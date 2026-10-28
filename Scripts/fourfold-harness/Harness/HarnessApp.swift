//  HarnessApp.swift — FOURFOLD simulator harness (Scripts/fourfold-harness/run.sh).
//  A throwaway host app that compiles the FourfoldAU sources and plays the AU's HOST for it: it supplies the transport / musical-context blocks, pulls the AU's render block from a 10 ms timer, and counts the MIDI notes the AU
//  sends per cable (All, A, B, C, D) — printed to the console every 2 s. It then shows `FourfoldRootView` (or, with `--reel`, the root view for 15 s and then the `FourfoldReelBrowser`). Nothing here ships.
//  It is an end-to-end check of the Fourfold sound path (document → FourfoldCompose → AU snapshot → Router → MIDI out) that needs no iPad and no AUM; Step 3's app shell grows out of the same idea.

import SwiftUI
import AVFoundation
import AudioToolbox
import Darwin

// MARK: - allocation watch (--alloc)
// The render path must not allocate (CLAUDE.md invariant 3). This hooks libmalloc's `malloc_logger` — the callback every malloc / free / realloc in the process goes through — and counts the ones made by the render block's own thread
// while `allocWatchThread` is set (the harness sets it around `renderBlock` and nowhere else). Everything here is preallocated plain memory: the hook itself must not allocate.
private let allocFrameDepth = 14, allocLogCap = 512
// All hook state is raw preallocated memory behind `let` pointers: a Debug build's exclusivity check on a global `var` allocates (swift_beginAccess → TLS context), which would re-enter this very hook.
private let allocState = UnsafeMutablePointer<Int>.allocate(capacity: 4)   // 0 watched mach thread (0 = off) · 1 allocations · 2 frees · 3 stacks logged
private let allocStacks = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: allocLogCap * allocFrameDepth)
private let allocSizes = UnsafeMutablePointer<UInt>.allocate(capacity: allocLogCap)
private let allocScratch = UnsafeMutablePointer<UnsafeMutableRawPointer?>.allocate(capacity: allocFrameDepth)

private let mallocHook: @convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void = { type, a1, a2, a3, result, skip in
    let st = allocState
    let me = st[0]
    guard me != 0, Int(pthread_mach_thread_np(pthread_self())) == me else { return }
    if type & 4 != 0 { st[2] += 1 }                                      // MALLOC_LOG_TYPE_DEALLOCATE (a realloc is both)
    if type & 2 != 0 {                                                    // MALLOC_LOG_TYPE_ALLOCATE
        st[1] += 1
        let logged = st[3]
        if logged < allocLogCap {
            st[0] = 0                                                     // backtrace() must not be counted (or recurse)
            let n = Int(backtrace(allocScratch, Int32(allocFrameDepth)))
            let base = logged * allocFrameDepth
            for i in 0..<allocFrameDepth { allocStacks[base + i] = i < n ? allocScratch[i] : nil }
            allocSizes[logged] = (type & 4 != 0) ? a3 : a2
            st[3] = logged + 1
            st[0] = me
        }
    }
}

enum AllocWatch {
    static func install() -> Bool {
        allocState.initialize(repeating: 0, count: 4)
        _ = backtrace(allocScratch, Int32(allocFrameDepth))               // warm backtrace's own lazy state
        guard let sym = dlsym(UnsafeMutableRawPointer(bitPattern: -2), "malloc_logger") else { return false }   // RTLD_DEFAULT
        sym.assumingMemoryBound(to: (@convention(c) (UInt32, UInt, UInt, UInt, UInt, UInt32) -> Void)?.self).pointee = mallocHook
        return true
    }
    static func begin() { allocState[0] = Int(pthread_mach_thread_np(pthread_self())) }
    static func end() { allocState[0] = 0 }
    static func reset() { allocState[1] = 0; allocState[2] = 0; allocState[3] = 0 }
    static var counts: (allocs: Int, frees: Int) { (allocState[1], allocState[2]) }
    /// One line per distinct allocating call stack: "xN size=… frame <- frame …" with raw symbol names (the script pipes them through swift-demangle).
    static func report(prefix: String) {
        var seen: [String: (Int, UInt, String)] = [:], order: [String] = []
        for i in 0..<allocState[3] {
            var names: [String] = [], offs: [String] = []
            for j in 0..<allocFrameDepth {
                guard let f = allocStacks[i * allocFrameDepth + j] else { break }
                var info = Dl_info()
                if dladdr(f, &info) != 0 {
                    names.append(info.dli_sname.map { String(cString: $0) } ?? "?")
                    // frames inside the harness's own image: offset from its load address, for `atos` (run.sh --alloc resolves them to file:line)
                    if let fname = info.dli_fname, String(cString: fname).contains("FFHarness"), let base = info.dli_fbase { offs.append(String(UInt(bitPattern: f) - UInt(bitPattern: base), radix: 16)) }
                } else { names.append("?") }
            }
            let key = names.dropFirst(2).prefix(9).joined(separator: " <- ")
            if let e = seen[key] { seen[key] = (e.0 + 1, e.1, e.2) } else { seen[key] = (1, allocSizes[i], offs.joined(separator: ",")); order.append(key) }
        }
        for k in order { fputs("\(prefix) STACK x\(seen[k]!.0) size=\(seen[k]!.1) OFFS=\(seen[k]!.2) \(k)\n", stderr) }
    }
}

/// A tiny emulated HOST: supplies the transport / musical-context blocks, receives the MIDI output blocks, and pulls the AU's render block from a timer.
final class Host {
    let sr = 48_000.0, tempo = 120.0
    var sampleTime: Float64 = 0
    var baseSample: Float64 = 0            // the beat is measured from here (a golden run restarts it per document)
    var hash: UInt64 = 0xcbf29ce484222325 // FNV-1a over every MIDI message the AU sends, for --golden
    var eventCount = 0
    var playing = true
    var onsPerCable = [Int](repeating: 0, count: FourfoldPorts.cableCount)
    var offsPerCable = [Int](repeating: 0, count: FourfoldPorts.cableCount)
    var firstOns: [(Int64, UInt8, UInt8)] = []
    let au: FourfoldAudioUnit
    let buf: AVAudioPCMBuffer
    var timer: Timer?
    var dumpName: String?    // --dump (with --golden): print every message as "DUMP <doc>\t<cable>\t<sample>\t<bytes>" so two engine versions can be compared event by event, not just by hash
    var watching = false     // --alloc: the MIDI block does nothing but count (the harness's own bookkeeping must not look like the AU's allocation)

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
            if self.watching { return noErr }
            func mix(_ v: UInt64) { self.hash = (self.hash ^ v) &* 0x100000001b3 }
            mix(UInt64(cable)); mix(UInt64(bitPattern: Int64(t) &- Int64(self.baseSample)))
            for i in 0..<len { mix(UInt64(bytes[i])) }
            if let d = self.dumpName { fputs("DUMP \(d)\t\(cable)\t\(Int64(t) &- Int64(self.baseSample))\t\((0..<len).map { String(bytes[$0], radix: 16) }.joined(separator: " "))\n", stderr) }
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
        let list = buf.mutableAudioBufferList, block = au.renderBlock
        if watching { AllocWatch.begin() }
        _ = block(&flags, &ts, frames, 0, list, nil)
        if watching { AllocWatch.end() }
        sampleTime += Double(frames)
    }
    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.01, repeats: true) { [unowned self] _ in self.render(480) }
        Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [unowned self] _ in
            print("HOST beat=\(String(format: "%.1f", self.sampleTime * self.tempo / 60 / self.sr)) ons per cable [All,RiffA,NotesA,RiffB,NotesB,RiffC,NotesC,RiffD,NotesD]=\(self.onsPerCable) offs=\(self.offsPerCable) firstA=\(self.firstOns.prefix(6).map { "\($0.1)@\($0.0)" })")
            let t = self.au.tapeStats()
            var tOn = [Int](repeating: 0, count: FourfoldPorts.cableCount), tOff = [Int](repeating: 0, count: FourfoldPorts.cableCount)
            for e in self.au.sessionTape.events(from: 0, to: Int.max) { if e.isOn { tOn[e.cable] += 1 } else { tOff[e.cable] += 1 } }
            print("DIAG panics=\(self.au.kernelDiagnostics().panics) stuckReason=\(self.au.kernelDiagnostics().stuckReason)")   // the engine's stuck-note self-heal count (see the 2026-10-25 status-log entry)
            print("TAPE notes ons per cable \(tOn) offs \(tOff)")
            print("TAPE events=\(t.events) dropped=\(t.dropped) passes=\(t.passes) complete=\(t.completePasses) endTick=\(t.endTick) resident=\(t.residentBytes / 1024)KiB")
        }
    }
}
extension Host {
    /// Publish the document the way FourfoldRootView.publish() does (from the AU's own getters).
    func publishDocument() {
        let input = FourfoldCompose.Input(lines: au.uiEuclideousLines(), riff: au.uiEuclideousRiff(), riffs: au.uiEuclideousRiffs(), activeRiff: au.uiEuclideousActiveRiff(),
                                          soloMask: au.uiEuclideousSoloMask(), locks: au.uiEuclideousLocks(), lockRevs: 0)
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
                if CommandLine.arguments.contains("--dump") { dumpName = name }
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

extension Host {
    /// The allocation audit: warm the default document unwatched (one-time lazy initialisation is not what this measures), then for the default document and every factory preset render 32 bars under a held chord with the allocation
    /// watch on around the render block only — including the transport-start edge and the stop edge — and print what the render thread allocated.
    func allocAudit() {
        timer?.invalidate()
        guard AllocWatch.install() else { fputs("ALLOC UNAVAILABLE: no malloc_logger symbol in this process\n", stderr); exit(2) }
        // the factory presets all read the KEY source, so the other note sources (CHORDS, MIDI IN with the held chord, MIDI IN + HOLD, + LATCH) are audited on the default document too
        // HOCKET (2026-10-27): two worst cases with every output in a lit rule — SWAP ROTATE over the riff outputs on HITS + a PASS ROTATE over the notes outputs on PASSES, and the same shapes on STEPS + BARS (a crossing)
        let sourceRuns = ["(default) CHORDS", "(default) CHORDS colours + borrowed", "(default) MIDI IN", "(default) MIDI IN + HOLD", "(default) MIDI IN + LATCH", "(default) MIDI IN + REPLAY",
                          "(default) HOCKET HITS+PASSES", "(default) HOCKET STEPS+BARS", "(default) HOCKET FANOUT", "(default) ROUTED"]
        var names = ["(default)"]; names += au.factoryPresetNames(); names += sourceRuns
        var totalAllocs = 0, totalFrees = 0, dirty = 0
        func step(_ i: Int) {
            if i == names.count {
                fputs("ALLOC ALL: documents=\(names.count) allocations=\(totalAllocs) frees=\(totalFrees) documentsThatAllocated=\(dirty)\n", stderr)
                exit(totalAllocs == 0 ? 0 : 1)
            }
            let name = names[i]
            watching = false
            playing = false; for _ in 0..<8 { render(480) }
            if name.hasPrefix("(default)") {
                au.resetToFreshInit()
                if name.contains("CHORDS") { au.editDocument { $0.euclideousNoteSource = .chords } }
                if name.contains("colours") {   // the CHORDS GRID ferry's 16-step progression with every colour and the four borrowed chords
                    au.editDocument {
                        var cfg = $0.euclideousChordSetsResolved[$0.activeChordSetResolved]
                        cfg.chordsSteps = 16
                        cfg.chordsDegrees = [0, 9, 3, 11, 4, 8, 10, 5, 0, 2, 7, 6, 1, 8, 9, 10]
                        cfg.chordsColours = [1, 2, 3, 4, 5, 6, 0, 1, 2, 3, 4, 5, 6, 0, 1, 2]
                        $0.setEuclideousChordSet($0.activeChordSetResolved, cfg)
                    }
                }
                if name.contains("MIDI IN") { au.editDocument { $0.euclideousNoteSource = .midi } }
                if name.contains("HOCKET HITS+PASSES") {
                    au.editDocument { $0.hocketRules = HocketRuleSet([
                        { var r = HocketRule(); r.main = [1]; r.alt = [3, 5, 7]; r.several = .rotate; r.mainLen = 3; r.altLen = 2; return r }(),
                        { var r = HocketRule(); r.mode = .pass; r.main = [2, 4]; r.alt = [6, 8]; r.several = .rotate; r.unit = .passes; r.own = .merge; return r }()]) }
                }
                if name.contains("HOCKET STEPS+BARS") {
                    au.editDocument { $0.hocketRules = HocketRuleSet([
                        { var r = HocketRule(); r.main = [1, 5]; r.alt = [3, 7]; r.unit = .steps; r.mainLen = 4; r.altLen = 3; r.offset = 2; return r }(),
                        { var r = HocketRule(); r.mode = .pass; r.main = [2, 6]; r.alt = [6, 2]; r.unit = .bars; r.own = .replace; return r }()]) }
                }
                if name.contains("HOCKET FANOUT") {   // one line to six ALT outputs on TOGETHER (the copies are appended to the hit's pitch set), and a second rule that fans a notes-layer pair out
                    au.editDocument { $0.hocketRules = HocketRuleSet([
                        { var r = HocketRule(); r.mode = .pass; r.main = [1]; r.alt = [3, 4, 5, 6, 7, 8]; r.own = .merge; r.mainLen = 1; r.altLen = 1; return r }(),
                        { var r = HocketRule(); r.mode = .pass; r.main = [2]; r.alt = [2]; r.unit = .steps; r.own = .merge; return r }()]) }
                }
                if name.contains("ROUTED") {   // CARD BACKS (2026-10-28): the routing worst case — every riff part on all four outputs, the notes parts on A+C or all four, lane 4's notes routed nowhere (drawn, never sent); the roll ring takes a record per strike
                    au.editDocument { var ls = $0.euclideousLinesResolved; for i in 0..<4 { ls[i].riffOutMask = 0x0F; ls[i].notesOutMask = i == 3 ? 0 : (i % 2 == 0 ? 0b0101 : 0x0F) }; $0.euclideousLines = ls }
                }
                if name.contains("HOLD") { au.editDocument { $0.euclideousHoldLatchMode = .hold } }
                if name.contains("LATCH") { au.editDocument { $0.euclideousHoldLatchMode = .latch } }
            } else { au.loadFactoryPreset(named: name) }
            publishDocument()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                for _ in 0..<8 { render(480) }
                baseSample = sampleTime
                hold([60, 64, 67]); playing = true
                if i == 0 || name.contains("HOCKET") || name.contains("ROUTED") { for _ in 0..<800 { render(480) }; playing = false; for _ in 0..<8 { render(480) }; baseSample = sampleTime; playing = true }   // an unwatched warm-up lap: Swift's one-time generic-metadata instantiation (the first use of each type) is not what this measures; HOCKET's types are first touched by its own scenarios   // the unwatched warm-up lap
                eventCount = 0; AllocWatch.reset(); watching = true
                for w in 0..<6400 {
                    if name.contains("REPLAY") {   // a pass replays from the middle of the run to three-quarters of it: the replay itself, the live engine running silently underneath, and the hand-back
                        if w == 3200, let p = au.reelPassNumbers().last(where: { $0 >= 0 }) { au.reelSelectPass(p) }
                        if w == 4800 { au.reelStopReplay() }
                    }
                    render(480)
                }
                playing = false; for _ in 0..<8 { render(480) }
                watching = false
                let (a, f) = AllocWatch.counts
                fputs("ALLOC \(name): events=\(eventCount) allocations=\(a) frees=\(f)\n", stderr)
                if a > 0 { dirty += 1; AllocWatch.report(prefix: "ALLOC \(name):") }
                totalAllocs += a; totalFrees += f
                release([60, 64, 67])
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
            if CommandLine.arguments.contains("--golden") || CommandLine.arguments.contains("--alloc") {
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
        if CommandLine.arguments.contains("--alloc") { DispatchQueue.main.async { host.allocAudit() }; return }
        host.start(); fputs("HOST started\n", stderr)
    }
    var body: some Scene { WindowGroup { Switcher() } }
}
