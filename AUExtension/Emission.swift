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
    /// COLOUR TAG (Paul 2026-08-19): the render calls this just before a note-ON emit with the sounding cell's DISPLAY
    /// hue (packed RGB), so the reel can paint each recorded note its colour. Default no-op — only the ReelTap cares.
    func markColour(_ hue: UInt32)
}
extension MIDIEmitter { func markColour(_ hue: UInt32) {} }   // default: ignore the colour tag

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
    struct Ev: Equatable { var beat = 0.0; var cable: UInt8 = 0; var b0: UInt8 = 0; var b1: UInt8 = 0; var b2: UInt8 = 0; var colour: UInt32 = 0 }
    static let cap = 16384
    private(set) var cur = [Ev](repeating: Ev(), count: cap); private(set) var curN = 0
    private(set) var loop = [Ev](repeating: Ev(), count: cap); private(set) var loopN = 0
    var hasLoop: Bool { loopN > 0 }
    var cycleBeats = 4.0                                           // the current pass length in beats (set by the Kernel; used to close open notes in the roll)

    // THE PASS-HISTORY RING (Paul 2026-08-19) — the pop-up pass browser keeps the last `histCount` completed passes.
    // A single flat buffer (one allocation, off the render thread) sliced `histCap` events per pass; pass p lives in
    // slot `p % histCount` (so a passNo maps straight to its slot). `loop` remains the SELECTED pass (replay + export).
    static let histCount = 32                                      // passes kept — fills the pop-up's top 4 rows (8×4)
    static let histCap = 8192                                      // events stored per pass (dense-pass overflow drops, as `cap` already does)
    private var hist = [Ev](repeating: Ev(), count: histCount * histCap)
    private var histLen = [Int](repeating: 0, count: histCount)    // events in each slot (0 = empty)
    private var histPassNo = [Int](repeating: -1, count: histCount)// absolute pass number stored in each slot
    private(set) var passCounter = 0                               // monotone COMPLETED-pass count (next pass = this value)
    private(set) var selectedPassNo = -1                          // the pinned selection (−1 = auto: `loop` tracks the latest)

    func record(beat: Double, cable: UInt8, colour: UInt32 = 0, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if curN < ReelDeck.cap { cur[curN] = Ev(beat: beat, cable: cable, b0: b0, b1: b1, b2: b2, colour: colour); curN += 1 }
    }
    func startPass() { curN = 0 }
    /// A pass just finished: file it into the ring, and — unless a pass is PINNED (manually selected) — make it the loop.
    func promote() {
        let slot = passCounter % ReelDeck.histCount
        let n = min(curN, ReelDeck.histCap)
        for i in 0..<n { hist[slot * ReelDeck.histCap + i] = cur[i] }
        histLen[slot] = n; histPassNo[slot] = passCounter
        passCounter += 1
        if selectedPassNo < 0 { loopN = min(curN, ReelDeck.cap); for i in 0..<loopN { loop[i] = cur[i] } }   // auto: latest → loop
    }
    func clear() { curN = 0; loopN = 0; state = .off; passCounter = 0; selectedPassNo = -1
        for i in 0..<ReelDeck.histCount { histLen[i] = 0; histPassNo[i] = -1 } }

    /// The 32 ring slots as pass numbers, OLDEST→NEWEST (index 31 = the most recent completed pass; −1 = empty).
    /// The pop-up lays these out in reading order so the newest lands bottom-right of the top 4×8 block.
    func passNumbers() -> [Int] {
        var out = [Int](repeating: -1, count: ReelDeck.histCount)
        for k in 0..<ReelDeck.histCount {
            let p = passCounter - 1 - k                            // newest first
            guard p >= 0 else { break }
            let slot = p % ReelDeck.histCount
            if histPassNo[slot] == p, histLen[slot] > 0 { out[ReelDeck.histCount - 1 - k] = p }
        }
        return out
    }
    /// Pin `passNo` as the loop (copy its ring slot into `loop`). Returns false if that pass is no longer in the ring.
    func selectPass(_ passNo: Int) -> Bool {
        guard passNo >= 0 else { return false }
        let slot = passNo % ReelDeck.histCount
        guard histPassNo[slot] == passNo, histLen[slot] > 0 else { return false }
        loopN = min(histLen[slot], ReelDeck.cap)
        for i in 0..<loopN { loop[i] = hist[slot * ReelDeck.histCap + i] }
        selectedPassNo = passNo
        return true
    }
    func clearSelection() { selectedPassNo = -1 }                 // resume auto: `loop` tracks the latest again

    /// One drawable note per (cable,note) on/off pair in the SELECTED pass — for the pop-up piano roll. Cables 1–4
    /// only (0 = the All duplicate). A note still open at the pass end closes at `cycleBeats`; an unmatched off is dropped.
    struct Note: Equatable { var cable: UInt8; var note: UInt8; var vel: UInt8; var start: Double; var end: Double; var colour: UInt32 = 0 }
    func selectedRoll() -> [Note] {
        var out: [Note] = []
        var open: [Int: (start: Double, vel: UInt8, colour: UInt32)] = [:]   // key = cable<<8 | note
        for i in 0..<loopN {
            let e = loop[i]
            guard e.cable >= 1, e.cable <= 4 else { continue }
            let key = Int(e.cable) << 8 | Int(e.b1)
            let isOn = (e.b0 & 0xF0) == 0x90 && e.b2 > 0
            let isOff = (e.b0 & 0xF0) == 0x80 || ((e.b0 & 0xF0) == 0x90 && e.b2 == 0)
            if isOn { open[key] = (e.beat, e.b2, e.colour) }       // the note-ON carries the sounding cell's colour
            else if isOff, let o = open.removeValue(forKey: key) {
                out.append(Note(cable: e.cable, note: e.b1, vel: o.vel, start: o.start, end: max(o.start, e.beat), colour: o.colour))
            }
        }
        for (key, o) in open {                                    // still sounding at the pass end → close at the loop length
            out.append(Note(cable: UInt8(key >> 8), note: UInt8(key & 0xFF), vel: o.vel, start: o.start, end: max(o.start, cycleBeats), colour: o.colour))
        }
        return out
    }
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
    private var pendingColour: UInt32 = 0            // set by the render right before each note-ON (markColour)
    func markColour(_ hue: UInt32) { pendingColour = hue }
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if recording, cycleBeats > 0, let deck {
            var beat = base + Double(sampleTime - windowStart) * beatsPerSample
            beat -= (beat / cycleBeats).rounded(.down) * cycleBeats           // → pass-relative
            deck.record(beat: beat, cable: cable, colour: pendingColour, b0, b1, b2)
        }
        out?.emit(sampleTime: sampleTime, cable: cable, b0, b1, b2)
    }
}

// MARK: - THE DOOR RING (config-sheets REPLAY, Paul 2026-08-20) — a per-door ring of INCOMING note events.
// The input-side twin of ReelDeck. A door records its live input CONTINUOUSLY (retro-capture — never arm). In REPLAY
// mode the last N passes are CAPTURED as a loop that cycles back as the door's living input: each render asks
// `notesSoundingAt(phase)` for the pool. Foundation-only, unit-testable; pure query (no accumulation → replay-safe).
final class DoorRing {
    struct Ev: Equatable { var beat = 0.0; var note: UInt8 = 0; var vel: UInt8 = 0; var on = false }
    static let cap = 4096
    private var buf = [Ev](repeating: Ev(), count: cap)   // circular record of recent input (ABSOLUTE beat)
    private var head = 0, count = 0
    private var loop = [Ev](repeating: Ev(), count: cap)  // the captured playback loop (beats re-based to [0, loopLen))
    private(set) var loopN = 0
    private(set) var loopLen = 0.0                        // the loop length in beats (0 ⇒ nothing captured)
    var hasLoop: Bool { loopLen > 0 }

    /// Append a live note event at absolute `beat` (evict-oldest when full).
    func record(beat: Double, note: UInt8, vel: UInt8, on: Bool) {
        buf[head] = Ev(beat: beat, note: note, vel: vel, on: on)
        head = (head + 1) % DoorRing.cap
        count = min(count + 1, DoorRing.cap)
    }
    private func ordered(_ i: Int) -> Ev { buf[(head - count + i + DoorRing.cap * 2) % DoorRing.cap] }   // i: 0…count-1, oldest→newest

    /// Capture the events in the last `lengthBeats` (ending at `endBeat`) as the playback loop, re-based to [0, len).
    func capture(endBeat: Double, lengthBeats: Double) {
        loopN = 0; loopLen = max(0, lengthBeats)
        guard lengthBeats > 0 else { return }
        let start = endBeat - lengthBeats
        for i in 0..<count where loopN < DoorRing.cap {
            let e = ordered(i)
            if e.beat >= start && e.beat < endBeat { loop[loopN] = Ev(beat: e.beat - start, note: e.note, vel: e.vel, on: e.on); loopN += 1 }
        }
    }
    func clearLoop() { loopN = 0; loopLen = 0 }

    /// Load an EXTERNAL loop (config-sheets FILE mode): a parsed .mid clip's note events drive the same playback path
    /// as a captured REPLAY loop, so a FILE door reuses `notesSoundingAt`. Events are (beat, note, vel, on), already in
    /// [0, lengthBeats); time-ordered by the caller (MidiFile.decode sorts, off-before-on at ties).
    func loadLoop(_ events: [(beat: Double, note: UInt8, vel: UInt8, on: Bool)], lengthBeats: Double) {
        loopN = 0; loopLen = max(0, lengthBeats)
        for e in events where loopN < DoorRing.cap { loop[loopN] = Ev(beat: e.beat, note: e.note, vel: e.vel, on: e.on); loopN += 1 }
    }
    /// Load from PARALLEL arrays (the box's SnapFileClip carries them) — no allocation, so it's safe to call on the
    /// render thread when the FILE clip changes. Arrays are the same length; caller guarantees ordering. (Paul 2026-08-20)
    func loadLoopParallel(beats: [Double], notes: [UInt8], vels: [UInt8], ons: [Bool], lengthBeats: Double) {
        loopN = 0; loopLen = max(0, lengthBeats)
        let n = min(beats.count, min(notes.count, min(vels.count, ons.count)))
        for k in 0..<n where loopN < DoorRing.cap { loop[loopN] = Ev(beat: beats[k], note: notes[k], vel: vels[k], on: ons[k]); loopN += 1 }
    }

    /// The notes SOUNDING at loop `phase` ∈ [0, loopLen): each note's LAST on/off at or before `phase` wins (on ⇒
    /// sounding). Events are time-ordered (recorded in arrival order). Writes into `outNote`/`outVel`, returns the count.
    @discardableResult func notesSoundingAt(_ phase: Double, outNote: inout [UInt8], outVel: inout [UInt8]) -> Int {
        var velByNote = [Int16](repeating: -1, count: 128)   // -1 = not sounding
        for i in 0..<loopN {
            let e = loop[i]
            if e.beat > phase { break }
            if e.note < 128 { velByNote[Int(e.note)] = (e.on && e.vel > 0) ? Int16(e.vel) : -1 }
        }
        var k = 0
        for n in 0..<128 where velByNote[n] >= 0 && k < outNote.count {
            outNote[k] = UInt8(n); outVel[k] = UInt8(velByNote[n]); k += 1
        }
        return k
    }
}
