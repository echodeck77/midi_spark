//  LaneStripClarityTests.swift — LANE STRIP CLARITY ferry (2026-11-17) §8: slim bands, the sounding chip's strokes,
//  stack label hiding, resting rank marks, the even hit colours, the playhead tick and the states. Pure, macOS target.

import XCTest

final class LaneStripClarityTests: XCTestCase {

    // MARK: §8.3 — the sounding chip under 12 pt: one white stroke, no ink, the cap band wholly inside the strokes

    func testSoundingStrokeInkRule() {
        XCTAssertFalse(laneStripSoundStrokeHasInk(chipHeight: 8), "an 8 pt chip: white stroke only")
        XCTAssertFalse(laneStripSoundStrokeHasInk(chipHeight: 9), "the T-44 band (hH 9): white stroke only")
        XCTAssertFalse(laneStripSoundStrokeHasInk(chipHeight: 11.9))
        XCTAssertTrue(laneStripSoundStrokeHasInk(chipHeight: 12), "12 pt or taller keeps STACK GREY 2.4's two strokes")
        XCTAssertTrue(laneStripSoundStrokeHasInk(chipHeight: 16))
    }

    func testChipCapBandSitsWhollyInsideTheStrokes() {
        // §2.4: the 7 pt heavy label's cap height must sit wholly between the strokes at every band height the
        // layout can produce (hH = max(8, round(T × 0.2)) — 8 is the floor; larger T grows it).
        for h in stride(from: 8.0, through: 24.0, by: 0.5) {
            let b = laneStripChipCapBand(chipHeight: CGFloat(h), labelSize: LaneStripBandMetrics.chipLabel)
            XCTAssertGreaterThanOrEqual(b.capTop, b.clearTop, "chip \(h): the cap's top is under the stroke band")
            XCTAssertLessThanOrEqual(b.capBottom, b.clearBottom, "chip \(h): the cap's bottom is under the stroke band")
        }
    }

    // MARK: §8.1 — slim bands: 4 pt, no labels, the cells take the height; the threshold is ON-SCREEN width (Paul 2026-11-17)

    func testSlimDecisionIsOnScreenWidth() {
        XCTAssertFalse(laneStripIsSlim(cellWidth: 14.67, displayScale: 1), "full size: 16 steps lay out at 14.67 — not slim")
        XCTAssertTrue(laneStripIsSlim(cellWidth: 14.67, displayScale: 0.5), "the AUM recording: ≈7.3 on screen — slim")
        XCTAssertFalse(laneStripIsSlim(cellWidth: 12, displayScale: 1), "exactly 12 is not under 12")
        XCTAssertTrue(laneStripIsSlim(cellWidth: 11.9, displayScale: 1))
        XCTAssertFalse(laneStripIsSlim(cellWidth: 31.33, displayScale: 0.5), "8 steps at half scale ≈ 15.7 — not slim")
    }

    func testSlimBandHeights() {
        // §1.2: rail 1.5 + gap 1 + band 4 + gap 1 = 7.5 a part. At T 41 both on: hC 26 (the spec's example); at the built T 44: 29.
        let t41 = laneStripBandHeights(T: 41, slim: true)
        XCTAssertEqual(t41.hH, 4); XCTAssertEqual(t41.hC, 26)
        let t44 = laneStripBandHeights(T: 44, slim: true)
        XCTAssertEqual(t44.hH, 4); XCTAssertEqual(t44.hC, 29)
        // §1.5: a lane that isn't slim keeps play rail 3.1's band.
        let wide = laneStripBandHeights(T: 44)
        XCTAssertEqual(wide.hH, 9); XCTAssertEqual(wide.hC, 19)
        // play rail 3.3: one part off collapses its reserve, slim or not.
        XCTAssertEqual(laneStripBandHeights(T: 44, riffFrac: 0, slim: true).hC, 36.5)
        XCTAssertEqual(laneStripBandHeights(T: 44, riffFrac: 0).hC, 31.5)
        // the frames carry the slim flag + 4 pt band slots
        let f = laneStripBandFrames(xs: [0, 10], columnW: 8, T: 44, slim: true)
        XCTAssertTrue(f.slim)
        XCTAssertEqual(f.header[0].height, 4); XCTAssertEqual(f.footer[0].height, 4)
        XCTAssertEqual(f.cells[0].height, 29)
    }

    // MARK: §8.2 — a slim chip rests at 60 % and sounds at 100 % (no stroke: the painter skips the stroke when slim)

    func testSlimChipOpacity() {
        XCTAssertEqual(laneStripSlimChipOpacity(sounding: false), 0.6)
        XCTAssertEqual(laneStripSlimChipOpacity(sounding: true), 1.0)
        XCTAssertEqual(LaneStripBandMetrics.slimChipRadius, 1)
        XCTAssertEqual(LaneStripBandMetrics.slimBandH, 4)
    }

    // MARK: §8.5 — stack labels only on the first hit and where the rank set changes; unpredicted labels the hit after

    func testStackLabelHiding() {
        // a pass of five hits all on rank 1: the first chip only
        XCTAssertEqual(laneStripFooterLabelled(hitRankSets: [[1], [1], [1], [1], [1]]), [true, false, false, false, false])
        // ranks 1, 1, 3, 3, 1: the first, third and fifth
        XCTAssertEqual(laneStripFooterLabelled(hitRankSets: [[1], [1], [3], [3], [1]]), [true, false, true, false, true])
        // an unpredicted slot ([]) labels the hit after it; the slot itself shows no label
        XCTAssertEqual(laneStripFooterLabelled(hitRankSets: [[1], [], [1], [1]]), [true, false, true, false])
        // rests (nil) are transparent to the comparison
        XCTAssertEqual(laneStripFooterLabelled(hitRankSets: [[2], nil, [2], nil, [3]]), [true, false, false, false, true])
        // chords compare as sets: {1,3} → {1,3} hides; {1,3} → {1,4} labels
        XCTAssertEqual(laneStripFooterLabelled(hitRankSets: [[1, 3], [1, 3], [1, 4]]), [true, false, true])
        // §3.4: the drawn set, not sounding, decides — the same sets give the same labels whatever is playing (pure input).
    }

    // MARK: §8.8 — the even hit colours: one lightness, ≥ 1.9:1 on the rest fill, a lighter playhead variant, built once

    func testHitColoursAreEvenAndContrasty() {
        let rest = StripHitTuning.restFill
        var lightnesses: [Double] = []
        for lane in 0..<4 {
            let hit = stripHitColour(lane: lane, atPlayhead: false)
            let ph = stripHitColour(lane: lane, atPlayhead: true)
            lightnesses.append(euclideousOKLCH(hit).L)
            XCTAssertGreaterThanOrEqual(euclideousWCAGContrast(hit, rest), 1.9, "lane \(lane): the hit must stand off #22242A")
            XCTAssertGreaterThan(euclideousOKLCH(ph).L, euclideousOKLCH(hit).L, "lane \(lane): the playhead variant is lighter")
            // the hue survives the round trip (the colour is the LANE's own, §9/§11)
            let want = euclideousOKLCH(euclideousLaneTokens[lane]).h
            let got = euclideousOKLCH(hit).h
            var d = abs(want - got); if d > 180 { d = 360 - d }
            XCTAssertLessThan(d, 8, "lane \(lane): the hit keeps the token's hue (Δh \(d)°)")
        }
        // §8.8: all four lanes share one OKLCH lightness (within 8-bit quantisation of the round trip)
        for l in lightnesses { XCTAssertEqual(l, lightnesses[0], accuracy: 0.015) }
        XCTAssertEqual(stripHitConversionCount, 8, "the 4 × 2 table is built once")
        _ = stripHitColour(lane: 2, atPlayhead: true)
        XCTAssertEqual(stripHitConversionCount, 8, "reads never convert")
    }

    // MARK: §8.9/§8.10 — the tick (pure parts: the rect, the stopped gate)

    func testPlayheadTickRectAndStoppedGate() {
        let cell = CGRect(x: 10, y: 12.5, width: 14.67, height: 19)
        let t = laneStripTickRect(cell: cell)
        XCTAssertEqual(t, CGRect(x: 10, y: 12.5, width: 14.67, height: 2), "2 pt, full width, along the inside of the top edge")
        XCTAssertEqual(LaneStripBandMetrics.tickH, 2)
        // §6.5/§8.10: stopped ⇒ the painter gets playheadStep nil (the existing `running ?` gate in EuclidCometBar) ⇒ no tick.
        XCTAssertNil(euclideousStripPlayheadStep(raw: 3.2, n: 0, dir: .fwd), "a degenerate lane has no playhead at all")
    }

    // MARK: §8.6/§8.7 — resting rank bars: predicted at rest, white while sounding, none for unpredicted/off parts

    func testRestingAndSoundingBarDecisions() {
        // §4.1/§4.3 — the stack's drawn ranks: the prediction until played, then the played set
        XCTAssertEqual(laneStripRestingStackRanks(played: [], predicted: [2, 5]), [2, 5], "predicted at rest")
        XCTAssertEqual(laneStripRestingStackRanks(played: [3], predicted: [2, 5]), [3], "a played hit's set replaces the prediction")
        XCTAssertEqual(laneStripRestingStackRanks(played: [], predicted: []), [], "unpredicted ⇒ no bars until it plays")
        // §4.4 — one white bar when both parts sound one rank (the stack's folds into the riff's width)
        XCTAssertTrue(laneStripStackBarFoldsIntoRiff(rank: 3, riffRank: 3, riffSounding: true))
        XCTAssertFalse(laneStripStackBarFoldsIntoRiff(rank: 3, riffRank: 3, riffSounding: false), "at rest the stack draws OVER the riff (B4.2), it does not fold")
        XCTAssertFalse(laneStripStackBarFoldsIntoRiff(rank: 3, riffRank: 5, riffSounding: true))
        XCTAssertFalse(laneStripStackBarFoldsIntoRiff(rank: 3, riffRank: nil, riffSounding: false))
        XCTAssertEqual(LaneRankBarTuning.restOpacity, 0.5, "§10: the resting bar opacity")
    }

    func testRankBarGeometryIsAmendmentOnes() {
        // §4.1: the bars sit at amendment 1 B4's slots, computed from the CURRENT hC — slim (29) and full (19) alike.
        let cellSlim = CGRect(x: 0, y: 7.5, width: 7, height: 29)
        let slim = rankSlotRect(cell: cellSlim, hC: 29, rank: 8, part: .riff)
        XCTAssertTrue(slim.filled, "slot (29−5)/8 = 3 < 4 ⇒ the filled-bar fallback")
        XCTAssertEqual(slim.rect.minY, cellSlim.minY + 1 + 0 * 3 + (3 - max(1, 3 - 0.5)) / 2, accuracy: 0.001, "rank 8 in the top slot")
        let full = rankSlotRect(cell: CGRect(x: 0, y: 12.5, width: 14.67, height: 19), hC: 19, rank: 1, part: .stack)
        XCTAssertTrue(full.filled, "at hC 19 the slot is 1.75 — always the bar fallback")
    }

    // MARK: §8.4 — the PLAY tiles' note chips share the one function (structural: the same stroke rule at the tile's band height)

    func testPlayTileNoteChipUsesTheSameStrokeRule() {
        // The tile's chip height is the ONE band formula at the tile's height (PartPlayButton.noteChipView): T 44 → 9 → no ink.
        let hH = LaneStripBandMetrics.bandH(T: 44)
        XCTAssertEqual(hH, 9)
        XCTAssertFalse(laneStripSoundStrokeHasInk(chipHeight: hH), "the tiles' 9 pt note chips lose the ink stroke with the bands")
    }
}
