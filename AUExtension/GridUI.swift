//  GridUI.swift
//  MidiSpark — the 8×8 grid view (build-order step 5, increment 1: READ-ONLY, bound to the document).
//  Proves the UI↔engine binding: load a session → the grid reflects it; play → the playhead moves.
//  Editing (paint/wire) is increment 2. Design tokens per docs/ui-port-guide.md.

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

/// The 8×8 grid, read-only. `scene.cells` is [column][row]; we lay rows top→bottom, columns left→right.
struct GridView: View {
    let scene: SceneState
    let playColumn: Int        // active grid column, from the engine's derived effColumn
    let playing: Bool

    // Canonical Colour hexes, in colourIDs / bank order (docs/ui-port-guide.md). Index = colour index.
    static let colourHex: [UInt32] = [
        0xFFC53D, 0xFF7A1A, 0xFF4B33, 0xC2244B, 0xFF4D9E, 0xFFA8B8, 0xB44DFF, 0x7A3DF0,
        0x5566FF, 0x38A6FF, 0x25E0F0, 0x148F80, 0x7BF2CE, 0x2ECC5E, 0xC6F23D, 0xC9A227,
    ]

    private static let accent = Color(red: 0.15, green: 0.88, blue: 0.94)   // cyan playhead accent

    var body: some View {
        VStack(spacing: 3) {
            // playhead bar: 8 segments, the active column lit while playing
            HStack(spacing: 3) {
                ForEach(0..<8, id: \.self) { col in
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(playing && col == playColumn ? GridView.accent : Color.white.opacity(0.08))
                        .frame(height: 3)
                }
            }
            ForEach(0..<8, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<8, id: \.self) { col in
                        cellView(col: col, row: row)
                    }
                }
            }
        }
    }

    @ViewBuilder private func cellView(col: Int, row: Int) -> some View {
        let cell = (col < scene.cells.count && row < scene.cells[col].count) ? scene.cells[col][row] : nil
        let colourIdx = cell.flatMap { colourIDs.firstIndex(of: $0.colourID) }
        let inActiveCol = playing && col == playColumn
        RoundedRectangle(cornerRadius: 4)
            .fill(colourIdx.map { Color(hex: GridView.colourHex[$0]) } ?? Color.white.opacity(0.05))
            .frame(maxWidth: .infinity)
            .frame(height: 26)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(inActiveCol ? Color.white.opacity(0.85) : Color.white.opacity(0.10),
                            lineWidth: inActiveCol ? 1.5 : 0.5)
            )
            // occupied cells carry a lit bus letter (lowest, for now) so the wiring reads at a glance
            .overlay(alignment: .bottomTrailing) {
                if let cell, let letter = busLetter(cell.buses) {
                    Text(letter)
                        .font(.system(size: 8, weight: .heavy, design: .monospaced))
                        .foregroundColor(.black.opacity(0.6))
                        .padding(2)
                }
            }
            .opacity(cell == nil ? 0.6 : 1)
    }

    private func busLetter(_ buses: Set<Bus>) -> String? {
        for b in Bus.allCases where buses.contains(b) { return b.rawValue }
        return nil
    }
}
