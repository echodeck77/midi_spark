//  Kernel.swift
//  MidiSpark — render entry point (spec v2.8 §4/§7).
//  The Kernel owns the INPUT side: transport & musical-context derivation, incoming MIDI
//  (the source pool + passthrough-when-stopped + CC forwarding), and the render-side parameter
//  event route. It then hands off to the Router (Router.swift), which owns grid columns, the
//  per-cell ARP derivation, the note tracker, and emission.
//
//  Invariants (unchanged): render reads ONLY the SnapshotBox; no allocation/locks/ObjC dispatch
//  on the hot path; the playhead is DERIVED, never accumulated.

import Foundation
import AudioToolbox
import AVFoundation
import CoreMIDI
import os

#if DEBUG
private let debugMachTimebase: mach_timebase_info_data_t = { var t = mach_timebase_info_data_t(); mach_timebase_info(&t); return t }()
/// A host time (mach absolute time ticks) as seconds on the `CACurrentMediaTime` timeline — DEBUG device log only.
private func debugHostSeconds(_ host: UInt64) -> Double {
    Double(host) * Double(debugMachTimebase.numer) / Double(max(1, debugMachTimebase.denom)) / 1_000_000_000
}
#endif

// KernelDiag moved to Diag.swift (Foundation-only) so Router can compile into the unit-test target.

/// The LIVE emission seam: adapts the render engine's Foundation-only `MIDIEmitter` protocol onto the
/// host's `AUMIDIOutputEventBlock`. This is the one place a note becomes AudioToolbox — and it lives
/// with the Kernel, the render boundary that already owns AudioToolbox legitimately. Called only from
/// the render thread (synchronously, inside Router.process), so `scratch` is reused without locking and
/// no per-note array is allocated on the hot path (the previous inline code allocated one per emit).
final class LiveMIDIEmitter: MIDIEmitter {
    var out: AUMIDIOutputEventBlock?
    private var scratch: [UInt8] = [0, 0, 0]
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        guard let out else { return }
        scratch[0] = b0; scratch[1] = b1; scratch[2] = b2
        _ = out(sampleTime, cable, 3, &scratch)   // AUEventSampleTime == Int64: passes through unchanged
    }
}

final class Kernel {
    var midiOut: AUMIDIOutputEventBlock?
    var musicalContext: AUHostMusicalContextBlock?
    var transportState: AUHostTransportStateBlock?
    var sampleRate: Double = 44_100
    var store: SnapshotStore?
    private(set) var diag = KernelDiag()


    // §5b COLUMN-SUBSET LAP: the held column keys (bit i = column i), set from the UI (PERFORM only),
    // read on the render thread. Ephemeral like auditionTarget; the UI clears it on stop / EDIT switch.
    private var laneMask: UInt16 = 0
    func setLaneMask(_ mask: UInt16) { laneMask = mask }
    private var panicRequested = false
    func panic() { panicRequested = true }
    // FOURFOLD SETTINGS, MAIN OUT tab (2026-10-15 ferry §4.6): a one-shot request the render thread consumes,
    // same shape as panic above — set from the main thread, read+cleared by this render's own process() call.
    // Narrower than panic: only Euclideous's own row's sounding voices (see Router.process's own consumption).
    private var euclideousAllNotesOffRequested = false
    /// LANE SOLO (2026-10-21): the UI's LIVE solo word — 0x100 | the effective mask (latched | held) once the page has spoken, 0 before. The main thread writes it the instant a SOLO button is touched or lifted;
    /// the render thread reads it once per window (the same plain-var hand-off as `soloEmitterMask` / `velKillMask`), so solo does not wait for a snapshot to be rebuilt and published. The snapshot's own
    /// `soloMask` stays the fallback for a session where no page has spoken.
    private var euclideousSoloLive: UInt16 = 0
    func setEuclideousSoloLive(_ mask: UInt8) { euclideousSoloLive = 0x100 | UInt16(mask & 0x0F) }
    /// RANDOM MODE ferry (§6.1/§6.3): one pending THROW/TWEAK/BACK/hold override per (lane, tab) — §6.1's
    /// "one slot per card tab," so a lane may have up to 3 in flight at once — carrying the beat each takes
    /// effect at. Flat, 12 slots (`euclideousRandomPendingSlot(lane:tab:)` is the one index every reader/
    /// writer uses). The SAME plain-var hand-off `euclideousSoloLive` above already uses (set from the main
    /// thread the instant a roll is queued or a hold starts/ends; read once per window). Never part of the
    /// document/SnapshotBox — the ferry's landing beat already carries a safety margin (the ferry text's own
    /// §6.1) comfortably wider than one render block, so this hand-off's staleness tolerance is harmless.
    private var euclideousPendingRolls = EuclideousPendingRollSlots()
    func setEuclideousPendingRolls(_ rolls: EuclideousPendingRollSlots) { euclideousPendingRolls = rolls }
    /// §5.6 the hold — a SEPARATE, higher-priority override per (lane, tab): "a throw or tweak landing
    /// during a hold changes the current state; the original keeps playing until the hold ends" requires
    /// the normal pending roll above to keep landing on schedule, undisturbed, while this one additionally
    /// overrides what's actually heard. Same plain hand-off; the UI clears a slot itself (a one-shot main-
    /// thread timer at the release beat — §6's landing beats are never used past the point of application,
    /// so there is nothing for Router itself to clear).
    private var euclideousHoldOverrides = EuclideousPendingRollSlots()
    func setEuclideousHoldOverrides(_ rolls: EuclideousPendingRollSlots) { euclideousHoldOverrides = rolls }
    /// LANE LOCK ferry (§6.2/§6.4): the UI's LIVE lock word — which lanes a finger is on (HELD) and each lane's document revision — stored by the main thread at the instant a touch starts / ends or a lock-relevant document
    /// write is made, read once per window by the Router (same plain hand-off as `euclideousSoloLive`). 0 = the page has not spoken: nothing is held and no edit is ever "on its way".
    private var euclideousLockLive: UInt64 = 0
    func setEuclideousLockLive(held: UInt8, revs: UInt32) { euclideousLockLive = EuclideousLockLive.word(held: held, revs: revs) }
    /// The snap seq the Router bumps each time a lock snap lands (one byte per lane) and the beats they landed at — the page polls these and applies the snap to the document (D3/D4).
    func euclideousLockSnapSeq() -> UInt32 { router.lockSnapSeqPacked }
    func euclideousAllNotesOffRequest() { euclideousAllNotesOffRequested = true }
    // MULTI-SCENE: a clean one-shot voice flush on a scene SWITCH — closes the old scene's sounding notes so
    // the new scene starts clean (a generation change alone doesn't flush). Distinct from panic (not hang-logged).
    private var flushRequested = false
    func flushVoices() { flushRequested = true }
    // PIANO LATCH is SELF-ARMING: a door in PIANO mode with picked notes latches WITHOUT the separate LATCH lock —
    // the on-screen notes ARE the pool (there's no live chord to capture, so nothing to "arm"). `effectiveLatchMask`
    // = the lock's `latchArmMask` OR'd with every PIANO door that has notes; it is what the Router + metering + the
    // latched-pool fill all read, so the frozen chord feeds the grid (and BYPASS) the moment notes are chosen.
    // REPLAY (config-sheets stage 3, Paul 2026-08-20): each door has an input RING that records its live notes always
    // (retro-capture); in REPLAY mode the last N passes loop back as the door's LIVING INPUT (it self-arms like PIANO,
    // its cells read the looped pool, live input flows only into the ring). Empty replayMask ⇒ zero effect (byte-
    // identical for every existing doc). ⚠ DEVICE EAR OWED — the audible loop can't be verified off-device.
    private let doorRings = [DoorRing(), DoorRing(), DoorRing(), DoorRing()]
    // MANUAL CATCH (Paul 2026-08-20): a REPLAY door records continuously but only LOOPS after the user presses "LAST N"
    // — that captures the last N passes as a fixed loop and ENGAGES it (press again = release, back to live input).
    private var replayEngagedMask: UInt8 = 0        // which REPLAY doors are actively looping (ephemeral)
    // FILE (config-sheets stage 4): doors playing a loaded .mid clip. The clip arrives in the box (race-safe); on a
    // generation change it's loaded into the door's ring, then plays like an always-engaged loop (phase = beat mod len).
    private var fileMask: UInt8 = 0
    private var fileClipGen: UInt64 = .max          // the box generation whose FILE clips are loaded into the rings
    private var replayCatchToggle: UInt8 = 0        // UI request: toggle door i's catch this render (bit i)
    private var renderWindowBeats = 0.0             // this render block's beat span — the REPLAY look-ahead (block-latency compensation)
    // FREE-RUN CLOCK (Paul 2026-08-25): when the HOST transport is STOPPED and an effective note is held, the plugin runs
    // its OWN beat so the published scene plays (note-triggered play). Enabled by the UI; a persistent accumulator like the
    // note tracker (a transport is inherently accumulated — the host's beatPos is too). Never advances while the host plays.
    private var freeRunEnabled = false
    private var freeRunActive = false
    private var freeRunBeat = 0.0
    private var freeRunEmptyStreak: Int64 = 0   // samples the effective-held set has read empty while free-run is active — the debounce so a momentary blink doesn't stop the clock + restart the pass at column 0 (Paul 2026-09-07)
    func setFreeRunEnabled(_ b: Bool) { freeRunEnabled = b }   // main-thread bool write; a torn read is benign (one late block)




    // Reused 3-byte scratch for passthrough forwarding — avoids a heap allocation per incoming MIDI event
    // on the render thread (invariant 3), mirroring LiveMIDIEmitter's scratch. Single render thread,
    // handleIncoming is not reentrant, so one shared buffer is safe.
    private var passthroughScratch = [UInt8](repeating: 0, count: 3)
    // §item 11 INPUT CABLES (eventList/UMP path): scratch the UMP→legacy parse writes into before
    // handoff to handleIncoming. Same single-render-thread, non-reentrant safety as passthroughScratch.
    private var umpScratch = [UInt8](repeating: 0, count: 3)
    // a8 hang fix (2026-07-25): the passthrough echo is note-balanced through this gate so a note-OFF is
    // forwarded whenever its ON was — even if playing/audition flipped in between (else = a stuck note).
    private var passthroughGate = PassthroughGate()
    // a8 assert-on-silence: the render thread self-HEALS (all-notes-off) and records the episode as plain numbers in
    // KernelDiag; the human os_log now happens OFF the render thread (the VC poll, edge-triggered on `panics`) so a
    // persistent violation can't crackle the audio thread. DEBUG additionally traps into the freshly-built corpse
    // (flip `hardTrapOnStuckNote` to keep testing THROUGH one). RELEASE never traps — never crash a gig.
    #if DEBUG
    private static let hardTrapOnStuckNote = true
    #endif
    // §a8b PLAYING hung-note net: samples the LIVE input has been continuously empty while playing (no armed
    // latch, no audition). The debounce clock for `playingSilenceLeak`; reset to 0 the moment input returns.
    private var emptyInputSamples: Int64 = 0
    // §4b THE FADER-KILL — a velocity fader dragged to its BOTTOM silences that emitter entirely (momentary,
    // ephemeral). Race-safe: single main-thread writer, render reads an aligned byte/bool.

    func euclideousRiffPositions() -> [Int] { router.euclideousRiffPositions() }   // each of Euclideous's 4 lanes' own riff-advance step, polled (Paul 2026-10-06)
    func euclideousRiffWalkState() -> [Int64] { router.euclideousRiffWalkState() }   // the live hit-ordinal each lane's walk last advanced on, for the main-thread cycle prediction (Paul 2026-10-12; simplified from a 3-field tuple once DRUNK was removed, 2026-10-13)
    func euclideousMaskPositions() -> [Int] { router.euclideousMaskPositions() }   // each lane's own mask position, polled — hit-driven, not a self-clock (Paul 2026-10-11 bugfix)
    func euclideousRiffLivePool() -> [UInt8] { router.euclideousRiffLivePool() }   // the ascending notes currently feeding the riff's own pool, polled (Paul 2026-10-08)
    func euclideousSourceStatus() -> Router.EuclideousSourceStatus { router.euclideousSourceStatus() }   // SOURCES STACK ferry (2026-10-26): lane-1's source status, polled
    func euclideousNoteViewEvents() -> [[Router.EuclideousNoteViewEventSnapshot]] { router.drainEuclideousNoteViewEvents() }   // NOTE VIEW's per-lane event queue, drained (Paul 2026-10-10)
    func euclideousLanesSeqStep() -> Int { router.euclideousLanesSeqStep() }   // the LANES sequencer's current step, polled (2026-10-14 sequencer panel ferry)
    func euclideousRiffsSeqStep() -> Int { router.euclideousRiffsSeqStep() }   // the RIFFS sequencer's current step, polled (2026-10-14)
    // `euclideousPlayingRiffIndex()` forwarder deleted 2026-10-18 (adversarial review) — zero callers
    // left once the ferry dropping the looper also dropped the editing-vs-playing distinction it served.

    private var busChannels: [UInt8] = [1, 2, 3, 4, 5, 6, 7, 8]               // CONTROLLER ROUTING (v1): per-port stamp channels (for the re-stamp forward)
    private var ignoreAllNotesOff = true     // INPUT (Paul 2026-09-06): mirror of box.ignoreAllNotesOff — suppress a source's CC120/123 wiping the live pool
    // NOTE MONITOR (Paul 2026-08-29): raw held notes are NOT echoed to the output — a CELL is the sole note source, so a
    // fresh instance (nothing selected) is SILENT. Default OFF; kept as a flag so a soundcheck toggle can re-enable it.
    private let noteMonitorPassthrough = false
    // SOUNDING SNAPSHOT (duration): per receiver, the velocities of the notes CURRENTLY HELD in the pool that
    // pass its filter. Refreshed each render into a fixed buffer (display-only, best-effort like the meters);
    // the UI reads it so a held-chord line/mark shows WHILE the chord is down and vanishes on release. A muted
    // receiver (filter ≥ 17) matches nothing → empty, as it should.
    // FLATTENED to 4×12 VALUE arrays (index i*12+k) — NOT nested [[UInt8]] (Paul 2026-08-24, code-review CR-1). A nested
    // array's per-element render write (`recvHeldVel[i][k] = v`) churns the INNER buffer's refcount while the ~4Hz poll
    // reads that same inner slot → the documented SIGTRAP freelist-corruption race. A flat value array has no inner-array
    // ARC, so the only residual race is a benign torn value (a stale meter byte). Mirrors the Router's flat feeds.

    private let pool = NotePool()       // the source (§2.5), fed by incoming MIDI
    private let router = Router()       // grid → emission (§2/§7)

    #if DEBUG
    // CHAOS ORACLE — the render side builds a full MIDI-CHAIN DUMP when silence looks SUSPICIOUS (playing + held +
    // routed path, yet nothing sounding), stashed for the main-thread driver to read + log. Built ONCE at the streak
    // threshold (rare) so the string alloc never hits the steady hot path. `chaosActive` gates it to a live session.
    #endif
    private let liveEmitter = LiveMIDIEmitter()   // the AUMIDIOutputEventBlock adapter (emission seam)
    // THE REEL-TO-REEL (Paul 2026-08-18): the deck (record/replay), the recording tap wrapping liveEmitter, and the
    // one-shot toggle from the UI (consumed on the render thread — same cross-thread pattern as panicRequested).
    let reel = ReelDeck()
    private let reelTap = ReelTap()
    // THE SESSION TAPE (reel phase 1b, 2026-10-25): everything the output sends since the first play, alongside the deck's 64-pass ring. The render thread writes through `tapeRecorder`; the main thread drains and reads `tape`.
    let tape = SessionTape()
    private let tapeRecorder: TapeRecorder
    // REEL PHASE 1c (REEL-2): while a pass replays, the live engine keeps RUNNING — its output goes to `reelSilentTap` (the tape hears it, the host does not) so the session tape has no hole and the engine is exactly where it
    // would have been when the user hands back to live. `reelFlushTap` is for the flush at the moment replay starts: the host DOES get those note-offs (the live notes must end), and so does the tape. Neither touches the deck.
    func tapeSetOrigin(_ tick: Int) { tapeRecorder.setOrigin(tick: tick) }   // main thread, before the first window: continue a restored session's clock
    private let reelSilentTap = ReelTap()
    private let reelFlushTap = ReelTap()
    init() {
        tapeRecorder = TapeRecorder(writer: tape.writer)
        reelTap.recorder = tapeRecorder
        reelSilentTap.recorder = tapeRecorder
        reelFlushTap.recorder = tapeRecorder
        reelFlushTap.out = liveEmitter
    }
    private var reelToggle = false
    private var reelExitFlush = false
    private var reelLastPass = Int.min
    private var reelTempoStored = 120.0
    private var reelStopRequest = false                             // control thread: stop replay → resume live
    private var reelBrowsing = false                                // the PASS BROWSER pop-up is open → freeze the history tape
    private var reelRecordFromStart = false                         // was the in-progress pass recorded from its start? (only such passes file)
    func reelSetBrowsing(_ on: Bool) { reelBrowsing = on }          // control thread: pop-up opened/closed
    func reelTouch() { reelToggle = true }                          // control thread: request a state toggle
    func reelStateValue() -> Int { switch reel.state { case .off: return 0; case .armed: return 1; case .replaying: return 2 } }
    // THE PASS BROWSER (Paul 2026-08-19): the pop-up reads the ring + selected roll; taps select+replay / stop (deferred to render).
    func reelPassNumbers() -> [Int] { reel.passNumbers() }
    func reelPassSignatures() -> [UInt64] { reel.passSignatures() }   // per-pass content hash (aligned with passNumbers) → REMOVE DUPLICATES
    func reelPassCounter() -> Int { reel.passCounter }                // monotone completed-pass count → per-pass STATE capture (Paul #5)
    func reelSelectedRoll() -> [ReelDeck.Note] { reel.selectedRoll() }   // read-only value copy — safe off the render thread (see BUILD reel note)
    func reelSelectedPassNo() -> Int { reel.selectedPassNo }
    func reelStageLoop(_ events: [ReelDeck.Ev], cycle: Double, pass: Int) -> Bool { reel.stageLoop(events, cycle: cycle, pass: pass) }   // main thread: pin + replay this pass (adopted by the next render window)
    func reelStopReplay() { reelStopRequest = true }
    func reelCycleValue() -> Double { reel.loopCycle }              // the SELECTED pass's length in beats (piano-roll x-axis + export) — not the live rate
    /// EXPORT (step 2): the recorded pass as SMF files — the A–D "sum" plus a per-emitter stem for each that has events.
    // (reelExport() — the whole-pass SMF export — was removed 2026-08-27; superseded by reelExportRange, its only path.)
    /// EXPORT a pass RANGE × a port SELECTION (Paul 2026-08-26). portMask == 0 ⇒ the MASTER (the sum of the eight ports) as one file;
    /// else one stem per selected port (Riff A = bit0 … Notes D = bit7). Each file is the passes [lo,hi] concatenated into one phrase.
    func reelExportRange(fromPass lo: Int, toPass hi: Int, portMask: UInt8) -> [(name: String, data: Data)] {
        let ppq = 480
        var files: [(name: String, data: Data)] = []
        if portMask == 0 {   // MASTER — the sum of the eight ports
            let (evs, total) = reel.exportRangeEvents(fromPass: lo, toPass: hi, cables: Set((1...FourfoldPorts.busCount).map { UInt8($0) }))
            if !evs.isEmpty { files.append((name: "Fourfold-All.mid", data: MidiFile.encode(events: evs, bpm: reelTempoStored, ppq: ppq, loopBeats: total))) }
        } else {                // the SELECTED emitter stems
            for i in 0..<FourfoldPorts.busCount where (portMask & (1 << UInt8(i))) != 0 {
                let (evs, total) = reel.exportRangeEvents(fromPass: lo, toPass: hi, cables: [UInt8(i + 1)])
                if !evs.isEmpty { files.append((name: "Fourfold-\(FourfoldPorts.shortName(cable: i + 1).capitalized).mid", data: MidiFile.encode(events: evs, bpm: reelTempoStored, ppq: ppq, loopBeats: total))) }
            }
        }
        return files
    }
    func reelRangeRoll(fromPass lo: Int, toPass hi: Int) -> (notes: [ReelDeck.Note], cycle: Double) {
        let r = reel.rangeRoll(fromPass: lo, toPass: hi); return (r.notes, r.totalBeats)   // read-only value copy — safe off the render thread while browsing freezes the tape
    }
    private func reelBlanketOff(out: MIDIEmitter?) {                // CC120 + CC123 on every channel × cable — kills the loop's ringing notes on stop
        for cable in UInt8(0)...UInt8(FourfoldPorts.busCount) { for ch in UInt8(0)..<16 {
            out?.emit(sampleTime: renderSampleImmediate, cable: cable, 0xB0 | ch, 120, 0)
            out?.emit(sampleTime: renderSampleImmediate, cable: cable, 0xB0 | ch, 123, 0)
        } }
    }

    // reset() arrives on the CONTROL thread (the AU's reset:, e.g. AUM disabling the plugin) and must NOT mutate the
    // render-shared state (pool / voices / router arrays) there — it races the render thread → a malloc crash (device
    // 2026-08-10). So it only FLAGS; the flush runs at the top of render() on the render thread (performReset below).
    private var pendingReset = false
    func reset() { pendingReset = true }
    private func performReset() {
        pool.reset()
        liveEmitter.out = midiOut       // pick up the current host block before flushing
        router.allNotesOff(atSample: renderSampleImmediate, out: liveEmitter)    // flush any hung notes
        reel.clear(); reelLastPass = Int.min                                     // THE REEL-TO-REEL: drop the tape on reset
        for r in doorRings { r.clearLoop() }; replayEngagedMask = 0; replayCatchToggle = 0   // REPLAY: drop each door's loop + disengage on reset
        fileMask = 0; fileClipGen = .max                                         // FILE: force a reload of clips from the box on the next render
        router.reset()                  // deferred inside the Router too — applied by the process() call this render makes
    }

    // MARK: - render

    func render(timestamp: UnsafePointer<AudioTimeStamp>,
                frameCount: AUAudioFrameCount,
                events: UnsafePointer<AURenderEvent>?) {

        guard let box = store?.acquire() else { return }
        if pendingReset { pendingReset = false; performReset() }   // deferred reset — runs on the render thread (no race with the control-thread reset())
        busChannels = box.busChannels                   // CONTROLLER ROUTING: per-emitter stamp channels
        ignoreAllNotesOff = box.ignoreAllNotesOff        // INPUT: don't let a source's CC120/123 flood wipe the live pool (Paul 2026-09-06)
        diag.renderCount &+= 1
        diag.snapshotGen = box.generation
        liveEmitter.out = midiOut       // sync the emission seam to the current host block, this render

        // A real document edit published a fresh snapshot → drop render-side overrides. Must run
        // BEFORE this render's parameter events are applied (§7).
        router.refreshOverrides(forGeneration: box.generation)

        // ---- transport & musical context (derived every render) ----
        var playing = false
        var beatPos = 0.0
        var tempo = 120.0
        if let ts = transportState {
            var flags = AUHostTransportStateFlags()
            _ = ts(&flags, nil, nil, nil)
            playing = flags.contains(.moving)
        }
        // FERRY (2026-10-14 §3, "sequencer step length"): `tsNum`/`tsDen` (the host's real time signature)
        // were ALREADY being read from the musical context block every render — then discarded. Nothing
        // downstream had any way to learn the host's real bar length, so Euclideous's own LANES/RIFFS
        // sequencer silently fell back to the GRID's own geometry (8 columns × the scene's stepRate) as a
        // stand-in for "one bar" — correct only by coincidence at one specific stepRate. `beatsPerBar` is
        // this engine's own beat unit (quarter notes, matching `tempo`'s BPM convention throughout this
        // file) — `tsNum` beats of `1/tsDen` each converts to `tsNum × 4/tsDen` quarter notes (e.g. 4/4 → 4,
        // 3/4 → 3, 6/8 → 3). Defaults to 4.0 (common time) when the host doesn't report a usable signature,
        // matching every other "unexpected ⇒ benign" default in this file.
        var beatsPerBar = 4.0
        // `sampleOffsetToNextBeat` was previously read and DISCARDED here — the same read-then-throw-away
        // shape as the tsNum/tsDen bug the 2026-10-14 ferry fixed. It is now used (below) purely as a
        // read-only cross-check on `beatPos`'s own precision; it does not alter any timing decision.
        var beatRefOffsetToNextBeat = -1
        if let mc = musicalContext {
            var bpm = 0.0, beat = 0.0
            var tsNum = 0.0; var tsDen: Int = 0; var sampleOffset: Int = 0; var measureBeat = 0.0
            if mc(&bpm, &tsNum, &tsDen, &beat, &sampleOffset, &measureBeat) {
                tempo = bpm > 0 ? bpm : 120
                beatPos = beat
                beatRefOffsetToNextBeat = sampleOffset
                if tsNum > 0, tsDen > 0 { beatsPerBar = tsNum * 4.0 / Double(tsDen) }
            }
        }
        diag.playing = playing; diag.beat = beatPos; diag.tempo = tempo; diag.beatsPerBar = beatsPerBar
        // See KernelDiag.beatRefErrorSamples: does the host's own "samples to the next beat" agree with the
        // fractional part of the beat position it handed us in the same call?
        diag.beatRefFrames = Int(frameCount)
        if beatRefOffsetToNextBeat >= 0, tempo > 0, sampleRate > 0 {
            let samplesPerBeat = sampleRate * 60.0 / tempo
            let fracIntoBeat = beatPos - beatPos.rounded(.down)
            let expectedToNextBeat = (1.0 - fracIntoBeat) * samplesPerBeat
            diag.beatRefErrorSamples = Double(beatRefOffsetToNextBeat) - expectedToNextBeat
            diag.beatRefValid = true
        } else {
            diag.beatRefErrorSamples = 0
            diag.beatRefValid = false
        }

        // ---- event list: MIDI + parameter events ----
        var ev = events
        while let e = ev {
            // Read each event as the one struct it is, NOT through `e.pointee.<member>`: AURenderEvent is a union, and Swift copies the WHOLE union (296 bytes) to read any member — more than the host allocated for a 24-byte MIDI event, so
            // the copy ran off the end of the event (AddressSanitizer: heap-buffer-overflow READ of 296, found 2026-10-25 by the soak). Every event begins with the same header.
            let raw = UnsafeRawPointer(e)
            let head = raw.assumingMemoryBound(to: AURenderEventHeader.self).pointee
            switch head.eventType {
            case .MIDI:
                let midi = raw.assumingMemoryBound(to: AUMIDIEvent.self).pointee
                withUnsafeBytes(of: midi.data) { raw in
                    let bytes = raw.bindMemory(to: UInt8.self)
                    let length = Int(midi.length)
                    if length >= 1 {
                        // §item 11 INPUT CABLES: map the host cable (0-based) to 1-based (cables 1–4);
                        // a single-input host delivers cable 0 → 1, which ANY receivers hear unchanged.
                        let eventCable = Int(midi.cable) + 1
                        handleIncoming(bytes: bytes, length: length,
                                       sampleTime: midi.eventSampleTime,
                                       playing: playing, cable: eventCable)
                    }
                }
            case .midiEventList:
                // §item 11 INPUT CABLES — the UMP / MIDI-2.0 path. Hosts that negotiate the eventList
                // protocol deliver events here instead of .MIDI; the UMP GROUP is the cable equivalent.
                // Walk the list IN PLACE (never copy — MIDIEventList is variable-length; a value copy
                // would drop trailing packets), decode each Channel-Voice message to legacy bytes.
                let ts = head.eventSampleTime
                if let listPtr = e.pointer(to: \.MIDIEventsList.eventList) {
                    var pkt = listPtr.pointer(to: \.packet)!
                    for _ in 0..<Int(listPtr.pointee.numPackets) {
                        processUMPPacket(pkt, sampleTime: ts, playing: playing)
                        pkt = UnsafePointer(MIDIEventPacketNext(UnsafeMutablePointer(mutating: pkt)))
                    }
                }
            case .parameter, .parameterRamp:
                let pe = raw.assumingMemoryBound(to: AUParameterEvent.self).pointee
                router.applyParamEvent(pe.parameterAddress, Double(pe.value), atSample: pe.eventSampleTime,
                                       rampDurationSampleFrames: pe.rampDurationSampleFrames, diag: &diag)
            default:
                break
            }
            ev = UnsafePointer(head.next)
        }

        // ---- THE REEL-TO-REEL: record/replay the emitter output (Paul 2026-08-18) ----
        // The pass length = 8 columns at the EFFECTIVE clock. ROW 8 HALFTIME scales the column clock (box.clockScale:
        // ÷2 ⇒ 2.0, so a bar is twice as long), so the reel must scale too — else it chops passes (+ exports the loop)
        // at the WRONG length under half/double speed and the MIDI comes out garbled (Paul 2026-08-24).
        let reelCycleBeats = Double(Snap.cols) * box.stepBeats
        let reelBps = sampleRate > 0 ? tempo / 60.0 / sampleRate : 0
        let reelWinStart = Int64(timestamp.pointee.mSampleTime)
        if reelToggle {                                            // a touch: off→armed · armed→off · replaying→off(+flush)
            reelToggle = false
            switch reel.state {
            case .off: reel.state = .armed
            case .armed: reel.state = .off
            case .replaying: reel.state = .off; reelExitFlush = true
            }
        }
        if !playing, reel.state != .off { reel.state = .off; reelExitFlush = true }   // transport stop → resume live
        if reel.adoptStagedLoop() {                                // the pop-up tapped a pass (REEL PHASE 1c: built from the session tape on the main thread and staged): it is pinned now — REPLAY NOW (replace live output)
            reel.state = .replaying; router.externalFlush(box: box, atSample: renderSampleImmediate, out: reelFlushTap)   // reel REPLACES live output (externalFlush also clears glide/mod — Finding 1: no process() edge here) → flush the live WIRE/bypass monitor too (reconcileBypass is skipped during replay, so it can't close them → hung notes, Paul 2026-08-24)
        }
        if reelStopRequest {                                       // the pop-up stopped replay: resume live, drop the pin
            reelStopRequest = false
            if reel.state == .replaying { reel.state = .off; reelExitFlush = true }
            reel.clearSelection()
        }
        reelTempoStored = tempo                                     // remembered for EXPORT (the loop length is now per-pass: reel.loopCycle)
        reel.cycleBeats = reelCycleBeats                            // the pass browser closes open notes in the roll at this length
        // THE HISTORY FREEZES while you're IN reel-to-reel (Paul 2026-08-19): the browser open OR a pass replaying → the
        // tape stops writing, so the pass list stays a stable snapshot. Recording resumes on the NEXT full pass on exit.
        let reelFrozen = reelBrowsing || reel.state == .replaying
        let reelPass = playing ? Int((beatPos / max(0.0001, reelCycleBeats)).rounded(.down)) : Int.min
        if playing, reelPass != reelLastPass {                     // pass boundary
            if reelRecordFromStart && !reelFrozen { reel.promote() }   // file ONLY a pass recorded start→finish, uninterrupted by reel mode
            if reel.state == .armed { reel.state = .replaying; router.externalFlush(box: box, atSample: renderSampleImmediate, out: reelFlushTap) }   // armed→replaying (externalFlush also clears glide/mod — Finding 1: no process() edge here): flush the live WIRE/bypass monitor too (see above)
            reel.startPass(pass: reelPass); reelLastPass = reelPass
            reelRecordFromStart = playing && !reelFrozen           // will the NEW pass record from its start? (partial/frozen passes never file)
        }
        if reelExitFlush { reelExitFlush = false; reelBlanketOff(out: liveEmitter) }
        reelTap.out = liveEmitter; reelTap.deck = reel
        tapeRecorder.beginWindow(playing: playing, beatPos: beatPos, windowBeats: Double(frameCount) * reelBps, tempo: tempo, cycleBeats: reelCycleBeats, sampleStart: reelWinStart, beatsPerSample: reelBps)
        reelTap.recording = playing && !reelFrozen
        reelTap.base = beatPos; reelTap.beatsPerSample = reelBps; reelTap.cycleBeats = reelCycleBeats; reelTap.windowStart = reelWinStart

        // FREE-RUN CLOCK: host stopped + an effective note held (live OR latched — latch/hold/keys honoured) ⇒ advance the
        // plugin's own beat and drive the scene as if playing; stop + FLUSH when the pool empties (no stuck notes). The
        // router sees a start-edge (scene reset) on begin. Byte-identical while the host plays (the guard is `!playing`).
        // GATED (Paul 2026-08-27, FERRY-strike-anchor ①): `freeRunEnabled` is now driven by BuildPage.buildPublishScene()
        // from the active play mode (PLAY THIS MIDI CHAIN / PLAY THIS PART / START THE PLAY GRID) — all off ⇒ this whole
        // block is inert ⇒ stopped is silent. It was a blanket-true-on-BUILD (the reverted held-note internal transport).
        var rPlaying = playing, rBeat = beatPos
        if freeRunEnabled && !playing {
            let effHeld = pool.count > 0
            // DEBOUNCE + CONTINUOUS BEAT (Paul 2026-09-07 — the "drops passes" amplifier): free-run must NOT stop the instant
            // the effective-held set reads empty for a single render. With a STACCATO source the live pool is empty between
            // chords, so effHeld leans entirely on the frozen HOLD pool; a one-render blink there would otherwise stop+flush
            // AND reset freeRunBeat to 0, restarting the grid at column 0 and dropping the rest of the pass. So: keep the beat
            // ADVANCING (never reset mid-run) and only truly stop after the held set has been empty for a GRACE window. A held
            // HOLD chord keeps effHeld true throughout, so this only ever absorbs a transient.
            freeRunEmptyStreak = effHeld ? 0 : (freeRunEmptyStreak &+ Int64(frameCount))
            let graceSamples = Int64(sampleRate * 0.5)   // ~0.5 s — far longer than a staccato gap / a capture blink, far shorter than "input stopped"
            if effHeld || (freeRunActive && freeRunEmptyStreak <= graceSamples) {
                if !freeRunActive { freeRunActive = true; freeRunBeat = 0; freeRunEmptyStreak = 0 }   // COLD start only → beat 0; a within-grace blink carries the beat (no column-0 restart)
                freeRunBeat += renderWindowBeats
                rPlaying = true; rBeat = freeRunBeat
            } else if freeRunActive {                    // grace elapsed with no input → genuinely stop + flush
                freeRunActive = false; freeRunBeat = 0; freeRunEmptyStreak = 0
                router.externalFlush(box: box, atSample: renderSampleImmediate, out: liveEmitter)   // Finding 1: flush glide/mod too (no process() edge here → stale glide slot otherwise)
            }
        } else if freeRunActive {   // host started, or free-run disabled mid-run → stop + flush the free-run notes (immediate — NOT debounced; hand the clock back at once)
            freeRunEmptyStreak = 0
            freeRunActive = false; freeRunBeat = 0
            router.externalFlush(box: box, atSample: renderSampleImmediate, out: liveEmitter)   // Finding 1: flush glide/mod too (no process() edge here → stale glide slot otherwise)
        }
        diag.beat = rBeat            // EFFECTIVE beat (host OR free-run) → UI beat-driven playheads work while the host is stopped (Paul 2026-08-29)
        diag.effectivePlaying = rPlaying   // host OR free-run actually running → the UI shows "playing" only when sound is really happening (Paul 2026-09-04)
        // REPLACE the live output with the recorded loop — but keep the live engine running underneath, silently (REEL PHASE 1c): the session tape goes on recording what it plays.
        let replayingLoop = reel.state == .replaying && reel.hasLoop
        if replayingLoop {
            reel.replay(beatPos: beatPos, windowBeats: Double(frameCount) * reelBps, cycleBeats: reel.loopCycle,   // loop at the SELECTED pass's own length, not the live rate
                        beatsPerSample: reelBps, windowStart: reelWinStart, out: liveEmitter)
        }
        do {
        // ---- hand off to the router (columns, arp, emission, note tracker) — output through the recording tap ----
        #if DEBUG
        // DEVICE LOG (walk-tags ferry 2026-10-15): stamp the window's first sample on the CACurrentMediaTime timeline so
        // the Router can date each note-on for the page's "HIT lane step t" line. Debug builds only; two scalar writes.
        router.debugWindowHostSeconds = timestamp.pointee.mFlags.contains(.hostTimeValid) ? debugHostSeconds(timestamp.pointee.mHostTime) : 0
        #endif
        router.process(box: box, pool: pool,
                        playing: rPlaying, beatPos: rBeat, tempo: tempo, beatsPerBar: beatsPerBar,
                        sampleRate: sampleRate,
                        timestampSample: timestamp.pointee.mSampleTime,
                        frameCount: frameCount, laneMask: laneMask,
                        panic: panicRequested,
                        euclideousAllNotesOff: euclideousAllNotesOffRequested,
                        euclideousSoloLive: euclideousSoloLive,
                        euclideousPendingRolls: euclideousPendingRolls,
                        euclideousHoldOverrides: euclideousHoldOverrides,
                        euclideousLockLive: euclideousLockLive,
                        sceneFlush: flushRequested,
                        out: replayingLoop ? reelSilentTap : reelTap, diag: &diag)   // → reelTap (reel + session tape) → liveEmitter; or, while a pass replays, the silent tap (session tape only)
        }
        diag.reelState = reelStateValue()
        panicRequested = false          // master panel PANIC is a one-shot — consumed by this render's flush
        euclideousAllNotesOffRequested = false   // one-shot — consumed by this render's flush
        flushRequested = false          // MULTI-SCENE scene-switch flush is a one-shot too

        // ---- a8 ASSERT-ON-SILENCE net: when nothing legitimately sounds (stopped, no held input, no
        //      audition), any lingering router voice or passthrough echo is a STUCK NOTE. Force silence —
        //      safe by construction here (nothing real is playing) — and count the self-heal for the poll.
        //      EFFECTIVE-PLAYING (Paul 2026-08-26): use `rPlaying`, not the host `playing` — during the FREE-RUN
        //      clock the engine drives voices while the host is STOPPED (from a latched/held chord, so the LIVE
        //      pool can be empty). Checking the host flag falsely fired this hard invariant on free-run (crash).
        diag.passthroughHeld = passthroughGate.activeCount
        let now = Int64(timestamp.pointee.mSampleTime)
        // `producing` = the engine is legitimately driving output: the host plays, the free-run clock runs, OR the reel
        // is replaying (which REPLACES the output and SKIPS router.process → activeVoiceCount goes stale; the soft net
        // already exempts it, so the hard net must too).
        let producing = rPlaying || reel.state == .replaying
        if silenceInvariantViolated(playing: producing, heldInput: pool.count, auditioning: false,
                                    activeVoices: diag.activeVoiceCount, passthroughHeld: diag.passthroughHeld) {
            healStuckNotes(now: now, hardTrap: true, reasonCode: 1, diag: &diag)   // 1 = silence invariant (stopped); DEBUG traps into the corpse
            emptyInputSamples = 0
        } else {
            diag.silenceViolated = false
            // §a8b PLAYING hung-note net — the sibling the stopped-net can't see. While the transport RUNS with
            // no LIVE input, no armed latch (which legitimately sustains a frozen chord), and no audition, the
            // grid has no source: after a debounce (kept ≥ a few columns so a note released mid-column still
            // rings to its boundary) any voice left sounding is stuck (e.g. a harmonizer off that went missing).
            // Soft-heal only (log + all-notes-off) — heuristic, so it never hard-traps.
            // CR-18[extra]: reel REPLAY replaces the live output and SKIPS router.process, so diag.activeVoiceCount goes
            // stale — exempt the replay state from the leak net (else it false-fires "playing silence leak", bumping diag.panics).
            // ROW 8 FREEZE (Paul 2026-08-22): frozen = voices deliberately SUSTAIN with no emission → exempt it too.
            let liveEmpty = playing && pool.count == 0 && reel.state != .replaying
            emptyInputSamples = liveEmpty ? emptyInputSamples &+ Int64(frameCount) : 0
            let columnSamples = Int64(max(1.0, box.stepBeats * 60.0 / max(1.0, tempo) * sampleRate))
            let debounce = max(Int64(sampleRate), 4 &* columnSamples)   // ≥ 1 s AND ≥ 4 columns — never cuts a legit tail
            if playingSilenceLeak(playing: playing, liveInput: pool.count, latchArmed: false,
                                  auditioning: false, emptyInputSamples: emptyInputSamples,
                                  debounceSamples: debounce, activeVoices: diag.activeVoiceCount,
                                  passthroughHeld: diag.passthroughHeld) {
                healStuckNotes(now: now, hardTrap: false, reasonCode: 2, diag: &diag)   // 2 = playing silence leak (soft — no trap)
                emptyInputSamples = 0
            }
        }
    }

    /// Force-silence the whole engine (the STUCK-NOTE heal shared by both a8 nets): dump the corpse for the
    /// log FIRST (always legible), all-notes-off every router voice, flush any stranded passthrough echo as a
    /// note-off on All + Emit Riff A, and count the self-heal. `hardTrap` = a HARD invariant (DEBUG crashes into the
    /// logged corpse); false = a heuristic net (soft-heal only, no trap).
    private func healStuckNotes(now: Int64, hardTrap: Bool, reasonCode: Int32, diag: inout KernelDiag) {
        // RENDER-THREAD DISCIPLINE (Paul 2026-09-12): the CURE runs here (alloc-free); the REPORT does NOT. We record
        // the reason + pre-flush counts as plain numbers and the main-thread poll (edge-triggered on `panics`, at 4 Hz,
        // ONCE per episode) builds the human line + os_logs it. The old version built a `[String]` voice fingerprint +
        // a `dump` String + `os_log(.fault)` on the audio thread EVERY block the violation persisted — a per-block heap
        // alloc + hang-subsystem log = audible crackle / a DSP MAX overload. No String / no os_log on this path now.
        diag.stuckReason = reasonCode
        diag.stuckVoices = diag.activeVoiceCount        // capture BEFORE the flush zeroes them (for the off-thread log)
        diag.stuckEchoes = diag.passthroughHeld
        diag.silenceViolated = true
        diag.panics &+= 1
        router.allNotesOff(atSample: now, out: reelTap)                  // close any leaked sequenced voices (alloc-free). Through the reel tap, so the offs that really went out are on the tape too (reel phase 1b)
        if let out = midiOut {                                           // flush stranded echoes as offs on All + Emit Riff A
            let drained = passthroughGate.drainActive()                  // fills a fixed-size scratch + returns a count — no allocation even when echoes are genuinely stranded (code-review finding 2026-10-04)
            for i in 0..<drained {
                let (chan, note) = passthroughGate.drained(i)
                passthroughScratch[0] = 0x80 | chan; passthroughScratch[1] = note; passthroughScratch[2] = 0
                _ = out(now, 0, 3, &passthroughScratch)
                _ = out(now, 1, 3, &passthroughScratch)
            }
        }
        diag.activeVoiceCount = 0; diag.passthroughHeld = 0
        #if DEBUG
        if hardTrap && Self.hardTrapOnStuckNote {                        // DEBUG ONLY (never the crackle build): build the corpse + crash into it
            let dump = "Fourfold STUCK-NOTE (reason \(reasonCode)): voices=[\(router.stuckVoiceFingerprint())] "
                     + "echoes=[\(passthroughGate.heldFingerprint())]"
            assertionFailure(dump)
        }
        #endif
    }


    // MARK: - incoming MIDI (source pool + passthrough)

    private func handleIncoming(bytes: UnsafeBufferPointer<UInt8>, length: Int,
                                sampleTime: AUEventSampleTime, playing: Bool, cable: Int = 0) {
        let status = bytes[0] & 0xF0
        let isNote = (status == 0x90 || status == 0x80)
        let channel = bytes[0] & 0x0F
        if status == 0x90, length >= 3 {
            pool.noteOn(bytes[1], velocity: bytes[2], channel: channel, cable: UInt8(clamping: cable))
        } else if status == 0x80, length >= 3 {
            pool.noteOff(bytes[1])
        }
        if !isNote {
            diag.ccCount &+= 1
            diag.ccStatus = bytes[0]
            diag.ccData1 = length > 1 ? bytes[1] : 0
            diag.ccData2 = length > 2 ? bytes[2] : 0
            if status == 0xB0, length >= 3 {
                // CC120/123 = ALL-SOUND / ALL-NOTES-OFF → flush our LIVE input pool, then forward. But do NOT touch the armed
                // LATCH/HOLD pools (Paul 2026-08-31 ROOT CAUSE): many sources send CC123 routinely (on chord release, between
                // phrases, on transport events), and wiping the frozen chord broke HOLD — the held chord died + the input
                // indicator dropped to zero on every new chord (app-independent). A user's HOLD is a deliberate freeze that must
                // survive a source's all-notes-off; a real host panic/transport-stop flushes stuck notes via the edge allNotesOff.
                // IGNORE ALL-NOTES-OFF (Paul 2026-09-06): a source that floods CC120/123 on every channel around each chord
                // (confirmed via MIDI monitor) would wipe the whole live pool here — silencing a sustained chord even though
                // the notes are still held (the "empty pass" report; channel-agnostic, so it hit even a channel-filtered door).
                // Default ON (ignore); real note-offs still release notes, host/transport panic still flushes stuck notes.
                // (The HOLD door no longer needs a "boundary" signal from this flood — it MIRRORS the live chord; see
                // updateLatchedPools' HOLD branch.)
                if (bytes[1] == 120 || bytes[1] == 123) && !ignoreAllNotesOff { pool.reset() }
            }
        }
        // CONTROLLER ROUTING (v1): CC · PB · AT · PC forward to each door's CONTROLLERS emitters (union), RE-STAMPED to
        // the emitter's stamp channel + cable. SUPERSEDES the old CC/PB/AT passthrough (All + Emit Riff A). Notes (soundcheck)
        // + system keep the passthrough below. (Ownership suppression — a BEND/MOD stage owning an address — is the
        // reserved rule, not v1: for now forward + generate both, last-writer.)
        if isForwardableController(bytes[0]), let out = midiOut {
            let fwd: UInt8 = 0xFF   // CC · PC · AT · PB from any input go to all eight ports (Riff A … Notes D), re-stamped with each port's own channel
            // CC120/123 (all-sound/all-notes-off): do NOT relay it to the synth when either a HOLD/LATCH is armed (it would
            // kill the deliberately-held chord DOWNSTREAM even though we keep it internally) OR ignoreAllNotesOff is on (the
            // source floods it as noise — Finding 2, 2026-09-07: forwarding it when NO latch was armed silenced the grid's OWN
            // sustained/legato output at the synth while our refcount still held those notes, an inconsistency vs the pool
            // suppression). Other CCs forward normally. Device-owed (Kernel isn't unit-tested).
            let suppressAllOff = (bytes[0] & 0xF0) == 0xB0 && length >= 2 && (bytes[1] == 120 || bytes[1] == 123) && ignoreAllNotesOff
            if fwd != 0 && !suppressAllOff {
                let n = min(length, 3)
                for i in 0..<n { passthroughScratch[i] = bytes[i] }
                var m = fwd
                while m != 0 {
                    let bus = Int(m.trailingZeroBitCount); m &= m - 1
                    passthroughScratch[0] = (bytes[0] & 0xF0) | ((busChannels[bus] &- 1) & 15)   // RE-STAMP the channel
                    _ = out(sampleTime, UInt8(bus + 1), n, &passthroughScratch)                  // the port's cable (Riff A = 1 … Notes D = 8)
                }
            }
            return   // controller handled by the routing forward — skip the legacy passthrough
        }
        // §2.6 (reconciled to §7b): stopped-note passthrough (soundcheck) go out on All (0) + Emit Riff A (1).
        // a8: routed through the gate so a note-OFF follows its forwarded ON regardless of state now.
        let pNote = length >= 2 ? bytes[1] : 0
        let pVel  = length >= 3 ? bytes[2] : 0
        // NOTE MONITOR OFF by policy (Paul 2026-08-29: "silence as no cell is selected"). Folding !noteMonitorPassthrough
        // into auditionSuppressing makes the gate treat every raw note as suppressed → mask 0 AND tracked want=false, so
        // its OFF also drops (no spurious note-off, no stuck note). System messages (isNote=false in the gate) still forward.
        let mask = passthroughGate.mask(statusByte: bytes[0], note: pNote, velocity: pVel,
                                        playing: playing, auditionSuppressing: !noteMonitorPassthrough)
        if mask != 0, let out = midiOut {
            let n = min(length, 3)
            for i in 0..<n { passthroughScratch[i] = bytes[i] }
            var m = mask
            while m != 0 {                                  // forward on each cable in the mask (0 = All, 1 = Emit Riff A)
                let cable = UInt8(m.trailingZeroBitCount); m &= m - 1
                _ = out(sampleTime, cable, n, &passthroughScratch)
            }
        }
    }

    // §item 11 INPUT CABLES — decode one UMP packet (its Channel-Voice messages) into the legacy path.
    // Each packet holds `wordCount` 32-bit UMP words; a message is 1–4 words (umpWordCount by type). We
    // stride word-by-word, converting MIDI-1.0-CV (MT 0x2) and MIDI-2.0-CV (MT 0x4) to legacy bytes with
    // the GROUP mapped to a 1-based cable — identical downstream to a .MIDI event. Other MTs are skipped.
    private func processUMPPacket(_ pkt: UnsafePointer<MIDIEventPacket>, sampleTime: AUEventSampleTime, playing: Bool) {
        let count = Int(pkt.pointee.wordCount)
        guard count > 0 else { return }
        withUnsafeBytes(of: pkt.pointee.words) { raw in
            let words = raw.bindMemory(to: UInt32.self)   // 64-word fixed tuple; count bounds the valid ones
            var i = 0
            while i < count && i < words.count {
                let w0 = words[i]
                let size = umpWordCount(mt: Int((w0 >> 28) & 0xF))
                let w1: UInt32 = (i + 1 < count && i + 1 < words.count) ? words[i + 1] : 0
                if let m = umpToLegacy(w0, w1) {
                    umpScratch[0] = m.b0; umpScratch[1] = m.b1; umpScratch[2] = m.b2
                    umpScratch.withUnsafeBufferPointer {
                        handleIncoming(bytes: $0, length: m.len, sampleTime: sampleTime,
                                       playing: playing, cable: m.group + 1)
                    }
                }
                i += size
            }
        }
    }
}
