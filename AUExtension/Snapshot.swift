//  Snapshot.swift
//  MidiSpark — the snapshot bridge (spec v2.8 §7).
//
//  The render thread NEVER reads the document. It reads a SnapshotBox: flat, fixed-size,
//  immutable after construction, published by atomic pointer swap. The UI thread builds
//  boxes (SnapshotBuilder) and publishes them (SnapshotStore.publish, MAIN THREAD ONLY).
//  Reads on the render thread are lock-free and allocation-free (acquire = one atomic load).

import Foundation
// Foundation-only on purpose: the effective-parameter functions below (§3.2 morph interpolation +
// quantization) are pure and unit-tested off-device. SnapshotStore — the one piece needing
// swift-atomics — lives in SnapshotStore.swift so this file can join the test target.

// MARK: - Fixed geometry

enum Snap {
    static let cols = 8, rows = 8, colours = 16
    // delta §9 item 11: a source filter ≥17 matches no held note (NotePool.matches never sees chan ≥16),
    // so it is the render-free way to express a MUTED receiver — its subscribers read an empty pool.
    static let mutedSourceFilter: UInt8 = 17
    // Ladders shared by builder and kernel. Order MUST match the enums' allCases (§8: stable).
    static let arpRateBeats: [Double] = ArpRate.allCases.map(\.beats)
    static let stepRateBeats: [Double] = StepRate.allCases.map(\.beats)
}

// MARK: - Flat cell (one per grid position; colourIndex < 0 = empty)

struct SnapCell {
    var colourIndex: Int8 = -1
    var alt = false
    var bypassed = false
    var muted = false
    var busMask: UInt8 = 0     // bits 0–3 = A–D (§2.3: the only exits)
    var runStartColumn: Int8 = -1   // LEGATO precompute (§7 v2.4) — UI-thread work, render just reads
    // v3.0 graph routing (delta §1, precomputed here so render never scans):
    var resolvedParent: Int8 = -1   // referenced row IF occupied & ≠ self, else −1 (= MIDI IN)
    var inputChannel: UInt8 = 0     // delta §7: source filter, 0 = OMNI, 1–16 channel, ≥17 = match-nothing
                                    // (a muted receiver; Snap.mutedSourceFilter). Resolved from the cell's
                                    // receiver at build time — MIDI-IN cells only; render just reads it.
    var resolvedReceiver: Int8 = -1 // delta §9 item 11: the receiver a MIDI-IN cell reads (0–3), else −1
    var inputCableMask: UInt8 = 0b1111  // §item 11 INPUT CABLES: the receiver's cable bitmask (ANY = all); render just reads it
}

// MARK: - Resolved per-state params (paramsB pre-merged over paramsA at build time)

struct SnapParams {
    var type: ProcessorType = .arp
    var patternIndex: UInt8 = 0
    var rateIndex: Int8 = 3          // index into Snap.arpRateBeats
    var octaves: UInt8 = 1
    var gate: Double = 0.6
    var phase: ArpPhase = .retrig
    var count: UInt8 = 3             // ratchet
    var ramp: Double = 0.5
    var passMask: UInt8 = 0b1111     // passgate
    var strumDir: StrumDir = .up     // strum
    var spread: Double = 0.1         // strum stagger, beats
    var curve: Double = 0            // strum timing curve −1…1
    var velTilt: Double = 0          // strum velocity tilt −1…1
    var probability: Double = 1      // chance: pass-through probability 0…1
    var harmIntervals: (Int8, Int8, Int8) = (0, 0, 0)   // harmonize: 3 added-voice intervals (0 = off)
    var harmVelScale: Double = 0.8   // harmonize: velocity scale on added voices
}

struct SnapColour {
    var transpose: Int8 = 0
    var morph: Double = 0
    var a = SnapParams()
    var b = SnapParams()             // delta item 8: this Colour's OWN procB resolved params (= a if B-less)
    var tier: MorphTier = .none      // none/full/swap — gates how a→b resolves (glide vs binary flip)
    var on = OnConfig()              // delta §9 item 1: the resolved ON assignments (arrive/scene = derivations,
}                                    // tap/hold = ephemeral gestures); render reads it precomputed here.

// MARK: - The box: immutable after construction → safe concurrent reads, no locks

final class SnapshotBox {
    let generation: UInt64           // increments per publish; render clears param overrides on change
    let stepBeats: Double
    let swing: Double                // 50…75 (§4 v2.3)
    let morphMaster: Double          // §13.5, parameter #35
    let colours: [SnapColour]        // exactly 16
    let cells: [SnapCell]            // 64, index = column * 8 + row
    let busChannels: [UInt8]         // v3.0 (delta §7): 4 stamp channels (1–16) for buses A–D
    let busEnabledMask: UInt8        // delta §6a: bit i set ⇒ emitter i (A–D) enabled; disabled = no output
    let claimEmitter: Int8           // delta §6a: the one-claimant CLAIM emitter (0–3), or −1 = none
    let flattenMask: UInt8           // emitter role family: bit i = emitter i ducks OTHER emitters while it sounds
    let flattenAmount: [UInt8]       // 4 per-emitter FLATTEN amounts (0…100 %)
    let altMask: UInt8               // emitter role family: the ALT turn-taking group (bits A–D)
    let altCount: [UInt8]            // 4 per-emitter ALT notes-per-turn (1…8)
    let masterKey: Int8              // master panel: per-scene master transpose (−12…12), on every output note
    let masterMute: Bool             // master panel: global emission kill
    let thruReceiver: Int8           // receiver strip: the THRU-pip receiver (0–3) passthrough follows (default 0 = R1)
    let receiverChannels: [UInt8]    // delta §9 item 11: the 4 receivers' channel filters (0 = OMNI, 1–16) — input metering
    let receiverCables: [UInt8]      // §item 11 INPUT CABLES: the 4 receivers' cable bitmasks (ANY = 0b1111) — input metering

    init(generation: UInt64, stepBeats: Double, swing: Double, morphMaster: Double,
         colours: [SnapColour], cells: [SnapCell], busChannels: [UInt8], busEnabledMask: UInt8 = 0b1111,
         claimEmitter: Int8 = -1, flattenMask: UInt8 = 0, flattenAmount: [UInt8] = [0, 0, 0, 0],
         altMask: UInt8 = 0, altCount: [UInt8] = [1, 1, 1, 1],
         masterKey: Int8 = 0, masterMute: Bool = false,
         thruReceiver: Int8 = 0, receiverChannels: [UInt8] = [0, 0, 0, 0],
         receiverCables: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111]) {
        self.generation = generation
        self.stepBeats = stepBeats
        self.swing = swing
        self.morphMaster = morphMaster
        self.colours = colours
        self.cells = cells
        self.busChannels = busChannels
        self.busEnabledMask = busEnabledMask
        self.claimEmitter = claimEmitter
        self.flattenMask = flattenMask
        self.flattenAmount = flattenAmount
        self.altMask = altMask
        self.altCount = altCount
        self.masterKey = masterKey
        self.masterMute = masterMute
        self.thruReceiver = thruReceiver
        self.receiverChannels = receiverChannels
        self.receiverCables = receiverCables
    }
}

// MARK: - Effective params (render-side, §3.2: stepped fields quantize, never glide)

/// The effective morph position for ONE CELL — the value every effective* helper takes as `t` to
/// interpolate a→b. Tier-aware (delta §9 item 5): `none` (unpaired) → 0, always A; `full`/`partial`
/// (same-ish type) → ALT pins full-B, else the Colour's morph macro (0…1); `swap` (cross-type) → a BINARY
/// flip on the ALT bit (0 or 1, no intermediate — the morph fader is inert for a swap pair). The global
/// morphMaster (param #300) is RETIRED — morph is per-Colour only. Cells differ only by their alt bit.
@inline(__always)
func effectiveT(_ c: SnapColour, morph: Double, alt: Bool) -> Double {
    switch c.tier {
    case .none:  return 0
    case .swap:  return alt ? 1.0 : 0.0
    default:     return alt ? 1.0 : min(1.0, max(0.0, morph))   // full, partial
    }
}

/// The effective processor TYPE for a cell — flips to the partner's type at t≥0.5 (only a `swap` pair has
/// a≠b type; `full`/`none` keep A's type at every t).
@inline(__always)
func effectiveType(_ c: SnapColour, t: Double) -> ProcessorType { t >= 0.5 ? c.b.type : c.a.type }

/// The effective passgate mask for a cell — follows the type flip (partner's mask past the midpoint).
@inline(__always)
func effectivePassMask(_ c: SnapColour, t: Double) -> UInt8 { t >= 0.5 ? c.b.passMask : c.a.passMask }

@inline(__always)
func effectiveRateBeats(_ c: SnapColour, t: Double) -> Double {
    let ia = Double(c.a.rateIndex), ib = Double(c.b.rateIndex)
    let idx = Int((ia + (ib - ia) * t).rounded())
    return Snap.arpRateBeats[max(0, min(Snap.arpRateBeats.count - 1, idx))]
}

@inline(__always)
func effectiveGate(_ c: SnapColour, t: Double) -> Double {
    c.a.gate + (c.b.gate - c.a.gate) * t                      // continuous: linear
}

@inline(__always)
func effectiveOctaves(_ c: SnapColour, t: Double) -> Int {
    let v = Double(c.a.octaves) + (Double(c.b.octaves) - Double(c.a.octaves)) * t
    return max(1, min(4, Int(v.rounded())))                   // stepped: round, clamp legal
}

// RATCHET (§3): repeats per step. Stepped field — interpolate then quantize to a LEGAL count
// (2/3/4/6/8; 5 and 7 are not legal), never gliding through illegal values (§3.2).
@inline(__always)
func effectiveRepeats(_ c: SnapColour, t: Double) -> Int {
    let v = Double(c.a.count) + (Double(c.b.count) - Double(c.a.count)) * t
    let legal = [2, 3, 4, 6, 8]
    var best = legal[0], bestD = Double.greatestFiniteMagnitude
    for L in legal { let d = abs(Double(L) - v); if d < bestD { bestD = d; best = L } }
    return best
}

// RATCHET velocity ramp 0–100% (§3): continuous.
@inline(__always)
func effectiveRamp(_ c: SnapColour, t: Double) -> Double {
    max(0, min(1, c.a.ramp + (c.b.ramp - c.a.ramp) * t))
}

// STRUM (§3): spread is B-overridable + continuous; curve/velTilt continuous. Direction not morphed.
@inline(__always)
func effectiveSpread(_ c: SnapColour, t: Double) -> Double {
    max(0, min(1, c.a.spread + (c.b.spread - c.a.spread) * t))
}

// CHANCE (§3): probability is B-overridable + continuous.
@inline(__always)
func effectiveProbability(_ c: SnapColour, t: Double) -> Double {
    max(0, min(1, c.a.probability + (c.b.probability - c.a.probability) * t))
}

// HARMONIZE (§3): the 3 added-voice intervals are STEPPED (semitones) — interpolate each toward B
// and round; velScale is continuous. Intervals clamp to −24…+24; 0 = voice off.
@inline(__always)
func effectiveHarmInterval(_ c: SnapColour, voice: Int, t: Double) -> Int {
    let a: Int, b: Int
    switch voice {
    case 0: a = Int(c.a.harmIntervals.0); b = Int(c.b.harmIntervals.0)
    case 1: a = Int(c.a.harmIntervals.1); b = Int(c.b.harmIntervals.1)
    default: a = Int(c.a.harmIntervals.2); b = Int(c.b.harmIntervals.2)
    }
    let v = (Double(a) + (Double(b) - Double(a)) * t).rounded()
    return max(-24, min(24, Int(v)))
}

@inline(__always)
func effectiveHarmVelScale(_ c: SnapColour, t: Double) -> Double {
    max(0.1, min(1, c.a.harmVelScale + (c.b.harmVelScale - c.a.harmVelScale) * t))
}
