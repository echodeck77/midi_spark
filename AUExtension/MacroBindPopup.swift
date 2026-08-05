import SwiftUI

/// MACRO A/B AUTHORING (macro-ab-authoring spec) — the [AB] popup on the Edit page's CHAIN section. Authoring by
/// DEMONSTRATION: the chain's continuous controls are re-rendered LIVE (heard at full as you tweak — they write the
/// cell); the delta (B − A per TOUCHED param) is bound to a macro row. On close the base returns to A, so the macro
/// holds B as an OFFSET (bases untouched → seals stable). v1 scope: the CHAIN group + the SLIDER bank (continuous →
/// always eligible). INPUT/OUTPUT groups + BUTTON/TIMELINE movers + the A↔B morph-audition slider are deferred.
struct MacroBindPopup: View {
    let chain: [ProcessorSlot]                 // the anchor cell's materialised chain (the A state, captured on open)
    let anchor: (col: Int, row: Int)           // the selection anchor (for the existing-binding chips)
    let selected: [(col: Int, row: Int)]       // all targets (twins) — each gets its own target tag
    let macros: [Macro]                        // the 24 (polled) — the SLIDER bank (0…7) binds here
    let onEditParam: (Int, MacroParam, Double) -> Void   // live-write B to all targets (slot, param, value)
    let onBind: (Int, [MacroTarget]) -> Void   // add the delta targets to macro `index`
    let onRemove: (Int) -> Void                // remove macro `index`'s binding on the anchor cell
    let onClose: () -> Void                    // restore A + dismiss

    @State private var aVals: [String: Double] = [:]   // captured A per "slot.param"
    @State private var bVals: [String: Double] = [:]   // the demonstrated B (live)
    @State private var toast: String? = nil

    private let ink = Color.white
    private let cyan = Color(red: 0.15, green: 0.88, blue: 0.94)
    private let editHue = Color(red: 0.95, green: 0.47, blue: 0.85)

    // The continuous params each slot type exposes (label + native range, matching resolve()'s clamps).
    private func contParams(_ t: ProcessorType) -> [(param: MacroParam, label: String, lo: Double, hi: Double)] {
        switch t {
        case .arp:       return [(.gate, "GATE", 0.05, 1)]
        case .passgate:  return [(.ramp, "RAMP", 0, 1)]
        case .strum:     return [(.spread, "SPREAD", 0, 1), (.curve, "CURVE", -1, 1), (.velTilt, "TILT", -1, 1)]
        case .chance:    return [(.probability, "CHANCE", 0, 1)]
        case .harmonize: return [(.harmVelScale, "H-VEL", 0.1, 1)]
        case .ratchet:   return []   // count is stepped — not a continuous macro target
        }
    }
    private func key(_ slot: Int, _ p: MacroParam) -> String { "\(slot).\(p.rawValue)" }

    /// The touched params (B ≠ A) as targets, replicated across every selected cell.
    private var deltaTargets: [MacroTarget] {
        var out: [MacroTarget] = []
        for (i, slot) in chain.enumerated() where !slot.bypassed {
            for cp in contParams(slot.type) {
                let k = key(i, cp.param)
                let a = aVals[k] ?? 0, b = bVals[k] ?? a
                let d = b - a
                if abs(d) < 1e-6 { continue }
                for c in selected { out.append(MacroTarget(col: c.col, row: c.row, slot: i, param: cp.param.rawValue, delta: d)) }
            }
        }
        return out
    }
    private var anyTouched: Bool { !deltaTargets.isEmpty }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                header
                if chain.contains(where: { !$0.bypassed && !contParams($0.type).isEmpty }) {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 14) {
                            bSection
                            Divider().overlay(ink.opacity(0.12))
                            bindSection
                        }.padding(.vertical, 6)
                    }
                } else {
                    Spacer()
                    Text("Add a processor with a continuous control (GATE · SPREAD · CHANCE · …) to author a B state.")
                        .font(.system(size: 11, design: .monospaced)).foregroundColor(ink.opacity(0.4))
                        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding()
                    Spacer()
                }
            }
            .padding(20)
            .frame(maxWidth: 560, maxHeight: 640)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.10, green: 0.11, blue: 0.13)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(ink.opacity(0.1)))
            .padding(20)
            if let t = toast { toastView(t) }
        }
        .onAppear(perform: capture)
    }

    private func capture() {
        for (i, slot) in chain.enumerated() {
            for cp in contParams(slot.type) {
                let v = slot.params.macroValue(cp.param)
                aVals[key(i, cp.param)] = v; bVals[key(i, cp.param)] = v
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text("BIND A→B").font(.system(size: 13, weight: .heavy, design: .monospaced)).foregroundColor(editHue)
                Spacer()
                Text("DONE").font(.system(size: 12, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.7))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(RoundedRectangle(cornerRadius: 5).fill(ink.opacity(0.08)))
                    .contentShape(Rectangle()).onTapGesture { onClose() }
            }
            Text("Tweak the chain to define B (heard live). Tap a macro to bind the change; the base returns to A on DONE.")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
        }.padding(.bottom, 10)
    }

    // The B editor — live sliders for each slot's continuous params (touched ⇒ they carry a delta).
    private var bSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(chain.enumerated()), id: \.offset) { (i, slot) in
                let params = contParams(slot.type)
                if !slot.bypassed && !params.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("SLOT \(i + 1) · \(slot.type.rawValue)").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.45))
                        ForEach(params, id: \.param) { cp in paramRow(slot: i, cp) }
                    }
                }
            }
        }
    }
    private func paramRow(slot: Int, _ cp: (param: MacroParam, label: String, lo: Double, hi: Double)) -> some View {
        let k = key(slot, cp.param)
        let a = aVals[k] ?? cp.lo
        let touched = abs((bVals[k] ?? a) - a) > 1e-6
        return HStack(spacing: 8) {
            Text(cp.label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(touched ? cyan : ink.opacity(0.55)).frame(width: 58, alignment: .leading)
            Slider(value: Binding(get: { bVals[k] ?? a }, set: { nv in bVals[k] = nv; onEditParam(slot, cp.param, nv) }), in: cp.lo...cp.hi).tint(cyan)
            Text(String(format: "%+.2f", (bVals[k] ?? a) - a)).font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(touched ? cyan : ink.opacity(0.3)).frame(width: 44, alignment: .trailing)
        }
    }

    // The binding list — the 8 SLIDER macros. Tap a row = bind the current delta; tap the CELL chip = remove it here.
    private var bindSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("BIND TO A MACRO SLIDER").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.55)).tracking(1)
            ForEach(0..<8, id: \.self) { i in macroRow(i) }
        }
    }
    private func macroRow(_ i: Int) -> some View {
        let m = i < macros.count ? macros[i] : Macro()
        let boundHere = m.targets.contains { $0.col == anchor.col && $0.row == anchor.row }
        return HStack(spacing: 8) {
            Text(m.name.isEmpty ? "M\(i + 1)" : m.name).font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(m.name.isEmpty ? ink.opacity(0.4) : cyan).frame(width: 64, alignment: .leading).lineLimit(1)
            if boundHere {
                Text("THIS CELL ✕").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(cyan))
                    .contentShape(Rectangle()).onTapGesture { onRemove(i); toast = "removed from \(m.name.isEmpty ? "M\(i+1)" : m.name)" }
            }
            Spacer()
            Text("BIND").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(anyTouched ? .black : ink.opacity(0.25))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 4).fill(anyTouched ? cyan : ink.opacity(0.05)))
                .contentShape(Rectangle())
                .onTapGesture { guard anyTouched else { return }; onBind(i, deltaTargets); toast = "bound → \(m.name.isEmpty ? "M\(i+1)" : m.name)" }
        }
        .padding(.vertical, 3)
    }

    private func toastView(_ t: String) -> some View {
        Text(t).font(.system(size: 11, weight: .heavy, design: .monospaced)).foregroundColor(.black)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(Capsule().fill(cyan))
            .transition(.opacity).onAppear {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.1) { withAnimation { if toast == t { toast = nil } } }
            }
    }
}

extension ColourParams {
    /// Read a continuous param as a Double (macro-authoring), defaulting to the SnapParams default when unset.
    func macroValue(_ mp: MacroParam) -> Double {
        switch mp {
        case .gate:         return gate ?? 0.6
        case .ramp:         return ramp ?? 0.5
        case .spread:       return spread ?? 0.1
        case .curve:        return curve ?? 0
        case .velTilt:      return velTilt ?? 0
        case .probability:  return probability ?? 1
        case .harmVelScale: return harmVelScale ?? 0.8
        }
    }
    /// Write a continuous param (macro-authoring live B write).
    mutating func setMacroValue(_ mp: MacroParam, _ v: Double) {
        switch mp {
        case .gate:         gate = v
        case .ramp:         ramp = v
        case .spread:       spread = v
        case .curve:        curve = v
        case .velTilt:      velTilt = v
        case .probability:  probability = v
        case .harmVelScale: harmVelScale = v
        }
    }
}
