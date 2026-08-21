//  Models.swift
//  MidiSpark — document model per spec v2.8 §9.
//  Colour = the treatment · Cell = the patch point · Preset = host fullState (reserved word).

import Foundation

// MARK: - Vocabulary

enum ProcessorType: String, Codable, CaseIterable {
    case arp = "ARP", ratchet = "RATCHET", passgate = "PASSGATE"
    case strum = "STRUM", chance = "CHANCE", harmonize = "HARMONIZE"
    case echo = "ECHO"   // the first TAIL stage — repeats a note at delayed beats (reuses rate=TIME · count=REPEATS · ramp=DECAY)
    case euclid = "EUCLID"     // GENERATOR — a K-of-N euclidean rhythm; strikes the chord on the evenly-spread pulses
    case burst = "BURST"       // GENERATOR — a one-shot accel/decel roll at step entry (reuses count · curve)
    case cascade = "CASCADE"   // GENERATOR — reveal the chord's notes one at a time, each held to the boundary (reuses rate · strumDir)
    case drone = "DRONE"       // GENERATOR — a flat sustained PAD: the entry chord held to the boundary (reuses gate = pad level)
    case shift = "SHIFT"       // GENERATOR — a groove NUDGE: push the chord's onset late (reuses spread = push amount)
    case humanize = "HUMANIZE" // GENERATOR — seeded per-note timing + velocity jitter, replay-safe (reuses spread = amount)
    case mod = "MOD"           // CC GENERATOR (delta "THE MOD PROCESSOR") — a beat-derived shaped CC on the cell's emitters; sounds NO notes
    case glide = "GLIDE"       // notes→PITCH-BEND translator — one mono sliding voice; steps GLIDE, leaps ARTICULATE
    case tutti = "TUTTI"       // SET-level chance (CHANCE's cousin): per step SOLO (one note) or TUTTI (the full set); a HOLD transform, never a driver
    case length = "LENGTH"     // per-slice GATE override (DURATION axis; CHOP routes · LENGTH shapes): PASS/MUTE/SHORT/LONG across 8 slices
    case weave = "WEAVE"       // rank-clocked polyrhythm DRIVER: each held note ticks on its own rank-derived clock (one chord → an interlocking ensemble)
    case split = "SPLIT"       // set-membership filter: keep a subset of the chord (TOP/BOTTOM n · RANGE · vel window). Re-pools before a driver, punches holes after one
    // §12: type IDs are append-only. Never reorder, never reuse.
}

// THE MOD PROCESSOR (delta · CC-stage §1 WAVE): the shape of the generated CC. SINE smooth · TRI symmetric ramp ·
// SQR on/off · RAMP rising saw · S&H stepped seeded-per-cycle random (replay-safe). §12: append-only (never reorder).
enum ModShape: String, Codable, CaseIterable { case sine = "SINE", triangle = "TRI", square = "SQR", ramp = "RAMP", sampleHold = "S&H" }
// CC-stage §1 RATE — the LFO PERIOD in BEATS per cycle (musical, slow↔fast). Its own type (the arp rate capped at
// ≤1 beat, too fast for sweeps). §12: append-only.
enum ModRate: String, Codable, CaseIterable {
    case r1_8 = "1/8", r1_4 = "1/4", r1_2 = "1/2", r1 = "1", r2 = "2", r4 = "4", r8 = "8", r16 = "16", r32 = "32"
    var periodBeats: Double {
        switch self { case .r1_8: 0.125; case .r1_4: 0.25; case .r1_2: 0.5; case .r1: 1; case .r2: 2; case .r4: 4; case .r8: 8; case .r16: 16; case .r32: 32 }
    }
}
// CC-stage §1 SOURCE — the stage's spine. SHAPE = an LFO · FOLLOW = tracks the sounding material · STEPS = an
// 8-step pattern · STRIKE = a per-entry AR envelope · EXTERN = re-emits an incoming CC, transformed. §12 append-only.
enum ModSource: String, Codable, CaseIterable { case shape = "SHAPE", follow = "FOLLOW", steps = "STEPS", strike = "STRIKE", extern = "EXTERN" }
// MOD TARGET (Paul 2026-08-20): CC = emit a MIDI CC (today) · CHAIN = modulate a chain param INTERNALLY (no CC), writing
// the param's offset lane — MOD composes with macros on the same lane. `modChainParam` = which param (the macro list).
enum ModTarget: String, Codable, CaseIterable { case cc = "CC", chain = "CHAIN" }
// FOLLOW — WHICH property of the sounding material drives the CC. §12 append-only.
enum ModFollow: String, Codable, CaseIterable { case density = "DENSITY", register = "REGISTER", count = "COUNT", vel = "VEL" }
// GLIDE — which held note the mono voice tracks when several sound at once. §12 append-only.
enum GlidePriority: String, Codable, CaseIterable { case last = "LAST", low = "LOW", high = "HIGH" }
enum ArpPattern: String, Codable, CaseIterable { case up = "UP", down = "DOWN", upDown = "UP-DN", random = "RANDOM", asPlayed = "AS PLAYED" }
enum ArpPhase: String, Codable, CaseIterable { case retrig = "RETRIG", legato = "LEGATO", free = "FREE" }   // §3.5
// SPAN — the timeline a pattern-based processor runs on (Paul 2026-08-18): CELL restarts the pattern each column
// (N steps = one column); ROW stretches the SAME N steps across the whole 8-column bar (a cross-column phrase). The
// column gate makes each cell voice only the pulses landing in its own column. Shared across EUCLID/LENGTH/TUTTI/… .
enum PatternSpan: String, Codable, CaseIterable { case cell = "CELL", row = "ROW" }
// MOD STEPS span (Paul 2026-08-20): PERIOD = today (8 steps over the modRate period) · ROW = 8 steps over the bar ·
// ROW×2 / ROW×4 = 16 / 32 breakpoints across 2 / 4 bars (the sequence longer than the row). `stepCount` = the # of
// breakpoints; `barMultiple` = how many bars the sequence spans (period → 1, but it uses the rate period, not the bar).
enum ModStepSpan: String, Codable, CaseIterable {
    case period = "PERIOD", row = "ROW", row2 = "ROW×2", row4 = "ROW×4"
    var stepCount: Int { switch self { case .period, .row: return 8; case .row2: return 16; case .row4: return 32 } }
    var barMultiple: Int { switch self { case .row2: return 2; case .row4: return 4; default: return 1 } }
}
enum StepRate: String, Codable, CaseIterable {
    case r2_1 = "2/1", r1_1 = "1/1", r1_2 = "1/2", r1_2d = "1/2.", r1_4 = "1/4", r1_8 = "1/8"
    var beats: Double {
        switch self { case .r2_1: 8; case .r1_1: 4; case .r1_2: 2; case .r1_2d: 3; case .r1_4: 1; case .r1_8: 0.5 }
    }
}
enum ArpRate: String, Codable, CaseIterable {
    case r1_4 = "1/4", r1_8 = "1/8", r1_8t = "1/8T", r1_16 = "1/16", r1_16t = "1/16T", r1_32 = "1/32"
    var beats: Double {
        switch self { case .r1_4: 1; case .r1_8: 0.5; case .r1_8t: 1.0/3.0; case .r1_16: 0.25; case .r1_16t: 1.0/6.0; case .r1_32: 0.125 }
    }
}
enum Bus: String, Codable, CaseIterable { case a = "A", b = "B", c = "C", d = "D"
    var cable: UInt8 { UInt8(Bus.allCases.firstIndex(of: self)!) }
}
/// Pack a set/list of buses into the per-cable bitmask (bit i = cable i). One place so the builder's bus/chop-alt
/// mask packing can't drift. Pure.
@inline(__always) func busBitmask<S: Sequence>(_ buses: S) -> UInt8 where S.Element == Bus { buses.reduce(0) { $0 | (1 << $1.cable) } }
enum StrumDir: String, Codable, CaseIterable { case up = "UP", down = "DOWN", alternate = "ALT" }   // §3 STRUM
enum TapAction: String, Codable, CaseIterable {
    case alt = "ALT", byp = "BYP", mute = "MUTE"
}
enum Quant: String, Codable { case off = "OFF", step = "STEP", pass = "PASS" }                              // §6.8
// TUTTI (working name; Paul 2026-08-13) — set-level chance, CHANCE's correlated cousin. MODE = COIN | PATTERN.
enum TuttiMode: String, Codable, CaseIterable { case coin = "COIN", pattern = "PATTERN" }
// COIN: which note survives a SOLO step, by pitch rank. CYCLE walks the solo across steps.
enum TuttiPick: String, Codable, CaseIterable { case low = "LOW", high = "HIGH", random = "RANDOM", cycle = "CYCLE" }
// PATTERN: per-slice set-shape. Octave variants are first-class; REST = the slice is silent.
enum TuttiSlice: String, Codable, CaseIterable {
    case all = "ALL", low = "LOW", high = "HIGH", top2 = "TOP2", bot2 = "BOT2",
         lowOct = "LOW+8", allDownOct = "ALL−8", rest = "REST"
}
// LENGTH (working name; Paul 2026-08-05) — per-slice GATE override. Four DISTINCT states: PASS = the chord stays
// present/sustained (ties, no re-attack) · MUTE = silence (a rest) · SHORT = a staccato stab · LONG = a re-attacked
// long note. Painted across 8 slices of the step; standalone it carves a held chord, downstream it overrides gates.
enum LenState: String, Codable, CaseIterable { case pass = "PASS", mute = "MUTE", short = "SHORT", long = "LONG" }
// WEAVE (working name; Paul 2026-08-07) — a rank-clocked polyrhythm DRIVER: each held note ticks on its own clock,
// derived from its rank. MODE = the ratio law. LADDER: rank r = base÷2^r (1/4·1/8·1/16…). HARMONIC: rank r = (r+1)×base
// (1:2:3:4 — pitch ratios as time ratios). (DRAWN + EUCLID modes are a phase-2 add — append-only enum.)
enum WeaveMode: String, Codable, CaseIterable { case ladder = "LADDER", harmonic = "HARMONIC", drawn = "DRAWN", euclid = "EUCLID" }
// RATCHET MODE (working name; Paul 2026-08-16, ferry) — the TUTTI precedent on ratchet. ALL = every step bursts (today);
// COIN = a seeded chance per step to ratchet-or-plain (a count range varies the burst); PATTERN = an 8-slice row of
// per-slice counts (0=plain · 2/3/4) painted across the bar. Append-only; ALL is the migration-invisible default.
enum RatchetMode: String, Codable, CaseIterable { case all = "ALL", coin = "COIN", pattern = "PATTERN" }

let colourIDs: [String] = ["gold","orange","vermilion","wine","magenta","blush","purple","violet",
                           "indigo","azure","cyan","teal","mint","green","chartreuse","slate"]

// MARK: - Colour (the treatment) — §1/§9

struct ColourParams: Codable, Equatable {
    // Superset of per-type params; only the active type's fields are meaningful. §12.0: append-only.
    var pattern: ArpPattern? = .up
    var rate: ArpRate? = .r1_16
    var octaves: Int? = 1
    var gate: Double? = 0.6
    var phase: ArpPhase? = .retrig
    var count: Int? = 3            // ratchet
    var ramp: Double? = 0.5        // ratchet
    var passes: [Bool]? = [true, true, true, true]  // passgate
    var strumDir: StrumDir? = .up  // strum
    var spread: Double? = 0.1      // strum: chord stagger in BEATS (0…1)
    var curve: Double? = 0         // strum: timing curve −1…1 (0 = linear)
    var velTilt: Double? = 0       // strum: velocity tilt −1…1 (0 = flat)
    var strumSpreadNorm: Bool? = true  // strum: rake spans a constant `spread` width (true) vs a per-note gap that widens with the pool (false)
    var probability: Double? = 1   // chance: pass-through probability 0…1 per note-on
    var chanceTilt: Double? = 0    // chance WEIGHT −1…1 (user 2026-08-11): +favours TOP notes, −favours BOTTOM
    var chanceDensity: Bool? = false // chance CONSTANT-DENSITY: keep ~a constant NUMBER of notes regardless of chord size
    var arpFit: Bool? = false      // arp FIT (user 2026-08-11): rate derives so ONE pool traversal = one beat (constant cycle)
    // harmonize (§3): up to 3 added voices, each an interval −24…+24 st (0 = voice OFF), plus a
    // velocity scale 0.1…1 applied to the ADDED voices (root stays full). B overrides the intervals.
    var harmIntervals: [Int]? = [0, 0, 0]
    var harmVelScale: Double? = 0.8
    // ECHO (the TAIL era, user 2026-08-08): the delay-echo controls. Append-only Optional (old docs decode nil →
    // defaults). SUPERSEDES echo's earlier reuse of rate/count/ramp; those keys are ignored for echo now.
    var echoSync: Bool? = true          // ON = beat divisions · OFF = milliseconds
    var echoDelayDiv: Int? = 4          // synced: delay in 16th-notes (1…16; 4 = one beat)
    var echoDelayMs: Double? = 250      // free: delay in ms
    var echoRepeats: Int? = 3           // number of echoes 1…16
    var echoOffset: Double? = 0         // ±0.33 — nudge echoes ahead of / behind the grid (fraction of the interval)
    var echoFeedDelay: Double? = 0.7    // 0…1 — input send: how loud the FIRST echo is
    var echoDecay: Double? = 0.5        // 0…1 — per-echo velocity FALLOFF (was FEEDBACK; removed per design 2026-08-07)
    var echoPitch: Int? = 0             // semitones transposed per successive echo (climbing / descending)
    var echoThru: Bool? = true          // THRU = pass the dry note · MUTE = echoes only
    var echoSpill: EchoSpill? = .ring   // TAIL SPILL (design 2026-08-07): RING past the bar · CUT inside it · HAND (birthstone, deferred)
    // EUCLID generator (user 2026-08-08). BURST reuses count+curve; CASCADE reuses rate+strumDir — no new fields.
    var euclidPulses: Int? = 5          // K — hits per cycle (1…16) when PULSES = FIXED
    var euclidSteps: Int? = 8           // N — steps in the cycle (2…16); K hits spread evenly across N
    var euclidRot: Int? = 0             // rotate the pattern (0…N−1)
    var euclidPulsesFromPool: Bool? = false   // PULSES mode (user 2026-08-09): POOL = K follows the held-note count
    var euclidSpan: PatternSpan? = nil        // CELL (per-column, default) | ROW (the N steps span the whole bar) — Paul 2026-08-18
    var burstSpan: PatternSpan? = nil         // BURST: CELL (the roll fills each column) | ROW (the roll unfolds across the bar) — Paul 2026-08-19
    var cascadeSpan: PatternSpan? = nil       // CASCADE: CELL (reveal per column) | ROW (the reveal spans the bar) — Paul 2026-08-19
    // THE MOD PROCESSOR (CC generator, delta). Append-only Optional. Reuses `rate` as the LFO PERIOD (one full shape
    // cycle per rate-beats). modReset = the LEAVE-DISPOSITION: true = reset the CC to 0 on column exit, false = leave-as-landed.
    var modCC: Int? = 74                // target controller number 0…127 (74 = filter cutoff, a common default)
    var modSource: ModSource? = .shape  // the SOURCE spine (SHAPE · FOLLOW · STEPS · STRIKE · EXTERN)
    var modShape: ModShape? = .sine     // WAVE — SINE · TRI · SQR · RAMP · S&H  (SHAPE)
    var modRate: ModRate? = .r2         // LFO PERIOD (beats per cycle) — SHAPE · STEPS (steps span one period)
    var modSpan: PatternSpan? = nil     // SHAPE: CELL (the modRate period, default) | ROW (one cycle spans the whole bar) — Paul 2026-08-19
    var modStepSpan: ModStepSpan? = nil // STEPS: PERIOD (rate period, default) | ROW | ROW×2 | ROW×4 (16/32 breakpoints) — Paul 2026-08-20
    var modFollow: ModFollow? = .register   // FOLLOW: which sounding property drives the CC
    var modSteps: [Int]? = nil          // STEPS: 8 values 0…127 (nil → a rising staircase)
    var modSmooth: Bool? = true         // STEPS: SMOOTH (interpolate) vs STEP (hold)
    var modAttack: Double? = 0.15       // STRIKE: attack, beats (rise to MAX on entry)
    var modRelease: Double? = 0.6       // STRIKE: release, beats (fall back to MIN)
    var modExternCC: Int? = 1           // EXTERN: the incoming CC# read + transformed (1 = mod wheel)
    // MIN/MAX (CC-stage §1 row 3): the shape maps 0…1 → [min, max]. RANGE is depth AND polarity — MIN > MAX inverts
    // (no invert chip). RESET leaves the CC to MIN on column exit. (Supersedes the interim `depth`.)
    var modMin: Int? = 0                // the shape's floor (0…127)
    var modMax: Int? = 127              // the shape's ceiling (0…127)
    var modReset: Bool? = true          // ON LEAVE: reset to MIN on column exit · OFF = leave-as-landed
    var modTarget: ModTarget? = nil     // SEND: CC (emit a controller, default) | CHAIN (modulate a chain param, no CC) — Paul 2026-08-20
    var modChainParam: MacroParam? = nil    // CHAIN target: which param (gate · spread · curve · …) the offset lands on
    // GLIDE (notes→pitch-bend translator). Append-only Optional.
    var glideTime: Double? = 0.25       // slide duration per transition, beats (0 = instant pitch-jump)
    var glideRange: Int? = 2            // ± bend range in semitones (1…48) — must match the synth
    var glidePriority: GlidePriority? = .last   // which held note the mono voice tracks
    var glideReanchor: Bool? = true     // out-of-range target → RE-ANCHOR (fresh note-on) · false = CLAMP to the range
    // TUTTI (working name; Paul 2026-08-13) — set-level chance. ONE processor, a MODE radio. COIN: per step a seeded
    // roll (BALANCE = P(TUTTI)) → SOLO (one PICK-chosen note) or TUTTI (the whole set). PATTERN (phase 2): 8 authored
    // slice states render the held set as a shape per slice. Append-only Optional (old docs decode nil → defaults).
    var tuttiMode: TuttiMode? = .coin
    var tuttiBalance: Double? = 0.5     // COIN: P(TUTTI) per step 0…1 (0 = always SOLO, 1 = always the full chord)
    var tuttiPick: TuttiPick? = .low    // COIN: which note carries a SOLO step, by rank
    var tuttiSlices: [TuttiSlice]? = [.all, .all, .all, .all, .all, .all, .all, .all]  // PATTERN: 8 slice set-shapes
    var tuttiRate: ArpRate? = .r1_8     // PATTERN: slices per window (reuses the arp rate divisions)
    var tuttiRotate: Int? = 0           // PATTERN: rotate the slice pattern along the bar (0…7)
    var tuttiSpan: PatternSpan? = nil   // PATTERN: CELL (the RATE stride, default) | ROW (the 8 slices span the whole bar) — Paul 2026-08-19
    // LENGTH (Paul 2026-08-05) — 8 slices of the STEP (like CHOP), each PASS/MUTE/SHORT/LONG, plus two gate lengths +
    // ROTATE. Default all-PASS = the chord sustains. Append-only Optional (old docs decode nil → defaults).
    var lenSlices: [LenState]? = [.pass, .pass, .pass, .pass, .pass, .pass, .pass, .pass]
    var lenShort: Double? = 0.4         // SHORT gate = 5…95% of ONE slice (staccato)
    var lenLong: Double? = 0.7          // LONG length 0…1 → 25% of a slice … the STEP end (rings across slices)
    var lenRotate: Int? = 0             // rotate the slice pattern (0…7)
    var lenSpan: PatternSpan? = nil     // CELL (per-column, default) | ROW (the 8 slices span the whole bar) — Paul 2026-08-19
    // WEAVE (Paul 2026-08-07) — the rank-clocked polyrhythm driver. BASE = the slowest (bass) clock; MODE = the ratio
    // law; SPAN = how many ranks weave (extras join the top clock); GATE (reused) is shared. Append-only Optional.
    var weaveMode: WeaveMode? = .ladder
    var weaveBaseStep: StepRate? = .r1_4   // the slowest / bass rank's clock (slow range 2/1…1/8). Was weaveBase:ArpRate — renamed for the slower range (old docs default)
    var weaveSpan: Int? = 4             // how many ranks get their own clock; notes beyond this join the top clock
    var weavePhase: ArpPhase? = .retrig // RETRIG = restart each step · FREE = free-run the grid · LEGATO = the interlock flows from the run's start
    var weaveDrawn: [StepRate]? = [.r1_2, .r1_4, .r1_8, .r1_8, .r1_8, .r1_8, .r1_8, .r1_8]  // DRAWN: one rate per rank (0…7)
    var weaveEuclidSteps: Int? = 8      // EUCLID: the cycle length M; rank r fills 2r+1 of M pulses (bass sparse → top dense)
    // SPLIT (Paul 2026-08-05) — a set-membership filter, reusing the chord-split + velocity-window model. Append-only.
    var splitSet: ChordSplit? = ChordSplit()   // ALL · TOP n · BOTTOM n · RANGE (pool-relative except RANGE)
    var splitVel: VelWindow? = VelWindow()     // pass only notes with velocity in [floor, ceil]
    // RATCHET MODE (Paul 2026-08-16, ferry) — ALL (uses `count`/`ramp` above) · COIN · PATTERN. Append-only Optional.
    var rtcMode: RatchetMode? = .all
    var rtcChance: Double? = 0.5               // COIN: P(ratchet) per step (else plain single hit)
    var rtcCountLo: Int? = 2                   // COIN: the burst count range low (when it ratchets)
    var rtcCountHi: Int? = 4                   // COIN: the burst count range high
    var rtcSlices: [Int]? = [2, 0, 2, 0, 2, 0, 2, 0]   // PATTERN: 8 per-slice counts (0 = plain single · 2/3/4 = roll)
    var rtcRate: ArpRate? = .r1_8              // PATTERN: slice rate (slices per window, walks the bar)
    var rtcRotate: Int? = 0                    // PATTERN: rotate the slice pattern (0…7)
    var rtcSpan: PatternSpan? = nil            // PATTERN: CELL (the RATE stride, default) | ROW (the 8 slices span the whole bar) — Paul 2026-08-19
}
/// TAIL SPILL — what happens to an echo's pending repeats when the playhead leaves the cell's column. RING lets
/// them spill past the bar (the tail era's default); CUT kills the pending ones (the sounding note finishes its
/// gate); HAND is the deferred BIRTHSTONE (handed repeats fire into the pool below). Enum three-valued from day one.
enum EchoSpill: String, Codable, CaseIterable { case ring = "RING", cut = "CUT", hand = "HAND" }

struct Colour: Codable, Equatable {
    var colourID: String
    var type: ProcessorType
    // v3.0 (delta §7): per-Colour OUT CH is REMOVED — channel is a property of the WIRE (busChannels),
    // not the treatment. Old docs carrying an `outChannel` key decode fine (Codable ignores unknown keys).
    var transpose: Int = 0         // −24…+24, accumulates in chains, clamped — the ACTIVE type's transpose
    var morph: Double = 0          // §3.2 — the per-colour macro AUParameter — the ACTIVE type's morph
    var paramsA: ColourParams = ColourParams()   // procA — the A face
    // delta item 8 (TWO-PROCESSOR Colours): procB — this Colour's OWN second face. paramsB is REAL storage
    // again (resolved with fallback A, so a sparse procB inherits A's fields). A cell's `alt` flag flips to
    // procB; `morph` (below) is the position toward it. B-less ⇒ typeB == nil ⇒ b = a, no morph.
    var paramsB: ColourParams = ColourParams()
    // delta item 8: procB's processor TYPE, or nil = B-less (the natural encoding — old docs decode nil).
    // Same type as A ⇒ FULL morph glide; different ⇒ SWAP (binary flip at t≥0.5). B is sourced ONLY when
    // this is non-nil, so a pre-pair doc's stale paramsB stays inert.
    var typeB: ProcessorType? = nil
    // delta item 8: procB's transpose — STORED (COPY A→B + round-trip) but render-INERT in v1 (SnapColour
    // carries a single transpose; both faces sound with A's, matching the old pair behavior). Making it
    // render-live is a future increment (SnapColour.transposeB + effectiveTranspose + 400+i addresses).
    // Optional (append-only §12.0) → old docs decode nil; read via `transposeBResolved`.
    var transposeB: Int? = nil
    // LEGACY (delta §9 item 5, retired by item 8): the old morph PARTNER — an index 0…15 or nil. DECODE-ONLY
    // now: `migrateColourPairsIfNeeded` copies the partner into procB, then the render ignores this. Kept
    // (never deleted) so an older build re-loading a migrated doc still reads the pair (lossless downgrade).
    var altColour: Int? = nil
    // Per-TYPE stash of TRANSPOSE (spec revision): each processor type keeps its own transpose, so
    // switching type never leaks a pitch. Optional → v2 docs decode as nil (all-zero).
    var transposeByType: [Int]? = nil
    // §9 item 1 the ON TRIGGER SYSTEM (GUI iteration 1, 2026-07-26): per-Colour trigger assignments,
    // STORED INERT — no engine execution yet. Optional so pre-ON docs decode as nil → OnConfig() defaults.
    var on: OnConfig? = nil
    /// The ON config, nil-safe (missing ⇒ all-"—"/unchecked). Non-persisting read helper.
    var onResolved: OnConfig { on ?? OnConfig() }
    // Cells/desk overhaul C1: an OPTIONAL Colour NAME (the user's word). Optional → old docs decode nil.
    var name: String? = nil
    /// The custom name if set, else the TYPE name (today's label). Never empty.
    var nameResolved: String { (name.flatMap { $0.isEmpty ? nil : $0 }) ?? type.rawValue }
    // Cells/desk overhaul D1: whether this Colour is DEFINED (a palette chip) vs an undefined "+" slot. Optional
    // → old docs decode nil ⇒ DEFINED (all 16 as today). Non-persisting read helper below.
    var defined: Bool? = nil
    var isDefined: Bool { defined ?? true }
    // CELL MACHINE stage-3 (feat/EditPageSpike): the shared TEMPLATE chain — this colour's default processor
    // chain, followed by every cell of this colour with NO per-cell override (Cell.processors == nil), in every
    // scene. Optional (append-only §12.0) → old docs decode nil; the builder then falls back to the legacy
    // single-processor type+paramsA. Editing it in the "ALL <colour>" scope changes every following cell at once.
    var templateChain: [ProcessorSlot]? = nil

    /// delta item 8: does this Colour have a second processor (procB)? Drives morph/ALT availability + greying.
    var hasProcB: Bool { typeB != nil }
    /// procB's transpose, nil-safe (missing ⇒ 0). Render-inert in v1; kept for COPY A→B + round-trip.
    var transposeBResolved: Int { transposeB ?? 0 }

    /// Switch the processor type, giving each type its own TRANSPOSE. Stash the active transpose under the
    /// old type, restore the new type's. Idempotent for a no-op switch. `morph` is a single per-Colour
    /// scalar (the position toward the partner, delta §9 item 5) — NOT per-type — so a type switch leaves
    /// it untouched. `transpose` remains the live (AUParameter- and snapshot-facing) value for this type.
    mutating func switchType(to newType: ProcessorType) {
        guard newType != type else { return }
        let n = ProcessorType.allCases.count
        func sized(_ a: [Int]?) -> [Int] { var v = a ?? []; if v.count < n { v += Array(repeating: 0, count: n - v.count) }; return v }
        var tStash = sized(transposeByType)
        let oldIdx = ProcessorType.allCases.firstIndex(of: type) ?? 0
        let newIdx = ProcessorType.allCases.firstIndex(of: newType) ?? 0
        tStash[oldIdx] = transpose      // save the active transpose under the old type
        transpose = tStash[newIdx]      // restore the new type's own transpose
        type = newType
        transposeByType = tStash
    }
}

// MARK: - ON trigger config (§9 item 1) — per-Colour; GUI iteration 1 stores it INERT (no engine yet).
// Enums are String-raw so their rawValue IS the chip label. Append-only (never reorder/reuse the strings).

enum OnTap: String, Codable, CaseIterable { case none = "—", alt = "ALT", mute = "MUTE", solo = "SOLO EMITTERS", fill = "FILL", replay = "REPLAY" }
enum OnTapWhen: String, Codable, CaseIterable { case now = "NOW", step = "STEP", pass = "PASS", lap = "LAP" }
enum OnTapFor: String, Codable, CaseIterable { case retap = "RETAP", onePass = "1 PASS", oneLap = "1 LAP" }
enum OnHold: String, Codable, CaseIterable { case none = "—", alt = "ALT", freeze = "FREEZE", sliceCycle = "SLICE-CYCLE", morphScrub = "MORPH-SCRUB", oct = "OCT" }
enum OnHoldRelease: String, Codable, CaseIterable { case spring = "SPRING", latch = "LATCH" }
enum SliceSize: String, Codable, CaseIterable { case half = "½", quarter = "¼", eighth = "⅛", sixteenth = "1⁄16" }
enum OnArrive: String, Codable, CaseIterable { case none = "—", altAlternate = "ALT-ALTERNATE", morphDrift = "MORPH-DRIFT", dice = "DICE", emitterRotate = "EMITTER-ROTATE" }
enum DriftMode: String, Codable, CaseIterable { case loop = "↻", pingpong = "⇄" }
enum OnLeave: String, Codable, CaseIterable { case none = "—", exitStab = "EXIT STAB", ringChop = "RING·CHOP" }

/// The five ON rows for one Colour. All fields defaulted (none/unchecked), so `OnConfig()` is "unassigned".
/// Every field non-Optional with a default — the whole struct is written together; `Colour.on` is the
/// Optional that gives old-doc compatibility. (A FUTURE schema change here must add fields as Optional or
/// custom-decode, or bump formatVersion — this version reads only what it wrote.)
struct OnConfig: Codable, Equatable {
    // ON TAP
    var tap: OnTap = .none
    var tapWhen: OnTapWhen = .now
    var tapFor: OnTapFor = .retap
    // ON HOLD
    var hold: OnHold = .none
    var holdRelease: OnHoldRelease = .spring
    var sliceSize: SliceSize = .quarter        // shown only when hold == .sliceCycle
    var octUp: Bool = true                     // OCT direction ± (shown only when hold == .oct)
    // ON ARRIVE
    var arrive: OnArrive = .none
    var arriveEvery: Int = 1                   // 1…4
    var driftPct: Int = 10                     // ±n% (shown only when arrive == .morphDrift)
    var driftMode: DriftMode = .pingpong       // ↻ / ⇄ (shown only when arrive == .morphDrift)
    // ON LEAVE
    var leave: OnLeave = .none
    // ON SCENE (independent checklist facets)
    var sceneEntrance: Bool = false
    var entrancePass: Int = 1                  // 1…16
    var sceneExit: Bool = false
    var exitPass: Int = 1                      // 1…16
    var sceneResetMorph: Bool = false
    var sceneAutoArm: Bool = false             // always greyed this iteration (no RECORD type)

    /// True when nothing is assigned anywhere — the whole section reads "unassigned".
    var isEmpty: Bool { self == OnConfig() }

    // Collapsed-row summaries (the accordion shows these). "" ⇒ the row is unassigned (render a dim "＋").
    var tapSummary: String {
        guard tap != .none else { return "" }
        return "\(tap.rawValue) · \(tapWhen.rawValue) · \(tapFor.rawValue)"
    }
    var holdSummary: String {
        guard hold != .none else { return "" }
        var s = "\(hold.rawValue) · \(holdRelease.rawValue)"
        if hold == .sliceCycle { s += " · \(sliceSize.rawValue)" }
        if hold == .oct { s += " · \(octUp ? "+" : "−")" }
        return s
    }
    var arriveSummary: String {
        guard arrive != .none else { return "" }
        var s = arrive.rawValue
        if arrive == .morphDrift { s += " \(driftMode.rawValue) \(driftPct)%" }
        s += " · every \(arriveEvery)"
        return s
    }
    var leaveSummary: String { leave == .none ? "" : leave.rawValue }
    var sceneSummary: String {
        var parts: [String] = []
        if sceneEntrance { parts.append("ENTER \(entrancePass)") }
        if sceneExit { parts.append("EXIT \(exitPass)") }
        if sceneResetMorph { parts.append("RESET MORPH") }
        if sceneAutoArm { parts.append("AUTO-ARM") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Cell (the patch point) — §1.1: cells share nothing.

/// §cell-edit D — CHORD SPLIT: which of a MIDI-IN cell's held source notes it takes. ALL (default) · TOP n ·
/// BOTTOM n · KEY RANGE (a split note + a side). On the ascending source list every mode is a contiguous
/// window (RANGE HIGH = the ≥split suffix, LOW = the <split prefix), resolved by `chordSplitWindow`.
enum SplitMode: String, Codable, CaseIterable { case all = "ALL", top = "TOP", bottom = "BOTTOM", range = "RANGE" }
struct ChordSplit: Codable, Equatable {
    var mode: SplitMode = .all
    var n: Int = 2            // TOP/BOTTOM: how many notes
    var note: Int = 60       // RANGE: the split point (MIDI note)
    var high: Bool = true    // RANGE: side — true = notes ≥ split (HIGH), false = notes < split (LOW)
}

/// §cell-edit D — VELOCITY WINDOW: a MIDI-IN cell admits only source notes whose velocity is in [floor, ceil].
/// The default (1…127) admits everything; it gates at the source boundary, BEFORE the chord split selects.
struct VelWindow: Codable, Equatable {
    var floor: Int = 1       // 1…127
    var ceil: Int = 127      // 1…127 (≥ floor)
}

/// §cell-edit F — per-slice output CHOP: each of a column's 8 slices can INDEPENDENTLY route to MAIN (own
/// emitters), ALT (the shared `altDest` set), and/or be MUTED (silent — overrides). Three per-slice bitmasks
/// (bit i = slice i). Default = all MAIN, no ALT, no MUTE (no effect). [Model + the routing ENGINE below.]
struct Chop: Codable, Equatable {
    var mainMask: UInt8 = 0xFF   // slices routed to the cell's own emitters
    var altMask: UInt8 = 0       // slices ALSO routed to altDest
    var muteMask: UInt8 = 0      // slices silenced (overrides main/alt)
    var altDest: Set<Bus> = []
}

struct Cell: Codable, Equatable {
    var colourID: String
    var stack: Bool = false        // v2 LEGACY (▾) — decode-only after commit 3; removed at commit 4
    var buses: Set<Bus> = [.a]     // sound leaves ONLY through a lit letter (§2.3)
    var srcMix: Bool = false       // v2 LEGACY (+SRC) — no v3 equivalent; dropped on migration
    var alt: Bool = false
    var bypassed: Bool = false
    var muted: Bool = false
    // v3.0 (delta §1/§2): the cell's single input reference. nil = MIDI IN; else the referenced row
    // in the same column. ⚠ RENDER-INERT but IDENTITY-LIVE: grid-chaining is retired so the render path
    // ignores this (resolvedParent is always −1), BUT it still feeds the cell's SEAL/twin identity hash
    // (Derivations.SealKey) and the flow diagram — do NOT delete it as "dead" or every seal hash changes.
    // Optional → old docs decode as nil, filled by migrateLegacyRoutingIfNeeded(). (Paul 2026-08-16)
    var inputRow: Int? = nil
    // v3.0 (delta §7): input-channel filter for a MIDI-IN cell. 0 = OMNI (default); 1–16 = only notes
    // arriving on that channel. Applies at the source boundary only (referenced parents aren't filtered).
    // LEGACY after RECEIVERS (delta §9 item 11): the filter now lives on the Receiver a cell subscribes
    // to. Kept for migration (synthesizeReceiversIfNeeded reads it) + as the fallback when a doc has no
    // receivers; not dropped until a later formatVersion (parallel to `stack`/`srcMix`).
    var inputChannel: Int = 0
    // delta §9 item 11: the RECEIVER a MIDI-IN cell subscribes to (0–3). Consulted ONLY when inputRow ==
    // nil; nil = the default receiver (0 = Receiver 1). Row-referencing cells ignore it. The cell's
    // effective source filter is resolved from this receiver at build time (SnapCell.inputChannel).
    var inputReceiver: Int? = nil
    // §cell-edit D CHORD SPLIT (per-cell): which held source notes this cell takes. Optional → old docs decode
    // as nil = ALL (no split). Applies at the source boundary (SnapCell mirror drives the render path).
    var chordSplit: ChordSplit? = nil
    var chordSplitResolved: ChordSplit { chordSplit ?? ChordSplit() }
    // §cell-edit D VELOCITY WINDOW (per-cell): admit only source notes with velocity in [floor, ceil]. Optional
    // → old docs decode nil = full range (1…127). Gates at the source boundary, before the chord split.
    var velWindow: VelWindow? = nil
    var velWindowResolved: VelWindow { velWindow ?? VelWindow() }
    // §cell-edit F CHOP (per-cell output sequence). Optional → old docs decode nil = no chop (all MAIN).
    var chop: Chop? = nil
    var chopResolved: Chop { chop ?? Chop() }
    // CELL MACHINE (feat/EditPageSpike, §proposal 2026-07-31): the cell OWNS a serial CHAIN of up to 8
    // processor slots (pedalboard model), replacing the shared-Colour treatment. Optional (append-only §12.0)
    // → old docs decode nil; the SnapshotBuilder falls back to a 1-slot head seeded from the referenced
    // Colour's A face (the cell can't see its Colour here, so resolution lives builder-side). Stage 1 renders
    // the HEAD slot + per-slot bypass; slots 2…8 are stored but not yet executed (serial chain = a later stage).
    var processors: [ProcessorSlot]? = nil
    // CELL LIBRARY star rating (0–5). Optional → old library files decode nil ⇒ unrated (0). Library metadata only;
    // grid cells leave it nil. (Paul 2026-08-17)
    var stars: Int? = nil
    var starsResolved: Int { max(0, min(5, stars ?? 0)) }

    /// "Machine minus routing" for the CELL LIBRARY (§cell-machine 4.8): a copy carrying this cell's colour +
    /// source-shaping (chord-split · velocity window · chop) + the given MATERIALISED chain, with ALL routing
    /// (input receiver/row + output emitters) and perform state stripped — ready to stamp into a fresh position
    /// and wire up. The grid-position-specific input row can't transfer; the emitters start blank (null-cell rule).
    func libraryStripped(materialisedChain: [ProcessorSlot]) -> Cell {
        var c = Cell(colourID: colourID)
        c.processors = materialisedChain
        c.chordSplit = chordSplit; c.velWindow = velWindow; c.chop = chop
        c.buses = []                 // no output until the user wires one (routing is per-placement)
        return c                     // inputRow/inputReceiver nil, alt/muted/bypassed false — all defaults
    }
}

// CELL MACHINE — one stage of a cell's processor chain: a processor type + its params + a true-bypass toggle.
// Reuses ColourParams verbatim as the per-slot param bag (append-only §12.0). Codable/Equatable so the chain
// round-trips like every other cell field.
struct ProcessorSlot: Codable, Equatable {
    var type: ProcessorType
    var params: ColourParams = ColourParams()
    var bypassed: Bool = false     // per-slot TRUE-BYPASS (the chain's debugger — proposal §2 C3)
    // MACRO AUTHORING (§7): the persisted ALTERNATIVE control set — reopening MACRO shows the last-authored B.
    // Additive Optional → old docs decode nil (no ALT authored yet). The binding stores the delta (ALT − MAIN).
    var paramsAlt: ColourParams? = nil
    var bypassedAlt: Bool? = nil
}

// MARK: - Receiver (delta §9 item 11) — a shared, named MIDI-input object

/// One of four document-level MIDI receivers. A MIDI-IN cell subscribes to a receiver (FROM RECEIVER n)
/// and inherits its channel filter; the receiver also carries a persisted input-mute (the input twin of
/// the §6a emitter mute) and a per-receiver MPE-merge flag (the "MPE front door" — field only for now;
/// merge semantics are their own later mini-spec). Receiver COLOUR is assigned by index (the fixed
/// infrastructure family), not stored. note-RANGE (register splits) is a later addition — no field yet.
/// THE CONFIG SHEETS (Paul 2026-08-20): a door's MODE — LATCH (notes toggle in/out of the pool, the old KEYS latch) ·
/// HOLD (chord-detect-and-replace, the old CHORD latch) · KEYS (the on-screen keyboard, the old PIANO latch) · REPLAY
/// (the door input ring loops as living input — stage 3) · FILE (a loaded .mid loops as living input — stage 4). The 3
/// EXISTING modes map to the legacy latchAdd/latchPiano fields; REPLAY/FILE are reserved (not yet wired → a HOLD-like
/// fallback until their stages land).
enum DoorMode: String, Codable, CaseIterable { case latch, hold, keys, replay, file }

struct Receiver: Codable, Equatable {
    var name: String = ""
    var channel: Int = 0        // 0 = OMNI (default), 1–16 = single wire channel (wire ch = channel − 1)
    // MULTI-CHANNEL (Paul 2026-08-21): a door can hear an arbitrary SUBSET of channels — a 16-bit mask (bit c = channel
    // c+1). Additive-Optional: nil ⇒ derive from the legacy `channel` (OMNI/single), byte-identical for old docs. 0xFFFF
    // = all (OMNI). 0 = none (hears nothing — the door is effectively closed by channel).
    var channelMask: UInt16? = nil
    var channelMaskResolved: UInt16 {
        if let m = channelMask { return m }
        return channel == 0 ? 0xFFFF : (UInt16(1) << UInt16(max(1, min(16, channel)) - 1))
    }
    var mpeMerge: Bool = false  // per-receiver MPE-merge (the front door); engine semantics deferred
    var muted: Bool = false     // input mute (PERSISTED) — a muted receiver feeds its subscribers nothing
    // INPUT ENABLE (2026-08-03): whether this door LISTENS for incoming notes. DISABLED = admit no NEW notes
    // (dark meter, latch SEALED — no re-capture), but a receiver already ARMED keeps FEEDING its frozen chord to
    // the grid ("close the door, keep the room" — latch A, disable A, play B untouched). Distinct from `muted`,
    // which stops the FEED into the grid entirely. Optional so old docs decode nil ⇒ enabled. Persisted, like mute.
    var inputEnabled: Bool? = nil
    /// The listen state, nil-safe: missing ⇒ enabled (listening). Non-persisting read helper.
    var inputEnabledResolved: Bool { inputEnabled ?? true }
    // RANGE (2026-08-03, redesign §2): the door's note WINDOW — it admits only notes with lo ≤ note ≤ hi. UPSTREAM
    // of the latch and the grid feed (a note outside the window is as if unplayed, for this door). Optional so old
    // docs decode nil ⇒ ALL (0…127). Persisted rig config. `rangeLo`/`rangeHi` are MIDI note numbers (0…127).
    var rangeLo: Int? = nil
    var rangeHi: Int? = nil
    /// The note window, nil-safe + clamped: missing ⇒ full range. Non-persisting read helpers.
    var rangeLoResolved: UInt8 { UInt8(max(0, min(127, rangeLo ?? 0))) }
    var rangeHiResolved: UInt8 { UInt8(max(0, min(127, rangeHi ?? 127))) }
    /// True when the door admits every note (the fast path skips the window check).
    var rangeIsFull: Bool { rangeLoResolved <= 0 && rangeHiResolved >= 127 }
    // BYPASS (2026-08-03, redesign §1/§2): when on, this door's shaped, in-range held notes sound DIRECTLY on its
    // destination emitters (A–D), skipping the grid — a live monitor path (works stopped too). A DIRECT injection:
    // no emitter roles (claim/flatten/alt). `bypassDest` is the A–D emitter bitmask (bit i = emitter i). Optional so
    // old docs decode nil ⇒ off / all dests. Persisted rig config.
    var bypass: Bool? = nil
    var bypassDest: Int? = nil
    var bypassResolved: Bool { bypass ?? false }
    /// The destination emitter mask, nil-safe: missing ⇒ ALL four (A–D). Non-persisting read helper.
    var bypassDestResolved: UInt8 { UInt8((bypassDest ?? 0b0001) & 0b1111) }   // default = emitter A (user 2026-08-05)
    // §item 11 INPUT CABLES (amendment 2026-07-26): the input cable(s) this receiver reads, as a BITMASK
    // (bit i = cable i+1; cables 1–4). Optional so pre-cable docs decode as nil ⇒ ANY (all cables) — a
    // migration no-op. The v1 stepper writes ANY or a single bit; the bitmask reserves subset-multi later.
    var cable: Int? = nil
    /// The cable bitmask, nil-safe: missing ⇒ ANY (hears every cable). Non-persisting read helper.
    var cableResolved: Int { cable ?? 0b1111 }
    // CONTROLLER ROUTING (v1, spec AcceptanceCriteria-controller-routing): the emitters (A–D bitmask) this door
    // forwards incoming CC · PB · AT · PC to, RE-STAMPED to each emitter's channel. Optional so old docs decode
    // nil ⇒ ALL-LIVE (all four). Persisted rig config.
    var controllerMask: Int? = nil
    var controllerMaskResolved: UInt8 { UInt8((controllerMask ?? 0b1111) & 0b1111) }
    // KEYS | CHORD (was "TWO LATCH MODES", ferry 2026-07-27; the toggle moved to the STRIP 2026-08-03): the
    // per-receiver latch update rule, stored in `latchAdd` (name kept for decode-compat). true = KEYS (per-note
    // toggle — each note-on toggles frozen-pool membership); false = CHORD (detect-and-replace — chord clears &
    // replaces the pool). Persisted rig config. DEFAULT is now KEYS (redesign §3): optional so old docs decode
    // nil ⇒ KEYS. Mode-switching NEVER clears the pool (the Kernel only resets on the arm rising edge); latch-off
    // releases all, in both modes.
    var latchAdd: Bool? = nil
    /// The latch mode, nil-safe: missing ⇒ KEYS (true — the redesign default). Non-persisting read helper. When an
    /// explicit `doorMode` is set it wins (LATCH ⇒ true, everything else ⇒ false); else falls through to the legacy
    /// field EXACTLY (byte-identical for old docs).
    var latchAddResolved: Bool { doorMode.map { $0 == .latch } ?? (latchAdd ?? true) }
    // PIANO latch (2026-08-10): a third latch mode — the frozen pool is CHOSEN from an on-screen keyboard, not captured
    // from live input. When on (+ the latch armed), `pianoNotes` feed the grid as the frozen chord. Optional so old
    // docs decode nil ⇒ off. Persisted rig config. `latchPiano` overrides KEYS|CHORD when true.
    var latchPiano: Bool? = nil
    var pianoNotes: [Int]? = nil
    /// KEYS (on-screen keyboard) when an explicit `doorMode == .keys`; else the legacy field EXACTLY (byte-identical).
    var latchPianoResolved: Bool { doorMode.map { $0 == .keys } ?? (latchPiano ?? false) }
    var pianoNotesResolved: [Int] { (pianoNotes ?? []).filter { $0 >= 0 && $0 <= 127 } }
    // THE CONFIG SHEETS (Paul 2026-08-20): the door's MODE. Additive-Optional — nil ⇒ derive from the legacy latch fields
    // (LATCH/HOLD/KEYS), so old docs are unchanged. When the door sheet sets it explicitly, it drives the resolvers above.
    var doorMode: DoorMode? = nil
    // REPLAY (stage 3): how much of the door's input HISTORY loops as living input — 1 · 2 · 4 · 8 passes. Additive-
    // Optional; nil ⇒ 1. Clamped to {1,2,4,8}.
    var replayPasses: Int? = nil
    var replayPassesResolved: Int { let p = replayPasses ?? 1; return [1, 2, 4, 8].contains(p) ? p : 1 }
    // FILE (config-sheets stage 4): a loaded .mid clip that loops as this door's input. Decoded events are stored on the
    // document (copy-in — self-contained). Additive-Optional. `fileName` is display-only.
    var fileClip: [MidiFile.NoteEvent]? = nil
    var fileLoopBeats: Double? = nil
    var fileName: String? = nil
    var doorModeResolved: DoorMode {
        if let m = doorMode { return m }
        if (latchPiano ?? false) { return .keys }
        return (latchAdd ?? true) ? .latch : .hold
    }
}

// MARK: - Scene & document — §9

struct SceneState: Codable, Equatable {
    var cells: [[Cell?]]           // [column][row], 8×8
    // (removed 2026-07: rowBypass/stackMute/stackSolo — dead since v3, never read by any engine path;
    //  old docs that still carry those keys decode fine, Codable just ignores them.)
    var stepRate: StepRate = .r1_2
    var swing: Int = 50            // 50 straight … 75 (§4 v2.3)
    // PER-PART CLOCK (Paul 2026-08-19): per-ROW overrides of the step rate + loop length, so deployed parts play at
    // independent tempos/lengths. Additive-Optional — old docs decode nil ⇒ every row uses `stepRate` / a full 8 (uniform).
    var rowStepRate: [StepRate?]? = nil   // per-row step (nil entry / nil array ⇒ the scene default)
    var rowLen: [Int?]? = nil             // per-row loop length in columns 1…8 (nil ⇒ 8)
    // PER-ROW LAP (Paul 2026-08-19): per-row column-loop mask, so the BUILD staging + perform grids loop INDEPENDENTLY
    // in one combined scene. nil ⇒ no per-row lap (the render uses the ephemeral global lap, GRID-tab behaviour).
    var rowLane: [UInt8]? = nil           // count Snap.cols when set; entry = that row's loop mask (0 = no loop)
    var tapAction: TapAction = .alt
    var quant: Quant = .off        // §6.8
    // master panel: KEY — per-scene master transpose (semitones, clamp ±12), applied to every output note.
    // Optional (append-only) → old scenes decode nil (0). PERSISTED (the key is structure).
    var masterKey: Int? = nil
    var masterKeyResolved: Int { max(-12, min(12, masterKey ?? 0)) }
    // LADDER (exclusive columns): the chosen "rung" per COLUMN — at most one cell speaks per column while LADDER
    // mode is on. Optional (append-only) → old scenes decode nil; per-column nil = "use the gentle default".
    // Scenes CAPTURE rung choices (arranged intensity). The LADDER on/off toggle itself is document-level.
    var activeRow: [Int?]? = nil
    /// The resolved rung for `col` (SINGLE / LADDER): a CHOSEN row silences the column when it is empty or −1 (user
    /// 2026-08-07: selecting an EMPTY cell mutes the column — the same "nothing speaks" as an explicit −1 deselect);
    /// a chosen row that is occupied → it; with NO choice at all → the TOPMOST occupied cell (the gentle default);
    /// an empty column → nil. Bounds-safe throughout.
    func ladderActiveRow(_ col: Int) -> Int? {
        if let ar = activeRow, col >= 0, col < ar.count, let r = ar[col] {
            if r < 0 { return nil }                                      // explicitly deselected → nothing
            return (r < 8 && cellAt(col, r) != nil) ? r : nil            // chosen: occupied → it; EMPTY → nil (mute the column)
        }
        for r in 0..<8 where cellAt(col, r) != nil { return r }          // NO choice → the topmost occupied (gentle default)
        return nil
    }

    static func empty() -> SceneState {
        SceneState(cells: Array(repeating: Array(repeating: nil, count: 8), count: 8))
    }

    /// A scene with no placed cells — the sparse "+" slot on the strip (never destroyed; just absent).
    var isEmpty: Bool { cells.allSatisfy { $0.allSatisfy { $0 == nil } } }

    /// delta §5 drag-and-drop: relocate a cell. Onto an empty slot = MOVE; onto an occupied slot = SWAP.
    /// Both are one swap of the cell structs — fields move AS-IS (MOVES NEVER REWRITE REFERENCES: inputRow
    /// is row-level, so within-row drags stay reference-safe and cross-row drags rewire meaning visibly).
    mutating func swapCells(_ a: (col: Int, row: Int), _ b: (col: Int, row: Int)) {
        guard inBounds(a.col, a.row), inBounds(b.col, b.row),
              (a.col != b.col || a.row != b.row) else { return }
        let tmp = cells[a.col][a.row]
        cells[a.col][a.row] = cells[b.col][b.row]
        cells[b.col][b.row] = tmp
    }

    /// Is (col,row) a real slot in THIS scene's grid? A decoded/ragged scene can be short of 8×8, and a UI
    /// selection can outlive its cell (a clear or a scene switch leaves a stale position), so callers must
    /// never trap on a subscript. `cellAt`/`setCell` are the bounds-safe read/write; use them off the hot path.
    func inBounds(_ col: Int, _ row: Int) -> Bool {
        col >= 0 && col < cells.count && row >= 0 && row < cells[col].count
    }
    func cellAt(_ col: Int, _ row: Int) -> Cell? { inBounds(col, row) ? cells[col][row] : nil }
    mutating func setCell(_ col: Int, _ row: Int, _ cell: Cell?) {
        guard inBounds(col, row) else { return }
        cells[col][row] = cell
    }
}

// MARK: - MACRO MODULATION (macro-panel + macro-ab-authoring specs)

/// Which bank a macro lives in. 24 macros total, banked by index: 0–7 SLIDERS · 8–15 BUTTONS · 16–23 TIMELINES.
/// SLIDER = continuous morph A→B · BUTTON = snap A|B (may carry switch/enum flips) · TIMELINE = an 8-step lane
/// drives the morph value per column (deferred). The SLIDER bank is the AU-automatable one (M1–M8).
enum MacroKind: Int, Codable { case slider = 0, button, timeline }

/// One binding target: a param on a (cell, slot) carrying its A→B **delta** (B − A, the authored depth). Deltas
/// are stored ON the binding (macro × target) so two macros can hold different B states of the same param; at
/// derivation the offsets SUM and clamp. `param` is a `MacroParam` raw value (append-only string for forward-compat).
struct MacroTarget: Codable, Equatable {
    var col: Int             // the target cell's column (0–7)
    var row: Int             // the target cell's row (0–7)
    var slot: Int            // the chain-slot index (0-based)
    var param: String        // the modulated param — a `MacroParam` raw value
    var delta: Double        // B − A, in the param's native units (may be negative = an inverted B)
}

/// The per-emitter OUTPUT role amounts a macro may modulate (the RACK's continuous amounts). Append-only.
enum MacroEmitterParam: String, Codable { case leak, duck, curve, pocket }

/// An OUTPUT binding target: a per-emitter (A–D) role amount carrying its A→B delta. Distinct from `MacroTarget`
/// (a cell/slot param) because these amounts are per-emitter GLOBAL state, folded in the builder, not per-slot.
struct MacroEmitterTarget: Codable, Equatable {
    var emitter: Int         // 0–3 (A–D)
    var param: String        // a `MacroEmitterParam` raw value
    var delta: Double        // B − A, in the amount's native units (LEAK/DUCK %, CURVE −100…100, POCKET ms)
}

/// One macro slot: a modulator that OFFSETS its targets (never rewrites their bases). Value 0 = home (nothing to
/// revert). `fixed` toggles the padlock: false = SPRING (release returns home / to the lane), true = FIXED (latched).
struct Macro: Codable, Equatable {
    var name: String = ""            // "" = unset/unnamed → renders as an INVITATION (dim/dashed +), not a dead control
    var value: Double = 0            // 0…1, unipolar; home at the foot (the offset model's soul)
    var fixed: Bool = false          // the padlock: false = SPRING (default) · true = FIXED (latched)
    var targets: [MacroTarget] = []  // CHAIN/INPUT: the A/B deltas on cell/slot params (empty = unbound)
    var emitterTargets: [MacroEmitterTarget] = []   // OUTPUT: the A/B deltas on per-emitter role amounts
    // TIMELINE lane (overlay-rule-macro-lanes spec): the playhead drives the macro's value per column. `laneOn` OFF
    // ⇒ today's manual macro. `lane` = 8 step values (0…1); `laneModes` = per-step 0 STEP · 1 SMOOTH · 2 BYPASS
    // (BYPASS ⇒ the manual value governs that column — sparse automation with honest gaps); `laneRate` indexes the
    // per-lane RATE (×8…÷8). Additive/Optional → old docs decode nil. Value = f(absolute beat × rate), replay-safe.
    var laneOn: Bool = false
    var lane: [Double]? = nil
    var laneModes: [Int]? = nil
    var laneRate: Int = 3            // index into Macro.laneRateMul (3 = ×1, the default: one step per column)

    /// The 8 lane values (0…1), nil/short-array safe.
    var laneResolved: [Double] { let a = lane ?? []; return (0..<8).map { $0 < a.count ? max(0, min(1, a[$0])) : 0 } }
    /// The 8 per-step modes (0 STEP · 1 SMOOTH · 2 BYPASS), nil/short-array safe.
    var laneModesResolved: [Int] { let a = laneModes ?? []; return (0..<8).map { $0 < a.count ? max(0, min(2, a[$0])) : 0 } }
    /// The RATE multiplier for a lane-rate index: ×8 … ×1 … ÷8 (how many lane steps advance per column).
    static let laneRateMul: [Double] = [8, 4, 2, 1, 0.5, 0.25, 0.125]
    var laneRateMulResolved: Double { let i = max(0, min(Macro.laneRateMul.count - 1, laneRate)); return Macro.laneRateMul[i] }
}

struct PluginState: Codable, Equatable {
    var formatVersion: Int = 2     // 2 = v2.x chain routing · 3 = v3.0 graph routing · 4 = + receivers (§migration)
    var colours: [Colour]
    var scenes: [SceneState]       // length 1 in v2.x; scenes are the flagship next feature
    var activeScene: Int = 0
    var morphMaster: Double = 0    // RETIRED (delta §9 item 5): param #300 stays registered (invariant 5)
                                   // but the render no longer applies it — morph is per-Colour only.
    var busChannels: [Int] = [1, 2, 3, 4]   // v3.0 (delta §7): each bus A–D stamps this channel on exit
    // delta §6a: per-emitter enable (the per-output performance mute). Optional so v2/old docs decode as
    // nil → all-enabled (the loader default); the gate lives ONLY at the emission boundary (seam rule 3).
    var busEnabled: [Bool]? = nil
    /// The four enable flags, nil/short-array safe (missing ⇒ enabled). Non-persisting read helper.
    var busEnabledResolved: [Bool] {
        let e = busEnabled ?? []
        return (0..<4).map { $0 < e.count ? e[$0] : true }
    }
    // delta §6a CLAIM: LEGACY single-claimant field (0–3), kept for lossless decode/downgrade. v2 supersedes
    // it with `claimMask`; a doc written by v2 also stamps this to the lowest claimed bus so an OLDER build
    // still reads one claimant. Suppression lives at the emission boundary against the live voice table.
    var claimEmitter: Int? = nil
    // delta §6a CLAIM v2 (2026-07-27): MULTI-claim mask — bit i set ⇒ emitter i claims (SHARED tier, claimants
    // never suppress each other; non-claimants yield the union of all claimants' sounding pitch classes).
    // Persisted. Optional → nil derives from the legacy `claimEmitter` (old docs decode unchanged).
    var claimMask: UInt8? = nil
    /// The claim mask (bits A–D), deriving from the legacy single-claimant field when unset. Non-persisting.
    var claimMaskResolved: UInt8 {
        if let m = claimMask { return m & 0b1111 }
        if let e = claimEmitter, (0..<4).contains(e) { return UInt8(1 << e) }
        return 0
    }
    // delta §6a CLAIM v2 LEAK %: per-claimant bleed — a claimed pitch class passes on non-claimants at this
    // scaled velocity (0 = full suppression = v1; the hole becomes a SHADOW). Persisted. Optional → nil = all 0.
    var claimLeak: [Int]? = nil
    /// The four LEAK amounts (0…100), nil/short-array safe (missing ⇒ 0). Non-persisting read helper.
    /// Resolve a persisted per-emitter (4-wide) Int array: clamp each element to [lo, hi], pad missing slots with
    /// `dflt`. The nil-safe read shape shared by every rack amount (claimLeak · fenceLo · pocketMs · …).
    static func resolved4(_ arr: [Int]?, _ dflt: Int, _ lo: Int, _ hi: Int) -> [Int] {
        let a = arr ?? []; return (0..<4).map { $0 < a.count ? clamp(a[$0], lo, hi) : dflt }
    }
    var claimLeakResolved: [Int] { Self.resolved4(claimLeak, 0, 0, 100) }
    // emitter role family: FLATTEN — activity ducking. While a FLATTEN emitter has anything sounding, OTHER
    // emitters' NEW note-ons arrive velocity-scaled by its amount (0…100%). Persisted (structure). Optional →
    // old docs decode nil (off). `flattenMask` = which emitters duck; `flattenAmount` = per-emitter amount.
    var flattenMask: UInt8? = nil
    var flattenAmount: [Int]? = nil
    /// The four FLATTEN amounts (0…100), nil/short-array safe (missing ⇒ 0). Non-persisting read helper.
    var flattenAmountResolved: [Int] { Self.resolved4(flattenAmount, 0, 0, 100) }
    // emitter role family: ALT — turn-taking. ALT-lit emitters form ONE group; notes fanning to the group
    // alternate among its members in position order (2 = ping-pong, 3–4 = round-robin). Persisted. `altMask`
    // = the group; `altCount` = per-emitter notes-per-turn (1…8, default 1). Optional → old docs decode nil.
    var altMask: UInt8? = nil
    var altCount: [Int]? = nil
    /// The four ALT counts (1…8), nil/short-array safe (missing ⇒ 1). Non-persisting read helper.
    var altCountResolved: [Int] { Self.resolved4(altCount, 1, 1, 8) }
    // TURNS hand-off MODE (user 2026-08-05): false/nil = PER-MOMENT (simultaneous notes all sound on the one
    // turn-holder); true = PER-NOTE (the group's emitters are TIME-EXCLUSIVE — simultaneous notes DROP all but the
    // first/leftmost, never delayed; successive onsets rotate). Document-level global; Optional → old docs decode nil.
    var turnsPerNote: Bool? = nil
    var turnsPerNoteResolved: Bool { turnsPerNote ?? false }
    // THE RACK — CURVE (design-the-rack §6, THIS VOICE family): a per-emitter velocity RE-MAP — the matching knob
    // between the grid's dynamics and the synth's response. `curveMask` = which emitters curve; `curveAmount` =
    // per-emitter −100…+100 (0 = linear, + = harder/boosts low velocities, − = softer). Persisted; Optional → old
    // docs decode nil (off). Self-affecting → gated by the rack like claim/duck/alt. (FLOOR/CEILING = later detail.)
    var curveMask: UInt8? = nil
    var curveAmount: [Int]? = nil
    /// The four CURVE amounts (−100…100), nil/short-array safe (missing ⇒ 0). Non-persisting read helper.
    var curveAmountResolved: [Int] { Self.resolved4(curveAmount, 0, -100, 100) }
    // THE RACK — FENCE (design-the-rack §6, THIS VOICE family): a per-emitter note-RANGE policy. Notes outside
    // [lo, hi] are handled by `fencePolicy` — 0 = DROP (suppress), 1 = CLAMP (to the nearest bound), 2 = FOLD
    // (octave-fold back in). `fenceMask` = which emitters fence; lo/hi = the window (0/127 default = no-op).
    // Persisted; Optional → old docs decode nil (off). Self-affecting → rack-gated. (Applied to the OUTPUT note.)
    var fenceMask: UInt8? = nil
    var fencePolicy: [Int]? = nil          // per-emitter 0=DROP · 1=CLAMP · 2=FOLD
    var fenceLo: [Int]? = nil              // per-emitter window low (0…127)
    var fenceHi: [Int]? = nil              // per-emitter window high (0…127)
    var fencePolicyResolved: [Int] { Self.resolved4(fencePolicy, 0, 0, 2) }
    var fenceLoResolved: [Int] { Self.resolved4(fenceLo, 0, 0, 127) }
    var fenceHiResolved: [Int] { Self.resolved4(fenceHi, 127, 0, 127) }
    // THE RACK — MONO (design-the-rack §6, THIS VOICE): force monophony at this output; a new note steals per
    // PRIORITY (0 = LAST · 1 = LOW · 2 = HIGH). Persisted; Optional → old docs nil (off). Self-affecting → rack-gated.
    var monoMask: UInt8? = nil
    var monoPriority: [Int]? = nil
    var monoPriorityResolved: [Int] { Self.resolved4(monoPriority, 0, 0, 2) }
    // THE RACK — POCKET (design-the-rack §6, THIS VOICE): per-output timing feel — shift this output's notes a few
    // ms ahead (push, −) or behind (lay-back, +). Persisted; Optional → nil (off). Self-affecting → rack-gated.
    var pocketMask: UInt8? = nil
    var pocketMs: [Int]? = nil          // per-emitter −50…50 ms
    var pocketMsResolved: [Int] { Self.resolved4(pocketMs, 0, -50, 50) }
    // THE RACK — CONVERSATION / LEAD·STANCE (design-the-rack §6, TOGETHER): one emitter LEADs; each other emitter's
    // STANCE admits its new notes only WITH the lead's sound (1) or AGAINST its silences (2), or FREE (0). Persisted.
    var convLead: Int? = nil            // nil/−1 = no lead; else emitter 0–3
    var convStance: [Int]? = nil        // per-emitter 0 FREE · 1 WITH · 2 AGAINST
    var convLeadResolved: Int { let l = convLead ?? -1; return (l >= 0 && l < 4) ? l : -1 }
    var convStanceResolved: [Int] { Self.resolved4(convStance, 0, 0, 2) }
    // THE RACK (design-the-rack §3, the two-tier law): the per-emitter "is the board in the signal path" gate.
    // The matrix toggles (claim/duck/alt/…) say which pedals are ARMED; this mask says whether the board is
    // patched in. Bit i clear ⇒ emitter i's whole rack is bypassed → its output is the raw wire regardless of the
    // matrix (the builder pre-ANDs this into claim/flatten/alt). Persisted (document-level, mirrors the emitter
    // family above). Optional → old docs (and clean instruments) decode nil = all ON, so existing claim/duck/alt
    // keep applying unchanged. LIVE/SOLO stay senior (the kill-switch law).
    var rackEnabledMask: UInt8? = nil
    /// The rack gate (bits A–D); missing ⇒ 0b1111 (all racks in path). Non-persisting read helper.
    var rackEnabledResolved: UInt8 { (rackEnabledMask ?? 0b1111) & 0b1111 }
    // THE CONFIG SHEETS (Paul 2026-08-20): the RACK has 4 saved CONFIGS (setups). Each config is a membership mask
    // (which emitters' boards are in-path); one is LIVE at a time. The render uses the ACTIVE config's mask. Additive-
    // Optional: a clean/old doc (rackConfigs nil) derives config 0 = the legacy `rackEnabledMask`, configs 1–3 = all-in,
    // active = 0 → `rackMaskResolved` == `rackEnabledResolved`, byte-identical. `rackEnabledMask` stays SYNCED to the
    // active config (the AU writes both) so an old reader still sees the live membership (lossless downgrade).
    var rackConfigs: [UInt8]? = nil        // 4 per-config membership masks (bits A–D)
    var rackActiveConfig: Int? = nil       // which config is LIVE (0…3)
    /// The 4 configs, resolved (a clean/old doc → config 0 is the legacy mask, the rest all-in).
    var rackConfigsResolved: [UInt8] {
        if let c = rackConfigs, c.count == 4 { return c.map { $0 & 0b1111 } }
        return [rackEnabledResolved, 0b1111, 0b1111, 0b1111]
    }
    /// Which config is live (0…3, clamped).
    var rackActiveConfigResolved: Int { max(0, min(3, rackActiveConfig ?? 0)) }
    /// The EFFECTIVE rack membership the render reads = the active config's mask.
    var rackMaskResolved: UInt8 { rackConfigsResolved[rackActiveConfigResolved] }
    // MACRO MODULATION (macro-panel spec): 24 macros in three banks (0–7 sliders · 8–15 buttons · 16–23 timelines).
    // Macros MODULATE (offset) targets at derivation; bases are NEVER rewritten, so identity/seals are unaffected
    // (performance, not edit). Values are GLOBAL v1 (not per-scene). Persisted; Optional → old docs decode nil (no
    // macros), a clean instrument gets 24 unset macros via `macrosResolved`.
    var macros: [Macro]? = nil
    /// The 24 macros, nil/short-array safe (missing ⇒ an unset `Macro`). Non-persisting read helper.
    var macrosResolved: [Macro] { let a = macros ?? []; return (0..<24).map { $0 < a.count ? a[$0] : Macro() } }
    /// The bank a macro index belongs to (0–7 sliders · 8–15 buttons · 16–23 timelines).
    static func macroKind(_ i: Int) -> MacroKind { i < 8 ? .slider : (i < 16 ? .button : .timeline) }
    // master panel: MUTE — global emission kill (PERSISTED, document-level unlike the per-scene KEY). Optional
    // → old docs decode nil (not muted). The gate lives at the emission boundary (seam rule 3).
    var masterMute: Bool? = nil
    // LADDER MODE — the exclusive-columns arm (PERSISTED, document-level; the per-scene `activeRow` holds WHICH
    // rung). While on, at most one cell speaks per column. Optional → old docs decode nil (off). Mirrors masterMute.
    var ladderMode: Bool? = nil
    var ladderModeResolved: Bool { ladderMode ?? false }
    // BUILD: the single UNASSIGNED workshop part, saved with the document (Paul 2026-08-16). Additive-Optional →
    // old saves decode as nil. Populated at save time from the live workshop; restored into BUILD @State on load.
    var buildUnassigned: BuildUnassignedData? = nil
    // receiver strip: the THRU pip — a PERSISTED one-of-4 radio (structure persists). Passthrough (CC/PB/AT +
    // stopped-note soundcheck) follows THIS receiver, superseding the hardwired follows-R1 rule. Optional so
    // old docs decode nil ⇒ default R1 (index 0). Mirrors claimEmitter's persist-and-radio shape.
    var thruReceiver: Int? = nil
    // delta §9 item 11: the four document-level MIDI receivers (shared named inputs). Optional so pre-
    // receiver docs decode as nil and get four synthesized by synthesizeReceiversIfNeeded() on load.
    var receivers: [Receiver]? = nil
    /// The four receivers, nil/short-array safe (missing ⇒ OMNI). Non-persisting read helper.
    var receiversResolved: [Receiver] {
        let r = receivers ?? []
        return (0..<4).map { $0 < r.count ? r[$0] : Receiver(name: "\($0 + 1)") }
    }
    /// The THRU-pip receiver index, nil-safe + clamped (missing ⇒ R1). Non-persisting read helper.
    var thruReceiverResolved: Int { min(3, max(0, thruReceiver ?? 0)) }

    /// A copy with one ACTIVE-scene cell forced to `cell` (nil = empty). Used to STRIP the live staging
    /// preview from the encoded preset: the preview is placed into the document transiently (so it sounds
    /// in context), so a host autosave landing mid-hover must encode the RESTORED cell, never the preview.
    /// Bounds-guarded → returns self unchanged for an out-of-range address.
    func restoringCell(col: Int, row: Int, to cell: Cell?) -> PluginState {
        guard activeScene >= 0, activeScene < scenes.count,
              col >= 0, col < scenes[activeScene].cells.count, row >= 0, row < scenes[activeScene].cells[col].count else { return self }
        var s = self
        s.scenes[activeScene].cells[col][row] = cell
        return s
    }

    // MARK: - MULTI-SCENE (2026-07-27) — the scene strip switches activeScene within one document

    static let maxScenes = 16          // the strip's fixed slot count (16 — the scene row sits on its own line below the header)

    /// The active scene index, always in-bounds (clamped; falls back to 0 if the doc is odd). Never crashes.
    var activeSceneResolved: Int { scenes.isEmpty ? 0 : max(0, min(scenes.count - 1, activeScene)) }
    /// The active scene (bounds-safe), for the render + UI.
    var activeSceneState: SceneState { scenes.isEmpty ? .empty() : scenes[activeSceneResolved] }

    /// Extend `scenes` to exactly `n` fixed slots (padding with empty "+" scenes). Idempotent; never shrinks
    /// below the current count. The strip is a fixed 16 slots, so old length-1 docs pad to 16 on load.
    mutating func padScenes(to n: Int = maxScenes) {
        if scenes.isEmpty { scenes = [.empty()] }
        while scenes.count < n { scenes.append(.empty()) }
    }
    /// SAVE-HERE: copy the ACTIVE scene into slot `i` (self-advertising save-as on an empty +), padding first.
    /// Precious-scene law: this is the ONLY write onto a slot; drag SWAPs, never overwrites (see the strip).
    mutating func saveCurrentScene(toSlot i: Int) {
        guard i >= 0, i < Self.maxScenes else { return }
        padScenes(to: max(i + 1, scenes.count))
        scenes[i] = activeSceneState
    }
    /// Switch the active scene to a NON-EMPTY slot. Empty slots aren't playable (they're + save targets).
    mutating func switchScene(to i: Int) {
        guard i >= 0, i < scenes.count, !scenes[i].isEmpty else { return }
        activeScene = i
    }

    // MARK: - S3: drag on the strip = MOVE / SWAP / DELETE (never overwrite — the precious-scene law)

    /// DRAG a scene onto another slot. The model decides: EMPTY target = MOVE (relocate; source empties);
    /// OCCUPIED target = SWAP (exchange). Never an overwrite. The active (playing) scene follows its content.
    mutating func dragScene(from a: Int, to b: Int) {
        guard a != b, scenes.indices.contains(a), scenes.indices.contains(b), !scenes[a].isEmpty else { return }
        if scenes[b].isEmpty { moveScene(from: a, to: b) } else { swapScenes(a, b) }
    }
    /// MOVE onto an empty slot: the scene relocates, the source becomes empty. The active index follows.
    mutating func moveScene(from a: Int, to b: Int) {
        guard a != b, scenes.indices.contains(a), scenes.indices.contains(b), scenes[b].isEmpty else { return }
        let act = activeSceneResolved
        scenes[b] = scenes[a]; scenes[a] = .empty()
        if act == a { activeScene = b }
    }
    /// SWAP two slots (exchange — never overwrite). The active (playing) scene follows its content to its new slot.
    mutating func swapScenes(_ a: Int, _ b: Int) {
        guard a != b, scenes.indices.contains(a), scenes.indices.contains(b) else { return }
        let act = activeSceneResolved
        scenes.swapAt(a, b)
        if act == a { activeScene = b } else if act == b { activeScene = a }
    }
    /// DELETE a scene (the trash). The ACTIVE scene REFUSES — the instrument always has a playing scene.
    /// Returns false (rejected) when the slot is the active one, empty, or out of range — the UI shakes on false.
    @discardableResult mutating func deleteScene(_ i: Int) -> Bool {
        guard scenes.indices.contains(i), i != activeSceneResolved, !scenes[i].isEmpty else { return false }
        scenes[i] = .empty()
        return true
    }

    /// Migrate a legacy (v2.x) document to the v3.0 routing schema, in place. Idempotent and gated
    /// on formatVersion, so it is safe to call on every document entering the AU (load / factory /
    /// test session). Mapping (migration-tree-routing.md §1): a cell fed under the old model — i.e.
    /// the cell ABOVE is occupied and its `stack` is on — references that row (`inputRow = r-1`);
    /// everything else is MIDI IN (nil). `srcMix` has no v3 equivalent and is dropped (logged).
    /// The old `stack`/`srcMix` fields are LEFT in place but are read ONLY by this migration now —
    /// the commit-3 flip made `resolvedParent` the live routing path (the router no longer reads `stack`).
    mutating func migrateLegacyRoutingIfNeeded() {
        if formatVersion < 3 {
            var droppedSrcMix = 0
            for si in scenes.indices {
                for col in scenes[si].cells.indices {
                    for row in scenes[si].cells[col].indices {
                        guard var cell = scenes[si].cells[col][row] else { continue }
                        let aboveStacked = row > 0 && (scenes[si].cells[col][row - 1]?.stack ?? false)
                        cell.inputRow = aboveStacked ? row - 1 : nil
                        if cell.srcMix { droppedSrcMix += 1 }
                        scenes[si].cells[col][row] = cell
                    }
                }
            }
            if droppedSrcMix > 0 {
                print("MidiSpark: migrated v2 document to graph routing; dropped +SRC on \(droppedSrcMix) cell(s) (no v3 equivalent).")
            }
            formatVersion = 3
        }
        synthesizeReceiversIfNeeded()   // delta §9 item 11 — runs for v3 docs too (they have no receivers yet)
        migrateColourPairsIfNeeded()    // delta item 8 — fold each Colour's partner into its own procB
        padScenes()                     // MULTI-SCENE: a fixed 16-slot strip — old length-1 docs pad with empties
    }

    /// delta item 8 (TWO-PROCESSOR Colours): fold the retired pair reference into each Colour's own procB.
    /// Idempotent, gated on formatVersion < 5. For a Colour with a valid `altColour` partner: copy the
    /// partner's type/params/transpose into procB (typeB/paramsB/transposeB), overwriting any stale paramsB.
    /// `altColour` is LEFT in place (decode-only legacy) so an older build re-loading a migrated doc still
    /// reads the pair — lossless downgrade. The new render sources B ONLY from typeB, so keeping altColour is
    /// inert. Reads partner.type/paramsA/transpose (never written here) so in-place mutation is safe.
    mutating func migrateColourPairsIfNeeded() {
        guard formatVersion < 5 else { return }
        var migrated = 0
        for i in colours.indices {
            guard let pi = colours[i].altColour, pi >= 0, pi < colours.count, pi != i else { continue }
            colours[i].typeB = colours[pi].type
            colours[i].paramsB = colours[pi].paramsA
            colours[i].transposeB = colours[pi].transpose
            migrated += 1
        }
        if migrated > 0 {
            print("MidiSpark: migrated \(migrated) Colour pair(s) into internal procB (delta item 8).")
        }
        formatVersion = 5
    }

    /// delta §9 item 11: promote per-cell input-channel filters to four shared RECEIVERS. Idempotent
    /// (gated on `receivers == nil`), runs on every doc entering the AU. Distinct MIDI-IN channel filters
    /// are collected in ORDER OF APPEARANCE → up to 4 receivers (Receiver 1 = the first, usually OMNI 0);
    /// >4 distinct collapse the overflow to Receiver 1 + log. Each MIDI-IN cell is pointed at the receiver
    /// matching its old filter. OMNI (the overwhelming default) → Receiver 1 ⇒ clean, band-free grids.
    mutating func synthesizeReceiversIfNeeded() {
        if receivers == nil {
            var distinct: [Int] = []
            for scene in scenes {
                for col in scene.cells {
                    for maybe in col {
                        guard let cell = maybe, cell.inputRow == nil else { continue }   // MIDI-IN cells only
                        let ch = max(0, min(16, cell.inputChannel))
                        if !distinct.contains(ch) { distinct.append(ch) }
                    }
                }
            }
            if distinct.isEmpty { distinct = [0] }                       // no MIDI-IN cells → a lone OMNI receiver
            let overflow = max(0, distinct.count - 4)
            if overflow > 0 { distinct = Array(distinct.prefix(4)) }
            var recs = distinct.enumerated().map { Receiver(name: "\($0.offset + 1)", channel: $0.element) }
            while recs.count < 4 { recs.append(Receiver(name: "\(recs.count + 1)")) }   // pad to 4 (OMNI)
            receivers = recs
            if overflow > 0 {
                print("MidiSpark: synthesized receivers; \(overflow) overflow input channel(s) collapsed to Receiver 1.")
            }
            formatVersion = max(formatVersion, 4)
        }
        // Point every UNPOINTED MIDI-IN cell at the receiver matching its channel (R1 on no match). This runs
        // ALWAYS (idempotent — only nil cells), so a v3 doc built with receivers PRE-SET but cells left nil is
        // repaired too — else those cells fall to the legacy per-cell filter and bypass receiver MUTE while
        // playing (delta §9 item 11 mute ruling 2026-07-26).
        guard let recs = receivers else { return }
        for si in scenes.indices {
            for col in scenes[si].cells.indices {
                for row in scenes[si].cells[col].indices {
                    guard var cell = scenes[si].cells[col][row],
                          cell.inputRow == nil, cell.inputReceiver == nil else { continue }
                    let ch = max(0, min(16, cell.inputChannel))
                    cell.inputReceiver = recs.firstIndex(where: { $0.channel == ch }) ?? 0   // overflow → R1
                    scenes[si].cells[col][row] = cell
                }
            }
        }
    }

    /// D1: mark a Colour DEFINED iff it is painted in some scene — so a fresh factory/arc ships a SPARSE palette
    /// (only the used Colours as chips; the rest are "+" slots). Old saved docs (`defined == nil`) are untouched.
    mutating func markDefinedFromUsage() {
        let used = Set(scenes.flatMap { $0.cells.flatMap { $0.compactMap { $0?.colourID } } })
        for i in colours.indices { colours[i].defined = used.contains(colours[i].colourID) }
    }

    static func factory() -> PluginState {
        var colours = colourIDs.map { Colour(colourID: $0, type: .arp) }
        // A few designed defaults so the factory session sounds immediately (§6.6). (Old paramsB ALT
        // demos dropped — the pair model sets ALT via a partner Colour; re-author as a follow-up.)
        func idx(_ id: String) -> Int { colourIDs.firstIndex(of: id)! }
        colours[idx("gold")].paramsA.octaves = 2
        colours[idx("cyan")].type = .ratchet
        colours[idx("cyan")].paramsA.count = 4
        colours[idx("vermilion")].type = .passgate
        colours[idx("magenta")].transpose = 12

        var scene = SceneState.empty()
        scene.cells[0][0] = Cell(colourID: "gold")
        scene.cells[2][0] = Cell(colourID: "vermilion")
        scene.cells[2][1] = Cell(colourID: "magenta", buses: [.b], inputRow: 0)   // references row 0 (§1)
        scene.cells[4][0] = Cell(colourID: "gold")
        scene.cells[6][0] = Cell(colourID: "cyan")
        var state = PluginState(colours: colours, scenes: [scene])
        state.formatVersion = 4   // built directly in the v3.0 graph model + receivers
        // Synthesize the four receivers AND POINT every MIDI-IN cell at one — the initial document + store are
        // built straight from factory() (no migrate pass), so without this the cells would keep inputReceiver=nil
        // and bypass receiver MUTE (delta §9 item 11).
        state.synthesizeReceiversIfNeeded()
        // Default routing (2026-07-27): receiver A = OMNI so the instrument works out of the box for the
        // one-keyboard majority (any channel is heard); B/C/D filter ch 2/3/4 so multi-source rigs are ready
        // without stranding the common case. Only the factory default changes here — old-doc migration keeps
        // synthesizing OMNI pads (never invents absent filters).
        for i in state.receivers!.indices { state.receivers![i].channel = i == 0 ? 0 : i + 1 }
        state.padScenes()   // MULTI-SCENE: slot 0 = the designed scene, slots 1–15 empty (+) — the strip is 16
        state.markDefinedFromUsage()   // D1: sparse palette — only the painted Colours are defined chips
        return state
    }

    /// INIT — a blank starting point (user 2026-08-09): the 16-colour palette + 4 receivers (R1 OMNI · B/C/D ch 2/3/4)
    /// + ONE EMPTY scene, NO cells placed. Set as the FACTORY DEFAULT (what a fresh instance loads); the DEFAULT ARC
    /// + curriculum stay available as named presets.
    static func makeInit() -> PluginState {
        var state = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        state.formatVersion = 4
        state.synthesizeReceiversIfNeeded()
        for i in state.receivers!.indices { state.receivers![i].channel = i == 0 ? 0 : i + 1 }
        // Start with ONE colour on the grid (user 2026-08-09): so the DRAG&DROP palette shows a single colour and
        // there is a piece to drag onto an empty slot (FORK → a new colour). GOLD, plain passthrough, top row.
        // SUBSCRIBE to R1 (inputReceiver 0) so the default cells hear R1's LATCH/PIANO frozen pool, not just live —
        // a nil receiver reads live OMNI only (resolvedReceiver = −1), so a latched chord never reaches them. R1 is
        // OMNI here, so live input is identical. (fix 2026-08-10: PIANO latch "nothing plays" on a fresh instance.)
        for c in 0..<4 { state.scenes[0].cells[c][0] = { var cell = Cell(colourID: "gold", buses: [.a]); cell.inputReceiver = 0; return cell }() }
        state.padScenes()
        state.markDefinedFromUsage()   // one used Colour (GOLD) → palette shows GOLD + fifteen "+" slots
        return state
    }

    /// §3b/3c THE DEFAULT ARC — the first-launch state: THREE musical scenes (arps → +elements → EPIC), all
    /// SINGLE-EMITTER (everything → A, ch1) so the first-try one-synth rig is always audible (the minimum-rig
    /// law). Each cell is an independent treatment of the held chord (MIDI-IN via R1/OMNI) summing to A — the
    /// one-chord orchestra. Content is a sensible first cut; ear-tuning happens on device.
    static func defaultArc() -> PluginState {
        var colours = colourIDs.map { Colour(colourID: $0, type: .arp) }
        func set(_ id: String, _ f: (inout Colour) -> Void) { f(&colours[colourIDs.firstIndex(of: id)!]) }
        // The arc's palette: arps at different patterns/rates/octaves + a harmonize bloom + a chance shimmer + a bass.
        set("gold")      { $0.type = .arp; $0.paramsA.pattern = .up;     $0.paramsA.rate = .r1_16; $0.paramsA.octaves = 1 }
        set("cyan")      { $0.type = .arp; $0.paramsA.pattern = .upDown; $0.paramsA.rate = .r1_8 }
        set("azure")     { $0.type = .arp; $0.paramsA.pattern = .up;     $0.paramsA.rate = .r1_16; $0.paramsA.octaves = 2 }  // sparkle up
        set("slate")    { $0.type = .arp; $0.paramsA.pattern = .up;     $0.paramsA.rate = .r1_8;  $0.transpose = -12 }       // bass octave down
        set("magenta")   { $0.type = .harmonize; $0.paramsA.harmIntervals = [4, 7, 0]; $0.paramsA.harmVelScale = 0.7 }        // + third + fifth bloom
        set("teal")      { $0.type = .chance; $0.paramsA.probability = 0.6 }                                                  // shimmer

        // Scene 1 — a series of arps, an interesting pattern
        var s1 = SceneState.empty()
        s1.cells[0][0] = Cell(colourID: "gold")
        s1.cells[2][0] = Cell(colourID: "cyan")
        s1.cells[4][0] = Cell(colourID: "gold")
        s1.cells[6][0] = Cell(colourID: "azure")

        // Scene 2 — adds elements (a bass octave + a harmonize bloom under the arps)
        var s2 = s1
        s2.cells[0][1] = Cell(colourID: "slate")
        s2.cells[4][1] = Cell(colourID: "magenta")

        // Scene 3 — EPIC: dense · OCT register spread · harmonize + chance shimmer · rhythmic interlock (all → A)
        var s3 = SceneState.empty()
        for c in [0, 2, 4, 6] { s3.cells[c][0] = Cell(colourID: "gold") }
        for c in [1, 3, 5, 7] { s3.cells[c][0] = Cell(colourID: "azure") }
        s3.cells[0][1] = Cell(colourID: "slate"); s3.cells[4][1] = Cell(colourID: "slate")
        s3.cells[2][1] = Cell(colourID: "magenta"); s3.cells[6][1] = Cell(colourID: "magenta")
        s3.cells[3][2] = Cell(colourID: "teal");   s3.cells[7][2] = Cell(colourID: "teal")

        var state = PluginState(colours: colours, scenes: [s1, s2, s3])
        state.formatVersion = 4
        state.synthesizeReceiversIfNeeded()                         // point every MIDI-IN cell at a receiver (R1)
        for i in state.receivers!.indices { state.receivers![i].channel = i == 0 ? 0 : i + 1 }   // A=OMNI, B/C/D=2/3/4
        state.padScenes()                                           // slots 3…7 = +
        state.markDefinedFromUsage()                                // D1: sparse palette — only the arc's Colours are defined
        return state
    }

    // MARK: - THE LADDER family (factory presets, Docs/AcceptanceCriteria-ladder.md §PART 2). Each is a full 8×8
    // "instrument": one machine per ROW, gentle (top) → intense (bottom), stamped as 8 twins per column; LADDER
    // mode ON; 3 SCENES = intensity curves (the active rung per column) over the SAME grid; single emitter A · ch1
    // (minimum rig); HARM (where present) is +12 octave only. Slot helpers:
    private static func lArp(_ pat: ArpPattern, _ rate: ArpRate, oct: Int, gate: Double, legato: Bool = false) -> ProcessorSlot {
        var p = ColourParams(); p.pattern = pat; p.rate = rate; p.octaves = oct; p.gate = gate
        if legato { p.phase = .legato }
        return ProcessorSlot(type: .arp, params: p)
    }
    private static func lPass(_ gate: Double, legato: Bool = true) -> ProcessorSlot {
        var p = ColourParams(); p.gate = gate; if legato { p.phase = .legato }
        return ProcessorSlot(type: .passgate, params: p)
    }
    private static func lHarm12() -> ProcessorSlot { var p = ColourParams(); p.harmIntervals = [12, 0, 0]; return ProcessorSlot(type: .harmonize, params: p) }
    private static func lRtc(_ count: Int) -> ProcessorSlot { var p = ColourParams(); p.count = count; return ProcessorSlot(type: .ratchet, params: p) }
    private static func lChnc(_ prob: Double) -> ProcessorSlot { var p = ColourParams(); p.probability = prob; return ProcessorSlot(type: .chance, params: p) }
    /// A configured ECHO (delay) slot — synced 16th-note divisions by default (user 2026-08-08 delay controls).
    static func lEcho(div: Int = 4, repeats: Int = 4, feedDelay: Double = 0.7, decay: Double = 0.5,
                      offset: Double = 0, pitch: Int = 0, thru: Bool = true, sync: Bool = true, ms: Double = 250) -> ProcessorSlot {
        var p = ColourParams()
        p.echoSync = sync; p.echoDelayDiv = div; p.echoDelayMs = ms; p.echoRepeats = repeats
        p.echoFeedDelay = feedDelay; p.echoDecay = decay; p.echoOffset = offset; p.echoPitch = pitch; p.echoThru = thru
        return ProcessorSlot(type: .echo, params: p)
    }

    /// Build a LADDER preset from 8 rung HUES (light→dark), 8 MACHINES (chains, row 0 = gentlest), and the scene
    /// CURVES (each an 8-entry per-column active row). All rungs → Emit A on R1; the grid is identical per scene.
    private static func ladderPreset(_ hues: [String], _ machines: [[ProcessorSlot]], _ curves: [[Int]]) -> PluginState {
        var grid = SceneState.empty()
        for col in 0..<8 { for row in 0..<8 {
            var c = Cell(colourID: hues[row]); c.inputReceiver = 0; c.buses = [.a]; c.processors = machines[row]
            grid.cells[col][row] = c
        } }
        let scenes = curves.map { curve -> SceneState in var s = grid; s.activeRow = curve.map { Optional($0) }; return s }
        var state = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: scenes)
        state.ladderMode = true; state.formatVersion = 4
        state.synthesizeReceiversIfNeeded()
        for i in state.receivers!.indices { state.receivers![i].channel = 0 }   // OMNI in; output = Emit A · ch1
        state.padScenes(); state.markDefinedFromUsage()
        return state
    }

    /// THE LADDER — the flagship (§PART 2): R1 STILL → R8 STORM. Warm gold → deep indigo.
    static func makeLadder() -> PluginState {
        ladderPreset(
            ["gold", "slate", "orange", "vermilion", "wine", "purple", "violet", "indigo"],
            [[lPass(1.0)],                                                        // R1 STILL — the held-chord bed
             [lArp(.up, .r1_4, oct: 1, gate: 0.92, legato: true)],               // R2 ROLL
             [lArp(.up, .r1_8, oct: 1, gate: 0.70)],                             // R3 PULSE
             [lArp(.upDown, .r1_8, oct: 2, gate: 0.65)],                         // R4 WEAVE
             [lArp(.up, .r1_16, oct: 2, gate: 0.55)],                            // R5 CLIMB
             [lHarm12(), lArp(.up, .r1_16, oct: 3, gate: 0.50)],                 // R6 SHINE
             [lArp(.up, .r1_16, oct: 2, gate: 0.45), lRtc(4)],                   // R7 GATLING (RTC drives)
             [lHarm12(), lArp(.random, .r1_32, oct: 4, gate: 0.30), lChnc(0.55)]],   // R8 STORM
            [[0, 1, 0, 1, 0, 1, 0, 1], [2, 2, 3, 3, 4, 4, 3, 3], [7, 5, 6, 5, 7, 5, 6, 6]])
    }

    /// TIDE — a flowing UP-DOWN ladder, calm → churning. Cool mint → violet.
    static func makeLadderTide() -> PluginState {
        ladderPreset(
            ["mint", "cyan", "green", "teal", "azure", "indigo", "purple", "violet"],
            [[lPass(1.0)],
             [lArp(.upDown, .r1_4, oct: 1, gate: 0.90, legato: true)],
             [lArp(.upDown, .r1_8, oct: 1, gate: 0.72)],
             [lArp(.upDown, .r1_8, oct: 2, gate: 0.62)],
             [lArp(.upDown, .r1_16, oct: 2, gate: 0.55)],
             [lArp(.upDown, .r1_16, oct: 3, gate: 0.50)],
             [lArp(.upDown, .r1_16t, oct: 3, gate: 0.45)],
             [lHarm12(), lArp(.upDown, .r1_32, oct: 4, gate: 0.35), lChnc(0.60)]],
            [[0, 1, 1, 0, 0, 1, 1, 0], [3, 4, 3, 2, 3, 4, 3, 2], [5, 6, 7, 6, 5, 6, 7, 6]])
    }

    /// FORGE — mechanical RATCHET bursts, humming → hammering. Hot chartreuse → purple.
    static func makeLadderForge() -> PluginState {
        ladderPreset(
            ["chartreuse", "gold", "slate", "orange", "vermilion", "wine", "magenta", "purple"],
            [[lPass(1.0)],
             [lArp(.up, .r1_8, oct: 1, gate: 0.62)],
             [lArp(.up, .r1_8, oct: 1, gate: 0.55), lRtc(2)],
             [lArp(.up, .r1_16, oct: 2, gate: 0.50), lRtc(3)],
             [lArp(.down, .r1_16, oct: 2, gate: 0.48), lRtc(4)],
             [lArp(.up, .r1_16, oct: 3, gate: 0.45), lRtc(4)],
             [lArp(.up, .r1_16t, oct: 3, gate: 0.42), lRtc(6)],
             [lArp(.random, .r1_32, oct: 3, gate: 0.32), lRtc(8), lChnc(0.55)]],
            [[0, 0, 1, 1, 0, 0, 1, 1], [2, 3, 4, 3, 2, 3, 4, 3], [6, 7, 7, 6, 6, 7, 7, 6]])
    }

    /// CHIME — octave-doubled bells, sparse → radiant (HARM +12 on every rung). Mint → indigo.
    static func makeLadderChime() -> PluginState {
        ladderPreset(
            ["mint", "chartreuse", "gold", "blush", "magenta", "purple", "violet", "indigo"],
            [[lPass(1.0)],
             [lHarm12(), lPass(0.95)],
             [lHarm12(), lArp(.up, .r1_8, oct: 1, gate: 0.70)],
             [lHarm12(), lArp(.up, .r1_8, oct: 2, gate: 0.62)],
             [lHarm12(), lArp(.upDown, .r1_16, oct: 2, gate: 0.55)],
             [lHarm12(), lArp(.up, .r1_16, oct: 3, gate: 0.50)],
             [lHarm12(), lArp(.up, .r1_16, oct: 3, gate: 0.45), lChnc(0.70)],
             [lHarm12(), lArp(.random, .r1_32, oct: 4, gate: 0.35), lChnc(0.55)]],
            [[1, 0, 0, 0, 0, 0, 0, 1], [3, 4, 5, 4, 3, 4, 5, 4], [5, 6, 7, 7, 6, 5, 6, 7]])
    }

    /// SPARK — generative, CHANCE-thinned, sparse → chaotic. Electric mint → wine.
    static func makeLadderSpark() -> PluginState {
        ladderPreset(
            ["mint", "cyan", "chartreuse", "azure", "magenta", "purple", "vermilion", "wine"],
            [[lPass(1.0)],
             [lArp(.up, .r1_8, oct: 1, gate: 0.65), lChnc(0.80)],
             [lArp(.up, .r1_16, oct: 1, gate: 0.55), lChnc(0.70)],
             [lArp(.upDown, .r1_16, oct: 2, gate: 0.50), lChnc(0.65)],
             [lArp(.random, .r1_16, oct: 2, gate: 0.50), lChnc(0.60)],
             [lArp(.random, .r1_16, oct: 3, gate: 0.45), lChnc(0.55)],
             [lHarm12(), lArp(.random, .r1_16t, oct: 3, gate: 0.45), lChnc(0.55)],
             [lHarm12(), lArp(.random, .r1_32, oct: 4, gate: 0.35), lChnc(0.45)]],
            [[0, 2, 0, 1, 0, 2, 0, 1], [3, 5, 4, 2, 4, 5, 3, 4], [7, 4, 6, 7, 5, 7, 4, 6]])
    }

    /// MIDI DELAYS (user 2026-08-08) — eight delay flavours, one per ROW, placed in COLUMN 0 only so each rings out
    /// across the empty columns. SINGLE mode: one flavour speaks at a time (switch with the row selectors); three
    /// scenes preset SLAP · DUB · CANYON. Hold a chord and hear the delay; the flavours span slap → dub → pitch → wide.
    static func makeDelays() -> PluginState {
        let hues = ["gold", "orange", "vermilion", "wine", "magenta", "purple", "violet", "indigo"]
        let machines: [[ProcessorSlot]] = [
            [lEcho(div: 3, repeats: 1, feedDelay: 0.85, decay: 0)],                 // R1 SLAP — one quick echo
            [lEcho(div: 2, repeats: 3, feedDelay: 0.8,  decay: 0.5)],               // R2 DOUBLE — 1/8, a few taps
            [lEcho(div: 3, repeats: 4, feedDelay: 0.75, decay: 0.55)],              // R3 DOTTED — dotted-note swing
            [lEcho(div: 4, repeats: 4, feedDelay: 0.75, decay: 0.6)],               // R4 QUARTER — one per beat
            [lEcho(div: 4, repeats: 12, feedDelay: 0.7, decay: 0.85)],              // R5 DUB — long decay tail
            [lEcho(div: 2, repeats: 6, feedDelay: 0.7,  decay: 0.6, pitch: 3)],     // R6 RISER — climbing +3
            [lEcho(div: 2, repeats: 6, feedDelay: 0.7,  decay: 0.6, pitch: -3)],    // R7 FALLER — descending −3
            [lEcho(div: 8, repeats: 3, feedDelay: 0.75, decay: 0.7, offset: 0.2)]]  // R8 CANYON — half-note, wide
        var grid = SceneState.empty()
        for row in 0..<8 {
            var c = Cell(colourID: hues[row]); c.inputReceiver = 0; c.buses = [.a]; c.processors = machines[row]
            grid.cells[0][row] = c   // COLUMN 0 only — the delay tail rings out across the empty columns
        }
        let scenes = [0, 4, 7].map { pick -> SceneState in    // SLAP · DUB · CANYON
            var s = grid; var ar = [Int?](repeating: nil, count: 8); ar[0] = pick; s.activeRow = ar; return s
        }
        var state = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: scenes)
        state.ladderMode = true; state.formatVersion = 4
        state.synthesizeReceiversIfNeeded()
        for i in state.receivers!.indices { state.receivers![i].channel = 0 }   // OMNI in; output = Emit A · ch1
        state.padScenes(); state.markDefinedFromUsage()
        return state
    }
}

// MARK: - MODELESS EDIT scope (2026-07-27) — scope-after-target: THIS · ALL IDENTICAL · ALL <COLOUR>

extension SceneState {
    enum EditScope { case thisOne, allIdentical, allColour, twins }

    /// The cells an EDIT at `(col,row)` should touch under `scope`, as encoded positions (col*8 + row), sorted.
    /// ALL IDENTICAL = same Colour AND same routing (input source + emitter buses); ALL COLOUR = same Colour.
    /// An empty exemplar ⇒ []. Pure — the counted-chip + flash-set truth behind "EDITING n · ALL GOLD".
    func editScopeTargets(col: Int, row: Int, scope: EditScope) -> [Int] {
        guard col >= 0, col < 8, row >= 0, row < 8, col < cells.count, row < cells[col].count,
              let ex = cells[col][row] else { return [] }
        var out: [Int] = []
        for c in 0..<8 where c < cells.count {
            for r in 0..<8 where r < cells[c].count {
                guard let cell = cells[c][r] else { continue }
                let hit: Bool
                switch scope {
                case .thisOne:      hit = c == col && r == row
                case .allColour:    hit = cell.colourID == ex.colourID
                case .allIdentical: hit = cell.colourID == ex.colourID && cell.inputRow == ex.inputRow
                                        && cell.inputReceiver == ex.inputReceiver && cell.buses == ex.buses
                case .twins:        // TWINS: full editable config equal (colour + chain + input + output +
                                    // source-shaping); transient perform state (alt/muted/bypassed) ignored.
                                    hit = cell.colourID == ex.colourID && cell.processors == ex.processors
                                        && cell.inputReceiver == ex.inputReceiver && cell.inputRow == ex.inputRow
                                        && cell.buses == ex.buses && cell.chordSplit == ex.chordSplit
                                        && cell.velWindow == ex.velWindow && cell.chop == ex.chop
                }
                if hit { out.append(c * 8 + r) }
            }
        }
        return out.sorted()
    }

    /// Apply `edit` to every cell in the EDIT scope — the propagation multiplier the write-armed panel commits.
    mutating func applyToScope(col: Int, row: Int, scope: EditScope, _ edit: (inout Cell) -> Void) {
        for key in editScopeTargets(col: col, row: row, scope: scope) {
            let c = key / 8, r = key % 8
            if var cell = cells[c][r] { edit(&cell); cells[c][r] = cell }
        }
    }

    // MARK: - §11 VERB LOGIC (the testable model ops behind the round verbs; PLACE stamps a Cell directly)

    /// DELETE — remove the cell at (col,row). (Grid-chaining retired: no cell reads another's row, so there are no
    /// children to re-point — a plain removal. The name stays `deleteCellSever` for the live DELETE verb caller.)
    mutating func deleteCellSever(col: Int, row: Int) {
        guard cells.indices.contains(col), cells[col].indices.contains(row) else { return }
        cells[col][row] = nil
    }

    // MARK: - ROUTING (receiver in · emitters out; the UI projection lights + taps these)

    /// ROUTE IN (single-select radio) — feed cell X from a RECEIVER door: inputRow = nil, inputReceiver = r (0–3).
    mutating func routeInReceiver(col: Int, row: Int, receiver: Int) {
        guard cells.indices.contains(col), cells[col].indices.contains(row), var c = cells[col][row] else { return }
        c.inputRow = nil; c.inputReceiver = max(0, min(3, receiver)); cells[col][row] = c
    }
    /// ROUTE OUT emitters — toggle cell X's membership of an emitter bus (multi).
    mutating func toggleEmitter(col: Int, row: Int, bus: Bus) {
        guard cells.indices.contains(col), cells[col].indices.contains(row), var c = cells[col][row] else { return }
        if c.buses.contains(bus) { c.buses.remove(bus) } else { c.buses.insert(bus) }
        cells[col][row] = c
    }
}

// MARK: - Session template / clipboard (delta §5) — one STAMP object

/// The session-scoped TEMPLATE = CLIPBOARD (one stamp object, delta §5): a cell's full config minus its
/// perform state. Written by committing a cell in the editor AND by COPY; read by the empty-cell pre-fill
/// and the split-paste actions. Ephemeral (never persisted). Bootstrap = the desk Colour + ⇐MIDI(R1) →A.
struct StampConfig: Equatable {
    var colourID: String
    var inputRow: Int? = nil        // a row reference; nil = MIDI-IN via the receiver below
    var inputReceiver: Int = 0      // 0–3, used when inputRow == nil
    var buses: Set<Bus> = [.a]

    static func bootstrap(colourID: String) -> StampConfig { StampConfig(colourID: colourID) }
    static func from(_ c: Cell) -> StampConfig {
        StampConfig(colourID: c.colourID, inputRow: c.inputRow, inputReceiver: c.inputReceiver ?? 0, buses: c.buses)
    }
    /// A fresh cell carrying this config (perform state defaulted).
    func makeCell() -> Cell {
        var c = Cell(colourID: colourID); applyRouting(to: &c); return c
    }
    /// Overwrite a cell's ROUTING (input source + output buses) from this config; colour + perform
    /// state untouched. Shared by `makeCell` and the staging live-propagation to the placed cells.
    func applyRouting(to c: inout Cell) {
        c.inputRow = inputRow; c.inputReceiver = inputReceiver; c.buses = buses
    }
}

// MARK: - Undo/redo (delta §5 / a6) — a bounded document-value stack

/// A bounded past/future stack of document VALUES for undo/redo (delta §5). `record` is called BEFORE a
/// mutation with the CURRENT (pre-mutation) value: it pushes onto the past, clears the redo future, and
/// caps the depth. A `coalesceKey` collapses a run of same-key records (a continuous gesture = one step):
/// the FIRST record of the run captures the pre-gesture value, later same-key records don't push again.
/// `undo`/`redo` take the live value and return the value to restore (moving the live one to the other
/// side). Pure and Foundation-only, so it unit-tests off-device; the AU owns the mutation choke point.
struct UndoStack<T: Equatable>: Equatable {
    private(set) var past: [T] = []
    private(set) var future: [T] = []
    private var lastKey: String? = nil
    let cap: Int

    init(cap: Int = 50) { self.cap = max(1, cap) }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func record(_ current: T, coalesceKey: String? = nil) {
        future.removeAll()                                   // a fresh edit invalidates the redo branch
        if let k = coalesceKey, k == lastKey, !past.isEmpty { return }   // same ongoing gesture → don't re-push
        past.append(current)
        if past.count > cap { past.removeFirst() }
        lastKey = coalesceKey
    }

    /// Returns the value to restore (and stashes `current` for redo), or nil if there is nothing to undo.
    mutating func undo(current: T) -> T? {
        guard let prev = past.popLast() else { return nil }
        future.append(current)
        lastKey = nil                                        // the next record starts a fresh coalesce run
        return prev
    }

    /// Returns the value to re-apply (and stashes `current` for undo), or nil if there is nothing to redo.
    mutating func redo(current: T) -> T? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        lastKey = nil
        return next
    }
}
