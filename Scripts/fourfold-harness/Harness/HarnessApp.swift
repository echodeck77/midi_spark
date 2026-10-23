//  HarnessApp.swift — FOURFOLD simulator harness (Scripts/fourfold-harness/run.sh).
//  A throwaway host app that compiles the FourfoldAU sources and plays the AU's HOST for it: it supplies the transport / musical-context blocks, pulls the AU's render block from a 10 ms timer, and counts the MIDI notes the AU
//  sends per cable (All, A, B, C, D) — printed to the console every 2 s. It then shows `FourfoldRootView` (or, with `--reel`, the root view for 15 s and then the `FourfoldReelBrowser`). Nothing here ships.
//  It is an end-to-end check of the Fourfold sound path (document → FourfoldCompose → AU snapshot → Router → MIDI out) that needs no iPad and no AUM; Step 3's app shell grows out of the same idea.

import SwiftUI
import AVFoundation
import AudioToolbox

/// A tiny emulated HOST: supplies the transport / musical-context blocks, receives the MIDI output blocks, and pulls the AU's render block from a timer.
final class Host {
    let sr = 48_000.0, tempo = 120.0
    var sampleTime: Float64 = 0
    var baseSample: Float64 = 0            // the beat is measured from here (a golden run restarts it per document)
    var hash: UInt64 = 0xcbf29ce484222325 // FNV-1a over every MIDI message the AU sends, for --golden
    var eventCount = 0
    var playing = true
    var onsPerCable = [Int](repeating: 0, count: 5)
    var offsPerCable = [Int](repeating: 0, count: 5)
    var firstOns: [(Int64, UInt8, UInt8)] = []
    let au: FourfoldAudioUnit
    let buf: AVAudioPCMBuffer
    var timer: Timer?

    init() {
        let d = AudioComponentDescription(componentType: kAudioUnitType_MIDIProcessor, componentSubType: 0x46726664, componentManufacturer: 0x4D53504B, componentFlags: 0, componentFlagsMask: 0)
        au = try! FourfoldAudioUnit(componentDescription: d, options: [])
        let fmt = AVAudioFormat(standardFormatWithSampleRate: sr, channels: 2)!
        buf = AVAudioPCMBuffer(pcmFormat: fmt, frameCapacity: 4096)!
        try? au.inputBusses[0].setFormat(fmt); try? au.outputBusses[0].setFormat(fmt)
        au.maximumFramesToRender = 4096
        au.transportStateBlock = { [unowned self] flags, _, _, _ in flags?.pointee = self.playing ? .moving : []; return true }
        au.musicalContextBlock = { [unowned self] bpm, tsNum, tsDen, beat, off, measure in
            bpm?.pointee = self.tempo; tsNum?.pointee = 4; tsDen?.pointee = 4
            let b = (self.sampleTime - self.baseSample) * self.tempo / 60.0 / self.sr
            beat?.pointee = b; off?.pointee = 0; measure?.pointee = (b / 4).rounded(.down) * 4
            return true
        }
        au.midiOutputEventBlock = { [unowned self] t, cable, len, bytes in
            self.eventCount += 1
            func mix(_ v: UInt64) { self.hash = (self.hash ^ v) &* 0x100000001b3 }
            mix(UInt64(cable)); mix(UInt64(bitPattern: Int64(t) &- Int64(self.baseSample)))
            for i in 0..<len { mix(UInt64(bytes[i])) }
            if len >= 3 {
                let st = bytes[0] & 0xF0
                if st == 0x90 && bytes[2] > 0 { self.onsPerCable[Int(cable)] += 1; if self.firstOns.count < 12 && cable == 1 { self.firstOns.append((t, bytes[1], bytes[2])) } }
                else if st == 0x80 || st == 0x90 { self.offsPerCable[Int(cable)] += 1 }
            }
            return noErr
        }
        try! au.allocateRenderResources()
    }
    func render(_ frames: UInt32) {
        var flags = AudioUnitRenderActionFlags()
        var ts = AudioTimeStamp(); ts.mSampleTime = sampleTime; ts.mFlags = .sampleTimeValid
        buf.frameLength = frames
        _ = au.renderBlock(&flags, &ts, frames, 0, buf.mutableAudioBufferList, nil)
        sampleTime += Double(frames)
    }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [unowned self] _ in self.render(480) }
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [unowned self] _ in
            print("HOST beat=\(String(format: "%.1f", self.sampleTime * self.tempo / 60 / self.sr)) ons per cable [All,A,B,C,D]=\(self.onsPerCable) offs=\(self.offsPerCable) firstA=\(self.firstOns.prefix(6).map { "\($0.1)@\($0.0)" })")
        }
    }
}
extension Host {
    /// Publish the document the way FourfoldRootView.publish() does (from the AU's own getters).
    func publishDocument() {
        let input = FourfoldCompose.Input(lines: au.uiEuclideousLines(), riff: au.uiEuclideousRiff(), riffs: au.uiEuclideousRiffs(), activeRiff: au.uiEuclideousActiveRiff(),
                                          mainOutMask: au.uiEuclideousMainOutMask(), soloMask: au.uiEuclideousSoloMask(), locks: au.uiEuclideousLocks(), lockRevs: 0)
        let chain = FourfoldCompose.chain(input)
        au.setBuildEphemeralMachines([(id: FourfoldCompose.machineID, machine: chain, transpose: 0)])
        au.setBuildStagingScene(FourfoldCompose.scene(chain: chain))
        au.setFreeRunEnabled(false)
    }
    func hold(_ notes: [UInt8]) { for n in notes { var m: [UInt8] = [0x90, n, 100]; au.scheduleMIDIEventBlock?(AUEventSampleTimeImmediate, 0, 3, &m) } }
    func release(_ notes: [UInt8]) { for n in notes { var m: [UInt8] = [0x80, n, 0]; au.scheduleMIDIEventBlock?(AUEventSampleTimeImmediate, 0, 3, &m) } }

    /// The regression oracle for engine changes: the default document and every factory preset, each rendered for 32 bars under a held C-major chord, hashing every MIDI byte the AU sends. Same hash = same sound.
    /// A chain of main-queue steps (load → publish → [let the AU rebuild its snapshot] → render), because the AU rebuilds on the main queue and a loop inside one block would starve it.
    func golden() {
        timer?.invalidate()
        var names = ["(default)"]; names += au.factoryPresetNames()
        var all: UInt64 = 0xcbf29ce484222325, total = 0
        func step(_ i: Int) {
            if i == names.count {
                fputs("GOLDEN ALL: documents=\(names.count) events=\(total) hash=\(String(all, radix: 16))\n", stderr)
                exit(0)
            }
            let name = names[i]
            playing = false; for _ in 0..<8 { render(480) }
            if name == "(default)" { au.resetToFreshInit() } else { au.loadFactoryPreset(named: name) }
            publishDocument()                                                      // schedules the snapshot rebuild on the main queue…
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in     // …which has run by now
                for _ in 0..<8 { render(480) }
                hash = 0xcbf29ce484222325; eventCount = 0; baseSample = sampleTime
                hold([60, 64, 67]); playing = true
                for _ in 0..<6400 { render(480) }                                  // 128 beats = 32 bars at 120 BPM
                playing = false; for _ in 0..<8 { render(480) }
                release([60, 64, 67])
                fputs("GOLDEN \(name): events=\(eventCount) hash=\(String(hash, radix: 16))\n", stderr)
                all = (all ^ hash) &* 0x100000001b3; total += eventCount
                DispatchQueue.main.async { step(i + 1) }
            }
        }
        step(0)
    }
}

let host = Host()

struct Switcher: View {
    @State var showReel = false
    var body: some View {
        Group {
            if CommandLine.arguments.contains("--golden") {
                Color.black         // golden mode: NO page — its 4 Hz poll edits the document (restart-chain pinning) and would race the steps below
            } else if showReel {
                GeometryReader { geo in FourfoldReelBrowser(au: host.au, size: geo.size, playing: true, tempo: 120, onClose: { showReel = false }) }
            } else {
                FourfoldRootView(au: host.au).ignoresSafeArea()
            }
        }
        .onAppear { if CommandLine.arguments.contains("--reel") { DispatchQueue.main.asyncAfter(deadline: .now() + 15) { showReel = true } } }
    }
}

@main struct HarnessApp: App {
    init() {
        setvbuf(stdout, nil, _IONBF, 0)
        if CommandLine.arguments.contains("--golden") { DispatchQueue.main.async { host.golden() }; return }
        host.start(); fputs("HOST started\n", stderr)
    }
    var body: some Scene { WindowGroup { Switcher() } }
}
