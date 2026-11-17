//  FillTabModelTests.swift — FILL TAB ferry (2026-11-14) §1 / §7.4 / §7.10: the new/changed per-lane fields — defaults, clamps, decode-tolerance, the fillReverse→ORDER migration, the 8→16 fillBars widening, the loop, and §1.4 neutrality.

import XCTest

final class FillTabModelTests: XCTestCase {
    func testDefaults() {
        let l = EuclidLine()
        XCTAssertEqual(l.fillLoopResolved, 8); XCTAssertEqual(l.fillCurveResolved, .steady); XCTAssertEqual(l.fillOrderResolved, .fwd)
        XCTAssertEqual(l.fillShapeResolved, .climb); XCTAssertEqual(l.fillHitsResolved, .all, "FILL TAB V2 / AMEND 1 default: ALL")
        XCTAssertEqual(l.fillNotesResolved, .riff, "FILL TAB V2 §1.3 default: RIFF")
        XCTAssertEqual(l.fillSpeedResolved, 1, "FILL TAB V2 / AMEND 1 default: ×1")
        XCTAssertEqual(l.fillRollResolved, 0); XCTAssertEqual(l.fillChanceResolved, 100); XCTAssertFalse(l.fillLandResolved)
        XCTAssertEqual(l.fillBarsResolved.count, 16); XCTAssertTrue(l.fillBarsResolved.allSatisfy { !$0 })
    }

    // FILL TAB V2 §1.4 — a stored SHIFT decodes (and plays) as CLIMB; the case stays decodable and round-trips.
    func testStoredShiftDecodesAsClimb() throws {
        var l = EuclidLine(); l.fillShape = .shift
        XCTAssertEqual(l.fillShapeResolved, .climb, "SHIFT is retired — it resolves to CLIMB (§1.4, the one sound change)")
        let r = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(l))
        XCTAssertEqual(r.fillShape, .shift, "the stored value round-trips untouched")
        XCTAssertEqual(r.fillShapeResolved, .climb)
    }

    // FILL TAB V2 §1.1–§1.3 — the new values store, round-trip, and an unknown stored value reads as the default.
    func testV2FieldsRoundTripAndTolerate() throws {
        var l = EuclidLine(); l.fillOrder = .stutter; l.fillHits = .build; l.fillNotes = .pedal
        let r = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(l))
        XCTAssertEqual(r.fillOrderResolved, .stutter); XCTAssertEqual(r.fillHitsResolved, .build); XCTAssertEqual(r.fillNotesResolved, .pedal)
        let junk = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"target":0,"fillNotes":"zigzag","fillOrder":"spiral"}"#.utf8))
        XCTAssertEqual(junk.fillNotesResolved, .riff, "an unknown stored NOTES reads as the default (§1.7)")
        XCTAssertEqual(junk.fillOrderResolved, .fwd, "an unknown stored ORDER reads as the default (§1.7)")
    }
    func testClampsAndUnknownFold() {
        var l = EuclidLine()
        l.fillLoop = 7; XCTAssertEqual(l.fillLoopResolved, 8); l.fillLoop = 16; XCTAssertEqual(l.fillLoopResolved, 16); l.fillLoop = 4; XCTAssertEqual(l.fillLoopResolved, 4)
        l.fillRoll = 9; XCTAssertEqual(l.fillRollResolved, 4)
        l.fillChance = 33; XCTAssertEqual(l.fillChanceResolved, 100); l.fillChance = 75; XCTAssertEqual(l.fillChanceResolved, 75)
    }

    // §7.4 — ORDER replaces REVERSE: a stored fillReverse decodes to REV / FWD; a written fillOrder wins.
    func testOrderMigratesFromReverse() {
        var rev = EuclidLine(); rev.fillReverse = true; XCTAssertEqual(rev.fillOrderResolved, .rev)
        var fwd = EuclidLine(); fwd.fillReverse = false; XCTAssertEqual(fwd.fillOrderResolved, .fwd)
        XCTAssertEqual(EuclidLine().fillOrderResolved, .fwd, "missing ⇒ FWD")
        var both = EuclidLine(); both.fillReverse = true; both.fillOrder = .bounce; XCTAssertEqual(both.fillOrderResolved, .bounce, "a written fillOrder wins over the legacy fillReverse")
    }

    // §7.10 — the loop + the 8→16 widening.
    func testLoopAndBarsWidening() throws {
        var l = EuclidLine(); l.fillOn = true; l.fillLoop = 4; l.fillBars = (0..<16).map { $0 == 3 }   // bar index 3 (= "bar 4") lit
        XCTAssertTrue(l.fillArmed(bar: 3) && l.fillArmed(bar: 7) && l.fillArmed(bar: 11), "loop 4 ⇒ bar 4 arms bars 4, 8, 12…")
        XCTAssertFalse(l.fillArmed(bar: 4), "bar 5 is not armed")
        l.fillLoop = 16; l.fillBars = (0..<16).map { $0 == 12 }   // "bar 13"
        XCTAssertTrue(l.fillArmed(bar: 12)); XCTAssertFalse(l.fillArmed(bar: 13), "loop 16 ⇒ only index 12 in the loop is armed"); XCTAssertTrue(l.fillArmed(bar: 28), "28 mod 16 = 12 ⇒ armed again a loop later")
        // an 8-entry stored array decodes into the first 8 of the 16-entry resolved view
        var eight = EuclidLine(); eight.fillBars = [true, false, false, false, false, false, false, true]   // bars 1 and 8
        let r = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(eight))
        XCTAssertEqual(r.fillBarsResolved.count, 16); XCTAssertTrue(r.fillBarsResolved[0]); XCTAssertTrue(r.fillBarsResolved[7]); XCTAssertTrue(r.fillBarsResolved[8...].allSatisfy { !$0 })
    }

    // §1.4/§1.6 — neutral (×1 STEADY FWD KEEP RIFF 0 0 0 off off) sounds exactly as no fill whatever LENGTH, SHAPE and CHANCE are.
    // FILL TAB V2: the DEFAULT lane is no longer neutral (HITS defaults to ALL) — a lit default bar now PLAYS a fill (§9).
    func testNeutral() {
        var l = EuclidLine(); l.fillOn = true; l.fillBars = (0..<16).map { $0 == 0 }
        XCTAssertFalse(l.fillNeutral, "the defaults (HITS ALL) are NOT neutral — a fresh lit bar fills (AMEND 1 / §9)")
        XCTAssertTrue(l.usesFill)
        l.fillHits = .keep                                        // §1.6 neutral needs KEEP (and RIFF, the default)
        XCTAssertTrue(l.fillNeutral); XCTAssertFalse(l.usesFill, "a lit but neutral fill does nothing")
        l.fillLength = 2; l.fillShape = .arch; l.fillChance = 50
        XCTAssertTrue(l.fillNeutral, "LENGTH, SHAPE and CHANCE don't break neutrality (§1.4)")
        l.fillCurve = .rush; XCTAssertFalse(l.fillNeutral, "RUSH is not neutral"); l.fillCurve = .steady
        l.fillOrder = .bounce; XCTAssertFalse(l.fillNeutral); l.fillOrder = .fwd
        l.fillOrder = .stutter; XCTAssertFalse(l.fillNeutral, "STUTTER is not neutral (V2)"); l.fillOrder = .fwd
        l.fillHits = .all; XCTAssertFalse(l.fillNeutral); l.fillHits = .keep
        l.fillHits = .build; XCTAssertFalse(l.fillNeutral, "BUILD is not neutral (V2)"); l.fillHits = .keep
        l.fillNotes = .flat; XCTAssertFalse(l.fillNeutral, "a NOTES mode is not neutral (V2 §1.6)"); l.fillNotes = .riff
        l.fillRoll = 2; XCTAssertFalse(l.fillNeutral); l.fillRoll = 0
        l.fillLand = true; XCTAssertFalse(l.fillNeutral); l.fillLand = false
        l.fillRanks = 3; XCTAssertFalse(l.fillNeutral)
        XCTAssertTrue(l.usesFill == false || l.fillNeutral == false)
    }

    func testRoundTrip() throws {
        var l = EuclidLine()
        l.fillLoop = 16; l.fillCurve = .rush; l.fillOrder = .shuffle; l.fillShape = .arch; l.fillHits = .flip; l.fillRoll = 4; l.fillChance = 25; l.fillLand = true
        l.fillBars = (0..<16).map { $0 % 4 == 0 }
        let r = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(l))
        XCTAssertEqual(r.fillLoop, 16); XCTAssertEqual(r.fillCurve, .rush); XCTAssertEqual(r.fillOrder, .shuffle); XCTAssertEqual(r.fillShape, .arch)
        XCTAssertEqual(r.fillHits, .flip); XCTAssertEqual(r.fillRoll, 4); XCTAssertEqual(r.fillChance, 25); XCTAssertEqual(r.fillLand, true)
        XCTAssertEqual(r.fillBars, l.fillBars)
    }
}
