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

    // MARK: §8.4 — the PLAY tiles' note chips share the one function (structural: the same stroke rule at the tile's band height)

    func testPlayTileNoteChipUsesTheSameStrokeRule() {
        // The tile's chip height is the ONE band formula at the tile's height (PartPlayButton.noteChipView): T 44 → 9 → no ink.
        let hH = LaneStripBandMetrics.bandH(T: 44)
        XCTAssertEqual(hH, 9)
        XCTAssertFalse(laneStripSoundStrokeHasInk(chipHeight: hH), "the tiles' 9 pt note chips lose the ink stroke with the bands")
    }
}
