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
        var euclideousLane: Int8 = -1 // LANE SOLO (2026-10-21): the Euclideous lane that struck this voice (−1 = none) — see `Router.euclideousStrikeLane`
        var euclideousLegato = false // GATE FOLLOWS THE RHYTHM (2026-10-13 ferry): an IMMORTAL legato-held voice owned
                                     // entirely by reconcileEuclidLegato (its own stateless-per-tick reconcile, mirroring
                                     // rtcHold/glideAnchor exactly). MUST be excluded from the grid hold-reconcile
                                     // (holdCandidate/emitColumnHolds) the SAME way rtcHold/glideAnchor already are — found
                                     // by tracing a real failing test: without this, every legato voice got swept into
                                     // holdCandidate (its offSample==.max alone made it look like a chord-hold drone) and
                                     // closed by the generic column-transition reconcile on the VERY NEXT column, since
                                     // Euclideous's own row never registers as a hold-adopting cell for that mechanism.
                                     // allNotesOff still closes it on every transport/scene edge (unconditional, as always).
    }
    private var voices = [Voice](repeating: Voice(), count: 128)

    // LANE SOLO (2026-10-21): which Euclideous lane struck a voice / an echo tail (−1 = none, every other row). `euclideousStrikeLane` is set for the duration of one lane's `runEuclidLine` and, per tail, while the
    // echo ring drains, and stamped by `openVoice` / `pushEchoTail` — so a solo that silences a lane can end exactly ITS sounding notes and pending repeats at once (`cutSoloSilencedLanes`).
    private var euclideousStrikeLane: Int8 = -1
    /// The UI's LIVE solo word (`Kernel.euclideousSoloLive`: 0x100 | the effective mask once the page has spoken, else 0 = "use the snapshot's"). Written by the main thread the instant a SOLO button is touched,
    /// read here once per render window — so solo reaches the engine within a buffer, not a snapshot rebuild later.
    private var soloLiveWord: UInt16 = 0
    /// The snapshot's solo mask as of the last Euclideous sweep — the early cut (before the echo ring drains) uses it when there is no live word.
    private var lastSnapshotSoloMask: UInt8 = 0
    private func soloMaskNow(snapshot: UInt8) -> UInt8 { soloLiveWord & 0x100 != 0 ? UInt8(soloLiveWord & 0x0F) : (snapshot & 0x0F) }

    // MARK: LANE LOCK (ferry 2026-10-21) — the snap back, decided HERE (the render thread), on the lane's own grid line
    // The lock itself (on / grid / the locked state L) rides the snapshot; what only the UI knows instantly — which lanes a finger is on and each lane's document revision — rides `lockLiveWord`
    // (`Kernel.euclideousLockLive`). At a grid line G the lane snaps to L exactly on G when it is deviated, not held and no edit to it is still on its way (`snapshot.lockRevs` ≠ the live revision =
    // "on its way"). The landing is TICK-exact: the window that holds G runs the lane twice — the old line for ticks before G, L applied for ticks from G — so the hit on the line plays L. After a landing
    // the lane keeps running on L (`lockOverrideActive`) until a snapshot built after the page applied the snap arrives (its revision changed), so the sound never waits for the main thread. The page polls
    // `lockSnapSeqPacked` (one byte per lane) to apply each landed snap to the document. Everything here is allocation-free: fixed arrays, in-place scratch lines.
    private var lockLiveWord: UInt64 = 0
    private var lockOverrideActive = [Bool](repeating: false, count: 4)
    private var lockOverrideRev = [UInt8](repeating: 0, count: 4)
    private(set) var lockSnapSeqPacked: UInt32 = 0
    private var lockSnapBeatsV = SIMD4<Double>(repeating: 0)
    var lockSnapBeats: [Double] { [lockSnapBeatsV[0], lockSnapBeatsV[1], lockSnapBeatsV[2], lockSnapBeatsV[3]] }
    private var lockPrevWindowEnd = 0.0
    /// A safety valve: "an edit is on its way" is believed for at most a second — if the page's publish never arrives (a bug, a stalled main thread) the lane must not be held off its grid forever.
    private var lockWindowSeconds = 0.0
    private var lockInFlightFor = [Double](repeating: 0, count: 4)
    private var lockPrevValid = false
    private var lockFromStart = [Bool](repeating: false, count: 4)
    private var lockAtSplit = [Bool](repeating: false, count: 4)
    private var lockSplitBeat = 0.0
    private var lockHasSplit = false
    private var lockAnyActive = false
    private var lockLinesBefore: [EuclidLine] = { var a = [EuclidLine](); a.reserveCapacity(8); for _ in 0..<4 { a.append(EuclidLine()) }; return a }()
    private var lockLinesAfter: [EuclidLine] = { var a = [EuclidLine](); a.reserveCapacity(8); for _ in 0..<4 { a.append(EuclidLine()) }; return a }()

    /// The plan for one Euclideous window `(windowStartBeat, windowEndBeat]`: which lanes already run on L (a landed snap the document has not caught up with), which land at a grid line in this window, and the
    /// scratch line arrays the two segments read (`lockLinesBefore` for ticks before the line, `lockLinesAfter` from it).
    private func planLocks(locks: [EuclideousLockSnap], lines: [EuclidLine], revs: UInt32, windowStartBeat: Double, windowEndBeat: Double) {
        lockAnyActive = false; lockHasSplit = false
        let discontinuity = !lockPrevValid || abs(windowStartBeat - lockPrevWindowEnd) > 1e-3   // a start / loop / seek: the first window's own start may sit on a line
        lockPrevValid = true; lockPrevWindowEnd = windowEndBeat
        let spoken = EuclideousLockLive.hasSpoken(lockLiveWord)
        let heldBits = spoken ? EuclideousLockLive.heldMask(lockLiveWord) : 0
        let liveRevs = EuclideousLockLive.revs(lockLiveWord)
        for lane in 0..<4 {
            lockFromStart[lane] = false; lockAtSplit[lane] = false
            guard lane < locks.count, lane < lines.count, locks[lane].on, let L = locks[lane].state else { lockOverrideActive[lane] = false; continue }
            let snapRev = EuclideousLockLive.rev(revs, lane: lane)
            let flightNow = spoken && EuclideousLockLive.rev(liveRevs, lane: lane) != snapRev
            lockInFlightFor[lane] = flightNow ? lockInFlightFor[lane] + lockWindowSeconds : 0
            if lockOverrideActive[lane] {
                if snapRev != lockOverrideRev[lane] { lockOverrideActive[lane] = false }   // a snapshot built after the page applied the snap (or after a user edit): it is authoritative again
                else { lockFromStart[lane] = true; lockAnyActive = true; continue }
            }
            guard let g = euclideousLockLineIn(grid: locks[lane].grid, barBeats: beatsPerBar, after: windowStartBeat, through: windowEndBeat, inclusiveStart: discontinuity) else { continue }
            let held = (heldBits >> UInt8(lane)) & 1 != 0
            let inFlight = flightNow && lockInFlightFor[lane] < 1.0
            guard euclideousLockSnapsAtLine(deviated: euclideousLockDeviated(line: lines[lane], from: L), held: held, editInFlight: inFlight) else { continue }
            lockOverrideActive[lane] = true; lockOverrideRev[lane] = snapRev
            lockAtSplit[lane] = true
            if !lockHasSplit || g < lockSplitBeat { lockSplitBeat = g }   // lines sit on whole beats, a window is under a beat: one line per window
            lockHasSplit = true; lockAnyActive = true
            lockSnapSeqPacked = EuclideousLockLive.bumped(lockSnapSeqPacked, lane: lane)
            lockSnapBeatsV[lane] = g
        }
        guard lockAnyActive else { return }
        lockLinesBefore.removeAll(keepingCapacity: true); lockLinesAfter.removeAll(keepingCapacity: true)
        for j in 0..<lines.count {
            var before = lines[j], after = lines[j]
            if j < locks.count, locks[j].on, let L = locks[j].state {
                if lockFromStart[j] || lockAtSplit[j] { L.applied(to: &after) }
                if lockFromStart[j] { L.applied(to: &before) }
            }
            lockLinesBefore.append(before); lockLinesAfter.append(after)
        }
    }
    /// §5.2 + "the mute kicks in immediately" (Paul 2026-10-21): the moment solo silences a lane its already-sounding notes END NOW (a note-off at this window's first sample) and its pending ratchet / roll repeats are
    /// dropped — a LANES mute lets them ring out, but a solo that left the other lanes sounding for a gate's length read as a delay. Only the solo-silenced lanes' own voices (tagged at the strike) are touched; every
    /// note-on still gets its note-off (`closeVoice` owns the refcount), so nothing is left sounding.
    private func cutSoloSilencedLanes(soloMask: UInt8, atSample t: Int64, out: MIDIEmitter?) {
        guard soloMask & 0x0F != 0 else { return }
        for lane in 0..<4 where euclideousSoloSilences(lane: lane, soloMask: soloMask) {
            let tag = Int8(lane)
            for i in voices.indices where voices[i].active && voices[i].euclideousLane == tag { closeVoice(i, atSample: t, out: out) }
            for i in echoTails.indices where echoTails[i].active && echoTails[i].lane == tag { echoTails[i].active = false }
        }
    }

    // Collision refcount (§7, normative): per (bus, channel, note). Note-ONs always emit
    // (re-articulation is audible truth); the wire note-OFF is emitted only when the LAST instance
    // releases — so a sustained note never drops under a same-pitch arp. 4 buses × 16 ch × 128 notes.
    // 5 cables now (delta §7b): 0 = ALL, 1–4 = A–D.
    private var refcount = [UInt8](repeating: 0, count: 5 * 16 * 128)
    private var distinctSounding = 0   // number of (cable,ch,note) with refcount > 0 (diag; kept incrementally)

    private var busChannels: [UInt8] = [1, 2, 3, 4]   // per-bus stamp channels, refreshed each process
    private var heldColumns: UInt16 = 0   // §5b COLUMN-SUBSET LAP: held column keys (bit i = column i),
                                         // ephemeral (PERFORM only), refreshed each process. 0 = no lap.
    private var busEnabledMask: UInt8 = 0b1111   // delta §6a: enabled emitters, refreshed each process
    private var prevBusEnabledMask: UInt8 = 0b1111   // edge: a bus going enabled→disabled closes its notes
    private var renderStart: Int64 = 0   // this render window's first sample — POCKET can't push a note before it
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
    private var masterMute = false
    // FERRY (2026-10-14 §3, "sequencer step length") — the host's REAL bar length in beats, set once per
    // render from `process()`'s new `beatsPerBar` parameter. Default 4.0 (common time) matches every
    // existing caller/test that doesn't pass it, including the whole pre-existing Euclideous test suite
    // (every one of which sets `stepRate = .r1_8`, making the OLD grid-derived `cyc` — 8 columns × 0.5
    // beats — coincidentally equal 4.0 too; confirmed by reading before relying on it, not assumed, so this
    // fix is byte-identical for the entire existing suite and only changes behaviour for a real host whose
    // time signature or grid stepRate diverges from that one coincidental combination).
    private var beatsPerBar: Double = 4.0
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
    private var markCount = [Int](repeating: 0, count: 4)
    private var withheldCount = [Int](repeating: 0, count: 4)
    private var soundCount = [Int](repeating: 0, count: 4)
    private var currentMachineIndex: Int16 = -1        // the emitting cell's machineIndex (for the SEAL comet feed) — CR-13a Int16
    private var curBox: SnapshotBox?                  // this render's box — so openVoice can read the sounding machine's DISPLAY hue to tag the reel (Paul 2026-08-19)
    private var currentCellIndex: Int = -1
    private var fBeatPos: Double = 0, fBeatsPerSample: Double = 0, fWindowStart: Int64 = 0   // this render's beat conversion (set in process)
    // RIFF DIRECTION = DRUNK (Paul 2026-09-28): the walk position persists per grid cell — same class as DEAL/ALT
    // above (a genuinely accumulated value; the codebase's architecture review, Docs/codebase-review-2026-08-16.md
    // finding A1, already flags this class as a known, disclosed limitation — not replay-exact across a mid-phrase
    // seek/loop — rather than a blessed exception; this is a deliberate third instance, not a free pass). Keyed on
    // `tick` (never `raw`, which resets at every SPAN boundary) so the walk is SPAN-oblivious by construction. Reset
    // on a fresh play, same trigger as DEAL/ALT, never on panic. Fixed storage → no render-path allocation.
    // EUCLIDEOUS RIFF ADVANCE (Paul 2026-10-06): each of Euclideous's 4 lines gets its OWN independent cursor into
    // the page's one shared riff pattern, advancing by exactly one step on that line's OWN hit (not on elapsed
    // time) — "each hit will progress riff by 1 step." Every direction needs ZERO new memory: the line's own
    // hit-ordinal (`ord`, already computed stateless in `runEuclidLine`) drives `riffStepAt` directly. DRUNK
    // (and the accumulated per-lane state it alone needed — `euclideousRiffDrunkPos`/`LastOrd`/
    // `LastSpanStart`) was REMOVED entire (Paul 2026-10-13 ferry, "Remove": "The DRUNK option") — scoped to
    // Euclideous's own walk only; the UNRELATED generic chain RIFF processor keeps its own separate
    // `riffDrunkPos`/`riffDrunkStep`/`riffDrunkPeek` above, fully untouched.
    // EUCLID MASK (Paul 2026-10-10 ferry, "Euclid mask, modes and settings") — the mask's own advancing
    // position is GENUINELY history-dependent, unlike the lane's own riff walk: §2.4's "STOP: the mask's
    // position holds where it is. PLAY continues from there" means the ordinal must count "sounding ticks
    // while the mask was ENABLED," which freezes across a stopped span rather than continuing to advance
    // in absolute tick-time the way `ord`/`hitsUpTo` do for the lane's own pattern — so this joins the SAME
    // disclosed DRUNK/DEAL/ALT accumulated-state class, not a pure derivation. Reset (to 0/.min/-1 as
    // appropriate) in the SAME `if wasPlaying != playing` block as every sibling array above/below.
    private var euclideousMaskOrd = [Int64](repeating: 0, count: 4)
    // OCT mode's UP/DOWN/ALT pattern: ALT alternates across successive CHANCE-passed OCT applications
    // specifically (a shift that never materializes due to a failed CHANCE roll doesn't consume a slot).
    private var euclideousMaskOctUp = [Bool](repeating: true, count: 4)
    // CLIMB's running rank-space transpose offset (pool units, same space as `melodyTranspose`) and
    // SWELL's running velocity offset — both accumulate once per CHANCE-passed masked note while that
    // mode is the lane's own active mode, WRAP/BOUNCE against their own boundary (CLIMB's is pool-size-
    // derived, re-evaluated fresh each time per the ratified reading; SWELL's is a fixed ±64).
    private var euclideousMaskClimbOffset = [Int](repeating: 0, count: 4)
    private var euclideousMaskSwellOffset = [Int](repeating: 0, count: 4)
    // REPEAT's own state: the last REAL note/velocity this lane struck (sentinel -1/0 = nothing yet,
    // closest structural precedent is `glideDrivenNote` below, though that one is scoped to GLIDE's own
    // ramp and not reusable directly), and how many more sounding steps the current repeat-hold has left
    // (0 = not currently repeating — the walk runs normally).
    private var euclideousLastSoundedNote = [Int8](repeating: -1, count: 4)
    private var euclideousLastSoundedVel = [UInt8](repeating: 0, count: 4)
    private var euclideousMaskRepeatRemaining = [Int](repeating: 0, count: 4)
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry) — REPEAT's own cache widened from
    // ONE note to the WHOLE merged pitch set (flat, 4 lanes × 9 slots — Engine rule 2's own ceiling), so a
    // repeat-hold on Euclideous's new additive model correctly replays every pitch that sounded on the last
    // genuine strike, not just one. `euclideousLastSoundedVel` above is REUSED as-is (a single shared
    // velocity already covers the whole set, per "every note in a hit shares the hit's velocity") — only
    // the note cache itself needed widening. `euclideousLastSoundedNote` (singular) is UNTOUCHED, still
    // read/written by `maskTransform`'s own `.repeatNote` case, which now serves ONLY the regular, non-
    // Euclideous EUCLID processor's legacy single-note-pick paths (Euclideous's own row never calls
    // `maskTransform` for `.repeatNote` anymore — see `runEuclidLine`'s new `isEuclideousRow` branch).
    private var euclideousLastSoundedNotes = [Int8](repeating: -1, count: 4 * 9)
    // RIFF/NOTES SPLIT (2026-10-13 ferry): the per-pitch velocity sibling to `euclideousLastSoundedNotes`
    // — Euclideous-exclusive, NOT the singular `euclideousLastSoundedVel` below (that one stays shared
    // with the legacy/non-Euclideous `maskTransform`'s own `.repeatNote` case). Left unreset on a
    // transport edge, same as `euclideousLastSoundedNotes` itself — both are safely gated by
    // `euclideousLastSoundedCount[i] = 0`, so nothing ever reads a stale slot.
    private var euclideousLastSoundedVels = [UInt8](repeating: 0, count: 4 * 9)
    // MIX TAB (2026-10-18): the per-pitch GATE sibling to `euclideousLastSoundedVels` — each cached pitch replays at its OWN layer's
    // gate (riff pitch = GATE, lit notes/TOP/TOP2 = the notes gate), gated by `euclideousLastSoundedCount[i]` like its siblings.
    private var euclideousLastSoundedGates = [Double](repeating: 0, count: 4 * 9)
    /// TEST-ONLY seam (default false, one Bool read at the `runEuclidLine` call site, no allocation): the Euclideous row force-
    /// disables its EUCLID MASK (LISTEN ferry §1), which makes the mask-driven paths — CHORD extras, RATCHET, REPEAT — unreachable end to
    /// end. Tests set this to drive them so their per-pitch gate rules can actually be asserted.
    var euclideousMaskEnabledForTests = false
    private var euclideousLastSoundedCount = [Int](repeating: 0, count: 4)
    /// NOTES TAB (2026-10-19, §7.2/§8.3): the pitch the riff note of the last riff-playing hit is sounding as, per lane (−1 = none) — kept across tied rests so the notes layer never
    /// re-strikes the held riff pitch. Render-state of the same class as the REPEAT cache above (a sounding-note tracker, not a derived position); reset on a play/stop edge and on `performReset`.
    private var euclideousHeldRiffPitch = [Int](repeating: -1, count: 4)
    // GATE FOLLOWS THE RHYTHM (Paul 2026-10-13 ferry): per-lane LEGATO continuity for GATE=100%. Flat
    // 4 lanes × 9 slots (matches `euclideousLastSoundedNotes`'s own ceiling — `noteViewMaxNotes`, the real
    // ceiling `addPitch`/`pitchCount` ever reaches, NOT the ferry's rounder "ten pitches" prose). Each
    // tracked entry stores the PITCH it represents + the own-cable/ALL-cable `voices[]` SLOT INDEX that
    // pitch opened — modelled directly on `GlideVoice.slot`'s own proven "store an index, close later by
    // that index, event-driven" shape, the one piece of this file already solving the identical problem.
    // A stored slot's identity is re-confirmed at EVERY touch (`active && note == trackedPitch`, not
    // `.active` alone — STRONGER than GlideVoice's own guard, because a legato hold can span many real
    // hits/render calls, unlike glide's much shorter column-boundary lifetime, so the window for an
    // unrelated reuse of the same slot index is correspondingly larger). `euclideousLegatoCount[i]` is the
    // live length of lane i's own tracked set; entries past that count are stale/unused.
    private var euclideousLegatoPitch = [Int8](repeating: -1, count: 4 * 9)
    private var euclideousLegatoOwnSlot = [Int16](repeating: -1, count: 4 * 9)
    private var euclideousLegatoAllSlot = [Int16](repeating: -1, count: 4 * 9)
    // ALT ROUTING ferry §6.3: the group OUTPUT a tracked legato note was opened on, so a hit whose group changed
    // (an ALT switch) does NOT reuse the old voice — the match becomes output-aware and the old voice closes/the new
    // strikes fresh. -1 ⇒ inherit (matches the `pitchBus` convention). For every lane with ALT OFF a pitch's group is
    // constant hit-to-hit, so the extra predicate is always true and the match is byte-identical.
    private var euclideousLegatoBus = [Int8](repeating: -1, count: 4 * 9)
    private var euclideousLegatoCount = [Int](repeating: 0, count: 4)
    // Edge-detect for "this lane just stopped" (ferry §2.5: "lane stopped... end everything
    // immediately") — checked in its OWN unconditional loop (NOT nested inside the per-line dispatch
    // loop's own `enabledResolved`-gated `where` clause, which structurally never executes once a lane is
    // disabled and so could never observe the true→false transition itself).
    private var euclideousLineWasEnabled = [Bool](repeating: true, count: 4)
    // LANES SEQUENCER MUTE EDGE-DETECT (2026-10-14 ferry, "sequencer panel, four riffs, per-lane reset"
    // §5: "when a lane switches off at a step boundary, send note-offs for its sounding notes at that
    // boundary, so nothing hangs") — a SECOND, PARALLEL edge-detect array mirroring `euclideousLineWasEnabled`
    // above exactly (same per-lane legato-tracker walk-and-close), but keyed on a DIFFERENT, independent
    // axis: "is this lane audible RIGHT NOW" (PLAY/STOP AND, when the LANES sequencer is ON, this step's own
    // lit/unlit cell) rather than just PLAY/STOP alone. Runs ALONGSIDE, not instead of, the existing sweep —
    // a lane can transition on either axis independently, and both need their own prompt note-off.
    private var euclideousLaneWasAudibleThisStep = [Bool](repeating: true, count: 4)
    /// Bookkeeping-only flush (mirrors `flushGlide`/`flushMod`'s own shape and call sites exactly) — the
    /// underlying voices are ALREADY closed by `allNotesOff` at every one of those same edges (it closes
    /// every active voice unconditionally, regardless of `offSample`, so an immortal `.max` legato voice
    /// is swept just like any other); this only clears the PARALLEL tracking so a stale slot index can't
    /// be mistaken for a still-held note the next time a lane reconciles.
    private func flushEuclideousLegato() {
        for i in 0..<4 { euclideousLegatoCount[i] = 0 }
    }
    // UI-POLLABLE MASK POSITION (Paul 2026-10-11 bug report: "Euclid mask was moving at the main rate, and
    // not progressing on hits from Euclid lane as I'd expect"). ROOT CAUSE, confirmed by reading — the
    // AUDIO/engine side was always correct: `euclideousMaskOrd` above only ever advances inside `if isHit`
    // (Router.swift's `runEuclidLine`), so the mask genuinely engages only on real sounding hits of the
    // lane's own Euclid pattern, never on raw sub-beat ticks. The bug is purely VISUAL — `maskCometRow`
    // (EuclideousPage.swift) drew the mask's step-bar with the SHARED, SELF-CLOCKED `EuclidCometBar` at a
    // hardcoded `rate: .r1_16` against the page's own live clock, exactly like an ordinary, continuously-
    // sweeping Euclid pattern — a position with NO relationship at all to `euclideousMaskOrd`'s real,
    // hit-driven advance. The EXACT "RATCHET PATTERN/DEST" class of bug this codebase's own history
    // repeatedly names: the lit cell and what's actually heard disagreeing because the UI reads an
    // unrelated clock instead of the engine's real state. FIX: mirror `euclideousRiffStep`'s own precedent
    // exactly — a plain UI-pollable array, written once per genuine lane hit (never time-driven), -1 when
    // the mask has never advanced (mirrors the riff cursor's own sentinel).
    private var euclideousMaskStep = [Int](repeating: -1, count: 4)
    func euclideousMaskPositions() -> [Int] { euclideousMaskStep }

    /// The EUCLID MASK's non-RATCHET per-note transforms (MUTE/OCT/ACCENT/SWELL/CHORD/REPEAT — MIRROR/
    /// CLIMB are riff-RANK concepts, already applied upstream to `rank` before this is ever called) — a
    /// pure extraction of the switch every masked strike runs, returning its result rather than mutating
    /// captured locals + an early `return`, so the SAME logic serves both the riff real-rank path (one
    /// call per hit) and plain NOTE mode (one call per resolved pool note).
    ///
    /// BUG FIX (2026-10-12, Paul: "ratchet doesn't work" — traced to a lane in plain NOTE mode, not
    /// RIFF): this logic used to live ONLY inline inside `runEuclidLine`'s `if useRiff {}` branch, so a
    /// lane's MASK — every mode, not just RATCHET — silently had NO EFFECT AT ALL on a lane in plain NOTE
    /// mode, directly contradicting this file's own design comment a few lines above this one's old
    /// location ("every other mode [besides MIRROR/LEAP/PAUSE]... applies in both modes alike"). The
    /// mask's own SETUP (ordinal advance, K/N hit test, CHANCE roll) was always correctly shared/
    /// unconditional; only the APPLICATION was riff-only. Confirmed by the existing test suite's own gap,
    /// not just reading: every pre-existing `testEuclidMask*` fixture (`maskFixture`, Tests/RouterTests.
    /// swift) hardcodes `useRiff: true` — not one test exercised the NOTE-mode path, which is exactly how
    /// this went unnoticed since the mask-modes ferry shipped.
    ///
    /// `resolveRank` lets CHORD's own interval offsets resolve against whichever pool the caller is
    /// actually reading (the riff-fed set, or NOTE mode's own `laneNotes`) — the one case that needs a
    /// "rank" concept beyond the already-resolved `note`/`vel` this function otherwise just transforms.
    private func maskTransform(rank: Int, note noteIn: Int, vel velIn: UInt8, lineIndex: Int, mm: EuclidLineMask,
                               maskedChancePassed: Bool, resolveRank: (Int) -> Int?) -> (note: Int, vel: UInt8, extra: [Int], muted: Bool) {
        guard maskedChancePassed else { return (noteIn, velIn, [], false) }
        var note = noteIn, vel = velIn
        var extraNotes: [Int] = []
        switch mm.modeResolved {
        case .mute:
            return (note, vel, [], true)
        case .oct:
            let up = mm.octPatternResolved == .up || (mm.octPatternResolved == .alt && euclideousMaskOctUp[lineIndex])
            if mm.octPatternResolved == .alt { euclideousMaskOctUp[lineIndex].toggle() }
            let shifted = note + (up ? 12 : -12) * mm.octAmountResolved
            if shifted >= 0 && shifted <= 127 { note = shifted }
        case .accent:
            vel = UInt8(max(1, min(127, Int(vel) + mm.accentAmountResolved)))
        case .swell:
            var off = euclideousMaskSwellOffset[lineIndex] + mm.swellStepResolved
            let bound = 64
            switch mm.swellRangeResolved {
            case .wrap: if off >= bound || off <= -bound { off = 0 }
            case .bounce:
                if off < -bound { off = -bound - (off + bound) }
                else if off > bound { off = bound - (off - bound) }
            }
            euclideousMaskSwellOffset[lineIndex] = off
            vel = UInt8(max(1, min(127, Int(vel) + off)))
        case .chord:
            let a = resolveRank(rank + mm.chordAResolved)
            let b = resolveRank(rank + mm.chordBResolved)
            for extra in [a, b] where extra != nil && extra != note && !extraNotes.contains(extra!) { extraNotes.append(extra!) }
        case .repeatNote:
            let cached = euclideousLastSoundedNote[lineIndex]
            if cached >= 0 {
                note = Int(cached); vel = euclideousLastSoundedVel[lineIndex]
                euclideousMaskRepeatRemaining[lineIndex] = mm.repeatCountResolved - 1
            }
        case .ratchet:
            break   // handled separately by `maskRatchetReps` below, after the base note/vel are finalized
        default: break
        }
        return (note, vel, extraNotes, false)
    }
    /// RATCHET's own repeat count, rolled from a SECOND seeded value (independent of the mask's CHANCE
    /// roll), capped so no subdivision is shorter than 1/128 of a bar — nil when not ratcheting (mode
    /// isn't RATCHET, or this hit's own CHANCE roll didn't pass). Shared by the riff and NOTE-mode
    /// callers for the same reason `maskTransform` is — see its own doc comment.
    private func maskRatchetReps(lineIndex: Int, rank: Int, mm: EuclidLineMask, maskedChancePassed: Bool, sub: Double, tempo: Double) -> Int? {
        guard maskedChancePassed, mm.modeResolved == .ratchet else { return nil }
        let lo = min(mm.ratchetMinResolved, mm.ratchetMaxResolved), hi = max(mm.ratchetMinResolved, mm.ratchetMaxResolved)
        let span = hi - lo + 1
        // INDEPENDENT PER RESOLVED NOTE (fix, 2026-10-13 adversarial review): the seed used to be just the
        // mask's own hit ordinal + lane — constant for every note resolved within ONE hit — so a multi-note
        // NOTE-mode pick (ALL/BOTTOM2/TOP2/a range) silently gave every note in the chord the IDENTICAL
        // repeat count, contradicting this feature's own shipped claim ("logically independent per resolved
        // note in a multi-note pick, not shared once across the whole chord"). `rank` (this one note's own
        // resolved pool rank, already in scope at both call sites) is folded into the hash so each note in
        // a pick rolls independently; RIFF mode (always exactly one resolved note per hit) is unaffected in
        // spirit — it's just reseeded with one more, fixed-per-hit term, not a behaviour change for it.
        let roll2 = splitmix64Mix(UInt64(bitPattern: euclideousMaskOrd[lineIndex]) &+ UInt64(lineIndex) &* 0xBF58476D1CE4E5B9 &+ UInt64(rank) &* 0x9E3779B97F4A7C15 &+ 0x2545F4914F6CDD1D)
        var nRep = lo + Int(roll2 % UInt64(span))
        let cap = euclideousRatchetCap(sub: sub, tempo: tempo)   // the shared formula (FX RATCH reads the same one)
        nRep = min(nRep, cap)
        return nRep
    }
    // LIVE RIFF POOL DISPLAY (Paul 2026-10-08): a stable, UI-pollable snapshot of the ascending notes
    // currently feeding the riff's own pool — mirrors the `cellSoundingNotes`/`riffDrunkPos` precedent
    // exactly (render-thread writes a plain array, a `pollXXX`-style accessor reads it from the UI timer, no
    // locking — a torn read of a value-type array is tolerable for a once-per-frame display readout). NOT
    // `riffSrcNoteBuf` itself — that's reused SCRATCH, overwritten by every `.euclid` cell this render window
    // touches, not safe to expose directly; this is a DEDICATED copy, written only for Euclideous's own row.
    private var euclideousRiffLiveNotes = [UInt8](repeating: 0, count: 16)
    private var euclideousRiffLiveCount = 0
    func euclideousRiffLivePool() -> [UInt8] { Array(euclideousRiffLiveNotes.prefix(euclideousRiffLiveCount)) }
    // SOURCES STACK ferry (2026-10-26) §2.9/§3: lane-1's (the global pool's) source status, read-and-copied on the
    // MAIN thread (the only Array alloc here, never on the render path), published through the existing 30 Hz poll.
    // The UI derives the chord NAME and the REST/WAITING/OFF labels from the SourcePlan + the display clock; this
    // carries only the render-only facts (which layers are sounding, the held MIDI notes, KEY's added count).
    struct EuclideousSourceStatus: Equatable {
        var midiNotes: [UInt8] = []
        var midiPlaying = false
        var chordsLit = false
        var chordsRest = false
        var keyLit = false
        var keyAdded = 0
    }
    func euclideousSourceStatus() -> EuclideousSourceStatus {
        EuclideousSourceStatus(midiNotes: Array(euclideousStatusMidiNotes.prefix(euclideousStatusMidiCount)),
                               midiPlaying: euclideousStatusMidiPlaying,
                               chordsLit: euclideousStatusChordsLit, chordsRest: euclideousStatusChordsRest,
                               keyLit: euclideousStatusKeyLit, keyAdded: euclideousStatusKeyAdded)
    }
    // Unified UI-poll surface: EVERY direction (not just DRUNK) writes its resolved step index here, so the poll
    // layer only ever reads one simple array regardless of which direction a lane is using.
    private var euclideousRiffStep = [Int](repeating: -1, count: 4)
    // RIFF POSITION MARKERS + LANE FOOTERS (Paul 2026-10-12 ferry): the live hit-ordinal (`advOrd`) each
    // lane's walk last advanced on — the main-thread prediction (`euclideousRiffCyclePrediction`,
    // Derivations.swift) needs this as its own `startOrd` baseline (continuing an in-progress FREE walk
    // rather than restarting from 0 every poll). Written at the SAME site `euclideousRiffStep` already is,
    // reset alongside it on a fresh play — now UNCONDITIONALLY, in both note and riff mode (Paul 2026-10-13
    // ferry, "Behaviour" rule 3: the walk keeps advancing silently in note mode).
    private var euclideousRiffLastOrd = [Int64](repeating: 0, count: 4)
    // NOTE VIEW (Paul 2026-10-10 ferry): a per-lane EVENT QUEUE — "the audio thread posts note and step
    // events... through a lock-free queue; the UI reads them." Mirrors `focusNotePitch`/`focusNoteHead`/
    // `focusNoteNew`'s exact ring-buffer shape (below, this file), just 4-wide (one ring PER LANE) instead
    // of one ring for a single focus cell — all 4 Euclideous lanes share ONE engine row (`Snap.
    // euclideousRow`), so no existing per-row/per-cell feed can tell them apart. One EVENT is one step's
    // whole OUTCOME, not one note — a chord/ALL pick strikes several notes in a single decision, stored
    // together so the UI's note box treats them as ONE update (ferry §4.6), not N separate ones.
    // kind: 0 = hit (a real note/chord struck) · 1 = miss-playing — DEAD since the 2026-10-10 ferry: `nvSent`
    // requires `isEuclideousRow`, and the one remaining push site for kind 1 (the `missNoteSel` branch) is now
    // gated `!isEuclideousRow` — the two can never both hold, so this kind can never actually reach NOTE VIEW
    // (confirmed, not assumed — the kept-but-unreachable case lives purely for `pushNoteViewEvent`'s own type
    // to stay stable; EuclideousPage.swift's note-box drawing no longer has a style for it) · 2 = rest-flash
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
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry), Engine rule 2: "a lane produces at
    // most NINE distinct pitches per hit: eight ranks plus the riff note" — was 8 (one riff note + up to 7
    // distinct simultaneous mask-chord extras, never a lit-note layer at the same time as riff before this
    // ferry).
    private static let noteViewMaxNotes = 9
    private var nvOnsetBeat    = [Double](repeating: 0, count: 4 * Router.noteViewRing)
    private var nvDurationBeat = [Double](repeating: 0, count: 4 * Router.noteViewRing)
    private var nvKind         = [UInt8](repeating: 0, count: 4 * Router.noteViewRing)
    private var nvNoteCount    = [UInt8](repeating: 0, count: 4 * Router.noteViewRing)
    private var nvNotes        = [UInt8](repeating: 0, count: 4 * Router.noteViewRing * Router.noteViewMaxNotes)
    // WIPE TELEMETRY (Paul 2026-10-10 ferry "riff-cell wipes") — -1 default, parallel to nvKind/
    // nvOnsetBeat above; only the 2 genuinely wipe-eligible push sites inside runEuclidLine ever set
    // these to a real 0...7 column / 1...8 rank.
    private var nvColumn = [Int8](repeating: -1, count: 4 * Router.noteViewRing)
    private var nvRank   = [Int8](repeating: -1, count: 4 * Router.noteViewRing)
    /// RESTART TILES ferry (2026-10-22): the riff column whose NOTE this hit struck — `nvColumn` except on a REPEAT hit (which keeps posting its own rest column there, RIFF WALK §6.5) where it is the repeated note's column.
    private var nvCellColumn = [Int8](repeating: -1, count: 4 * Router.noteViewRing)
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second ferry) — true exactly when `notes[0]` is genuinely
    // the riff's own resolved pitch for this hit (a real, non-rest riff rank; never FILL, which contributes
    // no distinct riff pitch per this ferry's own ruling) — lets the display layer (note box/summary label)
    // show "the riff note + n" vs. "the lowest sounding note + n" without re-deriving lane-level state.
    private var nvHasRiffNote = [Bool](repeating: false, count: 4 * Router.noteViewRing)
    private var nvHostSeconds = [Double](repeating: 0, count: 4 * Router.noteViewRing)   // DEBUG device log: the note-on's host-clock time (see the snapshot field)
    /// Set by the Kernel (DEBUG only) before each `process` — the host-clock seconds of this window's first sample; 0 = unknown.
    var debugWindowHostSeconds: Double = 0
    private var fSampleRate: Double = 48_000
    private var nvHead = [Int](repeating: 0, count: 4)
    private var nvNew  = [Int](repeating: 0, count: 4)
    // §5.1, literal: "nothing in this view may block or allocate on the audio thread." A caller-built
    // `[UInt8]` (an array literal, or a `.compactMap` result) is itself a render-thread heap allocation,
    // even for one element — found + fixed on a self-re-audit: the ORIGINAL 5 call sites each built one
    // of these before calling this function. `nvScratch` is the fix — ONE preallocated, reused buffer
    // every call site writes its (small, ≤8) note list into IN PLACE before calling this function with
    // just a count; nothing here or at any call site constructs a new array.
    private var nvScratch = [UInt8](repeating: 0, count: Router.noteViewMaxNotes)
    /// PULSE ferry (§1.3): the velocity each `nvScratch` pitch played with — parallel storage, fixed-size, written beside `nvScratch` at the Euclideous push sites only.
    private var nvVelScratch = [UInt8](repeating: 0, count: Router.noteViewMaxNotes)
    private var nvVels = [UInt8](repeating: 0, count: 4 * Router.noteViewRing * Router.noteViewMaxNotes)
    /// Records ONE step's outcome for `lane` (0...3) — called from inside `runEuclidLine` at its 3 real
    /// decision points (hit, miss-playing, rest-flash). Reads `noteCount` entries from `nvScratch`
    /// (written by the caller just before this call) — the FINAL, already-transposed/octave-shifted,
    /// 0...127-clamped MIDI values this tick is actually striking (ferry §5.3: "must match what is
    /// actually sent") — computed by the CALLER via the same arithmetic `strikeChord`'s own `strikeOne`
    /// uses, not re-derived here, so this can never silently disagree with the real emission. `noteCount`
    /// is pre-capped at `noteViewMaxNotes` by every caller (ample for any realistic chord). Write-side
    /// `nvNew` is capped at the ring size (never over-counted), matching `focusNoteNew`'s own idiom
    /// exactly — the ring naturally keeps-newest/drops-oldest with no extra branching needed.
    private func pushNoteViewEvent(lane: Int, onsetBeat: Double, durationBeat: Double, kind: UInt8, noteCount: Int, column: Int8 = -1, rank: Int8 = -1, hasRiffNote: Bool = false, withVels: Bool = false, cellColumn: Int8 = -1) {
        guard lane >= 0, lane < 4 else { return }
        let slot = lane * Router.noteViewRing + nvHead[lane]
        nvOnsetBeat[slot] = onsetBeat; nvDurationBeat[slot] = durationBeat; nvKind[slot] = kind
        nvColumn[slot] = column; nvRank[slot] = rank; nvHasRiffNote[slot] = hasRiffNote; nvCellColumn[slot] = cellColumn
        nvHostSeconds[slot] = (debugWindowHostSeconds > 0 && fBeatsPerSample > 0) ? debugWindowHostSeconds + (onsetBeat - fBeatPos) / fBeatsPerSample / fSampleRate : 0
        let nc = max(0, min(Router.noteViewMaxNotes, noteCount))
        nvNoteCount[slot] = UInt8(nc)
        let nbase = slot * Router.noteViewMaxNotes
        for i in 0..<Router.noteViewMaxNotes { nvNotes[nbase + i] = i < nc ? nvScratch[i] : 0 }
        for i in 0..<Router.noteViewMaxNotes { nvVels[nbase + i] = (withVels && i < nc) ? nvVelScratch[i] : 0 }   // PULSE §1.3: 0 = this site reports no velocities
        nvHead[lane] = (nvHead[lane] + 1) % Router.noteViewRing
        if nvNew[lane] < Router.noteViewRing { nvNew[lane] &+= 1 }
    }
    private var recCaptured = [Bool](repeating: false, count: Snap.cells)     // this cell's loop is committed → play (ONCE = never re-record)
    private var recCapN  = [Int](repeating: 0, count: Snap.cells)             // in-progress capture count (this window)
    private var recBufN  = [Int](repeating: 0, count: Snap.cells)             // committed loop note count
    private var recWindowIdx = [Int](repeating: Int.min, count: Snap.cells)   // CANON: the last window index committed (rolling)
    private var recArmUnit  = [Int](repeating: Int.min, count: Snap.cells)    // the grain unit the current capture (re)started on (Int.min = unarmed)
    private var recCycleBase = [Int](repeating: 0, count: Snap.cells)         // REFRESH: the unit the current committed loop began (for the M-cycle re-arm)
    // Reset the RECORDER state. `full` (scene/panic) drops the committed loop too; else (transport/latch/freeze) keep
    // the loop but discard any partial capture, so a stop→start keeps looping and a mid-record stop re-records clean.
    private func resetRecorderCapture(full: Bool) {
        for i in recCapN.indices { recCapN[i] = 0; recWindowIdx[i] = Int.min; recArmUnit[i] = Int.min; recCycleBase[i] = 0 }
        if full { for i in recCaptured.indices { recCaptured[i] = false; recBufN[i] = 0 } }
    }
    // THE SEAL COMET (note-on/off gate): a bitmask of the cells CURRENTLY SOUNDING (≥1 active non-silent voice).
    // Snapshotted on the render thread each window (a live set, like snapshotEmitterSounding); the UI polls it so the
    // The per-cell SOUNDING gate is derived on the UI side from `cellSoundVel > 0` (256-wide, covers cols 8–15); the old
    // 128-bit lo/hi bitmask was retired (Paul 2026-09-08 housekeeping) — it couldn't represent indices ≥128 (a 16-wide
    // part's second half) and had no consumer left after the VC switched to the velocity feed.
    private var currentAlt = false                   // §2 the emitting cell's effective FACE (A/B), stamped onto opened voices
    // §2 CONTINUITY: transition scratch — a legato immortal voice is a candidate for ADOPTION until the
    // reconcile either keeps it (matched by the new column) or closes it (dropped). Sized to the pool, reused.
    private var wasPlaying = false
    // LISTEN REBUILT fix (§3.6): the beat a fresh transport start landed on — DELAY counts "its own
    // steps" from here, not from absolute beat 0, so a borrowing lane rests for its first DELAY steps of
    // EVERY run, not just the ones that happen to fall at beat 0.
    private var euclideousListenTransportStartBeat: Double = 0
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

    // AUDITION (§6.4 / delta §5): the held cell's target (col*rows+row, −1 = none), the sample the hold
    // began (its free phase clock's origin), and a dedicated tick-dedup slot. All ephemeral — audition
    // is a live gesture, never persisted, never in the snapshot.
    // PREVIEW / cell audition (Phase 2, design 2026-07-26): a VIRTUAL cell (the staged config) rendered
    // SOLO through the audition machinery. `previewMode` gates the CLAIM logic OFF (solo = no other-emitter
    // context); `prevPreviewActive` flushes on the activation edge. Reuses the audition clock/dedup slots
    // (preview and audition are mutually exclusive). Ephemeral, never in the snapshot.
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
    private var glideVoices = [GlideVoice](repeating: GlideVoice(), count: Snap.cells)
    private var glideLastColumn = [Int32](repeating: -1, count: Snap.rows + 1)   // PER-ROW phrase-end on column exit (slot Snap.rows = the uniform/global call)
    private var modLastVal = [Int16](repeating: -1, count: 5 * 16 * 128)      // [cable*2048 + ch*128 + cc] → last CC value (-1 = none sent)
    private var prevFreezeActive = false      // ROW 8 FREEZE: the freeze→unfreeze edge (release the sustained notes + resume clean)

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
    // The driver emitters' SOURCE chord (note + inherited velocity), filled once per cell per window into a REUSED
    // fixed buffer (no render-path alloc — was a fresh `[(Int,UInt8)]` per generator/weave/tutti/length cell). The
    // emitters bind `srcNoteBuf[0..<srcNoteCount]` — a view whose 0-based indices match, so their reads are unchanged.
    private var srcNoteBuf = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128)
    private var srcNoteCount = 0
    // Render-hot-loop scratch for the pattern helpers (no per-window array alloc — invariant 3). euclid/burst are
    // weave-XOR-generator per cell (never nested) → one buffer each; tutti CAN nest ([TUTTI-pattern → TUTTI] folds the
    // emitter through applyStage) → the emitter (A) and applyStage (B) take SEPARATE rank buffers.
    private var euclidBuf = [Bool](repeating: false, count: 32)   // 32 = a PING-PONG lap (2 × 16 steps): a lane with hit timing is read in TICK space (RHYTHM POLISH, 2026-10-22)
    // RHYTHM POLISH (2026-10-22): the lane's in-step TILT positions (buffer space) and — for a lane with a fractional OFFSET and/or a fine TILT — its tick-space layout (cells + per-cell delay). Fixed-size, never
    // reallocated (invariant 3). A lane with neither never touches the tick-space pair.
    private var euclidMicro = [Double](repeating: 0, count: 16)
    private var euclidListenMicro = [Double](repeating: 0, count: 16)
    private var euclidTickCells = [Bool](repeating: false, count: 32)
    private var euclidTickDelay = [Double](repeating: 0, count: 32)
    // LISTEN (ferry 2026-10-14, adversarial-review fix): a SEPARATE reused buffer for building a
    // PARTNER lane's pattern — `euclidListenReaches`/euclideousBuildPatternInto must never write into
    // `euclidBuf` itself, since that's THIS lane's own pattern, still needed for the rest of this same
    // tick's evaluation. Shared across every FOLLOW/WITH/GAPS/SHADOW/AVOID/DUCK/ACCENT partner lookup
    // inside one `runEuclidLine` call — each use is synchronous (build, read, discard) before the next,
    // so one buffer safely serves all of them, even across several different partners in sequence (the
    // ANY-partner AVOID case loops over up to 3 lanes, each fully consumed before the next overwrites it).
    private var euclidListenScratch = [Bool](repeating: false, count: 16)
    // LISTEN REBUILT (ferry 2026-10-23): a SECOND reused buffer, for the BORROWED (COPY/FILL) pattern
    // before it's remapped into DIRECTION/DELAY order — `euclidListenScratch` above already holds the
    // SOURCE's own raw pattern at that point, so COPY/FILL's own hit/rest flip needs a buffer of its own.
    private var euclidListenBorrowed = [Bool](repeating: false, count: 16)
    // LISTEN REBUILT §4.2 (ECHO): per-lane, two cycles (current + the last COMPLETED one) of up to 16
    // strikes, each up to 9 pitches (matching the existing per-hit `pitches` struck-set's own cap) — pure
    // render-thread-owned state, mutated in place, never reassigned wholesale and never touched by any
    // other thread, so the cross-thread tuple-`Collection` precedent (`EuclideousPendingRollSlots`,
    // built for data WRITTEN from the main thread and READ from this one) doesn't apply here; a plain
    // pre-sized `Array`, mutated through `inout`/index access only, is the ALREADY-established pattern
    // for exactly this shape of single-thread-owned fixed buffer (`euclidBuf`/`tuttiRankBufA` above).
    private struct EuclideousEchoCycle {
        var pitchCount = [Int](repeating: 0, count: 16)    // strike j's own pitch count (0 = never struck)
        var pitches = [Int](repeating: 0, count: 16 * 9)   // strike j's pitches at [j*9 ..< j*9 + pitchCount[j]]
        var count = 0                                       // how many of the 16 strike slots are filled so far
        mutating func reset() { count = 0; for i in 0..<16 { pitchCount[i] = 0 } }
        mutating func append(count pc: Int, from src: [Int]) {
            guard count < 16 else { return }
            let k = max(0, min(9, pc))
            for i in 0..<k { pitches[count * 9 + i] = src[i] }
            pitchCount[count] = k
            count += 1
        }
        /// Allocation-free: calls `body` once per pitch of strike `j` (nothing if `j` is out of range or unstruck).
        func forEachPitch(_ j: Int, _ body: (Int) -> Void) {
            guard j >= 0, j < 16, j < count else { return }
            for i in 0..<pitchCount[j] { body(pitches[j * 9 + i]) }
        }
    }
    // Four DISTINCT instances (`repeating:` would share one set of inner arrays across all four, and the first write to each would copy them on the render thread).
    private var euclideousEchoCurrent = (0..<4).map { _ in EuclideousEchoCycle() }
    private var euclideousEchoLast = (0..<4).map { _ in EuclideousEchoCycle() }
    private var euclideousEchoCycleNum = [Int64](repeating: Int64.min, count: 4)
    /// §4.2/§9.6: how many hits THIS lane (as a follower) has struck under ECHO so far this transport run —
    /// "j, 0 for the first hit." Reset on every transport edge alongside the cycle buffers above.
    private var euclideousEchoFollowerJ = [Int](repeating: 0, count: 4)
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
    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry) — SUPERSEDES the old per-lane
    // (0...3) buffers entirely: every lane now reads the SAME pool, built once per cell-render from the
    // page's single resolved source (MIDI IN / CHORD / KEY), not 4 independently-sourced ones. Fills the
    // buffer from the LIVE pool by an explicit chanMask — mirrors the old `fillRiffSrcFromPool`/the retired
    // per-lane `fillLaneSrcFromPool` exactly, just one shared buffer instead of 4. Only ever consulted for
    // Euclideous's own reserved row (`laneCount`/`laneNotes` gate this) — every other `.euclid` cell in the
    // grid keeps reading the single shared `srcNoteBuf`/`srcNoteCount` exactly as before this feature.
    private var globalSrcBuf = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128)
    private var globalSrcCount = 0
    // SOURCES STACK ferry (2026-10-26): the MIDI and KEY source layers (CHORDS reuses `chordPoolScratch`), merged
    // into `globalSrcBuf` by `euclideousBuildSourceStack`. Preallocated — no render-thread allocation.
    private var midiLayerBuf = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128)
    private var keyLayerBuf = [Int](repeating: 0, count: 128)
    private var keyLayerCount = 0
    private var euclideousMidiLastNonEmptySample: Int64 = .min / 2   // §0.2 grace clock; "long ago" at start
    private var euclideousStackMidiPlaying = false                   // this window's MIDI-PLAYING (with release grace)
    // §2.9 status, published to the UI by `euclideousSourceStatus()` (read-and-copied on the main thread).
    private var euclideousStatusMidiNotes = [UInt8](repeating: 0, count: 8)
    private var euclideousStatusMidiCount = 0
    private var euclideousStatusMidiPlaying = false
    private var euclideousStatusChordsLit = false
    private var euclideousStatusChordsRest = false
    private var euclideousStatusKeyLit = false
    private var euclideousStatusKeyAdded = 0
    private var euclideousListenOrderScratch = [Int](repeating: 0, count: 32)   // the LISTEN processing order for the row being emitted (see `euclideousListenProcessingOrderInto`)
    // Per-hit working arrays, allocated ONCE here. They used to be `[T](repeating:count:)` locals — a heap allocation each, per hit, on the render thread (invariant 3). `takeScratch` moves one out (so it is uniquely owned and
    // writes never copy) and re-zeroes it; the caller's `defer` puts it back. Never nested: a hit takes each at most once, and no hit runs inside another.
    private var chordPoolScratch = [Int](repeating: 0, count: 8)   // the CHORDS note source's chord, built once per window (`chordSeqNotesInto`)
    private var hitRanks = [Int](repeating: 0, count: 8)
    private var hitPitches = [Int](repeating: 0, count: 9)
    private var hitPitchVel = [UInt8](repeating: 0, count: 9)
    private var hitPitchGate = [Double](repeating: 0, count: 9)
    // PER-LAYER ROUTING ferry (2026-10-25): each merged pitch's own output mask — -1 ⇒ "inherit" (the lane-wide
    // Optional was nil: the Router falls back to the cell bus, as today), else the concrete A–D mask. A riff pitch
    // gets `riffOutMaskResolved`, a notes pitch `notesOutMaskResolved`; a §4.2 collision slot gets notesOnly.
    private var hitPitchBus = [Int](repeating: -1, count: 9)
    // ALT ROUTING ferry (2026-10-25): the pending-collision scratch (a notes slot colliding with a riff slot whose
    // group is SPREAD/SPLIT-LOWEST, resolved in the post-pass). SPREAD's place is counted inline (≤9), no sort buffer.
    private var hitPendColRiffSlot = [Int](repeating: -1, count: 9)
    private var hitPendColPitch = [Int](repeating: 0, count: 9)
    private var hitPendColVel = [UInt8](repeating: 0, count: 9)
    private var hitPendColGate = [Double](repeating: 0, count: 9)
    private var hitCachedPitches = [Int](repeating: 0, count: 9)
    private var hitCachedVels = [UInt8](repeating: 0, count: 9)
    private var hitCachedGates = [Double](repeating: 0, count: 9)
    private var hitMaskBuf = [Bool](repeating: false, count: 16)
    private var legatoMatched = [Int](repeating: -1, count: 9)
    private var legatoNewPitch = [Int8](repeating: -1, count: 9)
    private var legatoNewBus = [Int8](repeating: -1, count: 9)   // ALT §6.3: the group each newly-tracked legato pitch opened on
    private var legatoNewOwn = [Int16](repeating: -1, count: 9)
    private var legatoNewAll = [Int16](repeating: -1, count: 9)
    @inline(__always) private func takeScratch<T>(_ store: inout [T], count: Int, filledWith value: T) -> [T] {
        var a: [T] = []
        swap(&a, &store)
        if a.count != count { a = [T](repeating: value, count: count); return a }   // only if a scratch was ever not handed back; allocates, never crashes
        for i in 0..<count { a[i] = value }
        return a
    }
    // SOURCES STACK ferry (2026-10-26): the Router's own `sortGlobalSrc` / `fillGlobalSrcFromPool` were replaced by
    // the shared free functions `euclideousStackSort` / `euclideousFillPoolLayer` (Derivations.swift) — the stacked
    // pool's single sort + layer-fill, so the merge and the layer buffers share ONE implementation.
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
    private var currentInputRecv: Int8 = -1
    // receiver strip LATCH: while a receiver is armed (bit set), its subscribers read a FROZEN pool (the
    // captured chord) instead of the live one — the Kernel maintains the frozen pools + hands them in.
    private var latchMask: UInt8 = 0
    private var latchedPools: [NotePool] = []
    private var receiverDisabledMask: UInt8 = 0            // INPUT ENABLE: bit i = receiver i not listening (door closed)
    private let emptyPool: NotePool = { let p = NotePool(); p.rebuildSorted(); return p }()   // a disabled door's cells read this
    // HOLD/LATCH (Paul 2026-10-20): Euclideous's OWN page-level pool, derived each render from `livePool` —
    // genuinely analogous to a door's `latchedPools` entry (reuses the SAME `NotePool.captureFiltered`/
    // `latchAddStep` primitives, Derivations.swift), but owned directly by Router (like the note tracker
    // above), not Kernel: there's no arm gesture here, just a pure function of (this render's resolved
    // `euclideousHoldLatchMode`, this render's `livePool`). ONE instance (Euclideous has one global pool, not
    // 4 per-door ones). `euclideousHoldLatchPrevHeld` is `latchAddStep`'s own caller-owned rising-edge state
    // (fixed 128-entry array, allocated once — render-thread safe, no per-tick allocation).
    private let euclideousHoldLatchPool = NotePool()
    private var euclideousHoldLatchPrevHeld = [Bool](repeating: false, count: 128)
    private var euclideousHoldLatchPrevMode: EuclideousHoldLatchMode? = nil
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

    private var strumProgress = [Int](repeating: 0, count: Snap.rows)   // strum notes emitted this column, per row
    private var prevForcedStep = Int.min   // last musical STEP seen while a column is HELD → re-arm strum each step (Paul 2026-08-15)

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
        var lane: Int8 = -1          // LANE SOLO (2026-10-21): the Euclideous lane that pushed this tail (−1 = none) — so a solo can drop ITS pending repeats
    }
    private static let echoTailCap = 256
    private var echoTails = [EchoTail](repeating: EchoTail(), count: Router.echoTailCap)
    private var echoPrevMEnd: Double = .nan   // last window's musical end — a large gap ⇒ a seek/loop discontinuity

    // THE FLOOD GOVERNOR (incident 2026-08-08: a runaway ECHO×HARM patch fed thousands of ev/s and wedged the
    // downstream synths). A hard per-EMITTER note-on cap per BEAT — overflow DROPS (counted), so we stay a good
    // citizen at our wire beneath every synth's allocator floor. Offs are NEVER capped (no stuck notes). Bounded,
    // visible (the cog HEALTH counter), never silent-failing. Reset each beat + on transport reset.
    static let floodCapPerBeat = 48           // dev-tunable; ~48/beat/emitter ≈ 384 ev/s total @ 120bpm
    // REVIEW FIX 2026-10-23: a Euclideous lane's strikes (its notes, and the echo-ring tails of its RATCH) count against their OWN, larger budget. Four lanes on one output at 1/16 with RATCH 4 is 64 note-ons a beat
    // — legitimate, and 48 silently dropped a quarter of them (132 of 516 in a probe). The 8×8 engine keeps the original runaway protection: a separate counter, so neither starves the other.
    static let euclideousFloodCapPerBeat = 160
    private var noteOnsThisBeat = [Int](repeating: 0, count: 4)
    private var euclideousOnsThisBeat = [Int](repeating: 0, count: 4)
    private var lastGovBeat = Int.min
    private(set) var floodDropped = 0          // session total surfaced to HEALTH ("dropped N this session")

    private var echoTailsActive: Bool { echoTails.contains { $0.active } }
    private func clearEchoTails() { for i in echoTails.indices { echoTails[i].active = false }; echoPrevMEnd = .nan }
    private func pushEchoTail(onset: Double, note: UInt8, vel: UInt8, busMask: UInt8, timeBeats: Double, repeats: Int,
                              feedDelay: Double, decay: Double, offset: Double, pitch: Int, gateBeats: Double) {
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
                                   decay: decay, offset: offset, pitch: pitch, gateBeats: gateBeats,
                                   lane: euclideousStrikeLane)
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
        for i in 0..<4 { noteOnsThisBeat[i] = 0; euclideousOnsThisBeat[i] = 0 }; lastGovBeat = Int.min   // FLOOD GOVERNOR: fresh budget on transport reset (floodDropped is a session total)
        for i in overrides.indices { overrides[i] = .nan }
        for i in rampDurationSamples.indices { rampDurationSamples[i] = 0 }   // a reset drops any in-flight ramp too
        overrideGen = .max
        clearEchoTails()
        for i in euclideousHeldRiffPitch.indices { euclideousHeldRiffPitch[i] = -1 }
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
                           bypassRecv: Int8 = -1, meter: Bool = false, rtcHold: Bool = false,
                           euclideousLegato: Bool = false) -> Int {
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
            out.markLane(Int(euclideousStrikeLane))   // LANE TAG (reel phase 1b): which Euclid lane is striking, for the session tape
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
        voices[slot].euclideousLane = euclideousStrikeLane   // LANE SOLO: who struck it (stamped unconditionally, so a reused slot's stale tag is always overwritten)
        voices[slot].euclideousLegato = euclideousLegato   // GATE FOLLOWS THE RHYTHM: tag the immortal legato hold (owned by reconcileEuclidLegato) — unconditional, so a reused slot's stale tag is always cleared
        voices[slot].glideAnchor = meter && !rtcHold  // GLIDE: `meter` marks glide direct-injection voices (its sole users — see
                                               // the comment above + the Voice.glideAnchor note); tag them so the
                                               // hold-continuity boundary-close skips them. A reused slot always resets
                                               // this (openVoice rewrites every field), so a later non-glide voice is clean.
        return slot
    }










    /// UI-poll read: each of Euclideous's 4 lines' own current riff-advance step index (−1 = not started / useRiff
    /// off). Plain array read, same shape as `riffDrunkPosAt` above — unlike that one, this reports ALL 6
    /// directions through one surface (`euclideousRiffStep` is written on every useRiff hit, not just DRUNK).
    func euclideousRiffPositions() -> [Int] { euclideousRiffStep }

    // SEQUENCER PANEL (2026-10-14 ferry §4) — "the step clock always runs," independent of either sequencer's
    // own ON state (ON only gates whether it actually mutes/switches) — so unlike the hit-driven riff/mask
    // polls above, these three are WRITTEN EVERY RENDER WINDOW regardless of whether anything audible is
    // happening, mirroring `currentLanesStep`/`currentRiffsStep`'s own per-window (not per-tick) granularity
    // inside `runEuclidLine`'s call site — a UI poll has no need for tick-level precision, and reusing that
    // same coarseness means the lit UI cell can never show a DIFFERENT step than the one the engine actually
    // used for this window's mute/switch decision. -1 = never rendered yet (no transport activity at all).
    private var euclideousLanesSeqStepLive = -1
    private var euclideousRiffsSeqStepLive = -1
    func euclideousLanesSeqStep() -> Int { euclideousLanesSeqStepLive }
    func euclideousRiffsSeqStep() -> Int { euclideousRiffsSeqStepLive }
    // `euclideousPlayingRiffIndexLive`/`euclideousPlayingRiffIndex()` (the old "editing vs. playing can
    // disagree" indicator, tracking what the RIFFS sequencer would switch to) are DELETED here (2026-10-18
    // adversarial review, following the ferry that dropped the looper and that whole distinction) —
    // confirmed zero remaining callers at every layer (`Kernel`/`MidiSparkAudioUnit`'s own forwarders
    // removed alongside this one).

    /// UI-poll read (Paul 2026-10-12 ferry): each lane's live walk-advance ordinal, for the main-thread
    /// cycle prediction (`euclideousRiffCyclePrediction`, Derivations.swift) — the ordinal this lane's walk
    /// last advanced on (its own `startOrd` baseline for continuing an in-progress FREE walk). Was a 3-field
    /// tuple incl. `drunkPos`/`drunkLastOrd` (DRUNK's own live walk state) — simplified to just the ordinal
    /// once DRUNK was removed from Euclideous's own walk (Paul 2026-10-13 ferry, "Remove").
    func euclideousRiffWalkState() -> [Int64] {
        (0..<4).map { i in i < euclideousRiffLastOrd.count ? euclideousRiffLastOrd[i] : 0 }
    }

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
        // WIPE/MARKER TELEMETRY (Paul 2026-10-10 "riff-cell wipes" ferry + the 2026-10-12 riff-grid-markers
        // ferry) — -1 = not a wipe/marker-eligible event. SKIP (ON REST), MUTE, PAUSE, the REPEAT hold, and
        // CHORD's own extra notes all either return before reaching a strike site that sets these or are
        // struck in a separate loop after it, so none of them ever set these. The real-rank strike site and
        // FILL (ON REST, since 2026-10-12 — needed so the riff-grid marker has a row to draw FILL-on-rest at)
        // both DO set them. `column` is the riff STEP actually read (post-LEAP); `rank` is the pool-rank at
        // that step AFTER INVERT and the EUCLID MASK's own MIRROR mode but BEFORE TRANSPOSE/OCT (the
        // real-rank site) or FILL's own first struck pool index, 1-based + TRANSPOSE (the FILL site) — in
        // both cases a value computed purely for picking which shared-grid cell/row to mark, deliberately
        // independent of whatever the actually-struck audio pitch ends up being once OCT is applied on top.
        var column: Int8 = -1
        var rank: Int8 = -1
        // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second ferry): see `nvHasRiffNote`'s own doc comment.
        var hasRiffNote: Bool = false
        /// DEBUG DEVICE LOG (walk-tags ferry 2026-10-15): the note-on's moment on the host clock (`CACurrentMediaTime`
        /// timeline) — the window's host time + the onset's sample offset. 0 = unknown (the Kernel only stamps it in
        /// DEBUG builds, and only when the host supplied a valid host time).
        var hostSeconds: Double = 0
        /// PULSE ferry (2026-10-20, §1.3): the velocity each pitch in `notes` actually played with, parallel to `notes` (the value handed to `strikeChord`, after MIX VEL / FX VEL / ACCENT / SWELL / LISTEN
        /// DUCK and ACCENT, 1…127). `vels[0]` is the riff note's when `hasRiffNote`; the rest are the notes layer's (and mask CHORD extras'). Empty on the retired non-Euclideous sites.
        var vels: [UInt8] = []
        /// RESTART TILES ferry (2026-10-22): the riff column whose note this hit struck — `column`, except on a REPEAT hit where it is the repeated note's column (`column` stays the hit's own rest seat). -1 = none.
        var cellColumn: Int8 = -1
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
                let vels = (0..<min(Router.noteViewMaxNotes, cnt)).map { nvVels[nbase + $0] }
                events.append(EuclideousNoteViewEventSnapshot(onsetBeat: nvOnsetBeat[slot], durationBeat: nvDurationBeat[slot], kind: nvKind[slot], notes: notes, column: nvColumn[slot], rank: nvRank[slot], hasRiffNote: nvHasRiffNote[slot], hostSeconds: nvHostSeconds[slot], vels: vels, cellColumn: nvCellColumn[slot]))
            }
            out.append(events)
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
        
        flushEuclideousLegato()   // 2026-10-13 GATE/legato ferry: same reason as flushGlide/flushMod — allNotesOff just closed every immortal legato voice, forget the stale bookkeeping
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


    private func anyVoiceActive() -> Bool {
        for v in voices where v.active { return true }
        return false
    }
    /// PER-PART CLOCK: any active voice belonging to ROW `r` (cellIndex row = index % Snap.rows) — the per-row transition gate.
    private func anyVoiceActiveInRow(_ r: Int) -> Bool {
        for v in voices where v.active && v.cellIndex >= 0 && Int(v.cellIndex) % Snap.rows == r { return true }
        return false
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

    /// Is bit `bus` (0–3) set in a per-emitter mask?
    @inline(__always) private func bit(_ mask: UInt8, _ bus: Int) -> Bool { mask & (1 << UInt8(bus)) != 0 }
    /// One articulation (note, on/off samples) fanned across the lit buses A–D. Fourfold has no rack (claim / flatten / curve / fence / mono / pocket / conversation), no ALT / TURNS / DEAL routing and no receiver strip,
    /// so a bus is just: enabled? → flood budget → the two cables (its own and ALL), stamped with the bus's channel.
    private func emitArtic(note: UInt8, busMask: UInt8,
                           onSample: Int64, offSample: Int64,
                           windowEnd: Int64, velocity: UInt8 = 96,
                           out: MIDIEmitter?, diag: inout KernelDiag,
                           onVoiceOpened: (Int) -> Void = { _ in }, euclideousLegato: Bool = false) {
        var lastCh: UInt8 = 0
        var mask = busMask
        while mask != 0 {
            let bus = Int(mask.trailingZeroBitCount)          // 0…3 = A…D
            mask &= mask - 1
            let c = emitOneBus(bus, note: note, velocity: velocity, onSample: onSample,
                               offSample: offSample, windowEnd: windowEnd, out: out, onVoiceOpened: onVoiceOpened, euclideousLegato: euclideousLegato)
            if c >= 0 { lastCh = UInt8(c) }
        }
        diag.emitCount &+= 1
        diag.lastEmitNote = note
        diag.lastEmitChan = lastCh
    }

    /// Emit ONE lit bus of a fanned articulation: enable gate → flood budget → the two cables (own bus+1 and ALL), both channel-stamped identically and tagged with the origin bus (§6a/§7b).
    /// Returns the wire channel it stamped, or −1 if nothing audible was emitted. A regular method (not a captured closure) — no render-path allocation.
    @discardableResult
    private func emitOneBus(_ bus: Int, note: UInt8, velocity: UInt8,
                            onSample: Int64, offSample: Int64, windowEnd: Int64, out: MIDIEmitter?,
                            onVoiceOpened: (Int) -> Void = { _ in }, euclideousLegato: Bool = false) -> Int {
        guard bit(busEnabledMask, bus) else { return -1 }
        // THE FLOOD GOVERNOR: a hard per-emitter budget per beat; overflow DROPS (counted, not silent-failing). Offs are never governed, so a dropped on never opens a voice.
        let euclideous = euclideousStrikeLane >= 0
        if euclideous ? euclideousOnsThisBeat[bus] >= Router.euclideousFloodCapPerBeat : noteOnsThisBeat[bus] >= Router.floodCapPerBeat { floodDropped &+= 1; return -1 }
        if euclideous { euclideousOnsThisBeat[bus] &+= 1 } else { noteOnsThisBeat[bus] &+= 1 }
        let ch = (busChannels[bus] &- 1) & 15   // the bus stamp (1–16 → 0–15 wire)
        let own = openVoice(note: note, chan: ch, cable: UInt8(bus + 1), bus: UInt8(bus),
                            onSample: onSample, offSample: offSample, velocity: velocity, out: out, euclideousLegato: euclideousLegato)
        if own >= 0 { onVoiceOpened(own) }
        if own >= 0 && offSample <= windowEnd { closeVoice(own, atSample: offSample, out: out) }
        let all = openVoice(note: note, chan: ch, cable: 0, bus: UInt8(bus),
                            onSample: onSample, offSample: offSample, velocity: velocity, out: out, euclideousLegato: euclideousLegato)
        if all >= 0 { onVoiceOpened(all) }
        if all >= 0 && offSample <= windowEnd { closeVoice(all, atSample: offSample, out: out) }
        return Int(ch)
    }


    private func emitTickRow(r: Int, effColumn: Int, S: Double, cycleBeats: Double, windowBeats: Double,
                             box: SnapshotBox, pool: NotePool, beatPos: Double, windowStart: Int64, windowEnd: Int64,
                             beatsPerSample: Double, a: Double, tempo: Double,
                             euclideousPendingRolls: EuclideousPendingRollSlots = EuclideousPendingRollSlots(), euclideousHoldOverrides: EuclideousPendingRollSlots = EuclideousPendingRollSlots(),
                             out: MIDIEmitter?, diag: inout KernelDiag) {
        // FOURFOLD (Step 4c): the Fourfold scene holds exactly one cell — a one-slot EUCLID chain on the reserved row (`FourfoldCompose`; `FourfoldComposeTests`). Everything the 8x8 grid did here for other processors (internal MOD / AUTO /
        // LFO modulation, input SOLO, UTILITY channel / nudge, DEAL, ON HOLD, the covered-chain drivers arp / ratchet / strum / weave / riff, LENGTH, TUTTI, the hold-tail chains) is a no-op or unreachable for that cell and is gone.
        let cell = box.cells[effColumn * Snap.rows + r]
        if cell.machineIndex < 0 || cell.muted || cell.dormant { return }   // LADDER dormant
        currentInputRecv = cell.resolvedReceiver      // this cell's receiver, for the input-vel override
        currentMachineIndex = cell.machineIndex       // item 4 marks: this cell's Machine, for the source tint
        currentCellIndex = effColumn * Snap.rows + r  // SEAL comet: this cell's grid index (the sounding column)
        let ci = Int(cell.machineIndex)
        let machine = box.machines[ci]
        if !onSceneAudible(machine.on, pass: diag.pass) { return }   // §9 item 1 ON SCENE: not entered / exited
        let transpose = machineTranspose(ci, machine)
        var treat = machine; treat.a = cell.proc
        let mode = cellMode(type: effectiveType(treat), bypassed: cell.bypassed)
        guard mode == .euclid else { return }
        let emits = cell.busMask != 0   // fan-out across every lit bus happens inside emitArtic
        emitGeneratorRow(mode: mode, cell: cell, row: r, machine: treat, transpose: transpose, emits: emits,
                                 pool: pool, effColumn: effColumn, beatPos: beatPos, windowBeats: windowBeats,
                                 windowStart: windowStart, windowEnd: windowEnd, beatsPerSample: beatsPerSample,
                                 S: S, a: a, cycleBeats: cycleBeats, tempo: tempo, euclideousPendingRolls: euclideousPendingRolls, euclideousHoldOverrides: euclideousHoldOverrides, out: out, diag: &diag)
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
        // WINDOW CONTIGUITY (FX TAB ferry, 2026-10-18): the previous window's `mEnd` and this window's `mStart` are the same instant, but a host's `beatPos` for the
        // next window is NOT bit-identical to `beatPos + frames × beatsPerSample`, so the half-open `[mStart, mEnd)` below could leave a one-ulp GAP between two windows —
        // and a deferred strike landing exactly on that boundary (a ratchet's thirds on a 64-multiple sample) would fire in neither. Within a microbeat of the previous
        // `mEnd`, start from it instead: windows tile exactly, so every strike fires once. Anything further apart (a real jump) is untouched.
        let lo = (!echoPrevMEnd.isNaN && abs(mStart - echoPrevMEnd) < 1e-6) ? echoPrevMEnd : mStart
        echoPrevMEnd = mEnd
        for i in echoTails.indices where echoTails[i].active {
            let e = echoTails[i]
            euclideousStrikeLane = e.lane   // LANE SOLO: the repeat's voice is tagged with the lane that pushed it
            if e.onset + (Double(e.repeats) + 1) * e.timeBeats < mStart { echoTails[i].active = false; continue }   // all past → retire
            for k in 1...e.repeats {
                let tau = e.onset + (Double(k) + e.offset) * e.timeBeats     // OFFSET nudges each echo off the grid
                if tau < lo || tau >= mEnd { continue }                     // half-open: fires in exactly one window (`lo`: windows tile exactly, see above)
                // FEED DELAY = the first echo's send level · FEEDBACK = the per-echo decay ratio (tail length)
                let v = Int((Double(e.vel) * e.feedDelay * pow(e.decay, Double(k - 1))).rounded())
                if v < 1 { continue }                                       // level floor kills the tail
                let n = Int(e.note) + k * e.pitch                           // PITCH: climb/descend each echo (flat semitones)
                guard n >= 0 && n <= 127 else { continue }
                let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                   windowStart: windowStart, S: S, a: a)
                let offT = sampleOf(musical: tau + e.gateBeats, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                    windowStart: windowStart, S: S, a: a)
                emitArtic(note: UInt8(n), busMask: e.busMask, onSample: onT, offSample: offT,
                          windowEnd: windowEnd, velocity: UInt8(min(127, v)), out: out, diag: &diag)
            }
        }
        euclideousStrikeLane = -1
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
                              lineIndex: Int = 0,   // which of this row's up-to-tickDedupSlotsPerRow lines this call is (EUCLID only; every other caller keeps the default, landing on slot 0 — byte-identical to the old single-scalar-per-row dedup)
                              tickFrom: Double = -Double.infinity, tickBefore: Double = Double.infinity,   // LANE LOCK: a window split at a lock line runs the lane twice — ticks before the line, then ticks from it (the default is every tick: byte-identical)
                              // RHYTHM POLISH (2026-10-22): how many STEPS into its tick cell this tick's hit sounds (0 for no hit / no timing ⇒ byte-identical). A delay is always < 1 step, so a hit stays inside its own cell; the
                              // tick is DUE when its strike beat — not its cell start — has reached the window's end, and the body is handed the strike beat.
                              strikeDelaySteps: (Int64) -> Double = { _ in 0 },
                              _ body: (_ tick: Int64, _ mTickBeat: Double,
                                       _ onTime: Int64, _ offTime: Int64) -> Void) {
        let dedupSlot = row * Router.tickDedupSlotsPerRow + min(max(0, lineIndex), Router.tickDedupSlotsPerRow - 1)
        let mStartReal = musicalOf(beatPos, stepBeats: S, a: a)
        let mEndReal = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        // `originRef: mStartReal` throughout this call — a single stable span-anchor reference for the whole
        // window, so every tick discovered below agrees on the same origin regardless of how many are found.
        let mStart = mStartReal, mEnd = mEndReal
        // floor, not ceil: a tick AT a column boundary sits between render windows — the previous
        // column's window rejects it (wrong column) and ceil would round past it, dropping the
        // column's first note. floor + the == dedup catches it once (fired slightly late, clamped).
        let firstTick = Int64((mStart / sub).rounded(.down))
        let lastT = Int64((mEnd / sub).rounded(.down))
        guard firstTick <= lastT else { return }

        for tick in firstTick...lastT {
            let mTickBeat = Double(tick) * sub   // LOCAL beat — feeds body() for note-selection only, never scheduling
            let mTickBeatReal = mTickBeat
            if mTickBeatReal + 1e-9 < tickFrom || mTickBeatReal + 1e-9 >= tickBefore { continue }   // LANE LOCK: before the dedup, so the other segment still gets this tick
            // Which column is EFFECTIVE at this tick's step (lap-aware, §5b) — REAL time, since columns stay
            // upstream of CLOCK — so a held column's ticks fire during the current window even though the tick's
            // TRUE column differs. With no lap, lapColumn returns the tick's true column and this is the original
            // `tickCol == effColumn`.
            let delayBeats = strikeDelaySteps(tick) * sub
            if delayBeats > 0 && mTickBeatReal + delayBeats > mEnd + 1e-9 { continue }   // RHYTHM POLISH: its strike falls in a later window — leave `lastTick` alone so that window fires it
            let tickStep = Int((mTickBeatReal / S).rounded(.down))
            let tickTrueCol = ((tickStep % columns) + columns) % columns   // wrap over the ROW's loop length (Lr < 8 → the short loop re-fires each pass)
            // PLAY: THIS CELL holds one column → its ticks fire EVERY window (decoupled from the timeline); normally
            // a tick fires only in its own effective column.
            if !forceColumnHold && lapColumn(laneMask: rowHeld[row], absoluteStep: tickStep, trueColumn: tickTrueCol) != effColumn { continue }   // PER-ROW LAP
            if tick == lastTick[dedupSlot] { continue }
            lastTick[dedupSlot] = tick

            let onTime = sampleOf(musical: mTickBeatReal + delayBeats, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                  windowStart: windowStart, S: S, a: a)
            // The GATE LENGTH is a LOCAL-time quantity (sub·gateFraction, the driver's own rhythm) but the clamp
            // that stops a note ringing past its column is a REAL-time boundary (columns stay upstream of CLOCK) —
            // so the local off-beat is computed, inverted back to real time, THEN clamped to the real column end.
            let colEnd = columnStart(mTickBeatReal, S) + S
            let mOffLocal = mTickBeat + sub * gateFraction
            let mOff = min(mOffLocal, colEnd)
            let offTime = sampleOf(musical: mOff, beatPos: beatPos, beatsPerSample: beatsPerSample,
                                   windowStart: windowStart, S: S, a: a)
            body(tick, mTickBeat + delayBeats, onTime, offTime)
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
            return effCol
        }
        return prevEdge
    }

    func process(box: SnapshotBox,
                 pool: NotePool,
                 playing: Bool,
                 beatPos: Double,
                 tempo: Double,
                 beatsPerBar: Double = 4.0,   // FERRY §3: the host's real beats-per-bar — read from the musical context block, NEVER derived from the grid's own stepRate/column count
                 sampleRate: Double,
                 timestampSample: Double,
                 frameCount: UInt32,
                 forceColumn: Int = -1,   // PLAY: THIS CELL — freeze the effective column here (isolated ungated play), −1 = normal
                 laneMask: UInt16 = 0,
                 panic: Bool = false,
                 euclideousAllNotesOff: Bool = false,
                 euclideousSoloLive: UInt16 = 0,
                 euclideousPendingRolls: EuclideousPendingRollSlots = EuclideousPendingRollSlots(),
                 euclideousHoldOverrides: EuclideousPendingRollSlots = EuclideousPendingRollSlots(),
                 euclideousLockLive: UInt64 = 0,
                 sceneFlush: Bool = false,
                 out: MIDIEmitter?,
                 diag: inout KernelDiag) {
        if pendingReset { pendingReset = false; performReset() }   // deferred reset — runs on the render thread (no race with the control-thread reset())
        tickRamps(atSample: Int64(timestampSample))   // §7: advance any in-flight .parameterRamp before this window's over() reads
        self.beatsPerBar = beatsPerBar              // FERRY §3: this render's real bar length, in this engine's own beat unit (quarter notes)

        busChannels = box.busChannels               // delta §7: per-bus stamp channels, this render
        curBox = box                                // for the reel's machine-by-cell note tag (openVoice reads the sounding machine's hue)
        heldColumns = laneMask                      // §5b lap: held column keys, this render
        // PER-ROW LAP (Paul 2026-08-19): the scene may set a per-row loop mask (BUILD's two grids loop independently);
        // else every row shares the global ephemeral lap (GRID tab = today). When set, the render goes down the per-row
        // path (rows may lap different columns), and each row reads rowHeld[r].
        let perRowLap = box.rowLaneMask.count == Snap.rows
        for r in 0..<Snap.rows { rowHeld[r] = perRowLap ? box.rowLaneMask[r] : laneMask }
        busEnabledMask = box.busEnabledMask         // delta §6a: enabled emitters, this render
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
        fBeatPos = beatPos; fBeatsPerSample = beatsPerSample; fWindowStart = windowStart; fSampleRate = sampleRate   // this render's beat conversion (the LANES mute sweep, the RIFFS sequencer step, NOTE VIEW's host time)
        let swing = min(75, max(50, over(1, box.swing)))
        let a = swing / 50.0
        var S = box.stepBeats
        let srIdx = Int(over(0, -1).rounded())
        if srIdx >= 0 && srIdx < Snap.stepRateBeats.count { S = Snap.stepRateBeats[srIdx] }
        diag.effSwing = swing

        // ---- drain scheduled gate-offs that have come due (survive across renders → no stuck note
        //      when a voice's off falls beyond its opening window). Runs regardless of transport. ----
        drainDue(windowStart: windowStart, windowEnd: windowEnd, out: out)
        // LANE SOLO (2026-10-21): the UI's live solo word, and — BEFORE the echo ring drains and any lane strikes — the solo-silenced lanes' sounding notes end now (the live word if the page has spoken, else the snapshot's mask
        // as the last Euclideous sweep saw it). The sweep inside the Euclideous row repeats this with the authoritative mask, so the snapshot-only path (no UI) is covered too.
        soloLiveWord = euclideousSoloLive
        lockLiveWord = euclideousLockLive    // LANE LOCK: the page's held lanes + revisions, read per window (planLocks)
        lockWindowSeconds = sampleRate > 0 ? Double(frameCount) / sampleRate : 0
        cutSoloSilencedLanes(soloMask: soloMaskNow(snapshot: lastSnapshotSoloMask), atSample: windowStart, out: out)
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding
        diag.floodDropped = floodDropped              // FLOOD GOVERNOR: surface the session drop total to HEALTH

        // ---- transport edges: all-notes-off (§7) ----
        if wasPlaying != playing {
            // LISTEN REBUILT fix (§3.6): stamp the START-only edge (not the stop edge too) before
            // `wasPlaying` below is overwritten — a borrowing lane's DELAY grace period reads this.
            if playing && !wasPlaying { euclideousListenTransportStartBeat = beatPos }
            allNotesOff(atSample: renderSampleImmediate, out: out)
            resetAllTickDedup(); for r in strumProgress.indices { strumProgress[r] = 0; lastGenStep[r] = Int64.min }
            prevEffColumn = -1
            for i in euclideousRiffStep.indices { euclideousRiffStep[i] = -1; euclideousRiffLastOrd[i] = 0 }   // EUCLIDEOUS RIFF: a fresh play restarts every lane's walk/cursor (Paul 2026-10-06) + the markers/footers ordinal poll (2026-10-12)
            for i in euclideousMaskOrd.indices {   // EUCLID MASK (Paul 2026-10-10): §2.5, "the global reset sets the mask to step 1, clears CLIMB/SWELL, and reseeds CHANCE" — step 1 = ordinal 0; CHANCE's seed is derived from this ordinal, so resetting it IS reseeding CHANCE, no separate mechanism needed.
                euclideousMaskOrd[i] = 0; euclideousMaskOctUp[i] = true
                euclideousMaskClimbOffset[i] = 0; euclideousMaskSwellOffset[i] = 0
                euclideousLastSoundedNote[i] = -1; euclideousLastSoundedVel[i] = 0; euclideousMaskRepeatRemaining[i] = 0
                euclideousLastSoundedCount[i] = 0   // LIT NOTES PLUS THE RIFF (Paul 2026-10-13): the widened REPEAT cache resets alongside its singular predecessor
                euclideousHeldRiffPitch[i] = -1     // NOTES TAB: nothing is held across a fresh play/stop
                euclideousMaskStep[i] = -1   // the UI-pollable position resets alongside the ordinal it mirrors
            }
            for i in 0..<4 { nvHead[i] = 0; nvNew[i] = 0 }   // NOTE VIEW: a fresh play/stop clears any stale queued events, not just future ones (Paul 2026-10-10)
            euclideousHoldLatchPool.reset()   // HOLD/LATCH: a fresh play/stop drops any stale frozen/latched notes (Paul 2026-10-20)
            for i in euclideousHoldLatchPrevHeld.indices { euclideousHoldLatchPrevHeld[i] = false }   // no re-allocation on the render thread — mutate in place, matching every sibling reset above
            lockPrevValid = false; for i in 0..<4 { lockOverrideActive[i] = false }   // LANE LOCK: a fresh play starts at L (the page has applied it) — no override, and the first window may sit on a line
            wasPlaying = playing
            // LISTEN REBUILT (ECHO, §4.2): a fresh play/stop drops every lane's captured strikes — no
            // stale cycle from a previous run bleeds into the next one. Mirrors every sibling reset above
            // (mutated in place, no re-allocation on the render thread).
            for i in 0..<4 { euclideousEchoCurrent[i].reset(); euclideousEchoLast[i].reset(); euclideousEchoCycleNum[i] = Int64.min; euclideousEchoFollowerJ[i] = 0 }
            clearEchoTails()                             // ECHO: transport start/stop kills tails (spec v1)
            flushEuclideousLegato()   // MOD: reset the CC on transport edges
        }
        // master panel PANIC: the one hard flush — close every voice + reset the column state, hang-kit-logged.
        if panic {
            allNotesOff(atSample: renderSampleImmediate, out: out, includeBypass: true)   // the one hard flush — bypass included
            panicControllers(atSample: renderSampleImmediate, out: out)   // §3: CC120 + CC123 on every channel/cable
            prevEffColumn = -1
            diag.panics &+= 1
            clearEchoTails()                             // ECHO: panic drops every pending tail
            flushEuclideousLegato()   // MOD: reset the CC on panic
        }
        // FOURFOLD SETTINGS, MAIN OUT tab (2026-10-15 ferry §4.6): a NARROWER flush than panic — only
        // Euclideous's own row's sounding voices (the same `cellIndex % Snap.rows` row filter
        // `closeExceptLegatoHolds`'s own `onlyRow` parameter already uses), each closed via the existing
        // `closeVoice` (which always emits on the voice's OWN stored channel from note-on time, never a
        // fresh `busChannels` re-lookup — satisfies §4.4's "a channel change must not strand notes" for
        // free). Then CC 123 on each of the 4 outputs' CURRENT channels (cables 1–4 — "Emit A"–"Emit D";
        // cable 0, "All", is not one of the four). "The lanes play on from their next hit. No transport,
        // pattern position, undo or document change" — unlike panic/sceneFlush below, nothing else here
        // resets column/echo/recorder/mod state.
        if euclideousAllNotesOff {
            for i in voices.indices where voices[i].active && Int(voices[i].cellIndex) % Snap.rows == Snap.euclideousRow {
                closeVoice(i, atSample: renderSampleImmediate, out: out)
            }
            if let out {
                for bus in 0..<4 {
                    let ch = (busChannels[bus] &- 1) & 15
                    out.emit(sampleTime: renderSampleImmediate, cable: UInt8(bus + 1), 0xB0 | ch, 123, 0)
                }
            }
        }
        // MULTI-SCENE scene SWITCH flush: close the OLD scene's sounding notes so the new scene (this render's
        // new snapshot generation) starts clean — a generation change alone doesn't flush. NOT hang-logged.
        if sceneFlush {
            allNotesOff(atSample: renderSampleImmediate, out: out)
            prevEffColumn = -1
            clearEchoTails()                             // ECHO: scene-mortal — the old scene's tails die
            flushEuclideousLegato()   // MOD: the old scene's CC state resets on the switch
        }
        pool.rebuildSorted()
        diag.poolCount = pool.count

        // ---- transport stopped: nothing derives (the live passthrough and the bypass monitor above already ran) ----
        if !playing {
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding
            return
        }

        // ---- derived column (§7). Musical space, so swing warps the beat→column map consistently
        //      with the arp ticks below. The COLUMN-SUBSET LAP (§5b) warps WHICH column is effective
        //      (held keys); the TRUE timeline — pass, swing — is unwarped (all off mNow). ----
        let mNow = musicalOf(beatPos, stepBeats: S, a: a)
        let govBeat = Int(beatPos.rounded(.down))                  // FLOOD GOVERNOR: reset the per-emitter budget each beat
        if govBeat != lastGovBeat { lastGovBeat = govBeat; for i in 0..<4 { noteOnsThisBeat[i] = 0; euclideousOnsThisBeat[i] = 0 } }
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

        let active = topCell(in: effColumn, box)
        diag.activeCellRow = active?.row ?? -1
        diag.activeCellParent = active.map { box.cells[effColumn * Snap.rows + $0.row].resolvedParent } ?? -1
        // (the stopped case already returned via the audition branch above, so playing is true here)

        // PER-PART CLOCK (Paul 2026-08-19): uniform ⇒ every row runs the scene-default step and a full 8-wide loop
        // (today's sound, byte-identical FAST PATH). Non-uniform ⇒ each row has its own step rate/loop length, so its
        // column edge + hold reconcile + ticks all derive on that row's OWN clock (the multi-clock path below).
        let uniformClock = box.rowStep.allSatisfy { $0 == S } && box.rowLength.allSatisfy { $0 == Snap.cols }
        let anyLaunchAnchor = box.rowLaunchAnchor.contains { $0 != 0 }   // PLAY-FERRY LAUNCH: an anchored ferry needs the per-row clock (its own phase offset), so it can't ride the uniform fast path
        let uniformFast = uniformClock && !perRowLap && !anyLaunchAnchor   // a per-row lap (BUILD's two grids) or a launch anchor forces the per-row path too

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
                    rowSBuf[r] = box.rowStep[r]; rowCycBuf[r] = 1; rowMNowBuf[r] = 0; rowEffColBuf[r] = -1; rowPassBuf[r] = 0
                    continue
                }
                rowLaunchArmed[r] = false
                let Sr = box.rowStep[r]
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
        drainEchoTails(mStart: mNow, mEnd: musicalOf(beatPos + Double(frameCount) * beatsPerSample, stepBeats: S, a: a),
                       beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, windowEnd: windowEnd,
                       S: S, a: a, out: out, diag: &diag)

        // CHORDS BUTTON (Paul 2026-10-08): a real gap found while testing, not by inspection — this guard
        // predates CHORDS mode and was always safe before it: EVERY processor type in this engine has always
        // needed SOME held/latched input to produce sound, so "nothing held anywhere ⇒ nothing can play" was a
        // completely sound assumption. A CHORDS- or KEY-mode Euclideous row breaks it — both generate their
        // own content algorithmically (CHORDS from the chord generator, KEY from `euclideousChordKeyTones`
        // alone — neither reads `pool`/`livePool` at all) and must keep playing even when nothing else in the
        // whole session has anything held. Cheap, allocation-free check (one optional field read) mirrors the
        // SAME "run me regardless of the pool" exception `emitFreeMod`/`emitColumnRatchetPattern` already get,
        // just folded into this guard's own condition instead of a separate pre-guard call, since CHORDS/KEY
        // ride the NORMAL emitTickRow→emitGeneratorRow dispatch once past this point (no separate subsystem
        // needed). FIXED 2026-10-21 (found while shipping HOLD/LATCH, reported separately, now fixed): this
        // used to read each LANE's legacy per-lane `sourceModeResolved` — a field the ONE-GLOBAL-SOURCE ferry
        // (2026-10-12) made decode-only/dead for behavior — instead of the page-level
        // `euclideousNoteSourceResolved` that actually governs the source today, so a CHORDS/KEY session with
        // nothing else held anywhere (and no lane's stale legacy field happening to still say `.chords`)
        // incorrectly fell through and went silent. No existing test caught it: every CHORDS/KEY RouterTest
        // passes a non-empty pool incidentally, masking the gap.
        // SOURCES STACK ferry (2026-10-26): MIDI IN always listens; CHORDS and KEY stack per the plan. Compute
        // MIDI PLAYING once per window — held notes now (filtered by LISTEN ON), OR within RELEASE GRACE of the
        // last non-empty window (§0.1/§0.2, so a legato chord change never lets a NO-MIDI layer blip in) — then
        // the plan's conditions, which GENERALISE the old `source == .chords || .key` gate. Byte-identical for
        // every pre-ferry document: the harness feeds no MIDI, and a KEY/CHORDS doc derives a plan whose condition
        // is met exactly when the old exclusive source made this true. `euclideousStackMidiPlaying` is read again
        // by the stacked-pool build in `emitGeneratorRow`.
        let euProc = box.cells[Snap.euclideousRow].procs.first
        // HOLD/LATCH (Paul 2026-10-20): a HOLD-sustained or LATCH-accumulated pool keeps driving the row once every
        // physical key is released — a non-empty MIDI contribution even with nothing held.
        let euclideousHoldLatchActive = euProc?.euclideousHoldLatchMode != nil && euclideousHoldLatchPool.count > 0
        let euMidiNonEmpty = (euProc.map { pool.srcCount(chanMask: $0.globalSrcChanMask, cableMask: 0b1111) > 0 } ?? false) || euclideousHoldLatchActive
        if euMidiNonEmpty { euclideousMidiLastNonEmptySample = windowStart }
        euclideousStackMidiPlaying = euclideousMidiPlaying(nonEmpty: euMidiNonEmpty, windowStart: windowStart, lastNonEmptySample: euclideousMidiLastNonEmptySample, sampleRate: sampleRate)
        let euPlan = euProc?.euclideousSourcePlan ?? SourcePlan()
        let euChordsActive = euclideousStackMidiPlaying ? euPlan.chordsWithMidi : euPlan.chordsNoMidi
        let euKeyActive = euclideousStackMidiPlaying ? euPlan.keyWithMidi : euPlan.keyNoMidi
        let euclideousGeneratedSourceActive = euChordsActive || euKeyActive
        guard pool.count > 0 || euclideousGeneratedSourceActive || euclideousHoldLatchActive else {   // latch: a frozen pool drives the TICK (arp) cells with no keys down
            euclideousRiffLiveCount = 0   // same reasoning — the riff's own live-pool display feed goes empty too
            // SOURCES STACK §2.9: nothing contributes this window (mergeStack won't run) — quiet the status so the UI
            // doesn't hold a stale light. MIDI may still read "playing" via the release grace even with nothing held.
            euclideousStatusMidiCount = 0; euclideousStatusMidiPlaying = euclideousStackMidiPlaying
            euclideousStatusChordsLit = false; euclideousStatusChordsRest = false
            euclideousStatusKeyLit = false; euclideousStatusKeyAdded = 0
            diag.activeVoiceCount = activeVoiceCount(); diag.distinctSounding = distinctSounding; return
        }

        // ---- per-window TICK content: evaluate rows top-down so a fed cell reads its feeder's
        //      output (mirror model). ARP cells produce ticks; identity-fed cells mirror the feeder;
        //      identity-unfed cells have no tick content (their hold was emitted at the transition). ----
        for r in 0..<Snap.rows { articCount[r] = 0 }
        let windowBeats = Double(frameCount) * beatsPerSample

        if uniformFast {
            for r in 0..<Snap.rows {
                emitTickRow(r: r, effColumn: effColumn, S: S, cycleBeats: cycleBeats, windowBeats: windowBeats,
                            box: box, pool: pool, beatPos: beatPos, windowStart: windowStart, windowEnd: windowEnd,
                            beatsPerSample: beatsPerSample, a: a, tempo: tempo, euclideousPendingRolls: euclideousPendingRolls, euclideousHoldOverrides: euclideousHoldOverrides, out: out, diag: &diag)
            }
        } else {
            let globalPass = diag.pass   // per-row ticks run on each row's OWN clock (buffers filled in the transition loop)
            for r in 0..<Snap.rows {
                if rowLaunchArmed[r] { continue }   // PLAY-FERRY LAUNCH: armed-not-started rows emit no ticks (rowEffColBuf = -1)
                diag.pass = rowPassBuf[r]
                let rowBeat = beatPos - box.rowLaunchAnchor[r]   // PLAY-FERRY LAUNCH: anchored beat so the arp/tick PHASE shifts with the launch (offset math cancels the anchor); 0 ⇒ raw
                emitTickRow(r: r, effColumn: rowEffColBuf[r], S: rowSBuf[r], cycleBeats: rowCycBuf[r], windowBeats: windowBeats,
                            box: box, pool: pool, beatPos: rowBeat, windowStart: windowStart, windowEnd: windowEnd,
                            beatsPerSample: beatsPerSample, a: a, tempo: tempo, euclideousPendingRolls: euclideousPendingRolls, euclideousHoldOverrides: euclideousHoldOverrides, out: out, diag: &diag)
            }
            diag.pass = globalPass
        }
        diag.activeVoiceCount = activeVoiceCount()
        diag.distinctSounding = distinctSounding
    }


    // MARK: - THE MOD PROCESSOR (CC generator, delta) — a beat-derived shaped CC on the active column's MOD cells.




    /// Emit a CC on every ENABLED bus in `busMask` — the per-bus cable (bus+1) + All(0), on the bus's stamp channel.
    /// Deduped per (cable,ch,cc): a repeat of the same value is dropped so a held shape doesn't flood the wire.
    /// `force` (FX TAB, 2026-10-18): send even when the value equals the last one sent on that (cable, channel, controller) — MOD's dedup is right for a
    /// continuously modulated controller, wrong for an FX CC that must arrive ONCE PER HIT. A forced send still records the value, so a MOD cell on the same
    /// controller keeps deduping against what is really on the wire. The bus set, the cable pair (own + ALL) and the channel stamp are the notes' own.
    private func emitModCC(cc: Int, value: Int, busMask: UInt8, atSample: Int64, out: MIDIEmitter?, force: Bool = false) {
        guard let out, cc >= 0 && cc <= 127, value >= 0 && value <= 127 else { return }
        for bus in 0..<4 where bit(busMask, bus) && bit(busEnabledMask, bus) {
            if soloEmitterMask != 0 && !bit(soloEmitterMask, bus) { continue }
            let ch = (busChannels[bus] &- 1) & 15
            emitModCCWire(cable: UInt8(bus + 1), ch: ch, cc: cc, value: value, atSample: atSample, out: out, force: force)
            emitModCCWire(cable: 0,               ch: ch, cc: cc, value: value, atSample: atSample, out: out, force: force)   // §7b ALL cable
        }
    }
    @inline(__always)
    private func emitModCCWire(cable: UInt8, ch: UInt8, cc: Int, value: Int, atSample: Int64, out: MIDIEmitter, force: Bool = false) {
        let key = Int(cable) * 2048 + Int(ch) * 128 + cc
        if key >= 0 && key < modLastVal.count { if !force && modLastVal[key] == Int16(value) { return }; modLastVal[key] = Int16(value) }
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
    /// Transport/scene/panic flush: the immortal glide notes are closed by allNotesOff — just forget the state.
    private func flushGlide(atSample: Int64 = renderSampleImmediate, out: MIDIEmitter? = nil) {
        for i in glideVoices.indices {
            resetGlideControllers(glideVoices[i], atSample: atSample, out: out)   // BEND re-centre + SYNTH CC65 off (E1 fix 2026-08-27: bend was left off-centre → later notes detuned)
            glideVoices[i] = GlideVoice()
        }
        for i in glideLastColumn.indices { glideLastColumn[i] = -1 }
    }




    private func emitGeneratorRow(mode: CellMode, cell: SnapCell, row r: Int, machine: SnapMachine, transpose: Int,
                                  emits: Bool, pool livePool: NotePool, effColumn: Int, beatPos: Double, windowBeats: Double,
                                  windowStart: Int64, windowEnd: Int64, beatsPerSample: Double, S: Double, a: Double,
                                  cycleBeats: Double = 0, tempo: Double = 120,
                                  euclideousPendingRolls: EuclideousPendingRollSlots = EuclideousPendingRollSlots(), euclideousHoldOverrides: EuclideousPendingRollSlots = EuclideousPendingRollSlots(),
                                  out: MIDIEmitter?, diag: inout KernelDiag) {
        let pool = effectivePool(for: cell, live: livePool)   // receiver LATCH: the frozen chord if armed
        let bm = arriveBusMask(base: cell.busMask, on: machine.on, arrivals: diag.pass)
        let p = machine.a
        let cyc = cycleBeats > 0 ? cycleBeats : Double(Snap.cols) * S
        let mWinStart = musicalOf(beatPos, stepBeats: S, a: a)
        let mWinEnd = musicalOf(beatPos + windowBeats, stepBeats: S, a: a)
        let colStart = columnStart(mWinStart, S)

        // The cell's filtered pool, each note carrying its VELOCITY, into the reused buffer. `srcNotes` = the raw source notes (transpose added per-strike).
        fillSrcFromPool(cell, pool)
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
        func strikeChord(tau: Double, velScale: Double, gateBeats: Double, onlyIndex: Int? = nil, octave: Int = 0, explicitNote: Int? = nil, explicitVel: UInt8? = nil, busOverride: UInt8? = nil, srcOverride: ArraySlice<(note: Int, vel: UInt8)>? = nil, onVoiceOpened: (Int) -> Void = { _ in }, euclideousLegato: Bool = false) {
            let onT = sampleOf(musical: tau, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
            // GATE FOLLOWS THE RHYTHM (2026-10-13 ferry): `gateBeats == .infinity` is Euclideous legato's own
            // "open-ended, I'll close it myself later" sentinel — `tau + .infinity` would otherwise feed a
            // non-finite musical offset into `sampleOf`, producing garbage. Every OTHER caller passes a
            // finite `gateBeats`, so `.isInfinite` is never true for them — zero behaviour change elsewhere.
            let offT: Int64 = gateBeats.isInfinite ? Int64.max
                : sampleOf(musical: tau + gateBeats, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
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
                if tbm != 0 {
                    emitArtic(note: UInt8(n), busMask: tbm, onSample: onT, offSample: offT, windowEnd: windowEnd, velocity: vel, out: out, diag: &diag, onVoiceOpened: onVoiceOpened, euclideousLegato: euclideousLegato)
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
        // GATE FOLLOWS THE RHYTHM (2026-10-13 ferry) — the shared legato reconcile, made PER PITCH by the MIX ferry (2026-10-18). Called
        // once per REAL processed Euclideous hit (including a silent/MUTE'd/empty one) with that hit's FINAL merged pitch set
        // (`pitches[0..<pitchCount]`) and each pitch's OWN gate (`gates`) — the riff pitch carries the lane's GATE, lit notes / TOP /
        // TOP2 the notes layer's gate, so legato is per LAYER (§7.3). A sibling nested function to `strikeChord` (not defined inside
        // the per-tick closure below), so it takes `tau`/`busOverride` explicitly, same convention.
        //
        // A pitch is LEGATO iff its own gate is exactly 100% (`euclideousGateIsLegato`) and this isn't a ratchet hit. A legato pitch
        // already tracked AND whose voice is still genuinely valid (`.active` AND still the same note — the MONO-steal `forgetEuclideous-
        // LegatoSlotAt` hook nils a stolen slot, so a stolen-then-reused held pitch correctly falls through to a fresh re-strike here, not
        // a silent no-op forever) is HELD — carried forward untouched, no note-off/note-on, immortal already. Anything tracked but NOT
        // matched (old-only, or matched by pitch but no longer genuinely valid, or the new pitch isn't legato — its layer's gate moved
        // below 100%, or a collision handed it the other layer's gate — or this is a ratchet/silent hit) gets a real, finite close "this
        // hit's time + overlap" — decided ONLY now, event-driven, never pre-scheduled (ferry §2.5.5). Every LEGATO pitch in the new set not
        // matched to a held entry is genuinely NEW — struck with `gateBeats: .infinity` (immortal, `strikeChord`'s own sentinel), its
        // own/all-cable `voices[]` slot captured via `onVoiceOpened` and tracked — mirrors `GlideVoice.slot`'s own proven "store an
        // index, close later by that index" shape. Only legato pitches are tracked.
        //
        // RETURNS a bitmask (bit j = `pitches[j]` was handled here as legato). The caller strikes every OTHER pitch normally, each at
        // its own finite gate-based length — a non-legato pitch just has its tracking absent and any previously-open legato voice's own
        // already-scheduled finite close fires on its own schedule.
        @discardableResult
        // PER-LAYER ROUTING ferry (2026-10-25): `busOf(j)` gives pitch j its own output mask — a riff pitch's riffBus,
        // a notes pitch's notesBus, a §4.2 collision slot's notesOnly. A non-escaping closure (no allocation). For every
        // existing lane every pitch resolves to emitterMask, so a new legato pitch opens on the same cables as before.
        func reconcileEuclidLegato(lineIndex: Int, pitches: [Int], pitchCount: Int, vels: [UInt8], gates: [Double], tau: Double,
                                    isRatchetThisHit: Bool, overlapBeats: Double, busOf: (Int) -> UInt8?) -> UInt16 {
            func isLegatoPitch(_ j: Int) -> Bool { !isRatchetThisHit && j < gates.count && euclideousGateIsLegato(gates[j]) }
            let base = lineIndex * 9
            let oldCount = euclideousLegatoCount[lineIndex]
            var matchedOldIndexForNew = takeScratch(&legatoMatched, count: 9, filledWith: -1)   // new-set index j → which OLD tracked index i (or -1)
            defer { legatoMatched = matchedOldIndexForNew }

            for i in 0..<oldCount {
                let trackedPitch = Int(euclideousLegatoPitch[base + i])
                let ownSlot = Int(euclideousLegatoOwnSlot[base + i]), allSlot = Int(euclideousLegatoAllSlot[base + i])
                let ownValid = ownSlot >= 0 && ownSlot < voices.count && voices[ownSlot].active && Int(voices[ownSlot].note) == trackedPitch
                let allValid = allSlot >= 0 && allSlot < voices.count && voices[allSlot].active && Int(voices[allSlot].note) == trackedPitch
                let trackedBus = Int(euclideousLegatoBus[base + i])
                var heldAsJ = -1
                if ownValid || allValid {
                    // ALT §6.3: an output-aware match — the same pitch on a DIFFERENT group (an ALT switch between two
                    // hits) is NOT a carry-on; `i` goes unmatched → it closes below and `j` strikes fresh on the new
                    // output. For ALT OFF the group is constant, so `(busOf(j)) == trackedBus` is always true here.
                    for j in 0..<pitchCount where matchedOldIndexForNew[j] < 0 && isLegatoPitch(j) && pitches[j] == trackedPitch
                        && (busOf(j).map(Int.init) ?? -1) == trackedBus { heldAsJ = j; matchedOldIndexForNew[j] = i; break }
                }
                if heldAsJ < 0 && (ownValid || allValid) {
                    // FX TAB §4.2: a pitch this hit STRIKES AGAIN (it isn't carried on — its new gate is below 100%, or the hit ratchets) closes at the hit's OWN sample,
                    // just before its new note-on, so a pitch never overlaps itself and the new note is never cut by the old one's late off (which used to land 10 ms
                    // AFTER the new on, in stream order OFF@+10ms then ON@hit). Pitches the hit does not strike still end `overlapBeats` after it.
                    var restruck = false
                    for j in 0..<pitchCount where pitches[j] == trackedPitch { restruck = true; break }
                    let closeOff = sampleOf(musical: restruck ? tau : tau + overlapBeats, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                    if ownValid { voices[ownSlot].offSample = closeOff; if closeOff <= windowEnd { closeVoice(ownSlot, atSample: closeOff, out: out) } }
                    if allValid { voices[allSlot].offSample = closeOff; if closeOff <= windowEnd { closeVoice(allSlot, atSample: closeOff, out: out) } }
                }
            }

            var legatoMask: UInt16 = 0
            var newPitch = takeScratch(&legatoNewPitch, count: 9, filledWith: -1), newOwn = takeScratch(&legatoNewOwn, count: 9, filledWith: -1), newAll = takeScratch(&legatoNewAll, count: 9, filledWith: -1)
            var newBus = takeScratch(&legatoNewBus, count: 9, filledWith: -1)
            defer { legatoNewPitch = newPitch; legatoNewOwn = newOwn; legatoNewAll = newAll; legatoNewBus = newBus }
            var tracked = 0
            for j in 0..<pitchCount where isLegatoPitch(j) {
                legatoMask |= UInt16(1) << UInt16(j)
                newPitch[tracked] = Int8(clamping: pitches[j])
                newBus[tracked] = Int8(busOf(j).map(Int.init) ?? -1)   // ALT §6.3: remember the group this voice opened on
                if matchedOldIndexForNew[j] >= 0 {
                    let i = matchedOldIndexForNew[j]
                    newOwn[tracked] = euclideousLegatoOwnSlot[base + i]; newAll[tracked] = euclideousLegatoAllSlot[base + i]
                } else {
                    var ownCap = -1, allCap = -1
                    strikeChord(tau: tau, velScale: 1.0, gateBeats: .infinity, octave: 0, explicitNote: pitches[j], explicitVel: vels[j], busOverride: busOf(j),
                                onVoiceOpened: { slot in if ownCap < 0 { ownCap = slot } else { allCap = slot } }, euclideousLegato: true)
                    newOwn[tracked] = Int16(ownCap); newAll[tracked] = Int16(allCap)
                }
                tracked += 1
            }
            for k in 0..<tracked { euclideousLegatoPitch[base + k] = newPitch[k]; euclideousLegatoOwnSlot[base + k] = newOwn[k]; euclideousLegatoAllSlot[base + k] = newAll[k]; euclideousLegatoBus[base + k] = newBus[k] }
            euclideousLegatoCount[lineIndex] = tracked
            return legatoMask
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
            // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry) — SUPERSEDES the per-lane
            // (0...3) sourceMode dispatch entirely: ALL 4 lanes now read ONE shared pool, built once per
            // cell-render from `p.euclideousNoteSourceResolved` (MIDI IN / CHORD / KEY) — Euclideous's own
            // reserved row only; every other `.euclid` cell in the grid keeps reading the single shared
            // `srcNotes`/`srcCount` this file always has, via `laneCount`/`laneNotes`'s own fallback branch,
            // byte-identical to before this feature (`isEuclideousRow` is false there). `globalSrcUsesLegacy`
            // mirrors the OLD per-lane fallback's own reasoning (a pre-existing "no receivers configured at
            // all" doc shape) — `globalSrcChanMaskSet` (SnapshotBuilder.swift) is unconditionally true for a
            // Euclideous row, so this flag never actually fires today; kept as a defensive fallback matching
            // the field's own `Bool` default (false), not a live concern.
            let isEuclideousRow = r == Snap.euclideousRow
            var globalSrcUsesLegacy = false
            // CHORDS pool, resolved at the beat it is FOR. The pool used to be built once per render window at the window's START beat, so a hit that lands exactly on a chord
            // change (a lane on the bar line under a chord that changes on the bar line — the usual case) read the PREVIOUS chord: on a legato lane that made it the pitch
            // already held, so it merged silently, and otherwise it played the old chord's note on the new chord's downbeat. `refreshChordPool(atBeat:)` is called by each tick
            // with that tick's own beat and rebuilds only when the beat falls in a different chord step than the pool was built for (a chord change — not per window).
            var chordPoolStep = Int.min
            let chordPoolRateBeats = p.chordsRateBeats > 0 ? p.chordsRateBeats : 4
            // SOURCES STACK ferry (2026-10-26): MIDI always listens, CHORDS and KEY stack under it. The three layers
            // are built into their own buffers, then `euclideousBuildSourceStack` merges them into globalSrcBuf. The
            // per-window MIDI-PLAYING flag (`euclideousStackMidiPlaying`) was computed in `process()`; recompute the
            // CHORDS condition here from the plan to gate the per-tick chord refresh.
            var chordLayerCount = 0, chordLayerIsRest = false
            var midiLayerCount = 0
            let euPlan = p.euclideousSourcePlan
            let euChordsActive = euclideousStackMidiPlaying ? euPlan.chordsWithMidi : euPlan.chordsNoMidi
            func fillChordLayer(atBeat m: Double) {
                chordPoolStep = Int((m / chordPoolRateBeats).rounded(.down))
                chordLayerCount = chordSeqNotesInto(&chordPoolScratch, beat: m, p, keyRoot: p.euclideousChordKeyRoot, keyTones: p.euclideousChordKeyTones, followNote: nil)
                chordLayerIsRest = chordLayerCount == 0   // §2.6: chordSeqNotesInto returns 0 ONLY for a REST column (PATTERN mode — a real degree always yields ≥1)
            }
            func mergeStack(atBeat m: Double) {
                fillChordLayer(atBeat: m)
                let st = euclideousBuildSourceStack(
                    into: &globalSrcBuf, cap: globalSrcBuf.count,
                    midi: midiLayerBuf[0..<midiLayerCount], midiPlaying: euclideousStackMidiPlaying,
                    chords: chordPoolScratch[0..<chordLayerCount], chordsIsRest: chordLayerIsRest,
                    key: keyLayerBuf[0..<keyLayerCount],
                    plan: euPlan, clash: p.euclideousClashPolicy, midiStatusOut: &euclideousStatusMidiNotes)
                globalSrcCount = st.count
                euclideousStatusMidiCount = min(euclideousStatusMidiNotes.count, st.midiAdmitted)
                euclideousStatusMidiPlaying = st.midiPlaying
                euclideousStatusChordsLit = st.chordsLit; euclideousStatusChordsRest = st.chordsRest
                euclideousStatusKeyLit = st.keyLit; euclideousStatusKeyAdded = st.keyAdded
            }
            // §2: re-merge at a tick only when the CHORDS column changed AND chords are contributing — otherwise the
            // window-start merge stands (byte-identical to a KEY/MIDI doc, which never changed within a window either).
            func refreshStack(atBeat m: Double) {
                guard isEuclideousRow, euChordsActive else { return }
                let mm = m + 1e-9                                    // a tick a hair under a chord boundary belongs to the new chord
                guard Int((mm / chordPoolRateBeats).rounded(.down)) != chordPoolStep else { return }
                mergeStack(atBeat: mm)
            }
            // HOLD/LATCH (Paul 2026-10-20, fixed 2026-10-21): checked HERE, once per Euclideous-row tick, so leaving
            // and returning to a MIDI contribution both reset correctly. Must run BEFORE fillMidiLayer (which reads
            // the pool). MIDI always listens now, so this no longer needs a source-mode guard.
            if isEuclideousRow, p.euclideousHoldLatchMode != euclideousHoldLatchPrevMode {
                euclideousHoldLatchPool.reset()
                for i in euclideousHoldLatchPrevHeld.indices { euclideousHoldLatchPrevHeld[i] = false }
                euclideousHoldLatchPrevMode = p.euclideousHoldLatchMode
            }
            // The MIDI layer: `livePool` (not the shadowed `pool`) avoids a self-arming door's content leaking in;
            // filtered by LISTEN ON. HOLD mirrors/freezes it, LATCH accumulates — both read back OMNI (filtered at
            // capture). Always built now (MIDI always listens); an empty live pool yields an empty layer.
            func fillMidiLayer() {
                switch p.euclideousHoldLatchMode {
                case .hold:
                    if livePool.srcCount(chanMask: p.globalSrcChanMask, cableMask: 0b1111) > 0 {
                        euclideousHoldLatchPool.captureFiltered(from: livePool, chanMask: p.globalSrcChanMask, cableMask: 0b1111)
                    }
                    midiLayerCount = euclideousFillPoolLayer(into: &midiLayerBuf, from: euclideousHoldLatchPool, chanMask: 0xFFFF)
                case .latch:
                    euclideousHoldLatchPool.latchAddStep(from: livePool, chanMask: p.globalSrcChanMask, cableMask: 0b1111, prevHeld: &euclideousHoldLatchPrevHeld)
                    midiLayerCount = euclideousFillPoolLayer(into: &midiLayerBuf, from: euclideousHoldLatchPool, chanMask: 0xFFFF)
                case nil:
                    midiLayerCount = euclideousFillPoolLayer(into: &midiLayerBuf, from: livePool, chanMask: p.globalSrcChanMask)
                }
            }
            // The KEY layer: the scale tones in ONE base octave (baseOct 3 = MIDI 48/C3); the rank-fold rule extends
            // higher octaves, so pre-baking a second octave would double-extend. Exactly today's `.key` formula.
            func fillKeyLayer() {
                let root = ((p.euclideousChordKeyRoot % 12) + 12) % 12
                let base = 3 * 12 + 12
                var n = 0
                for iv in p.euclideousChordKeyTones where n < keyLayerBuf.count {
                    let note = base + root + iv
                    if note >= 0 && note <= 127 { keyLayerBuf[n] = note; n += 1 }
                }
                keyLayerCount = n
            }
            if isEuclideousRow {
                fillMidiLayer()
                fillKeyLayer()
                mergeStack(atBeat: mWinStart)
            }
            func laneCount(_ li: Int) -> Int { (isEuclideousRow && !globalSrcUsesLegacy) ? globalSrcCount : srcCount }
            func laneNotes(_ li: Int) -> ArraySlice<(note: Int, vel: UInt8)> { (isEuclideousRow && !globalSrcUsesLegacy) ? globalSrcBuf[0..<globalSrcCount] : srcNotes }
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
            // LANE LOCK: every read of a lane's (or its partner's) line inside `runEuclidLine` goes through this — the snapshot's lines, or, for the window segment a lock snap has changed, the same lines with L applied.
            var linesView = p.euclidLines
            func runEuclidLine(lineIndex: Int, pulses kIn: Int, steps nIn: Int, rotate: Int, dir: EuclidDir, noteSel: EuclidNoteSel, gate: Double, octave: Int, velocity: Double, velocityAbsolute: Int, rate: Double, busOverride: UInt8?,
                                // PER-LAYER ROUTING ferry (2026-10-25): the riff layer's and notes layer's own resolved output
                                // masks (MAIN). Read ONLY inside the `isEuclideousRow` branch; the call site passes the EFFECTIVE
                                // MAIN masks (`eff.riff.mainMask` / `eff.notes.mainMask` — a follower adopts the leader's, §4.4),
                                // which equal `busOverride` (= emitterMask) for every existing lane, so this is byte-identical until
                                // a user splits them. nil default ⇒ the legacy fork never reads them.
                                riffBus: UInt8? = nil, notesBus: UInt8? = nil,
                                // ALT ROUTING ferry (2026-10-25): the effective per-part ALT routing (mode + masks + leadPartId),
                                // after the §4.4 link. nil ⇒ no ALT (the legacy fork, or a build with every mode OFF never reads
                                // past `groupOf`'s OFF short-circuit). The group decision rides this, not a second derivation.
                                alt: EuclideousEffectiveRouting? = nil,
                                missNoteSel: EuclidNoteSel? = nil, missGate: Double = 0.9, missOctave: Int = 0, missVelocity: Double = 1.0,
                                patternMiss: Bool = false,
                                useRiff: Bool = false, riffRotate: Int = 0, riffOctave: Int = 0,
                                riffDir: RiffDir = .forward, riffDirSeed: Int = 0, riffDirBias: Double = 0, tilt: Double = 0,
                                riffLock: Bool = false, riffInvert: Bool = false, riffOnRest: EuclidRiffOnRest = .skip,
                                riffStride: Int = 1, riffLength: Int = 8, riffAdvanceStep: Bool = false, riffAdvanceEvery: Int = 1, melodyTranspose: Int = 0,
                                mask: EuclidLineMask = EuclidLineMask(), customHits: [Bool]? = nil,
                                // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry) — read ONLY
                                // inside the new `isEuclideousRow` branch below; every other (non-Euclideous)
                                // row keeps the existing `useRiff`-driven fork completely unchanged, so these
                                // four new params are harmless no-ops for it regardless of what's passed.
                                riffOn: Bool = false,
                                // NOTES TAB ferry (2026-10-19): what is lit is ONE fixed-size ordered list (`litOrder`: positions 0-7 = ranks 1-8, 8 = TOP 2, 9 = TOP), and the lit notes play
                                // on the hits `notesWhen` / `notesChance` choose, as `notesPlayAs` says. (The per-note octave shifts no longer sound — the parameter is gone.)
                                litOrder: EuclideousLitOrder = EuclideousLitOrder(), notesWhen: UInt8 = 0b11, notesChance: Int = 100,
                                notesPlayAs: EuclidNotesPlayAs = .chord, notesReceivedOnly: Bool = false,
                                notesOn: Bool = true, notesVelocity: Int = 100, notesGate: Double = 0.9,
                                // LANES GRID (2026-10-18): the per-lane restart / mute grid is resolved INSIDE this function (it needs the
                                // lane's own step length and lap, known only after the pattern is built) from `linesView[lineIndex]` —
                                // so nothing grid-related is passed in any more.
                                // LISTEN TAB (ferry 2026-10-14) — all additive, defaulted to "off," so this
                                // function's one existing call site is the only one that needs to change.
                                // Partner indices are plain Ints (-1 = none/not applicable) rather than a
                                // bundled struct: `linesView`/`laneNotes`/`laneCount` are ALREADY in
                                // this closure's own captured scope (this is a nested func inside
                                // `process()`), so looking a partner's EuclidLine/pool up here directly is
                                // simpler and cheaper than having the call site pre-build and pass it.
                                // LISTEN REBUILT (ferry 2026-10-23): REPLACES every old listen* parameter above —
                                // one shared SOURCE lane (-1 = none) for the whole tab instead of a partner per row.
                                listenRhythm: EuclideousListenRhythmMode = .own, listenSource: Int = -1,
                                listenDelay: Int = 0, listenFeel: Double = 0, listenSpeed: Int = 0, listenDirection: EuclidDir = .fwd,
                                listenPitch: EuclideousListenPitchMode = .own, listenInterval: Int = 0, listenOctave: Int = 0,
                                // RHYTHM POLISH (2026-10-22): OFFSET's fractional part and whether this lane's TILT plays unrounded (`tiltFine`).
                                offsetFraction: Double = 0, tiltFine: Bool = false,
                                tickFrom: Double = -Double.infinity, tickBefore: Double = Double.infinity) {   // LANE LOCK: the segment of the window this call plays (the default is all of it)
                // LANE SOLO: every voice and echo tail this lane's hits open is stamped with the lane (Euclideous's own row only), so a solo can end exactly its notes.
                euclideousStrikeLane = isEuclideousRow ? Int8(lineIndex) : -1
                defer { euclideousStrikeLane = -1 }
                // LISTEN REBUILT §3 (COPY/FILL): REPLACES this lane's own generation entirely with the
                // SOURCE's own finished pattern (its own OFFSET/TILT/INV already baked in, via the SAME
                // `euclideousBuildHitPatternInto` FOLLOW used to read), remapped into DIRECTION's own
                // order (§3.4/`euclideousListenBorrowedIndex` — FWD mirrors the source's own LIVE playback
                // order, BKW reverses it, PING-PONG ping-pongs its STORED order) and shifted by DELAY (a
                // buffer rotation: "position p shows what the borrowed pattern had at p−DELAY," §3.6).
                // UNLIKE the old FOLLOW, this lane's own OFFSET/INV do NOT apply on top (§7: "a tab is
                // either fully the lane's own or fully paused" — the old "still applies on top" was
                // exactly the confusing half-overridden state this rebuild fixes).
                let n: Int
                var offsetFractionTotal = offsetFraction
                for i in 0..<16 { euclidMicro[i] = 0 }
                let copyOrFillValid = (listenRhythm == .copy || listenRhythm == .fill) && listenSource >= 0 && listenSource < linesView.count && listenSource != lineIndex
                var listenRhythmSourceRateBeats = rate
                if copyOrFillValid {
                    let sourceLine = linesView[listenSource]
                    let sourceN = euclideousBuildHitPatternInto(sourceLine, cells: &euclidListenScratch, micro: &euclidListenMicro)
                    euclideousListenBorrowedHits(sourcePattern: euclidListenScratch, n: sourceN, mode: listenRhythm, into: &euclidListenBorrowed)
                    for k in 0..<sourceN {
                        let srcIdx = euclideousListenBorrowedIndex(followerRaw: k, n: sourceN, followerDirection: listenDirection, sourceDirection: sourceLine.directionResolved)
                        euclidBuf[k] = euclidListenBorrowed[srcIdx]
                    }
                    n = sourceN
                    euclidRotateBuffer(&euclidBuf, steps: n, rotation: -listenDelay)
                    // FEEL (§3.7): a uniform micro-delay across every borrowed hit — a disclosed
                    // simplification of "applied exactly as TILT is today": TILT's own algorithm
                    // redistributes hits generated fresh from (pulses, steps) and has no defined meaning
                    // applied to an arbitrary externally-given (borrowed) pattern.
                    if listenFeel != 0 { for i in 0..<n where euclidBuf[i] { euclidMicro[i] = max(-0.5, min(0.5, listenFeel * 0.5)) } }
                    listenRhythmSourceRateBeats = sourceLine.rate?.beats ?? p.euclidRateBeats
                } else {
                    n = max(2, min(16, nIn))
                    let k = p.euclidPulsesFromPool ? srcCount : max(0, min(n, kIn))   // POOL: K = held-note count
                    // HAND-EDITED PATTERN (6-sliders ferry, Paul 2026-10-12): a non-nil `customHits` REPLACES
                    // pure generation entirely — it's the already-resolved hit pattern a HITS-slider rebuild
                    // produced (`euclidRebuildPattern`, Derivations.swift), so TILT has nothing left to bias
                    // (the UI disables it, and this is the engine-side half of that: tilt is simply never
                    // consulted once a custom pattern is in play). OFFSET (rotation) still applies — it's a
                    // position-shift on top of WHATEVER the base shape is, pure or edited, same as always.
                    if let custom = customHits, !custom.isEmpty {
                        for i in 0..<n { euclidBuf[i] = i < custom.count ? custom[i] : false }
                    } else {
                        // TILT BEFORE ROTATION (Paul 2026-10-11: "the offset makes tilt look indecipherable...
                        // maybe this could adjust to offset" — see `euclidTiltPattern`'s own doc comment for the
                        // full reasoning). Build the pattern unrotated, bias it early/middle/late while its own
                        // step 0 still means "the start of this pattern," THEN rotate the already-tilted result —
                        // so OFFSET slides the shape around the column without silently redefining what TILT's
                        // bias was relative to. Every downstream read of `euclidBuf` (the hit/rest test, the
                        // CYCLE/RANDOM ordinal walk, MISS's complement) still just picks up the final shape, zero
                        // other changes needed anywhere in this function.
                        euclidPatternInto(&euclidBuf, pulses: k, steps: n, rotation: 0)
                        if tilt != 0 {
                            if tiltFine { euclidTiltPatternFine(&euclidBuf, pulses: k, steps: n, tilt: tilt, micro: { i, f in self.euclidMicro[i] = f }) }   // RHYTHM POLISH: unrounded — the cell + the fraction of the step
                            else { euclidTiltPattern(&euclidBuf, pulses: k, steps: n, tilt: tilt) }
                        }
                    }
                    euclidRotateBuffer(&euclidBuf, steps: n, rotation: rotate)
                    euclidRotateMicro(&euclidMicro, steps: n, rotation: rotate)
                    // MISS = PATTERN INVERT (Paul 2026-10-10 ferry §2.2: "after HITS, TILT and OFFSET have produced
                    // the pattern") — SUPERSEDES the old dual-voice hit/miss split entire. Flipping `euclidBuf` here,
                    // once, before `cycleHits`/`isHitAt` below are ever read, makes every downstream hit-counting
                    // consumer in this function — cycleHits/effHits/hitsUpTo/ord/the riff walk/the TIE lookahead —
                    // automatically treat the inverted (now-sounding) steps as "hits," with no separate MISS branch
                    // needed anywhere else. `euclidCycleLen` (LOCK's own pattern-cycle length) is a function of `n`/
                    // `dir` alone, untouched by inverting the buffer's contents, matching ferry §2.3's "LOCK's
                    // 'pattern cycle' is unchanged."
                    if patternMiss { for i in 0..<n { euclidBuf[i].toggle(); euclidMicro[i] = 0 } }   // FLIP: the flipped hits sit on step starts
                }
                // LISTEN REBUILT §3.4: `euclidBuf` for a COPY/FILL lane is ALREADY in its own final tick
                // order (DIRECTION/listenDirection baked in by `euclideousListenBorrowedIndex` above) — the
                // lane's own `direction` (a RHYTHM-tab control, paused while borrowing, §7) must NOT be
                // applied a SECOND time by `cycleLen`/`isHitAt` below, or a lane that happened to have a
                // non-FWD `direction` stored from before it started borrowing would silently double-mirror.
                let dir = copyOrFillValid ? EuclidDir.fwd : dir
                // RATE×ladder (Paul 2026-08-27): GRID = the fixed step grain (density lives here + K/N); SPAN re-syncs the
                // pattern every N columns (FREE = 0 = free-run). Rate and loop decoupled — an odd N against an aligning
                // span drifts then snaps back. (Was the WIDTH model `sub = spanWidth/n`, where SPAN just scaled the speed.)
                // EUCLIDEOUS (Paul 2026-10-05): `rate` is now a PASSED-IN parameter (the caller resolves
                // L.rate?.beats ?? p.euclidRateBeats) instead of this closure directly capturing the machine-wide
                // field — lets each of Euclideous's 4 lines run its own rate; every existing non-Euclideous call
                // resolves to the exact same machine-wide value as before, byte-identical.
                // LISTEN REBUILT §3.3 (SPEED): the follower's own step length is the SOURCE's own ÷ 2^SPEED,
                // directly (`listenSpeed` IS the exponent — no sign inversion to remember, unlike the old
                // FOLLOW's `listenFollowRatio`).
                let sub = copyOrFillValid ? listenRhythmSourceRateBeats / pow(2.0, Double(listenSpeed)) : rate
                // RESET SPAN (Paul 2026-10-08, §2.2): Euclideous's own GLOBAL reset-span control — resolved
                // directly from `doc.euclideousResetSpanBarsResolved` into `p.euclideousResetSpanBars` (gated
                // to Euclideous's own row in SnapshotBuilder, 0 for every other `.euclid` cell) — OVERRIDES the
                // regular machine-wide `euclidSpanN` ladder when set, rather than composing with it: Euclideous
                // never exposes `euclidSpanN` on its own page, so the two can never both be meaningfully set at
                // once for the same line. `cyc` (this render's own "one bar" beat-length, already computed
                // above) is multiplied directly by the literal bar count — not routed through `spanLadderBeats`'s
                // own ladder, which tops out at 8 bars (its n=64 case) and has no slot for 16.
                // RESTARTS (history: the 2026-10-14 per-lane RESET in sequencer steps, its 2026-10-15 8-bit mask, and the 2026-10-14 "sequencer
                // step length" fix — a restart interval measured in the host's REAL bars (`beatsPerBar`), never the grid's `cyc`). All of that is now
                // the lane's two 16-cell restart masks below; a pre-feature document's old reset migrates into them at use, against the same real
                // bar (`euclideousLaneGridResolved`), so the bars-vs-grid-cycle bug cannot return through the migration.
                // LANES GRID (2026-10-18 ferry): the lane's mute grid and its two restart masks, resolved from the lane's own fields (or, for a
                // pre-feature document, migrated from the old sequencer + reset — `euclideousLaneGridResolved`) against THIS lane's own step
                // length and lap. `cycleLen` is the Router's lap in ticks; the units are integer multiples of the lane's tick.
                let cycleLen = euclidCycleLen(dir, n: n)
                // RHYTHM POLISH (2026-10-22): a lane with a fractional OFFSET and/or a fine TILT is read in TICK space — `euclideousHitLayoutInto` turns the buffer-space cells + in-step positions into the cell each hit
                // STARTS in (direction mirrored, wrapped round the lap) and its delay in that cell; every reader below then sees `eN` / `eDir` = (the lap's tick count, FWD) over those cells. A lane with neither keeps
                // (`n`, `dir`) over the buffer — the exact path it always ran.
                var timingActive = offsetFractionTotal > 0
                if !timingActive { for i in 0..<n where euclidMicro[i] != 0 { timingActive = true; break } }
                var eN = n, eDir = dir
                var hitTiming = EuclideousHitTiming.none
                if timingActive {
                    euclideousHitLayoutInto(cells: euclidBuf, micro: euclidMicro, fraction: offsetFractionTotal, n: n, dir: dir, outCells: &euclidTickCells, outDelay: &euclidTickDelay)
                    for i in 0..<cycleLen { euclidBuf[i] = euclidTickCells[i] }
                    eN = cycleLen; eDir = .fwd
                    hitTiming = EuclideousHitTiming(delay: euclidTickDelay)
                }
                var chains = EuclideousLaneRestartChains.off
                var muteCells: UInt16 = 0xFFFF
                var muteUnitBeats = 0.0
                // RESTART CHAINS: row-AGNOSTIC, like the `riffLock` field it replaces ("the mechanism itself...
                // is row-agnostic in the model") — resolved for ANY row with a real `EuclidLine`, not gated
                // behind `isEuclideousRow` the way the LANES-GRID-specific mute/grid block below still is.
                // RENDER-THREAD SAFETY (invariant 3: no allocation on the render path): `migrateRestartChains`
                // itself allocates (it walks and fits an arbitrary-length mark list) and is NOT safe to call
                // here. Migration instead happens on the MAIN thread (`AudioUnitViewController`'s resync
                // loop, where host beat-position context is ALSO available) and is pinned into the real
                // fields immediately on load — not deferred until an edit — specifically so the render
                // thread never needs to migrate anything itself: by the time real audio renders, a
                // pre-feature lane has normally already been pinned. `line.usesRestartChains == false`
                // here is therefore only the brief window before that first resync tick lands (or a
                // document built directly in a test, bypassing the AVC entirely) — FREE is a safe,
                // allocation-free default for that window, not a silent, permanent behaviour change.
                // LISTEN REBUILT fix (§3.5): "The follower's own RHYTHM RESTART and MELODY RESTART are not
                // read while COPY or FILL is on" (a leftover/independently-set chain must not shift its
                // phase) — AND "the follower restarts with every source restart" (×1/×2/×4) / "every 2nd or
                // 4th source restart" (×½/×¼). Both land from the SAME substitution: a borrowing lane reads
                // the SOURCE's own chain fields instead of its own, with `lapBeats` built from the
                // FOLLOWER's own (already SPEED-scaled) `cycleLen`/`sub` — so the chain's bar-based restart
                // schedule is unchanged (still the source's real restart moments) while how many of the
                // follower's own laps fit between them scales with SPEED exactly as §3.5 describes.
                // (Confirmed necessary, not just "safe to skip": `testShadowFollowsARhythmChainThatCutsThePassShort`
                // regressed when this first tried plain `.off` — a COPY+SHADOW lane needs the source's real,
                // chain-cut-short timing to sample the source's strikes at the right moments.)
                if lineIndex < linesView.count {
                    let line = copyOrFillValid ? linesView[listenSource] : linesView[lineIndex]
                    if line.usesRestartChains {
                        chains = EuclideousLaneRestartChains(rhythm: .from(line.restartRhythmBars ?? []),
                                                             melody: .from(line.restartMelodyPasses ?? []),
                                                             barBeats: beatsPerBar, lapBeats: Double(cycleLen) * sub)
                    }
                }
                if isEuclideousRow, lineIndex < linesView.count {
                    let line = linesView[lineIndex]
                    let passBeats = Double(cycleLen) * sub
                    let g = euclideousLaneGridResolved(line: line, lane: lineIndex, legacyOn: p.euclideousLanesSeqOn,
                                                       legacyRate: p.euclideousLanesSeqRate, legacyLen: p.euclideousLanesSeqLen,
                                                       legacyCells: p.euclideousLanesSeqCells, stepBeats: sub, passBeats: passBeats,
                                                       beatsPerBar: beatsPerBar)
                    muteCells = g.muteCells
                    muteUnitBeats = g.muteUnit.beats(stepBeats: sub, passBeats: passBeats)
                }
                // The pre-grid re-anchor (machine-wide bars span / bar ladder) applies only while a chain carries no restart mark.
                let ladderSpanBeats = p.euclideousResetSpanBars > 0 ? Double(p.euclideousResetSpanBars) * cyc
                    : (p.euclidSpanN > 0 ? spanLadderBeats(p.euclidSpanN, S: S, row: cyc) : 0)
                // `spanBeats` is also the LISTEN coincidence lookups' coarse re-anchor: one full restart cycle while a chain is in
                // force (the rhythm chain's own cycle, or the melody chain's when rhythm is FREE), else the ladder span — matching
                // the old grid's own "one full restart window" role, now sized from the chain instead of the 16-cell window.
                let spanBeats = chains.isActive
                    ? (!chains.rhythm.isFree ? Double(chains.rhythm.total) * chains.barBeats : Double(chains.melody.total) * chains.lapBeats)
                    : ladderSpanBeats
                // cycleLen (2n under PING-PONG, else n): looping the hit-count over the FULL cycle naturally
                // double-counts a ping-pong's repeated endpoints the same way the real read-sequence does — no
                // ×2 special-case needed (every buffer position 0..<n is visited exactly twice per 2n-tick lap).
                // factored once (Paul 2026-10-02, hit/miss split) — the SAME "is step s a hit" test the original
                // cycleHits/hitsUpTo loops already repeated inline; the new MISS path below needs a third copy,
                // so this is a pure de-duplication, not a behaviour change.
                func isHitAt(_ s: Int) -> Bool { euclidBuf[euclidReadIndex(s, n: eN, dir: eDir)] }
                var cycleHits = 0; for s in 0..<cycleLen where isHitAt(s) { cycleHits += 1 }
                let effHits = Int64(max(1, cycleHits))
                iterateTicks(row: r, effColumn: effColumn, sub: sub, gateFraction: 0.9,
                             beatPos: beatPos, windowBeats: windowBeats, windowStart: windowStart,
                             beatsPerSample: beatsPerSample, S: S, a: a, columns: max(1, Int((cyc / S).rounded())),
                             lineIndex: lineIndex, tickFrom: tickFrom, tickBefore: tickBefore,
                             strikeDelaySteps: { t in
                                 // RHYTHM POLISH: the hit read at tick `t` sounds this many steps into its cell (0 for a lane with no timing, or a tick that isn't a hit)
                                 guard timingActive else { return 0 }
                                 let ph = euclideousLaneChainPhase(buf: euclidBuf, n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, tick: t, chains: chains, legacySpanBeats: ladderSpanBeats)
                                 return ph.rawIsHit ? euclidTickDelay[ph.raw] : 0
                             }) { tick, mTickBeat, _, _ in
                    refreshStack(atBeat: mTickBeat)   // SOURCES STACK: re-merge if the CHORDS column changed at THIS tick's beat (chord-contributing docs only)
                    // SPAN RE-ANCHOR: FREE (spanBeats 0) = the global grid; else re-sync to step 0 every N cols. Pure/
                    // replay-exact. Kept as exact Int64 arithmetic, not routed through the continuous `euclidPhase`
                    // used by the GridUI comet-bar — a discrete hit/rest decision needs exact integer ticks, a
                    // comet's visual position tolerates float imprecision invisibly; the two shouldn't share a code
                    // path just because they share a CONCEPT (the same rate/span/anchor reading).
                    // PER-LANE RESET is LEN-RELATIVE (2026-10-14 ferry §5, fixed by a self-audit against the
                    // ferry's own text; generalised to an arbitrary mask by the 2026-10-15 ferry): re-anchors
                    // against the LANES sequencer's own lap boundary (`euclideousMaskedResetOrigin`), not a
                    // plain `columnStart` from absolute beat 0 — the two formulas only coincidentally agreed
                    // at the default LEN=8 every-N presets (every one of 1/2/4/8 divides it evenly); any other
                    // LEN, or any hand-placed mask, would silently diverge from the on-screen restart marks.
                    // RESTART CHAINS (2026-10-19): where this tick sits in the pattern — the tick count since the RHYTHM origin — comes from the
                    // one chain-era per-tick core (`euclideousLaneChainPhase`), the same call the next-hit gap, the TIE lookahead, the roll and
                    // the walk-tag mirror make. A tick is `tick × sub` beats; `mTickBeat` below is that same value.
                    let ph = euclideousLaneChainPhase(buf: euclidBuf, n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, tick: tick,
                                                      chains: chains, legacySpanBeats: ladderSpanBeats)
                    let localT = ph.localT
                    let raw = ph.raw
                    let rawIsHit = ph.rawIsHit
                    let cy = (localT - Int64(raw)) / Int64(cycleLen)   // floored cycle since the rhythm origin (localT = cy·cycleLen + raw) — the MISS ordinal below reads it, and LISTEN REBUILT's ECHO cycle-roll (§4.2)
                    // LISTEN REBUILT (§3): COPY/FILL already REPLACED `euclidBuf` itself with the borrowed
                    // pattern above — there is no separate per-tick filter any more (unlike the old WITH/
                    // GAPS, which filtered THIS lane's own rhythm against a coincidence test).
                    // §3.6 fix: "before the first DELAY steps of a transport run have passed, it plays
                    // nothing" — a TRUE rest (not a muted-but-still-counted hit, confirmed by §11.8's own
                    // worked example: ECHO's hit rank j must start at 0 on the first tick that actually
                    // sounds, not on the grace-period ticks), so this folds into `isHit` itself, upstream
                    // of the riff walk / ECHO's `euclideousEchoFollowerJ` counter / everything else that
                    // reads "was this tick a hit."
                    let withinDelayGrace = copyOrFillValid && listenDelay > 0
                        && (mTickBeat - euclideousListenTransportStartBeat) < Double(listenDelay) * sub - 1e-9
                    let isHit = rawIsHit && !withinDelayGrace
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
                    // the 8×8 grid calls too (confirmed — `linesView` is always populated, even for a
                    // plain single-EUCLID cell, so `lineIndex` 0...3 is NOT unique to Euclideous's own 4
                    // lanes). Without this guard, an ordinary EUCLID processor on any other row would also
                    // write into this SAME 4-slot queue, corrupting Euclideous's own NOTE VIEW with
                    // whichever unrelated cell happened to strike most recently.
                    // ferry: a hit produces a NOTE VIEW event (UI flare telemetry) if EITHER layer would leave anywhere — the union of the two parts. Both equal emitterMask for an existing lane, so byte-identical.
                    let nvSent = isEuclideousRow && chopMask(cell, m: mTickBeat, S: S, base: (riffBus ?? bm) | (notesBus ?? bm)) & p.mainOutMask != 0
                    func nvTiming(_ gateBeatsReal: Double) -> (onset: Double, duration: Double) {
                        let onsetReal = realOf(mTickBeat, stepBeats: S, a: a)
                        let offReal = realOf(mTickBeat + gateBeatsReal, stepBeats: S, a: a)
                        return (onsetReal, offReal - onsetReal)
                    }
                    // GATE FOLLOWS THE RHYTHM (2026-10-13 ferry) — computed once per tick, Euclideous-only
                    // (§3: the legacy non-Euclideous `useRiff`/plain-NOTE-mode forks below keep the OLD
                    // `min(sub * gate, S * 0.95)` formula untouched). `nextHitGapBeats` is the gap to the
                    // lane's own NEXT REAL pattern hit (§1.2: "after RHYTHM INV and hand edits, at the
                    // lane's rate... wrapping across the end of the cycle... include a reset if one falls
                    // before it") — mask-oblivious by construction (§1.3), bounded at the SAME cap
                    // `riffTieExtensionBeats` already uses so the two forward-scans this combines with
                    // (`nextHitGapBeats + tieExt`) share one consistent bound. `overlapBeats10ms`/
                    // `minGateBeats5ms` convert the ferry's literal 10ms/5ms into beats via the live tempo
                    // (closure-captured from `emitGeneratorRow`'s own new `tempo` parameter).
                    let nextHitGapBeats = isEuclideousRow
                        ? euclideousNextChainHitGapBeats(buf: euclidBuf, n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, tick: tick, cap: cycleLen * 4,
                                                          chains: chains, legacySpanBeats: ladderSpanBeats, timing: hitTiming)
                        : sub
                    let overlapBeats10ms = 0.010 * (tempo / 60.0)
                    let minGateBeats5ms = 0.005 * (tempo / 60.0)
                    // §3.1, literal: "length = the gap UP TO the tied hit, plus GATE × the FOLLOWING gap."
                    // Only the TIE's own extension scales with GATE — the gap up to the tied hit itself
                    // (already counted once in `nextHitGapBeats`) is always full/unscaled, since the note
                    // hasn't reached a real gate decision yet at that point. Caught by writing the
                    // acceptance test for this exact case, not assumed: the naive `gate * nextHitGapBeats +
                    // tieExt` (scaling BOTH segments together) would wrongly shrink the first segment too.
                    // MIX TAB (2026-10-18): per PITCH — each sounding pitch's length reads ITS OWN gate `g` (the riff pitch the lane's GATE, lit
                    // notes/TOP/TOP2 the notes gate), through the one pure `euclideousPitchGateBeats`; the 5 ms floor is unchanged.
                    func gateBeatsWithTie(_ g: Double, _ tieExt: Double) -> Double {
                        euclideousPitchGateBeats(gate: g, nextHitGapBeats: nextHitGapBeats, tieExt: tieExt, minGateBeats: minGateBeats5ms)
                    }
                    // LANES GRID §2.1/§2.2: the lane's MUTE is resolved PER HIT, at the hit's own beat — a hit on the first tick of a new cell takes
                    // the NEW cell's state (the old once-per-render-window decision took the previous step's). A muted hit still advances the walk
                    // (the existing "mute but keep walking" rule below), so muting never shifts the melody or the rhythm.
                    // LANE SOLO (ferry 2026-10-21, §5.2): a lane the solo mask silences goes through this SAME early return — it keeps walking (pattern, riff position, restarts, passes, DYNAMICS), nothing emits, the
                    // pulse feed sees no strike. `euclideousLaneMayStrike` is the one decision (the lane is already known to be enabled here); mask 0 — and every non-Euclideous row — is exactly the old test.
                    let lanesSeqMuted = !euclideousLaneMayStrike(lane: lineIndex, soloMask: isEuclideousRow ? soloMaskNow(snapshot: p.soloMask) : 0,
                                                                 muteAudible: euclideousLaneAudible(beat: mTickBeat, cells16: muteCells, unitBeats: muteUnitBeats), enabled: true)
                    if isHit {
                        // VELOCITY 0 = EFFECTIVELY OFF (Paul 2026-10-03: "investigate if the lane is effectively
                        // off with zero velocity") — confirmed by testing, not assumed: strikeChord's own
                        // clampVel floors EVERY note to MIDI 1...127 (the inherited-velocity-safety floor, not
                        // meant for this), so a line scaled to 0 was still striking audibly at velocity 1, never
                        // actually silent. Skip the strike entirely instead — this is what "zero velocity" means
                        // to a user reading the control. Checked BEFORE any of the (possibly expensive) RIFF/ARP/
                        // pool resolution below, not just at the final strikeChord call.
                        guard velocity > 0 else { return }
                        // EUCLID MASK — REPEAT HOLD CONTINUATION (Paul 2026-10-10 ferry §3): while a repeat
                        // is in progress, it takes ABSOLUTE priority — re-strike the cached note and decrement,
                        // with no re-evaluation of the mask test at all for the duration of the hold ("holding
                        // the riff walk" is read as holding the WHOLE per-tick decision process, not just the
                        // riff cursor specifically, avoiding any ambiguity about a second masked step occurring
                        // mid-hold). The walk/SHIFT/rank pipeline below never runs during a hold.
                        if euclideousMaskRepeatRemaining[lineIndex] > 0 {
                            euclideousMaskRepeatRemaining[lineIndex] -= 1
                            // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry): Euclideous's
                            // own row replays the WHOLE widened cache (`euclideousLastSoundedNotes`/`Count`,
                            // written by the new `isEuclideousRow` pipeline's own REPEAT-trigger branch
                            // below) — every OTHER row keeps replaying the original singular
                            // `euclideousLastSoundedNote` exactly as before, byte-identical.
                            if isEuclideousRow {
                                let n = euclideousLastSoundedCount[lineIndex]
                                if n > 0 {
                                    var cachedPitches = takeScratch(&hitCachedPitches, count: 9, filledWith: 0)
                                    var cachedVels = takeScratch(&hitCachedVels, count: 9, filledWith: 0)
                                    var cachedGates = takeScratch(&hitCachedGates, count: 9, filledWith: 0)
                                    defer { hitCachedPitches = cachedPitches; hitCachedVels = cachedVels; hitCachedGates = cachedGates }
                                    for i in 0..<n {
                                        cachedPitches[i] = Int(euclideousLastSoundedNotes[lineIndex * 9 + i])
                                        cachedVels[i] = euclideousLastSoundedVels[lineIndex * 9 + i]
                                        cachedGates[i] = euclideousLastSoundedGates[lineIndex * 9 + i]
                                    }
                                    let gb = max(minGateBeats5ms, cachedGates[0] * nextHitGapBeats)   // NOTE VIEW's one duration: pitch 0's (the riff note when the hit has one)
                                    // GATE/legato: a REPEAT-hold's cached set IS, by definition, exactly what's
                                    // already tracked — reconcile naturally resolves every one of them as HELD
                                    // (no re-strike) at 100%, correctly continuing to extend rather than
                                    // restriking each tick; below 100% it clears tracking and this falls
                                    // through to the OLD per-tick restrike loop, now on the new gap-based gate.
                                    // ferry §4.1: a REPEAT-HOLD replay is the riff layer — route it to riffBus (pitchBus isn't built on this early path).
                                    let handled = reconcileEuclidLegato(lineIndex: lineIndex, pitches: cachedPitches, pitchCount: n, vels: cachedVels, gates: cachedGates,
                                                                         tau: mTickBeat, isRatchetThisHit: false, overlapBeats: overlapBeats10ms, busOf: { _ in riffBus })
                                    for i in 0..<n where handled & (UInt16(1) << UInt16(i)) == 0 {
                                        strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: max(minGateBeats5ms, cachedGates[i] * nextHitGapBeats), octave: 0,
                                                    explicitNote: cachedPitches[i], explicitVel: cachedVels[i], busOverride: riffBus)
                                    }
                                    if nvSent {
                                        var nc = 0
                                        for i in 0..<n where nc < Router.noteViewMaxNotes { if let p = finalPitch(Int(euclideousLastSoundedNotes[lineIndex * 9 + i]), oct: 0) { nvScratch[nc] = p; nvVelScratch[nc] = euclideousLastSoundedVels[lineIndex * 9 + i]; nc += 1 } }
                                        if nc > 0 {
                                            let (onset, duration) = nvTiming(gb)
                                            pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 0, noteCount: nc, withVels: true)
                                        }
                                    }
                                }
                                return
                            }
                            let cached = euclideousLastSoundedNote[lineIndex]
                            if cached >= 0 {
                                let gb = min(sub * gate, S * 0.95)
                                strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: gb, octave: 0, explicitNote: Int(cached), explicitVel: euclideousLastSoundedVel[lineIndex], busOverride: riffBus)   // ferry §4.1: REPEAT-HOLD replay = riff layer
                                if nvSent, let p = finalPitch(Int(cached), oct: 0) {
                                    nvScratch[0] = p
                                    let (onset, duration) = nvTiming(gb)
                                    pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 0, noteCount: 1)
                                }
                            }
                            return
                        }
                        // ord (Paul 2026-09-29 v1b, widened 2026-10-02 for the RIFF/ARP sources below; DIE REMOVED
                        // 2026-10-02 "drop it, please" — a plain, unsalted ordinal): a monotonic, STATELESS "which
                        // hit number is this" — cycle count × this line's own hit density + the within-cycle hit
                        // rank. Hoisted above the pick switch (was computed only inside .cycle/.random) since
                        // .riff/.arp consume it too.
                        // RESTART CHAINS: the chain-era per-tick core gives `hitsUpTo` / `ord` (counted from the RHYTHM origin — a plain NOTE-mode
                        // pick keeps following the rhythm) AND `advOrd`, the riff walk's ordinal, counted from the MELODY origin. No `locked:`
                        // parameter — a melody chain of exactly [1] reproduces old LOCK's own re-anchoring with no special-casing (§4.7).
                        let tickInfo = euclideousLaneChainTick(buf: euclidBuf, n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                                               legacySpanBeats: ladderSpanBeats, advanceStep: riffAdvanceStep)
                        let hitsUpTo = tickInfo.hitsUpTo
                        let ord = tickInfo.ord
                        // EUCLID MASK (Paul 2026-10-10 ferry) — §2.1: "advances one step per SOUNDING step of
                        // its lane, i.e. after the lane's HIT/MISS invert is applied." `isHit` above is already
                        // POST-invert (ferry C's own `patternMiss` toggle happens before `cycleHits`/`isHitAt`
                        // are ever read), so every genuinely-sounding tick that reaches this point (we're
                        // already inside `if isHit`, past the velocity>0 guard) is exactly the right place to
                        // advance the mask. SCOPE, a disclosed judgment call: the mask's PITCH-affecting modes
                        // (MIRROR/LEAP) are riff-position concepts with no meaning in plain NOTE mode and are
                        // gated `useRiff` below at their own application sites; every other mode (MUTE/PAUSE/
                        // RATCHET/REPEAT/CHORD/OCT/ACCENT/CLIMB/SWELL) applies in both modes alike, since each
                        // only needs "a final resolved note/velocity/gate," which exists either way.
                        let mm = mask
                        var maskedChancePassed = false
                        if mm.enabledResolved {
                            // No separate dedup needed here: `iterateTicks` itself already dedups per
                            // (row, lineIndex) — this closure body runs at most once per real tick for this
                            // lane, the SAME guarantee the walk-advance state above relies on.
                            // RESTART CHAINS (ferry §5.5): a rhythm restart re-anchors the mask's own hit
                            // position too, derived fresh every tick from `ph` (not a stored "last restart"
                            // flag) — `ph.localT == 0` is exactly "this tick IS the rhythm origin." Checked
                            // only `if ph.gridOn` so the existing pause/resume-while-disabled nuance (the
                            // ordinal doesn't advance, and now doesn't reset, while `mm.enabledResolved` is
                            // false) is unchanged from today.
                            if ph.gridOn, ph.localT == 0 { euclideousMaskOrd[lineIndex] = 0 }
                            euclideousMaskOrd[lineIndex] += 1
                            let maskN = max(2, min(16, mm.stepsResolved))
                            let maskK = max(0, min(maskN, mm.pulsesResolved))
                            var maskBuf = takeScratch(&hitMaskBuf, count: 16, filledWith: false)   // maskN ≤ 16; `euclidPatternInto` writes only [0, maskN) and `maskBuf[maskPos]` reads inside it
                            defer { hitMaskBuf = maskBuf }
                            euclidPatternInto(&maskBuf, pulses: maskK, steps: maskN, rotation: mm.rotate ?? 0)
                            let maskOrdNow = euclideousMaskOrd[lineIndex]
                            let maskPos = Int((maskOrdNow - 1) % Int64(maskN))
                            // UI-POLLABLE POSITION (see the array's own doc comment above): updates on
                            // EVERY sounding hit the mask evaluates, whether or not that particular step
                            // turns out engaged by the mask's own K/N pattern — "progressing on hits from
                            // the Euclid lane" is the hit itself, not just the subset the mask happens to
                            // mask.
                            euclideousMaskStep[lineIndex] = maskPos
                            if maskPos >= 0 && maskBuf[maskPos] {
                                // CHANCE (§2.3, Seed Law): seeded purely on the mask's own ordinal — the SAME
                                // "derived from a stateless count, reseeds for free the instant the count resets"
                                // technique the existing (unrelated) chain-processor EUCLID MASK's own CHANCE
                                // already uses (`splitmix64Mix` on an ordinal `g`) — §2.5's "reseeds on the global
                                // reset" falls out automatically here, since `euclideousMaskOrd` itself resets to
                                // 0 there; no separate persisted seed needed.
                                let roll = Double(splitmix64Mix(UInt64(bitPattern: maskOrdNow) &+ UInt64(lineIndex) &* 0x9E3779B97F4A7C15 &+ 0xA24BAED4963EE407) & 0xFFFF) / 65535.0
                                if roll < mm.chanceResolved { maskedChancePassed = true }
                            }
                        }
                        // PAUSE (§3): silent AND the walk does not advance — must pre-empt EVERYTHING below,
                        // including entering `if useRiff {}` at all, since that's where the walk cursor moves.
                        if maskedChancePassed && mm.modeResolved == .pause { return }
                        // EUCLIDEOUS RIFF ADVANCE (Paul 2026-10-06): "each hit will progress riff by 1 step" —
                        // REPLACES noteSel/octave entirely when in RIFF mode (checked BEFORE the .riff/.arp
                        // sequential-source branch further below, not layered after it, so this wins regardless
                        // of whatever noteSel happens to be stored underneath — Paul's own ruling, not a guess).
                        // For every remaining direction this needs zero new memory: `ord` (just computed above)
                        // IS "which hit number is this," stateless — feeding it straight into `riffStepAt` gives
                        // "which step plays on this hit" with no accumulated state at all. `riffRotate`/
                        // `riffOctave` are this LANE's own independent offset into the one shared pattern (Paul:
                        // "independent cursor per lane") — rotate matches `euclidPatternInto`'s own `(i + rot) %
                        // n` read-index convention exactly (see `riffRotateStep`). OCTAVE REPLACES this line's
                        // own `octave` rather than stacking with it (passed 0 below) — the gesture pad that used
                        // to drive `octave` now drives `riffOctave` exclusively, so consulting the old frozen
                        // value too would silently reintroduce an offset the user can no longer see or edit.
                        //
                        // WALK ADVANCE NOW RUNS UNCONDITIONALLY ON MODE (Paul 2026-10-13 ferry, "Behaviour" rule
                        // 3: "in note mode, the riff walk keeps advancing silently, so it comes back in phase" —
                        // the user's own disclosed interpretation). Previously this whole computation lived
                        // INSIDE `if useRiff {}`, so switching a lane to NOTE mode froze its walk position dead
                        // — found by tracing, not assumed, before restructuring. Hoisted ABOVE the `if useRiff`
                        // fork because it needs NONE of the pool/rank machinery below (`thisLaneCount`/`notes`/
                        // `ranks`) — only the direction/stride/length/rotate/lock/advance-step params and the
                        // ord-family locals already computed above this point, all available regardless of
                        // mode or row. COMPUTED FOR EVERY ROW, not just Euclideous's own — a real bug caught
                        // and reverted: an earlier draft gated the WHOLE computation on `isEuclideousRow`
                        // (reasoning "only Euclideous has a riff walk to advance"), which silently froze
                        // `playedStep` at its harmless 0 default for every one of the many pre-existing
                        // RouterTests that build a riff-enabled `EuclidLine` at a plain row (0, not
                        // `Snap.euclideousRow`) — `isEuclideousRow` is specific to the ONE reserved row
                        // Euclideous's own UI happens to render at, not to "is this a riff-mode EuclidLine,"
                        // and the generic `[useRiff: true]` mechanism itself long predates Euclideous's own
                        // page/row (used standalone, by any chain cell, anywhere). ONLY the two STATE-ARRAY
                        // WRITES below are still gated — `euclideousRiffStep`/`euclideousRiffLastOrd` are fixed
                        // 4-slot arrays dedicated to Euclideous's own 4 lanes specifically (its UI's own
                        // markers/footers poll reads them by lineIndex 0...3), but `runEuclidLine` is called
                        // for EVERY `.euclid` cell's lines, Euclideous or not — writing them unconditionally
                        // would let an unrelated, non-Euclideous grid cell's own EUCLID line overwrite these
                        // same 4 slots underneath Euclideous's real lanes. DRUNK is gone from this path
                        // entirely (ferry "Remove": "The DRUNK option" — removed from Euclideous's own walk
                        // only; the UNRELATED generic chain RIFF processor keeps its own separate DRUNK state/
                        // control untouched, see `riffDrunkPos`/`riffDrunkStep` elsewhere in this file). A
                        // non-Euclideous riff-enabled line still walks via DRUNK's removal too, since
                        // `riffDir`/`riffDirSeed`/`riffDirBias` are per-`EuclidLine` fields, not gated by row
                        // either — any PRE-EXISTING test/doc that set `riffDir: .drunk` on a plain-row line
                        // now falls through `riffStepAt`'s own exhaustive switch to its `.drunk` arm, which
                        // returns the plain forward position (documented there as "never actually reached" by
                        // the ORIGINAL Euclideous-only caller — now genuinely reachable for a non-Euclideous
                        // line, a disclosed consequence of DRUNK's removal being scoped to Euclideous's own
                        // UI/engine path, not to the shared `RiffDir` enum's own exhaustiveness).
                        //
                        // FREE / LOCK (Paul 2026-10-09 ferry, "three new per-lane riff options"): LOCK
                        // re-anchors the riff's own position to its start at the FIRST hit of every lap of
                        // THIS LANE's own Euclid pattern. `hitsUpTo` (computed just above, for `ord`
                        // itself) is ALREADY "how many hits from position 0 up to this one, scanned fresh
                        // within ONE lap's pattern" by construction (the scan is always `0...raw`, and
                        // `raw` is always < cycleLen) — so `hitsUpTo - 1` IS exactly "position within the
                        // CURRENT lap," genuinely stateless, needing no new bookkeeping for any remaining
                        // direction — this is the WHOLE mechanism for FWD/REV/PEND/PING.
                        // ADVANCE (Paul 2026-10-10 ferry §3.5): HIT keeps today's hit-ordinal (`ord`/
                        // `hitsUpTo`); STEP advances on EVERY tick of this lane's own pattern, hit or
                        // miss — `localT` (the true monotonic per-tick count, already computed above)
                        // and `raw` (its lap-local form) are exactly the counters this needs, zero new
                        // state required. Both still only ever get EVALUATED at an actual hit (nothing
                        // strikes on a miss unless the separate MISS-side settings fire) — STEP changes
                        // WHICH ordinal value is fed in, not WHEN the walk position gets computed.
                        let advOrd: Int64 = tickInfo.advOrd
                        // RESET SPAN (Paul 2026-10-08): "the global reset span still applies on top of
                        // both modes" — the Euclid PATTERN's own phase is still re-anchored upstream
                        // (unchanged, computed earlier for `ord`/`hitsUpTo` themselves); the riff WALK's own
                        // extra `spanStart` re-anchor was DRUNK-only (a random walk needed an explicit nudge
                        // to hard-reset at a span boundary — every other direction already resets for free
                        // via `ord` alone) and is removed along with DRUNK — nothing computes or reads a
                        // separate `spanStart` in this function any more.
                        // STRIDE (§3.4): multiplies the ordinal fed into `riffStepAt` — FWD/REV/
                        // PENDULUM/PINGPONG all generalize this way (hand-verified against Paul's own
                        // worked example: stride 3 / length 5 → (ord*3) mod 5 for ord=0..4 gives
                        // 0,3,1,4,2 → 1-indexed 1,4,2,5,3, exactly matching §3.4's literal sequence).
                        // LENGTH (§3.2): every direction's own modulus is now `riffLength`, not the
                        // shared riff pattern's full step count — the lane walks only steps 1...LENGTH
                        // of the shared pattern, wrapping/reflecting within that window alone. `seed`
                        // still threads through for a legacy `.random` document (RANDOM was already
                        // retired from this page's own UI before this ferry, per an earlier ruling — not
                        // re-removed here, just never freshly reachable) so it keeps resolving exactly as
                        // it always has rather than silently changing behaviour for an old saved lane.
                        let seed = UInt64(bitPattern: Int64(riffDirSeed))
                        // RIFF WALK ferry §5.2: the column a hit reads is now ONE call —
                        // `euclideousRiffColumn` — built on the walk step w = floor(advOrd ÷ EVERY), not the
                        // raw ordinal directly. EVERY 1 (riffAdvanceEvery's default) makes w == advOrd, so
                        // this is byte-identical to the old two-line riffStepAt/riffRotateStep pipeline at
                        // EVERY 1 (test 1/test 3).
                        let playedStep = euclideousRiffColumn(ordinal: advOrd, every: riffAdvanceEvery, direction: riffDir, length: riffLength, stride: riffStride, shift: riffRotate, seed: seed)
                        if isEuclideousRow {
                            euclideousRiffStep[lineIndex] = playedStep   // the cursor updates even on a rest, so the UI tracks real motion through the whole pattern — now true in BOTH modes
                            euclideousRiffLastOrd[lineIndex] = advOrd    // RIFF MARKERS/FOOTERS poll (2026-10-12): the ordinal this cursor just advanced on
                        }

                        // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry — "This amends
                        // [the MELODY tab] instructions... replaces: the one-choice-at-a-time behaviour").
                        // Supersedes the mutually-exclusive NOTE-mode-vs-RIFF-mode fork below (`if useRiff
                        // {} else {<plain pick>}`) for EUCLIDEOUS's OWN row only — every other `.euclid`
                        // cell anywhere else in the grid (the regular, non-Euclideous BUILD-page processor,
                        // which has no UI for lit notes/riffOn and never sets them — `riffOnResolved`'s own
                        // migration safely falls back to FALSE for a genuinely untouched line, confirmed by
                        // construction in Models.swift) falls through to that UNCHANGED code exactly as
                        // before. Two independent, ADDITIVE layers: any of the 8 ranks/TOP/TOP2 can be lit
                        // at the same time the riff is on; both sound together on a hit where the riff
                        // resolves a real note.
                        if isEuclideousRow {
                            let thisLaneCount = laneCount(lineIndex)
                            let notes = laneNotes(lineIndex)
                            // WHICH RIFF IS PLAYING (2026-10-14 ferry §6/§7): four independently-stored
                            // riffs, picked either by the RIFFS sequencer (per-step, when its own PLAY is
                            // on) or by whichever tab is currently active in the editor (RIFFS off — "the
                            // selected tab plays," so editing and playback share one control, per the
                            // ferry's own disclosed dual-role reading of `activeRiff`). Resolved freshly
                            // PER HIT (`mTickBeat`, not the render-window-level `fBeatPos` the LANES mute
                            // check above uses) — a riff SWITCH directly changes which pitch sounds, not
                            // just whether one does, so the finer grain is worth it here.
                            // DISCLOSED JUDGMENT CALL (not addressed by the ferry's own text, raise back to
                            // design): `riffTieExtensionBeats` below is a closure capturing THIS `ranks`
                            // local — a riff switch landing inside its own forward TIE-lookahead scan is
                            // NOT re-resolved; the riff selected at the CURRENT hit is used for the whole
                            // lookahead, simplest-correct in the common case (a RATE-1-bar-or-slower RIFFS
                            // sequencer vs. a short TIE window), wrong only in a narrow edge case.
                            // LOOPER TABS (FERRY "looper tabs replace the riff tabs", ratified 2026-10-16) —
                            // SUPERSEDES the old per-riff lookup above (`playingRiffIdx`/`p.euclideousRiffs`
                            // decode-only now). §6.1/§6.2: the ONE pure `euclideousLooperEffectiveRank`
                            // decides a column's rank — called here once per column to rebuild the SAME
                            // `ranks`-shaped local every other line in this hit already reads by that name
                            // (the LISTEN/SHADOW partner-note lookup below, and `riffTieExtensionBeats`'s own
                            // forward scan). The looper's own fields are plain `SnapParams` — no render-
                            // thread bookkeeping of any kind (§6.4: the render thread never records; the
                            // main thread owns the loop and publishes it the ordinary way).
                            let euclideousLiveGridRanksForHit = p.euclideousLiveGrid.ranksResolved
                            var ranks = takeScratch(&hitRanks, count: 8, filledWith: 0)
                            defer { hitRanks = ranks }
                            for col in 0..<8 {
                                ranks[col] = euclideousLooperEffectiveRank(column: col, beat: mTickBeat, liveGrid: euclideousLiveGridRanksForHit,
                                                                            active: p.euclideousLooperActive, startBeat: p.euclideousLooperStartBeat,
                                                                            passes: p.euclideousLooperPasses, startRanks: p.euclideousLooperStartRanks,
                                                                            events: p.euclideousLooperEvents, beatsPerBar: beatsPerBar)
                            }
                            // NOTES TAB (2026-10-19, §6.7): a lit note's per-rank octave shift no longer sounds — the closure that read it is gone. `notesVel` below is the notes layer's own
                            // base velocity; the riff note keeps the lane's plain `velocityAbsolute` untouched.
                            let notesVel = UInt8(max(1, min(127, notesVelocity)))   // MIX TAB: the notes layer's OWN velocity (resolved — nil ⇒ VEL + the legacy offset — at the call site)
                            // MERGED, DEDUPED STRIKE SET (Engine rule 2: "at most nine distinct pitches per
                            // hit... fixed-size buffers, no allocation or locking on the audio thread") — a
                            // plain stack local, not a stored ivar: its lifetime is exactly one hit, the same
                            // class of "transient per-tick scratch" as `hitsUpTo`/`ord` themselves just above.
                            // `pitchVel` is the per-pitch velocity sibling (RIFF/NOTES SPLIT): first-insertion-
                            // wins, same as pitch dedup itself, which is what gives "riff wins on a pitch
                            // collision" for free — the riff layer's own `addPitch` call always runs first.
                            var pitches = takeScratch(&hitPitches, count: 9, filledWith: 0)
                            var pitchVel = takeScratch(&hitPitchVel, count: 9, filledWith: 0)
                            defer { hitPitches = pitches; hitPitchVel = pitchVel }
                            // MIX TAB (2026-10-18): `pitchGate` is the per-pitch GATE sibling to `pitchVel` — same fixed 9-slot storage, same
                            // first-insertion-wins (so on a collision the RIFF pitch's gate wins, exactly as its velocity already does).
                            var pitchGate = takeScratch(&hitPitchGate, count: 9, filledWith: 0)
                            defer { hitPitchGate = pitchGate }
                            // PER-LAYER ROUTING ferry (2026-10-25): each merged pitch's own output mask. `busOf(j)` is what every
                            // strike/defer below reads in place of the lane-wide `busOverride`. For every existing lane riffBus ==
                            // notesBus == emitterMask, so every slot gets emitterMask and the collision never splits → byte-identical.
                            var pitchBus = takeScratch(&hitPitchBus, count: 9, filledWith: -1)
                            defer { hitPitchBus = pitchBus }
                            func busOf(_ j: Int) -> UInt8? { j < 9 && pitchBus[j] >= 0 ? UInt8(pitchBus[j]) : nil }
                            // ── ALT ROUTING ferry (2026-10-25) §5–§6 ──────────────────────────────────────────────
                            // Hoist the group function's per-hit inputs (only computed when some ALT mode is on, so the
                            // golden path pays nothing). q = ord, s = localT, p = altPass, h = altH, the rest-hit flag and
                            // the two SPLIT-by-rank thresholds (SPLIT-LOWEST / SPREAD are set-dependent — `groupOf` defers
                            // them with -2 to the post-pass).
                            let altActive = alt.map { $0.riff.alt.mode != .off || $0.notes.alt.mode != .off } ?? false
                            let altPass = altActive ? euclideousFXNotePass(advOrd: advOrd, every: riffAdvanceEvery, riffDir: riffDir, length: riffLength, stride: riffStride, melodyEveryPass: chains.melody.isSingleLink1, lapsSinceRhythmOrigin: cy) : 0
                            let altH = altActive ? euclideousLaneChainTick(buf: euclidBuf, n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains, legacySpanBeats: ladderSpanBeats, advanceStep: false).advOrd : 0
                            let altIsRestHit = ranks[playedStep] < 1
                            let riffSplitT: Int = { guard let a = alt?.riff.alt, a.mode == .split, !a.splitLowest else { return Int.max }
                                return riffResolve(rank: a.splitRank, oct: riffOctave, n: thisLaneCount, wrap: .fold, asc: { notes[$0].note }) ?? Int.max }()
                            let notesSplitT: Int = { guard let a = alt?.notes.alt, a.mode == .split, !a.splitLowest else { return Int.max }
                                return riffResolve(rank: a.splitRank, oct: octave, n: thisLaneCount, wrap: .fold, asc: { notes[$0].note }) ?? Int.max }()
                            // the pending-collision scratch (a notes pitch colliding with a riff slot whose group is SPREAD/
                            // SPLIT-LOWEST and so unknown until the post-pass); dedicated ivars, no allocation.
                            var pendColCount = 0
                            var pendColPitch = takeScratch(&hitPendColPitch, count: 9, filledWith: 0)
                            var pendColVel = takeScratch(&hitPendColVel, count: 9, filledWith: 0)
                            var pendColGate = takeScratch(&hitPendColGate, count: 9, filledWith: 0)
                            var pendColRiff = takeScratch(&hitPendColRiffSlot, count: 9, filledWith: -1)
                            defer { hitPendColPitch = pendColPitch; hitPendColVel = pendColVel; hitPendColGate = pendColGate; hitPendColRiffSlot = pendColRiff }
                            /// §5.2 the per-note group output as a `pitchBus` value: -1 inherit, -2 pending (SPREAD/SPLIT-LOWEST,
                            /// resolved in the post-pass), else the concrete A–D mask. For ALT OFF this is exactly the part MAIN
                            /// mask, so `addPitch`'s collision decision is made with the same values at the same time → byte-identical.
                            func groupOf(_ part: EuclideousOutPart, pitch: Int, spreadPlace: Int) -> Int {
                                guard let alt = alt else { return (part == .riff ? riffBus : notesBus).map(Int.init) ?? -1 }
                                let pr = part == .riff ? alt.riff : alt.notes
                                if pr.alt.mode == .spread || (pr.alt.mode == .split && pr.alt.splitLowest) { return -2 }
                                let m = euclideousAltGroup(pr.alt, mainMask: part == .riff ? riffBus : notesBus, altMask: pr.alt.altMask,
                                                           q: ord, s: localT, p: altPass, h: altH, lane: lineIndex, leadPartId: pr.leadPartId,
                                                           isRestHit: altIsRestHit, notePitch: pitch, splitThreshold: part == .riff ? riffSplitT : notesSplitT, spreadPlace: spreadPlace)
                                return m.map(Int.init) ?? -1
                            }
                            // NOTES TAB (2026-10-19, §8.3-§8.4): the per-pitch TIE extension — the riff note carries on through every tied rest (`tieExt`), the notes layer's notes only up to
                            // the first tied rest the notes layer strikes on (`tieNotesExt`). `notesPitchMask` bit j marks a pitch the notes layer added (no allocation); `tieOf(j)` is what
                            // every strike below reads.
                            var notesPitchMask: UInt16 = 0
                            var pitchCount = 0
                            func addPitch(_ v: Int, vel: UInt8, gate g: Double, notesLayer: Bool = false) {
                                guard pitchCount < 9 else { return }
                                for j in 0..<pitchCount where pitches[j] == v {
                                    // ALT §6.2 per-OUTPUT collision, now on each note's GROUP output: a NOTES pitch equal to an
                                    // earlier RIFF pitch still sounds on notesGroup & ~riffGroup as a SECOND notes slot. Equal
                                    // groups (every ALT-OFF lane, both the part MAIN masks) ⇒ notesOnly 0 ⇒ dedup, byte-identical.
                                    guard notesLayer, (notesPitchMask >> UInt16(j)) & 1 == 0 else { return }
                                    let gr = pitchBus[j], gn = groupOf(.notes, pitch: v, spreadPlace: 0)
                                    if gr == -2 || gn == -2 {
                                        // a SPREAD / SPLIT-LOWEST side — the groups aren't known until the post-pass, so record the
                                        // collision (the notes note + the riff slot it hit) and add no slot yet.
                                        guard pendColCount < 9 else { return }
                                        pendColPitch[pendColCount] = v; pendColVel[pendColCount] = vel; pendColGate[pendColCount] = g; pendColRiff[pendColCount] = j
                                        pendColCount += 1
                                        return
                                    }
                                    guard gr >= 0, gn >= 0 else { return }   // either side inherits the cell bus ⇒ dedup (as the per-layer ferry did)
                                    let notesOnly = gn & ~gr
                                    guard notesOnly != 0, pitchCount < 9 else { return }
                                    pitches[pitchCount] = v; pitchVel[pitchCount] = vel; pitchGate[pitchCount] = g
                                    notesPitchMask |= UInt16(1) << UInt16(pitchCount); pitchBus[pitchCount] = notesOnly
                                    pitchCount += 1
                                    return
                                }
                                pitches[pitchCount] = v; pitchVel[pitchCount] = vel; pitchGate[pitchCount] = g
                                if notesLayer { notesPitchMask |= UInt16(1) << UInt16(pitchCount); pitchBus[pitchCount] = groupOf(.notes, pitch: v, spreadPlace: 0) }
                                else { pitchBus[pitchCount] = groupOf(.riff, pitch: v, spreadPlace: 0) }
                                pitchCount += 1
                            }
                            // RIFF LAYER — unchanged mechanics (walk→rank→LEAP→INVERT→TRANSPOSE→MIRROR/CLIMB→
                            // riffResolve, identical to the retired fork below), but now contributes a SINGLE
                            // pitch into the shared merge instead of striking on its own. `hadRiffNote`/
                            // `riffRank`/`riffNote` feed the hit-wide mask representative + NOTE VIEW's
                            // primary/+n convention below. `tieExt` (TIE's forward gate-length extension) is
                            // computed from WHEREVER the riff lands (rest or real rank) and shared by every
                            // pitch in the final merged strike, per "every note in a hit shares the hit's
                            // velocity and gate."
                            var hadRiffNote = false
                            var riffRank = 0, riffNote = 0
                            var tieExt = 0.0
                            var tieNotesExt = 0.0   // NOTES TAB: how far the notes layer's notes carry on through tied rests (≤ tieExt); see `notesPitchMask`
                            /// What kind of rest ended the riff layer's work this hit: 0 = none, 1 = a SKIP-like rest (SKIP, or REPEAT with no note to repeat), 2 = a tied rest. NOTES TAB (§8.1-§8.3):
                            /// a rest no longer ends the hit by itself — the notes layer may still strike on it; only when it plays nothing does the hit end exactly as it used to.
                            var restEnd = 0
                            func tieOf(_ j: Int) -> Double { (notesPitchMask >> UInt16(j)) & 1 != 0 ? tieNotesExt : tieExt }
                            var wipeColumn: Int8 = -1, wipeRankOut: Int8 = -1
                            var wipeCellColumn: Int8 = -1, repeatedColumn: Int8 = -1   // RESTART TILES: the column whose NOTE struck (the REPEAT lookback's column on a REPEAT hit, else the hit's own)
                            // FX TAB (ferry 2026-10-18): the page-level FX rows (a fixed-size, read-only snapshot — nothing here allocates) and THIS hit's decision
                            // from the one shared `euclideousFXApply`. `fx` stays empty (every row off) unless the lane plays its riff and a row has a cell for
                            // this column — so with every cell empty and BASE none every line below behaves exactly as before.
                            let fxAll = p.euclideousFX
                            let fxLive = !fxAll.isInert
                            let fxTieLane = fxLive && fxAll.rowHasCells(2, lane: lineIndex)
                            var fx = EuclideousFXHit()
                            func fxRiffVel() -> UInt8 { fx.vel.map { UInt8($0) } ?? UInt8(velocityAbsolute) }                       // VEL replaces the lane's VELOCITY for the riff note…
                            func fxRiffGate() -> Double { fx.gatePct.map { Double($0) / 100 } ?? gate }                              // …GATE replaces the lane's GATE
                            func fxLitVel() -> UInt8 { fx.vel.map { euclideousFXLitVelocity(fxVel: $0, notesVelocity: Int(notesVel), velocityAbsolute: velocityAbsolute) } ?? notesVel }   // lit notes: v + the NOTES VEL bar's offset
                            func fxLitGate() -> Double { fx.gatePct.map { Double($0) / 100 } ?? notesGate }                          // one effective gate per hit (GATE overrides the notes layer's own too)
                            /// A column's WRITTEN rank at a beat (the grid, or the looper's effective rank) — what 6.1's "rest hit" and 6.4's count read.
                            func writtenRankAt(_ column: Int, _ beat: Double) -> Int {
                                euclideousLooperEffectiveRank(column: column, beat: beat, liveGrid: euclideousLiveGridRanksForHit,
                                                               active: p.euclideousLooperActive, startBeat: p.euclideousLooperStartBeat,
                                                               passes: p.euclideousLooperPasses, startRanks: p.euclideousLooperStartRanks,
                                                               events: p.euclideousLooperEvents, beatsPerBar: beatsPerBar)
                            }
                            // TIE (ON REST): the held length comes from the shared core's lookahead (`euclideousChainTieExtensions`) — each future hit is evaluated with its own rhythm /
                            // melody origins, so the answer agrees with what the walk will really read there, across a restart or a window boundary. The rank at a future hit is read at
                            // THAT hit's beat (the looper's snapshot). FX TAB: a TIE-row hit is a tied hit whatever the lane's own ON REST is, so the lookahead also runs for a lane with TIE
                            // cells; a REST ties only while ON REST is TIE (`restTies`), an FX-tied real-rank hit is decided by the shared `euclideousFXApply` at that hit's beat.
                            // NOTES TAB (§8.4): it answers twice — the riff note's extension, and how far the notes layer's notes carry on (`notesStrikes` is the notes layer's own decision at
                            // each tied rest it scans, worked forward from this hit's count).
                            func tieLookaheads(hasNotesStrikes: Bool, notesStrikes: (_ isRest: Bool, _ column: Int, _ beat: Double) -> Bool) -> (riff: Double, notes: Double) {   // non-escaping: no heap context for what the caller's closure captures
                                guard riffOnRest == .tie || fxTieLane else { return (0, 0) }
                                return euclideousChainTieExtensionsCore(
                                    buf: euclidBuf, n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                    legacySpanBeats: ladderSpanBeats, advanceStep: riffAdvanceStep,
                                    riffDir: riffDir, stride: riffStride, length: riffLength, rotate: riffRotate, seed: seed, every: riffAdvanceEvery,
                                    bound: min(64, euclideousFXWalkPeriod(dir: riffDir, length: riffLength, stride: riffStride) * max(1, riffAdvanceEvery)),
                                    restTies: riffOnRest == .tie,
                                    fxTie: { col, _, r in fxTieLane && euclideousFXApply(fxAll, lane: lineIndex, playsRiff: true, column: col, writtenRank: r, pass: 0).tie },   // non-escaping: no heap context
                                    timing: hitTiming,
                                    rankAt: { column, beat in
                                        euclideousLooperEffectiveRank(column: column, beat: beat, liveGrid: euclideousLiveGridRanksForHit,
                                                                       active: p.euclideousLooperActive, startBeat: p.euclideousLooperStartBeat,
                                                                       passes: p.euclideousLooperPasses, startRanks: p.euclideousLooperStartRanks,
                                                                       events: p.euclideousLooperEvents, beatsPerBar: beatsPerBar)
                                    },
                                    hasNotesStrikes: hasNotesStrikes, notesStrikes: notesStrikes)
                            }
                            // LISTEN/SHADOW (§6): REPLACES the riff+lit-notes layers below entirely — "the
                            // lane's own riff and lit notes are ignored." Resolves the partner's own most
                            // recent real hit (sticky, matching the UI's own marker — "(My interpretation)"
                            // of "the note under the partner's walk arrow at that moment," since the arrow
                            // itself is sticky, not instantaneous), then shifts by INTERVAL (a pool-rank
                            // shift, BEFORE the fold) and OCT (combined with the partner's OWN riffOctave in
                            // one `riffResolve` call, so a rank pushed out of the pool by INTERVAL folds by
                            // octave exactly once, not twice). "If the partner's riff is off, the shadow is
                            // silent" / "if the partner's arrow is on a rest, the shadow rests too" both
                            // fall out of `euclideousListenPartnerNoteAt` returning nil (riff off is checked
                            // explicitly; a genuinely silent partner — never yet struck a real note within
                            // the bounded backward scan — is indistinguishable from "resting" and both
                            // correctly produce silence here).
                            // LISTEN REBUILT §4 (SHADOW/ECHO): REPLACE the riff+lit-notes layers below
                            // entirely — both read the SOURCE's own captured STRIKE (§1.3), not a fresh
                            // partner-note lookup: SHADOW takes its MOST RECENT strike (sticky — nothing
                            // yet this run leaves the hit silent, §4.1); ECHO takes the strike ranked `j`
                            // (this FOLLOWER's own hit count so far, §4.2/§9.6) against the source's
                            // current cycle if it's reached that rank yet, else its last completed one.
                            // Every resulting pitch moves by INTERVAL/OCTAVE (§6). The source's strike was
                            // captured for EVERY lane, every hit, at the identical point in its OWN
                            // pipeline (below) — so a chain (this lane's source following a THIRD lane)
                            // just works, and a muted/solo-silenced source still drives this (§5.2).
                            let shadowOrEchoValid = (listenPitch == .shadow || listenPitch == .echo) && listenSource >= 0 && listenSource < 4 && listenSource != lineIndex
                            if shadowOrEchoValid {
                                let notesBefore = pitchCount
                                func strikeFrom(_ cycle: EuclideousEchoCycle, _ idx: Int) {
                                    cycle.forEachPitch(idx) { note in
                                        let moved = euclideousListenMoveByInterval(note: note, interval: listenInterval, octave: listenOctave,
                                                                                    keyRoot: p.euclideousChordKeyRoot, scaleIntervals: p.euclideousChordKeyTones)
                                        addPitch(moved, vel: UInt8(velocityAbsolute), gate: gate)
                                    }
                                }
                                if listenPitch == .shadow {
                                    if euclideousEchoCurrent[listenSource].count > 0 { strikeFrom(euclideousEchoCurrent[listenSource], euclideousEchoCurrent[listenSource].count - 1) }
                                    else if euclideousEchoLast[listenSource].count > 0 { strikeFrom(euclideousEchoLast[listenSource], euclideousEchoLast[listenSource].count - 1) }
                                } else {
                                    let j = euclideousEchoFollowerJ[lineIndex]
                                    switch euclideousListenEchoIndex(j: j, currentCount: euclideousEchoCurrent[listenSource].count, lastCount: euclideousEchoLast[listenSource].count) {
                                    case .current(let idx): strikeFrom(euclideousEchoCurrent[listenSource], idx)
                                    case .last(let idx): strikeFrom(euclideousEchoLast[listenSource], idx)
                                    case .rest: break
                                    }
                                    euclideousEchoFollowerJ[lineIndex] += 1
                                }
                                if pitchCount > notesBefore { hadRiffNote = true; riffRank = thisLaneCount; riffNote = pitches[notesBefore] }
                            } else if riffOn, thisLaneCount > 0 {
                                let leapStep = (maskedChancePassed && mm.modeResolved == .leap)
                                    ? (((playedStep + mm.leapStepsResolved) % riffLength) + riffLength) % riffLength
                                    : playedStep
                                let rawRank = leapStep < ranks.count ? ranks[leapStep] : 0
                                // FX TAB §2.1/§2.2: `leapStep` IS the column this hit reads (riffStepAt, then SHIFT — the column the riff-grid marker shows) and `rawRank` its
                                // WRITTEN rank (before INVERT, before the NOTE offset). The NOTE pass index comes from the core's own inputs: the ordinal `advOrd` (a melody chain of [1]: the lap).
                                if fxLive {
                                    // The NOTE pass index is the ONE chain-era function the LANES roll calls too (`euclideousFXNotePass`): a riff cycle from the melody origin, or — under a melody chain of exactly [1],
                                    // the old LOCK — the lap (`cy`). It no longer reads the retired masked grid or the hidden `riffLock` flag (REVIEW FIX 2026-10-23).
                                    let notePass: Int = fxAll.rowHasCells(4, lane: lineIndex)
                                        ? euclideousFXNotePass(advOrd: advOrd, every: riffAdvanceEvery, riffDir: riffDir, length: riffLength, stride: riffStride,
                                                               melodyEveryPass: chains.melody.isSingleLink1, lapsSinceRhythmOrigin: cy)
                                        : 0
                                    fx = euclideousFXApply(fxAll, lane: lineIndex, playsRiff: true, column: leapStep, writtenRank: rawRank, pass: notePass)
                                }
                                // RIFF WALK ferry §5-6: factored into a re-enterable function so REPEAT (§6) can feed a DIFFERENT
                                // (borrowed) raw rank through the exact same invert/offset/transpose/mask-mode/riffResolve pipeline a
                                // normal hit uses, "exactly as if it had read that column" (§6.3) — `leapStep` (the hit's OWN column,
                                // for wipeColumn/mask LEAP) is never substituted, only the rank is. Bounded recursion: REPEAT's lookback
                                // only ever returns a column whose own rank is >= 1, so the recursive call can itself recurse at most
                                // zero further times (it never re-enters `.repeatLast`'s own rest branch).
                                // Returns true when the WHOLE hit must abort here (SKIP/TIE/REPEAT-not-found) —
                                // the lit-notes layer below must NOT run either (a `return` inside this nested
                                // func only exits the func itself, so the caller must re-propagate the signal).
                                @discardableResult
                                func strikeRiffRawRank(_ rr: Int, repeating: Bool = false) -> Bool {
                                    let invRank = (riffInvert && rr >= 1) ? (9 - rr) : rr
                                    // NOTE (§7.3): the offset goes straight after INVERT and before TRANSPOSE and the mask's rank modes. A moved rank is always a pitch (the column's
                                    // WRITTEN rank is not a rest — `euclideousFXApply` required that), even at 0 or below; with no offset the existing arithmetic is untouched.
                                    let fxMoved = fx.noteOffset != 0
                                    let transposedRank = fxMoved ? invRank + fx.noteOffset + melodyTranspose : (invRank >= 1 ? invRank + melodyTranspose : invRank)
                                    var rank = transposedRank
                                    if maskedChancePassed && rank >= 1 {
                                        switch mm.modeResolved {
                                        case .mirror:
                                            rank = 9 - rank
                                        case .climb:
                                            let bound = max(1, thisLaneCount) * (mm.climbRangeResolved == .wrap2 || mm.climbRangeResolved == .bounce2 ? 2 : 1)
                                            var off = euclideousMaskClimbOffset[lineIndex] + mm.climbStepResolved
                                            switch mm.climbRangeResolved {
                                            case .wrap1, .wrap2: if off >= bound || off <= -bound { off = 0 }
                                            case .bounce1, .bounce2:
                                                if off < -bound { off = -bound - (off + bound) }
                                                else if off > bound { off = bound - (off - bound) }
                                            }
                                            euclideousMaskClimbOffset[lineIndex] = off
                                            rank += off
                                        default: break
                                        }
                                    }
                                    if !fxMoved && rank < 1 {
                                        // REST. NOTES TAB (2026-10-19, §8): a rest hit no longer ends the hit by itself — the NOTES layer may still strike on it (WHEN RESTS, §8.1-§8.3),
                                        // so each outcome now just says what KIND of rest this is (`restEnd`) and the hit goes on to the notes layer below; only when that plays nothing does
                                        // the hit end exactly as it used to (the old SKIP / tied-rest exits live right after the notes layer):
                                        //   SKIP (and FILL, which decodes as SKIP) — the riff stays silent (restEnd 1);
                                        //   TIE — no new riff note, the riff note from before carries on (restEnd 2);
                                        //   REPEAT — the nearest earlier non-rest column's note again, fed through this SAME function "exactly as if it had read that column" (§6.3);
                                        //   none found — as SKIP (§6.2).
                                        switch riffOnRest {
                                        case .skip, .fill:
                                            restEnd = 1
                                        case .tie:
                                            restEnd = 2
                                        case .repeatLast:
                                            // `repeating`: the repeated rank came back through the transforms below 1 again (a negative TRANSPOSE can do that) — treat it as SKIP rather than
                                            // looking the same column up again forever.
                                            guard !repeating, let found = euclideousRiffRepeatLookback(
                                                buf: euclidBuf, n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                                legacySpanBeats: ladderSpanBeats, advanceStep: riffAdvanceStep,
                                                riffDir: riffDir, stride: riffStride, length: riffLength, rotate: riffRotate, seed: seed, every: riffAdvanceEvery,
                                                thisBeat: mTickBeat,
                                                rankAt: { column, beat in
                                                    euclideousLooperEffectiveRank(column: column, beat: beat, liveGrid: euclideousLiveGridRanksForHit,
                                                                                   active: p.euclideousLooperActive, startBeat: p.euclideousLooperStartBeat,
                                                                                   passes: p.euclideousLooperPasses, startRanks: p.euclideousLooperStartRanks,
                                                                                   events: p.euclideousLooperEvents, beatsPerBar: beatsPerBar)
                                                }) else {
                                                restEnd = 1
                                                return false
                                            }
                                            repeatedColumn = Int8(found.column)
                                            return strikeRiffRawRank(found.rank, repeating: true)
                                        }
                                    } else if let note0 = fxMoved
                                                ? riffResolveExtended(rank: rank, oct: riffOctave, n: thisLaneCount, asc: { notes[$0].note })   // a NOTE-moved rank folds both ways (rank 0 = the octave below)
                                                : riffResolve(rank: rank, oct: riffOctave, n: thisLaneCount, wrap: .fold, asc: { notes[$0].note }) {
                                        hadRiffNote = true
                                        riffRank = rank; riffNote = note0
                                        addPitch(note0, vel: fxRiffVel(), gate: fxRiffGate())   // FIRST, so index 0 is reliably "the riff note" for NOTE VIEW's primary/+n convention
                                        // WIPE TELEMETRY (ferry "riff-cell wipes" §2.2): mirrors the retired fork's
                                        // own wipeRank computation exactly — MIRROR re-applied to `invRank` (the
                                        // pre-TRANSPOSE value), "after INVERT, MIRROR and LEAP but before
                                        // TRANSPOSE and OCT." RIFF WALK ferry §6.5: on a REPEAT hit this still
                                        // posts the hit's OWN (rest) column, `leapStep` — never the repeated one.
                                        let wr = (maskedChancePassed && mm.modeResolved == .mirror && invRank >= 1) ? (9 - invRank) : invRank
                                        if wr >= 1 && wr <= 8 { wipeColumn = Int8(leapStep); wipeRankOut = Int8(wr); wipeCellColumn = repeating && repeatedColumn >= 0 ? repeatedColumn : Int8(leapStep) }
                                    }
                                    return false
                                }
                                strikeRiffRawRank(rawRank)
                            }

                            // NOTES TAB LAYER (ferry 2026-10-19, §6-§8) — independent of riffOn. WHICH hits the lit notes play (WHEN, CHANCE: 6.1-6.3), WHAT they play (the play list in the
                            // lit order: 6.5) and HOW (the way: 7.1) all come from the pure functions in Derivations.swift — the same ones every display calls. "Lit note n: pool rank n at the
                            // notes layer's octave. INV and TRANS do not apply" (no `riffInvert`/`melodyTranspose` here, unlike the riff layer); TOP / TOP 2 resolve at every hit so they
                            // follow chord changes. NOTES ON/OFF: off silences the lit notes from the next hit but keeps them lit. The rhythm, the LANES mute, the mask and FX TIE still decide
                            // first (they all act below, exactly as before).
                            let nw = EuclideousNotesWalk(n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, chains: chains, legacySpanBeats: ladderSpanBeats, advanceStep: riffAdvanceStep,
                                                         riffDir: riffDir, stride: riffStride, length: riffLength, rotate: riffRotate, seed: seed, every: riffAdvanceEvery)
                            var notesStruck = 0                    // pitches the notes layer actually added this hit (m, after 7.2)
                            var notesCounted = false               // chosen and let through by CHANCE — counts toward k for later hits
                            var notesList = EuclideousNotesList()  // the play list (6.5)
                            var notesK = 0
                            var notesH: Int64 = 0
                            var notesSlotBits: UInt64 = ~0         // nibble j = strike slot of pitch j (0xF = not a spread pitch); AVOID moves it with the pitch
                            // 7.2 / 8.3: the riff pitch a tied rest carries on is never struck again.
                            let heldRiffPitch = restEnd == 2 ? euclideousHeldRiffPitch[lineIndex] : -1
                            // LISTEN REBUILT §9.9 (confirmed by this ferry's own §0 research): NOTES pauses
                            // alongside RIFF whenever RIFF is borrowed — i.e. under SHADOW OR ECHO, not
                            // just SHADOW — since the NOTES layer reads riff-grid data (the walk ordinal,
                            // written ranks up to 1024 earlier hits, future columns for TIE) far beyond
                            // "the hit's single struck riff pitch."
                            if !shadowOrEchoValid, notesOn, thisLaneCount > 0, litOrder.count > 0,
                               euclideousNotesWhenChooses(when: notesWhen, isRestHit: ranks[playedStep] < 1) {
                                let usesCount = euclideousNotesWayUsesCount(notesPlayAs)
                                if usesCount || notesChance < 100 { notesH = euclideousNotesHitOrdinal(buf: euclidBuf, w: nw, tick: tick) }
                                if euclideousNotesChanceAllows(chance: notesChance, lane: lineIndex, h: notesH) {
                                    notesCounted = true
                                    notesList = euclideousNotesPlayList(order: litOrder, poolCount: thisLaneCount, receivedOnly: notesReceivedOnly) { rank in
                                        riffResolve(rank: rank, oct: octave, n: thisLaneCount, wrap: .fold, asc: { notes[$0].note })
                                    }
                                    if notesList.count > 0 {
                                        if usesCount {
                                            notesK = euclideousNotesCountBefore(buf: euclidBuf, w: nw, tick: tick, h: notesH, when: notesWhen, chance: notesChance, lane: lineIndex,
                                                                                thisBeat: mTickBeat, rankAt: writtenRankAt)
                                        }
                                        let pick = euclideousNotesWayPick(list: notesList, way: notesPlayAs, k: notesK)
                                        for i in 0..<pick.count {
                                            let pch = notesList.pitch(pick[i])
                                            if pch == heldRiffPitch { continue }
                                            let at = pitchCount
                                            addPitch(pch, vel: fxLitVel(), gate: fxLitGate(), notesLayer: true)
                                            if pitchCount > at {
                                                notesSlotBits = (notesSlotBits & ~(UInt64(0xF) << UInt64(4 * at))) | (UInt64(notesStruck) << UInt64(4 * at))
                                                notesStruck += 1
                                            }
                                        }
                                    }
                                }
                            }
                            // A rest hit whose notes layer played nothing ends exactly as it used to (§8.1, §8.3): a SKIP-like rest closes any legato note and posts the silent-rest NOTE VIEW
                            // event; a tied rest strikes nothing at all — whatever is sounding (the riff note, the notes from the hit before) carries on.
                            if restEnd != 0 && pitchCount == 0 {
                                if restEnd == 1 {
                                    reconcileEuclidLegato(lineIndex: lineIndex, pitches: [], pitchCount: 0, vels: [], gates: [],
                                                           tau: mTickBeat, isRatchetThisHit: false, overlapBeats: overlapBeats10ms, busOf: busOf)
                                    if nvSent {
                                        let (onset, duration) = nvTiming(sub)
                                        pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 2, noteCount: 0)
                                    }
                                }
                                return
                            }
                            // TIE (§8.3-§8.4): how far each layer's notes carry on. Only a hit that strikes something asks (the riff note through every tied rest; the notes layer's notes up to
                            // the first tied rest the notes layer itself strikes on, working k forward from this hit's).
                            if riffOn, pitchCount > 0, riffOnRest == .tie || fxTieLane {
                                let heldForTie = hadRiffNote ? riffNote : heldRiffPitch
                                var scanK = notesK + (notesCounted ? 1 : 0)
                                var scanH = notesH + 1
                                let ext: (riff: Double, notes: Double)
                                if notesStruck > 0 {
                                    ext = tieLookaheads(hasNotesStrikes: true, notesStrikes: { isRest, _, _ in
                                        var strikes = false
                                        if euclideousNotesWhenChooses(when: notesWhen, isRestHit: isRest), euclideousNotesChanceAllows(chance: notesChance, lane: lineIndex, h: scanH) {
                                            if isRest {
                                                let pk = euclideousNotesWayPick(list: notesList, way: notesPlayAs, k: scanK)
                                                for i in 0..<pk.count where notesList.pitch(pk[i]) != heldForTie { strikes = true; break }
                                            }
                                            scanK += 1
                                        }
                                        scanH += 1
                                        return strikes
                                    })
                                } else {
                                    ext = tieLookaheads(hasNotesStrikes: false, notesStrikes: { _, _, _ in false })
                                }
                                tieExt = ext.riff; tieNotesExt = ext.notes
                            }
                            // SILENCE: "if none are lit, the hit is silent" (riff off) / the riff genuinely
                            // produced nothing AND nothing is lit (riff on, SKIP-degraded or empty pool).
                            guard pitchCount > 0 else {
                                // GATE/legato §2.4: a genuinely silent hit still closes any held legato note here.
                                reconcileEuclidLegato(lineIndex: lineIndex, pitches: [], pitchCount: 0, vels: [], gates: [],
                                                       tau: mTickBeat, isRatchetThisHit: false, overlapBeats: overlapBeats10ms, busOf: busOf)
                                return
                            }
                            // LISTEN REBUILT §4.3 (AVOID): drops EVERY already-resolved pitch (riff or lit —
                            // not just the riff-sourced one, a real broadening vs the old AVOID) whose
                            // PITCH CLASS (octave ignored, §4.3/§9.8) is in the source's most recent
                            // strike. No MOVE any more — the new AVOID is mute-only by construction.
                            if listenPitch == .avoid, listenSource >= 0, listenSource < 4, listenSource != lineIndex {
                                var mask: UInt16 = 0
                                if euclideousEchoCurrent[listenSource].count > 0 {
                                    euclideousEchoCurrent[listenSource].forEachPitch(euclideousEchoCurrent[listenSource].count - 1) { mask |= UInt16(1) << UInt16((($0 % 12) + 12) % 12) }
                                } else if euclideousEchoLast[listenSource].count > 0 {
                                    euclideousEchoLast[listenSource].forEachPitch(euclideousEchoLast[listenSource].count - 1) { mask |= UInt16(1) << UInt16((($0 % 12) + 12) % 12) }
                                }
                                if mask != 0 {
                                    var i = 0
                                    while i < pitchCount {
                                        if euclideousListenAvoidDrops(note: pitches[i], mask: mask) {
                                            pitches[i] = pitches[pitchCount - 1]; pitchVel[i] = pitchVel[pitchCount - 1]; pitchGate[i] = pitchGate[pitchCount - 1]
                                            // NOTES TAB: the layer mark and the ROLL / RUN strike slot travel with the pitch that moved into slot i
                                            let last = pitchCount - 1
                                            notesPitchMask = (notesPitchMask & ~(UInt16(1) << UInt16(i))) | (((notesPitchMask >> UInt16(last)) & 1) << UInt16(i))
                                            notesPitchMask &= ~(UInt16(1) << UInt16(last))
                                            notesSlotBits = (notesSlotBits & ~(UInt64(0xF) << UInt64(4 * i))) | (((notesSlotBits >> UInt64(4 * last)) & 0xF) << UInt64(4 * i))
                                            notesSlotBits |= UInt64(0xF) << UInt64(4 * last)
                                            pitchBus[i] = pitchBus[last]   // PER-LAYER ROUTING: the output mask travels with the pitch moved into slot i too
                                            pitchCount -= 1
                                        } else {
                                            i += 1
                                        }
                                    }
                                    guard pitchCount > 0 else {
                                        reconcileEuclidLegato(lineIndex: lineIndex, pitches: [], pitchCount: 0, vels: [], gates: [],
                                                               tau: mTickBeat, isRatchetThisHit: false, overlapBeats: overlapBeats10ms, busOf: busOf)
                                        return
                                    }
                                }
                            }
                            // LISTEN REBUILT §1.3/§5.2: capture THIS hit's finished strike — every pitch
                            // just resolved (riff + notes + this lane's own AVOID, if any), before HIT-WIDE
                            // MASK's CHORD/OCT/RATCHET-count/ACCENT-SWELL and before mute/solo — into this
                            // lane's own ECHO buffer, for any OTHER lane that reads it as a SHADOW/ECHO/
                            // AVOID source. EVERY lane captures, unconditionally: a muted/solo-silenced
                            // lane still fully computes and captures (§5.2 — exactly how its walk/riff
                            // position already keeps advancing underneath a silenced lane today). `cy`
                            // (the floored cycle since the rhythm origin, computed above) is the cycle
                            // boundary ECHO rolls on — "one pass of the source's pattern" (§1.5).
                            if lineIndex >= 0, lineIndex < 4 {
                                if cy != euclideousEchoCycleNum[lineIndex] {
                                    // A swap, not `last = current`: the copy shared both inner arrays, so the reset right after had to duplicate them (two heap allocations on the render thread at every cycle boundary). What `last` ends up
                                    // holding is the same; `current`'s stale pitch slots are never read past its `count`.
                                    swap(&euclideousEchoLast[lineIndex], &euclideousEchoCurrent[lineIndex])
                                    euclideousEchoCurrent[lineIndex].reset()
                                    euclideousEchoCycleNum[lineIndex] = cy
                                }
                                euclideousEchoCurrent[lineIndex].append(count: pitchCount, from: pitches)
                            }

                            // EUCLID MASK — REPEAT (Paul 2026-10-10 ferry §3, widened for this ferry): "holding
                            // the riff walk" is read as holding the WHOLE per-tick decision, same as the
                            // existing top-of-function REPEAT-HOLD-CONTINUATION block for this lane — a
                            // triggering tick here REPLACES the just-resolved merged set with the WHOLE cached
                            // set from the last genuine strike (not just one note), via the widened
                            // `euclideousLastSoundedNotes`/`Count` (NOT the singular `euclideousLastSoundedNote`,
                            // which stays exclusively owned by the OLD/non-Euclideous paths below). Special-
                            // cased BEFORE the generic `maskTransform` call — that function's own `.repeatNote`
                            // case only knows how to substitute ONE note, and must stay that way for its other
                            // (non-Euclideous) callers.
                            if maskedChancePassed && mm.modeResolved == .repeatNote {
                                let cachedN = euclideousLastSoundedCount[lineIndex]
                                if cachedN > 0 {
                                    pitchCount = min(9, cachedN)
                                    notesPitchMask = 0; notesSlotBits = ~0   // a replayed set strikes together and carries on as the riff note does (as before)
                                    for i in 0..<pitchCount {
                                        pitches[i] = Int(euclideousLastSoundedNotes[lineIndex * 9 + i])
                                        pitchVel[i] = euclideousLastSoundedVels[lineIndex * 9 + i]
                                        pitchGate[i] = euclideousLastSoundedGates[lineIndex * 9 + i]
                                        pitchBus[i] = riffBus.map(Int.init) ?? -1   // ferry §4.1: REPEAT's replayed set is the riff layer, routed to riffBus
                                    }
                                }
                                euclideousMaskRepeatRemaining[lineIndex] = mm.repeatCountResolved - 1
                                let repGb = gateBeatsWithTie(pitchGate[0], tieOf(0))   // NOTE VIEW's one duration: pitch 0's (the riff note when the hit has one)
                                let repHandled = reconcileEuclidLegato(lineIndex: lineIndex, pitches: pitches, pitchCount: pitchCount, vels: pitchVel, gates: pitchGate,
                                                                        tau: mTickBeat, isRatchetThisHit: false, overlapBeats: overlapBeats10ms, busOf: busOf)
                                for j in 0..<pitchCount where repHandled & (UInt16(1) << UInt16(j)) == 0 {
                                    strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: gateBeatsWithTie(pitchGate[j], tieOf(j)), octave: 0, explicitNote: pitches[j], explicitVel: pitchVel[j], busOverride: busOf(j))
                                }
                                euclideousLastSoundedCount[lineIndex] = pitchCount
                                // The trigger caches the WHOLE set — notes, velocities AND (MIX ferry) gates. It used to write only the notes, so a REPEAT
                                // that triggered on the lane's very first hit (nothing cached yet) replayed stale/zero velocities; with per-pitch gates
                                // a zero cached gate would floor every replay to the 5 ms minimum. When the set came FROM the cache these writes are
                                // idempotent.
                                for i in 0..<pitchCount {
                                    euclideousLastSoundedNotes[lineIndex * 9 + i] = Int8(clamping: pitches[i])
                                    euclideousLastSoundedVels[lineIndex * 9 + i] = pitchVel[i]
                                    euclideousLastSoundedGates[lineIndex * 9 + i] = pitchGate[i]
                                }
                                if nvSent {
                                    var nc = 0
                                    for j in 0..<pitchCount where nc < Router.noteViewMaxNotes { if let p = finalPitch(pitches[j], oct: 0) { nvScratch[nc] = p; nvVelScratch[nc] = pitchVel[j]; nc += 1 } }
                                    if nc > 0 {
                                        let (onset, duration) = nvTiming(repGb)
                                        // WIPE TELEMETRY: a REPEAT TRIGGER (this branch) still reports the
                                        // riff position actually READ this tick (`wipeColumn`/`wipeRankOut`,
                                        // already computed above from the CURRENT hit's own riff resolution,
                                        // before REPEAT's own cached-set substitution replaced the SOUNDING
                                        // pitches) — mirrors the OLD single-note code's identical behaviour
                                        // exactly (its own wipeRank/wipeEligible were computed from the
                                        // current tick's rank, independent of whatever REPEAT went on to
                                        // substitute). Only -1/-1 when riff is off/FILL/SKIP-degraded this
                                        // tick, same as every other push site.
                                        pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: tieOf(0) > 0 ? 3 : 0, noteCount: nc,
                                                           column: wipeColumn, rank: wipeRankOut, hasRiffNote: hadRiffNote, withVels: true, cellColumn: wipeCellColumn)
                                    }
                                }
                                return
                            }

                            // HIT-WIDE MASK (ferry "Mask" §5): "the three-note [CHORD] mode applies to one
                            // note per hit: the riff note when the riff is on, otherwise the highest lit
                            // note" — generalized (Q2) to every mode needing a single representative
                            // (rank,note): MUTE/RATCHET/CHORD/OCT/ACCENT/SWELL all read ONE shared decision
                            // here, applied to the WHOLE merged set below. MIRROR/LEAP/CLIMB already ran,
                            // riff-rank-only, inside the `if riffOn` block above — not re-run here.
                            var repRank = riffRank, repNote = riffNote
                            if !hadRiffNote {
                                repNote = pitches[0..<pitchCount].max() ?? pitches[0]
                                repRank = thisLaneCount   // best-effort fallback: CHORD's own resolveRank below only needs A pool rank for its interval offsets, not which specific toggle produced this exact pitch
                                // NOTES TAB: the representative's pool rank is the rank of the play-list entry that struck this pitch (the list is the one thing that resolved it).
                                for i in 0..<notesList.count where notesList.pitch(i) == repNote { repRank = notesList.rank(i); break }
                            }
                            let maskOct = hadRiffNote ? riffOctave : octave
                            // RIFF/NOTES SPLIT: the representative's own base velocity, layer-aware — mirrors
                            // `maskOct` exactly, one line up.
                            let repVelBase: UInt8 = hadRiffNote ? fxRiffVel() : fxLitVel()
                            // MIX TAB: …and its gate (§7.4) — mask-added notes (CHORD intervals; ratchet repeats inherit per pitch) take the gate of the
                            // pitch they come from: the riff pitch when the hit has one, otherwise the notes layer (the `maskOct` rule again).
                            let repGateBase = euclideousExtraPitchGate(hadRiffNote: hadRiffNote, gate: fxRiffGate(), notesGate: fxLitGate())
                            let resolveRank: (Int) -> Int? = { r in riffResolve(rank: r, oct: maskOct, n: thisLaneCount, wrap: .fold, asc: { notes[$0].note }) }
                            let xf = maskTransform(rank: repRank, note: repNote, vel: repVelBase, lineIndex: lineIndex,
                                                   mm: mm, maskedChancePassed: maskedChancePassed, resolveRank: resolveRank)
                            // LANES SEQUENCER MUTE (2026-10-14 ferry §5): "the walk/cursor keeps advancing
                            // as normal — only the final emission is suppressed," exactly MASK's own MUTE
                            // mode's existing contract one line below, so it's folded into the SAME check
                            // rather than a parallel branch — everything above this point (the riff walk,
                            // the lit-notes merge, the mask-ordinal roll) has already run unconditionally.
                            if xf.muted || lanesSeqMuted {
                                // GATE/legato §2.4: MUTE is a mask-level silence of the whole hit — the notes
                                // still end here, at this hit's time + overlap, not later.
                                reconcileEuclidLegato(lineIndex: lineIndex, pitches: [], pitchCount: 0, vels: [], gates: [],
                                                       tau: mTickBeat, isRatchetThisHit: false, overlapBeats: overlapBeats10ms, busOf: busOf)
                                return
                            }   // MUTE: "applies to the whole hit" — silent; the walk already advanced normally above
                            // FX TAB §5: a hit a TIE cell applies to DOESN'T STRIKE — placed AFTER the mute check so a muted hit gets no FX (it still closes held notes there,
                            // as always), and it returns BEFORE the legato reconcile, exactly like a tied REST (`case .tie: return` above): whatever the lane is sounding —
                            // the riff note and the lit notes alike, legato-held or on a finite gate the previous hit's lookahead already extended — carries on through it.
                            // The walk already advanced; no NOTE VIEW event is posted (the preceding hit's event covers it); no CC (§8.4).
                            if fx.tie { return }
                            // OCT/ACCENT/SWELL (Q2: "on the whole hit") — the DELTA `maskTransform` applied to
                            // the one representative is applied identically to every OTHER pitch in the merged
                            // set, each independently clamped (a different starting pitch can clip differently
                            // at the extremes — an accepted edge case, same as every other per-note octave/
                            // velocity clamp in this file).
                            let noteDelta = xf.note - repNote
                            let vel = xf.vel
                            // RIFF/NOTES SPLIT: ACCENT/SWELL's delta now applies to each pitch's OWN already-
                            // differentiated velocity, not a single shared scalar. CHORD's extras are seeded at
                            // `repVelBase` (pre-delta — matching how they're ALSO seeded at the pre-`noteDelta`
                            // resolved note, never `xf.note` directly) so the uniform loop below lands them at
                            // exactly `xf.vel`, not double-counted.
                            let velDelta = Int(xf.vel) - Int(repVelBase)
                            for extra in xf.extra { addPitch(extra, vel: repVelBase, gate: repGateBase) }   // CHORD's own stab notes, deduped against everything already in the set
                            for i in 0..<pitchCount {
                                let shifted = pitches[i] + noteDelta
                                if shifted >= 0 && shifted <= 127 { pitches[i] = shifted }
                                pitchVel[i] = UInt8(max(1, min(127, Int(pitchVel[i]) + velDelta)))
                            }
                            // ── ALT §5 post-pass (SPREAD / SPLIT-LOWEST only, gated — never runs on the golden/common path) ──
                            // These two modes need the FINAL per-part pitch set (SPLIT-LOWEST the part's lowest pitch; SPREAD
                            // the note's low→high place). Resolve every slot `groupOf` deferred (-2) and every pending collision
                            // (§6.2) into a concrete `pitchBus`, so `busOf(j)` is authoritative for the strikes/reconcile below.
                            if altActive, let eff = alt,
                               eff.riff.alt.mode == .spread || eff.notes.alt.mode == .spread
                               || (eff.riff.alt.mode == .split && eff.riff.alt.splitLowest) || (eff.notes.alt.mode == .split && eff.notes.alt.splitLowest) {
                                func isNotes(_ i: Int) -> Bool { (notesPitchMask >> UInt16(i)) & 1 != 0 }
                                func partMin(_ wantNotes: Bool) -> Int { var m = Int.max; for i in 0..<pitchCount where isNotes(i) == wantNotes { m = min(m, pitches[i]) }; return m }
                                let riffMin = partMin(false), notesMin = partMin(true)
                                // the note's place among its part's pitches, low→high (stable by slot index on a tie)
                                func placeOf(pitch v: Int, slot j: Int, wantNotes: Bool) -> Int {
                                    var pl = 0
                                    for i in 0..<pitchCount where isNotes(i) == wantNotes && (pitches[i] < v || (pitches[i] == v && i < j)) { pl += 1 }
                                    return pl
                                }
                                func resolve(pitch v: Int, slot j: Int, wantNotes: Bool) -> UInt8? {
                                    let pr = wantNotes ? eff.notes : eff.riff
                                    let thr = pr.alt.splitLowest ? (wantNotes ? notesMin : riffMin) : (wantNotes ? notesSplitT : riffSplitT)
                                    return euclideousAltGroup(pr.alt, mainMask: wantNotes ? notesBus : riffBus, altMask: pr.alt.altMask,
                                                              q: ord, s: localT, p: altPass, h: altH, lane: lineIndex, leadPartId: pr.leadPartId,
                                                              isRestHit: altIsRestHit, notePitch: v, splitThreshold: thr, spreadPlace: placeOf(pitch: v, slot: j, wantNotes: wantNotes))
                                }
                                for j in 0..<pitchCount where pitchBus[j] == -2 { pitchBus[j] = resolve(pitch: pitches[j], slot: j, wantNotes: isNotes(j)).map(Int.init) ?? -1 }
                                // §6.2 pending collisions: the riff slot's group is concrete now; the notes twin sounds on gn & ~gr.
                                for k in 0..<pendColCount where pitchCount < 9 {
                                    let v = pendColPitch[k]
                                    var gr = -1
                                    for i in 0..<pitchCount where pitches[i] == v && !isNotes(i) { gr = pitchBus[i]; break }
                                    guard let gnM = resolve(pitch: v, slot: 9, wantNotes: true) else { continue }   // §11 flag 3: the twin takes a notes-part place
                                    let gn = Int(gnM)
                                    let notesOnly = gr >= 0 ? (gn & ~gr) : gn
                                    guard notesOnly != 0, pitchCount < 9 else { continue }
                                    pitches[pitchCount] = v; pitchVel[pitchCount] = pendColVel[k]; pitchGate[pitchCount] = pendColGate[k]
                                    notesPitchMask |= UInt16(1) << UInt16(pitchCount); pitchBus[pitchCount] = notesOnly
                                    pitchCount += 1
                                }
                            }
                            // GATE FOLLOWS THE RHYTHM (2026-10-13 ferry): the below-100%/REPEAT-cache gate is
                            // now `gate * nextHitGapBeats` (the gap to the lane's OWN next real pattern hit),
                            // floored at 5ms, plus TIE's own forward extension — replaces the old fixed
                            // `min(sub * gate, S * 0.95)`, which measured against the lane's constant rate
                            // rather than the pattern's own real spacing. The old `S * 0.95` column-overflow
                            // clamp is obsolete: `gate * nextHitGapBeats` can at most equal `nextHitGapBeats`
                            // exactly at gate=1.0 (the legato case, handled by reconcile below, never reaches
                            // this formula at all), so a below-100% note can never overlap into the next hit
                            // by construction (§1.4's "no overlaps" falls out for free).
                            // (MIX TAB: no single per-hit length any more — every pitch below takes `gateBeatsWithTie(pitchGate[j], tieExt)`.)
                            func cacheWholeSet() {
                                // REPEAT's own widened cache target (this ferry) — the WHOLE merged set, so a
                                // FUTURE hold correctly replays every pitch from THIS genuine strike. Written
                                // after the OCT/ACCENT/SWELL delta + CHORD extras, matching what actually
                                // struck. Harmless/idempotent on a REPEAT-triggered tick too (matches the OLD
                                // per-note code's own "always re-cache, even a substituted note" behaviour).
                                let n = min(9, pitchCount)
                                euclideousLastSoundedCount[lineIndex] = n
                                for i in 0..<n {
                                    euclideousLastSoundedNotes[lineIndex * 9 + i] = Int8(clamping: pitches[i])
                                    euclideousLastSoundedVels[lineIndex * 9 + i] = pitchVel[i]
                                    euclideousLastSoundedGates[lineIndex * 9 + i] = pitchGate[i]
                                }
                                // NOTES TAB (§7.2): remember the pitch the riff note sounded as, so a tied rest after this hit never re-strikes it from the notes layer. A hit without a riff
                                // note clears it — except a tied rest, which carries the riff note from before.
                                if hadRiffNote { euclideousHeldRiffPitch[lineIndex] = riffNote + noteDelta } else if restEnd != 2 { euclideousHeldRiffPitch[lineIndex] = -1 }
                                euclideousLastSoundedVel[lineIndex] = vel   // UNCHANGED — stays shared with the legacy non-Euclideous `.repeatNote` path; never widened/removed
                            }
                            // RATCHET (ferry "Mask" §5: "repeats the whole hit, all notes") — ONE shared roll
                            // for the hit (`maskRatchetReps` called ONCE, against the representative rank —
                            // the Phase A per-rank-independent seed fix stays fully intact for the OLD, non-
                            // Euclideous NOTE-mode-pick path below, which still needs it for its own multi-
                            // note picks; calling it ONCE per hit here is what makes it shared, not a change
                            // to the function itself). Resolved BEFORE reconcile so `isRatchetThisHit` can be
                            // passed accurately — ferry §3.2: "repeats are deliberate strikes, so they never
                            // merge, even at 100%" — a ratchet hit always reconciles (closing out whatever was
                            // previously legato-held) but is never itself tracked as held.
                            // FX CC (§8): ONE message per hit, at the hit's own sample, BEFORE any note-on at it (it goes out ahead of the reconcile and every strike below) and
                            // before the first strike of a ratcheted hit — also on a hit whose pitches all carry on legato. It reaches the notes' own buses, own cable + the ALL
                            // cable, on each bus's stamped channel (`emitModCC`, forced past MOD's dedup). Only hits that sound get here: tied, muted, rest and silent hits returned.
                            // §8.4: only a hit that SOUNDS sends a CC — a pitch pushed outside MIDI 0…127 (a far NOTE move plus TRANSPOSE) is dropped by `strikeChord`, so a hit whose
                            // every pitch is dropped is silent and sends nothing.
                            var fxAnySounds = false
                            for j in 0..<pitchCount where finalPitch(pitches[j], oct: 0) != nil { fxAnySounds = true; break }
                            if let ccv = fx.cc, emits, fxAnySounds, !masterMute {
                                let ccBusMask = chopMask(cell, m: mTickBeat, S: S, base: riffBus ?? bm) & p.mainOutMask   // ferry: the FX CC follows the RIFF layer (the hit it fires on); flagged judgment call, no notes in a CC
                                let ccSample = sampleOf(musical: mTickBeat, beatPos: beatPos, beatsPerSample: beatsPerSample, windowStart: windowStart, S: S, a: a)
                                emitModCC(cc: max(0, min(119, Int(fxAll.ccNumber))), value: ccv, busMask: ccBusMask, atSample: ccSample, out: out, force: true)
                            }
                            // FX RATCH (§3): n exactly (never rolled, never legal-size clamped), lowered only by the beat-width cap; REPLACES a mask RATCHET on the same hit.
                            let fxRatchN = fx.ratch >= 2 ? euclideousFXRatchetCount(requested: fx.ratch, sub: sub, tempo: tempo) : 0
                            var nRep = maskRatchetReps(lineIndex: lineIndex, rank: repRank, mm: mm, maskedChancePassed: maskedChancePassed, sub: sub, tempo: tempo)
                            if fxRatchN >= 2 { nRep = fxRatchN }
                            // RUN (§7.4): its notes are never carried on legato and never stay open into the next hit — they take part in the reconcile as ordinary (below-100%) notes, so what the
                            // notes layer was holding legato ends here exactly as at a hit that doesn't continue it.
                            if notesPlayAs == .run, notesStruck > 0 {
                                for j in 0..<pitchCount where (notesSlotBits >> UInt64(4 * j)) & 0xF != 0xF { pitchGate[j] = min(pitchGate[j], 0.99) }
                            }
                            let handled = reconcileEuclidLegato(lineIndex: lineIndex, pitches: pitches, pitchCount: pitchCount, vels: pitchVel, gates: pitchGate,
                                                                 tau: mTickBeat, isRatchetThisHit: nRep != nil, overlapBeats: overlapBeats10ms, busOf: busOf)
                            if let nRep {
                                // AUDIBLE RATCHET, take 3 — THE REAL ROOT CAUSE (2026-10-13, Paul: first
                                // "still not working in any perceptible way," then, after take 2 (every
                                // repeat given the hit's own FULL gate) — "it does affect the output... but
                                // feels more like a sustain than a ratchet"). Root-caused by dumping the raw
                                // on/off sample stream, not guessed a third time: firing all nRep
                                // `strikeChord` calls SYNCHRONOUSLY, in one sweep, means every earlier
                                // repeat's voice is STILL "active" in this SAME call when the next one
                                // opens — no real render window ever advances in between — so the engine's
                                // own (correct) same-pitch restrike rule ALWAYS force-closes each repeat
                                // exactly at the NEXT ONSET, regardless of whatever `gateBeats` was
                                // requested for it. Take 2's shorter gate was never actually consulted for
                                // any but the true last repeat — this was never a gate-length question at
                                // all. THE FIX: strike 0 fires immediately as before; repeats 1..<nRep are
                                // registered as ECHO-RING TAILS (`pushEchoTail`) instead of synchronous
                                // strikeChord calls — the SAME mechanism, for the SAME reason, the sibling
                                // RATCHET PATTERN/COIN folds already use (2026-09-06: "a per-tick fold can't
                                // spread strikes across audio blocks... via the ECHO ring so they spread
                                // across render blocks"). Drained one real window at a time as time actually
                                // advances, each repeat's own earlier voice gets a genuine chance to close
                                // naturally before the next one opens — restrike no longer overrides it.
                                // GATE LENGTH (2026-10-13 GATE/legato ferry §3.2, supersedes the earlier
                                // fixed-50%-duty-cycle version): "each repeat uses its own subdivision as its
                                // gap... at 100%, each repeat ends just before the next repeat starts" — GATE
                                // now applies PER-REPEAT too, replacing the hardcoded `*0.5` with `*gate`, so
                                // at 100% a repeat fills its own full subdivision width (ending right where
                                // the next one begins) instead of always sitting at a fixed half-width snap.
                                // MIX TAB: each pitch's repeats use ITS OWN gate — `(sub / nRep) × pitchGate[j]`.
                                let repSpacing = sub / Double(nRep)
                                // RATCH SHAPE (REVIEW FIX 2026-10-23): only an FX ratchet is shaped; a mask RATCHET stays flat (nRep ≠ fxRatchN there).
                                let ratchShape = fxRatchN >= 2 ? Int(fxAll.ratchShape) : 0
                                for j in 0..<pitchCount {
                                    // ferry §4.1: a ratchet's repeats follow the note they repeat — pitch j's own layer mask (the already-resolved busMask the deferred echo tail carries).
                                    let repBusMask = chopMask(cell, m: mTickBeat, S: S, base: busOf(j) ?? bm) & p.mainOutMask
                                    // each repeat lasts its pitch's gate × its slot, never under the 5 ms floor (the slot itself is ≥ 10 ms: `euclideousRatchetCap`)
                                    let repGate = max(minGateBeats5ms, repSpacing * pitchGate[j])
                                    strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: repGate, octave: 0, explicitNote: pitches[j],
                                                explicitVel: euclideousRatchetStrikeVelocity(base: pitchVel[j], shape: ratchShape, k: 0, n: nRep), busOverride: busOf(j))
                                    // A pitch outside MIDI 0…127 is dropped by `strikeChord` (strike 0); its deferred strikes must be dropped too — `UInt8(clamping:)` would turn a
                                    // very low pitch into note 0 and sound it (FX NOTE moves ranks far enough to reach this).
                                    guard nRep > 1, finalPitch(pitches[j], oct: 0) != nil else { continue }
                                    let tieLast = fxRatchN >= 2 && tieOf(j) > 0
                                    // FX §5.4: a tie after a ratcheted hit extends the LAST strike; the earlier ones are unchanged. The last strike is held for the gap left to the next hit in full plus gate × the tie extension (§4.3, with the hit's effective gate).
                                    let lastGate = tieLast ? max(repGate, (nextHitGapBeats - Double(nRep - 1) * repSpacing) + pitchGate[j] * tieOf(j)) : repGate
                                    func gateOf(_ k: Int) -> Double { tieLast && k == nRep - 1 ? lastGate : repGate }
                                    func velOf(_ k: Int) -> UInt8 { euclideousRatchetStrikeVelocity(base: pitchVel[j], shape: ratchShape, k: k, n: nRep) }
                                    // REPEATS INSIDE THIS WINDOW strike where they belong, now. The echo ring is drained at the top of a window, BEFORE the ticks run, so a deferred strike whose time is
                                    // still inside this window would never be looked at again ("tau < lo": skipped) — a ratchet whose slot is shorter than the host buffer lost strikes (1/16 n4 at 4096 frames
                                    // lost 28 %). ROLL / RUN already strike in-window repeats directly, for the same reason.
                                    var k = 1
                                    while k < nRep && mTickBeat + Double(k) * repSpacing < mWinEnd {
                                        strikeChord(tau: mTickBeat + Double(k) * repSpacing, velScale: 1.0, gateBeats: gateOf(k), octave: 0, explicitNote: pitches[j], explicitVel: velOf(k), busOverride: busOf(j))
                                        k += 1
                                    }
                                    guard k < nRep else { continue }
                                    // …the rest are DEFERRED strikes on the echo ring (the first one due is strike `k`: a tail's first repeat sits one `timeBeats` after its onset)
                                    let lastRegular = tieLast ? nRep - 2 : nRep - 1          // the last strike a plain tail serves
                                    if k <= lastRegular {
                                        if ratchShape == 0 {
                                            pushEchoTail(onset: mTickBeat + Double(k - 1) * repSpacing, note: UInt8(clamping: pitches[j]), vel: pitchVel[j], busMask: repBusMask,
                                                         timeBeats: repSpacing, repeats: lastRegular - k + 1, feedDelay: 1.0, decay: 1.0, offset: 0, pitch: 0,
                                                         gateBeats: repGate)
                                        } else {
                                            for m in k...lastRegular {   // a shaped ratchet: one tail per strike, each at its own velocity
                                                pushEchoTail(onset: mTickBeat + Double(m - 1) * repSpacing, note: UInt8(clamping: pitches[j]), vel: velOf(m), busMask: repBusMask,
                                                             timeBeats: repSpacing, repeats: 1, feedDelay: 1.0, decay: 1.0, offset: 0, pitch: 0,
                                                             gateBeats: repGate)
                                            }
                                        }
                                    }
                                    if tieLast && k <= nRep - 1 {
                                        pushEchoTail(onset: mTickBeat + Double(nRep - 2) * repSpacing, note: UInt8(clamping: pitches[j]), vel: velOf(nRep - 1), busMask: repBusMask,
                                                     timeBeats: repSpacing, repeats: 1, feedDelay: 1.0, decay: 1.0, offset: 0, pitch: 0,
                                                     gateBeats: lastGate)
                                    }
                                }
                                // NOTE VIEW covers strike 0 only — the deferred echo repeats don't push their
                                // own events, matching the existing, disclosed precedent for the sibling fold
                                // ("a downstream ECHO echoes only strike 0, not the ratchet copies").
                                if nvSent {
                                    var nc = 0
                                    for j in 0..<pitchCount where nc < Router.noteViewMaxNotes { if let p = finalPitch(pitches[j], oct: 0) { nvScratch[nc] = p; nvVelScratch[nc] = euclideousRatchetStrikeVelocity(base: pitchVel[j], shape: ratchShape, k: 0, n: nRep); nc += 1 } }
                                    if nc > 0 {
                                        let (onset, duration) = nvTiming(repSpacing * pitchGate[0])   // NOTE VIEW's one duration: pitch 0's
                                        pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 0, noteCount: nc,
                                                           column: wipeColumn, rank: wipeRankOut, hasRiffNote: hadRiffNote, withVels: true, cellColumn: wipeCellColumn)
                                    }
                                }
                                cacheWholeSet()
                                return
                            }
                            // ROLL / RUN (NOTES TAB §7.3-§7.4): only the notes layer's OWN notes are spread — the riff note and the mask's CHORD notes always strike at the hit. The first note (slot 0)
                            // strikes now; each later note is a DEFERRED strike on the shared echo ring (the mechanism FX RATCH and the mask's RATCHET use), so it lands on its own sample
                            // whatever the buffer size. A ratcheted hit never reaches here (§7.6): its strikes carry all the chosen notes together.
                            var spreadM = 0
                            for j in 0..<pitchCount where (notesSlotBits >> UInt64(4 * j)) & 0xF != 0xF { spreadM += 1 }
                            let isRun = spreadM >= 1 && notesPlayAs == .run
                            let isRoll = spreadM >= 2 && notesPlayAs == .roll
                            func slotNibble(_ j: Int) -> UInt64 { (notesSlotBits >> UInt64(4 * j)) & 0xF }
                            func strikePosition(_ j: Int) -> Int { var c = 0; let sj = slotNibble(j); for i in 0..<pitchCount where slotNibble(i) != 0xF && slotNibble(i) < sj { c += 1 }; return c }
                            var rollSpacing = 0.0, runSlot = 0.0
                            let runNoteGate = fxLitGate()   // RUN lengths read the notes layer's own gate (at 100% a note fills its slot), not the legato-capped copy the reconcile saw
                            if isRun { runSlot = euclideousNotesRunSlotBeats(stepBeats: sub, m: spreadM) }
                            if isRoll {
                                var firstNotes = 0
                                for j in 0..<pitchCount where slotNibble(j) != 0xF { firstNotes = j; break }
                                rollSpacing = euclideousNotesRollSpacingBeats(m: spreadM, gapBeats: nextHitGapBeats, lenBeats: gateBeatsWithTie(pitchGate[firstNotes], tieOf(firstNotes)),
                                                                              legato: pitchGate[firstNotes] >= 1.0, tempo: tempo)
                            }
                            // ferry §4.1: ROLL/RUN spread the NOTES layer's own notes — each deferred strike routes to pitch j's own mask (notesBus, or a §4.2 collision slot's notesOnly).
                            for j in 0..<pitchCount where handled & (UInt16(1) << UInt16(j)) == 0 {
                                if (isRun || isRoll) && slotNibble(j) != 0xF {
                                    let pos = strikePosition(j)
                                    let start = Double(pos) * (isRun ? runSlot : rollSpacing)
                                    let length = isRun ? max(minGateBeats5ms, runNoteGate * runSlot)
                                                       : max(minGateBeats5ms, gateBeatsWithTie(pitchGate[j], tieOf(j)) - start)   // every note ends where it would without the roll
                                    if pos == 0 || start <= 0 {
                                        strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: length, octave: 0, explicitNote: pitches[j], explicitVel: pitchVel[j], busOverride: busOf(j))
                                    } else if mTickBeat + start < mWinEnd {
                                        // Its own sample is still inside THIS render window. The echo ring is drained at the top of a window, before the ticks run, so a deferred
                                        // strike registered here would only be looked at next window — after its time — and be lost at a large buffer. Strike it where it belongs.
                                        strikeChord(tau: mTickBeat + start, velScale: 1.0, gateBeats: length, octave: 0, explicitNote: pitches[j], explicitVel: pitchVel[j], busOverride: busOf(j))
                                    } else if let fp = finalPitch(pitches[j], oct: 0) {   // a pitch outside MIDI 0…127 is dropped, as `strikeChord` drops it
                                        pushEchoTail(onset: mTickBeat, note: fp, vel: pitchVel[j], busMask: chopMask(cell, m: mTickBeat, S: S, base: busOf(j) ?? bm) & p.mainOutMask,
                                                     timeBeats: start, repeats: 1, feedDelay: 1.0, decay: 1.0, offset: 0, pitch: 0,
                                                     gateBeats: length)
                                    }
                                } else {
                                    strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: gateBeatsWithTie(pitchGate[j], tieOf(j)), octave: 0, explicitNote: pitches[j], explicitVel: pitchVel[j], busOverride: busOf(j))
                                }
                            }
                            cacheWholeSet()
                            if nvSent {
                                var nc = 0
                                for j in 0..<pitchCount where nc < Router.noteViewMaxNotes { if let p = finalPitch(pitches[j], oct: 0) { nvScratch[nc] = p; nvVelScratch[nc] = pitchVel[j]; nc += 1 } }
                                if nc > 0 {
                                    let (onset, duration) = nvTiming(gateBeatsWithTie(pitchGate[0], tieOf(0)))   // NOTE VIEW's one duration: pitch 0's (the riff note when the hit has one)
                                    pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: tieOf(0) > 0 ? 3 : 0, noteCount: nc,
                                                       column: wipeColumn, rank: wipeRankOut, hasRiffNote: hadRiffNote, withVels: true, cellColumn: wipeCellColumn)
                                }
                            }
                            return
                        }
                        if useRiff {
                            // DIRECTION IS PER-LANE (Paul 2026-10-07): riffDir/riffDirSeed/riffDirBias now come from
                            // THIS line (the fn params above), not the shared `p.euclideousRiff` — only the pattern
                            // CONTENT (steps/ranks) is shared; each lane walks it its own way.
                            let rp = p.euclideousRiff
                            // PER-LANE SOURCE (Paul 2026-10-09, ferry §2.4 — supersedes "follows lane 1"):
                            // each lane resolves the shared riff SHAPE against ITS OWN per-lane pool
                            // (`laneNotes(lineIndex)`/`laneCount(lineIndex)` — the exact same per-lane buffer
                            // that lane's own MIDI IN/KEY/CHORDS I/O-tab choice already fills, "whatever
                            // source THIS lane is on," not lane 0's) — so two lanes walking the identical
                            // riff shape with different inputs now genuinely play different notes.
                            let thisLaneCount = laneCount(lineIndex)
                            guard thisLaneCount > 0 else { return }   // the walk itself already advanced above regardless — only the STRIKE needs a non-empty pool
                            let notes = laneNotes(lineIndex)
                            let ranks = rp.ranks ?? []   // SnapshotBuilder always resolves this to a full, padded array (main thread) before Router ever sees it — `?? []` is a type-safety unwrap here, not a real fallback allocation

                            // LEAP (EUCLID MASK, Paul 2026-10-10 ferry §3): "play the riff position STEPS
                            // ahead or behind (wrapping within LENGTH) for this note only. The lane's walk
                            // position does not change." Sits UPSTREAM of INVERT/TRANSPOSE by substituting a
                            // DIFFERENT read position into the rank lookup below, ONLY for this one note —
                            // `euclideousRiffStep[lineIndex]` above was already written from the TRUE
                            // `playedStep`, never touched by this, so the persisted cursor is unaffected.
                            let leapStep = (maskedChancePassed && mm.modeResolved == .leap)
                                ? (((playedStep + mm.leapStepsResolved) % riffLength) + riffLength) % riffLength
                                : playedStep

                            // INVERT (Paul 2026-10-09 ferry): mirrors the rank BEFORE it's resolved against
                            // this lane's own source — "rank r plays as rank (9-r)... rests stay rests" — so
                            // it works identically regardless of source (MIDI/KEY/CHORDS all just feed
                            // `thisLaneCount`/`notes` the same way either side of this transform).
                            let rawRank = leapStep < ranks.count ? ranks[leapStep] : 0
                            let invRank = (riffInvert && rawRank >= 1) ? (9 - rawRank) : rawRank
                            // TRANSPOSE (§3.1/§3.7, Paul 2026-10-10 ferry): a rank-space shift applied AFTER
                            // INVERT, BEFORE resolving against the lane's source — a rest (rank<1) is left
                            // untouched, matching INVERT's own "rests stay rests." Out-of-pool wrap rides
                            // the SAME `riffResolve(wrap: .fold)` call below for free, not a separate rule —
                            // exactly §3.7's own "using the engine's existing rank-to-note wrap rule." OCT
                            // (`riffOctave`) is applied AFTER THAT, inside `riffResolve`'s own `oct:` param —
                            // already the natural ordering, matching §3.1's literal "...resolve against
                            // SOURCE → OCT."
                            let transposedRank = invRank >= 1 ? invRank + melodyTranspose : invRank
                            // EUCLID MASK — MIRROR/CLIMB (Paul 2026-10-10 ferry §3), applied after TRANSPOSE,
                            // mutually exclusive by construction (MODE is one setting per lane): MIRROR reuses
                            // the EXACT (9-rank) formula riffInvert already uses above, applied a SECOND,
                            // independent time — "restores the uninverted rank" is a free algebraic identity
                            // (9-(9-r)=r), no special-casing needed. CLIMB adds its own running rank-space
                            // offset (pool units, same space as TRANSPOSE) — accumulated/wrapped/bounced below,
                            // right before this is read, so the strike site always sees the CURRENT offset.
                            var rank = transposedRank
                            if maskedChancePassed && rank >= 1 {
                                switch mm.modeResolved {
                                case .mirror:
                                    rank = 9 - rank
                                case .climb:
                                    let bound = max(1, thisLaneCount) * (mm.climbRangeResolved == .wrap2 || mm.climbRangeResolved == .bounce2 ? 2 : 1)
                                    var off = euclideousMaskClimbOffset[lineIndex] + mm.climbStepResolved
                                    switch mm.climbRangeResolved {
                                    case .wrap1, .wrap2:
                                        if off >= bound || off <= -bound { off = 0 }
                                    case .bounce1, .bounce2:
                                        if off < -bound { off = -bound - (off + bound) }
                                        else if off > bound { off = bound - (off - bound) }
                                    }
                                    euclideousMaskClimbOffset[lineIndex] = off
                                    rank += off
                                default: break
                                }
                            }

                            // TIE LOOKAHEAD (Paul 2026-10-09 ferry, ON REST = TIE): mirrors the regular chain
                            // RIFF processor's own `tieRun` loop (`emitRiffRow`) exactly in spirit, walking
                            // HITS instead of fixed-rate ticks, since Euclideous's riff only advances on a hit
                            // of THIS lane's own pattern — hits land at irregular beat spacing (a genuine K/N
                            // Euclidean rhythm), so the extension is measured in real pattern-step distance to
                            // the hit that finally breaks the chain, not a fixed per-step duration.
                            //
                            // A LOCK cycle boundary is ALWAYS a hard stop for the chain, for every direction.
                            // LOCK's whole promise is "the same notes fall on the same beats every cycle" —
                            // letting a tie bleed across that boundary would make the FIRST hit of SOME cycles
                            // silently inherit a held note instead of genuinely landing on its own reproducible
                            // strike, breaking that promise for whichever cycles happened to end on a tied
                            // rest. Reasoned through, not asked (ferry §6 only raised a LOCK-cycle question for
                            // PING specifically) — stopping at the boundary is the one reading consistent with
                            // LOCK's own stated guarantee, for every direction alike.
                            //
                            // Bounded, allocation-free: at most `riffN` consecutive hits folded in, and at
                            // most 4 full laps of pattern-steps scanned looking for them (a sparse K=1 pattern
                            // can space hits far apart in step terms) — a safety cap, not expected to bind in
                            // practice.
                            func riffTieExtensionBeats() -> Double {
                                guard riffOnRest == .tie else { return 0 }
                                return euclideousChainTieExtensionBeats(
                                    buf: euclidBuf, n: eN, dir: eDir, cycleLen: cycleLen, sub: sub, tick: tick, chains: chains,
                                    legacySpanBeats: ladderSpanBeats, advanceStep: riffAdvanceStep,
                                    riffDir: riffDir, stride: riffStride, length: riffLength, rotate: riffRotate, seed: seed,
                                    timing: hitTiming,
                                    rankAt: { column, _ in column < ranks.count ? ranks[column] : 0 })
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
                                    let tieExt = riffTieExtensionBeats()
                                    let gb = min(sub * gate, S * 0.95) + tieExt
                                    let fillVel = UInt8(velocityAbsolute)
                                    let fillIdx = resolvedPickIndices(pickIndex, pickRange, count: notes.count)
                                    // TRANSPOSE (Paul 2026-10-10 ferry §3.7) applies here too — FILL strikes
                                    // "this lane's own NOTE/OCT pick as if riff were off," and PLACEMENT's
                                    // TRANSPOSE is mode-independent — via the SAME `riffResolve(wrap: .fold)`
                                    // lookup the real-rank branch below already uses, so an out-of-pool
                                    // transpose wraps identically either way; `octave: 0` to strikeChord since
                                    // the octave shift is already folded into the resolved note, matching that
                                    // branch's own established precedent exactly.
                                    for idx in fillIdx where idx >= 0 && idx < notes.count {
                                        guard let fillNote = riffResolve(rank: idx + 1 + melodyTranspose, oct: octave, n: notes.count, wrap: .fold, asc: { notes[$0].note }) else { continue }
                                        strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: gb, octave: 0, explicitNote: fillNote, explicitVel: fillVel, busOverride: busOverride)
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
                                            guard let fillNote = riffResolve(rank: idx + 1 + melodyTranspose, oct: octave, n: notes.count, wrap: .fold, asc: { notes[$0].note }) else { continue }
                                            if let p = finalPitch(fillNote, oct: 0) { nvScratch[fillNC] = p; fillNC += 1 }
                                        }
                                        if fillNC > 0 {
                                            let (onset, duration) = nvTiming(gb)
                                            // MARKER TELEMETRY (Paul 2026-10-12 ferry, Part 1 rule 7): the ONLY
                                            // strike site that previously left column/rank at their -1 default —
                                            // without this, the riff-grid marker has no way to know which row to
                                            // draw a FILL-on-rest marker at. `column` is `leapStep` (the real rest
                                            // column the walk landed on, matching the real-rank branch's own
                                            // `leapStep` convention below — "mask effects are ignored by the
                                            // prediction," so a LEAP mask active on the SAME lane at the SAME tick
                                            // is a narrow, disclosed edge case where this column could read
                                            // differently from `riffPositions()`'s own true cursor, not fixed here).
                                            // `rank` is FILL's own first struck pool index, 1-based + TRANSPOSE —
                                            // the same rank-space the riff grid's own 1...8 rows use; the FIRST
                                            // struck index stands in for "the note actually sounding" on a
                                            // multi-note FILL pick (ALL/BOT2/TOP2), a disclosed simplification.
                                            let fillRank = (fillIdx.first.map { $0 + 1 + melodyTranspose }) ?? 0
                                            let fillWipeEligible = fillRank >= 1 && fillRank <= 8
                                            pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: tieExt > 0 ? 3 : 0, noteCount: fillNC,
                                                               column: fillWipeEligible ? Int8(leapStep) : -1, rank: fillWipeEligible ? Int8(fillRank) : -1)
                                        }
                                    }
                                    return
                                case .repeatLast:
                                    // RIFF WALK ferry (2026-10-19): REPEAT is Euclideous-row only (§6) — this
                                    // retired, non-Euclideous fork has no UI path that can ever set it. Alias
                                    // to SKIP's own silence rather than build real lookback logic for dead code.
                                    if nvSent {
                                        let (onset, duration) = nvTiming(sub)
                                        pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 2, noteCount: 0)
                                    }
                                    return
                                }
                            }
                            // ABSOLUTE VELOCITY (Paul 2026-10-09): the riff-sourced note's own inherited velocity
                            // is no longer read at all — VELOCITY is a genuine override now, same as every other
                            // strike this lane makes (see EuclidLine.velocityAbsolute's own doc comment).
                            guard let note0 = riffResolve(rank: rank, oct: riffOctave, n: thisLaneCount, wrap: .fold, asc: { notes[$0].note }) else { return }
                            let tieExt = riffTieExtensionBeats()
                            let gb = min(sub * gate, S * 0.95) + tieExt
                            // EUCLID MASK — MUTE/RATCHET/CHORD/OCT/ACCENT/SWELL/REPEAT-trigger (Paul 2026-10-10
                            // ferry §3), applied to the already-fully-resolved primary note/velocity, mutually
                            // exclusive by construction (one MODE per lane). MIRROR/CLIMB already happened
                            // upstream (they adjust `rank` BEFORE `riffResolve`, not the resolved note) — only
                            // the modes that need the FINAL pitch/velocity value need `maskTransform` below.
                            // Shared with plain NOTE mode (`maskTransform`/`maskRatchetReps`'s own doc comments
                            // explain why this is a shared function now, not inline here — 2026-10-12 bug fix).
                            let resolveRank: (Int) -> Int? = { r in riffResolve(rank: r, oct: riffOctave, n: thisLaneCount, wrap: .fold, asc: { notes[$0].note }) }
                            let xf = maskTransform(rank: rank, note: note0, vel: UInt8(velocityAbsolute), lineIndex: lineIndex,
                                                   mm: mm, maskedChancePassed: maskedChancePassed, resolveRank: resolveRank)
                            if xf.muted { return }   // silent; the walk already advanced normally above
                            let note = xf.note, vel = xf.vel, extraNotes = xf.extra
                            let wipeRank = (maskedChancePassed && mm.modeResolved == .mirror && invRank >= 1) ? (9 - invRank) : invRank
                            let wipeEligible = wipeRank >= 1 && wipeRank <= 8
                            // RATCHET (§3): n repeats evenly spaced across `sub` (this lane's own rate-beats-
                            // per-step). AUDIBLE FIX, take 3 (2026-10-13, mirrors the Euclideous pipeline's
                            // identical fix above — takes 1/2 both proved wrong by direct testing: firing all
                            // nRep strikes SYNCHRONOUSLY left every earlier repeat's voice still "active" in
                            // the SAME call when the next one opened, so the engine's own same-pitch restrike
                            // rule force-closed each one at the NEXT ONSET regardless of whatever gate length
                            // was requested — a gate-length tweak alone could never fix this). Strike 0 fires
                            // immediately; repeats 1..<nRep are registered as ECHO-RING TAILS (`pushEchoTail`),
                            // the SAME mechanism the sibling RATCHET PATTERN/COIN folds already use, so each
                            // repeat's own voice gets a genuine chance to close naturally (drained one real
                            // window at a time) before the next one opens. Each repeat's own length is a
                            // short, fixed 50% duty cycle of its own slot, independent of the lane's GATE
                            // value — a real silent gap regardless of how long/short GATE is set.
                            if let nRep = maskRatchetReps(lineIndex: lineIndex, rank: rank, mm: mm, maskedChancePassed: maskedChancePassed, sub: sub, tempo: tempo) {
                                let repGate = (sub / Double(nRep)) * 0.5
                                let repSpacing = sub / Double(nRep)
                                let repBusMask = chopMask(cell, m: mTickBeat, S: S, base: busOverride ?? bm) & p.mainOutMask
                                strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: repGate, octave: 0, explicitNote: note, explicitVel: vel, busOverride: busOverride)
                                if nRep > 1 {
                                    pushEchoTail(onset: mTickBeat, note: UInt8(clamping: note), vel: vel, busMask: repBusMask,
                                                 timeBeats: repSpacing, repeats: nRep - 1, feedDelay: 1.0, decay: 1.0, offset: 0, pitch: 0,
                                                 gateBeats: repGate)
                                }
                                // NOTE VIEW covers strike 0 only — the deferred echo repeats don't push their
                                // own events, matching the existing, disclosed precedent for the sibling fold
                                // ("a downstream ECHO echoes only strike 0, not the ratchet copies").
                                if nvSent, let p0 = finalPitch(note, oct: 0) {
                                    nvScratch[0] = p0
                                    let (onset, duration) = nvTiming(repGate)
                                    pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 0, noteCount: 1,
                                                       column: wipeEligible ? Int8(leapStep) : -1, rank: wipeEligible ? Int8(wipeRank) : -1)
                                }
                                euclideousLastSoundedNote[lineIndex] = Int8(clamping: note); euclideousLastSoundedVel[lineIndex] = vel
                                return
                            }
                            strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: gb, octave: 0, explicitNote: note, explicitVel: vel, busOverride: busOverride)
                            for extra in extraNotes { strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: gb, octave: 0, explicitNote: extra, explicitVel: vel, busOverride: busOverride) }
                            // REPEAT's own cache: only update "last sounded" from a GENUINE, non-repeated strike
                            // (a repeat-hold's own re-strikes, handled far above this block entirely, never reach
                            // here, so this is always a real new note).
                            euclideousLastSoundedNote[lineIndex] = Int8(clamping: note); euclideousLastSoundedVel[lineIndex] = vel
                            // NOTE VIEW: `riffOctave` is already folded into `note` by `riffResolve` itself
                            // (its own `+ 12*oct`), which is why `octave: 0` is passed to strikeChord above —
                            // so the display pitch only adds `transpose`, never re-applying riffOctave.
                            // kind 3 (tied hit) when this strike itself ties through a FOLLOWING rest
                            // (`tieExt > 0`) — see the §4.5 comment on the FILL branch above for why this
                            // needs its own kind, not just a longer `durationBeat` fed into kind 0's formula.
                            if nvSent {
                                var nc = 0
                                if let p = finalPitch(note, oct: 0) { nvScratch[nc] = p; nc += 1 }
                                for extra in extraNotes where nc < Router.noteViewMaxNotes { if let p = finalPitch(extra, oct: 0) { nvScratch[nc] = p; nc += 1 } }
                                if nc > 0 {
                                    let (onset, duration) = nvTiming(gb)
                                    // WIPE TELEMETRY (ferry "riff-cell wipes" §2.2): "after INVERT, MIRROR and LEAP
                                    // but before TRANSPOSE and OCT" — `wipeRank` re-derives MIRROR on `invRank`
                                    // (the pre-TRANSPOSE value), a SEPARATE computation from the real audio
                                    // pipeline's own `rank`/`transposedRank` (untouched), purely to pick which
                                    // shared-grid cell to highlight; `leapStep` is already the post-LEAP column.
                                    // "If that rank is outside 1–8, don't wipe" — guarded below.
                                    pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: (extraNotes.isEmpty && tieExt > 0) ? 3 : 0, noteCount: nc,
                                                       column: wipeEligible ? Int8(leapStep) : -1, rank: wipeEligible ? Int8(wipeRank) : -1)
                                }
                            }
                            return
                        }
                        // SEQUENTIAL SOURCES (Paul 2026-10-02): .riff/.arp step through the immediately-preceding,
                        // non-bypassed slot's OWN authored sequence by `ord` — an explicit resolved MIDI note, not an
                        // index into the held chord, so this is a separate branch, not two more cases folded into the
                        // pool-index switch below. A stored .riff/.arp whose predecessor no longer matches (chain
                        // edited, now bypassed) emits nothing — same honest-non-guess contract as every other noteSel
                        // case that can't resolve (e.g. an aggregate pick against an empty pool).
                        // A RIFF/ARP "sequential source" needs a predecessor slot; Fourfold has none, so such a pick is silent.
                        if noteSel == .riff || noteSel == .arp { return }
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
                        // TRANSPOSE IGNORED IN NOTE MODE (Paul 2026-10-13 ferry, "Engine" rule 1: "Note mode
                        // plays exactly what the button shows... TRANS, INV and the walk settings are ignored
                        // in note mode") — SUPERSEDES the 2026-10-10 ferry's "applies in NOTE mode too" ruling,
                        // a deliberate reversal, not an oversight: a genuine bug was found tracing this before
                        // making the change (this branch WAS still adding `melodyTranspose` below, confirmed by
                        // reading, not assumed) — a note button showing "N3" would have silently played a
                        // transposed pitch if TRANSPOSE had ever been touched on a lane later switched to NOTE
                        // mode, directly contradicting the new ferry's "the button shows exactly what plays."
                        //
                        // EUCLID MASK (BUG FIX 2026-10-12, Paul: "ratchet doesn't work" — see `maskTransform`'s
                        // own doc comment): applies here now too, per resolved note, exactly as it already did
                        // in RIFF mode — previously this whole NOTE-mode branch never consulted the mask at
                        // all, so a lane's MASK (any mode) silently had zero effect unless that lane's SOURCE
                        // was RIFF. `struckNotes` batches a NON-ratcheted hit's notes into ONE combined NOTE
                        // VIEW push (matching the pre-fix behaviour for the common unmasked/multi-note case —
                        // e.g. an ALL pick against a 3-note chord showing all 3 together); a note RATCHET
                        // affects has genuinely diverged from its siblings (its own per-repeat timing), so it
                        // gets its own independent pushes instead, mirroring the riff path's identical split.
                        let resolveHitRank: (Int) -> Int? = { r in riffResolve(rank: r, oct: octave, n: hitNotes.count, wrap: .fold, asc: { hitNotes[$0].note }) }
                        // RENDER-THREAD ALLOCATION FIX (2026-10-13 adversarial review): this used to collect
                        // into a dynamically-growing `var struckNotes: [Int] = []`, allocating heap storage on
                        // the FIRST `.append` of every ordinary NOTE-mode hit — a direct violation of this
                        // file's own invariant 3 ("no allocation on the render path, fixed-size storage only").
                        // `hitNC` now writes DIRECTLY into the shared, preallocated `nvScratch` buffer as each
                        // note strikes, mirroring the exact idiom this same function already uses a few lines
                        // below for RATCHET's own per-repeat push and for the CHORD-effect `extraNotes` loop.
                        var hitNC = 0
                        for idx in hitIdx where idx >= 0 && idx < hitNotes.count {
                            let rank = idx + 1
                            guard let hitNote0 = resolveHitRank(rank) else { continue }
                            let xf = maskTransform(rank: rank, note: hitNote0, vel: hitVel, lineIndex: lineIndex,
                                                   mm: mm, maskedChancePassed: maskedChancePassed, resolveRank: resolveHitRank)
                            if xf.muted { continue }
                            // AUDIBLE RATCHET FIX, take 3 (2026-10-13) — see the riff-mode site's own comment
                            // above: strike 0 fires immediately; repeats 1..<nRep register as ECHO-RING
                            // TAILS (not synchronous strikeChord calls, which left every earlier repeat's
                            // voice "active" when the next one opened, so the engine's own same-pitch
                            // restrike rule force-closed each one at the NEXT ONSET regardless of the
                            // requested gate length — a gate-length tweak alone could never fix this). Each
                            // repeat's own length is a short, fixed 50% duty cycle of its own slot,
                            // independent of `hitGate` entirely.
                            if let nRep = maskRatchetReps(lineIndex: lineIndex, rank: rank, mm: mm, maskedChancePassed: maskedChancePassed, sub: sub, tempo: tempo) {
                                let repGate = (sub / Double(nRep)) * 0.5
                                let repSpacing = sub / Double(nRep)
                                let repBusMask = chopMask(cell, m: mTickBeat, S: S, base: busOverride ?? bm) & p.mainOutMask
                                strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: repGate, octave: 0, explicitNote: xf.note, explicitVel: xf.vel, busOverride: busOverride)
                                if nRep > 1 {
                                    pushEchoTail(onset: mTickBeat, note: UInt8(clamping: xf.note), vel: xf.vel, busMask: repBusMask,
                                                 timeBeats: repSpacing, repeats: nRep - 1, feedDelay: 1.0, decay: 1.0, offset: 0, pitch: 0,
                                                 gateBeats: repGate)
                                }
                                if nvSent, let p0 = finalPitch(xf.note, oct: 0) {
                                    nvScratch[0] = p0
                                    let (onset, duration) = nvTiming(repGate)
                                    pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 0, noteCount: 1)
                                }
                                euclideousLastSoundedNote[lineIndex] = Int8(clamping: xf.note); euclideousLastSoundedVel[lineIndex] = xf.vel
                                continue
                            }
                            strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: hitGate, octave: 0, explicitNote: xf.note, explicitVel: xf.vel, busOverride: busOverride)
                            for extra in xf.extra { strikeChord(tau: mTickBeat, velScale: 1.0, gateBeats: hitGate, octave: 0, explicitNote: extra, explicitVel: xf.vel, busOverride: busOverride) }
                            if nvSent {
                                if hitNC < Router.noteViewMaxNotes, let p = finalPitch(xf.note, oct: 0) { nvScratch[hitNC] = p; hitNC += 1 }
                                for extra in xf.extra where hitNC < Router.noteViewMaxNotes { if let p = finalPitch(extra, oct: 0) { nvScratch[hitNC] = p; hitNC += 1 } }
                            }
                            euclideousLastSoundedNote[lineIndex] = Int8(clamping: xf.note); euclideousLastSoundedVel[lineIndex] = xf.vel
                        }
                        // NOTE VIEW: the combined push for every note this hit struck NORMALLY (not via a
                        // per-repeat RATCHET push, already handled above, each with noteCount:1 of its own).
                        if nvSent, hitNC > 0 {
                            let (onset, duration) = nvTiming(hitGate)
                            pushNoteViewEvent(lane: lineIndex, onsetBeat: onset, durationBeat: duration, kind: 0, noteCount: hitNC)
                        }
                    } else if !isEuclideousRow, let missSel = missNoteSel {
                        // HIT/MISS SPLIT (Paul 2026-10-02: "plays the off notes") — STILL LIVE for the regular,
                        // non-Euclideous BUILD-page EUCLID processor's own dual-voice feature (GridUI.swift's
                        // `euclidHitMissBox`). The `!isEuclideousRow` guard (Paul 2026-10-10 ferry §2.4: "load
                        // it as HIT, ignore the old miss-side settings") is the explicit fix for a real
                        // conflict found during implementation: `missNoteSel`/`missGate`/`missOctave`/
                        // `missVelocity` are SHARED fields the ferry's own "remove from the engine" wording
                        // can't actually mean literally, since the regular processor still needs them — so
                        // instead, Euclideous's own row is unconditionally excluded from this branch,
                        // regardless of whatever stale `missNoteSel` an old Euclideous doc might still carry.
                        // `missNoteSel == nil` is the whole feature's on/off switch (nil ⇒ today's silent-rest
                        // behaviour, byte-identical for every doc that's never touched this) — there's no
                        // separate enable flag. No DIE salt on either side anymore (DIE was removed entire the
                        // same day — "drop it, please"). RIFF/ARP are NOT offered on the miss side (the UI never
                        // shows those two chips there); guarded explicitly so a stray `.riff`/`.arp` miss pick
                        // (a hand-edited doc, or a future UI slip) stays silent rather than falling through to
                        // `resolveEuclidPick`'s `default: (nil, nil)`, which reads as ALL (strike everything) —
                        // an honest no-op, not an accidental loud one.
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
            // A pulses<=0 row is an UNUSED fixed slot — skipped entirely, not run-and-silenced — UNLESS
            // `patternMiss` is engaged (Paul 2026-10-10 ferry §2.2's own literal example: "0 hits in MISS
            // mode plays every step"). Without this exception a 0-pulse line is discarded here BEFORE
            // `runEuclidLine` ever gets a chance to invert it, silently contradicting that exact example — a
            // real bug caught by this ferry's own test, not assumed safe just because the guard predates it.
            // `iterateTicks`
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
            // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, second same-day ferry) — `laneNotes(0)`/
            // `laneCount(0)` now resolve to the ONE shared global pool regardless of the `0` argument
            // (every lane reads the same buffer post-restructure, so this is no longer "lane 0's own pool
            // as a representative sample" — it's definitionally the SAME pool every lane's own walk uses).
            // `euclideousRiffLiveNotes`/`euclideousRiffLivePool()` — the riff panel's existing "show the
            // resolved note" readout — is exactly the new label column's own data source too, unchanged.
            if r == Snap.euclideousRow {
                let notes = laneNotes(0)
                riffSrcNoteCount = min(riffSrcNoteBuf.count, laneCount(0))
                for (i, sn) in notes.enumerated() where i < riffSrcNoteCount { riffSrcNoteBuf[i] = sn }
                euclideousRiffLiveCount = min(euclideousRiffLiveNotes.count, riffSrcNoteCount)
                for i in 0..<euclideousRiffLiveCount { euclideousRiffLiveNotes[i] = UInt8(max(0, min(127, riffSrcNoteBuf[i].note))) }
            } else {
                riffSrcNoteCount = srcNoteCount
                for i in 0..<srcNoteCount { riffSrcNoteBuf[i] = srcNoteBuf[i] }
            }
            // GATE FOLLOWS THE RHYTHM (2026-10-13 ferry §2.5/§4.4: "lane stopped... end everything
            // immediately") — a SEPARATE, UNCONDITIONAL loop over all 4 lines, deliberately NOT nested
            // inside the `where`-filtered dispatch loop below: that loop's own `where ... && L.
            // enabledResolved` guard means its body never executes once a lane is disabled — including on
            // the very render where it flips — so a check placed inside it could never observe the
            // true→false transition at all. Gated on `isEuclideousRow` (the 4-slot `euclideousLegato*`/
            // `euclideousLineWasEnabled` arrays are Euclideous-specific; an ordinary non-Euclideous EUCLID
            // row elsewhere in the grid also populates `p.euclidLines`, confirmed elsewhere in this
            // function — without this guard it would corrupt Euclideous's own tracking).
            if isEuclideousRow {
                for i in 0..<4 {
                    let isEnabled = i < p.euclidLines.count ? p.euclidLines[i].enabledResolved : true
                    if euclideousLineWasEnabled[i] && !isEnabled {
                        let base = i * 9
                        for k in 0..<euclideousLegatoCount[i] {
                            let ownSlot = Int(euclideousLegatoOwnSlot[base + k]), allSlot = Int(euclideousLegatoAllSlot[base + k])
                            if ownSlot >= 0 && ownSlot < voices.count && voices[ownSlot].active { closeVoice(ownSlot, atSample: windowStart, out: out) }
                            if allSlot >= 0 && allSlot < voices.count && voices[allSlot].active { closeVoice(allSlot, atSample: windowStart, out: out) }
                        }
                        euclideousLegatoCount[i] = 0
                    }
                    euclideousLineWasEnabled[i] = isEnabled
                }
            }
            // UI POLL (§4/§6) — written here, once per render window, regardless of `isEuclideousRow`-gating elsewhere: harmless for a
            // non-Euclideous cell (these same defaulted SnapParams fields just resolve to riff 0 there, never read by any UI). The LANES
            // sequencer's single step index is gone with the sequencer (2026-10-18): `euclideousLanesSeqStepLive` stays -1.
            if isEuclideousRow {
                let riffsSeqStepBeats = p.euclideousRiffsSeqRate.barsFraction * beatsPerBar
                let currentRiffsStep = euclideousSeqStepIndex(beat: fBeatPos, stepBeats: riffsSeqStepBeats, len: p.euclideousRiffsSeqLen)
                euclideousRiffsSeqStepLive = currentRiffsStep
            }
            // LANES GRID MUTE EDGE-DETECT (ferry §2.2: "held notes close at the boundary, but the boundaries are now each lane's OWN cell
            // boundaries, not one global step boundary") — the same per-lane legato walk-and-close as the PLAY/STOP sweep above, keyed on
            // "is this lane audible": enabled AND its own mute cell at that beat is set. A lane that went quiet exactly at (or before) this
            // window closes at the window start; one whose next cell boundary falls INSIDE the window closes at that boundary's sample.
            // Runs AFTER the PLAY/STOP sweep (if that already closed this lane's tracked voices this render, `euclideousLegatoCount[i]` is 0
            // and this is a no-op — no double-close).
            if isEuclideousRow {
                let windowEndBeat = fBeatPos + windowBeats
                for i in 0..<4 {
                    let enabled = i < p.euclidLines.count ? p.euclidLines[i].enabledResolved : true
                    var closeAt: Int64? = nil
                    var audibleAtEnd = false
                    if enabled {
                        var cells: UInt16 = 0xFFFF
                        var unit = 0.0
                        if i < p.euclidLines.count {
                            let geo = euclideousLaneStepGeometry(lines: p.euclidLines, lane: i, defaultRateBeats: p.euclidRateBeats)
                            let g = euclideousLaneGridResolved(line: p.euclidLines[i], lane: i, legacyOn: p.euclideousLanesSeqOn,
                                                               legacyRate: p.euclideousLanesSeqRate, legacyLen: p.euclideousLanesSeqLen,
                                                               legacyCells: p.euclideousLanesSeqCells, stepBeats: geo.sub,
                                                               passBeats: Double(geo.cycleLen) * geo.sub, beatsPerBar: beatsPerBar)
                            cells = g.muteCells
                            unit = g.muteUnit.beats(stepBeats: geo.sub, passBeats: Double(geo.cycleLen) * geo.sub)
                        }
                        // LANE SOLO (2026-10-21): a lane the solo mask silences is "not audible" here exactly as a muted cell is — its tracked legato voices close at the window start when solo first silences it, and it is
                        // audible again (for the next edge) when solo lets it back. `euclideousLaneMayStrike` is the one decision, shared with the per-hit test.
                        let soloMaskSweep = soloMaskNow(snapshot: p.soloMask)
                        lastSnapshotSoloMask = p.soloMask & 0x0F
                        cutSoloSilencedLanes(soloMask: soloMaskSweep, atSample: windowStart, out: out)
                        let audibleAtStart = euclideousLaneMayStrike(lane: i, soloMask: soloMaskSweep, muteAudible: euclideousLaneAudible(beat: fBeatPos, cells16: cells, unitBeats: unit), enabled: true)
                        if euclideousLaneWasAudibleThisStep[i] && !audibleAtStart {
                            closeAt = windowStart
                        } else if audibleAtStart,
                                  let b = euclideousLaneMuteStart(fromBeat: fBeatPos, toBeat: windowEndBeat, cells16: cells, unitBeats: unit) {
                            closeAt = windowStart + Int64(max(0, (b - fBeatPos) / beatsPerSample))
                        }
                        audibleAtEnd = euclideousLaneMayStrike(lane: i, soloMask: soloMaskSweep, muteAudible: euclideousLaneAudible(beat: windowEndBeat - 1e-9, cells16: cells, unitBeats: unit), enabled: true)
                    } else if euclideousLaneWasAudibleThisStep[i] {
                        closeAt = windowStart
                    }
                    if let closeSample = closeAt {
                        let base = i * 9
                        for k in 0..<euclideousLegatoCount[i] {
                            let ownSlot = Int(euclideousLegatoOwnSlot[base + k]), allSlot = Int(euclideousLegatoAllSlot[base + k])
                            if ownSlot >= 0 && ownSlot < voices.count && voices[ownSlot].active { closeVoice(ownSlot, atSample: closeSample, out: out) }
                            if allSlot >= 0 && allSlot < voices.count && voices[allSlot].active { closeVoice(allSlot, atSample: closeSample, out: out) }
                        }
                        euclideousLegatoCount[i] = 0
                    }
                    euclideousLaneWasAudibleThisStep[i] = enabled && audibleAtEnd
                }
            }
            // LISTEN (ferry 2026-10-14 §9): "a partner is processed before any lane that listens to it" —
            // Euclideous's own row walks its 4 lanes in that dependency order instead of raw array order;
            // every OTHER `.euclid` cell (LISTEN fields always nil there) gets the byte-identical plain
            // index order back, since `euclideousListenProcessingOrder` reduces to it when no lane has any
            // LISTEN mode lit (confirmed by construction: with every `deps[i]` empty, Kahn's algorithm
            // places lane 0, then 1, then 2, then 3, in that exact order).
            // LANE LOCK (D3): decide, once per window, which locked lanes land on a grid line in it (tick-exact below) and which already run on L.
            if isEuclideousRow && !p.euclideousLocks.isEmpty {
                planLocks(locks: p.euclideousLocks, lines: p.euclidLines, revs: p.lockRevs, windowStartBeat: beatPos, windowEndBeat: beatPos + windowBeats)
            } else {
                lockAnyActive = false; lockHasSplit = false
                if isEuclideousRow { for i in 0..<4 { lockOverrideActive[i] = false } }
            }
            // LISTEN REBUILT: the new single-source processing order (§9.3) — a source is still always
            // processed before any lane that depends on it, now also load-bearing for ECHO (§5.1), which
            // (unlike every OLD mode) reads the source's actual per-hit CAPTURED strike, not a fresh
            // re-derivation from its stored config.
            // Allocation-free: the order is built into a Router-owned scratch (the arrays-and-Set form allocated about eight times per window).
            let euclideousListenCount: Int
            if isEuclideousRow { euclideousListenCount = euclideousListenProcessingOrderInto(&euclideousListenOrderScratch, lines: p.euclidLines) }
            else { euclideousListenCount = min(p.euclidLines.count, euclideousListenOrderScratch.count); for i in 0..<euclideousListenCount { euclideousListenOrderScratch[i] = i } }
            for listenSlot in 0..<euclideousListenCount {
                let lineIndex = euclideousListenOrderScratch[listenSlot]
                guard lineIndex < p.euclidLines.count else { continue }
                // RANDOM MODE ferry (§6.1): "one slot per card tab" — a lane may have THREE independent
                // pending THROW/TWEAK/BACK/hold overrides in flight at once, each at its own `landingBeat`,
                // compared against `beatPos` — the SAME absolute beat every other per-tick decision in this
                // function already uses, never a second clock. A per-tick comparison, not a one-shot consumed
                // flag (invariant 2: derived, never accumulated) — every render re-checks it, so it's stable
                // regardless of how many renders straddle the landing beat. §10's "never touched" fields are
                // enforced structurally: only the three groups of arguments below ever read `*Roll`.
                // §5.6: the hold's own override takes priority — "the original keeps playing until the hold
                // ends" even while an unrelated THROW/TWEAK keeps landing underneath it on schedule.
                func euclideousLandedRoll(_ tab: EuclideousRandomTab) -> EuclideousPendingRoll? {
                    guard isEuclideousRow else { return nil }
                    let slot = euclideousRandomPendingSlot(lane: lineIndex, tab: tab)
                    if slot < euclideousHoldOverrides.count, let hold = euclideousHoldOverrides[slot],
                       euclideousRandomShouldApply(hostBeat: beatPos, landingBeat: hold.landingBeat) { return hold }
                    guard slot < euclideousPendingRolls.count, let roll = euclideousPendingRolls[slot] else { return nil }
                    return euclideousRandomShouldApply(hostBeat: beatPos, landingBeat: roll.landingBeat) ? roll : nil
                }
                let rhythmRoll = euclideousLandedRoll(.rhythm)
                let riffRoll = euclideousLandedRoll(.riff)
                let notesRoll = euclideousLandedRoll(.notes)
                // LANE LOCK: the lane plays its window in one segment, or — when a lock snap lands inside it — in two: the old line for the ticks before the line, L applied from it.
                func runSegment(tickFrom: Double, tickBefore: Double) {
                let L = linesView[lineIndex]
                guard (L.pulses > 0 || L.patternMissResolved) && L.enabledResolved else { return }
                // EUCLIDEOUS (Paul 2026-10-05): per-line RATE (nil ⇒ the machine-wide euclidRateBeats, byte-
                // identical for every line that's never set its own) and per-line EMITTER override (nil ⇒ the
                // cell's own bm, via strikeChord's busOverride).
                // OCT RANGE −2…+2 FOR EUCLIDEOUS ONLY (Paul 2026-10-13 ferry, "Engine" rule 4): `L.octaveResolved`
                // itself stays ±3 (shared with the regular, non-Euclideous BUILD-page EUCLID processor's own
                // OCTAVE stepper — narrowing it there would silently clip an unrelated feature, confirmed by
                // reading `GridUI.swift`'s `-3...3` control before deciding this) — the tighter range is applied
                // right here instead, gated on the SAME `isEuclideousRow` this per-row loop already computed.
                let euclideousOct = isEuclideousRow ? max(-2, min(2, L.octaveResolved)) : L.octaveResolved
                // ALT ferry §4.4: resolve the link once — a follower's MAIN mask + ALT routing become the leader's.
                // Value types only (no heap), so this is allocation-free on the render thread.
                let eff = euclideousEffectiveRouting(L)
                runEuclidLine(lineIndex: lineIndex, pulses: rhythmRoll?.pulses ?? L.pulses, steps: rhythmRoll?.steps ?? L.steps, rotate: rhythmRoll?.rotate ?? L.rotate, dir: L.directionResolved,
                              noteSel: L.noteSelResolved, gate: L.gateResolved, octave: euclideousOct, velocity: L.velocityResolved,
                              velocityAbsolute: L.velocityAbsoluteResolved,
                              rate: L.rate?.beats ?? p.euclidRateBeats, busOverride: L.emitterMask,
                              riffBus: eff.riff.mainMask, notesBus: eff.notes.mainMask, alt: eff,
                              missNoteSel: L.missNoteSel, missGate: L.missGateResolved, missOctave: L.missOctaveResolved, missVelocity: L.missVelocityResolved,
                              patternMiss: L.patternMissResolved,
                              useRiff: L.useRiffResolved, riffRotate: riffRoll?.riffRotate ?? L.riffRotateResolved, riffOctave: L.riffOctaveResolved,
                              // EUCLIDEOUS-SCOPED DRUNK/RANDOM→FWD (Paul 2026-10-13 ferry, Presets rule 1):
                              // `riffStepAt`'s own `.drunk`/`.random` arms already degrade to the plain
                              // forward position regardless (confirmed by reading — this call was already
                              // audibly byte-identical to FWD for either stored value), but the Euclideous-
                              // scoped `euclideousRiffDirResolved` makes that explicit by construction rather
                              // than relying on an incidental engine fallback, and keeps this one call site
                              // consistent with the new WALK row's own "which direction is lit" UI check.
                              riffDir: riffRoll?.riffDir ?? (isEuclideousRow ? L.euclideousRiffDirResolved : L.riffDirResolved), riffDirSeed: L.riffDirSeedResolved, riffDirBias: L.riffDirBiasResolved,
                              tilt: L.tiltResolved,
                              riffLock: L.riffLockResolved, riffInvert: riffRoll?.riffInvert ?? L.riffInvertResolved, riffOnRest: riffRoll?.riffOnRest ?? L.riffOnRestResolved,
                              riffStride: riffRoll?.riffStride ?? L.riffStrideResolved, riffLength: L.riffLengthResolved, riffAdvanceStep: riffRoll?.riffAdvanceStep ?? L.riffAdvanceStepResolved,
                              riffAdvanceEvery: riffRoll?.riffAdvanceEvery ?? L.riffAdvanceEveryResolved,   // RIFF WALK ferry §5: EVERY 1 (today's behaviour) by default
                              // LISTEN (ferry 2026-10-14 §1): "stop the Euclid mask affecting output" —
                              // Euclideous's own row now ALWAYS passes a disabled (default) mask, ignoring
                              // whatever `L.mask` holds, so every MASK-driven branch inside `runEuclidLine`
                              // (MUTE/PAUSE/RATCHET/REPEAT/CHORD/OCT/MIRROR/LEAP/CLIMB/ACCENT/SWELL) goes
                              // inert for Euclideous specifically — the FIELD/UI's underlying data and the
                              // engine code that reads it are both kept exactly as they were ("keep the
                              // mask's code and saved data for now"), just never fed a genuinely-enabled
                              // mask here. The non-Euclideous call path (none exists today, but kept
                              // symmetric for any future caller) still passes the real resolved mask.
                              melodyTranspose: L.melodyTransposeResolved, mask: (isEuclideousRow && !euclideousMaskEnabledForTests) ? EuclidLineMask() : L.maskResolved,
                              // RENDER-THREAD ALLOCATION FIX (2026-10-13 adversarial review): `customHitsResolved`
                              // can allocate (padding/truncating to a target length) whenever the stored array's
                              // own length disagrees with the target — a latent, currently-unreachable risk since
                              // every live write path keeps the two in sync, but a real hazard for a future
                              // migration/preset path that doesn't. The consumer (`runEuclidLine`'s own `if let
                              // custom = customHits {...}` branch, just above) already reads `custom[i]` with its
                              // own per-element bounds check (`i < custom.count ? custom[i] : false`, confirmed by
                              // reading before relying on it) — it already pads a shorter array and truncates a
                              // longer one for free, with no separate resized copy needed. Passing the RAW
                              // `L.customHits` directly removes the allocation possibility structurally, not just
                              // leaves it dormant.
                              customHits: L.customHits,
                              // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry): harmless
                              // no-ops for every non-Euclideous row (the new `isEuclideousRow`-gated branch
                              // inside `runEuclidLine` never reads these otherwise) — `riffOnResolved`/
                              // `litNotesResolved`/etc. already migrate safely to byte-identical legacy
                              // behaviour for any line that's never touched the new fields, confirmed in
                              // Models.swift.
                              riffOn: L.riffOnResolved,
                              // NOTES TAB (2026-10-19): the lit order is fixed-size data (ten bytes and a count), built from the lane's stored order without allocating; WHEN / CHANCE / PLAY AS /
                              // RECEIVED are plain scalars. `noteOctShifts` is no longer passed at all — the per-note octave shifts stopped sounding (§6.7).
                              litOrder: notesRoll?.notesLitOrder ?? L.litOrderResolved, notesWhen: notesRoll?.notesWhen ?? L.notesWhenResolved, notesChance: notesRoll?.notesChance ?? L.notesChanceResolved,
                              notesPlayAs: notesRoll?.notesPlayAs ?? L.notesPlayAsResolved, notesReceivedOnly: L.notesReceivedOnlyResolved,
                              notesOn: L.notesOnResolved, notesVelocity: L.notesVelocityResolved, notesGate: L.notesGateResolved,
                              // LISTEN REBUILT (ferry 2026-10-23) — only Euclideous's own row ever has a
                              // non-OWN mode here (every other `.euclid` cell's `EuclidLine` never sets
                              // these fields, so they resolve to the byte-identical "off" defaults below).
                              listenRhythm: L.listenRhythmResolved, listenSource: L.listenSourceResolved(ownLane: lineIndex),
                              listenDelay: L.listenDelayResolved, listenFeel: L.listenFeelResolved, listenSpeed: L.listenSpeedResolved, listenDirection: L.listenDirectionResolved,
                              listenPitch: L.listenPitchResolved, listenInterval: L.listenIntervalResolved, listenOctave: L.listenOctaveResolved,
                              // RHYTHM POLISH (2026-10-22): a landed rhythm roll replaces the lane's pattern (a randomise clears the fraction), TILT's unrounded marker rides the lane itself.
                              offsetFraction: rhythmRoll == nil ? L.offsetFractionResolved : 0, tiltFine: L.tiltIsFine,
                              tickFrom: tickFrom, tickBefore: tickBefore)
                }
                if lockHasSplit {
                    linesView = lockLinesBefore; runSegment(tickFrom: -Double.infinity, tickBefore: lockSplitBeat)
                    linesView = lockLinesAfter; runSegment(tickFrom: lockSplitBeat, tickBefore: Double.infinity)
                } else {
                    linesView = lockAnyActive ? lockLinesAfter : p.euclidLines
                    runSegment(tickFrom: -Double.infinity, tickBefore: Double.infinity)
                }
            }
            linesView = p.euclidLines   // release the scratch lines (so the next window rewrites them in place)
        default:
            break
        }
    }

    // MARK: - CELL MACHINE (feat/EditPageSpike) stage-2 — the serial chain feed

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

    // MARK: - per-row tick emitters (the process() per-window content, one method per processor)








    // (grid-chaining retired: `emitMirrorRow` — the referenced-parent mirror — is gone.)

    // MARK: - PREVIEW / cell audition (Phase 2, design 2026-07-26)




    // MARK: - audition (§6.4 / delta §5)





}
