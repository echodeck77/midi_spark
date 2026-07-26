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
    // receiver strip: per-receiver ±octave nudge (−3…+3), packed one signed byte each. Ephemeral (weather).
    private var inputOctave: UInt32 = 0
    func setInputOctave(_ recv: Int, _ oct: Int) {
        guard recv >= 0 && recv < 4 else { return }
        let byte = UInt32(UInt8(bitPattern: Int8(max(-3, min(3, oct))))) & 0xFF
        let shift = UInt32(recv) * 8
        inputOctave = (inputOctave & ~(0xFF << shift)) | (byte << shift)
    }
    // receiver strip: the momentary-absolute INPUT-velocity override (the slider's ride), packed byte per
    // receiver (0 = none, 1–127 = flatten). Ephemeral; the UI springs it back to 0 on slider release.
    private var inputVelOverride: UInt32 = 0
    func setInputVelOverride(_ recv: Int, _ value: Int?) {
        guard recv >= 0 && recv < 4 else { return }
        let byte = UInt32((value.map { max(1, min(127, $0)) } ?? 0)) & 0xFF
        let shift = UInt32(recv) * 8
        inputVelOverride = (inputVelOverride & ~(0xFF << shift)) | (byte << shift)
    }
    // emitter strip: per-emitter output ±octave nudge (−3…+3), packed one signed byte each. Ephemeral (weather).
    private var emitterOctave: UInt32 = 0
    func setEmitterOctave(_ bus: Int, _ oct: Int) {
        guard bus >= 0 && bus < 4 else { return }
        let byte = UInt32(UInt8(bitPattern: Int8(max(-3, min(3, oct))))) & 0xFF
        let shift = UInt32(bus) * 8
        emitterOctave = (emitterOctave & ~(0xFF << shift)) | (byte << shift)
    }
    // master panel: the momentary master velocity FADER (0 = none, 1–127 = force over all output). Ephemeral;
    // the UI springs it back on release. Plus PANIC — a one-shot all-notes-off + voice flush, hang-kit-logged.
    private var masterVelOverride: UInt8 = 0
    func setMasterVelOverride(_ value: Int?) { masterVelOverride = UInt8(value.map { max(1, min(127, $0)) } ?? 0) }
    private var panicRequested = false
    func panic() { panicRequested = true }
    // receiver strip LATCH (chord-hold): 4 FROZEN input pools + the armed mask. Each render, an armed
    // receiver captures the live filtered chord while fingers are down and FREEZES it when they lift (a NEW
    // chord replaces automatically — fingers-down re-captures); a fresh arm starts empty. The frozen pools
    // survive snapshot rebuilds (ephemeral kernel state), so a MUTE silences but does not clear them.
    private let latchedPools: [NotePool] = [NotePool(), NotePool(), NotePool(), NotePool()]
    private var latchArmMask: UInt8 = 0
    private var prevLatchArmMask: UInt8 = 0
    func setLatchArm(_ mask: UInt8) { latchArmMask = mask }
    private func updateLatchedPools() {
        guard latchArmMask != 0 || prevLatchArmMask != 0 else { return }   // fast path: nothing armed now or before
        pool.rebuildSorted()                       // the live pool's ascending view (process rebuilds again; idempotent)
        for i in 0..<4 {
            let bit = UInt8(1 << i)
            let isArmed = latchArmMask & bit != 0, wasArmed = prevLatchArmMask & bit != 0
            if isArmed && !wasArmed { latchedPools[i].reset() }   // fresh arm → start empty (no stale chord)
            if isArmed, pool.srcCount(filter: receiverChannels[i], cableMask: Int(receiverCables[i])) > 0 {
                latchedPools[i].captureFiltered(from: pool, filter: receiverChannels[i], cableMask: Int(receiverCables[i]))
            }   // armed + fingers up ⇒ keep the last captured chord (FREEZE)
        }
        prevLatchArmMask = latchArmMask
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
    func setVelOverride(_ bus: Int, _ value: Int?) {
        guard bus >= 0 && bus < 4 else { return }
        let byte = UInt32((value.map { max(1, min(127, $0)) } ?? 0)) & 0xFF
        let shift = UInt32(bus) * 8
        velOverride = (velOverride & ~(0xFF << shift)) | (byte << shift)
    }

    // §6a metering: read-and-clear per-emitter peak velocity + event count since the last call (UI poll).
    func drainEmitterActivity() -> (peak: [UInt8], events: [UInt32]) { router.drainMeters() }
    func drainEmitterMarks() -> [[(vel: UInt8, col: Int8)]] { router.drainMarks() }   // item 4 velocity marks

    // delta §9 item 11: INPUT metering — per-receiver peak velocity + event count since the last poll (the
    // input twin of §6a). `receiverChannels` is this render's filters (0 = OMNI, 1–16), set from the box.
    private var receiverChannels: [UInt8] = [0, 0, 0, 0]
    private var receiverCables: [UInt8] = [0b1111, 0b1111, 0b1111, 0b1111]   // §item 11: cable bitmasks (for metering)
    private var thruReceiver: Int = 0        // receiver strip: which receiver the passthrough gate follows (the THRU pip)
    private var inputPeak = [UInt8](repeating: 0, count: 4)
    private var inputEvents = [UInt32](repeating: 0, count: 4)
    func drainReceiverActivity() -> (peak: [UInt8], events: [UInt32]) {
        let r = (inputPeak, inputEvents)
        for i in 0..<4 { inputPeak[i] = 0; inputEvents[i] = 0 }
        return r
    }
    // item 4 VELOCITY MARKS (input side): per receiver, recent note-on velocities since the last poll (input
    // has no Colour → the UI tints them the strip's identity hue). Bounded to 8 per poll cycle.
    private var recvMarkVel = [[UInt8]](repeating: [UInt8](repeating: 0, count: 8), count: 4)
    private var recvMarkCount = [Int](repeating: 0, count: 4)
    func drainReceiverMarks() -> [[UInt8]] {
        var out = [[UInt8]]()
        for i in 0..<4 { out.append(Array(recvMarkVel[i][0..<recvMarkCount[i]])); recvMarkCount[i] = 0 }
        return out
    }

    private let pool = NotePool()       // the source (§2.5), fed by incoming MIDI
    private let router = Router()       // grid → emission (§2/§7)
    private let liveEmitter = LiveMIDIEmitter()   // the AUMIDIOutputEventBlock adapter (emission seam)

    func reset() {
        pool.reset()
        liveEmitter.out = midiOut       // pick up the current host block before flushing
        router.allNotesOff(atSample: renderSampleImmediate, out: liveEmitter)    // flush any hung notes
        router.reset()
    }

    // MARK: - render

    func render(timestamp: UnsafePointer<AudioTimeStamp>,
                frameCount: AUAudioFrameCount,
                events: UnsafePointer<AURenderEvent>?) {

        guard let box = store?.acquire() else { return }
        receiverChannels = box.receiverChannels        // delta §9 item 11: this render's input filters (for metering)
        receiverCables = box.receiverCables             // §item 11: this render's cable bitmasks
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

        // Audition (stopped only) REPLACES raw note passthrough when the held cell will sound — you hear
        // the processor alone (§6.4). Not auditioning / a cell that can't sound → notes still pass for
        // soundcheck. CC/PB/AT always pass. Computed once here so handleIncoming is cheap.
        let audition = playing ? -1 : Int(auditionTarget)
        suppressAuditionNotes = audition >= 0 && auditionCellSounds(box, audition)

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

        // receiver strip LATCH: refresh the frozen chords from the (now up-to-date) live pool before render.
        updateLatchedPools()
        // ---- hand off to the router (columns, arp, emission, note tracker) ----
        router.process(box: box, pool: pool,
                        playing: playing, beatPos: beatPos, tempo: tempo,
                        sampleRate: sampleRate,
                        timestampSample: timestamp.pointee.mSampleTime,
                        frameCount: frameCount, audition: audition, laneMask: laneMask,
                        velOverride: velOverride, heldCell: Int(heldCell), tapAltMask: tapAltMask,
                        tapMuteMask: tapMuteMask, soloEmitterMask: soloEmitterMask,
                        soloReceiverMask: soloReceiverMask, inputOctave: inputOctave, inputVelOverride: inputVelOverride,
                        emitterOctave: emitterOctave, masterVelOverride: masterVelOverride, panic: panicRequested,
                        latchMask: latchArmMask, latchedPools: latchedPools,
                        preview: (previewActive, Int(previewColourIndex), Int(previewFilter), previewBusMask, Int(previewInputRow)),
                        out: liveEmitter, diag: &diag)
        panicRequested = false          // master panel PANIC is a one-shot — consumed by this render's flush

        // ---- a8 ASSERT-ON-SILENCE net: when nothing legitimately sounds (stopped, no held input, no
        //      audition), any lingering router voice or passthrough echo is a STUCK NOTE. Force silence —
        //      safe by construction here (nothing real is playing) — and count the self-heal for the poll.
        diag.passthroughHeld = passthroughGate.activeCount
        if silenceInvariantViolated(playing: playing, heldInput: pool.count, auditioning: audition >= 0,
                                    activeVoices: diag.activeVoiceCount, passthroughHeld: diag.passthroughHeld) {
            // a8 DUMP-BEFORE-TRAP: read the corpse FIRST (before healing), so it is always legible.
            let dump = "MidiSpark STUCK-NOTE: silence violated — voices=[\(router.stuckVoiceFingerprint())] "
                     + "echoes=[\(passthroughGate.heldFingerprint())] (playing=\(playing) held=\(pool.count) audition=\(audition))"
            os_log(.fault, log: Self.hangLog, "%{public}s", dump)        // RELEASE: soft — surfaces without crashing a gig
            diag.silenceViolated = true
            diag.panics &+= 1
            // HEAL (the release safety net) — force silence; nothing legitimate can sound in this state.
            let now = Int64(timestamp.pointee.mSampleTime)
            router.allNotesOff(atSample: now, out: liveEmitter)          // close any leaked sequenced voices
            if let out = midiOut {                                       // flush stranded echoes as offs on All + Emit A
                for (chan, note) in passthroughGate.drainActive() {
                    passthroughScratch[0] = 0x80 | chan; passthroughScratch[1] = note; passthroughScratch[2] = 0
                    _ = out(now, 0, 3, &passthroughScratch)
                    _ = out(now, 1, 3, &passthroughScratch)
                }
            }
            diag.activeVoiceCount = 0; diag.passthroughHeld = 0
            #if DEBUG
            if Self.hardTrapOnStuckNote { assertionFailure(dump) }       // DEBUG: crash into the (already-logged) corpse
            #endif
        } else {
            diag.silenceViolated = false
        }
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
                                  && receiverHears(filter: receiverChannels[i], channel: channel) {
                    if vel > inputPeak[i] { inputPeak[i] = vel }
                    inputEvents[i] &+= 1
                    if recvMarkCount[i] < 8 { recvMarkVel[i][recvMarkCount[i]] = vel; recvMarkCount[i] += 1 }   // item 4 mark
                }
            }
        } else if status == 0x80, length >= 3 {
            pool.noteOff(bytes[1])
        }
        if !isNote {
            diag.ccCount &+= 1
            diag.ccStatus = bytes[0]
            diag.ccData1 = length > 1 ? bytes[1] : 0
            diag.ccData2 = length > 2 ? bytes[2] : 0
        }
        // §2.6 (reconciled to §7b): CC/PB/AT + stopped-note passthrough go out on All (0) + Emit A (1).
        // a8: routed through the gate so a note-OFF follows its forwarded ON regardless of state now.
        let pNote = length >= 2 ? bytes[1] : 0
        let pVel  = length >= 3 ? bytes[2] : 0
        var mask = passthroughGate.mask(statusByte: bytes[0], note: pNote, velocity: pVel,
                                        playing: playing, auditionSuppressing: suppressAuditionNotes || previewActive)
        // receiver strip: passthrough FOLLOWS THE THRU PIP's receiver (default R1) — supersedes follows-R1.
        // A non-note event forwards only if the THRU receiver hears it (cable + channel); a note soundcheck is
        // mute-gated only; a MUTED THRU passes NOTHING (note soundcheck included). See `thruAudible`.
        if !thruAudible(isNote: isNote, filter: receiverChannels[thruReceiver], cableMask: Int(receiverCables[thruReceiver]),
                        eventCable: cable, channel: channel) {
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
