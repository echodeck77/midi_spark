//  AnswerTradeReviewTests.swift — from the adversarial review of the ANSWER ferry's TRADE (2026-11-02): a legato first phase-B note, and every 4-lane TRADE arrangement through the edit / normalise rules.
//  Self-contained harness mirroring AnswerRouterTests: four lanes on four outputs (cable n+1), 120 BPM @ 48 kHz, a MIDI pool walked rank by rank.

import XCTest

private extension SnapshotBuilder {
    static func buildKeeping(_ st: PluginState) -> SnapshotBox {
        var d = st; var p = d.sourcePlanResolved; p.midiOctaves = .keep; d.euclideousSourcePlan = p
        return build(from: d)
    }
}

private struct ReviewRng: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}

private final class ReviewEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let chan: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, chan: b0 & 0x0F, note: b1, vel: b2)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
    var offs: [Ev] { events.filter { $0.status == 0x80 } }
}

final class AnswerTradeReviewTests: XCTestCase {
    private let beatSamples = 24_000.0
    private let pool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]

    private func lane(pulses: Int = 8, steps: Int = 8, rate: ArpRate = .r1_4, oct: Int = 0, vel: Int = 100, gate: Double = 0.5) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: pulses, steps: steps, velocityAbsolute: vel, rate: rate, useRiff: true, riffOn: true, sourceMode: .midi)
        l.gate = gate; l.riffOctave = oct
        return l
    }
    private func state(_ lines: [EuclidLine]) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        return st
    }
    private func held() -> NotePool { let p = NotePool(); for n in pool { p.noteOn(n, velocity: 100, channel: 0) }; return p }
    private func run(_ st: PluginState, beats: Double, frames: UInt32 = 2048) -> ReviewEmitter {
        let box = SnapshotBuilder.buildKeeping(st)
        let e = ReviewEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let p = held()
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    private func beatOf(_ sample: Int64) -> Double { ((Double(sample) + 2) / beatSamples * 1000).rounded() / 1000 }
    private func assertNothingLeftSounding(_ e: ReviewEmitter, file: StaticString = #filePath, line: UInt = #line) {
        var depth: [Int: Int] = [:]
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            let key = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            depth[key, default: 0] += ev.status == 0x90 ? 1 : -1
        }
        for (k, d) in depth { XCTAssertEqual(d, 0, "every note-on has its note-off (key \(k))", file: file, line: line) }
    }
    /// The held duration (in beats) of the FIRST note-on on `cable` at or after beat `atBeat`, to its matching note-off (ignores the pre-existing -2^32 sentinel offs).
    private func firstNoteDuration(_ e: ReviewEmitter, cable: UInt8, atBeat: Double) -> (note: Int, dur: Double)? {
        guard let on = e.ons.filter({ $0.cable == cable && beatOf($0.sample) >= atBeat - 1e-6 }).sorted(by: { $0.sample < $1.sample }).first else { return nil }
        guard let off = e.offs.filter({ $0.cable == cable && $0.note == on.note && $0.sample > on.sample }).sorted(by: { $0.sample < $1.sample }).first else { return (Int(on.note), .infinity) }
        return (Int(on.note), Double(off.sample - on.sample) / beatSamples)
    }
    private func walk(_ t: Int, oct: Int = 0) -> Int { Int(pool[((t % 8) + 8) % 8]) + 12 * oct }

    // A legato (raw gate 1.0) TRADE where the SUPPLIER's lane index is LOWER than the TRADER's: the supplier is processed first and pushes the trader's FIRST phase-B note onto the trader's legato held-set.
    // The boundary close (for the trader's OLD phase-A hold) must already have run, or it lands on that note and cuts it to the 10 ms overlap.
    func testBorrowLegatoFirstPhaseBNoteIsHeldNotCutWhenSupplierIndexIsLower() {
        var supplier = lane(rate: .r1_4, oct: 0, gate: 1.0)                 // lane 0 — processed first
        var trader = lane(rate: .r1_4, oct: 2, gate: 1.0)                   // lane 1 — borrows lane 0
        trader.listenSource = 0
        trader.answerTradeOn = true; trader.answerTradeMode = .borrow; trader.answerTradeWith = 0
        trader.answerCycleEach = 1; trader.answerCycleUnit = .bars          // bar 0 = own (A), bar 1 = borrow (B), …
        supplier.listenSource = 1
        let e = run(state([supplier, trader]), beats: 12)
        assertNothingLeftSounding(e)   // balanced — the bug this guards is a wrong DURATION, not a stuck note
        guard let first = firstNoteDuration(e, cable: 2, atBeat: 4.0) else { return XCTFail("the trader emitted nothing in phase B") }
        XCTAssertEqual(first.note, walk(4, oct: 2), "phase B: the trader plays the supplier's beat-4 note through its own octave")
        XCTAssertEqual(first.dur, 1.0, accuracy: 0.1, "legato: the borrowed note should be held until the next hit (beat 5), not cut after ~10 ms — got \(first.dur) beats")
    }

    // The mirror: the TRADER's index is the lower one (processed first) — the processing order must not matter.
    func testBorrowLegatoFirstPhaseBNoteIsHeldWhenTraderIndexIsLower() {
        var trader = lane(rate: .r1_4, oct: 2, gate: 1.0)                   // lane 0 — processed first, borrows lane 1
        var supplier = lane(rate: .r1_4, oct: 0, gate: 1.0)                 // lane 1
        trader.listenSource = 1
        trader.answerTradeOn = true; trader.answerTradeMode = .borrow; trader.answerTradeWith = 1
        trader.answerCycleEach = 1; trader.answerCycleUnit = .bars
        supplier.listenSource = 0
        let e = run(state([trader, supplier]), beats: 12)
        assertNothingLeftSounding(e)
        guard let first = firstNoteDuration(e, cable: 1, atBeat: 4.0) else { return XCTFail("the trader emitted nothing in phase B") }
        XCTAssertEqual(first.dur, 1.0, accuracy: 0.1, "legato: trader-lower ordering holds the borrowed note correctly — got \(first.dur) beats (contrast with supplier-lower)")
    }

    // SWAP at legato: the pair's HIGHER-indexed lane is pushed to by the lower one (processed first).
    func testSwapLegatoHigherLaneFirstPhaseBNoteIsHeld() {
        var one = lane(rate: .r1_4, oct: 0, gate: 1.0)                      // lane 0
        var three = lane(rate: .r1_4, oct: 2, gate: 1.0)                    // lane 2 (higher index of the pair)
        one.answerTradeOn = true; one.answerTradeMode = .swap; one.answerTradeWith = 2; one.answerCycleEach = 1; one.answerCycleUnit = .bars
        three.answerTradeOn = true; three.answerTradeMode = .swap; three.answerTradeWith = 0; three.answerCycleEach = 1; three.answerCycleUnit = .bars
        let e = run(state([one, lane(rate: .r1_4), three]), beats: 12)
        assertNothingLeftSounding(e)
        guard let first = firstNoteDuration(e, cable: 3, atBeat: 4.0) else { return XCTFail("lane 3 emitted nothing in phase B") }
        XCTAssertEqual(first.dur, 1.0, accuracy: 0.1, "legato SWAP: the higher lane's first borrowed note should be held, not cut — got \(first.dur) beats")
    }

    // MARK: pure 6.4 / 6.5 — fuzz every 4-lane TRADE arrangement

    private func isNormalised(_ L: [EuclidLine]) -> String? {
        for i in 0..<4 where L[i].answerTradeOnResolved && L[i].answerTradeModeResolved == .swap {
            let w = L[i].answerTradeWithResolved(ownLane: i)
            if w == i { return "lane \(i) SWAPs with itself" }
            let p = L[w]
            if !(p.answerTradeOnResolved && p.answerTradeModeResolved == .swap && p.answerTradeWithResolved(ownLane: w) == i) {
                return "lane \(i) SWAPs with \(w) which does not SWAP back"
            }
            if p.answerCycleEachResolved != L[i].answerCycleEachResolved || p.answerCycleUnitResolved != L[i].answerCycleUnitResolved {
                return "swap pair \(i)/\(w) differ in EACH/UNIT"
            }
        }
        return nil
    }

    func testEveryTradeArrangementNormalisesIdempotently() {
        var rng = ReviewRng(s: 0xA25C1E)
        for _ in 0..<20_000 {
            var ls = (0..<4).map { _ -> EuclidLine in
                var l = EuclidLine()
                l.answerTradeOn = Bool.random(using: &rng)
                l.answerTradeMode = Bool.random(using: &rng) ? .swap : .borrow
                l.answerTradeWith = Int.random(in: 0...3, using: &rng)
                l.answerCycleEach = Int.random(in: 1...16, using: &rng)
                l.answerCycleUnit = Bool.random(using: &rng) ? .bars : .passes
                return l
            }
            let r1 = euclideousNormalizeTrades(ls).lines
            if let bad = isNormalised(r1) { XCTFail("normalizeTrades left a non-normalised result: \(bad)"); return }
            let r2 = euclideousNormalizeTrades(r1).lines
            // idempotent: a second pass changes nothing that matters to the SWAP graph
            for i in 0..<4 {
                XCTAssertEqual(r1[i].answerTradeOnResolved, r2[i].answerTradeOnResolved, "normalizeTrades not idempotent (on) lane \(i)")
                XCTAssertEqual(r1[i].answerCycleEachResolved, r2[i].answerCycleEachResolved, "normalizeTrades not idempotent (each) lane \(i)")
                XCTAssertEqual(r1[i].answerCycleUnitResolved, r2[i].answerCycleUnitResolved, "normalizeTrades not idempotent (unit) lane \(i)")
            }
            // The UI always starts from a normalised document (load / snapshot normalise) and applies ONE edit per funnel.
            // Chaining edits from a normalised start must KEEP it normalised at every step (6.4). (Feeding applyTradeEdit a
            // non-normalised start is not something the UI does and is NOT asserted — it is an edit function, not a normaliser.)
            var chain = r1
            for _ in 0..<8 {
                let lane = Int.random(in: 0...3, using: &rng)
                let edit: EuclideousTradeEdit
                switch Int.random(in: 0...4, using: &rng) {
                case 0: edit = .on(Bool.random(using: &rng))
                case 1: edit = .mode(Bool.random(using: &rng) ? .swap : .borrow)
                case 2: edit = .with(Int.random(in: 0...3, using: &rng))
                case 3: edit = .each(Int.random(in: 1...16, using: &rng))
                default: edit = .unit(Bool.random(using: &rng) ? .bars : .passes)
                }
                chain = euclideousApplyTradeEdit(chain, lane: lane, edit: edit)
                if let bad = isNormalised(chain) { XCTFail("a single edit \(edit) on lane \(lane) from a normalised graph broke normalisation: \(bad)"); return }
            }
        }
    }

    private func desc(_ L: [EuclidLine]) -> String {
        (0..<4).map { i in "L\(i)[\(L[i].answerTradeOnResolved ? "on" : "off"),\(L[i].answerTradeModeResolved == .swap ? "swap" : "borrow"),w\(L[i].answerTradeWithResolved(ownLane: i))]" }.joined(separator: " ")
    }
    // Minimal search: apply ONE edit to a normalised start and see whether a single edit can leave a non-normalised graph.
    func testSingleEditKeepsTheGraphNormalised() {
        func starts() -> [[EuclidLine]] {
            // enumerate small normalised starts: a swap pair, a borrow, and plain
            var out: [[EuclidLine]] = []
            for pair in [(0,1),(0,2),(0,3),(1,2),(1,3),(2,3)] {
                var L = (0..<4).map { _ in EuclidLine() }
                L[pair.0].answerTradeOn = true; L[pair.0].answerTradeMode = .swap; L[pair.0].answerTradeWith = pair.1
                L[pair.1].answerTradeOn = true; L[pair.1].answerTradeMode = .swap; L[pair.1].answerTradeWith = pair.0
                out.append(L)
            }
            return out
        }
        let edits: [EuclideousTradeEdit] = [.on(true), .on(false), .mode(.swap), .mode(.borrow), .with(0), .with(1), .with(2), .with(3)]
        for start in starts() {
            precondition(isNormalised(start) == nil)
            for lane in 0..<4 {
                for edit in edits {
                    let r = euclideousApplyTradeEdit(start, lane: lane, edit: edit)
                    if let bad = isNormalised(r) {
                        XCTFail("ONE edit \(edit) on lane \(lane) of [\(desc(start))] → non-normalised: \(bad)  result [\(desc(r))]")
                        return
                    }
                }
            }
        }
    }
}
