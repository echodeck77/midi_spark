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

/// One lane's MUTE-view data (RESTART CHAINS ferry §8: the panel is mute-only now). Equatable, so the
/// static layer re-draws only when something it shows actually changed.
struct EuclideousLanesPanelLane: Equatable {
    var grid: EuclideousLaneGrid
    var unitLabel: String
    /// The MUTE cell length in beats, and the start of the window the roll covers (`floor(beat / window) × window`).
    var unitBeats: Double
    var windowStart: Double
    var roll: [EuclideousRollHit]
    /// Where this lane's restart marks (from its resolved CHAINS, §8.3) fall inside the mute window (read-only ticks, §4.8).
    var rhythmMarkBeats: [Double]
    var melodyMarkBeats: [Double]
    /// LANE SOLO §6.4: the solo mask silences this lane — its whole block (rail, cells, roll, marks, playhead) draws at 42 %, still live. One flag with the LANES mute's own dim of the roll's bars (never stacked: the bars
    /// already drawn dim for a muted cell stay as they are, this dims the block as a whole).
    var silenced: Bool = false
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
        .opacity(data.silenced ? EuclideousLaneDimStyle.opacity : 1)
        .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: data.silenced)
        .allowsHitTesting(false)
    }

    /// x of a position `u` (in cell units, 0…16) inside the lane's window; clamps at the right edge of the last cell.
    private func xOf(_ u: Double) -> CGFloat {
        let c = min(16.0, max(0, u))
        if c >= 16 { return layout.gridX + layout.cellLeft(15) + layout.cellW }
        let i = min(15, Int(c.rounded(.down)))
        return layout.gridX + layout.cellLeft(i) + CGFloat(c - Double(i)) * layout.cellW
    }

    /// RESTART CHAINS ferry §8.2: the RESTART view (its rows, marks, slots, outlines and strokes) is gone —
    /// this now ALWAYS paints the MUTE view. Restarts are set on each lane's own RHYTHM tab (§6).
    private func draw(_ ctx: inout GraphicsContext, lane: Int, data: EuclideousLanesPanelLane, accent: Color) {
        let top = layout.laneTop(lane)
        let gx = layout.gridX
        let cw = layout.cellW, laneH = layout.laneH
        let scale = laneH / 50

        // ── cells ──
        for i in 0..<16 {
            let r = CGRect(x: gx + layout.cellLeft(i), y: top, width: cw, height: laneH)
            let sounding = (data.grid.muteCells >> UInt16(i)) & 1 != 0
            let shape = RoundedRectangle(cornerRadius: 6).path(in: r)
            if sounding {
                ctx.fill(shape, with: .color(accent.opacity(0.2)))
                ctx.stroke(RoundedRectangle(cornerRadius: 5.5).path(in: r.insetBy(dx: 0.5, dy: 0.5)), with: .color(accent.opacity(0.4)), lineWidth: 1)
            } else {
                ctx.fill(shape, with: .color(EuclideousLanesPalette.mutedCell))
            }
        }

        // ── the roll (above the cell fills so muted cells still show their dim bars) ──
        for hit in data.roll where data.unitBeats > 0 {
            let color: Color
            if hit.rank < 1 {
                color = EuclideousLanesPalette.mutedBar.opacity(0.35)   // a rest / no riff rank: the middle line, dim, never blank (§3.3)
            } else if hit.audible {
                color = accent.opacity(1)
            } else {
                color = EuclideousLanesPalette.mutedBar.opacity(0.5)
            }
            let y = top + euclideousRollBarY(rank: hit.rank, laneH: laneH) - (hit.rank < 1 ? 1.5 : 0)
            // FX RATCH (§13.4): a ratcheted hit is drawn as its n strikes, one slot apart; every other hit is one bar (strikes == 1)
            for k in 0..<max(1, hit.strikes) {
                let b0 = hit.beat + Double(k) * hit.spacingBeats
                let u0 = (b0 - data.windowStart) / data.unitBeats
                guard u0 >= 0, u0 < 16 else { continue }
                let len = (k == hit.strikes - 1 && hit.lastGateBeats > 0) ? hit.lastGateBeats : hit.gateBeats
                let x0 = xOf(u0), x1 = xOf(u0 + len / data.unitBeats)
                ctx.fill(RoundedRectangle(cornerRadius: 1.5).path(in: CGRect(x: x0, y: y, width: max(2.5, x1 - x0), height: 3)), with: .color(color))
            }
        }

        // ── restart marks (§8.3: now derived from each lane's resolved CHAINS, not the retired masks) ──
        for (beats, melody) in [(data.rhythmMarkBeats, false), (data.melodyMarkBeats, true)] {
            let h = 20 * scale
            let y = top + (melody ? 27 : 3) * scale
            for b in beats {
                guard data.unitBeats > 0 else { break }
                let u = (b - data.windowStart) / data.unitBeats
                guard u >= 0, u < 16 else { continue }
                let x = xOf(u)
                ctx.fill(RoundedRectangle(cornerRadius: 1).path(in: CGRect(x: x - 1, y: y, width: 2, height: h)),
                         with: .color(EuclideousLanesPalette.ink.opacity(0.5)))
            }
        }
    }
}

/// The playheads: one per lane, 2pt wide, from 2pt above the block to 2pt below, glowing, drawn above everything. Position from the
/// transport beat only (`euclideousLanesPosition`), never a timer; frozen while the transport is stopped.
private struct EuclideousLanesPlayheads: View {
    let layout: EuclideousLanesLayout
    let unitBeats: [Double]
    let silenced: [Bool]
    let playing: Bool
    let beatAt: (Date) -> Double

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !playing)) { tl in
            let beat = beatAt(tl.date)
            // one Canvas per lane inside the ONE timeline, so a silenced lane's playhead eases to 42 % on its own (LANE SOLO §6.4)
            ZStack(alignment: .topLeading) {
                ForEach(0..<4, id: \.self) { lane in
                    Canvas { ctx, _ in
                        guard lane < unitBeats.count, unitBeats[lane] > 0 else { return }
                        let pos = euclideousLanesPosition(beat: beat, unitBeats: unitBeats[lane], layout: layout)
                        let r = CGRect(x: layout.gridX + pos.x - 1, y: layout.laneTop(lane) - 2, width: 2, height: layout.laneH + 4)
                        ctx.drawLayer { layer in
                            layer.addFilter(.shadow(color: EuclideousLanesPalette.ink.opacity(0.55), radius: 6))
                            layer.fill(RoundedRectangle(cornerRadius: 1).path(in: r), with: .color(EuclideousLanesPalette.ink))
                        }
                    }
                    .frame(width: layout.width, height: layout.height)
                    .opacity(lane < silenced.count && silenced[lane] ? EuclideousLaneDimStyle.opacity : 1)
                    .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: lane < silenced.count && silenced[lane])
                }
            }
            .frame(width: layout.width, height: layout.height)
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The whole LANES tab content: a mute-only hint line (RESTART CHAINS ferry §8.1 — replaces the old MUTE |
/// RESTART sub-tab chips), four lane blocks (rate box + cells), the roll, marks and playheads.
struct EuclideousLanesPanel: View {
    let layout: EuclideousLanesLayout
    let lanes: [EuclideousLanesPanelLane]
    let accents: [Color]
    let playing: Bool
    let beatAt: (Date) -> Double
    let onRateTap: (Int) -> Void
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
            subTabHint
            ForEach(0..<min(4, lanes.count), id: \.self) { lane in
                EuclideousLanesStaticLayer(layout: layout, lane: lane, data: lanes[lane], accents: accents).equatable()
            }
            ForEach(0..<4, id: \.self) { lane in rateBox(lane) }
            gestureLayer
            EuclideousLanesPlayheads(layout: layout, unitBeats: lanes.map { $0.unitBeats }, silenced: lanes.map { $0.silenced }, playing: playing, beatAt: beatAt)
            accessibilityCells
            legend
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    /// §8.1: "one line replaces the two chips: 'RESTARTS ARE SET ON EACH LANE'S RHYTHM TAB', in the LANES
    /// hint style, at x8, centred vertically, truncating. It isn't interactive."
    private var subTabHint: some View {
        Text("RESTARTS ARE SET ON EACH LANE\u{2019}S RHYTHM TAB")
            .font(heavyMono(8)).tracking(0.48).foregroundColor(EuclideousLanesPalette.dim)
            .lineLimit(1).truncationMode(.tail)
            .padding(.leading, 8)
            .frame(width: layout.width, height: EuclideousLanesLayout.subTabH, alignment: .leading)
            .allowsHitTesting(false)
    }

    // ── the rate box (§4.4): lane colour at 20% with a 1pt border, "RATE" over the unit ──
    private func rateBox(_ lane: Int) -> some View {
        let accent = accents[lane % accents.count]
        let data = lane < lanes.count ? lanes[lane] : nil
        return Button { onRateTap(lane) } label: {
            VStack(spacing: 3) {
                Text("RATE").font(.system(size: 7, weight: .medium, design: .monospaced)).tracking(0.42).foregroundColor(EuclideousLanesPalette.dim).lineLimit(1)
                Text(data?.unitLabel ?? "").font(heavyMono(10)).foregroundColor(EuclideousLanesPalette.ink).lineLimit(1).minimumScaleFactor(1)
            }
            .frame(width: EuclideousLanesLayout.railW, height: layout.laneH)
            .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.2)))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(accent, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .opacity(data?.silenced == true ? EuclideousLaneDimStyle.opacity : 1)   // LANE SOLO §6.4 — still live
        .animation(.easeInOut(duration: EuclideousLaneDimStyle.easeSeconds), value: data?.silenced == true)
        .offset(x: 0, y: layout.laneTop(lane))
        .accessibilityLabel(euclideousAppendSilencedBySolo(euclideousLanesRateBoxLabel(lane: lane, unit: data?.unitLabel ?? ""), silenced: data?.silenced == true))
        .accessibilityAction(named: "Next size") { onRateTap(lane) }
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
        ForEach(0..<4, id: \.self) { lane in
            ForEach(0..<16, id: \.self) { cell in
                let hit = EuclideousLanesHit(lane: lane, cell: cell, row: 0)
                let on = cellValue(hit)
                Color.clear
                    .frame(width: layout.cellW, height: layout.laneH)
                    .offset(x: layout.gridX + layout.cellLeft(cell), y: layout.laneTop(lane))
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(euclideousAppendSilencedBySolo(euclideousLanesMuteCellLabel(lane: lane, cell: cell, sounding: on), silenced: lane < lanes.count && lanes[lane].silenced))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Toggle") { onToggle(hit) }
                    .accessibilityAction { onToggle(hit) }
            }
        }
    }

    // ── the bottom row (§4.10) — RESTART CHAINS ferry §8.2/§8.3: the RESTART-tab hint text is gone; this is always the MUTE legend now. ──
    private var legend: some View {
        HStack(spacing: 8) {
            legendItem("RHYTHM RESTART", barY: 2)
            legendItem("MELODY RESTART", barY: 9)
        }
        .frame(width: layout.width, height: EuclideousLanesLayout.legendH, alignment: .leading)
        .offset(x: 0, y: layout.legendTop)
    }
    private func legendItem(_ label: String, barY: CGFloat) -> some View {
        HStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 2).fill(EuclideousLanesPalette.mutedCell).frame(width: 10, height: 16)
                Rectangle().fill(EuclideousLanesPalette.ink).frame(width: 4, height: 5).offset(x: 3, y: barY)
            }
            .frame(width: 10, height: 16)
            Text(label).font(heavyMono(8)).tracking(0.48).foregroundColor(EuclideousLanesPalette.dim).lineLimit(1).fixedSize()
        }
    }
}
