//  StackRiffArrowTests.swift — STACK GRID RIFF ARROW ferry (2026-11-12), slice 2: the pure arrow spec (§2) —
//  the fill is the riff map colour at the strip chip's (column, rank), the label is the column, REPEAT is hollow.
//  §7 tests 2, 3, 4 (test 1 — riffGhost = the current chip — is in LaneStripTests, where the plan fixtures live).

import XCTest
import CoreGraphics

final class StackRiffArrowTests: XCTestCase {
    private func near(_ c: EuclideousRGB, _ h: UInt32, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        let r = Int((h >> 16) & 0xFF), g = Int((h >> 8) & 0xFF), b = Int(h & 0xFF)
        XCTAssertLessThanOrEqual(abs(c.r - r) + abs(c.g - g) + abs(c.b - b), 3, "\(msg) got \(c) want #\(String(h, radix: 16))", file: file, line: line)
    }
    private let cell = CGRect(x: 10, y: 4, width: 60, height: 24)

    // §7.2 — the arrow fill equals the strip's current chip fill (riffMapColour) for the same (column, rank).
    func testArrowFillIsTheRiffMapColour() {
        near(euclideousStackRiffArrow(cell: cell, column: 3, rank: 1, isRepeat: false).fill, 0x898335, "col 3 rank 1")
        near(euclideousStackRiffArrow(cell: cell, column: 4, rank: 4, isRepeat: false).fill, 0x7BBC88, "col 4 rank 4")
        near(euclideousStackRiffArrow(cell: cell, column: 7, rank: 7, isRepeat: false).fill, 0xCECDFF, "col 7 rank 7")
        // and it IS riffMapColour (the strip's chip fill) by construction — can never diverge
        XCTAssertEqual(euclideousStackRiffArrow(cell: cell, column: 7, rank: 7, isRepeat: false).fill, riffMapColour(column: 7, rank: 7))
    }

    // §7.3 — REPEAT: a hollow arrow with the off-cell fill and a map-colour label.
    func testRepeatArrowIsHollow() {
        let a = euclideousStackRiffArrow(cell: cell, column: 6, rank: 6, isRepeat: true)
        XCTAssertTrue(a.isRepeat)
        XCTAssertEqual(a.fill, EuclideousStackArrowTuning.offFill, "REPEAT's body is the grid's off-cell fill #1F2127")
        XCTAssertEqual(a.fill, EuclideousRGB(r: 0x1F, g: 0x21, b: 0x27))
        near(a.labelColour, 0x89D0FF, "REPEAT's label is riffMapColour(6,6)")
        XCTAssertEqual(a.labelColour, riffMapColour(column: 6, rank: 6))
    }

    // §7.4 — the label is the COLUMN number (not the lane or the rank); a filled arrow's label is the ink.
    func testLabelIsTheColumnNumber() {
        let a = euclideousStackRiffArrow(cell: cell, column: 3, rank: 1, isRepeat: false)
        XCTAssertEqual(a.label, "3", "the label is the column, not the rank (1) or a lane")
        XCTAssertEqual(a.labelColour, EuclideousRGB(r: 0x0D, g: 0x0F, b: 0x14), "a filled arrow's label is the ink #0D0F14")
    }

    // §2.1 — the frame: 23 × 17 at the cell's left inset 3, vertically centred.
    func testArrowFrame() {
        let f = euclideousStackRiffArrow(cell: cell, column: 2, rank: 2, isRepeat: false).frame
        XCTAssertEqual(f, CGRect(x: 10 + 3, y: cell.midY - 17 / 2, width: 23, height: 17))   // (13, 7.5, 23, 17)
    }
}
