//  FourfoldEngine.swift
//  FOURFOLD Step 3 (2026-10-23, Docs/standalone-plan.md): the standalone app as the AU's SECOND HOST — the same blocks AUM supplies today, supplied by the app. ONE integration path (the AU class, built directly in-process; no
//  registration, no extension loading), never the Kernel itself.
//
//   · A silent AVAudioEngine SOURCE NODE is the sample-accurate render thread: its callback pulls the AU's render block with the buffer's own timestamp (the standard MIDI-app trick; also what lets iOS keep the app alive in the background).
//   · `FourfoldTransportClock` is the internal transport behind the `transportStateBlock` / `musicalContextBlock` (beat DERIVED from the render timeline); the UI reaches it only through `FourfoldTransportMailbox` (desired state, atomics).
//   · The AU's `midiOutputEventBlock` → `FourfoldMIDI.send`, each message stamped with the host time of its sample.
//   · CoreMIDI input → `scheduleMIDIEventBlock` (cable 0).
//  Everything on the audio thread is allocation-free: a preallocated scratch AudioBufferList, one clock value, and the CoreMIDI packet buffer.

import AVFoundation
import UIKit
import AudioToolbox
import Atomics

/// The UI's side of the transport: DESIRED state, read by the audio thread each buffer (level-triggered — see `FourfoldTransportClock.sync`).
final class FourfoldTransportMailbox {
    private let playingFlag = ManagedAtomic<Bool>(false)
    private let tempoBits = ManagedAtomic<UInt64>(Double(120).bitPattern)
    var playing: Bool {
        get { playingFlag.load(ordering: .relaxed) }
        set { playingFlag.store(newValue, ordering: .relaxed) }
    }
    var tempo: Double {
        get { Double(bitPattern: tempoBits.load(ordering: .relaxed)) }
        set { tempoBits.store(newValue.bitPattern, ordering: .relaxed) }
    }
}

final class FourfoldEngine {
    let au: FourfoldAudioUnit
    let midi = FourfoldMIDI()
    let mailbox = FourfoldTransportMailbox()

    private static let maxFrames: AVAudioFrameCount = 4096
    private let engine = AVAudioEngine()
    private var sourceNode: AVAudioSourceNode?
    private var renderBlock: AURenderBlock?
    private var observers: [NSObjectProtocol] = []

    // ── audio-thread state (written only inside `pump`; the host blocks read it from within the AU's render call on the same thread) ──
    private var clock: FourfoldTransportClock
    private var sampleRate: Double
    private var lastSampleTime = 0.0
    private var bufferSample = 0.0
    private var bufferHost: UInt64 = 0
    private let timebase: (numer: UInt32, denom: UInt32)
    private let scratch: UnsafeMutableAudioBufferListPointer
    private let scratchData: [UnsafeMutablePointer<Float>]

    private(set) var startError: String?

    init() throws {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        timebase = (tb.numer, tb.denom)
        try Self.configureSession()
        let rate = Self.sessionSampleRate()
        sampleRate = rate
        clock = FourfoldTransportClock(sampleRate: rate)
        au = try FourfoldAudioUnit(componentDescription: FourfoldAudioUnit.componentDescription, options: [])
        scratch = AudioBufferList.allocate(maximumBuffers: 2)
        scratchData = (0..<2).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: Int(Self.maxFrames)); p.initialize(repeating: 0, count: Int(Self.maxFrames)); return p
        }
        for i in 0..<2 { scratch[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: Self.maxFrames * 4, mData: scratchData[i]) }
        installHostBlocks()
        midi.onInput = { [weak au] bytes, length in au?.scheduleMIDIEventBlock?(AUEventSampleTimeImmediate, 0, length, bytes) }
        try buildGraph()
        try engine.start()
        observe()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        engine.stop()
        if au.renderResourcesAllocated { au.deallocateRenderResources() }
        scratchData.forEach { $0.deallocate() }
        free(scratch.unsafeMutablePointer)
    }

    func setPlaying(_ on: Bool) { mailbox.playing = on }
    func setTempo(_ bpm: Double) { mailbox.tempo = FourfoldTransportClock.clamped(bpm) }

    // MARK: - the host blocks (what AUM supplies)

    private func installHostBlocks() {
        au.transportStateBlock = { [unowned self] flags, _, _, _ in
            flags?.pointee = self.clock.playing ? .moving : []
            return true
        }
        au.musicalContextBlock = { [unowned self] bpm, tsNum, tsDen, beat, offsetToNextBeat, measureDownbeat in
            let b = self.clock.beat(at: self.bufferSample)
            bpm?.pointee = self.clock.tempo
            tsNum?.pointee = 4; tsDen?.pointee = 4
            beat?.pointee = b
            offsetToNextBeat?.pointee = self.clock.samplesToNextBeat(at: self.bufferSample)
            measureDownbeat?.pointee = (b / 4).rounded(.down) * 4
            return true
        }
        au.midiOutputEventBlock = { [unowned self] sampleTime, cable, length, bytes in
            let host = fourfoldHostTime(eventSample: sampleTime, baseSample: self.bufferSample, baseHost: self.bufferHost, sampleRate: self.sampleRate,
                                        numer: self.timebase.numer, denom: self.timebase.denom)
            self.midi.send(cable: Int(cable), bytes: bytes, length: length, hostTime: host)
            return noErr
        }
    }

    // MARK: - the graph

    private static func configureSession() throws {
        let s = AVAudioSession.sharedInstance()
        try s.setCategory(.playback, mode: .default, options: [.mixWithOthers])   // silent output, never ducks or stops another app's audio
        try? s.setPreferredIOBufferDuration(0.005)
        try s.setActive(true)
    }
    private static func sessionSampleRate() -> Double {
        let r = AVAudioSession.sharedInstance().sampleRate
        return r > 0 ? r : 48_000
    }

    /// (Re)build the AU's resources and the source node for the current session sample rate.
    private func buildGraph() throws {
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
        if au.renderResourcesAllocated { au.deallocateRenderResources() }
        try au.inputBusses[0].setFormat(fmt)
        try au.outputBusses[0].setFormat(fmt)
        au.maximumFramesToRender = Self.maxFrames
        try au.allocateRenderResources()
        renderBlock = au.renderBlock
        if let old = sourceNode { engine.detach(old) }
        let node = AVAudioSourceNode(format: fmt) { [unowned self] isSilence, timestamp, frameCount, output in
            self.pump(isSilence, timestamp, frameCount, output)
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
        sourceNode = node
        engine.prepare()
    }

    /// AUDIO THREAD: advance the internal transport to this buffer's start, then render the AU for it. The node's own output stays silent.
    private func pump(_ isSilence: UnsafeMutablePointer<ObjCBool>, _ timestamp: UnsafePointer<AudioTimeStamp>, _ frameCount: AVAudioFrameCount,
                      _ output: UnsafeMutablePointer<AudioBufferList>) -> OSStatus {
        isSilence.pointee = true
        for b in UnsafeMutableAudioBufferListPointer(output) { if let d = b.mData { memset(d, 0, Int(b.mDataByteSize)) } }
        guard let render = renderBlock, frameCount <= Self.maxFrames else { return noErr }
        var ts = timestamp.pointee
        let t = ts.mSampleTime
        lastSampleTime = t
        clock.sync(desiredPlaying: mailbox.playing, desiredTempo: mailbox.tempo, at: t)
        bufferSample = t
        bufferHost = ts.mFlags.contains(.hostTimeValid) ? ts.mHostTime : mach_absolute_time()
        for i in 0..<2 { scratch[i].mDataByteSize = frameCount * 4 }
        var flags = AudioUnitRenderActionFlags()
        _ = render(&flags, &ts, frameCount, 0, scratch.unsafeMutablePointer, nil)
        return noErr
    }

    // MARK: - route changes, interruptions

    private func observe() {
        let nc = NotificationCenter.default
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in self?.restart() })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            if let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: raw) == .ended { self?.restart() }
        })
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            if let self, !self.engine.isRunning { self.restart() }
        })
    }

    /// The engine stopped (route change, another app's interruption, a sample-rate change): rebuild at the session's rate and carry the beat over.
    func restart() {
        engine.stop()
        do {
            try Self.configureSession()
            let rate = Self.sessionSampleRate()
            clock.timelineWillRestart(lastSampleTime: lastSampleTime, newSampleRate: rate)
            sampleRate = rate
            try buildGraph()
            try engine.start()
            startError = nil
        } catch {
            startError = "AUDIO ENGINE: \(error.localizedDescription)"
        }
    }
}
