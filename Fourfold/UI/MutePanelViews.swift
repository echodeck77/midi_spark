//  MutePanelViews.swift
//  The MUTE tab of the bottom-right panel, rebuilt per emitter (MUTE TAB EMITTER ROLL ferry, 2026-11-09).
//
//  Four rows, one per OUTPUT (emitter) A–D. Each row is a neutral emitter-token TILE (its cell-size label) and a divided
//  mute STRIP with a clean roll of exactly what that emitter sends — one bar per note, at its REAL outgoing pitch, in the
//  colour of the LANE that sent it (a row fed by two lanes shows both). SwiftUI-only (the seam rule): every frame comes from
//  the pure `EuclideousMuteRowsLayout` + the feed (`euclideousEmitterRoll`) in Derivations.swift, so the drawing and the touch
//  can never disagree. This file paints what those return and routes the touches they interpret; the page owns the data + edits.
//
//  The OLD per-pass panel (`EuclideousLanesPanel`, LanesPanelPainter.swift) is kept compiled but unmounted (hide, don't delete).
//  §6 glow/flash effects land in the next slice; this one draws played (solid) / upcoming (dim) / muted (outline) + a playhead.

import SwiftUI

private extension Color {
    init(h: UInt32) { self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1) }
}
private func muteHeavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

enum EuclideousMutePalette {
    static let tileBG = Color(h: 0x1D1F24)
    static let stripBG = Color(h: 0x1B1D22)
    static let mutedCell = Color(h: 0x0E0F12)
    static let ink = Color(h: 0xF2F4F7)
    static let neutral = Color(h: 0xDFE3EA)   // the emitter token's neutral ring / the unit label
    static let outline = Color(h: 0x6A7079)   // a muted-cell ghost: a grey outline, not a bar
}

/// One output's row of data for the MUTE panel. Equatable, so a row's strip redraws only when what it shows changed.
struct EuclideousMuteRow: Equatable {
    var cells16: UInt16            // the output's 16-cell mute (bit set = sounds); edited by the strip
    var muteUnit: UInt8            // 0…3 — the cell-size label on the tile (1/16 · 1/8 · 1/4 · BAR)
    var unitBeats: Double          // the cell size in beats (for the beat-relative playhead — wraps smoothly)
    var windowStart: Double        // the 16-cell window the roll's notes are placed in
    var window: Double             // 16 × unitBeats
    var notes: [EmitterRollNote]   // played (from the log) + upcoming ghosts, already in the window
    var lo: Int, hi: Int           // the row's pitch axis
    var anyRouted: Bool            // any part routes here (token .live vs .unused)
    var flareLane: Int             // the latest sounding note's lane, for the token flare (−1 = none)
    var flareActivity: Double      // 0…1 flare strength
}

/// One row's STRIP: the divided mute tile, the C pitch-guides, and the roll (played solid / upcoming dim / muted outline). Its own
/// Equatable Canvas so it redraws only when the row changed — not every playhead frame (that is a separate layer).
private struct EuclideousMuteStripView: View, Equatable {
    let layout: EuclideousMuteRowsLayout
    let output: Int
    let data: EuclideousMuteRow
    let accents: [Color]

    static func == (a: Self, b: Self) -> Bool { a.layout == b.layout && a.output == b.output && a.data == b.data }

    var body: some View {
        Canvas { ctx, _ in draw(&ctx) }
            .frame(width: layout.width, height: layout.height)
            .allowsHitTesting(false)
    }

    private func draw(_ ctx: inout GraphicsContext) {
        let sr = layout.stripRect(output)
        guard sr.width > 0, sr.height > 0 else { return }
        let round = RoundedRectangle(cornerRadius: 8).path(in: sr)
        ctx.fill(round, with: .color(EuclideousMutePalette.stripBG))
        ctx.clip(to: round)   // §4.4 — nothing draws past the strip (fixes "bars past cell 16")

        // §4.4 — muted cells: a darker fill under a 135° hatch (the hatch clipped to each cell).
        for i in 0..<16 where (data.cells16 >> UInt16(i)) & 1 == 0 {
            let cr = CGRect(x: layout.cellLeft(i), y: sr.minY, width: layout.cellW, height: sr.height)
            ctx.fill(Path(cr), with: .color(EuclideousMutePalette.mutedCell))
            ctx.drawLayer { l in
                l.clip(to: Path(cr))
                var hatch = Path(); var x = cr.minX - cr.height
                while x < cr.maxX { hatch.move(to: CGPoint(x: x, y: cr.maxY)); hatch.addLine(to: CGPoint(x: x + cr.height, y: cr.minY)); x += 5 }   // 135°
                l.stroke(hatch, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            }
        }
        // §4.4 — hairline cell dividers (every fourth brighter, so beats of four read).
        for i in 0...16 {
            let x = layout.cellLeft(i)
            var p = Path(); p.move(to: CGPoint(x: x, y: sr.minY)); p.addLine(to: CGPoint(x: x, y: sr.maxY))
            ctx.stroke(p, with: .color(.white.opacity(i % 4 == 0 ? 0.13 : 0.05)), lineWidth: 0.5)
        }
        // §4.5 — a faint line at every C inside the row's range.
        if data.hi > data.lo {
            var p = data.lo; while p <= data.hi { if p % 12 == 0, let y = layout.cGuideY(pitch: p, lo: data.lo, hi: data.hi, row: output) {
                var g = Path(); g.move(to: CGPoint(x: sr.minX, y: y)); g.addLine(to: CGPoint(x: sr.maxX, y: y))
                ctx.stroke(g, with: .color(.white.opacity(0.06)), lineWidth: 0.5)
            }; p += 1 }
        }
        // §4.6 — the roll: each note a bar at its real pitch, in its source lane's colour. Played solid, upcoming dim (38 %), a
        // ghost in a muted cell a grey outline. (The sounding white-flash / glow are the next slice.)
        for n in data.notes {
            let r = layout.noteRect(row: output, pitch: n.pitch.map { Int($0) }, lo: data.lo, hi: data.hi,
                                    onset: n.onset, length: n.length, windowStart: data.windowStart, window: data.window)
            let shape = RoundedRectangle(cornerRadius: 2).path(in: r)
            let c = n.lane >= 0 && n.lane < accents.count ? accents[n.lane] : EuclideousMutePalette.neutral
            if !n.audible { ctx.stroke(shape, with: .color(EuclideousMutePalette.outline), lineWidth: 1) }   // a predicted hit that this cell silences
            else if n.ghost { ctx.fill(shape, with: .color(c.opacity(0.38))) }                               // upcoming
            else { ctx.fill(shape, with: .color(c)) }                                                        // played
        }
    }
}

/// §6 — the LIVE layer (60 fps while playing): the sounding-note GLOW + a white note-on FLASH, then one playhead per row (a 1 pt
/// ink line + a short trailing gradient + its glow), all from the TRANSPORT beat (the playhead wraps smoothly through the cell unit,
/// independent of the cached window). iOS-15 floor ⇒ glows are GraphicsContext `.shadow` filters, not a Metal `.layerEffect` (§6.3).
/// Stopped: the TimelineView pauses, the body re-renders with `playing == false`, so no glow / trail draws and the playhead freezes.
private struct EuclideousMuteLiveLayer: View {
    let layout: EuclideousMuteRowsLayout
    let rows: [EuclideousMuteRow]
    let accents: [Color]
    let playing: Bool
    let beatAt: (Date) -> Double

    private static let flashBeats = 0.12   // the white note-on flash fades over ~an eighth of a beat (DEVICE-OWED by eye)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !playing)) { tl in
            let beat = beatAt(tl.date)
            Canvas { ctx, _ in
                for o in 0..<min(4, rows.count) {
                    let data = rows[o]
                    let sr = layout.stripRect(o)
                    guard data.unitBeats > 0 else { continue }
                    // §6 — glow + flash on every note SOUNDING right now (played, audible). Clipped to the strip so nothing bleeds past.
                    if playing {
                        ctx.drawLayer { clipped in
                            clipped.clip(to: RoundedRectangle(cornerRadius: 8).path(in: sr))
                            for n in data.notes where !n.ghost && n.audible && n.pitch != nil && n.onset <= beat && n.onset + n.length > beat {
                                let r = layout.noteRect(row: o, pitch: n.pitch.map { Int($0) }, lo: data.lo, hi: data.hi,
                                                        onset: n.onset, length: n.length, windowStart: data.windowStart, window: data.window)
                                let c = n.lane >= 0 && n.lane < accents.count ? accents[n.lane] : EuclideousMutePalette.neutral
                                let shape = RoundedRectangle(cornerRadius: 2).path(in: r)
                                clipped.drawLayer { g in g.addFilter(.shadow(color: c.opacity(0.7), radius: 8)); g.fill(shape, with: .color(c)) }   // §6 — the bloom
                                let age = beat - n.onset
                                if age < Self.flashBeats { clipped.fill(shape, with: .color(.white.opacity(0.9 * (1 - age / Self.flashBeats)))) }   // §6 — the note-on flash
                            }
                        }
                    }
                    // the playhead: 1 pt ink + a short trailing gradient + a glow, all suppressed while stopped (only the frozen line stays).
                    let u = beat / data.unitBeats
                    let frac = (u - 16 * (u / 16).rounded(.down)) / 16      // (beat mod 16·unit) / (16·unit) — smooth wrap
                    let x = sr.minX + CGFloat(max(0, min(1, frac))) * sr.width
                    let trailW = min(48, x - sr.minX)
                    if playing, trailW > 1 {
                        let t = CGRect(x: x - trailW, y: sr.minY, width: trailW, height: sr.height)
                        ctx.fill(Path(t), with: .linearGradient(Gradient(colors: [EuclideousMutePalette.ink.opacity(0), EuclideousMutePalette.ink.opacity(0.16)]),
                                                                startPoint: t.origin, endPoint: CGPoint(x: t.maxX, y: t.minY)))
                    }
                    let line = CGRect(x: x - 0.5, y: sr.minY, width: 1, height: sr.height)
                    if playing { ctx.drawLayer { g in g.addFilter(.shadow(color: EuclideousMutePalette.ink.opacity(0.55), radius: 5)); g.fill(Path(line), with: .color(EuclideousMutePalette.ink)) } }
                    else { ctx.fill(Path(line), with: .color(EuclideousMutePalette.ink.opacity(0.8))) }   // stopped: a plain frozen line, no glow/trail
                }
            }
            .frame(width: layout.width, height: layout.height)
        }
        .frame(width: layout.width, height: layout.height)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The whole MUTE tab: four emitter rows (a token tile + a divided mute strip with the roll), a playhead per row, and the cell
/// paint / unit-cycle gestures. One Equatable strip per row + one playhead layer, like the old panel, so a frame redraws little.
struct EuclideousMutePanel: View {
    let layout: EuclideousMuteRowsLayout
    let rows: [EuclideousMuteRow]
    let accents: [Color]              // the four lane colours (notes + the token flare)
    let playing: Bool
    let beatAt: (Date) -> Double
    let onCycleUnit: (Int) -> Void                    // §5.1 — a tile tap cycles 1/16 → 1/8 → 1/4 → BAR
    let cellValue: (Int, Int) -> Bool                 // (output, cell) sounds right now?
    let onApply: (Int, Int, Bool, Bool) -> Void       // output, cell, value, first-of-stroke (one undo step opens on `first`)
    let onToggle: (Int, Int) -> Void                  // VoiceOver's "Toggle"

    @State private var strokeOutput: Int? = nil
    @State private var strokeValue = false
    @State private var lastCell: Int? = nil
    @State private var strokeStart: CGPoint? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<min(4, rows.count), id: \.self) { o in
                EuclideousMuteStripView(layout: layout, output: o, data: rows[o], accents: accents).equatable()
            }
            ForEach(0..<min(4, rows.count), id: \.self) { o in tile(o) }
            gestureLayer
            EuclideousMuteLiveLayer(layout: layout, rows: rows, accents: accents, playing: playing, beatAt: beatAt)
            accessibilityCells
        }
        .frame(width: layout.width, height: layout.height, alignment: .topLeading)
    }

    /// §4.3 — the left tile: the emitter token (neutral, flaring in the sounding lane's colour) over the cell-size label; one
    /// tap cycles the unit. 36 wide.
    private func tile(_ o: Int) -> some View {
        let data = rows[o]
        let r = layout.tileRect(o)
        let state = euclideousEmitterTokenEmitterState(muted: data.cells16 == 0, activity: data.flareActivity, anyRouted: data.anyRouted)
        let flare = data.flareLane >= 0 && data.flareLane < accents.count ? accents[data.flareLane] : .clear
        return Button { onCycleUnit(o) } label: {
            VStack(spacing: 3) {
                EuclideousEmitterTokenView(size: .d28, letter: euclideousOutputLetter(o), state: state, lane: flare)
                Text(euclideousMuteUnitLabel(data.muteUnit)).font(muteHeavyMono(9)).foregroundColor(EuclideousMutePalette.neutral).lineLimit(1)
            }
            .frame(width: r.width, height: r.height)
            .background(RoundedRectangle(cornerRadius: 8).fill(EuclideousMutePalette.tileBG))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .offset(x: r.minX, y: r.minY)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(euclideousOutputMuteUnitTileLabel(output: o, unit: data.muteUnit))
        .accessibilityHint("Cycles the cell size")
        .accessibilityAddTraits(.isButton)
    }

    // §5.2/§5.3 — one DragGesture over the STRIP region: touch-down paints the OPPOSITE of that cell (one undo step), the finger
    //   paints that value along the row it began in. Its hit area is only the strips, so the tiles keep their own taps.
    private var gestureLayer: some View {
        let region = CGRect(x: layout.stripX, y: layout.rowTop(0), width: layout.stripW,
                            height: layout.rowTop(3) + layout.rowH - layout.rowTop(0))
        return Color.clear
            .frame(width: layout.width, height: layout.height)
            .contentShape(Path(region))
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if strokeStart != v.startLocation { strokeOutput = nil; lastCell = nil; strokeStart = v.startLocation }
                    if strokeOutput == nil {
                        guard let h = layout.hit(x: v.startLocation.x, y: v.startLocation.y) else { return }
                        strokeOutput = h.output; strokeValue = !cellValue(h.output, h.cell); lastCell = h.cell
                        onApply(h.output, h.cell, strokeValue, true)
                    } else if let o = strokeOutput {
                        let cell = layout.cellIndex(x: v.location.x)
                        if cell != lastCell { lastCell = cell; onApply(o, cell, strokeValue, false) }
                    }
                }
                .onEnded { _ in strokeOutput = nil; lastCell = nil; strokeStart = nil })
    }

    // §7 — every cell is a real button for VoiceOver (the drag layer does the touching, so these carry no hit area).
    private var accessibilityCells: some View {
        ForEach(0..<min(4, rows.count), id: \.self) { o in
            ForEach(0..<16, id: \.self) { cell in
                Color.clear
                    .frame(width: layout.cellW, height: layout.rowH)
                    .offset(x: layout.cellLeft(cell), y: layout.rowTop(o))
                    .allowsHitTesting(false)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(euclideousOutputMuteCellLabel(output: o, cell: cell, sounding: cellValue(o, cell)))
                    .accessibilityAddTraits(.isButton)
                    .accessibilityAction(named: "Toggle") { onToggle(o, cell) }
                    .accessibilityAction { onToggle(o, cell) }
            }
        }
    }
}
