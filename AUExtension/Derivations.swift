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

    // MARK: - input-channel filter (delta §7): a MIDI-IN cell hears only its channel. `filter` is
    // 0 = OMNI (all held notes) or 1–16 (only notes arriving on that channel; wire channel = filter−1).
    // OMNI paths return the existing OMNI views in O(1); a real filter scans (≤128, source reads only).

    // §item 11 INPUT CABLES: admission is CHANNEL and CABLE. `cableMask` (bit i = cable i+1) defaults to
    // ANY (0b1111) so every existing call is unchanged; a cabled receiver passes its own mask.
    @inline(__always) private func matches(_ note: UInt8, _ filter: UInt8, _ cableMask: Int) -> Bool {
        (filter == 0 || chan[Int(note)] == filter - 1)
            && receiverHearsCable(mask: cableMask, eventCable: Int(cbl[Int(note)]))
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

    // §item 11: convenience readers — pull BOTH filter fields (channel + cable) off a SnapCell in one
    // place, so the render loop's ~dozen source-pick sites can't drift the (inputChannel, inputCableMask)
    // pairing. The base filter-taking methods stay for the preview/audition paths (which force a filter).
    func srcCount(for cell: SnapCell) -> Int {
        srcCount(filter: cell.inputChannel, cableMask: Int(cell.inputCableMask))
    }
    func srcAscending(_ k: Int, for cell: SnapCell) -> UInt8 {
        srcAscending(k, filter: cell.inputChannel, cableMask: Int(cell.inputCableMask))
    }

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

/// PASSTHROUGH routing (§2.6 reconciled to the §7b 5-cable model). The raw CC/PB/AT stream and the
/// stopped-transport NOTE passthrough go out on **All (cable 0) + Emit A (cable 1)** — bit i set ⇒
/// forward on cable i. CC/PB/AT always forward; notes forward ONLY when stopped and not being replaced
/// by an audition (§6.4). Returns 0 = drop. Two cables so a synth patched to either "All" or "Emit A"
/// receives controllers + soundcheck; the §6a emitter toggle governs NOTE emission, not this raw stream.
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

    /// PANIC / reset: the (channel, note) of every note still awaiting its OFF (for an all-notes-off flush),
    /// then clears them. The render side emits note-offs for these to guarantee silence.
    mutating func drainActive() -> [(channel: UInt8, note: UInt8)] {
        guard activeCount > 0 else { return [] }
        var out: [(UInt8, UInt8)] = []
        for i in 0..<active.count where active[i] { out.append((UInt8(i >> 7), UInt8(i & 0x7F))); active[i] = false }
        activeCount = 0
        return out
    }
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

/// The within-column sweep fraction (0 at column entry → 1 at exit) in REAL time — drives every
/// mutation-line playhead (grid cells AND §6b Colour chips). SWING-AWARE: swing stretches/compresses
/// the real column window (§4), so the sweep rides the SAME `musicalOf` warp the engine uses to map
/// beats→columns, else it finishes early and wraps mid-column. At swing 50 (a = 1) `musicalOf` is the
/// identity, so this is the raw (realBeat/step) fraction. One-clock: a pure function of the beat.
func columnSweepFraction(realBeat: Double, stepBeats: Double, swing: Int) -> Double {
    let a = Double(min(75, max(50, swing))) / 50.0
    let S = max(0.001, stepBeats)
    let m = musicalOf(realBeat, stepBeats: S, a: a)
    return ((m / S).truncatingRemainder(dividingBy: 1) + 1).truncatingRemainder(dividingBy: 1)
}

/// COLUMN-SUBSET LAP (delta §5b) — the whole perform-v2 feature in one function. With `laneMask` the
/// held columns (bit i set ⇒ column i is held), the EFFECTIVE column at global step `absoluteStep` is
/// the (absoluteStep mod k)-th held column, ordered left→right (k = held count). Only column SELECTION
/// is warped; the true timeline is untouched (pass/passgate/swing all run off it). `laneMask == 0`
/// (nothing held) passes `trueColumn` through unchanged. k∤8 gives the INTENDED polymeter rotation —
/// the mapping is never reset at pass boundaries, so a k-cycle phases against the 8-step timeline.
func lapColumn(laneMask: UInt8, absoluteStep: Int, trueColumn: Int) -> Int {
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

/// The base note (pre-this-cell-transpose) a source-reading ARP picks at pattern index `phaseIndex`,
/// for the given PATTERN over `octaves`. `filter` (delta §7) restricts the source pool to one input
/// channel (0 = OMNI). All patterns are pure functions of position (loop-consistent). Chord changes
/// never reset the index. Returns -1 for an empty (filtered) pool. No channel is returned — past the
/// input filter notes carry no channel (delta §7); emission stamps the bus channel.
func arpPickSource(phaseIndex: Int64, octaves: Int, pattern: UInt8,
                   pool: NotePool, filter: UInt8 = 0, cableMask: Int = 0b1111) -> Int {
    let count = pool.srcCount(filter: filter, cableMask: cableMask)
    guard count > 0 else { return -1 }
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
        pos = asc   // ascending through the press sequence (below), not the sorted set
    }

    // AS-PLAYED reads the press-order list; every other pattern reads the sorted list. Both filtered.
    let note = (pat == .asPlayed) ? Int(pool.srcPlayed(pos % count, filter: filter, cableMask: cableMask))
                                  : Int(pool.srcAscending(pos % count, filter: filter, cableMask: cableMask))
    return note + 12 * (pos / count)
}

/// §item 11 convenience — same as above, reading the (channel + cable) filter straight off a SnapCell
/// so the render loop's arp source-picks can't drift the pairing. The preview/audition paths keep the
/// explicit-`filter:` form (they force a source, not the cell's).
func arpPickSource(phaseIndex: Int64, octaves: Int, pattern: UInt8, pool: NotePool, for cell: SnapCell) -> Int {
    arpPickSource(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern,
                  pool: pool, filter: cell.inputChannel, cableMask: Int(cell.inputCableMask))
}

// MARK: - Processor dispatch (§3/§4)

/// What a cell does THIS render. Centralises processor dispatch: bypass and not-yet-built types
/// fall back to identity; an implemented processor gets its own mode; a closed PASSGATE is silent.
/// Adding a processor = one case here + its branch in the loop.
enum CellMode: Equatable { case arp, ratchet, strum, chance, harmonize, identity, silent }

// MARK: - Colour-pair morph tier (delta §9 item 5)

/// The morph capability of a Colour's pairing. `none` = unpaired (inert). `full` = the partner is the
/// SAME processor type → all params glide (§3.2 stepped-quantize interpolation). `swap` = different types
/// → a clean binary flip at the cell's ALT bit, NO fader ("the fader never lies"). `partial` = FUTURE
/// (shared "channels" glide while type identity flips) — the enum admits it; v1 never emits it.
enum MorphTier: UInt8, Equatable { case none, full, swap, partial }

/// Derive the tier from the pairing. `partner` is nil when unpaired.
func morphTier(selfType: ProcessorType, partner: ProcessorType?) -> MorphTier {
    guard let partner else { return .none }
    return selfType == partner ? .full : .swap
}

// MARK: - Receiver channel match (delta §9 item 11)

/// Does a receiver with `filter` (0 = OMNI, 1–16) hear a note arriving on wire `channel` (0–15)?
/// Wire channel = filter − 1. Used for input metering attribution (and mirrors NotePool's source filter).
@inline(__always) func receiverHears(filter: UInt8, channel: UInt8) -> Bool {
    filter == 0 || filter == channel + 1
}

/// INPUT CABLES admission (§item 11): does a receiver whose cable BITMASK is `mask` (bit i = cable i+1)
/// hear an event arriving on `eventCable` (1–4)? ANY = all bits set. An out-of-range/unknown cable (0 or
/// >4 — e.g. a single-input host that doesn't tag, or legacy) is heard by everyone (compatibility). This
/// is the cable comparison that sits AHEAD of the channel filter; the full admission is `cable AND channel`.
@inline(__always) func receiverHearsCable(mask: Int, eventCable: Int) -> Bool {
    guard eventCable >= 1 && eventCable <= 4 else { return true }
    return (mask & (1 << (eventCable - 1))) != 0
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

/// ALT-ALTERNATE: flip the cell's ALT bit every EVERY-N arrivals. arrivals 0 (first pass) = the base state.
func arriveAlt(base: Bool, on: OnConfig, arrivals: Int) -> Bool {
    guard on.arrive == .altAlternate, arrivals >= 0 else { return base }
    let n = max(1, on.arriveEvery)
    return base != ((arrivals / n) & 1 == 1)          // XOR the base with the flip parity
}

/// MORPH-DRIFT: advance the morph position by driftPct% every EVERY-N arrivals, wrapped (↻ sawtooth) or
/// bounced (⇄ triangle) into [0,1]. arrivals 0 = the base morph.
func arriveMorph(base: Double, on: OnConfig, arrivals: Int) -> Double {
    guard on.arrive == .morphDrift, arrivals >= 0 else { return base }
    let n = max(1, on.arriveEvery)
    let pos = base + Double(arrivals / n) * (Double(on.driftPct) / 100.0)
    switch on.driftMode {
    case .loop:                                       // sawtooth 0→1→0
        return pos - floor(pos)
    case .pingpong:                                   // triangle 0→1→0→1
        var ph = pos.truncatingRemainder(dividingBy: 2); if ph < 0 { ph += 2 }
        return ph <= 1 ? ph : 2 - ph
    }
}

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

/// `effectiveT` with ON ARRIVE applied — the alt/morph-based arrive treatments fold in here so the three
/// PLAYING derivation sites share one hook. Preview/audition pass through `effectiveT` directly (no arrivals).
@inline(__always)
func effectiveTWithArrive(_ c: SnapColour, baseMorph: Double, baseAlt: Bool, arrivals: Int) -> Double {
    effectiveT(c, morph: arriveMorph(base: baseMorph, on: c.on, arrivals: arrivals),
               alt: arriveAlt(base: baseAlt, on: c.on, arrivals: arrivals))
}

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
    case 0x9: return (0x90 | chan, idx, UInt8(max(1, min(127, Int((w1 >> 16) & 0xFFFF) >> 9))), 3, group)  // note-on (16→7, min 1)
    case 0xB: return (0xB0 | chan, idx, UInt8((w1 >> 25) & 0x7F), 3, group)              // CC (32→7)
    case 0xD: return (0xD0 | chan, UInt8((w1 >> 25) & 0x7F), 0, 2, group)                // channel pressure
    case 0xE: let v14 = (w1 >> 18) & 0x3FFF                                              // pitch bend (32→14)
              return (0xE0 | chan, UInt8(v14 & 0x7F), UInt8((v14 >> 7) & 0x7F), 3, group)
    default:  return nil
    }
}

@inline(__always)
func cellMode(type: ProcessorType, bypassed: Bool, passMask: UInt8, pass: Int) -> CellMode {
    if bypassed { return .identity }                       // §3: bypass = identity processor
    switch type {
    case .arp:       return .arp
    case .ratchet:   return .ratchet
    case .strum:     return .strum
    case .chance:    return .chance
    case .harmonize: return .harmonize
    case .passgate:                                        // §3/§4: gated by pass (mod 4)
        let bit = ((pass % 4) + 4) % 4
        return (passMask & (UInt8(1) << bit)) != 0 ? .identity : .silent
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
                     vels: inout [UInt8]) -> Int {
    var n = 0
    func add(_ note: Int, _ v: UInt8) {
        guard note >= 0 && note <= 127 else { return }
        for i in 0..<n where out[i] == note { return }    // de-dup (unison → single voice)
        out[n] = note; vels[n] = v; n += 1
    }
    add(base, baseVel)                                     // root at full velocity
    let addedVel = UInt8(max(1, min(127, Int((Double(baseVel) * velScale).rounded()))))
    for iv in [intervals.0, intervals.1, intervals.2] where iv != 0 { add(base + Int(iv), addedVel) }
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
    var h = UInt64(bitPattern: q) &* 0x9E3779B97F4A7C15 &+ UInt64(bitPattern: Int64(note &* 2654435761))
    h = (h ^ (h >> 30)) &* 0xBF58476D1CE4E5B9
    h = (h ^ (h >> 27)) &* 0x94D049BB133111EB
    h ^= (h >> 31)
    return Double(h >> 11) * (1.0 / 9_007_199_254_740_992.0) < probability
}

// MARK: - STRUM (§3): stagger a chord's onsets over `spread`, with a timing curve and velocity tilt

/// The onset delay (in beats, 0…spread) for strum position `j` of `count` notes. curve 0 = even
/// spacing; curve>0 bunches the early notes then opens out; curve<0 the reverse (exp = 2^curve, so
/// ±1 → ×2 / ÷2 of the linear fraction). ASSUMPTION: this curve shape is a feel choice — tune freely.
@inline(__always)
func strumOffset(index j: Int, count: Int, spread: Double, curve: Double) -> Double {
    guard count > 1 else { return 0 }
    let frac = Double(j) / Double(count - 1)              // 0 (first) … 1 (last)
    let shaped = pow(frac, pow(2.0, curve))              // curve 0 → linear
    return spread * shaped
}

/// Velocity for strum position `j`. tilt 0 = flat at base; tilt>0 crescendos across the strum
/// (first softer, last louder), tilt<0 decrescendos. ASSUMPTION: linear tilt around the base.
@inline(__always)
func strumVelocity(index j: Int, count: Int, tilt: Double, base: Int) -> UInt8 {
    guard count > 1 else { return UInt8(max(1, min(127, base))) }
    let frac = Double(j) / Double(count - 1)              // 0 … 1
    let scale = 1 + tilt * (frac - 0.5)                  // [1 − tilt/2 … 1 + tilt/2]
    return UInt8(max(1, min(127, Int((Double(base) * scale).rounded()))))
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
    guard count > 1 else { return UInt8(max(1, min(127, base))) }
    let frac = Double(index) / Double(count - 1)          // 0 (first) … 1 (last)
    let scale = (1.0 - ramp) + ramp * frac                // ramp 0 → 1; ramp 1 → frac
    return UInt8(max(1, min(127, Int((Double(base) * scale).rounded()))))
}
