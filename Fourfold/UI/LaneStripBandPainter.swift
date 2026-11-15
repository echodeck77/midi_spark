//  LaneStripBandPainter.swift — LANE STRIP BANDS ferry (2026-11-12): the Fourfold lane card's re-banded strip —
//  a riff HEADER (riff chips), the CELLS (steps/hits + per-rank sounding outlines), and a stack FOOTER (stack
//  chips), with a faint CC trace across the cells. Painted in ONE Canvas inside `EuclidCometBar`'s existing
//  `TimelineView` (the `strip != nil` path); the BUILD-page comet (`strip == nil`) never calls this.
//
//  SwiftUI-only (the GridUI seam rule: no UIKit, no AU frameworks). Every frame, colour, outline rect and cell
//  look comes from the pure functions in `LaneStripBands.swift` / `Derivations.swift`, so the drawing and the
//  tests can't disagree. Nothing here glows (§6.4); the PLAY lamps keep their own flash. Display only.

import SwiftUI

private extension Color {
    init(_ c: EuclideousRGB) { self.init(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, opacity: 1) }
}

/// §5: the page-computed CC source for a lane's strip — the one-bar curve from the CC tab's own `emitterCCTrace`
/// (points + dots over the bar), to be mapped onto the strip's steps by `laneCCStripTrace`. nil ⇒ the lane feeds no
/// CC emitter (§5.1), or STRIP CC (§5.7) is off.
struct EuclideousStripCCInput: Equatable { var points: [CGPoint]; var dots: [CGPoint]; var barBeats: Double }

/// Everything one frame of the banded strip needs (strip-local coordinates). Built once per frame in `EuclidCometBar`.
struct EuclideousStripBandInput {
    var frames: LaneStripBandFrames
    var hits: [EuclideousStripHit]
    var steps: Int
    var laneIndex: Int
    var tint: Color
    /// The strip's full width — the header/footer track plates span it.
    var stripWidth: CGFloat
    /// The step the rhythm sweep is on now (the §4.2 playhead cell); nil while stopped.
    var playheadStep: Int?
    /// §3.3 / §3.4 / §4.4: what sounds now, per step (from the note feed, mapped to steps by onset).
    var sounding = LaneStripSounding(riffRing: [], stackChip: [], stackChipRanks: [], stackRing: [], stackOutline: [])
    /// §5: the faint CC trace (line + hit dots + the playhead dot) in strip coordinates; nil ⇒ no trace.
    var cc: LaneCCStripTrace? = nil
    /// §3.6: the riff / notes part is on (an off part draws its chips as grey outlines).
    var riffShown: Bool = true
    var notesShown: Bool = true
    /// ALT §5.9: the buf-index steps whose hit plays in the alt state — a white inner outline on the body cell (empty for every non-ALT lane / stopped ⇒ identical).
    var altHitSteps: Set<Int> = []
}

/// §5.4: the faint CC trace — a 1 pt line, a 3 pt dot at each hit's value, a 4 pt dot at the playhead. Over the cells,
/// under the outlines; never a touch, never any height of its own.
private func laneStripDrawCC(_ ctx: inout GraphicsContext, _ cc: LaneCCStripTrace, playhead: CGPoint?) {
    typealias M = LaneStripBandMetrics
    let ink = Color(M.ccInk)
    if cc.line.count > 1 {
        var path = Path(); path.addLines(cc.line)
        ctx.stroke(path, with: .color(ink.opacity(M.ccLineAlpha)), style: StrokeStyle(lineWidth: 1, lineJoin: .round))
    }
    for dot in cc.dots {
        ctx.fill(Path(ellipseIn: CGRect(x: dot.x - M.ccHitDot / 2, y: dot.y - M.ccHitDot / 2, width: M.ccHitDot, height: M.ccHitDot)), with: .color(ink.opacity(M.ccHitDotAlpha)))
    }
    if let ph = playhead {
        ctx.fill(Path(ellipseIn: CGRect(x: ph.x - M.ccPlayheadDot / 2, y: ph.y - M.ccPlayheadDot / 2, width: M.ccPlayheadDot, height: M.ccPlayheadDot)), with: .color(ink.opacity(M.ccPlayheadDotAlpha)))
    }
}

/// §4.4 / §4.5: a sounding rank in a hit cell — a stroked outline (or the filled-bar fallback where the slot is tiny).
private func laneStripDrawRankMark(_ ctx: inout GraphicsContext, cell: CGRect, hC: CGFloat, rank: Int, part: LaneStripPart, colour: Color) {
    let m = rankSlotRect(cell: cell, hC: hC, rank: rank, part: part)
    guard m.rect.width > 0.5, m.rect.height > 0.3 else { return }
    if m.filled { ctx.fill(RoundedRectangle(cornerRadius: LaneStripBandMetrics.barRadius).path(in: m.rect), with: .color(colour)) }   // §B4.2 bar radius 0.5
    else { ctx.stroke(RoundedRectangle(cornerRadius: LaneStripBandMetrics.outlineRadius).path(in: m.rect), with: .color(colour), lineWidth: LaneStripBandMetrics.outlineStroke) }
}

private func laneStripChipFont(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// A rect with independent left-corner / right-corner radii (both top and bottom on a side share the radius) — the
/// §2 track plates are square on the joint side (toward their button) and rounded (r6) on the far side.
private func laneStripTrackPath(_ r: CGRect, leftR: CGFloat, rightR: CGFloat) -> Path {
    var p = Path()
    p.move(to: CGPoint(x: r.minX + leftR, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - rightR, y: r.minY))
    if rightR > 0 { p.addArc(center: CGPoint(x: r.maxX - rightR, y: r.minY + rightR), radius: rightR, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false) }
    p.addLine(to: CGPoint(x: r.maxX, y: r.maxY - rightR))
    if rightR > 0 { p.addArc(center: CGPoint(x: r.maxX - rightR, y: r.maxY - rightR), radius: rightR, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false) }
    p.addLine(to: CGPoint(x: r.minX + leftR, y: r.maxY))
    if leftR > 0 { p.addArc(center: CGPoint(x: r.minX + leftR, y: r.maxY - leftR), radius: leftR, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false) }
    p.addLine(to: CGPoint(x: r.minX, y: r.minY + leftR))
    if leftR > 0 { p.addArc(center: CGPoint(x: r.minX + leftR, y: r.minY + leftR), radius: leftR, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false) }
    p.closeSubpath()
    return p
}

func drawLaneStripBands(_ ctx: inout GraphicsContext, _ d: EuclideousStripBandInput) {
    typealias M = LaneStripBandMetrics
    let n = d.frames.cells.count
    let b = d.frames.bands

    // §2.3: the HEADER / FOOTER track PLATES — the tile fill #202226 with a 1 pt #2B2D33 border, square on the joint
    // side (the header toward PLAY RIFF on the left, the footer toward PLAY STACK on the right) and rounded r6 on the
    // far side, so each reads as the extension of its button. (The literal bridge FILLING the g gap to the button, and
    // the perfectly seamless shared outline, are device-owed — see the status log.)
    if d.stripWidth > 1, b.hH > 1 {
        let fill = Color(M.tileFill), border = Color(M.tileBorder), r = M.trackCornerRadius
        let header = CGRect(x: 0, y: 0, width: d.stripWidth, height: b.hH)
        let footer = CGRect(x: 0, y: b.hH + b.gap + b.hC + b.gap, width: d.stripWidth, height: b.hH)
        for (plate, leftR, rightR) in [(header, CGFloat(0), r), (footer, r, CGFloat(0))] {
            let path = laneStripTrackPath(plate, leftR: leftR, rightR: rightR)
            ctx.fill(path, with: .color(fill))
            ctx.stroke(path, with: .color(border), lineWidth: 1)
        }
    }

    // §4.1 / §4.2: the cells — steps and hits, no strike flash. A hit is lane100 (30 %, 45 % at the playhead) with a 3 pt
    // lane100 bar inside its bottom edge; a step is a flat grey (brighter at the playhead). (The beat-group shading, the
    // gap ring and the strike dip/glow of the old strip are replaced here, per the ferry.)
    for i in 0..<n {
        let cell = d.frames.cells[i]
        let isHit = i < d.hits.count && d.hits[i].kind != .rhythmRest
        let look = stripCellLook(isHit: isHit, isPlayhead: d.playheadStep == i)
        let shape = RoundedRectangle(cornerRadius: M.cellRadius).path(in: cell)
        switch look.fill {
        case .step:          ctx.fill(shape, with: .color(Color(M.stepFill)))
        case .playheadStep:  ctx.fill(shape, with: .color(Color(M.playheadStepFill)))
        case .hit(let a):    ctx.fill(shape, with: .color(d.tint.opacity(a)))
        }
        if look.bar {
            let bar = CGRect(x: cell.minX, y: cell.maxY - M.bottomBarH, width: cell.width, height: M.bottomBarH)
            ctx.fill(RoundedRectangle(cornerRadius: M.bottomBarH / 2).path(in: bar), with: .color(d.tint))
        }
    }

    let s = d.sounding
    func riffRing(_ i: Int) -> Bool { i < s.riffRing.count && s.riffRing[i] }
    func stackRing(_ i: Int) -> Bool { i < s.stackRing.count && s.stackRing[i] }

    // STACK GREY §3.2: a 1 pt #F2F4F7 inner stroke on a hit cell while a note that started there (riff or stack) sounds —
    // over the cell fill + its bottom bar, under the CC trace and the rank bars.
    for i in 0..<n where i < d.hits.count && d.hits[i].kind != .rhythmRest && (riffRing(i) || stackRing(i)) {
        let r = d.frames.cells[i].insetBy(dx: 0.5, dy: 0.5)
        ctx.stroke(RoundedRectangle(cornerRadius: M.cellRadius).path(in: r), with: .color(Color(M.soundStroke)), lineWidth: 1)
    }

    // ALT §5.9: a 1.5 pt #F2F4F7 inner outline on the body cell of each hit that plays in the alt state (empty set on every other lane / tab / while stopped ⇒ nothing drawn).
    if !d.altHitSteps.isEmpty {
        for i in 0..<n where d.altHitSteps.contains(i) && i < d.hits.count && d.hits[i].kind != .rhythmRest {
            let r = d.frames.cells[i].insetBy(dx: 0.75, dy: 0.75)
            ctx.stroke(RoundedRectangle(cornerRadius: M.cellRadius).path(in: r), with: .color(Color(hex: 0xF2F4F7)), lineWidth: 1.5)
        }
    }

    // §5: the faint CC trace — over the cells, under the rank outlines.
    if let cc = d.cc { laneStripDrawCC(&ctx, cc, playhead: cc.playhead) }

    // §4.4: the sounding rank OUTLINES in the hit cells — riff in its map colour (inset 3), stack in its chip colour
    // (inset 6, inside the riff's), while the note sounds. (The CC trace will draw between the cells and these outlines.)
    for i in 0..<n where i < d.hits.count {
        let cell = d.frames.cells[i]
        if d.riffShown, riffRing(i), let chip = d.hits[i].chip {
            laneStripDrawRankMark(&ctx, cell: cell, hC: d.frames.bands.hC, rank: chip.rank, part: .riff, colour: Color(riffMapColour(column: chip.column, rank: chip.rank)))
            for extra in d.hits[i].extraRanks {   // POLY: the other riff notes started on this column
                laneStripDrawRankMark(&ctx, cell: cell, hC: d.frames.bands.hC, rank: extra, part: .riff, colour: Color(riffMapColour(column: chip.column, rank: extra)))
            }
        }
        if d.notesShown, i < s.stackOutline.count {
            for rank in s.stackOutline[i] {
                laneStripDrawRankMark(&ctx, cell: cell, hC: d.frames.bands.hC, rank: rank, part: .stack, colour: Color(stackRankColour(rank: rank)))
            }
        }
    }

    // §3.2: the riff HEADER — a chip at each hit step, the riff column it reads, filled `riffMapColour(column, rank)`;
    // REPEAT is hollow/dashed in that colour; an off riff part draws every chip as a grey outline (§3.6). A chip wears the
    // lane ring from its note-on to its note-off (§3.4).
    for i in 0..<n where i < d.hits.count {
        let isHit = d.hits[i].kind != .rhythmRest
        if d.riffShown {
            guard let chip = d.hits[i].chip else { continue }
            laneStripDrawChip(&ctx, slot: d.frames.header[i], steps: d.steps,
                              fill: .map(riffMapColour(column: chip.column, rank: chip.rank)),
                              label: "\(chip.column)", hollow: chip.hollow, sounding: riffRing(i))
        } else if isHit {   // §B6: an OFF riff part draws a grey outline chip on every hit (its column where known), never sounding
            laneStripDrawChip(&ctx, slot: d.frames.header[i], steps: d.steps, fill: nil, label: d.hits[i].chip.map { "\($0.column)" } ?? "", hollow: false, sounding: false)
        }
    }

    // §3.3 / STACK GREY §2: the stack FOOTER — a chip at each hit step a stack note has played in this pass, grey by rank
    // (`stackRankColour`), SPLIT into one segment per voice (§2.3), ringed while it sounds; an off notes part draws grey
    // outline chips at the hit steps (§3.6). (Upcoming-hit prediction is a flagged follow-up — see the status log.)
    for i in 0..<n where i < d.hits.count {
        let isHit = d.hits[i].kind != .rhythmRest
        if d.notesShown, i < s.stackChipRanks.count, !s.stackChipRanks[i].isEmpty {
            laneStripDrawFooterChip(&ctx, slot: d.frames.footer[i], steps: d.steps, ranks: s.stackChipRanks[i], sounding: stackRing(i))
        } else if isHit {   // §B6.1: an OFF notes part, OR an upcoming hit not yet played / predicted, draws a grey outline chip (no label)
            laneStripDrawChip(&ctx, slot: d.frames.footer[i], steps: d.steps, fill: nil, label: "", hollow: false, sounding: false)
        }
    }
}

/// STACK GREY §2.3: the stack footer chip — one grey segment per voice (lowest rank on the left, 1 pt gaps), each its own
/// `stackRankColour` fill + `stackRankInk` label (hidden on a too-narrow segment, §B2.3). A segment under 4 pt wide ⇒ one
/// chip at the lowest rank, as before. §2.4's sounding double-stroke goes round the WHOLE frame, once.
func laneStripDrawFooterChip(_ ctx: inout GraphicsContext, slot: CGRect, steps: Int, ranks: [Int], sounding: Bool) {
    typealias M = LaneStripBandMetrics
    let frame = laneStripChipFrame(slot: slot)
    guard frame.width > 1, frame.height > 1 else { return }
    let a = sounding ? 1.0 : M.chipRestOpacity                               // §2.1: 100 % sounding, 78 % at rest
    let size = laneStripChipLabelSize(steps: steps)
    for seg in laneStripFooterSegments(frameWidth: frame.width, ranks: ranks) {
        let rect = CGRect(x: frame.minX + seg.x, y: frame.minY, width: seg.width, height: frame.height)
        ctx.fill(RoundedRectangle(cornerRadius: M.chipRadius).path(in: rect), with: .color(Color(stackRankColour(rank: seg.rank)).opacity(a)))
        let label = "\(seg.rank)"
        if laneStripChipLabelFits(label, chipWidth: rect.width, size: size) {   // §2.3: each segment's own width
            ctx.draw(ctx.resolve(Text(label).font(laneStripChipFont(size)).foregroundColor(Color(stackRankInk(rank: seg.rank)))), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }
    if sounding { laneStripDrawSoundStroke(&ctx, frame) }                    // §2.4: round the whole chip frame, once
}

/// STACK GREY §2.4: the sounding mark on a chip — a 1 pt #F2F4F7 stroke on the inside edge of the frame and a 1 pt #0D0F14
/// stroke just inside that, so it reads on both dark and light fills. Header, footer and split chips all use it.
func laneStripDrawSoundStroke(_ ctx: inout GraphicsContext, _ frame: CGRect) {
    typealias M = LaneStripBandMetrics
    ctx.stroke(RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(Color(M.soundStroke)), lineWidth: 1)
    ctx.stroke(RoundedRectangle(cornerRadius: max(0.5, M.chipRadius - 1)).path(in: frame.insetBy(dx: 1.5, dy: 1.5)), with: .color(Color(M.chipInk)), lineWidth: 1)
}

/// §3.1 / §3.6: one header or footer chip. `fill` nil ⇒ the off-part outline look (grey stroke, grey label, no fill);
/// `.map`/`.rgb` ⇒ a filled chip with ink label (or, when `hollow`, a dashed stroke + label in the fill colour).
enum LaneStripChipFill { case map(EuclideousRGB); case rgb(EuclideousRGB) }
func laneStripDrawChip(_ ctx: inout GraphicsContext, slot: CGRect, steps: Int, fill: LaneStripChipFill?, label: String, hollow: Bool, sounding: Bool) {
    typealias M = LaneStripBandMetrics
    let frame = laneStripChipFrame(slot: slot)
    guard frame.width > 1, frame.height > 1 else { return }
    let shape = RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame)
    let size = laneStripChipLabelSize(steps: steps)
    let labelColour: Color
    let a = sounding ? 1.0 : M.chipRestOpacity   // §B2.4: a sounding chip at 100 %, resting at 78 %
    if let fill {
        let c = Color(fillRGB(fill))
        if hollow {
            ctx.stroke(RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(c.opacity(a)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            labelColour = c
        } else {
            ctx.fill(shape, with: .color(c.opacity(a)))
            labelColour = Color(M.chipInk)
        }
        if sounding { laneStripDrawSoundStroke(&ctx, frame) }   // §2.4: the #F2F4F7 + #0D0F14 double inner stroke (reads on dark and light)
    } else {
        ctx.stroke(RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(Color(M.offChipStroke)), lineWidth: 1)
        labelColour = Color(M.offChipLabel)
    }
    if laneStripChipLabelFits(label, chipWidth: frame.width, size: size) {   // §B2.3: no label when the chip is narrower than the label + 2
        ctx.draw(ctx.resolve(Text(label).font(laneStripChipFont(size)).foregroundColor(labelColour)), at: CGPoint(x: frame.midX, y: frame.midY), anchor: .center)
    }
}
private func fillRGB(_ f: LaneStripChipFill) -> EuclideousRGB { switch f { case .map(let c): return c; case .rgb(let c): return c } }
