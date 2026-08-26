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

// THE SPAN LADDER (Paul 2026-08-22 §3): CELL|ROW generalises to a dial — 1·2·3·4·6·8 columns, then ×2·×4 bars
// (stored as 16/32). The pattern anchors at the row origin and repeats every N columns → polymeter at processor grain
// (odd N against the 8-column row). CELL = 1, ROW = 8 are the byte-identical endpoints (S and the row/bar width).
let spanLadderValues = [1, 2, 3, 4, 6, 8, 16, 32]
func spanLadderLabel(_ n: Int) -> String { n == 16 ? "×2" : (n == 32 ? "×4" : "\(n)") }
/// The span's WIDTH in beats: 1 = one column (S) · 8 = the whole row (`rowBeats`, byte-identical to the old ROW —
/// honours a short loop) · ×2/×4 = 2/4 rows · 2·3·4·6 = N columns (the polymeter spans). Pure.
@inline(__always) func spanLadderBeats(_ n: Int, S: Double, row rowBeats: Double) -> Double {
    switch n {
    case ...1: return S
    case 8:    return rowBeats
    case 16:   return 2 * rowBeats
    case 32:   return 4 * rowBeats
    default:   return Double(n) * S   // 2·3·4·6 columns
    }
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

/// The generated CC VALUE (0…127) at `phase`: the unipolar shape mapped onto [min, max]. The RANGE is depth AND
/// polarity — `min > max` INVERTS (no invert flag). Pure, replay-safe. (CC-stage §1 row 3.)
@inline(__always)
func modCCValue(_ shape: ModShape, phase: Double, min lo: Int, max hi: Int, column: Int, cc: Int, cycleIndex: Int) -> Int {
    let s = modUnipolar(shape, phase: phase, column: column, cc: cc, cycleIndex: cycleIndex)
    return modMap(s, min: lo, max: hi)
}

/// Map a unipolar [0,1] onto [min,max] as a CC value (0…127). MIN > MAX inverts. The universal row-3 mapping every
/// MOD source runs through (SHAPE · FOLLOW · STEPS · STRIKE · EXTERN). Pure.
@inline(__always)
func modMap(_ s: Double, min lo: Int, max hi: Int) -> Int {
    max(0, min(127, Int((Double(lo) + max(0, min(1, s)) * Double(hi - lo)).rounded())))
}

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

/// TIMELINE MACRO LANE — the value the playhead drives at musical position `absoluteBeat` (overlay-rule-macro-lanes).
/// PURE + replay-safe: the step position = `absoluteBeat / stepBeats × rateMul`, wrapped over the 8 steps.
///  · STEP   (0) — hold this step's value across the column.
///  · SMOOTH (1) — glide across the column from this step's value toward the NEXT NON-BYPASSED value (bypassed
///                 columns are skipped when finding the target).
///  · BYPASS (2) — the lane is ABSENT this column: the macro sits at its `manual` (fader) value — sparse automation
///                 with honest gaps.
/// `lane`/`modes` are the 8-wide resolved arrays; `rateMul` from `Macro.laneRateMulResolved`.
func laneValue(lane: [Double], modes: [Int], rateMul: Double, absoluteBeat: Double, stepBeats: Double, manual: Double) -> Double {
    let n = lane.count
    guard n > 0, stepBeats > 0, rateMul > 0 else { return manual }
    let pos = absoluteBeat / stepBeats * rateMul          // continuous step position
    let idx = Int(pos.rounded(.down))
    let phase = pos - Double(idx)                          // 0…1 within the current step
    let s = ((idx % n) + n) % n                            // wrapped step (handles negatives)
    let mode = s < modes.count ? modes[s] : 0
    switch mode {
    case 2:                                                // BYPASS → the manual/fader value governs this column
        return manual
    case 1:                                                // SMOOTH → glide toward the next non-bypassed value
        var j = s
        for _ in 0..<n { j = (j + 1) % n; if (j < modes.count ? modes[j] : 0) != 2 { break } }
        let a = lane[s], b = lane[j]
        return a + (b - a) * max(0, min(1, phase))
    default:                                               // STEP → hold this step's value
        return lane[s]
    }
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

/// The within-column sweep fraction (0 at column entry → 1 at exit) in REAL time — drives every
/// mutation-line playhead (grid cells AND §6b Colour chips). SWING-AWARE: swing stretches/compresses
/// the real column window (§4), so the sweep rides the SAME `musicalOf` warp the engine uses to map
/// beats→columns, else it finishes early and wraps mid-column. At swing 50 (a = 1) `musicalOf` is the
/// identity, so this is the raw (realBeat/step) fraction. One-clock: a pure function of the beat.
func columnSweepFraction(realBeat: Double, stepBeats: Double, swing: Int) -> Double {
    let a = Double(min(75, max(50, swing))) / 50.0
    let S = max(0.001, stepBeats)
    let m = musicalOf(realBeat, stepBeats: S, a: a)
    return positiveFract(m / S)
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
                   pool: NotePool, filter: UInt8 = 0, cableMask: Int = 0b1111,
                   noteLo: UInt8 = 0, noteHi: UInt8 = 127) -> Int {
    arpPick(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern, pool: pool,
            filter: filter, cableMask: cableMask, noteLo: noteLo, noteHi: noteHi).note
}

/// The arp source pick AND the picked note's velocity (user 2026-08-09: processors inherit velocity from their
/// input source). Velocity is OCTAVE-INVARIANT — it comes from the underlying HELD note, so an octave-arped copy
/// keeps the source dynamic. Returns (-1, 0) when the pool is empty.
func arpPick(phaseIndex: Int64, octaves: Int, pattern: UInt8,
             pool: NotePool, filter: UInt8 = 0, cableMask: Int = 0b1111,
             noteLo: UInt8 = 0, noteHi: UInt8 = 127,
             octDown: Bool = false, randomAnchor: Int = 0) -> (note: Int, vel: UInt8) {
    // Legacy single-channel `filter` → channel MASK, byte-identical (0 → OMNI 0xFFFF · n → bit n−1) — then the mask body.
    let mask: UInt16 = filter == 0 ? 0xFFFF : (filter >= 1 && filter <= 16 ? (UInt16(1) << UInt16(filter - 1)) : 0)
    return arpPick(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern, pool: pool,
                   chanMask: mask, cableMask: cableMask, noteLo: noteLo, noteHi: noteHi,
                   octDown: octDown, randomAnchor: randomAnchor)
}
// MULTI-CHANNEL arp source pick (Paul 2026-08-23): filter the source by a channel MASK so an arp honours a door's
// multi-channel subset on LIVE input (the `for: cell` path passes cell.inputChanMask; a frozen omniRead pool passes OMNI).
func arpPick(phaseIndex: Int64, octaves: Int, pattern: UInt8,
             pool: NotePool, chanMask: UInt16, cableMask: Int = 0b1111,
             noteLo: UInt8 = 0, noteHi: UInt8 = 127,
             octDown: Bool = false, randomAnchor: Int = 0) -> (note: Int, vel: UInt8) {
    // RANGE (§2): arps admit only in-window source notes (vel window intentionally NOT applied to arps — unchanged).
    let fullRange = noteLo <= 0 && noteHi >= 127
    let count = fullRange ? pool.srcCount(chanMask: chanMask, cableMask: cableMask)
                          : pool.srcCount(chanMask: chanMask, cableMask: cableMask, velLo: 0, velHi: 127, noteLo: noteLo, noteHi: noteHi)
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
        // RANDOM ANCHOR (Paul 2026-08-22): each CYCLE (span steps = one full pool×oct traversal) OPENS on the anchor —
        // asc==0 is the wrap → the lowest (1) / highest (2) ascending position; the rest shuffle (seeded, loop-consistent).
        if randomAnchor != 0 && asc == 0 {
            pos = randomAnchor == 1 ? 0 : span - 1
        } else {
            let h = splitmix64Mix(UInt64(bitPattern: phaseIndex) &+ 0x9E3779B97F4A7C15)   // deterministic hash of the tick → position (loop-consistent, not accumulated)
            pos = Int(h % UInt64(span))
        }
    case .asPlayed:
        pos = asc   // ascending through the press sequence (below), not the sorted set
    }

    // AS-PLAYED reads the press-order list; every other pattern reads the sorted list. Both filtered (+ RANGE window).
    let note: Int
    if pat == .asPlayed {
        note = Int(fullRange ? pool.srcPlayed(pos % count, chanMask: chanMask, cableMask: cableMask)
                             : pool.srcPlayed(pos % count, chanMask: chanMask, cableMask: cableMask, noteLo: noteLo, noteHi: noteHi))
    } else {
        // CR-18[extra] DECISION: the ARP walk reads the whole (channel/cable/RANGE-filtered) pool — the cell's VELOCITY
        // WINDOW (velLo/velHi pinned 0…127 here) and its CHORD SPLIT are INTENTIONALLY NOT applied to the arp, unlike
        // HOLD/STRUM/RATCHET. Long-standing (the vel-window omission is documented elsewhere); to punch holes in an arp's
        // pool by register/velocity, chain a SPLIT stage before the ARP. Documented, not changed (would alter every arp).
        note = Int(fullRange ? pool.srcAscending(pos % count, chanMask: chanMask, cableMask: cableMask)
                             : pool.srcAscending(pos % count, chanMask: chanMask, cableMask: cableMask, velLo: 0, velHi: 127, noteLo: noteLo, noteHi: noteHi))
    }
    guard note >= 0 && note <= 127 else { return (-1, 0) }
    // OCT DIRECTION (Paul 2026-08-22): PATTERN orders WITHIN a lap; this orders the LAPS. DOWN = start at the top octave
    // and descend ("up the chord, down the octaves"). Byte-identical when octDown = false (the default).
    let octIdx = pos / count
    let oct = octDown ? (max(1, octaves) - 1 - octIdx) : octIdx
    return (note + 12 * oct, pool.velocity(UInt8(note)))
}

/// §item 11 convenience — same as above, reading the (channel + cable) filter straight off a SnapCell
/// so the render loop's arp source-picks can't drift the pairing. The preview/audition paths keep the
/// explicit-`filter:` form (they force a source, not the cell's).
func arpPickSource(phaseIndex: Int64, octaves: Int, pattern: UInt8, pool: NotePool, for cell: SnapCell,
                   octDown: Bool = false, randomAnchor: Int = 0) -> Int {
    arpPick(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern, pool: pool, for: cell, octDown: octDown, randomAnchor: randomAnchor).note
}
func arpPick(phaseIndex: Int64, octaves: Int, pattern: UInt8, pool: NotePool, for cell: SnapCell,
             octDown: Bool = false, randomAnchor: Int = 0) -> (note: Int, vel: UInt8) {
    // MULTI-CHANNEL (Paul 2026-08-23): filter by the cell's channel MASK (was the legacy single `inputChannel` — which is
    // OMNI for a multi-channel-masked door, so an arp ignored the mask on live input). omniRead FROZEN pool → skip the
    // door filter entirely (channel/cable/range applied at capture; see NotePool.omniRead).
    arpPick(phaseIndex: phaseIndex, octaves: octaves, pattern: pattern,
            pool: pool, chanMask: pool.omniRead ? 0xFFFF : cell.inputChanMask, cableMask: pool.omniRead ? 0b1111 : Int(cell.inputCableMask),
            noteLo: pool.omniRead ? 0 : cell.inputRangeLo, noteHi: pool.omniRead ? 127 : cell.inputRangeHi,   // RANGE (§2)
            octDown: octDown, randomAnchor: randomAnchor)
}

// MARK: - Processor dispatch (§3/§4)

/// What a cell does THIS render. Centralises processor dispatch: bypass and not-yet-built types
/// fall back to identity; an implemented processor gets its own mode; a closed PASSGATE is silent.
/// Adding a processor = one case here + its branch in the loop.
enum CellMode: Equatable { case arp, ratchet, strum, chance, harmonize, echo, euclid, burst, cascade, drone, shift, humanize, tutti, length, weave, split, octave, transpose, riff, identity, silent }

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

// MARK: - ON TAP timing (§9 item 1, 4c) — quantized onset + duration expiry (pure functions of the beat)

/// The musical beat at which a tapped action TAKES EFFECT: NOW = immediately; STEP / PASS = the next step /
/// pass boundary strictly after the tap. (LAP ≈ PASS in v1 — the true §5b lap boundary is deferred.)
func tapOnsetBeat(tapBeat: Double, quant: OnTapWhen, stepBeats: Double) -> Double {
    let step = max(0.01, stepBeats), cycle = step * 8
    switch quant {
    case .now:          return tapBeat
    case .step:         return (floor(tapBeat / step) + 1) * step
    case .pass, .lap:   return (floor(tapBeat / cycle) + 1) * cycle
    }
}

/// The musical beat at which a tapped action EXPIRES: RETAP = never (held until re-tap); 1-PASS / 1-LAP = one
/// pass after onset. (1-LAP ≈ 1-PASS in v1.)
func tapExpiryBeat(onsetBeat: Double, duration: OnTapFor, stepBeats: Double) -> Double {
    switch duration {
    case .retap:            return .infinity
    case .onePass, .oneLap: return onsetBeat + max(0.01, stepBeats) * 8
    }
}

/// One ON-TAP overlay: a timed, ephemeral flip on a cell (never a document write). `cell` = col*8+row;
/// `busMask` carries the emitter bits (used by SOLO). Pure value type so the overlay logic stays testable.
/// (Distinct from `TapAction`, the persisted per-scene setting in Models — this is a live overlay instance.)
enum TapKind { case alt, mute, solo }
struct TapOverlay: Equatable { let cell: Int; let kind: TapKind; let busMask: UInt8; let onset: Double; let expiry: Double }

/// Apply a tap to the live overlay list. RETAP toggles OFF an existing same-cell+kind overlay; otherwise the
/// tap REPLACES any prior for that cell+kind with a fresh one (re-tap re-arms). Pure — returns the new list.
func applyTapOverlay(_ overlays: [TapOverlay], cell: Int, kind: TapKind, busMask: UInt8,
                     onset: Double, expiry: Double, retap: Bool) -> [TapOverlay] {
    if retap, let i = overlays.firstIndex(where: { $0.cell == cell && $0.kind == kind }) {
        var a = overlays; a.remove(at: i); return a      // RETAP: a second tap toggles it off
    }
    var a = overlays.filter { !($0.cell == cell && $0.kind == kind) }
    a.append(TapOverlay(cell: cell, kind: kind, busMask: busMask, onset: onset, expiry: expiry))
    return a
}

/// The live ON-TAP masks at beat `now`: expired overlays dropped; only overlays whose onset has arrived
/// contribute. alt/mute are per-cell bitmasks (bit = col*8+row); solo is a per-emitter busMask union
/// (seeded with `footSolo`, the emitter-strip foot SOLO). Pure — drives `refreshTapMasks` each poll + tap.
func tapOverlayMasks(_ overlays: [TapOverlay], now: Double, footSolo: UInt8 = 0)
    -> (surviving: [TapOverlay], alt: UInt64, mute: UInt64, solo: UInt8) {
    let surviving = overlays.filter { now < $0.expiry }
    var alt: UInt64 = 0, mute: UInt64 = 0, solo: UInt8 = footSolo
    for a in surviving where a.onset <= now {
        switch a.kind {
        case .alt:  alt  |= 1 << UInt64(a.cell)
        case .mute: mute |= 1 << UInt64(a.cell)
        case .solo: solo |= a.busMask
        }
    }
    return (surviving, alt, mute, solo)
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
func cellMode(type: ProcessorType, bypassed: Bool, passMask: UInt8, pass: Int) -> CellMode {
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
    case .split:     return .split                            // set-membership filter — keep a subset of the chord (a HOLD transform / set filter)
    case .octave:    return .octave                          // UTILITY — shift ±3 octaves (pitch transform)
    case .transpose: return .transpose                       // UTILITY — shift ±24 semitones
    case .channel, .nudge, .dest, .muteMatrix, .tap: return .identity   // UTILITY/ROUTING — note-transparent; the emit-side effect (channel/timing/emitter override · TAP's mid-chain send) applies elsewhere
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
    let addedVel = clampVel(Int((Double(baseVel) * velScale).rounded()))
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

/// Multi-cell routing (AcceptanceCriteria 2026-07-29): the per-column route-FOCUS map. A column contributes a
/// focus ONLY if EXACTLY ONE of the given cells is in it (2+ in a column is ambiguous → no focus there; ⑥ keeps
/// PLACE from ever hitting that, but SELECT can). Pure so the focus rule is unit-tested independent of SwiftUI.
/// Input = (col,row) pairs, already occupancy-filtered. Returns col → focus row.
func routeFociByColumn(_ cells: [(col: Int, row: Int)]) -> [Int: Int] {
    var byCol: [Int: [Int]] = [:]
    for c in cells { byCol[c.col, default: []].append(c.row) }
    return byCol.compactMapValues { $0.count == 1 ? $0[0] : nil }
}

// (Removed 2026-07-30: `placedCellRouting`/`PlacedRouting` — freshly placed cells no longer inherit or nudge
// any routing. A new cell is created with the model defaults: MIDI-IN + emitter A, wired by hand afterwards.)

// MARK: - Visual overhaul: EMBLEMS (cells & colour desk, AcceptanceCriteria 2026-07-29)

/// ONE static glyph per processor type — the "emblem" drawn on the cell face + the desk title. Placeholder
/// SF Symbol names this wave (the drawn artwork is a separate asset job). Pure so the mapping is testable.
func emblemSymbol(_ t: ProcessorType) -> String {
    switch t {
    case .arp:       return "chart.line.uptrend.xyaxis"   // the climb
    case .ratchet:   return "bolt.fill"                   // the burst
    case .passgate:  return "rectangle.split.3x1"         // the gate
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
    case .dest:      return "arrow.triangle.branch"        // ROUTING — per-step emitter (the hocket)
    case .muteMatrix: return "speaker.slash"               // ROUTING — per-step part-muting (the gate grid)
    case .riff:      return "music.note.list"              // DRIVER — the stored rank stencil (the chord-following line)
    case .tap:       return "arrow.turn.up.right"          // ROUTING — the mid-chain send (the stream turns off to a parallel wire)
    }
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
/// (Models.editScopeTargets `.twins`) MINUS colourID — colour is the hue block, not the seal. Sets are
/// sorted (unordered → canonical); chop keeps its raw nil vs value (matching the twin predicate exactly, so
/// twins share a seal). Triggers live on Colour, not Cell → excluded until they re-host. Codable → bytes.
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
/// The RESOLVED chain a cell actually plays: its per-cell override, else the colour's TEMPLATE, else the colour's
/// A face. The seal must hash THIS — a template/A-face cell has NIL `processors`, so its machine comes from the
/// colour; hashing raw nil made every such cell (the DEFAULT arc + most factory presets) share ONE seal. (Same
/// 3-tier resolution as SnapshotBuilder / AU.materializedChain.) Pure.
func resolvedCellChain(_ cell: Cell, colours: [Colour]) -> [ProcessorSlot] {
    if let p = cell.processors { return p }                              // per-cell OVERRIDE (incl. an explicit [] passthrough)
    let c = colours.first { $0.colourID == cell.colourID }
    if let t = c?.templateChain, !t.isEmpty { return t }                 // colour TEMPLATE
    return [ProcessorSlot(type: c?.type ?? .passgate, params: c?.paramsA ?? ColourParams())]   // legacy A face
}
/// A 32-bit FNV-1a over the JSON (sorted keys) of the behavioural config. Same config ⇒ same value on every
/// device (document-visible truth); config-twins (regardless of colour) share it. Pure/testable. §1 contract.
/// Hashes the RESOLVED chain (needs `colours`) so template/A-face cells reflect their colour's machine.
func sealHash(_ cell: Cell, colours: [Colour]) -> UInt32 {
    let chopKey = cell.chop.map { SealChopKey(m: $0.mainMask, a: $0.altMask, mu: $0.muteMask, alt: $0.altDest.map { $0.cable }.sorted()) }
    let key = SealKey(p: resolvedCellChain(cell, colours: colours), ir: cell.inputReceiver, irow: cell.inputRow,
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
func sealFit(_ geo: SealGeometry) -> SealFit {
    let xs = geo.nodes.map { $0.x }, ys = geo.nodes.map { $0.y }
    let minX = xs.min() ?? 0, maxX = xs.max() ?? 0, minY = ys.min() ?? 0, maxY = ys.max() ?? 0
    let rangeX = maxX - minX, rangeY = maxY - minY
    let fractions = geo.nodes.map { n in
        SIMD2(rangeX > 0 ? (n.x - minX) / rangeX : 0.5,
              rangeY > 0 ? (n.y - minY) / rangeY : 0.5)
    }
    return SealFit(fractions: fractions, rangeX: rangeX, rangeY: rangeY)
}

/// D3: the CENSUS — how many painted cells use each Colour, across all scenes. Census > 0 protects a Colour
/// from deletion (scenes-are-precious). Pure/testable.
func colourCensus(_ scenes: [SceneState]) -> [String: Int] {
    var n: [String: Int] = [:]
    for s in scenes { for col in s.cells { for cell in col { if let id = cell?.colourID { n[id, default: 0] += 1 } } } }
    return n
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

// MARK: - Routing visualisation graph (the while-wiring overlay)

struct RouteCell: Hashable { let col: Int; let row: Int }
enum RouteAnchor: Equatable { case receiver(Int), cell(RouteCell), emitter(Int) }
struct RouteEdge: Equatable { let from: RouteAnchor; let to: RouteAnchor; let lit: Bool }

/// The routing graph to draw while a verb is held: for every occupied cell, an INPUT edge (from its receiver if
/// MIDI-IN, else from its parent cell) and one OUTPUT edge per emitter it feeds. An edge is `lit` when its cell
/// sits on a path that runs through a SELECTED cell — i.e. the selected cell's connected input/output chain
/// (chains are per-column via `inputRow`). Pure so the graph is unit-testable; the view maps anchors → points.
func routingEdges(cells: [[Cell?]], selected: Set<RouteCell>) -> [RouteEdge] {
    func occupied(_ col: Int, _ row: Int) -> Bool { col < cells.count && row >= 0 && row < cells[col].count && cells[col][row] != nil }

    // lit = the selected cells themselves (grid-chaining retired → there is no cross-cell chain to trace).
    let lit = Set(selected.filter { occupied($0.col, $0.row) })

    var edges: [RouteEdge] = []
    for col in cells.indices {
        for row in cells[col].indices {
            guard let c = cells[col][row] else { continue }
            let here = RouteCell(col: col, row: row), on = lit.contains(here)
            if let rcv = c.inputReceiver {                     // MIDI-IN: receiver → this cell (nil receiver = unrouted → no edge)
                edges.append(RouteEdge(from: .receiver(rcv), to: .cell(here), lit: on))
            }
            for b in Bus.allCases where c.buses.contains(b) { // this cell → each emitter it feeds
                edges.append(RouteEdge(from: .cell(here), to: .emitter(Int(b.cable)), lit: on))
            }
        }
    }
    return edges
}
