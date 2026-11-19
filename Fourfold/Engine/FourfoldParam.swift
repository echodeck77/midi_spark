//  FourfoldParam.swift — host parameters (RATIFIED 2026-11-16), slice 1: the PURE mapping table (Foundation-only, in the FourfoldTests target).
//  ONE table maps each AU parameter ADDRESS ↔ a document (`PluginState`) field, BOTH ways: `get` reads the resolved value, `set` writes it (through the page's own setter where one exists — `euclideousSliderCommit` for Hits/Steps/Offset — so the
//  requested-remember + pattern regeneration stay correct). The AU (slice 2) builds its `AUParameterTree` and its observer/push from this table; nothing here touches CoreAudio. Addresses are STABLE FOREVER (invariant 5) — add, never renumber.
//  Alphabetical order (AUM lists params flat A→Z): the NAMES block cleanly — `Key …` → `Lane 1…4 …` → `Out a…d …`. Params only SET existing document fields, so an untouched document is byte-identical (golden unchanged). No render-side route; the AU marshals a host write onto main.

import Foundation

enum FourfoldParamKind: Equatable {
    case boolean
    case stepped                 // an integer range
    case indexed([String])       // an enum: value = the 0-based case index; the strings name the cases
}

struct FourfoldParamDef {
    let address: UInt64
    let name: String
    let min: Float, max: Float, def: Float
    let kind: FourfoldParamKind
    let get: (PluginState) -> Float
    let set: (inout PluginState, Float) -> Void
}

// MARK: - small helpers

private func laneOf(_ s: PluginState, _ i: Int) -> EuclidLine {
    let l = s.euclideousLinesResolved
    return (0..<l.count).contains(i) ? l[i] : EuclidLine(noteSel: .all)
}
private func editLane(_ s: inout PluginState, _ i: Int, _ f: (inout EuclidLine) -> Void) {
    var lines = s.euclideousLinesResolved
    guard (0..<lines.count).contains(i) else { return }
    f(&lines[i]); s.euclideousLines = lines
}
private func clampIndex(_ v: Float, _ count: Int) -> Int { max(0, min(count - 1, Int(v.rounded()))) }
private let laneNames = ["1", "2", "3", "4"]
private let outNames = ["a", "b", "c", "d"]
private let scaleNames = ScaleType.allCases.map { $0.rawValue }
private let rateNames = ArpRate.allCases.map { $0.rawValue }
private let rateDefaultIndex = ArpRate.allCases.firstIndex(of: .r1_4) ?? 0   // a lane with no stored rate reads as 1/4 (`defaultRateBeats` 0.25)

// MARK: - the table

/// Every host parameter, in ADDRESS order (the AU sorts for display; the host shows them alphabetically by `name`).
func fourfoldParams() -> [FourfoldParamDef] {
    var p: [FourfoldParamDef] = []

    // ── Global ──────────────────────────────────────────────────────────────
    p.append(FourfoldParamDef(address: 0, name: "Key Root", min: 0, max: 11, def: 0, kind: .indexed(["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]),
                              get: { Float($0.euclideousKeyRootResolved) },
                              set: { s, v in s.euclideousKeyRoot = clampIndex(v, 12) }))
    p.append(FourfoldParamDef(address: 1, name: "Key Scale", min: 0, max: Float(scaleNames.count - 1), def: Float(ScaleType.allCases.firstIndex(of: .naturalMinor) ?? 0), kind: .indexed(scaleNames),
                              get: { Float(ScaleType.allCases.firstIndex(of: $0.euclideousKeyTypeResolved) ?? 0) },
                              set: { s, v in s.euclideousKeyType = ScaleType.allCases[clampIndex(v, scaleNames.count)] }))
    // HEADER v2 (§2): the two global PLAY-part masters — automatable booleans, default ON (so an untouched document is byte-identical, golden unchanged). Addresses 2/3 extend the global block (0/1); addresses are stable forever (invariant 5).
    p.append(FourfoldParamDef(address: 2, name: "Play riff", min: 0, max: 1, def: 1, kind: .boolean,
                              get: { $0.riffMasterResolved ? 1 : 0 }, set: { s, v in s.riffMaster = v > 0.5 }))
    p.append(FourfoldParamDef(address: 3, name: "Play stack", min: 0, max: 1, def: 1, kind: .boolean,
                              get: { $0.stackMasterResolved ? 1 : 0 }, set: { s, v in s.stackMaster = v > 0.5 }))

    // ── Per lane (1…4) ──────────────────────────────────────────────────────
    for i in 0..<4 {
        let n = laneNames[i], base = UInt64(1000 + i * 100)
        func L(_ addr: UInt64, _ name: String, _ lo: Float, _ hi: Float, _ d: Float, _ k: FourfoldParamKind, _ g: @escaping (EuclidLine) -> Float, _ st: @escaping (inout EuclidLine, Float) -> Void) {
            p.append(FourfoldParamDef(address: base + addr, name: "Lane \(n) \(name)", min: lo, max: hi, def: d, kind: k,
                                      get: { g(laneOf($0, i)) }, set: { s, v in editLane(&s, i) { st(&$0, v) } }))
        }
        // lane-level
        L(0, "Play", 0, 1, 1, .boolean, { $0.enabledResolved ? 1 : 0 }, { l, v in l.enabled = v > 0.5 })
        L(1, "Hits", 0, 16, 1, .stepped, { Float($0.hitsRequestedResolved) }, { l, v in euclideousSliderCommit(.hits, &l, snapshot: l, newValue: Double(v.rounded())) })
        L(2, "Offset", 0, 15, 0, .stepped, { Float(max(0, min(15, $0.offsetRequestedResolved))) }, { l, v in euclideousSliderCommit(.offset, &l, snapshot: l, newValue: Double(v.rounded())) })
        L(3, "Steps", 2, 16, 8, .stepped, { Float($0.steps) }, { l, v in euclideousSliderCommit(.steps, &l, snapshot: l, newValue: Double(v.rounded())) })
        L(4, "Rate", 0, Float(rateNames.count - 1), Float(rateDefaultIndex), .indexed(rateNames), { Float(ArpRate.allCases.firstIndex(of: $0.rate ?? .r1_4) ?? rateDefaultIndex) }, { l, v in l.rate = ArpRate.allCases[clampIndex(v, rateNames.count)] })
        // riff part
        L(10, "Riff Play", 0, 1, 1, .boolean, { $0.riffOnResolved ? 1 : 0 }, { l, v in l.riffOn = v > 0.5 })
        L(11, "Riff Gate", 1, 99, 90, .stepped, { Float((($0.gateResolved) * 100).rounded()) }, { l, v in l.gate = Double(max(1, min(99, v.rounded()))) / 100 })
        L(12, "Riff Octave", -2, 2, 0, .stepped, { Float($0.riffOctaveResolved) }, { l, v in l.riffOctave = max(-2, min(2, Int(v.rounded()))) })
        L(13, "Riff Velocity", 1, 127, 100, .stepped, { Float($0.velocityAbsoluteResolved) }, { l, v in l.velocityAbsolute = max(1, min(127, Int(v.rounded()))) })
        // stack part (the notes layer)
        L(20, "Stack Play", 0, 1, 0, .boolean, { $0.notesOnResolved ? 1 : 0 }, { l, v in l.notesOn = v > 0.5 })
        L(21, "Stack Gate", 1, 99, 90, .stepped, { Float(($0.notesGateResolved * 100).rounded()) }, { l, v in l.notesGate = Double(max(1, min(99, v.rounded()))) / 100 })
        L(22, "Stack Octave", -2, 2, 0, .stepped, { Float($0.octaveResolved) }, { l, v in l.octave = max(-2, min(2, Int(v.rounded()))) })
        L(23, "Stack Velocity", 1, 127, 100, .stepped, { Float($0.notesVelocityResolved) }, { l, v in l.notesVelocity = max(1, min(127, Int(v.rounded()))) })
    }

    // ── Per output (a…d) — slot 0 of each output's CC emitter; Mute = the whole output ──
    for o in 0..<4 {
        let n = outNames[o], base = UInt64(2000 + o * 100)
        p.append(FourfoldParamDef(address: base + 0, name: "Out \(n) Mute", min: 0, max: 1, def: 0, kind: .boolean,
                                  get: { $0.euclideousOutputMutesResolved[o].cells16 == 0 ? 1 : 0 },   // muted = every cell cleared
                                  set: { s, v in var m = s.euclideousOutputMutesResolved; m[o].cells16 = v > 0.5 ? 0 : 0xFFFF; s.euclideousOutputMutes = m }))
        p.append(FourfoldParamDef(address: base + 1, name: "Out \(n) CC On", min: 0, max: 1, def: 0, kind: .boolean,
                                  get: { $0.euclideousEmitterCCsResolved[o * 4].on ? 1 : 0 },
                                  set: { s, v in var c = s.euclideousEmitterCCsResolved; c[o * 4].on = v > 0.5; s.euclideousEmitterCCs = c }))
        p.append(FourfoldParamDef(address: base + 2, name: "Out \(n) CC High", min: 0, max: 127, def: 127, kind: .stepped,
                                  get: { Float($0.euclideousEmitterCCsResolved[o * 4].high) },
                                  set: { s, v in var c = s.euclideousEmitterCCsResolved; c[o * 4].high = max(0, min(127, Int(v.rounded()))); s.euclideousEmitterCCs = c }))
        p.append(FourfoldParamDef(address: base + 3, name: "Out \(n) CC Low", min: 0, max: 127, def: 0, kind: .stepped,
                                  get: { Float($0.euclideousEmitterCCsResolved[o * 4].low) },
                                  set: { s, v in var c = s.euclideousEmitterCCsResolved; c[o * 4].low = max(0, min(127, Int(v.rounded()))); s.euclideousEmitterCCs = c }))
    }
    return p
}

/// The parameters sorted by NAME — the order the host shows them in its flat alphabetical list (used by a test to prove the naming blocks cleanly).
func fourfoldParamsAlphabetical() -> [FourfoldParamDef] { fourfoldParams().sorted { $0.name < $1.name } }
