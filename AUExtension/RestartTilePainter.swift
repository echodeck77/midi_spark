//  RestartTilePainter.swift
//  RHYTHM POLISH ferry (2026-10-22) §6 — draws what `restartTileState` (Derivations.swift) decided: the sweep that fills a restart tile from its left edge toward the next restart, and the progress track along its bottom.
//  The tile's border, fill and text are the page's (`restartTile` in EuclideousPage.swift); this is the one `Canvas` on top. Immediate-mode and allocation-free per frame; it takes no touches. SwiftUI-only on purpose (GridUI
//  seam rule) — every decision it draws is a pure function in Derivations.swift.
import SwiftUI

struct EuclideousRestartTileCanvas: View {
    let state: EuclideousRestartTileState
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 8

    private let ink = Color(hex: 0xF2F4F7)
    private let freeLit = Color(hex: 0xAAB0BA)

    var body: some View {
        Canvas { ctx, size in
            drawSweep(ctx, size)
            drawTrack(ctx, size)
        }
        .frame(width: width, height: height)
        .allowsHitTesting(false)
    }

    /// 6.3 — a rectangle from the tile's left edge (inside the 1 pt border, clipped to the radius) in the lane colour at 30 %, its leading edge a 2 pt lane100 line. Width = the tile's width × progress; no easing — it jumps to 0 at the restart.
    private func drawSweep(_ ctx: GraphicsContext, _ size: CGSize) {
        guard let p = state.progress, p > 0 else { return }
        var c = ctx
        c.clip(to: Path(roundedRect: CGRect(x: 1, y: 1, width: size.width - 2, height: size.height - 2), cornerRadius: max(0, radius - 1)))
        let w = size.width * CGFloat(max(0, min(1, p)))
        c.fill(Path(CGRect(x: 0, y: 0, width: w, height: size.height)), with: .color(accent.opacity(0.3)))
        c.fill(Path(CGRect(x: max(0, w - 2), y: 0, width: 2, height: size.height)), with: .color(accent))
    }

    /// 6.4 — x 10 to the right edge − 10, its bottom 6 pt above the tile's bottom, 12 tall; cells 6 tall (radius 2) centred in it, sp2 apart. lit lane100 (grey #AAB0BA when FREE) · unlit #F2F4F7 at 16 % · ghost a 1 pt dashed
    /// #F2F4F7 at 30 % outline. A tick is 2 × 12 (radius 1) in the gap after its unit, costing 2 pt plus one more sp2 gap. More than 16 cells: one continuous 6 pt bar instead.
    private func drawTrack(_ ctx: GraphicsContext, _ size: CGSize) {
        guard state.count > 0 else { return }
        let x0: CGFloat = 10, w = max(1, size.width - 20)
        let boxY = size.height - 6 - 12
        let cellY = boxY + 3
        let litColor: Color = state.isFree ? freeLit : accent
        let unlit = ink.opacity(0.16)
        let dash = StrokeStyle(lineWidth: 1, dash: [2, 2])
        func ghost(_ r: CGRect, _ radius: CGFloat) { ctx.stroke(Path(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerRadius: radius), with: .color(ink.opacity(0.30)), style: dash) }
        if state.continuous {
            let bar = CGRect(x: x0, y: cellY, width: w, height: 6)
            ctx.fill(Path(roundedRect: bar, cornerRadius: 3), with: .color(unlit))
            let lit = w * CGFloat(max(0, min(1, state.litFraction)))
            if lit > 0 { ctx.fill(Path(roundedRect: CGRect(x: x0, y: cellY, width: lit, height: 6), cornerRadius: 3), with: .color(litColor)) }
            if let g = state.ghostFromFraction {
                let gx = x0 + w * CGFloat(max(0, min(1, g)))
                ghost(CGRect(x: gx, y: cellY, width: max(1, x0 + w - gx), height: 6), 3)   // the dashed tail: the part of the lap this pass won't reach
            }
            euclideousRestartTileForEachContinuousTick(state, width: w) { x in
                ctx.fill(Path(roundedRect: CGRect(x: x0 + x - 1, y: boxY, width: 2, height: 12), cornerRadius: 1), with: .color(ink))
            }
            return
        }
        let ticks = state.tickMask.nonzeroBitCount   // ticks only ever sit in the gaps between cells (k < count), so every set bit is one
        let cw = euclideousRestartTileCellWidth(count: state.count, ticks: ticks, width: w)
        var x = x0
        for i in 0..<state.count {
            let r = CGRect(x: x, y: cellY, width: cw, height: 6)
            switch state.cell(i) {
            case 1: ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(litColor))
            case 2: ghost(r, 2)
            default: ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(unlit))
            }
            x += cw + 2
            if state.hasTick(after: i) && i < state.count - 1 {
                ctx.fill(Path(roundedRect: CGRect(x: x, y: boxY, width: 2, height: 12), cornerRadius: 1), with: .color(ink))
                x += 2 + 2
            }
        }
    }
}
