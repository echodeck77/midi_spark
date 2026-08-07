//  MacroAuthoringView.swift
//  THE MACRO AUTHORING pop-up (canonical, user 2026-08-07 rev 3). A DROPDOWN at the top ("add new macro…" plus
//  every macro already bound to this slot, its overridden controls in brackets); picking one REFLECTS it onto the
//  page. Select a processor's params → set each one's ALTERNATIVE value (its MAIN value is shown in text beside it)
//  → ONE big MAIN…WITH-MACRO slider (always present) auditions the whole selection live, sweeping multi-value
//  controls through their options. Below: the 8 macro SLIDERS + 8 macro BUTTONS — each still driveable even when
//  greyed. A macro's button reads "ADD TO M{n}" (dim until a selected control diverges from MAIN); pressing it
//  BINDS the selection's deltas and becomes "REMOVE FROM M{n}" (drops the binding, live in the MIDI out). A control
//  whose alternative equals its source stores nothing. APPLY/CANCEL top-right; only CANCEL reverts.

import SwiftUI

struct MacroAuthoringView: View {
    let group: MacroControlGroup
    let macros: [Macro]
    let existing: [MacroSlotBinding]                            // macros already bound to THIS slot (the dropdown + reflect)
    let accent: Color
    let base: [String: Double]                                  // the processor's current values (the offset base = MAIN)
    let onPreview: ([String: Double]) -> Void                   // audition: set the live slot to these values
    let onBind: (_ macroIndex: Int, _ deltas: [String: Double]) -> Void
    let onUnbind: (_ macroIndex: Int) -> Void                   // "REMOVE FROM M{n}" — drops this slot's binding
    let onSetMacro: (_ index: Int, _ value: Double) -> Void     // live macro drag inside the pop-up
    let onClose: (_ apply: Bool) -> Void
    var embedded: Bool = false                                  // EMBEDDED (in the processor edit pop-up): no header/scrim/frame;
    var onEngage: () -> Void = {}                               //   the controls gate behind an "Add macro" button / dropdown, and
                                                                //   the parent pop-up owns APPLY/CANCEL. onEngage fires when authoring begins.
    @State private var authoring = false                        // embedded: has the macro section been opened (Add macro / a pick)?

    @State private var selected: Set<String> = []               // params being authored for the current macro
    @State private var targets: [String: Double] = [:]          // the ALTERNATIVE value per param
    @State private var morph: Double = 1                         // the single MAIN…WITH-MACRO audition slider (0=MAIN, 1=alt)
    @State private var bound: [Int: [String]] = [:]             // macro index → param keys bound to it (session + existing)
    @State private var currentMacro: Int? = nil                 // the macro being authored/reflected (nil = a new one)
    @State private var macroVals: [Double] = Array(repeating: 0, count: 24)

    private let panel = Color.white.opacity(0.04)
    private let dim = Color.white.opacity(0.3)
    private let removeHue = Color(red: 0.95, green: 0.45, blue: 0.42)

    // MARK: derived

    private var alt: [String: Double] {                         // MAIN overlaid with the selected controls' alternatives
        var v = base
        for k in selected { v[k] = targets[k] ?? base[k] ?? 0 }
        return v
    }
    private var sparse: [String: Double] { macroSparseDelta(main: base, alt: alt, params: group.params) }   // §3 zero drops
    private var canAdd: Bool { !sparse.isEmpty }
    private func isBound(_ i: Int) -> Bool { !(bound[i] ?? []).isEmpty }
    private func lockMacro(_ key: String) -> Int? { bound.first { $0.key != currentMacro && $0.value.contains(key) }?.key }

    // MARK: body

    var body: some View {
        Group {
            if embedded { embeddedContent } else { standalone }
        }
        .onAppear {
            for m in 0..<min(24, macros.count) { macroVals[m] = macros[m].value }
            for b in existing { bound[b.macro] = Array(b.deltas.keys) }                  // reflect what's already set up
        }
    }

    // STANDALONE — the canonical modal (chain-stack MACRO button). Owns its scrim/header/APPLY/CANCEL.
    private var standalone: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onClose(true) }   // scrim-tap KEEPS the macros (only CANCEL reverts)
            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        macroPicker
                        paramSection
                        morphSection                                                     // ALWAYS present (§ user 2026-08-07)
                        macroPanels
                    }.padding(16)
                }
            }
            .frame(maxWidth: 580, maxHeight: 760)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.4), lineWidth: 1))
            .padding(20)
        }
    }

    // EMBEDDED — lives at the FOOT of the processor edit pop-up (user 2026-08-08). No header/scrim (the parent owns
    // APPLY/CANCEL). One adaptive gate: "+ ADD MACRO" (this slot has none) or the dropdown (it has some). Engaging it
    // reveals the authoring controls inline.
    private var embeddedContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if authoring || !existing.isEmpty { macroPicker } else { addMacroButton }
            if authoring {
                paramSection
                morphSection
                macroPanels
            }
        }
    }
    private var addMacroButton: some View {
        Button { authoring = true; onEngage(); newMacro() } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus.circle.fill").font(.system(size: 16, weight: .heavy))
                Text("ADD MACRO").font(.system(size: 13, weight: .heavy, design: .monospaced))
                Spacer(minLength: 0)
            }
            .foregroundColor(accent).padding(.horizontal, 14).frame(height: 44)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.12))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.4), lineWidth: 1)))
        }.buttonStyle(.plain)
    }

    // MARK: header — title + APPLY / CANCEL

    private var header: some View {
        HStack(spacing: 10) {
            Text("MACRO · \(group.title)").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(accent)
            Spacer()
            Button { onClose(false) } label: { chip("CANCEL", fill: false, hue: removeHue) }.buttonStyle(.plain)
            Button { onClose(true) } label: { chip("APPLY", fill: true, hue: accent) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
    private func chip(_ label: String, fill: Bool, hue: Color) -> some View {
        Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced))
            .foregroundColor(fill ? .black : hue).frame(minWidth: 64, minHeight: 32)
            .background(RoundedRectangle(cornerRadius: 6).fill(fill ? hue : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(hue.opacity(0.6), lineWidth: 1)))
    }

    // MARK: the macro picker (§1) — "add new macro…" + every macro on this slot (its overridden controls in brackets)

    private var macroPicker: some View {
        Menu {
            Button("add new macro…") { newMacro() }
            ForEach(existing, id: \.macro) { b in
                Button("M\(b.macro + 1)  (\(bindingLabel(b)))") { reflect(b) }
            }
        } label: {
            HStack(spacing: 8) {
                Text(currentMacro.map { "M\($0 + 1)" } ?? "add new macro…")
                    .font(.system(size: 13, weight: .heavy, design: .monospaced))
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy))
                Spacer(minLength: 0)
            }
            .foregroundColor(accent).padding(.horizontal, 12).frame(height: 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 7).fill(accent.opacity(0.12)))
        }
    }
    private func bindingLabel(_ b: MacroSlotBinding) -> String {
        b.deltas.keys.compactMap { k in group.params.first { $0.key == k }?.label }.sorted().joined(separator: ", ").lowercased()
    }

    // MARK: parameters — MAIN value in text + (when selected) the ALT control (enlarged to the main edit section, §2)

    private var paramSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("PARAMETERS").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8))
            ForEach(group.params, id: \.key) { p in paramRow(p) }
        }
        .padding(14).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(panel))
    }
    @ViewBuilder private func paramRow(_ p: MacroControlParam) -> some View {
        let isSel = selected.contains(p.key)
        let lockedTo = lockMacro(p.key)
        let locked = lockedTo != nil
        HStack(spacing: 12) {
            Button { if !locked { toggleParam(p.key) } } label: {
                Image(systemName: isSel ? "checkmark.square.fill" : "square")
                    .font(.system(size: 20)).foregroundColor(isSel ? accent : (locked ? dim : .white.opacity(0.55)))
            }.buttonStyle(.plain).disabled(locked)
            Text(p.label).font(.system(size: 13, weight: .heavy, design: .monospaced))
                .foregroundColor(locked ? dim : .white.opacity(0.8)).frame(width: 80, alignment: .leading)
            Text(mainText(p)).font(.system(size: 12, weight: .heavy, design: .monospaced))   // MAIN value in text (always, §2)
                .foregroundColor(locked ? dim : accent.opacity(0.7)).frame(width: 56, alignment: .leading)
            if let m = lockedTo {
                Text("→ M\(m + 1)").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(dim)
                Spacer(minLength: 0)
            } else if isSel {
                MacroControlEditor(param: p, accent: accent, value: Binding(
                    get: { targets[p.key] ?? base[p.key] ?? 0 },
                    set: { targets[p.key] = $0; preview() }))
            } else {
                Spacer(minLength: 0)
            }
        }
        .frame(minHeight: 40)
    }

    // MARK: the ONE big MAIN…WITH-MACRO audition slider (§ always present) — auditions the whole selection

    private var morphSection: some View {
        VStack(spacing: 10) {
            Slider(value: Binding(get: { morph }, set: { morph = $0; preview() }), in: 0...1).tint(accent)
                .scaleEffect(x: 1, y: 1.7, anchor: .center).padding(.vertical, 7)
                .disabled(sparse.isEmpty)
            HStack {
                Text("MAIN").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                Spacer()
                Text("WITH MACRO").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(accent)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 15).frame(maxWidth: .infinity)
        .opacity(sparse.isEmpty ? 0.5 : 1)
        .background(RoundedRectangle(cornerRadius: 8).fill(accent.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(accent.opacity(0.3), lineWidth: 1)))
    }

    // MARK: the macro panels — 8 sliders + 8 buttons, each with ADD/REMOVE (widgets stay driveable even when greyed, §6)

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
                        Group {
                            if isButton {
                                GridMacroButton(index: i, value: macroVals[i], fixed: i < macros.count ? macros[i].fixed : true) { idx, v in macroVals[idx] = v; onSetMacro(idx, v) }
                            } else {
                                GridMacroSlider(index: i, value: macroVals[i]) { idx, v in macroVals[idx] = v; onSetMacro(idx, v) }
                            }
                        }
                        .opacity(isBound(i) ? 1 : 0.4)                          // greyed until bound — but still driveable (§6)
                        addRemoveButton(i)
                    }.frame(maxWidth: .infinity)
                }
            }
        }
    }
    /// §3a/§3b: "ADD TO M{n}" (dim until a selected control diverges) ⇄ "REMOVE FROM M{n}" once bound.
    @ViewBuilder private func addRemoveButton(_ i: Int) -> some View {
        let isB = isBound(i)
        let enabled = isB || canAdd
        Button { isB ? unbind(i) : bind(to: i) } label: {
            Text(isB ? "REMOVE\nM\(i + 1)" : "ADD\nM\(i + 1)")
                .font(.system(size: 7, weight: .heavy, design: .monospaced)).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)
                .foregroundColor(enabled ? (isB ? removeHue : .black) : dim).frame(maxWidth: .infinity).frame(height: 26)
                .background(RoundedRectangle(cornerRadius: 3).fill(isB ? Color.clear : (enabled ? accent : Color.white.opacity(0.06)))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(isB ? removeHue.opacity(0.7) : Color.clear, lineWidth: 1)))
        }.buttonStyle(.plain).disabled(!enabled)
    }

    // MARK: logic

    private func preview() {
        onPreview(macroApply(main: base, delta: sparse, value: morph, params: group.params))
    }
    private func toggleParam(_ key: String) {
        if selected.contains(key) { selected.remove(key) }
        else { selected.insert(key); if targets[key] == nil { targets[key] = base[key] ?? 0 } }
        preview()
    }
    /// BIND the diverging selected controls to macro i (§3d dropped the zero-delta ones via `sparse`).
    private func bind(to i: Int) {
        guard canAdd else { return }
        let stored = sparse
        onBind(i, stored)
        var keys = bound[i] ?? []
        for k in stored.keys where !keys.contains(k) { keys.append(k) }
        bound[i] = keys
        currentMacro = nil; selected = []; morph = 1                    // round done; bound params grey out
        onPreview(base)                                                 // audio → MAIN
    }
    private func unbind(_ i: Int) {
        onUnbind(i)
        bound[i] = nil                                                  // its params return to available
        if currentMacro == i { currentMacro = nil; selected = [] }
        onPreview(base)
    }
    /// Dropdown: REFLECT an existing macro onto the page — its controls, values, and applied state (§1).
    private func reflect(_ b: MacroSlotBinding) {
        if !authoring { authoring = true; onEngage() }             // embedded: picking a macro reveals the controls + starts audition
        currentMacro = b.macro
        selected = Set(b.deltas.keys)
        for (k, d) in b.deltas { targets[k] = (base[k] ?? 0) + d }
        var keys = bound[b.macro] ?? []
        for k in b.deltas.keys where !keys.contains(k) { keys.append(k) }
        bound[b.macro] = keys
        morph = 1; preview()
    }
    private func newMacro() { if !authoring { authoring = true; onEngage() }; currentMacro = nil; selected = []; morph = 1; onPreview(base) }

    /// The MAIN value of a control, formatted for its kind (§2).
    private func mainText(_ p: MacroControlParam) -> String {
        let v = base[p.key] ?? 0
        switch p.kind {
        case .continuous:        return String(format: "%.2f", v)
        case .toggle:            return v >= 0.5 ? "ON" : "OFF"
        case .option(let labels):
            let i = clamp(Int(v.rounded()), 0, max(0, labels.count - 1))
            return labels.indices.contains(i) ? labels[i] : "—"
        case .stepper:           return "\(Int(v.rounded()))"
        case .mask(let bits):
            let m = Int(v.rounded())
            let on = (0..<bits).filter { (m >> $0) & 1 == 1 }.map { "\($0 + 1)" }
            return on.isEmpty ? "—" : on.joined(separator: ",")
        }
    }
}

/// A generic editor for ONE control — picks the widget from the descriptor kind (slider · toggle · segmented ·
/// stepper · bit-mask), reads/writes the value as a Double. Sized to match the main processor edit section (§2).
struct MacroControlEditor: View {
    let param: MacroControlParam
    let accent: Color
    @Binding var value: Double

    var body: some View {
        switch param.kind {
        case .continuous(let lo, let hi):
            HStack(spacing: 8) {
                Slider(value: $value, in: lo...hi).tint(accent)
                Text(String(format: "%.2f", value)).font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(width: 40)
            }
        case .toggle:
            let on = value >= 0.5
            Button { value = on ? 0 : 1 } label: {
                Text(on ? "ON" : "OFF").font(.system(size: 13, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6)).frame(width: 64, height: 36)
                    .background(RoundedRectangle(cornerRadius: 6).fill(on ? accent : Color.white.opacity(0.08)))
            }.buttonStyle(.plain)
            Spacer(minLength: 0)
        case .option(let labels):
            let idx = clamp(Int(value.rounded()), 0, max(0, labels.count - 1))
            Menu {
                ForEach(Array(labels.enumerated()), id: \.offset) { i, l in Button(l) { value = Double(i) } }
            } label: {
                HStack(spacing: 6) {
                    Text(labels.indices.contains(idx) ? labels[idx] : "—").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                    Image(systemName: "chevron.down").font(.system(size: 10, weight: .heavy)).foregroundColor(accent.opacity(0.7))
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).frame(height: 36)
                    .padding(.horizontal, 10).background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.10)))
            }
        case .stepper(let lo, let hi):
            HStack(spacing: 10) {
                stepBtn("minus") { value = Double(clamp(Int(value.rounded()) - 1, lo, hi)) }
                Text("\(Int(value.rounded()))").font(.system(size: 15, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.8)).frame(width: 36)
                stepBtn("plus") { value = Double(clamp(Int(value.rounded()) + 1, lo, hi)) }
                Spacer(minLength: 0)
            }
        case .mask(let bits):
            let m = Int(value.rounded())
            HStack(spacing: 6) {
                ForEach(0..<bits, id: \.self) { b in
                    let on = (m >> b) & 1 == 1
                    Button { value = Double(m ^ (1 << b)) } label: {
                        Text("\(b + 1)").font(.system(size: 12, weight: .heavy, design: .monospaced))
                            .foregroundColor(on ? .black : .white.opacity(0.5)).frame(width: 30, height: 30)
                            .background(RoundedRectangle(cornerRadius: 5).fill(on ? accent : Color.white.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func stepBtn(_ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) { Image(systemName: symbol).font(.system(size: 13, weight: .heavy)).foregroundColor(accent).frame(width: 34, height: 32).background(RoundedRectangle(cornerRadius: 6).fill(accent.opacity(0.12))) }.buttonStyle(.plain)
    }
}
