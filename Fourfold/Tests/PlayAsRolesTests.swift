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

    // MARK: §B6.1-§B6.6 — the role PASS builder

    private func lit(_ ranks: [Int], added: [Int]? = nil) -> EuclideousLitOrder {
        var o = EuclideousLitOrder(); for r in (added ?? ranks) { o.append(r - 1) }; return o
    }
    private func roleWord(_ pairs: [Int: EuclideousRankRole]) -> UInt16 { var m: UInt16 = 0; for (r, role) in pairs { m |= UInt16(role.rawValue) << UInt16(2 * (r - 1)) }; return m }
    private func pass(_ litRanks: [Int], order: EuclideousOrderMode, roles: [Int: EuclideousRankRole] = [:], added: [Int]? = nil, bassOn: Bool = false) -> [Int] {
        let rip = euclideousRowsRanksInPlay(litOrder: lit(litRanks, added: added), bassOn: bassOn)
        return euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: order, roles: roleWord(roles), passIndex: 0, lane: 0, shiftStart: 0, driftOn: false, driftStep: 0).array
    }

    // §B6.1 — every §B2.10 worked example.
    func testPassBuilderB2_10Examples() {
        // lit 1,2,3 = A,B,C; ONCE unless named; ORDER UP unless named.
        XCTAssertEqual(pass([1, 2, 3], order: .up, roles: [2: .double]), [1, 2, 2, 3], "B DOUBLE ⇒ A B B C")
        XCTAssertEqual(pass([1, 2, 3], order: .up, roles: [2: .returns]), [1, 2, 3, 2], "B RETURN ⇒ A B C B")
        XCTAssertEqual(pass([1, 2, 3], order: .up, roles: [2: .pedal]), [2, 1, 2, 3], "B PEDAL ⇒ B A B C")
        XCTAssertEqual(pass([1, 2, 3], order: .down, roles: [2: .returns]), [3, 2, 1, 2], "DOWN, B RETURN ⇒ C B A B")
        XCTAssertEqual(pass([1, 2, 3], order: .up, roles: [1: .returns, 2: .returns]), [1, 2, 3, 1, 2], "A and B RETURN ⇒ A B C A B")
        XCTAssertEqual(pass([1, 2, 3], order: .up, roles: [3: .returns]), [1, 2, 3, 3], "C RETURN ⇒ A B C C")
        XCTAssertEqual(pass([1, 3, 5, 6], order: .up, roles: [1: .pedal, 5: .returns, 6: .double]), [1, 3, 1, 5, 1, 6, 6, 1, 5], "the broken pedal with a double + return")
        XCTAssertEqual(pass([1, 3, 5, 6], order: .up, roles: [1: .pedal]), [1, 3, 1, 5, 1, 6], "the broken pedal 1 3 1 5 1 6")
        XCTAssertEqual(pass([1, 2, 3, 4], order: .bounce), [1, 2, 3, 4, 3, 2], "BOUNCE, lit 1-4")
        XCTAssertEqual(pass([1, 3, 4, 5], order: .bounce, roles: [1: .pedal]), [1, 3, 1, 4, 1, 5, 1, 4], "BOUNCE with a pedal")
        XCTAssertEqual(pass([1, 3, 5], order: .up, roles: [1: .pedal], bassOn: true), [3, 5], "BASS takes the pedal ⇒ no pedal, 3 5")
    }

    // §B6.6 — BASS on and the pedal on the lowest lit rank ⇒ no pedal in the pass (it isn't in play).
    func testBassTakingThePedalRemovesIt() {
        XCTAssertEqual(pass([1, 3, 5], order: .up, roles: [1: .pedal], bassOn: true), [3, 5])
        XCTAssertFalse(pass([1, 3, 5], order: .up, roles: [1: .pedal], bassOn: true).contains(1), "the pedal rank (taken by bass) never appears")
    }

    // §B6.2 — group invariants across every role combination for four lit ranks under every ORDER.
    func testGroupInvariants() {
        let orders: [EuclideousOrderMode] = [.up, .down, .outsideIn, .insideOut, .asAdded, .bounce]
        let litRanks = [1, 2, 3, 4]
        for order in orders {
            // every assignment of a role to each of the four ranks (4^4 = 256), at most one PEDAL
            for code in 0..<256 {
                var map: [Int: EuclideousRankRole] = [:]
                var pedals = 0
                for (i, r) in litRanks.enumerated() {
                    let role = EuclideousRankRole(rawValue: (code >> (2 * i)) & 0b11)!
                    if role == .pedal { pedals += 1 }
                    map[r] = role
                }
                guard pedals <= 1 else { continue }   // §B1.2: the model never stores two pedals
                let p = pass(litRanks, order: order, roles: map)
                let pedalRank = map.first { $0.value == .pedal }?.key
                // each DOUBLE pair is adjacent somewhere (never split by pedal / BOUNCE / round 2)
                for (r, role) in map where role == .double {
                    var adjacent = false
                    for i in 1..<max(1, p.count) where p[i] == r && p[i - 1] == r { adjacent = true }
                    XCTAssertTrue(adjacent, "order \(order) code \(code): DOUBLE rank \(r) pair not split")
                }
                // the pedal, if any, plays before every non-pedal group — i.e. every non-pedal entry is immediately preceded by the pedal OR by the pedal's own group-mate. Simplest robust check: the pedal count ≥ the number of groups, and no two non-pedal entries of DIFFERENT ranks are adjacent without a pedal between (a DOUBLE's pair is the one allowed same-rank adjacency).
                if let pedal = pedalRank {
                    for i in 1..<max(1, p.count) {
                        let a = p[i - 1], b = p[i]
                        if a != pedal && b != pedal && a != b {
                            XCTFail("order \(order) code \(code): two different non-pedal ranks \(a),\(b) adjacent with no pedal between — pedal must precede every group")
                        }
                    }
                }
                // each RETURN rank appears exactly twice, each ONCE rank exactly once (ignoring BOUNCE, which mirrors) when there is no pedal-free bounce doubling
                if order != .bounce {
                    for (r, role) in map {
                        let n = p.filter { $0 == r }.count
                        switch role {
                        case .once: XCTAssertEqual(n, 1, "order \(order) code \(code): ONCE rank \(r) once")
                        case .double: XCTAssertEqual(n, 2, "order \(order) code \(code): DOUBLE rank \(r) twice")
                        case .returns: XCTAssertEqual(n, 2, "order \(order) code \(code): RETURN rank \(r) twice")
                        case .pedal: break   // the pedal appears once per group — not a fixed count
                        }
                    }
                }
            }
        }
    }

    // §B6.5 — PASS (the display builder) equals the pass builder's output for the current ORDER, before SHIFT.
    func testDisplayPassEqualsTheBuilder() {
        let litO = lit([1, 3, 5, 6]); let r = roleWord([1: .pedal, 5: .returns, 6: .double])
        for order in [EuclideousOrderMode.up, .down, .bounce, .outsideIn] {
            let rip = euclideousRowsRanksInPlay(litOrder: litO, bassOn: false)
            let built = euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: order, roles: r, passIndex: 0, lane: 0, shiftStart: 0, driftOn: false, driftStep: 0)
            let shown = euclideousRowsDisplayPass(litOrder: litO, bassOn: false, order: order, roles: r, lane: 0, passIndex: 0)
            XCTAssertEqual(shown.array, built.array, "order \(order)")
        }
    }
}
