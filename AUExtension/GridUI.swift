//  GridUI.swift
//  MidiSpark — the 8×8 grid view (v56 four-row cell) + palette + OUTPUTS (build-order step 5).
//  In-cell editing (delta §4/§5): tap a cell BODY paints/recolours it with the palette brush; tap the
//  INPUT HEADER opens the FROM popover (MIDI IN / any other occupied row / IN CH filter); tap the
//  EMITTER strip opens the OUT popover (A–D); body LONG-PRESS opens the cell menu (clear / copy
//  colour). Every edit goes through MidiSparkAudioUnit.editScene → scheduleRebuild. Design tokens
//  per docs/ui-port-guide.md; visual language per Docs/midispark-preview-v56.html.

import SwiftUI

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
    var cellHeight: CGFloat = 54   // set by the parent to fit the available height (landscape)
    var editing: Bool = true    // EDIT: sub-cell zones (FROM/OUT popovers, paint). PERFORM: whole pad = one tap.
    var selCol: Int = -1
    var selRow: Int = -1
    var onTap: ((Int, Int) -> Void)? = nil
    // in-cell editing (delta §5): the header opens the FROM popover, the emitter strip the OUT popover.
    var onSetInput: ((Int, Int, Int?) -> Void)? = nil
    var onCycleInCh: ((Int, Int) -> Void)? = nil
    var onToggleBus: ((Int, Int, Bus) -> Void)? = nil
    var onClear: ((Int, Int) -> Void)? = nil        // body long-press → clear
    var onCopyColour: ((Int, Int) -> Void)? = nil   // body long-press → adopt colour as brush
    // AUDITION (§6.4 / delta §5): press-and-hold a cell (≈0.3s) → sound its processor alone while the
    // transport is stopped; release ends it. Fires in both modes; the engine only sounds it when stopped.
    var onAuditionStart: ((Int, Int) -> Void)? = nil
    var onAuditionEnd: (() -> Void)? = nil

    enum PopKind { case from, out }
    @State private var pop: (col: Int, row: Int, kind: PopKind)? = nil
    @State private var breathe = false     // shared ALT-ring breathe phase (§6.5); decorative, not beat-locked
    @State private var lastBeat: Double = 0
    @State private var lastBeatAt = Date()

    /// The beat position NOW, extrapolated from the last poll (one-clock rule, §4): the UI polls at
    /// ~4 Hz; between polls we advance the last value by elapsed·tempo so the playhead glides.
    private func liveBeat(_ now: Date) -> Double {
        playing ? lastBeat + now.timeIntervalSince(lastBeatAt) * tempo / 60.0 : lastBeat
    }

    // Layout constants — shared by cellView and the mutation-line overlay so they never drift.
    private static let vGap: CGFloat = 3
    private static let headH: CGFloat = 38     // the prominent column-key row (v57)

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
                Text("\(col + 1)")
                    .font(.system(size: 15, weight: .heavy, design: .monospaced))
                    .foregroundColor(active ? .black : .white.opacity(0.45))
                    .frame(maxWidth: .infinity).frame(height: Self.headH)
                    .background(RoundedRectangle(cornerRadius: 6)
                        .fill(active ? accentCyan : Color.white.opacity(0.06)))
            }
        }
        .overlay { masterArrow }
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
                // within-STEP fraction (0 at column entry → 1 at exit)
                let f = ((liveBeat(tl.date) / max(0.001, stepBeats)).truncatingRemainder(dividingBy: 1) + 1)
                    .truncatingRemainder(dividingBy: 1)
                ForEach(0..<8, id: \.self) { r in
                    if playing, let c = cellAt(playColumn, r), !c.muted {
                        let faint = c.bypassed
                        Rectangle()
                            .fill(Color.white.opacity(faint ? 0.4 : 0.92))
                            .frame(width: cellW - 4, height: 2)
                            .shadow(color: faint ? .clear : Color.white.opacity(0.8), radius: faint ? 0 : 4)
                            .position(x: colX, y: (Self.headH + Self.vGap) + CGFloat(r) * (cellHeight + Self.vGap) + f * cellHeight)
                    }
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder private func cellView(col: Int, row: Int) -> some View {
        let cell = (col < scene.cells.count && row < scene.cells[col].count) ? scene.cells[col][row] : nil
        let isSel = col == selCol && row == selRow
        let inActiveCol = playing && col == playColumn
        let parent = parentOf(col, row)
        let colour = cell.flatMap { c in colourColor(c.colourID) }
        let noDest = cell.map { $0.buses.isEmpty && !isTapped(col, row) } ?? false

        ZStack {
            RoundedRectangle(cornerRadius: 8).fill(colour ?? cellBg)

            if let cell {
                VStack(spacing: 0) {
                    inputHeader(cell, parent: parent, live: inActiveCol)
                        .contentShape(Rectangle())
                        // EDIT: header → FROM popover. PERFORM: whole pad is one target → the cell tap.
                        .onTapGesture { editing ? (pop = (col, row, .from)) : onTap?(col, row) }
                    Spacer(minLength: 0)
                    bodyText(cell)
                    Spacer(minLength: 0)
                    emitterStrip(cell, firing: inActiveCol)
                        .contentShape(Rectangle())
                        .onTapGesture { editing ? (pop = (col, row, .out)) : onTap?(col, row) }
                }
            } else {
                Text("\(row + 1)")                          // empty-cell watermark (§4)
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity).frame(height: cellHeight)
        .overlay {                                          // border: no-dest > selection > active > idle
            let activeGlow = inActiveCol && cell != nil     // only WORKING cells glow in the active column
            if noDest && !isSel {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(red: 0.95, green: 0.25, blue: 0.28), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSel ? accentAmber : (activeGlow ? Color.white.opacity(0.7) : cellEdge),
                            lineWidth: isSel ? 2 : (activeGlow ? 1.5 : 1))
            }
        }
        .overlay {                                          // ALT (B-state) breathing ring (§6.5)
            if cell?.alt == true {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(breathe ? 0.95 : 0.35), lineWidth: 2)
                    .padding(3)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?(col, row) }                  // body / empty → paint / recolour
        .onLongPressGesture(minimumDuration: 0.3, maximumDistance: .infinity) {
            onAuditionStart?(col, row)                      // fires ONCE at ~0.3s while holding → audition
        } onPressingChanged: { pressing in
            if !pressing { onAuditionEnd?() }               // release/cancel → stop the audition
        }
        .contextMenu {                                      // EDIT only: body long-press → cell menu (§5)
            if cell != nil && editing {
                Button(role: .destructive) { onClear?(col, row) } label: { Label("Clear", systemImage: "xmark") }
                Button { onCopyColour?(col, row) } label: { Label("Copy colour", systemImage: "eyedropper") }
            }
        }
        .popover(isPresented: popBinding(col, row)) { popoverContent(col, row) }
    }

    // One isPresented binding per cell, true only when this cell is the popover target.
    private func popBinding(_ col: Int, _ row: Int) -> Binding<Bool> {
        Binding(get: { pop?.col == col && pop?.row == row },
                set: { if !$0 { pop = nil } })
    }

    @ViewBuilder private func popoverContent(_ col: Int, _ row: Int) -> some View {
        let cell = cellAt(col, row)
        if pop?.kind == .out {
            HStack(spacing: 6) {
                ForEach(Bus.allCases, id: \.self) { b in
                    let on = cell?.buses.contains(b) ?? false
                    Text(b.rawValue)
                        .font(.system(size: 13, weight: .heavy, design: .monospaced))
                        .foregroundColor(on ? .black : .white.opacity(0.8))
                        .frame(width: 34, height: 34)
                        .background(RoundedRectangle(cornerRadius: 6).fill(on ? Color.white : Color.white.opacity(0.12)))
                        .onTapGesture { onToggleBus?(col, row, b) }
                }
            }
            .padding(12)
        } else {
            // FROM: MIDI IN, then each OTHER occupied row; + IN CH when MIDI IN.
            let occupied = (0..<8).filter { $0 != row && cellAt(col, $0) != nil }
            VStack(alignment: .leading, spacing: 4) {
                fromButton("MIDI IN", on: cell?.inputRow == nil) { onSetInput?(col, row, nil); pop = nil }
                ForEach(occupied, id: \.self) { r in
                    fromButton("ROW \(r + 1)", on: cell?.inputRow == r) { onSetInput?(col, row, r); pop = nil }
                }
                if cell?.inputRow == nil {
                    fromButton("IN CH: \(cell?.inputChannel ?? 0 == 0 ? "OMNI" : "\(cell!.inputChannel)")",
                               on: (cell?.inputChannel ?? 0) != 0, accent: true) { onCycleInCh?(col, row) }
                }
            }
            .padding(10)
        }
    }

    private func fromButton(_ label: String, on: Bool, accent: Bool = false, _ action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : (accent ? accentCyan : .white.opacity(0.85)))
            .padding(.vertical, 6).padding(.horizontal, 12)
            .frame(minWidth: 96, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5)
                .fill(on ? Color.white : Color.white.opacity(0.08)))
            .onTapGesture(perform: action)
    }

    // ① INPUT HEADER — "FROM MIDI" / "MIDI CHn" / "FROM ROW n"; flares white on the live column.
    private func inputHeader(_ cell: Cell, parent: Int, live: Bool) -> some View {
        let midi = parent < 0
        let label = midi ? (cell.inputChannel > 0 ? "MIDI CH\(cell.inputChannel)" : "FROM MIDI")
                         : "FROM ROW \(parent + 1)"
        return Text(label)
            .font(.system(size: 6.5, weight: .heavy, design: .monospaced))
            .lineLimit(1).minimumScaleFactor(0.7)
            .foregroundColor(live ? .black : (midi ? .white.opacity(0.7) : .white))
            .frame(maxWidth: .infinity).frame(height: 13)
            .background(live ? Color.white : Color.black.opacity(0.52))
            .clipShape(.rect(topLeadingRadius: 7, topTrailingRadius: 7))
    }

    // ② BODY — type + effective-ish params (compact). Rendered over the colour fill.
    private func bodyText(_ cell: Cell) -> some View {
        let c = colours.first { $0.colourID == cell.colourID }
        let dim = cell.bypassed || cell.muted
        return VStack(spacing: 1) {
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

/// OUTPUTS panel (delta §7/§7b): the fixed cable identities + each bus's stamp channel. Tap a bus's
/// channel to bump it (1…16 → wraps). Flags when two buses share a channel (their streams merge on
/// the All cable — legal, never blocked).
struct OutputsView: View {
    let busChannels: [Int]        // 4 values, 1–16
    let onBump: (Int) -> Void     // bump bus i's channel

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text("EMITTERS").font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.45))
                Text("All = everything, by channel").font(.system(size: 8, design: .monospaced))
                    .foregroundColor(.white.opacity(0.3))
            }
            HStack(spacing: 5) {
                ForEach(0..<4, id: \.self) { i in
                    let ch = i < busChannels.count ? busChannels[i] : i + 1
                    let shared = busChannels.filter { $0 == ch }.count > 1
                    HStack(spacing: 3) {
                        Text("\(["A","B","C","D"][i])").font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(.white.opacity(0.55))
                        Text("ch \(ch)")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundColor(.black)
                            .padding(.vertical, 3).padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 4)
                                .fill(shared ? Color(red: 0.98, green: 0.72, blue: 0.12)   // amber: shared-channel flag
                                             : Color(red: 0.15, green: 0.88, blue: 0.94)))
                            .contentShape(Rectangle())
                            .onTapGesture { onBump(i) }
                    }
                }
                Spacer()
            }
        }
    }
}

/// HEADER (delta §6): logotype · STEP rate · SWING · PASS/transport readout. STEP/SWING are the
/// scene-level timing controls (AUParameters 0/1) — the only in-plugin way to set them.
struct HeaderView: View {
    let stepIndex: Int          // into StepRate.allCases
    let swing: Int              // 50…75
    let playing: Bool
    let pass: Int
    let beat: Double
    let tempo: Double
    let build: String
    let editing: Bool           // EDIT vs PERFORM mode
    let onStep: (Int) -> Void
    let onSwing: (Int) -> Void
    let onToggleMode: () -> Void

    private let stepLabels = ["2/1", "1/1", "1/2", "1/2.", "1/4", "1/8"]   // StepRate.allCases order
    private let accent = Color(red: 0.15, green: 0.88, blue: 0.94)         // PERFORM / cyan
    private let amber = Color(red: 0.98, green: 0.72, blue: 0.12)          // EDIT

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text("8×8 STATE").font(.system(size: 12, weight: .heavy, design: .monospaced)).tracking(4)
                .foregroundColor(.white.opacity(0.85))

            // EDIT / PERFORM mode (§6.1/6.2)
            HStack(spacing: 2) {
                modeChip("EDIT", on: editing, hue: amber)
                modeChip("PERFORM", on: !editing, hue: accent)
            }
            .onTapGesture { onToggleMode() }

            // STEP rate selector
            HStack(spacing: 3) {
                Text("STEP").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                ForEach(Array(stepLabels.enumerated()), id: \.offset) { i, s in
                    Text(s).font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(i == stepIndex ? .black : .white.opacity(0.6))
                        .padding(.vertical, 3).padding(.horizontal, 5)
                        .background(RoundedRectangle(cornerRadius: 3).fill(i == stepIndex ? accent : Color.white.opacity(0.08)))
                        .onTapGesture { onStep(i) }
                }
            }

            // SWING
            HStack(spacing: 4) {
                Text("SWING \(swing)").font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.4)).frame(width: 62, alignment: .leading)
                Slider(value: Binding(get: { Double(swing) }, set: { onSwing(Int($0.rounded())) }), in: 50...75).tint(accent)
                    .frame(width: 90)
            }

            Spacer()

            Text(playing ? String(format: "PASS %d · %.1f bpm", pass + 1, tempo) : "stopped")
                .font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(playing ? accent : .white.opacity(0.4))
            Text("build \(build)").font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.3))
        }
    }

    private func modeChip(_ label: String, on: Bool, hue: Color) -> some View {
        Text(label).font(.system(size: 9, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.5))
            .padding(.vertical, 3).padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 3).fill(on ? hue : Color.white.opacity(0.08)))
    }
}

/// PROCESSOR box (delta §6): edits the SELECTED Colour (= the palette brush). Fixed height (static-
/// frames rule — sized for the largest field set; smaller types leave calm space). Type + transpose +
/// per-type params + morph, with an A/B state tab (§3.1). The B tab exposes ONLY the B-overridable
/// fields (§3 table); MORPH fades A→B. Transpose/morph are AUParameters (own callbacks); the rest go
/// through editColour, writing paramsA or paramsB per the active tab.
struct ProcessorBox: View {
    let colour: Colour
    let colourIndex: Int
    let onEdit: (@escaping (inout Colour) -> Void) -> Void
    let onTranspose: (Int) -> Void
    let onMorph: (Double) -> Void
    var onSetType: ((ProcessorType) -> Void)? = nil   // type switch isolates transpose/morph per type

    enum ABTab: Hashable { case a, b }
    @State private var tab: ABTab = .a

    private var accent: Color { colourColor(colour.colourID) ?? .gray }

    /// Display params for the current tab: A directly, or B merged over A (unset B fields show A).
    private var dp: ColourParams {
        guard tab == .b else { return colour.paramsA }
        var m = colour.paramsA
        let b = colour.paramsB
        if let v = b.rate { m.rate = v }; if let v = b.octaves { m.octaves = v }
        if let v = b.count { m.count = v }; if let v = b.passes { m.passes = v }
        if let v = b.spread { m.spread = v }; if let v = b.probability { m.probability = v }
        if let v = b.harmIntervals { m.harmIntervals = v }
        return m
    }
    /// Route a param edit to paramsA or paramsB per the active tab.
    private func setParam(_ f: @escaping (inout ColourParams) -> Void) {
        onEdit { c in if tab == .b { f(&c.paramsB) } else { f(&c.paramsA) } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Text("PROCESSOR").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.45))
                Text(colour.colourID.uppercased()).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                Spacer()
                ForEach([ABTab.a, ABTab.b], id: \.self) { t in       // A/B state tabs (§3.1)
                    Text(t == .a ? "A" : "B").font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(tab == t ? .black : .white.opacity(0.6))
                        .frame(width: 22, height: 16)
                        .background(RoundedRectangle(cornerRadius: 3).fill(tab == t ? accent : Color.white.opacity(0.1)))
                        .onTapGesture { tab = t }
                }
            }
            if tab == .a {
                seg(ProcessorType.allCases.map { typeShort($0) },
                    sel: typeShort(colour.type)) { i in onSetType?(ProcessorType.allCases[i]) }
                field("TRANSPOSE \(colour.transpose > 0 ? "+" : "")\(colour.transpose)") {
                    stepper(colour.transpose, -24, 24) { onTranspose($0) }
                }
            } else {
                Text("B-STATE — the morph target · overridable fields only")
                    .font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4))
            }

            typeParams(bTab: tab == .b)

            field("MORPH \(Int(colour.morph * 100))%  A→B") {
                Slider(value: Binding(get: { colour.morph }, set: { onMorph($0) }), in: 0...1).tint(accent)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .frame(height: 268, alignment: .top)   // fixed: sized for the largest (ARP) field set; smaller
        .clipped()                             // types leave calm space, overflow scrolls within, never bleeds
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.03)))
    }

    // Reads `dp` (display value for the current tab), writes via `setParam` (A or B). In the B tab
    // only the §3 B-overridable fields render (rate/octaves · count · passes · spread · probability ·
    // intervals); non-overridable fields (pattern/phase/gate/ramp/dir/tilt) are A-only.
    @ViewBuilder private func typeParams(bTab: Bool) -> some View {
        let p = dp
        switch colour.type {
        case .arp:
            if !bTab {
                field("PATTERN") { seg(ArpPattern.allCases.map(\.rawValue), sel: p.pattern?.rawValue ?? "UP") { i in
                    setParam { $0.pattern = ArpPattern.allCases[i] } } }
            }
            field("RATE") { seg(ArpRate.allCases.map(\.rawValue), sel: p.rate?.rawValue ?? "1/16") { i in
                setParam { $0.rate = ArpRate.allCases[i] } } }
            HStack(spacing: 8) {
                field("OCT") { seg(["1","2","3","4"], sel: "\(p.octaves ?? 1)") { i in
                    setParam { $0.octaves = i + 1 } } }
                if !bTab {
                    field("PHASE") { seg(ArpPhase.allCases.map(\.rawValue), sel: p.phase?.rawValue ?? "RETRIG") { i in
                        setParam { $0.phase = ArpPhase.allCases[i] } } }
                }
            }
            if !bTab {
                field("GATE \(Int((p.gate ?? 0.6) * 100))%") {
                    Slider(value: bind(p.gate ?? 0.6) { v in setParam { $0.gate = v } }, in: 0.05...1).tint(accent)
                }
            }
        case .ratchet:
            field("REPEATS") { seg(["2","3","4","6","8"], sel: "\(p.count ?? 3)") { i in
                setParam { $0.count = [2,3,4,6,8][i] } } }
            if !bTab {
                field("RAMP \(Int((p.ramp ?? 0.5) * 100))%") {
                    Slider(value: bind(p.ramp ?? 0.5) { v in setParam { $0.ramp = v } }, in: 0...1).tint(accent)
                }
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
            if !bTab {
                field("DIR") { seg(StrumDir.allCases.map(\.rawValue), sel: (p.strumDir ?? .up).rawValue) { i in
                    setParam { $0.strumDir = StrumDir.allCases[i] } } }
            }
            field("SPREAD \(Int((p.spread ?? 0.1) * 100))") {
                Slider(value: bind(p.spread ?? 0.1) { v in setParam { $0.spread = v } }, in: 0...1).tint(accent) }
            if !bTab {
                field("TILT \(Int((p.velTilt ?? 0) * 100))") {
                    Slider(value: bind((p.velTilt ?? 0) / 2 + 0.5) { v in setParam { $0.velTilt = (v - 0.5) * 2 } }, in: 0...1).tint(accent) }
            }
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
    let onPick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: columns), spacing: 4) {
            ForEach(Array(colourIDs.enumerated()), id: \.offset) { i, id in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: colourHexes[i]))
                    .frame(height: 22)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(id == brush ? Color.white : Color.white.opacity(0.12),
                                lineWidth: id == brush ? 2 : 0.5))
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(id) }
            }
        }
    }
}
