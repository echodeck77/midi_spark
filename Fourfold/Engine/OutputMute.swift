//  OutputMute.swift — the MUTE tab's per-OUTPUT mute (ferry "LANES → MUTE: each block is an emitter", 2026-11-02).
//
//  The bottom-right panel's MUTE tab (renamed from LANES) shows four blocks, one per OUTPUT A–D. Each block is a
//  16-cell grid (bit i set = cell i SOUNDS, cleared = that cell is muted) with a cell size in whole PASSES (1…8,
//  the bounded ◀ / ▶ ladder, default 1). The gate is at EMISSION: a note never starts on an output whose own mute
//  grid is clear at that beat (Router.emitOneOutput) — so it silences everything routed to that output, even notes
//  coming from another lane. This replaces the per-lane mute (`EuclidLine.muteCells16`/`muteUnit`), which is lane 1
//  ↔ output A by default; an output's grid ticks on its HOME lane's pass (A↔lane 1 … D↔lane 4), the only reading
//  under which "1 pass" is unambiguous.
//
//  Foundation-only, like `EmitterRatchetUI.swift` / `CardBack.swift`: the model + its pure maths live here, the
//  painter and the page only read them. Additive-Optional and decode-tolerant: nil, short, long or unreadable ⇒
//  four outputs at the defaults (every cell sounds, 1 pass), so an old session and every factory preset behave
//  exactly as before.

import Foundation

/// One output's MUTE grid: a 16-cell pattern and the cell size as a host-relative UNIT (1/16 · 1/8 · 1/4 · BAR).
struct EuclideousOutputMute: Equatable {
    var cells16: UInt16 = 0xFFFF   // bit i set = cell i SOUNDS; cleared = muted
    var passes: UInt8 = 1          // RETIRED (MUTE TAB EMITTER ROLL ferry 2026-11-09): the old ◀/▶ pass-span ladder; kept decodable+round-tripping, no longer read by the engine or the (new) UI — `muteUnit` replaces it
    var muteUnit: UInt8 = 0         // §1.2: cell size, 0 = 1/16 · 1 = 1/8 · 2 = 1/4 · 3 = BAR (default 1/16). A host-relative musical unit, not the home lane's pass — so every row at a given unit sweeps at the SAME speed

    static let minPasses: UInt8 = 1, maxPasses: UInt8 = 8
    static let unitCount: UInt8 = 4
    var isDefault: Bool { self == EuclideousOutputMute() }
    /// Clamp PASSES to 1…8 and the UNIT to 0…3; the cell mask is already a full 16 bits, nothing to clamp there.
    func normalized() -> EuclideousOutputMute {
        var m = self
        m.passes = max(Self.minPasses, min(Self.maxPasses, passes))
        if m.muteUnit >= Self.unitCount { m.muteUnit = 0 }   // an unknown stored unit (a future value) reads as 1/16
        return m
    }
    /// §5.1: one tap of the unit tile — cycle 1/16 → 1/8 → 1/4 → BAR → 1/16, returning a new value.
    func cyclingUnit() -> EuclideousOutputMute { var m = self; m.muteUnit = (muteUnit &+ 1) % Self.unitCount; return m }
    /// The ◀ / ▶ bounds (no wrap): ◀ is disabled at 1 pass, ▶ at 8.
    var canDec: Bool { passes > Self.minPasses }
    var canInc: Bool { passes < Self.maxPasses }
    /// Does cell `i` sound? (bit set). An out-of-range cell "sounds" so a bad index never silences.
    func sounds(_ i: Int) -> Bool { i < 0 || i >= 16 || (cells16 >> UInt16(i)) & 1 != 0 }
    /// One cell set/cleared (sounds / muted), returning a new value.
    func settingCell(_ i: Int, sounds: Bool) -> EuclideousOutputMute {
        guard i >= 0, i < 16 else { return self }
        var m = self
        let bit = UInt16(1) << UInt16(i)
        m.cells16 = sounds ? (cells16 | bit) : (cells16 & ~bit)
        return m
    }
    /// One ◀ / ▶ step of the pass ladder, bounded to 1…8.
    func steppingPasses(up: Bool) -> EuclideousOutputMute {
        var m = self
        m.passes = up ? min(Self.maxPasses, passes &+ 1) : max(Self.minPasses, passes &- 1)
        return m
    }
    /// This output has at least one muted cell (the Router's gate is skipped when no output does — byte-identical).
    var hasMute: Bool { cells16 != 0xFFFF }
    /// EMITTER TOKEN ferry §5.1: a MIX-emitter tap full-toggles the output — fully sounding (0xFFFF) ↔ fully muted (0x0000), leaving PASSES as it is. A partial MUTE-tab pattern reads as muted (`hasMute`) and a tap clears it to fully sounding.
    func toggledFull() -> EuclideousOutputMute { var m = self; m.cells16 = euclideousOutputMuteFullToggle(cells16); return m }
}

/// §5.1 (pure, testable): fully sounding ⇄ fully muted. Anything not already fully sounding (partial OR fully muted) unmutes to fully sounding.
func euclideousOutputMuteFullToggle(_ cells16: UInt16) -> UInt16 { cells16 == 0xFFFF ? 0x0000 : 0xFFFF }
extension EuclideousOutputMute: Codable {
    enum CodingKeys: String, CodingKey { case cells16, passes, muteUnit }
    /// Never throws on content: an unreadable key keeps its default, PASSES and the UNIT clamp. A pre-feature document has no
    /// `muteUnit` key → it loads at 1/16 (§1.3), keeping its `cells16` pattern (the old pass-span is dropped — `passes` round-trips but is inert).
    init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        if let v = (try? c.decodeIfPresent(UInt16.self, forKey: .cells16)) ?? nil { cells16 = v }
        if let v = (try? c.decodeIfPresent(UInt8.self, forKey: .passes)) ?? nil { passes = v }
        if let v = (try? c.decodeIfPresent(UInt8.self, forKey: .muteUnit)) ?? nil { muteUnit = v }
        self = normalized()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cells16, forKey: .cells16); try c.encode(passes, forKey: .passes); try c.encode(muteUnit, forKey: .muteUnit)
    }
}

/// The document's four output mutes: FIXED-SIZE storage (four named members and a subscript — no array to allocate
/// or share on the render path), encoded as a plain array of four. Every write through the subscript is normalised.
struct EuclideousOutputMutes: Equatable, Codable {
    static let count = 4
    private var m0 = EuclideousOutputMute(), m1 = EuclideousOutputMute(), m2 = EuclideousOutputMute(), m3 = EuclideousOutputMute()
    init() {}
    init(_ list: [EuclideousOutputMute]) { for (i, m) in list.prefix(Self.count).enumerated() { self[i] = m } }
    /// A stored value that isn't an array of mutes at all decodes to the defaults, never to a failed document load;
    /// a short array leaves the rest at their defaults, a long one drops the extras.
    init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.singleValueContainer(), let raw = try? c.decode([EuclideousOutputMute].self) else { return }
        for (i, m) in raw.prefix(Self.count).enumerated() { self[i] = m }
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(asArray)
    }
    subscript(i: Int) -> EuclideousOutputMute {
        get { switch i { case 0: return m0; case 1: return m1; case 2: return m2; default: return m3 } }
        set { let n = newValue.normalized(); switch i { case 0: m0 = n; case 1: m1 = n; case 2: m2 = n; default: m3 = n } }
    }
    var asArray: [EuclideousOutputMute] { [m0, m1, m2, m3] }
    /// Nothing has been touched: the same as no stored value at all (undo restores nil for it).
    var isAllDefault: Bool { self == EuclideousOutputMutes() }
    /// Any output has a muted cell — the Router's whole output-mute gate is skipped otherwise, bit for bit.
    var anyMuted: Bool { m0.hasMute || m1.hasMute || m2.hasMute || m3.hasMute }
}

// MARK: - Labels (the block is an OUTPUT now, not a lane)

/// The letter shown on an output's MUTE block and in its VoiceOver (output 0…3 = A…D).
func euclideousOutputLetter(_ output: Int) -> String {
    let letters = ["A", "B", "C", "D"]
    return output >= 0 && output < letters.count ? letters[output] : "?"
}
/// The pass-count readout on the rail, e.g. "1 PASS" … "8 PASS" — how many passes the 16 cells span (lowest = 1). RETIRED (the ◀/▶ rail is gone); kept for the unmounted old panel.
func euclideousOutputMutePassLabel(_ passes: Int) -> String { "\(passes) PASS" }
/// §1.2 — the cell size in BEATS (the engine's quarter-note unit) for a mute unit 0…3. A sixteenth = ¼ beat, an eighth = ½, a quarter = 1, BAR = the host's beats-per-bar. A 16-cell window spans 16× this.
func euclideousMuteUnitBeats(_ unit: UInt8, beatsPerBar: Double) -> Double {
    switch unit {
    case 1: return 0.5                      // 1/8
    case 2: return 1.0                      // 1/4
    case 3: return max(1e-9, beatsPerBar)   // BAR
    default: return 0.25                    // 1/16
    }
}
/// §5.1 — the cell-size label shown on the row's tile ("1/16" · "1/8" · "1/4" · "BAR").
func euclideousMuteUnitLabel(_ unit: UInt8) -> String {
    switch unit { case 1: return "1/8"; case 2: return "1/4"; case 3: return "BAR"; default: return "1/16" }
}
/// §7 — VoiceOver for the unit tile: which output and its current cell size (a button that cycles the size).
func euclideousOutputMuteUnitTileLabel(output: Int, unit: UInt8) -> String {
    "Output \(euclideousOutputLetter(output)) cell size \(euclideousMuteUnitLabel(unit))"
}
/// VoiceOver for one MUTE cell.
func euclideousOutputMuteCellLabel(output: Int, cell: Int, sounding: Bool) -> String {
    "Output \(euclideousOutputLetter(output)) cell \(cell + 1), \(sounding ? "sounding" : "muted")"
}
/// VoiceOver for the ◀ / ▶ rail — how many passes the output's 16-cell grid spans.
func euclideousOutputMuteRailLabel(output: Int, passes: Int) -> String {
    "Output \(euclideousOutputLetter(output)) showing \(passes) pass\(passes == 1 ? "" : "es")"
}
/// MUTE ZOOM (2026-11-03): VoiceOver for one unlabelled zoom arrow (◀ in / ▶ out) — on screen it is only an arrow, so this says which output,
/// which direction and the span it currently spans. (The bounds are spoken by the button's own disabled state.)
func euclideousOutputZoomLabel(output: Int, passes: Int, zoomIn: Bool) -> String {
    "Output \(euclideousOutputLetter(output)) zoom \(zoomIn ? "in" : "out"), showing \(passes) pass\(passes == 1 ? "" : "es")"
}

// MARK: - The old per-lane mute is NOT migrated
//
// MUTE TAB ferry (2026-11-02): Paul's clarification made the 16 cells DIVIDE a 1…8-PASS window (the ◀/▶ sets how many
// passes the roll/grid spans, NOT the cell size). The old per-lane mute (`EuclidLine.muteCells16`/`muteUnit`) is a
// different concept (it silences a LANE wherever it routes) on windows up to 32 passes, which the new 1…8-pass model
// cannot represent faithfully — so there is deliberately NO migration. An old session's per-lane mute keeps SOUNDING
// (the per-lane strike gate stays live in the Router), it is just not shown or editable in the new per-output MUTE tab;
// the user re-sets it there. See `Docs/euclideous-device-verification-debt.md`.
