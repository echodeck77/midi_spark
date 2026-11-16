//  ReelPhase2Tests.swift — REEL PHASE 2 (2026-11-16): the ANCHORED tape playhead (ReelDeck.replayAnchored / stageRange / toLiveReachedEnd).
//  Position is host beat − anchor (latched at the first emitting window), nothing accumulates. `.loop` repeats from press-time; `.toLive` plays once. Foundation-only, no simulator.

import XCTest

private final class Rec: MIDIEmitter {
    struct E: Equatable { var sample: Int64; var cable: UInt8; var b0: UInt8; var b1: UInt8; var b2: UInt8 }
    var out: [E] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { out.append(E(sample: sampleTime, cable: cable, b0: b0, b1: b1, b2: b2)) }
    func clear() { out.removeAll(keepingCapacity: true) }
}

final class ReelPhase2Tests: XCTestCase {
    // A two-event range: note-on at range-beat 0, note-off at 1, over a 4-beat span.
    private func stageTwoBeatNote(_ deck: ReelDeck, span: Double = 4, mode: ReelDeck.ReplayMode = .loop) {
        let evs = [ReelDeck.Ev(beat: 0.0, cable: 1, b0: 0x90, b1: 60, b2: 100),
                   ReelDeck.Ev(beat: 1.0, cable: 1, b0: 0x80, b1: 60, b2: 0)]
        XCTAssertTrue(deck.stageRange(evs, span: span, mode: mode, pass: -1))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertTrue(deck.usesAnchoredReplay)
    }

    // §2 — the anchor latches at the FIRST emitting window, so replay starts from NOW regardless of the host beat.
    func testAnchorLatchesAtFirstWindow() {
        let deck = ReelDeck(); let rec = Rec()
        stageTwoBeatNote(deck)
        // first window at an arbitrary host beat 137.0 → elapsed 0 → both events emit from the window start.
        deck.replayAnchored(beatPos: 137.0, windowBeats: 4.0, beatsPerSample: 0.001, windowStart: 5000, out: rec)
        XCTAssertEqual(rec.out, [Rec.E(sample: 5000, cable: 1, b0: 0x90, b1: 60, b2: 100),     // on at range-beat 0 → window start
                                 Rec.E(sample: 6000, cable: 1, b0: 0x80, b1: 60, b2: 0)])       // off at range-beat 1 → +1 beat = +1000 samples
    }

    // §2 / sample accuracy — the replayed sample offset equals the recorded beat offset, across tempos (beatsPerSample) and window starts.
    func testSampleAccuracyAcrossBuffers() {
        for bps in [1.0 / 64.0, 1.0 / 512.0, 1.0 / 4096.0] {
            let deck = ReelDeck(); let rec = Rec()
            stageTwoBeatNote(deck)
            deck.replayAnchored(beatPos: 0, windowBeats: 4.0, beatsPerSample: bps, windowStart: 0, out: rec)
            XCTAssertEqual(rec.out.first?.sample, 0)
            XCTAssertEqual(rec.out.last?.sample, Int64((1.0 / bps).rounded()), "note-off at beat 1 → 1/bps samples")
        }
    }

    // §2 — `.loop` repeats aligned to WHEN IT STARTED (anchor), not the global grid, and wraps across the seam in a straddling window.
    func testLoopRepeatsAndWrapsAtTheSeam() {
        let deck = ReelDeck(); let rec = Rec()
        stageTwoBeatNote(deck, span: 4, mode: .loop)
        deck.replayAnchored(beatPos: 100.0, windowBeats: 4.0, beatsPerSample: 0.001, windowStart: 0, out: rec)   // latch anchor 100; elapsed 0
        rec.clear()
        // a window one span later: elapsed 4 → phase 0 again → the loop repeats (identical offsets).
        deck.replayAnchored(beatPos: 104.0, windowBeats: 4.0, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertEqual(rec.out, [Rec.E(sample: 0, cable: 1, b0: 0x90, b1: 60, b2: 100), Rec.E(sample: 1000, cable: 1, b0: 0x80, b1: 60, b2: 0)])
        rec.clear()
        // a window straddling the seam (elapsed 102.5 → phase 2.5, window [2.5, 6.5)): the on at 0 and off at 1 both fall in the NEXT turn (b+span).
        deck.replayAnchored(beatPos: 202.5, windowBeats: 4.0, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertEqual(rec.out, [Rec.E(sample: Int64(((4.0 - 2.5) / 0.001).rounded()), cable: 1, b0: 0x90, b1: 60, b2: 100),    // on: 0+4 = 4, (4-2.5)/bps
                                 Rec.E(sample: Int64(((5.0 - 2.5) / 0.001).rounded()), cable: 1, b0: 0x80, b1: 60, b2: 0)])      // off: 1+4 = 5, (5-2.5)/bps
    }

    // §2 — derived position: calling at anchor + k·span reproduces IDENTICAL emissions, with no drift over many turns.
    func testNoDriftOverManyTurns() {
        let deck = ReelDeck(); let rec = Rec()
        stageTwoBeatNote(deck, span: 4)
        deck.replayAnchored(beatPos: 0, windowBeats: 4, beatsPerSample: 0.001, windowStart: 0, out: rec)   // anchor 0
        let first = rec.out
        for k in 1...10_000 {
            rec.clear()
            deck.replayAnchored(beatPos: Double(k) * 4.0, windowBeats: 4, beatsPerSample: 0.001, windowStart: 0, out: rec)
            XCTAssertEqual(rec.out, first, "turn \(k) must match the first turn exactly (no accumulation)")
        }
    }

    // §2 — `.toLive`: plays once forward, then `toLiveReachedEnd` fires at the span end (the Kernel hands back to live).
    func testToLivePlaysOnceThenReachesEnd() {
        let deck = ReelDeck(); let rec = Rec()
        stageTwoBeatNote(deck, span: 4, mode: .toLive)
        XCTAssertFalse(deck.toLiveReachedEnd(beatPos: 50.0), "not anchored yet → not ended")
        deck.replayAnchored(beatPos: 50.0, windowBeats: 4, beatsPerSample: 0.001, windowStart: 0, out: rec)   // anchor 50, elapsed 0 → plays
        XCTAssertEqual(rec.out.count, 2)
        XCTAssertFalse(deck.toLiveReachedEnd(beatPos: 53.9), "elapsed 3.9 < span 4")
        rec.clear()
        deck.replayAnchored(beatPos: 55.0, windowBeats: 4, beatsPerSample: 0.001, windowStart: 0, out: rec)   // elapsed 5 → past the range → silent
        XCTAssertTrue(rec.out.isEmpty, ".toLive does not loop")
        XCTAssertTrue(deck.toLiveReachedEnd(beatPos: 54.0), "elapsed 4 ≥ span 4 → hand back to live")
    }

    // The legacy stageLoop path is NOT anchored (the current browser keeps its phase-locked replay).
    func testStageLoopStaysLegacy() {
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageLoop([ReelDeck.Ev(beat: 0, cable: 1, b0: 0x90, b1: 60, b2: 100)], cycle: 4, pass: 0))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertFalse(deck.usesAnchoredReplay, "stageLoop → legacy phase-locked replay")
        XCTAssertFalse(deck.toLiveReachedEnd(beatPos: 999), "legacy is never a .toLive end")
    }

    // The loop never strands a note: a range whose note is still open at the span end gets a synthetic off (closeOpenLoopNotes), so each turn re-strikes.
    func testOpenNoteClosedAtSpanEnd() {
        let deck = ReelDeck(); let rec = Rec()
        // on at 0, NO off within the range → closeOpenLoopNotes must append an off at the span end.
        XCTAssertTrue(deck.stageRange([ReelDeck.Ev(beat: 0.0, cable: 1, b0: 0x90, b1: 60, b2: 100)], span: 4, mode: .loop, pass: -1))
        XCTAssertTrue(deck.adoptStagedLoop())
        deck.replayAnchored(beatPos: 0, windowBeats: 1.0, beatsPerSample: 0.001, windowStart: 0, out: rec)   // anchor 0, [0,1): the on only
        rec.clear()
        // a window straddling the seam (phase 3.5, [3.5,4.5)): the synthetic off at the span end (beat 4) AND the next turn's on (beat 0 → occ 4) both land here.
        deck.replayAnchored(beatPos: 3.5, windowBeats: 1.0, beatsPerSample: 0.001, windowStart: 0, out: rec)
        let offs = rec.out.filter { ($0.b0 & 0xF0) == 0x80 || (($0.b0 & 0xF0) == 0x90 && $0.b2 == 0) }
        XCTAssertEqual(offs.count, 1, "a synthetic off closes the held note at the span end (so no stuck note across the seam)")
    }
}
