//  PolyRiff.swift
//  POLY RIFF ferry (2026-10-29): the riff panel's POLY mode — a 16-column grid whose notes have a LENGTH (stretched across columns) and may stack in a column / overlap in time — and the pure functions behind it.
//  Foundation only, on purpose (the macOS test target compiles this file directly). MONO is untouched: nothing here is read unless `PluginState.riffPoly` is on.
//
//  The model. A POLY riff is a list of notes {column 0…15, rank 1…8, length 1…16 steps}. A note STARTS on its column; the walk reads a column exactly as MONO does (the one ordinal → column pair,
//  `euclideousRiffColumn(columns: 16)`), and every note starting on the column it reads strikes on that hit. A note's LENGTH is counted in WALK STEPS of the lane that plays it: it rings for `L` steps
//  (ADVANCE EVERY hits, or ticks under ADV STEP), whatever the direction or stride — Paul's decision. Two notes never overlap at one rank (they would be one pitch): normalisation clips the earlier one.
//  The render thread sees only `PolyRiffSnap` (fixed-size flat arrays, only ever READ there).

import Foundation

enum EuclideousPolyMetrics {
    static let columns = 16, ranks = 8, maxLength = 16
}

// MARK: - the document model

struct EuclideousPolyNote: Codable, Equatable {
    var col: Int
    var rank: Int
    var len: Int
    init(col: Int, rank: Int, len: Int = 1) { self.col = col; self.rank = rank; self.len = len }

    private enum Keys: String, CodingKey { case col, rank, len }
    /// Lenient: a missing or mistyped member decodes as an invalid value that normalisation drops, so one bad note never costs the whole document.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
        col = (try? c.decodeIfPresent(Int.self, forKey: .col)) ?? -1
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? 0
        len = (try? c.decodeIfPresent(Int.self, forKey: .len)) ?? 1
    }
}

struct EuclideousPolyRiff: Codable, Equatable {
    var notes: [EuclideousPolyNote] = []
    init(notes: [EuclideousPolyNote] = []) { self.notes = notes }

    private enum Keys: String, CodingKey { case notes }
    private struct Lossy: Decodable {
        let note: EuclideousPolyNote?
        init(from decoder: Decoder) throws { note = try? EuclideousPolyNote(from: decoder) }
    }
    /// Lenient all the way up: anything that is not an object with a `notes` list (an array, a number, a string) reads as an empty riff — it never fails the whole document.
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.container(keyedBy: Keys.self) else { return }
        notes = ((try? c.decodeIfPresent([Lossy].self, forKey: .notes)) ?? nil)?.compactMap { $0.note } ?? []
    }

    /// Every note in range, sorted by (column, rank), one note per (column, rank) (the longest wins), and no note running into the next one at its rank: the earlier note is clipped where the next starts, and no note runs off column 15.
    var normalized: EuclideousPolyRiff {
        typealias M = EuclideousPolyMetrics
        var best: [Int: Int] = [:]                                   // col * 8 + (rank − 1) → longest length
        for n in notes where n.col >= 0 && n.col < M.columns && n.rank >= 1 && n.rank <= M.ranks {
            let key = n.col * M.ranks + (n.rank - 1)
            best[key] = max(best[key] ?? 0, max(1, min(M.maxLength, n.len)))
        }
        var out: [EuclideousPolyNote] = []
        for r in 1...M.ranks {
            let cols = (0..<M.columns).filter { best[$0 * M.ranks + (r - 1)] != nil }
            for (i, c) in cols.enumerated() {
                var len = best[c * M.ranks + (r - 1)] ?? 1
                len = min(len, M.columns - c)
                if i + 1 < cols.count { len = min(len, cols[i + 1] - c) }
                out.append(EuclideousPolyNote(col: c, rank: r, len: max(1, len)))
            }
        }
        out.sort { ($0.col, $0.rank) < ($1.col, $1.rank) }
        return EuclideousPolyRiff(notes: out)
    }

    func note(startingAt col: Int, rank: Int) -> EuclideousPolyNote? { notes.first { $0.col == col && $0.rank == rank } }
    /// The note whose span includes `col` at `rank` (its head or a tail cell).
    func note(covering col: Int, rank: Int) -> EuclideousPolyNote? { notes.first { $0.rank == rank && col >= $0.col && col < $0.col + max(1, $0.len) } }
    var isEmpty: Bool { notes.isEmpty }

    /// First use of POLY: the MONO riff's eight columns as length-1 notes, twice over (columns 1–8 and 9–16). A lane's LEN defaults to the grid's width (16), so the doubled figure plays the MONO stream for FWD / REV and for any explicit LEN of 8 or less. PENDULUM and PING-PONG with the default LEN walk 16 columns, not 8 — a different (valid) melody, so those lanes change sound on the first switch (adversarial review 2026-10-29).
    static func seeded(from mono: EuclideousRiff) -> EuclideousPolyRiff {
        let r = mono.ranksResolved
        var notes: [EuclideousPolyNote] = []
        for rep in 0..<2 {
            for c in 0..<8 {
                let rank = c < r.count ? r[c] : 0
                if rank >= 1 && rank <= EuclideousPolyMetrics.ranks { notes.append(EuclideousPolyNote(col: rep * 8 + c, rank: rank, len: 1)) }
            }
        }
        return EuclideousPolyRiff(notes: notes).normalized
    }
}

// MARK: - the render thread's copy

/// Fixed-size flat arrays (16 start masks, 128 lengths), only ever READ on the render thread. `on` false ⇒ the Router takes its MONO path and never looks at the rest.
struct PolyRiffSnap: Equatable {
    var on: Bool = false
    /// bit (rank − 1) of `starts[col]` = a note starts on `col` at `rank`.
    var starts: [UInt8] = [UInt8](repeating: 0, count: EuclideousPolyMetrics.columns)
    /// `lengths[col * 8 + rank − 1]` = that note's length in walk steps (0 = none).
    var lengths: [UInt8] = [UInt8](repeating: 0, count: EuclideousPolyMetrics.columns * EuclideousPolyMetrics.ranks)
    /// The same notes seen from their LAST column: bit (rank − 1) of `ends[col]` = a note ENDS on `col` at `rank`, and `endLengths[col * 8 + rank − 1]` is its length. A walk heading toward lower columns (REV) meets a held note at this end
    /// and treats it as the note's start (it then rings the same number of steps).
    var ends: [UInt8] = [UInt8](repeating: 0, count: EuclideousPolyMetrics.columns)
    var endLengths: [UInt8] = [UInt8](repeating: 0, count: EuclideousPolyMetrics.columns * EuclideousPolyMetrics.ranks)
    init() {}
    init(_ riff: EuclideousPolyRiff, on: Bool) {
        self.on = on
        for n in riff.normalized.notes {
            starts[n.col] |= UInt8(1) << UInt8(n.rank - 1)
            lengths[n.col * EuclideousPolyMetrics.ranks + (n.rank - 1)] = UInt8(n.len)
            let last = n.col + n.len - 1
            ends[last] |= UInt8(1) << UInt8(n.rank - 1)
            endLengths[last * EuclideousPolyMetrics.ranks + (n.rank - 1)] = UInt8(n.len)
        }
    }
    @inline(__always) func startMask(_ col: Int) -> UInt8 { col >= 0 && col < starts.count ? starts[col] : 0 }
    @inline(__always) func length(col: Int, rank: Int) -> Int {
        let i = col * EuclideousPolyMetrics.ranks + (rank - 1)
        return col >= 0 && rank >= 1 && rank <= EuclideousPolyMetrics.ranks && i < lengths.count ? Int(lengths[i]) : 0
    }
    /// The highest rank starting on `col` (0 = none): the "representative" rank a column shows where one rank must stand for it (a rest test, an arrow seat, a count).
    @inline(__always) func topRank(_ col: Int) -> Int {
        let m = startMask(col)
        return m == 0 ? 0 : 8 - m.leadingZeroBitCount
    }
    /// The notes a hit on `col` STRIKES under `mode` (`euclideousPolyTrigger`): those starting there, those ending there, or both. One family of calls decides the mask, the length and the top rank, so the engine and every picture of it
    /// read the same thing.
    @inline(__always) func triggerMask(_ col: Int, _ mode: EuclideousPolyTrigger) -> UInt8 {
        guard col >= 0 && col < starts.count else { return 0 }
        switch mode {
        case .starts: return starts[col]
        case .ends:   return ends[col]
        case .both:   return starts[col] | ends[col]
        }
    }
    /// A note's length from the table that holds it: the starting note's where one starts on `col` at `rank` (a note that is both starting and ending there is one note of length 1), else the ending note's.
    @inline(__always) func triggerLength(col: Int, rank: Int, _ mode: EuclideousPolyTrigger) -> Int {
        guard col >= 0, col < starts.count, rank >= 1, rank <= EuclideousPolyMetrics.ranks else { return 0 }
        let i = col * EuclideousPolyMetrics.ranks + (rank - 1)
        if mode != .ends, starts[col] & (UInt8(1) << UInt8(rank - 1)) != 0 { return Int(lengths[i]) }
        if mode != .starts, ends[col] & (UInt8(1) << UInt8(rank - 1)) != 0 { return Int(endLengths[i]) }
        return 0
    }
    @inline(__always) func topTriggerRank(_ col: Int, _ mode: EuclideousPolyTrigger) -> Int {
        let m = triggerMask(col, mode)
        return m == 0 ? 0 : 8 - m.leadingZeroBitCount
    }
    /// The highest rank of ANY note starting or ending on `col` — "is there a note here at all" for a picture that does not know which way a hit is walking.
    @inline(__always) func topAnyRank(_ col: Int) -> Int { topTriggerRank(col, .both) }
    /// What a hit on `col` strikes, lowest rank first (the order the Router strikes them in) — for the pictures (the strip, the roll); the Router walks the mask itself.
    func triggerNotes(_ col: Int, _ mode: EuclideousPolyTrigger) -> [(rank: Int, len: Int)] {
        let m = triggerMask(col, mode)
        var out: [(rank: Int, len: Int)] = []
        for r in 1...EuclideousPolyMetrics.ranks where m & (UInt8(1) << UInt8(r - 1)) != 0 { out.append((rank: r, len: triggerLength(col: col, rank: r, mode))) }
        return out
    }
    /// The same ranks, highest first (a chip or an arrow each).
    func triggerRanks(_ col: Int, _ mode: EuclideousPolyTrigger) -> [Int] { triggerNotes(col, mode).map { $0.rank }.sorted(by: >) }
}

/// Which end of a held note a hit MEETS (2026-10-30). A POLY walk that moves toward HIGHER columns meets a note at its first column (that is where it strikes); one that moves toward LOWER columns meets it at its LAST column — the end is
/// treated as the start, and the note rings the same number of walk steps, so a note held from column 2 to 15 sounds the same walked either way. A hit that ARRIVES one way and LEAVES the other (the turn of a PENDULUM) meets both
/// ends. FWD is always `.starts` and REV always `.ends`; PENDULUM and PING-PONG decide per hit, from the walk positions either side of it (before SHIFT, as the arrow's heading does), so the answer is a pure function of the hit's ordinal:
/// moving right on arrival or on departure meets starts, moving left meets ends, and a repeated position (PING-PONG's doubled end step) counts only the move it does make — its first visit arrives, its second leaves.
enum EuclideousPolyTrigger: Equatable { case starts, ends, both }
func euclideousPolyTrigger(riffDir: RiffDir, length: Int, stride: Int, every: Int, ordinal: Int64) -> EuclideousPolyTrigger {
    switch riffDir {
    case .forward, .random, .drunk: return .starts
    case .reverse: return .ends
    case .pendulum, .pingpong:
        let len = max(1, length), st = max(1, stride)
        let w = Int(euclideousRiffWalkStep(ordinal: ordinal, every: max(1, every)))
        func pos(_ k: Int) -> Int { riffStepAt(riffDir, raw: k * st, steps: len, seed: 0) }
        let p = pos(w), before = pos(w - 1), after = pos(w + 1)
        let right = p > before || after > p, left = p < before || after < p
        return right && left ? .both : (left ? .ends : .starts)
    }
}
@inline(__always) func euclideousPolyTrigger(cfg c: EuclideousWalkLaneConfig, ordinal: Int64) -> EuclideousPolyTrigger {
    euclideousPolyTrigger(riffDir: c.riffDir, length: c.length, stride: c.stride, every: c.every, ordinal: ordinal)
}

/// The arrows a lane's current hit draws in POLY: its walk-plan seat (on the highest note the hit strikes) and one more for every other note the hit strikes — a chord shows an arrow on each of its notes. `seat.ordinal` is the
/// hit the arrow shows, which decides the end(s) the hit meets.
func euclideousPolyArrowSeats(_ seat: EuclideousLaneArrowState, poly: PolyRiffSnap, cfg: EuclideousWalkLaneConfig) -> [EuclideousLaneArrowState] {
    euclideousLaneArrowStates(seat, strikingRanks: poly.triggerRanks(seat.column, euclideousPolyTrigger(cfg: cfg, ordinal: seat.ordinal)))
}

// MARK: - the document fields

extension PluginState {
    /// POLY is on only when asked for; the default (nil) is MONO, exactly as before.
    var riffPolyResolved: Bool { riffPoly ?? false }
    var polyRiffResolved: EuclideousPolyRiff { (polyRiff ?? EuclideousPolyRiff()).normalized }
    var polyRiffSnapResolved: PolyRiffSnap { PolyRiffSnap(polyRiffResolved, on: riffPolyResolved) }

    /// POLY RIFF ferry: the four riff boxes are gone, so MONO is ONE riff — the one that was ACTIVE (it is what played). It becomes slot 0 and the others are dropped; sound is unchanged for every existing session.
    /// Idempotent; run wherever a document is loaded (a session, a user preset), beside `normalizeLocksAtLoad`.
    mutating func normalizeRiffsAtLoad() {
        let active = max(0, min(3, activeRiff ?? 0))
        if riffs == nil && active == 0 { activeRiff = nil; return }   // the legacy singular riff already is slot 0
        let chosen = riffsResolved[active]
        riffs = [chosen]
        activeRiff = nil
    }
}

// MARK: - the ring length of a stretched note

/// How many lane hits AHEAD a note of `len` steps still rings, counted from the hit it strikes on, under ADV HIT: `(len − 1) × every` — a length-1 note is exactly MONO's (0 more hits). Every strike of a step (EVERY > 1 strikes the same
/// column on each of its hits) rings that long from ITS hit.
@inline(__always) func euclideousPolyHitsAhead(len: Int, every: Int) -> Int { max(0, len - 1) * max(1, every) }

/// The times, in beats from THIS hit, of the lane's next hits ahead (`times[k − 1]` = the k-th following hit), up to `maxHits` of them — ONE scan serves every note of a hit, whatever their lengths. Every future tick is asked of
/// `euclideousLaneChainTick`, the call the TIE lookahead makes, so each hit's own rhythm / melody origins and its timing delay are honoured. The scan stops at a melody restart hit (`restartIndex` = that hit's 1-based index, else 0: the walk
/// starts over there) or at the tick cap. The cap is generous because a rhythm-restart chain can cut passes short and leave few hits per lap: `cycleLen × (maxHits + 1) × 8 + 256` ticks. Allocation-free (`times` is the caller's scratch).
func euclideousPolyHitTimes(maxHits: Int, times: inout [Double], buf: [Bool], eN: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                            chains: EuclideousLaneRestartChains, legacySpanBeats: Double, timing: EuclideousHitTiming = .none) -> (found: Int, restartIndex: Int) {
    guard maxHits > 0, times.count >= maxHits else { return (0, 0) }
    let dThis = timing.isNone ? 0 : timing.delaySteps(raw: euclideousLaneChainPhase(buf: buf, n: eN, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                                                                    legacySpanBeats: legacySpanBeats).raw)
    let cap = max(1, cycleLen) * (maxHits + 1) * 8 + 256
    var hits = 0, j = 0, restart = 0
    while j < cap && hits < maxHits {
        j += 1
        let info = euclideousLaneChainTick(buf: buf, n: eN, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick + Int64(j), chains: chains, legacySpanBeats: legacySpanBeats, advanceStep: false)
        guard info.rawIsHit else { continue }
        let dJ = timing.isNone ? 0 : timing.delaySteps(raw: info.raw)
        times[hits] = (Double(j) + (timing.isNone ? 0 : dJ - dThis)) * sub
        hits += 1
        if !chains.melody.isFree, info.advOrd == 0 { restart = hits; break }
    }
    return (hits, restart)
}
/// One poly note's length in beats under ADV HIT, from `euclideousPolyHitTimes`: the time from this hit to the `n`-th hit after it in full, plus GATE × the gap that follows that hit — the TIE rule's shape; with `n == 0` it is exactly
/// MONO's `gate × gap to the next hit`. A melody restart on or before the note's last hit ends the note AT that hit; a restart that is merely the hit AFTER it is just the end of its final gate-scaled gap. A scan that ran out of hits
/// (a pattern with too few) rings to the last hit it found, then GATE × the next gap.
func euclideousPolyRingFromTimes(hitsAhead n: Int, gate: Double, nextHitGapBeats: Double, minGateBeats: Double, times: [Double], found: Int, restartIndex: Int) -> Double {
    guard n > 0 else { return max(minGateBeats, gate * nextHitGapBeats) }
    if restartIndex > 0 && restartIndex <= n && restartIndex <= times.count { return max(minGateBeats, times[restartIndex - 1]) }
    if found > n && n < times.count { return max(minGateBeats, times[n - 1] + gate * (times[n] - times[n - 1])) }
    let last = found > 0 && found <= times.count ? times[found - 1] : 0
    return max(minGateBeats, last + gate * nextHitGapBeats)
}
/// The one-note form (the LANES roll draws each bar through it; the Router scans once per hit instead and calls `euclideousPolyRingFromTimes` — the same arithmetic).
func euclideousPolyRingBeats(hitsAhead n: Int, gate: Double, nextHitGapBeats: Double, minGateBeats: Double,
                             buf: [Bool], eN: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                             chains: EuclideousLaneRestartChains, legacySpanBeats: Double, timing: EuclideousHitTiming = .none) -> Double {
    guard n > 0 else { return max(minGateBeats, gate * nextHitGapBeats) }
    var times = [Double](repeating: 0, count: n + 1)
    let r = euclideousPolyHitTimes(maxHits: n + 1, times: &times, buf: buf, eN: eN, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains, legacySpanBeats: legacySpanBeats, timing: timing)
    return euclideousPolyRingFromTimes(hitsAhead: n, gate: gate, nextHitGapBeats: nextHitGapBeats, minGateBeats: minGateBeats, times: times, found: r.found, restartIndex: r.restartIndex)
}

/// What the ADV STEP ring needs to find a melody restart: the lane's pattern and chains (under ADV STEP the walk counts every tick, so a restart is any tick whose ordinal is 0).
struct EuclideousPolyStepRestartScan {
    var buf: [Bool], eN: Int, dir: EuclidDir, cycleLen: Int, tick: Int64, chains: EuclideousLaneRestartChains, legacySpanBeats: Double
}
/// Under ADV STEP the walk counts lane steps (ticks), so a note's extra length is plain time: `(len − 1) × every` steps, then GATE × the gap to the next hit — a length-1 note again exactly MONO's. A melody restart inside that span
/// ends the note at the restart tick (`scan`, nil = no chain to look at).
func euclideousPolyRingBeatsStep(len: Int, every: Int, gate: Double, nextHitGapBeats: Double, sub: Double, minGateBeats: Double, scan: EuclideousPolyStepRestartScan? = nil) -> Double {
    let plain = max(minGateBeats, Double(max(0, len - 1) * max(1, every)) * sub + gate * nextHitGapBeats)
    guard len > 1, sub > 0, let sc = scan, !sc.chains.melody.isFree else { return plain }
    let limit = Int(plain / sub) + 2
    var j = 1
    while j <= limit {
        let info = euclideousLaneChainTick(buf: sc.buf, n: sc.eN, dir: sc.dir, cycleLen: sc.cycleLen, sub: sub, tick: sc.tick + Int64(j), chains: sc.chains, legacySpanBeats: sc.legacySpanBeats, advanceStep: true)
        if info.advOrd == 0 { return max(minGateBeats, min(plain, Double(j) * sub)) }
        j += 1
    }
    return plain
}
