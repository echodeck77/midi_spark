//  RateTimingTests.swift — RATE ferry (2026-11-12), slice 2: the pure timing functions. euclideousRateRun (which run a host beat
//  sits in), euclideousLaneElapsed (§2.3), euclideousLaneHostBeat (the inverse), and EuclideousRateMap. No Router wiring yet.

import XCTest

final class RateTimingTests: XCTestCase {

    private func strip(_ codes: [UInt8]) -> EuclideousRateStrip { var l = EuclidLine(); l.rateBars = codes; return euclideousLaneRateStrip(line: l) }
    private func run(m: Double, R: Double = 0, end: Double = 1e6, bar: Int64 = 0) -> EuclideousRateRun { EuclideousRateRun(active: true, startBeat: R, endBeat: end, multiplier: m, runBarIndex: bar) }
    private let off = EuclideousRateRun()

    // §7.3 — inactive / FREE ⇒ elapsed is b − o, everywhere.
    func testInactiveElapsedIsBeatMinusOrigin() {
        var rng = SystemRandomNumberGenerator()
        for _ in 0..<1000 {
            let b = Double.random(in: -50...500, using: &rng), o = Double.random(in: -10...10, using: &rng)
            XCTAssertEqual(euclideousLaneElapsed(hostBeat: b, origin: o, run: off), b - o, accuracy: 1e-9)
        }
        // a FREE lane resolves to an inactive strip ⇒ its run is never active
        var free = EuclidLine(); free.rateBars = [3, 3, 3, 3, 3, 3, 3, 3]; free.rateFree = true
        XCTAssertFalse(euclideousRateRun(strip: euclideousLaneRateStrip(line: free), hostBeat: 5, beatsPerBar: 4).active)
    }

    // §7.1 — inside a run the step length is the lane's step length ÷ m, for every rate and multiplier.
    func testStepLengthHalvesDoublesByMultiplier() {
        for rate in ArpRate.allCases {
            let sub = rate.beats
            for code: UInt8 in [1, 2, 3, 4] {
                let m = euclideousRateMultiplier(code: code), r = run(m: m)
                for i in 0..<8 {
                    let a = euclideousLaneHostBeat(elapsedSinceOrigin: Double(i) * sub, origin: 0, run: r)
                    let b = euclideousLaneHostBeat(elapsedSinceOrigin: Double(i + 1) * sub, origin: 0, run: r)
                    XCTAssertEqual(b - a, sub / m, accuracy: 1e-9, "rate \(rate) ×\(m): a lane step is sub/m of host time")
                }
            }
        }
    }

    // §2.3 worked example + §7.8 (origin inside the run).
    func testElapsedInARun() {
        let r = run(m: 2, R: 12, end: 20, bar: 3)   // a ×2 run over bars 3–4, 4/4
        // origin BEFORE the run: elapsed = (R − o) + (b − R)·2
        XCTAssertEqual(euclideousLaneElapsed(hostBeat: 12, origin: 4, run: r), 8, accuracy: 1e-9, "at R, elapsed = R − o")
        XCTAssertEqual(euclideousLaneElapsed(hostBeat: 14, origin: 4, run: r), 8 + 4, accuracy: 1e-9, "2 beats into a ×2 run adds 4 lane beats")
        // §7.8: origin INSIDE the run ⇒ elapsed = (b − o)·m
        XCTAssertEqual(euclideousLaneElapsed(hostBeat: 16, origin: 13, run: r), (16 - 13) * 2, accuracy: 1e-9)
    }

    // the inverse round-trips: hostBeat(elapsed(b)) ≈ b for b inside a run.
    func testInverseRoundTrips() {
        let r = run(m: 1.5, R: 8, end: 16)
        for o in [0.0, 4.0, 9.0] {   // origin before, at, and inside the run
            for b in stride(from: max(o, 8.0), to: 16.0, by: 0.37) {
                let e = euclideousLaneElapsed(hostBeat: b, origin: o, run: r)
                XCTAssertEqual(euclideousLaneHostBeat(elapsedSinceOrigin: e, origin: o, run: r), b, accuracy: 1e-9, "o \(o) b \(b)")
            }
        }
    }

    // §2.4 — the rejoin is a jump: ×2/×4 jump BACK (elapsed drops), ×½/×1½ jump FORWARD (elapsed rises) at the run-end bar line.
    func testRejoinIsAJumpBackForFastForwardForSlow() {
        let o = 0.0, L = 4.0
        // ×2 over bar 0 only (boxes: box 0 ×2, rest off); at bar 1 the lane is off ⇒ elapsed = b − o.
        let fast = euclideousRateRun(strip: strip([3, 0, 0, 0, 0, 0, 0, 0]), hostBeat: 2, beatsPerBar: L)
        let eInRun = euclideousLaneElapsed(hostBeat: 3.999, origin: o, run: fast)        // ~8 lane beats by the end of a ×2 bar
        let eAfter = euclideousLaneElapsed(hostBeat: 4.001, origin: o, run: euclideousRateRun(strip: strip([3, 0, 0, 0, 0, 0, 0, 0]), hostBeat: 4.001, beatsPerBar: L))
        XCTAssertGreaterThan(eInRun, eAfter + 2, "a ×2 run jumps BACK at its end (replays)")
        XCTAssertEqual(eAfter, 4.001, accuracy: 1e-6, "after the run, elapsed returns to b − o")
        // ×½ over bar 0: by the end only ~2 lane beats; at bar 1 it jumps forward to b − o = 4.
        let slow = euclideousRateRun(strip: strip([1, 0, 0, 0, 0, 0, 0, 0]), hostBeat: 2, beatsPerBar: L)
        let sInRun = euclideousLaneElapsed(hostBeat: 3.999, origin: o, run: slow)
        XCTAssertLessThan(sInRun, 4, "a ×½ run is behind ×1 by its end ⇒ it jumps FORWARD to rejoin")
    }

    // euclideousRateRun resolves R / end / m / runBarIndex from the strip and bar length.
    func testRateRunBeatsFromTheStrip() {
        let s = strip([0, 0, 0, 3, 3, 1, 0, 0]), L = 4.0   // boxes 4,5 (idx 3,4) ×2; box 6 (idx 5) ×½
        let r = euclideousRateRun(strip: s, hostBeat: 13, beatsPerBar: L)   // bar 3 = box idx 3
        XCTAssertTrue(r.active); XCTAssertEqual(r.startBeat, 12); XCTAssertEqual(r.endBeat, 20, "run bars 3–4, ends at bar 5"); XCTAssertEqual(r.multiplier, 2); XCTAssertEqual(r.runBarIndex, 3)
        let r2 = euclideousRateRun(strip: s, hostBeat: 21, beatsPerBar: L)  // bar 5 = box idx 5 (×½)
        XCTAssertEqual(r2.startBeat, 20); XCTAssertEqual(r2.endBeat, 24); XCTAssertEqual(r2.multiplier, 0.5)
        // the run repeats every 8 bars: bar 11 (idx 3 again) is the same shape, one cycle later
        let r3 = euclideousRateRun(strip: s, hostBeat: 45, beatsPerBar: L)  // bar 11
        XCTAssertEqual(r3.startBeat, 44); XCTAssertEqual(r3.endBeat, 52); XCTAssertEqual(r3.runBarIndex, 11)
        XCTAssertFalse(euclideousRateRun(strip: s, hostBeat: 25, beatsPerBar: L).active, "an off box is not a run")
    }

    // the map reduces to today when inactive, and gives sub/m when active.
    func testMapHelpers() {
        var m = EuclideousRateMap(active: false, strip: EuclideousRateStrip(), originBeat: 3, sub: 0.5, beatsPerBar: 4)
        XCTAssertEqual(m.elapsed(hostBeat: 10), 7, accuracy: 1e-9); XCTAssertEqual(m.stepHostLength(hostBeat: 10), 0.5)
        m = EuclideousRateMap(active: true, strip: strip([3, 0, 0, 0, 0, 0, 0, 0]), originBeat: 0, sub: 0.5, beatsPerBar: 4)
        XCTAssertEqual(m.stepHostLength(hostBeat: 1), 0.25, accuracy: 1e-9, "inside the ×2 bar a step is sub/2")
        XCTAssertEqual(m.stepHostLength(hostBeat: 5), 0.5, accuracy: 1e-9, "after it, sub")
    }
}
