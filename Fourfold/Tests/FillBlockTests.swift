//  FillBlockTests.swift — FILL ferry (2026-11-13), slice 4: the FILL block's pure layout (§3) and the value
//  fields' text / index / drag / tap (§4.4/§6.3). The tiles' looks + feel are device-owed.

import XCTest

final class FillBlockTests: XCTestCase {

    // §3 — the landscape lane-card half (171.84 × 80): three rows at 24.67 (NOT the spec's ~29), 8 bar tiles 2.5 apart, 4 columns 3 apart, RANKS double-width.
    func testLayoutAtTheLandscapeHalf() {
        let L = euclideousFillBlockLayout(box: CGSize(width: 171.84, height: 80))
        XCTAssertEqual(L.rowH, (80 - 6) / 3, accuracy: 1e-6, "rowH = (H − 2·3)/3 = 24.67 (the note-value column's cell height)")
        XCTAssertEqual(L.barTiles.count, 8)
        XCTAssertEqual(L.barTiles[0].width, (171.84 - 2.5 * 7) / 8, accuracy: 1e-6, "bar tile ≈ 19.3 wide, 2.5 apart")
        XCTAssertEqual(L.barTiles[1].minX - L.barTiles[0].maxX, 2.5, accuracy: 1e-6)
        XCTAssertEqual(L.speed.width, (171.84 - 3 * 3) / 4, accuracy: 1e-6, "value column ≈ 40.7 wide, 3 apart")
        XCTAssertEqual(L.ranks.width, L.speed.width * 2 + 3, accuracy: 1e-6, "RANKS spans two columns + the gap")
        XCTAssertEqual(L.radius, 6)
        // row y's match the note-value column (0, 27.67, 55.33).
        XCTAssertEqual(L.barTiles[0].minY, 0, accuracy: 1e-6)
        XCTAssertEqual(L.fill.minY, L.rowH + 3, accuracy: 1e-6)
        XCTAssertEqual(L.ranks.minY, 2 * (L.rowH + 3), accuracy: 1e-6)
        // columns: FILL·SPEED·LENGTH·REVERSE on row 2; RANKS(1-2)·SWELL·BREAK on row 3.
        XCTAssertEqual(L.fill.minX, 0, accuracy: 1e-6)
        XCTAssertEqual(L.swell.minX, L.length.minX, accuracy: 1e-6, "SWELL sits under LENGTH (col 3)")
        XCTAssertEqual(L.brk.minX, L.reverse.minX, accuracy: 1e-6, "BREAK sits under REVERSE (col 4)")
    }

    // §4.4 — value text.
    func testValueText() {
        var l = EuclidLine()
        l.fillSpeed = 0; XCTAssertEqual(euclideousFillFieldValueText(.speed, l), "\u{00D7}\u{00BD}")   // ×½
        l.fillSpeed = 3; XCTAssertEqual(euclideousFillFieldValueText(.speed, l), "\u{00D7}2")
        l.fillSpeed = 4; XCTAssertEqual(euclideousFillFieldValueText(.speed, l), "\u{00D7}4")
        l.fillLength = 0; XCTAssertEqual(euclideousFillFieldValueText(.length, l), "BAR")
        l.fillLength = 2; XCTAssertEqual(euclideousFillFieldValueText(.length, l), "\u{00BC}")           // ¼
        l.fillRanks = -7; XCTAssertEqual(euclideousFillFieldValueText(.ranks, l), "\u{2212}7")            // −7
        l.fillRanks = 0; XCTAssertEqual(euclideousFillFieldValueText(.ranks, l), "0")
        l.fillSwell = 2; XCTAssertEqual(euclideousFillFieldValueText(.swell, l), "+2")
    }

    // §4.3 — the leading→trailing index and its round-trip, and the fraction.
    func testIndexFractionAndRoundTrip() {
        var l = EuclidLine()
        // LENGTH: leading ¼ (index 0) = stored 2; BAR (index 2) = stored 0.
        euclideousFillSetFieldIndex(.length, 0, &l); XCTAssertEqual(l.fillLength, 2); XCTAssertEqual(euclideousFillFieldIndex(.length, l), 0)
        euclideousFillSetFieldIndex(.length, 2, &l); XCTAssertEqual(l.fillLength, 0)
        // RANKS: index 0 = −7, index 14 = +7; fraction 0…1.
        euclideousFillSetFieldIndex(.ranks, 0, &l); XCTAssertEqual(l.fillRanks, -7); XCTAssertEqual(euclideousFillFieldFraction(.ranks, l), 0, accuracy: 1e-9)
        euclideousFillSetFieldIndex(.ranks, 14, &l); XCTAssertEqual(l.fillRanks, 7); XCTAssertEqual(euclideousFillFieldFraction(.ranks, l), 1, accuracy: 1e-9)
        euclideousFillSetFieldIndex(.ranks, 7, &l); XCTAssertEqual(euclideousFillFieldFraction(.ranks, l), 0.5, accuracy: 1e-9)
        // clamp.
        euclideousFillSetFieldIndex(.swell, 99, &l); XCTAssertEqual(l.fillSwell, 3)
        // defaults (§1.1): ×2, ½, 0, 0.
        XCTAssertEqual(EuclideousFillField.speed.defaultIndex, 3)
        XCTAssertEqual(EuclideousFillField.length.defaultIndex, 1)
        XCTAssertEqual(EuclideousFillField.ranks.defaultIndex, 7)
    }

    // §6.3 — tap halves + drag.
    func testTapHalvesAndDrag() {
        var l = EuclidLine(); euclideousFillSetFieldIndex(.ranks, 7, &l)   // 0
        XCTAssertEqual(euclideousFillFieldTapStep(.ranks, l, fracX: 0.2), 6, "leading half steps toward −7")
        XCTAssertEqual(euclideousFillFieldTapStep(.ranks, l, fracX: 0.8), 8, "trailing half steps toward +7")
        euclideousFillSetFieldIndex(.ranks, 0, &l)
        XCTAssertEqual(euclideousFillFieldTapStep(.ranks, l, fracX: 0.2), 0, "clamped at the leading end, no wrap")
        // drag maps position → nearest index.
        XCTAssertEqual(euclideousFillFieldDragIndex(.ranks, fracX: 0), 0)
        XCTAssertEqual(euclideousFillFieldDragIndex(.ranks, fracX: 1), 14)
        XCTAssertEqual(euclideousFillFieldDragIndex(.ranks, fracX: 0.5), 7)
        XCTAssertEqual(euclideousFillFieldDragIndex(.speed, fracX: 1), 4)
    }

    // §8 — VoiceOver.
    func testVoiceOver() {
        var l = EuclidLine(); l.fillSpeed = 3
        XCTAssertEqual(euclideousFillFieldAX(.speed, l), "Fill speed, times two")
        l.fillRanks = 3; XCTAssertEqual(euclideousFillFieldAX(.ranks, l), "Fill ranks, plus three")
        XCTAssertEqual(euclideousFillBarAX(3, on: true, current: true), "Fill bar 4, on, current")
        XCTAssertEqual(euclideousFillToggleAX(false), "Fill, off")
        XCTAssertEqual(euclideousFillBoolAX("break", on: true), "Fill break, on")
    }
}
