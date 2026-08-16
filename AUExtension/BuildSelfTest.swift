import Foundation

// IN-APP MIDI-OUTPUT SELF-TESTS (Paul 2026-08-16) — replaces the canned T-session loader on the dev overlay.
// Each test drives the REAL Router offline (the same engine the live render uses — the Dice precedent) with a
// BUILD-style scene + a held chord, RECORDS the emitted MIDI, and checks it against what the processor / BUILD
// scene SHOULD produce. So a regression where the MIDI output drifts from expected is caught on-device, in seconds,
// without a Mac. Focus: the BUILD page's colour→cell→MIDI mapping and the processor roster. Foundation-only; reuses
// SnapshotBuilder + Router. Dev-only (#if DEBUG) — never ships on the product face.
#if DEBUG

struct SelfTestResult: Identifiable {
    let id = UUID()
    let name: String
    let passed: Bool
    let detail: String        // "expected … got …" — shown only on failure
}

// A recording MIDIEmitter double (like Dice's, but keeps note + channel + cable + on/off, for exact-output checks).
final class SelfTestRecorder: MIDIEmitter {
    struct Ev { let on: Bool; let note: UInt8; let chan: UInt8; let cable: UInt8; let sample: Int64 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0
        if st == 0x90 && b2 > 0 { events.append(.init(on: true, note: b1, chan: b0 & 0x0F, cable: cable, sample: sampleTime)) }
        else if st == 0x80 || (st == 0x90 && b2 == 0) { events.append(.init(on: false, note: b1, chan: b0 & 0x0F, cable: cable, sample: sampleTime)) }
    }
    func ons(cable: UInt8) -> [UInt8] { events.filter { $0.on && $0.cable == cable }.map { $0.note } }
    var onsA: [UInt8] { ons(cable: 1) }                          // note-ons on Emit A
    var onCountA: Int { events.filter { $0.on && $0.cable == 1 }.count }
    /// No stuck notes: the LAST event for every (cable, channel, note) must be an OFF (a refcount collapse can fold
    /// many ons into one off, so on,on,off is legal — the sequence just must never END on an ON).
    var noStuck: Bool {
        var last: [Int: Bool] = [:]
        for e in events { last[(Int(e.cable) * 16 + Int(e.chan)) * 128 + Int(e.note)] = e.on }
        return last.values.allSatisfy { !$0 }
    }
}

enum BuildSelfTest {

    // MARK: fixtures

    /// A single-slot machine colour (its type on the A face), like a BUILD cast colour.
    static func colour(_ id: String, _ type: ProcessorType, _ cfg: (inout ColourParams) -> Void = { _ in }) -> Colour {
        var c = Colour(colourID: id, type: type); cfg(&c.paramsA); return c
    }
    /// A RAW passthrough colour — explicit empty chain = born-audible identity (holds the chord unprocessed), exactly
    /// what a BUILD colour with no machine sounds like.
    static func rawColour(_ id: String, transpose: Int = 0) -> Colour {
        var c = Colour(colourID: id, type: .passgate); c.templateChain = []; c.transpose = transpose; return c
    }
    static func cell(_ id: String, buses: Set<Bus> = [.a]) -> Cell {
        var c = Cell(colourID: id, buses: buses); c.inputReceiver = 0; return c
    }

    // MARK: the offline engine run

    /// Drive a BUILD-style scene through the REAL engine and record its MIDI. laneMask 0 = a normal 8-column sweep
    /// (BUILD never laps). Mirrors Dice.evalRun / RouterTests.run — held chord in, emitted MIDI captured, then a
    /// STOP window flushes so no-stuck-note can be checked.
    static func render(_ colours: [Colour], chord: [UInt8] = [60, 64, 67], beats: Double = 8, laneMask: UInt8 = 0,
                       _ build: (inout SceneState) -> Void) -> SelfTestRecorder {
        var s = SceneState.empty(); build(&s)
        var st = PluginState(colours: colours, scenes: [s]); st.busChannels = [1, 2, 3, 4]
        st.synthesizeReceiversIfNeeded()
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = SelfTestRecorder()
        let pool = NotePool(); for n in chord { pool.noteOn(n, velocity: 100, channel: 0) }; pool.rebuildSorted()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let wb = Double(frames) * tempo / 60.0 / sr; var beat = 0.0, ts = 0.0
        while beat < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                           timestampSample: ts, frameCount: frames, laneMask: laneMask, out: e, diag: &diag)
            beat += wb; ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, out: e, diag: &diag)   // stop → flush every voice
        return e
    }

    // small assertion sugar
    private static func check(_ name: String, _ passed: Bool, _ detail: @autoclosure () -> String) -> SelfTestResult {
        SelfTestResult(name: name, passed: passed, detail: passed ? "" : detail())
    }

    // MARK: the tests

    static func runAll() -> [SelfTestResult] {
        var out: [SelfTestResult] = []

        // 1 — a raw (machine-less) colour plays the held chord UNPROCESSED on Emit A.
        do {
            let e = render([rawColour("gold")]) { $0.cells[0][0] = cell("gold") }
            let got = Set(e.onsA)
            out.append(check("Raw colour plays the held chord", got == [60, 64, 67] && e.noStuck,
                             "expected {60,64,67} on Emit A, got \(Set(e.onsA).sorted()); noStuck=\(e.noStuck)"))
        }
        // 2 — the colour's TRANSPOSE shifts the output pitch.
        do {
            let e = render([rawColour("gold", transpose: 5)], chord: [60]) { $0.cells[0][0] = cell("gold") }
            out.append(check("Transpose shifts the pitch (+5)", Set(e.onsA) == [65] && e.noStuck,
                             "expected {65}, got \(Set(e.onsA).sorted())"))
        }
        // 3 — HARMONIZE adds the interval voice (60 with +12 → 60 and 72).
        do {
            let e = render([colour("gold", .harmonize) { $0.harmIntervals = [12, 0, 0] }], chord: [60]) { $0.cells[0][0] = cell("gold") }
            let got = Set(e.onsA)
            out.append(check("Harmonize adds the +12 voice", got.isSuperset(of: [60, 72]) && e.noStuck,
                             "expected ⊇{60,72}, got \(got.sorted())"))
        }
        // 4 — ARP arpeggiates: one chord yields MORE than its note-count of ons over time.
        do {
            let e = render([colour("gold", .arp)]) { $0.cells[0][0] = cell("gold") }
            out.append(check("Arp arpeggiates the chord over time", e.onCountA > 3 && e.noStuck,
                             "expected >3 ons on Emit A, got \(e.onCountA)"))
        }
        // 5 — CASCADE plays ONLY its populated columns, proportionally (the 'column 2 gates everything' regression):
        //     a sparse scene's output = the sum of its columns. No inversion, no phantom gating.
        do {
            func casc(_ cols: [Int]) -> Int {
                render([colour("gold", .cascade) { $0.rate = .r1_8 }]) { s in for c in cols { s.cells[c][0] = cell("gold") } }.onCountA
            }
            let all = casc([0, 1, 2, 3, 4, 5, 6, 7]), only2 = casc([2]), but2 = casc([0, 1, 3, 4, 5, 6, 7])
            out.append(check("Cascade sounds only its populated columns", all == only2 + but2 && but2 > only2,
                             "expected all(\(all)) == only-col2(\(only2)) + all-but-col2(\(but2))"))
        }
        // 6 — an EPHEMERAL colour (index ≥33, the unlimited-colours model) renders WITHOUT trapping the render thread
        //     and uses its OWN transpose (the override-table SIGTRAP fix).
        do {
            var colours = (0..<40).map { rawColour("x\($0)") }   // 40 colours → last index 39 ≫ 33
            colours[39].transpose = 7
            let e = render(colours, chord: [60]) { $0.cells[0][0] = cell("x39") }
            out.append(check("Ephemeral colour (index ≥33) doesn't trap the render", Set(e.onsA) == [67] && e.noStuck,
                             "expected {67} from x39 (+7), got \(Set(e.onsA).sorted())"))
        }
        // 7 — an ALL-BYPASSED chain collapses to the born-audible passthrough (holds the chord raw).
        do {
            var slot = ProcessorSlot(type: .arp); slot.bypassed = true
            var c = Colour(colourID: "gold", type: .passgate); c.templateChain = [slot]
            let e = render([c], chord: [60]) { $0.cells[0][0] = cell("gold") }
            out.append(check("A fully-bypassed chain is a passthrough", Set(e.onsA) == [60] && e.noStuck,
                             "expected {60}, got \(Set(e.onsA).sorted())"))
        }
        // 8 — an EMPTY scene emits nothing.
        do {
            let e = render([rawColour("gold")]) { _ in }
            out.append(check("An empty grid is silent", e.events.isEmpty,
                             "expected no MIDI, got \(e.events.count) events"))
        }
        // 9 — the cell's EMITTER routes the output: a cell on bus B sounds on Emit B (cable 2), never on Emit A.
        do {
            let e = render([rawColour("gold")], chord: [60]) { $0.cells[0][0] = cell("gold", buses: [.b]) }
            out.append(check("A cell on Emitter B avoids Emitter A", e.onsA.isEmpty && !e.ons(cable: 2).isEmpty,
                             "expected nothing on Emit A + something on Emit B, got A=\(e.onsA) B=\(e.ons(cable: 2))"))
        }
        // 10 — DRONE holds the whole chord as a pad.
        do {
            let e = render([colour("gold", .drone) { $0.gate = 0.8 }]) { $0.cells[0][0] = cell("gold") }
            out.append(check("Drone holds the chord as a pad", Set(e.onsA) == [60, 64, 67] && e.noStuck,
                             "expected {60,64,67}, got \(Set(e.onsA).sorted())"))
        }
        // 11 — NO STUCK NOTES across the whole processor roster (every type flushes clean on stop).
        do {
            let roster: [(String, Colour)] = [
                ("arp", colour("gold", .arp)),
                ("ratchet", colour("gold", .ratchet)),
                ("euclid", colour("gold", .euclid) { $0.euclidPulses = 4; $0.euclidSteps = 8 }),
                ("cascade", colour("gold", .cascade) { $0.rate = .r1_8 }),
                ("strum", colour("gold", .strum) { $0.spread = 0.5 }),
                ("chance", colour("gold", .chance)),
                ("harmonize", colour("gold", .harmonize) { $0.harmIntervals = [12, 0, 0] }),
                ("drone", colour("gold", .drone) { $0.gate = 0.8 }),
                ("passgate", colour("gold", .passgate) { $0.passes = [true, true, true, true]; $0.gate = 1.0 }),
            ]
            var stuck: [String] = []
            for (name, col) in roster {
                let e = render([col]) { $0.cells[0][0] = cell("gold") }
                if !e.noStuck { stuck.append(name) }
            }
            out.append(check("No stuck notes across the processor roster", stuck.isEmpty,
                             "left a note sounding after stop: \(stuck.joined(separator: ", "))"))
        }
        // 12 — every NOTE-emitting processor actually SOUNDS (chance excluded — it can legitimately drop the pool).
        do {
            let roster: [(String, Colour)] = [
                ("arp", colour("gold", .arp)),
                ("ratchet", colour("gold", .ratchet)),
                ("euclid", colour("gold", .euclid) { $0.euclidPulses = 4; $0.euclidSteps = 8 }),
                ("cascade", colour("gold", .cascade) { $0.rate = .r1_8 }),
                ("strum", colour("gold", .strum) { $0.spread = 0.5 }),
                ("harmonize", colour("gold", .harmonize) { $0.harmIntervals = [12, 0, 0] }),
                ("drone", colour("gold", .drone) { $0.gate = 0.8 }),
                ("passgate", colour("gold", .passgate) { $0.passes = [true, true, true, true]; $0.gate = 1.0 }),
            ]
            var silent: [String] = []
            for (name, col) in roster {
                let e = render([col]) { $0.cells[0][0] = cell("gold") }
                if e.onCountA == 0 { silent.append(name) }
            }
            out.append(check("Every processor sounds the held chord", silent.isEmpty,
                             "emitted nothing on Emit A: \(silent.joined(separator: ", "))"))
        }

        return out
    }
}
#endif
