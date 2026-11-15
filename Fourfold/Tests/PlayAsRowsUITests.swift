//  PlayAsRowsUITests.swift — PLAY AS ROWS ferry (2026-11-11): the NOTES tab layout (§5.2) and the pop-up tile pictures (§7).

import XCTest
import CoreGraphics

final class PlayAsRowsUITests: XCTestCase {
    // Amendment 1 §A10: seven rows (RANKS + six), 28 tall, 5 apart — 7×28 + 6×5 = 226, inside the real content area at both references.
    func testTheSevenRowsFitBothReferences() {
        for cardH in [301.0 as CGFloat, 301.67] {   // landscape / portrait lane card heights
            let h = EuclideousLaneCardMetrics.contentAreaH(cardHeight: cardH)
            let lay = euclideousPlayAsRowsLayout(contentAreaH: h, fullWidth: 360.67)
            XCTAssertTrue(lay.fits, "7 rows fit at contentAreaH \(h)")
            XCTAssertEqual(lay.emitRow.maxY, 226, accuracy: 0.01, "EMIT+OCT bottom at 226")
            XCTAssertEqual(lay.rankTiles.count, 8)
            XCTAssertEqual(lay.rankLabel.width, 55, "§A10 label column 55")
            XCTAssertEqual(lay.rankTiles[0].width, (360.67 - 80) / 8, accuracy: 0.01, "amend 3 §C1.3: tiles fill (~35.08 at 360.67), REPEAT gone")
            XCTAssertEqual(lay.rankTiles[0].height, 26, accuracy: 0.01, "§C1.3 height unchanged")
            XCTAssertEqual(lay.rankTiles[0].minX, 59, accuracy: 0.01, "tiles after the 55 label + 4 subGap")
            XCTAssertEqual(lay.rankTiles[7].maxX, 360.67, accuracy: 0.01, "§C1.3 the eighth tile fills to the row's end")
        }
    }
    // §A10.2 / test 7: at both references every control's frame lies inside the card, and REPEAT is inside the card clear of the tiles.
    func testEveryFrameIsInsideTheCard() {
        for w in [360.67 as CGFloat, 367.0] {   // landscape / portrait inner widths
            let lay = euclideousPlayAsRowsLayout(contentAreaH: 229, fullWidth: w)
            for t in lay.rankTiles {
                XCTAssertGreaterThanOrEqual(t.minX, lay.rankLabel.maxX)
                XCTAssertLessThanOrEqual(t.maxX, w + 0.01, "tile inside the card at \(w)")
            }
            XCTAssertEqual(lay.rankTiles[7].maxX, w, accuracy: 0.01, "amend 3 §C1.3: tiles fill to the row's end (REPEAT removed)")
            for r in [lay.whenRow, lay.orderRow, lay.voicesRow, lay.spreadRow, lay.bassRow, lay.emitRow] {
                XCTAssertEqual(r.width, w); XCTAssertGreaterThan(r.minY, 0); XCTAssertLessThanOrEqual(r.maxY, 226.01)
            }
        }
    }
    // §B3.1 (amend 2): the pop-up grid — FIVE rows (header + ONCE/DOUBLE/RETURN/PEDAL) of eight 26-tall cells + a PASS band, all inside the body. (Updated from amend 1's 4-row / 32 shape, which this test had not tracked.)
    func testRepeatPopupLayout() {
        let lay = euclideousRepeatPopupLayout(bodyW: 340, bodyH: 217)
        XCTAssertEqual(lay.cells.count, 5); XCTAssertEqual(lay.cells[0].count, 8)
        for row in lay.cells { for c in row { XCTAssertLessThanOrEqual(c.maxX, 340.01); XCTAssertEqual(c.height, EuclideousRepeatPopupLayout.cellH) } }
        XCTAssertGreaterThan(lay.passArea.minY, lay.cells[4][0].maxY, "PASS below the PEDAL row")
        XCTAssertGreaterThan(lay.divider.minY, lay.cells[4][0].maxY)
    }
    // §7: the tile pictures are well-formed (levels in 1…4, the right counts).
    func testTilePictures() {
        XCTAssertEqual(euclideousOrderTileLevels(.up), [1, 2, 3, 4, 1, 2])
        XCTAssertEqual(euclideousOrderTileLevels(.insideOut), [3, 2, 4, 1, 3, 2], "§7.1's explicit INSIDE OUT picture")   // the ferry's pictures are illustrative, not exact reverses
        for m in euclideousOrderTileOrder { for l in euclideousOrderTileLevels(m) { XCTAssertTrue((1...4).contains(l)) } }
        XCTAssertEqual(euclideousVoicesTileColumns(.all), [4]); XCTAssertEqual(euclideousVoicesTileColumns(.grow), [1, 2, 3, 4])
        XCTAssertEqual(euclideousSpreadTileDots(.run).map { $0.x }, [0.2, 0.5, 0.8])
    }
    // §5.4 SHIFT value text.
    func testShiftText() {
        XCTAssertEqual(euclideousShiftValueText(start: 3, driftOn: false, step: 2), "3")
        XCTAssertEqual(euclideousShiftValueText(start: 1, driftOn: true, step: 1), "1 · +1")
        XCTAssertEqual(euclideousShiftValueText(start: 2, driftOn: true, step: -3), "2 · -3")
    }
}
