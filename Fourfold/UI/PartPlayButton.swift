//  PartPlayButton.swift — PLAY RIFF / PLAY STACK ferry (2026-11-07): the lane card's two part-switch buttons.
//
//  The play tile becomes PLAY RIFF and the SOLO tile becomes PLAY STACK (the notes part). A neutral tile with "PLAY" over the part name and a small lane-colour triangle LAMP that lights when the part is on and flashes as it plays —
//  "a hint of the play button they replace, without claiming to start or stop anything" (Paul). Every colour, the lamp geometry and the flash come from the pure functions in Derivations.swift (`euclideousPartPlay*`), so the drawing,
//  the tests and the flash decision cannot disagree. A tap switches the part through the page's `cardBackToggle` funnel (one undo step). Lane PLAY and lane SOLO leave the card — MIX keeps the strip play and the per-part solo.

import SwiftUI

/// §2.3 the lamp triangle, mapped from the 8×9 box's path bounds to the frame (a test shares the points via `EuclideousPartPlayLamp`).
struct EuclideousPartPlayLampShape: Shape {
    func path(in rect: CGRect) -> Path {
        let b = EuclideousPartPlayLamp.pathBounds
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: rect.minX + (q.x - b.minX) / b.width * rect.width, y: rect.minY + (q.y - b.minY) / b.height * rect.height) }
        var path = Path()
        let pts = EuclideousPartPlayLamp.points
        path.move(to: p(pts[0])); path.addLine(to: p(pts[1])); path.addLine(to: p(pts[2])); path.closeSubpath()
        return path
    }
}

/// PLAY BUTTONS RAIL+NOTE §2.2: which edge the running-part rail runs along — the tile squares those two corners and omits
/// that edge's stroke (the rail IS the edge). nil = off / the BUILD page ⇒ a full rounded-rect stroke on all four sides.
enum EuclideousTileRailEdge { case top, bottom }

/// §2 the button. `isNotes` picks RIFF vs STACK; `accent` is the lane colour; `on` is the part's state; `sounding` (§1.4) is
/// whether the part's held set is non-empty (the triangle 100 % vs 55 %); `railEdge` (§2.2) squares the rail-edge corners.
/// Frame defaults to the card's 44 × 44 (the play / SOLO tile).
struct EuclideousPartPlayButton: View {
    let isNotes: Bool
    let accent: Color
    let on: Bool
    var sounding: Bool = false
    var noteChip: EuclideousPartNoteChip? = nil   // §4: nil ⇒ the word PLAY; non-nil ⇒ a chip of the part's most recent note-on hit
    var railEdge: EuclideousTileRailEdge? = nil
    var tile = CGSize(width: EuclideousLaneCardMetrics.playButtonW, height: EuclideousLaneCardMetrics.cometRowH)
    var target: CGSize? = nil
    var axLabel: String = ""
    let onTap: () -> Void

    @GestureState private var pressed = false   // §1.5: filled #2B2D33 while a touch is down, cleared at once on release

    private var look: EuclideousPartPlayLook { euclideousPartPlayLook(on: on) }
    private var type: EuclideousPartPlayType { euclideousPartPlayType(height: tile.height) }   // §A3: every size from the button's height

    var body: some View {
        content
            .frame(width: tile.width, height: tile.height)
            .background(tileBackground)   // §1.1/§1.2/§1.5 no fill, a 1 pt #5B606A stroke, #2B2D33 while pressed
            .frame(width: target?.width ?? tile.width, height: target?.height ?? tile.height, alignment: .top)
            .contentShape(Rectangle())
            // §1.5/§1.6: ONE min-0 drag does BOTH the touch-down #2B2D33 highlight (updating) and the tap (onEnded, when the
            // release is within the tile). The earlier `.simultaneousGesture(DragGesture) + .onTapGesture` pair swallowed the
            // tap — the riff/stack toggle stopped working. No hold, no double-tap (§2.6); the action is unchanged (§1.6).
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($pressed) { _, s, _ in s = true }
                    .onEnded { v in
                        let w = target?.width ?? tile.width, h = target?.height ?? tile.height
                        if (0...w).contains(v.location.x) && (0...h).contains(v.location.y) { onTap() }
                    }
            )
            .transaction { $0.animation = nil }   // §A4.6 looks change at once, with no ease
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(axLabel)
            .accessibilityValue(on ? "on" : "off")   // §6.2 / §7.1 unchanged
            .accessibilityAddTraits(.isButton)
            .ringToggleTrait()
    }

    private var content: some View {
        VStack(spacing: type.lineGap) {
            topLine
            nameText
        }
    }
    /// §4.1: line 1 is the triangle, then the word PLAY — or, while the part is running and has started a note, a chip of its
    /// most recent note-on hit (§4.2: 3 pt right of the triangle, filling to 3 pt inside the tile's right edge).
    @ViewBuilder private var topLine: some View {
        if let noteChip {
            HStack(spacing: 3) { lamp; noteChipView(noteChip) }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 3)
        } else {
            HStack(spacing: type.lampGap) { lamp; playText }   // §A3.1 the lamp, then PLAY — centred as a group
        }
    }
    /// §4.3: the chip, drawn by the strip's OWN shared chip function into this frame — riff = the header chip (riff-map fill +
    /// its column label), stack = the footer split (one grey segment per voice). `sounding` gives 100 % + strokes, else 78 %.
    @ViewBuilder private func noteChipView(_ nc: EuclideousPartNoteChip) -> some View {
        let hH = LaneStripBandMetrics.bandH(T: tile.height)   // §4.2 the band height, as if the part were on (review B1: the one formula, no inline copy)
        Canvas { ctx, size in
            let slot = CGRect(origin: .zero, size: size)
            if isNotes {
                laneStripDrawFooterChip(&ctx, slot: slot, steps: 8, ranks: nc.ranks, sounding: nc.sounding)
            } else if let chip = nc.chip {
                laneStripDrawChip(&ctx, slot: slot, steps: 8, fill: .map(riffMapColour(column: chip.column, rank: chip.rank)), label: "\(chip.column)", hollow: chip.hollow, sounding: nc.sounding)
            }
        }
        .frame(maxWidth: .infinity).frame(height: hH)
        .allowsHitTesting(false)   // §4.8: the chip never takes touches — a tap on it is a tap on the tile (it was eating the toggle)
    }
    private var playText: some View {
        Text("PLAY").font(.system(size: type.playSize, weight: .heavy, design: .monospaced)).tracking(type.playTracking).foregroundColor(Color(hex: look.playHex))
            .lineLimit(1).frame(height: type.playLineH)
    }
    private var nameText: some View {
        Text(isNotes ? "STACK" : "RIFF").font(.system(size: type.nameSize, weight: .heavy, design: .monospaced)).tracking(type.nameTracking)
            .foregroundColor(Color(hex: look.nameHex)).lineLimit(1).truncationMode(.tail)   // §A3.4 truncate, never shrink
            .fixedSize(horizontal: false, vertical: true).frame(height: type.nameLineH)   // the line box is 1.06 × the size; the glyphs keep their natural height inside it
    }
    private var tileBackground: some View {
        let radius = EuclideousPartPlayLook.tileRadius
        return ZStack {
            // §1.5: the pressed fill — #2B2D33 only while a touch is down (§1.1: nothing at rest, the card ground shows through).
            if pressed { RoundedRectangle(cornerRadius: radius).fill(Color(hex: EuclideousPartPlayLook.tilePressedFillHex)) }
            // §1.2 / §2.2: a 1 pt #5B606A stroke inside the frame; a rail edge omits its own edge + squares its two corners (the rail is the edge).
            tileStrokePath(CGRect(origin: .zero, size: tile).insetBy(dx: 0.5, dy: 0.5), radius: radius - 0.5, open: railEdge)
                .stroke(Color(hex: EuclideousPartPlayLook.tileStrokeHex), lineWidth: 1)
        }
    }

    /// §2.2: the tile stroke — a full rounded rect (nil), or an open 3-sided path with the rail edge omitted and its two
    /// corners square. `addArc(tangent1End:tangent2End:radius:)` rounds each far corner regardless of winding.
    private func tileStrokePath(_ r: CGRect, radius: CGFloat, open: EuclideousTileRailEdge?) -> Path {
        let rr = max(0, min(radius, min(r.width, r.height) / 2))
        guard let open else { return RoundedRectangle(cornerRadius: rr).path(in: r) }
        var p = Path()
        switch open {
        case .top:      // riff: the rail is on top — start at the square top-left, round the two bottom corners, end at the square top-right
            p.move(to: CGPoint(x: r.minX, y: r.minY))
            p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rr)
            p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: rr)
            p.addLine(to: CGPoint(x: r.maxX, y: r.minY))
        case .bottom:   // stack: the rail is on the bottom — start at the square bottom-left, round the two top corners, end at the square bottom-right
            p.move(to: CGPoint(x: r.minX, y: r.maxY))
            p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: rr)
            p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: rr)
            p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        }
        return p
    }

    /// §1.4 the lamp: the §2.3 triangle. ON = the lane colour (filled + a lane100 stroke), at 100 % while the part's held set
    /// is non-empty and `lampRestOpacity` (55 %) otherwise — no glow, no ease. OFF = no fill, a 1 pt #C9CDD4 outline.
    private var lamp: some View {
        let sz = CGSize(width: type.lampW, height: type.lampH)
        return Group {
            if look.lampFilled {
                EuclideousPartPlayLampShape().fill(accent)
                    .overlay(EuclideousPartPlayLampShape().stroke(accent, style: StrokeStyle(lineWidth: type.lampStroke, lineJoin: .round)))
                    .frame(width: sz.width, height: sz.height)
                    .opacity(sounding ? 1 : EuclideousPartPlayLook.lampRestOpacity)
            } else {
                EuclideousPartPlayLampShape().stroke(Color(hex: look.lampStrokeHex), style: StrokeStyle(lineWidth: type.lampStroke, lineJoin: .round))
                    .frame(width: sz.width, height: sz.height)
            }
        }
        .frame(width: sz.width, height: sz.height)
    }
}
