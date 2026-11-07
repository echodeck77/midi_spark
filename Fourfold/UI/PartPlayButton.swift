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

/// §2 the button. `isNotes` picks RIFF vs STACK; `accent` is the lane colour; `on` is the part's state; `flash` (0…1) is the lamp glow's opacity, computed by the caller from the note feed. Frame defaults to the card's 44 × 44 (the play / SOLO tile).
struct EuclideousPartPlayButton: View {
    let isNotes: Bool
    let accent: Color
    let on: Bool
    var flash: Double = 0
    var tile = CGSize(width: 44, height: 44)
    var target: CGSize? = nil
    var axLabel: String = ""
    let onTap: () -> Void

    private var look: EuclideousPartPlayLook { euclideousPartPlayLook(on: on) }

    var body: some View {
        content
            .frame(width: tile.width, height: tile.height)
            .background(tileBackground)   // §2.1 the tile, on and off alike
            .frame(width: target?.width ?? tile.width, height: target?.height ?? tile.height, alignment: .top)
            .contentShape(Rectangle())
            .onTapGesture { onTap() }      // §2.6 no hold, no double-tap
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(axLabel)
            .accessibilityValue(on ? "on" : "off")   // §6.2
            .accessibilityAddTraits(.isButton)
            .ringToggleTrait()
    }

    private var content: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) { lamp; playText }   // §2.2 line 1: the lamp, sp4, then PLAY — centred as a group
            nameText
        }
    }
    private var playText: some View {
        Text("PLAY").font(.system(size: 6, weight: .heavy, design: .monospaced)).tracking(0.16 * 6).foregroundColor(Color(hex: look.playHex))
    }
    private var nameText: some View {
        Text(isNotes ? "STACK" : "RIFF").font(.system(size: 9, weight: .heavy, design: .monospaced)).tracking(0.08 * 9)
            .foregroundColor(Color(hex: look.nameHex)).lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(height: 10)   // §2.2 truncate, never shrink
    }
    private var tileBackground: some View {
        RoundedRectangle(cornerRadius: EuclideousPartPlayLook.tileRadius).fill(Color(hex: EuclideousPartPlayLook.tileFillHex))
            .overlay(RoundedRectangle(cornerRadius: EuclideousPartPlayLook.tileRadius).strokeBorder(Color(hex: EuclideousPartPlayLook.tileBorderHex), lineWidth: 1))
    }

    /// §2.3–2.5 the lamp: a 5.5 × 6 triangle, filled lane (on) or a 1 pt grey outline (off), with round joins; a lane100 4 pt-blur glow at the flash activity.
    private var lamp: some View {
        let sz = EuclideousPartPlayLamp.size
        return ZStack {
            if flash > 0 {   // §2.5 the glow around the lamp
                EuclideousPartPlayLampShape().fill(accent).frame(width: sz.width, height: sz.height).blur(radius: 4).opacity(flash)
            }
            if look.lampFilled {
                EuclideousPartPlayLampShape().fill(accent)
                    .overlay(EuclideousPartPlayLampShape().stroke(accent, style: StrokeStyle(lineWidth: EuclideousPartPlayLamp.strokeWidth, lineJoin: .round)))
                    .frame(width: sz.width, height: sz.height)
            } else {
                EuclideousPartPlayLampShape().stroke(Color(hex: look.lampStrokeHex), style: StrokeStyle(lineWidth: EuclideousPartPlayLamp.strokeWidth, lineJoin: .round))
                    .frame(width: sz.width, height: sz.height)
            }
        }
        .frame(width: sz.width, height: sz.height)
    }
}
