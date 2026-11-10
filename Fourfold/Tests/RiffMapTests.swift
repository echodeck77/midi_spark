//  RiffMapTests.swift — RIFF MAP ferry (2026-11-10): every riff-grid cell has a colour from its column and rank, and every lane-strip chip wears the colour of the cell it plays.
//  This file is the pure side (§1: the colours, the faint form, the tables) and, further down, what the strip and the grid decide from them.

import XCTest

final class RiffMapTests: XCTestCase {

    private func hex(_ c: EuclideousRGB) -> String { String(format: "#%02X%02X%02X", c.r, c.g, c.b) }
    private func rgb(_ s: String) -> EuclideousRGB {
        let v = UInt32(s.dropFirst(), radix: 16)!
        return EuclideousRGB(r: Int(v >> 16) & 255, g: Int(v >> 8) & 255, b: Int(v) & 255)
    }
    private func assertNear(_ a: EuclideousRGB, _ b: EuclideousRGB, tol: Int = 1, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(abs(a.r - b.r) <= tol && abs(a.g - b.g) <= tol && abs(a.b - b.b) <= tol, "\(what): \(hex(a)) vs \(hex(b))", file: file, line: line)
    }
    private func luminance(_ c: EuclideousRGB) -> Double {
        func lin(_ v: Int) -> Double { let x = Double(v) / 255; return x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }
    private func contrast(_ a: EuclideousRGB, _ b: EuclideousRGB) -> Double {
        let la = luminance(a), lb = luminance(b)
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }

    /// The ferry's full table: rank 8 on top, columns 1 … 8 left to right.
    private let table: [Int: [String]] = [
        8: ["#FFCACF", "#FFD5A1", "#EEE99A", "#B5F8C2", "#8EFAF9", "#A6EEFF", "#DDDCFF", "#FFCDFF"],
        7: ["#FFBBC0", "#FFC692", "#DFDA8B", "#A6E9B3", "#7FEBEA", "#97DFFF", "#CECDFF", "#FCBEF5"],
        6: ["#FFACB2", "#F7B884", "#D0CB7D", "#97DAA5", "#6FDBDB", "#89D0FF", "#C0BEFF", "#ECAFE6"],
        5: ["#F19EA4", "#E8A976", "#C2BC6E", "#89CB96", "#5FCCCC", "#7AC1F2", "#B1AFF6", "#DDA1D7"],
        4: ["#E29096", "#D89B68", "#B3AE60", "#7BBC88", "#4FBEBD", "#6CB2E3", "#A3A1E7", "#CE93C8"],
        3: ["#D28188", "#C98D5A", "#A59F52", "#6DAD7B", "#3EAFAF", "#5EA4D4", "#9593D8", "#BF85B9"],
        2: ["#C3747A", "#BA7F4C", "#979144", "#5F9F6D", "#2AA1A1", "#4F96C5", "#8885C8", "#B077AB"],
        1: ["#B4666D", "#AC713E", "#898335", "#519160", "#0F9293", "#4188B6", "#7A77BA", "#A26A9D"],
    ]

    // MARK: §6 test 1 — the colours

    func testTheNamedCellsMatchTheFerrysTable() {
        for (c, r, h) in [(1, 1, "#B4666D"), (3, 3, "#A59F52"), (4, 5, "#89CB96"), (6, 2, "#4F96C5"), (8, 4, "#CE93C8"), (5, 8, "#8EFAF9"), (7, 6, "#C0BEFF"), (1, 8, "#FFCACF")] {
            assertNear(riffMapColour(column: c, rank: r), rgb(h), "(\(c),\(r))")
        }
    }
    func testAllSixtyFourCellsMatchTheFerrysTable() {
        for (rank, row) in table { for (i, h) in row.enumerated() { assertNear(riffMapColour(column: i + 1, rank: rank), rgb(h), "(\(i + 1),\(rank))") } }
    }
    func testColumnsAboveEightRepeatTheHuesAndOutOfRangeRanksClamp() {
        for c in 1...8 { for r in 1...8 { XCTAssertEqual(riffMapColour(column: c + 8, rank: r), riffMapColour(column: c, rank: r)) } }
        XCTAssertEqual(riffMapColour(column: 3, rank: 0), riffMapColour(column: 3, rank: 1))
        XCTAssertEqual(riffMapColour(column: 3, rank: 12), riffMapColour(column: 3, rank: 8))
        XCTAssertEqual(riffMapColour(column: 0, rank: 4), riffMapColour(column: 1, rank: 4))
    }

    // MARK: test 2 — lightness rises with rank

    func testLuminanceRisesStrictlyFromRankOneToEightInEveryColumn() {
        for c in 1...8 { for r in 1..<8 {
            XCTAssertLessThan(luminance(riffMapColour(column: c, rank: r)), luminance(riffMapColour(column: c, rank: r + 1)), "column \(c), rank \(r) → \(r + 1)")
        } }
    }

    // MARK: test 3 — the strip's ink reads on every colour

    func testInkReadsOnAllSixtyFourColours() {
        let ink = rgb("#0D0F14")
        for c in 1...8 { for r in 1...8 { XCTAssertGreaterThanOrEqual(contrast(ink, riffMapColour(column: c, rank: r)), 4.5, "(\(c),\(r)) \(hex(riffMapColour(column: c, rank: r)))") } }
    }

    // MARK: test 4 — the faint form

    func testFaintOverTheFerrysCanvasFillMatchesItsPins() {
        let canvas = rgb("#232428")
        for (c, r, h) in [(1, 1, "#403136"), (5, 8, "#384F52"), (8, 4, "#453A48")] {
            assertNear(riffMapFaintMix(riffMapColour(column: c, rank: r), over: canvas), rgb(h), "faint (\(c),\(r)) over #232428")
        }
    }
    /// The grid's REAL empty cell is not the canvas's #232428. It is white 8 % over the panel's white 3.5 % over the page ground (0.05, 0.055, 0.07); the constant must be exactly that, flat.
    func testTheEmptyFillConstantIsTheGridsRealEmptyCell() {
        let ground = [0.05, 0.055, 0.07].map { $0 * 255 }
        let panel = ground.map { $0 + 0.035 * (255 - $0) }
        let empty = panel.map { Int(($0 + 0.08 * (255 - $0)).rounded()) }
        let note = panel.map { Int(($0 + 0.85 * (255 - $0)).rounded()) }
        XCTAssertEqual(RiffMapTuning.emptyFill, EuclideousRGB(r: empty[0], g: empty[1], b: empty[2]))
        XCTAssertEqual(hex(RiffMapTuning.emptyFill), "#28292C")
        XCTAssertEqual(hex(EuclideousRGB(r: note[0], g: note[1], b: note[2])), "#DCDCDD", "the note cell the strip's old chips copied")
    }
    func testFaintIsTwentyPercentOfTheMapOverTheRealEmptyFillForAllSixtyFourCells() {
        let e = RiffMapTuning.emptyFill
        for c in 1...8 { for r in 1...8 {
            let m = riffMapColour(column: c, rank: r), f = riffMapFaint(column: c, rank: r)
            XCTAssertEqual(f.r, Int((0.2 * Double(m.r) + 0.8 * Double(e.r)).rounded()), "(\(c),\(r)) r")
            XCTAssertEqual(f.g, Int((0.2 * Double(m.g) + 0.8 * Double(e.g)).rounded()), "(\(c),\(r)) g")
            XCTAssertEqual(f.b, Int((0.2 * Double(m.b) + 0.8 * Double(e.b)).rounded()), "(\(c),\(r)) b")
        } }
        // the same cells over the real fill, spelled out for the three the ferry pins
        XCTAssertEqual(hex(riffMapFaint(column: 1, rank: 1)), "#443539")
    }
    func testFaintIsAlwaysCloserToTheEmptyFillThanToTheMapColour() {
        let e = RiffMapTuning.emptyFill
        func dist(_ a: EuclideousRGB, _ b: EuclideousRGB) -> Int { abs(a.r - b.r) + abs(a.g - b.g) + abs(a.b - b.b) }
        for c in 1...8 { for r in 1...8 { XCTAssertLessThan(dist(riffMapFaint(column: c, rank: r), e), dist(riffMapColour(column: c, rank: r), e)) } }
    }

    // MARK: test 5 — built once

    func testTheTablesAreBuiltOnceAndNoLookupConverts() {
        _ = riffMapColour(column: 1, rank: 1)   // first use builds them
        let built = riffMapConversionCount
        XCTAssertEqual(built, 64, "one OKLCH conversion per cell, the faint form is arithmetic")
        for i in 0..<20_000 { _ = riffMapColour(column: i % 12 + 1, rank: i % 8 + 1); _ = riffMapFaint(column: i % 9 + 1, rank: i % 8 + 1) }
        XCTAssertEqual(riffMapConversionCount, built, "a lookup never converts")
    }

    // MARK: test 10 — the grid

    func testAWrittenNoteFillsItsCellAndTheRestOfItsColumnIsFaint() {
        var ranks = [Int](repeating: 0, count: 8); ranks[1] = 3   // column 2 holds rank 3
        for r in 1...8 {
            let cell = riffMapGridCell(column: 2, rank: r, ranks: ranks)
            if r == 3 { XCTAssertEqual(hex(cell), "#C98D5A"); XCTAssertTrue(riffMapGridCellIsNote(column: 2, rank: r, ranks: ranks)) }
            else { XCTAssertEqual(cell, riffMapFaint(column: 2, rank: r), "rank \(r)"); XCTAssertFalse(riffMapGridCellIsNote(column: 2, rank: r, ranks: ranks)) }
        }
    }
    func testMovingTheNoteFillsTheNewCellAtOnceAndReturnsTheOldOneToFaint() {
        var ranks = [Int](repeating: 0, count: 8); ranks[1] = 3
        XCTAssertEqual(hex(riffMapGridCell(column: 2, rank: 3, ranks: ranks)), "#C98D5A")
        ranks[1] = 6   // the drag-a-line gesture writes the column's rank as the finger crosses it
        XCTAssertEqual(hex(riffMapGridCell(column: 2, rank: 6, ranks: ranks)), "#F7B884")
        XCTAssertEqual(riffMapGridCell(column: 2, rank: 3, ranks: ranks), riffMapFaint(column: 2, rank: 3))
    }
    func testARestColumnIsFaintInAllEightCells() {
        let ranks = [0, 0, 5, 0, 0, 0, 0, 0]
        for r in 1...8 { XCTAssertEqual(riffMapGridCell(column: 1, rank: r, ranks: ranks), riffMapFaint(column: 1, rank: r)); XCTAssertFalse(riffMapGridCellIsNote(column: 1, rank: r, ranks: ranks)) }
        XCTAssertTrue(riffMapGridCellIsNote(column: 3, rank: 5, ranks: ranks))
    }
    func testAColumnPastTheRanksIsFaintAndNeverCrashes() {
        XCTAssertFalse(riffMapGridCellIsNote(column: 9, rank: 4, ranks: [1, 2, 3]))
        XCTAssertFalse(riffMapGridCellIsNote(column: 0, rank: 4, ranks: [4]))
        XCTAssertEqual(riffMapGridCell(column: 4, rank: 2, ranks: [1, 2, 3]), riffMapFaint(column: 4, rank: 2))
    }
}
