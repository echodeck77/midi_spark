//  RankChipPainter.swift
//  POOL ferry (2026-11-02) §5: the ONE rank chip — today's NOTES key (radius, received / octave-copy looks, the label's type, the lit bar) with the rank number in its corner. NOW, the NOTES keys and the riff grid's label column all
//  draw this view from an `EuclideousRankChipSpec` (Derivations.swift); the spec says what a chip shows, `euclideousRankChipFitsCorner` whether its corner number can share it with the label. The view keeps no state.

import SwiftUI

private extension Color {
    init(h: UInt32) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}
private func chipHeavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }
private func chipBoldMono(_ size: CGFloat) -> Font { .system(size: size, weight: .bold, design: .monospaced) }
/// A rank label's font from the shared style (`EuclideousRankLabelStyle`): the grid label here and the MIX chip's text in `MixPanelViews.swift` both ask for their weights by name.
func rankLabelFont(_ weight: EuclideousRankLabelStyle.Weight, _ size: CGFloat) -> Font { .system(size: size, weight: weight == .heavy ? .heavy : .bold, design: .monospaced) }

struct EuclideousRankChipView: View {
    let spec: EuclideousRankChipSpec
    let accent: Color
    let size: CGSize

    private var isTop: Bool { spec.topKind != 0 }
    private var labelOpacity: Double { spec.sounding > 0 ? 1 : (spec.received ? 0.75 : 0.35) }
    private var labelColour: Color { spec.sounding > 0 ? Color(h: 0xF2F4F7) : Color.white.opacity(labelOpacity) }
    @ViewBuilder private var label: some View {
        if isTop {
            VStack(spacing: 2) {
                HStack(alignment: .lastTextBaseline, spacing: 1) {
                    Text("TOP").font(chipHeavyMono(10))
                    if spec.topKind == 1 { Text("2").font(chipHeavyMono(8)) }
                }
                .foregroundColor(labelColour).lineLimit(1)
                .frame(height: 13)
                Text(spec.name).font(chipBoldMono(8)).foregroundColor(spec.sounding > 0 ? Color(h: 0xF2F4F7) : Color(h: 0x8A909A)).lineLimit(1)
                    .frame(height: 10)
            }
        } else if spec.empty {
            Text(spec.name).font(rankLabelFont(EuclideousRankLabelStyle.noteWeight, EuclideousRankLabelStyle.grid.noteSize)).foregroundColor(labelColour).lineLimit(1)   // 5.4: an empty pool — the rank number, in the label's type
        } else {
            let style = EuclideousRankLabelStyle.grid
            let split = style.parts(of: spec.name)
            HStack(alignment: .lastTextBaseline, spacing: 0) {
                Text(split.note).font(rankLabelFont(EuclideousRankLabelStyle.noteWeight, style.noteSize))
                Text(split.octave).font(rankLabelFont(EuclideousRankLabelStyle.octaveWeight, style.octaveSize))
            }
            .foregroundColor(labelColour).lineLimit(1)   // truncate, never shrink
        }
    }
    var body: some View {
        let fill = spec.received ? Color(h: 0x30343C) : Color(h: 0x17191E)
        let border = spec.received ? Color(h: 0x454A54) : Color(h: 0x202329)
        let corner = spec.cornerNumber && !isTop && !spec.empty && euclideousRankChipFitsCorner(width: size.width, height: size.height, name: spec.name)
        ZStack(alignment: .bottom) {
            RoundedRectangle(cornerRadius: 6).fill(fill)
            RoundedRectangle(cornerRadius: 6).strokeBorder(border, lineWidth: 1)
            // the label: centred in the chip above a 6 pt bottom inset, clear of the bar and the place number
            label.frame(width: size.width, height: size.height - 6).frame(maxHeight: .infinity, alignment: .top)
            if corner {   // §5.3: the rank number — 8 pt bold at 70 % of the label's colour, inset 3 from the top and leading edges
                Text("\(spec.rank)").font(rankLabelFont(EuclideousRankLabelStyle.rankWeight, EuclideousRankLabelStyle.grid.rankSize)).lineLimit(1)
                    .foregroundColor(spec.sounding > 0 ? Color(h: 0xF2F4F7).opacity(EuclideousRankLabelStyle.rankAlphaFactor) : Color.white.opacity(labelOpacity * EuclideousRankLabelStyle.rankAlphaFactor))
                    .padding(.top, EuclideousRankLabelStyle.grid.inset).padding(.leading, EuclideousRankLabelStyle.grid.inset)
                    .frame(width: size.width, height: size.height, alignment: .topLeading)
            }
            if let place = spec.place {
                Text(place).font(chipHeavyMono(8.5)).foregroundColor(accent).lineLimit(1).frame(height: 10)
                    .padding(.bottom, 9.5)
            }
            if spec.lit {
                if spec.heldBack {
                    RoundedRectangle(cornerRadius: 2).strokeBorder(accent, lineWidth: 1.25).frame(height: 4).padding(.horizontal, 4).padding(.bottom, 3)
                } else {
                    RoundedRectangle(cornerRadius: 1.5).fill(accent).frame(height: 3).padding(.horizontal, 4).padding(.bottom, 3.5)
                }
            }
            if spec.riffDot {
                Circle().fill(Color(h: 0xDFE3EA)).frame(width: 5, height: 5).frame(maxHeight: .infinity, alignment: .top).padding(.top, 6)
            }
            if let src = spec.sourcePip, !isTop {   // INPUTS ferry 3.2: a 5 × 5 radius-1.5 pip in the note's source colour, inset 3 from the top and trailing edges (received notes only — an octave copy has none)
                RoundedRectangle(cornerRadius: 1.5).fill(Color(h: EuclideousSourceColour.fill(source: src))).frame(width: 5, height: 5)
                    .padding(.top, 3).padding(.trailing, 3)
                    .frame(width: size.width, height: size.height, alignment: .topTrailing)
            }
            if spec.sounding > 0 {
                RoundedRectangle(cornerRadius: 6).strokeBorder(accent, lineWidth: 1.5).opacity(spec.sounding)
            }
        }
        .frame(width: size.width, height: size.height)
        .shadow(color: spec.sounding > 0 ? accent.opacity(0.45 * spec.sounding) : .clear, radius: spec.sounding > 0 ? 10 : 0)
    }
}
