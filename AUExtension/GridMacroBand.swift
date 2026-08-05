import SwiftUI

/// GRID CONTROL BAND controls (layout-v2, user 2026-08-05) — the 8 macro ROTARIES (slider bank) and 8 macro BUTTONS
/// (button bank) that sit under the grid. Compact, self-contained (their own live drag state); they drive the macro
/// values through the AU param tree, so they stay in sync with the MACROS tab + host automation.

/// One macro rotary — a 270° gauge; a vertical drag turns it (up = more), relative to the value at drag start.
struct GridMacroRotary: View {
    let index: Int
    let value: Double
    let onSet: (Int, Double) -> Void

    @State private var v: Double = 0
    @State private var dragBase: Double? = nil
    @GestureState private var dragging = false
    private let hue = Color(red: 0.15, green: 0.88, blue: 0.94)

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle().trim(from: 0, to: 0.75)
                    .stroke(Color.white.opacity(0.14), style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(135))
                Circle().trim(from: 0, to: 0.75 * v)
                    .stroke(hue.opacity(0.9), style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(135))
                Capsule().fill(hue).frame(width: 2, height: 11).offset(y: -7).rotationEffect(.degrees(-135 + 270 * v))
            }
            .frame(width: 34, height: 34)
            Text("M\(index + 1)").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, s, _ in s = true }
            .onChanged { g in
                if dragBase == nil { dragBase = v }
                let nv = max(0, min(1, (dragBase ?? v) - Double(g.translation.height) / 140))
                v = nv; onSet(index, nv)
            }
            .onEnded { _ in dragBase = nil })
        .onAppear { v = value }
        .onChange(of: value) { nv in if !dragging { v = nv } }
    }
}

/// One macro slider — a compact VERTICAL fader (absolute: the touch position sets the value, drag to trim). Replaces
/// the grid-band rotary (user 2026-08-05); drives the macro value through the AU param tree like the MACROS-tab bank.
struct GridMacroSlider: View {
    let index: Int
    let value: Double
    let onSet: (Int, Double) -> Void

    @State private var v: Double = 0
    @GestureState private var dragging = false
    private let hue = Color(red: 0.15, green: 0.88, blue: 0.94)

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { g in
                let h = g.size.height
                ZStack(alignment: .bottom) {
                    Capsule().fill(Color.white.opacity(0.10)).frame(width: 5)
                    Capsule().fill(hue.opacity(0.9)).frame(width: 5, height: max(4, h * CGFloat(v)))
                    RoundedRectangle(cornerRadius: 2).fill(hue).frame(width: 16, height: 4)
                        .offset(y: -(h - 4) * CGFloat(v))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0).updating($dragging) { _, s, _ in s = true }
                    .onChanged { gg in
                        let nv = max(0, min(1, 1 - Double(gg.location.y / max(1, h))))   // ABSOLUTE: touch position = value
                        v = nv; onSet(index, nv)
                    })
            }
            .frame(height: 40)
            Text("M\(index + 1)").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
        }
        .onAppear { v = value }
        .onChange(of: value) { nv in if !dragging { v = nv } }
    }
}

/// One macro button — SPRING (momentary: press = B, release = A) or FIXED (toggle) per the macro's padlock.
struct GridMacroButton: View {
    let index: Int          // 8…15 (the button bank)
    let value: Double
    let fixed: Bool
    let onSet: (Int, Double) -> Void

    @State private var on = false
    private let hue = Color(red: 0.98, green: 0.72, blue: 0.12)

    var body: some View {
        VStack(spacing: 2) {
            RoundedRectangle(cornerRadius: 4).fill(on ? hue.opacity(0.9) : Color.white.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.1), lineWidth: 1))
                .frame(width: 34, height: 26)
                .contentShape(Rectangle())
                .gesture(fixed
                    ? AnyGesture(TapGesture().onEnded { on.toggle(); onSet(index, on ? 1 : 0) }.map { _ in () })
                    : AnyGesture(DragGesture(minimumDistance: 0)
                        .onChanged { _ in if !on { on = true; onSet(index, 1) } }
                        .onEnded { _ in on = false; onSet(index, 0) }.map { _ in () }))
            Text("B\(index - 7)").font(.system(size: 7, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
        }
        .onAppear { on = value >= 0.5 }
        .onChange(of: value) { on = $0 >= 0.5 }
    }
}
