//  PlayAsRolesTests.swift — PLAY AS ROWS, AMENDMENT 2 (2026-11-15) §B6: the role model (§B1) and, as step 3 lands, the role pass builder (§B2).

import XCTest

final class PlayAsRolesTests: XCTestCase {

    // §B6.4 — decode: the old count / second / third fields map to roles by §B1.3 (count 1 ⇒ ONCE; count 2/3 + AGAIN ⇒ DOUBLE; count 2/3 + LATER ⇒ RETURN; 3rd ignored; nothing ⇒ PEDAL never).
    func testRolesDeriveFromTheOldCountFieldsByB1_3() {
        var l = EuclidLine(noteSel: .all)
        l.setNotesRankCount(2, 3); l.setNotesRankSecond(2, .later)   // count 3 + LATER ⇒ RETURN
        l.setNotesRankCount(3, 2)                                    // count 2 + AGAIN (default) ⇒ DOUBLE
        l.setNotesRankCount(4, 2); l.setNotesRankSecond(4, .later)   // count 2 + LATER ⇒ RETURN
        l.setNotesRankCount(5, 1)                                    // count 1 ⇒ ONCE
        l.setNotesRankThird(2, .later)                               // the 3rd copy is ignored (still RETURN)
        XCTAssertNil(l.notesRankRoles, "the derive leaves the role field unset until the first role edit")
        XCTAssertEqual(l.notesRankRole(2), .returns)
        XCTAssertEqual(l.notesRankRole(3), .double)
        XCTAssertEqual(l.notesRankRole(4), .returns)
        XCTAssertEqual(l.notesRankRole(5), .once)
        XCTAssertEqual(l.notesRankRole(1), .once, "an untouched rank is ONCE")
        XCTAssertFalse((1...8).contains { l.notesRankRole($0) == .pedal }, "nothing decodes to PEDAL")
    }

    // §B6.3 — PEDAL is exclusive: setting it on a rank turns the previous PEDAL rank to ONCE, in the SAME setNotesRankRole call (so the page's one edit() is one undo step). A non-PEDAL edit never clears another rank.
    func testPedalIsExclusive() {
        var l = EuclidLine(noteSel: .all)
        l.setNotesRankRole(1, .pedal)
        XCTAssertEqual(l.notesRankRole(1), .pedal)
        l.setNotesRankRole(3, .pedal)                                // §B1.2: rank 1 → ONCE in the same call
        XCTAssertEqual(l.notesRankRole(1), .once)
        XCTAssertEqual(l.notesRankRole(3), .pedal)
        XCTAssertEqual((1...8).filter { l.notesRankRole($0) == .pedal }, [3], "at most one PEDAL per lane")
        // a DOUBLE / RETURN edit leaves the pedal alone
        l.setNotesRankRole(5, .double)
        XCTAssertEqual(l.notesRankRole(3), .pedal); XCTAssertEqual(l.notesRankRole(5), .double)
    }

    // §B1: a role edit seeds from the §B1.3-derived set, so another rank's derived role survives the first write.
    func testFirstRoleWriteKeepsTheOtherDerivedRoles() {
        var l = EuclidLine(noteSel: .all)
        l.setNotesRankCount(2, 2)                                    // rank 2 derives DOUBLE
        XCTAssertNil(l.notesRankRoles)
        l.setNotesRankRole(5, .pedal)                               // the first role write
        XCTAssertNotNil(l.notesRankRoles)
        XCTAssertEqual(l.notesRankRole(2), .double, "rank 2's derived DOUBLE survives the first role write")
        XCTAssertEqual(l.notesRankRole(5), .pedal)
    }

    // §B1.1 default + round-trip: a fresh lane is all ONCE and stores nil; a set role survives encode/decode.
    func testDefaultAndRoundTrip() throws {
        let fresh = EuclidLine(noteSel: .all)
        XCTAssertNil(fresh.notesRankRoles)
        for r in 1...8 { XCTAssertEqual(fresh.notesRankRole(r), .once) }
        var l = EuclidLine(noteSel: .all); l.setNotesRankRole(4, .returns); l.setNotesRankRole(1, .pedal)
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.notesRankRole(4), .returns); XCTAssertEqual(back.notesRankRole(1), .pedal)
    }
}
