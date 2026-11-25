//  ResetsTileV3.swift — RESETS V3 ferry (2026-11-24) §2: the ONE tile per RESETS card. Pure (Foundation + CoreGraphics); the Canvas (`ResetsTileV3View`) draws from these, and the §5 tests pin the frames + the block/span data (the drawing itself is device-owed).
//
//  One 46-tall tile with TWO block rows on ONE ruler — passes (RHYTHM) above, riff cycles (MELODY) below — a shared span so all four cards show the same window (§2.4), one playhead and a "still to come" dim across both (§2.9), two "N OF M" values (§2.10), and a host-bar/beat grid over the blocks (§2.7). No hatching anywhere: a cut pass/cycle ends at a tick in the lane's light tone (§2.6).

import Foundation
import CoreGraphics

enum EuclideousResetsTileMetrics {
    static let height: CGFloat = 46          // §2.2
    static let padV: CGFloat = 8, padLead: CGFloat = 10, padTrail: CGFloat = 10   // §2.3
    static let labelX: CGFloat = 10, labelW: CGFloat = 54
    static let rulerX: CGFloat = 72          // §2.3 ruler from x 72 …
    static let rulerTrailGap: CGFloat = 84   // … to TW − 84
    static let rulerTop: CGFloat = 8, rulerHeight: CGFloat = 30    // y 8 … 38
    static let rowTopInset: CGFloat = 2, rowHeight: CGFloat = 10   // rhythm y+2…+12
    static let melodyRowTopInset: CGFloat = 18                     // melody y+18…+28
    static let valueW: CGFloat = 66, valueTrail: CGFloat = 10      // value column, trailing edge TW − 10
    static let blockHeight: CGFloat = 10, blockGap: CGFloat = 1.5, blockRadius: CGFloat = 2   // §2.5
    static let cutTickW: CGFloat = 2, cutTickExtra: CGFloat = 2, cutTickInset: CGFloat = 2.5, cutTickRadius: CGFloat = 1   // §2.6 (14 tall = row 10 + 2 above + 2 below)
    static let denseFloor: CGFloat = 4       // §2.8 blocks under this wide ⇒ no gaps
    static let cutTickMinApart: CGFloat = 3  // §2.8 drop cut ticks closer than this
    static let gridMinApart: CGFloat = 4     // §2.7 beats/bars closer than this: drop / every-4th
}

/// §2.3 — the tile's inner frames, tile-LOCAL (origin = the tile's top-left). `tw` is the tile width TW.
struct EuclideousResetsTileFrames: Equatable {
    var ruler: CGRect, rhythmRow: CGRect, melodyRow: CGRect
    var rhythmLabel: CGRect, melodyLabel: CGRect, rhythmValue: CGRect, melodyValue: CGRect
    var rulerWidth: CGFloat { ruler.width }
}
func euclideousResetsTileFrames(tw: CGFloat) -> EuclideousResetsTileFrames {
    typealias M = EuclideousResetsTileMetrics
    let rw = max(0, tw - M.rulerTrailGap - M.rulerX)
    let ruler = CGRect(x: M.rulerX, y: M.rulerTop, width: rw, height: M.rulerHeight)
    let rhythmRow = CGRect(x: ruler.minX, y: ruler.minY + M.rowTopInset, width: rw, height: M.rowHeight)
    let melodyRow = CGRect(x: ruler.minX, y: ruler.minY + M.melodyRowTopInset, width: rw, height: M.rowHeight)
    func label(_ row: CGRect) -> CGRect { CGRect(x: M.labelX, y: row.midY - 7, width: M.labelW, height: 14) }
    func value(_ row: CGRect) -> CGRect { CGRect(x: tw - M.valueTrail - M.valueW, y: row.midY - 8, width: M.valueW, height: 16) }
    return EuclideousResetsTileFrames(ruler: ruler, rhythmRow: rhythmRow, melodyRow: melodyRow,
                                      rhythmLabel: label(rhythmRow), melodyLabel: label(melodyRow),
                                      rhythmValue: value(rhythmRow), melodyValue: value(melodyRow))
}

/// §2.4 — the span both rows share, at the UI beat. ALL set ⇒ ALL's current link; else the rhythm set's span; else the melody set's; else the host bar holding `beat`. (A stopped transport passes the playhead's frozen beat.)
func euclideousResetsTileSpan(cfg c: EuclideousWalkLaneConfig, allChain: [UInt8], barBeats: Double, beat: Double) -> (start: Double, len: Double) {
    let eps = 1e-9
    if !allChain.isEmpty, barBeats > 0 {
        let prev = euclideousAllRestartAtOrBefore(beat: beat, barBeats: barBeats, chain: allChain)
        let next = euclideousNextAllRestart(after: prev, barBeats: barBeats, chain: allChain) ?? (prev + barBeats)
        if next > prev + eps { return (prev, next - prev) }
    }
    var chains = c.chains
    let lap = Double(max(1, euclidCycleLen(c.dir, n: c.n))) * c.sub
    chains.lapBeats = lap
    if chains.hasRhythmRestarts {
        let o = chains.rhythmOriginBeat(beat), n = chains.nextRhythmRestart(after: beat) ?? (o + max(lap, barBeats))
        if n > o + eps { return (o, n - o) }
    }
    if chains.hasMelodyRestarts {
        let o = chains.melodyOriginBeat(beat), n = chains.nextMelodyRestart(after: beat) ?? (o + max(lap, barBeats))
        if n > o + eps { return (o, n - o) }
    }
    let s = barBeats > 0 ? (beat / barBeats).rounded(.down) * barBeats : 0
    return (s, max(eps, barBeats))
}

/// §2.5/§2.6 — one row's blocks (passes for RHYTHM, riff cycles for MELODY) that overlap the DISPLAY window [start, start+len). Each block carries its REAL cut flag (cut at the row's OWN next restart, not the display edge — the Canvas clips at the edges, never marks a clip as a cut). Bounded loops.
func euclideousResetsRowBlocks(kind: EuclideousRestartKind, cfg c: EuclideousWalkLaneConfig, displayStart: Double, displayLen: Double) -> [EuclideousRestartRulerBlock] {
    let eps = 1e-9
    let sub = c.sub
    guard sub > 0, c.n > 0, displayLen > eps else { return [] }
    let displayEnd = displayStart + displayLen
    var chains = c.chains
    let lap = Double(max(1, euclidCycleLen(c.dir, n: c.n))) * sub
    chains.lapBeats = lap
    var out: [EuclideousRestartRulerBlock] = []
    switch kind {
    case .rhythm:
        let isSet = chains.hasRhythmRestarts
        var q = chains.passIndex(beat: displayStart + eps)
        var guardN = 0
        while guardN < 8192 {
            let s = chains.passStart(q)
            if s >= displayEnd - eps { break }
            let end = chains.passStart(q + 1)
            let cut = isSet && (end - s) < lap - eps                 // a pass shorter than a full lap ended at a rhythm restart
            if end > displayStart + eps { out.append(.init(start: s, end: end, cut: cut)) }   // overlaps the window
            q += 1; guardN += 1
        }
    case .melody:
        let isSet = chains.hasMelodyRestarts
        var curTick = isSet ? chains.melodyOriginTick(displayStart + eps, sub: sub) : euclideousFreeMelodyCycleStartTickV3(c, beforeBeat: displayStart)
        var guardN = 0
        while guardN < 8192 {
            let startBeat = Double(curTick) * sub
            if startBeat >= displayEnd - eps { break }
            let naturalEnd = Double(euclideousMelodyCycleCompletionTickV3(c, fromTick: curTick)) * sub
            let nextRestart = isSet ? chains.nextMelodyRestart(after: startBeat) : nil
            let end = (nextRestart.map { $0 < naturalEnd - eps } ?? false) ? nextRestart! : naturalEnd
            let cut = end < naturalEnd - eps
            if end > displayStart + eps { out.append(.init(start: startBeat, end: end, cut: cut)) }
            if end <= startBeat + eps { break }                      // no-progress safety
            curTick = Int64((end / sub + eps).rounded(.down))
            guardN += 1
        }
    }
    return out
}

/// §2.7 — the host grid over the blocks: a bar line at each host bar line strictly inside the span, a beat line at each other host beat. Returns x (ruler-local, 0…rulerWidth) + whether it's a bar line. Density: beat lines closer than 4 pt are dropped; bar lines closer than 4 pt draw every 4th.
func euclideousResetsHostGridLines(spanStart: Double, spanLen: Double, barBeats: Double, rulerWidth: CGFloat) -> [(x: CGFloat, bar: Bool)] {
    let eps = 1e-9
    guard spanLen > eps, barBeats > eps, rulerWidth > 0 else { return [] }
    let perBeat = rulerWidth / CGFloat(spanLen)                      // px per beat
    let beatsClose = perBeat < EuclideousResetsTileMetrics.gridMinApart
    let barsClose = perBeat * CGFloat(barBeats) < EuclideousResetsTileMetrics.gridMinApart
    var out: [(CGFloat, Bool)] = []
    // every host BEAT strictly inside the span
    let firstBeat = Int64((spanStart + eps).rounded(.down)) + 1
    let lastBeat = Int64((spanStart + spanLen - eps).rounded(.up)) - 1
    guard lastBeat >= firstBeat else { return [] }
    var b = firstBeat
    while b <= lastBeat {
        let beat = Double(b)
        if beat > spanStart + eps && beat < spanStart + spanLen - eps {
            let isBar = barBeats > 0 && abs((beat / barBeats).rounded() - beat / barBeats) < 1e-6
            let x = CGFloat((beat - spanStart) / spanLen) * rulerWidth
            if isBar {
                let barIndex = Int((beat / barBeats).rounded())
                if !barsClose || barIndex % 4 == 0 { out.append((x, true)) }   // §2.7 bar lines <4 pt apart ⇒ every 4th
            } else if !beatsClose {
                out.append((x, false))                                          // §2.7 beat lines <4 pt apart ⇒ dropped
            }
        }
        b += 1
    }
    return out
}

/// §5.3 — the tile's VoiceOver: "Rhythm, 8 of 16 steps; melody, 3 of 8 notes" (steps for ADV STEP melody), with ", free" after a free part.
func euclideousResetsTileVoiceOver(rhythmNM: (n: Int, m: Int)?, rhythmSet: Bool, melodyNM: (n: Int, m: Int)?, melodySet: Bool, advStep: Bool) -> String {
    var r = "Rhythm"
    if let nm = rhythmNM { r += ", \(nm.n) of \(nm.m) steps" }
    if !rhythmSet { r += ", free" }
    var m = "melody"
    if let nm = melodyNM { m += ", \(nm.n) of \(nm.m) \(advStep ? "steps" : "notes")" }
    if !melodySet { m += ", free" }
    return r + "; " + m
}

// Local copies of the two melody-cycle walkers (the originals are `private` to Derivations.swift); identical logic — RESETS V3's own row enumeration reads them.
private func euclideousMelodyCycleCompletionTickV3(_ c: EuclideousWalkLaneConfig, fromTick: Int64) -> Int64 {
    let L = max(1, min(c.columns, c.length))
    let order = euclideousRiffCycleOrder(dir: c.riffDir, length: L, stride: c.stride, shift: c.rotate, columns: c.columns)
    let cycleUnits = Int64(max(1, order.period * max(1, c.every)))
    if c.advanceStep { return fromTick + cycleUnits }
    let cycleLen = max(1, euclidCycleLen(c.dir, n: c.n))
    let bound = fromTick + Int64(cycleLen) * (cycleUnits + 2) + 32
    var t = fromTick, idx: Int64 = -1
    while t <= bound { if euclideousWalkTick(c, tick: t).isHit { idx += 1; if idx == cycleUnits { return t } }; t += 1 }
    return bound
}
private func euclideousFreeMelodyCycleStartTickV3(_ c: EuclideousWalkLaneConfig, beforeBeat: Double) -> Int64 {
    guard c.sub > 0 else { return 0 }
    let target = Int64((beforeBeat / c.sub + 1e-9).rounded(.down))
    var cur: Int64 = 0, guardN = 0
    while guardN < 4096 { let next = euclideousMelodyCycleCompletionTickV3(c, fromTick: cur); if next > target || next <= cur { return cur }; cur = next; guardN += 1 }
    return cur
}
