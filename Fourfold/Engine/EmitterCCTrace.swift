//  EmitterCCTrace.swift — CC tab: the one-bar picture of what an emitter sends (pure; Foundation + CoreGraphics only, in the test target).
//
//  The page gathers the hits of every lane routed to an emitter (a beat inside the bar and the riff's WRITTEN rank at that hit) and this file turns them into the curve the engine's STEP / GLIDE / FALL segments would draw, so the picture
//  and the Router's `ccOnHit` agree on what a hit sends and where a ramp goes. The painter (`CCPanelViews.swift`) only draws what comes back.

import Foundation
import CoreGraphics

// MARK: - the trace: one bar of the emitter's output

/// A hit of a lane routed to the emitter, at a beat inside the bar; `rank` is the riff grid's WRITTEN rank (1…8) at the riff playhead of the lane whose hit it is, 0 for a column with no note (a RIFF rest holds the previous value).
/// `lane` is the lane (0…3) whose hit it is (the dots and the playhead wear its colour); `ordinal` is that lane's riff ordinal at the hit (PING-PONG reads its parity — the Router's `advOrd`).
struct EmitterCCTraceHit: Equatable { var beat: Double; var rank: Int; var lane: Int = 0; var ordinal: Int64 = 0; var passHits: Int = 1 }   // `passHits`: the lane's hits per pass (RAMP's span unit)
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
/// The CC value a hit carries — the engine's own `EmitterCCCfg.value(rank:ordinal:)`: FIXED `level`; RIFF LOW + (rank − 1)/7 × (HIGH − LOW), nil for a rest (rank 0); PING-PONG HIGH on an even ordinal, LOW on an odd one.
func emitterCCHitValue(_ cfg: EmitterCCCfg, rank: Int, ordinal: Int64 = 0, span: EmitterCCRiffSpan = .full, passHits: Int = 1) -> Int? { cfg.value(rank: rank, ordinal: ordinal, span: span, passHits: passHits) }
/// The emitter's output over one bar from the merged, time-ordered hits, mirroring the Router's segments: STEP holds the hit value; GLIDE holds for gap × (1 − t) then ramps to the NEXT hit's value (the hit's own value when the next hit is
/// a rest), arriving on it; FALL ramps to LOW over gap × t and holds. gap = the time to the next hit (the first hit of the next bar after the last). The bar repeats, so a position before the first hit reads the last hit's segment of the
/// previous bar.
func emitterCCTrace(cfg: EmitterCCCfg, hits rawHits: [EmitterCCTraceHit], barBeats: Double, gridBeats step: Double = 1, span: EmitterCCRiffSpan = .full) -> EmitterCCTrace {
    let bar = max(0.25, barBeats)
    let hits = rawHits.filter { $0.beat >= 0 && $0.beat < bar }.sorted { $0.beat < $1.beat }
    var grid: [Double] = []
    var g = 0.0
    while g < bar - 1e-9 { grid.append(g); g += max(0.125, step) }
    guard !hits.isEmpty else { return EmitterCCTrace(points: [], dots: [], ticks: [], gridBeats: grid, barBeats: bar) }
    let n = hits.count
    let t = Double(cfg.time) / 100
    // hit k's absolute time on the unrolled timeline (k may run past n or below 0 for the neighbouring bars)
    func at(_ k: Int) -> Double { let lap = Int((Double(k) / Double(n)).rounded(.down)); return hits[k - lap * n].beat + Double(lap) * bar }
    // A lane's riff ordinal advances by the number of its hits in a bar, so the bar before / after this one carries each hit's ordinal ∓ that — which matters to PING-PONG (an odd count flips the parity every bar: the segment that glides on into
    // the next bar aims at the OTHER value, and the one before the first hit was left by the previous bar's opposite parity).
    var perBar: [Int: Int64] = [:]
    for h in hits { perBar[h.lane, default: 0] += 1 }
    func value(_ k: Int) -> Int? { let lap = Int((Double(k) / Double(n)).rounded(.down)); let h = hits[k - lap * n]; return emitterCCHitValue(cfg, rank: h.rank, ordinal: h.ordinal &+ Int64(lap) &* (perBar[h.lane] ?? 0), span: span, passHits: h.passHits) }
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
        let te = at(e), gap = max(1e-9, at(e + 1) - te)
        switch cfg.travel {
        case .step: return (v, lane)
        case .glide:
            let nextV = value(e + 1) ?? v
            let hold = gap * (1 - t)
            if b - te < hold { return (v, lane) }
            if b - te >= gap - 1e-9 { return (nextV, lane) }
            let f = (b - te - hold) / max(1e-9, gap * t)
            return (Int((Double(v) + (Double(nextV) - Double(v)) * f).rounded()), lane)
        case .fall:
            let ramp = gap * t
            if b - te >= ramp { return (cfg.low, lane) }
            let f = (b - te) / max(1e-9, ramp)
            return (Int((Double(v) + (Double(cfg.low) - Double(v)) * f).rounded()), lane)
        }
    }
    var pts: [CGPoint] = [], ptLanes: [Int] = []
    let steps = Int((bar * 24).rounded())
    for i in 0...steps {
        let b = Double(i) / 24
        guard let o = output(at: min(b, bar - 1e-9)) else { continue }
        pts.append(CGPoint(x: b, y: Double(max(0, min(127, o.value))))); ptLanes.append(o.lane)
    }
    var dots: [CGPoint] = [], dotLanes: [Int] = []
    for h in hits { if let v = emitterCCHitValue(cfg, rank: h.rank, ordinal: h.ordinal, span: span, passHits: h.passHits) { dots.append(CGPoint(x: h.beat, y: Double(v))); dotLanes.append(h.lane) } }
    return EmitterCCTrace(points: pts, pointLanes: ptLanes, dots: dots, dotLanes: dotLanes, ticks: hits.map { $0.beat }, gridBeats: grid, barBeats: bar)
}
/// The lane whose hit is in effect at bar position `beat` (the nearest drawn point at or before it), nil when the trace is empty.
func emitterCCTraceLane(_ t: EmitterCCTrace, atBeat beat: Double) -> Int? {
    var best: Int? = nil
    for (i, p) in t.points.enumerated() where Double(p.x) <= beat + 1e-9 && i < t.pointLanes.count { best = t.pointLanes[i] }
    return best ?? t.pointLanes.first
}

// MARK: - which controls matter

/// The five bar sliders of an emitter's page.
enum EmitterCCField: Int, CaseIterable { case high, low, passes, time, mute }
/// True when a slider changes nothing in the emitter's current VALUE and TRAVEL — the page dims exactly these, so a live slider is always one that does something. HIGH and LOW are the RIFF map's ends, PING-PONG's two values and RAMP's two ends (and LOW is
/// FALL's target); PASSES is RAMP's span; TIME is the ramp's share of the gap to the next hit, which only GLIDE and FALL have; MUTE is always read.
func emitterCCFieldIsInert(_ f: EmitterCCField, mode: EmitterCCValueMode, travel: EmitterCCTravel) -> Bool {
    switch f {
    case .passes: return mode != .ramp
    case .time: return travel == .step
    case .high, .low, .mute: return false
    }
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
