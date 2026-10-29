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
}
private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

// MARK: - the toggle's disc (§4.3, §5.1–§5.3)

/// The emitter circle: a 28 pt disc #2A2D34 with a 2 pt ring and the output's letter (11 pt heavy). ON: ring #DFE3EA, letter #F2F4F7. OFF: ring #3A3E47, letter #8A909A. A RATCHED flare (`f` 0…1, the PULSE flash timing) thickens the
/// ring to 3 pt in the striking lane's colour over a 6 pt lane40 glow and washes the disc to lane20.
struct EmitterRatchetDisc: View {
    let letter: String
    let on: Bool
    let accent: Color
    let f: Double
    var body: some View {
        let ring = on ? EmitterRatchetPalette.light : EmitterRatchetPalette.offRing
        let letterColor = on ? EmitterRatchetPalette.text : EmitterRatchetPalette.muted
        return ZStack {
            if f > 0 { Circle().inset(by: 1).stroke(accent.opacity(0.4), lineWidth: 6).opacity(f) }       // §5.3 glow: lane40, 6 pt
            Circle().inset(by: 1).fill(EmitterRatchetPalette.disc)
            if f > 0 { Circle().inset(by: 1).fill(accent.opacity(0.2)).opacity(f) }                          // §5.3 wash: lane20 over #2A2D34
            Circle().inset(by: 1).stroke(ring, lineWidth: 2)
            if f > 0 { Circle().inset(by: 1).stroke(accent, lineWidth: 2 + f).opacity(f) }                   // §5.3: the ring thickens 2 → 3 pt in lane100
            Text(letter).font(heavyMono(11)).foregroundColor(letterColor)
        }
        .frame(width: EmitterRatchetMetrics.discSize, height: EmitterRatchetMetrics.discSize)
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
            for i in 0..<min(slots.count, M.slotCount) where i < r.steps {
                let rect = slots[i]
                ctx.fill(RoundedRectangle(cornerRadius: M.slotRadius).path(in: rect), with: .color(i == current ? P.current : P.slot))
                if (mask >> UInt16(i)) & 1 != 0 {
                    for b in emitterRatchetBarRects(in: rect, strikes: r.strikes) {
                        ctx.fill(RoundedRectangle(cornerRadius: M.barRadius).path(in: b), with: .color(P.light.opacity(emitterRatchetBarAlpha(chance: r.chance))))
                    }
                } else {
                    ctx.fill(RoundedRectangle(cornerRadius: M.barRadius).path(in: emitterRatchetRestDot(in: rect)), with: .color(P.restDot))
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
            for b in emitterRatchetBarRects(in: slots[current], strikes: r.strikes) {
                ctx.fill(RoundedRectangle(cornerRadius: EmitterRatchetMetrics.barRadius).path(in: b), with: .color(accent.opacity(alpha)))
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - one value cell (§4.6, §5.5, §6.2)

/// One of the five readout cells: a label, the value, a bar showing the value's share of its range. Dragging up raises the value and down lowers it (starting once the touch has moved 6 pt); a double tap resets it; a single tap does
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
        let value = Text(emitterRatchetValueText(field, r)).font(heavyMono(11)).monospacedDigit().foregroundColor(pressed ? P.ink : P.text)
        let trackW = max(0, size.width - 2 * M.progressInset)
        let fillW = trackW * CGFloat(emitterRatchetBarShare(field, r))
        let i = output, f = field
        return ZStack(alignment: .topLeading) {
            if pressed { RoundedRectangle(cornerRadius: M.cellPressedRadius).fill(P.light) }
            if leadingRule && !pressed { Rectangle().fill(P.rule).frame(width: 1, height: size.height) }
            HStack(alignment: .firstTextBaseline, spacing: M.cellLabelGap) {
                label.lineLimit(1).layoutPriority(0)                       // in a narrow cell (iPad mini: 55 pt) the LABEL truncates — "CHANCE 100%" must never read "10…" (§4.9: truncate, never shrink)
                value.lineLimit(1).fixedSize().layoutPriority(1)
            }
                .frame(width: size.width, alignment: .center)
                .padding(.top, M.cellLabelTop)
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
                    let target = emitterRatchetDragValue(f, start: dragStart ?? r, travelUp: -v.translation.height)
                    let want = f.value(of: target)
                    if want != f.value(of: r) { onEdit(!dragEdited) { $0[i] = f.setting(want, in: $0[i]) }; dragEdited = true }   // one undo step per drag
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

// MARK: - the tab

/// The RATCH tab: four cards A–D (toggle · strip · five cells), laid out by `emitterRatchetLayout`. `playing` keeps the flare layers animating (and for the 1.5 s after a stop).
struct EuclideousRatchetPanel: View {
    let layout: EmitterRatchetLayout
    let ratchets: EmitterRatchetSet
    let accents: [Color]
    let counts: String?                          // "hits" / "steps" in a dev build (FX COUNTS), nil in release — read by the strip's VoiceOver label
    let playing: Bool
    let pulseScale: Double
    let strikes: () -> [[EuclideousPulseStrike]] // the PULSE feed's strikes per lane
    @ObservedObject var live: EmitterRatchetLive
    let onEdit: (Bool, @escaping (inout EmitterRatchetSet) -> Void) -> Void
    let onDragEnd: () -> Void

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
                EmitterRatchetDisc(letter: emitterRatchetLetters[x], on: r.on, accent: ratcheted.map { accentOf($0.lane) } ?? .clear, f: ratcheted?.f ?? 0)
            }
            .frame(width: M.toggleWidth, height: innerH)
            .contentShape(Rectangle())
            .onTapGesture { onEdit(true) { $0[x].on.toggle() } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(emitterRatchetToggleLabel(output: x))
            .accessibilityValue(emitterRatchetToggleValue(on: r.on))
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
                    ForEach(0..<5, id: \.self) { c in
                        EmitterRatchetCell(output: x, field: EmitterRatchetField.allCases[c], r: r, size: layout.cells[c].size, leadingRule: c > 0, onEdit: onEdit, onDragEnd: onDragEnd)
                    }
                }
            }
            .frame(width: stripW)
            .opacity(r.on ? 1 : 0.42)
        }
        .padding(EdgeInsets(top: M.padVertical, leading: 0, bottom: M.padVertical, trailing: M.padRight))
        .frame(width: layout.cards.first?.width ?? 0, height: layout.cardHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: M.cardRadius).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: M.cardRadius).strokeBorder(P.cardEdge, lineWidth: 1))
    }
}
