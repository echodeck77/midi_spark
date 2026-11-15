//  CCPanelViews.swift — CC tab (ratified Nov 2026): the bottom-right panel's fourth tab.
//
//  Four collapsed emitter rows A–D; touching a row opens that emitter's full page (header · trace · VALUE/TRAVEL · five bar sliders), which fills the panel. Emitters use the neutral emitter token, never lane colours; no explanatory
//  text anywhere — labels and values only. Every edit is one document write + one republish through `onEditEmitterCC` (one undo step per gesture). The TRACE is one bar of the emitter's output (the curve, grid, ticks, hit dots and a playhead; its looks are
//  device-owed, flagged). The model and the engine are in `Models.swift` / `Router.swift` (the CC tab ferry's slice A); this file is only the UI.

import SwiftUI

private typealias P = EmitterRatchetPalette
private func heavyMonoCC(_ s: CGFloat) -> Font { .system(size: s, weight: .heavy, design: .monospaced) }
private let ccNeutral = Color(.sRGB, red: 0xDF / 255, green: 0xE3 / 255, blue: 0xEA / 255, opacity: 1)   // the neutral emitter colour (never a lane colour)

/// CC page v2 §2.2: the power glyph — an open arc (gap at the top) with a vertical stem through the gap; stroke 2, round caps. Drawn in its rect; the caller strokes it. Device-owed look.
struct EuclideousCCPowerIcon: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: rect.midX, y: rect.midY + rect.height * 0.07)
        let r = min(rect.width, rect.height) * 0.36
        p.addArc(center: c, radius: r, startAngle: .degrees(-48), endAngle: .degrees(228), clockwise: false)   // everything but a ~96° gap centred on 12 o'clock (SwiftUI y-down)
        p.move(to: CGPoint(x: c.x, y: c.y - r * 1.22))
        p.addLine(to: CGPoint(x: c.x, y: c.y - r * 0.1))
        return p
    }
}

/// One 0…127 (or a custom range) bar slider: label · dark track with a grey fill to the value · value. The whole row is a tall touch target;
/// the drag is RELATIVE (a scrubber anchored at touch-down — it never jumps to the finger), matching the app's other value fields. One undo burst per gesture. `dimmed` greys it.
struct CCBarSlider: View {
    let label: String
    let value: Int
    var lo = 0
    var hi = 127
    var dimmed = false
    let onChange: (Int, Bool) -> Void   // (new value, newStep)
    @GestureState private var dragging = false
    @State private var startValue: Int? = nil

    var body: some View {
        // CC page v2 §4.2: label 44 (10 pt, #9097A1) · bar (the rest, 14 tall, r5, #202329 track, #7C838E fill) · value 26 (12 pt, #F2F4F7), right.
        HStack(spacing: 6) {
            Text(label).font(heavyMonoCC(10)).tracking(0.6).foregroundColor(P.muted).frame(width: 44, alignment: .leading)
            GeometryReader { geo in
                let f = CGFloat(max(0, min(hi - lo, value - lo))) / CGFloat(max(1, hi - lo))
                ZStack(alignment: .leading) {   // the visible track sits in the middle of the taller touch area
                    RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0x202329)).frame(height: 14)
                    RoundedRectangle(cornerRadius: 5).fill(Color(hex: 0x7C838E)).frame(width: max(3, geo.size.width * f), height: 14)
                }
                .frame(maxHeight: .infinity, alignment: .center)
                .contentShape(Rectangle())   // the whole (tall) row is grabbable
                .gesture(DragGesture(minimumDistance: 1).updating($dragging) { _, s, _ in s = true }
                    .onChanged { g in
                        if startValue == nil { startValue = value }
                        let base = startValue ?? value
                        let delta = Int((g.translation.width / max(1, geo.size.width) * CGFloat(hi - lo)).rounded())   // RELATIVE: a 1-bar-width drag spans the full range; no jump to the finger
                        let v = max(lo, min(hi, base + delta))
                        if v != value { onChange(v, !dragging) }   // newStep on the first change of the drag
                    }
                    .onEnded { _ in startValue = nil })
            }
            .frame(height: 26)   // a tall, easy touch target
            Text("\(value)").font(heavyMonoCC(12)).foregroundColor(P.text).frame(width: 26, alignment: .trailing)
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
    // CC page v2 §2.3: `plain` drops the own tile + the up/down glyph, so the number sits inside the stepper's shared tile as "‹ CC n ›" — `width` sets its slot, `colour` its ink (on = #F2F4F7, off = #9097A1).
    var plain = false
    var width: CGFloat = 64
    var colour: Color = P.text
    @State private var start: Int? = nil
    @State private var burstOpen = false
    @GestureState private var gestureLive = false

    var body: some View {
        Group {
            if plain {
                Text("\(value)").font(heavyMonoCC(18)).monospacedDigit().foregroundColor(colour).frame(width: width, height: 30)
            } else {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .heavy)).foregroundColor(P.muted)
                    Text("\(value)").font(heavyMonoCC(16)).foregroundColor(P.text).frame(minWidth: 28)
                }
                .frame(width: width, height: 30)
                .background(RoundedRectangle(cornerRadius: 8).fill(P.slot))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(P.rule, lineWidth: 1))
            }
        }
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
    var dashed = false   // CC page v2 §3.1: the off-state line is dashed
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
            ctx.stroke(path, with: .color(lineColour ?? P.light), style: StrokeStyle(lineWidth: dashed ? 1.2 : (lineColour != nil ? 1.25 : (detailed ? 1.75 : 1.5)), lineCap: .round, lineJoin: .round, dash: dashed ? [3, 3] : []))
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
/// its own trace in the slot's DRIVER lane's colour. TAP a cell ⇒ toggle that slot on/off; LONG PRESS ⇒ its edit page (Paul 2026-11-15; was: tap opened the page). No on switch, no chevron (§4.7); the full on/off + edit is also on the page.
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
    let onToggle: (Int) -> Void   // CC tab (Paul 2026-11-15): a TAP on a cell toggles that slot on/off; a LONG PRESS opens the edit page (`onExpand`).

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
                        lineColour: dc.opacity(cc.on ? 0.85 : 0.3), areaColour: dc.opacity(cc.on ? 0.14 : 0.05), hideDots: true, faintDividers: true, bgRadius: 0)
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
        // the tap + hit shape MUST come before `.position` — `.position` fills the parent, so a gesture after it makes the hit area the whole row and every cell toggles the top-drawn slot (the wrong one).
        .contentShape(Rectangle())
        // CC tab (Paul 2026-11-15): a TAP toggles this slot on/off; a LONG PRESS (0.5 s, the riff-tab idiom) opens the edit page. VoiceOver can't long-press, so the edit is also an explicit "Edit" action.
        .onTapGesture { onToggle(k) }
        .onLongPressGesture(minimumDuration: 0.5) { onExpand(k) }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousCCBandAX(output: o, cc: cc.ccNumber, driverLane: (k < drivers.count ? drivers[k] : 0) + 1, on: cc.on))
        .accessibilityValue(cc.on ? "on" : "off")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: Text("Edit")) { onExpand(k) }
        .position(x: rect.midX, y: rect.midY)
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
    var outputMuted: Bool = false          // CC page v2 §2.4: the emitter tile shows a muted look when this slot's output is fully muted
    let onEdit: (Bool, @escaping (inout EmitterCCSet) -> Void) -> Void
    let onCollapse: () -> Void
    @State private var pickerOpen = false

    private var output: Int { slot / EmitterCCSet.slotsPerEmitter }
    private var slotIndex: Int { slot % EmitterCCSet.slotsPerEmitter }
    private var letter: String { euclideousOutputLetter(output) }
    private func laneColour(_ d: Int) -> Color { laneColours[max(0, min(laneColours.count - 1, d))] }
    private static let valueModes: [EmitterCCValueMode] = [.hits, .riff, .pingPong, .climb]
    /// CC page v2 §1: header · trace (or the lane picker in its place) · VALUE · a two-column grid of only the VISIBLE controls, each placed at its frame from `euclideousCCPageLayout`. The controls reflow (0.15 s) when the visible set changes (§4.6).
    var body: some View {
        let cc = ccs[slot]
        let L = euclideousCCPageLayout(box: bodySize)
        let visible = euclideousCCVisibleControls(mode: cc.valueMode, hold: cc.hold, ramp: cc.ramp)
        return ZStack(alignment: .topLeading) {
            place(header(cc), L.header)
            place(pickerOpen ? AnyView(pickerBody) : AnyView(traceArea(cc)), L.trace)
            place(valueRow(cc).opacity(cc.on ? 1 : 0.55), L.valueRow)          // §4: the VALUE row + grid draw at 55 % while the slot is off
            ForEach(Array(visible.enumerated()), id: \.element) { i, c in
                place(AnyView(controlCell(c, cc).opacity(cc.on ? 1 : 0.55)), L.gridCell(i))
            }
        }
        .frame(width: bodySize.width, height: bodySize.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: visible)
    }
    /// Place a fully-built leaf at its frame (gesture inside the leaf; `.position` moves the hit area with it).
    private func place<V: View>(_ v: V, _ f: CGRect) -> some View { v.frame(width: f.width, height: f.height).position(x: f.midX, y: f.midY) }
    /// §3: the trace, full width, no lane tag now (the driver is in the header). On = the driver lane's detailed trace; off = a dashed grey line only. Tapping it opens the lane picker (§3.2).
    @ViewBuilder private func traceArea(_ cc: EmitterCC) -> some View {
        let dc = laneColour(driverLane)
        CCTraceView(trace: trace, laneColours: laneColours, playhead: cc.on ? playhead : nil, detailed: cc.on,
                    lineColour: cc.on ? dc : Color(hex: 0x5C626C), areaColour: cc.on ? nil : .clear, hideDots: !cc.on, bgRadius: 8, dashed: !cc.on)
            .contentShape(Rectangle())
            .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { pickerOpen = true } }
            .accessibilityHidden(true)   // the driver tile in the header is the VoiceOver opener (§6)
    }
    /// §4.1: the VALUE row — four full-width segments.
    @ViewBuilder private func valueRow(_ cc: EmitterCC) -> some View {
        ccSeg(["HITS", "RIFF", "PING", "CLIMB"], selected: Self.valueModes.firstIndex(of: cc.valueMode) ?? 0, segH: 26, font: 11) { i in onEdit(true) { $0[slot].valueMode = Self.valueModes[i] } }
    }
    /// §4.2: one grid control — a slider (HIGH/LOW/HOLD/RAMP/PASSES) or a labelled two-segment control (TO/CURVE).
    @ViewBuilder private func controlCell(_ c: EuclideousCCControl, _ cc: EmitterCC) -> some View {
        switch c {
        case .high:   CCBarSlider(label: "HIGH", value: cc.high) { v, s in onEdit(s) { $0[slot].high = v } }
        case .low:    CCBarSlider(label: "LOW", value: cc.low) { v, s in onEdit(s) { $0[slot].low = v } }
        case .hold:   CCBarSlider(label: "HOLD", value: cc.hold, lo: 0, hi: 100) { v, s in onEdit(s) { $0[slot].hold = v } }
        case .ramp:   CCBarSlider(label: "RAMP", value: cc.effectiveRamp, lo: 0, hi: 100) { v, s in onEdit(s) { $0[slot].ramp = v } }   // the readout is the effective ramp; the stored value is kept
        case .passes: CCBarSlider(label: "PASSES", value: cc.passes, lo: 1, hi: EmitterCC.maxPasses) { v, s in onEdit(s) { $0[slot].passes = v } }
        case .to:     segCell("TO", ["REST", "NEXT"], cc.to == .rest ? 0 : 1) { i in onEdit(true) { $0[slot].to = i == 0 ? .rest : .next } }
        case .curve:  segCell("CURVE", ["LIN", "EXP"], cc.curve == .lin ? 0 : 1) { i in onEdit(true) { $0[slot].curve = i == 0 ? .lin : .exp } }
        }
    }
    /// §4.2: a labelled two-segment control (label like a slider's, then the segments 22 tall).
    @ViewBuilder private func segCell(_ label: String, _ options: [String], _ selected: Int, _ onPick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 6) {
            Text(label).font(heavyMonoCC(10)).tracking(0.6).foregroundColor(P.muted).frame(width: 44, alignment: .leading)
            ccSeg(options, selected: selected, segH: 22, font: 10, onPick: onPick)
        }
    }
    /// §4.1 colours: active #E8EBF0 fill / #111317 text; others #262930 / #9097A1. 3 pt between segments.
    @ViewBuilder private func ccSeg(_ options: [String], selected: Int, segH: CGFloat, font: CGFloat, onPick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 3) {
            ForEach(options.indices, id: \.self) { i in
                let on = i == selected
                Text(options[i]).font(heavyMonoCC(font)).tracking(0.6).foregroundColor(on ? Color(hex: 0x111317) : P.muted)
                    .frame(maxWidth: .infinity).frame(height: segH)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color(hex: 0xE8EBF0) : Color(hex: 0x262930)))
                    .contentShape(Rectangle()).onTapGesture { onPick(i) }
                    .accessibilityElement(children: .ignore).accessibilityLabel(options[i]).accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
    @ViewBuilder private func laneTab(_ d: Int, dc: Color) -> some View {
        Text("\(d + 1)").font(heavyMonoCC(EuclideousCCPickerMetrics.laneTabFontSize)).foregroundColor(P.ink)
            .frame(width: EuclideousCCPickerMetrics.laneTabW, height: EuclideousCCPickerMetrics.laneTabH)
            .background(RoundedRectangle(cornerRadius: EuclideousCCPickerMetrics.laneTabRadius).fill(dc))
    }
    /// §5.5 (rebuilt 2026-11-13): the four Euclid lanes drawn as the user already knows them — horizontal step strips — stacked full-width,
    /// filling the body. The current driver is full-strength with its colour wash + a thick lane-colour border + a filled lane tag; the
    /// others are dimmed with a thin border. Tap one ⇒ it drives this slot (one undo step); the header × closes the picker.
    private var pickerBody: some View {
        GeometryReader { geo in
            let rects = euclideousCCPickerRows(size: geo.size)
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
            laneStripCanvas(line: line, dc: dc, current: current, beat: beat)
            laneTab(lane, dc: dc).padding(EuclideousCCPickerMetrics.laneTabInset)
        }
        .frame(width: rect.width, height: rect.height)
        .clipShape(RoundedRectangle(cornerRadius: EuclideousCCPickerMetrics.cellRadius))
        .overlay(RoundedRectangle(cornerRadius: EuclideousCCPickerMetrics.cellRadius).strokeBorder(current ? dc : P.rule, lineWidth: current ? 3 : 1))
        // the tap MUST come before `.position` (see the rows' cell): otherwise every lane row's hit area is the whole picker and only lane 4 is selectable.
        .contentShape(Rectangle())
        .onTapGesture { onEdit(true) { $0[slot].driverLane = lane + 1 }; withAnimation(.easeInOut(duration: 0.12)) { pickerOpen = false } }
        .accessibilityElement(children: .ignore).accessibilityLabel("Lane \(lane + 1)").accessibilityAddTraits(current ? [.isButton, .isSelected] : [.isButton])
        .position(x: rect.midX, y: rect.midY)
    }
    /// The lane as the familiar horizontal Euclid step strip — the SAME pattern (`randomPictureRhythm`) and even cell geometry
    /// (`euclidEvenBoxGeometry`) the lane cards use: hits in the lane colour, rests dark, a playhead cell while running. Dimmed when not the current driver.
    private func laneStripCanvas(line: EuclidLine, dc: Color, current: Bool, beat: Double) -> some View {
        let dim = current ? 1.0 : 0.45
        let play = playing
        return Canvas { ctx, sz in
            let steps = max(2, min(16, line.steps))
            let offset = euclideousRandomDisplayedOffset(rotate: line.rotate, steps: steps)
            let pattern = randomPictureRhythm(line, steps: steps, hits: line.pulses, offset: offset)
            let leftInset = EuclideousCCPickerMetrics.laneTabW + EuclideousCCPickerMetrics.laneTabInset * 2
            let usableW = max(1, sz.width - leftInset - 10)
            let geo = euclidEvenBoxGeometry(n: steps, g: 4, usableWidth: usableW)
            let cellH = min(sz.height - 16, EuclideousCCPickerMetrics.stripMaxH)
            let y = (sz.height - cellH) / 2
            let ph = play ? euclideousRandomPicturePlayhead(beat: beat, stepBeats: line.rate?.beats ?? 0.5, steps: steps, dir: line.directionResolved) : -1
            for i in 0..<steps where i < geo.xs.count {
                let cell = CGRect(x: leftInset + geo.xs[i], y: y, width: geo.stepW, height: cellH)
                let fill = pattern[i] ? dc.opacity(dim) : Color(hex: 0x2C2F36).opacity(current ? 1 : 0.6)
                ctx.fill(RoundedRectangle(cornerRadius: 2).path(in: cell), with: .color(fill))
                if i == ph { ctx.fill(RoundedRectangle(cornerRadius: 2).path(in: cell), with: .color(Color(hex: 0xF2F4F7).opacity(0.22))) }
            }
        }
    }
    /// §2: back · power · CC stepper on the left; right-aligned ON [emitter] FROM [driver]. No close tile, no OFF pill, no token at the left (§2.5).
    @ViewBuilder private func header(_ cc: EmitterCC) -> some View {
        let dc = laneColour(driverLane)
        HStack(spacing: 6) {
            backButton
            powerButton(cc, dc: dc)
            ccStepper(cc)
            Spacer(minLength: 0)
            Text("ON").font(heavyMonoCC(9)).tracking(0.72).foregroundColor(P.muted)
            emitterTile
            Text("FROM").font(heavyMonoCC(9)).tracking(0.72).foregroundColor(P.muted)
            driverTile(dc: dc)
        }
        .frame(height: 30)
    }
    /// §2.1: a left chevron, no tile — back to the CC rows (or just closes the picker when it is open).
    private var backButton: some View {
        Path { p in p.move(to: CGPoint(x: 16, y: 7)); p.addLine(to: CGPoint(x: 8, y: 15)); p.addLine(to: CGPoint(x: 16, y: 23)) }
            .stroke(Color(hex: 0x9097A1), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            .frame(width: 26, height: 30)
            .contentShape(Rectangle().inset(by: -4))
            .onTapGesture { if pickerOpen { withAnimation(.easeInOut(duration: 0.12)) { pickerOpen = false } } else { onCollapse() } }
            .accessibilityElement(children: .ignore).accessibilityLabel("Back to CC").accessibilityAddTraits(.isButton)
    }
    /// §2.2: a power button — lit in the driver lane's colour when on, a grey outline when off. Toggles `on` (the same undo as the old OFF pill). No label.
    @ViewBuilder private func powerButton(_ cc: EmitterCC, dc: Color) -> some View {
        let on = cc.on
        EuclideousCCPowerIcon()
            .stroke(on ? dc : Color(hex: 0x5C626C), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            .frame(width: 16, height: 16)
            .frame(width: 34, height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(on ? dc.opacity(0.18) : Color.clear))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(on ? dc : Color(hex: 0x3A3E47), lineWidth: 1.5))
            .contentShape(Rectangle().inset(by: -4))
            .onTapGesture { onEdit(true) { $0[slot].on.toggle() } }
            .accessibilityElement(children: .ignore).accessibilityLabel("CC \(cc.ccNumber)").accessibilityValue(on ? "on" : "off").accessibilityAddTraits(.isButton).ringToggleTrait()
    }
    /// §2.3: ‹ CC n › in one tile — the number is draggable (plain, no own tile / glyph), #F2F4F7 on / #9097A1 off; ‹ › skip to the next free number (§1.4), hold repeats via the drag.
    @ViewBuilder private func ccStepper(_ cc: EmitterCC) -> some View {
        HStack(spacing: 2) {
            Text("\u{2039}").font(heavyMonoCC(14)).foregroundColor(P.muted).frame(width: 20, height: 30).contentShape(Rectangle()).onTapGesture { onEdit(true) { $0[slot].ccNumber = $0.nextCCNumber(from: $0[slot].ccNumber, output: output, slot: slotIndex, up: false) } }
            Text("CC").font(heavyMonoCC(9)).tracking(0.72).foregroundColor(P.muted)
            CCNumberSlider(value: cc.ccNumber, onChange: { v, newStep in onEdit(newStep) { s in var v2 = v; if (0..<EmitterCCSet.slotsPerEmitter).contains(where: { $0 != slotIndex && s[output: output, slot: $0].ccNumber == v }) { v2 = s.nextCCNumber(from: v, output: output, slot: slotIndex, up: true) }; s[slot].ccNumber = v2 } }, plain: true, width: 34, colour: cc.on ? P.text : P.muted)   // §1.4: a drag onto a taken number skips
            Text("\u{203A}").font(heavyMonoCC(14)).foregroundColor(P.muted).frame(width: 20, height: 30).contentShape(Rectangle()).onTapGesture { onEdit(true) { $0[slot].ccNumber = $0.nextCCNumber(from: $0[slot].ccNumber, output: output, slot: slotIndex, up: true) } }
        }
        .padding(.horizontal, 4).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x262930)))
        .accessibilityElement(children: .ignore).accessibilityLabel("Controller number").accessibilityValue("\(cc.ccNumber)")
        .accessibilityAdjustableAction { d in onEdit(true) { $0[slot].ccNumber = max(0, min(EmitterCC.maxCC, $0[slot].ccNumber + (d == .increment ? 1 : -1))) } }
    }
    /// §2.4: the emitter tile (display only — the output this slot sends on), the token at 22, muted look if the output is muted. No action.
    private var emitterTile: some View {
        EuclideousEmitterTokenView(size: .d22, letter: letter, state: euclideousEmitterTokenEmitterState(muted: outputMuted, activity: 0, anyRouted: true), lane: Color.clear)
            .frame(width: 22, height: 22)
            .padding(.horizontal, 6).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color(hex: 0x262930)))
            .accessibilityElement(children: .ignore).accessibilityLabel("Output \(letter)")
    }
    /// §2.4: the driver tile — a lane tab + a down chevron; tap opens the lane picker (tap again closes it). Lit in the lane colour while the picker is open.
    @ViewBuilder private func driverTile(dc: Color) -> some View {
        HStack(spacing: 5) {
            laneTab(driverLane, dc: dc)
            Path { p in p.move(to: CGPoint(x: 0, y: 0)); p.addLine(to: CGPoint(x: 4, y: 5)); p.addLine(to: CGPoint(x: 8, y: 0)) }
                .stroke(Color(hex: 0x9097A1), style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round)).frame(width: 8, height: 6)
        }
        .padding(.horizontal, 6).frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 8).fill(pickerOpen ? dc.opacity(0.18) : Color(hex: 0x262930)))
        .overlay(pickerOpen ? RoundedRectangle(cornerRadius: 8).strokeBorder(dc, lineWidth: 1.5) : nil)
        .contentShape(Rectangle().inset(by: -4))
        .onTapGesture { withAnimation(.easeInOut(duration: 0.12)) { pickerOpen.toggle() } }
        .accessibilityElement(children: .ignore).accessibilityLabel("From lane \(driverLane + 1)").accessibilityAddTraits(pickerOpen ? [.isButton, .isSelected] : [.isButton])
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
            // CC page v2 amendment 1 (2026-11-15): the MUTE slider is removed — a muted output parks each CC at its LOW. (The controls block is rebuilt in CC page v2 slice 4.)
            Spacer(minLength: 0)
        }
    }
}
