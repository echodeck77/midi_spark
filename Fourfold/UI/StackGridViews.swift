//  StackGridViews.swift — STACK GRID ferry (2026-11-08): the leaf views of the riff panel's STACK tab. They only paint what `StackGrid.swift` decides — a toggle cell (the note's name on a lane-coloured fill when it is selected, dimmed when it is not)
//  and a lane's column header; the axis is the app's own rank chip (`EuclideousRankChipView`), drawn from a spec. The page wires the taps through the NOTES tab's own action.

import SwiftUI

private func stackHeavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// One cell: the name of the note it stands for in its lane, with its STACK GRID LIVE look (§2). SOUNDING: full lane colour, ink text, a note-on glow; SELECTED-at-rest: lane colour at 50 %, #F2F4F7 text; OFF (not selected, not sounding):
/// a dark plate with a faint lane-coloured outline and the name dimmed (a cell with no position to toggle is dimmer still). `look.fillAlpha` 0 is the OFF look; the glow (lane colour, blurred, outside the frame) draws under the cell.
struct EuclideousStackCellView: View {
    let name: String
    let look: EuclideousStackCellLook
    /// STACK GRID RIFF ARROW ferry (2026-11-12): the lane's riff reads this cell now — the arrow's (column, rank, REPEAT). nil ⇒ no arrow (the ghost RING is gone). Replaces `ringed`.
    var arrowChip: (column: Int, rank: Int, isRepeat: Bool)? = nil
    let live: Bool
    let accent: Color
    let size: CGSize
    let fontSize: CGFloat
    private typealias AT = EuclideousStackArrowTuning
    var body: some View {
        let lit = look.fillAlpha > 0
        let arrow = arrowChip.map { euclideousStackRiffArrow(cell: CGRect(origin: .zero, size: size), column: $0.column, rank: $0.rank, isRepeat: $0.isRepeat) }
        ZStack {
            if look.glowAlpha > 0 {   // §2.2 the note-on glow — lane colour, a 4 pt blur, drawn OUTSIDE the cell frame and under it
                RoundedRectangle(cornerRadius: 5).fill(accent.opacity(look.glowAlpha))
                    .frame(width: size.width + 6, height: size.height + 6).blur(radius: EuclideousStackTuning.glowBlur)
            }
            RoundedRectangle(cornerRadius: 5).fill(lit ? accent.opacity(look.fillAlpha) : Color(hex: 0x1F2127))
            if !lit { RoundedRectangle(cornerRadius: 5).strokeBorder(accent.opacity(live ? 0.3 : 0.12), lineWidth: 1) }
            // §3.1: the name is centred in the cell width MINUS a 22 pt left inset, so it never moves when the arrow appears (arrow or not).
            Text(name).font(stackHeavyMono(fontSize)).foregroundColor(label(lit)).lineLimit(1)   // truncate, never shrink
                .position(x: (AT.nameInset + size.width) / 2, y: size.height / 2)
            if let arrow { riffArrow(arrow) }   // §2: the riff arrow, drawn LAST (over the name); never dimmed/tinted by the cell's state
        }
        .frame(width: size.width, height: size.height)
    }
    /// §2 the riff arrow at `spec.frame`: the reused riff-grid shape filled lane100 (the 1.5 pt edge), the same shape inset by the edge filled the map colour (or the off-cell fill for REPEAT), and the column label 4.5 pt in, left-aligned, centred.
    @ViewBuilder private func riffArrow(_ spec: EuclideousStackRiffArrow) -> some View {
        let inner = CGSize(width: AT.width - 2 * AT.edgeWidth, height: AT.height - 2 * AT.edgeWidth)
        ZStack {
            EuclideousArrowShape(outline: euclideousArrowOutline(kind: .right, w: AT.width, h: AT.height)).fill(accent)                         // §2.3 the lane100 edge
            EuclideousArrowShape(outline: euclideousArrowOutline(kind: .right, w: inner.width, h: inner.height)).fill(RiffMapPalette.swiftUIColour(spec.fill))
                .frame(width: inner.width, height: inner.height)                                                                                 // §2.4/§2.6 the body, inset 1.5 (centred)
        }
        .frame(width: AT.width, height: AT.height)
        .overlay(alignment: .leading) {   // §2.5 the column number, 4.5 pt in from the fill's left edge, vertically centred
            Text(spec.label).font(stackHeavyMono(AT.labelSize)).foregroundColor(RiffMapPalette.swiftUIColour(spec.labelColour)).lineLimit(1)
                .padding(.leading, AT.edgeWidth + AT.labelInset)
        }
        .position(x: spec.frame.midX, y: spec.frame.midY)
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
