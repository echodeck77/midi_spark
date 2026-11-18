//  PageLayoutTests.swift
//  PAGE LAYOUT ferry (2026-10-19, "six equal boxes in both orientations"): the pure page function and the formulas it feeds. Every number a
//  view draws a box with comes from `euclideousPageLayout`; these tests pin it at Paul's two reference screenshots (1190 × 726 landscape,
//  814 × 1102 portrait) and sweep it across sizes. The views themselves have no macOS test-target reach — device verification owns them.
//
//  SOURCE-WINS NOTE (ferry: "where source disagrees about an existing value, source wins"): FX's strip and LANES' blocks sit at panel y 32 / 60 in
//  source (8 padding + 20 tab row + sp4), not the spec's 35 / 63. The FX / LANES expectations below are therefore the source-consistent ones:
//  FX rowH = (box − 126) / 6, LANES laneH = (box − 100) / 4 (the spec's 31.67 / 31.78 and 54 / 54.17 are each 0.5–0.75pt smaller).

import XCTest
#if canImport(AppKit)
import AppKit
#endif

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
        // TAB STRIP ferry (2026-10-29) §1.3: the lane area (columns 1–2) holds the 28-tall strip, sp8, then the four cards (380.67 × 301); the riff panel and the bottom-right panel keep the old equal box (380.67 × 319) and their frames.
        let p = land
        XCTAssertTrue(p.isLandscape); XCTAssertEqual(p.headerKind, .a, "1158 wide, landscape: the header is layout A")
        XCTAssertEqual(p.box.width, 380.67, accuracy: 0.01); XCTAssertEqual(p.box.height, 319, accuracy: 1e-9)
        XCTAssertEqual(p.laneBox.width, 380.67, accuracy: 0.01); XCTAssertEqual(p.laneBox.height, 301, accuracy: 1e-9)
        near(p.strip, 16, 64, 769.33, 28, "the strip spans the lane area (the ferry's 753.33 is 16 short — Paul chose the lane area's width)")
        near(p.lanes[0], 16, 100, 380.67, 301, "lane 1"); near(p.lanes[1], 404.67, 100, 380.67, 301, "lane 2")
        near(p.lanes[2], 16, 409, 380.67, 301, "lane 3"); near(p.lanes[3], 404.67, 409, 380.67, 301, "lane 4")
        near(p.riff, 793.33, 64, 380.67, 319, "riff panel"); near(p.seq, 793.33, 391, 380.67, 319, "MIX | LANES | FX panel")
        XCTAssertEqual(p.strip.maxX, p.lanes[1].maxX, accuracy: 1e-9, "the strip ends flush with lane 2's right edge")
        XCTAssertEqual(p.lanes[3].maxY, 710, accuracy: 1e-9, "everything still ends at y 710")
        XCTAssertEqual(p.gutterX, 400.67, accuracy: 0.01, "was 378.5")
        XCTAssertEqual(p.seq.maxX, 1174, accuracy: 1e-9, "nothing past x 1174"); XCTAssertEqual(p.seq.maxY, 710, accuracy: 1e-9, "nothing past y 710")
        XCTAssertEqual(p.riffLeadingX, 777.33, accuracy: 0.01); XCTAssertEqual(p.laneCentreX, 384.67, accuracy: 0.01)
        XCTAssertEqual(p.floors, [.laneStrip], "FILL (2026-11-13): the 8th strip tab drops segments below the 96 pt cluster floor, so .laneStrip flags at the reference (clusters hidden, labels fit); nothing else: \(p.floors)")
    }
    func testPortraitReferenceIsTwoColumnsByThreeRowsAndFitsTheView() {
        let p = port
        XCTAssertFalse(p.isLandscape); XCTAssertEqual(p.headerKind, .b, "782 wide, portrait: layout B")
        XCTAssertEqual(p.box.width, 387, accuracy: 1e-9); XCTAssertEqual(p.box.height, 319.67, accuracy: 0.01)
        XCTAssertEqual(p.laneBox.width, 387, accuracy: 1e-9); XCTAssertEqual(p.laneBox.height, 301.67, accuracy: 0.01)
        near(p.strip, 16, 111, 782, 28, "the strip spans both columns")
        near(p.lanes[0], 16, 147, 387, 301.67, "lane 1"); near(p.lanes[1], 411, 147, 387, 301.67, "lane 2")
        near(p.lanes[2], 16, 456.67, 387, 301.67, "lane 3"); near(p.lanes[3], 411, 456.67, 387, 301.67, "lane 4")
        near(p.riff, 16, 766.33, 387, 319.67, "riff panel"); near(p.seq, 411, 766.33, 387, 319.67, "MIX | LANES | FX panel")
        XCTAssertEqual(p.lanes[2].maxY + 8, p.riff.minY, accuracy: 1e-9, "row 3 is unchanged at 766.33")
        XCTAssertEqual(p.gutterX, 407, accuracy: 1e-9, "was 442.5")
        XCTAssertEqual(p.seq.maxX, 798, accuracy: 1e-9, "the second column ends 16pt inside the 814 view (it ran to 869 before)")
        XCTAssertEqual(p.seq.maxY, 1086, accuracy: 0.01)
        XCTAssertEqual(p.laneCentreX, 391, accuracy: 1e-9, "= the container's centre, as portrait's header always used")
        XCTAssertEqual(p.floors, [.laneStrip], "FILL: 8 tabs → clusters hidden at the reference (labels fit); nothing else: \(p.floors)")
    }
    func testChooserIsTheViewsOwnWiderThanTall() {
        XCTAssertTrue(euclideousPageLayout(size: CGSize(width: 1190, height: 726)).isLandscape)
        XCTAssertFalse(euclideousPageLayout(size: CGSize(width: 814, height: 1102)).isLandscape)
        XCTAssertFalse(euclideousPageLayout(size: CGSize(width: 800, height: 800)).isLandscape, "square is not strictly wider than tall")
        // the header kind comes from the header's own ladder on the page's container width
        // 2026-10-20: two offsetting changes — output rings to 75% dropped OUTPUTS by 44pt (839.86 layout A
        // need), then the HOLD/LATCH header buttons widened NOTES by 114pt (953.86) — net +70, still short of 868.
        XCTAssertEqual(euclideousPageLayout(size: CGSize(width: 800, height: 600)).headerKind, .a, "768 ≥ the 705.88 layout A needs (HOCKET RETIRED 2026-11-17 dropped UTILITIES by 100; it was 805.88)")
        XCTAssertEqual(euclideousPageLayout(size: CGSize(width: 900, height: 600)).headerKind, .a, "868 ≥ 705.88: the one-row header")
        XCTAssertEqual(euclideousPageLayout(size: CGSize(width: 1190, height: 600)).headerKind, .a)
        XCTAssertEqual(euclideousPageLayout(size: CGSize(width: 400, height: 900)).headerKind, .c, "the three-row D is retired (it existed for the PATTERN | MIX switch): a narrow container takes the compact two-row header")
        XCTAssertEqual(euclideousPageLayout(size: CGSize(width: 600, height: 900)).headerKind, .b, "568 ≥ B's 383.88 and < A's 705.88")
    }

    // MARK: 3. the sweep

    // GRACEFUL SCALE-TO-FIT (small-window, 2026-10-26): at/above the minimum it's a no-op (the real size, scale 1);
    // below, the page lays out at the reference size and scales down uniformly, centred.
    func testScaleToFitIsANoOpAtOrAboveTheReferenceAndScalesCentredBelow() {
        // AT or ABOVE the reference in both dimensions (landscape + portrait, incl. a larger-than-ref view): no scaling, the real size, never scales UP.
        for s in [CGSize(width: 1190, height: 726), CGSize(width: 814, height: 1102), CGSize(width: 1400, height: 900), CGSize(width: 1000, height: 1300)] {
            let f = euclideousScaleToFit(s)
            XCTAssertFalse(f.scaled, "\(s) is at/above the reference"); XCTAssertEqual(f.scale, 1); XCTAssertEqual(f.renderSize, s); XCTAssertEqual(f.origin, .zero)
        }
        // Paul (2026-11-03): BELOW the reference — including 760×480 / 480×760, which the old rectangular minimum wrongly let through to the
        // overlapping fluid layout — the whole page shrinks uniformly to the reference, centred.
        for s in [CGSize(width: 760, height: 480), CGSize(width: 480, height: 760), CGSize(width: 1100, height: 680)] {
            XCTAssertTrue(euclideousScaleToFit(s).scaled, "\(s) is below the reference and must scale")
        }
        // too small (landscape): lays out at the 1190×726 reference, scales to fit, centred.
        let small = CGSize(width: 595, height: 363)   // exactly half the landscape reference
        let f = euclideousScaleToFit(small)
        XCTAssertTrue(f.scaled); XCTAssertEqual(f.renderSize, EuclideousScaleToFit.landscapeRef)
        XCTAssertEqual(f.scale, 0.5, accuracy: 1e-9, "min(595/1190, 363/726) = 0.5")
        XCTAssertEqual(f.origin.x, 0, accuracy: 1e-9); XCTAssertEqual(f.origin.y, 0, accuracy: 1e-9, "exactly half ⇒ fills, no centring gap")
        // a width-constrained small size centres vertically.
        let wide = euclideousScaleToFit(CGSize(width: 595, height: 400))
        XCTAssertEqual(wide.scale, 0.5, accuracy: 1e-9, "width binds (595/1190 < 400/726)")
        XCTAssertEqual(wide.origin.y, (400 - 726 * 0.5) / 2, accuracy: 1e-9, "centred in the leftover height")
        // below the reference in ONE dimension only still scales (uniformly), binding on that dimension.
        let shortH = euclideousScaleToFit(CGSize(width: 1190, height: 700))
        XCTAssertTrue(shortH.scaled); XCTAssertEqual(shortH.scale, 700.0 / 726.0, accuracy: 1e-9, "height binds; width letterboxes")
        // a zero/degenerate size never divides by zero.
        XCTAssertFalse(euclideousScaleToFit(.zero).scaled)
    }
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
                // TAB STRIP: the strip sits at the top of the lane area, sp8 above the cards, as wide as the two card columns plus their gap
                XCTAssertEqual(p.strip.minY, top, accuracy: 1e-9, tag); XCTAssertEqual(p.strip.height, 28, tag)
                XCTAssertEqual(p.strip.minX, p.lanes[0].minX, accuracy: 1e-9, tag); XCTAssertEqual(p.strip.maxX, p.lanes[1].maxX, accuracy: 1e-9, "\(tag): the strip spans the lane area")
                XCTAssertEqual(p.lanes[0].minY - p.strip.maxY, 8, accuracy: 1e-9, "\(tag): sp8 between the strip and the cards")
                for f in all {
                    let isLane = p.lanes.contains(f)
                    XCTAssertEqual(f.width, p.box.width, accuracy: 1e-9, "\(tag): same width"); XCTAssertEqual(f.height, isLane ? p.laneBox.height : p.box.height, accuracy: 1e-9, "\(tag): same height")
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
        XCTAssertEqual(full.notes, 306, accuracy: 0.01, "Sources panel v2: the SOURCES button (192) + sp8 + HOLD/LATCH (106)")
        let aNeeds = euclideousHeaderANeeds(full)   // HOCKET RETIRED (2026-11-17): brand 191.88 + gap + notes 306 + gap + utilities 176 = 705.88 (was 805.88 with the HOCKET pill's 100 in UTILITIES)
        XCTAssertEqual(aNeeds, 705.88, accuracy: 0.01)
        let bNeeds = full.brand + full.utilities + full.gap
        XCTAssertEqual(euclideousHeaderKind(containerW: aNeeds, isLandscape: true), .a)
        XCTAssertEqual(euclideousHeaderKind(containerW: aNeeds - 0.01, isLandscape: true), .b)
        XCTAssertEqual(euclideousHeaderKind(containerW: 5000, isLandscape: false), .b, "portrait never uses A")
        XCTAssertEqual(euclideousHeaderKind(containerW: bNeeds - 0.01, isLandscape: false), .c)
        XCTAssertEqual(bNeeds, 383.88, accuracy: 0.01)   // HOCKET RETIRED (2026-11-17): brand 191.88 + utilities 176 + gap 16 (was 483.88)
        XCTAssertEqual(euclideousHeaderKind(containerW: bNeeds, isLandscape: false), .b)
        for cw in stride(from: 200, through: 2400, by: 3) { for landscape in [true, false] { XCTAssertNotEqual(euclideousHeaderKind(containerW: CGFloat(cw), isLandscape: landscape), .d, "\(cw): the three-row layout is retired") } }
        for cw in stride(from: 300, through: 1500, by: 7) { for landscape in [true, false] {
            let l = euclideousHeaderLayout(containerW: CGFloat(cw), isLandscape: landscape, riffLeadingX: 0)
            XCTAssertEqual(l.kind, euclideousHeaderKind(containerW: CGFloat(cw), isLandscape: landscape), "\(cw) \(landscape)")
        } }
    }
    func testHeaderGroupsNeverOverlapOrLeaveTheContainer() {
        for cw in stride(from: 440, through: 1500, by: 7) { for landscape in [true, false] { for riffX in [CGFloat(0), 300, 777.33, 2000] {
            let l = euclideousHeaderLayout(containerW: CGFloat(cw), isLandscape: landscape, riffLeadingX: riffX)
            let tag = "\(cw) \(landscape) \(riffX)"
            XCTAssertEqual(l.brand.x, 0, tag); XCTAssertEqual(l.brand.row, 0, tag)
            XCTAssertEqual(l.utilities.x + l.utilities.width, CGFloat(cw), accuracy: 1e-9, "\(tag): the gear ends at the right edge"); XCTAssertEqual(l.utilities.row, 0, tag)
            if l.kind == .a {
                XCTAssertEqual(l.notes.row, 0, tag)
                XCTAssertGreaterThanOrEqual(l.notes.x, l.brand.width + l.widths.gap - 1e-9, "\(tag): NOTES clears BRAND")
                XCTAssertLessThanOrEqual(l.notes.x + l.notes.width + l.widths.gap, l.utilities.x + 1e-9, "\(tag): …and UTILITIES")
                XCTAssertEqual(l.notes.x, euclideousHeaderLayout(containerW: CGFloat(cw), isLandscape: landscape, riffLeadingX: 0).notes.x, accuracy: 1e-9, "\(tag): the riff panel's edge no longer moves it")
            } else {
                XCTAssertEqual(l.notes.row, 1, tag); XCTAssertEqual(l.notes.x, 0, "\(tag): NOTES alone leads row 2")
                XCTAssertLessThanOrEqual(l.notes.x + l.notes.width, CGFloat(cw) + 1e-9, "\(tag): B and C keep row 2 inside the container")
                XCTAssertLessThanOrEqual(l.brand.width + l.widths.gap, l.utilities.x + (l.kind == .c ? 1e9 : 1e-9), tag)
            }
        } } }
    }

    // MARK: 4–7. what each box does with its frame

    func testLaneCardZonesAtBothReferences() {
        // TAB STRIP ferry (2026-10-29) §3.2 / test 3: the card's tab row is gone and RHYTHM's upper zone is the card height − 156 (it was − 188); PLAY BUTTONS AMENDMENT 1 (2026-11-08) §A1.3: the gap under the top row is g = 4 (was 8),
        // so the body starts at y 58 and the upper zone is the card height − 152 (145 / 145.67 → 149 / 149.67).
        XCTAssertEqual(EuclideousLaneCardMetrics.bodyTop, 58); XCTAssertEqual(EuclideousLaneCardMetrics.chromeH, 68)
        // RHYTHM's upper zone (unchanged) + RIFF v3 §1.1 Row A = contentH − 154 (3·6 gaps + 49 + 49 + 38); content area is the REAL 233 / 233.67
        for (p, upper, rowA) in [(land, 149.0, 79.0), (port, 149.67, 79.67)] {
            let contentH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: p.laneBox.height)
            XCTAssertEqual(contentH - 80 - 4, upper, accuracy: 0.01, "RHYTHM upper zone = card height − 152")
            let r = euclideousRiffTabLayout(contentAreaH: contentH, fullWidth: EuclideousLaneCardMetrics.innerWidth(cardWidth: p.laneBox.width))
            XCTAssertEqual(r.rowAHeight, rowA, accuracy: 0.01, "RIFF v3 Row A = H − 154")
            XCTAssertEqual(r.bandHeight, 49); XCTAssertEqual(r.outputRowHeight, 38); XCTAssertEqual(r.rowGap, 6)
            XCTAssertEqual(r.gridCell, 5.6); XCTAssertEqual(r.gridSize, 54.6, accuracy: 0.01); XCTAssertEqual(r.gridTop, 4); XCTAssertEqual(r.labelTop, 60.6, accuracy: 0.01)
            XCTAssertFalse(r.underFloor)
        }
        // RIFF v3 §8.1 frames (landscape body 360.67 / portrait 367; from the REAL content area)
        let rl = euclideousRiffTabLayout(contentAreaH: EuclideousLaneCardMetrics.contentAreaH(cardHeight: land.laneBox.height), fullWidth: EuclideousLaneCardMetrics.innerWidth(cardWidth: land.laneBox.width))
        XCTAssertEqual(rl.tileWidth, 67); XCTAssertEqual(rl.walkX, 79)
        XCTAssertEqual(rl.walkWidth, 277.67, accuracy: 0.01)
        XCTAssertEqual(rl.directionButtonWidth, 34)
        XCTAssertEqual(rl.advanceEveryX, 120); XCTAssertEqual(rl.advanceEveryWidth, 168); XCTAssertEqual(rl.strideX, 296)
        XCTAssertEqual(rl.strideWidth, 60.67, accuracy: 0.01)
        XCTAssertEqual(rl.notesCellWidth, 85.17, accuracy: 0.01)
        // §8.3 walk column widths (landscape): n=16→14.26, n=8→31.02, n=5→34 (capped), n=1→34
        XCTAssertEqual(euclideousRiffWalkGrid(n: 16, innerWidth: rl.walkWidth).columnWidth, 14.26, accuracy: 0.01)
        XCTAssertEqual(euclideousRiffWalkGrid(n: 8, innerWidth: rl.walkWidth).columnWidth, 31.02, accuracy: 0.01)
        XCTAssertEqual(euclideousRiffWalkGrid(n: 5, innerWidth: rl.walkWidth).columnWidth, 34, accuracy: 0.01, "n=5 capped at 34, remainder empty")
        XCTAssertEqual(euclideousRiffWalkGrid(n: 1, innerWidth: rl.walkWidth).columnWidth, 34, accuracy: 0.01, "n=1 capped at 34")
        let rp = euclideousRiffTabLayout(contentAreaH: EuclideousLaneCardMetrics.contentAreaH(cardHeight: port.laneBox.height), fullWidth: EuclideousLaneCardMetrics.innerWidth(cardWidth: port.laneBox.width))
        XCTAssertEqual(rp.walkWidth, 284, accuracy: 0.01)
        XCTAssertEqual(rp.strideWidth, 67, accuracy: 0.01)
        XCTAssertEqual(rp.notesCellWidth, 86.75, accuracy: 0.01); XCTAssertEqual(rp.directionButtonWidth, 34)
    }
    /// RIFF v3 §8.2: in every layout Row A (tile + WALK) and the MOVE band (directions + ADVANCE EVERY + STRIDE) and the NOTES cells
    /// all span x4 … W−4, the tile grid and the walk grid share the same vertical geometry, and the four rows + three 6 pt gaps fill H.
    func testRiffV3BandAlignmentInEveryLayout() {
        for (ca, w) in [(233.0, 360.67), (233.67, 367.0), (170.0, 335.0), (120.0, 300.0)] {
            let r = euclideousRiffTabLayout(contentAreaH: ca, fullWidth: w)
            let inset = r.contentInset   // 4
            // Row A: the tile (x4, T) + 8 + WALK ends at W−4
            XCTAssertEqual(r.walkX, inset + r.tileWidth + 8, accuracy: 1e-9, "WALK at 4 + T + 8, at \(w)")
            XCTAssertEqual(r.walkX + r.walkWidth, w - inset, accuracy: 0.01, "Row A ends at W−4")
            // MOVE band: directions (x4, 3×34, 3 apart) → 8 → ADVANCE EVERY (168) → 8 → STRIDE → W−4
            XCTAssertEqual(r.advanceEveryX, inset + 3 * r.directionButtonWidth + 2 * 3 + 8, accuracy: 0.01, "ADVANCE EVERY after the directions + 8")
            XCTAssertEqual(r.strideX, r.advanceEveryX + r.advanceEveryWidth + 8, accuracy: 0.01, "STRIDE after the tile + 8")
            // STRIDE fills to W−4 only where it fits; below that (narrow w) the fixed 168 tile fills the band and STRIDE is clamped + reported (§1.8)
            if (w - inset) - r.strideX >= 1 { XCTAssertEqual(r.strideX + r.strideWidth, w - inset, accuracy: 0.01, "STRIDE ends at W−4") }
            XCTAssertEqual(inset + 4 * r.notesCellWidth + 3 * 4, w - inset, accuracy: 0.01, "NOTES cells end at W−4")
            XCTAssertEqual(r.moveBandTop, r.rowAHeight + 6, accuracy: 1e-9)
            XCTAssertEqual(r.notesBandTop, r.rowAHeight + 6 + 49 + 6, accuracy: 1e-9)
            // §1.4 the tile grid and the walk grid share the vertical geometry: grid top 4, a 10 pt label line 2 below the 54.6 grid
            XCTAssertEqual(r.gridTop, 4); XCTAssertEqual(r.labelTop, r.gridTop + r.gridSize + 2, accuracy: 1e-9); XCTAssertEqual(r.labelHeight, 10)
            if r.rowAHeight > 1 { XCTAssertEqual(r.outputRowTop + r.outputRowHeight, ca, accuracy: 0.01, "rows + gaps fill H") }
        }
    }
    /// RIFF v3 §8.13 / §1.9: no key or label on the tab truncates at either reference — every key now sits on its OWN full-width line
    /// (key-over-value), so the longest keys fit without shrinking. Measures the rendered width (heavy monospaced) against the key line.
    func testRiffV3KeysDoNotTruncate() {
        #if canImport(AppKit)
        func w(_ s: String, _ size: CGFloat) -> CGFloat {
            (s as NSString).size(withAttributes: [.font: NSFont.monospacedSystemFont(ofSize: size, weight: .heavy)]).width
        }
        for (ca, fw) in [(233.0, 360.67), (233.67, 367.0)] {
            let r = euclideousRiffTabLayout(contentAreaH: ca, fullWidth: fw)
            // ADVANCE EVERY's key line = the 168 tile less its 4 pt padding each side; STRIDE / LEN / SHIFT / TRANS key lines = their cell less the 2 pt key padding each side.
            XCTAssertLessThanOrEqual(w("ADVANCE EVERY", 10), r.advanceEveryWidth - 8, "ADVANCE EVERY fits the merged tile's key line")
            XCTAssertLessThanOrEqual(w("STRIDE", 10), r.strideWidth - 4, "STRIDE fits")
            for key in ["LEN", "SHIFT", "TRANS"] { XCTAssertLessThanOrEqual(w(key, 10), r.notesCellWidth - 4, "\(key) fits a NOTES cell") }
            // the walk column numbers (MONO columns are a single digit 1…8) and the tile's RIFF (9 pt, 0.16 em) fit their frames
            XCTAssertLessThanOrEqual(w("8", 9), euclideousRiffWalkGrid(n: 16, innerWidth: r.walkWidth).columnWidth, "a column number fits even the n=16 column")
            XCTAssertLessThanOrEqual(w("RIFF", 9) + 4 * 0.16 * 3, r.tileWidth - 4, "RIFF fits the tile")
        }
        #endif
    }
    /// Floors ferry (2026-10-23): TILT's EARLY/LATE end-labels — pure annotation, not the control — drop
    /// out below their own floor, independent of (and tighter than) the inert `rhythmZonesFloor`(192).
    func testRhythmEndLabelsDropBelowTheirOwnFloor() {
        let floor = EuclideousRhythmGeometry.endLabelsFloor   // 37 since the iPad-mini fix (was 28 — below ≈ 36.7 pt the captions' backing erased the label row's lower half)
        XCTAssertTrue(EuclideousRhythmGeometry.showsEndLabels(rowH: floor))
        XCTAssertTrue(EuclideousRhythmGeometry.showsEndLabels(rowH: 38.67), "the reference row height")
        XCTAssertFalse(EuclideousRhythmGeometry.showsEndLabels(rowH: floor - 0.01))
    }
    func testMixFairShareDropsTheStepperAtThePadFloor() {
        // PER-LAYER ROUTING ferry §5.2: the OUT row left MIX, so nominalBelowPad is now sp4 + stepper = 28 (was 52) and
        // only the OCT stepper can drop to its compact floor. The fallback triggers when innerH − 28 < minPadH(64), i.e.
        // innerH < 92.
        func gridFor(innerH: CGFloat) -> EuclideousMixGrid {
            // innerH = (height − sp16)/2 − panelPad*2  ⇒  height = (innerH + panelPad*2) * 2 + sp16
            let height = (innerH + EuclideousMixMetrics.panelPad * 2) * 2 + EuclideousMixMetrics.sp16
            return euclideousMixGrid(width: 400, height: height)
        }
        let atFloor = gridFor(innerH: 92)
        XCTAssertEqual(atFloor.stepperH, 24, accuracy: 1e-9); XCTAssertEqual(atFloor.outRowH, 0, "the OUT row is gone from MIX")
        XCTAssertEqual(atFloor.padH, 64, accuracy: 1e-9, "innerH 92 − nominal 28 = 64, exactly minPadH — nominal, not compact")
        let justUnder = gridFor(innerH: 91.99)
        XCTAssertEqual(justUnder.stepperH, 18, accuracy: 1e-9, "only the stepper drops now")
        XCTAssertEqual(justUnder.padH, 91.99 - 22, accuracy: 1e-9, "compact belowPad is 22 (4 + 18), buying 6 pt back")
    }
    func testRiffGridAtBothReferences() {
        // RIFF PANEL ferry (2026-10-19) §1: the tabs are 20 tall, the grid starts at y 34, four 8pt rails (41) sit under it — rows (box − 119) / 8 = 25 / 25.08.
        // (The layout ferry's own chrome was 77 and its pure height/rows pair is GONE: the panel's inside is laid out by `euclideousRiffPanelLayout`, once.)
        XCTAssertEqual(EuclideousRiffPanelMetrics.chromeH(), 119)
        let l = euclideousRiffPanelLayout(box: land.box), p = euclideousRiffPanelLayout(box: port.box)
        // POOL ferry (2026-11-02): the label column became a column of rank chips, 48 wide instead of 30 — the cell width gives up 18 / 8 = 2.25 pt (landscape 37.83 → 35.58, portrait 38.63 → 36.38); the formula is unchanged.
        XCTAssertEqual(l.cellW, 35.58, accuracy: 0.01); XCTAssertEqual(l.rowH, 25, accuracy: 1e-9)
        XCTAssertEqual(p.cellW, 36.38, accuracy: 0.01); XCTAssertEqual(p.rowH, 25.08, accuracy: 0.01)
        XCTAssertEqual(l.labelW, 48); XCTAssertEqual(p.labelW, 48); XCTAssertEqual(EuclideousRiffPanelMetrics.labelW, euclideousRankChipMinWidth(), "the column is exactly the narrowest chip that holds the widest label beside its corner number")
    }
    func testFXRowsFollowThePanelAndItsColumnsAreTheRiffGrids() {
        // rows share the height: (content − fixed) / 6 with content = box − 40. MIX ROWS AMENDMENT 1 (§A7, 2026-11-04): the hint row is hidden, so fixed is 66 not 86 (the 86 / hint-row numbers: 29 at a 260-tall content, 32.17 / 32.28 at the references) — 20 pt back, 3.33 pt a row.
        XCTAssertEqual(EuclideousFXLayout.fixedHeight, 86, "the nominal hint-included figure is kept (hide, don't delete)"); XCTAssertEqual(EuclideousFXLayout.fixedHeightNoHint, 66)
        XCTAssertFalse(EuclideousLowerRightCaptions.shown)
        XCTAssertEqual(euclideousFXRowH(contentHeight: 260), (260 - 66) / 6, accuracy: 1e-9)
        for (p, rowH) in [(land, 35.5), (port, 35.61)] {
            let body = euclideousSeqTabBodySize(panelWidth: p.box.width, panelHeight: p.box.height)
            XCTAssertEqual(body.height, p.box.height - 40, accuracy: 1e-9)
            let l = euclideousFXLayout(width: body.width, height: body.height)
            XCTAssertEqual(l.rowH, rowH, accuracy: 0.01)
            XCTAssertFalse(l.showHintRow, "no hint row on any tab")
            XCTAssertEqual(l.rowTop(5) + l.rowH, body.height, accuracy: 1e-9, "the sixth row ends sp8 above the panel's bottom, whatever the height — the freed 20 pt are the rows'")
            XCTAssertEqual(l.cellW, euclideousRiffCellW(maxWidth: p.box.width), "the columns are the riff grid's own function")
            // each FX column's offset from ITS panel's leading edge = the riff grid's column's offset from the riff panel's (8 pad + the label column + 4 gap, then cellW + 4)
            for c in 0..<8 {
                let fxOffset = 8 + l.colLeft(c)
                let riffOffset = 8 + euclideousRiffNoteLabelW(maxWidth: p.box.width) + 4 + CGFloat(c) * (euclideousRiffCellW(maxWidth: p.box.width) + 4)
                XCTAssertEqual(fxOffset, riffOffset, accuracy: 1e-9, "column \(c)")
                // …and on the page: landscape the panel sits directly under the riff panel (same x), so the edges are equal on the page too
                if p.isLandscape { XCTAssertEqual(p.seq.minX + fxOffset, p.riff.minX + riffOffset, accuracy: 1e-9) }
            }
        }
        XCTAssertEqual(euclideousFXLayout(width: 360, height: 245).rowH, (245 - 66) / 6, accuracy: 1e-9, "a shorter panel still shares the missing height")
        XCTAssertEqual(euclideousFXLayout(width: 360, height: 100).rowH, 24, "…down to 24, then no further")
        XCTAssertEqual(euclideousFXLayout(width: 360, height: 400).rowH, (400 - 66) / 6, accuracy: 1e-9, "no upper cap now")
        XCTAssertEqual(euclideousFXRowH(contentHeight: 303 - 40), (303 - 40 - 66) / 6, accuracy: 1e-9, "the old 303 frame (29.5 with the hint row)")
    }
    func testLanesBlocksAndCellsAtBothReferences() {
        // MUTE ZOOM (2026-11-03): each side loses a 22pt arrow + 4pt gap, so cellW drops 10/16 = 0.625 from the old 18.29 / 18.69.
        // MIX ROWS AMENDMENT 1 (§A7): MUTE's hint line and ZOOM legend are hidden, so the 24 + 4 band and the 4 + 16 row go to the blocks — laneH 54.75 → 66.75 and 54.92 → 66.92 (+12).
        XCTAssertEqual([EuclideousLanesLayout.subTabH, EuclideousLanesLayout.subTabGap, EuclideousLanesLayout.legendGap, EuclideousLanesLayout.legendH], [0, 0, 0, 0])
        for (p, cellW, laneH) in [(land, 17.665, 66.75), (port, 18.065, 66.92)] {
            let body = euclideousSeqTabBodySize(panelWidth: p.box.width, panelHeight: p.box.height)
            let l = euclideousLanesLayout(width: body.width, height: body.height)
            XCTAssertEqual(l.cellW, cellW, accuracy: 0.01); XCTAssertEqual(l.laneH, laneH, accuracy: 0.01)
            XCTAssertEqual(l.legendTop + EuclideousLanesLayout.legendH, body.height, accuracy: 1e-9, "the fourth block ends sp8 above the panel's bottom")
            XCTAssertEqual(l.laneTop(0), 0, "the blocks start at the top of the body")
            XCTAssertEqual(l.gridX + 16 * l.cellW + 15 * EuclideousLanesLayout.cellGap + EuclideousLanesLayout.arrowGap + EuclideousLanesLayout.arrowW,
                           body.width, accuracy: 1e-9, "the grid + the right zoom arrow tile the width (16 cells + 2pt gaps between the two arrows)")
        }
        XCTAssertEqual(euclideousLanesLayout(width: 394, height: 303 - 40).laneH, (303 - 40 - 12) / 4, accuracy: 1e-9, "the old 303 frame (50.75 with the captions)")
    }

    // MARK: 8. the header's inputs

    private func headerFor(_ p: EuclideousPageLayout, _ size: CGSize) -> EuclideousHeaderLayout {
        euclideousHeaderLayout(containerW: size.width - 32, isLandscape: p.isLandscape, riffLeadingX: p.riffLeadingX)
    }
    func testNotesIsCentredAt1190() {
        // layout A centres NOTES (306) between BRAND (0…191.88) and UTILITIES. HOCKET RETIRED (2026-11-17): UTILITIES lost 100 and moved right, so the centred NOTES x shifts +50: 383.94 → 433.94.
        let l = headerFor(land, landscapeRef)
        XCTAssertEqual(l.notes.x, 433.94, accuracy: 0.01)
        XCTAssertEqual(l.notes.x - l.brand.width, l.utilities.x - (l.notes.x + l.notes.width), accuracy: 1e-9)
        XCTAssertLessThan(l.notes.x, land.riffLeadingX)
    }

    // MARK: 9. floors

    func testFloorsAreFlaggedNotFixedAtTheOtherSizes() {
        // a guess at the 8.3-inch iPad mini's landscape plugin view: box 355 × 274 (TAB STRIP 2026-10-29: the header lost the switch, the dice and the padlock — layout A holds from a 837.88 view, so 1113 wide has the one-row header and the 274 box needs 636 high, as it did before CARD BACKS)
        // THE NINE PORTS (2026-10-26): with the header rings gone layout A's floor is 962 wide (container 930 + the two margins), so this 1113-wide view has the one-row header again (boxes start at 64)
        // and the view's original 636 height gives this guess's 355 × 274 box, which is what the floors below are about. (The REEL icon had pushed it to the two-row header and 683.)
        // CARD BACKS (2026-10-28): the PATTERN | MIX switch (+124) lifts A's floor to a 1185.88 view, so this 1113-wide view takes the two-row header again (boxes start at 111) and needs 683 high for the same 355 × 274 box.
        let mini = euclideousPageLayout(size: CGSize(width: 1113, height: 636))
        XCTAssertEqual(mini.headerKind, .a)
        XCTAssertEqual(mini.box.width, 355, accuracy: 1e-9); XCTAssertEqual(mini.box.height, 274, accuracy: 1e-9)
        let area = euclideousMixGridArea(panelWidth: 355, panelHeight: 274)
        let g = euclideousMixGrid(width: area.width, height: area.height)
        // PER-LAYER ROUTING ferry §5.2: with the OUT row gone the pad has room here — nominal padH 71 (innerH 99 − 28)
        // is above minPadH 64, so no compact fallback; the stepper stays 24 and cellW is untouched.
        XCTAssertEqual(g.padH, 71, accuracy: 1e-9); XCTAssertEqual(g.cellW, 74.75, accuracy: 1e-9)
        XCTAssertEqual(g.stepperH, 24, accuracy: 1e-9); XCTAssertEqual(g.outRowH, 0, accuracy: 1e-9)
        // Floors ferry: nominal rowH would be 19.375 (chrome 119) but that's under minRowH (24), so the tab
        // row drops to its compact floor (14) and chrome shrinks to 113, buying rowH back to 20.125.
        let miniRiffLayout = euclideousRiffPanelLayout(box: CGSize(width: 355, height: 274))
        XCTAssertEqual(miniRiffLayout.rowH, 20.125, accuracy: 1e-9)
        XCTAssertEqual(miniRiffLayout.tabRowH, 14, accuracy: 1e-9); XCTAssertEqual(miniRiffLayout.labelW, 48, accuracy: 1e-9, "cellW here (32.4) clears minCellW, so the label stays nominal")
        // RIFF v2: at this small lane card Row A is well under the 60pt floor, so .riffRowA flags. The standalone
        // layout reads the SAME lane box euclideousPageFloors uses, so its flags and mini.floors agree exactly.
        let r = euclideousRiffTabLayout(contentAreaH: EuclideousLaneCardMetrics.contentAreaH(cardHeight: mini.laneBox.height), fullWidth: EuclideousLaneCardMetrics.innerWidth(cardWidth: mini.laneBox.width))
        XCTAssertLessThan(r.rowAHeight, EuclideousRiffTabFloors.rowAHeight); XCTAssertTrue(r.rowAUnderFloor)
        let f = Set(mini.floors)
        XCTAssertTrue(f.isSuperset(of: [.mixCellW, .rhythmZones, .riffRowA]), "\(f)")
        XCTAssertEqual(f.contains(.riffDirectionButtons), r.directionButtonUnderFloor)
        XCTAssertEqual(f.contains(.riffBandControl), r.advanceEveryUnderFloor || r.strideUnderFloor || r.walkColumnUnderFloor, "the MOVE-band floor flags iff ADVANCE EVERY, STRIDE or the walk column is under its floor")
        XCTAssertEqual(f.contains(.riffNotesCell), r.notesCellUnderFloor)
        // PER-LAYER ROUTING ferry §5.2: dropping the OUT row lifts this mini pad to 71pt — now clear of BOTH the 64 floor and the 48 stop.
        XCTAssertFalse(f.contains(.mixPadH), "padH 71 ≥ minPadH 64 now the OUT row is gone"); XCTAssertFalse(f.contains(.mixPadHStop))
        XCTAssertTrue(f.contains(.riffRows), "20.1 (even after the tab-row fair-share gives it back 0.75) is still under 24"); XCTAssertFalse(f.contains(.fxRows), "FX rows 24.67 clear 24")
        // windowed AUM panels
        let wl = euclideousPageLayout(size: CGSize(width: 900, height: 553))   // (900 × 600 under the old ladder; layout A holds from a 837.88 view now, so 553 high gives the same 284 × 232.5 box under the one-row header)
        XCTAssertEqual(wl.headerKind, .a, "868 ≥ A's 705.88: boxes start at 64")
        XCTAssertEqual(wl.box.width, 284, accuracy: 1e-9); XCTAssertEqual(wl.box.height, 232.5, accuracy: 1e-9)
        // §5.2: at this windowed size the pad is 56.25 — under the 64 floor (`.mixPadH`) but no longer under the 48 stop (`.mixPadHStop`), the OUT row's room reclaimed.
        XCTAssertTrue(Set(wl.floors).isSuperset(of: [.mixCellW, .mixPadH, .rhythmZones, .riffRows, .fxRows]), "\(wl.floors)")
        XCTAssertFalse(Set(wl.floors).contains(.mixPadHStop))
        let wp = euclideousPageLayout(size: CGSize(width: 700, height: 900))   // 600 → 650 (LANE LOCK ferry §2.2): B's floor rose ≈564 → ≈616 · 650 → 700 (FOURFOLD REEL LINK 2026-10-23): → ≈660, so a 650-wide portrait view is layout C now
        XCTAssertEqual(wp.headerKind, .b); XCTAssertEqual(wp.box.width, 330, accuracy: 1e-9); XCTAssertEqual(wp.box.height, (900 - 111 - 32) / 3, accuracy: 1e-9)
        XCTAssertFalse(wp.floors.isEmpty)
        // each flag is exactly its threshold
        // (the card's chrome is 68 now — PLAY BUTTONS AMENDMENT 1, g = 4 under the top row: a card 259 tall has contentAreaH 191, 260 has 192 — it was 263 / 264 at chrome 72, 295 / 296 with the tab row)
        XCTAssertTrue(euclideousPageFloors(box: CGSize(width: 380, height: 319), laneBox: CGSize(width: 380, height: 259)).contains(.rhythmZones), "contentAreaH 191 < 192")
        XCTAssertFalse(euclideousPageFloors(box: CGSize(width: 380, height: 319), laneBox: CGSize(width: 380, height: 260)).contains(.rhythmZones), "contentAreaH 192")
        XCTAssertTrue(euclideousPageFloors(box: CGSize(width: 380, height: 259)).contains(.rhythmZones), "one size given: the lane card is that size")
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
        for p in [l20, p20] { XCTAssertEqual(p.strip.minY, EuclideousPageMetrics.top(p.headerKind), "the top edge doesn't move"); XCTAssertEqual(p.lanes[0].minY, p.strip.maxY + 8, "the cards sit sp8 below the strip") }
        // the 9pt-short page (no inset passed): the riff box is ~314.5 / 316.67 and its rows clear the floor (24.44 / 24.71)
        let short = euclideousPageLayout(size: CGSize(width: 1190, height: 717))
        XCTAssertEqual(short.box.height, 314.5, accuracy: 1e-9)
        XCTAssertEqual(euclideousRiffPanelLayout(box: short.box).rowH, 24.4375, accuracy: 1e-9)
        XCTAssertFalse(short.floors.contains(.riffRows))
        let shortP = euclideousPageLayout(size: CGSize(width: 814, height: 1093))
        XCTAssertEqual(shortP.box.height, 316.67, accuracy: 0.01); XCTAssertEqual(euclideousRiffPanelLayout(box: shortP.box).rowH, 24.71, accuracy: 0.01)
    }
}
