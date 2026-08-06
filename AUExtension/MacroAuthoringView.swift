//  MacroAuthoringView.swift
//  THE MACRO AUTHORING pop-up (canonical, user 2026-08-07). Select a processor's params → each shows a CONTROL
//  (sets the target) + a vertical TEST slider (auditions base→target live). Below: the 8 macro SLIDERS + 8 macro
//  BUTTONS, each with an APPLY that BINDS the current selection to that macro (multiple params per macro). A macro
//  dropdown + "add another macro" walk multiple bindings (params bound to a previous macro grey out). APPLY/CANCEL
//  top-right; CANCEL reverts every macro change since opening. The offset engine underneath is unchanged.

import SwiftUI

struct MacroAuthoringView: View {
    let group: MacroControlGroup
    let macros: [Macro]
    let accent: Color
    let base: [String: Double]                                  // the processor's current values (the offset base)
    let onPreview: ([String: Double]) -> Void                   // audition: set the live slot to these values
    let onBind: (_ macroIndex: Int, _ deltas: [String: Double]) -> Void
    let onSetMacro: (_ index: Int, _ value: Double) -> Void     // live macro drag inside the pop-up
    let onClose: (_ apply: Bool) -> Void

    @State private var selected: Set<String> = []               // params selected THIS round
    @State private var targets: [String: Double] = [:]          // the control value (target) per param
    @State private var test: [String: Double] = [:]             // per-param test slider (0…1), default 1 (alternative)
    @State private var boundParams: [String: Int] = [:]         // param key → the macro it was bound to (grey-out)
    @State private var boundMacros: [Int] = []                  // macros given a binding this session (the dropdown)
    @State private var macroVals: [Double] = Array(repeating: 0, count: 24)

    private let panel = Color.white.opacity(0.04)
    private let dim = Color.white.opacity(0.3)

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onClose(false) }
            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        paramSection
                        macroPanels
                        if !boundParams.isEmpty {
                            Button { startNewMacro() } label: {
                                Text("+ ADD ANOTHER MACRO").font(.system(size: 11, weight: .heavy, design: .monospaced))
                                    .foregroundColor(accent).frame(maxWidth: .infinity).frame(height: 34)
                                    .background(RoundedRectangle(cornerRadius: 7).fill(accent.opacity(0.14)))
                            }.buttonStyle(.plain)
                        }
                    }.padding(16)
                }
            }
            .frame(maxWidth: 540, maxHeight: 700)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.4), lineWidth: 1))
            .padding(20)
        }
        .onAppear { for m in 0..<min(24, macros.count) { macroVals[m] = macros[m].value } }
    }

    // MARK: header — the macro dropdown + APPLY / CANCEL

    private var header: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(Array(boundMacros.enumerated()), id: \.element) { i, _ in Text("Macro \(i + 1)") }
                Button("Add new macro") { startNewMacro() }
            } label: {
                HStack(spacing: 4) {
                    Text(boundMacros.isEmpty ? "Add new macro" : "Macro \(boundMacros.count) · + new")
                        .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy))
                }
                .foregroundColor(accent).padding(.horizontal, 10).frame(height: 28)
                .background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.12)))
            }
            Spacer()
            Button { onClose(false) } label: { chip("CANCEL", fill: false, hue: Color(red: 0.95, green: 0.35, blue: 0.38)) }.buttonStyle(.plain)
            Button { onClose(true) } label: { chip("APPLY", fill: true, hue: accent) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
    private func chip(_ label: String, fill: Bool, hue: Color) -> some View {
        Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced))
            .foregroundColor(fill ? .black : hue).frame(minWidth: 60, minHeight: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill ? hue : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(hue.opacity(0.6), lineWidth: 1)))
    }

    // MARK: parameters — select → control + test slider

    private var paramSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PARAMETERS").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            ForEach(group.params, id: \.key) { p in paramRow(p) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(panel))
    }
    @ViewBuilder private func paramRow(_ p: MacroControlParam) -> some View {
        let isSel = selected.contains(p.key)
        let lockedElsewhere = boundParams[p.key] != nil && !isSel      // bound to a previous macro → greyed
        HStack(spacing: 10) {
            Button { if !lockedElsewhere { toggleParam(p.key) } } label: {
                Image(systemName: isSel ? "checkmark.square.fill" : "square")
                    .font(.system(size: 15)).foregroundColor(isSel ? accent : (lockedElsewhere ? dim : .white.opacity(0.55)))
            }.buttonStyle(.plain).disabled(lockedElsewhere)
            Text(p.label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(lockedElsewhere ? dim : .white.opacity(0.7)).frame(width: 70, alignment: .leading)
            if isSel {
                MacroControlEditor(param: p, accent: accent, value: Binding(
                    get: { targets[p.key] ?? base[p.key] ?? 0 },
                    set: { targets[p.key] = $0; preview() }))
                VTestSlider(value: Binding(get: { test[p.key] ?? 1 }, set: { test[p.key] = $0; preview() }), accent: accent)
            } else if lockedElsewhere {
                Text("→ Macro \((boundMacros.firstIndex(of: boundParams[p.key]!) ?? 0) + 1)")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced)).foregroundColor(dim)
                Spacer(minLength: 0)
            } else {
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: the macro panels — 8 sliders + 8 buttons, each with APPLY

    private var macroPanels: some View {
        VStack(alignment: .leading, spacing: 10) {
            macroBank("SLIDERS", 0..<8, isButton: false)
            macroBank("BUTTONS", 8..<16, isButton: true)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(panel))
    }
    private func macroBank(_ title: String, _ range: Range<Int>, isButton: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 6) {
                ForEach(range, id: \.self) { i in
                    VStack(spacing: 4) {
                        if isButton {
                            GridMacroButton(index: i, value: macroVals[i], fixed: i < macros.count ? macros[i].fixed : true) { idx, v in macroVals[idx] = v; onSetMacro(idx, v) }
                        } else {
                            GridMacroSlider(index: i, value: macroVals[i]) { idx, v in macroVals[idx] = v; onSetMacro(idx, v) }
                        }
                        Button { bind(to: i) } label: {
                            Text("APPLY").font(.system(size: 7, weight: .heavy, design: .monospaced))
                                .foregroundColor(selected.isEmpty ? dim : .black).frame(maxWidth: .infinity).frame(height: 16)
                                .background(RoundedRectangle(cornerRadius: 3).fill(selected.isEmpty ? Color.white.opacity(0.06) : accent))
                        }.buttonStyle(.plain).disabled(selected.isEmpty)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: logic

    private var deltas: [String: Double] {
        var d: [String: Double] = [:]
        for k in selected { d[k] = (targets[k] ?? base[k] ?? 0) - (base[k] ?? 0) }
        return d
    }
    private func preview() {
        var v = base
        for k in selected {
            guard let p = group.params.first(where: { $0.key == k }) else { continue }
            let target = targets[k] ?? base[k] ?? 0, t = test[k] ?? 1, b = base[k] ?? 0
            if case .continuous(let lo, let hi) = p.kind { v[k] = min(hi, max(lo, b + t * (target - b))) }
            else { v[k] = t >= 0.5 ? target : b }
        }
        onPreview(v)
    }
    private func toggleParam(_ key: String) {
        if selected.contains(key) { selected.remove(key) }
        else { selected.insert(key); if targets[key] == nil { targets[key] = base[key] ?? 0 }; if test[key] == nil { test[key] = 1 } }
        preview()
    }
    private func bind(to macroIndex: Int) {
        guard !selected.isEmpty else { return }
        onBind(macroIndex, deltas)
        for k in selected { boundParams[k] = macroIndex }
        if !boundMacros.contains(macroIndex) { boundMacros.append(macroIndex) }
    }
    private func startNewMacro() { selected = []; onPreview(base) }   // clear the round; bound params grey out; audio → base
}

/// A generic editor for ONE control — picks the widget from the descriptor kind (slider · toggle · segmented ·
/// stepper · bit-mask), reads/writes the value as a Double so the control + the audition share one representation.
struct MacroControlEditor: View {
    let param: MacroControlParam
    let accent: Color
    @Binding var value: Double

    var body: some View {
        switch param.kind {
        case .continuous(let lo, let hi):
            HStack(spacing: 6) {
                Slider(value: $value, in: lo...hi).tint(accent)
                Text(String(format: "%.2f", value)).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(width: 32)
            }
        case .toggle:
            let on = value >= 0.5
            Button { value = on ? 0 : 1 } label: {
                Text(on ? "ON" : "OFF").font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6)).frame(width: 50, height: 26)
                    .background(RoundedRectangle(cornerRadius: 5).fill(on ? accent : Color.white.opacity(0.08)))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
        case .option(let labels):
            let idx = clamp(Int(value.rounded()), 0, max(0, labels.count - 1))
            Menu {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, l in Button(l) { value = Double(i) } }
            } label: {
                HStack(spacing: 4) {
                    Text(labels.indices.contains(idx) ? labels[idx] : "—").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .heavy)).foregroundColor(accent.opacity(0.7))
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        case .stepper(let lo, let hi):
            HStack(spacing: 8) {
                stepBtn("minus") { value = Double(clamp(Int(value.rounded()) - 1, lo, hi)) }
                Text("\(Int(value.rounded()))").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75)).frame(width: 30)
                stepBtn("plus") { value = Double(clamp(Int(value.rounded()) + 1, lo, hi)) }
                Spacer(minLength: 0)
            }
        case .mask(let bits):
            let m = Int(value.rounded())
            HStack(spacing: 4) {
                ForEach(0..<bits, id: \.self) { b in
                    let on = (m >> b) & 1 == 1
                    Button { value = Double(m ^ (1 << b)) } label: {
                        Text("\(b + 1)").font(.system(size: 9, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.5)).frame(width: 22, height: 22)
                            .background(RoundedRectangle(cornerRadius: 4).fill(on ? accent : Color.white.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func stepBtn(_ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) { Image(systemName: symbol).font(.system(size: 10, weight: .heavy)).foregroundColor(accent).frame(width: 24, height: 22).background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.12))) }.buttonStyle(.plain)
    }
}

/// A compact VERTICAL test slider (0…1) — auditions the param's base→target morph, defaulting to 1 (the target).
struct VTestSlider: View {
    @Binding var value: Double
    let accent: Color
    var body: some View {
        GeometryReader { g in
            let h = g.size.height
            ZStack(alignment: .bottom) {
                Capsule().fill(Color.white.opacity(0.10)).frame(width: 5)
                Capsule().fill(accent.opacity(0.9)).frame(width: 5, height: max(3, h * CGFloat(value)))
                RoundedRectangle(cornerRadius: 2).fill(accent).frame(width: 16, height: 4).offset(y: -(h - 4) * CGFloat(value))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity).contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { gg in value = max(0, min(1, 1 - Double(gg.location.y / max(1, h)))) })
        }
        .frame(width: 26, height: 40)
    }
}
