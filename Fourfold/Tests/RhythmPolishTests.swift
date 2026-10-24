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

    // MARK: 8 / 9. the restart tiles' state

    private func tileCfg(_ pulses: Int, _ steps: Int, dir: EuclidDir = .fwd, rhythm: [UInt8]? = nil, melody: [UInt8]? = nil, advanceStep: Bool = false, every: Int = 1,
                         riffLength: Int = 8, riffDir: RiffDir = .forward, stride: Int = 1, shift: Int = 0) -> EuclideousWalkLaneConfig {
        var l = EuclidLine(pulses: pulses, steps: steps, noteSel: .all)
        l.rate = .r1_8; l.direction = dir; l.restartRhythmBars = rhythm; l.restartMelodyPasses = melody
        l.riffAdvanceStep = advanceStep; l.riffAdvanceEvery = every; l.riffLength = riffLength; l.riffDir = riffDir; l.riffStride = stride; l.riffRotate = shift
        return euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
    }
    func testRhythmTileSweepAndTrack() {
        // 8 × 1/8, restart every 2 bars (8 beats): the sweep is a quarter of the way at beat 2, back to 0 at the restart; 3 slots lit at beat 1.25 and nothing is ghosted (the pass fits the cycle)
        let a = tileCfg(5, 8, rhythm: [2])
        XCTAssertEqual(restartTileState(.rhythm, cfg: a, beat: 2, running: true).progress!, 0.25, accuracy: 1e-9)
        XCTAssertEqual(restartTileState(.rhythm, cfg: a, beat: 8, running: true).progress!, 0, accuracy: 1e-9)
        XCTAssertEqual(restartTileState(.rhythm, cfg: a, beat: 7.999, running: true).progress!, 7.999 / 8, accuracy: 1e-9, "full just before the restart, then it drops")
        let a125 = restartTileState(.rhythm, cfg: a, beat: 1.25, running: true)
        XCTAssertEqual(a125.count, 8); XCTAssertEqual(a125.litCount, 3); XCTAssertEqual(a125.ghostCount, 0)
        XCTAssertEqual(a125.restartsInText, "next restart in 2 bars"); XCTAssertEqual(restartTileState(.rhythm, cfg: a, beat: 6.5, running: true).restartsInText, "next restart this bar")
        // 7 × 1/8 (a 3.5-beat pass) with a bar restart: the second pass is cut after one step — at beat 3.6 one slot is lit and six are ghosts; in the next bar (4.1) it is one lit, six unlit
        let b = tileCfg(7, 7, rhythm: [1])
        let b36 = restartTileState(.rhythm, cfg: b, beat: 3.6, running: true)
        XCTAssertEqual(b36.count, 7); XCTAssertEqual(b36.litCount, 1); XCTAssertEqual(b36.ghostCount, 6)
        let b41 = restartTileState(.rhythm, cfg: b, beat: 4.1, running: true)
        XCTAssertEqual(b41.litCount, 1); XCTAssertEqual(b41.ghostCount, 0)
        // and the first pass of a bar fits (3.5 < 4): no ghosts, 2 lit at beat 0.6
        XCTAssertEqual(restartTileState(.rhythm, cfg: b, beat: 0.6, running: true).ghostCount, 0)
        // stopped: the structure stays (the ghosts), nothing lit, no sweep
        let stopped = restartTileState(.rhythm, cfg: b, beat: 3.6, running: false)
        XCTAssertEqual(stopped.ghostCount, 6); XCTAssertEqual(stopped.litCount, 0); XCTAssertNil(stopped.progress); XCTAssertEqual(stopped.restartsInText, "")
        // FREE: lit cells (grey in the painter), no sweep, no ghosts — however the pass relates to the bar
        let free = restartTileState(.rhythm, cfg: tileCfg(7, 7), beat: 3.6, running: true)
        XCTAssertTrue(free.isFree); XCTAssertNil(free.progress); XCTAssertEqual(free.ghostCount, 0); XCTAssertGreaterThan(free.litCount, 0)
        // the acceptance lane: 9 steps at 1/4 (a 9-beat pass), 1 BAR: the sweep crosses once per bar; 4 slots lit at beat 3.9 and 5 ghosts
        var l = EuclidLine(pulses: 4, steps: 9, noteSel: .all); l.rate = .r1_4; l.restartRhythmBars = [1]; l.restartMelodyPasses = [2]
        let acc = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        let s39 = restartTileState(.rhythm, cfg: acc, beat: 3.9, running: true)
        XCTAssertEqual(s39.litCount, 4); XCTAssertEqual(s39.ghostCount, 5); XCTAssertEqual(s39.count, 9)
        XCTAssertEqual(restartTileState(.rhythm, cfg: acc, beat: 4, running: true).progress!, 0, accuracy: 1e-9, "empties on the bar line")
        // a lap over 16 slots (9 steps PING-PONG = 18) is one continuous bar
        let pp = restartTileState(.rhythm, cfg: tileCfg(4, 9, dir: .pingpong), beat: 4.5, running: true)
        XCTAssertTrue(pp.continuous); XCTAssertEqual(pp.count, 18); XCTAssertEqual(pp.litFraction, 4.5 / 9, accuracy: 1e-9)
    }

    // MARK: RESTART TILES ferry — the MELODY track: one cell per riff note

    /// The recording's lane: E(5,8) at 1/8 (hits on steps 0,2,4,5,7: beats 0, 1, 2, 2.5, 3.5 of every 4-beat pass), riff LEN 8, REV, ADV HIT, ADVANCE EVERY 2, rhythm 1 BAR.
    private func recordingCfg(melody: [UInt8]?, every: Int = 2) -> EuclideousWalkLaneConfig { tileCfg(5, 8, rhythm: [1], melody: melody, every: every, riffDir: .reverse) }
    private let recordingHitBeats: [Double] = [0, 1, 2, 2.5, 3.5, 4, 5, 6, 6.5, 7.5, 8, 9, 10, 10.5, 11.5, 12, 13, 14, 14.5, 15.5]

    func testTheRecordedLaneShowsEightCellsInWalkOrderLitInTurnWithThreeGhosts() {
        let cfg = recordingCfg(melody: [2])
        let order = euclideousRiffCycleOrder(dir: .reverse, length: 8, stride: 1, shift: 0)
        XCTAssertEqual((0..<8).map { order.column(ofCell: $0) + 1 }, [8, 7, 6, 5, 4, 3, 2, 1], "REV: the walk visits column 8 first")
        XCTAssertEqual(order.period, 8)
        // over one restart period (2 passes = 10 hits): cells 1–5 light in turn, each staying for the two hits that play it, and 3 are ghosts the whole time
        for (k, beat) in recordingHitBeats.prefix(10).enumerated() {
            let st = restartTileState(.melody, cfg: cfg, beat: beat + 0.1, running: true)
            XCTAssertEqual(st.count, 8)
            XCTAssertEqual(st.litCount, (k + 2) / 2, "after hit \(k + 1): hits 1–2 play cell 1, 3–4 cell 2, …")
            XCTAssertEqual(st.ghostCount, 3, "hit \(k + 1): the walk can only reach 5 of 8 notes before the melody restart")
            XCTAssertEqual(st.reachable, 5)
            XCTAssertEqual(st.notesThisCycleText, "5 of 8 notes this cycle")
            for i in 0..<8 { XCTAssertEqual(st.cell(i), UInt8(i < (k + 2) / 2 ? 1 : (i >= 5 ? 2 : 0)), "cell \(i + 1) after hit \(k + 1)") }
        }
        // the ghost count is the RIFF tab's NEVER PLAY count
        let ro = euclideousRiffReadout(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: euclidCycleLen(cfg.dir, n: cfg.n), sub: cfg.sub, chains: cfg.chains, legacySpanBeats: cfg.spanBeats,
                                       advanceStep: cfg.advanceStep, riffDir: cfg.riffDir, stride: cfg.stride, length: cfg.length, shift: cfg.rotate, every: cfg.every, seed: cfg.seed)
        XCTAssertEqual(ro?.neverPlay.count, 3)
        // the next period starts over: every cell clears and the first lights on its first hit
        let again = restartTileState(.melody, cfg: cfg, beat: 8.1, running: true)
        XCTAssertEqual(again.litCount, 1); XCTAssertEqual(again.ghostCount, 3)
        // stopped: the structure (order and ghosts) stays at the beat, nothing lit, no sweep
        let stopped = restartTileState(.melody, cfg: cfg, beat: 3.6, running: false)
        XCTAssertEqual(stopped.litCount, 0); XCTAssertEqual(stopped.ghostCount, 3); XCTAssertNil(stopped.progress)
    }
    func testMelodyFreeShowsEveryNoteWithNoGhostsAndClearsAndRefillsAtTheWrap() {
        let cfg = recordingCfg(melody: nil)
        let at12 = restartTileState(.melody, cfg: cfg, beat: 12.1, running: true)   // hit 16 just played: ordinal 15, the walk's last step
        XCTAssertEqual(at12.count, 8); XCTAssertEqual(at12.ghostCount, 0); XCTAssertEqual(at12.litCount, 8, "all 8 lit after 16 hits"); XCTAssertNil(at12.progress)
        let at13 = restartTileState(.melody, cfg: cfg, beat: 13.1, running: true)   // hit 17: a new cycle
        XCTAssertEqual(at13.litCount, 1, "cleared, with the first cell lit on hit 17"); XCTAssertEqual(at13.ghostCount, 0)
        XCTAssertEqual(restartTileState(.melody, cfg: cfg, beat: 0.1, running: true).ghostCount, 0)
    }
    func testAWalkCycleThatWrapsInsideARestartClearsAndRefillsAndGhostsTheRest() {
        // melody 4 PASS: 20 hits per period against a 16-hit walk cycle
        let cfg = recordingCfg(melody: [4])
        let first = restartTileState(.melody, cfg: cfg, beat: 12.1, running: true)
        XCTAssertEqual(first.litCount, 8); XCTAssertEqual(first.ghostCount, 0, "the first cycle reaches every note")
        let wrapped = restartTileState(.melody, cfg: cfg, beat: 13.1, running: true)   // hit 17
        XCTAssertEqual(wrapped.litCount, 1, "cleared and refilled at hit 17")
        XCTAssertEqual((0..<8).filter { wrapped.cell($0) == 2 }, [2, 3, 4, 5, 6, 7], "in the second cycle cells 3–8 are ghosts (only hits 17–20 remain: two notes)")
        XCTAssertEqual(wrapped.reachable, 2)
    }
    func testPendulumShowsEachNoteOnceAndTheWayBackLightsExistingCells() {
        let cfg = tileCfg(5, 8, riffLength: 4, riffDir: .pendulum)
        let order = euclideousRiffCycleOrder(dir: .pendulum, length: 4, stride: 1, shift: 0)
        XCTAssertEqual(order.period, 6, "0 1 2 3 2 1, then back to its start"); XCTAssertEqual(order.visited, 4)
        XCTAssertEqual((0..<4).map { order.column(ofCell: $0) }, [0, 1, 2, 3])
        // hits at beats 0, 1, 2, 2.5, 3.5, 4, 5: 1, 2, 3, 4 cells, then 4, 4 (the way back), then a new cycle: 1
        XCTAssertEqual([0.0, 1, 2, 2.5, 3.5, 4, 5].map { restartTileState(.melody, cfg: cfg, beat: $0 + 0.1, running: true).litCount }, [1, 2, 3, 4, 4, 4, 1])
        XCTAssertEqual(restartTileState(.melody, cfg: cfg, beat: 0.1, running: true).count, 4)
        // PING-PONG repeats each end: 0 1 2 3 3 2 1 0 — a cycle of 8 walk steps, still 4 cells
        let ping = euclideousRiffCycleOrder(dir: .pingpong, length: 4, stride: 1, shift: 0)
        XCTAssertEqual(ping.period, 8); XCTAssertEqual(ping.visited, 4); XCTAssertEqual((0..<8).map { ping.distinctThrough(step: $0) }, [1, 2, 3, 4, 4, 4, 4, 4])
    }
    func testAdvStepLightsANoteReachedOnARestStep() {
        // ADV STEP walks one riff position per STEP, hit or not: E(3,8) hits steps 0, 3, 6 — at beat 0.6 (step 1, a rest) the second note is lit already
        let cfg = tileCfg(3, 8, advanceStep: true)
        XCTAssertEqual(restartTileState(.melody, cfg: cfg, beat: 0.1, running: true).litCount, 1)
        XCTAssertEqual(restartTileState(.melody, cfg: cfg, beat: 0.6, running: true).litCount, 2, "a note reached on a step with no hit still lights")
        XCTAssertEqual(restartTileState(.melody, cfg: cfg, beat: 1.1, running: true).litCount, 3)
    }
    func testStrideLeavesSomeNotesNeverReachedAndShiftMovesTheWindow() {
        let two = euclideousRiffCycleOrder(dir: .forward, length: 8, stride: 2, shift: 0)
        XCTAssertEqual(two.period, 4); XCTAssertEqual(two.visited, 4)
        XCTAssertEqual((0..<8).map { two.column(ofCell: $0) }, [0, 2, 4, 6, 1, 3, 5, 7], "the four visited columns first, then the ones the stride never reaches")
        let shifted = euclideousRiffCycleOrder(dir: .forward, length: 4, stride: 1, shift: 4)
        XCTAssertEqual((0..<4).map { shifted.column(ofCell: $0) }, [4, 5, 6, 7], "LEN 4 SHIFT 4 reads columns 5–8")
        // under a melody chain the unreachable notes are ghosts; under FREE nothing is
        let chain = restartTileState(.melody, cfg: tileCfg(5, 8, melody: [1], stride: 2), beat: 0.1, running: true)
        XCTAssertEqual(chain.ghostCount, 4)
        XCTAssertEqual(restartTileState(.melody, cfg: tileCfg(5, 8, stride: 2), beat: 0.1, running: true).ghostCount, 0)
    }
    func testRandomAndDrunkWalksRunInColumnOrderWithNoGhosts() {
        // they cannot reach the Euclideous row (`euclideousRiffDirResolved` coerces both to FWD), but the order function handles them
        for dir in [RiffDir.random, .drunk] {
            let o = euclideousRiffCycleOrder(dir: dir, length: 8, stride: 1, shift: 0)
            XCTAssertTrue(o.unpredictable); XCTAssertEqual((0..<8).map { o.column(ofCell: $0) }, Array(0..<8))
            var cfg = tileCfg(5, 8, melody: [2]); cfg.riffDir = dir
            XCTAssertEqual(restartTileState(.melody, cfg: cfg, beat: 0.1, running: true).ghostCount, 0, "no ghosts when the walk can't be predicted")
        }
        var line = EuclidLine(); line.riffDir = .random
        XCTAssertEqual(line.euclideousRiffDirResolved, .forward); line.riffDir = .drunk; XCTAssertEqual(line.euclideousRiffDirResolved, .forward)
    }

    // MARK: strikes (the pulse feed's per-hit stream, keyed by cell)

    func testAStrikeBrightensItsCellByTheSharedEnvelopeAndNeverTouchesAnother() {
        let cc = euclideousRiffCycleOrder(dir: .reverse, length: 8, stride: 1, shift: 0).columnCells   // column 7 → cell 0, column 6 → cell 1, …
        func strike(_ col: Int8, at t: Double, vel: UInt8 = 100) -> EuclideousPulseStrike { var s = EuclideousPulseStrike(onsetBeat: 0, onsetAt: t, riffVel: vel, notesVel: 0); s.cellColumn = col; return s }
        let bank = euclideousRestartCellStrikes([strike(7, at: 10), strike(6, at: 9)], columnCells: cc, now: 10.05)
        XCTAssertEqual(bank.mix(cell: 0, scale: 1, reduceMotion: false), euclideousPulseEnvelopes(velocity: 100, seconds: 0.05, scale: 1).f, accuracy: 1e-12)
        XCTAssertGreaterThan(bank.mix(cell: 0, scale: 1, reduceMotion: false), 0.5, "just struck: bright")
        XCTAssertLessThan(bank.mix(cell: 1, scale: 1, reduceMotion: false), 0.01, "a second-old strike has settled (τ 0.16 s)")
        for i in 2..<8 { XCTAssertEqual(bank.mix(cell: i, scale: 1, reduceMotion: false), 0, "cell \(i) was never struck") }
        // velocity scaling: a soft strike shows, but less; the youngest strike per cell wins (the same note again re-strikes its cell)
        XCTAssertLessThan(euclideousRestartCellStrikes([strike(7, at: 10, vel: 30)], columnCells: cc, now: 10.05).mix(cell: 0, scale: 1, reduceMotion: false), bank.mix(cell: 0, scale: 1, reduceMotion: false))
        let twice = euclideousRestartCellStrikes([strike(7, at: 9.5), strike(7, at: 10)], columnCells: cc, now: 10.05)
        XCTAssertEqual(twice.mix(cell: 0, scale: 1, reduceMotion: false), bank.mix(cell: 0, scale: 1, reduceMotion: false), accuracy: 1e-12, "the cell strikes again on each hit and never moves on")
        // the PULSE setting: OFF = nothing, SUBTLE = scaled; Reduce Motion keeps the glow, exactly as the strip's key strike does
        XCTAssertEqual(bank.mix(cell: 0, scale: 0, reduceMotion: false), 0)
        XCTAssertEqual(bank.mix(cell: 0, scale: 0.6, reduceMotion: false), euclideousPulseEnvelopes(velocity: 100, seconds: 0.05, scale: 0.6).f, accuracy: 1e-12)
        XCTAssertEqual(bank.mix(cell: 0, scale: 1, reduceMotion: true), bank.mix(cell: 0, scale: 1, reduceMotion: false))
        // not yet happened, a notes-only strike and a strike with no riff column draw nothing
        var notesOnly = strike(7, at: 10); notesOnly.riffVel = 0
        let none = euclideousRestartCellStrikes([strike(7, at: 11), notesOnly, strike(-1, at: 10)], columnCells: cc, now: 10.05)
        for i in 0..<8 { XCTAssertEqual(none.mix(cell: i, scale: 1, reduceMotion: false), 0) }
    }

    // MARK: draw order

    func testTheRestartTileDrawsBaseThenSweepThenTrackThenText() {
        XCTAssertEqual(euclideousRestartTileLayerOrder, [.base, .sweep, .track, .text])
        let order = euclideousRestartTileLayerOrder
        XCTAssertLessThan(order.firstIndex(of: .sweep)!, order.firstIndex(of: .text)!, "the sweep (and its leading edge) never draws over the name, chain or unit")
        XCTAssertLessThan(order.firstIndex(of: .track)!, order.firstIndex(of: .text)!)
        XCTAssertLessThan(order.firstIndex(of: .base)!, order.firstIndex(of: .sweep)!)
    }

    // MARK: RESTART TILES ferry — the restart editor

    func testTheEditorHasNoTimelineAxisLabelOrHintAndItsStripsSitUnderTheChainRows() {
        typealias M = EuclideousRestartEditorMetrics
        XCTAssertEqual(euclideousRestartEditorSectionParts, [.chainRow, .strip], "a chain row and the tile's strip — nothing else: no timeline, no BAR 1–16, no hint (NO CHANGE and the melody-1 line included)")
        XCTAssertEqual(M.sectionH, 70)
        // The ferry's numbers: RHYTHM at y 36, MELODY at 114, the strips at x 68, 262.5 × 28, at y 78 and 156 — they hold at an editor height of 200 (the three gaps share 24 pt: 8 each)
        let g = euclideousRestartEditorLayout(width: 338.5, height: 200)
        XCTAssertEqual(g.gaps, [8, 8, 8])
        XCTAssertEqual(g.sections.map { $0.minY }, [36, 114]); XCTAssertEqual(g.sections.map { $0.height }, [70, 70])
        XCTAssertEqual(g.strips.map { $0.minX }, [68, 68]); XCTAssertEqual(g.strips.map { $0.width }, [262.5, 262.5]); XCTAssertEqual(g.strips.map { $0.height }, [28, 28])
        XCTAssertEqual(g.strips.map { $0.minY }, [78, 156])
        XCTAssertEqual(g.chainRows.map { $0.height }, [38, 38])
        // at the reference card's 208-high editor (SOURCE: the flexible gaps share 32 − 12… each gap grows equally) the sections sit lower, each strip still sp4 under its chain row
        let r = euclideousRestartEditorLayout(width: 338.5, height: 208)
        XCTAssertEqual(r.gaps[0], 32.0 / 3, accuracy: 1e-9); XCTAssertEqual(r.sections[0].minY, 8 + 20 + 32.0 / 3, accuracy: 1e-9)
        for i in 0..<2 { XCTAssertEqual(r.strips[i].minY, r.chainRows[i].maxY + 4, accuracy: 1e-9); XCTAssertEqual(r.sections[i].height, 70) }
        XCTAssertEqual(r.strips[1].minX, 68); XCTAssertEqual(r.strips[1].width, 262.5)
        // a short editor keeps every gap at its minimum (4, 8, 0)
        XCTAssertEqual(euclideousRestartEditorLayout(width: 338.5, height: 176).gaps, [4, 8, 0])
        // a few pt more than the minimums: the shares settle without ever going under one
        let mid = euclideousRestartEditorLayout(width: 338.5, height: 196).gaps
        XCTAssertEqual(mid.reduce(0, +), 20, accuracy: 1e-9); XCTAssertGreaterThanOrEqual(mid[1], 8); XCTAssertGreaterThanOrEqual(mid[0], 4)
    }
    func testAnEditToAChainChangesTheStripsStateInTheSameUpdate() {
        // the strips are the tile's pure state built from the CURRENT lines — an edit through the editor's own mutation (a link tapped, + , FREE) changes both at once
        var l = EuclidLine(pulses: 5, steps: 8, noteSel: .all); l.rate = .r1_8; l.riffAdvanceEvery = 2; l.riffDir = .reverse
        func states(_ line: EuclidLine, beat: Double) -> (rhythm: EuclideousRestartTileState, melody: EuclideousRestartTileState) {
            let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
            return (restartTileState(.rhythm, cfg: cfg, beat: beat, running: true), restartTileState(.melody, cfg: cfg, beat: beat, running: true))
        }
        let free = states(l, beat: 2.1)
        XCTAssertTrue(free.rhythm.isFree); XCTAssertNil(free.rhythm.progress); XCTAssertNil(free.melody.progress)
        l.restartRhythmBars = [2]           // "+": append a link (the editor's own mutation)
        l.restartMelodyPasses = [2]
        let set = states(l, beat: 2.1)
        XCTAssertFalse(set.rhythm.isFree); XCTAssertEqual(set.rhythm.progress!, 2.1 / 8, accuracy: 1e-9, "the sweep follows the new chain immediately")
        XCTAssertEqual(set.melody.ghostCount, 3, "and so does the track")
        l.restartMelodyPasses = [4]         // a tap on the link: the next length
        XCTAssertEqual(states(l, beat: 2.1).melody.ghostCount, 0, "4 passes = 20 hits, a full 16-hit cycle: no ghosts in the first cycle")
        l.restartRhythmBars = []            // FREE
        XCTAssertTrue(states(l, beat: 2.1).rhythm.isFree)
    }
    // The finished lane pattern (cells only) as the page and the engine build it — the allocating form of `euclideousBuildHitPatternInto`.
    private func euclideousBuildPattern(_ L: EuclidLine) -> (buf: [Bool], n: Int) {
        var cells = [Bool](repeating: false, count: 16), micro = [Double](repeating: 0, count: 16)
        let n = euclideousBuildHitPatternInto(L, cells: &cells, micro: &micro)
        return (cells, n)
    }
    func testFlipHitsIsTheSameToggleAsInv() {
        var cellsScratch = [Bool](repeating: false, count: 16), microScratch = [Double](repeating: 0, count: 16)
        // behaviour is the lane's `patternMiss`; the pattern it makes is the engine's own (the 7-step lane's gaps)
        var l = EuclidLine(pulses: 3, steps: 7, noteSel: .all)
        let plain = euclideousBuildPattern(l).buf
        l.patternMiss = true
        let flipped = euclideousBuildPattern(l).buf
        XCTAssertEqual((0..<7).map { flipped[$0] }, (0..<7).map { !plain[$0] }, "FLIP HITS plays exactly the steps that did not hit")
        XCTAssertEqual(EuclideousFlipHits.accessibilityLabel, "Flip hits"); XCTAssertEqual(EuclideousFlipHits.lines, ["FLIP", "HITS"])
        // the same stream as INV had: a flipped lane renders the complement of the plain lane's hits
        XCTAssertEqual(euclideousHitPatternInto(pulses: 3, steps: 7, rotate: 0, tilt: 0, fine: false, customHits: nil, patternMiss: true, cells: &cellsScratch, micro: &microScratch), 7)
        XCTAssertEqual((0..<7).map { cellsScratch[$0] }, (0..<7).map { flipped[$0] })
    }

    func testTheRightHalfRowsAndDirectionButtonsAtTheReferenceCard() {
        // the reference card's upper zone is 116 pt tall and its right half 167.25 pt wide (RHYTHM POLISH §1.2–1.3): three equal rows and four equal buttons, sp4 apart
        let gap = EuclideousRhythmGeometry.gap
        XCTAssertEqual(gap, 4)
        let rowH = EuclideousRhythmGeometry.rightRowH(upperH: 116)
        XCTAssertEqual(rowH, 36, accuracy: 1e-9); XCTAssertEqual(rowH * 3 + gap * 2, 116, accuracy: 1e-9, "three rows and two gaps fill the upper zone exactly")
        let bw = EuclideousRhythmGeometry.directionButtonW(rightHalfW: 167.25)
        XCTAssertEqual(bw, 38.8125, accuracy: 1e-9); XCTAssertEqual(bw * 4 + gap * 3, 167.25, accuracy: 1e-9, "four buttons and three gaps fill the right half exactly")
        // degenerate sizes never go to zero or negative (a layout must not trap or collapse)
        XCTAssertEqual(EuclideousRhythmGeometry.rightRowH(upperH: 0), 1); XCTAssertEqual(EuclideousRhythmGeometry.directionButtonW(rightHalfW: 0), 1)
        // TILT's EARLY/LATE labels drop out below the row-height floor and not above it
        XCTAssertTrue(EuclideousRhythmGeometry.showsEndLabels(rowH: EuclideousRhythmGeometry.endLabelsFloor))
        XCTAssertFalse(EuclideousRhythmGeometry.showsEndLabels(rowH: EuclideousRhythmGeometry.endLabelsFloor - 0.01))
    }

    func testTheRightHalfRowsFillTheUpperZoneInEveryPageLayout() {
        // The lane cards the page layout gives at the iPad sizes we ship to: the three rows always split the upper zone's height equally, whatever the card height.
        for size in [CGSize(width: 1366, height: 1024), CGSize(width: 1194, height: 834), CGSize(width: 1112, height: 834), CGSize(width: 1024, height: 768), CGSize(width: 834, height: 1194), CGSize(width: 768, height: 1024)] {
            let card = euclideousPageLayout(size: size).lanes[0]
            let upperH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: card.height) - 84
            let rowH = EuclideousRhythmGeometry.rightRowH(upperH: upperH)
            if upperH > 3 * EuclideousRhythmGeometry.gap { XCTAssertEqual(rowH * 3 + EuclideousRhythmGeometry.gap * 2, upperH, accuracy: 1e-9, "\(size): the three rows split the upper zone equally") }
            XCTAssertGreaterThanOrEqual(rowH, 1, "\(size)")
        }
    }
}
