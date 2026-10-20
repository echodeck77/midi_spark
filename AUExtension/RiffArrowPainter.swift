//  RiffArrowPainter.swift
//  The riff panel's blended ARROWS and lane RAILS (ferry "Riff panel: compact riff tabs, big arrows that blend, and lane rails under the grid", 2026-10-19).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `WalkTagPainter.swift` / `LanesPanelPainter.swift`: every number — the arrow's size,
//  outline, label, fill stops, its flare, a rail segment's look — comes from the pure functions in Derivations.swift (`euclideousArrowSpec`, `euclideousRailSpec`, …) so
//  the drawing and the tests can never disagree. This file paints what those return. It keeps no state.

import SwiftUI

private extension Color {
    init(_ c: EuclideousRGB, alpha: Double = 1) {
        self.init(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, opacity: alpha)
    }
}
private let riffInk = Color(.sRGB, red: 13.0 / 255, green: 15.0 / 255, blue: 20.0 / 255, opacity: 1)       // #0D0F14
private let riffSharedHollowLabel = Color(.sRGB, red: 242.0 / 255, green: 244.0 / 255, blue: 247.0 / 255, opacity: 1)   // #F2F4F7

/// An arrow's outline as a SwiftUI shape: the pure path commands (or a capsule) drawn in the rect's own coordinates.
struct EuclideousArrowShape: Shape {
    let outline: EuclideousArrowOutline
    func path(in rect: CGRect) -> Path {
        switch outline {
        case .capsule: return Capsule().path(in: rect)
        case .path(let cmds):
            var p = Path()
            func pt(_ q: CGPoint) -> CGPoint { CGPoint(x: rect.minX + q.x, y: rect.minY + q.y) }
            for c in cmds {
                switch c {
                case .move(let q): p.move(to: pt(q))
                case .line(let q): p.addLine(to: pt(q))
                case .quad(let to, let control): p.addQuadCurve(to: pt(to), control: pt(control))
                case .close: p.closeSubpath()
                }
            }
            return p
        }
    }
}

/// One cell's arrow (RIFF PANEL ferry §4): filled (one lane: the comet tile's gradient; shared: the OKLCH blend under a white / black highlight) with a 1pt-down shadow
/// that follows the shape, or HOLLOW on a rest (a dashed stroke inside the shape, no fill, no shadow); the lanes' numbers on it in #0D0F14 (the lane colour, or #F2F4F7
/// when shared, if hollow), truncated and never shrunk; a flare glow and a 1.06 scale about its centre while a lane in it strikes.
struct EuclideousArrowView: View {
    let spec: EuclideousArrowSpec
    private typealias S = EuclideousArrowStyle
    @Environment(\.accessibilityReduceMotion) private var reduceMotion   // PULSE §7.3: no arrow scale (the glow stays)

    private func gradient(_ stops: [EuclideousBlendStop]) -> LinearGradient {
        LinearGradient(stops: stops.map { Gradient.Stop(color: Color($0.colour, alpha: $0.alpha), location: CGFloat($0.position)) }, startPoint: .leading, endPoint: .trailing)
    }
    private var fillStyle: AnyShapeStyle {
        switch spec.fill {
        case .single(let c, let top, let bottom):
            return AnyShapeStyle(LinearGradient(colors: [Color(c, alpha: top), Color(c, alpha: bottom)], startPoint: .top, endPoint: .bottom))
        case .blend(let stops): return AnyShapeStyle(gradient(stops))
        }
    }
    private var labelColour: Color {
        guard spec.hollow else { return riffInk }
        if spec.lanes.count == 1, case .single(let c, _, _) = spec.fill { return Color(c) }
        return riffSharedHollowLabel
    }
    private var label: Text {
        let base = labelColour
        return spec.labelParts.reduce(Text("")) { acc, part in acc + Text(part.text).foregroundColor(base.opacity(part.alpha)) }
    }
    private var shape: EuclideousArrowShape { EuclideousArrowShape(outline: spec.outline) }
    private var highlight: LinearGradient {
        LinearGradient(stops: [.init(color: .white.opacity(S.highlightWhiteTop), location: 0), .init(color: .clear, location: S.highlightClearAt),
                               .init(color: .black.opacity(S.highlightBlackBottom), location: 1)], startPoint: .top, endPoint: .bottom)
    }
    @ViewBuilder private var body_: some View {
        if spec.hollow {
            // 4.8: a 1.5pt dashed stroke INSIDE the shape (3 on, 2 off) — drawn on the outline inset by half the stroke so it stays within the arrow's box.
            let inset = S.hollowStrokeWidth / 2
            let inner = EuclideousArrowShape(outline: euclideousArrowOutline(kind: spec.kind, w: spec.size.width - S.hollowStrokeWidth, h: spec.size.height - S.hollowStrokeWidth))
            inner.stroke(fillStyle, style: StrokeStyle(lineWidth: S.hollowStrokeWidth, lineJoin: .round, dash: S.hollowDash))
                .frame(width: spec.size.width - S.hollowStrokeWidth, height: spec.size.height - S.hollowStrokeWidth)
                .offset(x: inset, y: inset)
        } else {
            ZStack {
                shape.fill(fillStyle)
                if case .blend = spec.fill { shape.fill(highlight) }
            }
            .shadow(color: .black.opacity(S.shadowAlpha), radius: S.shadowRadius, x: 0, y: S.shadowY)
        }
    }
    var body: some View {
        let strength = spec.flareStrength
        ZStack(alignment: .topLeading) {
            body_
                .frame(width: spec.size.width, height: spec.size.height, alignment: .topLeading)
                .shadow(color: spec.flareColour.map { Color($0, alpha: S.flareAlpha * strength) } ?? .clear, radius: spec.flareColour == nil ? 0 : S.flareRadius * CGFloat(strength))   // PULSE §4.1: blur 12 × f
            label.font(.system(size: spec.labelSize, weight: .heavy, design: .monospaced)).lineLimit(1).truncationMode(.tail)
                .frame(width: spec.labelRect.width, height: spec.labelRect.height)
                .offset(x: spec.labelRect.minX, y: spec.labelRect.minY)
        }
        .frame(width: spec.size.width, height: spec.size.height, alignment: .topLeading)
        .scaleEffect(euclideousPulseFilter(.arrowScale, scale: 1, reduceMotion: reduceMotion) == .off ? 1 : 1 + (S.flareScale - 1) * strength)   // §4.1: 1 + 0.24 × f
        .opacity(spec.opacity)
    }
}

/// The four lane rails under the grid (RIFF PANEL ferry §6): each lane's number in the note-label column, then eight segments on the grid's columns — not played (a 1pt
/// inner ring), played (lane 16%), the trail (50 / 32 / 20%), the current column (the arrow's one-lane fill + the heading's chevron) with a glow while the lane strikes.
struct EuclideousRailsView: View {
    let layout: EuclideousRiffPanelLayout
    let rails: [EuclideousRailSpec]
    private typealias S = EuclideousRailStyle

    private func laneColour(_ lane: Int) -> Color { Color(euclideousLaneRGB[lane % euclideousLaneRGB.count]) }
    /// One segment, exactly 8 tall: the chevron and the glow are an overlay / background so neither can change the segment's layout size.
    @ViewBuilder private func segment(_ seg: EuclideousRailSegment, lane: Int, flare: Double) -> some View {
        let c = laneColour(lane)
        let r: CGFloat = EuclideousRiffPanelMetrics.railH / 2
        switch seg.look {
        case .notPlayed:
            RoundedRectangle(cornerRadius: r).strokeBorder(Color.white.opacity(S.notPlayedRing), lineWidth: 1).opacity(seg.opacity)
        case .played:
            RoundedRectangle(cornerRadius: r).fill(c.opacity(S.playedAlpha)).opacity(seg.opacity)
        case .trail(let k):
            RoundedRectangle(cornerRadius: r).fill(c.opacity(S.trailAlphas[min(2, max(0, k))])).opacity(seg.opacity)
        case .current(let heading):
            // the arrow's one-lane fill (4.4); the glow (0 0 8, spread 2 → a blurred rect 2pt larger all round) behind it; the chevron over it
            RoundedRectangle(cornerRadius: r)
                .fill(LinearGradient(colors: [c.opacity(EuclideousArrowStyle.topAlpha), c.opacity(EuclideousArrowStyle.bottomAlpha)], startPoint: .top, endPoint: .bottom))
                .background {
                    if flare > 0 {
                        RoundedRectangle(cornerRadius: r + 2).fill(c.opacity(S.glowAlpha * flare)).padding(-S.glowSpread).blur(radius: S.glowRadius / 2 * flare)   // PULSE §4.4: blur 8 × f, spread 2, lane100 @ 65% × f
                    }
                }
                .overlay {
                    switch heading {
                    case .right: Text("\u{203A}").font(.system(size: S.chevronSize, weight: .heavy, design: .monospaced)).foregroundColor(riffInk.opacity(S.chevronAlpha))
                    case .left: Text("\u{2039}").font(.system(size: S.chevronSize, weight: .heavy, design: .monospaced)).foregroundColor(riffInk.opacity(S.chevronAlpha))
                    case .still: Text("\u{2022}").font(.system(size: S.dotSize, weight: .heavy, design: .monospaced)).foregroundColor(riffInk.opacity(S.chevronAlpha))
                    }
                }
                .opacity(seg.opacity)
        }
    }
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(rails.indices, id: \.self) { k in
                let rail = rails[k]
                let nf = layout.railNumberFrame(rail.lane)
                Text("\(rail.lane + 1)").font(.system(size: S.numberSize, weight: .heavy, design: .monospaced))
                    .foregroundColor(laneColour(rail.lane).opacity(rail.numberOpacity))
                    .frame(width: nf.width, height: nf.height, alignment: .trailing)
                    .offset(x: nf.minX, y: nf.minY)
                ForEach(0..<rail.segments.count, id: \.self) { c in
                    let f = layout.railSegmentFrame(lane: rail.lane, column: c)
                    segment(rail.segments[c], lane: rail.lane, flare: rail.flare)
                        .frame(width: f.width, height: f.height)
                        .offset(x: f.minX, y: f.minY)
                }
            }
        }
        .frame(width: layout.box.width, height: layout.box.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }
}
