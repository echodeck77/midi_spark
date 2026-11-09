//  EmitterCCTraceTests.swift — CC tab: the one-bar trace (`EmitterCCTrace.swift`) — STEP · GLIDE · FALL, inverted LOW > HIGH, RIFF rests holding the previous value — and a differential test that the curve drawn is the one the Router sends.

import XCTest

final class EmitterCCTraceTests: XCTestCase {
    private func cfg(_ mode: EmitterCCValueMode = .riff, high: Int = 127, low: Int = 0, travel: EmitterCCTravel = .step, time: Int = 50) -> EmitterCCCfg {
        EmitterCCCfg(EmitterCC(on: true, ccNumber: 74, valueMode: mode, high: high, low: low, travel: travel, time: time, muteValue: 0))
    }
    private func hits(_ pairs: [(Double, Int)]) -> [EmitterCCTraceHit] { pairs.map { EmitterCCTraceHit(beat: $0.0, rank: $0.1) } }
    private func value(_ t: EmitterCCTrace, at beat: Double) -> Int? { t.points.first { abs(Double($0.x) - beat) < 1e-6 }.map { Int($0.y) } }

    // MARK: the trace

    func testAnEqualEndedPingPongTraceIsAFlatLineWithADotAndATickOnEveryHit() {
        let t = emitterCCTrace(cfg: cfg(.pingPong, high: 100, low: 100), hits: hits([(0, 1), (1, 1), (2.5, 1)]), barBeats: 4)
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
        XCTAssertNil(emitterCCHitValue(cfg(.riff), rank: 0)); XCTAssertEqual(emitterCCHitValue(cfg(.pingPong, high: 33, low: 33), rank: 0), 33, "PING-PONG ignores the rank")
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
        let t = emitterCCTrace(cfg: cfg(.pingPong), hits: hits([(-1, 1), (4, 1), (5, 1), (1, 1)]), barBeats: 4)
        XCTAssertEqual(t.ticks, [1])
    }
    func testATracePointMapsIntoTheTile() {
        let size = CGSize(width: 100, height: 40)
        XCTAssertEqual(emitterCCTracePoint(CGPoint(x: 0, y: 127), barBeats: 4, size: size), CGPoint(x: 0, y: 0), "beat 0, value 127: top left")
        XCTAssertEqual(emitterCCTracePoint(CGPoint(x: 4, y: 0), barBeats: 4, size: size), CGPoint(x: 100, y: 40), "the bar's end, value 0: bottom right")
        let p = emitterCCTracePoint(CGPoint(x: 2, y: 63.5), barBeats: 4, size: size, inset: 4)
        XCTAssertEqual(Double(p.x), 50, accuracy: 1e-9); XCTAssertEqual(Double(p.y), 20, accuracy: 1e-9)
    }

    // MARK: lanes, PING-PONG and the inert sliders (2026-11-09)
    func testEachDotAndEachPointWearsTheLaneWhoseHitItIs() {
        let hs = [EmitterCCTraceHit(beat: 0, rank: 1, lane: 0), EmitterCCTraceHit(beat: 2, rank: 8, lane: 2)]
        let t = emitterCCTrace(cfg: cfg(.riff), hits: hs, barBeats: 4)
        XCTAssertEqual(t.dotLanes, [0, 2]); XCTAssertEqual(t.pointLanes.count, t.points.count)
        XCTAssertEqual(emitterCCTraceLane(t, atBeat: 1.0), 0, "before lane 3's hit the value is lane 1's"); XCTAssertEqual(emitterCCTraceLane(t, atBeat: 2.5), 2, "after it, lane 3's")
        XCTAssertEqual(emitterCCTraceLane(t, atBeat: 3.99), 2, "…until the bar wraps"); XCTAssertNil(emitterCCTraceLane(emitterCCTrace(cfg: cfg(.riff), hits: [], barBeats: 4), atBeat: 1))
        // a RIFF rest makes no dot, but the lane in effect stays the previous one's
        let r = emitterCCTrace(cfg: cfg(.riff), hits: [EmitterCCTraceHit(beat: 0, rank: 8, lane: 1), EmitterCCTraceHit(beat: 2, rank: 0, lane: 3)], barBeats: 4)
        XCTAssertEqual(r.dotLanes, [1]); XCTAssertEqual(emitterCCTraceLane(r, atBeat: 3), 1, "a rest holds the previous value — and its lane")
    }
    func testAPingPongTraceStartsOnLowAndAlternatesWhateverTheRanks() {
        let c = EmitterCCCfg(EmitterCC(on: true, valueMode: .pingPong, high: 120, low: 10, travel: .step))
        let t = emitterCCTrace(cfg: c, hits: (0..<4).map { EmitterCCTraceHit(beat: Double($0), rank: 0, lane: 0, ordinal: Int64($0)) }, barBeats: 4)
        XCTAssertEqual(t.dots.map { Int($0.y) }, [10, 120, 10, 120], "the first hit is LOW; ranks (rests included) are not read")
        let g = emitterCCTrace(cfg: EmitterCCCfg(EmitterCC(on: true, valueMode: .pingPong, high: 120, low: 0, travel: .glide, time: 100)), hits: (0..<4).map { EmitterCCTraceHit(beat: Double($0), rank: 1, lane: 0, ordinal: Int64($0)) }, barBeats: 4)
        XCTAssertEqual(value(g, at: 0), 0); XCTAssertEqual(value(g, at: 0.5), 60); XCTAssertEqual(value(g, at: 1), 120); XCTAssertEqual(value(g, at: 1.5), 60, "a triangle rising from LOW")
    }
    func testASliderIsDimmedExactlyWhenItChangesNothing() {
        for m in EmitterCCValueMode.allCases { for t in EmitterCCTravel.allCases {
            XCTAssertEqual(emitterCCFieldIsInert(.passes, mode: m, travel: t), m != .ramp, "PASSES is RAMP's span: inert in every other mode")
            XCTAssertEqual(emitterCCFieldIsInert(.time, mode: m, travel: t), t == .step, "TIME is the ramp's share of the gap: a STEP has no ramp")
            for f in [EmitterCCField.high, .low, .mute] { XCTAssertFalse(emitterCCFieldIsInert(f, mode: m, travel: t), "\(f) is read in every mode and travel (LOW is FALL's target)") }
        } }
        XCTAssertEqual(EmitterCCField.allCases.count, 5, "HIGH · LOW · PASSES · TIME · MUTE")
    }
    func testARampTraceClimbsFromLowToHighAcrossTheSpan() {
        let c = EmitterCCCfg(EmitterCC(on: true, valueMode: .ramp, high: 120, low: 0, travel: .step, passes: 1))
        let t = emitterCCTrace(cfg: c, hits: (0..<4).map { EmitterCCTraceHit(beat: Double($0), rank: 0, lane: 0, ordinal: Int64($0), passHits: 4) }, barBeats: 4)
        XCTAssertEqual(t.dots.map { Int($0.y) }, [0, 40, 80, 120], "LOW on the first hit, HIGH on the last, evenly between")
        // over two passes the SAME bar shows the first or the second half of the climb, by the hits' ordinals
        let c2 = EmitterCCCfg(EmitterCC(on: true, valueMode: .ramp, high: 120, low: 0, travel: .step, passes: 2))
        let first = emitterCCTrace(cfg: c2, hits: (0..<4).map { EmitterCCTraceHit(beat: Double($0), rank: 0, lane: 0, ordinal: Int64($0), passHits: 4) }, barBeats: 4)
        let second = emitterCCTrace(cfg: c2, hits: (0..<4).map { EmitterCCTraceHit(beat: Double($0), rank: 0, lane: 0, ordinal: Int64(4 + $0), passHits: 4) }, barBeats: 4)
        XCTAssertEqual(first.dots.map { Int($0.y) }, [0, 17, 34, 51]); XCTAssertEqual(second.dots.map { Int($0.y) }, [69, 86, 103, 120], "the second pass ends on HIGH")
    }
    func testAPingPongBarWithAnOddNumberOfHitsFlipsItsParityAcrossTheSeam() {
        // 3 hits a bar, ordinals 3 4 5 (odd, even, odd = HIGH, LOW, HIGH): the next bar's first hit is ordinal 6 (even: LOW) and the previous bar's last is 2 (even: LOW)
        let c = EmitterCCCfg(EmitterCC(on: true, valueMode: .pingPong, high: 120, low: 0, travel: .glide, time: 100))
        let t = emitterCCTrace(cfg: c, hits: [(0.0, 3), (1.0, 4), (2.0, 5)].map { EmitterCCTraceHit(beat: $0.0, rank: 0, lane: 0, ordinal: $0.1) }, barBeats: 4)
        XCTAssertEqual(t.dots.map { Int($0.y) }, [120, 0, 120])
        XCTAssertEqual(value(t, at: 2), 120); XCTAssertEqual(value(t, at: 3), 60, "the last hit (HIGH) glides on toward the next bar's first hit, which is LOW (ordinal 6), over the 2-beat gap")
        XCTAssertEqual(value(t, at: 94.0 / 24), 5, "…and is nearly there at the bar's end")
        XCTAssertEqual(value(t, at: 0), 120, "this bar's first hit (ordinal 3, odd) is HIGH")
    }
    func testTheRingLandsExactlyOnEachDotWhenThePlayheadReachesIt() {
        for (travel, mode) in [(EmitterCCTravel.step, EmitterCCValueMode.riff), (.glide, .riff), (.fall, .riff), (.glide, .pingPong), (.fall, .pingPong), (.step, .ramp), (.glide, .ramp), (.fall, .ramp)] {
            let c = EmitterCCCfg(EmitterCC(on: true, valueMode: mode, high: 120, low: 10, travel: travel, time: 60))
            let hits = [(0.0, 1), (1.0, 5), (2.5, 3), (3.25, 8)].enumerated().map { EmitterCCTraceHit(beat: $0.element.0, rank: $0.element.1, lane: 0, ordinal: Int64($0.offset), passHits: 4) }
            let t = emitterCCTrace(cfg: c, hits: hits, barBeats: 4)
            for d in t.dots {
                let ring = emitterCCTraceValue(t.points, atBeat: Double(d.x))
                XCTAssertEqual(ring ?? -1, Double(d.y), accuracy: 0.5, "\(travel)/\(mode): the ring is on the dot at beat \(d.x)")
            }
        }
        // between two samples it interpolates along the drawn line; outside the bar it clamps; nothing to ride ⇒ nil
        let line = [CGPoint(x: 0, y: 0), CGPoint(x: 1, y: 100), CGPoint(x: 2, y: 50)]
        XCTAssertEqual(emitterCCTraceValue(line, atBeat: 0.5) ?? -1, 50, accuracy: 1e-9); XCTAssertEqual(emitterCCTraceValue(line, atBeat: 1.5) ?? -1, 75, accuracy: 1e-9)
        XCTAssertEqual(emitterCCTraceValue(line, atBeat: -1) ?? -1, 0, accuracy: 1e-9); XCTAssertEqual(emitterCCTraceValue(line, atBeat: 9) ?? -1, 50, accuracy: 1e-9)
        XCTAssertNil(emitterCCTraceValue([], atBeat: 1)); XCTAssertNil(emitterCCTraceValue([CGPoint(x: 0, y: 1)], atBeat: 0))
    }
}
