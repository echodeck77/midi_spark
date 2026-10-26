//  RestartFlashPainter.swift
//  The flash on the RHYTHM tab's restart tiles (2026-10-21): a lane-colour wash, a soft light band sweeping across, a white rim with an outer glow — drawn from the plain numbers
//  `euclideousRestartFlashLook` returns (all the decisions are pure and live in Derivations.swift). SwiftUI-only on purpose (GridUI seam rule), like `WalkTagPainter.swift`.

import SwiftUI

/// Laid OVER a tile (same frame, no hit testing). The wash and the sweep are clipped to the tile's rounded rect; the glow is cast outside it.
struct EuclideousRestartFlashOverlay: View {
    let look: EuclideousRestartFlashLook
    let accent: Color
    let radius: CGFloat

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width, h = geo.size.height
            let shape = RoundedRectangle(cornerRadius: radius)
            ZStack {
                shape.fill(accent.opacity(0.38 * look.wash))
                if let s = look.sweep {
                    // a soft white band, leaning 18°, travelling left → right across the tile (and a little beyond each side so it enters and leaves cleanly)
                    LinearGradient(colors: [.clear, .white.opacity(0.6 * look.sweepAlpha), .clear], startPoint: .leading, endPoint: .trailing)
                        .frame(width: 34, height: h * 1.8)
                        .rotationEffect(.degrees(18))
                        .position(x: -22 + (w + 44) * CGFloat(s), y: h / 2)
                }
                shape.strokeBorder(Color.white.opacity(0.85 * look.rim), lineWidth: 1.5)
            }
            .frame(width: w, height: h)
            .clipShape(shape)
            .shadow(color: accent.opacity(0.75 * look.glow), radius: 5 * CGFloat(look.glow))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
