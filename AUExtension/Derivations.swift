//  Derivations.swift
//  MidiSpark — the pure, stateless core of the engine (spec v2.8 §3/§4/§7).
//
//  Everything here is a pure function of its inputs (or, for NotePool, a self-contained data
//  structure): no Router state, no CoreAudio, no snapshot. That makes this the regression-prone
//  math the render thread leans on — swing warp, phase indexing, arp pattern selection, processor
//  dispatch — AND the part that is unit-testable off-device (see Tests/DerivationsTests.swift).
//  Foundation only, on purpose: the test target compiles this file directly.

import Foundation

/// Clamp `v` into [lo, hi] (assumes lo ≤ hi). One name for the `max(lo, min(hi, v))` idiom repeated across the
/// engine's resolvers and the macro offset math — states the clamp INTENT once, no behaviour change.
@inline(__always) func clamp<T: Comparable>(_ v: T, _ lo: T, _ hi: T) -> T { min(max(v, lo), hi) }
/// Positive modulo — `((x % n) + n) % n`, the rotate/wrap idiom used ~throughout (refactor 2026-09-03). `n > 0`.
@inline(__always) func posMod(_ x: Int, _ n: Int) -> Int { let m = x % n; return m < 0 ? m + n : m }

/// A velocity clamped to the legal 1…127 and narrowed to UInt8 — the shape every processor's output-velocity
/// scaling shares (never 0 = a note-off, never > 127). One name for `UInt8(max(1, min(127, v)))`.
@inline(__always) func clampVel(_ v: Int) -> UInt8 { UInt8(clamp(v, 1, 127)) }

/// The POSITIVE fractional part of `x` in [0, 1) — folds negatives forward (e.g. −0.1 → 0.9). One spelling of
/// the `(x.trunc(1) + 1).trunc(1)` idiom the chop/sweep column-time maths share.
@inline(__always) func positiveFract(_ x: Double) -> Double {
    (x.truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
}

/// The musical-beat START of the column that `beat` falls in — floors `beat` to the step grid (`S` = a step's beats).
/// The shared spelling of the `(beat / S).rounded(.down) * S` idiom the Router's emit paths repeat. Pure/testable.
@inline(__always) func columnStart(_ beat: Double, _ S: Double) -> Double { (beat / S).rounded(.down) * S }

/// A reset re-anchor ORIGIN that itself re-synchronizes at a bounded OUTER loop boundary (2026-10-14 ferry
/// §5: "the count restarts when the sequence loops, so the marks stay fixed") — found missing by a self-
/// audit against the ferry's raw text: the first build re-anchored the EUCLID pattern's own reset purely
/// from absolute beat 0 (`columnStart(beat, resetSteps*stepBeats)`), which only coincidentally matches the
/// on-screen restart marks when the LANES sequencer's own LEN happens to be a multiple of `resetSteps` (true
/// for every default combination, since LEN defaults to 8 and 1/2/4/8 all divide it evenly) — it silently
/// diverges from the marks for any OTHER LEN. This generalizes the re-anchor to ALSO wrap at a genuine outer
/// loop: within one lap of `loopSteps` sequencer steps, a restart happens at local step 0, `resetSteps`,
/// `2×resetSteps`, … (never crossing into the next lap even if `resetSteps` doesn't divide `loopSteps`
/// evenly), and a NEW lap always starts fresh at local step 0 regardless of where the previous lap's own
/// restart cycle had reached — exactly matching the UI's own restart-mark rule (`step % resetSteps == 0`
/// for `step` in `0..<loopSteps`), so the two can no longer silently disagree. `loopSteps <= 0` means "no
/// outer loop" — degenerates to the ORIGINAL, unbounded `columnStart(beat, Double(resetSteps)*stepBeats)`
/// exactly (every OTHER reset path — the legacy bars-count/span-ladder ones — keeps that unbounded shape,
/// untouched, since neither has a LEN concept to re-anchor against).
func euclideousLoopedResetOrigin(beat: Double, stepBeats: Double, resetSteps: Int, loopSteps: Int) -> Double {
    guard stepBeats > 0, resetSteps > 0 else { return 0 }
    let absStep = Int((beat / stepBeats).rounded(.down))
    let lapStartStep = loopSteps > 0 ? (absStep / loopSteps) * loopSteps : 0
    let stepsSinceLap = absStep - lapStartStep
    let restartStep = lapStartStep + (stepsSinceLap / resetSteps) * resetSteps
    return Double(restartStep) * stepBeats
}

/// "Every N" as an 8-bit stamp (2026-10-15 ferry §1.2): bits 0, N, 2N, … below 8 set; N ≤ 0 ⇒ empty (OFF).
/// The ONLY place a preset number becomes a mask — `EuclidLine.restartMaskResolved`'s own fallback and the
/// presets popover both call this, so "every N" can never drift between the two.
func euclideousStampMask(_ n: Int) -> UInt8 {
    guard n > 0 else { return 0 }
    var m: UInt8 = 0
    var s = 0
    while s < 8 { m |= (1 << s); s += n }
    return m
}

/// Generalises `euclideousLoopedResetOrigin` to an arbitrary per-step restart mask (2026-10-15 ferry, "per-
/// step restart points on the LANES tab" §2.1). Bit s (0..<loopSteps) set ⇒ the lane restarts at the start
/// of sequencer step s. Only bits below `loopSteps` take effect (§1.3) — masked here, so no caller can forget
/// to. "No restart point yet this lap" (no set bit at or before the current lap-local step) means the lane
/// is STILL running from the PREVIOUS lap's last restart point, not lap-start — so a mask with no mark on
/// step 0 does NOT re-anchor the lane when the sequence loops. This can return a NEGATIVE origin in the very
/// first lap (there is no "previous lap" yet, same as the ferry's own worked example) — plain arithmetic,
/// every caller handles it exactly like any other beat-0-relative origin, no special-casing. Deliberately a
/// plain `while` scan over at most 8 bits rather than a `Range` built from `local` — `local` can itself be
/// negative for a beat before the transport's bar 1 (the same truncating-division quirk already present in
/// `euclideousLoopedResetOrigin` above, reused here on purpose, §2.1's "reuse the existing flooring exactly"),
/// and `0...local` with a negative `local` is a Swift trap, not a quiet no-op.
func euclideousMaskedResetOrigin(beat: Double, stepBeats: Double, mask: UInt8, loopSteps: Int) -> Double {
    guard stepBeats > 0, loopSteps > 0 else { return 0 }
    let n = min(8, loopSteps)
    let widthMask: UInt8 = n >= 8 ? 0xFF : UInt8((1 << n) - 1)
    let m = mask & widthMask
    guard m != 0 else { return 0 }
    let absStep = Int((beat / stepBeats).rounded(.down))
    let lapStartStep = (absStep / n) * n
    let lapStart = Double(lapStartStep) * stepBeats
    let local = absStep - lapStartStep
    var bestAtOrBeforeLocal = -1
    var highestSet = -1
    var s = 0
    while s < n {
        if (m & (1 << s)) != 0 {
            highestSet = s
            if s <= local { bestAtOrBeforeLocal = s }
        }
        s += 1
    }
    if bestAtOrBeforeLocal >= 0 { return lapStart + Double(bestAtOrBeforeLocal) * stepBeats }
    let lapBeats = Double(n) * stepBeats
    return lapStart - lapBeats + Double(highestSet) * stepBeats
}

/// Which step index (0..<columns) a finger sliding off the RESET box lands on, given an X offset measured
/// from the box's OWN local left edge (2026-10-15 ferry §4.4, "one-thumb shortcut... hit-test with the same
/// cell-width and gap formula the grid draws with"). `labelW` is the RESET box's own width; the gap to its
/// right, and between every pair of cells after it, is the same `gap`. A touch still inside the box, in a
/// gap, or past the last cell misses (nil) — "lifting anywhere else does nothing" (§4.4).
func euclideousRestartStepHitTest(localX: CGFloat, labelW: CGFloat, gap: CGFloat, cellW: CGFloat, columns: Int) -> Int? {
    guard cellW > 0, columns > 0 else { return nil }
    let x = localX - labelW - gap
    guard x >= 0 else { return nil }
    let period = cellW + gap
    let step = Int((x / period).rounded(.down))
    guard step >= 0, step < columns else { return nil }
    let withinCellX = x - CGFloat(step) * period
    return withinCellX <= cellW ? step : nil
}

/// The RESET box's own label (2026-10-15 ferry §3), pure, derived from the lane's effective mask (bits below
/// `loopSteps` only). Tests N = 1, 2, 4, 8 in that order against the mask restricted to `loopSteps` — first
/// match wins, so two different stamps that happen to coincide once narrowed to a short LEN (e.g. every-4 and
/// every-8 at LEN 4, both narrow to {bit 0}) read identically, matching §1.2's "nothing records which preset
/// was picked."
struct EuclideousRestartLabel: Equatable { let value: String; let unit: String }
func euclideousRestartLabel(mask: UInt8, loopSteps: Int) -> EuclideousRestartLabel {
    let n = clamp(loopSteps, 0, 8)
    let widthMask: UInt8 = n <= 0 ? 0 : (n >= 8 ? 0xFF : UInt8((1 << n) - 1))
    let effective = mask & widthMask
    if effective == 0 { return EuclideousRestartLabel(value: "\u{2013}", unit: "OFF") }
    for N in [1, 2, 4, 8] where (euclideousStampMask(N) & widthMask) == effective {
        return EuclideousRestartLabel(value: "\(N)", unit: "STEP")
    }
    let count = (0..<8).filter { (effective & (1 << $0)) != 0 }.count
    return EuclideousRestartLabel(value: "\(count)", unit: "PTS")
}
/// The RESET box's VoiceOver phrasing (2026-10-15 ferry §4.9): "every N steps" / "off" / "k custom points" —
/// reuses `euclideousRestartLabel`'s own stamp-detection so the spoken and on-screen labels can never disagree
/// about what the mask resolves to, just phrased in full words instead of a compact value/unit pair.
func euclideousRestartAccessibleLabel(mask: UInt8, loopSteps: Int) -> String {
    let label = euclideousRestartLabel(mask: mask, loopSteps: loopSteps)
    switch label.unit {
    case "OFF": return "off"
    case "STEP": return "every \(label.value) steps"
    default: return "\(label.value) custom points"
    }
}

/// The LANES/RIFFS sequencer's own 0..<len step index at `beat` (2026-10-14 ferry, "sequencer panel, four
/// riffs, per-lane reset" §4: "steps are counted from the host's bar 1... the step clock always runs").
/// `stepBeats` is the sequencer's own resolved rate (e.g. `EuclideousSeqRate.barsFraction × one-bar-beats`).
/// Pure, derived-never-accumulated: `beat` is already an absolute host-beat position (this engine's own
/// standing convention, beat 0 = the transport origin / the host's bar 1), so flooring straight from it IS
/// "counted from the host's bar 1" — no separate anchor/reset state needed, the step clock genuinely always
/// runs for free. `len` is NOT the number of steps the pattern itself has — it's the sequencer's own loop
/// length (1...8); "the count restarts when the sequence loops" (§5) falls out of the plain modulus.
func euclideousSeqStepIndex(beat: Double, stepBeats: Double, len: Int) -> Int {
    guard stepBeats > 0 else { return 0 }
    let n = max(1, len)
    let absStep = Int((beat / stepBeats).rounded(.down))
    return ((absStep % n) + n) % n
}

// MARK: - LOOPER TABS (FERRY "looper tabs replace the riff tabs", ratified 2026-10-16)
//
// §6.1: ONE pure function decides a column's rank at any beat — from the live grid and, if one is
// running, the single loop. Every reader shares it (§6.2): the Router's per-hit riff read, the TIE
// lookahead's frozen snapshot, the grid display, the riff-grid markers, lane prediction, DRUNK,
// VoiceOver. No reader re-derives "what's the rank here" on its own — the exact bug class this codebase
// has hit repeatedly (RATCHET/DEST/the mask step bar/the ARP LFO/CLOCK's glide), named in CLAUDE.md as
// the recurring one. SUPERSEDES the loop-slots ferry's `euclideousActiveSource`/`euclideousEffectiveRank`/
// `euclideousSlotRankAtPosition` pair entirely — there is only one riff and at most one loop now, so
// there is no "which of several sources" question left to resolve.

/// A loop's own position within it, in bars, always in `[0, passes)` (§1.4: "bars since B, modulo N").
/// Exposed separately (not just inlined below) because the loop row's own segment-fill display (§7.4)
/// needs this SAME number — it must never re-derive its own version.
func euclideousLoopPositionBars(beat: Double, startBeat: Double, beatsPerBar: Double, passes: Double) -> Double {
    let barBeats = max(0.0001, beatsPerBar)
    let n = max(1, passes)
    let raw = (beat - startBeat) / barBeats
    return raw - n * (raw / n).rounded(.down)
}
/// §6.1, literal: no loop, or `beat` before B, → the live grid. Otherwise: position p = bars since B
/// modulo N; the loop's start rank, then its events on this column with offset ≤ p, in order, last one
/// wins (§3.2/§3.3's "replay is faithful... events apply in order"). `events` is one flat, per-column-
/// tagged array (§6.4's "fixed-capacity per-column buffers," threaded here as one array for simpler
/// plumbing — behaviourally identical, since this scan only ever looks at `ev.column == column` entries).
func euclideousLooperEffectiveRank(column: Int, beat: Double, liveGrid: [Int],
                                    active: Bool, startBeat: Double, passes: Int, startRanks: [Int],
                                    events: [EuclideousLoopEvent], beatsPerBar: Double) -> Int {
    guard column >= 0, column < 8 else { return 0 }
    let liveGridRank = column < liveGrid.count ? liveGrid[column] : 0
    guard active, beat >= startBeat else { return liveGridRank }
    let p = euclideousLoopPositionBars(beat: beat, startBeat: startBeat, beatsPerBar: beatsPerBar, passes: Double(max(1, passes)))
    var best: EuclideousLoopEvent? = nil
    for ev in events where ev.column == column && ev.offsetBars <= p + 1e-9 {
        if best == nil || ev.offsetBars > best!.offsetBars { best = ev }
    }
    let startRank = column < startRanks.count ? startRanks[column] : 0
    return best?.rank ?? startRank
}
/// §2.2, literal: "Recording starts at B, the NEXT bar line after the tap... a tap in a bar's first beat
/// STILL arms for the next bar line. There is no grace." — unlike the LANDED-overdub timing this ferry's
/// predecessor (loop-slots) used, arming NEVER retroactively anchors to the bar already in progress, even
/// when the tap lands in its first beat; it always targets the FOLLOWING line. Also used for §2.7's "a
/// transport start counts as a bar line" (pass `beat` = the run's own first beat) and §5.2's post-edge
/// re-arming. Kept here (not UI-private) so it stays off-device testable (§9.3).
func euclideousNextLandingBeat(from beat: Double, barBeats: Double) -> Double {
    guard barBeats > 0 else { return beat }
    return ((beat / barBeats).rounded(.down) + 1) * barBeats
}
/// §2.7/§5.2: a transport edge (host start, backward jump, the free-run↔host hand-over) ITSELF "counts as
/// a bar line" — unlike an ordinary tap (§2.2's always-the-NEXT-line, no-grace arming rule, above), the
/// run's own first bar line is the one the edge landed AT or just past (the poll notices a beat or so
/// later than the true edge, per §3.5's accepted jitter), not one further ahead. Floors `beat` down to its
/// enclosing bar line. Used for §5.2's "Armed: B is the first bar line after the edge" and "Replaying:
/// restarts from pass 1 at the run's first bar line."
func euclideousRunFirstBarLine(at beat: Double, barBeats: Double) -> Double {
    guard barBeats > 0 else { return beat }
    return (beat / barBeats).rounded(.down) * barBeats
}
/// §3.4: coalesce same-column events within 1/96 beat (converted to bars by the caller, since events are
/// bar-offset) — the LAST write wins. Cap 128 PER COLUMN; past the cap "an edit still sounds but isn't
/// recorded" — it's simply not appended (not inserted-and-evict-oldest), exactly per the literal text.
/// Pure; called from the MAIN THREAD only (§6.4 — the render thread never records), once per edit.
/// §7.3, literal: "segment width = (button width − 12 − gaps) ÷ N; gap 2 (N ≤ 8) or 1 (N = 16); if that
/// falls below 2, drop the gaps to 1." Pure (no SwiftUI dependency) so the loop row's own geometry stays
/// off-device testable, same convention `euclideousRestartStepHitTest` already established in this file.
func euclideousLooperSegmentGeometry(n: Int, buttonWidth: CGFloat) -> (segmentWidth: CGFloat, gap: CGFloat) {
    let inset: CGFloat = 6
    let available = max(0, buttonWidth - inset * 2)
    let nD = CGFloat(max(1, n))
    let initialGap: CGFloat = n <= 8 ? 2 : 1
    let rawSegW = (available - initialGap * CGFloat(max(0, n - 1))) / nD
    let gap: CGFloat = rawSegW < 2 && initialGap > 1 ? 1 : initialGap
    let segW = max(0, (available - gap * CGFloat(max(0, n - 1))) / nD)
    return (segW, gap)
}
func euclideousAppendLooperEvent(_ events: [EuclideousLoopEvent], column: Int, rank: Int, offsetBars: Double,
                                  coalesceWindowBars: Double, cap: Int = 128) -> [EuclideousLoopEvent] {
    var out = events
    for i in out.indices.reversed() where out[i].column == column {
        if abs(out[i].offsetBars - offsetBars) <= coalesceWindowBars {
            out[i] = EuclideousLoopEvent(offsetBars: offsetBars, column: column, rank: rank)
            return out
        }
        break   // same-column events are appended in time order — the most recent one is the only coalesce candidate
    }
    let columnCount = out.reduce(0) { $0 + ($1.column == column ? 1 : 0) }
    guard columnCount < cap else { return out }   // §3.4: past the cap, the edit still sounds live but isn't recorded
    out.append(EuclideousLoopEvent(offsetBars: offsetBars, column: column, rank: rank))
    return out
}

// THE SPAN LADDER (Paul 2026-08-22 §3): CELL|ROW generalises to a dial — 1·2·3·4·6·8 columns, then ×2·×4 bars
// (stored as 16/32). The pattern anchors at the row origin and repeats every N columns → polymeter at processor grain
// (odd N against the 8-column row). CELL = 1, ROW = 8 are the byte-identical endpoints (S and the row/bar width).
let spanLadderValues = [1, 2, 3, 4, 6, 8, 16, 32]
func spanLadderLabel(_ n: Int) -> String { n == 16 ? "×2" : (n == 32 ? "×4" : "\(n)") }
// ArpPattern.allCases is a COMPUTED property → it heap-allocates a fresh array on every access. The arp render path
// reads it per tick (arpPick + emitArpRow), which violates invariant 3 (no render-path allocation). Cache it once (the
// same idiom as spanLadderValues/rtcCoinSizes). Order = declaration order = patternIndex (SnapshotBuilder maps a stored
// index via firstIndex(of:)), so indexing the cache is byte-identical to indexing allCases. (efficiency 2026-08-29)
let arpPatternCases = ArpPattern.allCases
/// The ArpPattern at a stored patternIndex, clamped to UP for an out-of-range index — the render-path reader.
@inline(__always) func arpPatternAt(_ i: Int) -> ArpPattern { i >= 0 && i < arpPatternCases.count ? arpPatternCases[i] : .up }
/// The ARP RATE ladder the LFO is allowed to sweep, given an IGNORE mask (bit0 normal · bit1 dotted · bit2 triplet).
/// ArpRate.allCases is DECLARED as [6 normal · 6 dotted · 6 triplet] (family = index / 6), but a dotted/triplet rate
/// musically falls BETWEEN two adjacent normal rates (e.g. 1/4T and 1/8D both sit between 1/8 and 1/4 in actual
/// tempo) — so the ladder is sorted by ACTUAL DURATION (`.beats`, slow→fast), not by declaration block. Paul
/// 2026-09-26: a raw block-ordered ladder made a FROM→TO sweep between two normal rates (the common case — FROM
/// defaults to the arp's own base rate) NEVER reach dotted/triplet even when "included", because both endpoints sat
/// in the same contiguous block of ladder POSITIONS — the interleaved families were included in the SET but never
/// crossed in POSITION SPACE. Tempo-sorting makes ladder position a true proxy for musical position, so any
/// included rate that lies between the two endpoints (by tempo) is now genuinely visited. Never empty (an all-ignore
/// mask keeps normal). Paul 2026-09-16 (LFO rate-family ignore).
func arpRateAllowedLadder(ignore mask: Int) -> [Int] {
    let m = (mask & 0b111) == 0b111 ? 0b110 : (mask & 0b111)   // all-ignore → keep normal (mirrors rateIgnoreResolved)
    let kept: [Int] = (0..<18).filter { (m & (1 << ($0 / 6))) == 0 }
    let out: [Int] = kept.sorted { Snap.arpRateBeats[$0] > Snap.arpRateBeats[$1] }   // slow → fast, by real duration (not declaration block); Snap.arpRateBeats is a cached static, no render-path alloc
    return out.isEmpty ? Array(0..<6) : out
}
/// The POSITION in `ladder` of the rung nearest to `idx` (a raw 0…17 rate index) — snaps a FROM/TO endpoint onto the
/// allowed ladder so an ignored-family endpoint maps to the closest kept rate. Paul 2026-09-16.
func nearestLadderPos(_ ladder: [Int], _ idx: Int) -> Int {
    guard !ladder.isEmpty else { return 0 }
    var best = 0, bestD = Int.max
    for (p, v) in ladder.enumerated() { let d = abs(v - idx); if d < bestD { bestD = d; best = p } }
    return best
}
/// The span's WIDTH in beats: 1 = one column (S) · 8 = the whole row (`rowBeats`, byte-identical to the old ROW —
/// honours a short loop) · ×2/×4 = 2/4 rows · 2·3·4·6 = N columns (the polymeter spans). Pure.
@inline(__always) func spanLadderBeats(_ n: Int, S: Double, row rowBeats: Double) -> Double {
    switch n {
    case ...1: return S
    case 8:    return rowBeats
    case 16:   return 2 * rowBeats
    case 32:   return 4 * rowBeats
    case 64:   return 8 * rowBeats    // ×8 — the LFO DURATION ladder reaches ×8 (Paul 2026-09-15)
    default:   return Double(n) * S   // 2·3·4·6 columns
    }
}

/// EUCLID's live position, as ONE continuous phase in [0, n) — SHARED by the real render path
/// (Router.swift's `runEuclidLine`) and the GridUI comet-bar (Paul 2026-09-29 redesign), so a UI sweep can
/// never read a different clock than the engine actually does — the RATCHET-PATTERN/DEST class of bug this
/// project has hit twice before, where a UI re-derived a clock instead of calling the engine's own formula.
/// `mTickBeat` must already be the swing-warped "musical" beat (via `musicalOf`), matching `iterateTicks`.
func euclidPhase(mTickBeat: Double, sub: Double, spanBeats: Double, n: Int) -> Double {
    let phaseBeat = spanBeats > 0 ? (mTickBeat - columnStart(mTickBeat, spanBeats)) : mTickBeat
    let raw = phaseBeat / max(0.0001, sub)
    let nD = Double(max(1, n))
    return raw - nD * (raw / nD).rounded(.down)   // raw mod n, always in [0, n)
}
/// The comet bar's own raw tick count (Paul 2026-10-02: "reverse when BKW, back-and-forth on PING-PONG") —
/// `euclidPhase` above always mods by `n`, which only ever shows PING-PONG's ascending half; this instead mods
/// by the DIRECTION's real cycle length (`euclidCycleLen` — n for FWD/BKW, 2n for PING-PONG), matching the real
/// render path's own `localT mod cycleLen` (Router.swift's `runEuclidLine`) so a full ping-pong lap is visible.
/// UI-only (GridUI.swift's comet bar) — same as `euclidPhase`, never read by the render path.
func euclidCometRaw(mTickBeat: Double, sub: Double, spanBeats: Double, n: Int, dir: EuclidDir) -> Double {
    let phaseBeat = spanBeats > 0 ? (mTickBeat - columnStart(mTickBeat, spanBeats)) : mTickBeat
    let raw = phaseBeat / max(0.0001, sub)
    let cycleLen = Double(euclidCycleLen(dir, n: n))
    return raw - cycleLen * (raw / cycleLen).rounded(.down)   // raw mod cycleLen, always in [0, cycleLen)
}
/// The comet's own SCREEN position (continuous, for smooth sweep) given its raw tick count — the real-valued
/// analogue of `euclidReadIndex`, allowing a fractional `raw` instead of only integers: FWD sweeps left→right
/// (pos = raw); BKW sweeps right→left (pos = n − raw); PING-PONG sweeps left→right then bounces back right→left
/// within the same lap (ascending half pos = raw, descending half pos = 2n − raw). Box CONTENT (which buffer
/// entry each of the N boxes shows) is untouched by this — only the comet's own visual sweep direction.
func euclidCometPos(_ raw: Double, n: Int, dir: EuclidDir) -> Double {
    let nD = Double(max(1, n))
    switch dir {
    case .fwd: return raw
    case .bkw: return nD - raw
    case .pingpong: return raw < nD ? raw : 2 * nD - raw
    }
}

// CLOCK (AcceptanceCriteria-clock-processor, Paul 2026-09-26) — the pure beat → phase transform. A downstream fold
// consumer (RATCHET's own rate/slice math etc.) asks "what's local time AT this one real beat instant?"; a
// retimed DRIVER asks the inverse ("what real beat produces this local tick?"); these functions answer both — no
// accumulation, no walking. The SOVEREIGN LAW: this is the ONLY thing CLOCK touches. Windows, columns, spans' own
// extents, and everything else that reads a raw beat stays on that raw beat — callers choose which beat to feed
// these, never the reverse. (FIXED and WAVE modes — a simple ratio+offset and a zero-mean cosine/triangle wobble —
// were built and then REMOVED entire, same day: Paul's own spec, "a grid with a variable number of steps, each
// step a mutually exclusive speed, and another row on the same grid for glide", describes one mechanism, not a
// choice of three, and matches only what follows — CLOCK is now always this DRAWN lane.)

/// DRAWN mode (Stage 2, Paul 2026-09-26): RIFF's anatomy wearing time — resolve an authored lane's per-column ratio
/// picks into actual ratio VALUES, carrying an empty column (−1, "CARRY the previous rate") forward from the last
/// explicit pick, wrapping around the lane if the very first column(s) are empty. An ALL-empty lane falls back to
/// ×1 everywhere (never silent/undefined). Pure — call ONCE at resolve time (SnapshotBuilder), not per render: the
/// render-side `clockDrawnPhase` takes the already-resolved values, no −1 sentinels, no render-path allocation.
func clockDrawnResolveRatios(_ picks: [Int], steps: Int) -> [Double] {
    guard steps > 0 else { return [] }
    var lastExplicit = 4   // ×1 — the fallback if the WHOLE lane is empty
    for i in (0..<steps).reversed() { let v = i < picks.count ? picks[i] : -1; if v >= 0 { lastExplicit = v; break } }
    var carry = lastExplicit
    var idx = [Int](repeating: 4, count: steps)
    for i in 0..<steps {
        let v = i < picks.count ? picks[i] : -1
        if v >= 0 { carry = v }
        idx[i] = carry
    }
    return idx.map { clockRatioLadder[max(0, min(clockRatioLadder.count - 1, $0))] }
}

/// A GLIDE column's own (from, to) ramp endpoints (Paul 2026-09-26, span fix): NOT its immediate predecessor's
/// value — a run of consecutive GLIDE columns that all target the SAME ratio is coalesced into ONE SPAN, and this
/// column's endpoints are its own slice of that whole span's ramp. Caught against a worked example: three ×2-glide
/// columns in a row must ramp smoothly across all three (reaching ×2 only at the end of the third), not reach ×2
/// after the FIRST column and flatline for the other two — a from→to segment whose two ends are numerically equal
/// (the naive "ramp from my immediate predecessor" reading) has no slope to inherit, so it can't produce that
/// climb on its own. The walk here finds the span's boundaries (bounded O(steps) each direction — a fully-glide,
/// fully-identical lane still terminates after one lap, never spins forever) then linearly interpolates this
/// column's start/end fraction of the span's overall from→to distance. A run of DIFFERING consecutive targets
/// naturally forms spans of length 1 (no two neighbours share a target to coalesce with), which reduces EXACTLY to
/// the original one-column formula (`from = the column before the span`, `to = this column's own target`) — so a
/// genuinely-progressing sequence (1→2→3→2, each step a new target) is completely unaffected by this change.
func clockDrawnGlideEndpoints(_ i: Int, ratios: [Double], glide: [Bool], steps: Int) -> (from: Double, to: Double) {
    func ratioAt(_ k: Int) -> Double { ratios[posMod(posMod(k, steps), ratios.count)] }
    func isGlide(_ k: Int) -> Bool { k >= 0 && k < glide.count && glide[k] }
    let target = ratioAt(i)
    var spanStart = i, spanEnd = i
    var guard1 = 0
    while guard1 < steps { let prev = spanStart - 1; guard isGlide(prev), ratioAt(prev) == target else { break }; spanStart = prev; guard1 += 1 }
    var guard2 = 0
    while guard2 < steps { let next = spanEnd + 1; guard isGlide(next), ratioAt(next) == target else { break }; spanEnd = next; guard2 += 1 }
    let spanFrom = ratioAt(spanStart - 1)
    let spanLen = Double(spanEnd - spanStart + 1)
    let offset = Double(i - spanStart)
    let from = spanFrom + (target - spanFrom) * (offset / spanLen)
    let to = spanFrom + (target - spanFrom) * ((offset + 1) / spanLen)
    return (from, to)
}

/// GLIDE's "elastic landing", ACCELERATING glides only (Paul 2026-09-26 ②→③: "when it lands on a target, whether
/// it got there with or without glide, it should be in sync" — then, after trying it, "weird behaviour... appears
/// to change the velocity two cells after a jump" + "hiccups... a stutter" on a chained run of same-target glide
/// columns). The first cut of this fix applied the elastic overshoot to EVERY glide regardless of direction, which
/// is provably safe for an ACCELERATING glide (`to ≥ from`) but NOT for a DECELERATING one — confirmed by tracing a
/// from=2→to=1 column with a throwaway script: the elastic curve's cumulative local-time position runs UP TO 16%
/// AHEAD of a same-target SET for most of the column before snapping back to exact parity only at the very end.
/// That's the mechanism behind both reports: a downstream driver/fold-consumer reading the transformed beat
/// mid-glide sees local time race ahead of schedule (discovering an early/extra tick or step), then a compensating
/// gap as it catches back down — and it compounds badly across a coalesced run of several same-target columns
/// (Paul's 4-column ×1 example), since each individual column-slice repeats the same "race ahead, catch down"
/// wobble in series.
///
/// The asymmetry is a hard calculus fact, not a tuning choice: for ACCELERATING glides (`to ≥ from`), the straight
/// ramp's own average sits BELOW `to`, so reaching `to × rateBeats` requires the rate to rise ABOVE `to` for part
/// of the column — and since it starts BELOW `to` and only exceeds it late (after using up the deficit), the
/// cumulative position can be proven to stay ≤ a same-target SET throughout the whole column, converging to EXACT
/// equality only at the very end (never ahead, so no early-discovery artifact — see `DerivationsTests.
/// testClockDrawnGlideFullColumnAlwaysMatchesSetAtTheSameTarget`, and the boundary-value trace above). For
/// DECELERATING glides (`to < from`), the SAME zero-drift requirement instead needs the rate to dip BELOW `to`
/// first — and dipping below a SLOWER target while still starting FAST means the cumulative position necessarily
/// RACES AHEAD before it can fall back — the exact glitch. So: accelerating glides get the full elastic "in sync"
/// treatment; decelerating glides fall back to the plain straight-line ramp (its honest, non-zero average, exactly
/// the shape this whole CLOCK feature shipped with originally) — a real remaining asymmetry, not a bug, and the
/// `clockDrawnDriftPerLap` readout still honestly reports whatever residual drift a decelerating glide leaves.
///
/// `clockDrawnGlideShape` (for the accelerating branch) needs no adaptive floor now — `P = to + 0.5×(to−from) ≥ to
/// > 0` unconditionally when `to ≥ from`, so the split is always the simple symmetric midpoint (the earlier
/// adaptive-f floor existed only to keep decelerating overshoots from driving local time backward; decelerating
/// glides no longer take this branch at all, so that whole mechanism — and the need for a variable split fraction
/// at all — is gone; the split is always exactly `T/2`).
@inline(__always) func clockDrawnGlideShape(from: Double, to: Double) -> Double { to + 0.5 * (to - from) }
/// The local-time ADVANCE of one GLIDE column, from its start up to `t` beats in (0…`rateBeats`). ACCELERATING
/// (`to ≥ from`): the two-segment "elastic landing" `clockDrawnGlideShape` describes (a short kick past `to`, then
/// an ease back down onto it — the closed-form integral of a piecewise-linear rate, each half a plain quadratic).
/// DECELERATING (`to < from`): the plain single straight-line ramp (this feature's original shape) — see the
/// doc comment above for why forcing the elastic treatment here is unsafe, not merely undesirable.
@inline(__always) func clockDrawnGlideAdvance(_ t: Double, from: Double, to: Double, rateBeats T: Double) -> Double {
    guard T > 0 else { return 0 }
    guard to >= from else { return from * t + (to - from) / (2 * T) * t * t }
    let P = clockDrawnGlideShape(from: from, to: to)
    let half = T / 2
    if t <= half {
        return from * t + (P - from) * t * t / (2 * half)
    }
    let posHalf = half * (from + P) / 2
    let tp = t - half
    let rest = T - half
    return posHalf + P * tp + (to - P) * tp * tp / (2 * rest)
}
/// A GLIDE column's FULL local-time contribution over its whole duration. ACCELERATING: always exactly
/// `to × rateBeats`, the SAME a SET column at `to` would give — the "in sync" fix, safe by the proof above.
/// DECELERATING: the plain ramp's own honest average, `(from+to)/2 × rateBeats` — no forced sync (see above).
@inline(__always) func clockDrawnGlideFullAdvance(from: Double, to: Double, rateBeats: Double) -> Double {
    to >= from ? to * rateBeats : (from + to) / 2 * rateBeats
}
/// The exact inverse of `clockDrawnGlideAdvance` — given a target local-time advance `r` (0…the column's full
/// contribution), returns how far into the column (0…`rateBeats`) that is. DECELERATING: the single straight-ramp
/// quadratic (the `+` root — the rate is always positive throughout, so `columnAdvance` is strictly monotonic and
/// exactly one root lies in range). ACCELERATING: the same two-segment solve, unchanged. No iteration either way.
@inline(__always) func clockDrawnGlideAdvanceInverse(_ r: Double, from: Double, to: Double, rateBeats T: Double) -> Double {
    guard T > 0 else { return 0 }
    func solveQuadratic(_ a: Double, _ b: Double, _ target: Double) -> Double {
        guard abs(a) > 1e-12 else { return b > 0 ? target / b : 0 }
        let disc = max(0, b * b + 4 * a * target)
        return (-b + disc.squareRoot()) / (2 * a)
    }
    guard to >= from else {
        let t = solveQuadratic((to - from) / (2 * T), from, r)
        return max(0, min(T, t))
    }
    let P = clockDrawnGlideShape(from: from, to: to)
    let half = T / 2
    let posHalf = half * (from + P) / 2
    let rest = T - half
    if r <= posHalf {
        let t = solveQuadratic((P - from) / (2 * half), from, r)
        return max(0, min(half, t))
    }
    let tp = solveQuadratic((to - P) / (2 * rest), P, r - posHalf)
    return max(half, min(T, half + tp))
}
/// A resolved lane's per-column ratio, wrapping (both `i` and the array length may be negative/short — `posMod`
/// handles both). Shared by every function below so the wrap rule can't drift between them.
@inline(__always) func clockDrawnRatioAt(_ i: Int, ratios: [Double], steps: Int) -> Double { ratios[posMod(posMod(i, steps), ratios.count)] }
@inline(__always) func clockDrawnIsGlide(_ i: Int, glide: [Bool]) -> Bool { i >= 0 && i < glide.count && glide[i] }
/// Column i's FULL local-time contribution over its whole rateBeats span — SET = constant rate; GLIDE defers to
/// `clockDrawnGlideFullAdvance` (accelerating = `to × rateBeats`, matching SET exactly; decelerating = the ramp's
/// own honest average — see that function's doc). One shared spelling used by the phase function, its inverse, and
/// the drift readout so they can't disagree.
@inline(__always) func clockDrawnColumnAdvance(_ i: Int, ratios: [Double], glide: [Bool], steps: Int, rateBeats: Double) -> Double {
    guard clockDrawnIsGlide(i, glide: glide) else { return clockDrawnRatioAt(i, ratios: ratios, steps: steps) * rateBeats }
    let (from, to) = clockDrawnGlideEndpoints(i, ratios: ratios, glide: glide, steps: steps)
    return clockDrawnGlideFullAdvance(from: from, to: to, rateBeats: rateBeats)
}

/// DRAWN mode's phase transform: a piecewise per-column lane — a SET column (`glide[i]` false) holds a CONSTANT
/// rate for its whole duration (a jump at column entry); a GLIDE column (`glide[i]` true) ramps smoothly between
/// the endpoints `clockDrawnGlideEndpoints` gives it, via the elastic landing (accelerating) or the plain ramp
/// (decelerating) — see `clockDrawnGlideAdvance`'s doc for which and why. Recomputed
/// from the SPAN/lap origin every call (bounded to O(steps) — two small fixed-size loops (plus each glide
/// column's own bounded span walk), no accumulation across renders, no render-path allocation since
/// `ratios`/`glide` are the caller's own arrays). `periodBeats` 0 ⇒ free-run: the lane just repeats every
/// `steps × rateBeats` from absolute beat 0 forever (still O(steps) per call via the `fullLaps` factor-out, not a
/// per-lap walk since t=0). `ratios` is already fully resolved (via `clockDrawnResolveRatios` — no −1 sentinels);
/// `glide.count` may be short (missing ⇒ SET). `originOverride` (Paul 2026-09-26, driver retiming): when supplied,
/// USE this span-origin instead of recomputing `columnStart(beat, P)` — so a driver's whole tick search (window-
/// start bound, window-end bound, and every tick discovered in between) can be pinned to ONE shared origin computed
/// once from the window's real start, rather than each call silently picking its own (which could disagree right
/// at a SPAN boundary crossing mid-window — a razor-thin, self-correcting edge case, but this avoids introducing
/// it at all). nil (every existing caller) ⇒ byte-identical to before.
func clockDrawnPhase(_ beat: Double, ratios: [Double], glide: [Bool], steps: Int, rateBeats: Double, periodBeats P: Double, originOverride: Double? = nil) -> Double {
    guard steps > 0, rateBeats > 0, !ratios.isEmpty else { return beat }
    let lapBeats = Double(steps) * rateBeats
    guard lapBeats > 0 else { return beat }
    let originBeat = originOverride ?? (P > 0 ? columnStart(beat, P) : 0)
    let localBeat = beat - originBeat
    let fullLaps = (localBeat / lapBeats).rounded(.down)
    let remainder = localBeat - fullLaps * lapBeats                      // in [0, lapBeats)
    let col = min(steps - 1, max(0, Int((remainder / rateBeats).rounded(.down))))
    let withinCol = remainder - Double(col) * rateBeats                  // in [0, rateBeats)
    var lapAdvance = 0.0; for i in 0..<steps { lapAdvance += clockDrawnColumnAdvance(i, ratios: ratios, glide: glide, steps: steps, rateBeats: rateBeats) }
    var partial = 0.0; for i in 0..<col { partial += clockDrawnColumnAdvance(i, ratios: ratios, glide: glide, steps: steps, rateBeats: rateBeats) }
    let currentAdvance: Double
    if clockDrawnIsGlide(col, glide: glide) {
        let (from, to) = clockDrawnGlideEndpoints(col, ratios: ratios, glide: glide, steps: steps)
        currentAdvance = clockDrawnGlideAdvance(withinCol, from: from, to: to, rateBeats: rateBeats)
    } else {
        currentAdvance = clockDrawnRatioAt(col, ratios: ratios, steps: steps) * withinCol
    }
    return originBeat + fullLaps * lapAdvance + partial + currentAdvance
}

/// The exact inverse of `clockDrawnPhase` (Paul 2026-09-26, driver retiming — THE feature: "a grid with a variable
/// number of steps, each step a mutually exclusive speed, and another row on the same grid for glide", wired to
/// retime a driver's own tick generation, not just a downstream fold consumer's math). Given a LOCAL beat that
/// grid produced (relative to a KNOWN `originBeat` — see `Router.driverClockBeat`, which computes it once per
/// tick-search window so every candidate tick agrees on the same span-anchor), recover the REAL beat that
/// produced it. A SET column inverts linearly; a GLIDE column inverts the closed-form quadratic (the
/// antiderivative of a linear rate ramp, via the quadratic formula — the `+` root, since a column's own rate is
/// always positive throughout its span, so `columnAdvance` is strictly monotonic and exactly one root lies in
/// [0, rateBeats]). Both closed-form: a bounded O(steps) walk to find the column, then one algebraic solve — no
/// iteration, no numerical search, matching the "derived, never accumulated" invariant.
func clockDrawnPhaseInverse(_ localBeat: Double, originBeat: Double, ratios: [Double], glide: [Bool], steps: Int, rateBeats: Double) -> Double {
    guard steps > 0, rateBeats > 0, !ratios.isEmpty else { return localBeat }
    let lapBeats = Double(steps) * rateBeats
    var lapAdvance = 0.0; for i in 0..<steps { lapAdvance += clockDrawnColumnAdvance(i, ratios: ratios, glide: glide, steps: steps, rateBeats: rateBeats) }
    guard lapAdvance > 0 else { return originBeat }
    let localOffset = localBeat - originBeat
    let fullLaps = (localOffset / lapAdvance).rounded(.down)
    var remainder = localOffset - fullLaps * lapAdvance          // in [0, lapAdvance)
    var col = steps - 1
    var partial = 0.0
    for i in 0..<steps {
        let adv = clockDrawnColumnAdvance(i, ratios: ratios, glide: glide, steps: steps, rateBeats: rateBeats)
        if remainder < partial + adv || i == steps - 1 { col = i; break }
        partial += adv
    }
    remainder -= partial                                        // local advance WITHIN this column, ≥ 0
    let withinCol: Double
    if clockDrawnIsGlide(col, glide: glide) {
        let (from, to) = clockDrawnGlideEndpoints(col, ratios: ratios, glide: glide, steps: steps)
        withinCol = clockDrawnGlideAdvanceInverse(remainder, from: from, to: to, rateBeats: rateBeats)
    } else {
        let rate = clockDrawnRatioAt(col, ratios: ratios, steps: steps)
        withinCol = rate > 0 ? remainder / rate : 0
    }
    let clampedWithin = max(0, min(rateBeats, withinCol))
    return originBeat + fullLaps * lapBeats + Double(col) * rateBeats + clampedWithin
}

// KILL STEP (Paul 2026-09-26, sibling to CLOCK) — a single row of `steps` on/off switches (default 8): a DISABLED
// step is removed from the downstream timeline entirely; the ENABLED steps repeat to fill the space (an even split
// like 4-of-8 plays "the first half twice"; an uneven split like 3-of-8 rotates a 3-cycle that drifts against the
// 8-column bar — deliberate k∤steps polymeter, the same shape `Derivations.lapColumn` already gives the ephemeral
// LAP performance gesture, now AUTHORED with its own RATE/SPAN as a chain-position processor). Detected alongside
// `.clock` by `Router.driverClockBeat`/…Inverse/`clockTransformedBeat`, so it composes in chain order with CLOCK
// (and with itself) and reaches every consumer those functions already reach — no new call sites needed.
//
// Unlike CLOCK's ratio warp (a continuous, everywhere-invertible speed change), this is a DISCRETE remap: within a
// kept real column, local time runs at ORDINARY rate (no speed change) — only WHICH column comes next changes.

/// Construction (Paul 2026-09-27, generalized for MUTE/PAUSE): `columnMap`/`columnsPerLap` are a PRECOMPUTED table
/// (SnapshotBuilder, off the render thread — see its KILL STEP resolve comment) replacing the live onIdx/k scan this
/// function used to do itself. At the n-th real column since the span origin (n = ⌊(beat − origin) / rateBeats⌋, can
/// be negative before the origin), the value fed downstream is `lap·steps + columnMap[n mod columnsPerLap]` where
/// `lap = ⌊n / columnsPerLap⌋` — so `value mod steps` cycles through the table in order (e.g. steps=8, ON={0,1,2,3}
/// → 0,1,2,3,0,1,2,3,… over one pass — "the first half plays twice"). `value` is STRICTLY increasing in `n` (each
/// lap adds a full `steps`, always greater than any value within a lap) — exactly what the shared tick-search
/// machinery needs: a monotonic local beat it can walk forward through and invert discovered ticks back from. A
/// MUTE step occupies exactly one table slot, same as ON (MUTE affects only whether a note SOUNDS — Router.
/// emitDriverNote's own fold — never this table); a PAUSE step occupies `1 + pauseLen` CONSECUTIVE slots holding the
/// SAME value (a true freeze — no new tick can be discovered until the value changes); a DROP step occupies none
/// (columnsPerLap is table.count, not steps — the length already reflects every hold/skip). When nothing is
/// MUTE/PAUSE this is BYTE-IDENTICAL to the original ON/DROP-only formula (`columnMap`≡the old `onIdx`,
/// `columnsPerLap`≡the old `k`) — including the "nothing switched off ⇒ value ≡ n, a true no-op" case.
/// `originOverride`, mirroring `clockDrawnPhase`, lets a driver's whole tick-search window pin every candidate to
/// ONE shared span-origin (see that function's own doc comment for why).
/// KILL STEP's precomputed transform table (Paul 2026-09-27) — shared by SnapshotBuilder (the render resolve) and
/// GridUI (the editor's live-playhead preview), so the two can never independently drift (the RATCHET PATTERN/DEST
/// lesson: never derive a matrix's own clock separately from the one the render side actually reads). `modes` must
/// already be padded to the row's step count (the caller's own concern, mirroring `clockDrawnResolveRatios`'s
/// contract). See `killStepPhase`'s doc comment below for what the returned table means.
func killStepResolveTable(_ modes: [KillStepMode], pauseLen: Int) -> (columnMap: [Int], columnsPerLap: Int, firstSlot: [Int]) {
    var onIdx = (0..<modes.count).filter { modes[$0] != .drop }
    if onIdx.isEmpty { onIdx = Array(0..<modes.count) }   // all-DROP falls back to all-steps (never silent/undefined)
    var map: [Int] = []
    var firstSlot = Array(repeating: -1, count: modes.count)
    for i in onIdx {
        if firstSlot[i] < 0 { firstSlot[i] = map.count }
        let reps = modes[i] == .pause ? 1 + max(0, pauseLen) : 1
        for _ in 0..<reps { map.append(i) }
    }
    return (map, map.count, firstSlot)
}
func killStepPhase(_ beat: Double, columnMap: [Int], columnsPerLap: Int, steps: Int, rateBeats: Double, periodBeats P: Double, originOverride: Double? = nil) -> Double {
    guard steps > 0, rateBeats > 0, columnsPerLap > 0, columnsPerLap <= columnMap.count else { return beat }
    let originBeat = originOverride ?? (P > 0 ? columnStart(beat, P) : 0)
    let localOffset = beat - originBeat
    let nD = (localOffset / rateBeats).rounded(.down)
    let withinCol = localOffset - nD * rateBeats                 // in [0, rateBeats)
    let n = Int(nD)
    let lap = Int((Double(n) / Double(columnsPerLap)).rounded(.down))
    let j = n - lap * columnsPerLap                               // posMod(n, columnsPerLap), in [0, columnsPerLap)
    let value = lap * steps + columnMap[j]
    return originBeat + Double(value) * rateBeats + withinCol
}

/// The inverse of `killStepPhase`. Since the forward map DELETES dropped columns from local time (a genuine gap,
/// unlike CLOCK's everywhere-invertible ratio warp) and can additionally FREEZE on a paused one, a local beat that
/// lands on a step index that never occurs — routine, not an edge case, since a downstream driver's own tick grid
/// runs at ITS rate, generally not KILL STEP's — has no real beat that produced it. POLICY (documented, not a bug,
/// unchanged from before): snap it FORWARD to the start of the next real occurrence, so a tick that would have
/// spoken during a dropped step instead speaks promptly once real content resumes — "downstream jumps past that
/// step," read from the receiving end. `firstSlot[step]` (SnapshotBuilder) is the table's FIRST slot for that step,
/// or −1 if the step is DROP (never occurs). Whenever the local beat DOES land on a real occurrence, the inverse is
/// exact — `killStepPhase(killStepPhaseInverse(v, …), …) == v` at those points, same guarantee as before.
func killStepPhaseInverse(_ localBeat: Double, originBeat: Double, columnMap: [Int], columnsPerLap: Int, firstSlot: [Int], steps: Int, rateBeats: Double) -> Double {
    guard steps > 0, rateBeats > 0, columnsPerLap > 0 else { return localBeat }
    let localOffset = localBeat - originBeat
    let valueD = (localOffset / rateBeats).rounded(.down)
    let withinCol = localOffset - valueD * rateBeats              // in [0, rateBeats)
    let value = Int(valueD)
    let lap = Int((Double(value) / Double(steps)).rounded(.down))
    let e = value - lap * steps                                   // posMod(value, steps), in [0, steps)
    var s = e, best = -1
    while s < steps { if s < firstSlot.count && firstSlot[s] >= 0 { best = s; break }; s += 1 }   // the smallest real step AT/AFTER e within this lap…
    let n = best >= 0 ? lap * columnsPerLap + firstSlot[best] : (lap + 1) * columnsPerLap          // …else snap to the next lap's first real slot
    return originBeat + Double(n) * rateBeats + withinCol
}

/// THE DRIFT READOUT (Paul 2026-09-26, "honesty replaces the guarantee" — NARROWED same day by the elastic-landing
/// fix, then narrowed AGAIN to accelerating-only once that fix proved audibly unsafe for decelerations — see
/// `clockDrawnGlideAdvance`'s doc): a DRAWN lane's net time gained/lost per full lap, in BEATS (positive ⇒ the lane
/// runs ahead of grid time; negative ⇒ behind). Zero exactly when the lane's per-column CHECKPOINT values (each
/// glide column's own interpolated `to`, per `clockDrawnGlideEndpoints` — a mid-span glide reads its own slice, not
/// the span's final target) average to 1 across the lap. An ACCELERATING glide step no longer contributes any
/// extra drift purely from CHOOSING glide over SET (`clockDrawnColumnAdvance` makes those byte-identical); a
/// DECELERATING glide step still can — this readout is the honest way to see it, exactly as it always was for that
/// direction. So a lane can show non-zero drift either because it's genuinely, deliberately authored to run faster/
/// slower than real time on average, OR because it contains a decelerating glide — the readout doesn't distinguish
/// the two, same as before this whole "in sync" fix existed. Pure.
func clockDrawnDriftPerLap(_ ratios: [Double], glide: [Bool], steps: Int, rateBeats: Double) -> Double {
    guard steps > 0, !ratios.isEmpty else { return 0 }
    var lapAdvance = 0.0
    for i in 0..<steps { lapAdvance += clockDrawnColumnAdvance(i, ratios: ratios, glide: glide, steps: steps, rateBeats: rateBeats) }
    return lapAdvance - Double(steps) * rateBeats
}

/// Piano-roll LANE for a MIDI note: C2…C6 (36…84) → 0…1, clamped. Shared by the perform-grid + BUILD-grid piano-roll
/// faces so the pitch→lane mapping never drifts between them. (Paul 2026-08-19)
@inline(__always) func rollLaneForPitch(_ note: Int) -> Double { clamp(Double(note - 36) / 48.0, 0, 1) }

/// The splitmix64 finalizing avalanche — mixes a seed into a well-distributed 64-bit hash. Shared by the
/// loop-consistent RANDOM arp position and the per-note CHANCE gate so the two can't drift.
@inline(__always) func splitmix64Mix(_ x: UInt64) -> UInt64 {
    var h = x
    h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
    h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
    h ^= (h >> 31)
    return h
}

// MARK: - THE MOD PROCESSOR (CC generator, delta) — pure, beat-derived, replay-safe shape values.

/// The unipolar [0,1] value of a CC shape at `phase` (0…1 through the LFO period). SINE = (1+sin)/2 · RAMP = the
/// phase (rising saw) · S&H = a value HELD for the whole cycle, seeded by (column, cc, cycleIndex) so it's
/// REPLAY-SAFE (same beat → same value; no free-running state). Pure.
@inline(__always)
func modUnipolar(_ shape: ModShape, phase: Double, column: Int, cc: Int, cycleIndex: Int) -> Double {
    let p = positiveFract(phase)
    switch shape {
    case .sine:     return (1 + sin(2 * Double.pi * p)) / 2
    case .triangle: return 1 - abs(2 * p - 1)                 // 0 → 1 → 0 (peak at mid-cycle)
    case .square:   return p < 0.5 ? 1 : 0
    case .ramp:     return p
    case .sampleHold:
        let seed = (UInt64(bitPattern: Int64(cycleIndex)) &* 0x9E3779B97F4A7C15)
                 ^ (UInt64(column & 0xFF) &<< 8) ^ UInt64(cc & 0x7F)
        return Double(splitmix64Mix(seed) >> 11) / Double(UInt64(1) << 53)   // [0,1)
    }
}
/// Map a unipolar [0,1] onto [min,max] as a CC value (0…127). MIN > MAX inverts. The universal row-3 mapping every
/// MOD source runs through (SHAPE · FOLLOW · STEPS · STRIKE · EXTERN). Pure.
@inline(__always)
func modMap(_ s: Double, min lo: Int, max hi: Int) -> Int {
    max(0, min(127, Int((Double(lo) + max(0, min(1, s)) * Double(hi - lo)).rounded())))
}
/// QUANTIZE (design-cc-stage §14①): snap a 0…127 CC value to `levels` evenly-spaced steps — bit-crush for control
/// (stepped filter sweeps from any source). levels ≤ 1 = off (identity). Pure. (Paul 2026-09-09.)
@inline(__always)
func modQuantizeValue(_ value: Int, levels: Int) -> Int {
    guard levels >= 2 else { return value }
    let n = Double(min(32, levels) - 1)                       // e.g. 4 levels → points at 0, 42, 85, 127
    let idx = (Double(value) / 127.0 * n).rounded()           // nearest level index
    return max(0, min(127, Int((idx / n * 127.0).rounded())))
}
// (paramLFOValue REMOVED 2026-09-16 — the depth/phase/quantize LFO model it computed was retired in the FROM→TO editor
//  redesign; the live engine now sweeps via modUnipolar + from/to interpolation in Router.applyParamLFO. Was test-only.)

/// FOLLOW (CC-stage §1) — the unipolar [0,1] the CC tracks from the sounding material. COUNT = held-note count /8 ·
/// REGISTER = mean pitch mapped C1…C7 · VEL = mean velocity /127 · DENSITY = a busyness proxy (pool fullness, v1). Pure.
@inline(__always)
func modFollowUnipolar(_ what: ModFollow, count: Int, meanNote: Double, meanVel: Double) -> Double {
    switch what {
    case .count:    return Swift.min(1, Double(count) / 8.0)
    case .register: return count == 0 ? 0 : Swift.max(0, Swift.min(1, (meanNote - 24) / 72.0))   // C1(24)…C7(96)
    case .vel:      return count == 0 ? 0 : Swift.max(0, Swift.min(1, meanVel / 127.0))
    case .density:  return Swift.min(1, Double(count) / 8.0)   // v1 proxy = pool fullness (true event-rate density = a follow-up)
    }
}

/// STEPS (CC-stage §1) — the unipolar value at `phase` (0…1) across the 8-step pattern. STEP holds each step; SMOOTH
/// interpolates to the next (wrapping). Pure.
@inline(__always)
func modStepsUnipolar(_ steps: [Int], phase: Double, smooth: Bool) -> Double {
    let n = steps.count                                   // 8 (PERIOD/ROW), 16 (ROW×2) or 32 (ROW×4)
    guard n >= 1 else { return 0 }
    let p = positiveFract(phase) * Double(n)
    let i = Swift.min(n - 1, Int(p)); let frac = p - Double(i)
    let a = Double(steps[i]) / 127.0
    if !smooth { return a }
    let b = Double(steps[(i + 1) % n]) / 127.0
    return a + (b - a) * frac
}

/// The common name of a CC number (the CC-stage §1 "named dozen"), or nil for an unnamed controller. Pure/testable;
/// drives the labelled CC picker ("74 · CUTOFF").
func ccName(_ n: Int) -> String? {
    switch n {
    case 1:  return "MOD WHEEL"
    case 2:  return "BREATH"
    case 5:  return "PORTA TIME"
    case 7:  return "VOLUME"
    case 10: return "PAN"
    case 11: return "EXPRESSION"
    case 64: return "SUSTAIN"
    case 65: return "PORTAMENTO"
    case 71: return "RESONANCE"
    case 72: return "RELEASE"
    case 73: return "ATTACK"
    case 74: return "CUTOFF"
    case 91: return "REVERB"
    case 93: return "CHORUS"
    default: return nil
    }
}

/// CONTROLLER ROUTING (v1): the union emitter mask (A–D) an incoming controller forwards to — the OR of the
/// CONTROLLERS masks of every door that HEARS it (channel + cable). Pure/testable.
func controllerForwardMask(hearing: [Bool], masks: [UInt8]) -> UInt8 {
    var m: UInt8 = 0
    for i in 0..<min(hearing.count, masks.count) where hearing[i] { m |= masks[i] }
    return m & 0b1111
}

/// True if a status byte is a channel CONTROLLER we re-route (CC · Program Change · Channel Pressure/AT · Pitch Bend).
/// Poly-pressure (0xA0) is parked with MPE. Pure.
func isForwardableController(_ status: UInt8) -> Bool {
    let s = status & 0xF0
    return s == 0xB0 || s == 0xC0 || s == 0xD0 || s == 0xE0
}

// MARK: - GLIDE (notes→pitch-bend translator) — pure math.

/// The 14-bit pitch-bend value (0…16383, 8192 = centre) for `semitones` of bend within a ±`range`-semitone span.
/// Clamped to the wheel's limits. Pure. (GLIDE / the future BEND stage.)
@inline(__always)
func glideBend14(semitones: Double, range: Int) -> Int {
    let r = Double(max(1, range))
    let frac = max(-1, min(1, semitones / r))
    return max(0, min(16383, Int((8192.0 + frac * 8191.0).rounded())))
}

/// TRUE when a glide target is beyond the bend RANGE from the anchor → the note must RE-ANCHOR (or clamp). Pure.
@inline(__always)
func glideNeedsReanchor(target: Int, anchor: Int, range: Int) -> Bool { abs(target - anchor) > range }

/// GLIDE SYNTH mode (Paul 2026-08-22): map the glide TIME (beats) to a CC5 portamento-time value (0…127). Synth-
/// specific in reality, so this is a reasonable first-pass linear scaling (0.25 beat → ~6, ≥5.3 beats → 127). Pure.
func glideSynthCCTime(_ beats: Double) -> Int { max(0, min(127, Int((beats * 24.0).rounded()))) }

/// The "standard" resting value of a CC — what a MOD target reverts to when ABANDONED (the CC# swept past it). Volume
/// / expression / cutoff → full · pan / balance → centre · everything else → off. Pure. (So sweeping the target knob
/// past CC7 doesn't leave the synth's volume knocked down — user 2026-08-10.)
func ccDefault(_ cc: Int) -> Int {
    switch cc {
    case 7, 11: return 127   // volume · expression
    case 74:    return 127   // cutoff / brightness — full = filter effectively off
    case 8, 10: return 64    // balance · pan — centre
    default:    return 0
    }
}

/// STRIKE (CC-stage §1, v1 per-ENTRY) — an ATTACK→RELEASE envelope, `t` beats since the trigger (column entry).
/// Rises 0→1 over `attack`, falls 1→0 over `release`, then rests at 0. Pure.
@inline(__always)
func modStrikeUnipolar(t: Double, attack: Double, release: Double) -> Double {
    guard t >= 0 else { return 0 }
    let a = Swift.max(0.001, attack), r = Swift.max(0.001, release)
    if t < a { return t / a }
    let d = t - a
    return d < r ? 1 - d / r : 0
}


// MARK: - The source pool (§2.5): omni, keyed by note number

/// The live held-note pool. All input channels merge (omni, §2.5) — note number is the key — but
/// each note's originating channel is remembered for INHERIT stamping (§2.6). Fixed capacity, no
/// allocation after init. A class so the Kernel (writer) and Router (reader) share one instance
/// with no copies on the hot path.
final class NotePool {
    // A FROZEN pool (LATCH / REPLAY / FILE) is already door-filtered (channel + cable + range) at CAPTURE, so a cell
    // reading it must NOT re-apply the door filter — else a LATER channel/range edit drops the frozen notes (the
    // "replay stops when I disable the input channel" bug). When true, `srcCount/srcAscending(for:)` and
    // `arpPickSource(for:)` skip the door filter (OMNI channel/cable/full-range) but STILL apply the cell's velocity
    // window + chord split (cell processing, not door admission). false for the live pool → filtered as before.
    // (Paul 2026-08-23; mirrors the BYPASS path's `latched ? 0 : receiverChannels` read.)
    var omniRead = false
    private var vel = [UInt8](repeating: 0, count: 128)   // velocity by note (0 = not held)
    private var chan = [UInt8](repeating: 0, count: 128)  // originating channel by note
    private var cbl = [UInt8](repeating: 0, count: 128)   // §item 11: originating input cable (1–4; 0 = untagged)
    private(set) var sorted = [UInt8](repeating: 0, count: 128)
    private(set) var count = 0

    // Press order, for the AS-PLAYED arp pattern — the one thing the note-indexed views above lose.
    // Maintained incrementally: a genuinely new note appends; releasing one compacts it out; a
    // re-press of a still-held note keeps its original slot. playedCount == count (same held set).
    private var order = [UInt8](repeating: 0, count: 128)
    private(set) var playedCount = 0

    func reset() {
        for i in 0..<128 { vel[i] = 0; chan[i] = 0; cbl[i] = 0 }
        count = 0
        playedCount = 0
    }

    /// A VALUE snapshot of the held state (Paul 2026-09-03) — for the OFFLINE part-roll render: the caller clones the live
    /// pool on the main thread (a benign torn read of the flat UInt8 arrays, the 2026-08-10 class) and runs a fresh Router
    /// against the stable copy, so a mid-run change on the render thread can't garble the pass.
    func clone() -> NotePool {
        let p = NotePool()
        p.omniRead = omniRead
        for i in 0..<128 { p.vel[i] = vel[i]; p.chan[i] = chan[i]; p.cbl[i] = cbl[i]; p.order[i] = order[i] }
        p.count = count; p.playedCount = playedCount
        p.rebuildSorted()
        return p
    }

    func noteOn(_ note: UInt8, velocity: UInt8, channel: UInt8, cable: UInt8 = 0) {
        let n = Int(note)
        if velocity > 0 {
            if vel[n] == 0 {
                count += 1
                if playedCount < 128 { order[playedCount] = note; playedCount += 1 }
            }
            vel[n] = velocity
            chan[n] = channel
            cbl[n] = cable
        } else {
            noteOff(note)
        }
    }

    func noteOff(_ note: UInt8) {
        let n = Int(note)
        if vel[n] != 0 {
            count -= 1
            removeFromOrder(note)
        }
        vel[n] = 0
    }

    private func removeFromOrder(_ note: UInt8) {
        var i = 0
        while i < playedCount && order[i] != note { i += 1 }
        guard i < playedCount else { return }
        for j in i..<(playedCount - 1) { order[j] = order[j + 1] }
        playedCount -= 1
    }

    @inline(__always) func played(at index: Int) -> UInt8 { order[index] }   // AS-PLAYED lookup
    @inline(__always) func velocity(_ note: UInt8) -> UInt8 { vel[Int(note)] }   // held velocity (0 = not held)

    // MARK: - input-channel filter (delta §7): a MIDI-IN cell hears only its channel. `filter` is
    // 0 = OMNI (all held notes) or 1–16 (only notes arriving on that channel; wire channel = filter−1).
    // OMNI paths return the existing OMNI views in O(1); a real filter scans (≤128, source reads only).

    // §item 11 INPUT CABLES: admission is CHANNEL and CABLE. `cableMask` (bit i = cable i+1) defaults to
    // ANY (0b1111) so every existing call is unchanged; a cabled receiver passes its own mask.
    @inline(__always) private func matches(_ note: UInt8, _ filter: UInt8, _ cableMask: Int) -> Bool {
        (filter == 0 || chan[Int(note)] == filter - 1)
            && receiverHearsCable(mask: cableMask, eventCable: Int(cbl[Int(note)]))
    }
    // MULTI-CHANNEL (Paul 2026-08-21): a door can hear an arbitrary SUBSET of channels — a 16-bit mask (bit c = channel
    // c+1). 0xFFFF = all (OMNI). The single-channel `matches` above stays as the fast/OMNI path; a cell carrying a
    // non-full mask reads through these. `chanMaskOf` expands the legacy single filter, so the two agree exactly.
    @inline(__always) private func matchesMask(_ note: UInt8, _ chanMask: UInt16, _ cableMask: Int) -> Bool {
        (chanMask & (UInt16(1) << UInt16(chan[Int(note)]))) != 0
            && receiverHearsCable(mask: cableMask, eventCable: Int(cbl[Int(note)]))
    }
    func srcCount(chanMask: UInt16, cableMask: Int = 0b1111) -> Int {
        if chanMask == 0xFFFF && cableMask == 0b1111 { return count }
        var n = 0; for i in 0..<count where matchesMask(sorted[i], chanMask, cableMask) { n += 1 }; return n
    }
    func srcAscending(_ k: Int, chanMask: UInt16, cableMask: Int = 0b1111) -> UInt8 {
        if chanMask == 0xFFFF && cableMask == 0b1111 { return k < count ? sorted[k] : 255 }
        var seen = 0
        for i in 0..<count where matchesMask(sorted[i], chanMask, cableMask) { if seen == k { return sorted[i] }; seen += 1 }
        return 255
    }
    func srcCount(chanMask: UInt16, cableMask: Int, velLo: UInt8, velHi: UInt8, noteLo: UInt8, noteHi: UInt8) -> Int {
        var n = 0
        for i in 0..<count where matchesMask(sorted[i], chanMask, cableMask) {
            let note = sorted[i]; guard note >= noteLo && note <= noteHi else { continue }
            let v = vel[Int(note)]; if v >= velLo && v <= velHi { n += 1 }
        }
        return n
    }
    func srcAscending(_ k: Int, chanMask: UInt16, cableMask: Int, velLo: UInt8, velHi: UInt8, noteLo: UInt8, noteHi: UInt8) -> UInt8 {
        var seen = 0
        for i in 0..<count where matchesMask(sorted[i], chanMask, cableMask) {
            let note = sorted[i]; guard note >= noteLo && note <= noteHi else { continue }
            let v = vel[Int(note)]; guard v >= velLo && v <= velHi else { continue }
            if seen == k { return note }; seen += 1
        }
        return 255
    }

    /// BYPASS: the held velocity of a note (0 = not held). Public read for the Router's direct-injection pass.
    func heldVelocity(_ note: UInt8) -> UInt8 { vel[Int(note)] }
    func heldChannel(_ note: UInt8) -> UInt8 { chan[Int(note)] }   // §3 key filter reads these to preserve a remapped note's origin
    func heldCable(_ note: UInt8) -> UInt8 { cbl[Int(note)] }

    /// ALL sounding notes' pitch classes (no filter) — the reference set when a door's OWN pool IS the key reference (a
    /// SCALE / KEYS / latched door's frozen pool). Pure; no sort needed (reads vel[] directly). (ratified §3)
    func pitchClassMaskAll() -> UInt16 {
        var m: UInt16 = 0
        for n in 0..<128 where vel[n] != 0 { m |= UInt16(1) << UInt16(n % 12) }
        return m
    }
    /// KEYS EXCLUDE (Paul 2026-08-22): the 12-bit PITCH-CLASS mask of the notes currently held on a door's filter —
    /// the complement door subtracts these from its typed set. Pure. Requires rebuildSorted() first (like srcCount).
    func pitchClassMask(chanMask: UInt16, cableMask: Int, noteLo: UInt8, noteHi: UInt8) -> UInt16 {
        var m: UInt16 = 0
        let c = srcCount(chanMask: chanMask, cableMask: cableMask, velLo: 0, velHi: 127, noteLo: noteLo, noteHi: noteHi)
        for k in 0..<c {
            let n = srcAscending(k, chanMask: chanMask, cableMask: cableMask, velLo: 0, velHi: 127, noteLo: noteLo, noteHi: noteHi)
            if n <= 127 { m |= UInt16(1) << UInt16(Int(n) % 12) }
        }
        return m
    }
    /// Count of held notes passing the filter.
    func srcCount(filter: UInt8, cableMask: Int = 0b1111) -> Int {
        if filter == 0 && cableMask == 0b1111 { return count }
        var n = 0
        for i in 0..<count where matches(sorted[i], filter, cableMask) { n += 1 }
        return n
    }

    /// The k-th ascending held note passing the filter (k in 0..<srcCount). 255 if out of range.
    func srcAscending(_ k: Int, filter: UInt8, cableMask: Int = 0b1111) -> UInt8 {
        if filter == 0 && cableMask == 0b1111 { return k < count ? sorted[k] : 255 }
        var seen = 0
        for i in 0..<count where matches(sorted[i], filter, cableMask) {
            if seen == k { return sorted[i] }
            seen += 1
        }
        return 255
    }

    /// The k-th press-order held note passing the filter (k in 0..<srcCount). 255 if out of range.
    func srcPlayed(_ k: Int, filter: UInt8, cableMask: Int = 0b1111) -> UInt8 {
        if filter == 0 && cableMask == 0b1111 { return k < playedCount ? order[k] : 255 }
        var seen = 0
        for i in 0..<playedCount where matches(order[i], filter, cableMask) {
            if seen == k { return order[i] }
            seen += 1
        }
        return 255
    }
    // RANGE (§2): press-order read within a note window — the AS-PLAYED arp variant (press order preserved).
    func srcPlayed(_ k: Int, filter: UInt8, cableMask: Int, noteLo: UInt8, noteHi: UInt8) -> UInt8 {
        var seen = 0
        for i in 0..<playedCount where matches(order[i], filter, cableMask) {
            let note = order[i]; guard note >= noteLo && note <= noteHi else { continue }
            if seen == k { return note }; seen += 1
        }
        return 255
    }
    // MULTI-CHANNEL (Paul 2026-08-23): the AS-PLAYED reads by a channel MASK — so an arp honours a door's multi-channel
    // subset on LIVE input (not just the legacy single channel). chanMask 0xFFFF = OMNI.
    func srcPlayed(_ k: Int, chanMask: UInt16, cableMask: Int = 0b1111) -> UInt8 {
        var seen = 0
        for i in 0..<playedCount where matchesMask(order[i], chanMask, cableMask) {
            if seen == k { return order[i] }; seen += 1
        }
        return 255
    }
    func srcPlayed(_ k: Int, chanMask: UInt16, cableMask: Int, noteLo: UInt8, noteHi: UInt8) -> UInt8 {
        var seen = 0
        for i in 0..<playedCount where matchesMask(order[i], chanMask, cableMask) {
            let note = order[i]; guard note >= noteLo && note <= noteHi else { continue }
            if seen == k { return note }; seen += 1
        }
        return 255
    }

    // §item 11: convenience readers — pull BOTH filter fields (channel + cable) off a SnapCell in one
    // place, so the render loop's ~dozen source-pick sites can't drift the (inputChannel, inputCableMask)
    // pairing. The base filter-taking methods stay for the preview/audition paths (which force a filter).
    // §cell-edit D velocity-aware base + RANGE (§2) note window — channel/cable filter AND velocity ∈ [velLo, velHi]
    // AND note ∈ [noteLo, noteHi]. Only reached when a cell's vel window OR its receiver's note window is narrower
    // than full (the full-both path keeps the original fast readers above).
    func srcCount(filter: UInt8, cableMask: Int, velLo: UInt8, velHi: UInt8, noteLo: UInt8, noteHi: UInt8) -> Int {
        var n = 0
        for i in 0..<count where matches(sorted[i], filter, cableMask) {
            let note = sorted[i]; guard note >= noteLo && note <= noteHi else { continue }
            let v = vel[Int(note)]; if v >= velLo && v <= velHi { n += 1 }
        }
        return n
    }
    func srcAscending(_ k: Int, filter: UInt8, cableMask: Int, velLo: UInt8, velHi: UInt8, noteLo: UInt8, noteHi: UInt8) -> UInt8 {
        var seen = 0
        for i in 0..<count where matches(sorted[i], filter, cableMask) {
            let note = sorted[i]; guard note >= noteLo && note <= noteHi else { continue }
            let v = vel[Int(note)]; guard v >= velLo && v <= velHi else { continue }
            if seen == k { return note }; seen += 1
        }
        return 255
    }
    // The cell's admitted source = channel/cable + VELOCITY WINDOW (§cell-edit D) + RANGE note window (§2). Both
    // full → the fast readers; either narrower → the combined reader.
    private func srcCountFiltered(_ cell: SnapCell) -> Int {
        (cell.velFloor <= 1 && cell.velCeil >= 127 && cell.inputRangeLo <= 0 && cell.inputRangeHi >= 127)
            ? srcCount(chanMask: cell.inputChanMask, cableMask: Int(cell.inputCableMask))
            : srcCount(chanMask: cell.inputChanMask, cableMask: Int(cell.inputCableMask),
                       velLo: cell.velFloor, velHi: cell.velCeil, noteLo: cell.inputRangeLo, noteHi: cell.inputRangeHi)
    }
    private func srcAscendingFiltered(_ k: Int, _ cell: SnapCell) -> UInt8 {
        (cell.velFloor <= 1 && cell.velCeil >= 127 && cell.inputRangeLo <= 0 && cell.inputRangeHi >= 127)
            ? srcAscending(k, chanMask: cell.inputChanMask, cableMask: Int(cell.inputCableMask))
            : srcAscending(k, chanMask: cell.inputChanMask, cableMask: Int(cell.inputCableMask),
                           velLo: cell.velFloor, velHi: cell.velCeil, noteLo: cell.inputRangeLo, noteHi: cell.inputRangeHi)
    }
    // omniRead (FROZEN pool): skip the door filter (OMNI channel/cable/full-range — the pool was door-filtered at
    // capture) but KEEP the cell's velocity window (cell processing).
    private func srcCntFilt(_ cell: SnapCell) -> Int {
        if !omniRead { return srcCountFiltered(cell) }
        return cell.velFloor <= 1 && cell.velCeil >= 127 ? srcCount(filter: 0, cableMask: 0b1111)
            : srcCount(filter: 0, cableMask: 0b1111, velLo: cell.velFloor, velHi: cell.velCeil, noteLo: 0, noteHi: 127)
    }
    private func srcAscFilt(_ k: Int, _ cell: SnapCell) -> UInt8 {
        if !omniRead { return srcAscendingFiltered(k, cell) }
        return cell.velFloor <= 1 && cell.velCeil >= 127 ? srcAscending(k, filter: 0, cableMask: 0b1111)
            : srcAscending(k, filter: 0, cableMask: 0b1111, velLo: cell.velFloor, velHi: cell.velCeil, noteLo: 0, noteHi: 127)
    }
    // Full per-cell source read: velocity window (admission), THEN the chord split (a window on that list). omniRead
    // frozen pools skip the door filter (see `srcCntFilt`); the live pool is byte-identical (omniRead == false).
    func srcCount(for cell: SnapCell) -> Int {
        let base = srcCntFilt(cell)
        if cell.chordSplit.mode == .all { return base }
        return chordSplitWindow(count: base, split: cell.chordSplit) { Int(srcAscFilt($0, cell)) }.len
    }
    func srcAscending(_ k: Int, for cell: SnapCell) -> UInt8 {
        if cell.chordSplit.mode == .all { return srcAscFilt(k, cell) }
        let base = srcCntFilt(cell)
        let start = chordSplitWindow(count: base, split: cell.chordSplit) { Int(srcAscFilt($0, cell)) }.start
        return srcAscFilt(start + k, cell)
    }

    /// Rebuild the ascending note list; also re-derives `count` (belt-and-braces vs the incremental
    /// count, matching the pre-split behaviour).
    func rebuildSorted() {
        var n = 0
        for note in 0..<128 where vel[note] != 0 { sorted[n] = UInt8(note); n += 1 }
        count = n
    }

    /// receiver strip LATCH: FREEZE — replace this pool's contents with the notes of `src` passing
    /// (filter, cableMask), preserving each note's velocity/channel/cable so a subscriber's own filter is a
    /// no-op pass-through on the frozen chord. Allocation-free (fixed arrays); safe on the render thread.
    func captureFiltered(from src: NotePool, filter: UInt8, cableMask: Int, noteLo: UInt8 = 0, noteHi: UInt8 = 127) {
        reset()
        for i in 0..<src.count {
            let note = src.sorted[i]
            if note >= noteLo && note <= noteHi && src.matches(note, filter, cableMask) {   // RANGE (§2) upstream of latch
                noteOn(note, velocity: src.vel[Int(note)], channel: src.chan[Int(note)], cable: src.cbl[Int(note)])
            }
        }
        rebuildSorted()
    }

    /// TWO LATCH MODES — ADD (note-toggle accumulation): one render's step for an armed ADD receiver, applied
    /// to `self` (the frozen pool). Each note whose FILTERED hold RISES this render — held now, not held last
    /// render — TOGGLES its membership: present ⇒ removed, absent ⇒ added at the live note's velocity (channel/
    /// cable preserved, so a subscriber's own filter is a no-op pass-through, exactly like `captureFiltered`).
    /// `prevHeld` (128 flags, caller-owned + preallocated) carries the held state across renders for rising-edge
    /// detection. Allocation-free (fixed 0…127 sweep); safe on the render thread.
    func latchAddStep(from live: NotePool, filter: UInt8, cableMask: Int, noteLo: UInt8 = 0, noteHi: UInt8 = 127, prevHeld: inout [Bool]) {
        for n in 0..<128 {
            let note = UInt8(n)
            let held = live.vel[n] != 0 && note >= noteLo && note <= noteHi && live.matches(note, filter, cableMask)   // RANGE (§2) upstream of latch
            if held && !prevHeld[n] {                       // rising edge → toggle membership
                if vel[n] != 0 { noteOff(note) }            // already in the frozen pool → leave
                else { noteOn(note, velocity: live.vel[n], channel: live.chan[n], cable: live.cbl[n]) }   // → join
            }
            prevHeld[n] = held
        }
        rebuildSorted()
    }
    // MULTI-CHANNEL (Paul 2026-08-21): the mask twins of the latch-capture readers — a door hearing a channel SUBSET
    // freezes from all its channels. Byte-identical to the single-filter versions for OMNI (0xFFFF) / a single channel.
    func captureFiltered(from src: NotePool, chanMask: UInt16, cableMask: Int, noteLo: UInt8 = 0, noteHi: UInt8 = 127) {
        reset()
        for i in 0..<src.count {
            let note = src.sorted[i]
            if note >= noteLo && note <= noteHi && src.matchesMask(note, chanMask, cableMask) {
                noteOn(note, velocity: src.vel[Int(note)], channel: src.chan[Int(note)], cable: src.cbl[Int(note)])
            }
        }
        rebuildSorted()
    }
    /// The 128-bit MASK of admitted notes (lo = notes 0…63, hi = 64…127), filtered exactly like `captureFiltered`. Used by
    /// HOLD to detect a NEW chord by note IDENTITY (added/removed notes) rather than count — so a same-size swap or a
    /// within-block release+restrike is caught. (Paul 2026-08-31.)
    func admittedMask(chanMask: UInt16, cableMask: Int, noteLo: UInt8 = 0, noteHi: UInt8 = 127) -> (UInt64, UInt64) {
        var lo: UInt64 = 0, hi: UInt64 = 0
        for i in 0..<count {
            let note = sorted[i]
            if note >= noteLo && note <= noteHi && matchesMask(note, chanMask, cableMask) {
                if note < 64 { lo |= UInt64(1) << UInt64(note) } else { hi |= UInt64(1) << UInt64(note - 64) }
            }
        }
        return (lo, hi)
    }
    func latchAddStep(from live: NotePool, chanMask: UInt16, cableMask: Int, noteLo: UInt8 = 0, noteHi: UInt8 = 127, prevHeld: inout [Bool]) {
        for n in 0..<128 {
            let note = UInt8(n)
            let held = live.vel[n] != 0 && note >= noteLo && note <= noteHi && live.matchesMask(note, chanMask, cableMask)
            if held && !prevHeld[n] {
                if vel[n] != 0 { noteOff(note) }
                else { noteOn(note, velocity: live.vel[n], channel: live.chan[n], cable: live.cbl[n]) }
            }
            prevHeld[n] = held
        }
        rebuildSorted()
    }
    /// ADDITIVE filtered copy — merge `src`'s admitted notes INTO this pool WITHOUT clearing it (unlike captureFiltered).
    /// Plays LIVE input alongside a FROZEN source: for KEYS/REPLAY/FILE the door's enabled channels feed the grid ON TOP
    /// of the loop/clip/keyboard (Paul 2026-08-23). Channel-preserving; a pitch already present is overwritten by live
    /// (last-writer, harmless — the pool is note-indexed, so a duplicate is one entry either way). Rebuilds the sorted view.
    func mergeFiltered(from src: NotePool, chanMask: UInt16, cableMask: Int, noteLo: UInt8 = 0, noteHi: UInt8 = 127) {
        for i in 0..<src.count {
            let note = src.sorted[i]
            if note >= noteLo && note <= noteHi && src.matchesMask(note, chanMask, cableMask) {
                noteOn(note, velocity: src.vel[Int(note)], channel: src.chan[Int(note)], cable: src.cbl[Int(note)])
            }
        }
        rebuildSorted()
    }
}

enum HoldCapture { case replace, union, keep }
/// HOLD's per-render capture decision (PURE, so it's testable off-device — the Kernel just wires it to the live/frozen pools).
/// Given the PREVIOUS admitted note set, the CURRENT admitted set, and whether a release is pending (`releasing`), decide:
///   • REPLACE — a NEW chord: a note ADDED after a RELEASE (a removal this render OR a pending one) → freeze the current set.
///   • UNION   — the same chord still FORMING: an add with no release → accumulate (staggered/rolled onset builds up).
///   • KEEP    — no note added → hold the frozen chord.
/// Returns the action + the new `releasing` flag. Catches a same-size SWAP and a within-block release+restrike (both change
/// the SET even when the COUNT is unchanged). LIMITATION: a LEGATO change where the new chord fully sounds BEFORE the old is
/// released (no removal precedes the add) is indistinguishable from adding to the chord → UNION (documented). (Paul 2026-08-31.)
func holdCaptureDecision(prevLo: UInt64, prevHi: UInt64, curLo: UInt64, curHi: UInt64, releasing: Bool) -> (action: HoldCapture, releasing: Bool) {
    let removed = (prevLo & ~curLo) != 0 || (prevHi & ~curHi) != 0
    let added   = (curLo & ~prevLo) != 0 || (curHi & ~prevHi) != 0
    let rel = releasing || removed
    if added { return (rel ? .replace : .union, false) }
    return (.keep, rel)
}

/// THE SCALE DOOR pool (ratified spec §1): every note of `type` rooted at `root` (0=C…11=B), realized ascending across
/// `octaves` octaves from the home octave `baseOct` (baseOct 3 → C3 = MIDI 48, the C-1 convention). Out-of-MIDI notes
/// drop. Pure/testable — the derived KEYS pool for a SCALE door (fed exactly like tapped piano notes). No allocation
/// concern (called off the render path, in the snapshot build).
func scaleNotes(root: Int, type: ScaleType, baseOct: Int, octaves: Int) -> [Int] {
    let r = (root % 12 + 12) % 12
    let base = max(0, min(8, baseOct)) * 12 + 12                 // C-1 convention: octave 3 → MIDI 48 (C3)
    let oct = max(1, min(4, octaves))
    var out: [Int] = []
    for o in 0..<oct {
        for i in type.intervals {
            let n = base + r + o * 12 + i
            if n >= 0 && n <= 127 { out.append(n) }
        }
    }
    return out                                                  // already ascending + distinct (intervals rise within an octave; octaves step by 12)
}

/// The allocation-free core of POOL-STEP (§2): the pool as a 12-bit PITCH-CLASS mask (`pitchClassMaskAll`). Degree
/// arithmetic over the set bits; O(12), no allocation — safe on the render path. Empty mask ⇒ semitone fallback.
func poolStepMask(_ note: Int, steps: Int, pcMask: UInt16) -> Int {
    let k = pcMask.nonzeroBitCount
    guard k > 0 else { return max(0, min(127, note + steps)) }
    let pc = ((note % 12) + 12) % 12
    let baseOct = (note - pc) / 12                                  // note = baseOct*12 + pc
    var i = -1, rank = 0                                            // pc's DEGREE index among the set bits
    for b in 0..<12 where (pcMask >> UInt16(b)) & 1 != 0 { if b == pc { i = rank }; rank += 1 }
    if i < 0 {                                                      // FOLD: anchor at the nearest set pitch class (down ties before up)
        var best = 0, bestDist = 99, r = 0
        for b in 0..<12 where (pcMask >> UInt16(b)) & 1 != 0 {
            let d = min((((b - pc) % 12) + 12) % 12, (((pc - b) % 12) + 12) % 12)
            if d < bestDist { bestDist = d; best = r }
            r += 1
        }
        i = best
    }
    let target = i + steps
    let deg = ((target % k) + k) % k
    let octShift = Int((Double(target) / Double(k)).rounded(.down))
    var pcOut = 0, r = 0                                            // the deg-th set pitch class
    for b in 0..<12 where (pcMask >> UInt16(b)) & 1 != 0 { if r == deg { pcOut = b; break }; r += 1 }
    return max(0, min(127, baseOct * 12 + pcOut + octShift * 12))
}

/// The 12-bit PITCH-CLASS mask of a declared key (root + scale) — the reference set for a KEY-referenced AVOID/LOCK stage.
/// Pure/testable. (2026-08-31)
func scalePitchClassMask(root: Int, scale: ScaleType) -> UInt16 {
    var m: UInt16 = 0
    for iv in scale.intervals { m |= UInt16(1) << UInt16((((root + iv) % 12) + 12) % 12) }
    return m
}
/// Widen a 12-bit pitch-class mask by ±`semis` semitones — every set class ALSO marks its neighbours. AVOID's "CLASHES":
/// don't just dodge the reference's exact notes, dodge the ones a semitone (ic1, semis 1) or tone (ic2, semis 2) away that
/// clash with it. semis 0 = unchanged. Pure/testable. (2026-08-31)
func widenClashMask(_ mask: UInt16, semis: Int) -> UInt16 {
    guard mask != 0, semis > 0 else { return mask }
    var out = mask
    for pc in 0..<12 where (mask >> UInt16(pc)) & 1 != 0 {
        for d in 1...semis {
            out |= UInt16(1) << UInt16((pc + d) % 12)
            out |= UInt16(1) << UInt16((pc + 12 - (d % 12)) % 12)
        }
    }
    return out
}
// MARK: - CHORDS (ratified 2026-09-01) — diatonic progressions DERIVED from a key by rank arithmetic. Pure core.

/// The CHORDS voicing/spread (SPEC-chords-stage §1).
enum ChordVoicing: String, Codable, CaseIterable { case triad, seventh, add9 }
enum ChordSpread: String, Codable, CaseIterable { case close, open }

/// A DIATONIC chord on `degree` (0=I … 6=vii) as STACKED THIRDS over a scale — pool-steps {deg, deg+2, deg+4} (+deg+6 for a
/// 7th · +deg+8 for add9). No chord is stored: quality falls out of the key (SPEC-chords-stage). `scaleTones` = the scale's
/// intervals from the root, ascending (e.g. major [0,2,4,5,7,9,11] = `ScaleType.intervals`); `rootNote` = the key-root MIDI
/// note (the octave anchor). Degrees past the top wrap by octave (rank arithmetic). Returns absolute MIDI notes, ascending,
/// clamped 0…127. `open` lifts the middle voice an octave (a spread voicing). Pure/testable.
func diatonicChord(degree deg: Int, scaleTones: [Int], rootNote: Int,
                   voicing: ChordVoicing = .triad, spread: ChordSpread = .close) -> [Int] {
    let n = scaleTones.count
    guard n > 0 else { return [] }
    func tone(_ k: Int) -> Int {                                    // the k-th scale degree (wraps by octave)
        let idx = ((k % n) + n) % n
        let oct = Int(floor(Double(k) / Double(n)))
        return rootNote + scaleTones[idx] + 12 * oct
    }
    var steps = [deg, deg + 2, deg + 4]                             // the triad — stacked thirds
    if voicing == .seventh || voicing == .add9 { steps.append(deg + 6) }
    if voicing == .add9 { steps.append(deg + 8) }
    var notes = steps.map(tone)
    if spread == .open && notes.count >= 3 { notes[1] += 12 }       // OPEN: octave-lift the middle voice
    return notes.map { max(0, min(127, $0)) }.sorted()
}

/// THE CHORD SEQUENCER derivation (Paul 2026-09-04): the diatonic chord at beat `m` for a CHORDS config, in a resolved key.
/// SHARED by the CHORDS PROCESSOR stage (Router.applyStage) AND the chord DOOR pool-fill (Kernel) so they can NEVER diverge —
/// this is the "future processor work reflects on the door" contract in one function. `step = floor(m / chordsRateBeats)`;
/// PATTERN reads the drawn matrix (active length = chordsSteps, CARRY/REST honoured), WALK the seeded gravity dice, FOLLOW
/// names the degree from `followNote` (nil ⇒ the tonic — a door with no play-along input sits on I). `root`/`scaleTones` are
/// the ALREADY-RESOLVED key (the caller reads the SCALE-FROM door or the card key). Returns ascending MIDI notes, [] on REST.
func chordSeqNotes(beat m: Double, _ p: SnapParams, keyRoot root: Int, keyTones scaleTones: [Int], followNote: Int?) -> [Int] {
    let rateBeats = p.chordsRateBeats > 0 ? p.chordsRateBeats : 4
    let step = Int((m / rateBeats).rounded(.down))
    var deg = 0, rest = false
    switch p.chordsMode {
    case .pattern:
        let steps = max(1, min(16, p.chordsSteps))
        let degs = (0..<steps).map { $0 < p.chordsDegrees.count ? p.chordsDegrees[$0] : -1 }
        (deg, rest) = chordsDegreeAt(step: step, degrees: degs, rotate: p.chordsRotate)
    case .follow: deg = scaleDegreeOf(followNote ?? root, root: root, scaleTones: scaleTones)
    case .walk:   deg = chordsWalkDegreeAt(step: step, seed: UInt64(bitPattern: Int64(p.chordsWalkSeed)))
    }
    guard !rest else { return [] }
    return diatonicChord(degree: deg, scaleTones: scaleTones, rootNote: 48 + root, voicing: p.chordsVoicing, spread: p.chordsSpread).filter { $0 >= 0 && $0 <= 127 }
}


/// The next degree in a functional random WALK (SPEC-chords-stage §1 WALK — "the gravity dice"): SEEDED (replay-exact, no
/// accumulated state — the caller passes the step ordinal as `seed`), weighted by tonal gravity. From `prev` (0…6) the draw
/// favours resolution — V/vii° pull to I, I opens outward, ii/IV wander toward the dominant. Returns 0…6. Pure/testable.
func walkNextDegree(prev: Int, seed: UInt64) -> Int {
    // per-from transition weights over degrees I ii iii IV V vi vii (functional gravity; rows sum-agnostic — we normalise).
    let W: [[Int]] = [
        [1, 3, 2, 4, 5, 3, 1],   // I  → opens out (mostly to IV/V/ii/vi)
        [1, 1, 1, 2, 6, 1, 3],   // ii → predominant → V (or vii°)
        [3, 1, 1, 3, 2, 4, 1],   // iii→ to vi/IV/I
        [4, 3, 1, 1, 6, 2, 2],   // IV → to V (or ii, I)
        [8, 1, 1, 1, 1, 3, 1],   // V  → resolves HOME to I (vi = deceptive)
        [2, 4, 1, 4, 3, 1, 1],   // vi → predominant wander
        [8, 1, 1, 1, 2, 1, 1],   // vii°→ resolves HOME to I
    ]
    let p = ((prev % 7) + 7) % 7
    let row = W[p]
    let total = row.reduce(0, +)
    let r = Int(splitmix64Mix(seed) % UInt64(max(1, total)))
    var acc = 0
    for (i, w) in row.enumerated() { acc += w; if r < acc { return i } }
    return 0
}

/// The quality-aware Roman-numeral label for `degree` in a scale (SPEC-chords-stage §2 — self-updating headers). Reads the
/// ACTUAL third + fifth from `scaleTones` (rank arithmetic) so the case + glyph track the real quality: MAJ = upper (I),
/// MIN = lower (ii), DIM = lower + ° (vii°), AUG = upper + + (III+). Pure/testable.
func degreeLabel(degree deg: Int, scaleTones: [Int]) -> String {
    let n = scaleTones.count
    guard n > 0 else { return "" }
    func iv(_ k: Int) -> Int {                                      // interval (semitones) of the k-th degree above the chord root
        let base = scaleTones[((deg % n) + n) % n]
        let idx = ((k % n) + n) % n, oct = Int(floor(Double(k) / Double(n)))
        return scaleTones[idx] + 12 * oct - base
    }
    let third = ((iv(deg + 2) % 12) + 12) % 12, fifth = ((iv(deg + 4) % 12) + 12) % 12
    let numerals = ["I", "II", "III", "IV", "V", "VI", "VII"]
    let base = numerals[((deg % 7) + 7) % 7]
    switch (third, fifth) {
    case (4, 7): return base                    // MAJOR — uppercase
    case (3, 7): return base.lowercased()       // minor — lowercase
    case (3, 6): return base.lowercased() + "°" // diminished
    case (4, 8): return base + "+"              // augmented
    default:     return base                    // exotic scale → default to the numeral
    }
}

/// THE KEY FILTER (ratified scale-door §3): map an input note through a reference PITCH-CLASS set. `only` = keep only the
/// set's classes (ONLY / intersection — in-key) vs drop them (MINUS / complement). `snap` = an out-of-set note remaps to the
/// NEAREST legal note (SNAP — the jam-proof keyboard) vs drops (BLOCK — the strict gate). Returns the note (possibly
/// remapped), or nil to drop. Pitch-class (mod 12), octave-independent. Pure/testable; no allocation.
func keyFilterNote(_ note: Int, refMask: UInt16, only: Bool, snap: Bool) -> Int? {
    if refMask == 0 { return only ? nil : note }                // empty reference: ONLY admits nothing (the tell), MINUS excludes nothing
    func allowed(_ n: Int) -> Bool {
        let inSet = (refMask >> UInt16(((n % 12) + 12) % 12)) & 1 != 0
        return only ? inSet : !inSet
    }
    if allowed(note) { return note }
    guard snap else { return nil }                              // BLOCK
    for d in 1...12 {                                           // SNAP: the nearest legal note (down ties before up)
        if note - d >= 0 && allowed(note - d) { return note - d }
        if note + d <= 127 && allowed(note + d) { return note + d }
    }
    return nil
}

/// ECHO IN-KEY WALK: advance from `note` to the NEXT note whose pitch class is in `refMask` — ALWAYS a genuinely
/// different note (never returns `note` even if already in-key, unlike keyFilterNote's snap-to-nearest-or-stay).
/// dir > 0 = up, dir < 0 = down; dir == 0 or refMask == 0 ⇒ nil (hold — no legal move, mirrors echoPitch==0
/// meaning "no movement" in flat mode). Cross-octave (mod 12), bounded to 0...127 — the range bound itself caps
/// iteration count, no separate counter needed. Pure/testable; no allocation.
func nextInKeyNote(_ note: Int, refMask: UInt16, dir: Int) -> Int? {
    guard refMask != 0, dir != 0 else { return nil }
    let step = dir > 0 ? 1 : -1
    var n = note + step
    while n >= 0 && n <= 127 {
        if (refMask >> UInt16(n % 12)) & 1 != 0 { return n }
        n += step
    }
    return nil
}

/// MIDI note number → name: pitch class + a NON-NEGATIVE octave (note 0 = C0 … note 127 = G10) — the range
/// display never shows a "-1" octave (user 2026-08-03). Shared by the cog RANGE chips, the strip header's range
/// summary, and tests — one source so the naming can't drift.
func midiNoteName(_ n: UInt8) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "\(names[Int(n) % 12])\(Int(n) / 12)"
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

/// PASSTHROUGH routing (§2.6 reconciled to the §7b 5-cable model). The raw CC/PB/AT stream and the
/// stopped-transport NOTE passthrough go out on **All (cable 0) + Emit A (cable 1)** — bit i set ⇒
/// forward on cable i. CC/PB/AT always forward; notes forward ONLY when stopped and not being replaced
/// by an audition (§6.4). Returns 0 = drop. Two cables so a synth patched to either "All" or "Emit A"
/// receives controllers + soundcheck; the §6a emitter toggle governs NOTE emission, not this raw stream.
/// NOTE (Paul 2026-08-29): the Kernel now gates the NOTE branch OFF by policy (`noteMonitorPassthrough`,
/// default false) so a fresh instance is silent — a CELL is the sole note source. This pure function +
/// PassthroughGate stay intact/tested so the monitor can be re-enabled behind a soundcheck toggle later.
func passthroughCableMask(isNote: Bool, playing: Bool, auditionSuppressing: Bool) -> UInt8 {
    let forward = isNote ? (!playing && !auditionSuppressing) : true
    return forward ? 0b0000_0011 : 0        // cable 0 (All) + cable 1 (Emit A)
}

/// PASSTHROUGH GATE (a8 hang fix, 2026-07-25) — the STATEFUL wrapper that makes raw-note passthrough
/// note-balanced. The pure `passthroughCableMask` decides a note-ON's fate (forward only when stopped &
/// not audition-suppressed), but a note-OFF must NOT be re-judged by the *current* state: if `playing`
/// or audition flipped between a note's ON and its OFF, judging the OFF drops it and STRANDS the ON at
/// the synth — a stuck note, the hang. This gate forwards a note-OFF **iff that note's ON was
/// forwarded**, whatever the state is now. It tracks one bit per (channel, note); a `0x90` with
/// velocity 0 is a note-OFF. Pure/Foundation-only so the render loop owns one and unit tests drive it.
struct PassthroughGate {
    private var active = [Bool](repeating: false, count: 16 * 128)   // (channel<<7 | note): ON forwarded, awaiting OFF
    /// Count of raw notes echoed and still awaiting their OFF (kept O(1) for the per-render silence check).
    private(set) var activeCount = 0
    // RENDER-THREAD, FIXED-SIZE (code-review finding 2026-10-04): preallocated ONCE when this struct is
    // created (off the render thread), sized to the absolute worst case — every one of the 16×128 channel/note
    // slots stranded at once — so `drainActive()` can fill it IN PLACE and never allocate on the audio thread,
    // not even on the genuinely-stranded-echo path that used to build a fresh `[(UInt8,UInt8)]` there.
    private var drainScratch = [(channel: UInt8, note: UInt8)](repeating: (0, 0), count: 16 * 128)

    /// a8 DUMP: a one-line fingerprint of the still-held echoes (non-mutating; the assert-on-silence dump).
    func heldFingerprint() -> String {
        var parts: [String] = []
        for i in 0..<active.count where active[i] { parts.append("ch\(i >> 7)/n\(i & 0x7F)") }
        return parts.isEmpty ? "none" : parts.joined(separator: " ")
    }

    /// The cable mask (0 = drop) for one raw MIDI event. Call once per event, in arrival order.
    mutating func mask(statusByte: UInt8, note: UInt8, velocity: UInt8, playing: Bool, auditionSuppressing: Bool) -> UInt8 {
        let hi = statusByte & 0xF0
        guard hi == 0x90 || hi == 0x80 else {                       // CC/PB/AT etc. always pass
            return passthroughCableMask(isNote: false, playing: playing, auditionSuppressing: auditionSuppressing)
        }
        let idx = (Int(statusByte) & 0x0F) << 7 | (Int(note) & 0x7F)
        if hi == 0x80 || velocity == 0 {                            // note-OFF (incl. vel-0 note-on)
            let forward = active[idx]                               // forward iff we forwarded its ON
            if active[idx] { active[idx] = false; activeCount -= 1 }
            return forward ? 0b0000_0011 : 0
        }
        let m = passthroughCableMask(isNote: true, playing: playing, auditionSuppressing: auditionSuppressing)
        let want = (m != 0)                                         // remember, so the matching OFF follows
        if want != active[idx] { active[idx] = want; activeCount += want ? 1 : -1 }
        return m
    }

    /// PANIC / reset: fills `drainScratch[0..<count]` with the (channel, note) of every note still awaiting
    /// its OFF (for an all-notes-off flush), clears them, and returns the count. Render-thread safe — no
    /// allocation, fixed-size scratch (see `drained(_:)` to read an entry). The render side emits note-offs
    /// for these to guarantee silence.
    mutating func drainActive() -> Int {
        guard activeCount > 0 else { return 0 }
        var n = 0
        for i in 0..<active.count where active[i] { drainScratch[n] = (UInt8(i >> 7), UInt8(i & 0x7F)); active[i] = false; n += 1 }
        activeCount = 0
        return n
    }
    /// Read one entry drained by the most recent `drainActive()` call, by index (0..<the count it returned).
    func drained(_ i: Int) -> (channel: UInt8, note: UInt8) { drainScratch[i] }
}

/// ASSERT-ON-SILENCE (a8, 2026-07-25) — the plugin must be SILENT when nothing legitimately sounds:
/// transport stopped, no held input, no audition. Any voice or echoed note still open in THAT state is a
/// stuck note. Returns true = the invariant is VIOLATED. Pure, so it's the unit-testable core of the
/// render-side self-check (which then self-heals with an all-notes-off — safe, since nothing real sounds).
func silenceInvariantViolated(playing: Bool, heldInput: Int, auditioning: Bool,
                              activeVoices: Int, passthroughHeld: Int) -> Bool {
    guard !playing, heldInput == 0, !auditioning else { return false }   // something may legitimately sound
    return activeVoices > 0 || passthroughHeld > 0
}

/// §a8b — the PLAYING sibling of the silence invariant, a hung-note net for the case the stopped-net can't see.
/// MidiSpark is a processor: every voice descends from the live input chord. So while the transport RUNS with
/// no live held input, no armed latch (a latch legitimately sustains a frozen chord), and no audition, the grid
/// has no source — once the current column's scheduled note-offs pass, NOTHING should still sound. If voices (or
/// stranded echoes) persist past a debounce, they are STUCK (e.g. a harmonizer voice whose off was missed).
/// `emptyInputSamples` is how long the live input has been continuously empty (while playing); the debounce is
/// kept generous (≥ a few columns) so a note released mid-column still rings to its boundary before this fires.
/// Pure/testable; the Kernel owns the debounce clock and the heal. Unlike the hard stopped-invariant this is a
/// heuristic — the caller soft-heals (log + all-notes-off), it never hard-traps.
func playingSilenceLeak(playing: Bool, liveInput: Int, latchArmed: Bool, auditioning: Bool,
                        emptyInputSamples: Int64, debounceSamples: Int64,
                        activeVoices: Int, passthroughHeld: Int) -> Bool {
    guard playing, liveInput == 0, !latchArmed, !auditioning, emptyInputSamples >= debounceSamples else { return false }
    return activeVoices > 0 || passthroughHeld > 0
}

/// §cell-edit F — the emit bus-mask a CHOP slice yields for a cell whose own emitters are `base`. The three are
/// INDEPENDENT: MAIN adds the cell's own emitters, ALT adds the shared alt-destination mask, MUTE silences (wins
/// over both → 0). MAIN+ALT emits to both. Pure/testable.
func chopBusMask(_ base: UInt8, main: Bool, alt: Bool, mute: Bool, altMask: UInt8) -> UInt8 {
    if mute { return 0 }
    return (main ? base : 0) | (alt ? altMask : 0)
}

/// §cell-edit F — which of the 8 chop slices a musical onset `mBeat` falls in, WITHIN its column of length `S`
/// beats (0…7). The chop divides the CELL'S OWN column-time into 8, so each articulation routes by its slice.
/// Pure/testable.
func chopSlice(_ mBeat: Double, columnBeats S: Double) -> Int {
    guard S > 0 else { return 0 }
    let frac = positiveFract(mBeat / S)   // 0..<1 within the column
    return min(7, max(0, Int(frac * 8)))
}

/// TUTTI PATTERN — the GLOBAL slice index of an onset at `mBeat`, at `sliceBeats` per slice (so an authored pattern
/// walks continuously across columns rather than resetting). A pure function of musical position → replay-exact.
func tuttiSliceOf(_ mBeat: Double, sliceBeats: Double) -> Int {
    guard sliceBeats > 0 else { return 0 }
    return Int((mBeat / sliceBeats).rounded(.down))
}

/// TUTTI PATTERN — the ascending-rank indices a slice STATE emits + their octave shift (semitones). `count` = the
/// held set size (rank 0 = lowest … count−1 = highest). REST → none; the ±oct variants shift the emitted pitch. Pure.
// Fill `buf[0..<rankCount]` with the slice's ranks (indices into the sorted chord) — no-alloc form for the render hot
// loop. Returns (rankCount, octave). The array `tuttiSliceRanks` below wraps it for the tests.
func tuttiSliceRanksInto(_ buf: inout [Int], _ state: TuttiSlice, count: Int) -> (rankCount: Int, octave: Int) {
    guard count > 0, buf.count >= count else { return (0, 0) }
    switch state {
    case .all:        for i in 0..<count { buf[i] = i }; return (count, 0)
    case .low:        buf[0] = 0; return (1, 0)
    case .high:       buf[0] = count - 1; return (1, 0)
    case .top2:       if count >= 2 { buf[0] = count - 2; buf[1] = count - 1; return (2, 0) }; buf[0] = 0; return (1, 0)
    case .bot2:       if count >= 2 { buf[0] = 0; buf[1] = 1; return (2, 0) }; buf[0] = 0; return (1, 0)
    case .lowOct:     buf[0] = 0; return (1, 12)
    case .allDownOct: for i in 0..<count { buf[i] = i }; return (count, -12)
    case .rest:       return (0, 0)
    }
}
func tuttiSliceRanks(_ state: TuttiSlice, count: Int) -> (ranks: [Int], octave: Int) {
    var buf = [Int](repeating: 0, count: max(1, count))
    let (n, oct) = tuttiSliceRanksInto(&buf, state, count: count)
    return (Array(buf[0..<n]), oct)
}

// MARK: - LENGTH (Paul 2026-08-05): per-slice GATE override — 8 slices of the STEP, PASS/MUTE/SHORT/LONG

/// The note-on events (musical on/off beats) for ONE column's 8 slices — the STANDALONE re-articulator. PASS
/// sustains/TIES (no re-attack while ringing; resumes with a fresh sustain after silence), MUTE silences (and cuts a
/// ringing note), SHORT is staccato (5–95% of a slice), LONG rings (0.25 slice … the STEP end). Pure + window-
/// independent (recomputed per column from `colStart`); every off is capped at the column end (nothing rings past the
/// step — the envelope law). `rotate` shifts which painted slice maps to which time-slice.
// No-alloc form for the render hot loop: fill a caller-owned `buf` (≥ 8) with the events, return the count (≤ 8, since at
// most one event is appended per slice). Router binds a reused `lenEventBuf`; the array wrapper below is for the tests.
@discardableResult func lengthColumnEventsInto(_ buf: inout [(on: Double, off: Double)], slices: [LenState], rotate: Int,
                                               shortFrac: Double, longFrac: Double, colStart: Double, S: Double) -> Int {
    guard S > 0, !slices.isEmpty, buf.count >= 8 else { return 0 }
    let sliceLen = S / 8
    let colEnd = colStart + S
    let sf = max(0.05, min(0.95, shortFrac)), lf = max(0.0, min(1.0, longFrac))
    let eps = sliceLen * 1e-6
    var n = 0
    var lastIdx = -1
    var lastOff = -Double.greatestFiniteMagnitude
    for s in 0..<8 {
        let tau = colStart + Double(s) * sliceLen
        let sliceEnd = tau + sliceLen
        let state = slices[((s + rotate) % slices.count + slices.count) % slices.count]
        switch state {
        case .mute:
            if lastOff > tau + eps { buf[lastIdx].off = tau; lastOff = tau }           // cut a ringing note at the rest
        case .short:
            if lastOff > tau + eps { buf[lastIdx].off = tau }                          // a re-attack cuts the prior ring
            let off = min(colEnd, tau + sf * sliceLen)
            buf[n] = (tau, off); lastIdx = n; n += 1; lastOff = off
        case .long:
            if lastOff > tau + eps { buf[lastIdx].off = tau }
            let longLen = 0.25 * sliceLen + lf * max(0, (colEnd - tau) - 0.25 * sliceLen)
            let off = min(colEnd, tau + longLen)
            buf[n] = (tau, off); lastIdx = n; n += 1; lastOff = off
        case .pass:
            if lastOff >= tau - eps {                                                  // still ringing → TIE (extend, no re-attack)
                let newOff = min(colEnd, max(lastOff, sliceEnd)); buf[lastIdx].off = newOff; lastOff = newOff
            } else {                                                                   // silence behind → resume, sustained
                let off = min(colEnd, sliceEnd); buf[n] = (tau, off); lastIdx = n; n += 1; lastOff = off
            }
        }
    }
    return n
}
func lengthColumnEvents(slices: [LenState], rotate: Int, shortFrac: Double, longFrac: Double,
                        colStart: Double, S: Double) -> [(on: Double, off: Double)] {
    var buf = [(on: Double, off: Double)](repeating: (0, 0), count: 8)
    let n = lengthColumnEventsInto(&buf, slices: slices, rotate: rotate, shortFrac: shortFrac, longFrac: longFrac, colStart: colStart, S: S)
    return Array(buf[0..<n])
}

/// LENGTH — the per-onset gate decision for the DOWNSTREAM case (LENGTH after a driver: each existing onset gets its
/// gate replaced by the slice it lands in — no new notes). MUTE = drop, PASS = keep the driver's own off, SHORT/LONG =
/// a new off beat (capped at the step end). Pure.
enum LengthGate: Equatable { case drop, keep, overrideOff(Double) }
func lengthGateFor(_ state: LenState, onset: Double, shortFrac: Double, longFrac: Double, S: Double) -> LengthGate {
    guard S > 0 else { return .keep }
    let colStart = columnStart(onset, S), colEnd = colStart + S, sliceLen = S / 8
    switch state {
    case .mute: return .drop
    case .pass: return .keep
    case .short: return .overrideOff(min(colEnd, onset + max(0.05, min(0.95, shortFrac)) * sliceLen))
    case .long:
        let lf = max(0.0, min(1.0, longFrac))
        return .overrideOff(min(colEnd, onset + 0.25 * sliceLen + lf * max(0, (colEnd - onset) - 0.25 * sliceLen)))
    }
}

// MARK: - BURST family (Paul 2026-08-19): PATTERN carry-span + COIN chance

/// A rotated, safe read of an 8-slice BURST pattern (loaded docs may carry <8 → REST).
@inline(__always)
func burstSliceAt(_ slices: [BurstSlice], _ i: Int, rotate: Int) -> BurstSlice {
    guard !slices.isEmpty else { return .rest }
    let j = (((i - rotate) % 8) + 8) % 8
    return j < slices.count ? slices[j] : .rest
}
/// The SPAN of a burst launched at slice `i` — 1 (the burst slice) + the run of contiguous CARRY slices after it.
/// A carry with no preceding burst (or a rest) contributes nothing; the roll's strikes+curve stretch over this many
/// slices. (Paul 2026-08-19: CARRY = span-stretch, not gate-ring.)
@inline(__always)
func burstCarryRun(_ slices: [BurstSlice], at i: Int, rotate: Int, count: Int = 8) -> Int {
    guard burstSliceAt(slices, i, rotate: rotate) == .burst else { return 0 }   // burstSliceAt tiles mod-8, so this walks a >8-slice rate-driven pattern
    var run = 1
    while i + run < count && burstSliceAt(slices, i + run, rotate: rotate) == .carry { run += 1 }
    return run
}
/// Whether this STEP fires a burst under COIN — seeded, deterministic per step, salted apart from RATCHET/CHANCE.
@inline(__always)
func burstCoinFires(step: Int, chance: Double) -> Bool {
    if chance >= 1 { return true }
    if chance <= 0 { return false }
    let h = splitmix64Mix(UInt64(bitPattern: Int64(step)) &* 0x9E3779B97F4A7C15 &+ 0x1D8E4E27C47D124F)
    return Double(h >> 11) * (1.0 / 9_007_199_254_740_992.0) < chance
}

// MARK: - RATCHET COIN (Paul 2026-08-16): a seeded per-STEP roll — ratchet-or-plain, and the burst count

/// Whether this STEP ratchets (vs a plain single hit). DETERMINISTIC per step index (a hash — loop-consistent,
/// replay-exact, salted apart from CHANCE/TUTTI). `chance` = P(ratchet).
@inline(__always)
func rtcCoinRatchets(step: Int, chance: Double) -> Bool {
    if chance >= 1 { return true }
    if chance <= 0 { return false }
    let h = splitmix64Mix(UInt64(bitPattern: Int64(step)) &* 0x9E3779B97F4A7C15 &+ 0xA5A5A5A5A5A5A5A5)
    return Double(h >> 11) * (1.0 / 9_007_199_254_740_992.0) < chance
}
/// The burst count for a ratcheting step, a seeded pick in [lo, hi] (clamped, lo≤hi). Deterministic per step.
@inline(__always)
func rtcCoinCount(step: Int, lo: Int, hi: Int) -> Int {
    let l = max(1, min(lo, hi)), h = max(l, max(lo, hi))
    if l == h { return l }
    let x = splitmix64Mix(UInt64(bitPattern: Int64(step)) &* 0x2545F4914F6CDD1D &+ 0x1234567898765432)
    return l + Int(x % UInt64(h - l + 1))
}
/// COIN — the FIRE decision (Paul 2026-08-26 ②③④): does this step ratchet, after REFIRE GAP + QUOTA + velocity-odds?
/// FAST PATH: gap=0 & quota=0 ⇒ `rtcCoinRatchets(step, chance·velFactor)` (byte-identical when velFactor==1). Otherwise a
/// bounded, deterministic SCAN of the coin from the ROW START (the 8-step pass) — replay-exact, NO accumulated state
/// ("derived, never accumulated"). GAP: a fire suppresses the next N steps. QUOTA: at most `quota` fires per row.
/// v1: gap + quota reset per 8-step row (a fire on step 7 doesn't reach step 8 — a negligible boundary edge).
@inline(__always)
func rtcCoinFires(step s: Int, chance: Double, gap: Int, quota: Int, velFactor: Double) -> Bool {
    let eff = chance * velFactor
    if gap <= 0 && quota <= 0 { return rtcCoinRatchets(step: s, chance: eff) }
    let rowStart = (s >= 0 ? (s / 8) : ((s - 7) / 8)) * 8   // floor-div to the row origin (handles negative steps)
    var lastFire = Int.min / 2, fired = 0
    var t = rowStart
    while t <= s {
        var f = rtcCoinRatchets(step: t, chance: eff)
        if gap > 0 && t - lastFire <= gap { f = false }          // REFIRE GAP
        if quota > 0 && fired >= quota { f = false }             // QUOTA cap
        if f { lastFire = t; fired += 1 }
        if t == s { return f }
        t += 1
    }
    return false
}
/// COIN — SIZE WEIGHTS (Paul 2026-08-26 ①): the roll SIZES the dice can pick, and their odds (the drawn distribution).
let rtcCoinSizes = [2, 3, 4, 6, 8]
/// A seeded WEIGHTED pick over 2·3·4·6·8 by `weights` (bar heights). Deterministic per step (same salt as rtcCoinCount).
/// An empty/all-zero weight vector never reaches here (the engine falls back to LO/HI); guarded anyway.
@inline(__always)
func rtcCoinSize(step: Int, weights: [Int]) -> Int {
    let n = min(rtcCoinSizes.count, weights.count)
    var total = 0; for i in 0..<n { total += max(0, weights[i]) }
    guard total > 0 else { return rtcCoinSizes[0] }
    let x = splitmix64Mix(UInt64(bitPattern: Int64(step)) &* 0x2545F4914F6CDD1D &+ 0x1234567898765432)
    var pick = Int(x % UInt64(total))
    for i in 0..<n { pick -= max(0, weights[i]); if pick < 0 { return rtcCoinSizes[i] } }
    return rtcCoinSizes[n - 1]
}

/// RIFF (SPEC-riff-processor §1): the note a stencil RANK strikes against the held pool (sorted ascending, cell-filtered).
/// rank 1 = the lowest held note … N = the highest. A rank BEYOND the held count wraps per `wrap`: FOLD (wrap + octave up,
/// musical) · CLAMP (the top note) · WRAP (wrap in the same octave). `oct` nudges ±. Returns nil for a REST (rank ≤ 0) or
/// an empty pool. Zero pitches stored — the chord answers the stencil, so one riff plays in any key. Pure/testable.
func riffNote(rank: Int, oct: Int, pool: NotePool, for cell: SnapCell, wrap: RiffWrap) -> Int? {
    riffResolve(rank: rank, oct: oct, n: pool.srcCount(for: cell), wrap: wrap) { Int(pool.srcAscending($0, for: cell)) }
}
/// The RIFF rank→note core, over a sorted (ascending) note supply of size `n`. Shared by the direct (cell-filtered) path
/// and the chain-driver (OMNI composed set) path — `asc(k)` is the k-th note. Non-escaping closure ⇒ no render-path alloc.
@inline(__always) func riffResolve(rank: Int, oct: Int, n: Int, wrap: RiffWrap, asc: (Int) -> Int) -> Int? {
    guard rank >= 1, n > 0 else { return nil }
    let idx0 = rank - 1
    let note: Int
    if idx0 < n { note = asc(idx0) }
    else {
        let over = idx0 % n, laps = idx0 / n
        switch wrap {
        case .fold:  note = asc(over) + 12 * laps
        case .clamp: note = asc(n - 1)
        case .wrap:  note = asc(over)
        }
    }
    return note + 12 * oct
}

// MARK: - WEAVE (Paul 2026-08-07): a rank-clocked polyrhythm driver — each rank ticks on its own clock

/// The tick spacing (beats per tick) for `rank` (0 = bass) at a MODE and BASE clock. LADDER halves per rank
/// (base÷2^r → 1/4·1/8·1/16…); HARMONIC divides by rank+1 ((r+1)× as fast → 1:2:3:4, pitch ratios as time ratios).
/// Pure; clamped to a sane floor so a deep rank can't tick per-sample. Replay-exact (a function of rank + base only).
func weaveRate(mode: WeaveMode, baseBeats: Double, rank: Int) -> Double {
    let r = max(0, rank)
    switch mode {
    case .ladder:   return max(0.03125, baseBeats / pow(2, Double(r)))
    case .harmonic: return max(0.03125, baseBeats / Double(r + 1))
    case .drawn, .euclid: return max(0.03125, baseBeats)   // these modes drive their own clock in the emitter; this is only a fallback
    }
}

/// §cell-edit D — the contiguous [start, len) window of the ASCENDING source list a chord-split selects.
/// ALL = the whole list; TOP n = the n highest (a suffix); BOTTOM n = the n lowest (a prefix); RANGE = the
/// notes on one side of `split.note` (HIGH = the ≥split suffix, LOW = the <split prefix). `noteAt(i)` reads
/// the i-th ascending source note (consulted only for RANGE). Pure so the selection law is unit-tested.
func chordSplitWindow(count: Int, split: ChordSplit, noteAt: (Int) -> Int) -> (start: Int, len: Int) {
    guard count > 0 else { return (0, 0) }
    switch split.mode {
    case .all:    return (0, count)
    case .top:    let len = min(max(0, split.n), count); return (count - len, len)
    case .bottom: let len = min(max(0, split.n), count); return (0, len)
    case .range:
        var b = 0
        while b < count && noteAt(b) < split.note { b += 1 }   // first index whose note ≥ the split point
        return split.high ? (b, count - b) : (0, b)
    }
}


/// COLUMN-SUBSET LAP (delta §5b) — the whole perform-v2 feature in one function. With `laneMask` the
/// held columns (bit i set ⇒ column i is held), the EFFECTIVE column at global step `absoluteStep` is
/// the (absoluteStep mod k)-th held column, ordered left→right (k = held count). Only column SELECTION
/// is warped; the true timeline is untouched (pass/swing all run off it). `laneMask == 0`
/// (nothing held) passes `trueColumn` through unchanged. k∤8 gives the INTENDED polymeter rotation —
/// the mapping is never reset at pass boundaries, so a k-cycle phases against the 8-step timeline.
func lapColumn(laneMask: UInt16, absoluteStep: Int, trueColumn: Int) -> Int {
    let k = laneMask.nonzeroBitCount
    guard k > 0 else { return trueColumn }
    let idx = ((absoluteStep % k) + k) % k          // 0..<k, negative-safe
    var m = laneMask, seen = 0
    while m != 0 {
        let col = Int(m.trailingZeroBitCount)       // lowest set bit = leftmost held column
        if seen == idx { return col }
        seen += 1; m &= m - 1
    }
    return trueColumn                               // unreachable (idx < k)
}

// MARK: - ARP phase (§3.5): pattern index at a tick, per phase mode

/// The pattern index at this tick per PHASE mode. All pure functions of position — derived, never
/// accumulated (§7), so tempo/loop/relocate stay drift-free.
///  · RETRIG — restarts at each step (column) boundary.
///  · LEGATO — counts from the run's first column (snapshot-precomputed runStartColumn), so a
///    multi-column run of one Machine continues the pattern; a gap restarts it.
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

/// The base note (pre-this-cell-transpose) a source-reading ARP picks at pattern index `phaseIndex`,
/// for the given PATTERN over `octaves`. `filter` (delta §7) restricts the source pool to one input
/// channel (0 = OMNI). All patterns are pure functions of position (loop-consistent). Chord changes
/// never reset the index. Returns -1 for an empty (filtered) pool. No channel is returned — past the
/// input filter notes carry no channel (delta §7); emission stamps the bus channel.
func arpPickSource(phaseIndex: Int64, octaves: Int, pattern: UInt8,
                   pool: NotePool, filter: UInt8 = 0, cableMask: Int = 0b1111,
                   noteLo: UInt8 = 0, noteHi: UInt8 = 127, seed: UInt64 = 0) -> Int {
    arpPick(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern, pool: pool,
            filter: filter, cableMask: cableMask, noteLo: noteLo, noteHi: noteHi, seed: seed).note
}

/// The arp source pick AND the picked note's velocity (user 2026-08-09: processors inherit velocity from their
/// input source). Velocity is OCTAVE-INVARIANT — it comes from the underlying HELD note, so an octave-arped copy
/// keeps the source dynamic. Returns (-1, 0) when the pool is empty.
func arpPick(phaseIndex: Int64, octaves: Int, pattern: UInt8,
             pool: NotePool, filter: UInt8 = 0, cableMask: Int = 0b1111,
             noteLo: UInt8 = 0, noteHi: UInt8 = 127,
             octDown: Bool = false, randomAnchor: Int = 0, seed: UInt64 = 0,
             velocity: Double = 100, velTilt: Double = 0) -> (note: Int, vel: UInt8) {
    // Legacy single-channel `filter` → channel MASK, byte-identical (0 → OMNI 0xFFFF · n → bit n−1) — then the mask body.
    let mask: UInt16 = filter == 0 ? 0xFFFF : (filter >= 1 && filter <= 16 ? (UInt16(1) << UInt16(filter - 1)) : 0)
    return arpPick(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern, pool: pool,
                   chanMask: mask, cableMask: cableMask, noteLo: noteLo, noteHi: noteHi,
                   octDown: octDown, randomAnchor: randomAnchor, seed: seed,
                   velocity: velocity, velTilt: velTilt)
}
// MULTI-CHANNEL arp source pick (Paul 2026-08-23): filter the source by a channel MASK so an arp honours a door's
// multi-channel subset on LIVE input (the `for: cell` path passes cell.inputChanMask; a frozen omniRead pool passes OMNI).
func arpPick(phaseIndex: Int64, octaves: Int, pattern: UInt8,
             pool: NotePool, chanMask: UInt16, cableMask: Int = 0b1111,
             noteLo: UInt8 = 0, noteHi: UInt8 = 127,
             octDown: Bool = false, randomAnchor: Int = 0, seed: UInt64 = 0,
             // ARP VELOCITY · VELOCITY TILT (Paul 2026-09-30, revised same day): `velocity` is an ABSOLUTE value
             // 1…100 — the picked note's own input velocity is IGNORED entirely, every arp note plays at exactly
             // this level; `velTilt` then favours the top (+) or bottom (−) of the pool by the note's ASCENDING-POOL
             // RANK, applied on top of that fixed base — reuses `strumVelocity`'s own tilt formula verbatim (the
             // exact chanceTilt/velTilt/bipolarSlider convention), not a second tilt implementation.
             velocity: Double = 100, velTilt: Double = 0) -> (note: Int, vel: UInt8) {
    // RANGE (§2): arps admit only in-window source notes (vel window intentionally NOT applied to arps — unchanged).
    let fullRange = noteLo <= 0 && noteHi >= 127
    let count = fullRange ? pool.srcCount(chanMask: chanMask, cableMask: cableMask)
                          : pool.srcCount(chanMask: chanMask, cableMask: cableMask, velLo: 0, velHi: 127, noteLo: noteLo, noteHi: noteHi)
    guard count > 0 else { return (-1, 0) }
    let span = count * max(1, octaves)
    let asc = Int(((phaseIndex % Int64(span)) + Int64(span)) % Int64(span))   // UP position 0…span-1
    let pat = arpPatternAt(Int(pattern))   // cached cases — no per-tick allocation (was ArpPattern.allCases)

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
        // RANDOM ANCHOR (Paul 2026-08-22): each CYCLE (span steps = one full pool×oct traversal) OPENS on the anchor —
        // asc==0 is the wrap → the lowest (1) / highest (2) ascending position; the rest shuffle (seeded, loop-consistent).
        if randomAnchor != 0 && asc == 0 {
            pos = randomAnchor == 1 ? 0 : span - 1
        } else {
            let h = splitmix64Mix(UInt64(bitPattern: phaseIndex) &+ 0x9E3779B97F4A7C15)   // deterministic hash of the tick → position (loop-consistent, not accumulated)
            if randomAnchor != 0 && span > 1 {
                // ANCHOR EXCLUDED (Paul 2026-09-13): the anchor note sounds once (at the cycle wrap); the rest of the cycle
                // shuffles only the OTHER span−1 positions, so the anchor never repeats inside the random pool. LO skips
                // pos 0 (→ 1…span−1) · HI skips pos span−1 (→ 0…span−2). Octave copies of the anchor pitch stay in the pool
                // (they're different notes), only the exact anchored note is held out.
                let r = Int(h % UInt64(span - 1))
                pos = randomAnchor == 1 ? (1 + r) : r
            } else {
                pos = Int(h % UInt64(span))
            }
        }
    case .randomOnce:
        // RANDOM ONCE (Paul 2026-09-16): a FIXED shuffled order, rolled from a PERSISTED seed and repeated EVERY cycle —
        // unlike .random, which re-hashes the absolute tick so each cycle differs. The position depends ONLY on the within-
        // cycle index `asc` (0…span-1) and the seed, so every loop is identical, and different machines/seeds shuffle
        // differently. Same seeded-hash style as .random (not a strict permutation — a position may repeat, matching how
        // .random already behaves), just cycle-stable. No accumulation, no allocation (invariant 2/3).
        pos = Int(splitmix64Mix(UInt64(bitPattern: Int64(asc)) &+ seed) % UInt64(span))
    case .asPlayed:
        pos = asc   // ascending through the press sequence (below), not the sorted set
    case .altLo, .altHi:
        // ALT (Paul 2026-09-13): a pedal note alternates with each OTHER position. ALT LO pedals the lowest and walks the
        // others ascending → 1,2,1,3,1,4… ; ALT HI mirrors it — pedals the highest and walks the others descending. The
        // "others" span the octaves too (they're just the higher/lower span positions). Cycle length = 2·(span−1).
        let L = max(1, 2 * (span - 1))
        let s = Int(((phaseIndex % Int64(L)) + Int64(L)) % Int64(L))
        let loPos = (s % 2 == 0) ? 0 : (s + 1) / 2      // 0,1,0,2,0,3,… — low pedal + ascending others
        pos = (pat == .altLo) ? loPos : (span - 1 - loPos)   // ALT HI = the mirror (high pedal + descending others)
    }

    // AS-PLAYED reads the press-order list; every other pattern reads the sorted list. Both filtered (+ RANGE window).
    // `rank` is captured once (the same index used to fetch the note) so the VELOCITY TILT below reuses it directly —
    // for every pattern except AS-PLAYED this is the note's ASCENDING-POOL rank (0 = lowest); for AS-PLAYED it's the
    // PRESS-order index instead (srcPlayed, not srcAscending), an honest minor difference for that one mode rather
    // than a second, more expensive pitch-sort lookup just to keep the tilt "pitch-pure" everywhere.
    let rank = pos % count
    let note: Int
    if pat == .asPlayed {
        note = Int(fullRange ? pool.srcPlayed(rank, chanMask: chanMask, cableMask: cableMask)
                             : pool.srcPlayed(rank, chanMask: chanMask, cableMask: cableMask, noteLo: noteLo, noteHi: noteHi))
    } else {
        // CR-18[extra] DECISION: the ARP walk reads the whole (channel/cable/RANGE-filtered) pool — the cell's VELOCITY
        // WINDOW (velLo/velHi pinned 0…127 here) and its CHORD SPLIT are INTENTIONALLY NOT applied to the arp, unlike
        // HOLD/STRUM/RATCHET. Long-standing (the vel-window omission is documented elsewhere); to punch holes in an arp's
        // pool by register/velocity, chain a SPLIT stage before the ARP. Documented, not changed (would alter every arp).
        note = Int(fullRange ? pool.srcAscending(rank, chanMask: chanMask, cableMask: cableMask)
                             : pool.srcAscending(rank, chanMask: chanMask, cableMask: cableMask, velLo: 0, velHi: 127, noteLo: noteLo, noteHi: noteHi))
    }
    guard note >= 0 && note <= 127 else { return (-1, 0) }
    // OCT DIRECTION — PATTERN orders WITHIN a lap; this orders the LAPS. REDEFINED (Paul 2026-09-30, a deliberate
    // behaviour change — was "start at the top octave, descend TO the held keys," never going below them): now
    // symmetric with UP — lap 0 always opens AT the held register (octIdx 0 ⇒ oct 0); UP ascends from there
    // (oct = +octIdx), DOWN descends BELOW it (oct = −octIdx). No new range handling needed: every call site
    // already re-checks the FINAL `note + 12*oct` against 0…127 before emitting (unchanged — the same check that
    // already silently drops an UP note pushed above 127 equally drops a DOWN note pushed below 0).
    let octIdx = pos / count
    let oct = octDown ? -octIdx : octIdx
    // VELOCITY (Paul 2026-09-30, revised same day): `velocity` is the note's ENTIRE velocity — the input note's own
    // velocity (`pool.velocity`) is deliberately never read here anymore; every arp note plays at exactly the dialed
    // level, then TILT shapes it by pool rank — reuses `strumVelocity` verbatim, keyed on `rank`/`count` (the exact
    // ascending-pool index just used to fetch `note`).
    let base = clampVel(Int(velocity.rounded()))
    let vel = strumVelocity(index: rank, count: count, tilt: velTilt, base: Int(base))
    return (note + 12 * oct, vel)
}

/// §item 11 convenience — same as above, reading the (channel + cable) filter straight off a SnapCell
/// so the render loop's arp source-picks can't drift the pairing. The preview/audition paths keep the
/// explicit-`filter:` form (they force a source, not the cell's).
func arpPickSource(phaseIndex: Int64, octaves: Int, pattern: UInt8, pool: NotePool, for cell: SnapCell,
                   octDown: Bool = false, randomAnchor: Int = 0, seed: UInt64 = 0) -> Int {
    arpPick(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern, pool: pool, for: cell, octDown: octDown, randomAnchor: randomAnchor, seed: seed).note
}
func arpPick(phaseIndex: Int64, octaves: Int, pattern: UInt8, pool: NotePool, for cell: SnapCell,
             octDown: Bool = false, randomAnchor: Int = 0, seed: UInt64 = 0,
             velocity: Double = 100, velTilt: Double = 0) -> (note: Int, vel: UInt8) {
    // MULTI-CHANNEL (Paul 2026-08-23): filter by the cell's channel MASK (was the legacy single `inputChannel` — which is
    // OMNI for a multi-channel-masked door, so an arp ignored the mask on live input). omniRead FROZEN pool → skip the
    // door filter entirely (channel/cable/range applied at capture; see NotePool.omniRead).
    arpPick(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern,
            pool: pool, chanMask: pool.omniRead ? 0xFFFF : cell.inputChanMask, cableMask: pool.omniRead ? 0b1111 : Int(cell.inputCableMask),
            noteLo: pool.omniRead ? 0 : cell.inputRangeLo, noteHi: pool.omniRead ? 127 : cell.inputRangeHi,   // RANGE (§2)
            octDown: octDown, randomAnchor: randomAnchor, seed: seed,
            velocity: velocity, velTilt: velTilt)
}

// MARK: - Processor dispatch (§3/§4)

/// What a cell does THIS render. Centralises processor dispatch: bypass and not-yet-built types
/// fall back to identity; an implemented processor gets its own mode.
/// Adding a processor = one case here + its branch in the loop.
enum CellMode: Equatable { case arp, ratchet, strum, chance, harmonize, echo, euclid, burst, cascade, drone, shift, humanize, tutti, length, weave, split, octave, transpose, riff, hocket, avoid, chords, identity, silent }

// (morph removed: the A/B blend `MorphTier`/`morphTier` are gone — a cell renders its chain head directly.)

// MARK: - Receiver channel match (delta §9 item 11)

/// Does a receiver with `filter` (0 = OMNI, 1–16) hear a note arriving on wire `channel` (0–15)?
/// Wire channel = filter − 1. Used for input metering attribution (and mirrors NotePool's source filter).
@inline(__always) func receiverHears(filter: UInt8, channel: UInt8) -> Bool {
    filter == 0 || filter == channel + 1
}
// MULTI-CHANNEL (Paul 2026-08-21): does a door's channel SUBSET hear this channel? (bit c = channel c+1.)
@inline(__always) func receiverHearsMask(_ chanMask: UInt16, channel: UInt8) -> Bool {
    (chanMask & (UInt16(1) << UInt16(channel))) != 0
}

/// INPUT CABLES admission (§item 11): does a receiver whose cable BITMASK is `mask` (bit i = cable i+1)
/// hear an event arriving on `eventCable` (1–4)? ANY = all bits set. An out-of-range/unknown cable (0 or
/// >4 — e.g. a single-input host that doesn't tag, or legacy) is heard by everyone (compatibility). This
/// is the cable comparison that sits AHEAD of the channel filter; the full admission is `cable AND channel`.
@inline(__always) func receiverHearsCable(mask: Int, eventCable: Int) -> Bool {
    guard eventCable >= 1 && eventCable <= 4 else { return true }
    return (mask & (1 << (eventCable - 1))) != 0
}

/// The THRU-pip passthrough gate (receiver strip): may a passthrough event forward, following the THRU
/// receiver (its `filter`/`cableMask`)? A MUTED THRU (filter ≥ mutedSourceFilter) blocks EVERYTHING — the
/// note soundcheck included. A non-note event (CC/PB/AT) additionally requires the THRU receiver's
/// cable+channel admission; a note (stopped-transport soundcheck) is mute-gated only. Supersedes the
/// hardwired follows-R1 rule — same behaviour, now aimed by the movable pip.
@inline(__always) func thruAudible(isNote: Bool, isSystem: Bool, filter: UInt8, cableMask: Int, eventCable: Int, channel: UInt8) -> Bool {
    if filter >= Snap.mutedSourceFilter { return false }        // muted THRU passes nothing
    if isNote { return true }                                   // note soundcheck: mute-gated only
    // SYSTEM messages (0xF0–0xFF: clock/start/stop/SysEx/active-sensing) are channel-LESS — their status low nibble
    // is a sub-type, not a channel. Cable-gate them (a legitimate port distinction) but NEVER channel-filter, else a
    // non-OMNI THRU pip would silently swallow transport/clock. (audit 2026-08-05 B1.)
    if isSystem { return receiverHearsCable(mask: cableMask, eventCable: eventCable) }
    return receiverHearsCable(mask: cableMask, eventCable: eventCable) && receiverHears(filter: filter, channel: channel)
}

/// UI peak-hold decay (delta §6a metering): a level fading linearly from `peak` to 0 over `hold`
/// seconds since `since`. Shared by the RECEIVERS input meters and the EMITTERS output meters — the
/// UI owns the decay (the engine feed is read-and-clear). Clamped ≥ 0 so a stale timestamp reads dark.
func peakHoldLevel(peak: Double, since: Date, now: Date, hold: Double = 0.15) -> Double {
    guard hold > 0 else { return 0 }
    return max(0, peak * (1 - now.timeIntervalSince(since) / hold))
}

// MARK: - ON ARRIVE (§9 item 1) — temporal treatments as PURE derivations of the arrival counter

// "Arrivals" = the number of times the playhead has reached this cell's column since transport start (once
// per pass, so arrivals == the true pass counter). EVERY-N advances the effect once every N arrivals. All
// pure functions of (config, arrivals) — no accumulation, no render-thread writes (derive-vs-mutate law).

// (CELL MACHINE: ALT-ALTERNATE `arriveAlt` and MORPH-DRIFT `arriveMorph` were REMOVED with the morph layer —
//  both only steered the now-gone A/B face. EMITTER-ROTATE below is independent and stays.)

/// EMITTER-ROTATE: rotate the cell's 4-bit emitter mask (A–D) left one position every EVERY-N arrivals,
/// so the firing emitter(s) walk A→B→C→D→A across passes. Preserves the count of lit emitters; inert unless
/// the treatment is assigned and the mask is non-empty.
func arriveBusMask(base: UInt8, on: OnConfig, arrivals: Int) -> UInt8 {
    guard on.arrive == .emitterRotate, arrivals >= 0, base != 0 else { return base }
    let n = max(1, on.arriveEvery)
    let shift = (arrivals / n) & 3                        // 0…3 positions
    let m = base & 0x0F
    return ((m << shift) | (m >> (4 - shift))) & 0x0F     // rotate-left within the low 4 bits
}

/// ON SCENE audibility (§9 item 1): is a cell audible this pass? An ENTRANCE holds it out until its pass
/// (`p < entrancePass`); an EXIT retires it from its pass on (`p >= exitPass`). `pass` is 0-indexed (since
/// the scene anchor — v1 = transport start); the UI's ENTER/EXIT numbers are 1-indexed, so compare against
/// `pass + 1`. AND-composed with mute upstream. (RESET-MORPH needs a scene-restart to reset against, which
/// a single-scene world never fires — deferred to multi-scene.)
func onSceneAudible(_ on: OnConfig, pass: Int) -> Bool {
    let p = pass + 1                                   // 1-indexed pass, matching the 1…16 UI
    if on.sceneEntrance && p < on.entrancePass { return false }   // hasn't entered yet
    if on.sceneExit && p >= on.exitPass { return false }          // has exited
    return true
}

// MARK: - ON HOLD (§9 item 1) — momentary treatments while a cell is press-held (PERFORM). Ephemeral
// (audition-class): the held cell is an overlay, never a document write. SPRING = the overlay clears on
// release; LATCH (3c) will keep it until §5c HOLD. These are the alt/octave treatments (3a); FREEZE /
// MORPH-SCRUB / SLICE-CYCLE follow in 3b.

/// ON HOLD = ALT: flip the held cell to its B-state while held.
func holdAlt(base: Bool, on: OnConfig, held: Bool) -> Bool {
    (held && on.hold == .alt) ? !base : base
}

/// ON HOLD = OCT: shift the held cell's notes an octave (± per octUp) while held; 0 otherwise.
func holdOctaveShift(on: OnConfig, held: Bool) -> Int {
    (held && on.hold == .oct) ? (on.octUp ? 12 : -12) : 0
}

/// PLAY-FERRY LAUNCH (Paul 2026-09-09, Docs/PLAN-play-ferry-launch.md): the beat a launched ferry ANCHORS to for its
/// START mode. SYNC ⇒ 0 (no anchor — the row stays transport-locked, today's behaviour). INSTANT ⇒ the tap beat itself
/// (off-grid, from the part's top on tap). STEP/BEAT/PASS ⇒ the NEXT such boundary at or after the tap (quantized launch).
/// The engine derives the row's column from (beat − anchor), so a non-zero anchor plays the part from column 0.
/// `passBeats` = the part's loop length × its step (the PASS quantize unit). Pure so the launch math is unit-tested.
func ferryLaunchAnchor(beat: Double, start: FerryStart, stepBeats: Double, passBeats: Double) -> Double {
    switch start {
    case .sync:    return 0
    case .instant: return max(0, beat)
    case .step:    return ferryNextBoundary(beat, max(0.01, stepBeats))
    case .beat:    return ferryNextBoundary(beat, 1.0)
    case .pass:    return ferryNextBoundary(beat, max(max(0.01, stepBeats), passBeats))
    }
}
/// The next multiple of `unit` at or after `b` (a tap exactly on a boundary launches now, not a whole unit later).
private func ferryNextBoundary(_ b: Double, _ unit: Double) -> Double {
    guard unit > 0 else { return b }
    let floorB = (b / unit).rounded(.down) * unit
    return floorB >= b - 1e-9 ? floorB : floorB + unit
}

// MARK: - MPE detection (§ receiver property) — auto-detect the MPE controller for the cog-page indicator

/// A receiver is likely fed by an MPE controller when its recent note-ons spanned ≥2 distinct channels — MPE
/// spreads each note to its own member channel, an ordinary source uses one. `channelMask` bit i = channel i
/// (0-based) heard this window. Pure — drives the per-receiver MPE-detected light (a single-channel receiver
/// never trips it, so detection is meaningful only under OMNI / MPE-merge).
func mpeLikely(channelMask: UInt16) -> Bool { channelMask.nonzeroBitCount >= 2 }

// MARK: - UMP (MIDI 2.0 / eventList) → legacy 3-byte MIDI (§item 11 INPUT CABLES — the eventList path)

/// UMP message word count by Message Type (top nibble of word0), per the UMP spec — lets the parser
/// stride packet words without decoding every message.
func umpWordCount(mt: Int) -> Int {
    switch mt {
    case 0x0, 0x1, 0x2, 0x6, 0x7: return 1
    case 0x3, 0x4, 0x8, 0x9, 0xA: return 2
    case 0xB, 0xC: return 3
    default: return 4                       // 0x5, 0xD, 0xE, 0xF
    }
}

/// Convert a UMP Channel-Voice message to legacy 3-byte MIDI + its GROUP (0–15, the cable equivalent).
/// Handles MIDI-1.0 CV (MT 0x2, 1 word — already 7-bit) and MIDI-2.0 CV (MT 0x4, 2 words — note on/off,
/// CC, channel pressure, pitch bend, downscaled to 7/14-bit). Returns nil for any other message type.
func umpToLegacy(_ w0: UInt32, _ w1: UInt32) -> (b0: UInt8, b1: UInt8, b2: UInt8, len: Int, group: Int)? {
    let mt = Int((w0 >> 28) & 0xF)
    let group = Int((w0 >> 24) & 0xF)
    if mt == 0x2 {                          // MIDI 1.0 CV in UMP: [MT|grp][status][d1][d2]
        let status = UInt8((w0 >> 16) & 0xFF)
        let hi = status & 0xF0
        let len = (hi == 0xC0 || hi == 0xD0) ? 2 : 3
        return (status, UInt8((w0 >> 8) & 0x7F), UInt8(w0 & 0x7F), len, group)
    }
    guard mt == 0x4 else { return nil }     // MIDI 2.0 CV
    let chan = UInt8((w0 >> 16) & 0xF)
    let idx = UInt8((w0 >> 8) & 0x7F)
    switch (w0 >> 20) & 0xF {               // status nibble
    case 0x8: return (0x80 | chan, idx, 0, 3, group)                                     // note-off
    case 0x9: return (0x90 | chan, idx, clampVel(Int((w1 >> 16) & 0xFFFF) >> 9), 3, group)  // note-on (16→7, min 1)
    case 0xB: return (0xB0 | chan, idx, UInt8((w1 >> 25) & 0x7F), 3, group)              // CC (32→7)
    case 0xD: return (0xD0 | chan, UInt8((w1 >> 25) & 0x7F), 0, 2, group)                // channel pressure
    case 0xE: let v14 = (w1 >> 18) & 0x3FFF                                              // pitch bend (32→14)
              return (0xE0 | chan, UInt8(v14 & 0x7F), UInt8((v14 >> 7) & 0x7F), 3, group)
    default:  return nil
    }
}

@inline(__always)
func cellMode(type: ProcessorType, bypassed: Bool) -> CellMode {
    if bypassed { return .identity }                       // §3: bypass = identity processor
    switch type {
    case .arp:       return .arp
    case .ratchet:   return .ratchet
    case .strum:     return .strum
    case .chance:    return .chance
    case .harmonize: return .harmonize
    case .echo:      return .echo                          // the tail stage — its dry strikes + registers repeats
    case .euclid:    return .euclid                         // GENERATOR — K-of-N euclidean rhythm
    case .burst:     return .burst                          // GENERATOR — accel/decel roll at step entry
    case .cascade:   return .cascade                        // GENERATOR — incremental chord reveal
    case .drone:     return .drone                          // GENERATOR — flat sustained pad
    case .shift:     return .shift                          // GENERATOR — groove nudge
    case .humanize:  return .humanize                       // GENERATOR — seeded jitter
    case .mod:       return .silent                          // CC GENERATOR — sounds NO notes (its CC is emitted separately)
    case .glide:     return .silent                          // notes→pitch-bend — its ONE mono voice is emitted separately (emitColumnGlide)
    case .tutti:     return .tutti                            // SET-level chance — a per-step HOLD transform (SOLO/TUTTI), never a driver
    case .length:    return .length                           // per-slice GATE override — re-articulates a hold; overrides a driver's gates downstream
    case .weave:     return .weave                            // DRIVER — each held note ticks on its own rank-derived clock (polyrhythm)
    case .riff:      return .riff                             // DRIVER — a stored RANK stencil derived against the held chord (the chord-following 303)
    case .hocket:    return .hocket                           // DRIVER — plays its pool timed by listening to another wire (GAPS/TRADE)
    case .split:     return .split                            // set-membership filter — keep a subset of the chord (a HOLD transform / set filter)
    case .avoid:     return .avoid                            // per-note PITCH filter — re-pool upstream, punch/shift downstream (like SPLIT, but by pitch-class vs a reference)
    case .chords:    return .chords                          // HARMONY — a held trigger → the diatonic chord for the current degree (a set-shaper like harmonize)
    case .octave:    return .octave                          // UTILITY — shift ±3 octaves (pitch transform)
    case .transpose: return .transpose                       // UTILITY — shift ±24 semitones
    case .channel, .nudge, .dest, .muteMatrix, .tap, .velocity, .deal, .clock, .killStep, .euclidMask: return .identity   // UTILITY/ROUTING/DYNAMICS/TIME — note-transparent; the emit-side effect (channel/timing/emitter/VELOCITY override · TAP's mid-chain send · DEAL's emitter deal · CLOCK/KILL STEP's beat transform · EUCLID MASK's per-note fold) applies elsewhere
    case .recorder:  return .identity                       // RECORDER (Stage 0, inert): note-transparent for now; record/playback lands in the engine stage
    case .empty:     return .identity                       // the "nothing here" sentinel — always a no-op passthrough
    }                                                      // roster complete — every type handled
}

// MARK: - HARMONIZE (§3): expand one note into itself + up to 3 transposed voices

/// The notes a HARMONIZE cell emits for one input `base` note: the root, then each non-zero interval
/// (−24…+24 st), clamped to MIDI range and de-duplicated (a unison/collision would just refcount).
/// Returns count; fills `out` (caller-sized ≥ 4). `scaledVel` gives each voice's velocity: the root
/// at `baseVel`, added voices scaled by `velScale`. Pure — no allocation (caller owns the buffer).
@inline(__always)
func harmonizeVoices(base: Int, intervals: (Int8, Int8, Int8),
                     into out: inout [Int], vel baseVel: UInt8, velScale: Double,
                     vels: inout [UInt8], poolMask: UInt16 = 0) -> Int {
    var n = 0
    func add(_ note: Int, _ v: UInt8) {
        guard note >= 0 && note <= 127 else { return }
        for i in 0..<n where out[i] == note { return }    // de-dup (unison → single voice)
        out[n] = note; vels[n] = v; n += 1
    }
    add(base, baseVel)                                     // root at full velocity
    let addedVel = clampVel(Int((Double(baseVel) * velScale).rounded()))
    // §2 POOL-STEP: a non-zero poolMask makes each interval a DEGREE step up the pool (the diatonic third, in key), else semitones.
    for iv in [intervals.0, intervals.1, intervals.2] where iv != 0 { add(poolMask != 0 ? poolStepMask(base, steps: Int(iv), pcMask: poolMask) : base + Int(iv), addedVel) }
    return n
}

// MARK: - CHANCE (§3): deterministic per-note-on probability gate

/// Whether a note-on at musical beat `beat` for `note` passes a `probability` (0…1) gate. DETERMINISTIC
/// — a pure hash of (position, note), NOT a live RNG — so it is loop-consistent: loop the host and the
/// same notes drop; play forward and each position re-rolls. The off follows its on's fate (§3): the
/// caller simply doesn't emit either when this returns false. Beat is quantized to a 1/64 grid so
/// buffer-alignment jitter can't change a note's fate mid-flight.
@inline(__always)
func chancePasses(beat: Double, note: Int, probability: Double) -> Bool {
    if probability >= 1 { return true }
    if probability <= 0 { return false }
    let q = Int64((beat * 64).rounded())
    let h = splitmix64Mix(UInt64(bitPattern: q) &* 0x9E3779B97F4A7C15 &+ UInt64(bitPattern: Int64(note &* 2654435761)))
    return Double(h >> 11) * (1.0 / 9_007_199_254_740_992.0) < probability
}
/// CHANCE with POOL-AWARENESS (user 2026-08-11), folding into the seeded `chancePasses`:
/// • CONSTANT-DENSITY: keep roughly a CONSTANT NUMBER of notes regardless of chord size — per-note p = min(1, prob·8/N)
///   (so a big chord thins to ~prob·8 notes, a small one passes). • WEIGHT/tilt (−1…1): bias which notes survive by
///   their RANK (0 = bottom … 1 = top); +tilt favours the TOP notes, −tilt the BOTTOM.
func chancePassesPool(beat: Double, note: Int, rank: Int, count: Int, probability: Double, tilt: Double, constantDensity: Bool) -> Bool {
    var p = probability
    if constantDensity && count > 0 { p = min(1.0, probability * 8.0 / Double(count)) }
    if tilt != 0 && count > 1 {
        let f = Double(rank) / Double(count - 1)      // 0 (bottom) … 1 (top)
        p = max(0, min(1, p + tilt * (f - 0.5)))
    }
    return chancePasses(beat: beat, note: note, probability: p)
}

// MARK: - RIFF DIRECTION = DRUNK (Paul 2026-09-28): the per-tick random-walk delta. Pure — a hash of (seed, tick), NOT
// a live RNG — so the SAME tick always draws the SAME delta (replay-safe at the draw level; only the WALK POSITION
// that accumulates these deltas needs render-side memory, kept in Router.swift alongside DEAL's own counters).
// `bias` (−1…1, 0 = neutral) tilts the {−1,0,+1} weights via a squared tilt: bias=0 → uniform 1/3 each ("wanders
// evenly"); bias=+1 → weights (0,1,4) → 0%/20%/80% (forward-dominant but never deterministic — "Forward with
// stumbles", never plain Forward); bias=−1 mirrors exactly. Continuous, no branching beyond the two thresholds.
@inline(__always)
func riffDrunkDelta(tick: Int64, bias: Double, seed: UInt64) -> Int {
    let b = clamp(bias, -1, 1)
    let wLo = max(0, 1 - b) * max(0, 1 - b), wHi = max(0, 1 + b) * max(0, 1 + b)
    let h = splitmix64Mix(seed &+ UInt64(bitPattern: tick) &* 0x9E3779B97F4A7C15)
    let u = Double(h >> 11) * (1.0 / 9_007_199_254_740_992.0) * (wLo + 1 + wHi)
    return u < wLo ? -1 : (u < wLo + 1 ? 0 : 1)
}

/// RIFF TIE LOOKAHEAD FIX (Paul 2026-09-28): the stencil step a non-DRUNK direction mode plays at absolute tick
/// `raw` — the SAME formula `emitRiffRow` uses for the CURRENT tick, factored out so a caller can also ask about
/// `raw+1`, `raw+2`, … and be guaranteed to agree with what will actually play (one formula, not two that could
/// drift — the RATCHET/DEST class of bug this project keeps finding when a lookup and its lookahead diverge).
/// RIFF's TIE run used to always check `step+1, step+2, …` (array-index order) regardless of which way the
/// playhead was actually moving — already wrong for REVERSE (whose true next step is `step-1`), and meaningless
/// for RANDOM/PENDULUM/PING-PONG once direction stopped being a fixed ±1. This function is pure in `raw`, so
/// "what plays next" is just this same formula one tick further on — exact, not a guess. DRUNK isn't a function
/// of `raw` (it's stateful, keyed on `tick`) — see `riffDrunkPeek` below for that mode's lookahead instead.
@inline(__always)
func riffStepAt(_ dir: RiffDir, raw: Int, steps: Int, seed: UInt64) -> Int {
    let fwd = ((raw % steps) + steps) % steps
    switch dir {
    case .forward:  return fwd
    case .reverse:  return steps - 1 - fwd
    case .pendulum: let per = max(1, 2 * (steps - 1)); let t = ((raw % per) + per) % per; return t < steps ? t : per - t
    case .pingpong: let per = 2 * steps; let t = ((raw % per) + per) % per; return t < steps ? t : per - 1 - t
    case .random:   return Int(splitmix64Mix(seed &+ UInt64(bitPattern: Int64(raw))) % UInt64(steps))
    case .drunk:    return fwd   // never actually reached — the caller branches to riffDrunkPeek before calling this; kept exhaustive rather than force-unwrapped
    }
}

/// MELODY TAB — RIFF MARKS ON THE NOTE BUTTONS (Paul 2026-10-13 ferry, Notes-row rule 6 + Riff-block item 1,
/// "the mini contour follows live edits"): every rank (1...8) this lane's walk can EVER land on, across every
/// direction/stride/rotate/length/INVERT/TRANSPOSE combination — so the Notes row can mark "the riff might
/// strike this button" without predicting WHEN. Walks a generously-bounded ordinal range (large enough to
/// guarantee full coverage for any LEN≤8/STRIDE≤7/direction combination — no need to derive an exact minimal
/// period per direction, this is cheap and main-thread-only, never on the render path) through the EXACT same
/// walk→rank pipeline `runEuclidLine` itself uses (`riffStepAt` → `riffRotateStep` → rank lookup → INVERT →
/// TRANSPOSE, in that order — mirrors Router.swift's own sequence precisely, so a mark can never show a rank
/// the engine wouldn't actually reach). DRUNK is not reachable here (removed from Euclideous's own WALK
/// directions by this same ferry) — `riffStepAt`'s `.drunk` case is never passed `dir` by any caller of this
/// function, so `seed` is always 0 and genuinely unused for every real direction.
func euclideousRiffReachableRanks(dir: RiffDir, length: Int, stride: Int, rotate: Int, ranks: [Int], invert: Bool, transpose: Int) -> Set<Int> {
    guard length > 0, !ranks.isEmpty else { return [] }
    var out = Set<Int>()
    for ord in 0..<(2 * 8 * 7) {
        let walkPos = riffStepAt(dir, raw: ord * stride, steps: length, seed: 0)
        let playedStep = riffRotateStep(walkPos, by: rotate, steps: length)
        guard playedStep < ranks.count else { continue }
        let rawRank = ranks[playedStep]
        guard rawRank >= 1 else { continue }   // rest — never reaches a note button
        let invRank = invert ? 9 - rawRank : rawRank
        let transposedRank = invRank + transpose
        if transposedRank >= 1 && transposedRank <= 8 { out.insert(transposedRank) }
    }
    return out
}

/// RIFF/NOTES SPLIT (Paul's third same-day ferry) — the RIFF tab's own mini-grid thumbnail (a static 8×8
/// preview, not a live walk) needs "what rank does STEP i show," independent of direction/stride/rotate
/// entirely (those shape WHEN the walk visits a step, not what that step's own rank IS) — a genuinely
/// different question from `euclideousRiffReachableRanks` above (which asks "across every ordinal this
/// lane could ever visit, which ranks show up at all"). Deliberately MASK-oblivious — LEAP/MIRROR/CLIMB
/// are live per-hit mask ROLLS, not a static per-step property a thumbnail can show (matching the ferry's
/// own "what the mini grid shows" wording precisely). Mirrors `Router.swift`'s own real per-hit
/// `invRank`/`transposedRank` formula exactly (the SAME two lines, not an approximation) — a rest (rank 0)
/// passes through untouched by both INVERT and TRANSPOSE, matching the engine's own "transpose only
/// applies when invRank >= 1" guard; a non-rest result can legally land outside 1...8 after TRANSPOSE
/// (the engine's own `riffResolve(wrap: .fold)` octave-extends it rather than rejecting it — the caller
/// decides how to render that, this function only resolves the rank).
func euclideousRiffStepRanks(ranks: [Int], invert: Bool, transpose: Int) -> [Int] {
    ranks.map { rawRank in
        let invRank = (invert && rawRank >= 1) ? (9 - rawRank) : rawRank
        return invRank >= 1 ? invRank + transpose : invRank
    }
}

/// RIFF TIE LOOKAHEAD FIX, the DRUNK case: a NON-MUTATING simulation of the walk `aheadBy` ticks past `fromPos`
/// (the already-resolved CURRENT position) — lets TIE ask "what does DRUNK actually play next" without touching
/// the real persisted walk state (`riffDrunkPos`/`riffDrunkLastTick` in Router.swift). Exact, not approximate:
/// since `riffDrunkDelta` is itself a pure function of `tick`, replaying it for `tick+1…tick+aheadBy` from the
/// walk's own current position reproduces PRECISELY the steps the real walk will take when it actually reaches
/// those ticks (holding bias/steps/seed constant, which TIE's own short lookahead window always does in practice).
@inline(__always)
func riffDrunkPeek(fromPos: Int, tick: Int64, aheadBy: Int, steps: Int, bias: Double, seed: UInt64) -> Int {
    var pos = fromPos
    guard aheadBy > 0 else { return pos }
    for k in 1...aheadBy {
        var np = pos + riffDrunkDelta(tick: tick &+ Int64(k), bias: bias, seed: seed)
        if np < 0 { np = -np }
        if np > steps - 1 { np = 2 * (steps - 1) - np }
        pos = max(0, min(steps - 1, np))
    }
    return pos
}

/// EUCLIDEOUS RIFF ADVANCE (Paul 2026-10-06): applies a lane's own HORIZONTAL offset to an already-resolved riff
/// step index — mirrors `euclidPatternInto`'s own rotation convention exactly (`buf[i] = pattern[(i + rot) % n]`,
/// i.e. rotate shifts the READ index forward by `+rot`), so a positive rotate reads the same direction EUCLID's
/// own ROTATE already does. Pure, and always returns a value in `0..<steps` regardless of sign (Swift's `%` can
/// return negative for a negative operand, so the double-mod is load-bearing, not decorative).
@inline(__always)
func riffRotateStep(_ step: Int, by rotate: Int, steps: Int) -> Int {
    guard steps > 0 else { return 0 }
    return ((step + rotate) % steps + steps) % steps
}

// MARK: - TUTTI (Paul 2026-08-13): SET-level chance — decided ONCE per step for the whole held set (CHANCE's cousin)

/// Whether a step is TUTTI (the whole set passes) vs SOLO (one note). DETERMINISTIC per STEP — a pure hash of the
/// step INDEX only (no per-note term), so the whole set shares one fate and it's loop-consistent like `chancePasses`.
/// `step` is the column-step index derived from musical position (replay-exact); `balance` = P(TUTTI).
@inline(__always)
func tuttiIsTutti(step: Int, balance: Double) -> Bool {
    if balance >= 1 { return true }
    if balance <= 0 { return false }
    let h = splitmix64Mix(UInt64(bitPattern: Int64(step)) &* 0x9E3779B97F4A7C15 &+ 0xD1B54A32D192ED03)   // step-only seed, salted apart from chance
    return Double(h >> 11) * (1.0 / 9_007_199_254_740_992.0) < balance
}

/// The surviving rank on a SOLO step, by PICK, over `count` ascending ranks (0 = LOW … count−1 = HIGH). LOW/HIGH are
/// fixed; RANDOM is a seeded per-step pick; CYCLE walks the solo one rank per step. Pure + deterministic per `step`.
@inline(__always)
func tuttiSoloRank(step: Int, count: Int, pick: TuttiPick) -> Int {
    guard count > 1 else { return 0 }
    switch pick {
    case .low:    return 0
    case .high:   return count - 1
    case .random: return Int(splitmix64Mix(UInt64(bitPattern: Int64(step)) &* 0x2545F4914F6CDD1D &+ 0x9E3779B97F4A7C15) % UInt64(count))
    case .cycle:  return ((step % count) + count) % count
    }
}

// MARK: - STRUM (§3): stagger a chord's onsets over `spread`, with a timing curve and velocity tilt

/// The onset delay (in beats, 0…spread) for strum position `j` of `count` notes. curve 0 = even
/// spacing; curve>0 bunches the early notes then opens out; curve<0 the reverse (exp = 2^curve, so
/// ±1 → ×2 / ÷2 of the linear fraction). ASSUMPTION: this curve shape is a feel choice — tune freely.
@inline(__always)
func strumOffset(index j: Int, count: Int, spread: Double, curve: Double, normalize: Bool = true) -> Double {
    guard count > 1 else { return 0 }
    let frac = Double(j) / Double(count - 1)              // 0 (first) … 1 (last)
    let shaped = pow(frac, pow(2.0, curve))              // curve 0 → linear
    // §3 SPREAD NORMALIZE (pool-aware-family, honorable): normalize (default) → the rake spans `spread`
    // beats regardless of the pool size (three notes or six, the same width). PER-NOTE (off) → `spread`
    // is a reference 4-note rake's TOTAL, so the gap between adjacent onsets is fixed and the rake WIDENS
    // with the pool (clamped ≤ 1 beat so a big chord can't overrun its column).
    let width = normalize ? spread : min(1.0, (spread / 3.0) * Double(count - 1))
    return width * shaped
}

/// Velocity for strum position `j`. tilt 0 = flat at base; tilt>0 crescendos across the strum
/// (first softer, last louder), tilt<0 decrescendos. ASSUMPTION: linear tilt around the base.
@inline(__always)
func strumVelocity(index j: Int, count: Int, tilt: Double, base: Int) -> UInt8 {
    guard count > 1 else { return clampVel(base) }
    let frac = Double(j) / Double(count - 1)              // 0 … 1
    let scale = 1 + tilt * (frac - 0.5)                  // [1 − tilt/2 … 1 + tilt/2]
    return clampVel(Int((Double(base) * scale).rounded()))
}

/// Which SORTED-pool index strum position `j` maps to, per direction. ALTERNATE flips per pass
/// (position-derived, drift-free): even passes strum UP, odd passes DOWN.
@inline(__always)
func strumSortedIndex(position j: Int, count: Int, direction: StrumDir, pass: Int) -> Int {
    let up: Bool
    switch direction {
    case .up:        up = true
    case .down:      up = false
    case .alternate: up = (((pass % 2) + 2) % 2) == 0
    }
    return up ? j : (count - 1 - j)
}

// MARK: - RATCHET velocity ramp (§3)

/// Velocity for ratchet repeat `index` of `count`. ramp 0 = flat at base; ramp 1 = crescendo from
/// ~silent up to base (first hit softest, last full). ASSUMPTION: crescendo direction — flip if the
/// feel should accent the first hit instead.
@inline(__always)
func ratchetVelocity(base: Int, ramp: Double, index: Int, count: Int) -> UInt8 {
    guard count > 1 else { return clampVel(base) }
    let frac = Double(index) / Double(count - 1)          // 0 (first) … 1 (last)
    let scale = (1.0 - ramp) + ramp * frac                // ramp 0 → 1; ramp 1 → frac
    return clampVel(Int((Double(base) * scale).rounded()))
}

// MARK: - Authoring: PLACE per-hold one-per-column (/btw ⑥)

enum PlaceHoldDecision: Equatable { case allowed, blockedColumnUsed }

/// /btw ⑥ — during a single PLACE hold at most ONE cell may be placed per column. A FRESH tap in a
/// column that already holds a cell placed THIS hold is BLOCKED (release + re-hold to stack a second in
/// that column). Re-tapping a cell this hold already placed is NOT a fresh place (it toggles the cell
/// off), so callers pass `retoggle: true` and it is always allowed. Pure so the column rule is
/// unit-testable independent of the SwiftUI hold state. Applies to taps, row chevrons, AND strokes.
func placeHoldDecision(placedColumns: Set<Int>, retoggle: Bool, col: Int) -> PlaceHoldDecision {
    if retoggle { return .allowed }
    return placedColumns.contains(col) ? .blockedColumnUsed : .allowed
}

// MARK: - Visual overhaul: EMBLEMS (cells & machine desk, AcceptanceCriteria 2026-07-29)

/// ONE static glyph per processor type — the "emblem" drawn on the cell face + the desk title. Placeholder
/// SF Symbol names this wave (the drawn artwork is a separate asset job). Pure so the mapping is testable.
func emblemSymbol(_ t: ProcessorType) -> String {
    switch t {
    case .arp:       return "chart.line.uptrend.xyaxis"   // the climb
    case .ratchet:   return "bolt.fill"                   // the burst
    case .empty:     return "square.dashed"               // the sentinel — never shown as a real card
    case .strum:     return "fanblades.fill"              // the fan
    case .chance:    return "die.face.5.fill"             // the die
    case .tutti:     return "die.face.6.fill"             // the set-die (SOLO vs the whole band)
    case .length:    return "ruler"                        // the measured duration
    case .weave:     return "square.stack.3d.up.fill"      // interlocking layers — the rank clocks
    case .split:     return "square.split.2x1"             // keep a slice of the set
    case .harmonize: return "circle.hexagongrid.fill"     // the bloom
    case .echo:      return "repeat"                       // the tail
    case .euclid:    return "circle.grid.cross"            // the K-of-N grid
    case .burst:     return "wind"                         // the accelerating gust
    case .cascade:   return "arrow.down.right.and.arrow.up.left.circle"   // the incremental reveal
    case .drone:     return "waveform.path"               // the sustained pad
    case .shift:     return "arrow.right.to.line"         // the nudge
    case .humanize:  return "hand.draw"                   // the human hand
    case .mod:       return "dial.medium"                 // the CC generator (a control dial)
    case .glide:     return "point.topleft.down.to.point.bottomright.curvepath"   // the slide
    case .octave:    return "arrow.up.arrow.down"           // UTILITY — octave shift
    case .transpose: return "arrow.up.and.down.text.horizontal"   // UTILITY — semitone shift
    case .channel:   return "cable.connector"              // UTILITY — output channel override
    case .nudge:     return "arrow.left.and.right"         // UTILITY — time offset
    case .velocity:  return "chart.bar.fill"               // DYNAMICS — per-step velocity lane (accents)
    case .dest:      return "arrow.triangle.branch"        // ROUTING — per-step emitter (the hocket)
    case .deal:      return "rectangle.split.2x1"          // ROUTING — deal notes across two emitters
    case .recorder:  return "record.circle"                // TIME — the looper-in-a-chain (record + replay)
    case .clock:     return "clock.arrow.2.circlepath"      // TIME — a placeable pattern-clock transform
    case .killStep:  return "square.slash"                  // TIME — a step row that removes disabled steps from the downstream timeline
    case .euclidMask: return "line.3.horizontal.decrease.circle"   // DYNAMICS — a K-of-N mask FILTERING a driven rhythm (distinct from EUCLID's own grid glyph)
    case .muteMatrix: return "speaker.slash"               // ROUTING — per-step part-muting (the gate grid)
    case .riff:      return "music.note.list"              // DRIVER — the stored rank stencil (the chord-following line)
    case .tap:       return "arrow.turn.up.right"          // ROUTING — the mid-chain send (the stream turns off to a parallel wire)
    case .hocket:    return "ear"                           // DRIVER — listens to a wire; plays in its gaps / trades with it
    case .avoid:     return "hand.raised"                   // FILTER — the per-note pitch filter (avoid clashes / lock to key)
    case .chords:    return "pianokeys"                     // HARMONY — the derived diatonic progression
    }
}

/// VELOCITY (Paul 2026-09-07): the velocity OVERRIDE for step `col` of the per-step lane. Returns nil = PASSTHROUGH
/// (leave the note's own velocity untouched). A step marked in `pass` (pass[col] != 0), or `col` out of the drawn
/// `steps`, is passthrough; otherwise the lane value clamped to a legal note velocity 1…127 (never a vel-0 note-on,
/// which would read as a note-off — a MODIFIER must not silence). `col` wraps the drawn length. Pure/testable.
func velLaneStep(lane: [Int], pass: [Int], steps: Int, col: Int) -> Int? {
    guard steps > 0 else { return nil }
    let c = ((col % steps) + steps) % steps
    if c < pass.count && pass[c] != 0 { return nil }   // explicit PASSTHROUGH step
    guard c < lane.count else { return nil }
    return max(1, min(127, lane[c]))                    // the override
}

/// CHORDS PATTERN (SPEC-chords-stage §2): the DEGREE at grid step `step` from the drawn matrix. −1 = CARRY (empty column →
/// hold the previous chord) · 0…6 = degree I…vii · 7 = REST (explicit silence). CARRY scans back to the last real degree
/// (wrapping the 8-step loop once); an all-carry matrix ⇒ REST. `rotate` strides the matrix. Returns (degree, isRest). Pure.
func chordsDegreeAt(step: Int, degrees: [Int], rotate: Int) -> (degree: Int, rest: Bool) {
    let n = degrees.count
    guard n > 0 else { return (0, true) }
    func at(_ s: Int) -> Int { degrees[((s + rotate) % n + n) % n] }
    let here = at(step)
    if here == 7 { return (0, true) }                       // explicit REST
    if here >= 0 { return (here, false) }                   // a real degree
    for back in 1...n {                                     // CARRY: walk back to the last non-empty column
        let d = at(step - back)
        if d == 7 { return (0, true) }                      // a rest holds the silence
        if d >= 0 { return (d, false) }
    }
    return (0, true)                                        // all-carry ⇒ nothing to hold → rest
}

/// What the CHORDS degree MATRIX should show at column `c` (Bugfix Paul 2026-09-15): `bright` = an AUTHORED degree /
/// explicit REST (a cell the user set); `faint` = the chord an unset/carry column actually CARRIES (so the matrix matches
/// the audio when the length is extended past the authored columns). Mirrors `chordsDegreeAt`'s carry (no live ROTATE —
/// the matrix is the authored score). Previously the editor lit a FALSE degree-0 (I) for carry columns. Pure/testable.
func chordsMatrixCell(_ degrees: [Int], step c: Int, steps: Int) -> (bright: Int?, faint: Int?) {
    let v = c < degrees.count ? degrees[c] : -1
    if v >= 0 && v <= 7 { return (v, nil) }                 // authored degree (0…6) or explicit REST (7) → BRIGHT
    let degs = (0..<max(1, steps)).map { $0 < degrees.count ? degrees[$0] : -1 }
    let r = chordsDegreeAt(step: c, degrees: degs, rotate: 0)
    return (nil, r.rest ? nil : r.degree)                   // CARRY → FAINT the carried chord; carry-to-silence → nothing
}

/// CHORDS FOLLOW (SPEC-chords-stage §1 — "the bounce"): the scale DEGREE (0-based) a played `note` NAMES, by pitch class in
/// the scale (root + tones). A note NOT in the scale snaps to the nearest degree (down-ties). So a bassline names the
/// progression: play the tonic → I, the fifth → V. Pure/testable.
func scaleDegreeOf(_ note: Int, root: Int, scaleTones: [Int]) -> Int {
    let n = scaleTones.count
    guard n > 0 else { return 0 }
    let pc = (((note - root) % 12) + 12) % 12               // pitch class relative to the root
    for (i, iv) in scaleTones.enumerated() where ((iv % 12) + 12) % 12 == pc { return i }
    var best = 0, bestD = 99                                // off-scale → nearest degree by pitch-class distance
    for (i, iv) in scaleTones.enumerated() {
        let ivpc = ((iv % 12) + 12) % 12
        let d = min((((ivpc - pc) % 12) + 12) % 12, (((pc - ivpc) % 12) + 12) % 12)
        if d < bestD { bestD = d; best = i }
    }
    return best
}

/// CHORDS WALK (SPEC-chords-stage §1 — "the gravity dice"): the degree at grid step `step`, chaining `walkNextDegree` from
/// the tonic at step 0. Recomputed each window from the base `seed` (per-step salt) so it's REPLAY-EXACT with NO accumulated
/// cross-render state; bounded (the grid loops). Pure/testable.
func chordsWalkDegreeAt(step: Int, seed: UInt64) -> Int {
    var deg = 0
    // The RATE clock is free-running (m/rate keeps advancing on a pinned/frozen audition), so `step` is unbounded. LOOP
    // the walk every 64 rate-ticks rather than CLAMPing (the old clamp froze the progression at step 64 forever). Modulo
    // keeps the recompute bounded AND replay-exact (pure fn of step) while the walk keeps evolving (a long 64-chord loop).
    let s = posMod(step, 64)
    var i = 0
    while i < s { deg = walkNextDegree(prev: deg, seed: seed &+ UInt64(i) &* 0x9E3779B97F4A7C15); i += 1 }
    return deg
}

// MARK: - GENERATORS (user 2026-08-08) — pure pattern derivations, testable off-device.

/// EUCLID — the K-of-N euclidean rhythm: `pulses` hits spread as evenly as possible across `steps`, a hit on step 0
/// (before rotation). `pattern[i] == true` ⇒ strike on step i. Exactly `pulses` hits. `rotation` cycles the pattern.
// Fill `buf[0..<n]` with the euclidean pattern (n = the resolved step count) — the no-alloc form for the render hot
// loop (buf is a caller-owned fixed buffer). Returns n. The array `euclidPattern` below wraps it for the tests.
@discardableResult func euclidPatternInto(_ buf: inout [Bool], pulses: Int, steps: Int, rotation: Int = 0) -> Int {
    let n = max(1, min(64, steps))
    guard buf.count >= n else { return 0 }
    let k = max(0, min(n, pulses))
    let rot = ((rotation % n) + n) % n
    for i in 0..<n { let src = (i + rot) % n; buf[i] = (src * k) % n < k }   // hit at step 0, rotated
    return n
}
func euclidPattern(pulses: Int, steps: Int, rotation: Int = 0) -> [Bool] {
    var buf = [Bool](repeating: false, count: max(1, min(64, steps)))
    let n = euclidPatternInto(&buf, pulses: pulses, steps: steps, rotation: rotation)
    return Array(buf[0..<n])
}
/// TILT (Paul 2026-10-08, REDESIGNED 2026-10-11): "a TILT control to bias the distribution of hits to the
/// left or right" — reshapes an already-built K-of-N pattern so the K hits cluster toward the START
/// (negative tilt), MIDDLE (tilt=0, today's even spread), or END (positive tilt) of the N-step cycle,
/// without changing K or N. Deterministic, not random (this engine's own standing invariant: derived,
/// never accumulated).
///
/// LINEAR BLEND, not a power curve (Paul: "indecipherable or unpredictable... I like the idea that a
/// slider could place emphasis or density early, middle or late" — a power curve (`rank^gamma`) is
/// perceptually NONLINEAR: most of its visible movement bunches in a narrow band of the control's travel,
/// so other parts feel like they do nothing). Each hit's position is now a straight interpolation between
/// its EVEN-SPREAD position (today's tilt=0 placement) and a fully-packed-at-one-end position, scaled
/// linearly by `|tilt|` — tilt=0.5 lands each hit exactly HALFWAY between even and fully-packed, matching
/// a physical slider's own position 1:1. `tilt=±1` reaches the fully-packed end EXACTLY (all K hits
/// crammed into the first/last K steps, in their original relative order).
///
/// CALL BEFORE ROTATION, not after (the OTHER half of the same fix — Paul: "the offset makes it look
/// indecipherable... maybe this could adjust to offset"). This function no longer has any opinion on
/// rotation; every caller now applies it to the UNROTATED pattern (`euclidPatternInto(..., rotation: 0)`)
/// and rotates the TILTED result afterward via `euclidRotateBuffer`, below. This decouples TILT's own
/// "early/middle/late" meaning from wherever OFFSET currently points — previously, biasing toward "early"
/// meant "near raw step 0," which OFFSET would then silently redefine by shifting what raw step 0 even
/// corresponds to in real time; now TILT always means "bias toward the start/middle/end of THIS pattern,"
/// and OFFSET just slides the already-shaped result around the column, so the two compose instead of
/// fighting.
///
/// A target position that collides with an already-placed hit (a rounding artifact — the underlying
/// un-rounded positions are provably strictly increasing in hit order for any blend, so a collision can
/// only ever happen between immediate neighbours) is nudged forward (wrapping) to the next free step —
/// deterministic and stable, never drops or duplicates a hit. K≤1 or N≤1 has nothing to tilt (a single hit
/// has no "distribution" to bias) and is left untouched. Pure/testable.
// HAND-EDITED PATTERN REBUILD (6-sliders ferry, Paul 2026-10-12, §7, literal): "Snapshot the pattern at
// touch-down. For each new target count, rebuild from that snapshot: add hits into the widest gap, or
// remove the auto hit in the most crowded spot. Hand-placed hits are kept. Rebuilding from the snapshot
// means dragging back to the starting count restores the pattern exactly."
//
// A PURE function of (snapshot, targetCount) — not incremental from whatever the live pattern happens to
// be right now. Calling this fresh, every drag tick, against the SAME touch-down snapshot is what makes
// "drag back to the start, get the start back" hold TRIVIALLY (targetCount == the snapshot's own count is
// checked first and returns the snapshot verbatim, byte-for-byte) rather than needing separate undo
// bookkeeping. Treats the pattern as CIRCULAR for both gap-finding and crowding — a Euclidean rhythm has
// no edge, wrapping is its natural topology (matches every other read of this buffer in the engine).
//
// JUDGMENT CALL, flagged plainly: "the AUTO hit" (as distinct from a hand-placed one) is read here as
// describing the REMOVAL as automatic/algorithmic, not as marking specific snapshot positions ineligible —
// there is no OTHER mechanism anywhere in this codebase for hand-placing one individual hit (no direct
// tap-to-toggle step editor exists), so every hit already in the snapshot is necessarily "auto" in that
// sense, and all are equally eligible for removal here. If a genuine hand-tap editor is ever built
// alongside this, the removal rule may need to change to actually protect those positions.
func euclidRebuildPattern(_ snapshot: [Bool], targetCount: Int) -> [Bool] {
    let n = snapshot.count
    guard n > 0 else { return snapshot }
    let target = max(0, min(n, targetCount))
    let currentCount = snapshot.filter { $0 }.count
    if target == currentCount { return snapshot }
    var buf = snapshot
    if target > currentCount {
        for _ in 0..<(target - currentCount) {
            guard let i = euclidWidestGapCenter(buf) else { break }
            buf[i] = true
        }
    } else {
        for _ in 0..<(currentCount - target) {
            guard let i = euclidMostCrowdedHit(buf) else { break }
            buf[i] = false
        }
    }
    return buf
}
/// The rest position nearest the MIDDLE of the longest circular run of consecutive rests — ties broken by
/// the earliest (lowest-index) widest gap found walking from the first hit. An all-rest buffer has no
/// "gap between hits" yet (nothing to bisect) — starts at step 0 by convention. Pure.
func euclidWidestGapCenter(_ buf: [Bool]) -> Int? {
    let n = buf.count
    guard n > 0, buf.contains(false) else { return nil }   // nothing to add to, or already full
    guard let start = buf.firstIndex(of: true) else { return 0 }   // all-rest: start the very first hit at 0
    var bestLen = -1, bestGapStart = -1
    var i = start
    repeat {
        var runLen = 0
        var j = (i + 1) % n
        while !buf[j] { runLen += 1; j = (j + 1) % n; if j == i { break } }
        if runLen > bestLen { bestLen = runLen; bestGapStart = (i + 1) % n }
        i = j
    } while i != start
    guard bestGapStart >= 0, bestLen > 0 else { return nil }   // every step already a hit
    return (bestGapStart + bestLen / 2) % n
}
/// The hit with the SMALLEST total surrounding space (the sum of its two circular neighbour-gaps) —
/// removing it merges those two gaps into the smallest possible single gap, the greedy choice that keeps
/// the remaining pattern as evenly spread as possible. Ties broken by the lowest index. Pure.
func euclidMostCrowdedHit(_ buf: [Bool]) -> Int? {
    let n = buf.count
    let hits = (0..<n).filter { buf[$0] }
    guard !hits.isEmpty else { return nil }
    if hits.count == 1 { return hits[0] }
    func gapTo(_ from: Int, _ to: Int) -> Int { ((to - from) % n + n) % n }
    var best = hits[0], bestSpace = Int.max
    for (k, h) in hits.enumerated() {
        let prev = hits[(k - 1 + hits.count) % hits.count]
        let next = hits[(k + 1) % hits.count]
        let space = gapTo(prev, h) + gapTo(h, next)
        if space < bestSpace { bestSpace = space; best = h }
    }
    return best
}

func euclidTiltPattern(_ buf: inout [Bool], pulses k: Int, steps n: Int, tilt: Double) {
    guard tilt != 0, k > 1, n > 1 else { return }
    var hits: [Int] = []
    for i in 0..<n where i < buf.count && buf[i] { hits.append(i) }
    guard hits.count == k else { return }   // a mismatched/empty buf (caller error) — leave untouched rather than guess
    let t = max(-1, min(1, tilt))
    var used = Set<Int>()
    var placed: [Int] = []
    for i in 0..<hits.count {
        let evenPos = Double(i) / Double(k - 1) * Double(n - 1)   // today's tilt=0 placement
        // Blend toward whichever end `t`'s sign points at — the OTHER end never enters the computation,
        // so a pattern can never accidentally lean the wrong way from a sign error.
        let packedPos = t < 0 ? Double(i) : Double(n - k + i)     // fully early (i) or fully late (n−k+i)
        let target = evenPos + abs(t) * (packedPos - evenPos)
        var pos = Int(target.rounded())
        pos = max(0, min(n - 1, pos))
        while used.contains(pos) { pos = (pos + 1) % n }   // deterministic collision nudge — bounded: ≤ n iterations total across all k placements
        used.insert(pos)
        placed.append(pos)
    }
    for i in 0..<n where i < buf.count { buf[i] = false }
    for p in placed where p < buf.count { buf[p] = true }
}
/// Cyclically shifts an already-built pattern buffer by `rotation` steps — the EXACT same read-index
/// convention `euclidPatternInto`'s own `rotation` parameter already applies internally
/// (`buf[i] = rawPattern[(i+rot) % n]`), just as a separate, later step so `euclidTiltPattern` (above) can
/// run on the UNROTATED pattern first. A plain cyclic shift; carries no opinion about hits/tilt/anything
/// else. Tolerates `buf.count > n` (only indices `0..<n` are read/written), matching `euclidPatternInto`'s
/// own convention. ZERO ALLOCATION (invariant 3 — this is called from `runEuclidLine`, on the render
/// path): the classic three-reversal in-place rotation (reverse `[0,r)`, reverse `[r,n)`, reverse the
/// whole thing) via `Array.swapAt`, not a copy-and-reindex — a first draft of this function built a
/// `Array(buf[0..<n])` snapshot before reassigning, a genuine render-thread heap allocation, caught before
/// it shipped.
func euclidRotateBuffer(_ buf: inout [Bool], steps n: Int, rotation rot: Int) {
    guard n > 1, buf.count >= n else { return }
    let r = ((rot % n) + n) % n
    guard r != 0 else { return }
    func reverse(_ lo: Int, _ hi: Int) {
        var l = lo, h = hi - 1
        while l < h { buf.swapAt(l, h); l += 1; h -= 1 }
    }
    reverse(0, r)
    reverse(r, n)
    reverse(0, n)
}
/// DIRECTION (Paul 2026-09-29, extended 2026-10-01 to 3-way FWD/BKW/PING-PONG) — maps a position already reduced
/// mod `euclidCycleLen(dir, n:)` to the buffer index to read. FWD reads the already-rotated buffer in order; BKW
/// reads it back-to-front — a genuine time-mirror of the hit pattern, NOT a second rotation (rotate-then-reverse
/// and reverse-then-rotate differ in general, by a shift of 2×rotate mod n, coinciding only at rotate=0 or n/2 —
/// verified algebraically). Flipping the READ index on the already-rotated buffer, rather than rebuilding it, is
/// the smallest change and keeps ROTATE meaning "where the forward reading starts" and DIRECTION meaning "which
/// way it's read from there." PING-PONG reuses RIFF's own `.pingpong` shape (`riffStepAt`) — period `2n`, each
/// endpoint sounding on two consecutive ticks at the turn, not RIFF's OTHER mode `.pendulum` (period `2(n-1)`,
/// never repeats an endpoint) — confirmed `.pingpong` is specifically the case RIFF's own UI labels "PING-PONG".
@inline(__always) func euclidReadIndex(_ raw: Int, n: Int, dir: EuclidDir) -> Int {
    let nn = max(1, n)
    switch dir {
    case .fwd: return raw
    case .bkw: return nn - 1 - raw
    case .pingpong: return raw < nn ? raw : 2 * nn - 1 - raw
    }
}
/// The real cycle length DIRECTION implies — FWD/BKW repeat every N ticks (unchanged from before PING-PONG
/// existed); PING-PONG repeats every 2N (it must bounce all the way out and back before repeating), so a caller
/// must reduce its raw tick count mod THIS, not mod `n`, before calling `euclidReadIndex` above.
@inline(__always) func euclidCycleLen(_ dir: EuclidDir, n: Int) -> Int { dir == .pingpong ? max(1, 2 * n) : max(1, n) }

// ── EUCLIDEOUS (Paul 2026-10-05) — pure, testable logic for the standalone 4-lane instrument page ──────────────────
// Lives here (not in EuclideousPage.swift, which imports SwiftUI) specifically so it reaches the Foundation-only
// macOS unit-test target — this codebase's own standing rule: "keep new pure logic in Derivations.swift so it
// stays testable."

/// NOTE/OCTAVE gesture tab's X-axis cycle list — the FULL remaining `EuclidNoteSel` set (not the existing 5-chip
/// *display-trimmed* list used elsewhere, which was trimmed for visual WIDTH, a constraint a drag gesture
/// doesn't have) — EXCLUDING `.riff`/`.arp`. Those two only resolve when the immediately-preceding chain slot
/// matches (Router.swift's `predType` check); Euclideous's cell has exactly one processor slot by construction,
/// so `predType` is permanently nil there — if the cycle ever landed on either, that lane would silently go
/// silent with no on-screen explanation (caught during planning, not discovered as a device bug).
// RANDOM REMOVED (Paul 2026-10-10 melody pop-up ferry §2.1) — the case itself and its decode/resolve
// path stay untouched (an old doc with `.random` saved still plays correctly, per the established
// `euclidNoteSelShown` precedent, GridUI.swift); only the offered cycle shrinks. Every consumer
// (`euclideousStepNoteSel` below, the 4th pad's commit sites and the new melody pop-up alike)
// dereferences this ONE array, so removing it here is the complete fix.
let euclideousNoteSelCycle: [EuclidNoteSel] = [.all, .n1, .n2, .n3, .n4, .n5, .n6, .n7, .n8, .low, .high, .bottom2, .top2, .cycle]

/// Steps an `EuclidNoteSel` by `delta` positions through `euclideousNoteSelCycle`, wrapping.
func euclideousStepNoteSel(_ cur: EuclidNoteSel, by delta: Int) -> EuclidNoteSel {
    let list = euclideousNoteSelCycle
    let i = list.firstIndex(of: cur) ?? 0
    let n = list.count
    return list[((i + delta) % n + n) % n]
}

// euclideousNextRate (a plain tap-to-advance 18-case cycle) REMOVED 2026-10-06 — Paul: "I hate the current
// control and want a pop-up"; EuclideousPage's own ratePopupCard lets the user pick a rate directly instead
// of cycling through all 18 one tap at a time (and never offering a way back to nil/"inherit the machine rate").
// ratePopupCard ITSELF then REMOVED 2026-10-12 (ratified PATTERN-tab-layout ferry) — RATE is now a division×
// feel grid living directly in the tab, no pop-up needed; see the two functions immediately below.

/// RATE = division × feel (ratified PATTERN-tab-layout ferry, 2026-10-12). `ArpRate` is ALREADY an 18-case
/// enum laid out in exactly 3 groups of 6 — straight, dotted (×1.5), triplet (×2/3), each 1/1…1/32
/// (CLAUDE.md invariant: `allCases` order never changes, rate persists by raw string) — so decomposing/
/// recomposing a division (0...5, matching 1/1…1/32) and a feel (0=straight·1=dotted·2=triplet) needs NO
/// new stored field at all; this is a pure display/edit reshaping of the ONE field that already exists
/// (`EuclidLine.rate: ArpRate?`). Confirms the ferry's own "stop and report before changing its parameter
/// ID or range" clause is a non-issue: nothing outside 1/1–1/32 straight/dotted/triplet has ever existed
/// in this enum, so there is no out-of-range value to migrate.
func euclideousRateDivisionFeel(_ rate: ArpRate) -> (division: Int, feel: Int) {
    let all = ArpRate.allCases
    let i = all.firstIndex(of: rate) ?? 0
    return (i % 6, i / 6)
}
func euclideousRateFromDivisionFeel(division: Int, feel: Int) -> ArpRate {
    let d = max(0, min(5, division)), f = max(0, min(2, feel))
    return ArpRate.allCases[f * 6 + d]
}

// ── SIX VERTICAL SLIDERS (usability ferry, 2026-10-12) — replaces the 3 two-axis gesture pads entirely
// (HITS/TILT shared one pad, OFFSET/STEPS shared another, GATE/VELOCITY the third; now six independent
// single-axis tracks: HITS · STEPS · OFFSET · TILT · GATE · VELOCITY). Pure logic lives here, not
// EuclideousPage.swift, for the usual reason — Foundation-only, so it reaches the macOS unit-test target.

/// One of the six independent slider fields, left-to-right as specified.
enum EuclideousSliderField: Int, CaseIterable {
    case hits = 0, steps = 1, offset = 2, tilt = 3, gate = 4, velocity = 5
    var name: String {
        switch self {
        case .hits: return "HITS"; case .steps: return "STEPS"; case .offset: return "OFFSET"
        case .tilt: return "TILT"; case .gate: return "GATE"; case .velocity: return "VEL"
        }
    }
    /// Long-press help text (ferry §3.3: "<60 chars").
    var help: String {
        switch self {
        case .hits: return "How many of the steps actually strike"
        case .steps: return "How many steps the pattern has"
        case .offset: return "Rotates the pattern around its steps"
        case .tilt: return "Bunches hits toward the start or end"
        case .gate: return "How long each note lasts, as a share of the time until the next hit. At 100%, notes join: different notes overlap slightly and repeated notes hold as one."   // 2026-10-13 ferry's own literal text — exceeds this file's older "<60 chars" guideline, used verbatim per explicit instruction
        case .velocity: return "How hard every hit strikes"
        }
    }
    /// HITS/STEPS/OFFSET snap to one of a fixed count of whole values (band-snapped, ferry Touch
    /// behaviour §3); TILT/GATE/VELOCITY are continuous across their range, rounded only for storage/
    /// display (§5).
    var isWhole: Bool { self == .hits || self == .steps || self == .offset }
}

/// The field's current value (in its own natural units — NOT normalized) and its current valid range,
/// read straight off the line. Pure — the ONE source both the drawn fill/tick positions and the
/// touch→value mapping read, so the two can never disagree about where a value currently sits.
func euclideousSliderRange(_ field: EuclideousSliderField, _ line: EuclidLine) -> (value: Double, lo: Double, hi: Double) {
    switch field {
    case .hits:
        let steps = max(2, min(16, line.steps))
        return (Double(line.pulses), 0, Double(steps))             // 0...STEPS, per the ferry's own literal range
    case .steps:
        return (Double(line.steps), 2, 16)                          // unchanged from the old pad's own min/max
    case .offset:
        // OFFSET DRAG DIRECTION (Paul, on-device: "I scroll left, the hits scroll right") — confirmed by
        // deriving the real formula, not guessed: `euclidPatternInto` reads `buf[i] = pattern[(i+rotate)%n]`,
        // so a fixed hit's own SCREEN position is `(hitIndex - rotate) mod n` — INCREASING rotate moves a
        // hit LEFT on screen. The raw `rotate mod n` value used to map directly onto this HORIZONTAL
        // slider's own left=low/right=high convention (a plain, unremarkable slider convention, confirmed
        // correct in isolation) — so dragging LEFT (lowering the displayed value) lowered `rotate`, which
        // by the formula above moves a hit RIGHT: backwards from what a horizontal drag should feel like.
        // Fixed by DISPLAYING/COMMITTING the MIRRORED quantity `(n - rotate) mod n` instead of raw rotate —
        // the stored field and `euclidPatternInto`'s own rotation convention are completely UNCHANGED (no
        // engine/model change, no effect on any other reader of `rotate`); only this ONE slider's own
        // value↔rotate correspondence is inverted, so dragging right (raising the displayed value) now
        // LOWERS rotate, which moves hits right — drag left moves them left, matching the report exactly.
        let n = max(2, min(16, line.steps))
        let r = ((line.rotate % n) + n) % n
        let displayed = (n - r) % n
        return (Double(displayed), 0, Double(n - 1))                // 0...STEPS-1
    case .tilt:
        return (line.tiltResolved, -1, 1)
    case .gate:
        // GATE FOLLOWS THE RHYTHM (2026-10-13 ferry) changed what this floor actually protects: GATE is no
        // longer a fraction of a fixed short tick (where 5% was already tiny) but a fraction of the REAL gap
        // to the lane's own next hit — which can be seconds long on a sparse pattern (Paul, on-device: "5 of
        // 16, rate 1/8" computes a ~750-1000ms gap, so even the old 5% floor produced a non-trivial ~40-50ms
        // note, not a short blip). The OLD floor's own justification (avoid a near-zero-length note) no
        // longer tracks the new formula's real behaviour — lowered to 1%, which the engine's own separate
        // absolute `minGateBeats5ms` floor (Router.swift) still backstops regardless of how low this goes.
        return (line.gateResolved, 0.01, 1)
    case .velocity:
        return (Double(line.velocityAbsoluteResolved), 1, 127)
    }
}

/// Where the CURRENT value sits along the track, 0 (bottom/min) ... 1 (top/max) — used both to draw the
/// fill/edge-line and (inverted) as the basis for the "did touch-down land on the same value" dedup.
func euclideousSliderFrac(_ field: EuclideousSliderField, _ line: EuclidLine) -> Double {
    let r = euclideousSliderRange(field, line)
    guard r.hi > r.lo else { return 0 }
    return max(0, min(1, (r.value - r.lo) / (r.hi - r.lo)))
}

/// Maps a touch position (0 = bottom/min ... 1 = top/max, already clamped by the caller against the
/// track's own 6pt insets) to the value that position commits — band-snapped for a whole-number field
/// (ferry Touch behaviour §3: "split the travel into equal bands, one per value, snap to the band under
/// the finger"), plain linear interpolation for a continuous one (§5). TILT's own centre detent (§4) is
/// applied separately, by the caller, BEFORE this — it's a pre-step on the touch fraction, not a
/// property of the generic mapping.
func euclideousSliderValueAt(_ field: EuclideousSliderField, _ line: EuclidLine, frac: Double) -> Double {
    let r = euclideousSliderRange(field, line)
    let f = max(0, min(1, frac))
    if field.isWhole {
        let count = Int((r.hi - r.lo).rounded()) + 1
        guard count > 1 else { return r.lo }
        let band = min(count - 1, Int(f * Double(count)))
        return r.lo + Double(band)
    }
    return r.lo + f * (r.hi - r.lo)
}

/// TILT's centre detent (ferry Touch behaviour §4, literal): "within ±6% of the travel around the
/// centre, the value is exactly 0." `frac` is the raw 0...1 touch position (0.5 = dead-centre); returns
/// the detented fraction, still 0...1, which the caller then feeds through the ordinary TILT range
/// mapping (−1...1) via `euclideousSliderValueAt` as normal — a pure pre-step on the touch position, not
/// a second, separate value formula.
func euclideousTiltDetentFrac(_ frac: Double) -> Double {
    abs(frac - 0.5) <= 0.06 ? 0.5 : frac
}

/// Tick-mark positions (0...1 each, matching `euclideousSliderFrac`'s own convention) — ONLY HITS and
/// OFFSET carry ticks (ferry, literal: "one tick per possible count" / "one tick per step"); every other
/// field has none.
func euclideousSliderTickFracs(_ field: EuclideousSliderField, _ line: EuclidLine) -> [Double] {
    switch field {
    case .hits, .offset:
        let r = euclideousSliderRange(field, line)
        let count = Int((r.hi - r.lo).rounded()) + 1
        guard count > 1 else { return [0] }
        return (0..<count).map { Double($0) / Double(count - 1) }
    default:
        return []
    }
}

/// Commits ONE slider's new value onto the line (ferry Engineering: "write values through the existing
/// parameter path" — this is the pure "what should the write actually DO" half; the real `edit(idx){...}`
/// call lives in EuclideousPage.swift). `snapshot` is the line as it stood at TOUCH-DOWN (ferry §7:
/// HITS-on-an-edited-pattern rebuilds from that FROZEN snapshot every tick, not incrementally, so
/// "dragging back to the start restores the pattern exactly" holds for free) — every other field ignores
/// it and reads `line` live, since only HITS' rebuild needs the frozen starting shape.
func euclideousSliderCommit(_ field: EuclideousSliderField, _ line: inout EuclidLine, snapshot: EuclidLine, newValue: Double) {
    switch field {
    case .hits:
        let steps = max(2, min(16, line.steps))
        let target = max(0, min(steps, Int(newValue.rounded())))
        if let snap = snapshot.customHitsResolved(steps) {
            // EDITED PATTERN (ferry §7, literal): rebuild from the FROZEN touch-down snapshot, not the
            // live (possibly already-rebuilt-this-drag) buffer — a pure function of (snapshot, target),
            // so re-landing on the starting count reproduces the exact original pattern, not a drifted one.
            line.customHits = euclidRebuildPattern(snap, targetCount: target)
        }
        line.pulses = target   // kept in sync regardless, so every OTHER reader of `pulses` needs no changes
    case .steps:
        let target = max(2, min(16, Int(newValue.rounded())))
        if target != line.steps {
            // STEPS genuinely CHANGING reverts an edited pattern to pure Euclid (ferry §8, ratified) — the
            // caller only invokes this commit when the mapped value actually differs from the pre-touch
            // one (rule 6, "no change, no commit"), so landing back on the SAME band never reaches here.
            line.customHits = nil
            line.steps = target
            if line.pulses > target { line.pulses = target }
        }
    case .offset:
        // Inverse of euclideousSliderRange's own mirror (see its comment) — `newValue` is the DISPLAYED
        // quantity the slider's drag position computed; converting it back to the stored `rotate` needs
        // the same `(n - v) mod n` mirror applied in reverse (it's self-inverse, so the identical formula
        // undoes it exactly).
        let n = max(2, min(16, line.steps))
        let v = Int(newValue.rounded())
        let mirrored = (n - ((v % n) + n) % n) % n
        line.rotate = mirrored
    case .tilt:
        guard line.customHits == nil else { return }   // disabled on an edited pattern — defensive; the UI never drags this
        line.tilt = max(-1, min(1, newValue))
    case .gate:
        line.gate = max(0.01, min(1, newValue))   // matches euclideousSliderRange's own lowered floor — see its comment
    case .velocity:
        line.velocityAbsolute = max(1, min(127, Int(newValue.rounded())))
    }
}

/// Reverts the field(s) THIS slider owns back to their touch-down snapshot values (long-press help,
/// ferry Touch behaviour §10: "restore the value from the touch-down snapshot, then show the help
/// bubble") — undoes whatever `euclideousSliderCommit` already wrote at touch-down, before the bubble
/// shows, so a long-press never leaves a stray accidental edit behind. Mutates only this slider's own
/// field(s), not the whole line, so a second finger mid-gesture on a DIFFERENT slider of the same lane
/// can't be clobbered by this one's revert.
func euclideousSliderRevert(_ field: EuclideousSliderField, _ line: inout EuclidLine, snapshot: EuclidLine) {
    switch field {
    case .hits: line.pulses = snapshot.pulses; line.customHits = snapshot.customHits
    case .steps: line.steps = snapshot.steps; line.customHits = snapshot.customHits
    case .offset: line.rotate = snapshot.rotate
    case .tilt: line.tilt = snapshot.tilt
    case .gate: line.gate = snapshot.gate
    case .velocity: line.velocityAbsolute = snapshot.velocityAbsolute
    }
}

/// Double-tap reset (ferry §9: "same defaults as the pads had") — mirrors the OLD per-pad double-tap
/// exactly: the old TILT/HITS pad only ever reset TILT (never HITS); the old OFFSET/STEPS pad only ever
/// reset OFFSET/rotate (never STEPS) — so HITS and STEPS have NO double-tap action here either, by the
/// same precedent, not an oversight.
func euclideousSliderDoubleTapDefault(_ field: EuclideousSliderField, _ line: inout EuclidLine) {
    switch field {
    case .hits, .steps: break
    case .offset: line.rotate = 0
    case .tilt: line.tilt = 0
    case .gate: line.gate = 0.9
    case .velocity: line.velocityAbsolute = 100
    }
}

/// VoiceOver adjustable-action step size (ferry Engineering, literal: "swipe up and down changes the
/// value by 1, or by 1% for GATE") — TILT given the SAME 1% treatment as GATE: a flat "1" step would
/// jump its entire −1...1 range in a single swipe, which can't be what "swipe changes the value" means
/// for a field shaped like a percentage, unlike VELOCITY/HITS/STEPS/OFFSET's true integer units. Flagged
/// as a judgment call, not a literal instruction — TILT isn't named in the ferry's own "or by 1% for
/// GATE" clause.
func euclideousSliderAccessibilityStep(_ field: EuclideousSliderField) -> Double {
    switch field {
    case .gate, .tilt: return 0.01
    default: return 1
    }
}

/// The slider's own compact value readout text — mirrors this page's existing display conventions (a
/// true minus sign for negatives, a bare "0" with no sign) without depending on `euclideousSigned`
/// (EuclideousPage.swift, `private`, unreachable from here) so this stays pure/testable.
func euclideousSliderValueText(_ field: EuclideousSliderField, _ line: EuclidLine) -> String {
    switch field {
    case .hits: return "\(line.pulses)"
    case .steps: return "\(line.steps)"
    case .offset:
        // Shows the SAME mirrored quantity the slider's own fill position represents (euclideousSliderRange's
        // `.offset` case) — raw `rotate` would disagree with where the fill visibly sits.
        let n = max(2, min(16, line.steps))
        let r = ((line.rotate % n) + n) % n
        return "\((n - r) % n)"
    case .tilt:
        let pct = Int((line.tiltResolved * 100).rounded())
        return pct == 0 ? "0" : (pct > 0 ? "+\(pct)%" : "−\(-pct)%")
    case .gate:
        return "\(Int((line.gateResolved * 100).rounded()))%"
    case .velocity:
        return "\(line.velocityAbsoluteResolved)"
    }
}
/// VoiceOver-only variant (2026-10-13 ferry §6: "add 'legato' to the value at 100%, for example 'Gate,
/// 100 percent, legato'") — the on-screen compact text stays bare "100%"; only the spoken value gains the
/// suffix, and only for GATE specifically, at the exact 100% boundary (matching the legato mode's own
/// threshold, not a near-100% approximation).
func euclideousSliderAccessibilityValueText(_ field: EuclideousSliderField, _ line: EuclidLine) -> String {
    let base = euclideousSliderValueText(field, line)
    guard field == .gate, Int((line.gateResolved * 100).rounded()) >= 100 else { return base }
    return "\(base), legato"
}
/// Paul, on-device (2026-10-14): "The label GATE should read as LEGATO when at 100%" — a SECOND, now VISIBLE
/// legato cue, distinct from the VoiceOver-only one above. Supersedes nothing — the VALUE text above the
/// label stays a bare "100%" (still `euclideousSliderValueText`, untouched); only the LABEL beneath it
/// (normally the field's bare `field.name`) swaps to "LEGATO" at the exact same 100% boundary. Scoped to the
/// on-screen label only — the accessibility LABEL (`field.name` at the slider's own `.accessibilityLabel`
/// call site) is deliberately left unchanged, since `euclideousSliderAccessibilityValueText` already
/// announces legato via the spoken VALUE; changing both would read as "Legato, 100 percent, legato" to
/// VoiceOver, a redundant double-announcement this file's own `EuclideousSlider` body doesn't need.
func euclideousSliderLabelText(_ field: EuclideousSliderField, _ line: EuclidLine) -> String {
    guard field == .gate, Int((line.gateResolved * 100).rounded()) >= 100 else { return field.name }
    return "LEGATO"
}

// ── NOTE VIEW (Paul 2026-10-10 ferry, "note view, phase 1") — pure note-naming + rhythm-window projection ──────────

/// §4.7, literal: "use the convention the rest of the app already uses. If none exists, MIDI 60 = C3, sharps by
/// default, flats when the current KEY is a flat key." CHECKED FIRST, not assumed: this codebase already has TWO
/// disagreeing note-name functions — `midiNoteName` (0-based octave, MIDI 60 = "C5") and `RackMatrix.noteName`
/// (standard C-1 convention, MIDI 60 = "C4") — and NEITHER matches the ferry's own literal example (`octave =
/// n/12 - 2`), and neither has any flat-vs-sharp logic at all. A third, NOTE-VIEW-only convention, exactly per
/// the ferry's own anticipated fallback — not a reuse, because there was nothing correct to reuse.
// 2026-10-13 ferry: always the Unicode glyphs ♯ (U+266F) / ♭ (U+266D), never ASCII "#"/"b" — the
// prior ASCII spelling was the root of the note-button-vs-riff-grid-label mismatch this ferry fixes.
let euclideousNoteNamesSharp = ["C", "C\u{266F}", "D", "D\u{266F}", "E", "F", "F\u{266F}", "G", "G\u{266F}", "A", "A\u{266F}", "B"]
let euclideousNoteNamesFlat  = ["C", "D\u{266D}", "D", "E\u{266D}", "E", "F", "G\u{266D}", "G", "A\u{266D}", "A", "B\u{266D}", "B"]
/// Fix 5 (2026-10-14 ferry, "FERRY — RIFF tab fixes"): how many semitones to SUBTRACT from a scale's own
/// root to reach its conventional "relative major" root — the reference every circle-of-fifths flat/sharp
/// bias is actually keyed on. Found and fixed by tracing the reported symptom (a C-minor pool spelling
/// D♯2/G♯2/A♯2 instead of E♭2/A♭2/B♭2) to `euclideousKeyIsFlat` testing the KEY'S OWN root directly — correct
/// only for MAJOR keys; `euclideousKeyTypeResolved` defaults a fresh/untouched Euclideous session to
/// `.naturalMinor`, so this bug was reachable on day one, not an edge case. Dorian/phrygian/lydian/mixolydian
/// use their literal scale-degree relationship to the major scale they're a mode of (e.g. D dorian's own
/// relative major is C, a shift of 2 semitones — verified against all four: root − shift ≡ 0 when the root
/// IS that degree of C major). The three minor variants share natural minor's own shift — their altered
/// degrees don't change which key signature is conventionally used to notate them. Major/minor pentatonic and
/// blues inherit whichever of major/minor they're built from. Whole-tone and chromatic have no relative-major
/// concept at all (every semitone is in play, or none are a privileged "7"), so they fall back to major's
/// shift (0) as a reasoned default — flagged here, not a literal music-theory convention.
func euclideousScaleRelativeMajorShift(_ t: ScaleType) -> Int {
    switch t {
    case .major, .majorPentatonic, .wholeTone, .chromatic: return 0
    case .naturalMinor, .harmonicMinor, .melodicMinor, .minorPentatonic, .blues: return 9
    case .dorian: return 2
    case .phrygian: return 4
    case .lydian: return 5
    case .mixolydian: return 7
    }
}
/// A standard circle-of-fifths sharp/flat bias — keyed on the scale's own RELATIVE MAJOR root (via
/// `euclideousScaleRelativeMajorShift`), not the bare key root, so a minor-family (or modal) key spells
/// correctly, not just a major one. `scaleType` defaults to `.major` (a no-op shift) so every pre-existing
/// call site — and the 3 pitch-class-table tests that predate scale-awareness — keep their exact prior
/// behaviour unless they explicitly pass the real key type. F/Bb/Eb/Ab/Db (of the RELATIVE MAJOR) read
/// flat; everything else reads sharp, including F#/Gb's own genuine enharmonic ambiguity (defaulted to
/// sharp, the more common convention when the choice is otherwise arbitrary) — a reasoned, not measured,
/// simplification, flagged as such rather than presented as definitive.
func euclideousKeyIsFlat(_ rootPitchClass: Int, scaleType: ScaleType = .major) -> Bool {
    let shift = euclideousScaleRelativeMajorShift(scaleType)
    let relRoot = (((rootPitchClass - shift) % 12) + 12) % 12
    return [5, 10, 3, 8, 1].contains(relRoot)
}
/// MIDI 60 → "C4" (standard convention; CORRECTED from the original "C3" anchor — see the 2026-10-14 ferry
/// §1 comment below `euclideousAccessibleNoteName` for why every one of its 11 worked chords only
/// reconciles against this anchor, forcing the same correction here for "one name per note everywhere").
/// Sharps or flats per `flatKey`.
func euclideousNoteViewName(_ n: UInt8, flatKey: Bool) -> String {
    let pc = Int(n) % 12
    let octave = Int(n) / 12 - 1
    let name = flatKey ? euclideousNoteNamesFlat[pc] : euclideousNoteNamesSharp[pc]
    return "\(name)\(octave)"
}
/// Splits a full note-view string ("D\u{266D}2", "C-2", or the empty-pool "–" placeholder) into its
/// letter+accidental part and its trailing octave-digit part, so a caller can render the two at different
/// sizes sharing a baseline (2026-10-13 ferry §6: "name 15pt heavy, octave number 10pt bold, sharing a
/// baseline"). A string with no digit/minus (the "–" placeholder) returns the whole thing as the note part
/// with an empty octave part.
func euclideousSplitNoteOctave(_ s: String) -> (note: String, octave: String) {
    guard let idx = s.firstIndex(where: { $0.isNumber || $0 == "-" }) else { return (s, "") }
    return (String(s[s.startIndex..<idx]), String(s[idx...]))
}
/// VoiceOver spelling (Paul 2026-10-12 ferry, "one global riff/note source" accessibility rule: "each is
/// 'Rank 3, E flat 3'") — the SAME pitch-class/octave math as `euclideousNoteViewName`, with "flat"/"sharp"
/// spelled out as words instead of the ♭/♯ glyphs VoiceOver would otherwise read awkwardly or silently drop.
func euclideousAccessibleNoteName(_ n: UInt8, flatKey: Bool) -> String {
    let pc = Int(n) % 12
    let octave = Int(n) / 12 - 1
    // Mirrors euclideousNoteNamesFlat/Sharp's own letter choice exactly per pitch class (a flat and a sharp
    // spelling of the SAME pitch class can be different LETTERS, e.g. pc=1 is "D flat" or "C sharp" — not
    // derivable from one shared letter table).
    let raw = flatKey ? euclideousNoteNamesFlat[pc] : euclideousNoteNamesSharp[pc]
    let letter = String(raw.first!)
    let suffix = raw.count > 1 ? (flatKey ? " flat" : " sharp") : ""
    return "\(letter)\(suffix) \(octave)"
}

// ── FERRY (2026-10-14, "Euclideous fixes from Paul's 14 Oct run") §1: NOTE NAMES WITH NO KEY ───────────────
//
// Every F♯ was reading G♭ (and every other non-natural pitch class too) whenever the source was MIDI IN or
// CHORD — `euclideousKeyIsFlat`'s only two call-sites outside KEY mode hardcoded `flatKey: true`
// unconditionally (confirmed by reading every one of the 4 call sites in EuclideousPage.swift before
// touching anything — none of them even looked at the held pool). This isn't a flats-vs-sharps bias to
// retune; a source with no key has no reason to prefer flats at all. Spelling now derives a ROOT from
// whatever's actually sounding, per Paul's literal algorithm.
//
// OCTAVE ANCHOR CORRECTED ALONGSIDE THIS, not asked for in so many words but required by the ferry's OWN
// worked examples: every one of its 11 test chords only reconciles against `octave = floor(MIDI/12) − 1`
// (MIDI 60 = C4, the standard convention) — e.g. "50 54 57 → D3 F♯3 A3" needs floor(50/12)−1=3, not the
// EXISTING `euclideousNoteViewName`'s own floor(n/12)−2 (MIDI 60 = C3, ratified 2026-10-10 as a reasoned
// fallback when nothing else existed to reuse). Hand-verified against all 11 worked chords before touching
// anything, not assumed from one example. "One name per note everywhere on the page" means this can't be a
// second, disagreeing octave convention for the no-key path alone — the SAME physical note must read the
// SAME octave number regardless of which source is selected — so `euclideousNoteViewName`/
// `euclideousAccessibleNoteName` (used by KEY mode, "as now") were corrected to the SAME anchor, not left at
// the old one. A real, disclosed consequence: a KEY-mode octave label that used to read "C3" at MIDI 60 now
// reads "C4" — a visible change to every existing Euclideous session's own KEY-mode display, flagged plainly
// rather than silently introduced as a side effect of the no-key fix.
let euclideousRootNamesMajor = ["C", "D\u{266D}", "D", "E\u{266D}", "E", "F", "F\u{266F}", "G", "A\u{266D}", "A", "B\u{266D}", "B"]
let euclideousRootNamesMinor = ["C", "C\u{266F}", "D", "E\u{266D}", "E", "F", "F\u{266F}", "G", "G\u{266F}", "A", "B\u{266D}", "B"]
private let euclideousLetterOrder: [Character] = ["C", "D", "E", "F", "G", "A", "B"]
private let euclideousLetterPitchClass: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
// "1–2 → next letter; 3–4 → 2 letters up; 5 → 3 up; 6–7 → 4 up; 8–9 → 5 up; 10–11 → 6 up" (ferry §1c,
// literal) — index by the semitone distance above R (1...11; index 0 unused, R itself is a separate case).
private let euclideousLettersUpByInterval = [0, 1, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6]

/// §1a/b, literal: R = the lowest note in `pool` (the chord's OWN known root and "the lowest held note" are
/// the SAME value for Euclideous's own CHORDS generator — `diatonicChord` always stacks ascending thirds
/// from the root, and its OPEN spread only ever lifts the MIDDLE voice, never the root, so after `.sorted()`
/// the root is provably always index 0 — verified by reading `diatonicChord` directly, not assumed — so this
/// one function correctly serves both MIDI IN and CHORD with no separate "known root" plumbing needed).
/// Minor table wins when the pitch class 3 semitones above R is present among the pool's OWN pitch classes
/// (a real minor third sounding), else major. `nil` for an empty pool (nothing to spell relative to).
func euclideousRelativeRoot(pool: [UInt8]) -> (pc: Int, minor: Bool)? {
    guard let lowest = pool.min() else { return nil }
    let rootPC = Int(lowest) % 12
    let pcs = Set(pool.map { Int($0) % 12 })
    return (rootPC, pcs.contains((rootPC + 3) % 12))
}

/// §1c/d, literal: every other note named by its distance above R, mapped to a diatonic letter count via
/// the ferry's own table, then given whatever accidental makes that letter's NATURAL pitch class match —
/// collapsing the four octave-crossing spellings (B♯→C, E♯→F, C♭→B, F♭→E) to their plain neighbour. A
/// double accidental (or worse) has no worked example in the ferry's own 11 test chords — falls back to the
/// established sharp/flat tables directly, biased toward the overshoot's own sign; flagged as a reasoned
/// extension of the literal rule, not independently verified. Octave is always `floor(n/12) − 1`, computed
/// from the RAW MIDI number regardless of which letter was chosen — never derived from the letter's own
/// position, which is exactly what keeps it correct even after a B♯→C-style substitution.
func euclideousRelativeNoteName(_ n: UInt8, pool: [UInt8]) -> String {
    guard let root = euclideousRelativeRoot(pool: pool) else { return "–" }
    let rootName = root.minor ? euclideousRootNamesMinor[root.pc] : euclideousRootNamesMajor[root.pc]
    let octave = Int(n) / 12 - 1
    let pc = Int(n) % 12
    if pc == root.pc { return "\(rootName)\(octave)" }
    let d = ((pc - root.pc) % 12 + 12) % 12
    guard let rootLetter = rootName.first, let rootLetterIdx = euclideousLetterOrder.firstIndex(of: rootLetter) else {
        return "\(rootName)\(octave)"
    }
    let lettersUp = euclideousLettersUpByInterval[d]
    let targetLetter = euclideousLetterOrder[(rootLetterIdx + lettersUp) % 7]
    let naturalPC = euclideousLetterPitchClass[targetLetter] ?? 0
    var diff = ((pc - naturalPC) % 12 + 12) % 12
    if diff > 6 { diff -= 12 }
    var name: String
    switch diff {
    case 0: name = String(targetLetter)
    case 1: name = "\(targetLetter)\u{266F}"
    case -1: name = "\(targetLetter)\u{266D}"
    default: name = diff > 0 ? euclideousNoteNamesSharp[pc] : euclideousNoteNamesFlat[pc]   // double accidental fallback
    }
    switch name {
    case "B\u{266F}": name = "C"
    case "E\u{266F}": name = "F"
    case "C\u{266D}": name = "B"
    case "F\u{266D}": name = "E"
    default: break
    }
    return "\(name)\(octave)"
}

/// VoiceOver twin of `euclideousRelativeNoteName`, built by reusing `euclideousSplitNoteOctave` (the SAME
/// note/octave split the KEY-mode accessible path already relies on) rather than re-deriving letter/octave
/// logic a second time.
func euclideousAccessibleRelativeNoteName(_ n: UInt8, pool: [UInt8]) -> String {
    let full = euclideousRelativeNoteName(n, pool: pool)
    guard full != "–" else { return "no note" }
    let split = euclideousSplitNoteOctave(full)
    var note = split.note
    var suffix = ""
    if note.hasSuffix("\u{266F}") { suffix = " sharp"; note.removeLast() }
    else if note.hasSuffix("\u{266D}") { suffix = " flat"; note.removeLast() }
    return "\(note)\(suffix) \(split.octave)"
}

/// ONE dispatcher, used at every note-display call site on the page (ferry §1's own "one name per note
/// everywhere" rule) — KEY keeps its existing key-driven sharp/flat choice ("as now"); MIDI IN and CHORD
/// both spell relative to the derived root above. `source` is intentionally the whole enum, not a bool, so
/// a future third no-key source can't be silently mis-read as "has a key."
func euclideousDisplayNoteName(_ n: UInt8, source: EuclideousLaneSource, pool: [UInt8], keyRoot: Int, keyType: ScaleType) -> String {
    if source == .key { return euclideousNoteViewName(n, flatKey: euclideousKeyIsFlat(keyRoot, scaleType: keyType)) }
    return euclideousRelativeNoteName(n, pool: pool)
}
func euclideousAccessibleDisplayNoteName(_ n: UInt8, source: EuclideousLaneSource, pool: [UInt8], keyRoot: Int, keyType: ScaleType) -> String {
    if source == .key { return euclideousAccessibleNoteName(n, flatKey: euclideousKeyIsFlat(keyRoot, scaleType: keyType)) }
    return euclideousAccessibleRelativeNoteName(n, pool: pool)
}

// ── FERRY §2: RIFF-GRID ARROWS MOVE LATE ────────────────────────────────────────────────────────────────
//
// ROOT CAUSE (confirmed by reading, not guessed): the riff-tab thumbnail reads `riffPositions[idx]` directly
// in the view body — a plain, reactive read, current as of whatever SwiftUI render the ~30fps AU poll last
// triggered. The grid's own arrow (`riffMarker`, a retained `@State` — genuinely needed, since a TIE/SKIP
// rest must hold the PREVIOUS marker rather than jump, which a pure read of current state alone can't
// express) was instead re-derived by a SECOND, independent 20Hz `Timer` — two unsynchronized wall-clock
// timers, with no phase coordination between them, so the arrow lagged the already-current `riffPositions`
// by up to one 20Hz period (50ms) on a quiet render, and considerably more whenever the RunLoop was busy
// around a bar line (several of the 20Hz timer's own ticks coalescing/delaying, "several things changing
// together... arrows of different lanes jump on the same frame even when their hits were 0.3s apart" —
// exactly what an unrelated, independently-scheduled timer falling behind under load looks like). FIX: the
// timer is removed; the view now re-derives `riffMarker` via `.onChange` on the SAME `riffPositions`/
// `wipeEvents`/`playingRiffIndex` state the thumbnail/footer already read reactively — "the same per-lane
// current riff step... on the same display tick," literally. The MATH below was always correct (it's the
// SAME per-lane step `updateRiffMarkers` already ran) — extracted to a pure function purely so the "no
// delay of any kind is built into the math itself" half of this fix is unit-testable; the TIMING half (did
// the view actually call this promptly) has no test-target reach and stays device-owed, as it always has
// for anything in EuclideousPage.swift.
/// One lane's next `riffMarker` value, given its current value and this render's live inputs. Not riff-on →
/// nil. Position out of range → unchanged (hold). A real rank at this position → jump there. A rest with a
/// matching fresh FILL event → jump there (that's where sound was actually produced). A rest with nothing
/// new → unchanged — rests are explicitly OUT OF SCOPE for this fix (Paul is deciding that separately).
func euclideousRiffMarkerStep(current: (col: Int, row: Int)?, riffOn: Bool, riffPosition: Int,
                               resolved: [Int], wipeEvent: Router.EuclideousNoteViewEventSnapshot?) -> (col: Int, row: Int)? {
    guard riffOn else { return nil }
    guard riffPosition >= 0, riffPosition < 8 else { return current }
    let col = riffPosition
    let rank = col < resolved.count ? resolved[col] : 0
    if rank != 0 { return (col, rank) }
    if let wipeEvent, wipeEvent.column == Int8(col), wipeEvent.rank >= 1 { return (col, Int(wipeEvent.rank)) }
    return current
}

// ── FERRY §4: LANE OUTPUT CHIP WHEN MAIN OUT IS OFF ─────────────────────────────────────────────────────
enum EuclideousLaneOutChipStyle: Equatable { case filled, hollowDashed, plain }
/// Ratified 7 Oct: "a lane chip routed to an emitter whose main toggle is off is drawn dashed/hollow" — the
/// drawing never implemented it; `laneOutRow` collapsed routed-but-main-off to the exact same look as
/// not-routed (both read the one boolean `routed && mainOn`). The ROUTING itself was always kept (confirmed
/// by Paul: the chip turns green again the instant main A comes back on) — only the drawing had no third
/// state to show it. `routed` alone decides the SHAPE; `mainOn` only matters once routed.
func euclideousLaneOutChipStyle(routed: Bool, mainOn: Bool) -> EuclideousLaneOutChipStyle {
    guard routed else { return .plain }
    return mainOn ? .filled : .hollowDashed
}

// ── FERRY §5: FLASH ON A HIT THAT PLAYS NOTHING ─────────────────────────────────────────────────────────
enum EuclideousHitFlashStyle: Equatable { case solid, outline }
/// "The solid flash means a note started" (Paul's own stated rule, generalised one step further than his
/// literal 4-case table): a rhythm hit that starts nothing gets an outline instead, matching LISTEN's own
/// convention for a dropped hit. `footerState` is the SAME prediction the footer band already draws from
/// (so the two can never disagree about which case applies); `onRest` is the one piece the footer's own
/// `.hitOnRest` classification doesn't yet carry — FILL plays a substitute note (solid), SKIP/TIE play
/// nothing new (outline). `.miss` (a genuine rhythm rest, OR "riff off with nothing lit" collapsing every
/// step to miss) is a reasoned EXTENSION beyond the ferry's own four literal test cases, not one of them —
/// flagged as such: nothing can sound there either, so the same "solid means a note started" principle
/// says outline, but no worked example in the ferry covers this specific combination. A nil `footerState`
/// (no footer info available at all, e.g. the regular BUILD-page EUCLID editor's own comet bar, which never
/// passes `footerStates`) defaults to `.solid` — today's unchanged behaviour, since that editor has no
/// riff/ON-REST concept to be wrong about.
func euclideousHitFlashStyle(footerState: EuclidFooterState?, onRest: EuclidRiffOnRest) -> EuclideousHitFlashStyle {
    guard let footerState else { return .solid }
    switch footerState {
    case .hit: return .solid
    case .hitOnRest: return onRest == .fill ? .solid : .outline
    case .miss: return .outline
    }
}

/// EXPLAIN SILENCE (usability ferry §2, literal priority order): the first applicable reason a lane that's
/// nominally "playing" can't actually produce a note right now, or nil when it genuinely can (nothing to
/// explain — the note box falls through to its normal content). HIT-vs-GAPS (0 HITS / NO GAPS) is checked
/// regardless of riff mode, since riff still rides on the SAME underlying K/N pattern to decide WHEN to
/// advance — a 0-hit or fully-packed-under-GAPS pattern produces no trigger ticks for a riff walk either,
/// not just for a plain strike. EMPTY RIFF is the one check that's riff-specific on top of that.
///
/// "NO NOTES HELD" is GONE (one global riff/note source ferry, 2026-10-12, "Live states" rule — "per-lane
/// note boxes keep their existing silent-state messages for every other cause but stop explaining this
/// one"): the per-lane box used to check the line's OWN (now decode-only) `sourceModeResolved`, which is
/// doubly wrong post-migration — every untouched line defaults to `.key`, not `.midi`, so this check would
/// almost never fire correctly even if kept; and the cause it used to explain is now explained ONCE, at the
/// page level, by the riff grid's own "HOLD NOTES TO PLAY" banner (`riffGridView`'s `midiEmpty` branch) — a
/// per-lane repeat of the identical message would be noise, not information, now that it's a single global
/// condition rather than 4 independent per-lane ones.
func euclideousSilenceReason(line: EuclidLine, mainOutMask: UInt8, riffAllRest: Bool) -> String? {
    guard line.enabledResolved else { return "STOPPED" }
    let emitterMask = line.emitterMask ?? 0
    guard emitterMask != 0 else { return "NO OUTPUT" }
    guard (emitterMask & mainOutMask) != 0 else { return "MAIN OUT OFF" }
    if line.patternMissResolved {
        if line.pulses >= line.steps { return "NO GAPS" }
    } else {
        if line.pulses <= 0 { return "0 HITS" }
    }
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second ferry): reads `riffOnResolved` now, not the stale
    // `useRiffResolved` — that accessor still derives from the OLD, now-unread `melodyMode`/legacy `useRiff`
    // chain, which no longer reflects whether a lane's riff is genuinely on once the new MELODY tab writes
    // `riffOn` directly (a real divergence, not just a rename — caught before shipping).
    if line.riffOnResolved && riffAllRest { return "EMPTY RIFF" }
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry), Elsewhere-on-the-page §1: "nothing
    // lit and the riff off" is a NEW silent state — nothing is wired to produce a note at all (neither
    // layer has anything to resolve), distinct from EMPTY RIFF (riff on, but its own pool is exhausted).
    // RIFF/NOTES SPLIT (third same-day ferry): the notes layer can now ALSO be switched off entirely
    // (`notesOnResolved`, independent of whether anything is still lit/remembered underneath it) — a
    // lane with riff off AND the notes layer off is silent regardless of what's lit, the direct
    // generalization of the prior "nothing lit" check to the new master switch.
    if !line.riffOnResolved && (!line.notesOnResolved || (line.litNotesResolved == 0 && !line.topLitResolved && !line.top2LitResolved)) { return "NO NOTES" }
    return nil
}

/// §2, the RHYTHM-only tick/window projection the track reuses — standalone and pure so it's unit-testable
/// without a live `EuclideousPage` render. Deliberately mirrors the REAL render path's own hit-test exactly
/// (`euclidPatternInto`+`euclidTiltPattern`+`euclidReadIndex`, the SAME pair/order `Router.runEuclidLine`
/// itself calls) plus the REAL span-reset formula (Router.swift's own `euclideousResetSpanBars > 0 ? ... : 0`
/// — NOT `EuclidLaneUI`'s own `EuclidCometBar` call sites, which hardcode `spanN: 0` and so do NOT reflect
/// Euclideous's page-level reset-span override at all) — so a projected mark can never silently disagree with
/// what the engine would actually decide for that tick. Only the RHYTHM (hit-vs-miss) is projectable this way;
/// §4's own ruling ("the pitch is decided only when the step plays") is exactly why PITCH is never computed
/// here — only the real render path, via the NOTE VIEW event queue (Router.swift), ever resolves one.

/// Builds a lane's pattern buffer ONCE — callers build this once per lane per animation frame (it doesn't
/// change tick-to-tick, only when the lane's own settings are edited), then reuse it for every tick query.
func euclideousNoteViewPattern(pulses: Int, steps: Int, rotate: Int, tilt: Double, patternMiss: Bool = false, customHits: [Bool]? = nil) -> [Bool] {
    let n = max(2, min(16, steps))
    let k = max(0, min(n, pulses))
    var buf = [Bool](repeating: false, count: n)
    // HAND-EDITED PATTERN (6-sliders ferry, Paul 2026-10-12): a non-nil `customHits` mirrors Router.swift's
    // own `runEuclidLine` exactly — the explicit pattern replaces generation, TILT is never consulted.
    if let custom = customHits, !custom.isEmpty {
        for i in 0..<n { buf[i] = i < custom.count ? custom[i] : false }
    } else {
        // TILT BEFORE ROTATION — a real, pre-existing bug fixed here in passing, found while touching this
        // function for the customHits change above: the 2026-10-11 TILT redesign (see `euclidTiltPattern`'s
        // own doc comment) explicitly names "THREE call sites" it updated to build unrotated, tilt, THEN
        // rotate (Router.swift's real engine, `euclideousRhythmPicture`, `EuclidCometBar`) — this function,
        // NOTE VIEW's own pure mirror of the pattern, was missed. It still baked `rotation: rotate` directly
        // into `euclidPatternInto` before tilting, which is NOT equivalent to tilt-then-rotate whenever
        // tilt != 0 (that non-equivalence is the whole reason the redesign was needed) — meaning NOTE VIEW
        // could show marks disagreeing with what the engine actually struck on any TILTed lane. Fixed to
        // match the other three sites exactly: build unrotated, tilt, THEN rotate via `euclidRotateBuffer`.
        euclidPatternInto(&buf, pulses: k, steps: n, rotation: 0)
        if tilt != 0 { euclidTiltPattern(&buf, pulses: k, steps: n, tilt: tilt) }
    }
    // ROTATE APPLIES ON TOP OF customHits TOO (found 2026-10-12, while building the riff-grid-markers/
    // footers ferry on top of this function): the real engine (Router.swift, `runEuclidLine`) calls
    // `euclidRotateBuffer` UNCONDITIONALLY, AFTER the if/else — "OFFSET still applies — it's a position-
    // shift on top of WHATEVER the base shape is, pure or edited, same as always" (its own comment). This
    // function had rotation INSIDE the `else` branch only, so a hand-edited pattern with a non-zero ROTATE
    // showed the UN-rotated hand-edited shape in NOTE VIEW — the exact RATCHET/DEST class of bug this
    // codebase's history keeps finding, confirmed here before it could silently feed wrong riff-step
    // numbers into the new footer strips. Moved out of the `else`, matching the engine exactly.
    euclidRotateBuffer(&buf, steps: n, rotation: rotate)
    // MISS = PATTERN INVERT (ferry 2026-10-10 §4.1: "comets on the inverted steps") — the SAME single
    // inversion point `Router.runEuclidLine` applies, so this pure NOTE VIEW mirror can never disagree with
    // what actually sounds.
    if patternMiss { for i in 0..<n { buf[i].toggle() } }
    return buf
}
// MARK: - RIFF POSITION MARKERS + LANE FOOTERS (Paul 2026-10-12 ferry) — a shared "which riff step will
// this hit play" prediction, reused by the riff grid's own per-lane position marker AND the new per-lane
// footer strips. Mask effects (MUTE/PAUSE/RATCHET/REPEAT/CHORD/OCT/MIRROR/LEAP/CLIMB/ACCENT/SWELL) are
// DELIBERATELY excluded (the ferry's own Prediction §3: "a footer shows what the lane itself will play") —
// confirmed sound by tracing every mode in Router.swift's `maskTransform`/the riff block: PAUSE pre-empts
// the whole riff advance before this prediction's own inputs would even apply; every other mode only
// changes the resolved NOTE/VELOCITY after a step has already been read, never which riff step is read
// (MIRROR/CLIMB change the resolved RANK post-lookup; LEAP substitutes a one-off read position for a single
// note without touching the persisted walk cursor) — so none of them belong in a prediction of the lane's
// OWN walk.

/// One hit of a lap: `bufIdx` is its position in the pattern BUFFER (direction-independent — the screen's
/// own step boxes are always drawn in buffer-index order, per this page's standing "boxes don't reorder,
/// only the comet's motion does" convention), `tick` is the REAL, direction-aware tick at which it actually
/// sounds within one cycle (`euclidReadIndex`'s own output space). For FWD the two coincide, which is why a
/// bare `Int` literal still constructs a valid value — every pre-existing call site/test written before
/// direction-awareness existed keeps compiling unchanged.
struct EuclidHitStep: Equatable, ExpressibleByIntegerLiteral {
    let tick: Int
    let bufIdx: Int
    init(tick: Int, bufIdx: Int) { self.tick = tick; self.bufIdx = bufIdx }
    init(integerLiteral value: Int) { tick = value; bufIdx = value }
}
/// One Euclid lap's hits, in TRUE TEMPORAL order — the ordinal walk this prediction needs is "which hit
/// number is this," in the order hits actually sound, not the order their buffer positions happen to be
/// numbered. DIRECTION FIX (2026-10-13 adversarial review): this previously always walked the buffer in
/// plain ascending index order regardless of `dir` — correct for FWD (where a real tick's buffer index IS
/// its tick number), silently WRONG for BKW (whose real engine, `euclidReadIndex`, reads the SAME buffer
/// back-to-front — the hit at the HIGHEST buffer index sounds FIRST, not last) and for PING-PONG (whose
/// real cycle is `2n`, each hit sounding once ascending then once descending). Fixed by walking the REAL
/// tick axis (`0..<euclidCycleLen(dir,n)`) and converting each tick to its buffer index via
/// `euclidReadIndex` — the EXACT pair the real engine itself uses — so a hit can never be reported out of
/// its true chronological order. `dir` defaults to `.fwd` so every pre-existing caller that never passed a
/// direction keeps its old, correct-for-FWD behaviour byte-for-byte.
func euclideousLapHitSteps(pulses: Int, steps: Int, rotate: Int, tilt: Double, patternMiss: Bool, customHits: [Bool]?, dir: EuclidDir = .fwd) -> [EuclidHitStep] {
    euclideousLapHitSteps(buf: euclideousNoteViewPattern(pulses: pulses, steps: steps, rotate: rotate, tilt: tilt, patternMiss: patternMiss, customHits: customHits), dir: dir)
}
/// The same walk over an already-FINISHED pattern buffer (`buf.count` = the step count) — what a FOLLOW lane needs, since its
/// pattern is its partner's, not anything built from its own pulses/steps.
func euclideousLapHitSteps(buf: [Bool], dir: EuclidDir = .fwd) -> [EuclidHitStep] {
    let n = buf.count
    let cycleLen = euclidCycleLen(dir, n: n)
    var out: [EuclidHitStep] = []
    for raw in 0..<cycleLen {
        let bufIdx = euclidReadIndex(raw, n: n, dir: dir)
        if buf[bufIdx] { out.append(EuclidHitStep(tick: raw, bufIdx: bufIdx)) }
    }
    return out
}

/// Derives `euclideousRiffCyclePrediction`'s own `startOrd`/`drunkLive` inputs from the LIVE poll (the
/// ordinal the walk's most recent hit advanced on, + DRUNK's own live position/ordinal) — the UI only ever
/// polls "where is the walk right now," never "where did the current lap begin," so this reconstructs the
/// latter exactly rather than approximating it. Under LOCK the walk re-anchors every lap by construction
/// (`runEuclidLine`'s own `cycleReset` — hard resets to ordinal/position 0 at the lap's first hit), so the
/// baseline is always exactly 0 regardless of where the live poll happens to be. Under FREE, the walk is
/// one continuous, never-resetting sequence — `liveOrd % effHits` (HIT mode) or finding which `hitSteps`
/// entry `liveOrd % lapSteps` matches (STEP mode, since under that mode the ordinal literally IS the
/// elapsed grid-step count) both recover exactly which hit-index-within-the-lap the most recent hit was,
/// letting the lap's own first-hit ordinal be recovered by simple subtraction.
func euclideousRiffLapBaseline(hitSteps: [EuclidHitStep], lapSteps: Int, locked: Bool, advanceStep: Bool,
                                liveOrd: Int64, dir: EuclidDir = .fwd)
    -> (startOrd: Int64, currentHitIndex: Int) {
    guard !hitSteps.isEmpty, lapSteps > 0 else { return (0, 0) }
    // LOCK re-anchors every lap, so no live ordinal is needed. HIT mode feeds the walk the hit's own index (0, 1, 2…, so the
    // lap starts at 0). ADV STEP feeds it the LAP-LOCAL TICK itself (`raw` in `runEuclidLine`) — the leading rests count — so
    // the lap's first hit sits at ordinal `firstTick`, not 0 (`euclideousRiffCyclePrediction` subtracts `firstTick`, which
    // this baseline puts back). With the first hit on tick 0 the two are the same, which is why this went unnoticed.
    if locked { return (advanceStep ? Int64(hitSteps[0].tick) : 0, 0) }
    let firstTick = hitSteps[0].tick
    if advanceStep {
        // DIRECTION FIX (2026-10-13 adversarial review): previously reduced `liveOrd` mod the plain buffer
        // length and compared the result directly against `hitSteps`' own BUFFER-INDEX values — correct
        // only for FWD (where tick == bufIdx). Now reduces mod the REAL cycle length (`euclidCycleLen`,
        // which is `2*lapSteps` for PING-PONG, not `lapSteps`) and matches against each hit's own `.tick` —
        // the exact axis `euclidReadIndex` itself operates on, so this works unambiguously for every
        // direction, including PING-PONG's doubled hits (each occurrence has its own distinct tick, so
        // there's no ambiguity about which pass of the bounce "now" belongs to).
        let cycleLen = euclidCycleLen(dir, n: lapSteps)
        let curTick = Int(((liveOrd % Int64(cycleLen)) + Int64(cycleLen)) % Int64(cycleLen))
        guard let k = hitSteps.firstIndex(where: { $0.tick == curTick }) else { return (liveOrd, 0) }
        let lapStartOrd = liveOrd - Int64(hitSteps[k].tick - firstTick)
        return (lapStartOrd, k)
    } else {
        let effHits = Int64(hitSteps.count)
        let curIdx = Int(((liveOrd % effHits) + effHits) % effHits)
        let lapStartOrd = liveOrd - Int64(curIdx)
        return (lapStartOrd, curIdx)
    }
}

/// The riff step (1-based, matching the grid's own displayed rank numbers) each of this lap's hits will
/// play, in hit order — one entry per `hitSteps` entry. `startOrd` is the baseline ordinal for this lap's
/// FIRST hit (0 under LOCK — the walk re-anchors every lap; the live running hit-count under FREE, so
/// consecutive laps continue the same unbroken walk). `advanceStep` mirrors `runEuclidLine`'s own HIT-vs-
/// STEP branch exactly: under STEP mode the ordinal advances by the real elapsed GRID-STEP count since the
/// lap's first hit, not by 1 per hit. DRUNK is not one of Euclideous's own WALK directions (2026-10-12
/// MELODY-tab ferry — removed; the generic chain RIFF processor keeps its own, unrelated DRUNK untouched),
/// so every direction here is a pure function of the ordinal alone — no live-walk state to poll.
func euclideousRiffCyclePrediction(hitSteps: [EuclidHitStep], advanceStep: Bool, dir: RiffDir, stride: Int, length: Int,
                                    rotate: Int, seed: UInt64, startOrd: Int64) -> [Int] {
    guard !hitSteps.isEmpty, length > 0 else { return [] }
    let firstTick = hitSteps[0].tick
    return hitSteps.enumerated().map { (hitIdx, hs) in
        // DIRECTION FIX (2026-10-13 adversarial review): STEP-advance's "elapsed real ticks since the lap's
        // first hit" must be measured on the TICK axis (`.tick`), not the buffer-index axis — the two only
        // coincide for FWD. See `EuclidHitStep`'s own doc comment.
        let advOrd: Int64 = advanceStep ? startOrd + Int64(hs.tick - firstTick) : startOrd + Int64(hitIdx)
        let walkPos = riffStepAt(dir, raw: Int(advOrd) * stride, steps: length, seed: seed)
        return riffRotateStep(walkPos, by: rotate, steps: length) + 1   // 1-based, matching the grid's own displayed rank numbers
    }
}

/// Per-step footer state (ferry Part 2) — `prediction` is `euclideousRiffCyclePrediction`'s own output,
/// `nil` when the lane has riff off entirely. `riffRanksResolved` is the shared grid's own resolved rank
/// array (0 = rest). A step not in `hitSteps` is always `.miss`, regardless of riff — INV/customHits are
/// already baked into `hitSteps` by the caller (via `euclideousLapHitSteps`), so this function needs no
/// separate awareness of either.
///
/// `anyLit` (Paul 2026-10-13, second same-day "lit notes plus the riff" ferry, Elsewhere-on-page §4):
/// SUPERSEDES the prior ferry's own riff-off rule ("every hit gets a plain filled footer, no number," i.e.
/// unconditional `.hit(riffStep: nil)`) with a 2-way split that now depends on whether anything is lit —
/// "riff off with notes lit: grey footers, no number" (still `.hit(riffStep: nil)`, just drawn grey at the
/// `laneFooter` call site, keyed off `riffStep == nil`) vs. "riff off with nothing lit: the miss footer,
/// because nothing will sound" (every step, hit or miss alike, becomes `.miss`).
enum EuclidFooterState: Equatable { case hit(riffStep: Int?), hitOnRest(riffStep: Int), miss }
func euclideousFooterStates(hitSteps: [EuclidHitStep], lapSteps: Int, prediction: [Int]?, riffRanksResolved: [Int], anyLit: Bool = true) -> [EuclidFooterState] {
    var out = [EuclidFooterState](repeating: .miss, count: max(0, lapSteps))
    guard prediction != nil || anyLit else { return out }   // riff off, nothing lit: every step is .miss
    // `.bufIdx` is the screen-box position (the footer row sits directly under the step boxes, which never
    // reorder); `i` (the enumerate index) still pairs correctly with `prediction`, since both this function
    // and `euclideousRiffCyclePrediction` walk the SAME `hitSteps` array in the same order. For PING-PONG,
    // one bufIdx can be written twice (once per leg of the bounce) — the later write wins, a minor disclosed
    // nuance, not a crash or an out-of-bounds risk.
    for (i, hs) in hitSteps.enumerated() where hs.bufIdx >= 0 && hs.bufIdx < out.count {
        guard let prediction, i < prediction.count else { out[hs.bufIdx] = .hit(riffStep: nil); continue }
        let riffStep = prediction[i]
        let isRest = riffStep >= 1 && riffStep <= riffRanksResolved.count && riffRanksResolved[riffStep - 1] == 0
        out[hs.bufIdx] = isRest ? .hitOnRest(riffStep: riffStep) : .hit(riffStep: riffStep)
    }
    return out
}

// MARK: - ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second ferry same day) — replaces the per-lane
// `sourceMode` with a single page-level source feeding every lane alike. `riffResolve(wrap: .fold)`
// (above) already does "ascending pool, extend by octaves for any rank beyond n" lazily, per-rank — this
// function materializes exactly the first 8 entries of that SAME extension for the new UI label column
// (which needs 8 concrete rows to draw, not an on-demand formula); rank-9-and-beyond resolution (TRANSPOSE)
// still goes straight through `riffResolve` against the RAW sorted pool, never this padded view.

/// Hand-verified against all 3 of the ferry's own worked examples: a 7-note key ([0,2,3,5,7,8,10] for C
/// natural minor, say) → the 7 + the root one octave up (8th entry); a 3-note chord → 3+3+2 (drops only
/// the would-be 9th); one note → that note repeated 8 octaves. `sortedRaw` must already be sorted
/// ascending (callers always sort before calling, so this stays a pure reshape, not a second sort).
func euclideousGlobalPoolExtended(sortedRaw: [Int]) -> [Int] {
    guard !sortedRaw.isEmpty else { return [] }
    var pool = sortedRaw
    var lap = 1
    while pool.count < 8 {
        pool.append(contentsOf: sortedRaw.map { $0 + 12 * lap })
        lap += 1
    }
    return Array(pool.prefix(8))
}

/// Euclideous's own global reset-span override (§2.2 history) — `resetSpanBars > 0` re-anchors every `cyc`
/// beats; 0 = free-run. `cyc` is the session's own "one bar" beat length (already computed throughout
/// Router.swift/this page for every other span calculation).
func euclideousNoteViewSpanBeats(resetSpanBars: Int, cyc: Double) -> Double {
    resetSpanBars > 0 ? Double(resetSpanBars) * cyc : 0
}
/// Reset-progress fraction (ferry "riff-cell wipes, reset progress on lane cards" §3.2) — 0 just after a
/// reset, approaching 1 just before the next. Built on the SAME `columnStart` Router.swift itself uses to
/// find the real reset boundary (`spanStart`, the DRUNK hard-reset trigger) — by construction, this can
/// never visually disagree with when the engine actually resets. `spanBeats <= 0` (RESET SPAN off) ⇒ 0,
/// the caller's own job to additionally hide the fill entirely in that case (§3.3).
func euclideousResetProgress(liveBeat: Double, spanBeats: Double) -> Double {
    guard spanBeats > 0 else { return 0 }
    return max(0, min(1, (liveBeat - columnStart(liveBeat, spanBeats)) / spanBeats))
}
/// Whole bars remaining until the next reset (ferry §4.1: "IN n... counting down 8, 7, ... 1 for an
/// 8-bar span"), clamped to `1...resetSpanBars` so it reads `resetSpanBars` at the instant a window
/// starts and never displays 0. `cyc` is one bar in beats (the same quantity `spanBeats` was built from).
func euclideousResetBarsRemaining(liveBeat: Double, spanBeats: Double, cyc: Double, resetSpanBars: Int) -> Int {
    guard spanBeats > 0, cyc > 0 else { return 0 }
    let elapsed = liveBeat - columnStart(liveBeat, spanBeats)
    return max(1, min(resetSpanBars, Int(((spanBeats - elapsed) / cyc).rounded(.up))))
}
/// Is the tick at absolute beat `tickBeat` a hit, under the exact same span-re-anchor + direction-read rules
/// `Router.runEuclidLine` applies to every real tick? `buf` is this lane's own pattern (the function above).
func euclideousNoteViewIsHit(buf: [Bool], tickBeat: Double, sub: Double, spanBeats: Double, dir: EuclidDir) -> Bool {
    guard !buf.isEmpty, sub > 0 else { return false }
    let n = buf.count
    let cycleLen = euclidCycleLen(dir, n: n)
    let phaseBeat = spanBeats > 0 ? (tickBeat - columnStart(tickBeat, spanBeats)) : tickBeat
    let localT = Int64((phaseBeat / sub).rounded(.down))
    let raw = Int(((localT % Int64(cycleLen)) + Int64(cycleLen)) % Int64(cycleLen))
    return buf[euclidReadIndex(raw, n: n, dir: dir)]
}
/// 2026-10-13 ferry ("GATE follows the rhythm"): the beat GAP from `fromBeat` (exclusive) to the lane's own
/// NEXT real pattern hit — the SAME phaseBeat/columnStart reset-wrap `euclideousNoteViewIsHit` uses, so a
/// RESET SPAN boundary crossing between the two is honoured automatically: stepping forward in ABSOLUTE beat
/// and re-deriving the local tick from scratch at each candidate naturally reflects any span boundary crossed,
/// with no separate reset check. Deliberately takes `n` EXPLICITLY rather than delegating to
/// `euclideousNoteViewIsHit` (which derives its own modulus from `buf.count`) — caught by an RTCDEBUG trace,
/// not guessed: the render thread's real `euclidBuf` is a FIXED 16-slot scratch array (Router.swift, `private
/// var euclidBuf = [Bool](repeating: false, count: 16)`), so `buf.count` is almost always LARGER than the
/// lane's own real step count — delegating would silently wrap the cycle at 16 (or whatever the scratch
/// buffer's true allocated size is) instead of at the lane's own `n`, finding the wrong "next hit" entirely
/// for any `n` short of that allocation (an 8-step lane's own wrap at tick 8 read as a REST, since position 8
/// in the 16-slot buffer is unrelated padding, not the lane's own step 0 repeating). Deliberately MASK-
/// OBLIVIOUS (ferry §1.3: "mask probability doesn't change the gap... measured to the next PATTERN hit, even
/// if the mask then mutes that hit") — `buf` carries only the rhythm's own hit/rest shape (post RHYTHM-INV/
/// hand-edit/rotate/tilt, exactly as the live engine already builds it), nothing mask-related. Bounded at
/// `cap` ticks — deliberately reuses `riffTieExtensionBeats`'s own `cycleLen * 4` cap (not the ferry's literal
/// "bounded at 16 steps") so the two forward-scans this result is later combined with (`nextHitGap + tieExt`)
/// share one consistent bound, a disclosed judgment call. Returns `cap * sub` (not 0) if nothing is found
/// within the bound, so an all-rest/degenerate pattern still yields a usable, generous gap rather than a
/// zero-length note.
/// `mask`/`loopStepBeats`/`loopSteps` (mask 0 / the other two 0, byte-identical for every pre-existing call
/// site): opt in to the SAME masked reset origin `euclideousMaskedResetOrigin` uses, for the one caller whose
/// `spanBeats` came from a step-counted (LEN-bounded) per-lane reset rather than a bar-counted one — otherwise
/// this lookahead's own re-anchor prediction would silently disagree with the corrected per-hit origin above.
/// 2026-10-15 ferry ("per-step restart points," §2.3 "one formula... the TIE lookahead takes the mask instead
/// of resetSteps"): previously this REVERSE-DERIVED a step count from `(spanBeats / loopStepBeats).rounded()`
/// — a trick that only worked because every caller's `spanBeats` was literally `N × loopStepBeats` for one of
/// the four clean "every N" presets. An arbitrary hand-placed mask has no such N (two different masks with the
/// same POPULATION COUNT round-trip to the same wrong N through that division), so the mask is now threaded
/// through directly and `euclideousMaskedResetOrigin` is called on it exactly like the per-hit origin above —
/// no second derivation, matching §2.3 literally.
func euclideousNextHitGapBeats(buf: [Bool], n: Int, dir: EuclidDir, sub: Double, spanBeats: Double, fromBeat: Double, cap: Int, mask: UInt8 = 0, loopStepBeats: Double = 0, loopSteps: Int = 0) -> Double {
    guard !buf.isEmpty, n > 0, sub > 0, cap > 0 else { return sub }
    let cycleLen = euclidCycleLen(dir, n: n)
    var k = 1
    while k <= cap {
        let candidate = fromBeat + Double(k) * sub
        let phaseBeat: Double
        if spanBeats > 0 {
            if mask != 0, loopStepBeats > 0, loopSteps > 0 {
                let origin = euclideousMaskedResetOrigin(beat: candidate, stepBeats: loopStepBeats, mask: mask, loopSteps: loopSteps)
                phaseBeat = candidate - origin
            } else {
                phaseBeat = candidate - columnStart(candidate, spanBeats)
            }
        } else {
            phaseBeat = candidate
        }
        let localT = Int64((phaseBeat / sub).rounded(.down))
        let raw = Int(((localT % Int64(cycleLen)) + Int64(cycleLen)) % Int64(cycleLen))
        if buf[euclidReadIndex(raw, n: n, dir: dir)] { return Double(k) * sub }
        k += 1
    }
    return Double(cap) * sub
}
/// §2.1/§3.3 (Paul 2026-10-11: flipped to match a piano roll's own reading direction, the note more
/// visible for sitting against the strip's own note box instead of tucked off the far edge): a mark's
/// on-screen X, `trackW` (just entered, far right) ... 0 (the playhead, LEFT edge), moving continuously
/// as `nowBeat` advances — `nil` once it's outside the visible window entirely (either hasn't entered
/// yet, or — per §3.3, "remove each mark once it has passed the playhead" — has already played). `age`
/// is beats-until-this-tick-plays (positive = still approaching, 0 = playing exactly now, negative =
/// already played) — the mark's position is `trackW` scaled by how much of the window `age` still has
/// left to consume (age==windowBeats ⇒ trackW/far right; age==0 ⇒ 0/the playhead on the left).
func euclideousNoteViewMarkX(tickBeat: Double, nowBeat: Double, windowBeats: Double, trackW: CGFloat) -> CGFloat? {
    guard windowBeats > 0 else { return nil }
    let age = tickBeat - nowBeat
    guard age >= 0, age <= windowBeats else { return nil }
    return trackW * CGFloat(age / windowBeats)
}
/// §2.3, literal: "2 bars... if the fastest playing lane's steps would be less than 6pt apart, reduce the
/// window to 1 bar, then ½ bar." Picks the LARGEST of {2, 1, 0.5} bars that still clears the 6pt/step floor,
/// falling back to 0.5 (the stated floor — no further reduction below it) if even that doesn't clear it.
/// `fastestSub` is the smallest `rate.beats` among the lanes actually being shown (callers exclude disabled
/// lanes first, per §2.6 — a stopped lane draws no marks, so its own rate shouldn't drive the shared window).
func euclideousNoteViewWindowBars(fastestSub: Double, cyc: Double, trackW: CGFloat) -> Double {
    for bars in [2.0, 1.0, 0.5] {
        let windowBeats = bars * cyc
        guard windowBeats > 0 else { continue }
        let pxPerStep = trackW * CGFloat(fastestSub / windowBeats)
        if pxPerStep >= 6 || bars == 0.5 { return bars }
    }
    return 0.5
}

// ── EUCLIDEOUS LISTEN TAB (ferry 2026-10-14, "the LISTEN tab (lane relationships)") ─────────────────────
// §4/§9: the partner-picker's loop/chain exclusion, the auto-pick-on-first-light default, the per-tick
// processing order, and the preset-load loop-breaker. All pure, Foundation-only, and n-agnostic within
// the fixed 4-lane bound (Euclideous always has exactly 4, but nothing here hardcodes that beyond the
// `min(4, …)` guards every reader of `lines` already uses elsewhere in this file).

/// Whether `to` is reachable from `from` by following directed LISTEN edges (direct or transitive) — the
/// one primitive both loop-detection (§4) and preset loop-breaking (§4's own "(My interpretation.)" rule)
/// are built from. Iterative (not recursive) so a maliciously-cyclic `edges` array (one a bug elsewhere
/// handed this function, not a case that should ever occur once the picker's own exclusion holds) can
/// never stack-overflow — `visited` bounds the walk to at most `edges.count` nodes regardless.
func euclideousListenReaches(_ edges: [[Int]], from: Int, to: Int) -> Bool {
    if from == to { return true }
    guard from >= 0, from < edges.count else { return false }
    var visited = Set<Int>([from])
    var frontier = [from]
    while !frontier.isEmpty {
        var next: [Int] = []
        for n in frontier where n >= 0 && n < edges.count {
            for t in edges[n] {
                if t == to { return true }
                if !visited.contains(t) { visited.insert(t); next.append(t) }
            }
        }
        frontier = next
    }
    return false
}
/// Which of the 4 lanes' rows currently has a LIT partner edge, as an adjacency list — one entry per lane,
/// each listing the lane(s) IT currently listens to. `excludeLane`/`excludeRow`, when given, omits that
/// ONE row from the graph (used by the picker: the row being edited is about to be overwritten by
/// whichever candidate gets picked, so testing a candidate against that row's OWN prior choice would be
/// circular reasoning, not a real constraint). An AVOID row with ANY contributes an edge to EVERY OTHER
/// lane, not zero edges (adversarial-review fix, 2026-10-15 — the ORIGINAL "ANY can never itself be the
/// lane that closes a loop through one single edge" reasoning was wrong: if lane A has AVOID+ANY and
/// lane B then picks A as ITS own FOLLOW/WITH/GAPS/SHADOW/DUCK/ACCENT partner, A→B [one of ANY's many
/// edges] + B→A [the new pick] is a genuine 2-lane cycle, and the picker must grey A out of B's list to
/// prevent it — exactly matching the multi-edge treatment `euclideousListenProcessingOrder`'s own,
/// separate dependency computation already gives ANY, a few lines below).
enum EuclideousListenRow { case rhythm, pitch, level }
func euclideousListenEdges(_ lines: [EuclidLine], excludeLane: Int = -1, excludeRow: EuclideousListenRow? = nil) -> [[Int]] {
    let n = min(4, lines.count)
    var edges = [[Int]](repeating: [], count: n)
    for i in 0..<n {
        let L = lines[i]
        if !(i == excludeLane && excludeRow == .rhythm), L.listenRhythmMode != nil {
            let p = L.listenRhythmPartnerResolved
            if p != i, p < n { edges[i].append(p) }
        }
        if !(i == excludeLane && excludeRow == .pitch), L.listenPitchMode != nil {
            if L.listenPitchPartnerAnyResolved {
                for j in 0..<n where j != i { edges[i].append(j) }
            } else {
                let p = L.listenPitchPartnerResolved
                if p != i, p < n { edges[i].append(p) }
            }
        }
        if !(i == excludeLane && excludeRow == .level), L.listenLevelMode != nil {
            let p = L.listenLevelPartnerResolved
            if p != i, p < n { edges[i].append(p) }
        }
    }
    return edges
}
/// §4's partner-picker greying: every lane index that CAN'T be chosen as `lane`'s partner for `row` right
/// now — itself, always; any lane that would close a loop (directly or through other lanes); and, FOLLOW/
/// SHADOW only, any lane that is ITSELF currently following/shadowing something (checked one level only,
/// per the ferry's own literal words — a candidate's OWN partner is never walked further up the chain).
func euclideousListenGreyedPartners(_ lines: [EuclidLine], lane: Int, row: EuclideousListenRow) -> Set<Int> {
    let n = min(4, lines.count)
    var grey = Set<Int>([lane])
    guard lane >= 0, lane < n else { return grey }
    let edges = euclideousListenEdges(lines, excludeLane: lane, excludeRow: row)
    for p in 0..<n where p != lane {
        if euclideousListenReaches(edges, from: p, to: lane) { grey.insert(p) }
    }
    switch row {
    case .rhythm: for p in 0..<n where lines[p].listenRhythmMode == .follow { grey.insert(p) }
    case .pitch: for p in 0..<n where lines[p].listenPitchMode == .shadow { grey.insert(p) }
    case .level: break
    }
    return grey
}
/// §4's own auto-pick when a mode is FIRST lit: the next lane after `lane`, in order 1→2→3→4 (wrapping),
/// skipping anything `euclideousListenGreyedPartners` would grey out. `nil` ⇒ no lane is valid — the
/// caller must not light the mode at all (the ferry's own literal rule).
func euclideousListenDefaultPartner(_ lines: [EuclidLine], lane: Int, row: EuclideousListenRow) -> Int? {
    let grey = euclideousListenGreyedPartners(lines, lane: lane, row: row)
    for step in 1...3 {
        let candidate = (lane + step) % 4
        if !grey.contains(candidate) { return candidate }
    }
    return nil
}
/// The partner a row takes when its mode is LIT. The lane REMEMBERS the partner it last had on that row (a mode being switched
/// off, or swapped for another mode of the same row, never clears it), so lighting a mode puts the same partner back — as long
/// as it is still a legal choice (not greyed: not the lane itself, no loop, not a lane that is itself following/shadowing for
/// FOLLOW/SHADOW rows). If it has become illegal, or the lane never chose one, the §4 auto-pick (next valid lane) applies.
/// `nil` ⇒ no lane is valid, so the mode can't be lit (the ferry's own rule).
func euclideousListenPartnerToLight(_ lines: [EuclidLine], lane: Int, row: EuclideousListenRow) -> Int? {
    guard lane >= 0, lane < lines.count else { return nil }
    let stored: Int?
    switch row {
    case .rhythm: stored = lines[lane].listenRhythmPartner
    case .pitch: stored = lines[lane].listenPitchPartner
    case .level: stored = lines[lane].listenLevelPartner
    }
    if let stored, stored >= 0, stored < min(4, lines.count), !euclideousListenGreyedPartners(lines, lane: lane, row: row).contains(stored) {
        return stored
    }
    return euclideousListenDefaultPartner(lines, lane: lane, row: row)
}
/// Whether AVOID may use ANY for `lane` right now: ANY depends on EVERY other lane, so it is illegal if any other lane can
/// already reach this one (the same test the preset-load loop-breaker uses).
func euclideousListenAnyIsLegal(_ lines: [EuclidLine], lane: Int) -> Bool {
    let n = min(4, lines.count)
    guard lane >= 0, lane < n else { return false }
    let edges = euclideousListenEdges(lines, excludeLane: lane, excludeRow: .pitch)
    return !(0..<n).contains { $0 != lane && euclideousListenReaches(edges, from: $0, to: lane) }
}
/// Tapping a RHYTHM mode button: returns the lane's updated line, or nil when nothing should change (no valid partner).
/// Tapping the lit mode turns the row OFF and the lane goes back to its own rhythm — its partner is REMEMBERED. Lighting a
/// mode (from off, or switching FOLLOW/WITH/GAPS) restores the remembered partner when still legal.
/// (Lighting FOLLOW still zeroes the lane's OWN offset, the LISTEN ferry's rule — see the status log.)
func euclideousListenToggleRhythm(_ lines: [EuclidLine], lane: Int, mode: EuclideousRhythmMode) -> EuclidLine? {
    guard lane >= 0, lane < lines.count else { return nil }
    var L = lines[lane]
    if L.listenRhythmMode == mode { L.listenRhythmMode = nil; return L }
    guard let partner = euclideousListenPartnerToLight(lines, lane: lane, row: .rhythm) else { return nil }
    L.listenRhythmMode = mode; L.listenRhythmPartner = partner
    if mode == .follow { L.rotate = 0 }
    return L
}
/// Tapping a PITCH mode button. Off keeps the partner AND the ANY flag. AVOID restores ANY if it was chosen and is still legal
/// (it needs no specific partner); otherwise AVOID and SHADOW both need a specific, legal partner. SHADOW leaves the stored ANY
/// untouched — it can't use ANY, and `listenPitchPartnerAnyResolved` ignores it unless AVOID is lit.
func euclideousListenTogglePitch(_ lines: [EuclidLine], lane: Int, mode: EuclideousPitchMode) -> EuclidLine? {
    guard lane >= 0, lane < lines.count else { return nil }
    var L = lines[lane]
    if L.listenPitchMode == mode { L.listenPitchMode = nil; return L }
    let partner = euclideousListenPartnerToLight(lines, lane: lane, row: .pitch)
    if mode == .avoid, L.listenPitchPartnerAny == true, euclideousListenAnyIsLegal(lines, lane: lane) {
        L.listenPitchMode = mode
        if let partner { L.listenPitchPartner = partner }
        return L
    }
    guard let partner else { return nil }
    L.listenPitchMode = mode; L.listenPitchPartner = partner
    if mode == .avoid { L.listenPitchPartnerAny = false }
    return L
}
/// Tapping a LEVEL mode button: off keeps the partner; lighting (from off, or DUCK ↔ ACCENT) restores it when still legal.
func euclideousListenToggleLevel(_ lines: [EuclidLine], lane: Int, mode: EuclideousLevelMode) -> EuclidLine? {
    guard lane >= 0, lane < lines.count else { return nil }
    var L = lines[lane]
    if L.listenLevelMode == mode { L.listenLevelMode = nil; return L }
    guard let partner = euclideousListenPartnerToLight(lines, lane: lane, row: .level) else { return nil }
    L.listenLevelMode = mode; L.listenLevelPartner = partner
    return L
}
/// §9's per-tick processing order: a partner is always processed before any lane that listens to it.
/// Kahn's algorithm on the (always-acyclic, by the picker's own construction) 4-node dependency graph. An
/// ANY-partner AVOID row depends on every OTHER lane's own output, not one named partner — ordered after
/// everything it could possibly depend on by construction (its dependency list IS "every other lane").
/// Falls back to index order for whatever's left if a cycle somehow slipped through anyway (should not
/// happen once `euclideousListenGreyedPartners` has been honoured everywhere a partner is ever set) —
/// never hangs, never silently drops a lane.
func euclideousListenProcessingOrder(_ lines: [EuclidLine]) -> [Int] {
    let n = min(4, lines.count)
    guard n > 0 else { return [] }
    var deps = [[Int]](repeating: [], count: n)
    for i in 0..<n {
        let L = lines[i]
        if L.listenRhythmMode != nil { let p = L.listenRhythmPartnerResolved; if p != i, p < n { deps[i].append(p) } }
        if L.listenPitchMode != nil {
            if L.listenPitchPartnerAnyResolved { for j in 0..<n where j != i { deps[i].append(j) } }
            else { let p = L.listenPitchPartnerResolved; if p != i, p < n { deps[i].append(p) } }
        }
        if L.listenLevelMode != nil { let p = L.listenLevelPartnerResolved; if p != i, p < n { deps[i].append(p) } }
    }
    var order: [Int] = []
    var placed = Set<Int>()
    while order.count < n {
        var progressed = false
        for i in 0..<n where !placed.contains(i) {
            if deps[i].allSatisfy({ placed.contains($0) }) { order.append(i); placed.insert(i); progressed = true }
        }
        if !progressed {
            for i in 0..<n where !placed.contains(i) { order.append(i); placed.insert(i) }
            break
        }
    }
    return order
}
/// §4's own "(My interpretation.)" preset-load safety: if the loaded lines contain a loop anywhere in the
/// LISTEN graph, switch off whichever row closes it. Scans lane index 0→3, RHYTHM→PITCH→LEVEL within each
/// lane — a fixed, deterministic order, so a given broken preset always resolves the SAME way rather than
/// depending on dictionary/array iteration happenstance.
func euclideousListenBreakLoops(_ lines: [EuclidLine]) -> [EuclidLine] {
    var result = lines
    let n = min(4, lines.count)
    guard n > 0 else { return result }
    var edges = [[Int]](repeating: [], count: n)
    for i in 0..<n {
        if result[i].listenRhythmMode != nil {
            let p = result[i].listenRhythmPartnerResolved
            if p != i, p < n {
                if euclideousListenReaches(edges, from: p, to: i) { result[i].listenRhythmMode = nil; result[i].listenRhythmPartner = nil }
                else { edges[i].append(p) }
            }
        }
        if result[i].listenPitchMode != nil {
            if result[i].listenPitchPartnerAnyResolved {
                // ANY depends on every OTHER lane (adversarial-review fix, 2026-10-15 — mirrors the
                // identical fix in `euclideousListenEdges`): if any one of them can already reach `i`,
                // adding `i`→that-lane (one of ANY's many implicit edges) would close a cycle, so break
                // this lane's own PITCH row rather than let a loaded preset carry an undetected loop.
                if (0..<n).contains(where: { j in j != i && euclideousListenReaches(edges, from: j, to: i) }) {
                    result[i].listenPitchMode = nil; result[i].listenPitchPartner = nil; result[i].listenPitchPartnerAny = nil
                } else {
                    for j in 0..<n where j != i { edges[i].append(j) }
                }
            } else {
                let p = result[i].listenPitchPartnerResolved
                if p != i, p < n {
                    if euclideousListenReaches(edges, from: p, to: i) { result[i].listenPitchMode = nil; result[i].listenPitchPartner = nil }
                    else { edges[i].append(p) }
                }
            }
        }
        if result[i].listenLevelMode != nil {
            let p = result[i].listenLevelPartnerResolved
            if p != i, p < n {
                if euclideousListenReaches(edges, from: p, to: i) { result[i].listenLevelMode = nil; result[i].listenLevelPartner = nil }
                else { edges[i].append(p) }
            }
        }
    }
    return result
}

/// A lane's own FINISHED hit pattern — HITS/TILT/customHits → OFFSET(rotate) → patternMiss-invert, in
/// that exact order, mirroring `runEuclidLine`'s own inline pattern-build precisely (duplicated here, not
/// shared, since the render-thread original mutates a REUSED scratch buffer in place for zero allocation,
/// while this is a plain value return for LISTEN's own on-demand partner lookups — called at most a
/// handful of times per lane per render WINDOW, not per-tick, so the allocation here is bounded and
/// harmless, matching this file's own existing per-tick small-array precedent, e.g. MASK's `maskBuf`).
/// Deliberately does NOT replicate `p.euclidPulsesFromPool` (the regular, non-Euclideous HITS-FROM-POOL
/// override) — Euclideous's own UI has no control for it and never sets it, so every real caller is
/// unaffected; a hand-edited doc that somehow combined the two is an unreached, disclosed edge case.
/// The no-allocation form (adversarial-review fix, 2026-10-15): writes into a CALLER-OWNED, reused
/// buffer (sized >=16, matching `euclidBuf`/every other fixed scratch buffer in this codebase) instead
/// of allocating+returning a fresh array — this is the form the render thread must call. Reads
/// `L.customHits` RAW, never `.customHitsResolved`, which pads/allocates a fresh array of its own — the
/// identical raw-passthrough-with-manual-bounds-check idiom `runEuclidLine`'s own (non-LISTEN) pattern
/// build already uses for this exact field, so this function can never allocate regardless of caller.
func euclideousBuildPatternInto(_ L: EuclidLine, buf: inout [Bool]) -> Int {
    let n = max(2, min(16, L.steps))
    if let custom = L.customHits, !custom.isEmpty {
        for i in 0..<n { buf[i] = i < custom.count ? custom[i] : false }
    } else {
        let k = max(0, min(n, L.pulses))
        euclidPatternInto(&buf, pulses: k, steps: n, rotation: 0)
        if L.tiltResolved != 0 { euclidTiltPattern(&buf, pulses: k, steps: n, tilt: L.tiltResolved) }
    }
    euclidRotateBuffer(&buf, steps: n, rotation: L.rotate)
    if L.patternMissResolved { for i in 0..<n { buf[i].toggle() } }
    return n
}
/// Convenience value-returning wrapper for non-render-thread callers (UI code, tests), where a fresh
/// array is harmless. The render path must call `euclideousBuildPatternInto` directly against a reused
/// buffer instead (see its own doc comment) — never this wrapper, which allocates on every call.
func euclideousBuildPattern(_ L: EuclidLine) -> (buf: [Bool], n: Int) {
    var buf = [Bool](repeating: false, count: 16)
    let n = euclideousBuildPatternInto(L, buf: &buf)
    return (buf, n)
}
/// §5's own "coincide" test for WITH/GAPS: does the PARTNER's step pattern (not its sounding riff note —
/// "whether or not it sounded... riff rests, mutes and the LANES grid don't change it," the ferry's own
/// literal words) have a hit at (within `epsilonBeats` of) this exact beat? Pure, no allocation — a single
/// nearest-tick lookup against the partner's own already-built pattern buffer.
func euclideousListenPartnerHasHitAt(buf: [Bool], n: Int, dir: EuclidDir, rateBeats: Double, spanBeats: Double, atBeat: Double, epsilonBeats: Double) -> Bool {
    guard n > 0, rateBeats > 0, !buf.isEmpty else { return false }
    let phaseBeat = spanBeats > 0 ? (atBeat - columnStart(atBeat, spanBeats)) : atBeat
    let spanOrigin = spanBeats > 0 ? columnStart(atBeat, spanBeats) : 0
    let nearestLocalT = (phaseBeat / rateBeats).rounded()
    let nearestBeat = spanOrigin + nearestLocalT * rateBeats
    guard abs(nearestBeat - atBeat) <= epsilonBeats else { return false }
    let cycleLen = euclidCycleLen(dir, n: n)
    let raw = Int(((Int64(nearestLocalT) % Int64(cycleLen)) + Int64(cycleLen)) % Int64(cycleLen))
    return buf[euclidReadIndex(raw, n: n, dir: dir)]
}
/// §6's shared primitive for SHADOW and AVOID: the (rank, note) a lane with the given pattern/riff params
/// is sounding AT this exact beat (`epsilonBeats` given — AVOID's coincidence check) or at its most recent
/// real hit AT OR BEFORE this beat (`epsilonBeats` nil — SHADOW's "the note under the partner's walk arrow
/// at that moment," which stays wherever it last struck between hits, mirroring the UI's own sticky
/// marker). Resolves rank through the SAME INVERT→TRANSPOSE→source-pool pipeline `runEuclidLine`'s own
/// riff layer uses — MASK (MIRROR/LEAP/CLIMB) is deliberately NOT applied, matching §6's own literal list
/// ("after the partner's INV, TRANS and riff octave" — no mention of MASK). Bounded backward scan (same
/// shape as this file's own forward TIE-lookahead idiom, just run in reverse) — no allocation, pure.
func euclideousListenPartnerNoteAt(
    buf: [Bool], n: Int, dir: EuclidDir, rateBeats: Double, spanBeats: Double, atBeat: Double,
    epsilonBeats: Double?, line: EuclidLine, ranks: [Int], poolCount: Int, poolAsc: (Int) -> Int
) -> (rank: Int, note: Int)? {
    guard n > 0, rateBeats > 0, !buf.isEmpty else { return nil }
    let cycleLen = euclidCycleLen(dir, n: n)
    let phaseBeat = spanBeats > 0 ? (atBeat - columnStart(atBeat, spanBeats)) : atBeat
    let spanOrigin = spanBeats > 0 ? columnStart(atBeat, spanBeats) : 0
    let localTExact = phaseBeat / rateBeats
    var t: Int64
    if let eps = epsilonBeats {
        let nearest = localTExact.rounded()
        let nearestBeat = spanOrigin + nearest * rateBeats
        guard abs(nearestBeat - atBeat) <= eps else { return nil }
        t = Int64(nearest)
    } else {
        t = Int64(localTExact.rounded(.down))
    }
    let startT = t
    var scanned = 0
    let cap = cycleLen * 4
    while scanned < cap {
        let raw = Int(((t % Int64(cycleLen)) + Int64(cycleLen)) % Int64(cycleLen))
        if buf[euclidReadIndex(raw, n: n, dir: dir)] {
            if epsilonBeats != nil && t != startT { return nil }   // AVOID's coincidence check never falls back to an earlier hit — only an exact match counts
            var hitsUpTo = 0
            for s in 0...raw where buf[euclidReadIndex(s, n: n, dir: dir)] { hitsUpTo += 1 }
            let cy = (t - Int64(raw)) / Int64(cycleLen)
            var cycleHits = 0
            for s in 0..<cycleLen where buf[euclidReadIndex(s, n: n, dir: dir)] { cycleHits += 1 }
            let effHits = Int64(max(1, cycleHits))
            let advOrd: Int64 = line.riffAdvanceStepResolved
                ? (line.riffLockResolved ? Int64(raw) : t)
                : (line.riffLockResolved ? Int64(hitsUpTo - 1) : (cy * effHits + Int64(hitsUpTo - 1)))
            let seed = UInt64(bitPattern: Int64(line.riffDirSeedResolved))
            let walkPos = riffStepAt(line.euclideousRiffDirResolved, raw: Int(advOrd) * line.riffStrideResolved, steps: line.riffLengthResolved, seed: seed)
            let playedStep = riffRotateStep(walkPos, by: line.riffRotateResolved, steps: line.riffLengthResolved)
            let rawRank = playedStep < ranks.count ? ranks[playedStep] : 0
            guard rawRank >= 1 else { return nil }   // a rest — nothing sounding here
            let invRank = line.riffInvertResolved ? (9 - rawRank) : rawRank
            let transposedRank = invRank + line.melodyTransposeResolved
            guard transposedRank >= 1, poolCount > 0, let note = riffResolve(rank: transposedRank, oct: line.riffOctaveResolved, n: poolCount, wrap: .fold, asc: poolAsc) else { return nil }
            return (transposedRank, note)
        }
        t -= 1
        scanned += 1
    }
    return nil
}

// ── ARP EUCLID MASK (SPEC-arp-euclid-mask, ratified 2026-08-26) ──────────────────────────────────────────────────
// Pure per-step helpers over a Bjorklund K-of-N mask (SAME formula as euclidPatternInto). No allocation — safe in the
// render hot loop. `step` is the global arp-tick index. K == N ⇒ every step a hit (mask OFF) → callers short-circuit.
@inline(__always) func euclidMaskHit(_ step: Int, k: Int, n n0: Int, rotate: Int) -> Bool {
    let n = max(1, min(64, n0)); let kk = max(0, min(n, k))
    if kk >= n { return true }
    let i = ((step % n) + n) % n
    let src = (i + (((rotate % n) + n) % n)) % n
    return (src * kk) % n < kk
}
/// The hits STRICTLY BEFORE `step` — WAIT's walk index (the walk advances only on hits). K hits per N steps.
@inline(__always) func euclidMaskHitsBefore(_ step: Int, k: Int, n n0: Int, rotate: Int) -> Int {
    let n = max(1, min(64, n0)); let kk = max(1, min(n, k))
    let s = ((step % n) + n) % n; let laps = (step - s) / n
    var within = 0; for i in 0..<s where euclidMaskHit(i, k: kk, n: n, rotate: rotate) { within += 1 }
    return laps * kk + within
}
/// The consecutive NON-HIT steps AFTER `step` until the next hit — TIE's gate-extension span (≤ N−1, since K ≥ 1).
@inline(__always) func euclidMaskTieRun(_ step: Int, k: Int, n n0: Int, rotate: Int) -> Int {
    let n = max(1, min(64, n0)); var g = 0
    while g < n && !euclidMaskHit(step + g + 1, k: k, n: n, rotate: rotate) { g += 1 }
    return g
}

/// BURST — the fractional positions (0…<1 of the step) of a `count`-strike roll. `curve` bends the spacing:
/// 0 = even, +1 = ACCELERATE (gaps shrink → strikes bunch late), −1 = DECELERATE (gaps grow → bunch early).
/// The first strike is always at 0 (step entry). Pure/testable.
// Fill `buf[0..<c]` with the roll's fractional positions (c = the resolved strike count) — no-alloc form for the render
// hot loop. Returns c. The array `burstFractions` below wraps it for the tests.
@discardableResult func burstFractionsInto(_ buf: inout [Double], count: Int, curve: Double) -> Int {
    let c = max(1, min(16, count))
    guard buf.count >= c else { return 0 }
    if c == 1 { buf[0] = 0; return 1 }
    let gamma = pow(2.0, -max(-1.0, min(1.0, curve)))     // +1 → 0.5 (accel) · 0 → 1 (even) · −1 → 2 (decel)
    for i in 0..<c { buf[i] = pow(Double(i) / Double(c), gamma) }
    return c
}
func burstFractions(count: Int, curve: Double) -> [Double] {
    var buf = [Double](repeating: 0, count: max(1, min(16, count)))
    let c = burstFractionsInto(&buf, count: count, curve: curve)
    return Array(buf[0..<c])
}

// MARK: - THE SEAL (the derived cell face) — Docs/AcceptanceCriteria/AcceptanceCriteria-seal-face.md
// A maze/route glyph on a 3×3 lattice, generated from the behavioural-config hash. Same config ⇒ same seal
// everywhere (document-visible truth); config-twins share it. REPLACES the retired ORBIT (lissajous, ratio
// table). Generation follows the design mockup (INSTRUCTIONS-implement-the-seal §2), ported from its prose
// spec (the mockup HTML wasn't shipped, so the exact PRNG is a faithful mulberry32 — the grammar is the same).

/// The BEHAVIOURAL config of a cell, normalised for stable hashing: the SAME fields that define TWINS
/// (Models.editScopeTargets `.twins`) MINUS machineID — machine is the hue block, not the seal. Sets are
/// sorted (unordered → canonical); chop keeps its raw nil vs value (matching the twin predicate exactly, so
/// twins share a seal). Triggers live on Machine, not Cell → excluded until they re-host. Codable → bytes.
private struct SealChopKey: Encodable { let m: UInt8; let a: UInt8; let mu: UInt8; let alt: [UInt8] }
private struct SealKey: Encodable {
    let p: [ProcessorSlot]?    // the chain (slots + params + per-slot bypass)
    let ir: Int?               // input receiver
    let irow: Int?             // input row (inert now; kept for twin-parity)
    let b: [UInt8]             // output emitters (sorted bus cables)
    let cs: ChordSplit?        // source-shaping: chord split
    let vw: VelWindow?         // source-shaping: velocity window
    let ch: SealChopKey?       // output chop (nil when the cell has no chop, per twin equality)
}
/// The RESOLVED chain a cell actually plays: its per-cell override, else the machine's TEMPLATE, else the machine's
/// A face. The seal must hash THIS — a template/A-face cell has NIL `processors`, so its machine comes from the
/// machine; hashing raw nil made every such cell (the DEFAULT arc + most factory presets) share ONE seal. (Same
/// 3-tier resolution as SnapshotBuilder / AU.materializedChain.) Pure.
func resolvedCellChain(_ cell: Cell, machines: [Machine]) -> [ProcessorSlot] {
    if let p = cell.processors { return p }                              // per-cell OVERRIDE (incl. an explicit [] passthrough)
    let c = machines.first { $0.machineID == cell.machineID }
    if let t = c?.templateChain, !t.isEmpty { return t }                 // machine TEMPLATE
    return [ProcessorSlot(type: c?.type ?? .empty, params: c?.paramsA ?? MachineParams())]   // legacy A face
}
/// A 32-bit FNV-1a over the JSON (sorted keys) of the behavioural config. Same config ⇒ same value on every
/// device (document-visible truth); config-twins (regardless of machine) share it. Pure/testable. §1 contract.
/// Hashes the RESOLVED chain (needs `machines`) so template/A-face cells reflect their machine's machine.
func sealHash(_ cell: Cell, machines: [Machine]) -> UInt32 {
    let chopKey = cell.chop.map { SealChopKey(m: $0.mainMask, a: $0.altMask, mu: $0.muteMask, alt: $0.altDest.map { $0.cable }.sorted()) }
    let key = SealKey(p: resolvedCellChain(cell, machines: machines), ir: cell.inputReceiver, irow: cell.inputRow,
                      b: cell.buses.map { $0.cable }.sorted(), cs: cell.chordSplit, vw: cell.velWindow, ch: chopKey)
    let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
    guard let data = try? enc.encode(key) else { return 0 }
    var h: UInt32 = 2166136261                                   // FNV-1a offset basis
    for byte in data { h = (h ^ UInt32(byte)) &* 16777619 }      // ×FNV prime, wrapping
    return h
}

/// The seal's step PRNG — a mulberry32 seeded by the config hash (the mockup's `rnd`). Every seal decision
/// (start · route dirs · corner bits · coil node) is a successive draw, so the seal is reproducible from the hash.
private struct SealRNG {
    var s: UInt32
    mutating func next() -> UInt32 {
        s = s &+ 0x6D2B_79F5
        var z = s
        z = (z ^ (z >> 15)) &* (z | 1)
        z ^= z &+ ((z ^ (z >> 7)) &* (z | 61))
        return z ^ (z >> 14)
    }
    mutating func next(mod m: Int) -> Int { Int(next() % UInt32(max(1, m))) }
}

/// The seal's geometry in LATTICE space (nodes on a 3×3 grid, x/y ∈ {0,1,2}). The SwiftUI layer maps it into a
/// rect (pitch = half the drawable side) and draws the wire (quarter-arc or sharp mitre per corner), an optional
/// coil, and the terminals (filled start dot + end arrowhead). Pure/testable; twins share it.
struct SealGeometry: Equatable {
    var nodes: [SIMD2<Double>]     // route nodes, lattice coords 0…2 (≥2 by construction)
    var arcAtNode: [Bool]          // per node: true = QUARTER-ARC corner, false = sharp mitre (ends always false)
    var coilNode: Int              // index of the node the coil straddles, or −1 for no coil (≤1 coil, ever)
}

/// Generate the seal from the config hash (INSTRUCTIONS §2): START on the lattice, take ≤4 orthogonal MOVES
/// (reject immediate backtrack `dir==last^1` + out-of-bounds, ≤8 tries each), flag CORNERS from one hash word,
/// and add at most one COIL (iff hash%4==0) astride a mid-route node. Pure — same hash ⇒ identical geometry.
func sealGeometry(_ hash: UInt32) -> SealGeometry {
    var rng = SealRNG(s: hash)
    let dx = [1, -1, 0, 0], dy = [0, 0, 1, -1]      // dir 0/1 = ±x, 2/3 = ±y → opposite = dir^1 (backtrack test)
    // START on a LEFT/RIGHT edge, then a FORCED horizontal move inward — so the route ALWAYS spans across the
    // lattice and (with bbox-fit rendering) fills the full LENGTH instead of hugging one side (user request).
    let startLeft = rng.next(mod: 2) == 0
    var x = startLeft ? 0 : 2, y = rng.next(mod: 3)
    var nodes = [SIMD2(Double(x), Double(y))]
    var lastDir = startLeft ? 0 : 1
    x += dx[lastDir]; y += dy[lastDir]
    nodes.append(SIMD2(Double(x), Double(y)))
    for _ in 0..<3 {                                 // up to 3 further free moves → ≤5 nodes
        var moved = false
        for _ in 0..<8 {                             // ≤8 rejection tries per move
            let dir = rng.next(mod: 4)
            if dir == (lastDir ^ 1) { continue }     // reject immediate backtrack
            let nx = x + dx[dir], ny = y + dy[dir]
            if nx < 0 || nx > 2 || ny < 0 || ny > 2 { continue }   // reject out-of-bounds
            x = nx; y = ny; lastDir = dir
            nodes.append(SIMD2(Double(x), Double(y)))
            moved = true
            break
        }
        if !moved { break }                          // boxed in → stop routing early
    }
    let round = rng.next()                           // one hash word governs every corner
    var arc = [Bool](repeating: false, count: nodes.count)
    if nodes.count > 2 {
        for i in 1..<(nodes.count - 1) { arc[i] = (round >> UInt32(i)) & 1 == 1 }   // interior node i: arc iff bit set
    }
    var coilNode = -1
    if hash % 4 == 0 && nodes.count > 2 {            // at most one coil, on a mid-route node (index 1…len-2)
        coilNode = 1 + rng.next(mod: nodes.count - 2)
    }
    return SealGeometry(nodes: nodes, arcAtNode: arc, coilNode: coilNode)
}

/// The seal's nodes NORMALISED to unit fractions [0,1]² by FITTING the route's bounding box (independent x/y
/// scale), so the glyph fills the full LENGTH + height wherever the route sits on the lattice — no hugging one
/// side. A zero-range axis (a straight run) centres at 0.5. Also carries the lattice ranges (the drawer scales
/// its corner-arc radius by them). Pure/testable; the SwiftUI layer maps fractions → the padded rect. Twins share it.
struct SealFit: Equatable {
    var fractions: [SIMD2<Double>]   // per node, each component in [0,1] (0.5 on a zero-range axis)
    var rangeX: Double               // lattice x-extent (maxX − minX), 0…2
    var rangeY: Double               // lattice y-extent
}

/// The cell-face TRIGGER glyph — deviation-shown. The bottom-right glyph comes from the ON-TAP action; a
/// non-default ON-HOLD action rings it. Both default ⇒ nil (no mark). Placeholder SF Symbols. Pure/testable.
func triggerTapGlyph(_ t: OnTap) -> String? {
    switch t {
    case .none:   return nil
    case .alt:    return "arrow.left.arrow.right"   // ⇄ flip
    case .mute:   return "speaker.slash.fill"
    case .solo:   return "headphones"
    case .fill:   return "square.grid.3x3.fill"
    case .replay: return "arrow.clockwise"          // ↻ replay
    }
}
func triggerHoldGlyph(_ h: OnHold) -> String? {
    switch h {
    case .none:       return nil
    case .alt:        return "arrow.left.arrow.right"
    case .freeze:     return "snowflake"            // ❄ freeze
    case .sliceCycle: return "rectangle.split.3x1"
    case .morphScrub: return "slider.horizontal.3"
    case .oct:        return "arrow.up.arrow.down"  // ↑/↓ octave
    }
}
/// The single bottom-right mark: (glyph, ring). Tap sets the glyph; a hold rings it. Hold-only shows the hold
/// glyph, ringed. Both default ⇒ nil. Never more than two marks (a glyph + its ring).
func triggerMark(_ on: OnConfig) -> (glyph: String, ring: Bool)? {
    if let t = triggerTapGlyph(on.tap) { return (t, triggerHoldGlyph(on.hold) != nil) }
    if let h = triggerHoldGlyph(on.hold) { return (h, true) }
    return nil
}

// MARK: - THE ROOM LATTICE (rooms interface, Docs/INSTRUCTIONS-layout-lattice.md)
//
// The pure geometry shared by the part/select grids, the seam sliver, and the machine panel so all
// three land on the SAME horizontal band lines. Extracted here (Double, Foundation-only) so it's the
// ONE source of truth AND unit-testable — RoomsMetrics (SwiftUI, CGFloat) wraps it. The column layout
// is: [pad][▲PLAY door @ ch·nf][gap][header row @ ch][gap][8 interior rows @ ch, gap-separated][pad].
struct RoomsLatticeGeom: Equatable {
    var ch: Double          // one grid-row height (also the header/RECORD band height)
    var navH: Double        // the ▲PLAY door-bar band height (= ch · nf)
    var interiorTop: Double // y where the 8 interior rows begin (below the ▲PLAY door + header row)
    var interiorH: Double   // total height of the 8 interior rows (8 rows, 7 gaps)
}
/// Solve the room lattice for a content `height`. `nf` = the nav-door fraction of a cell (0.5). The cell
/// is floored at 6 so a tiny/degenerate height can never produce a non-positive or NaN row (guards the
/// GeometryReader's first zero-height layout pass). gap/pad default to the RoomsMetrics constants.
func roomsLattice(height: Double, gap: Double = 3, pad: Double = 3, nf: Double = 0.5) -> RoomsLatticeGeom {
    let c = max(6, (height - 2 * pad - 9 * gap) / (9 + nf))   // 9 full rows (door·nf + header + 8 interior counts as 8+nf) + the nf door
    return RoomsLatticeGeom(ch: c,
                            navH: c * nf,
                            interiorTop: pad + c * nf + gap + c + gap,
                            interiorH: c * 8 + gap * 7)
}

/// Rooms STAMP / COMMIT source priority (the SELECT grid). The live audition wins — it holds the card EDITS, with the
/// register home already baked in (so transpose 0) — then the browsed library cell, then the aimed side-button's part
/// row; nil if no source. Kept pure so the priority — the exact locus of the edit-not-carried bug (2026-08-29, where the
/// stamp read the ORIGINAL library chain and dropped edits) — is unit-tested; BuildPage resolves the three candidates
/// from @State and delegates here.
func roomsStampSource(auditionEdited: [ProcessorSlot]?,
                      libraryCell: (chain: [ProcessorSlot], transpose: Int)?,
                      sideRow: (chain: [ProcessorSlot], transpose: Int)?) -> (chain: [ProcessorSlot], transpose: Int)? {
    if let a = auditionEdited, !a.isEmpty { return (a, 0) }   // the live gsAud audition — edits + baked register home
    if let c = libraryCell { return c }                       // the browsed library/dealt cell
    if let s = sideRow { return s }                           // the aimed side-button's part row
    return nil
}

// MARK: - RIFF-GRID WALK TAGS WITH THREADS (ferry "Riff-grid walk tags with threads", ratified by Paul 2026-10-15)
//
// Each riff-on lane draws an arrow-shaped TAG on the shared riff grid (replacing the dark chip + small
// triangle), pointing the way its walk is about to move, with a THREAD to the seat it will take at its next
// advance. At each advance the tag travels its thread and ARRIVES exactly at the advance's scheduled time —
// so it departs BEFORE the hit, which is only possible because the schedule is PREDICTED here (a pure mirror of
// `Router.runEuclidLine`'s own tick/ordinal/walk arithmetic) rather than learned from the poll. Everything in
// this section is Foundation-only, pure and stateless: the page re-derives the whole picture from the live beat
// every frame, so there is no retained tag state to drift out of step with the thumbnail (the prerequisite).
//
// The polled step (`riffPositions`, the SAME value the RIFF-tab thumbnail reads) stays the authority for where a
// lane IS: `euclideousWalkTagPlan` only animates a flight when the prediction agrees with it (±1 hit of poll
// latency/lead); otherwise the tag simply sits on the polled step with no thread.

enum EuclideousTagMetrics {
    static let refBlockW: CGFloat = 42.5
    static let refBlockH: CGFloat = 29
    static let tagW: CGFloat = 18
    static let tagH: CGFloat = 11
    static let bodyW: CGFloat = 13
    static let pointW: CGFloat = 5
    static let insetX: CGFloat = 2
    static let insetY: CGFloat = 2.5
    static let wrapOvershoot: CGFloat = 2
    /// Longest a flight may take; a short interval caps it at half the time since the lane's previous advance.
    static let flightMaxSeconds: Double = 0.080
    static let turnDelaySeconds: Double = 0.020
    static let turnSeconds: Double = 0.100
    /// How long the polled step may trail the predicted landing before the prediction is distrusted.
    static let pollLagGraceSeconds: Double = 0.150
}

/// 1 at (or above) the reference 42.5 × 29pt block; smaller blocks scale the whole tag (and its seat insets)
/// down proportionally so a corner tag can never overflow its own block. Not part of the ratified spec — the spec
/// only gives the reference size — so it is a no-op wherever the spec's numbers apply.
func euclideousTagScale(blockW: CGFloat, blockH: CGFloat) -> CGFloat {
    max(0.1, min(1, min(blockW / EuclideousTagMetrics.refBlockW, blockH / EuclideousTagMetrics.refBlockH)))
}

/// The lane's tag seat inside a block, relative to the block's top-left. Lane 0 top-left, 1 top-right, 2
/// bottom-left, 3 bottom-right (the lane-card grid's own corners). Reference block: red (2,2.5), blue (22.5,2.5),
/// yellow (2,15.5), green (22.5,15.5), each 18 × 11.
func euclideousTagRect(lane: Int, blockW: CGFloat, blockH: CGFloat) -> CGRect {
    let s = euclideousTagScale(blockW: blockW, blockH: blockH)
    let w = EuclideousTagMetrics.tagW * s, h = EuclideousTagMetrics.tagH * s
    let ix = EuclideousTagMetrics.insetX * s, iy = EuclideousTagMetrics.insetY * s
    let l = posMod(lane, 4)
    let right = (l == 1 || l == 3), bottom = (l == 2 || l == 3)
    return CGRect(x: right ? blockW - ix - w : ix, y: bottom ? blockH - iy - h : iy, width: w, height: h)
}
func euclideousTagCentre(lane: Int, blockW: CGFloat, blockH: CGFloat) -> CGPoint {
    let r = euclideousTagRect(lane: lane, blockW: blockW, blockH: blockH)
    return CGPoint(x: r.midX, y: r.midY)
}
/// Centre of `lane`'s seat on the block at (`col` 0…7, `rank` 1…8; rank 8 is the top row), in the riff grid's
/// own coordinate space (top-left of the matrix = origin).
func euclideousTagSeatCentre(lane: Int, col: Int, rank: Int, cellW: CGFloat, cellH: CGFloat, gap: CGFloat) -> CGPoint {
    let c = euclideousTagCentre(lane: lane, blockW: cellW, blockH: cellH)
    return CGPoint(x: CGFloat(col) * (cellW + gap) + c.x, y: CGFloat(8 - rank) * (cellH + gap) + c.y)
}

/// CSS-style cubic-bezier easing (x → y) through (0,0),(x1,y1),(x2,y2),(1,1) — the ferry's ease-out is
/// (0.2, 0.8, 0.2, 1). Solves x(t) = x by bisection (x(t) is monotonic for these control points).
func euclideousCubicBezierEase(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double, _ x: Double) -> Double {
    if x <= 0 { return 0 }
    if x >= 1 { return 1 }
    func b(_ t: Double, _ p1: Double, _ p2: Double) -> Double { let u = 1 - t; return 3 * u * u * t * p1 + 3 * u * t * t * p2 + t * t * t }
    var lo = 0.0, hi = 1.0, t = x
    for _ in 0..<48 {
        let v = b(t, x1, x2)
        if abs(v - x) < 1e-10 { break }
        if v < x { lo = t } else { hi = t }
        t = (lo + hi) / 2
    }
    return b(t, y1, y2)
}
func euclideousTagEase(_ u: Double) -> Double { euclideousCubicBezierEase(0.2, 0.8, 0.2, 1, u) }

/// Seconds a flight takes: 80ms, or half the time since the lane's previous advance if that is shorter.
func euclideousTagFlightDuration(previousAdvance p: Double?, nextAdvance h: Double) -> Double {
    guard let p else { return EuclideousTagMetrics.flightMaxSeconds }
    return max(0, min(EuclideousTagMetrics.flightMaxSeconds, (h - p) / 2))
}
enum EuclideousTagPhase: Equatable {
    case seated                    // on its seat, thread showing (from the previous advance until departure)
    case inFlight(raw: Double)     // travelling; raw is linear 0…1 over the flight, un-eased
    case landed                    // at/after the scheduled advance — the caller re-plans from here
}
/// All times in seconds on one clock. Departure = next − duration; arrival = next (the advance's scheduled time).
func euclideousTagPhase(now: Double, previousAdvance p: Double?, nextAdvance h: Double) -> EuclideousTagPhase {
    let d = euclideousTagFlightDuration(previousAdvance: p, nextAdvance: h)
    let depart = h - d
    if now < depart { return .seated }
    if now < h { return .inFlight(raw: d > 0 ? (now - depart) / d : 1) }
    return .landed
}

// ── the engine mirror ───────────────────────────────────────────────────────────────────────────────

/// Everything `Router.runEuclidLine` reads to decide, for an absolute tick, whether it is a hit and which riff
/// step the walk lands on.
struct EuclideousWalkLaneConfig {
    var buf: [Bool]                 // the finished pattern (post FOLLOW / OFFSET / TILT / INV)
    var n: Int
    var dir: EuclidDir
    var sub: Double                 // beats per tick (the lane's rate, × the FOLLOW multiplier)
    var spanBeats: Double = 0       // machine-wide RESET span in beats (used only when there is no per-lane mask); 0 = free-run
    /// The lane's per-step RESTART mask (`EuclidLine.restartMaskResolved`, the 2026-10-15 ferry — the engine's own input).
    /// Non-zero selects the masked origin, exactly like `Router.runEuclidLine`; 0 = no per-lane restart.
    var restartMask: UInt8 = 0
    var loopStepBeats: Double = 0
    var loopSteps: Int = 8
    /// LISTEN WITH / GAPS: when set, a raw pattern hit only STRIKES if it passes the partner coincidence test. nil = no filter.
    var listen: EuclideousWalkListenFilter? = nil
    var riffDir: RiffDir = .forward
    var stride: Int = 1
    var length: Int = 8
    var rotate: Int = 0
    var locked: Bool = false        // LOCK
    var advanceStep: Bool = false   // ADV STEP
    var seed: UInt64 = 0
    /// SWING: the engine ticks in MUSICAL beats and maps each tick's onset to real time through `realOf`
    /// (`a` = swing% / 50, `swingStepBeats` = the scene's step beats). `a == 1` (50%) is the identity.
    var swingA: Double = 1
    var swingStepBeats: Double = 0.5
}

/// What `Router.runEuclidLine`'s `passesListenRhythmFilter` reads for a WITH / GAPS lane, captured once: the PARTNER's own
/// finished pattern, direction and rate, the span the engine re-anchors the coincidence lookup on, and its tolerance.
/// WITH strikes only when the partner has a hit at that tick; GAPS only when it has none.
struct EuclideousWalkListenFilter {
    var requireCoincide: Bool       // true = WITH, false = GAPS
    var buf: [Bool]
    var n: Int
    var dir: EuclidDir
    var rateBeats: Double
    var spanBeats: Double           // the engine's `spanBeats` for this lane (NOT the mirror's own reset origin)
    var epsilonBeats: Double        // 1ms in beats at the host tempo
}

/// The partner lane index lane `lane` is FOLLOWing, or nil: only RHYTHM → FOLLOW with a partner that exists counts (WITH and
/// GAPS keep the lane's own rhythm, so they are NOT following). The ONE definition the engine mirror, the lane card's look
/// and its gestures all share.
func euclideousFollowPartner(lane: Int, lines: [EuclidLine]) -> Int? {
    guard lane >= 0, lane < lines.count, lines[lane].listenRhythmMode == .follow else { return nil }
    let p = lines[lane].listenRhythmPartnerResolved
    return p >= 0 && p < lines.count ? p : nil
}
/// The lane whose RHYTHM the lane's own bar gestures (drag up/down = HITS, left/right = OFFSET, pinch = STEPS) should edit: the
/// partner it follows, else itself. A follower plays its partner's pattern, so the gesture edits what it is following.
func euclideousRhythmGestureTarget(lane: Int, lines: [EuclidLine]) -> Int {
    euclideousFollowPartner(lane: lane, lines: lines) ?? lane
}
/// How faded a FOLLOW lane's lit cells are drawn (1 = full strength): the cells are the PARTNER's hits in the partner's colour,
/// a little softer than a lane's own so they still read as "borrowed".
let euclideousListenCellFade: Double = 0.75

/// The pattern lane `lane` ACTUALLY plays, exactly as `Router.runEuclidLine` builds it: its own HITS/TILT/hand-edits/OFFSET/INV
/// — or, when it is FOLLOWing a valid partner, the PARTNER's finished pattern and step count with THIS lane's own OFFSET and INV
/// applied on top. `followsPartner` tells the UI whether the lane's own pulses/steps are the pattern at all: when they are not,
/// anything drawn from them (the step bar's cells, its footer) would disagree with what sounds. `rateBeats` is the step length
/// the engine ticks at — the lane's own rate, or the partner's × the FOLLOW multiplier — so the comet's sweep can match it
/// (`defaultRateBeats` stands in for a lane whose rate is unset, as everywhere in the UI's mirror).
/// ONE function for the walk-tag mirror and the lane card, so neither can drift from the engine on its own.
func euclideousEffectivePattern(lane: Int, lines: [EuclidLine], defaultRateBeats: Double = 0.25) -> (buf: [Bool], n: Int, followsPartner: Bool, rateBeats: Double)? {
    guard lane >= 0, lane < lines.count else { return nil }
    let L = lines[lane]
    if let followIdx = euclideousFollowPartner(lane: lane, lines: lines) {
        // Mirrors Router: the partner's finished pattern + step count, then THIS lane's own OFFSET / INV on top.
        let pb = euclideousBuildPattern(lines[followIdx])
        var buf = pb.buf
        euclidRotateBuffer(&buf, steps: pb.n, rotation: L.rotate)
        if L.patternMissResolved { for i in 0..<pb.n { buf[i].toggle() } }
        return (buf, pb.n, true, (lines[followIdx].rate?.beats ?? defaultRateBeats) * L.listenFollowRatioResolved)
    }
    let b = euclideousBuildPattern(L)
    return (b.buf, b.n, false, L.rate?.beats ?? defaultRateBeats)
}

func euclideousWalkLaneConfig(lane: Int, lines: [EuclidLine], cyc: Double, resetSpanBars: Int,
                              lanesSeqRate: EuclideousSeqRate, lanesSeqLen: Int,
                              defaultRateBeats: Double = 0.25, swingPercent: Double = 50, stepBeats: Double = 0.5,
                              beatsPerBar: Double = 4, tempo: Double = 120) -> EuclideousWalkLaneConfig? {
    guard lane >= 0, lane < lines.count else { return nil }
    let L = lines[lane]
    let followIdx = L.listenRhythmPartnerResolved   // the rhythm partner of ANY listen mode (WITH/GAPS use it below)
    guard let eff = euclideousEffectivePattern(lane: lane, lines: lines, defaultRateBeats: defaultRateBeats) else { return nil }
    let buf = eff.buf, n = eff.n
    let sub = eff.rateBeats
    // The LANES sequencer's step (and so the per-lane RESET, counted in those steps) is measured in the host's REAL bars
    // (`beatsPerBar`, 2026-10-14 sequencer-step-length fix); only the machine-wide reset span still counts grid-geometry `cyc`s.
    let lanesStepBeats = lanesSeqRate.barsFraction * beatsPerBar
    // The engine resets from the lane's 8-bit RESTART MASK (`restartMaskResolved`); a hand-placed mask has no "every N" form,
    // so the mirror must read the mask itself. With no mask it falls back to the machine-wide bars span, as the engine does.
    let restartMask = L.restartMaskResolved
    let spanBeats = restartMask != 0 ? 0 : (resetSpanBars > 0 ? Double(resetSpanBars) * cyc : 0)
    // LISTEN WITH / GAPS: the engine's coincidence lookup uses ITS `spanBeats` — one full LANES lap when a mask is set,
    // else the bars span — which differs from the mirror's own reset origin above, so it is captured separately.
    var listen: EuclideousWalkListenFilter? = nil
    if let mode = L.listenRhythmMode, mode != .follow, followIdx >= 0, followIdx < lines.count {
        let partner = lines[followIdx]
        let pb = euclideousBuildPattern(partner)
        let engineSpan = restartMask != 0 ? Double(lanesSeqLen) * lanesStepBeats : (resetSpanBars > 0 ? Double(resetSpanBars) * cyc : 0)
        listen = EuclideousWalkListenFilter(requireCoincide: mode == .with, buf: pb.buf, n: pb.n, dir: partner.directionResolved,
                                            rateBeats: partner.rate?.beats ?? defaultRateBeats, spanBeats: engineSpan,
                                            epsilonBeats: 0.001 * (max(1, tempo) / 60.0))
    }
    return EuclideousWalkLaneConfig(buf: buf, n: n, dir: L.directionResolved, sub: sub, spanBeats: spanBeats,
                                    restartMask: restartMask, loopStepBeats: lanesStepBeats, loopSteps: lanesSeqLen, listen: listen,
                                    riffDir: L.euclideousRiffDirResolved, stride: L.riffStrideResolved, length: L.riffLengthResolved,
                                    rotate: L.riffRotateResolved, locked: L.riffLockResolved, advanceStep: L.riffAdvanceStepResolved,
                                    seed: UInt64(bitPattern: Int64(L.riffDirSeedResolved)),
                                    swingA: min(75, max(50, swingPercent)) / 50.0, swingStepBeats: max(0.03125, stepBeats))
}
/// A tick's REAL onset beat — what the note-on is scheduled at (swing-warped), the time a tag must arrive.
func euclideousWalkRealBeat(_ c: EuclideousWalkLaneConfig, tick: Int64) -> Double {
    let m = Double(tick) * c.sub
    return c.swingA == 1 ? m : realOf(m, stepBeats: c.swingStepBeats, a: c.swingA)
}

struct EuclideousWalkTick: Equatable {
    var isHit: Bool          // the lane's OWN pattern has a hit on this tick (what the walk's ordinal arithmetic counts)
    var strikes: Bool        // it actually SOUNDS: a hit that also passes the LISTEN WITH / GAPS filter (== isHit with no filter)
    var advOrd: Int64        // the ordinal fed to the walk (`euclideousRiffLastOrd` on the render side)
    var playedStep: Int      // 0-based riff step (`euclideousRiffStep` on the render side)
}
/// One absolute tick, evaluated exactly the way `runEuclidLine` does (same `Double(tick) * sub` beat, same
/// floor/mod arithmetic, same `hitsUpTo`/`ord`/`advOrd` formulas) — so the predicted schedule cannot drift from
/// the engine's by anything but the clock itself.
func euclideousWalkTick(_ c: EuclideousWalkLaneConfig, tick: Int64) -> EuclideousWalkTick {
    let n = c.n
    let cycleLen = euclidCycleLen(c.dir, n: n)
    var cycleHits = 0
    for s in 0..<cycleLen where c.buf[euclidReadIndex(s, n: n, dir: c.dir)] { cycleHits += 1 }
    let effHits = Int64(max(1, cycleHits))
    let tickBeat = Double(tick) * c.sub
    let phaseBeat: Double
    if c.restartMask != 0 {
        phaseBeat = tickBeat - euclideousMaskedResetOrigin(beat: tickBeat, stepBeats: c.loopStepBeats, mask: c.restartMask, loopSteps: c.loopSteps)
    } else {
        phaseBeat = c.spanBeats > 0 ? (tickBeat - columnStart(tickBeat, c.spanBeats)) : tickBeat
    }
    let localT = Int64((phaseBeat / c.sub).rounded(.down))
    let raw = Int(((localT % Int64(cycleLen)) + Int64(cycleLen)) % Int64(cycleLen))
    let isHit = c.buf[euclidReadIndex(raw, n: n, dir: c.dir)]
    // WITH / GAPS: the engine folds the partner check into the STRIKE decision only — `hitsUpTo` / `ord` below still count
    // every raw hit of the lane's own pattern ("the lane keeps its own rhythm"), so a filtered tick advances the ordinal
    // silently and the next strike lands further along the walk.
    var strikes = isHit
    if isHit, let f = c.listen {
        let coincides = euclideousListenPartnerHasHitAt(buf: f.buf, n: f.n, dir: f.dir, rateBeats: f.rateBeats, spanBeats: f.spanBeats,
                                                         atBeat: tickBeat, epsilonBeats: f.epsilonBeats)
        strikes = f.requireCoincide ? coincides : !coincides
    }
    let cy = (localT - Int64(raw)) / Int64(cycleLen)
    var hitsUpTo = 0
    for s in 0...raw where c.buf[euclidReadIndex(s, n: n, dir: c.dir)] { hitsUpTo += 1 }
    let ord = cy * effHits + Int64(hitsUpTo - 1)
    let adv: Int64 = c.advanceStep ? (c.locked ? Int64(raw) : localT) : (c.locked ? Int64(hitsUpTo - 1) : ord)
    return EuclideousWalkTick(isHit: isHit, strikes: strikes, advOrd: adv, playedStep: euclideousWalkStep(c, ord: adv))
}
/// The riff step (0-based, post-NUDGE) the walk lands on at ordinal `ord`.
func euclideousWalkStep(_ c: EuclideousWalkLaneConfig, ord: Int64) -> Int {
    riffRotateStep(riffStepAt(c.riffDir, raw: Int(ord) * c.stride, steps: max(1, c.length), seed: c.seed), by: c.rotate, steps: max(1, c.length))
}
/// The walk position BEFORE NUDGE — the axis "up the steps / down the steps" is measured on.
private func euclideousWalkPos(_ c: EuclideousWalkLaneConfig, ord: Int64) -> Int {
    riffStepAt(c.riffDir, raw: Int(ord) * c.stride, steps: max(1, c.length), seed: c.seed)
}

/// STRIKING ticks (a raw hit that also passes any WITH / GAPS filter) around `beat`: `prev` is newest-first (the first is the latest hit at or before `beat`), `next` is
/// oldest-first (the first is the next hit strictly after it). Bounded, so an all-rest pattern returns empty.
func euclideousWalkScanHits(_ c: EuclideousWalkLaneConfig, beat: Double, back: Int, ahead: Int) -> (prev: [Int64], next: [Int64]) {
    guard c.sub > 0, c.n > 0 else { return ([], []) }
    // `beat` is REAL; ticks live in musical beats — map it across the swing warp first (monotonic, so the last
    // tick whose real onset is ≤ `beat` is the one whose musical beat is the last ≤ musicalOf(beat)).
    let mBeat = c.swingA == 1 ? beat : musicalOf(beat, stepBeats: c.swingStepBeats, a: c.swingA)
    let k0 = Int64((mBeat / c.sub).rounded(.down))
    let cap = Int64(euclidCycleLen(c.dir, n: c.n) * 4 + 16)
    var prev: [Int64] = [], next: [Int64] = []
    var k = k0, scanned: Int64 = 0
    while prev.count < back && scanned < cap {
        if euclideousWalkTick(c, tick: k).strikes { prev.append(k) }
        k -= 1; scanned += 1
    }
    k = k0 + 1; scanned = 0
    while next.count < ahead && scanned < cap {
        if euclideousWalkTick(c, tick: k).strikes { next.append(k) }
        k += 1; scanned += 1
    }
    return (prev, next)
}

/// The leftmost / rightmost displayed steps (0-based) the lane's walk ever lands on, as the walk itself computes
/// them from direction, LEN, NUDGE and STRIDE — the "loop's end blocks" a wrap thread runs out past.
func euclideousWalkVisitedRange(dir: RiffDir, length: Int, stride: Int, rotate: Int) -> (min: Int, max: Int) {
    let len = max(1, length)
    var lo = Int.max, hi = Int.min
    for ord in 0..<(2 * 8 * 7 + 2 * len) {
        let pos = riffStepAt(dir, raw: ord * stride, steps: len, seed: 0)
        let s = riffRotateStep(pos, by: rotate, steps: len)
        lo = Swift.min(lo, s); hi = Swift.max(hi, s)
    }
    return (lo, hi)
}

// ── the plan ────────────────────────────────────────────────────────────────────────────────────────

struct EuclideousTagDest: Equatable { var step: Int; var rank: Int; var isRest: Bool }
struct EuclideousWalkTagPlan: Equatable {
    var seatStep: Int            // 0-based column the tag sits in
    var seatRank: Int            // 1…8 row (a rest keeps the last note's row)
    var seatIsRest: Bool         // drawn hollow
    var facingRight: Bool        // the point faces the lane's next move
    var turned: Bool             // the next move reverses the last one (PEND / PING)
    var dest: EuclideousTagDest? // where the next advance lands (nil when nothing is scheduled)
    var isWrap: Bool
    var isReset: Bool
    var landedSeconds: Double?   // the previous advance, relative to "now" (≤ 0)
    var nextSeconds: Double?     // the next advance, relative to "now" (> 0)
    var landedTick: Int64?
    var visitedMin: Int
    var visitedMax: Int
}

/// `ranks` is the playing riff's rank per step (0 = rest). `polledStep` is the lane's live step (the SAME value
/// the RIFF-tab thumbnail reads; < 0 = not started). `running` = transport playing AND the lane playing. Returns
/// nil when there is nothing to draw (not started, or the riff has no notes on the steps the walk visits).
func euclideousWalkTagPlan(cfg: EuclideousWalkLaneConfig, ranks: [Int], beat: Double, secondsPerBeat spb: Double,
                           polledStep: Int, running: Bool) -> EuclideousWalkTagPlan? {
    guard polledStep >= 0 else { return nil }
    let len = max(1, min(8, cfg.length))
    func rankAt(_ s: Int) -> Int { s >= 0 && s < ranks.count ? max(0, min(8, ranks[s])) : 0 }
    guard (0..<len).contains(where: { rankAt($0) >= 1 }) else { return nil }   // empty riff: no tag
    let vis = euclideousWalkVisitedRange(dir: cfg.riffDir, length: len, stride: cfg.stride, rotate: cfg.rotate)

    // A tag sitting on the polled step with nothing scheduled: stopped transport, stopped lane, no hits, or a
    // prediction the poll doesn't corroborate.
    func staticPlan() -> EuclideousWalkTagPlan? {
        let step = min(polledStep, 7)
        let right = cfg.riffDir != .reverse
        var rank = rankAt(step)
        let rest = rank == 0
        if rest {
            var found = 0
            for j in 1...len {
                let r = rankAt(posMod(step + (right ? -j : j), len))
                if r >= 1 { found = r; break }
            }
            guard found >= 1 else { return nil }
            rank = found
        }
        return EuclideousWalkTagPlan(seatStep: step, seatRank: rank, seatIsRest: rest, facingRight: right, turned: false, dest: nil,
                                     isWrap: false, isReset: false, landedSeconds: nil, nextSeconds: nil, landedTick: nil,
                                     visitedMin: vis.min, visitedMax: vis.max)
    }
    guard running, cfg.sub > 0, spb > 0 else { return staticPlan() }
    let scan = euclideousWalkScanHits(cfg, beat: beat, back: 5, ahead: 1)
    guard let pTick = scan.prev.first, let hTick = scan.next.first else { return staticPlan() }
    let tP = euclideousWalkTick(cfg, tick: pTick), tH = euclideousWalkTick(cfg, tick: hTick)
    let secP = (euclideousWalkRealBeat(cfg, tick: pTick) - beat) * spb
    let secH = (euclideousWalkRealBeat(cfg, tick: hTick) - beat) * spb

    // Poll corroboration: the polled step must be the predicted landing, or the next one (the engine renders a
    // little ahead of the UI clock), or — for a short while — the one before (poll latency).
    // (A very fast lane can leave the poll more than one hit behind, so each earlier hit is allowed while the hit
    // AFTER it is still within the grace window.)
    let lagOK: Bool = {
        for j in 1..<max(1, min(4, scan.prev.count)) {
            let sinceNewer = (beat - euclideousWalkRealBeat(cfg, tick: scan.prev[j - 1])) * spb
            if sinceNewer < EuclideousTagMetrics.pollLagGraceSeconds && polledStep == euclideousWalkTick(cfg, tick: scan.prev[j]).playedStep { return true }
        }
        return false
    }()
    guard polledStep == tP.playedStep || polledStep == tH.playedStep || lagOK else { return staticPlan() }

    // Heights. A rest keeps the row of the last note the walk played; none ever played ⇒ nearest note behind.
    func heldRank(before ord: Int64) -> Int? {
        // The last note the lane actually PLAYED: walk back through its real earlier hits (correct under ADV STEP,
        // where ordinals also tick on non-hits, and across a LOCK/reset restart, where they jump back to 0).
        for t in scan.prev.dropFirst() {
            let r = rankAt(euclideousWalkTick(cfg, tick: t).playedStep)
            if r >= 1 { return r }
        }
        // None in the recent hits (a long run of rests, or the lane has barely started): the nearest note behind in
        // walk order.
        for j in 1...(2 * len + 2) {
            let r = rankAt(euclideousWalkStep(cfg, ord: ord - Int64(j)))
            if r >= 1 { return r }
        }
        return nil
    }
    let seatStep = tP.playedStep
    var seatRank = rankAt(seatStep)
    let seatIsRest = seatRank == 0
    if seatIsRest { guard let held = heldRank(before: tP.advOrd) else { return nil }; seatRank = held }
    let destStep = tH.playedStep
    let destRankRaw = rankAt(destStep)
    let dest = EuclideousTagDest(step: destStep, rank: destRankRaw >= 1 ? destRankRaw : seatRank, isRest: destRankRaw == 0)
    let isReset = tH.advOrd <= tP.advOrd

    // Facing: the direction of each move across the recent hits, carrying the previous facing through zero-length
    // moves (PING's repeated end step) — and, for a restart, the direction the walk WOULD have gone.
    let seq = Array(scan.prev.reversed()) + [hTick]
    let ords: [Int64] = seq.map { euclideousWalkTick(cfg, tick: $0).advOrd }
    func moveFacing(_ a: Int64, _ b: Int64, reset: Bool) -> Bool? {
        switch cfg.riffDir {
        case .forward, .random, .drunk: return true
        case .reverse: return false
        case .pendulum, .pingpong:
            let d = euclideousWalkPos(cfg, ord: reset ? a + 1 : b) - euclideousWalkPos(cfg, ord: a)
            return d > 0 ? true : (d < 0 ? false : nil)
        }
    }
    var facings: [Bool] = []
    var carry = true
    for i in 0..<(seq.count - 1) {
        if let f = moveFacing(ords[i], ords[i + 1], reset: ords[i + 1] <= ords[i]) { carry = f }
        facings.append(carry)
    }
    let facingRight = facings.last ?? true
    let prevFacing = facings.count >= 2 ? facings[facings.count - 2] : facingRight

    // Wrap (display space): the move heads one way but its destination lies the other way, so the thread leaves
    // by the end of the loop and re-enters at the other. A restart is never a wrap.
    let isWrap = !isReset && ((facingRight && destStep < seatStep) || (!facingRight && destStep > seatStep))
    return EuclideousWalkTagPlan(seatStep: seatStep, seatRank: seatRank, seatIsRest: seatIsRest, facingRight: facingRight,
                                 turned: prevFacing != facingRight, dest: dest, isWrap: isWrap, isReset: isReset,
                                 landedSeconds: secP, nextSeconds: secH, landedTick: pTick,
                                 visitedMin: vis.min, visitedMax: vis.max)
}

// ── thread geometry + motion ────────────────────────────────────────────────────────────────────────

struct EuclideousThreadSegment: Equatable { var from: CGPoint; var to: CGPoint }
struct EuclideousThreadGeometry: Equatable {
    var segments: [EuclideousThreadSegment]   // one straight line, or [exit piece, entry piece] for a wrap
    var dot: CGPoint
    var hollowDot: Bool
    var isWrap: Bool
}
/// nil = no thread (nothing scheduled, or a zero-length move: the destination is the current seat).
func euclideousThreadGeometry(lane: Int, plan: EuclideousWalkTagPlan, cellW: CGFloat, cellH: CGFloat, gap: CGFloat) -> EuclideousThreadGeometry? {
    guard let d = plan.dest else { return nil }
    if d.step == plan.seatStep && d.rank == plan.seatRank { return nil }
    let from = euclideousTagSeatCentre(lane: lane, col: plan.seatStep, rank: plan.seatRank, cellW: cellW, cellH: cellH, gap: gap)
    let to = euclideousTagSeatCentre(lane: lane, col: d.step, rank: d.rank, cellW: cellW, cellH: cellH, gap: gap)
    guard plan.isWrap else {
        return EuclideousThreadGeometry(segments: [EuclideousThreadSegment(from: from, to: to)], dot: to, hollowDot: d.isRest, isWrap: false)
    }
    let pitch = cellW + gap, over = EuclideousTagMetrics.wrapOvershoot
    let rightEdge = CGFloat(plan.visitedMax) * pitch + cellW + over
    let leftEdge = CGFloat(plan.visitedMin) * pitch - over
    let exitX = plan.facingRight ? rightEdge : leftEdge
    let entryX = plan.facingRight ? leftEdge : rightEdge
    return EuclideousThreadGeometry(segments: [EuclideousThreadSegment(from: from, to: CGPoint(x: exitX, y: from.y)),
                                               EuclideousThreadSegment(from: CGPoint(x: entryX, y: to.y), to: to)],
                                    dot: to, hollowDot: d.isRest, isWrap: true)
}
/// Where the tag is, and how opaque, `raw` (0…1, linear) of the way through a flight. A straight move eases along
/// the one line; a wrap travels the exit piece fading out over the first half, then the entry piece fading back in.
func euclideousTagFlightPose(_ g: EuclideousThreadGeometry, raw: Double) -> (centre: CGPoint, opacity: Double) {
    func lerp(_ s: EuclideousThreadSegment, _ e: Double) -> CGPoint {
        CGPoint(x: s.from.x + (s.to.x - s.from.x) * CGFloat(e), y: s.from.y + (s.to.y - s.from.y) * CGFloat(e))
    }
    let r = max(0, min(1, raw))
    if !g.isWrap || g.segments.count < 2 { return (lerp(g.segments[0], euclideousTagEase(r)), 1) }
    if r <= 0.5 { let u = r * 2; return (lerp(g.segments[0], euclideousTagEase(u)), 1 - u) }
    let u = (r - 0.5) * 2
    return (lerp(g.segments[1], euclideousTagEase(u)), u)
}

struct EuclideousTagDrawing: Equatable {
    var centre: CGPoint
    var hollow: Bool
    var pointsRight: Bool
    var scaleX: Double                           // 1 normally; sweeps 1 → 0 → −1 across a turn
    var opacity: Double
    var thread: EuclideousThreadGeometry?        // only while seated with a move scheduled
}
/// One lane, one instant: the plan's time offsets are already relative to "now" (landed ≤ 0 < next).
func euclideousTagDrawing(lane: Int, plan: EuclideousWalkTagPlan, cellW: CGFloat, cellH: CGFloat, gap: CGFloat) -> EuclideousTagDrawing {
    let seat = euclideousTagSeatCentre(lane: lane, col: plan.seatStep, rank: plan.seatRank, cellW: cellW, cellH: cellH, gap: gap)
    var out = EuclideousTagDrawing(centre: seat, hollow: plan.seatIsRest, pointsRight: plan.facingRight, scaleX: 1, opacity: 1, thread: nil)
    guard let nextS = plan.nextSeconds else { return out }
    let geo = euclideousThreadGeometry(lane: lane, plan: plan, cellW: cellW, cellH: cellH, gap: gap)
    // TURN: on landing, a horizontal flip about the tag's own centre — begins 20ms after arrival, lasts 100ms. A fast
    // lane can set off again before the flip is done, so it carries on through the flight rather than snapping.
    if plan.turned, let landed = plan.landedSeconds {
        let since = -landed
        if since < EuclideousTagMetrics.turnDelaySeconds + EuclideousTagMetrics.turnSeconds {
            out.pointsRight = !plan.facingRight   // still the old way round until the flip completes
            if since >= EuclideousTagMetrics.turnDelaySeconds {
                out.scaleX = 1 - 2 * (since - EuclideousTagMetrics.turnDelaySeconds) / EuclideousTagMetrics.turnSeconds
            }
        }
    }
    switch euclideousTagPhase(now: 0, previousAdvance: plan.landedSeconds, nextAdvance: nextS) {
    case .seated:
        out.thread = geo
    case .inFlight(let raw):
        if let geo { let pose = euclideousTagFlightPose(geo, raw: raw); out.centre = pose.centre; out.opacity = pose.opacity }
    case .landed:
        break
    }
    return out
}

// MARK: - FOURFOLD HEADER (ferry "Fourfold header", approved by Paul 2026-10-15)
//
// Pure, Foundation-only support for the regrouped header: the key label, the output rings' state and the lane-side
// pulse/trace cues, the A/B/C layout ladder (ONE formula shared by the header and the page body below it), and the
// ring flare envelope. Nothing here knows about SwiftUI; `EuclideousPage` and `OutputRingPainter` only draw what these
// return.

/// The key as the RECEIVER chip prints it (`"<root> <ScaleType.label>"`, ASCII sharps): e.g. "C MINOR", "A MIXO",
/// "D DORIAN". ONE function, used by the header's key pill AND `Receiver.scaleLabel`, so the two can never disagree.
func euclideousKeyLabel(root: Int, type: ScaleType) -> String {
    let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    return "\(names[((root % 12) + 12) % 12]) \(type.label)"
}

/// The key as VoiceOver should speak it ("Key, C minor"): the spoken root ("C sharp") and the scale spelled out (the chip
/// label abbreviates — "MIXO", "HARM MIN").
func euclideousKeySpokenName(root: Int, type: ScaleType) -> String {
    let roots = ["C", "C sharp", "D", "D sharp", "E", "F", "F sharp", "G", "G sharp", "A", "A sharp", "B"]
    let scale: String
    switch type {
    case .major: scale = "major"; case .naturalMinor: scale = "minor"; case .harmonicMinor: scale = "harmonic minor"
    case .melodicMinor: scale = "melodic minor"; case .dorian: scale = "dorian"; case .mixolydian: scale = "mixolydian"
    case .lydian: scale = "lydian"; case .phrygian: scale = "phrygian"; case .majorPentatonic: scale = "major pentatonic"
    case .minorPentatonic: scale = "minor pentatonic"; case .blues: scale = "blues"; case .wholeTone: scale = "whole tone"
    case .chromatic: scale = "chromatic"
    }
    return "\(roots[((root % 12) + 12) % 12]) \(scale)"
}

/// The four lanes' own emitter masks (the ones `laneOutRow` edits: nil = 0 = routed nowhere), padded/truncated to 4.
func euclideousLaneMasks(_ lines: [EuclidLine]) -> [UInt8] {
    (0..<4).map { $0 < lines.count ? (lines[$0].emitterMask ?? 0) : 0 }
}

// ── output rings ────────────────────────────────────────────────────────────────────────────────────

/// An output ring's quarters are LANES by where the lanes sit on screen: lane 0 top-left, 1 top-right, 2 bottom-left,
/// 3 bottom-right. Each arc is centred on these angles, measured CLOCKWISE FROM 12 O'CLOCK (so the 24° gaps sit at 12,
/// 3, 6 and 9) — NOT in lane-index order. SwiftUI measures from 3 o'clock; the painter converts.
let euclideousRingQuarterCentreDegrees: [Double] = [315, 45, 225, 135]
let euclideousRingArcDegrees: Double = 66

enum EuclideousOutputRingMode: Equatable {
    case onRouted      // output on, at least one lane routed to it
    case onUnrouted    // output on, no lane routed
    case off           // MAIN OUT bit off (dashed quarters)
}
struct EuclideousOutputRingState: Equatable {
    var mode: EuclideousOutputRingMode
    var lit: [Bool]    // index = lane 0…3: this lane's own emitter mask contains this output
    var dashed: Bool { mode == .off }
}
func euclideousOutputRingState(output: Int, laneMasks: [UInt8], mainOutMask: UInt8) -> EuclideousOutputRingState {
    let lit = (0..<4).map { lane in lane < laneMasks.count && (laneMasks[lane] >> UInt8(output)) & 1 != 0 }
    let on = (mainOutMask >> UInt8(output)) & 1 != 0
    return EuclideousOutputRingState(mode: on ? (lit.contains(true) ? .onRouted : .onUnrouted) : .off, lit: lit)
}

enum EuclideousOutputCue: Equatable { case none, ringOutCircle, ringRhythmTab, dim }
enum EuclideousOutputCueMode { case pulse, trace }
/// What each lane shows for output `output`: PULSE (after a tap) rings every routed lane — around its OUT circle if the
/// card is showing RHYTHM, else around its RHYTHM tab — and leaves the rest alone; TRACE (while held) does the same but
/// dims every lane that is NOT routed (so with no routed lane all four dim). `laneShowsRhythm[i]` = lane i's tab is RHYTHM.
func euclideousOutputCues(output: Int, laneMasks: [UInt8], laneShowsRhythm: [Bool], mode: EuclideousOutputCueMode) -> [EuclideousOutputCue] {
    (0..<4).map { lane in
        let routed = lane < laneMasks.count && (laneMasks[lane] >> UInt8(output)) & 1 != 0
        if routed { return (lane < laneShowsRhythm.count && laneShowsRhythm[lane]) ? .ringOutCircle : .ringRhythmTab }
        return mode == .trace ? .dim : .none
    }
}

// ── ring flare ──────────────────────────────────────────────────────────────────────────────────────

/// The comet bar's own flare windows, in LANE STEPS since the strike (one definition, used by `EuclidCometBar` and the
/// output rings so they fade together): the lingering afterglow and the short sharp burst.
let euclideousFlareAfterglowSteps: Double = 1.5
let euclideousFlareBurstSteps: Double = 0.35
/// 0…1 flare strength `ageSteps` after a strike: the burst's peak at the strike, settling onto 60% of the afterglow,
/// then fading to 0 as the afterglow ends. Drives the ring quarter's 2.5 → 3.5pt thickening, its 7pt glow and the
/// disc wash together.
func euclideousRingFlare(ageSteps: Double) -> Double {
    guard ageSteps >= 0 else { return 0 }
    let recede = max(0, 1 - ageSteps / euclideousFlareAfterglowSteps)
    let burst = max(0, 1 - ageSteps / euclideousFlareBurstSteps)
    return max(burst, recede * 0.6)
}

// ── Fourfold settings, MIDI IN "LISTEN ON" (2026-10-15 ferry §3) ───────────────────────────────────────

/// §3.1, literal: the value text under the LISTEN ON label. `mask` is already resolved (0xFFFF ⇒ every
/// channel — `EuclidLine`'s own "today's OMNI").
func euclideousListenOnValueLabel(mask: UInt16) -> String {
    if mask == 0xFFFF { return "ALL CHANNELS" }
    let picked = (0..<16).filter { (mask & (1 << $0)) != 0 }.map { $0 + 1 }
    if picked.isEmpty { return "ALL CHANNELS" }   // the model never actually resolves to empty (§3.5) — never silently say nothing
    if picked.count <= 4 { return "CH " + picked.map { "\($0)" }.joined(separator: " · ") }
    return "\(picked.count) CHANNELS"
}
/// §3.3, literal, tapping a numbered channel button (`channel1based` 1...16): "tapping a channel while ALL
/// is lit picks only that channel. After that, taps toggle channels. Turning off the last picked channel
/// lights ALL again." "Picking all sixteen by hand reads as ALL" falls out for free — toggling the 16th bit
/// on makes the mask equal 0xFFFF by construction, no separate case.
func euclideousListenOnAfterChannelTap(mask: UInt16, channel1based: Int) -> UInt16 {
    guard channel1based >= 1, channel1based <= 16 else { return mask }
    let bit: UInt16 = 1 << (channel1based - 1)
    if mask == 0xFFFF { return bit }
    let toggled = mask ^ bit
    return toggled == 0 ? 0xFFFF : toggled
}
/// §3.3: "tapping ALL goes back to every channel" — unconditional, regardless of the mask beforehand.
func euclideousListenOnAfterAllTap() -> UInt16 { 0xFFFF }
/// Display-only: "ALL lit means every channel, and the 16 buttons show unlit" — so a channel button never
/// reads lit while the mask is the all-channels value, even though every one of its bits is technically set.
func euclideousListenOnChannelIsLit(mask: UInt16, channel1based: Int) -> Bool {
    guard channel1based >= 1, channel1based <= 16, mask != 0xFFFF else { return false }
    return (mask & (1 << (channel1based - 1))) != 0
}
func euclideousListenOnAllIsLit(_ mask: UInt16) -> Bool { mask == 0xFFFF }

// ── Fourfold settings sheet geometry (2026-10-15 ferry §2.3) ───────────────────────────────────────────
/// "width = min(448, containerW)." The height half of §2.3 ("the tallest tab's natural height... one
/// formula, like the header ladder") is measured live instead (see `EuclideousSettingsSheet`'s own doc
/// comment on `FFSHeightKey` for why) — a disclosed departure from "one formula," since these rows include
/// wrapped prose a hand-rolled constant-based formula could only approximate, not reproduce exactly.
func euclideousSettingsSheetWidth(containerW: CGFloat) -> CGFloat { min(448, containerW) }

// ── ring painting decisions + the press state machine ───────────────────────────────────────────────

/// What sits behind an output ring's letter. Spec §4.5: OFF draws NO disc ("the ground shows through") — but HELD (§4.7)
/// is "disc #DFE3EA, letter ink", unconditionally, so a held OFF output still gets its (light) disc; without it the ink
/// letter would sit on the near-identical dark page ground and vanish.
enum EuclideousRingDisc: Equatable { case none, base, held }
func euclideousRingDisc(mode: EuclideousOutputRingMode, held: Bool) -> EuclideousRingDisc {
    if held { return .held }
    return mode == .off ? .none : .base
}
/// The letter's tone: ink only ever on the held (light) disc; otherwise by mode.
enum EuclideousRingLetterTone: Equatable { case ink, on, unrouted, off }
func euclideousRingLetterTone(mode: EuclideousOutputRingMode, held: Bool) -> EuclideousRingLetterTone {
    if held { return .ink }
    switch mode { case .onRouted: return .on; case .onUnrouted: return .unrouted; case .off: return .off }
}

/// One output ring's tap-vs-hold decision (spec §4.6/§4.7), kept PURE so it can be tested and so each ring owns its own
/// instance (a second finger on another ring can never disturb this one). Feed it the touch's events; it says what to do.
///   • release before `holdSeconds`            → `.tap`   (toggle, then pulse)
///   • the hold timer firing while still down  → `.holdBegan` (trace until release); the release then says `.holdEnded`
///     and NEVER `.tap` (a hold never toggles)
///   • dragging more than `dragCancel` away before the hold fires cancels the press entirely (no tap, no hold)
///   • a touch that is CANCELLED (system gesture, app backgrounded — no normal release) still ends a started hold
struct EuclideousRingPress: Equatable {
    static let holdSeconds: Double = 0.3
    static let dragCancel: Double = 14
    enum Action: Equatable { case none, tap, holdBegan, holdEnded }
    private(set) var down = false
    private(set) var holdFired = false
    private(set) var cancelled = false
    mutating func touchDown() { down = true; holdFired = false; cancelled = false }
    mutating func moved(distance: Double) {
        if down && !holdFired && !cancelled && distance > Self.dragCancel { cancelled = true }
    }
    mutating func holdTimerFired() -> Action {
        guard down, !holdFired, !cancelled else { return .none }
        holdFired = true
        return .holdBegan
    }
    mutating func touchEnded() -> Action {
        let a: Action = !down ? .none : (holdFired ? .holdEnded : (cancelled ? .none : .tap))
        self = EuclideousRingPress()
        return a
    }
    mutating func touchCancelled() -> Action {
        let a: Action = (down && holdFired) ? .holdEnded : .none
        self = EuclideousRingPress()
        return a
    }
}

// ── layout ladder ───────────────────────────────────────────────────────────────────────────────────

enum EuclideousHeaderMetrics {
    static let sp4: CGFloat = 4, sp8: CGFloat = 8, sp16: CGFloat = 16
    static let rowH: CGFloat = 44
    /// The spec's centre line, 31pt below the page top: a 44pt row centred on it puts the header block's top at 9pt.
    static let centreLineY: CGFloat = 31
    static var topMargin: CGFloat { centreLineY - rowH / 2 }
    static let target: CGFloat = 44, compactTarget: CGFloat = 36
    static let ringPitch: CGFloat = 44, compactRingPitch: CGFloat = 40
    static let markSize: CGFloat = 13
    static let monoAdvance: CGFloat = 0.6          // em — the page's monospaced advance estimate
    static let wordmarkChars = 8, wordmarkSize: CGFloat = 11, wordmarkTracking: CGFloat = 0.16
    static let captionChars = 3, captionSize: CGFloat = 9, captionTracking: CGFloat = 0.14
    static let segmentWidths: [CGFloat] = [66, 70, 40]
    static let segmentInset: CGFloat = 4
    static var segmentedWidth: CGFloat { segmentWidths.reduce(0, +) + segmentInset * 2 }   // 184
    static let keyPillWidth: CGFloat = 120
    /// The two text runs whose widths the layout estimates — the views use these SAME numbers for their frames.
    static var wordmarkWidth: CGFloat { CGFloat(wordmarkChars) * wordmarkSize * (monoAdvance + wordmarkTracking) }
    static var captionWidth: CGFloat { CGFloat(captionChars) * captionSize * (monoAdvance + captionTracking) }
}
struct EuclideousHeaderGroupWidths: Equatable {
    var brand: CGFloat, outputs: CGFloat, notes: CGFloat, utilities: CGFloat
    var gap: CGFloat            // the space between row-1 groups: sp16 (A, B) or sp8 (C)
    /// How far into the OUTPUTS group the first ring's target starts (the "OUT" caption + sp4; 0 when the caption is hidden).
    /// The RINGS — not the whole group — are what the spec centres on the lane gutter (§2.3), so the layout needs this.
    var outputsLead: CGFloat
    /// The four rings' own span (the OUTPUTS group minus its lead).
    var ringsSpan: CGFloat { outputs - outputsLead }
}
/// Each group's width, once, from the same constants the views draw with.
func euclideousHeaderGroupWidths(compact: Bool) -> EuclideousHeaderGroupWidths {
    typealias M = EuclideousHeaderMetrics
    let t = compact ? M.compactTarget : M.target
    let wordmarkW = M.wordmarkWidth
    let captionW = M.captionWidth
    let brand = M.markSize + M.sp8 + (compact ? 0 : wordmarkW + M.sp16) + 2 * t
    let lead = compact ? 0 : captionW + M.sp4
    let outputs = lead + 4 * (compact ? M.compactRingPitch : M.ringPitch)
    return EuclideousHeaderGroupWidths(brand: brand, outputs: outputs, notes: M.segmentedWidth + M.sp8 + M.keyPillWidth,
                                       utilities: 2 * t, gap: compact ? M.sp8 : M.sp16, outputsLead: lead)
}

/// The landscape page's column split — ONE definition for the body (`landscapeLayout`) and the header (which wants the
/// riff panel's leading edge and the lane grid's centre). Container coordinates: 0 = the container's leading edge.
struct EuclideousLandscapeColumns: Equatable {
    var riffColW: CGFloat, laneColW: CGFloat, riffLeadingX: CGFloat, laneCentreX: CGFloat
}
func euclideousLandscapeColumns(containerW: CGFloat) -> EuclideousLandscapeColumns {
    let riff = containerW * 0.36
    let lane = containerW - riff - EuclideousHeaderMetrics.sp16
    return EuclideousLandscapeColumns(riffColW: riff, laneColW: lane, riffLeadingX: lane + EuclideousHeaderMetrics.sp16, laneCentreX: lane / 2)
}

struct EuclideousHeaderGroupFrame: Equatable { var x: CGFloat; var width: CGFloat; var row: Int }
struct EuclideousHeaderLayout: Equatable {
    enum Kind: Equatable { case a, b, c }
    var kind: Kind
    var widths: EuclideousHeaderGroupWidths
    var brand: EuclideousHeaderGroupFrame, outputs: EuclideousHeaderGroupFrame
    var notes: EuclideousHeaderGroupFrame, utilities: EuclideousHeaderGroupFrame
    var rowCount: Int { kind == .a ? 1 : 2 }
    var compact: Bool { kind == .c }
    var height: CGFloat { rowCount == 1 ? EuclideousHeaderMetrics.rowH : EuclideousHeaderMetrics.rowH * 2 + EuclideousHeaderMetrics.sp4 }
}
private func headerClamp(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat) -> CGFloat { lo > hi ? lo : min(max(v, lo), hi) }

/// The first layout that fits `containerW` (page width − sp16 × 2). `riffLeadingX` / `laneCentreX` are in container
/// coordinates (see `euclideousLandscapeColumns`; portrait passes the container centre for `laneCentreX`). Portrait
/// never uses A. Positions are solved with ONE clamp per group, so no combination of slides can leave two groups
/// closer than their stated gap while the layout still "fits". The RINGS (not the OUTPUTS group with its caption) are what
/// centre on `laneCentreX` (spec §2.3), so the group's x is `laneCentreX − outputsLead − ringsSpan/2`, then clamped.
func euclideousHeaderLayout(containerW: CGFloat, isLandscape: Bool, riffLeadingX: CGFloat, laneCentreX: CGFloat) -> EuclideousHeaderLayout {
    typealias M = EuclideousHeaderMetrics
    let full = euclideousHeaderGroupWidths(compact: false)
    let aNeeds = full.brand + full.outputs + full.notes + full.utilities + 3 * full.gap
    let bNeeds = full.brand + full.outputs + full.utilities + 2 * full.gap
    if isLandscape && containerW >= aNeeds {
        let uX = containerW - full.utilities
        // NOTES: on the riff panel's leading edge, slid left until it clears UTILITIES by sp16 — but never so far left
        // that the rings (and BRAND) lose their own room.
        let notesX = headerClamp(riffLeadingX, full.brand + full.outputs + 2 * full.gap, uX - full.gap - full.notes)
        let ringsX = headerClamp(laneCentreX - full.outputsLead - full.ringsSpan / 2, full.brand + full.gap, notesX - full.gap - full.outputs)
        return EuclideousHeaderLayout(kind: .a, widths: full,
                                      brand: .init(x: 0, width: full.brand, row: 0), outputs: .init(x: ringsX, width: full.outputs, row: 0),
                                      notes: .init(x: notesX, width: full.notes, row: 0), utilities: .init(x: uX, width: full.utilities, row: 0))
    }
    let compact = containerW < bNeeds
    let w = compact ? euclideousHeaderGroupWidths(compact: true) : full
    let uX = containerW - w.utilities
    let ringsX = headerClamp(laneCentreX - w.outputsLead - w.ringsSpan / 2, w.brand + w.gap, uX - w.gap - w.outputs)
    return EuclideousHeaderLayout(kind: compact ? .c : .b, widths: w,
                                  brand: .init(x: 0, width: w.brand, row: 0), outputs: .init(x: ringsX, width: w.outputs, row: 0),
                                  notes: .init(x: 0, width: w.notes, row: 1), utilities: .init(x: uX, width: w.utilities, row: 0))
}
