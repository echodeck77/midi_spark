//  RhythmPolishTests.swift
//  RHYTHM POLISH ferry (2026-10-22): "prominent HITS, continuous OFFSET and TILT, FLIP HITS, and restart tiles that sweep". The pure surface: the model + persistence (§4, test 11), the slider functions (§2.2/§2.4, tests 3 and 7),
//  and — as the ferry's steps land — the hit-timing engine (§5), the layout (§1) and the restart tiles (§6). The Router-level goldens live in RouterTests next to the harness they need.

import XCTest

final class RhythmPolishTests: XCTestCase {

    private func decode(_ json: String) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: Data(json.utf8)) }
    private func roundTrip(_ l: EuclidLine) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l)) }

    // MARK: 11. persistence

    func testTheNewFieldsRoundTripAndNilDecodesToTodaysBehaviour() throws {
        var l = EuclidLine(pulses: 5, steps: 8, rotate: 3, noteSel: .all)
        l.offsetFraction = 0.25; l.tiltFine = -0.4; l.tilt = -0.4
        let back = try roundTrip(l)
        XCTAssertEqual(back.offsetFraction, 0.25); XCTAssertEqual(back.tiltFine, -0.4); XCTAssertEqual(back, l)
        let old = try decode(#"{"target":0,"pulses":5,"steps":8,"rotate":3,"tilt":0.5}"#)
        XCTAssertNil(old.offsetFraction); XCTAssertNil(old.tiltFine)
        XCTAssertEqual(old.offsetFractionResolved, 0); XCTAssertFalse(old.tiltIsFine)
        XCTAssertEqual(old.tiltResolved, 0.5, "with tiltFine nil the resolved TILT is exactly the stored `tilt`")
        // nothing is written for a lane that never used them
        let json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(EuclidLine())) as! [String: Any]
        XCTAssertNil(json["offsetFraction"]); XCTAssertNil(json["tiltFine"])
    }
    func testTheNewFieldsDecodeTolerantlyAndClamped() throws {
        XCTAssertNil(try decode(#"{"offsetFraction":"half","tiltFine":[1]}"#).offsetFraction, "a wrong-typed value is missing, never a whole-session reset")
        XCTAssertNil(try decode(#"{"offsetFraction":"half","tiltFine":[1]}"#).tiltFine)
        XCTAssertLessThan(try decode(#"{"offsetFraction":1.5}"#).offsetFractionResolved, 1)
        XCTAssertEqual(try decode(#"{"offsetFraction":-0.2}"#).offsetFractionResolved, 0)
        XCTAssertEqual(try decode(#"{"tiltFine":3}"#).tiltFine, 1); XCTAssertEqual(try decode(#"{"tiltFine":-3}"#).tiltFine, -1)
        XCTAssertEqual(try decode(#"{"tilt":0.2,"tiltFine":0.7}"#).tiltResolved, 0.7, "the fine value wins")
    }
    func testTheSnapshotBuilderLiteralCarriesBothFields() {
        var m = Machine(machineID: "gold", type: .euclid)
        var lines = (0..<4).map { _ in EuclidLine(noteSel: .all) }
        lines[0].offsetFraction = 0.6; lines[2].tiltFine = 0.35; lines[2].tilt = 0.35
        m.paramsA.euclidLines = lines
        let built = SnapshotBuilder.build(from: PluginState(machines: [m], scenes: [SceneState.empty()]))
        let out = built.machines.first { $0.a.euclidLines.count == 4 }?.a.euclidLines
        XCTAssertEqual(out?[0].offsetFraction, 0.6, "a fresh-literal rebuild that forgot the field would silently reset it on the next render")
        XCTAssertEqual(out?[2].tiltFine, 0.35)
        XCTAssertNil(out?[1].offsetFraction); XCTAssertNil(out?[1].tiltFine)
    }

    // MARK: 3. the STEPS setter keeps the fraction (and the §2.5 example still holds with fraction 0)

    func testAStepsChangeKeepsOffsetFractionAndTheRequestedMemory() {
        var l = EuclidLine(pulses: 3, steps: 8, noteSel: .all)
        euclideousSliderCommit(.offset, &l, snapshot: l, newValue: 5.25)
        XCTAssertEqual(l.offsetRequested, 5); XCTAssertEqual(l.offsetFractionResolved, 0.25, accuracy: 1e-12)
        euclideousSliderCommit(.steps, &l, snapshot: l, newValue: 6)
        XCTAssertEqual(l.offsetFractionResolved, 0.25, accuracy: 1e-12, "STEPS keeps offsetFraction as it is (4.2)")
        XCTAssertEqual(euclideousSliderRange(.offset, l).value, 5, "at 6 steps the slider tops out at STEPS−1 = 5; the stored fraction is untouched")
        euclideousSliderCommit(.steps, &l, snapshot: l, newValue: 8)
        XCTAssertEqual(euclideousSliderRange(.offset, l).value, 5.25, accuracy: 1e-9, "growing back restores the offset left behind, fraction included")
        // §2.5's example with fraction 0: offset 7 on 8 steps, shrink to 4, grow back → 7 again
        var e = EuclidLine(pulses: 3, steps: 8, noteSel: .all)
        euclideousSliderCommit(.offset, &e, snapshot: e, newValue: 7)
        XCTAssertNil(e.offsetFraction)
        euclideousSliderCommit(.steps, &e, snapshot: e, newValue: 4)
        XCTAssertEqual(euclideousSliderRange(.offset, e).value, 3)
        euclideousSliderCommit(.steps, &e, snapshot: e, newValue: 8)
        XCTAssertEqual(euclideousSliderRange(.offset, e).value, 7)
    }

    // MARK: 2.2 / 2.4 — OFFSET and TILT as continuous controls

    func testOffsetCommitsItsWholePartAndItsFractionAndReadsThemBack() {
        var l = EuclidLine(pulses: 3, steps: 8, noteSel: .all)
        euclideousSliderCommit(.offset, &l, snapshot: l, newValue: 5.25)
        XCTAssertEqual(l.rotate, 3, "the integer offset is stored as it always was: (8 − 5) % 8")
        XCTAssertEqual(l.offsetRequested, 5)
        XCTAssertEqual(euclideousSliderValueText(.offset, l), "5.25")
        XCTAssertEqual(euclideousSliderAccessibilityValueText(.offset, l), "5.25 steps")
        euclideousSliderCommit(.offset, &l, snapshot: l, newValue: 5)
        XCTAssertNil(l.offsetFraction, "a whole offset stores no fraction")
        XCTAssertEqual(euclideousSliderValueText(.offset, l), "5")
        euclideousSliderCommit(.offset, &l, snapshot: l, newValue: 1)
        XCTAssertEqual(euclideousSliderAccessibilityValueText(.offset, l), "1 step")
        // a comet-bar drag past the ends still wraps (mod STEPS) and keeps the fraction
        euclideousSliderCommit(.offset, &l, snapshot: l, newValue: 8.25)
        XCTAssertEqual(l.offsetRequested, 0); XCTAssertEqual(l.offsetFractionResolved, 0.25, accuracy: 1e-12)
        // 7.5 on 8 steps is representable in the model (the slider tops out at 7)
        l.offsetFraction = 0.5; l.offsetRequested = 7; l.rotate = 1
        XCTAssertEqual(euclideousSliderRange(.offset, l).value, 7, "the slider's range tops out at STEPS−1")
        XCTAssertEqual(euclideousSliderValueText(.offset, l), "7.50")
    }
    func testOffsetDoubleTapRevertAndTheTopOfTheTrack() {
        var l = EuclidLine(pulses: 3, steps: 8, noteSel: .all)
        let snap = l
        euclideousSliderCommit(.offset, &l, snapshot: snap, newValue: 4.4)
        euclideousSliderRevert(.offset, &l, snapshot: snap)
        XCTAssertNil(l.offsetFraction); XCTAssertEqual(l.rotate, 0)
        euclideousSliderCommit(.offset, &l, snapshot: snap, newValue: 4.4)
        euclideousSliderDoubleTapDefault(.offset, &l)
        XCTAssertNil(l.offsetFraction, "double-tap clears the fraction too — it is an OFFSET writer"); XCTAssertEqual(l.rotate, 0)
        // value ↔ position: a continuous mapping against the existing 0…STEPS−1 track
        XCTAssertEqual(euclideousSliderValueAt(.offset, l, frac: 0.5), 3.5, accuracy: 1e-12)
        XCTAssertEqual(euclideousSliderValueAt(.offset, l, frac: 1), 7); XCTAssertEqual(euclideousSliderValueAt(.offset, l, frac: 0), 0)
    }
    func testTiltWritesBothFieldsAndShowsAWholePercent() {
        var l = EuclidLine(pulses: 3, steps: 8, noteSel: .all)
        euclideousSliderCommit(.tilt, &l, snapshot: l, newValue: 0.404)
        XCTAssertEqual(l.tilt, 0.404); XCTAssertEqual(l.tiltFine, 0.404); XCTAssertTrue(l.tiltIsFine)
        XCTAssertEqual(euclideousSliderValueText(.tilt, l), "+40%")
        euclideousSliderCommit(.tilt, &l, snapshot: l, newValue: -0.124)
        XCTAssertEqual(euclideousSliderValueText(.tilt, l), "−12%")
        let snap = l
        euclideousSliderDoubleTapDefault(.tilt, &l)
        XCTAssertEqual(l.tilt, 0); XCTAssertEqual(l.tiltFine, 0); XCTAssertEqual(euclideousSliderValueText(.tilt, l), "0%")
        euclideousSliderRevert(.tilt, &l, snapshot: snap)
        XCTAssertEqual(l.tilt, -0.124); XCTAssertEqual(l.tiltFine, -0.124)
        // a fresh lane's value text, and the pre-existing "tilt only" lane keeps reading as it did (rounded timing)
        var old = EuclidLine(pulses: 3, steps: 8, noteSel: .all); old.tilt = 0.3
        XCTAssertFalse(old.tiltIsFine); XCTAssertEqual(euclideousSliderValueText(.tilt, old), "+30%")
    }

    // MARK: 7. the detents

    func testTheOffsetDetentSnapsWithin008OfAWholeStepAndReleasesPastIt() {
        XCTAssertEqual(euclideousOffsetDetent(2.08), 2); XCTAssertEqual(euclideousOffsetDetent(1.92), 2)
        XCTAssertEqual(euclideousOffsetDetent(2.0801), 2.0801, accuracy: 1e-12); XCTAssertEqual(euclideousOffsetDetent(2.5), 2.5)
        XCTAssertEqual(euclideousOffsetDetent(0.05), 0); XCTAssertEqual(euclideousOffsetDetent(6.95), 7)
        // stateless: moving back inside the radius re-snaps, moving out reads as itself
        XCTAssertEqual([2.0, 2.04, 2.09, 2.2, 2.09, 2.04].map(euclideousOffsetDetent), [2, 2, 2.09, 2.2, 2.09, 2])
    }
    func testTheTiltDetentSnapsWithin3PercentOfZero() {
        XCTAssertEqual(euclideousTiltDetent(0.03), 0); XCTAssertEqual(euclideousTiltDetent(-0.03), 0); XCTAssertEqual(euclideousTiltDetent(0.0), 0)
        XCTAssertEqual(euclideousTiltDetent(0.0301), 0.0301); XCTAssertEqual(euclideousTiltDetent(-0.5), -0.5)
        // through the slider's own mapping: dead centre of the travel is 0; ±3 % of the VALUE (1.5 % of the travel) still snaps, ±6 % of the value (3 % of the travel) does not
        let l = EuclidLine(pulses: 3, steps: 8, noteSel: .all)
        XCTAssertEqual(euclideousSliderValueAtDetented(.tilt, l, frac: 0.5), 0)
        XCTAssertEqual(euclideousSliderValueAtDetented(.tilt, l, frac: 0.5 + 0.014), 0)
        XCTAssertEqual(euclideousSliderValueAtDetented(.tilt, l, frac: 0.5 + 0.03), 0.06, accuracy: 1e-12)
        XCTAssertEqual(euclideousSliderValueAtDetented(.offset, l, frac: 3.05 / 7), 3, "OFFSET through the slider mapping")
        XCTAssertEqual(euclideousSliderValueAtDetented(.hits, l, frac: 1), 8, "other fields are untouched by the detent")
    }

    func testTheAdjustableActionsMoveByWholeStepsAndFivePercent() {
        XCTAssertEqual(euclideousSliderAccessibilityTarget(.offset, current: 5.25, increment: true), 6)
        XCTAssertEqual(euclideousSliderAccessibilityTarget(.offset, current: 5.25, increment: false), 5)
        XCTAssertEqual(euclideousSliderAccessibilityTarget(.offset, current: 5, increment: true), 6)
        XCTAssertEqual(euclideousSliderAccessibilityTarget(.offset, current: 5, increment: false), 4)
        XCTAssertEqual(euclideousSliderAccessibilityTarget(.tilt, current: 0.1, increment: true), 0.15, accuracy: 1e-12)
        XCTAssertEqual(euclideousSliderAccessibilityTarget(.tilt, current: 0.1, increment: false), 0.05, accuracy: 1e-12)
        XCTAssertEqual(euclideousSliderAccessibilityTarget(.hits, current: 3, increment: true), 4)
        XCTAssertEqual(euclideousSliderAccessibilityTarget(.gate, current: 0.5, increment: true), 0.51, accuracy: 1e-12)
    }

    // MARK: LANE LOCK — the two fields lock with the controls that write them

    func testALockHoldsTheFractionAndTheFineTilt() {
        var l = EuclidLine(pulses: 3, steps: 8, rotate: 2, noteSel: .all)
        let locked = LaneLockFields(line: l)
        XCTAssertFalse(euclideousLockDeviated(line: l, from: locked))
        l.offsetFraction = 0.3
        XCTAssertTrue(euclideousLockDeviated(line: l, from: locked), "a fractional OFFSET is a deviation")
        XCTAssertEqual(euclideousLockChangedControls(from: locked, to: l), [.offset, .cometStrip])
        var back = l; locked.applied(to: &back)
        XCTAssertNil(back.offsetFraction, "the snap restores it exactly")
        l.offsetFraction = nil; l.tilt = 0.4; l.tiltFine = 0.4
        XCTAssertTrue(euclideousLockDeviated(line: l, from: locked))
        // flipping only the rounded/unrounded marker (same value) is a deviation too: it sounds different
        var a = EuclidLine(pulses: 3, steps: 8, noteSel: .all); a.tilt = 0.4
        var b = a; b.tiltFine = 0.4
        XCTAssertTrue(euclideousLockDeviated(line: b, from: LaneLockFields(line: a)))
    }

    // MARK: 5. the hit layout — the builder and the buffer → tick-space mapping

    /// With no fine TILT the one builder IS the pipeline the engine always ran, and with no fraction the tick layout IS `buf[readIndex(raw)]` with every delay 0.
    func testTheBuilderAndTheLayoutReproduceTodayWhenThereIsNoTiming() {
        var checked = 0
        for steps in 2...16 {
            for pulses in stride(from: 0, through: steps, by: max(1, steps / 4)) {
                for rotate in [0, 1, steps - 1, steps + 2] {
                    for tilt in [0.0, 0.3, -0.7, 1, -1] {
                        for flip in [false, true] {
                            var cells = [Bool](repeating: false, count: 16), micro = [Double](repeating: 9, count: 16)
                            euclideousHitPatternInto(pulses: pulses, steps: steps, rotate: rotate, tilt: tilt, fine: false, customHits: nil, patternMiss: flip, cells: &cells, micro: &micro)
                            var ref = [Bool](repeating: false, count: 16)
                            euclidPatternInto(&ref, pulses: pulses, steps: steps, rotation: 0)
                            if tilt != 0 { euclidTiltPattern(&ref, pulses: pulses, steps: steps, tilt: tilt) }
                            euclidRotateBuffer(&ref, steps: steps, rotation: rotate)
                            if flip { for i in 0..<steps { ref[i].toggle() } }
                            XCTAssertEqual(Array(cells[0..<steps]), Array(ref[0..<steps]), "\(pulses)/\(steps) rot \(rotate) tilt \(tilt) flip \(flip)")
                            XCTAssertTrue(micro[0..<steps].allSatisfy { $0 == 0 }, "rounded TILT carries no in-step positions")
                            for dir in [EuclidDir.fwd, .bkw, .pingpong] {
                                var tc = [Bool](repeating: false, count: 32), td = [Double](repeating: 0, count: 32)
                                let cl = euclideousHitLayoutInto(cells: cells, micro: micro, fraction: 0, n: steps, dir: dir, outCells: &tc, outDelay: &td)
                                XCTAssertEqual(cl, euclidCycleLen(dir, n: steps))
                                for raw in 0..<cl {
                                    XCTAssertEqual(tc[raw], cells[euclidReadIndex(raw, n: steps, dir: dir)], "\(dir) tick \(raw)")
                                    XCTAssertEqual(td[raw], 0)
                                }
                                checked += 1
                            }
                        }
                    }
                }
            }
        }
        XCTAssertGreaterThan(checked, 3000)
    }
    /// Whatever the fraction, direction and fine TILT: every buffer hit is played (twice under PING-PONG), no two share a cell, and a delay never leaves its cell.
    func testTheLayoutNeverLosesDoublesOrOverlapsAHit() {
        var seed: UInt64 = 42
        func rnd(_ n: Int) -> Int { seed = seed &* 6364136223846793005 &+ 1442695040888963407; return Int((seed >> 33) % UInt64(max(1, n))) }
        for _ in 0..<3000 {
            let steps = 2 + rnd(15), pulses = 1 + rnd(steps), dir = [EuclidDir.fwd, .bkw, .pingpong][rnd(3)]
            let tilt = rnd(3) == 0 ? 0 : Double(rnd(199) - 99) / 100
            var cells = [Bool](repeating: false, count: 16), micro = [Double](repeating: 0, count: 16)
            euclideousHitPatternInto(pulses: pulses, steps: steps, rotate: rnd(steps), tilt: tilt, fine: rnd(4) != 0, customHits: nil, patternMiss: rnd(5) == 0, cells: &cells, micro: &micro)
            let f = rnd(4) == 0 ? 0 : Double(rnd(199)) / 100        // up to 1.98: a FOLLOW lane adds its partner's fraction
            var tc = [Bool](repeating: false, count: 32), td = [Double](repeating: 0, count: 32)
            let cl = euclideousHitLayoutInto(cells: cells, micro: micro, fraction: f, n: steps, dir: dir, outCells: &tc, outDelay: &td)
            let want = cells[0..<steps].filter { $0 }.count * (dir == .pingpong ? 2 : 1)
            XCTAssertEqual(tc[0..<cl].filter { $0 }.count, want, "\(pulses)/\(steps) \(dir) f \(f) tilt \(tilt)")
            for raw in 0..<cl { XCTAssertTrue(td[raw] >= 0 && td[raw] < 1, "delay \(td[raw])"); if !tc[raw] { XCTAssertEqual(td[raw], 0) } }
        }
    }
    func testEveryHitIsDrawnInTheBoxItsStartTimeFallsIn() {
        // FWD is the buffer; BKW with a fraction moves each hit one box (earlier in time = further right on the bar)
        var tc = [Bool](repeating: false, count: 32), td = [Double](repeating: 0, count: 32)
        let cells: [Bool] = [true, false, false, true, false, false, true, false]
        var cl = euclideousHitLayoutInto(cells: cells, micro: [Double](repeating: 0, count: 8), fraction: 0.5, n: 8, dir: .fwd, outCells: &tc, outDelay: &td)
        XCTAssertEqual(euclideousHitBoxes(layoutCells: Array(tc[0..<cl]), n: 8, dir: .fwd), cells, "a fraction under FWD leaves every hit in its own box")
        cl = euclideousHitLayoutInto(cells: cells, micro: [Double](repeating: 0, count: 8), fraction: 0.5, n: 8, dir: .bkw, outCells: &tc, outDelay: &td)
        XCTAssertEqual(euclideousHitBoxes(layoutCells: Array(tc[0..<cl]), n: 8, dir: .bkw), [false, true, false, false, true, false, false, true],
                       "BKW: half a step earlier on the clock is the box to the right")
        cl = euclideousHitLayoutInto(cells: cells, micro: [Double](repeating: 0, count: 8), fraction: 0, n: 8, dir: .bkw, outCells: &tc, outDelay: &td)
        XCTAssertEqual(euclideousHitBoxes(layoutCells: Array(tc[0..<cl]), n: 8, dir: .bkw), cells, "no fraction: the buffer itself")
    }

    // MARK: 12. geometry

    func testTheRhythmTabGeometryAtTheReferenceCard() {
        let g = euclideousRhythmTabLayout(cardWidth: 358.5, cardHeight: 312)
        // upper zone y 94–218, the right half at x 181.25, 167.25 wide: three rows, sp4 apart
        XCTAssertEqual(g.offsetRow.minY, 94); XCTAssertEqual(g.tiltRow.minY, 136.6667, accuracy: 1e-3); XCTAssertEqual(g.directionRow.minY, 179.3333, accuracy: 1e-3)
        for r in [g.offsetRow, g.tiltRow, g.directionRow] {
            XCTAssertEqual(r.minX, 181.25, accuracy: 1e-9); XCTAssertEqual(r.width, 167.25, accuracy: 1e-9); XCTAssertEqual(r.height, 116.0 / 3, accuracy: 1e-9)
        }
        XCTAssertEqual(g.directionRow.maxY, 218, accuracy: 1e-9, "the three rows exactly fill the upper zone")
        XCTAssertEqual(g.directionButtonW, 38.8125, accuracy: 1e-9)
        XCTAssertEqual(g.hitsTile.height, 124); XCTAssertEqual(g.hitsTile.minX, 10); XCTAssertEqual(g.stepsTile.minX, g.hitsTile.maxX + 4, accuracy: 1e-9)
        // lower zone y 222–302: the tiles sit in the rate grid's two rows (38 + 4 + 38)
        XCTAssertEqual(g.rhythmTile.minY, 222); XCTAssertEqual(g.melodyTile.minY, 264); XCTAssertEqual(g.melodyTile.maxY, 302)
        XCTAssertEqual(g.rhythmTile.height, 38); XCTAssertEqual(g.melodyTile.height, 38)
        // SOURCE WINS (reported): the right group is x 187.75, 160.75 wide — (338.5 − 17) / 2 — not the ferry's 188.5 / 160
        XCTAssertEqual(g.rhythmTile.minX, 187.75, accuracy: 1e-9); XCTAssertEqual(g.rhythmTile.width, 160.75, accuracy: 1e-9)
        XCTAssertEqual(g.melodyTile.minX, g.rhythmTile.minX); XCTAssertEqual(g.melodyTile.width, g.rhythmTile.width)
        XCTAssertEqual(g.rhythmTile.maxX, 348.5, accuracy: 1e-9, "the group still ends at the card's right inset")
        XCTAssertEqual(g.rateGroup.height, g.melodyTile.maxY - g.rhythmTile.minY, accuracy: 1e-9, "the restart section is exactly the size of the rate section")
    }
    func testTheTilesAndRowsInEveryPageLayout() {
        // The lane cards the page layout gives at the iPad sizes we ship to; every one keeps the structure: three equal right-half rows, two 38-tall tiles in the rate grid's rows.
        var report: [String] = []
        for size in [CGSize(width: 1366, height: 1024), CGSize(width: 1194, height: 834), CGSize(width: 1112, height: 834), CGSize(width: 1024, height: 768), CGSize(width: 834, height: 1194), CGSize(width: 768, height: 1024)] {
            let pl = euclideousPageLayout(size: size)
            let card = pl.lanes[0]
            let g = euclideousRhythmTabLayout(cardWidth: card.width, cardHeight: card.height)
            let upperH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: card.height) - 84
            XCTAssertEqual(g.offsetRow.height, (upperH - 8) / 3, accuracy: 1e-9)
            XCTAssertEqual(g.directionRow.maxY - g.offsetRow.minY, upperH, accuracy: 1e-9, "\(size): the three rows split the upper zone's height equally")
            XCTAssertEqual(g.rhythmTile.height, 38); XCTAssertEqual(g.melodyTile.minY - g.rhythmTile.maxY, 4)
            XCTAssertEqual(g.rhythmTile.width, (card.width - 20 - 17) / 2, accuracy: 1e-9)
            report.append(String(format: "%.0f×%.0f: card %.2f×%.2f · tiles %.2f×38 · right rows %.2f tall · direction buttons %.2f", size.width, size.height, card.width, card.height, g.rhythmTile.width, g.offsetRow.height, g.directionButtonW))
        }
        print("RHYTHM POLISH tile sizes per layout:\n" + report.joined(separator: "\n"))
    }
    func testTheHitsHeroBlockSitsOnTheFilledPartAndClampsAtTheTopAndAboveTheLabel() {
        typealias H = EuclideousHitsHero
        let tileH: CGFloat = 124, labelTop = H.labelBackingTop(tileH: tileH)
        XCTAssertEqual(H.blockH, 48); XCTAssertEqual(labelTop, 103, "the label's backing: 5 up from the bottom, 12 + 2 × 2 tall")
        func top(_ hits: Int, of steps: Int) -> CGFloat { euclideousHitsHeroTop(tileH: tileH, fillFraction: Double(hits) / Double(steps)) }
        // 0 hits: the lowest clamped position — 4 pt above the label's backing, fully inside the tile
        XCTAssertEqual(top(0, of: 9), labelTop - 4 - H.blockH, accuracy: 1e-9); XCTAssertEqual(top(0, of: 9) + H.blockH, labelTop - 4)
        XCTAssertLessThan(top(0, of: 9) + H.blockH, tileH)
        // 1 of 9: the fill is still short (its centre is below the clamp), so it is clamped too
        XCTAssertEqual(top(1, of: 9), labelTop - 4 - H.blockH, accuracy: 1e-9)
        // a full tile: the centre of the filled part is the tile's, the block is centred on it and ≥ 6 pt below the top
        let full = top(9, of: 9)
        XCTAssertEqual(full, (6 + tileH) / 2 - H.blockH / 2, accuracy: 1e-9); XCTAssertGreaterThanOrEqual(full, 6)
        // monotone: more hits never move the block down
        var last = CGFloat.infinity
        for h in 0...9 { let t = top(h, of: 9); XCTAssertLessThanOrEqual(t, last + 1e-9); last = t }
        // a tile too short for both limits keeps the 6 pt top clearance
        XCTAssertEqual(euclideousHitsHeroTop(tileH: 60, fillFraction: 0), 6)
    }
    func testTheHitsCaptionColoursArePaleLaneColours() {
        let lanes: [(Double, Double, Double)] = [(0.95, 0.35, 0.35), (0.35, 0.75, 0.95), (0.95, 0.75, 0.25), (0.55, 0.85, 0.45)]
        func hex(_ c: (r: Int, g: Int, b: Int)) -> String { String(format: "#%02X%02X%02X", c.r, c.g, c.b) }
        XCTAssertEqual(lanes.map { hex(euclideousHitsCaptionRGB($0)) }, ["#F2CDD0", "#CCE7F6", "#F2E7C9", "#D9EDD6"],
                       "75 % toward #F2F4F7 in sRGB bytes. The ferry quotes L1 as #F7C1C1, which this rule cannot produce (0xF7 is above both ends' red) — reported")
    }
    func testFlipHitsIsTheSameToggleAsInv() {
        // behaviour is the lane's `patternMiss`; the pattern it makes is the engine's own (the 7-step lane's gaps)
        var l = EuclidLine(pulses: 3, steps: 7, noteSel: .all)
        let plain = euclideousBuildPattern(l).buf
        l.patternMiss = true
        let flipped = euclideousBuildPattern(l).buf
        XCTAssertEqual((0..<7).map { flipped[$0] }, (0..<7).map { !plain[$0] }, "FLIP HITS plays exactly the steps that did not hit")
    }
}
