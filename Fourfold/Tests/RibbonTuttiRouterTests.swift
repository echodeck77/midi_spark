//  RibbonTuttiRouterTests.swift — RIBBON SETTINGS ferry (2026-11-16), slice 7: TUTTI FIRING (§6.5–6.9) through the REAL Router.
//
//  The #1-bug-class guard: it drives the actual engine (not a mirror) and reads each lane's emitted POOL RANK (`NoteRollRecord.rank`,
//  which for an 8-note ascending pool over the grid [1…8] equals the column's written rank). Two lanes are set to hit on the same
//  beats reading different columns; marking the trigger lane's column (or rank) must pull the other included lanes onto the fire rank
//  for exactly that beat, and leave everything byte-identical with no mark.

import XCTest

final class RibbonTuttiRouterTests: XCTestCase {

    /// A plain riff lane, 8 of 8 so every step is a hit (both lanes then strike on the same beats), with its own riff SHIFT.
    private func lane(rotate: Int) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, velocityAbsolute: 100, rate: .r1_4, useRiff: true, riffOn: true, sourceMode: .midi)
        l.riffRotate = rotate
        return l
    }

    /// Two lanes (0, 1) through the real Router. Returns [part: [beat: rank]] — part 2·lane is the riff. `marks` tweaks the settings.
    private func run(l0: EuclidLine, l1: EuclidLine, beats: Double = 8, marks: ((inout RibbonSettings) -> Void)? = nil) -> [Int: [Double: Int]] {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])   // column n → written rank n
        c.paramsA.euclidLines = [l0, l1, EuclidLine(enabled: false), EuclidLine(enabled: false)]
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
        while beatNow() < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            out += router.rollRing.drain()
            ts += Double(frames)
        }
        var by: [Int: [Double: Int]] = [:]
        for rec in out where !rec.isEnd {
            let b = (rec.onBeat * 1000).rounded() / 1000
            by[Int(rec.part), default: [:]][b] = Int(rec.rank)
        }
        return by
    }

    private func firstSharedBeat(_ a: [Double: Int], _ b: [Double: Int]) -> Double? {
        a.keys.filter { k in b.keys.contains(where: { abs($0 - k) < 1e-6 }) }.sorted().first
    }

    // §13.4 — a MARKED STEP: the trigger's column pulls every other included lane onto that column's written rank, on exactly the shared beat.
    func testMarkedStepPullsTheOtherLaneOntoTheFireRank() {
        let ctl = run(l0: lane(rotate: 0), l1: lane(rotate: 3))
        guard let r0 = ctl[0], let r2 = ctl[2], let beat = firstSharedBeat(r0, r2) else { return XCTFail("the two lanes share no hit beat") }
        let col0 = r0[beat]!, col1 = r2[beat]!                 // grid rank = column, so rank IS the column the lane read
        XCTAssertNotEqual(col0, col1, "the two lanes read different columns at the shared beat (so the fire is observable)")
        // Mark lane 0's column → lane 0 is the trigger; lane 1 must play lane 0's rank there, and its own rank elsewhere.
        let fired = run(l0: lane(rotate: 0), l1: lane(rotate: 3)) { $0.tuttiSteps = UInt8(1) << UInt8(col0 - 1) }
        XCTAssertEqual(fired[0]?[beat], col0, "the trigger plays its own rank")
        XCTAssertEqual(fired[2]?[beat], col0, "the other included lane plays the fire rank on the shared beat")
        // a beat only lane 0 hits is untouched; find one lane-1 beat that is NOT shared and check it kept its own rank.
        if let soloBeat = r2.keys.sorted().first(where: { k in !r0.keys.contains(where: { abs($0 - k) < 1e-6 }) }) {
            XCTAssertEqual(fired[2]?[soloBeat], r2[soloBeat], "a non-shared hit keeps its own rank (§6.8: only the trigger's step changes)")
        }
    }

    // §13.5 — a MARKED RANK: the lane that PLAYS the marked rank is the trigger; the others play that rank on the shared beat.
    func testMarkedRankPullsTheOtherLaneOntoThatRank() {
        let ctl = run(l0: lane(rotate: 0), l1: lane(rotate: 3))
        guard let r0 = ctl[0], let r2 = ctl[2], let beat = firstSharedBeat(r0, r2) else { return XCTFail("no shared beat") }
        let rank0 = r0[beat]!, rank1 = r2[beat]!
        XCTAssertNotEqual(rank0, rank1, "distinct ranks at the shared beat")
        // Mark lane 1's rank → lane 1 is the trigger (it plays the marked rank); lane 0 must play lane 1's rank there.
        let fired = run(l0: lane(rotate: 0), l1: lane(rotate: 3)) { $0.tuttiRanks = UInt8(1) << UInt8(rank1 - 1) }
        XCTAssertEqual(fired[2]?[beat], rank1, "the trigger (the marked-rank lane) plays its own rank")
        XCTAssertEqual(fired[0]?[beat], rank1, "the other included lane plays the fire rank")
    }

    // §3 PARTS gate: a lane EXCLUDED from the riff part is neither a trigger nor a receiver — its rank never changes under a mark.
    func testAnExcludedLaneDoesNotFireOrReceive() {
        let ctl = run(l0: lane(rotate: 0), l1: lane(rotate: 3))
        guard let r0 = ctl[0], let r2 = ctl[2], let beat = firstSharedBeat(r0, r2) else { return XCTFail("no shared beat") }
        let col0 = r0[beat]!
        // exclude lane 1's riff; marking lane 0's column must leave lane 1 on its own rank.
        let fired = run(l0: lane(rotate: 0), l1: lane(rotate: 3)) { $0.tuttiSteps = UInt8(1) << UInt8(col0 - 1); $0.riffLanes = 0b1101 }   // lane 1 (bit 1) off
        XCTAssertEqual(fired[2]?[beat], r2[beat], "an excluded lane keeps its own rank (§3)")
    }

    // §6.7 — one lane alone never fires (no OTHER included hit to pull), even with every step marked: its output is identical to no mark.
    func testOneLaneAloneNeverFires() {
        let plain = run(l0: lane(rotate: 0), l1: EuclidLine(enabled: false))
        let marked = run(l0: lane(rotate: 0), l1: EuclidLine(enabled: false)) { $0.tuttiSteps = 0xFF; $0.tuttiRanks = 0xFF }
        XCTAssertEqual(marked[0], plain[0], "a lone lane is unchanged — no partner to fire to")
        XCTAssertFalse(plain[0]?.isEmpty ?? true, "lane 0 actually plays")
    }
}
