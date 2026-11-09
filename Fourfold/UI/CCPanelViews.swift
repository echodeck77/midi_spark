//  CCPanelViews.swift — CC tab (ratified Nov 2026): the bottom-right panel's fourth tab.
//
//  Four collapsed emitter rows A–D; touching a row opens that emitter's full page (header · trace · VALUE/TRAVEL · five bar sliders), which fills the panel. Emitters use the neutral emitter token, never lane colours; no explanatory
//  text anywhere — labels and values only. Every edit is one document write + one republish through `onEditEmitterCC` (one undo step per gesture). The TRACE is one bar of the emitter's output (the curve, grid, ticks, hit dots and a playhead; its looks are
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

/// One bar of an emitter's output: a dark tile, the step grid's lines, small ticks under each hit (`detailed` only), a light line for the curve, a dot on each hit's value in the colour of the LANE whose hit it is and — while the transport runs — a
/// playhead and a ring riding the drawn curve at the playhead, both in the colour of the lane whose hit is in effect at that position. There is ONE bar clock, so there is one playhead; with several lanes on the emitter it changes colour as the lane
/// driving the value changes. Drawn from the pure `emitterCCTrace`; nothing here keeps time except the playhead, which asks the page's clock.
struct CCTraceView: View {
    let trace: EmitterCCTrace
    var laneColours: [Color] = []
    var playhead: ((Date) -> Double?)? = nil     // the bar position 0…1 at a date, nil while stopped
    var detailed = false
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: playhead == nil)) { tl in
            Canvas { ctx, sz in draw(&ctx, sz, head: playhead?(tl.date)) }
        }
        .accessibilityHidden(true)
    }
    private func colour(_ lane: Int?) -> Color { guard let l = lane, !laneColours.isEmpty else { return P.light }; return laneColours[max(0, min(laneColours.count - 1, l))] }
    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize, head: Double?) {
        ctx.fill(RoundedRectangle(cornerRadius: 6).path(in: CGRect(origin: .zero, size: sz)), with: .color(P.slot))
        let inset: CGFloat = detailed ? 6 : 5
        let w = sz.width - 2 * inset
        func x(_ beat: Double) -> CGFloat { inset + CGFloat(beat / max(1e-9, trace.barBeats)) * w }
        for b in trace.gridBeats { ctx.fill(Path(CGRect(x: x(b) - 0.5, y: 0, width: 1, height: sz.height)), with: .color(P.rule)) }
        if detailed { for b in trace.ticks { ctx.fill(Path(CGRect(x: x(b) - 0.5, y: sz.height - 6, width: 1, height: 5)), with: .color(P.muted)) } }
        let points = trace.points
        if points.count > 1 {
            var path = Path()
            for (i, pt) in points.enumerated() {
                let q = emitterCCTracePoint(pt, barBeats: trace.barBeats, size: sz, inset: inset)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            ctx.stroke(path, with: .color(P.light), style: StrokeStyle(lineWidth: detailed ? 1.75 : 1.5, lineCap: .round, lineJoin: .round))
        }
        let r: CGFloat = detailed ? 3.5 : 2.75
        for (i, d) in trace.dots.enumerated() {
            let q = emitterCCTracePoint(d, barBeats: trace.barBeats, size: sz, inset: inset)
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)), with: .color(colour(i < trace.dotLanes.count ? trace.dotLanes[i] : nil)))
        }
        if let h = head {
            let f = max(0, min(1, h))
            let c = colour(emitterCCTraceLane(trace, atBeat: f * trace.barBeats))
            let hx = inset + CGFloat(f) * w
            ctx.fill(Path(CGRect(x: hx - 0.75, y: 0, width: 1.5, height: sz.height)), with: .color(c.opacity(0.9)))
            // The ring rides the DRAWN curve at the playhead, so it lands exactly on each static dot as the playhead reaches it (the engine's own last-sent value arrives a poll behind the page's clock and, after a slider change, used to finish
            // the old ramp until the next hit; the engine now re-plans at once and its stream is proved against this curve by the unit tests).
            if let v = emitterCCTraceValue(points, atBeat: f * trace.barBeats) {
                let y = inset + (1 - CGFloat(v) / 127) * (sz.height - 2 * inset)
                ctx.stroke(Path(ellipseIn: CGRect(x: hx - 3.5, y: y - 3.5, width: 7, height: 7)), with: .color(c), lineWidth: 1.75)
            }
        }
    }
}

// MARK: - collapsed rows

/// The four collapsed emitter rows filling the panel. Each row: the token (tap = the on switch), the CC number (large), the trace, two stacked labels (value mode · travel), a chevron. Off rows dim to ~45 %. Tapping anywhere but the token opens the page.
struct EuclideousCCPanel: View {
    let bodySize: CGSize
    let ccs: EmitterCCSet
    let traces: [EmitterCCTrace]
    let playhead: (Date) -> Double?
    let laneColours: [Color]
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
            CCTraceView(trace: traces[x], laneColours: laneColours, playhead: cc.on ? playhead : nil).frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 2) {
                Text(cc.valueMode == .pingPong ? "PING" : cc.valueMode.rawValue).font(heavyMonoCC(9)).foregroundColor(P.muted)
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
    let traces: [EmitterCCTrace]
    let playhead: (Date) -> Double?
    let laneColours: [Color]
    let playing: Bool
    let onEdit: (Bool, @escaping (inout EmitterCCSet) -> Void) -> Void
    let onCollapse: () -> Void

    private var letter: String { ["A", "B", "C", "D"][output] }
    private static let valueModes: [EmitterCCValueMode] = [.riff, .pingPong]
    var body: some View {
        let cc = ccs[output]
        VStack(spacing: 8) {
            header(cc)
            CCTraceView(trace: traces[output], laneColours: laneColours, playhead: cc.on ? playhead : nil, detailed: true).frame(height: 84)
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
            EmitterRatchetSegmented(options: ["RIFF", "PING"], selected: Self.valueModes.firstIndex(of: cc.valueMode) ?? 0, height: 26, groupLabel: "Value") { i in onEdit(true) { $0[output].valueMode = Self.valueModes[i] } }
            Text("TRAVEL").font(heavyMonoCC(9)).foregroundColor(P.muted)
            EmitterRatchetSegmented(options: ["STEP", "GLIDE", "FALL"], selected: cc.travel == .step ? 0 : (cc.travel == .glide ? 1 : 2), height: 26, groupLabel: "Travel") { i in onEdit(true) { $0[output].travel = i == 0 ? .step : (i == 1 ? .glide : .fall) } }
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder private func rightColumn(_ cc: EmitterCC) -> some View {
        VStack(spacing: 6) {
            CCBarSlider(label: "HIGH", value: cc.high) { v, s in onEdit(s) { $0[output].high = v } }
            CCBarSlider(label: "LOW", value: cc.low) { v, s in onEdit(s) { $0[output].low = v } }
            CCBarSlider(label: "TIME", value: cc.time, lo: EmitterCC.minTime, hi: EmitterCC.maxTime, dimmed: emitterCCFieldIsInert(.time, travel: cc.travel)) { v, s in onEdit(s) { $0[output].time = v } }
            CCBarSlider(label: "MUTE", value: cc.muteValue) { v, s in onEdit(s) { $0[output].muteValue = v } }
            Spacer(minLength: 0)
        }
    }
}
