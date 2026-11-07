//  AnswerRouterTests.swift — ANSWER ferry (2026-11-02), §13 tests 4–8, 10–13: the CYCLE phases and TRADE against the real Router. Four lanes on four outputs (cable n+1), 120 BPM at 48 kHz (a beat = 24 000 samples), the MIDI pool
//  C D E F G A B C held down, and a riff that walks it rank by rank — so a lane's note on a beat says WHERE ITS WALK IS, and its octave says WHICH lane's MIX stage voiced it.

import XCTest

private extension SnapshotBuilder {
    /// Documents here hold notes where they are played (MIDI IN OCTAVES KEEP), so a pool note is the note the test names.
    static func build(keeping st: PluginState) -> SnapshotBox {
        var d = st; var p = d.sourcePlanResolved; p.midiOctaves = .keep; d.euclideousSourcePlan = p
        return build(from: d)
    }
}

private final class AnsEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let chan: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, chan: b0 & 0x0F, note: b1, vel: b2)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
    var offs: [Ev] { events.filter { $0.status == 0x80 } }
}

final class AnswerRouterTests: XCTestCase {
    private let beatSamples = 24_000.0
    private let pool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]

    // MARK: harness

    /// A lane that hits `pulses` of `steps` at `rate`, walking the pool upward one rank a hit; `oct` is its riff OCT (its MIX stage's octave), `vel` its VEL pad, `gate` its GATE.
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
    /// Runs `beats` of playing windows (the box may change per window through `boxAt`), then one STOP window.
    private func run(_ st: PluginState, beats: Double, frames: UInt32 = 2048, swapAt: [(beat: Double, state: PluginState)] = []) -> AnsEmitter {
        var box = SnapshotBuilder.build(keeping: st)
        let e = AnsEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let p = held()
        var ts = 0.0
        var pending = swapAt.sorted { $0.beat < $1.beat }
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            if let next = pending.first, beatNow() >= next.beat { box = SnapshotBuilder.build(keeping: next.state); pending.removeFirst() }
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    /// (beat, note, vel) of every note-on a lane (0-based) sent on its own output, in time order.
    private func hits(_ e: AnsEmitter, lane: Int) -> [(beat: Double, note: Int, vel: Int)] {
        e.ons.filter { Int($0.cable) == lane + 1 }.sorted { $0.sample < $1.sample }.map { (beatOf($0.sample), Int($0.note), Int($0.vel)) }
    }
    /// A sample's beat, to the millibeat (the engine places a hit within a sample of its beat, sometimes the sample before).
    private func beatOf(_ sample: Int64) -> Double { ((Double(sample) + 2) / beatSamples * 1000).rounded() / 1000 }
    private func hitsBetween(_ e: AnsEmitter, lane: Int, _ lo: Double, _ hi: Double) -> [(beat: Double, note: Int, vel: Int)] {
        hits(e, lane: lane).filter { $0.beat >= lo && $0.beat < hi }
    }
    private func assertNothingLeftSounding(_ e: AnsEmitter, file: StaticString = #filePath, line: UInt = #line) {
        var last: [Int: UInt8] = [:], depth: [Int: Int] = [:]
        for ev in e.events where ev.status == 0x90 || ev.status == 0x80 {
            let key = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            last[key] = ev.status
            depth[key, default: 0] += ev.status == 0x90 ? 1 : -1
        }
        for (k, v) in last { XCTAssertEqual(v, 0x80, "cable/channel/note \(k) was left sounding", file: file, line: line) }
        for (k, d) in depth { XCTAssertEqual(d, 0, "every note-on has its note-off (key \(k))", file: file, line: line) }
    }
    /// The pool note a lane with no octave sounds on beat `t` (its walk: one rank a beat, wrapping the riff's eight columns).
    private func walk(_ t: Int, oct: Int = 0) -> Int { Int(pool[((t % 8) + 8) % 8]) + 12 * oct }

    // MARK: 4 — PITCH CYCLE

    func testPitchCycleDoublesTheSourceThenPlaysItsOwnWalkThenDoublesAgain() {
        var red = lane(oct: 0), blue = lane(oct: 1)
        blue.listenSource = 0; blue.answerPitchOn = true; blue.answerPitchMode = .shadow; blue.answerPitchCycle = true; blue.answerCycleEach = 2; blue.answerCycleUnit = .bars
        red.listenSource = 1
        let e = run(state([red, blue]), beats: 24)
        let b = hitsBetween(e, lane: 1, 0, 24)
        XCTAssertEqual(b.count, 24)
        for t in 0..<8 { XCTAssertEqual(b[t].note, walk(t), "bars 1–2 (beat \(t)): blue doubles red") }
        for t in 8..<16 { XCTAssertEqual(b[t].note, walk(t, oct: 1), "bars 3–4 (beat \(t)): blue plays its own walk, an octave up — from where the walk is, not from the start") }
        for t in 16..<24 { XCTAssertEqual(b[t].note, walk(t), "bars 5–6 (beat \(t)): double again") }
        XCTAssertEqual(hitsBetween(e, lane: 0, 0, 24).map { $0.note }, (0..<24).map { walk($0) }, "the source is never affected")
        assertNothingLeftSounding(e)
    }

    // MARK: 5 — RHYTHM CYCLE

    func testRhythmCycleCopiesTheSourcesHitsInOddBarsAndPlaysItsOwnInEvenBars() {
        let red = lane(pulses: 3, steps: 8, rate: .r1_8)                    // x..x..x. = beats 0, 1.5, 3 of each bar
        var blue = lane(pulses: 4, steps: 8, rate: .r1_8, oct: 1)           // x.x.x.x. = beats 0, 1, 2, 3
        blue.listenSource = 0; blue.answerRhythmOn = true; blue.answerRhythmMode = .copy; blue.answerRhythmCycle = true; blue.answerCycleEach = 1; blue.answerCycleUnit = .bars
        let e = run(state([red, blue]), beats: 12)
        func beats(_ lo: Double, _ hi: Double) -> [Double] { hitsBetween(e, lane: 1, lo, hi).map { $0.beat } }
        XCTAssertEqual(beats(0, 4), [0, 1.5, 3], "bar 1: lane 1's hits")
        XCTAssertEqual(beats(4, 8), [4, 5, 6, 7], "bar 2: its own")
        XCTAssertEqual(beats(8, 12), [8, 9.5, 11], "bar 3: lane 1's again")
        assertNothingLeftSounding(e)
    }

    // MARK: 6 — PASSES count the borrowed pattern's restarts

    func testPassesCountTheBorrowedEightStepPatternNotTheLanesOwnFiveStepLap() {
        let red = lane(pulses: 8, steps: 8, rate: .r1_4)                   // an 8-beat lap, a hit a beat
        var blue = lane(pulses: 5, steps: 5, rate: .r1_8, oct: 1)          // its OWN lap is 2.5 beats, a hit every half beat
        blue.listenSource = 0; blue.answerRhythmOn = true; blue.answerRhythmMode = .copy; blue.answerRhythmCycle = true; blue.answerCycleEach = 2; blue.answerCycleUnit = .passes
        let e = run(state([red, blue]), beats: 40)
        func half(_ lo: Double, _ hi: Double) -> [Double] { hitsBetween(e, lane: 1, lo, hi).map { $0.beat } }
        XCTAssertEqual(half(0, 16), (0..<16).map(Double.init), "two passes of the 8-step source: blue plays its hits (a beat apart)")
        XCTAssertEqual(half(16, 32), (0..<32).map { 16 + Double($0) * 0.5 }, "then two passes of its own: a hit every half beat")
        XCTAssertEqual(half(32, 40), (0..<8).map { 32 + Double($0) }, "and the source's again")
        assertNothingLeftSounding(e)
    }

    // MARK: 7 — BORROW

    private func borrowState(blueMute: Bool = false, laneOn: Bool = true) -> PluginState {
        let red = lane(rate: .r1_4, oct: 0)
        var blue = lane(rate: .r1_4, oct: 1, vel: 90, gate: 0.4)           // the WITH lane: its own octave, VEL and GATE
        if blueMute { blue.muteCells16 = 0 }                                 // LANES-muted: it still supplies its strikes
        let green = lane(rate: .r1_8, oct: 0, vel: 100, gate: 0.9)
        var gold = lane(rate: .r1_8, oct: -1, vel: 60, gate: 0.9)            // the trader: octave −1, VEL 60
        gold.answerTradeOn = laneOn; gold.answerTradeMode = .borrow; gold.answerTradeWith = 1; gold.answerCycleEach = 2; gold.answerCycleUnit = .bars
        return state([red, blue, green, gold])
    }
    func testBorrowEmitsTheWithLanesOwnStrikesThroughTheTradersOwnMixInTheSecondHalf() {
        let e = run(borrowState(), beats: 24)
        let base = run(borrowState(laneOn: false), beats: 24)
        // lane 2 (the WITH lane) is unaffected
        XCTAssertEqual(hits(e, lane: 1).map { $0.note }, hits(base, lane: 1).map { $0.note })
        XCTAssertEqual(hits(e, lane: 1).map { $0.beat }, hits(base, lane: 1).map { $0.beat })
        // lane 4: its own half-beat hits in bars 1–2 and 5–6, lane 2's beat-apart strikes in bars 3–4
        XCTAssertEqual(hitsBetween(e, lane: 3, 0, 8).map { $0.beat }, hitsBetween(base, lane: 3, 0, 8).map { $0.beat }, "phase A: lane 4 plays as it always did")
        let traded = hitsBetween(e, lane: 3, 8, 16)
        let lane2 = hitsBetween(e, lane: 1, 8, 16)
        XCTAssertEqual(traded.map { $0.beat }, lane2.map { $0.beat }, "bars 3–4: lane 4 strikes exactly when lane 2 does")
        XCTAssertEqual(traded.map { $0.note }, lane2.map { $0.note - 12 * 2 }, "…the same notes through lane 4's own octave (−1 against lane 2's +1)")
        XCTAssertEqual(traded.map { $0.vel }, Array(repeating: 60, count: lane2.count), "…at lane 4's own VEL")
        let offs4 = e.offs.filter { $0.cable == 4 }.map { beatOf($0.sample) }
        for (i, h) in traded.enumerated() {
            let off = offs4.first { $0 > h.beat + 1e-6 } ?? -1
            XCTAssertEqual(off - h.beat, 0.4, accuracy: 0.02, "hit \(i): the note lasts lane 2's gate (0.4 of the beat), not lane 4's (0.9)")
        }
        XCTAssertEqual(hitsBetween(e, lane: 3, 16, 24).map { $0.beat }, hitsBetween(base, lane: 3, 16, 24).map { $0.beat }, "bars 5–6: back to its own")
        assertNothingLeftSounding(e)
    }
    func testAMutedWithLaneStillSuppliesItsStrikes() {
        let e = run(borrowState(blueMute: true), beats: 24)
        XCTAssertTrue(hits(e, lane: 1).isEmpty, "lane 2 is LANES-muted: it plays nothing itself")
        XCTAssertEqual(hitsBetween(e, lane: 3, 8, 16).count, 8, "…but lane 4 still emits its strikes")
        assertNothingLeftSounding(e)
    }
    func testTradersAndFollowersReadTheSameStrikesAtEveryBufferSize() {
        let reference = run(borrowState(), beats: 24, frames: 2048)
        func shape(_ e: AnsEmitter) -> [String] { e.ons.map { (beatOf($0.sample), $0.cable, $0.note, $0.vel) }.sorted { ($0.0, $0.1, $0.2) < ($1.0, $1.1, $1.2) }.map { "\($0.1):\($0.0):\($0.2):\($0.3)" } }
        for frames: UInt32 in [64, 256, 1024] {
            XCTAssertEqual(shape(run(borrowState(), beats: 24, frames: frames)), shape(reference), "buffer \(frames)")
        }
    }

    // MARK: 5.3 — boundaries only

    private func borrowDoc(each: Int, trade: Bool = true) -> PluginState {
        let red = lane(rate: .r1_4, oct: 0)
        let blue = lane(rate: .r1_4, oct: 1, vel: 90, gate: 0.4)
        let green = lane(rate: .r1_8, oct: 0)
        var gold = lane(rate: .r1_8, oct: -1, vel: 60, gate: 0.9)
        gold.answerTradeOn = trade; gold.answerTradeMode = .borrow; gold.answerTradeWith = 1; gold.answerCycleEach = each; gold.answerCycleUnit = .bars
        return state([red, blue, green, gold])
    }
    /// 1 when lane 4 plays lane 2's beat-apart strikes in [lo, hi), 0 when its own half-beat ones.
    private func isTraded(_ e: AnsEmitter, _ lo: Double, _ hi: Double) -> Bool {
        let b = hitsBetween(e, lane: 3, lo, hi).map { $0.beat }
        return b == (Int(lo)..<Int(hi)).map(Double.init)
    }
    func testAnEachChangeInTheMiddleOfAUnitLandsAtTheNextBoundaryOfTheUnitThenInForce() {
        // EACH 4 BARS: A until beat 16. At beat 6.5 EACH drops to 1: nothing changes until the bar line at 8, where bar 3 under EACH 1 is phase A, bar 4 phase B (12–16), bar 5 A…
        let e = run(borrowDoc(each: 4), beats: 28, swapAt: [(6.5, borrowDoc(each: 1))])
        XCTAssertFalse(isTraded(e, 0, 8), "before the boundary: phase A")
        XCTAssertFalse(isTraded(e, 8, 12), "bar 3 under EACH 1: A")
        XCTAssertTrue(isTraded(e, 12, 16), "bar 4: B")
        XCTAssertFalse(isTraded(e, 16, 20), "bar 5: A")
        XCTAssertTrue(isTraded(e, 20, 24), "bar 6: B")
        // The same edit at 6.5 against no edit: until beat 8 the two runs are note for note identical.
        let plain = run(borrowDoc(each: 4), beats: 28)
        func upTo8(_ x: AnsEmitter) -> [String] { x.ons.filter { beatOf($0.sample) < 8 }.map { "\($0.cable):\(beatOf($0.sample)):\($0.note)" } }
        XCTAssertEqual(upTo8(e), upTo8(plain), "an edit between boundaries changes nothing before the next one")
        assertNothingLeftSounding(e)
    }
    func testStartingACycleWaitsForTheNextBoundaryAndEndingItIsAtOnce() {
        // TRADE off until beat 5.5, then on (EACH 1): the cycle starts at the bar line at 8 — bar 3 is phase A (units 0–1 A, 1–2 B… here bar 3 = unit 2 = A), bar 4 B.
        let e = run(borrowDoc(each: 1, trade: false), beats: 20, swapAt: [(5.5, borrowDoc(each: 1))])
        XCTAssertFalse(isTraded(e, 4, 8), "switched on mid-bar-2: nothing yet")
        XCTAssertFalse(isTraded(e, 8, 12), "bar 3 is unit 2: phase A")
        XCTAssertTrue(isTraded(e, 12, 16), "bar 4 is unit 3: phase B")
        // Ending is immediate: TRADE off at beat 13.5, inside phase B — lane 4 is back on its own hits at once.
        let off = run(borrowDoc(each: 1), beats: 20, swapAt: [(13.5, borrowDoc(each: 1, trade: false))])
        XCTAssertTrue(isTraded(off, 12, 13), "still trading before the edit")
        let after = hitsBetween(off, lane: 3, 14, 16).map { $0.beat }
        XCTAssertEqual(after, [14, 14.5, 15, 15.5], "after TRADE goes off, lane 4 plays its own half-beat hits again")
        assertNothingLeftSounding(off)
    }
    func testACycleIsTheSameAtEveryBufferSize() {
        var red = lane(oct: 0), blue = lane(oct: 1)
        blue.listenSource = 0; blue.answerPitchOn = true; blue.answerPitchMode = .shadow; blue.answerPitchCycle = true; blue.answerCycleEach = 1; blue.answerCycleUnit = .bars
        red.listenSource = 1
        func shape(_ x: AnsEmitter) -> [String] { x.events.map { (beatOf($0.sample), $0.cable, $0.status, $0.note) }.sorted { ($0.0, $0.1, $0.2, $0.3) < ($1.0, $1.1, $1.2, $1.3) }.map { "\($0.0):\($0.1):\($0.2):\($0.3)" } }
        let reference = shape(run(state([red, blue]), beats: 20, frames: 2048))
        for frames: UInt32 in [64, 256, 1024, 4096] { XCTAssertEqual(shape(run(state([red, blue]), beats: 20, frames: frames)), reference, "buffer \(frames)") }
    }

    // MARK: 8 — SWAP

    private func swapState() -> PluginState {
        var one = lane(rate: .r1_4, oct: 0, vel: 100, gate: 0.5)              // lane 1: a hit a beat
        let two = lane(rate: .r1_4, oct: 0)
        var three = lane(rate: .r1_8, oct: -1, vel: 70, gate: 0.5)            // lane 3: a hit every half beat
        one.answerTradeOn = true; one.answerTradeMode = .swap; one.answerTradeWith = 2; one.answerCycleEach = 4; one.answerCycleUnit = .bars
        three.answerTradeOn = true; three.answerTradeMode = .swap; three.answerTradeWith = 0; three.answerCycleEach = 4; three.answerCycleUnit = .bars
        return state([one, two, three])
    }
    func testSwapExchangesTheTwoLanesStrikesInTheSecondHalfAndBackAfter() {
        let e = run(swapState(), beats: 48)
        // bars 1–4: each its own; 5–8 (beats 16–32): exchanged; 9–12: back
        XCTAssertEqual(hitsBetween(e, lane: 0, 0, 16).map { $0.beat }, (0..<16).map(Double.init))
        XCTAssertEqual(hitsBetween(e, lane: 2, 0, 16).map { $0.beat }, (0..<32).map { Double($0) * 0.5 })
        XCTAssertEqual(hitsBetween(e, lane: 0, 16, 32).map { $0.beat }, (0..<32).map { 16 + Double($0) * 0.5 }, "lane 1's output carries lane 3's half-beat strikes")
        XCTAssertEqual(hitsBetween(e, lane: 2, 16, 32).map { $0.beat }, (0..<16).map { 16 + Double($0) }, "lane 3's output carries lane 1's beat-apart strikes")
        XCTAssertEqual(hitsBetween(e, lane: 0, 16, 32).map { $0.vel }, Array(repeating: 100, count: 32), "lane 3's strikes through lane 1's VEL")
        XCTAssertEqual(hitsBetween(e, lane: 2, 16, 32).map { $0.vel }, Array(repeating: 70, count: 16), "lane 1's strikes through lane 3's VEL")
        XCTAssertEqual(hitsBetween(e, lane: 0, 32, 48).map { $0.beat }, (32..<48).map(Double.init), "back to its own")
        XCTAssertEqual(hitsBetween(e, lane: 2, 32, 48).map { $0.beat }, (0..<32).map { 32 + Double($0) * 0.5 })
        assertNothingLeftSounding(e)
    }

    // MARK: 10 — chains cannot loop

    /// ANSWER v2 §4.1 (replaces the old "a trade reads own strikes" combine test): a lane with TRADE on plays as if its RHYTHM and PITCH rows were OFF — they are excluded (they keep their settings). A SWAP pair's lane 2 sounds the SAME with FILL + SHADOW on as with them off.
    func testTradeExcludesTheRhythmAndPitchRows() {
        var one = lane(pulses: 3, steps: 8, rate: .r1_8, oct: 0)
        one.answerTradeOn = true; one.answerTradeMode = .swap; one.answerTradeWith = 1; one.answerCycleEach = 1
        var withRows = lane(pulses: 5, steps: 8, rate: .r1_8, oct: 1)
        withRows.listenSource = 0; withRows.answerRhythmOn = true; withRows.answerRhythmMode = .fill; withRows.answerPitchOn = true; withRows.answerPitchMode = .shadow
        withRows.answerTradeOn = true; withRows.answerTradeMode = .swap; withRows.answerTradeWith = 0; withRows.answerCycleEach = 1
        var withoutRows = withRows; withoutRows.answerRhythmOn = false; withoutRows.answerPitchOn = false
        let a = run(state([one, withRows]), beats: 16), b = run(state([one, withoutRows]), beats: 16)
        XCTAssertFalse(hits(a, lane: 1).isEmpty)
        XCTAssertEqual(hits(a, lane: 1).map { [$0.beat, Double($0.note)] }, hits(b, lane: 1).map { [$0.beat, Double($0.note)] }, "TRADE excludes RHYTHM/PITCH: lane 2 plays identically with or without them on")
        assertNothingLeftSounding(a)
    }

    // MARK: 11 (ANSWER v2 §10.7) — TRADE excludes RHYTHM / PITCH

    /// §10.7 (replaces the ANSWER ferry's test 11): lane 2 has RHYTHM FILL AND TRADE. §4.1 excludes FILL while TRADE is on — lane 2 plays as if the row were off; with TRADE switched off, FILL acts and the rhythm changes.
    func testTradeExcludesFillUntilItIsSwitchedOff() {
        let one = lane(pulses: 3, steps: 8, rate: .r1_8, oct: 0)   // the partner / source
        var two = lane(pulses: 5, steps: 8, rate: .r1_8, oct: 1)
        two.listenSource = 0; two.answerRhythmOn = true; two.answerRhythmMode = .fill
        two.answerTradeOn = true; two.answerTradeMode = .borrow; two.answerTradeWith = 0; two.answerCycleEach = 8
        var bare = two; bare.answerRhythmOn = false        // TRADE on, the row explicitly off
        var fillOnly = two; fillOnly.answerTradeOn = false // FILL on, TRADE off (the row acts)
        let eTrade = run(state([one, two]), beats: 8), eBare = run(state([one, bare]), beats: 8), eFill = run(state([one, fillOnly]), beats: 8)
        XCTAssertEqual(hits(eTrade, lane: 1).map { $0.beat }, hits(eBare, lane: 1).map { $0.beat }, "§4.1: FILL is excluded under TRADE — lane 2 plays as if the row were off")
        XCTAssertNotEqual(hits(eFill, lane: 1).map { $0.beat }, hits(eTrade, lane: 1).map { $0.beat }, "with TRADE off, FILL acts and changes the rhythm")
        assertNothingLeftSounding(eTrade)
    }

    // MARK: 15 — POOL: NOW shows the delayed pool under CANON and the frozen one under FREEZE

    /// The CHORDS document of the canon tests: four chords a bar (I IV V vi of C natural minor), every lane hitting once a beat on rank 1 — so the lane's pool IS the chord it is reading.
    private func chordsState(_ lines: [EuclidLine], unit: CanonUnit = .bars) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = [0, 3, 4, 5]; cs.chordsSteps = 4; cs.chordsRate = .r1_1
        st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        st.euclideousSourcePlan = SourcePlan(midiOn: false, chordsOn: true, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [])
        st.euclideousCanonUnit = unit
        return st
    }
    /// Runs `st` and returns every lane's NOW pool as the status feed reports it once the transport has passed each beat in `at`.
    private func poolsAt(_ st: PluginState, at beats: [Double]) -> [Double: [EuclideousLanePoolStatus]] {
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag(); let e = AnsEmitter()
        var ts = 0.0, out: [Double: [EuclideousLanePoolStatus]] = [:]
        var pending = beats.sorted()
        let frames: UInt32 = 1024
        func beatNow() -> Double { ts * 120.0 / 60.0 / 48_000.0 }
        while let next = pending.first {
            router.process(box: box, pool: NotePool(), playing: true, beatPos: beatNow(), tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
            if beatNow() >= next { out[next] = router.euclideousLanePoolStatus(); pending.removeFirst() }
        }
        return out
    }
    func testNowShowsTheDelayedPoolUnderCanon() {
        func chordLane() -> EuclidLine { var l = lane(rate: .r1_4); l.sourceMode = .midi; return l }
        var delayed = chordLane(); delayed.chordDelay = 1                     // one bar behind
        var stale = chordLane(); stale.poolHold = euclideousPoolHoldLock    // FREEZE is no longer read (INPUTS ferry): a lane with it set follows the progression like any other
        let st = chordsState([chordLane(), delayed, stale])
        let p = poolsAt(st, at: [2, 6, 10, 14])
        func notes(_ beat: Double, _ lane: Int) -> [UInt8] { p[beat]![lane].notes }
        XCTAssertFalse(notes(2, 0).isEmpty, "lane 1 is choosing from a chord")
        XCTAssertNotEqual(notes(2, 0), notes(6, 0), "the undelayed lane's pool follows the progression")
        XCTAssertEqual(notes(6, 1), notes(2, 0), "lane 2, one bar behind: its pool at beat 6 is the chord lane 1 chose from at beat 2")
        XCTAssertEqual(notes(10, 1), notes(6, 0), "…and at beat 10 the chord lane 1 had at beat 6")
        XCTAssertEqual(notes(6, 2), notes(6, 0), "a stored FREEZE LOCK does nothing: lane 3 follows the progression with lane 1")
        XCTAssertNotEqual(notes(14, 2), notes(2, 2), "…it does not keep the first pool")
        XCTAssertEqual(p[6]![0].count, p[6]![0].notes.count, "a pool of this size is reported whole")
    }
    func testNowIsEmptyWhenNothingContributes() {
        var st = chordsState([lane(rate: .r1_4)])
        st.euclideousSourcePlan = SourcePlan(midiOn: false, chordsOn: false, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [])
        let p = poolsAt(st, at: [3])
        XCTAssertEqual(p[3]![0].count, 0)
    }

    // MARK: 13 — stuck notes

    func testTradeSwitchedOnAndOffMidNoteLeavesNothingSounding() {
        var long = lane(rate: .r1_4, oct: 0, gate: 0.99)
        var other = lane(rate: .r1_8, oct: 1, gate: 0.99)
        long.answerCycleEach = 1; other.answerCycleEach = 1
        var onState = state([long, other])
        var l0 = long, l1 = other
        l0.answerTradeOn = true; l0.answerTradeMode = .swap; l0.answerTradeWith = 1; l1.answerTradeOn = true; l1.answerTradeMode = .swap; l1.answerTradeWith = 0
        onState = state([l0, l1])
        let offState = state([long, other])
        let e = run(offState, beats: 40, swapAt: [(5.3, onState), (11.7, offState), (17.2, onState), (21.9, offState), (26.4, onState), (33.1, offState)])
        assertNothingLeftSounding(e)
        let e2 = run(onState, beats: 40, swapAt: [(6.1, offState), (14.9, onState)])
        assertNothingLeftSounding(e2)
    }
}
