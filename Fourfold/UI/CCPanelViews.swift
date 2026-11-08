//  CCPanelViews.swift — CC tab (ratified Nov 2026): the bottom-right panel's fourth tab.
//
//  Four collapsed emitter rows A–D; touching a row opens that emitter's full page (header · trace · VALUE/TRAVEL · five bar sliders), which fills the panel. Emitters use the neutral emitter token, never lane colours; no explanatory
//  text anywhere — labels and values only. Every edit is one document write + one republish through `onEditEmitterCC` (one undo step per gesture). The live TRACE is a simple current-value line for now (the full curve/grid/ticks are
//  device-owed, flagged). The model and the engine are in `Models.swift` / `Router.swift` (the CC tab ferry's slice A); this file is only the UI.

import SwiftUI

private typealias P = EmitterRatchetPalette
private func heavyMonoCC(_ s: CGFloat) -> Font { .system(size: s, weight: .heavy, design: .monospaced) }
private let ccNeutral = Color(.sRGB, red: 0xDF / 255, green: 0xE3 / 255, blue: 0xEA / 255, opacity: 1)   // the neutral emitter colour (never a lane colour)

/// One 0…127 (or a custom range) bar slider: label · dark track with a grey fill to the value · value. Drag anywhere on the bar; one undo burst per gesture. `dimmed` greys it (LEVEL in RIFF mode).
struct CCBarSlider: View {
    let label: String
    let value: Int
    var lo = 0
    var hi = 127
    var dimmed = false
    let onChange: (Int, Bool) -> Void   // (new value, newStep)
    @GestureState private var dragging = false

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(heavyMonoCC(9)).foregroundColor(P.muted).frame(width: 40, alignment: .leading)
            GeometryReader { geo in
                let f = CGFloat(max(0, min(hi - lo, value - lo))) / CGFloat(max(1, hi - lo))
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4).fill(P.slot)
                    RoundedRectangle(cornerRadius: 4).fill(P.muted).frame(width: max(2, geo.size.width * f))
                }
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, s, _ in s = true }
                    .onChanged { g in
                        let frac = max(0, min(1, g.location.x / max(1, geo.size.width)))
                        let v = lo + Int((frac * CGFloat(hi - lo)).rounded())
                        if v != value { onChange(v, !dragging) }   // newStep on the first change of the drag
                    })
            }
            .frame(height: 16)
            Text("\(value)").font(heavyMonoCC(11)).foregroundColor(P.text).frame(width: 30, alignment: .trailing)
        }
        .opacity(dimmed ? 0.35 : 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label).accessibilityValue("\(value)")
        .accessibilityAdjustableAction { d in onChange(max(lo, min(hi, value + (d == .increment ? 1 : -1))), true) }
    }
}

/// A simple live trace: a dark tile with a light horizontal line at the current CC value. The full-bar curve, step grid and per-hit ticks are device-owed (flagged).
struct CCTraceView: View {
    let value: Int   // 0…127, or < 0 for "none yet"
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 6).fill(P.slot)
                if value >= 0 {
                    let y = geo.size.height * (1 - CGFloat(value) / 127)
                    P.light.frame(height: 1.5).offset(y: y - geo.size.height + 0.75)
                }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - collapsed rows

/// The four collapsed emitter rows filling the panel. Each row: the token (tap = the on switch), the CC number (large), the trace, two stacked labels (value mode · travel), a chevron. Off rows dim to ~45 %. Tapping anywhere but the token opens the page.
struct EuclideousCCPanel: View {
    let bodySize: CGSize
    let ccs: EmitterCCSet
    @ObservedObject var live: EmitterRatchetLive
    let playing: Bool
    let onEdit: (Bool, @escaping (inout EmitterCCSet) -> Void) -> Void
    let onExpand: (Int) -> Void

    private let letters = ["A", "B", "C", "D"]
    var body: some View {
        let gap: CGFloat = 6
        let rowH = max(1, (bodySize.height - gap * 3) / 4)
        VStack(spacing: gap) { ForEach(0..<4, id: \.self) { x in row(x, rowH: rowH) } }
            .frame(width: bodySize.width, height: bodySize.height, alignment: .topLeading)
    }
    @ViewBuilder private func row(_ x: Int, rowH: CGFloat) -> some View {
        let cc = ccs[x]
        HStack(spacing: 8) {
            EmitterRatchetDisc(letter: letters[x], on: cc.on, accent: ccNeutral, f: playing ? 0 : 0)
                .frame(width: 44, height: rowH)
                .contentShape(Rectangle())
                .onTapGesture { onEdit(true) { $0[x].on.toggle() } }
                .accessibilityElement(children: .ignore).accessibilityLabel("Emitter \(letters[x])").accessibilityValue(cc.on ? "on" : "off").accessibilityAddTraits(.isButton).ringToggleTrait()
            Text("\(cc.ccNumber)").font(heavyMonoCC(22)).foregroundColor(P.text).frame(width: 46, alignment: .leading)
            CCTraceView(value: cc.on ? (live.index(x) ?? -1) : -1).frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 2) {
                Text(cc.valueMode.rawValue).font(heavyMonoCC(9)).foregroundColor(P.muted)
                Text(cc.travel.rawValue).font(heavyMonoCC(9)).foregroundColor(P.muted)
            }
            Text("\u{203A}").font(heavyMonoCC(16)).foregroundColor(P.muted).frame(width: 14)   // chevron
        }
        .padding(.horizontal, 8)
        .frame(height: rowH)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.sRGB, red: 0x1B / 255, green: 0x1D / 255, blue: 0x23 / 255, opacity: 1)))
        .opacity(cc.on ? 1 : 0.45)
        .contentShape(Rectangle())
        .onTapGesture { onExpand(x) }   // the token above has its own tap (toggle); the rest of the row opens the page
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Emitter \(letters[x]) CC \(cc.ccNumber), \(cc.valueMode.rawValue.lowercased()), \(cc.travel.rawValue.lowercased())")
    }
}

// MARK: - the expanded page

/// One emitter's full page: a header (token · on switch · CC stepper · close), the trace, and two columns — VALUE/TRAVEL segmented on the left, five bar sliders on the right.
struct EuclideousCCExpandedView: View {
    let output: Int
    let bodySize: CGSize
    let ccs: EmitterCCSet
    @ObservedObject var live: EmitterRatchetLive
    let playing: Bool
    let onEdit: (Bool, @escaping (inout EmitterCCSet) -> Void) -> Void
    let onCollapse: () -> Void

    private var letter: String { ["A", "B", "C", "D"][output] }
    var body: some View {
        let cc = ccs[output]
        VStack(spacing: 8) {
            header(cc)
            CCTraceView(value: cc.on ? (live.index(output) ?? -1) : -1).frame(height: 84)
            HStack(alignment: .top, spacing: 10) {
                leftColumn(cc).frame(width: min(186, bodySize.width * 0.42))
                rightColumn(cc).frame(maxWidth: .infinity)
            }
        }
        .frame(width: bodySize.width, height: bodySize.height, alignment: .topLeading)
    }
    @ViewBuilder private func header(_ cc: EmitterCC) -> some View {
        HStack(spacing: 8) {
            EmitterRatchetDisc(letter: letter, on: cc.on, accent: ccNeutral, f: 0)
                .frame(width: 36, height: 30)
                .contentShape(Rectangle()).onTapGesture { onEdit(true) { $0[output].on.toggle() } }
                .accessibilityElement(children: .ignore).accessibilityLabel("Emitter \(letter)").accessibilityValue(cc.on ? "on" : "off").accessibilityAddTraits(.isButton).ringToggleTrait()
            Spacer(minLength: 0)
            ccStepper(cc)
            Text("\u{2715}").font(heavyMonoCC(14)).foregroundColor(P.muted).frame(width: 30, height: 30)
                .contentShape(Rectangle()).onTapGesture(perform: onCollapse)
                .accessibilityElement(children: .ignore).accessibilityLabel("Close").accessibilityAddTraits(.isButton)
        }
        .frame(height: 30)
    }
    @ViewBuilder private func ccStepper(_ cc: EmitterCC) -> some View {
        HStack(spacing: 3) {
            Text("CC").font(heavyMonoCC(10)).foregroundColor(P.muted)
            Text("\u{2039}").font(heavyMonoCC(13)).foregroundColor(P.muted).frame(width: 20, height: 30).contentShape(Rectangle()).onTapGesture { onEdit(true) { $0[output].ccNumber = max(0, $0[output].ccNumber - 1) } }
            Text("\(cc.ccNumber)").font(heavyMonoCC(13)).foregroundColor(P.text).frame(minWidth: 26)
            Text("\u{203A}").font(heavyMonoCC(13)).foregroundColor(P.muted).frame(width: 20, height: 30).contentShape(Rectangle()).onTapGesture { onEdit(true) { $0[output].ccNumber = min(EmitterCC.maxCC, $0[output].ccNumber + 1) } }
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("CC number").accessibilityValue("\(cc.ccNumber)")
        .accessibilityAdjustableAction { d in onEdit(true) { $0[output].ccNumber = max(0, min(EmitterCC.maxCC, $0[output].ccNumber + (d == .increment ? 1 : -1))) } }
    }
    @ViewBuilder private func leftColumn(_ cc: EmitterCC) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("VALUE").font(heavyMonoCC(9)).foregroundColor(P.muted)
            EmitterRatchetSegmented(options: ["FIXED", "RIFF"], selected: cc.valueMode == .riff ? 1 : 0, height: 26, groupLabel: "Value") { i in onEdit(true) { $0[output].valueMode = i == 1 ? .riff : .fixed } }
            Text("TRAVEL").font(heavyMonoCC(9)).foregroundColor(P.muted)
            EmitterRatchetSegmented(options: ["STEP", "GLIDE", "FALL"], selected: cc.travel == .step ? 0 : (cc.travel == .glide ? 1 : 2), height: 26, groupLabel: "Travel") { i in onEdit(true) { $0[output].travel = i == 0 ? .step : (i == 1 ? .glide : .fall) } }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder private func rightColumn(_ cc: EmitterCC) -> some View {
        VStack(spacing: 6) {
            CCBarSlider(label: "LEVEL", value: cc.level, dimmed: cc.valueMode == .riff) { v, s in onEdit(s) { $0[output].level = v } }
            CCBarSlider(label: "HIGH", value: cc.high) { v, s in onEdit(s) { $0[output].high = v } }
            CCBarSlider(label: "LOW", value: cc.low) { v, s in onEdit(s) { $0[output].low = v } }
            CCBarSlider(label: "TIME", value: cc.time, lo: EmitterCC.minTime, hi: EmitterCC.maxTime) { v, s in onEdit(s) { $0[output].time = v } }
            CCBarSlider(label: "MUTE", value: cc.muteValue) { v, s in onEdit(s) { $0[output].muteValue = v } }
            Spacer(minLength: 0)
        }
    }
}
