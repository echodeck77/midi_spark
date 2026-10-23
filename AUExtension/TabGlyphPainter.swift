//  TabGlyphPainter.swift
//  CLARITY PASS ferry (2026-10-23) §2.1/§2.2/§3.4 — the glyph that replaces the lane card's round status dot, and that the MIX pad's label wears too: a square (RIFF), an upright bar (NOTES) or a circle (LISTEN).
//  SwiftUI-only on purpose (GridUI seam rule). Which shape, whether it is on, and whose colour it fills with are decided by the pure `euclideousTabGlyph` (Derivations.swift); this file only draws the answer.

import SwiftUI

private extension Color {
    init(h: UInt32) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}

struct EuclideousTabGlyphView: View {
    let shape: EuclideousGlyphShape
    let on: Bool
    /// One colour fills the glyph; four (a LISTEN row set to ANY) fill a circle in quarters, the partner picker's own ANY dot.
    let fills: [Color]

    /// §2.1: RIFF a 9 × 9 square, radius 2 (echoes a riff-grid cell) · NOTES a 6 × 12 bar, radius 1.5 (echoes a NOTES key) · LISTEN a 9 circle. §2.2: off = a 1.5 pt #AAB0BA inner outline.
    static let square = CGSize(width: 9, height: 9), bar = CGSize(width: 6, height: 12), circle = CGSize(width: 9, height: 9)
    static let outline = Color(h: 0xAAB0BA)
    static let outlineWidth: CGFloat = 1.5

    static func size(_ shape: EuclideousGlyphShape) -> CGSize {
        switch shape { case .none: return .zero; case .square: return square; case .bar: return bar; case .circle: return circle }
    }

    var body: some View {
        let s = Self.size(shape)
        return glyph.frame(width: s.width, height: s.height)
    }

    @ViewBuilder private var glyph: some View {
        switch shape {
        case .none: EmptyView()
        case .square: drawn(RoundedRectangle(cornerRadius: 2))
        case .bar: drawn(RoundedRectangle(cornerRadius: 1.5))
        case .circle: drawn(Circle())
        }
    }

    @ViewBuilder private func drawn<S: InsettableShape>(_ s: S) -> some View {
        if !on {
            s.strokeBorder(Self.outline, lineWidth: Self.outlineWidth)
        } else if fills.count >= 4, shape == .circle {
            Canvas { ctx, sz in
                let c = CGPoint(x: sz.width / 2, y: sz.height / 2), r = min(sz.width, sz.height) / 2
                for i in 0..<4 {
                    var p = Path()
                    p.move(to: c)
                    p.addArc(center: c, radius: r, startAngle: .degrees(Double(i) * 90 - 90), endAngle: .degrees(Double(i + 1) * 90 - 90), clockwise: false)
                    p.closeSubpath()
                    ctx.fill(p, with: .color(fills[i]))
                }
            }
            .clipShape(Circle())
        } else {
            s.fill(fills.first ?? Self.outline)
        }
    }
}
