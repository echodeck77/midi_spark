//  AltCardViews.swift — ALT ferry (2026-11-14) §5.5–5.8: the stateless pieces of the ALT card — the override pill, the §5.7 ALT slider (its own look, MIX's relative drag), the cycle strip and the main-value pip. Frames come from `euclideousAltCardLayout` / `euclideousAltCycleCells`; the page wires the edits. Looks are device-owed.

import SwiftUI

/// §5.6 — the main mark: a 4 pt disc, #CED2DA (on a white OCT box, #3C4048). `onWhite` picks the darker ink.
struct EuclideousAltPip: View {
    var onWhite = false
    var body: some View { Circle().fill(Color(hex: onWhite ? 0x3C4048 : 0xCED2DA)).frame(width: 4, height: 4) }
}

/// §5.5 — an override pill (its own label). Off: #1F2127 fill, 1 pt #343840 border, #767C86 label. On: the selected-segment look (lane tint fill at 20 %, 1 pt lane100 border, #F2F4F7 label). The hit area fills `frame` (the whole grid cell).
struct EuclideousAltPill: View {
    let label: String; let on: Bool; let accent: Color; let frame: CGRect
    let axLabel: String; let onTap: () -> Void
    var body: some View {
        let fill: Color = on ? accent.opacity(0.2) : Color(hex: 0x1F2127)
        let border: Color = on ? accent : Color(hex: 0x343840)
        let ink: Color = on ? Color(hex: 0xF2F4F7) : Color(hex: 0x767C86)
        return Text(label).font(.system(size: 7.5, weight: .heavy, design: .monospaced)).tracking(0.98)   // 7.5 pt heavy, 0.13 em
            .foregroundColor(ink)
            .frame(width: frame.width, height: frame.height)
            .background(RoundedRectangle(cornerRadius: 4.5).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: 4.5).stroke(border, lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { onTap() }
            .offset(x: frame.minX, y: frame.minY)
            .accessibilityElement(children: .ignore).accessibilityLabel(axLabel).accessibilityAddTraits(.isButton).ringToggleTrait()
    }
}

/// §5.3 — the cycle strip: L cells, main #2A2D34, alt #17191F + a 1 pt #C8CCD4 inner border; the current cell (while running) fills lane100 (main) / #F2F4F7 (alt). `current` is the cycle position p (−1 = stopped / none).
struct EuclideousAltCycleStrip: View {
    let main: Int; let alt: Int; let current: Int; let accent: Color; let frame: CGRect
    private func fill(_ i: Int, _ isAlt: Bool) -> Color {
        if i == current { return isAlt ? Color(hex: 0xF2F4F7) : accent }
        return isAlt ? Color(hex: 0x17191F) : Color(hex: 0x2A2D34)
    }
    var body: some View {
        let m = max(1, main)
        let cells = euclideousAltCycleCells(main: main, alt: alt, strip: CGRect(x: 0, y: 0, width: frame.width, height: frame.height))
        let ax = "Cycle: \(m) main, \(max(1, alt)) alt" + (current >= 0 ? (current >= m ? ", alt now" : ", main now") : "")
        return ZStack(alignment: .topLeading) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, r in
                cell(i: i, isAlt: i >= m, r: r)
            }
        }
        .frame(width: frame.width, height: frame.height, alignment: .topLeading).offset(x: frame.minX, y: frame.minY)
        .accessibilityElement(children: .ignore).accessibilityLabel(ax)
    }
    private func cell(i: Int, isAlt: Bool, r: CGRect) -> some View {
        let border: Color = isAlt ? Color(hex: 0xC8CCD4) : .clear
        return RoundedRectangle(cornerRadius: 3).fill(fill(i, isAlt))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(border, lineWidth: 1))
            .frame(width: r.width, height: r.height).offset(x: r.minX, y: r.minY)
    }
}

/// §5.7 — the ALT slider: its OWN look (not the MIX field tile). #2A2D34 ground r6; a top-trailing "main › alt" label; a 3 pt track #17191F (8 in from each side) with a lane100 fill from the start to the alt value and a #CED2DA tick at the main
/// value. Pill off (§5.8): the tile at 45 %, no fill, no "›"/alt, the main value alone at 45 %; the tick full strength. Relative drag (the first write of a drag opens the undo step) + double-tap to the main value, mirroring MIX.
struct EuclideousAltSliderTile: View {
    let main: Int; let value: Int; let range: ClosedRange<Int>; let gate: Bool
    let on: Bool; let accent: Color; let frame: CGRect
    let axLabel: String
    let onWrite: (Int, Bool) -> Void   // (value, newStep)
    let onReset: () -> Void
    @State private var startValue = 0
    @State private var axisH: Bool? = nil
    @State private var wroteOnce = false
    @GestureState private var live = false
    private func text(_ v: Int) -> String { gate ? "\(v)%" : "\(v)" }
    private func frac(_ v: Int) -> CGFloat { CGFloat(v - range.lowerBound) / CGFloat(max(1, range.upperBound - range.lowerBound)) }
    var body: some View {
        let inset: CGFloat = 8, trackW = max(1, frame.width - 2 * inset)
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 6).fill(Color(hex: 0x2A2D34)).opacity(on ? 1 : 0.45)
            label.opacity(on ? 1 : 0.45).padding(.trailing, inset).padding(.top, 3).frame(width: frame.width, alignment: .trailing)
            track(trackW).frame(width: trackW, height: frame.height, alignment: .leading).offset(x: inset, y: 0)
        }
        .frame(width: frame.width, height: frame.height)
        .contentShape(Rectangle())
        .gesture(on ? drag(trackW) : nil)
        .highPriorityGesture(on ? TapGesture(count: 2).onEnded { onReset() } : nil)
        .onChange(of: live) { l in if !l { axisH = nil; wroteOnce = false } }
        .offset(x: frame.minX, y: frame.minY)
        .accessibilityElement(children: .ignore).accessibilityLabel(axLabel)
    }
    private var label: some View {
        HStack(alignment: .lastTextBaseline, spacing: 3) {
            Text(text(main)).font(.system(size: 8.5, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0x8A909A))
            if on {
                Text("›").font(.system(size: 9, weight: .heavy)).foregroundColor(Color(hex: 0x6E737C))
                Text(text(value)).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(Color(hex: 0xF2F4F7))
            }
        }
    }
    private func track(_ trackW: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Capsule().fill(Color(hex: 0x17191F)).frame(width: trackW, height: 3)
            if on { Capsule().fill(accent).frame(width: max(0, trackW * frac(value)), height: 3) }
            RoundedRectangle(cornerRadius: 1).fill(Color(hex: 0xCED2DA)).frame(width: 2, height: 10).offset(x: trackW * frac(main) - 1)
        }
    }
    private func drag(_ trackW: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($live) { _, l, _ in l = true }
            .onChanged { d in
                if axisH == nil { axisH = abs(d.translation.width) >= abs(d.translation.height); if axisH == true { startValue = value; wroteOnce = false } }
                guard axisH == true else { return }
                let v = euclideousMixSliderDrag(kind: gate ? .gate : .velocity, startValue: startValue, translation: d.translation.width, trackWidth: trackW)
                if v == value { return }
                onWrite(v, !wroteOnce); wroteOnce = true
            }
            .onEnded { _ in axisH = nil; wroteOnce = false }
    }
}
