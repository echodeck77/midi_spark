//  Models.swift
//  MidiSpark — document model per spec v2.8 §9.
//  Machine = the treatment · Cell = the patch point · Preset = host fullState (reserved word).

import Foundation

// MARK: - Vocabulary

enum ProcessorType: String, Codable, CaseIterable {
    case arp = "ARP", ratchet = "RATCHET", empty = "PASSGATE"   // EMPTY (Paul 2026-09-28, was PASSGATE): the pass-per-lap gating FEATURE is removed entirely; this case survives ONLY as the engine's internal "this chain slot has nothing in it" sentinel (buildPassthroughSlot/buildIsEmptySlot and equivalents) — never user-addable, never shown as a labeled card. Raw string kept as "PASSGATE" so an old saved cell of that type still decodes (landing here, now a plain inert passthrough — exactly right, since the gating it used to do no longer exists).
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
    case octave = "OCTAVE"     // UTILITY (Paul 2026-08-22): shift the chain ±3 octaves — pitch-class preserved (the pool thesis untouched)
    case transpose = "TRANSPOSE" // UTILITY: shift the chain ±24 semitones (moves notes OFF the held chord — the chromatic crowd's tool)
    case channel = "CHANNEL"   // UTILITY: this chain exits on a chosen MIDI channel (WIRE default | 1–16) — multitimbral from one output
    case nudge = "NUDGE"       // UTILITY: a pure time offset (± sixteenths) on the stream — slides what's already there (does NOT drive)
    case dest = "DEST"         // ROUTING (Paul 2026-08-22 §5): per-onset-slice EMITTER selection — hocket painted (CHOP's dest row generalised to any chain)
    case muteMatrix = "MUTEMATRIX" // ROUTING (Paul 2026-08-25 §5): per-step PART-MUTING — an A/B/C/D × 8 checkbox grid; each onset-slice removes the muted emitters (note-transparent)
    case riff = "RIFF"         // DRIVER (SPEC-riff-processor, ratified 2026-08-22): a stored STENCIL of RANK choices derived against the held chord — the chord-following 303. Zero pitches stored.
    case tap = "TAP"           // ROUTING (AcceptanceCriteria-tap-processor, ratified): emits the stream AS-IT-STANDS at its chain position (LEVEL-scaled, to THIS wire | A–D) AND passes it onward unchanged — layered parallel outputs
    case hocket = "HOCKET"     // DRIVER (AcceptanceCriteria-hocket-processor, v1): plays its pool (WHAT) timed by LISTENING to another emitter wire (WHEN) — GAPS answers in its silences, TRADE hit-for-hit. The chains converse.
    case avoid = "AVOID"       // FILTER (unified 2026-08-31): a per-note pitch filter — the DOOR key-filter as a chain stage. REFERENCE (KEY · DOOR · WIRE · ALL SOUNDING) × MODE (LOCK keep-in | AVOID remove-in) × ACTION (REMOVE drop | MOVE snap). Placeable anywhere; masks clashes / locks to key. Politeness, not counterpoint.
    case chords = "CHORDS"     // HARMONY (ratified 2026-09-01): derive a diatonic progression from a key by rank arithmetic — a held trigger → the chord for the current degree (PATTERN matrix · FOLLOW door-note · WALK gravity dice). A set-shaper like HARMONIZE, never a driver. No chord stored; plays in any key.
    case velocity = "VELOCITY" // DYNAMICS (Paul 2026-09-07): a per-step velocity SEQUENCER — override each note's velocity from a per-step lane (or PASSTHROUGH that step). Note-transparent MODIFIER (never a driver); TIME (RATE·STEPS·SPAN) or NOTE (advance per note) clock, mirroring RATCHET PATTERN.
    case deal = "DEAL"         // ROUTING (Paul 2026-09-16): a simple output dealer — OVERRIDE the emitters, deal N1 notes to emitter 1 then N2 to emitter 2 (repeat). Note-transparent; DEAL mode = OVER TIME (per strike) · WITHIN CHORD (per note) · EVERY NOTE.
    case recorder = "RECORDER" // TIME (AcceptanceCriteria-recorder, ratified 2026-09-18): the looper-in-a-chain — record N steps/passes of the upstream output, then loop it back. Transparent while recording, a driver while playing back.
    case clock = "CLOCK"       // TIME (AcceptanceCriteria-clock-processor, ratified 2026-09-26, design-partner spec): a placeable pattern-clock transform — everything downstream's OWN internal step machinery (a fold consumer's rate/slice math) reads a transformed beat; everything upstream, and every GRID-time quantity (windows/columns/spans/reel), is untouched (the sovereign law). Note-transparent.
    case killStep = "KILLSTEP" // TIME (Paul 2026-09-26, sibling to CLOCK): a single row of ON/OFF steps (variable count, default 8) with its own RATE + SPAN — a DISABLED step is removed from the downstream timeline entirely; the ENABLED steps repeat to fill the pass (an even split plays "the first half twice"; an uneven split rotates a sub-cycle that drifts against the bar — "overriding the clock"). Reuses CLOCK's own plumbing (Router.killStepPhase/…Inverse, detected alongside `.clock` by driverClockBeat/…Inverse/clockTransformedBeat) so it reaches the same whole generator roster CLOCK already does. Note-transparent.
    case euclidMask = "EUCLIDMASK" // DYNAMICS (Paul 2026-09-27): the arp-only euclid mask (SPEC-arp-euclid-mask), pulled out as its own downstream FOLD processor — a K-of-N Bjorklund pattern gates whatever driver precedes it (ARP/RIFF/STRUM/RATCHET/EUCLID-as-driver/…), not just ARP. GAPS = REST | TIE | CHORD + ROTATE only; WALK/WAIT was dropped (needs the driver's own phase-index, which a fold can't reach — see Docs/pending-tasks.md). Note-transparent classification (like VELOCITY/DEST); never a driver; a no-op with no upstream driver.
    // §12: type IDs are append-only. Never reorder, never reuse.
}
/// The CLOCK ratio ladder (×4…÷4) — a plain index into DRAWN's per-column picks, mirroring `spanLadderValues`'s "a
/// small curated ladder, not a free slider" shape. Index 4 (×1) is the identity/no-op rung. (Paul 2026-09-26: CLOCK
/// used to offer FIXED/WAVE/DRAWN as three mode choices; FIXED and WAVE were removed entire — Paul's own spec, "a
/// grid with a variable number of steps, each step a mutually exclusive speed, and another row on the same grid
/// for glide", describes ONE mechanism, not a choice of three, and matches only what was DRAWN mode. CLOCK is now
/// always that grid.)
let clockRatioLadder: [Double] = [4, 3, 2, 1.5, 1, 1.0 / 1.5, 0.5, 1.0 / 3.0, 0.25]
let clockRatioLabels: [String] = ["×4", "×3", "×2", "×1.5", "×1", "÷1.5", "÷2", "÷3", "÷4"]
enum DealMode: String, Codable, CaseIterable { case overTime = "OVER TIME", withinChord = "WITHIN CHORD", everyNote = "EVERY NOTE" }   // DEAL: when the deal advances (Paul 2026-09-16)
// RECORDER (AcceptanceCriteria-recorder, ratified 2026-09-18): the looper-in-a-chain — record N steps/passes of the
// upstream output, then play it back. Transparent while recording, a driver while playing back.
enum RecGrain: String, Codable, CaseIterable { case steps = "STEPS", passes = "PASSES" }   // the loop unit
enum RecArm: String, Codable, CaseIterable { case onPlay = "ON PLAY", afterN = "AFTER N" }  // when capture begins
enum RecMode: String, Codable, CaseIterable { case loop = "LOOP", freeze = "FREEZE", canon = "CANON" }
enum RecFreeze: String, Codable, CaseIterable { case held = "HELD", repeatLoop = "REPEAT" }  // FREEZE style: sustained pad | locked rhythmic loop
enum RecMix: String, Codable, CaseIterable { case replace = "REPLACE", layer = "LAYER" }     // playback: recording only | recording + live
enum RecCapture: String, Codable, CaseIterable { case once = "ONCE", refresh = "REFRESH", hold = "HOLD" }  // re-arm: lock | renew every M | manual grab
struct RecEvent: Codable, Equatable { var beat: Double = 0; var note: Int = 60; var vel: Int = 100; var gate: Double = 0.25 }   // one captured NOTE: start beat within the window · pitch · velocity · length (beats)
extension RecEvent {   // CR-8 decode-tolerant (a future field can't factory-reset an older buffer)
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        beat = try c.decodeIfPresent(Double.self, forKey: .beat) ?? 0
        note = try c.decodeIfPresent(Int.self, forKey: .note) ?? 60
        vel  = try c.decodeIfPresent(Int.self, forKey: .vel) ?? 100
        gate = try c.decodeIfPresent(Double.self, forKey: .gate) ?? 0.25
    }
}
// AVOID / LOCK (unified 2026-08-31, Paul) — one processor covers "avoid clashing with X" AND "lock to key": a per-note
// pitch-class filter (the ratified keyFilterNote) as a chain stage.
enum AvoidRefKind: String, Codable, CaseIterable { case key = "KEY", door = "DOOR", wire = "WIRE", sounding = "ALL", soundingOut = "OUTALL" }   // the reference set to test against (§G: soundingOut = EVERYTHING OUT, all emitter output minus this cell's own buses)
enum AvoidMode: String, Codable, CaseIterable { case lock = "LOCK", avoid = "AVOID" }        // LOCK = keep ONLY notes in the reference (in-key) · AVOID = REMOVE notes in the reference (dodge clashes)
enum AvoidAction: String, Codable, CaseIterable { case remove = "REMOVE", move = "MOVE" }    // a rejected note: REMOVE = drop (a rest) · MOVE = snap to the nearest safe tone
enum AvoidWhat: String, Codable, CaseIterable { case same = "SAME", clash = "CLASH", clash2 = "CLASH+" }   // AVOID mode: SAME = only the exact pitch-class (don't double) · CLASH = also ±1 semitone (ic1) · CLASH+ = also ±2 (ic2, stricter). Widens the avoided sphere to what CLASHES with the reference.

// HOCKET (spec §MODE): GAPS = speak only in the listened wire's SILENCES (call-and-response) · TRADE = hit-for-hit
// alternation with it (one line split across two synths, by listening). §12 append-only.
enum HocketMode: String, Codable, CaseIterable { case gaps = "GAPS", trade = "TRADE" }

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
// MOD EXTERN mode (design-cc-stage §6): RE-EMIT = re-range the incoming CC (today) · SCALE = the incoming CC scales the
// cell's SHAPE depth (rhythm from us, amount from the wheel). (Paul 2026-09-09.)
enum ModExternMode: String, Codable, CaseIterable { case reEmit = "RE-EMIT", scale = "SCALE" }
// MOD TARGET (Paul 2026-08-20): CC = emit a MIDI CC (today) · CHAIN = modulate a chain param INTERNALLY (no CC), writing
// the param's offset lane — MOD composes with macros on the same lane. `modChainParam` = which param (the macro list).
enum ModTarget: String, Codable, CaseIterable { case cc = "CC", chain = "CHAIN" }
// FOLLOW — WHICH property of the sounding material drives the CC. §12 append-only.
enum ModFollow: String, Codable, CaseIterable { case density = "DENSITY", register = "REGISTER", count = "COUNT", vel = "VEL" }
// GLIDE — which held note the mono voice tracks when several sound at once. §12 append-only.
enum GlidePriority: String, Codable, CaseIterable { case last = "LAST", low = "LOW", high = "HIGH" }
// GLIDE MODE (Paul 2026-08-22): how the slide happens. BEND = pitch-bend one voice (today) · SYNTH = drive the
// synth's own portamento (CC65 on + CC5 time, notes legato) · STEP = a fast chromatic run source→target. (MPE = v2.)
enum GlideMode: String, Codable, CaseIterable { case bend = "BEND", synth = "SYNTH", step = "STEP" }
// APPEND-ONLY (Paul 2026-09-13): new cases go at the END — patternIndex = firstIndex(of:) in allCases, so appending
// keeps every stored index stable. altLo/altHi = the low/high note pedals, alternating with each other note (1,2,1,3,1,4…).
enum ArpPattern: String, Codable, CaseIterable { case up = "UP", down = "DOWN", upDown = "UP-DN", random = "RANDOM", asPlayed = "AS PLAYED", altLo = "ALT LO", altHi = "ALT HI", randomOnce = "RANDOM ONCE" }   // .randomOnce APPENDED (Paul 2026-09-16) — keeps the stored patternIndex of 0…6 stable; a fixed shuffled order off a persisted seed (arpSeed)
// RIFF (SPEC-riff-processor §1): when a stencil RANK exceeds the held-note count (a 5 against a 3-note chord) —
// FOLD (wrap + octave up, default/musical) · CLAMP (the top note) · WRAP (wrap in the same octave).
enum RiffWrap: String, Codable, CaseIterable { case fold = "FOLD", clamp = "CLAMP", wrap = "WRAP" }
// PLAYHEAD DIRECTION (Paul 2026-09-28): 6 modes. The raw values are the PERSISTENCE keys (Codable) — `.pendulum` KEEPS
// the old "PING-PONG" raw value (its math is unchanged, only the Swift case + display name changed: it was always
// bounce-once-each-end, mislabeled) so an old saved doc decodes byte-identical and its editor now correctly shows
// PENDULUM instead of the wrong PING-PONG label. `.pingpong` is the truly-new "bounce twice" mode, given a FRESH raw
// value ("PONG") so it can never collide with an old save. `displayLabel` (not `.rawValue`) is what GridUI shows.
enum RiffDir: String, Codable, CaseIterable {
    case forward = "FWD", reverse = "REV", pendulum = "PING-PONG", pingpong = "PONG", random = "RANDOM", drunk = "DRUNK"
    var displayLabel: String {
        switch self {
        case .forward: return "FWD"
        case .reverse: return "REV"
        case .pendulum: return "PENDULUM"
        case .pingpong: return "PING-PONG"
        case .random: return "RANDOM"
        case .drunk: return "DRUNK"
        }
    }
}
// ARP EUCLID MASK (SPEC-arp-euclid-mask, ratified 2026-08-26): non-hit steps are silence (REST) or sustain the previous
// note (TIE); the walk marches through rests (MARCH — holes) or steps only on hits (WAIT — the sequence re-spaced).
enum ArpMaskGap: String, Codable, CaseIterable { case rest = "REST", tie = "TIE", chord = "CHORD" }   // non-hit steps: rest (silence) · tie (sustain the prior note) · chord (strike the full held chord) — Paul 2026-09-14
// KILL STEP per-step MODE (Paul 2026-09-27): a step is exactly one of these four — ON (plays normally) · MUTE (the
// downstream clock still advances through it, only its sound is suppressed — a pure per-note fold, no timing
// change) · DROP (today's original "disabled": removed from the downstream timeline entirely, the surviving steps
// compact + repeat to refill the pass) · PAUSE (the downstream clock FREEZES at its current value for a
// configurable number of extra steps, then resumes — a hold/breath, not a retrigger: nothing new triggers during
// the freeze, whatever's already sounding just rings on).
enum KillStepMode: String, Codable, CaseIterable { case on = "ON", mute = "MUTE", drop = "DROP", pause = "PAUSE" }
// EUCLID LINES (SPEC-euclid-variations §10, ratified): EUCLID = up to 8 lines in one card — each a euclid pattern
// (K-of-N · ROTATE · INVERT) striking a TARGET (0 = ALL the chord, honouring the card's PICK · 1–8 = a specific pool
// rank). Per-line STEPS = polyrhythm (kick/hat/pulse from one chord, one machine). Line 1 = today's single euclid; when
// `euclidLines` is nil the engine uses the flat euclidPulses/Steps/Rot params (migration-invisible, byte-identical).
/// PER-LANE I/O SOURCE (Paul 2026-10-08, the new I/O tab): each Euclideous lane independently picks where its
/// notes come from. MIDI = the existing lanes receiver (index 3, "receiver 4") — unchanged from the old global
/// LANES switch this replaces. KEY = the page's own global KEY pool — still genuinely silent today (§4.4's
/// KEY-mode pool mapping remains unresolved by this feature). CHORDS = whichever receiver (if any) is
/// configured as a CHORD door (DoorMode.chord) — resolved in SnapshotBuilder, which has the document access
/// this enum's own cases don't carry; there's no picker for WHICH chord door, by design (no receiver-picking
/// UI returns to this page) — an unconfigured CHORDS lane is honestly silent, not a guessed fallback.
enum EuclideousLaneSource: String, Codable, CaseIterable { case midi, key, chords }
// SOURCES STACK ferry (Paul 2026-10-26): the three note sources stop being exclusive. MIDI IN ALWAYS listens;
// CHORDS and KEY each STACK beneath it. Each generated source has two conditions — plays while MIDI plays /
// plays when there's no MIDI (both ⇒ always, neither ⇒ off). Page-level (`PluginState.euclideousSourcePlan`),
// one value feeding every lane (the pool is global); shaped as ONE value type so a lane can later carry its
// own override (spec §8 — NOT built now). SUPERSEDES the exclusive `euclideousNoteSource` as the behaviour
// driver; that field stays decode-only as the nil-derivation fallback (`sourcePlanResolved`, §1.2).
struct SourcePlan: Equatable, Codable {
    var chordsWithMidi = false
    var chordsNoMidi   = false
    var keyWithMidi    = false
    var keyNoMidi      = false
}
// SOURCES STACK §1.6: CLASHES is a DEV-build-only rig setting (judged by ear) — ALLOW keeps every stacked note,
// DROP thins a lower layer's note that sits a semitone from a higher layer's (§2.7). `clashPolicyResolved`
// forces ALLOW in release builds whatever is stored, so a stored DROP can never reach a shipped build.
enum ClashPolicy: String, Codable, CaseIterable { case allow = "ALLOW", drop = "DROP" }
// FOURFOLD SETTINGS, CLOCK tab (2026-10-15 ferry, "Fourfold settings" §5.1).
enum EuclideousHostStopBehavior: String, Codable, CaseIterable { case keepPlaying, stop }

// HOLD/LATCH (Paul 2026-10-20): a page-level behavioural port of the 8x8-State door graph's
// `DoorMode.hold`/`.latch` (§2081-2089 above) onto Euclideous's own ONE GLOBAL MIDI IN pool —
// Euclideous has no receiver/door graph to hang the EXISTING per-Receiver `latchedPools`
// (Kernel.swift) off, so this is new engine state, not a reuse of that mechanism. Mutually
// exclusive by construction (one optional field, not two independent bools): nil = off (today's
// plain live-MIDI behaviour, byte-identical for every existing document). Only meaningful against
// `.midi` source — CHORDS/KEY already generate a fixed algorithmic pool with no physical note-on/
// off to freeze or toggle.
enum EuclideousHoldLatchMode: String, Codable, CaseIterable { case hold = "HOLD", latch = "LATCH" }

/// MELODY TAB (Paul 2026-10-13 ferry, "Behaviour" rule 1): "note and riff are mutually exclusive, and the
/// selection IS the mode — there's no separate switch." Replaces reading `useRiff` directly as the mode flag
/// going forward — a dedicated field reads unambiguously as "the mode is the selection" (tapping a note/TOP/
/// TOP2 sets `.note`; tapping the RIFF strip or any riff control sets `.riff`), rather than a boolean whose
/// name ("use riff") doesn't describe a two-way choice. nil migrates from the OLD `useRiff` field (byte-
/// identical: `useRiff == true` ⇒ `.riff`, else `.note`) — see `EuclidLine.melodyModeResolved` below.
enum EuclideousMelodyMode: String, Codable, CaseIterable { case note, riff }

struct EuclidLine: Codable, Equatable {
    var target: Int = 0      // 0 = ALL (honours PICK) · 1–8 = strike that pool rank (silent if the chord lacks it)
    var pulses: Int = 1      // K hits (Paul 2026-10-02: a fresh lane defaults to 1 of 8)
    var steps: Int = 8       // N steps (per-line ⇒ polyrhythm)
    var rotate: Int = 0
    // DECODE-ONLY (Paul 2026-10-02: "remove the hits button and functionality") — Router.swift's runEuclidLine no
    // longer reads this; an old doc with it set true just stops flipping to the rests, nothing more.
    var invert: Bool = false
    var pick: EuclidPick? = nil   // v1b (Paul 2026-08-26): per-line PICK for TARGET=ALL lines (nil ⇒ the global euclidPick — byte-identical)
    // DECODE-ONLY (Paul 2026-10-02: "drop it, please") — Router.swift's runEuclidLine no longer reads this; an
    // old doc with a non-zero per-line die just stops salting CYCLE/RANDOM/RIFF/ARP's walk, nothing more.
    var die: Int? = nil
    var dieResolved: Int { die ?? 0 }
    // NOTE SELECT MERGE (Paul 2026-09-29, the 4-fixed-row redesign): target+pick collapse into ONE selector —
    // picking a specific rank (N1…N8) behaves like the old target; picking an aggregate (ALL/LOW/HIGH/BOT2/TOP2/
    // CYCLE/RANDOM) behaves like the old pick. OPTIONAL — same CR-8 reasoning as `die` above: a non-Optional
    // additive field would throw decoding a pre-redesign doc.
    var noteSel: EuclidNoteSel? = nil
    var reverse: Bool? = nil   // DIRECTION (decode-only legacy as of the FWD/BKW/PING-PONG redesign below — see `direction`): nil/false = FWD · true = BKW
    // STAGE 3 (Paul 2026-10-01, the PLAY/SELECT + settings-panel redesign): GATE/OCTAVE/DIRECTION(3-way)/ENABLED.
    // All OPTIONAL — same CR-8 reasoning as `die`/`noteSel` above: a non-Optional additive field would throw
    // decoding a pre-Stage-3 euclidLines doc.
    var gate: Double? = nil       // GATE: this hit's length as a fraction of its own rate interval. nil ⇒ 0.9 (today's hardcoded value, byte-identical)
    var octave: Int? = nil        // OCTAVE: ±3, shifts the struck note(s) by 12×this. nil ⇒ 0 (byte-identical)
    var direction: EuclidDir? = nil   // DIRECTION: FWD/BKW/PING-PONG. nil ⇒ derive from the legacy `reverse` bool (byte-identical for an old doc)
    var enabled: Bool? = nil      // PLAY/STOP: nil ⇒ true (byte-identical). false ⇒ this lane contributes nothing, WITHOUT touching pulses/steps/rotate
    // VELOCITY (Paul 2026-10-02): a per-line SCALE on the struck note's own inherited velocity (0…2 — attenuate
    // or boost, never an absolute override) — reuses `strikeChord`'s existing `velScale` parameter directly
    // rather than inventing ARP's "ignore the input, use a fixed 1…100 level" convention, since a EUCLID line can
    // strike either a pool note (whose own velocity should still matter) or a RIFF/ARP-resolved note (which
    // already carries its own velocity formula this scale multiplies on top of). nil ⇒ 1.0 = unity, byte-identical.
    var velocity: Double? = nil
    // VELOCITY, ABSOLUTE (Paul 2026-10-09, XY pad redesign): a genuine MIDI-velocity OVERRIDE (1...127),
    // mirroring ARP's own `arpVelocity` — ignores the struck note's inherited dynamics entirely, unlike
    // `velocity` above (a 0...2 SCALE on the inherited value). A NEW field, not a repurposed one: reusing
    // `velocity`'s own JSON key with a changed Swift type would throw decoding any older doc that had
    // already saved a `Double` there (`decodeIfPresent` only tolerates a MISSING key, not a wrong-typed
    // one). nil ⇒ 100. Once the VEL pad writes here, `velocity` itself is never touched by any UI action
    // again — a KNOWN, DISCLOSED consequence: `velocity`'s own "0 = mute this lane" guard in
    // `runEuclidLine` (and the EUCLID-beacon readiness scan, `euclidLineReady`, itself dead UI since the
    // 2026-10-05 beacon removal) both still work for an OLD doc that set `velocity: 0`, but there's no
    // way to reach that state from the UI going forward — the lane's own PLAY/STOP toggle is the live
    // equivalent.
    var velocityAbsolute: Int? = nil
    var velocityAbsoluteResolved: Int { max(1, min(127, velocityAbsolute ?? 100)) }
    // HIT/MISS SPLIT (Paul 2026-10-02): "the off notes" — a MISS (rest) step can now ALSO strike a note, with its
    // own note-select/velocity/gate/octave, fully independent of the HIT side. `missNoteSel` is the on/off switch
    // for the whole feature: nil ⇒ OFF (today's silent-rest behaviour, byte-identical for every existing doc) —
    // there is deliberately no separate enable flag; picking any chip turns it on. No `missDie` — DIE was removed
    // entire the same day ("drop it, please"), so MISS's ordinal is unsalted from the start, matching the HIT
    // side's own now-unsalted `ord`. RIFF/ARP are NOT offered for miss (the UI never shows those two chips there)
    // — a stored `.riff`/`.arp` miss pick (hand-edited doc, or a future UI bug) is guarded in Router.swift to
    // emit nothing, not silently fall through to ALL.
    // STILL LIVE (Paul 2026-10-10): this is the regular, non-Euclideous BUILD-page EUCLID editor's OWN dual-
    // voice feature (GridUI.swift's `euclidHitMissBox`) — UNTOUCHED by the 2026-10-10 Euclideous-only "MISS
    // becomes an invert" ferry, which added a completely separate, new `patternMiss` field below for
    // Euclideous's own lane cards instead of repurposing this shared one (which would have silently changed
    // the regular processor's long-standing feature too, never asked for).
    var missNoteSel: EuclidNoteSel? = nil   // MISS note select — nil ⇒ feature OFF, no second strike on a rest
    var missGate: Double? = nil        // MISS gate length. nil ⇒ 0.9 (same default as hit's own gate)
    var missOctave: Int? = nil         // MISS octave shift. nil ⇒ 0
    var missVelocity: Double? = nil    // MISS velocity multiplier. nil ⇒ 1.0
    // EUCLIDEOUS MISS = PATTERN INVERT (Paul 2026-10-10, "rhythm cards cleared of melody" ferry) — additive,
    // alongside the shared `missNoteSel` quad above, not a replacement for it. Euclideous's own lane cards
    // exclusively use THIS field now (their UI no longer writes `missNoteSel` at all); `patternMiss` flips
    // which steps of the lane's own Euclid pattern sound: false/nil (HIT, default) plays the hits as built by
    // HITS/TILT/ROTATE; true (MISS) inverts that pattern — the lane plays every step that is NOT a hit and is
    // silent on the hits. Applied once, directly to `euclidBuf`, immediately after HITS/TILT/ROTATE have built
    // it and before anything downstream (cycleHits/hitsUpTo/ord/the riff walk/the TIE lookahead) reads it — so
    // every one of those consumers automatically treats the inverted steps as "hits," with no separate MISS
    // code path needed for this mechanism. Resolving `patternMiss` true makes the OLD `missNoteSel` branch a
    // no-op for that tick regardless of whatever it holds (a genuinely Euclideous-only line never sets
    // `missNoteSel` in the first place, so this is academic in practice, not a real interaction to reason about).
    var patternMiss: Bool? = nil
    // PER-LINE RATE (Paul 2026-10-05, EUCLIDEOUS): nil ⇒ inherit the machine-wide `euclidRate`/`euclidRateBeats`
    // (byte-identical for every existing doc, incl. the BUILD-page EUCLID processor, which has no UI for this and
    // will never set it). Lets each of Euclideous's 4 lanes run its own tempo-relative rate.
    var rate: ArpRate? = nil
    // CARD BACKS (Paul 2026-10-28): each PART of a lane — its RIFF and its NOTES — carries its own 4-bit routing mask over the four outputs A–D (bit n = output A + n); a part leaves on every output whose bit is set, and a part
    // routed nowhere sounds nowhere (its notes still reach the roll, marked silent). nil ⇒ the lane's OWN output (lane 1 → A, lane 2 → B, lane 3 → C, lane 4 → D), so every lane that has neither field resolves BOTH parts to its
    // own output. Additive-Optional and decode-tolerant: a document that carries the pre-nine-ports keys of the same names reads them back (bits above the fourth are dropped on read).
    var riffOutMask: UInt8? = nil
    var notesOutMask: UInt8? = nil
    /// This lane's RIFF part's outputs (bits A–D); `lane` is the lane's index (0–3) — the default is its own output.
    func riffOutMaskResolved(lane: Int) -> UInt8 { (riffOutMask ?? (UInt8(1) << UInt8(max(0, min(3, lane))))) & 0x0F }
    /// This lane's NOTES part's outputs (bits A–D).
    func notesOutMaskResolved(lane: Int) -> UInt8 { (notesOutMask ?? (UInt8(1) << UInt8(max(0, min(3, lane))))) & 0x0F }
    // RIFF ADVANCE (Paul 2026-10-06, EUCLIDEOUS): when on, this lane's hits step through the page's shared
    // EuclideousRiff pattern instead of noteSel/octave — REPLACES them entirely, not layered on top. riffRotate/
    // riffOctave are this lane's own INDEPENDENT offsets into that one shared pattern (driven by the same
    // NOTE/OCTAVE gesture pad, relabelled, once useRiff is on). Only meaningful for Euclideous's own cell — the
    // regular chainable BUILD-page EUCLID processor has no UI for these and will never set them; a hand-edited
    // doc that did would resolve against the page's default-empty EuclideousRiff (a silent rest, not a crash).
    var useRiff: Bool? = nil
    // MELODY TAB (Paul 2026-10-13 ferry) — the mode selection itself, superseding `useRiff` as the thing
    // actually read for "which mode is this lane in" (see `EuclideousMelodyMode`'s own doc comment and
    // `melodyModeResolved` below). `useRiff` is kept, decode-only, purely as this migration's source of old
    // data — never read directly for mode again.
    //
    // SUPERSEDED, same day, by the "lit notes plus the riff" ferry below (`litNotes`/`topLit`/`top2Lit`/
    // `riffOn`): `melodyMode` is now ITSELF decode-only — kept, unread by anything but `litMigrated`'s own
    // migration formula, since a two-case enum can't represent "some notes lit AND the riff on," which this
    // ferry's own additive model requires. `melodyModeResolved`/`useRiffResolved` stay too, read ONLY by
    // that same migration formula — nothing else in Router.swift/EuclideousPage.swift reads either again.
    var melodyMode: EuclideousMelodyMode? = nil
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry — "This amends [the MELODY tab]
    // instructions; where they conflict, this wins... replaces: the one-choice-at-a-time behaviour"). Each
    // lane now has TWO INDEPENDENT, ADDITIVE layers instead of one mutually-exclusive mode: any number of
    // the eight note buttons (`litNotes`, a bitmask, bit i = rank i+1) plus TOP/TOP2 can be lit AT THE SAME
    // TIME the riff is on — both layers sound together on a hit where the riff resolves a real note.
    //
    // `riffOn` is the new, GENUINELY INDEPENDENT source of truth for "is the riff on" — not a re-derivation
    // of `melodyMode` (which can only ever say "note" XOR "riff"). nil on all four ⇒ migrate via
    // `litMigrated` below; the ferry's own stated fresh-lane default ("nothing lit, riff on, FWD") is
    // `litMigrated`'s own fallback when NONE of melodyMode/useRiff/noteSel/target/pick were ever touched.
    var litNotes: UInt8? = nil
    var topLit: Bool? = nil
    var top2Lit: Bool? = nil
    var riffOn: Bool? = nil
    /// Migration, computed once: reuses the EXISTING, already-correct `melodyModeResolved`/`noteSelResolved`
    /// (each already collapses BOTH prior eras — the pre-MELODY-tab `useRiff`-bool era and the just-shipped
    /// `melodyMode`-enum era — into one final value apiece) rather than re-deriving a field-presence
    /// priority chain by hand. Since the just-shipped MELODY tab's own UI only ever wrote `noteSel` to
    /// `.n1...n8`/`.high`/`.top2` (confirmed by reading `melodyNotesRow`/`melodyOctaveRow` before this ferry
    /// retired them), it can never reach the `default` branch below — so ONE flat mapping, with no explicit
    /// era-branching, satisfies both of the ferry's own literal Presets tables simultaneously: era 1's
    /// "LOWEST: 1 lit / HIGHEST: TOP lit / note n: n lit / any other value: 1 lit, logged" and era 2's
    /// "note n: n lit / TOP or TOP2: that one lit / RIFF: nothing lit, riff on" collapse to the identical
    /// switch, because era 2 structurally never produces the "any other value" case.
    // RENDER-THREAD SAFETY (caught on review, before this ever ran: `EuclidLine` is carried wholesale into
    // `SnapParams`/`Snap` and its own `...Resolved` accessors — THIS ONE INCLUDED — are read directly inside
    // `Router.process()`, i.e. on the AUDIO thread, via `L.litNotesResolved` etc. at the `runEuclidLine` call
    // site. A `FileHandle.standardError.write` call reachable from here would be a genuine syscall on the
    // render path — this computed property is therefore PURE (no I/O, no side effects) by construction; it
    // returns a `warn` flag instead of logging directly. The actual log line is written exactly once per
    // resolve, on the MAIN thread only, inside `SnapshotBuilder.build()` — see its own call site, mirroring
    // the pre-existing `euclideousNoteSourceResolved` precedent (also PluginState-level, also main-thread-
    // only) exactly.
    private var litMigrated: (lit: UInt8, top: Bool, top2: Bool, riffOn: Bool, warn: Bool) {
        // A genuinely fresh, never-touched lane must resolve to the ferry's own stated default ("nothing
        // lit, riff on, FWD"), not fall into the switch below — `melodyModeResolved`/`noteSelResolved`
        // would otherwise read `.note`/their own `default` ("ALL"-shaped) fallback for a lane that has
        // NEVER had any of these fields touched, which would wrongly migrate it to "1 lit, logged."
        guard melodyMode != nil || useRiff != nil || noteSel != nil || target != 0 || pick != nil else {
            return (0, false, false, true, false)
        }
        if melodyModeResolved == .riff { return (0, false, false, true, false) }
        switch noteSelResolved {
        case .low: return (0b0000_0001, false, false, false, false)   // "LOWEST: 1 lit" (era 1) == N1
        case .high: return (0, true, false, false, false)
        case .top2: return (0, false, true, false, false)
        case .n1, .n2, .n3, .n4, .n5, .n6, .n7, .n8:
            let r = noteSelResolved.specificRank ?? 1
            return (UInt8(1 << (r - 1)), false, false, false, false)
        default:
            // ALL/CYCLE/RANDOM/BOT2/RIFF/ARP — only reachable from a pre-MELODY-tab doc (era 2's own UI
            // never wrote these) — "any other value: 1 lit, and logged" (era 1's own literal wording).
            return (0b0000_0001, false, false, false, true)
        }
    }
    // NOTES TAB ferry (§5.2): the three below are READ-ONLY PROJECTIONS of the lit order (`litOrderResolved`); `litNotes`/`topLit`/`top2Lit` themselves are
    // only the legacy decode source and what the encoder writes.
    var litNotesResolved: UInt8 { litOrderResolved.rankMask }
    var topLitResolved: Bool { litOrderResolved.hasTop }
    var top2LitResolved: Bool { litOrderResolved.hasTop2 }
    var riffOnResolved: Bool { riffOn ?? litMigrated.riffOn }
    /// True exactly when none of `litNotes`/`topLit`/`top2Lit`/`riffOn` have been explicitly set AND the
    /// legacy migration landed on the "unexpected value" branch — i.e. this lane genuinely needs the
    /// one-time migration warning. Read ONLY by `SnapshotBuilder.build()`, on the main thread — never by
    /// Router.swift. Pure (no I/O), same reasoning as `litMigrated` itself.
    var litMigrationNeedsWarning: Bool {
        litNotes == nil && topLit == nil && top2Lit == nil && riffOn == nil && litMigrated.warn
    }
    // RIFF WINDOW (RIFF WINDOW ferry 2026-10-21): which of the riff's 8 columns the walk's window starts
    // reading from, wrapping at 8 — independent of LENGTH (see `euclideousSetRiffShift`/`euclideousRiffColumn`;
    // `riffRotateResolved`, below with the other resolved properties, does the wrapping).
    var riffRotate: Int? = nil
    // RETIRED (RIFF WINDOW ferry 2026-10-21): SHIFT used to be clamped into 0...(riffLengthResolved − 1) by
    // every LEN change, so this remembered what was actually asked for before the clamp, to restore on a later
    // LEN grow. SHIFT no longer depends on LENGTH at all (it wraps at a fixed 8, LEN just sizes the window),
    // so there is nothing left to clamp away or remember. Kept ONLY for Codable decode compatibility with
    // documents saved before this ferry — never written or read for resolution any more.
    var riffShiftRequested: Int? = nil
    var riffShiftRequestedResolved: Int { riffRotateResolved }
    var riffOctave: Int? = nil
    // RIFF DIRECTION, PER-LANE (Paul 2026-10-07: "the back/forward, drunk controls should be per lane, not on
    // the riff control" — supersedes the first-draft design, which put these on the SHARED EuclideousRiff struct
    // and hid the on/off toggle behind a tap on the NOTE/OCTAVE pad; a visible per-lane selector replaces both).
    // riffDir nil ⇒ .forward; riffDirSeed/riffDirBias mirror RIFF's own riffDirSeed/riffDirBias (seed for RANDOM,
    // bias for DRUNK only).
    var riffDir: RiffDir? = nil
    var riffDirSeed: Int? = nil
    var riffDirBias: Double? = nil
    // EUCLID MASK, PER LANE (Paul/design-channel 2026-10-07, ratified — Docs/SPEC-euclideous-rework.md §2.7):
    // a second, independent step pattern per lane — its own play/stop, step count, rotate (set via a DRAG
    // GESTURE on its own grid, not a separate control). Nested, mirroring `Chop`'s own nested-struct-on-a-
    // per-cell-model precedent (Models.swift, `Cell.chop`) — NOT flattened at the Snapshot layer like `Chop`
    // is, since there's no render consumer yet (the mask's actual musical EFFECT is explicitly deferred; it
    // must not alter the lane's output until that's designed). Carried wholesale into SnapParams, like
    // EuclidLine/EuclideousRiff themselves.
    var mask: EuclidLineMask? = nil
    // PER-LANE I/O (Paul 2026-10-08, the new I/O tab): replaces the old page-level GLOBAL "LANES KEY|MIDI"
    // switch — each lane now independently picks MIDI IN / KEY / CHORDS. nil ⇒ .midi (byte-identical to every
    // existing doc, which could only ever have used the old global switch's MIDI default anyway — the global
    // switch's own KEY setting, if ever saved, doesn't migrate per-lane; see SnapshotBuilder's own note on
    // this). CHORDS is resolved entirely in SnapshotBuilder (it needs doc.receivers, which this struct has no
    // access to) — this field only names the CHOICE, not which receiver answers it.
    var sourceMode: EuclideousLaneSource? = nil
    // MELODY POP-UP (Paul 2026-10-10 ferry, §2.2): "the default SOURCE for a new instance is KEY" —
    // flips the 2026-10-08 MIDI default. Safe to change at this shared level (unlike noteSel's own
    // fallback below): `sourceMode` is read only by Euclideous's own per-lane I/O machinery, never by
    // the regular/non-Euclideous EUCLID processor, so there's no other consumer this could silently
    // affect. A fresh Euclideous lane now opens reading its own KEY (page-level KEY+SCALE), not MIDI IN.
    var sourceModeResolved: EuclideousLaneSource { sourceMode ?? .key }
    // TILT (Paul 2026-10-08): bias this lane's own K-of-N hit distribution toward the start (negative) or end
    // (positive) of its N-step cycle — see `euclidTiltPattern`'s own doc comment for the exact mechanism.
    // nil ⇒ 0 = no bias, byte-identical to before this field existed.
    var tilt: Double? = nil
    var tiltResolved: Double { max(-1, min(1, tiltFine ?? tilt ?? 0)) }   // RHYTHM POLISH: the fine value wins; with `tiltFine` nil this is exactly the old `tilt` read
    // RIFF FREE/LOCK, INVERT, ON REST (Paul 2026-10-09 ferry, "three new per-lane riff options") — all three
    // ONLY ever read while `useRiffResolved` is true; otherwise inert, same as riffRotate/riffDir/etc. above.
    //
    // NAMED `riffLock`/`riffInvert`/`riffOnRest` (the `riff` prefix matching riffRotate/riffOctave/riffDir's
    // own convention) — deliberately NOT reusing the existing `invert` field above: that one is a RETIRED,
    // decode-only leftover from the 2026-10-02 HITS/REST removal, a completely different concept (it used to
    // flip which of a pattern's OWN hits/rests struck, nothing to do with riff rank mirroring) — reusing its
    // name here would silently resurrect a dead field's old semantics for anyone who'd ever set it on an old
    // doc. A genuinely new name avoids that collision entirely.
    //
    // LOCK (nil ⇒ false = FREE, today's continuous-drift behaviour): every time this lane's OWN Euclid K/N
    // pattern completes a lap (returns to its own starting step), the riff position re-anchors to its start
    // instead of continuing to advance — see Router.swift's `runEuclidLine` for the mechanism (reusing
    // `hitsUpTo`, already "position within the CURRENT lap" by construction, in place of the full continuous
    // `ord`; needs no new state for 5 of 6 directions — only DRUNK, a genuine random walk, needs an explicit
    // hard-reset, mirroring the existing reset-span hard-reset `euclideousRiffDrunkStep` already does).
    var riffLock: Bool? = nil
    var riffLockResolved: Bool { riffLock ?? false }
    // INVERT (nil ⇒ false = off): mirrors a resolved riff rank r to (9 − r) for THIS lane only — 1↔8, 2↔7,
    // 3↔6, 4↔5 — applied BEFORE the rank is resolved against the lane's own source (MIDI/KEY/CHORDS), so it
    // works identically regardless of source; a REST (rank 0) is unaffected either way ("rests stay rests").
    // The shared riff grid itself is never redrawn inverted — this is a per-lane READ transform only.
    var riffInvert: Bool? = nil
    var riffInvertResolved: Bool { riffInvert ?? false }
    // ON REST (nil ⇒ .skip, today's behaviour): what this lane does when one of its hits lands on a riff
    // REST. SKIP = silent. FILL = (MIX ferry 2026-10-18 Q1) contributes no riff pitch of its own — falls
    // through to the lit-notes/TOP/TOP2/mask layer exactly as if the riff had produced nothing this hit,
    // only extending a TIE lookahead if one is already running; no longer "strike the NOTE/OCT pick"
    // (that behaviour retired with the old NOTE-mode fork). TIE = no new strike; the PRECEDING real note's
    // own gate is extended, via forward lookahead at the moment IT struck, to cover this rest too. REPEAT
    // (RIFF WALK ferry 2026-10-19 §4.2/§6) = plays the nearest earlier non-rest column's note again.
    var riffOnRest: EuclidRiffOnRest? = nil
    var riffOnRestResolved: EuclidRiffOnRest { riffOnRest ?? .skip }
    // MELODY POP-UP (Paul 2026-10-10 ferry) — four new per-lane riff-walk controls, all read only
    // while `useRiffResolved` is true (except melodyTranspose, which also applies in NOTE mode —
    // see Router.swift's plain-hit path). STRIDE/LENGTH/ADVANCE share the `riff` prefix convention
    // (riffRotate/riffOctave/riffDir/riffLock/riffInvert/riffOnRest above); TRANSPOSE is named
    // `melody`, not `riff`, for two reasons: it applies in both RIFF and NOTE mode, and a bare
    // `transpose` would collide with the existing closed-over, semitone-space `transpose` variable
    // already used throughout Router.swift's `runEuclidLine`/`finalPitch` — a different, pre-existing,
    // machine-wide concept; this one is rank-space and per-lane.
    //
    // STRIDE (nil ⇒ 1, §2 default): the walk moves ±STRIDE positions per advance instead of ±1 — FWD/
    // REV/PENDULUM/PINGPONG all generalize by scaling the ordinal fed into `riffStepAt` (§3.4); DRUNK
    // ignores it (always ±1, a genuine random walk has no "stride" concept).
    var riffStride: Int? = nil
    var riffStrideResolved: Int { max(1, min(7, riffStride ?? 1)) }
    // LENGTH (nil ⇒ 8, §2 default): the lane walks only riff steps 1...LENGTH — every direction's own
    // modulus becomes LENGTH instead of the shared riff pattern's full step count (§3.2).
    var riffLength: Int? = nil
    var riffLengthResolved: Int { max(1, min(8, riffLength ?? 8)) }
    // ADVANCE (nil ⇒ false = HIT, §2 default): HIT = today's behaviour, the walk advances once per
    // hit of this lane's own Euclid pattern. STEP = the walk advances on EVERY step (hit or miss) —
    // notes still only sound on hits (§3.5); ON REST still only fires when a hit lands on a rest.
    var riffAdvanceStep: Bool? = nil
    var riffAdvanceStepResolved: Bool { riffAdvanceStep ?? false }
    // ADVANCE EVERY (RIFF WALK ferry 2026-10-19 §4.1, nil ⇒ 1, today's behaviour): the walk moves once
    // every N hits (ADV HIT) or steps (ADV STEP) instead of every one — see `euclideousRiffWalkStep`
    // (Derivations.swift) for the ordinal → walk-step formula every reader of the riff ordinal now goes
    // through. Legal 1...8 (raised from 1...4, 2026-10-22); clamp on decode.
    var riffAdvanceEvery: Int? = nil
    var riffAdvanceEveryResolved: Int { max(1, min(8, riffAdvanceEvery ?? 1)) }
    // TRANSPOSE (nil ⇒ 0, §2 default): a RANK-space shift (scale steps in KEY, chord/pool positions in
    // MIDI IN and CHORDS), applied AFTER INVERT and BEFORE resolving against the lane's source (§3.1,
    // §3.7) — wraps octave-up/down via the same `riffResolve(wrap: .fold)` every rank lookup already
    // uses, so an out-of-pool transpose is never a special case.
    var melodyTranspose: Int? = nil
    var melodyTransposeResolved: Int { max(-7, min(7, melodyTranspose ?? 0)) }
    // HAND-EDITED PATTERN (Paul 2026-10-12, "6 sliders" ferry §7/§8/TILT): nil ⇒ PURE Euclid generation
    // (euclidPatternInto + tilt, today's behaviour, byte-identical). Non-nil ⇒ an EXPLICIT per-step hit
    // pattern (length == stepsResolved, padded/truncated below) that REPLACES euclidPatternInto+tilt
    // entirely — written by the new HITS slider's widest-gap/most-crowded rebuild (Derivations.swift's
    // `euclidRebuildPattern`) once a drag on an edited pattern needs to add/remove hits while keeping
    // hand-placed ones. TILT is meaningless once this is set (it only biases FRESH generation) — the UI
    // disables it and shows an "EDITED" chip; tapping that chip (or changing STEPS, §8) clears this back
    // to nil, reverting to pure Euclid. `pulses` is kept in sync with this array's own true count on every
    // write, so every OTHER existing reader of `pulses` (silence-check, badges, pictures, …) stays correct
    // without needing to know this field exists at all — only the render path's own pattern-generation
    // step needs to check it.
    var customHits: [Bool]? = nil
    /// Padded/truncated to `n` with trailing rests — defensive only; every real writer already sizes this
    /// to the line's current `steps` before storing it.
    func customHitsResolved(_ n: Int) -> [Bool]? {
        guard let c = customHits else { return nil }
        if c.count == n { return c }
        if c.count > n { return Array(c.prefix(n)) }
        return c + Array(repeating: false, count: n - c.count)
    }
    // RIFF/NOTES SPLIT (Paul 2026-10-13 ferry): the NOTES-tab layer's own three new controls — a master
    // on/off switch, per-rank (1-8) octave shifts, and a velocity offset — all independent of the riff
    // layer's own octave/velocity. `octave`/`riffOctave` already existed as two separate fields before this
    // ferry (the old MELODY tab just merged them into one UI control); these three are genuinely new.
    var notesOn: Bool? = nil
    var noteOctShifts: [Int]? = nil
    var notesVelOffset: Int? = nil
    // PER-LANE RESET (2026-10-14 ferry, "sequencer panel, four riffs, per-lane reset") — REPLACES the old
    // machine-wide `PluginState.euclideousResetSpanBars` for Euclideous's row. nil ⇒ OFF (0) at THIS raw
    // accessor's own level — a real correction, caught by a pre-existing RouterTest failing once this
    // shipped: `EuclidLine` is constructed directly (bypassing `PluginState.euclideousLinesResolved`
    // entirely) by every non-Euclideous `.euclid` cell AND by essentially every RouterTest fixture, so a
    // nil-default of anything but OFF here would silently force a periodic re-anchor onto code that never
    // asked for one. "A genuinely fresh Euclideous document's lane defaults to 1 step" (§9) is a MIGRATION
    // rule, not a raw-field default — it's applied explicitly, main-thread-only, inside `PluginState.
    // euclideousLinesResolved`'s own fresh-document branch, which sets `resetSteps = 1` directly rather than
    // relying on this accessor's own fallback to do it. Resolved domain is exactly {0=OFF, 1, 2, 4, 8} —
    // anything else (a stray hand-edited value) falls back to 0/OFF, matching `euclideousResetSpanBarsResolved`'s
    // own identical "unexpected ⇒ benign" convention.
    var resetSteps: Int? = nil
    var resetStepsResolved: Int { let v = resetSteps ?? 0; return [0, 1, 2, 4, 8].contains(v) ? v : 0 }
    // PER-STEP RESTART MASK (2026-10-15 ferry, "per-step restart points on the LANES tab") — REPLACES
    // `resetSteps` as the thing every new write touches. `resetSteps` stays in the struct, decodable, but
    // nothing writes it anymore. Bit s (0..<8) set ⇒ the lane restarts at the start of sequencer step s+1.
    // `restartMaskResolved` falls back through `resetStepsResolved` (NOT the raw `resetSteps` field, and NOT
    // a fresh re-implementation of the old machine-wide-bars migration) — that accessor has ALREADY had
    // `PluginState.euclideousLinesResolved`'s document-level migration applied to its backing `resetSteps`
    // by the time any code reads a resolved line (fresh doc ⇒ 1, pre-existing doc ⇒ migrated-from-bars), so
    // layering the mask's fallback on top of it inherits that migration for free — no second migration path
    // to keep in sync. A line built directly (bypassing `euclideousLinesResolved` — every non-Euclideous
    // `.euclid` cell, every RouterTest fixture) still resolves to OFF, same as `resetStepsResolved` itself,
    // for the identical reason documented on that accessor above.
    var restartMask: UInt8? = nil
    var restartMaskResolved: UInt8 { restartMask ?? euclideousStampMask(resetStepsResolved) }
    // LISTEN TAB (ferry 2026-10-14, "the LISTEN tab (lane relationships)", RATIFIED): each lane can take
    // RHYTHM/PITCH/LEVEL from another lane, its "partner." Three independent rows, each with at most one
    // lit mode + its own partner lane. All additive-Optional, same CR-8 reasoning as every other field
    // added to this struct — nil everywhere ⇒ a pre-LISTEN doc plays byte-identical (every row "off,"
    // using the lane's own settings, exactly §0/§10's stated defaults).
    var listenRhythmMode: EuclideousRhythmMode? = nil
    var listenRhythmPartner: Int? = nil
    // FOLLOW's own rate multiplier (§5): an EXPONENT of 2, not the ratio itself — -3...-1 = ÷8/÷4/÷2,
    // 0 = ×1 (default), 1...2 = ×2/×4. `listenFollowRatio` below converts to the actual ratio Router.swift
    // applies to the partner's own step length.
    var listenFollowMult: Int? = nil
    var listenPitchMode: EuclideousPitchMode? = nil
    var listenPitchPartner: Int? = nil
    // ANY (§4, AVOID only): a SEPARATE bool rather than overloading `listenPitchPartner` with a sentinel
    // index — keeps "which lane" and "is it ANY" from ever being confused by a future reader, and a
    // picker UI never has to reserve a magic Int.
    var listenPitchPartnerAny: Bool? = nil
    // SHADOW's INTERVAL (§6): pool-step count, −7...+7, default 0 (UNISON). OCT: −2...+2, default 0.
    var listenShadowInterval: Int? = nil
    var listenShadowOctave: Int? = nil
    // AVOID's own action (§6): nil ⇒ MUTE (the spec's own stated default).
    var listenAvoidAction: EuclideousAvoidAction? = nil
    var listenLevelMode: EuclideousLevelMode? = nil
    var listenLevelPartner: Int? = nil
    // AMOUNT (§7): 0...1 in 0.05 steps, default 0.4 (40%) — shared by DUCK and ACCENT, per lane.
    var listenLevelAmount: Double? = nil
    // LISTEN REBUILT (ferry 2026-10-23, "Fourfold Listen Tab", RATIFIED): REPLACES every field above — one
    // shared source lane for the WHOLE tab (not one partner per row), RHYTHM (OWN/COPY/FILL) + fugue
    // controls, PITCH (OWN/SHADOW/ECHO/AVOID) + INTERVAL/OCTAVE. WITH, DUCK/ACCENT/AMOUNT and AVOID's MOVE
    // action are dropped outright — no new fields replace them. Every field above stays decodable
    // (`EuclidLine.init(from:)` migrates old → new on first load, §8.3) and is never written again.
    // Additive-Optional, same CR-8 reasoning as the block above: nil everywhere ⇒ byte-identical to a
    // doc that never touched LISTEN at all.
    var listenSource: Int? = nil
    var listenRhythm: EuclideousListenRhythmMode? = nil      // .own/.copy/.fill
    // DELAY (§3.6): 0...(source's own step count − 1), steps the follower runs behind. FEEL (§3.7): the
    // follower's own TILT-style feel, −1...1. SPEED (§3.3): an EXPONENT of 2 (not FOLLOW's old, inverted
    // ratio) — ×¼...×4 is −2...+2; the follower's own step length = the source's ÷ 2^exponent, directly,
    // matching §3.3's own words ("÷½ makes each step twice as long") with no sign inversion to remember.
    var listenDelay: Int? = nil
    var listenFeel: Double? = nil
    var listenSpeed: Int? = nil
    var listenDirection: EuclidDir? = nil                     // relative to the SOURCE's own playback order (§3.4), not absolute
    var listenPitch: EuclideousListenPitchMode? = nil         // .own/.shadow/.echo/.avoid
    var listenInterval: Int? = nil                            // scale steps in the current key, −6...+6 (UNISON = 0)
    var listenOctave: Int? = nil                              // −3...+3
    // MIX TAB (ferry 2026-10-18): the NOTES layer's OWN gate and velocity — lit notes, TOP and TOP2 — so the two layers are
    // independent per lane. APPENDED LAST (memberwise-init order), additive-Optional, decode-tolerant. nil ⇒ today's behaviour:
    // `notesGate` nil reads the lane's GATE; `notesVelocity` nil reads clamp(VEL + notesVelOffset). The layers PART at the first
    // edit of GATE/VEL (`euclideousPinNotesLayer`, Derivations.swift §6.3), so an old session sounds the same until edited.
    // The RIFF layer's gate/velocity are the lane's existing `gate`/`velocityAbsolute` (what the RHYTHM tab shows).
    var notesGate: Double? = nil
    var notesVelocity: Int? = nil
    // LANES GRID (ferry 2026-10-18, §1): each lane gets a 16-cell MUTE grid and two 16-cell RESTART masks (rhythm = the Euclid
    // pattern starts again from its first step, melody = the riff goes back to its first position), each on the lane's OWN cell
    // size. APPENDED LAST (memberwise-init order), additive-Optional, decode-tolerant. Bit i of a mask is cell i. nil ⇒ the §1
    // defaults (all cells sound, no restarts, PASS-sized cells) — or, for a pre-feature document, the §6 migration, which needs the
    // lane's live step/lap lengths and the host bar and so is resolved at use (`euclideousLaneGridResolved`, Derivations.swift),
    // not here. Every write goes to these fields; the old ones (`resetSteps`, `restartMask`, the document's LANES sequencer
    // ON/RATE/LEN/cells) stay decodable and are never written again.
    var muteCells16: UInt16? = nil
    var muteUnit: UInt8? = nil
    var restartRhythmMask16: UInt16? = nil
    var restartMelodyMask16: UInt16? = nil
    var restartUnit: UInt8? = nil
    var muteCells16Resolved: UInt16 { muteCells16 ?? 0xFFFF }
    var muteUnitResolved: EuclideousMuteUnit { muteUnit.flatMap { EuclideousMuteUnit(rawValue: $0) } ?? .pass }
    var restartRhythmMask16Resolved: UInt16 { restartRhythmMask16 ?? 0 }
    var restartMelodyMask16Resolved: UInt16 { restartMelodyMask16 ?? 0 }
    var restartUnitResolved: EuclideousRestartUnit { restartUnit.flatMap { EuclideousRestartUnit(rawValue: $0) } ?? .pass }
    /// True once any of the five grid fields has been written — the lane is then on the NEW model and the old fields no longer
    /// feed it (§6: a lane migrates until its first grid edit, which writes all five).
    var usesLaneGrid: Bool {
        muteCells16 != nil || muteUnit != nil || restartRhythmMask16 != nil || restartMelodyMask16 != nil || restartUnit != nil
    }
    // RESTART CHAINS (ferry 2026-10-19, REPLACES restartRhythmMask16/restartMelodyMask16/restartUnit —
    // those three stay decodable, never written again, same "hide, don't delete" treatment the LANES
    // GRID ferry itself gave resetSteps/restartMask before it). RHYTHM counts in bars, MELODY in passes.
    // nil ⇒ "pre-feature: resolve via the §12 migration" (NOT the same as FREE — an empty array IS FREE).
    // On decode, drop any link not in {1,2,3,4,6,8} and keep at most the first four (EuclideousRestartChain
    // enforces this; see Derivations.swift).
    var restartRhythmBars: [UInt8]? = nil
    var restartMelodyPasses: [UInt8]? = nil
    var usesRestartChains: Bool { restartRhythmBars != nil || restartMelodyPasses != nil }
    // HITS/OFFSET MEMORY (ferry 2026-10-19 §2.5): what HITS/OFFSET were last explicitly asked for, so
    // shrinking STEPS and growing it back restores the exact pattern you left (not just whatever HITS/
    // OFFSET got clamped to along the way). nil ⇒ "take the current pulses/rotate-derived value" — see
    // euclideousSliderCommit's STEPS case (Derivations.swift) for where these are read and written.
    var hitsRequested: Int? = nil
    var offsetRequested: Int? = nil
    // NOTES TAB ferry (2026-10-19, §5): WHEN the lit notes play (PLAYS / RESTS), how many of those hits get through (CHANCE), HOW they play (PLAY AS),
    // whether lit octave copies stay silent (RECEIVED), and the ONE stored source of truth for what is lit — the lit ORDER. APPENDED LAST (memberwise-init
    // order), additive-Optional, decode-tolerant.
    //  · `notesWhen`: bit 0 PLAYS, bit 1 RESTS. DEFAULT 0b11 (not nil) so a lane made in this build always SAVES its WHEN — nil only ever comes from a document
    //    saved before this feature, and the decoder migrates it (`migratedNotesWhen`) so an old lane sounds exactly as it did.
    //  · `notesLitOrder`: lit positions in the order they were lit, 0-7 = ranks 1-8, 8 = TOP 2, 9 = TOP. `litNotes`/`topLit`/`top2Lit` stay decodable but are
    //    READ-ONLY PROJECTIONS of it (`litNotesResolved` & co.); setting the order rewrites all three so the encoder always writes them in agreement.
    var notesWhen: UInt8? = 0b11
    var notesChance: Int? = nil
    var notesPlayAs: EuclidNotesPlayAs? = nil
    var notesReceivedOnly: Bool? = nil
    var notesLitOrder: [UInt8]? = nil {
        didSet { if let a = notesLitOrder, let o = EuclideousLitOrder(valid: a) { litNotes = o.rankMask; topLit = o.hasTop; top2Lit = o.hasTop2 } }
    }
    // RHYTHM POLISH ferry (2026-10-22, §4) — APPENDED LAST (memberwise-init order), additive-Optional, decode-tolerant. nil everywhere sounds exactly as before.
    //  · `offsetFraction` (0..<1): the part of OFFSET between whole steps. Every hit plays that fraction of a step LATER (`euclideousHitDelaySteps`); the displayed offset is `offsetRequested + offsetFraction`. The STEPS
    //    setter leaves it alone (4.2). nil ⇒ 0.
    //  · `tiltFine` (−1…1): TILT as the slider last wrote it AND the opt-in for UNROUNDED timing. `tilt` was already a Double, but the engine rounds a tilted hit onto the step grid (`euclidTiltPattern`); stopping that for every
    //    stored `tilt` would change how existing sessions sound, so a lane plays unrounded only when `tiltFine` is set (the TILT slider writes both fields, so an older build still reads `tilt`). nil ⇒ today's rounded TILT.
    var offsetFraction: Double? = nil
    var tiltFine: Double? = nil
    // CARD BACKS v2 (Paul 2026-10-28, the PITCH pad) — APPENDED LAST (memberwise-init order), additive-Optional, decode-tolerant: each PART's OUT-TRANSPOSE, −7…+7 STEPS of the KEY pill's scale, the last pitch change
    // before the part's octave (`euclideousScaleStepMove`). NOT `melodyTranspose` (the RIFF tab's TRANS, which shifts RANKS) and never written by it. nil ⇒ 0, byte-identical to a document that never had it.
    var riffOutTranspose: Int? = nil
    var notesOutTranspose: Int? = nil
    var riffOutTransposeResolved: Int { max(-7, min(7, riffOutTranspose ?? 0)) }
    var notesOutTransposeResolved: Int { max(-7, min(7, notesOutTranspose ?? 0)) }
    /// `offsetFraction` as the engine reads it: 0 for nil / non-finite, else clamped into 0..<1.
    var offsetFractionResolved: Double {
        guard let f = offsetFraction, f.isFinite else { return 0 }
        return max(0, min(1 - 1e-9, f))
    }
    /// TILT plays unrounded (continuous) on this lane — see `tiltFine`.
    var tiltIsFine: Bool { tiltFine != nil }
    var notesWhenResolved: UInt8 { let w = (notesWhen ?? 0b11) & 0b11; return w == 0 ? 0b11 : w }
    var notesPlaysResolved: Bool { notesWhenResolved & 0b01 != 0 }
    var notesRestsResolved: Bool { notesWhenResolved & 0b10 != 0 }
    var notesChanceResolved: Int { EuclidLine.nearestLegalNotesChance(notesChance ?? 100) }
    var notesPlayAsResolved: EuclidNotesPlayAs { notesPlayAs ?? .chord }
    var notesReceivedOnlyResolved: Bool { notesReceivedOnly ?? false }
    /// The lit order: the stored one when valid, else (5.2) the lit ranks from low to high, then TOP 2, then TOP.
    var litOrderResolved: EuclideousLitOrder {
        if let a = notesLitOrder, let o = EuclideousLitOrder(valid: a) { return o }
        return EuclideousLitOrder.derived(litNotes: litNotes ?? litMigrated.lit, top: topLit ?? litMigrated.top, top2: top2Lit ?? litMigrated.top2)
    }
    /// The ONE writer of what is lit — stores the order (and, through its observer, the three projected fields).
    mutating func setLitOrder(_ o: EuclideousLitOrder) { notesLitOrder = o.array }
    /// Nearest of 25 / 50 / 75 / 100 (60 -> 50, 63 -> 75, 0 -> 25, 200 -> 100).
    static func nearestLegalNotesChance(_ v: Int) -> Int {
        var best = 25
        for c in [25, 50, 75, 100] where abs(c - v) < abs(best - v) { best = c }
        return best
    }
    /// 5.6: a lane saved before WHEN existed. Riff OFF: the lit notes sound on every hit -> both. Riff ON: SKIP and TIE silence the lit notes on a rest hit
    /// (the hit returns before the lit-notes layer) -> PLAYS only; FILL and REPEAT sound them on a rest hit -> both.
    static func migratedNotesWhen(riffOn: Bool, onRest: EuclidRiffOnRest) -> UInt8 {
        guard riffOn else { return 0b11 }
        switch onRest { case .skip, .tie: return 0b01; case .fill, .repeatLast: return 0b11 }
    }
    /// LISTEN REBUILT migration (§8.3), run once per decode of a pre-rebuild document (the caller checks
    /// `usesNewListen` first — a document already on the new model is never re-migrated). Pure, no host
    /// context needed (unlike the restart-chains migration, which needs live tempo/bar length and so runs
    /// on the main-thread resync loop instead) — safe to call straight from the decoder.
    /// FOLLOW→COPY, GAPS→FILL, WITH→OWN (all per §8.3's own table). SHADOW/AVOID keep their names; AVOID's
    /// old MOVE action has no new-model equivalent and is simply dropped (the new AVOID is mute-only).
    /// DUCK/ACCENT/AMOUNT are dropped outright (the LEVEL row no longer exists). DELAY/FEEL/SPEED/DIRECTION
    /// are explicitly left at their defaults (§8.3), never derived from the old `listenFollowMult`.
    /// Old INTERVAL/OCTAVE carry straight across (clamped into the new, slightly narrower ±6 INTERVAL
    /// range; OCTAVE's new ±3 range is wider than the old ±2, so nothing clips there) — reported as a real
    /// difference, not a silent one, since old INTERVAL/OCTAVE already read a scale-step pool-rank shift,
    /// which is what the new INTERVAL/OCTAVE mean too.
    /// Source conflict (both old rows lit, pointing at different partners — a case the spec's own §8.3
    /// table doesn't cover): RHYTHM's partner wins, matching the spec's own RHYTHM-before-PITCH ordering
    /// throughout. AVOID+ANY (no new-model equivalent at all, §2.1 has no "ANY" option) maps to the lane's
    /// own still-stored specific partner (remembered "through SHADOW/off" even while ANY was active) if one
    /// exists, else the lowest-numbered other lane (§8.2's own existing default rule) — both disclosed
    /// judgment calls, reported in the ferry's own §14.8 writeup, not asked.
    static func migratedListen(rhythmMode: EuclideousRhythmMode?, rhythmPartner: Int?, pitchMode: EuclideousPitchMode?,
                                pitchPartner: Int?, pitchPartnerAny: Bool?, shadowInterval: Int?, shadowOctave: Int?)
        -> (source: Int?, rhythm: EuclideousListenRhythmMode?, pitch: EuclideousListenPitchMode?, interval: Int?, octave: Int?)? {
        var source: Int? = nil
        var rhythm: EuclideousListenRhythmMode? = nil
        var pitch: EuclideousListenPitchMode? = nil
        var interval: Int? = nil
        var octave: Int? = nil
        if let old = rhythmMode {
            switch old {
            case .follow: rhythm = .copy; source = max(0, min(3, rhythmPartner ?? 0))
            case .gaps:   rhythm = .fill; source = max(0, min(3, rhythmPartner ?? 0))
            case .with:   rhythm = .own
            }
        }
        if let old = pitchMode {
            switch old {
            case .shadow:
                pitch = .shadow
                if source == nil { source = max(0, min(3, pitchPartner ?? 0)) }
                interval = max(-6, min(6, shadowInterval ?? 0)); octave = shadowOctave
            case .avoid:
                pitch = .avoid
                if source == nil {
                    if pitchPartnerAny == true { source = pitchPartner ?? 0 } else { source = max(0, min(3, pitchPartner ?? 0)) }
                }
            }
        }
        guard rhythm != nil || pitch != nil else { return nil }
        return (source, rhythm, pitch, interval, octave)
    }
    var hitsRequestedResolved: Int { hitsRequested ?? pulses }
    /// The same mirrored-OFFSET quantity `euclideousSliderRange(.offset)` displays (Derivations.swift) —
    /// `(steps − rotate mod steps) mod steps` — so a fresh/unrequested lane's "remembered" OFFSET is exactly
    /// what its current `rotate` already shows, byte-identical to not having HITS/OFFSET memory at all.
    var offsetRequestedResolved: Int {
        guard let v = offsetRequested else {
            let n = max(2, min(16, steps))
            let r = ((rotate % n) + n) % n
            return (n - r) % n
        }
        return v
    }
    /// ANY is only meaningful for AVOID. The stored flag is REMEMBERED while the row is off or on SHADOW (so switching modes and
    /// back restores it), but it counts only while AVOID is the lit mode — every reader (loop graph, processing order, the
    /// engine, the picker) goes through this, so a remembered ANY can never make a SHADOW lane depend on every other lane.
    var listenFollowMultResolved: Int { max(-3, min(2, listenFollowMult ?? 0)) }
    /// The actual multiplier applied to the partner's own rate (beats-per-step) to get this lane's own
    /// rate — the INVERSE power of 2, so ×2 (exponent 1, "twice as fast") HALVES the step length
    /// (0.5 = 2^−1), ÷2 (exponent −1, "half as fast") DOUBLES it (2 = 2^1), matching §5's own worked
    /// definition exactly: "×2 = twice as fast (half the partner's step length)."
    var listenLevelAmountResolved: Double {
        let raw = max(0, min(1, listenLevelAmount ?? 0.4))
        return (raw / 0.05).rounded() * 0.05
    }
    // LISTEN REBUILT resolved accessors. `listenSourceResolved` has no stored default of its own (§8.2
    // "the lowest-numbered other lane" is a RESOLVED fallback, not something migration writes) — a lane
    // that's never touched LISTEN stays nil/off regardless of what this would resolve to, since both rows
    // read OWN unconditionally until one is actually lit.
    func listenSourceResolved(ownLane: Int) -> Int {
        if let s = listenSource, s >= 0, s < 4, s != ownLane { return s }
        return ownLane == 0 ? 1 : 0
    }
    var listenRhythmResolved: EuclideousListenRhythmMode { listenRhythm ?? .own }
    var listenDelayResolved: Int { max(0, listenDelay ?? 0) }   // upper-bounded live by the caller against the source's own step count (§3.6) — can't self-clamp without that
    var listenFeelResolved: Double { max(-1, min(1, listenFeel ?? 0)) }
    var listenSpeedResolved: Int { max(-2, min(2, listenSpeed ?? 0)) }
    var listenSpeedRatioResolved: Double { pow(2.0, Double(listenSpeedResolved)) }
    var listenDirectionResolved: EuclidDir { listenDirection ?? .fwd }
    var listenPitchResolved: EuclideousListenPitchMode { listenPitch ?? .own }
    var listenIntervalResolved: Int { max(-6, min(6, listenInterval ?? 0)) }
    var listenOctaveResolved: Int { max(-3, min(3, listenOctave ?? 0)) }
    /// True once any of the nine new-model fields has been written — the lane is then on the NEW model and
    /// the old fields above no longer feed it (§8.3: migration runs only while this is false).
    var usesNewListen: Bool {
        listenSource != nil || listenRhythm != nil || listenDelay != nil || listenFeel != nil || listenSpeed != nil
            || listenDirection != nil || listenPitch != nil || listenInterval != nil || listenOctave != nil
    }
    var isFollowingResolved: Bool { listenRhythmResolved != .own || listenPitchResolved != .own }
    var gateResolved: Double { gate ?? 0.9 }
    // NOT narrowed to ±2 here (Paul 2026-10-13 ferry, "Engine" rule 4) — `EuclidLine` is SHARED with the
    // regular, non-Euclideous BUILD-page EUCLID processor, whose own OCTAVE stepper reaches ±3 today
    // (`GridUI.swift`, `numPair(..., -3...3, ...)`, confirmed by reading before touching this) — narrowing
    // the SHARED accessor would have silently clipped that unrelated feature too. The ±2 range is applied
    // ONLY where Euclideous reads/writes this field: `Router.swift`'s one `runEuclidLine` call site (gated
    // `isEuclideousRow`) and the new MELODY tab's own OCT control (EuclideousPage.swift) — never here.
    var octaveResolved: Int { octave ?? 0 }
    var enabledResolved: Bool { enabled ?? true }
    var velocityResolved: Double { max(0, min(2, velocity ?? 1.0)) }
    var missGateResolved: Double { missGate ?? 0.9 }
    var missOctaveResolved: Int { missOctave ?? 0 }
    var missVelocityResolved: Double { max(0, min(2, missVelocity ?? 1.0)) }
    var patternMissResolved: Bool { patternMiss ?? false }
    // MELODY TAB (Paul 2026-10-13 ferry) — `melodyMode`, once set, is the sole source of truth; absent, it
    // migrates from the legacy `useRiff` boolean (byte-identical: true ⇒ riff, false/nil ⇒ note).
    var melodyModeResolved: EuclideousMelodyMode { melodyMode ?? (useRiff == true ? .riff : .note) }
    // `useRiffResolved` is now DERIVED from the mode, not the other way round — every existing Router.swift/
    // EuclidLaneUI.swift reader of `useRiffResolved` needs no change at all; only the WRITE side (the new
    // MELODY tab's UI) writes `melodyMode` directly instead of `useRiff`.
    var useRiffResolved: Bool { melodyModeResolved == .riff }
    // RIFF WINDOW ferry (2026-10-21): wraps at the riff's 8 columns, not LENGTH — see `riffRotate`'s own comment.
    var riffRotateResolved: Int { ((riffRotate ?? 0) % 8 + 8) % 8 }
    // OCT RANGE −2…+2 (ferry "Engine" rule 4 — was ±3).
    var riffOctaveResolved: Int { max(-2, min(2, riffOctave ?? 0)) }
    var riffDirResolved: RiffDir { riffDir ?? .forward }
    // EUCLIDEOUS-SCOPED DRUNK/RANDOM→FWD (Paul 2026-10-13 ferry, Presets rule 1: "the stored direction
    // carries over. DRUNK becomes FWD"). `riffDir`/`RiffDir` are SHARED with the unrelated generic chain
    // RIFF processor, which still reaches DRUNK/RANDOM fully live — this override sits BESIDE the shared
    // `riffDirResolved`, read only by Euclideous's own engine/UI call sites, mirroring the exact precedent
    // `octaveResolved`'s own doc comment already establishes (a Euclideous-only range narrowing applied at
    // the call site, never at the shared accessor). RANDOM was already excluded from Euclideous's own WALK
    // row by an earlier ferry; included here too so a hand-edited doc can't reach it either.
    var euclideousRiffDirResolved: RiffDir {
        let d = riffDirResolved
        return (d == .drunk || d == .random) ? .forward : d
    }
    var riffDirSeedResolved: Int { riffDirSeed ?? 0 }
    var riffDirBiasResolved: Double { max(-1, min(1, riffDirBias ?? 0)) }
    var maskResolved: EuclidLineMask { mask ?? EuclidLineMask() }
    /// The effective note selection — `noteSel` once the line's been touched under the new UI, else derived from
    /// the old target/pick pair so a pre-redesign line resolves identically to what it always played.
    var noteSelResolved: EuclidNoteSel {
        if let s = noteSel { return s }
        if target >= 1 { return EuclidNoteSel(rawValue: "N\(min(8, target))") ?? .all }
        switch pick ?? .all {
        case .all: return .all
        case .cycle: return .cycle
        case .low: return .low
        case .high: return .high
        case .random: return .random
        }
    }
    var reverseResolved: Bool { reverse ?? false }
    /// The effective direction — `direction` once touched under Stage 3, else derived from the legacy `reverse`
    /// bool (FWD/BKW only — PING-PONG never existed before this, so there's nothing for an old doc to migrate to).
    var directionResolved: EuclidDir { direction ?? (reverseResolved ? .bkw : .fwd) }
    var notesOnResolved: Bool { notesOn ?? true }
    // UI-CONVENIENCE ONLY (main thread) — pads/clamps to exactly 8 entries, which means it ALLOCATES. The
    // RENDER THREAD must never call this (Router.swift reads the raw `noteOctShifts: [Int]?` instead, via
    // a bounds-checked, zero-allocation closure, mirroring this exact file's own `customHits`/
    // `customHitsResolved` split: `customHitsResolved` also pads/allocates and is likewise never called
    // from the render path for the same reason — confirmed by an adversarial-review fix that moved
    // Router.swift's own read off the padded accessor and onto the raw optional, see `runEuclidLine`'s
    // `if let custom = customHits` branch).
    var noteOctShiftsResolved: [Int] {
        var r = noteOctShifts ?? Array(repeating: 0, count: 8)
        if r.count < 8 { r += Array(repeating: 0, count: 8 - r.count) }
        if r.count > 8 { r = Array(r.prefix(8)) }
        return r.map { max(-1, min(1, $0)) }
    }
    var notesVelOffsetResolved: Int { max(-64, min(64, notesVelOffset ?? 0)) }
    /// The NOTES layer's gate: its own once stored, else the lane's GATE. Same 1%…100% domain the GATE slider uses.
    var notesGateResolved: Double { max(0.01, min(1, notesGate ?? gateResolved)) }
    /// The NOTES layer's velocity: its own once stored (1…127), else VEL + the legacy offset — exactly today's notes velocity
    /// (`notesVelOffsetResolved` is already ±64-clamped, so this is byte-identical to the engine's old `velocityAbsolute + offset`).
    var notesVelocityResolved: Int {
        if let v = notesVelocity { return max(1, min(127, v)) }
        return max(1, min(127, velocityAbsoluteResolved + notesVelOffsetResolved))
    }
}
// DECODE-TOLERANT (CR-8 class, code-review finding 2026-10-04): every field EuclidLine has gained SINCE day one
// was correctly added as Optional, but the five ORIGINAL fields (target/pulses/steps/rotate/invert) are plain
// non-Optional with no custom init — safe today only by discipline, not by structure. EuclidLine is the single
// most actively-developed struct in this codebase (gained 9+ fields in the last few days alone); this closes
// the gap the same way Cell/Machine/OnConfig/etc. already are, so the NEXT field added here — even a careless
// non-Optional one — can never regress to a whole-session factory reset.
extension EuclidLine {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decodeIfPresent(Int.self, forKey: .target) ?? 0
        pulses = try c.decodeIfPresent(Int.self, forKey: .pulses) ?? 1
        steps = try c.decodeIfPresent(Int.self, forKey: .steps) ?? 8
        rotate = try c.decodeIfPresent(Int.self, forKey: .rotate) ?? 0
        invert = try c.decodeIfPresent(Bool.self, forKey: .invert) ?? false
        pick = try c.decodeIfPresent(EuclidPick.self, forKey: .pick)
        die = try c.decodeIfPresent(Int.self, forKey: .die)
        noteSel = try c.decodeIfPresent(EuclidNoteSel.self, forKey: .noteSel)
        reverse = try c.decodeIfPresent(Bool.self, forKey: .reverse)
        gate = try c.decodeIfPresent(Double.self, forKey: .gate)
        octave = try c.decodeIfPresent(Int.self, forKey: .octave)
        direction = try c.decodeIfPresent(EuclidDir.self, forKey: .direction)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
        velocity = try c.decodeIfPresent(Double.self, forKey: .velocity)
        missNoteSel = try c.decodeIfPresent(EuclidNoteSel.self, forKey: .missNoteSel)
        missGate = try c.decodeIfPresent(Double.self, forKey: .missGate)
        missOctave = try c.decodeIfPresent(Int.self, forKey: .missOctave)
        missVelocity = try c.decodeIfPresent(Double.self, forKey: .missVelocity)
        patternMiss = try c.decodeIfPresent(Bool.self, forKey: .patternMiss)
        rate = try c.decodeIfPresent(ArpRate.self, forKey: .rate)
        useRiff = try c.decodeIfPresent(Bool.self, forKey: .useRiff)
        melodyMode = try c.decodeIfPresent(EuclideousMelodyMode.self, forKey: .melodyMode)
        litNotes = try c.decodeIfPresent(UInt8.self, forKey: .litNotes)
        topLit = try c.decodeIfPresent(Bool.self, forKey: .topLit)
        top2Lit = try c.decodeIfPresent(Bool.self, forKey: .top2Lit)
        riffOn = try c.decodeIfPresent(Bool.self, forKey: .riffOn)
        riffRotate = try c.decodeIfPresent(Int.self, forKey: .riffRotate)
        // RIFF WALK ferry §4.1/§4.3: clamp AT DECODE (unlike hitsRequested/offsetRequested, which clamp
        // only at the point of consumption) — test 20 requires a corrupt/out-of-range stored value to
        // read back already clamped, not merely produce a clamped RESOLVED value.
        riffAdvanceEvery = (try c.decodeIfPresent(Int.self, forKey: .riffAdvanceEvery)).map { max(1, min(8, $0)) }
        riffShiftRequested = (try c.decodeIfPresent(Int.self, forKey: .riffShiftRequested)).map { max(0, min(7, $0)) }
        riffOctave = try c.decodeIfPresent(Int.self, forKey: .riffOctave)
        riffDir = try c.decodeIfPresent(RiffDir.self, forKey: .riffDir)
        riffDirSeed = try c.decodeIfPresent(Int.self, forKey: .riffDirSeed)
        riffDirBias = try c.decodeIfPresent(Double.self, forKey: .riffDirBias)
        mask = try c.decodeIfPresent(EuclidLineMask.self, forKey: .mask)
        sourceMode = try c.decodeIfPresent(EuclideousLaneSource.self, forKey: .sourceMode)
        tilt = try c.decodeIfPresent(Double.self, forKey: .tilt)
        riffLock = try c.decodeIfPresent(Bool.self, forKey: .riffLock)
        riffInvert = try c.decodeIfPresent(Bool.self, forKey: .riffInvert)
        riffOnRest = try c.decodeIfPresent(EuclidRiffOnRest.self, forKey: .riffOnRest)
        riffStride = try c.decodeIfPresent(Int.self, forKey: .riffStride)
        riffLength = try c.decodeIfPresent(Int.self, forKey: .riffLength)
        riffAdvanceStep = try c.decodeIfPresent(Bool.self, forKey: .riffAdvanceStep)
        melodyTranspose = try c.decodeIfPresent(Int.self, forKey: .melodyTranspose)
        customHits = try c.decodeIfPresent([Bool].self, forKey: .customHits)
        notesOn = try c.decodeIfPresent(Bool.self, forKey: .notesOn)
        noteOctShifts = try c.decodeIfPresent([Int].self, forKey: .noteOctShifts)
        notesVelOffset = try c.decodeIfPresent(Int.self, forKey: .notesVelOffset)
        resetSteps = try c.decodeIfPresent(Int.self, forKey: .resetSteps)
        restartMask = try c.decodeIfPresent(UInt8.self, forKey: .restartMask)
        listenRhythmMode = try c.decodeIfPresent(EuclideousRhythmMode.self, forKey: .listenRhythmMode)
        listenRhythmPartner = try c.decodeIfPresent(Int.self, forKey: .listenRhythmPartner)
        listenFollowMult = try c.decodeIfPresent(Int.self, forKey: .listenFollowMult)
        listenPitchMode = try c.decodeIfPresent(EuclideousPitchMode.self, forKey: .listenPitchMode)
        listenPitchPartner = try c.decodeIfPresent(Int.self, forKey: .listenPitchPartner)
        listenPitchPartnerAny = try c.decodeIfPresent(Bool.self, forKey: .listenPitchPartnerAny)
        listenShadowInterval = try c.decodeIfPresent(Int.self, forKey: .listenShadowInterval)
        listenShadowOctave = try c.decodeIfPresent(Int.self, forKey: .listenShadowOctave)
        listenAvoidAction = try c.decodeIfPresent(EuclideousAvoidAction.self, forKey: .listenAvoidAction)
        listenLevelMode = try c.decodeIfPresent(EuclideousLevelMode.self, forKey: .listenLevelMode)
        listenLevelPartner = try c.decodeIfPresent(Int.self, forKey: .listenLevelPartner)
        listenLevelAmount = try c.decodeIfPresent(Double.self, forKey: .listenLevelAmount)
        listenSource = try c.decodeIfPresent(Int.self, forKey: .listenSource)
        listenRhythm = try c.decodeIfPresent(EuclideousListenRhythmMode.self, forKey: .listenRhythm)
        listenDelay = try c.decodeIfPresent(Int.self, forKey: .listenDelay)
        listenFeel = try c.decodeIfPresent(Double.self, forKey: .listenFeel)
        listenSpeed = try c.decodeIfPresent(Int.self, forKey: .listenSpeed)
        listenDirection = try c.decodeIfPresent(EuclidDir.self, forKey: .listenDirection)
        listenPitch = try c.decodeIfPresent(EuclideousListenPitchMode.self, forKey: .listenPitch)
        listenInterval = try c.decodeIfPresent(Int.self, forKey: .listenInterval)
        listenOctave = try c.decodeIfPresent(Int.self, forKey: .listenOctave)
        // LISTEN REBUILT migration (§8.3): only while this document hasn't touched the new model at all —
        // a document already on it (even one row explicitly set back to OWN) is never re-migrated.
        if !usesNewListen, let m = EuclidLine.migratedListen(rhythmMode: listenRhythmMode, rhythmPartner: listenRhythmPartner,
                                                               pitchMode: listenPitchMode, pitchPartner: listenPitchPartner,
                                                               pitchPartnerAny: listenPitchPartnerAny, shadowInterval: listenShadowInterval,
                                                               shadowOctave: listenShadowOctave) {
            listenSource = m.source; listenRhythm = m.rhythm; listenPitch = m.pitch; listenInterval = m.interval; listenOctave = m.octave
        }
        // `velocityAbsolute` was the ONE stored field this decoder never read (it encoded, so a saved VEL was written to disk and
        // then silently reset to 100 on every load). Found by the MIX ferry's audit; decoding it is what makes a lane's VEL — and
        // the notes velocity pinned from it — survive a session or preset round trip.
        velocityAbsolute = try c.decodeIfPresent(Int.self, forKey: .velocityAbsolute)
        notesGate = try c.decodeIfPresent(Double.self, forKey: .notesGate)
        riffOutMask = (try c.decodeIfPresent(UInt8.self, forKey: .riffOutMask)).map { $0 & 0x0F }
        notesOutMask = (try c.decodeIfPresent(UInt8.self, forKey: .notesOutMask)).map { $0 & 0x0F }
        notesVelocity = try c.decodeIfPresent(Int.self, forKey: .notesVelocity)
        muteCells16 = try c.decodeIfPresent(UInt16.self, forKey: .muteCells16)
        muteUnit = try c.decodeIfPresent(UInt8.self, forKey: .muteUnit)
        restartRhythmMask16 = try c.decodeIfPresent(UInt16.self, forKey: .restartRhythmMask16)
        restartMelodyMask16 = try c.decodeIfPresent(UInt16.self, forKey: .restartMelodyMask16)
        restartUnit = try c.decodeIfPresent(UInt8.self, forKey: .restartUnit)
        restartRhythmBars = try c.decodeIfPresent([UInt8].self, forKey: .restartRhythmBars)
        restartMelodyPasses = try c.decodeIfPresent([UInt8].self, forKey: .restartMelodyPasses)
        hitsRequested = try c.decodeIfPresent(Int.self, forKey: .hitsRequested)
        offsetRequested = try c.decodeIfPresent(Int.self, forKey: .offsetRequested)
        // RHYTHM POLISH ferry (2026-10-22, §4.1): tolerant by construction (`try?`): a wrong-typed value reads as missing, never a whole-session reset; clamped at decode.
        offsetFraction = (try? c.decodeIfPresent(Double.self, forKey: .offsetFraction)).flatMap { $0 }.flatMap { $0.isFinite ? max(0, min(1 - 1e-9, $0)) : nil }
        tiltFine = (try? c.decodeIfPresent(Double.self, forKey: .tiltFine)).flatMap { $0 }.flatMap { $0.isFinite ? max(-1, min(1, $0)) : nil }
        // CARD BACKS v2: tolerant (`try?`), clamped at decode.
        riffOutTranspose = (try? c.decodeIfPresent(Int.self, forKey: .riffOutTranspose)).flatMap { $0 }.map { max(-7, min(7, $0)) }
        notesOutTranspose = (try? c.decodeIfPresent(Int.self, forKey: .notesOutTranspose)).flatMap { $0 }.map { max(-7, min(7, $0)) }
        // NOTES TAB ferry (2026-10-19, §5): tolerant by construction (`try?`): a wrong-typed value reads as missing, never a whole-session reset.
        let rawWhen = (try? c.decodeIfPresent(UInt8.self, forKey: .notesWhen)).flatMap { $0 }
        notesChance = (try? c.decodeIfPresent(Int.self, forKey: .notesChance)).flatMap { $0 }.map(EuclidLine.nearestLegalNotesChance)
        notesPlayAs = (try? c.decodeIfPresent(EuclidNotesPlayAs.self, forKey: .notesPlayAs)).flatMap { $0 }
        notesReceivedOnly = (try? c.decodeIfPresent(Bool.self, forKey: .notesReceivedOnly)).flatMap { $0 }
        // 5.2: a valid order wins and the legacy trio is rewritten from it; otherwise (missing OR invalid) the order stays nil and `litOrderResolved` derives it.
        notesLitOrder = nil
        if let a = (try? c.decodeIfPresent([UInt8].self, forKey: .notesLitOrder)).flatMap({ $0 }), let o = EuclideousLitOrder(valid: a) {
            notesLitOrder = o.array; litNotes = o.rankMask; topLit = o.hasTop; top2Lit = o.hasTop2
        }
        // 5.6 migration, here so every load path (presets, sessions, the host's saved state, paste) gets it. FILL leaves ON REST (§9): it decodes as SKIP, whatever
        // the lane's WHEN. A lane with no stored WHEN gets the sound-preserving one; one with a stored WHEN keeps it (`& 3`, neither bit -> both).
        if let w = rawWhen {
            let m = w & 0b11
            notesWhen = m == 0 ? 0b11 : m
        } else {
            notesWhen = EuclidLine.migratedNotesWhen(riffOn: riffOnResolved, onRest: riffOnRestResolved)
        }
        if riffOnRest == .fill { riffOnRest = .skip }
    }
}
// NOTES TAB ferry (2026-10-19, §5.1): the seven ways the lit notes play on a hit they are chosen for. String-raw like every sibling enum; an unknown stored value
// decodes as CHORD (never a whole-session reset).
enum EuclidNotesPlayAs: String, Codable, CaseIterable {
    case chord = "CHORD", roll = "ROLL", run = "RUN", cycle = "CYCLE", bounce = "BOUNCE", split = "SPLIT", build = "BUILD"
    init(from decoder: Decoder) throws {
        let raw = (try? decoder.singleValueContainer().decode(String.self)) ?? ""
        self = EuclidNotesPlayAs(rawValue: raw) ?? .chord
    }
}
/// The lit positions in the order they were lit, as FIXED-SIZE data (ten bytes and a count — the render thread reads it, so no array): 0-7 are ranks 1-8, 8 is
/// TOP 2 and 9 is TOP. No repeats, at most ten.
struct EuclideousLitOrder: Equatable {
    static let topTwoPosition = 8, topPosition = 9
    private(set) var count = 0
    private var bytes = SIMD16<UInt8>(repeating: 0)
    init() {}
    /// nil when `a` has a repeat or a value outside 0...9 ("valid" in 5.2).
    init?(valid a: [UInt8]) {
        guard a.count <= 10 else { return nil }
        var seen = 0
        var o = EuclideousLitOrder()
        for v in a {
            guard v <= 9, seen & (1 << Int(v)) == 0 else { return nil }
            seen |= 1 << Int(v); o.bytes[o.count] = v; o.count += 1
        }
        self = o
    }
    /// 5.2: the lit ranks from low to high, then TOP 2, then TOP.
    static func derived(litNotes: UInt8, top: Bool, top2: Bool) -> EuclideousLitOrder {
        var o = EuclideousLitOrder()
        for r in 0..<8 where litNotes & (1 << UInt8(r)) != 0 { o.append(r) }
        if top2 { o.append(topTwoPosition) }
        if top { o.append(topPosition) }
        return o
    }
    subscript(i: Int) -> Int { Int(bytes[i]) }
    func contains(_ position: Int) -> Bool { for i in 0..<count where Int(bytes[i]) == position { return true }; return false }
    /// Place of `position` in the order (0-based), or nil.
    func index(of position: Int) -> Int? { for i in 0..<count where Int(bytes[i]) == position { return i }; return nil }
    mutating func append(_ position: Int) {
        guard position >= 0, position <= 9, count < 10, !contains(position) else { return }
        bytes[count] = UInt8(position); count += 1
    }
    mutating func remove(_ position: Int) {
        guard let at = index(of: position) else { return }
        var i = at
        while i + 1 < count { bytes[i] = bytes[i + 1]; i += 1 }
        count -= 1; bytes[count] = 0
    }
    /// Lighting adds to the end of the order; unlighting takes it out (2.11).
    mutating func toggle(_ position: Int) { contains(position) ? remove(position) : append(position) }
    var array: [UInt8] { (0..<count).map { bytes[$0] } }
    /// The projected `litNotes` bitmask (bit i = rank i + 1).
    var rankMask: UInt8 { var m: UInt8 = 0; for i in 0..<count where bytes[i] < 8 { m |= 1 << bytes[i] }; return m }
    var hasTop: Bool { contains(EuclideousLitOrder.topPosition) }
    var hasTop2: Bool { contains(EuclideousLitOrder.topTwoPosition) }
}
// LISTEN TAB enums (ferry 2026-10-14) — String-raw, matching every sibling enum on this struct.
enum EuclideousRhythmMode: String, Codable, CaseIterable { case follow = "FOLLOW", with = "WITH", gaps = "GAPS" }
enum EuclideousPitchMode: String, Codable, CaseIterable { case shadow = "SHADOW", avoid = "AVOID" }
enum EuclideousLevelMode: String, Codable, CaseIterable { case duck = "DUCK", accent = "ACCENT" }
enum EuclideousAvoidAction: String, Codable, CaseIterable { case mute = "MUTE", move = "MOVE" }
// LISTEN REBUILT enums (ferry 2026-10-23) — String-raw, matching every sibling enum on this struct. DIRECTION
// reuses the existing `EuclidDir` (FWD/BKW/PING-PONG) rather than a new type (§2.3: "using the RHYTHM tab's
// existing direction glyphs").
enum EuclideousListenRhythmMode: String, Codable, CaseIterable { case own = "OWN", copy = "COPY", fill = "FILL" }
enum EuclideousListenPitchMode: String, Codable, CaseIterable { case own = "OWN", shadow = "SHADOW", echo = "ECHO", avoid = "AVOID" }
// RIFF ON REST (Paul 2026-10-09 ferry): what a lane does when a hit lands on a riff rest. String-raw so it
// persists by value, matching every other riff-adjacent enum's own convention (RiffDir, EuclidNoteSel, …).
// REPEAT (RIFF WALK ferry 2026-10-19 §4.2): a hit on a rest plays the nearest earlier non-rest column's
// note again (Derivations.swift's REPEAT lookback). Swift reserves `repeat`, hence `repeatLast`; the raw
// value "REPEAT" is what persists. Old documents never hold it (only ever skip/fill/tie decode old).
enum EuclidRiffOnRest: String, Codable, CaseIterable { case skip = "SKIP", fill = "FILL", tie = "TIE", repeatLast = "REPEAT" }
// EUCLID MASK MODES (Paul 2026-10-10 ferry, "Euclid mask, modes and settings" — gives the per-lane mask
// a real musical effect for the first time). 11 modes, grouped exactly as the MODE picker UI groups them
// (§4: Thinning · Thickening · Pitch · Dynamics). String-raw, matching every sibling enum on this page.
enum MaskMode: String, Codable, CaseIterable {
    case mute = "MUTE", pause = "PAUSE"
    case ratchet = "RATCHET", repeatNote = "REPEAT", chord = "CHORD"
    case oct = "OCT", mirror = "MIRROR", leap = "LEAP", climb = "CLIMB"
    case accent = "ACCENT", swell = "SWELL"
}
enum MaskOctPattern: String, Codable, CaseIterable { case up = "UP", down = "DOWN", alt = "ALT" }
// CLIMB's own 4-way RANGE (size × behaviour) — kept as its OWN enum, not shared with SWELL's below,
// since SWELL has no size variant at all (ferry §3: "RANGE: WRAP / BOUNCE" only) — matching this
// codebase's own MaskChordPick-vs-EuclidPick precedent of never force-sharing an enum across two
// features with genuinely different value sets.
enum MaskRange: String, Codable, CaseIterable { case wrap1 = "WRAP 1 OCT", wrap2 = "WRAP 2 OCT", bounce1 = "BOUNCE 1 OCT", bounce2 = "BOUNCE 2 OCT" }
enum MaskSwellRange: String, Codable, CaseIterable { case wrap = "WRAP", bounce = "BOUNCE" }
// EUCLID MASK, PER LANE (Paul/design-channel 2026-10-07, ratified shared settings; modes/params added
// 2026-10-10) — see `EuclidLine.mask`'s own doc comment for the full rationale. Brand new, so a synthesized
// Decodable would be safe, but given its OWN custom init anyway (matching `Chop`'s precedent exactly)
// costs nothing and future-proofs the very first field added here later.
struct EuclidLineMask: Codable, Equatable {
    var enabled: Bool? = nil   // play/stop; nil ⇒ false/STOP (ferry 2026-10-10 §1 table — see enabledResolved below)
    var pulses: Int? = nil     // K; nil ⇒ 1 (matches EuclidLine's own "a fresh lane defaults to 1 of 8")
    var steps: Int? = nil      // N; nil ⇒ 8
    var rotate: Int? = nil     // nil ⇒ 0; unbounded here, wrapped mod steps at read time (matches EuclidLine.rotate's own convention)
    var chance: Double? = nil  // 0...1; nil ⇒ 1.0 (100%)
    var mode: MaskMode? = nil  // nil ⇒ .mute
    // RATCHET
    var ratchetMin: Int? = nil   // nil ⇒ 2
    var ratchetMax: Int? = nil   // nil ⇒ 4
    // REPEAT
    var repeatCount: Int? = nil  // nil ⇒ 1
    // CHORD
    var chordA: Int? = nil   // nil ⇒ 2
    var chordB: Int? = nil   // nil ⇒ 4
    // OCT
    var octAmount: Int? = nil        // nil ⇒ 1
    var octPattern: MaskOctPattern? = nil   // nil ⇒ .up
    // LEAP
    var leapSteps: Int? = nil   // nil ⇒ 2
    // CLIMB
    var climbStep: Int? = nil        // nil ⇒ 1
    var climbRange: MaskRange? = nil // nil ⇒ .wrap1
    // ACCENT
    var accentAmount: Int? = nil   // nil ⇒ 24
    // SWELL
    var swellStep: Int? = nil             // nil ⇒ 8
    var swellRange: MaskSwellRange? = nil // nil ⇒ .bounce
    // MASK PLAY/STOP DEFAULT FLIPPED (Paul 2026-10-10 "Euclid mask, modes and settings" ferry §1's own
    // table: "PLAY / STOP ... Default: STOP") — OVERRIDES the original 2026-10-07 line-1-only build's
    // own `enabled ?? true` ("a fresh mask starts audible/active"), which made sense when the mask had
    // no engine effect at all (there was nothing to "start" either way); now that it genuinely changes
    // the lane's output, a mask a user has never touched must default to silent/inert, not quietly
    // live and already applying MUTE (this field's own default mode) to every untouched lane.
    var enabledResolved: Bool { enabled ?? false }
    // HITS floor is 0, not 1 (ferry 2026-10-10 §1 table: "HITS | 0 to STEPS | 1") — 0 is a genuinely
    // reachable, meaningful state ("the mask never masks anything"), unlike EuclidLine's own main-lane
    // `pulsesResolved`, which floors at 1 because a silent main lane has nothing else to make it audible.
    var pulsesResolved: Int { max(0, pulses ?? 1) }
    var stepsResolved: Int { max(2, min(16, steps ?? 8)) }
    var chanceResolved: Double { max(0, min(1, chance ?? 1.0)) }
    var modeResolved: MaskMode { mode ?? .mute }
    var ratchetMinResolved: Int { max(1, min(8, ratchetMin ?? 2)) }
    var ratchetMaxResolved: Int { max(1, min(8, ratchetMax ?? 4)) }
    var repeatCountResolved: Int { max(1, min(4, repeatCount ?? 1)) }
    var chordAResolved: Int { max(-7, min(7, chordA ?? 2)) }
    var chordBResolved: Int { max(-7, min(7, chordB ?? 4)) }
    var octAmountResolved: Int { max(1, min(2, octAmount ?? 1)) }
    var octPatternResolved: MaskOctPattern { octPattern ?? .up }
    var leapStepsResolved: Int { max(-4, min(4, leapSteps ?? 2)) }
    var climbStepResolved: Int { max(-7, min(7, climbStep ?? 1)) }
    var climbRangeResolved: MaskRange { climbRange ?? .wrap1 }
    var accentAmountResolved: Int { max(-64, min(64, accentAmount ?? 24)) }
    var swellStepResolved: Int { max(-32, min(32, swellStep ?? 8)) }
    var swellRangeResolved: MaskSwellRange { swellRange ?? .bounce }
}
extension EuclidLineMask {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled)
        pulses = try c.decodeIfPresent(Int.self, forKey: .pulses)
        steps = try c.decodeIfPresent(Int.self, forKey: .steps)
        rotate = try c.decodeIfPresent(Int.self, forKey: .rotate)
        chance = try c.decodeIfPresent(Double.self, forKey: .chance)
        mode = try c.decodeIfPresent(MaskMode.self, forKey: .mode)
        ratchetMin = try c.decodeIfPresent(Int.self, forKey: .ratchetMin)
        ratchetMax = try c.decodeIfPresent(Int.self, forKey: .ratchetMax)
        repeatCount = try c.decodeIfPresent(Int.self, forKey: .repeatCount)
        chordA = try c.decodeIfPresent(Int.self, forKey: .chordA)
        chordB = try c.decodeIfPresent(Int.self, forKey: .chordB)
        octAmount = try c.decodeIfPresent(Int.self, forKey: .octAmount)
        octPattern = try c.decodeIfPresent(MaskOctPattern.self, forKey: .octPattern)
        leapSteps = try c.decodeIfPresent(Int.self, forKey: .leapSteps)
        climbStep = try c.decodeIfPresent(Int.self, forKey: .climbStep)
        climbRange = try c.decodeIfPresent(MaskRange.self, forKey: .climbRange)
        accentAmount = try c.decodeIfPresent(Int.self, forKey: .accentAmount)
        swellStep = try c.decodeIfPresent(Int.self, forKey: .swellStep)
        swellRange = try c.decodeIfPresent(MaskSwellRange.self, forKey: .swellRange)
    }
}
// EUCLIDEOUS RIFF (Paul 2026-10-06): a single, SHARED step pattern on the Euclideous page — any of its 4 lines can
// opt in (EuclidLine.useRiff) to step through it on each of its own hits instead of its normal note-select. ONE
// struct, not an array-of-4 like euclideousLinesResolved's own lines — the pattern CONTENT (steps/ranks) is
// shared; each line's own cursor/rotate/octave/DIRECTION (all on EuclidLine itself — Paul 2026-10-07: "the back/
// forward, drunk controls should be per lane, not on the riff control") is independent. Brand new, so a
// synthesized Decodable is safe (no legacy doc ever had a non-Optional field here to break). Scoped deliberately
// small — no POLY/TIE/SLIDE/ACCENT (not asked for), no RATE/SPAN (advancement is hit-triggered, not time-
// triggered, so neither applies).
struct EuclideousRiff: Codable, Equatable {
    var steps: Int = 16                  // 1...32, mirrors riffSteps' own range/default feel
    var ranks: [Int]? = nil              // MONO per-step: 0 = rest, 1...8 = pool rank. nil ⇒ an ascending default figure
    /// 1...32, defensive against a hand-edited or future out-of-range doc.
    var stepsResolved: Int { max(1, min(32, steps)) }
    /// Padded/truncated to `stepsResolved` length; an unset/short doc gets the ferry's own named R1 shape,
    /// cycled (usability ferry §8.2, 2026-10-11: "riff R1" — R1 = `1 2 3 5 4 3 2 1` — SUPERSEDES the earlier
    /// plain-ascending-mod-8 default; never silence by default either way, matching EuclidLine's own "a
    /// fresh lane defaults to something audible" convention).
    private static let r1Shape = [1, 2, 3, 5, 4, 3, 2, 1]
    // GENUINELY SILENT (2026-10-14 ferry §9: riff slots 2-4 "start empty") — `ranks: []` does NOT produce
    // this on its own: `ranksResolved`'s own pad-with-R1-default logic below treats ANY short array
    // (empty included) as "pad the rest with the default shape," a pre-existing, deliberate fallback from
    // the original single-riff feature ("never silence by default") — so an empty array still resolves to
    // the full, audible R1 figure. A genuinely-silent riff needs an EXPLICIT all-rest array of the real
    // length instead (caught by this feature's own migration test failing against the naive `ranks: []`
    // before this helper existed).
    static var empty: EuclideousRiff { EuclideousRiff(steps: 8, ranks: [Int](repeating: 0, count: 8)) }
    var ranksResolved: [Int] {
        let n = stepsResolved
        var r = ranks ?? (0..<n).map { Self.r1Shape[$0 % Self.r1Shape.count] }
        if r.count < n { r += (r.count..<n).map { Self.r1Shape[$0 % Self.r1Shape.count] } }
        if r.count > n { r = Array(r.prefix(n)) }
        return r
    }
}
// FOUR RIFFS — shared migration (2026-10-14 ferry §7): `riffs == nil` migrates the old SINGLE riff into
// slot 0; slots 1-3 start EMPTY (§9), a deliberate, disclosed deviation from the ScalePool/chordSeqs
// precedent (whose own slots 1-3 default to a fresh REAL value). Pure/standalone (not a `PluginState`-only
// computed property) because BOTH `PluginState` (the persisted document's own copy, read by the UI/undo
// snapshot) AND `MachineParams` (the per-render-published copy the render engine actually reads, mirroring
// how `euclideousRiff` itself already lives on both types) need the IDENTICAL fallback rule.
func euclideousRiffsMigrated(_ riffs: [EuclideousRiff]?, legacySingular: EuclideousRiff) -> [EuclideousRiff] {
    guard let r = riffs else {
        return [legacySingular, EuclideousRiff.empty,
                EuclideousRiff.empty, EuclideousRiff.empty]
    }
    var out = Array(r.prefix(4))
    while out.count < 4 { out.append(EuclideousRiff.empty) }
    return out
}
// SEQUENCER RATE (2026-10-14 ferry, "sequencer panel, four riffs, per-lane reset" §4) — the LANES/RIFFS
// sequencers' own ¼/½/1/2/4-BAR rate ladder. Genuinely new: grepped the whole codebase before adding this —
// no existing enum covers fractional-bar multiples (the old reset-span control was a bare whole-bars `Int`,
// `[0,1,2,4,8,16]`; `ArpRate` is a musical note-rate like 1/8/1/16, an unrelated concept). String-raw so it
// persists by value, matching every other sibling enum's own convention.
enum EuclideousSeqRate: String, Codable, CaseIterable {
    case quarterBar = "¼ BAR", halfBar = "½ BAR", oneBar = "1 BAR", twoBars = "2 BARS", fourBars = "4 BARS"
    var barsFraction: Double {
        switch self {
        case .quarterBar: return 0.25
        case .halfBar: return 0.5
        case .oneBar: return 1
        case .twoBars: return 2
        case .fourBars: return 4
        }
    }
}
// SEQUENCER PANEL (2026-10-14 ferry) — two plain, UI-facing bundles (Foundation-only, no SwiftUI dependency,
// so they live here alongside the other shared models) grouping each sequencer's own ON/RATE/LEN/cells into
// one value, mirroring `MachineParams`'s own "one mutate closure per feature" convention (`onEditChords`)
// rather than four separate setters apiece. NOT persisted directly — `AudioUnitViewController` mirrors these
// from (and writes them back onto) the four separate `PluginState.euclideousLanesSeq*`/`euclideousRiffsSeq*`
// fields; the bundle exists purely to keep the UI's edit-callback surface small.
// FX TAB (ferry 2026-10-18) — six fixed effect rows (RATCH, GATE, TIE, VEL, NOTE, CC) on the riff's eight steps. PAGE-level (one set for the
// whole page, shared by all four lanes), stored as ONE additive-Optional document field (`PluginState.euclideousFX`). Row order is fixed and is
// the storage order: row r, riff column c lives at `cells[r * 8 + c]`. A cell is EMPTY (the sentinel `emptyCell`) or holds that row's legal value:
// RATCH 2/3/4 · GATE 5…95 in 5s (NO legato: 100 was retired 2026-10-20 — a stored 100 loads as 95) · TIE 1 (on) · VEL 1…127 · NOTE −3…−1/+1…+3 (never 0) · CC 0…127. Each row also has a lane set
// (bit n−1 = lane n, default all four). The whole struct is fixed-size flat arrays (6 + 48 + 3 settings) so the render thread only ever READS it.
// Defaults (every cell empty, BASE none) make every existing session and all 20 factory presets sound exactly as before.
struct EuclideousFX: Equatable {
    static let rows = 6, columns = 8
    /// The GATE row's top value. It was 100 (= LEGATO, a repeated pitch carried on as one note and the repeat sounded nothing — the same rule that read as "hits not producing MIDI" on the
    /// XY pad); Paul 2026-10-20: "remove 100=legato". The row's step is 5, so its top is 95 — a lane's own gate tops out at 99 (`euclideousLaneGateMax`); every hit now re-strikes.
    static let gateMax = 95
    static let emptyCell: Int8 = Int8.min
    static let allLanes: UInt8 = 0b1111
    var lanes: [UInt8] = [UInt8](repeating: EuclideousFX.allLanes, count: 6)
    var cells: [Int8] = [Int8](repeating: EuclideousFX.emptyCell, count: 48)
    var notePasses: UInt8 = 4        // NOTE row: PASSES, 2…8
    var ccNumber: UInt8 = 74         // CC row: controller 0…119 (120–127 are channel-mode messages, never sent)
    var ccBase: Int16 = -1           // CC row: BASE, −1 = none, else 0…127
    var ratchShape: UInt8 = 0        // RATCH row: SHAPE (REVIEW FIX 2026-10-23) — 0 FLAT, 1 ACCENT, 2 FADE, 3 RAMP (`EuclideousRatchShape`); how a ratcheted hit's strikes share its velocity

    /// A row's legal cell value for a raw integer, or nil for "empty / unreadable". GATE rounds to the nearest 5 within 5…`gateMax` (95 — a stored 100 from an older session loads as 95); the ranged rows clamp;
    /// NOTE 0 is not a value; TIE has no value (any non-sentinel is "on").
    static func legalCell(row: Int, raw: Int) -> Int8? {
        if raw == Int(emptyCell) { return nil }
        switch row {
        case 0: return Int8(max(2, min(4, raw)))
        case 1: return Int8(max(5, min(gateMax, Int((Double(raw) / 5).rounded()) * 5)))
        case 2: return 1
        case 3: return Int8(max(1, min(127, raw)))
        case 4: return raw == 0 ? nil : Int8(max(-3, min(3, raw)))
        case 5: return Int8(max(0, min(127, raw)))
        default: return nil
        }
    }
    /// The row's cell at `column` (0…7), nil when empty (or out of range).
    func cell(row: Int, column: Int) -> Int? {
        guard row >= 0, row < 6, column >= 0, column < 8 else { return nil }
        let v = cells[row * 8 + column]
        return v == EuclideousFX.emptyCell ? nil : Int(v)
    }
    func laneOn(row: Int, lane: Int) -> Bool {
        guard row >= 0, row < 6, lane >= 0, lane < 4 else { return false }
        return (lanes[row] >> UInt8(lane)) & 1 != 0
    }
    /// True when no cell holds a value and BASE is none — the engine's "FX does nothing" state.
    var isInert: Bool { ccBase < 0 && !cells.contains { $0 != EuclideousFX.emptyCell } }
    /// Does ANY lane-enabled cell exist in `row` for `lane`? (Cheap gate so the render path skips per-hit work for an untouched row.)
    func rowHasCells(_ row: Int, lane: Int) -> Bool {
        guard row >= 0, row < 6, laneOn(row: row, lane: lane) else { return false }
        for c in 0..<8 where cells[row * 8 + c] != EuclideousFX.emptyCell { return true }
        return false
    }
    /// Every field clamped to its legal domain and every array forced to its fixed length — what the engine and the UI read (`PluginState.euclideousFXResolved`).
    func normalized() -> EuclideousFX {
        var out = EuclideousFX()
        for r in 0..<6 {
            out.lanes[r] = (r < lanes.count ? lanes[r] : EuclideousFX.allLanes) & EuclideousFX.allLanes
            for c in 0..<8 {
                let i = r * 8 + c
                let raw = i < cells.count ? Int(cells[i]) : Int(EuclideousFX.emptyCell)
                out.cells[i] = EuclideousFX.legalCell(row: r, raw: raw) ?? EuclideousFX.emptyCell
            }
        }
        out.notePasses = UInt8(max(2, min(8, Int(notePasses))))
        out.ccNumber = UInt8(max(0, min(119, Int(ccNumber))))
        out.ccBase = ccBase < 0 ? -1 : Int16(min(127, Int(ccBase)))
        out.ratchShape = UInt8(max(0, min(EuclideousRatchShape.allCases.count - 1, Int(ratchShape))))
        return out
    }
}
// Hand-written Codable: the wire form is plain `Int` arrays and Ints so a hand-edited or future document with an out-of-range number can never throw
// (decoding straight into `[Int8]` would fail the WHOLE session load on a stray 300). Everything is clamped on the way in (`normalized`).
/// One number off the wire, read leniently: an integer, or a float that is rounded (a hand-edited `52.5`); anything else (a string, null, a nested value) reads as
/// nil — "a value that can't be read" — WITHOUT throwing, so one bad element is one empty cell, never a lost array (§1.6).
private struct EuclideousFXLossyInt: Decodable {
    let value: Int?
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.singleValueContainer() else { value = nil; return }
        if let i = try? c.decode(Int.self) { value = i }
        else if let d = try? c.decode(Double.self), d.isFinite, abs(d) < 1e9 { value = Int(d.rounded()) }
        else { value = nil }
    }
}
extension EuclideousFX: Codable {
    enum CodingKeys: String, CodingKey { case lanes, cells, notePasses, ccNumber, ccBase, ratchShape }
    init(from decoder: Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawLanes = (try? c.decodeIfPresent([EuclideousFXLossyInt].self, forKey: .lanes)) ?? nil
        let rawCells = (try? c.decodeIfPresent([EuclideousFXLossyInt].self, forKey: .cells)) ?? nil
        func scalar(_ k: CodingKeys) -> Int? { ((try? c.decodeIfPresent(EuclideousFXLossyInt.self, forKey: k)) ?? nil)?.value }
        var raw = EuclideousFX()
        // an unreadable lane set keeps its default (all four on); an unreadable cell is empty
        if let l = rawLanes { for r in 0..<6 where r < l.count { if let v = l[r].value { raw.lanes[r] = UInt8(truncatingIfNeeded: v) } } }
        if let cs = rawCells { for i in 0..<48 where i < cs.count { if let v = cs[i].value { raw.cells[i] = Int8(max(Int(Int8.min), min(Int(Int8.max), v))) } } }
        if let n = scalar(.notePasses) { raw.notePasses = UInt8(max(0, min(255, n))) }
        if let n = scalar(.ccNumber) { raw.ccNumber = UInt8(max(0, min(255, n))) }
        if let n = scalar(.ccBase) { raw.ccBase = Int16(max(-1, min(255, n))) }
        if let n = scalar(.ratchShape) { raw.ratchShape = UInt8(max(0, min(255, n))) }
        self = raw.normalized()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(lanes.map { Int($0) }, forKey: .lanes)
        try c.encode(cells.map { Int($0) }, forKey: .cells)
        try c.encode(Int(notePasses), forKey: .notePasses)
        try c.encode(Int(ccNumber), forKey: .ccNumber)
        try c.encode(Int(ccBase), forKey: .ccBase)
        if ratchShape != 0 { try c.encode(Int(ratchShape), forKey: .ratchShape) }   // only when set: a default document encodes exactly as before
    }
}
// MARK: - HOCKET (ferry 2026-10-27)
// A rule trades or passes lines between Fourfold's eight lane outputs (the nine-output build: ALL, then a riff and a notes output per lane). One additive-Optional, decode-tolerant document field
// (`PluginState.hocketRules`) holds up to four rules; nil or empty ⇒ no rules ⇒ every output sounds exactly as the nine-output build sends it (spec §5.2, §7.6).
// OUTPUTS ARE STORED BY THEIR STABLE HOST IDENTITY — the output's CABLE as `FourfoldPorts.cable` defines it (1 = Emit Riff A, 2 = Emit Notes A … 8 = Emit Notes D), never a display name. Cable 0 is ALL, which is never in a
// group, so a stored 0 (like any other unknown value) is dropped at decode (§5.4). The engine works in BUS indices (cable − 1); `HocketGroup` (Snapshot.swift) converts once, on the main thread.
// The enum names avoid the 8x8 leftovers `HocketMode` (GAPS/TRADE) and `ProcessorType.hocket`, which this engine copy still carries but can never reach.
enum HocketRuleMode: String, Codable, CaseIterable { case swap = "SWAP", pass = "PASS" }
enum HocketUnit: String, Codable, CaseIterable { case hits = "HITS", steps = "STEPS", passes = "PASSES", bars = "BARS" }
enum HocketSeveral: String, Codable, CaseIterable { case together = "TOGETHER", rotate = "ROTATE" }
enum HocketOwn: String, Codable, CaseIterable { case replace = "REPLACE", merge = "MERGE" }

struct HocketRule: Equatable {
    /// §5.3 — the empty rule: on; SWAP; no outputs; HITS; 1 main / 1 alt; offset 0; TOGETHER; COUNT ON the first MAIN output; REPLACE.
    var on = true
    var mode: HocketRuleMode = .swap
    var main: [Int] = []          // cables 1…8, in the order they were tapped
    var alt: [Int] = []
    var unit: HocketUnit = .hits
    var mainLen = 1               // 1…8
    var altLen = 1                // 1…8
    var offset = 0                // 0 … mainLen + altLen − 1
    var several: HocketSeveral = .together
    var countOn = 0               // an index into `main`
    var own: HocketOwn = .replace

    static let maxLen = 8
    /// §3.3 — a rule is lit when it is on and its MAIN group isn't empty. An unlit rule touches no output (§6.1).
    var isLit: Bool { on && !main.isEmpty }
    /// MAIN + ALT, the length of the cycle (2…16).
    var cycleLength: Int { mainLen + altLen }
    /// Every output this rule holds, in either group (an output is "taken" by it whether the rule is on or off, §4.4).
    var outputs: Set<Int> { Set(main).union(alt) }

    /// §5.4's per-rule clamps: lengths into 1…8, the offset into 0 … L − 1, COUNT ON to 0 when it points past MAIN, groups cleaned (unknown outputs, ALL and repeats dropped; an output may be in BOTH groups).
    func normalized() -> HocketRule {
        var r = self
        r.main = Self.cleanGroup(main); r.alt = Self.cleanGroup(alt)
        r.mainLen = max(1, min(Self.maxLen, mainLen)); r.altLen = max(1, min(Self.maxLen, altLen))
        r.offset = max(0, min(r.mainLen + r.altLen - 1, offset))
        r.countOn = r.main.indices.contains(countOn) ? countOn : 0
        return r
    }
    static func cleanGroup(_ g: [Int]) -> [Int] {
        var seen = Set<Int>(), out: [Int] = []
        for c in g where (1...8).contains(c) && seen.insert(c).inserted { out.append(c) }
        return out
    }
}
extension HocketRule: Codable {
    enum CodingKeys: String, CodingKey { case on, mode, main, alt, unit, mainLen, altLen, offset, several, countOn, own }
    /// Never throws on content: an unreadable key keeps its §5.3 default, an unknown enum word takes the default, numbers clamp (§5.4).
    init(from decoder: Decoder) throws {
        self.init()
        guard let c = try? decoder.container(keyedBy: CodingKeys.self) else { return }
        func int(_ k: CodingKeys) -> Int? { ((try? c.decodeIfPresent(EuclideousFXLossyInt.self, forKey: k)) ?? nil)?.value }
        func word<E: RawRepresentable>(_ k: CodingKeys, _ type: E.Type) -> E? where E.RawValue == String {
            guard let s = (try? c.decodeIfPresent(String.self, forKey: k)) ?? nil else { return nil }
            return E(rawValue: s)
        }
        func list(_ k: CodingKeys) -> [Int] { ((try? c.decodeIfPresent([EuclideousFXLossyInt].self, forKey: k)) ?? nil)?.compactMap { $0.value } ?? [] }
        if let b = (try? c.decodeIfPresent(Bool.self, forKey: .on)) ?? nil { on = b }
        if let m = word(.mode, HocketRuleMode.self) { mode = m }
        if let u = word(.unit, HocketUnit.self) { unit = u }
        if let s = word(.several, HocketSeveral.self) { several = s }
        if let o = word(.own, HocketOwn.self) { own = o }
        main = list(.main); alt = list(.alt)
        if let n = int(.mainLen) { mainLen = n }
        if let n = int(.altLen) { altLen = n }
        if let n = int(.offset) { offset = n }
        if let n = int(.countOn) { countOn = n }
        self = normalized()
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(on, forKey: .on); try c.encode(mode, forKey: .mode)
        try c.encode(main, forKey: .main); try c.encode(alt, forKey: .alt)
        try c.encode(unit, forKey: .unit); try c.encode(mainLen, forKey: .mainLen); try c.encode(altLen, forKey: .altLen); try c.encode(offset, forKey: .offset)
        try c.encode(several, forKey: .several); try c.encode(countOn, forKey: .countOn); try c.encode(own, forKey: .own)
    }
}

/// The document's rules: encoded as a plain array of rules, SANITISED whenever one is built or decoded (§5.4) — rules past the fourth dropped, an output already used by an EARLIER rule (in either of its groups, on or off)
/// dropped from every later one. A stored value that isn't an array of rules at all decodes to no rules, never to a failed document load.
struct HocketRuleSet: Equatable, Codable {
    static let maxRules = 4
    private(set) var rules: [HocketRule]
    init(_ rules: [HocketRule] = []) { self.rules = Self.sanitised(rules) }
    init(from decoder: Decoder) throws {
        guard let c = try? decoder.singleValueContainer(), let raw = try? c.decode([HocketRule].self) else { rules = []; return }
        rules = Self.sanitised(raw)
    }
    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rules)
    }
    static func sanitised(_ raw: [HocketRule]) -> [HocketRule] {
        var used = Set<Int>(), out: [HocketRule] = []
        for r0 in raw.prefix(maxRules) {
            var r = r0.normalized()
            let counted = r.main.indices.contains(r.countOn) ? r.main[r.countOn] : nil      // COUNT ON names an OUTPUT; keep naming it when earlier rules take outputs out of MAIN
            r.main = r.main.filter { !used.contains($0) }
            r.alt = r.alt.filter { !used.contains($0) }
            r.countOn = counted.flatMap { r.main.firstIndex(of: $0) } ?? 0
            r = r.normalized()
            used.formUnion(r.outputs)
            out.append(r)
        }
        return out
    }
}

struct EuclideousLanesSeq: Equatable {
    var on: Bool = false
    var rate: EuclideousSeqRate = .oneBar
    var len: Int = 8
    var cells: [Bool] = [Bool](repeating: true, count: 32)
}
struct EuclideousRiffsSeq: Equatable {
    var on: Bool = false
    var rate: EuclideousSeqRate = .oneBar
    var len: Int = 8
    var cells: [Int] = [Int](repeating: 0, count: 8)
}
// LOOPER TABS (FERRY "looper tabs replace the riff tabs", ratified 2026-10-16, DROPPED 2026-10-18) —
// SUPERSEDED the loop-slots ferry's 4-independent-slot model entirely, retired below (decode-only, see
// `EuclideousLoopSlot`'s own updated doc comment). A fresh ladder, not a reuse of `EuclideousSeqRate`
// (¼…4 BAR, a sequencer STEP rate) or the retired `EuclideousLoopBars` (1/2/4/8, the slots' own length) —
// this one is 2/4/8/16 PASSES. `EuclideousLooperModeKind` (the UI-only, never-persisted Off/Armed/
// Recording/Replaying state) is DELETED outright along with the looper's own `AudioUnitViewController`
// state machine — confirmed zero remaining callers, and nothing ever persisted it (unlike this enum's
// `EuclideousLooperPasses`/`EuclideousLoopEvent` neighbours below, which back real `PluginState` fields
// and stay decode-only for an old saved session).
enum EuclideousLooperPasses: String, Codable, CaseIterable {
    case twoPasses = "2", fourPasses = "4", eightPasses = "8", sixteenPasses = "16"
    var passes: Int {
        switch self {
        case .twoPasses: return 2; case .fourPasses: return 4; case .eightPasses: return 8; case .sixteenPasses: return 16
        }
    }
}
/// One recorded change within the (single, never-saved) loop: `offsetBars` (not beats) so a meter change
/// mid-loop keeps the loop's shape (§6.3). `rank` 0 = rest, 1...8 = pool rank, same convention as
/// `EuclideousRiff.ranks` — reused as-is from the loop-slots ferry (the shape was already right; only the
/// SLOT concept it used to live inside is retired). `column` is redundant when these are already bucketed
/// per-column (§6.4's "fixed-capacity per-column sorted buffers"), but keeping it lets the whole loop
/// thread through `MachineParams`/`SnapParams` as ONE flat array instead of 8 nested ones — simpler
/// plumbing, identical behaviour (the engine still treats it as 8 independent per-column timelines).
struct EuclideousLoopEvent: Codable, Equatable {
    var offsetBars: Double
    var column: Int
    var rank: Int
}
// RETIRED (loop-slots ferry, 2026-10-16, superseded same-day) — decode-only: `PluginState`/`MachineParams`
// kept these fields declared for a session saved in the brief window loop-slots was live (none is known to
// exist — it never reached a device), same "decode-safety for an old doc, unreachable from any UI" pattern
// as `euclideousReceiver`/`riffDirBias` elsewhere in this file. Never written again; `SnapParams` never
// decodes from disk, so its own mirrors were removed outright rather than kept decode-only.
enum EuclideousLoopBars: String, Codable, CaseIterable {
    case oneBar = "1 BAR", twoBars = "2 BARS", fourBars = "4 BARS", eightBars = "8 BARS"
    var bars: Double {
        switch self {
        case .oneBar: return 1; case .twoBars: return 2; case .fourBars: return 4; case .eightBars: return 8
        }
    }
}
struct EuclideousLoopSlot: Codable, Equatable {
    var length: EuclideousLoopBars = .fourBars
    var startRanks: [Int]? = nil
    var events: [EuclideousLoopEvent]? = nil
    static var empty: EuclideousLoopSlot { EuclideousLoopSlot() }
}
// EUCLID DIRECTION (Paul 2026-10-01): a DEDICATED enum, not a reuse of RIFF's own `RiffDir` — EUCLID needs only
// 3 of RiffDir's 6 cases (no RANDOM/DRUNK) and RiffDir's own PENDULUM/PING-PONG naming history (the persisted
// string and the display label disagree, for legacy-compat reasons specific to RIFF) would be a confusing fit
// here. PING-PONG's own MATH (euclidCycleLen/euclidReadIndex, Derivations.swift) reuses RiffDir's `.pingpong`
// shape (period 2n, each endpoint sounds on two consecutive ticks) — reuse of the FORMULA, not the type.
enum EuclidDir: String, Codable, CaseIterable { case fwd = "FWD", bkw = "BKW", pingpong = "PING-PONG" }
// EUCLID NOTE SELECT (Paul 2026-09-29): the merged target+pick selector above — one control answering "which
// note(s) does this line strike." String-raw so it persists by VALUE, not `allCases` index (the class of bug
// ArpPattern/index-persisted enums have already caused elsewhere in this codebase). Ordered ALL·N1…N8 then the
// aggregate strategies, matching the two-row chip grouping the redesigned editor draws (row 1 = specific ranks,
// row 2 = strategies) — `allCases` slicing at the UI layer relies on this exact order.
enum EuclidNoteSel: String, Codable, CaseIterable {
    case all = "ALL"
    case n1 = "N1", n2 = "N2", n3 = "N3", n4 = "N4", n5 = "N5", n6 = "N6", n7 = "N7", n8 = "N8"
    case low = "LOW", high = "HIGH", bottom2 = "BOT2", top2 = "TOP2", cycle = "CYCLE", random = "RANDOM"
    // SEQUENTIAL SOURCES (Paul 2026-10-02): when the slot immediately before this EUCLID line is exactly RIFF (or
    // ARP), each hit steps through that predecessor's OWN authored sequence (RIFF's riffRanks/riffMask, or ARP's
    // own pattern math) by hit-ordinal — not the composed chord pool. Router.swift resolves these; a line stored
    // with one of these two cases whose predecessor no longer matches (chain edited, or the predecessor is now
    // bypassed) silently emits nothing — same "resolves correctly or honestly does nothing" contract as every
    // other case here.
    case riff = "RIFF", arp = "ARP"
    /// 1...8 for a specific-rank pick; nil for every aggregate case (ALL/LOW/HIGH/BOT2/TOP2/CYCLE/RANDOM/RIFF/ARP).
    var specificRank: Int? {
        switch self {
        case .n1: 1; case .n2: 2; case .n3: 3; case .n4: 4; case .n5: 5; case .n6: 6; case .n7: 7; case .n8: 8
        default: nil
        }
    }
}
enum ArpPhase: String, Codable, CaseIterable { case retrig = "RETRIG", legato = "LEGATO", free = "FREE" }   // §3.5
// SPAN — the timeline a pattern-based processor runs on (Paul 2026-08-18): CELL restarts the pattern each column
// (N steps = one column); ROW stretches the SAME N steps across the whole 8-column bar (a cross-column phrase). The
// column gate makes each cell voice only the pulses landing in its own column. Shared across EUCLID/LENGTH/TUTTI/… .
enum PatternSpan: String, Codable, CaseIterable { case cell = "CELL", row = "ROW" }
// MOD STEPS span (Paul 2026-08-20): PERIOD = today (8 steps over the modRate period) · ROW = 8 steps over the bar ·
// ROW×2 / ROW×4 = 16 / 32 breakpoints across 2 / 4 bars (the sequence longer than the row). `stepCount` = the # of breakpoints.
enum ModStepSpan: String, Codable, CaseIterable {
    case period = "PERIOD", row = "ROW", row2 = "ROW×2", row4 = "ROW×4"
}
enum StepRate: String, Codable, CaseIterable {
    case r2_1 = "2/1", r1_1 = "1/1", r1_2 = "1/2", r1_2d = "1/2.", r1_4 = "1/4", r1_8 = "1/8"
    var beats: Double {
        switch self { case .r2_1: 8; case .r1_1: 4; case .r1_2: 2; case .r1_2d: 3; case .r1_4: 1; case .r1_8: 0.5 }
    }
}
enum ArpRate: String, Codable, CaseIterable {
    // Straights, then dotted (D = 1.5×), then triplets (T = 2/3×) — 1/1…1/32 each (Paul 2026-09-14). Rate persists by
    // rawValue, so keeping the existing rawValues/case names (r1_4/r1_8/r1_8t/r1_16/r1_16t/r1_32) keeps saved sessions
    // + every `.r1_8`-style reference resolving; only allCases grew + reordered (rate re-indexes at build via firstIndex).
    case r1_1 = "1/1",  r1_2 = "1/2",  r1_4 = "1/4",   r1_8 = "1/8",   r1_16 = "1/16",   r1_32 = "1/32"
    case r1_1d = "1/1D", r1_2d = "1/2D", r1_4d = "1/4D", r1_8d = "1/8D", r1_16d = "1/16D", r1_32d = "1/32D"
    case r1_1t = "1/1T", r1_2t = "1/2T", r1_4t = "1/4T", r1_8t = "1/8T", r1_16t = "1/16T", r1_32t = "1/32T"
    var beats: Double {
        switch self {
        case .r1_1: 4;      case .r1_2: 2;      case .r1_4: 1;        case .r1_8: 0.5;    case .r1_16: 0.25;      case .r1_32: 0.125
        case .r1_1d: 6;     case .r1_2d: 3;     case .r1_4d: 1.5;     case .r1_8d: 0.75;  case .r1_16d: 0.375;    case .r1_32d: 0.1875
        case .r1_1t: 8.0/3.0; case .r1_2t: 4.0/3.0; case .r1_4t: 2.0/3.0; case .r1_8t: 1.0/3.0; case .r1_16t: 1.0/6.0; case .r1_32t: 1.0/12.0
        }
    }
}
enum Bus: String, Codable, CaseIterable { case a = "A", b = "B", c = "C", d = "D"
    var cable: UInt8 { UInt8(Bus.allCases.firstIndex(of: self)!) }
}
/// Pack a set/list of buses into the per-cable bitmask (bit i = cable i). One place so the builder's bus/chop-alt
/// mask packing can't drift. Pure.
@inline(__always) func busBitmask<S: Sequence>(_ buses: S) -> UInt8 where S.Element == Bus { buses.reduce(0) { $0 | (1 << $1.cable) } }
enum StrumDir: String, Codable, CaseIterable { case up = "UP", down = "DOWN", alternate = "ALT" }   // §3 STRUM
// EUCLID PICK (Paul 2026-08-22) — what each euclidean hit strikes (the TUTTI vocabulary on euclid's hits).
enum EuclidPick: String, Codable, CaseIterable { case all = "ALL", cycle = "CYCLE", low = "LOW", high = "HIGH", random = "RANDOM" }
// EUCLID MASK's own CHORD PICK (Paul 2026-09-28): a DEDICATED enum, not a reuse of EuclidPick above — BOTTOM2/TOP2
// strike a PAIR of notes, which the driver's own `strikeChord(onlyIndex:)` mechanism (one pool-rank at a time) can't
// express, so extending the shared enum would have forced an unrelated change onto the standalone EUCLID driver.
enum MaskChordPick: String, Codable, CaseIterable { case all = "ALL", low = "LOW", high = "HIGH", bottom2 = "BOT2", top2 = "TOP2", cycle = "CYCLE", random = "RANDOM" }
// CHANCE MODE (Paul 2026-08-22 §5): SINGLE = one probability · PATTERN = 8 per-step odds (the odds SLIDER LANE).
enum ChanceMode: String, Codable, CaseIterable { case single = "SINGLE", pattern = "PATTERN" }
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
// RATCHET PATTERN clock (Paul 2026-09-07): TIME = the ratchet's own RATE grid advances the playhead by time · NOTE =
// the playhead advances one MATRIX column per note passing through (chain-only; standalone falls back to TIME).
enum RatchetClock: String, Codable, CaseIterable { case time = "TIME", note = "NOTE" }
// BURST family (Paul 2026-08-19): ONCE = today (fire at column entry) · COIN = seeded chance-of-burst per step ·
// PATTERN = an 8-slice BURST/CARRY/REST row (pick-then-paint). CARRY = span-stretch: the roll's strikes + curve
// redistribute across the burst slice + its contiguous carries (one breathing roll over the painted span).
enum BurstMode: String, Codable, CaseIterable { case once = "ONCE", coin = "COIN", pattern = "PATTERN" }
enum BurstSlice: String, Codable, CaseIterable { case burst = "B", carry = "C", rest = "R" }

let machineIDs: [String] = ["gold","orange","vermilion","wine","magenta","blush","purple","violet",
                           "indigo","azure","cyan","teal","mint","green","chartreuse","slate"]

// MARK: - Machine (the treatment) — §1/§9

// PER-PARAM LFO (Docs/PLAN-param-lfo.md, ratified 2026-09-15): the "LFO" button (∿) beside a param label — a waveform +
// period + depth wired inline to a setting, oscillating it over time. Reuses the MOD oscillator (`modUnipolar`) and the
// span-automation render write (`settingAuto`). `target` = an AutoParamField key (e.g. "gate"); the LFO adds a BIPOLAR
// swing AROUND the param's own (base) value, so depth 0 == byte-identical. Stage 1 targets ARP LENGTH (gate). Append-only.
// PER-PARAM LFO (Docs/PLAN-param-lfo.md; Paul 2026-09-15 redesign): the LFO sweeps a param FROM → TO and back, over a
// DURATION, shaped by a WAVE. No depth/phase/quantize (they confused) — the two endpoints ARE the range, authored with the
// param's own control. Removed fields (free/depth/phase/quantize/rateFamily) decode away as ignored extra keys.
struct ParamLFO: Codable, Equatable {
    var target: String = "gate"      // the AutoParamField key (or "arpRate") it modulates (resolved at build; unknown ⇒ dropped)
    var shape: ModShape = .sine      // WAVE — SINE · TRI · SQR · RAMP · S&H
    var period: ModRate = .r2        // DURATION as a fixed musical subdivision (beats/cycle) — used when stepSpan is nil
    var stepSpan: Int? = nil         // DURATION as grid STEPS: 1…8 = N steps · 16/32/64 = ×2/×4/×8 bars. nil ⇒ use `period`.
    var from: Double? = nil          // VESTIGIAL (Paul 2026-09-16): FROM is now the processor's OWN param (two views) — the
                                     //   engine + UI read the live base, not this. Kept for decode/round-trip compatibility.
    var to: Double? = nil            // sweep endpoint (the LFO's far end); FROM = the base param. ACTIVE when to != the base.
    var rateIgnore: Int? = nil       // "arpRate" only (Paul 2026-09-16): IGNORE families the sweep skips — bit0 normal · bit1 dotted · bit2 triplet. nil ⇒ default IGNORE dotted+triplet (0b110 = normal only). The full grid still shows; ignored rows just aren't swept.
    var rateIgnoreResolved: Int { let m = (rateIgnore ?? 0b110) & 0b111; return m == 0b111 ? 0b110 : m }   // never ignore ALL three (would leave no rate) — fall back to keeping normal
}
// DECODE-TOLERANT (CR-8 class, code-review finding 2026-10-04) — target/shape/period are the only non-Optional
// fields here; same gap and same fix as EuclidLine above.
extension ParamLFO {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        target = try c.decodeIfPresent(String.self, forKey: .target) ?? "gate"
        shape = try c.decodeIfPresent(ModShape.self, forKey: .shape) ?? .sine
        period = try c.decodeIfPresent(ModRate.self, forKey: .period) ?? .r2
        stepSpan = try c.decodeIfPresent(Int.self, forKey: .stepSpan)
        from = try c.decodeIfPresent(Double.self, forKey: .from)
        to = try c.decodeIfPresent(Double.self, forKey: .to)
        rateIgnore = try c.decodeIfPresent(Int.self, forKey: .rateIgnore)
    }
}

struct MachineParams: Codable, Equatable {
    // Superset of per-type params; only the active type's fields are meaningful. §12.0: append-only.
    var pattern: ArpPattern? = .up
    var rate: ArpRate? = .r1_16
    var octaves: Int? = 1
    var gate: Double? = 0.6
    var phase: ArpPhase? = .legato   // FLOW default (Paul 2026-09-14): LEGATO (was RETRIG) — arps sit connected by default
    var count: Int? = 3            // ratchet
    var ramp: Double? = 0.5        // ratchet
    var spread: Double? = 0.1      // strum: chord stagger in BEATS (0…1)
    // EUCLID MASK, standalone processor (Paul 2026-09-27): the SAME Bjorklund K-of-N idea once embedded directly on
    // the arp (now removed, Paul 2026-09-28 — fully superseded by this), pulled out as its own downstream FOLD stage
    // (isModifierFoldable) so it gates ANY driver's notes, not just ARP's own — reuses euclidMaskHit/euclidMaskTieRun
    // unchanged. WALK/WAIT is deliberately NOT here (Paul: "happy to drop wait as an option" — it needs the driver's
    // own phase-index, which a downstream fold can't reach; see pending-tasks.md).
    var maskN: Int? = nil             // the mask window (steps). nil ⇒ 8
    var maskK: Int? = nil             // hits (K of N). nil ⇒ = N (OFF/pass-through)
    // harmonize (§3): up to 3 added voices, each an interval −24…+24 st (0 = voice OFF), plus a
    // velocity scale 0.1…1 applied to the ADDED voices (root stays full). B overrides the intervals.
    var harmIntervals: [Int]? = [0, 0, 0]
    var euclidPulsesFromPool: Bool? = false   // PULSES mode (user 2026-08-09): POOL = K follows the held-note count
    var euclidRate: ArpRate? = .r1_16         // GRID: the step grain (Paul 2026-08-27) — density lives HERE (+ K of N). Absolute, decoupled from SPAN (like riff/arp).
    var euclidSpanN: Int? = nil               // SPAN RE-ANCHOR (Paul 2026-08-27, RATE×ladder): nil/0 ⇒ FREE (phase forever) · 1·2·3·4·6·8·16(×2)·32(×4) ⇒ re-sync the pattern to step 0 every N columns. Was the WIDTH-span (n steps across the span, which just scaled the speed).
    var euclidLines: [EuclidLine]? = nil      // EUCLID LINES (§10, ratified): up to 8 lines (each K·N·ROTATE·INVERT·TARGET). nil ⇒ the single euclid above (byte-identical)
    var euclideousRiff: EuclideousRiff? = nil // EUCLIDEOUS's own shared riff pattern (Paul 2026-10-06) — only meaningful for Euclideous's cell; nil ⇒ the struct's own plain defaults
    // FOUR RIFFS (2026-10-14 ferry §7) — mirrors `PluginState.riffs`/`activeRiff` exactly (same name, same
    // migration), one struct per layer: THIS copy is what `BuildPage.swift`'s publish path actually feeds
    // the render engine (`p.euclideousRiff = euclideousRiff` already does this for the singular field — the
    // new plural one needs the identical treatment); `PluginState`'s own copy is the persisted document's.
    var riffs: [EuclideousRiff]? = nil
    var activeRiff: Int? = nil
    // THE RIFF (ferry "looper tabs replace the riff tabs") — mirrors `PluginState`'s own copy exactly
    // (same name, same migration): this is what `BuildPage.swift`'s publish line feeds the render engine.
    var euclideousLiveGrid: EuclideousRiff? = nil
    // THE LOOPER (§6/§8.5) — NEVER saved (no `PluginState` field at all): purely a live, ephemeral mirror
    // of `AudioUnitViewController`'s own @State, republished on every edit exactly like every other live
    // Euclideous control. `active == true` is the only thing that matters to the render engine — Off/
    // Armed are UI-only concepts (§2) that never produce a loop for the engine to read at all.
    var euclideousLooperActive: Bool? = nil
    var euclideousLooperStartBeat: Double? = nil      // B
    var euclideousLooperPasses: EuclideousLooperPasses? = nil   // N
    var euclideousLooperStartRanks: [Int]? = nil      // 8, frozen at B
    var euclideousLooperEvents: [EuclideousLoopEvent]? = nil    // capped 128/column at the write site (§3.4)
    var soloMask: UInt8? = nil    // LANE SOLO (2026-10-21): the EFFECTIVE solo mask (latched | held), composed at publish — only meaningful for Euclideous's cell; nil ⇒ 0 (no solo, byte-identical for every other chain)
    var euclideousLocks: [EuclideousLaneLock]? = nil   // LANE LOCK (2026-10-21): the four lanes' locks, composed at publish — only meaningful for Euclideous's cell; nil ⇒ nothing locked (byte-identical for every other chain)
    var lockRevs: UInt32? = nil   // LANE LOCK: the per-lane document revisions this snapshot was built from (one byte per lane) — the render thread compares them with the live word to know an edit is on its way (6.4)
    var destSlices: [Int]? = nil                // DEST MATRIX (Paul 2026-08-22 §5): 8 per-step emitters (−1=NONE·0=A…3=D) — hocket painted. nil ⇒ a rotating default
    var destRate: ArpRate? = nil                 // DEST's OWN CLOCK (Paul 2026-09-26, RATCHET-PATTERN-shaped): the matrix sweeps this rate, free-running — decoupled from whatever drives the notes through it. nil ⇒ 1/8
    // DEAL (Paul 2026-09-16): the simple output dealer — override the emitters, deal N1 → emitter 1, N2 → emitter 2 (repeat). All additive-Optional.
    var dealE1: Int? = nil                       // emitter 1 (0=A…3=D); nil ⇒ A
    var dealE2: Int? = nil                       // emitter 2 (0=A…3=D); nil ⇒ B
    var dealN1: Int? = nil                       // notes to emitter 1; nil ⇒ 1
    var dealN2: Int? = nil                       // notes to emitter 2; nil ⇒ 1
    var dealMode: DealMode? = nil                // when the deal advances; nil ⇒ OVER TIME
    // CLOCK (AcceptanceCriteria-clock-processor, ratified 2026-09-26; FIXED/WAVE modes REMOVED same day — Paul's
    // own spec describes one grid, not a mode choice — CLOCK is now always the DRAWN lane below). Note-transparent —
    // the transform reaches only a downstream fold consumer's OWN internal step machinery
    // (Router.clockTransformedBeat) or a driver's own tick generation (Router.driverClockBeat/Inverse), never grid
    // time (columns/windows/spans/reel) itself.
    var clockSpanN: Int? = nil                   // the lane's SPAN re-anchor (spanLadderValues); nil ⇒ ROW (8)
    // DRAWN (Stage 2, Paul 2026-09-26): the lane — RIFF's anatomy wearing time; Paul's own final spec for the whole
    // feature ("a grid with a variable number of steps, each step a mutually exclusive speed, and another row on
    // the same grid for glide") — wired to retime a DRIVER's own tick generation (Router.driverClockBeat/Inverse),
    // not just a downstream fold consumer. Per column: −1 = CARRY the previous rate · 0…8 = a ratio-ladder index.
    // `clockDrawnGlide[i]` true ⇒ column i RAMPS IN from the previous column's landed rate (a linear rate ramp —
    // quadratic phase, stateless — no cross-render memory needed) instead of jumping at column entry (SET). STEPS
    // need not be 16 — a short lane phase-drifts against the grid on purpose (a rotating tempo-cycle).
    var clockDrawnRatios: [Int]? = nil           // per-column ratio-ladder index, or −1 = CARRY; nil ⇒ all ×1
    var clockDrawnGlide: [Bool]? = nil           // per-column SET(false)|GLIDE(true); nil ⇒ all SET
    var clockDrawnSteps: Int? = nil              // the lane length 1…32; nil ⇒ 8
    // RATE REMOVED (Paul 2026-09-26): "what's the point of rate when we have a speed-per-step grid?" — a separate
    // column-duration dial was a second, independent multiplier stacked on top of the per-step speed, AND part of
    // why the matrix's playhead couldn't line up with what plays. A clock column now IS one grid column — its
    // width is always this cell's own step (S), the SAME S the rest of the chain/grid already uses.
    // KILL STEP (Paul 2026-09-26, sibling to CLOCK — a DISCRETE remap, not a continuous ratio warp): a row of
    // `killStepCount` on/off switches; a disabled step is removed from the downstream timeline, the enabled steps
    // repeat to fill the pass. UNLIKE clock, it carries its OWN RATE (an ordinary per-processor clock control, not
    // borrowed from the grid's S) — the "value" it hands downstream is exact only relative to that rate.
    var killStepCount: Int? = nil                // step count 1…32; nil ⇒ 8
    var killStepEnabled: [Bool]? = nil           // LEGACY (Paul 2026-09-27, decode-only migration source — nothing shipped ever
                                                  // wrote this after killStepMode landed): per-step ON/OFF. When killStepMode is
                                                  // absent, resolved as true→.on/false→.drop (byte-identical to before).
    var killStepMode: [KillStepMode]? = nil      // per-step ON·MUTE·DROP·PAUSE (Paul 2026-09-27); nil ⇒ derive from killStepEnabled, else all ON
    var killStepRate: ArpRate? = nil             // this stage's OWN clock; nil ⇒ 1/8
    var killStepSpanN: Int? = nil                // SPAN re-anchor (spanLadderValues, 0 = FREE); nil ⇒ ROW (8)
    var muteSlices: [Int]? = nil                // MUTE MATRIX (Paul 2026-08-25 §5): 8 per-onset-slice MUTED-emitter masks (bit i = emitter i muted; 0…15). nil ⇒ nothing muted (byte-identical)
    var riffRanks: [Int]? = nil                 // MONO per-step: 0 = REST · 1–8 = the pool rank to strike (nil ⇒ a default ascending figure)
    var riffDir: RiffDir? = nil                 // DIRECTION (Paul 2026-09-16): FWD (default) | REV | PENDULUM | PING-PONG | RANDOM | DRUNK — the order the stencil steps play
    var riffDirSeed: Int? = nil                 // RANDOM + DRUNK share one seed (mirrors arpSeed): nil until first rolled, rolled fresh whenever RANDOM or DRUNK is picked
    var riffDirBias: Double? = 0                // DRUNK only: −1…1, 0 = wanders evenly, +1 = forward-biased ("stumbles"), −1 = reverse-biased
    // CHORDS (ratified 2026-09-01): derive a diatonic progression from a key. v1 (C2) = PATTERN — the drawn degree matrix,
    // in a stage-declared key. C2b reads the SCALE door's declared key; C3 FOLLOW · C4 WALK. See SPEC-chords-stage.md.
    var chordsMode: ChordsMode? = nil           // PATTERN (the drawn matrix) · FOLLOW (door note → degree) · WALK (gravity dice)
    var chordsDegrees: [Int]? = nil             // the 8-step PATTERN matrix: per step −1 = CARRY (empty) · 0…6 = degree I…vii · 7 = REST
    var chordsVoicing: ChordVoicing? = nil      // TRIAD | 7TH | ADD9
    var chordsSpread: ChordSpread? = nil        // CLOSE | OPEN
    var chordsRotate: Int? = nil                // rotate the PATTERN matrix ◀n▶
    var chordsWalkSeed: Int? = nil              // WALK: the base seed (RE-ROLL = new seed) — C4
    var chordsRate: StepRate? = nil             // STEPS+RATE (Paul 2026-09-01): the PROGRESSION clock — a chord per rate-tick (PATTERN/WALK advance on this, NOT per grid column). Default 1/1 = one chord per bar.
    var chordsSteps: Int? = nil                 // the PATTERN matrix length 1…16 (the progression loops every N); default 8. FOLLOW ignores it.
    var chordsRateResolved: StepRate { chordsRate ?? .r1_1 }
    var chordsStepsResolved: Int { max(1, min(16, chordsSteps ?? 8)) }
    var chordsVoicingResolved: ChordVoicing { chordsVoicing ?? .triad }
    var chordsSpreadResolved: ChordSpread { chordsSpread ?? .close }
    // CHORDS GRID ferry (Paul 2026-10-24) §1.4: per-column chord COLOUR — 0 none · 1...6 = `ChordColour`'s raw
    // value (7·9·6·ADD9·SUS2·SUS4). Stored as plain `[Int]?` (not `[ChordColour]?`) to mirror `chordsDegrees`'s
    // own raw-int convention. nil ⇒ no colour anywhere, byte-identical to every document before this ferry.
    var chordsColours: [Int]? = nil
    /// The 8-step degree matrix, resolved — defaults to a I–vi–IV–V loop (0,0,5,5,3,3,4,4) so a fresh CHORDS plays.
    // SIZED TO THE MATRIX WIDTH (Paul 2026-09-16 fix): pad/truncate the degrees to EXACTLY `steps`, so chordsDegreeAt (which
    // loops on degrees.count) plays every authored column of a 9…16-wide matrix — the old fixed-8 truncation dropped columns
    // 8–15 (they wrapped/carried, screen ≠ audio). Short arrays carry-fill with -1; nil ⇒ the 8-degree default. steps=8 ⇒
    // byte-identical to the old resolver.
    func chordsDegreesResolved(steps: Int) -> [Int] {
        let d = chordsDegrees ?? [0, 0, 5, 5, 3, 3, 4, 4]
        let n = max(1, min(16, steps))
        return d.count == n ? d : (d.count > n ? Array(d.prefix(n)) : d + [Int](repeating: -1, count: n - d.count))
    }
    // CHORDS GRID ferry §1.2: ALWAYS 16 entries, independent of the live `steps` count — the columns beyond
    // `steps` are hidden, not cleared. `chordsDegreesResolved(steps:)` above still resolves/truncates AT `steps`
    // for SnapshotBuilder's per-render read (the only reader that ever wants the currently-audible width); every
    // EDIT (cell taps, STEPS changes) reads/writes THESE instead, or a shrink→edit→grow would silently lose the
    // hidden columns — which is exactly what `chordsDegreesResolved(steps:)` does today when used for a write.
    // §1.2, literal: "a padded column takes the chord ... of the last stored column" — repeat the LAST entry,
    // not a CARRY (-1) sentinel, so a legacy 8-entry document's columns 9-16 start out as plain copies of column
    // 8 (spec test 2), not as carries-that-happen-to-resolve-the-same-way. An empty/never-touched array has no
    // "last" to copy, so it falls back to CARRY (matches today's behaviour exactly, since there's nothing to copy).
    func chordsDegreesResolved16() -> [Int] {
        let d = chordsDegrees ?? [0, 0, 5, 5, 3, 3, 4, 4]
        if d.count >= 16 { return Array(d.prefix(16)) }
        guard let last = d.last else { return [Int](repeating: -1, count: 16) }
        return d + [Int](repeating: last, count: 16 - d.count)
    }
    /// Mirrors `chordsDegreesResolved16()` for the colour row (§1.4): a padded column copies the last stored
    /// column's colour too. An empty/never-touched array pads with 0 (no colour).
    func chordsColoursResolved16() -> [Int] {
        let c = chordsColours ?? []
        if c.count >= 16 { return Array(c.prefix(16)) }
        guard let last = c.last else { return [Int](repeating: 0, count: 16) }
        return c + [Int](repeating: last, count: 16 - c.count)
    }
    /// The four EUCLID rows for editing/rendering — ALWAYS exactly 4 (the 2026-09-29 fixed-row redesign; SHARED
    /// by the GridUI editor and SnapshotBuilder's resolve so the two can't independently derive this differently).
    /// A touched `euclidLines` array pads/truncates to 4 with silent rows (`pulses: 0` → `euclidPatternInto`
    /// yields all-false, confirmed safe — matches the idle-row mockup). An untouched (nil/empty) machine derives
    /// row 0 from the flat single-euclid fields it always had; rows 1–3 are silent — so an old doc resolves and
    /// sounds byte-identical to before this shipped.
    func euclidLinesForEditing() -> [EuclidLine] {
        // A pre-redesign line with `noteSel == nil` takes its pick from its own `target` / `pick`; resolved HERE, once, so every reader sees a concrete selector.
        func resolved(_ L: EuclidLine) -> EuclidLine {
            guard L.noteSel == nil else { return L }   // already touched under the new UI — leave as authored
            var out = L
            if L.target >= 1 { out.noteSel = EuclidNoteSel(rawValue: "N\(min(8, L.target))") ?? .all }
            else {
                switch L.pick ?? .all {
                case .all: out.noteSel = .all
                case .cycle: out.noteSel = .cycle
                case .low: out.noteSel = .low
                case .high: out.noteSel = .high
                case .random: out.noteSel = .random
                }
            }
            return out
        }
        let pad: ([EuclidLine]) -> [EuclidLine] = { a in
            Array((a.map(resolved) + Array(repeating: EuclidLine(pulses: 0, noteSel: .all), count: 4)).prefix(4))
        }
        return pad(euclidLines ?? [])
    }
}
// CHORDS mode (SPEC-chords-stage §1): where the degree comes from.
enum ChordsMode: String, Codable, CaseIterable { case pattern, follow, walk }
// TIMING LANE (Paul 2026-08-22 §5): NUDGE's second mode — FIXED = one offset · LANE = a per-column pocket (a centred SLIDER LANE).
enum NudgeMode: String, Codable, CaseIterable { case fixed = "FIXED", lane = "LANE" }
/// TAIL SPILL — what happens to an echo's pending repeats when the playhead leaves the cell's column. RING lets
/// them spill past the bar (the tail era's default); CUT kills the pending ones (the sounding note finishes its
/// gate); HAND is the deferred BIRTHSTONE (handed repeats fire into the pool below). Enum three-valued from day one.
enum EchoSpill: String, Codable, CaseIterable { case ring = "RING", cut = "CUT", hand = "HAND" }
// ECHO ROUTE (§7②, ratified 2026-08-22): where the repeats flow. DIRECT = the tail is the cell's final emitted set
// (position-blind, v1). CHAIN = each repeat is re-folded through the chain stages AFTER the ECHO slot at the repeat's
// own beat — so [ECHO→LENGTH] chokes/ties repeats by the slice they land in, [ECHO→SPLIT] thins trails to a register.
enum EchoRoute: String, Codable, CaseIterable { case direct = "DIRECT", chain = "CHAIN" }
// ECHO PITCH MODE (Paul 2026-09-29): SEMITONES = the old flat per-repeat step. IN-KEY replaces the removed POOL
// mode — each repeat walks to the NEXT in-key note (nextInKeyNote, Derivations.swift), live, from whichever ABCD
// receivers are selected (echoInKeyReceivers); echoPitch's SIGN is the only part of it that matters in this mode.
enum EchoPitchMode: String, Codable, CaseIterable { case semitones = "SEMITONES", inKey = "IN-KEY" }

struct Machine: Codable, Equatable {
    var machineID: String
    var type: ProcessorType
    // v3.0 (delta §7): per-Machine OUT CH is REMOVED — channel is a property of the WIRE (busChannels),
    // not the treatment. Old docs carrying an `outChannel` key decode fine (Codable ignores unknown keys).
    var transpose: Int = 0         // −24…+24, accumulates in chains, clamped — the ACTIVE type's transpose
    var morph: Double = 0          // DECODE-ONLY ZOMBIE — the per-machine morph AUParameter (was 200+i) was REMOVED 2026-09-16; the A/B morph layer is gone, the render reads only the A bag
    var paramsA: MachineParams = MachineParams()   // procA — the A face
    // DECODE-ONLY ZOMBIES — the A/B TWO-PROCESSOR morph layer was REMOVED with the morph params (2026-09-16). paramsB/
    // typeB are no longer read by the render (every effective* reads the single A bag); they're kept only so older docs
    // decode. The historical model: procB was a Machine's second face, `alt` flipped to it, `morph` was the position
    // toward it (same type ⇒ glide · different ⇒ swap at t≥0.5). None of that runs now.
    var paramsB: MachineParams = MachineParams()
    var typeB: ProcessorType? = nil
    // delta item 8: procB's transpose — STORED (COPY A→B + round-trip) but render-INERT in v1 (SnapMachine
    // carries a single transpose; both faces sound with A's, matching the old pair behavior). Making it
    // render-live is a future increment (SnapMachine.transposeB + effectiveTranspose + 400+i addresses).
    // Optional (append-only §12.0) → old docs decode nil; read via `transposeBResolved`.
    var transposeB: Int? = nil
    // LEGACY (delta §9 item 5, retired by item 8): the old morph PARTNER — an index 0…15 or nil. DECODE-ONLY
    // now: `migrateMachinePairsIfNeeded` copies the partner into procB, then the render ignores this. Kept
    // (never deleted) so an older build re-loading a migrated doc still reads the pair (lossless downgrade).
    var altMachine: Int? = nil
    // Per-TYPE stash of TRANSPOSE (spec revision): each processor type keeps its own transpose, so
    // switching type never leaks a pitch. Optional → v2 docs decode as nil (all-zero).
    var transposeByType: [Int]? = nil
    // §9 item 1 the ON TRIGGER SYSTEM (GUI iteration 1, 2026-07-26): per-Machine trigger assignments,
    // STORED INERT — no engine execution yet. Optional so pre-ON docs decode as nil → OnConfig() defaults.
    var on: OnConfig? = nil
    /// The ON config, nil-safe (missing ⇒ all-"—"/unchecked). Non-persisting read helper.
    var onResolved: OnConfig { on ?? OnConfig() }
    // Cells/desk overhaul C1: an OPTIONAL Machine NAME (the user's word). Optional → old docs decode nil.
    var name: String? = nil
    /// The custom name if set, else the TYPE name (today's label). Never empty.
    var nameResolved: String { (name.flatMap { $0.isEmpty ? nil : $0 }) ?? type.rawValue }
    // Cells/desk overhaul D1: whether this Machine is DEFINED (a palette chip) vs an undefined "+" slot. Optional
    // → old docs decode nil ⇒ DEFINED (all 16 as today). Non-persisting read helper below.
    var defined: Bool? = nil
    var isDefined: Bool { defined ?? true }
    // CELL MACHINE stage-3 (feat/EditPageSpike): the shared TEMPLATE chain — this machine's default processor
    // chain, followed by every cell of this machine with NO per-cell override (Cell.processors == nil), in every
    // scene. Optional (append-only §12.0) → old docs decode nil; the builder then falls back to the legacy
    // single-processor type+paramsA. Editing it in the "ALL <machine>" scope changes every following cell at once.
    var templateChain: [ProcessorSlot]? = nil

    /// delta item 8: does this Machine have a second processor (procB)? Drives morph/ALT availability + greying.
    var hasProcB: Bool { typeB != nil }
    /// procB's transpose, nil-safe (missing ⇒ 0). Render-inert in v1; kept for COPY A→B + round-trip.
    var transposeBResolved: Int { transposeB ?? 0 }

}

// MARK: - ON trigger config (§9 item 1) — per-Machine; GUI iteration 1 stores it INERT (no engine yet).
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

/// The five ON rows for one Machine. All fields defaulted (none/unchecked), so `OnConfig()` is "unassigned".
/// Every field non-Optional with a default — the whole struct is written together; `Machine.on` is the
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
    var driftPct: Int = 10                     // INERT — the MORPH-DRIFT arrive treatment was removed with the morph layer (Derivations arriveMorph gone)
    var driftMode: DriftMode = .pingpong       // INERT — ditto
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
// DECODE-TOLERANT (CR-8 class, code-review finding 2026-10-04): `Machine`'s own decode-tolerant `init(from:)`
// reads `on` via `c.decodeIfPresent(OnConfig.self, forKey: .on)` — but `decodeIfPresent` only swallows a
// MISSING-KEY error at THAT level; if the key is present (true for any doc that's ever touched the ON editor)
// and OnConfig's OWN synthesized decode throws because one of ITS 16 non-Optional fields is missing, that
// throw propagates straight through Machine's "safe" init, defeating it entirely. Same decodeIfPresent-every-
// field pattern as Cell/Machine, scoped to this nested type so adding a 17th OnConfig field can never regress
// to a whole-document factory reset.
extension OnConfig {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tap = try c.decodeIfPresent(OnTap.self, forKey: .tap) ?? .none
        tapWhen = try c.decodeIfPresent(OnTapWhen.self, forKey: .tapWhen) ?? .now
        tapFor = try c.decodeIfPresent(OnTapFor.self, forKey: .tapFor) ?? .retap
        hold = try c.decodeIfPresent(OnHold.self, forKey: .hold) ?? .none
        holdRelease = try c.decodeIfPresent(OnHoldRelease.self, forKey: .holdRelease) ?? .spring
        sliceSize = try c.decodeIfPresent(SliceSize.self, forKey: .sliceSize) ?? .quarter
        octUp = try c.decodeIfPresent(Bool.self, forKey: .octUp) ?? true
        arrive = try c.decodeIfPresent(OnArrive.self, forKey: .arrive) ?? .none
        arriveEvery = try c.decodeIfPresent(Int.self, forKey: .arriveEvery) ?? 1
        driftPct = try c.decodeIfPresent(Int.self, forKey: .driftPct) ?? 10
        driftMode = try c.decodeIfPresent(DriftMode.self, forKey: .driftMode) ?? .pingpong
        leave = try c.decodeIfPresent(OnLeave.self, forKey: .leave) ?? .none
        sceneEntrance = try c.decodeIfPresent(Bool.self, forKey: .sceneEntrance) ?? false
        entrancePass = try c.decodeIfPresent(Int.self, forKey: .entrancePass) ?? 1
        sceneExit = try c.decodeIfPresent(Bool.self, forKey: .sceneExit) ?? false
        exitPass = try c.decodeIfPresent(Int.self, forKey: .exitPass) ?? 1
        sceneResetMorph = try c.decodeIfPresent(Bool.self, forKey: .sceneResetMorph) ?? false
        sceneAutoArm = try c.decodeIfPresent(Bool.self, forKey: .sceneAutoArm) ?? false
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
// DECODE-TOLERANT (CR-8 class, code-review finding 2026-10-04) — same reasoning as OnConfig above: `Cell`'s
// own init reads this via `decodeIfPresent(ChordSplit.self, forKey: .chordSplit)`, which only guards a MISSING
// key, not a nested decode throw. ChordSplit/VelWindow/Chop all get the same treatment below.
extension ChordSplit {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(SplitMode.self, forKey: .mode) ?? .all
        n = try c.decodeIfPresent(Int.self, forKey: .n) ?? 2
        note = try c.decodeIfPresent(Int.self, forKey: .note) ?? 60
        high = try c.decodeIfPresent(Bool.self, forKey: .high) ?? true
    }
}

/// §cell-edit D — VELOCITY WINDOW: a MIDI-IN cell admits only source notes whose velocity is in [floor, ceil].
/// The default (1…127) admits everything; it gates at the source boundary, BEFORE the chord split selects.
struct VelWindow: Codable, Equatable {
    var floor: Int = 1       // 1…127
    var ceil: Int = 127      // 1…127 (≥ floor)
}
extension VelWindow {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        floor = try c.decodeIfPresent(Int.self, forKey: .floor) ?? 1
        ceil = try c.decodeIfPresent(Int.self, forKey: .ceil) ?? 127
    }
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
extension Chop {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mainMask = try c.decodeIfPresent(UInt8.self, forKey: .mainMask) ?? 0xFF
        altMask = try c.decodeIfPresent(UInt8.self, forKey: .altMask) ?? 0
        muteMask = try c.decodeIfPresent(UInt8.self, forKey: .muteMask) ?? 0
        altDest = try c.decodeIfPresent(Set<Bus>.self, forKey: .altDest) ?? []
    }
}

struct Cell: Codable, Equatable {
    var machineID: String
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
    // processor slots (pedalboard model), replacing the shared-Machine treatment. Optional (append-only §12.0)
    // → old docs decode nil; the SnapshotBuilder falls back to a 1-slot head seeded from the referenced
    // Machine's A face (the cell can't see its Machine here, so resolution lives builder-side). Stage 1 renders
    // the HEAD slot + per-slot bypass; slots 2…8 are stored but not yet executed (serial chain = a later stage).
    var processors: [ProcessorSlot]? = nil
    // CELL LIBRARY star rating (0–5). Optional → old library files decode nil ⇒ unrated (0). Library metadata only;
    // grid cells leave it nil. (Paul 2026-08-17)
    var stars: Int? = nil
    var starsResolved: Int { max(0, min(5, stars ?? 0)) }

}

// DECODE-TOLERANCE (CR-8 class, 2026-08-29): the synthesized Decodable THROWS on any missing key EVEN for a
// field with a `= default` (Swift ignores the default on decode). `inputChannel` was added at v3.0 (non-Optional),
// so a genuine formatVersion-2 document lacking it would throw at Cell decode — BEFORE migrateLegacyRoutingIfNeeded()
// can run — and the WHOLE session silently factory-resets (the exact data-loss class as PluginState's CR-8). This
// decodeIfPresent-every-field init (the proven Macro/BuildPart pattern, in an EXTENSION so the memberwise init +
// synthesized Encodable stay) tolerates any missing key. Fields stay non-Optional and encode IDENTICALLY (a present
// key round-trips byte-for-byte, seal/twin/Equatable unchanged) — only a MISSING key now falls back to its default
// instead of throwing. machineID is genuinely required (a cell must name its machine) → a hard decode.
extension Cell {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machineID      = try c.decode(String.self, forKey: .machineID)                          // required — a cell must have a machine
        stack         = try c.decodeIfPresent(Bool.self, forKey: .stack) ?? false
        buses         = try c.decodeIfPresent(Set<Bus>.self, forKey: .buses) ?? [.a]
        srcMix        = try c.decodeIfPresent(Bool.self, forKey: .srcMix) ?? false
        alt           = try c.decodeIfPresent(Bool.self, forKey: .alt) ?? false
        bypassed      = try c.decodeIfPresent(Bool.self, forKey: .bypassed) ?? false
        muted         = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        inputRow      = try c.decodeIfPresent(Int.self, forKey: .inputRow)
        inputChannel  = try c.decodeIfPresent(Int.self, forKey: .inputChannel) ?? 0            // the v3.0 field that made a v2 doc throw
        inputReceiver = try c.decodeIfPresent(Int.self, forKey: .inputReceiver)
        chordSplit    = try c.decodeIfPresent(ChordSplit.self, forKey: .chordSplit)
        velWindow     = try c.decodeIfPresent(VelWindow.self, forKey: .velWindow)
        chop          = try c.decodeIfPresent(Chop.self, forKey: .chop)
        processors    = try c.decodeIfPresent([ProcessorSlot].self, forKey: .processors)
        stars         = try c.decodeIfPresent(Int.self, forKey: .stars)
    }
}
// DECODE-TOLERANT (CR-8, Paul 2026-09-08 housekeeping): the same guard the `Cell` init above uses, extended to the
// remaining central persisted types. Synthesized Decodable throws `keyNotFound` on a MISSING non-Optional key (even one
// with a `= default`), and these are decoded INSIDE PluginState's arrays — so one throw = the WHOLE document decode
// throws = a factory reset. A decodeIfPresent-every-field init means adding a non-Optional field later can never lose an
// older save. The memberwise init + synthesized encode/CodingKeys survive (custom init is in an extension). Round-trip-tested.
extension Machine {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        machineID = try c.decodeIfPresent(String.self, forKey: .machineID) ?? "c0"
        type = try c.decodeIfPresent(ProcessorType.self, forKey: .type) ?? .arp
        transpose = try c.decodeIfPresent(Int.self, forKey: .transpose) ?? 0
        morph = try c.decodeIfPresent(Double.self, forKey: .morph) ?? 0
        paramsA = try c.decodeIfPresent(MachineParams.self, forKey: .paramsA) ?? MachineParams()
        paramsB = try c.decodeIfPresent(MachineParams.self, forKey: .paramsB) ?? MachineParams()
        typeB = try c.decodeIfPresent(ProcessorType.self, forKey: .typeB)
        transposeB = try c.decodeIfPresent(Int.self, forKey: .transposeB)
        altMachine = try c.decodeIfPresent(Int.self, forKey: .altMachine)
        transposeByType = try c.decodeIfPresent([Int].self, forKey: .transposeByType)
        on = try c.decodeIfPresent(OnConfig.self, forKey: .on)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        defined = try c.decodeIfPresent(Bool.self, forKey: .defined)
        templateChain = try c.decodeIfPresent([ProcessorSlot].self, forKey: .templateChain)
    }
}
extension ProcessorSlot {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        type = try c.decodeIfPresent(ProcessorType.self, forKey: .type) ?? .arp
        params = try c.decodeIfPresent(MachineParams.self, forKey: .params) ?? MachineParams()
        bypassed = try c.decodeIfPresent(Bool.self, forKey: .bypassed) ?? false
        paramsAlt = try c.decodeIfPresent(MachineParams.self, forKey: .paramsAlt)
        bypassedAlt = try c.decodeIfPresent(Bool.self, forKey: .bypassedAlt)
    }
}
extension SceneState {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        cells = try c.decodeIfPresent([[Cell?]].self, forKey: .cells) ?? Array(repeating: Array(repeating: Cell?.none, count: 8), count: 8)
        stepRate = try c.decodeIfPresent(StepRate.self, forKey: .stepRate) ?? .r1_2
        swing = try c.decodeIfPresent(Int.self, forKey: .swing) ?? 50
        rowStepRate = try c.decodeIfPresent([StepRate?].self, forKey: .rowStepRate)
        rowLen = try c.decodeIfPresent([Int?].self, forKey: .rowLen)
        rowLaunchAnchor = try c.decodeIfPresent([Double].self, forKey: .rowLaunchAnchor)   // PLAY-FERRY LAUNCH: ephemeral; nil on document scenes
        rowLane = try c.decodeIfPresent([UInt16].self, forKey: .rowLane)
        masterKey = try c.decodeIfPresent(Int.self, forKey: .masterKey)
        activeRow = try c.decodeIfPresent([Int?].self, forKey: .activeRow)
        row8On = try c.decodeIfPresent([Bool].self, forKey: .row8On)
    }
}
extension Receiver {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        channel = try c.decodeIfPresent(Int.self, forKey: .channel) ?? 0
        channelMask = try c.decodeIfPresent(UInt16.self, forKey: .channelMask)
        mpeMerge = try c.decodeIfPresent(Bool.self, forKey: .mpeMerge) ?? false
        muted = try c.decodeIfPresent(Bool.self, forKey: .muted) ?? false
        inputEnabled = try c.decodeIfPresent(Bool.self, forKey: .inputEnabled)
        rangeLo = try c.decodeIfPresent(Int.self, forKey: .rangeLo)
        rangeHi = try c.decodeIfPresent(Int.self, forKey: .rangeHi)
        cable = try c.decodeIfPresent(Int.self, forKey: .cable)
        controllerMask = try c.decodeIfPresent(Int.self, forKey: .controllerMask)
        latchAdd = try c.decodeIfPresent(Bool.self, forKey: .latchAdd)
        latchPiano = try c.decodeIfPresent(Bool.self, forKey: .latchPiano)
        pianoNotes = try c.decodeIfPresent([Int].self, forKey: .pianoNotes)
        scaleRoot = try c.decodeIfPresent(Int.self, forKey: .scaleRoot)
        scaleType = try c.decodeIfPresent(ScaleType.self, forKey: .scaleType)
        scaleBaseOct = try c.decodeIfPresent(Int.self, forKey: .scaleBaseOct)
        scaleOctaves = try c.decodeIfPresent(Int.self, forKey: .scaleOctaves)
        scalePools = try c.decodeIfPresent([ScalePool].self, forKey: .scalePools)
        activeScale = try c.decodeIfPresent(Int.self, forKey: .activeScale)
        chordSeqs = try c.decodeIfPresent([MachineParams].self, forKey: .chordSeqs)
        activeChord = try c.decodeIfPresent(Int.self, forKey: .activeChord)
        doorMode = try c.decodeIfPresent(DoorMode.self, forKey: .doorMode)
        replayPasses = try c.decodeIfPresent(Int.self, forKey: .replayPasses)
        fileClip = try c.decodeIfPresent([MidiFile.NoteEvent].self, forKey: .fileClip)
        fileLoopBeats = try c.decodeIfPresent(Double.self, forKey: .fileLoopBeats)
        fileName = try c.decodeIfPresent(String.self, forKey: .fileName)
        excludeDoor = try c.decodeIfPresent(Int.self, forKey: .excludeDoor)
        excludeMode = try c.decodeIfPresent(ExcludeMode.self, forKey: .excludeMode)
        excludeReject = try c.decodeIfPresent(ExcludeReject.self, forKey: .excludeReject)
    }
}

// CELL MACHINE — one stage of a cell's processor chain: a processor type + its params + a true-bypass toggle.
// Reuses MachineParams verbatim as the per-slot param bag (append-only §12.0). Codable/Equatable so the chain
// round-trips like every other cell field.
struct ProcessorSlot: Codable, Equatable {
    var type: ProcessorType
    var params: MachineParams = MachineParams()
    var bypassed: Bool = false     // per-slot TRUE-BYPASS (the chain's debugger — proposal §2 C3)
    // MACRO AUTHORING (§7): the persisted ALTERNATIVE control set — reopening MACRO shows the last-authored B.
    // Additive Optional → old docs decode nil (no ALT authored yet). The binding stores the delta (ALT − MAIN).
    var paramsAlt: MachineParams? = nil
    var bypassedAlt: Bool? = nil
}

// MARK: - Receiver (delta §9 item 11) — a shared, named MIDI-input object

/// One of four document-level MIDI receivers. A MIDI-IN cell subscribes to a receiver (FROM RECEIVER n)
/// and inherits its channel filter; the receiver also carries a persisted input-mute (the input twin of
/// the §6a emitter mute) and a per-receiver MPE-merge flag (the "MPE front door" — field only for now;
/// merge semantics are their own later mini-spec). Receiver MACHINE is assigned by index (the fixed
/// infrastructure family), not stored. note-RANGE (register splits) is a later addition — no field yet.
/// THE CONFIG SHEETS (Paul 2026-08-20): a door's MODE — LATCH (notes toggle in/out of the pool, the old KEYS latch) ·
/// HOLD (chord-detect-and-replace, the old CHORD latch) · KEYS (the on-screen keyboard, the old PIANO latch) · REPLAY
/// (the door input ring loops as living input — stage 3) · FILE (a loaded .mid loops as living input — stage 4). The 3
/// EXISTING modes map to the legacy latchAdd/latchPiano fields; REPLAY/FILE are reserved (not yet wired → a HOLD-like
/// fallback until their stages land).
// THRU (Paul 2026-08-23) = "play it straight": the door feeds LIVE input to the grid with NO latching (the neutral
// default). It's the same audible feed as an un-armed latch door, but it CAN'T be armed — its strip button reads "SET"
// (static) and opens the config, rather than arming. LATCH/HOLD/KEYS/REPLAY/FILE are the armable modes.
enum DoorMode: String, Codable, CaseIterable { case thru, latch, hold, keys, replay, file, scale, chord }

// THE SCALE DOOR (ratified spec AcceptanceCriteria-scale-door §1, 2026-08-26): the sixth door mode's pool = every note of
// a chosen scale — a standing pitch-class set, no playing or typing. "KEYS with a picker": the engine IS the KEYS pool,
// derived from ROOT + SCALE + RANGE instead of tapped. `intervals` = semitone degrees from the root (one octave).
enum ScaleType: String, Codable, CaseIterable {
    case major, naturalMinor, harmonicMinor, melodicMinor, dorian, mixolydian, lydian, phrygian
    case majorPentatonic, minorPentatonic, blues, wholeTone, chromatic
    var intervals: [Int] {
        switch self {
        case .major:           return [0, 2, 4, 5, 7, 9, 11]
        case .naturalMinor:    return [0, 2, 3, 5, 7, 8, 10]
        case .harmonicMinor:   return [0, 2, 3, 5, 7, 8, 11]
        case .melodicMinor:    return [0, 2, 3, 5, 7, 9, 11]   // ascending form
        case .dorian:          return [0, 2, 3, 5, 7, 9, 10]
        case .mixolydian:      return [0, 2, 4, 5, 7, 9, 10]
        case .lydian:          return [0, 2, 4, 6, 7, 9, 11]
        case .phrygian:        return [0, 1, 3, 5, 7, 8, 10]
        case .majorPentatonic: return [0, 2, 4, 7, 9]
        case .minorPentatonic: return [0, 3, 5, 7, 10]
        case .blues:           return [0, 3, 5, 6, 7, 10]
        case .wholeTone:       return [0, 2, 4, 6, 8, 10]
        case .chromatic:       return [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]
        }
    }
    var label: String {
        switch self {
        case .major: return "MAJOR"; case .naturalMinor: return "MINOR"; case .harmonicMinor: return "HARM MIN"
        case .melodicMinor: return "MEL MIN"; case .dorian: return "DORIAN"; case .mixolydian: return "MIXO"
        case .lydian: return "LYDIAN"; case .phrygian: return "PHRYGIAN"; case .majorPentatonic: return "MAJ PENT"
        case .minorPentatonic: return "MIN PENT"; case .blues: return "BLUES"; case .wholeTone: return "WHOLE"; case .chromatic: return "CHROMATIC"
        }
    }
}

// FOUR SCALE POOLS (Paul 2026-09-04): a SCALE door configures FOUR scale pools and switches between them LIVE (RADIO —
// exactly one active) via a pop-up on the strip SCALE button. One pool = root · scale · home-octave window (base + span),
// the exact shape of the legacy single scale. `Codable, Equatable`; the defaults match the legacy single-scale defaults
// (C major, C3, 2 octaves) so a fresh pool is byte-identical to an unset legacy scale door.
struct ScalePool: Codable, Equatable {
    var root: Int = 0            // pitch class 0=C…11=B
    var type: ScaleType = .major
    var baseOct: Int = 3         // home octave
    var octaves: Int = 2         // span
}
// DECODE-TOLERANT (CR-8 class, code-review finding 2026-10-04) — `Receiver`'s own init reads this via
// `decodeIfPresent([ScalePool].self, forKey: .scalePools)`, which only guards a MISSING key/array, not a
// per-element decode throw inside ScalePool itself. Same treatment as OnConfig/ChordSplit/VelWindow/Chop.
extension ScalePool {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        root = try c.decodeIfPresent(Int.self, forKey: .root) ?? 0
        type = try c.decodeIfPresent(ScaleType.self, forKey: .type) ?? .major
        baseOct = try c.decodeIfPresent(Int.self, forKey: .baseOct) ?? 3
        octaves = try c.decodeIfPresent(Int.self, forKey: .octaves) ?? 2
    }
}

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
    // RANGE (2026-08-03, redesign §2): the door's note WINDOW — it admits only notes with lo ≤ note ≤ hi. UPSTREAM
    // of the latch and the grid feed (a note outside the window is as if unplayed, for this door). Optional so old
    // docs decode nil ⇒ ALL (0…127). Persisted rig config. `rangeLo`/`rangeHi` are MIDI note numbers (0…127).
    var rangeLo: Int? = nil
    var rangeHi: Int? = nil
    /// The note window, nil-safe + clamped: missing ⇒ full range. Non-persisting read helpers.
    var rangeLoResolved: UInt8 { UInt8(max(0, min(127, rangeLo ?? 0))) }
    var rangeHiResolved: UInt8 { max(rangeLoResolved, UInt8(max(0, min(127, rangeHi ?? 127)))) }   // CR-18[extra]: order the bounds — an inverted decoded window (hi < lo) would otherwise silently kill the door
    // (The door-level BYPASS toggle — `bypass`/`bypassDest`, redesign §1/§2 — was RETIRED 2026-08-25 (Paul: unused; the
    // no-machine LIVE WIRE covers the passthrough case). Codable is synthesized, so an old doc's `bypass`/`bypassDest`
    // keys simply decode away. Do NOT re-add these names — the wire path (`passEmitterMask`) is the replacement.)
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
    /// TRUE ⟺ the RESOLVED door mode is LATCH (the note-toggle capture branch). Derived from `doorModeResolved` so the
    /// engine's capture branch and the UI's mode display can NEVER disagree (Paul 2026-09-07 bug: an UNSET door displayed
    /// HOLD via doorModeResolved's `.hold` default but this resolver's old `latchAdd ?? true` sent it down the LATCH
    /// note-toggle branch → HOLD was silent/toggling). Explicit LATCH → true; explicit HOLD/KEYS/etc. → false; a legacy
    /// `latchAdd` flag is honoured through doorModeResolved; an unset door → HOLD (false), matching the display + makeInit.
    var latchAddResolved: Bool { doorModeResolved == .latch }
    // PIANO latch (2026-08-10): a third latch mode — the frozen pool is CHOSEN from an on-screen keyboard, not captured
    // from live input. When on (+ the latch armed), `pianoNotes` feed the grid as the frozen chord. Optional so old
    // docs decode nil ⇒ off. Persisted rig config. `latchPiano` overrides KEYS|CHORD when true.
    var latchPiano: Bool? = nil
    var pianoNotes: [Int]? = nil
    // THE SCALE DOOR (ratified §1): root (0=C…11=B) · scale · the home-octave window (base octave + how many octaves). The
    // pool is DERIVED (scaleNotes) and fed through the KEYS pipeline, so SCALE self-arms, honours EXCLUDE, and plays along
    // exactly like a piano door. Additive-Optional — nil ⇒ sensible defaults (C major, C3, 2 octaves); no effect on old docs.
    var scaleRoot: Int? = nil
    var scaleType: ScaleType? = nil
    var scaleBaseOct: Int? = nil
    var scaleOctaves: Int? = nil
    // FOUR SCALE POOLS (Paul 2026-09-04): the SCALE door now holds FOUR configurable pools and switches between them live
    // (RADIO, one active). Additive-Optional — nil ⇒ the legacy SINGLE scale (the four fields above) IS pool 0, active, and
    // slots 1–3 default; byte-identical for old docs. `activeScale` 0…3 is the radio selection. The whole render pipeline
    // reads `scaleRootResolved`/`scaleTypeResolved`/`scaleBaseOctResolved`/`scaleOctavesResolved`, now sourced from the
    // ACTIVE pool — so the builder/box/kernel/CHORDS are untouched; switching the radio republishes with the new scale.
    var scalePools: [ScalePool]? = nil
    var activeScale: Int? = nil
    /// The active pool index, clamped. A legacy door (no scalePools) is ALWAYS pool 0 (byte-identical; ignores any stray activeScale).
    var activeScaleResolved: Int { scalePools == nil ? 0 : max(0, min(3, activeScale ?? 0)) }
    /// FOUR concrete pools. Present ⇒ pad/truncate to 4. Absent ⇒ MIGRATE: pool 0 = the legacy single scale, pools 1–3 default.
    var scalePoolsResolved: [ScalePool] {
        if let p = scalePools {
            var out = Array(p.prefix(4))
            while out.count < 4 { out.append(ScalePool()) }
            return out
        }
        let legacy = ScalePool(root: scaleRoot ?? 0, type: scaleType ?? .major, baseOct: scaleBaseOct ?? 3, octaves: scaleOctaves ?? 2)
        return [legacy, ScalePool(), ScalePool(), ScalePool()]
    }
    /// The ACTIVE pool — the single source the four resolvers below read (so the engine sees exactly one scale at a time).
    var activePool: ScalePool { scalePoolsResolved[activeScaleResolved] }
    var scaleRootResolved: Int { let r = activePool.root; return (r % 12 + 12) % 12 }
    var scaleTypeResolved: ScaleType { activePool.type }
    var scaleBaseOctResolved: Int { max(0, min(8, activePool.baseOct)) }
    /// The KEY label of a SCALE door ("A MIXO"), else nil — the chip-never-lies readout, shared by the machine-column
    /// receiver chip AND the MIDI-config tab bar so they can never disagree. (2026-08-31)
    var scaleLabel: String? {
        guard doorModeResolved == .scale else { return nil }
        return euclideousKeyLabel(root: scaleRootResolved, type: scaleTypeResolved)   // shared with the Euclideous header's key pill
    }
    var scaleOctavesResolved: Int { max(1, min(4, activePool.octaves)) }
    // THE CHORD DOOR = a chord SEQUENCER (Paul 2026-09-04): the door reuses the CHORDS PROCESSOR's config wholesale — each of
    // FOUR instances IS a `MachineParams` (only its `chords*` fields are used), so the door's editor + per-beat derivation are
    // literally the processor's, and future CHORDS work reflects on the door for free. Radio-switched (activeChord). Additive-
    // Optional; nil ⇒ four INTERESTING default progressions (`defaultChordSeqs`). The pool is TIME-VARYING: the Kernel walks
    // the progression on the beat (PATTERN/WALK) at the chord RATE, keyed by the SCALE door named in `chordsScaleRef`.
    // (The old single-chord `chordPools`/`ChordPool` shape, shipped 2026-09-04 fe708c7, is gone — its stale JSON key decodes
    // away harmlessly since Codable ignores unknown keys; a doc from that few-hour window re-seeds the default progressions.)
    var chordSeqs: [MachineParams]? = nil
    var activeChord: Int? = nil
    var chordSeqsResolved: [MachineParams] {
        guard let s = chordSeqs else { return Receiver.defaultChordSeqs }
        var out = Array(s.prefix(4)); while out.count < 4 { out.append(MachineParams()) }; return out
    }
    /// FOUR interesting default progressions (all reference the KEY-FROM door D per the default rig; PATTERN, one chord/bar).
    static let defaultChordSeqs: [MachineParams] = {
        func seq(_ degrees: [Int], steps: Int, voicing: ChordVoicing = .triad) -> MachineParams {
            var p = MachineParams()
            p.chordsMode = .pattern; p.chordsDegrees = degrees; p.chordsSteps = steps
            return p
        }
        return [
            seq([0, 4, 5, 3], steps: 4),                    // AXIS: I–V–vi–IV
            seq([0, 5, 3, 4], steps: 4),                    // 50s: I–vi–IV–V
            seq([1, 4, 0, 5], steps: 4, voicing: .seventh), // JAZZ turnaround: ii7–V7–I7–vi7
            seq([0, 4, 5, 2, 3, 0, 3, 4], steps: 8),        // PACHELBEL: I–V–vi–iii–IV–I–IV–V
        ]
    }()
    /// KEYS-style derived pool: on for an explicit KEYS **or SCALE** door (a scale is a pre-typed pool); else the legacy
    /// field EXACTLY (byte-identical for old docs). The note SOURCE differs (tapped keys vs the derived scale set).
    var latchPianoResolved: Bool { doorMode.map { $0 == .keys || $0 == .scale || $0 == .chord } ?? (latchPiano ?? false) }
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
        if let la = latchAdd { return la ? .latch : .hold }   // honour an explicit legacy KEYS|CHORD toggle
        return .hold                                          // DEFAULT: an unset receiver defaults to HOLD (Paul 2026-08-31)
    }
    // KEYS EXCLUDE — the COMPLEMENT DOOR (Paul 2026-08-22): in KEYS mode, this door's pool = the typed set MINUS the
    // excluded door's current notes, by PITCH CLASS, live. nil/-1 ⇒ OFF; 0–3 ⇒ subtract that door (never self). Type a
    // palette here, exclude the chord door → this door plays everything the chord isn't (the flourish door).
    var excludeDoor: Int? = nil
    var excludeDoorResolved: Int { let d = excludeDoor ?? -1; return (d >= 0 && d <= 3) ? d : -1 }
    // THE KEY FILTER (ratified scale-door §3, 2026-08-26): the referenced input (excludeDoor) is either SUBTRACTED (MINUS —
    // the flourish/complement) or INTERSECTED (ONLY — consonance-locked, in-key). Out-of-set notes are BLOCKed (silence) or
    // SNAPped (remapped to the nearest legal note — the jam-proof keyboard). Pitch-class, per the CLAIM law. Additive-
    // Optional — nil ⇒ MINUS · BLOCK (today's ratified nature; byte-identical for old docs).
    var excludeMode: ExcludeMode? = nil
    var excludeReject: ExcludeReject? = nil
}

// §3: the two key-filter axes. MINUS = subtract the reference (the complement door) · ONLY = intersect (the key/chord lock).
// BLOCK = an out-of-set note is silence · SNAP = it sounds as the nearest legal note (the FOLD/nearest family).
enum ExcludeMode: String, Codable, CaseIterable { case minus, only }
enum ExcludeReject: String, Codable, CaseIterable { case block, snap }

// POOL-STEP UNITS (ratified §2): an offset counts in SEMITONES (chromatic) or POOL degrees (against the chain's pool).
enum PitchUnits: String, Codable, CaseIterable { case semitones, pool }
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
    var rowLaunchAnchor: [Double]? = nil  // PLAY-FERRY LAUNCH (Paul 2026-09-09): per-ENGINE-row launch phase anchor in beats (0 ⇒ no anchor, transport-locked). Ephemeral (composed for the BUILD play grid), additive-Optional so old docs decode nil.
    // PER-ROW LAP (Paul 2026-08-19): per-row column-loop mask, so the BUILD staging + perform grids loop INDEPENDENTLY
    // in one combined scene. nil ⇒ no per-row lap (the render uses the ephemeral global lap, GRID-tab behaviour).
    var rowLane: [UInt16]? = nil           // count Snap.cols when set; entry = that row's loop mask (0 = no loop)
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

    // ROW 8 (Paul 2026-08-22): the TOGGLE/RADIO lit state of the 8 action cells is captured PER SCENE (a scene switch
    // carries the lit toggles; HELD/ONE-SHOT acts are momentary and never stored). Additive-Optional → nil ⇒ all off.
    var row8On: [Bool]? = nil
    /// The 8 lit flags, nil/short-array safe (missing ⇒ off). Non-persisting read helper.
    var row8OnResolved: [Bool] {
        let o = row8On ?? []
        return (0..<8).map { $0 < o.count ? o[$0] : false }
    }

    static func empty() -> SceneState {
        SceneState(cells: Array(repeating: Array(repeating: nil, count: Snap.rows), count: Snap.maxCols))   // §E: maxCols(16) columns × Snap.rows(16) — rows 0–7 visible, 8–15 the hidden play layer; cols 8–15 empty until a part is 16-wide
    }

    /// A scene with no placed cells — the sparse "+" slot on the strip (never destroyed; just absent).
    var isEmpty: Bool { cells.allSatisfy { $0.allSatisfy { $0 == nil } } }


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
// DECODE-TOLERANT (CR-8 class, code-review finding 2026-10-04): unlike Cell/Machine, this struct had ZERO
// Optional fields and no custom init at all — the next field added here would throw on any doc containing a
// macro binding, factory-resetting the whole session. `param: ""` falls back to an unrecognized MacroParam raw
// value (silently inert, the honest "doesn't match any known param" case, not a wrong guess); `delta: 0` is the
// safe no-op offset (home, nothing to apply) — same defaults MacroEmitterTarget/MacroCellValue use below.
extension MacroTarget {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        col = try c.decodeIfPresent(Int.self, forKey: .col) ?? 0
        row = try c.decodeIfPresent(Int.self, forKey: .row) ?? 0
        slot = try c.decodeIfPresent(Int.self, forKey: .slot) ?? 0
        param = try c.decodeIfPresent(String.self, forKey: .param) ?? ""
        delta = try c.decodeIfPresent(Double.self, forKey: .delta) ?? 0
    }
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
// DECODE-TOLERANT (CR-8 class, code-review finding 2026-10-04) — same gap and same fix as MacroTarget above.
extension MacroEmitterTarget {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        emitter = try c.decodeIfPresent(Int.self, forKey: .emitter) ?? 0
        param = try c.decodeIfPresent(String.self, forKey: .param) ?? ""
        delta = try c.decodeIfPresent(Double.self, forKey: .delta) ?? 0
    }
}

/// PER-CELL macro VALUE (macro-automation §A2, Paul §K1 2026-09-01): PUNCH draws a per-cell value/state and SPAN a
/// sweep, so a macro's *value* can vary per grid cell instead of the one global PLAY value. Sparse (a short list of
/// drawn cells, like `MacroTarget`); the builder folds `override ?? global` into the cell's macro fold. The macro's
/// TARGETS (which params, what delta) are shared — only the driving VALUE is per-cell.
struct MacroCellValue: Codable, Equatable {
    var col: Int             // the grid column (0–7)
    var row: Int             // the grid row
    var macro: Int           // which macro (0–15)
    var value: Double        // the per-cell override value (0…1) — replaces the global macroValues[macro] for this cell
}
// DECODE-TOLERANT (CR-8 class, code-review finding 2026-10-04) — same gap and same fix as MacroTarget above.
extension MacroCellValue {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        col = try c.decodeIfPresent(Int.self, forKey: .col) ?? 0
        row = try c.decodeIfPresent(Int.self, forKey: .row) ?? 0
        macro = try c.decodeIfPresent(Int.self, forKey: .macro) ?? 0
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
    }
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
extension Macro {
    // DECODE-TOLERANT (Paul 2026-08-26 review fix): synthesized Decodable throws on a MISSING non-Optional key, so the
    // additive non-Optional fields (emitterTargets · laneOn · laneRate — added after Macro first persisted) would fail a
    // pre-field macro → the whole document decode throws → silent reset (the CR-8 data-loss class). decodeIfPresent every
    // field so an old/partial macro decodes to defaults. In an EXTENSION so the memberwise init + Encodable stay synthesized.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        value = try c.decodeIfPresent(Double.self, forKey: .value) ?? 0
        fixed = try c.decodeIfPresent(Bool.self, forKey: .fixed) ?? false
        targets = try c.decodeIfPresent([MacroTarget].self, forKey: .targets) ?? []
        emitterTargets = try c.decodeIfPresent([MacroEmitterTarget].self, forKey: .emitterTargets) ?? []
        laneOn = try c.decodeIfPresent(Bool.self, forKey: .laneOn) ?? false
        lane = try c.decodeIfPresent([Double].self, forKey: .lane)
        laneModes = try c.decodeIfPresent([Int].self, forKey: .laneModes)
        laneRate = try c.decodeIfPresent(Int.self, forKey: .laneRate) ?? 3
    }
}

// MARK: - ROW 8 — the action strip (Paul 2026-08-22, Docs/row8-spec.md)
// The bottom row = 8 TYPED cells, each a SEATED MACRO BUTTON {type · payload · mover}. Perform-only on the grid;
// authored on the ROW 8 EDIT PAGE. Scenes capture toggle/radio LIT state. Routing-class types ANNOUNCE (the wire law).

/// The action catalog. `.empty` = the [+] authoring invitation. Append-only (Codable rawValues are frozen).
enum Row8Type: String, Codable, CaseIterable {
    case empty            // the [+] — an unauthored cell (renders the ADD-glow invitation)
    // the zero-config instant-payoff trio (danger gradient, left)
    case stutter          // HELD: the sounding set retriggers at RATE (the DJ stutter)
    case freeze           // TOGGLE: sounding notes SUSTAIN + derivation pauses (the pad-of-now)
    case halftime         // TOGGLE: ÷2 | ×1 | ×2 the whole play-grid clock, boundary-deferred
    // the routing-class wing (announces)
    case redirect         // HELD: one wire's stream re-stamped onto another (A→B)
    case swap             // HELD|TOGGLE: two wires EXCHANGE streams (A↔B)
    case broadcast        // HELD: every emission MIRRORS to all wires (+channels) — the wall
    case kill             // ONE-SHOT: all-notes-off, soft or hard
    // the seated types
    case part             // TOGGLE: a referenced PART plays FROM THE CELL, scene-independent
    case sequence         // TOGGLE: a captured phrase loops (deferred payload — v1 stub)
    case setup            // ONE-SHOT (radio): activate rack SETUP n (the setup cells form a radio)
    case macro            // the macro's own nature: fire/hold macro n
    case input            // the door's mode-act (LATCH/HOLD/REPLAY/KEYS/FILE), dynamic per door mode
    case ccPunch          // HELD: punch a CC value while held
    case pcSend           // ONE-SHOT: send a Program Change
}

/// The mover column — how a press behaves. The macro/trigger family grammar, reused verbatim.
enum Row8Mover: String, Codable, CaseIterable {
    case held             // spring: acts while pressed, releases on lift
    case toggle           // latched on/off
    case oneShot          // fires once per tap
}

/// One ROW 8 cell: {type · payload · mover}. Only the payload fields relevant to `type` are used. Additive-Optional
/// payloads so future types extend without a migration break. Equatable/Codable for the document + scene capture.
struct Row8Cell: Codable, Equatable {
    var type: Row8Type = .empty
    var mover: Row8Mover = .toggle       // stored explicit; authoring seeds it from `Row8Type.defaultMover`
    // payloads — one per family (nil unless the type uses it):
    var partRef: Int? = nil              // PART: which part index
    var setupN: Int? = nil               // SETUP: rack config 0…3
    var macroN: Int? = nil               // MACRO: macro slot 0…7
    var doorRef: Int? = nil              // INPUT: which door A–D (0…3)
    var wireFrom: Int? = nil             // REDIRECT/SWAP: source wire A–D (0…3)
    var wireTo: Int? = nil               // REDIRECT/SWAP: dest wire A–D (0…3)
    var rate: ArpRate? = nil             // STUTTER: the retrigger rate (1/8 · 1/16 · 1/32 — ArpRate has the fast values)
    var halftimeMode: Int? = nil         // HALFTIME: 0 = ÷2 · 1 = ×1 · 2 = ×2
    var ccNum: Int? = nil                // CC-PUNCH: controller number 0…127
    var ccVal: Int? = nil                // CC-PUNCH: the value punched while held (0…127)
    var pcNum: Int? = nil                // PC-SEND: program number 0…127
    var killHard: Bool? = nil            // KILL: false = soft (notes-off) · true = hard (+ sound-off/panic)
    var broadcastAllChannels: Bool? = nil// BROADCAST: also mirror across all 16 channels
    var label: String? = nil             // optional user label (else the type glyph + a derived caption)

    /// The sensible default MOVER per type (spec §THE MODEL). Authoring seeds `mover` from this; the user can cycle it.
    static func defaultMover(for t: Row8Type) -> Row8Mover {
        switch t {
        case .stutter, .redirect, .broadcast, .ccPunch: return .held
        case .freeze, .halftime, .swap, .part, .sequence, .macro: return .toggle
        case .kill, .setup, .pcSend, .input, .empty: return .oneShot
        }
    }
    /// A freshly-authored cell of a type, with its default mover + type-appropriate payload seeds.
    static func make(_ t: Row8Type) -> Row8Cell {
        var c = Row8Cell(); c.type = t; c.mover = defaultMover(for: t)
        switch t {
        case .stutter:  c.rate = .r1_16
        case .halftime: c.halftimeMode = 0                      // ÷2 (the drop)
        case .redirect, .swap: c.wireFrom = 0; c.wireTo = 1     // A→B
        case .broadcast: c.broadcastAllChannels = true
        case .kill: c.killHard = false                          // soft
        case .setup: c.setupN = 0
        case .macro: c.macroN = 0
        case .part: c.partRef = 0
        case .input: c.doorRef = 0
        case .ccPunch: c.ccNum = 74; c.ccVal = 127              // cutoff, full
        case .pcSend: c.pcNum = 0
        default: break
        }
        return c
    }

    /// THE FACTORY DECK — the "danger gradient": left plays, right wields (spec §2). The shipping default (no reset;
    /// the layout is just the default, fully editable). Cell 4 is the deliberate [+] authoring invitation.
    static var factoryDeck: [Row8Cell] {
        [ make(.stutter), make(.freeze), make(.halftime), Row8Cell(),
          make(.redirect), make(.swap), make(.kill), make(.broadcast) ]
    }
}

struct PluginState: Codable, Equatable {
    var formatVersion: Int = 2     // 2 = v2.x chain routing · 3 = v3.0 graph routing · 4 = + receivers (§migration)
    var machines: [Machine]
    var scenes: [SceneState]       // length 1 in v2.x; scenes are the flagship next feature
    // CR-8: these three were the ONLY non-Optional post-v2 fields, so a PRE-v2 document (missing the keys) threw at
    // decode and the WHOLE document failed to load (data-loss). Now additive-Optional (a missing key decodes nil), with
    // resolvers giving the same defaults. New/factory/preset docs still write them, so this is decode-tolerance only.
    var activeScene: Int? = nil
    var morphMaster: Double? = nil // DECODE-ONLY ZOMBIE (delta §9 item 5): param #300 was REMOVED 2026-09-16 (address
                                   // free to reuse) and the render never applied it — kept only so older docs decode.
    var busChannels: [Int]? = nil  // v3.0 (delta §7): each OUTPUT stamps this channel on exit. CARD BACKS (2026-10-28): 4 entries, one per output A–D (default 1…4); a nine-ports document holds 8 (one per port): output n takes the RIFF port's entry (2n)
    /// The 4 stamp channels, one per output A–D (`FourfoldPorts`), nil/short-array safe. Missing ⇒ 1…4. An 8-entry (nine-ports) document maps output n ← entry 2n (the lane's riff port); a 5-to-7-entry list reads the same way.
    var busChannelsResolved: [Int] {
        let b = busChannels ?? []
        if b.count > 4 { return (0..<4).map { 2 * $0 < b.count ? b[2 * $0] : $0 + 1 } }
        return (0..<4).map { $0 < b.count ? b[$0] : $0 + 1 }
    }
    // ROW 8 (Paul 2026-08-22, Docs/row8-spec.md): the bottom ACTION strip — 8 TYPED performance cells. DOCUMENT state is
    // the authoring {type · payload · mover}; the toggle/radio LIT state is captured PER SCENE (SceneState.row8On).
    // Additive-Optional → old docs decode nil ⇒ the factory "danger gradient" deck (Row8Cell.factoryDeck).
    var row8: [Row8Cell]? = nil
    /// The 8 action cells, nil/short-array safe (missing ⇒ the factory deck). Non-persisting read helper.
    var row8Resolved: [Row8Cell] {
        let r = row8 ?? Row8Cell.factoryDeck
        return (0..<8).map { $0 < r.count ? r[$0] : Row8Cell() }
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
    // EUCLIDEOUS (Paul 2026-10-05): the standalone 4-lane instrument page's own PERSISTED config — not an
    // ephemeral BUILD-page audition (which never survives closing/reopening the plugin), a genuine authored
    // document field. Additive-Optional, same CR-8 reasoning as every other field on this struct: a missing key
    // decodes nil ⇒ the page has never been touched (resolves to the 4-fixed-line default shape, disabled).
    var euclideousLines: [EuclidLine]? = nil
    var euclideousEnabled: Bool? = nil
    var euclideousReceiver: Int? = nil
    /// Always exactly 4. UNLIKE `MachineParams.euclidLinesForEditing()` (whose rows 1-3 pad SILENT by design —
    /// only row 0 is meant active there), a short/missing array here pads with a PER-INDEX default (ferry
    /// 2026-10-09 §5): lane 1 (index 0) opens at 1 hit of 8 steps (the struct's own plain default — "a fresh
    /// lane defaults to 1 of 8"); lanes 2-4 open at 0 hits of 8 steps (deliberately silent until raised —
    /// DIFFERENT from lane 1, not a copy-paste); every lane's riff and notes leave on its own ports (`FourfoldPorts`) and
    /// riff ON with direction FWD (`useRiff = true`, `riffDir` left nil so it resolves to `.forward`) — see
    /// `euclideousDefaultLine(_:)` below. SUPERSEDES an earlier "every lane identical, pulses floored to ≥1"
    /// design (2026-10-06, fixing a since-resolved "no sound at all" bug from a stale pulses:0 default) — that
    /// blanket floor is REMOVED: 0 hits is now an intentional, deliberate default for lanes 2-4, not leftover
    /// corruption to repair. The gesture-level floor (`EuclideousPage.applyY`'s own `max(1, ...)` clamp on the
    /// TILT/HITS pad) still prevents a lane from being pinched back down to 0 once raised — 0 is reachable
    /// only as this starting point, exactly as the earlier design already intended for the "never reachable
    /// through the gesture" half of its own reasoning.
    private static func euclideousDefaultLine(_ i: Int) -> EuclidLine {
        // NEW DEFAULT STATE (usability ferry §8.2, 2026-10-11, literal): "riff R1 [see EuclideousRiff.
        // ranksResolved's own default above]; lane 1: riff FWD, 3/8, rate 1/8; lane 2: riff FWD, 5/16,
        // rate 1/16, OCT +1; lanes 3-4: 0 hits. All outputs A [CHANGED 2026-10-26: each lane has its own ports], source KEY." SUPERSEDES the prior ferry's
        // own "lane 1 = 1 of 8, lanes 2-4 = 0 hits" default entirely — a fresh/never-touched Euclideous
        // instance now opens on this musical shape instead.
        var x = EuclidLine(noteSel: .low)
        x.sourceMode = .key           // "source KEY" — set explicitly rather than relying on the shared
                                       // nil->.key fallback, so this default reads correctly even if that
                                       // fallback is ever revised for an unrelated reason.
        x.useRiff = true
        // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, 2nd same-day ferry) — "Default for every lane: nothing
        // lit, riff on, FWD," realized explicitly here rather than left to the migration fallback: `riffOn`
        // resolves correctly either way (`useRiff = true` above already drives `litMigrated` to the same
        // `(0,false,false,true)` result), but setting it directly keeps this factory's own intent legible
        // without needing to trace through the legacy-migration chain to see what it produces.
        x.riffOn = true
        x.riffDir = .forward
        switch i {
        case 0: x.pulses = 3; x.steps = 8; x.rate = .r1_8
        case 1: x.pulses = 5; x.steps = 16; x.rate = .r1_16; x.riffOctave = 1
        default: x.pulses = 0; x.steps = 8   // lanes 3-4
        }
        return x
    }
    /// PER-LANE RESET MIGRATION (2026-10-14 ferry; the fresh-document default CHANGED 2026-10-18 by the LANES GRID ferry): a line's own
    /// `resetSteps` stays nil (⇒ OFF — the grid's own default is "no restarts", §1.3/§9.1; it used to be 1 step) for a GENUINELY FRESH
    /// document (`euclideousLines == nil` — the whole feature untouched) but
    /// migrates from the OLD machine-wide `euclideousResetSpanBarsResolved` for a PRE-EXISTING one (any
    /// document that has ever set `euclideousLines` at all, including every one of the 20 shipped presets,
    /// none of which ever set `euclideousResetSpanBars` — so this migration leaves every preset's 4 lanes at
    /// OFF uniformly, matching "existing presets sound as before"). Verified this boundary can't misfire:
    /// `euclideousLines == nil` is true ONLY for a document where Euclideous was enabled with zero other
    /// interaction and no preset ever loaded.
    var euclideousLinesResolved: [EuclidLine] {
        let L = euclideousLines
        let isGenuinelyFresh = (L == nil)
        return (0..<4).map { i in
            var line = i < (L ?? []).count ? L![i] : Self.euclideousDefaultLine(i)
            // LEGATO REMOVED FROM A LANE'S GATE (2026-10-19): a stored 100% (an older session, or one set before this) loads as 99% — the UI and the engine (which are fed from
            // this) agree, and a repeated pitch re-strikes. (The FX tab's GATE row followed on 2026-10-20: it tops out at 95 and a stored 100 loads as 95.)
            if let g = line.gate, g > euclideousLaneGateMax { line.gate = euclideousLaneGateMax }
            if let g = line.notesGate, g > euclideousLaneGateMax { line.notesGate = euclideousLaneGateMax }
            if line.resetSteps == nil {
                // §9: "new pages: 1 step" is a MIGRATION rule, not `resetStepsResolved`'s own raw default
                // (that accessor's nil-default is OFF, deliberately — see its own doc comment) — a
                // genuinely fresh document's lane gets 1 explicitly, here; a pre-existing one migrates from
                // whatever the old machine-wide bars-count was.
                // LANES GRID §1.3 / §9.1: a fresh document's lanes carry NO restart marks (it used to default to "every 1 step"). Reported as a
                // difference: a never-edited document used to restart the riff every bar; it now counts straight through, until a mark is set.
                line.resetSteps = isGenuinelyFresh ? 0 : Self.migratedResetSteps(fromBars: euclideousResetSpanBarsResolved)
            }
            return line
        }
    }
    private static func migratedResetSteps(fromBars bars: Int) -> Int {
        switch bars { case 1, 2, 4, 8: return bars; case 16: return 8; default: return 0 }   // 0/anything else → OFF
    }
    /// ALWAYS TRUE (Fourfold header ferry 2026-10-15, §1: "the page always runs"): the ON chip is gone, so the stored field
    /// is decode-only — a document or preset saved with the page OFF loads audible. The resolver wins; the data is never
    /// rewritten (a stored `false` round-trips untouched).
    var euclideousEnabledResolved: Bool { true }
    var euclideousReceiverResolved: Int { max(0, min(3, euclideousReceiver ?? 0)) }
    // EUCLIDEOUS RIFF (Paul 2026-10-06): the page's one shared riff pattern, independent of which/how-many lines
    // have opted in via EuclidLine.useRiff. nil ⇒ the struct's own plain defaults (16 steps, an ascending figure).
    var euclideousRiff: EuclideousRiff? = nil
    var euclideousRiffResolved: EuclideousRiff { euclideousRiff ?? EuclideousRiff() }
    // FOUR RIFFS (2026-10-14 ferry, "sequencer panel, four riffs, per-lane reset" §7) — the riff grid now
    // holds FOUR independently-stored riffs, picked by tabs. `riffs == nil` ⇒ MIGRATE the old singular
    // `euclideousRiff` into slot 0; slots 1-3 start EMPTY (§9: "riffs 2-4 empty") — a deliberate, disclosed
    // deviation from the `ScalePool`/`chordSeqs` precedent (whose own slots 1-3 default to a fresh REAL
    // value, not empty) — mirror that precedent's SHAPE, not this one specific default. `activeRiff` is
    // dual-purpose: which riff is shown for EDITING on the grid, and — only when the RIFFS sequencer below
    // is OFF — which riff actually PLAYS (§6: "the riff selected in the riff grid's tabs is the one that
    // plays... tapping a riff tab switches riffs live"). One field, two roles — forced by composing §6+§7,
    // not explicitly stated; the only reading consistent with "editing riff 3 while riff 1 plays" existing
    // only while the RIFFS sequencer is genuinely ON.
    var riffs: [EuclideousRiff]? = nil
    var activeRiff: Int? = nil
    var riffsResolved: [EuclideousRiff] { euclideousRiffsMigrated(riffs, legacySingular: euclideousRiffResolved) }
    var activeRiffResolved: Int { max(0, min(3, activeRiff ?? 0)) }
    // THE RIFF (FERRY "looper tabs replace the riff tabs", ratified 2026-10-16, §8.1) — SUPERSEDES
    // `riffs`/`activeRiff` above, which stay in place decode-only (no new writes); a pre-ferry document
    // (nil) migrates with no data rewrite: the riff = riffs[activeRiffResolved]. No slots detour (the
    // loop-slots ferry's own 4-slot migration is retired along with the type it fed).
    var euclideousLiveGrid: EuclideousRiff? = nil
    var euclideousLiveGridResolved: EuclideousRiff { euclideousLiveGrid ?? riffsResolved[activeRiffResolved] }
    // RETIRED (loop-slots, superseded same-day) — decode-only.
    // EUCLIDEOUS PAGE REWORK (Paul/design-channel, 2026-10-07, ratified — Docs/SPEC-euclideous-rework.md):
    // global controls. `euclideousReceiver`/`euclideousReceiverResolved` above are now UNREACHABLE from any
    // UI (the single IN A/B/C/D selector was removed) but left in place inert, matching how `riffDirBias`
    // was already handled when ITS control was dropped — the lanes' own MIDI source is hardcoded to
    // receiver index 3 instead (BuildSceneLogic.swift), the riff's own to receiver index 0 (SnapshotBuilder.swift).
    //
    // RESET SPAN: a literal bar count (0=OFF·1·2·4·8·16) — deliberately NOT the existing `spanLadderBeats`
    // raw-value ladder, which uses a DIFFERENT unit (n=1...6 are literal columns there, only 8/16/32 mean
    // row-multiples) that only coincidentally agrees with "bars" at the top end. Genuinely inert for now —
    // §4.2 of the spec explicitly leaves "what exactly resets" undecided; this persists the CONTROL's value
    // only, nothing in Router reads it yet.
    var euclideousResetSpanBars: Int? = nil
    var euclideousResetSpanBarsResolved: Int { let v = euclideousResetSpanBars ?? 0; return [0, 1, 2, 4, 8, 16].contains(v) ? v : 0 }
    // LANES + RIFFS SEQUENCERS (2026-10-14 ferry §2/§3/§4) — the machine-wide RESET control above is REMOVED
    // from the UI (the per-lane `EuclidLine.resetSteps` replaces it, see `euclideousLinesResolved`'s own
    // migration); `euclideousResetSpanBars` itself stays wired, unreachable from any new control, purely as
    // the migration SOURCE value and decode-compat for an already-saved document. Two fully independent
    // sequences, each its own ON/RATE/LEN/cells (§4: "two separate sequences, each with its own ON, RATE and
    // LEN") — "the step clock always runs" (§4) means BOTH resolved-rate/len pairs are read unconditionally
    // by the engine's step-clock math regardless of their own ON state; ON only gates whether that sequence
    // actually MUTES lanes / SWITCHES riffs.
    var euclideousLanesSeqOn: Bool? = nil
    var euclideousLanesSeqRate: EuclideousSeqRate? = nil
    var euclideousLanesSeqLen: Int? = nil
    var euclideousLanesSeqCells: [Bool]? = nil   // 32 = 8 steps × 4 lanes, row-major (step*4 + lane); nil ⇒ all lit (§9)
    var euclideousLanesSeqOnResolved: Bool { euclideousLanesSeqOn ?? false }
    var euclideousLanesSeqRateResolved: EuclideousSeqRate { euclideousLanesSeqRate ?? .oneBar }
    var euclideousLanesSeqLenResolved: Int { max(1, min(8, euclideousLanesSeqLen ?? 8)) }
    var euclideousLanesSeqCellsResolved: [Bool] {
        guard let c = euclideousLanesSeqCells, c.count == 32 else { return [Bool](repeating: true, count: 32) }
        return c
    }
    var euclideousRiffsSeqOn: Bool? = nil
    var euclideousRiffsSeqRate: EuclideousSeqRate? = nil
    var euclideousRiffsSeqLen: Int? = nil
    var euclideousRiffsSeqCells: [Int]? = nil    // 8, each 0...3 (which riff plays that step); nil ⇒ all riff 0 (§9)
    var euclideousRiffsSeqOnResolved: Bool { euclideousRiffsSeqOn ?? false }
    var euclideousRiffsSeqRateResolved: EuclideousSeqRate { euclideousRiffsSeqRate ?? .oneBar }
    var euclideousRiffsSeqLenResolved: Int { max(1, min(8, euclideousRiffsSeqLen ?? 8)) }
    var euclideousRiffsSeqCellsResolved: [Int] {
        guard let c = euclideousRiffsSeqCells, c.count == 8 else { return [Int](repeating: 0, count: 8) }
        return c.map { max(0, min(3, $0)) }
    }
    // FX TAB (ferry 2026-10-18): the whole tab as ONE additive-Optional field; nil ⇒ every cell empty and the §1.3/§1.4 defaults, so every pre-feature
    // document and all 20 factory presets sound exactly as before. `Resolved` clamps everything (the render path and the UI only ever read this).
    /// RETIRED (card backs, 2026-10-28): the page's MAIN OUT mask — every output is always on now, so nothing shows, sets or reads it. Kept so a document that stored one decodes and writes it back unchanged.
    var euclideousMainOutMask: UInt8? = nil
    var euclideousFX: EuclideousFX? = nil
    var euclideousFXResolved: EuclideousFX { (euclideousFX ?? EuclideousFX()).normalized() }
    // HOCKET (ferry 2026-10-27): up to four rules trading or passing lines between the eight lane outputs — one additive-Optional field; nil or empty ⇒ no rules (the pop-up then shows one empty R1 that is stored only once
    // something in it is edited). Sanitised by `HocketRuleSet` whenever it is built or decoded, so `hocketRulesResolved` is what the render path, the page and undo all read.
    var hocketRules: HocketRuleSet? = nil
    var hocketRulesResolved: [HocketRule] { hocketRules?.rules ?? [] }
    // KEY + SCALE: a page-level root+type pair, reusing the existing `ScaleType` enum purely as storage —
    // does NOT pre-wire the SCALE-door/KEY±/FOUNT machinery §4.3 explicitly leaves open (a genuinely
    // independent new field, not a reference to any door's own scale pool).
    var euclideousKeyRoot: Int? = nil
    var euclideousKeyRootResolved: Int { ((euclideousKeyRoot ?? 0) % 12 + 12) % 12 }
    var euclideousKeyType: ScaleType? = nil
    var euclideousKeyTypeResolved: ScaleType { euclideousKeyType ?? .naturalMinor }
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry) — SUPERSEDES the per-lane
    // `EuclidLine.sourceMode` (now decode-only, kept only as this migration's own source of old data; the
    // render path never reads it again). MIGRATION: an old doc carries 4 independent per-lane values —
    // "take lane 1's... if the lanes disagree, still take lane 1 and log a warning" (the ferry's own literal
    // rule). `euclideousLinesResolved`/`sourceModeResolved` already give every lane a concrete value (nil ⇒
    // `.key`), so "4 per-lane values" always exist to compare, even for a document with no real per-lane
    // data at all — in which case all 4 trivially agree (`.key`) and no warning fires. No structured
    // warning-log mechanism exists anywhere in this codebase (checked before inventing one) — `FileHandle.
    // standardError` matches this project's own ad-hoc RTCDEBUG-trace convention for this class of output.
    var euclideousNoteSource: EuclideousLaneSource? = nil
    var euclideousNoteSourceResolved: EuclideousLaneSource {
        if let s = euclideousNoteSource { return s }
        let legacy = euclideousLinesResolved.map { $0.sourceModeResolved }
        if Set(legacy).count > 1 {
            FileHandle.standardError.write("Fourfold: Euclideous lanes disagree on legacy per-lane source (\(legacy)) — migrating to lane 1's (\(legacy[0]))\n".data(using: .utf8) ?? Data())
        }
        return legacy[0]
    }
    // SOURCES STACK ferry (Paul 2026-10-26, §1.1-§1.2): the stacking plan. Additive-Optional, decode-tolerant
    // (synthesized Codable). nil DERIVES from today's exclusive source so every existing document/preset is
    // byte-identical: MIDI ⇒ all false (CHORDS/KEY never add); CHORDS ⇒ chords both true ("always"); KEY ⇒ key
    // both true. The UI stops writing `euclideousNoteSource` and writes this instead; the old field survives
    // only as this derivation's input.
    var euclideousSourcePlan: SourcePlan? = nil
    var sourcePlanResolved: SourcePlan {
        if let p = euclideousSourcePlan { return p }
        switch euclideousNoteSourceResolved {
        case .midi:   return SourcePlan()                                            // all false
        case .chords: return SourcePlan(chordsWithMidi: true, chordsNoMidi: true)     // "always"
        case .key:    return SourcePlan(keyWithMidi: true, keyNoMidi: true)           // "always"
        }
    }
    // SOURCES STACK §1.6: the dev-only clash policy (a rig setting, not undoable, carried across preset loads
    // like the settings ferry's four). nil ⇒ ALLOW. `clashPolicyResolved` is the ONLY reader — it returns the
    // stored value under DEBUG but ALLOW unconditionally in release, so a shipped build never drops a note.
    var euclideousClashPolicy: ClashPolicy? = nil
    var clashPolicyResolved: ClashPolicy {
        #if DEBUG
        return euclideousClashPolicy ?? .allow
        #else
        return .allow
        #endif
    }
    // FOURFOLD SETTINGS — MIDI IN "LISTEN ON" (2026-10-15 ferry, "Fourfold settings"): which channels MIDI IN
    // hears, a 16-bit mask (bit c = channel c+1, matching `Receiver.channelMask`'s own documented convention —
    // SnapshotBuilder already forces a literal 0xFFFF into `SnapParams.globalSrcChanMask` for every MIDI-mode
    // Euclideous lane; this field replaces that literal). DELIBERATELY DIVERGES from `Receiver.channelMask`'s
    // own 0-fallback (there, 0 ⇒ "hears nothing"): here nil OR a stored 0 both resolve to 0xFFFF ("today's
    // OMNI... a stored 0 resolves to every channel too," §3.5, literal) — zero channels would silence MIDI IN
    // with nothing on screen saying why, which is exactly the failure mode §3.3's own ALL-relights-itself rule
    // exists to prevent at the UI layer; this resolver backstops it at the model layer too.
    var euclideousMidiInChannelMask: UInt16? = nil
    var euclideousMidiInChannelMaskResolved: UInt16 {
        let m = euclideousMidiInChannelMask ?? 0xFFFF
        return m == 0 ? 0xFFFF : m
    }
    // FOURFOLD SETTINGS — CLOCK "WHEN THE HOST STOPS" (same ferry, §5): nil ⇒ KEEP PLAYING, today's free-run
    // behaviour, byte-identical for every existing document (§5.2, literal).
    var euclideousHostStopBehavior: EuclideousHostStopBehavior? = nil
    var euclideousHostStopBehaviorResolved: EuclideousHostStopBehavior { euclideousHostStopBehavior ?? .keepPlaying }
    // HOLD/LATCH (Paul 2026-10-20, header buttons beside the key pill): nil ⇒ off, today's plain live-MIDI
    // pool, byte-identical for every existing document. See `EuclideousHoldLatchMode`'s own doc comment.
    var euclideousHoldLatchMode: EuclideousHoldLatchMode? = nil
    // EUCLIDEOUS CHORDS (Paul 2026-10-08): "next to [KEY] place a chords button that opens a pop-up to a
    // chord grid with rate control... base this on the existing chord grid used on the chord door." Stored
    // as a plain MachineParams — the EXACT same storage shape the chord door's own `Receiver.chordSeqs:
    // [MachineParams]?` already uses (only its `chords*` fields are ever touched; everything else on it is
    // inert) — so `chordsDegreesResolved(steps:)`/`chordsStepsResolved`/`chordsRateResolved`/
    // `chordsVoicingResolved`/`chordsSpreadResolved` are all reused as-is, zero new resolve logic needed.
    // PATTERN mode only (no MODE/SCALE-FROM/WALK/FOLLOW — "a chord grid with rate control" is the scoped ask);
    // the KEY is Euclideous's own page-level `euclideousKeyRoot`/`Type` above, not a receiver-door reference
    // (unlike the regular CHORDS processor's SCALE FROM, which doesn't apply here — Euclideous has no doors).
    // nil ⇒ `MachineParams()`'s own defaults, which already resolve `chordsDegreesResolved` to a sensible
    // I-I-V-V-IV-IV-V-V loop — a fresh, never-touched grid is audible immediately, not silent.
    var euclideousChords: MachineParams? = nil
    var euclideousChordsResolved: MachineParams { euclideousChords ?? MachineParams() }
    // CHORDS GRID ferry (Paul 2026-10-24): four independently-stored progressions ("tabs") replace the single
    // grid above. `euclideousChords` stays decodable forever (a legacy document's set 0 resolves FROM it, below)
    // but is never written again — the standard decode-only-sentinel pattern this codebase already uses
    // elsewhere (`riffLock`, the restart masks). `activeChordSet` is which tab is PLAYING; the popup may be
    // showing/editing a different tab at the same time (§4.4's queued switch) — "shown" and "playing" differ.
    // Deliberately a lazy/computed migration (no eager mutating pass at load): a legacy document that's never
    // touched never materializes `euclideousChordSets` at all and reads byte-identically through
    // `euclideousChordsResolved`; the FIRST edit (`setEuclideousChordSet`) is what "migrates" it, in place.
    var euclideousChordSets: [MachineParams]? = nil
    var activeChordSet: Int? = nil
    var euclideousChordSetsResolved: [MachineParams] {
        guard let sets = euclideousChordSets else {
            return [euclideousChordsResolved, MachineParams(), MachineParams(), MachineParams()]
        }
        var s = sets
        while s.count < 4 { s.append(MachineParams()) }
        return Array(s.prefix(4))
    }
    var activeChordSetResolved: Int { max(0, min(3, activeChordSet ?? 0)) }
    /// Writes `params` into chord-set `idx` (0...3), materializing `euclideousChordSets` on first use if the
    /// document hasn't been touched since the CHORDS GRID ferry — the ONE write path every chord-tab edit uses.
    mutating func setEuclideousChordSet(_ idx: Int, _ params: MachineParams) {
        guard idx >= 0, idx < 4 else { return }
        var sets = euclideousChordSetsResolved
        sets[idx] = params
        euclideousChordSets = sets
    }
    // SOURCE MODE, riff and lanes independently: nil ⇒ MIDI (true), NOT key — a fresh/never-touched doc, and
    // every EXISTING session saved before this rework, must keep sounding exactly as it did (its receiver-fed
    // MIDI pool), not go silent the instant this update lands (KEY mode currently resolves to an empty pool,
    // since §4.4's key-to-rank mapping is undecided — defaulting new installs to the SILENT mode would be a
    // real regression, not a neutral stub).
    var euclideousRiffSourceMidi: Bool? = nil
    var euclideousRiffSourceMidiResolved: Bool { euclideousRiffSourceMidi ?? true }
    var euclideousLanesSourceMidi: Bool? = nil
    var euclideousLanesSourceMidiResolved: Bool { euclideousLanesSourceMidi ?? true }
    // LANE SOLO (ferry 2026-10-21, §4.1): the LATCHED solo mask — bit i = lane i soloed. Stored, saved and handed to the render thread exactly as the document's other page fields are (a document field → the AVC's @State →
    // `MachineParams.soloMask` → `SnapParams.soloMask`; no undo; a preset load replaces it with the preset's own). nil ⇒ 0 = no solo, so every pre-feature document sounds as before. The HELD solo is UI state only and
    // is deliberately not a field of anything saved.
    var euclideousSoloMask: UInt8? = nil
    var euclideousSoloMaskResolved: UInt8 { (euclideousSoloMask ?? 0) & 0x0F }
    // LANE LOCK (ferry 2026-10-21, §3.2): one lock per Euclideous lane — on, snap-back grid (kept while unlocked) and the locked state L. A 4-entry array BESIDE `euclideousLines`, deliberately NOT a field of
    // `EuclidLine` (which is shared by the persisted `MachineParams`, the render `SnapParams` and every "is this the same line" test, and is the struct that nearly filled the extension's 1 MB debug stack).
    // Consequences by construction: a lock is never in an undo snapshot (9.2), carries through no preset (9.3) and no copy/paste (3.4), and a pre-feature document (nil) resolves to four unlocked lanes. A session
    // saved while a locked lane was deviated opens at L (`normalizeLocksAtLoad`, 3.5). The lock's mode (the padlock in the header) is page state: not here.
    var euclideousLocks: [EuclideousLaneLock]? = nil
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
        let dflt: [UInt8] = [rackEnabledResolved, 0b1111, 0b1111, 0b1111]
        guard let c = rackConfigs, !c.isEmpty else { return dflt }
        return (0..<4).map { $0 < c.count ? (c[$0] & 0b1111) : dflt[$0] }   // CR-9: PAD short / TRUNCATE long — don't discard user configs when the array isn't exactly length 4 (matches resolved4)
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
    // PER-CELL macro VALUES (macro-automation §A2 / §K1, Paul 2026-09-01): the PUNCH/SPAN store — a sparse list of
    // per-cell overrides for a macro's driving value (the TARGETS stay shared on the Macro; only the value varies per
    // cell). Additive-Optional → old docs decode nil (no overrides = the global PLAY value everywhere, byte-identical).
    // Baked at build time like every macro offset (v1 bake-at-publish). Travels with the document.
    var macroCellValues: [MacroCellValue]? = nil
    /// The LIVE macro bank (Paul §K3 2026-09-01): SIXTEEN named movements in TWO species — 8 SLIDER (0–7) + 8 TOGGLE
    /// (8–15). The old 8 TIMELINE macros (16–23) are RETIRED: a doc that stored them still DECODES (the Codable
    /// `macros` array is untouched → encode round-trips whatever is there), but only the first 16 are RESOLVED, so
    /// their offsets simply stop applying (decode-safe retirement). Byte-identical for any doc that only used 0–15.
    static let macroBankCount = 16
    /// The live 16 macros, nil/short-array safe (missing ⇒ an unset `Macro`). Non-persisting read helper.
    var macrosResolved: [Macro] { let a = macros ?? []; return (0..<Self.macroBankCount).map { $0 < a.count ? a[$0] : Macro() } }
    // master panel: MUTE — global emission kill (PERSISTED, document-level unlike the per-scene KEY). Optional
    // → old docs decode nil (not muted). The gate lives at the emission boundary (seam rule 3).
    var masterMute: Bool? = nil
    // LADDER MODE — the exclusive-columns arm (PERSISTED, document-level; the per-scene `activeRow` holds WHICH
    // rung). While on, at most one cell speaks per column. Optional → old docs decode nil (off). Mirrors masterMute.
    var ladderMode: Bool? = nil
    var ladderModeResolved: Bool { ladderMode ?? false }
    // IGNORE INCOMING ALL-NOTES-OFF (Paul 2026-09-06) — a MIDI SOURCE that floods CC120 (All Sound Off) / CC123 (All
    // Notes Off) around each chord (common — loop wraps, phrase ends, transport) would otherwise wipe our LIVE input
    // pool at Kernel.handleIncoming, silencing a sustained chord even though the notes are still held (the "empty pass"
    // report). PERSISTED, document-level (like masterMute). Default TRUE (ignore) — a MIDI PROCESSOR re-sequences input,
    // so a source's routine reset shouldn't clear it; real note-offs still release, and host/transport panic still flushes.
    var ignoreAllNotesOff: Bool? = nil
    var ignoreAllNotesOffResolved: Bool { ignoreAllNotesOff ?? true }
    // LATCH ARM — which input doors are ARMED (the KEYS/HOLD/LATCH/SCALE engage, a 4-bit mask). PERSISTED (Paul 2026-08-27,
    // "save the latch/keys section with the document") so a saved session reopens with the same doors engaged, and re-derived
    // on the render side (the kernel's live latchArmMask is seeded from this on every rebuild/load). Optional → old docs
    // decode nil (nothing armed). NOTE: the captured HOLD chord / REPLAY loop are inherently ephemeral — this restores the
    // ARM INTENT (KEYS/SCALE self-play from their persisted notes; HOLD/LATCH re-capture on the next input).
    var latchArmMask: UInt8? = nil
    // BUILD: the single UNASSIGNED workshop part, saved with the document (Paul 2026-08-16). Additive-Optional →
    // old saves decode as nil. Populated at save time from the live workshop; restored into BUILD @State on load.
    var buildUnassigned: BuildUnassignedData? = nil
    // THE ROOMS PLAY GRID (Paul 2026-08-30): the 8 independent play columns + their multi-step passes, saved with the
    // document. Additive-Optional → old saves decode nil. Populated from the live @State each poll; restored on load.
    var buildPlayGrid: BuildPlayGridData? = nil
    // SCENES V2 (Paul 2026-08-24): the DEPLOYED play-grid arrangements, one per scene index — this ALSO persists the
    // deployed play grid (the long-open gap). Additive-Optional → old saves decode nil. Restored into BUILD @State on load;
    // `buildScenesActive` = which was live. (The document's `scenes[]` + `activeScene` are the RENDER scenes; these are the
    // BUILD-authoring arrangements that compose into them.)
    var buildScenes: [BuildSceneSnapshot]? = nil
    var buildScenesActive: Int? = nil
    // PART AUTOMATION (Paul 2026-09-02): the AUTO lanes, keyed by machineID. Additive-Optional → old saves decode nil
    // (byte-identical: with no active lane, nothing bakes). Captured from BUILD @State each poll; restored on load.
    var partAuto: [String: PartAutoMachine]? = nil
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


    // MARK: - MULTI-SCENE (2026-07-27) — the scene strip switches activeScene within one document

    static let maxScenes = 16          // the strip's fixed slot count (16 — the scene row sits on its own line below the header)

    /// The active scene index, always in-bounds (clamped; falls back to 0 if the doc is odd). Never crashes.
    var activeSceneResolved: Int { scenes.isEmpty ? 0 : max(0, min(scenes.count - 1, activeScene ?? 0)) }
    /// The active scene (bounds-safe), for the render + UI.
    var activeSceneState: SceneState { scenes.isEmpty ? .empty() : scenes[activeSceneResolved] }

    /// Extend `scenes` to exactly `n` fixed slots (padding with empty "+" scenes). Idempotent; never shrinks
    /// below the current count. The strip is a fixed 16 slots, so old length-1 docs pad to 16 on load.
    mutating func padScenes(to n: Int = maxScenes) {
        if scenes.isEmpty { scenes = [.empty()] }
        while scenes.count < n { scenes.append(.empty()) }
    }

    // MARK: - S3: drag on the strip = MOVE / SWAP / DELETE (never overwrite — the precious-scene law)


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
                print("Fourfold: migrated v2 document to graph routing; dropped +SRC on \(droppedSrcMix) cell(s) (no v3 equivalent).")
            }
            formatVersion = 3
        }
        synthesizeReceiversIfNeeded()   // delta §9 item 11 — runs for v3 docs too (they have no receivers yet)
        migrateMachinePairsIfNeeded()    // delta item 8 — fold each Machine's partner into its own procB
        padScenes()                     // MULTI-SCENE: a fixed 16-slot strip — old length-1 docs pad with empties
    }

    /// delta item 8 (TWO-PROCESSOR Machines): fold the retired pair reference into each Machine's own procB.
    /// Idempotent, gated on formatVersion < 5. For a Machine with a valid `altMachine` partner: copy the
    /// partner's type/params/transpose into procB (typeB/paramsB/transposeB), overwriting any stale paramsB.
    /// `altMachine` is LEFT in place (decode-only legacy) so an older build re-loading a migrated doc still
    /// reads the pair — lossless downgrade. The new render sources B ONLY from typeB, so keeping altMachine is
    /// inert. Reads partner.type/paramsA/transpose (never written here) so in-place mutation is safe.
    mutating func migrateMachinePairsIfNeeded() {
        guard formatVersion < 5 else { return }
        var migrated = 0
        for i in machines.indices {
            guard let pi = machines[i].altMachine, pi >= 0, pi < machines.count, pi != i else { continue }
            machines[i].typeB = machines[pi].type
            machines[i].paramsB = machines[pi].paramsA
            machines[i].transposeB = machines[pi].transpose
            migrated += 1
        }
        if migrated > 0 {
            print("Fourfold: migrated \(migrated) Machine pair(s) into internal procB (delta item 8).")
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
                print("Fourfold: synthesized receivers; \(overflow) overflow input channel(s) collapsed to Receiver 1.")
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

    /// D1: mark a Machine DEFINED iff it is painted in some scene — so a fresh factory/arc ships a SPARSE palette
    /// (only the used Machines as chips; the rest are "+" slots). Old saved docs (`defined == nil`) are untouched.
    mutating func markDefinedFromUsage() {
        let used = Set(scenes.flatMap { $0.cells.flatMap { $0.compactMap { $0?.machineID } } })
        for i in machines.indices { machines[i].defined = used.contains(machines[i].machineID) }
    }

    static func factory() -> PluginState {
        var machines = machineIDs.map { Machine(machineID: $0, type: .arp) }
        // A few designed defaults so the factory session sounds immediately (§6.6). (Old paramsB ALT
        // demos dropped — the pair model sets ALT via a partner Machine; re-author as a follow-up.)
        func idx(_ id: String) -> Int { machineIDs.firstIndex(of: id)! }
        machines[idx("gold")].paramsA.octaves = 2
        machines[idx("cyan")].type = .ratchet
        machines[idx("cyan")].paramsA.count = 4
        machines[idx("vermilion")].type = .empty
        machines[idx("magenta")].transpose = 12

        var scene = SceneState.empty()
        scene.cells[0][0] = Cell(machineID: "gold")
        scene.cells[2][0] = Cell(machineID: "vermilion")
        scene.cells[2][1] = Cell(machineID: "magenta", buses: [.b], inputRow: 0)   // references row 0 (§1)
        scene.cells[4][0] = Cell(machineID: "gold")
        scene.cells[6][0] = Cell(machineID: "cyan")
        var state = PluginState(machines: machines, scenes: [scene])
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
        state.markDefinedFromUsage()   // D1: sparse palette — only the painted Machines are defined chips
        return state
    }

    /// INIT — a blank starting point (user 2026-08-09): the 16-machine palette + 4 receivers (R1 OMNI · B/C/D ch 2/3/4)
    /// + ONE EMPTY scene, NO cells placed. Set as the FACTORY DEFAULT (what a fresh instance loads); the DEFAULT ARC
    /// + curriculum stay available as named presets.
    static func makeInit() -> PluginState {
        var state = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) }, scenes: [SceneState.empty()])
        state.formatVersion = 4
        state.synthesizeReceiversIfNeeded()
        // Every door starts UNSET (doorMode nil → the strip shows "SET" pulsing) and DEFAULTS to HOLD when resolved (Paul
        // 2026-08-31, was THRU): a fresh receiver's mode is HOLD, not yet armed. The user arms/changes it from the strip.
        for i in state.receivers!.indices { state.receivers![i].channel = i == 0 ? 0 : i + 1; state.receivers![i].doorMode = nil }
        if state.receivers!.count > 3 {   // DEFAULT: receiver D → A MIXOLYDIAN scale door (Paul 2026-08-29) — fresh instances only
            state.receivers![3].doorMode = .scale; state.receivers![3].scaleRoot = 9; state.receivers![3].scaleType = .mixolydian
        }
        // DEFAULT RIG (Paul 2026-09-04): receiver C → a CHORD door (the chord sequencer), taking its KEY FROM door D above.
        // chordSeqs stays nil ⇒ the four interesting default progressions (Receiver.defaultChordSeqs, all chordsScaleRef = D).
        if state.receivers!.count > 2 { state.receivers![2].doorMode = .chord }
        // A FRESH INSTANCE IS SILENT (Paul 2026-08-29): the grid starts EMPTY — no default cells — so a held note produces
        // NOTHING until the user selects/ferries a cell. (Previously makeInit placed 8 GOLD .drone cells across the top row,
        // a legato straight-through passthrough; with the rooms interface the arrangement is built on the play/part grids,
        // so a document default cell just leaked input to the output on launch. "No cell selected ⇒ silence.")
        state.padScenes()
        state.markDefinedFromUsage()   // no cells → no machine is "in use" (the rooms SELECT grid is library-backed, not this palette)
        return state
    }









}

// MARK: - MODELESS EDIT scope (2026-07-27) — scope-after-target: THIS · ALL IDENTICAL · ALL <MACHINE>

extension SceneState {
    enum EditScope { case thisOne, allIdentical, allMachine, twins }



    // MARK: - §11 VERB LOGIC (the testable model ops behind the round verbs; PLACE stamps a Cell directly)


    // MARK: - ROUTING (receiver in · emitters out; the UI projection lights + taps these)

}

// MARK: - Session template / clipboard (delta §5) — one STAMP object

/// The session-scoped TEMPLATE = CLIPBOARD (one stamp object, delta §5): a cell's full config minus its
/// perform state. Written by committing a cell in the editor AND by COPY; read by the empty-cell pre-fill
/// and the split-paste actions. Ephemeral (never persisted). Bootstrap = the desk Machine + ⇐MIDI(R1) →A.
struct StampConfig: Equatable {
    var machineID: String
    var inputRow: Int? = nil        // a row reference; nil = MIDI-IN via the receiver below
    var inputReceiver: Int = 0      // 0–3, used when inputRow == nil
    var buses: Set<Bus> = [.a]

    static func from(_ c: Cell) -> StampConfig {
        StampConfig(machineID: c.machineID, inputRow: c.inputRow, inputReceiver: c.inputReceiver ?? 0, buses: c.buses)
    }
}

/// EUCLIDEOUS UNDO (usability ferry §7, 2026-10-11): the bundle of fields §7.2 lists as undoable — riff grid
/// edits, any lane setting (card/pads/tabs/mask/melody pop-up), RESET MELODY, and a preset load. Deliberately
/// EXCLUDES the page's own master ON/OFF
/// (not a field here at all — `enabled`/`EuclideousPage.enabled` stays outside this snapshot). `lines` is
/// captured whole (simplest to construct/compare) even though it also carries each line's own PLAY/STOP
/// (`enabled`) and its mask's own play/stop (`mask?.enabled`) — both of which §7.3 ALSO excludes
/// ("play/stop... not undoable"). Rather than strip those two sub-fields out of every snapshot (fragile to
/// keep in sync as EuclidLine grows), the RESTORE step (AudioUnitViewController's `euclideousApply`) re-merges
/// the CURRENT live play/stop state back in after applying a snapshot — so recording is simple/uniform while
/// restoring is what actually enforces the exclusion.
struct EuclideousUndoSnapshot: Equatable {
    var lines: [EuclidLine]
    var riff: EuclideousRiff
    var resetSpanBars: Int
    var keyRoot: Int
    var keyType: ScaleType
    // CHORDS GRID ferry (2026-10-24) replaced the single `chords` grid with 4 progressions + which plays.
    var chordSets: [MachineParams]
    var activeChordSet: Int
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry) — undoable like every other
    // page-level setting here (play/stop and MAIN OUT are the only two explicit exceptions, enforced at
    // restore time, not at this snapshot's own shape).
    var noteSource: EuclideousLaneSource
    // SOURCES STACK ferry (2026-10-26): the stacking plan, undoable like noteSource. OPTIONAL — nil means "not
    // set yet," so an undo/redo that restores nil leaves the document's legacy nil-derivation (from noteSource)
    // intact rather than stamping an explicit all-false plan. CLASHES is a rig setting and is NOT in this snapshot.
    var sourcePlan: SourcePlan? = nil
    // SEQUENCER PANEL (2026-10-14 ferry): four riffs + which one's active + both step clocks — undoable
    // page-level settings, same bucket as `riff`/`resetSpanBars` above, no §7.3-style exclusion named for
    // any of these. (Restored 2026-10-18 — the looper's own `liveGrid` single-pattern snapshot that
    // briefly replaced this pair is gone along with the looper itself.)
    var riffs: [EuclideousRiff]
    var activeRiff: Int
    var lanesSeq: EuclideousLanesSeq
    var riffsSeq: EuclideousRiffsSeq
    var fx: EuclideousFX = EuclideousFX()   // FX TAB (2026-10-18): cells, lane sets, PASSES, CC number, BASE — undoable page-level state (selection/brush/bubble are not)
    var holdLatchMode: EuclideousHoldLatchMode? = nil   // HOLD/LATCH (2026-10-20): undoable like noteSource above, no §7.3-style exclusion
    var hocketRules: [HocketRule] = []   // HOCKET (2026-10-27): the rules — undoable page-level state (which rule tab is showing, and whether the pop-up is open, are not); [] = none stored
    /// UNDO-5 (2026-10-25): lanes' PLAY/STOP are never undoable (§7.3) — EXCEPT across a preset load, which is itself a step and replaces them: only such a step carries the flags it must put back (`nil` = every other step, which
    /// keeps the live flags as always). Captured by `loadPreset` / `loadFactoryPreset`, and re-stamped on the opposite side when that step is undone or redone so ↶ and ↷ both land on the right flags.
    var presetPlay: [EuclideousLanePlay]? = nil
}

/// A lane's two play/stop flags (the lane's own and its mask's) — what `EuclideousUndoSnapshot.presetPlay` carries.
struct EuclideousLanePlay: Equatable {
    var enabled: Bool?
    var maskEnabled: Bool?
}
func euclideousPlayFlags(of lines: [EuclidLine]) -> [EuclideousLanePlay] {
    lines.map { EuclideousLanePlay(enabled: $0.enabled, maskEnabled: $0.mask?.enabled) }
}
func euclideousApplyPlayFlags(_ flags: [EuclideousLanePlay], to lines: inout [EuclidLine]) {
    for i in lines.indices where i < flags.count {
        lines[i].enabled = flags[i].enabled
        if var m = lines[i].mask { m.enabled = flags[i].maskEnabled; lines[i].mask = m }
    }
}

// MARK: - what becomes an undo step (UNDO audit, 2026-10-25)

/// UNDO-2: the page's lane funnel used to record every edit under ONE key, so edits to different controls merged into a single step for as long as nothing else was recorded in between. A key now lives only as long as the
/// EDITS KEEP ARRIVING: a pause longer than `gap` closes the run (a drag emits continuously; a person who lets go and starts again is making another edit), and the funnel adds which lanes the edit touched, so two
/// lanes never share a step either.
struct EuclideousEditGestures: Equatable {
    static let gap = 0.5
    private var epoch = 0
    private var last: Double? = nil
    mutating func key(_ base: String, at t: Double) -> String {
        if let l = last, t - l > Self.gap { epoch += 1 }
        last = t
        return "\(base)#\(epoch)"
    }
    /// An undo, a redo, a preset or a replaced document ends whatever run was open.
    mutating func historyMoved() { epoch += 1; last = nil }
}

/// UNDO-1 / UNDO-8: the funnels that take an explicit checkpoint ("newStep": the MIX pad, the FX tab, the STEPS drag) rely on the caller saying "a new burst begins here" — and used to take the checkpoint on that write even
/// when it changed nothing, and never again after an undo. `wanted` is raised by a new burst and by anything that moves the history; the checkpoint is taken at the first write that really CHANGES something.
struct EuclideousCheckpoint: Equatable {
    private var wanted = false
    mutating func newBurst() { wanted = true }
    mutating func historyMoved() { wanted = true }
    /// Call for every write of a burst, after the funnel knows whether it changed anything. True ⇒ record the undo step BEFORE applying this write.
    mutating func take(changed: Bool) -> Bool {
        guard changed, wanted else { return false }
        wanted = false
        return true
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
    /// The redo branch the run that is still open threw away when it began — handed back if that run turns out to be a no-op (`dropOpenRunIfUnchanged`).
    private var stashedFuture: [T]? = nil
    let cap: Int

    init(cap: Int = 50) { self.cap = max(1, cap) }

    var canUndo: Bool { !past.isEmpty }
    var canRedo: Bool { !future.isEmpty }

    mutating func record(_ current: T, coalesceKey: String? = nil) {
        let continuesRun = coalesceKey != nil && coalesceKey == lastKey && !past.isEmpty
        if !continuesRun { stashedFuture = future.isEmpty ? nil : future }
        future.removeAll()                                   // a fresh edit invalidates the redo branch
        if continuesRun { return }                           // same ongoing gesture → don't re-push
        past.append(current)
        if past.count > cap { past.removeFirst() }
        lastKey = coalesceKey
    }

    /// UNDO-6: a coalesced run that ended exactly where it began (a drag that wandered off and came back) is not a step — drop it. Only ever the run that is still open.
    @discardableResult
    mutating func dropOpenRunIfUnchanged(current: T) -> Bool {
        guard lastKey != nil else { return false }
        return dropLastStepIfUnchanged(current: current)
    }
    /// The same for a discrete step (a preset load that turned out to change nothing): the step just recorded is removed when the live value equals what it holds, and the redo branch it cleared comes back.
    @discardableResult
    mutating func dropLastStepIfUnchanged(current: T) -> Bool {
        guard let last = past.last, last == current else { return false }
        past.removeLast(); lastKey = nil
        if let back = stashedFuture { future = back }        // the redo branch the step cleared comes back: nothing happened
        stashedFuture = nil
        return true
    }

    /// Returns the value to restore (and stashes `current` for redo), or nil if there is nothing to undo.
    mutating func undo(current: T) -> T? {
        guard let prev = past.popLast() else { return nil }
        future.append(current)
        lastKey = nil; stashedFuture = nil                                        // the next record starts a fresh coalesce run
        return prev
    }

    /// Returns the value to re-apply (and stashes `current` for undo), or nil if there is nothing to redo.
    mutating func redo(current: T) -> T? {
        guard let next = future.popLast() else { return nil }
        past.append(current)
        lastKey = nil; stashedFuture = nil
        return next
    }
}
