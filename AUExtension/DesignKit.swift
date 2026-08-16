import SwiftUI

// THE DESIGN KIT (Paul 2026-08-16) — one source of truth for the desk's accent palette and the reusable chrome that
// was re-declared per file (the codebase review found the cyan literal 18×, amber 16×, editHue defined twice, and a
// PillToggle-shaped control re-implemented ~6 times). Every token below is the EXACT pre-existing literal, so nothing
// changes visually — this is a de-duplication, not a restyle.
//
// ADOPTION: files repoint their local `private let cyan = …` to `UI.cyan` etc. (call sites unchanged). The control
// PRIMITIVES here are for new code and INCREMENTAL adoption — the existing toggles/steppers differ in font/frame, so
// migrate them one at a time with a device glance rather than in a blind sweep.
enum UI {
    static let cyan    = Color(red: 0.15, green: 0.88, blue: 0.94)   // primary accent — active / selected / on
    static let amber   = Color(red: 0.98, green: 0.72, blue: 0.12)   // warm accent — save-ready / armed
    static let red     = Color(red: 0.98, green: 0.35, blue: 0.30)   // destructive / confirm / alarm
    static let green   = Color(red: 0.35, green: 0.92, blue: 0.50)   // affirmative (mint) — used by the cog + receivers
    static let editHue = Color(red: 0.95, green: 0.47, blue: 0.85)   // orchid — the EDIT face accent
    static let ink     = Color.white                                 // primary foreground
}

/// A filled-when-on rounded-pill toggle — the shape the desk re-implements as `busToggle`/`modeChip`/`onOffToggle`/
/// `modeSeg`/`transactChip`/etc. New chrome should use this; existing pills adopt it incrementally (they vary in
/// font size and padding, hence the knobs). `on` → filled with `hue` + black text; off → faint fill + `hue` text.
struct PillToggle: View {
    let label: String
    var on: Bool
    var hue: Color = UI.cyan
    var fontSize: CGFloat = 11
    var hPad: CGFloat = 10
    var vPad: CGFloat = 5
    let action: () -> Void
    var body: some View {
        Text(label)
            .font(.system(size: fontSize, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : hue)
            .padding(.horizontal, hPad).padding(.vertical, vPad)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? hue : Color.white.opacity(0.08)))
            .contentShape(Rectangle())
            .onTapGesture(perform: action)
    }
}
