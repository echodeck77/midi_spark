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

        // Audition (stopped only) REPLACES raw note passthrough when the held cell is a patterned type
        // (ARP/RATCHET, v1) — you hear the processor alone (§6.4). Other types / not auditioning → notes
        // still pass for soundcheck. CC/PB/AT always pass. Computed once here so handleIncoming is cheap.
        let audition = playing ? -1 : Int(auditionTarget)
        suppressAuditionNotes = audition >= 0 && auditionCellIsPatterned(box, audition)

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
                        handleIncoming(bytes: bytes, length: length,
                                       sampleTime: midi.eventSampleTime,
                                       playing: playing)
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

        // ---- hand off to the router (columns, arp, emission, note tracker) ----
        router.process(box: box, pool: pool,
                        playing: playing, beatPos: beatPos, tempo: tempo,
                        sampleRate: sampleRate,
                        timestampSample: timestamp.pointee.mSampleTime,
                        frameCount: frameCount, audition: audition, out: liveEmitter, diag: &diag)
    }

    /// True when the audition target is an occupied, non-muted, non-bypassed cell whose active type is
    /// ARP or RATCHET — the v1 audition types, which fully replace the raw note passthrough. Must agree
    /// with Router.auditionRender's own type switch (both gate on the same condition).
    private func auditionCellIsPatterned(_ box: SnapshotBox, _ target: Int) -> Bool {
        let col = target / Snap.rows, row = target % Snap.rows
        guard col >= 0, col < Snap.cols, row >= 0, row < Snap.rows else { return false }
        let cell = box.cells[col * Snap.rows + row]
        guard cell.colourIndex >= 0, !cell.muted, !cell.bypassed else { return false }
        let type = box.colours[Int(cell.colourIndex)].a.type
        return type == .arp || type == .ratchet
    }

    // MARK: - incoming MIDI (source pool + passthrough)

    private func handleIncoming(bytes: UnsafeBufferPointer<UInt8>, length: Int,
                                sampleTime: AUEventSampleTime, playing: Bool) {
        let status = bytes[0] & 0xF0
        let isNote = (status == 0x90 || status == 0x80)
        let channel = bytes[0] & 0x0F
        if status == 0x90, length >= 3 {
            pool.noteOn(bytes[1], velocity: bytes[2], channel: channel)
        } else if status == 0x80, length >= 3 {
            pool.noteOff(bytes[1])
        }
        if !isNote {
            diag.ccCount &+= 1
            diag.ccStatus = bytes[0]
            diag.ccData1 = length > 1 ? bytes[1] : 0
            diag.ccData2 = length > 2 ? bytes[2] : 0
        }
        // §2.6: CC/PB/AT pass through on cable A always; notes pass only when stopped AND not being
        // replaced by an audition (§6.4 — the held processor sounds alone instead of the raw chord).
        let shouldForward = isNote ? (!playing && !suppressAuditionNotes) : true
        if shouldForward, let out = midiOut {
            var copy: [UInt8] = [0, 0, 0]
            for i in 0..<min(length, 3) { copy[i] = bytes[i] }
            _ = out(sampleTime, 0, min(length, 3), &copy)
        }
    }
}
