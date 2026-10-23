//  WalkTagPainter.swift
//  The riff-grid WALK TAG + THREAD painters (ferry "Riff-grid walk tags with threads", 2026-10-15).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks): pure paint routines over the plain
//  geometry `Derivations.swift` computes (`EuclideousTagDrawing` / `EuclideousThreadGeometry`), kept out of
//  `EuclideousPage` so a macOS preview harness can render exactly what the page draws.

import SwiftUI

enum EuclideousWalkTagPainter {
    /// INK #0d0f14 — the outline / casing colour.
    static let ink = Color(.sRGB, red: 13.0 / 255, green: 15.0 / 255, blue: 20.0 / 255, opacity: 1)

    /// A thread: 1.5pt lane colour at 80% over a 3.5pt INK casing at 90% (a 1pt dark edge each side), square ends;
    /// a 5pt dot with a 1pt INK ring at the destination — or, when the next advance lands on a rest, a hollow 6pt
    /// ring (1.5pt lane-colour ring, no fill) with the same 1pt INK ring outside.
    static func drawThread(_ ctx: inout GraphicsContext, accent: Color, _ g: EuclideousThreadGeometry) {
        var p = Path()
        for seg in g.segments { p.move(to: seg.from); p.addLine(to: seg.to) }
        ctx.stroke(p, with: .color(ink.opacity(0.9)), style: StrokeStyle(lineWidth: 3.5, lineCap: .butt))
        ctx.stroke(p, with: .color(accent.opacity(0.8)), style: StrokeStyle(lineWidth: 1.5, lineCap: .butt))
        let c = g.dot
        func circle(_ d: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - d / 2, y: c.y - d / 2, width: d, height: d)) }
        if g.hollowDot {
            ctx.stroke(circle(7), with: .color(ink), style: StrokeStyle(lineWidth: 1))          // INK ring outside: r 3.0…4.0
            ctx.stroke(circle(4.5), with: .color(accent), style: StrokeStyle(lineWidth: 1.5))    // lane ring: r 1.5…3.0 (6pt overall)
        } else {
            ctx.fill(circle(7), with: .color(ink))
            ctx.fill(circle(5), with: .color(accent))
        }
    }

    /// A tag: an 18 × 11pt arrow-shaped pentagon (13pt body + 5pt point at mid-height on the travel side), round
    /// joins, 1.5pt INK outline centred on the edge. Hollow (a rest): no fill, the outline in the lane colour.
    /// `scaleX` flips it about its own centre for a PEND/PING turn.
    static func drawTag(_ ctx: inout GraphicsContext, lane: Int, accent: Color, _ d: EuclideousTagDrawing, cellW: CGFloat, cellH: CGFloat) {
        let r = euclideousTagRect(lane: lane, blockW: cellW, blockH: cellH)
        let w = r.width, h = r.height
        let body = w * EuclideousTagMetrics.bodyW / EuclideousTagMetrics.tagW
        let sx = CGFloat(d.scaleX) * (d.pointsRight ? 1 : -1)
        let local: [(CGFloat, CGFloat)] = [(-w / 2, -h / 2), (-w / 2 + body, -h / 2), (w / 2, 0), (-w / 2 + body, h / 2), (-w / 2, h / 2)]
        var path = Path()
        for (i, p) in local.enumerated() {
            let pt = CGPoint(x: d.centre.x + p.0 * sx, y: d.centre.y + p.1)
            if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
        }
        path.closeSubpath()
        let style = StrokeStyle(lineWidth: 1.5, lineJoin: .round)
        ctx.drawLayer { l in
            l.opacity = d.opacity
            if d.hollow {
                l.stroke(path, with: .color(accent), style: style)
            } else {
                l.fill(path, with: .color(accent))
                l.stroke(path, with: .color(ink), style: style)
            }
        }
    }
}
