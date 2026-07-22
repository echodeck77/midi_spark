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

struct KernelDiag {
    var renderCount: UInt64 = 0
    var playing = false
    var beat: Double = 0
    var tempo: Double = 0
    var poolCount = 0
    var snapshotGen: UInt64 = 0
    var paramEventCount: UInt64 = 0
    var lastParamAddr: Int64 = -1
    var lastParamValue: Double = 0
    var ccCount: UInt64 = 0
    var ccStatus: UInt8 = 0, ccData1: UInt8 = 0, ccData2: UInt8 = 0
    var effMorphGold: Double = 0
    var effRateBeats: Double = 0
    var effSwing: Double = 50
    var emitCount: UInt64 = 0
    var lastEmitNote: UInt8 = 0
    var lastEmitChan: UInt8 = 0        // 0-based wire channel; panel shows +1 (human numbering)
    var lastEmitInherit = true         // stamped from source channel (INHERIT) vs Colour OUT CH
    var effColumn = 0                  // active grid column (0…7), derived (§7)
    var pass: Int = 0                  // how many full 8-column cycles elapsed
    var activeCellRow = -1             // row of the sounding cell in effColumn, -1 = column empty
    var activeCellParent: Int8 = -1    // v3.0 resolvedParent of the active cell (−1 = MIDI IN)
    var activeVoiceCount = 0           // instances in the poly voice table (per bus × ch × note)
    var distinctSounding = 0           // distinct (bus,ch,note) on the wire; < voices when notes collide
}

final class Kernel {
    var midiOut: AUMIDIOutputEventBlock?
    var musicalContext: AUHostMusicalContextBlock?
    var transportState: AUHostTransportStateBlock?
    var sampleRate: Double = 44_100
    var store: SnapshotStore?
    private(set) var diag = KernelDiag()

    private let pool = NotePool()       // the source (§2.5), fed by incoming MIDI
    private let router = Router()       // grid → emission (§2/§7)

    func reset() {
        pool.reset()
        router.allNotesOff(atSample: AUEventSampleTimeImmediate, out: midiOut)   // flush any hung notes
        router.reset()
    }

    // MARK: - render

    func render(timestamp: UnsafePointer<AudioTimeStamp>,
                frameCount: AUAudioFrameCount,
                events: UnsafePointer<AURenderEvent>?) {

        guard let box = store?.acquire() else { return }
        diag.renderCount &+= 1
        diag.snapshotGen = box.generation

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
                        frameCount: frameCount, out: midiOut, diag: &diag)
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
        // §2.6: CC/PB/AT pass through on cable A always; notes pass only when stopped.
        let shouldForward = isNote ? !playing : true
        if shouldForward, let out = midiOut {
            var copy: [UInt8] = [0, 0, 0]
            for i in 0..<min(length, 3) { copy[i] = bytes[i] }
            _ = out(sampleTime, 0, min(length, 3), &copy)
        }
    }
}
