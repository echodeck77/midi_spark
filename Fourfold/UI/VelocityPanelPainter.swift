//  VelocityPanelPainter.swift
//  The VELOCITY tab of the bottom-right panel (2026-11-03) — the sibling of `RatchPanelPainter.swift`. Four cards A–D, one per output: a toggle disc, a 16-slot strip of the output's Euclid pattern, and five stacked drag cells
//  (STEPS · HITS · OFFSET · HIT VEL · MISS VEL). HIT VEL / MISS VEL are the two SLIDERS — bipolar (centre-anchored) signed offsets added to a note's own velocity. Every number comes from the pure functions in
//  `EmitterVelocityUI.swift` / Derivations.swift; this file paints them and routes the touches. It reuses the ratchet's palette, disc and metrics (the look is deliberately the same). The page owns the data and the one-undo-step edits.

import SwiftUI

// MARK: - the strip (the ratchet's clarity look: baseline, group shading, a bar per hit, a dot per rest)

private struct EmitterVelocityStripBase: View, Equatable {
    let slots: [CGRect]            // strip-local
    let v: EmitterVelocity
    let mask: UInt16
    let current: Int               // −1 = none
    var body: some View {
        Canvas { ctx, _ in
            typealias P = EmitterRatchetPalette
            typealias M = EmitterRatchetMetrics
            let last = min(slots.count, M.slotCount, max(0, v.steps)) - 1
            guard last >= 0 else { return }
            let base = CGRect(x: slots[0].minX, y: slots[0].maxY - 1, width: slots[last].maxX - slots[0].minX, height: 1)
            ctx.fill(RoundedRectangle(cornerRadius: 0.5).path(in: base), with: .color(P.baseline))
            for i in 0...last {
                let rect = slots[i]
                let tone = i == current ? P.slotCurrent : ((i / 4) % 2 == 0 ? P.slotA : P.slotB)
                ctx.fill(RoundedRectangle(cornerRadius: M.slotRadius).path(in: rect), with: .color(tone))
                if (mask >> UInt16(i)) & 1 != 0 {
                    // a HIT: one centred bar (the accent amount lives in the HIT VEL cell; the bar is the pattern, like a ratchet strike)
                    let barH: CGFloat = 12
                    let bar = CGRect(x: rect.midX - 1, y: rect.midY - barH / 2, width: 2, height: barH)
                    ctx.fill(RoundedRectangle(cornerRadius: 1).path(in: bar), with: .color(P.light))
                } else {
                    let d: CGFloat = 3
                    ctx.fill(Path(ellipseIn: CGRect(x: rect.midX - d / 2, y: rect.midY - d / 2, width: d, height: d)), with: .color(P.restMark))
                }
            }
        }
    }
}

// MARK: - one value cell (stacked label/value + progress; HIT VEL / MISS VEL are bipolar)

private struct EmitterVelocityCell: View {
    let output: Int
    let field: EmitterVelocityField
    let v: EmitterVelocity
    let size: CGSize
    let leadingRule: Bool
    let onEdit: (Bool, @escaping (inout EmitterVelocitySet) -> Void) -> Void
    let onDragEnd: () -> Void
    @State private var pressed = false
    @State private var dragStart: EmitterVelocity? = nil
    @State private var dragEdited = false
    @GestureState private var gestureLive = false

    private func finishDrag() {
        let edited = dragEdited
        pressed = false; dragStart = nil; dragEdited = false
        if edited { onDragEnd() }
    }

    var body: some View {
        typealias P = EmitterRatchetPalette
        typealias M = EmitterRatchetMetrics
        let label = Text(field.label).font(heavyMonoV(7)).tracking(7 * 0.06).foregroundColor(pressed ? P.pressedLabel : P.muted)
        let value = Text(emitterVelocityValueText(field, v)).font(heavyMonoV(12)).monospacedDigit().foregroundColor(pressed ? P.ink : P.text)
        let trackW = max(0, size.width - 2 * M.progressInset)
        let share = emitterVelocityBarShare(field, v)
        let i = output, f = field
        return ZStack(alignment: .topLeading) {
            if pressed { RoundedRectangle(cornerRadius: M.cellPressedRadius).fill(P.light) }
            if leadingRule && !pressed { Rectangle().fill(P.rule).frame(width: 1, height: size.height) }
            VStack(spacing: 0) {
                label.lineLimit(1)
                value.lineLimit(1).fixedSize()
            }
                .frame(width: size.width, alignment: .center)
                .padding(.top, 2)
            // the progress bar: a pattern field fills from the left (0…1); HIT VEL / MISS VEL fill from the centre (− to the left, + to the right)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: M.progressHeight / 2).fill(pressed ? P.ink.opacity(0.18) : P.rule).frame(width: trackW, height: M.progressHeight)
                if field.bipolar {
                    let half = trackW / 2
                    let w = min(half, abs(CGFloat(share)) * half)
                    RoundedRectangle(cornerRadius: M.progressHeight / 2).fill(pressed ? P.ink : P.muted)
                        .frame(width: max(share == 0 ? 0 : 1, w), height: M.progressHeight)
                        .offset(x: share >= 0 ? half : half - w)
                } else {
                    RoundedRectangle(cornerRadius: M.progressHeight / 2).fill(pressed ? P.ink : P.muted).frame(width: trackW * CGFloat(share), height: M.progressHeight)
                }
            }
            .padding(.leading, M.progressInset)
            .padding(.top, size.height - M.progressBottom - M.progressHeight)
        }
        .frame(width: size.width, height: size.height, alignment: .topLeading)
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { onEdit(true) { $0[i] = f.reset(in: $0[i]) } }
        .gesture(
            DragGesture(minimumDistance: emitterRatchetDragActivation)
                .updating($gestureLive) { _, live, _ in live = true }
                .onChanged { ev in
                    pressed = true
                    if dragStart == nil { dragStart = v; dragEdited = false }
                    let target = emitterVelocityDragValue(f, start: dragStart ?? v, travelUp: -ev.translation.height)
                    let want = f.value(of: target)
                    if want != f.value(of: v) { onEdit(!dragEdited) { $0[i] = f.setting(want, in: $0[i]) }; dragEdited = true }
                }
                .onEnded { _ in finishDrag() }
        )
        .onChange(of: gestureLive) { live in if !live { finishDrag() } }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(emitterVelocityCellLabel(output: output, field, v))
        .accessibilityAdjustableAction { dir in
            let delta = dir == .increment ? f.step : -f.step
            onEdit(true) { $0[i] = f.setting(f.value(of: $0[i]) + delta, in: $0[i]) }
        }
        .accessibilityAction { onEdit(true) { $0[i] = f.reset(in: $0[i]) } }   // a VoiceOver double-tap resets the cell
    }
}
private func heavyMonoV(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

// MARK: - the tab

/// The VELOCITY tab: four cards A–D (toggle · strip · five cells), laid out by `emitterRatchetLayout(…, cellCount: 5)`. `live` carries each output's current pattern step (−1 while stopped), so the strip can highlight it.
struct EuclideousVelocityPanel: View {
    let layout: EmitterRatchetLayout
    let velocities: EmitterVelocitySet
    let accents: [Color]
    @ObservedObject var live: EmitterRatchetLive
    let onEdit: (Bool, @escaping (inout EmitterVelocitySet) -> Void) -> Void
    let onDragEnd: () -> Void

    var body: some View {
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
        let v = velocities[x]
        let mask = emitterRatchetPatternMask(steps: v.steps, hits: v.hits, offset: v.offset)
        let slotsLocal = layout.slots.map { CGRect(x: $0.minX - layout.strip.minX, y: 0, width: $0.width, height: $0.height) }
        let current = live.index(x) ?? -1
        let accent = accents[max(0, min(accents.count - 1, x))]
        return HStack(alignment: .top, spacing: 0) {
            EmitterRatchetDisc(letter: emitterRatchetLetters[x], on: v.on, accent: accent, f: 0)
                .frame(width: M.toggleWidth, height: innerH)
                .contentShape(Rectangle())
                .onTapGesture { onEdit(true) { $0[x].on.toggle() } }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(emitterVelocityToggleLabel(output: x))
                .accessibilityValue(v.on ? "on" : "off")
                .accessibilityAddTraits(.isButton)
                .ringToggleTrait()
            Spacer().frame(width: M.toggleGap)
            VStack(spacing: M.stripGap) {
                EmitterVelocityStripBase(slots: slotsLocal, v: v, mask: mask, current: current).equatable()
                    .frame(width: stripW, height: M.stripHeight, alignment: .topLeading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(emitterVelocityStripLabel(output: x, v))
                HStack(spacing: 0) {
                    ForEach(0..<EmitterVelocityField.allCases.count, id: \.self) { c in
                        EmitterVelocityCell(output: x, field: EmitterVelocityField.allCases[c], v: v, size: layout.cells[min(c, layout.cells.count - 1)].size, leadingRule: c > 0, onEdit: onEdit, onDragEnd: onDragEnd)
                    }
                }
            }
            .frame(width: stripW)
            .opacity(v.on ? 1 : 0.42)
        }
        .padding(EdgeInsets(top: M.padVertical, leading: 0, bottom: M.padVertical, trailing: M.padRight))
        .frame(width: layout.cards.first?.width ?? 0, height: layout.cardHeight, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: M.cardRadius).fill(P.card))
        .overlay(RoundedRectangle(cornerRadius: M.cardRadius).strokeBorder(P.cardEdge, lineWidth: 1))
    }
}
