//  FourfoldMark.swift
//  The FOURFOLD mark in the header, the lanes' on-screen colours, and the toggle-trait helper the page's buttons share.
//  (This file held the header's output rings until THE NINE PORTS, 2026-10-26 — a note's port is fixed by its lane and layer, so there is nothing to toggle there.)
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `WalkTagPainter.swift`.

import SwiftUI

enum EuclideousRingPalette {
    /// The lanes' own on-screen colours (lane 1 top-left … lane 4 bottom-right) — the FOURFOLD mark's four squares.
    static let laneMark: [Color] = [Color(hex: 0xF25959), Color(hex: 0x59BFF2), Color(hex: 0xF2BF40), Color(hex: 0x8CD973)]
}

/// The FOURFOLD mark: 13 × 13, four 5.5pt squares (radius 1.5) with 2pt gutters, in the lanes' own on-screen order
/// (top-left red, top-right blue, bottom-left amber, bottom-right green).
struct FourfoldMark: View {
    var body: some View {
        Canvas { ctx, _ in
            let s: CGFloat = 5.5, g: CGFloat = 2
            let origins = [CGPoint(x: 0, y: 0), CGPoint(x: s + g, y: 0), CGPoint(x: 0, y: s + g), CGPoint(x: s + g, y: s + g)]
            for (i, o) in origins.enumerated() {
                ctx.fill(Path(roundedRect: CGRect(x: o.x, y: o.y, width: s, height: s), cornerRadius: 1.5), with: .color(EuclideousRingPalette.laneMark[i]))
            }
        }
        .frame(width: EuclideousHeaderMetrics.markSize, height: EuclideousHeaderMetrics.markSize)
        .accessibilityHidden(true)
    }
}

extension View {
    /// A TOGGLE trait where the OS has one (`.isToggle` is iOS 17 / macOS 14); older systems keep the `.isButton` trait the call site adds and the "on"/"off" word in the value.
    @ViewBuilder func ringToggleTrait() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) { self.accessibilityAddTraits(.isToggle) } else { self }
    }
}
