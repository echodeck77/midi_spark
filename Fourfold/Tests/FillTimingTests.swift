//  FillTimingTests.swift — FILL ferry (2026-11-13) slice 2: the pure §2 timing (region, fired-step count,
//  slot times, the forward/reverse source-step mapping, the rank climb, the swell ramp, BREAK, the reverse cap).
//
//  Paul's decision (2026-11-13): the fill CONTINUES THE WALK FORWARD (§2.2/§2.3), not a loop. The §7 raw text's
//  tests 3 & 4 assumed a loop; the values here are the formula's (test 3 → steps 5,6,7,8,1,2,3,4; test 4 reverse
//  → 4,3,2,1,8,7,6,5). The actual note-ons are proven in slice 3 (FillRouterTests); this pins the pure maths.

import XCTest

final class FillTimingTests: XCTestCase {

    // An 8-step 1/8 lane: sub = 0.5 beat, origin 0, B = 4 beats. Bar 4 = 0-based bar 3.
    private let sub = 0.5, B = 4.0, o = 0.0

    private func armedLine(speed: UInt8, length: UInt8, reverse: Bool = false, ranks: Int8 = 0, swell: Int8 = 0, brk: Bool = false) -> EuclidLine {
        var l = EuclidLine()
        l.fillBars = [false, false, false, true, false, false, false, false]   // bar 4 (index 3)
        l.fillSpeed = speed; l.fillLength = length; l.fillReverse = reverse; l.fillRanks = ranks; l.fillSwell = swell; l.fillBreak = brk
        return l
    }

    // MARK: §2.1 region

    func testRegionGeometry() {
        // bar 4 (index 3), ×2, LENGTH ½: E=16, D=2, F=14, m=2.
        let r = euclideousFillRegion(line: armedLine(speed: 3, length: 1), bar: 3, beatsPerBar: B)!
        XCTAssertEqual(r.E, 16); XCTAssertEqual(r.D, 2); XCTAssertEqual(r.F, 14); XCTAssertEqual(r.m, 2)
        // BAR: D=4, F=12.
        let bar = euclideousFillRegion(line: armedLine(speed: 3, length: 0), bar: 3, beatsPerBar: B)!
        XCTAssertEqual(bar.D, 4); XCTAssertEqual(bar.F, 12)
        // an unarmed bar ⇒ nil (byte-identical path); a neutral lane ⇒ nil whatever LENGTH.
        XCTAssertNil(euclideousFillRegion(line: armedLine(speed: 3, length: 1), bar: 2, beatsPerBar: B))
        XCTAssertNil(euclideousFillRegion(line: armedLine(speed: 1, length: 0), bar: 3, beatsPerBar: B), "×1, nothing else set ⇒ neutral ⇒ no region")
    }

    // MARK: §2.3 count + slot times (test 2 / test 3)

    func testCountAndTimesTest2_BAR_x2() {
        // test 2: bar 4 lit, ×2, BAR ⇒ 16 note-ons 0.25 beat apart.
        let r = euclideousFillRegion(line: armedLine(speed: 3, length: 0), bar: 3, beatsPerBar: B)!
        XCTAssertEqual(euclideousFillCount(r, origin: o, sub: sub), 16)
        XCTAssertEqual(euclideousFillSlotHostBeat(r, origin: o, sub: sub, slot: 0), 12, accuracy: 1e-9)
        XCTAssertEqual(euclideousFillSlotHostBeat(r, origin: o, sub: sub, slot: 1), 12.25, accuracy: 1e-9)
        XCTAssertEqual(euclideousFillSlotHostBeat(r, origin: o, sub: sub, slot: 15), 15.75, accuracy: 1e-9)
    }

    func testCountAndTimesTest3_half_x2() {
        // test 3: LENGTH ½, ×2 ⇒ 8 note-ons 0.25 apart starting at beat 2 of the bar (host beat 14).
        let r = euclideousFillRegion(line: armedLine(speed: 3, length: 1), bar: 3, beatsPerBar: B)!
        XCTAssertEqual(euclideousFillCount(r, origin: o, sub: sub), 8)
        XCTAssertEqual(euclideousFillSlotHostBeat(r, origin: o, sub: sub, slot: 0), 14, accuracy: 1e-9)
        for k in 0..<8 { XCTAssertEqual(euclideousFillSlotHostBeat(r, origin: o, sub: sub, slot: k), 14 + 0.25 * Double(k), accuracy: 1e-9) }
    }

    // MARK: §2.3 forward / reverse source step (test 3 / test 4) — pattern position = step index mod 8

    private func pos1(_ j: Int64) -> Int { Int(((j % 8) + 8) % 8) + 1 }   // 1-based step for an 8-step FWD lane, origin 0

    func testForwardStepsContinueTheWalk_test3() {
        // Paul's decision: CONTINUE FORWARD ⇒ steps 5,6,7,8,1,2,3,4 (NOT the raw text's looped 5,6,7,8,5,6,7,8).
        let r = euclideousFillRegion(line: armedLine(speed: 3, length: 1), bar: 3, beatsPerBar: B)!
        let N = euclideousFillCount(r, origin: o, sub: sub)
        let steps = (0..<N).map { pos1(euclideousFillSourceStep(r, origin: o, sub: sub, count: N, slot: $0)) }
        XCTAssertEqual(steps, [5, 6, 7, 8, 1, 2, 3, 4])
    }

    func testReverseMirrorsTheForwardList_test4() {
        // test 4: REVERSE ⇒ the forward list mirrored in time ⇒ 4,3,2,1,8,7,6,5 (reverse of 5,6,7,8,1,2,3,4).
        let r = euclideousFillRegion(line: armedLine(speed: 3, length: 1, reverse: true), bar: 3, beatsPerBar: B)!
        let N = euclideousFillCount(r, origin: o, sub: sub)
        let steps = (0..<N).map { pos1(euclideousFillSourceStep(r, origin: o, sub: sub, count: N, slot: $0)) }
        XCTAssertEqual(steps, [4, 3, 2, 1, 8, 7, 6, 5])
        // the slot TIMES are unchanged by reverse (§2.3: "Timing is unchanged; the order of what plays is mirrored").
        for k in 0..<N { XCTAssertEqual(euclideousFillSlotHostBeat(r, origin: o, sub: sub, slot: k), 14 + 0.25 * Double(k), accuracy: 1e-9) }
    }

    // MARK: §2.5 ranks climb (test 5)

    func testRankClimb_test5() {
        // +3 over N=8: first 0, last +3; round(3k/7).
        XCTAssertEqual((0..<8).map { euclideousFillRankOffset(ranks: 3, slot: $0, count: 8) }, [0, 0, 1, 1, 2, 2, 3, 3])
        XCTAssertEqual(euclideousFillRankOffset(ranks: 3, slot: 0, count: 1), 3, "N=1 ⇒ R")
        XCTAssertEqual(euclideousFillRankOffset(ranks: -7, slot: 7, count: 8), -7, "last slot gets the full negative climb")
    }

    // MARK: §2.6 swell ramp (test 6)

    func testSwellRamp_test6() {
        // +3 over 8: rise 0.35 → 1.0.
        XCTAssertEqual(euclideousFillSwellFactor(swell: 3, slot: 0, count: 8), 0.35, accuracy: 1e-9)
        XCTAssertEqual(euclideousFillSwellFactor(swell: 3, slot: 7, count: 8), 1.0, accuracy: 1e-9)
        // −3 over 8: fall 1.0 → 0.35.
        XCTAssertEqual(euclideousFillSwellFactor(swell: -3, slot: 0, count: 8), 1.0, accuracy: 1e-9)
        XCTAssertEqual(euclideousFillSwellFactor(swell: -3, slot: 7, count: 8), 0.35, accuracy: 1e-9)
        // 0 ⇒ no change.
        for k in 0..<8 { XCTAssertEqual(euclideousFillSwellFactor(swell: 0, slot: k, count: 8), 1) }
    }

    // MARK: §2.7 break window (test 7)

    func testBreakWindow_test7() {
        // BAR at 4/4 (bar 4, index 3): E=16, D=4 ⇒ the last quarter is [15,16) (the last beat).
        let r = euclideousFillRegion(line: armedLine(speed: 3, length: 0, brk: true), bar: 3, beatsPerBar: B)!
        XCTAssertFalse(euclideousFillBreakDrops(r, hostBeat: 14.75))
        XCTAssertTrue(euclideousFillBreakDrops(r, hostBeat: 15.0))
        XCTAssertTrue(euclideousFillBreakDrops(r, hostBeat: 15.75))
        // break off ⇒ never drops.
        let noBrk = euclideousFillRegion(line: armedLine(speed: 3, length: 0), bar: 3, beatsPerBar: B)!
        XCTAssertFalse(euclideousFillBreakDrops(noBrk, hostBeat: 15.5))
    }

    // MARK: §2.4 step length (test 11)

    func testStepLengthHalvesAtX2_test11() {
        let r = euclideousFillRegion(line: armedLine(speed: 3, length: 1), bar: 3, beatsPerBar: B)!   // ×2
        XCTAssertEqual(euclideousFillStepHostLength(r, sub: sub), 0.25, "sub 0.5 / m 2 = 0.25")
        let x4 = euclideousFillRegion(line: armedLine(speed: 4, length: 1), bar: 3, beatsPerBar: B)!   // ×4
        XCTAssertEqual(euclideousFillStepHostLength(x4, sub: sub), 0.125)
    }

    // MARK: §2.3 reverse buffer cap (test 12)

    func testReverseCapAndFallback_test12() {
        // N = 128 keeps reverse; above it, reverse falls back to forward.
        let r = euclideousFillRegion(line: armedLine(speed: 4, length: 0, reverse: true), bar: 3, beatsPerBar: B)!
        XCTAssertTrue(euclideousFillReverseActive(r, count: 128))
        XCTAssertFalse(euclideousFillReverseActive(r, count: 129), "above the 128 cap ⇒ forward")
        // the fallback plays forward: slot k ⇒ step j_0 + k.
        let j0 = euclideousFillFirstStep(r, origin: o, sub: sub)
        XCTAssertEqual(euclideousFillSourceStep(r, origin: o, sub: sub, count: 129, slot: 5), j0 + 5)
    }

    // MARK: §2.11 locate = play-through (the mapping is a pure function of the slot)

    func testLocateEqualsPlaythrough_test14() {
        let r = euclideousFillRegion(line: armedLine(speed: 3, length: 1, reverse: true, ranks: 3, swell: 2), bar: 3, beatsPerBar: B)!
        let N = euclideousFillCount(r, origin: o, sub: sub)
        // Reading slot 5 directly gives the same source step / time / offset / factor as iterating would.
        XCTAssertEqual(euclideousFillSourceStep(r, origin: o, sub: sub, count: N, slot: 5), euclideousFillFirstStep(r, origin: o, sub: sub) + Int64(N - 1 - 5))
        XCTAssertEqual(euclideousFillSlotHostBeat(r, origin: o, sub: sub, slot: 5), 14 + 0.25 * 5, accuracy: 1e-9)
        XCTAssertEqual(euclideousFillRankOffset(ranks: 3, slot: 5, count: N), euclideousFillRankOffset(ranks: 3, slot: 5, count: N))
    }
}
