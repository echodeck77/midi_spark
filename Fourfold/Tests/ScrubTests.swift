//  ScrubTests.swift — Scrub ferry (2026-11-16) §11: the pure ribbon-mapping + hit-source functions (§7). The engine
//  override, audition and golden byte-identity are in the Router/golden tests (slice 3+).

import XCTest
import CoreGraphics

final class ScrubTests: XCTestCase {

    // §11.1 — ribbon mapping in both orientations: a cell's centre gives its index; a gap gives the nearer; past an end clamps.
    func testRibbonMapping() {
        for box in [CGSize(width: 380.67, height: 301), CGSize(width: 387, height: 301.67)] {
            let L = euclideousRiffPanelLayout(box: box)
            XCTAssertEqual(euclideousScrubColumn(x: L.columnLeft(2) + L.cellW / 2, layout: L), 3, "column 3's centre")
            XCTAssertEqual(euclideousScrubColumn(x: L.columnLeft(3) - 0.5, layout: L), 4, "gap between 3 and 4, nearer 4")
            XCTAssertEqual(euclideousScrubColumn(x: L.columnLeft(2) + L.cellW + 0.5, layout: L), 3, "gap between 3 and 4, nearer 3")
            XCTAssertEqual(euclideousScrubColumn(x: L.columnLeft(0) - 20, layout: L), 1, "left of column 1 clamps to 1")
            XCTAssertEqual(euclideousScrubColumn(x: L.columnLeft(7) + L.cellW + 50, layout: L), 8, "past column 8 clamps to 8")
            XCTAssertEqual(euclideousScrubRiffRank(y: L.rowTop(0) + L.cellH / 2, layout: L), 8, "row 8 (top) gives rank 8")
            XCTAssertEqual(euclideousScrubRiffRank(y: L.rowTop(3) + L.cellH / 2, layout: L), 5, "rank 5")
            XCTAssertEqual(euclideousScrubRiffRank(y: L.rowTop(7) + L.cellH / 2, layout: L), 1, "row 1 (bottom) gives rank 1")
            XCTAssertEqual(euclideousScrubRiffRank(y: L.rowTop(7) + L.cellH + 20, layout: L), 1, "below row 1 clamps to 1")
        }
    }

    // §2.3 — the STACK axis ribbon maps y → rank 8…1 over the eight axis cells (no TOP rows).
    func testStackRibbonMapping() {
        for box in [CGSize(width: 380.67, height: 301), CGSize(width: 387, height: 301.67)] {
            let L = euclideousStackGridLayout(box: box)
            XCTAssertEqual(euclideousScrubStackRank(y: L.axis(0).midY, layout: L), 8, "axis row 0 (top) = rank 8")
            XCTAssertEqual(euclideousScrubStackRank(y: L.axis(7).midY, layout: L), 1, "axis row 7 (bottom) = rank 1")
            XCTAssertEqual(euclideousScrubStackRank(y: L.axis(0).minY - 20, layout: L), 8, "above clamps to 8")
            XCTAssertEqual(euclideousScrubStackRank(y: L.axis(7).maxY + 20, layout: L), 1, "below clamps to 1")
            XCTAssertEqual(euclideousScrubStackRank(y: L.axis(3).midY, layout: L), 5, "row 3 = rank 5")
        }
    }

    // §11.2 (pure part) — no hold: riffHitSource returns the natural column + its written rank, unchanged, for the walk's own columns.
    func testRiffHitSourceNoHoldIsIdentity() {
        let ranks = [3, 0, 5, 2, 7, 0, 1, 4]   // a sample riff (0 = rest)
        for ord in Int64(0)..<64 {
            let col = euclideousRiffColumn(ordinal: ord, every: 1, direction: .forward, length: 8, stride: 1, shift: 0, seed: 0, columns: 8) + 1   // 1-based
            let s = euclideousRiffHitSource(naturalColumn: col, rawRankAtColumn: { ranks[$0 - 1] }, columnHold: nil, rankHold: nil)
            XCTAssertEqual(s.column, col)
            XCTAssertEqual(s.rank, ranks[col - 1])
        }
    }

    // §11.3 — a column hold reads the held column's written rank; without it, the natural column.
    func testColumnHoldReadsTheHeldColumn() {
        let ranks = [3, 0, 5, 2, 7, 0, 1, 4]
        let s = euclideousRiffHitSource(naturalColumn: 7, rawRankAtColumn: { ranks[$0 - 1] }, columnHold: 5, rankHold: nil)
        XCTAssertEqual(s.column, 5); XCTAssertEqual(s.rank, 7, "column 5's written rank")
        let none = euclideousRiffHitSource(naturalColumn: 7, rawRankAtColumn: { ranks[$0 - 1] }, columnHold: nil, rankHold: nil)
        XCTAssertEqual(none.column, 7); XCTAssertEqual(none.rank, 1, "no hold ⇒ natural column 7")
    }

    // §11.4 — a column hold on a rest column is a rest, whatever on-rest treatment the lane has (the engine skips on-rest under any hold).
    func testColumnHoldOnRestIsRest() {
        let ranks = [3, 0, 5, 2, 7, 0, 1, 4]
        let s = euclideousRiffHitSource(naturalColumn: 3, rawRankAtColumn: { ranks[$0 - 1] }, columnHold: 2, rankHold: nil)   // column 2 is a rest
        XCTAssertEqual(s.rank, 0, "rest column ⇒ no riff note-on")
    }

    // §11.5 / §11.6 — a rank hold uses rank r on every hit (incl. a rest column), in the natural column; with both holds the rank wins and the display column is the held column.
    func testRankHoldAndBothHolds() {
        let ranks = [3, 0, 5, 2, 7, 0, 1, 4]
        let r = euclideousRiffHitSource(naturalColumn: 2, rawRankAtColumn: { ranks[$0 - 1] }, columnHold: nil, rankHold: 8)   // natural column 2 is a rest
        XCTAssertEqual(r.rank, 8, "rank 8 plays even on a rest column"); XCTAssertEqual(r.column, 2, "in the natural column")
        let both = euclideousRiffHitSource(naturalColumn: 7, rawRankAtColumn: { ranks[$0 - 1] }, columnHold: 3, rankHold: 8)
        XCTAssertEqual(both.rank, 8, "the rank wins"); XCTAssertEqual(both.column, 3, "the column hold still places the arrow")
    }

    // §11.7 (pure part) — a stack hold collapses to [r]; a pool with no note at r is a rest; nil hold ⇒ the natural ranks.
    func testStackHitRanks() {
        XCTAssertEqual(euclideousStackHitRanks(natural: [1, 2, 5], poolHasRank: { _ in true }, stackHold: 3), [3], "collapse to [r] whether or not selected")
        XCTAssertEqual(euclideousStackHitRanks(natural: [1, 2, 5], poolHasRank: { $0 != 3 }, stackHold: 3), [], "no note at r ⇒ rest")
        XCTAssertEqual(euclideousStackHitRanks(natural: [1, 2, 5], poolHasRank: { _ in true }, stackHold: nil), [1, 2, 5], "no hold ⇒ the natural ranks")
    }
}
