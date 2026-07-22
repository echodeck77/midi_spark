//  Emission.swift
//  MidiSpark — the MIDI emission seam (standalone-plan.md seam rule 1 / delta §7b
//  "emission is the only place that knows cables").
//
//  The render engine (Router) speaks ONLY this protocol — it never imports AudioToolbox, so the
//  whole of its tick-generation + refcount logic compiles into the Foundation-only macOS unit-test
//  target. The LIVE implementation (LiveMIDIEmitter, in Kernel.swift — the render boundary that
//  legitimately owns AudioToolbox) forwards to the host's AUMIDIOutputEventBlock; tests inject a
//  recording double and assert on the exact (sample, cable, bytes) stream.

import Foundation

/// Every MidiSpark MIDI message is a 3-byte channel-voice message (note-on / note-off). The cable
/// (0 = ALL, 1–4 = A–D, delta §7b) and the absolute sample time are chosen by the engine; the stamp
/// channel is already baked into `b0`'s low nibble by the time it reaches here.
protocol MIDIEmitter: AnyObject {
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8)
}

/// "Render this as soon as possible in this cycle." Mirrors AudioToolbox's `AUEventSampleTimeImmediate`
/// (`(AUEventSampleTime)0xffffffff00000000`, i.e. −(1<<32)); defined here so the pure engine never has
/// to import AudioToolbox to name it. LiveMIDIEmitter passes it straight through — since
/// `AUEventSampleTime == Int64` and the value is identical, the host sees exactly what it did before.
let renderSampleImmediate: Int64 = Int64(bitPattern: 0xffffffff00000000)
