//  LaneStripBands.swift — LANE STRIP BANDS ferry (2026-11-12; Fourfold only): the lane card's top strip
//  re-banded into a riff HEADER (joined to PLAY RIFF along the top), the CELLS (steps/hits + per-rank sounding
//  outlines), and a stack FOOTER (joined to PLAY STACK along the bottom), with a faint CC trace across the
//  cells. Foundation + CoreGraphics only (the macOS test target compiles this file directly): every frame,
//  colour, outline rect and the CC source choice are decided — and tested — here; the Canvas painter
//  (`LaneStripPainter.swift`) draws these and nothing else. Display only; nothing here is saved, sounded or sent.
//
//  T = 44 (Paul 2026-11-12: the spec's reference height 78 is screenshot pixels, like the play-buttons
//  amendment's "78 was screenshot px"; keep 44). So the strip is compact — `laneStripBandHeights` gives
//  hH 10 / hC 20, and the rank slot is 1.375 pt, so the §4.5 filled-bar fallback (and the §1.4 hC < 30 floor)
//  are active on every layout, by Paul's choice.

import Foundation
import CoreGraphics

// MARK: - §1 / §13: the band metrics (named so device can tune them; this ferry changes none)

enum LaneStripBandMetrics {
    /// §B2.1: header/footer height = max(8, round(T × this)); the cells band is what's left less the two row gaps.
    static let headerRatio = 0.22                       // amendment 1: was 0.23
    static let rowGap: CGFloat = 1                       // amendment 1: was 2
    /// §B2.2 / §B2.3: a chip is EXACTLY its cell's x/width at the band's full height (no shrink, no width cap), radius
    /// `chipRadius`, label `chipLabel` pt heavy, ink `chipInk`, no tracking; resting opacity `chipRestOpacity`, sounding 1
    /// with an inner `soundStroke` stroke (§B2.4). A label hides when the chip is narrower than count·`chipLabelAdvance`·size + 2.
    static let chipRadius: CGFloat = 2                   // amendment 1: was 4
    static let chipLabel: CGFloat = 7                    // amendment 1: was 10 (and 9 over 12 steps) — now a flat 7
    static let chipLabelAdvance: CGFloat = 0.6           // heavy-monospaced digit advance ÷ point size (§B2.3 label-fit)
    static let chipRestOpacity = 0.78
    static let chipInk = EuclideousRGB(r: 0x0D, g: 0x0F, b: 0x14)
    /// §B2.4: a sounding chip draws at 100 % with a 1 pt #F2F4F7 stroke INSIDE its frame (replaces the old outside ring).
    static let soundStroke = EuclideousRGB(r: 0xF2, g: 0xF4, b: 0xF7)
    /// §3.6: an off part's chips — outline only (1 pt #3A3D44 inner stroke), label #5A5E66, no ring.
    static let offChipStroke = EuclideousRGB(r: 0x3A, g: 0x3D, b: 0x44), offChipLabel = EuclideousRGB(r: 0x5A, g: 0x5E, b: 0x66)
    /// §B2.6: the ANSWER line along the footer track's inside-bottom edge — 1.5 pt, source lane100 @ 70 %, radius 1.
    static let answerLineH: CGFloat = 1.5, answerLineAlpha = 0.7, answerLineRadius: CGFloat = 1

    /// §4.2: cell fills — a step not under / under the playhead; a hit not under / under the playhead takes lane100 at
    /// `hitAlpha`/`hitPlayheadAlpha` with the 3 pt lane100 bottom bar. No strike flash, glow or ease.
    static let stepFill = EuclideousRGB(r: 0x2A, g: 0x2C, b: 0x33)
    static let playheadStepFill = EuclideousRGB(r: 0x3A, g: 0x3D, b: 0x44)
    static let hitAlpha = 0.30, hitPlayheadAlpha = 0.45
    static let bottomBarH: CGFloat = 3, cellRadius: CGFloat = 6
    /// §B4.1: the rank slots — 1 below the cell's top to 1 above its 3 pt bottom bar, split 8 ways (slot = (hC−5)/8). §B4.2:
    /// a sounding rank is a FILLED bar, height max(1, slot−0.5), radius 0.5, centred in its slot — riff inset 2 / stack inset 4
    /// (§B4.3 under a 12 pt cell: riff 1 / stack 3). §B4.4: only where the slot is ≥ 4 is it the old 1 pt stroked outline instead.
    static let slotPad: CGFloat = 1, outlineStroke: CGFloat = 1, outlineRadius: CGFloat = 1.5, slotInsetTB: CGFloat = 0.4
    static let riffInset: CGFloat = 2, stackInset: CGFloat = 4, riffInsetNarrow: CGFloat = 1, stackInsetNarrow: CGFloat = 3, narrowCell: CGFloat = 12
    static let slotFallback: CGFloat = 4, barMinH: CGFloat = 1, barRadius: CGFloat = 0.5

    /// §5.4 / §13: the CC trace — line/hit-dot/playhead-dot alphas over white, dot sizes, samples per step.
    static let ccLineAlpha = 0.20, ccHitDotAlpha = 0.35, ccPlayheadDotAlpha = 0.55
    static let ccHitDot: CGFloat = 3, ccPlayheadDot: CGFloat = 4, ccSamplesPerStep = 8
    static let ccInk = EuclideousRGB(r: 0xF2, g: 0xF4, b: 0xF7)

    /// §2: the joined buttons' chrome — the tile fill/border (never dimmed), the track's far-corner radius.
    static let tileFill = EuclideousRGB(r: 0x20, g: 0x22, b: 0x26), tileBorder = EuclideousRGB(r: 0x2B, g: 0x2D, b: 0x33)
    static let trackCornerRadius: CGFloat = 6
}

// MARK: - §1.4: the three band heights

struct LaneStripBandHeights: Equatable { var hH: CGFloat; var hC: CGFloat; var gap: CGFloat }
/// §B2.1: header/footer `hH = max(8, round(T × 0.22))`; the cells band `hC = T − 2·hH − 2·gap`, gap 1. (T 44 → hH 10, hC 22; T 78 → hH 17, hC 42.)
func laneStripBandHeights(T: CGFloat) -> LaneStripBandHeights {
    let hH = max(8, (T * LaneStripBandMetrics.headerRatio).rounded())
    let gap = LaneStripBandMetrics.rowGap
    return LaneStripBandHeights(hH: hH, hC: max(0, T - 2 * hH - 2 * gap), gap: gap)
}

// MARK: - §8.1 / §1: the top-row frames (one pure function; every layout)

/// §8.1 — every frame of the lane card's top row in CONTENT-box-local coordinates (origin at the content box's
/// top-left). A 5-column grid PLAY RIFF (w) | bridge (g) | strip | bridge (g) | PLAY STACK (w); the strip holds a
/// header (hH), the cells (hC) and a footer (hH), 2 pt gaps between. Both buttons span the full height T; the header
/// bridge sits in the header row only (between PLAY RIFF and the header), the footer bridge in the footer row only
/// (between the footer and PLAY STACK) — the other two bridge slots are empty. The header/cells/footer share ONE
/// column layout (`euclidEvenBoxGeometry`, today's 2 pt cell gap). `stackNameWidth` is the measured width of "STACK"
/// at §2.2's name size (the caller measures it in the real font); `w = ceil(stackNameWidth + 8)` (§1.3), both buttons.
struct LaneStripFrames: Equatable {
    var topRow: CGRect
    var leadTile: CGRect        // PLAY RIFF (w × T)
    var trailTile: CGRect       // PLAY STACK (w × T)
    var headerBridge: CGRect    // g × hH, header row, between leadTile and the strip
    var footerBridge: CGRect    // g × hH, footer row, between the strip and trailTile
    var strip: CGRect           // the middle column, full height T
    var header: CGRect          // the header track (strip's header band)
    var cells: CGRect           // the cells band
    var footer: CGRect          // the footer track (strip's footer band)
    var columnXs: [CGFloat]     // each step's left edge WITHIN the strip (0-based, before strip.minX)
    var columnW: CGFloat
    var w: CGFloat, g: CGFloat, T: CGFloat, hH: CGFloat, hC: CGFloat, gap: CGFloat

    /// A step's cell rect (in content-local coords).
    func cell(_ i: Int) -> CGRect { slot(i, y: cells.minY, h: hC) }
    /// A step's header chip slot (the full header-band column).
    func headerSlot(_ i: Int) -> CGRect { slot(i, y: header.minY, h: hH) }
    /// A step's footer chip slot (the full footer-band column).
    func footerSlot(_ i: Int) -> CGRect { slot(i, y: footer.minY, h: hH) }
    private func slot(_ i: Int, y: CGFloat, h: CGFloat) -> CGRect {
        guard i >= 0 && i < columnXs.count else { return .zero }
        return CGRect(x: strip.minX + columnXs[i], y: y, width: columnW, height: h)
    }
}

func laneTopRowFrames(T: CGFloat, content: CGSize, g: CGFloat, stackNameWidth: CGFloat, steps: Int) -> LaneStripFrames {
    let b = laneStripBandHeights(T: T)
    let w = (stackNameWidth + 8).rounded(.up)                       // §1.3: "STACK" + 4 each side, rounded up
    let leadTile = CGRect(x: 0, y: 0, width: w, height: T)
    let trailTile = CGRect(x: max(w, content.width - w), y: 0, width: w, height: T)
    let stripMinX = leadTile.maxX + g
    let stripMaxX = trailTile.minX - g
    let stripW = max(1, stripMaxX - stripMinX)
    let strip = CGRect(x: stripMinX, y: 0, width: stripW, height: T)
    let header = CGRect(x: stripMinX, y: 0, width: stripW, height: b.hH)
    let cells = CGRect(x: stripMinX, y: b.hH + b.gap, width: stripW, height: b.hC)
    let footer = CGRect(x: stripMinX, y: T - b.hH, width: stripW, height: b.hH)
    let headerBridge = CGRect(x: leadTile.maxX, y: 0, width: g, height: b.hH)
    let footerBridge = CGRect(x: stripMaxX, y: T - b.hH, width: g, height: b.hH)
    let geo = euclidEvenBoxGeometry(n: max(1, steps), g: 4, usableWidth: stripW)   // §1.6: today's even column layout (2 pt gap)
    return LaneStripFrames(topRow: CGRect(x: 0, y: 0, width: content.width, height: T),
                           leadTile: leadTile, trailTile: trailTile, headerBridge: headerBridge, footerBridge: footerBridge,
                           strip: strip, header: header, cells: cells, footer: footer,
                           columnXs: geo.xs, columnW: geo.stepW, w: w, g: g, T: T, hH: b.hH, hC: b.hC, gap: b.gap)
}

// MARK: - §1.6: the per-step band slots (built once per frame from the columns the strip already lays out)

/// The three bands' per-step frames in strip-local coordinates (origin at the strip's top-left), from the SAME column
/// xs/width the strip's cells use (so a header or footer slot sits exactly above/below its cell). `xs[i]` is step i's left
/// edge; `columnW` its width; `T` the strip height.
struct LaneStripBandFrames: Equatable {
    var bands: LaneStripBandHeights
    var cells: [CGRect]        // the cells band (y hH+gap, height hC)
    var header: [CGRect]       // the header chip slots (y 0, height hH)
    var footer: [CGRect]       // the footer chip slots (y T−hH, height hH)
}
func laneStripBandFrames(xs: [CGFloat], columnW: CGFloat, T: CGFloat) -> LaneStripBandFrames {
    let b = laneStripBandHeights(T: T)
    let cellsY = b.hH + b.gap, footerY = T - b.hH
    return LaneStripBandFrames(bands: b,
        cells: xs.map { CGRect(x: $0, y: cellsY, width: columnW, height: b.hC) },
        header: xs.map { CGRect(x: $0, y: 0, width: columnW, height: b.hH) },
        footer: xs.map { CGRect(x: $0, y: footerY, width: columnW, height: b.hH) })
}

/// §B2.2: the chip is EXACTLY its cell's x/width at the band's full height — no shrink, no 30-cap.
func laneStripChipFrame(slot: CGRect) -> CGRect { slot }
/// §B2.3: the chip label's point size — a flat 7 pt heavy (was 10, and 9 over 12 steps).
func laneStripChipLabelSize(steps: Int) -> CGFloat { LaneStripBandMetrics.chipLabel }
/// §B2.3: a label's drawn width (heavy monospaced: count · advance · size); hidden when the chip is narrower than this + 2.
func laneStripChipLabelFits(_ label: String, chipWidth: CGFloat, size: CGFloat) -> Bool {
    chipWidth >= CGFloat(label.count) * LaneStripBandMetrics.chipLabelAdvance * size + 2
}

// MARK: - §8.2: the stack chip colour (OKLCH, the lane's own hue)

/// How many OKLCH → sRGB conversions the stack-chip table cost — 32, once; a test reads it (it must never grow).
private(set) var stackChipConversionCount = 0
/// The 4 × 8 table (lane-major): `L = 0.60 + (rank − 1) × 0.32 ÷ 7`, `C = 0.10` (riff map's constants), `h` = the lane's
/// own lane100 OKLCH hue. Built once.
private let stackChipTable: [EuclideousRGB] = {
    var t: [EuclideousRGB] = []; t.reserveCapacity(32)
    for lane in 0..<4 {
        let h = euclideousOKLCH(euclideousLaneRGB[lane]).h * Double.pi / 180
        for rank in 1...8 {
            stackChipConversionCount += 1
            let L = RiffMapTuning.lightnessFloor + Double(rank - 1) * RiffMapTuning.lightnessRange / 7
            t.append(euclideousRGBFromOKLab(L: L, a: RiffMapTuning.chroma * cos(h), b: RiffMapTuning.chroma * sin(h)))
        }
    }
    return t
}()
/// §8.2: the stack footer chip's / stack rank outline's colour for a lane (0…3) and rank (1…8) — the lane's hue at the
/// rank's lightness. A table read, never a conversion.
func stackChipColour(lane: Int, rank: Int) -> EuclideousRGB {
    stackChipTable[max(0, min(3, lane)) * 8 + max(1, min(8, rank)) - 1]
}

// MARK: - §8.3 / §4.3–4.5: a rank's outline (or fallback bar) inside a hit cell

enum LaneStripPart: Equatable { case riff, stack }
/// The mark for a sounding rank in a hit cell: a 1 pt stroked outline, or — where the slot is under `slotFallback` (it
/// is, at T 44) — a filled 1 pt bar (`filled`). The painter strokes an outline / fills a bar; the colour comes from the
/// part (`riffMapColour` for riff, `stackChipColour` for stack).
struct LaneRankMark: Equatable { var rect: CGRect; var filled: Bool }
func rankSlotRect(cell: CGRect, hC: CGFloat, rank: Int, part: LaneStripPart) -> LaneRankMark {
    typealias M = LaneStripBandMetrics
    let r = max(1, min(8, rank))
    let slot = (hC - M.slotPad - (M.slotPad + M.bottomBarH)) / 8        // §B4.1: (hC − 1 − 4) ÷ 8
    let slotTop = cell.minY + M.slotPad + CGFloat(8 - r) * slot          // rank 1 at the bottom, rank 8 at the top
    let narrow = cell.width < M.narrowCell                               // §B4.3
    let sideInset = part == .riff ? (narrow ? M.riffInsetNarrow : M.riffInset) : (narrow ? M.stackInsetNarrow : M.stackInset)
    let x = cell.minX + sideInset, width = max(0, cell.width - 2 * sideInset)
    if slot < M.slotFallback {                                           // §B4.2/§B4.4: a filled bar (the outline is only for slot ≥ 4)
        let barH = max(M.barMinH, slot - 0.5)
        return LaneRankMark(rect: CGRect(x: x, y: slotTop + (slot - barH) / 2, width: width, height: barH), filled: true)
    }
    return LaneRankMark(rect: CGRect(x: x, y: slotTop + M.slotInsetTB, width: width, height: max(0, slot - 2 * M.slotInsetTB)), filled: false)
}

// MARK: - §8.6 / §4.2: a cell's look

/// §4.2: the fill a cell takes. `hit` uses lane100 at the given alpha (the painter supplies the lane colour); a step uses
/// a flat grey. No cell ever takes lane100 at 100 %, and nothing glows.
enum LaneCellFill: Equatable { case step, playheadStep, hit(alpha: Double) }
struct LaneCellLook: Equatable { var fill: LaneCellFill; var bar: Bool }
func stripCellLook(isHit: Bool, isPlayhead: Bool) -> LaneCellLook {
    typealias M = LaneStripBandMetrics
    if isHit { return LaneCellLook(fill: .hit(alpha: isPlayhead ? M.hitPlayheadAlpha : M.hitAlpha), bar: true) }
    return LaneCellLook(fill: isPlayhead ? .playheadStep : .step, bar: false)
}

/// §1.7 / §4.2: the step the rhythm sweep is on now (the playhead cell), from the strip's raw tick; nil while stopped.
func euclideousStripPlayheadStep(raw: Double, n: Int, dir: EuclidDir) -> Int? {
    guard n > 0 else { return nil }
    var s = Int(euclidCometPos(raw, n: n, dir: dir).rounded(.down))   // the continuous 0…n screen position, floored to a step
    if s < 0 { s = 0 }; if s >= n { s = n - 1 }
    return s
}

// MARK: - §8 / §5.1: the CC source emitter

/// §5.1: the first emitter in A–D (0…3) order that this lane's riff OR stack routes to (`routed`, the OR of the two
/// resolved output masks) and that has CC on (`ccOn`, bit o = `emitterCCs[o].on`). nil ⇒ no trace. The output-muted /
/// stopped suppression (§5.6) is applied where the trace is drawn, not here.
func laneCCSourceEmitter(routed: UInt8, ccOn: UInt8) -> Int? {
    for o in 0..<4 where (routed >> UInt8(o)) & 1 != 0 && (ccOn >> UInt8(o)) & 1 != 0 { return o }
    return nil
}

// MARK: - §8.5 / §5: the CC trace across the cells

/// §5.3: the emitter's CC output (from the SAME `emitterCCTrace` the CC tab draws — no second derivation) mapped onto the
/// strip's step axis. x: step k at cell k's left edge, `samplesPerStep` samples a step; y: value 127 at the cells' top,
/// 0 just above the bottom bar. The emitter's output is bar-periodic (`points`/`dots` over `barBeats`); a step's time is
/// read at its phase in the bar (the pass is taken to start on a bar line — exact when it does; a flagged approximation
/// otherwise). `value(atBeat:)` is `emitterCCTraceValue` passed in, so the mapping stays Foundation-only and testable.
struct LaneCCStripTrace: Equatable { var line: [CGPoint]; var dots: [CGPoint]; var playhead: CGPoint? }
func laneCCStripTrace(dots rawDots: [CGPoint], sub: Double, barBeats: Double, cellXs: [CGFloat], columnW: CGFloat,
                      cellsRect: CGRect, bottomBarH: CGFloat, samplesPerStep: Int,
                      playheadStepFloat: Double? = nil, playheadValue: Double? = nil, value: (Double) -> Double?) -> LaneCCStripTrace {
    let n = cellXs.count
    guard n > 0, sub > 0, barBeats > 0 else { return LaneCCStripTrace(line: [], dots: [], playhead: nil) }
    let pitch: CGFloat = n > 1 ? cellXs[1] - cellXs[0] : columnW
    func x(_ stepFloat: Double) -> CGFloat {
        let k = max(0, min(n - 1, Int(stepFloat.rounded(.down))))
        let x0 = cellXs[k], x1 = k + 1 < n ? cellXs[k + 1] : cellXs[k] + pitch
        return x0 + CGFloat(stepFloat - Double(k)) * (x1 - x0)
    }
    func y(_ v: Double) -> CGFloat { cellsRect.minY + (1 - CGFloat(max(0, min(127, v)) / 127)) * max(0, cellsRect.height - bottomBarH) }
    func phase(_ bp: Double) -> Double { let r = bp.truncatingRemainder(dividingBy: barBeats); return r < 0 ? r + barBeats : r }
    var line: [CGPoint] = []
    let total = n * max(1, samplesPerStep)
    for i in 0...total {
        let bp = Double(i) * sub / Double(max(1, samplesPerStep))
        if let v = value(phase(bp)) { line.append(CGPoint(x: x(Double(i) / Double(max(1, samplesPerStep))), y: y(v))) }
    }
    var dots: [CGPoint] = []
    for d in rawDots {
        let bp = Double(d.x)
        guard bp >= 0, bp < Double(n) * sub + 1e-9 else { continue }   // a hit inside the shown pass
        dots.append(CGPoint(x: x(bp / sub), y: y(Double(d.y))))
    }
    var playhead: CGPoint? = nil
    if let sf = playheadStepFloat, let pv = playheadValue { playhead = CGPoint(x: x(max(0, min(Double(n), sf))), y: y(pv)) }   // §5.4: the current sweep x and value
    return LaneCCStripTrace(line: line, dots: dots, playhead: playhead)
}

// MARK: - §3.3 / §3.4 / §4.4 / §4.6: the sounding held sets (fed from the note feed, mapped to steps by onset)

/// What sounds in one frame, per step. §4.6: a note "enters the set of the hit cell where it started" — `stepOf`
/// maps a note's onset beat to its step (the same sweep that places the playhead, so a display can't disagree with the
/// engine). The riff part rings/outlines at the step's own written rank (`riffRing`); the stack part carries its
/// authored rank (`stackChip` = the lowest played here for the footer label; `stackOutline` = the ranks sounding now,
/// one per voice). A note counts only once it reached an emitter (`outs != 0`, the lamp's gate).
struct LaneStripSounding: Equatable {
    var riffRing: [Bool]        // per step: a riff note that started here is sounding (header ring + the cell's riff outline)
    var stackChip: [Int?]       // per step: the lowest stack rank played here in the current pass (the footer chip), nil = none
    var stackRing: [Bool]       // per step: a stack note that started here is sounding (footer ring)
    var stackOutline: [[Int]]   // per step: the stack ranks sounding now (the cell's stack outlines, one per voice)
}
/// §B1.1: the step a NOTE whose sweep position is `raw` belongs to — the NEAREST step (round), not the floored
/// playhead cell, so a note struck at a step's leading edge lands on that step and not the one before it (the
/// amendment-1 slot bug: the footer used `euclideousStripPlayheadStep`'s `.rounded(.down)`, one step early).
func euclideousStripNoteStep(raw: Double, n: Int, dir: EuclidDir) -> Int? {
    guard n > 0 else { return nil }
    var s = Int(euclidCometPos(raw, n: n, dir: dir).rounded())
    if s < 0 { s = 0 }; if s >= n { s = n - 1 }
    return s
}

/// §B1.1 / §B1.3: snap a note's step to the authored HIT step whose cell lights for it — the nearest hit step,
/// ties to the earlier one. A late note (long gate, TIE, a ratchet strike, a delayed / held pool) reaches a step
/// after its hit's; snapping keeps its chip and rank mark in the hit's own slot. `hitSteps` must be ascending.
func laneStripSnapToHitStep(_ raw: Int, hitSteps: [Int]) -> Int {
    guard let first = hitSteps.first else { return raw }
    var best = first, bestD = abs(first - raw)
    for s in hitSteps.dropFirst() { let d = abs(s - raw); if d < bestD { best = s; bestD = d } }   // strict `<` keeps the earlier hit on a tie
    return best
}

func laneStripSounding(riffHeld: [NoteRollNote], stackHeld: [NoteRollNote], n: Int, now: Double, passBeats: Double, stepOf: (Double) -> Int, hitSteps: [Int]) -> LaneStripSounding {
    var riffRing = [Bool](repeating: false, count: max(0, n))
    var stackChip = [Int?](repeating: nil, count: max(0, n))
    var stackRing = [Bool](repeating: false, count: max(0, n))
    var stackOutline = [[Int]](repeating: [], count: max(0, n))
    // §B1: everything is indexed by the hit's own step — the rounded sweep step snapped to the nearest authored hit.
    func hitStep(_ onBeat: Double) -> Int { laneStripSnapToHitStep(stepOf(onBeat), hitSteps: hitSteps) }
    for note in riffHeld where note.outs != 0 && note.onBeat <= now && euclideousMixNoteSounds(note, at: now) {
        let s = hitStep(note.onBeat)
        if s >= 0 && s < n { riffRing[s] = true }
    }
    for note in stackHeld where note.outs != 0 && note.onBeat <= now {
        let sounding = euclideousMixNoteSounds(note, at: now)
        guard sounding || note.onBeat >= now - passBeats else { continue }   // §3.3: a played hit keeps its chip for the rest of the pass
        let s = hitStep(note.onBeat); let r = Int(note.rank)
        guard s >= 0 && s < n, r >= 1 && r <= 8 else { continue }
        if stackChip[s] == nil || r < stackChip[s]! { stackChip[s] = r }
        if sounding {
            stackRing[s] = true
            if !stackOutline[s].contains(r) { stackOutline[s].append(r) }
        }
    }
    return LaneStripSounding(riffRing: riffRing, stackChip: stackChip, stackRing: stackRing, stackOutline: stackOutline)
}
