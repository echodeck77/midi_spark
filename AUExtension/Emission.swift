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
    /// CELL TAG (Paul 2026-09-03): the render calls this just before a note-ON with the emitting cell's grid index
    /// (col·Snap.rows+row), so the PART roll can filter STRICTLY to the selected rung per column. Default no-op.
    func markCell(_ idx: Int)
}
extension MIDIEmitter { func markColour(_ hue: UInt32) {} ; func markCell(_ idx: Int) {} }   // defaults: ignore the tags

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
    var cycleBeats = 4.0                                           // the LIVE pass length in beats (set by the Kernel each render). Changes with the rate/HALFTIME.
    // A pass's length is fixed when it's FILED — the rate can change afterwards, so each stored pass carries its own
    // cycle, and `loop`/export/roll read `loopCycle` (the SELECTED or latest pass's length), NOT the live `cycleBeats`.
    // Else a pass recorded at one rate, exported after a rate change, gets the wrong loop length (Paul 2026-08-24).
    private(set) var loopCycle = 4.0
    private var histCycle = [Double](repeating: 4.0, count: histCount)

    // THE PASS-HISTORY RING (Paul 2026-08-19) — the pop-up pass browser keeps the last `histCount` completed passes.
    // A single flat buffer (one allocation, off the render thread) sliced `histCap` events per pass; pass p lives in
    // slot `p % histCount` (so a passNo maps straight to its slot). `loop` remains the SELECTED pass (replay + export).
    // 64 passes kept, 32 per browser page (top 4 rows, 8×4) → the pass browser PAGINATES (Paul 2026-08-26). histCount×histCap
    // is MEMORY-NEUTRAL vs the old 32×8192 (both = 262 144 event slots); 4096 events/pass stays above the flood-governor's
    // worst-case ~3k/bar, so no new truncation. Bump these as a pair to keep memory constant.
    static let histCount = 64                                      // passes kept (2 browser pages of 32)
    static let histCap = 4096                                      // events stored per pass (dense-pass overflow drops, as `cap` already does)
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
        histLen[slot] = n; histPassNo[slot] = passCounter; histCycle[slot] = cycleBeats   // remember the rate this pass was filed at
        passCounter += 1
        if selectedPassNo < 0 { loopN = min(curN, ReelDeck.cap); for i in 0..<loopN { loop[i] = cur[i] }; loopCycle = cycleBeats; closeOpenLoopNotes() }   // auto: latest → loop
    }

    // CR-5[review]: a pass's note-OFF can be missing from `loop` — truncated at `histCap` when re-selected from the browser,
    // OR simply because the note is held across the pass boundary (its off lives in the NEXT pass). Either way the looping
    // replay() would re-emit an ON with no OFF ⇒ a stuck note (invariant 4). Close every note still open at the loop end by
    // appending a synthetic OFF at `cycleBeats`, so the note re-strikes each loop instead of hanging. Fixed scratch, no alloc
    // (this runs once per promote/select, off the per-window render path). Uses the last-set `cycleBeats` (a step-rate change
    // is rare and self-corrects on the next promote/select).
    private var openStatus = [UInt8](repeating: 0xFF, count: 4 * 128)   // per (cable 1–4, note) the open ON's status byte; 0xFF = closed
    private func closeOpenLoopNotes() {
        for i in openStatus.indices { openStatus[i] = 0xFF }
        for i in 0..<loopN {
            let e = loop[i]
            guard e.cable >= 1, e.cable <= 4 else { continue }
            let k = Int(e.cable - 1) * 128 + Int(e.b1 & 0x7F)
            let isOn = (e.b0 & 0xF0) == 0x90 && e.b2 > 0
            let isOff = (e.b0 & 0xF0) == 0x80 || ((e.b0 & 0xF0) == 0x90 && e.b2 == 0)
            if isOn { openStatus[k] = e.b0 } else if isOff { openStatus[k] = 0xFF }
        }
        let off = max(0.0, loopCycle)                                  // close at the SELECTED pass's own length (not the live rate)
        for k in openStatus.indices where openStatus[k] != 0xFF && loopN < ReelDeck.cap {
            let cable = UInt8(k / 128 + 1), note = UInt8(k % 128), status = 0x80 | (openStatus[k] & 0x0F)
            loop[loopN] = Ev(beat: off, cable: cable, b0: status, b1: note, b2: 0); loopN += 1
        }
    }
    func clear() { curN = 0; loopN = 0; state = .off; passCounter = 0; selectedPassNo = -1; loopCycle = cycleBeats
        for i in 0..<ReelDeck.histCount { histLen[i] = 0; histPassNo[i] = -1; histCycle[i] = cycleBeats } }

    /// The `histCount` ring slots as pass numbers, OLDEST→NEWEST (the last index = the most recent completed pass; −1 =
    /// empty). The pass browser filters these to non-empty, then paginates 32 per page.
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
    /// A content SIGNATURE per pass, aligned with `passNumbers()` (oldest→newest; empty slot → 0). Two passes whose
    /// emitted note-ONs match (rounded timing · cable · pitch · velocity) hash EQUAL — the pass browser's REMOVE
    /// DUPLICATES toggle collapses runs that share a signature (e.g. a held loop filing the same bar every pass).
    /// Offs + the colour tag are excluded (musical content = the notes). Read while browsing (tape frozen) — no race.
    func passSignatures() -> [UInt64] {
        var out = [UInt64](repeating: 0, count: ReelDeck.histCount)
        for k in 0..<ReelDeck.histCount {
            let p = passCounter - 1 - k                            // newest first (mirrors passNumbers)
            guard p >= 0 else { break }
            let slot = p % ReelDeck.histCount
            guard histPassNo[slot] == p, histLen[slot] > 0 else { continue }
            var h: UInt64 = 0xcbf2_9ce4_8422_2325                  // FNV-1a offset basis
            let base = slot * ReelDeck.histCap
            for i in 0..<histLen[slot] {
                let e = hist[base + i]
                guard (e.b0 & 0xF0) == 0x90, e.b2 > 0 else { continue }   // note-ONs only
                let bq = UInt64(bitPattern: Int64((e.beat * 480.0).rounded()))   // quantise beat → float-noise-proof
                h = (h ^ bq) &* 0x100_0000_01b3
                h = (h ^ (UInt64(e.cable) << 16 | UInt64(e.b1) << 8 | UInt64(e.b2))) &* 0x100_0000_01b3
            }
            out[ReelDeck.histCount - 1 - k] = h
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
        loopCycle = histCycle[slot]   // the pinned pass's OWN length (the rate may have changed since)
        closeOpenLoopNotes()          // CR-5[review]: a truncated / boundary-held pass must not strand a note-OFF
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
    /// EXPORT a RANGE of passes as ONE phrase (Paul 2026-08-26): concatenate every NON-EMPTY pass in [lo, hi] back-to-back,
    /// each pass's beats offset by the cumulative length of the passes before it — so a phrase longer than one pass
    /// (input twice a bar → two passes) exports whole, and a note held across a boundary reunites (its ON in pass N,
    /// its OFF in pass N+1, offset correctly). Returns the combined events on `cables` + the total length in beats.
    func exportRangeEvents(fromPass lo: Int, toPass hi: Int, cables: Set<UInt8>) -> (events: [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)], totalBeats: Double) {
        var out: [(beat: Double, b0: UInt8, b1: UInt8, b2: UInt8)] = []
        var offset = 0.0
        var p = min(lo, hi); let end = max(lo, hi)
        while p <= end {
            if p >= 0 {
                let slot = ((p % ReelDeck.histCount) + ReelDeck.histCount) % ReelDeck.histCount
                if histPassNo[slot] == p, histLen[slot] > 0 {
                    let base = slot * ReelDeck.histCap
                    for i in 0..<histLen[slot] {
                        let e = hist[base + i]
                        if cables.contains(e.cable) { out.append((offset + e.beat, e.b0, e.b1, e.b2)) }
                    }
                    offset += histCycle[slot]   // advance the phrase clock by THIS pass's own length
                }
            }
            p += 1
        }
        return (out, offset)
    }
    /// The drawable notes for a RANGE of passes (Paul 2026-08-26): concatenated + offset like exportRangeEvents, so the
    /// pop-up roll shows the WHOLE selected phrase (not just one cell). Notes held across a pass boundary reunite. Cables
    /// 1–4 only. Returns the notes + the total length in beats (the roll's x-axis span).
    func rangeRoll(fromPass lo: Int, toPass hi: Int) -> (notes: [Note], totalBeats: Double) {
        var out: [Note] = []
        var open: [Int: (start: Double, vel: UInt8, colour: UInt32)] = [:]
        var offset = 0.0
        var p = min(lo, hi); let end = max(lo, hi)
        while p <= end {
            if p >= 0 {
                let slot = ((p % ReelDeck.histCount) + ReelDeck.histCount) % ReelDeck.histCount
                if histPassNo[slot] == p, histLen[slot] > 0 {
                    let base = slot * ReelDeck.histCap
                    for i in 0..<histLen[slot] {
                        let e = hist[base + i]
                        guard e.cable >= 1, e.cable <= 4 else { continue }
                        let key = Int(e.cable) << 8 | Int(e.b1)
                        let isOn = (e.b0 & 0xF0) == 0x90 && e.b2 > 0
                        let isOff = (e.b0 & 0xF0) == 0x80 || ((e.b0 & 0xF0) == 0x90 && e.b2 == 0)
                        if isOn { open[key] = (offset + e.beat, e.b2, e.colour) }
                        else if isOff, let o = open.removeValue(forKey: key) {
                            out.append(Note(cable: e.cable, note: e.b1, vel: o.vel, start: o.start, end: max(o.start, offset + e.beat), colour: o.colour))
                        }
                    }
                    offset += histCycle[slot]
                }
            }
            p += 1
        }
        for (key, o) in open { out.append(Note(cable: UInt8(key >> 8), note: UInt8(key & 0xFF), vel: o.vel, start: o.start, end: max(o.start, offset), colour: o.colour)) }
        return (out, offset)
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

// MARK: - THE PART ROLL (Paul 2026-09-02) — a live per-PART-cycle tape of the emitted output, for the part-page piano
// roll. Distinct from ReelDeck (the global RECORD tape, gated on host-play + a fixed 8-bar cycle → dead during the BUILD
// free-run audition). This one records the CURRENT part audition, pass-relative to the PART's OWN cycle, so the roll is
// true + aligned for both 8 and 16 width. A completed non-empty cycle becomes the stable drawn roll (`last`); an empty
// cycle leaves the previous roll as a dim GHOST (so "no input" shows the last pattern dim, not blank). Foundation-only,
// unit-testable. Read on the main thread (benign staleness, like the reel readers).
final class PartRollDeck {
    struct Ev: Equatable { var beat = 0.0; var cable: UInt8 = 0; var b0: UInt8 = 0; var b1: UInt8 = 0; var b2: UInt8 = 0; var colour: UInt32 = 0; var cell: Int = -1 }
    static let cap = 4096
    // THREAD MODEL (the 2026-08-10 flat-value-array lesson — no shared reference array crosses threads): the RENDER thread
    // owns `cur`/`curN` for the in-progress cycle. On endCycle a completed cycle is PUBLISHED into the INACTIVE of two flat
    // buffers, then `pubSel` flips (render is the SOLE writer of pubSel). `roll()` runs on the MAIN thread (the 4 Hz poll):
    // it reads the ACTIVE buffer via a VALUE snapshot first, so render never writes a buffer main is reading (double-buffer
    // SPSC). The only cross-thread scalar is `pubSel` (a stale-by-one-cycle read is benign; a torn Int read can't happen on
    // an aligned 64-bit store). This closes the render↔main data race on the drawn roll.
    private var cur = [Ev](repeating: Ev(), count: cap); private var curN = 0
    private var pubA = [Ev](repeating: Ev(), count: cap); private var pubAN = 0
    private var pubB = [Ev](repeating: Ev(), count: cap); private var pubBN = 0
    private var pubSel = 0                                                    // 0 → A is the published cycle, 1 → B
    func record(beat: Double, cable: UInt8, colour: UInt32, cell: Int = -1, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {   // RENDER
        if curN < PartRollDeck.cap { cur[curN] = Ev(beat: beat, cable: cable, b0: b0, b1: b1, b2: b2, colour: colour, cell: cell); curN += 1 }
    }
    /// A part cycle just completed: PUBLISH a non-empty cycle into the inactive buffer then flip; an empty cycle keeps the
    /// previous published cycle (the dim ghost). Reset `cur`. RENDER thread — never writes the buffer main is reading.
    func endCycle() {                                                        // RENDER
        if curN > 0 {
            if pubSel == 0 { for i in 0..<curN { pubB[i] = cur[i] }; pubBN = curN; pubSel = 1 }
            else           { for i in 0..<curN { pubA[i] = cur[i] }; pubAN = curN; pubSel = 0 }
        }
        curN = 0
    }
    func beginRecording() { curN = 0 }                                      // RENDER — reset the in-progress scratch on the recording rising edge (so MAIN never writes curN)
    func clear() { pubAN = 0; pubBN = 0 }                                    // MAIN — blank the PUBLISHED buffers only; `cur`/`curN` are RENDER-owned (reset by beginRecording), so no thread ever writes them concurrently. endCycle is gated off (partRollActive false) while this runs, so the pub zero can't race a publish.
    struct Note: Equatable { var cable: UInt8; var note: UInt8; var vel: UInt8; var start: Double; var end: Double; var colour: UInt32 = 0; var cell: Int = -1 }   // `cell` = the emitting cell's grid index (for the per-rung filter)
    /// Pair on/off in the last PUBLISHED cycle → drawable notes over [0, cycleBeats]. A note still open at cycle end holds
    /// to `cycleBeats` (the loop wraps it). Cables 1–4 only (0 = the All duplicate). MAIN thread: snapshots the active buffer
    /// by VALUE first (render only ever writes the inactive one) → no torn read. (Mirrors ReelDeck.selectedRoll.)
    func roll(cycleBeats: Double) -> [Note] {                               // MAIN
        let s = pubSel                                                       // pick the published buffer (single scalar read)
        let n = s == 0 ? pubAN : pubBN
        var snap = [Ev](); snap.reserveCapacity(n)
        if s == 0 { for i in 0..<n { snap.append(pubA[i]) } } else { for i in 0..<n { snap.append(pubB[i]) } }
        var out: [Note] = []
        var open: [Int: (start: Double, vel: UInt8, colour: UInt32, cell: Int)] = [:]   // key = cable<<8 | note
        for e in snap {
            guard e.cable >= 1, e.cable <= 4 else { continue }
            let key = Int(e.cable) << 8 | Int(e.b1)
            let isOn = (e.b0 & 0xF0) == 0x90 && e.b2 > 0
            let isOff = (e.b0 & 0xF0) == 0x80 || ((e.b0 & 0xF0) == 0x90 && e.b2 == 0)
            if isOn { open[key] = (e.beat, e.b2, e.colour, e.cell) }
            else if isOff, let o = open.removeValue(forKey: key) {
                out.append(Note(cable: e.cable, note: e.b1, vel: o.vel, start: o.start, end: max(o.start, e.beat), colour: o.colour, cell: o.cell))
            }
        }
        for (key, o) in open {
            out.append(Note(cable: UInt8(key >> 8), note: UInt8(key & 0xFF), vel: o.vel, start: o.start, end: max(o.start, cycleBeats), colour: o.colour, cell: o.cell))
        }
        return out
    }
}
// The part-roll's emit tap — wraps the live emitter (or the reel tap), records each emitted event to a PartRollDeck with
// a PART-cycle-relative beat, forwards downstream. `markColour` carries the sounding cell's colour AND forwards it on.
final class PartTap: MIDIEmitter {
    weak var out: MIDIEmitter?
    weak var deck: PartRollDeck?
    var recording = false
    var base = 0.0, beatsPerSample = 0.0, cycleBeats = 1.0
    var windowStart: Int64 = 0
    private var pendingColour: UInt32 = 0
    private var pendingCell: Int = -1
    func markColour(_ hue: UInt32) { pendingColour = hue; out?.markColour(hue) }   // forward so the reel still gets the colour
    func markCell(_ idx: Int) { pendingCell = idx; out?.markCell(idx) }            // the emitting cell — for the PART roll's per-rung filter
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if recording, cycleBeats > 0, let deck {
            var beat = base + Double(sampleTime - windowStart) * beatsPerSample
            beat -= (beat / cycleBeats).rounded(.down) * cycleBeats           // → PART-cycle-relative
            deck.record(beat: beat, cable: cable, colour: pendingColour, cell: pendingCell, b0, b1, b2)
        }
        out?.emit(sampleTime: sampleTime, cable: cable, b0, b1, b2)
    }
}

/// OFFLINE PART ROLL (Paul 2026-09-03): run the REAL Router over `box` for ONE pass against a held-input snapshot, recording
/// each emitted note with its emitting-cell tag. DETERMINISTIC + IMMEDIATE — the part's exact output for `held`, with NO
/// cycle lag and no dependence on live audio (fixes the "shows nothing / octave-vs-notation lag" class). Foundation-only,
/// unit-testable (Kernel-free). The caller CLONES the live pools first (thread-safe). Returns paired notes over [0, cyc].
func renderOfflinePartRoll(box: SnapshotBox, pool: NotePool, latched: [NotePool], latchMask: UInt8, cyc: Double) -> [PartRollDeck.Note] {
    guard cyc > 0 else { return [] }
    let router = Router(); var diag = KernelDiag()
    let deck = PartRollDeck(); let tap = PartTap()
    tap.deck = deck; tap.recording = true; tap.cycleBeats = cyc; tap.base = 0; tap.windowStart = 0
    let sr = 48_000.0, tempo = 120.0
    let bps = tempo / 60.0 / sr
    tap.beatsPerSample = bps
    let frames: UInt32 = 1024                         // blocks small enough to advance columns; onsets stay sample-accurate
    let wb = Double(frames) * bps
    var beat = 0.0, ts = 0.0
    while beat < cyc {
        router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: tempo, sampleRate: sr,
                       timestampSample: ts, frameCount: frames, latchMask: latchMask, latchedPools: latched, out: tap, diag: &diag)
        beat += wb; ts += Double(frames)
    }
    deck.endCycle()
    return deck.roll(cycleBeats: cyc)
}

// MARK: - THE DOOR RING (config-sheets REPLAY, Paul 2026-08-20) — a per-door ring of INCOMING note events.
// The input-side twin of ReelDeck. A door records its live input CONTINUOUSLY (retro-capture — never arm). In REPLAY
// mode the last N passes are CAPTURED as a loop that cycles back as the door's living input: each render asks
// `notesSoundingAt(phase)` for the pool. Foundation-only, unit-testable; pure query (no accumulation → replay-safe).
final class DoorRing {
    struct Ev: Equatable { var beat = 0.0; var note: UInt8 = 0; var vel: UInt8 = 0; var on = false; var chan: UInt8 = 0 }
    static let cap = 4096
    private var buf = [Ev](repeating: Ev(), count: cap)   // circular record of recent input (ABSOLUTE beat)
    private var head = 0, count = 0
    private var loop = [Ev](repeating: Ev(), count: cap)  // the captured playback loop (beats re-based to [0, loopLen))
    private(set) var loopN = 0
    private(set) var loopLen = 0.0                        // the loop length in beats (0 ⇒ nothing captured)
    var hasLoop: Bool { loopLen > 0 }
    // Reused scratch for notesSoundingAt (Paul 2026-09-01 refactor): it's a per-render call (Kernel.updateLatchedPools for
    // every engaged REPLAY/FILE door) — hoist its two 128-slot tables off the stack to avoid a per-render heap alloc
    // (invariant 3). Render-thread-only (loopRoll, the 4 Hz reader, uses its own local dict), reset at the top of each call.
    private var soundVelScratch = [Int16](repeating: -1, count: 128)
    private var soundChanScratch = [UInt8](repeating: 0, count: 128)

    /// Append a live note event at absolute `beat` (evict-oldest when full). CHANNEL-PRESERVING (Paul 2026-08-22): the
    /// note's incoming channel is recorded so replay re-emits it on its ORIGINAL channel — matching the live latch
    /// (captureFiltered) — so a channel-filtered cell admits the replayed loop just as it did the live input.
    func record(beat: Double, note: UInt8, vel: UInt8, on: Bool, chan: UInt8 = 0) {
        buf[head] = Ev(beat: beat, note: note, vel: vel, on: on, chan: chan)
        head = (head + 1) % DoorRing.cap
        count = min(count + 1, DoorRing.cap)
    }
    private func ordered(_ i: Int) -> Ev { buf[(head - count + i + DoorRing.cap * 2) % DoorRing.cap] }   // i: 0…count-1, oldest→newest

    /// Capture the events in the last `lengthBeats` (ending at `endBeat`) as the playback loop, re-based to [0, len).
    /// A note the hands were ALREADY HOLDING when the window opens has its note-on BEFORE `start` (outside the window),
    /// so it would be lost — the "REPLAY sometimes silent" bug. Fix (Paul 2026-08-21): seed beat-0 note-ons for every
    /// note SOUNDING at `start`, so a sustained chord loops from the top instead of vanishing.
    func capture(endBeat: Double, lengthBeats: Double) {
        loopN = 0; loopLen = max(0, lengthBeats)
        guard lengthBeats > 0 else { return }
        let start = endBeat - lengthBeats
        // 1) notes held across the window start → inject as beat-0 ons (their last on/off before `start` is an ON)
        var heldVel = [Int16](repeating: -1, count: 128)
        var heldChan = [UInt8](repeating: 0, count: 128)                  // preserve the held note's channel for its beat-0 seed
        for i in 0..<count {
            let e = ordered(i)
            if e.beat >= start { break }
            if e.note < 128 {
                if e.on && e.vel > 0 { heldVel[Int(e.note)] = Int16(e.vel); heldChan[Int(e.note)] = e.chan } else { heldVel[Int(e.note)] = -1 }
            }
        }
        for n in 0..<128 where heldVel[n] >= 0 && loopN < DoorRing.cap { loop[loopN] = Ev(beat: 0, note: UInt8(n), vel: UInt8(heldVel[n]), on: true, chan: heldChan[n]); loopN += 1 }
        // 2) the events inside the window, re-based to [0, len) — time-ordered (the ring records in arrival order)
        for i in 0..<count where loopN < DoorRing.cap {
            let e = ordered(i)
            if e.beat >= start && e.beat < endBeat { loop[loopN] = Ev(beat: e.beat - start, note: e.note, vel: e.vel, on: e.on, chan: e.chan); loopN += 1 }
        }
    }
    func clearLoop() { loopN = 0; loopLen = 0 }
    /// Drop the recorded HISTORY (not the captured loop). The ring records at ABSOLUTE host beats in arrival order, and
    /// both `capture`/`notesSoundingAt` assume arrival order == ascending beat. A transport stop→start or a host loop/seek
    /// makes new events record at beats that overlap/go backward vs the resident history → a garbled, mis-phased capture.
    /// Clear the history on those beat discontinuities so recording restarts monotone. (Paul 2026-08-23)
    func clearHistory() { head = 0; count = 0 }
    /// The oldest recorded event's beat (+∞ if empty) — so a capture can CLAMP its length to the history actually
    /// available and not prepend silent passes when < N passes have been played (Paul 2026-08-23).
    var oldestBeat: Double { count > 0 ? ordered(0).beat : .infinity }

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

    /// The captured loop as drawable NOTES WITH DURATION (Paul 2026-08-23): pair each note-on with its next off; a note
    /// still open at the loop end closes at `loopLen`. Drives the config-sheet REPLAY piano roll so it reflects EXACTLY
    /// what's playing from the RECORDING (durations, held chords) — not live input. Returns fresh value structs (no shared
    /// buffer); `loop` is a fixed-size value array written only on capture, so a main-thread read at 4 Hz is safe off the
    /// render thread (a torn read during a re-capture → a benign garbled bar for one frame). Mirrors ReelDeck.selectedRoll.
    struct Note: Equatable { var note: UInt8; var vel: UInt8; var start: Double; var end: Double; var chan: UInt8 }
    func loopRoll() -> [Note] {
        var out: [Note] = []
        var open = [Int: (start: Double, vel: UInt8, chan: UInt8)]()   // key = note number
        for i in 0..<loopN {
            let e = loop[i]
            if e.on && e.vel > 0 { open[Int(e.note)] = (e.beat, e.vel, e.chan) }
            else if let o = open.removeValue(forKey: Int(e.note)) {
                out.append(Note(note: e.note, vel: o.vel, start: o.start, end: max(o.start, e.beat), chan: o.chan))
            }
        }
        for (n, o) in open { out.append(Note(note: UInt8(n), vel: o.vel, start: o.start, end: max(o.start, loopLen), chan: o.chan)) }   // still sounding at loop end → hold to length
        return out
    }
    /// The notes SOUNDING at loop `phase` ∈ [0, loopLen): each note's LAST on/off at or before `phase` wins (on ⇒
    /// sounding). Events are time-ordered (recorded in arrival order). Writes into `outNote`/`outVel`, returns the count.
    @discardableResult func notesSoundingAt(_ phase: Double, outNote: inout [UInt8], outVel: inout [UInt8], outChan: inout [UInt8]) -> Int {
        // Mutate the reused instance scratch DIRECTLY (a local `var` copy would trigger COW = the alloc we're avoiding).
        for i in 0..<128 { soundVelScratch[i] = -1; soundChanScratch[i] = 0 }   // -1 = not sounding
        for i in 0..<loopN {
            let e = loop[i]
            if e.beat > phase { break }
            if e.note < 128 {
                if e.on && e.vel > 0 { soundVelScratch[Int(e.note)] = Int16(e.vel); soundChanScratch[Int(e.note)] = e.chan } else { soundVelScratch[Int(e.note)] = -1 }
            }
        }
        var k = 0
        for n in 0..<128 where soundVelScratch[n] >= 0 && k < outNote.count {
            outNote[k] = UInt8(n); outVel[k] = UInt8(soundVelScratch[n]); if k < outChan.count { outChan[k] = soundChanScratch[n] }; k += 1
        }
        return k
    }
}
