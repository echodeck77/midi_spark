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
    /// §B2.1 / PLAY-BUTTONS-RAIL §3.1: header/footer height = max(8, round(T × this)); the cells band is what's left
    /// after each ON part's reserve (rail + gap + band + gap). §10 tunable.
    static let headerRatio = 0.2                        // PLAY BUTTONS RAIL+NOTE §3.1: was 0.22 (amendment 1) / 0.23
    static let rowGap: CGFloat = 1                       // amendment 1: was 2
    /// PLAY BUTTONS RAIL+NOTE §2.1 / §10: the running-part rail — a 1.5 pt lane-colour line along the row's outer edge
    /// (riff top, stack bottom). Reserved by the band layout (rail 1.5 + gap 1 + band hH + gap 1 per on part); drawn in §2.
    static let railH: CGFloat = 1.5
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
    /// PLAY BUTTONS RAIL+NOTE §5.1 / §10: a stack hit the NOTES layer is predicted to play NOTHING on draws this flat #2B2D33 placeholder (no label, no stroke).
    static let emptySlotFill = EuclideousRGB(r: 0x2B, g: 0x2D, b: 0x33)
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

    /// §B2.1 / RAIL §3.1 — the ONE copy of the two formulas every consumer derives from (2026-11-16 review B1: they were
    /// re-derived inline in `laneStripBandFrames` and the PLAY tile's chip view — the drift class this project keeps hitting).
    static func bandH(T: CGFloat) -> CGFloat { max(8, (T * headerRatio).rounded()) }
    /// A running part's full reserve, outer edge → cells: rail 1.5 + gap 1 + band hH + gap 1.
    static func partReserve(hH: CGFloat) -> CGFloat { railH + rowGap + hH + rowGap }
}

// MARK: - §1.4: the three band heights

struct LaneStripBandHeights: Equatable { var hH: CGFloat; var hC: CGFloat; var gap: CGFloat }
/// PLAY BUTTONS RAIL+NOTE §3.1: `hH = max(8, round(T × 0.2))`; a part's reserve (outer→inner) is rail 1.5 + gap 1 + band
/// hH + gap 1, scaled by its presence fraction `riffFrac`/`stackFrac` (1 = in, 0 = collapsed, the cells extend to that
/// edge; a toggle eases between them, §3.4). `hC = T − riffFrac·reserve − stackFrac·reserve`. (T 44, both on → hH 9, hC 19;
/// one on → hC 31.5; both off → hC 44.) The spec's §3.2 example uses T 41 — the built T is 44 (source wins), so hC = 19 ≥ 16.
func laneStripBandHeights(T: CGFloat, riffFrac: Double = 1, stackFrac: Double = 1) -> LaneStripBandHeights {
    let hH = LaneStripBandMetrics.bandH(T: T)
    let reserve = LaneStripBandMetrics.partReserve(hH: hH)               // §3.1 full per-part reserve
    let hC = max(0, T - CGFloat(riffFrac) * reserve - CGFloat(stackFrac) * reserve)
    return LaneStripBandHeights(hH: hH, hC: hC, gap: LaneStripBandMetrics.rowGap)
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
    let railH = LaneStripBandMetrics.railH
    let strip = CGRect(x: stripMinX, y: 0, width: stripW, height: T)
    // PLAY BUTTONS RAIL+NOTE §3.1: the header band sits after the rail + gap; the cells after the full reserve; the footer a reserve up from the bottom.
    let headerY = railH + b.gap, cellsY = LaneStripBandMetrics.partReserve(hH: b.hH), footerY = T - railH - b.gap - b.hH
    let header = CGRect(x: stripMinX, y: headerY, width: stripW, height: b.hH)
    let cells = CGRect(x: stripMinX, y: cellsY, width: stripW, height: b.hC)
    let footer = CGRect(x: stripMinX, y: footerY, width: stripW, height: b.hH)
    let headerBridge = CGRect(x: leadTile.maxX, y: headerY, width: g, height: b.hH)
    let footerBridge = CGRect(x: stripMaxX, y: footerY, width: g, height: b.hH)
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
    var cells: [CGRect]        // the cells band (y cellsY, height hC)
    var header: [CGRect]       // the riff header chip slots (y headerY, height hH)
    var footer: [CGRect]       // the stack footer chip slots (y footerY, height hH)
    /// PLAY BUTTONS RAIL+NOTE §3: each part's presence 0…1 (the painter fades its band/chips by this and skips a 0 part);
    /// the rail height; and the bands' y positions (also the rail's y and the §4 note-chip height reference).
    var riffFrac: Double = 1, stackFrac: Double = 1
    var railH: CGFloat = LaneStripBandMetrics.railH
    var cellsY: CGFloat = 0, headerY: CGFloat = 0, footerY: CGFloat = 0
}
/// PLAY BUTTONS RAIL+NOTE §3.1/§3.3: the bands with each part's reserve scaled by its fraction. A part at 0 reserves nothing
/// (cells extend to that edge, no band drawn); at 1 the full rail 1.5 + gap 1 + band hH + gap 1. The header/footer sit at a
/// FIXED spot (rail + gap in from their edge) and are faded by the painter — the cells' own edge slides by `frac·reserve`.
func laneStripBandFrames(xs: [CGFloat], columnW: CGFloat, T: CGFloat, riffFrac: Double = 1, stackFrac: Double = 1) -> LaneStripBandFrames {
    let b = laneStripBandHeights(T: T, riffFrac: riffFrac, stackFrac: stackFrac)   // 2026-11-16 review B1: the ONE formula (it was re-derived inline here)
    let railH = LaneStripBandMetrics.railH
    let cellsY = CGFloat(riffFrac) * LaneStripBandMetrics.partReserve(hH: b.hH)
    let headerY = railH + b.gap, footerY = T - railH - b.gap - b.hH
    return LaneStripBandFrames(bands: b,
        cells: xs.map { CGRect(x: $0, y: cellsY, width: columnW, height: b.hC) },
        header: xs.map { CGRect(x: $0, y: headerY, width: columnW, height: b.hH) },
        footer: xs.map { CGRect(x: $0, y: footerY, width: columnW, height: b.hH) },
        riffFrac: riffFrac, stackFrac: stackFrac, railH: railH, cellsY: cellsY, headerY: headerY, footerY: footerY)
}

/// §B2.2: the chip is EXACTLY its cell's x/width at the band's full height — no shrink, no 30-cap.
func laneStripChipFrame(slot: CGRect) -> CGRect { slot }
/// §B2.3: the chip label's point size — a flat 7 pt heavy (was 10, and 9 over 12 steps).
func laneStripChipLabelSize(steps: Int) -> CGFloat { LaneStripBandMetrics.chipLabel }
/// §B2.3: a label's drawn width (heavy monospaced: count · advance · size); hidden when the chip is narrower than this + 2.
func laneStripChipLabelFits(_ label: String, chipWidth: CGFloat, size: CGFloat) -> Bool {
    chipWidth >= CGFloat(label.count) * LaneStripBandMetrics.chipLabelAdvance * size + 2
}

/// STACK GREY §2.3: the footer chip's segments for a step's played ranks across a frame of `frameWidth` — one per voice
/// (ascending `ranks`, lowest on the left, `gap` between), returned as (x offset from the frame's left, width, rank).
/// A split segment under `minSeg` wide ⇒ a single segment at the LOWEST rank spanning the whole frame (today's look).
func laneStripFooterSegments(frameWidth: CGFloat, ranks: [Int], gap: CGFloat = 1, minSeg: CGFloat = 4) -> [(x: CGFloat, width: CGFloat, rank: Int)] {
    guard let low = ranks.first, frameWidth > 1 else { return [] }
    let k = ranks.count
    if k == 1 { return [(0, frameWidth, low)] }
    let segW = (frameWidth - CGFloat(k - 1) * gap) / CGFloat(k)
    if segW < minSeg { return [(0, frameWidth, low)] }                   // §2.3 fallback: one chip at the lowest rank
    return ranks.enumerated().map { (CGFloat($0.offset) * (segW + gap), segW, $0.element) }
}

// MARK: - STACK RANKS GREY ferry (2026-11-15) §1: the neutral grey rank ramp
// (replaces §8.2's lane-hued `stackChipColour` — the stack now reads as grey on every lane, so lighter = higher is the
// riff map's shared language and lane colour stays the lane's identity. Riff chips/bars keep the riff map.)

/// §9: tunable on device (change none in THIS ferry). The ramp's OKLCH lightness floor and span.
enum StackRankTuning { static let lightnessFloor = 0.46, lightnessRange = 0.46 }   // §1.1: L 0.46 → 0.92 over the 8 ranks

/// §1.2: the WCAG 2.x relative luminance of an sRGB colour (grey ⇒ ≈ the channel's linear value).
private func stackRankLuminance(_ c: EuclideousRGB) -> Double {
    func lin(_ v: Int) -> Double { let s = Double(v) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
    return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
}
/// §1.2: the WCAG contrast ratio between two colours (≥ 1).
func euclideousWCAGContrast(_ a: EuclideousRGB, _ b: EuclideousRGB) -> Double {
    let la = stackRankLuminance(a), lb = stackRankLuminance(b)
    return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
}

/// How many OKLCH → sRGB conversions the grey rank-ramp table cost — 8, once; a test reads it (it must never grow).
private(set) var stackRankConversionCount = 0
/// §1.1/§1.2: the 8-entry ramp — a neutral grey (chroma 0, hue 0) at `L = 0.46 + (rank − 1) × 0.46 ÷ 7`, the SAME for every
/// lane, plus the ink (#0D0F14 or #F2F4F7) that has the higher WCAG contrast on it. Built once, the riff map's conversion.
private let stackRankTable: [(colour: EuclideousRGB, ink: EuclideousRGB)] = {
    let white = EuclideousRGB(r: 0xF2, g: 0xF4, b: 0xF7), ink = EuclideousRGB(r: 0x0D, g: 0x0F, b: 0x14)
    var t: [(colour: EuclideousRGB, ink: EuclideousRGB)] = []; t.reserveCapacity(8)
    for rank in 1...8 {
        stackRankConversionCount += 1
        let L = StackRankTuning.lightnessFloor + Double(rank - 1) * StackRankTuning.lightnessRange / 7
        let c = euclideousRGBFromOKLab(L: L, a: 0, b: 0)
        t.append((c, euclideousWCAGContrast(c, white) >= euclideousWCAGContrast(c, ink) ? white : ink))
    }
    return t
}()
/// §1.1: the stack footer chip's / stack rank bar's colour for a rank (1…8) — a neutral grey, dark at 1 to light at 8, the
/// SAME for every lane. A table read, never a conversion.
func stackRankColour(rank: Int) -> EuclideousRGB { stackRankTable[max(1, min(8, rank)) - 1].colour }
/// §1.2: the ink (#0D0F14 or #F2F4F7) that reads on `stackRankColour(rank)`.
func stackRankInk(rank: Int) -> EuclideousRGB { stackRankTable[max(1, min(8, rank)) - 1].ink }

// MARK: - §8.3 / §4.3–4.5: a rank's outline (or fallback bar) inside a hit cell

enum LaneStripPart: Equatable { case riff, stack }
/// The mark for a sounding rank in a hit cell: a 1 pt stroked outline, or — where the slot is under `slotFallback` (it
/// is, at T 44) — a filled 1 pt bar (`filled`). The painter strokes an outline / fills a bar; the colour comes from the
/// part (`riffMapColour` for riff, `stackRankColour` for stack).
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
                      cellsRect: CGRect, bottomBarH: CGFloat, samplesPerStep: Int, dir: EuclidDir = .fwd,
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
    // CC DIRECTION (2026-11-12): the value at raw walk position r is plotted at the CELL the playhead is at there
    // (`euclidCometPos`), so the curve runs WITH the direction-aware playhead — reversed for BKW, bouncing for ping-pong
    // over the full `cycleLen`. FWD (euclidCometPos(r,.fwd)=r, cycleLen=n) is byte-identical to the old forward map.
    let cycleLen = euclidCycleLen(dir, n: n)
    var line: [CGPoint] = []
    let total = cycleLen * max(1, samplesPerStep)
    for i in 0...total {
        let r = Double(i) / Double(max(1, samplesPerStep))
        if let v = value(phase(r * sub)) { line.append(CGPoint(x: x(euclidCometPos(r, n: n, dir: dir)), y: y(v))) }
    }
    var dots: [CGPoint] = []
    for d in rawDots {
        let bp = Double(d.x)
        guard bp >= 0, bp < Double(cycleLen) * sub + 1e-9 else { continue }   // a hit inside the shown pass (both legs for ping-pong)
        dots.append(CGPoint(x: x(euclidCometPos(bp / sub, n: n, dir: dir)), y: y(Double(d.y))))
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
    var stackChip: [Int?]       // per step: the lowest stack rank played here in the current pass (the footer chip's fallback label), nil = none
    var stackChipRanks: [[Int]] // STACK GREY §2.3: per step, ALL stack ranks played here this pass (ascending) — one footer segment per voice
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
    var stackChipRanks = [[Int]](repeating: [], count: max(0, n))
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
        if !stackChipRanks[s].contains(r) { stackChipRanks[s].append(r) }   // §2.3: every rank played here this pass (sorted below)
        if sounding {
            stackRing[s] = true
            if !stackOutline[s].contains(r) { stackOutline[s].append(r) }
        }
    }
    for s in 0..<stackChipRanks.count { stackChipRanks[s].sort() }           // §2.3: lowest rank on the left
    return LaneStripSounding(riffRing: riffRing, stackChip: stackChip, stackChipRanks: stackChipRanks, stackRing: stackRing, stackOutline: stackOutline)
}

// MARK: - RIFF GRID STACK DOTS (ferry 2026-11-16): a grey dot per sounding stack note on the riff grid, in the cell of (the lane's riff column at the START hit, the rank the stack played)

/// §8 tunables (named so device can change them). The dot FILL is `StackRankPalette.colour(rank)` (the grey ramp the stack-grey ferry built — NOT rebuilt here); the ring is #0D0F14 at `ringOpacity`.
enum RiffStackDotTuning {
    static let size: CGFloat = 3              // §2: the dot diameter
    static let ringWidth: CGFloat = 0.5       // §2: the dark ring
    static let ringOpacity: Double = 0.7      // §2: #0D0F14 @ 70 %
    static let cornerInsetX: CGFloat = 1.5    // §3: inset in from the cell's top-right corner (device-owed)
    static let cornerInsetY: CGFloat = 1.5
    static let laneStepX: CGFloat = 4         // §3: right-to-left step per lane when several lanes' dots share one cell (lane 1 rightmost)
    static let fadeSeconds: Double = 0.160    // §4: ease-out fade on note-off; 0 = a hard cut
}

/// One dot: the LANE (for the right-to-left, lane-order placement — not the colour, which is the RANK's grey), the grid cell (`column` 0-based, `rank` 1…8), and the `opacity` (1 while sounding, easing to 0 over the fade after note-off).
struct EuclideousRiffStackDot: Equatable {
    var lane: Int
    var column: Int   // 0-based grid column (ready for EuclideousRiffPanelLayout.cellFrame)
    var rank: Int     // 1…8
    var opacity: Double
}

/// §4 — the ease-out curve for the note-off fade: `age` 0…1 across the window → opacity 1…0, decelerating as it reaches 0 (ease-out).
@inline(__always) func euclideousRiffStackDotFade(_ age: Double) -> Double {
    let u = 1 - max(0, min(1, age))
    return u * u
}

/// §1 / §4 — the sounding stack dots for ONE lane, from the SAME held→step mapping the lane strip's stack outlines use (`laneStripSnapToHitStep(stepOf(onBeat))`, §1.6) plus the strip's own per-hit column
/// (`EuclideousStripHit.column`, 1-based). The feed carries no column, so the column is READ from the hit the note started on — never re-derived from a second clock. A note contributes while it sounds (opacity 1)
/// and for `fadeSeconds` after its note-off (ease-out to 0); `secPerBeat` converts the beat-domain `endBeat` to the wall-clock fade (0 ⇒ a hard cut). Allocation is one out array. `hits` / `hitSteps` are the strip
/// plan's for the leg the sweep is on; `now` the live beat; the caller has already dropped a lane whose stack is off / muted / solo-silenced (§5).
func euclideousRiffStackDots(lane: Int, stackHeld: [NoteRollNote], hits: [EuclideousStripHit], stepOf: (Double) -> Int, hitSteps: [Int], now: Double, fadeSeconds: Double, secPerBeat: Double, columns: Int = 8) -> [EuclideousRiffStackDot] {
    guard !hits.isEmpty else { return [] }
    let fadeBeats = secPerBeat > 0 ? fadeSeconds / secPerBeat : 0
    var out: [EuclideousRiffStackDot] = []
    for n in stackHeld where n.outs != 0 && n.onBeat <= now {   // §5: a note routed nowhere (`outs == 0`) lights nothing
        let opacity: Double
        if euclideousMixNoteSounds(n, at: now) { opacity = 1 }                 // still held / within gate
        else if let end = n.endBeat, end <= now, fadeBeats > 0 {               // §4: fading out after note-off
            let age = (now - end) / fadeBeats
            if age >= 1 { continue }
            opacity = euclideousRiffStackDotFade(age)
        } else { continue }                                                    // ended with a hard cut, or not yet / no longer drawn
        let r = Int(n.rank)
        guard r >= 1 && r <= 8 else { continue }
        let s = laneStripSnapToHitStep(stepOf(n.onBeat), hitSteps: hitSteps)   // §1.2/§4.6: the hit CELL the note started in (onset → step, snapped to the nearest authored hit)
        guard s >= 0 && s < hits.count, let col1 = hits[s].column, col1 >= 1 && col1 <= columns else { continue }   // POLY grids are 16 columns
        out.append(EuclideousRiffStackDot(lane: lane, column: col1 - 1, rank: r, opacity: opacity))   // §1.3: EuclideousStripHit.column is 1-based; the grid cell is 0-based
    }
    return out
}

// MARK: - PLAY BUTTONS RAIL+NOTE (2026-11-16) §4: the note the button shows in place of PLAY

/// §4.3: the chip of a part's MOST RECENT note-on hit. The riff tile draws `chip` (the header chip — riff-map fill + its
/// column label); the stack tile draws `ranks` (the footer split, one grey segment per voice). `sounding` is whether that
/// note-on is still sounding (§4.4: 100 % + strokes; else held at 78 %, no strokes). Built from the SAME onset → hit-step
/// mapping the lane strip's sounding sets use (`laneStripSnapToHitStep(stepOf(onBeat))`), so the tile can't disagree with
/// the strip. nil ⇒ no note-on has reached an emitter (§4.6: the word PLAY shows).
struct EuclideousPartNoteChip: Equatable {
    var chip: EuclideousStripChip?   // the riff header chip of the hit the newest note-on belongs to (nil when the hit has none)
    var ranks: [Int]                 // the stack ranks on that hit (ascending; the footer split)
    var sounding: Bool               // the newest note-on is still sounding
}
func euclideousPartNoteChip(held: [NoteRollNote], hits: [EuclideousStripHit], stepOf: (Double) -> Int, hitSteps: [Int], now: Double) -> EuclideousPartNoteChip? {
    var newest: NoteRollNote? = nil
    for n in held where n.outs != 0 && n.onBeat <= now {                    // §4.5: several sounding ⇒ the newest note-on
        if newest == nil || n.onBeat > newest!.onBeat { newest = n }
    }
    guard let newest else { return nil }                                    // §4.6: no note-on reached an emitter ⇒ PLAY
    let step = laneStripSnapToHitStep(stepOf(newest.onBeat), hitSteps: hitSteps)
    guard step >= 0 && step < hits.count else { return nil }
    var ranks: [Int] = []
    for n in held where n.outs != 0 && n.onBeat <= now {                    // §4.3: every held voice on THIS hit's step (the chord) — the footer split
        guard laneStripSnapToHitStep(stepOf(n.onBeat), hitSteps: hitSteps) == step else { continue }
        let r = Int(n.rank); if r >= 1 && r <= 8 && !ranks.contains(r) { ranks.append(r) }
    }
    ranks.sort()
    return EuclideousPartNoteChip(chip: hits[step].chip, ranks: ranks, sounding: euclideousMixNoteSounds(newest, at: now))
}

/// §5: the stack ranks the NOTES layer is PREDICTED to play on each hit — the engine's OWN `euclideousNotesHitPitches`
/// (fuzz-proven against the Router's notes body) mapped to pool ranks by `euclideousPoolRankOf` (the Router's own stamp), so
/// an upcoming predicted chip and the played chip (which reads a note record's stamped rank) agree as a hit transitions.
/// MONO only — a POLY lane (`poly != nil`) returns empty (⇒ the §5.1 #2B2D33 placeholder). Empty for a hit = predicted silent
/// (CHANCE-dropped / WHEN-excluded / empty pool). `pool` is the live pitch pool ascending; `isRestHit` per hit is the riff
/// column's written-rest state (MONO: `ranks[col−1] < 1`). Known limit (shared with the whole strip): `pool` is the GLOBAL
/// pool, so a lane with its own sources predicts against the global pool.
func euclideousStripStackRanks(line: EuclidLine, pool: [Int], cfg: EuclideousWalkLaneConfig?, hits: [EuclideousStripHit], lapStartTick: Int64?, lane: Int, ranks: [Int], poly: PolyRiffSnap?) -> [[Int]] {
    var out = [[Int]](repeating: [], count: hits.count)
    guard poly == nil, euclideousNotesLayerIsOn(line), !pool.isEmpty, let cfg, let lapStartTick else { return out }
    let oct = max(-2, min(2, line.octaveResolved))
    let slice = pool.map { (note: $0, vel: UInt8(100)) }[...]
    for i in 0..<hits.count {
        let h = hits[i]
        guard h.kind != .rhythmRest, h.tick >= 0 else { continue }
        let isRestHit: Bool = { guard let col = h.column, col >= 1, col - 1 < ranks.count else { return true }; return ranks[col - 1] < 1 }()
        let pitches = euclideousNotesHitPitches(line: line, pool: pool, cfg: cfg, tick: lapStartTick + Int64(h.tick), lane: lane, oct: oct, isRestHit: isRestHit, ranks: ranks, poly: nil)
        var rs: [Int] = []
        for p in pitches { let r = Int(euclideousPoolRankOf(slice, note: p)); if r >= 1 && r <= 8 && !rs.contains(r) { rs.append(r) } }
        out[i] = rs.sorted()
    }
    return out
}
