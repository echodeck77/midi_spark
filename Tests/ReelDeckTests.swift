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
        XCTAssertEqual(nums.count, 32)
        XCTAssertEqual(nums[31], 2, "newest is last (bottom-right of the pop-up)")
        XCTAssertEqual(nums[30], 1)
        XCTAssertEqual(nums[29], 0)
        XCTAssertEqual(nums[28], -1, "unfilled slots are empty")
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
        for n in 0..<(ReelDeck.histCount + 2) { filePass(deck, note: UInt8(1 + (n % 120))) }   // 34 passes
        let nums = deck.passNumbers()
        XCTAssertEqual(nums[31], ReelDeck.histCount + 1, "newest kept")
        XCTAssertEqual(nums[0], 2, "oldest kept = passCounter − histCount")
        XCTAssertFalse(deck.selectPass(0), "an evicted pass can't be selected")
        XCTAssertTrue(deck.selectPass(2), "the oldest surviving pass can")
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
}
