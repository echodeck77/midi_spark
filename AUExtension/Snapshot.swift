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
    var colourIndex: Int16 = -1   // CR-13a: Int16 (was Int8) — with the 16-colour cap gone, a document colour index can exceed 127; Int8(index) trapped at ≥128
    var alt = false
    var bypassed = false
    var passthrough = false     // NO-MACHINE chain (Paul 2026-08-23): a LIVE WIRE — its input passes straight through in
                                // realtime via the bypass monitor (reconcileBypass), NOT the grid's step clock; skipped in emitColumnHolds.
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
    var inputChanMask: UInt16 = 0xFFFF   // MULTI-CHANNEL (Paul 2026-08-21): the cell's channel bitmask (bit c = channel c+1); 0xFFFF = OMNI. The render filters on THIS; `inputChannel` above stays for metering/compat.
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
    // `slotBypass[k]` = slot k's true-bypass. (Morph removed — SnapColour carries only the single A face.) The
    // head-only stage-1 reads `proc` (== procs[0]) and `bypassed` (== slotBypass[0]); stage-2 runs the whole
    // chain in series (Router pipeline) with only the TAIL emitting.
    var procs: [SnapParams] = [SnapParams()]
    var slotBypass: [Bool] = [false]
    var proc: SnapParams { procs.first ?? SnapParams() }   // the head treatment (stage-1 read path)
}

// MARK: - Resolved per-state params (the single resolved param bag — the A/B morph layer was removed; paramsB/typeB are decode-only legacy)

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
    var chanceMode: ChanceMode = .single   // CHANCE PATTERN (Paul 2026-08-22 §5): SINGLE = one probability · PATTERN = 8 per-step odds
    var chanceSlices: [Int] = [100, 40, 70, 40, 100, 40, 70, 40]   // PATTERN: per-step odds 0…100%
    var chanceRotate: Int = 0        // PATTERN: rotate the odds figure
    var arpFit: Bool = false         // arp FIT: one pool traversal = one beat (constant cycle)
    var arpOctDown: Bool = false     // OCT DIRECTION: laps descend the octaves (top octave first)
    var arpRandomAnchor: Int = 0     // RANDOM ANCHOR: 0 off · 1 low-first · 2 high-first (RANDOM pattern)
    // EUCLID MASK (SPEC-arp-euclid-mask): resolved. maskK == maskN ⇒ OFF (untouched arp).
    var arpMaskN: Int = 8            // the mask window (steps)
    var arpMaskK: Int = 8            // hits (K of N); K == N ⇒ off
    var arpMaskGap: ArpMaskGap = .rest   // non-hit steps: rest | tie
    var arpMaskWalk: ArpMaskWalk = .march // march (through rests) | wait (advance on hits)
    var arpMaskRotate: Int = 0       // rotate the Bjorklund figure
    var harmIntervals: (Int8, Int8, Int8) = (0, 0, 0)   // harmonize: 3 added-voice intervals (0 = off)
    var harmUnits: PitchUnits = .semitones              // §2: harmonize intervals in semitones or pool degrees
    var utilTransposeUnits: PitchUnits = .semitones     // §2: TRANSPOSE in semitones or pool degrees
    var echoPitchUnits: PitchUnits = .semitones         // §2: ECHO pitch-per-repeat in semitones or pool degrees
    var glideStepUnits: PitchUnits = .semitones         // §2: GLIDE STEP zipper in semitones or pool degrees
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
    var echoRoute: EchoRoute = .direct // DIRECT = echo the final set (v1) · CHAIN = repeats re-fold through post-ECHO stages (§7②)
    // EUCLID generator (user 2026-08-08); BURST reuses count+curve, CASCADE reuses rateIndex+strumDir.
    var euclidPulses: Int = 5
    var euclidSteps: Int = 8
    var euclidRot: Int = 0
    var euclidPulsesFromPool: Bool = false   // POOL mode: K = the held-note count
    var euclidSpan: PatternSpan = .cell      // DEAD (WIDTH model) — decode-only legacy
    var euclidRateBeats: Double = 0.25       // GRID: the step grain (resolved from euclidRate; 1/16 = 0.25 beat)
    var euclidSpanN: Int = 0                  // SPAN re-anchor: 0 = FREE (free-run) · >0 = re-sync the pattern every N columns
    var euclidPick: EuclidPick = .all        // what each hit strikes: ALL | CYCLE (walk) | LOW | HIGH | RANDOM (Paul 2026-08-22)
    var euclidInvert: Bool = false           // play the N−K rests instead (the anti-pattern) — Paul 2026-08-22
    var euclidLines: [EuclidLine] = []       // EUCLID LINES (§10): up to 8 lines; EMPTY ⇒ the single euclid above (byte-identical)
    var burstSpan: PatternSpan = .cell       // BURST: CELL = per-column roll · ROW = the roll unfolds across the bar (Paul 2026-08-19)
    var burstSpanN: Int = 1                   // SPAN LADDER (Paul 2026-08-22): span width in columns
    var burstMode: BurstMode = .once         // BURST family: ONCE (today) · COIN · PATTERN (Paul 2026-08-19)
    var burstSlices: [BurstSlice] = [.burst, .carry, .carry, .rest, .burst, .rest, .rest, .rest]   // PATTERN: 8 slices (B/C/R)
    var burstRotate: Int = 0                 // PATTERN: rotate the slice figure
    var burstChance: Double = 0.5            // COIN: seeded chance-of-burst per step
    var burstRateBeats: Double = ArpRate.r1_8.beats   // RATE AXIS (Paul 2026-08-26): PATTERN slice WIDTH when burstRateOn
    var burstRateOn: Bool = false            // RATE AXIS: divide the span by burstRate (walking the 8-figure) vs the legacy fixed-8
    var cascadeSpan: PatternSpan = .cell     // CASCADE: CELL = per-column reveal · ROW = the reveal spans the bar (Paul 2026-08-19)
    var cascadeSpanN: Int = 0                // SPAN LADDER (RATE×ladder): 0 = legacy CELL|ROW · >0 = the reveal window in columns
    // THE MOD PROCESSOR (CC generator, delta / CC-stage §1).
    var modCC: Int = 74
    var modSource: ModSource = .shape    // SHAPE · FOLLOW · STEPS · STRIKE · EXTERN
    var modShape: ModShape = .sine       // WAVE
    var modRate: ModRate = .r2           // LFO period (beats/cycle)
    var modSpan: PatternSpan = .cell     // SHAPE: CELL = the modRate period · ROW = one cycle spans the whole bar (Paul 2026-08-19)
    var modStepSpan: ModStepSpan = .period   // STEPS: PERIOD (rate period) · ROW · ROW×2 · ROW×4 — the resolved box carries `modSteps.count` = 8/16/32 (Paul 2026-08-20)
    var modMin: Int = 0                  // shape floor  (MIN)
    var modMax: Int = 127                // shape ceiling (MAX); MIN > MAX inverts
    var modReset: Bool = true            // ON LEAVE: reset to MIN on column exit
    var modTarget: ModTarget = .cc       // SEND: CC (emit, default) · CHAIN (modulate a chain param INTERNALLY, no CC) — Paul 2026-08-20
    var modChainParam: MacroParam = .gate    // CHAIN target: which param the internal offset lands on
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
    var glideReanchor: Bool = true       // out-of-range → re-anchor (else clamp) — BEND only
    var glideMode: GlideMode = .bend     // BEND | SYNTH | STEP (Paul 2026-08-22)
    // TUTTI (set-level chance). COIN uses balance+pick; PATTERN slice fields land in phase 2.
    var tuttiMode: TuttiMode = .coin
    var tuttiBalance: Double = 0.5       // COIN: P(TUTTI) per step, 0…1
    var tuttiPick: TuttiPick = .low      // COIN: which rank a SOLO step keeps
    var tuttiSlices: [TuttiSlice] = [.all, .all, .all, .all, .all, .all, .all, .all]  // PATTERN: 8 authored slice shapes
    var tuttiSliceBeats: Double = 0.5    // PATTERN: slice width in beats (from tuttiRate)
    var tuttiRotate: Int = 0             // PATTERN: rotate the 8-slice pattern along the bar (0…7)
    var tuttiSpan: PatternSpan = .cell   // PATTERN: CELL = the RATE stride · ROW = the 8 slices span the whole bar (Paul 2026-08-19)
    var tuttiSpanN: Int = 0              // SPAN LADDER (RATE×ladder): 0 = LEGACY CELL|ROW path · >0 = the loop period in columns (RATE stays the slice width)
    // LENGTH — 8 slices of the STEP, each PASS/MUTE/SHORT/LONG, + two gate lengths + rotate.
    var lenSlices: [LenState] = [.pass, .pass, .pass, .pass, .pass, .pass, .pass, .pass]
    var lenShort: Double = 0.4           // SHORT gate = 5…95% of one slice
    var lenLong: Double = 0.7            // LONG length 0…1 → 25% of a slice … the step end
    var lenRotate: Int = 0               // rotate the slice pattern (0…7)
    var lenSpan: PatternSpan = .cell     // CELL = per-column · ROW = the 8 slices span the whole bar (Paul 2026-08-19)
    var lenSpanN: Int = 1                // SPAN LADDER (Paul 2026-08-22): span width in columns
    // WEAVE — the rank-clocked polyrhythm driver. GATE is the shared `gate` field above.
    var weaveMode: WeaveMode = .ladder
    var weaveBaseBeats: Double = 1.0     // the slowest/bass clock in beats (1/4 = 1 beat)
    var weaveSpan: Int = 4               // ranks that weave; extras join the top clock
    var weavePhase: ArpPhase = .retrig   // clock origin: RETRIG (per step) · FREE (grid) · LEGATO (from the run's start)
    var weaveDrawnBeats: [Double] = [2, 1, 0.5, 0.5, 0.5, 0.5, 0.5, 0.5]   // DRAWN: resolved per-rank tick beats (0…7)
    var weaveEuclidSteps: Int = 8        // EUCLID: cycle length M
    // SPLIT — a set-membership filter (chord-split + velocity window).
    var splitSet = ChordSplit()
    var splitVel = VelWindow()
    // RATCHET MODE — ALL uses count/ramp above; COIN/PATTERN below.
    var rtcMode: RatchetMode = .all
    var rtcChance: Double = 0.5
    var rtcCountLo: Int = 2
    var rtcCountHi: Int = 4
    var rtcSizeWeights: [Int] = []   // COIN ① (Paul 2026-08-26): weights for 2·3·4·6·8; EMPTY ⇒ fall back to LO/HI (byte-identical)
    var rtcGap: Int = 0              // COIN ② refire gap (0 = off) · ③ quota (0 = FREE) · ④ odds-from-velocity
    var rtcQuota: Int = 0
    var rtcOddsVel: Bool = false
    var rtcSlices: [Int] = [2, 0, 2, 0, 2, 0, 2, 0]   // PATTERN: per-slice counts (0 = plain)
    var rtcRateBeats: Double = 0.5                    // PATTERN: slice width in beats (from rtcRate)
    var rtcRotate: Int = 0
    var rtcSpan: PatternSpan = .cell                 // PATTERN: CELL = the RATE stride · ROW = the 8 slices span the whole bar (Paul 2026-08-19)
    var rtcSpanN: Int = 0                            // SPAN LADDER (RATE×ladder): 0 = legacy CELL|ROW · >0 = the loop period in columns
    var utilOctave: Int = 0                           // OCTAVE: ±3 octave shift (UTILITY, Paul 2026-08-22)
    var utilTranspose: Int = 0                        // TRANSPOSE: ±24 semitone shift
    var utilChannel: Int = 0                          // CHANNEL: 0 = WIRE (bus stamp) · 1–16 = output-channel override
    var utilNudge: Int = 0                            // NUDGE: time offset in sixteenths (−8…+8)
    var utilNudgeMode: NudgeMode = .fixed            // TIMING LANE (Paul 2026-08-22 §5): FIXED = one offset · LANE = a per-column pocket
    var utilNudgeLane: [Int] = [0, 0, 0, 0, 0, 0, 0, 0]   // LANE: 8 per-step offsets (−8…+8), the cell's COLUMN picks the slot
    var destSlices: [Int] = [0, 1, 2, 3, 0, 1, 2, 3]      // DEST MATRIX (Paul 2026-08-22 §5): per-onset-slice emitter (0=A…3=D), the hocket
    var muteSlices: [Int] = [0, 0, 0, 0, 0, 0, 0, 0]      // MUTE MATRIX (Paul 2026-08-25 §5): per-onset-slice MUTED-emitter mask (bit i = emitter i muted); 0 ⇒ nothing muted
    // RIFF (SPEC-riff-processor): the resolved stencil. riffRanks defaults to a musical figure so a fresh RIFF plays.
    var riffSteps: Int = 16
    var riffPoly: Bool = false                           // POLY: a step strikes the riffMask rank set (chord-following); MONO uses riffRanks
    var riffMask: [Int] = []                             // POLY per-step 8-bit rank mask (empty ⇒ all rest)
    var riffRateBeats: Double = 0.25                     // resolved from riffRate (1/16 = 0.25 beat)
    var riffRanks: [Int] = [1, 2, 3, 0, 2, 3, 4, 0, 1, 2, 3, 0, 5, 4, 3, 0]   // 0 = REST · 1–8 = pool rank (the default figure)
    var riffOct: [Int] = []                              // per-step −1·0·+1 (empty ⇒ all 0)
    var riffAccent: [Int] = []                           // per-step velocity accent (empty ⇒ none)
    var riffTie: [Bool] = []                             // per-step tie (empty ⇒ none)
    var riffSlide: [Bool] = []                           // per-step slide (empty ⇒ none)
    var riffWrap: RiffWrap = .fold
    var riffSpanN: Int = 0                               // SPAN re-anchor: 0 = FREE (free-run, today) · >0 = re-sync the stencil every N columns
    var strikePerSpan: Bool = false                      // STRIKE PER SPAN (Paul 2026-08-27): a DRONE re-articulates only at each span origin, holds between
    var strikeSpanN: Int = 8                             // the re-articulation cadence in columns (spanLadder, ≥1); 8 = once per row lap
    // HOCKET (AcceptanceCriteria-hocket-processor, v1): the wire-listening driver.
    var hocketSource: Int = 0                             // 0…3 = the listened emitter (wire A–D)
    var hocketMode: HocketMode = .gaps
    var hocketRateBeats: Double = 0.5                     // resolved from hocketRate (1/8 = 0.5 beat) — the decision tick grid
    // TAP (AcceptanceCriteria-tap-processor): the mid-chain send.
    var tapLevel: Double = 1.0
    var tapTo: Int = 0                                    // 0 = THIS WIRE · 1–4 = emitter A–D
    var tapMute: Bool = false
}

struct SnapColour {
    var transpose: Int8 = 0
    var a = SnapParams()             // the one resolved param bag (A/B morph removed)
    var on = OnConfig()              // delta §9 item 1: the resolved ON assignments (arrive/scene = derivations,
    var hue: UInt32 = 0              // the DISPLAY hue (packed RGB) — carried so the render can tag emitted notes with their colour (the reel piano roll paints each note its cell's colour). 0 = unknown ⇒ UI falls back.
}                                    // tap/hold = ephemeral gestures); render reads it precomputed here.

// FILE (config-sheets stage 4): a loaded .mid clip carried in the box (immutable → race-safe hand-off to the render
// thread). Parallel arrays of the decoded note events + the loop length in beats. loopBeats == 0 ⇒ no clip. (Paul 2026-08-20)
struct SnapFileClip: Equatable {
    var beats: [Double] = []
    var notes: [UInt8] = []
    var vels: [UInt8] = []
    var ons: [Bool] = []
    var loopBeats: Double = 0
}

// MARK: - The box: immutable after construction → safe concurrent reads, no locks

final class SnapshotBox {
    let generation: UInt64           // increments per publish; render clears param overrides on change
    let stepBeats: Double
    let swing: Double                // 50…75 (§4 v2.3)
    let morphMaster: Double          // §13.5, parameter #35
    let colours: [SnapColour]        // ≥16 — sized to the document (BUILD ephemeral colours append beyond the 16)
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
    let receiverChannelMask: [UInt16]  // MULTI-CHANNEL (Paul 2026-08-21): the 4 receivers' channel SUBSET masks (bit c = channel c+1; 0xFFFF = OMNI, 0 = none) — the door's own admission (metering + latch capture)
    let receiverCables: [UInt8]      // §item 11 INPUT CABLES: the 4 receivers' cable bitmasks (ANY = 0b1111) — input metering
    let latchAddMask: UInt8          // TWO LATCH MODES: bit i = receiver i latches in ADD (toggle) mode; 0 = CHORD
    let receiverDisabledMask: UInt8  // INPUT ENABLE: bit i = receiver i is DISABLED (not listening) — its frozen latch still feeds the grid, but no new live notes reach its cells
    let receiverRangeLo: [UInt8]     // RANGE (§2): the 4 receivers' note-window low bound (0…127) — for the latch capture (upstream of latch)
    let receiverRangeHi: [UInt8]     // RANGE (§2): the 4 receivers' note-window high bound (0…127)
    let passEmitterMask: [UInt8]     // NO-MACHINE WIRE (Paul 2026-08-23): per door, the UNION of empty-chain (passthrough) cells' emitters — their input passes straight through in realtime via reconcileBypass (like bypass, but per-cell)
    let receiverControllerMask: [UInt8]  // CONTROLLER ROUTING (v1): each door's emitters (A–D) it forwards incoming CC/PB/AT/PC to, re-stamped. Default ALL-LIVE.
    let receiverPianoMask: UInt8         // PIANO LATCH: bit i = receiver i's latch reads its on-screen keyboard selection (not live input)
    let receiverPianoNotes: [[UInt8]]    // PIANO LATCH: per-receiver chosen notes (the frozen chord when armed in PIANO mode)
    let receiverExcludeDoor: [Int8]      // KEY FILTER (Paul 2026-08-22): per door, the reference door (0–3) whose pitch classes filter this door's pool (-1 = OFF)
    let receiverExcludeOnly: UInt8       // KEY FILTER §3: bit i = door i INTERSECTS (ONLY / in-key) the reference vs subtracts it (MINUS / complement — the default)
    let receiverExcludeSnap: UInt8       // KEY FILTER §3: bit i = door i SNAPS out-of-set notes to the nearest legal note vs BLOCKs them (silence — the default)
    let receiverReplayMask: UInt8        // REPLAY (config-sheets stage 3): bit i = receiver i is in REPLAY mode (its input ring loops as living input)
    let receiverReplayPasses: [UInt8]    // REPLAY: per-receiver history length in passes (1·2·4·8) that loops
    let receiverFile: [SnapFileClip]     // FILE (config-sheets stage 4): per-door loaded .mid clip that loops as input (empty = none)
    let macroValues: [Double]        // MACRO MODULATION: the 24 live macro values (0…1), index = macro slot. The derivation reads these; the per-cell targets ride on SnapCell (added with the offset term).
    // PER-PART CLOCK (Paul 2026-08-19): the raw per-row step/len arrive as init params + are resolved below; only the
    // RESOLVED arrays are stored (the raw ones were write-only dead — removed 2026-08-25 housekeeping).
    let rowStep: [Double]            // RESOLVED per-row step (always Snap.rows long; falls back to `stepBeats`) — what the render reads
    let rowLength: [Int]             // RESOLVED per-row loop length (always Snap.rows long; falls back to Snap.cols) — what the render reads
    let rowLaneMask: [UInt8]         // PER-ROW LAP (Paul 2026-08-19): per-row column-loop mask; empty ⇒ use the EPHEMERAL global lap (laneMask) for every row (GRID tab = today). Non-empty (count Snap.rows) ⇒ each row laps its OWN columns (0 = no loop) — so the BUILD staging + perform grids loop independently.
    // ROW 8 (Paul 2026-08-22): FREEZE + HALFTIME are toggle cells whose LIT state is scene-captured, so they flow through
    // the box (no ephemeral channel). freezeActive = any lit FREEZE cell (sustain sounding notes + pause derivation).
    // clockScale = the play-grid clock multiplier from a lit HALFTIME cell (÷2 ⇒ 2.0 = steps twice as long · ×2 ⇒ 0.5 · ×1/none ⇒ 1.0).
    let freezeActive: Bool
    let clockScale: Double
    let busRemap: [UInt8]            // ROW 8 REDIRECT/SWAP: per-bus output-wire remap (default [0,1,2,3] = no redirect). A lit REDIRECT A→B sets [A]=B; a lit SWAP A↔B sets [A]=B,[B]=A. Applied at the emission stamp (cable+channel).
    let broadcastActive: Bool        // ROW 8 BROADCAST: while lit, every emitted note MIRRORS to ALL 4 emitter wires (the wall) — a per-note fan-out at the emission boundary.
    let broadcastAll16: Bool         // ROW 8 BROADCAST all-16 (Paul 2026-08-26): the ALL-cable copy also fans across every MIDI channel (a multitimbral wall).

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
         receiverChannelMask: [UInt16] = [0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF],
         receiverCables: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111], latchAddMask: UInt8 = 0,
         receiverDisabledMask: UInt8 = 0,
         receiverRangeLo: [UInt8] = [0, 0, 0, 0], receiverRangeHi: [UInt8] = [127, 127, 127, 127],
         passEmitterMask: [UInt8] = [0, 0, 0, 0],
         receiverControllerMask: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111],
         receiverPianoMask: UInt8 = 0, receiverPianoNotes: [[UInt8]] = [[], [], [], []],
         receiverExcludeDoor: [Int8] = [-1, -1, -1, -1], receiverExcludeOnly: UInt8 = 0, receiverExcludeSnap: UInt8 = 0,
         receiverReplayMask: UInt8 = 0, receiverReplayPasses: [UInt8] = [1, 1, 1, 1],
         receiverFile: [SnapFileClip] = [SnapFileClip(), SnapFileClip(), SnapFileClip(), SnapFileClip()],
         macroValues: [Double] = Array(repeating: 0, count: 24),
         rowStepBeats: [Double] = [], rowLen: [Int] = [], rowLaneMask: [UInt8] = [],
         freezeActive: Bool = false, clockScale: Double = 1.0, busRemap: [UInt8] = [0, 1, 2, 3],
         broadcastActive: Bool = false, broadcastAll16: Bool = false) {
        self.freezeActive = freezeActive
        self.clockScale = clockScale
        self.busRemap = busRemap
        self.broadcastActive = broadcastActive
        self.broadcastAll16 = broadcastAll16
        self.rowLaneMask = rowLaneMask
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
        self.receiverChannelMask = receiverChannelMask
        self.receiverCables = receiverCables
        self.latchAddMask = latchAddMask
        self.receiverDisabledMask = receiverDisabledMask
        self.receiverRangeLo = receiverRangeLo
        self.receiverRangeHi = receiverRangeHi
        self.passEmitterMask = passEmitterMask
        self.receiverControllerMask = receiverControllerMask
        self.receiverPianoMask = receiverPianoMask
        self.receiverPianoNotes = receiverPianoNotes
        self.receiverExcludeDoor = receiverExcludeDoor
        self.receiverExcludeOnly = receiverExcludeOnly
        self.receiverExcludeSnap = receiverExcludeSnap
        self.receiverReplayMask = receiverReplayMask
        self.receiverReplayPasses = receiverReplayPasses
        self.receiverFile = receiverFile
        self.macroValues = macroValues
        // PER-PART CLOCK helpers: resolve a row's step + loop length, falling back to the global values (uniform = today).
        func resolvedStep(_ r: Int) -> Double { (r >= 0 && r < rowStepBeats.count && rowStepBeats[r] > 0) ? rowStepBeats[r] : stepBeats }
        func resolvedLen(_ r: Int) -> Int { (r >= 0 && r < rowLen.count && rowLen[r] >= 1) ? min(Snap.cols, rowLen[r]) : Snap.cols }
        self.rowStep = (0..<Snap.rows).map(resolvedStep)
        self.rowLength = (0..<Snap.rows).map(resolvedLen)
    }
}

// MARK: - Macro modulation (the offset applier — base ⊕ Σ value×delta, clamped)

/// The continuous params a macro may modulate (raw values are `MacroTarget.param` strings). Append-only.
enum MacroParam: String, CaseIterable, Codable { case gate, ramp, spread, curve, velTilt, probability, harmVelScale, modMin, modMax, tuttiBalance, lenShort, lenLong, rtcChance }

/// One resolved modulation on a slot: macro index + which param + the authored A→B delta. Built from the document
/// targets at snapshot time (main thread); folded into the resolved `SnapParams` so every render read path sees it.
struct MacroMod { let macro: Int; let param: MacroParam; let delta: Double }

/// Apply the macro OFFSET to a resolved param bag: for each targeted param, `effective = clamp(base + Σ vₖ×deltaₖ)`
/// — overlaps SUM, then clamp ONCE (the offset law). Returns a COPY; `p` (the base) is never mutated, so identity/
/// seals — which read the document, not this — stay stable, and value 0 ⇒ home (no offset). Clamps match `resolve`.
func applyMacros(_ p: SnapParams, mods: [MacroMod], values: [Double]) -> SnapParams {
    guard !mods.isEmpty else { return p }
    var dGate = 0.0, dRamp = 0.0, dSpread = 0.0, dCurve = 0.0, dTilt = 0.0, dProb = 0.0, dHarm = 0.0, dMin = 0.0, dMax = 0.0, dTutti = 0.0, dLenS = 0.0, dLenL = 0.0, dRtc = 0.0
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
        case .tuttiBalance: dTutti += off
        case .lenShort:     dLenS += off
        case .lenLong:      dLenL += off
        case .rtcChance:    dRtc += off
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
    if dTutti != 0 { r.tuttiBalance = clamp(r.tuttiBalance + dTutti, 0, 1) }   // live-automatable SOLO↔TUTTI
    if dLenS != 0 { r.lenShort = clamp(r.lenShort + dLenS, 0.05, 0.95) }
    if dLenL != 0 { r.lenLong = clamp(r.lenLong + dLenL, 0, 1) }
    if dRtc != 0 { r.rtcChance = clamp(r.rtcChance + dRtc, 0, 1) }   // live-automatable ratchet density (COIN)
    return r
}

// MOD §2 INTERNAL TARGET (Paul 2026-08-20): the modulated range of each foldable param — the offset the MOD writes is
// (its MIN/MAX-ranged unipolar value) × this span, so a full MIN..MAX sweep can traverse the param's whole range.
func macroParamSpan(_ param: MacroParam) -> Double {
    switch param {
    case .curve, .velTilt:            return 2.0    // −1…1
    case .modMin, .modMax:            return 127.0  // 0…127
    case .harmVelScale, .lenShort:    return 0.9    // 0.1…1 · 0.05…0.95
    default:                          return 1.0    // 0…1 (gate/ramp/spread/probability/tuttiBalance/lenLong/rtcChance)
    }
}
// Add `offset` to `param`'s base, clamped to the param's valid range (same clamps as applyMacros — MOD + macros compose
// on this one lane). Used by the render-time internal-MOD application (Router.applyInternalMods).
func applyModChainOffset(_ p: SnapParams, param: MacroParam, offset: Double) -> SnapParams {
    guard offset != 0 else { return p }
    var r = p
    switch param {
    case .gate:         r.gate = clamp(r.gate + offset, 0.05, 1)
    case .ramp:         r.ramp = clamp(r.ramp + offset, 0, 1)
    case .spread:       r.spread = clamp(r.spread + offset, 0, 1)
    case .curve:        r.curve = clamp(r.curve + offset, -1, 1)
    case .velTilt:      r.velTilt = clamp(r.velTilt + offset, -1, 1)
    case .probability:  r.probability = clamp(r.probability + offset, 0, 1)
    case .harmVelScale: r.harmVelScale = clamp(r.harmVelScale + offset, 0.1, 1)
    case .modMin:       r.modMin = clamp(r.modMin + Int(offset.rounded()), 0, 127)
    case .modMax:       r.modMax = clamp(r.modMax + Int(offset.rounded()), 0, 127)
    case .tuttiBalance: r.tuttiBalance = clamp(r.tuttiBalance + offset, 0, 1)
    case .lenShort:     r.lenShort = clamp(r.lenShort + offset, 0.05, 0.95)
    case .lenLong:      r.lenLong = clamp(r.lenLong + offset, 0, 1)
    case .rtcChance:    r.rtcChance = clamp(r.rtcChance + offset, 0, 1)
    }
    return r
}

// MARK: - Effective params (render-side, §3.2: stepped fields quantize, never glide)

// CELL MACHINE (morph removed): the A/B blend is gone — every effective* reads the single (A) param bag.
// They keep a `t` arg (always 0, ignored) so the render call sites are unchanged; the render feeds them the
// per-cell chain slot via the `treat.a = head` injection SnapColour. (The retired a→b interpolation, tiers,
// and morphMaster #300 are history — Codable fields + the param address stay reserved per CLAUDE.md.)
@inline(__always)
func effectiveType(_ c: SnapColour) -> ProcessorType { c.a.type }

@inline(__always)
func effectivePassMask(_ c: SnapColour) -> UInt8 { c.a.passMask }

@inline(__always)
func effectiveRateBeats(_ c: SnapColour) -> Double {
    Snap.arpRateBeats[max(0, min(Snap.arpRateBeats.count - 1, Int(c.a.rateIndex)))]
}

@inline(__always)
func effectiveGate(_ c: SnapColour) -> Double { c.a.gate }

@inline(__always)
func effectiveOctaves(_ c: SnapColour) -> Int { max(1, min(4, Int(c.a.octaves))) }

// RATCHET (§3): repeats per step — quantized to a LEGAL count (2/3/4/6/8).
@inline(__always)
func effectiveRepeats(_ c: SnapColour) -> Int {
    let v = Double(c.a.count), legal = [2, 3, 4, 6, 8]
    var best = legal[0], bestD = Double.greatestFiniteMagnitude
    for L in legal { let d = abs(Double(L) - v); if d < bestD { bestD = d; best = L } }
    return best
}

@inline(__always)
func effectiveRamp(_ c: SnapColour) -> Double { clamp(c.a.ramp, 0, 1) }

@inline(__always)
func effectiveSpread(_ c: SnapColour) -> Double { clamp(c.a.spread, 0, 1) }

@inline(__always)
// CHANCE PATTERN (Paul 2026-08-22 §5): SINGLE returns the one probability; PATTERN returns the odds for the given STEP
// (the column index; the 8-slice figure, rotated). Beat-derived + replay-safe via chancePasses. `step` defaults to 0
// (the SINGLE path + audition ignore it).
func effectiveProbability(_ a: SnapParams, step: Int = 0) -> Double {
    if a.chanceMode == .pattern {
        let i = (((step + a.chanceRotate) % 8) + 8) % 8
        let v = i < a.chanceSlices.count ? a.chanceSlices[i] : 100
        return clamp(Double(v) / 100.0, 0, 1)
    }
    return clamp(a.probability, 0, 1)
}

@inline(__always)
func effectiveHarmInterval(_ c: SnapColour, voice: Int) -> Int {
    let a: Int
    switch voice {
    case 0: a = Int(c.a.harmIntervals.0)
    case 1: a = Int(c.a.harmIntervals.1)
    default: a = Int(c.a.harmIntervals.2)
    }
    return clamp(a, -24, 24)
}

@inline(__always)
func effectiveHarmVelScale(_ c: SnapColour) -> Double { clamp(c.a.harmVelScale, 0.1, 1) }
