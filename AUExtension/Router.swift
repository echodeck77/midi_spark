//  Router.swift
//  MidiSpark — the routing/derivation engine (spec v2.8 §2/§7; docs/router-design.md).
//
//  Split out of Kernel at build-order step 3, commit 4. The Kernel owns the INPUT side
//  (transport derivation, incoming MIDI, the source pool) and the render entry point; the
//  Router owns the OUTPUT side — grid columns, per-cell ARP derivation, the note tracker, and
//  emission. Behaviour is identical to the in-Kernel version this replaced (verified: T1).
//
//  Fan-out (every cell emits on its own cable + All), graph routing (row-feed via resolvedParent),
//  and the (cable, channel, note) collision refcount are all SHIPPED (see emitArtic + the refcount
//  at `voices`). The audition and preview solo paths are decomposed below; process()'s per-row tick
//  loop is the last monolith.

import Foundation
// AudioToolbox is GONE (standalone-plan seam rule 1): the Router now emits through the Foundation-only
// `MIDIEmitter` protocol (Emission.swift) and names sample times as plain Int64 — the AU integer
// typedefs were only aliases (Int64=Int64, UInt32=UInt32, UInt64=
// UInt64). So this whole file — tick generation, the graph derivation, the 5-cable refcount — compiles
// into the macOS unit-test target. The live MIDIEmitter adapter lives in Kernel.swift.

// NotePool and the pure derivation functions (musicalOf/realOf, phaseIndex, arpPickSource,
// cellMode/CellMode, ratchetVelocity) now live in Derivations.swift — pure, Foundation-only, and
// unit-tested. The Router keeps only what depends on its state.

// MARK: - The router / arp engine

final class Router {

    // Render-side parameter overrides (§7 second route). Slots:
    //   0 stepRate · 1 swing · 2+i transpose(i) · 18+i morph(i) · 34 morphMaster
    private var overrides = [Double](repeating: .nan, count: 35)
    private var overrideGen: UInt64 = .max

    // Poly note tracker (§7). Each sounding note is a Voice carrying the channel + cable its on used
    // and an ABSOLUTE gate-off sample, drained every render so an off beyond its opening window is
    // never dropped (no stuck note). Fixed capacity; no allocation on the hot path.
    private struct Voice {
        var active = false
        var note: UInt8 = 0
        var chan: UInt8 = 0
        var cable: UInt8 = 0
        var bus: UInt8 = 0           // delta §6a: originating emitter (0–3), so an emitter-disable can
        var offSample: Int64 = .max  // close exactly its notes (own cable + its All copy).
        var silent = false           // delta §6a CLAIM: a MUTED claimant's ghost voice — tracked for
                                     // exclusivity but never emitted (no wire, no refcount).
        // §2 CONTINUITY (LEGATO adoption): a legato chord-hold voice is IMMORTAL (offSample .max) and
        // carries the identity the adoption law keys on — same NOTE (wire) + same EMITTER (bus) + same
        // COLOUR-AND-FACE (colourIndex + alt). At a column boundary a re-held identical voice is ADOPTED
        // (kept, no off/on); a changed one closes and the new one strikes. Stamped for every voice
        // (harmless on non-hold voices — only audible immortal voices are ever adoption-matched).
        var colourIndex: Int8 = -1
        var alt = false
        var vel: UInt8 = 0           // §strips-done: the emit velocity, for the per-emitter hold-while-sounding feed
        var cellIndex: Int8 = -1     // SEAL comet: the emitting cell's grid index (col*8+row), for the per-cell
                                     // SOUNDING gate — the spark travels for exactly as long as the note is held.
        var bypassRecv: Int8 = -1    // BYPASS: ≥0 = a direct-injection voice for that receiver (IMMORTAL, managed by
                                     // reconcileBypass) — the grid's continuity + transport flushes leave it alone.
    }
    private var voices = [Voice](repeating: Voice(), count: 128)

    // Collision refcount (§7, normative): per (bus, channel, note). Note-ONs always emit
    // (re-articulation is audible truth); the wire note-OFF is emitted only when the LAST instance
    // releases — so a sustained note never drops under a same-pitch arp. 4 buses × 16 ch × 128 notes.
    // 5 cables now (delta §7b): 0 = ALL, 1–4 = A–D.
    private var refcount = [UInt8](repeating: 0, count: 5 * 16 * 128)
    private var distinctSounding = 0   // number of (cable,ch,note) with refcount > 0 (diag; kept incrementally)

    private var busChannels: [UInt8] = [1, 2, 3, 4]   // per-bus stamp channels, refreshed each process
    private var heldColumns: UInt8 = 0   // §5b COLUMN-SUBSET LAP: held column keys (bit i = column i),
                                         // ephemeral (PERFORM only), refreshed each process. 0 = no lap.
    private var busEnabledMask: UInt8 = 0b1111   // delta §6a: enabled emitters, refreshed each process
    private var prevBusEnabledMask: UInt8 = 0b1111   // edge: a bus going enabled→disabled closes its notes
    // §6a PERFORM velocity override (momentary absolute, ephemeral). Packed: byte i = emitter i's forced
    // velocity, 0 = no override, 1–127 = flatten every new note-on to this value. Scalar so the
    // main-write/render-read stays race-safe (an aligned UInt32, like heldColumns).
    private var velOverride: UInt32 = 0
    // §6a CLAIM v2 (persisted, MULTI-claim SHARED tier): bit i set ⇒ emitter i claims. A NON-claimant emitting
    // a PITCH CLASS (note % 12) sounding on ANY claimant is suppressed (own cable + its All copy) — claimants
    // own that harmony, others get the residue; claimants never suppress each other. Suppress, never defer.
    private var claimMask: UInt8 = 0
    // §6a CLAIM v2 LEAK %: per-claimant bleed. When a non-claimant yields a claimed pitch class, it passes at
    // this scaled velocity instead of falling silent (0 = full suppression = v1). Multi-claim = the MIN leak
    // among the claimants sounding that class wins (the strictest shadow).
    private var claimLeak: [UInt8] = [0, 0, 0, 0]
    // emitter role family: FLATTEN — activity ducking. While a FLATTEN emitter (bit set) has anything
    // sounding, OTHER emitters' NEW note-ons are velocity-scaled by that emitter's amount. Persisted; refreshed
    // from the box each render. Stateless — a pure query of the live voice table at admission time.
    private var flattenMask: UInt8 = 0
    private var flattenAmount: [UInt8] = [0, 0, 0, 0]
    // THE RACK — CURVE (design-the-rack §6): per-emitter output-velocity re-map. `curveMask` = which emitters
    // curve; `curveAmount` = −100…100 (0 = linear, + boosts low velocities = harder, − softens). Rack-gated in
    // the builder. Applied per note-on in emitOneBus (a pure transform of the outgoing velocity).
    private var curveMask: UInt8 = 0
    private var curveAmount: [Int8] = [0, 0, 0, 0]
    /// Is bit `bus` (0–3) set in a per-emitter mask? One name for the repeated `mask & (1 << UInt8(bus)) != 0`
    /// treatment-on test (previewMode stays explicit at each site — it isn't uniform).
    @inline(__always) private func bit(_ mask: UInt8, _ bus: Int) -> Bool { mask & (1 << UInt8(bus)) != 0 }
    /// The velocity re-map for one emitter: u' = u^gamma, gamma = 2^(−amount/100) (a smooth soft↔hard bend).
    private func curveVelocity(_ v: UInt8, _ amount: Int8) -> UInt8 {
        if amount == 0 { return v }
        let u = Double(v) / 127.0
        let mapped = pow(u, pow(2.0, -Double(amount) / 100.0))
        return UInt8(max(1, min(127, Int((mapped * 127.0).rounded()))))
    }
    // THE RACK — FENCE (design-the-rack §6): per-emitter note-RANGE policy on the OUTPUT note. `fenceMask` = which
    // emitters fence; policy 0 DROP · 1 CLAMP · 2 FOLD; lo/hi = the window. Rack-gated in the builder.
    private var fenceMask: UInt8 = 0
    private var fencePolicy: [UInt8] = [0, 0, 0, 0]
    private var fenceLo: [UInt8] = [0, 0, 0, 0]
    private var fenceHi: [UInt8] = [127, 127, 127, 127]
    /// Octave-FOLD a note into [lo, hi] by ±12; a window narrower than an octave can't fold, so it clamps.
    private func fenceFold(_ note: UInt8, lo: UInt8, hi: UInt8) -> UInt8 {
        let l = Int(lo), h = Int(hi)
        if h - l < 11 { return UInt8(min(max(Int(note), l), h)) }
        var n = Int(note)
        while n > h { n -= 12 }
        while n < l { n += 12 }
        return UInt8(min(max(n, l), h))
    }
    /// Apply emitter `bus`'s FENCE policy to an already octave/key-shifted output note (0…127): returns the fenced
    /// note, or `nil` when the policy DROPS it. A no-op when the emitter isn't fenced or the note is in-window.
    /// ONE source of truth so the emit path (`emitOneBus`) and the LEGATO adoption pitch prediction agree on the
    /// wire pitch — a mismatch there re-struck a fenced drone every column boundary.
    @inline(__always)
    private func fencedNote(_ note: UInt8, bus: Int) -> UInt8? {
        guard bit(fenceMask, bus) else { return note }
        let lo = fenceLo[bus], hi = fenceHi[bus]
        guard lo <= hi, note < lo || note > hi else { return note }   // no window / in-window → unchanged
        switch fencePolicy[bus] {
        case 0:  return nil                                  // DROP
        case 1:  return min(max(note, lo), hi)               // CLAMP
        default: return fenceFold(note, lo: lo, hi: hi)      // FOLD
        }
    }
    // THE RACK — MONO (design-the-rack §6): per-emitter monophony. A new note-on STEALS the emitter's current note
    // per PRIORITY (0 LAST always · 1 LOW keeps the lower · 2 HIGH keeps the higher). Scan-based (no tracker to
    // clean up): the current holder is read live from the voice table, so transport/column flushes stay unaware.
    private var monoMask: UInt8 = 0
    private var monoPriority: [UInt8] = [0, 0, 0, 0]
    // THE RACK — POCKET (design-the-rack §6): per-emitter timing shift (samples, from ±ms), applied to a note's
    // on/off before opening its voices (both shift equally → duration preserved; clamped into the render window).
    private var pocketMask: UInt8 = 0
    private var pocketSamples: [Int64] = [0, 0, 0, 0]
    private var renderStart: Int64 = 0   // this render window's first sample — POCKET can't push a note before it
    // THE RACK — CONVERSATION (design-the-rack §6): one LEAD emitter; a follower's STANCE admits its NEW notes only
    // WITH the lead's sound (1) or AGAINST its silences (2). A live query of the lead's voices, like FLATTEN/CLAIM.
    private var convLead: Int = -1
    private var convStance: [UInt8] = [0, 0, 0, 0]
    private func emitterSounding(_ bus: Int) -> Bool {
        let b = UInt8(bus)
        for v in voices where v.active && !v.silent && v.bus == b { return true }
        return false
    }
    // emitter role family: ALT / TURNS — turn-taking IN TIME. `altSequence` is the expanded turn order (each group
    // member, position order, repeated its COUNT/dwell). The turn advances once per ARTICULATION MOMENT (a new
    // onset SAMPLE), and ALL notes at the same moment route to the SAME holder. So a single fan-out cell whose notes
    // land at distinct times still ping-pongs per note, while independent cells that fire at the SAME instant hand
    // off in time (A this moment, B the next) instead of splitting simultaneously (user 2026-08-04). `altMomentIndex`
    // % len picks the holder. previewMode bypasses (no role context).
    private var altMask: UInt8 = 0
    // Preallocated to its max (4 buses × 8 count = 32) so `rebuildAltSequence`'s append loop never reallocates on
    // the render thread — even the first window that grows it (audit B5). removeAll(keepingCapacity:) holds it.
    private var altSequence: [UInt8] = { var a = [UInt8](); a.reserveCapacity(32); return a }()
    private var altLastOnset: Int64 = .min   // onset sample of the current articulation moment (sentinel = fresh)
    private var altMomentIndex = -1          // moments elapsed; advances once per new onset time → picks the holder
    private var turnsPerNote = false         // TURNS mode: true = PER-NOTE exclusive (drop a simultaneous group note)
    // master panel: per-scene KEY (transpose, from the box), global MUTE (from the box), and the ephemeral
    // master velocity FADER (from process(), like the emitter override) — all applied in emitOneBus.
    private var masterKey: Int = 0
    private var masterMute = false
    private var masterVelOverride: UInt8 = 0
    private func rebuildAltSequence(_ count: [UInt8]) {
        altSequence.removeAll(keepingCapacity: true)
        for bus in 0..<4 where bit(altMask, bus) {
            for _ in 0..<Int(max(1, count[bus])) { altSequence.append(UInt8(bus)) }
        }
    }
    // delta §6a metering feed (EVENT-driven, not beat-derived): per-emitter peak velocity + event count
    // accumulated on the render thread, read-and-cleared by the UI poll. UI owns the decay envelope.
    private var meterPeakVel = [UInt8](repeating: 0, count: 4)
    private var meterEvents = [UInt32](repeating: 0, count: 4)
    // item 4 VELOCITY MARKS: per emitter, a bounded buffer of recent note-on (velocity, source colourIndex)
    // since the last drain — the UI holds+fades each as a floating mark tinted by the source Colour. Fixed
    // scratch (no render alloc); fills to 8 per poll cycle then drops (drained ~4 Hz, so 8 is ample).
    // FLAT 4×8 (index bus*8+i). These render→main feeds MUST NOT be nested `[[…]]`: the render thread's nested-array
    // element write churns the INNER arrays' refcounts while the 4 Hz main-thread drain reads them → an ARC data race
    // → libmalloc free-block corruption (device crash 2026-08-10 in drainEmitterSounding). A FLAT value array has no
    // inner-array ARC, so the only residual race is a torn value read (benign — a stale meter mark). (see memory)
    private var markVel = [UInt8](repeating: 0, count: 32)
    private var markCol = [Int8](repeating: -1, count: 32)
    private var markCount = [Int](repeating: 0, count: 4)
    // §6a THE WITHHELD TELL: a parallel bounded buffer of note-ons SUPPRESSED by CLAIM (leak 0) since the last
    // drain — same (velocity, source colourIndex) shape. The UI renders these HOLLOW + a claim-hue tick so a
    // suppressed note reads as "withheld here", not a silent bug. Only full CLAIM suppression records (a LEAK
    // shadow already sounds as a dimmer mark; solo/mute/disabled are intentional silences, not withholdings).
    private var withheldVel = [UInt8](repeating: 0, count: 32)   // FLAT 4×8 (index bus*8+i) — see markVel note (render↔main ARC-safe)
    private var withheldCol = [Int8](repeating: -1, count: 32)
    private var withheldCount = [Int](repeating: 0, count: 4)
    // §strips-done (the emitter twin of the receiver's recvHeld): the notes CURRENTLY SOUNDING per emitter — a
    // live snapshot of the voice table sliced by bus, each carrying (velocity, source colourIndex) so the UI
    // draws a hold-while-sounding tick in the SOURCE Colour (cargo tint) and fades it on release. Snapshotted on
    // the render thread each window; read-and-copied by the UI poll (benign staleness race, like the meters).
    private var soundVel = [UInt8](repeating: 0, count: 48)   // FLAT 4×12 (index bus*12+i) — see markVel note (render↔main ARC-safe)
    private var soundCol = [Int8](repeating: -1, count: 48)
    private var soundCount = [Int](repeating: 0, count: 4)
    private var currentColourIndex: Int8 = -1        // the emitting cell's colourIndex (for the SEAL comet feed)
    // THE SEAL COMET: per-CELL peak note velocity since the last drain (index = col*8+row) — the grid comet's
    // motion signal. Accumulated on the render thread at the emit boundary, read-and-cleared by the UI poll (the
    // UI owns the ~1s decay). `currentCellIndex` is the emitting cell's grid index, set per-cell in the emit loops.
    private var cellStrike = [UInt8](repeating: 0, count: 64)
    // THE NOTE-SWEEP feed (Paul 2026-08-19): per-cell RECENT emitted note-ons (pitch + velocity), a small ring per cell.
    // Drained read-and-clear like the strike feed → the piano-roll faces place marks at REAL pitch (not a hash), and the
    // BUILD note-sweep CONTOUR axis gets its per-note pitch. Fixed storage; no allocation on the render path.
    private var cellNotePitch = [UInt8](repeating: 0, count: 64 * 6)
    private var cellNoteVel   = [UInt8](repeating: 0, count: 64 * 6)
    private var cellNoteHead  = [Int](repeating: 0, count: 64)     // ring write cursor per cell
    private var cellNoteNew   = [UInt8](repeating: 0, count: 64)   // note-ons written since the last drain (return capped at 6)
    private var currentCellIndex: Int = -1
    // THE SEAL COMET (note-on/off gate): a bitmask of the 64 cells CURRENTLY SOUNDING (≥1 active non-silent
    // voice). Snapshotted on the render thread each window (a live set, like snapshotEmitterSounding); the UI
    // polls it so the spark travels for exactly as long as the note is held, and stops on release.
    private var cellSoundingMask: UInt64 = 0
    private var currentAlt = false                   // §2 the emitting cell's effective FACE (A/B), stamped onto opened voices
    // §2 CONTINUITY: transition scratch — a legato immortal voice is a candidate for ADOPTION until the
    // reconcile either keeps it (matched by the new column) or closes it (dropped). Sized to the pool, reused.
    private var holdCandidate = [Bool](repeating: false, count: 128)
    private var wasPlaying = false
    private var prevEffColumn = -1   // column-transition edge (§7): change ⇒ truncate voices
    // MULTI-SCENE S2b RESTART-the-pass: a beat offset shifting the WHOLE playing clock so the current moment
    // becomes column 0 ("take it from the top"). 0 = no restart (normal play is byte-identical). Reset on the
    // transport-start edge; captured = the raw beat at the restart. Shifts musicalOf + sampleOf together.
    private var passAnchor: Double = 0

    // AUDITION (§6.4 / delta §5): the held cell's target (col*rows+row, −1 = none), the sample the hold
    // began (its free phase clock's origin), and a dedicated tick-dedup slot. All ephemeral — audition
    // is a live gesture, never persisted, never in the snapshot.
    private var prevAudition = -1
    private var auditionStartSample: Int64 = 0
    private var auditionLastTick: Int64 = -1
    // PREVIEW / cell audition (Phase 2, design 2026-07-26): a VIRTUAL cell (the staged config) rendered
    // SOLO through the audition machinery. `previewMode` gates the CLAIM logic OFF (solo = no other-emitter
    // context); `prevPreviewActive` flushes on the activation edge. Reuses the audition clock/dedup slots
    // (preview and audition are mutually exclusive). Ephemeral, never in the snapshot.
    private var previewMode = false
    private var forceColumnHold = false        // PLAY: THIS CELL — the effColumn is force-held → tick emitters play UNGATED (continuous)
    // THE MOD PROCESSOR (CC generator): a beat-derived shaped CC on the active column's MOD cells. Emitted at a
    // control grid; deduped per (cable,channel,cc) so a held value doesn't re-send; RESET on column exit.
    private var modLastColumn: Int32 = -1                                     // the column whose MOD cells emitted last (reset when it exits)
    private var modColumnEntryBeat = 0.0                                      // STRIKE: the beat the active column became active (AR trigger)
    private var modPrevTarget = [Int16](repeating: -1, count: 64 * 8)         // per (gridCell*8 + slot): the LAST CC# a MOD slot emitted — revert it when the target changes
    // GLIDE (notes→pitch-bend): one mono sliding voice per GLIDE cell. Beat-derived ramps + a sustained anchor note.
    private struct GlideVoice {
        var anchor: Int16 = -1     // the sounding note-on pitch (-1 = no voice)
        var bus: Int8 = -1         // the emitter it sounds on
        var slot: Int16 = -1       // the openVoice slot (to close on re-anchor / phrase-end)
        var bendFrom = 0.0         // semitones-from-anchor at the ramp start
        var bendTo = 0.0           // …at the ramp end
        var rampStart = 0.0        // beat the current ramp began
        var lastInput: Int16 = -1  // the last input note (to detect a new target)
        var lastBend14: Int16 = -1 // dedup the emitted bend
    }
    private var glideVoices = [GlideVoice](repeating: GlideVoice(), count: 64)
    private var glideLastColumn: Int32 = -1
    private var modLastVal = [Int16](repeating: -1, count: 5 * 16 * 128)      // [cable*2048 + ch*128 + cc] → last CC value (-1 = none sent)
    private let modCtrlBeats = 1.0 / 16.0                                     // CC control-grid resolution (16 points per beat)
    // EXTERN: the incoming controller VALUE STORE (cc → value, channel-agnostic v1) — the Kernel writes it each render
    // (side rail, §7 READ-AT-SOURCE); a MOD stage in EXTERN mode reads + transforms it. -1 = never seen.
    private var controllerIn = [Int16](repeating: -1, count: 128)
    private var prevPreviewActive = false
    private var previewPrevColumn = -1        // the virtual cell's column-transition edge (strum reset / chord-hold re-emit)
    // Chord-hold audition (v2) scratch: the note-set the held source should be sounding through the
    // treatment, vs. what is sounding now — reconciled each window so the sustained preview follows the
    // keys live. Fixed 128-note bitsets + per-note velocity; reused every window, no hot-path allocation.
    private var auditionDesired = [Bool](repeating: false, count: 128)
    private var auditionCurrent = [Bool](repeating: false, count: 128)
    private var auditionVel = [UInt8](repeating: 96, count: 128)

    @inline(__always)
    private func rcIndex(_ cable: UInt8, _ chan: UInt8, _ note: UInt8) -> Int {
        (Int(cable % 5) * 16 + Int(chan & 15)) * 128 + Int(note & 127)
    }

    // Per-row reference scratch (delta §1). Each row's TICK articulations this window, so a
    // referencing cell can mirror its parent's output. Fixed capacity, no hot-path allocation.
    // lastTick dedups each row's arp independently across (rare) overlapping windows.
    private struct Artic {
        var onSample: Int64 = 0
        var offSample: Int64 = 0
        var note: UInt8 = 0    // after this row's accumulated transpose
        var beat: Double = 0   // musical onset beat — the stable seed for CHANCE (loop-consistent)
    }
    private static let articCap = 24
    private var articBuf = [Artic](repeating: Artic(), count: Snap.rows * Router.articCap)
    private var articCount = [Int](repeating: 0, count: Snap.rows)
    // CELL MACHINE (feat/EditPageSpike) stage-2: the SERIAL CHAIN feed. For a covered 2-slot chain (tail = a
    // sequencer), the TAIL reads the HEAD's output SET at each of its ticks from this fixed scratch pool
    // (refilled in place per tick by `fillChainInput` — no alloc). The head's set is DERIVED (identity/gate/
    // chance/harmonize from the shaped source; arp head = its one note at m), so it is window-independent.
    // For N>2 slots, `composeChainSet` folds every stage before the tail into `chainScratch` via a ping-pong of
    // two working pools (chainA/chainB — no alloc). The tail sequencer reads the result each tick.
    private let chainScratch = NotePool()
    private let chainA = NotePool()
    private let chainB = NotePool()
    private var lastTick = [Int64](repeating: -1, count: Snap.rows)
    // Per-row: the absolute column-step a window-scan GENERATOR (burst/cascade/drone/shift/humanize) last emitted in.
    // On a column's FIRST window it differs from the current step → scan from colStart so the DOWNBEAT (and any pulse
    // in [colStart, mWinStart)) fires once instead of being dropped at the boundary. (Paul 2026-08-18)
    private var lastGenStep = [Int64](repeating: Int64.min, count: Snap.rows)
    // §9 item 1 ON TAP (unified ALT model): ephemeral per-cell ALT flips (bit col*8+row). Set each process()
    // from the param; XORed into a cell's base ALT so a PERFORM tap is momentary, never a document write.
    private var tapAltMask: UInt64 = 0
    private func tapFlipped(_ col: Int, _ row: Int) -> Bool { (tapAltMask >> UInt64(col * 8 + row)) & 1 == 1 }
    // §9 item 1 ON TAP actions (4b), ephemeral: MUTE = a per-cell momentary silence (bit col*8+row);
    // SOLO EMITTERS = a global emitter solo set (bits A–D; 0 = no solo → siblings fall silent at emission).
    private var tapMuteMask: UInt64 = 0
    private var soloEmitterMask: UInt8 = 0
    private func tapMuted(_ col: Int, _ row: Int) -> Bool { (tapMuteMask >> UInt64(col * 8 + row)) & 1 == 1 }
    // EDIT PAGE "play this cell only" (user 2026-08-08): an ephemeral solo SET (bits col*8+row). While non-empty,
    // every cell whose bit is UNSET falls silent (like muted/dormant) — so only the edited cell(s) sound. 0 = off.
    private var soloCellMask: UInt64 = 0
    private func cellSoloedOut(_ col: Int, _ row: Int) -> Bool { soloCellMask != 0 && (soloCellMask >> UInt64(col * 8 + row)) & 1 == 0 }
    /// PLAY: THIS CELL — is THIS cell an explicit solo target? A target plays REGARDLESS of mute / dormant / tap-mute
    /// (the feature isolates and previews one cell's machine, so grid state must not silence it). (user 2026-08-10)
    private func cellSoloForced(_ col: Int, _ row: Int) -> Bool { soloCellMask != 0 && (soloCellMask >> UInt64(col * 8 + row)) & 1 == 1 }
    // receiver strip: the additive input SOLO set (bits R1–R4). While non-empty, a cell whose receiver is
    // NOT a member falls silent — `audible = ¬muted ∧ (soloSet=∅ ∨ member)`. Row-fed cells (recv −1) reach
    // this through their root MIDI-IN cell in parentSoundingNote. Ephemeral (cleared on stop / EDIT).
    private var soloReceiverMask: UInt8 = 0
    private func soloSilenced(_ cell: SnapCell) -> Bool {
        soloReceiverMask != 0 && cell.resolvedReceiver >= 0 && (soloReceiverMask & (1 << UInt8(cell.resolvedReceiver))) == 0
    }
    // receiver strip: an ephemeral ±octave nudge per receiver (−3…+3), packed one signed byte each. Composes
    // with the cell's colour transpose at the per-cell transpose local (a PLAYING control; 0 in stopped
    // audition). A note pushed past 0…127 by the sum is dropped by the per-emit guard (intended).
    private var inputOctave: UInt32 = 0
    private var inputSemitone: UInt32 = 0                    // receiver strip: per-receiver ±semitone NOTE nudge (composes with octave)
    private func octaveShift(_ recv: Int8) -> Int {          // total input transpose = octave×12 + semitone
        guard recv >= 0 else { return 0 }
        let oct = Int(Int8(bitPattern: UInt8((inputOctave >> (UInt32(recv) * 8)) & 0xFF)))
        let semi = Int(Int8(bitPattern: UInt8((inputSemitone >> (UInt32(recv) * 8)) & 0xFF)))
        return oct * 12 + semi
    }
    // receiver strip: the momentary-absolute INPUT-velocity override (the slider's ride), packed byte per
    // receiver (0 = none). Flattens a receiver's subscribers at the wire. `currentInputRecv` is the receiver
    // of the cell being articulated (render is single-threaded, so one field suffices) — read in emitOneBus.
    private var inputVelOverride: UInt32 = 0
    private var currentInputRecv: Int8 = -1
    // emitter strip: an ephemeral ±octave nudge per emitter (−3…+3), packed one signed byte each. Applied at
    // the emission boundary to the OUTGOING note (the receiver OCT's output-side mirror); a note pushed past
    // 0…127 is dropped. Cleared on stop.
    private var emitterOctave: UInt32 = 0
    private func emitterOctaveShift(_ bus: Int) -> Int {
        let byte = UInt8((emitterOctave >> (UInt32(bus) * 8)) & 0xFF)
        return Int(Int8(bitPattern: byte)) * 12
    }
    // receiver strip LATCH: while a receiver is armed (bit set), its subscribers read a FROZEN pool (the
    // captured chord) instead of the live one — the Kernel maintains the frozen pools + hands them in.
    private var latchMask: UInt8 = 0
    private var prevLatchMask: UInt8 = 0
    private var latchedPools: [NotePool] = []
    private var receiverDisabledMask: UInt8 = 0            // INPUT ENABLE: bit i = receiver i not listening (door closed)
    private let emptyPool: NotePool = { let p = NotePool(); p.rebuildSorted(); return p }()   // a disabled door's cells read this
    // BYPASS (§1/§2): this render's per-receiver admission (channel/cable/range, mute+disable already folded into
    // receiverChannels) + which doors bypass + their destination emitter masks. Read from the box each render.
    private var receiverChannels: [UInt8] = [0, 0, 0, 0]
    private var receiverCables: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111]
    private var receiverRangeLo: [UInt8] = [0, 0, 0, 0]
    private var receiverRangeHi: [UInt8] = [127, 127, 127, 127]
    private var receiverBypassMask: UInt8 = 0
    private var receiverBypassDest: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111]
    private var bypassDesired = [Bool](repeating: false, count: 128)   // scratch: desired source notes this render
    private var bypassScratch = [UInt8](repeating: 0, count: 128)      // scratch: the desired notes, read once
    /// The pool a cell reads: its receiver's frozen LATCH pool when armed (which STILL feeds while the door is
    /// disabled — the point of "close the door, keep the room"); else, if the door is DISABLED (not listening),
    /// nothing; else the live pool. A row-fed cell (recv −1) always reads live (its root's latch reaches it via
    /// parentSoundingNote). Mute is handled upstream (the cell's match-nothing filter kills even the frozen read).
    private func effectivePool(for cell: SnapCell, live: NotePool) -> NotePool {
        let r = cell.resolvedReceiver
        if r >= 0 {
            if receiverBypassMask & (1 << UInt8(r)) != 0 { return emptyPool }   // BYPASS: the door skips the grid (its stream injects to emitters instead)
            if latchMask & (1 << UInt8(r)) != 0, Int(r) < latchedPools.count { return latchedPools[Int(r)] }
            if receiverDisabledMask & (1 << UInt8(r)) != 0 { return emptyPool }   // not armed + not listening → silent
        }
        return live
    }

    /// BYPASS (§1/§2): a bypassed door's shaped, in-range held notes sound DIRECTLY on its destination emitters,
    /// skipping the grid. Runs every render (stopped + playing — a live monitor). Reuses openVoice/closeVoice so
    /// the refcount + dual-cable (own + All) + panic-safety all apply; the voices are IMMORTAL and tagged
    /// (bypassRecv ≥ 0) so the grid's continuity/transport flushes leave them be. DIRECT injection: no emitter
    /// roles. v1 applies RANGE + channel/cable admission (a muted/disabled door goes quiet — same filter);
    /// octave/velocity SHAPING is deferred (the output note = the source note, so on/off balance by note).
    private func reconcileBypass(pool: NotePool, atSample sample: Int64, out: MIDIEmitter?) {
        guard receiverBypassMask != 0 || anyBypassVoiceActive() else { return }   // fast path: nothing bypassed & none to close
        let savedCI = currentColourIndex, savedCell = currentCellIndex, savedAlt = currentAlt
        currentColourIndex = -1; currentCellIndex = -1; currentAlt = false        // bypass voices carry no grid identity / SEAL
        defer { currentColourIndex = savedCI; currentCellIndex = savedCell; currentAlt = savedAlt }
        for r in 0..<4 {
            // SOLO includes bypass (ruling 2026-08-04): a receiver SOLO set silences every non-soloed door's bypass
            // too — the door mutes with the grid. (LIVE-off already silences bypass via the match-nothing filter.)
            let soloExcluded = soloReceiverMask != 0 && (soloReceiverMask & (1 << UInt8(r))) == 0
            let bypassed = (receiverBypassMask & (1 << UInt8(r)) != 0) && !soloExcluded
            let destMask = bypassed ? receiverBypassDest[r] : 0
            // LATCH (incl. self-armed PIANO): a bypassed door with an armed latch injects its FROZEN chord, not the
            // (for PIANO, empty) live pool. The frozen pool is already receiver-filtered at capture, so read it whole
            // (OMNI / all-cables / full-range) — mirrors the input meter's `armed ? OMNI` read.
            let latched = (latchMask & (1 << UInt8(r)) != 0) && r < latchedPools.count
            let src = latched ? latchedPools[r] : pool
            let filter: UInt8 = latched ? 0 : receiverChannels[r], cable = latched ? 0b1111 : Int(receiverCables[r])
            let lo: UInt8 = latched ? 0 : receiverRangeLo[r], hi: UInt8 = latched ? 127 : receiverRangeHi[r]
            let cnt = destMask == 0 ? 0 : src.srcCount(filter: filter, cableMask: cable, velLo: 0, velHi: 127, noteLo: lo, noteHi: hi)
            for k in 0..<cnt {
                let n = src.srcAscending(k, filter: filter, cableMask: cable, velLo: 0, velHi: 127, noteLo: lo, noteHi: hi)
                bypassScratch[k] = n; bypassDesired[Int(n)] = true
            }
            // CLOSE: this door's bypass voices whose note is released OR whose dest bus is no longer selected.
            for i in voices.indices where voices[i].active && voices[i].bypassRecv == Int8(r) {
                if !(bypassDesired[Int(voices[i].note)] && (destMask & (1 << voices[i].bus)) != 0) {
                    closeVoice(i, atSample: sample, out: out)
                }
            }
            // OPEN: each desired (note × dest emitter) not already sounding — on its own cable + the All copy.
            if destMask != 0 {
                for k in 0..<cnt {
                    let note = bypassScratch[k]
                    let vel = max(1, src.heldVelocity(note))
                    for d in 0..<4 where (destMask & (1 << UInt8(d))) != 0 && !bypassVoiceExists(recv: r, note: note, bus: UInt8(d)) {
                        let ch = (busChannels[d] &- 1) & 15
                        _ = openVoice(note: note, chan: ch, cable: UInt8(d + 1), bus: UInt8(d), onSample: sample, offSample: .max, velocity: vel, out: out, bypassRecv: Int8(r))
                        _ = openVoice(note: note, chan: ch, cable: 0,            bus: UInt8(d), onSample: sample, offSample: .max, velocity: vel, out: out, bypassRecv: Int8(r))
                    }
                }
            }
            for k in 0..<cnt { bypassDesired[Int(bypassScratch[k])] = false }   // clear the scratch for the next door
        }
    }
    private func anyBypassVoiceActive() -> Bool {
        for i in voices.indices where voices[i].active && voices[i].bypassRecv >= 0 { return true }
        return false
    }
    private func bypassVoiceExists(recv: Int, note: UInt8, bus: UInt8) -> Bool {
        for i in voices.indices where voices[i].active && voices[i].bypassRecv == Int8(recv) && voices[i].note == note && voices[i].bus == bus { return true }
        return false
    }
    private var strumProgress = [Int](repeating: 0, count: Snap.rows)   // strum notes emitted this column, per row
    // SPLIT downstream ([driver→SPLIT]): the driver's-source-pool note/vel bounds, resolved once per cell in the row loop
    // (where the live pool is in scope), then applied to every driven note in emitDriverNote.
    private var splitGateActive = false
    private var splitGateLo = 0, splitGateHi = 127, splitGateVF = 1, splitGateVC = 127
    private var prevForcedStep = Int.min   // last musical STEP seen while a column is HELD → re-arm strum each step (Paul 2026-08-15)
    private var harmNotes = [Int](repeating: 0, count: 4)               // HARMONIZE fan scratch (root + 3 voices)
    private var harmVels = [UInt8](repeating: 0, count: 4)

    // THE TAIL (AcceptanceCriteria-tail-era-delay-echo §0): ECHO repeats fire at FUTURE beats, so — unlike the pure
    // derived engine — they can't be re-derived from the current column (the cell isn't visited once the playhead
    // leaves, and a released chord leaves no pool). Each DRY strike REGISTERS an activation here; `drainEchoTails`
    // emits its due repeats every window, column-independent (tails ring out past the column AND past release). A
    // NEW sanctioned mutable-state exception: cleared on EVERY transport/scene/panic/latch edge + reset + a beat
    // discontinuity, so tails die on stop (v1) and never leak (the fuzz `quiescent` check guards it).
    private struct EchoTail {
        var active = false
        var onset: Double = 0        // musical beat of the dry strike (echo k at onset + (k + offset)·timeBeats)
        var note: UInt8 = 0
        var vel: UInt8 = 0           // the DRY velocity; echo k = vel · feedDelay · decay^(k-1)
        var busMask: UInt8 = 0
        var timeBeats: Double = 0.5
        var repeats: Int = 0         // 1…16
        var feedDelay: Double = 0.7  // input send — first echo level
        var decay: Double = 0.5   // regeneration — decay ratio between echoes
        var offset: Double = 0       // ±0.33 nudge off the grid
        var pitch: Int = 0           // semitones per successive echo
        var gateBeats: Double = 0.25
        var spill: EchoSpill = .ring // RING = tail spills past the column · CUT = pending repeats die at column exit
    }
    private static let echoTailCap = 256
    private var echoTails = [EchoTail](repeating: EchoTail(), count: Router.echoTailCap)
    private var echoPrevMEnd: Double = .nan   // last window's musical end — a large gap ⇒ a seek/loop discontinuity

    // THE FLOOD GOVERNOR (incident 2026-08-08: a runaway ECHO×HARM patch fed thousands of ev/s and wedged the
    // downstream synths). A hard per-EMITTER note-on cap per BEAT — overflow DROPS (counted), so we stay a good
    // citizen at our wire beneath every synth's allocator floor. Offs are NEVER capped (no stuck notes). Bounded,
    // visible (the cog HEALTH counter), never silent-failing. Reset each beat + on transport reset.
    static let floodCapPerBeat = 48           // dev-tunable; ~48/beat/emitter ≈ 384 ev/s total @ 120bpm
    private var noteOnsThisBeat = [Int](repeating: 0, count: 4)
    private var lastGovBeat = Int.min
    private(set) var floodDropped = 0          // session total surfaced to HEALTH ("dropped N this session")

    private var echoTailsActive: Bool { echoTails.contains { $0.active } }
    private func clearEchoTails() { for i in echoTails.indices { echoTails[i].active = false }; echoPrevMEnd = .nan }
    private func pushEchoTail(onset: Double, note: UInt8, vel: UInt8, busMask: UInt8, timeBeats: Double, repeats: Int,
                              feedDelay: Double, decay: Double, offset: Double, pitch: Int, gateBeats: Double,
                              spill: EchoSpill = .ring) {
        guard repeats > 0, timeBeats > 0, busMask != 0 else { return }
        var slot = -1
        for i in echoTails.indices where !echoTails[i].active { slot = i; break }
        if slot < 0 {                                    // budget: ring full → evict the OLDEST (smallest onset)
            var oldest = 0
            for i in echoTails.indices where echoTails[i].onset < echoTails[oldest].onset { oldest = i }
            slot = oldest
        }
        echoTails[slot] = EchoTail(active: true, onset: onset, note: note, vel: vel, busMask: busMask,
                                   timeBeats: timeBeats, repeats: min(16, repeats), feedDelay: feedDelay,
                                   decay: decay, offset: offset, pitch: pitch, gateBeats: gateBeats, spill: spill)
    }

    // reset() arrives on the CONTROL thread (the AU's @objc reset:, e.g. AUM disabling the plugin) — which can race
    // the render thread already inside process()/flushMod, so mutating the render-state arrays here corrupted the
    // Swift-Array refcounts → a malloc double-free crash (device 2026-08-10). So reset() only RAISES A FLAG; the
    // actual clear runs at the top of process() on the render thread, where it can't race. If no render follows
    // (teardown), nothing is left to clear anyway.
    private var pendingReset = false
    func reset() { pendingReset = true }
    private func performReset() {
        for i in voices.indices { voices[i].active = false; voices[i].offSample = .max; voices[i].silent = false }
        for i in refcount.indices { refcount[i] = 0 }
        distinctSounding = 0
        wasPlaying = false
        for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
        prevEffColumn = -1
        prevBusEnabledMask = 0b1111
        for i in 0..<4 { meterPeakVel[i] = 0; meterEvents[i] = 0; markCount[i] = 0; withheldCount[i] = 0; soundCount[i] = 0 }
        prevAudition = -1; auditionLastTick = -1
        for i in 0..<4 { noteOnsThisBeat[i] = 0 }; lastGovBeat = Int.min   // FLOOD GOVERNOR: fresh budget on transport reset (floodDropped is a session total)
        for i in overrides.indices { overrides[i] = .nan }
        overrideGen = .max
        clearEchoTails()
        modLastColumn = -1; modColumnEntryBeat = 0                              // MOD: forget the last CC + column (no reset emit — reset() has no `out`)
        for i in modLastVal.indices { modLastVal[i] = -1 }
        for i in modPrevTarget.indices { modPrevTarget[i] = -1 }
        for i in glideVoices.indices { glideVoices[i] = GlideVoice() }; glideLastColumn = -1
    }

    // MARK: parameter overrides

    @inline(__always)
    private func slot(for address: UInt64) -> Int? {
        switch address {
        case 0: return 0
        case 1: return 1
        case 100..<116: return 2 + Int(address - 100)
        case 200..<216: return 18 + Int(address - 200)
        case 300: return 34
        default: return nil
        }
    }

    @inline(__always)
    private func over(_ slotIndex: Int, _ fallback: Double) -> Double {
        // The override table is sized for the 16 host-automatable colours (transpose 2+i, morph 18+i, i<16).
        // An EPHEMERAL colour (index ≥16, Paul's unlimited-colours model) has no param address → no override,
        // so it uses its own value. Guard the read so a high colour index never traps the render thread.
        guard slotIndex >= 0, slotIndex < overrides.count else { return fallback }
        let v = overrides[slotIndex]
        return v.isNaN ? fallback : v
    }

    /// The per-cell base transpose: the TRANSPOSE param (override slot 2+ci), rounded to a semitone.
    /// Callers ADD the receiver/hold octave addends themselves — those differ per site (the preview/
    /// audition sites deliberately omit the receiver octave), so they must NOT be folded in here.
    private func colourTranspose(_ ci: Int, _ colour: SnapColour) -> Int {
        Int(over(2 + ci, Double(colour.transpose)).rounded())
    }

    /// A real document edit publishes a fresh snapshot generation → it is the new truth, so drop
    /// the render-side overrides and let the two param routes agree again (§7). Call once per render,
    /// BEFORE applying this render's parameter events.
    func refreshOverrides(forGeneration generation: UInt64) {
        if generation != overrideGen {
            for i in overrides.indices { overrides[i] = .nan }
            overrideGen = generation
        }
    }

    /// Apply one render-side .parameter/.parameterRamp event.
    func applyParamEvent(_ address: UInt64, _ value: Double, diag: inout KernelDiag) {
        guard let idx = slot(for: address) else { return }
        overrides[idx] = value
        diag.paramEventCount &+= 1
        diag.lastParamAddr = Int64(address)
        diag.lastParamValue = value
    }

    // Topmost occupied, non-muted cell in a grid column — the single active cell (grid-chaining across
    // cells is retired; a cell's OWN processor chain runs in emitColumnHolds / the tick loop). cells
    // index = column*8 + row (Snapshot.swift). Muted cells produce nothing (§6.2).
    @inline(__always)
    private func topCell(in column: Int, _ box: SnapshotBox) -> (row: Int, cell: SnapCell)? {
        let c = ((column % Snap.cols) + Snap.cols) % Snap.cols
        for row in 0..<Snap.rows {
            let cell = box.cells[c * Snap.rows + row]
            if cell.colourIndex >= 0 && !cell.muted { return (row, cell) }
        }
        return nil
    }

    // MARK: voice table

    /// Emit a note-on and register a voice with its scheduled gate-off. Returns the slot, or -1 if
    /// the table is full (the on still sounded; we just can't track its off — capacity is 128).
    @discardableResult
    private func openVoice(note: UInt8, chan: UInt8, cable: UInt8, bus: UInt8,
                           onSample: Int64, offSample: Int64,
                           velocity: UInt8 = 96, out: MIDIEmitter?, silent: Bool = false,
                           bypassRecv: Int8 = -1) -> Int {
        guard let out else { return -1 }
        // Claim a slot BEFORE emitting: at capacity we DROP the note (return −1 without emitting) rather
        // than emit an on we can't schedule an off for — an untrackable note would hang. At 128-voice
        // capacity this never trips for the real topologies (incl. claim ghosts, which are finite-lived).
        var slot = -1
        for i in voices.indices where !voices[i].active { slot = i; break }
        guard slot >= 0 else { return -1 }

        // §6a CLAIM: a SILENT voice (a muted claimant's reservation) is tracked for exclusivity only —
        // no wire note-on and no refcount, so it can never emit an off or hold a shared channel alive.
        if !silent {
            let idx = rcIndex(cable, chan, note)
            // WIRE ARTICULATION = RESTRIKE (user 2026-08-09, spec `-wire-articulation`): a strike on an ALREADY-
            // sounding (cable,ch,note) emits a clean note-OFF then note-ON at the same timestamp (off first) — a
            // proper re-attack that retriggers mono synths and pairs offs correctly. The refcount is UNCHANGED by
            // the re-articulation off (it governs the true release only), so the note still ends solely at
            // refcount→0 and nothing is left stuck. (MERGE — the old on-only overlap — is the deferred option chip.)
            if refcount[idx] > 0 { out.emit(sampleTime: onSample, cable: cable, 0x80 | chan, note, 0) }
            out.emit(sampleTime: onSample, cable: cable, 0x90 | chan, note, max(1, velocity))   // §7 clause 1: note-ons ALWAYS emit
            if refcount[idx] == 0 { distinctSounding += 1 }
            refcount[idx] += 1
        }

        voices[slot].active = true
        voices[slot].note = note
        voices[slot].chan = chan
        voices[slot].cable = cable
        voices[slot].bus = bus
        voices[slot].offSample = offSample
        voices[slot].silent = silent
        voices[slot].colourIndex = currentColourIndex   // §2 adoption identity (COLOUR-AND-FACE)
        voices[slot].alt = currentAlt
        voices[slot].vel = velocity                     // §strips-done: for the hold-while-sounding feed
        voices[slot].cellIndex = (currentCellIndex >= 0 && currentCellIndex < 64) ? Int8(currentCellIndex) : -1   // SEAL sounding gate
        voices[slot].bypassRecv = bypassRecv   // BYPASS: tag direct-injection voices so grid/transport flushes skip them
        return slot
    }

    /// delta §6a metering: read-and-clear the per-emitter peak velocity + event count since the last
    /// call. UI-poll side (main thread) vs render-side accumulation — the race is benign (a dropped
    /// meter tick at worst), consistent with the diag being display-only.
    func drainMeters() -> (peak: [UInt8], events: [UInt32]) {
        // Build FRESH arrays (never capture the render-written buffers) so the render thread can't hit copy-on-write
        // + a refcount race on a shared buffer — the _swift_release_dealloc crash class. The per-byte read/reset race
        // vs the render is benign (a dropped meter tick at worst).
        var peak = [UInt8](repeating: 0, count: 4), events = [UInt32](repeating: 0, count: 4)
        for i in 0..<4 { peak[i] = meterPeakVel[i]; meterPeakVel[i] = 0; events[i] = meterEvents[i]; meterEvents[i] = 0 }
        return (peak, events)
    }
    /// SEAL comet: read-and-clear the per-CELL peak strike velocity (index = col*8+row) since the last poll.
    /// Accumulates across render windows (never lost between polls); the UI stamps a hit time + owns the decay.
    func drainCellStrikes() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: 64)   // FRESH copy — never share `cellStrike` with the poll (COW-on-render race)
        for i in 0..<64 { out[i] = cellStrike[i]; cellStrike[i] = 0 }
        return out
    }

    /// NOTE-SWEEP feed: per cell, the note-ons emitted SINCE the last drain (up to 6 most-recent, oldest→newest) as
    /// pitch + velocity, plus a per-cell count. FRESH copies (never share render arrays with the poll). Read-and-clear.
    func drainCellNotes() -> (pitch: [UInt8], vel: [UInt8], count: [UInt8]) {
        var p = [UInt8](repeating: 0, count: 64 * 6), vv = [UInt8](repeating: 0, count: 64 * 6), cnt = [UInt8](repeating: 0, count: 64)
        for c in 0..<64 {
            let n = Int(cellNoteNew[c]); cnt[c] = cellNoteNew[c]; cellNoteNew[c] = 0
            for k in 0..<n {
                let idx = ((cellNoteHead[c] - n + k) % 6 + 6) % 6
                p[c * 6 + k] = cellNotePitch[c * 6 + idx]; vv[c * 6 + k] = cellNoteVel[c * 6 + idx]
            }
        }
        return (p, vv, cnt)
    }

    /// item 4 VELOCITY MARKS: read-and-clear the per-emitter note-on marks accumulated since the last poll —
    /// each a (velocity, source colourIndex). The UI latches a timestamp per mark and fades it (~250ms).
    func drainMarks() -> [[(vel: UInt8, col: Int8)]] {
        var out = [[(vel: UInt8, col: Int8)]]()
        for bus in 0..<4 {
            let cnt = min(8, max(0, markCount[bus]))   // clamp a possibly-torn count so the flat index stays in bounds
            var m = [(vel: UInt8, col: Int8)](); m.reserveCapacity(cnt)
            for i in 0..<cnt { m.append((markVel[bus * 8 + i], markCol[bus * 8 + i])) }
            markCount[bus] = 0
            out.append(m)
        }
        return out
    }

    /// §strips-done: snapshot the notes CURRENTLY SOUNDING per emitter — the active (non-silent) voices bucketed
    /// by originating bus, each a (velocity, source colourIndex). Called on the render thread once per window,
    /// AFTER process reconciles the voice table. Overwrites the buffers (a live set, not an accumulate-clear).
    func snapshotEmitterSounding() {
        for b in 0..<4 { soundCount[b] = 0 }
        for v in voices where v.active && !v.silent {
            let b = Int(v.bus)
            guard b >= 0, b < 4, soundCount[b] < 12 else { continue }
            soundVel[b * 12 + soundCount[b]] = v.vel
            soundCol[b * 12 + soundCount[b]] = v.colourIndex
            soundCount[b] += 1
        }
    }

    /// SEAL comet: snapshot which of the 64 cells are CURRENTLY SOUNDING (≥1 active, non-silent voice) into a
    /// bitmask. Render thread, once per window after reconciliation (like snapshotEmitterSounding). The UI polls
    /// `currentCellSounding` and drives the spark's life off the gate — travelling for exactly the held duration.
    func snapshotCellSounding() {
        var mask: UInt64 = 0
        for v in voices where v.active && !v.silent && v.cellIndex >= 0 {
            mask |= UInt64(1) << UInt64(v.cellIndex)
        }
        cellSoundingMask = mask
    }
    /// UI-poll read of the per-cell sounding bitmask (main thread; benign render/UI staleness, as the other feeds).
    func currentCellSounding() -> UInt64 { cellSoundingMask }

    /// §strips-done: UI-poll read of the currently-sounding snapshot (main thread; the render/UI race is benign
    /// staleness, identical to the meter + recvHeld feeds). Each emitter → its live (velocity, source colour) set.
    func drainEmitterSounding() -> [[(vel: UInt8, col: Int8)]] {
        var out = [[(vel: UInt8, col: Int8)]]()
        for b in 0..<4 {
            let cnt = min(12, max(0, soundCount[b]))   // clamp a possibly-torn count so the flat index stays in bounds
            var m = [(vel: UInt8, col: Int8)](); m.reserveCapacity(cnt)
            for i in 0..<cnt { m.append((soundVel[b * 12 + i], soundCol[b * 12 + i])) }
            out.append(m)
        }
        return out
    }

    /// §6a THE WITHHELD TELL: read-and-clear the per-emitter note-ons CLAIM fully suppressed (leak 0) since
    /// the last poll — each a (would-be velocity, source colourIndex). The UI draws these hollow + a claim tick.
    func drainWithheld() -> [[(vel: UInt8, col: Int8)]] {
        var out = [[(vel: UInt8, col: Int8)]]()
        for bus in 0..<4 {
            let cnt = min(8, max(0, withheldCount[bus]))   // clamp a possibly-torn count so the flat index stays in bounds
            var m = [(vel: UInt8, col: Int8)](); m.reserveCapacity(cnt)
            for i in 0..<cnt { m.append((withheldVel[bus * 8 + i], withheldCol[bus * 8 + i])) }
            withheldCount[bus] = 0
            out.append(m)
        }
        return out
    }

    /// delta §6a: close every sounding voice that ORIGINATED from emitter `bus` — its own cable AND its
    /// copy on All. The refcount keeps a shared-channel note alive on All if another (enabled) emitter
    /// still owns it (its All voice, from a different bus, is untouched).
    private func closeBus(_ bus: UInt8, atSample time: Int64, out: MIDIEmitter?) {
        for i in voices.indices where voices[i].active && voices[i].bus == bus { closeVoice(i, atSample: time, out: out) }
    }

    private func closeVoice(_ i: Int, atSample time: Int64, out: MIDIEmitter?) {
        guard voices[i].active else { return }
        let cable = voices[i].cable, chan = voices[i].chan, note = voices[i].note
        let wasSilent = voices[i].silent
        voices[i].active = false
        voices[i].offSample = .max
        voices[i].silent = false
        // §6a CLAIM: a silent reservation never touched the wire or the refcount — just free the slot.
        if wasSilent { return }

        let idx = rcIndex(cable, chan, note)
        if refcount[idx] > 0 { refcount[idx] -= 1 }
        if refcount[idx] == 0 {
            distinctSounding = max(0, distinctSounding - 1)
            // §7 clause 2: the wire note-off fires ONLY when the last instance releases. Clause 3:
            // no restoration strike — a surviving instance is simply never re-struck.
            out?.emit(sampleTime: time, cable: cable, 0x80 | chan, note, 0)
        }
    }

    /// Emit any scheduled gate-off that has come due this window (drained every render → no stuck
    /// note when a voice's off falls beyond the window it was opened in).
    private func drainDue(windowStart: Int64, windowEnd: Int64,
                          out: MIDIEmitter?) {
        for i in voices.indices where voices[i].active && voices[i].offSample <= windowEnd {
            closeVoice(i, atSample: max(voices[i].offSample, windowStart), out: out)
        }
    }

    /// Close every sounding voice at one sample time (transport edge, column transition, reset). BYPASS voices
    /// PERSIST by default (a live monitor survives transport/latch/scene edges — reconcileBypass owns their
    /// lifecycle); only a hard PANIC passes `includeBypass: true` to flush them too.
    func allNotesOff(atSample time: Int64, out: MIDIEmitter?, includeBypass: Bool = false) {
        for i in voices.indices where voices[i].active && (includeBypass || voices[i].bypassRecv < 0) {
            closeVoice(i, atSample: time, out: out)
        }
    }
    /// PANIC belt-and-braces (incident 2026-08-08 §3): beyond our own tracked note-offs, blast CC120 (all-sound-off)
    /// + CC123 (all-notes-off) on every channel and every cable, so a wedged synth we can't fully account for gets a
    /// blameless reset. Only on the hard flush (master-MUTE long-press / panic) — never on ordinary edges.
    func panicControllers(atSample time: Int64, out: MIDIEmitter?) {
        guard let out else { return }
        for cable: UInt8 in 0...4 {
            for ch: UInt8 in 0...15 {
                out.emit(sampleTime: time, cable: cable, 0xB0 | ch, 120, 0)   // All Sound Off
                out.emit(sampleTime: time, cable: cable, 0xB0 | ch, 123, 0)   // All Notes Off
            }
        }
    }

    /// §2 CONTINUITY: the column-transition close, minus the legato drones. Truncates every voice at the
    /// boundary (arp tails, retrig/chance/harmonize holds, claim ghosts) EXCEPT audible IMMORTAL voices —
    /// the legato chord-holds. Those survive into `emitColumnHolds`, which then ADOPTS the ones the new
    /// column re-holds identically and closes the rest (the reconcile). Everything else re-strikes as before.
    private func closeExceptLegatoHolds(atSample time: Int64, out: MIDIEmitter?) {
        // Keep every IMMORTAL voice (offSample .max) — the audible legato drones AND, if a drone landed on a
        // CLAIM emitter, its silent ownership ghost. Both share note+bus+colour+face, so the reconcile adopts
        // or closes them in lockstep (no orphaned ghost leaking a slot). During play these are the ONLY
        // immortal voices (arp/retrig ghosts carry a finite offSample; audition is stopped-only).
        for i in voices.indices where voices[i].active && voices[i].offSample != .max {
            closeVoice(i, atSample: time, out: out)
        }
    }

    /// §2 CONTINUITY: ADOPT a legato hold. Scan the transition's candidate voices for the ones matching this
    /// re-held identity — same wire NOTE + EMITTER (bus) + COLOUR-AND-FACE — and un-mark them (keep alive:
    /// own cable + its All copy, both cleared). Returns true iff ≥1 matched, in which case the caller does
    /// NOT re-emit on this bus: the existing voices flow through the boundary with no off/on (the drone).
    private func adoptLegatoBus(wire: UInt8, bus: UInt8, ci: Int8, alt: Bool) -> Bool {
        var found = false
        for i in voices.indices where holdCandidate[i]
            && voices[i].note == wire && voices[i].bus == bus
            && voices[i].colourIndex == ci && voices[i].alt == alt {
            holdCandidate[i] = false
            found = true
        }
        return found
    }

    private func anyVoiceActive() -> Bool {
        for v in voices where v.active { return true }
        return false
    }
    /// Any active IMMORTAL legato GRID hold (a sustained drone) — offSample .max, not a BYPASS voice. Used by the
    /// single-column-lap release fix (audit B2): a pinned effColumn never fires the column-change reconcile.
    private func anyLegatoHold() -> Bool {
        for v in voices where v.active && v.offSample == .max && v.bypassRecv < 0 { return true }
        return false
    }

    // §6a CLAIM v2: is `note`'s PITCH CLASS owned by ANY claimant, and if so at what LEAK %? Returns nil when
    // unclaimed (the note sounds normally); otherwise the MIN leak among the claimants sounding that class —
    // the strictest shadow wins (0 = full suppression). Matched on note % 12 (delta §6a user fix): a claimed
    // C3 owns ALL C's — every octave — so the claimant keeps its HARMONY and octave doubles are the residue
    // exclusivity prevents. Answered from the claimants' persistent SILENT ghosts (emitOneBus opens one per
    // claimant note, enabled or muted), which survive the audible voice's immediate close — so this is
    // rate-independent (a fast arp note that opens+closes inside one window still registers the claim).
    private func claimedPitchLeak(_ note: UInt8) -> Int? {
        guard claimMask != 0 else { return nil }
        let pc = note % 12
        var minLeak = Int.max
        for v in voices where v.active && v.silent && (claimMask & (1 << v.bus)) != 0 && v.note % 12 == pc {
            minLeak = min(minLeak, Int(claimLeak[Int(v.bus) & 3]))
        }
        return minLeak == Int.max ? nil : minLeak
    }

    private func activeVoiceCount() -> Int {
        var n = 0
        for v in voices where v.active { n += 1 }
        return n
    }

    /// FUZZ/CHAOS self-consistency (invariants I8/I10): the engine is fully QUIESCENT — no active voice, no distinct
    /// sounding note, every collision refcount back to zero. The fuzz harness asserts this after a flush + settle;
    /// a non-quiescent engine after `allNotesOff` is a leaked voice or a dangling refcount (a hung note in waiting).
    var quiescent: Bool {
        distinctSounding == 0 && voices.allSatisfy { !$0.active } && refcount.allSatisfy { $0 == 0 } && !echoTailsActive
    }
    /// I3 helper: true if two ACTIVE, non-silent voices share a full identity (note·chan·cable·emitter·Colour·face).
    /// The adoption law folds an identically re-held voice into ONE — a duplicate here is a phantom (adoption miss).
    var hasDuplicateVoices: Bool {
        var seen = Set<UInt64>()
        for v in voices where v.active && !v.silent {
            let key = (UInt64(v.note) << 40) | (UInt64(v.chan) << 32) | (UInt64(v.cable) << 24)
                    | (UInt64(v.bus) << 16) | (UInt64(bitPattern: Int64(v.colourIndex)) & 0xFF) << 8 | (v.alt ? 1 : 0)
            if !seen.insert(key).inserted { return true }
        }
        return false
    }

    /// a8 DUMP: a compact one-line fingerprint of every still-open voice — the readable "corpse" for the
    /// assert-on-silence dump. Off the render hot path (called only when the silence invariant is violated).
    func stuckVoiceFingerprint() -> String {
        var parts: [String] = []
        for v in voices where v.active {
            parts.append("n\(v.note)/ch\(v.chan)/cbl\(v.cable)/bus\(v.bus)\(v.silent ? "·ghost" : "")")
        }
        return parts.isEmpty ? "none" : parts.joined(separator: " ")
    }

    // MARK: - graph routing (delta §1)

    // (grid-chaining retired: `parentRow`/`resolvedParent` are gone — every cell reads its receiver source.)

    @inline(__always)
    private func sampleOf(musical: Double, beatPos: Double, beatsPerSample: Double,
                          windowStart: Int64, S: Double, a: Double) -> Int64 {
        let real = realOf(musical, stepBeats: S, a: a)
        return windowStart + Int64(max(0, (real - beatPos) / beatsPerSample))
    }

    private func storeArtic(row: Int, on: Int64, off: Int64,
                            note: UInt8, beat: Double) {
        let c = articCount[row]
        guard c < Router.articCap else { return }
        let i = row * Router.articCap + c
        articBuf[i].onSample = on; articBuf[i].offSample = off
        articBuf[i].note = note; articBuf[i].beat = beat
        articCount[row] = c + 1
    }

    /// FAN OUT one articulation to every lit bus (§2.3). Channel is STAMPED per bus here (delta §7:
    /// notes have no channel until this exit); each bus emits TWICE — its own cable (bus+1) and the
    /// ALL cable (0), both on busChannels[bus] (§7b). Every (cable,channel,note) is an independent
    /// voice under the refcount, so the ALL duplicate and any shared-channel merge off-pair correctly.
    /// Channel comes ONLY from the bus stamp now (INHERIT/OUT CH removed, delta §7).
    private func emitArtic(note: UInt8, busMask: UInt8,
                           onSample: Int64, offSample: Int64,
                           windowEnd: Int64, velocity: UInt8 = 96,
                           out: MIDIEmitter?, diag: inout KernelDiag) {
        var lastCh: UInt8 = 0
        // role family ALT / TURNS (user 2026-08-04/05): the TURNS emitters take turns playing the INCOMING notes
        // from ANY cell. The turn advances once per ARTICULATION MOMENT (a new onset sample). Two MODES:
        //  · PER-MOMENT (default): all notes at one moment route to the SAME holder = altSequence[momentIndex]
        //    (two independent cells firing together both sound on ONE emitter, then hand off next moment).
        //  · PER-NOTE (turnsPerNote, user 2026-08-05): the group's emitters are TIME-EXCLUSIVE — only the FIRST note
        //    of each moment plays (on the turn-holder; altSequence[0] = leftmost on the first strike), and every
        //    other note at that exact onset is DROPPED (busMask cleared of group bits — never delayed a tick).
        // Non-group emitters in the fan-out are untouched either way. A single fan-out cell whose notes land at
        // distinct times still ping-pongs per note. COUNT = moments of dwell. previewMode bypasses.
        var busMask = busMask
        if (busMask & altMask) != 0 && !previewMode && !altSequence.isEmpty {
            let newMoment = (onSample != altLastOnset)
            if newMoment { altLastOnset = onSample; altMomentIndex &+= 1 }   // a new moment → advance the turn
            if turnsPerNote && !newMoment {
                busMask &= ~altMask                                          // PER-NOTE: drop the simultaneous group note (leftmost/first survives, no delay)
            } else {
                busMask = (busMask & ~altMask) | (1 << altSequence[altMomentIndex % altSequence.count])
            }
        }
        // §6a CLAIM v2: emit ALL claimant buses in this fan-out FIRST (any order among them), so every
        // claimant's ownership trace (the silent ghost opened in emitOneBus) is in the table before any
        // non-claimant in the same fan-out checks — co-onset suppression is then order-independent.
        var mask = busMask
        var cm = busMask & claimMask
        while cm != 0 {
            let bus = Int(cm.trailingZeroBitCount)            // 0…3 = A…D
            cm &= cm - 1
            let c = emitOneBus(bus, note: note, velocity: velocity, onSample: onSample,
                               offSample: offSample, windowEnd: windowEnd, out: out)
            if c >= 0 { lastCh = UInt8(c) }
        }
        mask &= ~claimMask
        while mask != 0 {
            let bus = Int(mask.trailingZeroBitCount)          // 0…3 = A…D
            mask &= mask - 1
            let c = emitOneBus(bus, note: note, velocity: velocity, onSample: onSample,
                               offSample: offSample, windowEnd: windowEnd, out: out)
            if c >= 0 { lastCh = UInt8(c) }
        }
        diag.emitCount &+= 1
        diag.lastEmitNote = note
        diag.lastEmitChan = lastCh
    }

    /// Emit ONE lit bus of a fanned articulation: CLAIM handling → enable gate → velocity override →
    /// meter → the two cables (own bus+1 and ALL). Returns the wire channel it stamped, or −1 if nothing
    /// audible was emitted (gated/suppressed). A regular method (not a captured closure) — no render-path
    /// allocation. Both cables are channel-stamped identically and tagged with the origin bus (§6a/§7b).
    @discardableResult
    private func emitOneBus(_ bus: Int, note: UInt8, velocity: UInt8,
                            onSample: Int64, offSample: Int64, windowEnd: Int64, out: MIDIEmitter?) -> Int {
        // emitter strip OCT: shift the OUTGOING note by this emitter's ±octave overlay (0 = none). A note
        // pushed off 0…127 is dropped. Applied FIRST so CLAIM/metering/refcount all key on the real output
        // pitch. `note` is shadowed to the shifted value for the remainder.
        // master panel MUTE: a global emission kill — nothing sounds (claim ghosts included). previewMode
        // (stopped audition) still auditions through it.
        if masterMute && !previewMode { return -1 }
        // ...OCT shift + the master KEY (per-scene transpose) both fold into the outgoing pitch here.
        let sn = Int(note) + emitterOctaveShift(bus) + (previewMode ? 0 : masterKey)
        guard sn >= 0 && sn <= 127 else { return -1 }
        var note = UInt8(sn)
        // THE RACK FENCE: a per-emitter note-RANGE policy on the OUTPUT pitch — DROP (suppress), CLAMP (to the
        // nearest bound), or FOLD (octave-fold in). Applied here so CLAIM/metering/refcount all key on the fenced
        // pitch, and the note-off (opened on this same note) pairs cleanly. previewMode bypasses. `fencedNote` is
        // the shared transform (the legato adoption prediction applies the SAME one).
        if !previewMode {
            guard let fenced = fencedNote(note, bus: bus) else { return -1 }   // nil = DROP
            note = fenced
        }
        var leakScale = 100   // 100 = no attenuation; a leaked (shadow) non-claimant sets this < 100 below
        if claimMask != 0 && !previewMode {   // PREVIEW bypasses CLAIM (solo — no other-emitter context)
            if bit(claimMask, bus) {
                // §6a CLAIM ownership trace: a PERSISTENT silent ghost (no wire, no refcount) marks this
                // claimant as sounding the pitch for the note's whole life. It is what non-claimants check
                // (`claimedPitchLeak`), decoupled from the AUDIBLE voice below — which is immediate-closed
                // for short notes. So suppression is RATE-INDEPENDENT: a fast arp note that opens+closes
                // inside one render window still registers the claim. NOT immediate-closed here (that is the
                // whole point); drainDue / transport edges / reset close it sample-accurately. A muted
                // claimant opens ONLY this ghost. Claimants never suppress each other (SHARED tier), so a
                // claimant emitter always reaches its ghost — never the yield branch below.
                openVoice(note: note, chan: 0, cable: UInt8(bus + 1), bus: UInt8(bus),
                          onSample: onSample, offSample: offSample, velocity: 0, out: out, silent: true)
            } else if let leak = claimedPitchLeak(note) {
                // Non-claimant yields a pitch class a claimant owns. LEAK 0 → suppress, never defer: no voice
                // opens, no off to emit, refcount untouched (v1). LEAK > 0 → the hole becomes a SHADOW: fall
                // through and emit at scaled velocity (the strictest claimant's leak already won upstream).
                if leak == 0 {
                    // THE WITHHELD TELL: record the fully-suppressed note-on so the strip can render it hollow.
                    if withheldCount[bus] < 8 {
                        withheldVel[bus * 8 + withheldCount[bus]] = velocity; withheldCol[bus * 8 + withheldCount[bus]] = currentColourIndex
                        withheldCount[bus] += 1
                    }
                    return -1
                }
                leakScale = leak
            }
        }
        // delta §6a: a DISABLED emitter emits nothing audible (its claim ghost, if any, was opened above,
        // so a muted claimant still reserves). All is then exactly the sum of ENABLED emitters.
        guard bit(busEnabledMask, bus) else { return -1 }
        // §9 ON TAP = SOLO EMITTERS: while a solo set is held, sibling emitters fall silent (own cable + its
        // All contribution). previewMode bypasses (solo audition has no other-emitter context).
        if soloEmitterMask != 0 && !previewMode && !bit(soloEmitterMask, bus) { return -1 }
        // THE RACK CONVERSATION: a follower emitter admits its NEW note-ons only WITH the lead's sound (stance 1)
        // or AGAINST its silences (stance 2). A live query of the lead's voices (like FLATTEN). The lead itself and
        // FREE (stance 0) emitters are unaffected. previewMode bypasses (no other-emitter context).
        if convLead >= 0 && convLead != bus && !previewMode {
            let stance = convStance[bus]
            if stance != 0 {
                let leadSounding = emitterSounding(convLead)
                if (stance == 1 && !leadSounding) || (stance == 2 && leadSounding) { return -1 }
            }
        }
        // receiver strip INPUT override: while a receiver's slider is touched, flatten its subscribers' notes
        // to the slider value (applied to the base velocity). The emitter (OUTPUT) override below still wins
        // if both ride at once — the override closest to the wire has the last word.
        let iv = currentInputRecv >= 0 ? UInt8((inputVelOverride >> (UInt32(currentInputRecv) * 8)) & 0xFF) : 0
        let base = iv != 0 ? iv : velocity
        // §6a PERFORM momentary override: while a strip's slider is touched, flatten every NEW note-on on
        // that emitter to the slider value (own cable + its All copy). 0 = untouched → natural velocity.
        let ov = UInt8((velOverride >> (UInt32(bus) * 8)) & 0xFF)
        var v = ov != 0 ? ov : base
        // role family FLATTEN: while ANOTHER emitter with FLATTEN set is sounding, duck this NEW note-on by the
        // strongest such amount. Existing/sounding notes are untouched (the shipped no-lurch rule); the bloom
        // back is instant because it's a per-note-on query of the live voice table. previewMode bypasses.
        if flattenMask != 0 && !previewMode {
            var duck = 0
            for k in 0..<4 where k != bus && (flattenMask & (1 << UInt8(k))) != 0 && emitterSounding(k) {
                duck = max(duck, Int(flattenAmount[k]))
            }
            if duck > 0 { v = UInt8(max(1, Int(v) * (100 - duck) / 100)) }
        }
        // §6a CLAIM v2 LEAK: a leaked non-claimant (a claimed pitch class bleeding through) sounds at scaled
        // velocity — the SHADOW. Same tier as FLATTEN (a per-note-on duck); the master fader below still wins.
        if leakScale < 100 { v = UInt8(max(1, Int(v) * leakScale / 100)) }
        // THE RACK CURVE: per-emitter output-velocity re-map (soft↔hard). A per-note transform of the shaped
        // velocity, before the master fader (which still wins absolutely). previewMode bypasses (raw audition).
        if bit(curveMask, bus) && !previewMode { v = curveVelocity(v, curveAmount[bus]) }
        // master panel FADER: a momentary-absolute override over ALL output — applied LAST so it wins over the
        // per-emitter/input overrides and FLATTEN (the whisper-drop). 0 = untouched. previewMode bypasses.
        if masterVelOverride != 0 && !previewMode { v = masterVelOverride }
        // THE RACK MONO: force one note per emitter. Read the current holder (the emitter's own-cable voice) live;
        // decide by PRIORITY whether the new note wins; if it loses, suppress it (return −1 before metering); if it
        // wins, STEAL — close the holder's voices (own + its All copy) at this onSample, then fall through to open
        // the new note (RETRIG: old off, new on). Same-note re-articulation isn't a steal (refcount handles it).
        if bit(monoMask, bus) && !previewMode {
            var holder = -1
            for vv in voices where vv.active && !vv.silent && vv.bus == UInt8(bus) && vv.cable == UInt8(bus + 1) { holder = Int(vv.note); break }
            if holder >= 0 && holder != Int(note) {
                let wins: Bool
                switch monoPriority[bus] {
                case 1: wins = Int(note) <= holder     // LOW: keep the lower note
                case 2: wins = Int(note) >= holder     // HIGH: keep the higher note
                default: wins = true                    // LAST: the new note always steals
                }
                if !wins { return -1 }
                for i in voices.indices where voices[i].active && !voices[i].silent && voices[i].bus == UInt8(bus) && voices[i].note != note {
                    closeVoice(i, atSample: onSample, out: out)
                }
            }
        }
        // THE FLOOD GOVERNOR: this note-on has passed every suppression gate and WOULD sound. Cap it — a hard
        // per-emitter budget per beat; overflow DROPS (counted, not silent-failing). Offs are never governed, so a
        // dropped on simply never opens a voice → nothing to leave stuck. previewMode (stopped audition) is exempt.
        if !previewMode {
            if noteOnsThisBeat[bus] >= Router.floodCapPerBeat { floodDropped &+= 1; return -1 }
            noteOnsThisBeat[bus] &+= 1
        }
        if v > meterPeakVel[bus] { meterPeakVel[bus] = v }   // §6a metering (post-transform vel, incl. override)
        meterEvents[bus] &+= 1
        if currentCellIndex >= 0 && currentCellIndex < 64 {
            if v > cellStrike[currentCellIndex] { cellStrike[currentCellIndex] = v }   // SEAL comet: this cell struck
            let c = currentCellIndex, h = cellNoteHead[c]                              // NOTE-SWEEP: record the emitted pitch+vel (ring)
            cellNotePitch[c * 6 + h] = note; cellNoteVel[c * 6 + h] = v
            cellNoteHead[c] = (h + 1) % 6
            if cellNoteNew[c] < 6 { cellNoteNew[c] &+= 1 }
        }

        if markCount[bus] < 8 {                              // item 4: a floating velocity MARK for this note-on
            markVel[bus * 8 + markCount[bus]] = v; markCol[bus * 8 + markCount[bus]] = currentColourIndex
            markCount[bus] += 1
        }
        let ch = (busChannels[bus] &- 1) & 15             // 1–16 stored → 0–15 wire
        // THE RACK POCKET: shift this note's on/off by the emitter's timing offset (samples). Both shift equally so
        // the duration is preserved; the on is clamped into [renderStart, windowEnd] (can't play in the past or
        // beyond the window), and a held note (offSample .max) keeps its immortal off. previewMode bypasses.
        var onS = onSample, offS = offSample
        if bit(pocketMask, bus) && !previewMode && pocketSamples[bus] != 0 {
            let target = onSample + pocketSamples[bus]
            onS = max(renderStart, min(windowEnd, target))
            if offSample != .max { offS = max(onS + 1, offSample + (onS - onSample)) }
        }
        let own = openVoice(note: note, chan: ch, cable: UInt8(bus + 1), bus: UInt8(bus),
                            onSample: onS, offSample: offS, velocity: v, out: out)
        if own >= 0 && offS <= windowEnd { closeVoice(own, atSample: offS, out: out) }
        let all = openVoice(note: note, chan: ch, cable: 0, bus: UInt8(bus),
                            onSample: onS, offSample: offS, velocity: v, out: out)
        if all >= 0 && offS <= windowEnd { closeVoice(all, atSample: offS, out: out) }
        return Int(ch)
    }

    /// HOLD content, emitted ONCE per column at the transition: an identity cell whose input is MIDI
    /// IN articulates the whole (filtered) source chord and holds it to the column boundary (identity
    /// = sample-and-hold of its input pool). Arp cells and referencing mirrors have no hold.
    /// HARMONIZE emit (§3): expand `base` (post-transpose) into root + up to 3 interval voices and
    /// emit each with its velocity (root full, added voices scaled). Optionally stores artics so a
    /// downstream mirror sees the full expanded set. Shared by the MIDI-IN hold and the mirror path.
    private func emitHarmony(base: Int, colour: SnapColour, baseVel: UInt8, row: Int,
                             storeArtics: Bool, busMask: UInt8,
                             on: Int64, off: Int64, beat: Double,
                             windowEnd: Int64, sustain: Bool = false, out: MIDIEmitter?,
                             diag: inout KernelDiag) {
        let iv = (Int8(effectiveHarmInterval(colour, voice: 0)),
                  Int8(effectiveHarmInterval(colour, voice: 1)),
                  Int8(effectiveHarmInterval(colour, voice: 2)))
        let scale = effectiveHarmVelScale(colour)
        let cnt = harmonizeVoices(base: base, intervals: iv, into: &harmNotes,
                                  vel: baseVel, velScale: scale, vels: &harmVels)
        for i in 0..<cnt {
            if storeArtics { storeArtic(row: row, on: on, off: off, note: UInt8(harmNotes[i]), beat: beat) }
            guard busMask != 0 else { continue }
            if sustain {
                // PLAY: THIS CELL — under a frozen column each harmony voice is IMMORTAL + ADOPTED (per-bus, mirrors
                // the identity legato branch), so the every-window re-run reconciles the same harmonized set instead
                // of re-striking. Voices carry currentColourIndex/currentAlt so adoptLegatoBus matches on re-run.
                var emitMask: UInt8 = 0
                for b in UInt8(0)..<4 where busMask & (1 << b) != 0 {
                    let sw = Int(harmNotes[i]) + emitterOctaveShift(Int(b)) + masterKey
                    guard sw >= 0 && sw <= 127 else { continue }
                    guard let w = fencedNote(UInt8(sw), bus: Int(b)) else { continue }
                    if !adoptLegatoBus(wire: w, bus: b, ci: Int8(currentColourIndex), alt: currentAlt) { emitMask |= (1 << b) }
                }
                if emitMask != 0 {
                    emitArtic(note: UInt8(harmNotes[i]), busMask: emitMask, onSample: on, offSample: .max,
                              windowEnd: windowEnd, velocity: harmVels[i], out: out, diag: &diag)
                }
            } else {
                emitArtic(note: UInt8(harmNotes[i]), busMask: busMask, onSample: on, offSample: off,
                          windowEnd: windowEnd, velocity: harmVels[i], out: out, diag: &diag)
            }
        }
    }

    private func emitColumnHolds(box: SnapshotBox, column: Int, pool: NotePool, pass: Int,
                                 S: Double, a: Double, mNow: Double, beatPos: Double,
                                 beatsPerSample: Double, windowStart: Int64,
                                 windowEnd: Int64, out: MIDIEmitter?,
                                 reconcileOnly: Bool = false,   // PLAY: THIS CELL frozen-column re-run — adopt/close the immortal holds only, never re-strike
                                 diag: inout KernelDiag) {
        let colStart = columnStart(mNow, S)
        let onSample = sampleOf(musical: colStart, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                windowStart: windowStart, S: S, a: a)
        let offSample = sampleOf(musical: colStart + S, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                 windowStart: windowStart, S: S, a: a)
        // §2 CONTINUITY: every audible IMMORTAL (legato) voice from the previous column is a candidate for
        // ADOPTION. The reconcile below un-marks each one this column re-holds identically; any still marked
        // at the end were dropped (a different chord, a changed emitter/face, or an empty column) and close
        // at the boundary. An empty pool → no cell emits → all candidates close (close-at-first-empty-column,
        // the pass-length envelope) — so this runs even when the pool guard below skips the emit loop. Silent
        // CLAIM ghosts of a drone are candidates too (adoptLegatoBus matches them by note+bus+colour+face), so
        // a ghost adopts/closes in lockstep with its audible voice — never orphaned.
        for i in voices.indices { holdCandidate[i] = voices[i].active && voices[i].offSample == .max && voices[i].bypassRecv < 0 }   // BYPASS voices are immortal but NOT grid holds — never adopt/close them here
        // Proceed while the LIVE pool has notes OR any receiver is latch-armed: an armed receiver's FROZEN pool
        // feeds its subscribers even with no keys down (effectivePool). Non-subscribing cells read the empty live
        // pool → emit nothing, so opening the gate for the latch is safe. (Without this, the release of the keys
        // emptied the live pool and the whole hold loop was skipped — the latch "did nothing".)
        if pool.count > 0 || latchMask != 0 {
        for r in 0..<Snap.rows {
            let cell = box.cells[column * Snap.rows + r]
            if cell.colourIndex < 0 || cell.busMask == 0 || cellSoloedOut(column, r) || (!cellSoloForced(column, r) && (cell.muted || cell.dormant || tapMuted(column, r))) { continue }   // §9 ON TAP = MUTE · LADDER dormant (PLAY: THIS CELL overrides both)
            if isCoveredChain(cell) { continue }   // CELL MACHINE stage-2: the ARP tail emits in the tick loop; the head must not chord-hold here
            if composableLengthTailIndex(cell) != nil { continue }   // [→ LENGTH] re-articulates the composed set in the tick loop (emitLengthComposedRow), never a plain hold here
            if isEchoTail(cell) { continue }       // ECHO: an echo-tail cell fires its dry + tail in emitEchoColumn, never a hold here
            if soloSilenced(cell) { continue }   // receiver strip: input SOLO excludes this cell's receiver
            currentInputRecv = cell.resolvedReceiver   // receiver strip: this cell's receiver, for the input-vel override
            currentColourIndex = cell.colourIndex      // item 4 marks: this cell's Colour, for the source tint
            currentCellIndex = column * Snap.rows + r  // SEAL comet: this cell's grid index
            let ci = Int(cell.colourIndex)
            let colour = box.colours[ci]
            // Cells that chord-hold their MIDI-IN source: identity (incl. open passgate), CHANCE
            // (drops each note by probability), and HARMONIZE (expands each note to voices).
            // Arp/ratchet/strum and a closed passgate do not chord-hold.
            if !onSceneAudible(colour.on, pass: pass) { continue }   // §9 item 1 ON SCENE: not entered / exited
            let altFlag = cell.alt != tapFlipped(column, r)          // §9 ON TAP flip — this cell's voice-identity face
            currentAlt = altFlag                                     // §2 stamp fresh voices' face identity
            // CELL MACHINE: a HOLD-TAIL chain holds the TAIL slot's transform of every upstream stage's composed
            // set; a plain cell holds its head-only treatment of the source.
            let holdChain = isHoldTailChain(cell)
            let tailIdx = cell.procs.count - 1
            var treat = colour; let treatP = holdChain ? cell.procs[tailIdx] : cell.proc
            treat.a = treatP
            let mode = cellMode(type: effectiveType(treat),
                                bypassed: holdChain ? cell.slotBypass[tailIdx] : cell.bypassed,
                                passMask: effectivePassMask(treat), pass: pass)
            guard mode == .identity || mode == .chance || mode == .harmonize || mode == .drone || mode == .tutti || mode == .split else { continue }   // DRONE = a legato chord-hold (user 2026-08-10); TUTTI/SPLIT = SET filters
            if mode == .tutti && !holdChain && treat.a.tuttiMode == .pattern { continue }   // PATTERN standalone re-articulates per slice in the tick loop, not here
            let transpose = colourTranspose(ci, colour)
                          + octaveShift(cell.resolvedReceiver)           // receiver strip: input OCT nudge
            let prob = (mode == .chance) ? effectiveProbability(treat) : 1
            let droneScale = mode == .drone ? max(0.05, min(1.0, treatP.gate)) : 1.0   // DRONE: GATE = the pad's velocity level (relative to the source)
            let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: pass)   // §9 item 1 EMITTER-ROTATE
            // §2 CONTINUITY: an identity chord-hold under LEGATO is a DRONE — it flows through column
            // boundaries. RETRIG (and .free) re-strike as before; CHANCE/HARMONIZE re-speak (per-column
            // dice / expansion); the ALT turn-group is excluded (a rotating emitter is a fresh strike).
            // PLAY: THIS CELL (forceColumnHold) freezes the column, so this can't re-fire on a boundary to sustain a
            // gated hold — the cell would sound one column then die. Treat EVERY hold mode (identity / chance /
            // harmonize) as immortal+adopted so the machine plays CONTINUOUSLY; the frozen colStart makes the chance
            // dice + harmony stable, so the every-window re-run (reconcileOnly) adopts the identical set (no re-strike).
            let soloSustain = forceColumnHold && (bm & altMask) == 0
            let legato = (bm & altMask) == 0 && ((mode == .identity && treat.a.phase == .legato) || mode == .drone || soloSustain)   // a DRONE is ALWAYS legato (sustains + adopts across drone columns; closes where no drone re-holds it)
            if reconcileOnly && !legato { continue }   // frozen-column re-run: only the immortal holds reconcile
            // §cell-edit F CHOP: a hold is ONE articulation (at colStart = slice 0), so route it by that slice's
            // chop — MAIN adds the cell's own emitters, ALT adds altDest, MUTE silences. `chopMask` returns `bm`
            // unchanged when the cell has no chop, so this is a no-op for ordinary holds. (Tick cells chop per-tick.)
            let hbm = chopMask(cell, m: colStart, S: S, base: bm)
            let cellPool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: frozen chord if armed
            if holdChain { composeChainSet(cell: cell, pool: cellPool, upto: tailIdx - 1, m: colStart, S: S, cycleBeats: Double(Snap.cols) * S) }
            let srcN = holdChain ? chainScratch.srcCount(filter: 0, cableMask: 0b1111) : cellPool.srcCount(for: cell)   // §7 source filter
            // TUTTI: one seeded roll per STEP decides the whole set — TUTTI (−1 = every rank passes) or SOLO (only the
            // PICK-chosen rank). The step index is derived from musical position (colStart/S) so it's loop-consistent.
            let tuttiSolo: Int = {
                guard mode == .tutti, treat.a.tuttiMode == .coin else { return -1 }   // PATTERN (phase 2) passes through
                let step = S > 0 ? Int((colStart / S).rounded()) : 0
                return tuttiIsTutti(step: step, balance: treat.a.tuttiBalance) ? -1 : tuttiSoloRank(step: step, count: srcN, pick: treat.a.tuttiPick)
            }()
            // SPLIT (standalone/hold): the subset window of the held set to keep (TOP/BOTTOM re-rank the live pool; RANGE absolute).
            let splitWin: (start: Int, len: Int) = (mode == .split)
                ? chordSplitWindow(count: srcN, split: treat.a.splitSet,
                                   noteAt: { holdChain ? Int(chainScratch.srcAscending($0, filter: 0, cableMask: 0b1111)) : Int(cellPool.srcAscending($0, for: cell)) })
                : (0, srcN)
            for k in 0..<srcN {
                let base = holdChain ? Int(chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111)) : Int(cellPool.srcAscending(k, for: cell))
                let n = base + transpose
                guard n >= 0 && n <= 127 else { continue }
                let vel0 = max(1, holdChain ? chainScratch.velocity(UInt8(base)) : cellPool.velocity(UInt8(base)))   // inherit the source velocity (user 2026-08-09)
                let vel = droneScale < 1.0 ? UInt8(max(1, min(127, Int((Double(vel0) * droneScale).rounded())))) : vel0   // DRONE scales by GATE
                if mode == .chance && !chancePassesPool(beat: colStart, note: n, rank: k, count: srcN, probability: prob, tilt: treat.a.chanceTilt, constantDensity: treat.a.chanceDensity) { continue }   // POOL-AWARE chance (user 2026-08-11)
                if mode == .tutti && tuttiSolo >= 0 && k != tuttiSolo { continue }   // TUTTI SOLO step: only the PICK-chosen rank sounds
                if mode == .split && (k < splitWin.start || k >= splitWin.start + splitWin.len || Int(vel0) < treat.a.splitVel.floor || Int(vel0) > treat.a.splitVel.ceil) { continue }   // SPLIT: keep the subset + vel band
                if mode == .harmonize {
                    emitHarmony(base: n, colour: treat, baseVel: vel, row: r, storeArtics: false,
                                busMask: hbm, on: onSample, off: offSample, beat: colStart,
                                windowEnd: windowEnd, sustain: soloSustain, out: out, diag: &diag)   // PLAY: THIS CELL — harmonize holds sustain + adopt too
                } else if legato {
                    // §2 per-bus reconcile: ADOPT the buses a matching drone already sounds (no off/on);
                    // STRIKE only the buses that are new — each opened IMMORTAL (offSample .max) so drainDue
                    // never truncates it and only the next boundary's reconcile can close it.
                    var emitMask: UInt8 = 0
                    for b in UInt8(0)..<4 where hbm & (1 << b) != 0 {
                        let sw = n + emitterOctaveShift(Int(b)) + masterKey  // the octave/key-shifted pitch…
                        guard sw >= 0 && sw <= 127 else { continue }         // out of range → emitOneBus would drop it
                        guard let w = fencedNote(UInt8(sw), bus: Int(b)) else { continue }  // …then FENCE — the exact wire pitch emitOneBus will open (DROP → no bus)
                        if !adoptLegatoBus(wire: w, bus: b, ci: Int8(ci), alt: altFlag) { emitMask |= (1 << b) }
                    }
                    if emitMask != 0 {
                        emitArtic(note: UInt8(n), busMask: emitMask,
                                  onSample: onSample, offSample: .max, windowEnd: windowEnd,
                                  velocity: vel, out: out, diag: &diag)
                    }
                } else {
                    emitArtic(note: UInt8(n), busMask: hbm,
                              onSample: onSample, offSample: offSample, windowEnd: windowEnd,
                              velocity: vel, out: out, diag: &diag)
                }
            }
            // ECHO in a HOLD-tail chain ([ECHO→HARMONIZE], [ECHO→GATE]): register tails for the FULLY-PROCESSED set —
            // echo's chain position doesn't change the content (v1), it repeats the final (harmonized) output. Without
            // this the echo was silently dropped (composeChainSet folds it as pass-through). (user 2026-08-10 bug.)
            if !reconcileOnly, holdChain, let ep = chainEchoParams(cell) {
                composeChainSet(cell: cell, pool: cellPool, upto: tailIdx, m: colStart, S: S, cycleBeats: Double(Snap.cols) * S)
                for k in 0..<chainScratch.srcCount(filter: 0, cableMask: 0b1111) {
                    let base = Int(chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111))
                    let n = base + transpose; guard n >= 0 && n <= 127 else { continue }
                    pushEchoForNote(n, vel: max(1, chainScratch.velocity(UInt8(base))), bm: hbm, p: ep, onset: colStart, S: S)
                }
            }
        }
        }
        // §2 CONTINUITY: close the drones this column did NOT re-hold (dropped notes / empty column), at the
        // boundary. Adopted voices were un-marked above and flow through untouched.
        for i in voices.indices where holdCandidate[i] { closeVoice(i, atSample: onSample, out: out) }
    }

    /// ECHO (tail-era §2) — at a column ENTRY, strike each echo cell's DRY chord (short, so every repeat retriggers
    /// on the synth) and REGISTER a tail per struck note. Single-slot `[ECHO]` cells only (v1): a multi-slot chain's
    /// echo folds as pass-through (mode is taken from the head). Called once per column transition; the repeats
    /// themselves emit from `drainEchoTails` every window.
    private func emitEchoColumn(box: SnapshotBox, column: Int, pool: NotePool, pass: Int, S: Double, a: Double, tempo: Double,
                               mNow: Double, beatPos: Double, beatsPerSample: Double, windowStart: Int64,
                               windowEnd: Int64, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard pool.count > 0 || latchMask != 0 else { return }
        let colStart = columnStart(mNow, S)
        let onSample = sampleOf(musical: colStart, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                windowStart: windowStart, S: S, a: a)
        for r in 0..<Snap.rows {
            let cell = box.cells[column * Snap.rows + r]
            if cell.colourIndex < 0 || cell.busMask == 0 || cellSoloedOut(column, r) || (!cellSoloForced(column, r) && (cell.muted || cell.dormant || tapMuted(column, r))) { continue }
            if soloSilenced(cell) { continue }
            let ci = Int(cell.colourIndex)
            let colour = box.colours[ci]
            if !onSceneAudible(colour.on, pass: pass) { continue }
            guard isEchoTail(cell) else { continue }   // single-slot [ECHO] OR a hold-upstream chain tail (…→ECHO)
            let tailIdx = cell.procs.count - 1
            let p = cell.procs[tailIdx]                 // the ECHO slot's own controls (user 2026-08-08)
            registerEcho(p, cell: cell, colour: colour, ci: ci, column: column, r: r, pool: pool, tempo: tempo,
                         colStart: colStart, onSample: onSample, S: S, a: a, beatPos: beatPos,
                         beatsPerSample: beatsPerSample, windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        }
    }
    /// Strike the DRY note (only when THRU) + register the echo tail for each source note of an echo-tail cell —
    /// shared by the single/hold-tail path (emitEchoColumn) and the tick-driven path ([ARP→ECHO], per driver tick).
    private func registerEcho(_ p: SnapParams, cell: SnapCell, colour: SnapColour, ci: Int, column: Int, r: Int,
                              pool: NotePool, tempo: Double, colStart: Double, onSample: Int64, S: Double, a: Double,
                              beatPos: Double, beatsPerSample: Double, windowStart: Int64, windowEnd: Int64,
                              out: MIDIEmitter?, diag: inout KernelDiag) {
        // DELAY TIME: synced = 16th-notes (div/4 beats; 4 = one beat) · free = ms → beats at the live tempo.
        let timeBeats = p.echoSync ? Double(p.echoDelayDiv) / 4.0 : max(0.001, p.echoDelayMs / 1000.0 * tempo / 60.0)
        guard timeBeats > 0 else { return }
        let repeats = max(1, min(16, p.echoRepeats))
        let gateBeats = min(timeBeats * 0.9, S * 0.9)
        let offSample = sampleOf(musical: colStart + gateBeats, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                 windowStart: windowStart, S: S, a: a)
        let transpose = colourTranspose(ci, colour) + octaveShift(cell.resolvedReceiver)
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: 0)
        currentInputRecv = cell.resolvedReceiver; currentColourIndex = cell.colourIndex
        currentCellIndex = column * Snap.rows + r
        // SOURCE: a hold-upstream chain echoes its upstream stages' composed set ([PASSGATE→ECHO] the gated chord,
        // [HARMONIZE→ECHO] the harmonised set); a single [ECHO] echoes the cell's source directly.
        let cellPool = effectivePool(for: cell, live: pool)
        let multi = cell.procs.count >= 2
        if multi { composeChainSet(cell: cell, pool: cellPool, upto: cell.procs.count - 2, m: colStart, S: S, cycleBeats: Double(Snap.cols) * S) }
        let srcN = multi ? chainScratch.srcCount(filter: 0, cableMask: 0b1111) : cellPool.srcCount(for: cell)
        for k in 0..<srcN {
            let srcNote = multi ? chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111) : cellPool.srcAscending(k, for: cell)
            let n = Int(srcNote) + transpose
            guard n >= 0 && n <= 127 else { continue }
            let vel = max(1, multi ? chainScratch.velocity(srcNote) : cellPool.velocity(srcNote))   // inherit the source velocity (user 2026-08-09)
            // §cell-edit F CHOP: the dry AND the tail route through the per-slice split (was raw `bm` — echo bypassed
            // it). Both take the source note's slice destination, so a muted slice silences the note and its echoes.
            let chopped = chopMask(cell, m: colStart, S: S, base: bm)   // (user 2026-08-09)
            if p.echoThru && chopped != 0 {               // THRU passes the dry note; MUTE = echoes only
                emitArtic(note: UInt8(n), busMask: chopped, onSample: onSample, offSample: offSample,
                          windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
            }
            pushEchoTail(onset: colStart, note: UInt8(n), vel: vel, busMask: chopped, timeBeats: timeBeats, repeats: repeats,
                         feedDelay: p.echoFeedDelay, decay: p.echoDecay, offset: p.echoOffset, pitch: p.echoPitch,
                         gateBeats: gateBeats, spill: p.echoSpill)
        }
    }

    /// Emit every registered echo REPEAT whose musical time lands in this window [mStart, mEnd) — column-independent,
    /// so tails ring out after the playhead leaves the cell's column AND after the source chord releases. Each repeat
    /// opens a voice with a scheduled off (drainDue guarantees the off → no stuck note). Decay-floor + all-past retire
    /// the entry. A beat DISCONTINUITY (seek/loop/tempo jump) clears the ring — v1 drops tails on the jump (look-back
    /// preservation is v2). Runs BEFORE the empty-pool guard so a released chord's tail still sounds.
    private func drainEchoTails(mStart: Double, mEnd: Double, beatPos: Double, beatsPerSample: Double,
                               windowStart: Int64, windowEnd: Int64, S: Double, a: Double,
                               out: MIDIEmitter?, diag: inout KernelDiag) {
        if !echoPrevMEnd.isNaN && abs(mStart - echoPrevMEnd) > S { clearEchoTails() }   // seek/loop/tempo jump → drop tails
        echoPrevMEnd = mEnd
        for i in echoTails.indices where echoTails[i].active {
            let e = echoTails[i]
            // TAIL SPILL = CUT: once the playhead has crossed this tail's COLUMN boundary, stop scheduling repeats —
            // the last one already emitted keeps its scheduled off, so the sounding note finishes its gate (no lurch).
            if e.spill == .cut && mStart >= columnStart(e.onset, S) + S { echoTails[i].active = false; continue }
            if e.onset + (Double(e.repeats) + 1) * e.timeBeats < mStart { echoTails[i].active = false; continue }   // all past → retire
            for k in 1...e.repeats {
                let tau = e.onset + (Double(k) + e.offset) * e.timeBeats     // OFFSET nudges each echo off the grid
                if tau < mStart || tau >= mEnd { continue }                 // half-open: fires in exactly one window
                // FEED DELAY = the first echo's send level · FEEDBACK = the per-echo decay ratio (tail length)
                let v = Int((Double(e.vel) * e.feedDelay * pow(e.decay, Double(k - 1))).rounded())
                if v < 1 { continue }                                       // level floor kills the tail
                let n = Int(e.note) + k * e.pitch                           // PITCH: climb/descend each successive echo
                guard n >= 0 && n <= 127 else { continue }
                let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                   windowStart: windowStart, S: S, a: a)
                let offT = sampleOf(musical: tau + e.gateBeats, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                    windowStart: windowStart, S: S, a: a)
                emitArtic(note: UInt8(n), busMask: e.busMask, onSample: onT, offSample: offT,
                          windowEnd: windowEnd, velocity: UInt8(min(127, v)), out: out, diag: &diag)
            }
        }
    }

    /// The shared subdivision-tick scaffold for ARP and RATCHET. Walks every tick of length `sub`
    /// in this window that belongs to `effColumn`, dedups per row, and hands the body the tick's
    /// index, musical beat, and unwarped on/off sample times. `gateFraction` sets the note length
    /// as a fraction of `sub` (truncated at the column boundary). The body decides WHAT to emit;
    /// this owns the timing — so the boundary/dedup logic lives in exactly one place.
    /// Return from the body to skip a tick (the equivalent of `continue`).
    private func iterateTicks(row: Int, effColumn: Int, sub: Double, gateFraction: Double,
                              beatPos: Double, windowBeats: Double, windowStart: Int64,
                              beatsPerSample: Double, S: Double, a: Double,
                              _ body: (_ tick: Int64, _ mTickBeat: Double,
                                       _ onTime: Int64, _ offTime: Int64) -> Void) {
        let mStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        // floor, not ceil: a tick AT a column boundary sits between render windows — the previous
        // column's window rejects it (wrong column) and ceil would round past it, dropping the
        // column's first note. floor + the == dedup catches it once (fired slightly late, clamped).
        let firstTick = Int64((mStart / sub).rounded(.down))
        let lastT = Int64((mEnd / sub).rounded(.down))
        guard firstTick <= lastT else { return }

        for tick in firstTick...lastT {
            let mTickBeat = Double(tick) * sub
            // Which column is EFFECTIVE at this tick's step (lap-aware, §5b) — so a held column's ticks
            // fire during the current window even though the tick's TRUE column differs. With no lap,
            // lapColumn returns the tick's true column and this is the original `tickCol == effColumn`.
            let tickStep = Int((mTickBeat / S).rounded(.down))
            let tickTrueCol = ((tickStep % Snap.cols) + Snap.cols) % Snap.cols
            // PLAY: THIS CELL holds one column → its ticks fire EVERY window (decoupled from the timeline); normally
            // a tick fires only in its own effective column.
            if !forceColumnHold && lapColumn(laneMask: heldColumns, absoluteStep: tickStep, trueColumn: tickTrueCol) != effColumn { continue }
            if tick == lastTick[row] { continue }
            lastTick[row] = tick

            let onTime = sampleOf(musical: mTickBeat, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                  windowStart: windowStart, S: S, a: a)
            let colEnd = columnStart(mTickBeat, S) + S
            let mOff = min(mTickBeat + sub * gateFraction, colEnd)
            let offTime = sampleOf(musical: mOff, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                   windowStart: windowStart, S: S, a: a)
            body(tick, mTickBeat, onTime, offTime)
        }
    }

    // MARK: - the render-side pass

    func process(box: SnapshotBox,
                 pool: NotePool,
                 playing: Bool,
                 beatPos: Double,
                 tempo: Double,
                 sampleRate: Double,
                 timestampSample: Double,
                 frameCount: UInt32,
                 audition: Int = -1,
                 forceColumn: Int = -1,   // PLAY: THIS CELL — freeze the effective column here (isolated ungated play), −1 = normal
                 laneMask: UInt8 = 0,
                 velOverride: UInt32 = 0,
                 heldCell: Int = -1,
                 tapAltMask: UInt64 = 0,
                 tapMuteMask: UInt64 = 0,
                 soloCellMask: UInt64 = 0,
                 soloEmitterMask: UInt8 = 0,
                 soloReceiverMask: UInt8 = 0,
                 inputOctave: UInt32 = 0,
                 inputSemitone: UInt32 = 0,
                 inputVelOverride: UInt32 = 0,
                 emitterOctave: UInt32 = 0,
                 masterVelOverride: UInt8 = 0,
                 velKillMask: UInt8 = 0,
                 masterKill: Bool = false,
                 panic: Bool = false,
                 sceneFlush: Bool = false,
                 sceneRestart: Bool = false,
                 latchMask: UInt8 = 0,
                 latchedPools: [NotePool] = [],
                 preview: (active: Bool, colourIndex: Int, filter: Int, busMask: UInt8, inputRow: Int) = (false, -1, 0, 0, -1),
                 out: MIDIEmitter?,
                 diag: inout KernelDiag) {
        if pendingReset { pendingReset = false; performReset() }   // deferred reset — runs on the render thread (no race with the control-thread reset())
        self.tapAltMask = tapAltMask   // §9 item 1 ON TAP (unified ALT model): ephemeral per-cell alt flips
        self.tapMuteMask = tapMuteMask; self.soloEmitterMask = soloEmitterMask   // §9 item 1 ON TAP actions (4b)
        self.soloCellMask = soloCellMask           // EDIT "play this cell only" — silence every cell outside the set
        self.soloReceiverMask = soloReceiverMask   // receiver strip: additive input SOLO set (bits R1–R4)
        self.inputOctave = inputOctave             // receiver strip: per-receiver ±octave nudge
        self.inputSemitone = inputSemitone         // receiver strip: per-receiver ±semitone NOTE nudge
        self.inputVelOverride = inputVelOverride   // receiver strip: per-receiver input-velocity override
        self.emitterOctave = emitterOctave         // emitter strip: per-emitter output ±octave nudge
        self.masterVelOverride = masterVelOverride // master panel: the momentary master fader
        currentInputRecv = -1                      // set per-cell in the playing loops; −1 for preview/audition
        currentColourIndex = -1
        currentAlt = false
        self.latchMask = latchMask                 // receiver strip: which receivers read a frozen LATCH pool
        self.latchedPools = latchedPools
        self.receiverDisabledMask = box.receiverDisabledMask   // INPUT ENABLE: disabled doors block their cells' live read
        self.receiverChannels = box.receiverChannels; self.receiverCables = box.receiverCables   // BYPASS: per-receiver admission for the direct-injection pass
        self.receiverRangeLo = box.receiverRangeLo; self.receiverRangeHi = box.receiverRangeHi
        self.receiverBypassMask = box.receiverBypassMask; self.receiverBypassDest = box.receiverBypassDest

        busChannels = box.busChannels               // delta §7: per-bus stamp channels, this render
        heldColumns = laneMask                      // §5b lap: held column keys, this render
        busEnabledMask = box.busEnabledMask         // delta §6a: enabled emitters, this render
        // §4b THE FADER-KILL: a velocity fader at its BOTTOM = full silence (not vel-1). It folds into the
        // EFFECTIVE enabled mask, so the emission guard suppresses AND the enabled→disabled edge-close below
        // stops any sounding notes (the DJ fader-down). Master fader at the bottom kills every emitter. Ephemeral
        // (momentary, released → the bit restores → the emitter resumes), so it never touches the persisted toggle.
        busEnabledMask &= ~velKillMask
        if masterKill { busEnabledMask = 0 }
        self.velOverride = velOverride              // §6a PERFORM velocity override, this render
        claimMask = box.claimMask                   // §6a CLAIM v2: the claim mask, this render
        claimLeak = box.claimLeak                   // §6a CLAIM v2: per-claimant LEAK %, this render
        flattenMask = box.flattenMask               // role family: FLATTEN ducking set, this render
        flattenAmount = box.flattenAmount
        curveMask = box.curveMask                   // THE RACK CURVE: per-emitter velocity re-map set, this render
        curveAmount = box.curveAmount
        fenceMask = box.fenceMask                   // THE RACK FENCE: per-emitter note-range policy, this render
        fencePolicy = box.fencePolicy; fenceLo = box.fenceLo; fenceHi = box.fenceHi
        monoMask = box.monoMask                     // THE RACK MONO: per-emitter monophony set, this render
        monoPriority = box.monoPriority
        pocketMask = box.pocketMask                 // THE RACK POCKET: per-emitter timing shift, this render
        for b in 0..<4 { pocketSamples[b] = Int64((Double(box.pocketMs[b]) * sampleRate / 1000.0).rounded()) }
        convLead = Int(box.convLead)                // THE RACK CONVERSATION: lead + per-emitter stance, this render
        convStance = box.convStance
        altMask = box.altMask                       // role family: ALT turn-taking group, this render
        turnsPerNote = box.turnsPerNote             // TURNS mode: per-note exclusive vs per-moment
        rebuildAltSequence(box.altCount)
        masterKey = Int(box.masterKey)              // master panel: per-scene KEY + global MUTE, this render
        masterMute = box.masterMute

        // ---- window in samples; global (non-cell) timing ----
        let windowStart = Int64(timestampSample)
        renderStart = windowStart                   // POCKET: the earliest sample a pushed note may land on
        let windowEnd = windowStart + Int64(frameCount)

        // delta §6a: an emitter that just went enabled→disabled closes its sounding notes IMMEDIATELY
        // (own cable + its All copy; a shared-channel note survives on All via another enabled owner).
        if busEnabledMask != prevBusEnabledMask {
            let turnedOff = prevBusEnabledMask & ~busEnabledMask
            for bus: UInt8 in 0..<4 where turnedOff & (1 << bus) != 0 { closeBus(bus, atSample: windowStart, out: out) }
            prevBusEnabledMask = busEnabledMask
        }
        let beatsPerSample = tempo / 60.0 / sampleRate
        let swing = min(75, max(50, over(1, box.swing)))
        let a = swing / 50.0
        var S = box.stepBeats
        let srIdx = Int(over(0, -1).rounded())
        if srIdx >= 0 && srIdx < Snap.stepRateBeats.count { S = Snap.stepRateBeats[srIdx] }
        diag.effSwing = swing

        // ---- drain scheduled gate-offs that have come due (survive across renders → no stuck note
        //      when a voice's off falls beyond its opening window). Runs regardless of transport. ----
        drainDue(windowStart: windowStart, windowEnd: windowEnd, out: out)
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding
        diag.floodDropped = floodDropped              // FLOOD GOVERNOR: surface the session drop total to HEALTH

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0; lastGenStep[r] = Int64.min }
            prevEffColumn = -1
            altLastOnset = .min; altMomentIndex = -1     // role family ALT/TURNS: a fresh play restarts the rotation at the first member
            passAnchor = 0                               // MULTI-SCENE S2b: a fresh play is absolute (no restart offset)
            wasPlaying = playing
            clearEchoTails()                             // ECHO: transport start/stop kills tails (spec v1)
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide()   // MOD: reset the CC on transport edges
        }
        // master panel PANIC: the one hard flush — close every voice + reset the column state, hang-kit-logged.
        if panic {
            allNotesOff(atSample: renderSampleImmediate, out: out, includeBypass: true)   // the one hard flush — bypass included
            panicControllers(atSample: renderSampleImmediate, out: out)   // §3: CC120 + CC123 on every channel/cable
            prevEffColumn = -1
            diag.panics &+= 1
            clearEchoTails()                             // ECHO: panic drops every pending tail
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide()   // MOD: reset the CC on panic
        }
        // MULTI-SCENE scene SWITCH flush: close the OLD scene's sounding notes so the new scene (this render's
        // new snapshot generation) starts clean — a generation change alone doesn't flush. NOT hang-logged.
        if sceneFlush {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevEffColumn = -1
            clearEchoTails()                             // ECHO: scene-mortal — the old scene's tails die
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide()   // MOD: the old scene's CC state resets on the switch
        }
        // receiver strip LATCH edge: arming/disarming a receiver swaps the pool its subscribers read, so
        // close every voice and re-emit holds from the new effective pool (no stuck notes; on-edge re-strike).
        if latchMask != prevLatchMask {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevEffColumn = -1
            prevLatchMask = latchMask
            clearEchoTails()                             // ECHO: the pool swapped — drop tails from the old chord
        }

        pool.rebuildSorted()
        diag.poolCount = pool.count

        // BYPASS (§1/§2): the live direct-injection monitor — runs BEFORE the stopped/playing split so a bypassed
        // door sounds whether or not the transport rolls. (allNotesOff above skips bypass voices, so the edges don't
        // disturb them; only PANIC flushes them, and the next reconcile re-opens whatever's still held.)
        reconcileBypass(pool: pool, atSample: windowStart, out: out)

        // ---- PREVIEW / cell audition SOLO (Phase 2): the staged VIRTUAL cell renders ALONE. On the
        //      activation edge, flush every voice (entering = real cells go silent; leaving = they resume).
        //      STOPPED preview = arp of the source pool on the free clock (below); PLAYING preview = the
        //      virtual cell at the live column with the ROW-FEED (after effColumn, further down). ----
        if preview.active != prevPreviewActive {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            auditionStartSample = windowStart; auditionLastTick = -1
            for i in lastTick.indices { lastTick[i] = -1; lastGenStep[i] = Int64.min }      // free the solo row's tick-dedup
            previewPrevColumn = -1; strumProgress[0] = 0        // fresh column edge for the virtual cell
            prevPreviewActive = preview.active
        }

        // ---- AUDITION / stopped-PREVIEW (transport stopped) ----
        if !playing {
            if preview.active {
                previewStopped(colourIndex: preview.colourIndex, filter: preview.filter, busMask: preview.busMask,
                               box: box, pool: pool, tempo: tempo, sampleRate: sampleRate,
                               windowStart: windowStart, frameCount: frameCount, out: out, diag: &diag)
            } else {
                auditionRender(box: box, pool: pool, target: audition, tempo: tempo, sampleRate: sampleRate,
                               timestampSample: timestampSample, frameCount: frameCount, S: S, out: out, diag: &diag)
            }
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding
            return
        }
        prevAudition = -1   // playing ⇒ any audition was auto-released by the transport-start edge

        // MULTI-SCENE S2b RESTART-the-pass: capture the RAW beat as the anchor so THIS moment becomes column 0,
        // flush the old pass's voices + reset the tick phases (a self-switch; invariant 4). Then the WHOLE playing
        // clock shifts by `passAnchor` (0 ⇒ no shift ⇒ byte-identical normal play): musicalOf + sampleOf both take
        // the shifted `beatPos`, so columns/arp-phase/sample-timing restart together and land forward from NOW.
        if sceneRestart {
            passAnchor = beatPos
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevEffColumn = -1
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0; lastGenStep[r] = Int64.min }
            clearEchoTails()                             // ECHO: a pass restart drops the old pass's tails
        }
        let beatPos = beatPos - passAnchor

        // ---- derived column (§7). Musical space, so swing warps the beat→column map consistently
        //      with the arp ticks below. The COLUMN-SUBSET LAP (§5b) warps WHICH column is effective
        //      (held keys); the TRUE timeline — pass, passgate, swing — is unwarped (all off mNow). ----
        let mNow = musicalOf(beatPos, stepBeats: S, a: a)
        let govBeat = Int(beatPos.rounded(.down))                  // FLOOD GOVERNOR: reset the per-emitter budget each beat
        if govBeat != lastGovBeat { lastGovBeat = govBeat; for i in 0..<4 { noteOnsThisBeat[i] = 0 } }
        let cycleBeats = Double(Snap.cols) * S
        let posInCycle = mNow - (mNow / cycleBeats).rounded(.down) * cycleBeats
        let trueColumn = min(Snap.cols - 1, max(0, Int(posInCycle / S)))
        let absoluteStep = Int((mNow / S).rounded(.down))          // global step counter (derived)
        var effColumn = lapColumn(laneMask: heldColumns, absoluteStep: absoluteStep, trueColumn: trueColumn)
        forceColumnHold = forceColumn >= 0 && forceColumn < Snap.cols
        if forceColumnHold { effColumn = forceColumn }   // PLAY: THIS CELL — hold the soloed cell's column so its machine plays every window, ungated (user 2026-08-09)
        diag.effColumn = effColumn
        diag.absoluteStep = absoluteStep                           // LADDER commit signal: increments EACH step even during a column LAP (effColumn stays put)
        // STRUM re-fires only on a column transition (strumProgress). Under a HELD column (PLAY THIS MIDI CHAIN /
        // PLAY THIS CELL) the column never transitions, so a strum would sound ONCE then fall silent while arp/ratchet
        // loop. Re-arm strum each musical STEP so a held strum keeps sounding. (Paul 2026-08-15)
        if forceColumnHold { if absoluteStep != prevForcedStep { prevForcedStep = absoluteStep; for r in strumProgress.indices { strumProgress[r] = 0 } } }
        else { prevForcedStep = Int.min }
        diag.pass = Int((mNow / cycleBeats).rounded(.down))        // TRUE pass — never remapped (§5b)

        // PLAYING PREVIEW: the virtual cell renders SOLO at the live column — arp/ratchet/strum, with the
        // ROW-FEED (⇐ROW n reads that row's cell-at-effColumn by derivation) when the staged input is a row.
        if preview.active {
            previewPlaying(colourIndex: preview.colourIndex, filter: preview.filter, busMask: preview.busMask,
                           effColumn: effColumn, box: box, pool: pool,
                           beatPos: beatPos, windowBeats: Double(frameCount) * beatsPerSample, windowStart: windowStart,
                           windowEnd: windowEnd, beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats,
                           out: out, diag: &diag)
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding
            return
        }

        let active = topCell(in: effColumn, box)
        diag.activeCellRow = active?.row ?? -1
        diag.activeCellParent = active.map { box.cells[effColumn * Snap.rows + $0.row].resolvedParent } ?? -1
        // (the stopped case already returned via the audition branch above, so playing is true here)

        // ---- column transition (§7): active column changed → truncate all voices at the boundary
        //      (truncate-at-boundary tails), then emit the new column's HELD content once. A
        //      relocation/loop is the same edge, no special case. ----
        if effColumn != prevEffColumn {
            if anyVoiceActive() {
                let boundaryMusical = columnStart(mNow, S)     // start of effColumn
                let realB = realOf(boundaryMusical, stepBeats: S, a: a)
                let off = max(0, (realB - beatPos) / beatsPerSample)
                // §2 CONTINUITY: keep the legato drones alive across the boundary — emitColumnHolds reconciles
                // them (adopt the re-held, close the dropped). Everything else truncates here as before.
                closeExceptLegatoHolds(atSample: windowStart + Int64(off), out: out)
            }
            prevEffColumn = effColumn
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0; lastGenStep[r] = Int64.min }
            emitColumnHolds(box: box, column: effColumn, pool: pool, pass: diag.pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
            emitEchoColumn(box: box, column: effColumn, pool: pool, pass: diag.pass,   // ECHO: strike the dry + register the tail
                           S: S, a: a, tempo: tempo, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                           windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        } else if forceColumnHold {
            // PLAY: THIS CELL — the column is FROZEN, so the transition reconcile above fires only once (on engage).
            // Re-run the holds every window to SUSTAIN them: immortal identity/chance holds are adopted (not re-struck),
            // dropped notes close, and live/latch pool changes track. Without this a hold cell gates off after one
            // column and never re-strikes — silent, while the palette still shows its colour in the active column.
            emitColumnHolds(box: box, column: effColumn, pool: pool, pass: diag.pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, out: out, reconcileOnly: true, diag: &diag)
        } else if heldColumns != 0 && pool.count == 0 && latchMask == 0 && anyLegatoHold() {
            // AUDIT B2: a SINGLE-COLUMN lap pins effColumn, so the column-change reconcile above never fires — a
            // source release then strands the legato drone (immortal) until the ~1s Kernel self-heal (+ a spurious
            // panic count). Run the reconcile now: with an empty pool it re-holds nothing and closes every orphaned
            // drone at the boundary. Scoped to an active lap (heldColumns != 0) so normal playback is untouched.
            emitColumnHolds(box: box, column: effColumn, pool: pool, pass: diag.pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        }

        // ECHO tails ring out independent of the column and even after the source releases — BEFORE the empty-pool guard.
        drainEchoTails(mStart: mNow, mEnd: musicalOf(beatPos + Double(frameCount) * beatsPerSample, stepBeats: S, a: a),
                       beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, windowEnd: windowEnd,
                       S: S, a: a, out: out, diag: &diag)

        // THE MOD PROCESSOR: CC on the active column's MOD cells — BEFORE the pool guard (MOD needs no keys down).
        emitColumnMod(box: box, column: effColumn, pool: pool, beatPos: beatPos, windowBeats: Double(frameCount) * beatsPerSample,
                      beatsPerSample: beatsPerSample, windowStart: windowStart, out: out)
        // GLIDE: the mono sliding voices — before the pool guard (phrase-ends on an empty pool).
        emitColumnGlide(box: box, column: effColumn, pool: pool, beatPos: beatPos, windowBeats: Double(frameCount) * beatsPerSample,
                        beatsPerSample: beatsPerSample, windowStart: windowStart, out: out)

        guard pool.count > 0 || latchMask != 0 else {   // latch: a frozen pool drives the TICK (arp) cells with no keys down
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding; return
        }

        // ---- per-window TICK content: evaluate rows top-down so a fed cell reads its feeder's
        //      output (mirror model). ARP cells produce ticks; identity-fed cells mirror the feeder;
        //      identity-unfed cells have no tick content (their hold was emitted at the transition). ----
        for r in 0..<Snap.rows { articCount[r] = 0 }
        let windowBeats = Double(frameCount) * beatsPerSample

        for r in 0..<Snap.rows {
            let cell = box.cells[effColumn * Snap.rows + r]
            if cell.colourIndex < 0 || cellSoloedOut(effColumn, r) || (!cellSoloForced(effColumn, r) && (cell.muted || cell.dormant || tapMuted(effColumn, r))) { continue }   // §9 ON TAP = MUTE · LADDER dormant (PLAY: THIS CELL overrides both)
            if soloSilenced(cell) { continue }   // receiver strip: input SOLO excludes this cell's receiver
            currentInputRecv = cell.resolvedReceiver   // receiver strip: this cell's receiver, for the input-vel override
            currentColourIndex = cell.colourIndex      // item 4 marks: this cell's Colour, for the source tint
            currentCellIndex = effColumn * Snap.rows + r  // SEAL comet: this cell's grid index (the sounding column)
            let ci = Int(cell.colourIndex)
            let colour = box.colours[ci]
            if !onSceneAudible(colour.on, pass: diag.pass) { continue }   // §9 item 1 ON SCENE: not entered / exited
            // §9 item 1 ON HOLD (3a): while THIS cell is press-held, its ALT/OCT treatment overlays momentarily.
            let held = heldCell >= 0 && heldCell == effColumn * Snap.rows + r
            let transpose = colourTranspose(ci, colour)
                          + holdOctaveShift(on: colour.on, held: held)   // ON HOLD = OCT
                          + octaveShift(cell.resolvedReceiver)           // receiver strip: input OCT nudge
            // CELL MACHINE: the per-cell HEAD treatment (cell.proc) drives the render (morph + grid-chaining retired).
            var treat = colour; treat.a = cell.proc
            let mode = cellMode(type: effectiveType(treat), bypassed: cell.bypassed,
                                passMask: effectivePassMask(treat), pass: diag.pass)
            let emits = cell.busMask != 0   // fan-out across every lit bus happens inside emitArtic
            // DRONE = a legato chord-hold (user 2026-08-10): a SINGLE-SLOT drone sustains via emitColumnHolds (adopts
            // across adjacent drone columns, closes where no drone re-holds it), NOT the per-tick generator — skip it
            // here so it doesn't strike per step. A drone inside a multi-slot CHAIN keeps the generator path (v1).
            if mode == .drone && cell.procs.count <= 1 { continue }

            // CELL MACHINE stage-2: a covered chain (arp/ratchet/strum TAIL) runs the tail over the composed
            // upstream set; only the tail emits, and emitColumnHolds skips it.
            let driver = chainDriverIndex(cell)
            if driver >= 0 {
                let driveP = cell.procs[driver]                // the tick DRIVER (last tick-gen); slots before it compose, after it fold
                var treatDrive = colour; treatDrive.a = driveP
                // SPLIT downstream ([driver→SPLIT] = PUNCH HOLES): resolve its keep-window as NOTE bounds from the
                // driver's SOURCE POOL (the held chord), so each driven note outside the subset becomes a rest.
                splitGateActive = false
                if let si = downstreamSplitIndex(cell, after: driver) {
                    let ep = effectivePool(for: cell, live: pool)
                    let cnt = ep.srcCount(for: cell)
                    if cnt > 0 {
                        let sp = cell.procs[si]
                        let win = chordSplitWindow(count: cnt, split: sp.splitSet, noteAt: { Int(ep.srcAscending($0, for: cell)) })
                        if win.len > 0 {
                            splitGateLo = Int(ep.srcAscending(win.start, for: cell)); splitGateHi = Int(ep.srcAscending(win.start + win.len - 1, for: cell))
                        } else { splitGateLo = 1; splitGateHi = 0 }   // empty subset → nothing passes
                        splitGateVF = sp.splitVel.floor; splitGateVC = sp.splitVel.ceil
                        splitGateActive = true
                    }
                }
                switch driveP.type {
                case .arp:
                    emitArpRow(cell: cell, row: r, colour: treatDrive, transpose: transpose,
                               emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                               windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                               beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats,
                               chainDriver: driver, out: out, diag: &diag)
                case .ratchet:
                    emitRatchetRow(cell: cell, row: r, colour: treatDrive, transpose: transpose,
                                   emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                                   windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                                   beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats,
                                   chainDriver: driver, out: out, diag: &diag)
                case .strum:
                    emitStrumRow(cell: cell, row: r, colour: treatDrive, transpose: transpose, emits: emits,
                                 pool: pool, beatPos: beatPos, windowStart: windowStart, windowEnd: windowEnd,
                                 beatsPerSample: beatsPerSample, S: S, a: a, chainDriver: driver, out: out, diag: &diag)
                case .euclid, .burst, .cascade, .drone, .shift, .humanize:   // GENERATORS as chain drivers (user 2026-08-09)
                    let dm = cellMode(type: driveP.type, bypassed: false, passMask: driveP.passMask, pass: diag.pass)
                    emitGeneratorRow(mode: dm, cell: cell, row: r, colour: treatDrive, transpose: transpose, emits: emits,
                                     pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                                     windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                     S: S, a: a, cycleBeats: cycleBeats, chainDriver: driver, out: out, diag: &diag)
                case .weave:
                    emitWeaveRow(cell: cell, row: r, colour: treatDrive, transpose: transpose, emits: emits,
                                 pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                                 windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                 S: S, a: a, cycleBeats: cycleBeats, chainDriver: driver, out: out, diag: &diag)
                default: break
                }
                continue
            }
            if let li = composableLengthTailIndex(cell) {   // [<composable upstream> → LENGTH]: LENGTH re-articulates the composed set (no driver to fold it per-note)
                emitLengthComposedRow(cell: cell, row: r, colour: colour, transpose: transpose, emits: emits,
                                      lenIdx: li, pool: pool, beatPos: beatPos, windowBeats: windowBeats,
                                      windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                      S: S, a: a, out: out, diag: &diag)
                continue
            }
            if isHoldTailChain(cell) { continue }   // CELL MACHINE: a hold-tail chain emits at column boundaries (emitColumnHolds), not here

            switch mode {
            case .arp:
                emitArpRow(cell: cell, row: r, colour: treat, transpose: transpose,
                           emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                           windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                           beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .ratchet:
                emitRatchetRow(cell: cell, row: r, colour: treat, transpose: transpose,
                               emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                               windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                               beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .strum:
                emitStrumRow(cell: cell, row: r, colour: treat, transpose: transpose, emits: emits,
                             pool: pool, beatPos: beatPos, windowStart: windowStart, windowEnd: windowEnd,
                             beatsPerSample: beatsPerSample, S: S, a: a, out: out, diag: &diag)
            case .euclid, .burst, .cascade, .drone, .shift, .humanize:
                emitGeneratorRow(mode: mode, cell: cell, row: r, colour: treat, transpose: transpose, emits: emits,
                                 pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                                 windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                 S: S, a: a, out: out, diag: &diag)
            case .weave:
                emitWeaveRow(cell: cell, row: r, colour: treat, transpose: transpose, emits: emits,
                             pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                             windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                             S: S, a: a, out: out, diag: &diag)
            case .echo, .identity, .chance, .harmonize, .split:
                break   // echo's dry fired at the transition (repeats drain per-window); the hold types (incl. SPLIT filter) emit at the transition
            case .tutti:
                if treat.a.tuttiMode == .pattern {   // PATTERN re-articulates per slice here; COIN is a hold (emitColumnHolds)
                    emitTuttiPatternRow(cell: cell, row: r, colour: treat, transpose: transpose, emits: emits,
                                        pool: pool, beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                                        windowEnd: windowEnd, beatsPerSample: beatsPerSample, S: S, a: a, out: out, diag: &diag)
                }
            case .length:                          // standalone LENGTH re-articulates the held chord per the painted gate
                emitLengthRow(cell: cell, row: r, colour: treat, transpose: transpose, emits: emits,
                              pool: pool, beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                              windowEnd: windowEnd, beatsPerSample: beatsPerSample, S: S, a: a, out: out, diag: &diag)
            case .silent:
                break   // closed passgate → nothing this window
            }
        }
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding
    }

    // EXTERN side-rail (§7 READ AT SOURCE): the Kernel reports an incoming CC value into the store the MOD EXTERN
    // source reads + transforms. Never threads the note pipeline. CC121 (reset-all-controllers) clears it (Kernel).
    func setControllerIn(cc: Int, value: Int) {
        guard cc >= 0 && cc < 128 else { return }
        controllerIn[cc] = Int16(max(0, min(127, value)))
    }
    func clearControllerIn() { for i in controllerIn.indices { controllerIn[i] = -1 } }

    // MARK: - THE MOD PROCESSOR (CC generator, delta) — a beat-derived shaped CC on the active column's MOD cells.

    /// The unipolar [0,1] a MOD slot's SOURCE produces at beat `b` — SHAPE (LFO) · FOLLOW (sounding material) ·
    /// STEPS (8-step pattern) · STRIKE (per-entry AR) · EXTERN (incoming CC). Row-3 MIN/MAX maps it to a CC value.
    private func modSourceUnipolar(_ p: SnapParams, cell: SnapCell, pool: NotePool, b: Double, period: Double, column: Int) -> Double {
        switch p.modSource {
        case .shape:
            return modUnipolar(p.modShape, phase: b / period, column: column, cc: p.modCC, cycleIndex: Int((b / period).rounded(.down)))
        case .steps:
            return modStepsUnipolar(p.modSteps, phase: b / period, smooth: p.modSmooth)
        case .strike:
            return modStrikeUnipolar(t: b - modColumnEntryBeat, attack: p.modAttack, release: p.modRelease)
        case .follow:
            let src = effectivePool(for: cell, live: pool)
            let n = src.srcCount(for: cell)
            var sumN = 0.0, sumV = 0.0
            for k in 0..<n { let note = src.srcAscending(k, for: cell); sumN += Double(note); sumV += Double(src.velocity(note)) }
            return modFollowUnipolar(p.modFollow, count: n, meanNote: n > 0 ? sumN / Double(n) : 0, meanVel: n > 0 ? sumV / Double(n) : 0)
        case .extern:
            let raw = controllerIn[p.modExternCC & 127]                       // channel-agnostic v1
            return raw < 0 ? 0 : Double(raw) / 127.0                          // never seen → rest at 0
        }
    }

    /// Emit each active-column MOD slot's CC over this window at a control grid (block-size invariant, replay-safe),
    /// on every ENABLED bus's cable + All, on the bus's stamp channel. Runs BEFORE the held-note guard — MOD needs no
    /// keys down. When the playhead LEAVES a column, the departed column's MOD cells (modReset) send their default (0).
    private func emitColumnMod(box: SnapshotBox, column: Int, pool: NotePool, beatPos: Double, windowBeats: Double,
                               beatsPerSample: Double, windowStart: Int64, out: MIDIEmitter?) {
        if modLastColumn != Int32(column) {                       // LEAVE-DISPOSITION: reset the column we just left
            if modLastColumn >= 0 { emitModResets(box: box, column: Int(modLastColumn), atSample: windowStart, out: out) }
            modLastColumn = Int32(column)
            modColumnEntryBeat = beatPos                          // STRIKE: the AR envelope re-triggers on column entry
        }
        if masterMute && !previewMode { return }                  // master MUTE kills all output
        guard column >= 0 && column < Snap.cols else { return }
        let bEnd = beatPos + windowBeats
        for r in 0..<Snap.rows {
            let cell = box.cells[column * Snap.rows + r]
            if cell.colourIndex < 0 || cell.busMask == 0 || soloSilenced(cell) || cellSoloedOut(column, r) { continue }
            if !cellSoloForced(column, r) && (cell.muted || cell.dormant || tapMuted(column, r)) { continue }   // PLAY: THIS CELL overrides mute/dormant/tap
            for si in 0..<cell.procs.count where !cell.slotBypass[si] && cell.procs[si].type == .mod {
                let p = cell.procs[si]
                // TARGET CHANGED (the CC# knob swept): revert the ABANDONED cc to its STANDARD value so sweeping past
                // e.g. VOLUME (CC7) doesn't leave it knocked down. (user 2026-08-10.)
                let tkey = (column * Snap.rows + r) * 8 + si
                if tkey >= 0 && tkey < modPrevTarget.count {
                    let prev = Int(modPrevTarget[tkey])
                    if prev >= 0 && prev != p.modCC { emitModCC(cc: prev, value: ccDefault(prev), busMask: cell.busMask, atSample: windowStart, out: out) }
                    modPrevTarget[tkey] = Int16(p.modCC)
                }
                let period = max(0.03125, p.modRate.periodBeats)     // LFO / steps period, beats/cycle
                var k = Int((beatPos / modCtrlBeats).rounded(.up))    // control-grid points in [beatPos, bEnd)
                while Double(k) * modCtrlBeats < bEnd {
                    let b = Double(k) * modCtrlBeats
                    if b >= beatPos {
                        let s = modSourceUnipolar(p, cell: cell, pool: pool, b: b, period: period, column: column)
                        let value = modMap(s, min: p.modMin, max: p.modMax)
                        let sample = windowStart + Int64((((b - beatPos) / beatsPerSample)).rounded())
                        emitModCC(cc: p.modCC, value: value, busMask: cell.busMask, atSample: sample, out: out)
                    }
                    k += 1
                }
            }
        }
    }
    /// Reset every MOD cell in `column` whose modReset is ON to its default (0) — the CC-pollution guard. Stateless.
    private func emitModResets(box: SnapshotBox, column: Int, atSample: Int64, out: MIDIEmitter?) {
        guard column >= 0 && column < Snap.cols, !(masterMute && !previewMode) else { return }
        for r in 0..<Snap.rows {
            let cell = box.cells[column * Snap.rows + r]
            if cell.colourIndex < 0 || cell.busMask == 0 { continue }
            for si in 0..<cell.procs.count where !cell.slotBypass[si] && cell.procs[si].type == .mod && cell.procs[si].modReset {
                emitModCC(cc: cell.procs[si].modCC, value: cell.procs[si].modMin, busMask: cell.busMask, atSample: atSample, out: out)   // RESET → MIN
            }
        }
    }
    /// Transport/scene/panic flush: reset the last MOD column (leave-disposition) + forget the dedup state.
    private func flushMod(box: SnapshotBox, atSample: Int64, out: MIDIEmitter?) {
        if modLastColumn >= 0 { emitModResets(box: box, column: Int(modLastColumn), atSample: atSample, out: out) }
        modLastColumn = -1
        for i in modLastVal.indices { modLastVal[i] = -1 }
        for i in modPrevTarget.indices { modPrevTarget[i] = -1 }
    }
    /// Emit a CC on every ENABLED bus in `busMask` — the per-bus cable (bus+1) + All(0), on the bus's stamp channel.
    /// Deduped per (cable,ch,cc): a repeat of the same value is dropped so a held shape doesn't flood the wire.
    private func emitModCC(cc: Int, value: Int, busMask: UInt8, atSample: Int64, out: MIDIEmitter?) {
        guard let out, cc >= 0 && cc <= 127, value >= 0 && value <= 127 else { return }
        for bus in 0..<4 where bit(busMask, bus) && bit(busEnabledMask, bus) {
            if soloEmitterMask != 0 && !previewMode && !bit(soloEmitterMask, bus) { continue }
            let ch = (busChannels[bus] &- 1) & 15
            emitModCCWire(cable: UInt8(bus + 1), ch: ch, cc: cc, value: value, atSample: atSample, out: out)
            emitModCCWire(cable: 0,               ch: ch, cc: cc, value: value, atSample: atSample, out: out)   // §7b ALL cable
        }
    }
    @inline(__always)
    private func emitModCCWire(cable: UInt8, ch: UInt8, cc: Int, value: Int, atSample: Int64, out: MIDIEmitter) {
        let key = Int(cable) * 2048 + Int(ch) * 128 + cc
        if key >= 0 && key < modLastVal.count { if modLastVal[key] == Int16(value) { return }; modLastVal[key] = Int16(value) }
        out.emit(sampleTime: atSample, cable: cable, 0xB0 | ch, UInt8(cc), UInt8(value))
    }

    // MARK: - GLIDE (notes→pitch-bend translator) — one mono sliding voice per single-slot GLIDE cell (v1).

    private func emitBend(cable: UInt8, ch: UInt8, value: Int, atSample: Int64, out: MIDIEmitter?) {
        guard let out else { return }
        let v = max(0, min(16383, value))
        out.emit(sampleTime: atSample, cable: cable, 0xE0 | ch, UInt8(v & 0x7F), UInt8((v >> 7) & 0x7F))
    }
    /// End a GLIDE cell's phrase: close its anchor voice + centre the bend, and forget the voice.
    private func glidePhraseEnd(_ cellIdx: Int, atSample: Int64, out: MIDIEmitter?) {
        let gv = glideVoices[cellIdx]
        if gv.anchor >= 0 {
            if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: atSample, out: out) }
            if gv.bus >= 0 { emitBend(cable: UInt8(gv.bus + 1), ch: (busChannels[Int(gv.bus)] &- 1) & 15, value: 8192, atSample: atSample, out: out) }
        }
        glideVoices[cellIdx] = GlideVoice()
    }
    private func glidePhraseEndColumn(_ column: Int, atSample: Int64, out: MIDIEmitter?) {
        guard column >= 0 && column < Snap.cols else { return }
        for r in 0..<Snap.rows { glidePhraseEnd(column * Snap.rows + r, atSample: atSample, out: out) }
    }
    /// Transport/scene/panic flush: the immortal glide notes are closed by allNotesOff — just forget the state.
    private func flushGlide() { for i in glideVoices.indices { glideVoices[i] = GlideVoice() }; glideLastColumn = -1 }
    /// The mono input note (+velocity) a GLIDE cell tracks — by PRIORITY over its filtered source pool.
    private func glidePickPool(_ pool: NotePool, cell: SnapCell, priority: GlidePriority) -> (note: Int, vel: UInt8) {
        let n = pool.srcCount(for: cell)
        guard n > 0 else { return (-1, 0) }
        let note: UInt8
        switch priority {
        case .low:  note = pool.srcAscending(0, for: cell)
        case .high: note = pool.srcAscending(n - 1, for: cell)
        case .last: note = pool.srcPlayed(n - 1, filter: cell.inputChannel, cableMask: 0b1111)
        }
        return (Int(note), max(1, pool.velocity(note)))
    }
    /// Drive the mono glide voices for the active column's single-slot GLIDE cells: anchor on the first note, bend-ramp
    /// to each in-range target (else RE-ANCHOR / CLAMP), phrase-end on rest or column exit. Runs before the pool guard.
    private func emitColumnGlide(box: SnapshotBox, column: Int, pool: NotePool, beatPos: Double, windowBeats: Double,
                                 beatsPerSample: Double, windowStart: Int64, out: MIDIEmitter?) {
        if glideLastColumn != Int32(column) {                       // PHRASE END on column exit (spec)
            if glideLastColumn >= 0 { glidePhraseEndColumn(Int(glideLastColumn), atSample: windowStart, out: out) }
            glideLastColumn = Int32(column)
        }
        if masterMute && !previewMode { return }
        guard column >= 0 && column < Snap.cols else { return }
        let bEnd = beatPos + windowBeats
        for r in 0..<Snap.rows {
            let cellIdx = column * Snap.rows + r
            let cell = box.cells[cellIdx]
            // v1: SINGLE-SLOT GLIDE only ([ARP→GLIDE] is v2 — a chain with a note driver plays the driver, GLIDE ignored).
            guard cell.procs.count == 1, cell.procs[0].type == .glide, !cell.slotBypass[0] else { continue }
            if cell.colourIndex < 0 || cell.busMask == 0 || soloSilenced(cell) || cellSoloedOut(column, r)
               || (!cellSoloForced(column, r) && (cell.muted || cell.dormant || tapMuted(column, r))) {   // PLAY: THIS CELL overrides mute/dormant/tap
                glidePhraseEnd(cellIdx, atSample: windowStart, out: out); continue
            }
            let p = cell.procs[0]
            let ci = Int(cell.colourIndex); let colour = box.colours[ci]
            let transpose = colourTranspose(ci, colour) + octaveShift(cell.resolvedReceiver)
            let pick = glidePickPool(effectivePool(for: cell, live: pool), cell: cell, priority: p.glidePriority)
            guard pick.note >= 0 else { glidePhraseEnd(cellIdx, atSample: windowStart, out: out); continue }   // rest → phrase end
            let inNote = pick.note + transpose
            guard inNote >= 0 && inNote <= 127 else { continue }
            let bus = Int(cell.busMask.trailingZeroBitCount)
            let ch = (busChannels[bus] &- 1) & 15
            var gv = glideVoices[cellIdx]
            if gv.anchor < 0 {                                      // ANCHOR: first note = note-on + centred bend
                let slot = openVoice(note: UInt8(inNote), chan: ch, cable: UInt8(bus + 1), bus: UInt8(bus), onSample: windowStart, offSample: .max, velocity: pick.vel, out: out)
                gv = GlideVoice(); gv.anchor = Int16(inNote); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.lastInput = Int16(inNote); gv.rampStart = beatPos
                emitBend(cable: UInt8(bus + 1), ch: ch, value: 8192, atSample: windowStart, out: out); gv.lastBend14 = 8192
            } else if Int(gv.lastInput) != inNote {                 // NEW TARGET
                let semis = inNote - Int(gv.anchor)
                if p.glideReanchor && glideNeedsReanchor(target: inNote, anchor: Int(gv.anchor), range: p.glideRange) {
                    if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: windowStart, out: out) }
                    emitBend(cable: UInt8(bus + 1), ch: ch, value: 8192, atSample: windowStart, out: out)
                    let slot = openVoice(note: UInt8(inNote), chan: ch, cable: UInt8(bus + 1), bus: UInt8(bus), onSample: windowStart, offSample: .max, velocity: pick.vel, out: out)
                    gv.anchor = Int16(inNote); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.bendFrom = 0; gv.bendTo = 0; gv.rampStart = beatPos; gv.lastBend14 = 8192
                } else {                                            // GLIDE: capture the current bend, ramp to the new target (clamp if not re-anchoring)
                    let tt = max(0.0001, p.glideTime)
                    gv.bendFrom = gv.bendFrom + (gv.bendTo - gv.bendFrom) * min(1, p.glideTime > 0 ? (beatPos - gv.rampStart) / tt : 1)
                    gv.bendTo = p.glideReanchor ? Double(semis) : Double(max(-p.glideRange, min(p.glideRange, semis)))
                    gv.rampStart = beatPos
                }
                gv.lastInput = Int16(inNote)
            }
            let tt = max(0.0001, p.glideTime)                       // emit the bend ramp across this window (control grid, deduped)
            var k = Int((beatPos / modCtrlBeats).rounded(.up))
            while Double(k) * modCtrlBeats < bEnd {
                let b = Double(k) * modCtrlBeats
                if b >= beatPos {
                    let prog = p.glideTime > 0 ? min(1, (b - gv.rampStart) / tt) : 1
                    let v14 = glideBend14(semitones: gv.bendFrom + (gv.bendTo - gv.bendFrom) * prog, range: p.glideRange)
                    if gv.lastBend14 != Int16(v14) {
                        emitBend(cable: UInt8(gv.bus + 1), ch: ch, value: v14, atSample: windowStart + Int64(((b - beatPos) / beatsPerSample).rounded()), out: out)
                        gv.lastBend14 = Int16(v14)
                    }
                }
                k += 1
            }
            glideVoices[cellIdx] = gv
        }
    }

    // MARK: - GENERATORS (user 2026-08-08) — EUCLID · BURST · CASCADE, single-slot tick emitters. Each computes its
    // strike beats for the current column and emits those landing in this window (half-open, so each fires once).
    /// WEAVE (Paul 2026-08-07): the rank-clocked polyrhythm DRIVER. Each held note (ascending rank) ticks on its OWN
    /// clock — `weaveRate(mode, base, rank)` — so one chord becomes an interlocking ensemble (bass slow … top fast).
    /// Modelled on emitGeneratorRow: compose the source at colStart, then window-scan EACH rank's clock from colStart
    /// (RETRIG for free; no shared per-row tick state, so per-rank scans don't collide). SPAN ranks weave; extras join
    /// the top (fastest weaving) clock. As a chain driver each struck note folds downstream via emitDriverNote.
    private func emitWeaveRow(cell: SnapCell, row r: Int, colour: SnapColour, transpose: Int,
                              emits: Bool, pool livePool: NotePool, effColumn: Int, beatPos: Double, windowBeats: Double,
                              windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                              cycleBeats: Double = 0, chainDriver: Int = -1, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard S > 0 else { return }
        let pool = effectivePool(for: cell, live: livePool)   // receiver LATCH: the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)
        let p = colour.a
        let cyc = cycleBeats > 0 ? cycleBeats : Double(Snap.cols) * S
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let colStart = columnStart(mWinStart, S), colEnd = colStart + S
        let hasDownstream = chainDriver >= 0 && chainDriver < cell.procs.count - 1
        var srcNotes: [(note: Int, vel: UInt8)] = []
        if chainDriver > 0 {
            composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: colStart, S: S, cycleBeats: cyc)
            for k in 0..<chainScratch.srcCount(filter: 0, cableMask: 0b1111) { let n = chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111); srcNotes.append((Int(n), chainScratch.velocity(n))) }
        } else {
            for k in 0..<pool.srcCount(for: cell) { let n = pool.srcAscending(k, for: cell); srcNotes.append((Int(n), pool.velocity(n))) }
        }
        let count = srcNotes.count
        guard count > 0 else { return }
        let span = max(1, min(count, p.weaveSpan))
        let gateFrac = max(0.05, min(1.0, p.gate))
        // PHASE → the clock origin. RETRIG restarts each column (off capped at the boundary); FREE runs the global grid;
        // LEGATO flows from the run's first column. EUCLID is a per-column cycle, so it's always RETRIG.
        let phase: ArpPhase = (p.weaveMode == .euclid) ? .retrig : p.weavePhase
        let origin: Double, capAtCol: Bool
        switch phase {
        case .retrig: origin = colStart; capAtCol = true
        case .free:   origin = 0;        capAtCol = false
        case .legato:
            let passStart = (colStart / cyc).rounded(.down) * cyc
            let rs = cell.runStartColumn >= 0 ? Int(cell.runStartColumn) : Int(((colStart - passStart) / S).rounded(.down))
            origin = passStart + Double(rs) * S; capAtCol = false
        }
        for rank in 0..<count {
            let clockRank = min(rank, span - 1)   // extras join the top clock
            let n = srcNotes[rank].note + transpose
            guard n >= 0 && n <= 127 else { continue }
            let vel = srcNotes[rank].vel
            if p.weaveMode == .euclid {            // each rank plays an interlocking euclidean pattern (bass sparse → top dense)
                let M = max(2, min(16, p.weaveEuclidSteps))
                let pat = euclidPattern(pulses: max(1, min(M, 2 * clockRank + 1)), steps: M, rotation: 0)
                let sub = S / Double(M)
                for stepI in 0..<M where pat[stepI] {
                    let tau = colStart + Double(stepI) * sub
                    guard tau >= mWinStart && tau < mWinEnd else { continue }
                    emitWeaveStrike(cell: cell, row: r, note: n, vel: vel, tau: tau, off: min(colEnd, tau + sub * gateFrac), bm: bm,
                                    emits: emits, hasDownstream: hasDownstream, chainDriver: chainDriver, windowEnd: windowEnd,
                                    beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a, cyc: cyc, out: out, diag: &diag)
                }
            } else {                               // a regular per-rank clock (LADDER/HARMONIC formula, or DRAWN's authored rate)
                let sub = (p.weaveMode == .drawn) ? max(0.03125, p.weaveDrawnBeats[min(clockRank, p.weaveDrawnBeats.count - 1)])
                                                  : weaveRate(mode: p.weaveMode, baseBeats: max(0.03125, p.weaveBaseBeats), rank: clockRank)
                let scanEnd = capAtCol ? min(mWinEnd, colEnd) : mWinEnd
                var j = Int(((mWinStart - origin) / sub).rounded(.down)); if j < 0 { j = 0 }
                while true {
                    let tau = origin + Double(j) * sub
                    if tau >= scanEnd { break }
                    j += 1
                    guard tau >= mWinStart else { continue }
                    let off = capAtCol ? min(colEnd, tau + sub * gateFrac) : (tau + sub * gateFrac)
                    emitWeaveStrike(cell: cell, row: r, note: n, vel: vel, tau: tau, off: off, bm: bm,
                                    emits: emits, hasDownstream: hasDownstream, chainDriver: chainDriver, windowEnd: windowEnd,
                                    beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a, cyc: cyc, out: out, diag: &diag)
                }
            }
        }
    }

    /// One WEAVE strike: convert the musical on/off to samples, store the seal artic, and emit (folding downstream when
    /// chained, else direct). A method (not a nested closure) so it can take `diag` inout cleanly.
    private func emitWeaveStrike(cell: SnapCell, row r: Int, note n: Int, vel: UInt8, tau: Double, off: Double, bm: UInt8,
                                 emits: Bool, hasDownstream: Bool, chainDriver: Int, windowEnd: Int64, beatPos: Double,
                                 beatsPerSample: Double, windowStart: Int64, S: Double, a: Double, cyc: Double,
                                 out: MIDIEmitter?, diag: inout KernelDiag) {
        let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        let offT = sampleOf(musical: off, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        let tbm = chopMask(cell, m: tau, S: S, base: bm)
        storeArtic(row: r, on: onT, off: offT, note: UInt8(n), beat: tau)
        if !emits { return }
        if hasDownstream {
            emitDriverNote(n, cell: cell, driver: chainDriver, bm: bm, onSample: onT, offSample: offT, windowEnd: windowEnd,
                           velocity: max(1, vel), m: tau, S: S, cycleBeats: cyc, beatsPerSample: beatsPerSample, pass: diag.pass, out: out, diag: &diag)
        } else if tbm != 0 {
            emitArtic(note: UInt8(n), busMask: tbm, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: max(1, vel), out: out, diag: &diag)
        }
    }

    private func emitGeneratorRow(mode: CellMode, cell: SnapCell, row r: Int, colour: SnapColour, transpose: Int,
                                  emits: Bool, pool livePool: NotePool, effColumn: Int, beatPos: Double, windowBeats: Double,
                                  windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                                  cycleBeats: Double = 0, chainDriver: Int = -1, out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: livePool)   // receiver LATCH: the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)
        let p = colour.a
        let cyc = cycleBeats > 0 ? cycleBeats : Double(Snap.cols) * S
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let colStart = columnStart(mWinStart, S)

        // CELL MACHINE: as a chain DRIVER, the source is the composed set of the stages BEFORE the driver; each note
        // FOLDS through the stages AFTER it (emitDriverNote). A single-slot generator (chainDriver < 0) reads the
        // cell's filtered pool directly and emits with emitArtic. `srcNotes` = the raw source notes (transpose added
        // per-strike). Composed once at colStart — the source is stable across the column.
        let hasDownstream = chainDriver >= 0 && chainDriver < cell.procs.count - 1
        var srcNotes: [(note: Int, vel: UInt8)] = []   // each source note carries its VELOCITY (user 2026-08-09: generators inherit it)
        if chainDriver > 0 {
            composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: colStart, S: S, cycleBeats: cyc)
            for k in 0..<chainScratch.srcCount(filter: 0, cableMask: 0b1111) { let n = chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111); srcNotes.append((Int(n), chainScratch.velocity(n))) }
        } else {
            for k in 0..<pool.srcCount(for: cell) { let n = pool.srcAscending(k, for: cell); srcNotes.append((Int(n), pool.velocity(n))) }
        }

        // ONE chord strike at musical beat `tau` (source notes, chop-routed / downstream-folded), gated `gateBeats`.
        // `velScale` is the generator's per-strike envelope level (0…1) RELATIVE to each note's inherited source
        // velocity — so a soft chord bursts soft, a hard one bursts hard (user 2026-08-09).
        func strikeChord(tau: Double, velScale: Double, gateBeats: Double, onlyIndex: Int? = nil) {
            let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            let offT = sampleOf(musical: tau + gateBeats, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            let tbm = chopMask(cell, m: tau, S: S, base: bm)
            for (k, sn) in srcNotes.enumerated() {
                if let only = onlyIndex, k != only { continue }
                let n = sn.note + transpose
                guard n >= 0 && n <= 127 else { continue }
                let vel = UInt8(max(1, min(127, Int((Double(max(1, sn.vel)) * velScale).rounded()))))   // inherited velocity × envelope
                storeArtic(row: r, on: onT, off: offT, note: UInt8(n), beat: tau)
                if !emits { continue }
                if hasDownstream {   // fold the post-driver stages onto each generated note (a downstream passgate/harmonize/…)
                    emitDriverNote(n, cell: cell, driver: chainDriver, bm: bm, onSample: onT, offSample: offT,
                                   windowEnd: windowEnd, velocity: vel, m: tau, S: S, cycleBeats: cyc, beatsPerSample: beatsPerSample, pass: diag.pass, out: out, diag: &diag)
                } else if tbm != 0 {
                    emitArtic(note: UInt8(n), busMask: tbm, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        }
        // A window-scan generator's FIRST window in each column scans from colStart (not mWinStart) so the DOWNBEAT
        // strike — and any pulse in [colStart, mWinStart), emit-late/clamped to the block start — fires once, instead
        // of being dropped because the boundary-crossing block still rendered the previous column. lastGenStep dedups
        // per row so later windows in the same column don't re-emit. (EUCLID takes the iterateTicks path and ignores
        // this.) The absolute column-step is monotonic, so each column occurrence (incl. every lap) catches its own
        // downbeat. (Paul 2026-08-18)
        let curGenStep = Int64((columnStart(mWinStart, S) / S).rounded())
        let scanFrom = (curGenStep != lastGenStep[r]) ? colStart : mWinStart
        lastGenStep[r] = curGenStep
        func inWindow(_ tau: Double) -> Bool { tau >= scanFrom && tau < mWinEnd }

        switch mode {
        case .euclid:
            let n = max(2, min(16, p.euclidSteps))
            let k = p.euclidPulsesFromPool ? srcNotes.count : p.euclidPulses   // POOL: K = held-note count (composed set if chained)
            let pat = euclidPattern(pulses: k, steps: n, rotation: p.euclidRot)
            // SPAN: CELL fits N steps in one column (repeats each column); ROW stretches the SAME N steps across the
            // whole bar (a cross-column phrase). Only `sub` changes — the column gate below keeps each cell voicing
            // only the pulses that fall in its own column, so a euclid on a full row plays as one phrase. (Paul 2026-08-18)
            let sub = (p.euclidSpan == .row ? cyc : S) / Double(n)
            // Emit via iterateTicks (like the ARP) instead of a window-scan: its floor + per-row dedup CATCHES the
            // downbeat pulse (step 0, sitting exactly on the column boundary) that the old `tau >= mWinStart` scan
            // dropped whenever a render block didn't begin precisely on the boundary — i.e. almost always, so every
            // EUCLID lost its downbeat (K→K−1; K=1 = silent). The column gate keeps a cell's pulses in ITS column, so
            // it never reaches into the next one. (Paul 2026-08-18)
            iterateTicks(row: r, effColumn: effColumn, sub: sub, gateFraction: 0.9,
                         beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                         beatsPerSample: beatsPerSample, S: S, a: a) { tick, mTickBeat, _, _ in
                let step = Int(((tick % Int64(n)) + Int64(n)) % Int64(n))
                if pat[step] { strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: min(sub * 0.9, S * 0.9)) }
            }
        case .burst:
            let count = Int(max(2, min(16, p.count)))
            let fracs = burstFractions(count: count, curve: p.curve)
            let minGap = S / Double(count) * 0.9
            for (i, f) in fracs.enumerated() {
                let tau = colStart + f * S
                if inWindow(tau) {
                    let velScale = max(0.05, Double(100 - i * (60 / max(1, count))) / 100.0)   // fade across the roll (relative)
                    strikeChord(tau: tau, velScale: velScale, gateBeats: minGap)
                }
            }
        case .cascade:
            let sub = Snap.arpRateBeats[Int(max(0, min(Int8(Snap.arpRateBeats.count - 1), p.rateIndex)))]
            guard sub > 0 else { break }
            let srcN = srcNotes.count
            for j in 0..<srcN {                                   // reveal note j at tick j, HELD to the boundary (accumulating)
                let tau = colStart + Double(j) * sub
                if tau >= colStart + S { break }                  // ran past the column — the rest reveal next entry
                if inWindow(tau) {
                    let idx = p.strumDir == .down ? (srcN - 1 - j) : j   // reveal order (UP default · DOWN top-first)
                    let gate = (colStart + S) - tau                // sustain to the column boundary
                    strikeChord(tau: tau, velScale: 1.0, gateBeats: max(0.01, gate), onlyIndex: idx)
                }
            }
        case .drone:
            // PAD: strike the whole entry chord ONCE, held to the boundary; the GATE knob scales the inherited velocity.
            if inWindow(colStart) {
                strikeChord(tau: colStart, velScale: max(0.05, min(1, p.gate)), gateBeats: S)
            }
        case .shift:
            // GROOVE: push the chord's onset LATE by up to ~40% of the step (spread 0…1), held to the boundary.
            let push = max(0, min(1, p.spread)) * 0.4 * S
            let tau = colStart + push
            if inWindow(tau) { strikeChord(tau: tau, velScale: 1.0, gateBeats: max(0.05, S - push)) }
        case .humanize:
            // THE DETERMINISTIC HUMAN: each note strikes at a seeded late offset (0…~15% step) with a seeded velocity
            // duck — replay-safe (seed = column · note · index). AMOUNT (spread) scales both. Held to the boundary.
            // The duck is RELATIVE, so it ducks the inherited source velocity (user 2026-08-09).
            let amt = max(0, min(1, p.spread))
            let col = UInt64(bitPattern: Int64((colStart / S).rounded()))
            for (k, sn) in srcNotes.enumerated() {
                let note = sn.note + transpose
                guard note >= 0 && note <= 127 else { continue }
                let h = splitmix64Mix(col &* 2_654_435_761 &+ UInt64(note) &* 131 &+ UInt64(k) &* 17)
                let tFrac = Double(h & 0xFFFF) / 65535.0                     // 0…1 → late offset
                let vFrac = Double((h >> 16) & 0xFFFF) / 65535.0             // 0…1 → velocity duck
                let tau = colStart + tFrac * amt * 0.15 * S
                let velScale = max(0.05, (100.0 - vFrac * amt * 45.0) / 100.0)
                if inWindow(tau) { strikeChord(tau: tau, velScale: velScale, gateBeats: max(0.05, colStart + S - tau), onlyIndex: k) }
            }
        default:
            break
        }
    }

    // MARK: - CELL MACHINE (feat/EditPageSpike) stage-2 — the serial chain feed

    /// The chain's TICK DRIVER — the index of the LAST non-bypassed rhythm-generating slot (arp/ratchet/strum + the
    /// generators euclid/burst/cascade/drone/shift/humanize, user 2026-08-09). It sets the rhythm: slots BEFORE it
    /// compose as its source; slots AFTER it FOLD onto each note it emits (a per-tick hold — a passgate gates the
    /// pass, chance drops, harmonize expands). -1 = no tick generator (a hold/plain cell). This is what makes
    /// `[arp → passgate]` or `[euclid → harmonize]` keep generating (the driver drives, the tail folds).
    private func chainDriverIndex(_ cell: SnapCell) -> Int {
        guard cell.procs.count >= 2 else { return -1 }
        var i = cell.procs.count - 1
        while i >= 0 {
            if !cell.slotBypass[i] && isDriverType(cell.procs[i].type) { return i }
            i -= 1
        }
        return -1
    }
    /// The LAST non-bypassed SPLIT slot after `driver` (last-writer wins), or nil.
    private func downstreamSplitIndex(_ cell: SnapCell, after driver: Int) -> Int? {
        var found: Int? = nil, j = driver + 1
        while j < cell.procs.count { if !cell.slotBypass[j] && cell.procs[j].type == .split { found = j }; j += 1 }
        return found
    }
    private func isDriverType(_ t: ProcessorType) -> Bool {
        switch t {
        case .arp, .ratchet, .strum, .euclid, .burst, .cascade, .drone, .shift, .humanize, .weave: return true
        default: return false
        }
    }
    private func isCoveredChain(_ cell: SnapCell) -> Bool { chainDriverIndex(cell) >= 0 }
    /// A multi-slot chain whose TAIL holds at column boundaries via `emitColumnHolds` (holding the tail's
    /// transform of the composed upstream set): a bypassed tail (passthrough of the upstream set), or a
    /// gate/chance/harmonize tail. A non-bypassed STRUM tail is NOT covered yet → falls back to head-only.
    private func isHoldTailChain(_ cell: SnapCell) -> Bool {
        guard cell.procs.count >= 2, let last = cell.procs.last else { return false }
        if cell.slotBypass.last ?? false { return true }                 // bypassed tail = held passthrough
        switch last.type {
        case .passgate, .chance, .harmonize: return true
        case .split: return true                                         // SPLIT tail = a set-membership FILTER over the composed hold ([HARMONIZE → SPLIT] keeps a subset)
        case .tutti: return last.tuttiMode == .coin                      // TUTTI COIN tail = a per-step SET roll over the composed hold; PATTERN re-articulates (tick loop)
        default: return false
        }
    }
    /// A NO-DRIVER chain whose last non-bypassed slot is LENGTH, sitting after a composable (hold) upstream —
    /// `[TUTTI COIN → LENGTH]`, `[HARMONIZE → LENGTH]`, `[CHANCE → LENGTH]`, `[SPLIT → LENGTH]`, `[PASSGATE → LENGTH]`.
    /// Returns the LENGTH slot index; such a cell re-articulates its composed upstream set through LENGTH's gate
    /// (emitLengthComposedRow), so BOTH the standalone tick-loop switch and emitColumnHolds must defer to it. LENGTH
    /// re-articulates, so it can't be a plain hold-tail (isHoldTailChain). A TUTTI-PATTERN head is EXCLUDED —
    /// emitTuttiPatternRow already folds a downstream LENGTH per slice, preserving PATTERN's own rhythm. (Paul 2026-08-17)
    private func composableLengthTailIndex(_ cell: SnapCell) -> Int? {
        guard chainDriverIndex(cell) < 0 else { return nil }             // a driver already folds LENGTH per-note (emitDriverNote)
        var last = -1, i = cell.procs.count - 1
        while i >= 0 { if !cell.slotBypass[i] { last = i; break }; i -= 1 }
        guard last >= 1, cell.procs[last].type == .length else { return nil }
        var head = -1, h = 0
        while h < cell.procs.count { if !cell.slotBypass[h] { head = h; break }; h += 1 }
        if head >= 0, head != last, cell.procs[head].type == .tutti, cell.procs[head].tuttiMode == .pattern { return nil }
        var hasUpstream = false, k = 0
        while k < last { if !cell.slotBypass[k] && cell.procs[k].type != .length { hasUpstream = true; break }; k += 1 }
        return hasUpstream ? last : nil
    }
    /// A cell whose chain TAIL is ECHO and is NOT tick-driven: single-slot `[ECHO]`, or a hold-upstream chain like
    /// `[PASSGATE→ECHO]` / `[HARMONIZE→ECHO]`. `emitEchoColumn` registers its tail from the composed upstream set;
    /// `emitColumnHolds` + the tick loop leave it alone. (An `[ARP→ECHO]` tick echo stays Phase-2 — isCoveredChain.)
    private func isEchoTail(_ cell: SnapCell) -> Bool {
        guard !isCoveredChain(cell), let last = cell.procs.last, !(cell.slotBypass.last ?? false) else { return false }
        return last.type == .echo
    }
    /// The first non-bypassed ECHO slot's params in a chain, or nil — for registering echo tails when echo is an
    /// EARLIER slot of a hold-tail chain (e.g. [ECHO→HARMONIZE]), which the tail/driver echo paths don't cover.
    private func chainEchoParams(_ cell: SnapCell) -> SnapParams? {
        for i in 0..<cell.procs.count where !cell.slotBypass[i] && cell.procs[i].type == .echo { return cell.procs[i] }
        return nil
    }

    /// TUTTI PATTERN (standalone): render the held set as an authored SHAPE per slice, clocked at the slice rate — a
    /// per-slice re-articulator. TUTTI is not a driver; only a single-slot PATTERN cell reaches here (a chain routes
    /// its driver/hold instead). The 8-slice pattern walks GLOBALLY (ROTATE offsets it) so it strides the bar. No stuck
    /// notes: every strike carries an explicit off sample through emitArtic, the same lifecycle the generators use.
    private func emitTuttiPatternRow(cell: SnapCell, row r: Int, colour: SnapColour, transpose: Int, emits: Bool,
                                     pool: NotePool, beatPos: Double, windowBeats: Double, windowStart: Int64,
                                     windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                                     out: MIDIEmitter?, diag: inout KernelDiag) {
        let p = colour.a
        let sub = max(0.03125, p.tuttiSliceBeats)
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        var srcNotes: [(note: Int, vel: UInt8)] = []
        for k in 0..<pool.srcCount(for: cell) { let n = pool.srcAscending(k, for: cell); srcNotes.append((Int(n), pool.velocity(n))) }
        let count = srcNotes.count
        guard count > 0 else { return }
        // [TUTTI PATTERN → LENGTH]: TUTTI PATTERN isn't a note-DRIVER, so a downstream LENGTH never reached the
        // per-note fold (emitDriverNote) — it was silently dropped. Resolve the last non-bypassed LENGTH after the
        // head here and fold its gate onto each slice hit below (same MUTE-drops / PASS-keeps / SHORT·LONG-override
        // rule as emitDriverNote). (Paul 2026-08-17)
        var lenP: SnapParams? = nil
        var lj = 1
        while lj < cell.procs.count { if !cell.slotBypass[lj] && cell.procs[lj].type == .length { lenP = cell.procs[lj] }; lj += 1 }
        let gStart = Int((mWinStart / sub).rounded(.down)), gEnd = Int((mWinEnd / sub).rounded(.down))
        guard gEnd >= gStart else { return }
        for g in gStart...gEnd {
            let tau = Double(g) * sub
            guard tau >= mWinStart && tau < mWinEnd else { continue }
            let idx = (((g + p.tuttiRotate) % 8) + 8) % 8
            let (ranks, oct) = tuttiSliceRanks(idx < p.tuttiSlices.count ? p.tuttiSlices[idx] : .all, count: count)
            guard !ranks.isEmpty else { continue }                 // REST → silent slice
            var offBeat = tau + sub * 0.9                           // TUTTI's own ~90%-of-slice gate
            if let lp = lenP {                                     // downstream LENGTH overrides THIS slice's gate
                let sIdx = ((chopSlice(tau, columnBeats: S) + lp.lenRotate) % 8 + 8) % 8
                let st = sIdx < lp.lenSlices.count ? lp.lenSlices[sIdx] : .pass
                switch lengthGateFor(st, onset: tau, shortFrac: lp.lenShort, longFrac: lp.lenLong, S: S) {
                case .drop:                continue                 // MUTE → the slice rests
                case .keep:                break                    // PASS → keep TUTTI's own gate
                case .overrideOff(let ob): offBeat = ob             // SHORT/LONG → capped at the step end
                }
            }
            let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            let offT = sampleOf(musical: offBeat, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            let tbm = chopMask(cell, m: tau, S: S, base: bm)
            for rank in ranks where rank >= 0 && rank < count {
                let n = srcNotes[rank].note + transpose + oct
                guard n >= 0 && n <= 127 else { continue }
                storeArtic(row: r, on: onT, off: offT, note: UInt8(n), beat: tau)
                if emits && tbm != 0 { emitArtic(note: UInt8(n), busMask: tbm, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: max(1, srcNotes[rank].vel), out: out, diag: &diag) }
            }
        }
    }

    /// LENGTH (standalone): re-articulate the held chord per the painted 8-slice gate. Events (on/off beats) are the
    /// pure `lengthColumnEvents` (PASS ties, MUTE rests + cuts, SHORT staccato, LONG rings) — this just strikes ALL
    /// source notes at each event with its off. Not a driver; single-slot LENGTH reaches here via the tick loop.
    /// No stuck notes: finite offs capped at the step end, through the same emitArtic lifecycle the generators use.
    private func emitLengthRow(cell: SnapCell, row r: Int, colour: SnapColour, transpose: Int, emits: Bool,
                               pool: NotePool, beatPos: Double, windowBeats: Double, windowStart: Int64,
                               windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                               out: MIDIEmitter?, diag: inout KernelDiag) {
        guard S > 0 else { return }
        let p = colour.a
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        var srcNotes: [(note: Int, vel: UInt8)] = []
        for k in 0..<pool.srcCount(for: cell) { let n = pool.srcAscending(k, for: cell); srcNotes.append((Int(n), pool.velocity(n))) }
        guard !srcNotes.isEmpty else { return }
        var col = columnStart(mWinStart, S)
        while col < mWinEnd {
            let events = lengthColumnEvents(slices: p.lenSlices, rotate: p.lenRotate, shortFrac: p.lenShort, longFrac: p.lenLong, colStart: col, S: S)
            for e in events where e.on >= mWinStart && e.on < mWinEnd {
                let onT = sampleOf(musical: e.on, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                let offT = sampleOf(musical: e.off, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                let tbm = chopMask(cell, m: e.on, S: S, base: bm)
                for sn in srcNotes {
                    let n = sn.note + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    storeArtic(row: r, on: onT, off: offT, note: UInt8(n), beat: e.on)
                    if emits && tbm != 0 { emitArtic(note: UInt8(n), busMask: tbm, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: max(1, sn.vel), out: out, diag: &diag) }
                }
            }
            col += S
        }
    }

    /// LENGTH after a non-driver, composable upstream — `[TUTTI COIN → LENGTH]`, `[HARMONIZE → LENGTH]`,
    /// `[CHANCE → LENGTH]`, `[SPLIT → LENGTH]`, `[PASSGATE → LENGTH]`. LENGTH isn't a note-DRIVER, so its gate never
    /// reached the per-note fold (emitDriverNote) and was silently dropped. Re-articulate the COMPOSED upstream set
    /// (composeChainSet up to the slot before LENGTH) through LENGTH's 8-slice gate — recomposed at each column start
    /// so per-step-seeded upstreams (TUTTI COIN / CHANCE) stay loop-consistent. Same emitArtic lifecycle + step-capped
    /// offs as emitLengthRow → no stuck notes. (Paul 2026-08-17)
    private func emitLengthComposedRow(cell: SnapCell, row r: Int, colour: SnapColour, transpose: Int, emits: Bool,
                                       lenIdx: Int, pool: NotePool, beatPos: Double, windowBeats: Double,
                                       windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double,
                                       a: Double, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard S > 0, lenIdx >= 1, lenIdx < cell.procs.count else { return }
        let lp = cell.procs[lenIdx]
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let cellPool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: frozen chord if armed
        let cycleBeats = Double(Snap.cols) * S
        var col = columnStart(mWinStart, S)
        while col < mWinEnd {
            composeChainSet(cell: cell, pool: cellPool, upto: lenIdx - 1, m: col, S: S, cycleBeats: cycleBeats)   // the upstream set at this column
            let cnt = chainScratch.srcCount(filter: 0, cableMask: 0b1111)
            if cnt > 0 {
                let events = lengthColumnEvents(slices: lp.lenSlices, rotate: lp.lenRotate, shortFrac: lp.lenShort, longFrac: lp.lenLong, colStart: col, S: S)
                for e in events where e.on >= mWinStart && e.on < mWinEnd {
                    let onT = sampleOf(musical: e.on, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    let offT = sampleOf(musical: e.off, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    let tbm = chopMask(cell, m: e.on, S: S, base: bm)
                    for k in 0..<cnt {
                        let src = chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111)
                        let n = Int(src) + transpose
                        guard n >= 0 && n <= 127 else { continue }
                        let v = max(1, chainScratch.velocity(src))
                        storeArtic(row: r, on: onT, off: offT, note: UInt8(n), beat: e.on)
                        if emits && tbm != 0 { emitArtic(note: UInt8(n), busMask: tbm, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: v, out: out, diag: &diag) }
                    }
                }
            }
            col += S
        }
    }

    /// Transform note set `src` → `dst` (dst pre-reset) by ONE stage at beat m — a pure, window-independent
    /// derivation: identity/gate/ratchet/strum pass the set, a closed gate empties it, chance drops by
    /// probability, harmonize expands to voices, an ARP mid-chain collapses the set to its one note at m.
    private func applyStage(_ p: SnapParams, mode: CellMode, src: NotePool, into dst: NotePool,
                            cell: SnapCell, m: Double, S: Double, cycleBeats: Double) {
        switch mode {
        case .silent:
            break                                              // closed passgate → empty
        case .arp:
            var arpBeats = Snap.arpRateBeats[Int(max(0, min(Int8(Snap.arpRateBeats.count - 1), p.rateIndex)))]
            if arpBeats <= 0 { arpBeats = 0.25 }
            let tick = Int64((m / arpBeats).rounded(.down))
            let pIdx = phaseIndex(tick: tick, mTickBeat: Double(tick) * arpBeats, arpBeats: arpBeats, S: S,
                                  cycleBeats: cycleBeats, phase: p.phase, runStartColumn: cell.runStartColumn)
            let pick = arpPick(phaseIndex: pIdx, octaves: Int(p.octaves), pattern: p.patternIndex,
                               pool: src, filter: 0, cableMask: 0b1111)   // velocity inherited from the picked source note
            if pick.note >= 0 && pick.note <= 127 { dst.noteOn(UInt8(pick.note), velocity: max(1, pick.vel), channel: 0) }
        case .chance:
            let colStart = columnStart(m, S)
            let cCnt = src.srcCount(filter: 0, cableMask: 0b1111)
            for k in 0..<cCnt {
                let n = src.srcAscending(k, filter: 0, cableMask: 0b1111)
                if chancePassesPool(beat: colStart, note: Int(n), rank: k, count: cCnt, probability: p.probability, tilt: p.chanceTilt, constantDensity: p.chanceDensity) { dst.noteOn(n, velocity: max(1, src.velocity(n)), channel: 0) }
            }
        case .tutti:                                           // [TUTTI→ARP]: reshape the source pool per step/slice
            let cCnt = src.srcCount(filter: 0, cableMask: 0b1111)
            if p.tuttiMode == .coin {
                var solo = -1                                   // −1 = TUTTI (whole set passes)
                let step = S > 0 ? Int((columnStart(m, S) / S).rounded()) : 0
                if !tuttiIsTutti(step: step, balance: p.tuttiBalance) { solo = tuttiSoloRank(step: step, count: cCnt, pick: p.tuttiPick) }
                for k in 0..<cCnt where solo < 0 || k == solo {
                    let n = src.srcAscending(k, filter: 0, cableMask: 0b1111)
                    dst.noteOn(n, velocity: max(1, src.velocity(n)), channel: 0)
                }
            } else {                                            // PATTERN: the authored slice shape at beat m
                let sub = max(0.03125, p.tuttiSliceBeats)
                let idx = (((tuttiSliceOf(m, sliceBeats: sub) + p.tuttiRotate) % 8) + 8) % 8
                let (ranks, oct) = tuttiSliceRanks(idx < p.tuttiSlices.count ? p.tuttiSlices[idx] : .all, count: cCnt)
                for rank in ranks where rank >= 0 && rank < cCnt {
                    let n = src.srcAscending(rank, filter: 0, cableMask: 0b1111)
                    let shifted = Int(n) + oct
                    if shifted >= 0 && shifted <= 127 { dst.noteOn(UInt8(shifted), velocity: max(1, src.velocity(n)), channel: 0) }
                }
            }
        case .harmonize:
            let ivs = [p.harmIntervals.0, p.harmIntervals.1, p.harmIntervals.2]
            for k in 0..<src.srcCount(filter: 0, cableMask: 0b1111) {
                let base = Int(src.srcAscending(k, filter: 0, cableMask: 0b1111))
                let bv = max(1, src.velocity(UInt8(base)))                // the added voices inherit the base note's velocity
                dst.noteOn(UInt8(base), velocity: bv, channel: 0)
                for iv in ivs where iv != 0 { let v = base + Int(iv); if v >= 0 && v <= 127 { dst.noteOn(UInt8(v), velocity: bv, channel: 0) } }
            }
        case .split:                                           // set-membership filter — RE-POOL when upstream of a driver
            let cCnt = src.srcCount(filter: 0, cableMask: 0b1111)
            let win = chordSplitWindow(count: cCnt, split: p.splitSet, noteAt: { Int(src.srcAscending($0, filter: 0, cableMask: 0b1111)) })
            let vf = p.splitVel.floor, vc = p.splitVel.ceil
            for k in max(0, win.start)..<min(cCnt, win.start + win.len) {
                let n = src.srcAscending(k, filter: 0, cableMask: 0b1111)
                let v = Int(src.velocity(n))
                if v >= vf && v <= vc { dst.noteOn(n, velocity: max(1, src.velocity(n)), channel: 0) }
            }
        default:                                               // identity / open passgate / ratchet / strum → pass through
            for k in 0..<src.srcCount(filter: 0, cableMask: 0b1111) { let n = src.srcAscending(k, filter: 0, cableMask: 0b1111); dst.noteOn(n, velocity: max(1, src.velocity(n)), channel: 0) }
        }
        dst.rebuildSorted()   // srcAscending reads `sorted`; noteOn doesn't maintain it
    }

    /// Compose stages [0…upto] of the chain into `chainScratch` at beat m — the TAIL reads this each tick. Seeds
    /// from the SHAPED source (the cell's channel/split/vel filter applies only at the head), then folds each
    /// non-bypassed stage through a ping-pong of the two working pools. Fixed pools → no render-thread alloc.
    private func composeChainSet(cell: SnapCell, pool: NotePool, upto: Int, m: Double, S: Double, cycleBeats: Double) {
        let pass = Int((m / cycleBeats).rounded(.down))
        var cur = chainA, nxt = chainB
        cur.reset()
        for k in 0..<pool.srcCount(for: cell) { let n = pool.srcAscending(k, for: cell); cur.noteOn(n, velocity: max(1, pool.velocity(n)), channel: 0) }   // seed carries the source velocity
        cur.rebuildSorted()
        var j = 0
        while j <= upto {
            if !cell.slotBypass[j] && cell.procs[j].type != .mod && cell.procs[j].type != .glide {   // true-bypass + MOD/GLIDE (their output is separate) pass untouched
                let mode = cellMode(type: cell.procs[j].type, bypassed: false, passMask: cell.procs[j].passMask, pass: pass)
                nxt.reset()
                applyStage(cell.procs[j], mode: mode, src: cur, into: nxt, cell: cell, m: m, S: S, cycleBeats: cycleBeats)
                swap(&cur, &nxt)
            }
            j += 1
        }
        chainScratch.reset()
        for k in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) { let n = cur.srcAscending(k, filter: 0, cableMask: 0b1111); chainScratch.noteOn(n, velocity: max(1, cur.velocity(n)), channel: 0) }   // carry velocity to the tail's source
        chainScratch.rebuildSorted()
    }

    /// Emit one note that the chain's DRIVER produced (at tick beat `m`), routed through the chain's POST-driver
    /// stages: when the driver is the tail it emits directly; otherwise the note is folded through slots
    /// driver+1…tail (passgate gates the pass → silence, chance drops, harmonize expands, bypassed passes) and
    /// each surviving note is emitted. Reuses chainA/chainB (fixed pools — no render-thread alloc); safe to call
    /// after composeChainSet has produced the driver's source (chainScratch is no longer needed by this tick).
    private func emitDriverNote(_ note: Int, cell: SnapCell, driver: Int, bm: UInt8,
                                onSample: Int64, offSample: Int64, windowEnd: Int64, velocity: UInt8,
                                m: Double, S: Double, cycleBeats: Double, beatsPerSample: Double, pass: Int, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard note >= 0 && note <= 127 else { return }
        if driver >= cell.procs.count - 1 {                       // driver IS the tail → no post-stages
            emitChop(note, cell: cell, bm: bm, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: velocity, m: m, S: S, out: out, diag: &diag)
            return
        }
        // `pass` is the authoritative lap counter (diag.pass) — the SAME one a stand-alone passgate gates on, so a
        // downstream passgate opens/closes on the lap the user sees (not a beat-derived recomputation that can drift).
        var cur = chainA, nxt = chainB
        cur.reset(); cur.noteOn(UInt8(note), velocity: velocity, channel: 0); cur.rebuildSorted()
        // ECHO in a chain repeats the cell's FULLY-PROCESSED output (user 2026-08-09): it passes through the fold as
        // identity and registers its tails AFTER every downstream stage has run — so a stage after it (HARMONIZE,
        // GATE, …) shapes the echoes too, honouring "each stage receives its parent's output". THRU keeps the dry,
        // MUTE drops it (echoes only). (v1: echo's chain POSITION no longer changes the tail's content — it always
        // echoes the final set; per-repeat-as-it-fires processing is the deeper "hand the tails" work.)
        var echoP: SnapParams? = nil
        var lenP: SnapParams? = nil   // LENGTH downstream (last-writer wins): overrides each onset's gate by its slice
        var j = driver + 1
        while j < cell.procs.count {
            if !cell.slotBypass[j] {   // true-bypass passes untouched
                if cell.procs[j].type == .echo {
                    echoP = cell.procs[j]   // hold the params; the tails register once the fold completes (below)
                } else if cell.procs[j].type == .mod || cell.procs[j].type == .glide {
                    // MOD/GLIDE are note-transparent in the fold — their output is emitted separately (v1: [driver→GLIDE] plays the driver).
                } else if cell.procs[j].type == .length {
                    lenP = cell.procs[j]   // note-transparent SET-wise; its gate override lands on the final emit (below)
                } else if cell.procs[j].type == .split {
                    // SPLIT downstream is a per-note MEMBERSHIP filter against the driver's pool — applied at the final emit
                    // via the row-loop-resolved gate (splitGate*), not as a set transform here (src is a single note).
                } else {
                    let mode = cellMode(type: cell.procs[j].type, bypassed: false, passMask: cell.procs[j].passMask, pass: pass)
                    nxt.reset()
                    applyStage(cell.procs[j], mode: mode, src: cur, into: nxt, cell: cell, m: m, S: S, cycleBeats: cycleBeats)
                    swap(&cur, &nxt)
                }
            }
            j += 1
        }
        // LENGTH downstream: replace THIS onset's gate by the slice it lands in — MUTE drops the note (+ its echoes),
        // PASS keeps the driver's own gate, SHORT/LONG override the off. The off-beat → sample conversion is linear
        // in `beatsPerSample` (gate offs, not onsets, so intra-column swing warp is negligible here).
        var offOut = offSample
        if let lp = lenP {
            let sIdx = ((chopSlice(m, columnBeats: S) + lp.lenRotate) % 8 + 8) % 8
            let st = sIdx < lp.lenSlices.count ? lp.lenSlices[sIdx] : .pass
            switch lengthGateFor(st, onset: m, shortFrac: lp.lenShort, longFrac: lp.lenLong, S: S) {
            case .drop:                cur.reset(); cur.rebuildSorted()   // MUTE → no note, no echoes
            case .keep:                break
            case .overrideOff(let ob): offOut = onSample + Int64((max(0, ob - m) / beatsPerSample).rounded())
            }
        }
        if let ep = echoP {   // echo the fully-processed set (all downstream stages applied)
            // §cell-edit F CHOP: the tail routes through the per-slice split too — it inherits the source note's
            // slice destination, so echoes follow the note (a muted slice → mask 0 → no tail). (user 2026-08-09.)
            let echoBM = chopMask(cell, m: m, S: S, base: bm)
            for k in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) {
                let n = cur.srcAscending(k, filter: 0, cableMask: 0b1111)
                pushEchoForNote(Int(n), vel: max(1, cur.velocity(n)), bm: echoBM, p: ep, onset: m, S: S)   // each echo inherits its note's velocity
            }
            if !ep.echoThru { cur.reset(); cur.rebuildSorted() }   // MUTE → echoes only (no dry)
        }
        for k in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) {
            let n = cur.srcAscending(k, filter: 0, cableMask: 0b1111)
            if splitGateActive && (Int(n) < splitGateLo || Int(n) > splitGateHi || Int(cur.velocity(n)) < splitGateVF || Int(cur.velocity(n)) > splitGateVC) { continue }   // SPLIT punch-hole → rest
            emitChop(Int(n), cell: cell, bm: bm, onSample: onSample, offSample: offOut, windowEnd: windowEnd,
                     velocity: max(1, cur.velocity(n)), m: m, S: S, out: out, diag: &diag)   // per-note carried velocity (offOut = LENGTH-overridden gate)
        }
    }
    /// Register an echo tail for ONE tick note ([ARP→ECHO]) at beat `onset`. v1 tick-echo is SYNCED-delay only (the
    /// tick emitters don't thread tempo, so free-ms tick echo is deferred); the single/hold-tail path supports both.
    private func pushEchoForNote(_ note: Int, vel: UInt8, bm: UInt8, p: SnapParams, onset: Double, S: Double) {
        guard note >= 0 && note <= 127, p.echoSync else { return }
        let timeBeats = Double(p.echoDelayDiv) / 4.0
        pushEchoTail(onset: onset, note: UInt8(note), vel: vel, busMask: bm, timeBeats: timeBeats,
                     repeats: max(1, min(16, p.echoRepeats)), feedDelay: p.echoFeedDelay, decay: p.echoDecay,
                     offset: p.echoOffset, pitch: p.echoPitch, gateBeats: min(timeBeats * 0.9, S * 0.9), spill: p.echoSpill)
    }
    /// The emit bus-mask for a cell at musical beat `m` after its per-slice CHOP routing (independent main/alt/mute).
    private func chopMask(_ cell: SnapCell, m: Double, S: Double, base: UInt8) -> UInt8 {
        guard cell.chopActive else { return base }
        let sl = UInt8(chopSlice(m, columnBeats: S))
        return chopBusMask(base, main: (cell.chopMain >> sl) & 1 == 1, alt: (cell.chopAlt >> sl) & 1 == 1,
                           mute: (cell.chopMute >> sl) & 1 == 1, altMask: cell.chopAltMask)
    }
    /// Emit one note applying the cell's per-slice CHOP routing (the shared tail of every tick emitter).
    private func emitChop(_ note: Int, cell: SnapCell, bm: UInt8, onSample: Int64, offSample: Int64,
                          windowEnd: Int64, velocity: UInt8, m: Double, S: Double, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard note >= 0 && note <= 127 else { return }
        let tbm = chopMask(cell, m: m, S: S, base: bm)
        if tbm != 0 { emitArtic(note: UInt8(note), busMask: tbm, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: velocity, out: out, diag: &diag) }
    }

    // MARK: - per-row tick emitters (the process() per-window content, one method per processor)

    /// ARP (§3): index the input each tick — MIDI IN → filtered source pool; referencing → the parent's
    /// CURRENT sounding note by derivation, octave-arped by this cell (delta §1 "arpeggiate the arpeggio").
    private func emitArpRow(cell: SnapCell, row r: Int, colour: SnapColour, transpose: Int,
                            emits: Bool, box: SnapshotBox, pool: NotePool,
                            effColumn: Int, beatPos: Double, windowBeats: Double, windowStart: Int64,
                            windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                            chainDriver: Int = -1,
                            out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        var arpBeats = effectiveRateBeats(colour)
        let gate = effectiveGate(colour)
        let octaves = effectiveOctaves(colour)
        if colour.a.arpFit {   // FIT (user 2026-08-11): one full pool traversal = one beat, so the cycle stays constant as the chord grows
            let n = max(1, pool.srcCount(for: cell))
            arpBeats = max(0.03125, 1.0 / Double(n * octaves))
        }
        if arpBeats <= 0 { arpBeats = 0.25 }
        if r == diag.activeCellRow { diag.effMorphGold = 0;   diag.effRateBeats = arpBeats }

        iterateTicks(row: r, effColumn: effColumn, sub: arpBeats, gateFraction: gate,
                     beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                     beatsPerSample: beatsPerSample, S: S, a: a) { tick, mTickBeat, onTime, offTime in
            let pIdx = phaseIndex(tick: tick, mTickBeat: mTickBeat, arpBeats: arpBeats, S: S,
                                  cycleBeats: cycleBeats, phase: colour.a.phase,
                                  runStartColumn: cell.runStartColumn)
            let base: Int
            let srcVel: UInt8   // velocity inherited from the picked source note (user 2026-08-09)
            if chainDriver >= 0 {
                // CELL MACHINE: this ARP is the chain DRIVER — arp the composed SET of the stages BEFORE it at this
                // tick (OMNI, past the input filter). Derived per tick → pool-correct (arps ALL upstream voices).
                composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: mTickBeat, S: S, cycleBeats: cycleBeats)
                let pick = arpPick(phaseIndex: pIdx, octaves: octaves, pattern: colour.a.patternIndex,
                                   pool: chainScratch, filter: 0, cableMask: 0b1111)
                guard pick.note >= 0 else { return }
                base = pick.note; srcVel = max(1, pick.vel)
            } else {
                let pick = arpPick(phaseIndex: pIdx, octaves: octaves,
                                   pattern: colour.a.patternIndex, pool: pool, for: cell)   // §7 source filter
                guard pick.note >= 0 else { return }
                base = pick.note; srcVel = max(1, pick.vel)
            }
            let noteValue = base + transpose
            guard noteValue >= 0 && noteValue <= 127 else { return }
            storeArtic(row: r, on: onTime, off: offTime, note: UInt8(noteValue), beat: mTickBeat)
            if emits {
                // §cell-edit F CHOP + the chain's post-driver stages fold onto each arp note (e.g. a downstream passgate).
                if chainDriver >= 0 {
                    emitDriverNote(noteValue, cell: cell, driver: chainDriver, bm: bm, onSample: onTime, offSample: offTime,
                                   windowEnd: windowEnd, velocity: srcVel, m: mTickBeat, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, pass: diag.pass, out: out, diag: &diag)
                } else {
                    emitChop(noteValue, cell: cell, bm: bm, onSample: onTime, offSample: offTime, windowEnd: windowEnd,
                             velocity: srcVel, m: mTickBeat, S: S, out: out, diag: &diag)
                }
            }
        }
    }

    /// RATCHET (§3): re-strike the WHOLE input pool `repeats` times per column, staccato (0.6), velocity ramp.
    /// Not an arp (no index cycling) — every stab is the pool (or the parent's sounding note, when referenced).
    private func emitRatchetRow(cell: SnapCell, row r: Int, colour: SnapColour, transpose: Int,
                                emits: Bool, box: SnapshotBox, pool livePool: NotePool,
                                effColumn: Int, beatPos: Double, windowBeats: Double, windowStart: Int64,
                                windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                                chainDriver: Int = -1,
                                out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: livePool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        let ramp = effectiveRamp(colour)
        let p = colour.a
        if p.rtcMode != .all {   // COIN / PATTERN — strikes-per-step vary, so window-scan (not the fixed-sub iterateTicks)
            emitRatchetModal(mode: p.rtcMode, cell: cell, row: r, transpose: transpose, emits: emits, pool: pool, bm: bm,
                             ramp: ramp, chainDriver: chainDriver, beatPos: beatPos, windowBeats: windowBeats,
                             windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample, S: S, a: a,
                             cycleBeats: cycleBeats, p: p, out: out, diag: &diag)
            return
        }
        let repeats = effectiveRepeats(colour)
        let sub = S / Double(repeats)                          // one repeat every `sub` beats
        if r == diag.activeCellRow { diag.effMorphGold = 0;   diag.effRateBeats = sub }
        iterateTicks(row: r, effColumn: effColumn, sub: sub, gateFraction: 0.6,
                     beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                     beatsPerSample: beatsPerSample, S: S, a: a) { _, mTickBeat, onTime, offTime in
            let colStart = columnStart(mTickBeat, S)
            let repIdx = Int(((mTickBeat - colStart) / sub).rounded())    // 0…repeats-1
            let tbm = chopMask(cell, m: mTickBeat, S: S, base: bm)         // §cell-edit F CHOP: routes by the 8-slice
            if emits && tbm == 0 { return }                               // MUTE slice → this repeat is silent
            ratchetStrikeAt(cell: cell, row: r, transpose: transpose, emits: emits, pool: pool, bm: bm, tbm: tbm,
                            onTime: onTime, offTime: offTime, m: mTickBeat, repIdx: repIdx, count: repeats, ramp: ramp,
                            chainDriver: chainDriver, windowEnd: windowEnd, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, out: out, diag: &diag)
        }
    }

    /// ONE ratchet strike of the whole (composed-upstream, or held) chord at [onTime, offTime) with the velocity ramp.
    /// Shared by ALL (iterateTicks) and the COIN/PATTERN window-scan. Chain-driver notes fold downstream via emitDriverNote.
    private func ratchetStrikeAt(cell: SnapCell, row r: Int, transpose: Int, emits: Bool, pool: NotePool, bm: UInt8, tbm: UInt8,
                                 onTime: Int64, offTime: Int64, m: Double, repIdx: Int, count: Int, ramp: Double,
                                 chainDriver: Int, windowEnd: Int64, S: Double, cycleBeats: Double, beatsPerSample: Double,
                                 out: MIDIEmitter?, diag: inout KernelDiag) {
        if chainDriver >= 0 {
            composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: m, S: S, cycleBeats: cycleBeats)
            for k in 0..<chainScratch.srcCount(filter: 0, cableMask: 0b1111) {
                let sn = chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111); let n = Int(sn) + transpose
                guard n >= 0 && n <= 127 else { continue }
                storeArtic(row: r, on: onTime, off: offTime, note: UInt8(n), beat: m)
                if emits {
                    let vel = ratchetVelocity(base: max(1, Int(chainScratch.velocity(sn))), ramp: ramp, index: repIdx, count: count)
                    emitDriverNote(n, cell: cell, driver: chainDriver, bm: bm, onSample: onTime, offSample: offTime,
                                   windowEnd: windowEnd, velocity: vel, m: m, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, pass: diag.pass, out: out, diag: &diag)
                }
            }
        } else {
            for k in 0..<pool.srcCount(for: cell) {
                let sn = pool.srcAscending(k, for: cell); let n = Int(sn) + transpose
                guard n >= 0 && n <= 127 else { continue }
                storeArtic(row: r, on: onTime, off: offTime, note: UInt8(n), beat: m)
                if emits && tbm != 0 {
                    let vel = ratchetVelocity(base: max(1, Int(pool.velocity(sn))), ramp: ramp, index: repIdx, count: count)
                    emitArtic(note: UInt8(n), busMask: tbm, onSample: onTime, offSample: offTime, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        }
    }

    /// RATCHET COIN / PATTERN. COIN: per step, a seeded chance to ratchet (a count in [lo,hi]) vs a plain single hit.
    /// PATTERN: walk the 8-slice per-slice-count row at RATE — 0 = a plain single hit, N = a roll of N within the slice;
    /// ROTATE offsets the pattern. Window-scanned per column (like WEAVE/LENGTH); RETRIG at the column boundary.
    private func emitRatchetModal(mode: RatchetMode, cell: SnapCell, row r: Int, transpose: Int, emits: Bool, pool: NotePool,
                                  bm: UInt8, ramp: Double, chainDriver: Int, beatPos: Double, windowBeats: Double,
                                  windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                                  cycleBeats: Double, p: SnapParams, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard S > 0 else { return }
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a), mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        var col = columnStart(mWinStart, S)
        while col < mWinEnd {
            let colEnd = col + S
            if mode == .coin {
                let step = Int((col / S).rounded())
                let count = rtcCoinRatchets(step: step, chance: p.rtcChance) ? rtcCoinCount(step: step, lo: p.rtcCountLo, hi: p.rtcCountHi) : 1
                let sub = S / Double(max(1, count))
                for j in 0..<count {
                    let tau = col + Double(j) * sub
                    guard tau >= mWinStart && tau < mWinEnd else { continue }
                    let tbm = chopMask(cell, m: tau, S: S, base: bm); if emits && tbm == 0 { continue }
                    let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    let offT = sampleOf(musical: min(colEnd, tau + sub * 0.6), beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    ratchetStrikeAt(cell: cell, row: r, transpose: transpose, emits: emits, pool: pool, bm: bm, tbm: tbm,
                                    onTime: onT, offTime: offT, m: tau, repIdx: j, count: count, ramp: ramp, chainDriver: chainDriver,
                                    windowEnd: windowEnd, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, out: out, diag: &diag)
                }
            } else {   // PATTERN
                let sliceBeats = max(0.03125, p.rtcRateBeats)
                var sIdx = 0
                while true {
                    let sliceStart = col + Double(sIdx) * sliceBeats
                    if sliceStart >= colEnd { break }
                    sIdx += 1
                    let g = Int((sliceStart / sliceBeats).rounded(.down))
                    let idx = (((g + p.rtcRotate) % 8) + 8) % 8
                    let raw = idx < p.rtcSlices.count ? p.rtcSlices[idx] : 0
                    let count = raw <= 0 ? 1 : min(8, raw)                 // 0 = plain single hit
                    let sEnd = min(colEnd, sliceStart + sliceBeats), subSlice = sliceBeats / Double(count)
                    for j in 0..<count {
                        let tau = sliceStart + Double(j) * subSlice
                        guard tau >= mWinStart && tau < mWinEnd && tau < sEnd else { continue }
                        let tbm = chopMask(cell, m: tau, S: S, base: bm); if emits && tbm == 0 { continue }
                        let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                        let offT = sampleOf(musical: min(sEnd, tau + subSlice * 0.6), beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                        ratchetStrikeAt(cell: cell, row: r, transpose: transpose, emits: emits, pool: pool, bm: bm, tbm: tbm,
                                        onTime: onT, offTime: offT, m: tau, repIdx: j, count: count, ramp: ramp, chainDriver: chainDriver,
                                        windowEnd: windowEnd, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, out: out, diag: &diag)
                    }
                }
            }
            col += S
        }
    }

    /// STRUM (§3): stagger the source chord's onsets over `spread` beats from the column start, held to the
    /// boundary. Emitted per-window as each onset arrives (strumProgress, reset per column) — each note fires once.
    private func emitStrumRow(cell: SnapCell, row r: Int, colour: SnapColour, transpose: Int,
                              emits: Bool, pool: NotePool, beatPos: Double, windowStart: Int64, windowEnd: Int64,
                              beatsPerSample: Double, S: Double, a: Double, chainDriver: Int = -1,
                              out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        let spread = effectiveSpread(colour)
        let curve = colour.a.curve, tilt = colour.a.velTilt, dir = colour.a.strumDir
        let colStart = columnStart(musicalOf(beatPos, stepBeats: S, a: a), S)
        let cycleBeats = Double(Snap.cols) * S
        // CELL MACHINE: a STRUM chain DRIVER staggers the composed set of the stages BEFORE it (derived once at colStart).
        if chainDriver >= 0 { composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: colStart, S: S, cycleBeats: cycleBeats) }
        let count = chainDriver >= 0 ? chainScratch.srcCount(filter: 0, cableMask: 0b1111) : pool.srcCount(for: cell)   // §7 source filter
        if r == diag.activeCellRow { diag.effMorphGold = 0;   diag.effRateBeats = spread }
        guard count > 0 else { return }

        let offSample = sampleOf(musical: colStart + S, beatPos: beatPos,       // held to boundary
                                 beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        while strumProgress[r] < count {
            let j = strumProgress[r]
            let onsetMusical = colStart + strumOffset(index: j, count: count, spread: spread, curve: curve, normalize: colour.a.strumSpreadNorm)
            let onsetSample = sampleOf(musical: onsetMusical, beatPos: beatPos,
                                       beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            if onsetSample >= windowEnd { break }        // onset lands in a later window
            strumProgress[r] += 1

            let sortedIdx = strumSortedIndex(position: j, count: count, direction: dir, pass: diag.pass)
            let srcNote = chainDriver >= 0 ? chainScratch.srcAscending(sortedIdx, filter: 0, cableMask: 0b1111) : pool.srcAscending(sortedIdx, for: cell)
            let n = Int(srcNote) + transpose
            guard n >= 0 && n <= 127 else { continue }
            let srcVel = chainDriver >= 0 ? chainScratch.velocity(srcNote) : pool.velocity(srcNote)   // inherit + tilt
            let vel = strumVelocity(index: j, count: count, tilt: tilt, base: max(1, Int(srcVel)))
            let onT = max(onsetSample, windowStart)
            storeArtic(row: r, on: onT, off: offSample, note: UInt8(n), beat: onsetMusical)
            if emits {
                if chainDriver >= 0 {   // fold each strummed note through the stages AFTER the strum (e.g. a downstream passgate)
                    emitDriverNote(n, cell: cell, driver: chainDriver, bm: bm, onSample: onT, offSample: offSample,
                                   windowEnd: windowEnd, velocity: vel, m: onsetMusical, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, pass: diag.pass, out: out, diag: &diag)
                } else {
                    emitArtic(note: UInt8(n), busMask: bm, onSample: onT, offSample: offSample,
                              windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        }
    }

    // (grid-chaining retired: `emitMirrorRow` — the referenced-parent mirror — is gone.)

    // MARK: - PREVIEW / cell audition (Phase 2, design 2026-07-26)

    /// STOPPED preview — the staged VIRTUAL cell as an ARP of the source pool on the free audition clock
    /// (no playhead → no row-feed; `filter` = the staged receiver's channel, 0 = OMNI). Solo + CLAIM-bypass.
    private func previewStopped(colourIndex ci: Int, filter: Int, busMask: UInt8, box: SnapshotBox, pool: NotePool,
                                tempo: Double, sampleRate: Double, windowStart: Int64, frameCount: UInt32,
                                out: MIDIEmitter?, diag: inout KernelDiag) {
        guard ci >= 0, ci < box.colours.count, busMask != 0, pool.count > 0 else { return }
        let colour = box.colours[ci]
        let beatsPerSample = tempo / 60.0 / sampleRate
        let windowBeats = Double(frameCount) * beatsPerSample
        let windowEnd = windowStart + Int64(frameCount)
        let clockBeat = Double(windowStart - auditionStartSample) * beatsPerSample
        let transpose = colourTranspose(ci, colour)
        previewMode = true; defer { previewMode = false }
        guard effectiveType(colour) == .arp else { return }
        var arpBeats = effectiveRateBeats(colour); if arpBeats <= 0 { arpBeats = 0.25 }
        let gate = effectiveGate(colour)
        let octaves = effectiveOctaves(colour)
        auditionTicks(sub: arpBeats, gateFraction: gate, startBeat: clockBeat, windowBeats: windowBeats,
                      windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
            let pick = arpPick(phaseIndex: tick, octaves: octaves, pattern: colour.a.patternIndex,
                               pool: pool, filter: UInt8(clamping: filter))
            guard pick.note >= 0 else { return }
            let n = pick.note + transpose; guard n >= 0 && n <= 127 else { return }
            emitArtic(note: UInt8(n), busMask: busMask, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: max(1, pick.vel), out: out, diag: &diag)
        }
    }

    /// PLAYING preview (Increment 1b) — the staged VIRTUAL cell at the live column `effColumn`, SOLO. Mirrors
    /// the per-row ARP/RATCHET/STRUM derivation for one virtual row: ⇐ROW n reads that row's sounding note by
    /// derivation (parentSoundingNote); receiver/OMNI reads the filtered source pool. Uses tick slot row 0
    /// (free during solo). busEnabled respected; CLAIM bypassed. (Chord-hold/mirror types = a later cut.)
    private func previewPlaying(colourIndex ci: Int, filter: Int, busMask: UInt8, effColumn: Int,
                               box: SnapshotBox, pool: NotePool, beatPos: Double, windowBeats: Double,
                               windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                               cycleBeats: Double, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard ci >= 0, ci < box.colours.count, busMask != 0, pool.count > 0 else { return }
        let colour = box.colours[ci]
        let transpose = colourTranspose(ci, colour)
        let vr = 0                                        // virtual tick-dedup row (grid-chaining retired: always source-fed)
        let f = UInt8(clamping: filter)
        previewMode = true; defer { previewMode = false }
        let mode = cellMode(type: effectiveType(colour), bypassed: false,
                            passMask: effectivePassMask(colour), pass: diag.pass)

        // Virtual-cell COLUMN TRANSITION: truncate its voices at the boundary, reset per-column state, and
        // (chord-hold types on SOURCE input) emit the treated held chord sustained to the column boundary.
        if effColumn != previewPrevColumn {
            let mNow = musicalOf(beatPos, stepBeats: S, a: a)
            if anyVoiceActive() {
                let boundaryMusical = columnStart(mNow, S)
                let off = max(0, (realOf(boundaryMusical, stepBeats: S, a: a) - beatPos) / beatsPerSample)
                allNotesOff(atSample: windowStart + Int64(off), out: out)
            }
            previewPrevColumn = effColumn
            lastTick[vr] = -1; strumProgress[vr] = 0
            if mode == .identity || mode == .chance || mode == .harmonize || mode == .tutti {
                previewChordHold(isChance: mode == .chance, isHarmonize: mode == .harmonize, colour: colour,
                                 transpose: transpose, filter: f, busMask: busMask, mNow: mNow, beatPos: beatPos,
                                 beatsPerSample: beatsPerSample, S: S, a: a, windowStart: windowStart,
                                 windowEnd: windowEnd, pool: pool, out: out, diag: &diag)
            }
        }

        switch mode {
        case .arp:
            var arpBeats = effectiveRateBeats(colour); if arpBeats <= 0 { arpBeats = 0.25 }
            let gate = effectiveGate(colour)
            let octaves = effectiveOctaves(colour)
            iterateTicks(row: vr, effColumn: effColumn, sub: arpBeats, gateFraction: gate, beatPos: beatPos,
                         windowBeats: windowBeats, windowStart: windowStart, beatsPerSample: beatsPerSample, S: S, a: a) { tick, mTickBeat, onTime, offTime in
                let pIdx = phaseIndex(tick: tick, mTickBeat: mTickBeat, arpBeats: arpBeats, S: S,
                                      cycleBeats: cycleBeats, phase: colour.a.phase, runStartColumn: -1)
                let pick = arpPick(phaseIndex: pIdx, octaves: octaves, pattern: colour.a.patternIndex, pool: pool, filter: f)
                guard pick.note >= 0 else { return }
                let n = pick.note + transpose; guard n >= 0 && n <= 127 else { return }
                emitArtic(note: UInt8(n), busMask: busMask, onSample: onTime, offSample: offTime, windowEnd: windowEnd, velocity: max(1, pick.vel), out: out, diag: &diag)
            }
        case .ratchet:
            let repeats = effectiveRepeats(colour)
            let ramp = effectiveRamp(colour)
            let sub = S / Double(max(1, repeats))
            iterateTicks(row: vr, effColumn: effColumn, sub: sub, gateFraction: 0.6, beatPos: beatPos,
                         windowBeats: windowBeats, windowStart: windowStart, beatsPerSample: beatsPerSample, S: S, a: a) { _, mTickBeat, onTime, offTime in
                let colStart = columnStart(mTickBeat, S)
                let repIdx = Int(((mTickBeat - colStart) / sub).rounded())
                let srcN = pool.srcCount(filter: f)
                for k in 0..<srcN {
                    let sn = pool.srcAscending(k, filter: f)
                    let n = Int(sn) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    let vel = ratchetVelocity(base: max(1, Int(pool.velocity(sn))), ramp: ramp, index: repIdx, count: repeats)   // inherit
                    emitArtic(note: UInt8(n), busMask: busMask, onSample: onTime, offSample: offTime, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        case .strum:
            let spread = effectiveSpread(colour)
            let curve = colour.a.curve, tilt = colour.a.velTilt, dir = colour.a.strumDir
            let count = pool.srcCount(filter: f)   // STRUM is source-based (no row-feed, matching the real loop)
            if count > 0 {
                let colStart = columnStart(musicalOf(beatPos, stepBeats: S, a: a), S)
                let offSample = sampleOf(musical: colStart + S, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                while strumProgress[vr] < count {
                    let j = strumProgress[vr]
                    let onsetMusical = colStart + strumOffset(index: j, count: count, spread: spread, curve: curve, normalize: colour.a.strumSpreadNorm)
                    let onsetSample = sampleOf(musical: onsetMusical, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    if onsetSample >= windowEnd { break }
                    strumProgress[vr] += 1
                    let sortedIdx = strumSortedIndex(position: j, count: count, direction: dir, pass: diag.pass)
                    let sn = pool.srcAscending(sortedIdx, filter: f)
                    let n = Int(sn) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    let vel = strumVelocity(index: j, count: count, tilt: tilt, base: max(1, Int(pool.velocity(sn))))   // inherit
                    emitArtic(note: UInt8(n), busMask: busMask, onSample: max(onsetSample, windowStart),
                              offSample: offSample, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        default:
            break   // chord-hold handled at the transition above; a closed passgate is silent; fed-mirror = later cut
        }
    }

    /// The virtual cell's CHORD-HOLD (identity / open-passgate / CHANCE / HARMONIZE on SOURCE input): the
    /// per-cell body of `emitColumnHolds`, emitted once at the column transition, sustained to the boundary.
    private func previewChordHold(isChance: Bool, isHarmonize: Bool, colour: SnapColour, transpose: Int,
                                  filter: UInt8, busMask: UInt8, mNow: Double, beatPos: Double, beatsPerSample: Double,
                                  S: Double, a: Double, windowStart: Int64, windowEnd: Int64, pool: NotePool,
                                  out: MIDIEmitter?, diag: inout KernelDiag) {
        let colStart = columnStart(mNow, S)
        let onSample = sampleOf(musical: colStart, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        let offSample = sampleOf(musical: colStart + S, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        let prob = isChance ? effectiveProbability(colour) : 1
        let srcN = pool.srcCount(filter: filter)
        for k in 0..<srcN {
            let sn = pool.srcAscending(k, filter: filter)
            let n = Int(sn) + transpose
            guard n >= 0 && n <= 127 else { continue }
            if isChance && !chancePasses(beat: colStart, note: n, probability: prob) { continue }
            let vel = max(1, pool.velocity(sn))   // inherit the source velocity
            if isHarmonize {
                emitHarmony(base: n, colour: colour, baseVel: vel, row: 0, storeArtics: false,
                            busMask: busMask, on: onSample, off: offSample, beat: colStart, windowEnd: windowEnd, out: out, diag: &diag)
            } else {
                emitArtic(note: UInt8(n), busMask: busMask, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
            }
        }
    }

    // MARK: - audition (§6.4 / delta §5)

    /// Sound the held cell's processor ALONE against the live source while the transport is stopped.
    /// §6.4: phase zeroed, input FORCED to source (the `inputRow` reference is ignored), the cell's
    /// active A/B state, its lit letters, passgates all-open, an internal phase clock at host tempo.
    /// A change of `target` (new cell, switched cell, or release → −1) flushes and restarts the clock;
    /// transport start flushes via the process() transport edge (auto-release). Handles the
    /// time-varying processors ARP and RATCHET here; STRUM rolls via `auditionStrum` and the chord-hold
    /// types (identity/passgate/chance/harmonize) sustain via `auditionChordHold` — all shipped.
    private func auditionRender(box: SnapshotBox, pool: NotePool, target: Int,
                                tempo: Double, sampleRate: Double, timestampSample: Double,
                                frameCount: UInt32, S: Double, out: MIDIEmitter?, diag: inout KernelDiag) {
        let windowStart = Int64(timestampSample)
        if target != prevAudition {          // hold began / switched / released → cut and re-origin the clock
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevAudition = target
            auditionStartSample = windowStart
            auditionLastTick = -1
        }
        guard target >= 0 else { return }
        let col = target / Snap.rows, row = target % Snap.rows
        guard col >= 0, col < Snap.cols, row >= 0, row < Snap.rows else { return }
        let cell = box.cells[col * Snap.rows + row]
        guard cell.colourIndex >= 0, !cell.muted, cell.busMask != 0, !cell.bypassed else { return }
        guard pool.count > 0 else { return }          // no held notes → silence (soundcheck)
        let ci = Int(cell.colourIndex)
        let colour = box.colours[ci]
        // CELL MACHINE: audition previews the cell's RESOLVED HEAD treatment (override/template-aware), not the raw
        // Colour A face — `treat.a = cell.proc`, so effective*(treat) reads the head. (Multi-slot chains preview the
        // HEAD slot; a full serial preview of the tail is a follow-up.)
        var treat = colour; treat.a = cell.proc

        let beatsPerSample = tempo / 60.0 / sampleRate
        let auditionBeat = Double(windowStart - auditionStartSample) * beatsPerSample   // free phase clock
        let windowBeats = Double(frameCount) * beatsPerSample
        let windowEnd = windowStart + Int64(frameCount)
        let transpose = colourTranspose(ci, colour)

        switch effectiveType(treat) {
        case .arp:
            var arpBeats = effectiveRateBeats(treat); if arpBeats <= 0 { arpBeats = 0.25 }
            let gate = effectiveGate(treat)
            let octaves = effectiveOctaves(treat)
            auditionTicks(sub: arpBeats, gateFraction: gate, startBeat: auditionBeat, windowBeats: windowBeats,
                          windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
                let pick = arpPick(phaseIndex: tick, octaves: octaves,   // phase zeroed: index = ticks since hold
                                   pattern: treat.a.patternIndex, pool: pool, for: cell)
                guard pick.note >= 0 else { return }
                let n = pick.note + transpose; guard n >= 0 && n <= 127 else { return }
                emitArtic(note: UInt8(n), busMask: cell.busMask, onSample: onT, offSample: offT,
                          windowEnd: windowEnd, velocity: max(1, pick.vel), out: out, diag: &diag)
            }
        case .ratchet:
            let repeats = effectiveRepeats(treat)
            let ramp = effectiveRamp(treat)
            let sub = S / Double(max(1, repeats))
            auditionTicks(sub: sub, gateFraction: 0.6, startBeat: auditionBeat, windowBeats: windowBeats,
                          windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
                let repIdx = ((Int(tick) % repeats) + repeats) % repeats
                let srcN = pool.srcCount(for: cell)
                for k in 0..<srcN {
                    let sn = pool.srcAscending(k, for: cell)
                    let n = Int(sn) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    let vel = ratchetVelocity(base: max(1, Int(pool.velocity(sn))), ramp: ramp, index: repIdx, count: repeats)   // inherit
                    emitArtic(note: UInt8(n), busMask: cell.busMask, onSample: onT, offSample: offT,
                              windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        case .strum:
            // STRUM: roll the held chord in over `spread` beats from the hold (its own onset per note),
            // then sustain — the audition clock drives the roll; reconcile tracks live key changes.
            auditionStrum(cell: cell, colour: treat, pool: pool, transpose: transpose,
                          auditionBeat: auditionBeat, windowEnd: windowEnd, out: out, diag: &diag)
        default:
            // chord-hold types (passgate all-open / chance / harmonize): sustain the treated chord,
            // reconciled to the live held source each window (v2).
            auditionChordHold(cell: cell, colour: treat, pool: pool, transpose: transpose,
                              windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        }
    }

    /// Sustain the held source chord through a chord-hold treatment (§6.4), tracking the keys LIVE:
    /// build the note-set the source should sound through the treatment, then reconcile against what is
    /// currently sounding — close departed notes, open new ones (sustained; released by allNotesOff on
    /// hold-change / transport-start). passgate is forced all-open; chance seeds on the hold (beat 0) so
    /// each note is deterministically in or out for the whole hold; harmonize expands to its voices.
    private func auditionChordHold(cell: SnapCell, colour: SnapColour, pool: NotePool,
                                   transpose: Int, windowStart: Int64, windowEnd: Int64,
                                   out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionDesired[i] = false }
        let type = effectiveType(colour)
        let prob = (type == .chance) ? effectiveProbability(colour) : 1
        let srcN = pool.srcCount(for: cell)         // §7 source filter, forced source
        for k in 0..<srcN {
            let sn = pool.srcAscending(k, for: cell)
            let base = Int(sn) + transpose
            guard base >= 0 && base <= 127 else { continue }
            let bv = max(1, pool.velocity(sn))   // inherit the source velocity
            switch type {
            case .harmonize:
                let iv = (Int8(effectiveHarmInterval(colour, voice: 0)),
                          Int8(effectiveHarmInterval(colour, voice: 1)),
                          Int8(effectiveHarmInterval(colour, voice: 2)))
                let cnt = harmonizeVoices(base: base, intervals: iv, into: &harmNotes,
                                          vel: bv, velScale: effectiveHarmVelScale(colour), vels: &harmVels)
                for j in 0..<cnt where harmNotes[j] >= 0 && harmNotes[j] <= 127 {
                    auditionDesired[harmNotes[j]] = true; auditionVel[harmNotes[j]] = harmVels[j]
                }
            case .chance:
                if chancePasses(beat: 0, note: base, probability: prob) { auditionDesired[base] = true; auditionVel[base] = bv }
            default:                                                 // passgate all-open (sustain the chord)
                auditionDesired[base] = true; auditionVel[base] = bv
            }
        }
        reconcileAuditionVoices(busMask: cell.busMask, windowEnd: windowEnd, out: out, diag: &diag)
    }

    /// STRUM audition: the held chord ROLLS in — each note has its own onset (`strumOffset`) measured
    /// from the hold; a note joins the sustained set once the audition clock passes its onset. So the
    /// first hold rolls the chord; thereafter it sustains and reconcile tracks live key changes. No
    /// columns here, so direction uses pass 0 and notes never auto-release (offSample .max).
    private func auditionStrum(cell: SnapCell, colour: SnapColour, pool: NotePool,
                               transpose: Int, auditionBeat: Double,
                               windowEnd: Int64, out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionDesired[i] = false }
        let spread = effectiveSpread(colour)
        let count = pool.srcCount(for: cell)
        for j in 0..<count {
            guard auditionBeat >= strumOffset(index: j, count: count, spread: spread, curve: colour.a.curve, normalize: colour.a.strumSpreadNorm)
            else { continue }                                   // this note's onset hasn't arrived yet
            let sortedIdx = strumSortedIndex(position: j, count: count, direction: colour.a.strumDir, pass: 0)
            let sn = pool.srcAscending(sortedIdx, for: cell)
            let n = Int(sn) + transpose
            guard n >= 0 && n <= 127 else { continue }
            auditionDesired[n] = true
            auditionVel[n] = strumVelocity(index: j, count: count, tilt: colour.a.velTilt, base: max(1, Int(pool.velocity(sn))))   // inherit
        }
        reconcileAuditionVoices(busMask: cell.busMask, windowEnd: windowEnd, out: out, diag: &diag)
    }

    /// Drive the sustained audition voices toward `auditionDesired`/`auditionVel`: close any sounding
    /// note no longer wanted, open any wanted note not yet sounding — IMMEDIATE ("sound now"), never
    /// auto-closing (offSample .max); reconcile / release ends them. Shared by chord-hold and strum.
    private func reconcileAuditionVoices(busMask: UInt8, windowEnd: Int64, out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionCurrent[i] = false }
        // Exclude SILENT claim ghosts: they carry no wire note, so a desired audible note at that pitch
        // must still be opened (else a disabled claimant's reservation would mute an audition voice).
        for v in voices where v.active && !v.silent { auditionCurrent[Int(v.note)] = true }
        for i in voices.indices where voices[i].active && !auditionDesired[Int(voices[i].note)] {
            closeVoice(i, atSample: renderSampleImmediate, out: out)
        }
        for n in 0..<128 where auditionDesired[n] && !auditionCurrent[n] {
            emitArtic(note: UInt8(n), busMask: busMask, onSample: renderSampleImmediate, offSample: .max,
                      windowEnd: windowEnd, velocity: auditionVel[n], out: out, diag: &diag)
        }
    }

    /// The audition tick scaffold: like `iterateTicks` but with NO column gating and a single dedup
    /// slot — audition is one free-running cell. `startBeat` is beats elapsed since the hold began, so
    /// `tick` counts from 0 (phase zeroed). floor + the `== auditionLastTick` dedup catches a boundary
    /// tick exactly once across windows (fired at window start when clamped), matching iterateTicks.
    private func auditionTicks(sub: Double, gateFraction: Double, startBeat: Double, windowBeats: Double,
                               windowStart: Int64, beatsPerSample: Double,
                               _ body: (_ tick: Int64, _ onT: Int64, _ offT: Int64) -> Void) {
        guard sub > 0 else { return }
        let firstTick = Int64((startBeat / sub).rounded(.down))
        let lastT = Int64(((startBeat + windowBeats) / sub).rounded(.down))
        guard firstTick <= lastT else { return }
        for tick in firstTick...lastT {
            if tick == auditionLastTick { continue }
            auditionLastTick = tick
            let tickBeat = Double(tick) * sub
            let onT = windowStart + Int64(max(0, (tickBeat - startBeat) / beatsPerSample))
            let offT = windowStart + Int64(max(0, (tickBeat + sub * gateFraction - startBeat) / beatsPerSample))
            body(tick, onT, offT)
        }
    }
}
