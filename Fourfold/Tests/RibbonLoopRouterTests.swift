//  RibbonLoopRouterTests.swift — RIBBON SETTINGS ferry (2026-11-16), slice 8: LOOP (§9) through the REAL Router.
//
//  With a loop span set (the live word fed to router.process, as the UI feeds it), an included lane's riff reads columns
//  from the loop walk over the span — first hit at column `lo`, then the lane's own direction/STRIDE/EVERY (§9.2). The grid
//  is [1…8] (column n → written rank n) over an 8-note pool, so the emitted riff POOL RANK equals the column read — which
//  lets the test assert the exact loop sequence. The PARTS gate excludes a lane. No span ⇒ the natural walk (byte-identical).

import XCTest

final class RibbonLoopRouterTests: XCTestCase {

    private func lane(rotate: Int = 0) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, velocityAbsolute: 100, rate: .r1_4, useRiff: true, riffOn: true, sourceMode: .midi)
        l.riffRotate = rotate
        return l
    }

    /// Lane 0 only (lanes 1–3 off). Returns the riff's emitted POOL RANKS as (beat, rank) in onset order. `loop` (lo, hi) feeds the live word (cleared after `loopEndBeat`, §7/§9 release); `marks` tweaks the saved settings (PARTS / RELEASE).
    private func runBeats(_ l0: EuclidLine, loop: (Int, Int)?, loopEndBeat: Double? = nil, beats: Double = 8, marks: ((inout RibbonSettings) -> Void)? = nil) -> [(Double, Int)] {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [l0, EuclidLine(enabled: false), EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        if let marks { var s = RibbonSettings(); marks(&s); st.ribbonSettings = s }
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag()
        final class Null: MIDIEmitter { func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {} }
        let e = Null()
        let pool = NotePool(); for n in [UInt8]([48, 50, 52, 53, 55, 57, 59, 60]) { pool.noteOn(n, velocity: 100, channel: 0) }
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 480
        var ts = 0.0, out: [NoteRollRecord] = []
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            let active = loopEndBeat.map { beatNow() < $0 } ?? true
            let lo = UInt8(active ? (loop?.0 ?? 0) : 0), hi = UInt8(active ? (loop?.1 ?? 0) : 0)
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames,
                           forceColumn: 0, euclideousLoopLo: lo, euclideousLoopHi: hi, out: e, diag: &diag)
            out += router.rollRing.drain()
            ts += Double(frames)
        }
        return out.filter { !$0.isEnd && $0.part == 0 }.sorted { $0.onBeat < $1.onBeat }.map { ((($0.onBeat * 1000).rounded() / 1000), Int($0.rank)) }
    }

    /// Lane 0 only (lanes 1–3 off). Returns the riff's emitted POOL RANKS in onset order. `loop` (lo, hi) feeds the live word; `marks` tweaks the saved settings (PARTS).
    private func run(_ l0: EuclidLine, loop: (Int, Int)?, beats: Double = 6, marks: ((inout RibbonSettings) -> Void)? = nil) -> [Int] {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [l0, EuclidLine(enabled: false), EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        if let marks { var s = RibbonSettings(); marks(&s); st.ribbonSettings = s }
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag()
        final class Null: MIDIEmitter { func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {} }
        let e = Null()
        let pool = NotePool(); for n in [UInt8]([48, 50, 52, 53, 55, 57, 59, 60]) { pool.noteOn(n, velocity: 100, channel: 0) }
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 480
        var ts = 0.0, out: [NoteRollRecord] = []
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        let lo = UInt8(loop?.0 ?? 0), hi = UInt8(loop?.1 ?? 0)
        while beatNow() < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames,
                           forceColumn: 0, euclideousLoopLo: lo, euclideousLoopHi: hi, out: e, diag: &diag)
            out += router.rollRing.drain()
            ts += Double(frames)
        }
        return out.filter { !$0.isEnd && $0.part == 0 }.sorted { $0.onBeat < $1.onBeat }.map { Int($0.rank) }
    }

    // §9.2 — a FWD loop 3–5: the riff reads columns 3, 4, 5, 3, 4, 5, … (grid rank = column), first hit at the low column.
    func testForwardLoopReadsTheSpanFromItsLowColumn() {
        let natural = run(lane(), loop: nil)
        XCTAssertFalse(natural.isEmpty, "the lane plays")
        XCTAssertFalse(natural.allSatisfy { (3...5).contains($0) }, "without a loop the lane uses the whole grid")
        let looped = run(lane(), loop: (3, 5))
        XCTAssertTrue(looped.allSatisfy { (3...5).contains($0) }, "every looped hit reads a column inside 3–5 (got \(looped))")
        XCTAssertEqual(Array(looped.prefix(6)), [3, 4, 5, 3, 4, 5], "the loop walks 3,4,5 from its low column")
    }

    // §9.2 — a REVERSE lane loops the span in its own direction (5, 4, 3, 5, …).
    func testReverseLaneLoopsInItsOwnDirection() {
        var l = lane(); l.riffDir = .reverse
        let looped = run(l, loop: (3, 5))
        XCTAssertTrue(looped.allSatisfy { (3...5).contains($0) }, "inside the span (got \(looped))")
        XCTAssertEqual(Array(looped.prefix(4)), [5, 4, 3, 5], "REV walks the span downward from the top")
    }

    // §9.1 — a one-column span is a static repeat on that column.
    func testOneColumnSpanIsAStaticRepeat() {
        let looped = run(lane(), loop: (4, 4))
        XCTAssertEqual(Array(looped.prefix(4)), [4, 4, 4, 4], "a 4–4 loop repeats column 4")
    }

    // §7.1/§7.2 — RELEASE: SLIP snaps the walk back to its natural column when the loop ends; CONTINUE carries the walk on from the last looped column.
    func testReleaseContinueCarriesTheWalkOnWhileSlipSnapsBack() {
        let slip = runBeats(lane(), loop: (3, 5), loopEndBeat: 2) { $0.release = .slip }       // SLIP is the default, set explicitly
        let cont = runBeats(lane(), loop: (3, 5), loopEndBeat: 2) { $0.release = .carryOn }
        func split(_ s: [(Double, Int)]) -> (pre: [Int], post: [Int]) { (s.filter { $0.0 < 2 }.map { $0.1 }, s.filter { $0.0 >= 2 }.map { $0.1 }) }
        let (preSlip, postSlip) = split(slip), (preCont, postCont) = split(cont)
        XCTAssertFalse(preCont.isEmpty && postCont.isEmpty, "the lane plays before and after the release")
        XCTAssertEqual(preSlip, preCont, "both are in the loop (identical) before the release")
        XCTAssertTrue(preCont.allSatisfy { (3...5).contains($0) }, "the loop reads 3–5 before release (got \(preCont))")
        guard let lastLoop = preCont.last, let firstSlip = postSlip.first, let firstCont = postCont.first else { return XCTFail("no hits around the release") }
        XCTAssertEqual(firstCont, (lastLoop % 8) + 1, "CONTINUE carries the FWD walk on from the last looped column \(lastLoop) → \(lastLoop + 1)")
        XCTAssertNotEqual(postSlip, postCont, "SLIP and CONTINUE diverge after the release (SLIP snapped to natural \(firstSlip), CONTINUE continued \(firstCont))")
    }

    // §3.2 — an EXCLUDED riff lane ignores the loop entirely (plays its natural walk).
    func testExcludedLaneIgnoresTheLoop() {
        let natural = run(lane(), loop: nil)
        let excluded = run(lane(), loop: (3, 5)) { $0.riffLanes = 0b1110 }   // lane 0 (bit 0) off
        XCTAssertEqual(excluded, natural, "an excluded riff lane plays exactly as with no loop")
    }
}
