//  GridUI.swift
//  MidiSpark — the 8×8 grid view (four-row cell) + palette + RECEIVERS/OUTPUTS panels + the CELL EDITOR.
//  Editing (delta §5 rev 2): in EDIT the whole pad is ONE tap target that opens the floating CELL EDITOR
//  (input · colour · emitters · actions); body long-press auditions (stopped); PERFORM tap flips ALT. The
//  old FROM/OUT popovers + tap-paint + hold-menu are retired (folded into the editor). Every edit goes
//  through MidiSparkAudioUnit.editScene/editDocument → scheduleRebuild. Tokens per docs/ui-port-guide.md.

import SwiftUI
import UIKit   // ColumnHoldOverlay: multi-touch column-key holds (§5b) need a UIView, not a SwiftUI gesture

extension Color {
    /// 0xRRGGBB → Color. Used for the 16 canonical Colour hexes (do not "harmonise" them, §ui-guide).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Canonical Colour hexes, in colourIDs / bank order (docs/ui-port-guide.md). Index = colour index.
let colourHexes: [UInt32] = [
    0xFFC53D, 0xFF7A1A, 0xFF4B33, 0xC2244B, 0xFF4D9E, 0xFFA8B8, 0xB44DFF, 0x7A3DF0,
    0x5566FF, 0x38A6FF, 0x25E0F0, 0x148F80, 0x7BF2CE, 0x2ECC5E, 0xC6F23D, 0xC9A227,
]
// delta §9 item 11: the four receivers' fixed "infrastructure family" hues (muted), shared by the
// RECEIVERS panel and the cells' band-as-deviation marker.
let receiverHues: [Color] = [Color(hex: 0x6B7A8F), Color(hex: 0x7E6B8F), Color(hex: 0x6B8F7E), Color(hex: 0x8F836B)]

// §5 drag-and-drop: the grid's fixed layout metrics + a point→cell map, SHARED by GridView (its own
// coordinate space) and the VC (mapping a cross-view palette drag by the grid's captured global frame).
enum GridGeometry {
    static let headH: CGFloat = 38      // the prominent column-key row (v57)
    static let vGap: CGFloat = 3
    /// Which cell contains a point in GRID-LOCAL coordinates (origin = the column-key row's top-left)?
    static func cell(atLocal p: CGPoint, gridWidth: CGFloat, cellHeight: CGFloat) -> (col: Int, row: Int)? {
        guard gridWidth > 0 else { return nil }
        let cellW = (gridWidth - CGFloat(7) * vGap) / 8
        let col = Int(p.x / (cellW + vGap))
        let y = p.y - (cellHeight + vGap)            // below the column-key row (now a cell's height)
        let row = Int(y / (cellHeight + vGap))
        guard col >= 0, col < 8, row >= 0, row < 8, y >= 0 else { return nil }
        return (col, row)
    }
}

func colourColor(_ id: String) -> Color? {
    colourIDs.firstIndex(of: id).map { Color(hex: colourHexes[$0]) }
}

private let accentCyan = Color(red: 0.15, green: 0.88, blue: 0.94)   // playhead / PERFORM accent
private let accentAmber = Color(red: 0.98, green: 0.72, blue: 0.12)  // selection / EDIT accent (§6.5)

// v56 theme tokens (mockup `T`): cell recess, edges, dim ink.
private let cellBg = Color(hex: 0x0B0D11)
private let cellEdge = Color(hex: 0x20242D)
private let dimInk = Color(hex: 0x5C6472)

/// The 8×8 grid — v56 FOUR-ROW cell (delta §4): input header · type+params body · emitter strip;
/// empty cells show a row-number watermark. `scene.cells` is [column][row]. `colours` maps a cell's
/// colourID → its type/params for the body text.
struct GridView: View {
    let scene: SceneState
    let colours: [Colour]
    let playColumn: Int
    let playing: Bool
    var beat: Double = 0        // host beat position, polled ~4 Hz; extrapolated per-frame below
    var tempo: Double = 120
    var stepBeats: Double = 2   // beats per grid step (from the global STEP rate)
    var swing: Int = 50         // 50…75 — warps the sweep so it spans the real (swung) column window
    var cellHeight: CGFloat = 54   // set by the parent to fit the available height (landscape)
    var editing: Bool = true    // EDIT: pad tap → CELL EDITOR. PERFORM: pad tap → ALT flip. (Both = one target.)
    var selCol: Int = -1
    var selRow: Int = -1
    var onTap: ((Int, Int) -> Void)? = nil          // delta §5: whole-pad target → editor (EDIT, OCCUPIED cells only; empties inert)
    // AUDITION (§6.4 / delta §5): press-and-hold a cell (≈0.3s) → sound its processor alone while the
    // transport is stopped; release ends it. Fires in both modes; the engine only sounds it when stopped.
    var onAuditionStart: ((Int, Int) -> Void)? = nil
    var onAuditionEnd: (() -> Void)? = nil
    var onLongPressStageCell: ((Int, Int) -> Void)? = nil   // EDIT: long-press a populated cell → put it in cell-edit (+ armed for relocate)
    var laneMask: UInt8 = 0                          // §5b: held columns (bit i = column i) — for the LOOP highlight
    var onLaneMask: ((UInt8) -> Void)? = nil         // PERFORM: multi-column HOLD on the keys → held-set bitmask
    var holdLatch: Bool = false                      // §5c: while ON, an audition release LATCHES (keeps droning)
    var onMoveCell: ((_ from: (col: Int, row: Int), _ to: (col: Int, row: Int)) -> Void)? = nil   // §5 drag-and-drop (EDIT)
    var dropHoverCell: GridPos? = nil                // §5: the cell under a palette drag (highlight the drop target)
    var staging: Bool = false                        // cell-edit staging: EMPTY cells pulse a border to invite tap-to-place
    var stagingColor: Color = stagingCyan            // the staged Colour's own hue (the pulse colour)
    var stagedCells: Set<GridPos> = []               // cells placed this staging session: pulse colour↔black; gate the empty flash
    var hiddenPending: GridPos? = nil                // a just-hidden cell in its undo window: ring in its own colour, tap to restore
    var tapAltMask: UInt64 = 0                        // §9 item 1 ON TAP: ephemeral per-cell ALT flips (bit col*8+row)
    var tapMuteMask: UInt64 = 0                       // §9 item 1 ON TAP = MUTE: ephemeral per-cell mute (dims the cell)

    @State private var breathe = false     // shared ALT-ring breathe phase (§6.5); decorative, not beat-locked
    @State private var lastBeat: Double = 0
    @State private var lastBeatAt = Date()
    // §5 drag-and-drop (EDIT): the cell being dragged + the hovered drop target; the grid's measured size
    // maps a drag location (in the "grid" coordinate space) to a cell.
    struct GridPos: Hashable { let col: Int; let row: Int }
    @State private var dragFrom: GridPos? = nil
    @State private var dragTo: GridPos? = nil
    @State private var stagePressed = false          // this long-press already fired staging (once per gesture)
    @State private var gridSize: CGSize = .zero
    private func cellAt(location p: CGPoint) -> GridPos? {
        GridGeometry.cell(atLocal: p, gridWidth: gridSize.width, cellHeight: cellHeight).map { GridPos(col: $0.col, row: $0.row) }
    }

    /// The beat position NOW, extrapolated from the last poll (one-clock rule, §4): the UI polls at
    /// ~4 Hz; between polls we advance the last value by elapsed·tempo so the playhead glides.
    private func liveBeat(_ now: Date) -> Double {
        playing ? lastBeat + now.timeIntervalSince(lastBeatAt) * tempo / 60.0 : lastBeat
    }

    // Layout constants — shared by cellView and the mutation-line overlay so they never drift.
    private static let vGap = GridGeometry.vGap
    private static let headH = GridGeometry.headH     // the prominent column-key row (v57)

    var body: some View {
        VStack(spacing: Self.vGap) {
            columnKeys                                   // v57 prominent column keys + sweeping arrow
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: Self.vGap) {
                    ForEach(0..<8, id: \.self) { col in cellView(col: col, row: row) }
                }
            }
        }
        .overlay { mutationLines }                       // per-cell falling lines in the active column
        .coordinateSpace(name: "grid")                   // §5 drag-and-drop: maps a drag location → a cell
        .background(GeometryReader { g in Color.clear.onAppear { gridSize = g.size }.onChange(of: g.size) { gridSize = $0 } })
        .onAppear { withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) { breathe = true } }
        .onChange(of: beat) { newBeat in lastBeat = newBeat; lastBeatAt = Date() }
    }

    // v57 PROMINENT COLUMN KEYS — a numbered 40px key per column; the active one lights while playing.
    // The master playhead arrow sweeps across the top of this row (delta §4, one-clock). The column-hold
    // LAP gesture (§5b) will attach here later; the tap-to-mute interaction was removed pending the spec.
    private var columnKeys: some View {
        HStack(spacing: Self.vGap) {
            ForEach(0..<8, id: \.self) { col in
                let active = playing && col == playColumn
                let held = (laneMask & (1 << UInt8(col))) != 0     // §5b lap: this column is in the held set
                Text("\(col + 1)")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundColor(active ? .black : (held ? accentCyan : .white.opacity(0.45)))
                    .frame(maxWidth: .infinity).frame(height: cellHeight)   // key row = a cell's height (user 2026-07-26)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(active ? accentCyan : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 6)                 // LOOP state = held key ring (§5b)
                        .stroke(held ? accentCyan : .clear, lineWidth: 2).padding(1))
            }
        }
        .overlay { masterArrow }
        // PERFORM: a transparent multi-touch layer over the key row → held-column bitmask (the LAP).
        .overlay { if !editing, let cb = onLaneMask { ColumnHoldOverlay(gap: Self.vGap, latched: holdLatch, onChange: cb) } }
    }

    // Master playhead (delta §4): a glowing down-arrow sweeping left→right across the 8 columns over
    // one cycle, snapping at the loop. Pure function of the extrapolated beat — no view owns a clock.
    private var masterArrow: some View {
        GeometryReader { geo in
            let cycle = max(0.001, stepBeats * Double(Snap.cols))
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { tl in
                let b = liveBeat(tl.date)
                let frac = (b.truncatingRemainder(dividingBy: cycle) / cycle + 1).truncatingRemainder(dividingBy: 1)
                Text("▼")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.white)
                    .shadow(color: .white.opacity(0.9), radius: 4)
                    .position(x: geo.size.width * frac, y: 5)
                    .opacity(playing ? 0.95 : 0)
            }
        }
        .allowsHitTesting(false)
    }

    // Per-cell MUTATION line (delta §4): in the ACTIVE column, one white horizontal line falls
    // through each WORKING cell over its step (the "this machine is running" cue). Faint & glowless
    // when bypassed (identity); absent when muted. One overlay for all — geometry derived from the
    // shared layout constants; hit-testing off so cell taps pass through.
    private var mutationLines: some View {
        GeometryReader { geo in
            let cellW = (geo.size.width - 7 * Self.vGap) / 8
            let colX = CGFloat(playColumn) * (cellW + Self.vGap) + cellW / 2
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { tl in
                // within-column fraction (0 at column entry → 1 at exit), swing-aware so it spans the
                // real (swung) column window rather than finishing early and wrapping.
                let f = columnSweepFraction(realBeat: liveBeat(tl.date), stepBeats: stepBeats, swing: swing)
                ForEach(0..<8, id: \.self) { r in
                    if playing, let c = cellAt(playColumn, r), !c.muted {
                        let faint = c.bypassed
                        Rectangle()
                            .fill(Color.white.opacity(faint ? 0.4 : 0.92))
                            .frame(width: cellW - 4, height: 2)
                            .shadow(color: faint ? .clear : Color.white.opacity(0.8), radius: faint ? 0 : 4)
                            .position(x: colX, y: (cellHeight + Self.vGap) + CGFloat(r) * (cellHeight + Self.vGap) + f * cellHeight)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func cellView(col: Int, row: Int) -> some View {
        let raw = (col < scene.cells.count && row < scene.cells[col].count) ? scene.cells[col][row] : nil
        let cell = (raw?.muted == true) ? nil : raw    // a HIDDEN (muted) cell renders as EMPTY (disappeared); a tap toggles it back
        let isSel = col == selCol && row == selRow
        let inActiveCol = playing && col == playColumn
        let parent = parentOf(col, row)
        let colour = cell.flatMap { c in colourColor(c.colourID) }
        let noDest = cell.map { $0.buses.isEmpty && !isTapped(col, row) } ?? false
        let tapMutedHere = cell != nil && (tapMuteMask >> UInt64(col * 8 + row)) & 1 == 1   // §9 ON TAP = MUTE (momentary)

        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(colour ?? cellBg)

            if let cell {
                VStack(spacing: 0) {
                    inputHeader(cell, parent: parent, live: inActiveCol)
                    Spacer(minLength: 0)
                    bodyText(cell)
                    Spacer(minLength: 0)
                    emitterStrip(cell, firing: inActiveCol)
                }
            } else {
                Text("\(row + 1)")                          // empty-cell watermark (§4)
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.08))
            }
        }
        .opacity(tapMutedHere ? 0.28 : 1)                   // §9 ON TAP = MUTE: the momentarily-muted cell dims
        .frame(maxWidth: .infinity).frame(height: cellHeight)
        .overlay {                                          // border: recently-hidden > no-dest > selection > active > idle
            let activeGlow = inActiveCol && cell != nil     // only WORKING cells glow in the active column
            if GridPos(col: col, row: row) == hiddenPending, let hc = raw {
                // recently-HIDDEN (undo window): a ring in the hidden cell's own colour — tap to restore, touch elsewhere to delete
                RoundedRectangle(cornerRadius: 8).stroke(colourColor(hc.colourID) ?? accentAmber, lineWidth: 2.5)
            } else if noDest && !isSel {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(red: 0.95, green: 0.25, blue: 0.28), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSel ? accentAmber : (activeGlow ? Color.white.opacity(0.7) : cellEdge),
                            lineWidth: isSel ? 2 : (activeGlow ? 1.5 : 1))
            }
        }
        .overlay {                                          // ALT (B-state) breathing ring (§6.5) — effective ALT
            // §9 item 1 ON TAP (unified model): the ring follows base ALT XOR the ephemeral tap flip.
            let effAlt = cell.map { $0.alt != ((tapAltMask >> UInt64(col * 8 + row)) & 1 == 1) } ?? false
            if effAlt {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(breathe ? 0.95 : 0.35), lineWidth: 2)
                    .padding(3)
            }
        }
        .overlay {                                          // §5 drag-and-drop: the hovered drop target
            let pos = GridPos(col: col, row: row)
            if (dragFrom != nil && dragTo == pos && dragFrom != dragTo) || dropHoverCell == pos {
                RoundedRectangle(cornerRadius: 8).stroke(accentCyan, lineWidth: 2.5)
            }
        }
        .overlay {                                          // staging: EVERY empty cell pulses a border in the staged hue → tap to place
            if staging, cell == nil {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
                    let f = stagingPulseFraction(tl.date, period: 0.9)
                    RoundedRectangle(cornerRadius: 8).strokeBorder(stagingColor.opacity(0.2 + 0.7 * f), lineWidth: 2)
                }
                .allowsHitTesting(false)
            }
        }
        .overlay {                                          // staging: a PLACED cell pulses colour↔black, like its palette chip
            if stagedCells.contains(GridPos(col: col, row: row)) {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
                    let f = stagingPulseFraction(tl.date, period: 0.85)
                    RoundedRectangle(cornerRadius: 8).fill(Color.black).opacity(f * 0.72)
                }
                .allowsHitTesting(false)
            }
        }
        .opacity(dragFrom == GridPos(col: col, row: row) ? 0.4 : 1)   // dim the cell being dragged
        .contentShape(Rectangle())
        // delta §5: the whole pad is ONE tap target in both modes — EDIT opens the CELL EDITOR (the VC
        // routes onTap), PERFORM flips ALT. FROM/OUT popovers + the hold menu are retired (contents moved
        // into the editor). Body-hold still auditions (stopped).
        // TAP → onTap (EDIT: hide-with-undo / staging commit-place; PERFORM: ALT flip). LONG-PRESS a
        // populated cell (user 2026-07-26): EDIT puts it into cell-edit AND arms a relocate — keep dragging
        // to move it (overwrite target); PERFORM auditions on the hold. The long-press must complete before
        // the drag, so a quick tap can never stage or move a cell.
        .onTapGesture { onTap?(col, row) }
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.3)
                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("grid")))
                .onChanged { value in
                    guard case .second(true, let drag) = value else { return }   // long-press done → picked up
                    if editing {
                        if !stagePressed {                                        // fire staging ONCE: populated adopts,
                            stagePressed = true; onLongPressStageCell?(col, row)  // EMPTY stages the selected Colour (3rd entrance)
                        }
                        if cell != nil {                                          // relocate arms only for a pre-existing cell
                            if dragFrom == nil { dragFrom = GridPos(col: col, row: row) }
                            if let d = drag { dragTo = cellAt(location: d.location) }
                        }
                    } else {
                        onAuditionStart?(col, row)                                // PERFORM: hold → audition (idempotent)
                    }
                }
                .onEnded { value in
                    defer { dragFrom = nil; dragTo = nil; stagePressed = false }
                    if !editing { if !holdLatch { onAuditionEnd?() }; return }
                    guard case .second(true, let drag?) = value, let from = dragFrom,
                          let to = cellAt(location: drag.location), to != from else { return }
                    onMoveCell?((from.col, from.row), (to.col, to.row))           // relocate (overwrite)
                }
        )
    }

    // ① INPUT HEADER — "FROM MIDI" / "FROM R n" (a receiver) / "FROM ROW n"; flares white on the live
    // column. §9 item 11 BAND-AS-DEVIATION: a MIDI-IN cell on R2–R4 tints the header its receiver hue;
    // Receiver 1 (the default) and FROM-ROW cells show NO band — single-receiver grids stay clean.
    @ViewBuilder private func inputHeader(_ cell: Cell, parent: Int, live: Bool) -> some View {
        let midi = parent < 0
        let recv = cell.inputReceiver ?? 0
        let band: Color? = (midi && recv > 0 && recv < receiverHues.count) ? receiverHues[recv] : nil
        if midi && band == nil {
            EmptyView()          // a FROM-MIDI (Receiver 1) cell shows NO input header (user 2026-07-26)
        } else {
            // R2–R4 = the identity BAND only (band-as-deviation); a reference = "FROM ROW n".
            let compact = cellHeight < 36
            let label = compact ? "" : (midi ? "" : "FROM ROW \(parent + 1)")
            Text(label)
                .font(.system(size: 6.5, weight: .heavy, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.7)
                .foregroundColor(live ? .black : .white.opacity(0.85))
                .frame(maxWidth: .infinity).frame(height: compact ? 8 : 13)
                .background(live ? Color.white : (band ?? Color.black.opacity(0.52)))
                .clipShape(.rect(topLeadingRadius: 7, topTrailingRadius: 7))
        }
    }

    // ② BODY — type + effective-ish params (compact). Rendered over the colour fill.
    private func bodyText(_ cell: Cell) -> some View {
        let c = colours.first { $0.colourID == cell.colourID }
        let dim = cell.bypassed || cell.muted
        return HStack(spacing: 3) {                    // type + params on ONE line (user 2026-07-26)
            Text(typeLabel(c))
                .font(.system(size: 8, weight: .black, design: .monospaced))
            Text(paramText(c))
                .font(.system(size: 6.5, weight: .bold, design: .monospaced))
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .foregroundColor(dim ? .white.opacity(0.3) : .black.opacity(0.6))
        .padding(.horizontal, 2)
    }

    // ④ EMITTER STRIP — A B C D; lit = on, brighter (white) = firing this column.
    private func emitterStrip(_ cell: Cell, firing: Bool) -> some View {
        HStack(spacing: 2) {
            ForEach(Bus.allCases, id: \.self) { b in
                let on = cell.buses.contains(b)
                Text(b.rawValue)
                    .font(.system(size: 6.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? (firing ? .black : .white) : .black.opacity(0.4))
                    .frame(maxWidth: .infinity).frame(height: 11)
                    .background(RoundedRectangle(cornerRadius: 3)
                        .fill(on ? (firing ? Color.white : Color.black.opacity(0.62)) : Color.black.opacity(0.18)))
            }
        }
        .padding(.horizontal, 2).padding(.bottom, 2)
    }

    // ---- routing derivation (mirrors engine resolvedParent/parentRow — truthful, delta §1) ----
    private func cellAt(_ col: Int, _ row: Int) -> Cell? {
        guard col >= 0, col < scene.cells.count, row >= 0, row < scene.cells[col].count else { return nil }
        return scene.cells[col][row]
    }
    private func parentOf(_ col: Int, _ row: Int) -> Int {
        guard let ir = cellAt(col, row)?.inputRow, ir != row, let p = cellAt(col, ir), !p.muted else { return -1 }
        return ir
    }
    private func isTapped(_ col: Int, _ row: Int) -> Bool {
        for r in 0..<8 where r != row && cellAt(col, r)?.inputRow == row { return true }
        return false
    }
    private func typeLabel(_ c: Colour?) -> String {
        switch c?.type {
        case .arp: return "ARP"; case .ratchet: return "RTC"; case .passgate: return "PASS"
        case .strum: return "STRM"; case .chance: return "CHNC"; case .harmonize: return "HARM"
        case .none: return "—"
        }
    }
    private func paramText(_ c: Colour?) -> String {
        guard let c else { return "" }
        var s: String
        switch c.type {
        case .arp:
            s = c.paramsA.rate?.rawValue ?? ""
            if let o = c.paramsA.octaves, o > 1 { s += " \(o)OCT" }
            if c.paramsA.phase == .free { s += " ∞" }            // FREE-phase badge (§4)
        case .ratchet:  s = "×\(c.paramsA.count ?? 3)"
        case .passgate: s = "GATE"
        case .strum:    s = "SPR \(Int((c.paramsA.spread ?? 0.1) * 100))"
        case .chance:   s = "\(Int((c.paramsA.probability ?? 1) * 100))%"
        case .harmonize:
            let iv = (c.paramsA.harmIntervals ?? [0,0,0]).filter { $0 != 0 }
            s = iv.isEmpty ? "UNISON" : iv.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: " ")
        }
        if c.transpose != 0 { s += " \(c.transpose > 0 ? "+" : "")\(c.transpose)" }   // transpose badge
        return s
    }
}

// MARK: - Velocity marks (design item 4) — the strip meter is floating marks, not a bottom-fill

/// A floating velocity MARK: a note-on drawn at its velocity height, fading ~250ms. `col` is the source
/// colourIndex — emitters tint by the source Colour, −1 = the strip's own hue (receivers / master).
struct VelMark: Equatable { let vel: Double; let col: Int8; let born: Date; var withheld: Bool = false }

/// Draw a strip's velocity marks — horizontal ticks at each mark's velocity height, opacity fading over
/// ~250ms. Behind a TimelineView (the caller animates by passing `now`). `hueFor` maps a mark to its colour.
/// §6a THE WITHHELD TELL: a `withheld` mark (a note CLAIM fully suppressed) draws HOLLOW (a stroked outline
/// in the source hue) + a small amber CLAIM tick, fading a touch slower — suppression made visible, not silent.
func velMarkLayer(_ marks: [VelMark], now: Date, hueFor: @escaping (Int8) -> Color) -> some View {
    let claimAmber = Color(red: 0.98, green: 0.72, blue: 0.12)
    return GeometryReader { g in
        ForEach(Array(marks.enumerated()), id: \.offset) { _, m in
            let op = max(0, 1 - now.timeIntervalSince(m.born) / (m.withheld ? 0.4 : 0.25))
            let y = g.size.height * (1 - CGFloat(max(0, min(1, m.vel))))
            if m.withheld {
                ZStack {
                    Rectangle().stroke(hueFor(m.col).opacity(op * 0.8), lineWidth: 1).frame(height: 3)
                    Rectangle().fill(claimAmber.opacity(op)).frame(width: 4, height: 3)
                }.position(x: g.size.width / 2, y: y)
            } else {
                Rectangle().fill(hueFor(m.col).opacity(op)).frame(height: 2).position(x: g.size.width / 2, y: y)
            }
        }
    }
}

// MARK: - RECEIVERS panel (delta §9 item 11) — the input twin of the EMITTERS panel

/// The four MIDI receivers as a strip panel above COLOUR: name + a cable stepper + a channel filter
/// (EDIT: ▲▼, OMNI…16) + an INPUT MUTE (both modes — "kill a live keyboard") + a LIVE input meter.
/// MPE is SILENT AUTO-DETECT (user ruling 2026-07-25) — no interface anywhere. Receiver colours are the
/// fixed "infrastructure family" (muted).
struct ReceiversView: View {
    let receivers: [Receiver]
    let editing: Bool
    var peak: [Double] = [0, 0, 0, 0]                                    // §9 item 11 input meter: latched peak (0–1)
    var peakAt: [Date] = Array(repeating: .distantPast, count: 4)
    var heldVels: [[Double]] = [[], [], [], []]         // duration: currently-held input velocities (steady marks while held)
    var thruReceiver: Int = 0                           // receiver strip: the THRU pip (passthrough source)
    let onSetChannel: (Int, Int) -> Void
    let onToggleMute: (Int) -> Void
    var onSetCable: (Int, Int?) -> Void = { _, _ in }   // §item 11: set a receiver's input cable (nil = ANY)
    var onSetThru: (Int) -> Void = { _ in }             // THRU pip radio
    // Feature overlays — present in the shell, wired by later increments (inert defaults here).
    var soloMask: UInt8 = 0                             // inc 2: additive SOLO set
    var onToggleSolo: (Int) -> Void = { _ in }
    var latchMask: UInt8 = 0                            // inc 5: per-receiver chord LATCH
    var onToggleLatch: (Int) -> Void = { _ in }
    var octave: [Int] = [0, 0, 0, 0]                   // inc 3: ephemeral ±octave nudge
    var onOct: (Int, Int) -> Void = { _, _ in }        // (receiver, ±1)
    var onVelOverride: (Int, Int?) -> Void = { _, _ in }   // inc 4: the slider's momentary input-velocity override
    var holdLatch: Bool = false                        // §5c HOLD latches the touched slider value

    @State private var faderVel: [Int?] = [nil, nil, nil, nil]   // the touched slider value (nil = released → springs back)

    static let controlHeight: CGFloat = 76             // fixed control region — faces swap within it (§6a static-frame law)

    private var hues: [Color] { receiverHues }
    private func r(_ i: Int) -> Receiver { i < receivers.count ? receivers[i] : Receiver(name: "\(i + 1)") }
    private func bit(_ mask: UInt8, _ i: Int) -> Bool { mask & (1 << UInt8(i)) != 0 }
    private func wrap(_ ch: Int) -> Int { ch < 0 ? 16 : (ch > 16 ? 0 : ch) }   // OMNI(0)…16, wraps
    // §item 11 INPUT CABLES: the v1 stepper cycles ANY · 1 · 2 · 3 · 4 (single cable or ANY).
    private func cableLabel(_ mask: Int?) -> String {
        guard let m = mask, m != 0b1111, m != 0 else { return "ANY" }
        for c in 1...4 where m == (1 << (c - 1)) { return "\(c)" }
        return "…"                                       // a subset (future UI) — the v1 stepper never makes one
    }
    private func cableStep(_ mask: Int?, _ delta: Int) -> Int? {
        let cur = (mask.flatMap { m in (1...4).first { m == (1 << ($0 - 1)) } }) ?? 0   // 0 = ANY, else cable N
        let next = ((cur + delta) % 5 + 5) % 5
        return next == 0 ? nil : (1 << (next - 1))       // nil ⇒ ANY; else the single-cable bit
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MIDI INPUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            HStack(alignment: .top, spacing: 4) { ForEach(0..<4, id: \.self) { strip($0) } }
        }
    }

    // The strip: header (hue dot + R-label + THRU pip) · control region (SLIDER | features, faces swap) ·
    // foot (MUTE · SOLO). A soloed receiver GLOWs; when a solo set exists, excluded strips dim.
    private func strip(_ i: Int) -> some View {
        let rec = r(i), muted = rec.muted, isThru = thruReceiver == i
        let soloed = bit(soloMask, i), excluded = soloMask != 0 && !soloed
        return VStack(spacing: 3) {
            HStack(spacing: 3) {
                Circle().fill(hues[i]).frame(width: 7, height: 7)
                Text(["A", "B", "C", "D"][i]).font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(muted ? .white.opacity(0.3) : .white.opacity(0.85))
                Spacer(minLength: 0)
                thruPip(i, isThru: isThru, muted: muted)
            }
            HStack(alignment: .top, spacing: 3) {
                slider(i).frame(width: 14).frame(maxHeight: .infinity)   // input meter + momentary velocity override
                if editing { editFeatures(i, rec) } else { performFeatures(i) }
            }
            .frame(height: Self.controlHeight)
            HStack(spacing: 3) {                                // foot: MUTE · SOLO
                footBtn(muted ? "MUTED" : "LIVE", lit: !muted, hue: hues[i], dim: muted) { onToggleMute(i) }
                footBtn("SOLO", lit: soloed, hue: soloHue, dim: excluded) { onToggleSolo(i) }
            }
        }
        .padding(4).frame(maxWidth: .infinity)
        .background(RoundedRectangle(cornerRadius: 6)
            .fill(muted ? Color.white.opacity(0.02) : hues[i].opacity(soloed ? 0.22 : 0.12)))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(soloed ? soloHue.opacity(0.8) : .clear, lineWidth: 1))
        .opacity(excluded ? 0.5 : 1)
    }

    private let soloHue = Color(red: 0.98, green: 0.72, blue: 0.12)

    // THRU pip — a radio dot across the strips: exactly one lit; tap moves passthrough here. Dim on a muted strip.
    private func thruPip(_ i: Int, isThru: Bool, muted: Bool) -> some View {
        HStack(spacing: 2) {
            if isThru { Text("THRU").font(.system(size: 6, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(muted ? 0.3 : 0.6)) }
            Circle().fill(isThru ? (muted ? Color.white.opacity(0.3) : hues[i]) : .clear)
                .frame(width: 9, height: 9)
                .overlay(Circle().stroke(.white.opacity(isThru ? 0 : 0.35), lineWidth: 1))
        }
        .contentShape(Rectangle()).onTapGesture { onSetThru(i) }
    }

    // EDIT face — the CABLE (ANY · 1–4) + CHANNEL (OMNI · 1–16) steppers (metering stays in the slider).
    private func editFeatures(_ i: Int, _ rec: Receiver) -> some View {
        VStack(spacing: 3) {
            HStack(spacing: 1) {
                stepBtn("chevron.down") { onSetCable(i, cableStep(rec.cable, -1)) }
                Text("IN \(cableLabel(rec.cable))").font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85)).frame(maxWidth: .infinity)
                stepBtn("chevron.up") { onSetCable(i, cableStep(rec.cable, +1)) }
            }
            HStack(spacing: 1) {
                stepBtn("chevron.down") { onSetChannel(i, wrap(rec.channel - 1)) }
                Text(rec.channel == 0 ? "OMNI" : "\(rec.channel)").font(.system(size: 7, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.85)).frame(maxWidth: .infinity)
                stepBtn("chevron.up") { onSetChannel(i, wrap(rec.channel + 1)) }
            }
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }

    // PERFORM face — LATCH toggle over OCT−/OCT+ (with the deviation readout). Inert until incs 3/5 wire them.
    private func performFeatures(_ i: Int) -> some View {
        let oct = i < octave.count ? octave[i] : 0
        return VStack(spacing: 2) {
            featBtn("LATCH", lit: bit(latchMask, i)) { onToggleLatch(i) }
            HStack(spacing: 2) {
                featBtn("OCT−", lit: false) { onOct(i, -1) }
                featBtn("OCT+", lit: false) { onOct(i, +1) }
            }
            Text(oct == 0 ? " " : (oct > 0 ? "+\(oct)" : "\(oct)"))
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(oct != 0 ? soloHue : .white.opacity(0.3))
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }

    private func featBtn(_ label: String, lit: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : .white.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? soloHue : Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    private func footBtn(_ label: String, lit: Bool, hue: Color, dim: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : .white.opacity(dim ? 0.4 : 0.7))
            .frame(maxWidth: .infinity).frame(height: 15)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? hue : Color.white.opacity(0.06)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    private func stepBtn(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 9, weight: .heavy)).foregroundColor(.white.opacity(0.6))
            .frame(width: 18, height: 16).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    // The SLIDER — the emitter fader's INPUT twin. Idle: the live input meter. Touched: a momentary-absolute
    // velocity override (drag = whisper/slam the receiver's subscribers), released → springs home (unless HOLD
    // latches). A bright set-point line marks the forced value while touched.
    private func slider(_ i: Int) -> some View {
        let touched = (i < faderVel.count ? faderVel[i] : nil) != nil
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
            let level = touched ? Double(faderVel[i] ?? 0) / 127.0 : decayed(i, now: tl.date)
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05))
                    if touched {                                   // OVERRIDE: the fill bottom-to-finger + set-point
                        Rectangle().fill(hues[i]).frame(height: g.size.height * CGFloat(level))
                        Rectangle().fill(Color.white).frame(height: 1.5).offset(y: -g.size.height * CGFloat(level) + 0.75)
                    } else {                                       // hold-while-ringing: a steady tick per currently-HELD input note (strip hue)
                        ForEach(Array((i < heldVels.count ? heldVels[i] : []).enumerated()), id: \.offset) { _, v in
                            Rectangle().fill(hues[i].opacity(0.85)).frame(height: 2)
                                .position(x: g.size.width / 2, y: g.size.height * (1 - CGFloat(max(0, min(1, v)))))
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let frac = 1.0 - min(1, max(0, v.location.y / g.size.height))
                    let val = max(1, Int(frac * 127))
                    if i < faderVel.count { faderVel[i] = val }; onVelOverride(i, val)
                }.onEnded { _ in
                    if holdLatch { return }                 // §5c: HOLD keeps the value; release drops it
                    if i < faderVel.count { faderVel[i] = nil }; onVelOverride(i, nil)
                })
            }
        }
    }

    private func decayed(_ i: Int, now: Date) -> Double {
        guard i < peak.count, i < peakAt.count else { return 0 }
        return peakHoldLevel(peak: peak[i], since: peakAt[i], now: now)
    }
}

/// OUTPUTS panel (delta §7/§7b): the fixed cable identities + each bus's stamp channel. Tap a bus's
/// channel to bump it (1…16 → wraps). Flags when two buses share a channel (their streams merge on
/// the All cable — legal, never blocked).
/// EMITTERS panel (delta §6a): the four pads ARE the emitters. Pad BODY = enable/disable TOGGLE in BOTH
/// modes (the per-output performance mute). In EDIT the CH caption is an OPENER for the channel popover
/// (1–16); in PERFORM CH is display-only. Disabled = recessed/dark. (Firing-flash animation deferred —
/// it needs a per-bus emit signal from the engine.)
/// EMITTERS panel (delta §6a rev — a7). A mode-aware, per-emitter CHANNEL-STRIP mixer that supersedes
/// the a2 caption-popover. Every emitter is a vertical strip: a TOGGLE pad on top (letter + live
/// metering flash, both modes) over a fixed-height control region — EDIT shows a dedicated CH stepper
/// (▲/▼, no popover, no selection state); PERFORM shows a velocity FADER + LED ladder (the momentary
/// absolute override — drag to whisper/slam the bus, release springs it back). Both faces fill the
/// SAME strip height, so the desk box never resizes across the mode flip (§6a static-frame law).
struct OutputsView: View {
    let busEnabled: [Bool]        // 4 flags (short/empty ⇒ enabled)
    let busChannels: [Int]        // 4 values, 1–16
    let editing: Bool
    var emitPeak: [Double] = [0, 0, 0, 0]                                  // §6a meter: latched peak (0–1)
    var emitPeakAt: [Date] = Array(repeating: .distantPast, count: 4)      // when latched (peak-hold decay)
    var marks: [[VelMark]] = [[], [], [], []]                             // item 4: floating output velocity marks (Colour-tinted)
    var claimMask: UInt8 = 0                                               // §6a CLAIM v2: the multi-claim mask (bits A–D)
    var claimLeak: [Int] = [0, 0, 0, 0]                                    // §6a CLAIM v2: per-claimant LEAK % (0…100)
    var holdLatch: Bool = false                                            // §5c: fader release latches (keeps the value)
    let onToggle: (Int) -> Void           // toggle pad → enable/disable emitter i (both modes)
    let onSetChannel: (Int, Int) -> Void  // EDIT stepper → set emitter i's stamp channel (1–16)
    var onVelOverride: (Int, Int?) -> Void = { _, _ in }   // PERFORM fader → force vel (1–127); nil = release
    var onClaim: (Int) -> Void = { _ in }                  // PERFORM CLAIM → toggle emitter i in/out of the claim set
    var onClaimLeak: (Int, Int) -> Void = { _, _ in }      // PERFORM CLAIM drag → set emitter i's LEAK % (0…100)
    var soloMask: UInt8 = 0                                 // foot SOLO — additive set (reuses soloEmitterMask)
    var onToggleSolo: (Int) -> Void = { _ in }
    var octave: [Int] = [0, 0, 0, 0]                       // E-2: ephemeral output ±octave nudge
    var onOct: (Int, Int) -> Void = { _, _ in }            // (emitter, ±1)
    var flattenMask: UInt8 = 0                             // role family: FLATTEN (activity ducking) set
    var flattenAmount: [Int] = [0, 0, 0, 0]
    var onToggleFlatten: (Int) -> Void = { _ in }
    var onFlattenAmount: (Int, Int) -> Void = { _, _ in }
    var altMask: UInt8 = 0                                 // role family: ALT (turn-taking) group
    var altCount: [Int] = [1, 1, 1, 1]
    var onToggleAlt: (Int) -> Void = { _ in }
    var onAltCount: (Int, Int) -> Void = { _, _ in }

    // Live fader value per emitter WHILE its slider is touched (nil = released → engine springs back).
    @State private var faderVel: [Int?] = [nil, nil, nil, nil]
    @State private var roleDragBase: [Int?] = [nil, nil, nil, nil]   // role-button param value captured at drag start
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let letters = ["A", "B", "C", "D"]             // emitters A–D (box title MIDI OUTPUT disambiguates from inputs)
    private let controlHeight: CGFloat = 78   // the EDIT stepper / PERFORM fader region — identical both modes

    private func on(_ i: Int) -> Bool { i < busEnabled.count ? busEnabled[i] : true }
    private func ch(_ i: Int) -> Int { i < busChannels.count ? busChannels[i] : i + 1 }
    private func sharedWithEnabled(_ i: Int) -> Bool {
        on(i) && (0..<4).contains { $0 != i && on($0) && ch($0) == ch(i) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MIDI OUTPUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            HStack(alignment: .top, spacing: 4) { ForEach(0..<4, id: \.self) { strip($0) } }
        }
        .onChange(of: holdLatch) { latched in            // §5c: HOLD-off = the drop → every fader springs home
            if !latched { for i in 0..<4 { faderVel[i] = nil; onVelOverride(i, nil) } }
        }
    }

    // One emitter strip — the receiver strip's twin anatomy: header (dot + E-label + ch) · SLIDER | role
    // column (CLAIM/OCT in PERFORM, CHANNEL stepper in EDIT) · foot MUTE·SOLO. A soloed strip glows;
    // excluded strips dim. Both faces fill `controlHeight`, so the frame is identical across the mode flip.
    private func strip(_ i: Int) -> some View {
        let muted = !on(i), soloed = bit(soloMask, i), excluded = soloMask != 0 && !soloed
        return VStack(spacing: 3) {
            header(i, muted: muted)
            HStack(alignment: .top, spacing: 3) {
                fader(i).frame(width: 16).frame(maxHeight: .infinity)
                if editing { channelStepper(i) } else { roleColumn(i) }
            }
            .frame(height: controlHeight)
            HStack(spacing: 3) {                             // foot: MUTE (the enable gate) · SOLO
                footBtn(muted ? "MUTED" : "LIVE", lit: !muted, hue: cyan, dim: muted) { onToggle(i) }
                footBtn("SOLO", lit: soloed, hue: amber, dim: excluded) { onToggleSolo(i) }
            }
        }
        .frame(maxWidth: .infinity)
        .opacity(excluded ? 0.5 : 1)
    }

    private func bit(_ mask: UInt8, _ i: Int) -> Bool { mask & (1 << UInt8(i)) != 0 }

    // Header: enable dot + E-label + the stamp channel (amber when shared with another enabled emitter).
    private func header(_ i: Int, muted: Bool) -> some View {
        HStack(spacing: 3) {
            Circle().fill(muted ? Color.white.opacity(0.25) : cyan).frame(width: 7, height: 7)
            Text(letters[i]).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(muted ? .white.opacity(0.3) : .white.opacity(0.85))
            Spacer(minLength: 0)
            Text("ch\(ch(i))").font(.system(size: 8, weight: .heavy, design: .monospaced))
                .foregroundColor(sharedWithEnabled(i) ? amber : .white.opacity(0.5))
        }
    }

    // PERFORM role column: CLAIM (existing radio) + OCT−/OCT+. FLATTEN + ALT are DEFERRED (the role family is
    // gated behind the single-CLAIM device pass — spec 2026-07-26); their slots join here once CLAIM is trusted.
    private func roleColumn(_ i: Int) -> some View {
        let oct = i < octave.count ? octave[i] : 0
        let claimOn = claimMask & (1 << UInt8(i)) != 0
        let leak = i < claimLeak.count ? claimLeak[i] : 0
        let flatOn = flattenMask & (1 << UInt8(i)) != 0
        let flatAmt = i < flattenAmount.count ? flattenAmount[i] : 0
        let altOn = altMask & (1 << UInt8(i)) != 0
        let altN = i < altCount.count ? altCount[i] : 1
        return VStack(spacing: 2) {
            // CLAIM: tap toggles membership; drag sets LEAK % (0 = hard suppression, shown as plain "CLAIM").
            roleButton(i, label: "CLAIM", on: claimOn, value: leak, maxValue: 100,
                       onToggle: { onClaim(i) }, onDrag: { onClaimLeak(i, $0) })
            roleButton(i, label: "FLAT", on: flatOn, value: flatAmt, maxValue: 100,
                       onToggle: { onToggleFlatten(i) }, onDrag: { onFlattenAmount(i, $0) })
            roleButton(i, label: "ALT", on: altOn, value: altN > 1 ? altN : 0, maxValue: 8,
                       onToggle: { onToggleAlt(i) }, onDrag: { onAltCount(i, max(1, $0)) })
            HStack(spacing: 2) {
                octBtn("OCT−") { onOct(i, -1) }
                octBtn("OCT+") { onOct(i, +1) }
            }
            Text(oct == 0 ? " " : (oct > 0 ? "+\(oct)" : "\(oct)"))
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(oct != 0 ? amber : .white.opacity(0.3))
            Spacer(minLength: 0)
        }.frame(maxWidth: .infinity)
    }

    // A ROLE BUTTON — the shared grammar for the role family: TAP toggles `on`; a VERTICAL DRAG sets its one
    // parameter (relative to the value at drag start; up = more). Shows "LABEL n" when on and the value ≠ 0.
    private func roleButton(_ i: Int, label: String, on: Bool, value: Int, maxValue: Int,
                            onToggle: @escaping () -> Void, onDrag: @escaping (Int) -> Void) -> some View {
        Text(on && value != 0 ? "\(label) \(value)" : label)
            .font(.system(size: 7, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.65))
            .frame(maxWidth: .infinity).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? amber : Color.white.opacity(0.08)))
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .onChanged { v in
                    if roleDragBase[i] == nil { roleDragBase[i] = value }
                    if abs(v.translation.height) > 4 {
                        onDrag(max(0, min(maxValue, (roleDragBase[i] ?? value) + Int(-v.translation.height / 2))))
                    }
                }
                .onEnded { v in
                    let wasDrag = abs(v.translation.height) > 4
                    roleDragBase[i] = nil
                    if !wasDrag { onToggle() }
                })
    }
    private func octBtn(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    private func footBtn(_ label: String, lit: Bool, hue: Color, dim: Bool, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced))
            .foregroundColor(lit ? .black : .white.opacity(dim ? 0.4 : 0.7))
            .frame(maxWidth: .infinity).frame(height: 15)
            .background(RoundedRectangle(cornerRadius: 3).fill(lit ? hue : Color.white.opacity(0.06)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    // EDIT — a dedicated per-emitter channel stepper (▲/▼, wrapping 1–16). Replaces the a2 popover;
    // no selection state, no floating layer. Amber number = shares a channel with another enabled emitter.
    private func channelStepper(_ i: Int) -> some View {
        let enabled = on(i)
        return VStack(spacing: 0) {
            stepButton("chevron.up") { stepChannel(i, +1) }
            Text("\(ch(i))").font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundColor(enabled ? (sharedWithEnabled(i) ? amber : cyan) : .white.opacity(0.35))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            stepButton("chevron.down") { stepChannel(i, -1) }
        }
        .frame(maxWidth: .infinity).frame(height: controlHeight)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
        .overlay(alignment: .bottom) {
            Text("ch").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.25)).padding(.bottom, 1)
        }
    }
    private func stepButton(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 11, weight: .heavy))
            .foregroundColor(.white.opacity(0.6)).frame(maxWidth: .infinity).frame(height: 20)
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    private func stepChannel(_ i: Int, _ delta: Int) {
        var n = ch(i) + delta
        if n > 16 { n = 1 }; if n < 1 { n = 16 }
        onSetChannel(i, n)
    }

    // PERFORM — a vertical velocity fader with an 8-segment LED ladder. Idle: the ladder tracks the live
    // meter (decaying). Touched: it shows the forced value and a bright set-point line; drag maps y →
    // 1–127, release springs back (fader → nil, engine → natural velocity). Disabled emitter = greyed.
    private func fader(_ i: Int) -> some View {
        let enabled = on(i)
        return GeometryReader { g in
            let h = g.size.height
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
                let touched = faderVel[i] != nil
                let level = touched ? Double(faderVel[i]!) / 127.0 : decayed(i, now: tl.date)
                faderBody(i: i, level: level, touched: touched, enabled: enabled, now: tl.date)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        guard enabled else { return }
                        let frac = 1 - min(1, max(0, v.location.y / max(1, h)))
                        let val = max(1, Int((frac * 127).rounded()))
                        faderVel[i] = val
                        onVelOverride(i, val)
                    }
                    .onEnded { _ in
                        if holdLatch { return }             // §5c HOLD: latch at the released value (keep it)
                        faderVel[i] = nil
                        onVelOverride(i, nil)               // else spring back to natural velocity
                    }
            )
        }
        .frame(maxHeight: .infinity)   // fills the region above the CLAIM footer
    }


    // OVERRIDE (touched) = the LED-ladder FILL bottom-to-finger + set-point; PASSIVE (idle) = item-4 floating
    // velocity MARKS, each tinted in its source cell's Colour (who struck, how hard). Disabled = greyed.
    private func faderBody(i: Int, level: Double, touched: Bool, enabled: Bool, now: Date) -> some View {
        let segs = 8
        let lit = Int((Double(segs) * level).rounded(.up))
        return ZStack {
            if touched {
                VStack(spacing: 2) {
                    ForEach(0..<segs, id: \.self) { row in
                        let j = segs - 1 - row
                        let isLit = enabled && j < lit
                        let hot = j >= segs - 2
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(isLit ? (hot ? amber : cyan) : Color.white.opacity(enabled ? 0.08 : 0.04))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .overlay(alignment: .center) { if j == lit - 1 { Rectangle().fill(Color.white).frame(height: 2) } }
                    }
                }
            } else if enabled {
                velMarkLayer(i < marks.count ? marks[i] : [], now: now) { col in emitterHue(col) }
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.04)))
        .overlay(alignment: .bottom) {
            Text(enabled ? (touched ? "\(faderVel[i]!)" : "ch \(ch(i))") : "off")
                .font(.system(size: 7, weight: .heavy, design: .monospaced))
                .foregroundColor(holdLatch && touched ? amber : .white.opacity(touched ? 0.7 : 0.25))  // §5c HELD cue
                .padding(.bottom, 1)
        }
    }
    // item 4: a mark's tint = its source cell's Colour (−1 / out of range → the emitter cyan).
    private func emitterHue(_ col: Int8) -> Color {
        (col >= 0 && Int(col) < colourIDs.count) ? (colourColor(colourIDs[Int(col)]) ?? cyan) : cyan
    }

    private func decayed(_ i: Int, now: Date) -> Double {
        guard i < emitPeak.count, i < emitPeakAt.count else { return 0 }
        return peakHoldLevel(peak: emitPeak[i], since: emitPeakAt[i], now: now)   // ~150ms peak-hold decay
    }
}

/// MASTER PANEL (design item 3) — the bottom-right console corner, anatomy mirroring the strips: the SUM
/// METER behind a master velocity FADER (momentary-absolute over all output; spring / §5c HOLD-latch) beside
/// a feature column — MUTE (tap = kill · long-press = PANIC) · KEY −/+ (per-scene transpose). REVERT + INS are
/// reserved seats (snapshot + wire work). Fader = weather; MUTE/KEY = structure. NO SOLO (solo against nothing).
struct MasterView: View {
    let mute: Bool
    let key: Int
    var peak: Double = 0                                   // the sum meter (max of the emitter peaks)
    var peakAt: Date = .distantPast
    var marks: [VelMark] = []                              // item 4: the sum's velocity marks (Colour-tinted, capped)
    var holdLatch: Bool = false
    let onMute: () -> Void
    let onPanic: () -> Void
    let onKey: (Int) -> Void
    var onVelOverride: (Int?) -> Void = { _ in }

    @State private var faderVel: Int? = nil
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)
    private let red = Color(red: 0.98, green: 0.35, blue: 0.3)
    static let controlHeight: CGFloat = 92

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("MASTER").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            HStack(alignment: .top, spacing: 3) {
                fader.frame(width: 16).frame(maxHeight: .infinity)
                VStack(spacing: 2) {
                    Text(mute ? "MUTED" : "MUTE").font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(mute ? .black : .white.opacity(0.7))
                        .frame(maxWidth: .infinity).frame(height: 16)
                        .background(RoundedRectangle(cornerRadius: 3).fill(mute ? red : Color.white.opacity(0.08)))
                        .contentShape(Rectangle())
                        .onLongPressGesture(minimumDuration: 0.6) { onPanic() }
                        .simultaneousGesture(TapGesture().onEnded { onMute() })
                    HStack(spacing: 2) { keyBtn("KEY−") { onKey(-1) }; keyBtn("KEY+") { onKey(+1) } }
                    Text(key == 0 ? "KEY 0" : "KEY \(key > 0 ? "+" : "")\(key)")
                        .font(.system(size: 7, weight: .heavy, design: .monospaced))
                        .foregroundColor(key != 0 ? amber : .white.opacity(0.3))
                    HStack(spacing: 2) { seat("REVERT"); seat("INS") }   // reserved seats (item 7 / item 14)
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity)
            }.frame(height: Self.controlHeight)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // The master fader: idle shows the sum meter; touched forces velocity over ALL output (spring / HOLD-latch).
    private var fader: some View {
        let touched = faderVel != nil
        return TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
            let level = touched ? Double(faderVel ?? 0) / 127.0 : peakHoldLevel(peak: peak, since: peakAt, now: tl.date)
            GeometryReader { g in
                ZStack(alignment: .bottom) {
                    RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.05))
                    if touched {                                   // OVERRIDE: the fill over the sum + set-point
                        Rectangle().fill(amber).frame(height: g.size.height * CGFloat(level))
                        Rectangle().fill(Color.white).frame(height: 1.5).offset(y: -g.size.height * CGFloat(level) + 0.75)
                    } else {                                       // item 4: the sum's velocity marks (Colour-tinted)
                        velMarkLayer(marks, now: tl.date) { col in
                            (col >= 0 && Int(col) < colourIDs.count) ? (colourColor(colourIDs[Int(col)]) ?? cyan) : cyan
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 4)).contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                    let frac = 1.0 - min(1, max(0, v.location.y / g.size.height))
                    faderVel = max(1, Int(frac * 127)); onVelOverride(faderVel)
                }.onEnded { _ in
                    if holdLatch { return }
                    faderVel = nil; onVelOverride(nil)
                })
            }
        }
    }
    private func keyBtn(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7))
            .frame(maxWidth: .infinity).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    private func seat(_ label: String) -> some View {   // a reserved (inert) seat — dim, non-interactive
        Text(label).font(.system(size: 6, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.22))
            .frame(maxWidth: .infinity).frame(height: 13)
            .background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.03)))
    }
}

/// CONTROLS PANEL (design item 2) — the top-left flank tenant, "how time runs," beside the MIDI INPUT band.
/// STEP rate + SWING (the scene-level timing, AUParameters 0/1) + HOLD (the §5c gesture latch — big, "it's a
/// mode; modes get corners"). Moved out of the header, which slims to logo · EDIT/PERFORM · undo/redo.
struct ControlsView: View {
    let stepIndex: Int
    let swing: Int
    let holdLatch: Bool
    let editing: Bool
    let onStep: (Int) -> Void
    let onSwing: (Int) -> Void
    let onToggleHold: () -> Void
    private let stepLabels = ["2/1", "1/1", "1/2", "1/2.", "1/4", "1/8"]
    private let accent = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CONTROLS").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            VStack(alignment: .leading, spacing: 3) {
                Text("STEP").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                ForEach(0..<2, id: \.self) { row in
                    HStack(spacing: 3) {
                        ForEach(0..<3, id: \.self) { col in
                            let i = row * 3 + col
                            Text(stepLabels[i]).font(.system(size: 8, weight: .heavy, design: .monospaced))
                                .foregroundColor(i == stepIndex ? .black : .white.opacity(0.6))
                                .frame(maxWidth: .infinity).frame(height: 20)
                                .background(RoundedRectangle(cornerRadius: 3).fill(i == stepIndex ? accent : Color.white.opacity(0.08)))
                                .contentShape(Rectangle()).onTapGesture { onStep(i) }
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("SWING \(swing)").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                Slider(value: Binding(get: { Double(swing) }, set: { onSwing(Int($0.rounded())) }), in: 50...75).tint(accent)
            }
            // HOLD — big, PERFORM's gesture latch (dim/inactive in EDIT; the latch only bites while performing).
            Text("HOLD").font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(holdLatch ? .black : .white.opacity(editing ? 0.3 : 0.7))
                .frame(maxWidth: .infinity).frame(height: 34)
                .background(RoundedRectangle(cornerRadius: 5).fill(holdLatch ? amber : Color.white.opacity(0.08)))
                .contentShape(Rectangle()).onTapGesture { if !editing { onToggleHold() } }
            Spacer(minLength: 0)
        }
        .padding(8).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }
}

/// HEADER (delta §6): logotype · STEP rate · SWING · PASS/transport readout. STEP/SWING are the
/// scene-level timing controls (AUParameters 0/1) — the only in-plugin way to set them.
/// §5b COLUMN-SUBSET LAP — the multi-column HOLD gesture. A `UIView` (not a SwiftUI gesture) because
/// SwiftUI can't reliably track SIMULTANEOUS touches across the sibling column keys; this one view
/// receives every touch, maps each to a column, and reports the held-column BITMASK. Being UIKit, it
/// SURVIVES SwiftUI re-renders — so the 4 Hz poll can never tear a hold down mid-gesture. Only mounted
/// in PERFORM; unmounting (mode switch) cancels its touches → the parent gets mask 0.
private struct ColumnHoldOverlay: UIViewRepresentable {
    let gap: CGFloat
    var latched: Bool = false          // §5c HOLD: column keys become membership TOGGLES (editable lap set)
    let onChange: (UInt8) -> Void

    func makeUIView(context: Context) -> TouchRow { let v = TouchRow(); v.gap = gap; v.onChange = onChange; v.latched = latched; return v }
    func updateUIView(_ v: TouchRow, context: Context) { v.gap = gap; v.onChange = onChange; v.latched = latched }

    final class TouchRow: UIView {
        var gap: CGFloat = 3
        var onChange: ((UInt8) -> Void)?
        // §5c: while latched, a TAP toggles a column's membership and the set persists (release does
        // nothing). HOLD-on GRADUATES the currently-held columns into the set; HOLD-off clears it (the
        // VC also drops the engine lap). Momentary hold is the un-latched behaviour, unchanged.
        var latched: Bool = false {
            didSet { if latched != oldValue { latchedMask = latched ? currentTouchMask() : 0 } }
        }
        private var latchedMask: UInt8 = 0
        private var active: Set<UITouch> = []

        override init(frame: CGRect) { super.init(frame: frame); isMultipleTouchEnabled = true; backgroundColor = .clear }
        required init?(coder: NSCoder) { fatalError("no coder") }

        private func column(_ t: UITouch) -> Int? {
            let w = bounds.width; guard w > 0 else { return nil }
            let stride = (w + gap) / 8            // per-key stride: 8 keys + 7 inter-key gaps ⇒ (w+gap)/8
            let c = Int((t.location(in: self).x / stride).rounded(.down))
            return (c >= 0 && c < 8) ? c : nil
        }
        private func currentTouchMask() -> UInt8 {
            var mask: UInt8 = 0
            for t in active where t.phase != .ended && t.phase != .cancelled {
                if let c = column(t) { mask |= 1 << UInt8(c) }
            }
            return mask
        }
        private func report() { onChange?(latched ? latchedMask : currentTouchMask()) }

        override func touchesBegan(_ ts: Set<UITouch>, with e: UIEvent?) {
            active.formUnion(ts)
            if latched { for t in ts { if let c = column(t) { latchedMask ^= (1 << UInt8(c)) } } }   // tap = toggle
            report()
        }
        override func touchesMoved(_ ts: Set<UITouch>, with e: UIEvent?)     { if !latched { report() } }
        override func touchesEnded(_ ts: Set<UITouch>, with e: UIEvent?)     { active.subtract(ts); if !latched { report() } }
        override func touchesCancelled(_ ts: Set<UITouch>, with e: UIEvent?) { active.subtract(ts); if !latched { report() } }
    }
}

struct HeaderView: View {
    let playing: Bool
    let pass: Int
    let tempo: Double
    let editing: Bool           // EDIT vs PERFORM mode
    let onToggleMode: () -> Void
    var canUndo = false                 // delta §5 / a6 — EDIT-mode undo/redo
    var canRedo = false
    var onUndo: () -> Void = {}
    var onRedo: () -> Void = {}
    var onSecretTap: () -> Void = {}    // dev-build: a hidden long-press on the logotype reveals the T-session loader
    // STEP · SWING · HOLD moved to the CONTROLS flank; FLOW to the VISUALIZATION flank; the build stamp was
    // retired — so the header carries only the logotype, mode toggle, undo/redo, and the PASS/bpm readout.

    private let accent = Color(red: 0.15, green: 0.88, blue: 0.94)         // PERFORM / cyan
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)          // EDIT

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("8×8 STATE").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(4)
                .foregroundColor(.white.opacity(0.85))
                .onLongPressGesture(minimumDuration: 1.2) { onSecretTap() }   // dev: reveal the T-session loader

            // EDIT / PERFORM mode (§6.1/6.2)
            HStack(spacing: 2) {
                modeChip("EDIT", on: editing, hue: amber)
                modeChip("PERFORM", on: !editing, hue: accent)
            }
            .onTapGesture { onToggleMode() }

            // delta §5 / a6: undo/redo — EDIT only (undoing mid-performance is surprising, spec scope-lean).
            // STEP · SWING · HOLD moved to the CONTROLS flank panel (item 2 — the header slimmed).
            if editing {
                HStack(spacing: 3) {
                    headerIcon("arrow.uturn.backward", enabled: canUndo, action: onUndo)
                    headerIcon("arrow.uturn.forward", enabled: canRedo, action: onRedo)
                }
            }

            // FLOW retired into the VISUALIZATION flank thumbnail (item 2 — the picture is the button).

            Spacer()

            if playing {
                Text(String(format: "PASS %d · %.1f bpm", pass + 1, tempo))
                    .font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(accent)
            }
        }
    }

    private func headerIcon(_ name: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: name).font(.system(size: 11, weight: .heavy))
            .foregroundColor(enabled ? .white.opacity(0.75) : .white.opacity(0.2))
            .frame(width: 26, height: 22)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.06)))
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }

    private func modeChip(_ label: String, on: Bool, hue: Color) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.5))
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? hue : Color.white.opacity(0.08)))
    }
}

/// A PROCESSOR PANEL (delta item 8, TWO-PROCESSOR Colours): one self-contained editor for ONE face of the
/// selected Colour (= the palette brush) — the A face or the optional B face. Title row (PROCESSOR A/B +
/// COPY, and PASTE when the clipboard holds a processor) · type selector (A = 6 types; B = OFF + 6, OFF =
/// B-less) · TRANSPOSE + the full param set INLINE + (B only) the MORPH fader when B is a FULL glide.
/// FIXED frame sized for the largest (arp) field set, so truncation dies by geometry. A transpose/morph are
/// AUParameters (own callbacks); B's transpose + all params go through editColour. COPY/PASTE let any panel
/// lift a processor and drop it onto any other (cross-type paste retypes the target).
struct ProcessorBox: View {
    enum Face { case a, b }
    let colour: Colour
    let colourIndex: Int
    var face: Face = .a
    let onEdit: (@escaping (inout Colour) -> Void) -> Void
    let onTranspose: (Int) -> Void                      // A face: transpose is an AUParameter
    let onMorph: (Double) -> Void
    var onSetTypeA: ((ProcessorType) -> Void)? = nil    // A face: switchType via the AU (per-type stash)
    var canPaste: Bool = false                          // clipboard non-empty ⇒ show PASTE
    var onCopy: () -> Void = {}
    var onPaste: () -> Void = {}

    static let panelHeight: CGFloat = 300               // fixed — sized for the largest field set + morph

    private var isB: Bool { face == .b }
    private var accent: Color { colourColor(colour.colourID) ?? .gray }
    private var faceType: ProcessorType? { isB ? colour.typeB : colour.type }   // B may be nil = B-less
    private var p: ColourParams { isB ? colour.paramsB : colour.paramsA }
    private var faceTranspose: Int { isB ? colour.transposeBResolved : colour.transpose }
    private var glides: Bool { colour.typeB == colour.type }   // FULL morph ⇔ B is the same type as A
    private func setParam(_ f: @escaping (inout ColourParams) -> Void) {
        onEdit { c in if isB { f(&c.paramsB) } else { f(&c.paramsA) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            titleRow
            typeSelector
            if let ft = faceType {
                field("TRANSPOSE \(faceTranspose > 0 ? "+" : "")\(faceTranspose)") {
                    stepper(faceTranspose, -24, 24) { v in
                        if isB { onEdit { $0.transposeB = v } } else { onTranspose(v) }
                    }
                }
                typeParams(ft)
                if isB && glides {                       // morph glides A↔B; only meaningful for a FULL B
                    field("MORPH \(Int(colour.morph * 100))%  → B") {
                        Slider(value: Binding(get: { colour.morph }, set: { onMorph($0) }), in: 0...1).tint(accent)
                    }
                }
            } else {
                Text("no B — pick a type or PASTE to add a second processor")
                    .font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.4)).padding(.top, 4)
            }
            Spacer(minLength: 0)
        }
        .padding(8).frame(height: Self.panelHeight, alignment: .top).clipped()
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    private var titleRow: some View {
        HStack(spacing: 5) {
            Text(isB ? "PROCESSOR B" : "PROCESSOR A")
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
            Spacer()
            if faceType != nil { pill("COPY", onCopy) }
            if canPaste { pill("PASTE", onPaste) }
        }
    }

    // A face = the 6 types; B face = OFF (B-less) + the 6 types (pick a type to create B, OFF to remove it).
    @ViewBuilder private var typeSelector: some View {
        if isB {
            seg(["OFF"] + ProcessorType.allCases.map { typeShort($0) }, sel: colour.typeB.map { typeShort($0) } ?? "OFF") { i in
                if i == 0 { onEdit { $0.typeB = nil } } else { onEdit { $0.typeB = ProcessorType.allCases[i - 1] } }
            }
        } else {
            seg(ProcessorType.allCases.map { typeShort($0) }, sel: typeShort(colour.type)) { i in
                onSetTypeA?(ProcessorType.allCases[i])
            }
        }
    }

    private func pill(_ label: String, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(accent)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(RoundedRectangle(cornerRadius: 3).fill(accent.opacity(0.18)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }

    @ViewBuilder private func typeParams(_ ft: ProcessorType) -> some View {
        switch ft {
        case .arp:
            field("PATTERN") { seg(ArpPattern.allCases.map(\.rawValue), sel: p.pattern?.rawValue ?? "UP") { i in
                setParam { $0.pattern = ArpPattern.allCases[i] } } }
            field("RATE") { seg(ArpRate.allCases.map(\.rawValue), sel: p.rate?.rawValue ?? "1/16") { i in
                setParam { $0.rate = ArpRate.allCases[i] } } }
            HStack(spacing: 8) {
                field("OCT") { seg(["1","2","3","4"], sel: "\(p.octaves ?? 1)") { i in
                    setParam { $0.octaves = i + 1 } } }
                field("PHASE") { seg(ArpPhase.allCases.map(\.rawValue), sel: p.phase?.rawValue ?? "RETRIG") { i in
                    setParam { $0.phase = ArpPhase.allCases[i] } } }
            }
            field("GATE \(Int((p.gate ?? 0.6) * 100))%") {
                Slider(value: bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1).tint(accent)
            }
        case .ratchet:
            field("REPEATS") { seg(["2","3","4","6","8"], sel: "\(p.count ?? 3)") { i in
                setParam { $0.count = [2,3,4,6,8][i] } } }
            field("RAMP \(Int((p.ramp ?? 0.5) * 100))%") {
                Slider(value: bind(p.ramp ?? 0.5) { v in setParam { $0.ramp = v } }, in: 0...1).tint(accent)
            }
        case .passgate:
            field("PASSES") { HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { i in
                    let on = (p.passes ?? [true,true,true,true])[i]
                    Text("\(i+1)").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 22)
                        .background(RoundedRectangle(cornerRadius: 4).fill(on ? accent : Color.white.opacity(0.1)))
                        .onTapGesture { setParam { var pp = $0.passes ?? [true,true,true,true]; pp[i].toggle(); $0.passes = pp } }
                }
            } }
        case .strum:
            field("DIR") { seg(StrumDir.allCases.map(\.rawValue), sel: (p.strumDir ?? .up).rawValue) { i in
                setParam { $0.strumDir = StrumDir.allCases[i] } } }
            field("SPREAD \(Int((p.spread ?? 0.1) * 100))") {
                Slider(value: bind(p.spread ?? 0.1) { v in setParam { $0.spread = v } }, in: 0...1).tint(accent) }
            field("TILT \(Int((p.velTilt ?? 0) * 100))") {
                Slider(value: bind((p.velTilt ?? 0) / 2 + 0.5) { v in setParam { $0.velTilt = (v - 0.5) * 2 } }, in: 0...1).tint(accent) }
        case .chance:
            field("PROBABILITY \(Int((p.probability ?? 1) * 100))%") {
                Slider(value: bind(p.probability ?? 1) { v in setParam { $0.probability = v } }, in: 0...1).tint(accent) }
        case .harmonize:
            let iv = p.harmIntervals ?? [0,0,0]
            ForEach(0..<3, id: \.self) { k in
                field("VOICE \(k+1) \(iv[k] == 0 ? "off" : (iv[k] > 0 ? "+\(iv[k])" : "\(iv[k])"))") {
                    stepper(iv[k], -24, 24) { v in setParam { var a = $0.harmIntervals ?? [0,0,0]; a[k] = v; $0.harmIntervals = a } }
                }
            }
        }
    }

    // ---- small controls ----
    private func typeShort(_ t: ProcessorType) -> String {
        switch t { case .arp: "ARP"; case .ratchet: "RTC"; case .passgate: "PASS"
        case .strum: "STRM"; case .chance: "CHNC"; case .harmonize: "HARM" }
    }
    private func bind(_ v: Double, _ set: @escaping (Double) -> Void) -> Binding<Double> {
        Binding(get: { v }, set: set)
    }
    private func field<C: View>(_ label: String, @ViewBuilder _ content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            content()
        }
    }
    private func seg(_ options: [String], sel: String, _ onPick: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, o in
                Text(o).font(.system(size: 7.5, weight: .heavy, design: .monospaced))
                    .foregroundColor(o == sel ? .black : .white.opacity(0.7))
                    .frame(maxWidth: .infinity).frame(height: 18)
                    .background(RoundedRectangle(cornerRadius: 3).fill(o == sel ? accent : Color.white.opacity(0.08)))
                    .onTapGesture { onPick(i) }
            }
        }
    }
    private func stepper(_ v: Int, _ lo: Int, _ hi: Int, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            Text("−").font(.system(size: 13, weight: .heavy)).foregroundColor(.white.opacity(0.7))
                .frame(width: 26, height: 20).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
                .onTapGesture { set(max(lo, v - 1)) }
            Text("\(v)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.9)).frame(minWidth: 30)
            Text("+").font(.system(size: 13, weight: .heavy)).foregroundColor(.white.opacity(0.7))
                .frame(width: 26, height: 20).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
                .onTapGesture { set(min(hi, v + 1)) }
            Spacer()
        }
    }
}

/// The Colour brush palette — 16 chips in bank order; the active brush is ringed.
struct PaletteView: View {
    let brush: String
    var columns: Int = 4        // 4×4 in the desk (delta §6); callers may widen for a band
    // delta §6b — COLOUR-chip ACTIVITY PLAYHEADS: a chip sweeps while its Colour works in the live
    // column (mirrors the cell mutation-line condition + faint-when-only-bypassed). Orientation encodes
    // the face: TOP→BOTTOM for main, LEFT→RIGHT for alt-only (main wins mixed). One-clock: the sweep is
    // a pure function of the derived beat fraction (same TimelineView + liveBeat as the cell lines).
    var scene: SceneState = .empty()
    var playColumn: Int = -1
    var playing: Bool = false
    var beat: Double = 0
    var tempo: Double = 120
    var stepBeats: Double = 2
    var swing: Int = 50
    let onPick: (String) -> Void
    var onChipDrag: ((String, CGPoint) -> Void)? = nil    // §5 palette-to-grid: chip drag (id, global point)
    var onChipDrop: ((String, CGPoint) -> Void)? = nil    // §5 palette-to-grid: chip drop (id, global point)
    var onLongPress: ((String) -> Void)? = nil            // cell-edit staging: long-press → stage a cell of this Colour
    var stagingID: String? = nil                          // cell-edit staging: the staged chip pulses + wears the moving outline

    @State private var lastBeat: Double = 0
    @State private var lastBeatAt = Date()
    private func liveBeat(_ now: Date) -> Double { playing ? lastBeat + now.timeIntervalSince(lastBeatAt) * tempo / 60.0 : lastBeat }

    /// Is this Colour working in the live column? → (faint = all working instances bypassed, alt = no
    /// main instance i.e. alt-only). nil = not working. ONE sweep per Colour regardless of instance count.
    private func activity(_ id: String) -> (faint: Bool, alt: Bool)? {
        guard playing, playColumn >= 0, playColumn < scene.cells.count else { return nil }
        var working = false, hasMain = false, hasBright = false
        for r in 0..<8 where r < scene.cells[playColumn].count {
            guard let c = scene.cells[playColumn][r], c.colourID == id, !c.muted else { continue }
            working = true
            if !c.alt { hasMain = true }
            if !c.bypassed { hasBright = true }
        }
        return working ? (faint: !hasBright, alt: !hasMain) : nil
    }

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(Array(colourIDs.enumerated()), id: \.offset) { i, id in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: colourHexes[i]))
                    .frame(height: 22)
                    .overlay { if let a = activity(id) { chipSweep(a) } }   // §6b activity playhead
                    .overlay { if stagingID == id { stagedPulse } }         // staging: pulse original↔black to draw the eye back
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(id == brush ? Color.white : Color.white.opacity(0.12),
                                lineWidth: id == brush ? 2 : 0.5))
                    .marchingAnts(stagingID == id, color: Color(hex: colourHexes[i]), cornerRadius: 3)   // staging: moving outline in the Colour's own hue
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(id) }
                    .simultaneousGesture(                        // §5: drag a chip onto the grid (min-dist so tap is safe)
                        DragGesture(minimumDistance: 16, coordinateSpace: .global)
                            .onChanged { v in onChipDrag?(id, v.location) }
                            .onEnded { v in onChipDrop?(id, v.location) }
                    )
                    .simultaneousGesture(                        // cell-edit staging: press-hold (no move) → stage this Colour
                        LongPressGesture(minimumDuration: 0.45).onEnded { _ in onLongPress?(id) }
                    )
            }
        }
        .onChange(of: beat) { newBeat in lastBeat = newBeat; lastBeatAt = Date() }
    }

    // Staging pulse — the staged chip breathes from its original colour to black (~0.85s) to pull the eye
    // back to the long-press gesture. A black overlay whose opacity rides a cosine; pure UI.
    private var stagedPulse: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
            let f = stagingPulseFraction(tl.date, period: 0.85)
            RoundedRectangle(cornerRadius: 3).fill(Color.black).opacity(f * 0.85)
        }
        .allowsHitTesting(false)
    }

    private func chipSweep(_ a: (faint: Bool, alt: Bool)) -> some View {
        GeometryReader { g in
            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !playing)) { tl in
                let f = CGFloat(columnSweepFraction(realBeat: liveBeat(tl.date), stepBeats: stepBeats, swing: swing))
                Rectangle()
                    .fill(Color.white.opacity(a.faint ? 0.35 : 0.9))
                    .shadow(color: a.faint ? .clear : Color.white.opacity(0.7), radius: a.faint ? 0 : 2)
                    .frame(width: a.alt ? 2 : g.size.width, height: a.alt ? g.size.height : 2)
                    .position(x: a.alt ? f * g.size.width : g.size.width / 2,      // alt: LEFT→RIGHT
                              y: a.alt ? g.size.height / 2 : f * g.size.height)     // main: TOP→BOTTOM
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .allowsHitTesting(false)
    }
}

// MARK: - Cell-edit STAGING (user 2026-07-25) — long-press a colour → configure a pending cell in the
// side panels (EDIT only). The RECEIVERS panel becomes the cell's INPUT picker (R1–R4 radio + a FROM ROW
// option), the EMITTERS panel its OUTPUT buses. Ephemeral (a StampConfig), recalled across enter/exit.
// The render-path live-preview drag-to-grid is DEFERRED to the design spec — this is the panel scaffold.

private let stagingCyan = Color(red: 0.15, green: 0.88, blue: 0.94)
private let stagingAmber = Color(red: 0.98, green: 0.72, blue: 0.12)

/// A 0→1→0 breathing fraction for the staging pulses (chip, empty-cell border, placed-cell fill) — one
/// cosine so every pulse shares the same rhythm. `period` in seconds.
func stagingPulseFraction(_ date: Date, period: Double) -> Double {
    0.5 - 0.5 * cos(date.timeIntervalSinceReferenceDate * 2 * .pi / period)
}

/// Marching-ants animated dashed border — the "prominent moving outline" marking a panel in cell-edit
/// state. Pure UI (an animated dashPhase); no render-path involvement.
struct MarchingAnts: ViewModifier {
    var active: Bool
    var color: Color
    var cornerRadius: CGFloat = 6
    var lineWidth: CGFloat = 2
    func body(content: Content) -> some View {
        content.overlay {
            if active {
                // Drive the dash phase off the clock (TimelineView), not withAnimation — animating
                // StrokeStyle.dashPhase via withAnimation doesn't march reliably; a per-frame phase does.
                TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { tl in
                    let period = 0.6                                   // seconds per 11pt dash cycle (7 on + 4 off)
                    let phase = -11 * CGFloat(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period)
                    RoundedRectangle(cornerRadius: cornerRadius)
                        .strokeBorder(color, style: StrokeStyle(lineWidth: lineWidth, dash: [7, 4], dashPhase: phase))
                }
            }
        }
    }
}
extension View {
    func marchingAnts(_ active: Bool, color: Color = stagingCyan, cornerRadius: CGFloat = 6, lineWidth: CGFloat = 2) -> some View {
        modifier(MarchingAnts(active: active, color: color, cornerRadius: cornerRadius, lineWidth: lineWidth))
    }
}

/// RECEIVERS panel in cell-edit state: pick the pending cell's INPUT. R1–R4 select a receiver
/// (inputRow == nil, radio); FROM ROW selects a row reference (inputRow = 0…7) via a ± stepper.
struct StagingInputView: View {
    let inputRow: Int?
    let inputReceiver: Int
    let receivers: [Receiver]
    let onPickReceiver: (Int) -> Void
    let onPickRow: () -> Void          // select the FROM ROW option
    let onStepRow: (Int) -> Void       // ± wrapping 0…7
    private var hues: [Color] { receiverHues }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("MIDI INPUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Text("cell input").font(.system(size: 8, design: .monospaced)).foregroundColor(stagingCyan.opacity(0.75))
            }
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { i in
                    tile(["A", "B", "C", "D"][i], on: inputRow == nil && inputReceiver == i, hue: hues[i]) { onPickReceiver(i) }
                }
            }
            HStack(spacing: 6) {                                   // the FROM ROW input option + row stepper
                let on = inputRow != nil
                Text("FROM ROW").font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.7))
                    .padding(.horizontal, 8).frame(height: 26)
                    .background(RoundedRectangle(cornerRadius: 5).fill(on ? stagingAmber : Color.white.opacity(0.06)))
                    .contentShape(Rectangle()).onTapGesture { onPickRow() }
                Spacer()
                stepBtn("chevron.down") { onStepRow(-1) }
                Text(inputRow != nil ? "\(inputRow! + 1)" : "—").font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? stagingAmber : .white.opacity(0.3)).frame(minWidth: 20)
                stepBtn("chevron.up") { onStepRow(+1) }
            }
        }
    }
    private func tile(_ label: String, on: Bool, hue: Color, _ action: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.75))
            .frame(maxWidth: .infinity).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 5).fill(on ? hue : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(on ? .clear : Color.white.opacity(0.12), lineWidth: 1))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
    private func stepBtn(_ symbol: String, _ action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 10, weight: .heavy)).foregroundColor(.white.opacity(0.6))
            .frame(width: 22, height: 22).background(RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture(perform: action)
    }
}

/// EMITTERS panel in cell-edit state: the pending cell's OUTPUT buses (A–D membership toggles).
struct StagingEmittersView: View {
    let buses: Set<Bus>
    let onToggle: (Int) -> Void
    private let letters: [Bus] = [.a, .b, .c, .d]
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text("MIDI OUTPUT").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Text("cell output").font(.system(size: 8, design: .monospaced)).foregroundColor(stagingCyan.opacity(0.75))
            }
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { i in
                    let on = buses.contains(letters[i])
                    Text(letters[i].rawValue).font(.system(size: 13, weight: .heavy, design: .monospaced))   // A–D chips
                        .foregroundColor(on ? .black : .white.opacity(0.35))
                        .frame(maxWidth: .infinity).frame(height: 34)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? stagingCyan : Color.white.opacity(0.05)))
                        .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? .clear : Color.white.opacity(0.12), lineWidth: 1))
                        .contentShape(Rectangle()).onTapGesture { onToggle(i) }
                }
            }
        }
    }
}

/// ON section (§9 item 1) — the five per-Colour trigger rows in an accordion. GUI iteration 1: assignments
/// are stored INERT (no engine execution yet). Greying is contextual (ALT/MORPH/DICE families + the always-
/// grey RING·CHOP / AUTO-ARM); a grey chip surfaces its teaching subtext and changes nothing.
struct OnSectionView: View {
    let config: OnConfig
    let altPaired: Bool          // the staged Colour has an ALT partner
    let morphCompatible: Bool    // …and it can morph toward it
    let stochastic: Bool         // CHANCE type or random-pattern ARP (for DICE)
    let onEdit: (@escaping (inout OnConfig) -> Void) -> Void

    @State private var expanded: Int? = nil
    @State private var greyMsg: String? = nil
    private let altSub = "needs an ALT pair — set one in COLOUR"
    private let morphSub = "needs a compatible ALT pair"
    private let diceSub = "needs a stochastic Colour (CHANCE / random ARP)"
    private let ringSub = "with the tail rule"
    private let armSub = "RECORD Colours — no RECORD type yet"

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("ON").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Text("cell triggers").font(.system(size: 8, design: .monospaced)).foregroundColor(stagingCyan.opacity(0.75))
            }
            row(0, "ON TAP", config.tapSummary) { tapBody }
            row(1, "ON HOLD", config.holdSummary) { holdBody }
            row(2, "ON ARRIVE", config.arriveSummary) { arriveBody }
            row(3, "ON LEAVE", config.leaveSummary) { leaveBody }
            row(4, "ON SCENE", config.sceneSummary) { sceneBody }
            if let m = greyMsg { Text(m).font(.system(size: 7, design: .monospaced)).foregroundColor(stagingAmber) }
        }
    }

    // One accordion row: a header (title + summary / "＋") that toggles expansion, and the expanded body.
    @ViewBuilder private func row<Content: View>(_ i: Int, _ title: String, _ summary: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.55))
                Spacer()
                if summary.isEmpty { Text("＋").font(.system(size: 10, weight: .heavy)).foregroundColor(.white.opacity(0.25)) }
                else { Text(summary).font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(stagingCyan.opacity(0.85)).lineLimit(1).minimumScaleFactor(0.7) }
            }
            .contentShape(Rectangle())
            .onTapGesture { expanded = (expanded == i) ? nil : i; greyMsg = nil }
            if expanded == i { content() }
        }
        .padding(.bottom, 2)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1) }
    }

    private func chip(_ label: String, on: Bool, grey: Bool = false, sub: String? = nil, _ act: @escaping () -> Void) -> some View {
        Text(label).font(.system(size: 7.5, weight: .heavy, design: .monospaced))
            .foregroundColor(grey ? .white.opacity(0.22) : (on ? .black : .white.opacity(0.7)))
            .lineLimit(1).minimumScaleFactor(0.6)
            .padding(.horizontal, 3).frame(maxWidth: .infinity).frame(height: 20)
            .background(RoundedRectangle(cornerRadius: 4).fill(on && !grey ? stagingCyan : Color.white.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(on && !grey ? .clear : Color.white.opacity(0.1), lineWidth: 1))
            .contentShape(Rectangle())
            .onTapGesture { if grey { greyMsg = sub } else { greyMsg = nil; act() } }
    }
    private func footer(_ t: String) -> some View {
        Text(t).font(.system(size: 6.5, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.28))
    }
    private func stepper(_ label: String, _ value: Int, _ lo: Int, _ hi: Int, _ set: @escaping (Int) -> Void) -> some View {
        HStack(spacing: 4) {
            footer(label)
            Image(systemName: "minus").font(.system(size: 8, weight: .heavy)).foregroundColor(.white.opacity(0.6))
                .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle()).onTapGesture { set(max(lo, value - 1)) }
            Text("\(value)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(stagingCyan).frame(minWidth: 16)
            Image(systemName: "plus").font(.system(size: 8, weight: .heavy)).foregroundColor(.white.opacity(0.6))
                .frame(width: 16, height: 16).background(RoundedRectangle(cornerRadius: 3).fill(Color.white.opacity(0.08)))
                .contentShape(Rectangle()).onTapGesture { set(min(hi, value + 1)) }
        }
    }

    // ON TAP
    private var tapBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) { ForEach(OnTap.allCases, id: \.self) { c in
                chip(c.rawValue, on: config.tap == c, grey: c == .alt && !altPaired, sub: altSub) { onEdit { $0.tap = c } } } }
            if config.tap != .none {
                HStack(spacing: 3) { footer("when"); ForEach(OnTapWhen.allCases, id: \.self) { w in
                    chip(w.rawValue, on: config.tapWhen == w) { onEdit { $0.tapWhen = w } } } }
                HStack(spacing: 3) { footer("for "); ForEach(OnTapFor.allCases, id: \.self) { f in
                    chip(f.rawValue, on: config.tapFor == f) { onEdit { $0.tapFor = f } } } }
            }
        }
    }
    // ON HOLD
    private var holdBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) { ForEach(OnHold.allCases, id: \.self) { c in
                let grey = (c == .alt && !altPaired) || (c == .morphScrub && !morphCompatible)
                chip(c.rawValue, on: config.hold == c, grey: grey, sub: c == .alt ? altSub : morphSub) { onEdit { $0.hold = c } } } }
            if config.hold != .none {
                HStack(spacing: 3) { footer("rel"); ForEach(OnHoldRelease.allCases, id: \.self) { r in
                    chip(r.rawValue, on: config.holdRelease == r) { onEdit { $0.holdRelease = r } } } }
                if config.hold == .sliceCycle {
                    HStack(spacing: 3) { footer("size"); ForEach(SliceSize.allCases, id: \.self) { s in
                        chip(s.rawValue, on: config.sliceSize == s) { onEdit { $0.sliceSize = s } } } }
                }
                if config.hold == .oct {
                    HStack(spacing: 3) { footer("oct"); chip("+", on: config.octUp) { onEdit { $0.octUp = true } }; chip("−", on: !config.octUp) { onEdit { $0.octUp = false } } }
                }
            }
        }
    }
    // ON ARRIVE
    private var arriveBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) { ForEach(OnArrive.allCases, id: \.self) { c in
                let grey = (c == .altAlternate && !altPaired) || (c == .morphDrift && !morphCompatible) || (c == .dice && !stochastic)
                let sub = c == .altAlternate ? altSub : (c == .morphDrift ? morphSub : diceSub)
                chip(c.rawValue, on: config.arrive == c, grey: grey, sub: sub) { onEdit { $0.arrive = c } } } }
            if config.arrive != .none {
                stepper("every", config.arriveEvery, 1, 4) { v in onEdit { $0.arriveEvery = v } }
                if config.arrive == .morphDrift {
                    HStack(spacing: 3) {
                        stepper("drift%", config.driftPct, 0, 100) { v in onEdit { $0.driftPct = v } }
                        chip("↻", on: config.driftMode == .loop) { onEdit { $0.driftMode = .loop } }
                        chip("⇄", on: config.driftMode == .pingpong) { onEdit { $0.driftMode = .pingpong } }
                    }
                }
            }
        }
    }
    // ON LEAVE
    private var leaveBody: some View {
        HStack(spacing: 3) { ForEach(OnLeave.allCases, id: \.self) { c in
            chip(c.rawValue, on: config.leave == c, grey: c == .ringChop, sub: ringSub) { onEdit { $0.leave = c } } } }
    }
    // ON SCENE (checklist)
    private var sceneBody: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 3) {
                chip("☐ ENTER", on: config.sceneEntrance) { onEdit { $0.sceneEntrance.toggle() } }
                if config.sceneEntrance { stepper("pass", config.entrancePass, 1, 16) { v in onEdit { $0.entrancePass = v } } }
            }
            HStack(spacing: 3) {
                chip("☐ EXIT", on: config.sceneExit) { onEdit { $0.sceneExit.toggle() } }
                if config.sceneExit { stepper("pass", config.exitPass, 1, 16) { v in onEdit { $0.exitPass = v } } }
            }
            HStack(spacing: 3) {
                chip("☐ RESET MORPH", on: config.sceneResetMorph) { onEdit { $0.sceneResetMorph.toggle() } }
                chip("☐ AUTO-ARM", on: config.sceneAutoArm, grey: true, sub: armSub) { }
            }
        }
    }
}
