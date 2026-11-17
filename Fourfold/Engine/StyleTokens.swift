//  StyleTokens.swift — STYLE PASS 1 (2026-11-17) §1: the page's surface/selected/text tokens, ONE place, every view reads
//  them (no second copy of any value — test 1's source scan enforces it). Foundation-only so the macOS test target sees it.
//  §9: every value here is a named on-device tunable; change them HERE, nowhere else.
//
//  §1.1 ground stays "as built" (the page draws no own ground fill; the recording's #0E0F11 is the host's) — there is
//  deliberately NO ground token to repaint to. Weights live in the views (SwiftUI Font.Weight is not Foundation);
//  §4.1's key weight is `.medium`, applied at each key site, named in the findings.

import CoreGraphics

enum FourfoldStyle {
    // §1.1 surfaces
    static let card: UInt32 = 0x17191E            // cards and panels (was #1B1D23 lane cards / white@3.5 % panels / #17191E pop-ups)
    static let control: UInt32 = 0x23262D          // controls on a card (was, dominantly, #2A2D34)
    static let controlPressed: UInt32 = 0x2E323A   // a control while a touch is down
    // §1.2 selected
    static let selectedFill: UInt32 = 0xDFE3EA
    static let selectedInk: UInt32 = 0x0D0F14
    // §1.3 text
    static let value: UInt32 = 0xF2F4F7
    static let label: UInt32 = 0xB4BAC4            // an unselected button's text
    static let key: UInt32 = 0x959BA6              // a word that names a control and is neither tappable nor a value
    static let disabled: UInt32 = 0x4A4E57
    // §1.4 hairline: 1 pt, the control tone
    static let hairline: UInt32 = 0x23262D
    static let hairlineWidth: CGFloat = 1
    // §5 header (§9 tunables)
    static let iconStroke: CGFloat = 1.6           // custom-path icons; SF Symbols take .medium
    static let tapeDotSize: CGFloat = 5
    static let tapeDot: UInt32 = 0xF0475B
}

/// §3 THE ONE SELECTED LOOK — every tab, segment, switch, token and box reads these four functions (test 2's callers).
/// §3.1 a SEGMENT in a group: selected = the light fill + dark ink; unselected = NO fill of its own (nil — the group's
/// container shows through), label grey. §3.2 a SWITCH drawn as a pill or tile: off = the control tone, never clear.
/// No border in any state — a border that remains at a call site carries STATE (§2.6), not selection.
enum FourfoldSelect {
    static func segmentFill(_ selected: Bool) -> UInt32? { selected ? FourfoldStyle.selectedFill : nil }
    static func segmentInk(_ selected: Bool) -> UInt32 { selected ? FourfoldStyle.selectedInk : FourfoldStyle.label }
    static func switchFill(_ on: Bool) -> UInt32 { on ? FourfoldStyle.selectedFill : FourfoldStyle.control }
    static func switchInk(_ on: Bool) -> UInt32 { on ? FourfoldStyle.selectedInk : FourfoldStyle.label }
}
