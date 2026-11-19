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

    // RIFF v4 §6/§9 test 7 — the two screenshot cases driven through the extracted pure decision `euclideousRiffWalkStepTrail`.
    // The trail is correct by construction: at every tick, relative to the trail's OWN current, every entry before it is
    // played-or-skipped and every entry after it is upcoming-or-skipped. The screenshot oddities are a SAMPLE SKEW between the
    // 15 Hz live-current ring and the 30 Hz trail-set update (the ring leads the trail by ≤ one poll), NOT a reducer bug — the
    // second half of this test reproduces both artifacts purely by feeding `state(of:liveCurrent:)` a liveCurrent one step ahead.
    private func assertTrailInvariant(_ t: EuclideousRiffWalkTrail, P: Int, file: StaticString = #filePath, line: UInt = #line) {
        let c = t.current
        guard c >= 0 else { return }
        for i in 0..<P where i != c {
            let s = t.state(of: i, liveCurrent: c)
            if i < c { XCTAssert(s == .played || s == .skipped, "entry \(i) before current \(c) is \(s)", file: file, line: line) }
            else { XCTAssert(s == .upcoming || s == .skipped, "entry \(i) after current \(c) is \(s)", file: file, line: line) }
        }
    }
    func testWalkTrailTwoScreenshotCasesAndTheSkewDiagnosis() {
        // Case 1 — forward, LEN 8, 3 hits a pass, a reset every pass. Walk visits 0,2,4 then is sent back to 0 (early reset).
        var t = EuclideousRiffWalkTrail()
        var prev = -1
        for _ in 0..<8 {                                              // 8 passes ≈ 32 bars at 4 bars/pass
            for cur in [0, 2, 4] {
                let r = euclideousRiffWalkStepTrail(t, prev: prev, cur: cur, P: 8, looped: false)
                t = r.trail; prev = cur; assertTrailInvariant(t, P: 8)
            }
            let r = euclideousRiffWalkStepTrail(t, prev: prev, cur: 0, P: 8, looped: false)   // reset: prev 4 < 7, not looped
            XCTAssertTrue(r.tick, "an early send-back-to-0 flashes the tick")
            t = r.trail; prev = 0
            XCTAssertEqual(t.skipped, [5, 6, 7], "entries after the last-played (4) that the pass never reached are skipped")
            assertTrailInvariant(t, P: 8)
        }
        // Case 2 — forward, LEN 8, 5 hits a pass, no reset, ADVANCE EVERY 1: 0..7 then a natural wrap to 0 (no tick).
        t = EuclideousRiffWalkTrail(); prev = -1
        for _ in 0..<8 {
            for cur in 0...7 {
                let r = euclideousRiffWalkStepTrail(t, prev: prev, cur: cur, P: 8, looped: false)
                XCTAssertFalse(r.tick); t = r.trail; prev = cur; assertTrailInvariant(t, P: 8)
            }
            let r = euclideousRiffWalkStepTrail(t, prev: 7, cur: 0, P: 8, looped: false)   // prev == P−1 → natural wrap
            XCTAssertFalse(r.tick, "a natural wrap does NOT tick"); t = r.trail; prev = 0
            XCTAssertTrue(t.played.isEmpty && t.skipped.isEmpty)
        }
        // THE DIAGNOSIS: the screenshot artifacts come ONLY from drawing with a liveCurrent that leads the trail's own current.
        // Case 2 still: trail at current 3 (played 0,1,2), but the 15 Hz ring already shows liveCurrent 4 → entry 3 draws UPCOMING.
        var lag = EuclideousRiffWalkTrail(); lag.advance(to: 3, count: 8)
        XCTAssertEqual(lag.state(of: 3, liveCurrent: 4), .upcoming, "ring one ahead → the trail's own current draws upcoming (the Case-2 still)")
        XCTAssertEqual(lag.state(of: 4, liveCurrent: 4), .current)
        // Case 1 still: trail still mid-pass at current 2 (played 0,1), but the ring already wrapped to 0 → entry 1 still draws PLAYED while 0 is current.
        var lag2 = EuclideousRiffWalkTrail(); lag2.advance(to: 2, count: 8)
        XCTAssertEqual(lag2.state(of: 0, liveCurrent: 0), .current)
        XCTAssertEqual(lag2.state(of: 1, liveCurrent: 0), .played, "ring wrapped to 0 before the trail reset → a played entry sits after the drawn current (the Case-1 still)")
        // With liveCurrent == trail.current (no skew) both cases satisfy §3.7 — proven by assertTrailInvariant above.
    }

    // RIFF v4 §9 test 4 — the tile's cell colours: on → note #B4BAC4, empty #30343C, playing note = lane100 (nil);
    // off → note #3E424A, empty #2A2D33; never the selected fill (#DFE3EA / #F2F4F7).
    func testRiffTileCellColours() {
        XCTAssertEqual(euclideousRiffTileCellColour(isRiff: true, isHit: true, isCur: false), 0xB4BAC4, "on note")
        XCTAssertEqual(euclideousRiffTileCellColour(isRiff: true, isHit: false, isCur: false), 0x30343C, "on empty")
        XCTAssertNil(euclideousRiffTileCellColour(isRiff: true, isHit: true, isCur: true), "the playing cell draws in lane100")
        XCTAssertEqual(euclideousRiffTileCellColour(isRiff: false, isHit: true, isCur: false), 0x3E424A, "off note")
        XCTAssertEqual(euclideousRiffTileCellColour(isRiff: false, isHit: false, isCur: false), 0x2A2D33, "off empty")
        XCTAssertEqual(euclideousRiffTileCellColour(isRiff: false, isHit: true, isCur: true), 0x3E424A, "off ignores isCur (the tile isn't sounding)")
        for c: UInt32? in [euclideousRiffTileCellColour(isRiff: true, isHit: true, isCur: false),
                           euclideousRiffTileCellColour(isRiff: true, isHit: false, isCur: false)] {
            XCTAssertNotEqual(c, 0xDFE3EA, "never the selected fill"); XCTAssertNotEqual(c, 0xF2F4F7)
        }
    }

    // §6.3 — VoiceOver value.
    func testWalkVoiceOver() {
        XCTAssertEqual(euclideousRiffWalkVoiceOver(n: 8, playing: false, current: 3), "8 steps")
        XCTAssertEqual(euclideousRiffWalkVoiceOver(n: 8, playing: true, current: 3), "step 4 of 8")
        XCTAssertEqual(euclideousRiffWalkVoiceOver(n: 8, playing: true, current: -1), "8 steps", "no current → n steps")
    }
}
