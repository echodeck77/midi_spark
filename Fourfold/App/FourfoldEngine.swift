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
    #if FOURFOLD_LINK   // ABLETON LINK is OFF until after release — see `Docs/standalone-plan.md` "Ableton Link" for the switch
    // ABLETON LINK (2026-10-24 ferry): whether `pump` should push `clock`'s tempo/isPlaying out to the
    // Link session each buffer — a THIRD atomic flag on this same mailbox, not a plain stored Bool,
    // for the identical reason `playing`/`tempo` already are: it's written from the main thread (the
    // LINK toggle) and read every render callback.
    private let linkActiveFlag = ManagedAtomic<Bool>(false)
    #endif
    var playing: Bool {
        get { playingFlag.load(ordering: .relaxed) }
        set { playingFlag.store(newValue, ordering: .relaxed) }
    }
    var tempo: Double {
        get { Double(bitPattern: tempoBits.load(ordering: .relaxed)) }
        set { tempoBits.store(newValue.bitPattern, ordering: .relaxed) }
    }
    #if FOURFOLD_LINK
    var linkActive: Bool {
        get { linkActiveFlag.load(ordering: .relaxed) }
        set { linkActiveFlag.store(newValue, ordering: .relaxed) }
    }
    #endif
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
    // IDLE RELEASE (2026-11-13): the engine + shared session are held ONLY while playing. A short grace keeps them warm across a rapid stop→start so we don't re-setup on every transport nudge.
    private var releaseWork: DispatchWorkItem?
    private static let stopGrace: TimeInterval = 2.0

    // ── audio-thread state (written only inside `pump`; the host blocks read it from within the AU's render call on the same thread) ──
    private var clock: FourfoldTransportClock
    private var sampleRate: Double
    private var lastSampleTime = 0.0
    private var bufferSample = 0.0
    private var bufferHost: UInt64 = 0
    private let timebase: (numer: UInt32, denom: UInt32)
    private let scratch: UnsafeMutableAudioBufferListPointer
    private let scratchData: [UnsafeMutablePointer<Float>]

    #if FOURFOLD_LINK
    // ABLETON LINK (2026-10-24 ferry): one ABLLinkRef for the app's lifetime, created alongside the
    // AVAudioEngine. `linkRef` is read/written from `pump` (the audio thread, via the audio-thread-safe
    // ABLLinkCapture/CommitAudioSessionState pair — "lockfree" per ABLLink.h, consistent with this
    // file's own no-locks/no-allocation render-path rule) AND exposed read-only to the app layer
    // (`link`) for the main-thread callback registration and the settings view controller, which use
    // the SEPARATE app-thread API (ABLLinkCapture/CommitAppSessionState) — never the audio-thread one.
    private var linkRef: ABLLinkRef?
    var link: ABLLinkRef? { linkRef }
    #endif

    private(set) var startError: String?

    init() throws {
        var tb = mach_timebase_info_data_t(); mach_timebase_info(&tb)
        timebase = (tb.numer, tb.denom)
        // IDLE RELEASE: launch builds the graph (so the kernel is live for the UI) but does NOT activate the session or start the engine — an open-but-stopped Fourfold must not anchor/degrade other apps' audio (the system-wide crackle). `ensureRunning()` claims the hardware on the first play; `scheduleRelease()` hands it back when stopped.
        let rate = Self.sessionSampleRate()
        sampleRate = rate
        clock = FourfoldTransportClock(sampleRate: rate)
        #if FOURFOLD_LINK
        linkRef = ABLLinkNew(clock.tempo)
        #endif
        au = try FourfoldAudioUnit(componentDescription: FourfoldAudioUnit.componentDescription, options: [])
        let tapeURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("Fourfold/Session/session.tape")
        if CommandLine.arguments.contains("--fresh") { try? FileManager.default.removeItem(at: tapeURL) }   // UI tests start from an empty reel, like the factory document
        au.useDurableTape(at: tapeURL)                                                                        // REEL PHASE 1d: the session survives a relaunch (before the engine starts)
        scratch = AudioBufferList.allocate(maximumBuffers: 2)
        scratchData = (0..<2).map { _ in
            let p = UnsafeMutablePointer<Float>.allocate(capacity: Int(Self.maxFrames)); p.initialize(repeating: 0, count: Int(Self.maxFrames)); return p
        }
        for i in 0..<2 { scratch[i] = AudioBuffer(mNumberChannels: 1, mDataByteSize: Self.maxFrames * 4, mData: scratchData[i]) }
        installHostBlocks()
        // Incoming MIDI is processed only while PLAYING (the engine renders only then — idle release). Dropping it when stopped also stops stale events queueing up and firing as stuck notes on the next play.
        midi.onInput = { [weak self] bytes, length in guard let self, self.mailbox.playing else { return }; self.au.scheduleMIDIEventBlock?(AUEventSampleTimeImmediate, 0, length, bytes) }
        try buildGraph()   // allocate the AU's render resources + the source node, but DON'T start the engine — the hardware is claimed lazily on the first play
        observe()
    }

    deinit {
        for o in observers { NotificationCenter.default.removeObserver(o) }
        engine.stop()
        Self.deactivateSession()   // don't leave the shared session active after the engine is gone
        if au.renderResourcesAllocated { au.deallocateRenderResources() }
        scratchData.forEach { $0.deallocate() }
        free(scratch.unsafeMutablePointer)
        #if FOURFOLD_LINK
        if let linkRef { ABLLinkDelete(linkRef) }
        #endif
    }

    func setPlaying(_ on: Bool) {
        mailbox.playing = on
        if on { ensureRunning() } else { scheduleRelease() }   // IDLE RELEASE: hold the hardware only while playing
    }
    func setTempo(_ bpm: Double) { mailbox.tempo = FourfoldTransportClock.clamped(bpm) }
    #if FOURFOLD_LINK
    /// ABLETON LINK: `ABLLinkSetActive` is a configuration call (advertise/connect), not a realtime
    /// one — called here on the caller's thread (the UI), same as `ABLLinkNew`'s own "active by
    /// default after init" is implicitly a main-thread-time call in every LinkKit sample. Also flips
    /// the mailbox flag `pump` reads, so the audio thread stops/starts pushing Fourfold's own tempo/
    /// isPlaying into the session the moment the user toggles LINK off/on.
    func setLinkActive(_ on: Bool) {
        mailbox.linkActive = on
        if let linkRef { ABLLinkSetActive(linkRef, on) }
    }
    #endif

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
        // NO preferred IO buffer: Fourfold is MIDI-only and its output is silence, so it has no latency need of its own — and forcing the
        // SHARED hardware buffer (it was 0.005 s) reconfigured the device's audio route, degrading every other app's audio (YouTube etc.)
        // until a restart. MIDI stays sample-accurate regardless: events carry their own host time (see `installHostBlocks` / `pump`), so the
        // render-buffer granularity never affects MIDI timing. Accept whatever buffer the system / the foreground audio app already set.
        try s.setActive(true)
    }
    /// Release the shared session on the way out, so a backgrounded-then-terminated instance never leaves a silent `.playback` session
    /// holding the audio route. `.notifyOthersOnDeactivation` lets a paused app resume. (Background MIDI still works while the app lives —
    /// `UIBackgroundModes: audio` keeps the session active until the app actually goes away.)
    private static func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
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
        #if FOURFOLD_LINK
        // ABLETON LINK (2026-10-24 ferry): push Fourfold's OWN tempo/isPlaying out to the session —
        // the audio-thread-safe capture/set-if-changed/commit dance ABLLink.h itself recommends
        // ("modifying Link session state should be done in the audio thread for the most accurate
        // timing"), gated on the mailbox flag so it's a complete no-op when LINK is off. The INCOMING
        // direction (a peer's tempo/isPlaying pulling Fourfold along) is main-thread callbacks
        // registered on `linkRef` by FourfoldAppModel, calling the SAME setTempo/setPlaying the UI
        // uses — not read here, so this stays one-directional and allocation-free.
        if let linkRef, mailbox.linkActive {
            let state = ABLLinkCaptureAudioSessionState(linkRef)
            if abs(ABLLinkGetTempo(state) - clock.tempo) > 0.0001 { ABLLinkSetTempo(state, clock.tempo, bufferHost) }
            if ABLLinkIsPlaying(state) != clock.playing { ABLLinkSetIsPlaying(state, clock.playing, bufferHost) }
            ABLLinkCommitAudioSessionState(linkRef, state)
        }
        #endif
        for i in 0..<2 { scratch[i].mDataByteSize = frameCount * 4 }
        var flags = AudioUnitRenderActionFlags()
        _ = render(&flags, &ts, frameCount, 0, scratch.unsafeMutablePointer, nil)
        return noErr
    }

    // MARK: - route changes, interruptions

    private func observe() {
        let nc = NotificationCenter.default
        // A config change (route/rate) matters only while we actually hold the hardware (playing). When released (idle) the engine isn't running, so there is nothing to rebuild — and we must NOT re-claim the route.
        observers.append(nc.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            guard let self, self.engine.isRunning else { return }
            self.rebuildAndRestart()
        })
        observers.append(nc.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt, AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            if let self, self.mailbox.playing { self.ensureRunning() }   // reclaim the session only if we're still meant to be playing
        })
        observers.append(nc.addObserver(forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main) { [weak self] _ in
            if let self, self.mailbox.playing, !self.engine.isRunning { self.ensureRunning() }   // playing-in-background then returning: make sure the engine is up; a stopped Fourfold stays released
        })
        // IDLE RELEASE: backgrounded while stopped → hand the shared route back AT ONCE (no grace), so another foreground app (YouTube etc.) gets the hardware cleanly. While playing we keep it (background MIDI keeps sequencing out).
        observers.append(nc.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, !self.mailbox.playing else { return }
            self.releaseNow()
        })
        // On termination, release the shared session so a dying instance doesn't hold the route (deinit isn't guaranteed on an OS kill; this covers the graceful-exit path).
        observers.append(nc.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in self?.releaseNow() })
    }

    // MARK: - IDLE RELEASE (2026-11-13): hold the shared audio hardware only while playing

    /// MAIN THREAD, on PLAY: claim the session + start the engine if they aren't already up. Rebuilds the graph only if the hardware rate changed (or it was never built) — so a normal play after a stop is just `start()`.
    private func ensureRunning() {
        releaseWork?.cancel(); releaseWork = nil
        guard !engine.isRunning else { return }
        do {
            try Self.configureSession()
            let rate = Self.sessionSampleRate()
            if rate != sampleRate || sourceNode == nil {
                clock.timelineWillRestart(lastSampleTime: lastSampleTime, newSampleRate: rate)
                sampleRate = rate
                try buildGraph()
            }
            try engine.start()
            startError = nil
        } catch { startError = "AUDIO ENGINE: \(error.localizedDescription)" }
    }

    /// A config change (route/rate) WHILE PLAYING: rebuild at the new rate and carry the beat over. The session stays active throughout (a route change doesn't deactivate it), so we don't re-`setActive` — which would churn the shared route.
    private func rebuildAndRestart() {
        engine.stop()
        do {
            let rate = Self.sessionSampleRate()
            clock.timelineWillRestart(lastSampleTime: lastSampleTime, newSampleRate: rate)
            sampleRate = rate
            try buildGraph()
            try engine.start()
            startError = nil
        } catch { startError = "AUDIO ENGINE: \(error.localizedDescription)" }
    }

    /// On STOP: release after a short grace, so a rapid stop→start stays warm. A play during the grace cancels it (`ensureRunning`).
    private func scheduleRelease() {
        releaseWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            guard let self, !self.mailbox.playing else { return }
            self.engine.stop()
            Self.deactivateSession()
        }
        releaseWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stopGrace, execute: w)
    }

    /// Release the hardware immediately (backgrounded-idle / termination).
    private func releaseNow() {
        releaseWork?.cancel(); releaseWork = nil
        engine.stop()
        Self.deactivateSession()
    }
}
