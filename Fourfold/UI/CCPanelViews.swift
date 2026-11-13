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

/// The CC number as a plate you slide: drag up to raise it, down to lower it (`emitterCCNumberDrag`, relative to where the touch began), the chevrons beside it stay for single steps. One undo step per drag.
struct CCNumberSlider: View {
    let value: Int
    let onChange: (Int, Bool) -> Void   // (new value, newStep)
    @State private var start: Int? = nil
    @State private var burstOpen = false
    @GestureState private var gestureLive = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .heavy)).foregroundColor(P.muted)
            Text("\(value)").font(heavyMonoCC(16)).foregroundColor(P.text).frame(minWidth: 28)
        }
        .frame(width: 64, height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(P.slot))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.rule, lineWidth: 1))
        .contentShape(Rectangle().inset(by: -4))
        .gesture(DragGesture(minimumDistance: 3)
            .updating($gestureLive) { _, live, _ in live = true }
            .onChanged { g in
                if start == nil { start = value }
                let v = emitterCCNumberDrag(start: start ?? value, travelUp: -g.translation.height)
                guard v != value else { return }
                onChange(v, !burstOpen)   // the first write of a drag opens its undo step; the rest join it
                burstOpen = true
            }
            .onEnded { _ in finish() })
        .onChange(of: gestureLive) { live in if !live { finish() } }   // the system cancelled the touch: the next drag starts fresh
    }   // (VoiceOver: the stepper group around it is the one adjustable "CC number" element)
    private func finish() { start = nil; burstOpen = false }
}

/// One bar of an emitter's output: a dark tile, the step grid's lines, small ticks under each hit (`detailed` only), a light line for the curve, a dot on each hit's value in the colour of the LANE whose hit it is and — while the transport runs — a
/// playhead and a ring riding the drawn curve at the playhead, both in the colour of the lane whose hit is in effect at that position. There is ONE bar clock, so there is one playhead; with several lanes on the emitter it changes colour as the lane
/// driving the value changes. Drawn from the pure `emitterCCTrace`; nothing here keeps time except the playhead, which asks the page's clock.
struct CCTraceView: View {
    let trace: EmitterCCTrace
    var laneColours: [Color] = []
    var playhead: ((Date) -> Double?)? = nil     // the bar position 0…1 at a date, nil while stopped
    var detailed = false
    // CC SLOTS §4.4 — the rows' band trace: the LINE in the driver lane's colour + a faint area under it, faint beat dividers, no dots/ticks. nil ⇒ the edit page's look (white line, lane-coloured dots).
    var lineColour: Color? = nil
    var areaColour: Color? = nil
    var hideDots = false
    var faintDividers = false
    var bgRadius: CGFloat = 6
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: playhead == nil)) { tl in
            Canvas { ctx, sz in draw(&ctx, sz, head: playhead?(tl.date)) }
        }
        .accessibilityHidden(true)
    }
    private func colour(_ lane: Int?) -> Color { guard let l = lane, !laneColours.isEmpty else { return P.light }; return laneColours[max(0, min(laneColours.count - 1, l))] }
    private func draw(_ ctx: inout GraphicsContext, _ sz: CGSize, head: Double?) {
        ctx.fill(RoundedRectangle(cornerRadius: bgRadius).path(in: CGRect(origin: .zero, size: sz)), with: .color(P.slot))
        let inset: CGFloat = detailed ? 6 : (lineColour != nil ? 3 : 5)   // §4.4: 3 pt top/bottom for a band
        let w = sz.width - 2 * inset
        func x(_ beat: Double) -> CGFloat { inset + CGFloat(beat / max(1e-9, trace.barBeats)) * w }
        let dividerC: Color = faintDividers ? Color.white.opacity(0.05) : P.rule
        for b in trace.gridBeats { ctx.fill(Path(CGRect(x: x(b) - 0.25, y: 0, width: faintDividers ? 0.5 : 1, height: sz.height)), with: .color(dividerC)) }
        if detailed { for b in trace.ticks { ctx.fill(Path(CGRect(x: x(b) - 0.5, y: sz.height - 6, width: 1, height: 5)), with: .color(P.muted)) } }
        let points = trace.points
        if points.count > 1 {
            var path = Path()
            for (i, pt) in points.enumerated() {
                let q = emitterCCTracePoint(pt, barBeats: trace.barBeats, size: sz, inset: inset)
                if i == 0 { path.move(to: q) } else { path.addLine(to: q) }
            }
            if let area = areaColour {   // §4.4: fill the area under the curve
                var fill = path
                fill.addLine(to: CGPoint(x: emitterCCTracePoint(points[points.count - 1], barBeats: trace.barBeats, size: sz, inset: inset).x, y: sz.height))
                fill.addLine(to: CGPoint(x: emitterCCTracePoint(points[0], barBeats: trace.barBeats, size: sz, inset: inset).x, y: sz.height))
                fill.closeSubpath()
                ctx.fill(fill, with: .color(area))
            }
            ctx.stroke(path, with: .color(lineColour ?? P.light), style: StrokeStyle(lineWidth: lineColour != nil ? 1.25 : (detailed ? 1.75 : 1.5), lineCap: .round, lineJoin: .round))
        }
        if !hideDots {
        let r: CGFloat = detailed ? 3.5 : 2.75
        for (i, d) in trace.dots.enumerated() {
            let q = emitterCCTracePoint(d, barBeats: trace.barBeats, size: sz, inset: inset)
            ctx.fill(Path(ellipseIn: CGRect(x: q.x - r, y: q.y - r, width: 2 * r, height: 2 * r)), with: .color(colour(i < trace.dotLanes.count ? trace.dotLanes[i] : nil)))
        }
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

// MARK: - the four-cell rows (CC SLOTS §4; widened + spread 2026-11-13)

/// §4: four output rows A–D; each row is a token tile + FOUR cells (slots a/b/c/d) SIDE BY SIDE across the row, each a BIG CC number over
/// its own trace in the slot's DRIVER lane's colour. Tap a cell ⇒ that slot's edit page. No on switch, no chevron (§4.7); the on/off edit is on the page.
struct EuclideousCCRowsPanel: View {
    let bodySize: CGSize
    let ccs: EmitterCCSet
    let traces: [EmitterCCTrace]        // 16, per slot (output×4 + slot)
    let drivers: [Int]                  // 16, 0-based driver lane per slot
    let laneColours: [Color]
    let outputFullyMuted: [Bool]        // 4
    let playhead: (Date) -> Double?
    let playing: Bool
    let onExpand: (Int) -> Void

    private static let nearWhite = Color(.sRGB, red: 0xF2 / 255, green: 0xF4 / 255, blue: 0xF7 / 255, opacity: 1)
    private func driverColour(_ k: Int) -> Color { let d = k < drivers.count ? drivers[k] : 0; return laneColours[max(0, min(laneColours.count - 1, d))] }
    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<EuclideousCCRowsMetrics.rows, id: \.self) { o in
                let r = euclideousCCRowRect(o, panel: bodySize)
                row(o, rect: r).frame(width: r.width, height: r.height).position(x: r.midX, y: r.midY)
            }
        }.frame(width: bodySize.width, height: bodySize.height, alignment: .topLeading)
    }
    @ViewBuilder private func row(_ o: Int, rect: CGRect) -> some View {
        let L = euclideousCCRowLayout(rowWidth: rect.width, rowHeight: rect.height)
        let anyOn = (0..<EuclideousCCRowsMetrics.slots).contains { ccs[output: o, slot: $0].on }
        let muted = o < outputFullyMuted.count && outputFullyMuted[o]
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: EuclideousCCRowsMetrics.tileRadius).fill(Color(.sRGB, red: 0x1D / 255, green: 0x1F / 255, blue: 0x24 / 255, opacity: 1))
                .frame(width: L.tile.width, height: L.tile.height)
                .overlay(EuclideousEmitterTokenView(size: .d28, letter: euclideousOutputLetter(o), state: euclideousEmitterTokenEmitterState(muted: muted, activity: 0, anyRouted: anyOn), lane: Color.clear))
                .position(x: L.tile.midX, y: L.tile.midY)
                .accessibilityHidden(true)
            ForEach(0..<EuclideousCCRowsMetrics.slots, id: \.self) { s in cell(o: o, s: s, rect: L.cells[s]) }
        }
    }
    @ViewBuilder private func cell(o: Int, s: Int, rect: CGRect) -> some View {
        let k = o * EmitterCCSet.slotsPerEmitter + s, cc = ccs[k], dc = driverColour(k)
        let split = euclideousCCCellSplit(cellSize: rect.size)
        let fs = euclideousCCNumberFontSize(cellSize: rect.size)
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: EuclideousCCRowsMetrics.cellRadius).fill(P.slot)
            CCTraceView(trace: traces[k], laneColours: laneColours, playhead: cc.on ? playhead : nil,
                        lineColour: cc.on ? dc.opacity(0.85) : nil, areaColour: cc.on ? dc.opacity(0.14) : nil, hideDots: true, faintDividers: true, bgRadius: 0)
                .frame(width: split.trace.width, height: split.trace.height)
                .position(x: split.trace.midX, y: split.trace.midY)
            Text("\(cc.ccNumber)").font(heavyMonoCC(fs)).minimumScaleFactor(0.6).lineLimit(1)
                .foregroundColor(cc.on ? Self.nearWhite : P.muted)
                .frame(width: split.number.width, height: split.number.height)
                .position(x: split.number.midX, y: split.number.midY)
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: EuclideousCCRowsMetrics.cellRadius))
        .overlay(RoundedRectangle(cornerRadius: EuclideousCCRowsMetrics.cellRadius).strokeBorder(cc.on ? dc.opacity(0.6) : P.rule, lineWidth: 1))
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Rectangle())
        .onTapGesture { onExpand(k) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousCCBandAX(output: o, cc: cc.ccNumber, driverLane: (k < drivers.count ? drivers[k] : 0) + 1, on: cc.on))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - the edit page (one slot) + the lane picker (CC SLOTS §5)

/// One SLOT's full page: a header (token · ON switch · CC stepper · close), the trace in the driver lane's colour (tap ⇒ the lane picker), and two columns — VALUE/TO/CURVE on the left, the six bar sliders on the right. All read/write THIS slot.
struct EuclideousCCExpandedView: View {
    let slot: Int                         // the flat slot index k = output×4 + slot
    let bodySize: CGSize
    let ccs: EmitterCCSet
    let trace: EmitterCCTrace
    let driverLane: Int                   // 0-based
    let laneColours: [Color]
    let laneLines: [EuclidLine]           // the four Euclid lanes, for the picker's real rhythm pictures
    let laneBeat: (Date) -> Double        // the lanes' musical beat at a date (drives the pictures' playheads)
    let playhead: (Date) -> Double?
    let playing: Bool
    let onEdit: (Bool, @escaping (inout EmitterCCSet) -> Void) -> Void
    let onCollapse: () -> Void
    @State private var pickerOpen = false

    private var output: Int { slot / EmitterCCSet.slotsPerEmitter }
    private var slotIndex: Int { slot % EmitterCCSet.slotsPerEmitter }
    private var letter: String { euclideousOutputLetter(output) }
    private func laneColour(_ d: Int) -> Color { laneColours[max(0, min(laneColours.count - 1, d))] }
    private static let valueModes: [EmitterCCValueMode] = [.hits, .riff, .pingPong, .climb]
    var body: some View {
        let cc = ccs[slot]
        VStack(spacing: 8) {
            header(cc)
            if pickerOpen {   // §5.5 (rebuilt 2026-11-13): the lane picker fills the whole body below the header
                pickerBody.frame(maxWidth: .infinity, maxHeight: .infinity).transition(.opacity)
            } else {
                traceArea(cc).frame(height: 84)
                HStack(alignment: .top, spacing: 10) {
                    leftColumn(cc).frame(width: min(186, bodySize.width * 0.42))
                    rightColumn(cc).frame(maxWidth: .infinity)
                }
                .transition(.opacity)
            }
        }
        .frame(width: bodySize.width, height: bodySize.height, alignment: .topLeading)
    }
    /// §5.4: the trace in the driver lane's colour with a lane tag at the top-left; tapping it opens the full lane picker.
    @ViewBuilder private func traceArea(_ cc: EmitterCC) -> some View {
        let dc = laneColour(driverLane)
        ZStack(alignment: .topLeading) {
            CCTraceView(trace: trace, laneColours: laneColours, playhead: cc.on ? playhead : nil, detailed: true, lineColour: cc.on ? dc : nil)
                .contentShape(Rectangle())
                .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { pickerOpen = true } }
                .accessibilityElement(children: .ignore).accessibilityLabel(euclideousCCDriverAX(lane: driverLane + 1))
                .accessibilityAddTraits(.isButton).accessibilityAction(named: Text("Choose lane")) { withAnimation { pickerOpen = true } }
            laneTab(driverLane, dc: dc).padding(EuclideousCCPickerMetrics.laneTabInset)   // §5.4 top-left
        }
    }
    @ViewBuilder private func laneTab(_ d: Int, dc: Color) -> some View {
        Text("\(d + 1)").font(heavyMonoCC(EuclideousCCPickerMetrics.laneTabFontSize)).foregroundColor(P.ink)
            .frame(width: EuclideousCCPickerMetrics.laneTabW, height: EuclideousCCPickerMetrics.laneTabH)
            .background(RoundedRectangle(cornerRadius: EuclideousCCPickerMetrics.laneTabRadius).fill(dc))
    }
    /// §5.5 (rebuilt 2026-11-13): the four Euclid lanes as REAL rhythm pictures in a 2×2 grid filling the body. The current driver is
    /// full-strength with its colour wash + a thick lane-colour border + a filled lane tag; the others are dimmed with a thin border. Tap one ⇒ it drives this slot (one undo step); the header × closes the picker.
    private var pickerBody: some View {
        GeometryReader { geo in
            let rects = euclideousCCPickerGrid(size: geo.size)
            TimelineView(.animation(paused: !playing)) { tl in
                let beat = playing ? laneBeat(tl.date) : 0
                ZStack(alignment: .topLeading) {
                    ForEach(0..<4, id: \.self) { lane in laneCell(lane, rect: rects[lane], beat: beat) }
                }
            }
        }
    }
    @ViewBuilder private func laneCell(_ lane: Int, rect: CGRect, beat: Double) -> some View {
        let dc = laneColour(lane), current = lane == driverLane
        let line = lane < laneLines.count ? laneLines[lane] : EuclidLine()
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: EuclideousCCPickerMetrics.cellRadius).fill(current ? dc.opacity(0.14) : P.slot)
            EuclideousRandomRhythmPicture(line: line, original: nil, accent: dc, beat: beat)
                .opacity(current ? 1 : 0.4)
                .padding(8)
            laneTab(lane, dc: dc).padding(EuclideousCCPickerMetrics.laneTabInset)
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: EuclideousCCPickerMetrics.cellRadius))
        .overlay(RoundedRectangle(cornerRadius: EuclideousCCPickerMetrics.cellRadius).strokeBorder(current ? dc : P.rule, lineWidth: current ? 3 : 1))
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Rectangle())
        .onTapGesture { onEdit(true) { $0[slot].driverLane = lane + 1 }; withAnimation(.easeInOut(duration: 0.12)) { pickerOpen = false } }
        .accessibilityElement(children: .ignore).accessibilityLabel("Lane \(lane + 1)").accessibilityAddTraits(current ? [.isButton, .isSelected] : [.isButton])
    }
    @ViewBuilder private func header(_ cc: EmitterCC) -> some View {
        HStack(spacing: 8) {
            // §5.1 the token (display only — the emitter this slot sends on) + §5.2 the per-slot ON switch after it.
            EuclideousEmitterTokenView(size: .d28, letter: letter, state: euclideousEmitterTokenEmitterState(muted: false, activity: 0, anyRouted: cc.on), lane: Color.clear)
                .frame(width: 30, height: 30).accessibilityHidden(true)
            onSwitch(cc.on)
            Spacer(minLength: 0)
            ccStepper(cc)
            // CLOSE (§5.5): with the picker open it closes only the picker; otherwise back to the rows.
            Image(systemName: "xmark").font(.system(size: 14, weight: .heavy)).foregroundColor(P.ink)
                .frame(width: 52, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(P.light))
                .contentShape(Rectangle().inset(by: -4)).onTapGesture { if pickerOpen { withAnimation(.easeInOut(duration: 0.12)) { pickerOpen = false } } else { onCollapse() } }
                .accessibilityElement(children: .ignore).accessibilityLabel("Close").accessibilityAddTraits(.isButton)
        }
        .frame(height: 30)
    }
    /// §5.2 the slot's ON switch (the app's standard on/off pill).
    @ViewBuilder private func onSwitch(_ on: Bool) -> some View {
        Text(on ? "ON" : "OFF").font(heavyMonoCC(9)).tracking(0.8).foregroundColor(on ? P.ink : P.muted)
            .frame(width: 40, height: 24)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? P.light : P.slot))
            .overlay(on ? nil : RoundedRectangle(cornerRadius: 6).strokeBorder(P.rule, lineWidth: 1))
            .contentShape(Rectangle().inset(by: -4)).onTapGesture { onEdit(true) { $0[slot].on.toggle() } }
            .accessibilityElement(children: .ignore).accessibilityLabel("On").accessibilityValue(on ? "on" : "off").accessibilityAddTraits(.isButton).ringToggleTrait()
    }
    @ViewBuilder private func ccStepper(_ cc: EmitterCC) -> some View {
        HStack(spacing: 4) {
            Text("CC").font(heavyMonoCC(10)).foregroundColor(P.muted)
            Text("\u{2039}").font(heavyMonoCC(15)).foregroundColor(P.muted).frame(width: 28, height: 30).contentShape(Rectangle().inset(by: -4)).onTapGesture { onEdit(true) { $0[slot].ccNumber = $0.nextCCNumber(from: $0[slot].ccNumber, output: output, slot: slotIndex, up: false) } }   // §1.4 skip
            CCNumberSlider(value: cc.ccNumber) { v, newStep in onEdit(newStep) { s in var v2 = v; if (0..<EmitterCCSet.slotsPerEmitter).contains(where: { $0 != slotIndex && s[output: output, slot: $0].ccNumber == v }) { v2 = s.nextCCNumber(from: v, output: output, slot: slotIndex, up: true) }; s[slot].ccNumber = v2 } }   // §1.4: a drag onto a taken number skips to the next free
            Text("\u{203A}").font(heavyMonoCC(15)).foregroundColor(P.muted).frame(width: 28, height: 30).contentShape(Rectangle().inset(by: -4)).onTapGesture { onEdit(true) { $0[slot].ccNumber = $0.nextCCNumber(from: $0[slot].ccNumber, output: output, slot: slotIndex, up: true) } }   // §1.4 skip
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("CC number").accessibilityValue("\(cc.ccNumber)")
        .accessibilityAdjustableAction { d in onEdit(true) { $0[slot].ccNumber = max(0, min(EmitterCC.maxCC, $0[slot].ccNumber + (d == .increment ? 1 : -1))) } }
    }
    @ViewBuilder private func leftColumn(_ cc: EmitterCC) -> some View {
        let toInert = emitterCCToIsInert(cc)        // a HOLD of 100 % keeps the hit's value for the whole gap: there is nothing to ramp TO (dimmed, still tappable)
        let curveInert = emitterCCCurveIsInert(cc)  // the curve shapes a ramp that is 0 when HOLD is 100 or RAMP is 0
        VStack(alignment: .leading, spacing: 8) {   // three label-over-segments groups, as tall as the six sliders beside them
            VStack(alignment: .leading, spacing: 3) {
                Text("VALUE").font(heavyMonoCC(9)).foregroundColor(P.muted)
                EmitterRatchetSegmented(options: ["HITS", "RIFF", "PING", "CLIMB"], selected: Self.valueModes.firstIndex(of: cc.valueMode) ?? 0, height: 24, groupLabel: "Value") { i in onEdit(true) { $0[slot].valueMode = Self.valueModes[i] } }
            }
            VStack(alignment: .leading, spacing: 3) {
                Text("TO").font(heavyMonoCC(9)).foregroundColor(P.muted)
                EmitterRatchetSegmented(options: ["REST", "NEXT"], selected: cc.to == .rest ? 0 : 1, height: 24, groupLabel: "To") { i in onEdit(true) { $0[slot].to = i == 0 ? .rest : .next } }
            }.opacity(toInert ? 0.35 : 1)
            VStack(alignment: .leading, spacing: 3) {
                Text("CURVE").font(heavyMonoCC(9)).foregroundColor(P.muted)
                EmitterRatchetSegmented(options: ["LIN", "EXP"], selected: cc.curve == .lin ? 0 : 1, height: 24, groupLabel: "Curve") { i in onEdit(true) { $0[slot].curve = i == 0 ? .lin : .exp } }
            }.opacity(curveInert ? 0.35 : 1)
            Spacer(minLength: 0)
        }
    }
    @ViewBuilder private func rightColumn(_ cc: EmitterCC) -> some View {
        VStack(spacing: 6) {
            CCBarSlider(label: "HIGH", value: cc.high) { v, s in onEdit(s) { $0[slot].high = v } }
            CCBarSlider(label: "LOW", value: cc.low) { v, s in onEdit(s) { $0[slot].low = v } }
            CCBarSlider(label: "HOLD", value: cc.hold, lo: 0, hi: 100) { v, s in onEdit(s) { $0[slot].hold = v } }
            // RAMP reads the EFFECTIVE ramp (what HOLD leaves of the gap); the stored value is kept, so lowering HOLD restores it
            CCBarSlider(label: "RAMP", value: cc.effectiveRamp, lo: 0, hi: 100, dimmed: emitterCCFieldIsInert(.ramp, cc)) { v, s in onEdit(s) { $0[slot].ramp = v } }
            CCBarSlider(label: "PASSES", value: cc.passes, lo: 1, hi: EmitterCC.maxPasses, dimmed: emitterCCFieldIsInert(.passes, cc)) { v, s in onEdit(s) { $0[slot].passes = v } }
            CCBarSlider(label: "MUTE", value: cc.muteValue) { v, s in onEdit(s) { $0[slot].muteValue = v } }
            Spacer(minLength: 0)
        }
    }
}
