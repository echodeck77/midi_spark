//  PageLayoutTests.swift
//  PAGE LAYOUT ferry (2026-10-19, "six equal boxes in both orientations"): the pure page function and the formulas it feeds. Every number a
//  view draws a box with comes from `euclideousPageLayout`; these tests pin it at Paul's two reference screenshots (1190 × 726 landscape,
//  814 × 1102 portrait) and sweep it across sizes. The views themselves have no macOS test-target reach — device verification owns them.
//
//  SOURCE-WINS NOTE (ferry: "where source disagrees about an existing value, source wins"): FX's strip and LANES' blocks sit at panel y 32 / 60 in
//  source (8 padding + 20 tab row + sp4), not the spec's 35 / 63. The FX / LANES expectations below are therefore the source-consistent ones:
//  FX rowH = (box − 126) / 6, LANES laneH = (box − 100) / 4 (the spec's 31.67 / 31.78 and 54 / 54.17 are each 0.5–0.75pt smaller).

import XCTest

final class PageLayoutTests: XCTestCase {

    private func near(_ r: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.minX, x, accuracy: 0.01, "\(msg) x", file: file, line: line); XCTAssertEqual(r.minY, y, accuracy: 0.01, "\(msg) y", file: file, line: line)
        XCTAssertEqual(r.width, w, accuracy: 0.01, "\(msg) w", file: file, line: line); XCTAssertEqual(r.height, h, accuracy: 0.01, "\(msg) h", file: file, line: line)
    }
    private let landscapeRef = CGSize(width: 1190, height: 726)
    private let portraitRef = CGSize(width: 814, height: 1102)
    private var land: EuclideousPageLayout { euclideousPageLayout(size: landscapeRef) }
    private var port: EuclideousPageLayout { euclideousPageLayout(size: portraitRef) }

    // MARK: 1–2. the references

    func testLandscapeReferenceIsThreeColumnsByTwoRowsOfSixEqualBoxes() {
        let p = land
        XCTAssertTrue(p.isLandscape); XCTAssertEqual(p.headerKind, .a, "1158 wide, landscape: the header is layout A")
        XCTAssertEqual(p.box.width, 380.67, accuracy: 0.01); XCTAssertEqual(p.box.height, 319, accuracy: 1e-9)
        near(p.lanes[0], 16, 64, 380.67, 319, "lane 1"); near(p.lanes[1], 404.67, 64, 380.67, 319, "lane 2")
        near(p.lanes[2], 16, 391, 380.67, 319, "lane 3"); near(p.lanes[3], 404.67, 391, 380.67, 319, "lane 4")
        near(p.riff, 793.33, 64, 380.67, 319, "riff panel"); near(p.seq, 793.33, 391, 380.67, 319, "MIX | LANES | FX panel")
        XCTAssertEqual(p.gutterX, 400.67, accuracy: 0.01, "was 378.5")
        XCTAssertEqual(p.seq.maxX, 1174, accuracy: 1e-9, "nothing past x 1174"); XCTAssertEqual(p.seq.maxY, 710, accuracy: 1e-9, "nothing past y 710")
        XCTAssertEqual(p.riffLeadingX, 777.33, accuracy: 0.01); XCTAssertEqual(p.laneCentreX, 384.67, accuracy: 0.01)
        XCTAssertTrue(p.floors.isEmpty, "the reference flags nothing: \(p.floors)")
    }
    func testPortraitReferenceIsTwoColumnsByThreeRowsAndFitsTheView() {
        let p = port
        XCTAssertFalse(p.isLandscape); XCTAssertEqual(p.headerKind, .b, "782 wide, portrait: layout B")
        XCTAssertEqual(p.box.width, 387, accuracy: 1e-9); XCTAssertEqual(p.box.height, 319.67, accuracy: 0.01)
        near(p.lanes[0], 16, 111, 387, 319.67, "lane 1"); near(p.lanes[1], 411, 111, 387, 319.67, "lane 2")
        near(p.lanes[2], 16, 438.67, 387, 319.67, "lane 3"); near(p.lanes[3], 411, 438.67, 387, 319.67, "lane 4")
        near(p.riff, 16, 766.33, 387, 319.67, "riff panel"); near(p.seq, 411, 766.33, 387, 319.67, "MIX | LANES | FX panel")
        XCTAssertEqual(p.gutterX, 407, accuracy: 1e-9, "was 442.5")
        XCTAssertEqual(p.seq.maxX, 798, accuracy: 1e-9, "the second column ends 16pt inside the 814 view (it ran to 869 before)")
        XCTAssertEqual(p.seq.maxY, 1086, accuracy: 0.01)
        XCTAssertEqual(p.laneCentreX, 391, accuracy: 1e-9, "= the container's centre, as portrait's header always used")
        XCTAssertTrue(p.floors.isEmpty, "the reference flags nothing: \(p.floors)")
    }
    func testChooserIsTheViewsOwnWiderThanTall() {
        XCTAssertTrue(euclideousPageLayout(size: CGSize(width: 1190, height: 726)).isLandscape)
        XCTAssertFalse(euclideousPageLayout(size: CGSize(width: 814, height: 1102)).isLandscape)
        XCTAssertFalse(euclideousPageLayout(size: CGSize(width: 800, height: 800)).isLandscape, "square is not strictly wider than tall")
        // the header kind comes from the header's own ladder on the page's container width
        // 2026-10-20: two offsetting changes — output rings to 75% dropped OUTPUTS by 44pt (839.86 layout A
        // need), then the HOLD/LATCH header buttons widened NOTES by 114pt (953.86) — net +70, still short of 868.
        XCTAssertEqual(euclideousPageLayout(size: CGSize(width: 900, height: 600)).headerKind, .b, "868 < the now-953.86 layout A needs")
        XCTAssertEqual(euclideousPageLayout(size: CGSize(width: 1190, height: 600)).headerKind, .a)
        XCTAssertEqual(euclideousPageLayout(size: CGSize(width: 400, height: 900)).headerKind, .c)
    }

    // MARK: 3. the sweep

    func testEveryFrameLiesInsideTheViewBoxesAreEightApartAndAllSixAreTheSameSize() {
        let kinds: [EuclideousHeaderLayout.Kind] = [.a, .b, .c]
        for w in stride(from: 600, through: 1400, by: 50) { for h in stride(from: 600, through: 1400, by: 50) {
            for kind in kinds {
                let size = CGSize(width: CGFloat(w), height: CGFloat(h))
                let p = euclideousPageLayout(size: size, headerKind: kind)
                let all = p.lanes + [p.riff, p.seq]
                let top = EuclideousPageMetrics.top(kind)
                let tag = "\(w)×\(h) \(kind)"
                XCTAssertEqual(p.isLandscape, w > h, tag)
                for f in all {
                    XCTAssertEqual(f.width, p.box.width, accuracy: 1e-9, "\(tag): same width"); XCTAssertEqual(f.height, p.box.height, accuracy: 1e-9, "\(tag): same height")
                    XCTAssertGreaterThanOrEqual(f.minX, 16 - 1e-9, tag); XCTAssertLessThanOrEqual(f.maxX, size.width - 16 + 1e-9, "\(tag): right margin")
                    XCTAssertGreaterThanOrEqual(f.minY, top - 1e-9, "\(tag): below the header"); XCTAssertLessThanOrEqual(f.maxY, size.height - 16 + 1e-9, "\(tag): bottom margin")
                }
                // adjacency: lanes 1|2 and 3|4 are side by side, 1/3 and 2/4 stacked — all 8 apart
                XCTAssertEqual(p.lanes[1].minX - p.lanes[0].maxX, 8, accuracy: 1e-9, tag); XCTAssertEqual(p.lanes[3].minX - p.lanes[2].maxX, 8, accuracy: 1e-9, tag)
                XCTAssertEqual(p.lanes[2].minY - p.lanes[0].maxY, 8, accuracy: 1e-9, tag); XCTAssertEqual(p.lanes[3].minY - p.lanes[1].maxY, 8, accuracy: 1e-9, tag)
                if p.isLandscape {
                    XCTAssertEqual(p.riff.minX - p.lanes[1].maxX, 8, accuracy: 1e-9, tag); XCTAssertEqual(p.seq.minY - p.riff.maxY, 8, accuracy: 1e-9, tag)
                    XCTAssertEqual(p.seq.maxX, size.width - 16, accuracy: 1e-9, "\(tag): flush with the right margin")
                } else {
                    XCTAssertEqual(p.riff.minY - p.lanes[2].maxY, 8, accuracy: 1e-9, tag); XCTAssertEqual(p.seq.minX - p.riff.maxX, 8, accuracy: 1e-9, tag)
                    XCTAssertEqual(p.seq.maxX, size.width - 16, accuracy: 1e-9, "\(tag): flush with the right margin")
                }
                XCTAssertEqual(p.seq.maxY, size.height - 16, accuracy: 1e-9, "\(tag): flush with the bottom margin")
                XCTAssertEqual(p.gutterX, p.lanes[0].maxX + 4, accuracy: 1e-9, "\(tag): the gutter's centre is 4 past the first column")
            }
        } }
    }
    func testHeaderKindThresholdsAreTheLaddersOwn() {
        let full = euclideousHeaderGroupWidths(compact: false)
        let aNeeds = full.brand + full.outputs + full.notes + full.utilities + 3 * full.gap
        let bNeeds = full.brand + full.outputs + full.utilities + 2 * full.gap
        XCTAssertEqual(euclideousHeaderKind(containerW: aNeeds, isLandscape: true), .a)
        XCTAssertEqual(euclideousHeaderKind(containerW: aNeeds - 0.01, isLandscape: true), .b)
        XCTAssertEqual(euclideousHeaderKind(containerW: 5000, isLandscape: false), .b, "portrait never uses A")
        XCTAssertEqual(euclideousHeaderKind(containerW: bNeeds - 0.01, isLandscape: false), .c)
        for cw in stride(from: 300, through: 1500, by: 7) { for landscape in [true, false] {
            let l = euclideousHeaderLayout(containerW: CGFloat(cw), isLandscape: landscape, riffLeadingX: 0, laneCentreX: CGFloat(cw) / 2)
            XCTAssertEqual(l.kind, euclideousHeaderKind(containerW: CGFloat(cw), isLandscape: landscape), "\(cw) \(landscape)")
        } }
    }

    // MARK: 4–7. what each box does with its frame

    func testLaneCardZonesAtBothReferences() {
        for (p, upper, rowA) in [(land, 131.0, 89.0), (port, 131.67, 89.67)] {
            let contentH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: p.box.height)
            XCTAssertEqual(contentH - 80 - 4, upper, accuracy: 0.01, "upper zone = card height − 188")
            XCTAssertEqual(p.box.height - 188, upper, accuracy: 0.01)
            let r = euclideousRiffTabLayout(contentAreaH: contentH, fullWidth: EuclideousLaneCardMetrics.innerWidth(cardWidth: p.box.width))
            XCTAssertEqual(r.rowAHeight, rowA, accuracy: 0.01, "RIFF's row A is 89 against its floor of 82")
            XCTAssertFalse(r.underFloor)
        }
        // widths: landscape content 360.67, portrait 367
        let rl = euclideousRiffTabLayout(contentAreaH: land.box.height - 104, fullWidth: land.box.width - 20)
        XCTAssertEqual(rl.rightColumnWidth, 266.67, accuracy: 0.01)
        // Floors ferry (2026-10-23): 4 buttons over 3 gaps now (PENDULUM removed 2026-10-22; was ÷5 over 4 gaps, stale since then).
        XCTAssertEqual(rl.directionButtonWidth, 63.67, accuracy: 0.01)
        XCTAssertEqual(rl.hitStepButtonWidth, 106.33, accuracy: 0.01); XCTAssertEqual(rl.onRestButtonWidth, 96.22, accuracy: 0.01); XCTAssertEqual(rl.valueStepperWidth, 87.17, accuracy: 0.01)
        let rp = euclideousRiffTabLayout(contentAreaH: port.box.height - 104, fullWidth: port.box.width - 20)
        XCTAssertEqual(rp.directionButtonWidth, 65.25, accuracy: 0.01); XCTAssertEqual(rp.hitStepButtonWidth, 109.5, accuracy: 0.01)
        XCTAssertEqual(rp.onRestButtonWidth, 98.33, accuracy: 0.01); XCTAssertEqual(rp.valueStepperWidth, 88.75, accuracy: 0.01)
    }
    /// Floors ferry (2026-10-23): the WALK strip (read-only) drops out exactly when showing it would leave
    /// the direction row (real controls) under its own 32pt floor — never above, never below.
    func testRiffTabWalkStripDropsExactlyAtTheDirectionRowFloor() {
        // rowAHeight computed so that (rowAHeight - 4 - 38) lands exactly 1pt either side of the 32pt floor.
        // rowAHeight = upperH - 4 - 38, upperH = contentAreaH - 80 - 4 → solve contentAreaH for each case.
        func layout(rowAHeight target: CGFloat) -> EuclideousRiffTabLayout {
            let upperH = target + 4 + 38
            let contentAreaH = upperH + 80 + 4
            return euclideousRiffTabLayout(contentAreaH: contentAreaH, fullWidth: 338.5)
        }
        let justAbove = layout(rowAHeight: 32 + 4 + 38 + 1)   // directionRowIfShown = 33
        XCTAssertTrue(justAbove.showWalkStrip); XCTAssertEqual(justAbove.directionRowHeight, 33, accuracy: 0.01)
        let justBelow = layout(rowAHeight: 32 + 4 + 38 - 1)   // directionRowIfShown = 31 → strip drops, direction row gets the whole row A
        XCTAssertFalse(justBelow.showWalkStrip); XCTAssertEqual(justBelow.directionRowHeight, justBelow.rowAHeight, accuracy: 0.01)
        XCTAssertGreaterThan(justBelow.directionRowHeight, 31, "dropping the strip must leave the direction row BETTER off, not merely unchanged")
    }
    /// Floors ferry (2026-10-23): TILT's EARLY/LATE end-labels — pure annotation, not the control — drop
    /// out below their own floor, independent of (and tighter than) the inert `rhythmZonesFloor`(192).
    func testRhythmEndLabelsDropBelowTheirOwnFloor() {
        XCTAssertTrue(EuclideousRhythmGeometry.showsEndLabels(rowH: 28))
        XCTAssertTrue(EuclideousRhythmGeometry.showsEndLabels(rowH: 38.67), "the reference row height")
        XCTAssertFalse(EuclideousRhythmGeometry.showsEndLabels(rowH: 27.99))
    }
    func testMixAtBothReferencesFillsTheBoxAndClearsItsFloors() {
        for (p, areaW, areaH, cellW, rowH, padH, outW) in [(land, 364.67, 275.0, 81.17, 129.5, 69.5, 38.58), (port, 371.0, 275.67, 82.75, 129.83, 69.83, 39.38)] {
            let area = euclideousMixGridArea(panelWidth: p.box.width, panelHeight: p.box.height)
            XCTAssertEqual(area.width, areaW, accuracy: 0.01); XCTAssertEqual(area.height, areaH, accuracy: 0.01)
            let g = euclideousMixGrid(width: area.width, height: area.height)
            XCTAssertEqual(g.cellW, cellW, accuracy: 0.01); XCTAssertEqual(g.rowH, rowH, accuracy: 0.01); XCTAssertEqual(g.padH, padH, accuracy: 0.01)
            XCTAssertFalse(g.belowFloors); XCTAssertGreaterThanOrEqual(g.padH, EuclideousMixMetrics.floorPadH)
            XCTAssertEqual((g.cellW * 2 + 4 - 4 * 3) / 4, outW, accuracy: 0.01, "OUT buttons: four across the lane panel's inside width (a RIFF + NOTES pair), 4 apart")
            // §9.5's fit rule (the rotated name it chose is gone since the CLARITY PASS, the pure function stays): VEL — 30.5 / 30.8 available against the 44.8 "VELOCITY" needs
            XCTAssertEqual(euclideousMixVelocityDisplayName(plotH: g.padH - EuclideousMixMetrics.gateStripH), "VEL")
        }
        // the old portrait panel (393 × 248) is what drew nothing: nominal padH would be 34 (CLARITY PASS), but the
        // fair-share fallback drops the stepper/OUT row to their compact floors and buys the pad back to 46.
        let old = euclideousMixGridArea(panelWidth: 393, panelHeight: 248)
        let oldGrid = euclideousMixGrid(width: old.width, height: old.height)
        XCTAssertEqual(oldGrid.padH, 46, accuracy: 1e-9)
        XCTAssertEqual(oldGrid.stepperH, 18, accuracy: 1e-9); XCTAssertEqual(oldGrid.outRowH, 14, accuracy: 1e-9)
    }
    func testMixFairShareDropsTheStepperAndOutRowTogetherExactlyAtThePadFloor() {
        // the fallback triggers when innerH − nominalBelowPad(52) < minPadH(64), i.e. innerH < 116 — pin both sides.
        func gridFor(innerH: CGFloat) -> EuclideousMixGrid {
            // innerH = (height − sp16)/2 − panelPad*2  ⇒  height = (innerH + panelPad*2) * 2 + sp16
            let height = (innerH + EuclideousMixMetrics.panelPad * 2) * 2 + EuclideousMixMetrics.sp16
            return euclideousMixGrid(width: 400, height: height)
        }
        let atFloor = gridFor(innerH: 116)
        XCTAssertEqual(atFloor.stepperH, 24, accuracy: 1e-9); XCTAssertEqual(atFloor.outRowH, 20, accuracy: 1e-9)
        XCTAssertEqual(atFloor.padH, 64, accuracy: 1e-9, "innerH 116 − nominal 52 = 64, exactly minPadH — nominal, not compact")
        let justUnder = gridFor(innerH: 115.99)
        XCTAssertEqual(justUnder.stepperH, 18, accuracy: 1e-9); XCTAssertEqual(justUnder.outRowH, 14, accuracy: 1e-9)
        XCTAssertEqual(justUnder.padH, 115.99 - 40, accuracy: 1e-9, "compact belowPad is 40 (4+18+4+14), buying 12pt back")
    }
    func testRiffGridAtBothReferences() {
        // RIFF PANEL ferry (2026-10-19) §1: the tabs are 20 tall, the grid starts at y 34, four 8pt rails (41) sit under it — rows (box − 119) / 8 = 25 / 25.08.
        // (The layout ferry's own chrome was 77 and its pure height/rows pair is GONE: the panel's inside is laid out by `euclideousRiffPanelLayout`, once.)
        XCTAssertEqual(EuclideousRiffPanelMetrics.chromeH(), 119)
        let l = euclideousRiffPanelLayout(box: land.box), p = euclideousRiffPanelLayout(box: port.box)
        XCTAssertEqual(l.cellW, 37.83, accuracy: 0.01); XCTAssertEqual(l.rowH, 25, accuracy: 1e-9)
        XCTAssertEqual(p.cellW, 38.63, accuracy: 0.01); XCTAssertEqual(p.rowH, 25.08, accuracy: 0.01)
    }
    func testFXRowsFollowThePanelAndItsColumnsAreTheRiffGrids() {
        // rows share the height: (content − 86) / 6 with content = box − 40; 29 at the old 260-tall content (a 300pt box); no cap, floor 24
        XCTAssertEqual(EuclideousFXLayout.fixedHeight, 86)
        XCTAssertEqual(euclideousFXRowH(contentHeight: 260), 29, accuracy: 1e-9)
        for (p, rowH) in [(land, 32.17), (port, 32.28)] {
            let body = euclideousSeqTabBodySize(panelWidth: p.box.width, panelHeight: p.box.height)
            XCTAssertEqual(body.height, p.box.height - 40, accuracy: 1e-9)
            let l = euclideousFXLayout(width: body.width, height: body.height)
            XCTAssertEqual(l.rowH, rowH, accuracy: 0.01)
            XCTAssertEqual(l.hintTop + EuclideousFXLayout.hintH, body.height, accuracy: 1e-9, "the hint ends sp8 above the panel's bottom, whatever the height")
            XCTAssertEqual(l.cellW, euclideousRiffCellW(maxWidth: p.box.width), "the columns are the riff grid's own function")
            // each FX column's offset from ITS panel's leading edge = the riff grid's column's offset from the riff panel's (8 pad + 30 label + 4 gap, then cellW + 4)
            for c in 0..<8 {
                let fxOffset = 8 + l.colLeft(c)
                let riffOffset = 8 + 30 + 4 + CGFloat(c) * (euclideousRiffCellW(maxWidth: p.box.width) + 4)
                XCTAssertEqual(fxOffset, riffOffset, accuracy: 1e-9, "column \(c)")
                // …and on the page: landscape the panel sits directly under the riff panel (same x), so the edges are equal on the page too
                if p.isLandscape { XCTAssertEqual(p.seq.minX + fxOffset, p.riff.minX + riffOffset, accuracy: 1e-9) }
            }
        }
        XCTAssertEqual(euclideousFXLayout(width: 360, height: 245).rowH, 26.5, accuracy: 1e-9, "a shorter panel still shares the missing height")
        XCTAssertEqual(euclideousFXLayout(width: 360, height: 100).rowH, 24, "…down to 24, then no further")
        XCTAssertEqual(euclideousFXLayout(width: 360, height: 400).rowH, (400 - 86) / 6, accuracy: 1e-9, "no upper cap now")
        XCTAssertEqual(euclideousFXRowH(contentHeight: 303 - 40), 29.5, accuracy: 1e-9, "the old 303 frame: 29.5 here (the ferry text's 29 assumes the strip at y 35; source has it at 32)")
    }
    func testLanesBlocksAndCellsAtBothReferences() {
        for (p, cellW, laneH) in [(land, 18.29, 54.75), (port, 18.69, 54.92)] {
            let body = euclideousSeqTabBodySize(panelWidth: p.box.width, panelHeight: p.box.height)
            let l = euclideousLanesLayout(width: body.width, height: body.height)
            XCTAssertEqual(l.cellW, cellW, accuracy: 0.01); XCTAssertEqual(l.laneH, laneH, accuracy: 0.01)
            XCTAssertEqual(l.legendTop + EuclideousLanesLayout.legendH, body.height, accuracy: 1e-9, "the hint row sits sp8 above the panel's bottom")
            XCTAssertEqual(l.gridX + 16 * l.cellW + 15 * EuclideousLanesLayout.cellGap, body.width, accuracy: 1e-9, "16 cells + 2pt gaps tile the grid width")
        }
        XCTAssertEqual(euclideousLanesLayout(width: 394, height: 303 - 40).laneH, 50.75, accuracy: 1e-9, "the old 303 frame (the ferry text's 50 assumes the blocks at y 63; source has them at 60)")
    }

    // MARK: 8. the header's inputs

    private func headerFor(_ p: EuclideousPageLayout, _ size: CGSize) -> EuclideousHeaderLayout {
        euclideousHeaderLayout(containerW: size.width - 32, isLandscape: p.isLandscape, riffLeadingX: p.riffLeadingX, laneCentreX: p.laneCentreX)
    }
    /// Page x of ring `i`'s centre: container offset (16) + the OUTPUTS group's x + its caption lead + i × pitch + pitch / 2.
    private func ringCentre(_ l: EuclideousHeaderLayout, _ i: Int) -> CGFloat {
        16 + l.outputs.x + l.widths.outputsLead + CGFloat(i) * EuclideousHeaderMetrics.ringPitch + EuclideousHeaderMetrics.ringPitch / 2
    }
    func testRingsCentreOnTheLaneGutterInBothOrientations() {
        let hl = headerFor(land, landscapeRef)
        XCTAssertEqual(hl.kind, .a)
        // NARROWED 44→33pt pitch (2026-10-20, output rings to 75%): spacing between ring centres shrank from 44 to 33.
        // LANE LOCK ferry (§2.2): BRAND grew another 52pt (the padlock), so at the 1190 reference the rings' ideal x (centred on the lane gutter) is now LEFT of BRAND's trailing edge + sp16 — they pin flush against
        // BRAND, 17.19pt right of the gutter (before: 351.17 … 450.17, centred). Reported as a consequence of the required BRAND width, not a choice.
        for (i, x) in [368.36, 401.36, 434.36, 467.36].enumerated() { XCTAssertEqual(ringCentre(hl, i), CGFloat(x), accuracy: 0.01, "landscape ring \(i)") }
        XCTAssertEqual(hl.outputs.x, hl.brand.width + hl.widths.gap, accuracy: 1e-9, "the rings are pinned flush against BRAND")
        let hp = headerFor(port, portraitRef)
        XCTAssertEqual(hp.kind, .b); XCTAssertEqual(hp.utilities.x + hp.utilities.width + 16, 798, accuracy: 1e-9, "row 1 now fits: the gear ends at the right margin")
        // LANE LOCK ferry (§2.2): the same pin in portrait (before: 357.5 … 456.5, centred) — 10.86pt right of the gutter.
        for (i, x) in [368.36, 401.36, 434.36, 467.36].enumerated() { XCTAssertEqual(ringCentre(hp, i), CGFloat(x), accuracy: 0.01, "portrait ring \(i)") }
        // the rings sit to the RIGHT of the gutter by exactly how far BRAND pushes them (they used to be centred on it)
        XCTAssertEqual((ringCentre(hl, 1) + ringCentre(hl, 2)) / 2 - land.gutterX, 17.19, accuracy: 0.01)
        XCTAssertEqual((ringCentre(hp, 1) + ringCentre(hp, 2)) / 2 - port.gutterX, 10.86, accuracy: 0.01)
    }
    func testNotesDoesNotMoveAt1190() {
        // layout A: NOTES wants the riff panel's leading edge (777.33 now, 741.12 before) but slides left to sp16 before the 3 utility icons either way
        // WIDENED 312→426 (2026-10-20, HOLD/LATCH header buttons) — NOTES' own width grew 114pt, so its
        // clamped x (which ends at the same point before UTILITIES either way) shifts left by exactly that.
        let l = headerFor(land, landscapeRef)
        XCTAssertEqual(l.notes.x, 1158 - 132 - 16 - 426, accuracy: 1e-9)
        XCTAssertEqual(l.notes.x, 584, accuracy: 1e-9, "today's x at 1190 (741.12 clamped to 584)")
        XCTAssertLessThan(l.notes.x, land.riffLeadingX)
    }

    // MARK: 9. floors

    func testFloorsAreFlaggedNotFixedAtTheOtherSizes() {
        // a guess at the 8.3-inch iPad mini's landscape plugin view: box 355 × 274
        let mini = euclideousPageLayout(size: CGSize(width: 1113, height: 636))
        XCTAssertEqual(mini.headerKind, .a)
        XCTAssertEqual(mini.box.width, 355, accuracy: 1e-9); XCTAssertEqual(mini.box.height, 274, accuracy: 1e-9)
        let area = euclideousMixGridArea(panelWidth: 355, panelHeight: 274)
        let g = euclideousMixGrid(width: area.width, height: area.height)
        // Floors ferry: the nominal 52pt split would leave padH 47 (< minPadH 64), so the stepper/OUT row
        // drop to their compact floors (18/14), buying the pad back 12pt to 59 — cellW is untouched.
        XCTAssertEqual(g.padH, 59, accuracy: 1e-9); XCTAssertEqual(g.cellW, 74.75, accuracy: 1e-9)
        XCTAssertEqual(g.stepperH, 18, accuracy: 1e-9); XCTAssertEqual(g.outRowH, 14, accuracy: 1e-9)
        // Floors ferry: nominal rowH would be 19.375 (chrome 119) but that's under minRowH (24), so the tab
        // row drops to its compact floor (14) and chrome shrinks to 113, buying rowH back to 20.125.
        let miniRiffLayout = euclideousRiffPanelLayout(box: CGSize(width: 355, height: 274))
        XCTAssertEqual(miniRiffLayout.rowH, 20.125, accuracy: 1e-9)
        XCTAssertEqual(miniRiffLayout.tabRowH, 14, accuracy: 1e-9); XCTAssertEqual(miniRiffLayout.labelW, 30, accuracy: 1e-9, "cellW here (34.6) clears minCellW, so the label stays nominal")
        let r = euclideousRiffTabLayout(contentAreaH: 274 - 104, fullWidth: 335)
        XCTAssertEqual(r.rowAHeight, 44, accuracy: 1e-9, "RIFF's row A")
        // Floors ferry (2026-10-23): at this size, showing the WALK strip would leave only 2pt for the
        // direction row, so it drops out and the direction row takes the whole of row A (44) instead —
        // .riffDirectionRow no longer flags here, exactly the fallback's intended effect.
        XCTAssertFalse(r.showWalkStrip); XCTAssertEqual(r.directionRowHeight, 44, accuracy: 1e-9)
        let f = Set(mini.floors)
        XCTAssertTrue(f.isSuperset(of: [.mixCellW, .mixPadH, .rhythmZones, .riffRowA]), "\(f)")
        XCTAssertFalse(f.contains(.riffDirectionRow), "the WALK-strip-drop fallback resolves this at 44pt, clear of the 32pt floor")
        XCTAssertFalse(f.contains(.mixPadHStop), "the fair-share fallback buys padH back to 59, clear of the 48pt stop-floor")
        XCTAssertTrue(f.contains(.riffRows), "20.1 (even after the tab-row fair-share gives it back 0.75) is still under 24"); XCTAssertFalse(f.contains(.fxRows), "FX rows 24.67 clear 24")
        // windowed AUM panels
        let wl = euclideousPageLayout(size: CGSize(width: 900, height: 600))
        XCTAssertEqual(wl.headerKind, .b, "868 wide: B, boxes start at 111")
        XCTAssertEqual(wl.box.width, 284, accuracy: 1e-9); XCTAssertEqual(wl.box.height, 232.5, accuracy: 1e-9)
        XCTAssertTrue(Set(wl.floors).isSuperset(of: [.mixCellW, .mixPadHStop, .rhythmZones, .riffRows, .fxRows]), "\(wl.floors)")
        let wp = euclideousPageLayout(size: CGSize(width: 650, height: 900))   // 600 → 650 (LANE LOCK ferry §2.2): B's floor rose ≈564 → ≈616, so a 600-wide portrait view is layout C now
        XCTAssertEqual(wp.headerKind, .b); XCTAssertEqual(wp.box.width, 305, accuracy: 1e-9); XCTAssertEqual(wp.box.height, (900 - 111 - 32) / 3, accuracy: 1e-9)
        XCTAssertFalse(wp.floors.isEmpty)
        // each flag is exactly its threshold
        XCTAssertTrue(euclideousPageFloors(box: CGSize(width: 380, height: 295)).contains(.rhythmZones), "contentAreaH 191 < 192")
        XCTAssertFalse(euclideousPageFloors(box: CGSize(width: 380, height: 296)).contains(.rhythmZones), "contentAreaH 192")
    }

    // MARK: the bottom safe-area inset (Paul's ruling, 2026-10-19)

    func testTheBottomMarginIsTheLargerOfSixteenAndTheInset() {
        XCTAssertEqual(EuclideousPageMetrics.bottomMargin(inset: 0), 16); XCTAssertEqual(EuclideousPageMetrics.bottomMargin(inset: 9), 16, "an inset of 9 gives a margin of 16")
        XCTAssertEqual(EuclideousPageMetrics.bottomMargin(inset: 20), 20, "an inset of 20 gives 20"); XCTAssertEqual(EuclideousPageMetrics.bottomMargin(inset: 16), 16)
        // the page is laid out on the view's FULL height: an inset of 9 gives back exactly the reference boxes (319 / 319.67)
        let l9 = euclideousPageLayout(size: landscapeRef, bottomInset: 9), p9 = euclideousPageLayout(size: portraitRef, bottomInset: 9)
        XCTAssertEqual(l9, land); XCTAssertEqual(p9, port)
        XCTAssertEqual(l9.box.height, 319, accuracy: 1e-9); XCTAssertEqual(p9.box.height, 319.67, accuracy: 0.01)
        // an inset of 20: the boxes end 20 above the bottom, each a little shorter
        let l20 = euclideousPageLayout(size: landscapeRef, bottomInset: 20), p20 = euclideousPageLayout(size: portraitRef, bottomInset: 20)
        XCTAssertEqual(l20.seq.maxY, 726 - 20, accuracy: 1e-9); XCTAssertEqual(l20.box.height, (726 - 64 - 20 - 8) / 2, accuracy: 1e-9)
        XCTAssertEqual(p20.seq.maxY, 1102 - 20, accuracy: 1e-9); XCTAssertEqual(p20.box.height, (1102 - 111 - 20 - 16) / 3, accuracy: 1e-9)
        for p in [l20, p20] { XCTAssertEqual(p.lanes[0].minY, EuclideousPageMetrics.top(p.headerKind), "the top edge doesn't move") }
        // the 9pt-short page (no inset passed): the riff box is ~314.5 / 316.67 and its rows clear the floor (24.44 / 24.71)
        let short = euclideousPageLayout(size: CGSize(width: 1190, height: 717))
        XCTAssertEqual(short.box.height, 314.5, accuracy: 1e-9)
        XCTAssertEqual(euclideousRiffPanelLayout(box: short.box).rowH, 24.4375, accuracy: 1e-9)
        XCTAssertFalse(short.floors.contains(.riffRows))
        let shortP = euclideousPageLayout(size: CGSize(width: 814, height: 1093))
        XCTAssertEqual(shortP.box.height, 316.67, accuracy: 0.01); XCTAssertEqual(euclideousRiffPanelLayout(box: shortP.box).rowH, 24.71, accuracy: 0.01)
    }
}
