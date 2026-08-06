//  MacroAuthoringView.swift
//  THE MACRO AUTHORING FLOW — the UI (spec AcceptanceCriteria-macro-authoring.md). Generic over any CONTROL GROUP
//  (processor · receiver · emitter · rack): two full instances of the group's controls (MAIN above, ALTERNATIVE
//  below), a TEST slider (continuous morph) + TEST button (snap) to audition the mover feel live, then ADD TO MACRO
//  → the assignment view. APPLY / CANCEL. MAIN is REAL (its edits become the group's settings); everything rides
//  the host transaction (nothing escapes CANCEL). Renders from the data-only descriptor (MacroAuthoring.swift).

import SwiftUI

struct MacroAuthoringView: View {
    let group: MacroControlGroup
    let macros: [Macro]                                  // the 24 macro slots (for the assignment view)
    let accent: Color
    var initialMain: [String: Double]
    var initialAlt: [String: Double]
    let onWriteMain: ([String: Double]) -> Void           // MAIN is REAL — persist its edits to the live group
    let onPreview: ([String: Double]?) -> Void            // TEST: live-audition a value dict (nil = restore MAIN)
    let onPersistAlt: ([String: Double]) -> Void          // §7 persist the ALTERNATIVE set on the group
    let onAssign: (_ macroIndex: Int, _ delta: [String: Double]) -> Void
    let onClose: (_ apply: Bool) -> Void

    @State private var main: [String: Double] = [:]
    @State private var alt: [String: Double] = [:]
    @State private var testValue: Double = 0
    @State private var testSnappedAlt = false
    @State private var showAssign = false

    private var delta: [String: Double] { macroSparseDelta(main: main, alt: alt, params: group.params) }
    private var hasDiscrete: Bool { macroDeltaHasDiscrete(delta, params: group.params) }
    private let panel = Color.white.opacity(0.04)

    var body: some View {
        ZStack {
            Color.black.opacity(0.55).ignoresSafeArea().onTapGesture { onClose(false) }
            VStack(spacing: 0) {
                header
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        section("MAIN", subtitle: "the group's real settings") { editors(bindingToMain: true) }
                        section("ALTERNATIVE", subtitle: "where the macro moves it to") { editors(bindingToMain: false) }
                        testRow
                        addToMacroButton
                    }
                    .padding(16)
                }
                footer
            }
            .frame(maxWidth: 460, maxHeight: 640)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(accent.opacity(0.4), lineWidth: 1))
            .padding(20)
            if showAssign {
                MacroAssignmentView(macros: macros, delta: delta, hasDiscrete: hasDiscrete, accent: accent,
                                    onAssign: { i in onAssign(i, delta); showAssign = false },
                                    onClose: { showAssign = false })
            }
        }
        .onAppear { main = initialMain; alt = initialAlt.isEmpty ? initialMain : initialAlt }
    }

    private var header: some View {
        HStack {
            Text("MACRO").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(accent)
            Text(group.title).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 6)
    }

    private func section<V: View>(_ title: String, subtitle: String, @ViewBuilder _ body: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(title).font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.85))
                Text(subtitle).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.35))
            }
            body()
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(panel))
    }

    @ViewBuilder private func editors(bindingToMain: Bool) -> some View {
        VStack(spacing: 8) {
            ForEach(group.params, id: \.key) { p in
                MacroControlEditor(param: p, accent: accent, value: Binding(
                    get: { (bindingToMain ? main : alt)[p.key] ?? 0 },
                    set: { nv in
                        if bindingToMain { main[p.key] = nv; onWriteMain(main) }
                        else { alt[p.key] = nv; onPersistAlt(alt) }
                    }))
            }
        }
    }

    // TEST — a continuous slider (morph MAIN↔ALT) + a snap button; both audition via onPreview.
    private var testRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("TEST — audition the mover").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            HStack(spacing: 12) {
                Slider(value: Binding(get: { testValue }, set: { testValue = $0; onPreview(macroApply(main: main, delta: delta, value: $0, params: group.params)) }),
                       in: 0...1, onEditingChanged: { editing in if !editing { testValue = 0; onPreview(nil) } })
                    .tint(accent)
                Button {
                    testSnappedAlt.toggle()
                    onPreview(testSnappedAlt ? macroApply(main: main, delta: delta, value: 1, params: group.params) : nil)
                } label: {
                    Text(testSnappedAlt ? "ALT" : "MAIN").font(.system(size: 10, weight: .heavy, design: .monospaced))
                        .foregroundColor(testSnappedAlt ? .black : accent).frame(width: 54, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(testSnappedAlt ? accent : accent.opacity(0.12)))
                }.buttonStyle(.plain)
            }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(panel))
    }

    private var addToMacroButton: some View {
        Button { showAssign = true } label: {
            Text(delta.isEmpty ? "MOVE A CONTROL IN ALTERNATIVE FIRST" : "ADD TO MACRO →")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(delta.isEmpty ? .white.opacity(0.3) : .black)
                .frame(maxWidth: .infinity).frame(height: 40)
                .background(RoundedRectangle(cornerRadius: 8).fill(delta.isEmpty ? Color.white.opacity(0.06) : accent))
        }.buttonStyle(.plain).disabled(delta.isEmpty)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button { onPreview(nil); onClose(false) } label: { footChip("CANCEL", fill: false) }.buttonStyle(.plain)
            Button { onPreview(nil); onClose(true) } label: { footChip("APPLY", fill: true) }.buttonStyle(.plain)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
    }
    private func footChip(_ label: String, fill: Bool) -> some View {
        let hue: Color = label == "CANCEL" ? Color(red: 0.95, green: 0.35, blue: 0.38) : accent
        return Text(label).font(.system(size: 12, weight: .heavy, design: .monospaced))
            .foregroundColor(fill ? .black : hue).frame(maxWidth: .infinity).frame(height: 38)
            .background(RoundedRectangle(cornerRadius: 7).fill(fill ? hue : Color.clear)
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(hue.opacity(0.6), lineWidth: 1)))
    }
}

/// A generic editor for ONE control — picks the widget from the descriptor kind (slider · toggle · segmented ·
/// stepper · bit-mask), reads/writes the value as a Double so MAIN and ALT share one representation.
struct MacroControlEditor: View {
    let param: MacroControlParam
    let accent: Color
    @Binding var value: Double

    var body: some View {
        HStack(spacing: 10) {
            Text(param.label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(.white.opacity(0.6)).frame(width: 78, alignment: .leading)
            widget
        }
    }

    @ViewBuilder private var widget: some View {
        switch param.kind {
        case .continuous(let lo, let hi):
            HStack(spacing: 8) {
                Slider(value: $value, in: lo...hi).tint(accent)
                Text(String(format: "%.2f", value)).font(.system(size: 9, design: .monospaced)).foregroundColor(.white.opacity(0.5)).frame(width: 34)
            }
        case .toggle:
            let on = value >= 0.5
            Button { value = on ? 0 : 1 } label: {
                Text(on ? "ON" : "OFF").font(.system(size: 10, weight: .heavy, design: .monospaced))
                    .foregroundColor(on ? .black : .white.opacity(0.6)).frame(width: 54, height: 26)
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
                Text("\(Int(value.rounded()))").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.75)).frame(width: 34)
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
                            .foregroundColor(on ? .black : .white.opacity(0.5)).frame(width: 24, height: 24)
                            .background(RoundedRectangle(cornerRadius: 4).fill(on ? accent : Color.white.opacity(0.08)))
                    }.buttonStyle(.plain)
                }
                Spacer(minLength: 0)
            }
        }
    }
    private func stepBtn(_ symbol: String, _ tap: @escaping () -> Void) -> some View {
        Button(action: tap) { Image(systemName: symbol).font(.system(size: 10, weight: .heavy)).foregroundColor(accent).frame(width: 26, height: 24).background(RoundedRectangle(cornerRadius: 5).fill(accent.opacity(0.12))) }.buttonStyle(.plain)
    }
}

/// THE ASSIGNMENT VIEW — 8 sliders + 8 buttons, each with ASSIGN · the mover attribute · an IN-USE indicator.
/// A delta with any DISCRETE change is BUTTON-only (§5) — the slider rows dim. First assignment sets spring
/// (sliders) / toggle (buttons); thereafter FIXED here (shown read-only — edit on the Macro Main tab).
struct MacroAssignmentView: View {
    let macros: [Macro]
    let delta: [String: Double]
    let hasDiscrete: Bool
    let accent: Color
    let onAssign: (Int) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6).ignoresSafeArea().onTapGesture { onClose() }
            VStack(spacing: 10) {
                Text("ADD TO MACRO").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(accent)
                if hasDiscrete {
                    Text("this delta changes a discrete control → BUTTONS only").font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundColor(.white.opacity(0.4))
                }
                HStack(alignment: .top, spacing: 14) {
                    bank(title: "SLIDERS", range: 0..<8, eligible: !hasDiscrete)
                    bank(title: "BUTTONS", range: 8..<16, eligible: true)
                }
                Button { onClose() } label: {
                    Text("CANCEL").font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity).frame(height: 34).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.08)))
                }.buttonStyle(.plain)
            }
            .padding(16).frame(maxWidth: 420, maxHeight: 560)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.12, green: 0.13, blue: 0.15)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(accent.opacity(0.4), lineWidth: 1))
            .padding(24)
        }
    }

    private func bank(title: String, range: Range<Int>, eligible: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.5))
            ForEach(range, id: \.self) { i in assignRow(i, eligible: eligible) }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    private func assignRow(_ i: Int, eligible: Bool) -> some View {
        let m = i < macros.count ? macros[i] : nil
        let inUse = !(m?.targets.isEmpty ?? true) || !(m?.emitterTargets.isEmpty ?? true)
        let name = (m?.name.isEmpty == false) ? m!.name : (i < 8 ? "S\(i + 1)" : "B\(i - 7)")
        return HStack(spacing: 6) {
            Text(name).font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.white.opacity(0.7)).frame(width: 40, alignment: .leading)
            if inUse { Image(systemName: "link").font(.system(size: 8)).foregroundColor(accent.opacity(0.8)) }
            Spacer(minLength: 0)
            Button { if eligible { onAssign(i) } } label: {
                Text("ASSIGN").font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundColor(eligible ? .black : .white.opacity(0.25)).frame(width: 56, height: 22)
                    .background(RoundedRectangle(cornerRadius: 4).fill(eligible ? accent : Color.white.opacity(0.06)))
            }.buttonStyle(.plain).disabled(!eligible)
        }
        .opacity(eligible ? 1 : 0.4)
    }
}
