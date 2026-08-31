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

    // AUDITION (§6.4 / delta §5): the held cell (col*rows+row, −1 = none), set from the UI thread and
    // read on the render thread. Plain Int32 — a single aligned word, main-writes / render-reads, same
    // cross-thread pattern as `midiOut`; ephemeral, never persisted. `setAudition` is the only writer.
    private var auditionTarget: Int32 = -1
    private var suppressAuditionNotes = false     // this render: audition replaces raw note passthrough
    func setAudition(_ target: Int) { auditionTarget = Int32(target) }
    // (The reference-chord fallback was REMOVED 2026-08-23, Paul: a synthetic chord must never be part of the user experience.)

    // PREVIEW / cell audition (Phase 2): the staged VIRTUAL cell, set from the UI while PREVIEW is held.
    // Ephemeral, never persisted. colourIndex −1 = inactive. Row −1 = receiver input (its channel filter);
    // the Router renders it SOLO. Suppresses raw passthrough (only the virtual cell sounds).
    private var previewActive = false
    private var previewColourIndex: Int32 = -1
    private var previewFilter: Int32 = 0
    private var previewBusMask: UInt8 = 0
    private var previewInputRow: Int32 = -1
    func setPreview(colourIndex: Int, filter: Int, busMask: UInt8, inputRow: Int) {
        previewColourIndex = Int32(colourIndex); previewFilter = Int32(filter)
        previewBusMask = busMask; previewInputRow = Int32(inputRow); previewActive = colourIndex >= 0 && busMask != 0
    }
    func clearPreview() { previewActive = false; previewColourIndex = -1; previewBusMask = 0 }

    // §5b COLUMN-SUBSET LAP: the held column keys (bit i = column i), set from the UI (PERFORM only),
    // read on the render thread. Ephemeral like auditionTarget; the UI clears it on stop / EDIT switch.
    private var laneMask: UInt8 = 0
    func setLaneMask(_ mask: UInt8) { laneMask = mask }
    // EDIT PAGE "play this cell only" (user 2026-08-08): the solo SET (bits col*8+row). While non-empty, only these
    // cells sound. Ephemeral like laneMask; the UI sets it from the edit selection and clears it on OFF / leaving EDIT.
    private var soloCellMask: UInt64 = 0
    func setSoloCellMask(_ mask: UInt64) { soloCellMask = mask }
    private var soloColumn: Int32 = -1   // PLAY: THIS CELL — the column to freeze on (−1 = normal timeline)
    func setSoloColumn(_ c: Int) { soloColumn = Int32(c) }
    // §9 item 1 ON HOLD: the grid cell (col*8+row, −1 = none) currently press-held in PERFORM. Ephemeral like
    // laneMask; the UI sets it while a cell is held and clears it on release / stop / EDIT switch.
    private var heldCell: Int32 = -1
    func setHoldCell(_ cell: Int) { heldCell = Int32(cell) }
    // §9 item 1 ON TAP (unified ALT model): ephemeral per-cell ALT flips (bit col*8+row). Set by the PERFORM
    // tap; cleared on transport stop / mode switch. Never persisted — a tap is momentary now, not a doc write.
    private var tapAltMask: UInt64 = 0
    func setTapAltMask(_ mask: UInt64) { tapAltMask = mask }
    // §9 item 1 ON TAP actions (4b), ephemeral: per-cell MUTE + the global emitter SOLO set (bits A–D).
    private var tapMuteMask: UInt64 = 0
    private var soloEmitterMask: UInt8 = 0
    func setTapMuteMask(_ mask: UInt64) { tapMuteMask = mask }
    func setSoloEmitterMask(_ mask: UInt8) { soloEmitterMask = mask }
    // receiver strip: the additive input SOLO set (bits R1–R4), ephemeral. Cleared by the UI on stop / EDIT.
    private var soloReceiverMask: UInt8 = 0
    func setSoloReceiverMask(_ mask: UInt8) { soloReceiverMask = mask }
    // Splice one byte into `lane` (0–3) of a packed UInt32 strip, leaving the other three lanes intact.
    // The clamp/bit-pattern of the byte stays at each call site; this is only the mask-and-splice.
    private static func packLane(_ packed: UInt32, _ lane: Int, _ byte: UInt8) -> UInt32 {
        let shift = UInt32(lane) * 8
        return (packed & ~(0xFF << shift)) | (UInt32(byte) << shift)
    }
    // receiver strip: per-receiver ±octave nudge (−3…+3), packed one signed byte each. Ephemeral (weather).
    private var inputOctave: UInt32 = 0
    func setInputOctave(_ recv: Int, _ oct: Int) {
        guard recv >= 0 && recv < 4 else { return }
        let byte = UInt8(bitPattern: Int8(max(-3, min(3, oct))))
        inputOctave = Kernel.packLane(inputOctave, recv, byte)
    }
    // receiver strip: per-receiver ±semitone NOTE nudge (−12…+12), packed one signed byte each. Composes with octave.
    private var inputSemitone: UInt32 = 0
    func setInputSemitone(_ recv: Int, _ n: Int) {
        guard recv >= 0 && recv < 4 else { return }
        let byte = UInt8(bitPattern: Int8(max(-12, min(12, n))))
        inputSemitone = Kernel.packLane(inputSemitone, recv, byte)
    }
    // receiver strip: the momentary-absolute INPUT-velocity override (the slider's ride), packed byte per
    // receiver (0 = none, 1–127 = flatten). Ephemeral; the UI springs it back to 0 on slider release.
    private var inputVelOverride: UInt32 = 0
    func setInputVelOverride(_ recv: Int, _ value: Int?) {
        guard recv >= 0 && recv < 4 else { return }
        let byte = UInt8(value.map { max(1, min(127, $0)) } ?? 0)
        inputVelOverride = Kernel.packLane(inputVelOverride, recv, byte)
    }
    // emitter strip: per-emitter output ±octave nudge (−3…+3), packed one signed byte each. Ephemeral (weather).
    private var emitterOctave: UInt32 = 0
    func setEmitterOctave(_ bus: Int, _ oct: Int) {
        guard bus >= 0 && bus < 4 else { return }
        let byte = UInt8(bitPattern: Int8(max(-3, min(3, oct))))
        emitterOctave = Kernel.packLane(emitterOctave, bus, byte)
    }
    // master panel: the momentary master velocity FADER (0 = none, 1–127 = force over all output). Ephemeral;
    // the UI springs it back on release. Plus PANIC — a one-shot all-notes-off + voice flush, hang-kit-logged.
    private var masterVelOverride: UInt8 = 0
    func setMasterVelOverride(_ value: Int?) { masterVelOverride = UInt8(value.map { max(1, min(127, $0)) } ?? 0) }
    private var panicRequested = false
    func panic() { panicRequested = true }
    // MULTI-SCENE: a clean one-shot voice flush on a scene SWITCH — closes the old scene's sounding notes so
    // the new scene starts clean (a generation change alone doesn't flush). Distinct from panic (not hang-logged).
    private var flushRequested = false
    func flushVoices() { flushRequested = true }
    // MULTI-SCENE S2b: RESTART-the-pass — re-anchor the playing clock so the current moment becomes column 0.
    private var restartRequested = false
    func restartPass() { restartRequested = true }
    // receiver strip LATCH (chord-hold): 4 FROZEN input pools + the armed mask. Each render, an armed
    // receiver captures the live filtered chord while fingers are down and FREEZES it when they lift (a NEW
    // chord replaces automatically — fingers-down re-captures); a fresh arm starts empty. The frozen pools
    // survive snapshot rebuilds (ephemeral kernel state), so a MUTE silences but does not clear them.
    // omniRead = true: the FROZEN pools (LATCH/REPLAY/FILE) are door-filtered at capture, so the grid cells read them
    // WHOLE — a later channel/range edit can't drop the frozen notes (the "replay stops when I disable the input
    // channel" bug, Paul 2026-08-23). See NotePool.omniRead.
    private let latchedPools: [NotePool] = (0..<4).map { _ in let p = NotePool(); p.omniRead = true; return p }
    private var latchArmMask: UInt8 = 0
    private var prevLatchArmMask: UInt8 = 0
    // PIANO LATCH is SELF-ARMING: a door in PIANO mode with picked notes latches WITHOUT the separate LATCH lock —
    // the on-screen notes ARE the pool (there's no live chord to capture, so nothing to "arm"). `effectiveLatchMask`
    // = the lock's `latchArmMask` OR'd with every PIANO door that has notes; it is what the Router + metering + the
    // latched-pool fill all read, so the frozen chord feeds the grid (and BYPASS) the moment notes are chosen.
    private var effectiveLatchMask: UInt8 = 0
    // REPLAY (config-sheets stage 3, Paul 2026-08-20): each door has an input RING that records its live notes always
    // (retro-capture); in REPLAY mode the last N passes loop back as the door's LIVING INPUT (it self-arms like PIANO,
    // its cells read the looped pool, live input flows only into the ring). Empty replayMask ⇒ zero effect (byte-
    // identical for every existing doc). ⚠ DEVICE EAR OWED — the audible loop can't be verified off-device.
    private let doorRings = [DoorRing(), DoorRing(), DoorRing(), DoorRing()]
    private var replayMask: UInt8 = 0
    private var replayPasses = [UInt8](repeating: 1, count: 4)
    // MANUAL CATCH (Paul 2026-08-20): a REPLAY door records continuously but only LOOPS after the user presses "LAST N"
    // — that captures the last N passes as a fixed loop and ENGAGES it (press again = release, back to live input).
    private var replayEngagedMask: UInt8 = 0        // which REPLAY doors are actively looping (ephemeral)
    // FILE (config-sheets stage 4): doors playing a loaded .mid clip. The clip arrives in the box (race-safe); on a
    // generation change it's loaded into the door's ring, then plays like an always-engaged loop (phase = beat mod len).
    private var fileMask: UInt8 = 0
    private var fileClipGen: UInt64 = .max          // the box generation whose FILE clips are loaded into the rings
    private var replayAnchor = [Double](repeating: 0, count: 4)   // the beat each loop was captured at → phase = (beat − anchor) mod loopLen
    private var replayCatchToggle: UInt8 = 0        // UI request: toggle door i's catch this render (bit i)
    func toggleReplayCatch(_ i: Int) { if i >= 0 && i < 4 { replayCatchToggle |= UInt8(1 << i) } }
    func replayEngaged() -> UInt8 { replayEngagedMask }
    func latchArm() -> UInt8 { latchArmMask }   // the live explicit-arm mask, so the UI can RE-DERIVE it (survives a view rebuild) — Paul 2026-08-27
    // The engaged loop's ANCHOR beat (a pass boundary) — the config roll extrapolates the playhead phase = (beat − anchor)
    // mod loopLen from it, so the sweeping cursor stays in sync with playback between the 4 Hz polls (Paul 2026-08-26).
    func replayLoopAnchor(door i: Int) -> Double { (i >= 0 && i < 4) ? replayAnchor[i] : 0 }
    private var renderBeatPos = 0.0                 // this render's beat — read by updateLatchedPools for the REPLAY phase
    private var renderWindowBeats = 0.0             // this render block's beat span — the REPLAY look-ahead (block-latency compensation)
    private var prevRenderBeatPos = 0.0             // last render's beat — to spot a transport stop→start / seek / loop discontinuity
    private var prevRenderPlaying = false           // …so the DoorRing history can be cleared before it goes non-monotone
    // FREE-RUN CLOCK (Paul 2026-08-25): when the HOST transport is STOPPED and an effective note is held, the plugin runs
    // its OWN beat so the published scene plays (note-triggered play). Enabled by the UI; a persistent accumulator like the
    // note tracker (a transport is inherently accumulated — the host's beatPos is too). Never advances while the host plays.
    private var freeRunEnabled = false
    private var freeRunActive = false
    private var freeRunBeat = 0.0
    func setFreeRunEnabled(_ b: Bool) { freeRunEnabled = b }   // main-thread bool write; a torn read is benign (one late block)
    private var recordBeatBase = 0.0, recordBps = 0.0, recordWinStart: Int64 = 0   // beat mapping for handleIncoming's ring recording
    private var recordPlaying = false
    // Buffers for the REPLAY pool fill (fixed, no render-path alloc).
    private var replayNoteBuf = [UInt8](repeating: 0, count: 128)
    private var replayVelBuf = [UInt8](repeating: 0, count: 128)
    private var replayChanBuf = [UInt8](repeating: 0, count: 128)   // the loop's per-note ORIGINAL channel (channel-preserving replay)
    // REPLAY: record an incoming note into every REPLAY door that HEARS it (cable + channel + range), timestamped at the
    // event's beat. Only while PLAYING (the loop is beat-locked; a stopped instrument has no meaningful beat window).
    private func recordReplay(note: UInt8, vel: UInt8, on: Bool, sampleTime: AUEventSampleTime, channel: UInt8, cable: Int) {
        guard recordPlaying, replayMask != 0 else { return }
        let beat = recordBeatBase + Double(Int64(sampleTime) - recordWinStart) * recordBps
        for i in 0..<4 where (replayMask & (1 << UInt8(i))) != 0
                          && receiverHearsCable(mask: Int(receiverCables[i]), eventCable: cable)
                          && receiverHearsMask(receiverChanMask[i], channel: channel)
                          && (!on || (note >= receiverRangeLo[i] && note <= receiverRangeHi[i])) {   // range gates onsets; offs always record (pair cleanly)
            doorRings[i].record(beat: beat, note: note, vel: vel, on: on, chan: channel)   // preserve the incoming channel → replay re-emits it (channel-filtered cells admit the loop)
        }
    }
    // REPLAY: at each N-pass boundary, capture the last N passes as the door's loop (retro — never armed). N·cycleBeats
    // is a multiple of the boundary here, so playback phase = beatPos mod loopLen aligns. Runs from the reel section
    // (where the pass index is computed). Needs ≥ N passes of history before the first capture.
    // MANUAL CATCH: consume the UI's "LAST N" toggle requests. Press → capture the last N passes NOW (anchored at this
    // beat so the loop plays from its start) + ENGAGE looping; press again → release (clear the loop, back to live input).
    private func processReplayCatch(cycleBeats: Double, beatPos: Double) {
        guard replayCatchToggle != 0 else { return }
        for i in 0..<4 where (replayCatchToggle & (1 << UInt8(i))) != 0 {
            let bit = UInt8(1 << i)
            if replayEngagedMask & bit != 0 {                      // engaged → release
                doorRings[i].clearLoop(); replayEngagedMask &= ~bit
            } else if cycleBeats > 0 {                             // not engaged → capture the last N COMPLETED passes + engage
                let n = Int(replayPasses[i] == 0 ? 1 : replayPasses[i])
                // ALIGN to the last pass BOUNDARY, not the arbitrary press beat: capture [boundary − M·cyc, boundary]
                // and anchor there, so the loop's pass boundaries land on the grid's — a mid-pass press no longer leaves
                // the loop permanently phase-offset (the "looping not synced" bug, Paul 2026-08-23).
                let boundary = (beatPos / cycleBeats).rounded(.down) * cycleBeats
                // CLAMP to the passes actually recorded so a press with < N passes of history doesn't prepend silent
                // passes (which reads as an offset). M = min(N, whole passes since the oldest recorded event).
                let oldest = doorRings[i].oldestBeat
                let avail = oldest.isFinite ? max(1, Int(((boundary - oldest) / cycleBeats).rounded(.down))) : n
                let m = max(1, min(n, avail))
                doorRings[i].capture(endBeat: boundary, lengthBeats: Double(m) * cycleBeats)
                if doorRings[i].loopN > 0 {                         // only engage if something was actually captured (guards an empty/invalid-beat window)
                    replayAnchor[i] = boundary; replayEngagedMask |= bit
                }
            }
        }
        replayCatchToggle = 0
        effectiveLatchMask = computeEffectiveLatchMask()           // re-fold: a newly-engaged door self-arms this render
    }

    private func computeEffectiveLatchMask() -> UInt8 {
        var m = latchArmMask
        for i in 0..<4 where (pianoMask & (1 << UInt8(i))) != 0 && i < pianoNotes.count && !pianoNotes[i].isEmpty {
            m |= UInt8(1 << i)
        }
        for i in 0..<4 where (replayEngagedMask & (1 << UInt8(i))) != 0 && doorRings[i].hasLoop {   // REPLAY: only an ENGAGED door (LAST N pressed) loops → its cells read the loop
            m |= UInt8(1 << i)
        }
        for i in 0..<4 where (fileMask & (1 << UInt8(i))) != 0 && doorRings[i].hasLoop {   // FILE: a loaded clip plays always → self-arms
            m |= UInt8(1 << i)
        }
        return m
    }
    // TWO LATCH MODES: per-receiver ADD flag (from the box) + preallocated rising-edge state (ADD only).
    private var latchAddMask: UInt8 = 0
    private var latchPrevHeld = [[Bool]](repeating: [Bool](repeating: false, count: 128), count: 4)
    // HOLD (chord) mode (Paul 2026-08-31, rewrite): a NEW chord REPLACES the frozen pool, a still-forming chord UNIONS. The
    // "new chord" signal is NOT silence (which a sustained note / restrike breaks) but the held set GROWING right after a
    // RELEASE: notes-released → arm a replace · next growth → replace with the current live set · further growth in the same
    // gesture → union (staggered onset). A whole-chord restrike (release→regrow) replaces with the SAME chord = no drop.
    private var holdLiveLo = [UInt64](repeating: 0, count: 4)          // previous live NOTE SET per door (lo = notes 0…63)
    private var holdLiveHi = [UInt64](repeating: 0, count: 4)          // (hi = notes 64…127) — compared by IDENTITY so a same-size swap is caught
    private var holdReleasing = [Bool](repeating: true, count: 4)      // a release happened since the last capture → the next ADD is a NEW chord (true at arm so the first press replaces)
    func setLatchArm(_ mask: UInt8) { latchArmMask = mask }
    private func updateLatchedPools() {
        guard effectiveLatchMask != 0 || prevLatchArmMask != 0 else { return }   // fast path: nothing armed (incl. PIANO) now or before
        pool.rebuildSorted()                       // the live pool's ascending view (process rebuilds again; idempotent)
        for i in 0..<4 {
            let bit = UInt8(1 << i)
            let isArmed = effectiveLatchMask & bit != 0, wasArmed = prevLatchArmMask & bit != 0
            if isArmed && !wasArmed {
                latchedPools[i].reset()                                   // fresh arm → start empty (no stale chord)
                for n in 0..<128 { latchPrevHeld[i][n] = false }          // ...and clear the ADD edge state
                holdReleasing[i] = true; holdLiveLo[i] = 0; holdLiveHi[i] = 0   // ...and the HOLD gesture edge (first press after arm REPLACES)
            }
            guard isArmed else { continue }
            if (replayMask & bit != 0 && replayEngagedMask & bit != 0) || (fileMask & bit != 0) {
                // REPLAY (engaged) / FILE: the frozen pool = the loop SOUNDING at the current phase. REPLAY was captured
                // at replayAnchor[i] (phase = beat − anchor); a FILE clip plays from beat 0 (anchor 0). Re-based to
                // [0, loopLen). Refresh each render (pure f(beat) → replay-safe). STAMP the door's wire channel.
                let ring = doorRings[i]
                let isFile = fileMask & bit != 0
                latchedPools[i].reset()
                if ring.loopLen <= 0 { mergeLiveIntoLatched(i); continue }   // empty loop → still pass LIVE (Paul 2026-08-23)
                let anchor = isFile ? 0.0 : replayAnchor[i]
                // BLOCK-LATENCY COMPENSATION (Paul 2026-08-22): sample the loop at this block's END, not its start —
                // live input notes are added mid-block (handleIncoming) and so are present for their whole arrival
                // block; a block-start phase makes a loop onset appear one block LATE (the "constant amount out of
                // time"). The look-ahead of one block span aligns replay onset-granularity to live input.
                var phase = (renderBeatPos + renderWindowBeats - anchor).truncatingRemainder(dividingBy: ring.loopLen)
                if phase < 0 { phase += ring.loopLen }
                let cnt = ring.notesSoundingAt(phase, outNote: &replayNoteBuf, outVel: &replayVelBuf, outChan: &replayChanBuf)
                // CHANNEL-PRESERVING REPLAY (Paul 2026-08-22): re-emit each note on its ORIGINAL incoming channel — so a
                // channel-filtered cell admits the loop exactly as it did the live input (the "channel 3 → silent" bug).
                // FILE stamps the door's wire channel (a .mid clip carries no meaningful door channel).
                let fileStamp: UInt8 = (receiverChannels[i] >= 1 && receiverChannels[i] <= 16) ? receiverChannels[i] - 1 : 0
                for k in 0..<cnt { latchedPools[i].noteOn(replayNoteBuf[k], velocity: replayVelBuf[k], channel: isFile ? fileStamp : replayChanBuf[k]) }
                mergeLiveIntoLatched(i)   // REPLAY/FILE: LIVE input on the door's enabled channels plays ALONGSIDE the loop/clip (Paul 2026-08-23); also rebuilds sorted
                continue
            }
            if pianoMask & bit != 0 {
                // PIANO LATCH (2026-08-10): the frozen pool is the on-screen keyboard selection — not live input.
                // Refresh each render (static + cheap) so edits on the keyboard take effect immediately. Self-arming
                // via effectiveLatchMask (no lock needed). STAMP the receiver's own wire channel so a non-OMNI cell
                // reading this door still admits the notes (matches captureFiltered's channel-preserving behaviour).
                let stampCh: UInt8 = (receiverChannels[i] >= 1 && receiverChannels[i] <= 16) ? receiverChannels[i] - 1 : 0
                latchedPools[i].reset()
                for n in (i < pianoNotes.count ? pianoNotes[i] : []) { latchedPools[i].noteOn(n, velocity: 100, channel: stampCh) }   // KEYS/SCALE derived pool
                mergeLiveIntoLatched(i)   // KEYS/SCALE: play ALONG live — the door's enabled channels feed the grid on top of the picked pool (Paul 2026-08-23)
                // The KEY FILTER (EXCLUDE/ONLY + BLOCK/SNAP) is applied UNIFORMLY in pass 2 below — it references door B's
                // RESOLVED pool, which needs every door built first (so a SCALE key-door reads correctly, not empty-live).
                continue
            }
            let rLo = receiverRangeLo[i], rHi = receiverRangeHi[i]   // RANGE (§2): the latch admits only in-window notes
            if latchAddMask & bit != 0 {
                // KEYS (was ADD): note-toggle accumulation — each new note-on flips its membership in the frozen pool.
                latchedPools[i].latchAddStep(from: pool, chanMask: receiverChanMask[i], cableMask: Int(receiverCables[i]),
                                             noteLo: rLo, noteHi: rHi, prevHeld: &latchPrevHeld[i])
            } else {
                // HOLD (CHORD) — by NOTE IDENTITY (Paul 2026-08-31, count was too coarse): compare the live NOTE SET to last
                // render. A RELEASE (a note went off) arms "the next new note is a new chord". An ADD right after a release
                // (incl. the SAME render, e.g. a fast swap or a within-block release+restrike where the count is unchanged) →
                // REPLACE the frozen pool with the current live set. An ADD with no release (still forming) → UNION (staggered
                // chord builds up; "press three, only two hold"). A pure release keeps the frozen set. A note-for-note restrike
                // of the SAME chord (no net add/remove) → nothing → held chord survives.
                let (clo, chi) = pool.admittedMask(chanMask: receiverChanMask[i], cableMask: Int(receiverCables[i]), noteLo: rLo, noteHi: rHi)
                let hasRemoved = (holdLiveLo[i] & ~clo) != 0 || (holdLiveHi[i] & ~chi) != 0   // a held note went off
                let hasAdded   = (clo & ~holdLiveLo[i]) != 0 || (chi & ~holdLiveHi[i]) != 0   // a new note came on
                if hasRemoved { holdReleasing[i] = true }
                if hasAdded {
                    if holdReleasing[i] {                               // a new note AFTER a release → a NEW chord → REPLACE
                        latchedPools[i].captureFiltered(from: pool, chanMask: receiverChanMask[i], cableMask: Int(receiverCables[i]),
                                                        noteLo: rLo, noteHi: rHi)
                        holdReleasing[i] = false
                    } else {                                            // still forming the same chord → UNION (never shrink)
                        latchedPools[i].mergeFiltered(from: pool, chanMask: receiverChanMask[i], cableMask: Int(receiverCables[i]),
                                                      noteLo: rLo, noteHi: rHi)
                    }
                }
                holdLiveLo[i] = clo; holdLiveHi[i] = chi
            }
        }
        // ---- PASS 2: THE KEY FILTER (ratified §3) — every armed door's pool is filtered by a reference door's PITCH CLASSES
        //      (MINUS = subtract / the complement · ONLY = intersect / in-key), out-of-set notes BLOCKed or SNAPped to the
        //      nearest legal note. Runs AFTER pass 1 so the reference reads door B's RESOLVED pool (a SCALE key-door's
        //      derived set, a latched chord, etc.), not just B's live input. nil/-1 reference ⇒ no filter (byte-identical).
        for i in 0..<4 where (effectiveLatchMask & UInt8(1 << i)) != 0 {
            let ex = Int(receiverExcludeDoor[i])
            guard ex >= 0 && ex < 4 else { continue }
            let refMask = keyReferenceMask(door: ex)
            applyKeyFilter(door: i, refMask: refMask,
                           only: (receiverExcludeOnly & UInt8(1 << i)) != 0,
                           snap: (receiverExcludeSnap & UInt8(1 << i)) != 0)
        }
        prevLatchArmMask = effectiveLatchMask
    }
    /// The reference PITCH-CLASS set of door `ex` for the key filter: its RESOLVED pool — the frozen/derived pool if the
    /// door is armed (SCALE/KEYS/latched chord/replay/file), else its LIVE input filtered by the door's channel+range.
    /// §4 DYNAMIC REFERENCE + CARRY PIN: a live-played reference (THRU/unlatched B) tracks the CURRENT chord — so A is
    /// chord-locked, re-deriving live. When B falls momentarily silent (lifting to re-voice), the reference PERSISTS
    /// (the PEDAL law — the left hand's lift must not mute the right), refreshing on B's next material. A never-yet-played
    /// reference stays empty (ONLY ⇒ silence, the intended tell). Reset on the transport start edge (a fresh take).
    private func keyReferenceMask(door ex: Int) -> UInt16 {
        let frozen = latchedPools[ex].pitchClassMaskAll()                                              // a built frozen/derived pool
        let live = frozen != 0 ? frozen : pool.pitchClassMask(chanMask: receiverChanMask[ex], cableMask: Int(receiverCables[ex]),
                                                              noteLo: receiverRangeLo[ex], noteHi: receiverRangeHi[ex])
        if live != 0 { lastReferenceMask[ex] = live; return live }                                     // new material → refresh + use
        return lastReferenceMask[ex]                                                                   // momentary silence → hold the last set (0 if B never played)
    }
    /// Apply the key filter to door `i`'s frozen pool IN PLACE (no allocation — fixed scratch): each note is kept, dropped
    /// (BLOCK / out of set), or remapped (SNAP → nearest legal note). Remapped notes keep their velocity/channel/cable; a
    /// collision (two notes snapping to one target) folds via noteOn's note-indexing. Closes then re-adds so no note is
    /// visited twice. rebuildSorted() at the end (the pool's ascending view is read downstream).
    private func applyKeyFilter(door i: Int, refMask: UInt16, only: Bool, snap: Bool) {
        var changes = 0                                            // notes that must move (drop or remap)
        let p = latchedPools[i]
        for k in 0..<p.count {
            let note = Int(p.sorted[k])
            let result = keyFilterNote(note, refMask: refMask, only: only, snap: snap)
            if result == note { continue }                        // kept as-is
            let nn = UInt8(note)
            keyFilterNoteBuf[changes] = nn
            keyFilterToBuf[changes] = result == nil ? 255 : UInt8(result!)   // 255 = DROP (out of MIDI range → a safe sentinel); else the SNAP target
            keyFilterVelBuf[changes] = p.heldVelocity(nn)
            keyFilterChanBuf[changes] = p.heldChannel(nn)
            keyFilterCblBuf[changes] = p.heldCable(nn)
            changes += 1
        }
        guard changes > 0 else { return }
        for k in 0..<changes { latchedPools[i].noteOff(keyFilterNoteBuf[k]) }                          // close originals first (no double-visit)
        for k in 0..<changes where keyFilterToBuf[k] != 255 {                                          // re-add remapped survivors (SNAP)
            latchedPools[i].noteOn(keyFilterToBuf[k], velocity: keyFilterVelBuf[k], channel: keyFilterChanBuf[k], cable: keyFilterCblBuf[k])
        }
        latchedPools[i].rebuildSorted()
    }

    /// KEYS/REPLAY/FILE only (Paul 2026-08-23): merge the door's LIVE input — on its enabled channels (OMNI or the
    /// chosen subset), cable, and range — INTO the frozen pool, so you can play ALONG with the keyboard pick / loop /
    /// clip. Channel-preserving; derived each render (a released live note simply isn't re-merged next render → the
    /// grid's hold reconcile closes it, so no stuck notes). LATCH/HOLD do NOT call this — they ARE the captured chord.
    private func mergeLiveIntoLatched(_ i: Int) {
        latchedPools[i].mergeFiltered(from: pool, chanMask: receiverChanMask[i], cableMask: Int(receiverCables[i]),
                                      noteLo: receiverRangeLo[i], noteHi: receiverRangeHi[i])
    }

    // §6a PERFORM velocity override: per-emitter forced velocity, packed byte-per-emitter (0 = none,
    // 1–127 = flatten new note-ons on that bus). Ephemeral like laneMask; the UI springs it back to 0
    // on slider release. Single main-thread writer + render read of an aligned UInt32 = race-safe.
    private var velOverride: UInt32 = 0

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
    // a8 assert-on-silence dump/trap: os_log surfaces the corpse in every build; DEBUG additionally traps
    // (dump-before-trap, design side 2026-07-25). Flip `hardTrapOnStuckNote` to keep testing THROUGH a
    // stuck note in a debug build (it still logs + self-heals). RELEASE never traps — never crash a gig.
    private static let hangLog = OSLog(subsystem: "com.paulbarrett.MidiSpark", category: "hang")
    #if DEBUG
    private static let hardTrapOnStuckNote = true
    #endif
    // §a8b PLAYING hung-note net: samples the LIVE input has been continuously empty while playing (no armed
    // latch, no audition). The debounce clock for `playingSilenceLeak`; reset to 0 the moment input returns.
    private var emptyInputSamples: Int64 = 0
    func setVelOverride(_ bus: Int, _ value: Int?) {
        guard bus >= 0 && bus < 4 else { return }
        let byte = UInt8(value.map { max(1, min(127, $0)) } ?? 0)
        velOverride = Kernel.packLane(velOverride, bus, byte)
    }
    // §4b THE FADER-KILL — a velocity fader dragged to its BOTTOM silences that emitter entirely (momentary,
    // ephemeral). Race-safe: single main-thread writer, render reads an aligned byte/bool.
    private var velKillMask: UInt8 = 0
    private var masterKill = false
    func setEmitterVelKill(_ bus: Int, _ kill: Bool) {
        guard bus >= 0 && bus < 4 else { return }
        if kill { velKillMask |= UInt8(1) << UInt8(bus) } else { velKillMask &= ~(UInt8(1) << UInt8(bus)) }
    }
    func setMasterKill(_ on: Bool) { masterKill = on }

    // §6a metering: read-and-clear per-emitter peak velocity + event count since the last call (UI poll).
    func drainEmitterActivity() -> (peak: [UInt8], events: [UInt32]) { router.drainMeters() }
    func drainEmitterMarks() -> [[(vel: UInt8, col: Int8)]] { router.drainMarks() }   // item 4 velocity marks
    func drainWithheldMarks() -> [[(vel: UInt8, col: Int8)]] { router.drainWithheld() }   // §6a the withheld tell
    func drainEmitterSounding() -> [[(vel: UInt8, col: Int8)]] { router.drainEmitterSounding() }   // §strips-done: hold-while-sounding
    func drainCellStrikes() -> [UInt8] { router.drainCellStrikes() }   // SEAL comet: per-cell peak strike velocity
    func drainCellNotes() -> (pitch: [UInt8], vel: [UInt8], count: [UInt8]) { router.drainCellNotes() }   // NOTE-SWEEP: per-cell recent note-ons
    func pollCellSounding() -> (lo: UInt64, hi: UInt64) { router.currentCellSounding() }  // SEAL comet: per-cell sounding gate (128 cells: lo=0…63, hi=64…127)

    // delta §9 item 11: INPUT metering — per-receiver peak velocity + event count since the last poll (the
    // input twin of §6a). `receiverChannels` is this render's filters (0 = OMNI, 1–16), set from the box.
    private var receiverChannels: [UInt8] = [0, 0, 0, 0]
    private var receiverChanMask: [UInt16] = [0xFFFF, 0xFFFF, 0xFFFF, 0xFFFF]   // MULTI-CHANNEL: this render's per-door channel subset (for metering + latch capture)
    private var receiverCables: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111]   // §item 11: cable bitmasks (for metering)
    private var receiverRangeLo: [UInt8] = [0, 0, 0, 0]                       // RANGE (§2): note window for the latch capture (upstream of latch)
    private var receiverRangeHi: [UInt8] = [127, 127, 127, 127]
    private var receiverControllerMask: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111]   // CONTROLLER ROUTING (v1): per-door emitter forward mask
    private var busChannels: [UInt8] = [1, 2, 3, 4]                           // CONTROLLER ROUTING (v1): per-emitter stamp channels (for the re-stamp forward)
    private var pianoMask: UInt8 = 0                                          // PIANO LATCH: doors whose frozen pool is the on-screen keyboard
    private var pianoNotes: [[UInt8]] = [[], [], [], []]                      // PIANO LATCH: per-door chosen notes
    private var receiverExcludeDoor: [Int8] = [-1, -1, -1, -1]                // KEY FILTER: per door, the reference door whose pitch classes filter its pool (-1 = OFF)
    private var receiverExcludeOnly: UInt8 = 0                                // KEY FILTER §3: bit i = door i INTERSECTS (ONLY) vs subtracts (MINUS) the reference
    private var receiverExcludeSnap: UInt8 = 0                                // KEY FILTER §3: bit i = door i SNAPS out-of-set notes vs BLOCKs them
    private var lastReferenceMask = [UInt16](repeating: 0, count: 4)          // KEY FILTER §4 CARRY PIN: per reference door, its last NON-EMPTY pitch-class set — persists across the door's silences (the PEDAL law), refreshing on its next material
    private var keyFilterNoteBuf = [UInt8](repeating: 0, count: 128)          // §3 no-alloc scratch: notes to close then re-add (remap) when applying the key filter
    private var keyFilterToBuf = [UInt8](repeating: 0, count: 128)
    private var keyFilterVelBuf = [UInt8](repeating: 0, count: 128)
    private var keyFilterChanBuf = [UInt8](repeating: 0, count: 128)
    private var keyFilterCblBuf = [UInt8](repeating: 0, count: 128)
    private var thruReceiver: Int = 0        // receiver strip: which receiver the passthrough gate follows (the THRU pip)
    // NOTE MONITOR (Paul 2026-08-29): raw held notes are NOT echoed to the output — a CELL is the sole note source, so a
    // fresh instance (nothing selected) is SILENT. Default OFF; kept as a flag so a soundcheck toggle can re-enable it.
    private let noteMonitorPassthrough = false
    private var inputPeak = [UInt8](repeating: 0, count: 4)
    private var inputEvents = [UInt32](repeating: 0, count: 4)
    private var inputChannelMask = [UInt16](repeating: 0, count: 4)   // §MPE: channels (bit = ch-1) a receiver heard this window
    func drainReceiverActivity() -> (peak: [UInt8], events: [UInt32], channels: [UInt16]) {
        // FRESH copies — never capture the render-written buffers (COW-on-render + refcount race = the poll crash class).
        var peak = [UInt8](repeating: 0, count: 4), events = [UInt32](repeating: 0, count: 4), channels = [UInt16](repeating: 0, count: 4)
        for i in 0..<4 { peak[i] = inputPeak[i]; inputPeak[i] = 0; events[i] = inputEvents[i]; inputEvents[i] = 0; channels[i] = inputChannelMask[i]; inputChannelMask[i] = 0 }
        return (peak, events, channels)
    }
    // SOUNDING SNAPSHOT (duration): per receiver, the velocities of the notes CURRENTLY HELD in the pool that
    // pass its filter. Refreshed each render into a fixed buffer (display-only, best-effort like the meters);
    // the UI reads it so a held-chord line/mark shows WHILE the chord is down and vanishes on release. A muted
    // receiver (filter ≥ 17) matches nothing → empty, as it should.
    // FLATTENED to 4×12 VALUE arrays (index i*12+k) — NOT nested [[UInt8]] (Paul 2026-08-24, code-review CR-1). A nested
    // array's per-element render write (`recvHeldVel[i][k] = v`) churns the INNER buffer's refcount while the ~4Hz poll
    // reads that same inner slot → the documented SIGTRAP freelist-corruption race. A flat value array has no inner-array
    // ARC, so the only residual race is a benign torn value (a stale meter byte). Mirrors the Router's flat feeds.
    private var recvHeldVel = [UInt8](repeating: 0, count: 4 * 12)
    private var recvHeldNote = [UInt8](repeating: 0, count: 4 * 12)   // parallel PITCHES (config-sheets REPLAY roll, Paul 2026-08-20)
    private var recvHeldCount = [Int](repeating: 0, count: 4)
    private var hearingScratch = [Bool](repeating: false, count: 4)   // CR-16: reused so handleIncoming's controller-forward doesn't heap-allocate a [Bool] per event (invariant 3)
    // the header DOT: bit i = a LIVE (never latch) accepted note held on receiver i. A SCALAR mask, published in one
    // store — NOT a shared array. (A [Bool] returned by reference and retained by the UI kept the Kernel's buffer
    // persistently shared, so the render thread's per-element write triggered copy-on-write + a refcount race →
    // EXC_BAD_ACCESS in _swift_release_dealloc on the poll's next @State assignment. The mask can't corrupt a buffer.)
    private var recvLiveHeldMask: UInt8 = 0
    // ⚠ COPY ELEMENT-BY-ELEMENT, NEVER `Array(recvHeldVel[range])` (device SIGTRAP 2026-08-24). A slice/`Array(slice)` HOLDS
    // a strong reference to the render buffer for the whole copy → the buffer becomes SHARED → the render thread's next
    // `recvHeldVel[i]=…` write triggers copy-on-write, which frees the buffer the main thread is still copying from →
    // swift_unknownObjectRelease use-after-free. A per-element subscript READ never retains the buffer, so no COW is
    // triggered; a torn byte is benign (a stale meter value).
    func pollReceiverSounding() -> [[UInt8]] {
        var out = [[UInt8]]()
        for i in 0..<4 { let c = min(12, max(0, recvHeldCount[i])); var a = [UInt8](repeating: 0, count: c)
            for k in 0..<c { a[k] = recvHeldVel[i*12 + k] }; out.append(a) }
        return out
    }
    /// The PITCHES currently held per door (a fresh copy — race-safe like pollReceiverSounding). Drives the REPLAY roll.
    func pollReceiverSoundingNotes() -> [[UInt8]] {
        var out = [[UInt8]]()
        for i in 0..<4 { let c = min(12, max(0, recvHeldCount[i])); var a = [UInt8](repeating: 0, count: c)
            for k in 0..<c { a[k] = recvHeldNote[i*12 + k] }; out.append(a) }
        return out
    }
    func pollReceiverLiveHeld() -> UInt8 { recvLiveHeldMask }
    private func updateReceiverSounding() {
        pool.rebuildSorted()
        var liveMask: UInt8 = 0
        for i in 0..<4 {
            // The header DOT lights whenever a LIVE input note that this door ACCEPTS (channel+cable+RANGE) is held —
            // never the latch (the latched pool is frozen, not live). Independent of the meter's latch-aware display.
            if pool.srcCount(chanMask: receiverChanMask[i], cableMask: Int(receiverCables[i]),
                             velLo: 0, velHi: 127, noteLo: receiverRangeLo[i], noteHi: receiverRangeHi[i]) > 0 {
                liveMask |= 1 << UInt8(i)
            }
            recvHeldCount[i] = 0
            // When a receiver is ARMED, the meter shows the notes the LATCH holds (they keep sounding after the keys
            // lift). The latched pool is already receiver-filtered, so read it OMNI; otherwise read the live pool
            // through this receiver's channel subset.
            let armed = effectiveLatchMask & (1 << UInt8(i)) != 0   // incl. self-armed PIANO doors
            let src = armed ? latchedPools[i] : pool
            let chMask: UInt16 = armed ? 0xFFFF : receiverChanMask[i]
            let cable = armed ? 0b1111 : Int(receiverCables[i])
            let n = src.srcCount(chanMask: chMask, cableMask: cable)
            for k in 0..<n where recvHeldCount[i] < 12 {
                let note = src.srcAscending(k, chanMask: chMask, cableMask: cable)
                recvHeldNote[i*12 + recvHeldCount[i]] = note
                recvHeldVel[i*12 + recvHeldCount[i]] = src.velocity(note); recvHeldCount[i] += 1
            }
        }
        recvLiveHeldMask = liveMask   // one scalar publish → the render→main boundary can't corrupt a COW buffer
    }

    private let pool = NotePool()       // the source (§2.5), fed by incoming MIDI
    private let router = Router()       // grid → emission (§2/§7)

    #if DEBUG
    // CHAOS MODE — SIMULATED MIDI (debug-only): the chaos loop enqueues synthetic note bytes from the main thread;
    // render() drains them into the SAME handleIncoming path host MIDI uses, so a soak is self-contained (no
    // controller). The brief lock is a DELIBERATE debug-only exception to the no-locks-on-render invariant — this
    // code is `#if DEBUG`, never shipped.
    private let chaosMIDI = OSAllocatedUnfairLock(initialState: [(UInt8, UInt8, UInt8)]())
    func chaosEnqueue(_ status: UInt8, _ d1: UInt8, _ d2: UInt8) { chaosMIDI.withLock { $0.append((status, d1, d2)) } }
    private func drainChaosMIDI(playing: Bool) {
        let batch = chaosMIDI.withLock { b -> [(UInt8, UInt8, UInt8)] in let c = b; b.removeAll(keepingCapacity: true); return c }
        for (s, d1, d2) in batch {
            var bytes = [s, d1, d2]
            bytes.withUnsafeBufferPointer { handleIncoming(bytes: $0, length: 3, sampleTime: 0, playing: playing, cable: 1) }
        }
    }
    // CHAOS ORACLE — the render side builds a full MIDI-CHAIN DUMP when silence looks SUSPICIOUS (playing + held +
    // routed path, yet nothing sounding), stashed for the main-thread driver to read + log. Built ONCE at the streak
    // threshold (rare) so the string alloc never hits the steady hot path. `chaosActive` gates it to a live session.
    var chaosActive = false
    private var chaosSilentStreak = 0
    private let chaosDump = OSAllocatedUnfairLock(initialState: "")
    func chaosRoutingDump() -> String { chaosDump.withLock { $0 } }
    private func chaosOracleTick(_ box: SnapshotBox, playing: Bool) {
        guard chaosActive else { return }
        let suspicious = playing && pool.count > 0 && diag.distinctSounding == 0 && diag.routedPath
        chaosSilentStreak = suspicious ? chaosSilentStreak + 1 : 0
        if chaosSilentStreak == 12 { let t = buildRoutingText(box); chaosDump.withLock { $0 = t } }   // once, at threshold
    }
    // Why a cell can't route the LIVE pool to an emitter (nil = it CAN → a genuine path). Mirrors effectivePool's
    // gates: a DISABLED door isn't listening, a LATCH-ARMED door reads the FROZEN pool (so the live admission is moot) —
    // in both the cell won't sound from the live held notes. (The door-level BYPASS gate was retired 2026-08-25.)
    private func cellRouteBlock(_ c: SnapCell, _ box: SnapshotBox) -> String? {
        let r = Int(c.resolvedReceiver)
        if r >= 0 {
            let bit = UInt8(1 << r)
            if box.receiverDisabledMask & bit != 0 { return "recv DISABLED (not listening)" }
            if effectiveLatchMask       & bit != 0 { return "recv LATCHED (reads frozen, not live)" }
        }
        if (c.busMask & box.busEnabledMask) == 0 { return "no enabled emitter" }
        if pool.srcCount(for: c) == 0 { return "admits 0" }
        let m = c.proc   // the head machine, gated on THIS pass exactly as the router decides (a closed passgate is silent this pass)
        if cellMode(type: m.type, bypassed: c.slotBypass.first ?? false, passMask: m.passMask, pass: diag.pass) == .silent {
            return "passgate closed this pass (pass%4=\(((diag.pass % 4) + 4) % 4))"
        }
        if m.type == .chance && m.probability <= 0 { return "chance prob 0 (drops all)" }
        return nil
    }
    private func buildRoutingText(_ box: SnapshotBox) -> String {
        func rflags(_ r: Int) -> String {
            let bit = UInt8(1 << r); var f = ""
            if box.receiverDisabledMask & bit != 0 { f += " [DISABLED]" }
            if effectiveLatchMask       & bit != 0 { f += " [LATCHED]" }
            return f
        }
        var l = ["--- MIDI CHAIN @ suspicious silence ---",
                 "playing=\(diag.playing) held=\(pool.count) sounding=\(diag.distinctSounding) routedPath=\(diag.routedPath) playhead=col\(diag.effColumn) pass=\(diag.pass) master[mute=\(box.masterMute) kill=\(masterKill) vel=\(masterVelOverride)] enabledEmitters=0b\(String(box.busEnabledMask, radix: 2))"]
        let n = pool.srcCount(filter: 0)
        l.append("held notes: " + (0..<n).map { String(pool.srcAscending($0, filter: 0)) }.joined(separator: ","))
        for r in 0..<4 { l.append("  R\(r + 1): filter=\(receiverChannels[r]) range=\(receiverRangeLo[r])–\(receiverRangeHi[r])\(rflags(r))") }
        l.append("  roles: claim=0b\(String(box.claimMask, radix: 2)) leak=\(box.claimLeak) duck=0b\(String(box.flattenMask, radix: 2)) alt=0b\(String(box.altMask, radix: 2)) altCount=\(box.altCount)")
        for (i, c) in box.cells.enumerated() where c.colourIndex >= 0 && !c.muted && !c.dormant && c.busMask != 0 {
            let block = cellRouteBlock(c, box), m = c.proc
            let mdesc = "\(m.type)" + (m.type == .passgate ? " pass=0b\(String(m.passMask, radix: 2))" : m.type == .chance ? " prob=\(m.probability)" : "") + (c.procs.count > 1 ? " +chain\(c.procs.count)" : "")
            let here = (i / Snap.rows) == diag.effColumn ? " ◀playhead" : ""
            l.append("  cell \(i / 8),\(i % 8) col=\(c.colourIndex) [\(mdesc)] recv=\(c.resolvedReceiver) admits=\(pool.srcCount(for: c)) buses=0b\(String(c.busMask, radix: 2))" + (block == nil ? "  → PATH" : "  ✗ \(block!)") + here)
        }
        l.append(diag.routedPath ? "VERDICT: a routed path exists → SILENCE IS SUSPICIOUS (a machine may be gating: closed passgate / chance / arp tick — or a real bug)"
                                 : "VERDICT: no routed path → silence is EXPECTED")
        return l.joined(separator: "\n")
    }
    // CHAOS oracle (one cheap scan): a structural "should something sound?" — an occupied, audible cell that routes
    // the LIVE held pool to an enabled emitter (no bypass/disable/latch gate). No such path ⇒ silence is expected.
    private func computeRoutedPath(_ box: SnapshotBox) {
        if box.masterMute || masterKill { diag.routedPath = false; return }   // master mute / fader-kill silences ALL output → expected
        // Only the CURRENT column can sound right now — a routed cell in some OTHER column is not why this instant is
        // silent. Scan effColumn only, gated on this pass, so the verdict tracks what the playhead is actually over.
        let col = min(max(0, diag.effColumn), Snap.cols - 1)
        var path = false
        for row in 0..<Snap.rows {
            let c = box.cells[col * Snap.rows + row]
            if c.colourIndex >= 0 && !c.muted && !c.dormant && c.busMask != 0 && cellRouteBlock(c, box) == nil { path = true; break }
        }
        diag.routedPath = path
    }
    #endif
    private let liveEmitter = LiveMIDIEmitter()   // the AUMIDIOutputEventBlock adapter (emission seam)
    // THE REEL-TO-REEL (Paul 2026-08-18): the deck (record/replay), the recording tap wrapping liveEmitter, and the
    // one-shot toggle from the UI (consumed on the render thread — same cross-thread pattern as panicRequested).
    let reel = ReelDeck()
    private let reelTap = ReelTap()
    private var reelToggle = false
    private var reelExitFlush = false
    private var reelLastPass = Int.min
    private var reelTempoStored = 120.0
    // ROW 8 CC-PUNCH / PC-SEND (Paul 2026-08-24): a UI-queued control message, emitted on the EMITTER WIRES (the app's
    // outputs — how notes route out) each render. SPSC ring: main writes `ctrlTail`, render reads `ctrlHead`; each slot is
    // a UInt32-packed (type<<16)|(d1<<8)|d2 (type 0 = CC, 1 = PC). Aligned UInt32 element reads/writes are atomic on arm64
    // and the buffer is fixed (no ARC churn) → render-safe; a rare torn read only garbles one control byte (never a stuck note).
    private var ctrlRing = [UInt32](repeating: 0, count: 16)
    private var ctrlHead: UInt32 = 0
    private var ctrlTail: UInt32 = 0
    private var ctrlScratch: [UInt8] = [0, 0, 0]
    /// Queue a control message (main thread). type 0 = CC (d1 = cc#, d2 = value) · 1 = PC (d1 = program, d2 = 0).
    func queueControl(type: Int, d1: Int, d2: Int) {
        ctrlRing[Int(ctrlTail & 15)] = (UInt32(max(0, min(1, type))) << 16) | (UInt32(d1 & 0x7F) << 8) | UInt32(d2 & 0x7F)
        ctrlTail &+= 1
    }
    private func drainControl(box: SnapshotBox) {
        guard midiOut != nil else { ctrlHead = ctrlTail; return }
        while ctrlHead != ctrlTail {
            let p = ctrlRing[Int(ctrlHead & 15)]; ctrlHead &+= 1
            let isPC = ((p >> 16) & 0xFF) == 1
            let d1 = UInt8((p >> 8) & 0x7F), d2 = UInt8(p & 0x7F)
            let hi: UInt8 = isPC ? 0xC0 : 0xB0
            for e in 0..<4 where (box.busEnabledMask & (1 << UInt8(e))) != 0 {   // the enabled emitters, at their stamp channels
                emitCtrl(cable: UInt8(e + 1), status: hi | ((box.busChannels[e] &- 1) & 15), d1: d1, d2: d2, isPC: isPC)
            }
            emitCtrl(cable: 0, status: hi, d1: d1, d2: d2, isPC: isPC)          // + the ALL cable (channel 1)
        }
    }
    private func emitCtrl(cable: UInt8, status: UInt8, d1: UInt8, d2: UInt8, isPC: Bool) {
        guard let midiOut else { return }
        ctrlScratch[0] = status; ctrlScratch[1] = d1; ctrlScratch[2] = d2
        _ = midiOut(renderSampleImmediate, cable, isPC ? 2 : 3, &ctrlScratch)   // PC is a 2-byte message — never send a trailing 0
    }
    private var reelSelectRequest = Int.min                         // control thread: a pass to select+replay (Int.min = none)
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
    // The config-sheet REPLAY roll (Paul 2026-08-23): the ENGAGED door's captured loop as duration notes + its length,
    // so the piano roll reflects what's playing from the RECORDING. Value copies — safe off the render thread.
    func replayLoopRoll(door i: Int) -> [DoorRing.Note] { (i >= 0 && i < doorRings.count) ? doorRings[i].loopRoll() : [] }
    func replayLoopLen(door i: Int) -> Double { (i >= 0 && i < doorRings.count) ? doorRings[i].loopLen : 0 }
    func reelSelectedPassNo() -> Int { reel.selectedPassNo }
    func reelSelectPass(_ p: Int) { reelSelectRequest = p }
    func reelStopReplay() { reelStopRequest = true }
    func reelCycleValue() -> Double { reel.loopCycle }              // the SELECTED pass's length in beats (piano-roll x-axis + export) — not the live rate
    /// EXPORT (step 2): the recorded pass as SMF files — the A–D "sum" plus a per-emitter stem for each that has events.
    // (reelExport() — the whole-pass SMF export — was removed 2026-08-27; superseded by reelExportRange, its only path.)
    /// EXPORT a pass RANGE × an emitter SELECTION (Paul 2026-08-26). emitterMask == 0 ⇒ the MASTER (A–D sum) as one file;
    /// else one stem per selected emitter (A=bit0 … D=bit3). Each file is the passes [lo,hi] concatenated into one phrase.
    func reelExportRange(fromPass lo: Int, toPass hi: Int, emitterMask: UInt8) -> [(name: String, data: Data)] {
        let ppq = 480
        var files: [(name: String, data: Data)] = []
        if emitterMask == 0 {   // MASTER — the A–D sum
            let (evs, total) = reel.exportRangeEvents(fromPass: lo, toPass: hi, cables: [1, 2, 3, 4])
            if !evs.isEmpty { files.append((name: "MidiSpark-All.mid", data: MidiFile.encode(events: evs, bpm: reelTempoStored, ppq: ppq, loopBeats: total))) }
        } else {                // the SELECTED emitter stems
            for (i, letter) in ["A", "B", "C", "D"].enumerated() where (emitterMask & (1 << UInt8(i))) != 0 {
                let (evs, total) = reel.exportRangeEvents(fromPass: lo, toPass: hi, cables: [UInt8(i + 1)])
                if !evs.isEmpty { files.append((name: "MidiSpark-\(letter).mid", data: MidiFile.encode(events: evs, bpm: reelTempoStored, ppq: ppq, loopBeats: total))) }
            }
        }
        return files
    }
    func reelRangeRoll(fromPass lo: Int, toPass hi: Int) -> (notes: [ReelDeck.Note], cycle: Double) {
        let r = reel.rangeRoll(fromPass: lo, toPass: hi); return (r.notes, r.totalBeats)   // read-only value copy — safe off the render thread while browsing freezes the tape
    }
    private func reelBlanketOff(out: MIDIEmitter?) {                // CC120 + CC123 on every channel × cable — kills the loop's ringing notes on stop
        for cable in UInt8(0)...4 { for ch in UInt8(0)..<16 {
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
        receiverChannels = box.receiverChannels        // delta §9 item 11: this render's input filters (for metering)
        receiverChanMask = box.receiverChannelMask      // MULTI-CHANNEL: this render's per-door channel subsets
        receiverCables = box.receiverCables             // §item 11: this render's cable bitmasks
        receiverControllerMask = box.receiverControllerMask   // CONTROLLER ROUTING: per-door forward masks
        busChannels = box.busChannels                   // CONTROLLER ROUTING: per-emitter stamp channels
        pianoMask = box.receiverPianoMask               // PIANO LATCH: which doors read the keyboard
        pianoNotes = box.receiverPianoNotes
        receiverExcludeDoor = box.receiverExcludeDoor   // KEY FILTER: the reference door
        receiverExcludeOnly = box.receiverExcludeOnly   // §3: INTERSECT (ONLY) vs subtract (MINUS)
        receiverExcludeSnap = box.receiverExcludeSnap   // §3: SNAP vs BLOCK
        replayMask = box.receiverReplayMask             // REPLAY: which doors loop their input ring
        replayPasses = box.receiverReplayPasses
        drainControl(box: box)                          // ROW 8 CC-PUNCH / PC-SEND: flush any UI-queued control messages onto the emitter wires
        // FILE: load each door's clip into its ring when the snapshot generation changes (a clip edit → a new box).
        if fileClipGen != box.generation {
            fileClipGen = box.generation
            var fm: UInt8 = 0
            for i in 0..<4 {
                let clip = box.receiverFile[i]
                if clip.loopBeats > 0 {
                    doorRings[i].loadLoopParallel(beats: clip.beats, notes: clip.notes, vels: clip.vels, ons: clip.ons, lengthBeats: clip.loopBeats)
                    fm |= UInt8(1 << i)
                } else if fileMask & (1 << UInt8(i)) != 0 {   // was FILE, now cleared → drop the ring loop
                    doorRings[i].clearLoop()
                }
            }
            fileMask = fm
        }
        effectiveLatchMask = computeEffectiveLatchMask()   // PIANO SELF-ARM: fold PIANO-with-notes doors into the latch mask
        receiverRangeLo = box.receiverRangeLo            // RANGE (§2): this render's per-receiver note windows (latch capture)
        receiverRangeHi = box.receiverRangeHi
        latchAddMask = box.latchAddMask                 // TWO LATCH MODES: which receivers latch in ADD (toggle) mode
        thruReceiver = min(3, max(0, Int(box.thruReceiver)))   // receiver strip: which receiver passthrough follows
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
        if let mc = musicalContext {
            var bpm = 0.0, beat = 0.0
            var tsNum = 0.0; var tsDen: Int = 0; var sampleOffset: Int = 0; var measureBeat = 0.0
            if mc(&bpm, &tsNum, &tsDen, &beat, &sampleOffset, &measureBeat) {
                tempo = bpm > 0 ? bpm : 120
                beatPos = beat
            }
        }
        diag.playing = playing; diag.beat = beatPos; diag.tempo = tempo

        // REPLAY (config-sheets stage 3): the beat mapping handleIncoming uses to timestamp ring recordings, + the
        // per-render phase updateLatchedPools reads. Set BEFORE the events walk (recording) and updateLatchedPools.
        renderBeatPos = beatPos
        recordBeatBase = beatPos
        recordBps = sampleRate > 0 ? tempo / 60.0 / sampleRate : 0
        recordWinStart = Int64(timestamp.pointee.mSampleTime)
        recordPlaying = playing
        renderWindowBeats = Double(frameCount) * recordBps   // REPLAY look-ahead: sample the loop at the block END so a loop onset lands in the SAME block it would as live input (else it's one block late — the "constant lag")
        // TRANSPORT DISCONTINUITY → clear the DoorRing HISTORY (Paul 2026-08-23): the ring records at ABSOLUTE host beats
        // in arrival order, and capture()/notesSoundingAt() assume arrival order == ascending beat. A stop→start, a host
        // loop-back, or a backward scrub makes new events record at beats that overlap/go backward vs the resident
        // history → a garbled, mis-phased REPLAY capture ("out of sync around starting/stopping"). Reset recording to
        // monotone on those edges. A normal block advances beatPos by ~renderWindowBeats, so any backward move or a
        // forward jump ≫ one block is a discontinuity. The captured LOOP is left alone (it stays grid-aligned).
        let startEdge = playing && !prevRenderPlaying
        let jumped = playing && prevRenderPlaying && (beatPos < prevRenderBeatPos - 1e-6 || beatPos - prevRenderBeatPos > max(1.0, 4.0 * renderWindowBeats))   // CR-12: scale with the block span — a NORMAL block advances ~renderWindowBeats, so a fixed >1.0 mis-fired every block at high tempo × large buffer (starved REPLAY capture)
        if startEdge || jumped { for r in 0..<4 { doorRings[r].clearHistory() } }
        if startEdge { for r in 0..<4 { lastReferenceMask[r] = 0 } }   // §4 CARRY PIN resets on a fresh take (transport start)
        prevRenderBeatPos = beatPos; prevRenderPlaying = playing

        // Audition (stopped only) REPLACES raw note passthrough when the held cell will sound — you hear
        // the processor alone (§6.4). Not auditioning / a cell that can't sound → notes still pass for
        // soundcheck. CC/PB/AT always pass. Computed once here so handleIncoming is cheap.
        let audition = playing ? -1 : Int(auditionTarget)
        suppressAuditionNotes = audition >= 0 && auditionCellSounds(box, audition)

        #if DEBUG
        drainChaosMIDI(playing: playing)   // CHAOS SIMULATED source: fold any injected notes into the real input path, this render
        #endif

        // ---- event list: MIDI + parameter events ----
        var ev = events
        while let e = ev {
            let head = e.pointee.head
            switch head.eventType {
            case .MIDI:
                let midi = e.pointee.MIDI
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
                let ts = e.pointee.MIDIEventsList.eventSampleTime
                if let listPtr = e.pointer(to: \.MIDIEventsList.eventList) {
                    var pkt = listPtr.pointer(to: \.packet)!
                    for _ in 0..<Int(listPtr.pointee.numPackets) {
                        processUMPPacket(pkt, sampleTime: ts, playing: playing)
                        pkt = UnsafePointer(MIDIEventPacketNext(UnsafeMutablePointer(mutating: pkt)))
                    }
                }
            case .parameter, .parameterRamp:
                let pe = e.pointee.parameter
                router.applyParamEvent(pe.parameterAddress, Double(pe.value), diag: &diag)
            default:
                break
            }
            ev = UnsafePointer(head.next)
        }

        // REPLAY manual catch: consume any "LAST N" toggle (capture+engage / release) BEFORE the latch fill reads the loop.
        processReplayCatch(cycleBeats: Double(Snap.cols) * box.stepBeats, beatPos: renderBeatPos)
        // receiver strip LATCH: refresh the frozen chords from the (now up-to-date) live pool before render.
        updateLatchedPools()
        updateReceiverSounding()        // duration feed: snapshot the currently-held input notes per receiver
        // DOOR REPLAY diagnostic (2026-08-22): engaged mask + the engaged door's captured-loop + frozen-pool sizes —
        // so "loop animates but silent" localizes at a glance (see Diag.swift). loopN=0 ⇒ nothing captured; loopN>0 &
        // poolN=0 ⇒ the loop→pool fill isn't landing; poolN>0 & still silent ⇒ no grid cell reads that door.
        diag.replayEngaged = replayEngagedMask; diag.replayLoopN = 0; diag.replayPoolN = 0
        for i in 0..<4 where (replayEngagedMask & (1 << UInt8(i))) != 0 {
            diag.replayLoopN += doorRings[i].loopN; diag.replayPoolN += latchedPools[i].count
        }
        // ---- THE REEL-TO-REEL: record/replay the emitter output (Paul 2026-08-18) ----
        // The pass length = 8 columns at the EFFECTIVE clock. ROW 8 HALFTIME scales the column clock (box.clockScale:
        // ÷2 ⇒ 2.0, so a bar is twice as long), so the reel must scale too — else it chops passes (+ exports the loop)
        // at the WRONG length under half/double speed and the MIDI comes out garbled (Paul 2026-08-24).
        let reelCycleBeats = Double(Snap.cols) * box.stepBeats * box.clockScale
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
        if reelSelectRequest != Int.min {                          // the pop-up tapped a pass: pin it + REPLAY NOW (replace live output)
            let p = reelSelectRequest; reelSelectRequest = Int.min
            if reel.selectPass(p) { reel.state = .replaying; router.allNotesOff(atSample: renderSampleImmediate, out: liveEmitter, includeBypass: true) }   // reel REPLACES live output → flush the live WIRE/bypass monitor too (reconcileBypass is skipped during replay, so it can't close them → hung notes, Paul 2026-08-24)
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
            if reel.state == .armed { reel.state = .replaying; router.allNotesOff(atSample: renderSampleImmediate, out: liveEmitter, includeBypass: true) }   // armed→replaying: flush the live WIRE/bypass monitor too (see above)
            reel.startPass(); reelLastPass = reelPass
            reelRecordFromStart = playing && !reelFrozen           // will the NEW pass record from its start? (partial/frozen passes never file)
        }
        if reelExitFlush { reelExitFlush = false; reelBlanketOff(out: liveEmitter) }
        reelTap.out = liveEmitter; reelTap.deck = reel
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
            let effHeld = pool.count > 0 || (0..<4).contains { (effectiveLatchMask & (1 << UInt8($0))) != 0 && $0 < latchedPools.count && latchedPools[$0].count > 0 }
            if effHeld {
                if !freeRunActive { freeRunActive = true; freeRunBeat = 0 }
                freeRunBeat += renderWindowBeats
                rPlaying = true; rBeat = freeRunBeat
            } else if freeRunActive {
                freeRunActive = false; freeRunBeat = 0
                router.allNotesOff(atSample: renderSampleImmediate, out: liveEmitter, includeBypass: true)
            }
        } else if freeRunActive {   // host started, or free-run disabled mid-run → stop + flush the free-run notes
            freeRunActive = false; freeRunBeat = 0
            router.allNotesOff(atSample: renderSampleImmediate, out: liveEmitter, includeBypass: true)
        }
        diag.beat = rBeat            // EFFECTIVE beat (host OR free-run) → UI beat-driven playheads work while the host is stopped (Paul 2026-08-29)
        if reel.state == .replaying, reel.hasLoop {               // REPLACE the live output with the recorded loop
            reel.replay(beatPos: beatPos, windowBeats: Double(frameCount) * reelBps, cycleBeats: reel.loopCycle,   // loop at the SELECTED pass's own length, not the live rate
                        beatsPerSample: reelBps, windowStart: reelWinStart, out: liveEmitter)
        } else {
        // ---- hand off to the router (columns, arp, emission, note tracker) — output through the recording tap ----
        router.process(box: box, pool: pool,
                        playing: rPlaying, beatPos: rBeat, tempo: tempo,
                        sampleRate: sampleRate,
                        timestampSample: timestamp.pointee.mSampleTime,
                        frameCount: frameCount, audition: audition, forceColumn: Int(soloColumn), laneMask: laneMask,
                        velOverride: velOverride, heldCell: Int(heldCell), tapAltMask: tapAltMask,
                        tapMuteMask: tapMuteMask, soloCellMask: soloCellMask, soloEmitterMask: soloEmitterMask,
                        soloReceiverMask: soloReceiverMask, inputOctave: inputOctave, inputSemitone: inputSemitone, inputVelOverride: inputVelOverride,
                        emitterOctave: emitterOctave, masterVelOverride: masterVelOverride,
                        velKillMask: velKillMask, masterKill: masterKill, panic: panicRequested,
                        sceneFlush: flushRequested, sceneRestart: restartRequested,
                        latchMask: effectiveLatchMask, latchedPools: latchedPools,
                        preview: (previewActive, Int(previewColourIndex), Int(previewFilter), previewBusMask, Int(previewInputRow)),
                        out: reelTap, diag: &diag)
        router.snapshotEmitterSounding()   // §strips-done: capture the currently-sounding set (voices now reconciled)
        router.snapshotCellSounding()      // SEAL comet: capture which cells are sounding (note-on/off gate)
        }
        diag.reelState = reelStateValue()
        panicRequested = false          // master panel PANIC is a one-shot — consumed by this render's flush
        flushRequested = false          // MULTI-SCENE scene-switch flush is a one-shot too
        restartRequested = false        // MULTI-SCENE S2b restart-the-pass is a one-shot too

        #if DEBUG
        computeRoutedPath(box)                   // CHAOS oracle: is there a structural path a held note could sound through?
        chaosOracleTick(box, playing: playing)   // build the chain-state dump when silence looks SUSPICIOUS
        #endif

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
        if silenceInvariantViolated(playing: producing, heldInput: pool.count, auditioning: audition >= 0,
                                    activeVoices: diag.activeVoiceCount, passthroughHeld: diag.passthroughHeld) {
            healStuckNotes(now: now, hardTrap: true,   // a hard invariant: DEBUG traps into the corpse
                           reason: "silence violated (playing=\(playing) rPlaying=\(rPlaying) held=\(pool.count) audition=\(audition))",
                           diag: &diag)
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
            let liveEmpty = playing && pool.count == 0 && effectiveLatchMask == 0 && audition < 0 && reel.state != .replaying && !box.freezeActive
            emptyInputSamples = liveEmpty ? emptyInputSamples &+ Int64(frameCount) : 0
            let columnSamples = Int64(max(1.0, box.stepBeats * 60.0 / max(1.0, tempo) * sampleRate))
            let debounce = max(Int64(sampleRate), 4 &* columnSamples)   // ≥ 1 s AND ≥ 4 columns — never cuts a legit tail
            if playingSilenceLeak(playing: playing, liveInput: pool.count, latchArmed: effectiveLatchMask != 0,
                                  auditioning: audition >= 0, emptyInputSamples: emptyInputSamples,
                                  debounceSamples: debounce, activeVoices: diag.activeVoiceCount,
                                  passthroughHeld: diag.passthroughHeld) {
                healStuckNotes(now: now, hardTrap: false,
                               reason: "playing silence leak (no source for \(emptyInputSamples) samples)",
                               diag: &diag)
                emptyInputSamples = 0
            }
        }
    }

    /// Force-silence the whole engine (the STUCK-NOTE heal shared by both a8 nets): dump the corpse for the
    /// log FIRST (always legible), all-notes-off every router voice, flush any stranded passthrough echo as a
    /// note-off on All + Emit A, and count the self-heal. `hardTrap` = a HARD invariant (DEBUG crashes into the
    /// logged corpse); false = a heuristic net (soft-heal only, no trap).
    private func healStuckNotes(now: Int64, hardTrap: Bool, reason: String, diag: inout KernelDiag) {
        let dump = "MidiSpark STUCK-NOTE: \(reason) — voices=[\(router.stuckVoiceFingerprint())] "
                 + "echoes=[\(passthroughGate.heldFingerprint())]"
        os_log(.fault, log: Self.hangLog, "%{public}s", dump)            // RELEASE: soft — surfaces without crashing a gig
        diag.silenceViolated = true
        diag.panics &+= 1
        router.allNotesOff(atSample: now, out: liveEmitter)              // close any leaked sequenced voices
        if let out = midiOut {                                           // flush stranded echoes as offs on All + Emit A
            for (chan, note) in passthroughGate.drainActive() {
                passthroughScratch[0] = 0x80 | chan; passthroughScratch[1] = note; passthroughScratch[2] = 0
                _ = out(now, 0, 3, &passthroughScratch)
                _ = out(now, 1, 3, &passthroughScratch)
            }
        }
        diag.activeVoiceCount = 0; diag.passthroughHeld = 0
        #if DEBUG
        if hardTrap && Self.hardTrapOnStuckNote { assertionFailure(dump) }   // DEBUG: crash into the (already-logged) corpse
        #endif
    }

    /// True when the audition target is a cell that WILL sound (occupied, non-muted, non-bypassed, with
    /// lit buses) — audition then fully replaces the raw note passthrough. Must agree with the guard in
    /// Router.auditionRender (both gate on the same condition; a bypassed/empty/unlit cell keeps
    /// passthrough so the held chord is still audible).
    private func auditionCellSounds(_ box: SnapshotBox, _ target: Int) -> Bool {
        let col = target / Snap.rows, row = target % Snap.rows
        guard col >= 0, col < Snap.cols, row >= 0, row < Snap.rows else { return false }
        let cell = box.cells[col * Snap.rows + row]
        return cell.colourIndex >= 0 && !cell.muted && !cell.bypassed && cell.busMask != 0
    }

    // MARK: - incoming MIDI (source pool + passthrough)

    private func handleIncoming(bytes: UnsafeBufferPointer<UInt8>, length: Int,
                                sampleTime: AUEventSampleTime, playing: Bool, cable: Int = 0) {
        let status = bytes[0] & 0xF0
        let isNote = (status == 0x90 || status == 0x80)
        let channel = bytes[0] & 0x0F
        if status == 0x90, length >= 3 {
            pool.noteOn(bytes[1], velocity: bytes[2], channel: channel, cable: UInt8(clamping: cable))
            // delta §9 item 11 INPUT metering: attribute this note-on to EVERY receiver whose filter hears
            // it (§item 11: cable AND channel). A vel-0 note-on is a note-off — skip it.
            let vel = bytes[2]
            if vel > 0 {
                for i in 0..<4 where receiverHearsCable(mask: Int(receiverCables[i]), eventCable: cable)
                                  && receiverHearsMask(receiverChanMask[i], channel: channel) {
                    if vel > inputPeak[i] { inputPeak[i] = vel }
                    inputEvents[i] &+= 1
                    inputChannelMask[i] |= UInt16(1) << UInt16(channel)   // §MPE: track the channel spread this window
                }
            }
            recordReplay(note: bytes[1], vel: vel, on: vel > 0, sampleTime: sampleTime, channel: channel, cable: cable)
        } else if status == 0x80, length >= 3 {
            pool.noteOff(bytes[1])
            recordReplay(note: bytes[1], vel: 0, on: false, sampleTime: sampleTime, channel: channel, cable: cable)
        }
        if !isNote {
            diag.ccCount &+= 1
            diag.ccStatus = bytes[0]
            diag.ccData1 = length > 1 ? bytes[1] : 0
            diag.ccData2 = length > 2 ? bytes[2] : 0
            // EXTERN side-rail (§7): stash incoming CC values so a MOD EXTERN stage can read + transform them.
            // CC121 = Reset All Controllers → clear the store (§11). Note-agnostic; the note pipeline never sees this.
            if status == 0xB0, length >= 3 {
                if bytes[1] == 121 { router.clearControllerIn() } else { router.setControllerIn(cc: Int(bytes[1]), value: Int(bytes[2])) }
                // CC120/123 = ALL-SOUND / ALL-NOTES-OFF (ratified) → FLUSH our held pool + every armed latch, then forward.
                if bytes[1] == 120 || bytes[1] == 123 { pool.reset(); for p in latchedPools { p.reset() } }
            }
        }
        // CONTROLLER ROUTING (v1): CC · PB · AT · PC forward to each door's CONTROLLERS emitters (union), RE-STAMPED to
        // the emitter's stamp channel + cable. SUPERSEDES the old CC/PB/AT passthrough (All + Emit A). Notes (soundcheck)
        // + system keep the passthrough below. (Ownership suppression — a BEND/MOD stage owning an address — is the
        // reserved rule, not v1: for now forward + generate both, last-writer.)
        if isForwardableController(bytes[0]), let out = midiOut {
            for i in 0..<4 { hearingScratch[i] = receiverHearsCable(mask: Int(receiverCables[i]), eventCable: cable) && receiverHearsMask(receiverChanMask[i], channel: channel) }   // CR-16: reused scratch (no per-event alloc)
            let fwd = controllerForwardMask(hearing: hearingScratch, masks: receiverControllerMask)
            if fwd != 0 {
                let n = min(length, 3)
                for i in 0..<n { passthroughScratch[i] = bytes[i] }
                var m = fwd
                while m != 0 {
                    let bus = Int(m.trailingZeroBitCount); m &= m - 1
                    passthroughScratch[0] = (bytes[0] & 0xF0) | ((busChannels[bus] &- 1) & 15)   // RE-STAMP the channel
                    _ = out(sampleTime, UInt8(bus + 1), n, &passthroughScratch)                  // emitter cable (A=1…D=4)
                }
            }
            return   // controller handled by the routing forward — skip the legacy passthrough
        }
        // §2.6 (reconciled to §7b): stopped-note passthrough (soundcheck) go out on All (0) + Emit A (1).
        // a8: routed through the gate so a note-OFF follows its forwarded ON regardless of state now.
        let pNote = length >= 2 ? bytes[1] : 0
        let pVel  = length >= 3 ? bytes[2] : 0
        // NOTE MONITOR OFF by policy (Paul 2026-08-29: "silence as no cell is selected"). Folding !noteMonitorPassthrough
        // into auditionSuppressing makes the gate treat every raw note as suppressed → mask 0 AND tracked want=false, so
        // its OFF also drops (no spurious note-off, no stuck note). System messages (isNote=false in the gate) still forward.
        var mask = passthroughGate.mask(statusByte: bytes[0], note: pNote, velocity: pVel,
                                        playing: playing, auditionSuppressing: suppressAuditionNotes || previewActive || !noteMonitorPassthrough)
        // receiver strip: passthrough FOLLOWS THE THRU PIP's receiver (default R1) — supersedes follows-R1.
        // A non-note event forwards only if the THRU receiver hears it (cable + channel); a note soundcheck is
        // mute-gated only; a MUTED THRU passes NOTHING (note soundcheck included). See `thruAudible`.
        if !thruAudible(isNote: isNote, isSystem: bytes[0] >= 0xF0, filter: receiverChannels[thruReceiver],
                        cableMask: Int(receiverCables[thruReceiver]), eventCable: cable, channel: channel) {
            mask = 0
        }
        if mask != 0, let out = midiOut {
            let n = min(length, 3)
            for i in 0..<n { passthroughScratch[i] = bytes[i] }
            var m = mask
            while m != 0 {                                  // forward on each cable in the mask (0 = All, 1 = Emit A)
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
