//  EmitterCCTraceTests.swift — CC tab: the one-bar trace (`EmitterCCTrace.swift`) — STEP · GLIDE · FALL, inverted LOW > HIGH, RIFF rests holding the previous value — and a differential test that the curve drawn is the one the Router sends.

import XCTest

final class EmitterCCTraceTests: XCTestCase {
    private func cfg(_ mode: EmitterCCValueMode = .riff, level: Int = 100, high: Int = 127, low: Int = 0, travel: EmitterCCTravel = .step, time: Int = 50) -> EmitterCCCfg {
        EmitterCCCfg(EmitterCC(on: true, ccNumber: 74, valueMode: mode, level: level, high: high, low: low, travel: travel, time: time, muteValue: 0))
    }
    private func hits(_ pairs: [(Double, Int)]) -> [EmitterCCTraceHit] { pairs.map { EmitterCCTraceHit(beat: $0.0, rank: $0.1) } }
    private func value(_ t: EmitterCCTrace, at beat: Double) -> Int? { t.points.first { abs(Double($0.x) - beat) < 1e-6 }.map { Int($0.y) } }

    // MARK: the trace

    func testAFixedStepTraceIsAFlatLineAtTheLevelWithADotAndATickOnEveryHit() {
        let t = emitterCCTrace(cfg: cfg(.fixed, level: 100), hits: hits([(0, 1), (1, 1), (2.5, 1)]), barBeats: 4)
        XCTAssertEqual(t.ticks, [0, 1, 2.5]); XCTAssertEqual(t.dots.map { $0.x }, [0, 1, 2.5]); XCTAssertTrue(t.dots.allSatisfy { $0.y == 100 })
        XCTAssertTrue(t.points.allSatisfy { $0.y == 100 }); XCTAssertEqual(t.points.count, 4 * 24 + 1)
        XCTAssertEqual(t.gridBeats, [0, 1, 2, 3]); XCTAssertEqual(t.barBeats, 4)
    }
    func testARiffStepTraceCarriesTheRankMappedBetweenLowAndHigh() {
        let c = cfg(.riff, high: 127, low: 0)
        let t = emitterCCTrace(cfg: c, hits: hits([(0, 1), (1, 8), (2, 4)]), barBeats: 4)
        XCTAssertEqual(value(t, at: 0), 0); XCTAssertEqual(value(t, at: 1), 127); XCTAssertEqual(value(t, at: 2), c.riffValue(rank: 4)); XCTAssertEqual(value(t, at: 3.5), c.riffValue(rank: 4), "STEP holds until the next hit")
        XCTAssertEqual(t.dots.map { Int($0.y) }, [0, 127, c.riffValue(rank: 4)])
    }
    func testLowAboveHighInvertsTheMapping() {
        let c = cfg(.riff, high: 20, low: 100)
        XCTAssertEqual(emitterCCHitValue(c, rank: 1), 100); XCTAssertEqual(emitterCCHitValue(c, rank: 8), 20)
        let t = emitterCCTrace(cfg: c, hits: hits([(0, 1), (2, 8)]), barBeats: 4)
        XCTAssertEqual(value(t, at: 0), 100); XCTAssertEqual(value(t, at: 2), 20)
    }
    func testARiffRestHoldsThePreviousValueAndDrawsNoDot() {
        let t = emitterCCTrace(cfg: cfg(.riff), hits: hits([(0, 8), (1, 0), (2, 1)]), barBeats: 4)
        XCTAssertEqual(t.dots.count, 2, "the rest column makes no dot"); XCTAssertEqual(t.ticks, [0, 1, 2], "…but it is still a hit: it ticks")
        XCTAssertEqual(value(t, at: 1), 127, "held through the rest"); XCTAssertEqual(value(t, at: 2), 0)
        XCTAssertTrue(emitterCCTrace(cfg: cfg(.riff), hits: hits([(0, 0), (1, 0)]), barBeats: 4).points.isEmpty, "all rests: nothing is sent")
        XCTAssertNil(emitterCCHitValue(cfg(.riff), rank: 0)); XCTAssertEqual(emitterCCHitValue(cfg(.fixed, level: 33), rank: 0), 33, "FIXED ignores the rank")
    }
    func testAGlideHoldsThenRampsToTheNextHitsValueArrivingOnIt() {
        // hits at 0 (value 0) and 2 (value 127), TIME 50: gap 2 → hold to beat 1, then ramp to 127 arriving at beat 2
        let t = emitterCCTrace(cfg: cfg(.riff, travel: .glide, time: 50), hits: hits([(0, 1), (2, 8)]), barBeats: 4)
        XCTAssertEqual(value(t, at: 0.5), 0); XCTAssertEqual(value(t, at: 1), 0, "the hold lasts gap × (1 − t)")
        XCTAssertEqual(value(t, at: 1.5), 64, "half way up the ramp"); XCTAssertEqual(value(t, at: 2), 127, "arrived exactly on the next hit")
        // the last hit glides to the first hit of the next bar (value 0), the bar repeating
        XCTAssertEqual(value(t, at: 3), 127); XCTAssertEqual(value(t, at: 3.5), 64); XCTAssertEqual(value(t, at: 3.75), 32, "…and ramps toward the first hit of the next bar (value 0)")
    }
    func testAGlideToARestStaysAtItsOwnValue() {
        let t = emitterCCTrace(cfg: cfg(.riff, travel: .glide, time: 100), hits: hits([(0, 8), (2, 0)]), barBeats: 4)
        XCTAssertEqual(value(t, at: 1), 127, "the next hit is a rest: nothing to glide to"); XCTAssertEqual(value(t, at: 3), 127)
    }
    func testAFallRampsToLowOverTimePercentOfTheGapAndHoldsThere() {
        // hits at 0 (value 127) and 2: gap 2, TIME 50 → ramp to LOW (10) over 1 beat, hold LOW until beat 2
        let t = emitterCCTrace(cfg: cfg(.riff, high: 127, low: 10, travel: .fall, time: 50), hits: hits([(0, 8), (2, 8)]), barBeats: 4)
        XCTAssertEqual(value(t, at: 0), 127); XCTAssertEqual(value(t, at: 0.5), Int((127.0 + 10.0) / 2 + 0.5), "half way down")
        XCTAssertEqual(value(t, at: 1), 10); XCTAssertEqual(value(t, at: 1.75), 10, "held at LOW")
        XCTAssertEqual(value(t, at: 2), 127, "the next hit jumps back")
    }
    func testTheSegmentBeforeTheFirstHitIsTheLastHitsOfThePreviousBar() {
        let t = emitterCCTrace(cfg: cfg(.riff, travel: .step), hits: hits([(1, 8), (3, 1)]), barBeats: 4)
        XCTAssertEqual(value(t, at: 0.5), 0, "the bar repeats: the last hit's value is still held at the top of the bar")
        XCTAssertEqual(value(t, at: 1), 127)
    }
    func testNoHitsMeansNoTraceAndHitsOutsideTheBarAreIgnored() {
        XCTAssertTrue(emitterCCTrace(cfg: cfg(), hits: [], barBeats: 4).points.isEmpty)
        let t = emitterCCTrace(cfg: cfg(.fixed), hits: hits([(-1, 1), (4, 1), (5, 1), (1, 1)]), barBeats: 4)
        XCTAssertEqual(t.ticks, [1])
    }
    func testATracePointMapsIntoTheTile() {
        let size = CGSize(width: 100, height: 40)
        XCTAssertEqual(emitterCCTracePoint(CGPoint(x: 0, y: 127), barBeats: 4, size: size), CGPoint(x: 0, y: 0), "beat 0, value 127: top left")
        XCTAssertEqual(emitterCCTracePoint(CGPoint(x: 4, y: 0), barBeats: 4, size: size), CGPoint(x: 100, y: 40), "the bar's end, value 0: bottom right")
        let p = emitterCCTracePoint(CGPoint(x: 2, y: 63.5), barBeats: 4, size: size, inset: 4)
        XCTAssertEqual(Double(p.x), 50, accuracy: 1e-9); XCTAssertEqual(Double(p.y), 20, accuracy: 1e-9)
    }
}
