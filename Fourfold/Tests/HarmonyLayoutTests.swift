//  HarmonyLayoutTests.swift — INPUTS + HARMONY ferry (2026-11-06) test 12: the HARMONY page's geometry in every layout, the INPUTS rows' heights, the pill's widest case and the popover widths. The numbers it prints are the report's §13.4.

import XCTest

final class HarmonyLayoutTests: XCTestCase {
    private let landscape = CGSize(width: 769.33, height: 610)       // the lane cards' block at the 1190 reference
    private let portrait = CGSize(width: 782, height: 611.33)

    private func f(_ x: CGFloat) -> String { String(format: "%.2f", Double(x)) }

    func testTheReferenceGeometry() {
        let L = euclideousHarmonyLayout(block: landscape)
        let m = EuclideousHarmonyMetrics.self
        XCTAssertEqual(L.content, CGRect(x: 16, y: 16, width: 737.33, height: 578))
        XCTAssertEqual(L.titleRow.height, 36); XCTAssertEqual(L.rootRow.minY, 36 + 12); XCTAssertEqual(L.rootRow.height, 52)
        XCTAssertEqual(L.rootKeyW, (737.33 - 11 * 4) / 12, accuracy: 0.001, "twelve keys, 4 apart, equal")
        XCTAssertEqual(L.scaleRows.count, 1, "13 scales fit one row at the reference"); XCTAssertEqual(L.scalePerRow, 13)
        XCTAssertEqual(L.scaleChipW, (737.33 - 12 * 3) / 13, accuracy: 0.001); XCTAssertGreaterThanOrEqual(L.scaleChipW, 44)
        XCTAssertEqual(L.scaleRows[0].minY, 48 + 52 + 4); XCTAssertEqual(L.scaleRows[0].height, 30)
        XCTAssertEqual(L.chordsHeading.minY, 104 + 30 + 22); XCTAssertEqual(L.chordsHeading.height, 24)
        XCTAssertEqual(L.column0.minY, L.chordsHeading.maxY + 8)
        XCTAssertEqual(L.columnW, (737.33 - 16) / 2, accuracy: 0.001); XCTAssertEqual(L.column1.minX, L.columnW + 16, accuracy: 0.001)
        XCTAssertEqual(L.pickStrip.height, 36); XCTAssertEqual(L.pickStrip.maxY, L.content.height, "the band ends at the content's bottom")
        XCTAssertEqual(L.pickStrip.minY - L.column0.maxY, 16, accuracy: 0.001, "sp16 between the columns and the band")
        XCTAssertEqual(L.midiStrip.minX, L.column1.minX); XCTAssertEqual(L.pickStrip.width, L.columnW)
        XCTAssertEqual(L.gridH, L.column0.height - (26 + 8 + 12 + 4), accuracy: 0.001)
        // rows split the grid's height: CHORDS 12 rows 3 apart with 5 extra above REST; COLOUR 6 rows 3 apart
        let rc = L.rowH(.chords), rk = L.rowH(.colour)
        XCTAssertEqual(rc * 12 + 11 * 3 + 5, L.gridH, accuracy: 0.001); XCTAssertEqual(rk * 6 + 5 * 3, L.gridH, accuracy: 0.001)
        XCTAssertEqual(L.rowTop(.chords, position: 11) + rc, L.gridH, accuracy: 0.001, "REST ends on the grid's bottom")
        XCTAssertEqual(L.rowTop(.chords, position: 11) - L.rowTop(.chords, position: 10) - rc, 3 + 5, accuracy: 0.001, "REST carries 5 extra above it")
        XCTAssertEqual(L.rowTop(.colour, position: 5) + rk, L.gridH, accuracy: 0.001)
        // cells
        XCTAssertEqual(L.cellW(steps: 8), (L.columnW - 32 - 4 - 7 * 3) / 8, accuracy: 0.001); XCTAssertEqual(L.cellW(steps: 16), (L.columnW - 32 - 4 - 15 * 3) / 16, accuracy: 0.001)
        XCTAssertEqual(L.cellW(steps: 3), L.cellW(steps: 8), "fewer than 8 steps still lays out 8 columns")
        XCTAssertEqual(L.columnLeft(steps: 8, 0), 36); XCTAssertEqual(L.columnLeft(steps: 8, 7) + L.cellW(steps: 8), L.columnW, accuracy: 0.001)
        // popovers
        XCTAssertEqual(euclideousHarmonyPopoverHeight, 80); XCTAssertEqual(euclideousHarmonyPickPopoverHeight, 72)
        let pop = L.pillPopover(set: 0)
        XCTAssertEqual(pop.width, L.columnW); XCTAssertEqual(pop.minY, L.column0.minY + 26 + 6, accuracy: 0.001)
        XCTAssertEqual(L.pickPopover.maxY + 6, L.pickStrip.minY, accuracy: 0.001); XCTAssertEqual(L.pickPopover.width, L.pickStrip.width)
        XCTAssertEqual(L.closeTarget.width, 44); XCTAssertEqual(L.closeTarget.maxX, L.content.width)
        print("HARMONY-GEOMETRY landscape 769.33×610: content \(f(L.content.width))×\(f(L.content.height)) · title \(f(L.titleRow.height)) · root key \(f(L.rootKeyW)) × 52 · scale chip \(f(L.scaleChipW)) (\(L.scaleRows.count) row, \(L.scalePerRow) per row) · column \(f(L.columnW)) × \(f(L.column0.height)) · grid \(f(L.gridH)) · rowH CHORDS \(f(rc)) / COLOUR \(f(rk)) · cellW 8 \(f(L.cellW(steps: 8))) / 16 \(f(L.cellW(steps: 16))) · pill popover \(f(pop.width))×\(f(pop.height)) · PICK editor \(f(L.pickPopover.width))×\(f(L.pickPopover.height))")
        XCTAssertGreaterThanOrEqual(rc, 14, "CHORDS rows stay at or above 14 at the reference")
    }

    func testThePortraitGeometry() {
        let L = euclideousHarmonyLayout(block: portrait)
        XCTAssertEqual(L.content, CGRect(x: 16, y: 16, width: 750, height: 579.33))
        XCTAssertEqual(L.scaleRows.count, 1); XCTAssertEqual(L.scaleChipW, (750 - 36) / 13, accuracy: 0.001)
        let rc = L.rowH(.chords), rk = L.rowH(.colour)
        XCTAssertEqual(rc * 12 + 11 * 3 + 5, L.gridH, accuracy: 0.001); XCTAssertEqual(rk * 6 + 5 * 3, L.gridH, accuracy: 0.001)
        print("HARMONY-GEOMETRY portrait 782×611.33: content \(f(L.content.width))×\(f(L.content.height)) · root key \(f(L.rootKeyW)) · scale chip \(f(L.scaleChipW)) (\(L.scaleRows.count) row) · column \(f(L.columnW)) × \(f(L.column0.height)) · grid \(f(L.gridH)) · rowH CHORDS \(f(rc)) / COLOUR \(f(rk)) · cellW 8 \(f(L.cellW(steps: 8))) / 16 \(f(L.cellW(steps: 16)))")
    }

    func testScalesWrapIntoTwoEqualRowsWhenAChipWouldBeUnder44() {
        // 13 chips need 13 × 44 + 12 × 3 = 608 of content width: the block below 640 wraps
        let narrow = euclideousHarmonyLayout(block: CGSize(width: 600, height: 610))
        XCTAssertEqual(narrow.scaleRows.count, 2); XCTAssertEqual(narrow.scalePerRow, 7, "7 on the first row, 6 on the second, chips of one width")
        XCTAssertEqual(narrow.scaleChipW, (568 - 6 * 3) / 7, accuracy: 0.001); XCTAssertEqual(narrow.scaleRows[1].minY - narrow.scaleRows[0].minY, 30 + 3)
        XCTAssertEqual(narrow.chordsHeading.minY, 104 + 63 + 22, "the second scale row pushes everything below it down by 33")
        let edge = euclideousHarmonyLayout(block: CGSize(width: 640, height: 610))
        XCTAssertEqual(edge.scaleRows.count, 1, "at 608 of content width a chip is exactly 44")
        XCTAssertEqual(euclideousHarmonyLayout(block: CGSize(width: 639, height: 610)).scaleRows.count, 2)
        // the second row costs exactly 33 pt of grid height: 33 more block height gives the same grid
        let wrapped = euclideousHarmonyLayout(block: CGSize(width: 600, height: 643)), plain = euclideousHarmonyLayout(block: CGSize(width: 700, height: 610))
        XCTAssertEqual(wrapped.gridH, plain.gridH, accuracy: 0.001)
    }

    func testTheBandAndColumnsSurviveASmallBlock() {
        for h in stride(from: 300, through: 700, by: 25) {
            let L = euclideousHarmonyLayout(block: CGSize(width: 769.33, height: CGFloat(h)))
            XCTAssertGreaterThanOrEqual(L.gridH, 0); XCTAssertGreaterThanOrEqual(L.rowH(.chords), 0); XCTAssertGreaterThanOrEqual(L.rowH(.colour), 0)
            XCTAssertLessThanOrEqual(L.pickStrip.maxY, L.content.height + 0.001)
        }
    }

    func testThePopoverRowsGiveUpWidthWhereTheNaturalRowIsTooWide() {
        let L = euclideousHarmonyLayout(block: landscape)
        let inner = L.columnW - 20
        let R = euclideousHarmonyPopoverRows(innerW: inner)
        XCTAssertEqual(R.naturalAdvanceTime, 344); XCTAssertEqual(R.naturalRestart, 342); XCTAssertEqual(R.naturalAdvanceCounted, 308)
        XCTAssertGreaterThan(R.naturalAdvanceTime, inner, "the TIME row is wider than the popover at the reference"); XCTAssertGreaterThan(R.naturalRestart, inner)
        XCTAssertLessThanOrEqual(R.advanceTimeW, inner + 0.001); XCTAssertLessThanOrEqual(R.restartW, inner + 0.001)
        XCTAssertGreaterThanOrEqual(R.rateChipW, 20); XCTAssertGreaterThanOrEqual(R.squareW, 16)
        let wide = euclideousHarmonyPopoverRows(innerW: 400)
        XCTAssertEqual(wide.rateChipW, 25); XCTAssertEqual(wide.squareW, 18, "room to spare: the chords page's own chips")
        print("HARMONY-POPOVER inner \(f(inner)): natural TIME \(f(R.naturalAdvanceTime)) / RESTART \(f(R.naturalRestart)) / LOOP·RIFF \(f(R.naturalAdvanceCounted)) → rate chips \(f(R.rateChipW)) (25), lane squares \(f(R.squareW)) (18)")
    }

    func testThePillsWidestCaseFitsTheTitleRow() {
        var s = MachineParams(); s.advanceUnit = .loop; s.advanceLane = 3; s.advanceEvery = 8; s.restartOn = true; s.restartUnit = .riff; s.restartLane = 2; s.restartEvery = 16
        let widest = harmonyPill(s)
        var t = MachineParams(); t.chordsRate = .r1_2d      // TIME "1/2."
        let plain = harmonyPill(t)
        let L = euclideousHarmonyLayout(block: landscape)
        // the room the pill has: the column less the number (18), 4 lane squares (4 × 8 + 3 × 6), the gaps and the steps cluster (24 + 42 + 24)
        let room = L.columnW - 18 - 6 - (4 * 8 + 3 * 6) - 6 - 6 - 90
        let w = euclideousHarmonyPillEstimatedWidth(widest)
        print("HARMONY-PILL widest \"\(widest.advanceUnit) ■ \(widest.advanceValue) | \(widest.restart!.unit) ■ \(widest.restart!.value)\" ≈ \(f(w)) of \(f(room)) · plain \"\(plain.advanceUnit) \(plain.advanceValue)\" ≈ \(f(euclideousHarmonyPillEstimatedWidth(plain)))")
        XCTAssertLessThan(w, room, "even the widest pill fits beside four lane squares")
        XCTAssertLessThan(euclideousHarmonyPillEstimatedWidth(plain), w)
    }

    func testTheInputsRowHeightsAtEveryCardHeight() {
        // the card body (contentAreaH) at the reference is 229 (landscape) / 229.67 (portrait); the mini's is shorter
        for h in [229.0, 229.67, 200, 190, 175, 172, 150, 143] {
            let l = euclideousInputsTabLayout(contentAreaH: CGFloat(h))
            print("INPUTS-ROWS body \(h): NOW \(f(l.nowH)) · SOURCES \(f(l.sourcesH)) · MIDI \(f(l.midiH)) · CANON \(f(l.canonH)) · gap \(f(l.gap)) · fits \(l.fits)")
        }
    }
}
