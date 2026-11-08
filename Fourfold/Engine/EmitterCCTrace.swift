//  EmitterCCTrace.swift — CC tab: the one-bar picture of what an emitter sends (pure; Foundation + CoreGraphics only, in the test target).
//
//  The page gathers the hits of every lane routed to an emitter (a beat inside the bar and the riff's WRITTEN rank at that hit) and this file turns them into the curve the engine's STEP / GLIDE / FALL segments would draw, so the picture
//  and the Router's `ccOnHit` agree on what a hit sends and where a ramp goes. The painter (`CCPanelViews.swift`) only draws what comes back.

import Foundation
import CoreGraphics

// MARK: - the trace: one bar of the emitter's output

/// A hit of a lane routed to the emitter, at a beat inside the bar; `rank` is the riff grid's WRITTEN rank (1…8) at the riff playhead of the lane whose hit it is, 0 for a column with no note (a RIFF rest holds the previous value).
struct EmitterCCTraceHit: Equatable { var beat: Double; var rank: Int }
struct EmitterCCTrace: Equatable {
    /// The output sampled on the 1/96-note grid across the bar: `(beat, value)`, value 0…127 (what the engine would send, rounded). Empty when no hit lands in the bar (the emitter would be silent).
    var points: [CGPoint]
    /// A dot on each hit that carries a value: `(beat, value)`.
    var dots: [CGPoint]
    /// Every hit's beat (the ticks under the trace), rests included.
    var ticks: [Double]
    /// The step grid's lines (beats).
    var gridBeats: [Double]
    var barBeats: Double
}
/// The CC value a hit carries: FIXED — `level`; RIFF — LOW + (rank − 1)/7 × (HIGH − LOW) (the engine's `riffValue`); nil for a RIFF rest (rank 0).
func emitterCCHitValue(_ cfg: EmitterCCCfg, rank: Int) -> Int? {
    if cfg.valueMode == .fixed { return cfg.fixedValue }
    return rank >= 1 && rank <= 8 ? cfg.riffValue(rank: rank) : nil
}
/// The emitter's output over one bar from the merged, time-ordered hits, mirroring the Router's segments: STEP holds the hit value; GLIDE holds for gap × (1 − t) then ramps to the NEXT hit's value (the hit's own value when the next hit is
/// a rest), arriving on it; FALL ramps to LOW over gap × t and holds. gap = the time to the next hit (the first hit of the next bar after the last). The bar repeats, so a position before the first hit reads the last hit's segment of the
/// previous bar.
func emitterCCTrace(cfg: EmitterCCCfg, hits rawHits: [EmitterCCTraceHit], barBeats: Double, gridBeats step: Double = 1) -> EmitterCCTrace {
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
    func value(_ k: Int) -> Int? { let lap = Int((Double(k) / Double(n)).rounded(.down)); return emitterCCHitValue(cfg, rank: hits[k - lap * n].rank) }
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
    func output(at b: Double) -> Int? {
        guard let e = lastEvent(atOrBefore: b), let v = value(e) else { return nil }
        let te = at(e), gap = max(1e-9, at(e + 1) - te)
        switch cfg.travel {
        case .step: return v
        case .glide:
            let nextV = value(e + 1) ?? v
            let hold = gap * (1 - t)
            if b - te < hold { return v }
            if b - te >= gap - 1e-9 { return nextV }
            let f = (b - te - hold) / max(1e-9, gap * t)
            return Int((Double(v) + (Double(nextV) - Double(v)) * f).rounded())
        case .fall:
            let ramp = gap * t
            if b - te >= ramp { return cfg.low }
            let f = (b - te) / max(1e-9, ramp)
            return Int((Double(v) + (Double(cfg.low) - Double(v)) * f).rounded())
        }
    }
    var pts: [CGPoint] = []
    let steps = Int((bar * 24).rounded())
    for i in 0...steps {
        let b = Double(i) / 24
        guard let v = output(at: min(b, bar - 1e-9)) else { continue }
        pts.append(CGPoint(x: b, y: Double(max(0, min(127, v)))))
    }
    let dots = hits.compactMap { h -> CGPoint? in emitterCCHitValue(cfg, rank: h.rank).map { CGPoint(x: h.beat, y: Double($0)) } }
    return EmitterCCTrace(points: pts, dots: dots, ticks: hits.map { $0.beat }, gridBeats: grid, barBeats: bar)
}
/// A trace point in a tile `size` (value 127 at the top, 0 at the bottom; beat 0 at the left, the bar's end at the right).
func emitterCCTracePoint(_ p: CGPoint, barBeats: Double, size: CGSize, inset: CGFloat = 0) -> CGPoint {
    CGPoint(x: inset + CGFloat(p.x / max(1e-9, barBeats)) * (size.width - 2 * inset), y: inset + (1 - CGFloat(p.y) / 127) * (size.height - 2 * inset))
}
