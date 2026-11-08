//  StackGridViews.swift — STACK GRID ferry (2026-11-08): the leaf views of the riff panel's STACK tab. They only paint what `StackGrid.swift` decides — a toggle cell (the note's name on a lane-coloured fill when it is selected, dimmed when it is not)
//  and a lane's column header; the axis is the app's own rank chip (`EuclideousRankChipView`), drawn from a spec. The page wires the taps through the NOTES tab's own action.

import SwiftUI

private func stackHeavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// One cell: the name of the note it stands for in its lane. ON: the lane colour with ink text; OFF: a dark plate with a faint lane-coloured outline and the name dimmed; a cell with no position to toggle (a TOP row the pool is too small for) is dimmer still.
struct EuclideousStackCellView: View {
    let name: String
    let on: Bool
    let live: Bool
    let accent: Color
    let size: CGSize
    let fontSize: CGFloat
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5).fill(on ? accent : Color(hex: 0x1F2127))
            if !on { RoundedRectangle(cornerRadius: 5).strokeBorder(accent.opacity(live ? 0.3 : 0.12), lineWidth: 1) }
            Text(name).font(stackHeavyMono(fontSize)).foregroundColor(on ? Color(hex: 0x0D0F14) : Color.white.opacity(live ? 0.42 : 0.2)).lineLimit(1)   // truncate, never shrink
        }
        .frame(width: size.width, height: size.height)
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
