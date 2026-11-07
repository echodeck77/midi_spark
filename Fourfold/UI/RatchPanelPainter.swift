//  RatchPanelPainter.swift
//  The RATCH tab of the bottom-right panel (ferry "RATCH tab: a Euclid ratchet per emitter A–D", ratified 2026-10-28).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `FXPanelPainter.swift`: every number — the layout, the strip's marks, the cells' text and bar, what a drag means, the VoiceOver words — comes from the pure
//  functions in `EmitterRatchetUI.swift` / Derivations.swift, so the drawing, the touch and the tests cannot disagree. This file paints what those return and routes the touches. The page owns the data (the document's
//  `EmitterRatchetSet`) and the edits (one undo step per toggle tap, value drag, double-tap reset and VoiceOver swipe); nothing here keeps state beyond the finger in flight.
//
//  The emitter-circle view the ferry says to reuse (`outCircle`, the lane cards' output circle) was deleted with the nine ports (2026-10-27, commit e054469); `EmitterRatchetDisc` is that look — the 28 pt disc, the 2 pt ring, the
//  11 pt heavy letter, the PULSE-timed flare — rebuilt as one small view from the deleted code and the ferry's numbers.

import SwiftUI

enum EmitterRatchetPalette {
    static let card = Color(hex: 0x1B1D23), cardEdge = Color(hex: 0x23262D), slot = Color(hex: 0x20232A), current = Color(hex: 0x2A2D34)
    static let disc = Color(hex: 0x2A2D34), restDot = Color(hex: 0x3A3E47), offRing = Color(hex: 0x3A3E47), rule = Color(hex: 0x262930)
    static let light = Color(hex: 0xDFE3EA), text = Color(hex: 0xF2F4F7), muted = Color(hex: 0x8A909A), ink = Color(hex: 0x0D0F14), pressedLabel = Color(hex: 0x2A2D34)
    // STEP-COUNT CLARITY (2026-11-03, device-owed): the "too gray" slots were #20232A, barely above the #1B1D23 card. The active steps now read as countable cells — a brighter two-tone beat shading (groups of four, A / B),
    // a brighter still current step, a clearer rest mark, and a 1 pt baseline under exactly the active length so you can see at a glance how many steps the pattern has.
    static let slotA = Color(hex: 0x31353F), slotB = Color(hex: 0x272B33), slotCurrent = Color(hex: 0x4A5262), restMark = Color(hex: 0x5B616D), baseline = Color(hex: 0x474D59)
}
private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

// MARK: - the toggle's disc (§4.3, §5.1–§5.3)

/// EMITTER TOKEN ferry (2026-11-07) §6.1: the RATCH toggle IS the token at 28 — ratchet ON → live, OFF → unused, its RATCHED flare (`f`) → playing (the token's playing look reproduces the old lane40 glow / lane20 wash / lane100 ring+1
/// this view used to draw by hand), output muted → the muted look whatever the ratchet state. The tap (at the call site) still toggles the ratchet. The old by-hand drawing is replaced by the shared token; `discSize` is still 28.
struct EmitterRatchetDisc: View {
    let letter: String
    let on: Bool
    let accent: Color
    let f: Double
    var outputMuted: Bool = false
    var body: some View {
        EuclideousEmitterTokenView(size: .d28, letter: letter,
                                   state: euclideousEmitterTokenEmitterState(muted: outputMuted, activity: f, anyRouted: on),
                                   lane: accent)
    }
}

// MARK: - the strip (§4.5, §5.3, §5.4)

/// The static layer of one strip: the 16 slots (those past STEPS draw nothing), the current slot's lighter fill, and each slot's bars (a hit) or dot (a rest). No time in here — the flare is its own layer.
private struct EmitterRatchetStripBase: View, Equatable {
    let slots: [CGRect]            // strip-local
    let r: EmitterRatchet
    let mask: UInt16
    let current: Int               // −1 = none
    var body: some View {
        Canvas { ctx, _ in
            typealias P = EmitterRatchetPalette
            typealias M = EmitterRatchetMetrics
            let last = min(slots.count, M.slotCount, max(0, r.steps)) - 1       // STEP-COUNT CLARITY: the index of the last active step
            guard last >= 0 else { return }
            // the baseline under exactly the active steps — a 1 pt ruler showing the pattern's length at a glance (the "too gray" fix: you can see how many steps there are even before reading the number)
            let base = CGRect(x: slots[0].minX, y: slots[0].maxY - 1, width: slots[last].maxX - slots[0].minX, height: 1)
            ctx.fill(RoundedRectangle(cornerRadius: 0.5).path(in: base), with: .color(P.baseline))
            // RATCH EXPAND §4.4: the bars reflect the STRIKES mode — FIX draws `strikes`, RANGE draws MAX with the MIN-onward faint, HIT draws each slot's own count (by its pre-OFFSET ordinal)
            let maskNoOffset = emitterRatchetPatternMask(steps: r.steps, hits: r.hits, offset: 0)
            let baseAlpha = emitterRatchetBarAlpha(chance: r.chance)
            for i in 0...last {
                let rect = slots[i]
                // beat shading in groups of four (A, B, A, B) so the steps are countable cells, not one gray smear; the current step is brighter still
                let tone = i == current ? P.slotCurrent : ((i / 4) % 2 == 0 ? P.slotA : P.slotB)
                ctx.fill(RoundedRectangle(cornerRadius: M.slotRadius).path(in: rect), with: .color(tone))
                if (mask >> UInt16(i)) & 1 != 0 {
                    let ord = emitterRatchetHitOrdinal(index: i, steps: r.steps, offset: r.offset, patternMaskNoOffset: maskNoOffset)
                    let bars = emitterRatchetStripBars(r, ordinal: ord)
                    for (k, b) in emitterRatchetBarRects(in: rect, strikes: bars.count).enumerated() {
                        ctx.fill(RoundedRectangle(cornerRadius: M.barRadius).path(in: b), with: .color(P.light.opacity(baseAlpha * (k >= bars.faintFrom ? 0.3 : 1))))   // §4.4: RANGE's MIN-onward bars read faint
                    }
                } else {
                    // a clearer rest mark than the old 2 × 2 #3A3E47 dot: a 3 pt dot in #5B616D, centred (the pure `emitterRatchetRestDot` stays 2 × 2 — test-pinned — so draw it here)
                    let d: CGFloat = 3
                    ctx.fill(Path(ellipseIn: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)), with: .color(P.restMark))
                }
            }
        }
    }
}
/// The flare layer: the current slot's bars again in the striking lane's colour — lane100 on a RATCHED hit, lane100 at 35 % on a MISSED one — fading on the PULSE flash timing.
private struct EmitterRatchetStripFlare: View {
    let slots: [CGRect]
    let r: EmitterRatchet
    let mask: UInt16
    let current: Int
    let flare: EmitterRatchetFlare?
    let accent: Color
    var body: some View {
        Canvas { ctx, _ in
            guard let fl = flare, current >= 0, current < slots.count, current < r.steps, (mask >> UInt16(current)) & 1 != 0 else { return }
            let alpha = fl.ratcheted ? fl.f : 0.35 * fl.f
            // RATCH EXPAND §4.4: flash the same bar count the base drew for this slot (RANGE = MAX, HIT = this slot's count)
            let maskNoOffset = emitterRatchetPatternMask(steps: r.steps, hits: r.hits, offset: 0)
            let ord = emitterRatchetHitOrdinal(index: current, steps: r.steps, offset: r.offset, patternMaskNoOffset: maskNoOffset)
            for b in emitterRatchetBarRects(in: slots[current], strikes: emitterRatchetStripBars(r, ordinal: ord).count) {
                ctx.fill(RoundedRectangle(cornerRadius: EmitterRatchetMetrics.barRadius).path(in: b), with: .color(accent.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - one value cell (§4.6, §5.5, §6.2)

/// One of the six readout cells: a label, the value, a bar showing the value's share of its range. Dragging up raises the value and down lowers it (starting once the touch has moved 6 pt); a double tap resets it; a single tap does
/// nothing. While a finger is down the cell fills #DFE3EA and draws in ink.
private struct EmitterRatchetCell: View {
    let output: Int
    let field: EmitterRatchetField
    let r: EmitterRatchet
    let size: CGSize
    let leadingRule: Bool
    let onEdit: (Bool, @escaping (inout EmitterRatchetSet) -> Void) -> Void
    let onDragEnd: () -> Void                                     // the page drops the drag's undo step when it ended where it began
    @State private var pressed = false
    @State private var dragStart: EmitterRatchet? = nil
    @State private var dragEdited = false
    @GestureState private var gestureLive = false            // false again when the system CANCELS the touch (a call, a Control Center swipe): `onEnded` never runs then, so this is what closes the drag (as on the card backs' pads)

    private func finishDrag() {
        let edited = dragEdited
        pressed = false; dragStart = nil; dragEdited = false
        if edited { onDragEnd() }
    }

    var body: some View {
        typealias P = EmitterRatchetPalette
        typealias M = EmitterRatchetMetrics
        let label = Text(field.label).font(heavyMono(7)).tracking(7 * 0.06).foregroundColor(pressed ? P.pressedLabel : P.muted)
        let value = Text(emitterRatchetValueText(field, r)).font(heavyMono(12)).monospacedDigit().foregroundColor(pressed ? P.ink : P.text)   // STACKED (2026-11-03): a bigger number now that it has its own line
        let trackW = max(0, size.width - 2 * M.progressInset)
        let fillW = trackW * CGFloat(emitterRatchetBarShare(field, r))
        let i = output, f = field
        return ZStack(alignment: .topLeading) {
            if pressed { RoundedRectangle(cornerRadius: M.cellPressedRadius).fill(P.light) }
            if leadingRule && !pressed { Rectangle().fill(P.rule).frame(width: 1, height: size.height) }
            // STACKED (2026-11-03): label over value, each on its own full-width line — so six cells fit and the number reads big. The LABEL truncates on a narrow cell, never the value ("RESTART" → "RESTA…", never "FRE…"; §4.9: truncate, never shrink).
            VStack(spacing: 0) {
                label.lineLimit(1)
                value.lineLimit(1).fixedSize()
            }
                .frame(width: size.width, alignment: .center)
                .padding(.top, 2)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: M.progressHeight / 2).fill(pressed ? P.ink.opacity(0.18) : P.rule).frame(width: trackW, height: M.progressHeight)
                RoundedRectangle(cornerRadius: M.progressHeight / 2).fill(pressed ? P.ink : P.muted).frame(width: fillW, height: M.progressHeight)
            }
            .padding(.leading, M.progressInset)
            .padding(.top, size.height - M.progressBottom - M.progressHeight)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit(true) { $0[i] = f.reset(in: $0[i]) } }          // §6.2: a double tap resets the cell (HITS and OFFSET clamped by STEPS)
        .gesture(
            DragGesture(minimumDistance: emitterRatchetDragActivation)
                .updating($gestureLive) { _, live, _ in live = true }
                .onChanged { v in
                    pressed = true
                    if dragStart == nil { dragStart = r; dragEdited = false }
                    // compare the WHOLE ratchet, not just this field's value: STRIKES is a MASTER drag (§7.5) that in RANGE moves MIN and MAX together, which `f.value(of:)` (= strikes) would not see
                    let target = emitterRatchetDragValue(f, start: dragStart ?? r, travelUp: -v.translation.height).normalized()
                    if target != r { onEdit(!dragEdited) { $0[i] = target }; dragEdited = true }   // one undo step per drag
                }
                .onEnded { _ in finishDrag() }
        )
        .onChange(of: gestureLive) { live in
            if !live { finishDrag() }   // a cancelled touch: no stale fill, no stale start value, and the next drag is its own undo step
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emitterRatchetCellLabel(output: output, field, r))
        .accessibilityAdjustableAction { dir in
            let delta = dir == .increment ? f.step : -f.step
            onEdit(true) { $0[i] = f.setting(f.value(of: $0[i]) + delta, in: $0[i]) }    // §8.4: each swipe changes the value by one step (CHANCE 5), one undo step
        }
        .accessibilityAction { onEdit(true) { $0[i] = f.reset(in: $0[i]) } }   // §8.4 "Double-tap resets": a VoiceOver double-tap ACTIVATES the element (it never fires a count-2 tap gesture), so the default action is the reset
    }
}

// MARK: - the config button (RATCH EXPAND §4)

/// The collapsed card's config button: a sliders glyph in a 44-wide full-height target on the card's right edge. Tapping it expands that one emitter across the whole panel. OPEN: the plate fills #DFE3EA and the glyph inks dark; CLOSED: a hairline plate, a muted glyph.
struct EmitterRatchetConfigButton: View {
    let output: Int
    let open: Bool
    let onTap: () -> Void
    var body: some View {
        typealias P = EmitterRatchetPalette
        return ZStack {
            RoundedRectangle(cornerRadius: 8).fill(open ? P.light : P.slot)
            RoundedRectangle(cornerRadius: 8).strokeBorder(open ? Color.clear : P.offRing, lineWidth: 1)
            Image(systemName: "slider.horizontal.3").font(.system(size: 16, weight: .semibold))
                .foregroundColor(open ? P.ink : P.muted)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emitterRatchetConfigLabel(output: output))
        .accessibilityValue(emitterRatchetConfigValue(open: open))
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - the tab

/// The RATCH tab: four cards A–D (toggle · strip · four cells · config button), laid out by `emitterRatchetLayout`. `playing` keeps the flare layers animating (and for the 1.5 s after a stop).
struct EuclideousRatchetPanel: View {
    let layout: EmitterRatchetLayout
    let ratchets: EmitterRatchetSet
    let accents: [Color]
    /// EMITTER TOKEN §6.1: is output A–D muted (its MUTE-tab gate has any cell cleared) — the toggle shows the muted look.
    var outputMuted: [Bool] = [false, false, false, false]
    let counts: String?                          // "hits" / "steps" in a dev build (FX COUNTS), nil in release — read by the strip's VoiceOver label
    let playing: Bool
    let pulseScale: Double
    let strikes: () -> [[EuclideousPulseStrike]] // the PULSE feed's strikes per lane
    @ObservedObject var live: EmitterRatchetLive
    let onEdit: (Bool, @escaping (inout EmitterRatchetSet) -> Void) -> Void
    let onDragEnd: () -> Void
    var expandedOutput: Int? = nil                 // RATCH EXPAND §4: which emitter's config button reads OPEN (nil = all collapsed)
    var onConfig: (Int) -> Void = { _ in }         // tap a config button → expand that emitter (view-state only, never an undo step; §7.8)

    var body: some View {
        typealias P = EmitterRatchetPalette
        typealias M = EmitterRatchetMetrics
        let innerH = max(0, layout.cardHeight - 2 * M.padVertical)
        let stripW = layout.strip.width
        return VStack(alignment: .leading, spacing: M.gap) {
            ForEach(0..<4, id: \.self) { x in card(x, innerH: innerH, stripW: stripW) }
        }
        .padding(.top, M.top)
    }

    private func card(_ x: Int, innerH: CGFloat, stripW: CGFloat) -> some View {
        typealias P = EmitterRatchetPalette
        typealias M = EmitterRatchetMetrics
        let r = ratchets[x]
        let mask = emitterRatchetPatternMask(steps: r.steps, hits: r.hits, offset: r.offset)
        let slotsLocal = layout.slots.map { CGRect(x: $0.minX - layout.strip.minX, y: 0, width: $0.width, height: $0.height) }
        let current = live.index(x) ?? -1
        let flareSlot = live.flareIndex(x) ?? current       // the flare outlives a stop (its 1.5 s afterglow) though the highlighted slot clears
        let accentOf: (Int) -> Color = { accents[max(0, min(accents.count - 1, $0))] }
        return HStack(alignment: .top, spacing: 0) {
            // the toggle target: 44 × the card's inner height, the disc centred in it (§4.3)
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playing)) { tl in
                let now = tl.date.timeIntervalSinceReferenceDate
                let fl = emitterRatchetFlare(output: x, strikes: strikes(), now: now, scale: pulseScale)
                let ratcheted = fl?.ratcheted == true ? fl : nil
                EmitterRatchetDisc(letter: emitterRatchetLetters[x], on: r.on, accent: ratcheted.map { accentOf($0.lane) } ?? .clear, f: ratcheted?.f ?? 0, outputMuted: x < outputMuted.count && outputMuted[x])
            }
            .frame(width: M.toggleWidth, height: innerH)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(true) { $0[x].on.toggle() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(emitterRatchetToggleLabel(output: x))
            .accessibilityValue(emitterRatchetToggleValue(on: r.on) + ((x < outputMuted.count && outputMuted[x]) ? ", output muted" : ""))   // EMITTER TOKEN §8.2
            .accessibilityAddTraits(.isButton)
            .ringToggleTrait()
            Spacer().frame(width: M.toggleGap)
            // the right column (§4.4): the strip, 4 below it the readout row; 42 % while the emitter is off but still live (§5.2)
            VStack(spacing: M.stripGap) {
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 0).fill(Color.clear)
                    EmitterRatchetStripBase(slots: slotsLocal, r: r, mask: mask, current: current).equatable()
                    TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playing)) { tl in
                        let fl = emitterRatchetFlare(output: x, strikes: strikes(), now: tl.date.timeIntervalSinceReferenceDate, scale: pulseScale)
                        EmitterRatchetStripFlare(slots: slotsLocal, r: r, mask: mask, current: flareSlot, flare: fl, accent: fl.map { accentOf($0.lane) } ?? .clear)
                    }
                }
                .frame(width: stripW, height: M.stripHeight, alignment: .topLeading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(emitterRatchetStripLabel(output: x, r, counts: counts))
                HStack(spacing: 0) {
                    // RATCH EXPAND §4: the collapsed row shows STEPS · HITS · OFFSET · STRIKES (CHANCE / RESTART moved to the expanded view); STRIKES reads mode-aware ("×3" / "×2–4" / "×VAR") and is a MASTER drag
                    ForEach(Array(emitterRatchetCollapsedFields.enumerated()), id: \.offset) { c, field in
                        EmitterRatchetCell(output: x, field: field, r: r, size: layout.cells[min(c, layout.cells.count - 1)].size, leadingRule: c > 0, onEdit: onEdit, onDragEnd: onDragEnd)
                    }
                }
            }
            .frame(width: stripW)
            .opacity(r.on ? 1 : 0.42)
            // RATCH EXPAND §4: the config button on the card's right edge (full strength even when the emitter is off — it opens the editor, it is not part of the emitter's own state)
            if layout.config != nil {
                Spacer().frame(width: M.toggleGap)
                EmitterRatchetConfigButton(output: x, open: expandedOutput == x, onTap: { onConfig(x) })
                    .frame(width: M.configWidth, height: innerH)
            }
        }
        .padding(EdgeInsets(top: M.padVertical, leading: 0, bottom: M.padVertical, trailing: M.padRight))
        .frame(width: layout.cards.first?.width ?? 0, height: layout.cardHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: M.cardRadius).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: M.cardRadius).strokeBorder(P.cardEdge, lineWidth: 1))
    }
}

// MARK: - a reusable segmented control (RATCH EXPAND §5)

/// A row of equal pill buttons; the selected one fills #DFE3EA and inks dark. Used for STRIKES mode (FIX · RANGE · HIT) and GAP (FIT · 1/8 · 1/16 · 1/16T · 1/32).
struct EmitterRatchetSegmented: View {
    let options: [String]
    let selected: Int
    let height: CGFloat
    let groupLabel: String            // VoiceOver: the control's name ("Strikes mode" / "Strike gap")
    let onSelect: (Int) -> Void
    var body: some View {
        typealias P = EmitterRatchetPalette
        return HStack(spacing: 2) {
            ForEach(options.indices, id: \.self) { i in
                let sel = i == selected
                Text(options[i]).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(sel ? P.ink : P.light)
                    .lineLimit(1).minimumScaleFactor(0.65)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(RoundedRectangle(cornerRadius: 6).fill(sel ? P.light : P.slot))
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(i) }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(groupLabel) \(options[i])")
                    .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(height: height)
    }
}

// MARK: - a +/- stepper for RANGE's MIN / MAX (RATCH EXPAND §5)

private struct EmitterRatchetMiniStepper: View {
    let label: String
    let value: Int
    let a11y: String
    let onStep: (Int) -> Void
    var body: some View {
        typealias P = EmitterRatchetPalette
        return VStack(spacing: 3) {
            Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced)).tracking(7 * 0.06).foregroundColor(P.muted).lineLimit(1)
            HStack(spacing: 6) {
                glyph("minus") { onStep(-1) }
                Text("\(value)").font(.system(size: 14, weight: .heavy, design: .monospaced)).monospacedDigit().foregroundColor(P.text).frame(minWidth: 16)
                glyph("plus") { onStep(1) }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
        .accessibilityValue("\(value)")
        .accessibilityAdjustableAction { d in onStep(d == .increment ? 1 : -1) }
    }
    private func glyph(_ name: String, _ tap: @escaping () -> Void) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .bold)).foregroundColor(EmitterRatchetPalette.light)
            .frame(width: 26, height: 26).background(RoundedRectangle(cornerRadius: 6).fill(EmitterRatchetPalette.slot))
            .contentShape(Rectangle()).onTapGesture(perform: tap)
    }
}

// MARK: - the expanded view (RATCH EXPAND §5)

/// One emitter fills the whole panel: an A–D disc column on the left to switch which emitter is open, then the editor — a big strip, the value row (STEPS · HITS · OFFSET · CHANCE · RESTART + a collapse button), the STRIKES block
/// (FIX · RANGE · HIT and its count / MIN·MAX / per-hit editing) and the GAP block. CUT · SPILL is hidden (§0.2 — SPILL falls back to CUT this build). Every data edit is one undo step through `onEdit`; opening / switching / collapsing is view-state only (§7.8).
struct EmitterRatchetExpandedView: View {
    let output: Int
    let bodySize: CGSize
    let portrait: Bool
    let ratchets: EmitterRatchetSet
    let accents: [Color]
    var outputMuted: [Bool] = [false, false, false, false]   // EMITTER TOKEN §6.1
    let counts: String?
    let playing: Bool
    let pulseScale: Double
    let strikes: () -> [[EuclideousPulseStrike]]
    @ObservedObject var live: EmitterRatchetLive
    let onEdit: (Bool, @escaping (inout EmitterRatchetSet) -> Void) -> Void
    let onDragEnd: () -> Void
    let onSwitch: (Int) -> Void
    let onCollapse: () -> Void

    private let discW: CGFloat = 44, gap: CGFloat = 8

    var body: some View {
        typealias P = EmitterRatchetPalette
        let r = ratchets[output]
        let editorW = max(0, bodySize.width - discW - gap)
        return HStack(alignment: .top, spacing: gap) {
            discColumn
            editor(r: r, editorW: editorW).frame(width: editorW, alignment: .topLeading)
        }
        .frame(width: bodySize.width, height: bodySize.height, alignment: .topLeading)
    }

    private var discColumn: some View {
        typealias P = EmitterRatchetPalette
        return VStack(spacing: 8) {
            ForEach(0..<4, id: \.self) { i in
                let sel = i == output
                ZStack {
                    RoundedRectangle(cornerRadius: 10).fill(sel ? P.current : Color.clear)
                    RoundedRectangle(cornerRadius: 10).strokeBorder(sel ? P.light.opacity(0.6) : Color.clear, lineWidth: 1)
                    EmitterRatchetDisc(letter: emitterRatchetLetters[i], on: ratchets[i].on, accent: .clear, f: 0, outputMuted: i < outputMuted.count && outputMuted[i])
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { onSwitch(i) }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Edit emitter \(emitterRatchetLetters[i])")
                .accessibilityValue(sel ? "editing" : "")
                .accessibilityAddTraits(sel ? [.isButton, .isSelected] : .isButton)
            }
        }
        .frame(width: discW)
    }

    private func editor(r: EmitterRatchet, editorW: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            bigStrip(r: r, width: editorW)
            valueRow(r: r, width: editorW)
            strikesBlock(r: r, width: editorW)
            gapBlock(r: r, width: editorW)
            Spacer(minLength: 0)
        }
    }

    // the big strip (same base/flare the collapsed card draws, taller) — in HIT mode a tap on a hit cycles its count 1 → 2 → 3 → 4 (§5)
    private func bigStrip(r: EmitterRatchet, width: CGFloat) -> some View {
        typealias M = EmitterRatchetMetrics
        let h: CGFloat = 28
        let slotW = max(0, (width - CGFloat(M.slotCount - 1) * M.slotGap) / CGFloat(M.slotCount))
        let slots = (0..<M.slotCount).map { CGRect(x: CGFloat($0) * (slotW + M.slotGap), y: 0, width: slotW, height: h) }
        let mask = emitterRatchetPatternMask(steps: r.steps, hits: r.hits, offset: r.offset)
        let maskNoOffset = emitterRatchetPatternMask(steps: r.steps, hits: r.hits, offset: 0)
        let current = live.index(output) ?? -1
        let flareSlot = live.flareIndex(output) ?? current
        let accentOf: (Int) -> Color = { accents[max(0, min(accents.count - 1, $0))] }
        return ZStack(alignment: .topLeading) {
            EmitterRatchetStripBase(slots: slots, r: r, mask: mask, current: current).equatable()
            TimelineView(.animation(minimumInterval: 1.0 / 60, paused: !playing)) { tl in
                let fl = emitterRatchetFlare(output: output, strikes: strikes(), now: tl.date.timeIntervalSinceReferenceDate, scale: pulseScale)
                EmitterRatchetStripFlare(slots: slots, r: r, mask: mask, current: flareSlot, flare: fl, accent: fl.map { accentOf($0.lane) } ?? .clear)
            }
        }
        .frame(width: width, height: h, alignment: .topLeading)
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).onEnded { v in
            guard r.mode == .hit else { return }   // §5: per-hit counts are edited only in HIT mode
            let x = v.location.x
            guard let slot = slots.firstIndex(where: { x >= $0.minX && x <= $0.maxX }), slot < r.steps, (mask >> UInt16(slot)) & 1 != 0 else { return }
            let ord = emitterRatchetHitOrdinal(index: slot, steps: r.steps, offset: r.offset, patternMaskNoOffset: maskNoOffset)
            let next = r.hitCount(ord) % 4 + 1
            onEdit(true) { $0[output] = $0[output].settingHitCount(ord, next) }
        })
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emitterRatchetStripLabel(output: output, r, counts: counts))
    }

    // STEPS · HITS · OFFSET · CHANCE · RESTART, then the collapse (config) button
    private func valueRow(r: EmitterRatchet, width: CGFloat) -> some View {
        let fields: [EmitterRatchetField] = [.steps, .hits, .offset, .chance, .restart]
        let cellW = max(0, (width - EmitterRatchetMetrics.configWidth - gap) / CGFloat(fields.count))
        let h: CGFloat = 42
        return HStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(Array(fields.enumerated()), id: \.offset) { c, field in
                    EmitterRatchetCell(output: output, field: field, r: r, size: CGSize(width: cellW, height: h), leadingRule: c > 0, onEdit: onEdit, onDragEnd: onDragEnd)
                }
            }
            Spacer().frame(width: gap)
            EmitterRatchetConfigButton(output: output, open: true, onTap: onCollapse).frame(width: EmitterRatchetMetrics.configWidth, height: h)
        }
        .frame(width: width, height: h, alignment: .leading)
    }

    private func blockLabel(_ s: String) -> some View {
        Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced)).tracking(8 * 0.08).foregroundColor(EmitterRatchetPalette.muted)
    }

    // STRIKES: the mode segmented control, then the count (FIX) / MIN·MAX (RANGE) / hint (HIT)
    private func strikesBlock(r: EmitterRatchet, width: CGFloat) -> some View {
        typealias P = EmitterRatchetPalette
        let modeIdx = EmitterStrikeMode.allCases.firstIndex(of: r.mode) ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            blockLabel("STRIKES")
            EmitterRatchetSegmented(options: EmitterStrikeMode.allCases.map { $0.rawValue }, selected: modeIdx, height: 26, groupLabel: "Strikes mode") { idx in
                onEdit(true) { $0[output].mode = EmitterStrikeMode.allCases[idx] }   // §1.7: switching mode keeps every mode's stored values
            }
            Group {
                switch r.mode {
                case .fix:
                    EmitterRatchetCell(output: output, field: .strikes, r: r, size: CGSize(width: 90, height: 40), leadingRule: false, onEdit: onEdit, onDragEnd: onDragEnd)
                case .range:
                    HStack(spacing: 16) {
                        EmitterRatchetMiniStepper(label: "MIN", value: r.rangeMin, a11y: "Emitter \(emitterRatchetLetters[output]) strikes minimum") { d in
                            onEdit(true) { var x = $0[output]; x.rangeMin += d; $0[output] = x.normalized() }
                        }
                        EmitterRatchetMiniStepper(label: "MAX", value: r.rangeMax, a11y: "Emitter \(emitterRatchetLetters[output]) strikes maximum") { d in
                            onEdit(true) { var x = $0[output]; x.rangeMax += d; $0[output] = x.normalized() }
                        }
                    }
                case .hit:
                    Text("Tap a hit on the strip to set its count").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundColor(P.muted).lineLimit(2)
                }
            }
            .frame(height: 44, alignment: .leading)
        }
        .frame(width: width, alignment: .leading)
    }

    // GAP: the strike spacing (FIT · 1/8 · 1/16 · 1/16T · 1/32). CUT · SPILL is hidden (§0.2).
    private func gapBlock(r: EmitterRatchet, width: CGFloat) -> some View {
        let gapIdx = EmitterStrikeGap.allCases.firstIndex(of: r.gap) ?? 0
        return VStack(alignment: .leading, spacing: 4) {
            blockLabel("GAP")
            EmitterRatchetSegmented(options: EmitterStrikeGap.allCases.map { $0.rawValue }, selected: gapIdx, height: 26, groupLabel: "Strike gap") { idx in
                onEdit(true) { $0[output].gap = EmitterStrikeGap.allCases[idx] }
            }
        }
        .frame(width: width, alignment: .leading)
    }
}
