//  SharedUIHelpers.swift
//  FOURFOLD (2026-10-23, Step 1a) — four small helpers that used to live in GridUI.swift (the 8x8 grid widgets) but are needed by the Fourfold page and the AU class too.
//  Moved here verbatim so the Fourfold targets need not compile GridUI.swift. No behaviour change.

import SwiftUI

extension Color {
    /// 0xRRGGBB → Color. Used for the 16 canonical Machine hexes (do not "harmonise" them, §ui-guide).
    init(hex: UInt32) {
        self.init(.sRGB,
                  red:   Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue:  Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

/// Canonical Machine hexes, in machineIDs / bank order (docs/ui-port-guide.md). Index = machine index.
let machineHexes: [UInt32] = [
    0xFFC53D, 0xFF7A1A, 0xFF4B33, 0xC2244B, 0xFF4D9E, 0xFFA8B8, 0xB44DFF, 0x7A3DF0,
    0x5566FF, 0x38A6FF, 0x25E0F0, 0x148F80, 0x7BF2CE, 0x2ECC5E, 0xC6F23D, 0x4C6E8F,   // [15] SLATE (was BRONZE 0xC9A227 — too close to GOLD, user 2026-08-09)
]

// BUILD's STAGE-THE-GRID variations are REAL machine IDs given a custom hue near their source (a new, distinguishable
// machine — not a shade drawn over the source). Session-scoped, like the rest of the BUILD workspace. (Paul 2026-08-15)
var machineHueOverride: [String: UInt32] = [:]

/// EUCLID DRAG HUD (Paul 2026-10-02 relocation): what's live while dragging a lane's comet bar — reported UP to
/// whoever hosts `ProcessorBox`, since the HUD itself must render OUTSIDE this box's own (possibly scrolling)
/// container to float truly "above the touch," not fixed to the scrolling processor-edit page. `point` is in
/// WINDOW coordinates (UIKit's `location(in: view.window)`) — the host converts it into its own local space.
/// GENERALIZED (Paul 2026-10-06, EUCLIDEOUS's per-tab gesture pads): `primary`/`secondary` replace the old
/// rigid `hits`/`steps`/`offset` ints — "we need different overlays for velocity, gate, etc." needed a format
/// each caller controls, not one hardcoded to a single meaning. `euclidLaneDragHUDInfo` (below) is the ONE,
/// UNCHANGED hits/offset formatting both the regular BUILD-page editor and Euclideous's own HITS/OFFSET pad
/// still share; Euclideous's two NEW tabs (VEL/GATE, NOTE/OCT) get their own formatters in EuclideousPage.swift.
struct EuclidDragHUDInfo {
    let label: String      // "LANE 1"…"LANE 4" or "ALL LANES" (2-finger)
    let primary: String    // the big, central readout
    let secondary: String  // the smaller sub-line beneath it
    let point: CGPoint
}
