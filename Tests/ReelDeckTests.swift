//  ReelDeckTests.swift
//  THE REEL-TO-REEL (Paul 2026-08-18): unit tests for the pure record/replay math (ReelDeck is Foundation-only).

import XCTest

private final class ReelRec: MIDIEmitter {
    struct E: Equatable { var sample: Int64; var cable: UInt8; var b0: UInt8; var b1: UInt8; var b2: UInt8 }
    var events: [E] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        events.append(E(sample: sampleTime, cable: cable, b0: b0, b1: b1, b2: b2))
    }
}

final class ReelDeckTests: XCTestCase {

    func testRecordThenReplayReproducesTheLoopInOrderAndTiming() {
        let deck = ReelDeck()
        deck.record(beat: 0.0, cable: 1, 0x90, 60, 100)   // note on
        deck.record(beat: 1.0, cable: 1, 0x80, 60, 0)     // note off  ← preserved → no stuck note
        deck.record(beat: 2.0, cable: 2, 0x90, 64, 90)
        deck.promote()
        XCTAssertTrue(deck.hasLoop)
        let rec = ReelRec()
        // whole pass [12,16), cycleBeats 4, bps 0.001, windowStart 1000
        deck.replay(beatPos: 12.0, windowBeats: 4.0, cycleBeats: 4.0, beatsPerSample: 0.001, windowStart: 1000, out: rec)
        XCTAssertEqual(rec.events.count, 3)
        XCTAssertEqual(rec.events[0], .init(sample: 1000, cable: 1, b0: 0x90, b1: 60, b2: 100))
        XCTAssertEqual(rec.events[1], .init(sample: 1000 + 1000, cable: 1, b0: 0x80, b1: 60, b2: 0), "the note-OFF replays → no stuck note")
        XCTAssertEqual(rec.events[2], .init(sample: 1000 + 2000, cable: 2, b0: 0x90, b1: 64, b2: 90))
    }

    func testReplayLoopsAcrossThePassBoundary() {
        let deck = ReelDeck()
        deck.record(beat: 0.5, cable: 1, 0x90, 60, 100)   // one pulse at pass-relative 0.5
        deck.promote()
        // a window in pass 1 that straddles the boundary: [4.3, 4.7) → the 0.5 pulse's next occurrence is 4.5, in-window.
        let rec = ReelRec()
        deck.replay(beatPos: 4.3, windowBeats: 0.4, cycleBeats: 4.0, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertEqual(rec.events.count, 1)
        XCTAssertEqual(rec.events[0].sample, Int64((4.5 - 4.3) / 0.001))   // occ 4.5 → sample (4.5−4.3)/bps
    }

    // RATE CHANGE (Paul 2026-08-24): each pass keeps the length it was FILED at — the rate (HALFTIME / step rate) can
    // change afterwards, so a pinned/exported pass must use ITS OWN cycle, not the live one. Else the loop is the wrong
    // length and the exported MIDI comes out garbled.
    func testEachPassKeepsItsOwnCycleAcrossRateChanges() {
        let deck = ReelDeck()
        deck.cycleBeats = 4.0                                     // rate A: a 4-beat bar
        deck.record(beat: 0.0, cable: 1, 0x90, 60, 100); deck.record(beat: 1.0, cable: 1, 0x80, 60, 0)
        deck.promote()                                           // pass 0 filed at cycle 4 → the auto loop
        XCTAssertEqual(deck.loopCycle, 4.0)
        deck.cycleBeats = 8.0                                     // rate HALVED: the bar is now 8 beats
        deck.startPass()
        deck.record(beat: 0.0, cable: 1, 0x90, 62, 100); deck.record(beat: 2.0, cable: 1, 0x80, 62, 0)
        deck.promote()                                          // pass 1 filed at cycle 8 → the auto loop
        XCTAssertEqual(deck.loopCycle, 8.0, "the latest pass's own length")
        XCTAssertTrue(deck.selectPass(0))                       // pin the FIRST pass (recorded at cycle 4)
        XCTAssertEqual(deck.loopCycle, 4.0, "the pinned pass keeps ITS cycle, not the live 8")
    }

    func testEmptyLoopReplaysNothing() {
        let deck = ReelDeck()
        let rec = ReelRec()
        deck.replay(beatPos: 0, windowBeats: 4, cycleBeats: 4, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertTrue(rec.events.isEmpty)
        XCTAssertFalse(deck.hasLoop)
    }

    func testClearDropsTheTape() {
        let deck = ReelDeck()
        deck.record(beat: 0, cable: 1, 0x90, 60, 100); deck.promote()
        deck.state = .replaying
        deck.clear()
        XCTAssertFalse(deck.hasLoop)
        XCTAssertEqual(deck.state, .off)
    }

    // MARK: - THE PASS-HISTORY RING (Paul 2026-08-19)

    /// Record one distinguishable pass (a single note whose pitch encodes the pass) then file + advance.
    private func filePass(_ deck: ReelDeck, note: UInt8) {
        deck.record(beat: 0.0, cable: 1, 0x90, note, 100)
        deck.record(beat: 1.0, cable: 1, 0x80, note, 0)
        deck.promote(); deck.startPass()
    }

    func testHistoryRingKeepsPassesOldestToNewest() {
        let deck = ReelDeck()
        for n in 0..<3 { filePass(deck, note: UInt8(60 + n)) }     // passes 0,1,2
        let nums = deck.passNumbers()
        let last = ReelDeck.histCount - 1
        XCTAssertEqual(nums.count, ReelDeck.histCount)
        XCTAssertEqual(nums[last], 2, "newest is last (bottom-right of the newest page)")
        XCTAssertEqual(nums[last - 1], 1)
        XCTAssertEqual(nums[last - 2], 0)
        XCTAssertEqual(nums[last - 3], -1, "unfilled slots are empty")
    }

    func testSelectPassLoadsThatPassNotTheLatest() {
        let deck = ReelDeck()
        for n in 0..<3 { filePass(deck, note: UInt8(60 + n)) }     // pass 0=note60, 1=note61, 2=note62
        XCTAssertTrue(deck.selectPass(1))
        XCTAssertEqual(deck.selectedPassNo, 1)
        let ev = deck.exportEvents(cables: [1])
        XCTAssertEqual(ev.first?.b1, 61, "loop now holds pass 1's note")
    }

    func testPinnedSelectionSurvivesLaterPromotes() {
        let deck = ReelDeck()
        for n in 0..<2 { filePass(deck, note: UInt8(60 + n)) }
        XCTAssertTrue(deck.selectPass(0))                          // pin the OLD pass
        filePass(deck, note: 99)                                   // a new pass completes
        XCTAssertEqual(deck.exportEvents(cables: [1]).first?.b1, 60, "a pinned pass is not overwritten by a later promote")
        deck.clearSelection()
        filePass(deck, note: 77)                                   // auto again → loop tracks the latest
        XCTAssertEqual(deck.exportEvents(cables: [1]).first?.b1, 77)
    }

    func testRingEvictsBeyondCapacity() {
        let deck = ReelDeck()
        for n in 0..<(ReelDeck.histCount + 2) { filePass(deck, note: UInt8(1 + (n % 120))) }   // histCount+2 passes
        let nums = deck.passNumbers()
        XCTAssertEqual(nums[ReelDeck.histCount - 1], ReelDeck.histCount + 1, "newest kept")
        XCTAssertEqual(nums[0], 2, "oldest kept = passCounter − histCount")
        XCTAssertFalse(deck.selectPass(0), "an evicted pass can't be selected")
        XCTAssertTrue(deck.selectPass(2), "the oldest surviving pass can")
    }

    // REMOVE DUPLICATES (Paul 2026-08-26 #dedup): passes with the same emitted note-ONs hash EQUAL; a differing
    // note breaks the signature. Aligned with passNumbers (oldest→newest); empty slots → 0.
    func testPassSignaturesMatchForIdenticalPassesAndDifferForOthers() {
        let deck = ReelDeck()
        filePass(deck, note: 60)        // pass 0
        filePass(deck, note: 60)        // pass 1 — identical content
        filePass(deck, note: 67)        // pass 2 — different note
        let sigs = deck.passSignatures()
        let last = ReelDeck.histCount - 1   // newest = pass 2; last-1 = pass 1; last-2 = pass 0
        XCTAssertEqual(sigs[last - 1], sigs[last - 2], "identical passes share a signature")
        XCTAssertNotEqual(sigs[last], sigs[last - 1], "a different note changes the signature")
        XCTAssertNotEqual(sigs[last - 1], 0, "a filed pass has a non-zero signature")
        XCTAssertEqual(sigs[last - 3], 0, "an empty ring slot signs as 0")
    }

    func testSelectedRollPairsNotesAndClosesOpenOnesAtCycleEnd() {
        let deck = ReelDeck()
        deck.cycleBeats = 4.0
        deck.record(beat: 0.0, cable: 1, 0x90, 60, 100)   // A: 60 for [0,1]
        deck.record(beat: 1.0, cable: 1, 0x80, 60, 0)
        deck.record(beat: 2.0, cable: 2, 0x90, 64, 80)    // B: 64 opens, never closes → to cycleBeats
        deck.record(beat: 0.5, cable: 0, 0x90, 72, 90)    // cable 0 (All) is ignored
        deck.promote()
        let roll = deck.selectedRoll()
        XCTAssertEqual(roll.count, 2)
        let a = roll.first { $0.cable == 1 }; let b = roll.first { $0.cable == 2 }
        XCTAssertEqual(a?.note, 60); XCTAssertEqual(a?.start, 0.0); XCTAssertEqual(a?.end, 1.0)
        XCTAssertEqual(b?.note, 64); XCTAssertEqual(b?.end, 4.0, "an open note closes at the pass length")
    }
    // MULTI-PASS EXPORT (Paul 2026-08-26): a phrase longer than one pass exports whole — concatenate the passes, each
    // offset by the cumulative length; the range roll pairs across the concatenation.
    func testExportRangeAndRollConcatenatePassesWithOffset() {
        let deck = ReelDeck()
        deck.cycleBeats = 4.0
        deck.record(beat: 0.0, cable: 1, 0x90, 60, 100); deck.record(beat: 1.0, cable: 1, 0x80, 60, 0)
        deck.promote(); deck.startPass()                     // pass 0: note 60 [0,1], cycle 4
        deck.record(beat: 0.5, cable: 1, 0x90, 64, 90); deck.record(beat: 1.5, cable: 1, 0x80, 64, 0)
        deck.promote()                                       // pass 1: note 64 [0.5,1.5], cycle 4
        let (evs, total) = deck.exportRangeEvents(fromPass: 0, toPass: 1, cables: [1])
        XCTAssertEqual(total, 8.0, "two 4-beat passes → an 8-beat phrase")
        XCTAssertEqual(evs.count, 4, "both passes' on+off events survive")
        XCTAssertTrue(evs.contains { abs($0.beat - 0.0) < 1e-9 && $0.b1 == 60 }, "pass 0's note-on at offset 0")
        XCTAssertTrue(evs.contains { abs($0.beat - 4.5) < 1e-9 && $0.b1 == 64 }, "pass 1's note-on offset by pass 0's cycle (4 + 0.5)")
        let (notes, rtotal) = deck.rangeRoll(fromPass: 0, toPass: 1)
        XCTAssertEqual(rtotal, 8.0)
        XCTAssertEqual(notes.count, 2, "two paired notes across the range")
        XCTAssertTrue(notes.contains { $0.note == 64 && abs($0.start - 4.5) < 1e-9 && abs($0.end - 5.5) < 1e-9 }, "pass 1's note offset into the phrase")
    }
    // rangeRoll's whole point: a note held ACROSS a pass boundary REUNITES (its ON in pass N, its OFF in N+1 → one
    // Note), and a note never closed by the range end is FLUSHED at `total`. The all-populated test above exercises
    // neither. (Coverage gap 2026-08-30.)
    func testRangeRollReunitesAcrossBoundaryAndFlushesTrailing() {
        let deck = ReelDeck(); deck.cycleBeats = 4.0
        deck.record(beat: 3.0, cable: 1, 0x90, 60, 100)          // pass 0: ON 60 at beat 3, NO off
        deck.promote(); deck.startPass()
        deck.record(beat: 1.0, cable: 1, 0x80, 60, 0)            // pass 1: OFF 60 → reunites [3, 4+1=5]
        deck.record(beat: 2.0, cable: 1, 0x90, 67, 90)          // pass 1: ON 67, never closed → flush at total
        deck.promote()
        let (notes, total) = deck.rangeRoll(fromPass: 0, toPass: 1)
        XCTAssertEqual(total, 8.0)
        XCTAssertEqual(notes.count, 2, "the boundary-spanning note + the never-closed note")
        XCTAssertTrue(notes.contains { $0.note == 60 && abs($0.start - 3.0) < 1e-9 && abs($0.end - 5.0) < 1e-9 }, "60 reunites across the boundary (ON pass 0, OFF pass 1)")
        XCTAssertTrue(notes.contains { $0.note == 67 && abs($0.start - 6.0) < 1e-9 && abs($0.end - 8.0) < 1e-9 }, "67 never closes → flushed at the range end (total 8)")
    }
    // An EMPTY / unrecorded pass in the MIDDLE of a range is SKIPPED — it advances neither the events nor the phrase
    // clock (the export concatenates NON-EMPTY passes back-to-back). Locks the intended behaviour so a stray "advance
    // offset for the empty pass" can't slip in phantom silent bars. (Coverage gap 2026-08-30.)
    func testRangeExportSkipsAnEmptyInteriorPass() {
        let deck = ReelDeck(); deck.cycleBeats = 4.0
        deck.record(beat: 0.0, cable: 1, 0x90, 60, 100); deck.record(beat: 1.0, cable: 1, 0x80, 60, 0)
        deck.promote(); deck.startPass()                         // pass 0: note 60
        deck.promote(); deck.startPass()                         // pass 1: EMPTY (no records)
        deck.record(beat: 0.5, cable: 1, 0x90, 64, 90); deck.record(beat: 1.5, cable: 1, 0x80, 64, 0)
        deck.promote()                                           // pass 2: note 64
        let (evs, total) = deck.exportRangeEvents(fromPass: 0, toPass: 2, cables: [1])
        XCTAssertEqual(total, 8.0, "only the two NON-empty 4-beat passes count (pass 1 is skipped)")
        XCTAssertTrue(evs.contains { abs($0.beat - 4.5) < 1e-9 && $0.b1 == 64 }, "pass 2's note-on lands at offset 4 (pass 1 added no gap), not 8")
    }

    // THE DOOR RING (config-sheets REPLAY, Paul 2026-08-20): record input, capture a loop, query sounding notes.
    func testDoorRingCapturesAndQueriesSoundingNotes() {
        let ring = DoorRing()
        ring.record(beat: 0.0, note: 60, vel: 100, on: true)
        ring.record(beat: 0.5, note: 64, vel: 90, on: true)
        ring.record(beat: 1.0, note: 60, vel: 0, on: false)
        ring.record(beat: 2.0, note: 64, vel: 0, on: false)
        ring.capture(endBeat: 2.0, lengthBeats: 2.0)              // loop [0,2), start=0 → beats unchanged
        XCTAssertEqual(ring.loopLen, 2.0)
        var n = [UInt8](repeating: 0, count: 16), v = [UInt8](repeating: 0, count: 16), ch = [UInt8](repeating: 0, count: 16)
        func sounding(_ p: Double) -> Set<UInt8> { let c = ring.notesSoundingAt(p, outNote: &n, outVel: &v, outChan: &ch); return Set((0..<c).map { n[$0] }) }
        XCTAssertEqual(sounding(0.25), [60], "only 60 sounds at 0.25")
        XCTAssertEqual(sounding(0.75), [60, 64], "both sound at 0.75")
        XCTAssertEqual(sounding(1.5), [64], "60 released by 1.0 → only 64 at 1.5")
    }
    func testDoorRingRetroCaptureRebasesTheWindow() {
        let ring = DoorRing()
        ring.record(beat: 3.0, note: 40, vel: 70, on: true)      // an OLD note, RELEASED before the window → dropped
        ring.record(beat: 3.5, note: 40, vel: 0, on: false)
        ring.record(beat: 4.0, note: 48, vel: 80, on: true)      // HELD across the window start (never released)
        ring.record(beat: 5.5, note: 72, vel: 110, on: true)     // inside the last 1 beat
        ring.capture(endBeat: 6.0, lengthBeats: 1.0)             // window [5,6)
        var n = [UInt8](repeating: 0, count: 16), v = [UInt8](repeating: 0, count: 16), ch = [UInt8](repeating: 0, count: 16)
        func sounding(_ p: Double) -> Set<UInt8> { let c = ring.notesSoundingAt(p, outNote: &n, outVel: &v, outChan: &ch); return Set((0..<c).map { n[$0] }) }
        XCTAssertEqual(sounding(0.4), [48], "a note HELD across the window start loops from beat 0; the released old note is gone")
        XCTAssertEqual(sounding(0.6), [48, 72], "plus the recent note, rebased to 0.5")
    }
    // REPLAY intermittency fix (Paul 2026-08-21): a chord the hands were already SUSTAINING when the catch window opens
    // must loop from the top — its note-ons are before the window, so `capture` seeds them at beat 0 (else = silence).
    func testDoorRingCaptureSeedsNotesHeldAtWindowStart() {
        let ring = DoorRing()
        ring.record(beat: 0.0, note: 60, vel: 100, on: true)     // a chord pressed BEFORE the window, still held
        ring.record(beat: 0.0, note: 64, vel: 90, on: true)
        ring.record(beat: 3.0, note: 67, vel: 80, on: true)      // a later note added inside the window
        ring.capture(endBeat: 4.0, lengthBeats: 2.0)             // window [2,4): 60+64 held → beat 0; 67 at 3 → 1.0
        var n = [UInt8](repeating: 0, count: 16), v = [UInt8](repeating: 0, count: 16), ch = [UInt8](repeating: 0, count: 16)
        func sounding(_ p: Double) -> Set<UInt8> { let c = ring.notesSoundingAt(p, outNote: &n, outVel: &v, outChan: &ch); return Set((0..<c).map { n[$0] }) }
        XCTAssertEqual(sounding(0.5), [60, 64], "the sustained chord loops from the top (was dropped → silence)")
        XCTAssertEqual(sounding(1.5), [60, 64, 67], "the in-window note joins")
    }
    // loopRoll (config-sheet REPLAY piano roll, Paul 2026-08-23): the captured loop as DURATION notes — each on paired
    // with its off (a note still open at loop end closes at loopLen), preserving held-chord lengths + channel.
    func testDoorRingLoopRollPairsNotesWithDuration() {
        let ring = DoorRing()
        ring.record(beat: 0.0, note: 60, vel: 100, on: true, chan: 2)
        ring.record(beat: 1.0, note: 60, vel: 0, on: false, chan: 2)   // 60: [0,1]
        ring.record(beat: 0.5, note: 64, vel: 90, on: true)            // 64: [0.5, loopEnd] (never released)
        ring.capture(endBeat: 2.0, lengthBeats: 2.0)                   // start=0 → beats unchanged, loopLen 2
        let roll = ring.loopRoll().sorted { $0.note < $1.note }
        XCTAssertEqual(roll.count, 2)
        XCTAssertEqual(roll[0].note, 60); XCTAssertEqual(roll[0].start, 0.0); XCTAssertEqual(roll[0].end, 1.0, accuracy: 1e-9); XCTAssertEqual(roll[0].chan, 2)
        XCTAssertEqual(roll[1].note, 64); XCTAssertEqual(roll[1].start, 0.5, accuracy: 1e-9)
        XCTAssertEqual(roll[1].end, 2.0, accuracy: 1e-9, "a note still sounding at loop end closes at loopLen (real duration, not a point)")
    }
    // TRANSPORT DISCONTINUITY (Paul 2026-08-23): the ring records at ABSOLUTE beats, and capture assumes ascending
    // arrival order. clearHistory() drops the recorded events so post-stop/seek recording restarts MONOTONE — else the
    // old + new passes superpose into a garbled, mis-phased loop. oldestBeat reports the available history (< N clamp).
    func testDoorRingClearHistoryResetsRecordingAndOldestBeat() {
        let ring = DoorRing()
        ring.record(beat: 10.0, note: 60, vel: 100, on: true)    // a pre-stop pass at a high absolute beat
        ring.record(beat: 11.0, note: 60, vel: 0, on: false)
        XCTAssertEqual(ring.oldestBeat, 10.0, accuracy: 1e-9)
        ring.clearHistory()                                       // transport stop→start / seek → drop the stale history
        XCTAssertFalse(ring.oldestBeat.isFinite, "empty history → oldestBeat is +∞")
        ring.record(beat: 0.0, note: 72, vel: 90, on: true)       // recording restarts at the new (lower) beat, MONOTONE
        ring.record(beat: 1.0, note: 72, vel: 0, on: false)
        ring.capture(endBeat: 2.0, lengthBeats: 2.0)
        var n = [UInt8](repeating: 0, count: 16), v = [UInt8](repeating: 0, count: 16), ch = [UInt8](repeating: 0, count: 16)
        let c = ring.notesSoundingAt(0.5, outNote: &n, outVel: &v, outChan: &ch)
        XCTAssertEqual(Set((0..<c).map { n[$0] }), [72], "only the post-clear note loops — the stale beat-10 pass is gone")
    }
    // CHANNEL-PRESERVING REPLAY (Paul 2026-08-22): the loop must re-emit each note on its ORIGINAL channel — else a
    // channel-filtered door replays on the wrong channel and its cells reject the loop (the "channel 3 → silent" bug).
    func testDoorRingReplayPreservesTheRecordedChannel() {
        let ring = DoorRing()
        ring.record(beat: 0.0, note: 60, vel: 100, on: true, chan: 2)    // channel 3 (0-based 2)
        ring.record(beat: 3.0, note: 67, vel: 80, on: true, chan: 2)     // still held across the window start
        ring.capture(endBeat: 4.0, lengthBeats: 2.0)                     // 60 held → beat 0; 67 at 3 → 1.0
        var n = [UInt8](repeating: 0, count: 16), v = [UInt8](repeating: 0, count: 16), ch = [UInt8](repeating: 0, count: 16)
        let c = ring.notesSoundingAt(1.5, outNote: &n, outVel: &v, outChan: &ch)
        XCTAssertEqual(c, 2, "both notes sound at 1.5")
        for k in 0..<c { XCTAssertEqual(ch[k], 2, "note \(n[k]) replays on its recorded channel 3 (0-based 2), not a re-stamp") }
    }

    // CR-3[review]: a note-ON with no matching OFF (held across the pass boundary, or truncated when the pass was
    // re-selected from the browser) must get a SYNTHETIC off at the loop end — else replay() re-emits the ON forever
    // with no OFF ⇒ a stuck note (invariant 4).
    func testUnclosedNoteGetsSyntheticOffAtLoopEnd() {
        let deck = ReelDeck()
        deck.cycleBeats = 4.0
        deck.record(beat: 1.0, cable: 1, 0x90, 62, 100)   // ON, NO matching OFF
        deck.promote()                                    // auto-loop → closeOpenLoopNotes appends a synthetic OFF at cycleBeats
        XCTAssertTrue(deck.hasLoop)
        // window [3.5, 4.5): the note's ON next-occurrence is 5.0 (out of window); ONLY the synthetic OFF at 4.0 lands.
        let rec = ReelRec()
        deck.replay(beatPos: 3.5, windowBeats: 1.0, cycleBeats: 4.0, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertEqual(rec.events.count, 1, "just the synthetic OFF in this window")
        XCTAssertEqual(rec.events[0].b0 & 0xF0, 0x80, "it's a note-OFF")
        XCTAssertEqual(rec.events[0].b1, 62, "for the note left open")
        // and the ON still fires earlier in the pass (round-trip, no note lost)
        let rec2 = ReelRec()
        deck.replay(beatPos: 0.5, windowBeats: 1.0, cycleBeats: 4.0, beatsPerSample: 0.001, windowStart: 0, out: rec2)
        XCTAssertEqual(rec2.events.count, 1)
        XCTAssertEqual(rec2.events[0].b0 & 0xF0, 0x90, "the ON plays [1,4)")
    }
}
