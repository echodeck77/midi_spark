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
    let amounts: (leak: [Int], duck: [Int], curve: [Int], pocket: [Int])   // OUTPUT group A-state (the current per-emitter role amounts)
    let onEditParam: (Int, MacroParam, Double) -> Void   // CHAIN: live-write B to all targets (slot, param, value)
    let onBind: (Int, [MacroTarget]) -> Void   // CHAIN: add the delta targets to macro `index`
    let onRemove: (Int) -> Void                // CHAIN: remove macro `index`'s binding on the anchor cell
    let onBindEmitter: (Int, [MacroEmitterTarget]) -> Void   // OUTPUT: bind per-emitter amount deltas
    let onRemoveEmitter: (Int) -> Void                       // OUTPUT: clear macro's OUTPUT bindings
    let onClose: () -> Void                    // restore A + dismiss

    enum EditGroup { case chain, output }
    @State private var group: EditGroup = .chain       // which [AB] group (INPUT deferred)
    @State private var aVals: [String: Double] = [:]   // CHAIN captured A per "slot.param"
    @State private var bVals: [String: Double] = [:]   // CHAIN demonstrated B (live)
    @State private var outA: [String: Double] = [:]    // OUTPUT captured A per "emitter.param"
    @State private var outB: [String: Double] = [:]    // OUTPUT demonstrated B (local — bound as a delta on close)
    @State private var toast: String? = nil
    @State private var bindBank: MacroKind = .slider   // which bank the binding list shows (SLD default; TML deferred)

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

    // The per-emitter OUTPUT amounts (label + native range, matching the builder's clamps).
    private let amountDefs: [(param: MacroEmitterParam, label: String, lo: Double, hi: Double)] =
        [(.leak, "LEAK", 0, 100), (.duck, "DUCK", 0, 100), (.curve, "CURVE", -100, 100), (.pocket, "POCKET", -50, 50)]
    private func okey(_ e: Int, _ p: MacroEmitterParam) -> String { "\(e).\(p.rawValue)" }
    private func amountA(_ e: Int, _ p: MacroEmitterParam) -> Double {
        let arr: [Int]
        switch p {
        case .leak:   arr = amounts.leak
        case .duck:   arr = amounts.duck
        case .curve:  arr = amounts.curve
        case .pocket: arr = amounts.pocket
        }
        return (e >= 0 && e < arr.count) ? Double(arr[e]) : 0
    }

    /// CHAIN: the touched params (B ≠ A) as targets, replicated across every selected cell.
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
    /// OUTPUT: the touched per-emitter amounts (B ≠ A) as emitter targets.
    private var deltaEmitterTargets: [MacroEmitterTarget] {
        var out: [MacroEmitterTarget] = []
        for e in 0..<4 {
            for d in amountDefs {
                let k = okey(e, d.param); let a = outA[k] ?? 0, b = outB[k] ?? a
                if abs(b - a) < 1e-6 { continue }
                out.append(MacroEmitterTarget(emitter: e, param: d.param.rawValue, delta: b - a))
            }
        }
        return out
    }
    private var anyTouched: Bool { group == .output ? !deltaEmitterTargets.isEmpty : !deltaTargets.isEmpty }

    var body: some View {
        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea().onTapGesture { onClose() }
            VStack(alignment: .leading, spacing: 0) {
                header
                groupSelector.padding(.bottom, 8)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        if group == .chain {
                            if chain.contains(where: { !$0.bypassed && !contParams($0.type).isEmpty }) {
                                bSection
                            } else {
                                Text("Add a processor with a continuous control (GATE · SPREAD · CHANCE · …) to author a CHAIN B.")
                                    .font(.system(size: 10, design: .monospaced)).foregroundColor(ink.opacity(0.4))
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            outputSection
                        }
                        Divider().overlay(ink.opacity(0.12))
                        bindSection
                    }.padding(.vertical, 6)
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
        for e in 0..<4 {
            for d in amountDefs { let v = amountA(e, d.param); outA[okey(e, d.param)] = v; outB[okey(e, d.param)] = v }
        }
    }

    private var groupSelector: some View {
        HStack(spacing: 0) { groupChip("CHAIN", .chain); groupChip("OUTPUT", .output) }
            .background(RoundedRectangle(cornerRadius: 7).fill(ink.opacity(0.06)))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(0.1)))
    }
    private func groupChip(_ label: String, _ g: EditGroup) -> some View {
        let on = group == g
        return Text(label).font(.system(size: 11, weight: .heavy, design: .monospaced)).tracking(1)
            .foregroundColor(on ? .black : ink.opacity(0.5))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? editHue : Color.clear))
            .contentShape(Rectangle()).onTapGesture { group = g }
    }

    // OUTPUT group — demonstrate a per-emitter role-amount change; the delta binds to a macro (local B, no live write).
    private var outputSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Set a per-emitter amount to define B; bind the change to a macro. LEAK/DUCK % · CURVE ±100 · POCKET ±ms.")
                .font(.system(size: 9, design: .monospaced)).foregroundColor(ink.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            ForEach(0..<4, id: \.self) { e in
                VStack(alignment: .leading, spacing: 5) {
                    Text("EMITTER \(["A", "B", "C", "D"][e])").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.45))
                    ForEach(amountDefs, id: \.param) { d in amountRow(e, d) }
                }
            }
        }
    }
    private func amountRow(_ e: Int, _ d: (param: MacroEmitterParam, label: String, lo: Double, hi: Double)) -> some View {
        let k = okey(e, d.param); let a = outA[k] ?? d.lo
        let touched = abs((outB[k] ?? a) - a) > 1e-6
        return HStack(spacing: 8) {
            Text(d.label).font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(touched ? cyan : ink.opacity(0.55)).frame(width: 58, alignment: .leading)
            Slider(value: Binding(get: { outB[k] ?? a }, set: { outB[k] = $0 }), in: d.lo...d.hi).tint(cyan)
            Text(String(format: "%+.0f", (outB[k] ?? a) - a)).font(.system(size: 9, weight: .heavy, design: .monospaced))
                .foregroundColor(touched ? cyan : ink.opacity(0.3)).frame(width: 44, alignment: .trailing)
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

    // The binding list — SLIDER or BUTTON macros (TIMELINES land with that bank). A continuous-only B (all this
    // popup authors) is eligible for any mover, so both banks accept it; a SLIDER morphs A→B, a BUTTON snaps A|B.
    private var bindSection: some View {
        let base = bindBank == .button ? 8 : 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text("BIND TO A MACRO").font(.system(size: 10, weight: .heavy, design: .monospaced)).foregroundColor(ink.opacity(0.55)).tracking(1)
                Spacer()
                bankChip("SLD", .slider); bankChip("BTN", .button)
            }
            ForEach(0..<8, id: \.self) { r in macroRow(base + r) }
        }
    }
    private func bankChip(_ label: String, _ k: MacroKind) -> some View {
        let on = bindBank == k
        return Text(label).font(.system(size: 10, weight: .heavy, design: .monospaced))
            .foregroundColor(on ? .black : ink.opacity(0.5))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(on ? cyan : ink.opacity(0.08)))
            .contentShape(Rectangle()).onTapGesture { bindBank = k }
    }
    private func macroLabel(_ i: Int, _ m: Macro) -> String {
        if !m.name.isEmpty { return m.name }
        return i < 8 ? "M\(i + 1)" : "B\(i - 7)"
    }
    private func macroRow(_ i: Int) -> some View {
        let m = i < macros.count ? macros[i] : Macro()
        let boundHere = group == .output ? !m.emitterTargets.isEmpty
                                         : m.targets.contains { $0.col == anchor.col && $0.row == anchor.row }
        return HStack(spacing: 8) {
            Text(macroLabel(i, m)).font(.system(size: 11, weight: .heavy, design: .monospaced))
                .foregroundColor(m.name.isEmpty ? ink.opacity(0.4) : cyan).frame(width: 64, alignment: .leading).lineLimit(1)
            if boundHere {
                Text(group == .output ? "OUTPUT ✕" : "THIS CELL ✕").font(.system(size: 9, weight: .heavy, design: .monospaced)).foregroundColor(.black)
                    .padding(.horizontal, 6).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 3).fill(cyan))
                    .contentShape(Rectangle()).onTapGesture {
                        if group == .output { onRemoveEmitter(i) } else { onRemove(i) }
                        toast = "removed from \(macroLabel(i, m))"
                    }
            }
            Spacer()
            Text("BIND").font(.system(size: 10, weight: .heavy, design: .monospaced))
                .foregroundColor(anyTouched ? .black : ink.opacity(0.25))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(RoundedRectangle(cornerRadius: 4).fill(anyTouched ? cyan : ink.opacity(0.05)))
                .contentShape(Rectangle())
                .onTapGesture {
                    guard anyTouched else { return }
                    if group == .output { onBindEmitter(i, deltaEmitterTargets) } else { onBind(i, deltaTargets) }
                    toast = "bound → \(macroLabel(i, m))"
                }
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
