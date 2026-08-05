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
    private var markVel = [[UInt8]](repeating: [UInt8](repeating: 0, count: 8), count: 4)
    private var markCol = [[Int8]](repeating: [Int8](repeating: -1, count: 8), count: 4)
    private var markCount = [Int](repeating: 0, count: 4)
    // §6a THE WITHHELD TELL: a parallel bounded buffer of note-ons SUPPRESSED by CLAIM (leak 0) since the last
    // drain — same (velocity, source colourIndex) shape. The UI renders these HOLLOW + a claim-hue tick so a
    // suppressed note reads as "withheld here", not a silent bug. Only full CLAIM suppression records (a LEAK
    // shadow already sounds as a dimmer mark; solo/mute/disabled are intentional silences, not withholdings).
    private var withheldVel = [[UInt8]](repeating: [UInt8](repeating: 0, count: 8), count: 4)
    private var withheldCol = [[Int8]](repeating: [Int8](repeating: -1, count: 8), count: 4)
    private var withheldCount = [Int](repeating: 0, count: 4)
    // §strips-done (the emitter twin of the receiver's recvHeld): the notes CURRENTLY SOUNDING per emitter — a
    // live snapshot of the voice table sliced by bus, each carrying (velocity, source colourIndex) so the UI
    // draws a hold-while-sounding tick in the SOURCE Colour (cargo tint) and fades it on release. Snapshotted on
    // the render thread each window; read-and-copied by the UI poll (benign staleness race, like the meters).
    private var soundVel = [[UInt8]](repeating: [UInt8](repeating: 0, count: 12), count: 4)
    private var soundCol = [[Int8]](repeating: [Int8](repeating: -1, count: 12), count: 4)
    private var soundCount = [Int](repeating: 0, count: 4)
    private var currentColourIndex: Int8 = -1        // the emitting cell's colourIndex (for the SEAL comet feed)
    // THE SEAL COMET: per-CELL peak note velocity since the last drain (index = col*8+row) — the grid comet's
    // motion signal. Accumulated on the render thread at the emit boundary, read-and-cleared by the UI poll (the
    // UI owns the ~1s decay). `currentCellIndex` is the emitting cell's grid index, set per-cell in the emit loops.
    private var cellStrike = [UInt8](repeating: 0, count: 64)
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
    // §9 item 1 ON TAP (unified ALT model): ephemeral per-cell ALT flips (bit col*8+row). Set each process()
    // from the param; XORed into a cell's base ALT so a PERFORM tap is momentary, never a document write.
    private var tapAltMask: UInt64 = 0
    private func tapFlipped(_ col: Int, _ row: Int) -> Bool { (tapAltMask >> UInt64(col * 8 + row)) & 1 == 1 }
    // §9 item 1 ON TAP actions (4b), ephemeral: MUTE = a per-cell momentary silence (bit col*8+row);
    // SOLO EMITTERS = a global emitter solo set (bits A–D; 0 = no solo → siblings fall silent at emission).
    private var tapMuteMask: UInt64 = 0
    private var soloEmitterMask: UInt8 = 0
    private func tapMuted(_ col: Int, _ row: Int) -> Bool { (tapMuteMask >> UInt64(col * 8 + row)) & 1 == 1 }
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
            let filter = receiverChannels[r], cable = Int(receiverCables[r])
            let lo = receiverRangeLo[r], hi = receiverRangeHi[r]
            let cnt = destMask == 0 ? 0 : pool.srcCount(filter: filter, cableMask: cable, velLo: 0, velHi: 127, noteLo: lo, noteHi: hi)
            for k in 0..<cnt {
                let n = pool.srcAscending(k, filter: filter, cableMask: cable, velLo: 0, velHi: 127, noteLo: lo, noteHi: hi)
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
                    let vel = max(1, pool.heldVelocity(note))
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
    private var harmNotes = [Int](repeating: 0, count: 4)               // HARMONIZE fan scratch (root + 3 voices)
    private var harmVels = [UInt8](repeating: 0, count: 4)

    func reset() {
        for i in voices.indices { voices[i].active = false; voices[i].offSample = .max; voices[i].silent = false }
        for i in refcount.indices { refcount[i] = 0 }
        distinctSounding = 0
        wasPlaying = false
        for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
        prevEffColumn = -1
        prevBusEnabledMask = 0b1111
        for i in 0..<4 { meterPeakVel[i] = 0; meterEvents[i] = 0; markCount[i] = 0; withheldCount[i] = 0; soundCount[i] = 0 }
        prevAudition = -1; auditionLastTick = -1
        for i in overrides.indices { overrides[i] = .nan }
        overrideGen = .max
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

    // Topmost occupied, non-muted cell in a grid column — the single active cell (no chains until
    // commit 5). cells index = column*8 + row (Snapshot.swift). Muted cells produce nothing (§6.2).
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
            out.emit(sampleTime: onSample, cable: cable, 0x90 | chan, note, max(1, velocity))   // §7 clause 1: note-ons ALWAYS emit
            let idx = rcIndex(cable, chan, note)
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

    /// item 4 VELOCITY MARKS: read-and-clear the per-emitter note-on marks accumulated since the last poll —
    /// each a (velocity, source colourIndex). The UI latches a timestamp per mark and fades it (~250ms).
    func drainMarks() -> [[(vel: UInt8, col: Int8)]] {
        var out = [[(vel: UInt8, col: Int8)]]()
        for bus in 0..<4 {
            var m = [(vel: UInt8, col: Int8)](); m.reserveCapacity(markCount[bus])
            for i in 0..<markCount[bus] { m.append((markVel[bus][i], markCol[bus][i])) }
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
            soundVel[b][soundCount[b]] = v.vel
            soundCol[b][soundCount[b]] = v.colourIndex
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
            var m = [(vel: UInt8, col: Int8)](); m.reserveCapacity(soundCount[b])
            for i in 0..<soundCount[b] { m.append((soundVel[b][i], soundCol[b][i])) }
            out.append(m)
        }
        return out
    }

    /// §6a THE WITHHELD TELL: read-and-clear the per-emitter note-ons CLAIM fully suppressed (leak 0) since
    /// the last poll — each a (would-be velocity, source colourIndex). The UI draws these hollow + a claim tick.
    func drainWithheld() -> [[(vel: UInt8, col: Int8)]] {
        var out = [[(vel: UInt8, col: Int8)]]()
        for bus in 0..<4 {
            var m = [(vel: UInt8, col: Int8)](); m.reserveCapacity(withheldCount[bus])
            for i in 0..<withheldCount[bus] { m.append((withheldVel[bus][i], withheldCol[bus][i])) }
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
        distinctSounding == 0 && voices.allSatisfy { !$0.active } && refcount.allSatisfy { $0 == 0 }
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
                        withheldVel[bus][withheldCount[bus]] = velocity; withheldCol[bus][withheldCount[bus]] = currentColourIndex
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
        if v > meterPeakVel[bus] { meterPeakVel[bus] = v }   // §6a metering (post-transform vel, incl. override)
        meterEvents[bus] &+= 1
        if currentCellIndex >= 0 && currentCellIndex < 64 && v > cellStrike[currentCellIndex] { cellStrike[currentCellIndex] = v }   // SEAL comet: this cell struck

        if markCount[bus] < 8 {                              // item 4: a floating velocity MARK for this note-on
            markVel[bus][markCount[bus]] = v; markCol[bus][markCount[bus]] = currentColourIndex
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
    private func emitHarmony(base: Int, colour: SnapColour, t: Double, baseVel: UInt8, row: Int,
                             storeArtics: Bool, busMask: UInt8,
                             on: Int64, off: Int64, beat: Double,
                             windowEnd: Int64, out: MIDIEmitter?,
                             diag: inout KernelDiag) {
        let iv = (Int8(effectiveHarmInterval(colour, voice: 0, t: t)),
                  Int8(effectiveHarmInterval(colour, voice: 1, t: t)),
                  Int8(effectiveHarmInterval(colour, voice: 2, t: t)))
        let scale = effectiveHarmVelScale(colour, t: t)
        let cnt = harmonizeVoices(base: base, intervals: iv, into: &harmNotes,
                                  vel: baseVel, velScale: scale, vels: &harmVels)
        for i in 0..<cnt {
            if storeArtics { storeArtic(row: row, on: on, off: off, note: UInt8(harmNotes[i]), beat: beat) }
            if busMask != 0 {
                emitArtic(note: UInt8(harmNotes[i]), busMask: busMask, onSample: on, offSample: off,
                          windowEnd: windowEnd, velocity: harmVels[i], out: out, diag: &diag)
            }
        }
    }

    private func emitColumnHolds(box: SnapshotBox, column: Int, pool: NotePool, pass: Int,
                                 S: Double, a: Double, mNow: Double, beatPos: Double,
                                 beatsPerSample: Double, windowStart: Int64,
                                 windowEnd: Int64, out: MIDIEmitter?,
                                 diag: inout KernelDiag) {
        let colStart = (mNow / S).rounded(.down) * S
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
            if cell.colourIndex < 0 || cell.muted || cell.dormant || cell.busMask == 0 || tapMuted(column, r) { continue }   // §9 ON TAP = MUTE · LADDER dormant
            if isCoveredChain(cell) { continue }   // CELL MACHINE stage-2: the ARP tail emits in the tick loop; the head must not chord-hold here
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
            let t = 0.0                                              // morph removed
            // CELL MACHINE: a HOLD-TAIL chain holds the TAIL slot's transform of every upstream stage's composed
            // set; a plain cell holds its head-only treatment of the source.
            let holdChain = isHoldTailChain(cell)
            let tailIdx = cell.procs.count - 1
            var treat = colour; let treatP = holdChain ? cell.procs[tailIdx] : cell.proc
            treat.a = treatP
            let mode = cellMode(type: effectiveType(treat, t: t),
                                bypassed: holdChain ? cell.slotBypass[tailIdx] : cell.bypassed,
                                passMask: effectivePassMask(treat, t: t), pass: pass)
            guard mode == .identity || mode == .chance || mode == .harmonize else { continue }
            let transpose = colourTranspose(ci, colour)
                          + octaveShift(cell.resolvedReceiver)           // receiver strip: input OCT nudge
            let prob = (mode == .chance) ? effectiveProbability(treat, t: t) : 1
            let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: pass)   // §9 item 1 EMITTER-ROTATE
            // §2 CONTINUITY: an identity chord-hold under LEGATO is a DRONE — it flows through column
            // boundaries. RETRIG (and .free) re-strike as before; CHANCE/HARMONIZE re-speak (per-column
            // dice / expansion); the ALT turn-group is excluded (a rotating emitter is a fresh strike).
            let legato = mode == .identity && treat.a.phase == .legato && (bm & altMask) == 0
            // §cell-edit F CHOP: a hold is ONE articulation (at colStart = slice 0), so route it by that slice's
            // chop — MAIN adds the cell's own emitters, ALT adds altDest, MUTE silences. `chopMask` returns `bm`
            // unchanged when the cell has no chop, so this is a no-op for ordinary holds. (Tick cells chop per-tick.)
            let hbm = chopMask(cell, m: colStart, S: S, base: bm)
            let cellPool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: frozen chord if armed
            if holdChain { composeChainSet(cell: cell, pool: cellPool, upto: tailIdx - 1, m: colStart, S: S, cycleBeats: Double(Snap.cols) * S) }
            let srcN = holdChain ? chainScratch.srcCount(filter: 0, cableMask: 0b1111) : cellPool.srcCount(for: cell)   // §7 source filter
            for k in 0..<srcN {
                let base = holdChain ? Int(chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111)) : Int(cellPool.srcAscending(k, for: cell))
                let n = base + transpose
                guard n >= 0 && n <= 127 else { continue }
                if mode == .chance && !chancePasses(beat: colStart, note: n, probability: prob) { continue }
                if mode == .harmonize {
                    emitHarmony(base: n, colour: treat, t: t, baseVel: 96, row: r, storeArtics: false,
                                busMask: hbm, on: onSample, off: offSample, beat: colStart,
                                windowEnd: windowEnd, out: out, diag: &diag)
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
                                  out: out, diag: &diag)
                    }
                } else {
                    emitArtic(note: UInt8(n), busMask: hbm,
                              onSample: onSample, offSample: offSample, windowEnd: windowEnd,
                              out: out, diag: &diag)
                }
            }
        }
        }
        // §2 CONTINUITY: close the drones this column did NOT re-hold (dropped notes / empty column), at the
        // boundary. Adopted voices were un-marked above and flow through untouched.
        for i in voices.indices where holdCandidate[i] { closeVoice(i, atSample: onSample, out: out) }
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
            if lapColumn(laneMask: heldColumns, absoluteStep: tickStep, trueColumn: tickTrueCol) != effColumn { continue }
            if tick == lastTick[row] { continue }
            lastTick[row] = tick

            let onTime = sampleOf(musical: mTickBeat, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                  windowStart: windowStart, S: S, a: a)
            let colEnd = (mTickBeat / S).rounded(.down) * S + S
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
                 laneMask: UInt8 = 0,
                 velOverride: UInt32 = 0,
                 heldCell: Int = -1,
                 tapAltMask: UInt64 = 0,
                 tapMuteMask: UInt64 = 0,
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
        self.tapAltMask = tapAltMask   // §9 item 1 ON TAP (unified ALT model): ephemeral per-cell alt flips
        self.tapMuteMask = tapMuteMask; self.soloEmitterMask = soloEmitterMask   // §9 item 1 ON TAP actions (4b)
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

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
            prevEffColumn = -1
            altLastOnset = .min; altMomentIndex = -1     // role family ALT/TURNS: a fresh play restarts the rotation at the first member
            passAnchor = 0                               // MULTI-SCENE S2b: a fresh play is absolute (no restart offset)
            wasPlaying = playing
        }
        // master panel PANIC: the one hard flush — close every voice + reset the column state, hang-kit-logged.
        if panic {
            allNotesOff(atSample: renderSampleImmediate, out: out, includeBypass: true)   // the one hard flush — bypass included
            prevEffColumn = -1
            diag.panics &+= 1
        }
        // MULTI-SCENE scene SWITCH flush: close the OLD scene's sounding notes so the new scene (this render's
        // new snapshot generation) starts clean — a generation change alone doesn't flush. NOT hang-logged.
        if sceneFlush {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevEffColumn = -1
        }
        // receiver strip LATCH edge: arming/disarming a receiver swaps the pool its subscribers read, so
        // close every voice and re-emit holds from the new effective pool (no stuck notes; on-edge re-strike).
        if latchMask != prevLatchMask {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevEffColumn = -1
            prevLatchMask = latchMask
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
            for i in lastTick.indices { lastTick[i] = -1 }      // free the solo row's tick-dedup
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
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
        }
        let beatPos = beatPos - passAnchor

        // ---- derived column (§7). Musical space, so swing warps the beat→column map consistently
        //      with the arp ticks below. The COLUMN-SUBSET LAP (§5b) warps WHICH column is effective
        //      (held keys); the TRUE timeline — pass, passgate, swing — is unwarped (all off mNow). ----
        let mNow = musicalOf(beatPos, stepBeats: S, a: a)
        let cycleBeats = Double(Snap.cols) * S
        let posInCycle = mNow - (mNow / cycleBeats).rounded(.down) * cycleBeats
        let trueColumn = min(Snap.cols - 1, max(0, Int(posInCycle / S)))
        let absoluteStep = Int((mNow / S).rounded(.down))          // global step counter (derived)
        let effColumn = lapColumn(laneMask: heldColumns, absoluteStep: absoluteStep, trueColumn: trueColumn)
        diag.effColumn = effColumn
        diag.absoluteStep = absoluteStep                           // LADDER commit signal: increments EACH step even during a column LAP (effColumn stays put)
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
                let boundaryMusical = (mNow / S).rounded(.down) * S     // start of effColumn
                let realB = realOf(boundaryMusical, stepBeats: S, a: a)
                let off = max(0, (realB - beatPos) / beatsPerSample)
                // §2 CONTINUITY: keep the legato drones alive across the boundary — emitColumnHolds reconciles
                // them (adopt the re-held, close the dropped). Everything else truncates here as before.
                closeExceptLegatoHolds(atSample: windowStart + Int64(off), out: out)
            }
            prevEffColumn = effColumn
            for r in lastTick.indices { lastTick[r] = -1; strumProgress[r] = 0 }
            emitColumnHolds(box: box, column: effColumn, pool: pool, pass: diag.pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        } else if heldColumns != 0 && pool.count == 0 && latchMask == 0 && anyLegatoHold() {
            // AUDIT B2: a SINGLE-COLUMN lap pins effColumn, so the column-change reconcile above never fires — a
            // source release then strands the legato drone (immortal) until the ~1s Kernel self-heal (+ a spurious
            // panic count). Run the reconcile now: with an empty pool it re-holds nothing and closes every orphaned
            // drone at the boundary. Scoped to an active lap (heldColumns != 0) so normal playback is untouched.
            emitColumnHolds(box: box, column: effColumn, pool: pool, pass: diag.pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        }

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
            if cell.colourIndex < 0 || cell.muted || cell.dormant || tapMuted(effColumn, r) { continue }   // §9 ON TAP = MUTE · LADDER dormant
            if soloSilenced(cell) { continue }   // receiver strip: input SOLO excludes this cell's receiver
            currentInputRecv = cell.resolvedReceiver   // receiver strip: this cell's receiver, for the input-vel override
            currentColourIndex = cell.colourIndex      // item 4 marks: this cell's Colour, for the source tint
            currentCellIndex = effColumn * Snap.rows + r  // SEAL comet: this cell's grid index (the sounding column)
            let ci = Int(cell.colourIndex)
            let colour = box.colours[ci]
            if !onSceneAudible(colour.on, pass: diag.pass) { continue }   // §9 item 1 ON SCENE: not entered / exited
            // §9 item 1 ON HOLD (3a): while THIS cell is press-held, its ALT/OCT treatment overlays momentarily.
            let held = heldCell >= 0 && heldCell == effColumn * Snap.rows + r
            let t = 0.0   // morph removed — the render reads the head params directly
            let transpose = colourTranspose(ci, colour)
                          + holdOctaveShift(on: colour.on, held: held)   // ON HOLD = OCT
                          + octaveShift(cell.resolvedReceiver)           // receiver strip: input OCT nudge
            // CELL MACHINE: the per-cell HEAD treatment (cell.proc) drives the render (morph + grid-chaining retired).
            var treat = colour; treat.a = cell.proc
            let mode = cellMode(type: effectiveType(treat, t: t), bypassed: cell.bypassed,
                                passMask: effectivePassMask(treat, t: t), pass: diag.pass)
            let emits = cell.busMask != 0   // fan-out across every lit bus happens inside emitArtic

            // CELL MACHINE stage-2: a covered chain (arp/ratchet/strum TAIL) runs the tail over the composed
            // upstream set; only the tail emits, and emitColumnHolds skips it.
            let driver = chainDriverIndex(cell)
            if driver >= 0 {
                let driveP = cell.procs[driver]                // the tick DRIVER (last tick-gen); slots before it compose, after it fold
                var treatDrive = colour; treatDrive.a = driveP
                switch driveP.type {
                case .arp:
                    emitArpRow(cell: cell, row: r, colour: treatDrive, t: t, transpose: transpose,
                               emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                               windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                               beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats,
                               chainDriver: driver, out: out, diag: &diag)
                case .ratchet:
                    emitRatchetRow(cell: cell, row: r, colour: treatDrive, t: t, transpose: transpose,
                                   emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                                   windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                                   beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats,
                                   chainDriver: driver, out: out, diag: &diag)
                case .strum:
                    emitStrumRow(cell: cell, row: r, colour: treatDrive, t: t, transpose: transpose, emits: emits,
                                 pool: pool, beatPos: beatPos, windowStart: windowStart, windowEnd: windowEnd,
                                 beatsPerSample: beatsPerSample, S: S, a: a, chainDriver: driver, out: out, diag: &diag)
                default: break
                }
                continue
            }
            if isHoldTailChain(cell) { continue }   // CELL MACHINE: a hold-tail chain emits at column boundaries (emitColumnHolds), not here

            switch mode {
            case .arp:
                emitArpRow(cell: cell, row: r, colour: treat, t: t, transpose: transpose,
                           emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                           windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                           beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .ratchet:
                emitRatchetRow(cell: cell, row: r, colour: treat, t: t, transpose: transpose,
                               emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                               windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                               beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .strum:
                emitStrumRow(cell: cell, row: r, colour: treat, t: t, transpose: transpose, emits: emits,
                             pool: pool, beatPos: beatPos, windowStart: windowStart, windowEnd: windowEnd,
                             beatsPerSample: beatsPerSample, S: S, a: a, out: out, diag: &diag)
            case .identity, .chance, .harmonize:
                break   // unfed hold types have no tick content — their hold is emitted at the column transition
            case .silent:
                break   // closed passgate → nothing this window
            }
        }
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding
    }

    // MARK: - CELL MACHINE (feat/EditPageSpike) stage-2 — the serial chain feed

    /// The chain's TICK DRIVER — the index of the LAST non-bypassed arp/ratchet/strum slot. It sets the rhythm:
    /// slots BEFORE it compose as its source; slots AFTER it FOLD onto each note it emits (a per-tick hold — a
    /// passgate gates the pass, chance drops, harmonize expands). -1 = no tick generator (a hold/plain cell). This
    /// is what makes `[arp → passgate]` keep arpeggiating (the arp drives, the passgate gates it) instead of the
    /// arp collapsing to one note when it isn't the tail.
    private func chainDriverIndex(_ cell: SnapCell) -> Int {
        guard cell.procs.count >= 2 else { return -1 }
        var i = cell.procs.count - 1
        while i >= 0 {
            if !cell.slotBypass[i] {
                let t = cell.procs[i].type
                if t == .arp || t == .ratchet || t == .strum { return i }
            }
            i -= 1
        }
        return -1
    }
    private func isCoveredChain(_ cell: SnapCell) -> Bool { chainDriverIndex(cell) >= 0 }
    /// A multi-slot chain whose TAIL holds at column boundaries via `emitColumnHolds` (holding the tail's
    /// transform of the composed upstream set): a bypassed tail (passthrough of the upstream set), or a
    /// gate/chance/harmonize tail. A non-bypassed STRUM tail is NOT covered yet → falls back to head-only.
    private func isHoldTailChain(_ cell: SnapCell) -> Bool {
        guard cell.procs.count >= 2, let last = cell.procs.last else { return false }
        if cell.slotBypass.last ?? false { return true }                 // bypassed tail = held passthrough
        switch last.type { case .passgate, .chance, .harmonize: return true; default: return false }
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
            let n = arpPickSource(phaseIndex: pIdx, octaves: Int(p.octaves), pattern: p.patternIndex,
                                  pool: src, filter: 0, cableMask: 0b1111)
            if n >= 0 && n <= 127 { dst.noteOn(UInt8(n), velocity: 96, channel: 0) }
        case .chance:
            let colStart = (m / S).rounded(.down) * S
            for k in 0..<src.srcCount(filter: 0, cableMask: 0b1111) {
                let n = src.srcAscending(k, filter: 0, cableMask: 0b1111)
                if chancePasses(beat: colStart, note: Int(n), probability: p.probability) { dst.noteOn(n, velocity: 96, channel: 0) }
            }
        case .harmonize:
            let ivs = [p.harmIntervals.0, p.harmIntervals.1, p.harmIntervals.2]
            for k in 0..<src.srcCount(filter: 0, cableMask: 0b1111) {
                let base = Int(src.srcAscending(k, filter: 0, cableMask: 0b1111))
                dst.noteOn(UInt8(base), velocity: 96, channel: 0)
                for iv in ivs where iv != 0 { let v = base + Int(iv); if v >= 0 && v <= 127 { dst.noteOn(UInt8(v), velocity: 96, channel: 0) } }
            }
        default:                                               // identity / open passgate / ratchet / strum → pass through
            for k in 0..<src.srcCount(filter: 0, cableMask: 0b1111) { dst.noteOn(src.srcAscending(k, filter: 0, cableMask: 0b1111), velocity: 96, channel: 0) }
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
        for k in 0..<pool.srcCount(for: cell) { cur.noteOn(pool.srcAscending(k, for: cell), velocity: 96, channel: 0) }
        cur.rebuildSorted()
        var j = 0
        while j <= upto {
            if !cell.slotBypass[j] {   // true-bypass: the set passes untouched
                let mode = cellMode(type: cell.procs[j].type, bypassed: false, passMask: cell.procs[j].passMask, pass: pass)
                nxt.reset()
                applyStage(cell.procs[j], mode: mode, src: cur, into: nxt, cell: cell, m: m, S: S, cycleBeats: cycleBeats)
                swap(&cur, &nxt)
            }
            j += 1
        }
        chainScratch.reset()
        for k in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) { chainScratch.noteOn(cur.srcAscending(k, filter: 0, cableMask: 0b1111), velocity: 96, channel: 0) }
        chainScratch.rebuildSorted()
    }

    /// Emit one note that the chain's DRIVER produced (at tick beat `m`), routed through the chain's POST-driver
    /// stages: when the driver is the tail it emits directly; otherwise the note is folded through slots
    /// driver+1…tail (passgate gates the pass → silence, chance drops, harmonize expands, bypassed passes) and
    /// each surviving note is emitted. Reuses chainA/chainB (fixed pools — no render-thread alloc); safe to call
    /// after composeChainSet has produced the driver's source (chainScratch is no longer needed by this tick).
    private func emitDriverNote(_ note: Int, cell: SnapCell, driver: Int, bm: UInt8,
                                onSample: Int64, offSample: Int64, windowEnd: Int64, velocity: UInt8,
                                m: Double, S: Double, cycleBeats: Double, pass: Int, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard note >= 0 && note <= 127 else { return }
        if driver >= cell.procs.count - 1 {                       // driver IS the tail → no post-stages
            emitChop(note, cell: cell, bm: bm, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: velocity, m: m, S: S, out: out, diag: &diag)
            return
        }
        // `pass` is the authoritative lap counter (diag.pass) — the SAME one a stand-alone passgate gates on, so a
        // downstream passgate opens/closes on the lap the user sees (not a beat-derived recomputation that can drift).
        var cur = chainA, nxt = chainB
        cur.reset(); cur.noteOn(UInt8(note), velocity: velocity, channel: 0); cur.rebuildSorted()
        var j = driver + 1
        while j < cell.procs.count {
            if !cell.slotBypass[j] {   // true-bypass passes untouched
                let mode = cellMode(type: cell.procs[j].type, bypassed: false, passMask: cell.procs[j].passMask, pass: pass)
                nxt.reset()
                applyStage(cell.procs[j], mode: mode, src: cur, into: nxt, cell: cell, m: m, S: S, cycleBeats: cycleBeats)
                swap(&cur, &nxt)
            }
            j += 1
        }
        for k in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) {
            emitChop(Int(cur.srcAscending(k, filter: 0, cableMask: 0b1111)), cell: cell, bm: bm,
                     onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: velocity, m: m, S: S, out: out, diag: &diag)
        }
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
    private func emitArpRow(cell: SnapCell, row r: Int, colour: SnapColour, t: Double, transpose: Int,
                            emits: Bool, box: SnapshotBox, pool: NotePool,
                            effColumn: Int, beatPos: Double, windowBeats: Double, windowStart: Int64,
                            windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                            chainDriver: Int = -1,
                            out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        var arpBeats = effectiveRateBeats(colour, t: t)
        let gate = effectiveGate(colour, t: t)
        let octaves = effectiveOctaves(colour, t: t)
        if arpBeats <= 0 { arpBeats = 0.25 }
        if r == diag.activeCellRow { diag.effMorphGold = t; diag.effRateBeats = arpBeats }

        iterateTicks(row: r, effColumn: effColumn, sub: arpBeats, gateFraction: gate,
                     beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                     beatsPerSample: beatsPerSample, S: S, a: a) { tick, mTickBeat, onTime, offTime in
            let pIdx = phaseIndex(tick: tick, mTickBeat: mTickBeat, arpBeats: arpBeats, S: S,
                                  cycleBeats: cycleBeats, phase: colour.a.phase,
                                  runStartColumn: cell.runStartColumn)
            let base: Int
            if chainDriver >= 0 {
                // CELL MACHINE: this ARP is the chain DRIVER — arp the composed SET of the stages BEFORE it at this
                // tick (OMNI, past the input filter). Derived per tick → pool-correct (arps ALL upstream voices).
                composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: mTickBeat, S: S, cycleBeats: cycleBeats)
                let b = arpPickSource(phaseIndex: pIdx, octaves: octaves, pattern: colour.a.patternIndex,
                                      pool: chainScratch, filter: 0, cableMask: 0b1111)
                guard b >= 0 else { return }
                base = b
            } else {
                base = arpPickSource(phaseIndex: pIdx, octaves: octaves,
                                     pattern: colour.a.patternIndex, pool: pool, for: cell)   // §7 source filter
                guard base >= 0 else { return }
            }
            let noteValue = base + transpose
            guard noteValue >= 0 && noteValue <= 127 else { return }
            storeArtic(row: r, on: onTime, off: offTime, note: UInt8(noteValue), beat: mTickBeat)
            if emits {
                // §cell-edit F CHOP + the chain's post-driver stages fold onto each arp note (e.g. a downstream passgate).
                if chainDriver >= 0 {
                    emitDriverNote(noteValue, cell: cell, driver: chainDriver, bm: bm, onSample: onTime, offSample: offTime,
                                   windowEnd: windowEnd, velocity: 96, m: mTickBeat, S: S, cycleBeats: cycleBeats, pass: diag.pass, out: out, diag: &diag)
                } else {
                    emitChop(noteValue, cell: cell, bm: bm, onSample: onTime, offSample: offTime, windowEnd: windowEnd,
                             velocity: 96, m: mTickBeat, S: S, out: out, diag: &diag)
                }
            }
        }
    }

    /// RATCHET (§3): re-strike the WHOLE input pool `repeats` times per column, staccato (0.6), velocity ramp.
    /// Not an arp (no index cycling) — every stab is the pool (or the parent's sounding note, when referenced).
    private func emitRatchetRow(cell: SnapCell, row r: Int, colour: SnapColour, t: Double, transpose: Int,
                                emits: Bool, box: SnapshotBox, pool: NotePool,
                                effColumn: Int, beatPos: Double, windowBeats: Double, windowStart: Int64,
                                windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                                chainDriver: Int = -1,
                                out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        let repeats = effectiveRepeats(colour, t: t)
        let ramp = effectiveRamp(colour, t: t)
        let sub = S / Double(repeats)                          // one repeat every `sub` beats
        if r == diag.activeCellRow { diag.effMorphGold = t; diag.effRateBeats = sub }

        iterateTicks(row: r, effColumn: effColumn, sub: sub, gateFraction: 0.6,
                     beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                     beatsPerSample: beatsPerSample, S: S, a: a) { _, mTickBeat, onTime, offTime in
            let colStart = (mTickBeat / S).rounded(.down) * S
            let repIdx = Int(((mTickBeat - colStart) / sub).rounded())    // 0…repeats-1
            let vel = ratchetVelocity(base: 96, ramp: ramp, index: repIdx, count: repeats)
            // §cell-edit F CHOP: this ratchet repeat routes by which of the 8 column slices it lands in.
            let tbm = chopMask(cell, m: mTickBeat, S: S, base: bm)
            if emits && tbm == 0 { return }                   // MUTE slice → this repeat is silent
            if chainDriver >= 0 {
                // CELL MACHINE: RATCHET chain DRIVER — re-strike the composed set of the stages BEFORE it at this
                // repeat, then fold each struck note through the stages AFTER it (e.g. a downstream passgate).
                composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: mTickBeat, S: S, cycleBeats: cycleBeats)
                for k in 0..<chainScratch.srcCount(filter: 0, cableMask: 0b1111) {
                    let n = Int(chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111)) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    storeArtic(row: r, on: onTime, off: offTime, note: UInt8(n), beat: mTickBeat)
                    if emits {
                        emitDriverNote(n, cell: cell, driver: chainDriver, bm: bm, onSample: onTime, offSample: offTime,   // raw bm — emitChop applies the slice
                                       windowEnd: windowEnd, velocity: vel, m: mTickBeat, S: S, cycleBeats: cycleBeats, pass: diag.pass, out: out, diag: &diag)
                    }
                }
            } else {
                let srcN = pool.srcCount(for: cell)            // re-strike every held note passing the filter (§7)
                for k in 0..<srcN {
                    let n = Int(pool.srcAscending(k, for: cell)) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    storeArtic(row: r, on: onTime, off: offTime, note: UInt8(n), beat: mTickBeat)
                    if emits {
                        emitArtic(note: UInt8(n), busMask: tbm, onSample: onTime, offSample: offTime,
                                  windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                    }
                }
            }
        }
    }

    /// STRUM (§3): stagger the source chord's onsets over `spread` beats from the column start, held to the
    /// boundary. Emitted per-window as each onset arrives (strumProgress, reset per column) — each note fires once.
    private func emitStrumRow(cell: SnapCell, row r: Int, colour: SnapColour, t: Double, transpose: Int,
                              emits: Bool, pool: NotePool, beatPos: Double, windowStart: Int64, windowEnd: Int64,
                              beatsPerSample: Double, S: Double, a: Double, chainDriver: Int = -1,
                              out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: colour.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        let spread = effectiveSpread(colour, t: t)
        let curve = colour.a.curve, tilt = colour.a.velTilt, dir = colour.a.strumDir
        let colStart = (musicalOf(beatPos, stepBeats: S, a: a) / S).rounded(.down) * S
        let cycleBeats = Double(Snap.cols) * S
        // CELL MACHINE: a STRUM chain DRIVER staggers the composed set of the stages BEFORE it (derived once at colStart).
        if chainDriver >= 0 { composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: colStart, S: S, cycleBeats: cycleBeats) }
        let count = chainDriver >= 0 ? chainScratch.srcCount(filter: 0, cableMask: 0b1111) : pool.srcCount(for: cell)   // §7 source filter
        if r == diag.activeCellRow { diag.effMorphGold = t; diag.effRateBeats = spread }
        guard count > 0 else { return }

        let offSample = sampleOf(musical: colStart + S, beatPos: beatPos,       // held to boundary
                                 beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        while strumProgress[r] < count {
            let j = strumProgress[r]
            let onsetMusical = colStart + strumOffset(index: j, count: count, spread: spread, curve: curve)
            let onsetSample = sampleOf(musical: onsetMusical, beatPos: beatPos,
                                       beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            if onsetSample >= windowEnd { break }        // onset lands in a later window
            strumProgress[r] += 1

            let sortedIdx = strumSortedIndex(position: j, count: count, direction: dir, pass: diag.pass)
            let n = Int(chainDriver >= 0 ? chainScratch.srcAscending(sortedIdx, filter: 0, cableMask: 0b1111) : pool.srcAscending(sortedIdx, for: cell)) + transpose
            guard n >= 0 && n <= 127 else { continue }
            let vel = strumVelocity(index: j, count: count, tilt: tilt, base: 96)
            let onT = max(onsetSample, windowStart)
            storeArtic(row: r, on: onT, off: offSample, note: UInt8(n), beat: onsetMusical)
            if emits {
                if chainDriver >= 0 {   // fold each strummed note through the stages AFTER the strum (e.g. a downstream passgate)
                    emitDriverNote(n, cell: cell, driver: chainDriver, bm: bm, onSample: onT, offSample: offSample,
                                   windowEnd: windowEnd, velocity: vel, m: onsetMusical, S: S, cycleBeats: cycleBeats, pass: diag.pass, out: out, diag: &diag)
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
        let t = 0.0   // morph removed
        let transpose = colourTranspose(ci, colour)
        previewMode = true; defer { previewMode = false }
        guard effectiveType(colour, t: t) == .arp else { return }
        var arpBeats = effectiveRateBeats(colour, t: t); if arpBeats <= 0 { arpBeats = 0.25 }
        let gate = effectiveGate(colour, t: t)
        let octaves = effectiveOctaves(colour, t: t)
        auditionTicks(sub: arpBeats, gateFraction: gate, startBeat: clockBeat, windowBeats: windowBeats,
                      windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
            let base = arpPickSource(phaseIndex: tick, octaves: octaves, pattern: colour.a.patternIndex,
                                     pool: pool, filter: UInt8(clamping: filter))
            guard base >= 0 else { return }
            let n = base + transpose; guard n >= 0 && n <= 127 else { return }
            emitArtic(note: UInt8(n), busMask: busMask, onSample: onT, offSample: offT, windowEnd: windowEnd, out: out, diag: &diag)
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
        let t = 0.0                                       // morph removed
        let transpose = colourTranspose(ci, colour)
        let vr = 0                                        // virtual tick-dedup row (grid-chaining retired: always source-fed)
        let f = UInt8(clamping: filter)
        previewMode = true; defer { previewMode = false }
        let mode = cellMode(type: effectiveType(colour, t: t), bypassed: false,
                            passMask: effectivePassMask(colour, t: t), pass: diag.pass)

        // Virtual-cell COLUMN TRANSITION: truncate its voices at the boundary, reset per-column state, and
        // (chord-hold types on SOURCE input) emit the treated held chord sustained to the column boundary.
        if effColumn != previewPrevColumn {
            let mNow = musicalOf(beatPos, stepBeats: S, a: a)
            if anyVoiceActive() {
                let boundaryMusical = (mNow / S).rounded(.down) * S
                let off = max(0, (realOf(boundaryMusical, stepBeats: S, a: a) - beatPos) / beatsPerSample)
                allNotesOff(atSample: windowStart + Int64(off), out: out)
            }
            previewPrevColumn = effColumn
            lastTick[vr] = -1; strumProgress[vr] = 0
            if mode == .identity || mode == .chance || mode == .harmonize {
                previewChordHold(isChance: mode == .chance, isHarmonize: mode == .harmonize, colour: colour, t: t,
                                 transpose: transpose, filter: f, busMask: busMask, mNow: mNow, beatPos: beatPos,
                                 beatsPerSample: beatsPerSample, S: S, a: a, windowStart: windowStart,
                                 windowEnd: windowEnd, pool: pool, out: out, diag: &diag)
            }
        }

        switch mode {
        case .arp:
            var arpBeats = effectiveRateBeats(colour, t: t); if arpBeats <= 0 { arpBeats = 0.25 }
            let gate = effectiveGate(colour, t: t)
            let octaves = effectiveOctaves(colour, t: t)
            iterateTicks(row: vr, effColumn: effColumn, sub: arpBeats, gateFraction: gate, beatPos: beatPos,
                         windowBeats: windowBeats, windowStart: windowStart, beatsPerSample: beatsPerSample, S: S, a: a) { tick, mTickBeat, onTime, offTime in
                let pIdx = phaseIndex(tick: tick, mTickBeat: mTickBeat, arpBeats: arpBeats, S: S,
                                      cycleBeats: cycleBeats, phase: colour.a.phase, runStartColumn: -1)
                let base = arpPickSource(phaseIndex: pIdx, octaves: octaves, pattern: colour.a.patternIndex, pool: pool, filter: f)
                guard base >= 0 else { return }
                let n = base + transpose; guard n >= 0 && n <= 127 else { return }
                emitArtic(note: UInt8(n), busMask: busMask, onSample: onTime, offSample: offTime, windowEnd: windowEnd, out: out, diag: &diag)
            }
        case .ratchet:
            let repeats = effectiveRepeats(colour, t: t)
            let ramp = effectiveRamp(colour, t: t)
            let sub = S / Double(max(1, repeats))
            iterateTicks(row: vr, effColumn: effColumn, sub: sub, gateFraction: 0.6, beatPos: beatPos,
                         windowBeats: windowBeats, windowStart: windowStart, beatsPerSample: beatsPerSample, S: S, a: a) { _, mTickBeat, onTime, offTime in
                let colStart = (mTickBeat / S).rounded(.down) * S
                let repIdx = Int(((mTickBeat - colStart) / sub).rounded())
                let vel = ratchetVelocity(base: 96, ramp: ramp, index: repIdx, count: repeats)
                let srcN = pool.srcCount(filter: f)
                for k in 0..<srcN {
                    let n = Int(pool.srcAscending(k, filter: f)) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    emitArtic(note: UInt8(n), busMask: busMask, onSample: onTime, offSample: offTime, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        case .strum:
            let spread = effectiveSpread(colour, t: t)
            let curve = colour.a.curve, tilt = colour.a.velTilt, dir = colour.a.strumDir
            let count = pool.srcCount(filter: f)   // STRUM is source-based (no row-feed, matching the real loop)
            if count > 0 {
                let colStart = (musicalOf(beatPos, stepBeats: S, a: a) / S).rounded(.down) * S
                let offSample = sampleOf(musical: colStart + S, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                while strumProgress[vr] < count {
                    let j = strumProgress[vr]
                    let onsetMusical = colStart + strumOffset(index: j, count: count, spread: spread, curve: curve)
                    let onsetSample = sampleOf(musical: onsetMusical, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    if onsetSample >= windowEnd { break }
                    strumProgress[vr] += 1
                    let sortedIdx = strumSortedIndex(position: j, count: count, direction: dir, pass: diag.pass)
                    let n = Int(pool.srcAscending(sortedIdx, filter: f)) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    let vel = strumVelocity(index: j, count: count, tilt: tilt, base: 96)
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
    private func previewChordHold(isChance: Bool, isHarmonize: Bool, colour: SnapColour, t: Double, transpose: Int,
                                  filter: UInt8, busMask: UInt8, mNow: Double, beatPos: Double, beatsPerSample: Double,
                                  S: Double, a: Double, windowStart: Int64, windowEnd: Int64, pool: NotePool,
                                  out: MIDIEmitter?, diag: inout KernelDiag) {
        let colStart = (mNow / S).rounded(.down) * S
        let onSample = sampleOf(musical: colStart, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        let offSample = sampleOf(musical: colStart + S, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        let prob = isChance ? effectiveProbability(colour, t: t) : 1
        let srcN = pool.srcCount(filter: filter)
        for k in 0..<srcN {
            let n = Int(pool.srcAscending(k, filter: filter)) + transpose
            guard n >= 0 && n <= 127 else { continue }
            if isChance && !chancePasses(beat: colStart, note: n, probability: prob) { continue }
            if isHarmonize {
                emitHarmony(base: n, colour: colour, t: t, baseVel: 96, row: 0, storeArtics: false,
                            busMask: busMask, on: onSample, off: offSample, beat: colStart, windowEnd: windowEnd, out: out, diag: &diag)
            } else {
                emitArtic(note: UInt8(n), busMask: busMask, onSample: onSample, offSample: offSample, windowEnd: windowEnd, out: out, diag: &diag)
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
        let t = 0.0   // morph removed
        let transpose = colourTranspose(ci, colour)

        switch effectiveType(treat, t: t) {
        case .arp:
            var arpBeats = effectiveRateBeats(treat, t: t); if arpBeats <= 0 { arpBeats = 0.25 }
            let gate = effectiveGate(treat, t: t)
            let octaves = effectiveOctaves(treat, t: t)
            auditionTicks(sub: arpBeats, gateFraction: gate, startBeat: auditionBeat, windowBeats: windowBeats,
                          windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
                let base = arpPickSource(phaseIndex: tick, octaves: octaves,   // phase zeroed: index = ticks since hold
                                         pattern: treat.a.patternIndex, pool: pool, for: cell)
                guard base >= 0 else { return }
                let n = base + transpose; guard n >= 0 && n <= 127 else { return }
                emitArtic(note: UInt8(n), busMask: cell.busMask, onSample: onT, offSample: offT,
                          windowEnd: windowEnd, out: out, diag: &diag)
            }
        case .ratchet:
            let repeats = effectiveRepeats(treat, t: t)
            let ramp = effectiveRamp(treat, t: t)
            let sub = S / Double(max(1, repeats))
            auditionTicks(sub: sub, gateFraction: 0.6, startBeat: auditionBeat, windowBeats: windowBeats,
                          windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
                let repIdx = ((Int(tick) % repeats) + repeats) % repeats
                let vel = ratchetVelocity(base: 96, ramp: ramp, index: repIdx, count: repeats)
                let srcN = pool.srcCount(for: cell)
                for k in 0..<srcN {
                    let n = Int(pool.srcAscending(k, for: cell)) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    emitArtic(note: UInt8(n), busMask: cell.busMask, onSample: onT, offSample: offT,
                              windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
        case .strum:
            // STRUM: roll the held chord in over `spread` beats from the hold (its own onset per note),
            // then sustain — the audition clock drives the roll; reconcile tracks live key changes.
            auditionStrum(cell: cell, colour: treat, pool: pool, transpose: transpose, t: t,
                          auditionBeat: auditionBeat, windowEnd: windowEnd, out: out, diag: &diag)
        default:
            // chord-hold types (passgate all-open / chance / harmonize): sustain the treated chord,
            // reconciled to the live held source each window (v2).
            auditionChordHold(cell: cell, colour: treat, pool: pool, transpose: transpose, t: t,
                              windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        }
    }

    /// Sustain the held source chord through a chord-hold treatment (§6.4), tracking the keys LIVE:
    /// build the note-set the source should sound through the treatment, then reconcile against what is
    /// currently sounding — close departed notes, open new ones (sustained; released by allNotesOff on
    /// hold-change / transport-start). passgate is forced all-open; chance seeds on the hold (beat 0) so
    /// each note is deterministically in or out for the whole hold; harmonize expands to its voices.
    private func auditionChordHold(cell: SnapCell, colour: SnapColour, pool: NotePool,
                                   transpose: Int, t: Double, windowStart: Int64, windowEnd: Int64,
                                   out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionDesired[i] = false }
        let type = effectiveType(colour, t: t)
        let prob = (type == .chance) ? effectiveProbability(colour, t: t) : 1
        let srcN = pool.srcCount(for: cell)         // §7 source filter, forced source
        for k in 0..<srcN {
            let base = Int(pool.srcAscending(k, for: cell)) + transpose
            guard base >= 0 && base <= 127 else { continue }
            switch type {
            case .harmonize:
                let iv = (Int8(effectiveHarmInterval(colour, voice: 0, t: t)),
                          Int8(effectiveHarmInterval(colour, voice: 1, t: t)),
                          Int8(effectiveHarmInterval(colour, voice: 2, t: t)))
                let cnt = harmonizeVoices(base: base, intervals: iv, into: &harmNotes,
                                          vel: 96, velScale: effectiveHarmVelScale(colour, t: t), vels: &harmVels)
                for j in 0..<cnt where harmNotes[j] >= 0 && harmNotes[j] <= 127 {
                    auditionDesired[harmNotes[j]] = true; auditionVel[harmNotes[j]] = harmVels[j]
                }
            case .chance:
                if chancePasses(beat: 0, note: base, probability: prob) { auditionDesired[base] = true; auditionVel[base] = 96 }
            default:                                                 // passgate all-open (sustain the chord)
                auditionDesired[base] = true; auditionVel[base] = 96
            }
        }
        reconcileAuditionVoices(busMask: cell.busMask, windowEnd: windowEnd, out: out, diag: &diag)
    }

    /// STRUM audition: the held chord ROLLS in — each note has its own onset (`strumOffset`) measured
    /// from the hold; a note joins the sustained set once the audition clock passes its onset. So the
    /// first hold rolls the chord; thereafter it sustains and reconcile tracks live key changes. No
    /// columns here, so direction uses pass 0 and notes never auto-release (offSample .max).
    private func auditionStrum(cell: SnapCell, colour: SnapColour, pool: NotePool,
                               transpose: Int, t: Double, auditionBeat: Double,
                               windowEnd: Int64, out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionDesired[i] = false }
        let spread = effectiveSpread(colour, t: t)
        let count = pool.srcCount(for: cell)
        for j in 0..<count {
            guard auditionBeat >= strumOffset(index: j, count: count, spread: spread, curve: colour.a.curve)
            else { continue }                                   // this note's onset hasn't arrived yet
            let sortedIdx = strumSortedIndex(position: j, count: count, direction: colour.a.strumDir, pass: 0)
            let n = Int(pool.srcAscending(sortedIdx, for: cell)) + transpose
            guard n >= 0 && n <= 127 else { continue }
            auditionDesired[n] = true
            auditionVel[n] = strumVelocity(index: j, count: count, tilt: colour.a.velTilt, base: 96)
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
