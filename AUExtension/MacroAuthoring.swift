//  MacroAuthoring.swift
//  THE MACRO AUTHORING FLOW (canonical) — spec AcceptanceCriteria-macro-authoring.md.
//  Phase A: the GENERIC control-group registry + the pure authoring logic (sparse deltas · mover eligibility · the
//  offset-preview morph). Foundation-only + unit-tested — Paul's rule "this is about CONTROLS rather than processors
//  specifically" means the descriptor is data-only and the same logic serves processors · receivers · emitters ·
//  rack. The UI (authoring page + assignment view) and the per-domain group builders layer on top in later phases;
//  the offset ENGINE underneath (applyMacros / AU params / the 24 macro slots) is unchanged and reused.

import Foundation

/// How a single control moves — decides mover ELIGIBILITY (§5): a CONTINUOUS param can bind to a slider (a glide);
/// a DISCRETE one (enum flip · bool · mask · stepped count) is BUTTON-only (a snap), and dims the slider rows.
enum MacroControlKind: Equatable {
    case continuous(lo: Double, hi: Double)
    case discrete
    var isDiscrete: Bool { if case .discrete = self { return true }; return false }
}

/// One authorable control in a group — the descriptor the authoring page renders MAIN/ALT instances from and the
/// binding keys its sparse delta by. `key` is a STABLE identifier (continuous processor params reuse the existing
/// `MacroParam` raw values so their bindings stay `MacroTarget`-compatible; discrete params get their own keys).
struct MacroControlParam: Equatable {
    let key: String
    let label: String
    let kind: MacroControlKind
}

/// The app domains the flow can host on (Paul: "the recievers, the emmiters and the rack" as well as processors).
enum MacroDomain: String, Equatable { case processor, receiver, emitter, rack }

/// A registered CONTROL GROUP — any surface the MACRO button attaches to. Data-only: the authoring page renders
/// from `params`; the binding stores a sparse delta keyed by `param.key`; the host maps the group back to its
/// live target(s) by `id`.
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
        case .discrete:                   out[p.key] = v >= 0.5 ? base + d : base
        }
    }
    return out
}

// MARK: - the processor domain descriptor (the first host — Paul's illustration: "all controls available to that
// processor"). Continuous keys reuse the MacroParam raw values so their bindings fold through applyMacros today;
// discrete keys (bypass · type enums · stepped counts) are BUTTON-targets (their binding path lands with the
// button/timeline mover work). Receiver/emitter/rack descriptors follow in their wiring phases.

/// The authorable controls for a processor slot of `type` (plus the universal BYPASS). Pure/testable data.
func macroParamsForProcessor(_ type: ProcessorType) -> [MacroControlParam] {
    let bypass = MacroControlParam(key: "bypass", label: "BYPASS", kind: .discrete)
    let gate   = MacroControlParam(key: "gate", label: "GATE", kind: .continuous(lo: 0.05, hi: 1))
    switch type {
    case .arp:
        return [bypass,
                MacroControlParam(key: "pattern", label: "PATTERN", kind: .discrete),
                MacroControlParam(key: "rate", label: "RATE", kind: .discrete),
                MacroControlParam(key: "octaves", label: "OCTAVES", kind: .discrete),
                MacroControlParam(key: "phase", label: "PHASE", kind: .discrete),
                gate]
    case .ratchet:
        return [bypass,
                MacroControlParam(key: "count", label: "REPEATS", kind: .discrete),
                MacroControlParam(key: "ramp", label: "RAMP", kind: .continuous(lo: 0, hi: 1)),
                gate]
    case .strum:
        return [bypass,
                MacroControlParam(key: "strumDir", label: "DIR", kind: .discrete),
                MacroControlParam(key: "spread", label: "SPREAD", kind: .continuous(lo: 0, hi: 1)),
                MacroControlParam(key: "curve", label: "CURVE", kind: .continuous(lo: -1, hi: 1)),
                MacroControlParam(key: "velTilt", label: "VEL TILT", kind: .continuous(lo: -1, hi: 1))]
    case .chance:
        return [bypass,
                MacroControlParam(key: "probability", label: "CHANCE", kind: .continuous(lo: 0, hi: 1))]
    case .harmonize:
        return [bypass,
                MacroControlParam(key: "harm", label: "INTERVALS", kind: .discrete),
                MacroControlParam(key: "harmVelScale", label: "VOICE VEL", kind: .continuous(lo: 0.1, hi: 1))]
    case .passgate:
        return [bypass,
                MacroControlParam(key: "passMask", label: "PASSES", kind: .discrete)]
    }
}
