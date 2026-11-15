//  FillBlockTests.swift — FILL ferry (2026-11-13) + FILL TAB ferry (2026-11-14): the FILL block's pure layout (§3,
//  the whole-card grid: bar row + loop chip, preview, 3×4 controls), the value fields' text / index / drag / tap
//  (§4.3/§4.4/§6.3), and the ORDER / HITS selectors + curve / shape chips (§4.4/§4.5). The looks + feel are device-owed.

import XCTest
import CoreGraphics

final class FillBlockTests: XCTestCase {

    // §3 — the whole-card grid (360 × 233, loop 8): a 28 pt bar row + a 34 pt loop chip, a 50 pt preview, then 3 control rows of 4 equal columns.
    func testLayoutWholeCard() {
        let L = euclideousFillBlockLayout(box: CGSize(width: 360, height: 233), loop: 8)
        XCTAssertEqual(L.barCount, 8)
        XCTAssertEqual(L.barTiles.count, 8)
        XCTAssertEqual(L.barTiles[0].minY, 0, accuracy: 1e-6)
        XCTAssertEqual(L.barTiles[0].height, 28, accuracy: 1e-6, "bar row 28 tall")
        XCTAssertEqual(L.loopChip.maxX, 360, accuracy: 1e-6, "loop chip at the trailing end")
        XCTAssertEqual(L.loopChip.width, 34, accuracy: 1e-6)
        XCTAssertEqual(L.barTiles[1].minX - L.barTiles[0].maxX, 2.5, accuracy: 1e-6, "bar tiles 2.5 apart")
        XCTAssertEqual(L.previewH, 50, accuracy: 1e-6)
        XCTAssertEqual(L.preview.minY, 28 + 3, accuracy: 1e-6, "preview after the bar row + gap")
        XCTAssertEqual(L.preview.height, 50, accuracy: 1e-6)
        // control rows start after preview + gap; 3 rows 4.5 apart.
        let top = 28 + 3 + 50 + 3
        XCTAssertEqual(L.fill.minY, CGFloat(top), accuracy: 1e-6)
        XCTAssertEqual(L.rowH, (233 - CGFloat(top) - 4.5 * 2) / 3, accuracy: 1e-6)
        let colW = (360 - 3 * 3) / 4.0
        XCTAssertEqual(L.fill.width, CGFloat(colW), accuracy: 1e-6, "4 equal columns, 3 apart")
        // row 1 FILL·SPEED·LENGTH·ORDER, row 2 RANKS·SWELL·HITS·ROLL, row 3 CHANCE·BREAK·LAND·spare.
        XCTAssertEqual(L.fill.minX, 0, accuracy: 1e-6)
        XCTAssertEqual(L.order.minX, L.roll.minX, accuracy: 1e-6, "ORDER over ROLL (col 4)")
        XCTAssertEqual(L.speed.minX, L.swell.minX, accuracy: 1e-6, "SPEED over SWELL (col 2)")
        XCTAssertEqual(L.length.minX, L.hits.minX, accuracy: 1e-6, "LENGTH over HITS (col 3)")
        XCTAssertEqual(L.chance.minX, L.ranks.minX, accuracy: 1e-6, "CHANCE under RANKS (col 1)")
        XCTAssertEqual(L.ranks.minY, L.swell.minY, accuracy: 1e-6)
        XCTAssertEqual(L.chance.minY, L.brk.minY, accuracy: 1e-6)
        XCTAssertGreaterThan(L.land.minY, L.swell.minY, "row 3 below row 2")
        // §4.4 the chips sit in SPEED's / RANKS's top-trailing corner, 13 pt.
        XCTAssertEqual(L.curveChip.width, 13, accuracy: 1e-6)
        XCTAssertEqual(L.curveChip.maxX, L.speed.maxX - 2, accuracy: 1e-6)
        XCTAssertEqual(L.curveChip.minY, L.speed.minY + 2, accuracy: 1e-6)
        XCTAssertEqual(L.shapeChip.maxX, L.ranks.maxX - 2, accuracy: 1e-6)
    }

    // §3.1 — the loop length drives the bar-tile count; §5 the preview shrinks then vanishes on a short card.
    func testLoopCountsAndPreviewShrink() {
        XCTAssertEqual(euclideousFillBlockLayout(box: CGSize(width: 360, height: 233), loop: 4).barTiles.count, 4)
        XCTAssertEqual(euclideousFillBlockLayout(box: CGSize(width: 360, height: 233), loop: 16).barTiles.count, 16)
        XCTAssertEqual(euclideousFillBlockLayout(box: CGSize(width: 360, height: 233), loop: 8).previewH, 50, accuracy: 1e-6)
        XCTAssertEqual(euclideousFillBlockLayout(box: CGSize(width: 360, height: 190), loop: 8).previewH, 36, accuracy: 1e-6, "< 200 ⇒ 36")
        XCTAssertEqual(euclideousFillBlockLayout(box: CGSize(width: 360, height: 170), loop: 8).previewH, 0, accuracy: 1e-6, "< 180 ⇒ gone")
    }

    // §4.4 — value text, incl. ROLL / CHANCE.
    func testValueText() {
        var l = EuclidLine()
        l.fillSpeed = 0; XCTAssertEqual(euclideousFillFieldValueText(.speed, l), "\u{00D7}\u{00BD}")   // ×½
        l.fillSpeed = 4; XCTAssertEqual(euclideousFillFieldValueText(.speed, l), "\u{00D7}4")
        l.fillLength = 0; XCTAssertEqual(euclideousFillFieldValueText(.length, l), "BAR")
        l.fillRanks = -7; XCTAssertEqual(euclideousFillFieldValueText(.ranks, l), "\u{2212}7")            // −7
        l.fillSwell = 2; XCTAssertEqual(euclideousFillFieldValueText(.swell, l), "+2")
        l.fillRoll = 0; XCTAssertEqual(euclideousFillFieldValueText(.roll, l), "OFF")
        l.fillRoll = 3; XCTAssertEqual(euclideousFillFieldValueText(.roll, l), "3")
        l.fillChance = 50; XCTAssertEqual(euclideousFillFieldValueText(.chance, l), "50%")
        l.fillChance = 100; XCTAssertEqual(euclideousFillFieldValueText(.chance, l), "100%")
    }

    // §4.3 — index round-trip incl. ROLL / CHANCE; defaults.
    func testIndexAndRoundTrip() {
        var l = EuclidLine()
        euclideousFillSetFieldIndex(.roll, 4, &l); XCTAssertEqual(l.fillRoll, 4); XCTAssertEqual(euclideousFillFieldIndex(.roll, l), 4)
        euclideousFillSetFieldIndex(.chance, 0, &l); XCTAssertEqual(l.fillChance, 25); XCTAssertEqual(euclideousFillFieldIndex(.chance, l), 0)
        euclideousFillSetFieldIndex(.chance, 3, &l); XCTAssertEqual(l.fillChance, 100); XCTAssertEqual(euclideousFillFieldIndex(.chance, l), 3)
        XCTAssertEqual(EuclideousFillField.roll.defaultIndex, 0)
        XCTAssertEqual(EuclideousFillField.chance.defaultIndex, 3)
    }

    // §4.4/§4.5 — the curve / shape chips and the ORDER / HITS selectors cycle and reset.
    func testChipsAndSelectors() {
        var l = EuclidLine()
        XCTAssertEqual(euclideousFillCurveChipText(l), "STDY"); XCTAssertFalse(euclideousFillCurveIsRush(l))
        euclideousFillCycleCurve(&l); XCTAssertEqual(euclideousFillCurveChipText(l), "RUSH"); XCTAssertTrue(euclideousFillCurveIsRush(l))
        euclideousFillCycleCurve(&l); XCTAssertEqual(euclideousFillCurveChipText(l), "STDY")
        XCTAssertEqual(euclideousFillShapeChipText(l), "CLB")
        euclideousFillCycleShape(&l); XCTAssertEqual(euclideousFillShapeChipText(l), "ARC")
        euclideousFillCycleShape(&l); XCTAssertEqual(euclideousFillShapeChipText(l), "SHF")
        euclideousFillCycleShape(&l); XCTAssertEqual(euclideousFillShapeChipText(l), "CLB")
        // ORDER cycles FWD → REV → BOUNCE → SHUF → FWD; reset → FWD (and clears the retired reverse flag).
        XCTAssertEqual(euclideousFillSelectorText(.order, l), "FWD")
        euclideousFillCycleSelector(.order, &l); XCTAssertEqual(euclideousFillSelectorText(.order, l), "REV")
        euclideousFillCycleSelector(.order, &l); euclideousFillCycleSelector(.order, &l); XCTAssertEqual(euclideousFillSelectorText(.order, l), "SHUF")
        euclideousFillCycleSelector(.order, &l); XCTAssertEqual(euclideousFillSelectorText(.order, l), "FWD")
        euclideousFillCycleSelector(.order, &l); euclideousFillResetSelector(.order, &l); XCTAssertEqual(euclideousFillSelectorText(.order, l), "FWD"); XCTAssertNil(l.fillReverse)
        // HITS cycles KEEP → ALL → FLIP → KEEP.
        XCTAssertEqual(euclideousFillSelectorText(.hits, l), "KEEP")
        euclideousFillCycleSelector(.hits, &l); XCTAssertEqual(euclideousFillSelectorText(.hits, l), "ALL")
        euclideousFillCycleSelector(.hits, &l); euclideousFillCycleSelector(.hits, &l); XCTAssertEqual(euclideousFillSelectorText(.hits, l), "KEEP")
    }

    // §8 — VoiceOver.
    func testVoiceOver() {
        var l = EuclidLine(); l.fillSpeed = 3
        XCTAssertEqual(euclideousFillFieldAX(.speed, l), "Fill speed, times two")
        l.fillRoll = 2; XCTAssertEqual(euclideousFillFieldAX(.roll, l), "Fill roll, two")
        l.fillChance = 75; XCTAssertEqual(euclideousFillFieldAX(.chance, l), "Fill chance, 75 percent")
        XCTAssertEqual(euclideousFillSelectorAX(.order, l), "Fill order, forward")
        XCTAssertEqual(euclideousFillBarAX(3, on: true, current: true), "Fill bar 4, on, current")
        XCTAssertEqual(euclideousFillBoolAX("break", on: true), "Fill break, on")
    }
}
