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
        RoundedRectangle(cornerRadius: 4)
            .fill(cell.flatMap { colourColor($0.colourID) } ?? Color.white.opacity(0.05))
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(isSel ? accentAmber : (inActiveCol ? Color.white.opacity(0.85) : Color.white.opacity(0.10)),
                            lineWidth: isSel ? 2 : (inActiveCol ? 1.5 : 0.5))
            )
            .overlay(alignment: .topLeading) {
                if let cell, cell.stack {           // ▾ marks a cell that feeds the one below
                    Text("▾").font(.system(size: 9, weight: .bold)).foregroundColor(.black.opacity(0.6)).padding(2)
                }
            }
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

    private func busLetters(_ buses: Set<Bus>) -> String? {
        let s = Bus.allCases.filter { buses.contains($0) }.map(\.rawValue).joined()
        return s.isEmpty ? nil : s
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

/// Editor for the selected cell: paint/clear + wiring toggles. Empty selection shows a paint prompt.
struct CellEditorStrip: View {
    let cell: Cell?
    let brush: String
    let onPaint: () -> Void            // paint / repaint with the current brush
    let onClear: () -> Void
    let onToggleBus: (Bus) -> Void
    let onToggleStack: () -> Void
    let onToggleSrcMix: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            if let cell {
                RoundedRectangle(cornerRadius: 3).fill(colourColor(cell.colourID) ?? .gray)
                    .frame(width: 18, height: 18)
                Text(cell.colourID.uppercased()).font(.system(size: 9, weight: .heavy, design: .monospaced))
                    .foregroundColor(.white.opacity(0.7)).frame(width: 72, alignment: .leading)
                ForEach(Bus.allCases, id: \.self) { b in
                    chip(b.rawValue, on: cell.buses.contains(b)) { onToggleBus(b) }
                }
                chip("▾", on: cell.stack) { onToggleStack() }        // stack: feed the cell below
                chip("▸", on: cell.srcMix) { onToggleSrcMix() }      // +SRC: union feed with source
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
