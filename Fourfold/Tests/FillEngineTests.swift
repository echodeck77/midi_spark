//  FillEngineTests.swift — FILL TAB ferry (2026-11-14) §2 pure functions: ORDER (§7.3), SHAPE (§7.5), CHANCE (§7.9), SHUFFLE determinism, RUSH count/timing (§7.2). The Router-level wiring (ORDER content, SHAPE climb) rides the golden byte-identity + these pins.

import XCTest

final class FillEngineTests: XCTestCase {
    private func region(order: EuclideousFillOrder = .fwd, m: Double = 2, curve: EuclideousFillCurve = .steady, lane: Int = 0, bar: Int = 0) -> EuclideousFillRegion {
        var r = EuclideousFillRegion(); r.barIndex = bar; r.lane = lane; r.F = 0; r.E = 4; r.D = 4; r.m = m; r.curve = curve; r.order = order; return r
    }

    // §7.3 — ORDER on N = 8 (and BOUNCE on N = 7).
    func testOrder() {
        func seq(_ o: EuclideousFillOrder, N: Int, shuffle: [Int]? = nil) -> [Int] {
            var r = region(order: o); return (0..<N).map { Int(euclideousFillSourceStep(r, origin: 0, sub: 0.5, count: N, slot: $0, shuffle: shuffle)) }   // j0 = 0 ⇒ step index == content index
        }
        XCTAssertEqual(seq(.fwd, N: 8), [0, 1, 2, 3, 4, 5, 6, 7])
        XCTAssertEqual(seq(.rev, N: 8), [7, 6, 5, 4, 3, 2, 1, 0])
        XCTAssertEqual(seq(.bounce, N: 8), [0, 1, 2, 3, 3, 2, 1, 0])
        XCTAssertEqual(seq(.bounce, N: 7), [0, 1, 2, 3, 2, 1, 0])
    }

    // §7.3 — SHUFFLE is a permutation, identical for the same (lane, bar), different across bars.
    func testShuffleIsADeterministicPermutation() {
        func perm(lane: Int, bar: Int, N: Int = 8) -> [Int] { var b = [Int](repeating: 0, count: N); euclideousFillShuffle(lane: lane, bar: bar, count: N, into: &b); return b }
        let a = perm(lane: 1, bar: 3), a2 = perm(lane: 1, bar: 3)
        XCTAssertEqual(a, a2, "same lane + bar ⇒ identical")
        XCTAssertEqual(Set(a), Set(0..<8), "a permutation of 0…7")
        XCTAssertNotEqual(a, perm(lane: 1, bar: 4), "a different bar shuffles differently")
        XCTAssertNotEqual(a, perm(lane: 2, bar: 3), "a different lane shuffles differently")
        // the Router reads it through euclideousFillSourceStep
        var r = region(order: .shuffle)
        let mapped = (0..<8).map { Int(euclideousFillSourceStep(r, origin: 0, sub: 0.5, count: 8, slot: $0, shuffle: a)) }
        XCTAssertEqual(mapped, a)
    }

    // §7.5 — RANKS +4 on N = 9: CLIMB / ARCH / SHIFT.
    func testRankShape() {
        func off(_ s: EuclideousFillShape) -> [Int] { (0..<9).map { euclideousFillRankOffset(ranks: 4, slot: $0, count: 9, shape: s) } }
        XCTAssertEqual(off(.climb), [0, 1, 1, 2, 2, 3, 3, 4, 4])   // round half away from zero
        XCTAssertEqual(off(.arch), [0, 1, 2, 3, 4, 3, 2, 1, 0])
        XCTAssertEqual(off(.shift), [4, 4, 4, 4, 4, 4, 4, 4, 4])
        XCTAssertEqual(euclideousFillRankOffset(ranks: 4, slot: 0, count: 1, shape: .arch), 4, "N=1 ⇒ R")
    }

    // §7.6 — ROLL: 1 + round(ROLL·u) strikes per slot, thickening toward the downbeat; ROLL 0 ⇒ 1 everywhere; capped at 16.
    func testRollCount() {
        func counts(_ R: Int, N: Int) -> [Int] { (0..<N).map { euclideousFillRollCount(roll: R, slot: $0, count: N) } }
        XCTAssertEqual(counts(0, N: 8), [Int](repeating: 1, count: 8), "ROLL 0 ⇒ never more than one strike (byte-identical)")
        XCTAssertEqual(counts(4, N: 9), [1, 2, 2, 3, 3, 4, 4, 5, 5], "u = k/8 ⇒ 1+round(4u), round half away from zero")
        XCTAssertEqual(counts(4, N: 5), [1, 2, 3, 4, 5], "u = 0,¼,½,¾,1 ⇒ 1+round(4u)")
        XCTAssertEqual(euclideousFillRollCount(roll: 4, slot: 0, count: 1), 5, "N=1 ⇒ u=1 ⇒ 1+R")
        XCTAssertEqual(euclideousFillRollCount(roll: 20, slot: 9, count: 10), 16, "capped at 16")
    }

    // §7.9 — CHANCE 50: ~half of 1,000 armed bars play; deterministic per (lane, bar).
    func testChance() {
        XCTAssertTrue(euclideousFillChancePlays(lane: 0, bar: 0, chance: 100), "100% always plays")
        let plays = (0..<1000).filter { euclideousFillChancePlays(lane: 1, bar: $0, chance: 50) }.count
        XCTAssertTrue((450...550).contains(plays), "CHANCE 50 ≈ half (got \(plays))")
        XCTAssertEqual(euclideousFillChancePlays(lane: 1, bar: 7, chance: 50), euclideousFillChancePlays(lane: 1, bar: 7, chance: 50), "same (lane, bar) decides the same after a locate")
    }

    // §7.2 — RUSH ×2 over a BAR on an 8-step 1/8 lane: 12 fired steps (1.5 bars of lane time), gaps shrinking.
    func testRushCountAndGapsShrink() {
        let r = region(m: 2, curve: .rush)   // D = 4 beats (BAR), m = 2, sub = 0.5 ⇒ span D(1+m)/2 = 6 lane beats ⇒ 12 steps
        XCTAssertEqual(euclideousFillCount(r, origin: 0, sub: 0.5), 12)
        let t = (0..<13).map { euclideousFillSlotHostBeat(r, origin: 0, sub: 0.5, slot: $0) }
        let gaps = (1..<t.count).map { t[$0] - t[$0 - 1] }
        XCTAssertEqual(gaps.first!, 0.5, accuracy: 0.03, "first gap ≈ 0.5 beat (rate ×1 at F)")
        XCTAssertLessThan(gaps.last!, gaps.first!, "gaps shrink as the rate rises")
        XCTAssertEqual(gaps.last!, 0.25, accuracy: 0.05, "last gap ≈ 0.25 beat (rate ×2 at E)")
        XCTAssertTrue(zip(gaps, gaps.dropFirst()).allSatisfy { $0 >= $1 - 1e-9 }, "monotonically shrinking")
        // RUSH ×½ slows: fewer than 8 fired steps over the bar
        let slow = region(m: 0.5, curve: .rush)
        XCTAssertEqual(euclideousFillCount(slow, origin: 0, sub: 0.5), 6, "×½ RUSH covers D(1+m)/2 = 3 lane beats ⇒ 6 steps")
    }
}
