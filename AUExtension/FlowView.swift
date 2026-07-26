//  FlowView.swift
//  The FLOW VIEW (delta item 10 / mockup v62): the grid region becomes a live MIDI-flow theater —
//  receivers above · the grid as coloured glass · emitters below · notes as COMETS travelling their real
//  routing hops (entry → cell → reference → emitter), each in its cell's Colour, derivation-driven (a pure
//  function of the beat; one engine, many renderers). Watch-only. The FLOW button cycles VARIATIONS — a set
//  of example renderers exploring different ways to visualise the same derived flow, diagnostic + pleasing.
//
//  SwiftUI-only (seam rule): Canvas + TimelineView, the same beat-extrapolation the grid playhead uses.

import SwiftUI

// MARK: - the derived flow graph (pure — shared by every variation)

/// One placed cell, resolved for drawing: its hue, type, per-column tick count (visual), input source
/// (a receiver or a same-column row reference), and output emitters.
struct FlowCell {
    let col: Int, row: Int
    let hue: Color
    let label: String
    let ticks: Int          // pulses launched per column (visual approximation of the processor's rate)
    let srcReceiver: Int?   // entry hop from receiver i (MIDI-IN)
    let srcRow: Int?        // reference hop from a row in the same column
    let buses: [Int]        // 0…3 = A…D emission hops
    var rooted = true       // can it EVER sound? false = a pure reference CYCLE with no MIDI-IN root (silent)
}

/// Visual tick count for a Colour — how many comets it launches down each hop per column. A pure, capped
/// approximation of the processor's per-step activity (not sample-exact; this is a picture, not the engine).
func flowTicks(_ c: Colour, stepBeats: Double) -> Int {
    switch c.type {
    case .arp:      let r = (c.paramsA.rate ?? .r1_16).beats
                    return max(1, min(8, Int((stepBeats / max(0.03, r)).rounded())))
    case .ratchet:  return max(1, min(8, c.paramsA.count ?? 3))
    case .strum:    return 3
    default:        return 1   // passgate / chance / harmonize hold the chord — one pulse
    }
}

func flowLabel(_ t: ProcessorType) -> String {
    switch t {
    case .arp: "ARP"; case .ratchet: "RTC"; case .passgate: "PASS"
    case .strum: "STRM"; case .chance: "CHNC"; case .harmonize: "HARM"
    }
}

/// Resolve the scene's active column set into `FlowCell`s (MIDI-IN source = the cell's receiver; a row
/// reference = `inputRow`). Colours indexed by id.
func flowCells(scene: SceneState, colours: [Colour], stepBeats: Double) -> [FlowCell] {
    var out: [FlowCell] = []
    for c in 0..<8 {
        guard c < scene.cells.count else { break }
        for r in 0..<8 {
            guard r < scene.cells[c].count, let cell = scene.cells[c][r], !cell.muted else { continue }
            guard let colour = colours.first(where: { $0.colourID == cell.colourID }) else { continue }
            let buses = Bus.allCases.enumerated().filter { cell.buses.contains($0.element) }.map { $0.offset }
            out.append(FlowCell(
                col: c, row: r,
                hue: colourColor(cell.colourID) ?? .gray,
                label: flowLabel(colour.type),
                ticks: flowTicks(colour, stepBeats: stepBeats),
                srcReceiver: cell.inputRow == nil ? (cell.inputReceiver ?? 0) : nil,
                srcRow: cell.inputRow,
                buses: buses))
        }
    }
    // ROOTEDNESS: a cell can sound only if its input chain reaches a MIDI-IN source. Trace up `srcRow`; hitting
    // a `srcReceiver` (MIDI-IN) ⇒ rooted; a reference to an EMPTY/muted row ⇒ MIDI-IN fallback ⇒ rooted; a
    // revisited cell ⇒ a CYCLE with no source ⇒ SILENT (the engine's depth guard makes it soundless). This is
    // what stops the FLOW view from flying "output" comets out of a circular reference that never emits.
    func isRooted(_ start: Int) -> Bool {
        var seen = Set<Int>(); var cur = start
        while true {
            if seen.contains(cur) { return false }                    // cycle → structurally silent
            seen.insert(cur)
            if out[cur].srcReceiver != nil { return true }            // reads MIDI-IN
            guard let sr = out[cur].srcRow else { return false }
            guard let pi = out.firstIndex(where: { $0.col == out[cur].col && $0.row == sr }) else { return true }  // ref → empty/muted row = MIDI-IN
            cur = pi
        }
    }
    for i in out.indices { out[i].rooted = isRooted(i) }
    return out
}

// MARK: - the view

struct FlowView: View {
    var variation: Int = 1      // 1…5 (0 = not shown; the parent swaps back to the grid)
    let scene: SceneState
    let colours: [Colour]
    let receivers: [Receiver]
    var busChannels: [Int] = [1, 2, 3, 4]
    var busEnabled: [Bool] = [true, true, true, true]
    var playColumn: Int = 0
    var playing: Bool = false
    var beat: Double = 0
    var tempo: Double = 120
    var stepBeats: Double = 2
    var emitPeak: [Double] = [0, 0, 0, 0]
    var receiverPeak: [Double] = [0, 0, 0, 0]
    // item 4 feed: the ACTUAL note-ons (velocity + source colour), per emitter / per receiver. The comets are
    // the PLAN (derived routing); these draw where notes TRULY went — so suppression shows as a missing pulse.
    var emitMarks: [[VelMark]] = [[], [], [], []]
    var recvMarks: [[VelMark]] = [[], [], [], []]

    // beat extrapolation between the 4 Hz polls — identical to the grid playhead.
    @State private var lastBeat: Double = 0
    @State private var lastBeatAt = Date()
    @State private var traced: Int? = nil   // index into flowCells for TRACE (tap a cell); nil = none
    @State private var canvasSize: CGSize = .zero

    private func liveBeat(_ now: Date) -> Double {
        playing ? lastBeat + now.timeIntervalSince(lastBeatAt) * tempo / 60.0 : lastBeat
    }

    static let names = ["", "FLOW", "CONSTELLATION", "SCOPE", "WATERFALL", "RADAR"]

    private var cells: [FlowCell] { flowCells(scene: scene, colours: colours, stepBeats: stepBeats) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 40.0, paused: false)) { tl in
            Canvas { ctx, size in
                let b = liveBeat(tl.date)
                switch variation {
                case 2:  renderConstellation(ctx, size, b)
                case 3:  renderScope(ctx, size, b)
                case 4:  renderWaterfall(ctx, size, b)
                case 5:  renderRadar(ctx, size, b)
                default: renderFlow(ctx, size, b, tl.date)
                }
            }
            .background(Color(red: 0.043, green: 0.051, blue: 0.063))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.white.opacity(0.06), lineWidth: 1))
        }
        .background(GeometryReader { g in Color.clear.onAppear { canvasSize = g.size }
            .onChange(of: g.size) { canvasSize = $0 } })
        .onChange(of: beat) { nb in lastBeat = nb; lastBeatAt = Date() }
        .onChange(of: variation) { _ in traced = nil }
        // Tap-to-TRACE (watch-only): map the tap to a cell; tap empty space to release.
        .gesture(DragGesture(minimumDistance: 0).onEnded { g in traceHit(g.location) })
    }

    // MARK: geometry (shared by the grid-based variations)

    private func gridFrame(_ size: CGSize) -> (grid: CGRect, bandH: CGFloat) {
        let pad: CGFloat = 10
        let bandH = min(46, max(30, size.height * 0.12))
        let grid = CGRect(x: pad, y: pad + bandH + 6,
                          width: size.width - 2 * pad,
                          height: size.height - 2 * pad - 2 * (bandH + 6))
        return (grid, bandH)
    }
    private func cellRect(_ col: Int, _ row: Int, _ grid: CGRect) -> CGRect {
        let gap: CGFloat = 3
        let cw = (grid.width - 7 * gap) / 8, ch = (grid.height - 7 * gap) / 8
        return CGRect(x: grid.minX + CGFloat(col) * (cw + gap), y: grid.minY + CGFloat(row) * (ch + gap), width: cw, height: ch)
    }
    private func cellCenter(_ col: Int, _ row: Int, _ grid: CGRect) -> CGPoint {
        let r = cellRect(col, row, grid); return CGPoint(x: r.midX, y: r.midY)
    }
    private func bandX(_ i: Int, _ grid: CGRect) -> CGFloat { grid.minX + (CGFloat(i) + 0.5) * grid.width / 4 }

    private func traceHit(_ p: CGPoint) {
        let (grid, _) = gridFrame(canvasSize)
        for (i, fc) in cells.enumerated() where cellRect(fc.col, fc.row, grid).contains(p) {
            traced = (traced == i) ? nil : i; return
        }
        traced = nil
    }

    /// The family of a traced cell: its ancestors (up the reference chain) + descendants, within its column.
    private func tracedFamily() -> Set<Int> {
        guard let t = traced, t < cells.count else { return [] }
        let all = cells
        let root = all[t]
        var fam: Set<Int> = [t]
        // ancestors (follow srcRow up)
        var cur = root
        while let sr = cur.srcRow, let pi = all.firstIndex(where: { $0.col == cur.col && $0.row == sr }) {
            if fam.contains(pi) { break }; fam.insert(pi); cur = all[pi]
        }
        // descendants (cells in the same column whose srcRow chains back into the family)
        var changed = true
        while changed {
            changed = false
            for (i, fc) in all.enumerated() where !fam.contains(i) {
                if let sr = fc.srcRow, fam.contains(where: { all[$0].col == fc.col && all[$0].row == sr }) { fam.insert(i); changed = true }
            }
        }
        return fam
    }

    // MARK: quadratic-bezier hop

    private func bez(_ a: CGPoint, _ b: CGPoint, _ cp: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(x: u*u*a.x + 2*u*t*cp.x + t*t*b.x, y: u*u*a.y + 2*u*t*cp.y + t*t*b.y)
    }

    // A soft glowing dot (comet head / node).
    private func glowDot(_ context: GraphicsContext, _ p: CGPoint, _ radius: CGFloat, _ color: Color, _ intensity: Double) {
        var glow = context
        glow.addFilter(.blur(radius: radius * 1.6))
        glow.opacity = 0.55 * intensity
        glow.fill(Path(ellipseIn: CGRect(x: p.x - radius*1.8, y: p.y - radius*1.8, width: radius*3.6, height: radius*3.6)), with: .color(color))
        var core = context
        core.opacity = intensity
        core.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius*2, height: radius*2)), with: .color(color))
    }
}

// MARK: - the renderers (one derived flow, many pictures)

extension FlowView {
    private var accent: Color { Color(red: 0.145, green: 0.878, blue: 0.941) }        // FLOW cyan
    private func receiverHue(_ i: Int) -> Color {
        [Color(red: 0.56, green: 0.63, blue: 0.75), Color(red: 0.66, green: 0.56, blue: 0.75),
         Color(red: 0.56, green: 0.75, blue: 0.65), Color(red: 0.75, green: 0.69, blue: 0.56)][i % 4]
    }
    /// Derived column + fractional progress through it — the one clock every picture shares.
    private func clock(_ b: Double) -> (col: Int, frac: Double, pass: Int) {
        let step = max(0.1, stepBeats)
        var frac = (b / step).truncatingRemainder(dividingBy: 1); if frac < 0 { frac += 1 }
        let col = ((Int(floor(b / step)) % 8) + 8) % 8
        return (col, frac, Int(floor(b / (step * 8))) + 1)
    }

    // item 4: a note-on mark's tint — its source cell's Colour (−1 / out of range → the FLOW accent).
    private func markHue(_ col: Int8) -> Color {
        (col >= 0 && Int(col) < colourIDs.count) ? (colourColor(colourIDs[Int(col)]) ?? accent) : accent
    }

    // 1 — FLOW: receivers above, coloured-glass grid, emitters below, comets on the live column's real hops
    // (the PLAN), plus bright expanding rings where notes TRULY fired (the LIVE, from the item-4 mark feed).
    func renderFlow(_ ctx: GraphicsContext, _ size: CGSize, _ b: Double, _ now: Date) {
        var ctx = ctx
        let (grid, bandH) = gridFrame(size)
        let (col, frac, _) = clock(b)
        let rY = 10 + bandH / 2, eY = size.height - 10 - bandH / 2
        let all = cells, fam = tracedFamily()
        func recvPt(_ i: Int) -> CGPoint { CGPoint(x: bandX(i, grid), y: rY + bandH/2 - 4) }
        func emitPt(_ i: Int) -> CGPoint { CGPoint(x: bandX(i, grid), y: eY - bandH/2 + 4) }

        // receiver band
        for i in 0..<4 {
            let x = bandX(i, grid), hue = receiverHue(i)
            let box = CGRect(x: x - 34, y: rY - 15, width: 68, height: 30)
            ctx.stroke(Path(roundedRect: box, cornerRadius: 5), with: .color(hue.opacity(0.7)), lineWidth: 1.2)
            let cbl = (i < receivers.count ? receivers[i].cableResolved : 0b1111)
            ctx.draw(Text("\(["A","B","C","D"][i]) · \(cbl == 0b1111 ? "ANY" : "C")").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(hue), at: CGPoint(x: x, y: rY - 22))
            let peak = i < receiverPeak.count ? receiverPeak[i] : 0
            for p in 0..<3 { let lit = peak > 0.05 ? 0.9 : 0.2
                ctx.opacity = lit; ctx.fill(Path(ellipseIn: CGRect(x: x - 12 + CGFloat(p)*11 - 2.6, y: rY + 1, width: 5.2, height: 5.2)), with: .color(hue)); ctx.opacity = 1 }
        }
        // grid cells
        for r in 0..<8 { for c in 0..<8 {
            let rect = cellRect(c, r, grid)
            if let idx = all.firstIndex(where: { $0.col == c && $0.row == r }) {
                let fc = all[idx]
                let dim = traced != nil && !fam.contains(idx)
                ctx.opacity = dim ? 0.14 : (!fc.rooted ? 0.3 : (c == col ? 1.0 : 0.4))   // silent cycle ⇒ dimmed
                ctx.fill(Path(roundedRect: rect, cornerRadius: 5), with: .color(fc.hue))
                ctx.opacity = dim ? 0.25 : 0.9
                ctx.draw(Text(!fc.rooted ? "⟳" : fc.label).font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.black), at: CGPoint(x: rect.midX, y: rect.midY))
                ctx.opacity = 1
            } else {
                ctx.stroke(Path(roundedRect: rect, cornerRadius: 5), with: .color(.white.opacity(c == col ? 0.12 : 0.05)), lineWidth: 1)
            }
        } }
        // live-column glow
        if playing {
            let x0 = cellRect(col, 0, grid).minX - 3, x1 = cellRect(col, 7, grid).maxX + 3
            ctx.stroke(Path(roundedRect: CGRect(x: x0, y: grid.minY - 3, width: x1 - x0, height: grid.height + 6), cornerRadius: 6),
                       with: .color(accent.opacity(0.45)), lineWidth: 1.6)
        }
        // hops + comets (live column, plus a traced family anywhere)
        var ladder = emitPeak
        for (idx, fc) in all.enumerated() {
            let live = fc.col == col
            let on = traced == nil ? live : fam.contains(idx)
            if !on { continue }
            let ctr = cellCenter(fc.col, fc.row, grid)
            var hops: [(a: CGPoint, b: CGPoint, cp: CGPoint, bus: Int)] = []
            if let rc = fc.srcReceiver { let a = recvPt(rc); hops.append((a, ctr, CGPoint(x: (a.x+ctr.x)/2, y: (a.y+ctr.y)/2), -2)) }   // MIDI-IN hop (bus −2)
            if let sr = fc.srcRow, let p = all.first(where: { $0.col == fc.col && $0.row == sr }) {
                let a = cellCenter(p.col, p.row, grid); let bow: CGFloat = sr > fc.row ? -34 : 34
                hops.append((a, ctr, CGPoint(x: (a.x+ctr.x)/2 + bow, y: (a.y+ctr.y)/2), -1)) }
            for bus in fc.buses { let bpt = emitPt(bus); hops.append((ctr, bpt, CGPoint(x: (ctr.x+bpt.x)/2 + CGFloat(bus-1)*8, y: (ctr.y+bpt.y)/2), bus)) }
            for h in hops {
                // A silent cell's OUTPUT hop (a cycle that never emits) draws its guide edge FAINTLY but flies
                // NO comets — it must not look like notes reach the emitter. The loop/reference hops still flow.
                let silentOut = !fc.rooted && h.bus >= 0
                var gp = Path(); gp.move(to: h.a); gp.addQuadCurve(to: h.b, control: h.cp)
                ctx.stroke(gp, with: .color(fc.hue.opacity(silentOut ? 0.08 : 0.22)), lineWidth: 1)
                guard playing, !silentOut else { continue }
                // MIDI-IN hop (bus −2): the RAW input to the processor is the held chord — a SUSTAINED signal,
                // not the processor's rhythm. Draw a STEADY continuous stream (evenly-spaced dots drifting at a
                // constant rate) in the cell's Colour; the rhythm appears only on the OUTPUT hop, after the cell.
                if h.bus == -2 {
                    let n = 7, phase = b.truncatingRemainder(dividingBy: 1) / Double(n)
                    for k in 0..<n {
                        let t = (Double(k) / Double(n) + phase).truncatingRemainder(dividingBy: 1)
                        glowDot(ctx, bez(h.a, h.b, h.cp, CGFloat(t)), 1.7, fc.hue, 0.7)
                    }
                    continue
                }
                for k in 0..<fc.ticks {
                    let tt = frac * Double(fc.ticks) - Double(k)
                    guard tt >= 0, tt <= 1 else { continue }
                    let vel = 0.65 + 0.35 * sin(Double(k) * 2.7 + Double(fc.col))
                    // short fading tail
                    for s in 0..<5 { let ts = max(0, tt - Double(s) * 0.045)
                        let p = bez(h.a, h.b, h.cp, CGFloat(ts))
                        ctx.opacity = (1 - Double(s) / 5) * 0.5
                        ctx.fill(Path(ellipseIn: CGRect(x: p.x-2, y: p.y-2, width: 4, height: 4)), with: .color(fc.hue)); ctx.opacity = 1 }
                    let head = bez(h.a, h.b, h.cp, CGFloat(tt))
                    glowDot(ctx, head, 2.6 + 2.4 * vel, fc.hue, 1)
                    if h.bus >= 0, tt > 0.9, h.bus < ladder.count { ladder[h.bus] = min(1, ladder[h.bus] + 0.4 * vel) }
                }
            }
        }
        // emitter band + ladders
        for i in 0..<4 {
            let x = bandX(i, grid); let en = i < busEnabled.count && busEnabled[i]
            let box = CGRect(x: x - 34, y: eY - 15, width: 68, height: 30)
            ctx.stroke(Path(roundedRect: box, cornerRadius: 5), with: .color(accent.opacity(en ? 0.7 : 0.25)), lineWidth: 1.2)
            let ch = i < busChannels.count ? busChannels[i] : i+1
            ctx.draw(Text("EMIT \("ABCD"[i]) · CH\(ch)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(accent.opacity(en ? 1 : 0.4)), at: CGPoint(x: x, y: eY + 22))
            let lvl = i < ladder.count ? ladder[i] : 0
            for s in 0..<8 {
                ctx.opacity = Double(lvl) * 8 > Double(s) ? 0.95 : 0.12
                let col = s < 5 ? Color(red: 0.24, green: 0.86, blue: 0.52) : (s < 7 ? Color(red: 1, green: 0.77, blue: 0.24) : Color(red: 1, green: 0.29, blue: 0.2))
                ctx.fill(Path(CGRect(x: x - 28 + CGFloat(s)*7.4, y: eY - 6, width: 5.4, height: 12)), with: .color(col)); ctx.opacity = 1
            }
        }
        // ---- LIVE layer (item 4 feed): where notes TRULY fired. Each actual note-on = a bright expanding ring
        //      + core at the node, tinted in the source Colour, sized by velocity, fading ~250ms. Distinct from
        //      the PLAN comets above — a suppressed note (CLAIM/SOLO/chance/closed passgate) shows NO ring. ----
        func livePulse(_ pt: CGPoint, _ hue: Color, _ vel: Double, _ age: Double) {
            let op = max(0, 1 - age / 0.25); guard op > 0 else { return }
            let ringR = 3 + (4 + 10 * vel) * CGFloat(age / 0.25)     // expands as it fades
            ctx.stroke(Path(ellipseIn: CGRect(x: pt.x - ringR, y: pt.y - ringR, width: ringR*2, height: ringR*2)),
                       with: .color(hue.opacity(op * 0.9)), lineWidth: 2)
            glowDot(ctx, pt, 2 + 3 * vel, hue, op)                   // bright core
        }
        for i in 0..<4 {
            for m in (i < emitMarks.count ? emitMarks[i] : []) { livePulse(emitPt(i), markHue(m.col), m.vel, now.timeIntervalSince(m.born)) }
            for m in (i < recvMarks.count ? recvMarks[i] : []) { livePulse(recvPt(i), receiverHue(i), m.vel, now.timeIntervalSince(m.born)) }
        }
    }

    // 2 — CONSTELLATION: cells as glowing nodes; each tick drifts a soft particle toward its emitters; trails.
    func renderConstellation(_ ctx: GraphicsContext, _ size: CGSize, _ b: Double) {
        var ctx = ctx
        let (grid, bandH) = gridFrame(size)
        let (col, frac, _) = clock(b)
        let eY = size.height - 10 - bandH / 2, rY = 10 + bandH / 2
        let all = cells
        func emitPt(_ i: Int) -> CGPoint { CGPoint(x: bandX(i, grid), y: eY) }
        func recvPt(_ i: Int) -> CGPoint { CGPoint(x: bandX(i, grid), y: rY) }
        // faint anchor nodes
        for i in 0..<4 { glowDot(ctx, recvPt(i), 3, receiverHue(i).opacity(0.5), 0.5); glowDot(ctx, emitPt(i), 3, accent.opacity(0.5), 0.5) }
        for fc in all {
            let ctr = cellCenter(fc.col, fc.row, grid)
            let live = fc.col == col
            glowDot(ctx, ctr, live ? 6 : 3.4, fc.hue, live ? 1 : 0.5)
            guard playing else { continue }
            let dests = fc.buses.map { emitPt($0) } + (fc.srcReceiver.map { [recvPt($0)] } ?? [])
            for d in dests {
                for k in 0..<fc.ticks {
                    let tt = frac * Double(fc.ticks) - Double(k)
                    guard tt >= 0, tt <= 1 else { continue }
                    // ease-out drift + slight sag
                    let e = 1 - pow(1 - tt, 2)
                    let p = CGPoint(x: ctr.x + (d.x - ctr.x) * e, y: ctr.y + (d.y - ctr.y) * e + sin(tt * .pi) * 10)
                    ctx.opacity = (1 - tt) * 0.9
                    glowDot(ctx, p, 2 + 2 * (1 - tt), fc.hue, 1); ctx.opacity = 1
                }
            }
        }
    }

    // 3 — SCOPE: a clean diagnostic panel — receiver input bars · per-column activity · emitter output ladders.
    func renderScope(_ ctx: GraphicsContext, _ size: CGSize, _ b: Double) {
        var ctx = ctx
        let (col, _, pass) = clock(b)
        let pad: CGFloat = 16, w = size.width - 2*pad
        let all = cells
        // receiver input row
        let ry = pad + 6
        ctx.draw(Text("INPUT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)), at: CGPoint(x: pad + 22, y: ry))
        for i in 0..<4 {
            let x = pad + 70 + CGFloat(i) * (w - 70) / 4, bw = (w - 70) / 4 - 10
            let peak = i < receiverPeak.count ? receiverPeak[i] : 0
            ctx.fill(Path(CGRect(x: x, y: ry - 6, width: bw, height: 12)), with: .color(.white.opacity(0.06)))
            ctx.fill(Path(CGRect(x: x, y: ry - 6, width: bw * peak, height: 12)), with: .color(receiverHue(i)))
        }
        // per-column activity matrix
        let my = ry + 34, mh = size.height - my - 90
        for c in 0..<8 {
            let cx = pad + CGFloat(c) * w / 8, cw = w / 8 - 6
            let liveC = c == col && playing
            if liveC { ctx.fill(Path(roundedRect: CGRect(x: cx - 2, y: my - 2, width: cw + 4, height: mh + 4), cornerRadius: 4), with: .color(accent.opacity(0.12))) }
            for r in 0..<8 {
                let cy = my + CGFloat(r) * mh / 8, ch = mh / 8 - 3
                let rect = CGRect(x: cx, y: cy, width: cw, height: ch)
                if let fc = all.first(where: { $0.col == c && $0.row == r }) {
                    ctx.opacity = liveC ? 1 : 0.45
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(fc.hue)); ctx.opacity = 1
                } else {
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(.white.opacity(0.04)))
                }
            }
            ctx.draw(Text("\(c+1)").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(liveC ? accent : .white.opacity(0.3)), at: CGPoint(x: cx + cw/2, y: my + mh + 10))
        }
        // emitter output ladders
        let ey = size.height - 46
        ctx.draw(Text("OUTPUT").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.4)), at: CGPoint(x: pad + 26, y: ey))
        for i in 0..<4 {
            let x = pad + 70 + CGFloat(i) * (w - 70) / 4
            let peak = i < emitPeak.count ? emitPeak[i] : 0
            for s in 0..<10 { ctx.opacity = Double(peak) * 10 > Double(s) ? 0.95 : 0.12
                let col = s < 6 ? Color(red: 0.24, green: 0.86, blue: 0.52) : (s < 8 ? Color(red: 1, green: 0.77, blue: 0.24) : Color(red: 1, green: 0.29, blue: 0.2))
                ctx.fill(Path(CGRect(x: x + CGFloat(s)*9, y: ey - 5, width: 6.5, height: 12)), with: .color(col)); ctx.opacity = 1 }
            ctx.draw(Text("\("ABCD"[i])").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(accent), at: CGPoint(x: x - 8, y: ey + 1))
        }
        ctx.draw(Text("SCOPE · PASS \(pass)").font(.system(size: 8, design: .monospaced)).foregroundColor(.white.opacity(0.3)), at: CGPoint(x: size.width - 70, y: pad + 6))
    }

    // 4 — WATERFALL: emitter lanes A–D; emissions rain downward over recent time (a scrolling piano-roll).
    func renderWaterfall(_ ctx: GraphicsContext, _ size: CGSize, _ b: Double) {
        var ctx = ctx
        let pad: CGFloat = 16, w = size.width - 2*pad, top = pad + 18, bottom = size.height - 24
        let laneW = w / 4, window = stepBeats * 4        // beats of history shown
        let all = cells
        for i in 0..<4 {
            let lx = pad + CGFloat(i) * laneW
            ctx.fill(Path(CGRect(x: lx, y: top, width: laneW - 6, height: bottom - top)), with: .color(.white.opacity(0.03)))
            ctx.draw(Text("EMIT \("ABCD"[i])").font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(accent.opacity(0.7)), at: CGPoint(x: lx + laneW/2 - 3, y: top - 8))
        }
        guard playing else { return }
        // For each cell → bus, walk the ticks that fired within the window; place each by its age.
        let step = max(0.1, stepBeats)
        for fc in all { for bus in fc.buses {
            let lane = pad + CGFloat(bus) * laneW + 6
            // iterate the tick grid backward over the window
            let firstTick = Int(floor((b - window) / step * Double(fc.ticks)))
            let lastTick = Int(floor(b / step * Double(fc.ticks)))
            guard lastTick >= firstTick else { continue }
            for gt in firstTick...lastTick {
                // this tick fires only when its cell's column is the one it belongs to
                let tBeat = Double(gt) * step / Double(fc.ticks)
                let colAt = ((Int(floor(tBeat / step)) % 8) + 8) % 8
                guard colAt == fc.col else { continue }
                let age = b - tBeat; guard age >= 0, age <= window else { continue }
                let y = top + CGFloat(age / window) * (bottom - top)
                let fade = 1 - age / window
                let vel = 0.6 + 0.4 * sin(Double(gt) * 1.9)
                ctx.opacity = fade
                glowDot(ctx, CGPoint(x: lane + laneW/2 - 6, y: y), 2.5 + 3 * vel, fc.hue, 1)
                ctx.opacity = 1
            }
        } }
        // "now" line
        ctx.stroke(Path { p in p.move(to: CGPoint(x: pad, y: top)); p.addLine(to: CGPoint(x: pad + w, y: top)) }, with: .color(accent.opacity(0.4)), lineWidth: 1)
    }

    // 5 — RADAR: the 8 columns as radial spokes; the playhead sweeps like a radar beam; cells ride their spoke.
    func renderRadar(_ ctx: GraphicsContext, _ size: CGSize, _ b: Double) {
        var ctx = ctx
        let ctr = CGPoint(x: size.width/2, y: size.height/2)
        let rad = min(size.width, size.height)/2 - 20
        let (col, frac, _) = clock(b)
        let all = cells
        // rings + spokes
        for k in 1...8 { let rr = rad * CGFloat(k)/8
            ctx.stroke(Path(ellipseIn: CGRect(x: ctr.x-rr, y: ctr.y-rr, width: rr*2, height: rr*2)), with: .color(.white.opacity(0.04)), lineWidth: 1) }
        func ang(_ c: Int) -> Double { -Double.pi/2 + Double(c)/8 * 2 * .pi }
        for c in 0..<8 {
            let a = ang(c), end = CGPoint(x: ctr.x + cos(a)*rad, y: ctr.y + sin(a)*rad)
            ctx.stroke(Path { p in p.move(to: ctr); p.addLine(to: end) }, with: .color(.white.opacity(c == col ? 0.14 : 0.05)), lineWidth: 1)
        }
        // sweep beam (continuous angle from the beat)
        if playing {
            let sweep = -Double.pi/2 + (Double(col) + frac)/8 * 2 * .pi
            for s in 0..<14 { let a = sweep - Double(s)*0.03
                ctx.opacity = (1 - Double(s)/14) * 0.28
                ctx.stroke(Path { p in p.move(to: ctr); p.addLine(to: CGPoint(x: ctr.x+cos(a)*rad, y: ctr.y+sin(a)*rad)) }, with: .color(accent), lineWidth: 2); ctx.opacity = 1 }
        }
        // cells on their spoke (radius by row), comets flying outward toward the rim on emission
        for fc in all {
            let a = ang(fc.col), rr = rad * (0.28 + 0.62 * CGFloat(fc.row)/7)
            let p = CGPoint(x: ctr.x + cos(a)*rr, y: ctr.y + sin(a)*rr)
            let live = fc.col == col
            glowDot(ctx, p, live ? 6 : 3.4, fc.hue, live ? 1 : 0.45)
            guard playing, live, !fc.buses.isEmpty else { continue }
            for k in 0..<fc.ticks {
                let tt = frac * Double(fc.ticks) - Double(k); guard tt >= 0, tt <= 1 else { continue }
                let out = rr + (rad - rr) * CGFloat(tt)
                let cp = CGPoint(x: ctr.x + cos(a)*out, y: ctr.y + sin(a)*out)
                ctx.opacity = 1 - tt * 0.5
                glowDot(ctx, cp, 2 + 2.4*(1-tt), fc.hue, 1); ctx.opacity = 1
            }
        }
        glowDot(ctx, ctr, 4, accent, 0.8)
    }
}

private extension String {
    subscript(_ i: Int) -> Character { self[index(startIndex, offsetBy: i)] }
}
