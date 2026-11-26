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
    var lane: Int = 0            // FILL TAB §2.2/§2.7: the lane, for the (lane, bar) SHUFFLE / CHANCE seeds
    var F: Double = 0            // region start (host beats)
    var E: Double = 0            // region end / the rejoin line (host beats, exclusive)
    var D: Double = 0            // region length = L·B (host beats)
    var m: Double = 1            // speed multiplier
    var curve: EuclideousFillCurve = .steady   // FILL TAB §2.1
    var order: EuclideousFillOrder = .fwd      // FILL TAB §2.2 (replaces `reverse`: .fwd/.rev are the old forward/reverse)
    var shape: EuclideousFillShape = .climb    // FILL TAB §2.4
    var hits: EuclideousFillHits = .keep       // FILL TAB §2.3
    var notes: EuclideousFillNotes = .riff     // FILL TAB V2 §2.3 (RIFF = today, byte-identical)
    var ranks = 0                // −7…+7 climb amount R
    var swell = 0                // −3…+3 velocity ramp
    var roll = 0                 // FILL TAB §2.5 0…4
    var breakOn = false
    var land = false             // FILL TAB §2.6

    /// Step-display gate (Paul 2026-11-15): does this region change WHICH steps fire, WHEN, or whether they sound — i.e. the RHYTHM — vs the lane's ordinary ×1 forward walk? Only then should a step indicator (the comet) follow the
    /// fill "as it sounds"; a fill that merely recolours (RANKS) or reshapes velocity (SWELL) leaves the steps exactly where the base walk puts them, so the comet should keep the base step lighting. SPEED ≠ ×1, a non-forward ORDER,
    /// RUSH timing, a HITS change (ALL/FLIP) and BREAK (some steps go silent) all change the rhythm; RANKS / SWELL / ROLL / LAND / LENGTH do not move a step's position in time. (A judgment call on the exact set — flagged for Paul.)
    var changesHits: Bool { m != 1 || order != .fwd || curve == .rush || hits != .keep || breakOn }
}

/// §2.3 — reverse honours a fixed per-lane buffer; above it the region plays forward (reported). §2.3 worst case
/// (LENGTH BAR, ×4, a 1/32 lane) is 32 steps × 4 = 128, so 128 is the bound.
let euclideousFillReverseCap = 128

/// §2 — a lane's fill settings resolved into a self-contained, allocation-free value the Router (via `iterateTicks`)
/// and the display mirrors carry, so the pictures and the sound agree. `region(bar:)` gives the §2.1 region of any bar.
struct EuclideousFillPlan: Equatable {
    var active = false            // = line.usesFill (FILL on, a bar lit, non-neutral)
    var armed: UInt16 = 0         // FILL TAB §1.1: bit n = bar (n mod loop) lit (16 bars)
    var loop = 8                  // FILL TAB §1.1 the loop length (4/8/16)
    var lane = 0
    var m = 1.0                   // SPEED
    var lengthFraction = 0.5      // LENGTH L
    var curve: EuclideousFillCurve = .steady
    var order: EuclideousFillOrder = .fwd
    var shape: EuclideousFillShape = .climb
    var hits: EuclideousFillHits = .keep
    var notes: EuclideousFillNotes = .riff     // FILL TAB V2 §2.3
    var ranks = 0, swell = 0, roll = 0, breakOn = false, land = false, chance = 100
    var originBeat = 0.0          // the lane's rhythm restart origin (host beats)
    var beatsPerBar = 4.0
    var sub = 0.25                // the lane step length (host beats)
    init() {}
    init(line: EuclidLine, lane: Int = 0, originBeat: Double, beatsPerBar: Double, sub: Double) {
        guard line.usesFill else { return }
        active = true; self.lane = lane; loop = line.fillLoopResolved
        if let bars = line.fillBars { for i in 0..<min(16, bars.count) where bars[i] { armed |= (1 << UInt16(i)) } }   // read in place — no allocation on the render thread
        m = line.fillSpeedMultiplier; lengthFraction = line.fillLengthFraction
        curve = line.fillCurveResolved; order = line.fillOrderResolved; shape = line.fillShapeResolved; hits = line.fillHitsResolved; notes = line.fillNotesResolved
        ranks = line.fillRanksResolved; swell = line.fillSwellResolved; roll = line.fillRollResolved; breakOn = line.fillBreakResolved; land = line.fillLandResolved; chance = line.fillChanceResolved
        self.originBeat = originBeat; self.beatsPerBar = beatsPerBar; self.sub = sub
    }
    /// §2.1/§2.7 — the fill region of (0-based) bar `n`, or nil if the lane does not fill it (unarmed, or the CHANCE draw skipped it — a skipped bar plays exactly as no fill, §2.7).
    func region(bar n: Int) -> EuclideousFillRegion? {
        guard active, beatsPerBar > 0, (armed >> UInt16(((n % loop) + loop) % loop)) & 1 != 0 else { return nil }
        guard euclideousFillChancePlays(lane: lane, bar: n, chance: chance) else { return nil }
        var r = EuclideousFillRegion()
        r.barIndex = n; r.lane = lane; r.m = m
        r.D = lengthFraction * beatsPerBar; r.E = Double(n + 1) * beatsPerBar; r.F = r.E - r.D
        r.curve = curve; r.order = order; r.shape = shape; r.hits = hits; r.notes = notes
        r.ranks = ranks; r.swell = swell; r.roll = roll; r.breakOn = breakOn; r.land = land
        return r
    }
}

/// FILL TAB §2.7 — does the (lane, bar) CHANCE draw play the region? 100 % always plays; else a deterministic splitmix draw of (lane, bar) < chance. A pure function of (lane, bar), so a located bar decides the same as playing through.
func euclideousFillChancePlays(lane: Int, bar n: Int, chance: Int) -> Bool {
    guard chance < 100 else { return true }
    let seed = 0x9E3779B97F4A7C15 &* UInt64(bitPattern: Int64(lane &+ 1)) &+ (0xD1B54A32D192ED03 &* UInt64(bitPattern: Int64(n)))   // FILL-CHANCE salt
    return Int(splitmix64Mix(seed) % 100) < max(0, min(100, chance))
}
/// FILL TAB §2.2 — SHUFFLE's permutation of 0…N−1, a Fisher–Yates driven by a splitmix generator seeded from (lane, bar), written into `out` (the caller's fixed buffer — no allocation on the render thread). `out.count` must be ≥ N.
func euclideousFillShuffle(lane: Int, bar n: Int, count N: Int, into out: inout [Int]) {
    for i in 0..<N { out[i] = i }
    guard N > 1 else { return }
    var s = 0xC2B2AE3D27D4EB4F &* UInt64(bitPattern: Int64(lane &+ 1)) &+ (0x165667B19E3779F9 &* UInt64(bitPattern: Int64(n))) &+ 0x27D4EB2F165667C5   // FILL-SHUFFLE salt
    var i = N - 1
    while i > 0 { s = splitmix64Mix(s); let j = Int(s % UInt64(i + 1)); out.swapAt(i, j); i -= 1 }
}

/// §2.1 — the fill region of (0-based) bar `n` for this lane, or nil if the lane does not fill that bar.
/// nil whenever the lane is neutral/unarmed (§1.4/§1.5) ⇒ the Router takes its ordinary ×1 path (byte-identical).
func euclideousFillRegion(line: EuclidLine, bar n: Int, beatsPerBar B: Double, lane: Int = 0) -> EuclideousFillRegion? {
    EuclideousFillPlan(line: line, lane: lane, originBeat: 0, beatsPerBar: B, sub: 0).region(bar: n)
}

/// §2.3 — the lane's ×1 elapsed time at F: e(F) = F − o (before F the lane runs at ×1). `o` is the lane's
/// rhythm restart origin in host beats (§2.9: a restart exactly on F has already moved `o`; one strictly inside is deferred).
@inline(__always) func euclideousFillElapsedAtF(_ r: EuclideousFillRegion, origin o: Double) -> Double { r.F - o }

/// §2.3 — the first fired lane step j_0 (the smallest absolute step index whose start e ≥ e(F)).
@inline(__always) func euclideousFillFirstStep(_ r: EuclideousFillRegion, origin o: Double, sub: Double) -> Int64 {
    guard sub > 0 else { return 0 }
    return Int64(((r.F - o) / sub - 1e-9).rounded(.up))
}

/// §2.1/§2.3 — N, the number of fired steps. STEADY covers D·m of lane time; RUSH covers D·(1+m)/2 (the area under the linearly-rising rate). May be 0.
func euclideousFillCount(_ r: EuclideousFillRegion, origin o: Double, sub: Double) -> Int {
    guard sub > 0 else { return 0 }
    let eF = r.F - o
    let span = r.curve == .rush ? r.D * (1 + r.m) / 2 : r.D * r.m
    let j0 = Int64((eF / sub - 1e-9).rounded(.up))
    let jEnd = Int64(((eF + span) / sub - 1e-9).rounded(.up))   // first step at or past the region end (exclusive)
    return max(0, Int(jEnd - j0))
}

/// §2.1 — RUSH's normalised region position x(y): a step starting y lane-beats after e(F) fires at host beat F + D·x. x = y/D for m=1, else the positive root of (m−1)/2·x² + x − y/D = 0.
@inline(__always) func euclideousFillRushX(_ r: EuclideousFillRegion, yLaneBeats y: Double) -> Double {
    guard r.D > 0 else { return 0 }
    if abs(r.m - 1) < 1e-12 { return y / r.D }
    return (-1 + (1 + 2 * (r.m - 1) * (y / r.D)).squareRoot()) / (r.m - 1)
}

/// §2.1/§2.3 — the host beat of time-slot k. STEADY: t_k = F + (start(j_0+k) − e(F)) / m. RUSH: F + D·x(y).
func euclideousFillSlotHostBeat(_ r: EuclideousFillRegion, origin o: Double, sub: Double, slot k: Int) -> Double {
    let eF = r.F - o
    let startJ = Double(euclideousFillFirstStep(r, origin: o, sub: sub) + Int64(k)) * sub
    if r.curve == .rush { return r.F + r.D * euclideousFillRushX(r, yLaneBeats: startJ - eF) }
    return r.F + (startJ - eF) / r.m
}

/// §2.1 — RUSH's lane-elapsed-since-origin at host beat `b` inside the region [F, E): e(F) + D·(x + (m−1)x²/2), x = (b−F)/D.
/// The EXACT inverse of `euclideousFillSlotHostBeat`'s RUSH branch (y(x(y)) = y), so a render window that STARTS mid-region
/// seeds its first slot at exactly the step the previous window stopped before — no re-fire, no skip (the §3.1 dedup relies on it).
@inline(__always) func euclideousFillRushElapsed(_ r: EuclideousFillRegion, origin o: Double, hostBeat b: Double) -> Double {
    guard r.D > 0 else { return b - o }
    let x = max(0, min(1, (b - r.F) / r.D))
    return (r.F - o) + r.D * (x + (r.m - 1) * x * x / 2)
}

/// §2.2 — does this region's ORDER need the time→index remap buffer (ORDER ≠ FWD AND N within the cap)? Above the cap it falls back to FWD.
@inline(__always) func euclideousFillOrderBuffered(_ r: EuclideousFillRegion, count N: Int) -> Bool { r.order != .fwd && N <= euclideousFillReverseCap }

/// §2.2 — the lane STEP index playing at time-slot k, mapped by ORDER: FWD i=k · REV i=N−1−k · BOUNCE i=k<⌈N/2⌉?k:N−1−k · SHUFFLE i=π(k) (from the caller's precomputed permutation; above the cap or no buffer ⇒ FWD). Content is resolved FORWARD at that index (randomness is position-keyed, §2.11).
func euclideousFillSourceStep(_ r: EuclideousFillRegion, origin o: Double, sub: Double, count N: Int, slot k: Int, shuffle: [Int]? = nil) -> Int64 {
    let j0 = euclideousFillFirstStep(r, origin: o, sub: sub)
    guard euclideousFillOrderBuffered(r, count: N), N > 0 else { return j0 + Int64(k) }
    let i: Int
    switch r.order {
    case .fwd:     i = k
    case .rev:     i = N - 1 - k
    case .bounce:  let h = (N + 1) / 2; i = k < h ? k : (N - 1 - k)   // out then back: 0…h−1, then N−1−k
    case .shuffle: i = (shuffle != nil && k < shuffle!.count) ? shuffle![k] : k
    case .stutter: i = 0                                              // FILL TAB V2 §2.1: every slot plays the region's first forward step
    }
    return j0 + Int64(max(0, min(N - 1, i)))
}

/// §2.4 — the RANKS offset for time-slot k (k = 0…N−1 in TIME order), by SHAPE. CLIMB round(R·u) · ARCH round(R·(1−|2u−1|)) · SHIFT R. First/last 0 under CLIMB/ARCH; N=1 ⇒ R.
func euclideousFillRankOffset(ranks R: Int, slot k: Int, count N: Int, shape: EuclideousFillShape = .climb) -> Int {
    guard N > 1 else { return R }
    let u = Double(k) / Double(N - 1)
    switch shape {
    case .climb: return Int((Double(R) * u).rounded())
    case .arch:  return Int((Double(R) * (1 - abs(2 * u - 1))).rounded())
    case .shift: return R
    }
}

/// FILL TAB V2 §2.3 — the NOTES-mode transform for ONE voice of a sounding slot, in RANK space (the resolver's fold
/// wraps; a rank < 1 or an empty pool resolves nil = silent — the engine's own rule, adopted per the spec). `q0` is the
/// voice's resolved rank BEFORE the RANKS offset; `flatRank` the region's latched first-sounding rank for this part
/// (0 = not latched yet ⇒ this voice latches itself). Fixed-size result — no allocation on the render thread.
/// RIFF: q0+off · FLAT: flat+off · PEDAL odd: rank 1 alone, no offset (even as RIFF) · OCT: as RIFF, +12 semitones on
/// odd slots (post-resolve) · CHORD: q, q+2, q+4 (duplicates collapse at the add site).
struct EuclideousFillVoice: Equatable {
    var r0 = 0, r1 = 0, r2 = 0   // the ranks to strike (0 = unused slot)
    var count = 1
    var octUp = false            // OCT's odd-slot +12, applied to each resolved pitch
    var isPedal = false          // PEDAL's odd slot: one note per slot whatever the voice count (the add site gates)
}
extension EuclideousFillNotes {
    /// The render scalar's inverse (0 RIFF · 1 FLAT · 2 PEDAL · 3 OCT · 4 CHORD) — a switch, never an array literal (render thread).
    static func fromScalar(_ s: UInt8) -> EuclideousFillNotes {
        switch s { case 1: return .flat; case 2: return .pedal; case 3: return .oct; case 4: return .chord; default: return .riff }
    }
}
func euclideousFillNotesVoice(mode: EuclideousFillNotes, q0: Int, offset: Int, flatRank: Int, oddSlot: Bool) -> EuclideousFillVoice {
    var v = EuclideousFillVoice()
    switch mode {
    case .riff:  v.r0 = q0 + offset
    case .flat:  v.r0 = (flatRank > 0 ? flatRank : q0) + offset
    case .pedal: if oddSlot { v.r0 = 1; v.isPedal = true } else { v.r0 = q0 + offset }
    case .oct:   v.r0 = q0 + offset; v.octUp = oddSlot
    case .chord: let q = q0 + offset; v.r0 = q; v.r1 = q + 2; v.r2 = q + 4; v.count = 3
    }
    return v
}

/// §2.5 — ROLL's strike count for time-slot k: 1 + round(ROLL·u), u = k/(N−1) (so the roll thickens toward the downbeat). ROLL 0 ⇒ 1 (no roll ⇒ the slot strikes once, byte-identical). Capped at 16 (the echo-tail bound the ratchet mechanism keeps).
@inline(__always) func euclideousFillRollCount(roll R: Int, slot k: Int, count N: Int) -> Int {
    guard R > 0 else { return 1 }
    let u = N > 1 ? Double(k) / Double(N - 1) : 1
    return min(16, 1 + Int((Double(R) * u).rounded()))
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

/// §2.1/§2.4 — a fired step's duration in host beats. STEADY: the lane step length / m (so ×2 halves it). RUSH: sub / (1 + (m−1)·x) at the slot's own x, so a RUSH step shortens as the rate rises. Gate and ratchet spacing use it. STEADY ignores origin/slot ⇒ the old call is byte-identical.
@inline(__always) func euclideousFillStepHostLength(_ r: EuclideousFillRegion, origin o: Double = 0, sub: Double, slot k: Int = 0) -> Double {
    guard r.m > 0 else { return sub }
    guard r.curve == .rush else { return sub / r.m }
    let startJ = Double(euclideousFillFirstStep(r, origin: o, sub: sub) + Int64(k)) * sub
    let speed = 1 + (r.m - 1) * euclideousFillRushX(r, yLaneBeats: startJ - (r.F - o))
    return speed > 0 ? sub / speed : sub
}

// MARK: - STEP DISPLAY part 2 (FILL step flash, Paul 2026-11-25; gated to the playhead 2026-11-26) — what a hit-changing fill does to the box the playhead is sounding NOW
//
// The STEP DISPLAY ferry (2026-11-15) made the lane card's COMET follow a fill ("as it sounds", `euclideousLaneCometChainRaw`'s
// fill branch), gated on `changesHits` so a recolour-only fill keeps the base step lighting. This is the second half of that
// decision for the step CELLS themselves: a step the fill SOUNDS is drawn as a hit (in the lane colour — even a standard rest the
// fill plays), and a standard hit the fill DROPS is drawn as a rest — but ONLY on the box the playhead is sounding RIGHT NOW,
// not held across the region (Paul 2026-11-26: "only while it's sounding, not in advance or after"), so at the playhead a dropped
// hit reads EXACTLY as a sounding miss does in normal play (the painter's `stripCellLook` → `.playheadStep`). A fill that only
// recolours / retimes / reorders (`!changesHits`) is a visible no-op, matching "if the HITS that play are changed".
//
// (The earlier held-region set `euclideousFillStepFlash` is gone: it lit the whole region and, once gated to the playhead, its
// box map (`euclideousFillSourceStep`→`euclidReadIndex`) did not line up frame-for-frame with the comet's playhead box, so the
// override barely showed. This reads the standard hit AT THE PLAYHEAD BOX directly, so it can never point elsewhere.)

enum EuclideousFillPlayheadFlash: Equatable { case none, sounds, silencedMiss }

/// What a hit-CHANGING fill does to the box the playhead is sounding at `beat`: `.sounds` (draw it as a hit, incl. a standard rest
/// the fill plays), `.silencedMiss` (a standard hit the fill drops — draw it as a rest; at the playhead that is the normal
/// sounding-miss look), or `.none` (the standard pattern). `.none` for a non-fill lane, no active region, a recolour-only fill, or
/// `playheadBox` out of range. `standardHits` is the lane's displayed step-cell hit flags (the strip's own `d.hits`, folding in
/// FLIP HITS / `patternMiss`), indexed by displayed box.
///
/// Correct-by-construction: it reads the standard hit AT THE PLAYHEAD BOX and the fill's CURRENT slot `s = floor((beat − F)/stepLen)`
/// — the SAME slot `euclideousLaneCometChainRaw`'s comet highlights (§2.10) — so the override can never land on a box other than the
/// one the playhead is on. The ALL · FLIP · BUILD · KEEP hit-test and the BREAK drop are `Router.swift`'s.
func euclideousFillPlayheadFlash(plan: EuclideousFillPlan?, beat: Double, sub: Double, playheadBox: Int, standardHits: [Bool]) -> EuclideousFillPlayheadFlash {
    guard let plan, plan.active, sub > 0, plan.beatsPerBar > 0, playheadBox >= 0, playheadBox < standardHits.count else { return .none }
    let bn = Int((beat / plan.beatsPerBar).rounded(.down))
    guard let rg = plan.region(bar: bn), rg.changesHits, beat >= rg.F - 1e-9, beat < rg.E else { return .none }
    let o = plan.originBeat
    let N = euclideousFillCount(rg, origin: o, sub: sub)
    guard N > 0 else { return .none }
    let stepLen = max(1e-9, euclideousFillStepHostLength(rg, sub: sub))
    let s = min(max(0, N - 1), max(0, Int(((beat - rg.F) / stepLen).rounded(.down))))   // the comet's own current slot
    let std = standardHits[playheadBox]
    let hostBeat = euclideousFillSlotHostBeat(rg, origin: o, sub: sub, slot: s)
    let soundsHit: Bool
    if euclideousFillBreakDrops(rg, hostBeat: hostBeat) { soundsHit = false }
    else {
        switch rg.hits {
        case .keep:  soundsHit = std
        case .all:   soundsHit = true
        case .flip:  soundsHit = !std
        case .build: soundsHit = s >= (N + 1) / 2 ? true : std
        }
    }
    if soundsHit { return .sounds }
    return std ? .silencedMiss : .none
}
