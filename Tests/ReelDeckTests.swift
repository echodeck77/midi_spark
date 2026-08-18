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
}
