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

/// One output's MUTE grid: a 16-cell pattern and the cell size in whole PASSES (1…8).
struct EuclideousOutputMute: Equatable {
    var cells16: UInt16 = 0xFFFF   // bit i set = cell i SOUNDS; cleared = muted
    var passes: UInt8 = 1          // 1…8 passes per cell (the bounded arrow ladder; default = the lowest, 1 pass)

    static let minPasses: UInt8 = 1, maxPasses: UInt8 = 8
    var isDefault: Bool { self == EuclideousOutputMute() }
    /// Clamp PASSES to 1…8; the cell mask is already a full 16 bits, nothing to clamp there.
    func normalized() -> EuclideousOutputMute {
        var m = self
        m.passes = max(Self.minPasses, min(Self.maxPasses, passes))
        return m
    }
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
}
extension EuclideousOutputMute: Codable {
    enum CodingKeys: String, CodingKey { case cells16, passes }
    /// Never throws on content: an unreadable key keeps its default, PASSES clamps.
    init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        if let v = (try? c.decodeIfPresent(UInt16.self, forKey: .cells16)) ?? nil { cells16 = v }
        if let v = (try? c.decodeIfPresent(UInt8.self, forKey: .passes)) ?? nil { passes = v }
        self = normalized()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(cells16, forKey: .cells16); try c.encode(passes, forKey: .passes)
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
