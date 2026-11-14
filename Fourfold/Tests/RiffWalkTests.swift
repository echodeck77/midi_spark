//  RiffWalkTests.swift — RIFF tab v3 ferry (2026-11-14) §8: the walk grid's rank rule and the trail reducer (tests 4–7) + §6.3.

import XCTest

final class RiffWalkTests: XCTestCase {

    // §8.4 — the lit cell's rank = the chip's drawn rank (FLIP NOTES = 9−r, TRANS = +t, rest-safe); a forward walk reads column k at step k.
    func testWalkLitRankRule() {
        let ranks = [2, 5, 1, 5, 3, 2, 1, 1]
        XCTAssertEqual(euclideousRiffStepRanks(ranks: ranks, invert: false, transpose: 0), ranks)
        XCTAssertEqual(euclideousRiffStepRanks(ranks: ranks, invert: true, transpose: 0), [7, 4, 8, 4, 6, 7, 8, 8], "FLIP NOTES = 9 − r")
        XCTAssertEqual(euclideousRiffStepRanks(ranks: ranks, invert: false, transpose: 2), [4, 7, 3, 7, 5, 4, 3, 3], "TRANS = +t")
        // a rest (0) stays a rest under both transforms — the walk lights nothing there
        XCTAssertEqual(euclideousRiffStepRanks(ranks: [0, 3, 0], invert: true, transpose: 2), [0, 8, 0])
        // forward: step k reads column k
        for k in 0..<8 { XCTAssertEqual(euclideousRiffColumn(ordinal: Int64(k), every: 1, direction: .forward, length: 8, stride: 1, shift: 0, columns: 8), k) }
    }

    // §8.5 — advance(9) on a 14-entry walk: 0–8 played, 9 current, 10–13 upcoming.
    func testWalkTrailAdvance() {
        var t = EuclideousRiffWalkTrail()
        t.advance(to: 9, count: 14)
        XCTAssertEqual(t.current, 9)
        XCTAssertEqual(t.played, Set(0..<9)); XCTAssertTrue(t.skipped.isEmpty)
        for i in 0..<9 { XCTAssertEqual(t.state(of: i, liveCurrent: 9), .played) }
        XCTAssertEqual(t.state(of: 9, liveCurrent: 9), .current)
        for i in 10..<14 { XCTAssertEqual(t.state(of: i, liveCurrent: 9), .upcoming) }
    }

    // §8.6 — reset at current 11 → current 0, 12 & 13 skipped, 1–11 upcoming, nothing played; then advancing through 12 un-skips 12, 13 stays skipped.
    func testWalkTrailResetThenAdvance() {
        var t = EuclideousRiffWalkTrail()
        t.advance(to: 11, count: 14)                       // played 0–10, current 11
        t.reset(count: 14)
        XCTAssertEqual(t.current, 0); XCTAssertTrue(t.played.isEmpty)
        XCTAssertEqual(t.skipped, [12, 13])
        for i in 1...11 { XCTAssertEqual(t.state(of: i, liveCurrent: 0), .upcoming) }
        XCTAssertEqual(t.state(of: 12, liveCurrent: 0), .skipped); XCTAssertEqual(t.state(of: 13, liveCurrent: 0), .skipped)
        t.advance(to: 12, count: 14)                       // reaches 12
        XCTAssertEqual(t.played, Set(0..<12)); XCTAssertEqual(t.skipped, [13], "12 un-skips when reached, 13 stays skipped")
        XCTAssertEqual(t.state(of: 12, liveCurrent: 12), .current)
    }

    // §8.7 — a natural wrap clears played and skipped, marks nothing.
    func testWalkTrailWrap() {
        var t = EuclideousRiffWalkTrail()
        t.advance(to: 13, count: 14); t.reset(count: 14)   // leave some skipped around
        t.advance(to: 5, count: 14)
        t.wrap()
        XCTAssertTrue(t.played.isEmpty); XCTAssertTrue(t.skipped.isEmpty); XCTAssertEqual(t.current, 0)
        for i in 1..<14 { XCTAssertEqual(t.state(of: i, liveCurrent: -1), .upcoming) }
    }

    // §6.3 — VoiceOver value.
    func testWalkVoiceOver() {
        XCTAssertEqual(euclideousRiffWalkVoiceOver(n: 8, playing: false, current: 3), "8 steps")
        XCTAssertEqual(euclideousRiffWalkVoiceOver(n: 8, playing: true, current: 3), "step 4 of 8")
        XCTAssertEqual(euclideousRiffWalkVoiceOver(n: 8, playing: true, current: -1), "8 steps", "no current → n steps")
    }
}
