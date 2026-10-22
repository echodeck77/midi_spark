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
}
