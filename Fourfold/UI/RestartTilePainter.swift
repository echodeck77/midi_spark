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

// MARK: - RESETS V2 ferry (2026-11-15) §1 — the ruler (replaces the sweep + strip on the RESETS tab)

/// What the ruler draws, from the tested `euclideousRestartRuler` (span + blocks) + the lane's hits in the span + `now`.
struct EuclideousRestartRulerInput: Equatable {
    var ruler: EuclideousRestartRuler
    var barBeats: Double
    var hits: [Double]      // absolute hit beats inside the span (the lane's own rhythm hits; §1.6)
    var now: Double         // the musical beat of the playhead
    var running: Bool       // §1.7/§1.8: the to-come shade + playhead show only while the transport runs
}

/// §1.2–§1.8 — one ruler band: the track, the part's passes / riff cycles as blocks (hatched when cut), the host bar/beat grid, the lane's hits, the still-to-come shade and the playhead. Immediate-mode, allocation-light, takes no touch.
/// `blockColor` is the lane's lane100 for a set part (the caller brightens); a FREE part uses #5C626C regardless.
struct EuclideousRestartRulerCanvas: View {
    let input: EuclideousRestartRulerInput
    let blockColor: Color
    let width: CGFloat
    let height: CGFloat
    private let ink = Color(hex: 0xF2F4F7)
    var body: some View {
        Canvas { ctx, _ in draw(ctx) }
            .frame(width: width, height: height)
            .allowsHitTesting(false)
    }
    private func draw(_ base: GraphicsContext) {
        let r = input.ruler
        guard r.spanLen > 1e-9 else { return }
        let inset: CGFloat = 12, rw = max(1, width - 2 * inset), h: CGFloat = 10          // §1.2: x 12 … width−12, 10 tall, bottom at the strip's built bottom (height−6)
        let top = height - 6 - h
        let frame = CGRect(x: inset, y: top, width: rw, height: h)
        var ctx = base
        ctx.fill(Path(roundedRect: frame, cornerRadius: 2), with: .color(Color(hex: 0x2A2D34)))   // §1.2 track
        ctx.clip(to: Path(roundedRect: frame, cornerRadius: 2))                                    // clips everything inside it
        func x(_ b: Double) -> CGFloat { frame.minX + CGFloat((b - r.spanStart) / r.spanLen) * rw }
        let fill = r.isFree ? Color(hex: 0x5C626C) : blockColor
        // §1.4 blocks (first). Solid: width = duration − 1.5 (the 1.5 gap marks each boundary). Cut: 135° stripes, no end gap.
        for blk in r.blocks {
            let x0 = x(blk.start), x1 = x(blk.end)
            if blk.cut {
                let rect = CGRect(x: x0, y: top, width: max(0, x1 - x0), height: h)
                if rect.width > 0 { drawHatch(ctx, rect: rect, color: fill) }
            } else {
                let w = max(0, x1 - x0 - 1.5)
                if w > 0 { ctx.fill(Path(roundedRect: CGRect(x: x0, y: top, width: w, height: h), cornerRadius: 1.5), with: .color(fill)) }
            }
        }
        drawGrid(ctx, frame: frame, x: x)   // §1.5 over the blocks
        drawHits(ctx, frame: frame, x: x)   // §1.6
        if input.running {                  // §1.7 to-come + §1.8 playhead — hidden while stopped
            let px = x(input.now)
            if px < frame.maxX { ctx.fill(Path(CGRect(x: px, y: top, width: frame.maxX - px, height: h)), with: .color(Color(hex: 0x121318).opacity(0.5))) }
            ctx.fill(Path(CGRect(x: px - 1, y: top, width: 2, height: h)), with: .color(ink))
        }
    }
    /// §1.4 cut block: 135° stripes of `color`, 2 pt on / 2 pt off (period 4), clipped to the block, no end gap.
    private func drawHatch(_ ctx0: GraphicsContext, rect: CGRect, color: Color) {
        var ctx = ctx0
        ctx.clip(to: Path(rect))
        var c = rect.minX + rect.minY - rect.height
        let cMax = rect.maxX + rect.maxY
        while c <= cMax {
            var p = Path(); p.move(to: CGPoint(x: c - rect.minY, y: rect.minY)); p.addLine(to: CGPoint(x: c - rect.maxY, y: rect.maxY))   // x + y = c (135°)
            ctx.stroke(p, with: .color(color), lineWidth: 2)
            c += 4
        }
    }
    /// §1.5 — a 1×10 #F2F4F7@60% bar line at each host bar line strictly inside the span; a 1×3@25% beat tick at each other host beat. Drop the beat ticks when beats come under 4 pt apart; draw every 4th bar line when bar lines do.
    private func drawGrid(_ ctx: GraphicsContext, frame: CGRect, x: (Double) -> CGFloat) {
        let r = input.ruler, bb = input.barBeats
        guard bb > 0 else { return }
        let spanEnd = r.spanStart + r.spanLen
        let barPx = CGFloat(bb / r.spanLen) * frame.width, beatPx = CGFloat(1.0 / r.spanLen) * frame.width
        let barStride = barPx < 4 ? 4 : 1
        // beat ticks (skip the ones that are bar lines; drop all when too dense)
        if beatPx >= 4 {
            var b = ceil(r.spanStart - 1e-9);
            while b < spanEnd - 1e-9 {
                if b > r.spanStart + 1e-9 {
                    let onBar = abs((b / bb).rounded() * bb - b) < 1e-6
                    if !onBar { ctx.fill(Path(CGRect(x: x(b) - 0.5, y: frame.minY, width: 1, height: 3)), with: .color(ink.opacity(0.25))) }
                }
                b += 1
            }
        }
        // bar lines
        var k = Int((r.spanStart / bb).rounded(.down));
        var drawn = 0
        while Double(k) * bb < spanEnd - 1e-9 {
            let bl = Double(k) * bb
            if bl > r.spanStart + 1e-9 { if drawn % barStride == 0 { ctx.fill(Path(CGRect(x: x(bl) - 0.5, y: frame.minY, width: 1, height: frame.height)), with: .color(ink.opacity(0.6))) }; drawn += 1 }
            k += 1
        }
    }
    /// §1.6 — a 1×6 #0D0F14@50% mark at y 2 at each hit in the span. Drop ALL of them while any two are under 3 pt apart.
    private func drawHits(_ ctx: GraphicsContext, frame: CGRect, x: (Double) -> CGFloat) {
        let xs = input.hits.map { x($0) }.sorted()
        for i in 1..<max(1, xs.count) where xs[i] - xs[i - 1] < 3 { return }   // any two under 3 pt apart ⇒ draw none
        for px in xs { ctx.fill(Path(CGRect(x: px - 0.5, y: frame.minY + 2, width: 1, height: 6)), with: .color(Color(hex: 0x0D0F14).opacity(0.5))) }
    }
}
