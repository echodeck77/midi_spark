//  RhythmDynamicsGeometryTests.swift
//  RHYTHM DYNAMICS ferry (2026-10-21) §9 test 11 — the pure geometry of the RHYTHM tab's right half and the DYNAMICS editor, the cells and bars, the words — and §12.4's report of
//  every layout's card size, row height and which floors it falls under.

import XCTest

final class RhythmDynamicsGeometryTests: XCTestCase {
    private func near(_ r: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(r.minX, x, accuracy: 0.01, "\(what) x", file: file, line: line); XCTAssertEqual(r.minY, y, accuracy: 0.01, "\(what) y", file: file, line: line)
        XCTAssertEqual(r.width, w, accuracy: 0.01, "\(what) w", file: file, line: line); XCTAssertEqual(r.height, h, accuracy: 0.01, "\(what) h", file: file, line: line)
    }

    // MARK: the right half
    func testAtTheReferenceCardTheThreeRowsAre3867TallAtY94And13667And17933() {
        // the ferry's reference card: 358.5 × 312 → content area 208 → upper zone 124 (y 94–218)
        let contentH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: 312)
        XCTAssertEqual(contentH, 208); XCTAssertEqual(euclideousRhythmUpperH(contentAreaH: contentH), 124)
        XCTAssertEqual(euclideousRhythmRightRowH(upperH: 124), 38.67, accuracy: 0.005)
        let innerW = EuclideousLaneCardMetrics.innerWidth(cardWidth: 358.5)
        XCTAssertEqual(innerW, 338.5)
        let halfW = (innerW - 4) / 2
        XCTAssertEqual(halfW, 167.25); XCTAssertEqual(10 + halfW + 4, 181.25, "the right half starts at x 181.25")
        let rows = (0..<3).map { euclideousRhythmRightRow($0, upperH: 124, x: 10 + halfW + 4, width: halfW) }
        near(rows[0], 181.25, 0, 167.25, 38.67, "OFFSET"); near(rows[1], 181.25, 42.67, 167.25, 38.67, "TILT"); near(rows[2], 181.25, 85.33, 167.25, 38.67, "DYNAMICS")
        XCTAssertEqual(94 + rows[1].minY, 136.67, accuracy: 0.01); XCTAssertEqual(94 + rows[2].minY, 179.33, accuracy: 0.01)
        XCTAssertEqual(rows[2].maxY, 124, accuracy: 1e-9, "the three rows and two sp4 gaps fill the upper zone exactly")
    }
    func testAtTheLayoutFerrysLandscapeTheRowsAre41() {
        XCTAssertEqual(euclideousRhythmUpperH(contentAreaH: EuclideousLaneCardMetrics.contentAreaH(cardHeight: 319)), 131)
        XCTAssertEqual(euclideousRhythmRightRowH(upperH: 131), 41, accuracy: 1e-9)
        XCTAssertEqual(euclideousRhythmRightRowH(contentAreaH: 215), 41, accuracy: 1e-9)
    }
    func testRowsUnder36AreFlaggedNotShrunk() {
        // rows = (cardH − 196) / 3: 36 at 304
        XCTAssertTrue(euclideousPageFloors(box: CGSize(width: 380, height: 303)).contains(.rhythmRows))
        XCTAssertFalse(euclideousPageFloors(box: CGSize(width: 380, height: 304)).contains(.rhythmRows))
        XCTAssertEqual(euclideousRhythmRightRowH(contentAreaH: EuclideousLaneCardMetrics.contentAreaH(cardHeight: 303)), 35.67, accuracy: 0.01, "built at the formula's value")
    }

    // MARK: the editor
    func testTheEditorAtTheReferenceSitsWhereTheFerrySays() {
        let L = euclideousDynamicsEditorLayout(width: 338.5, height: 208)
        XCTAssertTrue(L.showsResult); XCTAssertFalse(L.clipsBottom)
        near(L.header, 8, 8, 322.5, 20, "header"); near(L.closeButton, 302.5, 8, 28, 20, "close")
        near(L.resultLabel!, 8, 36, 56, 40, "RESULT label")
        XCTAssertEqual(L.resultPreview!.minX, 68); XCTAssertEqual(L.resultPreview!.width, 262.5, accuracy: 1e-9); XCTAssertEqual(L.resultPreview!.minY, 37); XCTAssertEqual(L.resultPreview!.height, 38)
        near(L.accents, 8, 84, 159.25, 38, "ACCENTS"); near(L.shape, 171.25, 84, 159.25, 38, "SHAPE")
        near(L.depth, 8, 126, 159.25, 38, "DEPTH"); near(L.spread, 171.25, 126, 159.25, 38, "SPREAD")
        near(L.applyLabel, 8, 168, 56, 32, "APPLY label")
        XCTAssertEqual(L.applyButtons.count, 3)
        for (i, b) in L.applyButtons.enumerated() { near(b, 68 + CGFloat(i) * (84.83 + 4), 168, 84.83, 32, "APPLY button \(i)") }
        XCTAssertEqual(L.neededH, 208, accuracy: 1e-9, "everything fits a 208 pt editor exactly")
    }
    func testTheResultColumnsShareTheWidthTwoApart() {
        let L = euclideousDynamicsEditorLayout(width: 338.5, height: 208)
        let c16 = L.previewColumns(cells: 16)
        XCTAssertEqual(c16.count, 16); XCTAssertEqual(c16[0].vel.width, 14.53, accuracy: 0.005, "14.53 wide at 16 cells")
        XCTAssertEqual(c16[1].vel.minX - c16[0].vel.maxX, 2, accuracy: 1e-9)
        XCTAssertEqual(c16[15].vel.maxX, 262.5, accuracy: 1e-9)
        XCTAssertEqual(c16[0].vel.height, 32); XCTAssertEqual(c16[0].gate.height, 4); XCTAssertEqual(c16[0].gate.minY, 34, "a 2 pt gap under the 32 pt velocity cell")
        let c8 = L.previewColumns(cells: 8)
        XCTAssertEqual(c8[0].vel.width, 31.06, accuracy: 0.005, "(262.5 − 7 × 2) ÷ 8 — the ferry's 32.06 is an arithmetic slip, reported")
    }
    func testUnder208TheResultRowDropsAndTheRestMovesUp() {
        let L = euclideousDynamicsEditorLayout(width: 338.5, height: 207)
        XCTAssertFalse(L.showsResult); XCTAssertNil(L.resultLabel); XCTAssertNil(L.resultPreview)
        near(L.accents, 8, 36, 159.25, 38, "ACCENTS moves up under the header"); near(L.depth, 8, 78, 159.25, 38, "DEPTH")
        near(L.applyLabel, 8, 120, 56, 32, "APPLY")
        XCTAssertEqual(L.neededH, 160, accuracy: 1e-9, "the rest needs 160 (the ferry says 164; its own coordinates give 208 − 48)")
        XCTAssertFalse(L.clipsBottom)
        XCTAssertTrue(euclideousDynamicsEditorLayout(width: 338.5, height: 159).clipsBottom, "only below that does the bottom edge clip")
        XCTAssertTrue(euclideousPageFloors(box: CGSize(width: 380, height: 311)).contains(.dynamicsEditor), "contentAreaH 207")
        XCTAssertFalse(euclideousPageFloors(box: CGSize(width: 380, height: 312)).contains(.dynamicsEditor), "contentAreaH 208")
    }

    // MARK: §12.4 — every layout's card size, right-half row height and editor
    func testEveryLayoutsCardRowsAndEditor() {
        var report: [String] = []
        for (name, size) in [("landscape reference 1190×726", CGSize(width: 1190, height: 726)), ("portrait reference 814×1102", CGSize(width: 814, height: 1102)),
                             ("iPad 11in landscape 1194×834", CGSize(width: 1194, height: 834)), ("iPad 11in portrait 834×1194", CGSize(width: 834, height: 1194)),
                             ("iPad mini landscape 1133×744", CGSize(width: 1133, height: 744)), ("iPad mini portrait 744×1133", CGSize(width: 744, height: 1133)),
                             ("iPad 13in landscape 1376×1032", CGSize(width: 1376, height: 1032)), ("AUM window 900×600", CGSize(width: 900, height: 600))] {
            let p = euclideousPageLayout(size: size)
            let content = EuclideousLaneCardMetrics.contentAreaH(cardHeight: p.box.height)
            let upper = euclideousRhythmUpperH(contentAreaH: content), row = euclideousRhythmRightRowH(upperH: upper)
            let ed = euclideousDynamicsEditorLayout(width: EuclideousLaneCardMetrics.innerWidth(cardWidth: p.box.width), height: content)
            report.append(String(format: "%@: card %.2f × %.2f, zones %.1f (upper %.1f), rows %.2f, editor %.1f %@%@", name, p.box.width, p.box.height, content, upper, row, content,
                                 ed.showsResult ? "full" : "NO RESULT ROW", ed.clipsBottom ? " CLIPS" : ""))
            XCTAssertEqual(row, (upper - 8) / 3, accuracy: 1e-9)
            XCTAssertEqual(p.floors.contains(.rhythmRows), row < 36); XCTAssertEqual(p.floors.contains(.dynamicsEditor), content < 208)
        }
        print("DYNAMICS layouts:\n" + report.joined(separator: "\n"))
    }

    // MARK: the bars and the cells
    func testRowBarsAreTwoTallForARestAndAtLeastTwoForAHitAndShareTheStrip() {
        let bars = euclideousDynamicsRowBars(rowWidth: 167.25, rowHeight: 38.67, cells: [1, 0.5, nil, 0.0, 0.2, 1, nil, 0.7])
        XCTAssertEqual(bars.count, 8)
        XCTAssertEqual(bars[0].rect.height, 13); XCTAssertEqual(bars[1].rect.height, 6.5, accuracy: 1e-9); XCTAssertEqual(bars[2].rect.height, 2); XCTAssertFalse(bars[2].isHit)
        XCTAssertEqual(bars[3].rect.height, 2, "max(2, 13 × 0)"); XCTAssertEqual(bars[4].rect.height, 2.6, accuracy: 1e-9)
        XCTAssertEqual(bars[0].rect.minX, 8); XCTAssertEqual(bars[7].rect.maxX, 167.25 - 8, accuracy: 1e-9)
        XCTAssertEqual(bars[1].rect.minX - bars[0].rect.maxX, 3, accuracy: 1e-9)
        for b in bars { XCTAssertEqual(b.rect.maxY, 38.67 - 5, accuracy: 1e-9, "bottom-aligned 5 pt above the tile's bottom") }
        let b16 = euclideousDynamicsRowBars(rowWidth: 167.25, rowHeight: 38.67, cells: [Double?](repeating: 1, count: 16))
        XCTAssertEqual(b16[0].rect.width, 6.64, accuracy: 0.005, "(151.25 − 15 × 3) ÷ 16 — the ferry says about 6.9")
    }
    func testCellFactorsCoverEveryCellOfThePassAndShowTheSweepOfAPingPong() {
        let d = EuclideousDynamics(depth: 50, accents: 1, shape: 0, spread: 0, target: .vel)
        var l = EuclidLine(pulses: 5, steps: 8); l.direction = .fwd
        let fwd = euclideousDynamicsPassHitSteps(lane: 0, lines: [l])
        XCTAssertEqual(fwd.patternSteps, 8); XCTAssertEqual(fwd.cycleLen, 8); XCTAssertEqual(fwd.hits.count, 5)
        let cells = euclideousDynamicsCellFactors(d, lane: 0, pass: 0, patternSteps: 8, hitSteps: fwd.hits, cycleLen: 8, sweep: 0)
        XCTAssertEqual(cells.map { $0 != nil }, [true, false, true, false, true, true, false, true], "hits on steps 1, 3, 5, 6 and 8")
        XCTAssertEqual(cells[0], 1); XCTAssertEqual(cells[2]!, 0.5, accuracy: 1e-12)
        l.direction = .pingpong
        let pp = euclideousDynamicsPassHitSteps(lane: 0, lines: [l])
        XCTAssertEqual(pp.cycleLen, 16); XCTAssertEqual(pp.hits.count, 10)
        let first = euclideousDynamicsCellFactors(d, lane: 0, pass: 0, patternSteps: 8, hitSteps: pp.hits, cycleLen: 16, sweep: 0)
        let second = euclideousDynamicsCellFactors(d, lane: 0, pass: 0, patternSteps: 8, hitSteps: pp.hits, cycleLen: 16, sweep: 1)
        XCTAssertEqual(first.map { $0 != nil }, second.map { $0 != nil }, "the same cells are hits in both sweeps")
        XCTAssertEqual(first[0], 1, "the first sweep starts on the accent"); XCTAssertNotEqual(first[0], second[0], "…and the way back does not")
        // BKW: the cells stay in buffer order
        l.direction = .bkw
        let bkw = euclideousDynamicsPassHitSteps(lane: 0, lines: [l])
        let bc = euclideousDynamicsCellFactors(d, lane: 0, pass: 0, patternSteps: 8, hitSteps: bkw.hits, cycleLen: 8, sweep: 0)
        XCTAssertEqual(bc.map { $0 != nil }, cells.map { $0 != nil })
        XCTAssertEqual(bc[7], 1, "BKW plays step 8 first: it is the accent"); XCTAssertEqual(bc[0]!, 0.5, accuracy: 1e-12)
    }
    func testAFollowLaneUsesItsPartnersPatternForK() {
        var a = EuclidLine(pulses: 3, steps: 8), b = EuclidLine(pulses: 5, steps: 8)
        b.listenRhythmMode = .follow; b.listenRhythmPartner = 0
        a.direction = .fwd; b.direction = .fwd
        XCTAssertEqual(euclideousDynamicsPassHitSteps(lane: 1, lines: [a, b]).hits.count, 3, "lane 2 plays lane 1's three hits")
        XCTAssertEqual(euclideousDynamicsOwnPassHits(b), 5)
    }

    // MARK: the slider fields
    func testTheNewSliderFieldsRangeCommitResetAndSpeak() {
        var l = EuclidLine(pulses: 5, steps: 8)
        // ACCENTS: 0…k, shows min(stored, k), a drag stores what it shows
        l.dynAccents = 9
        XCTAssertEqual(euclideousSliderRange(.dynAccents, l, hits: 5).hi, 5); XCTAssertEqual(euclideousSliderRange(.dynAccents, l, hits: 5).value, 5, "stored 9 shows 5")
        XCTAssertEqual(euclideousSliderValueText(.dynAccents, l, hits: 5), "5 OF 5"); l.dynAccents = 2
        XCTAssertEqual(euclideousSliderValueText(.dynAccents, l, hits: 5), "2 OF 5"); XCTAssertEqual(euclideousSliderAccessibilityValueText(.dynAccents, l, hits: 5), "2 of 5")
        l.dynAccents = 0; XCTAssertEqual(euclideousSliderValueText(.dynAccents, l, hits: 5), "OFF")
        XCTAssertEqual(euclideousSliderTickFracs(.dynAccents, l, hits: 5).count, 6, "one tick per value 0…5")
        var d = l; euclideousSliderCommit(.dynAccents, &d, snapshot: l, newValue: 3); XCTAssertEqual(d.dynAccents, 3)
        euclideousSliderDoubleTapDefault(.dynAccents, &d); XCTAssertEqual(d.dynAccents, 1, "double-tap resets ACCENTS to 1")
        // DEPTH
        euclideousSliderCommit(.dynDepth, &d, snapshot: l, newValue: 44.6); XCTAssertEqual(d.dynDepth, 45)
        XCTAssertEqual(euclideousSliderValueText(.dynDepth, d), "45%"); XCTAssertEqual(euclideousSliderAccessibilityValueText(.dynDepth, d), "45 percent")
        euclideousSliderDoubleTapDefault(.dynDepth, &d); XCTAssertEqual(d.dynDepth, 0); XCTAssertEqual(euclideousSliderValueText(.dynDepth, d), "FLAT")
        // SHAPE (bipolar, true minus sign), SPREAD
        euclideousSliderCommit(.dynShape, &d, snapshot: l, newValue: -40); XCTAssertEqual(euclideousSliderValueText(.dynShape, d), "\u{2212}40")
        XCTAssertEqual(euclideousSliderAccessibilityValueText(.dynShape, d), "fade 40"); euclideousSliderCommit(.dynShape, &d, snapshot: l, newValue: 40)
        XCTAssertEqual(euclideousSliderValueText(.dynShape, d), "+40"); XCTAssertEqual(euclideousSliderAccessibilityValueText(.dynShape, d), "swell 40")
        euclideousSliderDoubleTapDefault(.dynShape, &d); XCTAssertEqual(euclideousSliderValueText(.dynShape, d), "0"); XCTAssertEqual(euclideousSliderAccessibilityValueText(.dynShape, d), "flat")
        euclideousSliderCommit(.dynSpread, &d, snapshot: l, newValue: 15); XCTAssertEqual(euclideousSliderValueText(.dynSpread, d), "15%"); XCTAssertEqual(euclideousSliderAccessibilityValueText(.dynSpread, d), "15 percent")
        // swipe steps: ACCENTS 1; SHAPE, DEPTH, SPREAD 5
        XCTAssertEqual(euclideousSliderAccessibilityStep(.dynAccents), 1)
        for f in [EuclideousSliderField.dynShape, .dynDepth, .dynSpread] { XCTAssertEqual(euclideousSliderAccessibilityStep(f), 5) }
        XCTAssertTrue(EuclideousSliderField.dynShape.isBipolar); XCTAssertTrue(EuclideousSliderField.tilt.isBipolar); XCTAssertFalse(EuclideousSliderField.dynDepth.isBipolar)
        // the existing six are untouched
        XCTAssertEqual(euclideousSliderRange(.hits, l).hi, 8); XCTAssertEqual(euclideousSliderValueText(.offset, l), "0")
    }
    func testTheWordsOfTheRowAndThePreview() {
        XCTAssertEqual(euclideousDynamicsDepthText(0), "FLAT"); XCTAssertEqual(euclideousDynamicsDepthText(45), "45%")
        XCTAssertEqual(euclideousDynamicsRowAccessibilityValue(depth: 0), "flat"); XCTAssertEqual(euclideousDynamicsRowAccessibilityValue(depth: 45), "depth 45 percent")
        XCTAssertEqual(euclideousDynamicsPreviewAccessibility(factors: [1, 0.55, 0.61], target: .vel), "This pass, velocity: hit 1 full, hit 2 at 55 percent, hit 3 at 61 percent")
        XCTAssertTrue(euclideousDynamicsPreviewAccessibility(factors: [1], target: .gate).contains("gate")); XCTAssertTrue(euclideousDynamicsPreviewAccessibility(factors: [1], target: .both).contains("velocity and gate"))
    }
}
