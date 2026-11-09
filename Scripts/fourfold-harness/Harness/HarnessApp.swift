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
        // `--octaves-keep` (MIDI IN OCTAVES ferry, 2026-11-01): force OCTAVES KEEP on whatever document was just loaded. The default is IGNORE, which folds the held chord and so changes every document's hash; KEEP must reproduce the pre-ferry
        // golden byte for byte (`diff Scripts/fourfold-harness/golden-keep.txt` against the run).
        if CommandLine.arguments.contains("--octaves-keep") { au.editDocument { var p = $0.sourcePlanResolved; p.midiOctaves = .keep; $0.euclideousSourcePlan = p } }
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
                goldenPoly()
                return
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
    /// POLY RIFF (2026-10-29): the documents that exercise the POLY riff, appended AFTER `GOLDEN ALL` so the 21 MONO lines above (and their ALL hash) stay the oracle for "MONO did not move". `POLY seeded` must equal `(default)`'s
    /// hash — the seed is the MONO riff twice over and the lane walks the whole grid, so the two modes play the same stream.
    func goldenPoly() {
        func lanes(_ ls: inout [EuclidLine], _ f: (inout EuclidLine, Int) -> Void) { for i in 0..<ls.count { f(&ls[i], i) } }
        let docs: [(String, (inout PluginState) -> Void)] = [
            ("POLY seeded", { s in s.polyRiff = EuclideousPolyRiff.seeded(from: s.riffsResolved[s.activeRiffResolved]); s.riffPoly = true;
                                  var ls = s.euclideousLinesResolved; lanes(&ls) { l, _ in l.riffLength = nil }; s.euclideousLines = ls }),
            ("POLY chords and long notes", { s in
                s.polyRiff = EuclideousPolyRiff(notes: (0..<16).flatMap { c in [EuclideousPolyNote(col: c, rank: c % 8 + 1, len: 1 + c % 5), EuclideousPolyNote(col: c, rank: (c * 3) % 8 + 1, len: 1 + c % 3)] }); s.riffPoly = true
                var ls = s.euclideousLinesResolved; lanes(&ls) { l, _ in l.riffOn = true; l.riffLength = nil }; s.euclideousLines = ls }),
            ("POLY walks", { s in
                s.polyRiff = EuclideousPolyRiff(notes: [(0, 1, 6), (0, 4, 2), (2, 6, 9), (5, 2, 3), (7, 8, 1), (9, 3, 7), (9, 5, 7), (12, 7, 4), (15, 1, 1)].map { EuclideousPolyNote(col: $0.0, rank: $0.1, len: $0.2) }); s.riffPoly = true
                var ls = s.euclideousLinesResolved
                lanes(&ls) { l, i in l.riffOn = true; l.riffLength = [16, 11, 16, 7][i]; l.riffAdvanceEvery = [1, 2, 3, 1][i]; l.riffDir = [.forward, .pendulum, .reverse, .pingpong][i]
                                     l.riffStride = [1, 1, 3, 5][i]; l.riffRotate = [0, 5, 9, 14][i]; l.riffAdvanceStep = i == 3 }
                s.euclideousLines = ls }),
            // REVERSE (2026-10-30): a REV walk strikes a held note at its LAST column. Every lane has hits here (the factory lanes 3 and 4 have none), three of them walk backward — one with ADV EVERY 2, one over a 12-column window with SHIFT 3 —
            // and the fourth walks forward as the control.
            ("POLY reverse", { s in
                s.polyRiff = EuclideousPolyRiff(notes: [(0, 1, 6), (2, 3, 14), (2, 6, 3), (8, 5, 5), (10, 2, 1), (12, 7, 4), (15, 4, 1)].map { EuclideousPolyNote(col: $0.0, rank: $0.1, len: $0.2) }); s.riffPoly = true
                var ls = s.euclideousLinesResolved
                lanes(&ls) { l, i in l.pulses = [9, 5, 7, 11][i]; l.steps = [16, 12, 16, 16][i]; l.riffOn = true; l.riffLength = [nil, 16, 12, nil][i]
                                     l.riffDir = [.reverse, .reverse, .reverse, .forward][i]; l.riffAdvanceEvery = [1, 2, 1, 1][i]; l.riffRotate = [0, 0, 3, 0][i] }
                s.euclideousLines = ls }),
            // PENDULUM / PING-PONG (2026-10-30): per hit, a note is struck at its first column going up, its last going down, and at a PENDULUM's turn by both ends. All four lanes have hits; the walks differ in LEN, EVERY, STRIDE and ADV.
            ("POLY pendulum and ping-pong", { s in
                s.polyRiff = EuclideousPolyRiff(notes: [(0, 1, 16), (1, 3, 5), (3, 6, 2), (6, 2, 7), (6, 5, 3), (9, 4, 1), (12, 7, 4), (13, 1, 3), (15, 8, 1)].map { EuclideousPolyNote(col: $0.0, rank: $0.1, len: $0.2) }); s.riffPoly = true
                var ls = s.euclideousLinesResolved
                lanes(&ls) { l, i in l.pulses = [9, 5, 7, 11][i]; l.steps = [16, 12, 16, 16][i]; l.riffOn = true; l.riffLength = [nil, 11, 16, 7][i]
                                     l.riffDir = [.pendulum, .pendulum, .pingpong, .pingpong][i]; l.riffAdvanceEvery = [1, 2, 1, 1][i]; l.riffStride = [1, 1, 3, 1][i]; l.riffAdvanceStep = i == 3 }
                s.euclideousLines = ls }),
        ]
        timer?.invalidate()
        var all: UInt64 = 0xcbf29ce484222325, total = 0
        func step(_ i: Int) {
            if i == docs.count {
                fputs("GOLDEN POLY ALL: documents=\(docs.count) events=\(total) hash=\(String(all, radix: 16))\n", stderr)
                goldenCanon()
                return
            }
            let (name, edit) = docs[i]
            playing = false; for _ in 0..<8 { render(480) }
            au.resetToFreshInit(); au.editDocument(edit)
            publishDocument()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                for _ in 0..<8 { render(480) }
                hash = 0xcbf29ce484222325; eventCount = 0; baseSample = sampleTime
                if CommandLine.arguments.contains("--dump") { dumpName = "POLY: " + name }
                hold([60, 64, 67]); playing = true
                for _ in 0..<6400 { render(480) }
                playing = false; for _ in 0..<8 { render(480) }
                release([60, 64, 67])
                fputs("GOLDEN POLY \(name): events=\(eventCount) hash=\(String(hash, radix: 16))\n", stderr)
                all = (all ^ hash) &* 0x100000001b3; total += eventCount
                DispatchQueue.main.async { step(i + 1) }
            }
        }
        step(0)
    }
}

/// The chords the harness's hand plays in the "changing" CANON documents: every 8 beats (400 renders of 480 frames) it lets go and presses the next — a delayed lane hears each change late, and the note-offs.
let canonHandChords: [[UInt8]] = [[60, 64, 67], [65, 69, 72], [67, 71, 74], [62, 65, 69]]
/// CHORD CANON (2026-10-31): a CHORDS progression that changes twice a bar through colours and the four borrowed chords, stacked ABOVE the held MIDI chord (so the delayed CHORDS layer meets the unshifted MIDI layer), and four
/// lanes with their own DELAY and SLIP. `shapes` gives the lanes the 5 · 7 · 11 · 16 step lengths (and a PING-PONG and a BKW) so the unit's own-lap rule is exercised; otherwise the lanes share 9/16 · 5/12 · 7/16 · 11/16.
/// (`slips` still sets the lanes' SLIP field — since the INPUTS ferry, 2026-11-06, the engine does not read it, so a document with slips plays as its slip-free twin: the CANON documents that use it changed by design.)
func canonDocument(_ s: inout PluginState, unit: CanonUnit, delays: [Int], slips: [Int], shapes: Bool = false, plan: SourcePlan? = nil) {
    s.euclideousSourcePlan = plan ?? SourcePlan(midiOn: true, chordsOn: true, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [])
    var cfg = s.euclideousChordSetsResolved[s.activeChordSetResolved]
    cfg.chordsSteps = 16
    cfg.chordsDegrees = [0, 9, 3, 11, 4, 8, 10, 5, 0, 2, 7, 6, 1, 8, 9, 10]
    cfg.chordsColours = [1, 2, 3, 4, 5, 6, 0, 1, 2, 3, 4, 5, 6, 0, 1, 2]
    cfg.chordsRate = .r1_2
    s.setEuclideousChordSet(s.activeChordSetResolved, cfg)
    s.euclideousCanonUnit = unit
    var ls = s.euclideousLinesResolved
    for i in 0..<4 {
        ls[i].pulses = (shapes ? [3, 4, 6, 9] : [9, 5, 7, 11])[i]; ls[i].steps = (shapes ? [5, 7, 11, 16] : [16, 12, 16, 16])[i]
        if shapes { ls[i].direction = [.fwd, .pingpong, .bkw, .fwd][i] }
        ls[i].riffOn = true
        ls[i].chordDelay = delays[i] == 0 ? nil : delays[i]; ls[i].chordSlip = slips[i] == 0 ? nil : slips[i]
    }
    s.euclideousLines = ls
}

extension Host {
    /// The CHORD CANON documents, appended AFTER `GOLDEN POLY ALL` so every line above stays the oracle for "nothing moved when no lane is delayed". ENTRY is left at its default (WRAP) — a dev setting a Release build ignores.
    func goldenCanon() {
        let allSources = SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: .add, pickNotes: [72, 76, 79])
        let docs: [(String, Bool, (inout PluginState) -> Void)] = [
            ("CANON control, no delays", false, { s in canonDocument(&s, unit: .passes, delays: [0, 0, 0, 0], slips: [0, 0, 0, 0]) }),   // the same CHORDS document with every DELAY and SLIP at 0: the delayed documents below must NOT hash like this one
            ("CANON passes", false, { s in canonDocument(&s, unit: .passes, delays: [0, 1, 2, 3], slips: [0, 0, 0, 0]) }),
            ("CANON bars and slip", false, { s in canonDocument(&s, unit: .bars, delays: [0, 1, 2, 4], slips: [0, 10, 20, 30]) }),
            ("CANON steps", false, { s in canonDocument(&s, unit: .steps, delays: [0, 3, 5, 8], slips: [5, 0, 15, 50]) }),
            ("CANON lanes of 5 7 11 16", false, { s in canonDocument(&s, unit: .passes, delays: [1, 1, 1, 1], slips: [0, 10, 0, 20], shapes: true) }),
            // ALL SOURCES (2026-10-31): the delayed lanes now hear incoming MIDI, PICK and KEY as well. The hand changes chord every 8 beats (the lanes hear each change a unit late — and the note-off in between).
            ("CANON MIDI IN, a hand changing chords", true, { s in canonDocument(&s, unit: .bars, delays: [0, 1, 2, 4], slips: [0, 0, 0, 0], plan: SourcePlan(midiOn: true, chordsOn: false, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [])) }),
            ("CANON MIDI IN with slip, lanes of 5 7 11 16", true, { s in canonDocument(&s, unit: .passes, delays: [1, 1, 2, 3], slips: [0, 10, 25, 50], shapes: true, plan: SourcePlan(midiOn: true, chordsOn: false, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [])) }),
            ("CANON every source", true, { s in canonDocument(&s, unit: .bars, delays: [0, 1, 2, 3], slips: [0, 15, 0, 30], plan: allSources) }),
            ("CANON MIDI replaces chords", true, { s in canonDocument(&s, unit: .bars, delays: [0, 1, 2, 3], slips: [0, 0, 5, 0], plan: SourcePlan(midiOn: true, chordsOn: true, pickOn: false, keyOn: true, midiMode: .replace, pickNotes: [])) }),
        ]
        timer?.invalidate()
        var all: UInt64 = 0xcbf29ce484222325, total = 0
        func step(_ i: Int) {
            if i == docs.count {
                fputs("GOLDEN CANON ALL: documents=\(docs.count) events=\(total) hash=\(String(all, radix: 16))\n", stderr)
                goldenOctaves()
                return
            }
            let (name, handChanges, edit) = docs[i]
            playing = false; for _ in 0..<8 { render(480) }
            au.resetToFreshInit(); au.editDocument(edit)
            publishDocument()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                for _ in 0..<8 { render(480) }
                hash = 0xcbf29ce484222325; eventCount = 0; baseSample = sampleTime
                if CommandLine.arguments.contains("--dump") { dumpName = "CANON: " + name }
                hold([60, 64, 67]); playing = true
                var held = 0
                for r in 0..<6400 {
                    if handChanges, r > 0, r % 400 == 0 { release(canonHandChords[held % canonHandChords.count]); held += 1; hold(canonHandChords[held % canonHandChords.count]) }   // the hand lets go and presses the next chord
                    render(480)
                }
                playing = false; for _ in 0..<8 { render(480) }
                release(canonHandChords[held % canonHandChords.count])
                release([60, 64, 67])
                fputs("GOLDEN CANON \(name): events=\(eventCount) hash=\(String(hash, radix: 16))\n", stderr)
                all = (all ^ hash) &* 0x100000001b3; total += eventCount
                DispatchQueue.main.async { step(i + 1) }
            }
        }
        step(0)
    }
}

/// MIDI IN OCTAVES / ROOT (2026-11-01): the hands. `octavesHandInversions` are high inversions of a C-major triad then three other chords (the fold must bring them all down to KEY's base octave); `rootHandNotes` one low note every 8
/// beats (the ROOT transpose: C2 = −12, G1 = −17, C3 = 0, G3 = +7 raw semitones from the base C).
let octavesHandInversions: [[UInt8]] = [[76, 79, 84], [77, 81, 84], [79, 83, 86], [74, 77, 81]]
let rootHandNotes: [[UInt8]] = [[50], [43], [48], [55]]

extension Host {
    /// The MIDI IN OCTAVES / ROOT documents, appended AFTER `GOLDEN CANON ALL` so every line above stays the oracle for "nothing else moved". With `--octaves-keep` the OCTAVES documents sound as KEEP (not IGNORE) — and the three ROOT documents
    /// must hash IDENTICALLY with and without it: ROOT's transpose is raw under both settings and ROOT admits no played note. NOTE (found 2026-11-01): the harness chains engine state from one document to the next, so a document's hash depends on
    /// its POSITION in the run (the same document run twice in a row hashes differently; every run of the same list reproduces exactly) — the order of this list is part of the oracle, and adding or moving a document re-derives the lines after it.
    func goldenOctaves() {
        func plan(_ chords: Bool, _ key: Bool, _ mode: MidiMode, _ octaves: MidiOctaves?, pick: [UInt8] = []) -> SourcePlan {
            SourcePlan(midiOn: true, chordsOn: chords, pickOn: !pick.isEmpty, keyOn: key, midiMode: mode, pickNotes: pick, midiOctaves: octaves)
        }
        let docs: [(String, [[UInt8]], (inout PluginState) -> Void)] = [
            ("MIDI alone, high inversions", octavesHandInversions, { s in s.euclideousSourcePlan = plan(false, false, .add, nil) }),
            ("MIDI alone KEEP, high inversions", octavesHandInversions, { s in s.euclideousSourcePlan = plan(false, false, .add, .keep) }),
            ("MIDI + KEY, high inversions", octavesHandInversions, { s in s.euclideousSourcePlan = plan(false, true, .add, nil) }),
            ("MIDI + CHORDS, high inversions", octavesHandInversions, { s in canonDocument(&s, unit: .bars, delays: [0, 0, 0, 0], slips: [0, 0, 0, 0], plan: plan(true, false, .add, nil)) }),
            ("REPLACE over CHORDS + KEY, high inversions", octavesHandInversions, { s in canonDocument(&s, unit: .bars, delays: [0, 0, 0, 0], slips: [0, 0, 0, 0], plan: plan(true, true, .replace, nil)) }),
            ("ROOT over CHORDS + KEY, a low note", rootHandNotes, { s in canonDocument(&s, unit: .bars, delays: [0, 0, 0, 0], slips: [0, 0, 0, 0], plan: plan(true, true, .root, nil)) }),
            ("ROOT over CHORDS + KEY + PICK KEEP, a low note", rootHandNotes, { s in canonDocument(&s, unit: .bars, delays: [0, 0, 0, 0], slips: [0, 0, 0, 0], plan: plan(true, true, .root, .keep, pick: [72, 76, 79])) }),
            ("ROOT with delayed lanes", rootHandNotes, { s in canonDocument(&s, unit: .bars, delays: [0, 1, 2, 4], slips: [0, 10, 20, 30], plan: plan(true, true, .root, nil)) }),
        ]
        timer?.invalidate()
        var all: UInt64 = 0xcbf29ce484222325, total = 0
        func step(_ i: Int) {
            if i == docs.count {
                fputs("GOLDEN OCTAVES ALL: documents=\(docs.count) events=\(total) hash=\(String(all, radix: 16))\n", stderr)
                goldenAnswer()
                return
            }
            let (name, hand, edit) = docs[i]
            playing = false; for _ in 0..<8 { render(480) }
            au.resetToFreshInit(); au.editDocument(edit)
            publishDocument()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                for _ in 0..<8 { render(480) }
                hash = 0xcbf29ce484222325; eventCount = 0; baseSample = sampleTime
                if CommandLine.arguments.contains("--dump") { dumpName = "OCTAVES: " + name }
                var held = 0
                hold(hand[0]); playing = true
                for r in 0..<6400 {
                    if r > 0, r % 400 == 0 { release(hand[held % hand.count]); held += 1; hold(hand[held % hand.count]) }   // the hand lets go and presses the next
                    render(480)
                }
                playing = false; for _ in 0..<8 { render(480) }
                release(hand[held % hand.count])
                fputs("GOLDEN OCTAVES \(name): events=\(eventCount) hash=\(String(hash, radix: 16))\n", stderr)
                all = (all ^ hash) &* 0x100000001b3; total += eventCount
                DispatchQueue.main.async { step(i + 1) }
            }
        }
        step(0)
    }
}

/// ANSWER ferry (2026-11-02): the default document's four lanes with rows, CYCLE flags and TRADE set. `variant` picks the shape (see `goldenAnswer`); the lanes keep the default document's own rhythms and riff, so every difference is the ferry's.
/// POOL ferry (2026-11-02): per-lane SOURCES masks (MIDI IN + CHORDS · CHORDS + KEY · PICK · all) (SUSTAIN on every lane was part of it until the INPUTS ferry, 2026-11-06, removed the stage). `plan` writes the page plan too (REPLACE with all four sources on and PICK notes).
/// TWO CHORD GRIDS (2026-11-03): `grid2` puts three lanes on CHORDS 2 (MIDI IN + CHORDS 2 · CHORDS 2 + KEY · CHORDS 2 alone) and leaves lane 4 on CHORDS 1, and gives grid 2 its own 16-step progression with colours and borrowed chords on a
/// different clock — so the per-lane build and the canon read both run on the second grid.
func poolDocument(_ s: inout PluginState, plan: Bool, grid2: Bool = false) {
    if plan { s.euclideousSourcePlan = SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: .replace, pickNotes: [72, 76, 79], midiOctaves: .keep) }
    var ls = s.euclideousLinesResolved
    var masks: [UInt8?] = [0b0011, 0b1010, 0b0100, nil]
    if grid2 {
        masks = [0b10001, 0b11000, 0b10000, nil]
        var g = MachineParams()
        g.chordsSteps = 16; g.chordsDegrees = [1, 8, 2, 10, 5, 9, 11, 3, 6, 0, 4, 7, 1, 9, 10, 8]
        g.chordsColours = [2, 3, 1, 4, 6, 5, 0, 2, 3, 4, 1, 5, 6, 0, 2, 1]; g.chordsRate = .r1_4
        s.setEuclideousChordSet(1, g)
    }
    for i in 0..<4 { ls[i].poolSrcMask = masks[i] }
    s.euclideousLines = ls
}
func answerDocument(_ s: inout PluginState, _ variant: Int) {
    var ls = s.euclideousLinesResolved
    for i in 0..<4 { ls[i].riffOn = true }
    ls[1].listenSource = 0; ls[2].listenSource = 0; ls[3].listenSource = 1; ls[0].listenSource = 2
    func rhythm(_ i: Int, _ m: EuclideousAnswerRhythmMode, cycle: Bool) { ls[i].answerRhythmOn = true; ls[i].answerRhythmMode = m; ls[i].answerRhythmCycle = cycle }
    func pitch(_ i: Int, _ m: EuclideousAnswerPitchMode, cycle: Bool) { ls[i].answerPitchOn = true; ls[i].answerPitchMode = m; ls[i].answerPitchCycle = cycle }
    func cycle(_ i: Int, each: Int, _ u: EuclideousAnswerCycleUnit) { ls[i].answerCycleEach = each; ls[i].answerCycleUnit = u }
    switch variant {
    case 0:   // every row OFF with the remembered modes, CYCLE flags, WITH and EACH / UNIT all stored: nothing may sound different from a document that never had them
        for i in 0..<4 { ls[i].answerRhythmMode = .fill; ls[i].answerRhythmCycle = true; ls[i].answerPitchMode = .avoid; ls[i].answerPitchCycle = true; ls[i].answerTradeMode = .borrow; ls[i].answerTradeWith = (i + 1) % 4; cycle(i, each: 3, .passes) }
    case 1:   // PITCH SHADOW with CYCLE (lane 2, 2 bars) and RHYTHM COPY with CYCLE (lane 3, 1 bar)
        pitch(1, .shadow, cycle: true); cycle(1, each: 2, .bars); rhythm(2, .copy, cycle: true); cycle(2, each: 1, .bars)
    case 2:   // PASSES: FILL with CYCLE counting the source's passes, AVOID with CYCLE
        rhythm(1, .fill, cycle: true); cycle(1, each: 2, .passes); pitch(2, .avoid, cycle: true); cycle(2, each: 3, .passes)
    case 3:   // BORROW (lane 4 ← lane 2, 2 bars) beside a rhythm that is not cycling
        ls[3].answerTradeOn = true; ls[3].answerTradeMode = .borrow; ls[3].answerTradeWith = 1; cycle(3, each: 2, .bars); rhythm(2, .copy, cycle: false)
    case 4:   // SWAP lanes 1 and 3 (4 bars), BORROW lane 4 ← lane 2 in PASSES
        for (i, w) in [(0, 2), (2, 0)] { ls[i].answerTradeOn = true; ls[i].answerTradeMode = .swap; ls[i].answerTradeWith = w; cycle(i, each: 4, .bars) }
        ls[3].answerTradeOn = true; ls[3].answerTradeMode = .borrow; ls[3].answerTradeWith = 1; cycle(3, each: 2, .passes)
    case 6:   // COPY / FILL followers that play a whole 2n lap (2026-11-07: a follower plays what its source plays): lane 1 COPY and lane 2 FILL of a PING-PONG lane 0, lane 3 FILL of lane 1 (a follower of a follower is not a source: it plays its own pattern)
        ls[0].direction = .pingpong; ls[0].pulses = 5; ls[0].steps = 8
        rhythm(1, .copy, cycle: false); rhythm(2, .fill, cycle: false); ls[2].listenDirection = .bkw
    default:  // every row on, cycling rows and a trade on the same lane
        rhythm(1, .copy, cycle: true); pitch(1, .shadow, cycle: true); ls[1].answerTradeOn = true; ls[1].answerTradeMode = .borrow; ls[1].answerTradeWith = 3; cycle(1, each: 2, .bars)
        pitch(2, .avoid, cycle: false); rhythm(3, .fill, cycle: false)
    }
    s.euclideousLines = ls
}

extension Host {
    /// The ANSWER documents, appended AFTER `GOLDEN OCTAVES ALL` so every line above stays the oracle for "nothing moved when no ANSWER row is on" (and document 0 is that case again, with the fields stored). The order of this list is part of the oracle.
    func goldenAnswer() {
        let docs: [(String, (inout PluginState) -> Void)] = [
            ("ANSWER every row off, fields stored", { s in answerDocument(&s, 0) }),
            ("ANSWER PITCH + RHYTHM cycles in bars", { s in answerDocument(&s, 1) }),
            ("ANSWER cycles in passes", { s in answerDocument(&s, 2) }),
            ("ANSWER BORROW", { s in answerDocument(&s, 3) }),
            ("ANSWER SWAP + BORROW", { s in answerDocument(&s, 4) }),
            ("ANSWER cycling rows + a trade on one lane", { s in answerDocument(&s, 5) }),
        ]
        timer?.invalidate()
        var all: UInt64 = 0xcbf29ce484222325, total = 0
        func step(_ i: Int) {
            if i == docs.count {
                fputs("GOLDEN ANSWER ALL: documents=\(docs.count) events=\(total) hash=\(String(all, radix: 16))\n", stderr)
                goldenInputs()
                return
            }
            let (name, edit) = docs[i]
            playing = false; for _ in 0..<8 { render(480) }
            au.resetToFreshInit(); au.editDocument(edit)
            publishDocument()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                for _ in 0..<8 { render(480) }
                hash = 0xcbf29ce484222325; eventCount = 0; baseSample = sampleTime
                if CommandLine.arguments.contains("--dump") { dumpName = "ANSWER: " + name }
                hold([60, 64, 67]); playing = true
                for _ in 0..<6400 { render(480) }
                playing = false; for _ in 0..<8 { render(480) }
                release([60, 64, 67])
                fputs("GOLDEN ANSWER \(name): events=\(eventCount) hash=\(String(hash, radix: 16))\n", stderr)
                all = (all ^ hash) &* 0x100000001b3; total += eventCount
                DispatchQueue.main.async { step(i + 1) }
            }
        }
        step(0)
    }
}

extension Host {
    /// INPUTS + HARMONY ferry (2026-11-06): each lane's own MIDI mode (ADD · REPLACE · ROOT) under the low-note hand of the OCTAVES documents, appended AFTER `GOLDEN ANSWER ALL` so every line above stays the oracle for "nothing else moved" (the CANON documents
    /// that set SLIP and the ROOT-with-delayed-lanes document changed by design in this ferry: SLIP is no longer read). The chips are the lanes' own (`poolSrcMask`); the page plan has every switch on, as a migrated document does.
    func goldenInputs() {
        func lanes(_ s: inout PluginState, modes: [MidiMode?], masks: [UInt8?] = [nil, nil, nil, nil]) {
            var ls = s.euclideousLinesResolved
            for i in 0..<4 { ls[i].midiMode = modes[i]; ls[i].poolSrcMask = masks[i] }
            s.euclideousLines = ls
        }
        func plan(_ mode: MidiMode) -> SourcePlan { SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: mode, pickNotes: [72, 76, 79], midiOctaves: .keep) }
        let docs: [(String, (inout PluginState) -> Void)] = [
            ("INPUTS ADD, REPLACE, ROOT and a lane without MIDI IN", { s in canonDocument(&s, unit: .bars, delays: [0, 0, 0, 0], slips: [0, 0, 0, 0], plan: plan(.add)); lanes(&s, modes: [.add, .replace, .root, .add], masks: [nil, nil, nil, 0b01110]) }),
            ("INPUTS every lane ROOT, delayed lanes", { s in canonDocument(&s, unit: .bars, delays: [0, 1, 2, 4], slips: [0, 0, 0, 0], plan: plan(.add)); lanes(&s, modes: [.root, .root, .root, .root]) }),
            ("INPUTS the document's REPLACE with one lane in ADD", { s in canonDocument(&s, unit: .bars, delays: [0, 0, 0, 0], slips: [0, 0, 0, 0], plan: plan(.replace)); lanes(&s, modes: [nil, .add, nil, nil]) }),
            ("INPUTS REPLACE and ROOT on the second chord grid", { s in
                canonDocument(&s, unit: .bars, delays: [0, 0, 1, 0], slips: [0, 0, 0, 0], plan: plan(.add)); poolDocument(&s, plan: false, grid2: true)
                lanes(&s, modes: [.replace, .root, .add, .root], masks: [0b10001, 0b11000, 0b10001, 0b10011]) }),
        ]
        timer?.invalidate()
        var all: UInt64 = 0xcbf29ce484222325, total = 0
        func step(_ i: Int) {
            if i == docs.count {
                fputs("GOLDEN INPUTS ALL: documents=\(docs.count) events=\(total) hash=\(String(all, radix: 16))\n", stderr)
                exit(0)
            }
            let (name, edit) = docs[i]
            playing = false; for _ in 0..<8 { render(480) }
            au.resetToFreshInit(); au.editDocument(edit)
            publishDocument()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                for _ in 0..<8 { render(480) }
                hash = 0xcbf29ce484222325; eventCount = 0; baseSample = sampleTime
                if CommandLine.arguments.contains("--dump") { dumpName = "INPUTS: " + name }
                var held = 0
                hold(rootHandNotes[0]); playing = true
                for r in 0..<6400 {
                    if r > 0, r % 400 == 0 { release(rootHandNotes[held % rootHandNotes.count]); held += 1; hold(rootHandNotes[held % rootHandNotes.count]) }
                    render(480)
                }
                playing = false; for _ in 0..<8 { render(480) }
                release(rootHandNotes[held % rootHandNotes.count])
                fputs("GOLDEN INPUTS \(name): events=\(eventCount) hash=\(String(hash, radix: 16))\n", stderr)
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
                          "(default) HOCKET HITS+PASSES", "(default) HOCKET STEPS+BARS", "(default) HOCKET FANOUT", "(default) POLY", "(default) POLY + HOCKET FANOUT", "(default) CANON", "(default) CANON shapes + HOCKET FANOUT", "(default) INPUTS lane modes hand", "(default) INPUTS ROOT delayed hand", "(default) CANON MIDI IN hand", "(default) CANON every source hand", "(default) ROUTED", "(default) ROUTED + OUT-TRANSPOSE", "(default) ROUTED + EMITTER RATCHETS", "(default) ROUTED + EMITTER VELOCITY", "(default) HOCKET FANOUT + EMITTER RATCHETS", "(default) MIDI IN KEEP", "(default) ROOT hand", "(default) ROOT hand delayed", "(default) ANSWER cycles", "(default) ANSWER COPY of a PING-PONG source", "(default) ANSWER SWAP + BORROW", "(default) ANSWER every row + HOCKET FANOUT + ROUTED", "(default) POOL SOURCES + SUSTAIN hand", "(default) POOL SUSTAIN + CANON every source hand", "(default) POOL grid 2 SOURCES + SUSTAIN hand", "(default) POOL grid 2 SUSTAIN + CANON every source hand", "(default) RESTART UNITS riff-first + isorhythm", "(default) RESTART UNITS cross-lane + WITH RHYTHM", "(default) RESTART UNITS WITH RHYTHM rhythm off", "(default) PART SOLO changing", "(default) PLAY AS SEQUENCE", "(default) EMITTER CC", "(default) OUTPUT MUTE"]
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
                if name.contains("MIDI IN KEEP") { au.editDocument { $0.euclideousSourcePlan = SourcePlan(midiOn: true, chordsOn: false, pickOn: false, keyOn: true, midiMode: .add, pickNotes: [], midiOctaves: .keep) } }   // MIDI IN OCTAVES (2026-11-01): the default is IGNORE (the fold runs in every "MIDI IN" scenario above); KEEP is the pass-through
                if name.contains("ROOT hand") {   // MIDI IN ROOT (2026-11-01): the hand's lowest note transposes a CHORDS + KEY pool; with delayed lanes in the second run (the canon merge folds / moves at read time)
                    let delays = name.contains("delayed") ? [0, 1, 2, 4] : [0, 0, 0, 0]
                    au.editDocument { canonDocument(&$0, unit: .bars, delays: delays, slips: [0, 0, 0, 0], plan: SourcePlan(midiOn: true, chordsOn: true, pickOn: false, keyOn: true, midiMode: .root, pickNotes: [])) }
                }
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
                if name.contains("POLY") {   // POLY RIFF (2026-10-29): the 16-column walk with chords, overlaps and every direction / EVERY, on top of the HOCKET fan-out in the second run (the per-pitch ring lengths follow the remap's copies)
                    au.editDocument {
                        $0.polyRiff = EuclideousPolyRiff(notes: (0..<16).flatMap { c in [EuclideousPolyNote(col: c, rank: c % 8 + 1, len: 1 + c % 5), EuclideousPolyNote(col: c, rank: (c * 3) % 8 + 1, len: 1 + c % 3)] }); $0.riffPoly = true
                        var ls = $0.euclideousLinesResolved
                        for i in 0..<4 { ls[i].riffOn = true; ls[i].riffLength = nil; ls[i].riffAdvanceEvery = [1, 2, 1, 3][i]; ls[i].riffDir = [.forward, .pendulum, .reverse, .pingpong][i] }
                        $0.euclideousLines = ls
                    }
                }
                if name.contains("CANON MIDI IN") {   // ALL SOURCES (2026-10-31): incoming MIDI only (the held chord changes every 8 beats below) — the history ring records, the delayed lanes read it back
                    au.editDocument { canonDocument(&$0, unit: .bars, delays: [1, 2, 3, 8], slips: [0, 10, 25, 50], plan: SourcePlan(midiOn: true, chordsOn: false, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [])) }
                } else if name.contains("CANON every source") {   // MIDI IN + CHORDS + PICK + KEY stacked, the hand changing chord
                    au.editDocument { canonDocument(&$0, unit: .passes, delays: [1, 2, 3, 8], slips: [0, 10, 25, 50], shapes: true, plan: SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: .add, pickNotes: [72, 76, 79])) }
                }
                if name.contains("CANON") {   // CHORD CANON (2026-10-31): every lane delayed and slipping (the per-lane pool re-merge on every chord step, the slip roll), the 5 · 7 · 11 · 16 lap lengths in the second run — on top of the HOCKET fan-out there
                    au.editDocument { canonDocument(&$0, unit: name.contains("shapes") ? .passes : .bars, delays: [1, 2, 3, 8], slips: [0, 10, 25, 50], shapes: name.contains("shapes")) }
                }
                if name.contains("INPUTS") {   // INPUTS + HARMONY (2026-11-06): each lane runs the stacked pool with its own chips and MIDI mode (ADD · REPLACE · ROOT + a lane without MIDI IN; every source on, PICK notes, OCTAVES IGNORE); the second run delays the lanes (the canon merge under ROOT / REPLACE)
                    let delayed = name.contains("delayed")
                    au.editDocument { s in
                        canonDocument(&s, unit: .bars, delays: delayed ? [0, 1, 2, 4] : [0, 0, 0, 0], slips: [0, 0, 0, 0], plan: SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: .add, pickNotes: [72, 76, 79]))
                        var ls = s.euclideousLinesResolved
                        let modes: [MidiMode?] = delayed ? [.root, .root, .replace, .root] : [.add, .replace, .root, .add]
                        for i in 0..<4 { ls[i].midiMode = modes[i]; ls[i].poolSrcMask = (!delayed && i == 3) ? 0b01110 : nil }
                        s.euclideousLines = ls
                    }
                }
                if name.contains("POOL") { au.editDocument { poolDocument(&$0, plan: !name.contains("CANON"), grid2: name.contains("grid 2")) } }   // POOL ferry (2026-11-02): per-lane sources + SUSTAIN on every lane; the pedal is driven below (CC64 down at 100, up at 300 of every 400 windows)
                if name.contains("RESTART UNITS") {   // RESTART UNITS (2026-11-04): the schedule's readers on the render path — A: lane 1 rhythm RIFF of itself, lane 2 melody HIT [3] with a RIFF rhythm, lanes 3–4 plain; B: a cross-lane ring (rhythm PASS of the next lane) with WITH RHYTHM and a melody PASS of another lane
                    let crossLane = name.contains("cross-lane"), loopOnly = name.contains("rhythm off")
                    au.editDocument {
                        var ls = $0.euclideousLinesResolved
                        for i in 0..<4 { ls[i].riffOn = true; ls[i].pulses = [3, 5, 4, 7][i]; ls[i].steps = [8, 8, 7, 12][i]; ls[i].restartRhythmBars = []; ls[i].restartMelodyPasses = [] }
                        if loopOnly {   // RESTART UNITS FIX 1 (2026-11-04): WITH RHYTHM with the rhythm chain off — the melody restarts at every pass start; lane 2 adds a HIT chain, lane 3 a PASS chain, lane 4 a stored but switched-off rhythm chain
                            for i in 0..<4 { ls[i].restartMelodyWithRhythm = true }
                            ls[1].restartMelodyPasses = [3]; ls[1].restartMelodyUnit = .hit
                            ls[2].restartMelodyPasses = [2]; ls[2].restartMelodyUnit = .pass
                            ls[3].restartRhythmBars = [1]; ls[3].restartRhythmOn = false
                        } else if !crossLane {
                            ls[0].restartRhythmBars = [1]; ls[0].restartRhythmUnit = .riff; ls[0].restartRhythmSource = 0
                            ls[1].restartRhythmBars = [1]; ls[1].restartRhythmUnit = .riff; ls[1].restartRhythmSource = 1; ls[1].restartMelodyPasses = [3]; ls[1].restartMelodyUnit = .hit
                            ls[2].restartMelodyPasses = [2]; ls[2].restartMelodyUnit = .bar
                        } else {
                            for i in 0..<4 { ls[i].restartRhythmBars = [2, 1]; ls[i].restartRhythmUnit = .pass; ls[i].restartRhythmSource = (i + 1) % 4; ls[i].restartMelodyWithRhythm = i % 2 == 0 ? true : nil }
                            ls[1].restartMelodyPasses = [1]; ls[1].restartMelodyUnit = .pass; ls[1].restartMelodySource = 3
                        }
                        $0.euclideousLines = ls
                    }
                }
                if name.contains("ROUTED") {   // CARD BACKS (2026-10-28): the routing worst case — every riff part on all four outputs, the notes parts on A+C or all four, lane 4's notes routed nowhere (drawn, never sent); the roll ring takes a record per strike
                    au.editDocument { var ls = $0.euclideousLinesResolved; for i in 0..<4 { ls[i].riffOutMask = 0x0F; ls[i].notesOutMask = i == 3 ? 0 : (i % 2 == 0 ? 0b0101 : 0x0F) }; $0.euclideousLines = ls }
                }
                if name.contains("OUT-TRANSPOSE") {   // CARD BACKS v2 (2026-10-28): every part shifted by scale steps (±7 included) on top of the routing worst case — the scale-step mover runs on every strike
                    au.editDocument { var ls = $0.euclideousLinesResolved; for i in 0..<4 { ls[i].riffOutTranspose = [3, -4, 7, -7][i]; ls[i].notesOutTranspose = [-5, 2, 7, -7][i] }; $0.euclideousLines = ls }
                }
                if name.contains("OUTPUT MUTE") {   // MUTE TAB EMITTER ROLL §2.3 (2026-11-09): every output has a muted pattern at a different unit (1/16·1/8·1/4·BAR) with every part routed to all four — the per-window unit build, the emission gate and the per-strike off-clamp (`euclideousLaneMuteStart`) all run; none may allocate
                    au.editDocument {
                        var ls = $0.euclideousLinesResolved; for i in 0..<4 { ls[i].riffOutMask = 0x0F; ls[i].notesOutMask = 0x0F }; $0.euclideousLines = ls
                        $0.euclideousOutputMutes = EuclideousOutputMutes((0..<4).map { o in EuclideousOutputMute(cells16: [0xAAAA, 0xCCCC, 0xF0F0, 0xFF00][o], passes: 1, muteUnit: UInt8(o)) })
                    }
                }
                if name.contains("EMITTER RATCHETS") {   // RATCH tab ferry (2026-10-28): every output ratcheting — the ×4 every-hit case with a CHANCE roll, a partial pattern, a rare one — on top of the routing / hocket worst cases: the count, the decision and the strike layout must allocate nothing
                    au.editDocument {
                        var set = EmitterRatchetSet()
                        set[0] = EmitterRatchet(on: true, steps: 16, hits: 16, offset: 0, chance: 75, strikes: 4)
                        set[1] = EmitterRatchet(on: true, steps: 5, hits: 3, offset: 1, chance: 50, strikes: 2)
                        set[2] = EmitterRatchet(on: true, steps: 7, hits: 4, offset: 2, chance: 100, strikes: 3)
                        set[3] = EmitterRatchet(on: true, steps: 2, hits: 2, offset: 0, chance: 25, strikes: 4)
                        $0.euclideousEmitterRatchets = set
                    }
                }
                if name.contains("EMITTER VELOCITY") {   // VELOCITY tab (2026-11-03): every output accented — varied patterns, signed HIT VEL / MISS VEL — on top of the routing worst case: the count, the decision and the per-output offset at emission must allocate nothing
                    au.editDocument {
                        var set = EmitterVelocitySet()
                        set[0] = EmitterVelocity(on: true, steps: 16, hits: 16, offset: 0, hitVel: 40, missVel: -20)
                        set[1] = EmitterVelocity(on: true, steps: 5, hits: 3, offset: 1, hitVel: -63, missVel: 63)
                        set[2] = EmitterVelocity(on: true, steps: 7, hits: 4, offset: 2, hitVel: 25, missVel: -10)
                        set[3] = EmitterVelocity(on: true, steps: 2, hits: 2, offset: 0, hitVel: 63, missVel: 0)
                        $0.euclideousEmitterVelocities = set
                    }
                }
                if name.contains("ANSWER") {   // ANSWER ferry (2026-11-02): the cycle latch, the window split, the phase rows, and TRADE's push — the record, the re-voiced rebuild and a second emission per hit (with the hocket fan-out and the routing worst case in the last run)
                    au.editDocument { answerDocument(&$0, name.contains("cycles") ? 1 : (name.contains("SWAP") ? 4 : (name.contains("PING-PONG") ? 6 : 5))) }
                }
                if name.contains("PLAY AS SEQ") {   // PLAY AS SEQUENCE (2026-11-08): every lane plays a MULTI-chip sequence covering all six new modes over lit notes, with TIE on — so the active-chip walk (`euclideousPlaySeqActive`), the per-hit mode pick and the TIE lookahead (which recomputes the active mode at each scanned hit) all run on the render thread each hit and must allocate nothing (the factory presets are all single-chip, so this is the only multi-chip coverage)
                    au.editDocument {
                        var ls = $0.euclideousLinesResolved
                        for i in 0..<4 {
                            ls[i].notesOn = true
                            ls[i].notesLitOrder = [0, 2, 4, 5, 7, 8, 9]   // several ranks + TOP 2 + TOP, so every mode has notes to arrange
                            ls[i].notesWhen = 0b11
                            ls[i].riffOnRest = .tie                        // exercise the TIE lookahead across chip boundaries
                            ls[i].notesPlaySeq = [
                                EuclideousPlayStep(mode: .cycle, hits: 2), EuclideousPlayStep(mode: .reverse, hits: 3),
                                EuclideousPlayStep(mode: .pairs, hits: 2), EuclideousPlayStep(mode: .random, hits: 1),
                                EuclideousPlayStep(mode: .alternate, hits: 3), EuclideousPlayStep(mode: .outline, hits: 2),
                                EuclideousPlayStep(mode: .drone, hits: 1), EuclideousPlayStep(mode: .build, hits: 2)]
                        }
                        $0.euclideousLines = ls
                    }
                }
                if name.contains("EMITTER CC") {   // CC tab (Nov 2026): every output sends a CC — HITS + RIFF + PING-PONG + CLIMB value modes, hold-then-ramp shapes (TO REST / NEXT, LIN / EXP), an inverted LOW > HIGH map — so the per-hit value, the GLIDE next-rank prediction, the ramp walk and the mute gate all run on the render thread and must allocate nothing
                    au.editDocument {
                        var set = EmitterCCSet()
                        set[0] = EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, hold: 50, ramp: 50, to: .next, curve: .lin, muteValue: 10)             // RIFF glide: hold, then ramp to the NEXT hit's value
                        set[1] = EmitterCC(on: true, ccNumber: 71, valueMode: .hits, high: 90, low: 20)                                                                              // HITS (merged coincident hits, count / routed) with the default shape: hold 25, ramp 50, REST, EXP
                        set[2] = EmitterCC(on: true, ccNumber: 1, valueMode: .climb, high: 20, low: 110, hold: 30, ramp: 70, to: .next, curve: .exp, passes: 2)                        // CLIMB over two passes, LOW > HIGH (descending), EXP to NEXT
                        set[3] = EmitterCC(on: true, ccNumber: 11, valueMode: .pingPong, high: 127, low: 0, hold: 0, ramp: 100, to: .rest, curve: .lin)                              // PING-PONG, a full-gap linear ramp to REST
                        $0.euclideousEmitterCCs = set
                        var ls = $0.euclideousLinesResolved   // the default document's lanes 3 and 4 have no hits, so C and D would never fire: give every emitter a lane (and lane 2 onto A as well, so one emitter merges two lanes)
                        for i in 2..<4 { ls[i].pulses = 3 + i; ls[i].steps = 8; ls[i].enabled = true }
                        ls[1].riffOutMask = 0b0011; ls[1].notesOutMask = 0b0011
                        $0.euclideousLines = ls
                    }
                }
                if name.contains("HOLD") { au.editDocument { $0.euclideousHoldLatchMode = .hold } }
                if name.contains("LATCH") { au.editDocument { $0.euclideousHoldLatchMode = .latch } }
            } else { au.loadFactoryPreset(named: name) }
            publishDocument()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [self] in
                for _ in 0..<8 { render(480) }
                baseSample = sampleTime
                hold([60, 64, 67]); playing = true
                if i == 0 || name.contains("HOCKET") || name.contains("ROUTED") || name.contains("CANON") || name.contains("ANSWER") || name.contains("INPUTS") { for _ in 0..<800 { render(480) }; playing = false; for _ in 0..<8 { render(480) }; baseSample = sampleTime; playing = true }   // an unwatched warm-up lap: Swift's one-time generic-metadata instantiation (the first use of each type) is not what this measures; HOCKET's types are first touched by its own scenarios   // the unwatched warm-up lap
                eventCount = 0; AllocWatch.reset(); watching = true
                var handIdx = 0
                for w in 0..<6400 {
                    if name.contains("PART SOLO") {   // PER-PART SOLO (MIX v2, 2026-11-05): the part mask changes every 40 windows through the page's live word — lane 1's riff alone, a lane + a part, a held notes part, then nothing — so the filter, the cut sweep and the dedupe run on the render thread
                        if w % 40 == 0 { au.setEuclideousPartSoloLive([0b0000_0001, 0b1000_0000, 0b0001_0100, 0, 0b0010_0010, 0][(w / 40) % 6]); au.setEuclideousSoloLive([0, 0b0010, 0, 0, 0b0100, 0][(w / 40) % 6]) }
                    }
                    if name.contains("hand"), w > 0, w % 400 == 0 { release(canonHandChords[handIdx % canonHandChords.count]); handIdx += 1; hold(canonHandChords[handIdx % canonHandChords.count]) }   // CANON: the hand changes chord
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
                if name.contains("hand") { release(canonHandChords[handIdx % canonHandChords.count]) }
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
