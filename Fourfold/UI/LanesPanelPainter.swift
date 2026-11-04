//  LanesPanelPainter.swift
//  The LANES tab of the bottom-right panel (ferry "LANES panel rebuilt as a per-lane mute grid with a live roll, plus separate rhythm
//  and melody restart rows", ratified 2026-10-18).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `MixPadPainter.swift`: every number — the layout, a
//  beat's x position, a touch's cell/row, the run outlines, the roll's bar rows — comes from the pure functions in Derivations.swift, so
//  the drawing and the touch can never disagree and the engine's own maths is what the picture shows. This file only paints what those
//  functions return and routes the touches they interpret. The page owns the data (the lanes' resolved grids, the cached roll feed) and
//  the edits (one undo step per stroke / rate tap); nothing here keeps state beyond the finger in flight.

import SwiftUI

private extension Color {
    init(h: UInt32) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}

enum EuclideousLanesPalette {
    static let mutedCell = Color(h: 0x22252C)
    static let ink = Color(h: 0xF2F4F7)
    static let dim = Color(h: 0xAAB0BA)
    static let mutedBar = Color(h: 0x6A7079)
}

private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// One OUTPUT's MUTE-view data (MUTE TAB ferry 2026-11-02: each block is an output A–D, muting EMISSION on that output).
/// Equatable, so the static layer re-draws only when something it shows actually changed.
struct EuclideousLanesPanelLane: Equatable {
    /// Output o's 16-cell mute (bit i set = cell i SOUNDS). The panel edits this (→ `euclideousOutputMutes[o]`).
    var cells16: UInt16
    /// The window size in whole PASSES (1…8) — the ◀ / ▶ zoom bounds (how many passes the 16 cells span).
    var passes: Int
    /// The mute cell length in beats (passes × the output's HOME lane's pass), and the start of the window the roll covers.
    var unitBeats: Double
    var windowStart: Double
    /// The REAL notes emitted on this output in the window (the actual MIDI, after routing / mute / ratchet / hocket — not a prediction), drawn pitch-positioned like the card-back rolls.
    var roll: [NoteRollNote]
    /// MUTE ZOOM (2026-11-03): the PREVIOUS equal-size window's emitted notes, ghosted dim behind `roll` (onion-skin) so the last iteration stays visible — at 8 passes it looks back the previous 8 passes.
    var rollPrev: [NoteRollNote]
    var canDec: Bool { passes > 1 }   // ◀ zoom IN enabled (can reach 1 pass)
    var canInc: Bool { passes < 8 }   // ▶ zoom OUT enabled (can reach 8 passes)
}

/// The static layer: cell fills, run outlines, restart marks / slots, the roll, the read-only marks. No time in here — the playhead is a
/// separate layer — so it is redrawn only when its inputs change.
private struct EuclideousLanesStaticLayer: View, Equatable {
    let layout: EuclideousLanesLayout
    /// ONE lane's layer (LANE SOLO: each lane is its own Canvas so its block can ease to 42 % on its own — an opacity modifier can't reach inside a shared Canvas).
    let lane: Int
    let data: EuclideousLanesPanelLane
    let accents: [Color]

    static func == (a: Self, b: Self) -> Bool { a.layout == b.layout && a.lane == b.lane && a.data == b.data }

    var body: some View {
        Canvas { ctx, _ in
            draw(&ctx, lane: lane, data: data, accent: accents[lane % accents.count])
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
    }

    /// x of a position `u` (in cell units, 0…16) inside the lane's window; clamps at the right edge of the last cell.
    private func xOf(_ u: Double) -> CGFloat {
        let c = min(16.0, max(0, u))
        if c >= 16 { return layout.gridX + layout.cellLeft(15) + layout.cellW }
        let i = min(15, Int(c.rounded(.down)))
        return layout.gridX + layout.cellLeft(i) + CGFloat(c - Double(i)) * layout.cellW
    }

    /// MUTE TAB ferry (2026-11-02): each block is an OUTPUT. The cells are output o's mute grid (a muted cell is dim); the roll behind them is the REAL MIDI that LEFT on this output in the window (from `NoteRollModel`,
    /// filtered to this output), drawn pitch-positioned — so a muted cell shows up as the gap it actually creates. (The per-lane restart marks are gone — an output has no rhythm of its own.)
    private func draw(_ ctx: inout GraphicsContext, lane output: Int, data: EuclideousLanesPanelLane, accent: Color) {
        let top = layout.laneTop(output)
        let gx = layout.gridX
        let cw = layout.cellW, laneH = layout.laneH

        // ── cells (bit set = sounds; cleared = muted) ──
        for i in 0..<16 {
            let r = CGRect(x: gx + layout.cellLeft(i), y: top, width: cw, height: laneH)
            let sounding = (data.cells16 >> UInt16(i)) & 1 != 0
            let shape = RoundedRectangle(cornerRadius: 6).path(in: r)
            if sounding {
                ctx.fill(shape, with: .color(accent.opacity(0.2)))
                ctx.stroke(RoundedRectangle(cornerRadius: 5.5).path(in: r.insetBy(dx: 0.5, dy: 0.5)), with: .color(accent.opacity(0.4)), lineWidth: 1)
            } else {
                ctx.fill(shape, with: .color(EuclideousLanesPalette.mutedCell))
            }
        }

        // ── the real emitted roll (above the cells) — pitch-positioned, DEVICE-OWED look: a fixed 36…96 range maps to the block height (notes clamp), each note a bar from its on to its off (held → to the window end). ──
        let loP = 36.0, hiP = 96.0, pSpan = hiP - loP
        func yOf(_ pitch: UInt8) -> CGFloat {
            let t = (Double(pitch) - loP) / pSpan
            return top + laneH - 2 - CGFloat(min(1, max(0, t))) * (laneH - 4)   // high pitch near the top
        }
        // MUTE ZOOM (2026-11-03): draw a window's notes into the 16-cell space, mapping each note's beat through `windowStart`. The previous
        // iteration is ghosted dim FIRST (onion-skin behind the current), the current window bright on top. A held note fills to the window end.
        func drawRoll(_ notes: [NoteRollNote], windowStart: Double, opacity: Double) {
            guard data.unitBeats > 0 else { return }
            for note in notes {
                let u0 = (note.onBeat - windowStart) / data.unitBeats
                let endBeat = note.endBeat ?? (windowStart + data.unitBeats * 16)
                let u1 = (endBeat - windowStart) / data.unitBeats
                guard u1 > 0, u0 < 16 else { continue }
                let x0 = xOf(max(0, u0)), x1 = xOf(min(16, u1)), y = yOf(note.pitch)
                ctx.fill(RoundedRectangle(cornerRadius: 1.5).path(in: CGRect(x: x0, y: y - 1.5, width: max(2.5, x1 - x0), height: 3)), with: .color(accent.opacity(opacity)))
            }
        }
        drawRoll(data.rollPrev, windowStart: data.windowStart - data.unitBeats * 16, opacity: 0.28)   // the previous iteration, dim behind
        drawRoll(data.roll, windowStart: data.windowStart, opacity: 1)                                // this iteration, full strength
    }
}

/// The playheads: one per lane, 2pt wide, from 2pt above the block to 2pt below, glowing, drawn above everything. Position from the
/// transport beat only (`euclideousLanesPosition`), never a timer; frozen while the transport is stopped.
private struct EuclideousLanesPlayheads: View {
    let layout: EuclideousLanesLayout
    let unitBeats: [Double]
    let playing: Bool
    let beatAt: (Date) -> Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !playing)) { tl in
            let beat = beatAt(tl.date)
            Canvas { ctx, _ in
                for output in 0..<4 {
                    guard output < unitBeats.count, unitBeats[output] > 0 else { continue }
                    let pos = euclideousLanesPosition(beat: beat, unitBeats: unitBeats[output], layout: layout)
                    let r = CGRect(x: layout.gridX + pos.x - 1, y: layout.laneTop(output) - 2, width: 2, height: layout.laneH + 4)
                    ctx.drawLayer { layer in
                        layer.addFilter(.shadow(color: EuclideousLanesPalette.ink.opacity(0.55), radius: 6))
                        layer.fill(RoundedRectangle(cornerRadius: 1).path(in: r), with: .color(EuclideousLanesPalette.ink))
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

/// The whole MUTE tab content: a hint line, four output blocks (each the 16-cell mute grid flanked by ◀ zoom-in /
/// ▶ zoom-out arrows — MUTE ZOOM 2026-11-03), the real emitted roll (current bright, previous dim), and playheads.
struct EuclideousLanesPanel: View {
    let layout: EuclideousLanesLayout
    let lanes: [EuclideousLanesPanelLane]
    let accents: [Color]
    let playing: Bool
    let beatAt: (Date) -> Double
    /// One zoom step of an output's window size in passes (output, up). `up` = ▶ zoom out (more passes); bounded 1…8 by the page.
    let onStepPass: (Int, Bool) -> Void
    /// The value the cell under the finger has right now (a stroke starts by painting the OPPOSITE).
    let cellValue: (EuclideousLanesHit) -> Bool
    /// Apply `value` to a cell. `first` is true for the touch-down cell of a stroke (the page opens ONE undo step there).
    let onApply: (EuclideousLanesHit, Bool, Bool) -> Void
    let onToggle: (EuclideousLanesHit) -> Void   // VoiceOver's "Toggle" (a whole stroke of one cell)

    @State private var strokeLane: Int? = nil
    @State private var strokeValue = false
    @State private var lastApplied: EuclideousLanesHit? = nil
    @State private var strokeStart: CGPoint? = nil   // a touch whose start differs from the stroke in flight is a NEW stroke (a cancelled gesture may never call onEnded)

    var body: some View {
        ZStack(alignment: .topLeading) {
            if EuclideousLowerRightCaptions.shown { subTabHint }   // §A7: hidden, not deleted
            ForEach(0..<min(4, lanes.count), id: \.self) { lane in
                EuclideousLanesStaticLayer(layout: layout, lane: lane, data: lanes[lane], accents: accents).equatable()
            }
            ForEach(0..<4, id: \.self) { output in
                zoomArrow(output, zoomIn: true)    // ◀ left of the roll
                zoomArrow(output, zoomIn: false)   // ▶ right of the roll
            }
            gestureLayer
            EuclideousLanesPlayheads(layout: layout, unitBeats: lanes.map { $0.unitBeats }, playing: playing, beatAt: beatAt)
            accessibilityCells
            if EuclideousLowerRightCaptions.shown { legend }   // §A7: hidden, not deleted
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    /// MUTE TAB ferry (2026-11-02): the per-lane restart hint is gone (the blocks are outputs now). One line, same hint style / slot — DEVICE-OWED wording.
    private var subTabHint: some View {
        Text("MUTE \u{2014} TAP CELLS TO SILENCE EACH OUTPUT")
            .font(heavyMono(8)).tracking(0.48).foregroundColor(EuclideousLanesPalette.dim)
            .lineLimit(1).truncationMode(.tail)
            .padding(.leading, 8)
            .frame(width: layout.width, height: EuclideousLanesLayout.subTabH, alignment: .leading)
            .allowsHitTesting(false)
    }

    // ── MUTE ZOOM (2026-11-03): one unlabelled zoom arrow flanking the roll — ◀ (zoomIn) on the LEFT where the old rail sat steps the output's
    //    window DOWN toward 1 pass (finer); ▶ (zoomOut) on the RIGHT steps it UP toward 8 (coarser, looking further back). No letter, no number,
    //    no "PASS": the output's accent colour tells the blocks apart and the roll itself shows the span. Greyed and disabled at the respective
    //    bound (◀ at 1 pass, ▶ at 8). Full-block height, so the whole arrow column is the hit target — much bigger than the old 38pt rail's
    //    ~12pt ◀/▶. DEVICE-OWED look: the arrow width (22), the fill/border opacities and the glyph size. ──
    private func zoomArrow(_ output: Int, zoomIn: Bool) -> some View {
        let accent = accents[output % accents.count]
        let data = output < lanes.count ? lanes[output] : nil
        let enabled = zoomIn ? (data?.canDec == true) : (data?.canInc == true)
        return Button { onStepPass(output, !zoomIn) } label: {   // zoomIn ⇒ step DOWN (up:false); zoomOut ⇒ step UP (up:true)
            Text(zoomIn ? "\u{25C0}" : "\u{25B6}").font(heavyMono(12))
                .foregroundColor(enabled ? accent : EuclideousLanesPalette.mutedBar)
                .frame(width: EuclideousLanesLayout.arrowW, height: layout.laneH)
                .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(enabled ? 0.18 : 0.06)))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(enabled ? accent.opacity(0.9) : EuclideousLanesPalette.mutedBar.opacity(0.5), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .offset(x: zoomIn ? 0 : layout.rightArrowX, y: layout.laneTop(output))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousOutputZoomLabel(output: output, passes: data?.passes ?? 1, zoomIn: zoomIn))
        .accessibilityAddTraits(.isButton)
    }

    // ── the stroke gesture (§5.2): touch-down sets the stroke value to the OPPOSITE of that cell; every cell the finger then passes in the
    //    lane it began in takes that value. One DragGesture over the whole content; the maths is the pure hit test. ──
    private var gestureLayer: some View {
        // The layer spans the whole content so its coordinates are the panel's own (what the pure hit test expects), but its HIT AREA is only the
        // grid — the sub-tab chips and the rate boxes sit under/next to it and must keep their own taps.
        let gridArea = CGRect(x: layout.gridX - 1, y: layout.laneTop(0), width: layout.gridW + 2,
                              height: layout.laneTop(3) + layout.laneH - layout.laneTop(0))
        return Color.clear
            .frame(width: layout.width, height: layout.height)
            .contentShape(Path(gridArea))
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if strokeStart != v.startLocation { strokeLane = nil; lastApplied = nil; strokeStart = v.startLocation }
                        if strokeLane == nil {
                            guard let h = euclideousLanesHit(x: v.startLocation.x, y: v.startLocation.y, layout: layout, restart: false) else { return }
                            strokeLane = h.lane; strokeValue = !cellValue(h); lastApplied = h
                            onApply(h, strokeValue, true)
                        } else if let lane = strokeLane,
                                  let h = euclideousLanesStrokeHit(x: v.location.x, y: v.location.y, lane: lane, layout: layout, restart: false),
                                  h != lastApplied {
                            lastApplied = h
                            onApply(h, strokeValue, false)
                        }
                    }
                    .onEnded { _ in strokeLane = nil; lastApplied = nil; strokeStart = nil }
            )
    }

    // ── VoiceOver (§7): every cell is a real button with the spec's words; the gesture layer above does the touching, so these carry no hit area ──
    private var accessibilityCells: some View {
        ForEach(0..<4, id: \.self) { output in
            ForEach(0..<16, id: \.self) { cell in
                let hit = EuclideousLanesHit(lane: output, cell: cell, row: 0)
                let on = cellValue(hit)
                Color.clear
                    .frame(width: layout.cellW, height: layout.laneH)
                    .offset(x: layout.gridX + layout.cellLeft(cell), y: layout.laneTop(output))
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(euclideousOutputMuteCellLabel(output: output, cell: cell, sounding: on))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Toggle") { onToggle(hit) }
                    .accessibilityAction { onToggle(hit) }
            }
        }
    }

    // ── the bottom row — MUTE TAB ferry (2026-11-02): the per-lane RHYTHM/MELODY RESTART swatches are gone (outputs have no restart); one caption, DEVICE-OWED wording. ──
    private var legend: some View {
        Text("\u{25C0} ZOOM IN \u{00B7} \u{25B6} ZOOM OUT (1\u{2013}8 PASSES) \u{00B7} THE PREVIOUS ITERATION GHOSTS DIM BEHIND")
            .font(heavyMono(8)).tracking(0.4).foregroundColor(EuclideousLanesPalette.dim)
            .lineLimit(1).truncationMode(.tail)
            .frame(width: layout.width, height: EuclideousLanesLayout.legendH, alignment: .leading)
            .offset(x: 0, y: layout.legendTop)
            .allowsHitTesting(false)
    }
}
