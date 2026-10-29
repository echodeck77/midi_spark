//  LaneStripPainter.swift
//  The lane card's STRIP: a riff contour over a row of notes keys (ferry "a riff contour over a row of notes keys, in place of the comet", 2026-10-21).
//  LANE STRIP readability ferry (2026-10-22): each layer has one job — rhythm = lane colour, riff = the white
//  chips, notes = the key row. CLARITY PASS (2026-10-23) §1: the rhythm's columns are evenly spaced (no group
//  gaps) and shaded in alternating beat groups — a hit is the lane colour at 42 % / 30 %, a rest a solid grey,
//  a gap a rest grey with a lane ring — with the floor bar kept on hits only.
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `RiffArrowPainter.swift` / `NotesTabPainter.swift`: every frame, height, label, chip, key, playhead position and strike
//  look comes from the pure functions in Derivations.swift (`euclideousStrip*`), so the drawing and the tests can never disagree. This file paints what those return, once per display frame
//  (the strip's own `TimelineView` in `EuclidCometBar`). It keeps no state. Colours are the riff grid's and the NOTES tab's own, reported where the ferry's numbers differ from the source.

import SwiftUI

private extension Color {
    init(h: UInt32) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}

enum EuclideousStripPalette {
    /// The riff grid's note cell (white @ 85% over that panel): ≈ #DCDCDD. The ferry says #DFE3EA; source wins.
    static let noteChip = Color(h: 0xDCDCDD)
    /// The dashed rest look of the RESTART TILES ferry — no longer drawn since the CLARITY PASS (a rest is a solid grey from `euclideousStripColumnLook`); kept, hide-don't-delete.
    static let rhythmRest = Color(h: 0x1A1C21), restDash = Color(h: 0x3A3E47)
    static let greyChip = Color(h: 0x6B707A)
    static let ink = Color(h: 0x0D0F14)
    /// The NOTES tab's key looks (`EuclideousNotesKeyView`): a received note, and an octave copy / an unlit key.
    static let keyPlays = Color(h: 0x30343C), keyPlaysBorder = Color(h: 0x454A54)
    static let keyDark = Color(h: 0x17191E), keyDarkBorder = Color(h: 0x202329)
    static let keyLabel = Color(h: 0xCBCCCE)   // white @ 75% over #30343C — the tab key's label
    static let keyLabelLit = Color(h: 0xF2F4F7)
}

/// What the page works out per body for one lane's strip (nothing here changes per frame).
struct EuclideousStripPlan {
    /// The pass the footers show, one leg for FWD / BKW and two (the up sweep, then the way back) for PING-PONG: the frame draws the leg the lane is on.
    var legs: [EuclideousStripLeg]
    /// The ticks in one sweep (the step count): PING-PONG's second leg starts at this lap-local tick.
    var sweepLength: Int
    /// The lane's walk config and the absolute tick of the shown pass's first step — what the current chip needs to place the arrow's landed hit in this pass.
    var cfg: EuclideousWalkLaneConfig?
    var lapStartTick: Int64?
    /// The current chip may show: the riff layer plays on this lane (on, and not SHADOWing) and its arrow isn't suppressed (MIDI IN with nothing held).
    var riffPlays: Bool
    /// LISTEN SHADOW: the lane's riff and notes are ignored — no chips, and the partner-colour band drawn over the key row stands in for the keys.
    var shadowed: Bool
    /// The hits' VoiceOver sentence (6.1); the bar adds "on step N" and "silent at this step", which move with the clock.
    var hitsPhrase: String
    /// HOCKET §9.3: the document's rules, the live counts and which lane this is — what the strip reads each frame (from the TimelineView, never observed) to draw a resting layer's marks hollow and to flash a layer in the colour of the lane it left on.
    var hocketRules: [HocketRule] = []
    var hocketLive: HocketLiveModel? = nil
    var lane = 0
    /// The riff / notes TAB is on (an off part shows only the clarity pass's off look; hocket states don't apply, 9.1).
    var riffPartOn = true
    var notesPartOn = true

    func legIndex(raw: Double) -> Int { euclideousStripLegIndex(raw: raw, n: sweepLength, legCount: legs.count) }
}

/// Everything one frame of the strip needs.
struct EuclideousStripFrameInput {
    /// What the strip draws for each step (the leg the lane is on): a rhythm rest is a dashed cell with no key.
    var hits: [EuclideousStripHit]
    var shadowed: Bool
    var frames: [EuclideousStripFrame]
    /// CLARITY PASS §1.2: the beat group size (`euclidStepGroupSize(forRate:)` — 3 under a triplet, else 4); display only.
    var groupSize: Int
    var tint: Color
    /// nil while the lane or the transport is stopped.
    var playhead: EuclideousStripPlayhead?
    var areaMinX: CGFloat
    var areaMaxX: CGFloat
    /// The step whose chip is the lane's current one (1.4), nil when there is none.
    var current: Int?
    var riffStrikes: [EuclideousStripTileStrike?]
    var noteStrikes: [EuclideousStripTileStrike?]
    /// HOCKET §9.3: what each layer draws while a rule is lit — hollow marks and no flash while RESTING, the flash colour otherwise (nil = no hocket: exactly as before).
    var riffLook: HocketStripLayerLook? = nil
    var notesLook: HocketStripLayerLook? = nil
    var ownLane = 0
    var scale: Double
    var reduceMotion: Bool
}

/// HOCKET §9.3: the two layers' looks for one frame — nil when nothing is lit, the transport is stopped, or the part is off.
func hocketStripLooks(_ s: EuclideousStripPlan, playing: Bool) -> (riff: HocketStripLayerLook?, notes: HocketStripLayerLook?) {
    guard playing, let live = s.hocketLive, s.hocketRules.contains(where: { $0.isLit }) else { return (nil, nil) }
    let riff = s.riffPartOn ? hocketStripLayerLook(lane: s.lane, view: hocketLivePartView(lane: s.lane, notes: false, rules: s.hocketRules, live: live)) : nil
    let notes = s.notesPartOn ? hocketStripLayerLook(lane: s.lane, view: hocketLivePartView(lane: s.lane, notes: true, rules: s.hocketRules, live: live)) : nil
    return (riff, notes)
}
/// The colour a strike's flash and glow take: the lane's own `tint` unless the strike's notes left on ANOTHER lane's output — then that lane's lane100 (HOCKET §9.3).
private func flashTint(_ d: EuclideousStripFrameInput, _ strike: EuclideousStripTileStrike?) -> Color {
    guard let strike else { return d.tint }
    let lane = hocketFlashLane(ownLane: d.ownLane, dest: strike.dest)
    return lane == d.ownLane ? d.tint : Color(h: HocketPalette.lane100(lane).hex)
}

private func stripFont(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// A label that fits `maxWidth`: truncated at the tail with an ellipsis, never shrunk.
private func fitted(_ ctx: GraphicsContext, _ s: String, size: CGFloat, maxWidth: CGFloat) -> String {
    if CGFloat(s.count) * 5 <= maxWidth { return s }   // a monospaced 7 pt heavy glyph is ≈ 4.4 pt wide: this much room needs no measuring (the text resolve is the costly part of a frame)
    var t = s
    while t.count > 1 {
        let w = ctx.resolve(Text(t).font(stripFont(size))).measure(in: CGSize(width: 1000, height: 100)).width
        if w <= maxWidth { return t }
        t = String(t.dropLast(t.hasSuffix("\u{2026}") ? 2 : 1)) + "\u{2026}"
        if t == "\u{2026}" { break }
    }
    return t
}

func drawEuclideousStrip(_ ctx: inout GraphicsContext, _ d: EuclideousStripFrameInput) {
    typealias M = EuclideousStripMetrics
    typealias P = EuclideousStripPalette
    let n = d.frames.count
    let dash = StrokeStyle(lineWidth: 1, dash: [3, 2])

    // 1. the track (CLARITY PASS 2026-10-23 §1): an evenly spaced column per step, shaded in alternating beat groups (A, B, A, B from step 1 — 4 steps, 3 under a triplet) so you count blocks, not cells. A hit is the
    // lane colour (42 % in group A, 30 % in B), a rhythm rest a SOLID grey (#41454F / #30333A — present, never dashed), a gap (a hit on a riff rest) its group's rest grey with a 1 pt lane ring at 45 %. All of it is
    // `euclideousStripColumnLook`; this loop only paints what it returns.
    for i in 0..<n {
        let col = d.frames[i].column
        let shape = RoundedRectangle(cornerRadius: M.columnRadius).path(in: col)
        let look = euclideousStripColumnLook(kind: i < d.hits.count ? d.hits[i].kind : .rhythmRest, tone: euclideousStepGroupTone(step: i, groupSize: d.groupSize))
        switch look.fill {
        case .lane(let alpha): ctx.fill(shape, with: .color(d.tint.opacity(alpha)))
        case .solid(let hex): ctx.fill(shape, with: .color(Color(h: hex)))
        }
        if look.ringAlpha > 0 {
            let inset = look.ringWidth / 2
            ctx.stroke(RoundedRectangle(cornerRadius: M.columnRadius - inset).path(in: col.insetBy(dx: inset, dy: inset)), with: .color(d.tint.opacity(look.ringAlpha)), lineWidth: look.ringWidth)
        }
    }

    // 2. the playhead: one column wide, over the cells and under the floor bars/chips, clipped to the step area
    if let ph = d.playhead {
        let band = CGRect(x: ph.x, y: 0, width: ph.width, height: M.trackH)
        ctx.drawLayer { layer in
            layer.clip(to: Path(CGRect(x: d.areaMinX, y: 0, width: max(0, d.areaMaxX - d.areaMinX), height: M.trackH)))
            let shape = RoundedRectangle(cornerRadius: M.columnRadius).path(in: band)
            layer.fill(shape, with: .color(d.tint.opacity(M.playheadFillAlpha)))
            layer.clip(to: shape)
            let edge = ph.movingRight ? CGRect(x: band.maxX - M.playheadEdgeW, y: 0, width: M.playheadEdgeW, height: M.trackH)
                                      : CGRect(x: band.minX, y: 0, width: M.playheadEdgeW, height: M.trackH)
            layer.fill(Path(edge), with: .color(d.tint.opacity(M.playheadEdgeAlpha)))
        }
    }

    // 3. the floor bars: lane-coloured, over the columns and the playhead, under the chips — the even
    // comb that makes the Euclid spread countable at a glance. On hits only (a gap reads as a rest the rhythm still hits: its ring is its mark).
    for i in 0..<n where i < d.hits.count && euclideousStripColumnLook(kind: d.hits[i].kind, tone: .a).floorBar {
        let bar = euclideousStripFloorBarFrame(column: d.frames[i].column)
        ctx.fill(RoundedRectangle(cornerRadius: M.floorBarRadius).path(in: bar), with: .color(d.tint))
    }

    // 4. the chips
    for i in 0..<n where i < d.hits.count {
        guard let chip = d.hits[i].chip else { continue }
        let isCurrent = d.current == i && !chip.hollow && !chip.grey && d.riffLook?.hollow != true
        let riffRests = d.riffLook?.hollow == true                                            // HOCKET §9.3: a resting layer's marks are hollow and don't flash
        let strike = (i < d.riffStrikes.count && !riffRests) ? d.riffStrikes[i] : nil
        let flash = flashTint(d, strike)
        let env = strike.map { euclideousPulseEnvelopes(velocity: $0.velocity, seconds: $0.seconds, scale: d.scale) } ?? .none
        let look = euclideousStripChipLook(env, scale: d.scale, reduceMotion: d.reduceMotion)
        let frame = euclideousStripChipFrame(column: d.frames[i].column, rank: chip.rank).offsetBy(dx: 0, dy: look.dip)
        let shape = RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame)
        if riffRests {
            ctx.stroke(RoundedRectangle(cornerRadius: M.chipRadius - 0.75).path(in: frame.insetBy(dx: 0.75, dy: 0.75)), with: .color(chip.grey ? P.greyChip : P.noteChip), lineWidth: HocketStripLayerLook.hollowWidth)
        } else if chip.hollow {
            let outline = RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame.insetBy(dx: 0.5, dy: 0.5))
            if look.glowAlpha > 0.01 {
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: flash.opacity(look.glowAlpha), radius: look.glowBlur / 2))
                    layer.stroke(outline, with: .color(d.tint), style: dash)
                }
            }
            ctx.stroke(outline, with: .color(d.tint), style: dash)
        } else {
            if look.glowAlpha > 0.01 {
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: flash.opacity(look.glowAlpha), radius: look.glowBlur / 2))   // a SwiftUI radius is about half a CSS blur
                    layer.fill(shape, with: .color(chip.grey ? P.greyChip : P.noteChip))
                }
            }
            ctx.fill(shape, with: .color(chip.grey ? P.greyChip : P.noteChip))
            if look.glowAlpha > 0.01 && strike != nil && flash != d.tint { ctx.fill(shape, with: .color(flash.opacity(look.glowAlpha))) }   // an AWAY flash: the chip takes the colour of the lane it went to (§9.3)
            if isCurrent {
                // the arrow's own one-lane fill over the light chip — the arrow-on-its-cell look (the lane colour at 95% falling to 55%)
                ctx.fill(shape, with: .linearGradient(Gradient(colors: [d.tint.opacity(EuclideousArrowStyle.topAlpha), d.tint.opacity(EuclideousArrowStyle.bottomAlpha)]),
                                                      startPoint: CGPoint(x: frame.midX, y: frame.minY), endPoint: CGPoint(x: frame.midX, y: frame.maxY)))
            }
        }
        // POLY RIFF: the other notes starting on this column — a plain chip at each one's height (no label, no flash: the main chip carries them)
        for extra in d.hits[i].extraRanks {
            ctx.fill(RoundedRectangle(cornerRadius: M.chipRadius).path(in: euclideousStripChipFrame(column: d.frames[i].column, rank: extra).offsetBy(dx: 0, dy: look.dip)), with: .color(riffRests ? Color.clear : P.noteChip))
        }
        if euclideousStripShowsChipLabel(columnWidth: d.frames[i].column.width) {
            let text = Text("\(chip.column)").font(stripFont(M.chipLabelSize)).foregroundColor(riffRests ? (chip.grey ? P.greyChip : P.noteChip) : (chip.hollow ? d.tint : P.ink))
            ctx.draw(ctx.resolve(text), at: CGPoint(x: frame.midX, y: frame.midY), anchor: .center)
        }
    }

    // 5. the key row (a SHADOWing lane has none: the partner-colour band over this row stands in)
    guard !d.shadowed else { return }
    for i in 0..<n where i < d.hits.count && d.hits[i].kind != .rhythmRest {
        let key = d.frames[i].key
        let k = d.hits[i].key
        let plays = k?.plays ?? false
        let shape = RoundedRectangle(cornerRadius: M.keyRadius).path(in: key)
        let notesRest = d.notesLook?.hollow == true                                           // HOCKET §9.3: a resting layer's keys are hollow and don't flash
        let strike = (i < d.noteStrikes.count && !notesRest) ? d.noteStrikes[i] : nil
        let flash = flashTint(d, strike)
        let env = strike.map { euclideousPulseEnvelopes(velocity: $0.velocity, seconds: $0.seconds, scale: d.scale) } ?? .none
        let look = euclideousStripKeyLook(env, scale: d.scale, reduceMotion: d.reduceMotion)
        // a strike lights the key it lands on even when the pass shown says the notes were not due there (the engine struck: the display must not hide it)
        if look.glowAlpha > 0.01 {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: flash.opacity(look.glowAlpha), radius: 5))   // blur 10, spread 1
                layer.fill(RoundedRectangle(cornerRadius: M.keyRadius + 1).path(in: key.insetBy(dx: -1, dy: -1)), with: .color(plays ? P.keyPlays : P.keyDark))
            }
        }
        if notesRest {   // §9.3: hollow — a 1.5 pt outline in the key's usual (border) colour instead of its fill
            ctx.stroke(RoundedRectangle(cornerRadius: M.keyRadius - 0.75).path(in: key.insetBy(dx: 0.75, dy: 0.75)), with: .color(plays ? P.keyPlaysBorder : P.keyDarkBorder), lineWidth: HocketStripLayerLook.hollowWidth)
        } else {
            ctx.fill(shape, with: .color(plays ? P.keyPlays : P.keyDark))
            ctx.stroke(RoundedRectangle(cornerRadius: M.keyRadius - 0.5).path(in: key.insetBy(dx: 0.5, dy: 0.5)), with: .color(plays ? P.keyPlaysBorder : P.keyDarkBorder), lineWidth: 1)
        }
        if look.ringAlpha > 0.01 {
            ctx.stroke(RoundedRectangle(cornerRadius: M.keyRadius - 0.75).path(in: key.insetBy(dx: 0.75, dy: 0.75)), with: .color(flash.opacity(look.ringAlpha)), lineWidth: 1.5)
        }
        guard plays, let k else { continue }
        // the lane bar — or, below 100% CHANCE, a ring that says "may skip"
        let barW = max(0, key.width - 2 * M.barInset)
        if barW > 0 {
            if k.chanceRing {
                let ring = CGRect(x: key.minX + M.barInset, y: key.maxY - M.barBottom - M.ringH, width: barW, height: M.ringH)
                ctx.stroke(RoundedRectangle(cornerRadius: 1).path(in: ring.insetBy(dx: 0.5, dy: 0.5)), with: .color(d.tint), lineWidth: 1)
            } else {
                let bar = CGRect(x: key.minX + M.barInset, y: key.maxY - M.barBottom - M.barH, width: barW, height: M.barH)
                ctx.fill(RoundedRectangle(cornerRadius: 1).path(in: bar), with: .color(d.tint))
            }
        }
        if let label = k.label, euclideousStripShowsKeyLabel(keyWidth: key.width) {
            let s = fitted(ctx, label, size: M.keyLabelSize, maxWidth: key.width - 2)
            let text = Text(s).font(stripFont(M.keyLabelSize)).foregroundColor(look.labelLit ? P.keyLabelLit : P.keyLabel)
            ctx.draw(ctx.resolve(text), at: CGPoint(x: key.midX, y: key.minY + 1 + M.keyLabelLine / 2), anchor: .center)
        }
    }
}
