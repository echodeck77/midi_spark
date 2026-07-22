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
    var selCol: Int = -1
    var selRow: Int = -1
    var onTap: ((Int, Int) -> Void)? = nil
    // in-cell editing (delta §5): the header opens the FROM popover, the emitter strip the OUT popover.
    var onSetInput: ((Int, Int, Int?) -> Void)? = nil
    var onCycleInCh: ((Int, Int) -> Void)? = nil
    var onToggleBus: ((Int, Int, Bus) -> Void)? = nil
    var onClear: ((Int, Int) -> Void)? = nil        // body long-press → clear
    var onCopyColour: ((Int, Int) -> Void)? = nil   // body long-press → adopt colour as brush

    enum PopKind { case from, out }
    @State private var pop: (col: Int, row: Int, kind: PopKind)? = nil

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {                          // master playhead bar (down-arrow strip, simple)
                ForEach(0..<8, id: \.self) { col in
                    Text(playing && col == playColumn ? "▼" : "")
                        .font(.system(size: 8, weight: .heavy))
                        .foregroundColor(accentCyan)
                        .frame(maxWidth: .infinity).frame(height: 9)
                }
            }
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { col in cellView(col: col, row: row) }
                }
            }
        }
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
                        .onTapGesture { pop = (col, row, .from) }        // header → FROM popover
                    Spacer(minLength: 0)
                    bodyText(cell)
                    Spacer(minLength: 0)
                    emitterStrip(cell, firing: inActiveCol)
                        .contentShape(Rectangle())
                        .onTapGesture { pop = (col, row, .out) }         // emitter strip → OUT popover
                }
            } else {
                Text("\(row + 1)")                          // empty-cell watermark (§4)
                    .font(.system(size: 20, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.08))
            }
        }
        .frame(maxWidth: .infinity).frame(height: 54)
        .overlay {                                          // border: no-dest > selection > active > idle
            if noDest && !isSel {
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color(red: 0.95, green: 0.25, blue: 0.28), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSel ? accentAmber : (inActiveCol ? Color.white.opacity(0.7) : cellEdge),
                            lineWidth: isSel ? 2 : (inActiveCol ? 1.5 : 1))
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?(col, row) }                  // body / empty → paint / recolour
        .contextMenu {                                      // body long-press → cell menu (delta §5)
            if cell != nil {
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
        switch c.type {
        case .arp:
            var s = c.paramsA.rate?.rawValue ?? ""
            if let o = c.paramsA.octaves, o > 1 { s += " \(o)OCT" }
            return s
        case .ratchet:  return "×\(c.paramsA.count ?? 3)"
        case .passgate: return "GATE"
        case .strum:    return "SPR \(Int((c.paramsA.spread ?? 0.1) * 100))"
        case .chance:   return "\(Int((c.paramsA.probability ?? 1) * 100))%"
        case .harmonize:
            let iv = (c.paramsA.harmIntervals ?? [0,0,0]).filter { $0 != 0 }
            return iv.isEmpty ? "UNISON" : iv.map { $0 > 0 ? "+\($0)" : "\($0)" }.joined(separator: " ")
        }
    }
}

/// The four output bus lanes (A–D). Shows, per column, which buses have an emitting cell — a
/// truthful map of where sound leaves the plugin. A lane pulses when MIDI is flowing (global
/// emit activity), the lightweight "current flows when MIDI flows" cue.
struct BusLanesView: View {
    let scene: SceneState
    let active: Bool          // any emission happening right now (from the diag emit counter)

    var body: some View {
        VStack(spacing: 2) {
            ForEach(Array(Bus.allCases.enumerated()), id: \.offset) { _, bus in
                HStack(spacing: 3) {
                    Text(bus.rawValue).font(.system(size: 9, weight: .heavy, design: .monospaced))
                        .foregroundColor(.white.opacity(0.5)).frame(width: 12)
                    ForEach(0..<8, id: \.self) { col in
                        let emits = columnEmits(col, to: bus)
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(emits ? (active ? Color(red: 0.15, green: 0.88, blue: 0.94)
                                                  : Color(red: 0.15, green: 0.88, blue: 0.94).opacity(0.4))
                                        : Color.white.opacity(0.05))
                            .frame(height: 5)
                    }
                }
            }
        }
    }

    private func columnEmits(_ col: Int, to bus: Bus) -> Bool {
        guard col < scene.cells.count else { return false }
        return scene.cells[col].contains { $0?.buses.contains(bus) ?? false }
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
                Text("OUTPUTS").font(.system(size: 9, weight: .heavy, design: .monospaced))
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

/// The Colour brush palette — 16 chips in bank order; the active brush is ringed.
struct PaletteView: View {
    let brush: String
    let onPick: (String) -> Void

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
            ForEach(Array(colourIDs.enumerated()), id: \.offset) { i, id in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(hex: colourHexes[i]))
                    .frame(height: 18)
                    .overlay(RoundedRectangle(cornerRadius: 3)
                        .stroke(id == brush ? Color.white : Color.white.opacity(0.12),
                                lineWidth: id == brush ? 2 : 0.5))
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(id) }
            }
        }
    }
}
