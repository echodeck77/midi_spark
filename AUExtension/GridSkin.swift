import SwiftUI

// ── GRID SKIN (Paul 2026-09-08, PLAN-grid-rebuild) ──────────────────────────────────────────────────────────────────
// The grid's fresh visual layer, built from scratch so the old constellation/drift stylings can't leak in. A cell's
// FACE is a STATIC piano-roll RIBBON — the note bars (GridSelBar: x0…x1 time · y pitch · vel), drawn ONCE, tinted. No
// drift, no blink, no per-cell TimelineView (the calm-cells ruling + a real perf win): motion lives ONLY on the ferry
// row. Reads the SAME roll feeds the old faces did — only the DRAWING is new (KEEP the data, replace the picture).
extension DiagView {
    /// The static piano-roll ribbon: each held note is a horizontal bar at its pitch lane (y: 0 = bottom … 1 = top),
    /// spanning its on→off time (x0…x1), thickness + opacity by velocity, in `tint` (the cell's emitter hue). Calm by
    /// construction — no animation. Used by every part / SELECT / row-selector / ferry face.
    @ViewBuilder func roomsRibbonFace(_ bars: [GridSelBar], tint: Color) -> some View {
        Canvas { ctx, size in
            let w = size.width, h = size.height
            for b in bars {
                let x0 = b.x0 * w
                let x1 = max(x0 + 2, b.x1 * w)                       // a floor so a zero-length note still reads
                let yc = (1 - b.y) * (h - 4) + 2                     // pitch lane → y (top = high)
                let th = 2.0 + b.vel * 2.5                           // velocity → thickness
                let rect = CGRect(x: x0, y: yc - th / 2, width: x1 - x0, height: th)
                ctx.fill(Path(roundedRect: rect, cornerRadius: th / 2), with: .color(tint.opacity(0.4 + 0.5 * b.vel)))
            }
        }
        .padding(2)
        .allowsHitTesting(false)
    }
}
