//  Derivations.swift
//  MidiSpark — the pure, stateless core of the engine (spec v2.8 §3/§4/§7).
//
//  Everything here is a pure function of its inputs (or, for NotePool, a self-contained data
//  structure): no Router state, no CoreAudio, no snapshot. That makes this the regression-prone
//  math the render thread leans on — swing warp, phase indexing, arp pattern selection, processor
//  dispatch — AND the part that is unit-testable off-device (see Tests/DerivationsTests.swift).
//  Foundation only, on purpose: the test target compiles this file directly.

import Foundation

// MARK: - The source pool (§2.5): omni, keyed by note number

/// The live held-note pool. All input channels merge (omni, §2.5) — note number is the key — but
/// each note's originating channel is remembered for INHERIT stamping (§2.6). Fixed capacity, no
/// allocation after init. A class so the Kernel (writer) and Router (reader) share one instance
/// with no copies on the hot path.
final class NotePool {
    private var vel = [UInt8](repeating: 0, count: 128)   // velocity by note (0 = not held)
    private var chan = [UInt8](repeating: 0, count: 128)  // originating channel by note
    private(set) var sorted = [UInt8](repeating: 0, count: 128)
    private(set) var count = 0

    func reset() {
        for i in 0..<128 { vel[i] = 0; chan[i] = 0 }
        count = 0
    }

    func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8) {
        let n = Int(note)
        if velocity > 0 {
            if vel[n] == 0 { count += 1 }
            vel[n] = velocity
            chan[n] = channel
        } else {
            noteOff(note)
        }
    }

    func noteOff(_ note: UInt8) {
        let n = Int(note)
        if vel[n] != 0 { count -= 1 }
        vel[n] = 0
    }

    @inline(__always) func channel(of note: Int) -> UInt8 { chan[note] }

    /// Rebuild the ascending note list; also re-derives `count` (belt-and-braces vs the incremental
    /// count, matching the pre-split behaviour).
    func rebuildSorted() {
        var n = 0
        for note in 0..<128 where vel[note] != 0 { sorted[n] = UInt8(note); n += 1 }
        count = n
    }
}

// MARK: - Swing warp (§4 v2.3): real beat ⇄ musical beat, identity at 50 (a = 1)

@inline(__always)
func musicalOf(_ realBeat: Double, stepBeats S: Double, a: Double) -> Double {
    let pair = 2 * S
    let base = (realBeat / pair).rounded(.down) * pair
    let u = realBeat - base
    let split = a * S
    let m = u < split ? u / a : S + (u - split) / (2 - a)
    return base + m
}

@inline(__always)
func realOf(_ musicalBeat: Double, stepBeats S: Double, a: Double) -> Double {
    let pair = 2 * S
    let base = (musicalBeat / pair).rounded(.down) * pair
    let v = musicalBeat - base
    let u = v < S ? v * a : a * S + (v - S) * (2 - a)
    return base + u
}

// MARK: - ARP phase (§3.5): pattern index at a tick, per phase mode

/// The pattern index at this tick per PHASE mode. All pure functions of position — derived, never
/// accumulated (§7), so tempo/loop/relocate stay drift-free.
///  · RETRIG — restarts at each step (column) boundary.
///  · LEGATO — counts from the run's first column (snapshot-precomputed runStartColumn), so a
///    multi-column run of one Colour continues the pattern; a gap restarts it.
///  · FREE   — free-running from the origin; successive passes land on different slices.
@inline(__always)
func phaseIndex(tick: Int64, mTickBeat: Double, arpBeats: Double, S: Double,
                cycleBeats: Double, phase: ArpPhase, runStartColumn: Int8) -> Int64 {
    switch phase {
    case .free:
        return tick
    case .retrig:
        let colStart = (mTickBeat / S).rounded(.down) * S
        return tick - Int64((colStart / arpBeats).rounded())
    case .legato:
        let passStart = (mTickBeat / cycleBeats).rounded(.down) * cycleBeats
        let rs = runStartColumn >= 0 ? Int(runStartColumn)
                                     : Int(((mTickBeat - passStart) / S).rounded(.down))
        let runStart = passStart + Double(rs) * S
        return tick - Int64((runStart / arpBeats).rounded())
    }
}

// MARK: - ARP pattern selection (§3)

/// The base note (pre-this-cell-transpose) + provenance channel a source-reading ARP picks at
/// pattern index `phaseIndex`, for the given PATTERN over `octaves`. All patterns are pure functions
/// of position (loop-consistent — RANDOM lands the same note on the same tick every pass). Chord
/// changes never reset the index. Returns base -1 for an empty pool.
func arpPickSource(phaseIndex: Int64, octaves: Int, pattern: UInt8,
                   pool: NotePool) -> (base: Int, chan: UInt8) {
    let count = pool.count
    guard count > 0 else { return (-1, 0) }
    let span = count * max(1, octaves)
    let asc = Int(((phaseIndex % Int64(span)) + Int64(span)) % Int64(span))   // UP position 0…span-1
    let pat = Int(pattern) < ArpPattern.allCases.count ? ArpPattern.allCases[Int(pattern)] : .up

    let pos: Int
    switch pat {
    case .up:
        pos = asc
    case .down:
        pos = span - 1 - asc
    case .upDown:
        // triangle, no repeated top/bottom: 0…span-1…1, period 2(span-1)
        let period = max(1, 2 * (span - 1))
        let tri = Int(((phaseIndex % Int64(period)) + Int64(period)) % Int64(period))
        pos = tri < span ? tri : period - tri
    case .random:
        // deterministic hash of the tick → position (loop-consistent, not accumulated)
        var h = UInt64(bitPattern: phaseIndex) &+ 0x9E3779B97F4A7C15
        h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
        h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
        h ^= (h >> 31)
        pos = Int(h % UInt64(span))
    case .asPlayed:
        pos = asc   // TODO: needs press-order in NotePool (note-indexed today); falls back to UP
    }

    let note = Int(pool.sorted[pos % count])
    return (note + 12 * (pos / count), pool.channel(of: note))
}

// MARK: - Processor dispatch (§3/§4)

/// What a cell does THIS render. Centralises processor dispatch: bypass and not-yet-built types
/// fall back to identity; an implemented processor gets its own mode; a closed PASSGATE is silent.
/// Adding a processor = one case here + its branch in the loop.
enum CellMode: Equatable { case arp, ratchet, identity, silent }

@inline(__always)
func cellMode(type: ProcessorType, bypassed: Bool, passMask: UInt8, pass: Int) -> CellMode {
    if bypassed { return .identity }                       // §3: bypass = identity processor
    switch type {
    case .arp:      return .arp
    case .ratchet:  return .ratchet
    case .passgate:                                        // §3/§4: gated by pass (mod 4)
        let bit = ((pass % 4) + 4) % 4
        return (passMask & (UInt8(1) << bit)) != 0 ? .identity : .silent
    default:        return .identity                       // STRUM/CHANCE/HARMONIZE: identity until built
    }
}

// MARK: - RATCHET velocity ramp (§3)

/// Velocity for ratchet repeat `index` of `count`. ramp 0 = flat at base; ramp 1 = crescendo from
/// ~silent up to base (first hit softest, last full). ASSUMPTION: crescendo direction — flip if the
/// feel should accent the first hit instead.
@inline(__always)
func ratchetVelocity(base: Int, ramp: Double, index: Int, count: Int) -> UInt8 {
    guard count > 1 else { return UInt8(max(1, min(127, base))) }
    let frac = Double(index) / Double(count - 1)          // 0 (first) … 1 (last)
    let scale = (1.0 - ramp) + ramp * frac                // ramp 0 → 1; ramp 1 → frac
    return UInt8(max(1, min(127, Int((Double(base) * scale).rounded()))))
}
