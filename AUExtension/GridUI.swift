//  GridUI.swift
//  MidiSpark — the 8×8 grid view + edit controls (build-order step 5).
//  Increment 1: read-only grid bound to the document. Increment 2: edit mode — a Colour palette
//  (brush), tap-to-paint, and a per-cell editor strip for wiring (buses / ▾ stack / ▸ +SRC).
//  Every edit goes through MidiSparkAudioUnit.editScene → scheduleRebuild. Design tokens per
//  docs/ui-port-guide.md. NB: gesture model here is "tap paints an empty cell / selects an occupied
//  one; clear + repaint are explicit in the strip" — safe & predictable; we align to the mockup's
//  exact tap-to-clear/repaint when we match the HTML.

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

/// The 8×8 grid. `scene.cells` is [column][row]; rows lay top→bottom, columns left→right.
struct GridView: View {
    let scene: SceneState
    let playColumn: Int
    let playing: Bool
    var selCol: Int = -1
    var selRow: Int = -1
    var onTap: ((Int, Int) -> Void)? = nil

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 3) {                          // playhead bar
                ForEach(0..<8, id: \.self) { col in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(playing && col == playColumn ? accentCyan : Color.white.opacity(0.08))
                        .frame(height: 3)
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
        let parent = parentOf(col, row)                           // resolved reference (−1 = MIDI IN), reroute applied
        let fed = parent >= 0
        let noDest = cell.map { $0.buses.isEmpty && !isTapped(col, row) } ?? false   // §1 reference-aware

        RoundedRectangle(cornerRadius: 4)
            .fill(cell.flatMap { colourColor($0.colourID) } ?? Color.white.opacity(0.05))
            .frame(maxWidth: .infinity)
            .frame(height: 32)
            // border: selection (amber) > no-destination warning (dashed red, §1) > active col > idle
            .overlay {
                if noDest && !isSel {
                    RoundedRectangle(cornerRadius: 4)
                        .strokeBorder(Color(red: 0.95, green: 0.25, blue: 0.28),
                                      style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(isSel ? accentAmber : (inActiveCol ? Color.white.opacity(0.85) : Color.white.opacity(0.10)),
                                lineWidth: isSel ? 2 : (inActiveCol ? 1.5 : 0.5))
                }
            }
            // INPUT HEADER (delta §4): text naming the cell's input — top-left, small.
            .overlay(alignment: .topLeading) {
                if let cell {
                    Text(inputLabel(cell, parent: parent))
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundColor(fed ? .black.opacity(0.7) : .black.opacity(0.45))
                        .padding(.horizontal, 2).padding(.top, 1)
                }
            }
            // EMITTERS: lit bus letters, bottom-right (§4 emitter strip, compact form).
            .overlay(alignment: .bottomTrailing) {
                if let cell, let letters = busLetters(cell.buses) {
                    Text(letters).font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(.black.opacity(0.65)).padding(2)
                }
            }
            .opacity(cell == nil ? 0.6 : 1)
            .contentShape(Rectangle())
            .onTapGesture { onTap?(col, row) }
    }

    // Routing derivation — mirrors the engine (SnapshotBuilder.resolvedParent + Router.parentRow),
    // so the picture is truthful (delta §1, acceptance 12).
    private func cellAt(_ col: Int, _ row: Int) -> Cell? {
        guard col >= 0, col < scene.cells.count, row >= 0, row < scene.cells[col].count else { return nil }
        return scene.cells[col][row]
    }
    /// Resolved parent row: inputRow if that row is occupied, ≠ self, and NOT muted (reroute); else −1.
    private func parentOf(_ col: Int, _ row: Int) -> Int {
        guard let ir = cellAt(col, row)?.inputRow, ir != row, let p = cellAt(col, ir), !p.muted else { return -1 }
        return ir
    }
    /// Does any OTHER cell in the column reference this row? (reference-aware no-destination, §1)
    private func isTapped(_ col: Int, _ row: Int) -> Bool {
        for r in 0..<8 where r != row && cellAt(col, r)?.inputRow == row { return true }
        return false
    }
    private func inputLabel(_ cell: Cell, parent: Int) -> String {
        if parent >= 0 { return "◄\(parent + 1)" }          // FROM ROW n (1-based)
        if cell.inputChannel > 0 { return "CH\(cell.inputChannel)" }
        return "IN"
    }

    private func busLetters(_ buses: Set<Bus>) -> String? {
        let s = Bus.allCases.filter { buses.contains($0) }.map(\.rawValue).joined()
        return s.isEmpty ? nil : s
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

/// Editor for the selected cell (v3.0 model): input reference (FROM) + IN CH filter + bus emitters +
/// paint/clear. `occupiedRows` is the list of OTHER occupied rows in the selected column — the legal
/// reference targets (delta §1). FROM cycles MIDI IN → each of those rows (a blind-build stand-in for
/// the spec's FROM popover). IN CH cycles OMNI → 1…16 and shows only when the input is MIDI IN (§7).
struct CellEditorStrip: View {
    let cell: Cell?
    let brush: String
    let occupiedRows: [Int]            // other occupied rows in this column (reference targets)
    let onPaint: () -> Void
    let onClear: () -> Void
    let onToggleBus: (Bus) -> Void
    let onCycleFrom: () -> Void        // MIDI IN → next occupied row → … → MIDI IN
    let onCycleInCh: () -> Void        // OMNI → 1 → … → 16 → OMNI

    var body: some View {
        HStack(spacing: 5) {
            if let cell {
                RoundedRectangle(cornerRadius: 3).fill(colourColor(cell.colourID) ?? .gray)
                    .frame(width: 18, height: 18)
                Text(cell.colourID.uppercased()).font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7)).frame(width: 62, alignment: .leading)
                // FROM: the input reference. "FROM IN" or "FROM R<n>" (1-based).
                chip(fromLabel(cell), on: cell.inputRow != nil, disabled: occupiedRows.isEmpty) { onCycleFrom() }
                // IN CH filter — only meaningful for a MIDI-IN cell.
                if cell.inputRow == nil {
                    chip(cell.inputChannel == 0 ? "CH OMNI" : "CH \(cell.inputChannel)",
                         on: cell.inputChannel != 0) { onCycleInCh() }
                }
                Text("· OUT").font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.35))
                ForEach(Bus.allCases, id: \.self) { b in
                    chip(b.rawValue, on: cell.buses.contains(b)) { onToggleBus(b) }
                }
                chip("repaint", on: false) { onPaint() }
                chip("✕", on: false, danger: true) { onClear() }
            } else {
                Text("empty cell — tap the grid to paint the \(brush.uppercased()) brush")
                    .font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                chip("paint", on: false) { onPaint() }
            }
            Spacer()
        }
    }

    private func fromLabel(_ cell: Cell) -> String {
        if let ir = cell.inputRow { return "FROM R\(ir + 1)" }
        return "FROM IN"
    }

    private func chip(_ label: String, on: Bool, danger: Bool = false, disabled: Bool = false,
                      _ action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(disabled ? .white.opacity(0.25) : (on ? .black : .white.opacity(0.75)))
            .padding(.vertical, 4).padding(.horizontal, 7)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(on && !disabled ? accentCyan : (danger ? Color(red: 0.8, green: 0.25, blue: 0.3).opacity(0.5)
                                                  : Color.white.opacity(0.10))))
            .contentShape(Rectangle())
            .onTapGesture { if !disabled { action() } }
    }

    private func chip(_ label: String, on: Bool, danger: Bool = false, _ action: @escaping () -> Void) -> some View {
        Text(label)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : .white.opacity(0.75))
            .padding(.vertical, 4).padding(.horizontal, 7)
            .background(RoundedRectangle(cornerRadius: 4)
                .fill(on ? accentCyan : (danger ? Color(red: 0.8, green: 0.25, blue: 0.3).opacity(0.5)
                                                  : Color.white.opacity(0.10))))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
