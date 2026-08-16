import SwiftUI

/// LAYOUT v2 — THE MACROS TAB (macro-panel + macro-ab-authoring specs). The management surface for the 24 macros in
/// three banks (BTN | SLD | TML), eight controls at a time (the house density). Macros MODULATE their targets as an
/// offset; value 0 = home. This tab shows + DRIVES the values (+ the padlock: SPRING releases home, FIXED latches,
/// + rename); AUTHORING the bindings (the A/B popup) lands on the Edit page (M4). Unset slots read as INVITATIONS
/// (dim/dashed), not dead controls. The SLIDER bank is the one exposed as automatable AU params (M1–M8).
struct MacroPanel: View {
    let macros: [Macro]                       // the 24 (polled), index = macro slot
    let onSetValue: (Int, Double) -> Void     // routes via the AU param tree (host-automation-synced)
    let onSetFixed: (Int, Bool) -> Void       // the padlock
    let onSetName: (Int, String) -> Void      // rename (12 chars)

    @State private var bank: MacroKind = .slider
    @State private var renaming: Int? = nil
    @State private var draft = ""

    private let ink = Color.white
    private let cyan = UI.cyan
    private let amber = UI.amber

    private var range: Range<Int> {
        switch bank { case .slider: return 0..<8; case .button: return 8..<16; case .timeline: return 16..<24 }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Text("MACROS").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.7)).tracking(1.5)
                Spacer()
                bankSelector
            }
            Group {
                switch bank {
                case .slider:   sliderBank
                case .button:   buttonBank
                case .timeline: timelinePlaceholder
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Text(bankHint).font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.35))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: 760, maxHeight: .infinity, alignment: .top)
        .frame(maxWidth: .infinity, alignment: .center)
        .alert("Rename macro", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("name", text: $draft)
            Button("Save") { if let i = renaming { onSetName(i, draft) }; renaming = nil }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
    }

    // BTN | SLD | TML — the bank selector (the perform panel shows one at a time; this tab is the management view).
    private var bankSelector: some View {
        HStack(spacing: 0) {
            seg("BTN", .button); seg("SLD", .slider); seg("TML", .timeline)
        }
        .background(RoundedRectangle(cornerRadius: 7).fill(ink.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(0.1)))
    }
    private func seg(_ label: String, _ k: MacroKind) -> some View {
        let on = bank == k
        return Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1)
            .foregroundColor(on ? .black : ink.opacity(0.5))
            .padding(.horizontal, 12).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? cyan : Color.clear))
            .contentShape(Rectangle()).onTapGesture { bank = k }
    }

    private var bankHint: String {
        switch bank {
        case .slider:   return "SLIDERS morph A→B continuously (M1–M8, host-automatable). Drag to ride; the padlock at the foot toggles SPRING (release → home) or FIXED (latched). Bind targets from the MACRO button on a processor slot."
        case .button:   return "BUTTONS snap A|B. SPRING = momentary punch-in; FIXED = a latched rig-switch. Bind from the MACRO button on a processor slot."
        case .timeline: return "TIMELINES: the playhead drives the macro per column (an 8-step lane). The lane editor + per-column modes arrive with this bank."
        }
    }

    // MARK: banks

    private var sliderBank: some View {
        HStack(alignment: .bottom, spacing: 8) {
            ForEach(range, id: \.self) { i in
                MacroFader(index: i, macro: macros[safe: i] ?? Macro(),
                           accent: cyan, onSetValue: onSetValue, onToggleFixed: onSetFixed,
                           onTapName: { renaming = i; draft = macros[safe: i]?.name ?? "" })
            }
        }
    }

    private var buttonBank: some View {
        HStack(alignment: .top, spacing: 8) {
            ForEach(range, id: \.self) { i in
                MacroButton(index: i, macro: macros[safe: i] ?? Macro(),
                            accent: amber, onSetValue: onSetValue, onToggleFixed: onSetFixed,
                            onTapName: { renaming = i; draft = macros[safe: i]?.name ?? "" })
            }
        }
    }

    private var timelinePlaceholder: some View {
        VStack(spacing: 8) {
            Spacer()
            Text("TIMELINES").font(.system(size: 18, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.45))
            Text("the laned bank — coming").font(.system(size: 11, design: .monospaced)).foregroundColor(ink.opacity(0.3)).tracking(1)
            Spacer()
        }
    }
}

// MARK: - one SLIDER macro (vertical fader + name + padlock)

private struct MacroFader: View {
    let index: Int
    let macro: Macro
    let accent: Color
    let onSetValue: (Int, Double) -> Void
    let onToggleFixed: (Int, Bool) -> Void
    let onTapName: () -> Void

    @State private var v: Double = 0
    @GestureState private var dragging = false
    private let ink = Color.white
    private var unset: Bool { macro.name.isEmpty && macro.targets.isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            nameChip
            fader
            Text(String(format: "%.0f", v * 100)).font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(ink.opacity(v > 0 ? 0.7 : 0.3))
            padlock
        }
        .frame(maxWidth: .infinity)
        .opacity(unset && v == 0 ? 0.5 : 1)                 // chrome-quiet: unset + zero recede
        .onAppear { v = macro.value }
        .onChange(of: macro.value) { nv in if !dragging { v = nv } }   // reflect external (automation) moves when idle
    }

    private var nameChip: some View {
        Text(macro.name.isEmpty ? "M\(index + 1)" : macro.name)
            .font(.system(size: 9, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundColor(macro.name.isEmpty ? ink.opacity(0.35) : accent)
            .frame(maxWidth: .infinity).frame(height: 16)
            .background(RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.06)))
            .contentShape(Rectangle()).onTapGesture { onTapName() }
    }

    private var fader: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 5).fill(ink.opacity(unset ? 0.03 : 0.07))
                    .overlay(RoundedRectangle(cornerRadius: 5)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: unset ? [3, 3] : []))
                        .foregroundColor(ink.opacity(unset ? 0.18 : 0.10)))
                RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.85))
                    .frame(height: max(0, min(h, CGFloat(v) * h)))
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0)
                .updating($dragging) { _, s, _ in s = true }
                .onChanged { g2 in
                    let nv = max(0, min(1, 1 - Double(g2.location.y / h)))
                    v = nv; onSetValue(index, nv)
                }
                .onEnded { _ in
                    if !macro.fixed {                       // SPRING: release returns home
                        withAnimation(.easeOut(duration: 0.18)) { v = 0 }
                        onSetValue(index, 0)
                    }
                })
        }
        .frame(width: 40, height: 150)
    }

    private var padlock: some View {
        Image(systemName: macro.fixed ? "lock.fill" : "lock.open")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(macro.fixed ? accent : ink.opacity(0.4))
            .frame(width: 30, height: 22).contentShape(Rectangle())
            .onTapGesture { onToggleFixed(index, !macro.fixed) }
    }
}

// MARK: - one BUTTON macro (A|B snap: momentary if spring, toggle if fixed)

private struct MacroButton: View {
    let index: Int
    let macro: Macro
    let accent: Color
    let onSetValue: (Int, Double) -> Void
    let onToggleFixed: (Int, Bool) -> Void
    let onTapName: () -> Void

    @State private var on = false
    private let ink = Color.white
    private var unset: Bool { macro.name.isEmpty && macro.targets.isEmpty }

    var body: some View {
        VStack(spacing: 6) {
            Text(macro.name.isEmpty ? "B\(index - 7)" : macro.name)
                .font(.system(size: 9, weight: .heavy, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundColor(macro.name.isEmpty ? ink.opacity(0.35) : accent)
                .frame(maxWidth: .infinity).frame(height: 16)
                .background(RoundedRectangle(cornerRadius: 3).fill(ink.opacity(0.06)))
                .contentShape(Rectangle()).onTapGesture { onTapName() }
            pad
            Image(systemName: macro.fixed ? "lock.fill" : "lock.open")
                .font(.system(size: 12, weight: .semibold)).foregroundColor(macro.fixed ? accent : ink.opacity(0.4))
                .frame(width: 30, height: 22).contentShape(Rectangle())
                .onTapGesture { onToggleFixed(index, !macro.fixed) }
        }
        .frame(maxWidth: .infinity)
        .opacity(unset && !on ? 0.5 : 1)
        .onAppear { on = macro.value >= 0.5 }
        .onChange(of: macro.value) { on = $0 >= 0.5 }
    }

    // FIXED = TOGGLE (tap flips + latches) · SPRING = MOMENTARY (press = B, release = A).
    private var pad: some View {
        RoundedRectangle(cornerRadius: 6).fill(on ? accent.opacity(0.85) : ink.opacity(unset ? 0.03 : 0.08))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: unset ? [3, 3] : []))
                .foregroundColor(ink.opacity(unset ? 0.18 : 0.10)))
            .frame(width: 40, height: 100)
            .contentShape(Rectangle())
            .gesture(
                macro.fixed
                ? AnyGesture(TapGesture().onEnded { on.toggle(); onSetValue(index, on ? 1 : 0) }.map { _ in () })
                : AnyGesture(DragGesture(minimumDistance: 0)
                    .onChanged { _ in if !on { on = true; onSetValue(index, 1) } }
                    .onEnded { _ in on = false; onSetValue(index, 0) }.map { _ in () })
            )
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
