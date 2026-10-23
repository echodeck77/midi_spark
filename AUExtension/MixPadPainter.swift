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
    // CLARITY PASS (2026-10-23) §3.4/§3.7: the pad's label (on / off), the OFF word, and the colour of a readout's value.
    static let labelOn = Color(h: 0xF2F4F7)
    static let labelOff = Color(h: 0xAAB0BA)
}

private func heavyMono(_ size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .monospaced) }

/// One pad: the plot with its puck, a label top-left ("RIFF" / "NOTES" + the tab's glyph), the VEL and GATE readouts along the bottom. `gate` is a fraction (0.01…1), `velocity` 1…127. CLARITY PASS (2026-10-23): the 24 pt VEL
/// strip and its rotated name are gone, and a pad whose layer is OFF is an inert dashed outline marked OFF — it takes no touch and shows no knob.
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
        if off { disabledBody } else { enabledBody }
    }

    /// §3.4: "RIFF" or "NOTES" then the tab's glyph in the same state, 10 pt heavy in the tab row's face and tracking, inset 5 from the top and 6 from the left. On: #F2F4F7; off: #AAB0BA.
    private var padLabel: some View {
        HStack(spacing: 5) {
            Text(notes ? "NOTES" : "RIFF").font(heavyMono(EuclideousMixMetrics.labelSize)).tracking(1)
                .foregroundColor(off ? EuclideousMixPalette.labelOff : EuclideousMixPalette.labelOn).lineLimit(1)
            EuclideousTabGlyphView(shape: notes ? .bar : .square, on: !off, fills: [accent])
        }
        .padding(.top, EuclideousMixMetrics.labelTop).padding(.leading, EuclideousMixMetrics.labelLeft)
        .allowsHitTesting(false)
    }

    /// §3.7: lane100 at 7 %, a 1.5 pt dashed (3 on, 2 off) lane100 inner border at 45 %, the pad's own radius; "OFF" centred (12 pt heavy, #AAB0BA, 2 pt tracking); the label as its off look. No fill area, edges or knob, no gesture:
    /// a touch does nothing, so the pad's velocity and gate are kept as stored and the layer is never turned on from here. VoiceOver reads the label only ("Lane 1 riff, off").
    private var disabledBody: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.07))
            RoundedRectangle(cornerRadius: 6).strokeBorder(accent.opacity(0.45), style: StrokeStyle(lineWidth: 1.5, dash: [3, 2]))
            Text(euclideousMixOffWord).font(heavyMono(12)).tracking(2).foregroundColor(EuclideousMixPalette.labelOff).lineLimit(1)
        }
        .frame(width: cellW, height: padH)
        .overlay(alignment: .topLeading) { padLabel }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
    }

    /// §3.5: "VEL 100" bottom-left, "GATE 90%" bottom-right, 10 pt, inset 4 from the bottom and 6 from the side; the words yield to the numbers by pad width (`euclideousMixReadouts`). The word is the quiet #8A909A, the number #F2F4F7.
    private func readout(_ s: String) -> Text {
        let font = heavyMono(EuclideousMixMetrics.labelSize)
        guard let space = s.firstIndex(of: " ") else { return Text(s).font(font).foregroundColor(EuclideousMixPalette.value) }
        return Text(String(s[..<space]) + " ").font(font).foregroundColor(EuclideousMixPalette.name) + Text(String(s[s.index(after: space)...])).font(font).foregroundColor(EuclideousMixPalette.value)
    }
    private var readouts: some View {
        let r = euclideousMixReadouts(padWidth: cellW, velocity: velocity, gate: gate)
        return HStack(spacing: 4) {
            readout(r.velocity).lineLimit(1).fixedSize()
            Spacer(minLength: 0)
            readout(r.gate).lineLimit(1).fixedSize()
        }
        .padding(.horizontal, EuclideousMixMetrics.readoutSide).padding(.bottom, EuclideousMixMetrics.readoutBottom)
        .frame(width: cellW, height: padH, alignment: .bottom)
        .allowsHitTesting(false)
    }

    private var enabledBody: some View {
        let g = geo
        let lane = accent
        let puck = g.puck(gate: gate, velocity: velocity)
        let d: CGFloat = touching ? 16 : 12
        return ZStack(alignment: .topLeading) {
            // track, fill, axes, ticks, extension lines, value lines — §3.11's back-to-front order
            Canvas { ctx, _ in
                ctx.fill(Path(roundedRect: g.track, cornerRadius: 6), with: .color(EuclideousMixPalette.track))
                ctx.fill(Path(CGRect(x: g.plot.minX, y: puck.y, width: max(0, puck.x - g.plot.minX), height: max(0, g.plotH - puck.y))),
                         with: .color(lane.opacity(0.20)))
                ctx.fill(Path(g.yAxis), with: .color(EuclideousMixPalette.axis)); ctx.fill(Path(g.xAxis), with: .color(EuclideousMixPalette.axis))
                for x in g.tickXs { ctx.fill(Path(CGRect(x: x - 0.5, y: g.plotH - 4, width: 1, height: 4)), with: .color(EuclideousMixPalette.tick)) }
                for y in g.tickYs { ctx.fill(Path(CGRect(x: g.plot.minX + 1, y: y - 0.5, width: 4, height: 1)), with: .color(EuclideousMixPalette.tick)) }
                // extension lines (2pt, lane @30%): up from the puck to the top, right from the puck to the trailing edge
                ctx.fill(Path(CGRect(x: puck.x - 1, y: 0, width: 2, height: max(0, puck.y))), with: .color(lane.opacity(0.30)))
                ctx.fill(Path(CGRect(x: puck.x, y: puck.y - 1, width: max(0, g.cellW - puck.x), height: 2)), with: .color(lane.opacity(0.30)))
                // value lines (2pt, lane): down from the puck to the axis, left from the puck to the pad's leading edge
                ctx.fill(Path(CGRect(x: puck.x - 1, y: puck.y, width: 2, height: max(0, g.plotH - puck.y))), with: .color(lane))
                ctx.fill(Path(CGRect(x: g.plot.minX, y: puck.y - 1, width: max(0, puck.x - g.plot.minX), height: 2)), with: .color(lane))
            }
            .frame(width: cellW, height: padH)
            readouts
            padLabel
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
        onEditStep(newStep) { l in euclideousMixPadWriteIfEnabled(&l, notes: notes, gate: g, velocity: v) }   // §3.7: even a stale view cannot write an OFF pad
    }
    /// Double tap (§4.4): both values return to a new lane's GATE 90% / VEL 100, merged into the burst the first tap opened.
    private func reset() {
        if abs(gate - 0.9) < 1e-9, velocity == 100 { return }   // already there — nothing to undo
        let newStep = burst.nextWriteNeedsNewStep()
        let notes = notes
        onEditStep(newStep) { l in euclideousMixPadResetIfEnabled(&l, notes: notes) }
    }
    private func resetAlways() {
        let notes = notes
        onEditStep(true) { l in euclideousMixPadResetIfEnabled(&l, notes: notes) }
    }
}

/// The OCT stepper under each pad: − and + buttons (28 × 28) at the ends, "OCT" + the octave centred between them. CLARITY PASS (2026-10-23) §3.7: under an OFF pad it keeps its normal look at `opacity` 0.5 (the page passes 1
/// while the lane is solo-silenced — the panel's own 42 % covers it) and still edits.
struct EuclideousMixOctaveStepper: View {
    let cellW: CGFloat
    let octave: Int
    let accent: Color
    var opacity: Double = 1
    let accessibilityLabelText: String
    let onSet: (Int) -> Void

    var body: some View {
        let minus = euclideousMixOctaveNext(octave, up: false), plus = euclideousMixOctaveNext(octave, up: true)
        let octaveColour: Color = octave == 0 ? EuclideousMixPalette.value : accent
        return ZStack {
            RoundedRectangle(cornerRadius: 6).fill(EuclideousMixPalette.stepper)
            HStack(spacing: 0) {
                button("minus", enabled: minus != nil) { if let m = minus { onSet(m) } }
                Spacer(minLength: 0)
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text("OCT").font(heavyMono(8)).tracking(0.08 * 8).foregroundColor(EuclideousMixPalette.name).lineLimit(1)
                    Text(euclideousMixOctaveText(octave)).font(heavyMono(13)).monospacedDigit().foregroundColor(octaveColour).lineLimit(1)
                }
                Spacer(minLength: 0)
                button("plus", enabled: plus != nil) { if let p = plus { onSet(p) } }
            }
        }
        .frame(width: cellW, height: EuclideousMixMetrics.stepperH)
        .opacity(opacity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabelText)
        .accessibilityValue(euclideousMixOctaveSpoken(octave))
        .accessibilityAdjustableAction { direction in
            if let n = euclideousMixOctaveNext(octave, up: direction == .increment) { onSet(n) }
        }
    }
    private func button(_ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Image(systemName: symbol).font(.system(size: 12, weight: .heavy))
            .foregroundColor(!enabled ? EuclideousMixPalette.glyphDisabled : EuclideousMixPalette.glyph)
            .frame(width: EuclideousMixMetrics.stepperH, height: EuclideousMixMetrics.stepperH)
            .contentShape(Rectangle())
            .onTapGesture { if enabled { action() } }
    }
}


// MARK: - PULSE (ferry 2026-10-20, §5): the ripple, the fill flash, the puck swell and the OUT-button glow
//
// ONE overlay Canvas over the whole MIX grid (never one per pad — the page's standing DSP rule), painted from pure numbers: `euclideousPulseEnvelopes` / `euclideousPulseRipple` (Derivations.swift) turn a strike's played
// velocity and age into what each effect draws. The pads themselves are untouched: values, gestures, steppers and the header's pulse and trace rings on the OUT buttons are as they were.

/// One pad that has a strike to show: its frame in the overlay's coordinates, the puck centre and the VEL × GATE fill rectangle in PAD coordinates, the lane colour, and the strike (velocity 1…127, seconds since its onset).
struct EuclideousMixPulsePad: Equatable {
    var rect: CGRect
    var puck: CGPoint
    var fill: CGRect
    var colour: Color
    var velocity: Int
    var seconds: Double
}
/// One routed, main-out-on OUT button that its lane's strike should glow.
struct EuclideousMixPulseButton: Equatable {
    var rect: CGRect
    var colour: Color
    var velocity: Int
    var seconds: Double
}
struct EuclideousMixPulseOverlay: View {
    let pads: [EuclideousMixPulsePad]
    let buttons: [EuclideousMixPulseButton]
    let scale: Double
    let size: CGSize
    /// The Canvas is larger than the grid by this much on every side so a glow just outside the bottom row's buttons isn't cut off.
    static let bleed: CGFloat = 12
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let b = Self.bleed
        Canvas { ctx, _ in
            ctx.translateBy(x: b, y: b)
            let ripples = euclideousPulseFilter(.ripple, scale: scale, reduceMotion: reduceMotion) != .off
            let swell = euclideousPulseFilter(.puckSwell, scale: scale, reduceMotion: reduceMotion) != .off
            for pad in pads {
                let env = euclideousPulseEnvelopes(velocity: pad.velocity, seconds: pad.seconds, scale: scale)
                let ripple = ripples ? euclideousPulseRipple(d0: 12, velocity: pad.velocity, seconds: pad.seconds, scale: scale) : nil
                guard env.isVisible || ripple != nil else { continue }
                ctx.drawLayer { layer in
                    layer.translateBy(x: pad.rect.minX, y: pad.rect.minY)
                    layer.clip(to: Path(roundedRect: CGRect(origin: .zero, size: pad.rect.size), cornerRadius: 6))   // "clipped to the pad" (5.2)
                    // 5.3: the VEL × GATE fill takes a lane100 overlay at 25% × f
                    if env.f > 0 { layer.fill(Path(pad.fill), with: .color(pad.colour.opacity(0.25 * env.f))) }
                    // 5.2: the ripple — a 1.5 stroke ring around the puck, growing and fading with the velocity
                    if let r = ripple {
                        let d = r.diameter
                        layer.stroke(Path(ellipseIn: CGRect(x: pad.puck.x - d / 2, y: pad.puck.y - d / 2, width: d, height: d)), with: .color(pad.colour.opacity(r.opacity)), lineWidth: 1.5)
                    }
                    // 5.4: the puck swells by 6 × b (12 → up to 18) inside its 2pt #15161A ring, with an outer glow of blur 12 × f (shadow radius 6 × f) at f
                    if env.f > 0 || env.b > 0 {
                        let d: CGFloat = 12 + (swell ? 6 * CGFloat(env.b) : 0)
                        layer.drawLayer { puck in
                            puck.addFilter(.shadow(color: pad.colour.opacity(env.f), radius: 6 * CGFloat(env.f)))
                            puck.fill(Path(ellipseIn: CGRect(x: pad.puck.x - (d + 4) / 2, y: pad.puck.y - (d + 4) / 2, width: d + 4, height: d + 4)), with: .color(EuclideousMixPalette.puckRing))
                            puck.fill(Path(ellipseIn: CGRect(x: pad.puck.x - d / 2, y: pad.puck.y - d / 2, width: d, height: d)), with: .color(pad.colour))
                        }
                    }
                }
            }
            // 5.5: each routed OUT button with its main out on gains an outer glow of blur 10 × f (radius 5 × f) in lane100 at f and a white overlay at 45% × f
            for button in buttons {
                let env = euclideousPulseEnvelopes(velocity: button.velocity, seconds: button.seconds, scale: scale)
                guard env.f > 0 else { continue }
                let shape = Path(roundedRect: button.rect, cornerRadius: 6)
                ctx.drawLayer { layer in
                    layer.clip(to: shape, options: .inverse)   // only the glow OUTSIDE the button: the button (and its letter) is the page's own, drawn underneath
                    layer.addFilter(.shadow(color: button.colour.opacity(env.f), radius: 5 * CGFloat(env.f)))
                    layer.fill(shape, with: .color(button.colour))
                }
                ctx.fill(shape, with: .color(.white.opacity(0.45 * env.f)))
            }
        }
        .frame(width: size.width + 2 * b, height: size.height + 2 * b)
        .offset(x: -b, y: -b)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
