//  LaneSoloPainter.swift
//  The SOLO button that replaced the step-count box at the end of each lane's comet row (LANE SOLO ferry, 2026-10-21), and the touch handling behind it.
//
//  SwiftUI-only on purpose (GridUI seam rule), like `OutputRingPainter.swift`. All the decisions are pure and live in Derivations.swift: the look (`euclideousSoloButtonLook`), tap vs hold
//  (`EuclideousSoloPress`, `euclideousSoloLatchAfter`), the words. This file only draws and wires a finger to them.

import SwiftUI

private extension Color {
    init(h: UInt32) {
        self.init(.sRGB, red: Double((h >> 16) & 0xFF) / 255, green: Double((h >> 8) & 0xFF) / 255, blue: Double(h & 0xFF) / 255, opacity: 1)
    }
}

enum EuclideousSoloPalette {
    static let offFill = Color(h: 0x2A2D34)
    static let offBorder = Color(h: 0x3A3E47)
    static let offLabel = Color(h: 0xAAB0BA)
    static let ink = Color(h: 0x0D0F14)
    static let heldFill = Color(h: 0xDFE3EA)   // the header's held look (`headerHoldLatchChip` active)
    static let size: CGFloat = 44, radius: CGFloat = 9   // the step-count box's frame and the play button's radius
}

/// §2: 44 × 44, radius 9, "SOLO" 10 pt heavy mono at 0.06 em, centred, truncating never shrinking. OFF: #2A2D34 + a 1 pt #3A3E47 inner border + #AAB0BA; LATCHED: lane colour, no border, ink; HELD (from 300 ms
/// until release, latched or not): #DFE3EA, no border, ink. It changes look at once (no ease) and is never dimmed — the caller never puts an opacity on it.
struct EuclideousSoloButton: View {
    let accent: Color
    let latched: Bool
    let heldLook: Bool
    typealias P = EuclideousSoloPalette

    var body: some View {
        let look = euclideousSoloButtonLook(latched: latched, heldLook: heldLook)
        let fill: Color = look == .off ? P.offFill : (look == .latched ? accent : P.heldFill)
        Text("SOLO")
            .font(.system(size: 10, weight: .heavy, design: .monospaced)).tracking(0.6)
            .foregroundColor(look == .off ? P.offLabel : P.ink)
            .lineLimit(1).truncationMode(.tail)
            .frame(width: P.size, height: P.size)
            .background(RoundedRectangle(cornerRadius: P.radius).fill(fill))
            .overlay {
                if look == .off { RoundedRectangle(cornerRadius: P.radius).inset(by: 0.5).stroke(P.offBorder, lineWidth: 1) }
            }
            .transaction { $0.animation = nil }   // §2.4: at once — the card's own animations never reach it
    }
}

/// One SOLO button with its own touch (§3): its own `@State`, so two fingers on two buttons are independent (§3.5). Touch-down calls `onDown` at once — the lane counts as soloed from the moment of touch, for sound
/// and for every dim (§3.1). The button turns to its HELD look 300 ms in. Whatever lifts it, wherever the finger is (a slide-off never cancels, §3.4), ends it through `onUp(latchToggles:)`: a tap (under 300 ms)
/// toggles the latch, a hold leaves it. A touch the system cancels, or a button that goes away mid-touch, ends as a hold would. VoiceOver's activation is a tap (§3.2).
struct EuclideousSoloPressable: View {
    let lane: Int
    let accent: Color
    let latched: Bool
    let onDown: () -> Void
    /// `true` = a tap (flip the latch); `false` = a hold / cancel (leave it). Either way the held bit is cleared — in the SAME update, so a tap never flickers.
    let onUp: (_ latchToggles: Bool) -> Void

    @State private var press = EuclideousSoloPress()
    @State private var heldLook = false
    @State private var holdTask: Task<Void, Never>? = nil
    @GestureState private var touching = false

    private func now() -> Double { ProcessInfo.processInfo.systemUptime }

    var body: some View {
        EuclideousSoloButton(accent: accent, latched: latched, heldLook: heldLook)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .updating($touching) { _, t, _ in t = true }
                    .onChanged { _ in
                        guard !press.down else { return }
                        press.touchDown(at: now())
                        onDown()
                        holdTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: UInt64(EuclideousRingPress.holdSeconds * 1_000_000_000))
                            guard !Task.isCancelled else { return }
                            press.holdTimerFired()
                            heldLook = press.showsHeldLook
                        }
                    }
                    .onEnded { _ in finish(cancelled: false) }
            )
            .onChange(of: touching) { t in
                // The finger is gone. After a normal release `onEnded` has already reset `press`, so this is a no-op; after a CANCELLED touch `onEnded` never runs and this ends the touch as a hold would.
                // Deferred one turn so it can never race ahead of `onEnded` and eat a tap.
                guard !t else { return }
                Task { @MainActor in if press.down { finish(cancelled: true) } }
            }
            .onDisappear { if press.down { finish(cancelled: true) } }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(euclideousSoloAccessibilityLabel(lane: lane))
            .accessibilityValue(euclideousSoloAccessibilityValue(latched: latched))
            .accessibilityHint(euclideousSoloAccessibilityHint)
            .accessibilityAddTraits(.isButton)
            .ringToggleTrait()
            .accessibilityAction { onUp(true) }   // §3.2: a VoiceOver double-tap is a tap
    }

    private func finish(cancelled: Bool) {
        holdTask?.cancel(); holdTask = nil
        let r = cancelled ? press.touchCancelled() : press.touchEnded(at: now())
        heldLook = false
        if case .ended(let toggles) = r { onUp(toggles) }
    }
}

/// How dimmed each of the four lanes is, 0 (full strength) … 1 (the OFF-dim 42 %). A `VectorArithmetic` so a painter that draws these in a Canvas can be an `Animatable` view: SwiftUI then re-evaluates its body with
/// interpolated levels for the 0.15 s ease (a Canvas's contents cannot be animated by an opacity modifier from outside, and a lane's quarter is just one stroke inside it).
struct EuclideousLaneDimLevels: VectorArithmetic, Equatable {
    var l0 = 0.0, l1 = 0.0, l2 = 0.0, l3 = 0.0
    init() {}
    init(_ flags: [Bool]) {
        func f(_ i: Int) -> Double { i < flags.count && flags[i] ? 1 : 0 }
        l0 = f(0); l1 = f(1); l2 = f(2); l3 = f(3)
    }
    subscript(lane: Int) -> Double { [l0, l1, l2, l3][max(0, min(3, lane))] }
    /// The lane's drawn opacity: 1 at level 0, 0.42 at level 1.
    func opacity(_ lane: Int) -> Double { 1 - (1 - EuclideousLaneDimStyle.opacity) * self[lane] }
    static var zero: EuclideousLaneDimLevels { EuclideousLaneDimLevels() }
    static func += (a: inout Self, b: Self) { a.l0 += b.l0; a.l1 += b.l1; a.l2 += b.l2; a.l3 += b.l3 }
    static func -= (a: inout Self, b: Self) { a.l0 -= b.l0; a.l1 -= b.l1; a.l2 -= b.l2; a.l3 -= b.l3 }
    static func + (a: Self, b: Self) -> Self { var r = a; r += b; return r }
    static func - (a: Self, b: Self) -> Self { var r = a; r -= b; return r }
    mutating func scale(by rhs: Double) { l0 *= rhs; l1 *= rhs; l2 *= rhs; l3 *= rhs }
    var magnitudeSquared: Double { l0 * l0 + l1 * l1 + l2 * l2 + l3 * l3 }
}
