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

    // Render-side parameter overrides (§7 second route) — this is the Router's OWN compact slot numbering, NOT the AU
    // tree addresses. Slots: 0 stepRate · 1 swing · 2+i transpose(i) · 18+i morph(i) · 34 morphMaster.
    // NOTE: the morph slots (18+i, 34) are now DEAD — the morph AU params were removed 2026-09-16, so no host
    // .parameter event ever targets them; transpose (2+i) is the only live per-machine override. Array kept at 35.
    private var overrides = [Double](repeating: .nan, count: 35)
    private var overrideGen: UInt64 = .max
    // §7 RAMP SMOOTHING: a .parameterRamp event (host automation draws a line, not a step) arms a linear
    // interpolation instead of snapping `overrides[idx]` immediately. rampDurationSamples[i] == 0 is the
    // sentinel for "no ramp in flight at slot i" — tickRamps() skips those slots entirely (cheap, no branch
    // cost beyond the guard). Fixed-size, parallel to `overrides`; no allocation on the render path.
    private var rampFrom = [Double](repeating: 0, count: 35)
    private var rampTo = [Double](repeating: 0, count: 35)
    private var rampStartSample = [Int64](repeating: 0, count: 35)
    private var rampDurationSamples = [Int64](repeating: 0, count: 35)

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
        // MACHINE-AND-FACE (machineIndex + alt). At a column boundary a re-held identical voice is ADOPTED
        // (kept, no off/on); a changed one closes and the new one strikes. Stamped for every voice
        // (harmless on non-hold voices — only audible immortal voices are ever adoption-matched).
        var machineIndex: Int16 = -1   // CR-13a: Int16 (was Int8) — matches SnapCell; a machine index can exceed 127
        var alt = false
        var vel: UInt8 = 0           // §strips-done: the emit velocity, for the per-emitter hold-while-sounding feed
        var onBeat: Double = 0       // PART ROW ROLL (Paul 2026-09-29): true onset beat (raw, un-swing-warped) — the
                                     // exact focusNoteBeat formula, stamped in openVoice. 0 on a fresh/inactive slot
                                     // (harmless — only ever read while active).
        var cellIndex: Int16 = -1    // SEAL comet: the emitting cell's grid index (col*Snap.rows+row). Int16 (was Int8, whose 127 ceiling = the exact 7*16+15 cell max) so a 16-COLUMN grid (index up to 15*16+15 = 255) doesn't overflow — the grid-8|16 groundwork (2026-08-31)
                                     // SOUNDING gate — the spark travels for exactly as long as the note is held.
        var bypassRecv: Int8 = -1    // BYPASS: ≥0 = a direct-injection voice for that receiver (IMMORTAL, managed by
                                     // reconcileBypass) — the grid's continuity + transport flushes leave it alone.
        var glideAnchor = false      // GLIDE: a direct-injection glide voice (IMMORTAL, managed by the glide subsystem —
                                     // emitColumnGlide/emitGlideDriven + flushGlide). Like bypassRecv, the hold-continuity
                                     // boundary-close must SKIP it, else a glide note sustained across a column boundary
                                     // is wrongly cut (marked a holdCandidate, no hold cell adopts it → closed). BUG fix
                                     // 2026-08-29. Set from `meter` in openVoice (the two flag the identical voice set).
        var rtcHold = false          // RATCHET PATTERN standalone (Paul 2026-09-08): an IMMORTAL pass-through sustain voice
                                     // owned entirely by emitColumnRatchetPattern (a stateless per-window diff-reconcile, like
                                     // reconcileBypass). Excluded from the grid hold-reconcile (emitColumnHolds candidate loop)
                                     // so the grid boundary never closes it; allNotesOff closes it on every transport/scene edge.
    }
    private var voices = [Voice](repeating: Voice(), count: 128)

    // Collision refcount (§7, normative): per (bus, channel, note). Note-ONs always emit
    // (re-articulation is audible truth); the wire note-OFF is emitted only when the LAST instance
    // releases — so a sustained note never drops under a same-pitch arp. 4 buses × 16 ch × 128 notes.
    // 5 cables now (delta §7b): 0 = ALL, 1–4 = A–D.
    private var refcount = [UInt8](repeating: 0, count: 5 * 16 * 128)
    private var distinctSounding = 0   // number of (cable,ch,note) with refcount > 0 (diag; kept incrementally)

    private var busChannels: [UInt8] = [1, 2, 3, 4]   // per-bus stamp channels, refreshed each process
    private var busRemap: [UInt8] = [0, 1, 2, 3]      // ROW 8 REDIRECT/SWAP: per-bus output-wire remap (identity = no redirect), refreshed each process
    private var broadcastActive = false               // ROW 8 BROADCAST: mirror every emitted note to all 4 wires, refreshed each process
    private var broadcastAll16 = false                // ROW 8 BROADCAST (Paul 2026-08-26): also fan the ALL-cable copy across all 16 channels
    private var heldColumns: UInt16 = 0   // §5b COLUMN-SUBSET LAP: held column keys (bit i = column i),
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
        return clampVel(Int((mapped * 127.0).rounded()))
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
    // AVOID / LOCK (unified 2026-08-31): the 12-bit PITCH-CLASS set the voice table is sounding — `bus` nil = every
    // emitter (ALL SOUNDING), else one wire. The live-query model of HOCKET/CONVERSATION: it sees what earlier rows have
    // emitted SO FAR this render (the L1 caveat — put the avoider on a LATER row than its source). Excludes silent ghosts.
    private func soundingPitchClassMask(bus: Int?) -> UInt16 {
        var m: UInt16 = 0
        for v in voices where v.active && !v.silent && (bus == nil || Int(v.bus) == bus!) { m |= UInt16(1) << UInt16(Int(v.note) % 12) }
        return m
    }
    // AVOID DOOR reference: the live input pool this render, so a DOOR-referenced AVOID can read what ANOTHER receiver is
    // playing RIGHT NOW (Paul's "listen to a different receiver"). A held reference to the render's NotePool (a class),
    // valid only during process (where avoidRefMask runs). The door's own channel/cable/range filter selects its notes.
    private weak var avoidLivePool: NotePool?
    private func doorLivePitchClassMask(_ r: Int) -> UInt16 {
        guard let pool = avoidLivePool, r >= 0, r < receiverChannels.count else { return 0 }
        let filter = receiverChannels[r], cable = Int(receiverCables[r]), lo = r < receiverRangeLo.count ? receiverRangeLo[r] : 0, hi = r < receiverRangeHi.count ? receiverRangeHi[r] : 127
        var m: UInt16 = 0
        for k in 0..<pool.srcCount(filter: filter, cableMask: cable, velLo: 0, velHi: 127, noteLo: lo, noteHi: hi) {
            m |= UInt16(1) << UInt16(Int(pool.srcAscending(k, filter: filter, cableMask: cable, velLo: 0, velHi: 127, noteLo: lo, noteHi: hi)) % 12)
        }
        return m
    }
    // The pitch classes a DOOR contributes as a reference: its latched/SCALE pool if frozen, else its live THRU input.
    @inline(__always) private func doorRefMask(_ d: Int) -> UInt16 {
        let latched = d >= 0 && d < latchedPools.count ? latchedPools[d].pitchClassMaskAll() : 0
        return latched != 0 ? latched : doorLivePitchClassMask(d)
    }
    /// The reference PITCH-CLASS set an AVOID/LOCK stage tests against: a declared KEY · another DOOR (its latched/SCALE
    /// pool if present, else its LIVE input) · a WIRE's live output · EVERYTHING = every OTHER input door (never this
    /// chain's own receiver — Paul 2026-08-31: "everything except its own receiver"; input-domain, so it MATCHES the
    /// editor piano's prediction and can never avoid itself). `ownDoor` = the AVOID cell's receiver. Computed once per fold.
    private func avoidRefMask(_ p: SnapParams, ownDoor: Int, ownBusMask: UInt8) -> UInt16 {
        let base: UInt16
        switch p.avoidRefKind {
        case .key:      base = scalePitchClassMask(root: p.avoidRoot, scale: p.avoidScale)
        case .door:     base = doorRefMask(max(0, min(3, p.avoidRefIndex)))
        case .wire:     base = soundingPitchClassMask(bus: max(0, min(3, p.avoidRefIndex)))   // OUTPUT ▸A–D: a specific emitter's live output
        case .sounding: var m: UInt16 = 0; for d in 0..<4 where d != ownDoor { m |= doorRefMask(d) }; base = m   // EVERYTHING IN = the union of every OTHER input door
        case .soundingOut:                                                                    // §G EVERYTHING OUT = all emitter output EXCEPT this cell's OWN buses (self-exclude by BUS)
            var m: UInt16 = 0; for b in 0..<4 where (ownBusMask >> UInt8(b)) & 1 == 0 { m |= soundingPitchClassMask(bus: b) }; base = m
        }
        // WHAT (AVOID mode only): widen the avoided sphere to the CLASHING neighbours (ic1/ic2). LOCK keeps the exact set.
        return (!p.avoidLock && p.avoidClashSemis > 0) ? widenClashMask(base, semis: p.avoidClashSemis) : base
    }
    /// Apply an AVOID/LOCK stage to ONE note: keep it, remap it (MOVE), or drop it (REMOVE → nil).
    /// LOCK keeps/snaps to the reference (musical — it IS the referenced key). AVOID drops notes in the blocked sphere;
    /// MOVE snaps a blocked note to the nearest SURVIVING note in the INPUT SCALE (`survivorMask` = the pool's passing
    /// classes) — never a chromatic note outside the pool (Paul 2026-08-31: this is a scale processor, so MOVE stays in key).
    @inline(__always) private func avoidFilter(_ note: Int, _ p: SnapParams, refMask: UInt16, survivorMask: UInt16) -> Int? {
        if p.avoidLock { return keyFilterNote(note, refMask: refMask, only: true, snap: p.avoidMove) }
        let pc = ((note % 12) + 12) % 12
        if (refMask >> UInt16(pc)) & 1 == 0 { return note }                 // not blocked → passes through
        guard p.avoidMove, survivorMask != 0 else { return nil }            // DROP (or nothing survives to move onto)
        return keyFilterNote(note, refMask: survivorMask, only: true, snap: true)   // snap to the nearest surviving scale note
    }
    /// The INPUT-scale classes that PASS an AVOID stage (a note's class ∉ the blocked sphere) — MOVE's legal landing set.
    @inline(__always) private func avoidSurvivors(_ notes: (Int) -> Int, count: Int, refMask: UInt16) -> UInt16 {
        var m: UInt16 = 0
        for k in 0..<count { let pc = ((notes(k) % 12) + 12) % 12; if (refMask >> UInt16(pc)) & 1 == 0 { m |= UInt16(1) << UInt16(pc) } }
        return m
    }
    // HOCKET (wire-as-source v1): the sample of the most recent REAL note-on on each emitter (A–D) — the "when the wire
    // struck" edge that TRADE reads. Updated in openVoice; reset to a far-past sentinel on transport/flush edges so a
    // stale onset can't false-trigger. Read-only from HOCKET's tick (same live-query model as CONVERSATION's L1 caveat).
    private var emitterLastOnsetSample = [Int64](repeating: .min, count: 4)
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
    // item 4 VELOCITY MARKS: per emitter, a bounded buffer of recent note-on (velocity, source machineIndex)
    // since the last drain — the UI holds+fades each as a floating mark tinted by the source Machine. Fixed
    // scratch (no render alloc); fills to 8 per poll cycle then drops (drained ~4 Hz, so 8 is ample).
    // FLAT 4×8 (index bus*8+i). These render→main feeds MUST NOT be nested `[[…]]`: the render thread's nested-array
    // element write churns the INNER arrays' refcounts while the 4 Hz main-thread drain reads them → an ARC data race
    // → libmalloc free-block corruption (device crash 2026-08-10 in drainEmitterSounding). A FLAT value array has no
    // inner-array ARC, so the only residual race is a torn value read (benign — a stale meter mark). (see memory)
    private var markVel = [UInt8](repeating: 0, count: 32)
    private var markCol = [Int8](repeating: -1, count: 32)
    private var markCount = [Int](repeating: 0, count: 4)
    // §6a THE WITHHELD TELL: a parallel bounded buffer of note-ons SUPPRESSED by CLAIM (leak 0) since the last
    // drain — same (velocity, source machineIndex) shape. The UI renders these HOLLOW + a claim-hue tick so a
    // suppressed note reads as "withheld here", not a silent bug. Only full CLAIM suppression records (a LEAK
    // shadow already sounds as a dimmer mark; solo/mute/disabled are intentional silences, not withholdings).
    private var withheldVel = [UInt8](repeating: 0, count: 32)   // FLAT 4×8 (index bus*8+i) — see markVel note (render↔main ARC-safe)
    private var withheldCol = [Int8](repeating: -1, count: 32)
    private var withheldCount = [Int](repeating: 0, count: 4)
    // §strips-done (the emitter twin of the receiver's recvHeld): the notes CURRENTLY SOUNDING per emitter — a
    // live snapshot of the voice table sliced by bus, each carrying (velocity, source machineIndex) so the UI
    // draws a hold-while-sounding tick in the SOURCE Machine (cargo tint) and fades it on release. Snapshotted on
    // the render thread each window; read-and-copied by the UI poll (benign staleness race, like the meters).
    private var soundVel = [UInt8](repeating: 0, count: 48)   // FLAT 4×12 (index bus*12+i) — see markVel note (render↔main ARC-safe)
    private var soundCol = [Int8](repeating: -1, count: 48)
    private var soundCount = [Int](repeating: 0, count: 4)
    private var currentMachineIndex: Int16 = -1        // the emitting cell's machineIndex (for the SEAL comet feed) — CR-13a Int16
    private var curBox: SnapshotBox?                  // this render's box — so openVoice can read the sounding machine's DISPLAY hue to tag the reel (Paul 2026-08-19)
    // THE SEAL COMET: per-CELL peak note velocity since the last drain (index = col*Snap.rows+row) — the grid comet's
    // motion signal. Accumulated on the render thread at the emit boundary, read-and-cleared by the UI poll (the
    // UI owns the ~1s decay). `currentCellIndex` is the emitting cell's grid index, set per-cell in the emit loops.
    private var cellStrike = [UInt8](repeating: 0, count: Snap.cells)   // Snap.cells = 256 (maxCols·rows = 16·16; index col*rows+row)
    // THE NOTE-SWEEP feed (Paul 2026-08-19): per-cell RECENT emitted note-ons (pitch + velocity), a small ring per cell.
    // Drained read-and-clear like the strike feed → the piano-roll faces place marks at REAL pitch (not a hash), and the
    // BUILD note-sweep CONTOUR axis gets its per-note pitch. Fixed storage; no allocation on the render path.
    private var cellNotePitch = [UInt8](repeating: 0, count: Snap.cells * 6)
    private var cellNoteVel   = [UInt8](repeating: 0, count: Snap.cells * 6)
    private var cellNoteHead  = [Int](repeating: 0, count: Snap.cells)     // ring write cursor per cell
    private var cellNoteNew   = [UInt8](repeating: 0, count: Snap.cells)   // note-ons written since the last drain (return capped at 6)
    private var currentCellIndex: Int = -1
    // THE FOCUS-CELL note-EVENT feed (Paul 2026-08-31): for the ONE cell shown in the machine (focusCellIdx), a bigger ring of
    // recent emitted note-ons WITH their musical BEAT — so the chain-flow comets animate the REAL notes at REAL timing (not an
    // offline simulation). FLAT scalar arrays (invariant 3 crash-fix: never nested [[…]]); read-and-clear via drainFocusNotes.
    private static let focusRing = 64
    private var focusCellIdx: Int = -1
    private var focusNotePitch = [UInt8](repeating: 0, count: Router.focusRing)
    private var focusNoteVel   = [UInt8](repeating: 0, count: Router.focusRing)
    private var focusNoteBeat  = [Double](repeating: 0, count: Router.focusRing)
    private var focusNoteHead  = 0
    private var focusNoteNew   = 0
    private var fBeatPos: Double = 0, fBeatsPerSample: Double = 0, fWindowStart: Int64 = 0   // this render's beat conversion (set in process)
    // UTILITY (Paul 2026-08-22) — per-cell EMIT overrides, set right where currentCellIndex is set and read in emitOneBus.
    // Both are byte-identical when unset (−1 / 0). Reset before drainEchoTails so echo tails use the wire defaults (v1).
    private var chanOverride: Int16 = -1   // CHANNEL: output channel (−1 = the bus stamp · 0–15 = override)
    private var nudgeSamples: Int64 = 0    // NUDGE: timing offset in samples (0 = none)
    // DEAL (Paul 2026-09-16): a note-transparent OUTPUT dealer — override the emitters, deal N1 notes → emitter 1, N2 →
    // emitter 2 (repeat). Set per-cell (dealSetup); the per-cell counters advance in emitArtic. Live turn-taking state
    // (same class as ALT/TURNS' altMomentIndex): reset on a fresh play. Fixed storage → no render-path allocation.
    private var dealActive = false
    private var dealE1 = 0, dealE2 = 1, dealN1 = 1, dealN2 = 1
    private var dealMode: DealMode = .overTime
    private var dealMoment = [Int](repeating: -1, count: Snap.cells)        // moments elapsed (OVER TIME) · −1 ⇒ first strike is pos 0
    private var dealNoteInMoment = [Int](repeating: 0, count: Snap.cells)   // rank within the current moment (WITHIN CHORD)
    private var dealLastOnset = [Int64](repeating: .min, count: Snap.cells) // last onset sample per cell (moment detection)
    private var dealGlobal = [Int](repeating: 0, count: Snap.cells)         // running note count (EVERY NOTE)
    // RIFF DIRECTION = DRUNK (Paul 2026-09-28): the walk position persists per grid cell — same class as DEAL/ALT
    // above (a genuinely accumulated value; the codebase's architecture review, Docs/codebase-review-2026-08-16.md
    // finding A1, already flags this class as a known, disclosed limitation — not replay-exact across a mid-phrase
    // seek/loop — rather than a blessed exception; this is a deliberate third instance, not a free pass). Keyed on
    // `tick` (never `raw`, which resets at every SPAN boundary) so the walk is SPAN-oblivious by construction. Reset
    // on a fresh play, same trigger as DEAL/ALT, never on panic. Fixed storage → no render-path allocation.
    private var riffDrunkPos = [Int](repeating: -1, count: Snap.cells)           // −1 ⇒ not yet started (first strike parks at step 0)
    private var riffDrunkPrevPos = [Int](repeating: -1, count: Snap.cells)       // the position immediately BEFORE the current tick's move — −1 ⇒ no previous strike yet (SLIDE's own lookback, Paul 2026-09-28)
    private var riffDrunkLastTick = [Int64](repeating: .min, count: Snap.cells)  // last tick this cell's walk advanced on
    // EUCLIDEOUS RIFF ADVANCE (Paul 2026-10-06): each of Euclideous's 4 lines gets its OWN independent cursor into
    // the page's one shared riff pattern, advancing by exactly one step on that line's OWN hit (not on elapsed
    // time) — "each hit will progress riff by 1 step." For 5 of 6 directions this needs ZERO new memory: the
    // line's own hit-ordinal (`ord`, already computed stateless in `runEuclidLine`) drives `riffStepAt` directly.
    // Only DRUNK is genuinely path-dependent (a random walk's position depends on its own history, not just "what
    // time is it now") — same accepted-exception class as `riffDrunkPos` above (not replay-exact across a seek),
    // just HIT-triggered (keyed on distinct `ord`) instead of tick-triggered, and sized 4 (one per Euclideous
    // lane, not `Snap.cells`) since Euclideous is always exactly 4 lines at one fixed, reserved cell.
    private var euclideousRiffDrunkPos = [Int](repeating: -1, count: 4)
    private var euclideousRiffDrunkLastOrd = [Int64](repeating: .min, count: 4)
    // RESET SPAN (Paul 2026-10-08): per-lane "last observed span-start beat" — lets DRUNK detect a span
    // boundary crossing and hard-reset its walk to 0, the same "fresh start" treatment the very-first-hit
    // case already gives it. NaN = "never observed" (also the sentinel for "span is off" at the call site —
    // see euclideousRiffDrunkStep). Every OTHER riff direction resets for free via `ord` alone (no new state
    // needed) since `ord` is already derived from the span-re-anchored local beat.
    private var euclideousRiffLastSpanStart = [Double](repeating: .nan, count: 4)
    // LIVE RIFF POOL DISPLAY (Paul 2026-10-08): a stable, UI-pollable snapshot of the ascending notes
    // currently feeding the riff's own pool — mirrors the `cellSoundingNotes`/`riffDrunkPos` precedent
    // exactly (render-thread writes a plain array, a `pollXXX`-style accessor reads it from the UI timer, no
    // locking — a torn read of a value-type array is tolerable for a once-per-frame display readout). NOT
    // `riffSrcNoteBuf` itself — that's reused SCRATCH, overwritten by every `.euclid` cell this render window
    // touches, not safe to expose directly; this is a DEDICATED copy, written only for Euclideous's own row.
    private var euclideousRiffLiveNotes = [UInt8](repeating: 0, count: 16)
    private var euclideousRiffLiveCount = 0
    func euclideousRiffLivePool() -> [UInt8] { Array(euclideousRiffLiveNotes.prefix(euclideousRiffLiveCount)) }
    // Unified UI-poll surface: EVERY direction (not just DRUNK) writes its resolved step index here, so the poll
    // layer only ever reads one simple array regardless of which direction a lane is using.
    private var euclideousRiffStep = [Int](repeating: -1, count: 4)
    // NOTE VIEW (Paul 2026-10-10 ferry): a per-lane EVENT QUEUE — "the audio thread posts note and step
    // events... through a lock-free queue; the UI reads them." Mirrors `focusNotePitch`/`focusNoteHead`/
    // `focusNoteNew`'s exact ring-buffer shape (below, this file), just 4-wide (one ring PER LANE) instead
    // of one ring for a single focus cell — all 4 Euclideous lanes share ONE engine row (`Snap.
    // euclideousRow`), so no existing per-row/per-cell feed can tell them apart. One EVENT is one step's
    // whole OUTCOME, not one note — a chord/ALL pick strikes several notes in a single decision, stored
    // together so the UI's note box treats them as ONE update (ferry §4.6), not N separate ones.
    // kind: 0 = hit (a real note/chord struck) · 1 = miss-playing (the MISS side struck) · 2 = rest-flash
    // (riff ON-REST=SKIP's momentary "—", ferry §4.5) · 3 = tied hit (a real/FILL hit whose own gate was
    // extended by `riffTieExtensionBeats` to cover a following rest, ferry §4.5's TIE case — a DISTINCT
    // kind from a plain hit, not just a longer `durationBeat`, because the ferry describes genuinely
    // different UI behaviour for it: full brightness for the WHOLE held/extended span, settling only once
    // it's truly over — see `noteViewNoteBoxContent`'s own handling of this kind). Fixed-size, preallocated,
    // zero allocation during
    // `process()` — the only allocation this feature ever does is inside `drainEuclideousNoteViewEvents`
    // (below), building fresh small arrays on the calling (main) thread, exactly like `drainFocusNotes`/
    // `drainCellNotes` already do.
    private static let noteViewRing = 8
    private static let noteViewMaxNotes = 8
    private var nvOnsetBeat    = [Double](repeating: 0, count: 4 * Router.noteViewRing)
    private var nvDurationBeat = [Double](repeating: 0, count: 4 * Router.noteViewRing)
    private var nvKind         = [UInt8](repeating: 0, count: 4 * Router.noteViewRing)
    private var nvNoteCount    = [UInt8](repeating: 0, count: 4 * Router.noteViewRing)
    private var nvNotes        = [UInt8](repeating: 0, count: 4 * Router.noteViewRing * Router.noteViewMaxNotes)
    private var nvHead = [Int](repeating: 0, count: 4)
    private var nvNew  = [Int](repeating: 0, count: 4)
    // §5.1, literal: "nothing in this view may block or allocate on the audio thread." A caller-built
    // `[UInt8]` (an array literal, or a `.compactMap` result) is itself a render-thread heap allocation,
    // even for one element — found + fixed on a self-re-audit: the ORIGINAL 5 call sites each built one
    // of these before calling this function. `nvScratch` is the fix — ONE preallocated, reused buffer
    // every call site writes its (small, ≤8) note list into IN PLACE before calling this function with
    // just a count; nothing here or at any call site constructs a new array.
    private var nvScratch = [UInt8](repeating: 0, count: Router.noteViewMaxNotes)
    /// Records ONE step's outcome for `lane` (0...3) — called from inside `runEuclidLine` at its 3 real
    /// decision points (hit, miss-playing, rest-flash). Reads `noteCount` entries from `nvScratch`
    /// (written by the caller just before this call) — the FINAL, already-transposed/octave-shifted,
    /// 0...127-clamped MIDI values this tick is actually striking (ferry §5.3: "must match what is
    /// actually sent") — computed by the CALLER via the same arithmetic `strikeChord`'s own `strikeOne`
    /// uses, not re-derived here, so this can never silently disagree with the real emission. `noteCount`
    /// is pre-capped at `noteViewMaxNotes` by every caller (ample for any realistic chord). Write-side
    /// `nvNew` is capped at the ring size (never over-counted), matching `focusNoteNew`'s own idiom
    /// exactly — the ring naturally keeps-newest/drops-oldest with no extra branching needed.
    private func pushNoteViewEvent(lane: Int, onsetBeat: Double, durationBeat: Double, kind: UInt8, noteCount: Int) {
        guard lane >= 0, lane < 4 else { return }
        let slot = lane * Router.noteViewRing + nvHead[lane]
        nvOnsetBeat[slot] = onsetBeat; nvDurationBeat[slot] = durationBeat; nvKind[slot] = kind
        let nc = max(0, min(Router.noteViewMaxNotes, noteCount))
        nvNoteCount[slot] = UInt8(nc)
        let nbase = slot * Router.noteViewMaxNotes
        for i in 0..<Router.noteViewMaxNotes { nvNotes[nbase + i] = i < nc ? nvScratch[i] : 0 }
        nvHead[lane] = (nvHead[lane] + 1) % Router.noteViewRing
        if nvNew[lane] < Router.noteViewRing { nvNew[lane] &+= 1 }
    }
    // EUCLID BEACON READINESS (Paul 2026-10-05, closing the beacon's own disclosed gap — "doesn't walk RIFF/ARP's
    // own resolved note... reads the door's raw held notes, not the fully-resolved upstream-chain pool"). Bit
    // (lineIndex*2 + (isMiss?1:0)) is set when that line's resolved noteSel/missNoteSel currently has a genuine
    // target to strike — computed from the SAME real guards runEuclidLine's hit/miss closures apply (see the
    // computation site in `case .euclid:`), not approximated from a door's raw note count. NOT accumulated state
    // (unlike riffDrunkPos above) — fully recomputed every render for every cell currently dispatching as EUCLID,
    // and explicitly zeroed at the pool-empty guard in `process()` so "nothing held" reads as "nothing can play"
    // promptly rather than going stale. UI-poll read via `euclidLineReadyAt`, same plain-array-read safety as
    // `riffDrunkPosAt`/`cellSoundVel` (a torn UInt8 is benign — one stale frame).
    private var euclidLineReady = [UInt8](repeating: 0, count: Snap.cells)
    // RECORDER (AcceptanceCriteria-recorder, ratified 2026-09-18) — the looper-in-a-chain. STAGE 1: LOOP · PASSES|STEPS ·
    // ON PLAY|AFTER N · REPLACE|LAYER · CAPTURE ONCE, fed by an UPSTREAM DRIVER (captured in the driver fold). Per-cell
    // render-side buffer (persistence + FREEZE/CANON/REFRESH/CLEAR are later stages). Sanctioned accumulated-state
    // (echo-ring class): the record/playback PHASE is a pure fn of the pass/step number, so a committed loop plays back
    // replay-exact (spec §REPLAY-EXACTNESS) — only the live capture window is not seek-exact.
    private static let recNoteCap = 96
    private var recCaptured = [Bool](repeating: false, count: Snap.cells)     // this cell's loop is committed → play (ONCE = never re-record)
    private var recCapN  = [Int](repeating: 0, count: Snap.cells)             // in-progress capture count (this window)
    private var recCapStart = [Double](repeating: 0, count: Snap.cells * Router.recNoteCap)  // note start, beats within the window
    private var recCapNote  = [UInt8](repeating: 0, count: Snap.cells * Router.recNoteCap)
    private var recCapVel   = [UInt8](repeating: 0, count: Snap.cells * Router.recNoteCap)
    private var recCapGate  = [Double](repeating: 0, count: Snap.cells * Router.recNoteCap)  // note length in beats
    private var recBufN  = [Int](repeating: 0, count: Snap.cells)             // committed loop note count
    private var recBufStart = [Double](repeating: 0, count: Snap.cells * Router.recNoteCap)
    private var recBufNote  = [UInt8](repeating: 0, count: Snap.cells * Router.recNoteCap)
    private var recBufVel   = [UInt8](repeating: 0, count: Snap.cells * Router.recNoteCap)
    private var recBufGate  = [Double](repeating: 0, count: Snap.cells * Router.recNoteCap)
    private var recWindowIdx = [Int](repeating: Int.min, count: Snap.cells)   // CANON: the last window index committed (rolling)
    private var recArmUnit  = [Int](repeating: Int.min, count: Snap.cells)    // the grain unit the current capture (re)started on (Int.min = unarmed)
    private var recCycleBase = [Int](repeating: 0, count: Snap.cells)         // REFRESH: the unit the current committed loop began (for the M-cycle re-arm)
    // Reset the RECORDER state. `full` (scene/panic) drops the committed loop too; else (transport/latch/freeze) keep
    // the loop but discard any partial capture, so a stop→start keeps looping and a mid-record stop re-records clean.
    private func resetRecorderCapture(full: Bool) {
        for i in recCapN.indices { recCapN[i] = 0; recWindowIdx[i] = Int.min; recArmUnit[i] = Int.min; recCycleBase[i] = 0 }
        if full { for i in recCaptured.indices { recCaptured[i] = false; recBufN[i] = 0 } }
    }
    // The non-bypassed RECORDER proc downstream of `driver` (the capture stage), or nil.
    private func downstreamRecorder(_ cell: SnapCell, after driver: Int) -> Int? {
        var j = driver + 1
        while j < cell.procs.count { if !cell.slotBypass[j] && cell.procs[j].type == .recorder { return j }; j += 1 }
        return nil
    }
    // The cell's first non-bypassed RECORDER proc (any slot), or nil — for the playback pass.
    private func recorderSlot(_ cell: SnapCell) -> Int? {
        var j = 0
        while j < cell.procs.count { if !cell.slotBypass[j] && cell.procs[j].type == .recorder { return j }; j += 1 }
        return nil
    }
    // RECORDER window geometry (a pure fn of the grain/len/arm + the clock): unitBeats = the grain unit, window = N units,
    // and the record window spans units [startUnit, endUnit). The PASS/STEP number decides record vs playback.
    private func recWindow(_ p: SnapParams, passBeats: Double, stepBeats: Double) -> (unitBeats: Double, window: Double, startUnit: Int, endUnit: Int) {
        let unitBeats = max(0.03125, p.recGrain == .passes ? passBeats : stepBeats)
        let n = max(1, min(32, p.recLen))
        let armDelay = p.recArm == .afterN ? max(0, min(32, p.recArmN)) : 0
        return (unitBeats, unitBeats * Double(n), armDelay, armDelay + n)
    }
    private func dealSetup(_ cell: SnapCell) {   // find this cell's DEAL proc (last wins, like chopMask's DEST scan); set the emit-side state
        dealActive = false
        for j in 0..<cell.procs.count where !cell.slotBypass[j] && cell.procs[j].type == .deal {
            let p = cell.procs[j]
            dealActive = true; dealE1 = p.dealE1 & 3; dealE2 = p.dealE2 & 3; dealN1 = max(1, p.dealN1); dealN2 = max(1, p.dealN2); dealMode = p.dealMode
        }
    }
    // THE SEAL COMET (note-on/off gate): a bitmask of the cells CURRENTLY SOUNDING (≥1 active non-silent voice).
    // Snapshotted on the render thread each window (a live set, like snapshotEmitterSounding); the UI polls it so the
    // The per-cell SOUNDING gate is derived on the UI side from `cellSoundVel > 0` (256-wide, covers cols 8–15); the old
    // 128-bit lo/hi bitmask was retired (Paul 2026-09-08 housekeeping) — it couldn't represent indices ≥128 (a 16-wide
    // part's second half) and had no consumer left after the VC switched to the velocity feed.
    private var cellSoundVel = [UInt8](repeating: 0, count: Snap.cells)   // per-cell SOUNDING velocity (max over the cell's active voices) — stays up while a note is HELD, unlike the strike feed. Feeds the emitter fader's per-machine floor (Paul 2026-09-07).
    private var currentAlt = false                   // §2 the emitting cell's effective FACE (A/B), stamped onto opened voices
    // §2 CONTINUITY: transition scratch — a legato immortal voice is a candidate for ADOPTION until the
    // reconcile either keeps it (matched by the new column) or closes it (dropped). Sized to the pool, reused.
    private var holdCandidate = [Bool](repeating: false, count: 128)
    private var wasPlaying = false
    private var prevEffColumn = -1   // column-transition edge (§7): change ⇒ truncate voices
    private var prevUniformFast = true   // CR-11: was the last render on the uniform clock? A live uniform↔multi switch isn't a flush, so the per-row trackers must be re-seeded on the change (else a stale prevEffColumnRow[r] skips a row's transition reconcile → phantom drone)
    // PER-PART CLOCK (Paul 2026-08-19): the multi-clock render path. Each ROW runs its own step rate, so its
    // column-transition edge is tracked SEPARATELY (prevEffColumnRow) and its per-window clock is derived into the
    // scratch buffers below (fixed-size, no render-path alloc). Uniform scenes never touch any of this (fast path).
    private var prevEffColumnRow = [Int](repeating: -1, count: Snap.rows)
    private var rowEffColBuf = [Int](repeating: 0, count: Snap.rows)     // per-row effective column this window
    private var rowSBuf = [Double](repeating: 0, count: Snap.rows)       // per-row step beats
    private var rowCycBuf = [Double](repeating: 0, count: Snap.rows)     // per-row cycle beats (Lr · Sr)
    private var rowMNowBuf = [Double](repeating: 0, count: Snap.rows)    // per-row musical position
    private var rowPassBuf = [Int](repeating: 0, count: Snap.rows)       // per-row pass index
    private var rowLaunchArmed = [Bool](repeating: false, count: Snap.rows)   // PLAY-FERRY LAUNCH: this row is armed (quantized start not yet reached) → emit nothing this window
    private var rowHeld = [UInt16](repeating: 0, count: Snap.rows)        // PER-ROW LAP: each row's effective loop mask (box.rowLaneMask[r], or the global ephemeral lap when the scene set none)
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
    // MOD leave-disposition + STRIKE trigger, PER-ROW (Paul 2026-08-19): the multi-clock path emits MOD per row at the
    // row's own column, so each row tracks its OWN last-emitted column + entry beat. Slot Snap.rows = the uniform/global
    // call (onlyRow == nil), byte-identical to the old single value.
    private var modLastColumn = [Int32](repeating: -1, count: Snap.rows + 1)  // the column whose MOD cells emitted last, per slot (reset when it exits)
    private var modColumnEntryBeat = [Double](repeating: 0, count: Snap.rows + 1)  // STRIKE: the beat the slot's active column became active (AR trigger)
    private var modPrevTarget = [Int16](repeating: -1, count: Snap.cells * 8)         // per (gridCell*8 + slot): the LAST CC# a MOD slot emitted — revert it when the target changes
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
        // STEP mode (Paul 2026-08-22): a pending chromatic run source→target, emitted step-by-step across windows.
        var stepFrom: Int16 = -1   // the run's origin note
        var stepTarget: Int16 = -1 // the run's destination (held when reached)
        var stepTotal: Int16 = 0   // |Δ| semitones = number of steps in the run
        var stepsDone: Int16 = 0   // steps already emitted (idempotent across windows)
        var stepRunStart = 0.0     // beat the run began
        var stepVel: UInt8 = 100   // the run's velocity (captured when the run was set up — used by both glide paths)
        var mode: GlideMode = .bend   // the voice's glide mode (set at anchor) — phrase-end centres the bend ONLY for BEND
    }
    /// Emit the pending STEP chromatic run's strikes that fall in this window (shared by the single-slot + driven paths).
    /// Intermediate steps are short zipper notes; the final step is the TARGET, held (offSample .max) until the next
    /// transition. Idempotent across windows via `stepsDone`. (Paul 2026-08-26 — [driver→GLIDE] STEP awareness.)
    private func emitGlideStepRun(_ gv: inout GlideVoice, cable: UInt8, ch: UInt8, bus: Int, glideTime: Double,
                                  beatPos: Double, bEnd: Double, beatsPerSample: Double, windowStart: Int64, out: MIDIEmitter?) {
        guard gv.stepTotal > 0, gv.stepsDone < gv.stepTotal else { return }
        let N = Int(gv.stepTotal), from = Int(gv.stepFrom), tgt = Int(gv.stepTarget)
        let dir = tgt >= from ? 1 : -1
        let stepBeat = max(0.00005, glideTime) / Double(N)
        var i = Int(gv.stepsDone) + 1
        while i <= N {
            let onBeat = gv.stepRunStart + Double(i) * stepBeat
            if onBeat >= bEnd { break }                          // a later window carries this step
            let onS = windowStart + Int64((max(0, onBeat - beatPos) / beatsPerSample).rounded())
            let sn = max(0, min(127, from + dir * i))
            if i < N {                                           // intermediate zipper note (short)
                let offS = onS + Int64(max(1, (stepBeat * 0.9 / beatsPerSample).rounded()))
                _ = openVoice(note: UInt8(sn), chan: ch, cable: cable, bus: UInt8(bus), onSample: onS, offSample: offS, velocity: gv.stepVel, out: out, meter: true)
            } else {                                             // final = the TARGET, held until the next transition
                let slot = openVoice(note: UInt8(max(0, min(127, tgt))), chan: ch, cable: cable, bus: UInt8(bus), onSample: onS, offSample: .max, velocity: gv.stepVel, out: out, meter: true)
                gv.slot = Int16(slot)
            }
            gv.stepsDone = Int16(i); i += 1
        }
    }
    private var glideVoices = [GlideVoice](repeating: GlideVoice(), count: Snap.cells)
    private var glideLastColumn = [Int32](repeating: -1, count: Snap.rows + 1)   // PER-ROW phrase-end on column exit (slot Snap.rows = the uniform/global call)
    // [driver→GLIDE] v2 (§7①, ratified 2026-08-22): a chain DRIVER (arp/cascade/…) folds its notes into a downstream
    // GLIDE slot instead of emitting them — the walk becomes one mono gliding voice (the 303 line). Per-window TRANSIENT
    // target buffer (reset each window, NO cross-window accumulation — invariant 2): emitDriverNote records (beat, note,
    // vel) here + SUPPRESSES the note-on; emitGlideDriven (post-tick) consumes them into the SAME glideVoices, so
    // flushGlide / glidePhraseEnd / the no-stuck-notes contract all cover driven glide unchanged.
    private static let glideDrivenCap = 8                                        // max driver targets recorded per cell per window
    private var glideDrivenNote = [Int16](repeating: -1, count: Snap.cells * 8)          // per (gridCell*cap + i): the driver's note
    private var glideDrivenBeat = [Double](repeating: 0, count: Snap.cells * 8)          // …its musical beat (ramp origin)
    private var glideDrivenVel  = [UInt8](repeating: 0, count: Snap.cells * 8)           // …its velocity (anchor/re-anchor note-on)
    private var glideDrivenCount = [Int](repeating: 0, count: Snap.cells)                // per gridCell: targets recorded this window
    private var modLastVal = [Int16](repeating: -1, count: 5 * 16 * 128)      // [cable*2048 + ch*128 + cc] → last CC value (-1 = none sent)
    private let modCtrlBeats = 1.0 / 16.0                                     // CC control-grid resolution (16 points per beat)
    // EXTERN: the incoming controller VALUE STORE (cc → value, channel-agnostic v1) — the Kernel writes it each render
    // (side rail, §7 READ-AT-SOURCE); a MOD stage in EXTERN mode reads + transforms it. -1 = never seen.
    private var controllerIn = [Int16](repeating: -1, count: 128)
    private var prevPreviewActive = false
    private var prevFreezeActive = false      // ROW 8 FREEZE: the freeze→unfreeze edge (release the sustained notes + resume clean)
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
    // The driver emitters' SOURCE chord (note + inherited velocity), filled once per cell per window into a REUSED
    // fixed buffer (no render-path alloc — was a fresh `[(Int,UInt8)]` per generator/weave/tutti/length cell). The
    // emitters bind `srcNoteBuf[0..<srcNoteCount]` — a view whose 0-based indices match, so their reads are unchanged.
    private var srcNoteBuf = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128)
    // STANDALONE RATCHET PATTERN (Paul 2026-09-08): the desired PASS sustain set for ONE cell — reused fixed scratch
    // (no render-path alloc). Max 16 held notes × 4 buses = 64 (wire, bus, velocity) triples.
    private var rtcDesWire = [UInt8](repeating: 0, count: 128)
    private var rtcDesBus  = [UInt8](repeating: 0, count: 128)
    private var rtcDesVel  = [UInt8](repeating: 0, count: 128)
    private var rtcDesCI   = [Int16](repeating: -1, count: 128)   // adoption key: machine (a row of same-machine cells sustains seamlessly)
    private var rtcDesCell = [Int16](repeating: -1, count: 128)   // the cell that first opens a wire (SEAL/roll stamp)
    private var lenEventBuf = [(on: Double, off: Double)](repeating: (0, 0), count: 8)   // LENGTH: reused no-alloc scratch (invariant 3)
    private var srcNoteCount = 0
    // Render-hot-loop scratch for the pattern helpers (no per-window array alloc — invariant 3). euclid/burst are
    // weave-XOR-generator per cell (never nested) → one buffer each; tutti CAN nest ([TUTTI-pattern → TUTTI] folds the
    // emitter through applyStage) → the emitter (A) and applyStage (B) take SEPARATE rank buffers.
    private var euclidBuf = [Bool](repeating: false, count: 16)
    private var burstBuf = [Double](repeating: 0, count: 16)
    private var tuttiRankBufA = [Int](repeating: 0, count: 128)
    private var tuttiRankBufB = [Int](repeating: 0, count: 128)
    private func fillSrcFromScratch() {
        srcNoteCount = 0
        let c = chainScratch.srcCount(filter: 0, cableMask: 0b1111)
        for k in 0..<c where srcNoteCount < srcNoteBuf.count {
            let n = chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111)
            srcNoteBuf[srcNoteCount] = (Int(n), chainScratch.velocity(n)); srcNoteCount += 1
        }
    }
    private func fillSrcFromPool(_ cell: SnapCell, _ pool: NotePool) {
        srcNoteCount = 0
        let c = pool.srcCount(for: cell)
        for k in 0..<c where srcNoteCount < srcNoteBuf.count {
            let n = pool.srcAscending(k, for: cell)
            srcNoteBuf[srcNoteCount] = (Int(n), pool.velocity(n)); srcNoteCount += 1
        }
    }
    // EUCLIDEOUS PAGE REWORK (2026-10-07): the riff's own note-picking source is a SEPARATE pool from the
    // lanes' own (`srcNoteBuf` above) — read via an EXPLICIT chanMask (not `for: cell`, which reads the
    // cell's own resolved receiver fields — those belong to the lanes' source). Mirrors `fillSrcFromPool`
    // exactly, just keyed by a raw chanMask instead of a SnapCell. `chanMask == 0` (KEY mode, or no doc
    // receivers) naturally yields `c == 0` — an honest empty pool, no separate guard needed.
    // RIFF'S OWN POOL (Paul 2026-10-09, ferry §2.4 — supersedes the 2026-10-07/08 "follows lane 1" design):
    // the actual AUDIO resolution of a useRiff-on lane no longer reads this buffer at all — each lane now
    // resolves the shared riff SHAPE against its OWN per-lane pool directly (`laneNotes(lineIndex)`/
    // `laneCount(lineIndex)`, the SAME per-lane buffer its own MIDI IN/KEY/CHORDS I/O-tab choice already
    // fills — see the `if useRiff {` block in `case .euclid:`). This buffer is now DISPLAY-ONLY — still
    // filled, per render, by copying lane 0's own resolved pool (see the riff-fill block below), purely to
    // feed `euclideousRiffLiveNotes` (a kept-but-currently-unrendered "show the resolved note" readout) —
    // nothing in the audible path depends on it being lane 0's view specifically anymore.
    private var riffSrcNoteBuf = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128)
    private var riffSrcNoteCount = 0
    // PER-LANE I/O (Paul 2026-10-08): each Euclideous lane independently resolves MIDI IN / KEY / CHORDS — this
    // fills ONE lane's buffer from the LIVE pool by an explicit chanMask (mirrors the old `fillRiffSrcFromPool`
    // exactly, just one buffer PER LANE (0...3) instead of one shared buffer) — used for MIDI-mode lanes only;
    // CHORDS-mode lanes are filled directly from `chordSeqNotes` instead (see `case .euclid:`'s own per-lane
    // fill loop). Only ever consulted for Euclideous's own reserved row (`laneCount`/`laneNotes` gate this) —
    // every other `.euclid` cell in the grid keeps reading the single shared `srcNoteBuf`/`srcNoteCount`
    // exactly as before this feature, untouched.
    private var laneSrcBuf = [[(note: Int, vel: UInt8)]](repeating: [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128), count: 4)
    private var laneSrcCount = [Int](repeating: 0, count: 4)
    private func fillLaneSrcFromPool(_ pool: NotePool, lane: Int, chanMask: UInt16) {
        laneSrcCount[lane] = 0
        let c = pool.srcCount(chanMask: chanMask, cableMask: 0b1111)
        for k in 0..<c where laneSrcCount[lane] < laneSrcBuf[lane].count {
            let n = pool.srcAscending(k, chanMask: chanMask, cableMask: 0b1111)
            laneSrcBuf[lane][laneSrcCount[lane]] = (Int(n), pool.velocity(n)); laneSrcCount[lane] += 1
        }
    }
    // TICK DEDUP, keyed per (row, slot) not just per row (Paul 2026-10-05, fixing the timing smear investigated
    // and left open on 2026-10-03: "`lastTick[row]` is a SINGLE scalar SHARED across every line on this row —
    // safe for one real line; a known limitation for 2+ real lines sharing a row across a window boundary").
    // EUCLID's up-to-4-lines-per-row design (the ONLY `iterateTicks` caller that invokes it more than once per
    // row in a single render — ARP/RIFF/RATCHET-ALL/HOCKET each call it exactly once per row) meant two real
    // lines on the same row shared ONE dedup scalar: when one line's tick advanced it past a tick the OTHER
    // line hadn't reached yet, the other line's catch-up fire computed its `sampleOf` conversion in a LATER
    // window's frame, landing roughly one render-window late — never a stuck note (every strike still gets a
    // valid on/off pair), just smeared timing. `tickDedupSlotsPerRow` matches EUCLID's fixed 4-line count;
    // every OTHER caller passes the default `lineIndex: 0`, landing on slot 0 of its row — the SAME single
    // scalar-per-row behaviour as before, byte-identical.
    private static let tickDedupSlotsPerRow = 4
    private var lastTick = [Int64](repeating: -1, count: Snap.rows * Router.tickDedupSlotsPerRow)
    /// Reset every tick-dedup slot for ONE row (all `tickDedupSlotsPerRow` lines) — the per-row flush/transition
    /// edges that used to do a single `lastTick[row] = -1`.
    private func resetTickDedup(row: Int) {
        guard row >= 0 else { return }
        let base = row * Router.tickDedupSlotsPerRow
        for s in 0..<Router.tickDedupSlotsPerRow where base + s < lastTick.count { lastTick[base + s] = -1 }
    }
    /// Reset every tick-dedup slot for EVERY row — the whole-grid flush edges that used to do
    /// `for r in lastTick.indices { lastTick[r] = -1 }` (still correct post-widening on its own, since
    /// `.indices` adapts to the new size, but factored here so callers that paired it with a row-SIZED loop
    /// over `strumProgress`/`lastGenStep` in the SAME `for` don't silently go out of bounds now that `lastTick`
    /// is 4× longer than those two arrays).
    private func resetAllTickDedup() {
        for i in lastTick.indices { lastTick[i] = -1 }
    }
    // Per-row: the absolute column-step a window-scan GENERATOR (burst/cascade/drone/shift/humanize) last emitted in.
    // On a column's FIRST window it differs from the current step → scan from colStart so the DOWNBEAT (and any pulse
    // in [colStart, mWinStart)) fires once instead of being dropped at the boundary. (Paul 2026-08-18)
    private var lastGenStep = [Int64](repeating: Int64.min, count: Snap.rows)
    private var soloEmitterMask: UInt8 = 0
    // receiver strip: the additive input SOLO set (bits R1–R4). While non-empty, a cell whose receiver is
    // NOT a member falls silent — `audible = ¬muted ∧ (soloSet=∅ ∨ member)`. Row-fed cells (recv −1) reach
    // this through their root MIDI-IN cell in parentSoundingNote. Ephemeral (cleared on stop / EDIT).
    private var soloReceiverMask: UInt8 = 0
    private func soloSilenced(_ cell: SnapCell) -> Bool {
        soloReceiverMask != 0 && cell.resolvedReceiver >= 0 && (soloReceiverMask & (1 << UInt8(cell.resolvedReceiver))) == 0
    }
    // receiver strip: an ephemeral ±octave nudge per receiver (−3…+3), packed one signed byte each. Composes
    // with the cell's machine transpose at the per-cell transpose local (a PLAYING control; 0 in stopped
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
    // INPUT ADMISSION: this render's per-receiver channel/cable/range filter (mute+disable already folded into
    // receiverChannels) + the no-machine LIVE WIRE mask. Read from the box each render. (The door-level BYPASS mask/dest
    // that once lived here was retired 2026-08-25; only passEmitterMask remains.)
    private var receiverChannels: [UInt8] = [0, 0, 0, 0]
    private var receiverCables: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111]
    private var receiverRangeLo: [UInt8] = [0, 0, 0, 0]
    private var receiverRangeHi: [UInt8] = [127, 127, 127, 127]
    private var receiverScaleRoot: [Int] = [-1, -1, -1, -1]       // CHORDS C2b#1: per-receiver declared scale root (−1 = not a scale door), this render
    private var receiverScaleType: [ScaleType] = [.major, .major, .major, .major]
    private var passEmitterMask: [UInt8] = [0, 0, 0, 0]   // NO-MACHINE WIRE: per door, the union of passthrough cells' emitters (reconcileBypass injects the door's input to them in realtime)
    private var bypassDesired = [Bool](repeating: false, count: 128)   // scratch: desired source notes this render
    private var bypassScratch = [UInt8](repeating: 0, count: 128)      // scratch: the desired notes, read once
    /// The pool a cell reads: its receiver's frozen LATCH pool when armed (which STILL feeds while the door is
    /// disabled — the point of "close the door, keep the room"); else, if the door is DISABLED (not listening),
    /// nothing; else the live pool. A row-fed cell (recv −1) always reads live (its root's latch reaches it via
    /// parentSoundingNote). Mute is handled upstream (the cell's match-nothing filter kills even the frozen read).
    private func effectivePool(for cell: SnapCell, live: NotePool) -> NotePool {
        let r = cell.resolvedReceiver
        if r >= 0 {
            if latchMask & (1 << UInt8(r)) != 0, Int(r) < latchedPools.count { return latchedPools[Int(r)] }
            if receiverDisabledMask & (1 << UInt8(r)) != 0 { return emptyPool }   // not armed + not listening → silent
        }
        return live
    }

    /// NO-MACHINE LIVE WIRE (Paul 2026-08-23): a passthrough (empty-chain) cell's shaped, in-range held notes sound
    /// DIRECTLY on its emitters, in realtime, skipping the grid's step clock. Runs every render (stopped + playing — a
    /// live monitor). Reuses openVoice/closeVoice so the refcount + dual-cable (own + All) + panic-safety all apply; the
    /// voices are IMMORTAL and tagged (bypassRecv ≥ 0) so the grid's continuity/transport flushes leave them be. DIRECT
    /// injection: no emitter roles. v1 applies RANGE + channel/cable admission (a muted/disabled door goes quiet — same
    /// filter); octave/velocity SHAPING is deferred (the output note = the source note, so on/off balance by note).
    /// (The door-level BYPASS toggle that once shared this path was retired 2026-08-25 — Paul; only the wire remains.)
    private func reconcileBypass(pool: NotePool, atSample sample: Int64, out: MIDIEmitter?) {
        guard passEmitterMask.contains(where: { $0 != 0 }) || anyBypassVoiceActive() else { return }   // fast path: no wire cells / none to close
        let savedCI = currentMachineIndex, savedCell = currentCellIndex, savedAlt = currentAlt
        currentMachineIndex = -1; currentCellIndex = -1; currentAlt = false        // wire voices carry no grid identity / SEAL
        defer { currentMachineIndex = savedCI; currentCellIndex = savedCell; currentAlt = savedAlt }
        for r in 0..<4 {
            // SOLO includes the wire (ruling 2026-08-04): a receiver SOLO set silences every non-soloed door's wire
            // too — the door mutes with the grid. (LIVE-off already silences it via the match-nothing filter.)
            let soloExcluded = soloReceiverMask != 0 && (soloReceiverMask & (1 << UInt8(r))) == 0
            // CR-4: master MUTE (the "nothing sounds" contract) silences the wire monitor too — destMask 0 both opens
            // none AND closes any live monitor voice (the reconcile below). Matches the grid/MOD/GLIDE mute guards.
            // R3 (2026-08-30): honor the emitter ENABLE + output-SOLO gates like the grid path (emitOneBus) too — a
            // disabled or soloed-out emitter must silence the wire (was: the wire ignored both → it kept sounding on a
            // disabled/soloed-out emitter, diverging from the grid). The close/open diff below self-corrects → no stuck note.
            let outAvail: UInt8 = busEnabledMask & (soloEmitterMask != 0 ? soloEmitterMask : 0b1111)
            let destMask = (masterMute && !previewMode) ? 0 : (soloExcluded ? 0 : (passEmitterMask[r] & outAvail))
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
    // AVOID+MOVE downstream ([driver→AVOID(move)]): the survivor pitch classes of the DRIVER's whole output pool, resolved
    // once per cell in the row loop, so a blocked driven note snaps in-scale (like a standalone AVOID) instead of dropping.
    // `Valid` is gated TRUE only around emitDriverNote's downstream fold — the upstream compose uses its own whole-set src.
    private var avoidDriverSurvivor: UInt16 = 0
    private var avoidDriverSurvivorValid = false
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
        var pitch: Int = 0           // semitones per successive echo (flat mode) — IN-KEY mode reads only its SIGN (direction)
        // ECHO IN-KEY (Paul 2026-09-29, supersedes the old POOL-STEP field): PITCH STEP walks to the next in-key
        // note instead of a flat semitone amount, live, from whichever ABCD receivers are selected.
        var inKeyMode: Bool = false      // true ⇒ PITCH STEP walks to the next in-key note; captured once at registration.
                                          // Kept as its OWN flag rather than inferred from inKeyReceivers != 0 — inferring
                                          // it would make "IN-KEY mode with zero receivers ticked" indistinguishable from
                                          // "mode not engaged," silently falling back to flat semitone math instead of the
                                          // required "hold at last landed pitch" behaviour for an empty reference set.
        var inKeyReceivers: UInt8 = 0    // bit i = receiver A..D contributing the live reference; the SELECTION is fixed
                                          // for the tail's life (like every other echo param), only its CONTENT is live.
        // WALK STATE: the previous repeat's actual landed note (−1 = not yet walked; repeat 1 starts from `note`). A
        // sanctioned mutable-state exception, same class as riffDrunkPos (~line 332) — disclosed, not treated as a
        // blanket precedent (see CLAUDE.md's RIFF DRUNK entry / Docs/codebase-review-2026-08-16.md finding A1).
        // Lower risk than DRUNK though: this is PER-TAIL not per-cell, and structurally exempt from the seek/loop
        // replay concern DRUNK carries, because a tail cannot survive a beat discontinuity at all (clearEchoTails
        // fires first — see drainEchoTails' own discontinuity check). Reset is free, not a separate mechanism:
        // pushEchoTail always fully RECONSTRUCTS the struct via a literal (never in-place field mutation), so a
        // reused slot's inKeyLast silently defaults back to −1. Do not change pushEchoTail to partial mutation
        // without re-zeroing this field explicitly.
        var inKeyLast: Int8 = -1
        var gateBeats: Double = 0.25
        var spill: EchoSpill = .ring // RING = tail spills past the column · CUT = pending repeats die at column exit
        // §7② ROUTE = CHAIN: re-fold each repeat through the chain stages AFTER the ECHO slot, at the repeat's own beat.
        // cellIdx/echoSlot look up the LIVE cell in drainEchoTails; route == .direct → the flat path (v1, byte-identical).
        var route: EchoRoute = .direct
        var cellIdx: Int = -1        // the emitting cell's grid index (for the CHAIN re-fold's live-chain lookup)
        var echoSlot: Int = -1       // the ECHO slot's position; the re-fold runs slots echoSlot+1 … tail
        // UTILITY (2026-08-23): the source cell's CHANNEL/NUDGE override, captured at registration, so the repeats sound
        // on the same channel + timing as the dry (a [CHANNEL→ECHO] cell echoes on its own channel, not the wire).
        var chan: Int8 = -1          // output channel override (−1 = the bus stamp)
        var nudge: Int64 = 0         // timing offset in samples
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
                              spill: EchoSpill = .ring, route: EchoRoute = .direct, cellIdx: Int = -1, echoSlot: Int = -1,
                              inKeyMode: Bool = false, inKeyReceivers: UInt8 = 0) {
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
                                   decay: decay, offset: offset, pitch: pitch, inKeyMode: inKeyMode, inKeyReceivers: inKeyReceivers,
                                   gateBeats: gateBeats, spill: spill,
                                   route: route, cellIdx: cellIdx, echoSlot: echoSlot,
                                   chan: Int8(max(-1, min(15, Int(chanOverride)))), nudge: nudgeSamples)   // repeats inherit the registering cell's CHANNEL/NUDGE (set at every push site)
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
        resetAllTickDedup(); for r in strumProgress.indices { strumProgress[r] = 0 }
        prevEffColumn = -1
        prevBusEnabledMask = 0b1111
        prevFreezeActive = false   // ROW 8 FREEZE: a reset clears the sustain edge
        for i in 0..<4 { meterPeakVel[i] = 0; meterEvents[i] = 0; markCount[i] = 0; withheldCount[i] = 0; soundCount[i] = 0 }
        prevAudition = -1; auditionLastTick = -1
        for i in 0..<4 { noteOnsThisBeat[i] = 0 }; lastGovBeat = Int.min   // FLOOD GOVERNOR: fresh budget on transport reset (floodDropped is a session total)
        for i in overrides.indices { overrides[i] = .nan }
        for i in rampDurationSamples.indices { rampDurationSamples[i] = 0 }   // a reset drops any in-flight ramp too
        overrideGen = .max
        clearEchoTails()
        resetRecorderCapture(full: true)             // RECORDER: a full reset clears the loops
        for i in modLastColumn.indices { modLastColumn[i] = -1; modColumnEntryBeat[i] = 0 }   // MOD: forget the last CC + column, every slot (no reset emit — reset() has no `out`)
        for i in modLastVal.indices { modLastVal[i] = -1 }
        for i in modPrevTarget.indices { modPrevTarget[i] = -1 }
        for i in glideVoices.indices { glideVoices[i] = GlideVoice() }; for i in glideLastColumn.indices { glideLastColumn[i] = -1 }
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
        // The override table is sized for the 16 host-automatable machines (transpose 2+i, i<16; the morph slots 18+i
        // are dead since the morph AU params were removed 2026-09-16).
        // An EPHEMERAL machine (index ≥16, Paul's unlimited-machines model) has no param address → no override,
        // so it uses its own value. Guard the read so a high machine index never traps the render thread.
        guard slotIndex >= 0, slotIndex < overrides.count else { return fallback }
        let v = overrides[slotIndex]
        return v.isNaN ? fallback : v
    }

    /// The per-cell base transpose: the TRANSPOSE param (override slot 2+ci), rounded to a semitone.
    /// Callers ADD the receiver/hold octave addends themselves — those differ per site (the preview/
    /// audition sites deliberately omit the receiver octave), so they must NOT be folded in here.
    private func machineTranspose(_ ci: Int, _ machine: SnapMachine) -> Int {
        // Only machines 0..15 have a TRANSPOSE param address (slot 2+ci ∈ 2..17). For an EPHEMERAL machine (ci ≥ 16)
        // slot 2+ci ∈ 18..33 = the MORPH override slots — host automation of a (render-dead) morph param would then
        // silently rewrite this machine's transpose EVERY render. An ephemeral machine has no param address, so it uses
        // its own value (as the `over` comment above already intends but did not enforce). (Paul 2026-08-27)
        guard ci < 16 else { return Int(machine.transpose) }
        return Int(over(2 + ci, Double(machine.transpose)).rounded())
    }

    /// A real document edit publishes a fresh snapshot generation → it is the new truth, so drop
    /// the render-side overrides and let the two param routes agree again (§7). Call once per render,
    /// BEFORE applying this render's parameter events.
    func refreshOverrides(forGeneration generation: UInt64) {
        if generation != overrideGen {
            for i in overrides.indices { overrides[i] = .nan }
            for i in rampDurationSamples.indices { rampDurationSamples[i] = 0 }   // a real doc edit is the new truth — drop any in-flight ramp too
            overrideGen = generation
        }
    }

    /// Apply one render-side .parameter/.parameterRamp event. A plain .parameter (rampDurationSampleFrames
    /// ≤1) snaps `overrides[idx]` immediately, same as before. A genuine .parameterRamp arms a linear
    /// interpolation from the CURRENT override to `value`, advanced each render by tickRamps(atSample:) —
    /// so a host-automated sweep draws a ramp instead of a staircase of per-block jumps (§7 second route).
    /// If nothing has overridden this slot yet (no known starting value to ramp FROM), snaps instead of
    /// guessing a baseline.
    func applyParamEvent(_ address: UInt64, _ value: Double, atSample: Int64, rampDurationSampleFrames: UInt32, diag: inout KernelDiag) {
        guard let idx = slot(for: address) else { return }
        if rampDurationSampleFrames > 1, !overrides[idx].isNaN {
            rampFrom[idx] = overrides[idx]
            rampTo[idx] = value
            rampStartSample[idx] = atSample
            rampDurationSamples[idx] = Int64(rampDurationSampleFrames)
        } else {
            overrides[idx] = value
            rampDurationSamples[idx] = 0   // an instant .parameter event supersedes any ramp already in flight at this slot
        }
        diag.paramEventCount &+= 1
        diag.lastParamAddr = Int64(address)
        diag.lastParamValue = value
    }

    /// Advance every in-flight render-side ramp to its value at this render window's start sample.
    /// Called once per render (top of process()), before anything reads `overrides` via `over(_:_:)`.
    private func tickRamps(atSample: Int64) {
        for i in rampDurationSamples.indices where rampDurationSamples[i] > 0 {
            let elapsed = atSample - rampStartSample[i]
            if elapsed >= rampDurationSamples[i] {
                overrides[i] = rampTo[i]
                rampDurationSamples[i] = 0
            } else if elapsed > 0 {
                let frac = Double(elapsed) / Double(rampDurationSamples[i])
                overrides[i] = rampFrom[i] + (rampTo[i] - rampFrom[i]) * frac
            }
            // elapsed <= 0: the ramp's start sample hasn't arrived yet this window (armed mid-block, this
            // IS that block) — leave `overrides[i]` at rampFrom[i], its value since the instant it was armed.
        }
    }

    // Topmost occupied, non-muted cell in a grid column — the single active cell (grid-chaining across
    // cells is retired; a cell's OWN processor chain runs in emitColumnHolds / the tick loop). cells
    // index = column*Snap.rows + row (256 cells = maxCols·rows; Snapshot.swift). Muted cells produce nothing (§6.2).
    @inline(__always)
    private func topCell(in column: Int, _ box: SnapshotBox) -> (row: Int, cell: SnapCell)? {
        let c = ((column % Snap.maxCols) + Snap.maxCols) % Snap.maxCols   // §E: wrap over the full 16-col storage so a 16-wide column reads its OWN cell (not col%8)
        for row in 0..<Snap.rows {
            let cell = box.cells[c * Snap.rows + row]
            if cell.machineIndex >= 0 && !cell.muted { return (row, cell) }
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
                           bypassRecv: Int8 = -1, meter: Bool = false, rtcHold: Bool = false) -> Int {
        guard let out else { return -1 }
        // Claim a slot BEFORE emitting: at capacity we DROP the note (return −1 without emitting) rather
        // than emit an on we can't schedule an off for — an untrackable note would hang. The drop is CLEAN
        // (no off owed → no stuck note). 128 slots covers the normal topologies (incl. finite-lived claim
        // ghosts), but ROW-8 BROADCAST-ALL-16 CAN exceed it (a chord × up to 20 voices/note) → some notes
        // drop silently — the note-hungry all-16 fan is the one path that trips this cap. (corrected 2026-08-27)
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
            // MACHINE TAG: hand the reel the sounding cell's DISPLAY hue just before the note-ON, so its piano roll
            // paints each note its machine (no-op on every emitter but the ReelTap). (Paul 2026-08-19)
            if let b = curBox, currentMachineIndex >= 0, Int(currentMachineIndex) < b.machines.count {
                out.markHue(b.machines[Int(currentMachineIndex)].hue)
            }
            out.markCell(currentCellIndex)   // CELL TAG: the PART roll filters to the selected rung per column (Paul 2026-09-03)
            out.emit(sampleTime: onSample, cable: cable, 0x90 | chan, note, max(1, velocity))   // §7 clause 1: note-ons ALWAYS emit
            if refcount[idx] == 0 { distinctSounding += 1 }
            refcount[idx] += 1
            if bus < 4 && onSample > emitterLastOnsetSample[Int(bus)] { emitterLastOnsetSample[Int(bus)] = onSample }   // HOCKET: the wire's latest onset (TRADE reads it)
            // METER-TRUTH (Paul 2026-08-25): a direct-injection note-on (GLIDE) bypasses emitArtic/emitOneBus, so it
            // must light the emitter strip HERE or it sounds invisibly. Opt-in (`meter`) so the normal path — which
            // already meters in emitOneBus — never double-counts. Bus-keyed, same accumulators as §6a metering.
            if meter {
                let bi = Int(bus)
                if bi >= 0 && bi < 4 {
                    let vv = max(1, velocity)
                    if vv > meterPeakVel[bi] { meterPeakVel[bi] = vv }
                    meterEvents[bi] &+= 1
                }
            }
        }

        voices[slot].active = true
        voices[slot].note = note
        voices[slot].chan = chan
        voices[slot].cable = cable
        voices[slot].bus = bus
        voices[slot].offSample = offSample
        voices[slot].silent = silent
        voices[slot].machineIndex = currentMachineIndex   // §2 adoption identity (MACHINE-AND-FACE)
        voices[slot].alt = currentAlt
        voices[slot].vel = velocity                     // §strips-done: for the hold-while-sounding feed
        voices[slot].onBeat = fBeatPos + Double(onSample - fWindowStart) * fBeatsPerSample   // PART ROW ROLL: focusNoteBeat's exact formula
        voices[slot].cellIndex = (currentCellIndex >= 0 && currentCellIndex < Snap.cells) ? Int16(currentCellIndex) : -1   // SEAL sounding gate (Int16 now — was the grid's hard ceiling at Int8's 127)
        voices[slot].bypassRecv = bypassRecv   // BYPASS: tag direct-injection voices so grid/transport flushes skip them
        voices[slot].rtcHold = rtcHold         // RATCHET PATTERN standalone: tag the immortal pass-through sustain (owned by emitColumnRatchetPattern)
        voices[slot].glideAnchor = meter && !rtcHold  // GLIDE: `meter` marks glide direct-injection voices (its sole users — see
                                               // the comment above + the Voice.glideAnchor note); tag them so the
                                               // hold-continuity boundary-close skips them. A reused slot always resets
                                               // this (openVoice rewrites every field), so a later non-glide voice is clean.
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
    /// SEAL comet: read-and-clear the per-CELL peak strike velocity (index = col*Snap.rows+row) since the last poll.
    /// Accumulates across render windows (never lost between polls); the UI stamps a hit time + owns the decay.
    func drainCellStrikes() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: Snap.cells)   // FRESH copy — never share `cellStrike` with the poll (COW-on-render race)
        for i in 0..<Snap.cells { out[i] = cellStrike[i]; cellStrike[i] = 0 }
        return out
    }

    /// NOTE-SWEEP feed: per cell, the note-ons emitted SINCE the last drain (up to 6 most-recent, oldest→newest) as
    /// pitch + velocity, plus a per-cell count. FRESH copies (never share render arrays with the poll). Read-and-clear.
    func drainCellNotes() -> (pitch: [UInt8], vel: [UInt8], count: [UInt8]) {
        var p = [UInt8](repeating: 0, count: Snap.cells * 6), vv = [UInt8](repeating: 0, count: Snap.cells * 6), cnt = [UInt8](repeating: 0, count: Snap.cells)
        for c in 0..<Snap.cells {
            let n = Int(cellNoteNew[c]); cnt[c] = cellNoteNew[c]; cellNoteNew[c] = 0
            for k in 0..<n {
                let idx = ((cellNoteHead[c] - n + k) % 6 + 6) % 6
                p[c * 6 + k] = cellNotePitch[c * 6 + idx]; vv[c * 6 + k] = cellNoteVel[c * 6 + idx]
            }
        }
        return (p, vv, cnt)
    }
    func setFocusCell(_ i: Int) { focusCellIdx = i }   // control-thread hint; process overwrites it each render from its param (torn read benign)
    /// FOCUS note-event feed: the focus cell's note-ons emitted SINCE the last drain (up to focusRing, oldest→newest) as
    /// pitch + velocity + musical BEAT. FRESH copies (never share render arrays). Read-and-clear.
    func drainFocusNotes() -> (pitch: [UInt8], vel: [UInt8], beat: [Double], count: Int) {
        let cap = Router.focusRing
        let n = min(cap, max(0, focusNoteNew)); focusNoteNew = 0
        var p = [UInt8](repeating: 0, count: n), vv = [UInt8](repeating: 0, count: n), bt = [Double](repeating: 0, count: n)
        for k in 0..<n {
            let idx = ((focusNoteHead - n + k) % cap + cap) % cap
            p[k] = focusNotePitch[idx]; vv[k] = focusNoteVel[idx]; bt[k] = focusNoteBeat[idx]
        }
        return (p, vv, bt, n)
    }

    /// item 4 VELOCITY MARKS: read-and-clear the per-emitter note-on marks accumulated since the last poll —
    /// each a (velocity, source machineIndex). The UI latches a timestamp per mark and fades it (~250ms).
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
    /// by originating bus, each a (velocity, source machineIndex). Called on the render thread once per window,
    /// AFTER process reconciles the voice table. Overwrites the buffers (a live set, not an accumulate-clear).
    func snapshotEmitterSounding() {
        for b in 0..<4 { soundCount[b] = 0 }
        for v in voices where v.active && !v.silent {
            let b = Int(v.bus)
            guard b >= 0, b < 4, soundCount[b] < 12 else { continue }
            soundVel[b * 12 + soundCount[b]] = v.vel
            soundCol[b * 12 + soundCount[b]] = Int8(clamping: v.machineIndex)   // CR-13a: the UI-tint feed stays Int8 (a machine ≥128 tints as 127 — cosmetic, no trap)
            soundCount[b] += 1
        }
    }

    /// SEAL comet: snapshot each of the 256 cells' SOUNDING velocity (≥1 active, non-silent voice) into `cellSoundVel`.
    /// Render thread, once per window after reconciliation (like snapshotEmitterSounding). The UI polls `cellSoundingVel-
    /// Snapshot` and derives the sounding GATE from `> 0` (covering all cols incl. 8–15) — the spark lives for the held duration.
    func snapshotCellSounding() {
        for i in 0..<Snap.cells { cellSoundVel[i] = 0 }                    // per-cell sounding VELOCITY: reset then take the max over each cell's active voices (256-wide; the UI derives the sounding GATE from this)
        for v in voices where v.active && !v.silent && v.cellIndex >= 0 && v.cellIndex < Snap.cells {
            if v.vel > cellSoundVel[Int(v.cellIndex)] { cellSoundVel[Int(v.cellIndex)] = v.vel }
        }
    }
    /// UI-poll read of the per-cell SOUNDING velocity (0…127), element-copied into a FRESH array so the main thread never
    /// shares the render buffer (a torn UInt8 read is benign — one stale bar). Feeds the emitter fader's per-machine floor.
    func cellSoundingVelSnapshot() -> [UInt8] {
        var out = [UInt8](repeating: 0, count: Snap.cells)
        for i in 0..<Snap.cells { out[i] = cellSoundVel[i] }
        return out
    }

    /// UI-poll read: the PITCHES currently sounding (active, non-silent voices) for ONE cell — a genuine held-note
    /// snapshot (on until off, via `voices[].cellIndex`/`.active`), not an onset trail. Scanned on demand (128 voices,
    /// no persistent state) — race-safe like `cellSoundingVelSnapshot` (a torn read is benign, one stale frame).
    /// Feeds the processor editor's OUTPUT piano (Paul 2026-09-28: replaces the OUT mini-roll).
    func cellSoundingNotes(_ cellIndex: Int) -> [UInt8] {
        guard cellIndex >= 0 else { return [] }
        var out: [UInt8] = []
        for v in voices where v.active && !v.silent && Int(v.cellIndex) == cellIndex { out.append(v.note) }
        return out
    }

    /// UI-poll read: every actively-sounding (non-silent) voice, bucketed by ENGINE ROW (index = cellIndex %
    /// Snap.rows), each carrying its true onset beat (Voice.onBeat) — feeds the PART grid's live per-row piano-roll
    /// overlay (Paul 2026-09-29). One scan of all 128 voices; race-safe like `cellSoundingNotes` (a torn read is
    /// benign, one stale frame — no locking). BYPASS voices (cellIndex == -1) are naturally excluded, same as
    /// `cellSoundingNotes`. Returns the WHOLE row range unscoped (like `cellSoundingVelSnapshot`), not caller-scoped
    /// — the scan cost is voice-count-bound regardless, so there's no efficiency reason to narrow it.
    func rowSoundingVoices() -> [[(note: UInt8, vel: UInt8, onBeat: Double)]] {
        var out = [[(note: UInt8, vel: UInt8, onBeat: Double)]](repeating: [], count: Snap.rows)
        for v in voices where v.active && !v.silent && v.cellIndex >= 0 {
            out[Int(v.cellIndex) % Snap.rows].append((note: v.note, vel: v.vel, onBeat: v.onBeat))
        }
        return out
    }

    /// UI-poll read: a RIFF cell's own DRUNK walk position (Paul 2026-09-28, closing the last named sweep gap) —
    /// −1 = not yet started / not a RIFF cell / out of range. A plain array read (no scanning), same shape as
    /// `cellSoundingNotes` above. This is genuine accumulated render-thread state with no closed form the UI could
    /// extrapolate between polls (unlike every other RIFF direction, which reads `riffStepAt` directly) — the editor
    /// polls this at the diagnostic cadence and shows it as a discrete jump, not a smooth sweep. That ceiling is
    /// real, not a shortcut: this IS the true position, just not continuously knowable off the render thread.
    func riffDrunkPosAt(_ cellIndex: Int) -> Int {
        guard cellIndex >= 0 && cellIndex < riffDrunkPos.count else { return -1 }
        return riffDrunkPos[cellIndex]
    }

    /// UI-poll read: this cell's EUCLID beacon readiness bits (see `euclidLineReady`'s own declaration for the
    /// bit layout and what "ready" means) — 0 for a cell that isn't currently dispatching as EUCLID, or that
    /// hasn't rendered since its pool last went empty.
    func euclidLineReadyAt(_ cellIndex: Int) -> UInt8 {
        guard cellIndex >= 0 && cellIndex < euclidLineReady.count else { return 0 }
        return euclidLineReady[cellIndex]
    }

    /// UI-poll read: each of Euclideous's 4 lines' own current riff-advance step index (−1 = not started / useRiff
    /// off). Plain array read, same shape as `riffDrunkPosAt` above — unlike that one, this reports ALL 6
    /// directions through one surface (`euclideousRiffStep` is written on every useRiff hit, not just DRUNK).
    func euclideousRiffPositions() -> [Int] { euclideousRiffStep }

    /// NOTE VIEW drain (Paul 2026-10-10 ferry): read-and-clear, FRESH per-lane arrays (never share the
    /// render-written buffers with the poll — same COW/refcount-race avoidance every `drain*` in this
    /// file already follows), oldest→newest, mirroring `drainFocusNotes` exactly. 4 inner arrays (one
    /// per lane), each 0...`noteViewRing` events deep depending on how many that lane posted since the
    /// last drain.
    struct EuclideousNoteViewEventSnapshot: Equatable {
        let onsetBeat: Double
        let durationBeat: Double
        let kind: UInt8
        let notes: [UInt8]
    }
    func drainEuclideousNoteViewEvents() -> [[EuclideousNoteViewEventSnapshot]] {
        var out: [[EuclideousNoteViewEventSnapshot]] = []
        out.reserveCapacity(4)
        for lane in 0..<4 {
            let n = min(Router.noteViewRing, max(0, nvNew[lane])); nvNew[lane] = 0
            var events: [EuclideousNoteViewEventSnapshot] = []
            events.reserveCapacity(n)
            for k in 0..<n {
                let idx = ((nvHead[lane] - n + k) % Router.noteViewRing + Router.noteViewRing) % Router.noteViewRing
                let slot = lane * Router.noteViewRing + idx
                let nbase = slot * Router.noteViewMaxNotes
                let cnt = Int(nvNoteCount[slot])
                let notes = (0..<min(Router.noteViewMaxNotes, cnt)).map { nvNotes[nbase + $0] }
                events.append(EuclideousNoteViewEventSnapshot(onsetBeat: nvOnsetBeat[slot], durationBeat: nvDurationBeat[slot], kind: nvKind[slot], notes: notes))
            }
            out.append(events)
        }
        return out
    }

    /// §strips-done: UI-poll read of the currently-sounding snapshot (main thread; the render/UI race is benign
    /// staleness, identical to the meter + recvHeld feeds). Each emitter → its live (velocity, source machine) set.
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
    /// the last poll — each a (would-be velocity, source machineIndex). The UI draws these hollow + a claim tick.
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
        for i in 0..<4 { emitterLastOnsetSample[i] = .min }   // HOCKET: clear the wire-onset feed on any flush edge (no stale TRADE trigger)
    }
    /// EXTERNAL hard flush — for the Kernel's reel/free-run edges, which close voices OUTSIDE Router.process() and so get
    /// no transport edge. allNotesOff alone closes a glide's immortal ANCHOR voice but leaves its `glideVoices[]` slot
    /// dangling; on resume (host still playing → no process() edge → no flushGlide) a reused slot gets wrong-closed by
    /// glide's phrase-end → a spurious note-off. This mirrors what process() does at its own flush edges, so those Kernel
    /// edges can't strand the glide/mod subsystems. (Paul 2026-09-07, housekeeping — engine Finding 1.)
    func externalFlush(box: SnapshotBox, atSample time: Int64, out: MIDIEmitter?, includeBypass: Bool = false) {
        allNotesOff(atSample: time, out: out, includeBypass: includeBypass)
        flushGlide(atSample: time, out: out)
        flushMod(box: box, atSample: time, out: out)
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
    private func closeExceptLegatoHolds(atSample time: Int64, out: MIDIEmitter?, onlyRow: Int? = nil) {
        // Keep every IMMORTAL voice (offSample .max) — the audible legato drones AND, if a drone landed on a
        // CLAIM emitter, its silent ownership ghost. Both share note+bus+machine+face, so the reconcile adopts
        // or closes them in lockstep (no orphaned ghost leaking a slot). During play these are the ONLY
        // immortal voices (arp/retrig ghosts carry a finite offSample; audition is stopped-only).
        // PER-PART CLOCK: `onlyRow` scopes the truncation to ONE row (a fast part's boundary never cuts a slow part's note).
        for i in voices.indices where voices[i].active && voices[i].offSample != .max
            && (onlyRow == nil || (voices[i].cellIndex >= 0 && Int(voices[i].cellIndex) % Snap.rows == onlyRow!)) {
            closeVoice(i, atSample: time, out: out)
        }
    }

    /// §2 CONTINUITY: ADOPT a legato hold. Scan the transition's candidate voices for the ones matching this
    /// re-held identity — same wire NOTE + EMITTER (bus) + MACHINE-AND-FACE — and un-mark them (keep alive:
    /// own cable + its All copy, both cleared). Returns true iff ≥1 matched, in which case the caller does
    /// NOT re-emit on this bus: the existing voices flow through the boundary with no off/on (the drone).
    private func adoptLegatoBus(wire: UInt8, bus: UInt8, ci: Int16, alt: Bool) -> Bool {
        // Adopt exactly ONE strike's worth — one own-cable copy + one All-cable copy (a strike opens exactly those two
        // per bus). Un-marking EVERY match would break a SELF-COLLIDING harmonize (two source notes fanning to the same
        // wire on one bus, e.g. {60,67}+7 → 60's +7 == 67's root): the first voice's call would un-mark BOTH pairs, the
        // second source's call would then find none, and it would re-strike a fresh immortal voice EVERY window — a
        // per-window voice/refcount leak that machine-guns and grows to the voice cap under PLAY: THIS CELL. Pairing
        // one-per-cable adopts each colliding pair separately. Prefer a real (non-silent) voice over a CLAIM ghost so a
        // ghost is never adopted in a real voice's place and then stranded. Byte-identical for the non-colliding case
        // (one own + one All exist → both un-marked → found) and the identity/drone path (never self-collides).
        var ownIdx = -1, allIdx = -1
        for i in voices.indices where holdCandidate[i]
            && voices[i].note == wire && voices[i].bus == bus
            && voices[i].machineIndex == ci && voices[i].alt == alt {
            if voices[i].cable == 0 {
                if allIdx < 0 || (voices[allIdx].silent && !voices[i].silent) { allIdx = i }
            } else {
                if ownIdx < 0 || (voices[ownIdx].silent && !voices[i].silent) { ownIdx = i }
            }
        }
        var found = false
        if ownIdx >= 0 { holdCandidate[ownIdx] = false; found = true }
        if allIdx >= 0 { holdCandidate[allIdx] = false; found = true }
        return found
    }

    private func anyVoiceActive() -> Bool {
        for v in voices where v.active { return true }
        return false
    }
    /// PER-PART CLOCK: any active voice belonging to ROW `r` (cellIndex row = index % Snap.rows) — the per-row transition gate.
    private func anyVoiceActiveInRow(_ r: Int) -> Bool {
        for v in voices where v.active && v.cellIndex >= 0 && Int(v.cellIndex) % Snap.rows == r { return true }
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
    // hasDuplicateVoices (an I3 adoption-miss diagnostic) RETIRED (Paul 2026-09-12 dead-code sweep — no caller, not even in Tests).
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
        // DEAL (Paul 2026-09-16): OVERRIDE the emitters — deal N1 notes → emitter 1, N2 → emitter 2 (cycling). A per-cell live
        // counter (same class as ALT/TURNS): OVER TIME advances per STRIKE (onset moment) · WITHIN CHORD per note in the moment
        // (a chord split by rank) · EVERY NOTE per note-on. previewMode bypasses; wins over the cell's own emitters + chopMask.
        if dealActive && !previewMode, currentCellIndex >= 0, currentCellIndex < dealMoment.count {
            let c = currentCellIndex
            if onSample != dealLastOnset[c] { dealLastOnset[c] = onSample; dealMoment[c] &+= 1; dealNoteInMoment[c] = 0 } else { dealNoteInMoment[c] &+= 1 }
            dealGlobal[c] &+= 1
            let cyc = max(1, dealN1 + dealN2)
            let pos: Int
            switch dealMode {
            case .overTime:    pos = dealMoment[c]
            case .withinChord: pos = dealNoteInMoment[c]
            case .everyNote:   pos = dealGlobal[c] - 1
            }
            busMask = UInt8(1) << UInt8((((pos % cyc) + cyc) % cyc) < dealN1 ? dealE1 : dealE2)
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
                        withheldVel[bus * 8 + withheldCount[bus]] = velocity; withheldCol[bus * 8 + withheldCount[bus]] = Int8(clamping: currentMachineIndex)
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
        // THE FLOOD GOVERNOR — the CAPACITY check runs BEFORE the MONO steal (CR-5): a hard per-emitter budget per beat;
        // overflow DROPS (counted, not silent-failing). Offs are never governed, so a dropped on never opens a voice.
        // Ordering matters: if the governor would drop this note, return -1 NOW — else MONO below closes the emitter's
        // holder for a note the governor then drops → the emitter goes silent for the beat. previewMode is exempt.
        if !previewMode && noteOnsThisBeat[bus] >= Router.floodCapPerBeat { floodDropped &+= 1; return -1 }
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
                    if voices[i].glideAnchor { forgetGlideAnchorAtSlot(i, atSample: onSample, out: out) }   // MONO stole a glide anchor → drop the glide's stale slot ref (else a reused slot is wrong-closed later)
                    closeVoice(i, atSample: onSample, out: out)
                }
            }
        }
        // CONSUME the flood budget only once the note is going to sound (after MONO's suppression decision, so a
        // MONO-suppressed note doesn't eat the budget — behaviour-preserving for the non-flood case).
        if !previewMode { noteOnsThisBeat[bus] &+= 1 }
        if v > meterPeakVel[bus] { meterPeakVel[bus] = v }   // §6a metering (post-transform vel, incl. override)
        meterEvents[bus] &+= 1
        if currentCellIndex >= 0 && currentCellIndex < Snap.cells {   // Snap.cells = 128 (was 64 — dropped the strike/note feed for cols 4–7, whose index ≥64)
            if v > cellStrike[currentCellIndex] { cellStrike[currentCellIndex] = v }   // SEAL comet: this cell struck
            let c = currentCellIndex, h = cellNoteHead[c]                              // NOTE-SWEEP: record the emitted pitch+vel (ring)
            cellNotePitch[c * 6 + h] = note; cellNoteVel[c * 6 + h] = v
            cellNoteHead[c] = (h + 1) % 6
            if cellNoteNew[c] < 6 { cellNoteNew[c] &+= 1 }
        }
        if currentCellIndex == focusCellIdx && focusCellIdx >= 0 && !previewMode {     // FOCUS note-event feed: the machine's cell → the REAL emitted note + its BEAT (Paul 2026-08-31)
            let fh = focusNoteHead
            focusNotePitch[fh] = note; focusNoteVel[fh] = v
            focusNoteBeat[fh] = fBeatPos + Double(onSample - fWindowStart) * fBeatsPerSample
            focusNoteHead = (fh + 1) % Router.focusRing
            if focusNoteNew < Router.focusRing { focusNoteNew &+= 1 }
        }

        if markCount[bus] < 8 {                              // item 4: a floating velocity MARK for this note-on
            markVel[bus * 8 + markCount[bus]] = v; markCol[bus * 8 + markCount[bus]] = Int8(clamping: currentMachineIndex)
            markCount[bus] += 1
        }
        // ROW 8 REDIRECT / SWAP (Paul 2026-08-22): while active, this emitter's OUTPUT stream is re-stamped onto another
        // wire — the note comes out on `outWire`'s cable + channel (previewMode bypasses). The origin `bus` is kept for the
        // enable/claim/meter gates + the voice's adoption key, and the ACTUAL (cable, chan) is stored in the voice, so a
        // note in flight when the redirect is RELEASED still closes on the wire it opened (no stuck note — the handoff). 1:1 default ⇒ byte-identical.
        let outWire = previewMode ? Int(bus) : Int(busRemap[Int(bus)])
        let ch = (chanOverride >= 0 && !previewMode) ? UInt8(chanOverride) : (busChannels[outWire] &- 1) & 15   // UTILITY CHANNEL override (previewMode bypasses, like NUDGE), else the (remapped) bus stamp (1–16 → 0–15 wire)
        // THE RACK POCKET (per-emitter) + UTILITY NUDGE (per-cell): shift this note's on/off by the timing offset
        // (samples). Both shift equally so the duration is preserved; the on is clamped into [renderStart, windowEnd]
        // (can't play in the past or beyond the window), and a held note (offSample .max) keeps its immortal off. previewMode bypasses.
        var onS = onSample, offS = offSample
        let shift = ((bit(pocketMask, bus) && !previewMode) ? pocketSamples[bus] : 0) + (previewMode ? 0 : nudgeSamples)
        if shift != 0 {
            let target = onSample + shift
            onS = max(renderStart, min(windowEnd, target))
            if offSample != .max { offS = max(onS + 1, offSample + (onS - onSample)) }
        }
        if broadcastActive && !previewMode {
            // ROW 8 BROADCAST (Paul 2026-08-24): the WALL — mirror this note to ALL 4 emitter wires, each on its own stamp
            // channel (chanOverride still wins). Each voice stores its cable, so a note in flight when broadcast is
            // released closes on the wire it opened (no stuck notes). v1: fans to the 4 WIRES (not all 16 channels).
            for w in 0..<4 {
                let wch = (chanOverride >= 0) ? UInt8(chanOverride) : (busChannels[w] &- 1) & 15
                let bv = openVoice(note: note, chan: wch, cable: UInt8(w + 1), bus: UInt8(bus),
                                   onSample: onS, offSample: offS, velocity: v, out: out)
                if bv >= 0 && offS <= windowEnd { closeVoice(bv, atSample: offS, out: out) }
            }
        } else {
            let own = openVoice(note: note, chan: ch, cable: UInt8(outWire + 1), bus: UInt8(bus),   // REDIRECT/SWAP: own cable follows the remapped wire
                                onSample: onS, offSample: offS, velocity: v, out: out)
            if own >= 0 && offS <= windowEnd { closeVoice(own, atSample: offS, out: out) }
        }
        if broadcastAll16 && !previewMode {
            // ROW 8 BROADCAST all-16 (Paul 2026-08-26): fan the ALL-cable copy across every MIDI channel (a multitimbral
            // wall). Each (cable 0, channel c, note) is a distinct refcount key → each closes cleanly (no stuck notes).
            // Note-hungry (16× per note) — the flood governor applies. Only reached while BROADCAST is lit.
            for c in UInt8(0)..<16 {
                let av = openVoice(note: note, chan: c, cable: 0, bus: UInt8(bus), onSample: onS, offSample: offS, velocity: v, out: out)
                if av >= 0 && offS <= windowEnd { closeVoice(av, atSample: offS, out: out) }
            }
        } else {
            let all = openVoice(note: note, chan: ch, cable: 0, bus: UInt8(bus),
                                onSample: onS, offSample: offS, velocity: v, out: out)
            if all >= 0 && offS <= windowEnd { closeVoice(all, atSample: offS, out: out) }
        }
        return Int(ch)
    }

    /// HOLD content, emitted ONCE per column at the transition: an identity cell whose input is MIDI
    /// IN articulates the whole (filtered) source chord and holds it to the column boundary (identity
    /// = sample-and-hold of its input pool). Arp cells and referencing mirrors have no hold.
    /// HARMONIZE emit (§3): expand `base` (post-transpose) into root + up to 3 interval voices and
    /// emit each with its velocity (root full, added voices scaled). Optionally stores artics so a
    /// downstream mirror sees the full expanded set. Shared by the MIDI-IN hold and the mirror path.
    private func emitHarmony(base: Int, machine: SnapMachine, baseVel: UInt8, row: Int,
                             storeArtics: Bool, busMask: UInt8,
                             on: Int64, off: Int64, beat: Double,
                             windowEnd: Int64, sustain: Bool = false, poolMask: UInt16 = 0, out: MIDIEmitter?,
                             diag: inout KernelDiag) {
        let iv = (Int8(effectiveHarmInterval(machine, voice: 0)),
                  Int8(effectiveHarmInterval(machine, voice: 1)),
                  Int8(effectiveHarmInterval(machine, voice: 2)))
        let scale = effectiveHarmVelScale(machine)
        let cnt = harmonizeVoices(base: base, intervals: iv, into: &harmNotes,
                                  vel: baseVel, velScale: scale, vels: &harmVels, poolMask: poolMask)
        for i in 0..<cnt {
            if storeArtics { storeArtic(row: row, on: on, off: off, note: UInt8(harmNotes[i]), beat: beat) }
            guard busMask != 0 else { continue }
            if sustain {
                // PLAY: THIS CELL — under a frozen column each harmony voice is IMMORTAL + ADOPTED (per-bus, mirrors
                // the identity legato branch), so the every-window re-run reconciles the same harmonized set instead
                // of re-striking. Voices carry currentMachineIndex/currentAlt so adoptLegatoBus matches on re-run.
                var emitMask: UInt8 = 0
                for b in UInt8(0)..<4 where busMask & (1 << b) != 0 {
                    let sw = Int(harmNotes[i]) + emitterOctaveShift(Int(b)) + masterKey
                    guard sw >= 0 && sw <= 127 else { continue }
                    guard let w = fencedNote(UInt8(sw), bus: Int(b)) else { continue }
                    if !adoptLegatoBus(wire: w, bus: b, ci: currentMachineIndex, alt: currentAlt) { emitMask |= (1 << b) }
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

    // PER-PART CLOCK (Paul 2026-08-19): ONE row's per-window TICK content at `effColumn`, on `S`/`cycleBeats`. Extracted
    // from the process() row loop so BOTH the uniform fast-path AND the per-row multi-clock path share it verbatim.
    // Reads `diag.pass` (the caller sets it to the ROW's pass in the per-row path). No behaviour change vs the old inline loop.
    // PHASE 2 render-time AUTO (Paul 2026-09-04): a ×N-passes / SMOOTH lane overrides one scalar param on this cell's proc,
    // computed from the beat. STEP = per-column (integer rank, endpoint-inclusive, matches the Phase-1 bake). SMOOTH =
    // a continuous sawtooth across the span, SAMPLED ONCE PER RENDER WINDOW (block-start beat, like applyInternalMods) —
    // so a SMOOTH value is quantized to block boundaries, not strictly block-size-invariant (deterministic per host
    // schedule; STEP flips only at column boundaries, which are per-block, so STEP is invariant). Derived from the beat →
    // replay-exact for a given schedule. No render-path alloc UNLESS a lane is active (the settingAuto SnapParams is a
    // value copy, but the `cell.procs[slot] =` write-back below is a COW of the procs array — feature-gated: the
    // byte-identical default writes nothing). ra.slot is resolved against the machine TEMPLATE; a per-cell chain override
    // of a different type at that slot would get a harmless ignored field (never a trap — slot bound-guarded).
    private func applyRenderAuto(_ cell: inout SnapCell, box: SnapshotBox, r: Int, musicalBeat mb: Double, S: Double) {
        let ci = Int(cell.machineIndex)
        guard ci >= 0, ci < box.renderAuto.count, let ra = box.renderAuto[ci],
              ra.slot >= 0, ra.slot < cell.procs.count, S > 0 else { return }
        let W = max(1, box.rowLength.indices.contains(r) ? box.rowLength[r] : Snap.cols)
        let period = ra.passes >= 2 ? ra.passes * W : (ra.spanCols > 0 ? ra.spanCols : W)
        guard period >= 1 else { return }
        let posCols = mb / S - Double(ra.startCol)   // continuous column position past the span start
        guard posCols >= 0 else { return }           // before the span → leave the base param
        let m = Double(period)
        let frac: Double
        if ra.smooth { frac = posCols.truncatingRemainder(dividingBy: m) / m }                     // continuous sawtooth 0…1
        else { let rank = Int(posCols) % period; frac = period > 1 ? Double(rank) / Double(period - 1) : 1 }   // stepped, endpoint-inclusive
        cell.procs[ra.slot] = cell.procs[ra.slot].settingAuto(ra.field, ra.lo + frac * (ra.hi - ra.lo))
    }
    /// PER-PARAM LFO (Docs/PLAN-param-lfo.md): oscillate scalar params around their base value. Beat-derived → replay-safe
    /// (invariant 2); the `cell.procs[si] = …` write-back is a COW of the procs array (same accepted render-path alloc as
    /// applyRenderAuto — feature-gated on box.hasParamLFO, so byte-identical + alloc-free when no LFO is active); reshapes a scalar only, opens/closes no voices
    /// (invariant 4). Sampled at the window beat, like SMOOTH renderAuto / applyInternalMods (block-start, deterministic per
    /// schedule). Runs AFTER renderAuto + internal MOD, so it swings around a base that already includes those (the ratified
    /// "sum" behaviour). Called only when box.hasParamLFO (else byte-identical). (Paul 2026-09-15.)
    private func applyParamLFO(_ cell: inout SnapCell, box: SnapshotBox, r: Int, beat mb: Double, S: Double, column: Int) {
        guard S > 0 else { return }
        let W = max(1, box.rowLength.indices.contains(r) ? box.rowLength[r] : Snap.cols)
        let gridBeats = Double(W) * S
        for si in cell.procs.indices where !cell.procs[si].paramLFOs.isEmpty {
            for lfo in cell.procs[si].paramLFOs {
                // BASE → TO sweep (Paul 2026-09-16 two-views): FROM ≡ the processor's own param (its authored base value),
                // so the LFO stores only TO. The shape's 0…1 maps BASE→TO→BASE. Inactive when TO == the base (guarded).
                guard let to = lfo.to else { continue }
                // DURATION: grid STEPS (stepSpan, re-syncs to the grid) or a fixed musical subdivision (period).
                let periodBeats = (lfo.stepSpan ?? 0) > 0 ? spanLadderBeats(lfo.stepSpan!, S: S, row: gridBeats) : lfo.period.periodBeats
                guard periodBeats > 0 else { continue }
                let cyc = Int((mb / periodBeats).rounded(.down))
                let u = modUnipolar(lfo.shape, phase: mb / periodBeats, column: column, cc: 0, cycleIndex: cyc)   // 0…1
                if lfo.target == "arpRate" {                                       // rate = the discrete ladder index (0…17); FROM = the base rate, TO = a rate pick
                    let from = Double(max(0, min(17, Int(cell.procs[si].rateIndex))))   // the authored base rate IS the FROM endpoint
                    guard from != to else { continue }
                    // IGNORE families (Paul 2026-09-16): sweep over the ALLOWED-rate ladder only, so ignored families are
                    // never visited (snap FROM/TO to the nearest kept rung, interpolate over ladder POSITIONS).
                    let ladder = arpRateAllowedLadder(ignore: lfo.rateIgnoreResolved)
                    let fp = nearestLadderPos(ladder, Int(from.rounded())), tp = nearestLadderPos(ladder, Int(to.rounded()))
                    let pos = Int((Double(fp) + u * Double(tp - fp)).rounded())
                    cell.procs[si].rateIndex = Int8(ladder[max(0, min(ladder.count - 1, pos))])
                } else if let field = AutoParamField(key: lfo.target) {
                    let from = cell.procs[si].autoValue(field)                     // the authored base param IS the FROM endpoint
                    guard from != to else { continue }
                    cell.procs[si] = cell.procs[si].settingAuto(field, from + u * (to - from))   // sweep base→TO; settingAuto clamps
                }
            }
        }
    }
    private func emitTickRow(r: Int, effColumn: Int, S: Double, cycleBeats: Double, windowBeats: Double,
                             box: SnapshotBox, pool: NotePool, beatPos: Double, windowStart: Int64, windowEnd: Int64,
                             beatsPerSample: Double, a: Double, heldCell: Int, out: MIDIEmitter?, diag: inout KernelDiag) {
            var cell = box.cells[effColumn * Snap.rows + r]
            if cell.machineIndex < 0 || cell.muted || cell.dormant { return }   // LADDER dormant
            applyInternalMods(&cell, column: effColumn, pool: pool, mNow: musicalOf(beatPos, stepBeats: S, a: a), S: S, cycleBeats: cycleBeats, box: box)   // §2 INTERNAL MOD: modulate this cell's chain params (no-op unless a MOD targets the chain)
            if !box.renderAuto.isEmpty { applyRenderAuto(&cell, box: box, r: r, musicalBeat: musicalOf(beatPos, stepBeats: S, a: a), S: S) }   // PHASE 2: ×N/SMOOTH render-time param ramp
            if box.hasParamLFO { applyParamLFO(&cell, box: box, r: r, beat: musicalOf(beatPos, stepBeats: S, a: a), S: S, column: effColumn) }   // PER-PARAM LFO (Docs/PLAN-param-lfo.md): swing scalar params around their base
            if soloSilenced(cell) { return }   // receiver strip: input SOLO excludes this cell's receiver
            currentInputRecv = cell.resolvedReceiver   // receiver strip: this cell's receiver, for the input-vel override
            currentMachineIndex = cell.machineIndex      // item 4 marks: this cell's Machine, for the source tint
            currentCellIndex = effColumn * Snap.rows + r  // SEAL comet: this cell's grid index (the sounding column)
            chanOverride = cellChanOverride(cell); nudgeSamples = cellNudgeSamples(cell, beatsPerSample: beatsPerSample, step: effColumn)   // UTILITY CHANNEL/NUDGE emit overrides for this cell
            dealSetup(cell)   // DEAL: this cell's emitter-deal state (Paul 2026-09-16)
            let ci = Int(cell.machineIndex)
            let machine = box.machines[ci]
            if !onSceneAudible(machine.on, pass: diag.pass) { return }   // §9 item 1 ON SCENE: not entered / exited
            // §9 item 1 ON HOLD (3a): while THIS cell is press-held, its ALT/OCT treatment overlays momentarily.
            let held = heldCell >= 0 && heldCell == effColumn * Snap.rows + r
            var transpose = machineTranspose(ci, machine)
                          + holdOctaveShift(on: machine.on, held: held)   // ON HOLD = OCT
                          + octaveShift(cell.resolvedReceiver)           // receiver strip: input OCT nudge
            // CELL MACHINE: the per-cell HEAD treatment (cell.proc) drives the render (morph + grid-chaining retired).
            var treat = machine; treat.a = cell.proc
            let mode = cellMode(type: effectiveType(treat), bypassed: cell.bypassed)
            let emits = cell.busMask != 0   // fan-out across every lit bus happens inside emitArtic
            // DRONE = a legato chord-hold (user 2026-08-10): a SINGLE-SLOT drone sustains via emitColumnHolds (adopts
            // across adjacent drone columns, closes where no drone re-holds it), NOT the per-tick generator — skip it
            // here so it doesn't strike per step. A drone inside a multi-slot CHAIN keeps the generator path (v1).
            if mode == .drone && cell.procs.count <= 1 { return }

            // CELL MACHINE stage-2: a covered chain (arp/ratchet/strum TAIL) runs the tail over the composed
            // upstream set; only the tail emits, and emitColumnHolds skips it.
            let driver = chainDriverIndex(cell)
            if driver >= 0 {
                let driveP = cell.procs[driver]                // the tick DRIVER (last tick-gen); slots before it compose, after it fold
                var treatDrive = machine; treatDrive.a = driveP
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
                // AVOID+MOVE downstream ([driver→AVOID(move)]): resolve the driver's whole output pool's SURVIVING classes
                // (pool classes ∉ the avoided sphere), so a blocked driven note snaps to an in-scale survivor instead of
                // dropping (B-1). Applied in emitDriverNote's fold (gated by avoidDriverSurvivorValid there). Paul 2026-08-31.
                avoidDriverSurvivor = 0
                if let ai = downstreamAvoidMoveIndex(cell, after: driver) {
                    let ap = cell.procs[ai]
                    let ep = effectivePool(for: cell, live: pool)
                    let cnt = ep.srcCount(for: cell)
                    let refMask = avoidRefMask(ap, ownDoor: Int(cell.resolvedReceiver), ownBusMask: cell.busMask)
                    avoidDriverSurvivor = avoidSurvivors({ Int(ep.srcAscending($0, for: cell)) }, count: cnt, refMask: refMask)
                }
                switch driveP.type {
                case .arp:
                    emitArpRow(cell: cell, row: r, machine: treatDrive, transpose: transpose,
                               emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                               windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                               beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats,
                               chainDriver: driver, out: out, diag: &diag)
                case .ratchet:
                    emitRatchetRow(cell: cell, row: r, machine: treatDrive, transpose: transpose,
                                   emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                                   windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                                   beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats,
                                   chainDriver: driver, out: out, diag: &diag)
                case .strum:
                    emitStrumRow(cell: cell, row: r, machine: treatDrive, transpose: transpose, emits: emits,
                                 pool: pool, beatPos: beatPos, windowStart: windowStart, windowEnd: windowEnd,
                                 beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, chainDriver: driver, out: out, diag: &diag)
                case .euclid, .burst, .cascade, .drone, .shift, .humanize, .hocket:   // GENERATORS as chain drivers (user 2026-08-09; HOCKET 2026-08-27)
                    let dm = cellMode(type: driveP.type, bypassed: false)
                    emitGeneratorRow(mode: dm, cell: cell, row: r, machine: treatDrive, transpose: transpose, emits: emits,
                                     pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                                     windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                     S: S, a: a, cycleBeats: cycleBeats, chainDriver: driver, out: out, diag: &diag)
                case .weave:
                    emitWeaveRow(cell: cell, row: r, machine: treatDrive, transpose: transpose, emits: emits,
                                 pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                                 windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                 S: S, a: a, cycleBeats: cycleBeats, chainDriver: driver, out: out, diag: &diag)
                case .riff:
                    emitRiffRow(cell: cell, row: r, machine: treatDrive, transpose: transpose, emits: emits,
                                box: box, pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                                windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                S: S, a: a, cycleBeats: cycleBeats, chainDriver: driver, out: out, diag: &diag)
                default: break
                }
                return
            }
            if let li = composableLengthTailIndex(cell) {   // [<composable upstream> → LENGTH]: LENGTH re-articulates the composed set (no driver to fold it per-note)
                emitLengthComposedRow(cell: cell, row: r, machine: machine, transpose: transpose, emits: emits,
                                      lenIdx: li, pool: pool, beatPos: beatPos, windowBeats: windowBeats,
                                      windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                      S: S, a: a, out: out, diag: &diag)
                return
            }
            if isHoldTailChain(cell) { return }   // CELL MACHINE: a hold-tail chain emits at column boundaries (emitColumnHolds), not here

            switch mode {
            case .arp:
                emitArpRow(cell: cell, row: r, machine: treat, transpose: transpose,
                           emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                           windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                           beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .ratchet:
                emitRatchetRow(cell: cell, row: r, machine: treat, transpose: transpose,
                               emits: emits, box: box, pool: pool, effColumn: effColumn, beatPos: beatPos,
                               windowBeats: windowBeats, windowStart: windowStart, windowEnd: windowEnd,
                               beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .strum:
                emitStrumRow(cell: cell, row: r, machine: treat, transpose: transpose, emits: emits,
                             pool: pool, beatPos: beatPos, windowStart: windowStart, windowEnd: windowEnd,
                             beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .euclid, .burst, .cascade, .drone, .shift, .humanize, .hocket:
                // PART GRID × GENERATOR interaction bug (Paul 2026-10-04, "it feels more like a problem with the
                // part grid than the euclid, or it may be in the way they interact"): this STANDALONE-driver branch
                // (chainDriverIndex(cell) < 0 — no multi-slot chain to fold) used to omit cycleBeats entirely, so
                // emitGeneratorRow's `cyc = cycleBeats > 0 ? cycleBeats : Double(Snap.cols) * S` silently fell back
                // to the hardcoded 8-column default — on a 16-wide part (or any row whose per-part RATE/LENGTH
                // differs from the scene default, forcing the multi-clock path), the generator's own SPAN re-anchor
                // and its `columns:` wraparound both derived from that wrong, too-short cycle, permanently capping
                // it to the FIRST HALF of a 16-column pass (or more generally, Snap.cols worth of it) — reproduced
                // in testEuclidFreshRowOnA16WidePartPlaysThroughAllSixteenColumns. The sibling ARP/RATCHET/RIFF
                // cases a few lines above already pass cycleBeats correctly; this was the one gap.
                emitGeneratorRow(mode: mode, cell: cell, row: r, machine: treat, transpose: transpose, emits: emits,
                                 pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                                 windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                 S: S, a: a, cycleBeats: cycleBeats, chainDriver: driver, out: out, diag: &diag)
            case .weave:
                emitWeaveRow(cell: cell, row: r, machine: treat, transpose: transpose, emits: emits,
                             pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                             windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                             S: S, a: a, cycleBeats: cycleBeats, chainDriver: driver, out: out, diag: &diag)
            case .riff:                            // DRIVER — the stored rank stencil, derived against the held chord
                emitRiffRow(cell: cell, row: r, machine: treat, transpose: transpose, emits: emits,
                            box: box, pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                            windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                            S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .echo, .identity, .chance, .harmonize, .split, .avoid, .chords, .octave, .transpose:
                break   // echo's dry fired at the transition (repeats drain per-window); the set-shapers (CHANCE/HARMONIZE/SPLIT/AVOID/CHORDS · OCTAVE/TRANSPOSE shift) emit via the compose/hold path, not per-tick
            case .tutti:
                if treat.a.tuttiMode == .pattern {   // PATTERN re-articulates per slice here; COIN is a hold (emitColumnHolds)
                    emitTuttiPatternRow(cell: cell, row: r, machine: treat, transpose: transpose, emits: emits,
                                        pool: pool, beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                                        windowEnd: windowEnd, beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
                }
            case .length:                          // standalone LENGTH re-articulates the held chord per the painted gate
                emitLengthRow(cell: cell, row: r, machine: treat, transpose: transpose, emits: emits,
                              pool: pool, beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                              windowEnd: windowEnd, beatsPerSample: beatsPerSample, S: S, a: a, cycleBeats: cycleBeats, out: out, diag: &diag)
            case .silent:
                break   // a silenced downstream stage → nothing this window
            }
    }

    private func emitColumnHolds(box: SnapshotBox, column: Int, pool: NotePool, pass: Int,
                                 S: Double, a: Double, mNow: Double, beatPos: Double,
                                 beatsPerSample: Double, windowStart: Int64,
                                 windowEnd: Int64, tempo: Double, out: MIDIEmitter?,
                                 // PART GRID × GENERATOR interaction bug (Paul 2026-10-05, same root cause as the
                                 // EUCLID 16-wide-part fix the day before): STRIKE PER SPAN and the CHORDS-hold
                                 // composeChainSet pass counter used to hardcode Double(Snap.cols) * S instead of
                                 // the row's REAL cycle length — correct only by coincidence on a default 8-column,
                                 // default-rate row. Required (no default): this function has no business guessing
                                 // a row's length when every caller already has the right value in scope (the
                                 // uniform fast path's own global cycleBeats, or the multi-clock path's per-row cycR).
                                 cycleBeats: Double,
                                 reconcileOnly: Bool = false,   // PLAY: THIS CELL frozen-column re-run — adopt/close the immortal holds only, never re-strike
                                 auditionSustain: Bool = false, // PINNED continuous row (the SELECT/PLAY audition): sustain EVERY hold like forceColumnHold, so a frozen single-column preview rings continuously
                                 onlyRow: Int? = nil,           // PER-PART CLOCK: scope the hold reconcile + emit to ONE row
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
        // CLAIM ghosts of a drone are candidates too (adoptLegatoBus matches them by note+bus+machine+face), so
        // a ghost adopts/closes in lockstep with its audible voice — never orphaned.
        for i in voices.indices { holdCandidate[i] = voices[i].active && voices[i].offSample == .max && voices[i].bypassRecv < 0 && !voices[i].glideAnchor && !voices[i].rtcHold
            && (onlyRow == nil || (voices[i].cellIndex >= 0 && Int(voices[i].cellIndex) % Snap.rows == onlyRow!)) }   // BYPASS + GLIDE voices are immortal but NOT grid holds — never adopt/close them here; per-part clock scopes to the row
        // Proceed while the LIVE pool has notes OR any receiver is latch-armed: an armed receiver's FROZEN pool
        // feeds its subscribers even with no keys down (effectivePool). Non-subscribing cells read the empty live
        // pool → emit nothing, so opening the gate for the latch is safe. (Without this, the release of the keys
        // emptied the live pool and the whole hold loop was skipped — the latch "did nothing".)
        if pool.count > 0 || latchMask != 0 {
        for r in 0..<Snap.rows where onlyRow == nil || onlyRow == r {   // PER-PART CLOCK: one row, or all (no per-call allocation)
            var cell = box.cells[column * Snap.rows + r]
            if cell.machineIndex < 0 || cell.busMask == 0 || cell.muted || cell.dormant { continue }   // LADDER dormant
            if cell.passthrough && cell.resolvedReceiver >= 0 { continue }   // NO-MACHINE WIRE (Paul 2026-08-23): a door-connected passthrough passes its input straight through in REALTIME (reconcileBypass), NOT on the grid's step clock. (A door-less passthrough — no receiver to source from in the per-door bypass pass — stays a gridded hold.)
            if !box.renderAuto.isEmpty { applyRenderAuto(&cell, box: box, r: r, musicalBeat: mNow, S: S) }   // PHASE 2: ×N/SMOOTH render-time param ramp (a hold samples the value at the column-entry beat)
            applyInternalMods(&cell, column: column, pool: pool, mNow: mNow, S: S, cycleBeats: cycleBeats, box: box)   // §2 INTERNAL MOD: modulate this hold cell's chain params (no-op unless a MOD targets the chain)
            if box.hasParamLFO { applyParamLFO(&cell, box: box, r: r, beat: mNow, S: S, column: column) }   // PER-PARAM LFO (Docs/PLAN-param-lfo.md): swing scalar params around their base
            if isCoveredChain(cell) { continue }   // CELL MACHINE stage-2: the ARP tail emits in the tick loop; the head must not chord-hold here
            if composableLengthTailIndex(cell) != nil { continue }   // [→ LENGTH] re-articulates the composed set in the tick loop (emitLengthComposedRow), never a plain hold here
            if isEchoTail(cell) { continue }       // ECHO: an echo-tail cell fires its dry + tail in emitEchoColumn, never a hold here
            if soloSilenced(cell) { continue }   // receiver strip: input SOLO excludes this cell's receiver
            currentInputRecv = cell.resolvedReceiver   // receiver strip: this cell's receiver, for the input-vel override
            currentMachineIndex = cell.machineIndex      // item 4 marks: this cell's Machine, for the source tint
            currentCellIndex = column * Snap.rows + r  // SEAL comet: this cell's grid index
            chanOverride = cellChanOverride(cell); nudgeSamples = cellNudgeSamples(cell, beatsPerSample: beatsPerSample, step: column)   // UTILITY CHANNEL/NUDGE emit overrides for this hold cell
            dealSetup(cell)   // DEAL: this cell's emitter-deal state (Paul 2026-09-16)
            let ci = Int(cell.machineIndex)
            let machine = box.machines[ci]
            // Cells that chord-hold their MIDI-IN source: identity, CHANCE
            // (drops each note by probability), and HARMONIZE (expands each note to voices).
            // Arp/ratchet/strum do not chord-hold.
            if !onSceneAudible(machine.on, pass: pass) { continue }   // §9 item 1 ON SCENE: not entered / exited
            let altFlag = cell.alt                                   // this cell's voice-identity face
            currentAlt = altFlag                                     // §2 stamp fresh voices' face identity
            // CELL MACHINE: a HOLD-TAIL chain holds the TAIL slot's transform of every upstream stage's composed
            // set; a plain cell holds its head-only treatment of the source.
            let holdChain = isHoldTailChain(cell)
            let holdEchoMute = holdChain && (chainEchoIndex(cell).map { !cell.procs[$0].echoThru } ?? false)   // ECHO MUTE in a hold chain (Paul 2026-08-26): echoes only — suppress the dry (the tails register below); THRU keeps the dry
            let tailIdx = cell.procs.count - 1
            var treat = machine; let treatP = holdChain ? cell.procs[tailIdx] : cell.proc
            treat.a = treatP
            let mode = cellMode(type: effectiveType(treat),
                                bypassed: holdChain ? cell.slotBypass[tailIdx] : cell.bypassed)
            guard mode == .identity || mode == .chance || mode == .harmonize || mode == .drone || mode == .tutti || mode == .split || mode == .avoid || mode == .octave || mode == .transpose || mode == .chords else { continue }   // DRONE = a legato chord-hold (user 2026-08-10); TUTTI/SPLIT/AVOID = SET/pitch filters; OCTAVE/TRANSPOSE = pitch SHIFTS (Paul 2026-08-22); CHORDS = a diatonic SET-REPLACE (a lone/tail hold sounds the derived chord — Paul 2026-09-01)
            if mode == .tutti && !holdChain && treat.a.tuttiMode == .pattern { continue }   // PATTERN standalone re-articulates per slice in the tick loop, not here
            // CHORDS (Paul 2026-09-01): the stage REPLACES the set with a derived diatonic chord. Compose it INTO
            // chainScratch (upto the CHORDS slot INCLUSIVE) and read the emission source from chainScratch — so a lone
            // [CHORDS] and a [X→CHORDS] tail both SOUND the chord as a plain (legato-adoptable) hold, no per-rank map.
            let chordsHold = (mode == .chords)
            let readScratch = holdChain || chordsHold
            let transpose = machineTranspose(ci, machine)
                          + octaveShift(cell.resolvedReceiver)           // receiver strip: input OCT nudge
                          + holdShift(treatP, mode: mode)                // UTILITY: OCTAVE (±12·n) / TRANSPOSE (±semitones) shift the held (composed) set
            let prob = (mode == .chance) ? effectiveProbability(treat.a, step: Int((colStart / S).rounded())) : 1   // CHANCE PATTERN: per-step odds (Paul 2026-08-22)
            let droneScale = mode == .drone ? max(0.05, min(1.0, treatP.gate)) : 1.0   // DRONE: GATE = the pad's velocity level (relative to the source)
            let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: pass)   // §9 item 1 EMITTER-ROTATE
            // §2 CONTINUITY: an identity chord-hold under LEGATO is a DRONE — it flows through column
            // boundaries. RETRIG (and .free) re-strike as before; CHANCE/HARMONIZE re-speak (per-column
            // dice / expansion); the ALT turn-group is excluded (a rotating emitter is a fresh strike).
            // PLAY: THIS CELL (forceColumnHold) freezes the column, so this can't re-fire on a boundary to sustain a
            // gated hold — the cell would sound one column then die. Treat EVERY hold mode (identity / chance /
            // harmonize) as immortal+adopted so the machine plays CONTINUOUSLY; the frozen colStart makes the chance
            // dice + harmony stable, so the every-window re-run (reconcileOnly) adopts the identical set (no re-strike).
            // A FROZEN-COLUMN preview sustains EVERY hold (Paul device 2026-09-01): PLAY THIS CELL (forceColumnHold) AND the
            // continuous SELECT/PLAY audition (a row PINNED to one column → no re-firing transition, `auditionSustain`) treat
            // every hold mode (identity / chance / harmonize / SPLIT / AVOID / OCTAVE / TRANSPOSE / CHORDS, incl. a bypassed-
            // driver identity tail like [CHORDS→bypassed ARP]) as immortal+adopted, so the preview RINGS instead of striking
            // once and gating off. The every-window reconcile below re-derives + adopts (tracks a late latch / a changing
            // note). On a SWEEPING row nothing here fires — holds re-strike per column boundary as before (byte-identical).
            let soloSustain = (forceColumnHold || auditionSustain) && (bm & altMask) == 0
            let legato = (bm & altMask) == 0 && ((mode == .identity && treat.a.phase == .legato) || mode == .drone || soloSustain)
            if reconcileOnly && !legato { continue }   // frozen-column re-run: only the immortal holds reconcile
            // STRIKE PER SPAN (Paul 2026-08-27, the span ladder's other half): a legato hold (v1: DRONE) fires ONCE at
            // each span origin and HOLDS (adopts) through the rest — the multi-column pad. Off the same span-ladder
            // re-anchor: at a span origin we DISABLE adoption below, so the old immortal stays a holdCandidate (closed at
            // the loop end, refcount-safe → NO wire off) while the fresh strike restrikes the same wire (openVoice off→on)
            // — a clean re-attack. Between origins we adopt (no re-strike). Key-up (empty pool) closes as usual. Skipped
            // under reconcileOnly (PLAY: THIS CELL freezes the column → would re-articulate every window). nil ⇒ off ⇒ today's drone.
            let spsSpanBeats = (legato && treat.a.strikePerSpan && !reconcileOnly)
                ? spanLadderBeats(treat.a.strikeSpanN, S: S, row: cycleBeats) : 0
            let spsReArticulate = spsSpanBeats > 0 && abs(colStart - columnStart(colStart, spsSpanBeats)) < 1e-9
            // §cell-edit F CHOP: a hold is ONE articulation (at colStart = slice 0), so route it by that slice's
            // chop — MAIN adds the cell's own emitters, ALT adds altDest, MUTE silences. `chopMask` returns `bm`
            // unchanged when the cell has no chop, so this is a no-op for ordinary holds. (Tick cells chop per-tick.)
            let hbm = chopMask(cell, m: colStart, S: S, base: bm)
            let cellPool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: frozen chord if armed
            // CHORDS reads its progression clock from the RAW beat (mNow), NOT the grid-quantized colStart — else the rate
            // step is sampled only at column boundaries and aliases to one degree (Paul 2026-09-01). Other holds keep colStart.
            let composeM = chordsHold ? mNow : colStart
            if holdChain { composeChainSet(cell: cell, pool: cellPool, upto: chordsHold ? tailIdx : tailIdx - 1, m: composeM, S: S, cycleBeats: cycleBeats) }   // CHORDS tail: include the stage so chainScratch holds the derived chord
            else if chordsHold { composeChainSet(cell: cell, pool: cellPool, upto: 0, m: composeM, S: S, cycleBeats: cycleBeats) }   // lone [CHORDS]: fold the single stage
            let srcN = readScratch ? chainScratch.srcCount(filter: 0, cableMask: 0b1111) : cellPool.srcCount(for: cell)   // §7 source filter (CHORDS reads the composed chord)
            // §2 POOL-STEP UNITS (standalone/hold): TRANSPOSE steps the note by pool DEGREES; HARMONIZE voices in degrees.
            // The pool mask = the SOURCE set's pitch classes (the scale/chord feeding the cell). procShift = the processor's
            // own shift (register offsets stay semitone). Mask computed once per hold (no render alloc).
            let poolTrans = mode == .transpose && treat.a.utilTransposeUnits == .pool
            let poolHarm = mode == .harmonize && treat.a.harmUnits == .pool
            let holdPoolMask: UInt16 = (poolTrans || poolHarm) ? (holdChain ? chainScratch.pitchClassMaskAll() : cellPool.pitchClassMaskAll()) : 0
            let procShift = holdShift(treatP, mode: mode), regShift = transpose - procShift
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
            let avoidHoldMask: UInt16 = mode == .avoid ? avoidRefMask(treatP, ownDoor: Int(cell.resolvedReceiver), ownBusMask: cell.busMask) : 0   // AVOID/LOCK (standalone / hold-tail): the reference set, once per hold
            // The FINAL emitted note for rank k (base + the register/pool shift) — also the survivor scan's input.
            let holdFinalNote: (Int) -> Int = { k in
                let b = holdChain ? Int(self.chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111)) : Int(cellPool.srcAscending(k, for: cell))
                return poolTrans ? poolStepMask(b, steps: procShift, pcMask: holdPoolMask) + regShift : b + transpose
            }
            let avoidSurvivorMask: UInt16 = (mode == .avoid && !treatP.avoidLock && treatP.avoidMove && avoidHoldMask != 0)
                ? avoidSurvivors(holdFinalNote, count: srcN, refMask: avoidHoldMask) : 0   // AVOID MOVE lands only on the input scale's surviving notes
            for k in 0..<srcN where !holdEchoMute {                  // ECHO MUTE: the dry is suppressed (echoes-only); tails still register below
                let base = readScratch ? Int(chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111)) : Int(cellPool.srcAscending(k, for: cell))
                var n = poolTrans ? poolStepMask(base, steps: procShift, pcMask: holdPoolMask) + regShift : base + transpose
                if mode == .avoid {                                   // AVOID/LOCK filter (standalone/hold-tail): drop (REMOVE) or remap (MOVE)
                    guard let f = avoidFilter(n, treatP, refMask: avoidHoldMask, survivorMask: avoidSurvivorMask) else { continue }
                    n = f
                }
                guard n >= 0 && n <= 127 else { continue }
                let vel0 = max(1, readScratch ? chainScratch.velocity(UInt8(base)) : cellPool.velocity(UInt8(base)))   // inherit the source velocity (user 2026-08-09)
                let vel = droneScale < 1.0 ? clampVel(Int((Double(vel0) * droneScale).rounded())) : vel0   // DRONE scales by GATE
                if mode == .chance && !chancePassesPool(beat: colStart, note: n, rank: k, count: srcN, probability: prob, tilt: treat.a.chanceTilt, constantDensity: treat.a.chanceDensity) { continue }   // POOL-AWARE chance (user 2026-08-11)
                if mode == .tutti && tuttiSolo >= 0 && k != tuttiSolo { continue }   // TUTTI SOLO step: only the PICK-chosen rank sounds
                if mode == .split && (k < splitWin.start || k >= splitWin.start + splitWin.len || Int(vel0) < treat.a.splitVel.floor || Int(vel0) > treat.a.splitVel.ceil) { continue }   // SPLIT: keep the subset + vel band
                if mode == .harmonize {
                    emitHarmony(base: n, machine: treat, baseVel: vel, row: r, storeArtics: false,
                                busMask: hbm, on: onSample, off: offSample, beat: colStart,
                                windowEnd: windowEnd, sustain: soloSustain, poolMask: poolHarm ? holdPoolMask : 0, out: out, diag: &diag)   // PLAY: THIS CELL — harmonize holds sustain + adopt too
                } else if legato {
                    // §2 per-bus reconcile: ADOPT the buses a matching drone already sounds (no off/on);
                    // STRIKE only the buses that are new — each opened IMMORTAL (offSample .max) so drainDue
                    // never truncates it and only the next boundary's reconcile can close it.
                    var emitMask: UInt8 = 0
                    for b in UInt8(0)..<4 where hbm & (1 << b) != 0 {
                        let sw = n + emitterOctaveShift(Int(b)) + masterKey  // the octave/key-shifted pitch…
                        guard sw >= 0 && sw <= 127 else { continue }         // out of range → emitOneBus would drop it
                        guard let w = fencedNote(UInt8(sw), bus: Int(b)) else { continue }  // …then FENCE — the exact wire pitch emitOneBus will open (DROP → no bus)
                        // STRIKE PER SPAN: at a span origin, skip adoption (|| short-circuits adoptLegatoBus away) so the
                        // old immortal is NOT un-marked — it closes at the loop end (refcount-safe) while the fresh strike re-attacks.
                        if spsReArticulate || !adoptLegatoBus(wire: w, bus: b, ci: Int16(ci), alt: altFlag) { emitMask |= (1 << b) }
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
            // TAP in a HOLD-tail chain (Paul 2026-08-26, [X→TAP] / [X→TAP→Y] with no tick driver): mirror each TAP slot's
            // INPUT set to its wire (LEVEL-scaled), once per column entry — the parallel send, matching the driver-path TAP
            // (emitDriverNote). THIS WIRE (0) layers on the cell's chopped output; A–D goes to that emitter; MUTE = no dry
            // effect (TAP is note-transparent, so the dry hold already played the passing stream).
            if !reconcileOnly, holdChain {
                for t in 0..<cell.procs.count where cell.procs[t].type == .tap && !cell.slotBypass[t] {
                    let tp = cell.procs[t]
                    if tp.tapMute { continue }
                    composeChainSet(cell: cell, pool: cellPool, upto: t - 1, m: colStart, S: S, cycleBeats: Double(Snap.cols) * S)
                    let tapBM: UInt8 = tp.tapTo == 0 ? hbm : (UInt8(1) << UInt8(max(0, min(3, tp.tapTo - 1))))
                    for k in 0..<chainScratch.srcCount(filter: 0, cableMask: 0b1111) {
                        let base = Int(chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111))
                        let tn = base + transpose; guard tn >= 0 && tn <= 127 else { continue }
                        let tv = clampVel(Int((Double(max(1, chainScratch.velocity(UInt8(base)))) * tp.tapLevel).rounded()))
                        emitArtic(note: UInt8(tn), busMask: tapBM, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: tv, out: out, diag: &diag)
                    }
                }
            }
            // ECHO in a HOLD-tail chain ([ECHO→HARMONIZE], [ECHO→SPLIT], …): register tails. DIRECT (default) repeats the
            // FULLY-PROCESSED final set (position-blind, v1 — without this the echo is dropped, composeChainSet folds it
            // as pass-through; user 2026-08-10 bug). CHAIN (§7②, Paul 2026-08-22) seeds from ECHO's INPUT set and
            // drainEchoTails re-folds each repeat through the stages AFTER the ECHO slot (so [ECHO→SPLIT] thins each repeat).
            if !reconcileOnly, holdChain, let ei = chainEchoIndex(cell) {
                let ep = cell.procs[ei]
                let chainRoute = ep.echoRoute == .chain && ei < tailIdx     // CHAIN only when a downstream stage exists
                composeChainSet(cell: cell, pool: cellPool, upto: chainRoute ? ei - 1 : tailIdx, m: colStart, S: S, cycleBeats: Double(Snap.cols) * S)
                for k in 0..<chainScratch.srcCount(filter: 0, cableMask: 0b1111) {
                    let base = Int(chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111))
                    let n = base + transpose; guard n >= 0 && n <= 127 else { continue }
                    pushEchoForNote(n, vel: max(1, chainScratch.velocity(UInt8(base))), bm: hbm, p: ep, onset: colStart, S: S, tempo: tempo,
                                    route: chainRoute ? .chain : .direct, cellIdx: chainRoute ? currentCellIndex : -1, echoSlot: chainRoute ? ei : -1)
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
                               windowEnd: Int64, out: MIDIEmitter?, onlyRow: Int? = nil, diag: inout KernelDiag) {
        guard pool.count > 0 || latchMask != 0 else { return }
        let colStart = columnStart(mNow, S)
        let onSample = sampleOf(musical: colStart, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                windowStart: windowStart, S: S, a: a)
        for r in 0..<Snap.rows where onlyRow == nil || onlyRow == r {
            let cell = box.cells[column * Snap.rows + r]
            if cell.machineIndex < 0 || cell.busMask == 0 || cell.muted || cell.dormant { continue }
            if soloSilenced(cell) { continue }
            let ci = Int(cell.machineIndex)
            let machine = box.machines[ci]
            if !onSceneAudible(machine.on, pass: pass) { continue }
            if isEchoTail(cell) {   // single-slot [ECHO] OR a hold-upstream chain tail (…→ECHO)
                let tailIdx = cell.procs.count - 1
                let p = cell.procs[tailIdx]                 // the ECHO slot's own controls (user 2026-08-08)
                registerEcho(p, cell: cell, machine: machine, ci: ci, column: column, r: r, pool: pool, tempo: tempo,
                             colStart: colStart, onSample: onSample, S: S, a: a, beatPos: beatPos,
                             beatsPerSample: beatsPerSample, windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
            } else if composableLengthTailIndex(cell) != nil, let ei = chainEchoIndex(cell) {
                // §7② [ECHO→…→LENGTH]: LENGTH re-articulates in the tick loop (emitLengthComposedRow), which SWALLOWS the
                // echo (composeChainSet folds it as passthrough) — so this is the ONLY place its tails register. Column
                // entry, once. DIRECT = echo the composed set flat; CHAIN = re-fold each repeat through LENGTH (choked/tied).
                registerLengthChainEcho(cell: cell, echoIdx: ei, machine: machine, ci: ci, column: column, r: r, pool: pool, tempo: tempo, beatsPerSample: beatsPerSample, colStart: colStart, S: S)
            }
        }
    }
    /// §7② Register the echo tails for a non-driver [ECHO→…→LENGTH] chain (LENGTH's re-articulator swallows the echo).
    /// Once per column entry (from emitEchoColumn). NO dry strike — the length-gated dry is emitted by emitLengthComposedRow
    /// (which suppresses it when the echo is MUTE). CHAIN re-folds each repeat through LENGTH at drain; DIRECT echoes flat.
    private func registerLengthChainEcho(cell: SnapCell, echoIdx ei: Int, machine: SnapMachine, ci: Int, column: Int, r: Int,
                                         pool: NotePool, tempo: Double, beatsPerSample: Double, colStart: Double, S: Double) {
        let ep = cell.procs[ei]
        var last = -1, i = cell.procs.count - 1
        while i >= 0 { if !cell.slotBypass[i] { last = i; break }; i -= 1 }
        let chainRoute = ep.echoRoute == .chain && ei < last
        // Compute the delay the SAME way registerEcho does — synced (div/16ths) OR free (ms→beats at tempo). pushEchoForNote
        // is synced-only, so pushing directly here is what keeps a FREE-delay MUTE echo audible (else dry-suppressed + no
        // tails = silence, the review's regression). (Paul 2026-08-23)
        let timeBeats = ep.echoSync ? Double(ep.echoDelayDiv) / 4.0 : max(0.001, ep.echoDelayMs / 1000.0 * tempo / 60.0)
        guard timeBeats > 0 else { return }
        let repeats = max(1, min(16, ep.echoRepeats))
        let gateBeats = min(timeBeats * 0.9, S * 0.9)
        let transpose = machineTranspose(ci, machine) + octaveShift(cell.resolvedReceiver)
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: 0)
        currentInputRecv = cell.resolvedReceiver; currentMachineIndex = cell.machineIndex; currentCellIndex = column * Snap.rows + r
        chanOverride = cellChanOverride(cell); nudgeSamples = cellNudgeSamples(cell, beatsPerSample: beatsPerSample, step: column)   // the tails inherit THIS cell's CHANNEL/NUDGE (captured by pushEchoTail)
        let cellPool = effectivePool(for: cell, live: pool)
        composeChainSet(cell: cell, pool: cellPool, upto: chainRoute ? ei - 1 : last, m: colStart, S: S, cycleBeats: Double(Snap.cols) * S)   // CHAIN = ECHO's INPUT · DIRECT = the composed set (LENGTH is passthrough in composeChainSet)
        let chopped = chopMask(cell, m: colStart, S: S, base: bm)
        for k in 0..<chainScratch.srcCount(filter: 0, cableMask: 0b1111) {
            let base = Int(chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111))
            let n = base + transpose; guard n >= 0 && n <= 127 else { continue }
            pushEchoTail(onset: colStart, note: UInt8(n), vel: max(1, chainScratch.velocity(UInt8(base))), busMask: chopped,
                         timeBeats: timeBeats, repeats: repeats, feedDelay: ep.echoFeedDelay, decay: ep.echoDecay,
                         offset: ep.echoOffset, pitch: ep.echoPitch, gateBeats: gateBeats, spill: ep.echoSpill,
                         route: chainRoute ? .chain : .direct, cellIdx: chainRoute ? currentCellIndex : -1, echoSlot: chainRoute ? ei : -1)
        }
    }
    /// Strike the DRY note (only when THRU) + register the echo tail for each source note of an echo-tail cell —
    /// shared by the single/hold-tail path (emitEchoColumn) and the tick-driven path ([ARP→ECHO], per driver tick).
    private func registerEcho(_ p: SnapParams, cell: SnapCell, machine: SnapMachine, ci: Int, column: Int, r: Int,
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
        let transpose = machineTranspose(ci, machine) + octaveShift(cell.resolvedReceiver)
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: 0)
        currentInputRecv = cell.resolvedReceiver; currentMachineIndex = cell.machineIndex
        currentCellIndex = column * Snap.rows + r
        chanOverride = cellChanOverride(cell); nudgeSamples = cellNudgeSamples(cell, beatsPerSample: beatsPerSample, step: column)   // the echo DRY uses THIS cell's UTILITY CHANNEL/NUDGE (not a stale neighbour's); tails reset to wire before drain (review 2026-08-23)
        // SOURCE: a hold-upstream chain echoes its upstream stages' composed set ([HARMONIZE→ECHO] the widened chord,
        // [HARMONIZE→ECHO] the harmonised set); a single [ECHO] echoes the cell's source directly.
        let cellPool = effectivePool(for: cell, live: pool)
        let multi = cell.procs.count >= 2
        if multi { composeChainSet(cell: cell, pool: cellPool, upto: cell.procs.count - 2, m: colStart, S: S, cycleBeats: Double(Snap.cols) * S) }
        let srcN = multi ? chainScratch.srcCount(filter: 0, cableMask: 0b1111) : cellPool.srcCount(for: cell)
        let echoInKey = p.echoPitchMode == .inKey
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
                         gateBeats: gateBeats, spill: p.echoSpill,
                         inKeyMode: echoInKey, inKeyReceivers: echoInKey ? p.echoInKeyReceivers : 0)
        }
    }

    // ECHO IN-KEY: union of the live pitch-classes of every SELECTED receiver (bit i = A..D) — mirrors avoidRefMask's
    // .sounding union (line ~207), but user-selected rather than "every other door."
    private func echoInKeyRefMask(_ mask: UInt8) -> UInt16 {
        var m: UInt16 = 0
        for d in 0..<4 where (mask >> UInt8(d)) & 1 != 0 { m |= doorRefMask(d) }
        return m
    }
    /// Emit every registered echo REPEAT whose musical time lands in this window [mStart, mEnd) — column-independent,
    /// so tails ring out after the playhead leaves the cell's column AND after the source chord releases. Each repeat
    /// opens a voice with a scheduled off (drainDue guarantees the off → no stuck note). Decay-floor + all-past retire
    /// the entry. A beat DISCONTINUITY (seek/loop/tempo jump) clears the ring — v1 drops tails on the jump (look-back
    /// preservation is v2). Runs BEFORE the empty-pool guard so a released chord's tail still sounds.
    private func drainEchoTails(box: SnapshotBox, mStart: Double, mEnd: Double, beatPos: Double, beatsPerSample: Double,
                               windowStart: Int64, windowEnd: Int64, S: Double, a: Double,
                               out: MIDIEmitter?, diag: inout KernelDiag) {
        if !echoPrevMEnd.isNaN && abs(mStart - echoPrevMEnd) > S { clearEchoTails() }   // seek/loop/tempo jump → drop tails
        echoPrevMEnd = mEnd
        for i in echoTails.indices where echoTails[i].active {
            let e = echoTails[i]
            chanOverride = Int16(e.chan); nudgeSamples = e.nudge   // repeats sound on the source cell's CHANNEL/NUDGE (captured at registration) — emitOneBus reads these
            currentCellIndex = e.cellIdx >= 0 ? e.cellIdx : -1   // E6 fix 2026-08-27: attribute the repeat to its SOURCE cell (was a stale value from the prior loop → mis-keyed close-except-legato / SEAL / note-sweep)
            // TAIL SPILL = CUT: once the playhead has crossed this tail's COLUMN boundary, stop scheduling repeats —
            // the last one already emitted keeps its scheduled off, so the sounding note finishes its gate (no lurch).
            if e.spill == .cut && mStart >= columnStart(e.onset, S) + S { echoTails[i].active = false; continue }
            if e.onset + (Double(e.repeats) + 1) * e.timeBeats < mStart { echoTails[i].active = false; continue }   // all past → retire
            // ECHO IN-KEY: the walk cursor is seeded ONCE per tail per drain call, then read/written as a LOCAL var
            // through the whole k-loop below — NOT through `e` (a value-type snapshot taken above, before this loop).
            // If two repeats fire in the SAME render window (fast rate + large frameCount), reading the cursor
            // through `e` would read the same stale value twice and break the chain; the local var lets k+1 see
            // k's actual landed note within one drain call, while the array write-back (below) is what lets the
            // NEXT render window's drain call continue from where this one left off.
            var inKeyWalk = e.inKeyLast >= 0 ? Int(e.inKeyLast) : Int(e.note)
            for k in 1...e.repeats {
                let tau = e.onset + (Double(k) + e.offset) * e.timeBeats     // OFFSET nudges each echo off the grid
                if tau < mStart || tau >= mEnd { continue }                 // half-open: fires in exactly one window
                // FEED DELAY = the first echo's send level · FEEDBACK = the per-echo decay ratio (tail length)
                let v = Int((Double(e.vel) * e.feedDelay * pow(e.decay, Double(k - 1))).rounded())
                if v < 1 { continue }                                       // level floor kills the tail
                let n: Int
                if e.inKeyMode {                                            // walk to the next in-key note, live, chained from the last landed pitch
                    let dir = e.pitch > 0 ? 1 : (e.pitch < 0 ? -1 : 0)
                    if let next = nextInKeyNote(inKeyWalk, refMask: echoInKeyRefMask(e.inKeyReceivers), dir: dir) { inKeyWalk = next }   // else: hold at the last landed note (empty mask / dir 0 / range exhausted)
                    n = inKeyWalk
                    echoTails[i].inKeyLast = Int8(clamping: inKeyWalk)       // persists for the NEXT render window's drain call
                } else {
                    n = Int(e.note) + k * e.pitch                           // PITCH: climb/descend each echo (flat semitones)
                }
                guard n >= 0 && n <= 127 else { continue }
                let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                   windowStart: windowStart, S: S, a: a)
                let offT = sampleOf(musical: tau + e.gateBeats, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                    windowStart: windowStart, S: S, a: a)
                // §7② ROUTE = CHAIN: re-fold THIS repeat through the post-ECHO stages at beat tau (LENGTH gates/ties it,
                // SPLIT thins by register/velocity, HARMONIZE dresses it, …). DIRECT → the flat v1 strike (byte-identical).
                if e.route == .chain && e.cellIdx >= 0 {
                    refoldEchoRepeat(e, n: n, v: min(127, v), tau: tau, S: S, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                     windowStart: windowStart, windowEnd: windowEnd, a: a, box: box, out: out, diag: &diag)
                } else {
                    emitArtic(note: UInt8(n), busMask: e.busMask, onSample: onT, offSample: offT,
                              windowEnd: windowEnd, velocity: UInt8(min(127, v)), out: out, diag: &diag)
                }
            }
        }
        chanOverride = -1; nudgeSamples = 0; currentCellIndex = -1   // clear the per-tail override so the MOD/GLIDE block + tick loop start clean
    }
    /// §7② Emit ONE echo repeat (note `n`, vel `v`, beat `tau`) through the chain stages AFTER the ECHO slot, looked up
    /// on the LIVE cell — LENGTH gates/ties it by the slice it lands in, SPLIT/CHANCE/HARMONIZE re-shape it, etc. Falls
    /// back to a flat strike if the live chain changed (the ECHO slot is gone / no longer ECHO) or has no downstream
    /// stages. Uses the chainA/chainB scratch (free here — drainEchoTails runs before the tick loop that also uses them).
    private func refoldEchoRepeat(_ e: EchoTail, n: Int, v: Int, tau: Double, S: Double, beatPos: Double,
                                  beatsPerSample: Double, windowStart: Int64, windowEnd: Int64, a: Double,
                                  box: SnapshotBox, out: MIDIEmitter?, diag: inout KernelDiag) {
        let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        func flat() {
            let offT = sampleOf(musical: tau + e.gateBeats, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            emitArtic(note: UInt8(n), busMask: e.busMask, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: UInt8(min(127, max(1, v))), out: out, diag: &diag)
        }
        guard e.cellIdx >= 0 && e.cellIdx < box.cells.count else { flat(); return }
        let cell = box.cells[e.cellIdx]
        guard e.echoSlot >= 0 && e.echoSlot < cell.procs.count, cell.procs[e.echoSlot].type == .echo else { flat(); return }
        let cycleBeats = Double(Snap.cols) * S
        let pass = cycleBeats > 0 ? Int((tau / cycleBeats).rounded(.down)) : 0   // the lap the repeat lands in (for chance seeds)
        var cur = chainA, nxt = chainB
        cur.reset(); cur.noteOn(UInt8(min(127, max(0, n))), velocity: UInt8(min(127, max(1, v))), channel: 0); cur.rebuildSorted()
        var lenP: SnapParams? = nil
        var j = e.echoSlot + 1
        while j < cell.procs.count {
            if !cell.slotBypass[j] {
                let t = cell.procs[j].type
                if t == .echo || t == .mod || t == .glide {         // no nested echo (v1); MOD/GLIDE are note-transparent
                } else if t == .length {
                    lenP = cell.procs[j]                            // gate override applied to the emit below (last-writer)
                } else {
                    let mode = cellMode(type: t, bypassed: false)
                    nxt.reset()
                    applyStage(cell.procs[j], mode: mode, src: cur, into: nxt, cell: cell, m: tau, S: S, cycleBeats: cycleBeats)
                    swap(&cur, &nxt)
                }
            }
            j += 1
        }
        var offBeat = tau + e.gateBeats
        if let lp = lenP {                                          // LENGTH downstream: gate THIS repeat by the slice at tau
            // Match the DRY's gate width: a NON-DRIVER [ECHO→LENGTH] dry (emitLengthComposedRow) honors SPAN=ROW (the 8
            // slices span the whole bar); the driver-fold dry (emitDriverNote) is per-column. Use the same so the repeats
            // gate on the SAME pattern the dry does (else dry+echoes diverge for SPAN=ROW — the review's finding).
            let lenColBeats = (chainDriverIndex(cell) < 0) ? spanLadderBeats(lp.lenSpanN, S: S, row: cycleBeats) : S   // SPAN LADDER (Paul 2026-08-22)
            let sIdx = ((chopSlice(tau, columnBeats: lenColBeats) + lp.lenRotate) % 8 + 8) % 8
            let st = sIdx < lp.lenSlices.count ? lp.lenSlices[sIdx] : .pass
            switch lengthGateFor(st, onset: tau, shortFrac: lp.lenShort, longFrac: lp.lenLong, S: lenColBeats) {
            case .drop:                return                       // MUTE slice → this repeat is silent
            case .keep:                break
            case .overrideOff(let ob): offBeat = ob
            }
        }
        let offT = sampleOf(musical: offBeat, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        for k in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) {
            let nn = cur.srcAscending(k, filter: 0, cableMask: 0b1111)
            emitArtic(note: nn, busMask: e.busMask, onSample: onT, offSample: offT, windowEnd: windowEnd,
                      velocity: max(1, cur.velocity(nn)), out: out, diag: &diag)
        }
    }

    /// The shared subdivision-tick scaffold for ARP and RATCHET. Walks every tick of length `sub`
    /// in this window that belongs to `effColumn`, dedups per row, and hands the body the tick's
    /// index, musical beat, and unwarped on/off sample times. `gateFraction` sets the note length
    /// as a fraction of `sub` (truncated at the column boundary). The body decides WHAT to emit;
    /// this owns the timing — so the boundary/dedup logic lives in exactly one place.
    /// Return from the body to skip a tick (the equivalent of `continue`).
    ///
    /// CLOCK driver retiming (Paul 2026-09-26, final spec — DRAWN mode's grid: "a variable number of steps, each
    /// step a mutually exclusive speed, and another row on the same grid for glide"): `clockCell`/`clockFrom`/
    /// `clockTo`/`cycleBeats` are defaulted — every caller that omits them, and every call where `clockTo <=
    /// clockFrom` (no driver, or no CLOCK stage upstream of it), takes the exact code path this function always
    /// has; byte-identical. When present, the tick SEARCH runs in the CLOCK-transformed LOCAL beat space (so the
    /// driver's rhythm genuinely speeds up/slows down/glides per the authored lane), but the column-membership
    /// gate and all sample scheduling still key off the REAL beat each local tick maps back to — columns are
    /// upstream of CLOCK, untouched (the sovereign law) — so a candidate is inverted back to real time immediately
    /// on discovery, before anything else reads it. Only the LOCAL `mTickBeat` handed to `body()` stays local,
    /// since note-SELECTION (`phaseIndex`→`arpPick`) is correctly a function of the driver's own local rhythm,
    /// never of real time.
    private func iterateTicks(row: Int, effColumn: Int, sub: Double, gateFraction: Double,
                              beatPos: Double, windowBeats: Double, windowStart: Int64,
                              beatsPerSample: Double, S: Double, a: Double, columns: Int = Snap.cols,
                              clockCell: SnapCell? = nil, clockFrom: Int = 0, clockTo: Int = 0, cycleBeats: Double = 0,
                              lineIndex: Int = 0,   // which of this row's up-to-tickDedupSlotsPerRow lines this call is (EUCLID only; every other caller keeps the default, landing on slot 0 — byte-identical to the old single-scalar-per-row dedup)
                              _ body: (_ tick: Int64, _ mTickBeat: Double,
                                       _ onTime: Int64, _ offTime: Int64) -> Void) {
        let dedupSlot = row * Router.tickDedupSlotsPerRow + min(max(0, lineIndex), Router.tickDedupSlotsPerRow - 1)
        let hasClock = clockCell != nil && clockTo > clockFrom
        let mStartReal = musicalOf(beatPos, stepBeats: S, a: a)
        let mEndReal = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        // `originRef: mStartReal` throughout this call — a single stable span-anchor reference for the whole
        // window, so every tick discovered below agrees on the same origin regardless of how many are found.
        let mStart = hasClock ? driverClockBeat(clockCell!, from: clockFrom, to: clockTo, atBeat: mStartReal, S: S, cycleBeats: cycleBeats, originRef: mStartReal) : mStartReal
        let mEnd = hasClock ? driverClockBeat(clockCell!, from: clockFrom, to: clockTo, atBeat: mEndReal, S: S, cycleBeats: cycleBeats, originRef: mStartReal) : mEndReal
        // floor, not ceil: a tick AT a column boundary sits between render windows — the previous
        // column's window rejects it (wrong column) and ceil would round past it, dropping the
        // column's first note. floor + the == dedup catches it once (fired slightly late, clamped).
        let firstTick = Int64((mStart / sub).rounded(.down))
        let lastT = Int64((mEnd / sub).rounded(.down))
        guard firstTick <= lastT else { return }

        for tick in firstTick...lastT {
            let mTickBeat = Double(tick) * sub   // LOCAL beat — feeds body() for note-selection only, never scheduling
            let mTickBeatReal = hasClock ? driverClockBeatInverse(clockCell!, from: clockFrom, to: clockTo, atLocalBeat: mTickBeat, S: S, cycleBeats: cycleBeats, originRef: mStartReal) : mTickBeat
            // Which column is EFFECTIVE at this tick's step (lap-aware, §5b) — REAL time, since columns stay
            // upstream of CLOCK — so a held column's ticks fire during the current window even though the tick's
            // TRUE column differs. With no lap, lapColumn returns the tick's true column and this is the original
            // `tickCol == effColumn`.
            let tickStep = Int((mTickBeatReal / S).rounded(.down))
            let tickTrueCol = ((tickStep % columns) + columns) % columns   // wrap over the ROW's loop length (Lr < 8 → the short loop re-fires each pass)
            // PLAY: THIS CELL holds one column → its ticks fire EVERY window (decoupled from the timeline); normally
            // a tick fires only in its own effective column.
            if !forceColumnHold && lapColumn(laneMask: rowHeld[row], absoluteStep: tickStep, trueColumn: tickTrueCol) != effColumn { continue }   // PER-ROW LAP
            if tick == lastTick[dedupSlot] { continue }
            lastTick[dedupSlot] = tick

            let onTime = sampleOf(musical: mTickBeatReal, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                  windowStart: windowStart, S: S, a: a)
            // The GATE LENGTH is a LOCAL-time quantity (sub·gateFraction, the driver's own rhythm) but the clamp
            // that stops a note ringing past its column is a REAL-time boundary (columns stay upstream of CLOCK) —
            // so the local off-beat is computed, inverted back to real time, THEN clamped to the real column end.
            let colEnd = columnStart(mTickBeatReal, S) + S
            let mOffLocal = mTickBeat + sub * gateFraction
            let mOffReal = hasClock ? driverClockBeatInverse(clockCell!, from: clockFrom, to: clockTo, atLocalBeat: mOffLocal, S: S, cycleBeats: cycleBeats, originRef: mStartReal) : mOffLocal
            let mOff = min(mOffReal, colEnd)
            let offTime = sampleOf(musical: mOff, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                   windowStart: windowStart, S: S, a: a)
            body(tick, mTickBeat, onTime, offTime)
        }
    }

    // MARK: - the render-side pass

    // COLUMN TRANSITION (§7) — extracted so the uniform fast-path AND the per-row multi-clock path share it VERBATIM
    // (Paul 2026-08-21 housekeeping; byte-identical to the two inline blocks it replaced). `onlyRow` nil = the whole
    // grid on the global clock (uniform); r = just that row on its own clock (multi). `prevEdge` is the caller's edge
    // tracker (`prevEffColumn` / `prevEffColumnRow[r]`); the NEW edge is returned. On a transition: truncate the row's
    // voices at the boundary (legato drones survive), reset its tick state, then emit the new column's HELD + ECHO
    // content once. `forceColumnHold` re-runs the holds every window (SUSTAIN); a single-column lap with an empty pool
    // reconciles orphaned drones. The edge trackers are read ONLY here, so assigning `prevEdge` after the emits (vs the
    // old before) is behaviour-identical.
    @inline(__always)
    private func emitColumnTransition(box: SnapshotBox, effCol: Int, prevEdge: Int, onlyRow: Int?,
                                      S: Double, a: Double, mNow: Double, pass: Int, tempo: Double,
                                      beatPos: Double, beatsPerSample: Double, windowStart: Int64, windowEnd: Int64,
                                      cycleBeats: Double,   // the row's real pass length — see emitColumnHolds's own doc comment
                                      heldActive: Bool, pinned: Bool = false, pool: NotePool, out: MIDIEmitter?, diag: inout KernelDiag) -> Int {
        let savedPass = diag.pass
        diag.pass = pass
        defer { diag.pass = savedPass }
        if effCol != prevEdge {
            if (onlyRow == nil ? anyVoiceActive() : anyVoiceActiveInRow(onlyRow!)) {
                let boundaryMusical = columnStart(mNow, S)                  // start of effCol
                let realB = realOf(boundaryMusical, stepBeats: S, a: a)
                let off = max(0, (realB - beatPos) / beatsPerSample)
                closeExceptLegatoHolds(atSample: windowStart + Int64(off), out: out, onlyRow: onlyRow)
            }
            if let rr = onlyRow { resetTickDedup(row: rr); strumProgress[rr] = 0; lastGenStep[rr] = Int64.min }
            else { resetAllTickDedup(); for r in strumProgress.indices { strumProgress[r] = 0; lastGenStep[r] = Int64.min } }
            emitColumnHolds(box: box, column: effCol, pool: pool, pass: pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, tempo: tempo, out: out, cycleBeats: cycleBeats, auditionSustain: pinned, onlyRow: onlyRow, diag: &diag)   // pinned → strike immortal so the preview rings
            emitEchoColumn(box: box, column: effCol, pool: pool, pass: pass,   // ECHO: strike the dry + register the tail
                           S: S, a: a, tempo: tempo, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                           windowStart: windowStart, windowEnd: windowEnd, out: out, onlyRow: onlyRow, diag: &diag)
            return effCol
        } else if forceColumnHold || pinned {
            // PLAY: THIS CELL (forceColumnHold) OR a PINNED continuous row (the SELECT/PLAY audition, a single-column
            // loop that never re-transitions) — re-run the holds every window to SUSTAIN the legato ones (adopt when
            // unchanged, re-strike when the derived set CHANGES). This is what makes a legato CHORDS follow a late-armed
            // latch / a changing FOLLOW note on the audition instead of striking once and gating off (Paul 2026-09-01).
            emitColumnHolds(box: box, column: effCol, pool: pool, pass: pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, tempo: tempo, out: out, cycleBeats: cycleBeats, reconcileOnly: true, auditionSustain: pinned, onlyRow: onlyRow, diag: &diag)
        } else if heldActive && pool.count == 0 && latchMask == 0 && anyLegatoHold() {
            // AUDIT B2: a single-column lap pins the column so no edge fires — reconcile now to close orphaned drones.
            emitColumnHolds(box: box, column: effCol, pool: pool, pass: pass,
                            S: S, a: a, mNow: mNow, beatPos: beatPos, beatsPerSample: beatsPerSample,
                            windowStart: windowStart, windowEnd: windowEnd, tempo: tempo, out: out, cycleBeats: cycleBeats, onlyRow: onlyRow, diag: &diag)
        }
        return prevEdge
    }

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
                 laneMask: UInt16 = 0,
                 velOverride: UInt32 = 0,
                 heldCell: Int = -1,
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
                 preview: (active: Bool, machineIndex: Int, filter: Int, busMask: UInt8, inputRow: Int) = (false, -1, 0, 0, -1),
                 focusCell: Int = -1,     // FOCUS: the cell whose per-note flow the machine shows (records the focus note-event feed) — ephemeral, not in the snapshot
                 out: MIDIEmitter?,
                 diag: inout KernelDiag) {
        if pendingReset { pendingReset = false; performReset() }   // deferred reset — runs on the render thread (no race with the control-thread reset())
        tickRamps(atSample: Int64(timestampSample))   // §7: advance any in-flight .parameterRamp before this window's over() reads
        self.soloEmitterMask = soloEmitterMask     // emitter strip: additive foot SOLO set (bits A–D)
        self.soloReceiverMask = soloReceiverMask   // receiver strip: additive input SOLO set (bits R1–R4)
        self.inputOctave = inputOctave             // receiver strip: per-receiver ±octave nudge
        self.inputSemitone = inputSemitone         // receiver strip: per-receiver ±semitone NOTE nudge
        self.inputVelOverride = inputVelOverride   // receiver strip: per-receiver input-velocity override
        self.emitterOctave = emitterOctave         // emitter strip: per-emitter output ±octave nudge
        self.masterVelOverride = masterVelOverride // master panel: the momentary master fader
        currentInputRecv = -1                      // set per-cell in the playing loops; −1 for preview/audition
        currentMachineIndex = -1
        currentAlt = false
        self.latchMask = latchMask                 // receiver strip: which receivers read a frozen LATCH pool
        self.latchedPools = latchedPools
        self.receiverDisabledMask = box.receiverDisabledMask   // INPUT ENABLE: disabled doors block their cells' live read
        self.receiverChannels = box.receiverChannels; self.receiverCables = box.receiverCables   // BYPASS: per-receiver admission for the direct-injection pass
        self.receiverRangeLo = box.receiverRangeLo; self.receiverRangeHi = box.receiverRangeHi
        self.receiverScaleRoot = box.receiverScaleRoot; self.receiverScaleType = box.receiverScaleType   // CHORDS C2b#1: a SCALE door declares the key
        self.avoidLivePool = pool   // AVOID: a DOOR-referenced filter reads another receiver's LIVE notes this render (valid only during process)
        self.passEmitterMask = box.passEmitterMask

        busChannels = box.busChannels               // delta §7: per-bus stamp channels, this render
        busRemap = box.busRemap                      // ROW 8 REDIRECT/SWAP: per-bus output remap, this render
        broadcastActive = box.broadcastActive        // ROW 8 BROADCAST: mirror to all wires, this render
        broadcastAll16 = box.broadcastAll16          // ROW 8 BROADCAST: + all 16 channels on the ALL cable
        curBox = box                                // for the reel's machine-by-cell note tag (openVoice reads the sounding machine's hue)
        heldColumns = laneMask                      // §5b lap: held column keys, this render
        // PER-ROW LAP (Paul 2026-08-19): the scene may set a per-row loop mask (BUILD's two grids loop independently);
        // else every row shares the global ephemeral lap (GRID tab = today). When set, the render goes down the per-row
        // path (rows may lap different columns), and each row reads rowHeld[r].
        let perRowLap = box.rowLaneMask.count == Snap.rows
        for r in 0..<Snap.rows { rowHeld[r] = perRowLap ? box.rowLaneMask[r] : laneMask }
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
        // R1 (2026-08-30): master MUTE folds into the effective enabled mask exactly like master-KILL (line above), so
        // the enabled→disabled EDGE below CLOSES sustained content (legato drones, glide anchors). Was: MUTE only
        // suppressed NEW emission via the per-path guards, so a sustained note's on was never paired with an off — it
        // rang on through the mute (an invariant-4 violation; masterKill flushed but plain MUTE didn't). The per-path
        // `masterMute` guards stay (belt-and-suspenders); recoverable — an unmute re-strikes held content next boundary.
        if masterMute && !previewMode { busEnabledMask = 0 }

        // ---- window in samples; global (non-cell) timing ----
        let windowStart = Int64(timestampSample)
        renderStart = windowStart                   // POCKET: the earliest sample a pushed note may land on
        let windowEnd = windowStart + Int64(frameCount)

        // delta §6a: an emitter that just went enabled→disabled closes its sounding notes IMMEDIATELY
        // (own cable + its All copy; a shared-channel note survives on All via another enabled owner).
        if busEnabledMask != prevBusEnabledMask {
            let turnedOff = prevBusEnabledMask & ~busEnabledMask
            for bus: UInt8 in 0..<4 where turnedOff & (1 << bus) != 0 { closeBus(bus, atSample: windowStart, out: out) }
            // GLIDE (review 2026-08-23 [4]): closeBus closed any immortal glide ANCHOR on a disabled bus — forget its stale
            // bookkeeping (else the freed voice slot is later reused and wrongly closed → a spurious off on an unrelated note,
            // and the glide goes silent). Targeted to the disabled buses so glides on still-live emitters survive.
            for i in glideVoices.indices where glideVoices[i].bus >= 0 && (turnedOff & (1 << UInt8(glideVoices[i].bus))) != 0 {
                resetGlideControllers(glideVoices[i], atSample: windowStart, out: out)   // E5 fix 2026-08-27: re-centre bend / clear CC65 on the disabled bus (was blanked without a controller reset)
                glideVoices[i] = GlideVoice()
            }
            prevBusEnabledMask = busEnabledMask
        }
        let beatsPerSample = tempo / 60.0 / sampleRate
        focusCellIdx = focusCell                              // FOCUS note-event feed: this render's target cell + beat conversion
        fBeatPos = beatPos; fBeatsPerSample = beatsPerSample; fWindowStart = windowStart
        let swing = min(75, max(50, over(1, box.swing)))
        let a = swing / 50.0
        var S = box.stepBeats
        let srIdx = Int(over(0, -1).rounded())
        if srIdx >= 0 && srIdx < Snap.stepRateBeats.count { S = Snap.stepRateBeats[srIdx] }
        // ROW 8 HALFTIME (Paul 2026-08-22): a lit HALFTIME cell scales the whole play-grid COLUMN clock (÷2 ⇒ 2.0 = steps
        // twice as long · ×2 ⇒ 0.5). Applied to S here + the per-row steps below (uniformClock compares like-scaled).
        // v1: a raw scale — the column phase re-references at the toggle (the transition machinery re-strikes cleanly, no
        // stuck notes); a phase-anchored boundary-deferred "never-lurch" drop is a flagged follow-up. 1.0 ⇒ byte-identical.
        let clockScale = box.clockScale
        S *= clockScale
        diag.effSwing = swing

        // ROW 8 FREEZE (Paul 2026-08-22): while a lit FREEZE cell holds, sounding notes SUSTAIN (offs held) and derivation
        // PAUSES (no new notes). So while frozen we skip drainDue (the scheduled note-offs stay pending) + the whole
        // emission + the bypass monitor — but the transport/panic/scene/latch flush edges STILL run below (a stop or panic
        // must always release, never strand a note). The freeze→unfreeze EDGE releases the held notes + resets the phases.
        let frozen = box.freezeActive

        // ---- drain scheduled gate-offs that have come due (survive across renders → no stuck note
        //      when a voice's off falls beyond its opening window). Runs regardless of transport. ----
        if !frozen { drainDue(windowStart: windowStart, windowEnd: windowEnd, out: out) }
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding
        diag.floodDropped = floodDropped              // FLOOD GOVERNOR: surface the session drop total to HEALTH

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            resetAllTickDedup(); for r in strumProgress.indices { strumProgress[r] = 0; lastGenStep[r] = Int64.min }
            prevEffColumn = -1
            altLastOnset = .min; altMomentIndex = -1     // role family ALT/TURNS: a fresh play restarts the rotation at the first member
            for i in dealMoment.indices { dealMoment[i] = -1; dealNoteInMoment[i] = 0; dealLastOnset[i] = .min; dealGlobal[i] = 0 }   // DEAL: a fresh play restarts the deal (Paul 2026-09-16)
            for i in riffDrunkPos.indices { riffDrunkPos[i] = -1; riffDrunkPrevPos[i] = -1; riffDrunkLastTick[i] = .min }   // RIFF DRUNK: a fresh play restarts the walk (Paul 2026-09-28)
            for i in euclideousRiffDrunkPos.indices { euclideousRiffDrunkPos[i] = -1; euclideousRiffDrunkLastOrd[i] = .min; euclideousRiffStep[i] = -1; euclideousRiffLastSpanStart[i] = .nan }   // EUCLIDEOUS RIFF: a fresh play restarts every lane's walk/cursor (Paul 2026-10-06) + re-arms span-reset detection (2026-10-08)
            for i in 0..<4 { nvHead[i] = 0; nvNew[i] = 0 }   // NOTE VIEW: a fresh play/stop clears any stale queued events, not just future ones (Paul 2026-10-10)
            passAnchor = 0                               // MULTI-SCENE S2b: a fresh play is absolute (no restart offset)
            wasPlaying = playing
            clearEchoTails()                             // ECHO: transport start/stop kills tails (spec v1)
            resetRecorderCapture(full: false)            // RECORDER: keep the committed loop across a stop→start; discard any partial capture
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide(atSample: renderSampleImmediate, out: out)   // MOD: reset the CC on transport edges
        }
        // master panel PANIC: the one hard flush — close every voice + reset the column state, hang-kit-logged.
        if panic {
            allNotesOff(atSample: renderSampleImmediate, out: out, includeBypass: true)   // the one hard flush — bypass included
            panicControllers(atSample: renderSampleImmediate, out: out)   // §3: CC120 + CC123 on every channel/cable
            prevEffColumn = -1
            diag.panics &+= 1
            clearEchoTails()                             // ECHO: panic drops every pending tail
            resetRecorderCapture(full: true)             // RECORDER: panic clears the loops too
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide(atSample: renderSampleImmediate, out: out)   // MOD: reset the CC on panic
        }
        // MULTI-SCENE scene SWITCH flush: close the OLD scene's sounding notes so the new scene (this render's
        // new snapshot generation) starts clean — a generation change alone doesn't flush. NOT hang-logged.
        if sceneFlush {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevEffColumn = -1
            clearEchoTails()                             // ECHO: scene-mortal — the old scene's tails die
            resetRecorderCapture(full: true)             // RECORDER: the old scene's loops die on the switch
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide(atSample: renderSampleImmediate, out: out)   // MOD: the old scene's CC state resets on the switch
        }
        // receiver strip LATCH edge: arming/disarming a receiver swaps the pool its subscribers read, so
        // close every voice and re-emit holds from the new effective pool (no stuck notes; on-edge re-strike).
        if latchMask != prevLatchMask {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevEffColumn = -1
            prevLatchMask = latchMask
            clearEchoTails()                             // ECHO: the pool swapped — drop tails from the old chord
            resetRecorderCapture(full: false)            // RECORDER: keep the loop across a latch edge; discard partial capture
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide(atSample: renderSampleImmediate, out: out)   // parity with the other edges: allNotesOff closed the immortal GLIDE anchors — forget the stale voice bookkeeping (else silent glide + a freed slot reused then wrongly closed). (review 2026-08-23)
        }

        pool.rebuildSorted()
        diag.poolCount = pool.count
        chanOverride = -1; nudgeSamples = 0   // UTILITY: clean slate each render — preview/audition/bypass + the echo dry must NOT inherit a stale per-cell override from the previous render/cell; the tick/hold loops set them per-cell (review 2026-08-23)

        // ROW 8 FREEZE edge + gate. The freeze→UNFREEZE edge releases the sustained notes (incl. the bypass wire) and
        // resets the column/tick phases so derivation resumes clean at the boundary. While FROZEN, return here — the
        // sounding notes sustain (drainDue was skipped above) and NOTHING new emits (bypass + the whole grid are paused).
        if frozen != prevFreezeActive {
            if !frozen {                                  // unfreeze: release + resume
                allNotesOff(atSample: renderSampleImmediate, out: out, includeBypass: true)
                prevEffColumn = -1
                resetAllTickDedup(); for r in strumProgress.indices { strumProgress[r] = 0; lastGenStep[r] = Int64.min }
                for i in prevEffColumnRow.indices { prevEffColumnRow[i] = -1 }
                clearEchoTails()
                resetRecorderCapture(full: false)             // RECORDER: unfreeze keeps the loop
                flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide(atSample: renderSampleImmediate, out: out)
            }
            prevFreezeActive = frozen
        }
        if frozen {
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding
            return   // sustain (offs held) + emit nothing (derivation paused)
        }

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
            resetAllTickDedup(); for i in lastGenStep.indices { lastGenStep[i] = Int64.min }      // free the solo row's tick-dedup
            previewPrevColumn = -1; strumProgress[0] = 0        // fresh column edge for the virtual cell
            clearEchoTails()                                    // parity with the other flush edges
            resetRecorderCapture(full: false)             // RECORDER: a uniform↔multi clock switch keeps the loop
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide(atSample: renderSampleImmediate, out: out)   // review 2026-08-23 [4]: allNotesOff closed the immortal MOD/GLIDE anchors — forget their stale bookkeeping (else a reused slot later emits a spurious off + the glide/CC goes silent)
            prevPreviewActive = preview.active
        }

        // ---- AUDITION / stopped-PREVIEW (transport stopped) ----
        if !playing {
            if preview.active {
                previewStopped(machineIndex: preview.machineIndex, filter: preview.filter, busMask: preview.busMask,
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
            resetAllTickDedup(); for r in strumProgress.indices { strumProgress[r] = 0; lastGenStep[r] = Int64.min }
            clearEchoTails()                             // ECHO: a pass restart drops the old pass's tails
            resetRecorderCapture(full: false)             // RECORDER: a pass restart keeps the loop (it IS the loop)
            flushMod(box: box, atSample: renderSampleImmediate, out: out); flushGlide(atSample: renderSampleImmediate, out: out)   // parity: allNotesOff closed the immortal MOD/GLIDE voices — forget their stale bookkeeping (review 2026-08-23)
        }
        let beatPos = beatPos - passAnchor

        // ---- derived column (§7). Musical space, so swing warps the beat→column map consistently
        //      with the arp ticks below. The COLUMN-SUBSET LAP (§5b) warps WHICH column is effective
        //      (held keys); the TRUE timeline — pass, swing — is unwarped (all off mNow). ----
        let mNow = musicalOf(beatPos, stepBeats: S, a: a)
        let govBeat = Int(beatPos.rounded(.down))                  // FLOOD GOVERNOR: reset the per-emitter budget each beat
        if govBeat != lastGovBeat { lastGovBeat = govBeat; for i in 0..<4 { noteOnsThisBeat[i] = 0 } }
        let cycleBeats = Double(Snap.cols) * S
        let posInCycle = mNow - (mNow / cycleBeats).rounded(.down) * cycleBeats
        let trueColumn = min(Snap.cols - 1, max(0, Int(posInCycle / S)))
        let absoluteStep = Int((mNow / S).rounded(.down))          // global step counter (derived)
        var effColumn = lapColumn(laneMask: heldColumns, absoluteStep: absoluteStep, trueColumn: trueColumn)
        forceColumnHold = forceColumn >= 0 && forceColumn < Snap.maxCols
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
            previewPlaying(machineIndex: preview.machineIndex, filter: preview.filter, busMask: preview.busMask,
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

        // PER-PART CLOCK (Paul 2026-08-19): uniform ⇒ every row runs the scene-default step and a full 8-wide loop
        // (today's sound, byte-identical FAST PATH). Non-uniform ⇒ each row has its own step rate/loop length, so its
        // column edge + hold reconcile + ticks all derive on that row's OWN clock (the multi-clock path below).
        let uniformClock = box.rowStep.allSatisfy { $0 * clockScale == S } && box.rowLength.allSatisfy { $0 == Snap.cols }   // HALFTIME scales S + each rowStep alike, so a uniform doc stays on the fast path
        let anyLaunchAnchor = box.rowLaunchAnchor.contains { $0 != 0 }   // PLAY-FERRY LAUNCH: an anchored ferry needs the per-row clock (its own phase offset), so it can't ride the uniform fast path
        let uniformFast = uniformClock && !perRowLap && !anyLaunchAnchor   // a per-row lap (BUILD's two grids) or a launch anchor forces the per-row path too

        // CLOCK-MODE SWITCH stuck-note fix (Paul 2026-09-01 bug-hunt): a LIVE uniform↔multi flip (a per-part-rate edit,
        // or entering/leaving a per-row lap) moves glide/mod's per-row tracker slot (onlyRow r ↔ nil → glideLastColumn/
        // modLastColumn), orphaning an IMMORTAL glide anchor / a mod-reset leave-disposition at its OLD column → the glide
        // never phrase-ends (a stuck drone) / the CC hangs. The per-row reconcile below (prevEffColumnRow re-seed) keeps
        // HOLDS seamless across the switch; glide/mod need their own close. So on a genuine mode CHANGE (not a flush edge —
        // those already flushed + returned), phrase-END every glide voice (emits its note-off) + send the mod leave-resets
        // + clear the glide trackers, so both re-establish cleanly on the new clock this same window. Covers BOTH directions
        // (the line-2440 prevEffColumnRow re-seed only handles uniform→multi).
        if prevEffColumn != -1 && uniformFast != prevUniformFast {
            for i in 0..<Snap.cells { glidePhraseEnd(i, atSample: windowStart, out: out) }
            flushMod(box: box, atSample: windowStart, out: out)
            for i in glideLastColumn.indices { glideLastColumn[i] = -1 }
        }
        // ---- column transition (§7): active column changed → truncate all voices at the boundary
        //      (truncate-at-boundary tails), then emit the new column's HELD content once. A
        //      relocation/loop is the same edge, no special case. ----
        if uniformFast {
            prevEffColumn = emitColumnTransition(box: box, effCol: effColumn, prevEdge: prevEffColumn, onlyRow: nil,
                                                 S: S, a: a, mNow: mNow, pass: diag.pass, tempo: tempo,
                                                 beatPos: beatPos, beatsPerSample: beatsPerSample,
                                                 windowStart: windowStart, windowEnd: windowEnd, cycleBeats: cycleBeats,
                                                 heldActive: heldColumns != 0, pool: pool, out: out, diag: &diag)
        } else {
            // ===== MULTI-CLOCK PATH — each row on its own step rate; each transition on that row's OWN clock =====
            let globalPass = diag.pass
            if prevEffColumn == -1 || prevUniformFast { for i in prevEffColumnRow.indices { prevEffColumnRow[i] = -1 } }   // a flush edge, OR a live uniform→multi switch (CR-11), re-seeds the per-row trackers so each row reconciles this window
            for r in 0..<Snap.rows {
                // PLAY-FERRY LAUNCH (Paul 2026-09-09): a non-zero anchor phase-shifts the row so it plays FROM COLUMN 0 at
                // the launch beat. Anchor 0 ⇒ SYNC/non-ferry (byte-identical, transport-locked). If the (quantized) start
                // hasn't been reached yet (anchor > beat), the row is ARMED but silent this window (rowEffColBuf = -1 → the
                // downstream ratchet subsystem skips via col==effCol; the mod/glide + tick loops skip via rowLaunchArmed).
                let anchor = box.rowLaunchAnchor[r]
                if anchor != 0 && anchor > beatPos {
                    rowLaunchArmed[r] = true; prevEffColumnRow[r] = -1
                    rowSBuf[r] = box.rowStep[r] * clockScale; rowCycBuf[r] = 1; rowMNowBuf[r] = 0; rowEffColBuf[r] = -1; rowPassBuf[r] = 0
                    continue
                }
                rowLaunchArmed[r] = false
                let Sr = box.rowStep[r] * clockScale   // ROW 8 HALFTIME scales every row's clock too
                let Lr = box.rowLength[r]
                let mNr = musicalOf(beatPos - anchor, stepBeats: Sr, a: a)   // PLAY-FERRY LAUNCH: (beat − anchor) → the row's own phase-0 is the launch beat
                let cycR = Double(Lr) * Sr
                let posR = mNr - (mNr / cycR).rounded(.down) * cycR
                let trueColR = min(Lr - 1, max(0, Int(posR / Sr)))
                let absStepR = Int((mNr / Sr).rounded(.down))
                var effColR = lapColumn(laneMask: rowHeld[r], absoluteStep: absStepR, trueColumn: trueColR)   // PER-ROW LAP
                if forceColumnHold { effColR = forceColumn }
                let passR = Int((mNr / cycR).rounded(.down))
                rowSBuf[r] = Sr; rowCycBuf[r] = cycR; rowMNowBuf[r] = mNr; rowEffColBuf[r] = effColR; rowPassBuf[r] = passR
                let pinnedRow = rowHeld[r] != 0 && (rowHeld[r] & (rowHeld[r] &- 1)) == 0   // exactly one held column = a PINNED continuous row (audition / single play-cell) → sustain-reconcile its legato holds every window
                prevEffColumnRow[r] = emitColumnTransition(box: box, effCol: effColR, prevEdge: prevEffColumnRow[r], onlyRow: r,
                                                           S: Sr, a: a, mNow: mNr, pass: passR, tempo: tempo,
                                                           beatPos: beatPos - anchor, beatsPerSample: beatsPerSample,   // PLAY-FERRY LAUNCH: the ANCHORED beat, so the transition's strike/close sample offsets stay in the raw window (anchor cancels in the difference) while the phase shifts
                                                           windowStart: windowStart, windowEnd: windowEnd, cycleBeats: cycR,
                                                           heldActive: rowHeld[r] != 0, pinned: pinnedRow, pool: pool, out: out, diag: &diag)
            }
            diag.pass = globalPass
            prevEffColumn = effColumn   // keep the GLOBAL edge current (echo dry now fires per-row above, on each row's own clock)
        }
        prevUniformFast = uniformFast   // CR-11: remember the clock mode so the next render detects a live uniform↔multi switch

        // ECHO tails ring out independent of the column and even after the source releases — BEFORE the empty-pool guard.
        chanOverride = -1; nudgeSamples = 0   // UTILITY: the holds above set these per-cell; echo tails use the wire defaults (v1)
        drainEchoTails(box: box, mStart: mNow, mEnd: musicalOf(beatPos + Double(frameCount) * beatsPerSample, stepBeats: S, a: a),
                       beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, windowEnd: windowEnd,
                       S: S, a: a, out: out, diag: &diag)

        // THE MOD PROCESSOR (CC, no keys) + GLIDE (mono bend) — BEFORE the pool guard. On the uniform fast path they run
        // once at the global column; on the multi-clock path each row's MOD/GLIDE cells fire at that ROW's own column
        // (per-part clock), with per-row leave-disposition. (Paul 2026-08-19)
        let modWindowBeats = Double(frameCount) * beatsPerSample
        if uniformFast {
            emitColumnMod(box: box, column: effColumn, pool: pool, beatPos: beatPos, windowBeats: modWindowBeats,
                          beatsPerSample: beatsPerSample, windowStart: windowStart, out: out, S: S, cycleBeats: cycleBeats)
            emitColumnGlide(box: box, column: effColumn, pool: pool, beatPos: beatPos, windowBeats: modWindowBeats,
                            beatsPerSample: beatsPerSample, windowStart: windowStart, out: out)
            emitColumnRecorder(box: box, column: effColumn, beatPos: beatPos, windowBeats: modWindowBeats,
                               passBeats: cycleBeats, S: S, a: a, beatsPerSample: beatsPerSample,
                               windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        } else {
            for r in 0..<Snap.rows {
                if rowLaunchArmed[r] { continue }   // PLAY-FERRY LAUNCH: armed-not-started rows emit nothing (rowEffColBuf = -1)
                let rowBeat = beatPos - box.rowLaunchAnchor[r]   // PLAY-FERRY LAUNCH: anchored beat (anchor cancels in the offset math; 0 ⇒ raw)
                emitColumnMod(box: box, column: rowEffColBuf[r], pool: pool, beatPos: rowBeat, windowBeats: modWindowBeats,
                              beatsPerSample: beatsPerSample, windowStart: windowStart, out: out, onlyRow: r,
                              S: box.rowStep[r], cycleBeats: Double(box.rowLength[r]) * box.rowStep[r])
                emitColumnGlide(box: box, column: rowEffColBuf[r], pool: pool, beatPos: rowBeat, windowBeats: modWindowBeats,
                                beatsPerSample: beatsPerSample, windowStart: windowStart, out: out, onlyRow: r)
                let recSr = box.rowStep[r]; let recPass = Double(box.rowLength[r]) * recSr
                emitColumnRecorder(box: box, column: rowEffColBuf[r], beatPos: rowBeat, windowBeats: modWindowBeats,
                                   passBeats: recPass, S: recSr, a: a, beatsPerSample: beatsPerSample,
                                   windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag, onlyRow: r)
            }
        }
        // FREE / LFO CELL (design-cc-stage §16, Paul 2026-09-09): MOD cells marked FREE emit every window regardless of
        // the playhead — the grid as a mod-matrix. Scans all cells (active-column FREE slots skipped in emitColumnMod).
        emitFreeMod(box: box, pool: pool, beatPos: beatPos, windowBeats: modWindowBeats,
                    beatsPerSample: beatsPerSample, windowStart: windowStart, out: out)
        // STANDALONE RATCHET PATTERN (Paul 2026-09-08): a per-window pass-through subsystem (scans all cells, owns its
        // immortal sustains) — BEFORE the pool guard so it closes on release. One call handles uniform + per-row clocks.
        emitColumnRatchetPattern(box: box, uniformFast: uniformFast, effColumn: effColumn, pool: pool,
                                 beatPos: beatPos, windowBeats: modWindowBeats, windowStart: windowStart, windowEnd: windowEnd,
                                 beatsPerSample: beatsPerSample, S: S, a: a, out: out, diag: &diag)

        // CHORDS BUTTON (Paul 2026-10-08): a real gap found while testing, not by inspection — this guard
        // predates CHORDS mode and was always safe before it: EVERY processor type in this engine has always
        // needed SOME held/latched input to produce sound, so "nothing held anywhere ⇒ nothing can play" was a
        // completely sound assumption. A CHORDS-mode Euclideous lane breaks it — it generates its own content
        // algorithmically and must keep playing even when nothing else in the whole session has anything held.
        // Cheap, allocation-free check (euclidLines is always exactly 4 entries) mirrors the SAME "run me
        // regardless of the pool" exception `emitFreeMod`/`emitColumnRatchetPattern` already get, just folded
        // into this guard's own condition instead of a separate pre-guard call, since CHORDS rides the NORMAL
        // emitTickRow→emitGeneratorRow dispatch once past this point (no separate subsystem needed).
        let euclideousChordsActive = box.cells[Snap.euclideousRow].procs.first?.euclidLines.contains { $0.sourceModeResolved == .chords } ?? false
        guard pool.count > 0 || latchMask != 0 || euclideousChordsActive else {   // latch: a frozen pool drives the TICK (arp) cells with no keys down
            for i in euclidLineReady.indices { euclidLineReady[i] = 0 }   // nothing held/latched ⇒ nothing can play; case .euclid: won't run below to refresh this itself
            euclideousRiffLiveCount = 0   // same reasoning — the riff's own live-pool display feed goes empty too
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding; return
        }

        // ---- per-window TICK content: evaluate rows top-down so a fed cell reads its feeder's
        //      output (mirror model). ARP cells produce ticks; identity-fed cells mirror the feeder;
        //      identity-unfed cells have no tick content (their hold was emitted at the transition). ----
        for r in 0..<Snap.rows { articCount[r] = 0 }
        for i in 0..<Snap.cells { glideDrivenCount[i] = 0 }   // §7① [driver→GLIDE]: fresh per-window target buffer (emitDriverNote fills it, emitGlideDriven drains it)
        let windowBeats = Double(frameCount) * beatsPerSample

        if uniformFast {
            for r in 0..<Snap.rows {
                emitTickRow(r: r, effColumn: effColumn, S: S, cycleBeats: cycleBeats, windowBeats: windowBeats,
                            box: box, pool: pool, beatPos: beatPos, windowStart: windowStart, windowEnd: windowEnd,
                            beatsPerSample: beatsPerSample, a: a, heldCell: heldCell, out: out, diag: &diag)
                emitGlideDriven(box: box, column: effColumn, row: r, beatPos: beatPos, windowBeats: windowBeats,   // §7① [driver→GLIDE]: drain the driver's targets into the mono glide voice
                                beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a, out: out)
            }
        } else {
            let globalPass = diag.pass   // per-row ticks run on each row's OWN clock (buffers filled in the transition loop)
            for r in 0..<Snap.rows {
                if rowLaunchArmed[r] { continue }   // PLAY-FERRY LAUNCH: armed-not-started rows emit no ticks (rowEffColBuf = -1)
                diag.pass = rowPassBuf[r]
                let rowBeat = beatPos - box.rowLaunchAnchor[r]   // PLAY-FERRY LAUNCH: anchored beat so the arp/tick PHASE shifts with the launch (offset math cancels the anchor); 0 ⇒ raw
                emitTickRow(r: r, effColumn: rowEffColBuf[r], S: rowSBuf[r], cycleBeats: rowCycBuf[r], windowBeats: windowBeats,
                            box: box, pool: pool, beatPos: rowBeat, windowStart: windowStart, windowEnd: windowEnd,
                            beatsPerSample: beatsPerSample, a: a, heldCell: heldCell, out: out, diag: &diag)
                emitGlideDriven(box: box, column: rowEffColBuf[r], row: r, beatPos: rowBeat, windowBeats: windowBeats,   // §7① per-row clock
                                beatsPerSample: beatsPerSample, windowStart: windowStart, S: rowSBuf[r], a: a, out: out)
            }
            diag.pass = globalPass
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
    private func modSourceUnipolar(_ p: SnapParams, cell: SnapCell, pool: NotePool, b: Double, period: Double, column: Int, entryBeat: Double) -> Double {
        switch p.modSource {
        case .shape:
            return modUnipolar(p.modShape, phase: b / period + p.modPhase, column: column, cc: p.modCC, cycleIndex: Int((b / period).rounded(.down)))   // §14② PHASE offset
        case .steps:
            return modStepsUnipolar(p.modSteps, phase: b / period, smooth: p.modSmooth)
        case .strike:
            return modStrikeUnipolar(t: b - entryBeat, attack: p.modAttack, release: p.modRelease)
        case .follow:
            let src = effectivePool(for: cell, live: pool)
            let n = src.srcCount(for: cell)
            var sumN = 0.0, sumV = 0.0
            for k in 0..<n { let note = src.srcAscending(k, for: cell); sumN += Double(note); sumV += Double(src.velocity(note)) }
            return modFollowUnipolar(p.modFollow, count: n, meanNote: n > 0 ? sumN / Double(n) : 0, meanVel: n > 0 ? sumV / Double(n) : 0)
        case .extern:
            let raw = controllerIn[p.modExternCC & 127]                       // channel-agnostic v1
            let ext = raw < 0 ? 0 : Double(raw) / 127.0                        // never seen → rest at 0
            if p.modExternMode == .scale {                                    // §6 SCALE: the wheel scales the SHAPE's depth (rhythm from us, amount from the hand)
                let sh = modUnipolar(p.modShape, phase: b / period + p.modPhase, column: column, cc: p.modCC, cycleIndex: Int((b / period).rounded(.down)))
                return sh * ext
            }
            return ext                                                        // RE-EMIT (re-ranged by MIN/MAX below)
        }
    }

    // SPAN — SHAPE: CELL = the modRate period · ROW = the whole bar. STEPS: PERIOD = the rate period · ROW/×2/×4 =
    // 1/2/4 bars. Shared by the CC emit path and the §2 internal-target sampler.
    // S/cycleBeats (Paul 2026-10-05) are now the CALLER's real per-row step/pass length, not Double(Snap.cols)*
    // box.stepBeats — same bug class as the EUCLID 16-wide-part fix, here affecting MOD's ROW/ROW2/ROW4 span
    // modes and its GRID STEPS duration ladder. `box` is no longer needed now that both quantities are passed in.
    private func modPeriodBeats(_ p: SnapParams, S: Double, cycleBeats: Double) -> Double {
        if p.modStepSpanN > 0 { return max(0.03125, spanLadderBeats(p.modStepSpanN, S: S, row: cycleBeats)) }   // GRID STEPS duration (Paul 2026-09-16, the arp-LFO ladder) — supersedes modRate/modSpan when set
        if p.modSource == .steps {
            switch p.modStepSpan {
            case .period: return max(0.03125, p.modRate.periodBeats)
            case .row:    return max(0.03125, cycleBeats)
            case .row2:   return max(0.03125, 2 * cycleBeats)
            case .row4:   return max(0.03125, 4 * cycleBeats)
            }
        }
        return (p.modSpan == .row) ? max(0.03125, cycleBeats) : max(0.03125, p.modRate.periodBeats)
    }

    // §2 INTERNAL TARGET (Paul 2026-08-20): apply each internal-target MOD's BOUNDARY value (sampled once at the column
    // start — boundary-deferred) to the cell's chain params, on the offset lane. Byte-identical when no MOD targets the
    // chain (the loop finds none → cell untouched). Applied to EVERY slot (harmless where the param is unused) + the head.
    private func applyInternalMods(_ cell: inout SnapCell, column: Int, pool: NotePool, mNow: Double, S: Double, cycleBeats: Double, box: SnapshotBox) {
        let boundary = columnStart(mNow, S)   // no render-path allocation — apply each internal MOD's offset inline (invariant 3)
        for si in 0..<cell.procs.count where !cell.slotBypass[si] && cell.procs[si].type == .mod && cell.procs[si].modTarget == .chain {
            let mp = cell.procs[si]
            let u = modSourceUnipolar(mp, cell: cell, pool: pool, b: boundary, period: modPeriodBeats(mp, S: S, cycleBeats: cycleBeats), column: column, entryBeat: boundary)
            let out = Double(mp.modMin) / 127 + u * Double(mp.modMax - mp.modMin) / 127   // MIN/MAX re-range (MIN>MAX inverts)
            let off = out * macroParamSpan(mp.modChainParam)                               // scale to the param's span (approved v1 mapping)
            if off == 0 { continue }
            let param = mp.modChainParam
            for sj in 0..<cell.procs.count { cell.procs[sj] = applyModChainOffset(cell.procs[sj], param: param, offset: off) }   // every slot (harmless where unused); `proc` = procs[0]
        }
    }

    /// Emit each active-column MOD slot's CC over this window at a control grid (block-size invariant, replay-safe),
    /// on every ENABLED bus's cable + All, on the bus's stamp channel. Runs BEFORE the held-note guard — MOD needs no
    /// keys down. When the playhead LEAVES a column, the departed column's MOD cells (modReset) send their default (0).
    private func emitColumnMod(box: SnapshotBox, column: Int, pool: NotePool, beatPos: Double, windowBeats: Double,
                               beatsPerSample: Double, windowStart: Int64, out: MIDIEmitter?, onlyRow: Int? = nil,
                               S: Double = 0, cycleBeats: Double = 0) {
        let slot = onlyRow ?? Snap.rows                           // PER-ROW LEAVE-DISPOSITION: one slot per row, or the global slot
        if modLastColumn[slot] != Int32(column) {                 // LEAVE-DISPOSITION: reset the column we just left
            if modLastColumn[slot] >= 0 { emitModResets(box: box, column: Int(modLastColumn[slot]), atSample: windowStart, out: out, onlyRow: onlyRow) }
            modLastColumn[slot] = Int32(column)
            modColumnEntryBeat[slot] = beatPos                    // STRIKE: the AR envelope re-triggers on column entry
        }
        let entryBeat = modColumnEntryBeat[slot]
        if masterMute && !previewMode { return }                  // master MUTE kills all output
        guard column >= 0 && column < Snap.maxCols else { return }
        let bEnd = beatPos + windowBeats
        for r in 0..<Snap.rows where onlyRow == nil || onlyRow == r {
            let cell = box.cells[column * Snap.rows + r]
            if cell.machineIndex < 0 || cell.busMask == 0 || soloSilenced(cell) { continue }
            if cell.muted || cell.dormant { continue }
            for si in 0..<cell.procs.count where !cell.slotBypass[si] && cell.procs[si].type == .mod {
                let p = cell.procs[si]
                if p.modFree { continue }   // FREE / LFO cell (§16): emitted every window by emitFreeMod, regardless of the active column — skip here to avoid double-emit
                // TARGET CHANGED (the CC# knob swept): revert the ABANDONED cc to its STANDARD value so sweeping past
                // e.g. VOLUME (CC7) doesn't leave it knocked down. (user 2026-08-10.)
                let tkey = (column * Snap.rows + r) * 8 + si
                if tkey >= 0 && tkey < modPrevTarget.count {
                    let prev = Int(modPrevTarget[tkey])
                    if prev >= 0 && prev != p.modCC { emitModCC(cc: prev, value: ccDefault(prev), busMask: cell.busMask, atSample: windowStart, out: out) }
                    modPrevTarget[tkey] = Int16(p.modCC)
                }
                if p.modTarget == .chain { continue }   // §2 INTERNAL TARGET: emits NO CC — the offset is applied to the chain in emitTickRow/emitColumnHolds
                let period = modPeriodBeats(p, S: S, cycleBeats: cycleBeats)
                var k = Int((beatPos / modCtrlBeats).rounded(.up))    // control-grid points in [beatPos, bEnd)
                while Double(k) * modCtrlBeats < bEnd {
                    let b = Double(k) * modCtrlBeats
                    if b >= beatPos {
                        // CLOCK (Paul 2026-09-26, Stage 3): MOD has no driver — CLOCK reaches it whenever a CLOCK stage
                        // sits ANYWHERE before MOD's own slot in THIS cell's chain (from chain-start, not driver-relative
                        // like the fold consumers), transforming only the SHAPE read below; `sample` (when the CC is
                        // actually sent) stays on the real beat `b` — CLOCK never touches real output timing.
                        let bClock = S > 0 ? clockTransformedBeat(cell, from: 0, to: si, atBeat: b, S: S, cycleBeats: cycleBeats) : b
                        let s = modSourceUnipolar(p, cell: cell, pool: pool, b: bClock, period: period, column: column, entryBeat: entryBeat)
                        var value = modMap(s, min: p.modMin, max: p.modMax)
                        if p.modQuantize > 1 { value = modQuantizeValue(value, levels: p.modQuantize) }   // §14① QUANTIZE
                        let sample = windowStart + Int64((((b - beatPos) / beatsPerSample)).rounded())
                        emitModCC(cc: p.modCC, value: value, busMask: cell.busMask, atSample: sample, out: out)
                    }
                    k += 1
                }
            }
        }
    }
    /// FREE / THE LFO CELL (design-cc-stage §16, Paul 2026-09-09): MOD slots with `modFree` speak EVERY window
    /// regardless of the playhead — place a cell whose whole job is modulation and the grid becomes a mod-matrix.
    /// Scans ALL cells (the active column's FREE slots are skipped by emitColumnMod → no double-emit). Beat-derived
    /// (f(absolute beat) → replay-safe, block-invariant); NO leave-disposition (a FREE cell never exits), and a
    /// transport/scene flush (flushMod) stops it. Runs once per window, before the pool guard. CC targets only
    /// (a FREE chain-target has no active column to fold into — out of scope v1).
    private func emitFreeMod(box: SnapshotBox, pool: NotePool, beatPos: Double, windowBeats: Double,
                             beatsPerSample: Double, windowStart: Int64, out: MIDIEmitter?) {
        if masterMute && !previewMode { return }
        let bEnd = beatPos + windowBeats
        for idx in 0..<Snap.cells {
            let cell = box.cells[idx]
            if cell.machineIndex < 0 || cell.busMask == 0 || soloSilenced(cell) { continue }
            let col = idx / Snap.rows, row = idx % Snap.rows
            if cell.muted || cell.dormant { continue }
            let rowS = box.rowStep[row], rowCyc = Double(box.rowLength[row]) * rowS   // CLOCK (Stage 3): this row's own clock, for the transform below
            for si in 0..<cell.procs.count where !cell.slotBypass[si] && cell.procs[si].type == .mod && cell.procs[si].modFree && cell.procs[si].modTarget == .cc {
                let p = cell.procs[si]
                let period = modPeriodBeats(p, S: rowS, cycleBeats: rowCyc)
                var k = Int((beatPos / modCtrlBeats).rounded(.up))
                while Double(k) * modCtrlBeats < bEnd {
                    let b = Double(k) * modCtrlBeats
                    if b >= beatPos {
                        let bClock = rowS > 0 ? clockTransformedBeat(cell, from: 0, to: si, atBeat: b, S: rowS, cycleBeats: rowCyc) : b
                        let s = modSourceUnipolar(p, cell: cell, pool: pool, b: bClock, period: period, column: col, entryBeat: 0)   // FREE ignores column entry → phase from the origin
                        var value = modMap(s, min: p.modMin, max: p.modMax)
                        if p.modQuantize > 1 { value = modQuantizeValue(value, levels: p.modQuantize) }
                        let sample = windowStart + Int64((((b - beatPos) / beatsPerSample)).rounded())
                        emitModCC(cc: p.modCC, value: value, busMask: cell.busMask, atSample: sample, out: out)
                    }
                    k += 1
                }
            }
        }
    }
    /// Reset every MOD cell in `column` whose modReset is ON to its default (0) — the CC-pollution guard. Stateless.
    private func emitModResets(box: SnapshotBox, column: Int, atSample: Int64, out: MIDIEmitter?, onlyRow: Int? = nil) {
        guard column >= 0 && column < Snap.maxCols, !(masterMute && !previewMode) else { return }
        for r in 0..<Snap.rows where onlyRow == nil || onlyRow == r {
            let cell = box.cells[column * Snap.rows + r]
            if cell.machineIndex < 0 || cell.busMask == 0 { continue }
            for si in 0..<cell.procs.count where !cell.slotBypass[si] && cell.procs[si].type == .mod && cell.procs[si].modReset && cell.procs[si].modTarget == .cc {
                emitModCC(cc: cell.procs[si].modCC, value: cell.procs[si].modMin, busMask: cell.busMask, atSample: atSample, out: out)   // RESET → MIN (CC targets only; internal has no CC)
            }
        }
    }
    /// Transport/scene/panic flush: reset the last MOD column (leave-disposition) + forget the dedup state.
    private func flushMod(box: SnapshotBox, atSample: Int64, out: MIDIEmitter?) {
        for slot in modLastColumn.indices {                       // reset EVERY row's last MOD column (+ the global slot)
            let onlyRow = slot < Snap.rows ? slot : nil
            if modLastColumn[slot] >= 0 { emitModResets(box: box, column: Int(modLastColumn[slot]), atSample: atSample, out: out, onlyRow: onlyRow) }
            modLastColumn[slot] = -1
        }
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
    /// Reset the CONTROLLERS a glide voice armed on its bus channel — the pitch wheel (BEND) back to centre, and the
    /// portamento CC65 (SYNTH) OFF. The immortal glide NOTE is closed separately (closeVoice / allNotesOff), but its
    /// controllers are NOT, so any edge that abandons a glide voice MUST call this or later notes on that channel play
    /// detuned (bend left off-centre) or glued (CC65 left armed). One source of truth for glidePhraseEnd + every flush
    /// edge (transport/scene/panic/latch via flushGlide, and the emitter enable→disable edge). (Paul 2026-08-27 E1/E5)
    private func resetGlideControllers(_ gv: GlideVoice, atSample: Int64, out: MIDIEmitter?) {
        guard gv.anchor >= 0, gv.bus >= 0 else { return }
        let ch = (busChannels[Int(gv.bus)] &- 1) & 15
        if gv.mode == .bend  { emitBend(cable: UInt8(gv.bus + 1), ch: ch, value: 8192, atSample: atSample, out: out) }   // SYNTH/STEP emit no bend (Paul 2026-08-26)
        if gv.mode == .synth { out?.emit(sampleTime: atSample, cable: UInt8(gv.bus + 1), 0xB0 | ch, 65, 0) }
    }
    /// End a GLIDE cell's phrase: close its anchor voice + reset its controllers, and forget the voice.
    private func glidePhraseEnd(_ cellIdx: Int, atSample: Int64, out: MIDIEmitter?) {
        let gv = glideVoices[cellIdx]
        if gv.anchor >= 0 {
            if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: atSample, out: out) }
            resetGlideControllers(gv, atSample: atSample, out: out)
        }
        glideVoices[cellIdx] = GlideVoice()
    }
    private func glidePhraseEndColumn(_ column: Int, atSample: Int64, out: MIDIEmitter?, onlyRow: Int? = nil) {
        guard column >= 0 && column < Snap.maxCols else { return }
        for r in 0..<Snap.rows where onlyRow == nil || onlyRow == r { glidePhraseEnd(column * Snap.rows + r, atSample: atSample, out: out) }
    }
    /// An EXTERNAL closer (MONO voice-steal) just closed the voice at `slot`. If that voice was a GLIDE anchor, the glide
    /// subsystem still holds `glideVoices[k].slot == slot` — a dangling reference to a now-freed (and possibly REUSED) slot,
    /// so a later glide update would wrong-close whatever voice took the slot (a spurious note-off). Forget the bookkeeping:
    /// re-centre the anchor's bend/CC (else it's left off-centre) + clear the GlideVoice. The note-off itself was already
    /// emitted by the external closer. (Paul 2026-09-01 bug-hunt Finding 4.)
    private func forgetGlideAnchorAtSlot(_ slot: Int, atSample: Int64, out: MIDIEmitter?) {
        for k in glideVoices.indices where glideVoices[k].anchor >= 0 && Int(glideVoices[k].slot) == slot {
            resetGlideControllers(glideVoices[k], atSample: atSample, out: out)
            glideVoices[k] = GlideVoice()
        }
    }
    /// Transport/scene/panic flush: the immortal glide notes are closed by allNotesOff — just forget the state.
    private func flushGlide(atSample: Int64 = renderSampleImmediate, out: MIDIEmitter? = nil) {
        for i in glideVoices.indices {
            resetGlideControllers(glideVoices[i], atSample: atSample, out: out)   // BEND re-centre + SYNTH CC65 off (E1 fix 2026-08-27: bend was left off-centre → later notes detuned)
            glideVoices[i] = GlideVoice()
        }
        for i in glideLastColumn.indices { glideLastColumn[i] = -1 }
    }
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
    /// R2 (2026-08-30): the OUTPUT pitch a glide voice sounds — the SAME transform the grid applies in emitOneBus:
    /// emitter OCT overlay + master KEY (per-scene transpose), range-guarded, then the RACK FENCE. nil ⇒ suppress
    /// (out of range / fence DROP). So a glide plays IN KEY and honours per-emitter octave + FENCE, like every other
    /// voice (was raw source pitch → glide diverged from the rest of the patch). previewMode bypasses KEY + FENCE
    /// (a stopped audition, like emitOneBus). Safe: every glide close is by the stored voice SLOT, never a recomputed
    /// note, so shifting the note at the open sites can never strand an off.
    private func glideOutNote(_ inNote: Int, bus: Int) -> UInt8? {
        let sn = inNote + emitterOctaveShift(bus) + (previewMode ? 0 : masterKey)
        guard sn >= 0 && sn <= 127 else { return nil }
        if previewMode { return UInt8(sn) }
        return fencedNote(UInt8(sn), bus: bus)
    }
    /// R2: whether a glide may sound on this emitter — the emitter ENABLE + output-SOLO gates emitOneBus applies. A
    /// disabled or soloed-out emitter silences glide; a glide voice on a now-unavailable bus is PHRASE-ENDED at its
    /// call sites (self-correcting each render → no stuck note). previewMode bypasses (a solo audition has no
    /// other-emitter context — matches emitOneBus). CLAIM + CONVERSATION are intentionally NOT applied: their discrete
    /// note-ghost / per-onset-stance models don't map onto a continuous mono bend (flagged as a future item).
    private func glideBusAvailable(_ bus: Int) -> Bool {
        if previewMode { return true }
        return bit(busEnabledMask, bus) && (soloEmitterMask == 0 || bit(soloEmitterMask, bus))
    }
    /// Drive the mono glide voices for the active column's single-slot GLIDE cells: anchor on the first note, bend-ramp
    /// to each in-range target (else RE-ANCHOR / CLAMP), phrase-end on rest or column exit. Runs before the pool guard.
    // RECORDER (AcceptanceCriteria-recorder) — commit the capture at the record-window end, then play the committed loop.
    // Runs per window BEFORE the tick loop (like emitColumnGlide), so a commit lands before this window's driver fold.
    // The buffer is captured in emitDriverNote (upstream driver); REPLACE-suppression of the live note happens there.
    private func emitColumnRecorder(box: SnapshotBox, column: Int, beatPos: Double, windowBeats: Double,
                                    passBeats: Double, S: Double, a: Double, beatsPerSample: Double,
                                    windowStart: Int64, windowEnd: Int64, out: MIDIEmitter?, diag: inout KernelDiag,
                                    onlyRow: Int? = nil) {
        if masterMute && !previewMode { return }
        guard column >= 0 && column < Snap.maxCols else { return }
        let mStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        for r in 0..<Snap.rows where onlyRow == nil || onlyRow == r {
            let ci = column * Snap.rows + r
            let cell = box.cells[ci]
            guard let rs = recorderSlot(cell) else { continue }
            if cell.machineIndex < 0 || cell.busMask == 0 || soloSilenced(cell) || cell.muted || cell.dormant { continue }
            let rp = cell.procs[rs]
            let w = recWindow(rp, passBeats: passBeats, stepBeats: S)
            let unit = Int((mStart / w.unitBeats).rounded(.down))
            // CANON (rolling self-delay): at each window boundary, the just-finished window's capture → the play buffer;
            // play it back ONE WINDOW LATE. The live input keeps playing (LAYER in the capture hook), so the phrase
            // chases itself a window later — a round. Never locks (keeps rolling).
            if rp.recMode == .canon {
                let win = max(0.03125, w.window)
                let widx = Int((mStart / win).rounded(.down))
                if recWindowIdx[ci] != widx {
                    let base = ci * Router.recNoteCap, n = min(recCapN[ci], Router.recNoteCap)
                    for i in 0..<n { recBufStart[base+i] = recCapStart[base+i]; recBufNote[base+i] = recCapNote[base+i]; recBufVel[base+i] = recCapVel[base+i]; recBufGate[base+i] = recCapGate[base+i] }
                    recBufN[ci] = n; recCapN[ci] = 0; recWindowIdx[ci] = widx
                }
                if recBufN[ci] > 0 {
                    currentCellIndex = ci; chanOverride = -1; nudgeSamples = 0
                    for i in 0..<recBufN[ci] {
                        let x = ci * Router.recNoteCap + i
                        let sched = Double(widx) * win + recBufStart[x]
                        if sched >= mStart && sched < mEnd {
                            let onS = sampleOf(musical: sched, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                            let gate = max(0.01, recBufGate[x])
                            let offS = min(windowEnd, sampleOf(musical: sched + gate, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a))
                            emitArtic(note: recBufNote[x], busMask: cell.busMask, onSample: onS, offSample: max(onS + 1, offS), windowEnd: windowEnd, velocity: recBufVel[x], out: out, diag: &diag)
                        }
                    }
                    currentCellIndex = -1
                }
                continue
            }
            // LOAD / authored buffer: a persisted (or hand-authored) recEvents seeds the loop directly — it plays
            // immediately and the live capture is skipped (recEvents is AUTHORITATIVE when present; CLEAR empties it →
            // live recording resumes). REFRESH still re-arms over it; ONCE plays it forever. (SAVE — draining a live
            // capture back to recEvents — is a later stage; this is the read/CLEAR half.)
            if !recCaptured[ci] && recBufN[ci] == 0 && !rp.recEvents.isEmpty {
                let n = min(rp.recEvents.count, Router.recNoteCap), base = ci * Router.recNoteCap
                for i in 0..<n {
                    let ev = rp.recEvents[i]
                    recBufStart[base+i] = max(0, ev.beat); recBufNote[base+i] = UInt8(max(0, min(127, ev.note)))
                    recBufVel[base+i] = UInt8(max(1, min(127, ev.vel))); recBufGate[base+i] = max(0.01, ev.gate)
                }
                recBufN[ci] = n; recCaptured[ci] = true; recCycleBase[ci] = unit
            }
            // ARM: on first reaching the record window, set the rolling record-window origin (REFRESH re-arms it later).
            let recN = max(1, w.endUnit - w.startUnit)
            if !recCaptured[ci] && recArmUnit[ci] == Int.min && unit >= w.startUnit { recArmUnit[ci] = w.startUnit }
            // COMMIT at the record-window end: build the loop buffer from the capture, per MODE.
            if !recCaptured[ci] && recArmUnit[ci] != Int.min && unit >= recArmUnit[ci] + recN && recCapN[ci] > 0 {
                let src = min(recCapN[ci], Router.recNoteCap)
                let base = ci * Router.recNoteCap
                if rp.recMode == .freeze && rp.recFreeze == .held {
                    // FREEZE HELD: collapse to DISTINCT pitches, each held for the whole window (a frozen pad that
                    // re-pulses per loop — a true legato sustain is a follow-up needing the immortal-hold reconcile).
                    var n = 0
                    for i in 0..<src {
                        let note = recCapNote[base + i]
                        var dup = false
                        for j in 0..<n where recBufNote[base + j] == note { dup = true; break }
                        if !dup && n < Router.recNoteCap {
                            recBufStart[base + n] = 0; recBufNote[base + n] = note
                            recBufVel[base + n] = recCapVel[base + i]; recBufGate[base + n] = w.window
                            n += 1
                        }
                    }
                    recBufN[ci] = n
                } else {
                    // LOOP · FREEZE REPEAT · (CANON plays as loop in v1): the captured notes verbatim.
                    for i in 0..<src {
                        recBufStart[base + i] = recCapStart[base + i]; recBufNote[base + i] = recCapNote[base + i]
                        recBufVel[base + i] = recCapVel[base + i]; recBufGate[base + i] = recCapGate[base + i]
                    }
                    recBufN[ci] = src
                }
                recCaptured[ci] = true; recCycleBase[ci] = recArmUnit[ci] + recN
            }
            // REFRESH: every M cycles (M × N units) after the commit, re-arm to re-record the next window (the old loop
            // pauses for that window while the live input is re-captured; ONCE/HOLD never re-arm here — HOLD's momentary
            // grab needs a control signal, a later stage).
            if recCaptured[ci] && rp.recCapture == .refresh {
                let m2 = max(1, rp.recRefreshM)
                if unit >= recCycleBase[ci] + m2 * recN { recCaptured[ci] = false; recCapN[ci] = 0; recArmUnit[ci] = unit }
            }
            guard recCaptured[ci], recBufN[ci] > 0, w.window > 0 else { continue }   // nothing to play yet (recording / re-recording)
            // PLAYBACK: LOOP the buffer from beat 0. Emit due notes in [mStart, mEnd) (test this loop iteration + the next).
            let kBase = Int((mStart / w.window).rounded(.down))
            currentCellIndex = ci; chanOverride = -1; nudgeSamples = 0
            for i in 0..<recBufN[ci] {
                let x = ci * Router.recNoteCap + i
                let st = recBufStart[x]
                for k in [kBase, kBase + 1] where k >= 0 {
                    let sched = Double(k) * w.window + st
                    if sched >= mStart && sched < mEnd {
                        let onS = sampleOf(musical: sched, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                        let gate = max(0.01, recBufGate[x])
                        let offS = min(windowEnd, sampleOf(musical: sched + gate, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a))
                        emitArtic(note: recBufNote[x], busMask: cell.busMask, onSample: onS, offSample: max(onS + 1, offS),
                                  windowEnd: windowEnd, velocity: recBufVel[x], out: out, diag: &diag)
                    }
                }
            }
            currentCellIndex = -1
        }
    }
    private func emitColumnGlide(box: SnapshotBox, column: Int, pool: NotePool, beatPos: Double, windowBeats: Double,
                                 beatsPerSample: Double, windowStart: Int64, out: MIDIEmitter?, onlyRow: Int? = nil) {
        let slot = onlyRow ?? Snap.rows
        if glideLastColumn[slot] != Int32(column) {                 // PHRASE END on column exit (spec)
            if glideLastColumn[slot] >= 0 { glidePhraseEndColumn(Int(glideLastColumn[slot]), atSample: windowStart, out: out, onlyRow: onlyRow) }
            glideLastColumn[slot] = Int32(column)
        }
        if masterMute && !previewMode { return }
        guard column >= 0 && column < Snap.maxCols else { return }
        let bEnd = beatPos + windowBeats
        for r in 0..<Snap.rows where onlyRow == nil || onlyRow == r {
            let cellIdx = column * Snap.rows + r
            let cell = box.cells[cellIdx]
            // §7① [driver→GLIDE] v2: a driven-glide cell's ACTIVE emission is post-tick (emitGlideDriven); this pass runs
            // BEFORE the pool guard, so here we only phrase-end it on REST / mute (a key-release while the column is
            // unchanged — column-exit is already handled by the glideLastColumn block above), then leave it to the tick.
            let dr = chainDriverIndex(cell)
            if dr >= 0, downstreamGlideIndex(cell, after: dr) != nil {
                let inactive = cell.machineIndex < 0 || cell.busMask == 0 || soloSilenced(cell) || cell.muted || cell.dormant
                    || effectivePool(for: cell, live: pool).count == 0
                    || (cell.busMask != 0 && !glideBusAvailable(Int(cell.busMask.trailingZeroBitCount)))   // R2: a disabled/soloed-out emitter silences the driven glide
                if inactive { glidePhraseEnd(cellIdx, atSample: windowStart, out: out) }
                continue
            }
            // SINGLE-SLOT GLIDE (the soloist): its mono voice is picked from the held pool below.
            guard cell.procs.count == 1, cell.procs[0].type == .glide, !cell.slotBypass[0] else { continue }
            if cell.machineIndex < 0 || cell.busMask == 0 || soloSilenced(cell) || cell.muted || cell.dormant {
                glidePhraseEnd(cellIdx, atSample: windowStart, out: out); continue
            }
            let p = cell.procs[0]
            let ci = Int(cell.machineIndex); let machine = box.machines[ci]
            let transpose = machineTranspose(ci, machine) + octaveShift(cell.resolvedReceiver)
            let pick = glidePickPool(effectivePool(for: cell, live: pool), cell: cell, priority: p.glidePriority)
            guard pick.note >= 0 else { glidePhraseEnd(cellIdx, atSample: windowStart, out: out); continue }   // rest → phrase end
            let inNote = pick.note + transpose
            guard inNote >= 0 && inNote <= 127 else { continue }
            let bus = Int(cell.busMask.trailingZeroBitCount)
            let cable = UInt8(bus + 1)
            let ch = (busChannels[bus] &- 1) & 15
            // R2 (2026-08-30): route the glide through the SAME output gates emitOneBus applies — a disabled/soloed-out
            // emitter silences it (phrase-ended → self-correcting, no stuck note), and the OUTPUT pitch adds the emitter
            // OCT overlay + master KEY + RACK FENCE. Every anchor/bend/re-anchor below keys on `outN` (the output pitch),
            // so the whole voice lives in output space (was: raw source pitch → glide played out of key / off a disabled bus).
            guard glideBusAvailable(bus) else { glidePhraseEnd(cellIdx, atSample: windowStart, out: out); continue }
            guard let outNote = glideOutNote(inNote, bus: bus) else { glidePhraseEnd(cellIdx, atSample: windowStart, out: out); continue }   // out of range / FENCE DROP → phrase-end (like a rest)
            let outN = Int(outNote)
            var gv = glideVoices[cellIdx]
            switch p.glideMode {
            case .bend:
                if gv.anchor < 0 {                                      // ANCHOR: first note = note-on + centred bend
                    let slot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: windowStart, offSample: .max, velocity: pick.vel, out: out, meter: true)
                    gv = GlideVoice(); gv.anchor = Int16(outN); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.lastInput = Int16(outN); gv.rampStart = beatPos
                    emitBend(cable: cable, ch: ch, value: 8192, atSample: windowStart, out: out); gv.lastBend14 = 8192
                } else if Int(gv.lastInput) != outN {                   // NEW TARGET
                    let semis = outN - Int(gv.anchor)
                    if p.glideReanchor && glideNeedsReanchor(target: outN, anchor: Int(gv.anchor), range: p.glideRange) {
                        if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: windowStart, out: out) }
                        emitBend(cable: cable, ch: ch, value: 8192, atSample: windowStart, out: out)
                        let slot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: windowStart, offSample: .max, velocity: pick.vel, out: out, meter: true)
                        gv.anchor = Int16(outN); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.bendFrom = 0; gv.bendTo = 0; gv.rampStart = beatPos; gv.lastBend14 = 8192
                    } else {                                            // GLIDE: capture the current bend, ramp to the new target (clamp if not re-anchoring)
                        let tt = max(0.0001, p.glideTime)
                        gv.bendFrom = gv.bendFrom + (gv.bendTo - gv.bendFrom) * min(1, p.glideTime > 0 ? (beatPos - gv.rampStart) / tt : 1)
                        gv.bendTo = p.glideReanchor ? Double(semis) : Double(max(-p.glideRange, min(p.glideRange, semis)))
                        gv.rampStart = beatPos
                    }
                    gv.lastInput = Int16(outN)
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
            case .synth:
                // SYNTH: the synth glides itself — CC65 portamento ON + CC5 time at anchor, then LEGATO note transitions
                // (open the new note BEFORE releasing the old so the synth portamentos between them). No pitch-bend, no range.
                if gv.anchor < 0 {
                    out?.emit(sampleTime: windowStart, cable: cable, 0xB0 | ch, 65, 127)                 // CC65 portamento ON
                    out?.emit(sampleTime: windowStart, cable: cable, 0xB0 | ch, 5, UInt8(glideSynthCCTime(p.glideTime)))   // CC5 portamento time
                    let slot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: windowStart, offSample: .max, velocity: pick.vel, out: out, meter: true)
                    gv = GlideVoice(); gv.anchor = Int16(outN); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.lastInput = Int16(outN)
                } else if Int(gv.lastInput) != outN {
                    let newSlot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: windowStart, offSample: .max, velocity: pick.vel, out: out, meter: true)
                    if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: windowStart, out: out) }   // release old AFTER new = legato
                    gv.anchor = Int16(outN); gv.slot = Int16(newSlot); gv.lastInput = Int16(outN)
                }
            case .step:
                // STEP: a fast chromatic run source→target — each semitone a short note, the target held. Note-hungry:
                // the zipper opens voices via openVoice (the glide-voice mechanism), so the PER-BEAT flood governor does
                // NOT gate it — it's bounded only by |Δ| ≤ 127 steps and the 128-voice cap. The run is scheduled across
                // windows (idempotent via stepsDone). (review 2026-08-26: corrected — governor doesn't apply here.)
                if gv.anchor < 0 {
                    let slot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: windowStart, offSample: .max, velocity: pick.vel, out: out, meter: true)
                    gv = GlideVoice(); gv.anchor = Int16(outN); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.lastInput = Int16(outN)
                } else if Int(gv.lastInput) != outN {                   // NEW TARGET: start a run from the current note
                    if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: windowStart, out: out) }
                    gv.slot = -1
                    gv.stepFrom = gv.anchor; gv.stepTarget = Int16(outN); gv.stepVel = pick.vel
                    gv.stepTotal = Int16(abs(outN - Int(gv.anchor))); gv.stepsDone = 0; gv.stepRunStart = beatPos
                    gv.anchor = Int16(outN); gv.lastInput = Int16(outN)   // the target becomes the anchor for the NEXT transition
                }
                emitGlideStepRun(&gv, cable: cable, ch: ch, bus: bus, glideTime: p.glideTime, beatPos: beatPos, bEnd: bEnd, beatsPerSample: beatsPerSample, windowStart: windowStart, out: out)
            }
            gv.bus = Int8(bus); gv.mode = p.glideMode
            glideVoices[cellIdx] = gv
        }
    }

    /// §7① [driver→GLIDE] v2 (post-tick): consume the driver's recorded notes (glideDriven* buffer) into the cell's mono
    /// gliding voice. The FIRST target opens a sustained anchor note; each in-range next target BENDS it over glideTime;
    /// a leap beyond RANGE RE-ANCHORS (fresh note-on) or CLAMPS. Between ticks (no new target) the anchor sustains and
    /// the bend keeps ramping. Column-exit + rest phrase-ends are done in emitColumnGlide (before the pool guard); this
    /// only runs for the ACTIVE column's cell. Single-emitter (the cell's lowest bus) — fan-out stays a v2 item.
    private func emitGlideDriven(box: SnapshotBox, column: Int, row r: Int, beatPos: Double, windowBeats: Double,
                                 beatsPerSample: Double, windowStart: Int64, S: Double, a: Double, out: MIDIEmitter?) {
        guard column >= 0 && column < Snap.maxCols else { return }
        if masterMute && !previewMode { return }
        let cellIdx = column * Snap.rows + r
        let cell = box.cells[cellIdx]
        let dr = chainDriverIndex(cell)
        guard dr >= 0, let gi = downstreamGlideIndex(cell, after: dr), !cell.slotBypass[gi] else { return }
        if cell.machineIndex < 0 || cell.busMask == 0 || soloSilenced(cell) || cell.muted || cell.dormant { return }   // inactive → emitColumnGlide already phrase-ended it
        let p = cell.procs[gi]
        let bus = Int(cell.busMask.trailingZeroBitCount)
        guard glideBusAvailable(bus) else { glidePhraseEnd(cellIdx, atSample: windowStart, out: out); return }   // R2: a disabled/soloed-out emitter silences the driven glide (self-correcting → no stuck note)
        let ch = (busChannels[bus] &- 1) & 15
        var gv = glideVoices[cellIdx]
        let cnt = glideDrivenCount[cellIdx]
        let cable = UInt8(bus + 1)
        let bEnd = beatPos + windowBeats
        for i in 0..<cnt {                                        // apply each driver target in beat order
            let inNote = Int(glideDrivenNote[cellIdx * Self.glideDrivenCap + i])
            let vel = glideDrivenVel[cellIdx * Self.glideDrivenCap + i]
            let tb = glideDrivenBeat[cellIdx * Self.glideDrivenCap + i]
            let onS = sampleOf(musical: tb, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)   // swing-accurate (was a raw linear conversion that dropped the warp — review 2026-08-23)
            guard let outNote = glideOutNote(inNote, bus: bus) else { continue }   // R2: OCT + KEY + FENCE; out of range / DROP → skip this target (keep the current anchor)
            let outN = Int(outNote)
            switch p.glideMode {
            case .bend:
                if gv.anchor < 0 {                                   // ANCHOR: first driver note = note-on + centred bend
                    let slot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: onS, offSample: .max, velocity: vel, out: out, meter: true)
                    gv = GlideVoice(); gv.anchor = Int16(outN); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.lastInput = Int16(outN); gv.rampStart = tb
                    emitBend(cable: cable, ch: ch, value: 8192, atSample: onS, out: out); gv.lastBend14 = 8192
                } else if Int(gv.lastInput) != outN {               // NEW TARGET
                    let semis = outN - Int(gv.anchor)
                    if p.glideReanchor && glideNeedsReanchor(target: outN, anchor: Int(gv.anchor), range: p.glideRange) {   // leap → RE-ANCHOR
                        if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: onS, out: out) }
                        emitBend(cable: cable, ch: ch, value: 8192, atSample: onS, out: out)
                        let slot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: onS, offSample: .max, velocity: vel, out: out, meter: true)
                        gv.anchor = Int16(outN); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.bendFrom = 0; gv.bendTo = 0; gv.rampStart = tb; gv.lastBend14 = 8192
                    } else {                                         // in range → GLIDE (capture the current bend, ramp to the new target; clamp if not re-anchoring)
                        let tt = max(0.0001, p.glideTime)
                        gv.bendFrom = gv.bendFrom + (gv.bendTo - gv.bendFrom) * min(1, p.glideTime > 0 ? (tb - gv.rampStart) / tt : 1)
                        gv.bendTo = p.glideReanchor ? Double(semis) : Double(max(-p.glideRange, min(p.glideRange, semis)))
                        gv.rampStart = tb
                    }
                    gv.lastInput = Int16(outN)
                }
            case .synth:                                            // SYNTH: the synth glides itself — CC65 ON + CC5 time at anchor, then LEGATO transitions
                if gv.anchor < 0 {
                    out?.emit(sampleTime: onS, cable: cable, 0xB0 | ch, 65, 127)
                    out?.emit(sampleTime: onS, cable: cable, 0xB0 | ch, 5, UInt8(glideSynthCCTime(p.glideTime)))
                    let slot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: onS, offSample: .max, velocity: vel, out: out, meter: true)
                    gv = GlideVoice(); gv.anchor = Int16(outN); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.lastInput = Int16(outN)
                } else if Int(gv.lastInput) != outN {
                    let newSlot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: onS, offSample: .max, velocity: vel, out: out, meter: true)
                    if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: onS, out: out) }   // release old AFTER new = legato
                    gv.anchor = Int16(outN); gv.slot = Int16(newSlot); gv.lastInput = Int16(outN)
                }
            case .step:                                             // STEP: a fast chromatic run per transition (emitted after the loop; note-hungry, governed)
                if gv.anchor < 0 {
                    let slot = openVoice(note: outNote, chan: ch, cable: cable, bus: UInt8(bus), onSample: onS, offSample: .max, velocity: vel, out: out, meter: true)
                    gv = GlideVoice(); gv.anchor = Int16(outN); gv.bus = Int8(bus); gv.slot = Int16(slot); gv.lastInput = Int16(outN)
                } else if Int(gv.lastInput) != outN {
                    if gv.slot >= 0 && Int(gv.slot) < voices.count && voices[Int(gv.slot)].active { closeVoice(Int(gv.slot), atSample: onS, out: out) }
                    gv.slot = -1
                    gv.stepFrom = gv.anchor; gv.stepTarget = Int16(outN); gv.stepVel = vel
                    gv.stepTotal = Int16(abs(outN - Int(gv.anchor))); gv.stepsDone = 0; gv.stepRunStart = tb
                    gv.anchor = Int16(outN); gv.lastInput = Int16(outN)
                }
            }
        }
        gv.bus = Int8(bus); gv.mode = p.glideMode
        switch p.glideMode {
        case .bend:
            if gv.anchor >= 0 {                                  // emit the bend ramp across this window (control grid, deduped) — sustains between ticks
                let tt = max(0.0001, p.glideTime)
                var k = Int((beatPos / modCtrlBeats).rounded(.up))
                while Double(k) * modCtrlBeats < bEnd {
                    let b = Double(k) * modCtrlBeats
                    if b >= beatPos {
                        let prog = p.glideTime > 0 ? min(1, (b - gv.rampStart) / tt) : 1
                        let v14 = glideBend14(semitones: gv.bendFrom + (gv.bendTo - gv.bendFrom) * prog, range: p.glideRange)
                        if gv.lastBend14 != Int16(v14) {
                            emitBend(cable: cable, ch: ch, value: v14, atSample: windowStart + Int64(((b - beatPos) / beatsPerSample).rounded()), out: out)
                            gv.lastBend14 = Int16(v14)
                        }
                    }
                    k += 1
                }
            }
        case .synth: break
        case .step:
            emitGlideStepRun(&gv, cable: cable, ch: ch, bus: bus, glideTime: p.glideTime, beatPos: beatPos, bEnd: bEnd, beatsPerSample: beatsPerSample, windowStart: windowStart, out: out)
        }
        glideVoices[cellIdx] = gv
    }

    // MARK: - GENERATORS (user 2026-08-08) — EUCLID · BURST · CASCADE, single-slot tick emitters. Each computes its
    // strike beats for the current column and emits those landing in this window (half-open, so each fires once).
    /// WEAVE (Paul 2026-08-07): the rank-clocked polyrhythm DRIVER. Each held note (ascending rank) ticks on its OWN
    /// clock — `weaveRate(mode, base, rank)` — so one chord becomes an interlocking ensemble (bass slow … top fast).
    /// Modelled on emitGeneratorRow: compose the source at colStart, then window-scan EACH rank's clock from colStart
    /// (RETRIG for free; no shared per-row tick state, so per-rank scans don't collide). SPAN ranks weave; extras join
    /// the top (fastest weaving) clock. As a chain driver each struck note folds downstream via emitDriverNote.
    private func emitWeaveRow(cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int,
                              emits: Bool, pool livePool: NotePool, effColumn: Int, beatPos: Double, windowBeats: Double,
                              windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                              cycleBeats: Double = 0, chainDriver: Int = -1, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard S > 0 else { return }
        let pool = effectivePool(for: cell, live: livePool)   // receiver LATCH: the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)
        let p = machine.a
        let cyc = cycleBeats > 0 ? cycleBeats : Double(Snap.cols) * S
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let colStart = columnStart(mWinStart, S), colEnd = colStart + S
        let hasDownstream = chainDriver >= 0 && chainDriver < cell.procs.count - 1
        if chainDriver > 0 {
            composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: colStart, S: S, cycleBeats: cyc)
            fillSrcFromScratch()
        } else {
            fillSrcFromPool(cell, pool)
        }
        let srcNotes = srcNoteBuf[0..<srcNoteCount]   // view, no alloc — 0-based indices match the old array
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
        // CLOCK (Paul 2026-09-26): WEAVE's per-rank clock is a hand-rolled window scan, not `iterateTicks` — so it
        // gets the SAME treatment built directly into its own loop: the window bounds + this rank's own origin/
        // column-cap all shift into local time ONCE (shared across every rank — none of them depend on rank), the
        // EXISTING search math runs unchanged there, and each found local tick inverts back to real before
        // scheduling. No-op (byte-identical) when this cell isn't a retimed driver.
        let localWinStart = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: mWinStart, S: S, cycleBeats: cyc, originRef: mWinStart)
        let localWinEnd = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: mWinEnd, S: S, cycleBeats: cyc, originRef: mWinStart)
        let localColStart = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: colStart, S: S, cycleBeats: cyc, originRef: mWinStart)
        let localColEnd = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: colEnd, S: S, cycleBeats: cyc, originRef: mWinStart)
        let localOrigin = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: origin, S: S, cycleBeats: cyc, originRef: mWinStart)
        for rank in 0..<count {
            let clockRank = min(rank, span - 1)   // extras join the top clock
            let n = srcNotes[rank].note + transpose
            guard n >= 0 && n <= 127 else { continue }
            let vel = srcNotes[rank].vel
            if p.weaveMode == .euclid {            // each rank plays an interlocking euclidean pattern (bass sparse → top dense)
                let M = max(2, min(16, p.weaveEuclidSteps))
                euclidPatternInto(&euclidBuf, pulses: max(1, min(M, 2 * clockRank + 1)), steps: M, rotation: 0)
                let sub = S / Double(M)
                for stepI in 0..<M where euclidBuf[stepI] {
                    let localTau = localColStart + Double(stepI) * sub
                    let (tau, gate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: localTau, localOff: min(localColStart + S, localTau + sub * gateFrac), S: S, cycleBeats: cyc, originRef: mWinStart)
                    guard tau >= mWinStart && tau < mWinEnd else { continue }
                    emitWeaveStrike(cell: cell, row: r, note: n, vel: vel, tau: tau, off: tau + gate, bm: bm,
                                    emits: emits, hasDownstream: hasDownstream, chainDriver: chainDriver, windowEnd: windowEnd,
                                    beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a, cyc: cyc, out: out, diag: &diag)
                }
            } else {                               // a regular per-rank clock (LADDER/HARMONIC formula, or DRAWN's authored rate)
                let sub = (p.weaveMode == .drawn) ? max(0.03125, p.weaveDrawnBeats[min(clockRank, p.weaveDrawnBeats.count - 1)])
                                                  : weaveRate(mode: p.weaveMode, baseBeats: max(0.03125, p.weaveBaseBeats), rank: clockRank)
                let localScanEnd = capAtCol ? min(localWinEnd, localColEnd) : localWinEnd
                var j = Int(((localWinStart - localOrigin) / sub).rounded(.down)); if j < 0 { j = 0 }
                while true {
                    let localTau = localOrigin + Double(j) * sub
                    if localTau >= localScanEnd { break }
                    j += 1
                    guard localTau >= localWinStart else { continue }
                    let localOff = capAtCol ? min(localColEnd, localTau + sub * gateFrac) : (localTau + sub * gateFrac)
                    let (tau, gate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: localTau, localOff: localOff, S: S, cycleBeats: cyc, originRef: mWinStart)
                    emitWeaveStrike(cell: cell, row: r, note: n, vel: vel, tau: tau, off: tau + gate, bm: bm,
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

    private func emitGeneratorRow(mode: CellMode, cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int,
                                  emits: Bool, pool livePool: NotePool, effColumn: Int, beatPos: Double, windowBeats: Double,
                                  windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                                  cycleBeats: Double = 0, chainDriver: Int = -1, out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: livePool)   // receiver LATCH: the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)
        let p = machine.a
        let cyc = cycleBeats > 0 ? cycleBeats : Double(Snap.cols) * S
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let colStart = columnStart(mWinStart, S)

        // CELL MACHINE: as a chain DRIVER, the source is the composed set of the stages BEFORE the driver; each note
        // FOLDS through the stages AFTER it (emitDriverNote). A single-slot generator (chainDriver < 0) reads the
        // cell's filtered pool directly and emits with emitArtic. `srcNotes` = the raw source notes (transpose added
        // per-strike). Composed once at colStart — the source is stable across the column.
        let hasDownstream = chainDriver >= 0 && chainDriver < cell.procs.count - 1
        // each source note carries its VELOCITY (user 2026-08-09: generators inherit it) — filled into the reused buffer
        if chainDriver > 0 {
            composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: colStart, S: S, cycleBeats: cyc)
            fillSrcFromScratch()
        } else {
            fillSrcFromPool(cell, pool)
        }
        let srcNotes = srcNoteBuf[0..<srcNoteCount]   // view, no alloc — 0-based indices match the old array

        // ONE chord strike at musical beat `tau` (source notes, chop-routed / downstream-folded), gated `gateBeats`.
        // `velScale` is the generator's per-strike envelope level (0…1) RELATIVE to each note's inherited source
        // velocity — so a soft chord bursts soft, a hard one bursts hard (user 2026-08-09).
        // OCTAVE (Paul 2026-10-01, EUCLID's per-lane shift): additive, defaulted 0 — every OTHER call site below
        // (hocket/echo/tutti/etc, none of which author a per-lane octave) simply omits it, byte-identical. Mirrors
        // UTILITY's `utilOctave`/ARP's `arpPick` convention exactly: ×12, add, clamp 0...127 right at emission —
        // not a new convention invented for EUCLID.
        // EUCLIDEOUS (Paul 2026-10-05): `busOverride` lets a PER-LINE EuclidLine.emitterMask replace the cell's
        // own `bm` for this one strike — nil (every existing caller) is byte-identical. Only reaches `chopMask`'s
        // `base:` (not `emitDriverNote`'s separate `bm:` a few lines down) — EUCLID is structurally always the
        // chain tail for Euclideous's one-slot cell (`hasDownstream` is permanently false there), so this is
        // sufficient for that use. Since EuclidLine is shared with the existing, chainable BUILD-page EUCLID
        // processor too, a line with emitterMask SET there would also route independently of the cell's own
        // buses the moment a downstream processor exists — a disclosed, nil-default-safe consequence, not a bug.
        // PER-LANE I/O (Paul 2026-10-08): `srcOverride`, nil for every call site outside Euclideous's own
        // per-lane loop — byte-identical for every other caller (ARP/RIFF/BURST/the lone-driver `.euclid` path
        // elsewhere in the grid). Only the Euclideous per-line HIT/MISS pick calls below pass a real value
        // (that lane's own resolved pool), so a chord can no longer be picked from the wrong lane's notes.
        func strikeChord(tau: Double, velScale: Double, gateBeats: Double, onlyIndex: Int? = nil, octave: Int = 0, explicitNote: Int? = nil, explicitVel: UInt8? = nil, busOverride: UInt8? = nil, srcOverride: ArraySlice<(note: Int, vel: UInt8)>? = nil) {
            let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            let offT = sampleOf(musical: tau + gateBeats, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            // EUCLIDEOUS PAGE REWORK (2026-10-07): a global MAIN OUT master gate, applied AFTER chopMask's
            // own full DEST/CHOP/MUTE-MATRIX routing resolves `tbm` — not pre-masked into `base` — since
            // ALT-routing (`chopBusMask`) and DEST-routing both construct their own bus bits independent of
            // `base`; pre-masking would silently fail to suppress an ALT- or DEST-routed note. `p.mainOutMask`
            // is 0b1111 (all-open) for every non-Euclideous chain, so this is byte-identical everywhere else.
            let tbm = chopMask(cell, m: tau, S: S, base: busOverride ?? bm) & p.mainOutMask
            func strikeOne(_ rawNote: Int, _ rawVel: UInt8) {
                let n = rawNote + transpose + 12 * octave
                guard n >= 0 && n <= 127 else { return }
                let vel = clampVel(Int((Double(max(1, rawVel)) * velScale).rounded()))   // inherited velocity × envelope
                storeArtic(row: r, on: onT, off: offT, note: UInt8(n), beat: tau)
                if !emits { return }
                if hasDownstream {   // fold the post-driver stages onto each generated note (a downstream harmonize/chance/…)
                    emitDriverNote(n, cell: cell, driver: chainDriver, bm: bm, onSample: onT, offSample: offT,
                                   windowEnd: windowEnd, velocity: vel, m: tau, S: S, cycleBeats: cyc, beatsPerSample: beatsPerSample, pass: diag.pass, out: out, diag: &diag)
                } else if tbm != 0 {
                    emitArtic(note: UInt8(n), busMask: tbm, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
                }
            }
            // SEQUENTIAL SOURCES (Paul 2026-10-02): a RIFF/ARP-sourced pick resolves to an EXPLICIT note value that
            // frequently isn't present in srcNotes at all (RIFF's FOLD wrap and per-step octave lane, ARP's own
            // octave laps, both routinely land outside the composed pool's own pitches) — so it can't flow through
            // the onlyIndex/srcNotes-index path below. `strikeOne` factors the shared store+emit tail so both paths
            // (an explicit note, or a srcNotes-indexed pick) run through identical transpose/octave/range/velocity/
            // downstream-fold-or-direct-emit logic — not a second, divergent copy of it.
            if let en = explicitNote { strikeOne(en, explicitVel ?? 100); return }
            let notes = srcOverride ?? srcNotes
            for (k, sn) in notes.enumerated() {
                if let only = onlyIndex, k != only { continue }
                strikeOne(sn.note, sn.vel)
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
            // EUCLID LINES (2026-09-29 fixed-4-row redesign): ALWAYS exactly 4 lines — SnapshotBuilder's
            // `euclidLinesForEditing()` guarantees this (an untouched machine's row 0 derives from the flat
            // single-euclid fields, rows 1-3 silent, so a pre-redesign doc plays byte-identical). TARGET+PICK
            // merged into `noteSelResolved` (a specific rank N1…N8, or an aggregate ALL/LOW/HIGH/BOT2/TOP2/CYCLE/
            // RANDOM). DIRECTION (`reverseResolved`) mirrors the pattern by flipping the READ INDEX into the
            // already-rotated buffer, not rebuilding it — rotate-then-reverse ≠ reverse-then-rotate in general
            // (they differ by a shift of 2×rotate mod n), so this is a deliberate, tested composition order, not
            // an arbitrary one (see `testEuclidReverseFlipsReadIndexNotRebuiltBuffer`).
            let srcCount = srcNotes.count
            // PER-LANE I/O (Paul 2026-10-08, the new I/O tab + CHORDS button): fill each lane's own pool BEFORE
            // the readiness check below (which also needs the per-lane count now) — Euclideous's own reserved
            // row only. Every other `.euclid` cell anywhere else in the grid keeps reading the single shared
            // `srcNotes`/`srcCount` this file always has, via `laneCount`/`laneNotes`'s own fallback branch —
            // byte-identical to before this feature, since `isEuclideousRow` is false there. Three sources,
            // mode-dispatched per lane: MIDI reads the live pool by chanMask (`fillLaneSrcFromPool`, unchanged
            // mechanism); CHORDS reads Euclideous's own on-page chord generator (`chordSeqNotes`, the SAME pure
            // function the regular CHORDS processor and the chord door both already share — resolved ONCE per
            // cell-render here, not per-tick, matching every other pool-fill's own "stable across the column"
            // convention); KEY stays silent (§4.4 unresolved). `laneUsesLegacyPool[i]` is set ONLY for a
            // MIDI-mode lane when `doc.receivers` was nil/empty at build time (SnapshotBuilder's guard skips
            // resolving `laneSrcChanMasks` entirely then) — a pre-existing "no receivers configured at all"
            // legacy shape the cell's own OMNI fallback (`sc.inputChanMask = 0xFFFF`) already handles via the
            // shared `srcNotes`/`srcCount`; without this, an empty `laneSrcChanMasks` would silently read as
            // "every MIDI lane's chanMask is 0" (silent) instead of falling back to that legacy OMNI pool —
            // caught by 2 existing reset-span RouterTests regressing (neither sets `st.receivers` at all), not
            // by inspection. CHORDS/KEY lanes never fall back — they have no "legacy" shape to honour.
            let isEuclideousRow = r == Snap.euclideousRow
            let hasLaneChanMasks = !p.laneSrcChanMasks.isEmpty
            var laneUsesLegacyPool = [Bool](repeating: false, count: 4)
            if isEuclideousRow {
                let chordNotes = chordSeqNotes(beat: mWinStart, p, keyRoot: p.euclideousChordKeyRoot, keyTones: p.euclideousChordKeyTones, followNote: nil)
                // KEY MODE (Paul 2026-10-09, 2nd report: "key does nothing" — a real, previously-disclosed gap,
                // not a regression: §4.4 of the original page-rework spec explicitly left "how KEY-mode notes
                // map to a pool" unresolved, and it was never picked up after. Built now, directly from the
                // SAME page-level KEY picker CHORDS already reads (`euclideousChordKeyRoot`/`KeyTones` — shared
                // fields, see Snapshot.swift's own doc comment on them) — a lane set to KEY plays the notes of
                // that scale directly, independent of any live or generated pool, the simplest reading of "play
                // in this key" for a mode with no external source at all. Mirrors `scaleNotes`'s own exact
                // formula (Derivations.swift — "every note of `type` rooted at `root`, realized ascending across
                // `octaves` octaves from `baseOct`") rather than calling it directly, since SnapParams only
                // carries the already-resolved INTERVAL array (`euclideousChordKeyTones`), not the `ScaleType`
                // enum `scaleNotes` itself takes. baseOct 3 / octaves 2 matches `ScalePool`'s own standing
                // default (home octave 3, a 2-octave span) — the established convention for "a scale as a pool"
                // everywhere else in this codebase, not a new number invented for this one case.
                var keyScaleNotes: [Int] = []
                do {
                    let root = ((p.euclideousChordKeyRoot % 12) + 12) % 12
                    let base = 3 * 12 + 12   // baseOct 3 → MIDI 48 (C3), the C-1 convention `scaleNotes` itself uses
                    for o in 0..<2 {
                        for iv in p.euclideousChordKeyTones {
                            let n = base + root + o * 12 + iv
                            if n >= 0 && n <= 127 { keyScaleNotes.append(n) }
                        }
                    }
                }
                for i in 0..<4 {
                    let srcMode = i < p.euclidLines.count ? p.euclidLines[i].sourceModeResolved : .midi
                    switch srcMode {
                    case .chords:
                        laneSrcCount[i] = min(laneSrcBuf[i].count, chordNotes.count)
                        for k in 0..<laneSrcCount[i] { laneSrcBuf[i][k] = (chordNotes[k], 100) }   // 100 = the standing "no live velocity to inherit" default (matches strikeChord's own explicitVel fallback)
                    case .key:
                        laneSrcCount[i] = min(laneSrcBuf[i].count, keyScaleNotes.count)
                        for k in 0..<laneSrcCount[i] { laneSrcBuf[i][k] = (keyScaleNotes[k], 100) }   // same "no live velocity to inherit" default as CHORDS above
                    case .midi:
                        if hasLaneChanMasks {
                            // LITERALLY LIVE, OMNI (Paul 2026-10-09, two rounds): `pool` here is
                            // `emitGeneratorRow`'s own SHADOWED local (`effectivePool(for: cell, live: livePool)`,
                            // set at this function's top) — it applies the generic self-arm/latch substitution
                            // every regular grid cell gets, with no awareness that THIS read is one of three
                            // explicit, mutually-exclusive choices (MIDI IN vs KEY vs CHORDS) where "MIDI IN"
                            // specifically promises live input and nothing else — a self-arming door on whichever
                            // receiver this cell nominally resolves to would silently leak its generated content
                            // through here (round 1's bug: "plays something even with nothing plumbed in").
                            // Reading `livePool` (this function's own un-substituted parameter, still in scope)
                            // instead of `pool` fixes that leak — but `laneSrcChanMasks` ALSO used to key this
                            // read to one specific hardcoded receiver's channel mask (round 2's bug: "midi in
                            // does nothing" — an unverified guess at which receiver index, see
                            // SnapshotBuilder.swift's own note on this, that never matched whatever receiver
                            // Paul actually plugs a controller into). `laneSrcChanMasks[i]` is now always 0xFFFF
                            // for a MIDI-mode lane (SnapshotBuilder.swift), so this reads EVERY live note on
                            // EVERY channel — genuinely "any live input, no receiver dependency at all." For
                            // every other `.euclid` cell in the grid (where effectivePool's substitution is the
                            // correct, desired behaviour), this call is unreached entirely (gated by
                            // `isEuclideousRow` above), so nothing there changes.
                            fillLaneSrcFromPool(livePool, lane: i, chanMask: i < p.laneSrcChanMasks.count ? p.laneSrcChanMasks[i] : 0)
                        } else {
                            laneUsesLegacyPool[i] = true
                        }
                    }
                }
            }
            func laneCount(_ li: Int) -> Int { (isEuclideousRow && !laneUsesLegacyPool[li]) ? laneSrcCount[li] : srcCount }
            func laneNotes(_ li: Int) -> ArraySlice<(note: Int, vel: UInt8)> { (isEuclideousRow && !laneUsesLegacyPool[li]) ? laneSrcBuf[li][0..<laneSrcCount[li]] : srcNotes }
            // SEQUENTIAL SOURCES (Paul 2026-10-02): when the slot immediately before this EUCLID (chainDriver, the
            // index of EUCLID's own slot since emitGeneratorRow only dispatches here for the chain's driver) is
            // exactly RIFF or ARP, and NOT bypassed, a line set to the matching noteSel steps through that
            // predecessor's own authored sequence instead of picking from the held chord — see runEuclidLine's hit
            // closure below. Bypassed-predecessor excluded to match every other adjacency/scan helper in this file
            // (chainDriverIndex, composeChainSet's fold loop, the downstream*Index helpers all treat a bypassed
            // slot as "not really there") — testChainBypassedHeadArpsSourceOnly already locks in the analogous case.
            let predIdx = chainDriver - 1
            let predType: ProcessorType? = (chainDriver >= 1 && !cell.slotBypass[predIdx]) ? cell.procs[predIdx].type : nil
            // EUCLID BEACON READINESS (Paul 2026-10-05): computed once per cell per render (not per tick — none of
            // these conditions are tick-dependent), written into `euclidLineReady`, read by GridUI's beacon via
            // `euclidLineReadyAt`. Mirrors the EXACT guards `runEuclidLine`'s hit/miss closures apply below, not an
            // approximation: velocity>0 · for .riff/.arp, the predecessor TYPE matches AND has a genuine target
            // (RIFF: at least one non-rest authored step, confirmed via the same bounded scan `runEuclidLine` uses,
            // AND a non-empty pool feeding riff's own slot — `riffResolve` only ever fails for rank<1 or an empty
            // pool, per its own doc comment, so "pool non-empty" is exactly sufficient, not an approximation; ARP:
            // a non-empty pool feeding arp's own slot — `arpPick`/`arpPickSource` only ever return note<0 for an
            // empty [chan/cable-filtered] pool, per their own doc comments) · for every other pick (ranked N1…N8 or
            // aggregate ALL/LOW/HIGH/BOT2/TOP2/CYCLE/RANDOM), the TRUE upstream `srcCount` already composed for
            // this cell's chain — not the door's raw held notes (the beacon's own disclosed gap before this fix).
            // HONEST LIMIT, same posture as `riffDrunkPosAt`'s own doc comment: a CHANCE-style probabilistic stage
            // between the door and this slot is read at THIS render's current beat (mWinStart), not the exact
            // future tick the beacon is asking about — inherent to a probabilistic stage, not a shortcut taken.
            if currentCellIndex >= 0 && currentCellIndex < euclidLineReady.count {
                var ready: UInt8 = 0
                for (li, L) in p.euclidLines.enumerated() where li < 4 {
                    if L.velocityResolved > 0 {
                        let sel = L.noteSelResolved
                        var hitOK = false
                        if sel == .riff {
                            if predType == .riff {
                                let rp = cell.procs[predIdx]
                                let riffSteps = max(1, min(32, rp.riffSteps))
                                var nonRest = 0
                                for i in 0..<riffSteps {
                                    let isRest = rp.riffPoly ? ((i < rp.riffMask.count ? rp.riffMask[i] : 0) == 0)
                                                              : ((i < rp.riffRanks.count ? rp.riffRanks[i] : 0) < 1)
                                    if !isRest { nonRest += 1 }
                                }
                                if nonRest > 0 {
                                    composeChainSet(cell: cell, pool: pool, upto: predIdx - 1, m: mWinStart, S: S, cycleBeats: cyc)
                                    hitOK = chainScratch.srcCount(filter: 0) > 0
                                }
                            }
                        } else if sel == .arp {
                            if predType == .arp {
                                composeChainSet(cell: cell, pool: pool, upto: predIdx - 1, m: mWinStart, S: S, cycleBeats: cyc)
                                hitOK = chainScratch.srcCount(filter: 0) > 0
                            }
                        } else if let rank = sel.specificRank {
                            hitOK = laneCount(li) >= rank
                        } else {
                            hitOK = laneCount(li) > 0
                        }
                        if hitOK { ready |= UInt8(1 << (li * 2)) }
                    }
                    if let missSel = L.missNoteSel, missSel != .riff, missSel != .arp, L.missVelocityResolved > 0 {
                        let missOK = missSel.specificRank.map { laneCount(li) >= $0 } ?? (laneCount(li) > 0)
                        if missOK { ready |= UInt8(1 << (li * 2 + 1)) }
                    }
                }
                euclidLineReady[currentCellIndex] = ready
            }
            // one line = one euclid pass; reuses `euclidBuf` (filled + consumed synchronously before the next line).
            // DIRECTION (Paul 2026-10-01, 3-way redesign): `dir` replaces the old binary `reverse` — FWD/BKW read the
            // n-length buffer directly/mirrored (unchanged math, renamed); PING-PONG reuses RIFF's own `.pingpong`
            // shape (period 2n, each endpoint sounding on two consecutive ticks) via `euclidCycleLen`/`euclidReadIndex`.
            // GATE/OCTAVE are new per-lane fields threaded straight to `strikeChord`.
            // Resolves an aggregate/rank note-select against a walk ordinal into (pickIndex, pickRange) — shared
            // by the HIT and MISS paths below (Paul 2026-10-02 hit/miss split) so the ALL/LOW/HIGH/BOT2/TOP2/
            // CYCLE/RANDOM switch exists exactly once; RIFF/ARP are intentionally NOT handled here (they resolve
            // an explicit note via a separate mechanism entirely, and MISS never offers them — see the guard at
            // the MISS call site). A pure extraction of the pre-existing inline logic, not a behaviour change.
            // PER-LANE I/O (Paul 2026-10-08): `count` is now an explicit parameter (was the outer, cell-shared
            // `srcCount`) — each call site passes `laneCount(lineIndex)`, so this resolves against whichever
            // pool THAT lane actually reads (its own MIDI/KEY/CHORDS choice), not the cell's shared one.
            func resolveEuclidPick(_ sel: EuclidNoteSel, ord: Int64, count: Int) -> (index: Int?, range: (lo: Int, hi: Int)?) {
                if let rank = sel.specificRank { return (rank - 1, nil) }
                switch sel {
                case .all: return (nil, nil)
                case .low: return (0, nil)
                case .high: return (count - 1, nil)
                case .bottom2: return count > 0 ? (nil, (0, min(1, count - 1))) : (nil, nil)
                case .top2: return count > 0 ? (nil, (max(0, count - 2), count - 1)) : (nil, nil)
                case .cycle, .random:
                    guard count > 0 else { return (nil, nil) }
                    let idx = sel == .cycle
                        ? Int(((ord % Int64(count)) + Int64(count)) % Int64(count))
                        : Int(splitmix64Mix(UInt64(bitPattern: ord) &+ 0x9E3779B97F4A7C15) % UInt64(count))
                    return (idx, nil)
                default: return (nil, nil)   // N1…N8 already resolved via specificRank above; .riff/.arp never reach here
                }
            }
            // ABSOLUTE VELOCITY (Paul 2026-10-09, XY pad redesign): `resolveEuclidPick` answers either a single
            // index, a closed range (BOT2/TOP2), or neither (ALL) — the `onlyIndex:`/`strikeChord` path reads an
            // INHERITED velocity per note, which is exactly right for a SCALE multiplier but wrong once a lane's
            // own VELOCITY pad is a genuine absolute override: there's no single inherited value for `.all` (no
            // index at all) to apply an absolute override "instead of." Normalizing to a concrete, always-
            // populated index list lets every pick shape strike via `explicitNote:` uniformly (one `strikeChord`
            // call per note, each carrying the SAME absolute velocity) instead of forking on which pick shape it is.
            func resolvedPickIndices(_ pickIndex: Int?, _ pickRange: (lo: Int, hi: Int)?, count: Int) -> [Int] {
                if let range = pickRange { return Array(range.lo...range.hi) }
                if let idx = pickIndex { return [idx] }
                return Array(0..<count)
            }
            func runEuclidLine(lineIndex: Int, pulses kIn: Int, steps nIn: Int, rotate: Int, dir: EuclidDir, noteSel: EuclidNoteSel, gate: Double, octave: Int, velocity: Double, velocityAbsolute: Int, rate: Double, busOverride: UInt8?,
                                missNoteSel: EuclidNoteSel? = nil, missGate: Double = 0.9, missOctave: Int = 0, missVelocity: Double = 1.0,
                                useRiff: Bool = false, riffRotate: Int = 0, riffOctave: Int = 0,
                                riffDir: RiffDir = .forward, riffDirSeed: Int = 0, riffDirBias: Double = 0, tilt: Double = 0,
                                riffLock: Bool = false, riffInvert: Bool = false, riffOnRest: EuclidRiffOnRest = .skip) {
                let n = max(2, min(16, nIn))
                let k = p.euclidPulsesFromPool ? srcCount : max(0, min(n, kIn))   // POOL: K = held-note count
                euclidPatternInto(&euclidBuf, pulses: k, steps: n, rotation: rotate)
                // TILT (Paul 2026-10-08): a single insertion point, AFTER rotation — every downstream read of
                // `euclidBuf` (the hit/rest test, the CYCLE/RANDOM ordinal walk, MISS's complement) picks up the
                // tilted shape for free, with zero other changes needed anywhere in this function.
                if tilt != 0 { euclidTiltPattern(&euclidBuf, pulses: k, steps: n, tilt: tilt) }
                // RATE×ladder (Paul 2026-08-27): GRID = the fixed step grain (density lives here + K/N); SPAN re-syncs the
                // pattern every N columns (FREE = 0 = free-run). Rate and loop decoupled — an odd N against an aligning
                // span drifts then snaps back. (Was the WIDTH model `sub = spanWidth/n`, where SPAN just scaled the speed.)
                // EUCLIDEOUS (Paul 2026-10-05): `rate` is now a PASSED-IN parameter (the caller resolves
                // L.rate?.beats ?? p.euclidRateBeats) instead of this closure directly capturing the machine-wide
                // field — lets each of Euclideous's 4 lines run its own rate; every existing non-Euclideous call
                // resolves to the exact same machine-wide value as before, byte-identical.
                let sub = rate
                // RESET SPAN (Paul 2026-10-08, §2.2): Euclideous's own GLOBAL reset-span control — resolved
                // directly from `doc.euclideousResetSpanBarsResolved` into `p.euclideousResetSpanBars` (gated
                // to Euclideous's own row in SnapshotBuilder, 0 for every other `.euclid` cell) — OVERRIDES the
                // regular machine-wide `euclidSpanN` ladder when set, rather than composing with it: Euclideous
                // never exposes `euclidSpanN` on its own page, so the two can never both be meaningfully set at
                // once for the same line. `cyc` (this render's own "one bar" beat-length, already computed
                // above) is multiplied directly by the literal bar count — not routed through `spanLadderBeats`'s
                // own ladder, which tops out at 8 bars (its n=64 case) and has no slot for 16.
                let spanBeats = p.euclideousResetSpanBars > 0 ? Double(p.euclideousResetSpanBars) * cyc
                    : (p.euclidSpanN > 0 ? spanLadderBeats(p.euclidSpanN, S: S, row: cyc) : 0)
                // cycleLen (2n under PING-PONG, else n): looping the hit-count over the FULL cycle naturally
                // double-counts a ping-pong's repeated endpoints the same way the real read-sequence does — no
                // ×2 special-case needed (every buffer position 0..<n is visited exactly twice per 2n-tick lap).
                let cycleLen = euclidCycleLen(dir, n: n)
                // factored once (Paul 2026-10-02, hit/miss split) — the SAME "is step s a hit" test the original
                // cycleHits/hitsUpTo loops already repeated inline; the new MISS path below needs a third copy,
                // so this is a pure de-duplication, not a behaviour change.
                func isHitAt(_ s: Int) -> Bool { euclidBuf[euclidReadIndex(s, n: n, dir: dir)] }
                var cycleHits = 0; for s in 0..<cycleLen where isHitAt(s) { cycleHits += 1 }
                let effHits = Int64(max(1, cycleHits))
                iterateTicks(row: r, effColumn: effColumn, sub: sub, gateFraction: 0.9,
                             beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                             beatsPerSample: beatsPerSample, S: S, a: a, columns: max(1, Int((cyc / S).rounded())),
                             clockCell: chainDriver >= 0 ? cell : nil, clockFrom: 0, clockTo: chainDriver, cycleBeats: cyc,
                             lineIndex: lineIndex) { _, mTickBeat, _, _ in
                    // SPAN RE-ANCHOR: FREE (spanBeats 0) = the global grid; else re-sync to step 0 every N cols. Pure/
                    // replay-exact. Kept as exact Int64 arithmetic, not routed through the continuous `euclidPhase`
                    // used by the GridUI comet-bar — a discrete hit/rest decision needs exact integer ticks, a
                    // comet's visual position tolerates float imprecision invisibly; the two shouldn't share a code
                    // path just because they share a CONCEPT (the same rate/span/anchor reading).
                    let phaseBeat = spanBeats > 0 ? (mTickBeat - columnStart(mTickBeat, spanBeats)) : mTickBeat
                    let localT = Int64((phaseBeat / sub).rounded(.down))
                    let raw = Int(((localT % Int64(cycleLen)) + Int64(cycleLen)) % Int64(cycleLen))
                    let ri = euclidReadIndex(raw, n: n, dir: dir)
                    let isHit = euclidBuf[ri]
                    let cy = (localT - Int64(raw)) / Int64(cycleLen)   // floored cycle within the span (localT = cy·cycleLen + raw) — shared by both the HIT and MISS ordinals below
                    // NOTE VIEW (Paul 2026-10-10 ferry) — two small helpers shared by all 4 push sites below.
                    // `finalPitch` replicates (not reuses — `strikeChord`'s `strikeOne` is a widely-shared
                    // closure, not Euclideous-specific, so threading a side-channel through it would be the
                    // wrong place for this) the exact `rawNote + transpose + 12*octave` arithmetic + the
                    // 0...127 guard `strikeOne` applies — so a note that would be silently DROPPED there is
                    // never pushed for display either (§5.3: "must match what is actually sent"). `nvTiming`
                    // converts a tick's MUSICAL beat + a real-beat-domain gate length into the REAL onset the
                    // UI's continuous `EuclidLiveClock`-style extrapolation runs on — via `realOf` on both the
                    // onset AND the (onset+gate) endpoint separately, since swing warp is piecewise-linear,
                    // not affine, across a swing-pair boundary (so the duration can't just be passed through
                    // unconverted).
                    func finalPitch(_ raw: Int, oct: Int) -> UInt8? {
                        let v = raw + transpose + 12 * oct
                        return (v >= 0 && v <= 127) ? UInt8(v) : nil
                    }
                    // `tbm` (the SAME formula `strikeChord` computes internally, Router.swift ~3896) is the
                    // actually-resolved bus mask after MUTE MATRIX/DEST/CHOP/MAIN OUT — `strikeChord` still
                    // runs `storeArtic` when this is 0, but SKIPS `emitArtic` entirely, i.e. nothing is
                    // actually sent. Computed ONCE per tick (not per push site) and reused to gate every
                    // push below — without this, a muted/un-routed lane would still show a note in the box
                    // that was never really heard, a direct violation of §5.3. Safe to call a second time:
                    // `strikeChord` already calls this identically once per note it strikes within the SAME
                    // tick (same `m: mTickBeat`), so this isn't a new category of cost.
                    //
                    // `isEuclideousRow` (already in scope, computed once per cell above) is EQUALLY load-
                    // bearing here, caught before any test was written, not after: `runEuclidLine` is the
                    // SAME shared function every ordinary, non-Euclideous `.euclid` cell anywhere else in
                    // the 8×8 grid calls too (confirmed — `p.euclidLines` is always populated, even for a
                    // plain single-EUCLID cell, so `lineIndex` 0...3 is NOT unique to Euclideous's own 4
                    // lanes). Without this guard, an ordinary EUCLID processor on any other row would also
                    // write into this SAME 4-slot queue, corrupting Euclideous's own NOTE VIEW with
                    // whichever unrelated cell happened to strike most recently.
                    let nvSent = isEuclideousRow && chopMask(cell, m: mTickBeat, S: S, base: busOverride ?? bm) & p.mainOutMask != 0
                    func nvTiming(_ gateBeatsReal: Double) -> (onset: Double, duration: Double) {
                        let onsetReal = realOf(mTickBeat, stepBeats: S, a: a)
                        let offReal = realOf(mTickBeat + gateBeatsReal, stepBeats: S, a: a)
                        return (onsetReal, offReal - onsetReal)
                    }
                    if isHit {
                        // VELOCITY 0 = EFFECTIVELY OFF (Paul 2026-10-03: "investigate if the lane is effectively
                        // off with zero velocity") — confirmed by testing, not assumed: strikeChord's own
                        // clampVel floors EVERY note to MIDI 1...127 (the inherited-velocity-safety floor, not
                        // meant for this), so a line scaled to 0 was still striking audibly at velocity 1, never
                        // actually silent. Skip the strike entirely instead — this is what "zero velocity" means
                        // to a user reading the control. Checked BEFORE any of the (possibly expensive) RIFF/ARP/
                        // pool resolution below, not just at the final strikeChord call.
                        guard velocity > 0 else { return }
                        // ord (Paul 2026-09-29 v1b, widened 2026-10-02 for the RIFF/ARP sources below; DIE REMOVED
                        // 2026-10-02 "drop it, please" — a plain, unsalted ordinal): a monotonic, STATELESS "which
                        // hit number is this" — cycle count × this line's own hit density + the within-cycle hit
                        // rank. Hoisted above the pick switch (was computed only inside .cycle/.random) since
                        // .riff/.arp consume it too.
                        var hitsUpTo = 0; for s in 0...raw where isHitAt(s) { hitsUpTo += 1 }
                        let ord = cy * effHits + Int64(hitsUpTo - 1)
                        // EUCLIDEOUS RIFF ADVANCE (Paul 2026-10-06): "each hit will progress riff by 1 step" —
                        // REPLACES noteSel/octave entirely when on (checked BEFORE the .riff/.arp sequential-source
                        // branch just below, not layered after it, so this wins regardless of whatever noteSel
                        // happens to be stored underneath — Paul's own ruling, not a guess). For 5 of 6 directions
                        // this needs zero new memory: `ord` (just computed above) IS "which hit number is this,"
                        // stateless — feeding it straight into `riffStepAt` gives "which step plays on this hit"
                        // with no accumulated state at all. Only DRUNK is genuinely path-dependent (see
                        // `euclideousRiffDrunkStep`'s own declaration for why). `riffRotate`/`riffOctave` are this
                        // LANE's own independent offset into the one shared pattern (Paul: "independent cursor per
                        // lane") — rotate matches `euclidPatternInto`'s own `(i + rot) % n` read-index convention
                        // exactly (see `riffRotateStep`). OCTAVE REPLACES this line's own `octave` rather than
                        // stacking with it (passed 0 below) — the gesture pad that used to drive `octave` now
                        // drives `riffOctave` exclusively, so consulting the old frozen value too would silently
                        // reintroduce an offset the user can no longer see or edit.
                        if useRiff {
                            // DIRECTION IS PER-LANE (Paul 2026-10-07): riffDir/riffDirSeed/riffDirBias now come from
                            // THIS line (the fn params above), not the shared `p.euclideousRiff` — only the pattern
                            // CONTENT (steps/ranks) is shared; each lane walks it its own way.
                            let rp = p.euclideousRiff
                            let riffN = rp.stepsResolved
                            // PER-LANE SOURCE (Paul 2026-10-09, ferry §2.4 — supersedes "follows lane 1"):
                            // each lane resolves the shared riff SHAPE against ITS OWN per-lane pool
                            // (`laneNotes(lineIndex)`/`laneCount(lineIndex)` — the exact same per-lane buffer
                            // that lane's own MIDI IN/KEY/CHORDS I/O-tab choice already fills, "whatever
                            // source THIS lane is on," not lane 0's) — so two lanes walking the identical
                            // riff shape with different inputs now genuinely play different notes.
                            let thisLaneCount = laneCount(lineIndex)
                            guard thisLaneCount > 0 else { return }
                            let notes = laneNotes(lineIndex)
                            let seed = UInt64(bitPattern: Int64(riffDirSeed))
                            let ranks = rp.ranks ?? []   // SnapshotBuilder always resolves this to a full, padded array (main thread) before Router ever sees it — `?? []` is a type-safety unwrap here, not a real fallback allocation

                            // FREE / LOCK (Paul 2026-10-09 ferry, "three new per-lane riff options"): LOCK
                            // re-anchors the riff's own position to its start at the FIRST hit of every lap of
                            // THIS LANE's own Euclid pattern. `hitsUpTo` (computed just above, for `ord`
                            // itself) is ALREADY "how many hits from position 0 up to this one, scanned fresh
                            // within ONE lap's pattern" by construction (the scan is always `0...raw`, and
                            // `raw` is always < cycleLen) — so `hitsUpTo - 1` IS exactly "position within the
                            // CURRENT lap," genuinely stateless, needing no new bookkeeping for 5 of 6
                            // directions. Substituting it for the full continuous `ord` is the WHOLE mechanism
                            // for FWD/REV/PEND/PING — RAND gets "reseed every restart" for free too, since
                            // `riffStepAt(.random, raw: 0, seed:)` with the SAME seed always hashes to the same
                            // step. Only DRUNK needs an explicit nudge (a walk's position depends on its own
                            // history, not just "what time is it") — `euclideousRiffDrunkStep`'s new
                            // `cycleReset` flag, fired exactly on `hitsUpTo == 1`, hard-resets it, the SAME
                            // "fresh start" treatment the existing reset-span boundary already gets.
                            let locked = riffLock
                            let riffOrd = locked ? Int64(hitsUpTo - 1) : ord
                            // RESET SPAN (Paul 2026-10-08): "the global reset span still applies on top of
                            // both modes" — unchanged, still independently re-anchors via spanStart below;
                            // LOCK and reset-span are two separate re-anchor mechanisms layered together, not
                            // one replacing the other (LOCK acts on the HIT-ordinal fed to the riff lookup;
                            // reset-span already acts further upstream, on the Euclid pattern's own phase).
                            let spanStart = spanBeats > 0 ? columnStart(mTickBeat, spanBeats) : Double.nan
                            let stepIdx = riffDir == .drunk
                                ? euclideousRiffDrunkStep(lane: lineIndex, ord: riffOrd, steps: riffN, bias: riffDirBias, seed: seed, spanStart: spanStart, cycleReset: locked && hitsUpTo == 1)
                                : riffStepAt(riffDir, raw: Int(riffOrd), steps: riffN, seed: seed)
                            let rotIdx = riffRotateStep(stepIdx, by: riffRotate, steps: riffN)
                            euclideousRiffStep[lineIndex] = rotIdx   // the cursor updates even on a rest, so the UI tracks real motion through the whole pattern

                            // INVERT (Paul 2026-10-09 ferry): mirrors the rank BEFORE it's resolved against
                            // this lane's own source — "rank r plays as rank (9-r)... rests stay rests" — so
                            // it works identically regardless of source (MIDI/KEY/CHORDS all just feed
                            // `thisLaneCount`/`notes` the same way either side of this transform). OCT
                            // (`riffOctave`) is applied AFTER, inside `riffResolve`'s own `oct:` param below —
                            // already the natural ordering; invert never touches it.
                            let rawRank = rotIdx < ranks.count ? ranks[rotIdx] : 0
                            let rank = (riffInvert && rawRank >= 1) ? (9 - rawRank) : rawRank

                            // TIE LOOKAHEAD (Paul 2026-10-09 ferry, ON REST = TIE): mirrors the regular chain
                            // RIFF processor's own `tieRun` loop (`emitRiffRow`) exactly in spirit, walking
                            // HITS instead of fixed-rate ticks, since Euclideous's riff only advances on a hit
                            // of THIS lane's own pattern — hits land at irregular beat spacing (a genuine K/N
                            // Euclidean rhythm), so the extension is measured in real pattern-step distance to
                            // the hit that finally breaks the chain, not a fixed per-step duration.
                            //
                            // A LOCK cycle boundary is ALWAYS a hard stop for the chain, for every direction —
                            // not just DRUNK, and not merely because DRUNK's own peek can't safely simulate
                            // across a reset. LOCK's whole promise is "the same notes fall on the same beats
                            // every cycle" — letting a tie bleed across that boundary would make the FIRST hit
                            // of SOME cycles silently inherit a held note instead of genuinely landing on its
                            // own reproducible strike, breaking that promise for whichever cycles happened to
                            // end on a tied rest. Reasoned through, not asked (ferry §6 only raised a LOCK-
                            // cycle question for PING specifically) — stopping at the boundary is the one
                            // reading consistent with LOCK's own stated guarantee, for every direction alike.
                            //
                            // Bounded, allocation-free: at most `riffN` consecutive hits folded in, and at
                            // most 4 full laps of pattern-steps scanned looking for them (a sparse K=1 pattern
                            // can space hits far apart in step terms) — a safety cap, not expected to bind in
                            // practice.
                            func riffTieExtensionBeats(startStepIdx: Int, startOrd: Int64) -> Double {
                                guard riffOnRest == .tie else { return 0 }
                                var hitsAhead = 0
                                var lastConsumedT = localT
                                var t = localT
                                var stepsScanned = 0
                                let stepScanCap = cycleLen * 4
                                while hitsAhead < riffN && stepsScanned < stepScanCap {
                                    t += 1; stepsScanned += 1
                                    let fRaw = Int(((t % Int64(cycleLen)) + Int64(cycleLen)) % Int64(cycleLen))
                                    guard isHitAt(fRaw) else { continue }
                                    var fHitsUpTo = 0; for s in 0...fRaw where isHitAt(s) { fHitsUpTo += 1 }
                                    if locked && fHitsUpTo == 1 { break }   // a locked lane's own cycle restart always breaks the chain
                                    hitsAhead += 1
                                    let fCy = (t - Int64(fRaw)) / Int64(cycleLen)
                                    let fOrd = locked ? Int64(fHitsUpTo - 1) : (fCy * effHits + Int64(fHitsUpTo - 1))
                                    let fStepIdx = riffDir == .drunk
                                        ? riffDrunkPeek(fromPos: startStepIdx, tick: startOrd, aheadBy: hitsAhead, steps: riffN, bias: riffDirBias, seed: seed)
                                        : riffStepAt(riffDir, raw: Int(fOrd), steps: riffN, seed: seed)
                                    let fRotIdx = riffRotateStep(fStepIdx, by: riffRotate, steps: riffN)
                                    let fRank = fRotIdx < ranks.count ? ranks[fRotIdx] : 0
                                    guard fRank < 1 else { break }   // a real note breaks the chain
                                    lastConsumedT = t
                                }
                                return Double(lastConsumedT - localT) * sub
                            }

                            // ON REST (Paul 2026-10-09 ferry): a rank of 0 is a rest, in both the shared
                            // pattern's own terms and (per the spec) after inversion. SKIP = today's
                            // behaviour, unchanged. FILL = strike this lane's own NOTE/OCT pick as if riff
                            // were off — §6 OPEN, answered per the ferry's own instruction ("use the last-set
                            // NOTE choice for now"): `noteSel`/`octave` are this function's own un-riff-
                            // overridden parameters, already holding whatever was last set (frozen, not
                            // editable, while the pad shows RIFF SHIFT/OCT instead — exactly the ferry's own
                            // description of the situation). TIE = no strike here; the PRECEDING real/FILL
                            // hit's own lookahead above already extended ITS gate to cover this step, if one
                            // exists — if this is genuinely the first hit ever (nothing preceding), that's
                            // indistinguishable from SKIP, which is exactly the spec's own stated fallback
                            // ("if no note from this lane is sounding, behave as SKIP") — achieved for free,
                            // no separate "is a note sounding" tracking needed, mirroring how the regular
                            // chain RIFF processor's own TIE steps already work (a tie step is ALWAYS a no-op
                            // at its own position, including the very first one).
                            if rank < 1 {
                                switch riffOnRest {
                                case .skip:
                                    // NOTE VIEW (ferry §4.5): "show a grey '—' for one step's duration, then
                                    // return to the previous note at 40%" — a rest-flash event, duration =
                                    // ONE STEP (`sub`, this lane's own rate), not the full gate — nothing is
                                    // actually struck here, so there's no gate length to borrow. Gated on
                                    // `nvSent` too — a muted/un-routed lane shows nothing at all, not even
                                    // a rest flash, since §5.3 scopes this to what's actually sent.
                                    if nvSent {
                                        let (onset, duration) = nvTiming(sub)
                                        pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 2, noteCount: 0)
                                    }
                                    return
                                case .tie:
                                    // NOTE VIEW: deliberately NO push here — the PRECEDING real/FILL hit's own
                                    // `riffTieExtensionBeats` lookahead already extended ITS queued event's
                                    // `durationBeat` to cover this rest step, so the note box's fade already
                                    // runs the full tied span for free. Posting a second event here would
                                    // wrongly restart the fade partway through.
                                    return
                                case .fill:
                                    let (pickIndex, pickRange) = resolveEuclidPick(noteSel, ord: ord, count: thisLaneCount)
                                    let tieExt = riffTieExtensionBeats(startStepIdx: stepIdx, startOrd: riffOrd)
                                    let gb = min(sub * gate, S * 0.95) + tieExt
                                    let fillVel = UInt8(velocityAbsolute)
                                    let fillIdx = resolvedPickIndices(pickIndex, pickRange, count: notes.count)
                                    for idx in fillIdx where idx >= 0 && idx < notes.count {
                                        strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: gb, octave: octave, explicitNote: notes[idx].note, explicitVel: fillVel, busOverride: busOverride)
                                    }
                                    // NOTE VIEW (ferry §4.5): "ON REST = FILL: show the filled note as a
                                    // normal hit" — kind 0, same as any other hit, from the SAME indices the
                                    // strike loop above just used (read-only, the strike itself is untouched) —
                                    // UNLESS this FILL itself went on to tie through a further rest (`tieExt >
                                    // 0`), in which case it gets kind 3 (tied hit) for the SAME reason the real-
                                    // rank branch below does: §4.5's TIE wording ("full brightness... fading
                                    // from the END of the extended note") describes behaviour genuinely
                                    // different from the general §4.4 continuous-fade rule, not just "a longer
                                    // input to the same formula."
                                    if nvSent {
                                        var fillNC = 0
                                        for idx in fillIdx where idx >= 0 && idx < notes.count && fillNC < Router.noteViewMaxNotes {
                                            if let p = finalPitch(Int(notes[idx].note), oct: octave) { nvScratch[fillNC] = p; fillNC += 1 }
                                        }
                                        if fillNC > 0 {
                                            let (onset, duration) = nvTiming(gb)
                                            pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: tieExt > 0 ? 3 : 0, noteCount: fillNC)
                                        }
                                    }
                                    return
                                }
                            }
                            // ABSOLUTE VELOCITY (Paul 2026-10-09): the riff-sourced note's own inherited velocity
                            // is no longer read at all — VELOCITY is a genuine override now, same as every other
                            // strike this lane makes (see EuclidLine.velocityAbsolute's own doc comment).
                            guard let note = riffResolve(rank: rank, oct: riffOctave, n: thisLaneCount, wrap: .fold, asc: { notes[$0].note }) else { return }
                            let tieExt = riffTieExtensionBeats(startStepIdx: stepIdx, startOrd: riffOrd)
                            let gb = min(sub * gate, S * 0.95) + tieExt
                            strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: gb, octave: 0, explicitNote: note, explicitVel: UInt8(velocityAbsolute), busOverride: busOverride)
                            // NOTE VIEW: `riffOctave` is already folded into `note` by `riffResolve` itself
                            // (its own `+ 12*oct`), which is why `octave: 0` is passed to strikeChord above —
                            // so the display pitch only adds `transpose`, never re-applying riffOctave.
                            // kind 3 (tied hit) when this strike itself ties through a FOLLOWING rest
                            // (`tieExt > 0`) — see the §4.5 comment on the FILL branch above for why this
                            // needs its own kind, not just a longer `durationBeat` fed into kind 0's formula.
                            if nvSent, let p = finalPitch(Int(note), oct: 0) {
                                nvScratch[0] = p
                                let (onset, duration) = nvTiming(gb)
                                pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: tieExt > 0 ? 3 : 0, noteCount: 1)
                            }
                            return
                        }
                        // SEQUENTIAL SOURCES (Paul 2026-10-02): .riff/.arp step through the immediately-preceding,
                        // non-bypassed slot's OWN authored sequence by `ord` — an explicit resolved MIDI note, not an
                        // index into the held chord, so this is a separate branch, not two more cases folded into the
                        // pool-index switch below. A stored .riff/.arp whose predecessor no longer matches (chain
                        // edited, now bypassed) emits nothing — same honest-non-guess contract as every other noteSel
                        // case that can't resolve (e.g. an aggregate pick against an empty pool).
                        if noteSel == .riff || noteSel == .arp {
                            guard (noteSel == .riff && predType == .riff) || (noteSel == .arp && predType == .arp) else { return }
                            let rp = cell.procs[predIdx]
                            if noteSel == .riff {
                                let riffSteps = max(1, min(32, rp.riffSteps))
                                func riffStepIsRest(_ i: Int) -> Bool {
                                    rp.riffPoly ? ((i < rp.riffMask.count ? rp.riffMask[i] : 0) == 0) : ((i < rp.riffRanks.count ? rp.riffRanks[i] : 0) < 1)
                                }
                                // two bounded (≤32) scans, no allocation — mirrors this same function's own cycleHits/
                                // hitsUpTo idiom above, just counting/locating non-rest steps instead of hit hits.
                                var nonRestCount = 0
                                for i in 0..<riffSteps where !riffStepIsRest(i) { nonRestCount += 1 }
                                guard nonRestCount > 0 else { return }   // all-rest predecessor (POLY empty mask / all-zero MONO ranks) — silent, not a crash
                                let wantedOrd = Int(((ord % Int64(nonRestCount)) + Int64(nonRestCount)) % Int64(nonRestCount))
                                var seen = 0; var stepIdx = -1
                                for i in 0..<riffSteps where !riffStepIsRest(i) {
                                    if seen == wantedOrd { stepIdx = i; break }
                                    seen += 1
                                }
                                guard stepIdx >= 0 else { return }
                                let roct = stepIdx < rp.riffOct.count ? rp.riffOct[stepIdx] : 0        // RIFF's own per-step OCT lane — stacks additively with this line's own `octave` at strikeChord
                                // ABSOLUTE VELOCITY (Paul 2026-10-09): RIFF's own per-step velocity formula
                                // (accent lane + coinVelFactor) is no longer read — VELOCITY overrides it, same
                                // as every other strike this lane makes.
                                composeChainSet(cell: cell, pool: pool, upto: predIdx - 1, m: mTickBeat, S: S, cycleBeats: cyc)   // the pool feeding INTO the riff's own slot (a no-op pass-through when riff is slot 0)
                                func strikeRiffRank(_ rank: Int) {
                                    guard rank >= 1 else { return }
                                    guard let base = riffResolve(rank: rank, oct: roct, n: chainScratch.srcCount(filter: 0), wrap: rp.riffWrap, asc: { Int(chainScratch.srcAscending($0, filter: 0)) }) else { return }
                                    strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: min(sub * gate, S * 0.95), octave: octave, explicitNote: base, explicitVel: UInt8(velocityAbsolute), busOverride: busOverride)
                                }
                                if rp.riffPoly {   // POLY: a step strikes the whole set rank mask as a simultaneous chord-stab
                                    let polyMask = stepIdx < rp.riffMask.count ? rp.riffMask[stepIdx] : 0
                                    for rank in 1...8 where (polyMask & (1 << (rank - 1))) != 0 { strikeRiffRank(rank) }
                                } else {
                                    strikeRiffRank(stepIdx < rp.riffRanks.count ? rp.riffRanks[stepIdx] : 0)
                                }
                            } else {   // .arp
                                composeChainSet(cell: cell, pool: pool, upto: predIdx - 1, m: mTickBeat, S: S, cycleBeats: cyc)   // the pool feeding INTO the arp's own slot
                                // `ord` becomes `phaseIndex` directly, unmodified — arpPick is fully pure/total in
                                // phaseIndex (incl. RANDOM/RANDOM ONCE, both seeded hashes of phaseIndex alone).
                                // ABSOLUTE VELOCITY (Paul 2026-10-09): the upstream ARP's own VELOCITY/VELOCITY
                                // TILT-resolved pick velocity is no longer read — this line's own VELOCITY
                                // overrides it, same as every other strike this lane makes.
                                let pick = arpPick(phaseIndex: ord, octaves: max(1, min(4, Int(rp.octaves))), pattern: rp.patternIndex, pool: chainScratch,
                                                   chanMask: 0xFFFF, cableMask: 0b1111,
                                                   octDown: rp.arpOctDown, randomAnchor: rp.arpRandomAnchor, seed: rp.arpSeed,
                                                   velocity: rp.arpVelocity, velTilt: rp.arpVelTilt)
                                guard pick.note >= 0 else { return }   // empty predecessor-fed pool
                                strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: min(sub * gate, S * 0.95), octave: octave, explicitNote: pick.note, explicitVel: UInt8(velocityAbsolute), busOverride: busOverride)
                            }
                            return
                        }
                        // GATE loosens the column-boundary safety clamp 0.9→0.95 so an aggressive per-lane GATE still
                        // can't bleed past its own column; OCTAVE threads straight to strikeChord (clamped there, like
                        // UTILITY/ARP). VELOCITY (Paul 2026-10-09) is a genuine absolute MIDI override — the
                        // inherited note's own velocity is never read; every pick shape (a single rank, BOT2/TOP2's
                        // pair, or ALL) resolves to a concrete index list first (`resolvedPickIndices`) so it can
                        // strike via `explicitNote:` uniformly, mirroring ARP's own `arpVelocity` convention.
                        let (pickIndex, pickRange) = resolveEuclidPick(noteSel, ord: ord, count: laneCount(lineIndex))
                        let hitNotes = laneNotes(lineIndex)
                        let hitVel = UInt8(velocityAbsolute)
                        let hitGate = min(sub * gate, S * 0.95)
                        let hitIdx = resolvedPickIndices(pickIndex, pickRange, count: hitNotes.count)
                        for idx in hitIdx where idx >= 0 && idx < hitNotes.count {
                            strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: hitGate, octave: octave, explicitNote: hitNotes[idx].note, explicitVel: hitVel, busOverride: busOverride)
                        }
                        // NOTE VIEW: read-only mirror of the strike loop above, same resolved indices,
                        // written straight into `nvScratch` (no intermediate `.compactMap` array — §5.1).
                        if nvSent {
                            var hitNC = 0
                            for idx in hitIdx where idx >= 0 && idx < hitNotes.count && hitNC < Router.noteViewMaxNotes {
                                if let p = finalPitch(Int(hitNotes[idx].note), oct: octave) { nvScratch[hitNC] = p; hitNC += 1 }
                            }
                            if hitNC > 0 {
                                let (onset, duration) = nvTiming(hitGate)
                                pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 0, noteCount: hitNC)
                            }
                        }
                    } else if let missSel = missNoteSel {
                        // HIT/MISS SPLIT (Paul 2026-10-02: "plays the off notes") — a REST step can now ALSO strike,
                        // with its own independent note-select/velocity/gate/octave. `missNoteSel == nil` is the
                        // whole feature's on/off switch (nil ⇒ today's silent-rest behaviour, byte-identical for
                        // every doc that's never touched this) — there's no separate enable flag. No DIE salt on
                        // either side anymore (DIE was removed entire the same day — "drop it, please"). RIFF/ARP
                        // are NOT offered on the miss side (the UI never shows those two chips there); guarded
                        // explicitly so a stray `.riff`/`.arp` miss pick (a hand-edited doc, or a future UI slip)
                        // stays silent rather than falling through to `resolveEuclidPick`'s `default: (nil, nil)`,
                        // which reads as ALL (strike everything) — an honest no-op, not an accidental loud one.
                        guard missSel != .riff && missSel != .arp else { return }
                        // VELOCITY 0 = EFFECTIVELY OFF — same guard as the HIT side above, same reasoning (a
                        // MISS line scaled to 0 should be silent, not audible at clampVel's 1...127 floor).
                        guard missVelocity > 0 else { return }
                        let effMisses = Int64(max(1, cycleLen - cycleHits))   // every cycle is hits+misses, so this is just the complement of effHits
                        var missesUpTo = 0; for s in 0...raw where !isHitAt(s) { missesUpTo += 1 }
                        let missOrd = cy * effMisses + Int64(missesUpTo - 1)
                        let (pickIndex, pickRange) = resolveEuclidPick(missSel, ord: missOrd, count: laneCount(lineIndex))
                        let missGateReal = min(sub * missGate, S * 0.95)
                        if let range = pickRange {
                            for idx in range.lo...range.hi { strikeChord(tau: mTickBeat, velScale: missVelocity, gateBeats: missGateReal, onlyIndex: idx, octave: missOctave, busOverride: busOverride, srcOverride: laneNotes(lineIndex)) }
                        } else {
                            strikeChord(tau: mTickBeat, velScale: missVelocity, gateBeats: missGateReal, onlyIndex: pickIndex, octave: missOctave, busOverride: busOverride, srcOverride: laneNotes(lineIndex))
                        }
                        // NOTE VIEW (ferry §4.3, "miss-playing"): mirrors the SAME 3 pick shapes the real
                        // strike calls above resolve (a single index / a range / both-nil-meaning-ALL),
                        // writing straight into `nvScratch` — no `resolvedPickIndices([Int])` detour and
                        // no `.compactMap` (§5.1: neither call site above this needs to allocate either,
                        // so this read-only mirror shouldn't be the one place that does).
                        if nvSent {
                            let missNotesPool = laneNotes(lineIndex)
                            var missNC = 0
                            func addMiss(_ idx: Int) {
                                guard idx >= 0, idx < missNotesPool.count, missNC < Router.noteViewMaxNotes else { return }
                                if let p = finalPitch(Int(missNotesPool[idx].note), oct: missOctave) { nvScratch[missNC] = p; missNC += 1 }
                            }
                            if let range = pickRange { for idx in range.lo...range.hi { addMiss(idx) } }
                            else if let idx = pickIndex { addMiss(idx) }
                            else { for idx in 0..<missNotesPool.count { addMiss(idx) } }
                            if missNC > 0 {
                                let (onset, duration) = nvTiming(missGateReal)
                                pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 1, noteCount: missNC)
                            }
                        }
                    }
                }
            }
            // A pulses<=0 row is an UNUSED fixed slot — skipped entirely, not run-and-silenced. `iterateTicks`
            // used to dedup via a scalar `lastTick[row]` SHARED across every line on this row (safe for one real
            // line; a known timing-smear limitation for 2+ real lines sharing a row across a window boundary —
            // FIXED 2026-10-05, `iterateTicks` now dedups per (row, lineIndex), one scalar per line). Before that
            // fix, running all 4 lines unconditionally under POOL (which overrides EVERY line's K to the
            // held-note count, ignoring its own authored `pulses`) turned the 3 always-present silent padding
            // rows into 3 more real, identical lines competing for that shared dedup state — caught by
            // `testEuclidPulsesFromPoolTracksHeldCount` going 9→54 note-ons, traced with a throwaway debug trace,
            // not guessed. Skipping a pulses<=0 row still keeps it out of the dedup contention entirely (now
            // moot for correctness, since lines no longer share a slot, but still cheap and matches the idle-row
            // mockup — "0 hits, no comet" — an unused row stays silent regardless of POOL).
            // PLAY/STOP (Paul 2026-10-01): `enabledResolved` gates emission ONLY — pulses/steps/rotate are never
            // touched by the toggle, so re-enabling a lane resumes exactly the pattern it had before (not the
            // pulses=0 "unused slot" case just above, which is a different, permanent-until-edited state).
            // `lineIndex` (the array position, 0...3 — fixed per-lane identity, NOT a re-packed "nth active
            // line" count) is each line's OWN tick-dedup slot, so a lane keeps the SAME slot across windows
            // where a sibling lane happens to be silent — using `.enumerated()`'s offset directly, not a
            // separately-tracked "active line count", is what makes that stable.
            // EUCLIDEOUS PAGE REWORK (2026-10-07/08, DISPLAY-ONLY role since 2026-10-09 ferry §2.4): this
            // fill still copies lane 0's own resolved pool into `riffSrcNoteBuf`/`riffSrcNoteCount`, but
            // nothing in the AUDIBLE path reads it anymore — the `if useRiff {` resolution (above, in the
            // per-line loop) now reads EACH lane's own per-lane buffer directly (`laneNotes(lineIndex)`/
            // `laneCount(lineIndex)`), so two lanes with different I/O-tab sources genuinely hear different
            // notes off the same shared riff shape. This buffer's only remaining consumer is
            // `euclideousRiffLiveNotes` below (a kept-but-currently-unrendered "show the resolved note"
            // readout) — left reading lane 0 specifically since nothing displays it and a single sample
            // point is as good as any for now. `useRiff`/`euclideousRiff` are plain fields on the SHARED
            // EuclidLine/MachineParams — row-agnostic in the model and in SnapshotBuilder's resolve — so a
            // `.euclid` cell anywhere else in the grid (every pre-existing `useRiff` RouterTest places its cell
            // at row 0, not Snap.euclideousRow) must keep reading the SAME pool the lanes themselves use,
            // exactly as before this split — the `else` branch's plain copy of srcNoteBuf/srcNoteCount is
            // unchanged, and `laneNotes`/`laneCount` already resolve to that same shared pool for any
            // non-Euclideous row regardless of lineIndex (see their own definitions above).
            if r == Snap.euclideousRow {
                let notes = laneNotes(0)
                riffSrcNoteCount = min(riffSrcNoteBuf.count, laneCount(0))
                for (i, sn) in notes.enumerated() where i < riffSrcNoteCount { riffSrcNoteBuf[i] = sn }
                // LIVE RIFF POOL DISPLAY (Paul 2026-10-08): a dedicated snapshot for the riff panel's own
                // "show the resolved note, not just the rank" ask — see euclideousRiffLivePool()'s own doc.
                euclideousRiffLiveCount = min(euclideousRiffLiveNotes.count, riffSrcNoteCount)
                for i in 0..<euclideousRiffLiveCount { euclideousRiffLiveNotes[i] = UInt8(max(0, min(127, riffSrcNoteBuf[i].note))) }
            } else {
                riffSrcNoteCount = srcNoteCount
                for i in 0..<srcNoteCount { riffSrcNoteBuf[i] = srcNoteBuf[i] }
            }
            for (lineIndex, L) in p.euclidLines.enumerated() where L.pulses > 0 && L.enabledResolved {
                // EUCLIDEOUS (Paul 2026-10-05): per-line RATE (nil ⇒ the machine-wide euclidRateBeats, byte-
                // identical for every line that's never set its own) and per-line EMITTER override (nil ⇒ the
                // cell's own bm, via strikeChord's busOverride).
                runEuclidLine(lineIndex: lineIndex, pulses: L.pulses, steps: L.steps, rotate: L.rotate, dir: L.directionResolved,
                              noteSel: L.noteSelResolved, gate: L.gateResolved, octave: L.octaveResolved, velocity: L.velocityResolved,
                              velocityAbsolute: L.velocityAbsoluteResolved,
                              rate: L.rate?.beats ?? p.euclidRateBeats, busOverride: L.emitterMask,
                              missNoteSel: L.missNoteSel, missGate: L.missGateResolved, missOctave: L.missOctaveResolved, missVelocity: L.missVelocityResolved,
                              useRiff: L.useRiffResolved, riffRotate: L.riffRotateResolved, riffOctave: L.riffOctaveResolved,
                              riffDir: L.riffDirResolved, riffDirSeed: L.riffDirSeedResolved, riffDirBias: L.riffDirBiasResolved,
                              tilt: L.tiltResolved,
                              riffLock: L.riffLockResolved, riffInvert: L.riffInvertResolved, riffOnRest: L.riffOnRestResolved)
            }
        case .burst:
            let count = Int(max(2, min(16, p.count)))
            // Lay ONE accel/decel roll of `count` strikes across [anchor, anchor+width], window-gated (reused burstBuf,
            // no alloc). Shared by all three modes; ONCE reproduces the old inline loop → byte-identical. CLOCK
            // (Paul 2026-09-26): the anchor shifts into local time, the roll's own shape is computed there
            // unchanged, then each strike's onset+gate invert back to real — `clockLocalAnchor`/`clockDriverTiming`
            // no-op (byte-identical) when this cell isn't a retimed driver.
            func layBurst(anchor: Double, width: Double) {
                let localAnchor = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: anchor, S: S, cycleBeats: cyc, originRef: mWinStart)
                burstFractionsInto(&burstBuf, count: count, curve: p.curve)
                let minGap = width / Double(count) * 0.9
                for i in 0..<count {
                    let localTau = localAnchor + burstBuf[i] * width
                    let (tau, gate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: localTau, localOff: localTau + minGap, S: S, cycleBeats: cyc, originRef: mWinStart)
                    if inWindow(tau) {
                        let velScale = max(0.05, Double(100 - i * (60 / max(1, count))) / 100.0)   // fade across the roll (relative)
                        strikeChord(tau: tau, velScale: velScale, gateBeats: gate)
                    }
                }
            }
            // SPAN LADDER (Paul 2026-08-22): the roll/pattern spans N columns (·16=×2 ·32=×4), anchored at the span origin;
            // odd N = polymeter. CELL=1 (S) / ROW=8 (cyc) are byte-identical. The window gate keeps each cell to its column.
            let bSpan = spanLadderBeats(p.burstSpanN, S: S, row: cyc)
            switch p.burstMode {
            case .once:
                layBurst(anchor: columnStart(colStart, bSpan), width: bSpan)
            case .coin:
                // seeded chance-of-burst per column-step — the roll fills THIS column when it fires (replay-exact)
                if burstCoinFires(step: Int((colStart / S).rounded()), chance: p.burstChance) { layBurst(anchor: colStart, width: S) }
            case .pattern:
                // At each BURST slice the roll STRETCHES over its carry-run; CARRY/REST launch nothing.
                let patAnchor = columnStart(colStart, bSpan)
                if p.burstRateOn {
                    // RATE AXIS (Paul 2026-08-26): the span is divided into slices of width burstRateBeats; the 8-figure
                    // WALKS/TILES (mod-8) across them — a fine rate packs many roll-slices, a coarse rate fewer than 8.
                    let sliceW = max(0.001, p.burstRateBeats)
                    let nSlices = max(1, min(64, Int((bSpan / sliceW).rounded())))
                    for i in 0..<nSlices {
                        let run = burstCarryRun(p.burstSlices, at: i, rotate: p.burstRotate, count: nSlices)
                        if run > 0 { layBurst(anchor: patAnchor + Double(i) * sliceW, width: Double(run) * sliceW) }
                    }
                } else {
                    let sliceW = bSpan / 8   // LEGACY fixed-8 (byte-identical)
                    for i in 0..<8 {
                        let run = burstCarryRun(p.burstSlices, at: i, rotate: p.burstRotate)
                        if run > 0 { layBurst(anchor: patAnchor + Double(i) * sliceW, width: Double(run) * sliceW) }
                    }
                }
            }
        case .cascade:
            let srcN = srcNotes.count
            // SPAN: CELL reveals across the column at the arp rate; ROW spreads the reveal EVENLY across the whole BAR
            // (one note per bar-slice), anchored at the bar start. (Paul 2026-08-19)
            // SPAN LADDER (Paul 2026-08-22, RATE×ladder): cascadeSpanN>0 ⇒ RATE = the reveal spacing, SPAN N = the reveal
            // WINDOW in columns (anchored at the span origin; re-anchors every N cols). cascadeSpanN==0 ⇒ LEGACY CELL|ROW.
            let cLadder = p.cascadeSpanN > 0
            let cRow = (p.cascadeSpan == .row)
            let arpRateReveal = Snap.arpRateBeats[Int(max(0, min(Int8(Snap.arpRateBeats.count - 1), p.rateIndex)))]
            let cWidth = cLadder ? spanLadderBeats(p.cascadeSpanN, S: S, row: cyc) : (cRow ? cyc : S)
            let cAnchor = cLadder ? columnStart(colStart, cWidth) : (cRow ? columnStart(colStart, cyc) : colStart)
            let sub = cLadder ? arpRateReveal : (cRow ? (cWidth / Double(max(1, srcN))) : arpRateReveal)
            guard sub > 0 else { break }
            // CLOCK (Paul 2026-09-26): the anchor and the held-to-boundary point both shift into local time; each
            // reveal's local tick then inverts back independently (a duration can't invert directly — only points
            // can — so the gate is the REAL difference of two independently-inverted points, not a scaled width).
            let localAnchor = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: cAnchor, S: S, cycleBeats: cyc, originRef: mWinStart)
            for j in 0..<srcN {                                   // reveal note j at tick j, HELD to the boundary (accumulating)
                let localTau = localAnchor + Double(j) * sub
                if localTau >= localAnchor + cWidth { break }     // ran past the span — the rest reveal next entry
                let (tau, gate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: localTau, localOff: localAnchor + cWidth, S: S, cycleBeats: cyc, originRef: mWinStart)
                if inWindow(tau) {
                    let idx = p.strumDir == .down ? (srcN - 1 - j) : j   // reveal order (UP default · DOWN top-first)
                    strikeChord(tau: tau, velScale: 1.0, gateBeats: max(0.01, gate), onlyIndex: idx)
                }
            }
        case .drone:
            // PAD: strike the whole entry chord ONCE, held to the boundary; the GATE knob scales the inherited velocity.
            // CLOCK (Paul 2026-09-26): the column's local start anchors the strike; held-to-boundary is the local
            // column's own end, both inverted back to real for scheduling.
            let droneLocalStart = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: colStart, S: S, cycleBeats: cyc, originRef: mWinStart)
            let (droneTau, droneGate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: droneLocalStart, localOff: droneLocalStart + S, S: S, cycleBeats: cyc, originRef: mWinStart)
            if inWindow(droneTau) {
                strikeChord(tau: droneTau, velScale: max(0.05, min(1, p.gate)), gateBeats: droneGate)
            }
        case .shift:
            // GROOVE: push the chord's onset LATE by up to ~40% of the step (spread 0…1), held to the boundary.
            let push = max(0, min(1, p.spread)) * 0.4 * S
            let shiftLocalStart = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: colStart, S: S, cycleBeats: cyc, originRef: mWinStart)
            let (tau, gate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: shiftLocalStart + push, localOff: shiftLocalStart + S, S: S, cycleBeats: cyc, originRef: mWinStart)
            if inWindow(tau) { strikeChord(tau: tau, velScale: 1.0, gateBeats: gate) }
        case .humanize:
            // THE DETERMINISTIC HUMAN: each note strikes at a seeded late offset (0…~15% step) with a seeded velocity
            // duck — replay-safe (seed = column · note · index). AMOUNT (spread) scales both. Held to the boundary.
            // The duck is RELATIVE, so it ducks the inherited source velocity (user 2026-08-09).
            let amt = max(0, min(1, p.spread))
            let col = UInt64(bitPattern: Int64((colStart / S).rounded()))
            let humanizeLocalStart = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: colStart, S: S, cycleBeats: cyc, originRef: mWinStart)
            for (k, sn) in srcNotes.enumerated() {
                let note = sn.note + transpose
                guard note >= 0 && note <= 127 else { continue }
                let h = splitmix64Mix(col &* 2_654_435_761 &+ UInt64(note) &* 131 &+ UInt64(k) &* 17)
                let tFrac = Double(h & 0xFFFF) / 65535.0                     // 0…1 → late offset
                let vFrac = Double((h >> 16) & 0xFFFF) / 65535.0             // 0…1 → velocity duck
                let velScale = max(0.05, (100.0 - vFrac * amt * 45.0) / 100.0)
                let (tau, gate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: humanizeLocalStart + tFrac * amt * 0.15 * S, localOff: humanizeLocalStart + S, S: S, cycleBeats: cyc, originRef: mWinStart)
                if inWindow(tau) { strikeChord(tau: tau, velScale: velScale, gateBeats: gate, onlyIndex: k) }
            }
        case .hocket:
            // HOCKET (v1, AcceptanceCriteria-hocket-processor): play the pool (WHAT) timed by LISTENING to another wire
            // (WHEN). Each decision tick queries the listened emitter — GAPS strikes only in its SILENCES (call-and-
            // response), TRADE answers just AFTER it strikes (hit-for-hit). The pool is walked ascending, one note per
            // strike → a line split across two synths by listening. Live query of the wire's voices/onset (the
            // CONVERSATION L1 caveat: what it has emitted SO FAR this render is visible — put the listener downstream).
            let srcCount = srcNotes.count
            let listenBus = max(0, min(3, p.hocketSource))
            // THE CYCLE LAW (wire-grain): a HOCKET that OUTPUTS on the wire it LISTENS to is a loop — it falls SILENT
            // (the standing "loops fall silent" rule). Cross-cell cycles aren't detected in v1 (they ping-pong at one
            // block's latency); the direct self-cycle is the footgun this guards.
            if srcCount > 0 && (bm & (UInt8(1) << UInt8(listenBus))) == 0 {
                let sub = max(0.03125, p.hocketRateBeats)
                iterateTicks(row: r, effColumn: effColumn, sub: sub, gateFraction: 0.9,
                             beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                             beatsPerSample: beatsPerSample, S: S, a: a, columns: max(1, Int((cyc / S).rounded())),
                             clockCell: chainDriver >= 0 ? cell : nil, clockFrom: 0, clockTo: chainDriver, cycleBeats: cyc) { tick, mTickBeat, onTime, _ in
                    let pass: Bool
                    switch p.hocketMode {
                    case .gaps:
                        pass = !emitterSounding(listenBus)                               // speak only in the wire's silence
                    case .trade:
                        let last = emitterLastOnsetSample[listenBus]                     // the wire's most recent onset
                        let subSamples = Int64((sub / max(1e-9, beatsPerSample)).rounded())
                        pass = last != .min && last < onTime && last >= onTime - subSamples   // it struck within the last tick → answer now
                    }
                    guard pass else { return }
                    let idx = Int(((tick % Int64(srcCount)) + Int64(srcCount)) % Int64(srcCount))   // walk the pool ascending (a line)
                    strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: min(sub * 0.9, S * 0.9), onlyIndex: idx)
                }
            }
        default:
            break
        }
    }

    // MARK: - CELL MACHINE (feat/EditPageSpike) stage-2 — the serial chain feed

    /// The chain's TICK DRIVER — the index of the LAST non-bypassed rhythm-generating slot (arp/ratchet/strum + the
    /// generators euclid/burst/cascade/drone/shift/humanize, user 2026-08-09). It sets the rhythm: slots BEFORE it
    /// compose as its source; slots AFTER it FOLD onto each note it emits (a per-tick hold — a downstream stage gates the
    /// pass, chance drops, harmonize expands). -1 = no tick generator (a hold/plain cell). This is what makes
    /// `[arp → chance]` or `[euclid → harmonize]` keep generating (the driver drives, the tail folds).
    private func chainDriverIndex(_ cell: SnapCell) -> Int {
        guard cell.procs.count >= 2 else { return -1 }
        // The driver = the LAST non-bypassed driver that ISN'T a foldable ratchet. A RATCHET PATTERN (always) or a COIN
        // ratchet in PASS-THROUGH folds PER-NOTE downstream (emitDriverNote), so the UPSTREAM driver (e.g. the ARP) keeps its
        // rhythm + note lengths and the ratchet re-shapes each note in place instead of re-pooling (Paul 2026-09-06). If EVERY
        // driver here is a foldable ratchet — nothing upstream to fold ONTO (a lone [RATCHET PATTERN] in a chain, or
        // [HARMONIZE → RATCHET PATTERN] where HARMONIZE isn't a driver) — the last one DRIVES (re-pools) as before.
        var lastDriver = -1, lastNonFold = -1, i = 0
        while i < cell.procs.count {
            if !cell.slotBypass[i] && isDriverType(cell.procs[i].type) {
                lastDriver = i
                if !isRatchetFoldable(cell.procs[i]) && !isModifierFoldable(cell.procs[i]) { lastNonFold = i }
            }
            i += 1
        }
        return lastNonFold >= 0 ? lastNonFold : lastDriver
    }
    /// A ratchet that FOLDS per-note downstream instead of driving (Paul 2026-09-07): PATTERN (Model B — advances one matrix
    /// column PER ARP NOTE: 0 = rest, 1 = passthrough, 2…8 = ratchet that note in place), or a COIN ratchet in PASS-THROUGH.
    /// As the ONLY driver (standalone) the ratchet still DRIVES self-clocked (chainDriverIndex falls to lastDriver → emitRatchetModal).
    private func isRatchetFoldable(_ p: SnapParams) -> Bool { p.type == .ratchet && (p.rtcMode == .pattern || (p.rtcMode == .coin && p.rtcFold)) }
    /// SHIFT / HUMANIZE are per-note MODIFIERS (Paul 2026-09-06): downstream of a real driver they don't re-pool — they
    /// jitter/push each driven note IN PLACE (emitDriverNote), so [ARP→HUMANIZE] humanizes the arp's notes + keeps its
    /// rhythm. As the ONLY driver (standalone / [non-driver→SHIFT]) they still GENERATE (chainDriverIndex falls to lastDriver).
    /// DEAD-CODE CLEANUP (code-review finding 2026-10-04): this used to also check `.velocity`/`.euclidMask`, but its
    /// ONLY caller (chainDriverIndex, below) only ever evaluates it inside `isDriverType(...)==true`, and that switch's
    /// exhaustive case list never includes `.velocity`/`.euclidMask` — those two arms could never fire. Both types'
    /// real fold-eligibility is correctly handled elsewhere (`downstreamMaskFoldIndex` and VELOCITY's own dedicated
    /// per-note fold in `emitDriverNote`), so removing the unreachable checks here changes nothing behaviourally.
    private func isModifierFoldable(_ p: SnapParams) -> Bool { p.type == .shift || p.type == .humanize }
    /// The FIRST non-bypassed foldable RATCHET slot after `driver` — PATTERN (per-slice REST/pass/burst) or COIN PASS-THROUGH.
    private func downstreamRatchetFoldIndex(_ cell: SnapCell, after driver: Int) -> Int? {
        var j = driver + 1
        while j < cell.procs.count { if !cell.slotBypass[j] && isRatchetFoldable(cell.procs[j]) { return j }; j += 1 }
        return nil
    }
    /// The FIRST non-bypassed EUCLID MASK slot after `driver` (Paul 2026-09-27) — the arp-only euclid mask, pulled out
    /// as its own downstream fold so it gates ANY driver's notes, not just ARP's own.
    private func downstreamMaskFoldIndex(_ cell: SnapCell, after driver: Int) -> Int? {
        var j = driver + 1
        while j < cell.procs.count { if !cell.slotBypass[j] && cell.procs[j].type == .euclidMask { return j }; j += 1 }
        return nil
    }
    /// CLOCK (AcceptanceCriteria-clock-processor, Paul 2026-09-26) — THE SOVEREIGN LAW, mechanically: the beat a
    /// downstream fold consumer at `target` should use for its OWN internal step/rate math, after composing every
    /// non-bypassed CLOCK stage strictly between `from` and `target` IN CHAIN ORDER (multiple CLOCKs compose — the
    /// composition test). No CLOCK in range ⇒ returns `atBeat` unchanged, so this is a no-op (byte-identical)
    /// whenever the feature is unused. This is the ONLY thing CLOCK touches: `S`/`cycleBeats` (needed only to size
    /// the lane's own SPAN) are read, never transformed — the caller's own window/column/span math is untouched,
    /// and the RETURNED value is substituted ONLY into that one consumer's own rate/slice formula, never
    /// propagated anywhere else (note pitch/velocity, gate timing, echo scheduling — all keep reading the real
    /// beat). CLOCK is now always the DRAWN lane below — FIXED/WAVE were removed entire (Paul 2026-09-26, same day —
    /// Paul's own spec describes one mechanism, not a choice of three).
    private func clockTransformedBeat(_ cell: SnapCell, from: Int, to target: Int, atBeat: Double, S: Double, cycleBeats: Double) -> Double {
        guard target > from else { return atBeat }
        var beat = atBeat
        var j = from
        while j < target {
            if !cell.slotBypass[j] {
                let p = cell.procs[j]
                if p.type == .clock {
                    // FREE (clockSpanN 0) is a real, tested mode here — the lane just laps forever from absolute
                    // beat 0 (clockDrawnPhase's own fullLaps factoring keeps that O(steps), never a per-lap walk
                    // since t=0). spanLadderBeats itself has no "0 = free" sentinel (n≤1 means ONE COLUMN, not
                    // free) — this mirrors the same explicit `> 0` guard RATCHET PATTERN/DEST use for their own
                    // free-run spans.
                    let period = p.clockSpanN > 0 ? spanLadderBeats(p.clockSpanN, S: S, row: cycleBeats) : 0
                    // rateBeats = S (Paul 2026-09-26): a clock column IS one grid column — no separate RATE dial.
                    // This is also what makes the matrix's live-column highlight (GridUI) trivially correct: it's
                    // the SAME clock the rest of the grid already extrapolates from, just widened to this lane's
                    // own STEPS/SPAN.
                    beat = clockDrawnPhase(beat, ratios: p.clockDrawnRatios, glide: p.clockDrawnGlide,
                                           steps: p.clockDrawnSteps, rateBeats: S, periodBeats: period)
                } else if p.type == .killStep {
                    // KILL STEP (Paul 2026-09-26, sibling to CLOCK) carries its OWN rate — unlike a clock column,
                    // its "column" isn't the cell's grid step, so `S` here is ITS resolved rate, not the caller's.
                    let rate = p.killStepRateBeats
                    let period = p.killStepSpanN > 0 ? spanLadderBeats(p.killStepSpanN, S: rate, row: cycleBeats) : 0
                    beat = killStepPhase(beat, columnMap: p.killStepColumnMap, columnsPerLap: p.killStepColumnsPerLap, steps: p.killStepCount, rateBeats: rate, periodBeats: period)
                }
            }
            j += 1
        }
        return beat
    }
    /// Driver retiming (Paul 2026-09-26, final spec: "a grid with a variable number of steps, each step a mutually
    /// exclusive speed, and another row on the same grid for glide"). `clockTransformedBeat` above is for
    /// DOWNSTREAM fold consumers that only ever READ a beat — for a DRIVER's own tick generation, the tick must be
    /// SCHEDULED too, which needs an exact inverse. CLOCK's grid IS this spec: its per-column ratio picks
    /// (`clockDrawnRatios`) ARE the mutually-exclusive-speed-per-step, and `clockDrawnGlide` IS the second row on
    /// that same grid — no separate glide mechanism needed, its own ramping is stateless (purely a function of
    /// where you are in the current column, never a remembered "previous session" value). `originRef` is the
    /// window's own REAL start beat, threaded through unchanged from `iterateTicks`; every CLOCK slot recomputes
    /// its OWN span-origin from it (each slot may carry its own SPAN), pinned to this ONE reference for the whole
    /// tick search so the forward window-bound transforms and every later tick inversion agree on the same
    /// span-anchor (see `clockDrawnPhase`'s `originOverride` doc comment for why that matters).
    private func driverClockBeat(_ cell: SnapCell, from: Int, to target: Int, atBeat: Double, S: Double, cycleBeats: Double, originRef: Double) -> Double {
        guard target > from else { return atBeat }
        var beat = atBeat
        var j = from
        while j < target {
            if !cell.slotBypass[j] {
                let p = cell.procs[j]
                if p.type == .clock {
                    let period = p.clockSpanN > 0 ? spanLadderBeats(p.clockSpanN, S: S, row: cycleBeats) : 0
                    let origin = period > 0 ? columnStart(originRef, period) : 0
                    beat = clockDrawnPhase(beat, ratios: p.clockDrawnRatios, glide: p.clockDrawnGlide,
                                           steps: p.clockDrawnSteps, rateBeats: S, periodBeats: period,
                                           originOverride: origin)
                } else if p.type == .killStep {
                    let rate = p.killStepRateBeats
                    let period = p.killStepSpanN > 0 ? spanLadderBeats(p.killStepSpanN, S: rate, row: cycleBeats) : 0
                    let origin = period > 0 ? columnStart(originRef, period) : 0
                    beat = killStepPhase(beat, columnMap: p.killStepColumnMap, columnsPerLap: p.killStepColumnsPerLap, steps: p.killStepCount, rateBeats: rate,
                                         periodBeats: period, originOverride: origin)
                }
            }
            j += 1
        }
        return beat
    }
    /// The exact inverse of `driverClockBeat` — walks the SAME range in REVERSE order (undo the last-applied
    /// transform first, since inverting a composition reverses order), used to convert a LOCAL tick a retimed
    /// driver found back to the REAL beat it must schedule its note-on/off at. `originRef` must be the SAME value
    /// passed to `driverClockBeat` for this window, so every slot's origin agrees between the forward and inverse
    /// passes.
    private func driverClockBeatInverse(_ cell: SnapCell, from: Int, to target: Int, atLocalBeat: Double, S: Double, cycleBeats: Double, originRef: Double) -> Double {
        guard target > from else { return atLocalBeat }
        var beat = atLocalBeat
        var j = target - 1
        while j >= from {
            if !cell.slotBypass[j] {
                let p = cell.procs[j]
                if p.type == .clock {
                    let period = p.clockSpanN > 0 ? spanLadderBeats(p.clockSpanN, S: S, row: cycleBeats) : 0
                    let origin = period > 0 ? columnStart(originRef, period) : 0
                    beat = clockDrawnPhaseInverse(beat, originBeat: origin, ratios: p.clockDrawnRatios, glide: p.clockDrawnGlide,
                                                  steps: p.clockDrawnSteps, rateBeats: S)
                } else if p.type == .killStep {
                    let rate = p.killStepRateBeats
                    let period = p.killStepSpanN > 0 ? spanLadderBeats(p.killStepSpanN, S: rate, row: cycleBeats) : 0
                    let origin = period > 0 ? columnStart(originRef, period) : 0
                    beat = killStepPhaseInverse(beat, originBeat: origin, columnMap: p.killStepColumnMap, columnsPerLap: p.killStepColumnsPerLap, firstSlot: p.killStepFirstSlot, steps: p.killStepCount, rateBeats: rate)
                }
            }
            j -= 1
        }
        return beat
    }
    /// KILL STEP MUTE (Paul 2026-09-27): unlike DROP/PAUSE (which are TRANSFORM behaviors — they change what local
    /// beat a downstream driver reads, above), MUTE changes nothing about time — a muted step counts exactly like ON
    /// for `killStepPhase`. Its whole effect is "this note doesn't sound," decided independently, at the note's own
    /// REAL onset — the same per-note-fold shape EUCLID MASK's REST just shipped with. Mirrors `driverClockBeat`'s
    /// own `0..<target` scan (so it composes across more than one preceding KILL STEP the same way the transform
    /// already does), computing each one's OWN real step index directly from `m` (no inversion needed — MUTE doesn't
    /// touch the transform, so the note's real onset already tells us which real step it fell in).
    private func precedingKillStepMuted(_ cell: SnapCell, before target: Int, atRealBeat m: Double, cycleBeats: Double) -> Bool {
        var j = 0
        while j < target {
            if !cell.slotBypass[j], cell.procs[j].type == .killStep {
                let p = cell.procs[j]
                let rate = p.killStepRateBeats
                let period = p.killStepSpanN > 0 ? spanLadderBeats(p.killStepSpanN, S: rate, row: cycleBeats) : 0
                let origin = period > 0 ? columnStart(m, period) : 0
                let stepIdx = posMod(Int(((m - origin) / rate).rounded(.down)), max(1, p.killStepCount))
                if stepIdx < p.killStepMode.count && p.killStepMode[stepIdx] == .mute { return true }
            }
            j += 1
        }
        return false
    }
    /// Widening driver retiming beyond ARP/RIFF/RATCHET-ALL (Paul 2026-09-26: "shouldn't all downstream processors
    /// read an upstream clock, defaulting to the real one if none is present?" — yes). Those three share
    /// `iterateTicks`, which does "shift the search window forward, walk in local time, invert each discovered
    /// tick back" internally. EUCLID and HOCKET already route through `iterateTicks` too (just needed the same 3
    /// arguments wired in) — but BURST/CASCADE/DRONE/SHIFT/HUMANIZE/WEAVE and RATCHET's PATTERN/COIN modes each
    /// compute their OWN one-shot/loop timing directly, with no shared helper to hook into. These two functions
    /// factor out the same pattern for THEM: `clockLocalAnchor` shifts a real anchor point forward into the
    /// clock's local time (so a generator's existing internal math — unchanged — runs relative to where the clock
    /// says "now" is); `clockDriverTiming` takes the resulting local onset/off pair and inverts BOTH back to real
    /// beats, returning a real onset + a real gate length (computed as a difference of two independently-inverted
    /// points, never by "converting a duration" — durations don't invert correctly under a non-uniform transform,
    /// only points do). Both are no-ops (chainDriver < 0, i.e. no driver context at all) or CLOCK-absent (the
    /// underlying `driverClockBeat`/Inverse already no-op when no `.clock` slot is in range) — so every existing
    /// call site that doesn't yet pass through these two functions is unaffected, and every generator's own
    /// column-membership/window-search bounds keep reading the untransformed real beat (the sovereign law: only a
    /// driver's own onset/gate — not which grid column it's active in — should ever see the clock's time).
    private func clockLocalAnchor(_ cell: SnapCell, chainDriver: Int, realAnchor: Double, S: Double, cycleBeats: Double, originRef: Double) -> Double {
        guard chainDriver >= 0 else { return realAnchor }
        return driverClockBeat(cell, from: 0, to: chainDriver, atBeat: realAnchor, S: S, cycleBeats: cycleBeats, originRef: originRef)
    }
    private func clockDriverTiming(_ cell: SnapCell, chainDriver: Int, localOnset: Double, localOff: Double, S: Double, cycleBeats: Double, originRef: Double) -> (onset: Double, gateBeats: Double) {
        guard chainDriver >= 0 else { return (localOnset, max(0.001, localOff - localOnset)) }
        let onset = driverClockBeatInverse(cell, from: 0, to: chainDriver, atLocalBeat: localOnset, S: S, cycleBeats: cycleBeats, originRef: originRef)
        let off = driverClockBeatInverse(cell, from: 0, to: chainDriver, atLocalBeat: localOff, S: S, cycleBeats: cycleBeats, originRef: originRef)
        return (onset, max(0.001, off - onset))
    }
    /// The LAST non-bypassed SPLIT slot after `driver` (last-writer wins), or nil.
    private func downstreamSplitIndex(_ cell: SnapCell, after driver: Int) -> Int? {
        var found: Int? = nil, j = driver + 1
        while j < cell.procs.count { if !cell.slotBypass[j] && cell.procs[j].type == .split { found = j }; j += 1 }
        return found
    }
    /// The FIRST non-bypassed AVOID slot after `driver` that is in AVOID+MOVE mode (the only downstream case that needs the
    /// driver's whole pool as its in-scale MOVE survivor set — B-1 fix), or nil.
    private func downstreamAvoidMoveIndex(_ cell: SnapCell, after driver: Int) -> Int? {
        var j = driver + 1
        while j < cell.procs.count {
            if !cell.slotBypass[j], cell.procs[j].type == .avoid, !cell.procs[j].avoidLock, cell.procs[j].avoidMove { return j }
            j += 1
        }
        return nil
    }
    /// The FIRST non-bypassed GLIDE slot after `driver` (§7①: [driver→GLIDE] v2), or nil. When present, the driver's
    /// notes feed GLIDE's mono voice (emitGlideDriven) rather than sounding — the 303 line. v1: GLIDE is mono, so it
    /// consumes the driver's note directly; set-shapers between driver and GLIDE are ignored (a separate v2 concern).
    private func downstreamGlideIndex(_ cell: SnapCell, after driver: Int) -> Int? {
        var j = driver + 1
        while j < cell.procs.count { if !cell.slotBypass[j] && cell.procs[j].type == .glide { return j }; j += 1 }
        return nil
    }
    private func isDriverType(_ t: ProcessorType) -> Bool {
        switch t {
        case .arp, .ratchet, .strum, .euclid, .burst, .cascade, .drone, .shift, .humanize, .weave, .riff, .hocket: return true
        default: return false
        }
    }
    private func isCoveredChain(_ cell: SnapCell) -> Bool { chainDriverIndex(cell) >= 0 }
    /// A multi-slot chain whose TAIL holds at column boundaries via `emitColumnHolds` (holding the tail's
    /// transform of the composed upstream set): a bypassed tail (passthrough of the upstream set), or a
    /// gate/chance/harmonize tail. A non-bypassed STRUM tail is NOT covered yet → falls back to head-only.
    /// UTILITY (Paul 2026-08-22): the pitch shift a held OCTAVE/TRANSPOSE stage adds to the composed set — folded into
    /// the hold's `transpose`. Other modes = 0 (a no-op for every existing hold type).
    private func holdShift(_ p: SnapParams, mode: CellMode) -> Int {
        switch mode {
        case .octave:    return 12 * Int(p.utilOctave)
        case .transpose: return Int(p.utilTranspose)
        default:         return 0
        }
    }
    /// UTILITY CHANNEL (Paul 2026-08-22): the per-cell output-channel override — the LAST non-bypassed CHANNEL stage's
    /// channel (0-based), or −1 for WIRE (the bus stamp). Whole-cell + position-independent (the chain exits on one channel).
    private func cellChanOverride(_ cell: SnapCell) -> Int16 {
        var out: Int16 = -1
        for j in 0..<cell.procs.count where !cell.slotBypass[j] && cell.procs[j].type == .channel {
            let c = cell.procs[j].utilChannel; if c >= 1 && c <= 16 { out = Int16(c - 1) }   // 0 = WIRE (no override)
        }
        return out
    }
    /// UTILITY NUDGE: the per-cell timing offset in SAMPLES — the sum of non-bypassed NUDGE stages (sixteenths of a
    /// beat), at the live block's beatsPerSample. Applied like the RACK POCKET (shift on/off equally, clamped — no stuck notes).
    private func cellNudgeSamples(_ cell: SnapCell, beatsPerSample: Double, step: Int = 0) -> Int64 {
        guard beatsPerSample > 0 else { return 0 }
        // TIMING LANE (Paul 2026-08-22 §5): a LANE-mode NUDGE reads the offset for THIS step (the cell's column) — the
        // pocket drawn per column; FIXED reads the single offset (byte-identical).
        var ticks = 0
        let s = ((step % 8) + 8) % 8
        for j in 0..<cell.procs.count where !cell.slotBypass[j] && cell.procs[j].type == .nudge {
            let p = cell.procs[j]
            if p.utilNudgeMode == .lane { ticks += s < p.utilNudgeLane.count ? p.utilNudgeLane[s] : 0 }
            else { ticks += p.utilNudge }
        }
        guard ticks != 0 else { return 0 }
        return Int64(((Double(ticks) / 16.0) / beatsPerSample).rounded())
    }
    private func isHoldTailChain(_ cell: SnapCell) -> Bool {
        guard cell.procs.count >= 2, let last = cell.procs.last else { return false }
        if cell.slotBypass.last ?? false { return true }                 // bypassed tail = held passthrough
        switch last.type {
        case .empty, .chance, .harmonize: return true
        case .split: return true                                         // SPLIT tail = a set-membership FILTER over the composed hold ([HARMONIZE → SPLIT] keeps a subset)
        case .avoid: return true                                         // AVOID/LOCK tail = a per-note pitch FILTER over the composed hold ([HARMONIZE → AVOID] drops/snaps clashes)
        case .octave, .transpose: return true                            // UTILITY pitch-shift tail = a per-note SHIFT of the composed hold ([HARMONIZE → OCTAVE])
        case .chords: return true                                        // CHORDS tail = a diatonic SET-REPLACE over the composed hold ([SPLIT → CHORDS] etc.); emitColumnHolds composes it in and sounds the chord
        case .tutti: return last.tuttiMode == .coin                      // TUTTI COIN tail = a per-step SET roll over the composed hold; PATTERN re-articulates (tick loop)
        case .tap: return chainDriverIndex(cell) < 0                     // TAP tail = a held passthrough + its parallel send, but ONLY with no driver ([HARMONIZE→TAP]); [ARP→TAP] stays driver-folded (Paul 2026-08-26)
        default: return false
        }
    }
    /// A NO-DRIVER chain whose last non-bypassed slot is LENGTH, sitting after a composable (hold) upstream —
    /// `[TUTTI COIN → LENGTH]`, `[HARMONIZE → LENGTH]`, `[CHANCE → LENGTH]`, `[SPLIT → LENGTH]`.
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
    /// `[HARMONIZE→ECHO]` / `[CHANCE→ECHO]`. `emitEchoColumn` registers its tail from the composed upstream set;
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
    /// The first non-bypassed ECHO slot's INDEX (or nil) — §7② the non-driver CHAIN-echo path needs the slot position
    /// so `drainEchoTails`/`refoldEchoRepeat` can re-fold each repeat through the stages AFTER it.
    private func chainEchoIndex(_ cell: SnapCell) -> Int? {
        for i in 0..<cell.procs.count where !cell.slotBypass[i] && cell.procs[i].type == .echo { return i }
        return nil
    }

    /// TUTTI PATTERN (standalone): render the held set as an authored SHAPE per slice, clocked at the slice rate — a
    /// per-slice re-articulator. TUTTI is not a driver; only a single-slot PATTERN cell reaches here (a chain routes
    /// its driver/hold instead). The 8-slice pattern walks GLOBALLY (ROTATE offsets it) so it strides the bar. No stuck
    /// notes: every strike carries an explicit off sample through emitArtic, the same lifecycle the generators use.
    private func emitTuttiPatternRow(cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int, emits: Bool,
                                     pool: NotePool, beatPos: Double, windowBeats: Double, windowStart: Int64,
                                     windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                                     out: MIDIEmitter?, diag: inout KernelDiag) {
        let p = machine.a
        // SPAN LADDER (Paul 2026-08-22, RATE×ladder): when tuttiSpanN>0, the RATE is the slice width and SPAN N sets the
        // loop PERIOD in columns (the pattern re-anchors every N columns → polymeter). tuttiSpanN==0 keeps the LEGACY
        // CELL|ROW path (byte-identical): CELL strides the 8-slice pattern at the RATE; ROW spans the 8 slices over the bar.
        // cycleBeats (Paul 2026-10-05) is the row's REAL pass length, not a hardcoded Double(Snap.cols) * S — matters
        // the moment this row's part is wider than 8 columns or runs a custom rate (same bug class as the EUCLID fix).
        let tuttiLadder = p.tuttiSpanN > 0
        let tuttiSpanBeats = tuttiLadder ? spanLadderBeats(p.tuttiSpanN, S: S, row: cycleBeats) : 0
        let sub = tuttiLadder ? max(0.03125, p.tuttiSliceBeats)
                              : ((p.tuttiSpan == .row) ? max(0.03125, cycleBeats / 8.0) : max(0.03125, p.tuttiSliceBeats))
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        fillSrcFromPool(cell, pool)
        let srcNotes = srcNoteBuf[0..<srcNoteCount]   // view, no alloc — 0-based indices match the old array
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
            let idx: Int
            if tuttiLadder {   // re-anchor the slice walk every N columns (the loop period) → polymeter
                let localG = Int(((tau - columnStart(tau, tuttiSpanBeats)) / sub).rounded(.down))
                idx = (((localG + p.tuttiRotate) % 8) + 8) % 8
            } else {
                idx = (((g + p.tuttiRotate) % 8) + 8) % 8
            }
            let (rankCount, oct) = tuttiSliceRanksInto(&tuttiRankBufA, idx < p.tuttiSlices.count ? p.tuttiSlices[idx] : .all, count: count)
            guard rankCount > 0 else { continue }                  // REST → silent slice
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
            for ri in 0..<rankCount {
                let rank = tuttiRankBufA[ri]; guard rank >= 0 && rank < count else { continue }
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
    private func emitLengthRow(cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int, emits: Bool,
                               pool: NotePool, beatPos: Double, windowBeats: Double, windowStart: Int64,
                               windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                               out: MIDIEmitter?, diag: inout KernelDiag) {
        guard S > 0 else { return }
        let p = machine.a
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        fillSrcFromPool(cell, pool)
        let srcNotes = srcNoteBuf[0..<srcNoteCount]   // view, no alloc — 0-based indices match the old array
        guard !srcNotes.isEmpty else { return }
        // SPAN: CELL fits the 8 slices in each column; ROW stretches them across the whole BAR (slice i = column i) → a
        // whole-bar trance-gate phrase. Only the span width changes; the window gate keeps each cell to its own slice.
        // cycleBeats (Paul 2026-10-05) is the row's REAL pass length, not a hardcoded Double(Snap.cols) * S.
        let span = spanLadderBeats(p.lenSpanN, S: S, row: cycleBeats)   // SPAN LADDER (Paul 2026-08-22)
        var col = columnStart(mWinStart, span)
        while col < mWinEnd {
            let evN = lengthColumnEventsInto(&lenEventBuf, slices: p.lenSlices, rotate: p.lenRotate, shortFrac: p.lenShort, longFrac: p.lenLong, colStart: col, S: span)
            for ei in 0..<evN {
                let e = lenEventBuf[ei]
                guard e.on >= mWinStart && e.on < mWinEnd else { continue }
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
            col += span
        }
    }

    /// LENGTH after a non-driver, composable upstream — `[TUTTI COIN → LENGTH]`, `[HARMONIZE → LENGTH]`,
    /// `[CHANCE → LENGTH]`, `[SPLIT → LENGTH]`. LENGTH isn't a note-DRIVER, so its gate never
    /// reached the per-note fold (emitDriverNote) and was silently dropped. Re-articulate the COMPOSED upstream set
    /// (composeChainSet up to the slot before LENGTH) through LENGTH's 8-slice gate — recomposed at each column start
    /// so per-step-seeded upstreams (TUTTI COIN / CHANCE) stay loop-consistent. Same emitArtic lifecycle + step-capped
    /// offs as emitLengthRow → no stuck notes. (Paul 2026-08-17)
    private func emitLengthComposedRow(cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int, emits: Bool,
                                       lenIdx: Int, pool: NotePool, beatPos: Double, windowBeats: Double,
                                       windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double,
                                       a: Double, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard S > 0, lenIdx >= 1, lenIdx < cell.procs.count else { return }
        let lp = cell.procs[lenIdx]
        let echoMuteDry = (chainEchoParams(cell)?.echoThru == false)   // §7② [ECHO→…→LENGTH] MUTE: echoes only — suppress the length-gated dry (the tails register in emitEchoColumn)
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let cellPool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: frozen chord if armed
        let cycleBeats = Double(Snap.cols) * S
        let span = spanLadderBeats(lp.lenSpanN, S: S, row: cycleBeats)   // SPAN LADDER (Paul 2026-08-22)
        var col = columnStart(mWinStart, span)
        while col < mWinEnd {
            composeChainSet(cell: cell, pool: cellPool, upto: lenIdx - 1, m: col, S: S, cycleBeats: cycleBeats)   // the upstream set at this span-unit start
            let cnt = chainScratch.srcCount(filter: 0, cableMask: 0b1111)
            if cnt > 0 {
                let evN = lengthColumnEventsInto(&lenEventBuf, slices: lp.lenSlices, rotate: lp.lenRotate, shortFrac: lp.lenShort, longFrac: lp.lenLong, colStart: col, S: span)
                for ei in 0..<evN {
                    let e = lenEventBuf[ei]
                    guard e.on >= mWinStart && e.on < mWinEnd else { continue }
                    let onT = sampleOf(musical: e.on, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    let offT = sampleOf(musical: e.off, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    let tbm = chopMask(cell, m: e.on, S: S, base: bm)
                    for k in 0..<cnt {
                        let src = chainScratch.srcAscending(k, filter: 0, cableMask: 0b1111)
                        let n = Int(src) + transpose
                        guard n >= 0 && n <= 127 else { continue }
                        let v = max(1, chainScratch.velocity(src))
                        storeArtic(row: r, on: onT, off: offT, note: UInt8(n), beat: e.on)
                        if emits && tbm != 0 && !echoMuteDry { emitArtic(note: UInt8(n), busMask: tbm, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: v, out: out, diag: &diag) }
                    }
                }
            }
            col += span
        }
    }

    /// Transform note set `src` → `dst` (dst pre-reset) by ONE stage at beat m — a pure, window-independent
    /// derivation: identity/gate/ratchet/strum pass the set, a closed gate empties it, chance drops by
    /// probability, harmonize expands to voices, an ARP mid-chain collapses the set to its one note at m.
    // CLOCK (Paul 2026-09-26, Stage 3): `clockFrom`/`atSlot` — when both ≥0 (the emitDriverNote fold call site passes
    // `driver + 1`/this slot's own index j) — let the ONE self-clocked case below (.tutti) read a CLOCK-transformed
    // beat for its OWN step/rate math, same mechanism as RATCHET/VELOCITY/DEST. Every other mode here ignores them
    // entirely (they don't read `m` as a self-clock at all — ARP/CHANCE/etc. still key off the raw beat, untouched);
    // default -1 ⇒ byte-identical to every pre-existing call site (composeChainSet's upstream re-pooling, the echo-
    // repeat refold — neither is "downstream of a driver", so CLOCK has nothing to transform there in this pass).
    private func applyStage(_ p: SnapParams, mode: CellMode, src: NotePool, into dst: NotePool,
                            cell: SnapCell, m: Double, S: Double, cycleBeats: Double, clockFrom: Int = -1, atSlot: Int = -1) {
        switch mode {
        case .silent:
            break                                              // a silenced downstream stage → empty
        case .arp:
            var arpBeats = Snap.arpRateBeats[Int(max(0, min(Int8(Snap.arpRateBeats.count - 1), p.rateIndex)))]
            if arpBeats <= 0 { arpBeats = 0.25 }
            let tick = Int64((m / arpBeats).rounded(.down))
            let pIdx = phaseIndex(tick: tick, mTickBeat: Double(tick) * arpBeats, arpBeats: arpBeats, S: S,
                                  cycleBeats: cycleBeats, phase: p.phase, runStartColumn: cell.runStartColumn)
            let pick = arpPick(phaseIndex: pIdx, octaves: Int(p.octaves), pattern: p.patternIndex,
                               pool: src, filter: 0, cableMask: 0b1111,
                               octDown: p.arpOctDown, randomAnchor: p.arpRandomAnchor, seed: p.arpSeed)   // velocity inherited from the picked source note
            if pick.note >= 0 && pick.note <= 127 { dst.noteOn(UInt8(pick.note), velocity: max(1, pick.vel), channel: 0) }
        case .chance:
            let colStart = columnStart(m, S)
            let chanceBase = effectiveProbability(p, step: Int((colStart / S).rounded()))   // CHANCE PATTERN: per-step odds
            let cCnt = src.srcCount(filter: 0, cableMask: 0b1111)
            for k in 0..<cCnt {
                let n = src.srcAscending(k, filter: 0, cableMask: 0b1111)
                if chancePassesPool(beat: colStart, note: Int(n), rank: k, count: cCnt, probability: chanceBase, tilt: p.chanceTilt, constantDensity: p.chanceDensity) { dst.noteOn(n, velocity: max(1, src.velocity(n)), channel: 0) }
            }
        case .tutti:                                           // [TUTTI→ARP]: reshape the source pool per step/slice
            let mClock = clockFrom >= 0 && atSlot >= 0 ? clockTransformedBeat(cell, from: clockFrom, to: atSlot, atBeat: m, S: S, cycleBeats: cycleBeats) : m
            let cCnt = src.srcCount(filter: 0, cableMask: 0b1111)
            if p.tuttiMode == .coin {
                var solo = -1                                   // −1 = TUTTI (whole set passes)
                let step = S > 0 ? Int((columnStart(mClock, S) / S).rounded()) : 0
                if !tuttiIsTutti(step: step, balance: p.tuttiBalance) { solo = tuttiSoloRank(step: step, count: cCnt, pick: p.tuttiPick) }
                for k in 0..<cCnt where solo < 0 || k == solo {
                    let n = src.srcAscending(k, filter: 0, cableMask: 0b1111)
                    dst.noteOn(n, velocity: max(1, src.velocity(n)), channel: 0)
                }
            } else {                                            // PATTERN: the authored slice shape at beat m
                let sub = max(0.03125, p.tuttiSliceBeats)
                let idx = (((tuttiSliceOf(mClock, sliceBeats: sub) + p.tuttiRotate) % 8) + 8) % 8
                let (rankCount, oct) = tuttiSliceRanksInto(&tuttiRankBufB, idx < p.tuttiSlices.count ? p.tuttiSlices[idx] : .all, count: cCnt)
                for ri in 0..<rankCount {
                    let rank = tuttiRankBufB[ri]; guard rank >= 0 && rank < cCnt else { continue }
                    let n = src.srcAscending(rank, filter: 0, cableMask: 0b1111)
                    let shifted = Int(n) + oct
                    if shifted >= 0 && shifted <= 127 { dst.noteOn(UInt8(shifted), velocity: max(1, src.velocity(n)), channel: 0) }
                }
            }
        case .harmonize:
            let iv0 = p.harmIntervals.0, iv1 = p.harmIntervals.1, iv2 = p.harmIntervals.2   // unrolled — no per-stage array alloc (render path)
            // §2 POOL-STEP: an interval is either semitones (base+iv) or pool DEGREES against the source pool (base stepped
            // iv places up the scale/chord — the diatonic third, no inference). The pitch-class mask is computed ONCE (no alloc).
            let harmPool = p.harmUnits == .pool
            let harmMask: UInt16 = harmPool ? src.pitchClassMaskAll() : 0
            @inline(__always) func harmVoice(_ base: Int, _ iv: Int8) -> Int { harmPool ? poolStepMask(base, steps: Int(iv), pcMask: harmMask) : base + Int(iv) }
            for k in 0..<src.srcCount(filter: 0, cableMask: 0b1111) {
                let base = Int(src.srcAscending(k, filter: 0, cableMask: 0b1111))
                let bv = max(1, src.velocity(UInt8(base)))                // the added voices inherit the base note's velocity
                dst.noteOn(UInt8(base), velocity: bv, channel: 0)
                if iv0 != 0 { let v = harmVoice(base, iv0); if v >= 0 && v <= 127 { dst.noteOn(UInt8(v), velocity: bv, channel: 0) } }
                if iv1 != 0 { let v = harmVoice(base, iv1); if v >= 0 && v <= 127 { dst.noteOn(UInt8(v), velocity: bv, channel: 0) } }
                if iv2 != 0 { let v = harmVoice(base, iv2); if v >= 0 && v <= 127 { dst.noteOn(UInt8(v), velocity: bv, channel: 0) } }
            }
        case .chords:                                          // HARMONY — a held note TRIGGERS; the derived diatonic chord for the current degree REPLACES the set
            let cCnt = src.srcCount(filter: 0, cableMask: 0b1111)
            if cCnt > 0 {                                       // no input = no trigger → silent
                let lo = src.srcAscending(0, filter: 0, cableMask: 0b1111)   // the lowest input note (the trigger)
                // STEPS+RATE (Paul 2026-09-01): the progression advances on its OWN clock (chordsRateBeats), NOT per grid
                // column — so it steps at a musical tempo and plays THROUGH even on a frozen/pinned audition (m keeps
                // advancing). `step` = the free-running rate-tick index; PATTERN loops it over chordsSteps.
                // C2b (Paul 2026-09-01): CHORDS reads its KEY from the REFERENCED door — SCALE FROM ▸A–D, a receiver set to
                // SCALE. The cell's OWN input is the TRIGGER (FOLLOW names the degree from the note you play); this separate
                // door supplies root+scale. No valid scale reference ⇒ the C-major fallback (p.chordsRoot/Scale, default C).
                let ref = p.chordsScaleRef   // −1 = none
                let doorScale = (ref >= 0 && ref < receiverScaleRoot.count && receiverScaleRoot[ref] >= 0)
                let root = doorScale ? receiverScaleRoot[ref] : p.chordsRoot
                let scaleTones = doorScale ? receiverScaleType[ref].intervals : p.chordsScale.intervals
                // The degree→chord derivation (STEPS/RATE/PATTERN/WALK/FOLLOW) is SHARED with the chord DOOR via chordSeqNotes
                // — one source of truth so future CHORDS work reflects on both. `m` is the raw beat (steps on tempo, plays
                // through a pinned audition); FOLLOW names the degree from the trigger `lo`.
                let vel = max(1, src.velocity(lo))              // the trigger's velocity
                for n in chordSeqNotes(beat: m, p, keyRoot: root, keyTones: scaleTones, followNote: Int(lo)) {
                    dst.noteOn(UInt8(n), velocity: vel, channel: 0)
                }
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
        case .avoid:                                           // per-note PITCH filter — RE-POOL upstream / hold-tail: drop or snap each note vs the reference
            let refMask = avoidRefMask(p, ownDoor: Int(cell.resolvedReceiver), ownBusMask: cell.busMask)
            let srcN = src.srcCount(filter: 0, cableMask: 0b1111)
            // AVOID MOVE lands only on the input scale's SURVIVING notes (never a chromatic note outside the pool). The
            // survivor pool is `src` (the whole set upstream/hold-tail), OR the DRIVER's whole output pool when AVOID sits
            // DOWNSTREAM of a driver and `src` is a single note (avoidDriverSurvivor, resolved per column — B-1 fix, so
            // [ARP→AVOID(move)] snaps in-scale like a standalone AVOID instead of degrading to DROP). Paul 2026-08-31.
            let survivorMask: UInt16 = (!p.avoidLock && p.avoidMove)
                ? (avoidDriverSurvivorValid ? avoidDriverSurvivor : avoidSurvivors({ Int(src.srcAscending($0, filter: 0, cableMask: 0b1111)) }, count: srcN, refMask: refMask))
                : 0
            for k in 0..<srcN {
                let n = src.srcAscending(k, filter: 0, cableMask: 0b1111)
                if let outN = avoidFilter(Int(n), p, refMask: refMask, survivorMask: survivorMask), outN >= 0, outN <= 127 { dst.noteOn(UInt8(outN), velocity: max(1, src.velocity(n)), channel: 0) }
            }
        case .octave, .transpose:                              // UTILITY — pitch shift (pitch-class preserved for OCTAVE); out-of-range notes drop
            // §2 POOL-STEP: TRANSPOSE in POOL units steps each note by utilTranspose DEGREES up the source pool ("up a
            // third in key"); OCTAVE stays ×12 semitones (an octave has no pool meaning). Mask computed once (no alloc).
            let transPool = (mode == .transpose) && p.utilTransposeUnits == .pool
            let transMask: UInt16 = transPool ? src.pitchClassMaskAll() : 0
            let sh = (mode == .octave) ? 12 * Int(p.utilOctave) : Int(p.utilTranspose)
            for k in 0..<src.srcCount(filter: 0, cableMask: 0b1111) {
                let sn = src.srcAscending(k, filter: 0, cableMask: 0b1111)
                let n = transPool ? poolStepMask(Int(sn), steps: Int(p.utilTranspose), pcMask: transMask) : Int(sn) + sh
                if n >= 0 && n <= 127 { dst.noteOn(UInt8(n), velocity: max(1, src.velocity(sn)), channel: 0) }
            }
        default:                                               // identity / ratchet / strum → pass through
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
                let mode = cellMode(type: cell.procs[j].type, bypassed: false)
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
    /// driver+1…tail (chance drops, harmonize expands, bypassed passes) and
    /// each surviving note is emitted. Reuses chainA/chainB (fixed pools — no render-thread alloc); safe to call
    /// after composeChainSet has produced the driver's source (chainScratch is no longer needed by this tick).
    private func emitDriverNote(_ note: Int, cell: SnapCell, driver: Int, bm: UInt8,
                                onSample: Int64, offSample: Int64, windowEnd: Int64, velocity: UInt8,
                                m: Double, S: Double, cycleBeats: Double, beatsPerSample: Double, pass: Int, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard note >= 0 && note <= 127 else { return }
        // KILL STEP MUTE (Paul 2026-09-27): checked FIRST, before even the driver-is-tail shortcut below — a bare
        // [KILL STEP→ARP] chain (nothing after the driver) takes that shortcut straight to emitChop, so a fold check
        // placed any later (alongside EUCLID MASK's, further down) would never see it.
        if precedingKillStepMuted(cell, before: driver, atRealBeat: m, cycleBeats: cycleBeats) { return }
        // §7① [driver→GLIDE] v2: a downstream GLIDE slot consumes the driver's note as a target for its mono gliding
        // voice — RECORD it (post-tick emitGlideDriven anchors/bends) and SUPPRESS the note-on here. Keyed by the
        // emitting cell's grid index (currentCellIndex, set per-cell in emitTickRow). Multi-emitter fan-out is v2.
        if currentCellIndex >= 0 && currentCellIndex < Snap.cells, downstreamGlideIndex(cell, after: driver) != nil {   // was < 64 (dropped [driver→GLIDE] for cols 4–7)
            let ci = currentCellIndex, k = glideDrivenCount[ci]
            if k < Self.glideDrivenCap {
                glideDrivenNote[ci * Self.glideDrivenCap + k] = Int16(note)
                glideDrivenBeat[ci * Self.glideDrivenCap + k] = m
                glideDrivenVel[ci * Self.glideDrivenCap + k] = velocity
                glideDrivenCount[ci] = k + 1
            }
            return
        }
        // RECORDER capture (AcceptanceCriteria-recorder): a downstream RECORDER records the driver's notes during its
        // record window (transparent — the note still plays); once its loop is committed it plays back separately in
        // emitColumnRecorder, and REPLACE suppresses the live note here. Phase = a pure fn of the pass/step number.
        if currentCellIndex >= 0 && currentCellIndex < Snap.cells, let rs = downstreamRecorder(cell, after: driver) {
            let ci = currentCellIndex, rp = cell.procs[rs]
            if rp.recMode == .canon {
                // CANON: always record into the current window's ring (reset at boundaries in emitColumnRecorder); LAYER
                // (never suppress — the live note keeps playing while its recording chases it one window later).
                let k = recCapN[ci]
                if k < Router.recNoteCap {
                    let w = recWindow(rp, passBeats: cycleBeats, stepBeats: S)
                    let win = max(0.03125, w.window)
                    let x = ci * Router.recNoteCap + k
                    recCapStart[x] = m - (m / win).rounded(.down) * win
                    recCapNote[x] = UInt8(note); recCapVel[x] = velocity
                    recCapGate[x] = max(0.01, Double(offSample - onSample) * beatsPerSample)
                    recCapN[ci] = k + 1
                }
                // fall through — LAYER
            } else if recCaptured[ci] {
                if rp.recMix == .replace { return }               // committed loop → the live note is suppressed (the loop plays in emitColumnRecorder)
            } else if recArmUnit[ci] != Int.min {
                // RECORDING: the record window is [recArmUnit, recArmUnit + N) (rolls on a REFRESH re-arm). Capture the
                // note (start relative to the window origin), then pass through (transparent). recArmUnit is set in
                // emitColumnRecorder on (re)arm; Int.min = not yet armed (pre-arm on ARM AFTER-N) → pass through.
                let w = recWindow(rp, passBeats: cycleBeats, stepBeats: S)
                let unit = Int((m / w.unitBeats).rounded(.down))
                let n = max(1, w.endUnit - w.startUnit)
                if unit >= recArmUnit[ci] && unit < recArmUnit[ci] + n {
                    let k = recCapN[ci]
                    if k < Router.recNoteCap {
                        let base = Double(recArmUnit[ci]) * w.unitBeats
                        let x = ci * Router.recNoteCap + k
                        recCapStart[x] = m - base
                        recCapNote[x] = UInt8(note)
                        recCapVel[x] = velocity
                        recCapGate[x] = max(0.01, Double(offSample - onSample) * beatsPerSample)
                        recCapN[ci] = k + 1
                    }
                }
            }
        }
        if driver >= cell.procs.count - 1 {                       // driver IS the tail → no post-stages
            emitChop(note, cell: cell, bm: bm, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: velocity, m: m, S: S, out: out, diag: &diag)
            return
        }
        // `pass` is the authoritative lap counter (diag.pass) — the SAME one a stand-alone chance gate reads, so a
        // downstream gate opens/closes on the lap the user sees (not a beat-derived recomputation that can drift).
        var cur = chainA, nxt = chainB
        cur.reset(); cur.noteOn(UInt8(note), velocity: velocity, channel: 0); cur.rebuildSorted()
        // ECHO in a chain repeats the cell's FULLY-PROCESSED output (user 2026-08-09): it passes through the fold as
        // identity and registers its tails AFTER every downstream stage has run — so a stage after it (HARMONIZE,
        // GATE, …) shapes the echoes too, honouring "each stage receives its parent's output". THRU keeps the dry,
        // MUTE drops it (echoes only). (v1: echo's chain POSITION no longer changes the tail's content — it always
        // echoes the final set; per-repeat-as-it-fires processing is the deeper "hand the tails" work.)
        var echoP: SnapParams? = nil
        var lenP: SnapParams? = nil   // LENGTH downstream (last-writer wins): overrides each onset's gate by its slice
        var shiftP: SnapParams? = nil   // SHIFT downstream (Paul 2026-09-06): a fixed late push per note
        var humanP: SnapParams? = nil   // HUMANIZE downstream: seeded per-note timing + velocity jitter
        var velP: SnapParams? = nil     // VELOCITY downstream (Paul 2026-09-07): a per-step velocity OVERRIDE; note-transparent, applied at the final emit
        var velIdx = -1                 // its slot index (Paul 2026-09-26, CLOCK Stage 3) — so its own rate math can read a CLOCK-transformed beat
        var j = driver + 1
        avoidDriverSurvivorValid = true   // downstream fold: a [driver→AVOID(move)] snaps onto the driver's whole-pool survivors (resolved above), not the single driven note (B-1)
        defer { avoidDriverSurvivorValid = false }
        while j < cell.procs.count {
            if !cell.slotBypass[j] {   // true-bypass passes untouched
                if cell.procs[j].type == .echo {
                    echoP = cell.procs[j]   // hold the params; DIRECT registers over the final folded set (below)
                    if cell.procs[j].echoRoute == .chain {   // §7② CHAIN: seed from the set reaching ECHO's INPUT (cur so far); drainEchoTails re-folds each repeat through slots j+1…tail
                        let echoBM = chopMask(cell, m: m, S: S, base: bm, clockFrom: driver + 1, cycleBeats: cycleBeats)
                        for kk in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) {
                            let sn = cur.srcAscending(kk, filter: 0, cableMask: 0b1111)
                            pushEchoForNote(Int(sn), vel: max(1, cur.velocity(sn)), bm: echoBM, p: cell.procs[j], onset: m, S: S,
                                            route: .chain, cellIdx: currentCellIndex, echoSlot: j)
                        }
                    }
                } else if cell.procs[j].type == .mod || cell.procs[j].type == .glide {
                    // MOD/GLIDE are note-transparent in the fold — their output is emitted separately (v1: [driver→GLIDE] plays the driver).
                } else if cell.procs[j].type == .length {
                    lenP = cell.procs[j]   // note-transparent SET-wise; its gate override lands on the final emit (below)
                } else if cell.procs[j].type == .split {
                    // SPLIT downstream is a per-note MEMBERSHIP filter against the driver's pool — applied at the final emit
                    // via the row-loop-resolved gate (splitGate*), not as a set transform here (src is a single note).
                } else if cell.procs[j].type == .tap {
                    // TAP (AcceptanceCriteria-tap-processor): emit the stream AS-IT-STANDS here to the tap wire (LEVEL-scaled)
                    // AND pass it on unchanged — [ARP→TAP→HARM] = the straight walk + the harmonized walk, simultaneously.
                    // THIS WIRE (0) layers on the cell's output; A–D emits on that emitter (the parallel out). No cur change.
                    let tp = cell.procs[j]
                    if !tp.tapMute {
                        let tapBM: UInt8 = tp.tapTo == 0 ? bm : (UInt8(1) << UInt8(max(0, min(3, tp.tapTo - 1))))
                        for kk in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) {
                            let tn = cur.srcAscending(kk, filter: 0, cableMask: 0b1111)
                            let tv = clampVel(Int((Double(max(1, cur.velocity(tn))) * tp.tapLevel).rounded()))
                            emitArtic(note: tn, busMask: tapBM, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: tv, out: out, diag: &diag)
                        }
                    }
                } else if cell.procs[j].type == .ratchet {
                    // COIN PASS-THROUGH fold (Paul 2026-09-06): note-TRANSPARENT in the set fold — its burst-or-pass is applied
                    // at the FINAL emit (below), so the note reaches it unchanged. (A ratchet is only downstream if it's a fold;
                    // a driving ratchet would BE the driver.)
                } else if cell.procs[j].type == .shift {
                    shiftP = cell.procs[j]   // GROOVE (Paul 2026-09-06): a per-note late PUSH; applied at the final emit (note-transparent to the set)
                } else if cell.procs[j].type == .humanize {
                    humanP = cell.procs[j]   // GROOVE: seeded per-note timing + velocity jitter; applied at the final emit
                } else if cell.procs[j].type == .velocity {
                    velP = cell.procs[j]; velIdx = j   // per-step velocity OVERRIDE; note-transparent to the set, applied at the final emit
                } else {
                    let mode = cellMode(type: cell.procs[j].type, bypassed: false)
                    nxt.reset()
                    // CLOCK (Paul 2026-09-26, Stage 3): threads into applyStage's ONE self-clocked case (.tutti) —
                    // every other mode here ignores clockFrom/atSlot entirely, so this is a no-op elsewhere.
                    applyStage(cell.procs[j], mode: mode, src: cur, into: nxt, cell: cell, m: m, S: S, cycleBeats: cycleBeats, clockFrom: driver + 1, atSlot: j)
                    swap(&cur, &nxt)
                }
            }
            j += 1
        }
        // EUCLID MASK fold (Paul 2026-09-27): the arp-only euclid mask pulled out as its own downstream stage — a
        // K-of-N Bjorklund pattern gates THIS driver's notes, whichever driver it is. Ordinal `g` keys off the
        // driver's own nominal step (driverStep, the SAME derivation VELOCITY's NOTE clock uses below) — "1 mask
        // column = 1 driven note" — so it can never disagree with what's actually driving. REST/TIE drop the note on
        // a gap (TIE's gate-extension happened at the PRECEDING hit, mirrored below — exactly like the ARP-embedded
        // mask); CHORD replaces it with a stab off the composed input pool (chainScratch, already populated by the
        // driver's own composeChainSet call just before it invoked this function — no separate pool needed here).
        var maskDropAll = false
        var maskChordP: SnapParams? = nil
        var maskChordPickRange: (lo: Int, hi: Int)? = nil   // nil ⇒ ALL (strike everyone); else an INCLUSIVE range of chainScratch indices (BOTTOM2/TOP2 span two; everything else collapses to lo==hi, one note)
        var maskTieOffBeats = 0.0
        var maskAccentBoost = 0
        if let mi = downstreamMaskFoldIndex(cell, after: driver) {
            let mp = cell.procs[mi]
            let mN = max(2, min(16, mp.maskN ?? 8)), mK = max(1, min(mN, mp.maskK ?? mN))
            let driverStep = max(0.03125, Snap.arpRateBeats[max(0, min(Snap.arpRateBeats.count - 1, Int(cell.procs[driver].rateIndex)))])
            // SPAN (Paul 2026-09-28): re-anchor the pattern's own ordinal to 0 every N notes, sized by the DRIVER's
            // own step (mirrors KILL STEP sizing its own span ladder by its own rate, not the cell's grid step).
            // FREE (0, default) ⇒ g is the raw absolute tick count, byte-identical to before this feature.
            let spanBeats = mp.maskSpanN > 0 ? spanLadderBeats(mp.maskSpanN, S: driverStep, row: cycleBeats) : 0
            let origin = spanBeats > 0 ? columnStart(m, spanBeats) : 0
            let g = Int(((m - origin) / driverStep).rounded(.down))
            let rot = mp.maskRotate ?? 0
            if mK < mN {
                // INVERT (Paul 2026-09-28): play the N−K rests instead — mirrors EUCLID's own euclidInvert exactly.
                var hit = euclidMaskHit(g, k: mK, n: mN, rotate: rot)
                if mp.maskInvert { hit = !hit }
                // FILL (Paul 2026-09-28): every Nth pass overrides the mask entirely — everything plays, no
                // exceptions (bypasses INVERT's own result too, and CHANCE below). `pass` is the SAME authoritative
                // lap counter a stand-alone chance gate reads.
                let isFill = mp.maskFillEvery > 0 && pass % mp.maskFillEvery == 0
                if isFill { hit = true }
                // CHANCE (Paul 2026-09-28): a coin-flip that can only DEMOTE a hit to a gap, never promote a gap to
                // a hit — the deterministic skeleton keeps its shape, chance just thins it (an Elektron-style trig
                // condition). Skipped on a fill pass (fill means "everything, no exceptions"). Seeded on `g` alone —
                // replay-exact, no accumulated state — mirroring HUMANIZE's own inline splitmix64Mix idiom.
                if !isFill && hit && mp.maskChance < 1 {
                    let roll = Double(splitmix64Mix(UInt64(bitPattern: Int64(g)) &+ 0xC2B2AE3D27D4EB4F) & 0xFFFF) / 65535.0
                    if roll >= mp.maskChance { hit = false }
                }
                if !hit {                                                          // GAP
                    if (mp.maskGap ?? .rest) == .chord {
                        maskChordP = mp
                        // CHORD PICK (Paul 2026-09-28): which note(s) of the composed chord this gap strikes —
                        // mirrors the sibling EUCLID driver's own PICK resolution, keyed on "gaps before g" (derived
                        // from the already-tested euclidMaskHitsBefore — no new pure function needed).
                        let count = chainScratch.srcCount(filter: 0)
                        if count > 0 {
                            switch mp.maskChordPick {
                            case .all: maskChordPickRange = nil
                            case .low: maskChordPickRange = (0, 0)
                            case .high: maskChordPickRange = (count - 1, count - 1)
                            // BOTTOM2/TOP2 (Paul 2026-09-28): the two lowest/highest chord tones. Collapses to a
                            // single note when the composed pool is too small (a 1-note "chord") rather than
                            // repeating it or reading out of range.
                            case .bottom2: maskChordPickRange = (0, min(1, count - 1))
                            case .top2: maskChordPickRange = (max(0, count - 2), count - 1)
                            case .cycle, .random:
                                let gapsBefore = g - euclidMaskHitsBefore(g, k: mK, n: mN, rotate: rot)
                                let idx = mp.maskChordPick == .cycle
                                    ? posMod(gapsBefore, count)
                                    : Int(splitmix64Mix(UInt64(bitPattern: Int64(gapsBefore)) &+ 0x9E3779B97F4A7C15) % UInt64(count))
                                maskChordPickRange = (idx, idx)
                            }
                        }
                    } else { maskDropAll = true }                                  // REST or TIE
                } else if (mp.maskGap ?? .rest) == .tie {                          // HIT, TIE: cover the following gap run
                    maskTieOffBeats = Double(euclidMaskTieRun(g, k: mK, n: mN, rotate: rot)) * driverStep
                }
            }
            // ACCENT LAYER (Paul 2026-09-28): fully independent of the gate above — a second K/N/ROTATE test
            // sharing the SAME g (so a SPAN re-anchor keeps both patterns' relative phase stable). K=N (default)
            // ⇒ off, matching the gate's own no-op convention. Applied to the surviving note in the final emit loop.
            if mp.maskAccentK < mp.maskAccentN && euclidMaskHit(g, k: mp.maskAccentK, n: mp.maskAccentN, rotate: mp.maskAccentRotate) {
                maskAccentBoost = mp.maskAccentAmount
            }
        }
        if maskDropAll { return }
        if let mp = maskChordP {
            let cOct = (mp.maskChordOct ?? 0) * 12
            let cVelScale = mp.maskChordVel ?? 1
            let chordGateBeats = max(0.01, mp.maskChordGate ?? 0.6) * S
            let offC = onSample + Int64((chordGateBeats / beatsPerSample).rounded())
            let echoBM = chopMask(cell, m: m, S: S, base: bm, clockFrom: driver + 1, cycleBeats: cycleBeats)
            func stab(_ b: Int) {
                let nv = b + cOct
                guard nv >= 0 && nv <= 127 else { return }
                let cvel = UInt8(max(1, min(127, Int(Double(max(1, chainScratch.velocity(UInt8(b)))) * cVelScale))))
                emitChop(nv, cell: cell, bm: echoBM, onSample: onSample, offSample: offC, windowEnd: windowEnd, velocity: cvel, m: m, S: S, out: out, diag: &diag, clockFrom: driver + 1, cycleBeats: cycleBeats)
            }
            if let range = maskChordPickRange {
                let count = chainScratch.srcCount(filter: 0)
                if count > 0 {   // guard BEFORE constructing the ClosedRange — it traps if lo > hi (e.g. count somehow 0 here)
                    for idx in max(0, range.lo)...min(count - 1, range.hi) { stab(Int(chainScratch.srcAscending(idx, filter: 0))) }
                }
            } else {
                for k in 0..<chainScratch.srcCount(filter: 0) { stab(Int(chainScratch.srcAscending(k, filter: 0))) }
            }
            return
        }
        // RATCHET fold (Paul 2026-09-07): the ratchet is a PASS-THROUGH with its OWN CLOCK — NOT a driver, NOT per arp-note.
        // PATTERN: the ratchet's playhead runs on its OWN RATE (rtcRate, SPAN re-anchors); a note passing through reads
        // whichever column that playhead is on AT THE NOTE'S TIME (col = floor(noteBeat ÷ rtcRate) mod STEPS). 1 = PASS THROUGH
        // (the note as-is) · 2…8 = ratchet it N over the ratchet's own rate slot (spacing rtcRate ÷ N) · never silent. So two
        // 1/8 notes inside one 1/4 column BOTH read that column → both ratchet. COIN: seeded fire over the driver step. Bursts
        // ride the ECHO ring so the copies emit across render blocks.
        var foldBurst = 0; var foldSpacingBeats = 0.0; var foldDecay = 1.0
        if let fi = downstreamRatchetFoldIndex(cell, after: driver) {
            let rp = cell.procs[fi]
            // CLOCK (Paul 2026-09-26, Stage 1 flagship consumer): if a CLOCK stage sits between the driver and this
            // ratchet fold — e.g. [EUCLID→CLOCK 3:2→RATCHET] — the ratchet's OWN rate/slice math below reads the
            // TRANSFORMED beat, not the raw one; note pitch/velocity/gate timing (everything else in this function)
            // still key off the real `m`. No CLOCK in range ⇒ mClock == m (byte-identical, the sovereign law).
            let mClock = clockTransformedBeat(cell, from: driver + 1, to: fi, atBeat: m, S: S, cycleBeats: cycleBeats)
            var slotBeats = Snap.arpRateBeats[max(0, min(Snap.arpRateBeats.count - 1, Int(cell.procs[driver].rateIndex)))]   // COIN: subdivide the driver (arp) step
            if rp.rtcMode == .pattern {
                let steps = max(1, min(32, rp.rtcSteps))
                // CLOCK (Paul 2026-09-07): TIME = the ratchet's OWN RATE grid (col = floor(beat ÷ rtcRate)); NOTE = advance one
                // column PER NOTE through (col = this note's ordinal). NOTE's ordinal is derived from the driver's step (exact
                // for a uniform arp; approximate for a variable-timing driver), and a ratchet burst spreads over the note gap.
                let advBeats = rp.rtcClock == .note ? slotBeats : max(0.03125, rp.rtcRateBeats)   // slotBeats = the driver (arp) step
                let spanBeats = rp.rtcSpanN > 0 ? Double(rp.rtcSpanN) * advBeats : 0  // SPAN = re-anchor every N MATRIX columns; 0 = free-run
                let localBeat = spanBeats > 0 ? (mClock - columnStart(mClock, spanBeats)) : mClock   // re-anchor the playhead phase; else free-run
                let g = Int((localBeat / advBeats).rounded(.down))                    // TIME: which column at this note's time · NOTE: this note's ordinal
                let col = (((g + rp.rtcRotate) % steps) + steps) % steps
                let raw = col < rp.rtcSlices.count ? rp.rtcSlices[col] : 1
                if raw == 0 { cur.reset(); cur.rebuildSorted() }                      // OFF column → MUTE this driven note (unselect-to-mute, Paul 2026-09-08)
                else if raw >= 2 { foldBurst = min(8, raw); slotBeats = advBeats }    // active column → ratchet N over the advance slot (own rate, or the note gap in NOTE mode) · 1 = passthrough
            } else {   // COIN pass-through (velFactor 1.0 in fold mode)
                let step = Int((mClock / S).rounded())
                if rtcCoinFires(step: step, chance: rp.rtcChance, gap: rp.rtcGap, quota: rp.rtcQuota, velFactor: 1.0) {
                    foldBurst = rp.rtcSizeWeights.isEmpty ? rtcCoinCount(step: step, lo: rp.rtcCountLo, hi: rp.rtcCountHi)
                                                          : rtcCoinSize(step: step, weights: rp.rtcSizeWeights)
                }
            }
            if foldBurst > 1 { foldSpacingBeats = slotBeats / Double(foldBurst); foldDecay = max(0.2, 1.0 - rp.ramp * 0.6) }   // BURST FADE ≈ echo decay taper
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
        if let ep = echoP {
            if ep.echoRoute != .chain {   // DIRECT (v1): echo the fully-processed final set (all downstream stages applied)
                // §cell-edit F CHOP: the tail routes through the per-slice split too — it inherits the source note's
                // slice destination, so echoes follow the note (a muted slice → mask 0 → no tail). (user 2026-08-09.)
                let echoBM = chopMask(cell, m: m, S: S, base: bm, clockFrom: driver + 1, cycleBeats: cycleBeats)
                for k in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) {
                    let n = cur.srcAscending(k, filter: 0, cableMask: 0b1111)
                    pushEchoForNote(Int(n), vel: max(1, cur.velocity(n)), bm: echoBM, p: ep, onset: m, S: S)   // each echo inherits its note's velocity
                }
            }   // CHAIN tails were already registered at the ECHO slot (from its INPUT set); drainEchoTails re-folds them.
            if !ep.echoThru { cur.reset(); cur.rebuildSorted() }   // MUTE → echoes only (no dry) — both routes
        }
        // VELOCITY fold (Paul 2026-09-07): a downstream VELOCITY reads its per-step lane at THIS driver note's time and
        // sets the emitted velocity (or PASSTHROUGH = leave the inherited value). CLOCK TIME = col by wall-beat over its
        // own RATE grid; NOTE = advance one column per driver note (col = the driver step's ordinal). SPAN re-anchors the
        // lane every N columns. Computed once (same onset for the whole folded set → every note this step shares it).
        var velOverride: Int? = nil
        if let vp = velP {
            // CLOCK (Paul 2026-09-26, Stage 3): a CLOCK stage between the driver and this VELOCITY fold retimes its
            // OWN lane-step math, same mechanism as RATCHET's fold above — note pitch/timing here is untouched.
            let mClock = velIdx >= 0 ? clockTransformedBeat(cell, from: driver + 1, to: velIdx, atBeat: m, S: S, cycleBeats: cycleBeats) : m
            let steps = max(1, min(32, vp.velSteps))
            let driverStep = Snap.arpRateBeats[max(0, min(Snap.arpRateBeats.count - 1, Int(cell.procs[driver].rateIndex)))]
            let advBeats = vp.velClock == .note ? max(0.03125, driverStep) : max(0.03125, vp.velRateBeats)
            let spanBeats = vp.velSpanN > 0 ? Double(vp.velSpanN) * advBeats : 0
            let localBeat = spanBeats > 0 ? (mClock - columnStart(mClock, spanBeats)) : mClock
            let g = Int((localBeat / advBeats).rounded(.down))
            velOverride = velLaneStep(lane: vp.velLane, pass: vp.velPass, steps: steps, col: g)
        }
        for k in 0..<cur.srcCount(filter: 0, cableMask: 0b1111) {
            let n = cur.srcAscending(k, filter: 0, cableMask: 0b1111)
            if splitGateActive && (Int(n) < splitGateLo || Int(n) > splitGateHi || Int(cur.velocity(n)) < splitGateVF || Int(cur.velocity(n)) > splitGateVC) { continue }   // SPLIT punch-hole → rest
            var baseVel = velOverride ?? max(1, Int(cur.velocity(n)))   // VELOCITY override (nil = passthrough) wins the base; HUMANIZE below can still jitter it
            var onN = onSample, offN = offOut
            // GROOVE MODIFIERS (Paul 2026-09-06): a downstream SHIFT / HUMANIZE re-shapes THIS driver note IN PLACE — the ARP
            // keeps its rhythm, each note is pushed / jittered (SHIFT = a fixed late push · HUMANIZE = seeded per-note timing +
            // velocity jitter, replay-safe by seed = column·note·index). On/off shift together (length preserved), clamped into
            // the window like NUDGE/POCKET. So [ARP→HUMANIZE] humanizes the arp's notes instead of re-pooling the chord.
            if shiftP != nil || humanP != nil {
                var offB: Int64 = 0; var vScale = 1.0
                if let sp = shiftP { offB += Int64((max(0, min(1, sp.spread)) * 0.4 * S / max(1e-9, beatsPerSample)).rounded()) }
                if let hp = humanP {
                    let amt = max(0, min(1, hp.spread))
                    let colu = UInt64(bitPattern: Int64((m / S).rounded()))
                    let h = splitmix64Mix(colu &* 2_654_435_761 &+ UInt64(n) &* 131 &+ UInt64(k) &* 17)
                    offB += Int64((Double(h & 0xFFFF) / 65535.0 * amt * 0.15 * S / max(1e-9, beatsPerSample)).rounded())
                    vScale *= max(0.05, (100.0 - Double((h >> 16) & 0xFFFF) / 65535.0 * amt * 45.0) / 100.0)
                }
                if offB != 0 { let len = max(1, offN - onN); onN = min(windowEnd, onSample + offB); offN = onN + len }   // shift both → length preserved, clamped to the block
                baseVel = max(1, Int((Double(baseVel) * vScale).rounded()))
            }
            // EUCLID MASK TIE (Paul 2026-09-27): a hit note covers the following gap run — extend its own gate,
            // mirroring the ARP-embedded mask's identical `off = on + (ties+1)×step×gate` shape.
            if maskTieOffBeats > 0 { offN += Int64((maskTieOffBeats / beatsPerSample).rounded()) }
            // EUCLID MASK ACCENT (Paul 2026-09-28): an additive boost on the surviving note, exactly like RIFF's own ACCENT lane.
            if maskAccentBoost != 0 { baseVel = Int(clampVel(baseVel + maskAccentBoost)) }
            // STRIKE 0 = the driver note itself, at its OWN length (offOut = LENGTH-overridden gate). Then, if the fold
            // ratchet calls for N>1, register N−1 more COPIES spaced over the gap to the next note — via the ECHO ring so
            // they spread across render blocks (each copy keeps the note's own length; overlaps re-articulate cleanly).
            emitChop(Int(n), cell: cell, bm: bm, onSample: onN, offSample: offN, windowEnd: windowEnd, velocity: UInt8(baseVel), m: m, S: S, out: out, diag: &diag, clockFrom: driver + 1, cycleBeats: cycleBeats)
            if foldBurst > 1 && foldSpacingBeats > 0 {
                let noteLenBeats = max(0.01, Double(max(1, offOut - onSample)) * beatsPerSample)
                let echoBM = chopMask(cell, m: m, S: S, base: bm, clockFrom: driver + 1, cycleBeats: cycleBeats)
                pushEchoTail(onset: m, note: n, vel: UInt8(baseVel), busMask: echoBM, timeBeats: foldSpacingBeats, repeats: foldBurst - 1,
                             feedDelay: 1.0, decay: foldDecay, offset: 0, pitch: 0, gateBeats: noteLenBeats)
            }
        }
    }
    /// Register an echo tail for ONE note at beat `onset`. SYNCED delay always works; FREE (ms) works when `tempo > 0`
    /// (the hold-tail path threads it — Paul 2026-08-26). The tick-driver path ([ARP→ECHO]) passes tempo 0, so FREE tick
    /// echo stays deferred there (the tick emitters don't thread tempo).
    private func pushEchoForNote(_ note: Int, vel: UInt8, bm: UInt8, p: SnapParams, onset: Double, S: Double,
                                 tempo: Double = 0, route: EchoRoute = .direct, cellIdx: Int = -1, echoSlot: Int = -1) {
        guard note >= 0 && note <= 127 else { return }
        let timeBeats: Double
        if p.echoSync { timeBeats = Double(p.echoDelayDiv) / 4.0 }
        else if tempo > 0 { timeBeats = max(0.001, p.echoDelayMs / 1000.0 * tempo / 60.0) }   // FREE (ms → beats) — needs tempo
        else { return }   // FREE with no tempo (tick-driver path) — deferred
        pushEchoTail(onset: onset, note: UInt8(note), vel: vel, busMask: bm, timeBeats: timeBeats,
                     repeats: max(1, min(16, p.echoRepeats)), feedDelay: p.echoFeedDelay, decay: p.echoDecay,
                     offset: p.echoOffset, pitch: p.echoPitch, gateBeats: min(timeBeats * 0.9, S * 0.9), spill: p.echoSpill,
                     route: route, cellIdx: cellIdx, echoSlot: echoSlot)
    }
    /// The emit bus-mask for a cell at musical beat `m` after its per-slice CHOP routing (independent main/alt/mute).
    /// CLOCK (Paul 2026-09-26, Stage 3): `clockFrom` — when ≥0 (the driver-fold call sites pass `driver + 1`) — is the
    /// slot a CLOCK stage between it and DEST's own slot would retime; DEST is the ONLY reader (CHOP's `chopSlice` and
    /// MUTE MATRIX's `columnStart` below are unaffected — this doesn't touch note timing, only DEST's own routing read).
    /// Default −1 ⇒ byte-identical to every pre-existing call site (no driver context, or CLOCK not yet reached there).
    private func chopMask(_ cell: SnapCell, m: Double, S: Double, base: UInt8, clockFrom: Int = -1, cycleBeats: Double = 0) -> UInt8 {
        // ONE bounded scan (≤8 procs) for the last DEST + the last MUTE — a proc is never both, so the else-if keeps each
        // "last wins" independently. DEST is the router (overrides CHOP); MUTE (§5) composes on top, removing emitters.
        var destProc = -1, muteProc = -1
        for j in 0..<cell.procs.count where !cell.slotBypass[j] {
            let t = cell.procs[j].type
            if t == .dest { destProc = j } else if t == .muteMatrix { muteProc = j }
        }
        var result: UInt8
        if destProc >= 0 {
            // DEST MATRIX (Paul 2026-08-22 §5, reworked 2026-09-26 — RATCHET-PATTERN-shaped): a routing-class processor that
            // OVERRIDES the emitter per step — the hocket painted (CHOP's dest row generalised); wins over CHOP (DEST is the
            // router). Its step is now driven by DEST's OWN FREE-RUNNING CLOCK (destRateBeats), not `chopSlice` (an 8-way
            // subdivision of the CELL'S OWN column) — that tied the matrix to whatever was driving notes through it, so the
            // lit cell in the editor had nothing to do with the emitter actually heard (the same class of bug RATCHET
            // PATTERN had before it got its own clock — see Router.swift's RATCHET fold comment above). A note passing
            // through reads whichever column DEST's own playhead is on AT THE NOTE'S TIME: col = floor(m ÷ destRateBeats)
            // mod 8. The UI matrix (GridUI's `.dest` case) extrapolates the SAME formula per animation frame, so the lit
            // cell and the audible route are always the same clock. −1 = NONE (no emitter — silence this step).
            let dp = cell.procs[destProc]
            let mClock = clockFrom >= 0 ? clockTransformedBeat(cell, from: clockFrom, to: destProc, atBeat: m, S: S, cycleBeats: cycleBeats) : m
            let rate = max(0.03125, dp.destRateBeats)
            let sl = (((Int((mClock / rate).rounded(.down))) % 8) + 8) % 8
            let d = dp.destSlices
            let e = sl < d.count ? max(-1, min(3, d[sl])) : 0
            result = e < 0 ? 0 : (UInt8(1) << UInt8(e))   // route to exactly this emitter, or none
        } else if cell.chopActive {
            let sl = Int(chopSlice(m, columnBeats: S))
            result = chopBusMask(base, main: (cell.chopMain >> UInt8(sl)) & 1 == 1, alt: (cell.chopAlt >> UInt8(sl)) & 1 == 1,
                                 mute: (cell.chopMute >> UInt8(sl)) & 1 == 1, altMask: cell.chopAltMask)
        } else { result = base }
        // MUTE MATRIX (Paul 2026-08-25 §5): remove the muted emitters for this step, indexed by the GRID COLUMN (0…7) —
        // NOT the chop sub-slice — so it matches CHANCE PATTERN / TIMING LANE: a MUTE machine across a ROW mutes the drawn
        // columns (a hold or a normal-rate driver only ever touches sub-slice 0, so sub-slice muting looked inert). If it
        // empties the mask the note is dropped (emitChop / emitColumnHolds skip a 0 mask → no voice opens → no stuck note).
        if muteProc >= 0 {
            let mm = cell.procs[muteProc].muteSlices
            let col = ((Int((columnStart(m, S) / S).rounded()) % 8) + 8) % 8   // the grid column, like CHANCE PATTERN's step
            result &= ~UInt8(col < mm.count ? max(0, min(15, mm[col])) : 0)
        }
        return result
    }
    /// Emit one note applying the cell's per-slice CHOP routing (the shared tail of every tick emitter).
    /// CLOCK (Paul 2026-09-26, Stage 3): `clockFrom`/`cycleBeats` forward to `chopMask` — see its own doc comment.
    private func emitChop(_ note: Int, cell: SnapCell, bm: UInt8, onSample: Int64, offSample: Int64,
                          windowEnd: Int64, velocity: UInt8, m: Double, S: Double, out: MIDIEmitter?, diag: inout KernelDiag,
                          clockFrom: Int = -1, cycleBeats: Double = 0) {
        guard note >= 0 && note <= 127 else { return }
        let tbm = chopMask(cell, m: m, S: S, base: bm, clockFrom: clockFrom, cycleBeats: cycleBeats)
        if tbm != 0 { emitArtic(note: UInt8(note), busMask: tbm, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: velocity, out: out, diag: &diag) }
    }

    // MARK: - per-row tick emitters (the process() per-window content, one method per processor)

    /// ARP (§3): index the input each tick — MIDI IN → filtered source pool; referencing → the parent's
    /// CURRENT sounding note by derivation, octave-arped by this cell (delta §1 "arpeggiate the arpeggio").
    /// RIFF (SPEC-riff-processor): a DRIVER that plays a stored RANK STENCIL against the held chord — the chord-following
    /// 303. Per tick (at riffRate), the step's RANK resolves to a pool note (`riffResolve` — chord-following), REST for
    /// rank 0; WRAP/OCT applied; ACCENT boosts the played-chord's peak velocity. Mirrors emitArpRow's tick lifecycle so it
    /// composes as a chain driver + folds through CHOP/downstream stages. v1: no TIE/SLIDE (the §5 lanes are stage 2).
    /// RIFF DIRECTION = DRUNK: the stateful step lookup. Advances the per-cell walk AT MOST ONCE per distinct `tick`
    /// (so a render window spanning several new ticks advances once per tick, in order — not once per render call),
    /// reflecting at the walls (a single reflection always suffices since the delta is always ±1/0 and position is
    /// always kept in range). `steps` is a LIVE 1…32 param, so a stored position from a wider stencil is defensively
    /// re-clamped if it's since shrunk. Gated on `!previewMode`, matching DEAL's own "auditioning must not perturb
    /// persisted playback state" convention — an audition reads the current position without advancing it.
    private func riffDrunkStep(ci: Int, tick: Int64, steps: Int, bias: Double, seed: UInt64) -> Int {
        guard ci >= 0, ci < riffDrunkPos.count else { return 0 }
        if previewMode { return riffDrunkPos[ci] < 0 ? 0 : min(steps - 1, riffDrunkPos[ci]) }
        if riffDrunkPos[ci] < 0 { riffDrunkPos[ci] = 0; riffDrunkPrevPos[ci] = -1; riffDrunkLastTick[ci] = tick; return 0 }
        if tick != riffDrunkLastTick[ci] {
            riffDrunkPrevPos[ci] = riffDrunkPos[ci]   // SLIDE's lookback (Paul 2026-09-28): where the walk was before THIS move
            riffDrunkLastTick[ci] = tick
            var np = riffDrunkPos[ci] + riffDrunkDelta(tick: tick, bias: bias, seed: seed)
            if np < 0 { np = -np }
            if np > steps - 1 { np = 2 * (steps - 1) - np }
            riffDrunkPos[ci] = max(0, min(steps - 1, np))
        }
        return riffDrunkPos[ci]
    }
    /// EUCLIDEOUS RIFF ADVANCE, the DRUNK case: the sibling of `riffDrunkStep` above, but HIT-triggered (keyed on
    /// distinct `ord`, a lane's own stateless hit-ordinal) instead of TICK-triggered — "each hit will progress
    /// riff by 1 step," not "each elapsed beat". Sized 4 (one per Euclideous lane), not `Snap.cells`, since
    /// Euclideous is always exactly 4 lines at one fixed, reserved cell. Same `previewMode` guard as
    /// `riffDrunkStep` — an audition pass must not perturb the real, persisted walk.
    /// RESET SPAN (Paul 2026-10-08): `spanStart` is the span-re-anchored beat this hit's window starts at
    /// (NaN when reset-span is OFF, the sentinel for "don't track this"). Every OTHER riff direction resets
    /// for free when a span boundary passes, since `ord` is already derived from the span-re-anchored local
    /// beat and naturally restarts low — DRUNK's walk POSITION doesn't follow from that alone (a random walk's
    /// position depends on its own history, not just "what time is it now"), so this is the one direction that
    /// needs an explicit nudge: when `spanStart` changes from what was last observed, hard-reset the walk to 0,
    /// the exact same "fresh start" treatment the very-first-hit-ever case below already gives it.
    private func euclideousRiffDrunkStep(lane: Int, ord: Int64, steps: Int, bias: Double, seed: UInt64, spanStart: Double, cycleReset: Bool = false) -> Int {
        guard lane >= 0, lane < euclideousRiffDrunkPos.count else { return 0 }
        if previewMode { return euclideousRiffDrunkPos[lane] < 0 ? 0 : min(steps - 1, euclideousRiffDrunkPos[lane]) }
        if euclideousRiffDrunkPos[lane] < 0 {
            euclideousRiffDrunkPos[lane] = 0; euclideousRiffDrunkLastOrd[lane] = ord; euclideousRiffLastSpanStart[lane] = spanStart
            return 0
        }
        // LOCK (Paul 2026-10-09 ferry): the SAME "fresh start" hard-reset the span-boundary branch below
        // already performs, just triggered by a DIFFERENT boundary — this lane's own Euclid pattern
        // completing a lap, signalled by the caller passing `cycleReset: true` on exactly the first hit of
        // each new lap (`hitsUpTo == 1`, already known to the caller — this function has no concept of
        // "hits" or "laps" itself, so it can't detect this boundary on its own). Checked BEFORE the span
        // check below so LOCK still resets even when reset-span is off (spanStart stays NaN, never equal to
        // anything, so that branch alone would never fire for a LOCK-only lane).
        if cycleReset {
            euclideousRiffDrunkPos[lane] = 0; euclideousRiffDrunkLastOrd[lane] = ord
            return 0
        }
        if !spanStart.isNaN, spanStart != euclideousRiffLastSpanStart[lane] {
            euclideousRiffLastSpanStart[lane] = spanStart
            euclideousRiffDrunkPos[lane] = 0; euclideousRiffDrunkLastOrd[lane] = ord
            return 0
        }
        if ord != euclideousRiffDrunkLastOrd[lane] {
            euclideousRiffDrunkLastOrd[lane] = ord
            var np = euclideousRiffDrunkPos[lane] + riffDrunkDelta(tick: ord, bias: bias, seed: seed)
            if np < 0 { np = -np }
            if np > steps - 1 { np = 2 * (steps - 1) - np }
            euclideousRiffDrunkPos[lane] = max(0, min(steps - 1, np))
        }
        return euclideousRiffDrunkPos[lane]
    }
    private func emitRiffRow(cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int,
                             emits: Bool, box: SnapshotBox, pool: NotePool,
                             effColumn: Int, beatPos: Double, windowBeats: Double, windowStart: Int64,
                             windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                             chainDriver: Int = -1,
                             out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: pool)
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)
        let p = machine.a
        let steps = max(1, min(32, p.riffSteps))   // variable length (Paul 2026-08-26): 1…32, so odd lengths give polymeter (was locked to ≤16)
        var riffBeats = p.riffRateBeats; if riffBeats <= 0 { riffBeats = 0.25 }
        let gate = effectiveGate(machine)
        let baseVel = max(1, Int(coinVelFactor(pool) * 127))   // inherit the held chord's peak velocity (accent boosts it)
        if r == diag.activeCellRow { diag.effMorphGold = 0; diag.effRateBeats = riffBeats }
        iterateTicks(row: r, effColumn: effColumn, sub: riffBeats, gateFraction: gate,
                     beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                     beatsPerSample: beatsPerSample, S: S, a: a, columns: max(1, Int((cycleBeats / S).rounded())),
                     clockCell: chainDriver >= 0 ? cell : nil, clockFrom: 0, clockTo: chainDriver, cycleBeats: cycleBeats) { tick, mTickBeat, onTime, offTime in
            // SPAN RE-ANCHOR (Paul 2026-08-27, the universal re-sync model — riff is the first card): FREE (spanN 0) runs
            // the global grid (today, byte-identical); spanN > 0 re-syncs the stencil to step 0 every N columns, so an odd
            // `steps` against an aligning span DRIFTS then SNAPS BACK (polymeter). Pure (derived from the absolute beat +
            // the span constant — no accumulated phase), so replay-exact.
            let phaseBeat = p.riffSpanN > 0 ? (mTickBeat - columnStart(mTickBeat, spanLadderBeats(p.riffSpanN, S: S, row: cycleBeats))) : mTickBeat
            let raw = Int((phaseBeat / riffBeats).rounded(.down))
            // DIRECTION (Paul 2026-09-16, widened to 6 modes Paul 2026-09-28): the stencil playback order. DRUNK is
            // the one stateful mode (keyed on `tick`, NOT `raw` — SPAN-oblivious by construction, see riffDrunkPos);
            // every other mode is `riffStepAt`, the SAME pure formula the TIE lookahead below calls for `raw+k` —
            // one formula, so the current step and "what plays next" can never disagree.
            let riffCi = effColumn * Snap.rows + r   // this cell's grid index — shared by the DRUNK step lookup below and its SLIDE lookback
            let step: Int = p.riffDir == .drunk
                ? riffDrunkStep(ci: riffCi, tick: tick, steps: steps, bias: p.riffDirBias, seed: p.riffDirSeed)
                : riffStepAt(p.riffDir, raw: raw, steps: steps, seed: p.riffDirSeed)
            if step < p.riffTie.count && p.riffTie[step] { return }   // §5 TIE — no new attack; the striking step's off was EXTENDED to cover this step (a held ⌒)
            // POLY (Paul 2026-08-26): a step strikes a SET of ranks (riffMask bits) — a chord that follows the held chord;
            // MONO strikes the single riffRanks[step]. Both share the per-step §5 modifiers.
            let polyMask = p.riffPoly ? (step < p.riffMask.count ? p.riffMask[step] : 0) : 0
            let monoRank = p.riffPoly ? 0 : (step < p.riffRanks.count ? p.riffRanks[step] : 0)
            if p.riffPoly { if polyMask == 0 { return } } else if monoRank < 1 { return }   // REST
            let oct = step < p.riffOct.count ? p.riffOct[step] : 0        // §5 OCT lane (−1·0·+1) — per step (all ranks)
            let accent = step < p.riffAccent.count ? p.riffAccent[step] : 0   // §5 ACCENT lane
            let vel = clampVel(baseVel + accent)
            // §5 TIE: extend the off through the following TIE steps (they skip their own strike above). DIRECTION-
            // AWARE lookahead (Paul 2026-09-28, fixing a bug that predates the 6-mode widening): "the following
            // step" means whatever this RIFF actually plays next — `step+1` only for FORWARD; REVERSE's true next
            // step is `step-1`, and PENDULUM/PING-PONG alternate depending which leg of the bounce we're on. Asking
            // `riffStepAt`/`riffDrunkPeek` for `raw+k`/`tick+k` (the SAME formula the current step above just used,
            // one tick further on) is exact for every mode, not a direction-specific patch bolted onto FORWARD's.
            var tieRun = 0
            while tieRun < steps {
                let ss = p.riffDir == .drunk
                    ? riffDrunkPeek(fromPos: step, tick: tick, aheadBy: tieRun + 1, steps: steps, bias: p.riffDirBias, seed: p.riffDirSeed)
                    : riffStepAt(p.riffDir, raw: raw + tieRun + 1, steps: steps, seed: p.riffDirSeed)
                if ss < p.riffTie.count && p.riffTie[ss] { tieRun += 1 } else { break }
            }
            var effOff = offTime + Int64((Double(tieRun) * riffBeats / beatsPerSample).rounded())
            // §5 SLIDE: glide LEGATO into the next → arm the synth's portamento (CC65) + overlap the boundary so the next
            // note opens before this closes (the 303 slide; feeds a synth in portamento, or a downstream GLIDE SYNTH).
            // Non-slide AFTER a slide clears CC65. Per-step, derived (replay-safe) — emitted once on the lowest bus.
            let isSlide = step < p.riffSlide.count && p.riffSlide[step]
            if isSlide { effOff += Int64((riffBeats * 0.12 / beatsPerSample).rounded()) }
            if emits {
                let sbus = bm.trailingZeroBitCount
                if sbus < 4 {
                    let sch = (busChannels[sbus] &- 1) & 15
                    // DIRECTION-AWARE (Paul 2026-09-28, the TIE-lookahead fix's mirror image): "the PREVIOUS step" means
                    // whatever this RIFF actually played immediately before — `step-1` only for FORWARD. Same fix shape
                    // as TIE: `riffStepAt(raw-1)` is the identical pure formula one tick EARLIER, so it agrees with the
                    // current step by construction. DRUNK can't be algebraically un-walked (a reflected random walk
                    // isn't invertible from its current position alone), so its previous position is simply REMEMBERED
                    // (riffDrunkPrevPos, set in riffDrunkStep) rather than recomputed; −1 ⇒ this is the walk's very
                    // first strike, so there's nothing to have slid from.
                    let prevStep = p.riffDir == .drunk ? riffDrunkPrevPos[riffCi] : riffStepAt(p.riffDir, raw: raw - 1, steps: steps, seed: p.riffDirSeed)
                    let prevSlide = prevStep >= 0 && prevStep < p.riffSlide.count && p.riffSlide[prevStep]
                    if isSlide { out?.emit(sampleTime: onTime, cable: UInt8(sbus + 1), 0xB0 | sch, 65, 127) }
                    else if prevSlide { out?.emit(sampleTime: onTime, cable: UInt8(sbus + 1), 0xB0 | sch, 65, 0) }
                }
            }
            func strikeRank(_ rank: Int) {   // resolve ONE rank against the held/composed chord and emit it (shared by MONO + POLY)
                guard rank >= 1 else { return }
                let base: Int?
                if chainDriver >= 0 {   // [X → RIFF]: derive against the composed upstream set (re-pooled per tick, OMNI)
                    composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: mTickBeat, S: S, cycleBeats: cycleBeats)
                    base = riffResolve(rank: rank, oct: oct, n: chainScratch.srcCount(filter: 0), wrap: p.riffWrap) { Int(chainScratch.srcAscending($0, filter: 0)) }
                } else {
                    base = riffNote(rank: rank, oct: oct, pool: pool, for: cell, wrap: p.riffWrap)
                }
                guard let b = base else { return }
                let noteValue = b + transpose
                guard noteValue >= 0 && noteValue <= 127 else { return }
                storeArtic(row: r, on: onTime, off: effOff, note: UInt8(noteValue), beat: mTickBeat)
                if emits {
                    if chainDriver >= 0 {
                        emitDriverNote(noteValue, cell: cell, driver: chainDriver, bm: bm, onSample: onTime, offSample: effOff,
                                       windowEnd: windowEnd, velocity: vel, m: mTickBeat, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, pass: diag.pass, out: out, diag: &diag)
                    } else {
                        emitChop(noteValue, cell: cell, bm: bm, onSample: onTime, offSample: effOff, windowEnd: windowEnd,
                                 velocity: vel, m: mTickBeat, S: S, out: out, diag: &diag)
                    }
                }
            }
            if p.riffPoly {
                for rank in 1...8 where (polyMask & (1 << (rank - 1))) != 0 { strikeRank(rank) }
            } else {
                strikeRank(monoRank)
            }
        }
    }
    private func emitArpRow(cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int,
                            emits: Bool, box: SnapshotBox, pool: NotePool,
                            effColumn: Int, beatPos: Double, windowBeats: Double, windowStart: Int64,
                            windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                            chainDriver: Int = -1,
                            out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        var arpBeats = effectiveRateBeats(machine)
        let gate = effectiveGate(machine)
        let octaves = effectiveOctaves(machine)
        let velocity = effectiveArpVelocity(machine)   // ARP VELOCITY (Paul 2026-09-30, revised same day): an ABSOLUTE value 1…100 — the input note's own velocity is ignored entirely
        let velTilt = effectiveArpVelTilt(machine)     // ARP VELOCITY TILT −1…1: favours top (+) / bottom (−) of the pool
        if arpBeats <= 0 { arpBeats = 0.25 }
        // SPAN (Paul 2026-09-13, the universal re-anchor model — replaces FIT): FREE (spanN 0) runs the global grid
        // (byte-identical to before); spanN > 0 re-syncs the pattern to index 0 every N columns. Pure (derived from the
        // absolute beat + the span constant, no accumulated phase → replay-exact). Subtracting the span origin from the
        // tick/beat leaves RETRIG unchanged (it already resets per column) and re-anchors FREE per span window.
        let arpSpanBeats = machine.a.arpSpanN > 0 ? spanLadderBeats(machine.a.arpSpanN, S: S, row: cycleBeats) : 0
        if r == diag.activeCellRow { diag.effMorphGold = 0;   diag.effRateBeats = arpBeats }
        // RANDOM is FREE-running (Paul 2026-08-25 fix): a random walk gains nothing from RETRIG's per-column reset — it just
        // re-anchors + repeats the same shuffle every column (so RANDOM ANCHOR pedalled the low note instead of "anchor then
        // shuffle until the next pool cycle"). Using the free `tick` makes the anchor fire once per pool traversal + the
        // shuffle never repeat. Other patterns keep their NEW-CHORD phase.
        let arpIsRandom = arpPatternAt(Int(machine.a.patternIndex)) == .random   // cached cases — no per-tick allocation

        iterateTicks(row: r, effColumn: effColumn, sub: arpBeats, gateFraction: gate,
                     beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                     beatsPerSample: beatsPerSample, S: S, a: a, columns: max(1, Int((cycleBeats / S).rounded())),
                     clockCell: chainDriver >= 0 ? cell : nil, clockFrom: 0, clockTo: chainDriver, cycleBeats: cycleBeats) { tick, mTickBeat, onTime, offTime in
            // SPAN re-anchor: shift the tick + beat back to the span-window origin so the pattern re-syncs to index 0
            // every N columns (spanN 0 ⇒ no shift ⇒ byte-identical). RETRIG cancels out (its per-column reset is
            // preserved); FREE counts from the span origin; RANDOM re-shuffles from the span origin.
            var pTick = tick, pBeat = mTickBeat
            if arpSpanBeats > 0 {
                let origin = columnStart(mTickBeat, arpSpanBeats)
                pTick = tick - Int64((origin / arpBeats).rounded())
                pBeat = mTickBeat - origin
            }
            let pIdx = arpIsRandom ? pTick : phaseIndex(tick: pTick, mTickBeat: pBeat, arpBeats: arpBeats, S: S,
                                  cycleBeats: cycleBeats, phase: machine.a.phase,
                                  runStartColumn: cell.runStartColumn)
            let base: Int
            let srcVel: UInt8   // ARP VELOCITY (Paul 2026-09-30, revised same day): NO LONGER inherited from the picked source note — arpPick now derives this from the VELOCITY/VELOCITY TILT controls directly, ignoring the source's own velocity
            if chainDriver >= 0 {
                // CELL MACHINE: this ARP is the chain DRIVER — arp the composed SET of the stages BEFORE it at this
                // tick (OMNI, past the input filter). Derived per tick → pool-correct (arps ALL upstream voices).
                composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: mTickBeat, S: S, cycleBeats: cycleBeats)
                let pick = arpPick(phaseIndex: pIdx, octaves: octaves, pattern: machine.a.patternIndex,
                                   pool: chainScratch, filter: 0, cableMask: 0b1111,
                                   octDown: machine.a.arpOctDown, randomAnchor: machine.a.arpRandomAnchor, seed: machine.a.arpSeed,
                                   velocity: velocity, velTilt: velTilt)
                guard pick.note >= 0 else { return }
                base = pick.note; srcVel = max(1, pick.vel)
            } else {
                let pick = arpPick(phaseIndex: pIdx, octaves: octaves,
                                   pattern: machine.a.patternIndex, pool: pool, for: cell,
                                   octDown: machine.a.arpOctDown, randomAnchor: machine.a.arpRandomAnchor, seed: machine.a.arpSeed,   // §7 source filter
                                   velocity: velocity, velTilt: velTilt)
                guard pick.note >= 0 else { return }
                base = pick.note; srcVel = max(1, pick.vel)
            }
            let noteValue = base + transpose
            guard noteValue >= 0 && noteValue <= 127 else { return }
            storeArtic(row: r, on: onTime, off: offTime, note: UInt8(noteValue), beat: mTickBeat)
            if emits {
                // §cell-edit F CHOP + the chain's post-driver stages fold onto each arp note (e.g. a downstream chance/harmonize).
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

    /// COIN — ODDS FROM VELOCITY (Paul 2026-08-26 ④): the representative velocity of the held pool (its PEAK, 0…1) — play
    /// harder, more rolls. 1.0 (unity) when the pool is empty (no scaling). Bounded scan of the small held pool; no alloc.
    private func coinVelFactor(_ pool: NotePool) -> Double {
        let n = pool.srcCount(filter: 0); guard n > 0 else { return 1.0 }
        var peak: UInt8 = 0
        for k in 0..<n { let v = pool.velocity(pool.srcAscending(k, filter: 0)); if v > peak { peak = v } }
        return peak == 0 ? 1.0 : Double(peak) / 127.0
    }
    /// RATCHET (§3): re-strike the WHOLE input pool `repeats` times per column, staccato (0.6), velocity ramp.
    /// Not an arp (no index cycling) — every stab is the pool (or the parent's sounding note, when referenced).
    private func emitRatchetRow(cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int,
                                emits: Bool, box: SnapshotBox, pool livePool: NotePool,
                                effColumn: Int, beatPos: Double, windowBeats: Double, windowStart: Int64,
                                windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double,
                                chainDriver: Int = -1,
                                out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: livePool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        let ramp = effectiveRamp(machine)
        let p = machine.a
        if p.rtcMode != .all {   // COIN / PATTERN — strikes-per-step vary, so window-scan (not the fixed-sub iterateTicks)
            emitRatchetModal(mode: p.rtcMode, cell: cell, row: r, transpose: transpose, emits: emits, pool: pool, bm: bm,
                             ramp: ramp, chainDriver: chainDriver, beatPos: beatPos, windowBeats: windowBeats,
                             windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample, S: S, a: a,
                             cycleBeats: cycleBeats, p: p, out: out, diag: &diag)
            return
        }
        let repeats = effectiveRepeats(machine)
        let sub = S / Double(repeats)                          // one repeat every `sub` beats
        if r == diag.activeCellRow { diag.effMorphGold = 0;   diag.effRateBeats = sub }
        iterateTicks(row: r, effColumn: effColumn, sub: sub, gateFraction: 0.6,
                     beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                     beatsPerSample: beatsPerSample, S: S, a: a, columns: max(1, Int((cycleBeats / S).rounded())),
                     clockCell: chainDriver >= 0 ? cell : nil, clockFrom: 0, clockTo: chainDriver, cycleBeats: cycleBeats) { _, mTickBeat, onTime, offTime in
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

    /// RATCHET COIN / PATTERN. COIN: per grid column, a seeded chance to ratchet (a count in [lo,hi]) vs a plain single hit
    /// (window-scanned per column). PATTERN (Paul 2026-09-07, RIFF-shaped): a SELF-CLOCKED step MATRIX — the playhead sweeps
    /// STEPS columns at RATE (its own clock, SPAN re-anchors); each column's COUNT decides passthrough (1) or ratchet (2…8),
    /// subdividing that column's RATE slot. Window-scanned over the absolute beat so it spreads across blocks + free-runs.
    private func emitRatchetModal(mode: RatchetMode, cell: SnapCell, row r: Int, transpose: Int, emits: Bool, pool: NotePool,
                                  bm: UInt8, ramp: Double, chainDriver: Int, beatPos: Double, windowBeats: Double,
                                  windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                                  cycleBeats: Double, p: SnapParams, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard S > 0 else { return }
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a), mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        if mode == .pattern {
            // STANDALONE RATCHET PATTERN (Paul 2026-09-08): a SINGLE-SLOT ratchet-pattern cell is a PASS-THROUGH PROCESSOR
            // of the input, not a generator — handled entirely by emitColumnRatchetPattern (sustain on count-1, ratchet on
            // 2…8, gap on 0, gated on live input). So DON'T generate here. Multi-slot chains ([RATCHET PATTERN→X]) keep the
            // self-clocked generator below for now (flagged follow-up).
            if cell.procs.count <= 1 { return }
            // PATTERN — a SELF-CLOCKED step MATRIX (Paul 2026-09-07, RIFF-shaped): the playhead sweeps STEPS columns at RATE
            // (the ratchet's OWN clock, re-anchored by SPAN — FREE = free-run); each column holds a COUNT — 1 = passthrough
            // (one hit), 2…8 = RATCHET that many (subdividing the column's RATE slot into count staccato sub-strikes). Window-
            // scanned over the ABSOLUTE beat so it spreads across render blocks + free-runs independent of the global grid.
            // Feeds the upstream note (re-clocks the arp). BURST FADE (ramp) tapers velocity across a column's sub-strikes.
            let rate = max(0.03125, p.rtcRateBeats)
            let steps = max(1, min(32, p.rtcSteps))
            let spanBeats = p.rtcSpanN > 0 ? Double(p.rtcSpanN) * rate : 0   // SPAN = re-anchor every N MATRIX columns (N × RATE); 0 = free-run (Paul 2026-09-07)
            // CLOCK (Paul 2026-09-26): the same iterateTicks pattern, built into this hand-rolled loop directly —
            // the window bounds shift into local time, the tick search (which matrix column, which count) runs
            // there unchanged, each sub-strike inverts back to real before the REAL half-open window check.
            let localWinStart = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: mWinStart, S: S, cycleBeats: cycleBeats, originRef: mWinStart)
            let localWinEnd = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: mWinEnd, S: S, cycleBeats: cycleBeats, originRef: mWinStart)
            var tk = Int((localWinStart / rate).rounded(.down)) - 1          // one tick early (a sub-strike can spill into this window)
            while true {
                let tickStart = Double(tk) * rate   // LOCAL
                if tickStart >= localWinEnd { break }
                // which matrix column is the playhead on? re-anchored by SPAN (like RIFF), else free-running; + ROTATE
                let localTick = spanBeats > 0 ? Int(((tickStart - columnStart(tickStart, spanBeats)) / rate).rounded(.down)) : tk
                let col = (((localTick + p.rtcRotate) % steps) + steps) % steps
                let count = max(1, min(8, col < p.rtcSlices.count ? p.rtcSlices[col] : 1))   // 1 = single hit · 2…8 = ratchet · NO REST (Paul 2026-09-07: every column sounds)
                let sub = rate / Double(count)
                for j in 0..<count {
                    let localTau = tickStart + Double(j) * sub
                    let (tau, gate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: localTau, localOff: localTau + sub * 0.6, S: S, cycleBeats: cycleBeats, originRef: mWinStart)
                    if tau < mWinStart || tau >= mWinEnd { continue }   // half-open: fires in exactly one render window (REAL)
                    let tbm = chopMask(cell, m: tau, S: S, base: bm); if emits && tbm == 0 { continue }
                    let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    let offT = sampleOf(musical: tau + gate, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    ratchetStrikeAt(cell: cell, row: r, transpose: transpose, emits: emits, pool: pool, bm: bm, tbm: tbm,
                                    onTime: onT, offTime: offT, m: tau, repIdx: j, count: count, ramp: ramp, chainDriver: chainDriver,
                                    windowEnd: windowEnd, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, out: out, diag: &diag)
                }
                tk += 1
            }
            return
        }
        var col = columnStart(mWinStart, S)
        while col < mWinEnd {
            if mode == .coin {
                let step = Int((col / S).rounded())
                // COIN — SHAPING THE DICE (Paul 2026-08-26): ①④ fire decision (gap/quota/velocity-gated), then ① size pick.
                let ratchets = rtcCoinFires(step: step, chance: p.rtcChance, gap: p.rtcGap, quota: p.rtcQuota,
                                            velFactor: p.rtcOddsVel ? coinVelFactor(pool) : 1.0)
                let count = ratchets ? (p.rtcSizeWeights.isEmpty ? rtcCoinCount(step: step, lo: p.rtcCountLo, hi: p.rtcCountHi)
                                                                 : rtcCoinSize(step: step, weights: p.rtcSizeWeights)) : 1
                let sub = S / Double(max(1, count))
                // CLOCK (Paul 2026-09-26): the COIN decision itself stays keyed to the REAL grid column (`step`,
                // above — column membership is the sovereign law) — only the sub-strikes WITHIN a firing column
                // retime: shift this column's start into local time, run the existing spacing math there, invert
                // each sub-strike back.
                let localCol = clockLocalAnchor(cell, chainDriver: chainDriver, realAnchor: col, S: S, cycleBeats: cycleBeats, originRef: mWinStart)
                for j in 0..<count {
                    let localTau = localCol + Double(j) * sub
                    let (tau, gate) = clockDriverTiming(cell, chainDriver: chainDriver, localOnset: localTau, localOff: min(localCol + S, localTau + sub * 0.6), S: S, cycleBeats: cycleBeats, originRef: mWinStart)
                    guard tau >= mWinStart && tau < mWinEnd else { continue }
                    let tbm = chopMask(cell, m: tau, S: S, base: bm); if emits && tbm == 0 { continue }
                    let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    let offT = sampleOf(musical: tau + gate, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    ratchetStrikeAt(cell: cell, row: r, transpose: transpose, emits: emits, pool: pool, bm: bm, tbm: tbm,
                                    onTime: onT, offTime: offT, m: tau, repIdx: j, count: count, ramp: ramp, chainDriver: chainDriver,
                                    windowEnd: windowEnd, S: S, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, out: out, diag: &diag)
                }
            }
            col += S
        }
    }

    /// Is any RATCHET PATTERN standalone sustain voice active? (fast-path guard, mirrors anyBypassVoiceActive)
    private func anyRtcHoldVoiceActive() -> Bool {
        for i in voices.indices where voices[i].active && voices[i].rtcHold { return true }
        return false
    }
    private func rtcHoldVoiceExists(note: UInt8, bus: UInt8, ci: Int16) -> Bool {
        for i in voices.indices where voices[i].active && voices[i].rtcHold && voices[i].note == note && voices[i].bus == bus && voices[i].machineIndex == ci { return true }
        return false
    }

    /// STANDALONE RATCHET PATTERN (Paul 2026-09-08) — a PROCESSOR of the input, NOT a generator. Called EVERY window
    /// (before the pool guard, like emitColumnMod/Glide). Scans every SINGLE-SLOT ratchet-pattern cell; the ratchet's OWN
    /// clock (rtcRate·STEPS·SPAN·rotate) decides the treatment, the INPUT decides whether anything sounds:
    ///   • count 1 (PASS)      → sustain the held chord as an IMMORTAL legato hold (adopted across windows + grid columns).
    ///   • count 2…8 (RATCHET) → close the sustain + window-scan N staccato sub-strikes over the column's rate slot.
    ///   • count 0 (OFF)       → close the sustain (a gap — unselect-to-mute).
    ///   • cell not the active column for its row / no input → close its sustains.
    /// Stateless diff-reconcile (like reconcileBypass): the immortal rtcHold voices are owned entirely here (excluded from
    /// the grid hold-reconcile); allNotesOff closes them on every transport/scene edge → no stuck notes. v1: single-slot
    /// cells only (a [RATCHET PATTERN → X] chain keeps the old self-clocked generator — flagged follow-up).
    private func emitColumnRatchetPattern(box: SnapshotBox, uniformFast: Bool, effColumn: Int, pool livePool: NotePool,
                                          beatPos: Double, windowBeats: Double, windowStart: Int64, windowEnd: Int64,
                                          beatsPerSample: Double, S: Double, a: Double, out: MIDIEmitter?, diag: inout KernelDiag) {
        var hasCell = false
        for i in 0..<Snap.cells {
            let c = box.cells[i]
            if c.machineIndex >= 0 && c.procs.count <= 1 && c.proc.type == .ratchet && c.proc.rtcMode == .pattern { hasCell = true; break }
        }
        guard hasCell || anyRtcHoldVoiceActive() else { return }
        let savedCI = currentMachineIndex, savedCell = currentCellIndex, savedAlt = currentAlt
        defer { currentMachineIndex = savedCI; currentCellIndex = savedCell; currentAlt = savedAlt }

        // PHASE 1 — across ALL active single-slot ratchet-pattern cells: gather the GLOBAL desired PASS sustain set
        // (deduped by wire+bus+machine, so a row of same-machine cells sustains SEAMLESSLY — cell N+1 adopts cell N's
        // voice), and emit the RATCHET (count 2…8) staccato sub-strikes immediately (non-immortal).
        var nDes = 0
        for idx in 0..<Snap.cells {
            let cell = box.cells[idx]
            guard cell.machineIndex >= 0 && cell.procs.count <= 1 && cell.proc.type == .ratchet && cell.proc.rtcMode == .pattern else { continue }
            let row = idx % Snap.rows, col = idx / Snap.rows
            let effCol = uniformFast ? effColumn : rowEffColBuf[row]
            let sRow = uniformFast ? S : rowSBuf[row]
            let ci = Int(cell.machineIndex)
            let machine = box.machines[ci]
            let p = cell.proc   // the RESOLVED ratchet-pattern params (templateChain/processors head), NOT machine.a (which is the machine's own face — moot for a chain cell)
            let audible = !(cell.busMask == 0 || cell.muted || cell.dormant || soloSilenced(cell) || !onSceneAudible(machine.on, pass: diag.pass))
            guard (col == effCol) && audible else { continue }
            currentMachineIndex = Int16(ci); currentCellIndex = idx; currentAlt = false
            let cellPool = effectivePool(for: cell, live: livePool)
            let srcN = cellPool.srcCount(for: cell)
            guard srcN > 0 else { continue }
            let rate = max(0.03125, p.rtcRateBeats)
            let steps = max(1, min(32, p.rtcSteps))
            let spanBeats = p.rtcSpanN > 0 ? Double(p.rtcSpanN) * rate : 0
            let mWinStart = musicalOf(beatPos, stepBeats: sRow, a: a)
            let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: sRow, a: a)
            func columnCount(atTick tickStart: Double) -> Int {   // the ratchet's OWN-clock column count at a tick start
                let localTick = spanBeats > 0 ? Int(((tickStart - columnStart(tickStart, spanBeats)) / rate).rounded(.down)) : Int((tickStart / rate).rounded(.down))
                let cc = (((localTick + p.rtcRotate) % steps) + steps) % steps
                return max(0, min(8, cc < p.rtcSlices.count ? p.rtcSlices[cc] : 1))
            }
            let transpose = machineTranspose(ci, machine) + octaveShift(cell.resolvedReceiver)
            let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)
            // PASS (count 1 at the window start) → contribute this cell's held chord to the global desired sustain.
            if columnCount(atTick: Double(Int((mWinStart / rate).rounded(.down))) * rate) == 1 {
                for k in 0..<srcN {
                    let sn = cellPool.srcAscending(k, for: cell)
                    let n = Int(sn) + transpose
                    guard n >= 0 && n <= 127 else { continue }
                    let vel = max(1, cellPool.velocity(sn))
                    for b in UInt8(0)..<4 where bm & (1 << b) != 0 {
                        let sw = n + emitterOctaveShift(Int(b)) + masterKey
                        guard sw >= 0 && sw <= 127, let w = fencedNote(UInt8(sw), bus: Int(b)) else { continue }
                        var dup = false
                        for d in 0..<nDes where rtcDesWire[d] == w && rtcDesBus[d] == b && rtcDesCI[d] == Int16(ci) { dup = true; break }
                        if !dup && nDes < rtcDesWire.count { rtcDesWire[nDes] = w; rtcDesBus[nDes] = b; rtcDesVel[nDes] = vel; rtcDesCI[nDes] = Int16(ci); rtcDesCell[nDes] = Int16(idx); nDes += 1 }
                    }
                }
            }
            // RATCHET columns (count 2…8) in the window → staccato sub-strikes (non-immortal, gated on live input).
            let ramp = p.ramp
            let cycleBeats = Double(Snap.cols) * sRow
            var tk = Int((mWinStart / rate).rounded(.down)) - 1
            while true {
                let tickStart = Double(tk) * rate
                if tickStart >= mWinEnd { break }
                let ct = columnCount(atTick: tickStart)
                if ct >= 2 {
                    let sub = rate / Double(ct)
                    for j in 0..<ct {
                        let tau = tickStart + Double(j) * sub
                        if tau < mWinStart || tau >= mWinEnd { continue }
                        let tbm = chopMask(cell, m: tau, S: sRow, base: bm); if tbm == 0 { continue }
                        let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: sRow, a: a)
                        let offT = sampleOf(musical: tau + sub * 0.6, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: sRow, a: a)
                        ratchetStrikeAt(cell: cell, row: row, transpose: transpose, emits: true, pool: cellPool, bm: bm, tbm: tbm,
                                        onTime: onT, offTime: offT, m: tau, repIdx: j, count: ct, ramp: ramp, chainDriver: -1,
                                        windowEnd: windowEnd, S: sRow, cycleBeats: cycleBeats, beatsPerSample: beatsPerSample, out: out, diag: &diag)
                    }
                }
                tk += 1
            }
        }
        // PHASE 2 — reconcile ALL rtcHold voices vs the global desired set: close those no longer wanted (released /
        // gap / RATCHET column / playhead left), open the missing (own cable + All copy, both IMMORTAL).
        for i in voices.indices where voices[i].active && voices[i].rtcHold {
            var keep = false
            for d in 0..<nDes where rtcDesWire[d] == voices[i].note && rtcDesBus[d] == voices[i].bus && rtcDesCI[d] == voices[i].machineIndex { keep = true; break }
            if !keep { closeVoice(i, atSample: windowStart, out: out) }
        }
        for d in 0..<nDes {
            let w = rtcDesWire[d], b = rtcDesBus[d], ci = rtcDesCI[d]
            if rtcHoldVoiceExists(note: w, bus: b, ci: ci) { continue }
            currentMachineIndex = ci; currentCellIndex = Int(rtcDesCell[d]); currentAlt = false
            let ch = (busChannels[Int(b)] &- 1) & 15
            _ = openVoice(note: w, chan: ch, cable: b + 1, bus: b, onSample: windowStart, offSample: .max, velocity: rtcDesVel[d], out: out, meter: true, rtcHold: true)
            _ = openVoice(note: w, chan: ch, cable: 0,     bus: b, onSample: windowStart, offSample: .max, velocity: rtcDesVel[d], out: out, meter: false, rtcHold: true)
        }
    }

    /// STRUM (§3): stagger the source chord's onsets over `spread` beats from the column start, held to the
    /// boundary. Emitted per-window as each onset arrives (strumProgress, reset per column) — each note fires once.
    private func emitStrumRow(cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int,
                              emits: Bool, pool: NotePool, beatPos: Double, windowStart: Int64, windowEnd: Int64,
                              beatsPerSample: Double, S: Double, a: Double, cycleBeats: Double, chainDriver: Int = -1,
                              out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: pool)   // receiver strip LATCH: read the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)   // §9 item 1 EMITTER-ROTATE
        let spread = effectiveSpread(machine)
        let curve = machine.a.curve, tilt = machine.a.velTilt, dir = machine.a.strumDir
        let colStart = columnStart(musicalOf(beatPos, stepBeats: S, a: a), S)
        // cycleBeats (Paul 2026-10-05) is now the CALLER's real per-row pass length, not a local Double(Snap.cols)*S —
        // same bug class as the EUCLID 16-wide-part fix, here affecting STRUM's own upstream compose + downstream fold.
        // CELL MACHINE: a STRUM chain DRIVER staggers the composed set of the stages BEFORE it (derived once at colStart).
        if chainDriver >= 0 { composeChainSet(cell: cell, pool: pool, upto: chainDriver - 1, m: colStart, S: S, cycleBeats: cycleBeats) }
        let count = chainDriver >= 0 ? chainScratch.srcCount(filter: 0, cableMask: 0b1111) : pool.srcCount(for: cell)   // §7 source filter
        if r == diag.activeCellRow { diag.effMorphGold = 0;   diag.effRateBeats = spread }
        guard count > 0 else { return }

        let offSample = sampleOf(musical: colStart + S, beatPos: beatPos,       // held to boundary
                                 beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        while strumProgress[r] < count {
            let j = strumProgress[r]
            let onsetMusical = colStart + strumOffset(index: j, count: count, spread: spread, curve: curve, normalize: machine.a.strumSpreadNorm)
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
                if chainDriver >= 0 {   // fold each strummed note through the stages AFTER the strum (e.g. a downstream chance/harmonize)
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
    private func previewStopped(machineIndex ci: Int, filter: Int, busMask: UInt8, box: SnapshotBox, pool: NotePool,
                                tempo: Double, sampleRate: Double, windowStart: Int64, frameCount: UInt32,
                                out: MIDIEmitter?, diag: inout KernelDiag) {
        guard ci >= 0, ci < box.machines.count, busMask != 0, pool.count > 0 else { return }
        let machine = box.machines[ci]
        let beatsPerSample = tempo / 60.0 / sampleRate
        let windowBeats = Double(frameCount) * beatsPerSample
        let windowEnd = windowStart + Int64(frameCount)
        let clockBeat = Double(windowStart - auditionStartSample) * beatsPerSample
        let transpose = machineTranspose(ci, machine)
        previewMode = true; defer { previewMode = false }
        guard effectiveType(machine) == .arp else { return }
        var arpBeats = effectiveRateBeats(machine); if arpBeats <= 0 { arpBeats = 0.25 }
        let gate = effectiveGate(machine)
        let octaves = effectiveOctaves(machine)
        auditionTicks(sub: arpBeats, gateFraction: gate, startBeat: clockBeat, windowBeats: windowBeats,
                      windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
            let pick = arpPick(phaseIndex: tick, octaves: octaves, pattern: machine.a.patternIndex,
                               pool: pool, filter: UInt8(clamping: filter),
                               octDown: machine.a.arpOctDown, randomAnchor: machine.a.arpRandomAnchor, seed: machine.a.arpSeed)
            guard pick.note >= 0 else { return }
            let n = pick.note + transpose; guard n >= 0 && n <= 127 else { return }
            emitArtic(note: UInt8(n), busMask: busMask, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: max(1, pick.vel), out: out, diag: &diag)
        }
    }

    /// PLAYING preview (Increment 1b) — the staged VIRTUAL cell at the live column `effColumn`, SOLO. Mirrors
    /// the per-row ARP/RATCHET/STRUM derivation for one virtual row: ⇐ROW n reads that row's sounding note by
    /// derivation (parentSoundingNote); receiver/OMNI reads the filtered source pool. Uses tick slot row 0
    /// (free during solo). busEnabled respected; CLAIM bypassed. (Chord-hold/mirror types = a later cut.)
    private func previewPlaying(machineIndex ci: Int, filter: Int, busMask: UInt8, effColumn: Int,
                               box: SnapshotBox, pool: NotePool, beatPos: Double, windowBeats: Double,
                               windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                               cycleBeats: Double, out: MIDIEmitter?, diag: inout KernelDiag) {
        guard ci >= 0, ci < box.machines.count, busMask != 0, pool.count > 0 else { return }
        let machine = box.machines[ci]
        let transpose = machineTranspose(ci, machine)
        let vr = 0                                        // virtual tick-dedup row (grid-chaining retired: always source-fed)
        let f = UInt8(clamping: filter)
        previewMode = true; defer { previewMode = false }
        let mode = cellMode(type: effectiveType(machine), bypassed: false)

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
                previewChordHold(isChance: mode == .chance, isHarmonize: mode == .harmonize, machine: machine,
                                 transpose: transpose, filter: f, busMask: busMask, mNow: mNow, beatPos: beatPos,
                                 beatsPerSample: beatsPerSample, S: S, a: a, windowStart: windowStart,
                                 windowEnd: windowEnd, pool: pool, out: out, diag: &diag)
            }
        }

        switch mode {
        case .arp:
            var arpBeats = effectiveRateBeats(machine); if arpBeats <= 0 { arpBeats = 0.25 }
            let gate = effectiveGate(machine)
            let octaves = effectiveOctaves(machine)
            iterateTicks(row: vr, effColumn: effColumn, sub: arpBeats, gateFraction: gate, beatPos: beatPos,
                         windowBeats: windowBeats, windowStart: windowStart, beatsPerSample: beatsPerSample, S: S, a: a) { tick, mTickBeat, onTime, offTime in
                let pIdx = phaseIndex(tick: tick, mTickBeat: mTickBeat, arpBeats: arpBeats, S: S,
                                      cycleBeats: cycleBeats, phase: machine.a.phase, runStartColumn: -1)
                let pick = arpPick(phaseIndex: pIdx, octaves: octaves, pattern: machine.a.patternIndex, pool: pool, filter: f, octDown: machine.a.arpOctDown, randomAnchor: machine.a.arpRandomAnchor, seed: machine.a.arpSeed)
                guard pick.note >= 0 else { return }
                let n = pick.note + transpose; guard n >= 0 && n <= 127 else { return }
                emitArtic(note: UInt8(n), busMask: busMask, onSample: onTime, offSample: offTime, windowEnd: windowEnd, velocity: max(1, pick.vel), out: out, diag: &diag)
            }
        case .ratchet:
            let repeats = effectiveRepeats(machine)
            let ramp = effectiveRamp(machine)
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
            let spread = effectiveSpread(machine)
            let curve = machine.a.curve, tilt = machine.a.velTilt, dir = machine.a.strumDir
            let count = pool.srcCount(filter: f)   // STRUM is source-based (no row-feed, matching the real loop)
            if count > 0 {
                let colStart = columnStart(musicalOf(beatPos, stepBeats: S, a: a), S)
                let offSample = sampleOf(musical: colStart + S, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                while strumProgress[vr] < count {
                    let j = strumProgress[vr]
                    let onsetMusical = colStart + strumOffset(index: j, count: count, spread: spread, curve: curve, normalize: machine.a.strumSpreadNorm)
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
            break   // chord-hold handled at the transition above; a rolled-false chance is silent; fed-mirror = later cut
        }
    }

    /// The virtual cell's CHORD-HOLD (identity / CHANCE / HARMONIZE on SOURCE input): the
    /// per-cell body of `emitColumnHolds`, emitted once at the column transition, sustained to the boundary.
    private func previewChordHold(isChance: Bool, isHarmonize: Bool, machine: SnapMachine, transpose: Int,
                                  filter: UInt8, busMask: UInt8, mNow: Double, beatPos: Double, beatsPerSample: Double,
                                  S: Double, a: Double, windowStart: Int64, windowEnd: Int64, pool: NotePool,
                                  out: MIDIEmitter?, diag: inout KernelDiag) {
        let colStart = columnStart(mNow, S)
        let onSample = sampleOf(musical: colStart, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        let offSample = sampleOf(musical: colStart + S, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
        let prob = isChance ? effectiveProbability(machine.a, step: Int((colStart / S).rounded())) : 1   // CHANCE PATTERN: per-step odds
        let srcN = pool.srcCount(filter: filter)
        for k in 0..<srcN {
            let sn = pool.srcAscending(k, filter: filter)
            let n = Int(sn) + transpose
            guard n >= 0 && n <= 127 else { continue }
            if isChance && !chancePasses(beat: colStart, note: n, probability: prob) { continue }
            let vel = max(1, pool.velocity(sn))   // inherit the source velocity
            if isHarmonize {
                emitHarmony(base: n, machine: machine, baseVel: vel, row: 0, storeArtics: false,
                            busMask: busMask, on: onSample, off: offSample, beat: colStart, windowEnd: windowEnd,
                            poolMask: machine.a.harmUnits == .pool ? pool.pitchClassMaskAll() : 0, out: out, diag: &diag)   // §2 audition parity
            } else {
                emitArtic(note: UInt8(n), busMask: busMask, onSample: onSample, offSample: offSample, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag)
            }
        }
    }

    // MARK: - audition (§6.4 / delta §5)

    /// Sound the held cell's processor ALONE against the live source while the transport is stopped.
    /// §6.4: phase zeroed, input FORCED to source (the `inputRow` reference is ignored), the cell's
    /// active A/B state, its lit letters, an internal phase clock at host tempo.
    /// A change of `target` (new cell, switched cell, or release → −1) flushes and restarts the clock;
    /// transport start flushes via the process() transport edge (auto-release). Handles the
    /// time-varying processors ARP and RATCHET here; STRUM rolls via `auditionStrum` and the chord-hold
    /// types (identity/chance/harmonize) sustain via `auditionChordHold` — all shipped.
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
        guard col >= 0, col < Snap.maxCols, row >= 0, row < Snap.rows else { return }
        let cell = box.cells[col * Snap.rows + row]
        guard cell.machineIndex >= 0, !cell.muted, cell.busMask != 0, !cell.bypassed else { return }
        guard pool.count > 0 else { return }          // no held notes → silence (soundcheck)
        let ci = Int(cell.machineIndex)
        let machine = box.machines[ci]
        // CELL MACHINE: audition previews the cell's RESOLVED HEAD treatment (override/template-aware), not the raw
        // Machine A face — `treat.a = cell.proc`, so effective*(treat) reads the head. (Multi-slot chains preview the
        // HEAD slot; a full serial preview of the tail is a follow-up.)
        var treat = machine; treat.a = cell.proc

        // TAG the audition's voices with the REAL cell being auditioned (was never set here at all — every audition
        // voice inherited whatever currentCellIndex/currentMachineIndex a PRIOR real scene render last left behind,
        // or -1 on a fresh session). SEAL comet / cellSoundVel / cellNoteHead / cellSoundingNotes all key off these,
        // so an audition was invisible — or misattributed to a stale cell — to every one of them. Paul 2026-09-28
        // ("the OUT piano shows nothing"): traced to this, not the piano itself. Mirrors the save/set/defer-restore
        // idiom emitColumnRatchetPattern already uses for the same "attribute to a specific cell" need.
        let savedCI = currentMachineIndex, savedCell = currentCellIndex, savedAlt = currentAlt
        defer { currentMachineIndex = savedCI; currentCellIndex = savedCell; currentAlt = savedAlt }
        currentMachineIndex = Int16(ci); currentCellIndex = target; currentAlt = cell.alt

        let beatsPerSample = tempo / 60.0 / sampleRate
        let auditionBeat = Double(windowStart - auditionStartSample) * beatsPerSample   // free phase clock
        let windowBeats = Double(frameCount) * beatsPerSample
        let windowEnd = windowStart + Int64(frameCount)
        let transpose = machineTranspose(ci, machine)

        switch effectiveType(treat) {
        case .arp:
            var arpBeats = effectiveRateBeats(treat); if arpBeats <= 0 { arpBeats = 0.25 }
            let gate = effectiveGate(treat)
            let octaves = effectiveOctaves(treat)
            auditionTicks(sub: arpBeats, gateFraction: gate, startBeat: auditionBeat, windowBeats: windowBeats,
                          windowStart: windowStart, beatsPerSample: beatsPerSample) { tick, onT, offT in
                let pick = arpPick(phaseIndex: tick, octaves: octaves,   // phase zeroed: index = ticks since hold
                                   pattern: treat.a.patternIndex, pool: pool, for: cell,
                                   octDown: treat.a.arpOctDown, randomAnchor: treat.a.arpRandomAnchor, seed: treat.a.arpSeed)
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
            auditionStrum(cell: cell, machine: treat, pool: pool, transpose: transpose,
                          auditionBeat: auditionBeat, windowEnd: windowEnd, out: out, diag: &diag)
        default:
            // chord-hold types (identity / chance / harmonize): sustain the treated chord,
            // reconciled to the live held source each window (v2).
            auditionChordHold(cell: cell, machine: treat, pool: pool, transpose: transpose,
                              windowStart: windowStart, windowEnd: windowEnd, out: out, diag: &diag)
        }
    }

    /// Sustain the held source chord through a chord-hold treatment (§6.4), tracking the keys LIVE:
    /// build the note-set the source should sound through the treatment, then reconcile against what is
    /// currently sounding — close departed notes, open new ones (sustained; released by allNotesOff on
    /// hold-change / transport-start). chance seeds on the hold (beat 0) so
    /// each note is deterministically in or out for the whole hold; harmonize expands to its voices.
    private func auditionChordHold(cell: SnapCell, machine: SnapMachine, pool: NotePool,
                                   transpose: Int, windowStart: Int64, windowEnd: Int64,
                                   out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionDesired[i] = false }
        let type = effectiveType(machine)
        let prob = (type == .chance) ? effectiveProbability(machine.a) : 1   // audition is phase-zeroed → step 0
        let srcN = pool.srcCount(for: cell)         // §7 source filter, forced source
        for k in 0..<srcN {
            let sn = pool.srcAscending(k, for: cell)
            let base = Int(sn) + transpose
            guard base >= 0 && base <= 127 else { continue }
            let bv = max(1, pool.velocity(sn))   // inherit the source velocity
            switch type {
            case .harmonize:
                let iv = (Int8(effectiveHarmInterval(machine, voice: 0)),
                          Int8(effectiveHarmInterval(machine, voice: 1)),
                          Int8(effectiveHarmInterval(machine, voice: 2)))
                let cnt = harmonizeVoices(base: base, intervals: iv, into: &harmNotes,
                                          vel: bv, velScale: effectiveHarmVelScale(machine), vels: &harmVels)
                for j in 0..<cnt where harmNotes[j] >= 0 && harmNotes[j] <= 127 {
                    auditionDesired[harmNotes[j]] = true; auditionVel[harmNotes[j]] = harmVels[j]
                }
            case .chance:
                if chancePasses(beat: 0, note: base, probability: prob) { auditionDesired[base] = true; auditionVel[base] = bv }
            default:                                                 // identity (sustain the chord)
                auditionDesired[base] = true; auditionVel[base] = bv
            }
        }
        reconcileAuditionVoices(busMask: cell.busMask, windowEnd: windowEnd, out: out, diag: &diag)
    }

    /// STRUM audition: the held chord ROLLS in — each note has its own onset (`strumOffset`) measured
    /// from the hold; a note joins the sustained set once the audition clock passes its onset. So the
    /// first hold rolls the chord; thereafter it sustains and reconcile tracks live key changes. No
    /// columns here, so direction uses pass 0 and notes never auto-release (offSample .max).
    private func auditionStrum(cell: SnapCell, machine: SnapMachine, pool: NotePool,
                               transpose: Int, auditionBeat: Double,
                               windowEnd: Int64, out: MIDIEmitter?, diag: inout KernelDiag) {
        for i in 0..<128 { auditionDesired[i] = false }
        let spread = effectiveSpread(machine)
        let count = pool.srcCount(for: cell)
        for j in 0..<count {
            guard auditionBeat >= strumOffset(index: j, count: count, spread: spread, curve: machine.a.curve, normalize: machine.a.strumSpreadNorm)
            else { continue }                                   // this note's onset hasn't arrived yet
            let sortedIdx = strumSortedIndex(position: j, count: count, direction: machine.a.strumDir, pass: 0)
            let sn = pool.srcAscending(sortedIdx, for: cell)
            let n = Int(sn) + transpose
            guard n >= 0 && n <= 127 else { continue }
            auditionDesired[n] = true
            auditionVel[n] = strumVelocity(index: j, count: count, tilt: machine.a.velTilt, base: max(1, Int(pool.velocity(sn))))   // inherit
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
