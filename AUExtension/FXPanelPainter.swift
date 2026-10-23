//  FXPanelPainter.swift
//  The FX tab of the bottom-right panel (ferry "FX tab: six fixed effect rows on the riff's steps", ratified 2026-10-18).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `LanesPanelPainter.swift`: every number — the layout, a cell's mark,
//  the bubble's text and place, what a touch means, the step tables — comes from the pure functions in Derivations.swift (`euclideousFX*`), so the
//  drawing, the touch and the tests can never disagree. This file paints what those return and routes the touches they interpret. The page owns the
//  data (the document's `EuclideousFX`, the selected row, the brushes) and the edits (one undo step per tap / double-tap pair / stroke / value drag /
//  lane toggle / stepper tap or drag); nothing here keeps state beyond the finger in flight and the bubble.

import SwiftUI

private extension Color {
    init(h: UInt32, a: Double = 1) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: a)
    }
}

/// §11.1's palette, named as the spec names it.
enum EuclideousFXPalette {
    static let ink = Color(h: 0x0D0F14), text = Color(h: 0xF2F4F7), muted = Color(h: 0xAAB0BA), caption = Color(h: 0x8A909A)
    static let dim = Color(h: 0x5C626C), chip = Color(h: 0x2A2D34), emptyCell = Color(h: 0x22252C), light = Color(h: 0xDFE3EA)
    static let hollowRing = Color(h: 0x4A4E57), bubbleBorder = Color(h: 0x3A3E47)
}
private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// One column's header (§11.2): the written rank's note name, or the dim en dash on a rest.
struct EuclideousFXHeaderLabel: Equatable { var text: String; var rest: Bool }

/// The static layer: band, headers, cells and their marks, the NOTE preview ring. No time in here — the flash is its own layer — so it only redraws when its
/// inputs change.
private struct EuclideousFXStaticLayer: View, Equatable {
    let layout: EuclideousFXLayout
    let fx: EuclideousFX
    let selectedRow: Int
    let headers: [EuclideousFXHeaderLabel]
    let previewColumn: Int?

    var body: some View {
        Canvas { ctx, _ in
            let P = EuclideousFXPalette.self
            // ── selected-row band (§11.4), behind the row ──
            ctx.fill(RoundedRectangle(cornerRadius: 8).path(in: layout.bandRect(row: selectedRow)), with: .color(Color.white.opacity(0.06)))
            // (the header — §11.2 — is real Text in `EuclideousFXPanel.header`, not Canvas, so VoiceOver can read it: §14.4 calls it static text)
            // ── cells (§11.5/§11.6) ──
            for r in 0..<6 {
                let rowDim = fx.lanes[r] & EuclideousFX.allLanes != 0
                for c in 0..<8 {
                    let rest = c < headers.count && headers[c].rest
                    let rect = layout.cellRect(row: r, col: c)
                    let shape = RoundedRectangle(cornerRadius: 5).path(in: rect)
                    let v = fx.cell(row: r, column: c)
                    var cc = ctx
                    cc.opacity = euclideousFXCellOpacity(restColumn: rest, rowHasLanes: rowDim)
                    cc.fill(shape, with: .color(v == nil ? P.emptyCell : P.light))
                    if let v { drawMark(&cc, euclideousFXMark(row: r, value: v, cellW: layout.cellW), in: rect) }
                    // §11.7: the cell the NOTE strip previews
                    if r == 4, selectedRow == 4, previewColumn == c {
                        cc.stroke(RoundedRectangle(cornerRadius: 4.25).path(in: rect.insetBy(dx: 0.75, dy: 0.75)), with: .color(P.ink), lineWidth: 1.5)
                    }
                }
            }
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
    }

    private func drawMark(_ ctx: inout GraphicsContext, _ mark: EuclideousFXMark, in rect: CGRect) {
        let ink = EuclideousFXPalette.ink
        let cx = rect.midX, cy = rect.midY
        switch mark {
        case .ticks(let n):
            let w: CGFloat = 2.5, h: CGFloat = 12, gap: CGFloat = 4
            let total = CGFloat(n) * w + CGFloat(n - 1) * gap
            for i in 0..<n {
                ctx.fill(RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: cx - total / 2 + CGFloat(i) * (w + gap), y: cy - h / 2, width: w, height: h)), with: .color(ink))
            }
        case .gate(let label, let barW, let fillW), .bar(let label, let barW, let fillW):
            // the number (9pt heavy), 3pt above a bar 3 tall: the pair is centred in the cell
            let textH: CGFloat = 11, group = textH + 3 + 3
            let top = cy - group / 2
            ctx.draw(ctx.resolve(Text(label).font(heavyMono(9)).foregroundColor(ink)), at: CGPoint(x: cx, y: top + textH / 2), anchor: .center)
            let bar = CGRect(x: cx - barW / 2, y: top + textH + 3, width: barW, height: 3)
            ctx.fill(RoundedRectangle(cornerRadius: 1.5).path(in: bar), with: .color(ink.opacity(0.18)))
            ctx.fill(RoundedRectangle(cornerRadius: 1.5).path(in: CGRect(x: bar.minX, y: bar.minY, width: fillW, height: 3)), with: .color(ink))
        case .tie(let arcW):
            // path M2 2 Q15 11 28 2 in a 30 × 10 box, 2pt round-capped stroke, scaled to the cell
            let s = arcW / 30
            var p = Path()
            let ox = cx - arcW / 2, oy = cy - 5 * s
            p.move(to: CGPoint(x: ox + 2 * s, y: oy + 2 * s))
            p.addQuadCurve(to: CGPoint(x: ox + 28 * s, y: oy + 2 * s), control: CGPoint(x: ox + 15 * s, y: oy + 11 * s))
            ctx.stroke(p, with: .color(ink), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        case .step(let label):
            ctx.draw(ctx.resolve(Text(label).font(heavyMono(11)).foregroundColor(ink)), at: CGPoint(x: cx, y: cy), anchor: .center)
        }
    }
}

/// The firing flash (§11.8): a cell that has a value and applied to a hit that struck keeps its fill and mark and gains a 2pt inner ring in the hit's lane colour
/// plus a 10pt glow, its opacity the PULSE flash f of the strike that fires it (velocity-scaled, ferry 2026-10-20 §8.1). Its own layer so only it animates.
private struct EuclideousFXFlashLayer: View {
    let layout: EuclideousFXLayout
    let accents: [Color]
    let playing: Bool
    let flashAt: (Date) -> [EuclideousFXFlash?]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !playing)) { tl in
            let flashes = playing ? flashAt(tl.date) : []   // `playing`: the page is playing or settling after a stop (PULSE §9.1)
            Canvas { ctx, _ in
                for (i, f) in flashes.enumerated() {
                    guard let f, f.intensity > 0.01 else { continue }
                    let r = i / 8, c = i % 8
                    let rect = layout.cellRect(row: r, col: c)
                    let lane = accents[f.lane % accents.count]
                    // the 2pt inner ring, with the 10pt glow (the lane colour at 45%) cast from it
                    ctx.drawLayer { layer in
                        layer.addFilter(.shadow(color: lane.opacity(0.45 * f.intensity), radius: 10))
                        layer.stroke(RoundedRectangle(cornerRadius: 4).path(in: rect.insetBy(dx: 1, dy: 1)), with: .color(lane.opacity(f.intensity)), lineWidth: 2)
                    }
                }
            }
            .frame(width: layout.width, height: layout.height)
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The whole FX tab content.
struct EuclideousFXPanel: View {
    let layout: EuclideousFXLayout
    let fx: EuclideousFX
    let selectedRow: Int
    let headers: [EuclideousFXHeaderLabel]
    /// VoiceOver's note name for each column (nil = a rest).
    let noteNames: [String?]
    let accents: [Color]
    /// LANE SOLO §6.5: lane i is solo-silenced — its dot on every rail and its button in the strip draw at 42 % (still live).
    let silenced: [Bool]
    let previewText: String
    let previewColumn: Int?
    let brushes: [Int]
    let playing: Bool
    let flashAt: (Date) -> [EuclideousFXFlash?]
    let onSelectRow: (Int) -> Void
    let onTouchBegan: (Int, Int) -> Void
    let onEvent: (EuclideousFXTouchEvent) -> Void
    let onTouchEnded: () -> Void
    let onToggleLane: (Int) -> Void
    let onStepper: (EuclideousFXStepper, Int, Bool) -> Void
    let onAdjust: (Int, Int, Bool) -> Void
    let onToggleCell: (Int, Int) -> Void

    @State private var touch: EuclideousFXTouch? = nil
    @State private var touchStart: CGPoint? = nil     // a touch whose start differs from the one in flight is a NEW touch (a cancelled gesture may never call onEnded)
    @State private var bubble: (row: Int, col: Int, value: Int)? = nil
    @State private var stepperDragStart: Int? = nil
    @State private var stepperDragEdited = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            EuclideousFXStaticLayer(layout: layout, fx: fx, selectedRow: selectedRow, headers: headers, previewColumn: previewColumn).equatable()
            EuclideousFXFlashLayer(layout: layout, accents: accents, playing: playing, flashAt: flashAt)
            header
            ForEach(0..<6, id: \.self) { r in rail(r) }
            strip
            if layout.showHintRow { hint }
            cellGesture
            accessibilityCells
            bubbleView
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    // ── header (§11.2): "RIFF" over the note-label column and each column's written rank by name ("–" on a rest). Static text, not focusable controls. ──
    private var header: some View {
        let P = EuclideousFXPalette.self
        return ZStack(alignment: .topLeading) {
            Text("RIFF").font(.system(size: 8, weight: .bold, design: .monospaced)).foregroundColor(P.dim).lineLimit(1)
                .frame(width: EuclideousFXLayout.labelW, height: EuclideousFXLayout.headerH, alignment: .trailing)
                .offset(x: 0, y: layout.headerTop)
            ForEach(0..<8, id: \.self) { c in
                let h = c < headers.count ? headers[c] : EuclideousFXHeaderLabel(text: "–", rest: true)
                Text(h.text).font(.system(size: 9, weight: .bold, design: .monospaced)).foregroundColor(h.rest ? P.dim : P.caption).lineLimit(1)
                    .frame(width: layout.cellW, height: EuclideousFXLayout.headerH, alignment: .center)
                    .offset(x: layout.colLeft(c), y: layout.headerTop)
            }
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // ── rails (§11.3): real buttons, so they keep their own taps (§12.10) ──
    private func rail(_ r: Int) -> some View {
        let row = EuclideousFXRow(rawValue: r) ?? .ratch
        let sel = r == selectedRow
        let mask = fx.lanes[r] & EuclideousFX.allLanes
        let P = EuclideousFXPalette.self
        let name = row.railName(ccNumber: Int(fx.ccNumber))
        return Button { onSelectRow(r) } label: {
            VStack(spacing: 4) {
                Text(name).font(heavyMono(9)).foregroundColor(sel ? P.ink : (mask == 0 ? P.dim : P.text)).lineLimit(1)
                HStack(spacing: 2) {
                    ForEach(0..<4, id: \.self) { lane in
                        let on = (mask >> UInt8(lane)) & 1 != 0
                        let c = accents[lane % accents.count]
                        ZStack {
                            if on {
                                Circle().fill(c)
                                if sel { Circle().stroke(Color(h: 0x0D0F14, a: 0.45), lineWidth: 0.75) }
                            } else {
                                Circle().stroke(sel ? Color(h: 0x0D0F14, a: 0.4) : P.hollowRing, lineWidth: 1)
                            }
                        }
                        .frame(width: 4, height: 4)
                        .opacity(lane < silenced.count && silenced[lane] ? EuclideousLaneDimStyle.opacity : 1)
                        .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: lane < silenced.count && silenced[lane])
                    }
                }
            }
            .frame(width: EuclideousFXLayout.labelW, height: layout.rowH)
            .background(RoundedRectangle(cornerRadius: 5).fill(sel ? P.light : P.chip))
            .opacity(mask == 0 ? 0.42 : 1)
        }
        .buttonStyle(.plain)
        .offset(x: 0, y: layout.rowTop(r))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousFXRailLabel(row: r, ccNumber: Int(fx.ccNumber), mask: mask, selected: sel))
        .accessibilityHint("Shows its lanes and settings")
        .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
    }

    // ── strip (§11.9) ──
    private var strip: some View {
        let P = EuclideousFXPalette.self
        let row = EuclideousFXRow(rawValue: selectedRow) ?? .ratch
        let mask = fx.lanes[selectedRow] & EuclideousFX.allLanes
        let buttonsEnd = layout.firstColX + 4 * 32 + 3 * 4
        let x0 = buttonsEnd + 16
        return ZStack(alignment: .topLeading) {
            Text("LANES").font(heavyMono(8)).tracking(0.32).foregroundColor(P.caption).lineLimit(1)
                .frame(width: EuclideousFXLayout.labelW, height: EuclideousFXLayout.stripH, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { lane in
                    let on = (mask >> UInt8(lane)) & 1 != 0
                    let c = accents[lane % accents.count]
                    Button { onToggleLane(lane) } label: {
                        Text("\(lane + 1)").font(heavyMono(10)).foregroundColor(on ? P.text : P.muted)
                            .frame(width: 32, height: EuclideousFXLayout.stripH)
                            .background(RoundedRectangle(cornerRadius: 6).fill(on ? c.opacity(0.2) : P.chip))
                            .overlay(RoundedRectangle(cornerRadius: 6).inset(by: 0.5).stroke(on ? c : Color.clear, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                    .opacity(lane < silenced.count && silenced[lane] ? EuclideousLaneDimStyle.opacity : 1)
                    .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: lane < silenced.count && silenced[lane])
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(euclideousFXLaneButtonLabel(lane: lane, on: on))
                    .accessibilityAddTraits(on ? [.isButton, .isSelected] : .isButton)
                    .ringToggleTrait()
                }
            }
            .offset(x: layout.firstColX)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(euclideousFXLaneGroupLabel(row: selectedRow, ccNumber: Int(fx.ccNumber)))
            Group {
                if let d = row.stripDescription {
                    Text(d).font(heavyMono(8)).tracking(0.32).foregroundColor(P.caption).lineLimit(1).truncationMode(.tail)
                        .frame(width: max(0, layout.width - x0), height: EuclideousFXLayout.stripH, alignment: .leading)
                } else if row == .note {
                    HStack(spacing: 4) {
                        stepper(.passes)
                        Text(previewText).font(heavyMono(8)).tracking(0.32).foregroundColor(P.muted).lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(width: max(0, layout.width - x0), height: EuclideousFXLayout.stripH, alignment: .leading)
                } else {
                    HStack(spacing: 4) { stepper(.ccNumber); stepper(.base) }
                        .frame(width: max(0, layout.width - x0), height: EuclideousFXLayout.stripH, alignment: .leading)
                }
            }
            .offset(x: x0)
        }
        .frame(width: layout.width, height: EuclideousFXLayout.stripH, alignment: .topLeading)
    }

    /// A stepper (§11.9/§12.7): 24 tall, chip fill, radius 6; `‹` and `›` are 20 × 24; between them the key and the value, baseline-aligned. The chevrons never
    /// wrap — at an end the chevron draws at 40% and is disabled. Dragging the value changes it, a double-tap on it resets it.
    private func stepper(_ s: EuclideousFXStepper) -> some View {
        let P = EuclideousFXPalette.self
        let value = euclideousFXStepperValue(s, fx: fx)
        let canDown = euclideousFXStepperStep(s, current: value, up: false) != nil
        let canUp = euclideousFXStepperStep(s, current: value, up: true) != nil
        func chevron(_ glyph: String, up: Bool, enabled: Bool) -> some View {
            Button { if let n = euclideousFXStepperStep(s, current: value, up: up) { onStepper(s, n, true) } } label: {
                Text(glyph).font(.system(size: 12, weight: .medium)).foregroundColor(P.caption)
                    .frame(width: 20, height: EuclideousFXLayout.stripH)
            }
            .buttonStyle(.plain).disabled(!enabled).opacity(enabled ? 1 : 0.4)
            .accessibilityHidden(true)
        }
        return HStack(spacing: 0) {
            chevron("‹", up: false, enabled: canDown)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(euclideousFXStepperKey(s)).font(heavyMono(8)).foregroundColor(P.caption).lineLimit(1).fixedSize()
                Text(euclideousFXStepperValueText(s, value: value)).font(heavyMono(10)).foregroundColor(P.text).lineLimit(1).fixedSize()
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { onStepper(s, euclideousFXStepperDefault(s), true) }
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { v in
                        if stepperDragStart == nil { stepperDragStart = value; stepperDragEdited = false }
                        let n = euclideousFXStepperDrag(s, start: stepperDragStart ?? value, travelUp: -v.translation.height)
                        if n != euclideousFXStepperValue(s, fx: fx) { onStepper(s, n, !stepperDragEdited); stepperDragEdited = true }
                    }
                    .onEnded { _ in stepperDragStart = nil; stepperDragEdited = false }
            )
            chevron("›", up: true, enabled: canUp)
        }
        .frame(width: euclideousFXStepperWidth(s), height: EuclideousFXLayout.stripH)
        .background(RoundedRectangle(cornerRadius: 6).fill(P.chip))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousFXStepperSpoken(s, value: value))
        .accessibilityAdjustableAction { dir in
            let up = dir == .increment
            if let n = euclideousFXStepperStep(s, current: value, up: up) { onStepper(s, n, true) }
        }
    }

    // ── the hint row (§11.10) ──
    private var hint: some View {
        Text(euclideousFXHintText).font(heavyMono(8)).tracking(0.48).foregroundColor(EuclideousFXPalette.muted).lineLimit(1).truncationMode(.tail)
            .frame(width: layout.width, height: EuclideousFXLayout.hintH, alignment: .leading)
            .offset(x: 0, y: layout.hintTop)
    }

    // ── the cells' touch (§12.2–§12.4): one DragGesture over the CELLS only — the rails, lane buttons and steppers sit outside its hit area and keep their taps (§12.10) ──
    private var cellGesture: some View {
        let area = CGRect(x: layout.firstColX - 2, y: layout.rowTop(0) - 2, width: layout.colLeft(7) + layout.cellW + 2 - (layout.firstColX - 2),
                          height: layout.rowTop(5) + layout.rowH + 2 - (layout.rowTop(0) - 2))
        return Color.clear
            .frame(width: layout.width, height: layout.height)
            .contentShape(Path(area))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if touchStart != v.startLocation {
                            touchStart = v.startLocation; touch = nil; bubble = nil
                            if case .cell(let r, let c)? = euclideousFXHit(x: v.startLocation.x, y: v.startLocation.y, layout: layout) {
                                let cur = fx.cell(row: r, column: c)
                                touch = EuclideousFXTouch(point: v.startLocation, row: r, col: c, cellValue: cur, brush: brushes[r])
                                onTouchBegan(r, c)
                            }
                        }
                        guard var t = touch else { return }
                        let events = t.moved(to: v.location, layout: layout)
                        touch = t
                        for e in events { onEvent(e) }
                        if let dv = t.draggedValue { bubble = (t.row, t.startCol, dv) } else { bubble = nil }
                    }
                    .onEnded { _ in
                        if let t = touch { for e in t.ended() { onEvent(e) } }
                        touch = nil; touchStart = nil; bubble = nil
                        onTouchEnded()
                    }
            )
    }

    // ── VoiceOver (§14.2): every cell is a real element with the spec's words; the gesture layer above does the touching, so these carry no hit area ──
    @ViewBuilder private var accessibilityCells: some View {
        ForEach(0..<6, id: \.self) { r in
            ForEach(0..<8, id: \.self) { c in
                let v = fx.cell(row: r, column: c)
                let rect = layout.cellRect(row: r, col: c)
                let base = Color.clear
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(euclideousFXCellLabel(row: r, ccNumber: Int(fx.ccNumber), column: c, noteName: c < noteNames.count ? noteNames[c] : nil, value: v))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Toggle") { onToggleCell(r, c) }
                    .accessibilityAction { onToggleCell(r, c) }
                // §14.2: every row but TIE is adjustable (TIE has no value to step)
                if r == 2 { base } else { base.accessibilityAdjustableAction { dir in onAdjust(r, c, dir == .increment) } }
            }
        }
    }

    // ── the value bubble (§11.11): only during a value drag, never hit-testable ──
    @ViewBuilder private var bubbleView: some View {
        if let b = bubble {
            let text = euclideousFXBubbleText(row: b.row, value: b.value, ccNumber: Int(fx.ccNumber))
            let g = euclideousFXBubble(text: text, cell: layout.cellRect(row: b.row, col: b.col), bounds: layout.panelBounds)
            let P = EuclideousFXPalette.self
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6).fill(P.emptyCell)
                    .frame(width: g.rect.width, height: g.rect.height)
                    .shadow(color: Color.black.opacity(0.45), radius: 12, x: 0, y: 4)
                    .overlay(RoundedRectangle(cornerRadius: 6).inset(by: 0.5).stroke(P.bubbleBorder, lineWidth: 1))
                    .offset(x: g.rect.minX, y: g.rect.minY)
                // the notch: a 9pt square turned 45°, half of it below the bubble, the 1pt border on its two lower edges only
                let half: CGFloat = 9 * 0.7071
                Path { p in
                    p.move(to: CGPoint(x: g.notchX - half, y: g.rect.maxY)); p.addLine(to: CGPoint(x: g.notchX, y: g.rect.maxY + half))
                    p.addLine(to: CGPoint(x: g.notchX + half, y: g.rect.maxY)); p.closeSubpath()
                }.fill(P.emptyCell)
                Path { p in
                    p.move(to: CGPoint(x: g.notchX - half, y: g.rect.maxY)); p.addLine(to: CGPoint(x: g.notchX, y: g.rect.maxY + half))
                    p.addLine(to: CGPoint(x: g.notchX + half, y: g.rect.maxY))
                }.stroke(P.bubbleBorder, lineWidth: 1)
                Text(text).font(heavyMono(11)).foregroundColor(P.text).lineLimit(1).fixedSize()
                    .frame(width: g.rect.width, height: g.rect.height)
                    .offset(x: g.rect.minX, y: g.rect.minY)
            }
            .frame(width: layout.width, height: layout.height, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}
