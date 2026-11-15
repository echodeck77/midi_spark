//  PlayAsRowsAmendment3Tests.swift — PLAY AS ROWS, AMENDMENT 3 (2026-11-15): the RANKS pop-up lights/roles ranks (§C2),
//  the grey rank bar's shape shows the role (§C3), and WHEN RIFF is two independent flags (§C4). §C5 tests (pure, macOS).

import XCTest

final class PlayAsRowsAmendment3Tests: XCTestCase {

    private func unlit(_ l: inout EuclidLine, _ rank: Int) {
        if l.litOrderResolved.contains(rank - 1) { euclideousToggleLitPosition(&l, position: rank - 1) }
    }

    // §C5 test 1 — a tap on an unlit rank's DOUBLE lights it with role DOUBLE, addedOrder gains it at the END; a tap on the selected cell turns it off and keeps the role; both are reversible (one undo step on the page).
    func testPopupTapLightsSetsRoleAndTogglesOff() {
        var l = EuclidLine(noteSel: .all)
        unlit(&l, 5); unlit(&l, 3)                                   // rank 5 then rank 3 are off
        euclideousToggleLitPosition(&l, position: 4)                // light rank 5 first, so the order ends with it
        XCTAssertEqual(l.litOrderResolved.array.last, 4)
        euclideousRanksPopupCellTap(&l, rank: 3, role: .double)     // §C2.3 tap DOUBLE on unlit rank 3
        XCTAssertTrue(l.litOrderResolved.contains(2), "the rank lights")
        XCTAssertEqual(l.notesRankRole(3), .double, "with the chosen role")
        XCTAssertEqual(l.litOrderResolved.array.last, 2, "addedOrder gains it at the end")
        euclideousRanksPopupCellTap(&l, rank: 3, role: .double)     // §C2.5 tap the selected cell
        XCTAssertFalse(l.litOrderResolved.contains(2), "turns the rank off")
        XCTAssertEqual(l.notesRankRole(3), .double, "its role is kept")
    }

    // §C5 test 2 — PEDAL on an unlit rank lights it, makes it the pedal and returns the old pedal to ONCE, in one call.
    func testPopupPedalOnUnlitMovesThePedal() {
        var l = EuclidLine(noteSel: .all)
        l.setNotesRankRole(1, .pedal)                               // rank 1 is the pedal
        unlit(&l, 6)
        euclideousRanksPopupCellTap(&l, rank: 6, role: .pedal)      // §C2.6
        XCTAssertTrue(l.litOrderResolved.contains(5), "rank 6 lights")
        XCTAssertEqual(l.notesRankRole(6), .pedal, "rank 6 is the pedal")
        XCTAssertEqual(l.notesRankRole(1), .once, "the old pedal returns to ONCE")
    }

    // §C5 test 3 — the pop-up and a STACK grid tap write the SAME store, through `euclideousToggleLitPosition`.
    func testPopupAndGridShareTheStore() {
        var a = EuclidLine(noteSel: .all), b = EuclidLine(noteSel: .all)
        unlit(&a, 4); unlit(&b, 4)
        euclideousRanksPopupCellTap(&a, rank: 4, role: .once)       // pop-up tap (ONCE keeps the default role)
        euclideousToggleLitPosition(&b, position: 3)               // the grid/tile toggle
        XCTAssertEqual(a.litOrderResolved.array, b.litOrderResolved.array, "both light position 3 the same way")
    }

    // §C5 test 4 — the rank bar's shape per role (width 100); an unlit tile draws the ONCE shape whatever its role.
    func testRankBarShape() {
        func eq(_ got: [EuclideousRankBarSeg], _ want: [(Double, Double)], _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(got.count, want.count, msg, file: file, line: line)
            for (g, w) in zip(got, want) { XCTAssertEqual(g.x, w.0, accuracy: 1e-6, msg, file: file, line: line); XCTAssertEqual(g.w, w.1, accuracy: 1e-6, msg, file: file, line: line) }
        }
        func segs(_ role: EuclideousRankRole, lit: Bool) -> [EuclideousRankBarSeg] { euclideousRankBarSegments(role: role, lit: lit, width: 100) }
        eq(segs(.once, lit: true), [(30, 40)], "ONCE: one 40% bar centred")
        eq(segs(.pedal, lit: true), [(15, 70)], "PEDAL: one 70% bar centred")
        eq(segs(.double, lit: true), [(31.25, 18), (50.75, 18)], "DOUBLE: two 18% bars 1.5 apart, centred")
        eq(segs(.returns, lit: true), [(30, 14), (56, 14)], "RETURN: two 14% bars 12%-of-width apart, centred")
        eq(segs(.double, lit: false), [(30, 40)], "an unlit tile draws ONCE whatever its role (§C3.2)")
        eq(segs(.pedal, lit: false), [(30, 40)], "unlit PEDAL draws ONCE")
    }

    // §C5 test 5 — WHEN RIFF is two independent flags; each resolver reads its own bit.
    func testWhenIsTwoIndependentFlags() {
        var l = EuclidLine()
        l.notesWhen = 0b01; XCTAssertTrue(l.notesPlaysResolved); XCTAssertFalse(l.notesRestsResolved)
        l.notesWhen = 0b10; XCTAssertFalse(l.notesPlaysResolved); XCTAssertTrue(l.notesRestsResolved)
        l.notesWhen = 0b11; XCTAssertTrue(l.notesPlaysResolved); XCTAssertTrue(l.notesRestsResolved)
    }
}
