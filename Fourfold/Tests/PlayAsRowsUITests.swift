//  PlayAsRowsUITests.swift — PLAY AS ROWS ferry (2026-11-11): the NOTES tab layout (§5.2) and the pop-up tile pictures (§7).

import XCTest
import CoreGraphics

final class PlayAsRowsUITests: XCTestCase {
    // §5.2: the seven rows fit the 233 / 233.67 content area (7×28 + 6×6 = 232).
    func testTheSevenRowsFitBothReferences() {
        for h in [233.0 as CGFloat, 233.67] {
            let lay = euclideousPlayAsRowsLayout(contentAreaH: h, fullWidth: 360.67, cross: false)
            XCTAssertTrue(lay.fits, "7 rows fit at \(h)")
            XCTAssertNotNil(lay.emitRow); XCTAssertNotNil(lay.bassRow)
            XCTAssertEqual(lay.emitRow!.maxY, 232, accuracy: 0.01, "EMIT+OCT bottom at 232")
            XCTAssertTrue(lay.hidden.isEmpty)
            XCTAssertEqual(lay.rankTiles.count, 8); XCTAssertNil(lay.secondRow)
        }
    }
    // §6.5: × mode grows RANKS to 92 and hides BASS, EMIT (and anything below SPREAD).
    func testCrossModeHidesTheBottomRows() {
        let lay = euclideousPlayAsRowsLayout(contentAreaH: 233, fullWidth: 360.67, cross: true)
        XCTAssertNotNil(lay.secondRow); XCTAssertNotNil(lay.thirdRow)
        XCTAssertNotNil(lay.spreadRow, "SPREAD still shows")
        XCTAssertNil(lay.bassRow, "BASS hidden"); XCTAssertNil(lay.emitRow, "EMIT hidden")
        XCTAssertEqual(Set(lay.hidden), ["BASS", "EMIT"])
        XCTAssertEqual(lay.secondCells.count, 8); XCTAssertEqual(lay.thirdCells.count, 8)
        // the 2ND/3RD cells line up under the tiles
        for i in 0..<8 { XCTAssertEqual(lay.secondCells[i].minX, lay.rankTiles[i].minX); XCTAssertEqual(lay.thirdCells[i].minX, lay.rankTiles[i].minX) }
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
