//  OutputRingPainter.swift
//  The Fourfold header's OUTPUT RING (MAIN OUT A–D) and the FOURFOLD mark (ferry "Fourfold header", 2026-10-15).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `WalkTagPainter.swift`: pure paint
//  routines over the plain state `Derivations.swift` computes (`EuclideousOutputRingState`, `euclideousRingFlare`), kept
//  out of `EuclideousPage` so a macOS harness can render exactly what the page draws.

import SwiftUI

private extension Color {
    init(h: UInt32) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}

enum EuclideousRingPalette {
    static let disc = Color(h: 0x1B1D23)
    static let unlitQuarter = Color(h: 0x3A3E47)
    static let heldDisc = Color(h: 0xDFE3EA)
    static let ink = Color(h: 0x0D0F14)
    static let letterOn = Color(h: 0xF2F4F7)
    static let letterUnrouted = Color(h: 0x8A909A)
    static let letterOff = Color(h: 0x5C626C)
    /// The lanes' own on-screen colours (lane 1 top-left … lane 4 bottom-right) — the FOURFOLD mark's four squares.
    static let laneMark: [Color] = [Color(h: 0xF25959), Color(h: 0x59BFF2), Color(h: 0xF2BF40), Color(h: 0x8CD973)]
}

/// One output ring: a disc of radius 17 and four 66° quarter arcs (round caps, 2.5pt) on radius 17, centred at 315°/45°/
/// 225°/135° clockwise from 12 o'clock = lanes 1…4 (TL/TR/BL/BR). A quarter is lane-coloured when that lane routes here,
/// else a dim mark. OFF: no disc, every quarter dashed (2.5 on / 2 off, butt caps). HELD: the disc goes light, the letter ink.
/// `flare` (0…1 per lane) thickens a quarter 2.5 → 3.5pt over a 7pt lane-40% glow and washes the disc to lane-20%.
struct EuclideousOutputRing: View {
    let letter: String
    let state: EuclideousOutputRingState
    let laneColours: [Color]            // 4, lane 0…3
    var held = false
    var flare: [Double] = [0, 0, 0, 0]
    /// The tap target's drawn width (44 normally, 40 compact) — the ring itself is the same ~36pt either way.
    var width: CGFloat = 44
    var height: CGFloat = 44

    static let radius: CGFloat = 17
    static let arcThickness: CGFloat = 2.5

    var body: some View {
        Canvas { ctx, size in
            let c = CGPoint(x: size.width / 2, y: size.height / 2)
            let r = Self.radius
            // DISC (not drawn at all when off — the ground shows through).
            if state.mode != .off {
                let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                ctx.fill(disc, with: .color(held ? EuclideousRingPalette.heldDisc : EuclideousRingPalette.disc))
                if !held {
                    for lane in 0..<4 where lane < flare.count && flare[lane] > 0 && lane < laneColours.count {
                        ctx.fill(disc, with: .color(laneColours[lane].opacity(0.2 * flare[lane])))
                    }
                }
            }
            // QUARTERS
            for lane in 0..<4 {
                let centre = euclideousRingQuarterCentreDegrees[lane]
                let half = euclideousRingArcDegrees / 2
                let f = lane < flare.count ? max(0, min(1, flare[lane])) : 0
                let lit = lane < state.lit.count && state.lit[lane]
                let colour = (lit && lane < laneColours.count) ? laneColours[lane] : EuclideousRingPalette.unlitQuarter
                // A polyline on the radius (24 segments across 66° ≈ 0.8pt each): no reliance on SwiftUI's flipped-axis
                // `clockwise:` semantics, and dashing runs along it exactly.
                var arc = Path()
                for i in 0...24 {
                    let deg = centre - half + euclideousRingArcDegrees * Double(i) / 24
                    let rad = deg * .pi / 180
                    let p = CGPoint(x: c.x + r * CGFloat(sin(rad)), y: c.y - r * CGFloat(cos(rad)))
                    if i == 0 { arc.move(to: p) } else { arc.addLine(to: p) }
                }
                if f > 0 && lit && lane < laneColours.count {
                    ctx.stroke(arc, with: .color(laneColours[lane].opacity(0.4 * f)), style: StrokeStyle(lineWidth: 7, lineCap: .round))
                }
                let thickness = Self.arcThickness + CGFloat(f)
                if state.dashed {
                    ctx.stroke(arc, with: .color(colour), style: StrokeStyle(lineWidth: thickness, lineCap: .butt, dash: [2.5, 2]))
                } else {
                    ctx.stroke(arc, with: .color(colour), style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                }
            }
            // LETTER
            let letterColour: Color = held ? EuclideousRingPalette.ink
                : (state.mode == .onRouted ? EuclideousRingPalette.letterOn
                   : (state.mode == .onUnrouted ? EuclideousRingPalette.letterUnrouted : EuclideousRingPalette.letterOff))
            ctx.draw(Text(letter).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(letterColour), at: c)
        }
        .frame(width: width, height: height)
    }
}

/// The FOURFOLD mark: 13 × 13, four 5.5pt squares (radius 1.5) with 2pt gutters, in the lanes' own on-screen order
/// (top-left red, top-right blue, bottom-left amber, bottom-right green). It teaches the quarter mapping the rings use.
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
