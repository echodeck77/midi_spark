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

// MARK: - THE REEL-TO-REEL (Paul 2026-08-18) — a 1-pass tape of the EMITTED output.
// Foundation-only (no AudioToolbox) so it lives here and is unit-testable. While recording, every emitted event is
// captured with its PASS-RELATIVE beat (0…cycleBeats). On ARM, the just-finished pass becomes the loop; from the next
// pass boundary the loop REPLACES the live output (looping) until a second touch resumes live. Step 1 toward MIDI export.
final class ReelDeck {
    enum State: Equatable { case off, armed, replaying }
    var state: State = .off
    struct Ev: Equatable { var beat = 0.0; var cable: UInt8 = 0; var b0: UInt8 = 0; var b1: UInt8 = 0; var b2: UInt8 = 0 }
    static let cap = 16384
    private(set) var cur = [Ev](repeating: Ev(), count: cap); private(set) var curN = 0
    private(set) var loop = [Ev](repeating: Ev(), count: cap); private(set) var loopN = 0
    var hasLoop: Bool { loopN > 0 }
    func record(beat: Double, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if curN < ReelDeck.cap { cur[curN] = Ev(beat: beat, cable: cable, b0: b0, b1: b1, b2: b2); curN += 1 }
    }
    func startPass() { curN = 0 }
    func promote() { loopN = curN; for i in 0..<curN { loop[i] = cur[i] } }   // the just-finished pass becomes the loop
    func clear() { curN = 0; loopN = 0; state = .off }
    /// The loop's events on the given cables (for EXPORT). cables: {1,2,3,4} = the A–D sum; {n} = one emitter. (Paul 2026-08-18)
    func exportEvents(cables: Set<UInt8>) -> [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)] {
        (0..<loopN).compactMap { cables.contains(loop[$0].cable) ? (loop[$0].beat, loop[$0].b0, loop[$0].b1, loop[$0].b2) : nil }
    }
    /// Emit every loop event whose NEXT occurrence lands in this render window [beatPos, beatPos+windowBeats). Loops
    /// across the pass boundary per-event, so a window straddling the boundary plays both spans.
    func replay(beatPos: Double, windowBeats: Double, cycleBeats: Double, beatsPerSample: Double, windowStart: Int64, out: MIDIEmitter?) {
        guard beatsPerSample > 0, cycleBeats > 0 else { return }
        let passStart = (beatPos / cycleBeats).rounded(.down) * cycleBeats
        let end = beatPos + windowBeats
        for i in 0..<loopN {
            var occ = passStart + loop[i].beat
            if occ < beatPos { occ += cycleBeats }                            // already passed this pass → next pass
            if occ < end {
                let s = windowStart + Int64(max(0, (occ - beatPos) / beatsPerSample))
                out?.emit(sampleTime: s, cable: loop[i].cable, loop[i].b0, loop[i].b1, loop[i].b2)
            }
        }
    }
}

/// A recording pass-through emitter: forwards to the live sink AND, while recording, captures each event's PASS-RELATIVE
/// beat into the deck. The Kernel sets the block mapping (base beat, beats/sample, cycleBeats, windowStart) each render.
final class ReelTap: MIDIEmitter {
    weak var out: MIDIEmitter?
    weak var deck: ReelDeck?
    var recording = false
    var base = 0.0, beatsPerSample = 0.0, cycleBeats = 1.0
    var windowStart: Int64 = 0
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if recording, cycleBeats > 0, let deck {
            var beat = base + Double(sampleTime - windowStart) * beatsPerSample
            beat -= (beat / cycleBeats).rounded(.down) * cycleBeats           // → pass-relative
            deck.record(beat: beat, cable: cable, b0, b1, b2)
        }
        out?.emit(sampleTime: sampleTime, cable: cable, b0, b1, b2)
    }
}
