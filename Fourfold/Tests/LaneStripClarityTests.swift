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

    // MARK: §8.4 — the PLAY tiles' note chips share the one function (structural: the same stroke rule at the tile's band height)

    func testPlayTileNoteChipUsesTheSameStrokeRule() {
        // The tile's chip height is the ONE band formula at the tile's height (PartPlayButton.noteChipView): T 44 → 9 → no ink.
        let hH = LaneStripBandMetrics.bandH(T: 44)
        XCTAssertEqual(hH, 9)
        XCTAssertFalse(laneStripSoundStrokeHasInk(chipHeight: hH), "the tiles' 9 pt note chips lose the ink stroke with the bands")
    }
}
