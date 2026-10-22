//  RestartTilePainter.swift
//  RHYTHM POLISH ferry (2026-10-22) §6 + RESTART TILES ferry (2026-10-22) §1–§3 — draws what `restartTileState` (Derivations.swift) decided: the sweep that fills a restart tile from its left edge toward the next restart, and the
//  progress track (RHYTHM: step slots; MELODY: one cell per riff note, struck by each hit that plays it). Two small `Canvas`es — one per layer — so the page can stack them in `euclideousRestartTileLayerOrder`
//  (base · sweep · track · text) and the sweep can never draw over the text. Immediate-mode and allocation-free per frame; neither takes a touch. SwiftUI-only on purpose (GridUI seam rule) — every decision it draws is a
//  pure function in Derivations.swift.
import SwiftUI

struct EuclideousRestartTileCanvas: View {
    enum Part { case sweep, track }
    let part: Part
    let state: EuclideousRestartTileState
    let accent: Color
    let width: CGFloat
    let height: CGFloat
    var radius: CGFloat = 8
    /// The editor's strips centre the 12 pt track box vertically; the tile keeps it 6 pt above its bottom.
    var trackCentred = false
    /// MELODY strikes (RESTART TILES §1.5): per cell, how far its latest strike has brightened it (the page builds the bank from the pulse feed; nil = none / stopped).
    var strikes: EuclideousCellStrikeBank? = nil
    var pulseScale: Double = 1
    var reduceMotion = false

    private let ink = Color(hex: 0xF2F4F7)
    private let freeLit = Color(hex: 0xAAB0BA)

    var body: some View {
        Canvas { ctx, size in
            switch part {
            case .sweep: drawSweep(ctx, size)
            case .track: drawTrack(ctx, size)
            }
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

    /// 6.4 — x 10 to the right edge − 10, its bottom 6 pt above the tile's bottom (centred in the editor's strip), 12 tall; cells 6 tall (radius 2) centred in it, sp2 apart. lit lane100 (grey #AAB0BA when FREE) · unlit #F2F4F7 at
    /// 16 % · ghost a 1 pt dashed #F2F4F7 at 30 % outline. A struck MELODY cell brightens toward #F2F4F7 and settles back. More than 16 RHYTHM slots: one continuous 6 pt bar instead.
    private func drawTrack(_ ctx: GraphicsContext, _ size: CGSize) {
        guard state.count > 0 else { return }
        let x0: CGFloat = 10, w = max(1, size.width - 20)
        let boxY = trackCentred ? (size.height - 12) / 2 : size.height - 6 - 12
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
            return
        }
        let cw = euclideousRestartTileCellWidth(count: state.count, width: w)
        var x = x0
        for i in 0..<state.count {
            let r = CGRect(x: x, y: cellY, width: cw, height: 6)
            switch state.cell(i) {
            case 1:
                ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(litColor))
                if state.kind == .melody, let strikes {
                    let f = strikes.mix(cell: i, scale: pulseScale, reduceMotion: reduceMotion)
                    if f > 0.01 { ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(ink.opacity(f))) }   // lane100 → #F2F4F7 by the strike's envelope
                }
            case 2: ghost(r, 2)
            default: ctx.fill(Path(roundedRect: r, cornerRadius: 2), with: .color(unlit))
            }
            x += cw + 2
        }
    }
}
