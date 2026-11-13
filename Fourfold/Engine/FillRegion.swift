//  FillRegion.swift — FILL ferry (2026-11-13) §2: the pure timing of a per-lane fill.
//
//  Foundation-only, allocation-free (fixed-size values, no heap). The Router reads these; the display
//  mirrors read them too, so the engine and the pictures can never disagree about which step a fill fires.
//
//  Paul's decision (2026-11-13): the fill CONTINUES THE WALK FORWARD at speed m (§2.2/§2.3's formula) — it is
//  NOT a loop of the last-LENGTH window. The §7 raw text's tests 3 and 4 assumed a loop (5,6,7,8,5,6,7,8); per
//  this decision the lane runs on (5,6,7,8,1,2,3,4) and the tests here assert the formula's values.

/// §2.1 — a fill region: the host-beat window [F, E), its length D (host beats) and its speed m, plus the
/// lane's own fill shape (REVERSE/RANKS/SWELL/BREAK). Built per (lane, bar) from the lane and the host bar length.
struct EuclideousFillRegion: Equatable {
    var barIndex: Int = 0        // the 0-based host bar (host bar 1 = bar 0)
    var F: Double = 0            // region start (host beats)
    var E: Double = 0            // region end / the rejoin line (host beats, exclusive)
    var D: Double = 0            // region length = L·B (host beats)
    var m: Double = 1            // speed multiplier
    var reverse = false
    var ranks = 0                // −7…+7 climb
    var swell = 0                // −3…+3 velocity ramp
    var breakOn = false
}

/// §2.3 — reverse honours a fixed per-lane buffer; above it the region plays forward (reported). §2.3 worst case
/// (LENGTH BAR, ×4, a 1/32 lane) is 32 steps × 4 = 128, so 128 is the bound.
let euclideousFillReverseCap = 128

/// §2.1 — the fill region of (0-based) bar `n` for this lane, or nil if the lane does not fill that bar.
/// nil whenever the lane is neutral/unarmed (§1.4/§1.5) ⇒ the Router takes its ordinary ×1 path (byte-identical).
func euclideousFillRegion(line: EuclidLine, bar n: Int, beatsPerBar B: Double) -> EuclideousFillRegion? {
    guard B > 0, line.usesFill, line.fillArmed(bar: n) else { return nil }
    var r = EuclideousFillRegion()
    r.barIndex = n
    r.m = line.fillSpeedMultiplier
    r.D = line.fillLengthFraction * B
    r.E = Double(n + 1) * B
    r.F = r.E - r.D
    r.reverse = line.fillReverseResolved
    r.ranks = line.fillRanksResolved
    r.swell = line.fillSwellResolved
    r.breakOn = line.fillBreakResolved
    return r
}

/// §2.3 — the lane's ×1 elapsed time at F: e(F) = F − o (before F the lane runs at ×1). `o` is the lane's
/// rhythm restart origin in host beats (§2.9: a restart exactly on F has already moved `o`; one strictly inside is deferred).
@inline(__always) func euclideousFillElapsedAtF(_ r: EuclideousFillRegion, origin o: Double) -> Double { r.F - o }

/// §2.3 — the first fired lane step j_0 (the smallest absolute step index whose start e ≥ e(F)).
@inline(__always) func euclideousFillFirstStep(_ r: EuclideousFillRegion, origin o: Double, sub: Double) -> Int64 {
    guard sub > 0 else { return 0 }
    return Int64(((r.F - o) / sub - 1e-9).rounded(.up))
}

/// §2.3 — N, the number of fired steps (steps whose start in lane time lies in [e(F), e(F)+D·m)); may be 0.
func euclideousFillCount(_ r: EuclideousFillRegion, origin o: Double, sub: Double) -> Int {
    guard sub > 0 else { return 0 }
    let eF = r.F - o
    let j0 = Int64((eF / sub - 1e-9).rounded(.up))
    let jEnd = Int64(((eF + r.D * r.m) / sub - 1e-9).rounded(.up))   // first step at or past the region end (exclusive)
    return max(0, Int(jEnd - j0))
}

/// §2.3 — the host beat of time-slot k: t_k = F + (start(j_0+k) − e(F)) / m.
func euclideousFillSlotHostBeat(_ r: EuclideousFillRegion, origin o: Double, sub: Double, slot k: Int) -> Double {
    let eF = r.F - o
    let startJ = Double(euclideousFillFirstStep(r, origin: o, sub: sub) + Int64(k)) * sub
    return r.F + (startJ - eF) / r.m
}

/// §2.3 — is REVERSE in force for this region (reverse set AND within the buffer cap)? Above the cap it falls back to forward.
@inline(__always) func euclideousFillReverseActive(_ r: EuclideousFillRegion, count N: Int) -> Bool { r.reverse && N <= euclideousFillReverseCap }

/// §2.3 — the lane STEP index that plays at time-slot k: forward j_0+k; reverse j_0+(N−1−k). The step's own
/// content (hit/rest, riff ordinal, stack, random draws) is resolved FORWARD at that index (the engine's randomness
/// is position-keyed, so an on-demand reverse read equals a forward buffer read mirrored — §2.11).
func euclideousFillSourceStep(_ r: EuclideousFillRegion, origin o: Double, sub: Double, count N: Int, slot k: Int) -> Int64 {
    let j0 = euclideousFillFirstStep(r, origin: o, sub: sub)
    return j0 + Int64(euclideousFillReverseActive(r, count: N) ? (N - 1 - k) : k)
}

/// §2.5 — the rank climb offset for time-slot k (k = 0…N−1 in TIME order). First slot 0, last R; N=1 ⇒ R.
func euclideousFillRankOffset(ranks R: Int, slot k: Int, count N: Int) -> Int {
    guard N > 1 else { return R }
    return Int((Double(R) * Double(k) / Double(N - 1)).rounded())
}

/// §2.6 — the velocity factor for time-slot k. S>0 rises to 1 at the downbeat; S<0 falls from 1; S=0 ⇒ 1.
func euclideousFillSwellFactor(swell S: Int, slot k: Int, count N: Int) -> Double {
    guard S != 0 else { return 1 }
    let d = Double(abs(S)) / 3
    let u = N > 1 ? Double(k) / Double(N - 1) : 1
    return S > 0 ? 1 - 0.65 * d * (1 - u) : 1 - 0.65 * d * u
}

/// §2.7 — does BREAK drop a note-on whose host start is `t`? (t in [E − D/4, E).) Steps still advance and still count.
@inline(__always) func euclideousFillBreakDrops(_ r: EuclideousFillRegion, hostBeat t: Double) -> Bool {
    r.breakOn && t >= r.E - r.D / 4 - 1e-9 && t < r.E
}

/// §2.4 — a fired step's duration in host beats (= the lane step length / m). Gate and ratchet spacing use it, so ×2 halves them.
@inline(__always) func euclideousFillStepHostLength(_ r: EuclideousFillRegion, sub: Double) -> Double { r.m > 0 ? sub / r.m : sub }
