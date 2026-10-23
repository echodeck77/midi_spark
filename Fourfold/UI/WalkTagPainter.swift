//  WalkTagPainter.swift
//  The riff-grid WALK TAG + THREAD painters (ferry "Riff-grid walk tags with threads", 2026-10-15).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks): pure paint routines over the plain
//  geometry `Derivations.swift` computes (`EuclideousTagDrawing` / `EuclideousThreadGeometry`), kept out of
//  `EuclideousPage` so a macOS preview harness can render exactly what the page draws.

import SwiftUI

enum EuclideousWalkTagPainter {
    /// INK #0d0f14 — the outline / casing colour.
    static let ink = Color(.sRGB, red: 13.0 / 255, green: 15.0 / 255, blue: 20.0 / 255, opacity: 1)


}
