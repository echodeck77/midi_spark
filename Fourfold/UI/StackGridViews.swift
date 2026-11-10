//  StackGridViews.swift — STACK GRID ferry (2026-11-08): the leaf views of the riff panel's STACK tab. They only paint what `StackGrid.swift` decides — a toggle cell (the note's name on a lane-coloured fill when it is selected, dimmed when it is not)
//  and a lane's column header; the axis is the app's own rank chip (`EuclideousRankChipView`), drawn from a spec. The page wires the taps through the NOTES tab's own action.

import SwiftUI

private func stackHeavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// One cell: the name of the note it stands for in its lane, with its STACK GRID LIVE look (§2). SOUNDING: full lane colour, ink text, a note-on glow; SELECTED-at-rest: lane colour at 50 %, #F2F4F7 text; OFF (not selected, not sounding):
/// a dark plate with a faint lane-coloured outline and the name dimmed (a cell with no position to toggle is dimmer still). `look.fillAlpha` 0 is the OFF look; the glow (lane colour, blurred, outside the frame) draws under the cell.
struct EuclideousStackCellView: View {
    let name: String
    let look: EuclideousStackCellLook
    let live: Bool
    let accent: Color
    let size: CGSize
    let fontSize: CGFloat
    var body: some View {
        let lit = look.fillAlpha > 0
        ZStack {
            if look.glowAlpha > 0 {   // §2.2 the note-on glow — lane colour, a 4 pt blur, drawn OUTSIDE the cell frame and under it (the ring, §3, draws over)
                RoundedRectangle(cornerRadius: 5).fill(accent.opacity(look.glowAlpha))
                    .frame(width: size.width + 6, height: size.height + 6).blur(radius: EuclideousStackTuning.glowBlur)
            }
            RoundedRectangle(cornerRadius: 5).fill(lit ? accent.opacity(look.fillAlpha) : Color(hex: 0x1F2127))
            if !lit { RoundedRectangle(cornerRadius: 5).strokeBorder(accent.opacity(live ? 0.3 : 0.12), lineWidth: 1) }
            Text(name).font(stackHeavyMono(fontSize)).foregroundColor(label(lit)).lineLimit(1)   // truncate, never shrink
        }
        .frame(width: size.width, height: size.height)
    }
    private func label(_ lit: Bool) -> Color {
        guard lit else { return Color.white.opacity(live ? 0.42 : 0.2) }
        return look.labelInk ? Color(hex: 0x0D0F14) : Color(hex: 0xF2F4F7)   // sounding = ink; selected-at-rest = #F2F4F7
    }
}
/// A lane's column header: its number on its colour.
struct EuclideousStackHeaderView: View {
    let lane: Int
    let accent: Color
    let size: CGSize
    let fontSize: CGFloat
    var body: some View {
        RoundedRectangle(cornerRadius: 5).fill(accent)
            .overlay(Text("\(lane + 1)").font(stackHeavyMono(fontSize)).foregroundColor(Color(hex: 0x0D0F14)))
            .frame(width: size.width, height: size.height)
    }
}
