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
    static let restartIdleCell = Color(h: 0x1B1D23)
    static let ink = Color(h: 0xF2F4F7)
    static let dim = Color(h: 0xAAB0BA)
    static let chipOn = Color(h: 0xDFE3EA)
    static let chipOnText = Color(h: 0x0D0F14)
    static let chipOff = Color(h: 0x2A2D34)
    static let slot = Color(h: 0x5C626C)
    static let mutedBar = Color(h: 0x6A7079)
}

private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// One lane's data for the active sub-tab. Equatable, so the static layer re-draws only when something it shows actually changed.
struct EuclideousLanesPanelLane: Equatable {
    var grid: EuclideousLaneGrid
    /// The rate box's value for the active sub-tab (the mute unit on MUTE, the restart unit on RESTART).
    var unitLabel: String
    /// The active tab's cell length in beats, and the start of the window the roll covers (`floor(beat / window) × window`).
    var unitBeats: Double
    var windowStart: Double
    var roll: [EuclideousRollHit]
    /// MUTE tab only: where this lane's restart marks fall inside the mute window (read-only ticks, §4.8).
    var rhythmMarkBeats: [Double]
    var melodyMarkBeats: [Double]
    /// RESTART tab only: whether the lane is audible at each restart cell's start (the cell fill, §4.9).
    var cellAudible: [Bool]
}

/// The static layer: cell fills, run outlines, restart marks / slots, the roll, the read-only marks. No time in here — the playhead is a
/// separate layer — so it is redrawn only when its inputs change.
private struct EuclideousLanesStaticLayer: View, Equatable {
    let layout: EuclideousLanesLayout
    let tab: EuclideousLanesSubTab
    let lanes: [EuclideousLanesPanelLane]
    let accents: [Color]

    static func == (a: Self, b: Self) -> Bool { a.layout == b.layout && a.tab == b.tab && a.lanes == b.lanes }

    var body: some View {
        Canvas { ctx, _ in
            let restart = tab == .restart
            for lane in 0..<min(4, lanes.count) {
                draw(&ctx, lane: lane, data: lanes[lane], accent: accents[lane % accents.count], restart: restart)
            }
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

    private func draw(_ ctx: inout GraphicsContext, lane: Int, data: EuclideousLanesPanelLane, accent: Color, restart: Bool) {
        let top = layout.laneTop(lane)
        let gx = layout.gridX
        let cw = layout.cellW, laneH = layout.laneH, rowH = layout.rowH
        let scale = laneH / 50

        // ── cells ──
        if !restart {
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
        } else {
            for row in 0..<2 {
                let y = top + (row == 0 ? 0 : rowH + EuclideousLanesLayout.restartRowGap)
                for i in 0..<16 {
                    let r = CGRect(x: gx + layout.cellLeft(i), y: y, width: cw, height: rowH)
                    let audible = i < data.cellAudible.count ? data.cellAudible[i] : true
                    ctx.fill(RoundedRectangle(cornerRadius: 5).path(in: r), with: .color(audible ? accent.opacity(0.10) : EuclideousLanesPalette.restartIdleCell))
                }
            }
            // run outlines (one set per row) — 1.5pt, drawn 1pt outside the cells; carried-over / empty runs dashed at 40%
            for row in 0..<2 {
                let y = top + (row == 0 ? 0 : rowH + EuclideousLanesLayout.restartRowGap)
                let mask = row == 0 ? data.grid.rhythmMask : data.grid.melodyMask
                for run in euclideousLanesRuns(mask: mask) {
                    let x0 = gx + layout.cellLeft(run.start) - 1
                    let x1 = gx + layout.cellLeft(run.end - 1) + cw + 1
                    let rect = CGRect(x: x0, y: y - 1, width: x1 - x0, height: rowH + 2)
                    let path = RoundedRectangle(cornerRadius: 6).path(in: rect)
                    if run.dashed {
                        ctx.stroke(path, with: .color(accent.opacity(0.4)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                    } else {
                        ctx.stroke(path, with: .color(accent.opacity(0.8)), lineWidth: 1.5)
                    }
                }
            }
        }

        // ── the roll (above the cell fills so muted cells still show their dim bars; lower contrast on RESTART) ──
        for hit in data.roll where data.unitBeats > 0 {
            let u0 = (hit.beat - data.windowStart) / data.unitBeats
            guard u0 >= 0, u0 < 16 else { continue }
            let u1 = u0 + hit.gateBeats / data.unitBeats
            let x0 = xOf(u0), x1 = xOf(u1)
            let w = max(2.5, x1 - x0)
            let y = top + euclideousRollBarY(rank: hit.rank, laneH: laneH) - (hit.rank < 1 ? 1.5 : 0)
            let rect = CGRect(x: x0, y: y, width: w, height: 3)
            let color: Color
            if hit.rank < 1 {
                color = EuclideousLanesPalette.mutedBar.opacity(0.35)   // a rest / no riff rank: the middle line, dim, never blank (§3.3)
            } else if hit.audible {
                color = accent.opacity(restart ? 0.45 : 1)
            } else {
                color = EuclideousLanesPalette.mutedBar.opacity(restart ? 0.25 : 0.5)
            }
            ctx.fill(RoundedRectangle(cornerRadius: 1.5).path(in: rect), with: .color(color))
        }

        // ── restart marks ──
        if restart {
            for row in 0..<2 {
                let y = top + (row == 0 ? 0 : rowH + EuclideousLanesLayout.restartRowGap)
                let mask = row == 0 ? data.grid.rhythmMask : data.grid.melodyMask
                let markH = 18 * rowH / 24, inset = 3 * rowH / 24
                for i in 0..<16 {
                    let left = gx + layout.cellLeft(i)
                    if (mask >> UInt16(i)) & 1 != 0 {
                        ctx.fill(RoundedRectangle(cornerRadius: 2).path(in: CGRect(x: left + 2, y: y + inset, width: 4, height: markH)),
                                 with: .color(EuclideousLanesPalette.ink))
                    } else {
                        var p = Path()
                        p.move(to: CGPoint(x: left + 3, y: y + inset)); p.addLine(to: CGPoint(x: left + 3, y: y + inset + markH))
                        ctx.stroke(p, with: .color(EuclideousLanesPalette.slot), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                    }
                }
            }
        } else {
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
                for lane in 0..<4 where lane < unitBeats.count && unitBeats[lane] > 0 {
                    let pos = euclideousLanesPosition(beat: beat, unitBeats: unitBeats[lane], layout: layout)
                    let r = CGRect(x: layout.gridX + pos.x - 1, y: layout.laneTop(lane) - 2, width: 2, height: layout.laneH + 4)
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

/// The whole LANES tab content: sub-tab chips, four lane blocks (rate box + cells), the roll, marks, playheads, and the legend / hint.
struct EuclideousLanesPanel: View {
    let layout: EuclideousLanesLayout
    let tab: EuclideousLanesSubTab
    let lanes: [EuclideousLanesPanelLane]
    let accents: [Color]
    let playing: Bool
    let beatAt: (Date) -> Double
    let onSelectTab: (EuclideousLanesSubTab) -> Void
    let onRateTap: (Int) -> Void
    /// The value the cell under the finger has right now (a stroke starts by painting the OPPOSITE).
    let cellValue: (EuclideousLanesHit) -> Bool
    /// Apply `value` to a cell. `first` is true for the touch-down cell of a stroke (the page opens ONE undo step there).
    let onApply: (EuclideousLanesHit, Bool, Bool) -> Void
    let onToggle: (EuclideousLanesHit) -> Void   // VoiceOver's "Toggle" (a whole stroke of one cell)

    @State private var strokeLane: Int? = nil
    @State private var strokeValue = false
    @State private var lastApplied: EuclideousLanesHit? = nil

    var body: some View {
        let restart = tab == .restart
        ZStack(alignment: .topLeading) {
            subTabChips
            EuclideousLanesStaticLayer(layout: layout, tab: tab, lanes: lanes, accents: accents).equatable()
            ForEach(0..<4, id: \.self) { lane in rateBox(lane) }
            gestureLayer(restart: restart)
            EuclideousLanesPlayheads(layout: layout, unitBeats: lanes.map { $0.unitBeats }, playing: playing, beatAt: beatAt)
            accessibilityCells(restart: restart)
            legend
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    // ── sub-tab chips (§4.3) ──
    private var subTabChips: some View {
        HStack(spacing: 4) {
            chip("MUTE", width: 52, selected: tab == .mute) { onSelectTab(.mute) }
            chip("RESTART", width: 76, selected: tab == .restart) { onSelectTab(.restart) }
        }
        .frame(width: layout.width, height: EuclideousLanesLayout.subTabH, alignment: .leading)
    }
    private func chip(_ title: String, width: CGFloat, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(heavyMono(10)).tracking(0.6).lineLimit(1)
                .foregroundColor(selected ? EuclideousLanesPalette.chipOnText : EuclideousLanesPalette.dim)
                .frame(width: width, height: EuclideousLanesLayout.subTabH)
                .background(RoundedRectangle(cornerRadius: 6).fill(selected ? EuclideousLanesPalette.chipOn : EuclideousLanesPalette.chipOff))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title.capitalized)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
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
        .offset(x: 0, y: layout.laneTop(lane))
        .accessibilityLabel(euclideousLanesRateBoxLabel(lane: lane, unit: data?.unitLabel ?? ""))
        .accessibilityAction(named: "Next size") { onRateTap(lane) }
    }

    // ── the stroke gesture (§5.2): touch-down sets the stroke value to the OPPOSITE of that cell; every cell the finger then passes in the
    //    lane it began in takes that value. One DragGesture over the whole content; the maths is the pure hit test. ──
    private func gestureLayer(restart: Bool) -> some View {
        Color.clear
            .frame(width: layout.width, height: layout.height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        if strokeLane == nil {
                            guard let h = euclideousLanesHit(x: v.startLocation.x, y: v.startLocation.y, layout: layout, restart: restart) else { return }
                            strokeLane = h.lane; strokeValue = !cellValue(h); lastApplied = h
                            onApply(h, strokeValue, true)
                        } else if let lane = strokeLane,
                                  let h = euclideousLanesStrokeHit(x: v.location.x, y: v.location.y, lane: lane, layout: layout, restart: restart),
                                  h != lastApplied {
                            lastApplied = h
                            onApply(h, strokeValue, false)
                        }
                    }
                    .onEnded { _ in strokeLane = nil; lastApplied = nil }
            )
    }

    // ── VoiceOver (§7): every cell is a real button with the spec's words; the gesture layer above does the touching, so these carry no hit area ──
    @ViewBuilder private func accessibilityCells(restart: Bool) -> some View {
        ForEach(0..<4, id: \.self) { lane in
            ForEach(0..<(restart ? 2 : 1), id: \.self) { row in
                ForEach(0..<16, id: \.self) { cell in
                    let hit = EuclideousLanesHit(lane: lane, cell: cell, row: row)
                    let on = cellValue(hit)
                    let y = layout.laneTop(lane) + (row == 0 ? 0 : layout.rowH + EuclideousLanesLayout.restartRowGap)
                    Color.clear
                        .frame(width: layout.cellW, height: restart ? layout.rowH : layout.laneH)
                        .offset(x: layout.gridX + layout.cellLeft(cell), y: y)
                        .allowsHitTesting(false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(restart ? euclideousLanesRestartCellLabel(lane: lane, cell: cell, melody: row == 1, set: on)
                                                    : euclideousLanesMuteCellLabel(lane: lane, cell: cell, sounding: on))
                        .accessibilityAddTraits(.isButton)
                        .accessibilityAction(named: "Toggle") { onToggle(hit) }
                        .accessibilityAction { onToggle(hit) }
                }
            }
        }
    }

    // ── the bottom row (§4.10) ──
    private var legend: some View {
        Group {
            if tab == .mute {
                HStack(spacing: 8) {
                    legendItem("RHYTHM RESTART", barY: 2)
                    legendItem("MELODY RESTART", barY: 9)
                }
            } else {
                Text(euclideousLanesRestartHint).font(heavyMono(8)).tracking(0.48).foregroundColor(EuclideousLanesPalette.dim)
                    .lineLimit(1).truncationMode(.tail).frame(maxWidth: .infinity, alignment: .leading)
            }
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
