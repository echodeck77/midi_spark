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
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: Keys.self)
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

    /// First use of POLY: the MONO riff's eight columns as length-1 notes, twice over (columns 1–8 and 9–16). A lane's LEN defaults to the grid's width, so the doubled figure sounds exactly as the MONO riff did (which wraps at 8).
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
    init() {}
    init(_ riff: EuclideousPolyRiff, on: Bool) {
        self.on = on
        for n in riff.normalized.notes {
            starts[n.col] |= UInt8(1) << UInt8(n.rank - 1)
            lengths[n.col * EuclideousPolyMetrics.ranks + (n.rank - 1)] = UInt8(n.len)
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

/// One poly note's length in beats under ADV HIT: the time from this hit to the `n`-th hit after it in full, plus GATE × the gap that follows that hit — the TIE rule's shape ("the gap up to the tied hit, GATE × the following gap"); with
/// `n == 0` it is exactly MONO's `gate × gap to the next hit`. A melody restart inside the span ends the note AT the restart hit (the walk starts over there). Every hit's own rhythm / restart origins are honoured because each future tick is
/// asked of `euclideousLaneChainTick`, the same call the TIE lookahead makes. Allocation-free; bounded by `cycleLen × (n + 1)` ticks.
func euclideousPolyRingBeats(hitsAhead n: Int, gate: Double, nextHitGapBeats: Double, minGateBeats: Double,
                             buf: [Bool], eN: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                             chains: EuclideousLaneRestartChains, legacySpanBeats: Double, timing: EuclideousHitTiming = .none) -> Double {
    guard n > 0 else { return max(minGateBeats, gate * nextHitGapBeats) }
    let dThis = timing.isNone ? 0 : timing.delaySteps(raw: euclideousLaneChainPhase(buf: buf, n: eN, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                                                                    legacySpanBeats: legacySpanBeats).raw)
    let cap = max(1, cycleLen) * (n + 1)
    var hits = 0, j = 0
    var tN = 0.0                                                    // the time to the n-th hit ahead
    while j < cap {
        j += 1
        let t = tick + Int64(j)
        let info = euclideousLaneChainTick(buf: buf, n: eN, dir: dir, cycleLen: cycleLen, sub: sub, tick: t, chains: chains, legacySpanBeats: legacySpanBeats, advanceStep: false)
        guard info.rawIsHit else { continue }
        let dJ = timing.isNone ? 0 : timing.delaySteps(raw: info.raw)
        let at = (Double(j) + (timing.isNone ? 0 : dJ - dThis)) * sub
        // a melody restart ends the note AT that hit when the restart falls on or before the note's last hit; a restart that is merely the hit AFTER it is just the end of its final, GATE-scaled gap
        if !chains.melody.isFree, info.advOrd == 0, hits + 1 <= n { return max(minGateBeats, at) }
        hits += 1
        if hits == n { tN = at }
        else if hits == n + 1 { return max(minGateBeats, tN + gate * (at - tN)) }
    }
    return max(minGateBeats, tN + gate * nextHitGapBeats)           // a degenerate pattern ran out of hits: the last gap we know
}

/// Under ADV STEP the walk counts lane steps (ticks), so a note's extra length is plain time: `(len − 1) × every` steps, then GATE × the gap to the next hit — a length-1 note again exactly MONO's.
@inline(__always) func euclideousPolyRingBeatsStep(len: Int, every: Int, gate: Double, nextHitGapBeats: Double, sub: Double, minGateBeats: Double) -> Double {
    max(minGateBeats, Double(max(0, len - 1) * max(1, every)) * sub + gate * nextHitGapBeats)
}
