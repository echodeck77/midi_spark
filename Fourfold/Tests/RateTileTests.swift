//  RateTileTests.swift — RATE ferry (2026-11-12), slice 5: the RATE tile's pure layout (§3) and the current-box / progress /
//  readout maths (§5/§4.2). The box/chip/FREE interactions are page methods (device-owed); the model ops they do are trivial.

import XCTest

final class RateTileTests: XCTestCase {
    func testLayoutHasEightBoxesFourChipsAndAFreePill() {
        let L = euclideousRateTileLayout(box: CGSize(width: 172, height: 80))
        XCTAssertTrue(L.showHeader, "80 pt is ≥ 72 ⇒ the header shows (§3.5)")
        XCTAssertEqual(L.boxes.count, 8); XCTAssertEqual(L.chips.count, 4)
        XCTAssertEqual(L.freePill.width, 32, accuracy: 0.01, "§3.2 FREE pill 32 wide")
        for b in L.boxes { XCTAssertGreaterThanOrEqual(b.height, 28, "§3.2 boxes never under 28 tall") }
        // boxes 2.5 apart, left to right
        for i in 1..<8 { XCTAssertEqual(L.boxes[i].minX - L.boxes[i - 1].maxX, 2.5, accuracy: 0.05, "boxes 2.5 pt apart") }
        // everything inside the 6 pt side padding
        XCTAssertGreaterThanOrEqual(L.boxes[0].minX, 6 - 0.01); XCTAssertLessThanOrEqual(L.boxes[7].maxX, 172 - 6 + 0.01)
    }
    func testShortLayoutDropsTheHeader() {
        let L = euclideousRateTileLayout(box: CGSize(width: 172, height: 64))
        XCTAssertFalse(L.showHeader, "under 72 pt the header row is dropped (§3.5)")
        XCTAssertEqual(L.chevron, .zero); XCTAssertEqual(L.boxes.count, 8)
    }
    func testCurrentBoxWrapsEveryEightBarsAndIsNilWhenStopped() {
        XCTAssertNil(euclideousRateCurrentBox(hostBeat: nil, beatsPerBar: 4), "§4.8 stopped ⇒ no current box")
        XCTAssertEqual(euclideousRateCurrentBox(hostBeat: 0.1, beatsPerBar: 4), 0, "host bar 1 ⇒ box 1 (index 0)")
        XCTAssertEqual(euclideousRateCurrentBox(hostBeat: 13, beatsPerBar: 4), 3, "bar 3 ⇒ box index 3")
        XCTAssertEqual(euclideousRateCurrentBox(hostBeat: 33, beatsPerBar: 4), 0, "bar 8 wraps to box index 0")
        XCTAssertEqual(euclideousRateCurrentBox(hostBeat: 7, beatsPerBar: 3.5), 2, "7/8 time: bar 2")
    }
    func testBarProgressRunsZeroToOne() {
        XCTAssertEqual(euclideousRateBarProgress(hostBeat: 12, beatsPerBar: 4), 0, accuracy: 1e-9, "at the bar line")
        XCTAssertEqual(euclideousRateBarProgress(hostBeat: 14, beatsPerBar: 4), 0.5, accuracy: 1e-9, "halfway")
        XCTAssertEqual(euclideousRateBarProgress(hostBeat: 15.9, beatsPerBar: 4), 0.975, accuracy: 1e-9, "approaching the next")
    }
    func testReadoutLabel() {
        var l = EuclidLine()
        XCTAssertEqual(euclideousRateReadoutLabel(line: l, currentBox: 3), "\u{00D7}1", "no override ⇒ ×1")
        l.rateBars = [0, 0, 0, 3, 0, 0, 0, 0]
        XCTAssertEqual(euclideousRateReadoutLabel(line: l, currentBox: 3), "\u{00D7}2", "in a ×2 box ⇒ ×2")
        XCTAssertEqual(euclideousRateReadoutLabel(line: l, currentBox: 1), "\u{00D7}1", "an off box ⇒ ×1")
    }
    func testMultiplierLabels() {
        XCTAssertEqual([1, 2, 3, 4].map { euclideousRateMultiplierLabel(code: UInt8($0)) }, ["\u{00D7}\u{00BD}", "\u{00D7}1\u{00BD}", "\u{00D7}2", "\u{00D7}4"])
    }
}
