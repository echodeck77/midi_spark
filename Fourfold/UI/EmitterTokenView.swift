//  EmitterTokenView.swift — EMITTER TOKEN ferry (2026-11-07): the two paint sites for the one token.
//
//  The DRAWING is a single `GraphicsContext` routine, `drawEuclideousEmitterToken`, fed by the pure geom + paint in `Fourfold/Engine/EmitterToken.swift`. The SwiftUI `EuclideousEmitterTokenView` is just a `Canvas` that calls it
//  (so the routing circles, which live in SwiftUI layouts with taps, get the exact same drawing); the RATCH toggle and the MIX emitter column, which already draw in a Canvas, call the routine directly. §2.4's "never a second
//  drawing" is honoured: there is ONE routine; the only split is who hosts the `GraphicsContext`.

import SwiftUI

extension EuclideousTokenInk {
    /// Resolve to a Color; `.lane` takes the lane/output colour the paint site supplies.
    func color(lane: Color) -> Color {
        switch self {
        case .none: return .clear
        case .hex(let h, let a): return Color(hex: h).opacity(a)
        case .lane(let a): return lane.opacity(a)
        }
    }
    var isNone: Bool { if case .none = self { return true }; return false }
}

/// Draw the token into `rect` (a square D×D frame; a larger rect centres the token). `held` (§5.2, MIX only) overrides the disc to #DFE3EA and the letter to ink #0D0F14 over the current ring, cancelling any flare.
func drawEuclideousEmitterToken(_ ctx: GraphicsContext, rect: CGRect, size: EuclideousEmitterTokenSize, letter: String,
                                paint rawPaint: EuclideousEmitterTokenPaint, lane: Color, held: Bool = false) {
    let g = euclideousEmitterTokenGeom(size)
    var paint = rawPaint
    if held {
        paint.disc = .hex(0xDFE3EA, 1)
        paint.letter = .hex(0x0D0F14, 1)
        paint.flare = 0
    }
    let side = min(rect.width, rect.height)
    let scale = side / g.diameter
    let box = CGRect(x: rect.midX - side / 2, y: rect.midY - side / 2, width: side, height: side)
    let cx = box.midX, cy = box.midY
    let ringR = g.ringRadius * scale
    let ringW = paint.ringWidth * scale
    let gap = Double(g.gapAngle)

    // The gapped ring, gap centred on 12 o'clock; a dashed stroke starts at a gap edge (§1.3). Symmetric about the top whichever way it sweeps.
    func ringPath() -> Path {
        var p = Path()
        let top = -Double.pi / 2
        p.addArc(center: CGPoint(x: cx, y: cy), radius: ringR,
                 startAngle: .radians(top + gap / 2),
                 endAngle: .radians(top + gap / 2 + (2 * .pi - gap)),
                 clockwise: false)
        return p
    }
    func discPath() -> Path {
        let r = ringR - ringW / 2   // the ring's inner edge
        return Path(ellipseIn: CGRect(x: cx - r, y: cy - r, width: r * 2, height: r * 2))
    }

    // §2.1 playing glow (under everything): a 6 pt lane40 ring, at the flare activity.
    if paint.flare > 0 {
        ctx.stroke(Path(ellipseIn: CGRect(x: cx - ringR, y: cy - ringR, width: ringR * 2, height: ringR * 2)),
                   with: .color(lane.opacity(EuclideousEmitterTokenFlare.glowAlpha * paint.flare)),
                   lineWidth: EuclideousEmitterTokenFlare.glowWidth * scale)
    }
    // §1.2 the disc inside the ring (muted / routed looks draw none).
    if !paint.disc.isNone { ctx.fill(discPath(), with: .color(paint.disc.color(lane: lane))) }
    // §2.1 the lane20 wash over the disc, at the flare activity.
    if paint.flare > 0 { ctx.fill(discPath(), with: .color(lane.opacity(EuclideousEmitterTokenFlare.washAlpha * paint.flare))) }
    // the ring (dashed for muted / routed-muted).
    let style = StrokeStyle(lineWidth: ringW, lineCap: .butt, dash: paint.dashed ? EuclideousEmitterTokenFlare.dash.map { $0 * scale } : [])
    ctx.stroke(ringPath(), with: .color(paint.ring.color(lane: lane)), style: style)
    // §2.1 the flare ring (lane100, w+1) over the base ring, at the flare activity.
    if paint.flare > 0 {
        ctx.stroke(ringPath(), with: .color(lane.opacity(paint.flare)), lineWidth: (paint.ringWidth + EuclideousEmitterTokenFlare.ringDelta) * scale)
    }
    // §1.3 the key, in the gap, always the ring's colour (lane100 over the base at the flare activity).
    if !paint.key.isNone {
        let k = g.keyRect
        let kr = CGRect(x: box.minX + k.minX * scale, y: box.minY + k.minY * scale, width: k.width * scale, height: k.height * scale)
        let kp = Path(roundedRect: kr, cornerRadius: g.keyRadius * scale)
        ctx.fill(kp, with: .color(paint.key.color(lane: lane)))
        if paint.flare > 0 { ctx.fill(kp, with: .color(lane.opacity(paint.flare))) }
    }
    // the letter, centred.
    if !paint.letter.isNone {
        ctx.draw(Text(letter).font(.system(size: g.letterSize * scale, weight: .heavy, design: .monospaced)).foregroundColor(paint.letter.color(lane: lane)),
                 at: CGPoint(x: cx, y: cy), anchor: .center)
    }
}

/// The token as a SwiftUI view (the routing circles use this; it is a Canvas over the one draw routine). The frame is the token's own diameter.
struct EuclideousEmitterTokenView: View {
    let size: EuclideousEmitterTokenSize
    let letter: String
    let state: EuclideousEmitterTokenState
    var lane: Color = .clear
    var held: Bool = false
    var body: some View {
        let d = euclideousEmitterTokenGeom(size).diameter
        return Canvas { ctx, sz in
            drawEuclideousEmitterToken(ctx, rect: CGRect(origin: .zero, size: sz), size: size, letter: letter,
                                       paint: euclideousEmitterTokenPaint(state, size: size), lane: lane, held: held)
        }
        .frame(width: d, height: d)
    }
}
