//  RiffMapPalette.swift — RIFF MAP ferry (2026-11-10): the map colours as SwiftUI `Color`s, built ONCE from the pure tables (`riffMapColour` / `riffMapFaint`, Derivations.swift). A draw reads a slot; it converts nothing.

import SwiftUI

enum RiffMapPalette {
    static func swiftUIColour(_ c: EuclideousRGB) -> Color { Color(.sRGB, red: Double(c.r) / 255, green: Double(c.g) / 255, blue: Double(c.b) / 255, opacity: 1) }
    private static let map: [Color] = (0..<64).map { swiftUIColour(riffMapColour(column: $0 / 8 + 1, rank: $0 % 8 + 1)) }
    private static let faint: [Color] = (0..<64).map { swiftUIColour(riffMapFaint(column: $0 / 8 + 1, rank: $0 % 8 + 1)) }
    /// The colour of a written note at `column` (1-based) and `rank` 1…8 — a grid note cell's fill, a lane-strip chip's fill.
    static func colour(column: Int, rank: Int) -> Color { map[riffMapIndex(column: column, rank: rank)] }
    /// An empty grid cell's fill.
    static func faintColour(column: Int, rank: Int) -> Color { faint[riffMapIndex(column: column, rank: rank)] }
}
