//  ReelV3Tests.swift — REEL V3, the paged looper (2026-11-16, `Docs/reel-v3-paged-looper.md` §2/§4): the deck's v3 staging
//  (ARM at a tape boundary · top-up · instant phase-matched page switch · live-phase page-back · retile), the scheduled-start
//  emission (an anchor mid-window starts sample-exact; a late flip anchors in the past and keeps the phase), the position
//  feeds, and the recorder's live-tape-beat mapping. Foundation-only, no simulator; drives the deck like ReelPhase2Tests.

import XCTest

private final class Rec: MIDIEmitter {
    struct E: Equatable { var sample: Int64; var cable: UInt8; var b0: UInt8; var b1: UInt8; var b2: UInt8 }
    var out: [E] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { out.append(E(sample: sampleTime, cable: cable, b0: b0, b1: b1, b2: b2)) }
    func clear() { out.removeAll(keepingCapacity: true) }
}

final class ReelV3Tests: XCTestCase {
    private func on(_ beat: Double, note: UInt8 = 60) -> ReelDeck.Ev { ReelDeck.Ev(beat: beat, cable: 1, b0: 0x90, b1: note, b2: 100) }
    private func off(_ beat: Double, note: UInt8 = 60) -> ReelDeck.Ev { ReelDeck.Ev(beat: beat, cable: 1, b0: 0x80, b1: note, b2: 0) }

    // MARK: the ARM — adopt stays live; the flip (the Kernel's job, simulated here) starts replay sample-exact at the boundary

    func testArmAdoptStaysArmedAndDoesNotAnchor() {
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageRangeV3([on(0), off(1)], span: 4, startTapeBeat: 16, armEndTapeBeat: 20))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .arm)
        XCTAssertTrue(deck.isArmedV3)
        XCTAssertEqual(deck.armEndTapeBeat, 20)
        XCTAssertEqual(deck.startTapeBeat, 16)
        XCTAssertEqual(deck.state, .off, "an armed page stays LIVE until the tape boundary")
    }

    func testArmedFlipStartsSampleExactMidWindow() {
        let deck = ReelDeck(); let rec = Rec()
        XCTAssertTrue(deck.stageRangeV3([on(0), off(1)], span: 4, startTapeBeat: 16, armEndTapeBeat: 20))
        XCTAssertTrue(deck.adoptStagedLoop())
        // the Kernel: boundary lands 0.25 beats into the window starting at host beat 50 → anchor 50.25.
        deck.beginArmedReplay(anchor: 50.25)
        deck.state = .replaying
        XCTAssertFalse(deck.isArmedV3)
        deck.replayAnchored(beatPos: 50.0, windowBeats: 1.0, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertEqual(rec.out, [Rec.E(sample: 250, cable: 1, b0: 0x90, b1: 60, b2: 100)],
                       "the on at page-beat 0 sounds exactly at the boundary (sample 250), nothing before it; the off at beat 1 (occ 51.25) is beyond this window")
    }

    func testLateFlipAnchorsInThePastAndKeepsThePhase() {
        let deck = ReelDeck(); let rec = Rec()
        XCTAssertTrue(deck.stageRangeV3([on(1.0, note: 61), on(2.0, note: 62), on(2.5, note: 63)], span: 16, startTapeBeat: 0))
        XCTAssertTrue(deck.adoptStagedLoop())
        deck.beginArmedReplay(anchor: 48)        // the boundary was 2 beats ago (a late adopt) — the missed head played live
        deck.state = .replaying
        deck.replayAnchored(beatPos: 50.0, windowBeats: 1.0, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertEqual(rec.out.map { $0.b1 }, [62, 63], "phase 2: beats before 2 are skipped this turn, 2.0 and 2.5 sound")
        XCTAssertEqual(rec.out.map { $0.sample }, [0, 500])
    }

    // MARK: top-up — the anchor (phase) is kept and the late tail completes

    func testTopUpKeepsThePhaseAndCompletesTheTail() {
        let deck = ReelDeck(); let rec = Rec()
        XCTAssertTrue(deck.stageRangeV3([on(0)], span: 4, startTapeBeat: 0))         // the incomplete page (its tail not yet drained)
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .start)
        deck.state = .replaying
        deck.replayAnchored(beatPos: 10.0, windowBeats: 0.1, beatsPerSample: 0.001, windowStart: 0, out: rec)   // anchor 10
        rec.clear()
        XCTAssertTrue(deck.stageRangeV3([on(0), off(1), on(3.5, note: 64)], span: 4, startTapeBeat: 0, keepAnchor: true, flushOnAdopt: false))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .keep)
        XCTAssertFalse(deck.adoptedFlush, "a top-up of the same page never blankets the sounding notes")
        deck.replayAnchored(beatPos: 13.4, windowBeats: 0.4, beatsPerSample: 0.001, windowStart: 0, out: rec)   // phase 3.4, window [3.4, 3.8)
        XCTAssertEqual(rec.out, [Rec.E(sample: 100, cable: 1, b0: 0x90, b1: 64, b2: 100)],
                       "the topped-up tail event at page-beat 3.5 sounds at its true place; the phase did not move")
        XCTAssertEqual(deck.replayPos(), 3.4, accuracy: 1e-9, "replay position = page start + phase")
    }

    // MARK: page switch — instant and phase-matched

    func testPageSwitchIsInstantAndPhaseMatched() {
        let deck = ReelDeck(); let rec = Rec()
        XCTAssertTrue(deck.stageRangeV3([on(1.0, note: 60)], span: 4, startTapeBeat: 0))
        XCTAssertTrue(deck.adoptStagedLoop())
        deck.state = .replaying
        deck.replayAnchored(beatPos: 20.0, windowBeats: 0.1, beatsPerSample: 0.001, windowStart: 0, out: rec)   // anchor 20
        rec.clear()
        // switch to the page [8, 12) — same width; its own note at page-beat 1.5.
        XCTAssertTrue(deck.stageRangeV3([on(1.5, note: 72)], span: 4, startTapeBeat: 8, keepAnchor: true, livePhase: true, flushOnAdopt: true))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .keep, "mid-replay, keepAnchor wins over livePhase")
        XCTAssertTrue(deck.adoptedFlush, "a page switch blankets the old loop's ringing notes")
        deck.replayAnchored(beatPos: 21.4, windowBeats: 0.2, beatsPerSample: 0.001, windowStart: 0, out: rec)   // phase 1.4, window [1.4, 1.6)
        XCTAssertEqual(rec.out, [Rec.E(sample: 100, cable: 1, b0: 0x90, b1: 72, b2: 100)],
                       "the NEW page's note sounds at the SAME phase — the old page's note at 1.0 is gone")
        XCTAssertEqual(deck.replayPos(), 8 + 1.4, accuracy: 1e-9)
    }

    // MARK: live-phase page-back — paging back from the live (not yet flipped) page starts NOW, beat-aligned to the page grid

    func testLivePhasePageBackStartsAtTheLiveClocksPagePhase() {
        let deck = ReelDeck(); let rec = Rec()
        XCTAssertTrue(deck.stageRangeV3([on(2.0, note: 70)], span: 4, startTapeBeat: 8, keepAnchor: true, livePhase: true))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .livePhase, "not replaying ⇒ the live-phase start is pending")
        XCTAssertTrue(deck.livePhasePending)
        // the Kernel: live tape beat 17.9 (phase 1.9 of its own page) at host beat 100 → the shown page plays from ITS beat 1.9.
        deck.beginLivePhaseReplay(beatPos: 100.0, liveTapeBeat: 17.9)
        deck.state = .replaying
        XCTAssertFalse(deck.livePhasePending)
        deck.replayAnchored(beatPos: 100.0, windowBeats: 0.2, beatsPerSample: 0.001, windowStart: 0, out: rec)   // window = page beats [1.9, 2.1)
        XCTAssertEqual(rec.out, [Rec.E(sample: 100, cable: 1, b0: 0x90, b1: 70, b2: 100)],
                       "the note at page-beat 2.0 sounds 0.1 beats in — beat-aligned with what would have played")
        XCTAssertEqual(deck.replayPos(), 8 + 1.9, accuracy: 1e-9)
    }

    func testKeepAdoptRacingTheHandBackIsDropped() {
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageRangeV3([on(0)], span: 4, startTapeBeat: 0, keepAnchor: true, flushOnAdopt: false))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .dropped, "a top-up that raced the hand-back must not restart replay")
        XCTAssertFalse(deck.isArmedV3)
        XCTAssertEqual(deck.state, .off)
    }

    // MARK: retile — a width change maps the playhead's TAPE position into the new grid exactly

    func testRetileHalvingKeepsTheTapePosition() {
        let deck = ReelDeck(); let rec = Rec()
        XCTAssertTrue(deck.stageRangeV3([on(10.0, note: 60)], span: 16, startTapeBeat: 0))   // the old page [0, 16)
        XCTAssertTrue(deck.adoptStagedLoop())
        deck.state = .replaying
        deck.replayAnchored(beatPos: 100.0, windowBeats: 0.1, beatsPerSample: 0.001, windowStart: 0, out: rec)   // anchor 100
        rec.clear()
        // at host beat 110 the playhead is at tape beat 10 → halve to the page [8, 16) (the half holding the playhead); its note sits at page-beat 2 (tape 10).
        XCTAssertTrue(deck.stageRangeV3([on(2.0, note: 60)], span: 8, startTapeBeat: 8, keepAnchor: true, flushOnAdopt: true, retile: true))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .keep)
        deck.replayAnchored(beatPos: 110.0, windowBeats: 0.5, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertEqual(rec.out, [Rec.E(sample: 0, cable: 1, b0: 0x90, b1: 60, b2: 100)],
                       "the playhead stays at tape beat 10: the note there sounds at the window start")
        XCTAssertEqual(deck.replayPos(), 10.0, accuracy: 1e-9, "same tape beat, new grid")
    }

    func testRetileDoublingKeepsTheTapePosition() {
        let deck = ReelDeck(); let rec = Rec()
        XCTAssertTrue(deck.stageRangeV3([on(5.0, note: 61)], span: 8, startTapeBeat: 0))     // the old page [0, 8)
        XCTAssertTrue(deck.adoptStagedLoop())
        deck.state = .replaying
        deck.replayAnchored(beatPos: 200.0, windowBeats: 0.1, beatsPerSample: 0.001, windowStart: 0, out: rec)   // anchor 200
        rec.clear()
        // at host beat 205 the playhead is at tape beat 5 → double to [0, 16): position preserved.
        XCTAssertTrue(deck.stageRangeV3([on(5.0, note: 61)], span: 16, startTapeBeat: 0, keepAnchor: true, flushOnAdopt: true, retile: true))
        XCTAssertTrue(deck.adoptStagedLoop())
        deck.replayAnchored(beatPos: 205.0, windowBeats: 0.5, beatsPerSample: 0.001, windowStart: 0, out: rec)
        XCTAssertEqual(rec.out.map { $0.sample }, [0], "the note at tape beat 5 sounds right where the playhead is")
        XCTAssertEqual(deck.replayPos(), 5.0, accuracy: 1e-9)
    }

    // MARK: cancel / clear / legacy parity

    func testCancelArmDropsThePendingArmAndLivePhase() {
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageRangeV3([on(0)], span: 4, startTapeBeat: 0, armEndTapeBeat: 4))
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertTrue(deck.isArmedV3)
        deck.cancelArm()
        XCTAssertFalse(deck.isArmedV3)
        XCTAssertNil(deck.armEndTapeBeat)
        XCTAssertFalse(deck.livePhasePending)
    }

    func testClearResetsTheV3State() {
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageRangeV3([on(0)], span: 4, startTapeBeat: 12, armEndTapeBeat: 16))
        XCTAssertTrue(deck.adoptStagedLoop())
        deck.clear()
        XCTAssertFalse(deck.isArmedV3)
        XCTAssertNil(deck.armEndTapeBeat)
        XCTAssertEqual(deck.startTapeBeat, 0)
        XCTAssertEqual(deck.state, .off)
    }

    func testLegacyAdoptsAreUntouched() {
        let deck = ReelDeck()
        XCTAssertTrue(deck.stageRange([on(0)], span: 4, mode: .loop, pass: -1))      // phase 2
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .start)
        XCTAssertEqual(deck.startTapeBeat, 0)
        XCTAssertFalse(deck.isArmedV3)
        XCTAssertTrue(deck.stageLoop([on(0)], cycle: 4, pass: 0))                    // legacy pass browser
        XCTAssertTrue(deck.adoptStagedLoop())
        XCTAssertEqual(deck.adoptedKind, .start)
        XCTAssertFalse(deck.usesAnchoredReplay)
    }

    // MARK: the recorder's live tape clock (the armed flip's and the live sweep's time base)

    // MARK: the page grid (the pure screen layer, `Docs/reel-v3-paged-looper.md` §0/§1/§3)

    func testPageGridTilesTheTapeFromZero() {
        let p = reelV3Page(at: 17.0, bars: 4, beatsPerBar: 4)       // W = 16 → page 1 = [16, 32)
        XCTAssertEqual(p, ReelV3Page(index: 1, startBeat: 16, endBeat: 32))
        XCTAssertEqual(reelV3Page(at: 0, bars: 4, beatsPerBar: 4).index, 0)
        XCTAssertEqual(reelV3Page(at: -3, bars: 4, beatsPerBar: 4).index, 0, "never before the tape start")
    }

    func testStepClampsBetweenZeroAndTheLivePage() {
        let p1 = reelV3Page(at: 20.0, bars: 4, beatsPerBar: 4)      // page 1
        XCTAssertEqual(reelV3Step(p1, by: -1, bars: 4, beatsPerBar: 4, liveBeat: 100).index, 0)
        XCTAssertEqual(reelV3Step(p1, by: -5, bars: 4, beatsPerBar: 4, liveBeat: 100).index, 0, "clamped at the first page")
        XCTAssertEqual(reelV3Step(p1, by: 10, bars: 4, beatsPerBar: 4, liveBeat: 70).index, 4, "clamped at the LIVE page (70/16 → 4)")
    }

    func testHalveKeepsTheHalfThePlayheadIsIn() {
        let page = ReelV3Page(index: 1, startBeat: 16, endBeat: 32)                     // 4 bars
        let (nb, second) = reelV3Halve(bars: 4, page: page, playheadBeat: 27.0, beatsPerBar: 4)
        XCTAssertEqual(nb, 2)
        XCTAssertEqual(second, ReelV3Page(index: 3, startBeat: 24, endBeat: 32), "playhead at 27 → the second half")
        let (_, first) = reelV3Halve(bars: 4, page: page, playheadBeat: 17.0, beatsPerBar: 4)
        XCTAssertEqual(first.startBeat, 16, "playhead at 17 → the first half")
        let (_, fallback) = reelV3Halve(bars: 4, page: page, playheadBeat: 99.0, beatsPerBar: 4)
        XCTAssertEqual(fallback.startBeat, 16, "a playhead outside the page falls back to its start")
        XCTAssertEqual(reelV3Halve(bars: 1, page: page, playheadBeat: 17, beatsPerBar: 4).bars, 1, "1 bar is the floor")
    }

    func testDoubleKeepsTheShownPagesStartInView() {
        let odd = ReelV3Page(index: 3, startBeat: 24, endBeat: 32)                      // 2 bars, odd index
        let (nb, p) = reelV3Double(bars: 2, page: odd, beatsPerBar: 4)
        XCTAssertEqual(nb, 4)
        XCTAssertEqual(p, ReelV3Page(index: 1, startBeat: 16, endBeat: 32), "the 4-bar tile holding beat 24")
        XCTAssertEqual(reelV3Double(bars: 32, page: odd, beatsPerBar: 4).bars, 32, "32 bars is the ceiling")
    }

    func testMinimapTapLandsOnThePageAndClampsToLive() {
        let rect = CGRect(x: 0, y: 0, width: 100, height: 36)
        let p = reelV3MinimapPage(atX: 50, rect: rect, bars: 4, beatsPerBar: 4, sessionEndBeat: 64, liveBeat: 60)
        XCTAssertEqual(p.index, 2, "x 50% of a 64-beat session = beat 32 = page 2")
        let clamped = reelV3MinimapPage(atX: 99, rect: rect, bars: 4, beatsPerBar: 4, sessionEndBeat: 64, liveBeat: 20)
        XCTAssertEqual(clamped.index, 1, "a tap past the live page lands ON the live page")
        let c0 = reelV3MinimapCell(index: 0, bars: 4, beatsPerBar: 4, sessionEndBeat: 64, rect: rect)
        XCTAssertEqual(c0, CGRect(x: 0, y: 0, width: 25, height: 36), "4 pages → quarter-width cells")
    }

    func testLabelsAndSpokenState() {
        let p = ReelV3Page(index: 4, startBeat: 64, endBeat: 80)
        XCTAssertEqual(reelV3PageLabel(p, beatsPerBar: 4), "BARS 17–20")
        XCTAssertEqual(reelV3PageLabel(ReelV3Page(index: 2, startBeat: 8, endBeat: 12), beatsPerBar: 4), "BAR 3")
        XCTAssertEqual(reelV3WidthLabel(bars: 4), "4 BARS")
        XCTAssertEqual(reelV3WidthLabel(bars: 1), "1 BAR")
        XCTAssertEqual(reelV3SpokenState(page: p, beatsPerBar: 4, live: true, armed: true), "Reel, bars 17–20, live — loops when the page ends")
        XCTAssertEqual(reelV3SpokenState(page: p, beatsPerBar: 4, live: false, armed: false), "Reel, bars 17–20, looping")
    }

    func testLayoutStacksMinimapRollControlBar() {
        let L = reelV3Layout(size: CGSize(width: 800, height: 600))
        XCTAssertEqual(L.minimap, CGRect(x: 16, y: 16, width: 768, height: 36))
        XCTAssertEqual(L.controlBar, CGRect(x: 16, y: 600 - 16 - 56, width: 768, height: 56))
        XCTAssertEqual(L.roll, CGRect(x: 16, y: 16 + 36 + 12, width: 768, height: 600 - 16 - 56 - 12 - (16 + 36 + 12)))
        XCTAssertFalse(L.belowFloor)
        XCTAssertTrue(reelV3Layout(size: CGSize(width: 400, height: 200)).belowFloor, "a short window is drawn at the formula values and flagged")
    }

    func testLiveTapeBeatFollowsTheSegmentMappingAcrossAStop() {
        let t = SessionTape(chunkEvents: 256, poolSize: 64)
        let rec = TapeRecorder(writer: t.writer)
        XCTAssertNil(rec.liveTapeBeat(atHostBeat: 10.0), "no segment open before the first playing window")
        rec.beginWindow(playing: true, beatPos: 10.0, windowBeats: 0.5, tempo: 120, cycleBeats: 16, sampleStart: 0, beatsPerSample: 0.001)
        XCTAssertEqual(rec.liveTapeBeat(atHostBeat: 10.0) ?? -1, 0.0, accuracy: 1e-9, "the session clock starts at 0")
        XCTAssertEqual(rec.liveTapeBeat(atHostBeat: 10.25) ?? -1, 0.25, accuracy: 1e-3, "1:1 within the window (tick-quantised)")
        rec.beginWindow(playing: false, beatPos: 10.5, windowBeats: 0.5, tempo: 120, cycleBeats: 16, sampleStart: 0, beatsPerSample: 0.001)
        XCTAssertNil(rec.liveTapeBeat(atHostBeat: 10.5), "stopped → the segment is closed")
        // restart somewhere else entirely: the tape continues where it left off (0.5 beats in), host beat 50 maps there.
        rec.beginWindow(playing: true, beatPos: 50.0, windowBeats: 0.5, tempo: 120, cycleBeats: 16, sampleStart: 0, beatsPerSample: 0.001)
        XCTAssertEqual(rec.liveTapeBeat(atHostBeat: 50.0) ?? -1, 0.5, accuracy: 1e-3, "the next segment starts at the tick the last one ended — no gap, no shear")
    }
}
