//  PolyRiffEditTests.swift — POLY RIFF ferry (2026-10-29), slice 2: how a touch edits the POLY grid (create, stretch either way, shorten, remove, clip) and where its cells are. Pure functions (PolyRiffEdit.swift).

import XCTest

final class PolyRiffEditTests: XCTestCase {
    private func n(_ c: Int, _ r: Int, _ l: Int = 1) -> EuclideousPolyNote { EuclideousPolyNote(col: c, rank: r, len: l) }
    private func shape(_ r: EuclideousPolyRiff) -> [[Int]] { r.normalized.notes.map { [$0.col, $0.rank, $0.len] } }

    // MARK: a touch on an empty cell

    func testATouchOnAnEmptyCellMakesALengthOneNoteAndLiftingKeepsIt() {
        let b = EuclideousPolyDrag.begin(EuclideousPolyRiff(), col: 4, rank: 3)
        XCTAssertEqual(shape(b.riff), [[4, 3, 1]]); XCTAssertFalse(b.drag.existing)
        XCTAssertEqual(shape(b.drag.end(b.riff)), [[4, 3, 1]], "a tap on an empty cell leaves the note")
    }
    func testDraggingRightStretchesTheNewNoteAndDraggingLeftStretchesItTheOtherWay() {
        var (d, r) = EuclideousPolyDrag.begin(EuclideousPolyRiff(), col: 4, rank: 3)
        (d, r) = d.update(r, fingerCol: 7); XCTAssertEqual(shape(r), [[4, 3, 4]], "right: columns 4…7")
        (d, r) = d.update(r, fingerCol: 5); XCTAssertEqual(shape(r), [[4, 3, 2]], "back towards the start: shorter")
        (d, r) = d.update(r, fingerCol: 1); XCTAssertEqual(shape(r), [[1, 3, 4]], "left past the touched column: the note now ENDS on it, columns 1…4")
        XCTAssertTrue(d.moved); XCTAssertEqual(shape(d.end(r)), [[1, 3, 4]], "a drag keeps the note")
    }
    func testTheRankNeverChangesDuringADrag() {
        var (d, r) = EuclideousPolyDrag.begin(EuclideousPolyRiff(), col: 2, rank: 6)
        (d, r) = d.update(r, fingerCol: 6)
        XCTAssertEqual(Set(shape(r).map { $0[1] }), [6])
    }
    func testAStretchStopsAtTheGridsEdgesAndAtTheNextNoteOnTheSameRank() {
        var (d, r) = EuclideousPolyDrag.begin(EuclideousPolyRiff(notes: [n(8, 3, 2)]), col: 4, rank: 3)
        (d, r) = d.update(r, fingerCol: 15); XCTAssertEqual(shape(r).first { $0[0] == 4 }, [4, 3, 4], "stops at column 7, the cell before the note on column 8")
        (d, r) = d.update(r, fingerCol: 0);  XCTAssertEqual(shape(r).first { $0[0] == 0 }, [0, 3, 5], "to the left edge")
        var (e, q) = EuclideousPolyDrag.begin(EuclideousPolyRiff(notes: [n(1, 5, 2)]), col: 12, rank: 5)
        (e, q) = e.update(q, fingerCol: 0); XCTAssertEqual(shape(q).first { $0[0] != 1 }, [3, 5, 10], "stops after the note on columns 1–2")
        var (f, p) = EuclideousPolyDrag.begin(EuclideousPolyRiff(), col: 14, rank: 1)
        (f, p) = f.update(p, fingerCol: 40); XCTAssertEqual(shape(p), [[14, 1, 2]], "the finger past the last column clamps to 15")
        _ = (d, e, f)
    }
    func testNotesAtOtherRanksNeverGetInTheWay() {
        var (d, r) = EuclideousPolyDrag.begin(EuclideousPolyRiff(notes: [n(5, 2, 3), n(6, 4, 1)]), col: 3, rank: 3)
        (d, r) = d.update(r, fingerCol: 9)
        XCTAssertEqual(shape(r), [[3, 3, 7], [5, 2, 3], [6, 4, 1]].sorted { ($0[0], $0[1]) < ($1[0], $1[1]) }, "a note may overlap notes at other ranks — that is POLY")
        _ = d
    }

    // MARK: a touch on a note

    func testATouchOnANoteThatDoesNotMoveRemovesIt() {
        let riff = EuclideousPolyRiff(notes: [n(2, 3, 4), n(9, 1)])
        for col in 2...5 {   // its head or any tail cell
            let b = EuclideousPolyDrag.begin(riff, col: col, rank: 3)
            XCTAssertTrue(b.drag.existing); XCTAssertEqual(shape(b.riff), shape(riff), "touch-down changes nothing yet")
            XCTAssertEqual(shape(b.drag.end(b.riff)), [[9, 1, 1]], "lift without moving: the note is gone (column \(col))")
        }
    }
    func testDraggingFromANoteKeepsTheFarEndAndMovesTheNearOne() {
        let riff = EuclideousPolyRiff(notes: [n(2, 3, 4)])                       // columns 2…5
        // touched on its tail end: the head stays, the tail follows the finger
        var (d, r) = EuclideousPolyDrag.begin(riff, col: 5, rank: 3)
        (d, r) = d.update(r, fingerCol: 9); XCTAssertEqual(shape(r), [[2, 3, 8]], "stretched right")
        (d, r) = d.update(r, fingerCol: 3); XCTAssertEqual(shape(r), [[2, 3, 2]], "shortened")
        (d, r) = d.update(r, fingerCol: 0); XCTAssertEqual(shape(r), [[0, 3, 3]], "past the fixed end it flips: columns 0…2")
        XCTAssertEqual(shape(d.end(r)), [[0, 3, 3]], "moved, so it stays")
        // touched near its head: the tail stays
        var (e, q) = EuclideousPolyDrag.begin(riff, col: 2, rank: 3)
        (e, q) = e.update(q, fingerCol: 0); XCTAssertEqual(shape(q), [[0, 3, 6]], "the head dragged left: columns 0…5")
        (e, q) = e.update(q, fingerCol: 4); XCTAssertEqual(shape(q), [[4, 3, 2]], "the head dragged right: columns 4…5")
        // touched in the exact middle of an odd-length note (columns 2…4, touched on 3): the head stays and the tail follows
        var (f, p) = EuclideousPolyDrag.begin(EuclideousPolyRiff(notes: [n(2, 3, 3)]), col: 3, rank: 3)
        (f, p) = f.update(p, fingerCol: 8); XCTAssertEqual(shape(p), [[2, 3, 7]])
        _ = (d, e, f)
    }
    func testAnEditNeverLeavesTwoNotesOverlappingOnARank() {
        var rng = PolyRiffRNG(0xED17)
        for _ in 0..<400 {
            var riff = EuclideousPolyRiff()
            for _ in 0..<(Int(rng.next() % 8) + 1) { riff = riff.toggled(col: Int(rng.next() % 16), rank: Int(rng.next() % 8) + 1) }
            let col = Int(rng.next() % 16), rank = Int(rng.next() % 8) + 1
            var (d, r) = EuclideousPolyDrag.begin(riff, col: col, rank: rank)
            for _ in 0..<6 { (d, r) = d.update(r, fingerCol: Int(rng.next() % 16)); XCTAssertEqual(r, r.normalized, "already normalised after every move") }
            r = d.end(r)
            for rk in 1...8 {
                let ns = r.normalized.notes.filter { $0.rank == rk }.sorted { $0.col < $1.col }
                for (a, b) in zip(ns, ns.dropFirst()) { XCTAssertLessThan(a.col + a.len, b.col + 1, "rank \(rk): \(a) runs into \(b)") }
                for x in ns { XCTAssertTrue(x.col >= 0 && x.col + x.len <= 16 && x.len >= 1) }
            }
        }
    }
    func testToggledIsATapWithNoDrag() {
        var r = EuclideousPolyRiff()
        r = r.toggled(col: 6, rank: 4); XCTAssertEqual(shape(r), [[6, 4, 1]])
        r = r.toggled(col: 6, rank: 4); XCTAssertTrue(r.isEmpty)
        r = EuclideousPolyRiff(notes: [n(2, 4, 3)]).toggled(col: 3, rank: 4); XCTAssertTrue(r.isEmpty, "a tail cell removes the whole note")
    }

    // MARK: VoiceOver's longer / shorter

    func testResizeByOneLengthensAndShortensFromTheTail() {
        let riff = EuclideousPolyRiff(notes: [n(2, 3, 3), n(9, 3, 1), n(4, 6, 1)])
        XCTAssertEqual(shape(riff.resized(noteAt: 2, rank: 3, by: 1)), [[2, 3, 4], [4, 6, 1], [9, 3, 1]].sorted { ($0[0], $0[1]) < ($1[0], $1[1]) })
        XCTAssertEqual(shape(riff.resized(noteAt: 3, rank: 3, by: -1)).first { $0[1] == 3 }, [2, 3, 2], "from any cell the note covers")
        XCTAssertEqual(shape(riff.resized(noteAt: 2, rank: 3, by: -9)).first { $0[0] == 2 && $0[1] == 3 }, [2, 3, 1], "never under one column")
        XCTAssertEqual(shape(riff.resized(noteAt: 2, rank: 3, by: 30)).first { $0[0] == 2 && $0[1] == 3 }, [2, 3, 7], "stops before the next note on its rank (column 9)")
        XCTAssertEqual(shape(EuclideousPolyRiff(notes: [n(14, 1, 2)]).resized(noteAt: 14, rank: 1, by: 5)), [[14, 1, 2]], "and at the grid's edge")
        XCTAssertEqual(shape(riff.resized(noteAt: 12, rank: 5, by: 1)), shape(riff), "an empty cell: nothing changes")
    }

    // MARK: what the arrows and the walk mirror read

    func testTopRanksAndTheArrowSeat() {
        let r = EuclideousPolyRiff(notes: [n(0, 2, 3), n(0, 5), n(4, 1), n(15, 8)])
        XCTAssertEqual(r.topRanks, [5, 0, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 8], "the highest rank STARTING on each column")
        XCTAssertEqual(r.seatRank(col: 0), 5); XCTAssertEqual(r.seatRank(col: 1), 2, "a rest column shows the note still sounding through it"); XCTAssertEqual(r.seatRank(col: 3), 0)
        XCTAssertEqual(r.seatRank(col: 4), 1)
    }

    // MARK: the grid's frames

    func testThePolyGridFramesAtBothReferences() {
        for (box, cellW) in [(CGSize(width: 380.67, height: 319), 18.79), (CGSize(width: 387, height: 319.67), 19.19)] {
            let l = euclideousPolyPanelLayout(box: box), m = euclideousRiffPanelLayout(box: box)
            XCTAssertEqual(l.columns, 16); XCTAssertEqual(l.colGap, 2); XCTAssertEqual(l.cellW, cellW, accuracy: 0.01)
            XCTAssertEqual(l.labelW, m.labelW, "the note-name column is the MONO one"); XCTAssertEqual(l.tabRowH, m.tabRowH)
            XCTAssertEqual(l.cellH, m.rowH, accuracy: 1e-9, "cells as tall as their rows (MONO caps a cell's height at its width)")
            XCTAssertEqual(l.gridSize.width, l.cellW * 16 + 30, accuracy: 1e-9)
            XCTAssertEqual(l.columnLeft(15) + l.cellW, l.columnLeft(0) + l.gridSize.width, accuracy: 1e-9, "column 16 ends where the grid does")
            XCTAssertLessThanOrEqual(l.columnLeft(0) + l.gridSize.width, box.width - EuclideousRiffPanelMetrics.padding + 1e-9, "inside the panel's padding")
            XCTAssertEqual(l.gridSize.height, l.cellH * 8 + EuclideousRiffPanelMetrics.rowGap * 7, accuracy: 1e-9); XCTAssertEqual(l.gridTop, m.gridTop, "the same top")
            XCTAssertEqual(l.railTop(0), l.gridTop + l.gridSize.height + EuclideousRiffPanelMetrics.gridToRails, accuracy: 1e-9)
        }
        // the MONO layout is the one it always was
        let m = euclideousRiffPanelLayout(box: CGSize(width: 380.67, height: 319))
        XCTAssertEqual(m.columns, 8); XCTAssertEqual(m.colGap, 4); XCTAssertEqual(m.gridSize.width, m.cellW * 8 + 28, accuracy: 1e-9)
    }
    func testATouchLandsOnTheCellUnderIt() {
        let l = euclideousPolyPanelLayout(box: CGSize(width: 380.67, height: 319))
        for col in [0, 7, 15] { for rank in [1, 4, 8] {
            let f = l.cellFrame(column: col, rank: rank).offsetBy(dx: -l.columnLeft(0), dy: -l.rowTop(0))
            let hit = euclideousPolyCellAt(CGPoint(x: f.midX, y: f.midY), layout: l)
            XCTAssertTrue(hit.col == col && hit.rank == rank, "\(col),\(rank) → \(hit)")
        } }
        let off = euclideousPolyCellAt(CGPoint(x: -50, y: 9999), layout: l); XCTAssertTrue(off.col == 0 && off.rank == 1, "outside clamps to the grid")
        let off2 = euclideousPolyCellAt(CGPoint(x: 9999, y: -5), layout: l); XCTAssertTrue(off2.col == 15 && off2.rank == 8)
    }
}
