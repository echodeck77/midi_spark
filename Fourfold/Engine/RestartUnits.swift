//  RestartUnits.swift — RESTART UNITS ferry (2026-11-04): the per-chain UNIT / SOURCE / ON switch and the melody's WITH RHYTHM link, as stored on a lane and as resolved for the engine (Foundation only).
//
//  A lane still has two chains — `restartRhythmBars` (RHYTHM) and `restartMelodyPasses` (MELODY) — each a list of up to four links. Their names stay; the links now count in the chain's UNIT (a comment on the
//  fields says so). RHYTHM counts BAR | PASS (another lane's passes) | RIFF (riff completions of any lane, its own by default); MELODY counts PASS (any lane's, its own by default) | BAR | HIT (its own lane's hits).
//  A chain is ACTIVE when its switch is on AND it holds a link; an inactive chain behaves as FREE and keeps its links. Every field is additive-Optional: nil resolves to what the engine always did, so a document
//  that never had them plays exactly as before.

import Foundation

enum EuclideousRhythmRestartUnit: String, Codable, CaseIterable {
    case bar = "BAR", pass = "PASS", riff = "RIFF"
    /// Does this unit count another lane's events (§2.3)? BAR does not.
    var readsSource: Bool { self != .bar }
    /// "bar", "pass", "riff" — the singular the tiles and VoiceOver use.
    var word: String { rawValue.lowercased() }
}
enum EuclideousMelodyRestartUnit: String, Codable, CaseIterable {
    case pass = "PASS", bar = "BAR", hit = "HIT"
    var readsSource: Bool { self == .pass }
    var word: String { rawValue.lowercased() }
}

/// §2.2: the values a link may take — 1, 2, 3, 4, 6, 8 for BAR / PASS / RIFF; 1…8 for HIT.
func euclideousRestartLinkIsValid(_ v: UInt8, hit: Bool) -> Bool { hit ? (1...8).contains(Int(v)) : [1, 2, 3, 4, 6, 8].contains(Int(v)) }
/// The link ladder a tap steps through (§7.4): the valid values in order.
func euclideousRestartLinkLadder(hit: Bool) -> [UInt8] { hit ? [1, 2, 3, 4, 5, 6, 7, 8] : [1, 2, 3, 4, 6, 8] }
/// §3.3: the links a stored array keeps for a unit — the valid ones, at most the first four.
func euclideousRestartValidLinks(_ raw: [UInt8], hit: Bool) -> [UInt8] {
    var out: [UInt8] = []
    for v in raw where euclideousRestartLinkIsValid(v, hit: hit) { if out.count < 4 { out.append(v) } }
    return out
}

extension EuclideousRestartChain {
    /// A chain from a stored link array for a unit: HIT keeps 1…8 (so 5 and 7), every other unit {1,2,3,4,6,8}; at most four links.
    static func from(_ raw: [UInt8], hit: Bool) -> EuclideousRestartChain {
        var p: UInt32 = 0; var i = 0
        for v in raw where euclideousRestartLinkIsValid(v, hit: hit) {
            guard i < 4 else { break }
            p |= UInt32(v) << UInt32(8 * i); i += 1
        }
        return EuclideousRestartChain(packed: p)
    }
}

/// A lane's two chains as resolved (§3.1) — fixed-size value data (the packed chains are one UInt32 each), safe to build on the render thread.
struct EuclideousRestartSettings: Equatable {
    /// The links as stored (validated for the unit), whether or not the chain is on.
    var rhythm: EuclideousRestartChain = .free
    var rhythmUnit: EuclideousRhythmRestartUnit = .bar
    /// The lane the unit counts (0…3): meaningful only where `rhythmUnit.readsSource`; kept (and ignored) otherwise.
    var rhythmSource: Int = 0
    var rhythmOn = false
    var melody: EuclideousRestartChain = .free
    var melodyUnit: EuclideousMelodyRestartUnit = .pass
    var melodySource: Int = 0
    var melodyOn = false
    var withRhythm = false
    /// §2.4: a chain is active when it is on and holds at least one link.
    var rhythmActive: Bool { rhythmOn && !rhythm.isFree }
    var melodyActive: Bool { melodyOn && !melody.isFree }
    /// Does anything here restart anything? (Inactive chains and no WITH RHYTHM ⇒ the lane behaves as FREE / FREE.)
    var anyActive: Bool { rhythmActive || melodyActive || withRhythm }
    /// Can the closed-form reference functions express this? (RHYTHM BAR; MELODY PASS of the lane itself; no WITH RHYTHM.) Anything else needs the schedule.
    func isClosedFormExpressible(ownLane: Int) -> Bool {
        (!rhythmActive || rhythmUnit == .bar) && (!melodyActive || (melodyUnit == .pass && melodySource == ownLane)) && !withRhythm
    }
    static let off = EuclideousRestartSettings()
}

extension EuclidLine {
    var restartRhythmUnitResolved: EuclideousRhythmRestartUnit { restartRhythmUnit ?? .bar }
    var restartMelodyUnitResolved: EuclideousMelodyRestartUnit { restartMelodyUnit ?? .pass }
    /// §3.1: nil → the lane itself; a stored own-lane source on RHYTHM PASS resolves to the next lane (lane 4 wraps to lane 1) — a restart on its own pass changes nothing.
    func restartRhythmSourceResolved(ownLane: Int) -> Int {
        let own = max(0, min(3, ownLane))
        let stored = restartRhythmSource.map { max(0, min(3, $0)) } ?? own
        if restartRhythmUnitResolved == .pass && stored == own { return (own + 1) % 4 }
        return stored
    }
    func restartMelodySourceResolved(ownLane: Int) -> Int { restartMelodySource.map { max(0, min(3, $0)) } ?? max(0, min(3, ownLane)) }
    var restartRhythmChainResolved: EuclideousRestartChain { .from(restartRhythmBars ?? [], hit: false) }
    var restartMelodyChainResolved: EuclideousRestartChain { .from(restartMelodyPasses ?? [], hit: restartMelodyUnitResolved == .hit) }
    /// §3.1: nil → on exactly when the chain holds a link (every pre-feature document).
    var restartRhythmOnResolved: Bool { restartRhythmOn ?? !restartRhythmChainResolved.isFree }
    var restartMelodyOnResolved: Bool { restartMelodyOn ?? !restartMelodyChainResolved.isFree }
    var restartMelodyWithRhythmResolved: Bool { restartMelodyWithRhythm ?? false }
}

/// The ONE resolver: a lane's restart settings from its stored fields (`lane` is its index — the default source and RHYTHM PASS's "never itself").
func euclideousRestartSettings(line l: EuclidLine, lane: Int) -> EuclideousRestartSettings {
    EuclideousRestartSettings(rhythm: l.restartRhythmChainResolved, rhythmUnit: l.restartRhythmUnitResolved, rhythmSource: l.restartRhythmSourceResolved(ownLane: lane), rhythmOn: l.restartRhythmOnResolved,
                              melody: l.restartMelodyChainResolved, melodyUnit: l.restartMelodyUnitResolved, melodySource: l.restartMelodySourceResolved(ownLane: lane), melodyOn: l.restartMelodyOnResolved,
                              withRhythm: l.restartMelodyWithRhythmResolved)
}

/// The closed-form reference chains for a line — what every site that used to write `.from(line.restartRhythmBars ?? [])` now calls. A lane whose chains were never pinned is `.off`, as before. A chain the closed forms cannot
/// express (a RHYTHM unit other than BAR, a MELODY unit other than PASS or counting another lane, WITH RHYTHM) is `.free` here — the schedule is what reads those; this is the reference path and the fallback.
func euclideousLaneRestartChains(line: EuclidLine, lane: Int, barBeats: Double, lapBeats: Double) -> EuclideousLaneRestartChains {
    guard line.usesRestartChains else { return .off }
    let s = euclideousRestartSettings(line: line, lane: lane)
    return EuclideousLaneRestartChains(rhythm: s.rhythmActive && s.rhythmUnit == .bar ? s.rhythm : .free,
                                       melody: s.melodyActive && s.melodyUnit == .pass && s.melodySource == max(0, min(3, lane)) ? s.melody : .free,
                                       barBeats: barBeats, lapBeats: lapBeats)
}
