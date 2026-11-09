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
    func testAPingPongTraceAlternatesHighAndLowWhateverTheRanks() {
        let c = EmitterCCCfg(EmitterCC(on: true, valueMode: .pingPong, high: 120, low: 10, travel: .step))
        let t = emitterCCTrace(cfg: c, hits: (0..<4).map { EmitterCCTraceHit(beat: Double($0), rank: 0, lane: 0, ordinal: Int64($0)) }, barBeats: 4)
        XCTAssertEqual(t.dots.map { Int($0.y) }, [120, 10, 120, 10], "ranks (rests included) are not read")
        let g = emitterCCTrace(cfg: EmitterCCCfg(EmitterCC(on: true, valueMode: .pingPong, high: 120, low: 0, travel: .glide, time: 100)), hits: (0..<4).map { EmitterCCTraceHit(beat: Double($0), rank: 1, lane: 0, ordinal: Int64($0)) }, barBeats: 4)
        XCTAssertEqual(value(g, at: 0.5), 60); XCTAssertEqual(value(g, at: 1), 0); XCTAssertEqual(value(g, at: 1.5), 60, "a triangle")
    }
    func testASliderIsDimmedExactlyWhenItChangesNothing() {
        typealias F = EmitterCCField
        func inert(_ mode: EmitterCCValueMode, _ travel: EmitterCCTravel) -> Set<Int> { Set(F.allCases.filter { emitterCCFieldIsInert($0, mode: mode, travel: travel) }.map { $0.rawValue }) }
        let bars = F.bars.rawValue
        XCTAssertEqual(inert(.fixed, .step), [F.high.rawValue, F.low.rawValue, bars, F.time.rawValue])
        XCTAssertEqual(inert(.fixed, .glide), [F.high.rawValue, F.low.rawValue, bars], "GLIDE reads TIME; FIXED reads neither HIGH nor LOW")
        XCTAssertEqual(inert(.fixed, .fall), [F.high.rawValue, bars], "FALL's target is LOW")
        XCTAssertEqual(inert(.riff, .step), [F.level.rawValue, bars, F.time.rawValue]); XCTAssertEqual(inert(.riff, .fall), [F.level.rawValue, bars])
        XCTAssertEqual(inert(.pingPong, .glide), [F.level.rawValue, bars]); XCTAssertEqual(inert(.pingPong, .step), [F.level.rawValue, bars, F.time.rawValue])
        for t in EmitterCCTravel.allCases { XCTAssertEqual(inert(.sine, t), [F.level.rawValue, F.time.rawValue], "SINE reads HIGH, LOW and BARS only (no hits, so no TIME, whatever the travel)") }
        for m in EmitterCCValueMode.allCases { for t in EmitterCCTravel.allCases { XCTAssertFalse(emitterCCFieldIsInert(.mute, mode: m, travel: t), "MUTE is always read") } }
        XCTAssertTrue(emitterCCTravelIsInert(mode: .sine)); XCTAssertFalse(emitterCCTravelIsInert(mode: .riff)); XCTAssertFalse(emitterCCTravelIsInert(mode: .pingPong)); XCTAssertFalse(emitterCCTravelIsInert(mode: .fixed))
    }
    func testTheSineTraceIsTheEnginesSineOverTheBarItIsIn() {
        var c = EmitterCCCfg(EmitterCC(on: true, valueMode: .sine, high: 120, low: 0, sineBars: 3))   // 1 bar a cycle
        let t = emitterCCSineTrace(cfg: c, barStartBeat: 0, barBeats: 4)
        XCTAssertEqual(t.count, 97); XCTAssertEqual(Int(t[0].y), 0, "a cycle starts at LOW"); XCTAssertEqual(Int(t[48].y), 120, "…crests half way"); XCTAssertEqual(Int(t[96].y), 0, "…and is back at the bar line")
        XCTAssertEqual(Int(t[24].y), 60, "a quarter in it is half way up")
        // a 4-bar cycle: bar 2 (beats 4…8) is the slice from a quarter to a half of the cycle — it rises from half way to the crest
        c = EmitterCCCfg(EmitterCC(on: true, valueMode: .sine, high: 120, low: 0, sineBars: 5))
        let b2 = emitterCCSineTrace(cfg: c, barStartBeat: 4, barBeats: 4)
        XCTAssertEqual(Int(b2[0].y), 60); XCTAssertEqual(Int(b2[96].y), 120)
        XCTAssertEqual(Int(emitterCCSineTrace(cfg: c, barStartBeat: 12, barBeats: 4)[96].y), 0, "the fourth bar ends the cycle back at LOW")
        // LOW above HIGH inverts it
        let inv = emitterCCSineTrace(cfg: EmitterCCCfg(EmitterCC(on: true, valueMode: .sine, high: 0, low: 100)), barStartBeat: 0, barBeats: 4)
        XCTAssertEqual(Int(inv[0].y), 100); XCTAssertEqual(Int(inv[48].y), 0)
    }
    func testAPingPongBarWithAnOddNumberOfHitsFlipsItsParityAcrossTheSeam() {
        // 3 hits a bar, ordinals 3 4 5 (HIGH-LOW-HIGH reading 120 / 0 / 120 is for even / odd / even... here 3 is odd, so LOW-HIGH-LOW): the next bar's first hit is ordinal 6 (even: HIGH) and the previous bar's last is 2 (even: HIGH)
        let c = EmitterCCCfg(EmitterCC(on: true, valueMode: .pingPong, high: 120, low: 0, travel: .glide, time: 100))
        let t = emitterCCTrace(cfg: c, hits: [(0.0, 3), (1.0, 4), (2.0, 5)].map { EmitterCCTraceHit(beat: $0.0, rank: 0, lane: 0, ordinal: $0.1) }, barBeats: 4)
        XCTAssertEqual(t.dots.map { Int($0.y) }, [0, 120, 0])
        XCTAssertEqual(value(t, at: 2), 0); XCTAssertEqual(value(t, at: 3), 60, "the last hit (LOW) glides on toward the next bar's first hit, which is HIGH (ordinal 6), over the 2-beat gap")
        XCTAssertEqual(value(t, at: 94.0 / 24), 115, "…and is nearly there at the bar's end")
        // before the first hit the previous bar's last hit (ordinal 2, HIGH) is still gliding to this bar's first (LOW): it is wrapped values, here the very top of the bar
        XCTAssertEqual(value(t, at: 0), 0)
    }
}
