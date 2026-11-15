//  PlayAsRowsEngineTests.swift — PLAY AS ROWS ferry (2026-11-11): the ENGINE half (§2, §3, §4, §10.1-§10.5).
//  Amendment 2 (2026-11-15): the per-rank COUNTS became ROLES — the pass-builder worked examples + invariants moved to
//  PlayAsRolesTests (§B6.1/2/5/6); this file keeps the key orders, SHIFT/DRIFT, the chains (VOICES/SPREAD), BASS and the
//  RUN BLOCK, all with roles = all-ONCE (the default) or a role map where a repeat is wanted.

import XCTest

final class PlayAsRowsEngineTests: XCTestCase {
    // Build a lit order from ranks (ascending), or in a given ADDED order.
    private func lit(_ ranks: [Int], added: [Int]? = nil) -> EuclideousLitOrder {
        var o = EuclideousLitOrder(); for r in (added ?? ranks) { o.append(r - 1) }; return o
    }
    /// A packed roles word (2 bits/rank) from a {rank: role} map; ranks not named are ONCE.
    private func roles(_ pairs: [Int: EuclideousRankRole]) -> UInt16 { var m: UInt16 = 0; for (r, role) in pairs { m |= UInt16(role.rawValue) << UInt16(2 * (r - 1)) }; return m }

    private func buildPass(_ litRanks: [Int], order: EuclideousOrderMode, roles r: UInt16 = 0,
                           added: [Int]? = nil, passIndex: Int = 0, shiftStart: Int = 0, driftOn: Bool = false, driftStep: Int = 1, bassOn: Bool = false) -> [Int] {
        let rip = euclideousRowsRanksInPlay(litOrder: lit(litRanks, added: added), bassOn: bassOn)
        return euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: order, roles: r,
                                       passIndex: passIndex, lane: 0, shiftStart: shiftStart, driftOn: driftOn, driftStep: driftStep).array
    }

    // code-review 2026-11-12 — a lane whose hit ordinal grows past the RUN BLOCK must keep walking (the old
    // `(cap − p)` floor froze a single-chip arpeggio on one note forever past 4096), and the pass must LOOP at the block.
    func testRunBlockLoopsAndNeverFreezes() {
        func pick(_ h: Int64) -> [Int] {   // ranks 1,2,3 lit; default chains = an UP arpeggio, VOICES 1
            let r = euclideousRowsResolve(orderChain: nil, voicesChain: nil, spreadChain: nil,
                                          litOrder: lit([1, 2, 3]), roles: 0,
                                          bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1,
                                          lane: 0, hitOrdinal: h)
            return (0..<r.count).map { Int(r[$0]) }
        }
        let a = pick(5000), b = pick(5001), c = pick(5002)
        XCTAssertFalse(a == b && b == c, "past the block the arpeggio still advances (not frozen on one note)")
        for h: Int64 in [0, 1, 2, 7, 100, 3000, 4100] { XCTAssertEqual(pick(h), pick(h + euclideousRowsRunBlock), "hit \(h) == hit \(h) + block") }
    }

    // §10.1 — the key orders.
    func testKeyOrders() {
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .up), [2, 5, 6, 8])
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .down), [8, 6, 5, 2])
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .outsideIn), [2, 8, 5, 6])   // lowest, highest, 2nd-lowest, 2nd-highest
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .insideOut), [6, 5, 8, 2])   // OUTSIDE IN reversed
    }

    // §10.3 — SHIFT rotates by s; DRIFT adds step per pass; SHUFFLE ignores both.
    func testShiftAndDrift() {
        let base = buildPass([1, 2, 3, 4], order: .up)                            // 1 2 3 4
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, shiftStart: 1), Array(base[1...] + base[..<1]))   // 2 3 4 1
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, shiftStart: 2), [3, 4, 1, 2])
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, passIndex: 0, driftOn: true, driftStep: 1), [1, 2, 3, 4])
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, passIndex: 1, driftOn: true, driftStep: 1), [2, 3, 4, 1])
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, passIndex: 2, driftOn: true, driftStep: 1), [3, 4, 1, 2])
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, passIndex: 2, shiftStart: 1, driftOn: true, driftStep: 1), [4, 1, 2, 3])
        let s0 = buildPass([1, 2, 3, 4], order: .shuffle, shiftStart: 0)
        let s2 = buildPass([1, 2, 3, 4], order: .shuffle, shiftStart: 2)
        XCTAssertEqual(s0, s2); XCTAssertEqual(Set(s0), Set([1, 2, 3, 4]))
    }

    // §10.5 — VOICES 2 over A B B C (lit 1,2,3, rank 2 DOUBLE): A+B, B+C, A+B, B+C.
    func testVoicesTwoOverABBC() {
        let c = roles([2: .double])
        let order = [EuclideousOrderChip(value: .up, hits: 4)], voices = [EuclideousVoicesChip(value: .two, hits: 4)]
        let litO = lit([1, 2, 3])
        let want: [[Int]] = [[1, 2], [2, 3], [1, 2], [2, 3]]
        for (h, exp) in want.enumerated() {
            let hit = euclideousRowsResolve(orderChain: order, voicesChain: voices, spreadChain: nil, litOrder: litO,
                                            roles: c, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hit.ranks, exp, "hit \(h)")
        }
    }

    // §10.5 — ALL plays every rank in play once per hit; GROW grows 1..m and wraps.
    func testAllAndGrow() {
        let litO = lit([1, 2, 3, 4])
        for h in 0..<6 {
            let all = euclideousRowsResolve(orderChain: nil, voicesChain: [EuclideousVoicesChip(value: .all, hits: 4)], spreadChain: nil, litOrder: litO,
                                            roles: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(Set(all.ranks), Set([1, 2, 3, 4]), "ALL hit \(h) plays all four"); XCTAssertEqual(all.count, 4)
        }
        let grow = [EuclideousVoicesChip(value: .grow, hits: 16)]
        for (h, size) in [(0, 1), (1, 2), (2, 3), (3, 4), (4, 1), (5, 2)] {
            let hit = euclideousRowsResolve(orderChain: nil, voicesChain: grow, spreadChain: nil, litOrder: litO,
                                            roles: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hit.count, size, "GROW hit \(h) size"); XCTAssertEqual(hit.ranks, Array(1...size))
        }
    }

    // §10.4 — the three chains advance independently and loop; a single chip holds; SPREAD comes through.
    func testChainsIndependentAndLoop() {
        let order = [EuclideousOrderChip(value: .up, hits: 2), EuclideousOrderChip(value: .down, hits: 2)]
        let spread = [EuclideousSpreadChip(value: .together, hits: 1), EuclideousSpreadChip(value: .strum, hits: 1)]
        let litO = lit([1, 2, 3])
        let voices = [EuclideousVoicesChip(value: .three, hits: 99)]
        let expOrder: [[Int]] = [[1, 2, 3], [1, 2, 3], [3, 2, 1], [3, 2, 1], [1, 2, 3]]
        let expSpread: [EuclideousSpreadMode] = [.together, .strum, .together, .strum, .together]
        for h in 0..<5 {
            let hit = euclideousRowsResolve(orderChain: order, voicesChain: voices, spreadChain: spread, litOrder: litO,
                                            roles: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hit.ranks, expOrder[h], "order hit \(h)")
            XCTAssertEqual(hit.spread, expSpread[h], "spread hit \(h)")
        }
    }

    // §4.5 — BASS: HOLD sounds every hit; FIRST on even hits only; the chord excludes the lowest lit rank.
    func testBass() {
        let litO = lit([1, 2, 3])
        let voices = [EuclideousVoicesChip(value: .all, hits: 4)]
        for h in 0..<4 {
            let hold = euclideousRowsResolve(orderChain: nil, voicesChain: voices, spreadChain: nil, litOrder: litO,
                                             roles: 0, bassOn: true, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hold.bassRank, 1, "HOLD bass every hit \(h)")
            XCTAssertEqual(Set(hold.ranks), Set([2, 3]), "chord excludes the bass rank")
            let first = euclideousRowsResolve(orderChain: nil, voicesChain: voices, spreadChain: nil, litOrder: litO,
                                              roles: 0, bassOn: true, bassMode: .first, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(first.bassRank, h % 2 == 0 ? 1 : 0, "FIRST bass on even hits (\(h))")
        }
    }

    // §2.8 — nothing lit ⇒ the chord is empty (bass may still play).
    func testNothingInPlay() {
        let hit = euclideousRowsResolve(orderChain: nil, voicesChain: nil, spreadChain: nil, litOrder: EuclideousLitOrder(),
                                        roles: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: 0)
        XCTAssertEqual(hit.count, 0); XCTAssertEqual(hit.bassRank, 0)
    }

    // A default lane (ORDER [UP], VOICES [1]) plays an UP arpeggio: one note a hit, each lit rank once per pass (§11).
    func testDefaultLaneIsUpArpeggio() {
        let litO = lit([1, 2, 3])
        var got: [Int] = []
        for h in 0..<6 {
            let hit = euclideousRowsResolve(orderChain: nil, voicesChain: nil, spreadChain: nil, litOrder: litO,
                                            roles: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hit.count, 1, "one note a hit"); got.append(hit.ranks[0])
        }
        XCTAssertEqual(got, [1, 2, 3, 1, 2, 3])   // round and round
    }
}
