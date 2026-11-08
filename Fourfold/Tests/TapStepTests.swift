//  TapStepTests.swift — TAP A STEP (2026-11-08): a single tap on a lane's rhythm strip toggles that step's hit. The pure side: `euclideousToggleStepHit` (the strip's column → the engine's finished buffer → the
//  hand-edited pattern the lane stores), the nearest-column rule, and the writers that must now cope with a hand-edited lane (a landed random roll).

import XCTest

final class TapStepTests: XCTestCase {

    private func built(_ l: EuclidLine) -> [Bool] {
        let n = max(2, min(16, l.steps))
        var cells = [Bool](repeating: false, count: n), micro = [Double](repeating: 0, count: n)
        euclideousBuildHitPatternInto(l, cells: &cells, micro: &micro)
        return cells
    }
    private func line(_ pulses: Int, _ steps: Int, rotate: Int = 0) -> EuclidLine { EuclidLine(pulses: pulses, steps: steps, rotate: rotate, noteSel: .all) }

    func testATapOnARestAddsAHitAndATapOnAHitRemovesIt() {
        var l = line(3, 8)   // x..x..x.
        let before = built(l)
        XCTAssertEqual(before, [true, false, false, true, false, false, true, false])
        euclideousToggleStepHit(&l, box: 1)
        XCTAssertEqual(built(l), [true, true, false, true, false, false, true, false])
        XCTAssertEqual(l.pulses, 4, "the HITS number follows the tap"); XCTAssertEqual(l.hitsRequested, 4)
        XCTAssertEqual(l.customHits, [true, true, false, true, false, false, true, false])
        euclideousToggleStepHit(&l, box: 0)
        XCTAssertEqual(built(l), [false, true, false, true, false, false, true, false])
        XCTAssertEqual(l.pulses, 3)
        XCTAssertEqual(euclideousSliderValueText(.hits, l), "3", "the HITS slider reads the new count")
        XCTAssertEqual(euclideousRhythmTabCounts(lane: 0, lines: [l]).hits, "3", "…and so does the tab count the MIX HITS box shows")
    }
    func testATapOutsideTheStripDoesNothing() {
        var l = line(3, 8); let copy = l
        euclideousToggleStepHit(&l, box: -1); euclideousToggleStepHit(&l, box: 8)
        XCTAssertEqual(l, copy)
    }
    func testEmptyingAndFillingALane() {
        var l = line(1, 4)
        for b in 0..<4 { if built(l)[b] { euclideousToggleStepHit(&l, box: b) } }
        XCTAssertEqual(l.pulses, 0); XCTAssertEqual(built(l), [false, false, false, false])
        for b in 0..<4 { euclideousToggleStepHit(&l, box: b) }
        XCTAssertEqual(l.pulses, 4); XCTAssertEqual(built(l), [true, true, true, true])
    }
    func testOffsetAndFlipArePreservedAndTheStripColumnIsWhatChanges() {
        var l = line(3, 8, rotate: 3); l.patternMiss = true
        let before = built(l)
        euclideousToggleStepHit(&l, box: 5)
        var expected = before; expected[5].toggle()
        XCTAssertEqual(built(l), expected, "with OFFSET 3 and FLIP on, column 5 is the one that changes")
        XCTAssertEqual(l.rotate, 3); XCTAssertEqual(l.patternMiss, true)
        XCTAssertEqual(l.pulses, l.customHits!.filter { $0 }.count, "pulses is the stored pattern's own count, the invariant customHits always carried")
    }
    func testHandEditedAndFinelyTiltedLanesToggleExactlyTheTappedColumn() {
        var seed: UInt64 = 0x9E3779B97F4A7C15
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(n)) }
        for _ in 0..<600 {
            let n = 2 + rnd(15)
            var l = line(rnd(n + 1), n, rotate: rnd(n))
            if rnd(3) == 0 { l.tilt = Double(rnd(21) - 10) / 10; if rnd(2) == 0 { l.tiltFine = l.tilt } }
            if rnd(3) == 0 { l.patternMiss = true }
            if rnd(4) == 0 { l.customHits = (0..<n).map { _ in rnd(2) == 0 } }
            if rnd(3) == 0 { l.direction = [EuclidDir.fwd, .bkw, .pingpong][rnd(3)] }
            if rnd(3) == 0 { l.offsetFraction = Double(rnd(9) + 1) / 10 }
            let box = rnd(n)
            let cell = euclideousStripBoxCell(box: box, n: n, dir: l.directionResolved, fractionalOffset: l.offsetFractionResolved > 1e-9)
            let before = built(l)
            var expected = before; expected[cell].toggle()
            euclideousToggleStepHit(&l, box: box)
            XCTAssertEqual(built(l), expected, "n \(n) box \(box)")
            XCTAssertEqual(l.pulses, l.customHits!.filter { $0 }.count)
            XCTAssertEqual(l.customHits!.count, n)
            // a second tap puts the cell back
            euclideousToggleStepHit(&l, box: box)
            XCTAssertEqual(built(l), before, "tapping the same column twice returns the displayed pattern")
        }
    }
    /// The boxes the strip lights (`euclideousHitBoxes` over the engine's tick layout) change in exactly the tapped column — FWD, BKW and PING-PONG, whole and fractional OFFSET (PING-PONG with a fraction lights a hit's box twice, so it is left out).
    func testTheLitBoxesChangeInExactlyTheTappedColumn() {
        for dir in [EuclidDir.fwd, .bkw, .pingpong] {
            for fraction in [0.0, 0.4] where !(dir == .pingpong && fraction > 0) {
                for n in [5, 8, 16] {
                    for box in 0..<n {
                        var l = line(3, n, rotate: 1); l.direction = dir; if fraction > 0 { l.offsetFraction = fraction }
                        func boxes(_ l: EuclidLine) -> [Bool] {
                            var cells = [Bool](repeating: false, count: n), micro = [Double](repeating: 0, count: n)
                            euclideousBuildHitPatternInto(l, cells: &cells, micro: &micro)
                            var tc = [Bool](repeating: false, count: 32), td = [Double](repeating: 0, count: 32)
                            let cl = euclideousHitLayoutInto(cells: cells, micro: micro, fraction: l.offsetFractionResolved, n: n, dir: dir, outCells: &tc, outDelay: &td)
                            return euclideousHitBoxes(layoutCells: Array(tc[0..<cl]), n: n, dir: dir)
                        }
                        let before = boxes(l)
                        var expected = before; expected[box].toggle()
                        euclideousToggleStepHit(&l, box: box)
                        XCTAssertEqual(boxes(l), expected, "\(dir) fraction \(fraction) n \(n) box \(box)")
                    }
                }
            }
        }
    }

    func testTheNearestColumnTakesTheTapGapsAndMarginsIncluded() {
        let xs: [CGFloat] = [6, 30, 54, 78], w: CGFloat = 22   // 2 pt gaps, 6 pt margin
        XCTAssertEqual(euclideousStripStepAtX(0, columnMinXs: xs, columnW: w), 0, "the left margin belongs to the first column")
        XCTAssertEqual(euclideousStripStepAtX(28.5, columnMinXs: xs, columnW: w), 0, "a gap goes to its nearer neighbour")
        XCTAssertEqual(euclideousStripStepAtX(29.5, columnMinXs: xs, columnW: w), 1)
        XCTAssertEqual(euclideousStripStepAtX(65, columnMinXs: xs, columnW: w), 2)
        XCTAssertEqual(euclideousStripStepAtX(500, columnMinXs: xs, columnW: w), 3, "past the end is the last column")
        XCTAssertNil(euclideousStripStepAtX(10, columnMinXs: [], columnW: w))
    }

    func testALandedRandomRhythmReplacesAHandEditedPattern() {
        var l = line(3, 8); euclideousToggleStepHit(&l, box: 1)
        XCTAssertNotNil(l.customHits)
        euclideousRandomCommitPendingRoll(EuclideousPendingRoll(tab: .rhythm, landingBeat: 8, steps: 8, pulses: 5, rotate: 2), into: &l)
        XCTAssertNil(l.customHits, "the roll's Euclid pattern plays, not the old hand-edited one")
        XCTAssertEqual(l.pulses, 5); XCTAssertEqual(built(l).filter { $0 }.count, 5)
        // a riff roll leaves the rhythm alone
        var m = line(3, 8); euclideousToggleStepHit(&m, box: 1)
        euclideousRandomCommitPendingRoll(EuclideousPendingRoll(tab: .riff, landingBeat: 8), into: &m)
        XCTAssertNotNil(m.customHits)
    }
}
