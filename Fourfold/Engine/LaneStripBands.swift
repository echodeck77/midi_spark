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
    /// §1.4: header/footer height = round(T × this); the cells band is what's left less the two row gaps.
    static let headerRatio = 0.23
    static let rowGap: CGFloat = 2
    /// §3.1: a chip is `hH − chipShrink` tall, at most `chipMaxW` wide, radius `chipRadius`, label `chipLabel` heavy
    /// (`chipLabelMany` over `manySteps` steps), ink `chipInk`, no tracking; rest opacity `chipRestOpacity`, sounding 1.
    static let chipShrink: CGFloat = 4, chipMaxW: CGFloat = 30, chipRadius: CGFloat = 4
    static let chipLabel: CGFloat = 10, chipLabelMany: CGFloat = 9, manySteps = 12
    static let chipRestOpacity = 0.78
    static let chipInk = EuclideousRGB(r: 0x0D, g: 0x0F, b: 0x14)
    /// §3.4: a sounding chip's lane100 ring — 1.5 pt, a 1.5 pt #202226 gap between ring and chip, drawn outside the chip.
    static let ringWidth: CGFloat = 1.5, ringGap: CGFloat = 1.5
    /// §3.6: an off part's chips — outline only (1 pt #3A3D44 inner stroke), label #5A5E66, no ring.
    static let offChipStroke = EuclideousRGB(r: 0x3A, g: 0x3D, b: 0x44), offChipLabel = EuclideousRGB(r: 0x5A, g: 0x5E, b: 0x66)
    /// §3.7: the ANSWER line along the footer track's inside-bottom edge — 2 pt, source lane100 @ 70 %, radius 1.
    static let answerLineH: CGFloat = 2, answerLineAlpha = 0.7, answerLineRadius: CGFloat = 1

    /// §4.2: cell fills — a step not under / under the playhead; a hit not under / under the playhead takes lane100 at
    /// `hitAlpha`/`hitPlayheadAlpha` with the 3 pt lane100 bottom bar. No strike flash, glow or ease.
    static let stepFill = EuclideousRGB(r: 0x2A, g: 0x2C, b: 0x33)
    static let playheadStepFill = EuclideousRGB(r: 0x3A, g: 0x3D, b: 0x44)
    static let hitAlpha = 0.30, hitPlayheadAlpha = 0.45
    static let bottomBarH: CGFloat = 3, cellRadius: CGFloat = 6
    /// §4.3–4.5: the rank slots — pad 3 at the cell's top and (3 + the bar) at its bottom, split 8 ways; a lit rank is a
    /// 1 pt stroked outline (inset riff 3 / stack 6 from the cell's sides, radius 1.5, inset 0.4 top+bottom in its slot),
    /// or — where a slot is under `slotFallback` — a `fallbackBarH`-tall filled bar centred in the slot, same insets.
    static let slotPad: CGFloat = 3, outlineStroke: CGFloat = 1, outlineRadius: CGFloat = 1.5, slotInsetTB: CGFloat = 0.4
    static let riffInset: CGFloat = 3, stackInset: CGFloat = 6
    static let slotFallback: CGFloat = 3, fallbackBarH: CGFloat = 1

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
/// §1.4: header/footer `hH = round(T × 0.23)`; the cells band `hC = T − 2·hH − 2·gap`. (T 44 → hH 10, hC 20; T 78 → hH 18, hC 38.)
func laneStripBandHeights(T: CGFloat) -> LaneStripBandHeights {
    let hH = (T * LaneStripBandMetrics.headerRatio).rounded()
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
    let slot = (hC - M.slotPad - (M.slotPad + M.bottomBarH)) / 8        // §4.3: (hC − 3 − 6) ÷ 8
    let slotTop = cell.minY + M.slotPad + CGFloat(8 - r) * slot          // rank 1 at the bottom, rank 8 at the top
    let sideInset = part == .riff ? M.riffInset : M.stackInset
    let x = cell.minX + sideInset, width = max(0, cell.width - 2 * sideInset)
    if slot < M.slotFallback {                                           // §4.5: a 1-tall filled bar centred in the slot
        return LaneRankMark(rect: CGRect(x: x, y: slotTop + (slot - M.fallbackBarH) / 2, width: width, height: M.fallbackBarH), filled: true)
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

// MARK: - §8 / §5.1: the CC source emitter

/// §5.1: the first emitter in A–D (0…3) order that this lane's riff OR stack routes to (`routed`, the OR of the two
/// resolved output masks) and that has CC on (`ccOn`, bit o = `emitterCCs[o].on`). nil ⇒ no trace. The output-muted /
/// stopped suppression (§5.6) is applied where the trace is drawn, not here.
func laneCCSourceEmitter(routed: UInt8, ccOn: UInt8) -> Int? {
    for o in 0..<4 where (routed >> UInt8(o)) & 1 != 0 && (ccOn >> UInt8(o)) & 1 != 0 { return o }
    return nil
}
