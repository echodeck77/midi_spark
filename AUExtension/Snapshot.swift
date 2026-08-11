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
    var dormant = false        // LADDER: a non-active rung while LADDER mode is on — silent (skipped at the emit
                               // guards, like `muted`) but present/visible; resolved in the builder so the render
                               // thread stays LADDER-unaware. Default false → identical to pre-LADDER behaviour.
    var busMask: UInt8 = 0     // bits 0–3 = A–D (§2.3: the only exits)
    var runStartColumn: Int8 = -1   // LEGATO precompute (§7 v2.4) — UI-thread work, render just reads
    // v3.0 graph routing (delta §1, precomputed here so render never scans):
    var resolvedParent: Int8 = -1   // referenced row IF occupied & ≠ self, else −1 (= MIDI IN)
    var inputChannel: UInt8 = 0     // delta §7: source filter, 0 = OMNI, 1–16 channel, ≥17 = match-nothing
                                    // (a muted receiver; Snap.mutedSourceFilter). Resolved from the cell's
                                    // receiver at build time — MIDI-IN cells only; render just reads it.
    var resolvedReceiver: Int8 = -1 // delta §9 item 11: the receiver a MIDI-IN cell reads (0–3), else −1
    var inputCableMask: UInt8 = 0b1111  // §item 11 INPUT CABLES: the receiver's cable bitmask (ANY = all); render just reads it
    var chordSplit = ChordSplit()   // §cell-edit D: which held source notes this cell takes (ALL default); render reads via srcCount/srcAscending(for:)
    var velFloor: UInt8 = 1         // §cell-edit D VELOCITY WINDOW: admit source notes with velocity in [floor, ceil]
    var velCeil: UInt8 = 127        // (1…127 default = admit all); applied in srcCount/srcAscending(for:) before the split
    var inputRangeLo: UInt8 = 0     // RANGE (§2): the receiver's note WINDOW — admit source notes with note ∈ [lo, hi]
    var inputRangeHi: UInt8 = 127   // (0…127 default = admit all); applied in srcCount/srcAscending(for:) with the vel window
    var chopMain: UInt8 = 0xFF       // §cell-edit F: per-slice → the cell's own emitters (bit i = slice i)
    var chopAlt: UInt8 = 0           // §cell-edit F: per-slice → ALSO the shared ALT destination
    var chopMute: UInt8 = 0          // §cell-edit F: per-slice → silenced (overrides)
    var chopAltMask: UInt8 = 0       // §cell-edit F: the shared ALT destination as a bus bitmask
    var chopActive = false           // fast-path: any slice deviates from all-MAIN
    // CELL MACHINE (feat/EditPageSpike): the resolved processor CHAIN — one SnapParams per slot, head first,
    // resolved from the cell's `processors` (or a 1-slot head from the Colour's A face when the cell has none).
    // `slotBypass[k]` = slot k's true-bypass. Morph is dropped (SnapColour.a/b/tier/morph go dormant). The
    // head-only stage-1 reads `proc` (== procs[0]) and `bypassed` (== slotBypass[0]); stage-2 runs the whole
    // chain in series (Router pipeline) with only the TAIL emitting.
    var procs: [SnapParams] = [SnapParams()]
    var slotBypass: [Bool] = [false]
    var proc: SnapParams { procs.first ?? SnapParams() }   // the head treatment (stage-1 read path)
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
    var strumSpreadNorm: Bool = true // strum: constant-width rake (true) vs per-note gap widening with the pool (false)
    var probability: Double = 1      // chance: pass-through probability 0…1
    var chanceTilt: Double = 0       // chance WEIGHT −1…1 (user 2026-08-11)
    var chanceDensity: Bool = false  // chance CONSTANT-DENSITY (keep ~a constant count regardless of chord size)
    var arpFit: Bool = false         // arp FIT: one pool traversal = one beat (constant cycle)
    var harmIntervals: (Int8, Int8, Int8) = (0, 0, 0)   // harmonize: 3 added-voice intervals (0 = off)
    var harmVelScale: Double = 0.8   // harmonize: velocity scale on added voices
    // ECHO (user 2026-08-08)
    var echoSync: Bool = true
    var echoDelayDiv: Int = 4        // 16th-notes (1…16)
    var echoDelayMs: Double = 250
    var echoRepeats: Int = 3         // 1…16
    var echoOffset: Double = 0       // ±0.33
    var echoFeedDelay: Double = 0.7  // 0…1
    var echoDecay: Double = 0.5      // 0…1 per-echo falloff
    var echoPitch: Int = 0           // semitones per echo
    var echoThru: Bool = true        // THRU vs MUTE
    var echoSpill: EchoSpill = .ring // RING past the bar · CUT inside it · HAND (deferred)
    // EUCLID generator (user 2026-08-08); BURST reuses count+curve, CASCADE reuses rateIndex+strumDir.
    var euclidPulses: Int = 5
    var euclidSteps: Int = 8
    var euclidRot: Int = 0
    var euclidPulsesFromPool: Bool = false   // POOL mode: K = the held-note count
    // THE MOD PROCESSOR (CC generator, delta / CC-stage §1).
    var modCC: Int = 74
    var modSource: ModSource = .shape    // SHAPE · FOLLOW · STEPS · STRIKE · EXTERN
    var modShape: ModShape = .sine       // WAVE
    var modRate: ModRate = .r2           // LFO period (beats/cycle)
    var modMin: Int = 0                  // shape floor  (MIN)
    var modMax: Int = 127                // shape ceiling (MAX); MIN > MAX inverts
    var modReset: Bool = true            // ON LEAVE: reset to MIN on column exit
    var modFollow: ModFollow = .register // FOLLOW: which property
    var modSteps: [Int] = [0, 18, 36, 54, 72, 90, 108, 127]   // STEPS: 8 values 0…127 (default rising staircase)
    var modSmooth: Bool = true           // STEPS: SMOOTH vs STEP
    var modAttack: Double = 0.15         // STRIKE attack (beats)
    var modRelease: Double = 0.6         // STRIKE release (beats)
    var modExternCC: Int = 1             // EXTERN source CC#
    // GLIDE (notes→pitch-bend translator).
    var glideTime: Double = 0.25         // slide duration, beats (0 = instant)
    var glideRange: Int = 2              // ± bend range, semitones
    var glidePriority: GlidePriority = .last
    var glideReanchor: Bool = true       // out-of-range → re-anchor (else clamp)
}

struct SnapColour {
    var transpose: Int8 = 0
    var a = SnapParams()             // the one resolved param bag (A/B morph removed)
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
    let claimMask: UInt8             // delta §6a CLAIM v2: bit i = emitter i claims (SHARED tier); 0 = no claim
    let claimLeak: [UInt8]           // delta §6a CLAIM v2: 4 per-claimant LEAK % (0 = full suppression = v1)
    let flattenMask: UInt8           // emitter role family: bit i = emitter i ducks OTHER emitters while it sounds
    let flattenAmount: [UInt8]       // 4 per-emitter FLATTEN amounts (0…100 %)
    let altMask: UInt8               // emitter role family: the ALT turn-taking group (bits A–D)
    let altCount: [UInt8]            // 4 per-emitter ALT notes-per-turn (1…8)
    let turnsPerNote: Bool           // TURNS mode: true = PER-NOTE exclusive (drop simultaneous); false = PER-MOMENT
    let curveMask: UInt8             // THE RACK CURVE: bit i = emitter i re-maps its output velocity (rack-gated)
    let curveAmount: [Int8]          // 4 per-emitter CURVE amounts (−100…100; 0 = linear, + harder, − softer)
    let fenceMask: UInt8             // THE RACK FENCE: bit i = emitter i applies a note-range policy (rack-gated)
    let fencePolicy: [UInt8]         // 4 per-emitter policies: 0 DROP · 1 CLAMP · 2 FOLD
    let fenceLo: [UInt8]             // 4 per-emitter window lows (0…127)
    let fenceHi: [UInt8]             // 4 per-emitter window highs (0…127)
    let monoMask: UInt8             // THE RACK MONO: bit i = emitter i is monophonic (rack-gated)
    let monoPriority: [UInt8]        // 4 per-emitter priorities: 0 LAST · 1 LOW · 2 HIGH
    let pocketMask: UInt8            // THE RACK POCKET: bit i = emitter i shifts its timing (rack-gated)
    let pocketMs: [Int8]             // 4 per-emitter timing offsets (−50…50 ms; − push, + lay-back)
    let convLead: Int8               // THE RACK CONVERSATION: the LEAD emitter (0–3), or −1 = none
    let convStance: [UInt8]          // 4 per-emitter stances: 0 FREE · 1 WITH · 2 AGAINST (rack-gated to FREE)
    let rackMask: UInt8              // THE RACK (design-the-rack §3): bit i = emitter i's rack is IN the signal path. The builder pre-ANDs this into claimMask/flattenMask/altMask/curveMask above; carried here for future self-affecting treatments (MONO/FENCE) to gate on.
    let masterKey: Int8              // master panel: per-scene master transpose (−12…12), on every output note
    let masterMute: Bool             // master panel: global emission kill
    let thruReceiver: Int8           // receiver strip: the THRU-pip receiver (0–3) passthrough follows (default 0 = R1)
    let receiverChannels: [UInt8]    // delta §9 item 11: the 4 receivers' channel filters (0 = OMNI, 1–16) — input metering
    let receiverCables: [UInt8]      // §item 11 INPUT CABLES: the 4 receivers' cable bitmasks (ANY = 0b1111) — input metering
    let latchAddMask: UInt8          // TWO LATCH MODES: bit i = receiver i latches in ADD (toggle) mode; 0 = CHORD
    let receiverDisabledMask: UInt8  // INPUT ENABLE: bit i = receiver i is DISABLED (not listening) — its frozen latch still feeds the grid, but no new live notes reach its cells
    let receiverRangeLo: [UInt8]     // RANGE (§2): the 4 receivers' note-window low bound (0…127) — for the latch capture (upstream of latch)
    let receiverRangeHi: [UInt8]     // RANGE (§2): the 4 receivers' note-window high bound (0…127)
    let receiverBypassMask: UInt8    // BYPASS (§1/§2): bit i = receiver i bypasses the grid (its stream injects straight to emitters)
    let receiverBypassDest: [UInt8]  // BYPASS: the 4 receivers' destination emitter masks (A–D), default ALL
    let receiverControllerMask: [UInt8]  // CONTROLLER ROUTING (v1): each door's emitters (A–D) it forwards incoming CC/PB/AT/PC to, re-stamped. Default ALL-LIVE.
    let receiverPianoMask: UInt8         // PIANO LATCH: bit i = receiver i's latch reads its on-screen keyboard selection (not live input)
    let receiverPianoNotes: [[UInt8]]    // PIANO LATCH: per-receiver chosen notes (the frozen chord when armed in PIANO mode)
    let macroValues: [Double]        // MACRO MODULATION: the 24 live macro values (0…1), index = macro slot. The derivation reads these; the per-cell targets ride on SnapCell (added with the offset term).

    init(generation: UInt64, stepBeats: Double, swing: Double, morphMaster: Double,
         colours: [SnapColour], cells: [SnapCell], busChannels: [UInt8], busEnabledMask: UInt8 = 0b1111,
         claimMask: UInt8 = 0, claimLeak: [UInt8] = [0, 0, 0, 0],
         flattenMask: UInt8 = 0, flattenAmount: [UInt8] = [0, 0, 0, 0],
         altMask: UInt8 = 0, altCount: [UInt8] = [1, 1, 1, 1], turnsPerNote: Bool = false,
         curveMask: UInt8 = 0, curveAmount: [Int8] = [0, 0, 0, 0],
         fenceMask: UInt8 = 0, fencePolicy: [UInt8] = [0, 0, 0, 0],
         fenceLo: [UInt8] = [0, 0, 0, 0], fenceHi: [UInt8] = [127, 127, 127, 127],
         monoMask: UInt8 = 0, monoPriority: [UInt8] = [0, 0, 0, 0],
         pocketMask: UInt8 = 0, pocketMs: [Int8] = [0, 0, 0, 0],
         convLead: Int8 = -1, convStance: [UInt8] = [0, 0, 0, 0], rackMask: UInt8 = 0b1111,
         masterKey: Int8 = 0, masterMute: Bool = false,
         thruReceiver: Int8 = 0, receiverChannels: [UInt8] = [0, 0, 0, 0],
         receiverCables: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111], latchAddMask: UInt8 = 0,
         receiverDisabledMask: UInt8 = 0,
         receiverRangeLo: [UInt8] = [0, 0, 0, 0], receiverRangeHi: [UInt8] = [127, 127, 127, 127],
         receiverBypassMask: UInt8 = 0, receiverBypassDest: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111],
         receiverControllerMask: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111],
         receiverPianoMask: UInt8 = 0, receiverPianoNotes: [[UInt8]] = [[], [], [], []],
         macroValues: [Double] = Array(repeating: 0, count: 24)) {
        self.generation = generation
        self.stepBeats = stepBeats
        self.swing = swing
        self.morphMaster = morphMaster
        self.colours = colours
        self.cells = cells
        self.busChannels = busChannels
        self.busEnabledMask = busEnabledMask
        self.claimMask = claimMask
        self.claimLeak = claimLeak
        self.flattenMask = flattenMask
        self.flattenAmount = flattenAmount
        self.altMask = altMask
        self.altCount = altCount
        self.turnsPerNote = turnsPerNote
        self.curveMask = curveMask
        self.curveAmount = curveAmount
        self.fenceMask = fenceMask
        self.fencePolicy = fencePolicy
        self.fenceLo = fenceLo
        self.fenceHi = fenceHi
        self.monoMask = monoMask
        self.monoPriority = monoPriority
        self.pocketMask = pocketMask
        self.pocketMs = pocketMs
        self.convLead = convLead
        self.convStance = convStance
        self.rackMask = rackMask
        self.masterKey = masterKey
        self.masterMute = masterMute
        self.thruReceiver = thruReceiver
        self.receiverChannels = receiverChannels
        self.receiverCables = receiverCables
        self.latchAddMask = latchAddMask
        self.receiverDisabledMask = receiverDisabledMask
        self.receiverRangeLo = receiverRangeLo
        self.receiverRangeHi = receiverRangeHi
        self.receiverBypassMask = receiverBypassMask
        self.receiverBypassDest = receiverBypassDest
        self.receiverControllerMask = receiverControllerMask
        self.receiverPianoMask = receiverPianoMask
        self.receiverPianoNotes = receiverPianoNotes
        self.macroValues = macroValues
    }
}

// MARK: - Macro modulation (the offset applier — base ⊕ Σ value×delta, clamped)

/// The continuous params a macro may modulate (raw values are `MacroTarget.param` strings). Append-only.
enum MacroParam: String, CaseIterable { case gate, ramp, spread, curve, velTilt, probability, harmVelScale, modMin, modMax }

/// One resolved modulation on a slot: macro index + which param + the authored A→B delta. Built from the document
/// targets at snapshot time (main thread); folded into the resolved `SnapParams` so every render read path sees it.
struct MacroMod { let macro: Int; let param: MacroParam; let delta: Double }

/// Apply the macro OFFSET to a resolved param bag: for each targeted param, `effective = clamp(base + Σ vₖ×deltaₖ)`
/// — overlaps SUM, then clamp ONCE (the offset law). Returns a COPY; `p` (the base) is never mutated, so identity/
/// seals — which read the document, not this — stay stable, and value 0 ⇒ home (no offset). Clamps match `resolve`.
func applyMacros(_ p: SnapParams, mods: [MacroMod], values: [Double]) -> SnapParams {
    guard !mods.isEmpty else { return p }
    var dGate = 0.0, dRamp = 0.0, dSpread = 0.0, dCurve = 0.0, dTilt = 0.0, dProb = 0.0, dHarm = 0.0, dMin = 0.0, dMax = 0.0
    for m in mods {
        let v = (m.macro >= 0 && m.macro < values.count) ? values[m.macro] : 0
        let off = v * m.delta
        if off == 0 { continue }
        switch m.param {
        case .gate:         dGate += off
        case .ramp:         dRamp += off
        case .spread:       dSpread += off
        case .curve:        dCurve += off
        case .velTilt:      dTilt += off
        case .probability:  dProb += off
        case .harmVelScale: dHarm += off
        case .modMin:       dMin += off
        case .modMax:       dMax += off
        }
    }
    var r = p
    if dGate != 0 { r.gate = clamp(r.gate + dGate, 0.05, 1) }
    if dRamp != 0 { r.ramp = clamp(r.ramp + dRamp, 0, 1) }
    if dSpread != 0 { r.spread = clamp(r.spread + dSpread, 0, 1) }
    if dCurve != 0 { r.curve = clamp(r.curve + dCurve, -1, 1) }
    if dTilt != 0 { r.velTilt = clamp(r.velTilt + dTilt, -1, 1) }
    if dProb != 0 { r.probability = clamp(r.probability + dProb, 0, 1) }
    if dHarm != 0 { r.harmVelScale = clamp(r.harmVelScale + dHarm, 0.1, 1) }
    if dMin != 0 { r.modMin = clamp(r.modMin + Int(dMin.rounded()), 0, 127) }
    if dMax != 0 { r.modMax = clamp(r.modMax + Int(dMax.rounded()), 0, 127) }
    return r
}

// MARK: - Effective params (render-side, §3.2: stepped fields quantize, never glide)

// CELL MACHINE (morph removed): the A/B blend is gone — every effective* reads the single (A) param bag.
// They keep a `t` arg (always 0, ignored) so the render call sites are unchanged; the render feeds them the
// per-cell chain slot via the `treat.a = head` injection SnapColour. (The retired a→b interpolation, tiers,
// and morphMaster #300 are history — Codable fields + the param address stay reserved per CLAUDE.md.)
@inline(__always)
func effectiveType(_ c: SnapColour, t: Double) -> ProcessorType { c.a.type }

@inline(__always)
func effectivePassMask(_ c: SnapColour, t: Double) -> UInt8 { c.a.passMask }

@inline(__always)
func effectiveRateBeats(_ c: SnapColour, t: Double) -> Double {
    Snap.arpRateBeats[max(0, min(Snap.arpRateBeats.count - 1, Int(c.a.rateIndex)))]
}

@inline(__always)
func effectiveGate(_ c: SnapColour, t: Double) -> Double { c.a.gate }

@inline(__always)
func effectiveOctaves(_ c: SnapColour, t: Double) -> Int { max(1, min(4, Int(c.a.octaves))) }

// RATCHET (§3): repeats per step — quantized to a LEGAL count (2/3/4/6/8).
@inline(__always)
func effectiveRepeats(_ c: SnapColour, t: Double) -> Int {
    let v = Double(c.a.count), legal = [2, 3, 4, 6, 8]
    var best = legal[0], bestD = Double.greatestFiniteMagnitude
    for L in legal { let d = abs(Double(L) - v); if d < bestD { bestD = d; best = L } }
    return best
}

@inline(__always)
func effectiveRamp(_ c: SnapColour, t: Double) -> Double { clamp(c.a.ramp, 0, 1) }

@inline(__always)
func effectiveSpread(_ c: SnapColour, t: Double) -> Double { clamp(c.a.spread, 0, 1) }

@inline(__always)
func effectiveProbability(_ c: SnapColour, t: Double) -> Double { clamp(c.a.probability, 0, 1) }

@inline(__always)
func effectiveHarmInterval(_ c: SnapColour, voice: Int, t: Double) -> Int {
    let a: Int
    switch voice {
    case 0: a = Int(c.a.harmIntervals.0)
    case 1: a = Int(c.a.harmIntervals.1)
    default: a = Int(c.a.harmIntervals.2)
    }
    return clamp(a, -24, 24)
}

@inline(__always)
func effectiveHarmVelScale(_ c: SnapColour, t: Double) -> Double { clamp(c.a.harmVelScale, 0.1, 1) }
