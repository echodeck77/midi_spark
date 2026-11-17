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

    // RIBBON SETTINGS REMOVED (Paul 2026-11-17): SnapshotBuilder feeds the engine `.defaults` whatever the document stores,
    // so TUTTI (and every other setting) is INERT — the removal's pin, through the REAL Router. The old firing tests
    // (marked step/rank pulls the other lane, the PARTS gate, the lone-lane case) described behaviour that is now
    // unreachable; this replaces them with the one fact that matters: a stored document sounds exactly as if no
    // settings were ever saved.
    func testStoredRibbonSettingsAreInert() {
        let plain = run(l0: lane(rotate: 0), l1: lane(rotate: 3))
        let marked = run(l0: lane(rotate: 0), l1: lane(rotate: 3)) {
            $0.tuttiSteps = 0xFF; $0.tuttiRanks = 0xFF; $0.riffLanes = 0b0001; $0.stackLanes = 0; $0.latch = true
            $0.touchMode = .tutti; $0.release = .carryOn
        }
        XCTAssertEqual(marked[0], plain[0], "stored settings change nothing — lane 0")
        XCTAssertEqual(marked[2], plain[2], "stored settings change nothing — lane 1")
        XCTAssertFalse(plain[0]?.isEmpty ?? true, "lane 0 actually plays")
        XCTAssertFalse(plain[2]?.isEmpty ?? true, "lane 1 actually plays")
    }
}
