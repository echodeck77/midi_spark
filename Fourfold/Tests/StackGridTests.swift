//  StackGridTests.swift — STACK GRID ferry (2026-11-08): the riff panel's STACK tab. The pure side: the rows and their order, which stored position each cell stands for, that a STACK toggle writes EXACTLY what the NOTES tab's key writes (and a NOTES
//  toggle shows on the cell — there is one store), the note each cell names, the frames, the axis chips and the tab strip's new label.

import XCTest

final class StackGridTests: XCTestCase {

    private func pool(_ notes: [UInt8]) -> EuclideousLanePoolNotes {
        var p = EuclideousLanePoolNotes()
        let s = notes.sorted()
        p.count = s.count; p.notes = s
        p.top = s.last ?? 0; p.top2 = s.count >= 2 ? s[s.count - 2] : 0
        return p
    }
    /// A lane with NOTHING selected (a bare `EuclidLine` derives its lit notes from the legacy fields, which light every rank).
    private func line() -> EuclidLine { var l = EuclidLine(noteSel: .all); l.notesOn = false; l.setLitOrder(EuclideousLitOrder()); return l }

    // MARK: the rows

    func testTheRowsAreEightDownToOne() {   // TOP / TOP−1 / TOP−2 removed 2026-11-09 (Paul) — the stack shows only ranks
        XCTAssertEqual(euclideousStackGridRows.map { $0.label }, ["8", "7", "6", "5", "4", "3", "2", "1"])
        XCTAssertEqual(euclideousStackGridRows.count, 8)
        XCTAssertEqual(euclideousStackGridRows.map { $0.spoken }.first, "rank 8"); XCTAssertEqual(euclideousStackGridRows.last?.spoken, "rank 1")
    }

    // MARK: the position a cell stands for

    func testARankRowIsItsRankAndTopIsTheTopKey() {
        for n in [0, 1, 3, 8, 12] {
            for r in 1...8 { XCTAssertEqual(EuclideousStackRow.rank(r).position(poolCount: n), r - 1, "rank \(r), pool \(n)") }
            XCTAssertEqual(EuclideousStackRow.top.position(poolCount: n), EuclideousLitOrder.topPosition, "TOP is the NOTES tab's TOP key at any pool size")
        }
        XCTAssertEqual(EuclideousLitOrder.topPosition, 9)
    }
    func testTopMinusRowsAreThePoolRanksBelowTheTop() {
        XCTAssertEqual(EuclideousStackRow.topMinus1.position(poolCount: 5), 3, "rank 4 = position 3"); XCTAssertEqual(EuclideousStackRow.topMinus2.position(poolCount: 5), 2, "rank 3 = position 2")
        XCTAssertEqual(EuclideousStackRow.topMinus1.position(poolCount: 2), 0); XCTAssertEqual(EuclideousStackRow.topMinus2.position(poolCount: 3), 0)
        XCTAssertNil(EuclideousStackRow.topMinus1.position(poolCount: 1), "no second note"); XCTAssertNil(EuclideousStackRow.topMinus2.position(poolCount: 2), "no third note")
        XCTAssertNil(EuclideousStackRow.topMinus1.position(poolCount: 0)); XCTAssertNil(EuclideousStackRow.topMinus2.position(poolCount: 0))
        XCTAssertEqual(EuclideousStackRow.topMinus1.position(poolCount: 9), 7, "rank 8 is the last the selection holds"); XCTAssertNil(EuclideousStackRow.topMinus2.position(poolCount: 11), "rank 9 is beyond the selection")
        XCTAssertNil(EuclideousStackRow.topMinus1.position(poolCount: 10))
    }

    // MARK: the required test — a STACK toggle writes the same value NOTES reads

    /// For every row and several pool sizes: toggling the cell leaves the lane exactly as the NOTES tab's own action on the same position does, the NOTES reads (the lit order, the rank mask, TOP, the layer's on-ness) all see it, and the cell is on exactly
    /// when the NOTES key is lit. A NOTES toggle then shows on the cell, and a second STACK toggle takes it away again — there is one store.
    func testAStackToggleWritesTheSameValueTheNotesTabReads() {
        for n in [0, 1, 2, 3, 5, 8, 9] {
            for row in euclideousStackGridRows {
                var viaStack = line(), viaNotes = line()
                let p = row.position(poolCount: n)
                let wrote = euclideousStackCellToggle(&viaStack, row: row, poolCount: n)
                XCTAssertEqual(wrote, p != nil, "\(row.label), pool \(n)")
                guard let p else { XCTAssertEqual(viaStack, viaNotes, "a cell with no position writes nothing"); continue }
                euclideousToggleLitPosition(&viaNotes, position: p)   // the NOTES key's own action
                XCTAssertEqual(viaStack, viaNotes, "\(row.label), pool \(n): the same stored value")
                XCTAssertTrue(viaStack.litOrderResolved.contains(p), "NOTES reads the lit order")
                XCTAssertEqual(viaStack.litOrderResolved.array, viaNotes.litOrderResolved.array)
                if p < 8 { XCTAssertNotEqual(viaStack.litNotesResolved & (1 << UInt8(p)), 0, "the rank mask the NOTES keys light from") } else { XCTAssertTrue(viaStack.topLitResolved, "the TOP key") }
                XCTAssertTrue(viaStack.notesOnResolved, "a tap on an off layer also turns it on, as a NOTES key does")
                XCTAssertTrue(euclideousStackCellIsOn(viaStack, row: row, poolCount: n), "the cell is on")
                XCTAssertFalse(euclideousStackCellIsOn(line(), row: row, poolCount: n), "…and was off")
                // NOTES turns it off → the cell shows off; STACK turns it on again → NOTES reads it
                euclideousToggleLitPosition(&viaStack, position: p)
                XCTAssertFalse(euclideousStackCellIsOn(viaStack, row: row, poolCount: n), "a NOTES toggle shows on the cell")
                euclideousStackCellToggle(&viaStack, row: row, poolCount: n)
                XCTAssertTrue(viaStack.litOrderResolved.contains(p))
            }
        }
    }
    /// Cells of different rows and lanes keep their own positions: lighting rank 3 on one lane leaves every other cell of that lane (but a TOP row aliasing the same rank) as it was.
    func testCellsShareOnlyWhatTheyShareInTheStore() {
        var l = line()
        euclideousStackCellToggle(&l, row: .rank(3), poolCount: 5)
        XCTAssertTrue(euclideousStackCellIsOn(l, row: .rank(3), poolCount: 5))
        XCTAssertFalse(euclideousStackCellIsOn(l, row: .rank(4), poolCount: 5)); XCTAssertFalse(euclideousStackCellIsOn(l, row: .top, poolCount: 5), "TOP is its own key")
        XCTAssertTrue(euclideousStackCellIsOn(l, row: .topMinus2, poolCount: 5), "with five notes held TOP−2 IS rank 3 — the same stored position")
        XCTAssertFalse(euclideousStackCellIsOn(l, row: .topMinus2, poolCount: 6), "with six held, rank 3 is TOP−3: no row")
        var other = line()
        euclideousStackCellToggle(&other, row: .top, poolCount: 5)
        XCTAssertTrue(other.topLitResolved); XCTAssertEqual(other.litNotesResolved, 0)
    }

    // MARK: the note each cell names

    func testEachCellNamesItsLanesNote() {
        let five = pool([48, 52, 55, 60, 64])
        XCTAssertEqual(EuclideousStackRow.top.note(pool: five), 64); XCTAssertEqual(EuclideousStackRow.topMinus1.note(pool: five), 60); XCTAssertEqual(EuclideousStackRow.topMinus2.note(pool: five), 55)
        XCTAssertEqual(EuclideousStackRow.rank(1).note(pool: five), 48); XCTAssertEqual(EuclideousStackRow.rank(5).note(pool: five), 64)
        XCTAssertEqual(EuclideousStackRow.rank(6).note(pool: five), 60, "past the received notes a rank is an octave copy of the pool: 48 + 12")
        XCTAssertEqual(EuclideousStackRow.rank(8).note(pool: five), 67)
        let one = pool([60])
        XCTAssertEqual(EuclideousStackRow.top.note(pool: one), 60); XCTAssertNil(EuclideousStackRow.topMinus1.note(pool: one)); XCTAssertNil(EuclideousStackRow.topMinus2.note(pool: one))
        XCTAssertEqual(EuclideousStackRow.rank(8).note(pool: one), 60 + 84, "one note repeats up the octaves")
        let none = pool([])
        for row in euclideousStackGridRows { XCTAssertNil(row.note(pool: none), row.label) }
        // each lane has its own pool and so its own names
        XCTAssertNotEqual(EuclideousStackRow.top.note(pool: five), EuclideousStackRow.top.note(pool: one))
    }

    // MARK: the frames

    func testTheLayoutHasFourColumnsEightRowsAndTheRiffGridsAxis() {   // 8 rows since TOP/TOP−1/TOP−2 were removed (2026-11-09)
        for box in [CGSize(width: 380.67, height: 301), CGSize(width: 387, height: 301.67), CGSize(width: 439.33, height: 450), CGSize(width: 284, height: 232.5)] {
            let L = euclideousStackGridLayout(box: box), base = euclideousRiffPanelLayout(box: box)
            XCTAssertEqual(L.rowCount, 8)
            XCTAssertEqual(L.labelW, base.labelW, "the axis is the riff grid's label column"); XCTAssertEqual(L.axis(0).minX, 8)
            XCTAssertEqual(L.header(0).minY, 8 + base.tabRowH + 6, accuracy: 1e-9, "the headers start where the riff grid does")
            for r in 0..<8 {
                XCTAssertEqual(L.axis(r).height, L.rowH, accuracy: 1e-9)
                for lane in 0..<4 {
                    let c = L.cell(row: r, lane: lane)
                    XCTAssertEqual(c.minY, L.axis(r).minY, accuracy: 1e-9); XCTAssertEqual(c.width, L.colW, accuracy: 1e-9)
                    XCTAssertEqual(c.minX, L.header(lane).minX, accuracy: 1e-9, "a column sits under its header")
                    if lane > 0 { XCTAssertEqual(c.minX - L.cell(row: r, lane: lane - 1).maxX, L.colGap, accuracy: 1e-9) }
                }
            }
            XCTAssertEqual(L.cell(row: 0, lane: 0).minX - L.axis(0).maxX, 4, accuracy: 1e-9, "the axis gap is the riff grid's")
            XCTAssertEqual(L.cell(row: 7, lane: 3).maxX, box.width - 8, accuracy: 1e-9, "the last column ends on the panel's padding")
            XCTAssertEqual(L.cell(row: 7, lane: 0).maxY, box.height - 8, accuracy: 1e-9, "the last row ends on the panel's padding")
        }
        let ref = euclideousStackGridLayout(box: CGSize(width: 380.67, height: 301))
        print("STACKGRID rowH at the landscape reference \(ref.rowH) colW \(ref.colW) font \(ref.cellFontSize)")
    }
    func testRowHeightsAtEveryPageLayout() {
        let sizes: [(String, CGSize)] = [("1376×1032", CGSize(width: 1376, height: 1032)), ("1366×1024", CGSize(width: 1366, height: 1024)), ("1194×834", CGSize(width: 1194, height: 834)), ("1190×726 (ref)", CGSize(width: 1190, height: 726)),
                                         ("1133×744 (mini)", CGSize(width: 1133, height: 744)), ("1113×683", CGSize(width: 1113, height: 683)), ("1113×636", CGSize(width: 1113, height: 636)), ("1024×768", CGSize(width: 1024, height: 768)),
                                         ("900×600 window", CGSize(width: 900, height: 600)), ("834×1210", CGSize(width: 834, height: 1210)), ("814×1102 (ref)", CGSize(width: 814, height: 1102)), ("768×1024", CGSize(width: 768, height: 1024)),
                                         ("744×1133 (mini)", CGSize(width: 744, height: 1133)), ("700×900 window", CGSize(width: 700, height: 900))]
        var lines: [String] = []
        for (name, size) in sizes {
            let box = euclideousPageLayout(size: size).box
            let L = euclideousStackGridLayout(box: box)
            XCTAssertGreaterThan(L.rowH, 0); XCTAssertGreaterThan(L.colW, 0)
            lines.append("STACKGRID-LAYOUT \(name): panel \(String(format: "%.1f", Double(box.width)))×\(String(format: "%.1f", Double(box.height))) rowH \(String(format: "%.2f", Double(L.rowH))) colW \(String(format: "%.2f", Double(L.colW))) font \(L.cellFontSize)\(L.belowFloor ? " [under the 14 pt row floor]" : "")")
        }
        print(lines.joined(separator: "\n"))
    }

    // MARK: the axis, the header switch and the tab strip

    func testTheAxisUsesTheRankChipsOwnLooks() {
        for r in 1...8 {
            let s = euclideousStackAxisSpec(.rank(r))
            XCTAssertEqual(s.rank, r); XCTAssertEqual(s.name, String(r), "the rank number in the chip's label type"); XCTAssertTrue(s.empty); XCTAssertTrue(s.received); XCTAssertFalse(s.lit); XCTAssertEqual(s.topKind, 0)
        }
        XCTAssertEqual(euclideousStackAxisSpec(.top).topKind, 2, "TOP is the NOTES key's TOP box"); XCTAssertEqual(euclideousStackAxisSpec(.topMinus1).topKind, 3); XCTAssertEqual(euclideousStackAxisSpec(.topMinus2).topKind, 4)
        for row in [EuclideousStackRow.top, .topMinus1, .topMinus2] { XCTAssertEqual(euclideousStackAxisSpec(row).name, "", "the label alone, no second line") }
    }
    func testTheHeaderSwitchIsRiffThenStackAndOpensOnRiff() {
        XCTAssertEqual(EuclideousRiffPanelTab.allCases.map { $0.label }, ["RIFF", "STACK"]); XCTAssertEqual(EuclideousRiffPanelTab.opening, .riff)
        XCTAssertEqual(EuclideousRiffPanelTab.allCases.map { $0.spoken }, ["Riff", "Stack"])
    }
    func testTheNotesTabIsCalledStackInTheTabStrip() {
        XCTAssertEqual(EuclideousPageTab.notes.label, "STACK"); XCTAssertEqual(EuclideousPageTab.notes.spokenName, "Stack")
        XCTAssertEqual(euclideousPageTabOrder.map { $0.label }, ["INPUTS", "EUCLID", "RESETS", "RIFF", "STACK", "ANSWER", "MIX"], "the label changed, nothing else: same place, same tab")
        XCTAssertEqual(EuclideousPageTab.notes.front, .notes, "behaviour and content stay as they are")
    }
}
