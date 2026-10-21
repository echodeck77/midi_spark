//  LaneStripPainter.swift
//  The lane card's STRIP: a riff contour over a row of notes keys (ferry "a riff contour over a row of notes keys, in place of the comet", 2026-10-21).
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
    /// The riff grid's empty cell (`riffGridCell`: white @ 8% over its panel — itself white @ 3.5% on the page ground (0.05, 0.055, 0.07)) as an opaque colour: ≈ #28292D. The ferry says #24262C; source wins.
    static let hitColumn = Color(h: 0x28292D)
    /// The riff grid's note cell (white @ 85% over that panel): ≈ #DCDCDD. The ferry says #DFE3EA; source wins.
    static let noteChip = Color(h: 0xDCDCDD)
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
    var hits: [EuclideousStripHit]
    /// The lane's hits of the pass the footers show (`bufIdx` and lap-local tick), its walk config and the absolute tick of the pass's first step — what the current chip needs to place the arrow's landed hit in this pass.
    var hitSteps: [EuclidHitStep]
    var cfg: EuclideousWalkLaneConfig?
    var lapStartTick: Int64?
    /// The current chip may show: the riff layer plays on this lane (on, and not SHADOWing) and its arrow isn't suppressed (MIDI IN with nothing held).
    var riffPlays: Bool
    /// LISTEN SHADOW: the lane's riff and notes are ignored — no chips, and the partner-colour band drawn over the key row stands in for the keys.
    var shadowed: Bool
    /// The hits' VoiceOver sentence (6.1); the bar adds "on step N" and "silent at this step", which move with the clock.
    var hitsPhrase: String
}

/// Everything one frame of the strip needs.
struct EuclideousStripFrameInput {
    var plan: EuclideousStripPlan
    /// The rhythm's hit at each step as the strip draws it (a rest is a dashed cell with no key).
    var hitMask: [Bool]
    var frames: [EuclideousStripFrame]
    var tint: Color
    /// nil while the lane or the transport is stopped.
    var playhead: EuclideousStripPlayhead?
    var areaMinX: CGFloat
    var areaMaxX: CGFloat
    /// The step whose chip is the lane's current one (1.4), nil when there is none.
    var current: Int?
    var riffStrikes: [EuclideousStripTileStrike?]
    var noteStrikes: [EuclideousStripTileStrike?]
    var scale: Double
    var reduceMotion: Bool
}

private func stripFont(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// A label that fits `maxWidth`: truncated at the tail with an ellipsis, never shrunk.
private func fitted(_ ctx: GraphicsContext, _ s: String, size: CGFloat, maxWidth: CGFloat) -> String {
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

    // 1. the track: a dark cell per hit, a dashed one per rhythm rest, and a lane-colour inner ring on a gap
    for i in 0..<n {
        let col = d.frames[i].column
        let shape = RoundedRectangle(cornerRadius: M.columnRadius).path(in: col)
        if i < d.hitMask.count, d.hitMask[i] {
            ctx.fill(shape, with: .color(P.hitColumn))
            if i < d.plan.hits.count, d.plan.hits[i].kind == .gap {
                ctx.stroke(RoundedRectangle(cornerRadius: M.columnRadius - 0.5).path(in: col.insetBy(dx: 0.5, dy: 0.5)), with: .color(d.tint.opacity(0.45)), lineWidth: 1)
            }
        } else {
            ctx.fill(shape, with: .color(P.rhythmRest))
            ctx.stroke(RoundedRectangle(cornerRadius: M.columnRadius - 0.5).path(in: col.insetBy(dx: 0.5, dy: 0.5)), with: .color(P.restDash), style: dash)
        }
    }

    // 2. the playhead: one column wide, over the cells and under the chips, clipped to the step area
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

    // 3. the chips
    for i in 0..<n where i < d.plan.hits.count {
        guard let chip = d.plan.hits[i].chip, i < d.hitMask.count, d.hitMask[i] else { continue }
        let isCurrent = d.current == i && !chip.hollow && !chip.grey
        let strike = i < d.riffStrikes.count ? d.riffStrikes[i] : nil
        let env = strike.map { euclideousPulseEnvelopes(velocity: $0.velocity, seconds: $0.seconds, scale: d.scale) } ?? .none
        let look = euclideousStripChipLook(env, scale: d.scale, reduceMotion: d.reduceMotion)
        let frame = euclideousStripChipFrame(column: d.frames[i].column, rank: chip.rank).offsetBy(dx: 0, dy: look.dip)
        let shape = RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame)
        if chip.hollow {
            let outline = RoundedRectangle(cornerRadius: M.chipRadius).path(in: frame.insetBy(dx: 0.5, dy: 0.5))
            if look.glowAlpha > 0.01 {
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: d.tint.opacity(look.glowAlpha), radius: look.glowBlur / 2))
                    layer.stroke(outline, with: .color(d.tint), style: dash)
                }
            }
            ctx.stroke(outline, with: .color(d.tint), style: dash)
        } else {
            if look.glowAlpha > 0.01 {
                ctx.drawLayer { layer in
                    layer.addFilter(.shadow(color: d.tint.opacity(look.glowAlpha), radius: look.glowBlur / 2))   // a SwiftUI radius is about half a CSS blur
                    layer.fill(shape, with: .color(chip.grey ? P.greyChip : P.noteChip))
                }
            }
            ctx.fill(shape, with: .color(chip.grey ? P.greyChip : P.noteChip))
            if isCurrent {
                // the arrow's own one-lane fill over the light chip — the arrow-on-its-cell look (the lane colour at 95% falling to 55%)
                ctx.fill(shape, with: .linearGradient(Gradient(colors: [d.tint.opacity(EuclideousArrowStyle.topAlpha), d.tint.opacity(EuclideousArrowStyle.bottomAlpha)]),
                                                      startPoint: CGPoint(x: frame.midX, y: frame.minY), endPoint: CGPoint(x: frame.midX, y: frame.maxY)))
            }
        }
        if euclideousStripShowsChipLabel(columnWidth: d.frames[i].column.width) {
            let text = Text("\(chip.column)").font(stripFont(M.chipLabelSize)).foregroundColor(chip.hollow ? d.tint : P.ink)
            ctx.draw(ctx.resolve(text), at: CGPoint(x: frame.midX, y: frame.midY), anchor: .center)
        }
    }

    // 4. the key row (a SHADOWing lane has none: the partner-colour band over this row stands in)
    guard !d.plan.shadowed else { return }
    for i in 0..<n where i < d.hitMask.count && d.hitMask[i] {
        let key = d.frames[i].key
        let k = i < d.plan.hits.count ? d.plan.hits[i].key : nil
        let plays = k?.plays ?? false
        let shape = RoundedRectangle(cornerRadius: M.keyRadius).path(in: key)
        let strike = i < d.noteStrikes.count ? d.noteStrikes[i] : nil
        let env = strike.map { euclideousPulseEnvelopes(velocity: $0.velocity, seconds: $0.seconds, scale: d.scale) } ?? .none
        let look = euclideousStripKeyLook(env, scale: d.scale, reduceMotion: d.reduceMotion)
        if plays && look.glowAlpha > 0.01 {
            ctx.drawLayer { layer in
                layer.addFilter(.shadow(color: d.tint.opacity(look.glowAlpha), radius: 5))   // blur 10, spread 1
                layer.fill(RoundedRectangle(cornerRadius: M.keyRadius + 1).path(in: key.insetBy(dx: -1, dy: -1)), with: .color(plays ? P.keyPlays : P.keyDark))
            }
        }
        ctx.fill(shape, with: .color(plays ? P.keyPlays : P.keyDark))
        ctx.stroke(RoundedRectangle(cornerRadius: M.keyRadius - 0.5).path(in: key.insetBy(dx: 0.5, dy: 0.5)), with: .color(plays ? P.keyPlaysBorder : P.keyDarkBorder), lineWidth: 1)
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
        if look.ringAlpha > 0.01 {
            ctx.stroke(RoundedRectangle(cornerRadius: M.keyRadius - 0.75).path(in: key.insetBy(dx: 0.75, dy: 0.75)), with: .color(d.tint.opacity(look.ringAlpha)), lineWidth: 1.5)
        }
        if let label = k.label, euclideousStripShowsKeyLabel(keyWidth: key.width) {
            let s = fitted(ctx, label, size: M.keyLabelSize, maxWidth: key.width - 2)
            let text = Text(s).font(stripFont(M.keyLabelSize)).foregroundColor(look.labelLit ? P.keyLabelLit : P.keyLabel)
            ctx.draw(ctx.resolve(text), at: CGPoint(x: key.midX, y: key.minY + 1 + M.keyLabelLine / 2), anchor: .center)
        }
    }
}
