//  EmitterCCTrace.swift — CC tab: the one-bar picture of what an emitter sends (pure; Foundation + CoreGraphics only, in the test target).
//
//  The page gathers the hits of every lane routed to an emitter (a beat inside the bar and the riff's WRITTEN rank at that hit), `emitterCCMergeHits` makes them the emitter's ONE hit stream, and `emitterCCTrace` turns that into the curve the engine's
//  hold-then-ramp shape would draw — through the SAME `EmitterCCCfg.value` and `emitterCCShape` the Router uses, so the picture and the Router's `ccOnHit` agree on what a hit sends and where a ramp goes. The painter (`CCPanelViews.swift`) only draws
//  what comes back.

import Foundation
import CoreGraphics

// MARK: - the trace: one bar of the emitter's output

/// A hit of a lane routed to the emitter, at a beat inside the bar; `rank` is the riff grid's WRITTEN rank (1…8) at the riff playhead of the lane whose hit it is, 0 for a column with no note (a RIFF rest: no new value, the current shape continues).
/// `lane` is the lane (0…3) whose hit it is (the dots and the playhead wear its colour); `ordinal` is that lane's riff ordinal at the hit (PING-PONG reads its parity, CLIMB its place in the span — the Router's `advOrd`); `passHits` is the lane's hits per
/// pass (CLIMB's span unit); `barHits` is how many hits the lane has in the bar (its ordinal advances by that each bar; 0 ⇒ counted from the events); `count` / `routed` are the merged event's lane count (HITS).
struct EmitterCCTraceHit: Equatable { var beat: Double; var rank: Int; var lane: Int = 0; var ordinal: Int64 = 0; var passHits: Int = 1; var barHits: Int = 0; var count: Int = 1; var routed: Int = 1 }
/// Several lanes routed to one emitter hit as ONE stream (amendment 1): hits on the same step (the same beat, within 1e-6) are ONE event, read from the first of them in lane order, whose `count` is how many lanes hit and whose `routed` is the number of lanes
/// routed here and not stopped or muted. Sorted by beat.
func emitterCCMergeHits(_ raw: [EmitterCCTraceHit], routed: Int) -> [EmitterCCTraceHit] {
    let sorted = raw.sorted { $0.beat != $1.beat ? $0.beat < $1.beat : $0.lane < $1.lane }
    var out: [EmitterCCTraceHit] = []
    for h in sorted {
        if var last = out.last, abs(last.beat - h.beat) < 1e-6 { last.count += 1; out[out.count - 1] = last; continue }
        var e = h; e.count = 1; e.routed = max(1, routed); out.append(e)
    }
    return out
}
struct EmitterCCTrace: Equatable {
    /// The output sampled on the 1/96-note grid across the bar: `(beat, value)`, value 0…127 (what the engine would send, rounded). Empty when no hit lands in the bar (the emitter would be silent).
    var points: [CGPoint]
    /// The lane whose hit is in effect at each point (parallel to `points`) — the lane that set the value being drawn.
    var pointLanes: [Int] = []
    /// A dot on each hit that carries a value: `(beat, value)`, and the lane each belongs to (parallel).
    var dots: [CGPoint]
    var dotLanes: [Int] = []
    /// Every hit's beat (the ticks under the trace), rests included.
    var ticks: [Double]
    /// The step grid's lines (beats).
    var gridBeats: [Double]
    var barBeats: Double
}
/// The CC value a hit carries — the engine's own `EmitterCCCfg.value(rank:ordinal:span:passHits:count:routed:)`: HITS LOW + count/routed × (HIGH − LOW); RIFF the rank's value over the riff's span, nil for a rest (rank 0); PING-PONG LOW on an even ordinal,
/// HIGH on an odd one; CLIMB the hit's place in the span.
func emitterCCHitValue(_ cfg: EmitterCCCfg, rank: Int, ordinal: Int64 = 0, span: EmitterCCRiffSpan = .full, passHits: Int = 1, count: Int = 1, routed: Int = 1) -> Int? {
    cfg.value(rank: rank, ordinal: ordinal, span: span, passHits: passHits, count: count, routed: routed)
}
/// The emitter's output over one bar from its merged, time-ordered hit events (`emitterCCMergeHits`), mirroring the Router's shape (amendment 1): at each hit the value jumps to the hit value, HOLDs it for `hold` % of the gap, RAMPs over the effective ramp
/// (`min(ramp, 100 − hold)` % of the gap; 0 ⇒ jump to the target at the end of the hold) along the curve to the target — LOW (REST) or the next event's value (NEXT; the hit's own value when the next is a RIFF rest) — and sits at the target until the next
/// hit. gap = the time to the next hit (the first hit of the next bar after the last). The bar repeats, so a position before the first hit reads the last hit's shape from the previous bar. A RIFF rest carries no value: the previous shape continues.
func emitterCCTrace(cfg: EmitterCCCfg, hits rawHits: [EmitterCCTraceHit], barBeats: Double, gridBeats step: Double = 1, span: EmitterCCRiffSpan = .full) -> EmitterCCTrace {
    let bar = max(0.25, barBeats)
    let hits = rawHits.filter { $0.beat >= 0 && $0.beat < bar }.sorted { $0.beat < $1.beat }
    var grid: [Double] = []
    var g = 0.0
    while g < bar - 1e-9 { grid.append(g); g += max(0.125, step) }
    guard !hits.isEmpty else { return EmitterCCTrace(points: [], dots: [], ticks: [], gridBeats: grid, barBeats: bar) }
    let n = hits.count
    let holdF = Double(cfg.hold) / 100, rampF = Double(cfg.effectiveRamp) / 100
    // hit k's absolute time on the unrolled timeline (k may run past n or below 0 for the neighbouring bars)
    func at(_ k: Int) -> Double { let lap = Int((Double(k) / Double(n)).rounded(.down)); return hits[k - lap * n].beat + Double(lap) * bar }
    // A lane's riff ordinal advances by the number of its hits in a bar, so the bar before / after this one carries each hit's ordinal ∓ that — which matters to PING-PONG (an odd count flips the parity every bar: the segment that glides on into
    // the next bar aims at the OTHER value, and the one before the first hit was left by the previous bar's opposite parity) and to CLIMB.
    var perBar: [Int: Int64] = [:]
    for h in hits { perBar[h.lane, default: 0] += 1 }
    func value(_ k: Int) -> Int? {
        let lap = Int((Double(k) / Double(n)).rounded(.down)); let h = hits[k - lap * n]
        let adv = Int64(h.barHits > 0 ? h.barHits : Int(perBar[h.lane] ?? 0))
        return emitterCCHitValue(cfg, rank: h.rank, ordinal: h.ordinal &+ Int64(lap) &* adv, span: span, passHits: h.passHits, count: h.count, routed: h.routed)
    }
    func laneOf(_ k: Int) -> Int { let lap = Int((Double(k) / Double(n)).rounded(.down)); return hits[k - lap * n].lane }
    // the latest hit that carries a value at or before beat b (searching backwards across bars), or nil when none carries one
    func lastEvent(atOrBefore b: Double) -> Int? {
        var k = n - 1
        // the latest k with at(k) <= b, on the unrolled timeline
        while k >= 0 && at(k) > b + 1e-9 { k -= 1 }
        var tries = 0
        while tries <= n {
            let kk = k - tries
            if value(kk) != nil { return kk }
            tries += 1
        }
        return nil
    }
    func output(at b: Double) -> (value: Int, lane: Int)? {
        guard let e = lastEvent(atOrBefore: b), let v = value(e) else { return nil }
        let lane = laneOf(e)
        let te = at(e), gap = max(1e-9, at(e + 1) - te), el = b - te
        let holdT = gap * holdF, rampT = gap * rampF
        if el < holdT - 1e-9 { return (v, lane) }
        let target = cfg.hold >= 100 ? v : (cfg.to == .rest ? cfg.low : (value(e + 1) ?? v))   // HOLD 100 % = steps: the value stays until a new one arrives
        if rampT <= 1e-9 || el >= holdT + rampT - 1e-9 { return (target, lane) }   // no ramp: it jumps to the target at the end of the hold; after the ramp it sits there
        let f = (el - holdT) / rampT
        return (Int((Double(v) + (Double(target) - Double(v)) * emitterCCShape(f, curve: cfg.curve)).rounded()), lane)
    }
    var pts: [CGPoint] = [], ptLanes: [Int] = []
    let steps = Int((bar * 24).rounded())
    for i in 0...steps {
        let b = Double(i) / 24
        guard let o = output(at: min(b, bar - 1e-9)) else { continue }
        pts.append(CGPoint(x: b, y: Double(max(0, min(127, o.value))))); ptLanes.append(o.lane)
    }
    var dots: [CGPoint] = [], dotLanes: [Int] = []
    for h in hits { if let v = emitterCCHitValue(cfg, rank: h.rank, ordinal: h.ordinal, span: span, passHits: h.passHits, count: h.count, routed: h.routed) { dots.append(CGPoint(x: h.beat, y: Double(v))); dotLanes.append(h.lane) } }
    return EmitterCCTrace(points: pts, pointLanes: ptLanes, dots: dots, dotLanes: dotLanes, ticks: hits.map { $0.beat }, gridBeats: grid, barBeats: bar)
}
/// The lane whose hit is in effect at bar position `beat` (the nearest drawn point at or before it), nil when the trace is empty.
func emitterCCTraceLane(_ t: EmitterCCTrace, atBeat beat: Double) -> Int? {
    var best: Int? = nil
    for (i, p) in t.points.enumerated() where Double(p.x) <= beat + 1e-9 && i < t.pointLanes.count { best = t.pointLanes[i] }
    return best ?? t.pointLanes.first
}

// MARK: - which controls matter

/// The six bar sliders of an emitter's page.
enum EmitterCCField: Int, CaseIterable { case high, low, hold, ramp, passes, mute }
/// True when a control changes nothing in the emitter's current settings — the page dims exactly these (they stay usable), so a live control is always one that does something (amendment 1): RAMP and TO have nothing to work with when HOLD is 100 (the hit's
/// value is held for the whole gap); CURVE shapes a ramp that is 0 when HOLD is 100 or RAMP is 0; PASSES is CLIMB's span; HIGH, LOW, HOLD and MUTE are always read (LOW is also the REST target).
func emitterCCFieldIsInert(_ f: EmitterCCField, _ cc: EmitterCC) -> Bool {
    switch f {
    case .ramp: return cc.hold >= 100
    case .passes: return cc.valueMode != .climb
    case .high, .low, .hold, .mute: return false
    }
}
func emitterCCToIsInert(_ cc: EmitterCC) -> Bool { cc.hold >= 100 }
func emitterCCCurveIsInert(_ cc: EmitterCC) -> Bool { cc.effectiveRamp == 0 }

/// Sliding the CC NUMBER on an emitter's page: up raises it, `emitterCCNumberDragPointsPerStep` points a step, pinned to 0…`EmitterCC.maxCC`. Relative to where the touch began, so the first touch never jumps the value.
let emitterCCNumberDragPointsPerStep: CGFloat = 3
func emitterCCNumberDrag(start: Int, travelUp: CGFloat) -> Int {
    let steps = Int((travelUp / emitterCCNumberDragPointsPerStep).rounded())
    return max(0, min(EmitterCC.maxCC, start + steps))
}

/// The drawn curve's value (0…127) at bar position `beat`, interpolated along the same polyline the page strokes — so a marker riding it lands exactly on the static dots when the playhead reaches them. nil with fewer than two points.
func emitterCCTraceValue(_ points: [CGPoint], atBeat beat: Double) -> Double? {
    guard points.count > 1 else { return nil }
    if beat <= Double(points[0].x) { return Double(points[0].y) }
    var i = 1
    while i < points.count && Double(points[i].x) < beat { i += 1 }
    if i >= points.count { return Double(points[points.count - 1].y) }
    let a = points[i - 1], b = points[i]
    let w = Double(b.x - a.x)
    return w > 1e-12 ? Double(a.y) + (Double(b.y) - Double(a.y)) * (beat - Double(a.x)) / w : Double(b.y)
}

/// A trace point in a tile `size` (value 127 at the top, 0 at the bottom; beat 0 at the left, the bar's end at the right).
func emitterCCTracePoint(_ p: CGPoint, barBeats: Double, size: CGSize, inset: CGFloat = 0) -> CGPoint {
    CGPoint(x: inset + CGFloat(p.x / max(1e-9, barBeats)) * (size.width - 2 * inset), y: inset + (1 - CGFloat(p.y) / 127) * (size.height - 2 * inset))
}
