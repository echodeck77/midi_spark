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

    // FOURFOLD REEL LINK (2026-10-23): a hit ON the pass boundary is emitted by the window that contains it — the LAST window of the old pass.
    // It belongs to the next pass; filing it in the old one (wrapped to beat 0) doubled that pass's downbeat and exported the real one a pass early.
    func testAnEventPastThePassBoundaryIsFiledAtTheHeadOfTheNextPassNotTheTail() {
        let deck = ReelDeck(), sink = ReelRec(), tap = ReelTap()
        tap.out = sink; tap.deck = deck; tap.recording = true
        tap.cycleBeats = 4; tap.beatsPerSample = 0.001; tap.base = 3.9; tap.windowStart = 1000    // a window [3.9, 4.1): sample 1000 is beat 3.9, sample 1100 is beat 4.0
        deck.cycleBeats = 4
        deck.startPass(pass: 0)
        tap.emit(sampleTime: 1050, cable: 1, 0x90, 60, 100)    // beat 3.95 — the old pass's last moments
        tap.emit(sampleTime: 1100, cable: 1, 0x90, 62, 100)    // beat 4.0 — the next pass's downbeat
        tap.emit(sampleTime: 1150, cable: 1, 0x80, 62, 0)      // beat 4.05 — its note-off, still in the straddling window
        XCTAssertEqual(sink.events.count, 3, "the live output is untouched")
        XCTAssertEqual(deck.curN, 1, "only the 3.95 event belongs to the pass being recorded")
        XCTAssertEqual(deck.carryN, 2); XCTAssertEqual(deck.carryPass, 1)
        deck.promote()
        deck.startPass(pass: 1)
        XCTAssertEqual(deck.curN, 2, "the new pass opens with its downbeat and that note's off")
        XCTAssertEqual(deck.cur[0].beat, 0.0, accuracy: 1e-9); XCTAssertEqual(deck.cur[0].b1, 62)
        XCTAssertEqual(deck.cur[1].beat, 0.05, accuracy: 1e-9); XCTAssertEqual(deck.cur[1].b0, 0x80)
        XCTAssertEqual(deck.carryN, 0, "the carry is spent")
        XCTAssertTrue(deck.selectPass(0))
        let roll = deck.selectedRoll()
        XCTAssertEqual(roll.count, 1, "pass 0 holds only its own note — pass 1's downbeat is no longer a stray at its start")
        XCTAssertEqual(roll.first?.start ?? -1, 3.95, accuracy: 1e-9)
    }
    func testAHitComputedAHairUnderTheBoundaryStillGoesToTheNextPass() {
        let deck = ReelDeck(), tap = ReelTap()
        tap.deck = deck; tap.recording = true
        tap.cycleBeats = 4; tap.beatsPerSample = 4.0 / 96_000.0; tap.base = 3.99; tap.windowStart = 95_760
        deck.startPass(pass: 0)
        tap.emit(sampleTime: 96_000 - 1, cable: 2, 0x90, 48, 90)       // a sample before the boundary: still pass 0
        tap.emit(sampleTime: 96_000, cable: 2, 0x90, 50, 90)           // exactly on it (3.9999999… in floating point is the hazard)
        XCTAssertEqual(deck.curN, 1); XCTAssertEqual(deck.carryN, 1)
    }
    func testACarryForAnotherPassIsDroppedAndNoArgumentStartPassDropsIt() {
        let deck = ReelDeck()
        deck.recordNext(pass: 5, beat: 0.1, cable: 1, 0x90, 60, 100)
        deck.startPass(pass: 9)                                        // the transport jumped: that carry is for a pass that never began
        XCTAssertEqual(deck.curN, 0); XCTAssertEqual(deck.carryN, 0)
        deck.recordNext(pass: 3, beat: 0.2, cable: 1, 0x90, 60, 100)
        deck.startPass()
        XCTAssertEqual(deck.curN, 0, "no pass given = no seeding"); XCTAssertEqual(deck.carryN, 0)
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


    // CR-3[review]: a note-ON with no matching OFF (held across the pass boundary, or truncated when the pass was
    // re-selected from the browser) must get a SYNTHETIC off at the loop end — else replay() re-emits the ON forever
    // with no OFF ⇒ a stuck note (invariant 4).
    // Review 2026-10-27: the ALL cable (0) is replayed too, and carries each port on its own channel — a note held across the pass end on ALL, on its channel, gets its off on ALL (it used to be left to ring until STOP).
    func testUnclosedNoteOnAllAndOnAPortEachGetTheirOwnSyntheticOff() {
        let deck = ReelDeck()
        deck.cycleBeats = 4.0
        deck.record(beat: 1.0, cable: 0, 0x94, 62, 100); deck.record(beat: 1.0, cable: 5, 0x94, 62, 100)   // the same note, ch 5, on ALL and on Emit Riff C — neither is closed
        deck.record(beat: 1.0, cable: 0, 0x97, 62, 100); deck.record(beat: 1.0, cable: 6, 0x97, 62, 100)   // …and again on ch 8 / Emit Notes C
        deck.promote()
        let rec = ReelRec()
        deck.replay(beatPos: 3.5, windowBeats: 1.0, cycleBeats: 4.0, beatsPerSample: 0.001, windowStart: 0, out: rec)
        let offs = rec.events.filter { $0.b0 & 0xF0 == 0x80 }.map { "\($0.cable):\($0.b0 & 0x0F)" }.sorted()
        XCTAssertEqual(offs, ["0:4", "0:7", "5:4", "6:7"], "one synthetic off per open (cable, channel, note), ALL included")
    }
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

// THE PART ROLL (Paul 2026-09-02): the live per-part-cycle note capture for the part-page piano roll.
final class PartRollDeckTests: XCTestCase {
}

// The OFFLINE PART ROLL (Paul 2026-09-03) — the deterministic, no-lag feed that replaces the live audio capture.
final class OfflinePartRollTests: XCTestCase {

}
