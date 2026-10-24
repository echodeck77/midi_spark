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
    /// MACHINE TAG (Paul 2026-08-19): the render calls this just before a note-ON emit with the sounding cell's DISPLAY
    /// hue (packed RGB), so the reel can paint each recorded note its machine. Default no-op — only the ReelTap cares.
    func markHue(_ hue: UInt32)
    /// CELL TAG (Paul 2026-09-03): the render calls this just before a note-ON with the emitting cell's grid index
    /// (col·Snap.rows+row), so the PART roll can filter STRICTLY to the selected rung per column. Default no-op.
    func markCell(_ idx: Int)
}
extension MIDIEmitter { func markHue(_ hue: UInt32) {} ; func markCell(_ idx: Int) {} }   // defaults: ignore the tags

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
    struct Ev: Equatable { var beat = 0.0; var cable: UInt8 = 0; var b0: UInt8 = 0; var b1: UInt8 = 0; var b2: UInt8 = 0; var machine: UInt32 = 0 }
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
    // WAS memory-neutral vs the old 32×8192 (both 262 144 slots) at 4096 events/pass, above the 8×8 flood-governor's worst-case
    // ~3k/bar. FOURFOLD REEL LINK (2026-10-23): a busy Fourfold pass (4 lanes of 1/32 chords with ratchets) measured past 4096
    // and lost its tail silently, so the cap is 8192 — 64 × 8192 × 16 B = 8 MB of event slots (was 4 MB), allocated once off the
    // render thread. Still a ceiling, not a guarantee: past it the overflow drops, exactly as `cap` already does.
    static let histCount = 64                                      // passes kept (2 browser pages of 32)
    static let histCap = 8192                                      // events stored per pass (dense-pass overflow drops, as `cap` already does)
    private var hist = [Ev](repeating: Ev(), count: histCount * histCap)
    private var histLen = [Int](repeating: 0, count: histCount)    // events in each slot (0 = empty)
    private var histPassNo = [Int](repeating: -1, count: histCount)// absolute pass number stored in each slot
    private(set) var passCounter = 0                               // monotone COMPLETED-pass count (next pass = this value)
    private(set) var selectedPassNo = -1                          // the pinned selection (−1 = auto: `loop` tracks the latest)

    func record(beat: Double, cable: UInt8, machine: UInt32 = 0, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if curN < ReelDeck.cap { cur[curN] = Ev(beat: beat, cable: cable, b0: b0, b1: b1, b2: b2, machine: machine); curN += 1 }
    }
    /// Begin recording a new pass. `pass` (the Kernel's pass number for it) seeds the new pass with the events the tape set aside for it —
    /// those the render emitted, for this pass's own first beats, in the LAST window of the pass before (see `recordNext`); a carry for any
    /// other pass (a loop jump, a stop in between) is dropped. No argument = no seeding (and any carry is dropped).
    func startPass(pass: Int? = nil) {
        curN = 0
        if let pass, pass == carryPass, carryN > 0 {
            let n = min(carryN, ReelDeck.cap)
            for i in 0..<n { cur[i] = carry[i] }
            curN = n
        }
        carryN = 0; carryPass = Int.min
    }
    // FOURFOLD REEL LINK (2026-10-23) — THE PASS-BOUNDARY CARRY. The Kernel changes pass at the first window that STARTS in the new pass, but a
    // hit sitting exactly ON the boundary (every downbeat hit, and nearly every Fourfold lane has one) is emitted by the window that CONTAINS the
    // boundary — the last window of the OLD pass — so it used to be filed there, wrapped to beat 0, as a stray note at the old pass's start (its
    // note-off then landed in the new pass: an orphan off, a doubled on, and a downbeat that exported a whole pass early). `ReelTap` now sets such
    // events aside here, tagged with the pass they belong to, and `startPass(pass:)` files them at the head of that pass. Fixed storage, no allocation.
    static let carryCap = 1024
    private var carry = [Ev](repeating: Ev(), count: carryCap); private(set) var carryN = 0; private(set) var carryPass = Int.min
    func recordNext(pass: Int, beat: Double, cable: UInt8, machine: UInt32 = 0, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if carryN > 0, carryPass != pass { carryN = 0 }
        carryPass = pass
        if carryN < ReelDeck.carryCap { carry[carryN] = Ev(beat: beat, cable: cable, b0: b0, b1: b1, b2: b2, machine: machine); carryN += 1 }
    }
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
    func clear() { curN = 0; carryN = 0; carryPass = Int.min; loopN = 0; state = .off; passCounter = 0; selectedPassNo = -1; loopCycle = cycleBeats
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
    /// Offs + the machine tag are excluded (musical content = the notes). Read while browsing (tape frozen) — no race.
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
    struct Note: Equatable { var cable: UInt8; var note: UInt8; var vel: UInt8; var start: Double; var end: Double; var machine: UInt32 = 0 }
    func selectedRoll() -> [Note] {
        var out: [Note] = []
        var open: [Int: (start: Double, vel: UInt8, machine: UInt32)] = [:]   // key = cable<<8 | note
        for i in 0..<loopN {
            let e = loop[i]
            guard e.cable >= 1, e.cable <= 4 else { continue }
            let key = Int(e.cable) << 8 | Int(e.b1)
            let isOn = (e.b0 & 0xF0) == 0x90 && e.b2 > 0
            let isOff = (e.b0 & 0xF0) == 0x80 || ((e.b0 & 0xF0) == 0x90 && e.b2 == 0)
            if isOn { open[key] = (e.beat, e.b2, e.machine) }       // the note-ON carries the sounding cell's machine
            else if isOff, let o = open.removeValue(forKey: key) {
                out.append(Note(cable: e.cable, note: e.b1, vel: o.vel, start: o.start, end: max(o.start, e.beat), machine: o.machine))
            }
        }
        for (key, o) in open {                                    // still sounding at the pass end → close at the loop length
            out.append(Note(cable: UInt8(key >> 8), note: UInt8(key & 0xFF), vel: o.vel, start: o.start, end: max(o.start, cycleBeats), machine: o.machine))
        }
        return out
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
        var open: [Int: (start: Double, vel: UInt8, machine: UInt32)] = [:]
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
                        if isOn { open[key] = (offset + e.beat, e.b2, e.machine) }
                        else if isOff, let o = open.removeValue(forKey: key) {
                            out.append(Note(cable: e.cable, note: e.b1, vel: o.vel, start: o.start, end: max(o.start, offset + e.beat), machine: o.machine))
                        }
                    }
                    offset += histCycle[slot]
                }
            }
            p += 1
        }
        for (key, o) in open { out.append(Note(cable: UInt8(key >> 8), note: UInt8(key & 0xFF), vel: o.vel, start: o.start, end: max(o.start, offset), machine: o.machine)) }
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
    private var pendingMachine: UInt32 = 0            // set by the render right before each note-ON (markHue)
    func markHue(_ hue: UInt32) { pendingMachine = hue }
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if recording, cycleBeats > 0, let deck {
            var beat = base + Double(sampleTime - windowStart) * beatsPerSample
            // An event that sounds in the pass AFTER this window's (the window contains the boundary) belongs to that pass, not this one — see `ReelDeck.recordNext`.
            // The 1e-6-beat nudge (≈ 0.03 sample) keeps a hit computed a hair under the boundary on its right side.
            let windowPass = (base / cycleBeats).rounded(.down)
            let eventPass = ((beat + 1e-6) / cycleBeats).rounded(.down)
            if eventPass == windowPass + 1 {
                deck.recordNext(pass: Int(eventPass), beat: max(0, beat - eventPass * cycleBeats), cable: cable, machine: pendingMachine, b0, b1, b2)
            } else {
                beat -= (beat / cycleBeats).rounded(.down) * cycleBeats       // → pass-relative
                deck.record(beat: beat, cable: cable, machine: pendingMachine, b0, b1, b2)
            }
        }
        out?.emit(sampleTime: sampleTime, cable: cable, b0, b1, b2)
    }
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
    /// The oldest recorded event's beat (+∞ if empty) — so a capture can CLAMP its length to the history actually
    /// available and not prepend silent passes when < N passes have been played (Paul 2026-08-23).


    /// The captured loop as drawable NOTES WITH DURATION (Paul 2026-08-23): pair each note-on with its next off; a note
    /// still open at the loop end closes at `loopLen`. Drives the config-sheet REPLAY piano roll so it reflects EXACTLY
    /// what's playing from the RECORDING (durations, held chords) — not live input. Returns fresh value structs (no shared
    /// buffer); `loop` is a fixed-size value array written only on capture, so a main-thread read at 4 Hz is safe off the
    /// render thread (a torn read during a re-capture → a benign garbled bar for one frame). Mirrors ReelDeck.selectedRoll.
    struct Note: Equatable { var note: UInt8; var vel: UInt8; var start: Double; var end: Double; var chan: UInt8 }
}
