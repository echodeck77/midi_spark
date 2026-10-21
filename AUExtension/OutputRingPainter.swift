//  OutputRingPainter.swift
//  The Fourfold header's OUTPUT RING (MAIN OUT A–D) and the FOURFOLD mark (ferry "Fourfold header", 2026-10-15).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `WalkTagPainter.swift`: pure paint
//  routines over the plain state `Derivations.swift` computes (`EuclideousOutputRingState`, `euclideousPulseRingStroke`), kept
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
/// `flare` (0…1 per lane — PULSE ferry 2026-10-20 §6: each lane's velocity-scaled flash f) thickens its quarter 2.5 → 5pt (2.5 + 2.5 × f); the strongest lane washes the disc (lane100 @ 38% × f over #1B1D23), glows the whole ring (blur 6 × f at
/// 70% × f) and turns the letter white while f > 0.35.
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
            // DISC: none when off (the ground shows through) — EXCEPT while held, whose light disc is unconditional (§4.7);
            // `euclideousRingDisc` is the one decision, tested, so a held OFF ring can't end up with an ink letter on no disc.
            let discKind = euclideousRingDisc(mode: state.mode, held: held)
            // PULSE §6.2: two lanes on one output — each quarter follows its own lane; the wash, the glow and the letter follow the stronger.
            var topLane = -1
            var topF = 0.0
            for lane in 0..<4 where lane < flare.count && lane < laneColours.count && flare[lane] > topF { topLane = lane; topF = min(1, flare[lane]) }
            if discKind != .none {
                let disc = Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
                if discKind == .base, topLane >= 0 {   // §6.1: the whole ring glows — blur 6 × f (shadow radius 3 × f) in that lane's colour at 70% × f
                    ctx.drawLayer { layer in
                        layer.addFilter(.shadow(color: laneColours[topLane].opacity(0.7 * topF), radius: 3 * CGFloat(topF)))
                        layer.fill(disc, with: .color(EuclideousRingPalette.disc))
                    }
                }
                ctx.fill(disc, with: .color(discKind == .held ? EuclideousRingPalette.heldDisc : EuclideousRingPalette.disc))
                if discKind == .base, topLane >= 0 {   // §6.1: the disc takes a lane100 wash at 38% × f over #1B1D23, from the strongest striking lane
                    ctx.fill(disc, with: .color(laneColours[topLane].opacity(0.38 * topF)))
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
                let thickness = euclideousPulseRingStroke(f: lit ? f : 0)   // §6.1: 2.5 + 2.5 × f (the old 7pt per-quarter glow is replaced by the whole-ring glow above)
                if state.dashed {
                    ctx.stroke(arc, with: .color(colour), style: StrokeStyle(lineWidth: thickness, lineCap: .butt, dash: [2.5, 2]))
                } else {
                    ctx.stroke(arc, with: .color(colour), style: StrokeStyle(lineWidth: thickness, lineCap: .round))
                }
            }
            // LETTER
            let letterColour: Color
            let letterTone = euclideousRingLetterTone(mode: state.mode, held: held)
            switch letterTone {
            case .ink: letterColour = EuclideousRingPalette.ink
            case .on: letterColour = EuclideousRingPalette.letterOn
            case .unrouted: letterColour = EuclideousRingPalette.letterUnrouted
            case .off: letterColour = EuclideousRingPalette.letterOff
            }
            ctx.draw(Text(letter).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(euclideousPulseRingLetterIsWhite(f: topF, tone: letterTone) ? Color.white : letterColour), at: c)   // §6.1: #FFFFFF while f > 0.35
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

/// Wraps ONE output ring with its own tap-vs-hold handling (`EuclideousRingPress`, pure + tested). Each ring owns its own
/// `@State` and `@GestureState`, so two fingers on two rings are independent (a shared slot would swallow both taps), and a
/// touch the system CANCELS (no `onEnded`) still ends a started hold through the `GestureState` reset.
struct EuclideousRingPressable<Content: View>: View {
    let onTap: () -> Void
    /// `true` when the 300ms hold fires, `false` when that hold ends (release OR cancellation).
    let onHold: (Bool) -> Void
    @ViewBuilder let content: () -> Content

    @State private var press = EuclideousRingPress()
    @State private var holdTask: Task<Void, Never>? = nil
    @GestureState private var touching = false

    var body: some View {
        content()
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, t, _ in t = true }
                    .onChanged { g in
                        if !press.down {
                            press.touchDown()
                            holdTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: UInt64(EuclideousRingPress.holdSeconds * 1_000_000_000))
                                guard !Task.isCancelled else { return }
                                perform(press.holdTimerFired())
                            }
                        } else {
                            press.moved(distance: Double(hypot(g.translation.width, g.translation.height)))
                            if press.cancelled { holdTask?.cancel() }
                        }
                    }
                    .onEnded { _ in
                        holdTask?.cancel(); holdTask = nil
                        perform(press.touchEnded())
                    }
            )
            .onChange(of: touching) { t in
                // The finger is gone. After a normal release `onEnded` has already run (and reset `press`), so this is a
                // no-op; after a CANCELLED touch `onEnded` never runs and this is what ends a started hold. Deferred one
                // turn so it can never race ahead of `onEnded` and eat a tap.
                guard !t else { return }
                Task { @MainActor in
                    guard press.down else { return }
                    holdTask?.cancel(); holdTask = nil
                    perform(press.touchCancelled())
                }
            }
    }

    private func perform(_ a: EuclideousRingPress.Action) {
        switch a {
        case .tap: onTap()
        case .holdBegan: onHold(true)
        case .holdEnded: onHold(false)
        case .none: break
        }
    }
}

extension View {
    /// §4.9 asks for a TOGGLE trait. `.isToggle` is iOS 17 / macOS 14; the target is iOS 16, where the ring keeps its
    /// `.isButton` trait (added at the call site) and the "on"/"off" word already in its label.
    @ViewBuilder func ringToggleTrait() -> some View {
        if #available(iOS 17.0, macOS 14.0, *) { self.accessibilityAddTraits(.isToggle) } else { self }
    }
}
