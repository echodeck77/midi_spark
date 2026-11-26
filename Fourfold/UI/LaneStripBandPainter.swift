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
    /// PLAY BUTTONS RAIL+NOTE §6.1: both parts off → the HIT cells (fill + bottom bar) draw at this (0.42); rest cells, the
    /// playhead and the tiles are unchanged. 1 (one part on, or the whole strip already dimmed by solo/mute) ⇒ no cell dim.
    var cellDim: Double = 1
    /// ALT §5.9: the buf-index steps whose hit plays in the alt state — a white inner outline on the body cell (empty for every non-ALT lane / stopped ⇒ identical).
    var altHitSteps: Set<Int> = []
    /// STEP DISPLAY part 2 (FILL step flash, 2026-11-25; gated to the playhead 2026-11-26): what a hit-changing fill does to the
    /// box the playhead is sounding NOW — `.sounds` draws it as a hit (incl. a standard rest the fill plays), `.silencedMiss` draws a
    /// dropped standard hit as a rest (at the playhead = the normal sounding-miss look). Applied ONLY on `playheadStep`, so the
    /// effect shows while sounding, not in advance or after. `.none` (non-fill / recolour-only / stopped) ⇒ standard pattern, byte-identical.
    var fillPlayheadFlash: EuclideousFillPlayheadFlash = .none
    /// LANE STRIP CLARITY §5.1: the lane whose hit COLOUR the cells take (the CARD's lane — under an ANSWER trade the strip
    /// shows the partner's plan in the card's own colour, so this is the card index, not the plan's).
    var hitColourLane: Int = 0
    /// RIFF SOURCE ferry (§9): a READER lane's riff chips + rank marks take the SOURCE lane's colour (§3.11 on the card
    /// strip), in place of the borrowed cell's riff-map colour — so the chip says the line comes from the source. nil ⇒ own.
    var riffSourceColor: EuclideousRGB? = nil
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

/// Amendment 1 B4's slots / LANE STRIP CLARITY §4: a rank's mark in a hit cell. RESTING — the part's colour at 50 %
/// (a filled bar, or B4.4's stroked outline where the slot is ≥ 4). SOUNDING — #F2F4F7 at 100 % in place of the resting
/// colour; where the slot is ≥ 4 the sounding rank FILLS its outline white (§4.5).
private func laneStripDrawRankMark(_ ctx: inout GraphicsContext, cell: CGRect, hC: CGFloat, rank: Int, part: LaneStripPart, restColour: Color, sounding: Bool) {
    let m = rankSlotRect(cell: cell, hC: hC, rank: rank, part: part)
    guard m.rect.width > 0.5, m.rect.height > 0.3 else { return }
    typealias M = LaneStripBandMetrics
    let colour = sounding ? Color(M.soundStroke) : restColour.opacity(LaneRankBarTuning.restOpacity)
    if m.filled || sounding { ctx.fill(RoundedRectangle(cornerRadius: m.filled ? M.barRadius : M.outlineRadius).path(in: m.rect), with: .color(colour)) }   // §B4.2 bar / §4.5 the filled outline
    else { ctx.stroke(RoundedRectangle(cornerRadius: M.outlineRadius).path(in: m.rect), with: .color(colour), lineWidth: M.outlineStroke) }
}

private func laneStripChipFont(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

func drawLaneStripBands(_ ctx: inout GraphicsContext, _ d: EuclideousStripBandInput) {
    typealias M = LaneStripBandMetrics
    let n = d.frames.cells.count
    let riffFrac = d.frames.riffFrac, stackFrac = d.frames.stackFrac

    // PLAY BUTTONS RAIL+NOTE §2.5: NO track plate / bridge / band background / band outline is drawn — the running-part
    // RAIL (§2) is the only edge, drawn by the row's overlay; a stopped part's band simply isn't here (§3.3) and the cells
    // extend into it. (The old #202226 track plates of the LANE STRIP BANDS ferry are retired.)

    // §4.1 / §4.2: the cells — steps and hits, no strike flash. A hit is lane100 (30 %, 45 % at the playhead) with a 3 pt
    // lane100 bar inside its bottom edge; a step is a flat grey (brighter at the playhead). (The beat-group shading, the
    // gap ring and the strike dip/glow of the old strip are replaced here, per the ferry.)
    for i in 0..<n {
        let cell = d.frames.cells[i]
        var isHit = i < d.hits.count && d.hits[i].kind != .rhythmRest
        let atPlayhead = d.playheadStep == i
        // STEP DISPLAY part 2 (gated to the playhead, Paul 2026-11-26): a hit-changing fill overrides ONLY the box the playhead is
        // sounding NOW — not held across the region (not in advance, not after). `.sounds` ⇒ a hit while the playhead is on it (lane
        // colour, incl. a standard rest the fill plays); `.silencedMiss` ⇒ a dropped standard hit reads as a rest EXACTLY as a
        // sounding miss does in normal play (stripCellLook → .playheadStep), and only then.
        if atPlayhead {
            switch d.fillPlayheadFlash {
            case .sounds:       isHit = true
            case .silencedMiss: isHit = false
            case .none:         break
            }
        }
        let look = stripCellLook(isHit: isHit, isPlayhead: atPlayhead)
        let shape = RoundedRectangle(cornerRadius: M.cellRadius).path(in: cell)
        switch look.fill {
        case .step:          ctx.fill(shape, with: .color(Color(M.stepFill)))                 // CLARITY §5.3: #22242A (#3A3D44 at the playhead)
        case .playheadStep:  ctx.fill(shape, with: .color(Color(M.playheadStepFill)))
        case .hit(let ph):   // CLARITY §5.1/§5.2: the opaque even hit colour (one lightness across lanes); §5.4 both-parts-off dims it
            ctx.fill(shape, with: .color(Color(stripHitColour(lane: d.hitColourLane, atPlayhead: ph)).opacity(d.cellDim)))
        }
        if look.bar {
            let bar = CGRect(x: cell.minX, y: cell.maxY - M.bottomBarH, width: cell.width, height: M.bottomBarH)
            ctx.fill(RoundedRectangle(cornerRadius: M.bottomBarH / 2).path(in: bar), with: .color(d.tint.opacity(d.cellDim)))
        }
    }

    let s = d.sounding
    func riffRing(_ i: Int) -> Bool { i < s.riffRing.count && s.riffRing[i] }
    func stackRing(_ i: Int) -> Bool { i < s.stackRing.count && s.stackRing[i] }

    // STACK GREY §3.2's white stroke round a sounding hit cell is REMOVED (LANE STRIP CLARITY §6.3): sounding is shown by
    // the chip (§1.4/§2) and the white rank bar (§4.2); the §6 tick (drawn last, below) shows only where the playhead is.

    // ALT §5.9: a 1.5 pt #F2F4F7 inner outline on the body cell of each hit that plays in the alt state (empty set on every other lane / tab / while stopped ⇒ nothing drawn).
    if !d.altHitSteps.isEmpty {
        for i in 0..<n where d.altHitSteps.contains(i) && i < d.hits.count && d.hits[i].kind != .rhythmRest {
            let r = d.frames.cells[i].insetBy(dx: 0.75, dy: 0.75)
            ctx.stroke(RoundedRectangle(cornerRadius: M.cellRadius).path(in: r), with: .color(Color(hex: 0xF2F4F7)), lineWidth: 1.5)
        }
    }

    // §5: the faint CC trace — over the cells, under the rank outlines.
    if let cc = d.cc { laneStripDrawCC(&ctx, cc, playhead: cc.playhead) }

    // LANE STRIP CLARITY §4 (replaces amendment 1 B4.2's sounding-only marks): for each ON part, EVERY hit cell draws its
    // rank bar(s) — RESTING at 50 % in the part's colour (riff map / grey ramp), #F2F4F7 at 100 % while a note from that
    // hit sounds (§4.2). A played hit's set replaces the prediction, as its chip does (§4.3). Riff first, stack over it
    // (§4.4 — the stack's bar is narrower and sits inside); while BOTH sound one rank, one white bar at the riff's width.
    // Over the cell fill + CC trace, under the §6 tick (§4.7). An off part (frac 0) draws none (§4.6).
    for i in 0..<n where i < d.hits.count && d.hits[i].kind != .rhythmRest {
        let cell = d.frames.cells[i]
        let riffChip = riffFrac > 0 ? d.hits[i].chip : nil
        let riffSounds = riffRing(i)
        if let chip = riffChip {
            // RIFF SOURCE §9: a reader's rank marks are the SOURCE lane's colour, not the borrowed cell's map colour.
            let riffRestColour: (Int) -> Color = { rank in d.riffSourceColor.map { Color($0) } ?? Color(riffMapColour(column: chip.column, rank: rank)) }
            laneStripDrawRankMark(&ctx, cell: cell, hC: d.frames.bands.hC, rank: chip.rank, part: .riff,
                                  restColour: riffRestColour(chip.rank), sounding: riffSounds)
            for extra in d.hits[i].extraRanks {   // POLY: the other riff notes started on this column
                laneStripDrawRankMark(&ctx, cell: cell, hC: d.frames.bands.hC, rank: extra, part: .riff,
                                      restColour: riffRestColour(extra), sounding: riffSounds)
            }
        }
        if stackFrac > 0 {
            let played = i < s.stackChipRanks.count ? s.stackChipRanks[i] : []
            let ranks = laneStripRestingStackRanks(played: played, predicted: d.hits[i].predictedStackRanks)   // §4.1: unpredicted ⇒ none until played
            for rank in ranks {
                let sounds = i < s.stackOutline.count && s.stackOutline[i].contains(rank)
                if sounds, laneStripStackBarFoldsIntoRiff(rank: rank, riffRank: riffChip?.rank, riffSounding: riffSounds) { continue }   // §4.4: one white bar at the riff's width
                laneStripDrawRankMark(&ctx, cell: cell, hC: d.frames.bands.hC, rank: rank, part: .stack,
                                      restColour: Color(stackRankColour(rank: rank)), sounding: sounds)
            }
        }
    }

    // §3.2: the riff HEADER — a chip at each hit step, the riff column it reads, filled `riffMapColour(column, rank)`;
    // REPEAT is hollow/dashed in that colour; a chip wears the sounding stroke from its note-on to its note-off (§3.4).
    // PLAY BUTTONS RAIL+NOTE §3.3: an OFF riff part (riffFrac 0) draws NOTHING here (the band is gone, the cells extend);
    // while a part eases off, its chips fade at `riffFrac`.
    if riffFrac > 0 {
        for i in 0..<n where i < d.hits.count {
            guard let chip = d.hits[i].chip else { continue }
            // RIFF SOURCE §9: a reader's header chip is the SOURCE lane's colour; an own lane keeps the riff-map colour of the cell it plays.
            let fill: LaneStripChipFill = d.riffSourceColor.map { .rgb($0) } ?? .map(riffMapColour(column: chip.column, rank: chip.rank))
            laneStripDrawChip(&ctx, slot: d.frames.header[i], steps: d.steps,
                              fill: fill,
                              label: "\(chip.column)", hollow: chip.hollow, sounding: riffRing(i), opacity: riffFrac, slim: d.frames.slim)
        }
    }

    // §3.3 / STACK GREY §2: the stack FOOTER — a chip at each hit step a stack note has played in this pass, grey by rank
    // (`stackRankColour`), SPLIT into one segment per voice (§2.3), ringed while it sounds. PLAY BUTTONS RAIL+NOTE §3.3: an
    // OFF notes part (stackFrac 0) draws NOTHING. (§5, slice 5, adds the real predicted chip / #2B2D33 slot on upcoming hits.)
    if stackFrac > 0 {
        // LANE STRIP CLARITY §3: a footer chip is LABELLED only on the pass's first hit and where its drawn rank set
        // (played-or-predicted, §3.1) changes from the hit before; an unpredicted slot labels the hit after it (§3.2).
        var drawnSets = [[Int]?](repeating: nil, count: n)
        for i in 0..<n where i < d.hits.count && d.hits[i].kind != .rhythmRest {
            if i < s.stackChipRanks.count, !s.stackChipRanks[i].isEmpty { drawnSets[i] = s.stackChipRanks[i] }
            else { drawnSets[i] = d.hits[i].predictedStackRanks }
        }
        let labelled = laneStripFooterLabelled(hitRankSets: drawnSets)
        for i in 0..<n where i < d.hits.count {
            if i < s.stackChipRanks.count, !s.stackChipRanks[i].isEmpty {
                laneStripDrawFooterChip(&ctx, slot: d.frames.footer[i], steps: d.steps, ranks: s.stackChipRanks[i], sounding: stackRing(i), opacity: stackFrac, slim: d.frames.slim, labelled: labelled[i])   // a played hit — its chip, ringed while sounding
            } else if d.hits[i].kind != .rhythmRest {
                // PLAY BUTTONS RAIL+NOTE §5 (Paul 2026-11-16): every upcoming hit gets a chip too, like the riff — the REAL
                // predicted ranks (resting look, 78 %), or a flat #2B2D33 placeholder when the hit is predicted silent.
                let pred = d.hits[i].predictedStackRanks
                if !pred.isEmpty {
                    laneStripDrawFooterChip(&ctx, slot: d.frames.footer[i], steps: d.steps, ranks: pred, sounding: false, opacity: stackFrac, slim: d.frames.slim, labelled: labelled[i])
                } else {
                    ctx.fill(RoundedRectangle(cornerRadius: d.frames.slim ? M.slimChipRadius : M.chipRadius).path(in: d.frames.footer[i]), with: .color(Color(M.emptySlotFill).opacity(stackFrac)))   // §1.8: on a slim lane the unpredicted slot is the 4 pt #2B2D33 bar
                }
            }
        }
    }

    // LANE STRIP CLARITY §6: the playhead TICK — a 2 pt #F2F4F7 bar along the inside of the current cell's top edge,
    // clipped to the cell's rounded shape (it takes the top corner radius), the SAME on a hit and a rest, drawn on top of
    // everything in the cell (§6.6). Stopped ⇒ `playheadStep` nil ⇒ none (§6.5).
    if let p = d.playheadStep, p >= 0 && p < n {
        let cell = d.frames.cells[p]
        var c = ctx
        c.clip(to: RoundedRectangle(cornerRadius: M.cellRadius).path(in: cell))
        c.fill(Path(laneStripTickRect(cell: cell)), with: .color(Color(M.soundStroke)))
    }
}

/// STACK GREY §2.3: the stack footer chip — one grey segment per voice (lowest rank on the left, 1 pt gaps), each its own
/// `stackRankColour` fill + `stackRankInk` label (hidden on a too-narrow segment, §B2.3). A segment under 4 pt wide ⇒ one
/// chip at the lowest rank, as before. §2.4's sounding double-stroke goes round the WHOLE frame, once.
func laneStripDrawFooterChip(_ ctx: inout GraphicsContext, slot: CGRect, steps: Int, ranks: [Int], sounding: Bool, opacity: Double = 1, slim: Bool = false, labelled: Bool = true) {
    typealias M = LaneStripBandMetrics
    let frame = laneStripChipFrame(slot: slot)
    guard frame.width > 1, frame.height > 1, opacity > 0 else { return }
    // LANE STRIP CLARITY §1.3/§1.4: a slim band's chip is a flat colour bar — radius 1, no label, no stroke, 60 % / 100 %.
    let a = (slim ? laneStripSlimChipOpacity(sounding: sounding) : (sounding ? 1.0 : M.chipRestOpacity)) * opacity
    let radius = slim ? M.slimChipRadius : M.chipRadius
    let size = laneStripChipLabelSize(steps: steps)
    for seg in laneStripFooterSegments(frameWidth: frame.width, ranks: ranks) {
        let rect = CGRect(x: frame.minX + seg.x, y: frame.minY, width: seg.width, height: frame.height)
        ctx.fill(RoundedRectangle(cornerRadius: radius).path(in: rect), with: .color(Color(stackRankColour(rank: seg.rank)).opacity(a)))
        guard !slim, labelled else { continue }                              // §1.3: no labels on a slim band · CLARITY §3.3: an unlabelled chip shows no segment labels
        let label = "\(seg.rank)"
        if laneStripChipLabelFits(label, chipWidth: rect.width, size: size) {   // §2.3: each segment's own width
            ctx.draw(ctx.resolve(Text(label).font(laneStripChipFont(size)).foregroundColor(Color(stackRankInk(rank: seg.rank)).opacity(opacity))), at: CGPoint(x: rect.midX, y: rect.midY), anchor: .center)
        }
    }
    if sounding, !slim, opacity > 0.5 { laneStripDrawSoundStroke(&ctx, frame) }   // §2.4 (full bands only; §1.4: slim sounds by opacity alone)
}

/// STACK GREY §2.4 / LANE STRIP CLARITY §2.2–§2.3: the sounding mark on a chip — a 1 pt #F2F4F7 stroke on the inside edge
/// of the frame; the 1 pt #0D0F14 stroke just inside it draws only on a chip 12 pt or taller (`laneStripSoundStrokeHasInk`)
/// — in the 9 pt bands the ink stroke sat exactly on the 7 pt digit's cap/baseline and read as a strike-through.
/// Header, footer, split chips and the PLAY tiles' note chips all use it; the label is drawn AFTER this, on top (§2.1).
func laneStripDrawSoundStroke(_ ctx: inout GraphicsContext, _ frame: CGRect) {
    typealias M = LaneStripBandMetrics
    ctx.stroke(RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(Color(M.soundStroke)), lineWidth: 1)
    if laneStripSoundStrokeHasInk(chipHeight: frame.height) {
        ctx.stroke(RoundedRectangle(cornerRadius: max(0.5, M.chipRadius - 1)).path(in: frame.insetBy(dx: 1.5, dy: 1.5)), with: .color(Color(M.chipInk)), lineWidth: 1)
    }
}

/// §3.1 / §3.6: one header or footer chip. `fill` nil ⇒ the off-part outline look (grey stroke, grey label, no fill);
/// `.map`/`.rgb` ⇒ a filled chip with ink label (or, when `hollow`, a dashed stroke + label in the fill colour).
enum LaneStripChipFill { case map(EuclideousRGB); case rgb(EuclideousRGB) }
func laneStripDrawChip(_ ctx: inout GraphicsContext, slot: CGRect, steps: Int, fill: LaneStripChipFill?, label: String, hollow: Bool, sounding: Bool, opacity: Double = 1, slim: Bool = false) {
    typealias M = LaneStripBandMetrics
    let frame = laneStripChipFrame(slot: slot)
    guard frame.width > 1, frame.height > 1, opacity > 0 else { return }
    let radius = slim ? M.slimChipRadius : M.chipRadius                      // LANE STRIP CLARITY §1.3
    let shape = RoundedRectangle(cornerRadius: radius).path(in: frame)
    let size = laneStripChipLabelSize(steps: steps)
    let labelColour: Color
    let a = (slim ? laneStripSlimChipOpacity(sounding: sounding) : (sounding ? 1.0 : M.chipRestOpacity)) * opacity   // §B2.4 / CLARITY §1.4
    if let fill {
        let c = Color(fillRGB(fill))
        if hollow {
            ctx.stroke(RoundedRectangle(cornerRadius: radius).path(in: frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(c.opacity(a)), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
            labelColour = c
        } else {
            ctx.fill(shape, with: .color(c.opacity(a)))
            labelColour = Color(M.chipInk)
        }
        if sounding, !slim, opacity > 0.5 { laneStripDrawSoundStroke(&ctx, frame) }   // §2.4 (full bands; §1.4: slim sounds by opacity alone)
    } else {
        ctx.stroke(RoundedRectangle(cornerRadius: radius).path(in: frame.insetBy(dx: 0.5, dy: 0.5)), with: .color(Color(M.offChipStroke).opacity(opacity)), lineWidth: 1)
        labelColour = Color(M.offChipLabel)
    }
    guard !slim else { return }                                              // §1.3: no labels on a slim band
    if laneStripChipLabelFits(label, chipWidth: frame.width, size: size) {   // §B2.3: no label when the chip is narrower than the label + 2
        ctx.draw(ctx.resolve(Text(label).font(laneStripChipFont(size)).foregroundColor(labelColour.opacity(opacity))), at: CGPoint(x: frame.midX, y: frame.midY), anchor: .center)
    }
}
private func fillRGB(_ f: LaneStripChipFill) -> EuclideousRGB { switch f { case .map(let c): return c; case .rgb(let c): return c } }
