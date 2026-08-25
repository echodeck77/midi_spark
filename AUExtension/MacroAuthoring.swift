//  MacroAuthoring.swift
//  THE MACRO AUTHORING FLOW (canonical) — spec AcceptanceCriteria-macro-authoring.md.
//  The GENERIC control-group registry + the pure authoring logic (sparse deltas · mover eligibility · the
//  offset-preview morph) + per-domain value get/set. Foundation-only + unit-tested — Paul's rule "this is about
//  CONTROLS rather than processors specifically" makes the descriptor data-only, so the SAME flow + UI serve
//  processors · receivers · emitters · rack. The offset ENGINE underneath (applyMacros / AU params / the 24 macro
//  slots) is unchanged and reused; this layer authors bindings on top of it.

import Foundation

/// How one control moves — drives BOTH the generic renderer (which widget) and mover ELIGIBILITY (§5): only
/// `.continuous` may bind to a slider (a glide); everything else is DISCRETE (a snap → BUTTON-only, dims sliders).
enum MacroControlKind: Equatable {
    case continuous(lo: Double, hi: Double)   // slider — 0…1, bipolar, ms…
    case toggle                               // bool — 0/1 (a switch)
    case option([String])                     // enum — value = index into the option labels (a segmented pick)
    case stepper(lo: Int, hi: Int)            // integer range — value = the int (±)
    case mask(bits: Int)                      // packed bit-toggles — value = the packed integer

    var isDiscrete: Bool { if case .continuous = self { return false }; return true }
}

/// One authorable control — the descriptor the authoring page renders MAIN/ALT instances from and the binding keys
/// its sparse delta by. `key` is STABLE (continuous processor params reuse the `MacroParam` raw values so their
/// bindings stay `MacroTarget`-compatible; discrete params get their own keys, bound via the button/timeline path).
struct MacroControlParam: Equatable {
    let key: String
    let label: String
    let kind: MacroControlKind
}

/// The app domains the flow hosts on (Paul: "the recievers, the emmiters and the rack" as well as processors).
enum MacroDomain: String, Equatable { case processor, receiver, emitter, rack }

/// A registered CONTROL GROUP — any surface the MACRO button attaches to. Data-only: the authoring page renders
/// from `params`; the binding stores a sparse delta keyed by `param.key`; the host maps the group back to its live
/// target(s) by `id`.
struct MacroControlGroup: Equatable {
    let id: String
    let title: String
    let domain: MacroDomain
    let params: [MacroControlParam]
}

// MARK: - the pure authoring logic (drives the TEST audition, the assignment eligibility, and the stored binding)

/// §3 SPARSE DELTAS: for each param, ALT − MAIN, keeping ONLY the params that actually diverge (untouched params
/// carry nothing). Continuous compares with an epsilon (float noise); discrete compares exactly. Keys are
/// `MacroControlParam.key`. This IS the stored binding (relative — the offset law: if MAIN later moves, the delta
/// still applies to the new base).
func macroSparseDelta(main: [String: Double], alt: [String: Double],
                      params: [MacroControlParam], eps: Double = 1e-9) -> [String: Double] {
    var out: [String: Double] = [:]
    for p in params {
        let d = (alt[p.key] ?? 0) - (main[p.key] ?? 0)
        if p.kind.isDiscrete ? (d != 0) : (abs(d) > eps) { out[p.key] = d }
    }
    return out
}

/// §5 MOVER ELIGIBILITY: a delta touching ANY discrete param is BUTTON-only (the slider rows dim). A
/// continuous-only delta may also bind to a slider.
func macroDeltaHasDiscrete(_ delta: [String: Double], params: [MacroControlParam]) -> Bool {
    let discrete = Set(params.filter { $0.kind.isDiscrete }.map(\.key))
    return delta.keys.contains { discrete.contains($0) }
}

/// The offset PREVIEW (the M1 law, generalised to a value dict) — effective = MAIN + value × delta per param.
/// Continuous params glide, clamped to their range; discrete params SNAP to ALT past the halfway point (a
/// button/step, never an intermediate). Drives the TEST slider (continuous) + TEST button (snap) audition and, at
/// bind time, matches how the engine folds the offset. Returns a full value dict (MAIN for untouched params).
func macroApply(main: [String: Double], delta: [String: Double], value: Double,
                params: [MacroControlParam]) -> [String: Double] {
    var out = main
    let v = clamp(value, 0, 1)
    for p in params {
        guard let d = delta[p.key], d != 0 else { continue }
        let base = main[p.key] ?? 0
        switch p.kind {
        case .continuous(let lo, let hi): out[p.key] = clamp(base + v * d, lo, hi)
        case .option(let labels):         out[p.key] = clamp((base + v * d).rounded(), 0, Double(max(0, labels.count - 1)))   // SWEEP through the options
        case .stepper(let lo, let hi):    out[p.key] = Double(clamp(Int((base + v * d).rounded()), lo, hi))                    // SWEEP through the steps
        case .toggle, .mask:              out[p.key] = v >= 0.5 ? base + d : base                                              // binary SNAP at halfway
        }
    }
    return out
}

/// One macro's binding to a processor slot — the param→delta map it holds on (col,row,slot). Powers the pop-up's
/// "edit an existing macro" dropdown (reflect a macro back onto the page). Only continuous targets are stored today.
struct MacroSlotBinding: Equatable { let macro: Int; let deltas: [String: Double] }

/// The macros already bound to a processor slot, each with its param→delta map (summing overlapping targets).
/// `col/row/slot` identify the slot; index = the macro's index. Pure/testable.
func macroSlotBindings(_ macros: [Macro], col: Int, row: Int, slot: Int) -> [MacroSlotBinding] {
    var out: [MacroSlotBinding] = []
    for (i, m) in macros.enumerated() {
        var d: [String: Double] = [:]
        for t in m.targets where t.col == col && t.row == row && t.slot == slot { d[t.param, default: 0] += t.delta }
        if !d.isEmpty { out.append(MacroSlotBinding(macro: i, deltas: d)) }
    }
    return out
}

// MARK: - the PROCESSOR domain (the first host — Paul's illustration). "All controls available to that processor"
// + the universal BYPASS. Continuous keys reuse the MacroParam raws so those bindings fold through the engine
// today; discrete keys are BUTTON-targets (their binding path lands with the button/timeline mover work).

/// The authorable controls for a processor slot of `type` (plus the universal BYPASS). Pure/testable data.
func macroParamsForProcessor(_ type: ProcessorType) -> [MacroControlParam] {
    let bypass = MacroControlParam(key: "bypass", label: "BYPASS", kind: .toggle)
    let gate   = MacroControlParam(key: "gate", label: "GATE", kind: .continuous(lo: 0.05, hi: 1))
    // GATE means note length in ARP + WEAVE → friendly label LENGTH (reply global rule). RATCHET keeps GATE (not in the reply).
    let length = MacroControlParam(key: "gate", label: "LENGTH", kind: .continuous(lo: 0.05, hi: 1))
    switch type {
    case .arp:
        return [bypass,
                MacroControlParam(key: "pattern", label: "PATTERN", kind: .option(ArpPattern.allCases.map(\.rawValue))),
                MacroControlParam(key: "rate", label: "SPEED", kind: .option(ArpRate.allCases.map(\.rawValue))),
                MacroControlParam(key: "octaves", label: "OCTAVES", kind: .stepper(lo: 1, hi: 4)),
                MacroControlParam(key: "phase", label: "NEW CHORD", kind: .option(ArpPhase.allCases.map(\.rawValue))),
                length]
    case .ratchet:
        return [bypass,
                MacroControlParam(key: "rtcMode", label: "MODE", kind: .option(RatchetMode.allCases.map(\.rawValue))),
                MacroControlParam(key: "count", label: "REPEATS", kind: .stepper(lo: 2, hi: 8)),
                MacroControlParam(key: "ramp", label: "BURST FADE", kind: .continuous(lo: 0, hi: 1)),
                MacroControlParam(key: "rtcChance", label: "CHANCE", kind: .continuous(lo: 0, hi: 1)),
                MacroControlParam(key: "rtcCountLo", label: "SIZE MIN", kind: .stepper(lo: 1, hi: 8)),
                MacroControlParam(key: "rtcCountHi", label: "SIZE MAX", kind: .stepper(lo: 1, hi: 8)),
                MacroControlParam(key: "rtcRate", label: "GRID", kind: .option(ArpRate.allCases.map(\.rawValue))),
                MacroControlParam(key: "rtcRotate", label: "ROTATE", kind: .stepper(lo: 0, hi: 7)),
                gate]
    case .strum:
        return [bypass,
                MacroControlParam(key: "strumDir", label: "DIRECTION", kind: .option(StrumDir.allCases.map(\.rawValue))),
                MacroControlParam(key: "spread", label: "SPREAD", kind: .continuous(lo: 0, hi: 1)),
                MacroControlParam(key: "curve", label: "CURVE", kind: .continuous(lo: -1, hi: 1)),
                MacroControlParam(key: "velTilt", label: "VOL TILT", kind: .continuous(lo: -1, hi: 1))]
    case .chance:
        return [bypass,
                MacroControlParam(key: "probability", label: "CHANCE", kind: .continuous(lo: 0, hi: 1))]
    case .harmonize:
        return [bypass,
                MacroControlParam(key: "harm0", label: "VOICE 1", kind: .stepper(lo: -24, hi: 24)),
                MacroControlParam(key: "harm1", label: "VOICE 2", kind: .stepper(lo: -24, hi: 24)),
                MacroControlParam(key: "harm2", label: "VOICE 3", kind: .stepper(lo: -24, hi: 24)),
                MacroControlParam(key: "harmVelScale", label: "VOICE VEL", kind: .continuous(lo: 0.1, hi: 1))]
    case .passgate:
        return [bypass,
                MacroControlParam(key: "passMask", label: "PLAY ON PASS", kind: .mask(bits: 4))]
    case .echo:
        return [bypass,
                MacroControlParam(key: "rate", label: "TIME", kind: .option(ArpRate.allCases.map(\.rawValue))),
                MacroControlParam(key: "count", label: "REPEATS", kind: .stepper(lo: 2, hi: 8)),
                MacroControlParam(key: "ramp", label: "FADE", kind: .continuous(lo: 0, hi: 1))]
    case .euclid:
        return [bypass,
                MacroControlParam(key: "euclidPulses", label: "HITS FROM", kind: .stepper(lo: 1, hi: 16)),
                MacroControlParam(key: "euclidSteps", label: "STEPS", kind: .stepper(lo: 2, hi: 16)),
                MacroControlParam(key: "euclidRot", label: "ROTATE", kind: .stepper(lo: 0, hi: 15))]
    case .burst:
        return [bypass,
                MacroControlParam(key: "count", label: "HITS", kind: .stepper(lo: 2, hi: 16)),
                MacroControlParam(key: "curve", label: "SHAPE", kind: .continuous(lo: -1, hi: 1))]
    case .cascade:
        return [bypass,
                MacroControlParam(key: "rate", label: "SPEED", kind: .option(ArpRate.allCases.map(\.rawValue)))]
    case .drone:
        return [bypass, MacroControlParam(key: "gate", label: "LEVEL", kind: .continuous(lo: 0.05, hi: 1))]
    case .shift:
        return [bypass, MacroControlParam(key: "spread", label: "PUSH", kind: .continuous(lo: 0, hi: 1))]
    case .humanize:
        return [bypass, MacroControlParam(key: "spread", label: "FEEL", kind: .continuous(lo: 0, hi: 1))]
    case .mod:
        return [bypass,
                MacroControlParam(key: "modCC", label: "SEND CC", kind: .stepper(lo: 0, hi: 127)),
                MacroControlParam(key: "modShape", label: "WAVE", kind: .option(ModShape.allCases.map(\.rawValue))),
                MacroControlParam(key: "modMin", label: "MIN", kind: .continuous(lo: 0, hi: 127)),   // range IS depth+polarity; macro-able (stabs)
                MacroControlParam(key: "modMax", label: "MAX", kind: .continuous(lo: 0, hi: 127)),
                MacroControlParam(key: "modRate", label: "CYCLE", kind: .option(ModRate.allCases.map(\.rawValue))),
                MacroControlParam(key: "modReset", label: "ON EXIT", kind: .toggle)]
    case .glide:
        return [bypass,
                MacroControlParam(key: "glideRange", label: "BEND RANGE", kind: .stepper(lo: 1, hi: 48)),
                MacroControlParam(key: "glidePriority", label: "FOLLOW", kind: .option(GlidePriority.allCases.map(\.rawValue))),
                MacroControlParam(key: "glideReanchor", label: "TOO FAR", kind: .toggle)]
    case .tutti:
        return [bypass,
                MacroControlParam(key: "tuttiMode", label: "MODE", kind: .option(TuttiMode.allCases.map(\.rawValue))),
                MacroControlParam(key: "tuttiBalance", label: "BALANCE", kind: .continuous(lo: 0, hi: 1)),
                MacroControlParam(key: "tuttiPick", label: "SOLO NOTE", kind: .option(TuttiPick.allCases.map(\.rawValue)))]
    case .length:
        return [bypass,
                MacroControlParam(key: "lenShort", label: "SHORT =", kind: .continuous(lo: 0.05, hi: 0.95)),
                MacroControlParam(key: "lenLong", label: "LONG =", kind: .continuous(lo: 0, hi: 1)),
                MacroControlParam(key: "lenRotate", label: "ROTATE", kind: .stepper(lo: 0, hi: 7))]
    case .weave:
        return [bypass,
                MacroControlParam(key: "weaveMode", label: "MODE", kind: .option(WeaveMode.allCases.map(\.rawValue))),
                MacroControlParam(key: "weaveBaseStep", label: "BASS CLOCK", kind: .option(StepRate.allCases.map(\.rawValue))),
                MacroControlParam(key: "weavePhase", label: "NEW CHORD", kind: .option(ArpPhase.allCases.map(\.rawValue))),
                MacroControlParam(key: "weaveSpan", label: "VOICES", kind: .stepper(lo: 1, hi: 8)),
                MacroControlParam(key: "weaveEuclidSteps", label: "STEPS", kind: .stepper(lo: 2, hi: 16)),
                length]
    case .split:
        return [bypass,
                MacroControlParam(key: "splitMode", label: "KEEP", kind: .option(SplitMode.allCases.map(\.rawValue))),
                MacroControlParam(key: "splitN", label: "NOTES", kind: .stepper(lo: 1, hi: 8)),
                MacroControlParam(key: "splitNote", label: "AT NOTE", kind: .stepper(lo: 0, hi: 127)),
                MacroControlParam(key: "splitHigh", label: "SIDE", kind: .toggle),
                MacroControlParam(key: "splitVFloor", label: "VEL MIN", kind: .stepper(lo: 1, hi: 127)),
                MacroControlParam(key: "splitVCeil", label: "VEL MAX", kind: .stepper(lo: 1, hi: 127))]
    case .octave, .transpose, .channel, .nudge, .dest, .muteMatrix:
        return [bypass]   // UTILITY/ROUTING (Paul 2026-08-22): a single simple control; edited directly (macro-folding is out of scope)
    }
}

/// The control group for a processor slot at a grid position (id encodes col·row·slot so the host maps back).
func macroGroupForProcessor(col: Int, row: Int, slot: Int, type: ProcessorType) -> MacroControlGroup {
    MacroControlGroup(id: "proc:\(col),\(row),\(slot)", title: type.rawValue.uppercased(),
                      domain: .processor, params: macroParamsForProcessor(type))
}

private func optionIndex<T: RawRepresentable & CaseIterable>(_ v: T?) -> Double where T.RawValue == String {
    Double(Array(T.allCases).firstIndex { $0.rawValue == v?.rawValue } ?? 0)
}
private func caseAt<T: CaseIterable>(_ i: Double, _: T.Type) -> T {
    let all = Array(T.allCases); return all[clamp(Int(i.rounded()), 0, all.count - 1)]
}

/// READ a processor slot's live values into the descriptor's value dict (the MAIN/ALT seed + the delta operands).
/// Enums encode as their case index; toggles 0/1; steppers/masks as their integer. Pure/testable.
func processorValues(_ slot: ProcessorSlot) -> [String: Double] {
    let p = slot.params
    var v: [String: Double] = ["bypass": slot.bypassed ? 1 : 0]
    for param in macroParamsForProcessor(slot.type) {
        switch param.key {
        case "pattern":      v[param.key] = optionIndex(p.pattern)
        case "rate":         v[param.key] = optionIndex(p.rate)
        case "phase":        v[param.key] = optionIndex(p.phase)
        case "strumDir":     v[param.key] = optionIndex(p.strumDir)
        case "octaves":      v[param.key] = Double(p.octaves ?? 1)
        case "gate":         v[param.key] = p.gate ?? 0.6
        case "count":        v[param.key] = Double(p.count ?? 3)
        case "ramp":         v[param.key] = p.ramp ?? 0.5
        case "rtcMode":      v[param.key] = optionIndex(p.rtcMode)
        case "rtcChance":    v[param.key] = p.rtcChance ?? 0.5
        case "rtcCountLo":   v[param.key] = Double(p.rtcCountLo ?? 2)
        case "rtcCountHi":   v[param.key] = Double(p.rtcCountHi ?? 4)
        case "rtcRate":      v[param.key] = optionIndex(p.rtcRate)
        case "rtcRotate":    v[param.key] = Double(p.rtcRotate ?? 0)
        case "spread":       v[param.key] = p.spread ?? 0.1
        case "curve":        v[param.key] = p.curve ?? 0
        case "velTilt":      v[param.key] = p.velTilt ?? 0
        case "probability":  v[param.key] = p.probability ?? 1
        case "harmVelScale": v[param.key] = p.harmVelScale ?? 0.8
        case "euclidPulses": v[param.key] = Double(p.euclidPulses ?? 5)
        case "euclidSteps":  v[param.key] = Double(p.euclidSteps ?? 8)
        case "euclidRot":    v[param.key] = Double(p.euclidRot ?? 0)
        case "harm0":        v[param.key] = Double(p.harmIntervals?[safe: 0] ?? 0)
        case "harm1":        v[param.key] = Double(p.harmIntervals?[safe: 1] ?? 0)
        case "harm2":        v[param.key] = Double(p.harmIntervals?[safe: 2] ?? 0)
        case "passMask":     v[param.key] = Double((p.passes ?? [true, true, true, true]).enumerated()
                                                     .reduce(0) { $0 | ($1.element ? (1 << $1.offset) : 0) })
        case "modCC":        v[param.key] = Double(p.modCC ?? 74)
        case "modShape":     v[param.key] = optionIndex(p.modShape)
        case "modRate":      v[param.key] = optionIndex(p.modRate)
        case "modMin":       v[param.key] = Double(p.modMin ?? 0)
        case "modMax":       v[param.key] = Double(p.modMax ?? 127)
        case "modReset":     v[param.key] = (p.modReset ?? true) ? 1 : 0
        case "glideRange":    v[param.key] = Double(p.glideRange ?? 2)
        case "glidePriority": v[param.key] = optionIndex(p.glidePriority)
        case "glideReanchor": v[param.key] = (p.glideReanchor ?? true) ? 1 : 0
        case "tuttiMode":    v[param.key] = optionIndex(p.tuttiMode)
        case "tuttiBalance": v[param.key] = p.tuttiBalance ?? 0.5
        case "tuttiPick":    v[param.key] = optionIndex(p.tuttiPick)
        case "lenShort":     v[param.key] = p.lenShort ?? 0.4
        case "lenLong":      v[param.key] = p.lenLong ?? 0.7
        case "lenRotate":    v[param.key] = Double(p.lenRotate ?? 0)
        case "weaveMode":    v[param.key] = optionIndex(p.weaveMode)
        case "weaveBaseStep": v[param.key] = optionIndex(p.weaveBaseStep)
        case "weavePhase":   v[param.key] = optionIndex(p.weavePhase)
        case "weaveSpan":    v[param.key] = Double(p.weaveSpan ?? 4)
        case "weaveEuclidSteps": v[param.key] = Double(p.weaveEuclidSteps ?? 8)
        case "splitMode":    v[param.key] = optionIndex(p.splitSet?.mode)
        case "splitN":       v[param.key] = Double(p.splitSet?.n ?? 2)
        case "splitNote":    v[param.key] = Double(p.splitSet?.note ?? 60)
        case "splitHigh":    v[param.key] = (p.splitSet?.high ?? true) ? 1 : 0
        case "splitVFloor":  v[param.key] = Double(p.splitVel?.floor ?? 1)
        case "splitVCeil":   v[param.key] = Double(p.splitVel?.ceil ?? 127)
        default: break
        }
    }
    return v
}

/// WRITE a value dict back onto a processor slot (MAIN-is-real on APPLY). Only the slot's own descriptor keys are
/// applied; discretes round + clamp to their legal domain. Pure/testable (round-trips with `processorValues`).
func applyProcessorValues(_ v: [String: Double], to slot: ProcessorSlot) -> ProcessorSlot {
    var s = slot
    if let b = v["bypass"] { s.bypassed = b >= 0.5 }
    for param in macroParamsForProcessor(slot.type) {
        guard let val = v[param.key] else { continue }
        switch param.key {
        case "pattern":      s.params.pattern = caseAt(val, ArpPattern.self)
        case "rate":         s.params.rate = caseAt(val, ArpRate.self)
        case "phase":        s.params.phase = caseAt(val, ArpPhase.self)
        case "strumDir":     s.params.strumDir = caseAt(val, StrumDir.self)
        case "octaves":      s.params.octaves = clamp(Int(val.rounded()), 1, 4)
        case "gate":         s.params.gate = clamp(val, 0.05, 1)
        case "count":        s.params.count = clamp(Int(val.rounded()), 2, 8)
        case "ramp":         s.params.ramp = clamp(val, 0, 1)
        case "rtcMode":      s.params.rtcMode = caseAt(val, RatchetMode.self)
        case "rtcChance":    s.params.rtcChance = clamp(val, 0, 1)
        case "rtcCountLo":   s.params.rtcCountLo = clamp(Int(val.rounded()), 1, 8)
        case "rtcCountHi":   s.params.rtcCountHi = clamp(Int(val.rounded()), 1, 8)
        case "rtcRate":      s.params.rtcRate = caseAt(val, ArpRate.self)
        case "rtcRotate":    s.params.rtcRotate = clamp(Int(val.rounded()), 0, 7)
        case "spread":       s.params.spread = clamp(val, 0, 1)
        case "curve":        s.params.curve = clamp(val, -1, 1)
        case "velTilt":      s.params.velTilt = clamp(val, -1, 1)
        case "probability":  s.params.probability = clamp(val, 0, 1)
        case "harmVelScale": s.params.harmVelScale = clamp(val, 0.1, 1)
        case "euclidPulses": s.params.euclidPulses = clamp(Int(val.rounded()), 1, 16)
        case "euclidSteps":  s.params.euclidSteps = clamp(Int(val.rounded()), 2, 16)
        case "euclidRot":    s.params.euclidRot = clamp(Int(val.rounded()), 0, 15)
        case "harm0", "harm1", "harm2":
            let idx = Int(param.key.suffix(1)) ?? 0
            var h = s.params.harmIntervals ?? [0, 0, 0]; while h.count < 3 { h.append(0) }
            h[idx] = clamp(Int(val.rounded()), -24, 24); s.params.harmIntervals = h
        case "passMask":
            let m = clamp(Int(val.rounded()), 0, 15); s.params.passes = (0..<4).map { (m >> $0) & 1 == 1 }
        case "modCC":        s.params.modCC = clamp(Int(val.rounded()), 0, 127)
        case "modShape":     s.params.modShape = caseAt(val, ModShape.self)
        case "modRate":      s.params.modRate = caseAt(val, ModRate.self)
        case "modMin":       s.params.modMin = clamp(Int(val.rounded()), 0, 127)
        case "modMax":       s.params.modMax = clamp(Int(val.rounded()), 0, 127)
        case "modReset":     s.params.modReset = val >= 0.5
        case "glideRange":    s.params.glideRange = clamp(Int(val.rounded()), 1, 48)
        case "glidePriority": s.params.glidePriority = caseAt(val, GlidePriority.self)
        case "glideReanchor": s.params.glideReanchor = val >= 0.5
        case "tuttiMode":    s.params.tuttiMode = caseAt(val, TuttiMode.self)
        case "tuttiBalance": s.params.tuttiBalance = clamp(val, 0, 1)
        case "tuttiPick":    s.params.tuttiPick = caseAt(val, TuttiPick.self)
        case "lenShort":     s.params.lenShort = clamp(val, 0.05, 0.95)
        case "lenLong":      s.params.lenLong = clamp(val, 0, 1)
        case "lenRotate":    s.params.lenRotate = clamp(Int(val.rounded()), 0, 7)
        case "weaveMode":    s.params.weaveMode = caseAt(val, WeaveMode.self)
        case "weaveBaseStep": s.params.weaveBaseStep = caseAt(val, StepRate.self)
        case "weavePhase":   s.params.weavePhase = caseAt(val, ArpPhase.self)
        case "weaveSpan":    s.params.weaveSpan = clamp(Int(val.rounded()), 1, 8)
        case "weaveEuclidSteps": s.params.weaveEuclidSteps = clamp(Int(val.rounded()), 2, 16)
        case "splitMode":    s.params.splitSet = { var c = s.params.splitSet ?? ChordSplit(); c.mode = caseAt(val, SplitMode.self); return c }()
        case "splitN":       s.params.splitSet = { var c = s.params.splitSet ?? ChordSplit(); c.n = clamp(Int(val.rounded()), 1, 8); return c }()
        case "splitNote":    s.params.splitSet = { var c = s.params.splitSet ?? ChordSplit(); c.note = clamp(Int(val.rounded()), 0, 127); return c }()
        case "splitHigh":    s.params.splitSet = { var c = s.params.splitSet ?? ChordSplit(); c.high = val >= 0.5; return c }()
        case "splitVFloor":  s.params.splitVel = { var w = s.params.splitVel ?? VelWindow(); w.floor = clamp(Int(val.rounded()), 1, 127); return w }()
        case "splitVCeil":   s.params.splitVel = { var w = s.params.splitVel ?? VelWindow(); w.ceil = clamp(Int(val.rounded()), 1, 127); return w }()
        default: break
        }
    }
    return s
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
