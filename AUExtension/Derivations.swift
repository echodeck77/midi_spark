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
    // LANES GRID (2026-10-18): the 8-bit form is now a wrapper over the 16-cell `euclideousMaskedResetOrigin(beat:cellBeats:mask:cells:)`
    // below (same flooring, same arithmetic) — kept for the old per-step restart mask and its tests.
    guard stepBeats > 0, loopSteps > 0 else { return 0 }
    return euclideousMaskedResetOrigin(beat: beat, cellBeats: stepBeats, mask: UInt16(mask), cells: min(8, loopSteps))
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
// §2.2/§2.7/§3.4/§7.3's own `euclideousNextLandingBeat`/`euclideousRunFirstBarLine`/
// `euclideousAppendLooperEvent`/`euclideousLooperSegmentGeometry` are DELETED (2026-10-18 ferry, "drop
// the loop functionality") — each had zero remaining callers once `AudioUnitViewController`'s looper
// state machine and `EuclideousPage`'s loop-row UI were removed; confirmed by grep before deleting.
// `euclideousLoopPositionBars`/`euclideousLooperEffectiveRank` above stay — Router.swift's per-hit read
// still calls `euclideousLooperEffectiveRank`, now permanently with `active: false`.

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
        // RIFF WINDOW ferry (2026-10-21): SHIFT wraps at the riff's 8 columns, not at LENGTH — see
        // `euclideousRiffColumn`'s own comment for why. Mirrored here so a short-LENGTH lane's marks agree
        // with what the engine can actually reach.
        let playedStep = riffRotateStep(walkPos, by: rotate, steps: 8)
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

/// RIFF WALK ferry (2026-10-19) §5.2: the walk step w = floor(o ÷ EVERY) — the riff ordinal divided down so
/// EVERY consecutive hits (ADV HIT) or steps (ADV STEP) of a group share the same walk position. EVERY 1
/// (today's behaviour) makes this the identity. Floors towards −∞ (never reached in practice — o is never
/// negative — but §5.2 asks for it, and `floorDiv` already does it for free).
@inline(__always)
func euclideousRiffWalkStep(ordinal o: Int64, every: Int) -> Int64 {
    floorDiv(o, Int64(max(1, every)))
}
/// RIFF WALK ferry §5.2: the column a riff hit reads — today's `riffStepAt` → `riffRotateStep` pipeline, with
/// the WALK STEP (not the raw ordinal) driving the walk. Every site that turns the riff ordinal into a column
/// calls this and nothing else — no second derivation. `w * stride` stays far inside `Int`'s range in every
/// real caller (w is bounded by the walk period, at most 16, and stride by 7).
/// RIFF WINDOW ferry (2026-10-21): `riffStepAt` still cycles over `0..<length` — LENGTH is the WIDTH of the
/// window the walk loops over (and still anchors PENDULUM/PING-PONG's bounce points, REVERSE's mirroring,
/// etc., exactly as before). The final `riffRotateStep` used to wrap that result back into the SAME
/// `0..<length` window (so SHIFT only ever reordered the read sequence within columns 1...LENGTH — it could
/// never reach column LENGTH+1). It now wraps at 8 (the riff's real column count) instead, so SHIFT picks
/// WHERE that LENGTH-wide window starts in the full 8-column riff, wrapping past column 8 back to column 1
/// (LEN 4 SHIFT 4 now reads columns 5,6,7,8 — Paul's own worked example). SHIFT 0 and LENGTH 8 are both
/// unaffected by this change (mod 8 == mod length in both cases), so this only changes lanes that combine a
/// short LENGTH with a nonzero SHIFT — exactly the combination that used to silently do nothing useful.
@inline(__always)
func euclideousRiffColumn(ordinal o: Int64, every: Int, direction dir: RiffDir, length: Int, stride: Int, shift: Int, seed: UInt64 = 0) -> Int {
    let w = euclideousRiffWalkStep(ordinal: o, every: every)
    let step = riffStepAt(dir, raw: Int(w) * stride, steps: max(1, length), seed: seed)
    return riffRotateStep(step, by: shift, steps: 8)
}
/// RIFF WINDOW ferry (2026-10-21): the set of columns (0-based, 0...7) a LENGTH-wide window starting at SHIFT
/// covers, wrapping past column 8 back to column 1 — the ONE definition of "is this column inside the lane's
/// current riff window," so the mini-grid thumbnail, the never-play computation and the rail's played-column
/// set can't disagree about which columns the walk can actually reach. Before this ferry the window was
/// always `0..<length`; now it's this set instead, wherever a caller used to test `col < length`.
func euclideousRiffWindowColumns(length: Int, shift: Int) -> Set<Int> {
    let len = max(1, min(8, length))
    return Set((0..<len).map { ((shift + $0) % 8 + 8) % 8 })
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
    /// HITS/STEPS snap to one of a fixed count of whole values (band-snapped, ferry Touch behaviour §3);
    /// OFFSET (RHYTHM POLISH ferry, 2026-10-22), TILT, GATE and VELOCITY are continuous across their range, rounded only for storage/display (§5).
    /// OFFSET and TILT also carry a detent at their natural points (`euclideousSliderValueAtDetented`).
    var isWhole: Bool { self == .hits || self == .steps }
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
        // RHYTHM POLISH (2026-10-22): the displayed offset is the whole part plus `offsetFraction`; the slider's top is still STEPS−1 (a fraction on the top value reads as the top).
        return (min(Double(n - 1), Double(displayed) + line.offsetFractionResolved), 0, Double(n - 1))   // 0...STEPS-1
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
/// RHYTHM POLISH ferry (2026-10-22) §2.2 — the detents at the two controls' natural points, as pure functions of the VALUE (stateless: a drag within the radius reads as the point, one past it reads as itself, so "stays
/// snapped until it moves past that distance" holds by construction). OFFSET snaps to a whole step within 0.08 of a step; TILT snaps to 0 within 3 % (±0.03 of the value — NOT of the travel, which the older
/// `euclideousTiltDetentFrac` above measured as ±6 % of travel = ±12 % of the value; that one is no longer called).
enum EuclideousDetent {
    static let offsetStep = 0.08
    static let tiltValue = 0.03
}
func euclideousOffsetDetent(_ v: Double) -> Double {
    let r = v.rounded()
    return abs(v - r) <= EuclideousDetent.offsetStep + 1e-9 ? r : v   // the epsilon makes the stated radius inclusive despite binary rounding (2.08 − 2 = 0.08000000000000007)
}
func euclideousTiltDetent(_ v: Double) -> Double { abs(v) <= EuclideousDetent.tiltValue + 1e-9 ? 0 : v }
/// What a touch at `frac` commits, detents included — the ONE place the OFFSET / TILT detents are applied (the slider and the tests both call this).
func euclideousSliderValueAtDetented(_ field: EuclideousSliderField, _ line: EuclidLine, frac: Double) -> Double {
    let v = euclideousSliderValueAt(field, line, frac: frac)
    switch field {
    case .offset: return euclideousOffsetDetent(v)
    case .tilt: return euclideousTiltDetent(v)
    default: return v
    }
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
        line.hitsRequested = target   // RESTART CHAINS ferry §2.5: what was actually asked for, surviving a later shorter STEPS
    case .steps:
        let target = max(2, min(16, Int(newValue.rounded())))
        if target != line.steps {
            // STEPS genuinely CHANGING reverts an edited pattern to pure Euclid (ferry §8, ratified) — the
            // caller only invokes this commit when the mapped value actually differs from the pre-touch
            // one (rule 6, "no change, no commit"), so landing back on the SAME band never reaches here.
            // §2.5 (2026-10-19 ferry): pin whatever HITS/OFFSET were last actually asked for — resolved from
            // the CURRENT pulses/rotate if nothing was requested yet — before this change can clamp them
            // away, so growing STEPS back later restores the exact pattern left behind (§2.5's own example).
            if line.hitsRequested == nil { line.hitsRequested = line.pulses }
            if line.offsetRequested == nil { line.offsetRequested = line.offsetRequestedResolved }
            line.customHits = nil
            line.steps = target
            line.pulses = max(0, min(target, line.hitsRequestedResolved))
            line.rotate = (target - min(line.offsetRequestedResolved, target - 1)) % target
        }
    case .offset:
        // Inverse of euclideousSliderRange's own mirror (see its comment) — `newValue` is the DISPLAYED
        // quantity the slider's drag position computed; converting it back to the stored `rotate` needs
        // the same `(n - v) mod n` mirror applied in reverse (it's self-inverse, so the identical formula
        // undoes it exactly).
        // RHYTHM POLISH (2026-10-22): the value is continuous now — its whole part is the old integer offset (a comet-bar drag past the ends still wraps, mod STEPS) and its fraction is `offsetFraction`
        // (nil when the value is a whole step, so a whole offset stores exactly what it always did).
        let n = max(2, min(16, line.steps))
        let whole = newValue.rounded(.down)
        let frac = newValue - whole
        let v = Int(whole)
        let displayed = ((v % n) + n) % n
        let mirrored = (n - displayed) % n
        line.rotate = mirrored
        line.offsetRequested = displayed   // RESTART CHAINS ferry §2.5: what was actually asked for, surviving a later shorter STEPS
        line.offsetFraction = frac < 1e-9 ? nil : min(frac, 1 - 1e-9)
    case .tilt:
        guard line.customHits == nil else { return }   // disabled on an edited pattern — defensive; the UI never drags this
        // RHYTHM POLISH: writes both — `tilt` (an older build still reads it) and `tiltFine` (the opt-in for unrounded timing).
        let t = max(-1, min(1, newValue))
        line.tilt = t
        line.tiltFine = t
    case .gate:
        let target = max(0.01, min(euclideousLaneGateMax, newValue))   // floor matches euclideousSliderRange's own lowered floor; the ceiling is 99% — a lane's gate is never legato (`euclideousLaneGateMax`)
        // MIX ferry §6.3: the layers PART at the first edit — pin the notes layer to the CURRENT gate before it changes (only on a
        // genuine change, so a no-op commit never parts them). Same undo step: this runs inside the caller's one `edit`.
        if target != line.gateResolved { euclideousPinNotesLayer(&line, gate: true, velocity: false) }
        line.gate = target
    case .velocity:
        let target = max(1, min(127, Int(newValue.rounded())))
        if target != line.velocityAbsoluteResolved { euclideousPinNotesLayer(&line, gate: false, velocity: true) }
        line.velocityAbsolute = target
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
    // RHYTHM fixes §4 (2026-10-21): each case now restores every field its own commit touches, not
    // just the headline one — `hitsRequested`/`offsetRequested` (and, for `.steps`, `pulses`/`rotate`
    // too) were left at whatever the committed-then-aborted drag last wrote, so a long-press-cancel
    // could leave a stale requested value (or, for STEPS, a stale pulses/rotate pair inconsistent
    // with the restored step count) to resurface unexpectedly on a later edit.
    case .hits: line.pulses = snapshot.pulses; line.customHits = snapshot.customHits; line.hitsRequested = snapshot.hitsRequested
    case .steps:
        line.steps = snapshot.steps; line.pulses = snapshot.pulses; line.rotate = snapshot.rotate; line.customHits = snapshot.customHits
        line.hitsRequested = snapshot.hitsRequested; line.offsetRequested = snapshot.offsetRequested
    case .offset: line.rotate = snapshot.rotate; line.offsetRequested = snapshot.offsetRequested; line.offsetFraction = snapshot.offsetFraction
    case .tilt: line.tilt = snapshot.tilt; line.tiltFine = snapshot.tiltFine
    case .gate:
        line.gate = snapshot.gate
        // A long-press revert is NOT an edit: if the touch-down commit parted the layers (pinned `notesGate` to the old GATE), put
        // that back too, or a stray press would leave later GATE edits moving only the riff. Only the pin is undone — a notes-pad
        // value that differs from the snapshot GATE is left alone.
        if snapshot.notesGate == nil, line.notesGate == snapshot.gateResolved { line.notesGate = nil }
    case .velocity:
        line.velocityAbsolute = snapshot.velocityAbsolute
        if snapshot.notesVelocity == nil, line.notesVelocity == snapshot.notesVelocityResolved { line.notesVelocity = nil }
    }
}

/// Double-tap reset (ferry §9: "same defaults as the pads had") — mirrors the OLD per-pad double-tap
/// exactly: the old TILT/HITS pad only ever reset TILT (never HITS); the old OFFSET/STEPS pad only ever
/// reset OFFSET/rotate (never STEPS) — so HITS and STEPS have NO double-tap action here either, by the
/// same precedent, not an oversight.
func euclideousSliderDoubleTapDefault(_ field: EuclideousSliderField, _ line: inout EuclidLine) {
    switch field {
    case .hits, .steps: break
    case .offset: line.rotate = 0; line.offsetFraction = nil   // RHYTHM POLISH: double-tap clears the fraction too (it is an OFFSET writer)
    case .tilt: line.tilt = 0; line.tiltFine = 0
    case .gate:
        if line.gateResolved != 0.9 { euclideousPinNotesLayer(&line, gate: true, velocity: false) }
        line.gate = 0.9
    case .velocity:
        if line.velocityAbsoluteResolved != 100 { euclideousPinNotesLayer(&line, gate: false, velocity: true) }
        line.velocityAbsolute = 100
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
    case .gate: return 0.01
    case .tilt: return 0.05   // RHYTHM POLISH (2026-10-22) §2.4: a TILT swipe moves 5 %
    default: return 1
    }
}
/// RHYTHM POLISH §2.4 — where an adjustable swipe lands: OFFSET goes to the next / previous WHOLE step (clearing any fraction: 5.25 → 6 up, 5 down; 5 → 6 / 4); every other field moves by its step.
func euclideousSliderAccessibilityTarget(_ field: EuclideousSliderField, current cur: Double, increment: Bool) -> Double {
    if field == .offset { return increment ? cur.rounded(.down) + 1 : cur.rounded(.up) - 1 }
    let step = euclideousSliderAccessibilityStep(field)
    return increment ? cur + step : cur - step
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
        // RHYTHM POLISH §2.2: "5" for a whole offset, "5.25" (two decimals) only when the fraction isn't 0.
        let n = max(2, min(16, line.steps))
        let r = ((line.rotate % n) + n) % n
        let whole = (n - r) % n
        let f = line.offsetFractionResolved
        return f < 0.005 ? "\(whole)" : String(format: "%.2f", Double(whole) + f)
    case .tilt:
        let pct = Int((line.tiltResolved * 100).rounded())
        return pct == 0 ? "0%" : (pct > 0 ? "+\(pct)%" : "−\(-pct)%")   // RHYTHM POLISH §2.2: a whole percent with a sign, zero as "0%"
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
    if field == .offset { return base == "1" ? "1 step" : "\(base) steps" }   // RHYTHM POLISH §2.4: "Offset 5.25 steps" — the fraction is spoken
    guard field == .gate, euclideousGateIsLegato(line.gateResolved) else { return base }
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
    guard field == .gate, euclideousGateIsLegato(line.gateResolved) else { return field.name }
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

/// RHYTHM POLISH: the same list read from a lane's TICK-SPACE layout (a lane with a fractional OFFSET and/or a fine TILT — `EuclideousWalkLaneConfig.buf`): `tick` is the layout's own cell, `bufIdx` the BOX that tick
/// reads (`euclidReadIndex` with the lane's real step count and direction), i.e. the box the hit's start time falls in.
func euclideousLapHitSteps(layoutCells: [Bool], n: Int, dir: EuclidDir) -> [EuclidHitStep] {
    var out: [EuclidHitStep] = []
    for raw in 0..<min(layoutCells.count, euclidCycleLen(dir, n: n)) where layoutCells[raw] {
        out.append(EuclidHitStep(tick: raw, bufIdx: euclidReadIndex(raw, n: n, dir: dir)))
    }
    return out
}

/// Derives `euclideousRiffCyclePrediction`'s own `startOrd`/`drunkLive` inputs from the LIVE poll (the
/// ordinal the walk's most recent hit advanced on, + DRUNK's own live position/ordinal) — the UI only ever
/// polls "where is the walk right now," never "where did the current lap begin," so this reconstructs the
/// latter exactly rather than approximating it. RESTART CHAINS (ferry 2026-10-19): when the CURRENT pass is
/// itself one of the melody chain's own restart passes (`isMelodyRestartPass`, computed by the caller via
/// `euclideousIsMelodyChainRestartPass` — a melody chain of exactly [1] is true for every pass, old LOCK's own
/// guarantee, §4.7), the walk re-anchors at this lap's own start by construction, so the baseline is exactly 0
/// regardless of where the live poll happens to be. Any OTHER pass (a longer chain's non-restart passes) walks
/// on from an EARLIER lap's origin — this fallback cannot reconstruct which one from `hitSteps`/`liveOrd` alone,
/// so it falls through to the FREE reconstruction below; the call site's own `euclideousLapStartOrdinal` (the
/// engine's real per-tick core) overrides this with the exact answer whenever it can be computed, which is why
/// this fallback only needs to be honest, not exact, in that case. Under FREE, the walk is one continuous,
/// never-resetting sequence — `liveOrd % effHits` (HIT mode) or finding which `hitSteps` entry `liveOrd %
/// lapSteps` matches (STEP mode, since under that mode the ordinal literally IS the elapsed grid-step count)
/// both recover exactly which hit-index-within-the-lap the most recent hit was, letting the lap's own first-hit
/// ordinal be recovered by simple subtraction.
func euclideousRiffLapBaseline(hitSteps: [EuclidHitStep], lapSteps: Int, isMelodyRestartPass: Bool, advanceStep: Bool,
                                liveOrd: Int64, dir: EuclidDir = .fwd)
    -> (startOrd: Int64, currentHitIndex: Int) {
    guard !hitSteps.isEmpty, lapSteps > 0 else { return (0, 0) }
    // A restart pass re-anchors, so no live ordinal is needed. HIT mode feeds the walk the hit's own index (0, 1, 2…, so the
    // lap starts at 0). ADV STEP feeds it the LAP-LOCAL TICK itself (`raw` in `runEuclidLine`) — the leading rests count — so
    // the lap's first hit sits at ordinal `firstTick`, not 0 (`euclideousRiffCyclePrediction` subtracts `firstTick`, which
    // this baseline puts back). With the first hit on tick 0 the two are the same, which is why this went unnoticed.
    if isMelodyRestartPass { return (advanceStep ? Int64(hitSteps[0].tick) : 0, 0) }
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
                                    rotate: Int, seed: UInt64, startOrd: Int64, every: Int = 1) -> [Int] {
    guard !hitSteps.isEmpty, length > 0 else { return [] }
    let firstTick = hitSteps[0].tick
    return hitSteps.enumerated().map { (hitIdx, hs) in
        // DIRECTION FIX (2026-10-13 adversarial review): STEP-advance's "elapsed real ticks since the lap's
        // first hit" must be measured on the TICK axis (`.tick`), not the buffer-index axis — the two only
        // coincide for FWD. See `EuclidHitStep`'s own doc comment.
        let advOrd: Int64 = advanceStep ? startOrd + Int64(hs.tick - firstTick) : startOrd + Int64(hitIdx)
        // LANE STRIP ferry (2026-10-21): through `euclideousRiffColumn`, the one ordinal -> column function the Router, the mirror, the rails and REPEAT call. This used to walk
        // `riffStepAt(raw: ordinal × stride)` itself and so ignored ADVANCE EVERY: with EVERY ≥ 2 the footer numbers disagreed with the engine. `every` 1 is byte-identical.
        return euclideousRiffColumn(ordinal: advOrd, every: every, direction: dir, length: length, stride: stride, shift: rotate, seed: seed) + 1   // 1-based, matching the grid's own displayed rank numbers
    }
}

/// LANE STRIP ferry (2026-10-21): the pass the footers show, assembled in ONE place so the page and the tests call the same code — the lap that contains `nowBeat` (read when the page's body runs, which is
/// when the footers switch passes), its hits' riff columns (`prediction`, one per hit in time order), the ordinal its first hit reads (`startOrd`) and the ABSOLUTE tick of its first step
/// (`lapStartTick`; nil when the pattern has no hit or `cfg` is unknown), from which every hit's own tick follows (`lapStartTick + hit.tick`).
struct EuclideousFooterPass: Equatable { var prediction: [Int]; var startOrd: Int64; var lapStartTick: Int64? }
func euclideousFooterPass(line: EuclidLine, cfg: EuclideousWalkLaneConfig?, hitSteps: [EuclidHitStep], lapSteps: Int, liveOrd: Int64, nowBeat: Double) -> EuclideousFooterPass {
    let isMelodyRestartPass = cfg.map {
        euclideousIsMelodyChainRestartPass(beat: nowBeat, lapBeats: $0.chains.lapBeats, barBeats: $0.chains.barBeats, rhythmChain: $0.chains.rhythm, melodyChain: $0.chains.melody)
    } ?? false
    var baseline = euclideousRiffLapBaseline(hitSteps: hitSteps, lapSteps: lapSteps, isMelodyRestartPass: isMelodyRestartPass,
                                              advanceStep: line.riffAdvanceStepResolved, liveOrd: liveOrd, dir: line.directionResolved)
    var lapStartTick: Int64? = nil
    // LANES GRID §2.8: the lap's baseline takes BOTH origins — the riff ordinal the CURRENT lap's first hit reads, from the engine's own per-tick core, not reverse-derived from the polled ordinal.
    if let cfg, let lap = euclideousLapStart(cfg: cfg, beat: nowBeat) { baseline.startOrd = lap.ordinal; lapStartTick = lap.lapStartTick }
    let prediction = euclideousRiffCyclePrediction(hitSteps: hitSteps, advanceStep: line.riffAdvanceStepResolved, dir: line.euclideousRiffDirResolved,
                                                    stride: line.riffStrideResolved, length: line.riffLengthResolved, rotate: line.riffRotateResolved,
                                                    seed: UInt64(bitPattern: Int64(line.riffDirSeedResolved)), startOrd: baseline.startOrd, every: line.riffAdvanceEveryResolved)
    return EuclideousFooterPass(prediction: prediction, startOrd: baseline.startOrd, lapStartTick: lapStartTick)
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
/// `hitTied` (FX TAB §13.2): a hit an FX TIE cell applies to — drawn exactly as a hit on a tied rest (`hitOnRest`), but it can never be a FILL strike.
enum EuclidFooterState: Equatable { case hit(riffStep: Int?), hitOnRest(riffStep: Int), hitTied(riffStep: Int), miss }
func euclideousFooterStates(hitSteps: [EuclidHitStep], lapSteps: Int, prediction: [Int]?, riffRanksResolved: [Int], anyLit: Bool = true, fxTieColumns: UInt8 = 0) -> [EuclidFooterState] {
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
        let fxTied = !isRest && riffStep >= 1 && riffStep <= 8 && (fxTieColumns >> UInt8(riffStep - 1)) & 1 != 0   // `riffStep` is the 1-based column the walk reads (after SHIFT)
        out[hs.bufIdx] = isRest ? .hitOnRest(riffStep: riffStep) : (fxTied ? .hitTied(riffStep: riffStep) : .hit(riffStep: riffStep))
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
func euclideousNextHitGapBeats(buf: [Bool], n: Int, dir: EuclidDir, sub: Double, spanBeats: Double, fromBeat: Double, cap: Int) -> Double {
    // LANES GRID (2026-10-18): a thin wrapper over the tick-based core form below (no restart grid; `spanBeats` is the pre-grid re-anchor).
    // The per-lane restart-mask parameters this used to take are gone — a restart is the grid's job now, and the Router calls the core form.
    guard !buf.isEmpty, n > 0, sub > 0, cap > 0 else { return sub }
    return euclideousNextHitGapBeats(buf: buf, n: n, dir: dir, cycleLen: euclidCycleLen(dir, n: n), sub: sub,
                                     tick: Int64((fromBeat / sub).rounded()), cap: cap, grid: .off, legacySpanBeats: spanBeats)
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
        if L.tiltResolved != 0 {
            // RHYTHM POLISH: a TILT-fine lane's cells are the step each hit STARTS in (the engine's), not the nearest step — cells only here, so nothing allocates.
            if L.tiltIsFine { euclidTiltPatternFine(&buf, pulses: k, steps: n, tilt: L.tiltResolved) }
            else { euclidTiltPattern(&buf, pulses: k, steps: n, tilt: L.tiltResolved) }
        }
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

// MARK: - HIT TIMING (RHYTHM POLISH ferry, 2026-10-22, §5) — continuous OFFSET and TILT
//
// A hit's TIME inside a pass is its step plus a fraction of a step: OFFSET's fractional part shifts every hit later by that fraction (in the control's own sense — on the bar, to the right), and TILT, when the lane has
// `tiltFine`, places each hit at its UNROUNDED position instead of the nearest step. Both are real-valued positions inside the lap, so they are worked out ONCE, here, in the lap's own TICK space (the order the engine plays
// the pattern in — BKW and PING-PONG mirror a position, and the shift follows the control, not the clock): every tick cell either holds a hit or doesn't (`cells`) and a hit has a `delay` ∈ [0,1) steps into its cell.
// Because a delay never leaves its cell, hits stay in time order, a pass is still a whole number of cells (a rhythm restart still lands on a cell boundary, so a hit can never be shifted past the restart that ends its
// pass — spec 5.2 holds by construction), and every ordinal / footer / strip / riff-walk reader that counts CELLS is unchanged. Only the readers of a hit's TIME (the Router's strike, the gap to the next hit, the TIE
// lookahead, the walk mirror's beat, the roll) read `EuclideousHitTiming`. A lane with no fraction and no fine TILT never reaches any of this: its cells are today's buffer, its timing `.none` — byte-identical.

/// TILT without the rounding: the same positions as `euclidTiltPattern` (a linear blend from the even spread toward fully packed), but each hit lands in cell `floor(target)` with `frac(target)` reported through
/// `micro(cell, fraction)` instead of being rounded to the nearest step. Distinct targets are ≥ 1 apart (the even spread is, and so is the packed one), so no two hits share a cell; the nudge is the same
/// deterministic guard as the rounded version's and only fires on floating-point noise. The in-step positions go out through `micro(cell, fraction)` (non-escaping, so nothing allocates).
func euclidTiltPatternFine(_ buf: inout [Bool], pulses k: Int, steps n: Int, tilt: Double, micro: (Int, Double) -> Void) {
    guard tilt != 0, k > 1, n > 1 else { return }
    var count = 0
    for i in 0..<n where i < buf.count && buf[i] { count += 1 }
    guard count == k else { return }   // a mismatched/empty buf (caller error) — leave untouched rather than guess
    let t = max(-1, min(1, tilt))
    for i in 0..<n where i < buf.count { buf[i] = false }
    for i in 0..<k {
        let evenPos = Double(i) / Double(k - 1) * Double(n - 1)
        let packedPos = t < 0 ? Double(i) : Double(n - k + i)
        var target = evenPos + abs(t) * (packedPos - evenPos)
        let nearest = target.rounded()
        if abs(target - nearest) < 1e-9 { target = nearest }   // an exact step stays exact (t = ±1, a full pattern…)
        var cell = max(0, min(n - 1, Int(target.rounded(.down))))
        var frac = max(0, min(1 - 1e-12, target - Double(cell)))
        while cell < buf.count && buf[cell] { cell = (cell + 1) % n; frac = 0 }   // bounded; only reachable through float noise
        if cell < buf.count { buf[cell] = true }
        micro(cell, frac)
    }
}
/// The cells alone (no in-step positions) — what the render thread's partner lookups and the display need.
func euclidTiltPatternFine(_ buf: inout [Bool], pulses k: Int, steps n: Int, tilt: Double) {
    euclidTiltPatternFine(&buf, pulses: k, steps: n, tilt: tilt, micro: { _, _ in })
}
/// `euclidRotateBuffer`'s twin for the per-cell in-step positions: the SAME cyclic shift, so a hit and its fraction move together.
func euclidRotateMicro(_ m: inout [Double], steps n: Int, rotation rot: Int) {
    guard n > 1, m.count >= n else { return }
    let r = ((rot % n) + n) % n
    guard r != 0 else { return }
    func reverse(_ lo: Int, _ hi: Int) {
        var l = lo, h = hi - 1
        while l < h { m.swapAt(l, h); l += 1; h -= 1 }
    }
    reverse(0, r); reverse(r, n); reverse(0, n)
}
/// A lane's finished pattern in BUFFER space — HITS/TILT/hand edits → OFFSET (rotate) → FLIP — with the TILT-fine in-step positions (`micro`, 0 everywhere else; FLIP clears them: the flipped hits sit on step starts).
/// The ONE builder behind the Router, the walk mirror, `euclideousBuildPatternInto` and the display, so the cells cannot drift apart. With `fine` false this is exactly the rounded pipeline the engine always ran.
@discardableResult
func euclideousHitPatternInto(pulses k: Int, steps n: Int, rotate: Int, tilt: Double, fine: Bool, customHits: [Bool]?, patternMiss: Bool,
                              cells: inout [Bool], micro: inout [Double]) -> Int {
    for i in 0..<n where i < micro.count { micro[i] = 0 }
    if let custom = customHits, !custom.isEmpty {
        for i in 0..<n { cells[i] = i < custom.count ? custom[i] : false }
    } else {
        euclidPatternInto(&cells, pulses: k, steps: n, rotation: 0)
        if tilt != 0 {
            if fine { euclidTiltPatternFine(&cells, pulses: k, steps: n, tilt: tilt, micro: { i, f in if i < micro.count { micro[i] = f } }) }
            else { euclidTiltPattern(&cells, pulses: k, steps: n, tilt: tilt) }
        }
    }
    euclidRotateBuffer(&cells, steps: n, rotation: rotate)
    euclidRotateMicro(&micro, steps: n, rotation: rotate)
    if patternMiss { for i in 0..<n { cells[i].toggle(); if i < micro.count { micro[i] = 0 } } }
    return n
}
func euclideousBuildHitPatternInto(_ L: EuclidLine, cells: inout [Bool], micro: inout [Double]) -> Int {
    let n = max(2, min(16, L.steps))
    return euclideousHitPatternInto(pulses: max(0, min(n, L.pulses)), steps: n, rotate: L.rotate, tilt: L.tiltResolved, fine: L.tiltIsFine,
                                    customHits: L.customHits, patternMiss: L.patternMissResolved, cells: &cells, micro: &micro)
}

/// Per-tick delays (steps into the tick's cell) of a lane's hits, in TICK space: `delay[raw]` for the hit read at tick `raw` (the engine's `raw`, 0..<cycleLen). Empty = no timing (every hit on its step).
struct EuclideousHitTiming: Equatable {
    var delay: [Double] = []
    static let none = EuclideousHitTiming()
    var isNone: Bool { delay.isEmpty }
    @inline(__always) func delaySteps(raw: Int) -> Double { raw >= 0 && raw < delay.count ? delay[raw] : 0 }
}

/// BUFFER space → TICK space. Each hit of the buffer sits at `b + micro[b]` steps; `fraction` (OFFSET's fractional part, plus a FOLLOW partner's) pushes it right on the bar and the position wraps around the step
/// count. A real position is then mapped to the lap's tick axis the way the direction reads the buffer — FWD as is; BKW mirrored (`n−1−x`); PING-PONG once forward and once mirrored (`2n−1−x`, the engine's own turn:
/// each end sounds on two consecutive ticks) — wrapped into `0..<cycleLen`, and split into the tick cell (`floor`) and the delay in it (`frac`). With no fraction and no micro this reproduces
/// `buf[euclidReadIndex(raw)]` exactly, with delay 0. A hit whose cell is already taken (only a PING-PONG turn, or float noise) moves to the next free cell on its step start — never dropped, never doubled.
/// Writes `outCells[0..<cycleLen]` / `outDelay[0..<cycleLen]` (both ≥ 32 long) and returns `cycleLen`.
@discardableResult
func euclideousHitLayoutInto(cells: [Bool], micro: [Double], fraction f: Double, n: Int, dir: EuclidDir,
                             outCells: inout [Bool], outDelay: inout [Double]) -> Int {
    let cl = euclidCycleLen(dir, n: n)
    for i in 0..<cl { outCells[i] = false; outDelay[i] = 0 }
    let nD = Double(n), clD = Double(cl)
    func place(_ u0: Double) {
        var u = u0 - clD * (u0 / clD).rounded(.down)            // wrap into 0..<cycleLen
        let nearest = u.rounded()
        if abs(u - nearest) < 1e-9 { u = nearest }
        if u >= clD { u -= clD }
        var cell = max(0, min(cl - 1, Int(u.rounded(.down))))
        var d = max(0, min(1 - 1e-12, u - Double(cell)))
        var guardCount = 0
        while outCells[cell] && guardCount < cl { cell = (cell + 1) % cl; d = 0; guardCount += 1 }
        outCells[cell] = true
        outDelay[cell] = d
    }
    for b in 0..<n where b < cells.count && cells[b] {
        var x = Double(b) + (b < micro.count ? micro[b] : 0) + f
        while x >= nD { x -= nD }
        switch dir {
        case .fwd: place(x)
        case .bkw: place(nD - 1 - x)
        case .pingpong: place(x); place(2 * nD - 1 - x)
        }
    }
    return cl
}
/// The cells a lane's step boxes should show: each hit in the BOX its start time falls in (RHYTHM POLISH §3.1) — the tick cell mapped back through the direction. Same as the buffer for FWD; BKW / PING-PONG may move a
/// hit one box when a fraction is set (a PING-PONG box lights if either of its two visits holds a hit).
func euclideousHitBoxes(layoutCells: [Bool], n: Int, dir: EuclidDir) -> [Bool] {
    var out = [Bool](repeating: false, count: n)
    for raw in 0..<euclidCycleLen(dir, n: n) where raw < layoutCells.count && layoutCells[raw] { out[euclidReadIndex(raw, n: n, dir: dir)] = true }
    return out
}
/// §8.3 — a rhythm chain's own restart beats inside `[windowStart, windowStart + windowBeats)`, walked
/// forward via `euclideousNextRhythmRestart` from just before the window (the LANES mute window's read-only
/// marks). FREE gives none — nothing to mark.
func euclideousChainRhythmMarkBeats(chain: EuclideousRestartChain, barBeats: Double, windowStart: Double, windowBeats: Double) -> [Double] {
    guard !chain.isFree, barBeats > 0, windowBeats > 0 else { return [] }
    var out: [Double] = []
    var b = windowStart - Double(max(1, chain.total)) * barBeats - 1   // safely before the window
    var guardCount = 0
    while guardCount < 4096 {
        guard let next = euclideousNextRhythmRestart(after: b, barBeats: barBeats, chain: chain) else { break }
        if next >= windowStart + windowBeats - 1e-9 { break }
        if next >= windowStart - 1e-9 { out.append(next) }
        b = next
        guardCount += 1
    }
    return out
}
/// §8.3 — a melody chain's own restarting-pass START beats inside the window, via `euclideousPassIndex`/
/// `Start` and `euclideousIsMelodyChainRestartPass`. FREE gives none.
func euclideousChainMelodyMarkBeats(melodyChain: EuclideousRestartChain, rhythmChain: EuclideousRestartChain, barBeats: Double, lapBeats: Double, windowStart: Double, windowBeats: Double) -> [Double] {
    guard !melodyChain.isFree, lapBeats > 0, windowBeats > 0 else { return [] }
    let qStart = Int64((euclideousPassIndex(beat: windowStart, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythmChain)) - 1)
    var out: [Double] = []
    var q = qStart
    var guardCount = 0
    while guardCount < 4096 {
        let start = euclideousPassStart(q, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythmChain)
        if start >= windowStart + windowBeats - 1e-9 { break }
        if start >= windowStart - 1e-9,
           euclideousIsMelodyChainRestartPass(beat: start, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythmChain, melodyChain: melodyChain) {
            out.append(start)
        }
        q += 1
        guardCount += 1
    }
    return out
}
/// §5.6/§6.2 — "a rhythm chain 'changes nothing' when it isn't FREE and every restart lands on a lap start
/// of the free-running lane: every running total × barBeats, and C × barBeats, is a whole multiple of
/// lapBeats (within the epsilon)." Drives the restart editor's amber hint line, nowhere in the engine
/// itself (§5.6: "the engine doesn't special-case it").
func euclideousRhythmChainChangesNothing(_ chain: EuclideousRestartChain, barBeats: Double, lapBeats: Double) -> Bool {
    guard !chain.isFree, lapBeats > 0 else { return false }
    let eps = 1e-6
    func isWholeMultiple(_ beats: Double) -> Bool { let q = beats / lapBeats; return abs(q.rounded() - q) < eps }
    guard isWholeMultiple(Double(chain.total) * barBeats) else { return false }
    for i in 0..<chain.count where !isWholeMultiple(Double(chain.runningTotal(i)) * barBeats) { return false }
    return true
}
/// §6.1/§6.2 — a chain's own display text ("2·1·1" or "FREE"), the ONE formatting both the tile and the
/// editor read, so they can't drift. U+00B7 MIDDLE DOT joins links.
func euclideousRestartChainText(_ chain: EuclideousRestartChain) -> String {
    chain.isFree ? "FREE" : chain.links.map { String($0) }.joined(separator: "\u{B7}")
}
/// §13.4 — a restart tile's VoiceOver label.
func euclideousRestartTileAccessibleLabel(name: String, chain: EuclideousRestartChain, unitSingular: String, unitPlural: String) -> String {
    let cap = name.capitalized
    if chain.isFree { return "\(cap) restarts, free" }
    if chain.isSingleLink1 { return "\(cap) restarts every \(unitSingular)" }
    if chain.count == 1 { return "\(cap) restarts every \(chain.link(0)) \(unitPlural)" }
    let parts = chain.links.map { "\($0)" }
    let joined = "\(parts[0]) \(unitPlural), then " + parts.dropFirst().joined(separator: ", then ")
    return "\(cap) restarts after \(joined), repeating"
}
/// §6.2 — the restart editor's 16-cell timeline for one chain, from `windowStartUnit` (a bar or pass number,
/// whichever this chain counts in). Cell i is a mark (a restart falls there) and which of the two shades it
/// draws (true = 26%, alternating at each mark after the window's own first cell, which always starts high).
func euclideousRestartTimelineCells(chain: EuclideousRestartChain, windowStartUnit: Int) -> [(isMark: Bool, shadeHigh: Bool)] {
    guard !chain.isFree else { return Array(repeating: (false, true), count: 16) }
    let total = max(1, chain.total)
    var out: [(isMark: Bool, shadeHigh: Bool)] = []
    var shadeHigh = true
    for i in 0..<16 {
        let u = windowStartUnit + i
        let r = ((u % total) + total) % total
        let isMark = (0..<chain.count).contains { chain.runningTotal($0) == r }
        if isMark, i > 0 { shadeHigh.toggle() }
        out.append((isMark, shadeHigh))
    }
    return out
}
/// RESTART CHAINS ferry §3.2 — the STEPS picker's preview pattern for hypothetical length `n`: pure Euclid
/// at `min(hitsRequested, n)` hits, the lane's own TILT, offset `min(offsetRequested, n-1)` and INV, built
/// with the SAME functions the engine uses (`euclidPatternInto` at rotation 0, `euclidTiltPattern`,
/// `euclidRotateBuffer`, then INV). Never reads `customHits` — only the CURRENT length's own cell shows the
/// hand-edited pattern (§3.2's own distinction); every other length's preview is always pure Euclid.
func euclideousStepsPickerPreview(_ line: EuclidLine, length n: Int) -> [Bool] {
    let steps = max(2, min(16, n))
    let hits = max(0, min(steps, line.hitsRequestedResolved))
    let offset = max(0, min(steps - 1, line.offsetRequestedResolved))
    var buf = [Bool](repeating: false, count: steps)
    euclidPatternInto(&buf, pulses: hits, steps: steps, rotation: 0)
    if line.tiltResolved != 0 { euclidTiltPattern(&buf, pulses: hits, steps: steps, tilt: line.tiltResolved) }
    // OFFSET's own stored convention is `rotate = (n - offset) mod n` (`euclideousSliderRange`/`Commit`'s
    // mirror) — applying it the same way here keeps the preview consistent with the real slider's own drag.
    let rotate = (steps - offset) % steps
    euclidRotateBuffer(&buf, steps: steps, rotation: rotate)
    if line.patternMissResolved { for i in 0..<steps { buf[i].toggle() } }
    return buf
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
/// The restart chains a lane's own fields resolve to — `.off` (both FREE) until `migrateRestartChains` (main thread) has pinned real ones, exactly as `Router.runEuclidLine` and the UI's
/// walk mirror resolve them (`cycleLen` is the lane's lap in ticks, `sub` its tick in beats). Allocation-free (`EuclideousRestartChain.from` packs into a UInt32).
func euclideousLaneRestartChains(for line: EuclidLine, cycleLen: Int, sub: Double, beatsPerBar: Double) -> EuclideousLaneRestartChains {
    line.usesRestartChains
        ? EuclideousLaneRestartChains(rhythm: .from(line.restartRhythmBars ?? []), melody: .from(line.restartMelodyPasses ?? []), barBeats: beatsPerBar, lapBeats: Double(cycleLen) * sub)
        : .off
}
/// §6's shared primitive for SHADOW and AVOID: the (rank, note) a lane with the given pattern/riff params
/// is sounding AT this exact beat (`epsilonBeats` given — AVOID's coincidence check) or at its most recent
/// real hit AT OR BEFORE this beat (`epsilonBeats` nil — SHADOW's "the note under the partner's walk arrow
/// at that moment," which stays wherever it last struck between hits, mirroring the UI's own sticky
/// marker). Resolves rank through the SAME INVERT→TRANSPOSE→source-pool pipeline `runEuclidLine`'s own
/// riff layer uses — MASK (MIRROR/LEAP/CLIMB) is deliberately NOT applied, matching §6's own literal list
/// ("after the partner's INV, TRANS and riff octave" — no mention of MASK). Bounded backward scan (same
/// shape as this file's own forward TIE-lookahead idiom, just run in reverse) — no allocation, pure.
///
/// THE PARTNER'S WALK IS THE ENGINE'S OWN (fixed 2026-10-20). This used to re-derive the partner's riff ordinal by hand from the retired LOCK model — it knew nothing of ADVANCE EVERY, the
/// RHYTHM / MELODY restart chains or the melody origin, so a SHADOW / AVOID lane whose partner had EVERY ≥ 2 or a restart chain followed a different column from the one the partner actually
/// plays. It now asks the same two functions the Router, the TIE lookahead and the UI's walk mirror ask: `euclideousLaneChainTick` (the tick's hit / ordinal, from the partner's own chains,
/// absolute tick) and `euclideousRiffColumn` (EVERY, direction, STRIDE, SHIFT) — so "the note under the partner's arrow" is, by construction, what its walk reads. `legacySpanBeats` is the
/// machine-wide re-anchor (`ladderSpanBeats`), used only while the partner has no chain; the partner's own chains come from its own fields (`beatsPerBar` sizes their bar).
/// STILL NOT FOLLOWED (disclosed): a partner that is itself FOLLOWing a third lane (its pattern here is its own), the partner's WITH / GAPS strike filter, and its ON REST modes
/// (§6's own rule stands: a hit on a rest — REPEAT / TIE / FILL included — leaves the shadow resting).
func euclideousListenPartnerNoteAt(
    buf: [Bool], n: Int, dir: EuclidDir, rateBeats: Double, legacySpanBeats: Double, atBeat: Double, beatsPerBar: Double,
    epsilonBeats: Double?, line: EuclidLine, ranks: [Int], poolCount: Int, poolAsc: (Int) -> Int
) -> (rank: Int, note: Int)? {
    guard n > 0, rateBeats > 0, !buf.isEmpty else { return nil }
    let cycleLen = euclidCycleLen(dir, n: n)
    let chains = euclideousLaneRestartChains(for: line, cycleLen: cycleLen, sub: rateBeats, beatsPerBar: beatsPerBar)
    let advanceStep = line.riffAdvanceStepResolved
    let localTExact = atBeat / rateBeats
    var t: Int64
    if let eps = epsilonBeats {
        let nearest = localTExact.rounded()
        guard abs(nearest * rateBeats - atBeat) <= eps else { return nil }
        t = Int64(nearest)
    } else {
        t = Int64(localTExact.rounded(.down))
    }
    let startT = t
    var scanned = 0
    let cap = cycleLen * 4
    let seed = UInt64(bitPattern: Int64(line.riffDirSeedResolved))
    while scanned < cap {
        let info = euclideousLaneChainTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: rateBeats, tick: t, chains: chains,
                                           legacySpanBeats: legacySpanBeats, advanceStep: advanceStep)
        if info.rawIsHit {
            if epsilonBeats != nil && t != startT { return nil }   // AVOID's coincidence check never falls back to an earlier hit — only an exact match counts
            let playedStep = euclideousRiffColumn(ordinal: info.advOrd, every: line.riffAdvanceEveryResolved, direction: line.euclideousRiffDirResolved,
                                                  length: line.riffLengthResolved, stride: line.riffStrideResolved, shift: line.riffRotateResolved, seed: seed)
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
    var spanBeats: Double = 0       // machine-wide RESET span in beats (the pre-grid re-anchor, used only while the grid has no mark); 0 = free-run
    /// The lane's restart grid in its own ticks (LANES GRID, 2026-10-18) — kept ONLY for the FX tab's own closed-form
    /// pass index (`euclideousFXPassIndex`, out of the restart-chains ferry's scope); every other reader below uses `chains`.
    var grid: EuclideousLaneRestartGrid = .off
    /// RESTART CHAINS (ferry 2026-10-19): the lane's resolved rhythm/melody chains — what the walk mirror, the roll's
    /// gap/tie lookahead and the lap-start baseline actually read now. `.off` (both FREE) is the safe pre-migration
    /// default — the same one `Router.swift` falls back to during the brief pre-first-resync window.
    var chains: EuclideousLaneRestartChains = .off
    /// The lane's mute grid (cells + cell length in beats), for the roll and the lane card. 0 length = always audible.
    var muteCells: UInt16 = 0xFFFF
    var muteUnitBeats: Double = 0
    /// LISTEN WITH / GAPS: when set, a raw pattern hit only STRIKES if it passes the partner coincidence test. nil = no filter.
    var listen: EuclideousWalkListenFilter? = nil
    var riffDir: RiffDir = .forward
    var stride: Int = 1
    var length: Int = 8
    var rotate: Int = 0
    var locked: Bool = false        // LOCK
    var advanceStep: Bool = false   // ADV STEP
    var seed: UInt64 = 0
    var every: Int = 1              // RIFF WALK ferry §5.2: ADVANCE EVERY — 1 is today's behaviour
    /// SWING: the engine ticks in MUSICAL beats and maps each tick's onset to real time through `realOf`
    /// (`a` = swing% / 50, `swingStepBeats` = the scene's step beats). `a == 1` (50%) is the identity.
    var swingA: Double = 1
    var swingStepBeats: Double = 0.5
    /// The roll (LANES GRID §3) draws the lane's riff contour and gate lengths, so the config also carries what the roll reads beyond the
    /// walk itself: whether the riff is on, the riff layer's GATE, ON REST, and the rank transforms the Router applies (INVERT, TRANSPOSE).
    var riffOn: Bool = true
    var gate: Double = 0.9
    var onRest: EuclidRiffOnRest = .skip
    var invert: Bool = false
    var transpose: Int = 0
    // FX TAB (2026-10-18): what the roll needs to call the SAME per-hit function the Router calls — the page-level FX rows, this lane's index, whether the
    // lane actually plays its riff (riff on and not SHADOWing), and the scene grid's `cyc` (the RATCH beat-width cap measures against it, as the mask's did).
    var fx: EuclideousFX = EuclideousFX()
    var lane: Int = 0
    var playsRiff: Bool = true
    var cyc: Double = 4
    /// RHYTHM POLISH (2026-10-22): the hits' delays inside their tick cells (tick space) — `.none` for a lane with no fraction and no fine TILT. When it is set, `buf` / `n` / `dir` above are the lane's TICK-SPACE
    /// layout (`euclideousHitLayoutInto`: n = the lap's tick count, dir = FWD) — exactly what the Router reads — so every engine-mirroring reader below sees the cells the engine plays.
    var timing: EuclideousHitTiming = .none
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
    guard let e = euclideousEffectiveHitPattern(lane: lane, lines: lines, defaultRateBeats: defaultRateBeats) else { return nil }
    return (e.buf, e.n, e.followsPartner, e.rateBeats)
}
/// `euclideousEffectivePattern` plus the lane's hit TIMING inputs (RHYTHM POLISH, 2026-10-22): the buffer-space in-step positions of a fine TILT and the total OFFSET fraction (a FOLLOW lane adds its partner's, whose
/// own offset already rotates the shape it inherits). The cells are exactly the ones the Router builds.
struct EuclideousEffectiveHitPattern {
    var buf: [Bool]; var n: Int; var followsPartner: Bool; var rateBeats: Double
    var micro: [Double]; var fraction: Double
    var hasTiming: Bool { fraction > 0 || micro.contains { $0 != 0 } }
}
func euclideousEffectiveHitPattern(lane: Int, lines: [EuclidLine], defaultRateBeats: Double = 0.25) -> EuclideousEffectiveHitPattern? {
    guard lane >= 0, lane < lines.count else { return nil }
    let L = lines[lane]
    var cells = [Bool](repeating: false, count: 16), micro = [Double](repeating: 0, count: 16)
    if let followIdx = euclideousFollowPartner(lane: lane, lines: lines) {
        // Mirrors Router: the partner's finished pattern + step count (+ its in-step positions and fraction), then THIS lane's own OFFSET / FLIP on top.
        let n = euclideousBuildHitPatternInto(lines[followIdx], cells: &cells, micro: &micro)
        euclidRotateBuffer(&cells, steps: n, rotation: L.rotate)
        euclidRotateMicro(&micro, steps: n, rotation: L.rotate)
        if L.patternMissResolved { for i in 0..<n { cells[i].toggle(); micro[i] = 0 } }
        return EuclideousEffectiveHitPattern(buf: cells, n: n, followsPartner: true, rateBeats: (lines[followIdx].rate?.beats ?? defaultRateBeats) * L.listenFollowRatioResolved,
                                             micro: micro, fraction: lines[followIdx].offsetFractionResolved + L.offsetFractionResolved)
    }
    let n = euclideousBuildHitPatternInto(L, cells: &cells, micro: &micro)
    return EuclideousEffectiveHitPattern(buf: cells, n: n, followsPartner: false, rateBeats: L.rate?.beats ?? defaultRateBeats, micro: micro, fraction: L.offsetFractionResolved)
}

func euclideousWalkLaneConfig(lane: Int, lines: [EuclidLine], cyc: Double, resetSpanBars: Int,
                              lanesSeqRate: EuclideousSeqRate, lanesSeqLen: Int, lanesSeqOn: Bool = false, lanesSeqCells: [Bool]? = nil,
                              fx: EuclideousFX = EuclideousFX(),
                              defaultRateBeats: Double = 0.25, swingPercent: Double = 50, stepBeats: Double = 0.5,
                              beatsPerBar: Double = 4, tempo: Double = 120) -> EuclideousWalkLaneConfig? {
    guard lane >= 0, lane < lines.count else { return nil }
    let L = lines[lane]
    let followIdx = L.listenRhythmPartnerResolved   // the rhythm partner of ANY listen mode (WITH/GAPS use it below)
    guard let eff = euclideousEffectiveHitPattern(lane: lane, lines: lines, defaultRateBeats: defaultRateBeats) else { return nil }
    // RHYTHM POLISH: a lane with timing (a fraction and/or a fine TILT) is read in TICK space — the layout the Router builds — with its per-tick delays; any other lane keeps the buffer it always had.
    var buf = eff.buf, n = eff.n
    var cfgDir = L.directionResolved
    var timing = EuclideousHitTiming.none
    if eff.hasTiming {
        var tc = [Bool](repeating: false, count: 32), td = [Double](repeating: 0, count: 32)
        let cl = euclideousHitLayoutInto(cells: eff.buf, micro: eff.micro, fraction: eff.fraction, n: eff.n, dir: L.directionResolved, outCells: &tc, outDelay: &td)
        buf = Array(tc[0..<cl]); n = cl; cfgDir = .fwd
        timing = EuclideousHitTiming(delay: Array(td[0..<cl]))
    }
    let sub = eff.rateBeats
    // LANES GRID (2026-10-18): the lane's mute grid and restart masks, resolved EXACTLY as `Router.runEuclidLine` resolves them — from the
    // lane's own fields, or migrated from the old sequencer + reset against THIS lane's step and lap and the host's real bar.
    let cycleLen = euclidCycleLen(cfgDir, n: n)
    let g = euclideousLaneGridResolved(line: L, lane: lane, legacyOn: lanesSeqOn, legacyRate: lanesSeqRate, legacyLen: lanesSeqLen,
                                       legacyCells: lanesSeqCells ?? [Bool](repeating: true, count: 32), stepBeats: sub,
                                       passBeats: Double(cycleLen) * sub, beatsPerBar: beatsPerBar)
    let grid = euclideousLaneRestartGrid(g, cycleLen: cycleLen)
    let ladderSpan = resetSpanBars > 0 ? Double(resetSpanBars) * cyc : 0
    let spanBeats = ladderSpan
    // RESTART CHAINS (ferry 2026-10-19): `.off` (both FREE) during the brief pre-first-resync window before
    // `AudioUnitViewController`'s main-thread migration pins real chains — the SAME safe default the Router falls
    // back to, so the mirror and the engine never disagree even in that window.
    let passBeats = Double(cycleLen) * sub
    let chains: EuclideousLaneRestartChains = L.usesRestartChains
        ? EuclideousLaneRestartChains(rhythm: .from(L.restartRhythmBars ?? []), melody: .from(L.restartMelodyPasses ?? []),
                                      barBeats: beatsPerBar, lapBeats: passBeats)
        : .off
    // LISTEN WITH / GAPS: the engine's coincidence lookup uses ITS `spanBeats` — one full LANES lap when a mask is set,
    // else the bars span — which differs from the mirror's own reset origin above, so it is captured separately.
    var listen: EuclideousWalkListenFilter? = nil
    if let mode = L.listenRhythmMode, mode != .follow, followIdx >= 0, followIdx < lines.count {
        let partner = lines[followIdx]
        let pb = euclideousBuildPattern(partner)
        let engineSpan = grid.isActive ? Double(16 * grid.unitTicks) * sub : ladderSpan
        listen = EuclideousWalkListenFilter(requireCoincide: mode == .with, buf: pb.buf, n: pb.n, dir: partner.directionResolved,
                                            rateBeats: partner.rate?.beats ?? defaultRateBeats, spanBeats: engineSpan,
                                            epsilonBeats: 0.001 * (max(1, tempo) / 60.0))
    }
    return EuclideousWalkLaneConfig(buf: buf, n: n, dir: cfgDir, sub: sub, spanBeats: spanBeats,
                                    grid: grid, chains: chains, muteCells: g.muteCells,
                                    muteUnitBeats: g.muteUnit.beats(stepBeats: sub, passBeats: Double(cycleLen) * sub), listen: listen,
                                    riffDir: L.euclideousRiffDirResolved, stride: L.riffStrideResolved, length: L.riffLengthResolved,
                                    rotate: L.riffRotateResolved, locked: L.riffLockResolved, advanceStep: L.riffAdvanceStepResolved,
                                    seed: UInt64(bitPattern: Int64(L.riffDirSeedResolved)), every: L.riffAdvanceEveryResolved,
                                    swingA: min(75, max(50, swingPercent)) / 50.0, swingStepBeats: max(0.03125, stepBeats),
                                    riffOn: L.riffOnResolved, gate: L.gateResolved, onRest: L.riffOnRestResolved,
                                    invert: L.riffInvertResolved, transpose: L.melodyTransposeResolved,
                                    fx: fx, lane: lane, playsRiff: euclideousLanePlaysRiff(L), cyc: cyc, timing: timing)
}
/// A tick's REAL onset beat — what the note-on is scheduled at (swing-warped), the time a tag must arrive.
func euclideousWalkRealBeat(_ c: EuclideousWalkLaneConfig, tick: Int64) -> Double {
    // RHYTHM POLISH: a hit plays its delay into the tick's cell — the beat a tag must arrive at.
    var steps = Double(tick)
    if !c.timing.isNone {
        let ph = euclideousLaneChainPhase(buf: c.buf, n: c.n, dir: c.dir, cycleLen: euclidCycleLen(c.dir, n: c.n), sub: c.sub, tick: tick, chains: c.chains, legacySpanBeats: c.spanBeats)
        if ph.rawIsHit { steps += c.timing.delaySteps(raw: ph.raw) }
    }
    let m = steps * c.sub
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
    // The mirror IS the engine's per-tick core (RESTART CHAINS, 2026-10-19) — the same call `Router.runEuclidLine` makes — so a tag, a
    // prediction or a roll bar can no longer drift from what sounds by anything but the clock itself. No `locked:` — a melody
    // chain of exactly [1] reproduces old LOCK's own re-anchoring with no special-casing (§4.7).
    let info = euclideousLaneChainTick(buf: c.buf, n: c.n, dir: c.dir, cycleLen: euclidCycleLen(c.dir, n: c.n), sub: c.sub, tick: tick,
                                       chains: c.chains, legacySpanBeats: c.spanBeats, advanceStep: c.advanceStep)
    // WITH / GAPS: the engine folds the partner check into the STRIKE decision only — `advOrd` still counts every raw hit of the
    // lane's own pattern ("the lane keeps its own rhythm"), so a filtered tick advances the ordinal silently and the next strike
    // lands further along the walk.
    var strikes = info.rawIsHit
    if info.rawIsHit, let f = c.listen {
        let tickBeat = Double(tick) * c.sub
        let coincides = euclideousListenPartnerHasHitAt(buf: f.buf, n: f.n, dir: f.dir, rateBeats: f.rateBeats, spanBeats: f.spanBeats,
                                                         atBeat: tickBeat, epsilonBeats: f.epsilonBeats)
        strikes = f.requireCoincide ? coincides : !coincides
    }
    return EuclideousWalkTick(isHit: info.rawIsHit, strikes: strikes, advOrd: info.advOrd, playedStep: euclideousWalkStep(c, ord: info.advOrd))
}
/// The riff step (0-based, post-SHIFT) the walk lands on at ordinal `ord` — RIFF WALK ferry §5.2: routed
/// through `euclideousRiffColumn` (ordinal -> walk step w = floor(ord/EVERY) -> column), the ONE place
/// this mirror turns an ordinal into a column, so it can't drift from the Router's own formula.
func euclideousWalkStep(_ c: EuclideousWalkLaneConfig, ord: Int64) -> Int {
    euclideousRiffColumn(ordinal: ord, every: c.every, direction: c.riffDir, length: max(1, c.length), stride: c.stride, shift: c.rotate, seed: c.seed)
}
/// The walk position BEFORE SHIFT — the axis "up the steps / down the steps" is measured on. Also routed
/// through the walk step (not the raw ordinal), so "facing" agrees with what the walk actually did between
/// two hits of the same EVERY group (no movement, not a hypothetical raw-ordinal one).
private func euclideousWalkPos(_ c: EuclideousWalkLaneConfig, ord: Int64) -> Int {
    riffStepAt(c.riffDir, raw: Int(euclideousRiffWalkStep(ordinal: ord, every: c.every)) * c.stride, steps: max(1, c.length), seed: c.seed)
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
/// RIFF PANEL ferry (2026-10-19) §4.1/§4.8: where a TIE-on-rest lane's arrow STAYS — the column, row and ordinal of the nearest earlier hit that really
/// played a note (the tied note is still sounding through the rest). Nil unless the seat is a rest under ON REST = TIE with a note behind it.
struct EuclideousTieStay: Equatable { var step: Int; var rank: Int; var ordinal: Int64 }
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
    /// RIFF PANEL ferry: the ordinal (`advOrd`) of the hit the tag is seated on — nil for a stopped/static seat (the caller supplies the polled ordinal).
    var seatOrdinal: Int64? = nil
    var tieStay: EuclideousTieStay? = nil
}

/// `ranks` is the playing riff's rank per step (0 = rest). `polledStep` is the lane's live step (the SAME value
/// the RIFF-tab thumbnail reads; < 0 = not started). `running` = transport playing AND the lane playing. Returns
/// nil when there is nothing to draw (not started, or the riff has no notes on the steps the walk visits).
func euclideousWalkTagPlan(cfg: EuclideousWalkLaneConfig, ranks: [Int], beat: Double, secondsPerBeat spb: Double,
                           polledStep: Int, running: Bool, polledOrdinal: Int64? = nil) -> EuclideousWalkTagPlan? {
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
        // TIE-on-rest stay-put for a static seat: walk the polled ordinal backward to the nearest earlier note.
        var stay: EuclideousTieStay? = nil
        if rest, cfg.onRest == .tie, let po = polledOrdinal {
            for j in 1...(2 * len + 2) {
                let o2 = po - Int64(j)
                guard o2 >= 0 else { break }
                let col = euclideousWalkStep(cfg, ord: o2)
                let r = rankAt(col)
                if r >= 1 { stay = EuclideousTieStay(step: col, rank: r, ordinal: o2); break }
            }
        }
        return EuclideousWalkTagPlan(seatStep: step, seatRank: rank, seatIsRest: rest, facingRight: right, turned: false, dest: nil,
                                     isWrap: false, isReset: false, landedSeconds: nil, nextSeconds: nil, landedTick: nil,
                                     visitedMin: vis.min, visitedMax: vis.max, seatOrdinal: polledOrdinal, tieStay: stay)
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
    // TIE-on-rest stay-put (RIFF PANEL ferry §4.1/§4.8): the nearest EARLIER hit that read a note — among the lane's recent striking hits, else the nearest
    // note behind in walk order — is where the arrow stays; its ordinal gives the heading.
    var stay: EuclideousTieStay? = nil
    if seatIsRest, cfg.onRest == .tie {
        for t in scan.prev.dropFirst() {
            let w = euclideousWalkTick(cfg, tick: t)
            let r = rankAt(w.playedStep)
            if r >= 1 { stay = EuclideousTieStay(step: w.playedStep, rank: r, ordinal: w.advOrd); break }
        }
        if stay == nil {
            for j in 1...(2 * len + 2) {
                let o2 = tP.advOrd - Int64(j)
                guard o2 >= 0 else { break }
                let col = euclideousWalkStep(cfg, ord: o2)
                let r = rankAt(col)
                if r >= 1 { stay = EuclideousTieStay(step: col, rank: r, ordinal: o2); break }
            }
        }
    }
    return EuclideousWalkTagPlan(seatStep: seatStep, seatRank: seatRank, seatIsRest: seatIsRest, facingRight: facingRight,
                                 turned: prevFacing != facingRight, dest: dest, isWrap: isWrap, isReset: isReset,
                                 landedSeconds: secP, nextSeconds: secH, landedTick: pTick,
                                 visitedMin: vis.min, visitedMax: vis.max, seatOrdinal: tP.advOrd, tieStay: stay)
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

enum EuclideousOutputCue: Equatable { case none, dim }
enum EuclideousOutputCueMode { case pulse, trace }
/// What each LANE CARD shows for output `output` (RESTART CHAINS ferry §10: the RING half of this moved to
/// `euclideousOutputRingTargets`, below — the lane cards no longer have OUT circles to ring, §10.4). TRACE
/// (while held) dims every lane that is NOT routed (so with no routed lane all four dim, §10.3, unchanged);
/// PULSE leaves every lane card alone.
func euclideousOutputCues(output: Int, laneMasks: [UInt8], mode: EuclideousOutputCueMode) -> [EuclideousOutputCue] {
    (0..<4).map { lane in
        let routed = lane < laneMasks.count && (laneMasks[lane] >> UInt8(output)) & 1 != 0
        if routed { return .none }
        return mode == .trace ? .dim : .none
    }
}
/// §10.2/§10.3 — where the ring for output `output` goes, PULSE or TRACE alike: one ring per routed lane's
/// OWN MIX OUT button when the bottom-right panel is showing MIX; otherwise ONE ring around the MIX tab
/// itself (drawn once, however many lanes are routed) — never both. No lane routed to `output` ⇒ no ring at
/// all (§10.2's own "if no lane is routed to X, there is no ring"); a layout where the panel isn't on screen
/// ⇒ no ring either (§10.5 — the caller simply never calls this when the panel is absent).
enum EuclideousOutputRingTarget: Equatable { case mixOutButton(lane: Int), mixTab }
func euclideousOutputRingTargets(output: Int, laneMasks: [UInt8], panelShowsMix: Bool) -> [EuclideousOutputRingTarget] {
    let routedLanes = (0..<4).filter { lane in lane < laneMasks.count && (laneMasks[lane] >> UInt8(output)) & 1 != 0 }
    guard !routedLanes.isEmpty else { return [] }
    return panelShowsMix ? routedLanes.map { .mixOutButton(lane: $0) } : [.mixTab]
}

// ── ring flare ──────────────────────────────────────────────────────────────────────────────────────

/// The OLD comet-bar flare windows, in LANE STEPS since the strike — now read ONLY by the regular BUILD-page EUCLID editor's comet bar (no strike feed there). Every Euclideous strike effect uses PULSE's velocity-scaled
/// envelopes instead (`euclideousPulseEnvelopes`, 2026-10-20): the header rings, riff arrows and rails, the FX flash and the NOTES key glow no longer read these.
let euclideousFlareAfterglowSteps: Double = 1.5
let euclideousFlareBurstSteps: Double = 0.35

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
    /// The output rings' CANVAS stays at its NATURAL size (fed to `EuclideousOutputRing`'s own `width`/`height`) —
    /// shrinking the view's own frame instead of scaling the finished render clips the hardcoded radius-17 circle
    /// before the scale ever applies (the exact hazard `EuclideousSettingsSheet.mainOutRow` already worked around
    /// with `.scaleEffect` + a reclaiming `.frame`). `ringPitch`/`compactRingPitch` are the POST-scale LAYOUT
    /// footprint every other header formula reads; the call site applies `.scaleEffect(outputRingScale)` then
    /// reclaims exactly this width/height.
    static let outputRingScale: CGFloat = 0.75   // Paul, 2026-10-20: output emitter toggles to 75% of their original size
    static let ringNaturalPitch: CGFloat = 44, compactRingNaturalPitch: CGFloat = 40
    static let ringPitch: CGFloat = ringNaturalPitch * outputRingScale, compactRingPitch: CGFloat = compactRingNaturalPitch * outputRingScale
    static let markSize: CGFloat = 13
    static let monoAdvance: CGFloat = 0.6          // em — the page's monospaced advance estimate
    static let wordmarkChars = 8, wordmarkSize: CGFloat = 11, wordmarkTracking: CGFloat = 0.16
    static let captionChars = 3, captionSize: CGFloat = 9, captionTracking: CGFloat = 0.14
    static let segmentWidths: [CGFloat] = [66, 70, 40]
    static let segmentInset: CGFloat = 4
    static var segmentedWidth: CGFloat { segmentWidths.reduce(0, +) + segmentInset * 2 }   // 184
    static let keyPillWidth: CGFloat = 120
    // HOLD/LATCH (Paul 2026-10-20): two fixed-width chips after the key pill, same "nothing moves when the
    // selection changes" shape as `segmentWidths` above — chip 0 = HOLD (4 chars), chip 1 = LATCH (5 chars).
    static let holdLatchChipWidths: [CGFloat] = [48, 54]
    static var holdLatchWidth: CGFloat { holdLatchChipWidths.reduce(0, +) + sp4 }   // 2 chips + the gap between them
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
    // RANDOM MODE ferry §2.2: the dice sits sp8 after redo — one more target + one more gap than before. LANE LOCK ferry §2.2: the padlock sits sp8 after the dice — once more (+52 at 44, +44 at the compact 36).
    let brand = M.markSize + M.sp8 + (compact ? 0 : wordmarkW + M.sp16) + 4 * t + 2 * M.sp8
    let lead = compact ? 0 : captionW + M.sp4
    let outputs = lead + 4 * (compact ? M.compactRingPitch : M.ringPitch)
    // UTILITIES is 3 icons (presets · SWING, 2026-10-17 · settings), one `t`-wide touch target each.
    return EuclideousHeaderGroupWidths(brand: brand, outputs: outputs, notes: M.segmentedWidth + M.sp8 + M.keyPillWidth + M.sp8 + M.holdLatchWidth,
                                       utilities: 3 * t, gap: compact ? M.sp8 : M.sp16, outputsLead: lead)
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

/// The header's layout A / B / C for a container width — the ladder's ONE decision (A: landscape and wide enough for all four groups on one
/// row; B: two rows; C: two compact rows when even B won't fit). It depends only on the width and the orientation, never on where the gutter
/// or the riff panel sit, so the page layout can take the kind as an input and the header can then take its positions from the page layout.
func euclideousHeaderKind(containerW: CGFloat, isLandscape: Bool) -> EuclideousHeaderLayout.Kind {
    let full = euclideousHeaderGroupWidths(compact: false)
    let aNeeds = full.brand + full.outputs + full.notes + full.utilities + 3 * full.gap
    let bNeeds = full.brand + full.outputs + full.utilities + 2 * full.gap
    if isLandscape && containerW >= aNeeds { return .a }
    return containerW < bNeeds ? .c : .b
}

/// The first layout that fits `containerW` (page width − sp16 × 2). `riffLeadingX` / `laneCentreX` are in container
/// coordinates (the page layout's `riffLeadingX` / `laneCentreX`, which are the riff panel's x and the lane gutter's x less the page margin). Portrait
/// never uses A. Positions are solved with ONE clamp per group, so no combination of slides can leave two groups
/// closer than their stated gap while the layout still "fits". The RINGS (not the OUTPUTS group with its caption) are what
/// centre on `laneCentreX` (spec §2.3), so the group's x is `laneCentreX − outputsLead − ringsSpan/2`, then clamped.
func euclideousHeaderLayout(containerW: CGFloat, isLandscape: Bool, riffLeadingX: CGFloat, laneCentreX: CGFloat) -> EuclideousHeaderLayout {
    typealias M = EuclideousHeaderMetrics
    let full = euclideousHeaderGroupWidths(compact: false)
    let kind = euclideousHeaderKind(containerW: containerW, isLandscape: isLandscape)
    if kind == .a {
        let uX = containerW - full.utilities
        // NOTES: on the riff panel's leading edge, slid left until it clears UTILITIES by sp16 — but never so far left
        // that the rings (and BRAND) lose their own room.
        let notesX = headerClamp(riffLeadingX, full.brand + full.outputs + 2 * full.gap, uX - full.gap - full.notes)
        let ringsX = headerClamp(laneCentreX - full.outputsLead - full.ringsSpan / 2, full.brand + full.gap, notesX - full.gap - full.outputs)
        return EuclideousHeaderLayout(kind: .a, widths: full,
                                      brand: .init(x: 0, width: full.brand, row: 0), outputs: .init(x: ringsX, width: full.outputs, row: 0),
                                      notes: .init(x: notesX, width: full.notes, row: 0), utilities: .init(x: uX, width: full.utilities, row: 0))
    }
    let compact = kind == .c
    let w = compact ? euclideousHeaderGroupWidths(compact: true) : full
    let uX = containerW - w.utilities
    let ringsX = headerClamp(laneCentreX - w.outputsLead - w.ringsSpan / 2, w.brand + w.gap, uX - w.gap - w.outputs)
    return EuclideousHeaderLayout(kind: compact ? .c : .b, widths: w,
                                  brand: .init(x: 0, width: w.brand, row: 0), outputs: .init(x: ringsX, width: w.outputs, row: 0),
                                  notes: .init(x: 0, width: w.notes, row: 1), utilities: .init(x: uX, width: w.utilities, row: 0))
}

// MARK: - PAGE LAYOUT (ferry "Page layout: six equal boxes in both orientations", ratified 2026-10-19)
//
// ONE pure function takes the view's size (as the view reports it — never the screen, the window, a reference width or a minimum) and the
// header's layout kind and returns the six boxes: lane cards 1–4, the riff panel and the MIX | LANES | FX panel. All six are the same size.
// Landscape is three columns by two rows (lane 1 · lane 2 · riff / lane 3 · lane 4 · panel); portrait is two columns by three (lane 1 · lane 2 /
// lane 3 · lane 4 / riff · panel). Everything that places or sizes a box reads this; every formula that depends on a box (the lane card's zones,
// the riff grid's rows and columns, MIX's grid, FX's rows, LANES' blocks) takes its size from the box — nothing measured from content changes a
// box's size. No ScrollView, nothing clipped, no minimumScaleFactor (house rules): a size under a floor is drawn at the formula's values and
// REPORTED (`floors`), never shrunk.

enum EuclideousPageMetrics {
    /// Left, right and bottom margins; the gap between boxes, both ways.
    static let margin: CGFloat = 16
    static let gap: CGFloat = 8
    /// The boxes' top edge: sp16 below the header's controls (32pt, centred in the 44pt rows). Layout A (one row): the controls end at y 47 → 63,
    /// rounded to the 8pt grid = 64. Layouts B and C: row 2's controls end at y 95 → 111 (row 2's controls sit at y 63–95 in source).
    static let topOneRowHeader: CGFloat = 64
    static let topTwoRowHeader: CGFloat = 111
    static func top(_ kind: EuclideousHeaderLayout.Kind) -> CGFloat { kind == .a ? topOneRowHeader : topTwoRowHeader }
    /// The bottom margin: sp16, or the view's bottom safe-area inset (the home-indicator zone) when that is larger, so no box ever sits in it. An inset of 9 gives 16; an
    /// inset of 20 gives 20. The page is laid out on the view's FULL height (the inset is passed in, not subtracted from `size`).
    static func bottomMargin(inset: CGFloat) -> CGFloat { max(margin, inset) }
}

/// A lane card's fixed rows, hoisted out of the view so the page's floor list and the card draw from the same numbers: the comet row (44), the
/// tab row (28), the 10pt inset on every side and two 6pt gaps leave `contentAreaH = card height − 104` for the lane tab (RHYTHM: lower zone 80,
/// upper zone the rest = card height − 188).
enum EuclideousLaneCardMetrics {
    static let inset: CGFloat = 10, rowGap: CGFloat = 6, cometRowH: CGFloat = 44, tabRowH: CGFloat = 28
    /// RHYTHM's STEPS picker covers both zones and is built only when they reach this (`tabContent`); the
    /// restart editor no longer has a hard floor — see `euclideousRestartEditorFallback` below (RHYTHM
    /// fixes §5.1, 2026-10-21).
    static let rhythmZonesFloor: CGFloat = 192
    /// RHYTHM fixes §5.1 — the restart editor's own progressive fallback thresholds: below this, each
    /// section drops its 16-cell timeline (+ the sp4 after it); below `restartEditorHintFloor`, each
    /// section drops its hint line too (+ the sp4 before it); below THAT, the editor still renders (the
    /// same reduced content) and lets its own bottom edge clip rather than refusing to build at all.
    static let restartEditorTimelineFloor: CGFloat = 156
    static let restartEditorHintFloor: CGFloat = 128
    static var chromeH: CGFloat { cometRowH + tabRowH + inset * 2 + rowGap * 2 }
    static func innerWidth(cardWidth: CGFloat) -> CGFloat { max(1, cardWidth - inset * 2) }
    static func contentAreaH(cardHeight: CGFloat) -> CGFloat { max(1, cardHeight - chromeH) }
}
/// RHYTHM POLISH §2.3 — FLIP HITS (INV renamed): the two printed lines and the VoiceOver label, one definition for the button and the tests.
enum EuclideousFlipHits {
    static let lines = ["FLIP", "HITS"]
    static let accessibilityLabel = "Flip hits"
}
// MARK: - RHYTHM TAB GEOMETRY (RHYTHM POLISH ferry, 2026-10-22, §1) — the upper zone's right half is three rows (OFFSET, TILT, the direction row), the lower zone's right group two tiles

/// Every number the RHYTHM tab's new arrangement needs, as pure functions of the lane card's size — in CARD coordinates (the reference card is 358.5 × 312: upper zone y 94–218, lower zone y 222–302) — so the views and the
/// tests read the same figures. The views take their row heights and widths from the small functions below; `euclideousRhythmTabLayout` composes them into frames.
struct EuclideousRhythmTabLayout: Equatable {
    var offsetRow: CGRect, tiltRow: CGRect, directionRow: CGRect       // the right half, sp4 apart
    var directionButtonW: CGFloat                                      // four equal buttons across `directionRow`, sp4 apart
    var hitsTile: CGRect, stepsTile: CGRect                            // the left half's two columns (unchanged)
    var rhythmTile: CGRect, melodyTile: CGRect                         // the lower zone's right group: two full-width rows of 38, sp4 apart
    var rateGroup: CGRect                                              // the lower zone's left group (unchanged), for reference
}
enum EuclideousRhythmGeometry {
    static let gap: CGFloat = 4, controlRowH: CGFloat = 38, controlBlockH: CGFloat = 80, dividerFootprint: CGFloat = 17
    /// The three right-half rows split the upper zone's height equally (RHYTHM POLISH 1.2).
    static func rightRowH(upperH: CGFloat) -> CGFloat { max(1, (upperH - gap * 2) / 3) }
    /// Four equal direction buttons, sp4 apart, across the right half (1.3).
    static func directionButtonW(rightHalfW: CGFloat) -> CGFloat { max(1, (rightHalfW - gap * 3) / 4) }
    /// The two halves of the upper zone (sp4 apart) and of the lower control block (the 17 pt divider footprint between them).
    static func upperHalfW(fullWidth: CGFloat) -> CGFloat { max(1, (fullWidth - gap) / 2) }
    static func lowerHalfW(fullWidth: CGFloat) -> CGFloat { max(1, (fullWidth - dividerFootprint) / 2) }
}
func euclideousRhythmTabLayout(cardWidth: CGFloat, cardHeight: CGFloat) -> EuclideousRhythmTabLayout {
    typealias G = EuclideousRhythmGeometry
    let inset = EuclideousLaneCardMetrics.inset
    let contentTop = inset + EuclideousLaneCardMetrics.cometRowH + EuclideousLaneCardMetrics.rowGap + EuclideousLaneCardMetrics.tabRowH + EuclideousLaneCardMetrics.rowGap
    let fullW = EuclideousLaneCardMetrics.innerWidth(cardWidth: cardWidth)
    let contentH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: cardHeight)
    let upperH = max(1, contentH - G.controlBlockH - G.gap)
    let halfW = G.upperHalfW(fullWidth: fullW)
    let rightX = inset + halfW + G.gap
    let rowH = G.rightRowH(upperH: upperH)
    let leftColW = max(1, (halfW - G.gap) / 2)
    let lowerY = contentTop + upperH + G.gap
    let lowerHalf = G.lowerHalfW(fullWidth: fullW)
    let rightGroupX = inset + lowerHalf + G.dividerFootprint
    return EuclideousRhythmTabLayout(
        offsetRow: CGRect(x: rightX, y: contentTop, width: halfW, height: rowH),
        tiltRow: CGRect(x: rightX, y: contentTop + rowH + G.gap, width: halfW, height: rowH),
        directionRow: CGRect(x: rightX, y: contentTop + (rowH + G.gap) * 2, width: halfW, height: rowH),
        directionButtonW: G.directionButtonW(rightHalfW: halfW),
        hitsTile: CGRect(x: inset, y: contentTop, width: leftColW, height: upperH),
        stepsTile: CGRect(x: inset + leftColW + G.gap, y: contentTop, width: leftColW, height: upperH),
        rhythmTile: CGRect(x: rightGroupX, y: lowerY, width: lowerHalf, height: G.controlRowH),
        melodyTile: CGRect(x: rightGroupX, y: lowerY + G.controlRowH + G.gap, width: lowerHalf, height: G.controlRowH),
        rateGroup: CGRect(x: inset, y: lowerY, width: lowerHalf, height: G.controlBlockH))
}

/// RHYTHM POLISH 2.1 — the HITS tile's hero number: 36 pt, with "OF n" 2 pt under it in 8 pt, as one block centred on the FILLED part of the tile and clamped so it stays ≥ 6 pt below the tile's top and ≥ 4 pt above
/// the HITS label's backing. At 0 hits the fill is a sliver at the bottom, so the block sits in its lowest clamped position (still fully inside the tile). The block's height is the three boxes' sum (the number's
/// line box is its font size, the caption's 10 pt, 2 pt between) — a layout decision, flagged: it is not measured from the font.
enum EuclideousHitsHero {
    static let numberSize: CGFloat = 36, captionSize: CGFloat = 8, captionBox: CGFloat = 10, gap: CGFloat = 2
    static let minTop: CGFloat = 6, labelClearance: CGFloat = 4
    /// The HITS label ("HITS", 10 pt, 5 pt up from the tile's bottom) and its opaque backing (2 pt above and below the 12 pt line).
    static let labelBottomInset: CGFloat = 5, labelBox: CGFloat = 12, labelBackingPad: CGFloat = 2
    static var blockH: CGFloat { numberSize + gap + captionBox }
    static func labelBackingTop(tileH: CGFloat) -> CGFloat { tileH - labelBottomInset - labelBox - labelBackingPad * 2 }
}
/// `fillFraction` is the slider's own 0…1 fill (`euclideousSliderFrac`); `trackInset` the slider's 6 pt travel inset. Returns the block's top y inside the tile.
func euclideousHitsHeroTop(tileH: CGFloat, fillFraction: Double, trackInset: CGFloat = 6) -> CGFloat {
    typealias H = EuclideousHitsHero
    let travel = max(1, tileH - trackInset * 2)
    let fillTop = trackInset + (1 - CGFloat(max(0, min(1, fillFraction)))) * travel      // the same mapping as the slider's `travelPos` (vertical)
    let centre = (fillTop + tileH) / 2
    let maxTop = H.labelBackingTop(tileH: tileH) - H.labelClearance - H.blockH
    return max(H.minTop, min(maxTop, centre - H.blockH / 2))
}
/// RHYTHM POLISH 2.1 — the caption colour: the lane colour lightened to 75 % toward #F2F4F7, component by component in sRGB bytes (rounded). The spec names L1 as #F7C1C1; that cannot be reached by this rule
/// (its red, 0xF7, is above both ends'), so L1 comes out #F2CDD0 — reported, not forced.
func euclideousHitsCaptionRGB(_ base: (r: Double, g: Double, b: Double)) -> (r: Int, g: Int, b: Int) {
    let t = (r: 242.0, g: 244.0, b: 247.0)
    func mix(_ a: Double, _ b: Double) -> Int { Int((a * 255 * 0.25 + b * 0.75).rounded()) }
    return (mix(base.r, t.r), mix(base.g, t.g), mix(base.b, t.b))
}

// MARK: - RESTART EDITOR LAYOUT (RESTART TILES ferry, 2026-10-22, §3) — each section is the chain row and the tile's own live strip

/// What a restart-editor section holds, top to bottom. The timeline, its axis label ("BAR 1–16") and the hint line (every case of it, NO CHANGE and the melody-1 line included) are gone; the page builds each section
/// by walking this list, so nothing else can appear. (`euclideousRhythmChainChangesNothing` stays: the migration still calls it — only its UI went.)
enum EuclideousRestartEditorPart: Hashable { case chainRow, strip }
let euclideousRestartEditorSectionParts: [EuclideousRestartEditorPart] = [.chainRow, .strip]
enum EuclideousRestartEditorMetrics {
    static let padding: CGFloat = 8, headerH: CGFloat = 20, labelW: CGFloat = 56, gap: CGFloat = 4
    static let rowH: CGFloat = 38, stripH: CGFloat = 28, stripRadius: CGFloat = 6
    static var sectionH: CGFloat { rowH + gap + stripH }                   // 70: the section is no taller than it was
    /// The three flexible gaps (after the header, between the sections, after the last) — their minimums, as the editor's VStack always had them.
    static let gapMins: [CGFloat] = [4, 8, 0]
}
struct EuclideousRestartEditorLayout: Equatable {
    var sections: [CGRect]      // RHYTHM, MELODY — in the editor's own coordinates (0,0 = its top-left corner)
    var chainRows: [CGRect]
    var strips: [CGRect]
    var gaps: [CGFloat]         // after the header · between the sections · after the last
}
/// The editor's vertical layout from its size. The three gaps share what the height leaves over equally, none under its minimum (the water-fill a SwiftUI stack of flexible spacers does) — and the page now
/// builds the gaps from THIS, so the view cannot disagree with it. Section origins: 8 + 20 + gap₁ and again + 70 + gap₂. The strip sits sp4 below the chain row, x = 8 + 56 + 4 = 68, as wide as the content less the
/// label column and its gap (262.5 at the reference 338.5-wide editor), 28 tall.
func euclideousRestartEditorLayout(width: CGFloat, height: CGFloat) -> EuclideousRestartEditorLayout {
    typealias M = EuclideousRestartEditorMetrics
    let innerH = max(0, height - M.padding * 2)
    var leftover = max(0, innerH - M.headerH - 2 * M.sectionH)
    var gaps = M.gapMins
    if leftover > M.gapMins.reduce(0, +) {   // otherwise every gap sits at its minimum (and the editor's own bottom edge clips)
        var free = [true, true, true]
        var settled = false
        while !settled {
            settled = true
            let n = CGFloat(free.filter { $0 }.count)
            guard n > 0 else { break }
            let share = leftover / n
            for i in 0..<3 where free[i] && share < M.gapMins[i] { free[i] = false; gaps[i] = M.gapMins[i]; leftover -= M.gapMins[i]; settled = false }
            if settled { for i in 0..<3 where free[i] { gaps[i] = share } }
        }
    }
    let contentW = max(1, width - M.padding * 2)
    let y1 = M.padding + M.headerH + gaps[0]
    let y2 = y1 + M.sectionH + gaps[1]
    var sections: [CGRect] = [], rows: [CGRect] = [], strips: [CGRect] = []
    for y in [y1, y2] {
        sections.append(CGRect(x: M.padding, y: y, width: contentW, height: M.sectionH))
        rows.append(CGRect(x: M.padding, y: y, width: contentW, height: M.rowH))
        strips.append(CGRect(x: M.padding + M.labelW + M.gap, y: y + M.rowH + M.gap, width: max(1, contentW - M.labelW - M.gap), height: M.stripH))
    }
    return EuclideousRestartEditorLayout(sections: sections, chainRows: rows, strips: strips, gaps: gaps)
}

/// RHYTHM fixes §5.1 (2026-10-21) — what the restart editor shows at a given height, as ONE pure decision
/// the view just reads (not re-derived inline), so a test can pin the exact 192/156/128pt thresholds the
/// spec names without needing the (untestable) SwiftUI view itself.
struct EuclideousRestartEditorFallback: Equatable { var showTimeline: Bool; var showHint: Bool }
func euclideousRestartEditorFallback(height: CGFloat) -> EuclideousRestartEditorFallback {
    EuclideousRestartEditorFallback(showTimeline: height >= EuclideousLaneCardMetrics.restartEditorTimelineFloor,
                                    showHint: height >= EuclideousLaneCardMetrics.restartEditorHintFloor)
}

/// The riff panel's chrome (RIFF PANEL ferry, 2026-10-19 §1): sp8 padding all round; the four riff tabs (20 tall); 6pt (a drawing value); the grid (the 30pt
/// note-label column, a 4pt gap, then eight columns at `euclideousRiffCellW`'s width with 4pt gaps, and eight rows with 4pt gaps); sp8; the four lane rails
/// (8 tall, 3 apart = 41); the bottom padding. 8 + 20 + 6 above the grid and 8 + 41 + 8 below it = 91, so the grid is box height − 91 tall and
/// `rowH = (box height − 119) / 8`. There is deliberately NO height-for-rows pair here (the old `riffPanelHeight` and its inverse are gone, and this
/// ferry's §1.3 says not to bring them back): the panel's inside is laid out from its box by `euclideousRiffPanelLayout`, once.
enum EuclideousRiffPanelMetrics {
    static let padding: CGFloat = 8
    static let tabRowH: CGFloat = 20, tabGap: CGFloat = 4, tabToGrid: CGFloat = 6
    static let labelW: CGFloat = 30, labelGap: CGFloat = 4, colGap: CGFloat = 4, rowGap: CGFloat = 4
    static let gridToRails: CGFloat = 8
    static let railH: CGFloat = 8, railGap: CGFloat = 3
    static var railsH: CGFloat { railH * 4 + railGap * 3 }          // 41
    /// The row-height floor the page REPORTS under (it is never enforced when drawing): a box at least 311 tall.
    static let minRowH: CGFloat = 24
    /// Everything but the eight rows' own height: 8 + 20 + 6 + 7 × 4 + 8 + 41 + 8 = 119.
    static var chromeH: CGFloat { padding + tabRowH + tabToGrid + rowGap * 7 + gridToRails + railsH + padding }
}
/// §1 / §8.1: the riff panel's inside, from the box the page function gives it. Every coordinate is in the panel's own space (0,0 = its top-left).
struct EuclideousRiffPanelLayout: Equatable {
    typealias M = EuclideousRiffPanelMetrics
    var box: CGSize
    /// The grid's column width — `euclideousRiffCellW`, the one function the FX tab's columns also use (so FX keeps lining up).
    var cellW: CGFloat
    /// The nominal row height `(box height − 119) / 8`, NOT floored (a box under the floor is drawn at this value and reported).
    var rowH: CGFloat
    /// The cell height the grid draws: the smaller of `rowH` and `cellW` (the grid has always kept its cells from being taller than wide).
    var cellH: CGFloat
    var belowFloor: Bool { rowH < M.minRowH }
    var tabWidth: CGFloat { (box.width - M.padding * 2 - M.tabGap * 3) / 4 }
    func tabFrame(_ i: Int) -> CGRect { CGRect(x: M.padding + CGFloat(i) * (tabWidth + M.tabGap), y: M.padding, width: tabWidth, height: M.tabRowH) }
    /// Column 0's left edge: padding + the note-label column + its gap = 42.
    var firstColumnX: CGFloat { M.padding + M.labelW + M.labelGap }
    var gridTop: CGFloat { M.padding + M.tabRowH + M.tabToGrid }                        // 34
    var gridSize: CGSize { CGSize(width: cellW * 8 + M.colGap * 7, height: cellH * 8 + M.rowGap * 7) }
    func columnLeft(_ c: Int) -> CGFloat { firstColumnX + CGFloat(c) * (cellW + M.colGap) }
    /// Row `r` counted from the top (rank 8 is row 0).
    func rowTop(_ r: Int) -> CGFloat { gridTop + CGFloat(r) * (cellH + M.rowGap) }
    func cellFrame(column: Int, rank: Int) -> CGRect { CGRect(x: columnLeft(column), y: rowTop(8 - rank), width: cellW, height: cellH) }
    var railsTop: CGFloat { gridTop + gridSize.height + M.gridToRails }
    func railTop(_ lane: Int) -> CGFloat { railsTop + CGFloat(lane) * (M.railH + M.railGap) }
    /// The lane's number sits in the note-label column, right-aligned and centred on its rail.
    func railNumberFrame(_ lane: Int) -> CGRect { CGRect(x: M.padding, y: railTop(lane), width: M.labelW, height: M.railH) }
    func railSegmentFrame(lane: Int, column: Int) -> CGRect { CGRect(x: columnLeft(column), y: railTop(lane), width: cellW, height: M.railH) }
}
func euclideousRiffPanelLayout(box: CGSize) -> EuclideousRiffPanelLayout {
    typealias M = EuclideousRiffPanelMetrics
    let cellW = euclideousRiffCellW(maxWidth: box.width)
    let rowH = (box.height - M.chromeH) / 8
    return EuclideousRiffPanelLayout(box: box, cellW: cellW, rowH: rowH, cellH: min(max(1, rowH), cellW))
}

/// The bottom-right panel's tab body (what LANES and FX are laid out in): the panel less sp8 padding all round, the 20pt tab row and the sp4 gap.
func euclideousSeqTabBodySize(panelWidth: CGFloat, panelHeight: CGFloat) -> CGSize {
    let pad = EuclideousMixMetrics.sp8 * 2
    return CGSize(width: max(1, panelWidth - pad), height: max(1, panelHeight - pad - EuclideousMixMetrics.tabRowH - EuclideousMixMetrics.sp4))
}

/// A floor some box's contents fall under (§5.2). A flag, never a clamp.
enum EuclideousPageFloor: Equatable, Hashable {
    case rhythmZones                 // card tab content < 192 (RHYTHM's two zones)
    case riffRowA, riffDirectionRow, riffLowerRows, riffDirectionButtons   // the RIFF tab ferry's floors: 82 · 32 · 32 · 40 wide
    case mixCellW, mixPadH, mixPadHStop   // MIX: cellW < 84 · padH < 76 · padH < 60
    case riffRows                    // riff grid rows < 24
    case fxRows                      // FX rows < 24
}

/// Which floors a box of this size falls under. Every flagged item is still drawn at the formula's values.
func euclideousPageFloors(box: CGSize) -> [EuclideousPageFloor] {
    var out: [EuclideousPageFloor] = []
    let contentH = EuclideousLaneCardMetrics.contentAreaH(cardHeight: box.height)
    if contentH < EuclideousLaneCardMetrics.rhythmZonesFloor { out.append(.rhythmZones) }
    let r = euclideousRiffTabLayout(contentAreaH: contentH, fullWidth: EuclideousLaneCardMetrics.innerWidth(cardWidth: box.width))
    if r.rowAHeight < 82 { out.append(.riffRowA) }
    if r.directionRowHeight < 32 { out.append(.riffDirectionRow) }
    if r.lowerRowHeight < 32 { out.append(.riffLowerRows) }
    if r.directionButtonWidth < 40 { out.append(.riffDirectionButtons) }
    let area = euclideousMixGridArea(panelWidth: box.width, panelHeight: box.height)
    let g = euclideousMixGrid(width: area.width, height: area.height)
    if g.cellW < EuclideousMixMetrics.minCellW { out.append(.mixCellW) }
    if g.padH < EuclideousMixMetrics.minPadH { out.append(.mixPadH) }
    if g.padH < EuclideousMixMetrics.floorPadH { out.append(.mixPadHStop) }
    if euclideousRiffPanelLayout(box: box).belowFloor { out.append(.riffRows) }
    let body = euclideousSeqTabBodySize(panelWidth: box.width, panelHeight: box.height)
    if euclideousFXRowH(contentHeight: body.height) < EuclideousFXLayout.minRowH { out.append(.fxRows) }
    return out
}

struct EuclideousPageLayout: Equatable {
    var isLandscape: Bool
    var headerKind: EuclideousHeaderLayout.Kind
    /// The one box size (all six frames have it).
    var box: CGSize
    /// Lane cards 1–4, the riff panel and the MIX | LANES | FX panel, in page coordinates (0,0 = the view's top-left).
    var lanes: [CGRect]
    var riff: CGRect
    var seq: CGRect
    /// The lane gutter's centre x — the output rings centre on it (§1.6).
    var gutterX: CGFloat
    var floors: [EuclideousPageFloor]
    /// The same two numbers in the header's CONTAINER coordinates (0 = the page margin), which is what `euclideousHeaderLayout` takes.
    var riffLeadingX: CGFloat { riff.minX - EuclideousPageMetrics.margin }
    var laneCentreX: CGFloat { gutterX - EuclideousPageMetrics.margin }
}

/// The page's six boxes for a view of `size` and a header of `headerKind`. Orientation is the view's own: strictly wider than tall is landscape.
func euclideousPageLayout(size: CGSize, headerKind: EuclideousHeaderLayout.Kind, bottomInset: CGFloat = 0) -> EuclideousPageLayout {
    typealias P = EuclideousPageMetrics
    let landscape = size.width > size.height
    let top = P.top(headerKind)
    let bottom = P.bottomMargin(inset: bottomInset)
    let cw: CGFloat, rh: CGFloat
    if landscape {
        cw = max(1, (size.width - P.margin * 2 - P.gap * 2) / 3)
        rh = max(1, (size.height - top - bottom - P.gap) / 2)
    } else {
        cw = max(1, (size.width - P.margin * 2 - P.gap) / 2)
        rh = max(1, (size.height - top - bottom - P.gap * 2) / 3)
    }
    func frame(_ col: Int, _ row: Int) -> CGRect {
        CGRect(x: P.margin + CGFloat(col) * (cw + P.gap), y: top + CGFloat(row) * (rh + P.gap), width: cw, height: rh)
    }
    let lanes = [frame(0, 0), frame(1, 0), frame(0, 1), frame(1, 1)]
    let riff = landscape ? frame(2, 0) : frame(0, 2)
    let seq = landscape ? frame(2, 1) : frame(1, 2)
    let box = CGSize(width: cw, height: rh)
    return EuclideousPageLayout(isLandscape: landscape, headerKind: headerKind, box: box, lanes: lanes, riff: riff, seq: seq,
                                gutterX: P.margin + cw + P.gap / 2, floors: euclideousPageFloors(box: box))
}
/// `euclideousPageLayout` with the header kind taken from the header's own ladder for this view width — what the page itself calls.
func euclideousPageLayout(size: CGSize, bottomInset: CGFloat = 0) -> EuclideousPageLayout {
    let kind = euclideousHeaderKind(containerW: size.width - EuclideousPageMetrics.margin * 2, isLandscape: size.width > size.height)
    return euclideousPageLayout(size: size, headerKind: kind, bottomInset: bottomInset)
}

// MARK: - MIX TAB (ferry 2026-10-18): gate, velocity and octave for every layer
//
// Pure, Foundation-only support for the sequencer panel's MIX tab and the per-layer gate/velocity model: the legato predicate
// the engine and every label share, the §6.3 "layers part at the first edit" helper, the NOTES VEL bar's relative view, the
// pad's geometry and touch maths (one definition for drawing AND touch), labels/accessibility text, octave setters shared with
// the RIFF/NOTES tabs, the tab model, and the per-touch undo state machine. `EuclideousPage`/`MixPadPainter` only draw/route.

/// Exactly 100% (rounded to a whole percent) is LEGATO — the ONE predicate behind the engine's per-layer legato, the RHYTHM
/// tab's "LEGATO" label, the pad's strip name and the spoken value, so they can never disagree.
func euclideousGateIsLegato(_ g: Double) -> Bool { Int((g * 100).rounded()) >= 100 }

/// The highest GATE a lane's RIFF or NOTES layer can be SET to (Paul 2026-10-19: "remove the legato from the xy box — it's a bit confusing in retrospect"). 100% used to
/// be LEGATO — a repeated pitch carried on as one note and the repeat sounded nothing — which read as hits failing to produce MIDI. The pad, the VoiceOver step, the
/// RHYTHM slider and a document's stored lane gates (`PluginState.euclideousLinesResolved`) all stop at this, so a lane's own gate can no longer be legato. The
/// ENGINE's legato (`euclideousGateIsLegato`) is untouched, but nothing the UI or a document can set reaches it any more: the FX tab's GATE row stopped at 95 on 2026-10-20 (it was 100 = LEGATO).
let euclideousLaneGateMax = 0.99

/// §6.3: the layers part at the FIRST edit. Before GATE changes, if `notesGate` is nil store the current GATE in it; before VEL
/// changes, if `notesVelocity` is nil store its current resolved value. ONE helper every GATE/VEL setter calls (inside the
/// caller's own undo step), so an old session sounds the same until edited and from the first edit the two layers are independent.
func euclideousPinNotesLayer(_ line: inout EuclidLine, gate: Bool, velocity: Bool) {
    if gate, line.notesGate == nil { line.notesGate = line.gateResolved }
    if velocity, line.notesVelocity == nil { line.notesVelocity = line.notesVelocityResolved }
}

/// One pitch's note length in beats (RIFF/NOTES pitches each carry their OWN gate): the gap to the lane's next real hit × that
/// pitch's gate, floored at `minGateBeats` (the engine's 5 ms), plus — when a TIE extends the hit — the full gap up to the tied
/// hit and only the extension scaled by the gate (the ferry's §3.1 TIE rule, unchanged, just per pitch).
func euclideousPitchGateBeats(gate: Double, nextHitGapBeats: Double, tieExt: Double, minGateBeats: Double) -> Double {
    tieExt > 0 ? max(minGateBeats, nextHitGapBeats + gate * tieExt) : max(minGateBeats, gate * nextHitGapBeats)
}
/// A mask-added note (CHORD interval) takes the gate — and, via `repVelBase`, the velocity — of the pitch it comes from: the
/// riff pitch when the hit has one, otherwise the notes layer (the same layer rule as the mask's octave, `maskOct`).
func euclideousExtraPitchGate(hadRiffNote: Bool, gate: Double, notesGate: Double) -> Double { hadRiffNote ? gate : notesGate }

// ── the NOTES VEL bar becomes a view of `notesVelocity` relative to VEL (§6.4) ────────────────────────────────────────

/// What the bar shows: clamp(notesVelocity − VEL, −64, 64).
func euclideousNotesVelBarValue(_ line: EuclidLine) -> Int { max(-64, min(64, line.notesVelocityResolved - line.velocityAbsoluteResolved)) }
/// Writing an offset `o` stores notesVelocity = clamp(VEL + o, 1, 127). Nothing writes `notesVelOffset` any more (it stays decodable).
func euclideousNotesVelBarWrite(_ line: inout EuclidLine, offset o: Int) {
    line.notesVelocity = max(1, min(127, line.velocityAbsoluteResolved + max(-64, min(64, o))))
}
/// The bar's double tap stores VEL into notesVelocity (offset 0).
func euclideousNotesVelBarDoubleTap(_ line: inout EuclidLine) { line.notesVelocity = line.velocityAbsoluteResolved }

// ── octave: ONE setter per layer, shared by the RIFF/NOTES tabs and the MIX stepper ──────────────────────────────────

/// RIFF layer octave (the RIFF tab's OCT row).
func euclideousSetRiffOctave(_ line: inout EuclidLine, _ v: Int) { line.riffOctave = v }

// ── LEN / SHIFT (RIFF WINDOW ferry 2026-10-21 — supersedes the RIFF WALK ferry's "SHIFT memory": SHIFT now
// wraps at the riff's own 8 columns, not at LEN, so it is independent of LENGTH and never needs clamping-
// then-remembering across a LEN change) ──────────────────────────────────────────────────────────────────

/// The ONE LEN setter — every LEN edit (the values-row stepper, keyboard, VoiceOver adjustment) calls this,
/// never `riffLength` directly. SHIFT is untouched by a LEN change (RIFF WINDOW ferry): LEN only sizes the
/// walk's own window (how many columns, counted from SHIFT, it cycles through); SHIFT independently picks
/// WHERE in the 8-column riff that window starts. Previously LEN clamped `riffRotate` into 0...(LEN−1) and a
/// "requested" shadow value remembered what SHIFT was before the clamp, restoring it when LEN grew back; that
/// whole mechanism is gone because there's nothing to clamp away any more.
func euclideousSetRiffLength(_ line: inout EuclidLine, _ L: Int) {
    line.riffLength = L
}
/// The ONE SHIFT setter — every SHIFT edit stores the new value, reduced into 0...7 (the riff's 8 columns,
/// wrapping — e.g. SHIFT 9 stores as 1), into `riffRotate`, the one field the engine and every other reader
/// keep reading. Independent of LENGTH: LEN 4 SHIFT 5 reads columns 6,7,8,1 (wrapping past the end), and
/// changing LEN afterwards never perturbs SHIFT.
func euclideousSetRiffShift(_ line: inout EuclidLine, _ v: Int) {
    line.riffRotate = ((v % 8) + 8) % 8
}
/// NOTES layer octave (the NOTES tab's octave trough): writing it also switches the notes layer ON, as that control always has.
func euclideousSetNotesOctave(_ line: inout EuclidLine, _ v: Int) {
    if !line.notesOnResolved { line.notesOn = true }
    line.octave = v
}
/// The layer's octave as the stepper shows it: −2…+2 (the engine clamps `octave` to ±2 for this row).
func euclideousMixOctave(of line: EuclidLine, notes: Bool) -> Int { max(-2, min(2, notes ? line.octaveResolved : line.riffOctaveResolved)) }
/// 0, +1, +2, −1, −2 with a true minus (U+2212).
func euclideousMixOctaveText(_ v: Int) -> String { v > 0 ? "+\(v)" : (v < 0 ? "\u{2212}\(-v)" : "0") }
/// VoiceOver: "0", "plus 1", "minus 2".
func euclideousMixOctaveSpoken(_ v: Int) -> String { v > 0 ? "plus \(v)" : (v < 0 ? "minus \(-v)" : "0") }
/// The octave one step up/down, or nil at the end of −2…+2 (no wrap — that button is disabled).
func euclideousMixOctaveNext(_ v: Int, up: Bool) -> Int? { let n = v + (up ? 1 : -1); return (-2...2).contains(n) ? n : nil }

// ── the layer-off look (§3.15) and VoiceOver wording ─────────────────────────────────────────────────────────────────

/// A layer is OFF exactly when its dot on the lane card's tab is hollow: the riff card switched off, or `notesOn` false.
func euclideousMixLayerIsOff(_ line: EuclidLine, notes: Bool) -> Bool { notes ? !euclideousNotesLayerIsOn(line) : !line.riffOnResolved }

// ── when is the NOTES layer ON? (Paul 2026-10-18) ──────────────────────────────────────────────────────────────────────

/// True when at least one note is SELECTED in the NOTES tab: a lit key (rank 1…8), TOP, or TOP 2.
func euclideousNotesHaveSelection(_ line: EuclidLine) -> Bool {
    line.litNotesResolved != 0 || line.topLitResolved || line.top2LitResolved
}
/// THE one definition of "the notes layer is on": its switch is on AND a note is selected. With no notes selected the layer is
/// OFF — even if its switch says on, because there is nothing for it to play. Everything that shows the layer's state reads this
/// (the lane card's NOTES dot, the NOTES strip, the MIX tab's pad and stepper), so they can never disagree. The engine is
/// untouched: with nothing selected it never had a pitch to sound.
func euclideousNotesLayerIsOn(_ line: EuclidLine) -> Bool { line.notesOnResolved && euclideousNotesHaveSelection(line) }

// ── CLARITY PASS (2026-10-23) §2/§5.3: the lane card's tab glyphs ────────────────────────────────────────────────────────
//
// RIFF gets a square, NOTES an upright bar, LISTEN a circle; RHYTHM none. A glyph is filled in a lane's colour when its tab's thing is ON — exactly the condition that filled the old round dot (RIFF `riffOnResolved`, NOTES
// `euclideousNotesLayerIsOn`, LISTEN a lit row) — and a 1.5 pt outline when off. The MIX pad's label wears the same glyph in the same state, and `euclideousMixLayerIsOff` is the ONE on/off both read.

/// The four lane-card tabs, in tab order (the page's `EuclideousLaneTab` has the same raw values).
enum EuclideousTabKind: Int, CaseIterable { case rhythm = 0, riff = 1, notes = 2, listen = 3 }
enum EuclideousGlyphShape: Equatable { case none, square, bar, circle }
enum EuclideousGlyphFill: Equatable {
    case lane(Int)   // that lane's lane100
    case anyLane     // the four lane colours in quarters (the LISTEN partner picker's ANY dot)
}
struct EuclideousTabGlyph: Equatable { var shape: EuclideousGlyphShape; var on: Bool; var fill: EuclideousGlyphFill }

/// What LISTEN is following: the first lit row in tab order (RHYTHM, PITCH, LEVEL) whose partner is a stored lane other than this one; an AVOID row set to ANY is "any lane". A lit row with no stored partner (an old
/// or hand-made document — the pickers always store one) is no source at all, and so is a row pointing at its own lane.
enum EuclideousListenSource: Equatable { case none, lane(Int), any }
func euclideousListenSource(_ line: EuclidLine, lane: Int) -> EuclideousListenSource {
    func specific(_ p: Int?) -> Int? { guard let p, (0..<4).contains(p), p != lane else { return nil }; return p }
    if line.listenRhythmMode != nil, let p = specific(line.listenRhythmPartner) { return .lane(p) }
    if line.listenPitchMode != nil {
        if line.listenPitchPartnerAnyResolved { return .any }
        if let p = specific(line.listenPitchPartner) { return .lane(p) }
    }
    if line.listenLevelMode != nil, let p = specific(line.listenLevelPartner) { return .lane(p) }
    return .none
}
/// §5.3. `lane` is the lane the tab row belongs to (RIFF and NOTES fill in its colour).
func euclideousTabGlyph(tab: EuclideousTabKind, line: EuclidLine, lane: Int) -> EuclideousTabGlyph {
    switch tab {
    case .rhythm: return EuclideousTabGlyph(shape: .none, on: true, fill: .lane(lane))
    case .riff:   return EuclideousTabGlyph(shape: .square, on: !euclideousMixLayerIsOff(line, notes: false), fill: .lane(lane))
    case .notes:  return EuclideousTabGlyph(shape: .bar, on: !euclideousMixLayerIsOff(line, notes: true), fill: .lane(lane))
    case .listen:
        switch euclideousListenSource(line, lane: lane) {
        case .lane(let p): return EuclideousTabGlyph(shape: .circle, on: true, fill: .lane(p))
        case .any:         return EuclideousTabGlyph(shape: .circle, on: true, fill: .anyLane)
        case .none:        return EuclideousTabGlyph(shape: .circle, on: false, fill: .lane(lane))
        }
    }
}
/// §2.3: the RHYTHM tab's "hits/steps" ("5/16"), the same two numbers the HITS and STEPS sliders print.
func euclideousRhythmTabCount(_ line: EuclidLine) -> String {
    "\(euclideousSliderValueText(.hits, line))/\(euclideousSliderValueText(.steps, line))"
}
/// §4.1: "Rhythm, 5 of 16 hits" · "Riff, on" / "Riff, off" · "Notes, on" / "Notes, off" · "Listen, on, following lane 2" / "Listen, off".
func euclideousTabAccessibilityLabel(tab: EuclideousTabKind, line: EuclidLine, lane: Int) -> String {
    switch tab {
    case .rhythm: return "Rhythm, \(euclideousSliderValueText(.hits, line)) of \(euclideousSliderValueText(.steps, line)) hits"
    case .riff:   return "Riff, " + (euclideousTabGlyph(tab: .riff, line: line, lane: lane).on ? "on" : "off")
    case .notes:  return "Notes, " + (euclideousTabGlyph(tab: .notes, line: line, lane: lane).on ? "on" : "off")
    case .listen:
        switch euclideousListenSource(line, lane: lane) {
        case .lane(let p): return "Listen, on, following lane \(p + 1)"
        case .any:         return "Listen, on, following any lane"
        case .none:        return "Listen, off"
        }
    }
}

/// Selecting a note ENABLES an off layer in the same tap ("one tap does both"): each toggle turns the layer's switch on if it was
/// off, then flips that one selection. Starting from any off state (switch off, or nothing selected), selecting one note leaves the
/// layer on. De-selecting a note never turns anything off by itself — the layer just reads off once the last one goes.
func euclideousToggleNotesKey(_ line: inout EuclidLine, rank: Int) {
    guard (1...8).contains(rank) else { return }
    euclideousToggleLitPosition(&line, position: rank - 1)
}
func euclideousToggleNotesTop(_ line: inout EuclidLine) { euclideousToggleLitPosition(&line, position: EuclideousLitOrder.topPosition) }
func euclideousToggleNotesTop2(_ line: inout EuclidLine) { euclideousToggleLitPosition(&line, position: EuclideousLitOrder.topTwoPosition) }
/// NOTES TAB ferry §2.11: a tap lights or unlights a key through the lit ORDER — lighting adds it to the END, unlighting takes it out, lighting it again later puts it at
/// the end. Positions 0-7 are ranks 1-8, 8 is TOP 2, 9 is TOP. One edit, so one undo step; and — as before — a tap on an off layer also turns it on.
func euclideousToggleLitPosition(_ line: inout EuclidLine, position: Int) {
    guard (0...9).contains(position) else { return }
    if !line.notesOnResolved { line.notesOn = true }
    var o = line.litOrderResolved
    o.toggle(position)
    line.setLitOrder(o)
}

// ── the VELOCITY strip label (Paul 2026-10-18: "VEL" → "velocity") ─────────────────────────────────────────────────────

/// The name turned along the pad's VEL strip. Upper-case like every other label on the page (GATE, LEGATO, OCT).
let euclideousMixVelocityName = "VELOCITY"
let euclideousMixVelocityNameShort = "VEL"
/// RESTART CHAINS ferry §9.5 — "keep VELOCITY when it fits between the bottom of the value's 14pt line box
/// (y 17) plus sp4 and the strip's bottom inset (plotH − 4)... otherwise show VEL. Work the fit out from the
/// font metrics the view draws with. It never truncates." Replaces the OLD `euclideousMixVelocityNameLength`
/// truncate-to-fit mechanism (MIX §3.12, superseded here) with a genuine two-way word choice. A real UIFont/
/// NSFont measurement isn't available to this Foundation-only, macOS-test-linkable file (CLAUDE.md: the
/// macOS test target links no UIKit/AppKit) — approximated from the SAME heavy-monospaced-8pt/0.08em-
/// tracking metrics `MixPadPainter.swift` actually draws with (a heavy monospaced glyph at size S runs
/// roughly 0.62×S wide; SwiftUI's `.tracking` adds its own amount after every character, last included).
/// Calibrated against the ferry's own literal example — "VELOCITY fits at padH 96 but not at 76" — which
/// this reproduces exactly; not independently verified at every other size (device-owed, §16).
func euclideousMixVelocityNameFits(plotH: CGFloat) -> Bool {
    let available = plotH - 4 - 17 - EuclideousMixMetrics.sp4
    let fontSize: CGFloat = 8, glyphWidth = 0.62 * fontSize, tracking = 0.08 * fontSize
    let needed = CGFloat(euclideousMixVelocityName.count) * (glyphWidth + tracking)
    return available >= needed
}
/// The display word for the current pad height — "VELOCITY" when it fits, else the never-truncating "VEL".
func euclideousMixVelocityDisplayName(plotH: CGFloat) -> String {
    euclideousMixVelocityNameFits(plotH: plotH) ? euclideousMixVelocityName : euclideousMixVelocityNameShort
}
func euclideousMixPadAccessibilityLabel(lane: Int, notes: Bool, off: Bool) -> String { "Lane \(lane + 1) \(notes ? "notes" : "riff")" + (off ? ", off" : "") }
func euclideousMixOctaveAccessibilityLabel(lane: Int, notes: Bool) -> String { "Lane \(lane + 1) \(notes ? "notes" : "riff") octave" }

// ── gate / velocity text (both layers share the RHYTHM tab's rules) ───────────────────────────────────────────────────

private func euclideousGateProbe(_ gate: Double) -> EuclidLine { var l = EuclidLine(); l.gate = gate; return l }
/// The strip's name: always GATE — the pad no longer offers legato (see `euclideousLaneGateMax`), so it never says LEGATO.
func euclideousMixGateName(gate: Double) -> String { EuclideousSliderField.gate.name }
/// The strip's value: "<n>%".
func euclideousMixGateValueText(gate: Double) -> String { euclideousSliderValueText(.gate, euclideousGateProbe(gate)) }
/// "gate 60 percent, velocity 104" — plain percent, no "legato" (the pad can't set it).
func euclideousMixPadAccessibilityValue(gate: Double, velocity: Int) -> String {
    let g = euclideousSliderValueText(.gate, euclideousGateProbe(gate)).replacingOccurrences(of: "%", with: " percent")
    return "gate \(g), velocity \(velocity)"
}
/// VoiceOver swipe up/down steps velocity by 4 (clamped 1…127).
func euclideousMixVelocityStep(_ v: Int, up: Bool) -> Int { max(1, min(127, v + (up ? 4 : -4))) }
/// "Longer gate" / "Shorter gate": 5 percentage points each (clamped 1…99%).
func euclideousMixGateStep(_ g: Double, longer: Bool) -> Double {
    let pct = Int((g * 100).rounded()) + (longer ? 5 : -5)
    return Double(max(1, min(Int(euclideousLaneGateMax * 100), pct))) / 100
}

// ── CLARITY PASS (2026-10-23) §3.5/§3.7: the pad's readouts, and an OFF pad that does nothing ─────────────────────────

/// The pad's two bottom readouts: the velocity bottom-left, the gate bottom-right, both 10 pt. The spec's "VEL 100" and "GATE 90%" need ≈ 90 pt of text plus insets, and a pad is ≈ 81 pt wide, so the words yield to
/// the numbers by pad width (Paul's ruling, 2026-10-23): "VEL 100" / "GATE 90%" when both fit, else "VEL 100" / "90%", else "100" / "90%". Nothing is ever truncated or shrunk. Glyph width is the same 0.62 × size
/// approximation `euclideousMixVelocityNameFits` uses (a Foundation-only file has no font metrics); a 4 pt minimum gap and the 6 pt side insets are kept clear.
struct EuclideousMixReadouts: Equatable { var velocity: String; var gate: String }
func euclideousMixReadouts(padWidth: CGFloat, velocity: Int, gate: Double) -> EuclideousMixReadouts {
    let m = EuclideousMixMetrics.self
    let v = "\(velocity)", g = euclideousMixGateValueText(gate: gate)
    let room = padWidth - 2 * m.readoutSide - 4
    func width(_ s: String) -> CGFloat { CGFloat(s.count) * 0.62 * m.labelSize }
    for form in [("VEL \(v)", "GATE \(g)"), ("VEL \(v)", g)] where width(form.0) + width(form.1) <= room {
        return EuclideousMixReadouts(velocity: form.0, gate: form.1)
    }
    return EuclideousMixReadouts(velocity: v, gate: g)
}
/// §3.7: a pad whose layer is OFF takes no touch. These are the ONLY places a pad's closure writes a lane, so even a stale view cannot change a disabled pad's layer, velocity or gate (and nothing here ever turns the layer on).
@discardableResult
func euclideousMixPadWriteIfEnabled(_ line: inout EuclidLine, notes: Bool, gate: Double, velocity: Int) -> Bool {
    guard !euclideousMixLayerIsOff(line, notes: notes) else { return false }
    euclideousMixPadWrite(&line, notes: notes, gate: gate, velocity: velocity)
    return true
}
@discardableResult
func euclideousMixPadResetIfEnabled(_ line: inout EuclidLine, notes: Bool) -> Bool {
    guard !euclideousMixLayerIsOff(line, notes: notes) else { return false }
    euclideousMixPadReset(&line, notes: notes)
    return true
}
/// A touch at `p` on a pad: its values from the point (§4.1), written only if the pad is enabled. Returns whether it wrote.
@discardableResult
func euclideousMixPadTouchWrite(_ line: inout EuclidLine, notes: Bool, at p: CGPoint, geometry: EuclideousMixPadGeometry) -> Bool {
    let v = geometry.values(at: p)
    return euclideousMixPadWriteIfEnabled(&line, notes: notes, gate: v.gate, velocity: v.velocity)
}
/// §3.7: the OFF pad's centred word and the OCT stepper's dim (50 %, and not at all while the lane is solo-silenced — the panel's own 42 % covers it, never 21 %).
let euclideousMixOffWord = "OFF"
func euclideousMixOffStepperOpacity(off: Bool, soloSilenced: Bool) -> Double { off && !soloSilenced ? 0.5 : 1 }

// ── the grid (§2): one formula for the whole MIX area ────────────────────────────────────────────────────────────────

enum EuclideousMixMetrics {
    static let sp4: CGFloat = 4, sp8: CGFloat = 8, sp16: CGFloat = 16
    static let tabRowH: CGFloat = 20
    // RESTART CHAINS ferry §9.6: OCT shrinks from 28 to 24; §9.7 adds the 20pt OUT row under each lane's pair.
    static let stepperH: CGFloat = 24
    static let outRowH: CGFloat = 20
    /// CLARITY PASS (2026-10-23) §3.3: the rotated VEL name and the value that filled this 24 pt left strip both moved (the label to the top-left, the value to the bottom-left readout), so the strip is
    /// gone and the plot spans the whole pad. 0 keeps every formula that names the strip (plot, axes, puck origin, touch inverse) a single definition.
    static let velStripW: CGFloat = 0
    static let gateStripH: CGFloat = 14
    static let puckInset: CGFloat = 7
    /// CLARITY PASS §3.1/§3.2: a lane's panel — padding sp4, radius = the lane card's 12; panels sit sp16 apart both ways.
    static let panelPad: CGFloat = 4, panelRadius: CGFloat = 12
    /// CLARITY PASS §3.4/§3.5: the pad's label (10 pt heavy, inset 5 from the top / 6 from the left) and its readouts (10 pt, inset 4 from the bottom / 6 from the side).
    static let labelTop: CGFloat = 5, labelLeft: CGFloat = 6, readoutBottom: CGFloat = 4, readoutSide: CGFloat = 6, labelSize: CGFloat = 10
    /// §9.3: below either, REPORT with the panel size — never shrink anything. PAGE LAYOUT ferry (2026-10-19) retired §9.3's STOP: below padH 60 MIX
    /// is still drawn, at the formula's values (never an empty panel); `floorPadH` is now only a flag the page's floor list raises.
    /// CLARITY PASS: the panels' padding and sp16 gaps cost every pad 6 pt of width and 12 of height at any size (84 → 78, 76 → 64, 60 → 48 move by exactly that), so the legibility floors keep the same headroom.
    static let minCellW: CGFloat = 78, minPadH: CGFloat = 64, floorPadH: CGFloat = 48
}
/// The grid area (inside the panel's sp8 padding, below the 20pt tab row + sp8) for a panel of this size.
func euclideousMixGridArea(panelWidth: CGFloat, panelHeight: CGFloat) -> CGSize {
    CGSize(width: panelWidth - EuclideousMixMetrics.sp8 * 2,
           height: panelHeight - EuclideousMixMetrics.sp8 * 2 - EuclideousMixMetrics.tabRowH - EuclideousMixMetrics.sp8)
}
struct EuclideousMixGrid: Equatable {
    /// `rowH` is a lane PANEL's height (CLARITY PASS: it was the row of cells' height), `padH` a pad's.
    var cellW: CGFloat, rowH: CGFloat, padH: CGFloat
    /// §2.8: this panel is too small for the ferry's legibility floors (reported, not shrunk).
    var belowFloors: Bool { cellW < EuclideousMixMetrics.minCellW || padH < EuclideousMixMetrics.minPadH }
    /// CLARITY PASS §3.1/§3.2: a lane panel = padding sp4, the RIFF pad, sp4, the NOTES pad, padding sp4.
    var panelW: CGFloat { cellW * 2 + EuclideousMixMetrics.sp4 + EuclideousMixMetrics.panelPad * 2 }
    var panelH: CGFloat { rowH }
    /// A panel's origin from the grid area's top-leading corner: four panels in a 2×2 grid where the lane cards sit (lanes 1,2 on the top row, 3,4 below), sp16 apart both ways.
    func panelOrigin(lane: Int) -> CGPoint {
        let col = lane % 2, row = (lane / 2) % 2
        return CGPoint(x: CGFloat(col) * (panelW + EuclideousMixMetrics.sp16), y: CGFloat(row) * (panelH + EuclideousMixMetrics.sp16))
    }
    func panelFrame(lane: Int) -> CGRect { CGRect(origin: panelOrigin(lane: lane), size: CGSize(width: panelW, height: panelH)) }
    /// A pad's origin from the grid area's top-leading corner (inside its panel's padding; RIFF then NOTES, sp4 apart).
    func origin(lane: Int, notes: Bool) -> CGPoint {
        let o = panelOrigin(lane: lane), pad = EuclideousMixMetrics.panelPad
        return CGPoint(x: o.x + pad + (notes ? cellW + EuclideousMixMetrics.sp4 : 0), y: o.y + pad)
    }
    /// The lane's OUT A–D row: across the panel's inside width, sp4 under the OCT steppers.
    func outRowFrame(lane: Int) -> CGRect {
        let o = panelOrigin(lane: lane), pad = EuclideousMixMetrics.panelPad, sp4 = EuclideousMixMetrics.sp4
        return CGRect(x: o.x + pad, y: o.y + pad + padH + sp4 + EuclideousMixMetrics.stepperH + sp4, width: panelW - pad * 2, height: EuclideousMixMetrics.outRowH)
    }
}
/// CLARITY PASS §3.1/§3.2 (replacing §9.1's cellW = (W − 16) / 4, rowH = (H − 8) / 2): panelW = (W − 16) / 2 and panelH = (H − 16) / 2 (sp16 between panels), cellW = (panelW − 12) / 2 (sp4 padding both sides + sp4 between
/// the pads), padH = panelH − 8 − 52 (the padding, then sp4 + the OCT stepper's 24 + sp4 + the OUT row's 20 under the pad). Against §9.1 that is exactly 6 pt narrower and 12 pt shorter, at any size.
func euclideousMixGrid(width: CGFloat, height: CGFloat) -> EuclideousMixGrid {
    let m = EuclideousMixMetrics.self
    let panelH = (height - m.sp16) / 2
    let panelW = (width - m.sp16) / 2
    let belowPad = m.sp4 + m.stepperH + m.sp4 + m.outRowH
    return EuclideousMixGrid(cellW: (panelW - m.panelPad * 2 - m.sp4) / 2, rowH: panelH, padH: panelH - m.panelPad * 2 - belowPad)
}

/// The frame of one of a lane's four OUT A–D buttons, in the grid area's coordinates — the SAME numbers `mixOutRow` lays its HStack out with (the row's width, sp4 gaps, 20pt tall, under the OCT stepper), so the PULSE glow
/// (§5.5) lands exactly on the button.
func euclideousMixOutButtonFrame(grid: EuclideousMixGrid, lane: Int, button b: Int) -> CGRect {
    let sp4 = EuclideousMixMetrics.sp4
    let row = grid.outRowFrame(lane: lane)
    let btnW = max(1, (row.width - sp4 * 3) / 4)
    return CGRect(x: row.minX + CGFloat(b) * (btnW + sp4), y: row.minY, width: btnW, height: row.height)
}

// ── the pad (§3/§4): drawing geometry and touch-to-value are ONE definition ────────────────────────────────────────────

struct EuclideousMixPadGeometry: Equatable {
    let cellW: CGFloat, padH: CGFloat
    var plotW: CGFloat { cellW - EuclideousMixMetrics.velStripW }
    var plotH: CGFloat { padH - EuclideousMixMetrics.gateStripH }
    var track: CGRect { CGRect(x: 0, y: 0, width: cellW, height: padH) }
    var velStrip: CGRect { CGRect(x: 0, y: 0, width: EuclideousMixMetrics.velStripW, height: plotH) }
    var gateStrip: CGRect { CGRect(x: EuclideousMixMetrics.velStripW, y: plotH, width: plotW, height: EuclideousMixMetrics.gateStripH) }
    var plot: CGRect { CGRect(x: EuclideousMixMetrics.velStripW, y: 0, width: plotW, height: plotH) }
    var yAxis: CGRect { CGRect(x: EuclideousMixMetrics.velStripW, y: 0, width: 1, height: plotH) }
    var xAxis: CGRect { CGRect(x: EuclideousMixMetrics.velStripW, y: plotH, width: plotW, height: 1) }
    /// Puck travel is inset 7 at both ends of each axis.
    private var travelX: CGFloat { plotW - EuclideousMixMetrics.puckInset * 2 }
    private var travelY: CGFloat { plotH - EuclideousMixMetrics.puckInset * 2 }
    private var originX: CGFloat { EuclideousMixMetrics.velStripW + EuclideousMixMetrics.puckInset }   // 24 + 7 = 31 — the puck's leftmost centre
    /// The puck centre for a gate fraction (0.01…1 = 1…100%) and a velocity (1…127).
    func puck(gate: Double, velocity: Int) -> CGPoint {
        CGPoint(x: originX + CGFloat(gate) * travelX, y: plotH - EuclideousMixMetrics.puckInset - CGFloat(velocity) / 127 * travelY)
    }
    /// Tick centres at q = 25, 50, 75% of each axis's travel.
    var tickXs: [CGFloat] { [0.25, 0.5, 0.75].map { originX + CGFloat($0) * travelX } }
    var tickYs: [CGFloat] { [0.25, 0.5, 0.75].map { plotH - EuclideousMixMetrics.puckInset - CGFloat($0) * travelY } }
    /// Touch-to-value (§4.1): a touch ANYWHERE on the pad (strips included) sets both values from that point —
    /// gate% = round((x − 31) / (plotW − 14) × 100), velocity = round((plotH − 7 − y) / (plotH − 14) × 127) — each clamped to its
    /// field's range (gate 1…99%, velocity 1…127). Returns the gate as a fraction.
    func values(at p: CGPoint) -> (gate: Double, velocity: Int) {
        let g = Int((Double((p.x - originX) / travelX) * 100).rounded())
        let v = Int((Double((plotH - EuclideousMixMetrics.puckInset - p.y) / travelY) * 127).rounded())
        return (Double(max(1, min(Int(euclideousLaneGateMax * 100), g))) / 100, max(1, min(127, v)))   // gate 1…99% — the far right edge is 99%, not legato
    }
}

/// Writes a pad's values into a line. RIFF: through the SAME setters the RHYTHM sliders use (so GATE/VEL always agree and the §6.3
/// pin happens); NOTES: straight into the notes layer's own fields.
func euclideousMixPadWrite(_ line: inout EuclidLine, notes: Bool, gate: Double, velocity: Int) {
    if notes {
        line.notesGate = max(0.01, min(euclideousLaneGateMax, gate)); line.notesVelocity = max(1, min(127, velocity))
    } else {
        let snap = line
        euclideousSliderCommit(.gate, &line, snapshot: snap, newValue: gate)
        euclideousSliderCommit(.velocity, &line, snapshot: snap, newValue: Double(velocity))
    }
}
/// Double tap (§4.4): both values return to what a new lane starts with (GATE 90%, VEL 100) — RIFF via the sliders' own double-tap
/// default (pin included), NOTES by storing those values in the notes layer.
func euclideousMixPadReset(_ line: inout EuclidLine, notes: Bool) {
    if notes { line.notesGate = 0.9; line.notesVelocity = 100 }
    else { euclideousSliderDoubleTapDefault(.gate, &line); euclideousSliderDoubleTapDefault(.velocity, &line) }
}
/// What a pad currently shows: the layer's gate (fraction) and velocity.
func euclideousMixPadValues(of line: EuclidLine, notes: Bool) -> (gate: Double, velocity: Int) {
    notes ? (line.notesGateResolved, line.notesVelocityResolved) : (line.gateResolved, line.velocityAbsoluteResolved)
}

// ── one undo step per TOUCH (§4.3/§4.4) ───────────────────────────────────────────────────────────────────────────

/// The page's `edit()` funnel records with one fixed coalesce key, and `UndoStack` coalesces on key equality alone — so consecutive
/// edits across DIFFERENT touches merge into one step. A pad wants one step per touch, so it checkpoints explicitly: the first
/// value-changing write of a burst asks for a new step (`nextWriteNeedsNewStep` — true once), every later write in the burst just
/// mutates. A touch that begins within `continueWithin` of the previous touch lifting CONTINUES the burst, so a double tap's reset
/// merges with the first tap and one undo returns to before it. An empty touch (no write) adds no step.
struct EuclideousPadUndoBurst: Equatable {
    static let continueWithin: Double = 0.35
    private(set) var stepOpen = false
    private var lastUp: Double? = nil
    mutating func touchDown(at t: Double) {
        if let up = lastUp, t - up <= Self.continueWithin, stepOpen { /* a second tap — same burst */ } else { stepOpen = false }
        lastUp = nil
    }
    mutating func nextWriteNeedsNewStep() -> Bool {
        if stepOpen { return false }
        stepOpen = true
        return true
    }
    mutating func touchEnd(at t: Double) { lastUp = t }
}

// ── the sequencer panel's tabs (§1) ───────────────────────────────────────────────────────────────────────────────────

/// MIX first (and the default), LANES second; RIFFS stays hidden. CORRECTION (2026-10-18 adversarial
/// review): an earlier version of this comment claimed RIFFS was "never reachable there even in the
/// pre-looper previous committed version" — WRONG, verified by git archaeology. Immediately before the
/// loop/looper ferries (`0e9e6a0`/`8a4337e`, 2026-10-16), `sequencerPanel` had a live, tappable two-tab
/// LANES/RIFFS strip showing `sequencerRiffsGrid` (a per-step riff-ASSIGNMENT matrix, a DIFFERENT feature
/// from the four-riff-tabs one) — it only became unreachable LATER, when the MIX ferry (`a2da76a`)
/// introduced this very `visible` list. What IS true: the four-riff-TABS feature (`riffTabRow()`) never
/// lived inside this tab strip at all, in any revision — it lives in the standalone `riffGridView` panel,
/// shown directly in the page layout, restored there 2026-10-18.
enum EuclideousSeqTab: Int, CaseIterable {
    case mix = 0, lanes = 1, riffs = 2, fx = 3
    var label: String { switch self { case .mix: return "MIX"; case .lanes: return "LANES"; case .riffs: return "RIFFS"; case .fx: return "FX" } }
    /// The tabs a layout without FX shows. PAGE LAYOUT ferry (2026-10-19): no layout is without FX any more — portrait's panel is the riff panel's own width,
    /// so the FX columns match the riff grid's, and it is 319 tall — but the list stays for a caller that wants it.
    static let visible: [EuclideousSeqTab] = [.mix, .lanes]
    /// FX is the third tab after MIX and LANES (the page offers it in both orientations since the PAGE LAYOUT ferry).
    static func visible(fxAvailable: Bool) -> [EuclideousSeqTab] { fxAvailable ? [.mix, .lanes, .fx] : visible }
    static let `default`: EuclideousSeqTab = .mix
}
/// Tabs only: equal widths across the full content width, sp4 apart (two tabs at the 401pt reference = 198.5 each).
func euclideousSeqTabWidth(count: Int, contentWidth: CGFloat) -> CGFloat {
    guard count > 0 else { return contentWidth }
    return (contentWidth - EuclideousMixMetrics.sp4 * CGFloat(count - 1)) / CGFloat(count)
}

// MARK: - LANES GRID (ferry 2026-10-18) — per-lane mute grid + separate rhythm / melody restart rows
//
// Every lane owns a 16-cell MUTE grid (a cell sounds or is muted) and two 16-cell RESTART masks (RHYTHM: the Euclid pattern starts
// again from its first step; MELODY: the riff goes back to its first position), each on the lane's OWN cell size. Everything that
// needs these values — the Router per hit, the TIE / gap lookahead, the roll, the walk-tag mirror, the lane-card dimming, the
// playheads — calls the functions below with the same resolved fields (§2.8: one formula, no second derivation).

/// One mute cell's length (§1.2). Raw values are STORED (`EuclidLine.muteUnit`) — never renumber.
enum EuclideousMuteUnit: UInt8, CaseIterable {
    case step = 0, fourSteps = 1, pass = 2, twoPass = 3
    var label: String {
        switch self { case .step: return "STEP"; case .fourSteps: return "4STP"; case .pass: return "PASS"; case .twoPass: return "2PASS" }
    }
    /// The rate box's tap order on MUTE (§5.1): STEP → 4STP → PASS → 2PASS → STEP.
    var next: EuclideousMuteUnit {
        switch self { case .step: return .fourSteps; case .fourSteps: return .pass; case .pass: return .twoPass; case .twoPass: return .step }
    }
    /// How many of the lane's own ticks one cell lasts; `cycleLen` is the Router's lap length in ticks (`euclidCycleLen`).
    func ticks(cycleLen: Int) -> Int {
        switch self { case .step: return 1; case .fourSteps: return 4; case .pass: return cycleLen; case .twoPass: return 2 * cycleLen }
    }
    func beats(stepBeats: Double, passBeats: Double) -> Double {
        switch self { case .step: return stepBeats; case .fourSteps: return 4 * stepBeats; case .pass: return passBeats; case .twoPass: return 2 * passBeats }
    }
}
/// One restart cell's length (§1.4). Raw values are STORED (`EuclidLine.restartUnit`) — never renumber.
enum EuclideousRestartUnit: UInt8, CaseIterable {
    case fourSteps = 1, pass = 2, twoPass = 3, fourPass = 4
    var label: String {
        switch self { case .fourSteps: return "4STP"; case .pass: return "PASS"; case .twoPass: return "2PASS"; case .fourPass: return "4PASS" }
    }
    /// The rate box's tap order on RESTART (§5.1): 4STP → PASS → 2PASS → 4PASS → 4STP.
    var next: EuclideousRestartUnit {
        switch self { case .fourSteps: return .pass; case .pass: return .twoPass; case .twoPass: return .fourPass; case .fourPass: return .fourSteps }
    }
    func ticks(cycleLen: Int) -> Int {
        switch self { case .fourSteps: return 4; case .pass: return cycleLen; case .twoPass: return 2 * cycleLen; case .fourPass: return 4 * cycleLen }
    }
    func beats(stepBeats: Double, passBeats: Double) -> Double {
        switch self { case .fourSteps: return 4 * stepBeats; case .pass: return passBeats; case .twoPass: return 2 * passBeats; case .fourPass: return 4 * passBeats }
    }
}

/// A lane's grid fields, resolved (§1.6): the new fields when the lane has been edited on the grid, otherwise the §6 migration.
struct EuclideousLaneGrid: Equatable {
    var muteCells: UInt16 = 0xFFFF
    var muteUnit: EuclideousMuteUnit = .pass
    var rhythmMask: UInt16 = 0
    var melodyMask: UInt16 = 0
    var restartUnit: EuclideousRestartUnit = .pass
    static let defaults = EuclideousLaneGrid()
}

/// §2.1 — the mute cell (0…15) a beat falls in: `floor((beat mod window) / unit)` with window = 16 × unit, spelt as the floored
/// absolute cell count mod 16 (the same quotient `euclideousMaskedResetOrigin` floors). `beat` is the absolute host beat, the same
/// zero the old step clock used. The mute window is NOT re-anchored by a restart.
func euclideousLaneMuteCell(beat: Double, unitBeats: Double) -> Int {
    guard unitBeats > 0 else { return 0 }
    return posMod(Int((beat / unitBeats).rounded(.down)), 16)
}
/// §2.1 — is the lane audible at `beat`? Pure; the Router calls it per hit at the hit's own beat (§2.2), the roll for every bar, the
/// lane card for its dimming, the panel for the cell fills.
func euclideousLaneAudible(beat: Double, cells16: UInt16, unitBeats: Double) -> Bool {
    if cells16 == 0xFFFF { return true }
    return (cells16 >> UInt16(euclideousLaneMuteCell(beat: beat, unitBeats: unitBeats))) & 1 != 0
}
/// §2.2 — the first beat in `(fromBeat, toBeat]` at which a SET cell is followed by a CLEAR one (the lane stops being audible), or nil.
/// The Router closes a lane's held legato notes there, at the lane's OWN cell boundary rather than one global step boundary.
func euclideousLaneMuteStart(fromBeat: Double, toBeat: Double, cells16: UInt16, unitBeats: Double) -> Double? {
    guard unitBeats > 0, cells16 != 0xFFFF, toBeat > fromBeat else { return nil }
    var cell = Int((fromBeat / unitBeats).rounded(.down))
    var guardCount = 0
    while guardCount < 64 {
        let boundary = Double(cell + 1) * unitBeats
        if boundary > toBeat { return nil }
        let before = (cells16 >> UInt16(posMod(cell, 16))) & 1 != 0
        let after = (cells16 >> UInt16(posMod(cell + 1, 16))) & 1 != 0
        if boundary > fromBeat, before, !after { return boundary }
        cell += 1; guardCount += 1
    }
    return nil
}

/// The cell pick shared by the origin's beat form and cell form, so the two can never disagree: with cells 0…n-1 per window, the
/// highest SET cell at or before the beat's own cell in this window, else (no mark yet this window) the window's LAST mark carried
/// over from the window before. Nil when the (width-masked) mask is empty. Flooring and integer division are the legacy
/// `euclideousMaskedResetOrigin`'s own, reused exactly (§2.3).
private func euclideousMaskedResetPick(beat: Double, cellBeats: Double, mask: UInt16, cells: Int) -> (lapStartCell: Int, s: Int, carried: Bool, n: Int)? {
    guard cellBeats > 0, cells > 0 else { return nil }
    return euclideousMaskedResetPick(absCell: Int((beat / cellBeats).rounded(.down)), mask: mask, cells: cells)
}
/// The same pick from an ABSOLUTE CELL INDEX — what the tick-based core feeds it (`floorDiv(tick, ticksPerCell)`, pure integers).
private func euclideousMaskedResetPick(absCell: Int, mask: UInt16, cells: Int, floored: Bool = false) -> (lapStartCell: Int, s: Int, carried: Bool, n: Int)? {
    guard cells > 0 else { return nil }
    let n = min(16, cells)
    let widthMask: UInt16 = n >= 16 ? 0xFFFF : UInt16((1 << n) - 1)
    let m = mask & widthMask
    guard m != 0 else { return nil }
    // `floored` (the tick-based core) extends the window grid backwards PERIODICALLY for cells before beat 0, so the schedule there is
    // the previous window's mirror image; the legacy beat/8-bit forms keep Int's truncating division (their documented quirk).
    let lapStartCell = floored ? Int(floorDiv(Int64(absCell), Int64(n))) * n : (absCell / n) * n
    let local = absCell - lapStartCell
    var bestAtOrBeforeLocal = -1, highestSet = -1, s = 0
    while s < n {
        if (m & (1 << UInt16(s))) != 0 {
            highestSet = s
            if s <= local { bestAtOrBeforeLocal = s }
        }
        s += 1
    }
    if bestAtOrBeforeLocal >= 0 { return (lapStartCell, bestAtOrBeforeLocal, false, n) }
    return (lapStartCell, highestSet, true, n)
}
/// §2.3 — the restart ORIGIN (beat) for a 16-cell (or `cells`-cell) mask. Empty mask → 0 (free-runs from beat 0). A set bit `s` at
/// or before the beat's cell → that window's start + s × cellBeats; no mark yet this window → the PREVIOUS window's last mark (a
/// NEGATIVE origin in the first window — plain arithmetic, every caller handles it like any other beat-0-relative origin).
func euclideousMaskedResetOrigin(beat: Double, cellBeats: Double, mask: UInt16, cells: Int) -> Double {
    guard let p = euclideousMaskedResetPick(beat: beat, cellBeats: cellBeats, mask: mask, cells: cells) else { return 0 }
    let lapStart = Double(p.lapStartCell) * cellBeats
    if !p.carried { return lapStart + Double(p.s) * cellBeats }
    let lapBeats = Double(p.n) * cellBeats
    return lapStart - lapBeats + Double(p.s) * cellBeats
}
/// The same origin as an ABSOLUTE CELL INDEX (nil when the mask is empty) — what the melody-ordinal arithmetic subtracts, in exact
/// integers, to place one origin relative to the other.
func euclideousMaskedResetCell(beat: Double, cellBeats: Double, mask: UInt16, cells: Int) -> Int? {
    guard let p = euclideousMaskedResetPick(beat: beat, cellBeats: cellBeats, mask: mask, cells: cells) else { return nil }
    return p.lapStartCell + p.s - (p.carried ? p.n : 0)
}

/// §6 — the mute unit whose length is nearest to the old step length `s` (ties go to the LONGER). No array is built: the render thread calls
/// this through `euclideousLaneGridResolved` for a pre-feature lane, every window.
private func euclideousNearestMuteUnit(_ s: Double, stepBeats: Double, passBeats: Double) -> EuclideousMuteUnit {
    var best = EuclideousMuteUnit.step, bestBeats = stepBeats, bestD = abs(stepBeats - s)
    for raw in 1...3 {
        let u = EuclideousMuteUnit(rawValue: UInt8(raw)) ?? .pass
        let b = u.beats(stepBeats: stepBeats, passBeats: passBeats), d = abs(b - s)
        if d < bestD - 1e-9 || (abs(d - bestD) <= 1e-9 && b > bestBeats) { best = u; bestBeats = b; bestD = d }
    }
    return best
}
private func euclideousNearestRestartUnit(_ s: Double, stepBeats: Double, passBeats: Double) -> EuclideousRestartUnit {
    var best = EuclideousRestartUnit.fourSteps, bestBeats = best.beats(stepBeats: stepBeats, passBeats: passBeats), bestD = abs(bestBeats - s)
    for raw in 2...4 {
        let u = EuclideousRestartUnit(rawValue: UInt8(raw)) ?? .pass
        let b = u.beats(stepBeats: stepBeats, passBeats: passBeats), d = abs(b - s)
        if d < bestD - 1e-9 || (abs(d - bestD) <= 1e-9 && b > bestBeats) { best = u; bestBeats = b; bestD = d }
    }
    return best
}
/// §6 — a lane's grid fields as the engine, the roll and the panel must all read them. A lane that has been edited on the grid
/// (`usesLaneGrid`) reads its five new fields (unset ones at the §1 defaults). A pre-feature lane migrates from the old data:
///   · sequencer OFF  → every cell sounds, PASS-sized (§6.1);
///   · sequencer ON   → the mute unit nearest to the old step length S (ties longer), cell i = the old cell (i mod LEN) (§6.2);
///   · the old per-lane restart (resetSteps / the 8-bit mask — NOT gated by the sequencer's ON, so it migrates either way) → the
///     restart unit nearest to S, BOTH masks getting the old marks repeated: cell j = old bit (j mod LEN) (§6.3).
/// Resolved at use because S, the lane's step / lap lengths and the host bar are only known to the render and the page, not to the
/// decoder. Pure; the render thread calls it per lane per window (no allocation: the old cells are read in place).
func euclideousLaneGridResolved(line: EuclidLine, lane: Int, legacyOn: Bool, legacyRate: EuclideousSeqRate, legacyLen: Int,
                                legacyCells: [Bool], stepBeats: Double, passBeats: Double, beatsPerBar: Double) -> EuclideousLaneGrid {
    if line.usesLaneGrid {
        return EuclideousLaneGrid(muteCells: line.muteCells16Resolved, muteUnit: line.muteUnitResolved,
                                  rhythmMask: line.restartRhythmMask16Resolved, melodyMask: line.restartMelodyMask16Resolved,
                                  restartUnit: line.restartUnitResolved)
    }
    var g = EuclideousLaneGrid.defaults
    let len = max(1, min(8, legacyLen))
    let s = legacyRate.barsFraction * beatsPerBar
    if legacyOn {
        g.muteUnit = euclideousNearestMuteUnit(s, stepBeats: stepBeats, passBeats: passBeats)
        if legacyCells.count == 32, lane >= 0, lane < 4 {
            var cells: UInt16 = 0
            for i in 0..<16 where legacyCells[(i % len) * 4 + lane] { cells |= (1 << UInt16(i)) }
            g.muteCells = cells
        }
    }
    let old = line.restartMaskResolved
    let widthMask: UInt8 = len >= 8 ? 0xFF : UInt8((1 << len) - 1)
    if old & widthMask != 0 {
        g.restartUnit = euclideousNearestRestartUnit(s, stepBeats: stepBeats, passBeats: passBeats)
        var mask: UInt16 = 0
        for j in 0..<16 where (old & widthMask) & (1 << UInt8(j % len)) != 0 { mask |= (1 << UInt16(j)) }
        g.rhythmMask = mask; g.melodyMask = mask
    }
    return g
}
/// The first edit of a lane on the grid writes ALL FIVE fields from the resolved view (like the MIX pin), so the lane is then
/// stable on the new model whatever the old fields still hold.
func euclideousPinLaneGrid(_ line: inout EuclidLine, _ g: EuclideousLaneGrid) {
    line.muteCells16 = g.muteCells; line.muteUnit = g.muteUnit.rawValue
    line.restartRhythmMask16 = g.rhythmMask; line.restartMelodyMask16 = g.melodyMask; line.restartUnit = g.restartUnit.rawValue
}

// ── RESTART CHAIN MIGRATION (ferry 2026-10-19 §12) — pure, main-thread cost only; the caller
// (Router.runEuclidLine) memoizes this, it is never called on the render path's hot loop. ──────────────

/// §12.3-12.7 — given a lane's CURRENT resolved OLD restart data (via `euclideousLaneGridResolved`, NEVER
/// re-derived — the exact ground truth every other reader of the old model already shares), what rhythm/
/// melody chain reproduces its restart beats over a 128-bar window, or the disclosed fallback.
struct EuclideousMigratedChains: Equatable {
    var rhythm: [UInt8] = []
    var melody: [UInt8] = []
    var rhythmExact = true
    var melodyExact = true
    func chains(barBeats: Double, lapBeats: Double) -> EuclideousLaneRestartChains {
        EuclideousLaneRestartChains(rhythm: .from(rhythm), melody: .from(melody), barBeats: barBeats, lapBeats: lapBeats)
    }
}
/// The shortest repeating gap-cycle in `marks` (an ascending list of unit numbers — bars or passes), ≤ 4
/// distinct gaps each from {1,2,3,4,6,8}. Empty input ⇒ FREE (exact). A first mark away from 0, or a
/// single isolated mark with no repeating cycle a chain can express, ⇒ not exact (the fallback applies).
private func euclideousFitRestartChain(_ marks: [Int]) -> (links: [UInt8], exact: Bool) {
    guard !marks.isEmpty else { return ([], true) }
    guard marks.first == 0 else { return ([], false) }
    guard marks.count > 1 else { return ([], false) }
    var gaps: [Int] = []
    for i in 1..<marks.count { gaps.append(marks[i] - marks[i - 1]) }
    var period = 0
    for p in 1...min(4, gaps.count) where gaps.indices.allSatisfy({ gaps[$0] == gaps[$0 % p] }) { period = p; break }
    guard period > 0 else { return ([], false) }
    let links = Array(gaps.prefix(period))
    guard links.allSatisfy({ [1, 2, 3, 4, 6, 8].contains($0) }) else { return ([], false) }
    return (links.map(UInt8.init), true)
}
func migrateRestartChains(line: EuclidLine, lane: Int, legacyOn: Bool, legacyRate: EuclideousSeqRate, legacyLen: Int,
                          legacyCells: [Bool], sub: Double, n: Int, dir: EuclidDir, barBeats: Double) -> EuclideousMigratedChains {
    var result = EuclideousMigratedChains()
    guard barBeats > 0, sub > 0 else { return result }
    let cycleLen = euclidCycleLen(dir, n: n)
    let passBeats = Double(cycleLen) * sub
    let g = euclideousLaneGridResolved(line: line, lane: lane, legacyOn: legacyOn, legacyRate: legacyRate, legacyLen: legacyLen,
                                       legacyCells: legacyCells, stepBeats: sub, passBeats: passBeats, beatsPerBar: barBeats)
    let windowBeats = 128 * barBeats
    /// Every old-model mark's own BEAT, in ascending order, within the window — walked cell by cell (the
    /// finest granularity a mark can occur at), exactly as §12.3 asks: "evaluate today's origin function(s)
    /// at every old cell... keep every beat where the origin changes."
    func oldMarkBeats(_ mask: UInt16) -> [Double] {
        guard mask != 0 else { return [] }
        let cellBeats = g.restartUnit.beats(stepBeats: sub, passBeats: passBeats)
        guard cellBeats > 0 else { return [] }
        var out: [Double] = []
        var cell = 0
        while Double(cell) * cellBeats < windowBeats {
            if euclideousMaskedResetCell(absCell: cell, mask: mask, cells: 16) == cell { out.append(Double(cell) * cellBeats) }
            cell += 1
        }
        return out
    }
    func toUnits(_ beats: [Double], unitBeats: Double) -> [Int]? {
        guard unitBeats > 0 else { return nil }
        var out: [Int] = []
        for b in beats {
            let u = b / unitBeats
            guard abs(u.rounded() - u) < 1e-6 else { return nil }   // doesn't land on a bar/pass boundary — can't convert
            out.append(Int(u.rounded()))
        }
        return out
    }
    // RHYTHM (§12.4): independent of LOCK — a rhythm mark always restarts the pattern, chain-agnostic.
    // "Drop any [mark] that lands on a lap start of the lane as it runs with the restarts before it,
    // since they change nothing" (§5.6's own "changes nothing" condition) — when the lap length itself is
    // a whole number of bars, a mark on one of those natural lap-start bars is redundant with the FREE
    // cadence and never needed kept in the first place (dropping it can only ever reduce, never grow, the
    // kept set, so there is no earlier-kept-restart to re-check against: a mark redundant with the plain
    // FREE cadence stays redundant whatever ELSE was also marked).
    if let bars = toUnits(oldMarkBeats(g.rhythmMask), unitBeats: barBeats) {
        let lapBars = barBeats > 0 ? passBeats / barBeats : 0
        let lapIsWholeBars = lapBars > 0 && abs(lapBars.rounded() - lapBars) < 1e-9
        let kept = lapIsWholeBars ? bars.filter { $0 % Int(lapBars.rounded()) != 0 } : bars
        let fit = euclideousFitRestartChain(kept)
        result.rhythm = fit.links; result.rhythmExact = fit.exact
    } else {
        result.rhythm = []; result.rhythmExact = false
    }
    // MELODY (§12.5): "if riffLock is true, the melody chain is 1" — taken literally. The old per-tick core
    // composed LOCK with a SIMULTANEOUSLY-set old melody mask as `max(lap start, mask position)`
    // (`euclideousLaneTick`'s own `ref = locked ? max(cy*cl, jM) : jM`) — but `euclideousLaneGridResolved`'s
    // OWN pre-grid migration (just above, confirmed by reading it) mirrors a single old restart into BOTH
    // masks IDENTICALLY (`g.rhythmMask = mask; g.melodyMask = mask`), and a rhythm mark always itself forces
    // a fresh lap start — so whenever `rhythmMask == melodyMask` (every lane migrated from the single-
    // restart era, the overwhelmingly common case), `jM`'s own marks always coincide with a lap start LOCK
    // already produces on its own, making the `max()` reduce to the lap start every time: melody chain [1]
    // is then provably exact, not merely assumed. DISCLOSED LIMITATION, reported not silently absorbed: a
    // melody mask genuinely DIFFERENT from the rhythm mask (only possible via the newer LANES GRID masks
    // set independently, or a hand-built document) is NOT verified against the real `max()` composition —
    // flagged `melodyExact = false` so §12.7 reports it rather than claiming an unchecked exact match.
    if line.riffLockResolved {
        result.melody = [1]
        result.melodyExact = (g.melodyMask == g.rhythmMask)
    } else if let passes = toUnits(oldMarkBeats(g.melodyMask), unitBeats: passBeats) {
        let fit = euclideousFitRestartChain(passes)
        result.melody = fit.links; result.melodyExact = fit.exact
    } else {
        result.melody = []; result.melodyExact = false
    }
    return result
}
/// §12.2 — the first edit of a lane's chain on the RHYTHM tab writes BOTH fields from the resolved view
/// (mirrors `euclideousPinLaneGrid` immediately above), so the lane is stable on the new model from then on
/// whatever the old fields still hold.
func euclideousPinRestartChains(_ line: inout EuclidLine, _ rhythm: EuclideousRestartChain, _ melody: EuclideousRestartChain) {
    line.restartRhythmBars = rhythm.links; line.restartMelodyPasses = melody.links
}

// ── the per-tick core (§2.4 – §2.8) ──────────────────────────────────────────────────────────────────────────────────
//
// ONE function decides, for one tick of one lane, "where is this tick in the pattern, does a hit fire, and which riff ordinal does it
// read". `Router.runEuclidLine` calls it per tick; the TIE lookahead, the next-hit gap, the roll feed and the walk-tag mirror call
// it for the ticks they look at. Nothing re-derives any of it. All arithmetic is exact integers on the lane's own ticks (a tick `k`
// sits at beat `k × sub`), so a restart cell is `ticksPerCell` ticks and the two origins are cell indices — there is no float
// comparison between "the cell the beat is in" and "the tick the beat is" to disagree at a boundary.

/// Floored integer division (rounds toward −∞), the semantics every tick/cell index here needs for ticks before beat 0.
@inline(__always) func floorDiv(_ a: Int64, _ b: Int64) -> Int64 {
    let q = a / b
    return (a % b != 0 && ((a < 0) != (b < 0))) ? q - 1 : q
}

/// A lane's restart geometry in its own ticks — scalars only, so the render thread builds one per lane per window with no allocation.
struct EuclideousLaneRestartGrid: Equatable {
    var unitTicks: Int = 0          // ticks per restart cell (`EuclideousRestartUnit.ticks`); 0 = no grid
    var rhythmMask: UInt16 = 0
    var melodyMask: UInt16 = 0
    static let off = EuclideousLaneRestartGrid()
    /// The grid replaces the legacy origin only when it carries a mark (§2.3: an empty mask free-runs from beat 0, exactly the
    /// no-restart behaviour — so a grid with no marks is the legacy path).
    var isActive: Bool { unitTicks > 0 && (rhythmMask | melodyMask) != 0 }
}
func euclideousLaneRestartGrid(_ g: EuclideousLaneGrid, cycleLen: Int) -> EuclideousLaneRestartGrid {
    EuclideousLaneRestartGrid(unitTicks: g.restartUnit.ticks(cycleLen: max(1, cycleLen)), rhythmMask: g.rhythmMask, melodyMask: g.melodyMask)
}
/// The origin CELL (absolute index) for an absolute cell, from a 16-cell mask. Nil when the mask is empty.
func euclideousMaskedResetCell(absCell: Int, mask: UInt16, cells: Int = 16) -> Int? {
    guard let p = euclideousMaskedResetPick(absCell: absCell, mask: mask, cells: cells, floored: true) else { return nil }
    return p.lapStartCell + p.s - (p.carried ? p.n : 0)
}

/// Where a tick sits in the lane's pattern: the tick count since the RHYTHM origin (`localT`), its position in the cycle (`raw`), whether
/// the pattern has a hit there, and — when the grid is in force — both origins' cell indices.
struct EuclideousLanePhase: Equatable {
    var localT: Int64
    var raw: Int
    var rawIsHit: Bool
    var gridOn: Bool
    var cellO: Int          // rhythm origin cell (0 when the rhythm mask is empty: it free-runs from beat 0)
    var cellM: Int          // melody origin cell (0 when the melody mask is empty)
}
/// The cheap half of the core — enough to know whether a tick is a hit (the gap scan and the roll's first pass use only this).
/// `legacySpanBeats` is the pre-grid re-anchor (the bar-ladder / machine-wide span) and applies only when the grid has no marks.
func euclideousLanePhase(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                         grid: EuclideousLaneRestartGrid, legacySpanBeats: Double) -> EuclideousLanePhase {
    var localT: Int64
    var cellO = 0, cellM = 0
    let gridOn = grid.isActive
    if gridOn {
        let u = Int64(grid.unitTicks)
        let absCell = Int(floorDiv(tick, u))
        if grid.rhythmMask != 0 { cellO = euclideousMaskedResetCell(absCell: absCell, mask: grid.rhythmMask) ?? 0 }
        if grid.melodyMask != 0 { cellM = euclideousMaskedResetCell(absCell: absCell, mask: grid.melodyMask) ?? 0 }
        localT = tick - Int64(cellO) * u
    } else {
        // The pre-grid arithmetic, verbatim (a tick's beat → the span re-anchor → the floored tick count).
        let tickBeat = Double(tick) * sub
        let phaseBeat = legacySpanBeats > 0 ? (tickBeat - columnStart(tickBeat, legacySpanBeats)) : tickBeat
        localT = Int64((phaseBeat / sub).rounded(.down))
    }
    let cl = Int64(max(1, cycleLen))
    let raw = Int(((localT % cl) + cl) % cl)
    return EuclideousLanePhase(localT: localT, raw: raw, rawIsHit: buf[euclidReadIndex(raw, n: n, dir: dir)],
                               gridOn: gridOn, cellO: cellO, cellM: cellM)
}

/// Hits in the first `m` ticks of the lane's cyclic pattern (any integer `m`; the pattern repeats every `cycleLen` ticks and extends
/// backwards the same way). The building block of every ordinal below.
private func euclideousPatternHits(_ m: Int64, buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, cycleHits: Int) -> Int64 {
    let cl = Int64(cycleLen)
    let q = floorDiv(m, cl)
    let r = Int(m - q * cl)
    var pre = 0
    var s = 0
    while s < r { if buf[euclidReadIndex(s, n: n, dir: dir)] { pre += 1 }; s += 1 }
    return q * Int64(cycleHits) + Int64(pre)
}
/// Hits in ABSOLUTE ticks `[0, nTicks)` of the lane's real schedule — which follows the RHYTHM restarts, so each segment between two
/// marks starts the pattern afresh. The schedule is periodic in the 16-cell window (every window has the same marks), so this is
/// `windows × hitsPerWindow + the partial window`, the partial one a walk over at most 17 segments.
private func euclideousScheduleHits(_ nTicks: Int64, rhythmMask: UInt16, unitTicks: Int, buf: [Bool], n: Int, dir: EuclidDir,
                                    cycleLen: Int, cycleHits: Int) -> Int64 {
    func pat(_ m: Int64) -> Int64 { euclideousPatternHits(m, buf: buf, n: n, dir: dir, cycleLen: cycleLen, cycleHits: cycleHits) }
    guard rhythmMask != 0 else { return pat(nTicks) }
    let u = Int64(unitTicks)
    let window = 16 * u
    /// Hits in window-relative ticks [0, r), 0 ≤ r ≤ window.
    func inWindow(_ r: Int64) -> Int64 {
        guard r > 0 else { return 0 }
        var highest = 0, first = -1
        for s in 0..<16 where (rhythmMask >> UInt16(s)) & 1 != 0 { highest = s; if first < 0 { first = s } }
        var total: Int64 = 0
        // the segment carried over from the previous window: cells [0, first) running from the previous window's last mark
        if first > 0 {
            let origin = Int64(highest - 16) * u
            let hi = min(Int64(first) * u, r)
            if hi > 0 { total += pat(hi - origin) - pat(0 - origin) }
        }
        var s = first
        while s >= 0 && s < 16 {
            var next = s + 1
            while next < 16 && (rhythmMask >> UInt16(next)) & 1 == 0 { next += 1 }
            let lo = Int64(s) * u
            if lo >= r { break }
            let hi = min(Int64(next) * u, r)
            let origin = lo
            total += pat(hi - origin) - pat(lo - origin)
            s = next
        }
        return total
    }
    let q = floorDiv(nTicks, window)
    let rem = nTicks - q * window
    return q * inWindow(window) + inWindow(rem)
}

/// What one tick of a lane IS, beyond where it sits: the cycle count and in-cycle hit rank (the legacy `cy` / `hitsUpTo`), and the
/// ordinal the riff walk reads (`advOrd`) — counted from the MELODY origin on the lane's actual hit schedule (§2.5).
struct EuclideousLaneTickInfo: Equatable {
    var localT: Int64
    var raw: Int
    var rawIsHit: Bool
    var cy: Int64
    var hitsUpTo: Int
    var ord: Int64          // hits since the RHYTHM origin (the pre-grid `ord`) — what a plain NOTE-mode pick (CYCLE / RANDOM) walks
    var advOrd: Int64       // the ordinal fed to the riff walk (counted from the MELODY origin)
}
/// The per-tick core. `tick` is the lane's absolute tick (a tick sits at beat `tick × sub`); `cycleLen` is `euclidCycleLen(dir, n)`.
/// Without a grid mark this is exactly the pre-grid arithmetic: `ord`/`advOrd` from the single (span) origin. With one, the rhythm
/// origin phases the pattern and the melody origin sets where the riff ordinal counts from:
///   · FREE — hits (HIT advance) or ticks (STEP advance) since the melody origin, on the schedule that really sounded;
///   · LOCK — the same, but counted from the LATER of the melody origin and the start of the current Euclid lap (which is anchored
///     to the rhythm origin), so a lap boundary still re-anchors the riff exactly as before.
/// Both marks on the same cell reproduce the old single restart (the melody origin then equals the rhythm origin).
func euclideousLaneTick(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                        grid: EuclideousLaneRestartGrid, legacySpanBeats: Double,
                        locked: Bool, advanceStep: Bool) -> EuclideousLaneTickInfo {
    let ph = euclideousLanePhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, grid: grid, legacySpanBeats: legacySpanBeats)
    let cl = Int64(max(1, cycleLen))
    let cy = (ph.localT - Int64(ph.raw)) / cl
    var hitsUpTo = 0
    var s = 0
    while s <= ph.raw { if buf[euclidReadIndex(s, n: n, dir: dir)] { hitsUpTo += 1 }; s += 1 }
    var cycleHits = 0
    s = 0
    while s < cycleLen { if buf[euclidReadIndex(s, n: n, dir: dir)] { cycleHits += 1 }; s += 1 }
    let advOrd: Int64
    let ord = cy * Int64(max(1, cycleHits)) + Int64(hitsUpTo - 1)
    if !ph.gridOn || ph.cellM == ph.cellO {
        // one shared origin (no marks, or both origins on the same cell): exactly the pre-grid single-restart arithmetic
        advOrd = advanceStep ? (locked ? Int64(ph.raw) : ph.localT) : (locked ? Int64(hitsUpTo - 1) : ord)
    } else {
        let u = Int64(grid.unitTicks)
        let jM = Int64(ph.cellM - ph.cellO) * u                 // the melody origin, in ticks relative to the rhythm origin
        let ref = locked ? max(cy * cl, jM) : jM
        if advanceStep {
            advOrd = ph.localT - ref
        } else {
            let upTo = euclideousPatternHits(ph.localT + 1, buf: buf, n: n, dir: dir, cycleLen: cycleLen, cycleHits: cycleHits)
            if ref >= 0 {
                advOrd = upTo - euclideousPatternHits(ref, buf: buf, n: n, dir: dir, cycleLen: cycleLen, cycleHits: cycleHits) - 1
            } else {
                // the melody origin lies BEFORE the current rhythm segment: add the hits of the segments between the two origins
                func scheduleAt(_ cell: Int) -> Int64 {
                    euclideousScheduleHits(Int64(cell) * u, rhythmMask: grid.rhythmMask, unitTicks: grid.unitTicks, buf: buf, n: n, dir: dir,
                                           cycleLen: cycleLen, cycleHits: cycleHits)
                }
                advOrd = upTo + (scheduleAt(ph.cellO) - scheduleAt(ph.cellM)) - 1
            }
        }
    }
    return EuclideousLaneTickInfo(localT: ph.localT, raw: ph.raw, rawIsHit: ph.rawIsHit, cy: cy, hitsUpTo: hitsUpTo, ord: ord, advOrd: advOrd)
}

/// The beat gap from `tick` (exclusive) to the lane's NEXT real pattern hit — the same core, so a restart (either kind of mark falls
/// on the rhythm origin) between the two is honoured. Bounded at `cap` ticks; returns `cap × sub` when nothing is found.
func euclideousNextHitGapBeats(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64, cap: Int,
                               grid: EuclideousLaneRestartGrid, legacySpanBeats: Double) -> Double {
    guard !buf.isEmpty, n > 0, sub > 0, cap > 0 else { return sub }
    var k = 1
    while k <= cap {
        if euclideousLanePhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick + Int64(k), grid: grid,
                               legacySpanBeats: legacySpanBeats).rawIsHit { return Double(k) * sub }
        k += 1
    }
    return Double(cap) * sub
}

/// ON REST = TIE (§3.1's "tie computation"): how many beats the note struck at `tick` is held over the riff RESTS that follow, walking
/// the lane's future HITS through the core so the answer agrees with what the Router will read at each of them — across a rhythm
/// restart, a melody restart, and a window boundary with no mark on cell 0. A LOCK reset (the first hit after the riff's reference
/// point) always breaks the chain. `rankAt(step, beat)` is the effective rank at a riff column at that hit's own beat. Bounded,
/// allocation-free: at most `length` hits and `cycleLen × 4` ticks.
func euclideousRiffTieExtensionBeats(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                                     grid: EuclideousLaneRestartGrid, legacySpanBeats: Double, locked: Bool, advanceStep: Bool,
                                     riffDir: RiffDir, stride: Int, length: Int, rotate: Int, seed: UInt64,
                                     restTies: Bool = true, fxTie: (_ column: Int, _ beat: Double, _ writtenRank: Int) -> Bool = { _, _, _ in false },
                                     rankAt: (_ column: Int, _ beat: Double) -> Int) -> Double {
    var hitsAhead = 0
    var lastConsumed = 0
    var j = 0
    let cap = cycleLen * 4
    while hitsAhead < length && j < cap {
        j += 1
        let t = tick + Int64(j)
        let info = euclideousLaneTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: t, grid: grid,
                                      legacySpanBeats: legacySpanBeats, locked: locked, advanceStep: advanceStep)
        guard info.rawIsHit else { continue }
        if locked && info.advOrd == 0 { break }                 // a locked lane's own reset always breaks the chain
        hitsAhead += 1
        let step = riffStepAt(riffDir, raw: Int(info.advOrd) * stride, steps: length, seed: seed)
        let column = riffRotateStep(step, by: rotate, steps: length)
        // FX TAB (2026-10-18): a future hit CONTINUES the chain when it is a TIED hit — a rest while ON REST is TIE (`restTies`), or a real-rank hit
        // an FX TIE cell applies to (`fxTie`, decided by the shared `euclideousFXApply` at that hit's own beat). Anything else is a real note and breaks it.
        // `restTies`/`fxTie` default to "rests tie, no FX", the pre-FX behaviour. `fxTie` is deliberately a NON-optional, non-escaping closure: an Optional closure
        // parameter is implicitly escaping, which made the Router heap-allocate a context for it on every hit of a lane with TIE cells (render-thread allocation).
        let beatJ = Double(t) * sub
        let writtenJ = rankAt(column, beatJ)
        if writtenJ < 1 {
            guard restTies else { break }
        } else {
            guard fxTie(column, beatJ, writtenJ) else { break }
        }
        lastConsumed = j
    }
    return Double(lastConsumed) * sub
}

// ── RESTART CHAINS (ferry 2026-10-19) — REPLACES the masked rhythm/melody grid above as the engine's real
// restart source. `EuclideousLaneRestartGrid`/`euclideousLanePhase`/`euclideousLaneTick`/
// `euclideousNextHitGapBeats`/`euclideousRiffTieExtensionBeats` ABOVE are kept exactly as they were,
// completely unused by the real restart decision from here on — they stay ONLY because the FX tab
// (out of scope for this ferry, landed after it was planned) builds its own closed-form pass-index math
// directly on top of them, with its own full test suite (`Tests/FXTabTests.swift`) constructing
// `EuclideousLaneRestartGrid` values by hand. Touching that shared name/shape to redesign it for chains
// would be exactly the FX-tab redesign this ferry's own "Out of scope" list rules out, so the two restart
// cores now coexist under different names, matching this project's own established precedent: every prior
// restart-model generation here (resetSteps → the 8-bit mask → the 16-cell LANES GRID masks) got its own
// distinctly-named functions rather than overloading the previous generation's names. FX's own
// restart-awareness is therefore FROZEN at whatever a lane's old restartRhythmMask16/restartMelodyMask16
// happen to hold (decode-only from here — nothing ever pins them again) and will not reflect a lane's new
// chains; flagged in this ferry's own report (§17.9), not silently absorbed.

/// A restart chain (RHYTHM in bars, MELODY in passes — §4.1), packed as 4 bytes in one UInt32: byte i is
/// link i+1, 0 = unused. FREE = 0 (every byte 0). Fixed-size, Equatable, no allocation — the render-path
/// shape §4.11 asks for.
struct EuclideousRestartChain: Equatable {
    var packed: UInt32 = 0
    static let free = EuclideousRestartChain()
    var isFree: Bool { packed == 0 }
    var count: Int {
        for i in 0..<4 where (packed >> UInt32(8 * i)) & 0xFF == 0 { return i }
        return 4
    }
    func link(_ i: Int) -> Int { Int((packed >> UInt32(8 * i)) & 0xFF) }
    /// C — the chain's own cycle length, in its own unit (bars for rhythm, passes for melody). 0 ⇒ FREE.
    var total: Int { var t = 0; var i = 0; while i < count { t += link(i); i += 1 }; return t }
    /// o_i (o_0 = 0): the running total BEFORE link i.
    func runningTotal(_ i: Int) -> Int { var t = 0; var s = 0; while s < i { t += link(s); s += 1 }; return t }
    /// True exactly when this chain is a single link of 1 — "a melody chain of 1 is exactly what LOCK did" (§4.7).
    var isSingleLink1: Bool { count == 1 && link(0) == 1 }
    /// Builds a chain from a validated link array (§4.11: drop anything not in {1,2,3,4,6,8}, keep ≤ 4).
    static func from(_ raw: [UInt8]) -> EuclideousRestartChain {
        var p: UInt32 = 0; var i = 0
        for v in raw where [1, 2, 3, 4, 6, 8].contains(Int(v)) {
            guard i < 4 else { break }
            p |= UInt32(v) << UInt32(8 * i); i += 1
        }
        return EuclideousRestartChain(packed: p)
    }
    /// The inverse of `.from` — the validated link list this chain holds, for storing back onto a lane (§12.2's pin).
    var links: [UInt8] { (0..<count).map { UInt8(link($0)) } }
}
/// §5.1 — the RHYTHM origin, in BEATS. FREE ⇒ 0. Otherwise: cycle = C × barBeats, m = floor(beat/cycle), w = beat −
/// m×cycle; the origin is m×cycle + barBeats × the largest running total o_i with o_i×barBeats ≤ w (o_0 = 0 always
/// qualifies — a running-total chain always has a mark at its own cycle start). Bounded: ≤ 4 links.
func euclideousRhythmChainOrigin(beat: Double, barBeats: Double, chain: EuclideousRestartChain) -> Double {
    guard !chain.isFree, barBeats > 0 else { return 0 }
    let cycle = Double(chain.total) * barBeats
    guard cycle > 0 else { return 0 }
    let m = (beat / cycle).rounded(.down)
    let w = beat - m * cycle
    var bestBeats = 0.0
    var i = 0
    while i < chain.count {
        let oBeats = Double(chain.runningTotal(i)) * barBeats
        if oBeats <= w + 1e-9 { bestBeats = oBeats } else { break }
        i += 1
    }
    return m * cycle + bestBeats
}
/// §5.1, second half — the NEXT rhythm restart strictly after `beat`; nil when FREE.
func euclideousNextRhythmRestart(after beat: Double, barBeats: Double, chain: EuclideousRestartChain) -> Double? {
    guard !chain.isFree, barBeats > 0 else { return nil }
    let cycle = Double(chain.total) * barBeats
    guard cycle > 0 else { return nil }
    let m = (beat / cycle).rounded(.down)
    let w = beat - m * cycle
    var i = 0
    while i < chain.count {
        let oBeats = Double(chain.runningTotal(i)) * barBeats
        if oBeats > w + 1e-9 { return m * cycle + oBeats }
        i += 1
    }
    return (m + 1) * cycle
}
/// §5.2 — the PASS index at `beat` (0-based). FREE ⇒ floor(beat/lapBeats). Otherwise: link i's segment holds
/// passes_i = ceil(l_i×barBeats/lapBeats − ε) passes (ε so an exact multiple adds no empty pass), Q = Σ passes_i
/// over one rhythm cycle, index = m×Q + Σ(passes_i before w's segment) + floor((w − that segment's own start + ε)/lapBeats),
/// where m = floor((beat + ε)/cycle) (rhythm fixes §3.3: every floor/ceil in this family reads `+ ε`, not just the
/// ceil — a beat landing exactly on a cycle or segment boundary (floating-point noise aside) must round UP into the
/// next cycle/segment, not stay a hair short of it).
/// Bounded: ≤ 4 segments.
func euclideousPassIndex(beat: Double, lapBeats: Double, barBeats: Double, rhythmChain: EuclideousRestartChain) -> Int64 {
    guard lapBeats > 0 else { return 0 }
    guard !rhythmChain.isFree, barBeats > 0 else { return Int64((beat / lapBeats).rounded(.down)) }
    let cycle = Double(rhythmChain.total) * barBeats
    guard cycle > 0 else { return Int64((beat / lapBeats).rounded(.down)) }
    let eps = 1e-9
    func passesIn(_ linkBars: Int) -> Int64 { Int64((Double(linkBars) * barBeats / lapBeats - eps).rounded(.up)) }
    let m = ((beat + eps) / cycle).rounded(.down)
    let w = beat - m * cycle
    var Q: Int64 = 0
    var i = 0
    while i < rhythmChain.count { Q += passesIn(rhythmChain.link(i)); i += 1 }
    var passesBefore: Int64 = 0
    i = 0
    while i < rhythmChain.count {
        let segStart = Double(rhythmChain.runningTotal(i)) * barBeats
        let segLen = Double(rhythmChain.link(i)) * barBeats
        if w < segStart + segLen - eps || i == rhythmChain.count - 1 {
            return Int64(m) * Q + passesBefore + Int64(((w - segStart + eps) / lapBeats).rounded(.down))
        }
        passesBefore += passesIn(rhythmChain.link(i)); i += 1
    }
    return Int64(m) * Q + passesBefore
}
/// §5.2's inverse — the BEAT a given pass index starts at.
func euclideousPassStart(_ q: Int64, lapBeats: Double, barBeats: Double, rhythmChain: EuclideousRestartChain) -> Double {
    guard lapBeats > 0 else { return 0 }
    guard !rhythmChain.isFree, barBeats > 0 else { return Double(q) * lapBeats }
    let cycle = Double(rhythmChain.total) * barBeats
    guard cycle > 0 else { return Double(q) * lapBeats }
    let eps = 1e-9
    func passesIn(_ linkBars: Int) -> Int64 { Int64((Double(linkBars) * barBeats / lapBeats - eps).rounded(.up)) }
    var Q: Int64 = 0
    var i = 0
    while i < rhythmChain.count { Q += passesIn(rhythmChain.link(i)); i += 1 }
    guard Q > 0 else { return 0 }
    let m = floorDiv(q, Q)
    var r = q - m * Q
    i = 0
    while i < rhythmChain.count {
        let p = passesIn(rhythmChain.link(i))
        if r < p { return Double(m) * cycle + Double(rhythmChain.runningTotal(i)) * barBeats + Double(r) * lapBeats }
        r -= p; i += 1
    }
    return Double(m) * cycle   // defensive; unreachable given Q's own definition
}
/// §5.3 — the MELODY origin, in BEATS. FREE ⇒ 0. Otherwise: P = Σ melody links, q = passIndex(beat), r = q mod P,
/// q0 = q − r + the largest running total p_i ≤ r (p_0 = 0 always qualifies); origin = passStart(q0).
func euclideousMelodyChainOrigin(beat: Double, lapBeats: Double, barBeats: Double,
                                  rhythmChain: EuclideousRestartChain, melodyChain: EuclideousRestartChain) -> Double {
    guard !melodyChain.isFree else { return 0 }
    let P = Int64(melodyChain.total)
    guard P > 0 else { return 0 }
    let q = euclideousPassIndex(beat: beat, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythmChain)
    let r = ((q % P) + P) % P
    var best: Int64 = 0
    var i = 0
    while i < melodyChain.count {
        let p = Int64(melodyChain.runningTotal(i))
        if p <= r { best = p } else { break }
        i += 1
    }
    let q0 = q - r + best
    return euclideousPassStart(q0, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythmChain)
}
/// Whether `beat`'s own pass is itself one of the melody chain's restart passes (§4.6: "sends the riff position
/// back to its start AT THE START of a restarting pass") — the genuine replacement for old LOCK's unconditional
/// "every lap restarts" (`euclideousRiffLapBaseline`'s own fallback, below): a melody chain of exactly [1]
/// naturally answers true for every pass with no special-casing (P = 1, so `r` is always 0 = `best`) — old LOCK's
/// own guarantee, §4.7. Any other chain answers true only on the passes `euclideousMelodyChainOrigin` itself
/// would anchor AT (same `q`/`r`/`best` walk, ≤ 4 links). FREE is never a restart pass.
func euclideousIsMelodyChainRestartPass(beat: Double, lapBeats: Double, barBeats: Double,
                                        rhythmChain: EuclideousRestartChain, melodyChain: EuclideousRestartChain) -> Bool {
    guard !melodyChain.isFree else { return false }
    let P = Int64(melodyChain.total)
    guard P > 0 else { return false }
    let q = euclideousPassIndex(beat: beat, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythmChain)
    let r = ((q % P) + P) % P
    var best: Int64 = 0
    var i = 0
    while i < melodyChain.count {
        let p = Int64(melodyChain.runningTotal(i))
        if p <= r { best = p } else { break }
        i += 1
    }
    return best == r
}
/// Floors a beat-domain origin to the lane's own tick grid — the ONE place a chain origin (bar- or pass-based)
/// becomes the tick-domain anchor the per-tick core subtracts. Same flooring convention as the legacy
/// re-anchor (`columnStart` + `.rounded(.down)`) above.
@inline(__always) func euclideousOriginTick(_ originBeat: Double, sub: Double) -> Int64 {
    guard sub > 0 else { return 0 }
    return Int64((originBeat / sub).rounded(.down))
}
/// §5.4 — hits (pattern hits) from beat 0 up to ABSOLUTE TICK `m` (exclusive), on the lane's REAL schedule: each
/// rhythm-chain segment restarts the pattern's own phase at its own start. FREE rhythm ⇒ the plain
/// `euclideousPatternHits`. One formula — both the engine's HIT-mode ordinal and the §12 migration's own
/// ground-truth walk read this, so a hit-ordinal can never drift from a second derivation (§5.7). Bounded: ≤ 4
/// segments for the partial cycle.
func euclideousChainHitsBefore(_ m: Int64, rhythm: EuclideousRestartChain, barBeats: Double, sub: Double,
                               buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, cycleHits: Int) -> Int64 {
    func pat(_ x: Int64) -> Int64 { euclideousPatternHits(x, buf: buf, n: n, dir: dir, cycleLen: cycleLen, cycleHits: cycleHits) }
    guard !rhythm.isFree, sub > 0, barBeats > 0 else { return pat(m) }
    let cycleBeats = Double(rhythm.total) * barBeats
    let cycleTicks = euclideousOriginTick(cycleBeats, sub: sub)
    guard cycleTicks > 0 else { return pat(m) }
    func inCycle(_ r: Int64) -> Int64 {
        guard r > 0 else { return 0 }
        var total: Int64 = 0
        var i = 0
        while i < rhythm.count {
            let segStartTick = euclideousOriginTick(Double(rhythm.runningTotal(i)) * barBeats, sub: sub)
            if segStartTick >= r { break }
            let segEndBeat = i + 1 < rhythm.count ? Double(rhythm.runningTotal(i + 1)) * barBeats : cycleBeats
            let hi = min(euclideousOriginTick(segEndBeat, sub: sub), r)
            total += pat(hi - segStartTick)
            i += 1
        }
        return total
    }
    let q = floorDiv(m, cycleTicks)
    return q * inCycle(cycleTicks) + inCycle(m - q * cycleTicks)
}
/// A lane's restart geometry in BEATS — the chain-era replacement for `EuclideousLaneRestartGrid`. `barBeats`/
/// `lapBeats` are the context §5.1-§5.3 need, resolved once per lane per render.
struct EuclideousLaneRestartChains: Equatable {
    var rhythm: EuclideousRestartChain = .free
    var melody: EuclideousRestartChain = .free
    var barBeats: Double = 4
    var lapBeats: Double = 0
    static let off = EuclideousLaneRestartChains()
    var isActive: Bool { !rhythm.isFree || !melody.isFree }
}
/// Where a tick sits in the lane's pattern, chain-era: the tick count since the RHYTHM origin (`localT`), its
/// position in the cycle (`raw`), whether the pattern has a hit there, and — when a chain is in force — both
/// origins as ABSOLUTE TICKS (already fully resolved; no further unit scaling anywhere downstream, unlike the
/// old grid's cell indices).
struct EuclideousLaneChainPhase: Equatable {
    var localT: Int64
    var raw: Int
    var rawIsHit: Bool
    var gridOn: Bool
    var originTickO: Int64
    var originTickM: Int64
}
/// The chain-era counterpart of `euclideousLanePhase` — same shape, origins from §5.1/§5.3 instead of a masked
/// cell lookup.
func euclideousLaneChainPhase(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                              chains: EuclideousLaneRestartChains, legacySpanBeats: Double) -> EuclideousLaneChainPhase {
    var localT: Int64
    var originTickO: Int64 = 0, originTickM: Int64 = 0
    let gridOn = chains.isActive
    if gridOn, sub > 0 {
        let beat = Double(tick) * sub
        if !chains.rhythm.isFree {
            originTickO = euclideousOriginTick(euclideousRhythmChainOrigin(beat: beat, barBeats: chains.barBeats, chain: chains.rhythm), sub: sub)
        }
        if !chains.melody.isFree {
            let originBeat = euclideousMelodyChainOrigin(beat: beat, lapBeats: chains.lapBeats, barBeats: chains.barBeats,
                                                          rhythmChain: chains.rhythm, melodyChain: chains.melody)
            originTickM = euclideousOriginTick(originBeat, sub: sub)
        }
        localT = tick - originTickO
    } else {
        let tickBeat = Double(tick) * sub
        let phaseBeat = legacySpanBeats > 0 ? (tickBeat - columnStart(tickBeat, legacySpanBeats)) : tickBeat
        localT = Int64((phaseBeat / sub).rounded(.down))
    }
    let cl = Int64(max(1, cycleLen))
    let raw = Int(((localT % cl) + cl) % cl)
    return EuclideousLaneChainPhase(localT: localT, raw: raw, rawIsHit: buf[euclidReadIndex(raw, n: n, dir: dir)],
                                    gridOn: gridOn, originTickO: originTickO, originTickM: originTickM)
}
/// The chain-era counterpart of `euclideousLaneTick` — same `EuclideousLaneTickInfo` result shape (it carries no
/// restart-model-specific fields). §4.7: a melody chain of exactly `[1]` reproduces old LOCK's own re-anchoring
/// with no special-casing (every pass boundary is itself a melody restart, so the melody origin is always the
/// current pass's own start) — there is no `locked:` parameter here at all.
func euclideousLaneChainTick(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                             chains: EuclideousLaneRestartChains, legacySpanBeats: Double, advanceStep: Bool) -> EuclideousLaneTickInfo {
    let ph = euclideousLaneChainPhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains, legacySpanBeats: legacySpanBeats)
    let cl = Int64(max(1, cycleLen))
    let cy = (ph.localT - Int64(ph.raw)) / cl
    var hitsUpTo = 0
    var s = 0
    while s <= ph.raw { if buf[euclidReadIndex(s, n: n, dir: dir)] { hitsUpTo += 1 }; s += 1 }
    var cycleHits = 0
    s = 0
    while s < cycleLen { if buf[euclidReadIndex(s, n: n, dir: dir)] { cycleHits += 1 }; s += 1 }
    let ord = cy * Int64(max(1, cycleHits)) + Int64(hitsUpTo - 1)
    let advOrd: Int64
    if !ph.gridOn || ph.originTickM == ph.originTickO {
        advOrd = advanceStep ? ph.localT : ord
    } else if advanceStep {
        advOrd = tick - ph.originTickM
    } else {
        let upTo = euclideousChainHitsBefore(tick + 1, rhythm: chains.rhythm, barBeats: chains.barBeats, sub: sub,
                                             buf: buf, n: n, dir: dir, cycleLen: cycleLen, cycleHits: cycleHits)
        let before = euclideousChainHitsBefore(ph.originTickM, rhythm: chains.rhythm, barBeats: chains.barBeats, sub: sub,
                                               buf: buf, n: n, dir: dir, cycleLen: cycleLen, cycleHits: cycleHits)
        advOrd = upTo - before - 1
    }
    return EuclideousLaneTickInfo(localT: ph.localT, raw: ph.raw, rawIsHit: ph.rawIsHit, cy: cy, hitsUpTo: hitsUpTo, ord: ord, advOrd: advOrd)
}
/// The chain-era counterpart of `euclideousNextHitGapBeats`.
func euclideousNextChainHitGapBeats(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64, cap: Int,
                                    chains: EuclideousLaneRestartChains, legacySpanBeats: Double, timing: EuclideousHitTiming = .none) -> Double {
    guard !buf.isEmpty, n > 0, sub > 0, cap > 0 else { return sub }
    // RHYTHM POLISH §5.2: the gap runs between the two hits' ACTUAL times — whole ticks plus the difference of their delays (a uniform fraction cancels).
    let dThis = timing.isNone ? 0 : timing.delaySteps(raw: euclideousLaneChainPhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                                                                    legacySpanBeats: legacySpanBeats).raw)
    var k = 1
    while k <= cap {
        let ph = euclideousLaneChainPhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick + Int64(k), chains: chains, legacySpanBeats: legacySpanBeats)
        if ph.rawIsHit { return (Double(k) + (timing.isNone ? 0 : timing.delaySteps(raw: ph.raw) - dThis)) * sub }
        k += 1
    }
    return Double(cap) * sub
}
/// The chain-era counterpart of `euclideousRiffTieExtensionBeats`. §4.6: a melody restart ends a TIE run (no hit
/// moves) — `info.advOrd == 0` at a restarting pass's own first hit is exactly that, with no `locked:` special case.
func euclideousChainTieExtensionBeats(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                                      chains: EuclideousLaneRestartChains, legacySpanBeats: Double, advanceStep: Bool,
                                      riffDir: RiffDir, stride: Int, length: Int, rotate: Int, seed: UInt64, every: Int = 1, bound: Int? = nil,
                                      restTies: Bool = true, fxTie: (_ column: Int, _ beat: Double, _ writtenRank: Int) -> Bool = { _, _, _ in false },
                                      timing: EuclideousHitTiming = .none,
                                      rankAt: (_ column: Int, _ beat: Double) -> Int) -> Double {
    euclideousChainTieExtensions(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains, legacySpanBeats: legacySpanBeats,
                                 advanceStep: advanceStep, riffDir: riffDir, stride: stride, length: length, rotate: rotate, seed: seed, every: every, bound: bound,
                                 restTies: restTies, fxTie: fxTie, timing: timing, rankAt: rankAt, notesStrikes: nil).riff
}
/// NOTES TAB ferry (2026-10-19) §8.4: the TIE lookahead, now with TWO answers. `riff` is the riff note's extension, exactly as before. `notes` is how far the notes the notes layer
/// strikes on this hit carry on: they carry through the tied hits until the first TIED REST on which the notes layer itself strikes (it re-strikes there, so what it struck before ends
/// at that hit as it would at an untied one). `notesStrikes(isRest, column, beat)` is asked, in order, about every scanned tied hit — it advances its own count k as it goes — and says
/// whether the notes strike there; an FX-tied real hit is asked too (isRest false) so the count stays right, and never stops the notes. nil = the notes carry exactly as far as the riff.
func euclideousChainTieExtensions(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                                  chains: EuclideousLaneRestartChains, legacySpanBeats: Double, advanceStep: Bool,
                                  riffDir: RiffDir, stride: Int, length: Int, rotate: Int, seed: UInt64, every: Int = 1, bound: Int? = nil,
                                  restTies: Bool = true, fxTie: (_ column: Int, _ beat: Double, _ writtenRank: Int) -> Bool = { _, _, _ in false },
                                  timing: EuclideousHitTiming = .none,
                                  rankAt: (_ column: Int, _ beat: Double) -> Int,
                                  notesStrikes: ((_ isRest: Bool, _ column: Int, _ beat: Double) -> Bool)?) -> (riff: Double, notes: Double) {
    var hitsAhead = 0
    var lastConsumed = 0
    var notesLast = 0
    // RHYTHM POLISH §5.2: lengths are measured to the tied hit's ACTUAL time — whole ticks plus the difference of the two hits' delays; `rankAt` is asked at that time too.
    let dThis = timing.isNone ? 0 : timing.delaySteps(raw: euclideousLaneChainPhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                                                                    legacySpanBeats: legacySpanBeats).raw)
    var lastDelay = 0.0, notesLastDelay = 0.0
    var notesStopped = notesStrikes == nil
    var j = 0
    // RIFF WALK ferry §5.5 (Euclideous row only — the retired/legacy fork passes no `bound`, keeping its
    // own original `length`-based cap byte-identical): the lookahead must reach the end of any run of tied
    // rests up to P × EVERY consecutive hits long (at most 64) — "scan as many laps as it takes to see
    // that many hits," so the tick-scan cap scales with the hit bound too (a maximally sparse pattern
    // needs up to one full cycle per hit).
    let hitsBound = bound ?? length
    let cap = cycleLen * hitsBound
    while hitsAhead < hitsBound && j < cap {
        j += 1
        let t = tick + Int64(j)
        let info = euclideousLaneChainTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: t, chains: chains,
                                           legacySpanBeats: legacySpanBeats, advanceStep: advanceStep)
        guard info.rawIsHit else { continue }
        let dJ = timing.isNone ? 0 : timing.delaySteps(raw: info.raw)
        // a melody restart always breaks the chain (§4.6: "no hit moves") — mirrors the old `locked &&`
        // guard exactly: only a non-FREE melody chain actually restarts periodically, so only then does
        // advOrd==0 mean "a restart just happened" rather than merely "the very first hit since beat 0."
        if !chains.melody.isFree, info.advOrd == 0 { break }
        hitsAhead += 1
        let column = euclideousRiffColumn(ordinal: info.advOrd, every: every, direction: riffDir, length: length, stride: stride, shift: rotate, seed: seed)
        let beatJ = (Double(t) + dJ) * sub
        let writtenJ = rankAt(column, beatJ)
        let isRest = writtenJ < 1
        if isRest {
            guard restTies else { break }
        } else {
            guard fxTie(column, beatJ, writtenJ) else { break }
        }
        if let ns = notesStrikes, !notesStopped {
            if ns(isRest, column, beatJ) { notesStopped = true } else { notesLast = j; notesLastDelay = dJ }
        }
        lastConsumed = j; lastDelay = dJ
    }
    func ext(_ j: Int, _ d: Double) -> Double { j == 0 ? 0 : (Double(j) + (timing.isNone ? 0 : d - dThis)) * sub }
    return (ext(lastConsumed, lastDelay), notesStrikes == nil ? ext(lastConsumed, lastDelay) : ext(notesLast, notesLastDelay))
}

/// RIFF WALK ferry (2026-10-19) §6.2: REPEAT's lookback — the column of the nearest EARLIER hit of this
/// lane, since the melody origin, whose written rank (read at THIS hit's own beat, §6.3 — never a
/// historical snapshot) isn't a rest. Pure, allocation-free, fixed-size work only; everything is derived
/// from `tick` and the lane's own values, never accumulated state (not the mask REPEAT's own
/// `euclideousLastSoundedNotes` cache — a different, pre-existing feature), so starting the transport at
/// any beat gives the same notes (test 11). Returns nil when the riff has no note anywhere right now, or
/// none is found within the bound (both cases play exactly as SKIP).
func euclideousRiffRepeatLookback(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64,
                                  chains: EuclideousLaneRestartChains, legacySpanBeats: Double, advanceStep: Bool,
                                  riffDir: RiffDir, stride: Int, length: Int, rotate: Int, seed: UInt64, every: Int,
                                  thisBeat: Double, rankAt: (_ column: Int, _ beat: Double) -> Int) -> (column: Int, rank: Int)? {
    let len = max(1, length)
    // §6.2's own early exit: "if no column the walk reaches has a note, the hit is silent at once."
    var anyNote = false
    for c in 0..<len where rankAt(c, thisBeat) >= 1 { anyNote = true; break }
    guard anyNote else { return nil }
    let here = euclideousLaneChainTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                       legacySpanBeats: legacySpanBeats, advanceStep: advanceStep)
    if !advanceStep {
        // ADV HIT: walk ordinals o−1, o−2, … at most EVERY × P of them (≤64) — covers the whole walk.
        let bound = min(64, euclideousFXWalkPeriod(dir: riffDir, length: len, stride: stride) * max(1, every))
        var j: Int64 = 1
        while j <= Int64(bound) {
            let o2 = here.advOrd - j
            guard o2 >= 0 else { break }
            let col = euclideousRiffColumn(ordinal: o2, every: every, direction: riffDir, length: len, stride: stride, shift: rotate, seed: seed)
            let r = rankAt(col, thisBeat)
            if r >= 1 { return (col, r) }
            j += 1
        }
        return nil
    } else {
        // ADV STEP: walk this lane's own earlier HITS backward in real time order (the Router's own hit
        // schedule — pass starts, rhythm restarts and muted hits all included via `euclideousLaneChainTick`
        // itself, which is already restart-aware per tick), at most 1024 of them, stopping at the melody
        // origin. Never assumes a regular lap across a restart (test 8f).
        let originTickM = euclideousLaneChainPhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains, legacySpanBeats: legacySpanBeats).originTickM
        var found = 0
        var t = tick - 1
        while t >= originTickM, found < 1024 {   // the origin tick itself is a searchable position (often the very first real hit, FREE-melody case included)
            let info = euclideousLaneChainTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: t, chains: chains,
                                               legacySpanBeats: legacySpanBeats, advanceStep: advanceStep)
            if info.rawIsHit {
                found += 1
                let col = euclideousRiffColumn(ordinal: info.advOrd, every: every, direction: riffDir, length: len, stride: stride, shift: rotate, seed: seed)
                let r = rankAt(col, thisBeat)
                if r >= 1 { return (col, r) }
            }
            t -= 1
        }
        return nil
    }
}

// MARK: - RIFF WALK ferry §7: the walk, the readout and what never plays (main-thread only, memoised on
// their inputs by the caller — these are NOT render-thread functions, unlike §5/§6 above).

@inline(__always) private func euclideousGcd64(_ a: Int64, _ b: Int64) -> Int64 { var x = abs(a), y = abs(b); while y != 0 { (x, y) = (y, x % y) }; return max(1, x) }
@inline(__always) private func euclideousLcm64(_ a: Int64, _ b: Int64) -> Int64 { abs(a / euclideousGcd64(a, b) * b) }

/// §7.3's own Q: "the number of passes in one rhythm cycle (1, one lap, with the rhythm chain FREE)" —
/// the same Q `euclideousPassIndex`/`euclideousPassStart` compute internally, factored out so §7 doesn't
/// re-derive it. Bounded: ≤ 4 rhythm-chain links.
func euclideousRhythmCycleQ(lapBeats: Double, barBeats: Double, rhythmChain: EuclideousRestartChain) -> Int64 {
    guard lapBeats > 0 else { return 1 }
    guard !rhythmChain.isFree, barBeats > 0 else { return 1 }
    let eps = 1e-9
    var Q: Int64 = 0
    var i = 0
    while i < rhythmChain.count { Q += Int64((Double(rhythmChain.link(i)) * barBeats / lapBeats - eps).rounded(.up)); i += 1 }
    return max(1, Q)
}

/// §7.2: pass `q`'s own footer list — (pattern step, riff column) for each of ITS hits, in time order,
/// from the Router's own per-hit functions (pass start/`euclideousPassStart`, the lane's hit steps, the
/// riff ordinal from the melody origin via `euclideousLaneChainTick`, and §5.2's `euclideousRiffColumn`).
/// Bounded by the NEXT pass's own start (not a fixed `cycleLen`-tick window), so a rhythm restart that
/// cuts THIS pass short is reflected automatically, with no separate "cut short" branch (§14 test 5).
func euclideousRiffFooterList(pass q: Int64, buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double,
                              chains: EuclideousLaneRestartChains, legacySpanBeats: Double, advanceStep: Bool,
                              riffDir: RiffDir, stride: Int, length: Int, shift: Int, every: Int, seed: UInt64) -> [(step: Int, column: Int)] {
    guard sub > 0 else { return [] }
    let lapBeats = Double(cycleLen) * sub
    let passStartTick = euclideousOriginTick(euclideousPassStart(q, lapBeats: lapBeats, barBeats: chains.barBeats, rhythmChain: chains.rhythm), sub: sub)
    let nextPassStartTick = euclideousOriginTick(euclideousPassStart(q + 1, lapBeats: lapBeats, barBeats: chains.barBeats, rhythmChain: chains.rhythm), sub: sub)
    var out: [(step: Int, column: Int)] = []
    var tick = passStartTick
    while tick < nextPassStartTick {
        let info = euclideousLaneChainTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains, legacySpanBeats: legacySpanBeats, advanceStep: advanceStep)
        if info.rawIsHit {
            let col = euclideousRiffColumn(ordinal: info.advOrd, every: every, direction: riffDir, length: length, stride: stride, shift: shift, seed: seed)
            out.append((info.raw, col))
        }
        tick += 1
    }
    return out
}

/// §7.3-§7.6: H (hits per rhythm cycle), J (the footer-repeat search bound) and d (the readout's own
/// number — "lines up every d passes") — nil when over budget (§7.4: J > 4096). `nil` H==0 is its own
/// case ("no hits to play"), reported by the caller, not folded into this return.
struct EuclideousRiffReadout {
    var hitsPerCycle: Int
    var period: Int64         // d
    var neverPlay: Set<Int>   // 0-based columns 0..<LEN no hit ever reads over the J passes examined
    var neverPlayWalkSteps: Set<Int>   // 0-based walk steps (mod P) no hit ever reads
}
func euclideousRiffReadout(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double,
                           chains: EuclideousLaneRestartChains, legacySpanBeats: Double, advanceStep: Bool,
                           riffDir: RiffDir, stride: Int, length: Int, shift: Int, every: Int, seed: UInt64) -> EuclideousRiffReadout? {
    guard sub > 0 else { return nil }
    let lapBeats = Double(cycleLen) * sub
    let P = Int64(euclideousFXWalkPeriod(dir: riffDir, length: length, stride: stride))
    let len = max(1, length)
    let Q = euclideousRhythmCycleQ(lapBeats: lapBeats, barBeats: chains.barBeats, rhythmChain: chains.rhythm)
    let cycleBeats = chains.rhythm.isFree ? lapBeats : Double(chains.rhythm.total) * chains.barBeats
    let cycleTicks = euclideousOriginTick(cycleBeats, sub: sub)
    var cycleHits = 0
    var s = 0
    while s < cycleLen { if buf[euclidReadIndex(s, n: n, dir: dir)] { cycleHits += 1 }; s += 1 }
    let H = Int(euclideousChainHitsBefore(cycleTicks, rhythm: chains.rhythm, barBeats: chains.barBeats, sub: sub, buf: buf, n: n, dir: dir, cycleLen: cycleLen, cycleHits: cycleHits))
    guard H > 0 else { return EuclideousRiffReadout(hitsPerCycle: 0, period: 0, neverPlay: [], neverPlayWalkSteps: []) }
    let A: Int64 = advanceStep ? cycleTicks : Int64(H)
    let M = P * Int64(max(1, every))
    let J: Int64 = chains.melody.isFree ? (Q * M / euclideousGcd64(M, A)) : euclideousLcm64(Q, Int64(chains.melody.total))
    guard J > 0, J <= 4096 else { return nil }   // §7.4: over budget
    var F: [[Int]] = []
    F.reserveCapacity(Int(J))
    var playedColumns = Set<Int>()
    var playedWalkSteps = Set<Int>()
    for q in 0..<J {
        let list = euclideousRiffFooterList(pass: q, buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, chains: chains,
                                            legacySpanBeats: legacySpanBeats, advanceStep: advanceStep, riffDir: riffDir,
                                            stride: stride, length: len, shift: shift, every: every, seed: seed)
        F.append(list.map { $0.column })
        for (_, col) in list { playedColumns.insert(col) }
    }
    // never-play: §7.6 — columns in the lane's own window (RIFF WINDOW ferry: LEN columns starting at SHIFT,
    // wrapping at 8 — no longer always 0...LEN) no hit reads over the J passes examined.
    var neverPlay = Set<Int>()
    for c in euclideousRiffWindowColumns(length: len, shift: shift) where !playedColumns.contains(c) { neverPlay.insert(c) }
    // the strip's own never-play set is in WALK-STEP space (w mod P), not column space — recompute the
    // walk steps actually visited by replaying each pass's own hit ordinals through euclideousRiffWalkStep.
    for q in 0..<J {
        let passStartTick = euclideousOriginTick(euclideousPassStart(q, lapBeats: lapBeats, barBeats: chains.barBeats, rhythmChain: chains.rhythm), sub: sub)
        let nextPassStartTick = euclideousOriginTick(euclideousPassStart(q + 1, lapBeats: lapBeats, barBeats: chains.barBeats, rhythmChain: chains.rhythm), sub: sub)
        var tick = passStartTick
        while tick < nextPassStartTick {
            let info = euclideousLaneChainTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains, legacySpanBeats: legacySpanBeats, advanceStep: advanceStep)
            if info.rawIsHit {
                let w = Int(((euclideousRiffWalkStep(ordinal: info.advOrd, every: every) % P) + P) % P)
                playedWalkSteps.insert(w)
            }
            tick += 1
        }
    }
    var neverPlayWalkSteps = Set<Int>()
    for w in 0..<Int(P) where !playedWalkSteps.contains(w) { neverPlayWalkSteps.insert(w) }
    // d: the smallest d >= 1 with F(q+d) == F(q) for every q — a divisor of J. Brute force over J's own
    // divisors (J <= 4096, so at most a few dozen divisors) rather than a KMP prefix function: simpler,
    // correct, and this only runs on a settings change, never per frame.
    var d = J
    var cand: Int64 = 1
    while cand < J {
        if J % cand == 0 {
            var ok = true
            var q: Int64 = 0
            while q < J - cand { if F[Int(q)] != F[Int(q + cand)] { ok = false; break }; q += 1 }
            if ok { d = cand; break }
        }
        cand += 1
    }
    return EuclideousRiffReadout(hitsPerCycle: H, period: d, neverPlay: neverPlay, neverPlayWalkSteps: neverPlayWalkSteps)
}
/// RIFF WALK ferry §7.2 asked for the readout to be MEMOISED on its inputs; it was recomputed on every SwiftUI body evaluation (≈30 Hz, once per lane by the lane card's mini-grid and once
/// more by its WALK strip — and, since the RIFF PANEL ferry, once more per lane by the rails' played set). One slot per lane, keyed on EVERY input `euclideousRiffReadout` reads, so a hit
/// returns the same answer the function would and any edit to a lane's pattern, rate, chains or riff settings recomputes it. A reference type the page keeps in `@State` (filling it never
/// invalidates the view); main thread only — these are not render-thread functions. `computeCount` is for the tests.
final class EuclideousRiffReadoutCache {
    struct Key: Equatable {
        var buf: [Bool], n: Int, dir: EuclidDir, sub: Double, chains: EuclideousLaneRestartChains, spanBeats: Double, advanceStep: Bool
        var riffDir: RiffDir, stride: Int, length: Int, shift: Int, every: Int, seed: UInt64
    }
    private var slots: [(key: Key, value: EuclideousRiffReadout?)?] = [nil, nil, nil, nil]
    private(set) var computeCount = 0
    private func compute(_ k: Key) -> EuclideousRiffReadout? {
        computeCount += 1
        return euclideousRiffReadout(buf: k.buf, n: k.n, dir: k.dir, cycleLen: euclidCycleLen(k.dir, n: k.n), sub: k.sub, chains: k.chains, legacySpanBeats: k.spanBeats,
                                     advanceStep: k.advanceStep, riffDir: k.riffDir, stride: k.stride, length: k.length, shift: k.shift, every: k.every, seed: k.seed)
    }
    func readout(lane: Int, cfg c: EuclideousWalkLaneConfig) -> EuclideousRiffReadout? {
        let key = Key(buf: c.buf, n: c.n, dir: c.dir, sub: c.sub, chains: c.chains, spanBeats: c.spanBeats, advanceStep: c.advanceStep,
                      riffDir: c.riffDir, stride: c.stride, length: c.length, shift: c.rotate, every: c.every, seed: c.seed)
        guard lane >= 0, lane < slots.count else { return compute(key) }
        if let hit = slots[lane], hit.key == key { return hit.value }
        let value = compute(key)
        slots[lane] = (key, value)
        return value
    }
}
/// §7.5: the readout's own text. `overBudget` is true when `euclideousRiffReadout` itself returned nil.
/// The "LINES UP EVERY n PASSES" wording is gone (Paul, 2026-10-22: "remove the labels that say things
/// like 'lines up every n steps'") — only the NEVER PLAY count still shows, kept in its own amber split
/// (a leading " · " with nothing before it, so `euclideousWalkReadoutText`'s existing split still paints
/// it amber without needing its own change).
func euclideousRiffReadoutText(_ r: EuclideousRiffReadout?, overBudget: Bool) -> String {
    if overBudget { return "CYCLE TOO LONG TO COUNT" }
    guard let r else { return "CYCLE TOO LONG TO COUNT" }
    if r.hitsPerCycle == 0 { return "NO HITS TO PLAY" }
    guard r.neverPlay.count >= 1 else { return "" }
    return " · \(r.neverPlay.count) NEVER PLAY"
}

/// RIFF WALK ferry §1.5: every RIFF-tab frame, from the content width and the two zones' heights — the ONE
/// pure function §1.3/§1.4/§1.6 describe. Reuses RHYTHM's own `patternBlockH`(80)/`upperH` split (§1.1: "the
/// RIFF tab now fills them exactly") rather than the ferry's own literal 124/208 reference figures, which
/// don't match the real `contentAreaH` formula — reported in the final write-up, not silently reconciled.
struct EuclideousRiffTabLayout: Equatable {
    var rowAHeight: CGFloat
    var rowBHeight: CGFloat
    var lowerRowHeight: CGFloat
    var rightColumnWidth: CGFloat
    var walkStripHeight: CGFloat
    var directionRowHeight: CGFloat
    var directionButtonWidth: CGFloat
    var labelColumnWidth: CGFloat
    var everyStepperWidth: CGFloat
    var hitStepButtonWidth: CGFloat
    var onRestButtonWidth: CGFloat
    var valueStepperWidth: CGFloat
    var underFloor: Bool   // §1.6's own floors: row A 82, direction row 32 tall, lower rows 32 tall, direction buttons 40 wide
}
func euclideousRiffTabLayout(contentAreaH: CGFloat, fullWidth: CGFloat, sp4: CGFloat = 4) -> EuclideousRiffTabLayout {
    let patternBlockH: CGFloat = 80   // the SAME fixed constant RHYTHM's own lower block uses
    let upperH = max(1, contentAreaH - patternBlockH - sp4)
    let rowBHeight: CGFloat = 38
    let rowAHeight = max(1, upperH - sp4 - rowBHeight)
    let lowerRowHeight = max(1, (patternBlockH - sp4) / 2)
    let cardWidth: CGFloat = 90
    let rightColumnWidth = max(1, fullWidth - cardWidth - sp4)
    let walkStripHeight: CGFloat = 38
    let directionRowHeight = max(1, rowAHeight - sp4 - walkStripHeight)
    let directionButtonWidth = max(1, (rightColumnWidth - 4 * sp4) / 5)
    let labelColumnWidth: CGFloat = 60
    let everyStepperWidth: CGFloat = 76
    let hitStepButtonWidth = max(1, (fullWidth - labelColumnWidth - everyStepperWidth - 3 * sp4) / 2)
    // NOTES TAB ferry §9.1: FILL left ON REST — three equal buttons (SKIP, TIE, REPEAT) sp4 apart after the label column and its gap: (fullWidth − 60 − 3·sp4) ÷ 3 = 88.83 at the 338.5 reference, 76 at 300.
    let onRestButtonWidth = max(1, (fullWidth - labelColumnWidth - 3 * sp4) / 3)
    let valueStepperWidth = max(1, (fullWidth - 3 * sp4) / 4)
    let underFloor = rowAHeight < 82 || directionRowHeight < 32 || lowerRowHeight < 32 || directionButtonWidth < 40
    return EuclideousRiffTabLayout(rowAHeight: rowAHeight, rowBHeight: rowBHeight, lowerRowHeight: lowerRowHeight,
                                   rightColumnWidth: rightColumnWidth, walkStripHeight: walkStripHeight,
                                   directionRowHeight: directionRowHeight, directionButtonWidth: directionButtonWidth,
                                   labelColumnWidth: labelColumnWidth, everyStepperWidth: everyStepperWidth,
                                   hitStepButtonWidth: hitStepButtonWidth, onRestButtonWidth: onRestButtonWidth,
                                   valueStepperWidth: valueStepperWidth, underFloor: underFloor)
}

/// A Euclideous lane's step length, step count and lap length exactly as `Router.runEuclidLine` derives them — a FOLLOWing lane ticks at
/// its partner's rate × the FOLLOW multiplier over the partner's step count. Reads fields only (no pattern is built), so the render
/// thread's mute edge-detect sweep can use it before any lane runs. `defaultRateBeats` stands in for a lane with no rate of its own.
func euclideousLaneStepGeometry(lines: [EuclidLine], lane: Int, defaultRateBeats: Double) -> (sub: Double, n: Int, cycleLen: Int) {
    guard lane >= 0, lane < lines.count else { return (defaultRateBeats, 8, 8) }
    let L = lines[lane]
    let n: Int, sub: Double
    if let partner = euclideousFollowPartner(lane: lane, lines: lines) {
        n = max(2, min(16, lines[partner].steps))
        sub = (lines[partner].rate?.beats ?? defaultRateBeats) * L.listenFollowRatioResolved
    } else {
        n = max(2, min(16, L.steps))
        sub = L.rate?.beats ?? defaultRateBeats
    }
    return (sub, n, euclidCycleLen(L.directionResolved, n: n))
}


// ── the LANES panel's pure maths (LANES GRID §3, §4, §5, §7) ─────────────────────────────────────────────────────────
//
// Everything the panel draws or hit-tests comes from here, so `LanesPanelPainter`/`EuclideousPage` only paint and route: the layout
// numbers, the position of a beat inside a lane's 16-cell window, which cell/row a touch lands on, the run outlines, the restart-mark
// beats shown on the MUTE tab, the edits a tap / stroke / rate-box tap make, the roll's feed, and the accessibility words.


/// §4: the panel's own geometry from the content area under the MIX | LANES tab strip. Horizontal sizes follow the spec's formula exactly
/// (rail 38, gap 4, then 16 cells with 2pt gaps across the rest — 20.125pt cells at the 394pt reference content width); the vertical
/// budget is the spec's (sub-tab row 24, gap 4, four lane blocks with 4 between, gap 4, legend 16) with the lane blocks taking whatever
/// height the real panel leaves — 50 at the reference, less on a short portrait panel (floor 34), more on a tall one. Nothing is a font size.
struct EuclideousLanesLayout: Equatable {
    static let railW: CGFloat = 38, railGap: CGFloat = 4, cellGap: CGFloat = 2
    static let subTabH: CGFloat = 24, subTabGap: CGFloat = 4, laneGap: CGFloat = 4, legendGap: CGFloat = 4, legendH: CGFloat = 16
    static let restartRowGap: CGFloat = 2
    static let minLaneH: CGFloat = 34
    let width: CGFloat
    let height: CGFloat
    let laneH: CGFloat
    var gridX: CGFloat { Self.railW + Self.railGap }
    var gridW: CGFloat { max(0, width - gridX) }
    var cellW: CGFloat { max(0.5, (gridW - Self.cellGap * 15) / 16) }
    var pitch: CGFloat { cellW + Self.cellGap }
    var rowH: CGFloat { (laneH - Self.restartRowGap) / 2 }
    /// The left edge of cell `i` measured from the GRID's own left edge (`cellLeft(i) = i × 22.125` at the reference).
    func cellLeft(_ i: Int) -> CGFloat { CGFloat(i) * pitch }
    func laneTop(_ lane: Int) -> CGFloat { Self.subTabH + Self.subTabGap + CGFloat(lane) * (laneH + Self.laneGap) }
    var legendTop: CGFloat { laneTop(3) + laneH + Self.legendGap }
}
func euclideousLanesLayout(width: CGFloat, height: CGFloat) -> EuclideousLanesLayout {
    let fixed = EuclideousLanesLayout.subTabH + EuclideousLanesLayout.subTabGap + EuclideousLanesLayout.laneGap * 3
        + EuclideousLanesLayout.legendGap + EuclideousLanesLayout.legendH
    return EuclideousLanesLayout(width: width, height: height, laneH: max(EuclideousLanesLayout.minLaneH, (height - fixed) / 4))
}

/// §4.4/§2.9 — where a beat sits inside a lane's 16-unit window: `u = (beat mod window) / unit`, `i = min(15, floor(u))`,
/// `x = cellLeft(i) + (u − i) × cellW` (so the playhead jumps the 2pt gaps — intended). Derived from the transport beat, never a timer.
struct EuclideousLanesPosition: Equatable { var cell: Int; var u: Double; var x: CGFloat }
func euclideousLanesPosition(beat: Double, unitBeats: Double, layout: EuclideousLanesLayout) -> EuclideousLanesPosition {
    guard unitBeats > 0 else { return EuclideousLanesPosition(cell: 0, u: 0, x: 0) }
    let units = beat / unitBeats
    let u = units - 16 * (units / 16).rounded(.down)
    let i = min(15, max(0, Int(u.rounded(.down))))
    return EuclideousLanesPosition(cell: i, u: u, x: layout.cellLeft(i) + CGFloat(u - Double(i)) * layout.cellW)
}
/// The window a roll covers on the active sub-tab (§3.2): `16 × unit`, starting at `floor(beat / window) × window`.
func euclideousLanesWindow(beat: Double, unitBeats: Double) -> (start: Double, length: Double) {
    guard unitBeats > 0 else { return (0, 0) }
    let window = 16 * unitBeats
    return ((beat / window).rounded(.down) * window, window)
}

/// What a touch is over. `row` is 0 on MUTE (the whole block) and 0 = RHYTHM / 1 = MELODY on RESTART.
struct EuclideousLanesHit: Equatable { var lane: Int; var cell: Int; var row: Int }
/// §5.3 — the hit test, with the same cell-width and gap formula the grid draws with. Each cell's area extends 1pt into the gaps on each
/// side (so the 2pt gaps are fully claimed), and on RESTART the rhythm row extends 1pt into the 2pt gap between the rows (the melody row
/// takes the other 1pt). (x, y) are in the panel content's own coordinates. Nil outside any lane block or the grid.
func euclideousLanesHit(x: CGFloat, y: CGFloat, layout: EuclideousLanesLayout, restart: Bool) -> EuclideousLanesHit? {
    for lane in 0..<4 {
        let top = layout.laneTop(lane)
        guard y >= top, y <= top + layout.laneH else { continue }
        guard let cell = euclideousLanesCellAt(x: x, layout: layout) else { return nil }
        let row = restart ? (y - top < layout.rowH + 1 ? 0 : 1) : 0
        return EuclideousLanesHit(lane: lane, cell: cell, row: row)
    }
    return nil
}
/// The cell a given x is over (cells claim 1pt of the gap on each side); nil left of the grid or right of the last cell.
func euclideousLanesCellAt(x: CGFloat, layout: EuclideousLanesLayout) -> Int? {
    let gx = x - layout.gridX
    guard gx >= -1, gx < layout.gridW + 1, layout.pitch > 0 else { return nil }
    return min(15, max(0, Int(((gx + 1) / layout.pitch).rounded(.down))))
}
/// A stroke continuing inside the lane it began in (§5.2): the finger's x gives the cell (clamped to the grid ends), its y — clamped to the
/// lane block — gives the row on RESTART. Nil only if the grid has no width.
func euclideousLanesStrokeHit(x: CGFloat, y: CGFloat, lane: Int, layout: EuclideousLanesLayout, restart: Bool) -> EuclideousLanesHit? {
    guard lane >= 0, lane < 4, layout.pitch > 0 else { return nil }
    let top = layout.laneTop(lane)
    let ly = min(max(y, top), top + layout.laneH)
    let cell = euclideousLanesCellAt(x: min(max(x, layout.gridX), layout.gridX + layout.gridW - 0.001), layout: layout) ?? 0
    return EuclideousLanesHit(lane: lane, cell: cell, row: restart ? (ly - top < layout.rowH + 1 ? 0 : 1) : 0)
}

/// §4.9 — one restart-to-restart run on a row, as cells `[start, end)`. SOLID runs start on a mark; a run that begins at cell 0 WITHOUT a
/// mark there (carried over from the previous window, §2.3) is DASHED up to the first mark; a row with no marks is ONE dashed run around
/// all 16 cells.
struct EuclideousLanesRun: Equatable { var start: Int; var end: Int; var dashed: Bool }
func euclideousLanesRuns(mask: UInt16) -> [EuclideousLanesRun] {
    let marks = (0..<16).filter { (mask >> UInt16($0)) & 1 != 0 }
    guard let first = marks.first else { return [EuclideousLanesRun(start: 0, end: 16, dashed: true)] }
    var runs: [EuclideousLanesRun] = []
    if first > 0 { runs.append(EuclideousLanesRun(start: 0, end: first, dashed: true)) }
    for (k, m) in marks.enumerated() { runs.append(EuclideousLanesRun(start: m, end: k + 1 < marks.count ? marks[k + 1] : 16, dashed: false)) }
    return runs
}
/// §4.8 — the beats at which a lane's restart marks fall inside `[windowStart, windowStart + windowBeats)`: each mark repeats every restart
/// period (16 restart units), so the MUTE tab (whose window is 16 MUTE units) shows them wherever they land.
func euclideousLanesMarkBeats(mask: UInt16, restartUnitBeats: Double, windowStart: Double, windowBeats: Double) -> [Double] {
    guard mask != 0, restartUnitBeats > 0, windowBeats > 0 else { return [] }
    let period = 16 * restartUnitBeats
    var out: [Double] = []
    var k = Int((windowStart / period).rounded(.down))
    while Double(k) * period < windowStart + windowBeats {
        for c in 0..<16 where (mask >> UInt16(c)) & 1 != 0 {
            let b = Double(k) * period + Double(c) * restartUnitBeats
            if b >= windowStart - 1e-9 && b < windowStart + windowBeats - 1e-9 { out.append(b) }
        }
        k += 1
    }
    return out
}

/// §5 — every edit the panel makes to a lane, as one value. Applying one FIRST pins all five grid fields from the lane's resolved view
/// (so a pre-feature lane's migrated values become its stored values, whatever the old fields hold later), then writes.
enum EuclideousLaneGridOp: Equatable {
    case mute(cell: Int, on: Bool)
    case restart(melody: Bool, cell: Int, on: Bool)
    case nextMuteUnit
    case nextRestartUnit
}
func euclideousApplyLaneGridOp(_ line: inout EuclidLine, resolved: EuclideousLaneGrid, _ op: EuclideousLaneGridOp) {
    // Pin ONCE: a stroke applies many ops against one `resolved` snapshot taken at touch-down — after the first, the lane's own stored
    // fields are the truth, and re-pinning the stale snapshot would overwrite the cells the stroke just painted.
    if !line.usesLaneGrid { euclideousPinLaneGrid(&line, resolved) }
    func set(_ bits: UInt16?, _ cell: Int, _ on: Bool) -> UInt16 {
        let b = UInt16(1) << UInt16(max(0, min(15, cell)))
        return on ? ((bits ?? 0) | b) : ((bits ?? 0) & ~b)
    }
    switch op {
    case .mute(let cell, let on): line.muteCells16 = set(line.muteCells16, cell, on)
    case .restart(let melody, let cell, let on):
        if melody { line.restartMelodyMask16 = set(line.restartMelodyMask16, cell, on) }
        else { line.restartRhythmMask16 = set(line.restartRhythmMask16, cell, on) }
    case .nextMuteUnit: line.muteUnit = resolved.muteUnit.next.rawValue
    case .nextRestartUnit: line.restartUnit = resolved.restartUnit.next.rawValue
    }
}
/// The current value of the cell a stroke starts on (the stroke then paints the OPPOSITE, §5.2).
func euclideousLaneGridCellValue(_ g: EuclideousLaneGrid, restart: Bool, melody: Bool, cell: Int) -> Bool {
    let bit = UInt16(1) << UInt16(max(0, min(15, cell)))
    if !restart { return g.muteCells & bit != 0 }
    return (melody ? g.melodyMask : g.rhythmMask) & bit != 0
}

/// A lane's grid as the page must read it: resolved against the lane's own live step / lap, the host bar and the pre-feature sequencer
/// fields — the same call the Router and the mirror make, so the panel, the roll and the engine can never disagree about a lane.
struct EuclideousLaneGridView: Equatable {
    var grid: EuclideousLaneGrid
    var sub: Double
    var cycleLen: Int
    var muteUnitBeats: Double
    var restartUnitBeats: Double
}
func euclideousLaneGridView(lines: [EuclidLine], lane: Int, legacy: EuclideousLanesSeq, defaultRateBeats: Double, beatsPerBar: Double) -> EuclideousLaneGridView {
    let geo = euclideousLaneStepGeometry(lines: lines, lane: lane, defaultRateBeats: defaultRateBeats)
    let pass = Double(geo.cycleLen) * geo.sub
    let line = lane >= 0 && lane < lines.count ? lines[lane] : EuclidLine()
    let g = euclideousLaneGridResolved(line: line, lane: lane, legacyOn: legacy.on, legacyRate: legacy.rate, legacyLen: legacy.len,
                                       legacyCells: legacy.cells, stepBeats: geo.sub, passBeats: pass, beatsPerBar: beatsPerBar)
    return EuclideousLaneGridView(grid: g, sub: geo.sub, cycleLen: geo.cycleLen,
                                  muteUnitBeats: g.muteUnit.beats(stepBeats: geo.sub, passBeats: pass),
                                  restartUnitBeats: g.restartUnit.beats(stepBeats: geo.sub, passBeats: pass))
}

// ── accessibility + legend words (§7, §4.10) ───────────────────────────────────────────────────────────────────────────
func euclideousLanesMuteCellLabel(lane: Int, cell: Int, sounding: Bool) -> String { "Lane \(lane + 1) cell \(cell + 1), \(sounding ? "sounding" : "muted")" }
func euclideousLanesRestartCellLabel(lane: Int, cell: Int, melody: Bool, set: Bool) -> String {
    "Lane \(lane + 1) cell \(cell + 1) \(melody ? "melody" : "rhythm") restart, \(set ? "set" : "not set")"
}
func euclideousLanesRateBoxLabel(lane: Int, unit: String) -> String { "Lane \(lane + 1) cell size \(unit)" }
let euclideousLanesRestartHint = "TOP ROW = RHYTHM RESTART. BOTTOM ROW = MELODY RESTART."

// ── the roll (§3) ──────────────────────────────────────────────────────────────────────────────────────────────────────
/// One hit of the picture behind the cells: where it falls, which riff rank it reads (0 = it sounds nothing from the riff — a rest, or the
/// riff is off), how long it is held (the tie extension included), and whether the lane is audible at that beat.
struct EuclideousRollHit: Equatable {
    var beat: Double
    var rank: Int
    var gateBeats: Double
    var audible: Bool
    // FX TAB (2026-10-18): a ratcheted hit is drawn as its `strikes` strikes, `spacingBeats` apart, each `gateBeats` long (the last one `lastGateBeats` when a tie
    // extends it; 0 = same as `gateBeats`). 1 / 0 / 0 for every ordinary hit.
    var strikes: Int = 1
    var spacingBeats: Double = 0
    var lastGateBeats: Double = 0
}
/// §3.1 — the hits of one lane in `[windowStart, windowStart + windowBeats)`. Built ONLY from the shared pieces the Router calls per hit:
/// the walk mirror (`euclideousWalkTick` = `euclideousLaneTick`), `rankAt` (the effective rank at a riff column and beat — the looper-aware
/// read), `euclideousNextHitGapBeats`, `euclideousRiffTieExtensionBeats`, `euclideousPitchGateBeats` and `euclideousLaneAudible`. Pure and
/// side-effect free; the page caches the result per (lane inputs, window) and never recomputes per frame. A lane that cannot be honoured
/// exactly: SHADOW lanes (their pitch comes from the partner, so the roll shows the lane's OWN riff column), an AVOID-muted pick, and a
/// FILL hit (it strikes the lane's own NOTE pick, which the rank axis cannot show) — those draw as rests (rank 0).
func euclideousLaneRollHits(cfg c: EuclideousWalkLaneConfig, windowStart: Double, windowBeats: Double, minGateBeats: Double,
                            rankAt: (_ column: Int, _ beat: Double) -> Int) -> [EuclideousRollHit] {
    guard c.sub > 0, c.n > 0, windowBeats > 0 else { return [] }
    let cycleLen = euclidCycleLen(c.dir, n: c.n)
    let laneHasNoteFX = c.fx.rowHasCells(4, lane: c.lane)
    let laneHasTieFX = c.fx.rowHasCells(2, lane: c.lane)
    let fxLive = c.playsRiff && c.riffOn && !c.fx.isInert
    var tick = Int64((windowStart / c.sub - 1e-9).rounded(.up))
    var out: [EuclideousRollHit] = []
    while true {
        let beat = Double(tick) * c.sub
        if beat >= windowStart + windowBeats - 1e-9 { break }
        defer { tick += 1 }
        let w = euclideousWalkTick(c, tick: tick)
        guard w.strikes else { continue }
        // RHYTHM POLISH: the hit sounds its delay into the cell — everything below is asked at THAT time, as the Router asks it.
        let hitBeat = c.timing.isNone ? beat : beat + c.timing.delaySteps(raw: euclideousLaneChainPhase(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: c.sub, tick: tick,
                                                                                                         chains: c.chains, legacySpanBeats: c.spanBeats).raw) * c.sub
        // The SAME decision the Router makes per hit (§2.3): the column the walk reads, the written rank there, the pass index, then `euclideousFXApply`.
        let written = c.riffOn ? rankAt(w.playedStep, hitBeat) : 0
        var fxHit = EuclideousFXHit()
        if fxLive {
            let pass = laneHasNoteFX ? euclideousFXPassIndex(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: c.sub, tick: tick, grid: c.grid,
                                                              legacySpanBeats: c.spanBeats, locked: c.locked, advanceStep: c.advanceStep,
                                                              riffDir: c.riffDir, stride: c.stride, length: c.length, every: c.every) : 0
            fxHit = euclideousFXApply(c.fx, lane: c.lane, playsRiff: true, column: w.playedStep, writtenRank: written, pass: pass)
        }
        if fxHit.tie { continue }                      // a tied hit does not strike: no bar of its own (the previous bar's length covers it)
        var rank = 0
        if c.riffOn {
            rank = euclideousRiffStepRanks(ranks: [written], invert: c.invert, transpose: c.transpose)[0]
            if fxHit.noteOffset != 0 && written >= 1 { rank = max(1, min(8, rank + fxHit.noteOffset)) }   // drawing only: NOTE's offset, clamped to the 1–8 rows
        }
        let g = fxHit.gatePct.map { Double($0) / 100 } ?? c.gate
        let gap = euclideousNextChainHitGapBeats(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: c.sub, tick: tick, cap: cycleLen * 4,
                                                  chains: c.chains, legacySpanBeats: c.spanBeats, timing: c.timing)
        var tie = 0.0
        if rank >= 1, c.onRest == .tie || laneHasTieFX {
            tie = euclideousChainTieExtensionBeats(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: c.sub, tick: tick, chains: c.chains,
                                                  legacySpanBeats: c.spanBeats, advanceStep: c.advanceStep,
                                                  riffDir: c.riffDir, stride: c.stride, length: c.length, rotate: c.rotate, seed: c.seed,
                                                  restTies: c.onRest == .tie,
                                                  fxTie: { col, _, r in
                                                      laneHasTieFX && euclideousFXApply(c.fx, lane: c.lane, playsRiff: true, column: col, writtenRank: r, pass: 0).tie
                                                  },
                                                  timing: c.timing,
                                                  rankAt: rankAt)
        }
        let audible = euclideousLaneAudible(beat: hitBeat, cells16: c.muteCells, unitBeats: c.muteUnitBeats)
        let nStrikes = rank >= 1 && fxHit.ratch >= 2 ? euclideousFXRatchetCount(requested: fxHit.ratch, sub: c.sub, cyc: c.cyc) : 0
        if nStrikes >= 2 {
            let slot = c.sub / Double(nStrikes)
            let per = max(minGateBeats, slot * g)
            let last = tie > 0 ? max(per, (gap - Double(nStrikes - 1) * slot) + g * tie) : per
            out.append(EuclideousRollHit(beat: hitBeat, rank: max(0, rank), gateBeats: per, audible: audible, strikes: nStrikes, spacingBeats: slot, lastGateBeats: last))
        } else {
            out.append(EuclideousRollHit(beat: hitBeat, rank: max(0, rank), gateBeats: euclideousPitchGateBeats(gate: g, nextHitGapBeats: gap, tieExt: tie, minGateBeats: minGateBeats),
                                         audible: audible))
        }
    }
    return out
}
/// §4.6 — a roll bar's vertical position: `y = 4 + (8 − rank) × 5` from the lane block's top (rank 1 lowest, 8 highest). A rest / no-rank
/// hit sits on the middle line (`22pt`, §3.3). The block scales with the real lane height; the 3pt bar height does not.
func euclideousRollBarY(rank: Int, laneH: CGFloat) -> CGFloat {
    let scale = laneH / 50
    if rank < 1 { return 22 * scale }
    return (4 + CGFloat(8 - min(8, rank)) * 5) * scale
}

// ── the footer's lap baseline and the comet's phase, from the same core (§2.5, §2.8) ──────────────────────────────────
/// The riff ordinal the CURRENT rhythm lap's first hit reads — the footer's baseline, taken from the core with BOTH origins instead of
/// being reverse-derived from the polled ordinal (which a melody restart would break). The lap is the one containing the latest tick at or
/// before `beat`; nil if the pattern has no hit. Restarts that fall INSIDE the lap are not foreseen (the prediction stays oblivious to
/// them, §2.8), exactly as before.
func euclideousLapStartOrdinal(cfg c: EuclideousWalkLaneConfig, beat: Double) -> Int64? { euclideousLapStart(cfg: c, beat: beat)?.ordinal }
/// LANE STRIP ferry: the same lap, with the ABSOLUTE tick of its first step (raw 0) as well — a hit of the shown pass sits at `lapStartTick + hit.tick`, which is how the strip asks the notes
/// functions (k, the hit ordinal) and REPEAT's lookback about that hit.
func euclideousLapStart(cfg c: EuclideousWalkLaneConfig, beat: Double) -> (lapStartTick: Int64, ordinal: Int64)? {
    guard c.sub > 0, c.n > 0 else { return nil }
    let cycleLen = euclidCycleLen(c.dir, n: c.n)
    let tick = Int64((beat / c.sub).rounded(.down))
    let now = euclideousLaneChainTick(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: c.sub, tick: tick, chains: c.chains,
                                      legacySpanBeats: c.spanBeats, advanceStep: c.advanceStep)
    let lapStart = tick - Int64(now.raw)
    for r in 0..<cycleLen where c.buf[euclidReadIndex(r, n: c.n, dir: c.dir)] {
        let ord = euclideousLaneChainTick(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: c.sub, tick: lapStart + Int64(r), chains: c.chains,
                                          legacySpanBeats: c.spanBeats, advanceStep: c.advanceStep).advOrd
        return (lapStart, ord)
    }
    return nil
}
/// The comet's continuous position in its cycle at `beat`, measured from the RHYTHM origin — the lane card's comet and hit flashes read this
/// (instead of the legacy span re-anchor), so they agree with the pattern the engine is really playing across a restart.
func euclideousLaneCometRaw(beat: Double, n: Int, dir: EuclidDir, sub: Double, grid: EuclideousLaneRestartGrid, legacySpanBeats: Double) -> Double {
    guard sub > 0, n > 0 else { return 0 }
    let cycleLen = euclidCycleLen(dir, n: n)
    let ticks = beat / sub
    let tick = Int64(ticks.rounded(.down))
    let buf = [Bool](repeating: false, count: max(1, n))
    let ph = euclideousLanePhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, grid: grid, legacySpanBeats: legacySpanBeats)
    let raw = Double(ph.localT) + (ticks - Double(tick))
    let cl = Double(cycleLen)
    return raw - cl * (raw / cl).rounded(.down)
}
/// RESTART CHAINS (ferry 2026-10-19): the chain-era counterpart of `euclideousLaneCometRaw` above — the ONLY real call
/// site (the lane card's comet sweep, `EuclidLaneUI.swift`) now reads this instead; the old grid-based function stays
/// untouched for `LanesGridTests.swift`'s own byte-identical coverage of the grid model.
func euclideousLaneCometChainRaw(beat: Double, n: Int, dir: EuclidDir, sub: Double, chains: EuclideousLaneRestartChains, legacySpanBeats: Double) -> Double {
    guard sub > 0, n > 0 else { return 0 }
    let cycleLen = euclidCycleLen(dir, n: n)
    let ticks = beat / sub
    let tick = Int64(ticks.rounded(.down))
    let buf = [Bool](repeating: false, count: max(1, n))
    let ph = euclideousLaneChainPhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains, legacySpanBeats: legacySpanBeats)
    let raw = Double(ph.localT) + (ticks - Double(tick))
    let cl = Double(cycleLen)
    return raw - cl * (raw / cl).rounded(.down)
}


// MARK: - FX TAB engine (ferry 2026-10-18) — the one per-hit decision, the NOTE pass index, and their small helpers
//
// ONE function (`euclideousFXApply`) decides what the six rows do to a hit; the Router calls it per hit, the TIE lookahead calls it for each future hit,
// the LANES roll calls it for every bar, the FX tab's firing flash and VoiceOver call it — nobody re-derives any of it (§2.3). Everything is pure,
// allocation-free and a function of the beat, the origins and the snapshot (§9.2).

enum EuclideousFXRow: Int, CaseIterable {
    case ratch = 0, gate, tie, vel, note, cc
    /// The row's cell value after a double-tap (§12.3), and its brush's starting value (§12.5).
    var defaultValue: Int { switch self { case .ratch: return 2; case .gate: return 50; case .tie: return 1; case .vel: return 100; case .note: return 1; case .cc: return 64 } }
}

/// What the rows do to ONE hit that plays the riff. `appliedRows` has bit r set when row r's CELL had a value that applied (the firing flash reads it); a BASE
/// send has no cell, so it sets no bit. A TIE hit short-circuits everything (`tie == true`, nothing else set — not even a CC).
struct EuclideousFXHit: Equatable {
    var tie = false
    var ratch = 0              // 0 = none, else 2…4 strikes
    var gatePct: Int? = nil    // 5…95 (no legato since 2026-10-20)
    var vel: Int? = nil        // 1…127
    var noteStep = 0           // s (−3…−1, +1…+3), 0 = no NOTE cell applied
    var noteOffset = 0         // s × (pass mod PASSES) — what the riff rank moves by on this hit
    var cc: Int? = nil         // the controller value to send (the cell's, else BASE), nil = send nothing
    var appliedRows: UInt8 = 0
}

/// Which riff columns (bit c = column c, 0-based) an FX TIE cell turns into a tied hit for `lane` — what the lane footer and comet bar need to draw those hits as
/// hits on a tied rest (§13.2). Zero for a lane that doesn't play the riff or isn't on the TIE row. TIE doesn't depend on the pass, so this is static.
func euclideousFXTieColumns(_ fx: EuclideousFX, line: EuclidLine, lane: Int) -> UInt8 {
    guard euclideousLanePlaysRiff(line), fx.laneOn(row: 2, lane: lane) else { return 0 }
    var m: UInt8 = 0
    for c in 0..<8 where fx.cell(row: 2, column: c) != nil { m |= UInt8(1) << UInt8(c) }
    return m
}
/// "The lane plays the riff": its riff layer is on and it isn't SHADOWing a partner (the shadow branch REPLACES the riff layer). The one definition the
/// Router's gate, the roll and the walk tags share.
func euclideousLanePlaysRiff(_ line: EuclidLine) -> Bool { line.riffOnResolved && line.listenPitchMode != .shadow }

/// §2.2/§2.3 — what the rows do to a hit on `lane` that reads riff `column` (0…7) whose WRITTEN rank (before INVERT and before the NOTE offset) is
/// `writtenRank`; `pass` is the hit's NOTE pass index (7.2; only read when a NOTE cell applies). Applies only when (a) the row has the lane on, (b) the
/// lane plays the riff, (c) the written rank is not a rest, (d) the row's cell holds a value. TIE wins outright; the CC row also acts on BASE.
func euclideousFXApply(_ fx: EuclideousFX, lane: Int, playsRiff: Bool, column: Int, writtenRank: Int, pass: Int) -> EuclideousFXHit {
    var hit = EuclideousFXHit()
    guard playsRiff, writtenRank >= 1, column >= 0, column < 8, lane >= 0, lane < 4 else { return hit }
    if fx.laneOn(row: 2, lane: lane), fx.cell(row: 2, column: column) != nil { hit.tie = true; return hit }
    if fx.laneOn(row: 0, lane: lane), let v = fx.cell(row: 0, column: column) { hit.ratch = max(2, min(4, v)); hit.appliedRows |= 1 << 0 }
    if fx.laneOn(row: 1, lane: lane), let v = fx.cell(row: 1, column: column) { hit.gatePct = max(5, min(EuclideousFX.gateMax, v)); hit.appliedRows |= 1 << 1 }   // 5…95: the GATE row has no legato (2026-10-20)
    if fx.laneOn(row: 3, lane: lane), let v = fx.cell(row: 3, column: column) { hit.vel = max(1, min(127, v)); hit.appliedRows |= 1 << 3 }
    if fx.laneOn(row: 4, lane: lane), let v = fx.cell(row: 4, column: column), v != 0 {
        let passes = max(2, min(8, Int(fx.notePasses)))
        hit.noteStep = v
        hit.noteOffset = v * (((pass % passes) + passes) % passes)
        hit.appliedRows |= 1 << 4
    }
    if fx.laneOn(row: 5, lane: lane) {
        if let v = fx.cell(row: 5, column: column) { hit.cc = max(0, min(127, v)); hit.appliedRows |= 1 << 5 }
        else if fx.ccBase >= 0 { hit.cc = max(0, min(127, Int(fx.ccBase))) }
    }
    return hit
}

/// The lit notes' velocity under an FX VEL `v`: v plus the NOTES VEL bar's displayed offset (`notesVelocity − VEL`, clamped ±64 exactly as the bar shows it),
/// clamped to 1…127 (§6.1).
func euclideousFXLitVelocity(fxVel v: Int, notesVelocity: Int, velocityAbsolute: Int) -> UInt8 {
    let off = max(-64, min(64, notesVelocity - velocityAbsolute))
    return UInt8(max(1, min(127, v + off)))
}

/// The RATCH beat-width cap — the mask RATCHET's own rule, factored out so both read ONE formula: no strike slot shorter than 1/128 of the scene grid's bar
/// (`cyc` = stepRate × columns, NOT the host bar), never below 1.
func euclideousRatchetCap(sub: Double, cyc: Double) -> Int { max(1, Int(sub * 128.0 / max(0.0001, cyc))) }
/// FX RATCH's strike count: exactly the cell's n (no roll, no legal-size clamp), lowered only by the cap; fewer than 2 strikes is a plain hit (0).
func euclideousFXRatchetCount(requested n: Int, sub: Double, cyc: Double) -> Int {
    let c = min(n, euclideousRatchetCap(sub: sub, cyc: cyc))
    return c >= 2 ? c : 0
}

/// riffResolve's fold, extended DOWNWARD for FX-moved ranks (§7.3). `riffResolve` returns nil (a rest) for any rank below 1 — correct for a written rest and
/// left untouched — so a NOTE-moved rank that lands at 0 or below needs this: floor-division folds it into the octave below (with C3 E♭3 G3 held, rank 0 is G2,
/// rank −2 is C2). Identical to `riffResolve(wrap: .fold)` for rank ≥ 1 (rank 9 = G5). Never traps; the caller's pitch-range handling decides what a huge result does.
@inline(__always) func riffResolveExtended(rank: Int, oct: Int, n: Int, asc: (Int) -> Int) -> Int? {
    guard n > 0 else { return nil }
    let idx0 = rank - 1
    var laps = idx0 / n
    var over = idx0 - laps * n
    if over < 0 { over += n; laps -= 1 }
    return asc(over) + 12 * laps + 12 * oct
}

// ── the NOTE pass index (§7.2) ────────────────────────────────────────────────────────────────────────────────────────

private func euclideousFXGcd(_ a: Int, _ b: Int) -> Int { var x = abs(a), y = abs(b); while y != 0 { (x, y) = (y, x % y) }; return max(1, x) }
/// The riff walk's period in ORDINALS: `D / gcd(D, STRIDE)` where D is `riffStepAt`'s own modulus for the direction — FWD/REV `LENGTH`, PEND `2·LENGTH − 2`,
/// PING `2·LENGTH`; 1 when LENGTH is 1. (RANDOM/DRUNK can't reach Euclideous — `euclideousRiffDirResolved` coerces them to FWD — and use FWD's period.)
func euclideousFXWalkPeriod(dir: RiffDir, length: Int, stride: Int) -> Int {
    let l = max(1, length)
    if l == 1 { return 1 }
    let d: Int
    switch dir {
    case .forward, .reverse, .random, .drunk: d = l
    case .pendulum: d = 2 * l - 2
    case .pingpong: d = 2 * l
    }
    return d / euclideousFXGcd(d, max(1, stride))
}
/// FREE: `p = floor(o / P)`, `o` the riff ordinal the Router feeds `riffStepAt` (counted from the melody origin).
func euclideousFXFreePass(advOrd: Int64, period: Int) -> Int {
    Int(floorDiv(advOrd, Int64(max(1, period))))
}
/// LOCK: `p` = the number of LOCK resets — Euclid lap starts — strictly AFTER the melody origin and at or before this tick. A lap starts at every multiple of
/// `cycleLen` ticks from the RHYTHM origin, and a rhythm mark starts a fresh lap. In CLOSED FORM (never a loop over laps): the rhythm segments repeat every
/// 16 restart cells, so `L(x)` (lap starts ≤ x) is whole windows × lap starts per window + a walk over at most 17 segments.
func euclideousFXLockPass(tick: Int64, cycleLen: Int, grid: EuclideousLaneRestartGrid, localT: Int64) -> Int {
    let cl = Int64(max(1, cycleLen))
    guard grid.isActive else { return Int(floorDiv(localT, cl)) }          // one origin (the legacy span or beat 0): laps since it
    let u = Int64(grid.unitTicks)
    let absCell = Int(floorDiv(tick, u))
    let cellM = grid.melodyMask != 0 ? (euclideousMaskedResetCell(absCell: absCell, mask: grid.melodyMask) ?? 0) : 0
    let m = Int64(cellM) * u                                               // the melody origin, in absolute ticks
    if grid.rhythmMask == 0 { return Int(floorDiv(tick, cl) - floorDiv(m, cl)) }   // the rhythm origin is beat 0: laps at multiples of cl
    return Int(euclideousLapStartsUpTo(tick, rhythmMask: grid.rhythmMask, unitTicks: u, cycleLen: cl) - euclideousLapStartsUpTo(m, rhythmMask: grid.rhythmMask, unitTicks: u, cycleLen: cl))
}
/// L(x): lap starts at or before absolute tick `x`, relative to a consistent baseline (only DIFFERENCES are meaningful). Segments are the rhythm marks'
/// own (the carried segment before the window's first mark runs from the previous window's last mark); a segment starting at `a` has lap starts at `a + k·cl`.
private func euclideousLapStartsUpTo(_ x: Int64, rhythmMask: UInt16, unitTicks u: Int64, cycleLen cl: Int64) -> Int64 {
    let window = 16 * u
    var first = -1, last = -1
    for c in 0..<16 where (rhythmMask >> UInt16(c)) & 1 != 0 { if first < 0 { first = c }; last = c }
    guard first >= 0 else { return floorDiv(x, cl) }
    /// lap starts at a + k·cl (k ≥ 0) inside [lo, hi], where the segment began at `a`
    func inSegment(a: Int64, lo: Int64, hi: Int64) -> Int64 {
        guard hi >= lo else { return 0 }
        let jmax = floorDiv(hi - a, cl)
        let jmin: Int64 = lo > a ? -floorDiv(a - lo, cl) : 0              // ceil((lo − a) / cl)
        return max(0, jmax - jmin + 1)
    }
    /// lap starts per window and within window-relative ticks [0, r]
    func perWindow(_ r: Int64) -> Int64 {
        var total: Int64 = 0
        let firstP = Int64(first) * u
        total += inSegment(a: Int64(last - 16) * u, lo: 0, hi: min(r, firstP - 1))          // the carried segment
        var c = first
        while c >= 0 && c < 16 {
            var next = c + 1
            while next < 16 && (rhythmMask >> UInt16(next)) & 1 == 0 { next += 1 }
            let a = Int64(c) * u
            if a > r { break }
            total += inSegment(a: a, lo: a, hi: min(r, Int64(next) * u - 1))
            c = next
        }
        return total
    }
    let wn = floorDiv(x, window)
    return wn * perWindow(window - 1) + perWindow(x - wn * window)
}
/// The hit's NOTE pass index from the lane's per-tick core inputs — the one function the Router (FREE: it already holds `advOrd`; LOCK: it holds `localT`), the
/// roll and the tests all use. FREE reads the core's ordinal; LOCK counts resets in closed form.
func euclideousFXPassIndex(buf: [Bool], n: Int, dir: EuclidDir, cycleLen: Int, sub: Double, tick: Int64, grid: EuclideousLaneRestartGrid,
                           legacySpanBeats: Double, locked: Bool, advanceStep: Bool, riffDir: RiffDir, stride: Int, length: Int, every: Int = 1) -> Int {
    if locked {
        let ph = euclideousLanePhase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, grid: grid, legacySpanBeats: legacySpanBeats)
        return euclideousFXLockPass(tick: tick, cycleLen: cycleLen, grid: grid, localT: ph.localT)
    }
    let info = euclideousLaneTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: tick, grid: grid, legacySpanBeats: legacySpanBeats,
                                  locked: false, advanceStep: advanceStep)
    // RIFF WALK ferry §5.2 test 7: the FREE path counts the WALK STEP, not the raw ordinal, so every EVERY
    // hit of a group gets the same NOTE pass/offset — the LOCK path above is untouched (out of this ferry's
    // scope, per the restart-chains ferry's own precedent).
    return euclideousFXFreePass(advOrd: euclideousRiffWalkStep(ordinal: info.advOrd, every: every), period: euclideousFXWalkPeriod(dir: riffDir, length: length, stride: stride))
}

/// The riff grid's own cell width (§10.3: "call the riff grid's own function, don't re-derive it"): the FX tab's columns and the riff grid's are the SAME numbers
/// because both read this. `maxWidth` is the panel's outer width (the riff column); the 30pt note-label column, the sp4 gap and the sp8 padding on both
/// sides are the grid's own.
func euclideousRiffCellW(maxWidth: CGFloat) -> CGFloat {
    let n: CGFloat = 8, label: CGFloat = 30, sp4: CGFloat = 4, sp8: CGFloat = 8
    let gridW = max(1, maxWidth - (label + sp4))
    return max(1, (gridW - sp8 * 2 - sp4 * (n - 1)) / n)
}


// MARK: - FX TAB — UI maths (ferry 2026-10-18 §10–§14): layout, cell marks, bubble, gestures, steppers, strings, flash
//
// Everything the FX tab draws or interprets is a number or a string from here, so the painter (FXPanelPainter.swift) only paints what these return and the
// tests can reach every claim. The columns come from `euclideousRiffCellW` — the riff grid's own function — so the FX columns and the riff grid's columns are the
// same numbers by construction (§10.3).

extension EuclideousFXRow {
    static let railNames = ["RATCH", "GATE", "TIE", "VEL", "NOTE"]
    /// The rail's name (§11.3): the CC row reads "CC" plus its controller number with no space (CC74).
    func railName(ccNumber: Int) -> String { self == .cc ? "CC\(ccNumber)" : Self.railNames[rawValue] }
    /// VoiceOver's name for the row (§14.1).
    func spokenName(ccNumber: Int) -> String {
        switch self {
        case .ratch: return "ratchet"
        case .gate: return "gate"
        case .tie: return "tie"
        case .vel: return "velocity"
        case .note: return "note step"
        case .cc: return "controller \(ccNumber)"
        }
    }
    /// The strip's one-line description (§11.9); NOTE and CC show steppers instead.
    var stripDescription: String? {
        switch self {
        case .ratch: return "PLAYS THE NOTE 2–4 TIMES IN ITS STEP"
        case .gate: return "REPLACES THE LANE\u{2019}S GATE"
        case .tie: return "THE NOTE BEFORE CARRIES ON THROUGH"
        case .vel: return "REPLACES THE LANE\u{2019}S VELOCITY"
        case .note, .cc: return nil
        }
    }
    /// Does a vertical drag on a cell edit a value? (TIE has none: any drag there paints.)
    var hasValueDrag: Bool { self != .tie }
}
let euclideousFXHintText = "TAP: ON/OFF · DRAG ALONG: PAINT · DRAG UP/DOWN: VALUE · DOUBLE-TAP: RESET"

/// §10: positions inside the panel's CONTENT (the panel's own 8pt padding already taken off; y 0 = the top of the strip, which sits under the tab row).
/// Strip 24 · 4 · header 14 · 4 · six rows 4 apart · 4 · hint 16. PAGE LAYOUT ferry (2026-10-19): the rows no longer have a fixed 29pt — they SHARE the
/// panel's height, `rowH = (content height − 86) / 6`, so the hint always ends sp8 above the panel's bottom (29 at a 260-tall content area, as before);
/// never below 24 (§10.4's floor — a shorter panel is drawn at 24 and REPORTED by the page's floor list, nothing is shrunk). There is no upper cap.
struct EuclideousFXLayout: Equatable {
    static let labelW: CGFloat = 30, gap: CGFloat = 4, colGap: CGFloat = 4
    static let stripH: CGFloat = 24, headerH: CGFloat = 14, hintH: CGFloat = 16, rowGap: CGFloat = 4
    static let minRowH: CGFloat = 24, bandPad: CGFloat = 2
    /// Everything but the six rows' own height: strip, 4, header, 4, five 4pt row gaps, 4, hint = 86.
    static let fixedHeight: CGFloat = stripH + rowGap + headerH + rowGap + rowGap * 5 + rowGap + hintH
    let width: CGFloat
    let height: CGFloat
    let cellW: CGFloat
    let rowH: CGFloat
    var firstColX: CGFloat { Self.labelW + Self.gap }
    func colLeft(_ c: Int) -> CGFloat { firstColX + CGFloat(c) * (cellW + Self.colGap) }
    var headerTop: CGFloat { Self.stripH + Self.rowGap }
    var rowsTop: CGFloat { headerTop + Self.headerH + Self.rowGap }
    func rowTop(_ r: Int) -> CGFloat { rowsTop + CGFloat(r) * (rowH + Self.rowGap) }
    var hintTop: CGFloat { rowTop(5) + rowH + Self.rowGap }
    func cellRect(row: Int, col: Int) -> CGRect { CGRect(x: colLeft(col), y: rowTop(row), width: cellW, height: rowH) }
    func railRect(row: Int) -> CGRect { CGRect(x: 0, y: rowTop(row), width: Self.labelW, height: rowH) }
    /// The selected row's band (§11.4): 4pt wider than the content on each side (it starts at the panel's x 4), 2pt taller above and below the row.
    func bandRect(row: Int) -> CGRect {
        CGRect(x: -4, y: rowTop(row) - Self.bandPad, width: width + 8, height: rowH + Self.bandPad * 2)
    }
    /// The whole panel (padding included) in content coordinates — what the bubble is kept 6pt inside of.
    var panelBounds: CGRect { CGRect(x: -8, y: -(8 + 20 + 4), width: width + 16, height: height + 8 + 20 + 4 + 8) }
}
/// `width` is the panel CONTENT width (the panel's width − 16); the riff grid's `maxWidth` is that plus the grid's own 8pt padding on each side.
func euclideousFXLayout(width: CGFloat, height: CGFloat) -> EuclideousFXLayout {
    let rowH = max(EuclideousFXLayout.minRowH, euclideousFXRowH(contentHeight: height))
    return EuclideousFXLayout(width: width, height: height, cellW: euclideousRiffCellW(maxWidth: width + 16), rowH: rowH)
}
/// The six rows' shared height for a content area of `contentHeight`, BEFORE the 24pt floor — what the page's floor list compares against 24.
func euclideousFXRowH(contentHeight: CGFloat) -> CGFloat { (contentHeight - EuclideousFXLayout.fixedHeight) / 6 }

enum EuclideousFXTarget: Equatable { case rail(row: Int), cell(row: Int, col: Int) }
/// §12.4: hit-test with the cellW and gap the grid draws with, each cell's area reaching 2pt into the gaps on every side (the gaps are 4: fully claimed).
/// The rail takes the label column plus 2pt of the gap. Nil outside every row.
func euclideousFXHit(x: CGFloat, y: CGFloat, layout: EuclideousFXLayout) -> EuclideousFXTarget? {
    for r in 0..<6 {
        let top = layout.rowTop(r) - 2, bottom = layout.rowTop(r) + layout.rowH + 2
        guard y >= top, y < bottom else { continue }
        if x >= 0, x < EuclideousFXLayout.labelW + 2 { return .rail(row: r) }
        if let c = euclideousFXColumn(x: x, layout: layout, clamped: false) { return .cell(row: r, col: c) }
        return nil
    }
    return nil
}
/// The column under `x` (cells claim 2pt into their gaps). `clamped` pins an x beyond either end to the first / last column — a paint stroke keeps painting the
/// edge cell while the finger drifts past the grid.
func euclideousFXColumn(x: CGFloat, layout: EuclideousFXLayout, clamped: Bool) -> Int? {
    let pitch = layout.cellW + EuclideousFXLayout.colGap
    let u = (x - (layout.firstColX - 2)) / pitch
    if u < 0 { return clamped ? 0 : nil }
    let c = Int(u.rounded(.down))
    if c > 7 { return clamped ? 7 : (x < layout.colLeft(7) + layout.cellW + 2 ? 7 : nil) }
    return c
}

/// §11.5: what a cell with a value draws, in ink on the light fill. Widths are the spec's: ticks 2.5 × 12 (r 1) 4 apart; the bar is min(28, cellW − 8) wide and 3 tall
/// with an ink-18% track; the tie arc is drawn in a 30 × 10 box scaled down to min(30, cellW − 6) wide in a narrow cell.
enum EuclideousFXMark: Equatable {
    case ticks(count: Int)
    case gate(label: String, barW: CGFloat, fillW: CGFloat)
    case tie(arcW: CGFloat)
    case bar(label: String, barW: CGFloat, fillW: CGFloat)
    case step(label: String)
}
func euclideousFXSignedLabel(_ v: Int) -> String { v < 0 ? "\u{2212}\(-v)" : "+\(v)" }
func euclideousFXMark(row: Int, value: Int, cellW: CGFloat) -> EuclideousFXMark {
    let barW = max(2, min(28, cellW - 8))
    func fill(_ num: Double, _ den: Double) -> CGFloat { min(barW, max(2, barW * CGFloat(num / den))) }
    switch row {
    case 0: return .ticks(count: max(2, min(4, value)))
    case 1: return .gate(label: "\(value)", barW: barW, fillW: fill(Double(value), 100))
    case 2: return .tie(arcW: max(2, min(30, cellW - 6)))
    case 3, 5: return .bar(label: "\(value)", barW: barW, fillW: fill(Double(value), 127))
    default: return .step(label: euclideousFXSignedLabel(value))
    }
}

/// §11.11: the value bubble's text.
func euclideousFXBubbleText(row: Int, value: Int, ccNumber: Int) -> String {
    switch row {
    case 0: return "RATCH \u{00D7}\(value)"
    case 1: return "GATE \(value)%"
    case 3: return "VEL \(value)"
    case 4: return "NOTE \(euclideousFXSignedLabel(value)) A PASS"
    case 5: return "CC\(ccNumber) = \(value)"
    default: return ""
    }
}
struct EuclideousFXBubble: Equatable { var rect: CGRect; var notchX: CGFloat }
/// 24 tall, as wide as its text plus 18, centred over the cell with its bottom 7pt above the cell's top, kept 6pt inside the panel; the 9pt notch stays on the
/// cell's centre (pulled in to stay on the bubble's bottom edge). Heavy monospaced 11pt text is 0.6 em a character.
func euclideousFXBubble(text: String, cell: CGRect, bounds: CGRect) -> EuclideousFXBubble {
    let w = (CGFloat(text.count) * 11 * 0.6).rounded(.up) + 18, h: CGFloat = 24
    let x = max(bounds.minX + 6, min(bounds.maxX - 6 - w, cell.midX - w / 2))
    let y = max(bounds.minY + 6, cell.minY - 7 - h)
    let rect = CGRect(x: x, y: y, width: w, height: h)
    return EuclideousFXBubble(rect: rect, notchX: max(rect.minX + 9, min(rect.maxX - 9, cell.midX)))
}

// ── value drags (§12.4) and the steppers (§12.7) ─────────────────────────────────────────────────────────────────────

private let euclideousFXRatchValues = [2, 3, 4]
private let euclideousFXNoteValues = [-3, -2, -1, 1, 2, 3]
/// The legal values of a row, in order, when it has a short list (RATCH, NOTE); nil for the ranged rows.
func euclideousFXValueList(row: Int) -> [Int]? { row == 0 ? euclideousFXRatchValues : (row == 4 ? euclideousFXNoteValues : nil) }
/// Points of finger travel per value step: RATCH 18, GATE 5 (per 5%), VEL 2, NOTE 14, CC 2.
func euclideousFXPointsPerStep(row: Int) -> CGFloat { [18, 5, 0, 2, 14, 2][max(0, min(5, row))] }
/// The value after `travelUp` points of upward finger travel from the lock point, rounded to the nearest step and clamped at the ends.
func euclideousFXDragValue(row: Int, start: Int, travelUp: CGFloat) -> Int {
    let pps = euclideousFXPointsPerStep(row: row)
    guard pps > 0 else { return start }
    let steps = Int((travelUp / pps).rounded())
    if let list = euclideousFXValueList(row: row) {
        let i0 = list.firstIndex(of: start) ?? (list.enumerated().min { abs($0.element - start) < abs($1.element - start) }?.offset ?? 0)
        return list[max(0, min(list.count - 1, i0 + steps))]
    }
    switch row {
    case 1: return max(5, min(EuclideousFX.gateMax, start + 5 * steps))
    case 3: return max(1, min(127, start + steps))
    default: return max(0, min(127, start + steps))
    }
}
/// One step of VoiceOver's increment / decrement (§14.2): one value step; NOTE skips 0; an empty cell turns on at the brush when incremented. Nil = no change.
func euclideousFXAdjust(row: Int, current: Int?, brush: Int, up: Bool) -> Int? {
    guard row != 2 else { return nil }
    guard let cur = current else { return up ? brush : nil }
    let next: Int
    if let list = euclideousFXValueList(row: row) {
        guard let i = list.firstIndex(of: cur) else { return nil }
        let j = i + (up ? 1 : -1)
        guard j >= 0, j < list.count else { return nil }
        next = list[j]
    } else {
        next = euclideousFXDragValue(row: row, start: cur, travelUp: (up ? 1 : -1) * euclideousFXPointsPerStep(row: row))
    }
    return next == cur ? nil : next
}

enum EuclideousFXStepper: Equatable { case passes, ccNumber, base }
let euclideousFXBaseStops = [-1, 0, 32, 64, 96, 127]
/// `‹` / `›`: PASSES and CC step by one, BASE through –, 0, 32, 64, 96, 127 (from a value in between, `›` goes to the next listed value up and `‹` to the next
/// down). Nil at an end — the chevron is disabled and draws at 40% (§12.7: steppers never wrap).
func euclideousFXStepperStep(_ s: EuclideousFXStepper, current: Int, up: Bool) -> Int? {
    switch s {
    case .passes: let n = current + (up ? 1 : -1); return (2...8).contains(n) ? n : nil
    case .ccNumber: let n = current + (up ? 1 : -1); return (0...119).contains(n) ? n : nil
    case .base:
        return up ? euclideousFXBaseStops.first { $0 > current } : euclideousFXBaseStops.last { $0 < current }
    }
}
/// Dragging a stepper's value: PASSES 12pt per step, CC and BASE 2pt (BASE's – is one step below 0).
func euclideousFXStepperDrag(_ s: EuclideousFXStepper, start: Int, travelUp: CGFloat) -> Int {
    let steps = Int((travelUp / (s == .passes ? 12 : 2)).rounded())
    switch s {
    case .passes: return max(2, min(8, start + steps))
    case .ccNumber: return max(0, min(119, start + steps))
    case .base: return max(-1, min(127, start + steps))
    }
}
/// The double-tap on a stepper's value: PASSES 4, CC 74, BASE –.
func euclideousFXStepperDefault(_ s: EuclideousFXStepper) -> Int { s == .passes ? 4 : (s == .ccNumber ? 74 : -1) }
func euclideousFXStepperKey(_ s: EuclideousFXStepper) -> String { s == .passes ? "PASSES" : (s == .ccNumber ? "CC" : "BASE") }
func euclideousFXStepperValueText(_ s: EuclideousFXStepper, value: Int) -> String { s == .base && value < 0 ? "–" : "\(value)" }
func euclideousFXStepperWidth(_ s: EuclideousFXStepper) -> CGFloat { s == .passes ? 100 : (s == .ccNumber ? 84 : 90) }
func euclideousFXStepperSpoken(_ s: EuclideousFXStepper, value: Int) -> String {
    switch s {
    case .passes: return "Passes \(value)"
    case .ccNumber: return "Controller number \(value)"
    case .base: return "Base value \(value < 0 ? "none" : "\(value)")"
    }
}
func euclideousFXStepperValue(_ s: EuclideousFXStepper, fx: EuclideousFX) -> Int {
    switch s { case .passes: return Int(fx.notePasses); case .ccNumber: return Int(fx.ccNumber); case .base: return Int(fx.ccBase) }
}
func euclideousFXSetStepper(_ fx: inout EuclideousFX, _ s: EuclideousFXStepper, value: Int) {
    switch s {
    case .passes: fx.notePasses = UInt8(max(2, min(8, value)))
    case .ccNumber: fx.ccNumber = UInt8(max(0, min(119, value)))
    case .base: fx.ccBase = value < 0 ? -1 : Int16(min(127, value))
    }
}

// ── cell edits (the model side of §12) ───────────────────────────────────────────────────────────────────────────────

/// Set (or, with nil, empty) one cell, clamped to the row's legal domain.
func euclideousFXSetCell(_ fx: inout EuclideousFX, row: Int, col: Int, value: Int?) {
    guard row >= 0, row < 6, col >= 0, col < 8 else { return }
    fx.cells[row * 8 + col] = value.flatMap { EuclideousFX.legalCell(row: row, raw: $0) } ?? EuclideousFX.emptyCell
}
/// §12.2: a tap on an empty cell takes the brush; a tap on a cell with a value empties it.
func euclideousFXTapCell(_ fx: inout EuclideousFX, row: Int, col: Int, brush: Int) {
    euclideousFXSetCell(&fx, row: row, col: col, value: fx.cell(row: row, column: col) == nil ? brush : nil)
}
/// §12.6: a lane button flips that lane's bit on the row.
func euclideousFXToggleLane(_ fx: inout EuclideousFX, row: Int, lane: Int) {
    guard row >= 0, row < 6, lane >= 0, lane < 4 else { return }
    fx.lanes[row] ^= UInt8(1) << UInt8(lane)
}
/// §12.3: a second tap on the same cell within 320 ms.
let euclideousFXDoubleTapWindow: Double = 0.32
func euclideousFXIsDoubleTap(previous: (row: Int, col: Int, time: Double)?, row: Int, col: Int, time: Double) -> Bool {
    guard let p = previous else { return false }
    return p.row == row && p.col == col && time - p.time >= 0 && time - p.time <= euclideousFXDoubleTapWindow
}

// ── the touch reducer (§12.2–§12.4) ──────────────────────────────────────────────────────────────────────────────────

enum EuclideousFXTouchEvent: Equatable {
    case paint(row: Int, col: Int, on: Bool)        // `on`: the cell takes the row's brush; otherwise it empties
    case value(row: Int, col: Int, value: Int)      // a value drag's current value (an empty cell takes it)
    case tap(row: Int, col: Int)
}
/// One finger on one cell. Below 8pt of travel nothing happens (a tap on lift); the touch locks to an axis as soon as either component reaches 8pt — vertical if
/// the vertical one is larger, otherwise horizontal — and on the TIE row any drag paints. A paint stroke's value is the opposite of the first cell's state at
/// touch-down and every cell of the touched row the finger crosses takes it; a value drag measures travel from the lock point.
struct EuclideousFXTouch {
    enum Phase { case pending, paint, value }
    static let lockDistance: CGFloat = 8
    private(set) var phase: Phase = .pending
    let start: CGPoint
    let row: Int
    let startCol: Int
    private let startHadValue: Bool
    private let startValue: Int
    private var lockY: CGFloat = 0
    private var lastCol: Int
    private var paintOn = false
    private var lastValue: Int
    /// The value being dragged (for the bubble), nil outside a value drag.
    var draggedValue: Int? { phase == .value ? lastValue : nil }
    init(point: CGPoint, row: Int, col: Int, cellValue: Int?, brush: Int) {
        start = point; self.row = row; startCol = col; lastCol = col
        startHadValue = cellValue != nil; startValue = cellValue ?? brush; lastValue = cellValue ?? brush
    }
    mutating func moved(to p: CGPoint, layout: EuclideousFXLayout) -> [EuclideousFXTouchEvent] {
        switch phase {
        case .pending:
            let dx = p.x - start.x, dy = p.y - start.y
            guard max(abs(dx), abs(dy)) >= Self.lockDistance else { return [] }
            if abs(dy) > abs(dx), EuclideousFXRow(rawValue: row)?.hasValueDrag == true {
                phase = .value; lockY = p.y
                return [.value(row: row, col: startCol, value: startValue)]
            }
            phase = .paint; paintOn = !startHadValue
            let col = euclideousFXColumn(x: p.x, layout: layout, clamped: true) ?? startCol
            var out: [EuclideousFXTouchEvent] = [.paint(row: row, col: startCol, on: paintOn)]
            out += cross(from: startCol, to: col)
            lastCol = col
            return out
        case .paint:
            let col = euclideousFXColumn(x: p.x, layout: layout, clamped: true) ?? lastCol
            guard col != lastCol else { return [] }
            let out = cross(from: lastCol, to: col)
            lastCol = col
            return out
        case .value:
            let v = euclideousFXDragValue(row: row, start: startValue, travelUp: lockY - p.y)
            guard v != lastValue else { return [] }
            lastValue = v
            return [.value(row: row, col: startCol, value: v)]
        }
    }
    func ended() -> [EuclideousFXTouchEvent] { phase == .pending ? [.tap(row: row, col: startCol)] : [] }
    private func cross(from a: Int, to b: Int) -> [EuclideousFXTouchEvent] {
        guard a != b else { return [] }
        let step = b > a ? 1 : -1
        return stride(from: a + step, through: b, by: step).map { .paint(row: row, col: $0, on: paintOn) }
    }
}

// ── labels, the preview and VoiceOver (§11.2, §11.9, §14) ───────────────────────────────────────────────────────────

/// §11.2: the header over a column — the written rank the riff plays there, named exactly as the riff grid's note-label column names that rank
/// (`euclideousGlobalPoolExtended` + the page's naming). A rest shows "–" (dim); with nothing held the rank number shows.
func euclideousFXHeaderLabel(rank: Int, pool: [Int], name: (Int) -> String) -> (text: String, rest: Bool) {
    guard rank >= 1 else { return ("–", true) }
    guard !pool.isEmpty else { return ("\(rank)", false) }
    let ext = euclideousGlobalPoolExtended(sortedRaw: pool)
    return rank <= ext.count ? (name(ext[rank - 1]), false) : ("–", false)
}
/// §11.9: the cell the NOTE preview reads — the NOTE cell touched last, else the leftmost NOTE cell on a non-rest column; nil when there is none.
func euclideousFXPreviewColumn(touched: Int?, fx: EuclideousFX, ranks: [Int]) -> Int? {
    func ok(_ c: Int) -> Bool { fx.cell(row: 4, column: c) != nil && c < ranks.count && ranks[c] >= 1 }
    if let t = touched, ok(t) { return t }
    return (0..<8).first(where: ok)
}
/// §11.9: the notes the previewed cell plays on passes 1…N joined by " › ", each moved rank resolved through the engine's fold on the current pool (INVERT,
/// TRANSPOSE, octave and mask ignored); with nothing held the moved ranks themselves (4 › 5 › 6 › 7, or 1 › 0 › −1). `pool` is the held notes ascending.
func euclideousFXNotePreviewText(fx: EuclideousFX, touched: Int?, ranks: [Int], pool: [Int], name: (Int) -> String) -> String {
    guard let c = euclideousFXPreviewColumn(touched: touched, fx: fx, ranks: ranks), let s = fx.cell(row: 4, column: c) else { return "NO STEPS YET" }
    let passes = max(2, min(8, Int(fx.notePasses)))
    return (0..<passes).map { k -> String in
        let rank = ranks[c] + s * k
        guard !pool.isEmpty else { return rank < 0 ? "\u{2212}\(-rank)" : "\(rank)" }
        guard let pitch = riffResolveExtended(rank: rank, oct: 0, n: pool.count, asc: { pool[$0] }), pitch >= 0, pitch <= 127 else { return "–" }
        return name(pitch)
    }.joined(separator: " › ")
}
func euclideousFXLanesPhrase(mask: UInt8) -> String {
    let lanes = (0..<4).filter { (mask >> UInt8($0)) & 1 != 0 }.map { $0 + 1 }
    switch lanes.count {
    case 0: return "no lanes"
    case 4: return "all lanes"
    case 1: return "lane \(lanes[0])"
    default: return "lanes " + lanes.dropLast().map(String.init).joined(separator: ", ") + " and \(lanes.last!)"
    }
}
func euclideousFXRailLabel(row: Int, ccNumber: Int, mask: UInt8, selected: Bool) -> String {
    let name = EuclideousFXRow(rawValue: row)?.spokenName(ccNumber: ccNumber) ?? ""
    return "FX row, \(name), \(euclideousFXLanesPhrase(mask: mask))" + (selected ? ", selected" : "")
}
func euclideousFXLaneGroupLabel(row: Int, ccNumber: Int) -> String {
    "Lanes that play the \(EuclideousFXRow(rawValue: row)?.spokenName(ccNumber: ccNumber) ?? "") row"
}
func euclideousFXLaneButtonLabel(lane: Int, on: Bool) -> String { "Lane \(lane + 1), " + (on ? "plays this row" : "ignores this row") }
/// §14.2: "Note n, <name or rest>, <value>" — an empty cell ends with the row's name and "off".
func euclideousFXCellLabel(row: Int, ccNumber: Int, column: Int, noteName: String?, value: Int?) -> String {
    let rowName = EuclideousFXRow(rawValue: row)?.spokenName(ccNumber: ccNumber) ?? ""
    var tail = "\(rowName) off"
    if let v = value {
        switch row {
        case 0: tail = "ratchet \(v)"
        case 1: tail = "gate \(v) percent"
        case 2: tail = "tie on"
        case 3: tail = "velocity \(v)"
        case 4: tail = "note step \(v < 0 ? "minus" : "plus") \(abs(v)) per pass"
        default: tail = "controller \(ccNumber) value \(v)"
        }
    }
    return "Note \(column + 1), \(noteName ?? "rest"), \(tail)"
}
/// §11.6: a rest column's cells, and a row with no lanes, draw at 42% — and the two multiply.
func euclideousFXCellOpacity(restColumn: Bool, rowHasLanes: Bool) -> Double { (restColumn ? 0.42 : 1) * (rowHasLanes ? 1 : 0.42) }

// ── the firing flash (§11.8) ─────────────────────────────────────────────────────────────────────────────────────────

struct EuclideousFXFlash: Equatable { var lane: Int; var intensity: Double }
/// FX §11.8's firing flash, now on PULSE ferry (2026-10-20, §8.1) timing: each lane's latest RIFF strike that has happened (`strikes[lane]`, from the feed: the riff column the hit read, its played velocity and its onset on the
/// display clock) flashes the cells of the rows `euclideousFXApply` says applied to it, in that lane's colour, at §1's flash f for that velocity `now - onsetAt` seconds on — so it scales with velocity and fades on the same
/// timing as every other strike effect (it used to read the comet bar's step-based flare). A later hit on the same cell takes the cell over. 48 entries, row-major. TIE hits post no event, and BASE sends have no cell.
func euclideousFXFlashCells(fx: EuclideousFX, lines: [EuclidLine], strikes: [EuclideousPulseStrike?], ranks: [Int], now: Double, scale: Double) -> [EuclideousFXFlash?] {
    var out = [EuclideousFXFlash?](repeating: nil, count: 48)
    var onsets = [Double](repeating: -Double.infinity, count: 48)
    for lane in 0..<min(4, min(lines.count, strikes.count)) {
        guard let s = strikes[lane], s.riffVel > 0, s.column >= 0, Int(s.column) < 8, s.onsetAt <= now else { continue }
        let col = Int(s.column)
        let hit = euclideousFXApply(fx, lane: lane, playsRiff: euclideousLanePlaysRiff(lines[lane]), column: col, writtenRank: col < ranks.count ? ranks[col] : 0, pass: 0)
        guard hit.appliedRows != 0 else { continue }
        let intensity = euclideousPulseEnvelopes(velocity: Int(s.riffVel), seconds: now - s.onsetAt, scale: scale).f
        guard intensity > 0 else { continue }
        for r in 0..<6 where (hit.appliedRows >> UInt8(r)) & 1 != 0 {
            let i = r * 8 + col
            if s.onsetAt >= onsets[i] { onsets[i] = s.onsetAt; out[i] = EuclideousFXFlash(lane: lane, intensity: intensity) }
        }
    }
    return out
}

// MARK: - RIFF PANEL ferry (2026-10-19): compact tabs, blended arrows, lane rails — the pure maths (§5, §8)
//
// Everything the riff panel's new look draws or says is a number or a string from here, so `RiffArrowPainter.swift` only PAINTS what these return and the tests reach every
// claim: each lane's heading (§5.1), how lanes sharing a note group into one arrow (§5.3), the OKLCH blend its fill uses (§5.4), the arrow's outline / size / label / fill
// (§4), a lane's current column and its three-column trail (§6.3), what a rail's eight segments look like (§6.2/§6.4), the tab-size mini icon (§2.3) and the VoiceOver words
// (§7). Display only: nothing here is read by the engine, the snapshot or the document.

// ── 5.1 heading ──────────────────────────────────────────────────────────────────────────────────────────────────────────────

enum EuclideousArrowHeading: Equatable { case left, right, still }

/// §5.1. STILL when LEN ≤ 1 or the walk's period P (`euclideousFXWalkPeriod`, riff ferry 7.1) is 1. Otherwise FWD heads right and REV heads left, whatever SHIFT and
/// the wrap from the last column to the first do. PEND and PING: with w = floor(o ÷ EVERY) and p the walk position `riffStepAt` gives at w (BEFORE SHIFT), take the smallest k
/// from 1 to P whose position differs from p — right if it is higher, left if lower, still if there is none (so PING's repeated end step looks one further and the arrow
/// turns exactly at each end). `ordinal` is the ordinal of the hit the arrow SHOWS (under ADV STEP, that hit's step ordinal). RANDOM / DRUNK can't reach Euclideous
/// (`euclideousRiffDirResolved` coerces them to FWD) and head right.
func euclideousArrowHeading(riffDir: RiffDir, length: Int, stride: Int, every: Int, ordinal: Int64) -> EuclideousArrowHeading {
    let len = max(1, length), st = max(1, stride), ev = max(1, every)
    let period = euclideousFXWalkPeriod(dir: riffDir, length: len, stride: st)
    if len <= 1 || period <= 1 { return .still }
    switch riffDir {
    case .forward, .random, .drunk: return .right
    case .reverse: return .left
    case .pendulum, .pingpong:
        let w = Int(euclideousRiffWalkStep(ordinal: ordinal, every: ev))
        func pos(_ k: Int) -> Int { riffStepAt(riffDir, raw: (w + k) * st, steps: len, seed: 0) }
        let p = pos(0)
        for k in 1...period { let q = pos(k); if q != p { return q > p ? .right : .left } }
        return .still
    }
}

// ── 5.3 grouping ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

enum EuclideousArrowKind: Equatable { case right, left, double, still }
struct EuclideousArrowMember: Equatable { var lane: Int; var heading: EuclideousArrowHeading }
/// §5.3: double-headed if any lane in the cell heads left AND any heads right; otherwise right if any heads right, left if any heads left, else still. Left-to-right order:
/// the lanes heading left, then the still lanes, then the lanes heading right, each group in lane order. (`lanes` are 0-based lane indices.)
func euclideousArrowGrouping(_ members: [EuclideousArrowMember]) -> (kind: EuclideousArrowKind, lanes: [Int]) {
    let sorted = members.sorted { $0.lane < $1.lane }
    let lefts = sorted.filter { $0.heading == .left }, stills = sorted.filter { $0.heading == .still }, rights = sorted.filter { $0.heading == .right }
    let kind: EuclideousArrowKind = (!lefts.isEmpty && !rights.isEmpty) ? .double : (!rights.isEmpty ? .right : (!lefts.isEmpty ? .left : .still))
    return (kind, (lefts + stills + rights).map { $0.lane })
}

// ── 5.4 colour: OKLCH blending ───────────────────────────────────────────────────────────────────────────────────────────────

struct EuclideousRGB: Equatable, Hashable { var r: Int; var g: Int; var b: Int }
/// The four lane accents as the page draws them — ONE definition (`EuclideousPage.laneAccents` is built from it): red, blue, yellow, green.
let euclideousLaneAccentComponents: [(r: Double, g: Double, b: Double)] = [(0.95, 0.35, 0.35), (0.35, 0.75, 0.95), (0.95, 0.75, 0.25), (0.55, 0.85, 0.45)]
let euclideousLaneRGB: [EuclideousRGB] = euclideousLaneAccentComponents.map {
    EuclideousRGB(r: Int(($0.r * 255).rounded()), g: Int(($0.g * 255).rounded()), b: Int(($0.b * 255).rounded()))
}
private func euclideousSRGBToLinear(_ v: Int) -> Double { let c = Double(v) / 255; return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
private func euclideousLinearToSRGB(_ v: Double) -> Int {
    let c = v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    return Int(max(0, min(255, (c * 255).rounded())))
}
/// sRGB → linear light → OKLab (Björn Ottosson's matrices) → (L, a, b).
func euclideousOKLab(_ c: EuclideousRGB) -> (L: Double, a: Double, b: Double) {
    let r = euclideousSRGBToLinear(c.r), g = euclideousSRGBToLinear(c.g), b = euclideousSRGBToLinear(c.b)
    let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
    let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
    let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
    return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
            1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
            0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
}
func euclideousRGBFromOKLab(L: Double, a: Double, b: Double) -> EuclideousRGB {
    let l_ = L + 0.3963377774 * a + 0.2158037573 * b
    let m_ = L - 0.1055613458 * a - 0.0638541728 * b
    let s_ = L - 0.0894841775 * a - 1.2914855480 * b
    let l = l_ * l_ * l_, m = m_ * m_ * m_, s = s_ * s_ * s_
    return EuclideousRGB(r: euclideousLinearToSRGB(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                         g: euclideousLinearToSRGB(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                         b: euclideousLinearToSRGB(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
}
/// OKLab as lightness L, chroma C and hue h (degrees).
func euclideousOKLCH(_ c: EuclideousRGB) -> (L: Double, C: Double, h: Double) {
    let lab = euclideousOKLab(c)
    var h = atan2(lab.b, lab.a) * 180 / .pi
    if h < 0 { h += 360 }
    return (lab.L, (lab.a * lab.a + lab.b * lab.b).squareRoot(), h)
}
/// §5.4: mix two colours at `t` by interpolating L and C linearly and h the SHORTER way round the circle; convert back and clamp each channel to 0–255.
/// t = 0 / 1 return the inputs exactly (no round trip), so a lane's own colour stays pure at its end.
func euclideousMixOKLCH(_ a: EuclideousRGB, _ b: EuclideousRGB, t: Double) -> EuclideousRGB {
    if t <= 0 { return a }
    if t >= 1 { return b }
    let x = euclideousOKLCH(a), y = euclideousOKLCH(b)
    var d = (y.h - x.h).truncatingRemainder(dividingBy: 360)
    if d > 180 { d -= 360 } else if d < -180 { d += 360 }
    let L = x.L + (y.L - x.L) * t, C = x.C + (y.C - x.C) * t, h = (x.h + d * t) * .pi / 180
    return euclideousRGBFromOKLab(L: L, a: C * cos(h), b: C * sin(h))
}
/// "An even blend" of three or more colours (the flare glow, §4.7): the mean in OKLab.
func euclideousEvenBlend(_ colours: [EuclideousRGB]) -> EuclideousRGB {
    guard let first = colours.first else { return EuclideousRGB(r: 0, g: 0, b: 0) }
    if colours.count == 1 { return first }
    var L = 0.0, a = 0.0, b = 0.0
    for c in colours { let o = euclideousOKLab(c); L += o.L; a += o.a; b += o.b }
    let n = Double(colours.count)
    return euclideousRGBFromOKLab(L: L / n, a: a / n, b: b / n)
}

struct EuclideousBlendStop: Equatable { var position: Double; var colour: EuclideousRGB; var alpha: Double }
/// §5.4: the fill for lanes c1 … cn (n ≥ 2), left to right: lane i's colour sits at position i ÷ (n − 1). Between neighbours at p0 and p1, with hold = 0.14 ÷ (n − 1),
/// seven stops at u = 0, 1/6 … 1 take the mix at e = u²(3 − 2u), placed at p0 + hold + (p1 − p0 − 2 × hold) × u — except u = 0 and u = 1, which sit exactly at p0 and p1. So each
/// lane's own colour stays pure at its end and the middle blends. `alphas[i]` is lane i's alpha (4.9: a muted lane's stops take 42%); a stop between two lanes takes the
/// same eased mix of their alphas. Memoised by lane set (main thread only — it is drawing, not engine).
func euclideousBlendStops(colours: [EuclideousRGB], alphas: [Double]? = nil) -> [EuclideousBlendStop] {
    let n = colours.count
    guard n >= 2 else { return colours.map { EuclideousBlendStop(position: 0, colour: $0, alpha: alphas?.first ?? 1) } }
    let al = (alphas != nil && alphas!.count == n) ? alphas! : [Double](repeating: 1, count: n)
    let key = EuclideousBlendCache.Key(colours: colours, alphas: al)
    if let hit = EuclideousBlendCache.stops[key] { return hit }
    var out: [EuclideousBlendStop] = []
    let hold = 0.14 / Double(n - 1)
    for i in 0..<(n - 1) {
        let p0 = Double(i) / Double(n - 1), p1 = Double(i + 1) / Double(n - 1)
        for j in 0...6 {
            let u = Double(j) / 6, e = u * u * (3 - 2 * u)
            let pos = j == 0 ? p0 : (j == 6 ? p1 : p0 + hold + (p1 - p0 - 2 * hold) * u)
            let stop = EuclideousBlendStop(position: pos, colour: euclideousMixOKLCH(colours[i], colours[i + 1], t: e), alpha: al[i] + (al[i + 1] - al[i]) * e)
            if let last = out.last, last.position == pos, last.colour == stop.colour, last.alpha == stop.alpha { continue }
            out.append(stop)
        }
    }
    if EuclideousBlendCache.stops.count > 256 { EuclideousBlendCache.stops.removeAll() }
    EuclideousBlendCache.stops[key] = out
    return out
}
enum EuclideousBlendCache {
    struct Key: Hashable { var colours: [EuclideousRGB]; var alphas: [Double] }
    /// Main-thread only (the painters). Bounded: 4 lanes make at most a few dozen distinct sets.
    nonisolated(unsafe) static var stops: [Key: [EuclideousBlendStop]] = [:]
}

// ── §4 the arrow ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

enum EuclideousArrowStyle {
    /// 4.4: ONE lane — the comet bar's hit-tile fill. SOURCE differs from the ferry's mock ("lane100 at the top to lane100 × 0.86 at the bottom"): the comet's tile
    /// (`EuclidCometBar`, `layer.fill` linearGradient) is the lane colour at 95% alpha at the top to 55% (+25% of the afterglow) at the bottom, so that is what the arrow
    /// uses (reported). Two or more lanes: the blend under `highlight*` (white 16% → clear at 45% → black 14%).
    static let topAlpha = 0.95, bottomAlpha = 0.55
    static let highlightWhiteTop = 0.16, highlightClearAt = 0.45, highlightBlackBottom = 0.14
    static let shadowAlpha = 0.45, shadowRadius: CGFloat = 0.75, shadowY: CGFloat = 1
    static let hollowStrokeWidth: CGFloat = 1.5, hollowDash: [CGFloat] = [3, 2]
    static let mutedAlpha = 0.42
    /// PULSE §4.1 (replacing rails 4.7's 6pt glow and 1.06 scale): the flare's PEAK — scale 1 + 0.24 × f, a glow of blur 12 × f (SwiftUI shadow radius = half a CSS blur, so 6 × f) at 85% × f.
    static let flareBlur: CGFloat = 12, flareRadius: CGFloat = 6, flareAlpha = 0.85, flareScale: CGFloat = 1.24
    static let labelSizes: [CGFloat] = [10, 8.5, 6.5, 6]     // by lane count 1…4
    static let tipRadius: CGFloat = 0.9, tipSoftening: CGFloat = 1.3
    /// The width and height of the arrow centred in a cell: width cellW − 7, height min(18, cellH − 8).
    static func size(cellW: CGFloat, cellH: CGFloat) -> CGSize { CGSize(width: max(1, cellW - 7), height: max(1, min(18, cellH - 8))) }
}
/// One path command in an arrow's outline (SwiftUI's `Path` is built from these; the numbers are testable).
enum EuclideousPathCmd: Equatable { case move(CGPoint), line(CGPoint), quad(to: CGPoint, control: CGPoint), close }
enum EuclideousArrowOutline: Equatable { case path([EuclideousPathCmd]), capsule }
/// 4.3: in a w × h box, pointing right (mirrored for left), with r = min(4, h ÷ 3) and t = m = h ÷ 2: a rounded tail, straight sides and a softened tip; the double-headed
/// arrow has a softened tip at BOTH ends; "still" is a capsule.
func euclideousArrowOutline(kind: EuclideousArrowKind, w: CGFloat, h: CGFloat) -> EuclideousArrowOutline {
    typealias S = EuclideousArrowStyle
    let r = min(4, h / 3), t = h / 2, m = h / 2
    let k = S.tipRadius, q = S.tipSoftening
    func P(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y) }
    switch kind {
    case .still: return .capsule
    case .right, .left:
        let right: [EuclideousPathCmd] = [
            .move(P(r, 0)), .line(P(w - t, 0)), .line(P(w - k, m - q)), .quad(to: P(w - k, m + q), control: P(w, m)), .line(P(w - t, h)), .line(P(r, h)),
            .quad(to: P(0, h - r), control: P(0, h)), .line(P(0, r)), .quad(to: P(r, 0), control: P(0, 0)), .close]
        if kind == .right { return .path(right) }
        func mirror(_ p: CGPoint) -> CGPoint { P(w - p.x, p.y) }
        return .path(right.map {
            switch $0 {
            case .move(let p): return .move(mirror(p))
            case .line(let p): return .line(mirror(p))
            case .quad(let to, let c): return .quad(to: mirror(to), control: mirror(c))
            case .close: return .close
            }
        })
    case .double:
        return .path([
            .move(P(t, 0)), .line(P(w - t, 0)), .line(P(w - k, m - q)), .quad(to: P(w - k, m + q), control: P(w, m)), .line(P(w - t, h)), .line(P(t, h)),
            .line(P(k, m + q)), .quad(to: P(k, m - q), control: P(0, m)), .close])
    }
}

/// One lane's part in an arrow: its heading, whether the LANES grid has it muted at this beat, and its flare strength (0 = none, 1 = the strike's peak).
struct EuclideousArrowLane: Equatable { var lane: Int; var heading: EuclideousArrowHeading; var muted: Bool; var flare: Double }
enum EuclideousArrowFill: Equatable {
    case single(colour: EuclideousRGB, topAlpha: Double, bottomAlpha: Double)
    case blend(stops: [EuclideousBlendStop])
}
struct EuclideousArrowLabelPart: Equatable { var text: String; var alpha: Double }
struct EuclideousArrowSpec: Equatable {
    var kind: EuclideousArrowKind
    var lanes: [Int]                       // 0-based, in the fill's left-to-right order
    var size: CGSize
    var outline: EuclideousArrowOutline
    var hollow: Bool                       // 4.8: a rest — no fill, no shadow, a dashed stroke
    var fill: EuclideousArrowFill          // also the hollow stroke's colours (a gradient when shared)
    var labelParts: [EuclideousArrowLabelPart]
    var labelSize: CGFloat
    var labelRect: CGRect                  // in the arrow's own box
    var opacity: Double                    // 1, or 0.42 when EVERY lane in it is muted
    var flareColour: EuclideousRGB?        // the blend of the lanes now flaring; nil = none
    var flareStrength: Double              // 0…1
    var label: String { labelParts.map { $0.text }.joined() }
}
/// 8.2 / §4: the arrow for ONE cell from its lanes' headings, mutes and flare states. `hollow` = every lane in it is on a rest.
func euclideousArrowSpec(cellW: CGFloat, cellH: CGFloat, members: [EuclideousArrowLane], hollow: Bool,
                         laneColours: [EuclideousRGB] = euclideousLaneRGB) -> EuclideousArrowSpec? {
    typealias S = EuclideousArrowStyle
    guard !members.isEmpty else { return nil }
    let group = euclideousArrowGrouping(members.map { EuclideousArrowMember(lane: $0.lane, heading: $0.heading) })
    let byLane = Dictionary(members.map { ($0.lane, $0) }, uniquingKeysWith: { a, _ in a })
    let ordered = group.lanes.compactMap { byLane[$0] }
    func colour(_ lane: Int) -> EuclideousRGB { laneColours[((lane % laneColours.count) + laneColours.count) % laneColours.count] }
    let size = S.size(cellW: cellW, cellH: cellH)
    let n = ordered.count
    let shared = n >= 2
    // 4.9: alone and muted → the whole arrow at 42%; sharing → that lane's stops (and number) at 42%, the arrow dims as a whole only when EVERY lane in it is muted.
    let allMuted = ordered.allSatisfy { $0.muted }
    let fill: EuclideousArrowFill = shared
        ? .blend(stops: euclideousBlendStops(colours: ordered.map { colour($0.lane) }, alphas: ordered.map { $0.muted ? S.mutedAlpha : 1 }))
        : .single(colour: colour(ordered[0].lane), topAlpha: S.topAlpha, bottomAlpha: S.bottomAlpha)
    var parts: [EuclideousArrowLabelPart] = []
    for (i, m) in ordered.enumerated() {
        if i > 0 { parts.append(EuclideousArrowLabelPart(text: "\u{00B7}", alpha: 1)) }
        parts.append(EuclideousArrowLabelPart(text: "\(m.lane + 1)", alpha: (shared && m.muted) ? S.mutedAlpha : 1))
    }
    let t = size.height / 2
    // 4.6: one lane, or two in a one-way arrow → centred in the BODY (between the tail and the tip's base); double-headed, or three or more → the whole arrow, 2pt side insets.
    let bodyRule = n == 1 || (n == 2 && group.kind != .double)
    let labelRect: CGRect
    if group.kind == .still {
        // a capsule has no tip, so its "body" is the whole shape: centred on it, with the same 2pt side insets as the double-headed arrow
        labelRect = CGRect(x: 2, y: 0, width: max(1, size.width - 4), height: size.height)
    } else if bodyRule {
        labelRect = group.kind == .left ? CGRect(x: t, y: 0, width: size.width - t, height: size.height) : CGRect(x: 0, y: 0, width: size.width - t, height: size.height)
    } else {
        labelRect = CGRect(x: 2, y: 0, width: max(1, size.width - 4), height: size.height)
    }
    // 4.7: the glow takes the blend of the lanes NOW flaring — one lane its colour, two the t = 0.5 mix, more an even blend.
    let flaring = ordered.filter { $0.flare > 0 }
    let flareColour: EuclideousRGB? = flaring.isEmpty ? nil
        : (flaring.count == 1 ? colour(flaring[0].lane) : (flaring.count == 2 ? euclideousMixOKLCH(colour(flaring[0].lane), colour(flaring[1].lane), t: 0.5) : euclideousEvenBlend(flaring.map { colour($0.lane) })))
    return EuclideousArrowSpec(kind: group.kind, lanes: group.lanes, size: size, outline: euclideousArrowOutline(kind: group.kind, w: size.width, h: size.height),
                               hollow: hollow, fill: fill, labelParts: parts, labelSize: S.labelSizes[min(3, n - 1)], labelRect: labelRect,
                               opacity: allMuted ? S.mutedAlpha : 1, flareColour: flareColour, flareStrength: flaring.map { $0.flare }.max() ?? 0)
}

/// RIFF GRID review (2026-10-21): a lane is RUNNING while the transport (or the free-run that stands in for it) plays AND the engine runs the lane — the Router's own gate (`runEuclidLine`'s caller):
/// the lane's PLAY / STOP is on and it has HITS (or its pattern is inverted). The riff panel's arrows, the lane card's riff thumbnail highlight and its spoken "now on step" show a lane's live position
/// only while it runs: the engine keeps a lane's last riff step when it stops running (the step resets only at a transport edge), so without this a lane switched off — or taken down to 0 HITS —
/// kept an arrow sitting on its last note, as if it were still walking. (The WALK strip's ring and the rails' current column already followed the PLAY / STOP half of this rule.)
func euclideousLaneRunsInEngine(_ line: EuclidLine) -> Bool { (line.pulses > 0 || line.patternMissResolved) && line.enabledResolved }
func euclideousLaneIsRunning(transportPlaying: Bool, line: EuclidLine) -> Bool { transportPlaying && euclideousLaneRunsInEngine(line) }
/// The arrow of a lane draws only while the lane runs and its riff is on (a SHADOWing lane's riff is overridden entirely, so the caller passes `riffOn` already false for it).
func euclideousLaneArrowShows(riffOn: Bool, running: Bool) -> Bool { riffOn && running }

/// One lane's arrow seat: the cell it occupies (column 0-based, rank 1…8), whether it is on a rest (hollow) and its heading.
struct EuclideousLaneArrowState: Equatable {
    var lane: Int
    var column: Int
    var rank: Int
    var hollow: Bool
    var heading: EuclideousArrowHeading
}
/// §4.1/§4.8: the cell a lane's arrow occupies, from the SAME plan the marker used (so where it sits and when it moves are unchanged). A hit on a rest seats the arrow in the
/// rest's own column at the held row, hollow — under SKIP, FILL and REPEAT alike (the engine plays nothing, a lit-notes layer, or the repeated note there; the cell is the
/// marker's today); under TIE the arrow STAYS on the tied note's cell, drawn as normal (`plan.tieStay`). The heading is for the hit the arrow SHOWS.
func euclideousLaneArrowState(lane: Int, cfg: EuclideousWalkLaneConfig, plan: EuclideousWalkTagPlan, polledOrdinal: Int64) -> EuclideousLaneArrowState {
    let column: Int, rank: Int, hollow: Bool, ordinal: Int64
    if plan.seatIsRest, cfg.onRest == .tie, let stay = plan.tieStay {
        (column, rank, hollow, ordinal) = (stay.step, stay.rank, false, stay.ordinal)
    } else {
        (column, rank, hollow, ordinal) = (plan.seatStep, plan.seatRank, plan.seatIsRest, plan.seatOrdinal ?? polledOrdinal)
    }
    let heading = euclideousArrowHeading(riffDir: cfg.riffDir, length: cfg.length, stride: cfg.stride, every: cfg.every, ordinal: ordinal)
    return EuclideousLaneArrowState(lane: lane, column: column, rank: rank, hollow: hollow, heading: heading)
}
struct EuclideousArrowCell: Equatable { var column: Int; var rank: Int; var members: [EuclideousLaneArrowState]; var hollow: Bool }
/// §4.1: lanes whose arrows sit in the same cell share ONE arrow (hollow only if every lane in it is on a rest). Cells come out in the order of their lowest lane.
func euclideousArrowCells(_ states: [EuclideousLaneArrowState]) -> [EuclideousArrowCell] {
    var cells: [EuclideousArrowCell] = []
    for s in states.sorted(by: { $0.lane < $1.lane }) {
        if let i = cells.firstIndex(where: { $0.column == s.column && $0.rank == s.rank }) { cells[i].members.append(s) }
        else { cells.append(EuclideousArrowCell(column: s.column, rank: s.rank, members: [s], hollow: true)) }
    }
    return cells.map { var c = $0; c.hollow = c.members.allSatisfy { $0.hollow }; return c }
}

// ── §6 the rails ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

struct EuclideousRailWalk: Equatable {
    var current: Int          // the column the lane's latest hit read (0-based)
    var trail: [Int]          // up to three earlier columns, newest first
    var ordinal: Int64        // that hit's ordinal (its heading is measured on it)
}
/// §6.3 / 8.3: the column the hit at `hitTick` read, and the TRAIL — going back from it through the lane's earlier hits since the melody origin, in REPEAT's lookback order
/// (ADV HIT: ordinals o−1, o−2, …; ADV STEP: the lane's own earlier hits backward in real time), take the column each read, skipping any column equal to the one taken
/// just before it (the first comparison is with the current column), until three are found or 64 hits have been checked. Pure: nothing is accumulated.
func euclideousRailWalk(cfg: EuclideousWalkLaneConfig, hitTick: Int64) -> EuclideousRailWalk {
    let len = max(1, cfg.length)
    let cycleLen = euclidCycleLen(cfg.dir, n: cfg.n)
    func column(_ ord: Int64) -> Int {
        euclideousRiffColumn(ordinal: ord, every: cfg.every, direction: cfg.riffDir, length: len, stride: cfg.stride, shift: cfg.rotate, seed: cfg.seed)
    }
    let here = euclideousLaneChainTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: hitTick, chains: cfg.chains,
                                       legacySpanBeats: cfg.spanBeats, advanceStep: cfg.advanceStep)
    let current = column(here.advOrd)
    var trail: [Int] = []
    var last = current
    var checked = 0
    func take(_ col: Int) { checked += 1; if col != last { trail.append(col); last = col } }
    if !cfg.advanceStep {
        var o2 = here.advOrd - 1
        while o2 >= 0, checked < 64, trail.count < 3 { take(column(o2)); o2 -= 1 }
    } else {
        let origin = euclideousLaneChainPhase(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: hitTick, chains: cfg.chains, legacySpanBeats: cfg.spanBeats).originTickM
        var t = hitTick - 1
        var scanned = 0
        let tickCap = 64 * max(1, cycleLen) + 64          // a sparse pattern spaces its hits up to a lap apart
        while t >= origin, checked < 64, trail.count < 3, scanned < tickCap {
            let info = euclideousLaneChainTick(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: t, chains: cfg.chains,
                                               legacySpanBeats: cfg.spanBeats, advanceStep: true)
            if info.rawIsHit { take(column(info.advOrd)) }
            t -= 1; scanned += 1
        }
    }
    return EuclideousRailWalk(current: current, trail: trail, ordinal: here.advOrd)
}
/// §6.2 / 8.3: the columns a lane PLAYS — exactly what the riff card's mini-grid draws at full strength:
/// inside the lane's own window (RIFF WINDOW ferry: LEN columns starting at SHIFT, wrapping at 8) and not in
/// the readout's never-play set (`neverPlay` is empty when the readout is over budget or the lane has no
/// hits, 7.6's fallbacks — so every column in the window fills).
func euclideousRailPlayedColumns(length: Int, shift: Int, neverPlay: Set<Int>) -> Set<Int> {
    Set(euclideousRiffWindowColumns(length: length, shift: shift).filter { !neverPlay.contains($0) })
}

enum EuclideousRailLook: Equatable { case notPlayed, played, trail(Int), current(EuclideousArrowHeading) }
struct EuclideousRailSegment: Equatable { var look: EuclideousRailLook; var opacity: Double }
struct EuclideousRailSpec: Equatable {
    var lane: Int
    var segments: [EuclideousRailSegment]   // eight, one per grid column
    var numberOpacity: Double
    var flare: Double                       // the current segment's glow strength (0 = none)
}
enum EuclideousRailStyle {
    static let trailAlphas = [0.5, 0.32, 0.2], playedAlpha = 0.16, notPlayedRing = 0.08
    static let riffOffOpacity = 0.6, riffOffNumberOpacity = 0.42, mutedOpacity = 0.42
    static let chevronSize: CGFloat = 10, dotSize: CGFloat = 7, chevronAlpha = 0.78, numberSize: CGFloat = 8.5
    static let glowRadius: CGFloat = 8, glowSpread: CGFloat = 2, glowAlpha = 0.65
}
/// §6.2 / §6.4: one rail's eight segments. Riff off → all eight not-played at 60%, the number at 42%, nothing current. A stopped lane or transport (or before the lane's first hit) →
/// the played columns only. Muted by the LANES grid → the segments and the chevron at 42%, the number at full strength. `current` outranks a trail column.
func euclideousRailSpec(lane: Int, riffOn: Bool, running: Bool, muted: Bool, played: Set<Int>, current: Int?, trail: [Int], heading: EuclideousArrowHeading, flare: Double) -> EuclideousRailSpec {
    typealias S = EuclideousRailStyle
    guard riffOn else {
        return EuclideousRailSpec(lane: lane, segments: [EuclideousRailSegment](repeating: EuclideousRailSegment(look: .notPlayed, opacity: S.riffOffOpacity), count: 8),
                                  numberOpacity: S.riffOffNumberOpacity, flare: 0)
    }
    let opacity = muted ? S.mutedOpacity : 1
    var segs = (0..<8).map { EuclideousRailSegment(look: played.contains($0) ? .played : .notPlayed, opacity: opacity) }
    var f = 0.0
    if running, let cur = current, (0..<8).contains(cur) {
        for (k, c) in trail.prefix(3).enumerated() where (0..<8).contains(c) { segs[c].look = .trail(k) }
        segs[cur].look = .current(heading)
        f = flare
    }
    return EuclideousRailSpec(lane: lane, segments: segs, numberOpacity: 1, flare: f)
}

// ── §2.3 the tab-size mini icon ──────────────────────────────────────────────────────────────────────────────────────────────

struct EuclideousMiniIconStyle: Equatable {
    var colPitch: CGFloat, rowPitch: CGFloat, markW: CGFloat, markH: CGFloat, dotW: CGFloat, dotH: CGFloat, markRadius: CGFloat
    /// The 31 × 23 icon every other place draws (4 / 3 pitch, 3 × 2 marks, 1 × 1 dots).
    static let standard = EuclideousMiniIconStyle(colPitch: 4, rowPitch: 3, markW: 3, markH: 2, dotW: 1, dotH: 1, markRadius: 0.5)
    /// The riff TAB ROW's: 21.7 × 12.8 (column pitch 2.8, row pitch 1.65, marks 2.1 × 1.25, dots 0.7 × 0.7).
    static let tab = EuclideousMiniIconStyle(colPitch: 2.8, rowPitch: 1.65, markW: 2.1, markH: 1.25, dotW: 0.7, dotH: 0.7, markRadius: 0.5)
    var size: CGSize { CGSize(width: colPitch * 7 + markW, height: rowPitch * 7 + markH) }
}
struct EuclideousMiniIconGeometry: Equatable {
    var size: CGSize
    var marks: [CGRect]       // one per column that has a note at rank 1…8
    var dots: [CGRect]        // every other (column, row) — a rest is a full column of dots
}
/// Where the icon's marks and dots go for a riff's ranks: a step with a note at rank r draws a mark at row 8 − r; every OTHER row of that step gets a dot centred where a mark
/// would be. At the standard style this is exactly what the icon has always drawn (marks at (4c, 3·row), dots at (4c + 1, 3·row + 0.5)).
func euclideousMiniIconGeometry(ranks: [Int], style: EuclideousMiniIconStyle) -> EuclideousMiniIconGeometry {
    var marks: [CGRect] = [], dots: [CGRect] = []
    for step in 0..<8 {
        let r = step < ranks.count ? ranks[step] : 0
        let noteRow = (r >= 1 && r <= 8) ? (8 - r) : -1
        let x = CGFloat(step) * style.colPitch
        for row in 0..<8 {
            let y = CGFloat(row) * style.rowPitch
            if row == noteRow { marks.append(CGRect(x: x, y: y, width: style.markW, height: style.markH)) }
            else { dots.append(CGRect(x: x + (style.markW - style.dotW) / 2, y: y + (style.markH - style.dotH) / 2, width: style.dotW, height: style.dotH)) }
        }
    }
    return EuclideousMiniIconGeometry(size: style.size, marks: marks, dots: dots)
}

// ── §7 VoiceOver ─────────────────────────────────────────────────────────────────────────────────────────────────────────────

func euclideousHeadingPhrase(_ h: EuclideousArrowHeading) -> String {
    switch h { case .left: return "heading left"; case .right: return "heading right"; case .still: return "staying put" }
}
/// "1, 2 and 3" — a list joined with commas and a final "and".
private func euclideousSpokenList(_ items: [String]) -> String {
    switch items.count {
    case 0: return ""
    case 1: return items[0]
    default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
    }
}
/// §7.1: what a grid cell with an arrow adds after its label: ", lane 1 heading right" (or "heading left", or "staying put"); with several lanes ", lanes 2 and 3: 2 heading left,
/// 3 heading right"; on a rest ", lane 1 heading right, on a rest".
func euclideousArrowCellPhrase(members: [EuclideousArrowMember], onRest: Bool) -> String {
    let sorted = members.sorted { $0.lane < $1.lane }
    guard !sorted.isEmpty else { return "" }
    var s: String
    if sorted.count == 1 { s = ", lane \(sorted[0].lane + 1) \(euclideousHeadingPhrase(sorted[0].heading))" }
    else {
        s = ", lanes \(euclideousSpokenList(sorted.map { "\($0.lane + 1)" })): " + sorted.map { "\($0.lane + 1) \(euclideousHeadingPhrase($0.heading))" }.joined(separator: ", ")
    }
    if onRest { s += ", on a rest" }
    return s
}
/// §7.2: columns as a spoken list, 1-based; runs of three or more read as a range ("1 and 3 to 8", "1 to 4"). `columns` are 0-based.
func euclideousSpokenColumns(_ columns: Set<Int>) -> String {
    let sorted = columns.sorted()
    var items: [String] = []
    var i = 0
    while i < sorted.count {
        var j = i
        while j + 1 < sorted.count, sorted[j + 1] == sorted[j] + 1 { j += 1 }
        if j - i + 1 >= 3 { items.append("\(sorted[i] + 1) to \(sorted[j] + 1)") } else { for k in i...j { items.append("\(sorted[k] + 1)") } }
        i = j + 1
    }
    return euclideousSpokenList(items)
}
/// §7.2: one rail as one static element — "Lane 1: plays columns 1 and 3 to 8, on 4, heading right"; "Lane 2: riff off"; "Lane 4: stopped, plays columns 1 to 4". While the lane is muted
/// it adds ", silent at this step".
func euclideousRailAccessibilityLabel(lane: Int, riffOn: Bool, running: Bool, played: Set<Int>, current: Int?, heading: EuclideousArrowHeading, muted: Bool) -> String {
    var s = "Lane \(lane + 1): "
    if !riffOn { s += "riff off" }
    else {
        if !running { s += "stopped, " }
        s += played.isEmpty ? "plays no columns" : "plays column\(played.count == 1 ? "" : "s") \(euclideousSpokenColumns(played))"
        if running, let c = current { s += ", on \(c + 1), \(euclideousHeadingPhrase(heading))" }
    }
    if muted { s += ", silent at this step" }
    return s
}

// MARK: - NOTES TAB (ferry 2026-10-19, §6-§8) — which hits the lit notes play, the play list, the seven ways, and ROLL / RUN timing
//
// Everything the Router decides about the lit notes, and everything a display shows about it, comes from the functions below — one derivation, never two.
// Pure, allocation-free (fixed SIMD storage, non-escaping closures) and safe on the render thread.

/// The lane facts every per-hit NOTES decision reads: the finished rhythm and the riff walk — scalars only (the pattern `buf` is passed beside it).
struct EuclideousNotesWalk {
    var n: Int
    var dir: EuclidDir
    var cycleLen: Int
    var sub: Double
    var chains: EuclideousLaneRestartChains
    var legacySpanBeats: Double
    var advanceStep: Bool
    var riffDir: RiffDir
    var stride: Int
    var length: Int
    var rotate: Int
    var seed: UInt64
    var every: Int
}

/// 6.4: the count k runs in blocks of this many hits (and restarts at the melody origin).
let euclideousNotesBlock: Int64 = 1024
/// A salt of its own so the NOTES CHANCE rolls never repeat the mask's or RATCHET's.
private let euclideousNotesChanceSalt: UInt64 = 0x4E4F_5445_5343_4841

/// 6.2: PLAYS (bit 0) and RESTS (bit 1) choose a hit when it is not a rest hit and PLAYS is on, or it is a rest hit and RESTS is on.
@inline(__always) func euclideousNotesWhenChooses(when: UInt8, isRestHit: Bool) -> Bool { (when & (isRestHit ? 0b10 : 0b01)) != 0 }

/// 6.3: the CHANCE roll, 0...99, from `splitmix64Mix` (the idiom the mask's chance uses) seeded with the lane and `h` (the hit's index among the lane's pattern hits since the
/// melody origin) plus a salt of its own. Replay-exact: a pure function of (lane, h).
@inline(__always) func euclideousNotesChanceRoll(lane: Int, h: Int64) -> Int {
    let x = UInt64(bitPattern: h) &* 0x9E37_79B9_7F4A_7C15 &+ UInt64(truncatingIfNeeded: lane) &* 0xBF58_476D_1CE4_E5B9 &+ euclideousNotesChanceSalt
    return Int(splitmix64Mix(x) % 100)
}
/// A chosen hit gets through when roll < CHANCE; CHANCE 100 lets every one through.
@inline(__always) func euclideousNotesChanceAllows(chance: Int, lane: Int, h: Int64) -> Bool { chance >= 100 || euclideousNotesChanceRoll(lane: lane, h: h) < chance }

/// h: the hit's index among the lane's pattern hits since the melody origin (the rhythm's hits, before LANES, the mask or FX act on them), 0 for the first — whatever ADVANCE the
/// riff walk uses (under ADV STEP the walk counts ticks, but the notes count hits).
func euclideousNotesHitOrdinal(buf: [Bool], w: EuclideousNotesWalk, tick: Int64) -> Int64 {
    euclideousLaneChainTick(buf: buf, n: w.n, dir: w.dir, cycleLen: w.cycleLen, sub: w.sub, tick: tick, chains: w.chains,
                            legacySpanBeats: w.legacySpanBeats, advanceStep: false).advOrd
}
/// 6.1: the riff column the lane's walk reads at the hit on `tick`, and whether its WRITTEN rank is a rest — worked out whether or not the riff layer is on. INVERT, TRANSPOSE,
/// an FX NOTE offset, the mask's rank modes and ON REST never change it.
func euclideousNotesRiffColumn(buf: [Bool], w: EuclideousNotesWalk, tick: Int64) -> Int {
    let info = euclideousLaneChainTick(buf: buf, n: w.n, dir: w.dir, cycleLen: w.cycleLen, sub: w.sub, tick: tick, chains: w.chains,
                                       legacySpanBeats: w.legacySpanBeats, advanceStep: w.advanceStep)
    return euclideousRiffColumn(ordinal: info.advOrd, every: w.every, direction: w.riffDir, length: w.length, stride: w.stride, shift: w.rotate, seed: w.seed)
}
func euclideousNotesIsRestHit(buf: [Bool], w: EuclideousNotesWalk, tick: Int64, rankAt: (_ column: Int, _ beat: Double) -> Int) -> Bool {
    rankAt(euclideousNotesRiffColumn(buf: buf, w: w, tick: tick), Double(tick) * w.sub) < 1
}

/// 6.4: k for the hit with ordinal `h` on `tick` — the number of EARLIER hits since the melody origin that PLAYS and RESTS chose and CHANCE let through, whatever happened to
/// them next (a LANES mute, the mask, FX TIE, an empty list, the riff taking the pitch). It is counted in blocks of 1024 hits: only the hits from `h − h mod 1024` to `h − 1`.
/// Each earlier hit is decided by 6.1-6.3 with the lane's CURRENT values, so an edit re-derives k instead of carrying old state. `thisBeat` reads every earlier hit's written rank (the
/// grid has no time axis; a looper would — none exists), as the RIFF ferry's REPEAT lookback does.
///   · WHEN both and CHANCE 100: every earlier hit counts — O(1).
///   · ADV HIT: the walk ordinal IS the hit ordinal, so the column of hit h' is a closed form — O(h mod 1024), no ticks.
///   · ADV STEP: the walk ordinal is a tick count, so the earlier hits are found by stepping the lane's ticks backwards (at most 1023 hits, the same shape as REPEAT's lookback).
func euclideousNotesCountBefore(buf: [Bool], w: EuclideousNotesWalk, tick: Int64, h: Int64, when: UInt8, chance: Int, lane: Int,
                                thisBeat: Double, rankAt: (_ column: Int, _ beat: Double) -> Int) -> Int {
    guard h > 0 else { return 0 }
    let blockStart = h - (h % euclideousNotesBlock)
    let want = Int(h - blockStart)
    guard want > 0 else { return 0 }
    if when & 0b11 == 0b11 && chance >= 100 { return want }
    var k = 0
    if !w.advanceStep {
        var hp = blockStart
        while hp < h {
            let col = euclideousRiffColumn(ordinal: hp, every: w.every, direction: w.riffDir, length: w.length, stride: w.stride, shift: w.rotate, seed: w.seed)
            if euclideousNotesWhenChooses(when: when, isRestHit: rankAt(col, thisBeat) < 1) && euclideousNotesChanceAllows(chance: chance, lane: lane, h: hp) { k += 1 }
            hp += 1
        }
        return k
    }
    var found = 0
    var t = tick - 1
    let floorTick = tick - Int64(want + 1) * Int64(max(1, w.cycleLen)) * 4 - 64   // a hard bound for a degenerate (hit-less) pattern
    while found < want && t > floorTick {
        let ph = euclideousLaneChainPhase(buf: buf, n: w.n, dir: w.dir, cycleLen: w.cycleLen, sub: w.sub, tick: t, chains: w.chains, legacySpanBeats: w.legacySpanBeats)
        if ph.rawIsHit {
            found += 1
            let hp = h - Int64(found)
            let info = euclideousLaneChainTick(buf: buf, n: w.n, dir: w.dir, cycleLen: w.cycleLen, sub: w.sub, tick: t, chains: w.chains,
                                               legacySpanBeats: w.legacySpanBeats, advanceStep: true)
            let col = euclideousRiffColumn(ordinal: info.advOrd, every: w.every, direction: w.riffDir, length: w.length, stride: w.stride, shift: w.rotate, seed: w.seed)
            if euclideousNotesWhenChooses(when: when, isRestHit: rankAt(col, thisBeat) < 1) && euclideousNotesChanceAllows(chance: chance, lane: lane, h: hp) { k += 1 }
        }
        t -= 1
    }
    return k
}

/// The play list (6.5): up to eleven notes — a pitch, the lit-order position it came from, and the pool rank it stands for — in fixed storage.
struct EuclideousNotesList: Equatable {
    static let capacity = 16
    private(set) var count = 0
    private var pitches = SIMD16<Int16>(repeating: 0)
    private var positions = SIMD16<UInt8>(repeating: 0)
    private var ranks = SIMD16<Int16>(repeating: 0)
    init() {}
    func pitch(_ i: Int) -> Int { Int(pitches[i]) }
    func position(_ i: Int) -> Int { Int(positions[i]) }
    func rank(_ i: Int) -> Int { Int(ranks[i]) }
    func contains(pitch p: Int) -> Bool { for i in 0..<count where Int(pitches[i]) == p { return true }; return false }
    func index(ofPitch p: Int) -> Int? { for i in 0..<count where Int(pitches[i]) == p { return i }; return nil }
    /// A pitch already in the list is left out ("when its pitch is already in the list").
    mutating func append(pitch p: Int, position: Int, rank: Int) {
        guard count < EuclideousNotesList.capacity, !contains(pitch: p), p >= Int(Int16.min), p <= Int(Int16.max) else { return }
        pitches[count] = Int16(p); positions[count] = UInt8(position); ranks[count] = Int16(rank); count += 1
    }
    /// The list without `pitch` (for 7.2: the riff keeps its pitch).
    func without(pitch p: Int) -> EuclideousNotesList {
        var o = EuclideousNotesList()
        for i in 0..<count where Int(pitches[i]) != p { o.append(pitch: Int(pitches[i]), position: Int(positions[i]), rank: Int(ranks[i])) }
        return o
    }
}
/// 6.5: go through the lit order from first to last. A rank is the pool note at that rank (`resolve` = `riffResolve` against this hit's pool at the notes layer's octave); TOP is the
/// highest received note (rank n); TOP 2 keeps its pair — the second-highest AND the highest (ranks n − 1 and n; one received note gives that note), so it adds up to two pitches.
/// A position is left out when RECEIVED is on and its rank is an octave copy (rank > n; TOP and TOP 2 are received notes, never left out), when it has no note, or when its pitch is
/// already in the list. With nothing held (n = 0) the list is empty.
func euclideousNotesPlayList(order: EuclideousLitOrder, poolCount n: Int, receivedOnly: Bool, resolve: (_ rank: Int) -> Int?) -> EuclideousNotesList {
    var list = EuclideousNotesList()
    guard n > 0 else { return list }
    for i in 0..<order.count {
        let pos = order[i]
        if pos < 8 {
            let rank = pos + 1
            if receivedOnly && rank > n { continue }
            if let p = resolve(rank) { list.append(pitch: p, position: pos, rank: rank) }
        } else if pos == EuclideousLitOrder.topPosition {
            if let p = resolve(n) { list.append(pitch: p, position: pos, rank: n) }
        } else {
            let lo = max(1, n - 1)
            if let p = resolve(lo) { list.append(pitch: p, position: pos, rank: lo) }
            if let p = resolve(n) { list.append(pitch: p, position: pos, rank: n) }
        }
    }
    return list
}

/// The notes a way strikes on one hit, as indices into the play list, in STRIKE ORDER.
struct EuclideousNotesPick: Equatable {
    private(set) var count = 0
    private var idx = SIMD16<UInt8>(repeating: 0)
    init() {}
    subscript(i: Int) -> Int { Int(idx[i]) }
    mutating func append(_ i: Int) { guard count < 16 else { return }; idx[count] = UInt8(i); count += 1 }
}
/// 7.1. With the list L (n notes) and the count k: CHORD every note, together · ROLL every note, low to high when k is even and high to low when k is odd · RUN every note in L's order,
/// one after another across the step · CYCLE L[k mod n] · BOUNCE L[0] for n = 1, else with p = 2n − 2 and x = k mod p: L[x] when x < n, else L[p − x] · SPLIT with L sorted low to high,
/// the lowest alone when k is even and all the others together when k is odd (one note: that note every hit) · BUILD the first (k mod n) + 1 notes. n = 0: nothing.
func euclideousNotesWayPick(list: EuclideousNotesList, way: EuclidNotesPlayAs, k: Int) -> EuclideousNotesPick {
    var out = EuclideousNotesPick()
    let n = list.count
    guard n > 0 else { return out }
    let k = max(0, k)
    func sortedLowToHigh() -> EuclideousNotesPick {
        var s = EuclideousNotesPick()
        var used: UInt16 = 0
        for _ in 0..<n {
            var best = -1
            for i in 0..<n where used & (1 << UInt16(i)) == 0 && (best < 0 || list.pitch(i) < list.pitch(best)) { best = i }
            used |= 1 << UInt16(best); s.append(best)
        }
        return s
    }
    switch way {
    case .chord, .run:
        for i in 0..<n { out.append(i) }
    case .roll:
        let s = sortedLowToHigh()
        if k % 2 == 0 { for i in 0..<n { out.append(s[i]) } } else { var i = n - 1; while i >= 0 { out.append(s[i]); i -= 1 } }
    case .cycle:
        out.append(k % n)
    case .bounce:
        if n == 1 { out.append(0) } else {
            let p = 2 * n - 2, x = k % p
            out.append(x < n ? x : p - x)
        }
    case .split:
        let s = sortedLowToHigh()
        if n == 1 || k % 2 == 0 { out.append(s[0]) } else { for i in 1..<n { out.append(s[i]) } }
    case .build:
        for i in 0...(k % n) { out.append(i) }
    }
    return out
}
/// Does this way index the count k at all? (CHORD and RUN never do — the Router and the lookahead skip the count for them.)
@inline(__always) func euclideousNotesWayUsesCount(_ way: EuclidNotesPlayAs) -> Bool { !(way == .chord || way == .run) }

/// 7.3: ROLL's spacing in beats, for m ≥ 2 notes: s = min(25 ms, R ÷ (m − 1)), R the lesser of half the gap to the lane's next pattern hit and half the notes' length on this hit (the
/// length is ignored when the notes are legato). Note j (counting from 0, in strike order) starts j × s after the hit; every note still ends where it would without the roll.
func euclideousNotesRollSpacingBeats(m: Int, gapBeats: Double, lenBeats: Double, legato: Bool, tempo: Double) -> Double {
    guard m >= 2 else { return 0 }
    let r = legato ? gapBeats / 2 : min(gapBeats / 2, lenBeats / 2)
    return max(0, min(0.025 * tempo / 60.0, r / Double(m - 1)))
}
/// 7.4: RUN's slot in beats — the lane's step length ÷ m. Note j starts j × slot after the hit and lasts its effective gate as a share of its slot.
@inline(__always) func euclideousNotesRunSlotBeats(stepBeats: Double, m: Int) -> Double { m > 0 ? stepBeats / Double(m) : stepBeats }

// MARK: - NOTES TAB layout (ferry 2026-10-19, §1, §3, §4) — every frame, from the content width and the two zones' heights
//
// Frames are in the tab's CONTENT coordinates: (0, 0) is the top-left of the upper zone (card x 10, y 94 at the reference), `width` the content width (338.5 at the reference) and `height` both zones and
// the gap between them (208). The upper zone is the RHYTHM tab's own (`contentAreaH − patternBlockH(80) − sp4`), the lower zone its fixed 80.

struct EuclideousNotesTabLayout: Equatable {
    static let stripW: CGFloat = 35, stripGap: CGFloat = 3, labelW: CGFloat = 48, rowH: CGFloat = 38, chanceW: CGFloat = 88
    static let keyGap: CGFloat = 2, topTwoExtraGap: CGFloat = 4, pickerPad: CGFloat = 6, pickerHeaderH: CGFloat = 18, closeW: CGFloat = 30
    static let keyFloorW: CGFloat = 24, keyRowFloorH: CGFloat = 64, rowFloorH: CGFloat = 32
    var content: CGRect
    var strip: CGRect
    var keys: [CGRect]                 // ranks 1-8, then TOP 2, then TOP
    var keyRow: CGRect, whenRow: CGRect, playAsRow: CGRect, soundRow: CGRect
    var whenLabel: CGRect, playAsLabel: CGRect, soundLabel: CGRect
    var plays: CGRect, rests: CGRect, chance: CGRect, playAs: CGRect, received: CGRect
    var picker: CGRect, pickerHeader: CGRect, pickerClose: CGRect
    var pickerCells: [CGRect]          // CHORD, ROLL, RUN, then CYCLE, BOUNCE, SPLIT, BUILD
    var underFloor: Bool
    var floorFlags: [String]
}
func euclideousNotesTabLayout(contentAreaH: CGFloat, fullWidth: CGFloat, sp4: CGFloat = 4) -> EuclideousNotesTabLayout {
    typealias L = EuclideousNotesTabLayout
    let patternBlockH: CGFloat = 80
    let upperH = max(1, contentAreaH - patternBlockH - sp4)
    let lowerRowH = max(1, (patternBlockH - sp4) / 2)
    let keyRowH = max(1, upperH - sp4 - L.rowH)
    let colX = L.stripW + L.stripGap
    let colW = max(1, fullWidth - colX)
    let keyW = max(1, (colW - (7 * L.keyGap + (L.keyGap + L.topTwoExtraGap) + L.keyGap)) / 10)
    var keys: [CGRect] = []
    var x = colX
    for i in 0..<10 {
        keys.append(CGRect(x: x, y: 0, width: keyW, height: keyRowH))
        x += keyW + L.keyGap + (i == 7 ? L.topTwoExtraGap : 0)
    }
    let whenY = keyRowH + sp4, playAsY = upperH + sp4, soundY = playAsY + lowerRowH + sp4
    let ctrlX = colX + L.labelW + sp4                 // where a row's controls start, after its label column
    let toggleW = max(1, (fullWidth - ctrlX - L.chanceW - sp4 - sp4) / 2)
    let plays = CGRect(x: ctrlX, y: whenY, width: toggleW, height: L.rowH)
    let rests = CGRect(x: plays.maxX + sp4, y: whenY, width: toggleW, height: L.rowH)
    let chance = CGRect(x: fullWidth - L.chanceW, y: whenY, width: L.chanceW, height: L.rowH)
    let wide = max(1, fullWidth - ctrlX)
    let playAs = CGRect(x: ctrlX, y: playAsY, width: wide, height: lowerRowH)
    let received = CGRect(x: ctrlX, y: soundY, width: wide, height: lowerRowH)
    // the picker: both zones and the gap, 6 pt padding, a header row, then two rows of ways splitting the rest
    let pad = L.pickerPad
    let innerW = max(1, fullWidth - 2 * pad)
    let waysH = max(1, (contentAreaH - 2 * pad - L.pickerHeaderH - 2 * sp4) / 2)
    let row1Y = pad + L.pickerHeaderH + sp4, row2Y = row1Y + waysH + sp4
    let top3W = max(1, (innerW - 2 * sp4) / 3), bottom4W = max(1, (innerW - 3 * sp4) / 4)
    var cells: [CGRect] = []
    for i in 0..<3 { cells.append(CGRect(x: pad + CGFloat(i) * (top3W + sp4), y: row1Y, width: top3W, height: waysH)) }
    for i in 0..<4 { cells.append(CGRect(x: pad + CGFloat(i) * (bottom4W + sp4), y: row2Y, width: bottom4W, height: waysH)) }
    var flags: [String] = []
    if keyW < L.keyFloorW { flags.append("keys \(keyW)") }
    if keyRowH < L.keyRowFloorH { flags.append("key row \(keyRowH)") }
    if L.rowH < L.rowFloorH || lowerRowH < L.rowFloorH { flags.append("rows \(min(L.rowH, lowerRowH))") }
    return EuclideousNotesTabLayout(
        content: CGRect(x: 0, y: 0, width: fullWidth, height: contentAreaH),
        strip: CGRect(x: 0, y: 0, width: L.stripW, height: contentAreaH),
        keys: keys,
        keyRow: CGRect(x: colX, y: 0, width: colW, height: keyRowH),
        whenRow: CGRect(x: colX, y: whenY, width: colW, height: L.rowH),
        playAsRow: CGRect(x: colX, y: playAsY, width: colW, height: lowerRowH),
        soundRow: CGRect(x: colX, y: soundY, width: colW, height: lowerRowH),
        whenLabel: CGRect(x: colX, y: whenY, width: L.labelW, height: L.rowH),
        playAsLabel: CGRect(x: colX, y: playAsY, width: L.labelW, height: lowerRowH),
        soundLabel: CGRect(x: colX, y: soundY, width: L.labelW, height: lowerRowH),
        plays: plays, rests: rests, chance: chance, playAs: playAs, received: received,
        picker: CGRect(x: 0, y: 0, width: fullWidth, height: contentAreaH),
        pickerHeader: CGRect(x: pad, y: pad, width: innerW, height: L.pickerHeaderH),
        pickerClose: CGRect(x: fullWidth - pad - L.closeW, y: pad, width: L.closeW, height: L.pickerHeaderH),
        pickerCells: cells, underFloor: !flags.isEmpty, floorFlags: flags)
}

/// One bar of a way preview (3.3, 4.4): the pool rank row it sits in (1 = the bottom row, 8 = the top) and its horizontal span as fractions of the row's width.
struct EuclideousNotesPreviewBar: Equatable { var rank: Int; var x: Double; var w: Double }
/// 10.6: column `k` of a preview shows 7.1's notes for that k with the CURRENT play list — ignoring the riff, WHEN, CHANCE and the riff-pitch drop (7.2). A bar spans its row, except under RUN, where
/// note j of m covers the j-th m-th of the row left to right in strike order, and under ROLL, where each bar is 76% of the row wide and note j of m starts j × 24 ÷ (m − 1) % in, in strike order.
/// With one note, either spans its row. A note whose rank is not one of the grid's eight rows (TOP over a pool of more than eight) has no row to sit in.
func euclideousNotesPreviewBars(list: EuclideousNotesList, way: EuclidNotesPlayAs, k: Int) -> [EuclideousNotesPreviewBar] {
    let pick = euclideousNotesWayPick(list: list, way: way, k: k)
    let m = pick.count
    var bars: [EuclideousNotesPreviewBar] = []
    for j in 0..<m {
        let rank = list.rank(pick[j])
        guard rank >= 1, rank <= 8 else { continue }
        switch way {
        case .run where m >= 2: bars.append(EuclideousNotesPreviewBar(rank: rank, x: Double(j) / Double(m), w: 1 / Double(m)))
        case .roll where m >= 2: bars.append(EuclideousNotesPreviewBar(rank: rank, x: Double(j) * 0.24 / Double(m - 1), w: 0.76))
        default: bars.append(EuclideousNotesPreviewBar(rank: rank, x: 0, w: 1))
        }
    }
    return bars
}
/// 10.3: under RUN, CYCLE, BOUNCE and BUILD each key whose note is in the play list shows its 1-based place in the list; keys left out of the list show none, and CHORD, ROLL and SPLIT show none at
/// all. Index = lit-order position (0-7 ranks, 8 TOP 2, 9 TOP). TOP 2 keeps its pair, so it can hold two places: "2–3".
func euclideousNotesPlaceNumbers(list: EuclideousNotesList, way: EuclidNotesPlayAs) -> [String?] {
    var out = [String?](repeating: nil, count: 10)
    guard way == .run || way == .cycle || way == .bounce || way == .build else { return out }
    for pos in 0..<10 {
        var places: [Int] = []
        for i in 0..<list.count where list.position(i) == pos { places.append(i + 1) }
        if let f = places.first, let l = places.last { out[pos] = f == l ? "\(f)" : "\(f)\u{2013}\(l)" }
    }
    return out
}

// MARK: - NOTES TAB VoiceOver (ferry 2026-10-19, §11; U+2019 for apostrophes)

let euclideousNotesKeyRowGroupLabel = "Lit notes: the riff grid\u{2019}s eight rows, then the top two received notes"
let euclideousNotesWhenGroupLabel = "When the notes play"
let euclideousNotesPlayAsGroupLabel = "How the lit notes play"
let euclideousNotesSoundOnlyGroupLabel = "Which lit notes sound"
let euclideousNotesPickerGroupLabel = "Play the lit notes as"
let euclideousNotesPickerCloseLabel = "Close, keeping the current way"
let euclideousNotesPlaysLabel = "Play on hits where the riff plays a note"
let euclideousNotesRestsLabel = "Play on hits where the riff rests"
let euclideousNotesReceivedLabel = "Sound only received notes"
let euclideousNotesReceivedHint = "Lit octave copies stay silent"
let euclideousNotesPlayAsHint = "Choose another way to play"

/// 11.7: a way’s sentence ("One lit note a hit, in the order you lit them"). 11.8 reads the same sentence after the way’s name.
func euclideousNotesWayDescription(_ way: EuclidNotesPlayAs) -> String {
    switch way {
    case .chord: return "every lit note at once"
    case .roll: return "every lit note in a quick strum, upwards and downwards on alternate hits"
    case .run: return "every lit note one after another, spread across the hit\u{2019}s step, in the order you lit them"
    case .cycle: return "one lit note a hit, in the order you lit them"
    case .bounce: return "one lit note a hit, through the order you lit them and back"
    case .split: return "the lowest lit note on one hit, the rest together on the next"
    case .build: return "one more lit note each hit, in the order you lit them, then start again"
    }
}
private func euclideousNotesCapitalised(_ s: String) -> String { s.prefix(1).uppercased() + s.dropFirst() }
/// 11.8: "Chord: every lit note at once".
func euclideousNotesWayAccessibilityLabel(_ way: EuclidNotesPlayAs) -> String { "\(euclideousNotesCapitalised(way.rawValue.lowercased())): \(euclideousNotesWayDescription(way))" }
/// 11.7: the button reads "Play as cycle", with the sentence as its value.
func euclideousNotesPlayAsButtonLabel(_ way: EuclidNotesPlayAs) -> String { "Play as \(way.rawValue.lowercased())" }
func euclideousNotesPlayAsButtonValue(_ way: EuclidNotesPlayAs) -> String { euclideousNotesCapitalised(euclideousNotesWayDescription(way)) }
/// 11.5: PLAYS and RESTS are toggles; the only one that is on says why a tap does nothing, and while the riff is off both add that it still decides.
func euclideousNotesWhenHint(isOnlyOneOn: Bool, riffOn: Bool) -> String {
    var parts: [String] = []
    if isOnlyOneOn { parts.append("One of the two always stays on") }
    if !riffOn { parts.append("The riff is off but still decides") }
    return parts.joined(separator: ". ")
}
/// 11.6: CHANCE as one adjustable element.
func euclideousNotesChanceValue(_ chance: Int) -> String {
    chance >= 100 ? "100 percent: every chosen hit plays" : "\(chance) percent: each chosen hit plays \(chance) times in 100"
}
/// "1st", "2nd", "3rd", "4th", … "11th".
func euclideousNotesOrdinal(_ n: Int) -> String {
    let m100 = n % 100
    if (11...13).contains(m100) { return "\(n)th" }
    switch n % 10 { case 1: return "\(n)st"; case 2: return "\(n)nd"; case 3: return "\(n)rd"; default: return "\(n)th" }
}
/// 11.3: "Rank 6, A flat 3, received, lit, 3rd in the lit order". `spokenNote` nil = nothing held. `place` is the place number the key shows (10.3), if any.
func euclideousNotesRankKeyAccessibilityLabel(rank: Int, spokenNote: String?, received: Bool, lit: Bool, heldBack: Bool, place: String?) -> String {
    var s = "Rank \(rank), \(spokenNote ?? "nothing held"), \(received ? "received" : "an octave copy"), \(lit ? "lit" : "not lit")"
    if heldBack { s += ", held back because only received notes sound" }
    if let place { s += ", \(euclideousNotesSpokenPlace(place)) in the lit order" }
    return s
}
/// "3" -> "3rd"; "2–3" -> "2nd and 3rd".
func euclideousNotesSpokenPlace(_ place: String) -> String {
    let parts = place.split(separator: "\u{2013}").compactMap { Int($0) }
    return parts.map(euclideousNotesOrdinal).joined(separator: " and ")
}
/// 11.4: TOP 2 keeps its pair ("The two highest received notes, A flat 3 and B flat 3, not lit"; with one received note it is that note); TOP is "The highest received note, B flat 3, lit".
/// `spokenNotes` empty = nothing held.
func euclideousNotesTopKeyAccessibilityLabel(isTopTwo: Bool, spokenNotes: [String], lit: Bool, place: String?) -> String {
    let what: String
    if isTopTwo { what = spokenNotes.count >= 2 ? "The two highest received notes" : "The highest received note" } else { what = "The highest received note" }
    let notes = spokenNotes.isEmpty ? "nothing held" : spokenNotes.joined(separator: " and ")
    var s = "\(what), \(notes), \(lit ? "lit" : "not lit")"
    if let place { s += ", \(euclideousNotesSpokenPlace(place)) in the lit order" }
    return s
}

// MARK: - NOTES TAB displays (ferry 2026-10-19, §10) — keys light as their notes sound, the riff dot, the comet strip's pips and the grey footers

/// 10.1 / 10.2: what the keys show for one lane at one moment, worked out from the lane's latest strike (its pitches from the NOTE VIEW event, its velocities and display-clock onset from the feed) and §6-§7's own functions
/// (no engine path of its own): which lit-order positions are sounding (0…1 glow strength = §1's flash f for the notes layer's played velocity, from each note's START — the hit, or its ROLL / RUN offset — PULSE ferry
/// 2026-10-20 §8.1, replacing the comet bar's step-based timing), and the rank key the riff dot sits on (f for the riff note's velocity). A key never lights for a note the riff took (event note 0 is the riff's pitch when the
/// hit has one — it is skipped) and a held-back key has no entry in the list.
struct EuclideousNotesKeyFlash: Equatable {
    var sounding: [Double] = Array(repeating: 0, count: 10)
    var riffDotRank: Int? = nil
    var riffDotStrength: Double = 0
}
/// - `eventPitches`: the pitches the hit struck, in strike order (the NOTE VIEW event's `notes`; the riff note first when `hasRiffNote`).
/// - `seconds`: time since the strike's onset (the hit); `riffVel` / `notesVel`: the velocities the two layers played.
/// - `list`: the CURRENT play list built at octave 0; `pitchShift` is 12 × the lane's notes octave (what the engine added when it resolved them).
func euclideousNotesKeyFlash(eventPitches: [UInt8], hasRiffNote: Bool, riffRank: Int, seconds: Double, riffVel: Int, notesVel: Int, list: EuclideousNotesList, pitchShift: Int, way: EuclidNotesPlayAs,
                             stepBeats: Double, gapBeats: Double, lenBeats: Double, legato: Bool, tempo: Double, scale: Double) -> EuclideousNotesKeyFlash {
    var out = EuclideousNotesKeyFlash()
    let first = hasRiffNote ? 1 : 0
    var matched: [Int] = []   // list indices, in strike order
    if eventPitches.count > first {
        for k in first..<eventPitches.count {
            if let i = list.index(ofPitch: Int(eventPitches[k]) - pitchShift) { matched.append(i) }
        }
    }
    let m = matched.count
    let secPerBeat = 60.0 / max(1.0, tempo)
    var spacing = 0.0   // beats between one note's start and the next
    if way == .roll, m >= 2 { spacing = euclideousNotesRollSpacingBeats(m: m, gapBeats: gapBeats, lenBeats: lenBeats, legato: legato, tempo: tempo) }
    if way == .run, m >= 1 { spacing = euclideousNotesRunSlotBeats(stepBeats: stepBeats, m: m) }
    for (j, i) in matched.enumerated() {
        let strength = euclideousPulseEnvelopes(velocity: notesVel, seconds: seconds - Double(j) * spacing * secPerBeat, scale: scale).f
        let pos = list.position(i)
        if pos >= 0, pos < 10 { out.sounding[pos] = max(out.sounding[pos], strength) }
    }
    if hasRiffNote, (1...8).contains(riffRank) {
        out.riffDotRank = riffRank
        out.riffDotStrength = euclideousPulseEnvelopes(velocity: riffVel, seconds: seconds, scale: scale).f
    }
    return out
}

/// 10.4: each hit cell of the comet strip whose hit PLAYS and RESTS choose gets a pip — a fill at CHANCE 100, a ring below (CHANCE may skip the hit). 0 none, 1 fill, 2 ring.
/// `states` is the footer's own per-step prediction (the SAME one the footers draw), so a pip can never sit on a hit the footers don't show. A hit an FX TIE cell applies to strikes
/// nothing, so it gets none; a miss is no hit.
func euclideousNotesPips(states: [EuclidFooterState], when: UInt8, chance: Int) -> [UInt8] {
    states.map { st in
        switch st {
        case .hit: return euclideousNotesWhenChooses(when: when, isRestHit: false) ? (chance >= 100 ? 1 : 2) : 0
        case .hitOnRest: return euclideousNotesWhenChooses(when: when, isRestHit: true) ? (chance >= 100 ? 1 : 2) : 0
        case .hitTied, .miss: return 0
        }
    }
}
/// 10.5: with the riff OFF, the notes layer ON and only one of PLAYS and RESTS on, the footers show on every tab as they would with the riff on — but grey — so you can see which hits
/// the riff's written columns decide. Otherwise, with the riff off, they are as they always were.
func euclideousNotesGreyFooters(riffOn: Bool, notesLayerOn: Bool, when: UInt8) -> Bool {
    !riffOn && notesLayerOn && ((when & 0b11) == 0b01 || (when & 0b11) == 0b10)
}

// The picker's cell order (§4.3: the top row plays every lit note on each hit, the bottom row a changing set) and each way's one-line description (§4.4).
let euclideousNotesWayDescriptions: [EuclidNotesPlayAs: String] = [
    .chord: "ALL AT ONCE", .roll: "A QUICK STRUM", .run: "ACROSS THE STEP", .cycle: "ONE AT A TIME", .bounce: "TO AND FRO", .split: "LOW THEN REST", .build: "STACKS UP",
]
let euclideousNotesWayOrder: [EuclidNotesPlayAs] = [.chord, .roll, .run, .cycle, .bounce, .split, .build]


// MARK: - PULSE (ferry 2026-10-20 "strikes that show velocity …") — the one strike envelope, the gap decision, the level mark, the tail, the ripple, the ring
//
// Every number a strike effect draws with comes from here (Foundation-only, allocation-free per call); the painters only paint it and the tests pin it. Colour is the lane's identity and NEVER
// shows velocity — velocity only shows through brightness, size and reach (1.7). Nothing here animates at rest: every effect starts at a strike and ends by itself (1.8).

/// PULSE setting → the scale P (7.1): OFF 0, SUBTLE 0.6, FULL 1. The stored level is 0 / 1 / 2 (anything else reads FULL).
func euclideousPulseScale(level: Int) -> Double { level == 0 ? 0 : (level == 1 ? 0.6 : 1) }
let euclideousPulseMaxAge: Double = 1.5

/// 1.1: how much a note of velocity `v` (1…127) shows — a soft note still registers: vis = 0.2 + 0.8 × (v ÷ 127)^1.3.
func euclideousPulseVis(_ v: Int) -> Double { 0.2 + 0.8 * pow(Double(max(0, min(127, v))) / 127.0, 1.3) }

/// The four decays of one strike, `t` seconds after its onset: burst b (τ 0.05), flash f (τ 0.16), key k (τ 0.08), tail a (τ 0.35) — each vis × P × e^(−t ÷ τ), clamped 0…1.
/// A strike that hasn't happened yet (t < 0), is older than 1.5 s, or has every value under 0.01 draws nothing.
struct EuclideousPulseEnvelopes: Equatable {
    var b = 0.0, f = 0.0, k = 0.0, a = 0.0
    static let none = EuclideousPulseEnvelopes()
    var isVisible: Bool { b >= 0.01 || f >= 0.01 || k >= 0.01 || a >= 0.01 }
}
func euclideousPulseEnvelopes(velocity: Int, seconds t: Double, scale p: Double) -> EuclideousPulseEnvelopes {
    guard t >= 0, t <= euclideousPulseMaxAge, p > 0, velocity > 0 else { return .none }
    let base = euclideousPulseVis(velocity) * p
    func e(_ tau: Double) -> Double { max(0, min(1, base * exp(-t / tau))) }
    let env = EuclideousPulseEnvelopes(b: e(0.05), f: e(0.16), k: e(0.08), a: e(0.35))
    return env.isVisible ? env : .none
}




/// 5.2: the MIX ripple around a puck of diameter `d0`: p = min(1, t ÷ 0.36), diameter d0 + 44 × p × (0.35 + 0.65 × vis), opacity (1 − p) × vis × P. nil when it isn't alive.
func euclideousPulseRipple(d0: CGFloat, velocity: Int, seconds t: Double, scale p: Double) -> (diameter: CGFloat, opacity: Double)? {
    guard t >= 0, t < 0.36, p > 0, velocity > 0 else { return nil }
    return euclideousPulseRipple(d0: d0, vis: euclideousPulseVis(velocity), progress: min(1, t / 0.36), scale: p)
}
/// 5.2 in its own terms — `vis` and the progress p = min(1, t ÷ 0.36) — so the ferry's worked numbers can be asserted literally.
func euclideousPulseRipple(d0: CGFloat, vis: Double, progress q: Double, scale p: Double) -> (diameter: CGFloat, opacity: Double) {
    (d0 + 44 * CGFloat(q) * CGFloat(0.35 + 0.65 * vis), (1 - q) * vis * p)
}

/// 6.1: the sounding quarter's stroke 2.5 + 2.5 × f, and the letter's white while f > 0.35.
func euclideousPulseRingStroke(f: Double) -> CGFloat { 2.5 + 2.5 * CGFloat(max(0, min(1, f))) }
/// 6.1: the letter draws #FFFFFF while f > 0.35 — on a ring whose letter is the lit one (`.on`). A HELD ring keeps its ink letter on the light disc (6.3: held is unchanged), and an off / unrouted ring has no strike.
func euclideousPulseRingLetterIsWhite(f: Double, tone: EuclideousRingLetterTone = .on) -> Bool { tone == .on && f > 0.35 }
/// 4.3: the riff panel's note name lights in the lane's colour while f > 0.12.
func euclideousPulseNameLit(f: Double) -> Bool { f > 0.12 }

/// 2.1: a GAP is a hit tile whose hit — in the pass the footers show — reads a riff REST with ON REST at SKIP or TIE (FILL decodes as SKIP). REPEAT hits strike and are not gaps; an FX-tied hit is
/// not a riff rest and stays a normal tile (Paul 2026-10-20); with the riff off there are no gaps (2.6). The footer states are the footers' own per-hit decision, so a gap switches exactly when the footers do.
func euclideousPulseIsGap(state: EuclidFooterState, onRest: EuclidRiffOnRest, riffOn: Bool) -> Bool {
    guard riffOn, case .hitOnRest = state else { return false }
    return onRest == .skip || onRest == .tie || onRest == .fill
}

/// 6: a ring shows a strike of either layer — the louder one.
func euclideousPulseRingVelocity(riffVel: Int, notesVel: Int) -> Int { max(riffVel, notesVel) }

/// 7: what each strike effect does under the PULSE scale and Reduce Motion. OFF (P = 0): every strike effect is off. Reduce Motion: no chip dip (the lane strip's key dip move), no ripple, no puck
/// swell, no arrow scale; glows, washes, overlays and the note name stay. (The comet's dot swell, tail, flare core and level mark were removed by the LANE STRIP ferry, 2026-10-21.)
enum EuclideousPulseEffect: CaseIterable { case keyDipMove, ripple, puckSwell, arrowScale, glow, wash, overlay, noteName, letter }
enum EuclideousPulseTreatment: Equatable { case off, full }
func euclideousPulseFilter(_ effect: EuclideousPulseEffect, scale p: Double, reduceMotion: Bool) -> EuclideousPulseTreatment {
    guard p > 0 else { return .off }
    guard reduceMotion else { return .full }
    switch effect {
    case .keyDipMove, .ripple, .puckSwell, .arrowScale: return .off
    default: return .full
    }
}

/// One strike as the feed keeps it: the onset beat (the engine's real beat — it maps the strike to its comet tile) and `onsetAt`, the same moment on the DISPLAY clock (`timeIntervalSinceReferenceDate`),
/// worked out ONCE when the event arrives from the dejittered beat anchor the comet dot reads — so a strike draws in the frame the dot reaches its tile, and keeps decaying in wall time even after the
/// anchor stops advancing (a stopped transport re-anchors every poll). `riffVel` / `notesVel` are the velocities those layers played (0 = that layer didn't strike on this hit).
struct EuclideousPulseStrike: Equatable { var onsetBeat: Double; var onsetAt: Double; var riffVel: UInt8; var notesVel: UInt8; var rank: Int8 = -1; var column: Int8 = -1
    /// RESTART TILES ferry (2026-10-22): the riff column whose NOTE this hit struck (`column`, except a REPEAT hit's repeated note) — the MELODY tile's cell for the strike. -1 = no riff note.
    var cellColumn: Int8 = -1
    /// The comet tile this strike belongs to, resolved ONCE (`EuclideousPulseFeed.resolveTiles`) for the lane geometry `tileKey` names — the chain-aware mapping is not free, so it is not redone every frame. -1 = not resolved yet.
    var tile: Int16 = -1; var tileKey: Int = 0 }   // `rank` / `column`: the riff-grid row and column the engine reports for this hit (REPEAT's rank is the repeated note's); -1 = none

/// 9.2: the small retained list per lane, filled from the existing NOTE VIEW poll (nothing new is polled). Main-thread only (filled by the poll, read inside the surfaces' TimelineViews), held in
/// `LiveTelemetry` so filling it never re-runs the page body. A strike is a kind 0 / 3 event that carries notes; a rest flash (kind 2), a tied rest with nothing struck and a muted / FX-tied hit post
/// no event, so they never appear here.
final class EuclideousPulseFeed {
    static let ringCap = 48
    private var rings: [[EuclideousPulseStrike]] = Array(repeating: [], count: 4)
    private var playing = false
    /// When the transport / free-run stopped (nil while playing or before anything played): the surfaces keep animating for 1.5 s after it, then idle.
    private(set) var stoppedAt: Date? = nil
    init() {}
    /// `anchorBeat` / `anchorAt` / `tempo`: the UI beat clock the comet dot extrapolates from (`LiveTelemetry.beatAnchor`, `beatAnchorAt`, `tempo`).
    func ingest(lane: Int, events: [Router.EuclideousNoteViewEventSnapshot], anchorBeat: Double, anchorAt: Date, tempo: Double) {
        guard lane >= 0, lane < 4 else { return }
        let secPerBeat = 60.0 / max(1.0, tempo)
        for ev in events where (ev.kind == 0 || ev.kind == 3) && !ev.notes.isEmpty {
            if let last = rings[lane].last, ev.onsetBeat < last.onsetBeat - 0.5 { rings[lane].removeAll(keepingCapacity: true) }   // the beat went back: a restart or a loop
            func vel(_ i: Int) -> UInt8 { i < ev.vels.count ? ev.vels[i] : 100 }
            let first = ev.hasRiffNote ? 1 : 0
            var notes: UInt8 = 0
            if ev.notes.count > first { for i in first..<ev.notes.count { notes = max(notes, vel(i)) } }
            let at = anchorAt.timeIntervalSinceReferenceDate + (ev.onsetBeat - anchorBeat) * secPerBeat
            rings[lane].append(EuclideousPulseStrike(onsetBeat: ev.onsetBeat, onsetAt: at, riffVel: ev.hasRiffNote ? vel(0) : 0, notesVel: notes, rank: ev.hasRiffNote ? ev.rank : -1, column: ev.hasRiffNote ? ev.column : -1, cellColumn: ev.hasRiffNote ? ev.cellColumn : -1))
            if rings[lane].count > Self.ringCap { rings[lane].removeFirst(rings[lane].count - Self.ringCap) }
        }
    }
    /// Chronological, oldest first.
    func strikes(lane: Int) -> [EuclideousPulseStrike] { lane >= 0 && lane < 4 ? rings[lane] : [] }
    /// The lane's strikes with every strike's comet tile resolved for the geometry `key` (see `euclideousPulseGeometryKey`): a strike is mapped once, when it first draws, and again only if the lane's pattern, rate, direction, chains or swing
    /// change. Per frame this is a scan that finds nothing to do.
    func resolveTiles(lane: Int, key: Int, tileOf: (Double) -> Int) -> [EuclideousPulseStrike] {
        guard lane >= 0, lane < 4 else { return [] }
        for i in rings[lane].indices where rings[lane][i].tile < 0 || rings[lane][i].tileKey != key {
            rings[lane][i].tile = Int16(max(0, min(Int(Int16.max), tileOf(rings[lane][i].onsetBeat))))
            rings[lane][i].tileKey = key
        }
        return rings[lane]
    }
    func latest(lane: Int, where keep: (EuclideousPulseStrike) -> Bool = { _ in true }) -> EuclideousPulseStrike? {
        guard lane >= 0, lane < 4 else { return nil }
        return rings[lane].last(where: keep)
    }
    /// The latest strike that has HAPPENED by `now` (a reference-date time) on the given layer — a strike still in the future is not there yet, and must not hide the one before it that is still fading.
    func latestHappened(lane: Int, now: Double, riff: Bool) -> EuclideousPulseStrike? { latest(lane: lane) { $0.onsetAt <= now && (riff ? $0.riffVel > 0 : $0.notesVel > 0) } }
    /// Called from the poll when the playing flag is (re)read — only an EDGE does anything: a start clears the strikes of the last run (their beats mean nothing now), a stop stamps the moment.
    func noteTransport(playing now: Bool, at when: Date) {
        // The start edge is read at the 4 Hz poll, up to 0.25 s after it happened; strikes that arrived meanwhile (30 Hz poll) belong to the new run, so only the older ones go.
        if now { if !playing { let cut = when.timeIntervalSinceReferenceDate - 0.5; for i in rings.indices { rings[i].removeAll { $0.onsetAt < cut } } }; stoppedAt = nil }
        else if playing { stoppedAt = when }
        playing = now
    }
    func reset() { for i in rings.indices { rings[i].removeAll(keepingCapacity: true) }; stoppedAt = nil; playing = false }
    /// 9.1: the surfaces run while playing, and for the 1.5 s the last strikes (and the marks' fade) need after it stops.
    func isSettling(now: Date) -> Bool { stoppedAt.map { now.timeIntervalSince($0) < euclideousPulseMaxAge } ?? false }
}

/// The comet tile a strike belongs to: the buffer step the engine read at the onset tick — the same index `footerStates[i]` and the tile loop use. `rawAtOnset` is the comet's raw tick count at the strike's
/// MUSICAL onset beat (the same function the dot uses); onsets sit on tick boundaries, so it is rounded to the nearest tick.
func euclideousPulseTileForOnset(rawAtOnset: Double, n: Int, dir: EuclidDir) -> Int {
    let cl = max(1, euclidCycleLen(dir, n: n))
    var k = Int(rawAtOnset.rounded()) % cl
    if k < 0 { k += cl }
    return max(0, min(max(1, n) - 1, euclidReadIndex(k, n: n, dir: dir)))
}

/// What the tile mapping depends on: the lane's step count, direction, step length, span, swing and restart chains. Two keys are equal exactly when `euclideousPulseTileForOnset` would map every onset the same way.
func euclideousPulseGeometryKey(n: Int, dir: EuclidDir, sub: Double, spanBeats: Double, swing: Double, stepBeats: Double, chains: EuclideousLaneRestartChains?) -> Int {
    var h = Hasher()
    h.combine(n); h.combine(dir.rawValue); h.combine(sub.bitPattern); h.combine(spanBeats.bitPattern); h.combine(swing.bitPattern); h.combine(stepBeats.bitPattern)
    if let c = chains { h.combine(c.rhythm.packed); h.combine(c.melody.packed); h.combine(c.barBeats.bitPattern); h.combine(c.lapBeats.bitPattern) }
    return h.finalize()
}

// MARK: - LANE STRIP (ferry 2026-10-21 "a riff contour over a row of notes keys, in place of the comet")
//
// The lane card's 44 pt header strip is two rows on today's step columns: a 27 pt RIFF TRACK (a dark cell per step; on each hit that reads a riff note a light CHIP numbered with its
// riff column, at a height set by its rank, so the strip traces the riff's melody the way the riff grid draws it; the lane's current note in the lane colour; a playhead band instead of
// the comet dot) over a 14 pt KEY ROW (a key per hit, in the NOTES tab's key look, lit with the lane bar and the note's name when the notes will play on that hit). Every number below is
// built from the footers', the arrow's and the notes functions that already exist — nothing here re-derives what the engine decides. Display only: nothing here reaches the engine,
// the snapshot or the document. `LaneStripPainter.swift` only paints what these return.
//
// LANE STRIP readability ferry (2026-10-22): the Euclid pattern had gone quiet — a hit and a rhythm
// rest read as the same grey, and the only lane colour on the whole strip was a 45% ring on a riff
// gap. Each layer now has one job: rhythm = lane colour (a 24%-fill/70%-border hit column plus a
// solid lane-coloured floor bar), riff = the white chips (nudged up so they never cover the floor
// bar), notes = the grey key row (untouched). See `euclideousStripFloorBarFrame`/
// `euclideousStripDrawsAsHit` below and `LaneStripPainter.swift`'s columns loop.

enum EuclideousStripMetrics {
    static let trackH: CGFloat = 27, keyRowH: CGFloat = 14, rowGap: CGFloat = 3
    static let columnRadius: CGFloat = 4, keyRadius: CGFloat = 3
    static let chipH: CGFloat = 9, chipInset: CGFloat = 2, chipRadius: CGFloat = 2
    static let chipLabelLine: CGFloat = 9, keyLabelLine: CGFloat = 8
    static let chipLabelSize: CGFloat = 7, keyLabelSize: CGFloat = 7
    /// §1.2 / §3.2: a column narrower than this draws no chip label, a key narrower than this no key label.
    static let chipLabelFloor: CGFloat = 12, keyLabelFloor: CGFloat = 16
    /// LANE STRIP readability ferry §2.1/§6.1: a chip's top is (8 − r) × 2 from its column's top, so rank 8
    /// sits at 0 and rank 1 at 14 (its 9-tall chip then ends at 23, 1 pt clear of the floor bar at 24).
    /// Still expressed as `chipTravel ÷ 7` below (14 ÷ 7 = 2) so `euclideousStripChipTop`'s own formula
    /// needs no change — only this one constant moved (was 18, giving (8−r)×18÷7 = flush with the 27pt track).
    static let chipTravel: CGFloat = 14
    static let playheadFillAlpha = 0.14, playheadEdgeAlpha = 0.85, playheadEdgeW: CGFloat = 2
    /// §3.2: the lane bar is 2 tall, inset 3, its bottom 2 above the key's; below 100% CHANCE it is a 1 pt ring 3 tall.
    /// (KEY ROW's own geometry — unrelated to, and deliberately not reused by, the readability ferry's floor bar below.)
    static let barH: CGFloat = 2, barInset: CGFloat = 3, barBottom: CGFloat = 2, ringH: CGFloat = 3
    static let mutedAlpha = 0.42
    /// The distance a playhead slides past the last column before the next pass starts it on the first: one column plus the 2 pt gap inside a group (the strip clips it to the step area).
    static let slideGap: CGFloat = 2
    /// LANE STRIP readability ferry §1.1: a hit (or gap) column's lane-coloured fill/border.
    static let hitFillAlpha = 0.24, hitBorderAlpha = 0.70, hitBorderW: CGFloat = 1.5
    /// §1.1/§6.2: the floor bar — lane100 (opaque), 2 tall, inset 2 each side (full width under 6 pt wide),
    /// its top 24 down from the column's own top (1 pt above the track's 27pt bottom edge).
    static let floorBarH: CGFloat = 2, floorBarInset: CGFloat = 2, floorBarMinWidth: CGFloat = 6
    static let floorBarTop: CGFloat = 24, floorBarRadius: CGFloat = 1
    /// RESTART TILES ferry (2026-10-22) §4: a rhythm rest is present, never blank, and never a dot — `euclideousStripRestLook` below.
    /// CLARITY PASS (2026-10-23) §1: the columns are evenly spaced at today's within-group gap (no group gaps); beats are told apart by shading alternate groups. A rhythm rest is a SOLID fill (never dashed) —
    /// #41454F in group A, #30333A in group B; a hit is the lane colour at 42 % (A) / 30 % (B); a gap (a hit on a riff rest) is the rest fill plus a 1 pt inner ring in the lane colour at 45 %.
    /// (The readability pass's `hitFillAlpha`/`hitBorderAlpha`/`hitBorderW` above are no longer drawn — hide, don't delete.)
    static let columnGap: CGFloat = 2
    static let hitAlphaA = 0.42, hitAlphaB = 0.30
    static let restHexA: UInt32 = 0x41454F, restHexB: UInt32 = 0x30333A
    static let gapRingAlpha = 0.45, gapRingW: CGFloat = 1
}
/// RESTART TILES ferry §4.1 (restoring the LANE STRIP ferry's §1.1 after the readability ferry's dot): a rhythm rest column is #1A1C21 with a 1 pt dashed #3A3E47 INNER border (3 on, 2 off) at the column's full size. That is the
/// whole look — there is no other mark, so there is nothing for a dot to be. Holds for every lane, every tab and every OFFSET: a column is a rest when no hit's start falls in it (polish §3.1).
struct EuclideousStripRestLook: Equatable {
    var fillHex: UInt32 = 0x1A1C21
    var borderHex: UInt32 = 0x3A3E47
    var borderWidth: CGFloat = 1
    var dash: [CGFloat] = [3, 2]
}
let euclideousStripRestLook = EuclideousStripRestLook()

/// LANE STRIP readability ferry §2.1/§6.1 (was riff/notes strip 7.2): a chip's top from its rank, in
/// its column's own y: (8 − r) × `chipTravel` ÷ 7.
func euclideousStripChipTop(rank: Int) -> CGFloat { CGFloat(8 - max(1, min(8, rank))) * EuclideousStripMetrics.chipTravel / 7 }

/// LANE STRIP readability ferry §6.2: a hit column's floor bar — lane-coloured, full column width when
/// narrower than `floorBarMinWidth`, inset `floorBarInset` each side otherwise.
func euclideousStripFloorBarFrame(column: CGRect) -> CGRect {
    typealias M = EuclideousStripMetrics
    let inset = column.width < M.floorBarMinWidth ? 0 : M.floorBarInset
    return CGRect(x: column.minX + inset, y: column.minY + M.floorBarTop, width: max(0, column.width - 2 * inset), height: M.floorBarH)
}

/// 7.1: one step's frames in the strip's own coordinates: the track cell (y 0, 27 tall) and the key (y 30, 14 tall), both at the step's column x and width.
struct EuclideousStripFrame: Equatable { var column: CGRect; var key: CGRect }
func euclideousStripLayout(xs: [CGFloat], columnW: CGFloat) -> [EuclideousStripFrame] {
    typealias M = EuclideousStripMetrics
    return xs.map { x in
        EuclideousStripFrame(column: CGRect(x: x, y: 0, width: columnW, height: M.trackH),
                             key: CGRect(x: x, y: M.trackH + M.rowGap, width: columnW, height: M.keyRowH))
    }
}
/// A chip's frame inside its column: inset 2 from each side, 9 tall, its top set by the rank.
func euclideousStripChipFrame(column: CGRect, rank: Int) -> CGRect {
    typealias M = EuclideousStripMetrics
    return CGRect(x: column.minX + M.chipInset, y: column.minY + euclideousStripChipTop(rank: rank), width: max(0, column.width - 2 * M.chipInset), height: M.chipH)
}
func euclideousStripShowsChipLabel(columnWidth w: CGFloat) -> Bool { w >= EuclideousStripMetrics.chipLabelFloor }
func euclideousStripShowsKeyLabel(keyWidth w: CGFloat) -> Bool { w >= EuclideousStripMetrics.keyLabelFloor }

/// 5.1: a lane the LANES grid has muted draws its whole strip at 42% and makes no strikes.
func euclideousStripMuteLook(muted: Bool) -> (opacity: Double, strikes: Bool) { (muted ? EuclideousStripMetrics.mutedAlpha : 1, !muted) }

// ── the per-hit plan (7.3) ───────────────────────────────────────────────────────────────────────────────────────────────

enum EuclideousStripColumnKind: Equatable {
    case rhythmRest   // the rhythm has no hit here: a dashed column (`euclideousStripRestLook`), present, never blank
    case hit          // the rhythm hits: a lane-coloured column with a floor bar (with a chip when the hit reads a riff note)
    case gap          // a hit on a riff REST under SKIP / TIE (or a REPEAT that finds no note): draws exactly like `.hit`, just with no chip
}
/// LANE STRIP readability ferry §6.3: whether a step's column draws lane-coloured (hit AND gap — REPEAT
/// is encoded as `EuclideousStripChip.hollow`, not a fourth kind, so it's already covered here) vs a
/// quiet rhythm rest. The one shared rule drawing and tests both call, so they can't disagree.
func euclideousStripDrawsAsHit(_ kind: EuclideousStripColumnKind) -> Bool { kind != .rhythmRest }

// ── CLARITY PASS (2026-10-23) §1.3: what a column is filled with ──────────────────────────────────────────────────────────

/// Beat groups alternate A, B, A, B from step 1 (§1.2). Display only: a group's size never changes timing.
enum EuclideousStepGroupTone: Equatable { case a, b }
/// §5.2: a step's group (A or B) from its 0-based index and the group size (`euclidStepGroupSize(forRate:)` — 3 under a triplet, else 4). A last group shorter than its size is simply short.
func euclideousStepGroupTone(step: Int, groupSize: Int) -> EuclideousStepGroupTone {
    (max(0, step) / max(1, groupSize)) % 2 == 0 ? .a : .b
}
enum EuclideousStripColumnFill: Equatable {
    case lane(alpha: Double)   // the lane colour at this opacity over the card ground
    case solid(hex: UInt32)
}
/// One column's whole look: its fill, the inner ring (alpha 0 = none), and whether the lane-coloured floor bar sits under it. Rest: solid, no ring, no bar. Hit: lane fill + the floor bar. Gap: the rest fill + a ring, no bar.
struct EuclideousStripColumnLook: Equatable {
    var fill: EuclideousStripColumnFill
    var ringAlpha: Double
    var ringWidth: CGFloat
    var floorBar: Bool
}
func euclideousStripColumnLook(kind: EuclideousStripColumnKind, tone: EuclideousStepGroupTone) -> EuclideousStripColumnLook {
    typealias M = EuclideousStripMetrics
    let rest = EuclideousStripColumnFill.solid(hex: tone == .a ? M.restHexA : M.restHexB)
    switch kind {
    case .rhythmRest: return EuclideousStripColumnLook(fill: rest, ringAlpha: 0, ringWidth: 0, floorBar: false)
    case .hit:        return EuclideousStripColumnLook(fill: .lane(alpha: tone == .a ? M.hitAlphaA : M.hitAlphaB), ringAlpha: 0, ringWidth: 0, floorBar: true)
    case .gap:        return EuclideousStripColumnLook(fill: rest, ringAlpha: M.gapRingAlpha, ringWidth: M.gapRingW, floorBar: false)
    }
}
/// `rank` 1…8 is the WRITTEN rank the arrow's row rule uses (INV and TRANS never touch it); `column` is the riff column (1-based) the footer shows; `hollow` = a REPEAT hit (the repeated note's
/// height, a dashed lane outline); `grey` = the riff is off and only one of PLAYS / RESTS is on (the chips show which hits the riff's columns decide).
struct EuclideousStripChip: Equatable { var rank: Int; var column: Int; var hollow: Bool; var grey: Bool }
/// `plays` = the notes will play on this hit; `chanceRing` = CHANCE below 100 (it may skip the hit); `label` = what the way plays here, nil when there is nothing to name; `picked` = the pitches the way picks.
struct EuclideousStripKey: Equatable { var plays: Bool; var chanceRing: Bool; var label: String?; var picked: [Int] }
struct EuclideousStripHit: Equatable {
    var kind: EuclideousStripColumnKind = .rhythmRest
    var chip: EuclideousStripChip? = nil
    var key: EuclideousStripKey? = nil
    var column: Int? = nil   // the footer's riff column for this hit (1-based), nil when none is read
    var tick: Int = -1       // the hit's lap-local tick (its place in the pass), -1 for a rest
}
/// What the key row needs to know about the lane's notes layer: the layer on (`euclideousNotesLayerIsOn`), WHEN, CHANCE, the way, the play list and the lane index (CHANCE's roll is seeded with it).
struct EuclideousStripNotes {
    var layerOn: Bool
    var when: UInt8
    var chance: Int
    var way: EuclidNotesPlayAs
    var list: EuclideousNotesList
    var lane: Int
}
/// The notes walk a lane config describes — the same fields the Router builds `EuclideousNotesWalk` from.
func euclideousNotesWalk(from c: EuclideousWalkLaneConfig) -> EuclideousNotesWalk {
    EuclideousNotesWalk(n: c.n, dir: c.dir, cycleLen: euclidCycleLen(c.dir, n: c.n), sub: c.sub, chains: c.chains, legacySpanBeats: c.spanBeats, advanceStep: c.advanceStep,
                        riffDir: c.riffDir, stride: c.stride, length: c.length, rotate: c.rotate, seed: c.seed, every: c.every)
}
/// REPEAT's repeated rank at the hit on absolute `tick`: the WRITTEN rank of the nearest earlier hit's column that is not a rest (`euclideousRiffRepeatLookback`, the Router's own call), nil
/// when there is none (the hit then plays as SKIP).
func euclideousStripRepeatRank(cfg c: EuclideousWalkLaneConfig, ranks: [Int], tick: Int64) -> Int? {
    euclideousRiffRepeatLookback(buf: c.buf, n: c.n, dir: c.dir, cycleLen: euclidCycleLen(c.dir, n: c.n), sub: c.sub, tick: tick, chains: c.chains, legacySpanBeats: c.spanBeats,
                                 advanceStep: c.advanceStep, riffDir: c.riffDir, stride: c.stride, length: c.length, rotate: c.rotate, seed: c.seed, every: c.every,
                                 thisBeat: Double(tick) * c.sub, rankAt: { col, _ in col >= 0 && col < ranks.count ? ranks[col] : 0 })?.rank
}

/// 7.3: for every buffer step, what the strip draws — from the footers' own states for the pass they show.
///   · `pattern[i]` is the rhythm's hit at step i as the strip draws it; `hitSteps` and `states` are the footers' (`euclideousLapHitSteps`, `euclideousFooterStates`).
///   · `riffPlays` = the riff layer is on and not shadowed; `grey` = `euclideousNotesGreyFooters`; `onRest` the lane's ON REST.
///   · `cfg` + `lapStartTick` (from `euclideousFooterPass`) place each hit on the tick axis, which REPEAT's lookback and the notes' count k need; without them REPEAT reads as a gap and k as 0.
///   · `notes` nil = the notes layer is off / ignored: every key is unlit.
///   · `name` names a pitch the way the riff grid does; `keyLabels` false skips the label work (k is not free) when the keys are too narrow to show one.
func euclideousStripHits(pattern: [Bool], hitSteps: [EuclidHitStep], states: [EuclidFooterState], ranks: [Int], riffPlays: Bool, grey: Bool, onRest: EuclidRiffOnRest,
                         cfg: EuclideousWalkLaneConfig?, lapStartTick: Int64?, notes: EuclideousStripNotes?, keyLabels: Bool = true, name: (Int) -> String) -> [EuclideousStripHit] {
    let n = pattern.count
    var out = [EuclideousStripHit](repeating: EuclideousStripHit(), count: n)
    var tickAt = [Int](repeating: -1, count: n)
    for hs in hitSteps where hs.bufIdx >= 0 && hs.bufIdx < n { tickAt[hs.bufIdx] = hs.tick }   // PING-PONG writes a step twice; the later leg wins, as in the footers
    func writtenRank(_ column: Int) -> Int { column >= 1 && column <= ranks.count ? max(0, min(8, ranks[column - 1])) : 0 }
    let nw = cfg.map(euclideousNotesWalk(from:))
    for i in 0..<n where pattern[i] {
        var hit = EuclideousStripHit(kind: .hit, tick: tickAt[i])
        let state: EuclidFooterState = i < states.count ? states[i] : .miss
        let absTick: Int64? = (lapStartTick != nil && tickAt[i] >= 0) ? lapStartTick! + Int64(tickAt[i]) : nil
        switch state {
        case .hit(let col?), .hitTied(let col):
            hit.column = col
            let r = writtenRank(col)
            if r >= 1 {
                if riffPlays { hit.chip = EuclideousStripChip(rank: r, column: col, hollow: false, grey: false) }
                else if grey { hit.chip = EuclideousStripChip(rank: r, column: col, hollow: false, grey: true) }
            }
        case .hitOnRest(let col):
            hit.column = col
            if riffPlays && onRest == .repeatLast {
                // REPEAT strikes the repeated note (not a gap): the arrow's on-rest look — a hollow chip at the repeated rank's height; a riff with nothing to repeat plays as SKIP, so a gap
                var repeated: Int? = nil
                if let cfg, let t = absTick { repeated = euclideousStripRepeatRank(cfg: cfg, ranks: ranks, tick: t) }
                if let r = repeated, r >= 1 { hit.chip = EuclideousStripChip(rank: r, column: col, hollow: true, grey: false) } else { hit.kind = .gap }
            } else if euclideousPulseIsGap(state: state, onRest: onRest, riffOn: riffPlays) {
                hit.kind = .gap
            }
        case .hit(nil), .miss:
            break
        }
        // the key row: a key under every hit, lit when the notes will play there
        if let notes, notes.layerOn {
            let plays = euclideousNotesPips(states: [state], when: notes.when, chance: notes.chance)[0] != 0
            var label: String? = nil
            var picked: [Int] = []
            if plays, notes.list.count > 0 {
                var k = 0
                if euclideousNotesWayUsesCount(notes.way), let cfg, let nw, let t = absTick {
                    let h = euclideousNotesHitOrdinal(buf: cfg.buf, w: nw, tick: t)
                    k = euclideousNotesCountBefore(buf: cfg.buf, w: nw, tick: t, h: h, when: notes.when, chance: notes.chance, lane: notes.lane,
                                                   thisBeat: Double(t) * cfg.sub, rankAt: { col, _ in col >= 0 && col < ranks.count ? ranks[col] : 0 })
                }
                let pick = euclideousNotesWayPick(list: notes.list, way: notes.way, k: k)
                for j in 0..<pick.count { picked.append(notes.list.pitch(pick[j])) }
                if keyLabels { label = euclideousStripKeyLabel(pitches: picked, name: name) }
            }
            hit.key = EuclideousStripKey(plays: plays, chanceRing: plays && notes.chance < 100, label: label, picked: picked)
        } else {
            hit.key = EuclideousStripKey(plays: false, chanceRing: false, label: nil, picked: [])
        }
        out[i] = hit
    }
    return out
}
/// 3.2: one note — its name; several — the lowest note's name, "+" and how many more (G3+2); none — no label.
func euclideousStripKeyLabel(pitches: [Int], name: (Int) -> String) -> String? {
    guard let lowest = pitches.min() else { return nil }
    return pitches.count == 1 ? name(lowest) : name(lowest) + "+\(pitches.count - 1)"
}

// ── PING-PONG legs ───────────────────────────────────────────────────────────────────────────────────────────────────────

/// One sweep of the pass: its hits (`bufIdx`, lap-local tick) and what the strip draws for them. A lane whose rhythm direction is FWD or BKW has ONE leg — each step is visited once per pass. PING-PONG visits
/// every step TWICE (up, then back down, the end steps repeating), and the two visits read different riff columns and notes, so it has two legs; one chip and one key per step can only show one of them, and
/// the strip shows the sweep the playhead is on (the first while the lane is stopped). (The footers always showed the later visit only — "the later write wins" — which is wrong for the first sweep.)
struct EuclideousStripLeg: Equatable { var hitSteps: [EuclidHitStep]; var hits: [EuclideousStripHit] }
/// Which leg the lane is on at lap-local tick `raw`: PING-PONG's second sweep starts at tick n; every other lane has the one leg.
func euclideousStripLegIndex(raw: Double, n: Int, legCount: Int) -> Int { legCount > 1 && raw >= Double(n) ? 1 : 0 }
/// The strip's legs for the pass the footers show: `hitSteps` / `prediction` are the footers' (`euclideousLapHitSteps`, `euclideousFooterPass`), split into sweeps for PING-PONG; each leg's states come from
/// `euclideousFooterStates` over its own hits and its chips, gaps and keys from `euclideousStripHits`.
func euclideousStripLegs(pattern: [Bool], hitSteps: [EuclidHitStep], prediction: [Int]?, lapSteps: Int, ranks: [Int], anyLit: Bool, fxTieColumns: UInt8, pingPong: Bool,
                         riffPlays: Bool, grey: Bool, onRest: EuclidRiffOnRest, cfg: EuclideousWalkLaneConfig?, lapStartTick: Int64?, notes: EuclideousStripNotes?, name: (Int) -> String) -> [EuclideousStripLeg] {
    let all = Array(hitSteps.indices)
    let groups: [[Int]] = pingPong ? [all.filter { hitSteps[$0].tick < lapSteps }, all.filter { hitSteps[$0].tick >= lapSteps }] : [all]
    return groups.map { idxs in
        let steps = idxs.map { hitSteps[$0] }
        let pred: [Int]? = prediction.map { p in idxs.compactMap { $0 < p.count ? p[$0] : nil } }
        let states = euclideousFooterStates(hitSteps: steps, lapSteps: lapSteps, prediction: pred, riffRanksResolved: ranks, anyLit: anyLit, fxTieColumns: fxTieColumns)
        let hits = euclideousStripHits(pattern: pattern, hitSteps: steps, states: states, ranks: ranks, riffPlays: riffPlays, grey: grey, onRest: onRest, cfg: cfg, lapStartTick: lapStartTick, notes: notes, name: name)
        return EuclideousStripLeg(hitSteps: steps, hits: hits)
    }
}

// ── the current chip (1.4 / 1.6) ─────────────────────────────────────────────────────────────────────────────────────────

/// The chip that is the lane's CURRENT one: which leg it lives in and the step (buffer index) it sits on.
struct EuclideousStripCurrent: Equatable { var leg: Int; var step: Int }
/// The chip of the hit the lane's riff arrow shows. `landedTick` is the arrow's plan's latest landed hit (an absolute tick, nil before the lane's first hit and for a static seat); `passLapStartTick` the lap the
/// footers show. nil when the landed hit is in another pass, when the arrow sits on a rest (a gap or a REPEAT's hollow chip has no filled chip), and when nothing has landed. `arrowStaysOnTiedNote` = the arrow's
/// TIE stay-put (it sits on the tied note while the rest is the landed hit): the current chip then stays on the nearest EARLIER hit (this leg first, then the leg before) that has a filled chip — the same note
/// `plan.tieStay` names — or nowhere if the tied note belongs to the pass before.
func euclideousStripCurrentStep(cfg c: EuclideousWalkLaneConfig, landedTick: Int64?, passLapStartTick: Int64?, arrowStaysOnTiedNote: Bool, legs: [EuclideousStripLeg]) -> EuclideousStripCurrent? {
    guard let landed = landedTick, let lapStart = passLapStartTick else { return nil }
    let cycleLen = euclidCycleLen(c.dir, n: c.n)
    let info = euclideousLaneChainTick(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: c.sub, tick: landed, chains: c.chains, legacySpanBeats: c.spanBeats, advanceStep: c.advanceStep)
    guard landed - Int64(info.raw) == lapStart else { return nil }
    guard let li = legs.firstIndex(where: { $0.hitSteps.contains { $0.tick == info.raw } }), let j = legs[li].hitSteps.firstIndex(where: { $0.tick == info.raw }) else { return nil }
    func filledChip(_ leg: Int, _ step: Int) -> Bool {
        let hits = legs[leg].hits
        return step >= 0 && step < hits.count && (hits[step].chip.map { !$0.hollow && !$0.grey } ?? false)
    }
    if filledChip(li, legs[li].hitSteps[j].bufIdx) { return EuclideousStripCurrent(leg: li, step: legs[li].hitSteps[j].bufIdx) }
    guard arrowStaysOnTiedNote else { return nil }
    var leg = li, jj = j - 1
    while leg >= 0 {
        while jj >= 0 { if filledChip(leg, legs[leg].hitSteps[jj].bufIdx) { return EuclideousStripCurrent(leg: leg, step: legs[leg].hitSteps[jj].bufIdx) }; jj -= 1 }
        leg -= 1
        if leg >= 0 { jj = legs[leg].hitSteps.count - 1 }
    }
    return nil
}

// ── the playhead (2.x / 7.4) ─────────────────────────────────────────────────────────────────────────────────────────────

struct EuclideousStripPlayhead: Equatable { var x: CGFloat; var width: CGFloat; var movingRight: Bool }
/// 2.2: `raw` is the lane's position in its pass, in ticks (the comet's `cometRaw`: whole numbers are step onsets). At an onset the band covers the column the lane reads then exactly; between onsets its
/// left edge moves linearly to the column it reads next by the fraction of the step gone, so it glides over a group gap. At the end of an FWD or BKW pass the next column does not exist: the band
/// slides off the end it is travelling toward, one column and a gap past it, and the next pass starts it on the first column. PING-PONG repeats its end step (the same column twice), so the band rests
/// there for a step. `xs` are the columns' x in the strip's own coordinates.
func euclideousStripPlayhead(raw: Double, n: Int, dir: EuclidDir, xs: [CGFloat], columnW: CGFloat) -> EuclideousStripPlayhead {
    let n = max(1, min(n, xs.count))
    guard n > 0, !xs.isEmpty else { return EuclideousStripPlayhead(x: 0, width: columnW, movingRight: true) }
    let cl = euclidCycleLen(dir, n: n)
    let wrapped = raw - Double(cl) * (raw / Double(cl)).rounded(.down)
    let k0 = min(cl - 1, max(0, Int(wrapped.rounded(.down))))
    let frac = CGFloat(max(0, min(1, wrapped - Double(k0))))
    let i0 = euclidReadIndex(k0, n: n, dir: dir)
    let movingRight: Bool
    switch dir {
    case .fwd: movingRight = true
    case .bkw: movingRight = false
    case .pingpong: movingRight = k0 < n
    }
    let x0 = xs[i0]
    let x1: CGFloat
    if k0 == cl - 1 && dir != .pingpong {
        x1 = dir == .fwd ? xs[n - 1] + columnW + EuclideousStripMetrics.slideGap : xs[0] - columnW - EuclideousStripMetrics.slideGap
    } else {
        x1 = xs[euclidReadIndex((k0 + 1) % cl, n: n, dir: dir)]
    }
    return EuclideousStripPlayhead(x: x0 + (x1 - x0) * frac, width: columnW, movingRight: movingRight)
}

// ── strikes (4.x) ────────────────────────────────────────────────────────────────────────────────────────────────────────

typealias EuclideousStripTileStrike = (velocity: Int, seconds: Double)
/// Each step's latest strike of each layer, separately: the riff's (its chip) and the notes' (its key). A strike still in the future (its onset after `now`, a reference-date time) is not there yet.
/// A strike's step is its resolved `tile` (`EuclideousPulseFeed.resolveTiles`).
func euclideousStripTileStrikes(_ strikes: [EuclideousPulseStrike], tiles n: Int, now: Double) -> (riff: [EuclideousStripTileStrike?], notes: [EuclideousStripTileStrike?]) {
    var riff = [EuclideousStripTileStrike?](repeating: nil, count: max(0, n))
    var notes = [EuclideousStripTileStrike?](repeating: nil, count: max(0, n))
    for s in strikes where s.onsetAt <= now {
        let t = Int(s.tile)
        guard t >= 0, t < n else { continue }
        if s.riffVel > 0 { riff[t] = (Int(s.riffVel), now - s.onsetAt) }
        if s.notesVel > 0 { notes[t] = (Int(s.notesVel), now - s.onsetAt) }
    }
    return (riff, notes)
}
/// 4.1: a riff strike draws its chip down 2 × k with an outer glow of blur 10 × f in the lane colour at f. Reduce Motion: no dip, the glow stays. PULSE OFF (P = 0): neither.
struct EuclideousStripChipLook: Equatable { var dip: CGFloat; var glowBlur: CGFloat; var glowAlpha: Double }
func euclideousStripChipLook(_ env: EuclideousPulseEnvelopes, scale: Double, reduceMotion: Bool) -> EuclideousStripChipLook {
    let dip = euclideousPulseFilter(.keyDipMove, scale: scale, reduceMotion: reduceMotion) == .off ? 0 : CGFloat(env.k)
    let glow = euclideousPulseFilter(.glow, scale: scale, reduceMotion: reduceMotion) == .off ? 0 : env.f
    return EuclideousStripChipLook(dip: 2 * dip, glowBlur: CGFloat(10 * glow), glowAlpha: glow)
}
/// 4.2: a notes strike gives the hit's key a 1.5 pt lane-colour inner ring at f and an outer glow (blur 10, spread 1) at 45% × f, and turns its label #F2F4F7 while f > 0.25.
struct EuclideousStripKeyLook: Equatable { var ringAlpha: Double; var glowAlpha: Double; var labelLit: Bool }
func euclideousStripKeyLook(_ env: EuclideousPulseEnvelopes, scale: Double, reduceMotion: Bool) -> EuclideousStripKeyLook {
    let f = euclideousPulseFilter(.glow, scale: scale, reduceMotion: reduceMotion) == .off ? 0 : env.f
    return EuclideousStripKeyLook(ringAlpha: f, glowAlpha: 0.45 * f, labelLit: f > 0.25)
}

// ── VoiceOver (6.x) ──────────────────────────────────────────────────────────────────────────────────────────────────────

/// 6.1: the strip is ONE element whose value reads each hit in step order — "step 1, riff column 6, A flat 3", "step 3, rest in the riff" — with ", notes play C 4" (several: "notes play G 3 and 2
/// more") where the notes play; then, while playing, "on step 5"; while muted ", silent at this step". `spokenRank` speaks the note at a written rank; `spokenPitch` speaks a pitch.
/// The hits' sentence (changes with the plan) and the live part (moves with the clock) are separate so the bar adds the second at its own body evaluation.
func euclideousStripHitsPhrase(hits: [EuclideousStripHit], spokenRank: (Int) -> String?, spokenPitch: (Int) -> String) -> String {
    var parts: [String] = []
    for (i, h) in hits.enumerated() where h.kind != .rhythmRest {
        var s = "step \(i + 1)"
        if h.kind == .gap { s += ", rest in the riff" }
        else if let c = h.chip {
            if c.hollow { s += ", rest in the riff, repeats " + (spokenRank(c.rank) ?? "the note before") }
            else {
                s += ", riff column \(c.column)"
                if !c.grey, let n = spokenRank(c.rank) { s += ", " + n }
            }
        } else { s += ", hit" }
        if let k = h.key, k.plays, let lowest = k.picked.min() {
            s += k.picked.count == 1 ? ", notes play " + spokenPitch(lowest) : ", notes play " + spokenPitch(lowest) + " and \(k.picked.count - 1) more"
        }
        parts.append(s)
    }
    return parts.isEmpty ? "no hits" : parts.joined(separator: "; ")
}
func euclideousStripAppendLive(_ hitsPhrase: String, onStep: Int?, muted: Bool) -> String {
    var out = hitsPhrase
    if let on = onStep { out += "; on step \(on)" }
    if muted { out += ", silent at this step" }
    return out
}
func euclideousStripAccessibilityValue(hits: [EuclideousStripHit], spokenRank: (Int) -> String?, spokenPitch: (Int) -> String, onStep: Int?, muted: Bool) -> String {
    euclideousStripAppendLive(euclideousStripHitsPhrase(hits: hits, spokenRank: spokenRank, spokenPitch: spokenPitch), onStep: onStep, muted: muted)
}

// MARK: - STEP-BOX GEOMETRY (moved here unchanged from EuclidLaneUI.swift by the LANE STRIP ferry, 2026-10-21, so the strip's layout is testable on macOS)

/// Shared step-box geometry — the SAME formula `EuclidCometBar`'s own Canvas drawing uses for box width/
/// gap, so the gesture pad's rotate-drag sensitivity (how many points of finger movement = one step) can
/// never compute a DIFFERENT box pitch than what's actually on screen for that lane. One function, two
/// callers, by construction can't drift apart (the RATCHET/DEST class of bug this codebase keeps guarding
/// against — a widget and the thing it controls silently disagreeing about the same quantity).
func euclidBoxGeometry(n: Int, usableWidth: CGFloat) -> (boxW: CGFloat, gap: CGFloat, pitch: CGFloat) {
    // GAP TIERS (2026-10-13, "footers inside the step cells" ferry §2, literal): "3pt gaps, or 2pt above
    // 12 steps" — collapses the old 3-tier 4/3/2 ladder to 2. Shared with the regular BUILD-page EUCLID
    // editor's own comet bar and Euclideous's own MASK-tab step bar (both read this same function) — a
    // disclosed, harmless side effect: their own 2-8-step gap tightens 4pt→3pt, nothing else changes.
    let gap: CGFloat = n <= 12 ? 3 : 2
    // "No minimum cell width" (ferry §2) — the `max(3, ...)` floor below is crash/negative-width
    // protection only, never a touch-target minimum; left as-is.
    let boxW = max(3, (usableWidth - gap * CGFloat(n - 1)) / CGFloat(n))
    return (boxW, gap, boxW + gap)
}

/// STEP GROUPS (2026-10-14 ferry, "Step groups on the lane step row") — a SEPARATE, opt-in geometry from
/// `euclidBoxGeometry` above (not a generalization of it: the gap system is genuinely different — a fixed
/// 2pt WITHIN a group and 7pt BETWEEN groups, regardless of step count, replacing that function's own
/// count-dependent 3pt/2pt tiers for whichever caller opts in). Groups count from step 1, left to right, and
/// are FIXED TO STEP POSITION — never to whatever's currently hit (OFFSET/TILT/hand-edited hits/DIRECTION/
/// INVERT only ever change which box lights up, never where a box's own rect sits; this struct decides
/// position alone). `xs[i]` is each step's own left edge (0-based, excluding any caller-side inset); the
/// formula is the ferry's own literal one, hand-verified against every one of its 7 given check tables
/// before being trusted (e.g. n=7,g=4: w=29.86, x(4)=4×29.86+2×4+5×1=132.44, matching the ferry's own
/// "groups at 0, 132.43" exactly, mod rounding). `ruleX`/`ruleW` describe the LEFTOVER rule (nil when n is
/// an exact multiple of g — "counts that divide evenly get no rule"): the leftover is a group's own trailing
/// SHORT remainder (`n mod g`), or — when n itself is smaller than g — the WHOLE row.
struct EuclidStepGroupGeometry {
    let stepW: CGFloat
    let xs: [CGFloat]
    let ruleX: CGFloat?
    let ruleW: CGFloat?
}
func euclidGroupedBoxGeometry(n: Int, g: Int, usableWidth: CGFloat) -> EuclidStepGroupGeometry {
    guard n > 0 else { return EuclidStepGroupGeometry(stepW: 0, xs: [], ruleX: nil, ruleW: nil) }
    let gSize = max(1, g)
    let groups = max(1, Int((Double(n) / Double(gSize)).rounded(.up)))
    let withinGaps = max(0, n - groups)      // one fewer 2pt gap than steps, per group, summed over all groups
    let betweenGaps = max(0, groups - 1)     // one fewer 7pt gap than the group count
    let totalGaps = CGFloat(withinGaps) * 2 + CGFloat(betweenGaps) * 7
    let w = max(0.5, (usableWidth - totalGaps) / CGFloat(n))
    var xs = [CGFloat](repeating: 0, count: n)
    for i in 0..<n { xs[i] = CGFloat(i) * w + 2 * CGFloat(i) + 5 * CGFloat(i / gSize) }
    let leftover = n % gSize
    guard leftover != 0 else { return EuclidStepGroupGeometry(stepW: w, xs: xs, ruleX: nil, ruleW: nil) }
    let firstLeftoverIdx = n - leftover
    let x0 = xs[firstLeftoverIdx]
    let xEnd = xs[n - 1] + w
    return EuclidStepGroupGeometry(stepW: w, xs: xs, ruleX: x0, ruleW: xEnd - x0)
}
/// The group size for a given RATE — g=3 under triplet feel, g=4 otherwise (ferry §4, literal). Shared by
/// `EuclidCometBar` and the MASK step bar (ferry §5: "uses the same group size as its lane") so the two
/// can't independently land on different group sizes for what's meant to be the same lane.
func euclidStepGroupSize(forRate rate: ArpRate) -> Int {
    euclideousRateDivisionFeel(rate).feel == 2 ? 3 : 4
}
/// The step columns a caller lays out: the Euclideous lane STRIP (CLARITY PASS) gets the even geometry, every other grouped caller the grouped one. One call site per use keeps the draw closures' DEBUG frames small.
func euclidColumnGeometry(strip: Bool, n: Int, g: Int, usableWidth: CGFloat) -> EuclidStepGroupGeometry {
    strip ? euclidEvenBoxGeometry(n: n, g: g, usableWidth: usableWidth) : euclidGroupedBoxGeometry(n: n, g: g, usableWidth: usableWidth)
}
/// CLARITY PASS (2026-10-23) §1.1 — the lane strip's columns: NO group gaps. Every column takes today's within-group spacing (`EuclideousStripMetrics.columnGap`, 2 pt), evenly, and the width the 7 pt
/// between-group gaps used to take is shared across the columns; `usableWidth` (the strip's overall frame) is unchanged. `xs[i] = i·(w + 2)`. The leftover rule's fields (`ruleX`/`ruleW`) are the grouped
/// geometry's, recomputed from these columns: `g` only decides which trailing steps are the short last group (nil when `n` is an exact multiple). The MASK step bar keeps `euclidGroupedBoxGeometry`.
func euclidEvenBoxGeometry(n: Int, g: Int, usableWidth: CGFloat) -> EuclidStepGroupGeometry {
    guard n > 0 else { return EuclidStepGroupGeometry(stepW: 0, xs: [], ruleX: nil, ruleW: nil) }
    let gap = EuclideousStripMetrics.columnGap
    let w = max(0.5, (usableWidth - gap * CGFloat(n - 1)) / CGFloat(n))
    let xs = (0..<n).map { CGFloat($0) * (w + gap) }
    let leftover = n % max(1, g)
    guard leftover != 0 else { return EuclidStepGroupGeometry(stepW: w, xs: xs, ruleX: nil, ruleW: nil) }
    let x0 = xs[n - leftover]
    return EuclidStepGroupGeometry(stepW: w, xs: xs, ruleX: x0, ruleW: xs[n - 1] + w - x0)
}

// MARK: - LANE SOLO (ferry 2026-10-21)
// The step-count box at the end of each lane's comet row became a SOLO button. Tap latches (additive); a hold (≥ 300 ms) solos while held. While any lane is soloed every other lane is SILENT (it keeps walking,
// exactly as a LANES-muted lane does) and GREYED OUT to the page's 42 % everywhere that lane shows. Everything below is pure: the Router and every dim call `euclideousLaneMayStrike` /
// `euclideousLaneIsDimmed` (§5.1 — no second derivation anywhere), the SOLO button calls the press machine and the look. Mask 0 changes nothing, bit for bit.

/// §4.3: what the engine and every display use — the latched mask or the held one (bit i = lane i), four bits.
@inline(__always) func euclideousSoloEffective(latched: UInt8, held: UInt8) -> UInt8 { (latched | held) & 0x0F }
/// A lane is SOLO-SILENCED when the effective mask is not 0 and does not contain it (§6 preamble).
@inline(__always) func euclideousSoloSilences(lane: Int, soloMask: UInt8) -> Bool {
    let m = soloMask & 0x0F
    return m != 0 && lane >= 0 && lane < 4 && (m >> UInt8(lane)) & 1 == 0
}
/// §5.1 — may the lane sound at this moment? Its PLAY state allows it, the LANES sequencer's cell doesn't mute it (`muteAudible` = `euclideousLaneAudible`), and the solo mask is 0 or contains the lane.
/// The Router calls it per hit and in its mute edge sweep; `euclideousLaneIsDimmed` below is the same question for the displays.
@inline(__always) func euclideousLaneMayStrike(lane: Int, soloMask: UInt8, muteAudible: Bool, enabled: Bool) -> Bool {
    enabled && muteAudible && !euclideousSoloSilences(lane: lane, soloMask: soloMask)
}
/// §6: does a view that shows this lane draw it at the OFF-dim 42 %? A lane the LANES grid mutes at this beat OR the solo mask silences — ONE dim, never both multiplied. This is `euclideousLaneMayStrike` with the
/// play state taken out (a stopped lane is shown by its play button, not greyed).
@inline(__always) func euclideousLaneIsDimmed(lane: Int, soloMask: UInt8, muteAudible: Bool) -> Bool {
    !euclideousLaneMayStrike(lane: lane, soloMask: soloMask, muteAudible: muteAudible, enabled: true)
}
/// The dimmed lanes' 0.42, in one place (the page's existing OFF-dim value) and the ease every dim uses (§6: 0.15 s both ways).
enum EuclideousLaneDimStyle {
    static let opacity = 0.42
    static let easeSeconds = 0.15
}
/// The four lanes' dim flags for a given solo mask (LANES-mute is beat-derived and added by the caller where it applies).
func euclideousSoloSilencedLanes(soloMask: UInt8) -> [Bool] { (0..<4).map { euclideousSoloSilences(lane: $0, soloMask: soloMask) } }

// ── tap vs hold (§3) ────────────────────────────────────────────────────────────────────────────────────

/// §3.2 / §3.3: the latched value AFTER a press of `pressSeconds`, from the latched value before. A tap (under 300 ms, the header rings' threshold) toggles it; a hold (300 ms or more) leaves it exactly as it was —
/// a hold never toggles. Touch-down already counted the lane as soloed (§3.1), so the "off + tap → on" case changes nothing the touch hadn't already shown.
func euclideousSoloLatchAfter(latchedBefore: Bool, pressSeconds: Double) -> Bool {
    pressSeconds >= EuclideousRingPress.holdSeconds ? latchedBefore : !latchedBefore
}
/// One SOLO button's touch, as a pure state machine (the view owns the timer and the clock): down at once (the lane counts as soloed from touch-down, §3.1); after 300 ms the HELD look; whatever lifts it — wherever the
/// finger is, a slide-off never cancels (§3.4) — decides tap or hold by DURATION; a touch the system cancels ends as a hold would (it never toggles). Unlike `EuclideousRingPress` there is no drag-cancel.
struct EuclideousSoloPress: Equatable {
    enum Release: Equatable {
        case none
        /// The touch ended; `latchToggles` is true for a tap. The caller clears the held bit and, for a tap, flips the latched one — in ONE update.
        case ended(latchToggles: Bool)
    }
    private(set) var down = false
    private(set) var holdFired = false
    private(set) var downAt: Double = 0
    /// The held look (§2.3): from 300 ms until release.
    var showsHeldLook: Bool { down && holdFired }
    mutating func touchDown(at now: Double) { down = true; holdFired = false; downAt = now }
    /// The 300 ms timer fired while still down.
    mutating func holdTimerFired() { if down { holdFired = true } }
    mutating func touchEnded(at now: Double) -> Release {
        guard down else { return .none }
        let isHold = holdFired || now - downAt >= EuclideousRingPress.holdSeconds
        self = EuclideousSoloPress()
        return .ended(latchToggles: !isHold)
    }
    /// A cancelled touch (the system took it, the view went away): ends as a hold would — held cleared, latch untouched.
    mutating func touchCancelled() -> Release {
        guard down else { return .none }
        self = EuclideousSoloPress()
        return .ended(latchToggles: false)
    }
}

// ── the button's look and words (§2.3, §7.1) ────────────────────────────────────────────────────────────

enum EuclideousSoloButtonLook: Equatable { case off, latched, held }
/// §2.3: OFF (#2A2D34 + 1 pt #3A3E47 inner border, label #AAB0BA), LATCHED (lane100, no border, label #0D0F14), HELD (#DFE3EA, no border, label #0D0F14 — from 300 ms until release, whether or not it was latched).
func euclideousSoloButtonLook(latched: Bool, heldLook: Bool) -> EuclideousSoloButtonLook { heldLook ? .held : (latched ? .latched : .off) }
func euclideousSoloAccessibilityLabel(lane: Int) -> String { "Solo lane \(lane + 1)" }
func euclideousSoloAccessibilityValue(latched: Bool) -> String { latched ? "on" : "off" }
let euclideousSoloAccessibilityHint = "Tap to latch; hold to solo while held"
/// §7.2: what a solo-silenced lane's value / label adds, as the silent-lane look adds ", silent at this step".
let euclideousSilencedBySoloPhrase = "silenced by solo"
func euclideousAppendSilencedBySolo(_ s: String, silenced: Bool) -> String {
    guard silenced else { return s }
    return s.isEmpty ? euclideousSilencedBySoloPhrase : s + ", " + euclideousSilencedBySoloPhrase
}

// MARK: - RESTART FLASH (2026-10-21) — the RHYTHM tab's two restart tiles flash every time their lane restarts
// "Flash in a stylish way every time the rhythm or melody restarts, including its natural restart point when it's on FREE mode" (Paul). Everything here is pure and built from the engine's OWN origins — the
// rhythm / melody chain origins the Router's per-tick core reads (`euclideousRhythmChainOrigin`, `euclideousMelodyChainOrigin`), the per-tick phase (`euclideousLaneChainPhase`) and the walk mirror
// (`euclideousWalkTick`) — so the flash and the sound cannot disagree about when a restart happened (the recurring bug class: one derivation, never two).
//   · RHYTHM, with a chain: each rhythm restart (a chain mark; the first at beat 0). FREE: its natural restart — the start of every pass (lap) of the pattern.
//   · MELODY, with a chain: each melody restart (the first hit of a restarting pass). FREE: its natural restart — the riff walk coming back to its first step (every period × EVERY walk ordinals), which is NOT
//     tied to the pass (a riff of 8 over 5 hits restarts every 8 hits). A riff that is off, or of length 1 (nothing to come back to), has none.

enum EuclideousRestartKind: Equatable { case rhythm, melody }

/// How long a restart's flash lives, and what each part of it does (seconds since the restart).
enum EuclideousRestartFlash {
    static let life = 0.7
    static let glowTau = 0.2          // the wash / rim / glow decay e^(−t ÷ τ)
    static let sweepSeconds = 0.42    // the light band crossing the tile
    static let spinSeconds = 0.5      // the ↻ icon's one full turn
}

/// Seconds since the lane's last restart of `kind` at REAL beat `beat`, or nil when there has been none within `lifeSeconds` (so nothing to draw). `secondsPerBeat` is 60 ÷ tempo.
func euclideousRestartSinceSeconds(_ kind: EuclideousRestartKind, cfg c: EuclideousWalkLaneConfig, beat: Double, secondsPerBeat spb: Double,
                                   lifeSeconds: Double = EuclideousRestartFlash.life) -> Double? {
    guard c.sub > 0, c.n > 0, spb > 0, beat.isFinite else { return nil }
    let mNow = c.swingA == 1 ? beat : musicalOf(beat, stepBeats: c.swingStepBeats, a: c.swingA)
    func realOfMusical(_ m: Double) -> Double { c.swingA == 1 ? m : realOf(m, stepBeats: c.swingStepBeats, a: c.swingA) }
    /// `s` seconds since the real beat of a musical event; nil when it hasn't happened yet or is older than the flash's life.
    func since(musicalEvent m: Double) -> Double? {
        let s = (beat - realOfMusical(m)) * spb
        return s >= -1e-9 && s <= lifeSeconds + 1e-9 ? max(0, s) : nil
    }
    let lifeTicks = Int64((lifeSeconds / spb / c.sub).rounded(.up)) + 2
    let k0 = Int64((mNow / c.sub).rounded(.down))
    let cycleLen = euclidCycleLen(c.dir, n: c.n)
    switch kind {
    case .rhythm:
        if !c.chains.rhythm.isFree {
            return since(musicalEvent: euclideousRhythmChainOrigin(beat: mNow, barBeats: c.chains.barBeats, chain: c.chains.rhythm))
        }
        var k = k0
        while k >= k0 - lifeTicks {
            if euclideousLaneChainPhase(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: c.sub, tick: k, chains: c.chains, legacySpanBeats: c.spanBeats).raw == 0 {
                return since(musicalEvent: Double(k) * c.sub)
            }
            k -= 1
        }
        return nil
    case .melody:
        if !c.chains.melody.isFree {
            return since(musicalEvent: euclideousMelodyChainOrigin(beat: mNow, lapBeats: c.chains.lapBeats, barBeats: c.chains.barBeats,
                                                                    rhythmChain: c.chains.rhythm, melodyChain: c.chains.melody))
        }
        guard c.riffOn, c.playsRiff else { return nil }
        let period = euclideousFXWalkPeriod(dir: c.riffDir, length: c.length, stride: c.stride)
        guard period > 1 else { return nil }
        let cyc = Int64(period) * Int64(max(1, c.every))
        var k = k0
        while k >= k0 - lifeTicks {
            let w = euclideousWalkTick(c, tick: k)
            // ADV HIT counts hits: the walk is back at its first step on the hit whose ordinal is a whole number of cycles. ADV STEP counts ticks: on the tick whose ordinal is.
            if (c.advanceStep || w.isHit), w.advOrd >= 0, w.advOrd % cyc == 0 { return since(musicalEvent: Double(k) * c.sub) }
            k -= 1
        }
        return nil
    }
}

/// What one restart's flash looks like `seconds` after it, as plain numbers the painter draws (all 0…1 unless noted). `scale` is the page's PULSE level (0 OFF · 0.6 SUBTLE · 1 FULL); nil when off or over.
/// Reduce Motion keeps the glow and drops the two moving parts (the sweep and the spin), as the other pulse effects do.
struct EuclideousRestartFlashLook: Equatable {
    var wash: Double      // the lane colour lifting the tile
    var rim: Double       // the white rim
    var glow: Double      // the outer glow's strength
    var sweep: Double?    // the light band's position across the tile, 0 (left) … 1 (right); nil once it has crossed
    var sweepAlpha: Double
    var spinDegrees: Double   // the ↻ icon's rotation, 0 … 360
    var hot: Double       // how white the icon reads
}
func euclideousRestartFlashLook(since seconds: Double, scale p: Double, reduceMotion: Bool) -> EuclideousRestartFlashLook? {
    typealias F = EuclideousRestartFlash
    guard p > 0, seconds >= 0, seconds <= F.life else { return nil }
    let decay = exp(-seconds / F.glowTau) * p
    guard decay >= 0.01 else { return nil }
    func easeOut(_ x: Double) -> Double { let t = max(0, min(1, x)); return 1 - pow(1 - t, 3) }
    let sweeping = !reduceMotion && seconds < F.sweepSeconds
    return EuclideousRestartFlashLook(wash: decay, rim: decay, glow: decay,
                                      sweep: sweeping ? easeOut(seconds / F.sweepSeconds) : nil,
                                      sweepAlpha: sweeping ? p * (1 - seconds / F.sweepSeconds) : 0,
                                      spinDegrees: reduceMotion ? 0 : 360 * easeOut(seconds / F.spinSeconds),
                                      hot: decay)
}

// MARK: - RESTART TILES (RHYTHM POLISH ferry, 2026-10-22, §6; the MELODY track rebuilt by the RESTART TILES ferry, 2026-10-22)

/// §6.3 / §6.4 — where one restart tile stands at a beat: how far its fill has swept toward the next restart (`progress`), and the track under its text. ONE pure function (`restartTileState`) builds it for both tiles, the editor's
/// strips and the tests; it is the engine's own: the rhythm origin / next rhythm restart / pass start and index, the melody origin and its next restart, the lane's real hit schedule (`euclideousChainHitsBefore`) and the
/// riff walk itself (`euclideousRiffColumn`'s own pieces, the per-tick core's `advOrd`). Fixed-size and allocation-free: the first 16 cells are two bits each in `cellBits`.
/// RHYTHM: one cell per step slot of the lap; more than 16 ⇒ one continuous bar (`continuous`) from the fractions below. MELODY: one cell per riff NOTE (the riff's LEN, at most 8), in the order the walk first visits them.
struct EuclideousRestartTileState: Equatable {
    static let cellCap = 16
    var kind: EuclideousRestartKind
    var isFree: Bool = true
    var progress: Double? = nil           // the sweep's fraction of the tile (nil: FREE, or the lane isn't running)
    var count: Int = 0                    // step slots (RHYTHM) / riff notes (MELODY) in the track
    var cellBits: UInt32 = 0              // 2 bits per cell, cells 0…15: 0 unlit · 1 lit · 2 ghost (a slot / note this pass won't reach)
    var continuous: Bool { count > EuclideousRestartTileState.cellCap }
    var litFraction: Double = 0           // continuous form: how much of the bar is lit
    var ghostFromFraction: Double? = nil  // continuous RHYTHM: the dashed tail starts here
    var restartsIn: Int? = nil            // whole bars (RHYTHM) / passes (MELODY) until the next restart, rounded up; nil when FREE or not running
    /// MELODY: the riff column → cell map (4 bits per column 0…7, 0xF = no cell) that a strike's column is looked up in, and how many of the cells the walk reaches this cycle before the next melody restart (all of them when FREE).
    var columnCells: UInt32 = 0xFFFF_FFFF
    var reachable: Int = 0
    func cell(_ i: Int) -> UInt8 { i >= 0 && i < 16 ? UInt8((cellBits >> UInt32(2 * i)) & 3) : 0 }
    /// The cell a strike on riff column `c` belongs to, nil when the track has none for it.
    func cell(forColumn c: Int) -> Int? {
        guard c >= 0, c < 8 else { return nil }
        let v = Int((columnCells >> UInt32(4 * c)) & 0xF)
        return v == 0xF ? nil : v
    }
    var litCount: Int { (0..<min(count, 16)).filter { cell($0) == 1 }.count }
    var ghostCount: Int { (0..<min(count, 16)).filter { cell($0) == 2 }.count }
    /// §6.7 — the VoiceOver value while the lane runs: "next restart in 3 bars" / "in 2 passes", or "this bar" / "this pass" when it falls at the end of the current one. Empty when FREE or stopped.
    var restartsInText: String {
        guard let n = restartsIn else { return "" }
        let unit = kind == .rhythm ? "bar" : "pass"
        return n <= 1 ? "next restart this \(unit)" : "next restart in \(n) \(unit == "bar" ? "bars" : "passes")"
    }
    /// RESTART TILES §3.5 — what the editor's strip adds for MELODY: "5 of 8 notes this cycle" (the notes the walk reaches before the next melody restart). Empty for RHYTHM.
    var notesThisCycleText: String { kind == .melody && count > 0 ? "\(reachable) of \(count) notes this cycle" : "" }
    mutating func setCell(_ i: Int, _ v: UInt32) { guard i >= 0, i < 16 else { return }; cellBits = (cellBits & ~(UInt32(3) << UInt32(2 * i))) | (v << UInt32(2 * i)) }
}
/// RESTART TILES §2 — what a restart tile draws, back to front. ONE list: the page builds the tile by walking it, so the order cannot drift from what the tests pin (the sweep and its leading edge never draw over the
/// name, chain or unit). The tile's text sits on no backing, so nothing hides the sweep or track behind it.
enum EuclideousRestartTileLayer: Hashable { case base, sweep, track, text }
let euclideousRestartTileLayerOrder: [EuclideousRestartTileLayer] = [.base, .sweep, .track, .text]

/// The beat of the next MELODY restart strictly after `beat` — the start of the next pass that begins one of the chain's links; nil when FREE.
func euclideousNextMelodyRestart(after beat: Double, lapBeats: Double, barBeats: Double, rhythmChain: EuclideousRestartChain, melodyChain: EuclideousRestartChain) -> Double? {
    guard !melodyChain.isFree else { return nil }
    let P = Int64(melodyChain.total)
    guard P > 0, lapBeats > 0 else { return nil }
    let q = euclideousPassIndex(beat: beat, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythmChain)
    let r = ((q % P) + P) % P
    var nextOffset = P
    var i = 0
    while i < melodyChain.count {
        let p = Int64(melodyChain.runningTotal(i))
        if p > r { nextOffset = p; break }
        i += 1
    }
    return euclideousPassStart(q - r + nextOffset, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythmChain)
}

/// RESTART TILES §1.2 / §1.3 — the riff's walk cycle as the MELODY tile's cells: cell i is the i-th DISTINCT riff column the walk visits from the start of a cycle (FWD LEN → 1 order, REV the other way, PEND / PING outward
/// then back — a revisit adds no cell). A cycle is `period` walk steps (`euclideousFXWalkPeriod`: D ÷ gcd(D, STRIDE), D = LEN · 2·LEN−2 · 2·LEN) and ends where the walk returns to its start. The track always has LEN cells: columns
/// the stride never visits follow the visited ones in window order (they are never reached). RAND / DRUNK can't reach the Euclideous row (`euclideousRiffDirResolved` coerces them to FWD) but are handled: column order, `unpredictable`.
/// Fixed-size: 4 bits per column / cell / walk step.
struct EuclideousRiffCycleOrder: Equatable {
    var length = 1, period = 1, visited = 0
    var unpredictable = false
    var columnCells: UInt32 = 0xFFFF_FFFF     // column 0…7 → its cell (0xF = none)
    var cellColumns: UInt32 = 0               // cell 0…7 → its column
    var distinctBits: UInt64 = 0              // walk step 0…15 → how many distinct cells the walk has reached through that step (1…8)
    func column(ofCell i: Int) -> Int { i >= 0 && i < 8 ? Int((cellColumns >> UInt32(4 * i)) & 0xF) : 0 }
    func cell(ofColumn c: Int) -> Int? { guard c >= 0, c < 8 else { return nil }; let v = Int((columnCells >> UInt32(4 * c)) & 0xF); return v == 0xF ? nil : v }
    func distinctThrough(step w: Int) -> Int { w < 0 ? 0 : Int((distinctBits >> UInt64(4 * min(15, w))) & 0xF) }
}
func euclideousRiffCycleOrder(dir: RiffDir, length: Int, stride: Int, shift: Int) -> EuclideousRiffCycleOrder {
    var o = EuclideousRiffCycleOrder()
    let L = max(1, min(8, length)), st = max(1, stride)
    o.length = L
    var count = 0
    func assign(_ col: Int) { o.columnCells = (o.columnCells & ~(UInt32(0xF) << UInt32(4 * col))) | (UInt32(count) << UInt32(4 * col)); o.cellColumns |= UInt32(col) << UInt32(4 * count); count += 1 }
    func assigned(_ col: Int) -> Bool { (o.columnCells >> UInt32(4 * col)) & 0xF != 0xF }
    if dir == .random || dir == .drunk {
        o.unpredictable = true; o.period = L
        for i in 0..<L { assign(riffRotateStep(i, by: shift, steps: 8)); o.distinctBits |= UInt64(count) << UInt64(4 * i) }
        o.visited = L
        return o
    }
    let P = max(1, min(16, euclideousFXWalkPeriod(dir: dir, length: L, stride: st)))
    o.period = P
    for w in 0..<P {
        let col = riffRotateStep(riffStepAt(dir, raw: w * st, steps: L, seed: 0), by: shift, steps: 8)
        if !assigned(col) { assign(col) }
        o.distinctBits |= UInt64(count) << UInt64(4 * w)
    }
    o.visited = count
    for i in 0..<L { let col = riffRotateStep(i, by: shift, steps: 8); if !assigned(col) { assign(col) } }   // the stride never reaches these
    return o
}

/// `beat` is the engine's MUSICAL beat. `running` false (stopped transport, or the lane isn't playing): the track keeps its structure at `beat` with nothing lit and no sweep.
func restartTileState(_ kind: EuclideousRestartKind, cfg c: EuclideousWalkLaneConfig, beat: Double, running: Bool) -> EuclideousRestartTileState {
    var st = EuclideousRestartTileState(kind: kind)
    let eps = 1e-9
    let sub = c.sub
    guard sub > 0, c.n > 0 else { return st }
    let cycleLen = euclidCycleLen(c.dir, n: c.n)
    let lap = Double(cycleLen) * sub
    let barBeats = c.chains.barBeats
    let rhythm = c.chains.rhythm
    switch kind {
    case .rhythm:
        st.isFree = rhythm.isFree
        let pass = euclideousPassIndex(beat: beat, lapBeats: lap, barBeats: barBeats, rhythmChain: rhythm)
        let passStart = euclideousPassStart(pass, lapBeats: lap, barBeats: barBeats, rhythmChain: rhythm)
        let next: Double? = rhythm.isFree ? nil : euclideousNextRhythmRestart(after: beat, barBeats: barBeats, chain: rhythm)
        let cur = max(0, min(cycleLen - 1, Int(((beat - passStart) / sub + eps).rounded(.down))))
        st.count = cycleLen
        for i in 0..<min(cycleLen, EuclideousRestartTileState.cellCap) {
            if running && i <= cur { st.setCell(i, 1) }
            else if let nx = next, passStart + Double(i) * sub >= nx - eps { st.setCell(i, 2) }   // a slot the pass won't reach before the next rhythm restart
        }
        if st.continuous {
            st.litFraction = running ? max(0, min(1, (beat - passStart) / lap)) : 0
            if let nx = next { let f = (nx - passStart) / lap; if f < 1 - eps { st.ghostFromFraction = max(0, f) } }
        }
        if let nx = next, running {
            let origin = euclideousRhythmChainOrigin(beat: beat, barBeats: barBeats, chain: rhythm)
            st.progress = nx > origin ? max(0, min(1, (beat - origin) / (nx - origin))) : 0
            st.restartsIn = max(1, Int(((nx - beat) / barBeats - eps).rounded(.up)))
        }
    case .melody:
        let chain = c.chains.melody
        st.isFree = chain.isFree
        let L = max(1, min(8, c.length))
        let order = euclideousRiffCycleOrder(dir: c.riffDir, length: L, stride: c.stride, shift: c.rotate)
        let every = max(1, c.every)
        let cycleUnits = Int64(max(1, order.period * every))   // one full walk cycle, in hits (ADV HIT) or steps (ADV STEP)
        st.count = L
        st.columnCells = order.columnCells
        var cycleHits = 0
        for s in 0..<cycleLen where c.buf[euclidReadIndex(s, n: c.n, dir: c.dir)] { cycleHits += 1 }
        func unitsBefore(_ m: Int64) -> Int64 {
            c.advanceStep ? m : euclideousChainHitsBefore(m, rhythm: rhythm, barBeats: barBeats, sub: sub, buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, cycleHits: cycleHits)
        }
        let tickNow = Int64(((beat / sub) + eps).rounded(.down))
        let originBeat = chain.isFree ? 0 : euclideousMelodyChainOrigin(beat: beat, lapBeats: lap, barBeats: barBeats, rhythmChain: rhythm, melodyChain: chain)
        let oT = euclideousOriginTick(originBeat, sub: sub)
        // The walk's ordinal NOW: the riff position the walk has reached — the current tick's under ADV STEP, the latest hit's (since the melody origin) under ADV HIT. None yet ⇒ nothing lit.
        var ordNow: Int64 = -1
        if tickNow >= oT {
            if c.advanceStep {
                ordNow = euclideousLaneChainTick(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: sub, tick: tickNow, chains: c.chains, legacySpanBeats: c.spanBeats, advanceStep: true).advOrd
            } else {
                var t = tickNow, scanned = 0
                while t >= oT && scanned <= cycleLen * 4 + 16 {
                    let info = euclideousLaneChainTick(buf: c.buf, n: c.n, dir: c.dir, cycleLen: cycleLen, sub: sub, tick: t, chains: c.chains, legacySpanBeats: c.spanBeats, advanceStep: false)
                    if info.rawIsHit { ordNow = info.advOrd; break }
                    t -= 1; scanned += 1
                }
            }
        }
        let cycle = ordNow >= 0 ? ordNow / cycleUnits : 0                  // a new cycle (or a melody restart) starts this evaluation with every cell unlit and the first one lit
        let c0 = cycle * cycleUnits
        let wNow = ordNow >= 0 ? Int((ordNow - c0) / Int64(every)) : -1
        let lit = running ? order.distinctThrough(step: min(wNow, order.period - 1)) : 0
        var reachable = order.visited                                       // FREE: everything the walk visits (no ghosts)
        if !chain.isFree, !order.unpredictable, let nextBeat = euclideousNextMelodyRestart(after: beat, lapBeats: lap, barBeats: barBeats, rhythmChain: rhythm, melodyChain: chain) {
            let nT = euclideousOriginTick(nextBeat, sub: sub)
            let units = max(0, unitsBefore(nT) - unitsBefore(oT))           // units from the melody origin to the next melody restart
            let lastOrd = min(c0 + cycleUnits - 1, units - 1)               // the last ordinal this cycle can reach before that restart
            let wMax = lastOrd >= c0 ? Int((lastOrd - c0) / Int64(every)) : -1
            reachable = order.distinctThrough(step: min(wMax, order.period - 1))
            if running {
                st.progress = nextBeat > originBeat ? max(0, min(1, (beat - originBeat) / (nextBeat - originBeat))) : 0
                st.restartsIn = max(1, Int(((nextBeat - beat) / lap - eps).rounded(.up)))
            }
        }
        st.reachable = reachable
        for i in 0..<min(L, EuclideousRestartTileState.cellCap) {
            if i < lit { st.setCell(i, 1) }
            else if !chain.isFree && !order.unpredictable && i >= reachable { st.setCell(i, 2) }   // a note this walk cycle won't reach before the next melody restart
        }
    }
    return st
}

/// RESTART TILES §1.5 — the latest strike on each MELODY cell, in fixed storage (16 slots: no allocation per frame). A strike is an event from the same per-hit stream the strip's strikes use (`EuclideousPulseFeed`), keyed by
/// the cell of its riff column (`cellColumn` — a REPEAT hit's repeated note); TIE continuations, SKIP gaps, FX-tied and muted hits post no event, so they never appear. The look is the strip's key strike's: the shared envelope's
/// flash `f` through the PULSE setting and Reduce Motion (`euclideousPulseFilter(.glow, …)`).
struct EuclideousCellStrikeBank {
    typealias V = (UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8, UInt8)
    typealias A = (Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double, Double)
    private var vel: V = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    private var age: A = (-1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1)   // seconds since the strike; < 0 = none
    init() {}
    /// Keeps the youngest strike per cell.
    mutating func record(cell: Int, velocity: Int, seconds: Double) {
        guard cell >= 0, cell < 16, velocity > 0, seconds >= 0 else { return }
        let a: Double = withUnsafePointer(to: &age) { $0.withMemoryRebound(to: Double.self, capacity: 16) { $0[cell] } }
        guard a < 0 || seconds < a else { return }
        withUnsafeMutablePointer(to: &age) { $0.withMemoryRebound(to: Double.self, capacity: 16) { $0[cell] = seconds } }
        withUnsafeMutablePointer(to: &vel) { $0.withMemoryRebound(to: UInt8.self, capacity: 16) { $0[cell] = UInt8(max(1, min(127, velocity))) } }
    }
    /// How far cell `cell`'s strike has brightened it toward #F2F4F7 (0…1): 0 when it has none, or PULSE is OFF.
    func mix(cell: Int, scale p: Double, reduceMotion: Bool) -> Double {
        guard cell >= 0, cell < 16 else { return 0 }
        let a: Double = withUnsafePointer(to: age) { $0.withMemoryRebound(to: Double.self, capacity: 16) { $0[cell] } }
        guard a >= 0 else { return 0 }
        let v: UInt8 = withUnsafePointer(to: vel) { $0.withMemoryRebound(to: UInt8.self, capacity: 16) { $0[cell] } }
        let env = euclideousPulseEnvelopes(velocity: Int(v), seconds: a, scale: p)
        return euclideousPulseFilter(.glow, scale: p, reduceMotion: reduceMotion) == .off ? 0 : env.f
    }
}
func euclideousRestartCellStrikes(_ strikes: [EuclideousPulseStrike], columnCells: UInt32, now: Double) -> EuclideousCellStrikeBank {
    var bank = EuclideousCellStrikeBank()
    for s in strikes where s.onsetAt <= now && s.riffVel > 0 && s.cellColumn >= 0 && s.cellColumn < 8 {
        let v = Int((columnCells >> UInt32(4 * Int(s.cellColumn))) & 0xF)
        if v != 0xF { bank.record(cell: v, velocity: Int(s.riffVel), seconds: now - s.onsetAt) }
    }
    return bank
}
/// §6.4 — the track's geometry for `count` cells in a box `width` wide: each cell is `(width − 2 × (count − 1)) / count` (sp2 between cells).
func euclideousRestartTileCellWidth(count: Int, width: CGFloat) -> CGFloat {
    guard count > 0 else { return 0 }
    return max(1, (width - 2 * CGFloat(count - 1)) / CGFloat(count))
}

/// The restart tile's label for a tile `width` wide: "RHYTHM RESTART" / "MELODY RESTART" when it fits at 8 pt heavy mono (`EuclideousHeaderMetrics.monoAdvance` × 8 per character, 2 pt either side),
/// else just "RHYTHM" / "MELODY" — never a word cut in the middle (the ↻ beside the value still says "restart").
func euclideousRestartTileLabel(name: String, width: CGFloat) -> String {
    let full = "\(name) RESTART"
    let needed = CGFloat(full.count) * 8 * EuclideousHeaderMetrics.monoAdvance + 4
    return width >= needed ? full : name
}
