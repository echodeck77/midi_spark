//  PlayAsRowsEngineTests.swift — PLAY AS ROWS ferry (2026-11-11): the ENGINE half (§2, §3, §4, §10.1-§10.5).
//
//  The pass builder and the per-hit resolver are PURE functions of the lit ranks, the §1 model and the hit ordinal since the melody origin — so the §2.6 worked examples pin the pass, and a simulated hit sequence pins the chains and
//  each-hit consume. Every assertion here is a literal from the ferry text.

import XCTest

final class PlayAsRowsEngineTests: XCTestCase {
    // Build a lit order from ranks (ascending), or in a given ADDED order.
    private func lit(_ ranks: [Int], added: [Int]? = nil) -> EuclideousLitOrder {
        var o = EuclideousLitOrder(); for r in (added ?? ranks) { o.append(r - 1) }; return o
    }
    private func counts(_ pairs: [Int: Int]) -> UInt16 { var m: UInt16 = 0; for (r, c) in pairs { m |= UInt16(max(0, min(2, c - 1))) << UInt16(2 * (r - 1)) }; return m }
    private func laterMask(_ ranks: [Int]) -> UInt8 { var m: UInt8 = 0; for r in ranks { m |= 1 << UInt8(r - 1) }; return m }

    private func buildPass(_ litRanks: [Int], order: EuclideousOrderMode, counts c: UInt16 = 0, second: UInt8 = 0, third: UInt8 = 0,
                           added: [Int]? = nil, passIndex: Int = 0, shiftStart: Int = 0, driftOn: Bool = false, driftStep: Int = 1, bassOn: Bool = false) -> [Int] {
        let rip = euclideousRowsRanksInPlay(litOrder: lit(litRanks, added: added), bassOn: bassOn)
        return euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: order, counts: c, secondLater: second, thirdLater: third,
                                       passIndex: passIndex, lane: 0, shiftStart: shiftStart, driftOn: driftOn, driftStep: driftStep).array
    }

    // §10.1 / §2.6 — the pass builder, every worked example.
    func testPassBuilderExamples() {
        // lit 1,2,3 = A,B,C. B 2, AGAIN: A B B C. B 2, LATER: A B C B. DOWN with B 2, LATER: C B A B.
        XCTAssertEqual(buildPass([1, 2, 3], order: .up, counts: counts([2: 2])), [1, 2, 2, 3])
        XCTAssertEqual(buildPass([1, 2, 3], order: .up, counts: counts([2: 2]), second: laterMask([2])), [1, 2, 3, 2])
        XCTAssertEqual(buildPass([1, 2, 3], order: .down, counts: counts([2: 2]), second: laterMask([2])), [3, 2, 1, 2])
        // B 3: AGAIN·AGAIN A B B B C; AGAIN·LATER A B B C B; LATER·AGAIN A B C B B; LATER·LATER A B C B B.
        XCTAssertEqual(buildPass([1, 2, 3], order: .up, counts: counts([2: 3])), [1, 2, 2, 2, 3])
        XCTAssertEqual(buildPass([1, 2, 3], order: .up, counts: counts([2: 3]), third: laterMask([2])), [1, 2, 2, 3, 2])
        XCTAssertEqual(buildPass([1, 2, 3], order: .up, counts: counts([2: 3]), second: laterMask([2])), [1, 2, 3, 2, 2])
        XCTAssertEqual(buildPass([1, 2, 3], order: .up, counts: counts([2: 3]), second: laterMask([2]), third: laterMask([2])), [1, 2, 3, 2, 2])
        // lit 2,5,6,8; rank 5 count 2 LATER; rank 8 count 3 AGAIN,LATER. UP: 2 5 6 8 8 5 8.
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .up, counts: counts([5: 2, 8: 3]), second: laterMask([5]), third: laterMask([8])), [2, 5, 6, 8, 8, 5, 8])
        // AS ADDED with addedOrder 8,2,5,6: 8 8 2 5 6 8 5; with start 1: 8 2 5 6 8 5 8.
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .asAdded, counts: counts([5: 2, 8: 3]), second: laterMask([5]), third: laterMask([8]), added: [8, 2, 5, 6]), [8, 8, 2, 5, 6, 8, 5])
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .asAdded, counts: counts([5: 2, 8: 3]), second: laterMask([5]), third: laterMask([8]), added: [8, 2, 5, 6], shiftStart: 1), [8, 2, 5, 6, 8, 5, 8])
        // BOUNCE, lit 1-4, all count 1: 1 2 3 4 3 2.
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .bounce), [1, 2, 3, 4, 3, 2])
    }

    // §10.1 — the other key orders.
    func testKeyOrders() {
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .up), [2, 5, 6, 8])
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .down), [8, 6, 5, 2])
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .outsideIn), [2, 8, 5, 6])   // lowest, highest, 2nd-lowest, 2nd-highest
        XCTAssertEqual(buildPass([2, 5, 6, 8], order: .insideOut), [6, 5, 8, 2])   // OUTSIDE IN reversed
    }

    // §10.2 — one rank among three lit, every count/timing: exactly `count` copies, and every AGAIN copy sits straight after the copy before it.
    func testCopyCountsAndContiguity() {
        for count in 1...3 {
            for secondLater in [false, true] {
                for thirdLater in [false, true] {
                    let pass = buildPass([1, 2, 3], order: .up, counts: counts([2: count]),
                                         second: secondLater ? laterMask([2]) : 0, third: thirdLater ? laterMask([2]) : 0)
                    XCTAssertEqual(pass.filter { $0 == 2 }.count, count, "count=\(count) sL=\(secondLater) tL=\(thirdLater)")
                    // an AGAIN copy is adjacent to the copy before it: if copy 2 is AGAIN, two 2s are adjacent somewhere.
                    if count >= 2 && !secondLater {
                        var adj = false; for i in 1..<pass.count where pass[i] == 2 && pass[i - 1] == 2 { adj = true }
                        XCTAssertTrue(adj, "copy 2 AGAIN ⇒ adjacent (count=\(count) tL=\(thirdLater))")
                    }
                }
            }
        }
    }

    // §10.3 — SHIFT rotates by s; DRIFT adds step per pass; SHUFFLE ignores both.
    func testShiftAndDrift() {
        let base = buildPass([1, 2, 3, 4], order: .up)                            // 1 2 3 4
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, shiftStart: 1), Array(base[1...] + base[..<1]))   // 2 3 4 1
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, shiftStart: 2), [3, 4, 1, 2])
        // DRIFT +1: pass 0 no shift, pass 1 shifts 1, pass 2 shifts 2 …
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, passIndex: 0, driftOn: true, driftStep: 1), [1, 2, 3, 4])
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, passIndex: 1, driftOn: true, driftStep: 1), [2, 3, 4, 1])
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, passIndex: 2, driftOn: true, driftStep: 1), [3, 4, 1, 2])
        // a start with drift: start 1, drift +1, pass 2 ⇒ rotate 3
        XCTAssertEqual(buildPass([1, 2, 3, 4], order: .up, passIndex: 2, shiftStart: 1, driftOn: true, driftStep: 1), [4, 1, 2, 3])
        // SHUFFLE ignores SHIFT — the permutation is the same whatever the start (it is a function of lane+passIndex only).
        let s0 = buildPass([1, 2, 3, 4], order: .shuffle, shiftStart: 0)
        let s2 = buildPass([1, 2, 3, 4], order: .shuffle, shiftStart: 2)
        XCTAssertEqual(s0, s2); XCTAssertEqual(Set(s0), Set([1, 2, 3, 4]))
    }

    // §10.5 — VOICES 2 over A B B C: A+B, B+C, A+B, B+C.
    func testVoicesTwoOverABBC() {
        // A B B C comes from lit 1,2,3 with rank 2 count 2 AGAIN.
        let c = counts([2: 2])
        var l = EuclidLine(); l.notesOrderChain = [EuclideousOrderChip(value: .up, hits: 4)]; l.notesVoicesChain = [EuclideousVoicesChip(value: .two, hits: 4)]
        let litO = lit([1, 2, 3])
        let want: [[Int]] = [[1, 2], [2, 3], [1, 2], [2, 3]]
        for (h, exp) in want.enumerated() {
            let hit = euclideousRowsResolve(orderChain: l.notesOrderChain, voicesChain: l.notesVoicesChain, spreadChain: nil, litOrder: litO,
                                            counts: c, secondLater: 0, thirdLater: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hit.ranks, exp, "hit \(h)")
        }
    }

    // §10.5 — ALL plays every rank in play once per hit; GROW grows 1..m and wraps.
    func testAllAndGrow() {
        let litO = lit([1, 2, 3, 4])
        for h in 0..<6 {
            let all = euclideousRowsResolve(orderChain: nil, voicesChain: [EuclideousVoicesChip(value: .all, hits: 4)], spreadChain: nil, litOrder: litO,
                                            counts: 0, secondLater: 0, thirdLater: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(Set(all.ranks), Set([1, 2, 3, 4]), "ALL hit \(h) plays all four"); XCTAssertEqual(all.count, 4)
        }
        // GROW: m = 4 ⇒ sizes 1,2,3,4,1,2,… each from the pass start.
        let grow = [EuclideousVoicesChip(value: .grow, hits: 16)]
        for (h, size) in [(0, 1), (1, 2), (2, 3), (3, 4), (4, 1), (5, 2)] {
            let hit = euclideousRowsResolve(orderChain: nil, voicesChain: grow, spreadChain: nil, litOrder: litO,
                                            counts: 0, secondLater: 0, thirdLater: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hit.count, size, "GROW hit \(h) size"); XCTAssertEqual(hit.ranks, Array(1...size))
        }
    }

    // §10.4 — the three chains advance independently and loop; a single chip holds; SPREAD comes through.
    func testChainsIndependentAndLoop() {
        let order = [EuclideousOrderChip(value: .up, hits: 2), EuclideousOrderChip(value: .down, hits: 2)]   // UP for 2 hits, DOWN for 2, loop
        let spread = [EuclideousSpreadChip(value: .together, hits: 1), EuclideousSpreadChip(value: .strum, hits: 1)]   // alternates every hit
        let litO = lit([1, 2, 3])
        // VOICES 3 (whole chord) so each hit shows the ORDER chip's key order directly.
        let voices = [EuclideousVoicesChip(value: .three, hits: 99)]
        let expOrder: [[Int]] = [[1, 2, 3], [1, 2, 3], [3, 2, 1], [3, 2, 1], [1, 2, 3]]   // UP,UP,DOWN,DOWN,UP(loop) — ORDER change starts a new pass at position 0
        let expSpread: [EuclideousSpreadMode] = [.together, .strum, .together, .strum, .together]
        for h in 0..<5 {
            let hit = euclideousRowsResolve(orderChain: order, voicesChain: voices, spreadChain: spread, litOrder: litO,
                                            counts: 0, secondLater: 0, thirdLater: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hit.ranks, expOrder[h], "order hit \(h)")
            XCTAssertEqual(hit.spread, expSpread[h], "spread hit \(h)")
        }
    }

    // §4.5 — BASS: HOLD sounds every hit; FIRST on even hits only; the chord excludes the lowest lit rank.
    func testBass() {
        let litO = lit([1, 2, 3])   // lowest lit = 1 ⇒ bass
        let voices = [EuclideousVoicesChip(value: .all, hits: 4)]
        for h in 0..<4 {
            let hold = euclideousRowsResolve(orderChain: nil, voicesChain: voices, spreadChain: nil, litOrder: litO,
                                             counts: 0, secondLater: 0, thirdLater: 0, bassOn: true, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hold.bassRank, 1, "HOLD bass every hit \(h)")
            XCTAssertEqual(Set(hold.ranks), Set([2, 3]), "chord excludes the bass rank")
            let first = euclideousRowsResolve(orderChain: nil, voicesChain: voices, spreadChain: nil, litOrder: litO,
                                              counts: 0, secondLater: 0, thirdLater: 0, bassOn: true, bassMode: .first, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(first.bassRank, h % 2 == 0 ? 1 : 0, "FIRST bass on even hits (\(h))")
        }
    }

    // §2.8 — nothing lit ⇒ the chord is empty (bass may still play).
    func testNothingInPlay() {
        let hit = euclideousRowsResolve(orderChain: nil, voicesChain: nil, spreadChain: nil, litOrder: EuclideousLitOrder(),
                                        counts: 0, secondLater: 0, thirdLater: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: 0)
        XCTAssertEqual(hit.count, 0); XCTAssertEqual(hit.bassRank, 0)
    }

    // A default lane (ORDER [UP], VOICES [1]) plays an UP arpeggio: one note a hit, each lit rank once per pass (§11).
    func testDefaultLaneIsUpArpeggio() {
        let litO = lit([1, 2, 3])
        var got: [Int] = []
        for h in 0..<6 {
            let hit = euclideousRowsResolve(orderChain: nil, voicesChain: nil, spreadChain: nil, litOrder: litO,
                                            counts: 0, secondLater: 0, thirdLater: 0, bassOn: false, bassMode: .hold, shiftStart: 0, driftOn: false, driftStep: 1, lane: 0, hitOrdinal: Int64(h))
            XCTAssertEqual(hit.count, 1, "one note a hit"); got.append(hit.ranks[0])
        }
        XCTAssertEqual(got, [1, 2, 3, 1, 2, 3])   // round and round
    }
}
