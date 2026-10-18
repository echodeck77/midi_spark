//  MixPadPainter.swift
//  The MIX tab's XY PAD (gate × velocity) and OCT STEPPER (ferry "MIX tab", 2026-10-18).
//
//  SwiftUI-only on purpose (GridUI seam rule: no UIKit, no AU frameworks), like `OutputRingPainter.swift`: every number — region
//  rects, puck centre, ticks, and the touch-to-value inverse — comes from the pure `EuclideousMixPadGeometry` in Derivations.swift,
//  so the drawing and the touch can never disagree about where a value sits. The pad owns only its own touch state (one finger per
//  pad, independent of every other pad), and reports values + undo checkpoints through `onEditStep`.

import SwiftUI

private extension Color {
    init(h: UInt32) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}

enum EuclideousMixPalette {
    static let track = Color(h: 0x22252C)
    static let axis = Color(h: 0x3A3E47)
    static let tick = Color(h: 0x4A4E57)
    static let puckRing = Color(h: 0x15161A)
    static let value = Color(h: 0xF2F4F7)
    static let name = Color(h: 0x8A909A)
    static let stepper = Color(h: 0x2A2D34)
    static let glyph = Color(h: 0xAAB0BA)
    static let glyphDisabled = Color(h: 0x4A4E57)
    // §3.15 / §5.6 — a layer that's OFF still edits, but reads grey.
    static let offAccent = Color(h: 0x6A7079)
    static let offName = Color(h: 0x5C626C)
    static let offValue = Color(h: 0x8A909A)
    static let offGlyph = Color(h: 0x5C626C)
}

private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// One pad: VEL strip (left), GATE strip (bottom), the plot with its puck. `gate` is a fraction (0.01…1), `velocity` 1…127.
struct EuclideousMixPad: View {
    let cellW: CGFloat
    let padH: CGFloat
    let gate: Double
    let velocity: Int
    let accent: Color
    let off: Bool
    let notes: Bool
    let accessibilityLabelText: String
    /// The page's `editStep`: `newStep == true` takes an undo checkpoint first (once per touch burst), then mutates the lane.
    let onEditStep: (Bool, @escaping (inout EuclidLine) -> Void) -> Void
    /// Preview/harness hook only: draw the TOUCHED look (16pt puck + glow) without a finger. Never set by the page.
    var showTouched = false

    @State private var touchingState = false
    @State private var burst = EuclideousPadUndoBurst()
    @State private var lastWritten: (gate: Double, velocity: Int)? = nil
    @State private var startLocation: CGPoint? = nil
    @State private var lastShortTapAt: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var touching: Bool { touchingState || showTouched }
    private var geo: EuclideousMixPadGeometry { EuclideousMixPadGeometry(cellW: cellW, padH: padH) }
    private func now() -> Double { Date().timeIntervalSinceReferenceDate }

    var body: some View {
        let g = geo
        let lane = off ? EuclideousMixPalette.offAccent : accent
        let nameColour = off ? EuclideousMixPalette.offName : EuclideousMixPalette.name
        let valueColour = off ? EuclideousMixPalette.offValue : EuclideousMixPalette.value
        let puck = g.puck(gate: gate, velocity: velocity)
        let d: CGFloat = touching ? 16 : 12
        return ZStack(alignment: .topLeading) {
            // track, fill, axes, ticks, extension lines, value lines — §3.11's back-to-front order
            Canvas { ctx, _ in
                ctx.fill(Path(roundedRect: g.track, cornerRadius: 6), with: .color(EuclideousMixPalette.track))
                ctx.fill(Path(CGRect(x: g.plot.minX, y: puck.y, width: max(0, puck.x - g.plot.minX), height: max(0, g.plotH - puck.y))),
                         with: .color(lane.opacity(off ? 0.16 : 0.20)))
                ctx.fill(Path(g.yAxis), with: .color(EuclideousMixPalette.axis)); ctx.fill(Path(g.xAxis), with: .color(EuclideousMixPalette.axis))
                for x in g.tickXs { ctx.fill(Path(CGRect(x: x - 0.5, y: g.plotH - 4, width: 1, height: 4)), with: .color(EuclideousMixPalette.tick)) }
                for y in g.tickYs { ctx.fill(Path(CGRect(x: g.plot.minX + 1, y: y - 0.5, width: 4, height: 1)), with: .color(EuclideousMixPalette.tick)) }
                // extension lines (2pt, lane @30%): up from the puck to the top, right from the puck to the trailing edge
                ctx.fill(Path(CGRect(x: puck.x - 1, y: 0, width: 2, height: max(0, puck.y))), with: .color(lane.opacity(0.30)))
                ctx.fill(Path(CGRect(x: puck.x, y: puck.y - 1, width: max(0, g.cellW - puck.x), height: 2)), with: .color(lane.opacity(0.30)))
                // value lines (2pt, lane): down from the puck to the axis, left from the puck to the VEL strip
                ctx.fill(Path(CGRect(x: puck.x - 1, y: puck.y, width: 2, height: max(0, g.plotH - puck.y))), with: .color(lane))
                ctx.fill(Path(CGRect(x: g.plot.minX, y: puck.y - 1, width: max(0, puck.x - g.plot.minX), height: 2)), with: .color(lane))
            }
            .frame(width: cellW, height: padH)
            // VEL strip text: the value (11pt, 14pt line box at y 3…17) and the name turned to read bottom-to-top
            Text("\(velocity)").font(heavyMono(11)).monospacedDigit().foregroundColor(valueColour).lineLimit(1)
                .frame(width: EuclideousMixMetrics.velStripW, height: 14).offset(x: 0, y: 3)
            Text("VEL").font(heavyMono(8)).tracking(0.08 * 8).foregroundColor(nameColour).lineLimit(1).fixedSize()
                .rotationEffect(.degrees(-90))
                .position(x: EuclideousMixMetrics.velStripW / 2, y: g.plotH - 4 - (3 * 8 * (0.6 + 0.08)) / 2)
            // GATE strip text: name (truncates) from x 27, value (never truncates) ending 4pt from the trailing edge
            HStack(spacing: 0) {   // no extra gap: the name only truncates if it would actually TOUCH the value (LEGATO fits at the reference width)
                Text(euclideousMixGateName(gate: gate)).font(heavyMono(8)).tracking(0.08 * 8).foregroundColor(nameColour)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
                Text(euclideousMixGateValueText(gate: gate)).font(heavyMono(11)).monospacedDigit().foregroundColor(valueColour).lineLimit(1).fixedSize()
                    .layoutPriority(1)
            }
            .padding(.leading, 3).padding(.trailing, 4)
            .frame(width: g.gateStrip.width, height: EuclideousMixMetrics.gateStripH)
            .offset(x: g.gateStrip.minX, y: g.gateStrip.minY)
            // the puck: a 12pt disc (16 while touched, with a glow) inside a 2pt #15161A ring; the size eases over 0.15 s
            ZStack {
                Circle().fill(EuclideousMixPalette.puckRing).frame(width: d + 4, height: d + 4)
                Circle().fill(lane).frame(width: d, height: d)
                    .shadow(color: touching ? lane.opacity(0.55) : .clear, radius: 6)   // ≈ the design's 12pt blur, no offset
            }
            .position(puck)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.15), value: touching)
            .allowsHitTesting(false)
        }
        .frame(width: cellW, height: padH, alignment: .topLeading)
        .clipShape(RoundedRectangle(cornerRadius: 6))   // everything drawn in the pad is clipped to the track
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { drag in
                    if !touchingState { touchingState = true; startLocation = drag.location; lastWritten = nil; burst.touchDown(at: now()) }
                    apply(drag.location)
                }
                .onEnded { drag in
                    let start = startLocation ?? drag.location
                    let moved = hypot(drag.location.x - start.x, drag.location.y - start.y)
                    touchingState = false; startLocation = nil
                    burst.touchEnd(at: now())
                    if moved <= 4 {
                        if let last = lastShortTapAt, now() - last <= EuclideousPadUndoBurst.continueWithin { lastShortTapAt = nil; reset() }
                        else { lastShortTapAt = now() }
                    } else { lastShortTapAt = nil }
                }
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(euclideousMixPadAccessibilityValue(gate: gate, velocity: velocity))
        .accessibilityAdjustableAction { direction in
            write(gate: gate, velocity: euclideousMixVelocityStep(velocity, up: direction == .increment), newStepAlways: true)
        }
        .accessibilityAction(named: "Longer gate") { write(gate: euclideousMixGateStep(gate, longer: true), velocity: velocity, newStepAlways: true) }
        .accessibilityAction(named: "Shorter gate") { write(gate: euclideousMixGateStep(gate, longer: false), velocity: velocity, newStepAlways: true) }
        .accessibilityAction(named: "Reset") { resetAlways() }
    }

    /// Touch-to-value: a touch anywhere on the pad sets BOTH values from that point (§4.1). "No change, no commit": a touch that
    /// lands on the values it already has writes nothing (and so opens no undo step).
    private func apply(_ p: CGPoint) {
        let v = geo.values(at: p)
        if let last = lastWritten, abs(last.gate - v.gate) < 1e-9, last.velocity == v.velocity { return }
        lastWritten = v
        if abs(v.gate - gate) < 1e-9, v.velocity == velocity { return }
        write(gate: v.gate, velocity: v.velocity, newStepAlways: false)
    }
    private func write(gate g: Double, velocity v: Int, newStepAlways: Bool) {
        let newStep = newStepAlways ? true : burst.nextWriteNeedsNewStep()
        let notes = notes
        onEditStep(newStep) { l in euclideousMixPadWrite(&l, notes: notes, gate: g, velocity: v) }
    }
    /// Double tap (§4.4): both values return to a new lane's GATE 90% / VEL 100, merged into the burst the first tap opened.
    private func reset() {
        if abs(gate - 0.9) < 1e-9, velocity == 100 { return }   // already there — nothing to undo
        let newStep = burst.nextWriteNeedsNewStep()
        let notes = notes
        onEditStep(newStep) { l in euclideousMixPadReset(&l, notes: notes) }
    }
    private func resetAlways() {
        let notes = notes
        onEditStep(true) { l in euclideousMixPadReset(&l, notes: notes) }
    }
}

/// The OCT stepper under each pad: − and + buttons (28 × 28) at the ends, "OCT" + the octave centred between them.
struct EuclideousMixOctaveStepper: View {
    let cellW: CGFloat
    let octave: Int
    let accent: Color
    let off: Bool
    let accessibilityLabelText: String
    let onSet: (Int) -> Void

    var body: some View {
        let minus = euclideousMixOctaveNext(octave, up: false), plus = euclideousMixOctaveNext(octave, up: true)
        let octaveColour: Color = off ? EuclideousMixPalette.offValue : (octave == 0 ? EuclideousMixPalette.value : accent)
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(EuclideousMixPalette.stepper)
            HStack(spacing: 0) {
                button("minus", enabled: minus != nil) { if let m = minus { onSet(m) } }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("OCT").font(heavyMono(8)).tracking(0.08 * 8).foregroundColor(off ? EuclideousMixPalette.offName : EuclideousMixPalette.name).lineLimit(1)
                    Text(euclideousMixOctaveText(octave)).font(heavyMono(13)).monospacedDigit().foregroundColor(octaveColour).lineLimit(1)
                }
                Spacer(minLength: 0)
                button("plus", enabled: plus != nil) { if let p = plus { onSet(p) } }
            }
        }
        .frame(width: cellW, height: EuclideousMixMetrics.stepperH)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(euclideousMixOctaveSpoken(octave))
        .accessibilityAdjustableAction { direction in
            if let n = euclideousMixOctaveNext(octave, up: direction == .increment) { onSet(n) }
        }
    }
    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .heavy))
            .foregroundColor(!enabled ? EuclideousMixPalette.glyphDisabled : (off ? EuclideousMixPalette.offGlyph : EuclideousMixPalette.glyph))
            .frame(width: EuclideousMixMetrics.stepperH, height: EuclideousMixMetrics.stepperH)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}
