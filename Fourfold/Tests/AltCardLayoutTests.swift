//  AltCardLayoutTests.swift — ALT ferry (2026-11-14) §5 / §9.15: the pure card layout. The real card bodies (landscape 360.67 × 233, portrait 367 × 233.67) are both under the 236 pt full total, so §5.1's band-shrink fallback applies at the reference — the ferry's "about 240" is ~7 high; this test documents B = 233.

import XCTest

final class AltCardLayoutTests: XCTestCase {
    private func near(_ a: CGFloat, _ b: CGFloat, _ what: String, _ acc: CGFloat = 0.01) { XCTAssertEqual(a, b, accuracy: acc, what) }
    private func landscape() -> CGSize { CGSize(width: EuclideousLaneCardMetrics.innerWidth(cardWidth: 380.67), height: EuclideousLaneCardMetrics.contentAreaH(cardHeight: 301)) }
    private func portrait() -> CGSize { CGSize(width: EuclideousLaneCardMetrics.innerWidth(cardWidth: 387), height: EuclideousLaneCardMetrics.contentAreaH(cardHeight: 301.67)) }

    // §9.15 — the frames at the landscape reference; §5.1's fallback applies (B 233 < 236 ⇒ bands shrink equally).
    func testTheFramesAtTheLandscapeReference() {
        let size = landscape(); let BW = size.width, B = size.height
        XCTAssertEqual(B, 233, accuracy: 0.01); XCTAssertEqual(BW, 360.67, accuracy: 0.01)
        let L = euclideousAltCardLayout(size: size)
        XCTAssertEqual(L.appliedCase, .bandsShrunk, "B 233 < 236 ⇒ the bands shrink equally (the ferry's ~240 is high)")
        // §5.1 rows, top to bottom: UNIT 42 · gap 5 · cycle 13 · gap 5 · band · gap 5 · band
        XCTAssertEqual(L.unitPanel, CGRect(x: 0, y: 0, width: BW, height: 42))
        XCTAssertEqual(L.cycleStrip, CGRect(x: 0, y: 47, width: BW, height: 13))
        near(L.riff.panel.minY, 65, "RIFF band y"); near(L.riff.panel.height, 81.5, "band shrunk to 81.5 (83 − 3/2)")
        near(L.stack.panel.minY, 151.5, "STACK band y"); near(L.stack.panel.maxY, B, "the two bands reach the body bottom")
        // §5.2 UNIT: 4 segments totalling 186, then two steppers sharing the rest
        XCTAssertEqual(L.unitSegments.count, 4); near(L.unitSegments[0].minX, 4 + 3, "segments inset 3 inside the 186 group")
        XCTAssertLessThanOrEqual(L.unitSegments[3].maxX, 4 + 186, "the 4 segments stay within the 186-wide group")
        near(L.altStepper.maxX, BW - 4, "the ALT stepper ends at the panel's trailing inset")
        // §5.4 band grid columns: part tile 35, then 31 | 118 | 31 | rest at x 44 / 79 / 201 / 236
        near(L.riff.partTile.width, 35, "part tile 35 wide"); near(L.riff.partTile.minX, 4, "part tile at the inset")
        near(L.riff.outPill.minX, 44, "OUT pill column"); near(L.riff.tokens.minX, 79, "tokens column"); near(L.riff.tokens.width, 118, "tokens 118 wide")
        near(L.riff.octPill.minX, 201, "OCT pill column"); near(L.riff.octBoxes.minX, 236, "OCT boxes column")
        near(L.riff.octBoxes.maxX, BW - 4, "the OCT boxes reach the trailing inset")
        // OUT above VEL, OCT above GATE, tokens above the VEL slider at matching widths (§5.4)
        near(L.riff.velPill.minX, L.riff.outPill.minX, "VEL under OUT"); near(L.riff.gatePill.minX, L.riff.octPill.minX, "GATE under OCT")
        near(L.riff.velSlider.minX, L.riff.tokens.minX, "VEL slider under the tokens"); near(L.riff.velSlider.width, L.riff.tokens.width, "matching widths")
    }

    func testPortraitAlsoShrinks() {
        let L = euclideousAltCardLayout(size: portrait())
        XCTAssertEqual(L.appliedCase, .bandsShrunk)
        near(L.riff.panel.height, 83 - (236 - 233.67) / 2, "portrait bands shrink by half the 2.33 shortfall")
        near(L.stack.panel.maxY, portrait().height, "the bands reach the body bottom")
    }

    // §5.1's ladder at synthetic sizes: full ≥ 236, bandsShrunk down to the 75 floor, then cantFit.
    func testTheShrinkLadder() {
        func c(_ B: CGFloat) -> EuclideousAltCardLayout.Case { euclideousAltCardLayout(size: CGSize(width: 360.67, height: B)).appliedCase }
        XCTAssertEqual(c(236), .full); XCTAssertEqual(c(240), .full)
        XCTAssertEqual(c(233), .bandsShrunk); XCTAssertEqual(c(220), .bandsShrunk)   // 83 − (236−220)/2 = 75, still fits
        XCTAssertEqual(c(219), .cantFit)                                            // shortfall 17 ⇒ band would be 74.5 < 75
        // at full the bands are 83 and the rows are 35/31 gap 4
        let full = euclideousAltCardLayout(size: CGSize(width: 360.67, height: 240))
        near(full.riff.panel.height, 83, "full band height")
        near(full.riff.velPill.minY - full.riff.outPill.minY, 37, "row-2 pill below row-1 pill: a 35-tall row + 4 gap, each pill centred in its own row (35 vs 31 tall) ⇒ 37")
    }

    // §5.3 — the cycle strip's cells: L = main + alt cells, equal, 3 apart, the first `main` are main cells.
    func testCycleCells() {
        let strip = CGRect(x: 10, y: 0, width: 200, height: 13)
        let cells = euclideousAltCycleCells(main: 3, alt: 1, strip: strip)
        XCTAssertEqual(cells.count, 4)
        near(cells[0].minX, 10, "the first cell at the strip's leading edge")
        near(cells[1].minX - cells[0].minX, cells[0].width + 3, "cells are 3 pt apart")
        near(cells.last!.maxX, 210, "the last cell reaches the strip's trailing edge")
        // m 1 a 2 ⇒ 3 cells, cell 0 main, cells 1,2 alt (the caller colours by index < m)
        XCTAssertEqual(euclideousAltCycleCells(main: 1, alt: 2, strip: strip).count, 3)
    }
}
