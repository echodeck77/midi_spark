import XCTest

/// ANSWER ferry (2026-11-02) §11 / §13 — the pure functions: following, cycling, phase, effective rows, emit source, SWAP pairing, normalizeTrades, the phase bar, the borrowed tabs, the latch, the layout and the strip.
final class AnswerTabTests: XCTestCase {
    private func lanes() -> [EuclidLine] { (0..<4).map { _ in EuclidLine() } }
    private func on(_ l: inout EuclidLine, mode: EuclideousAnswerTradeMode, with: Int, each: Int? = nil, unit: EuclideousAnswerCycleUnit? = nil) {
        l.answerTradeOn = true; l.answerTradeMode = mode; l.answerTradeWith = with
        if let e = each { l.answerCycleEach = e }; if let u = unit { l.answerCycleUnit = u }
    }

    // MARK: 11.1 – 11.3

    func testIsFollowingIsRhythmOrPitchAndNeverTrade() {
        XCTAssertFalse(euclideousAnswerIsFollowing(rhythmOn: false, pitchOn: false))
        XCTAssertTrue(euclideousAnswerIsFollowing(rhythmOn: true, pitchOn: false)); XCTAssertTrue(euclideousAnswerIsFollowing(rhythmOn: false, pitchOn: true))
        XCTAssertTrue(euclideousAnswerIsFollowing(rhythmOn: true, pitchOn: true))
    }
    func testHasCycleNeedsARowOnWithCycleOrTrade() {
        func h(_ rOn: Bool, _ rC: Bool, _ pOn: Bool, _ pC: Bool, _ t: Bool) -> Bool { euclideousAnswerHasCycle(rhythmOn: rOn, rhythmCycle: rC, pitchOn: pOn, pitchCycle: pC, tradeOn: t) }
        XCTAssertFalse(h(false, false, false, false, false))
        XCTAssertFalse(h(false, true, false, true, false), "a CYCLE flag on a switched-off row does not make a cycle")
        XCTAssertFalse(h(true, false, true, false, false), "rows on without CYCLE do not cycle")
        XCTAssertTrue(h(true, true, false, false, false)); XCTAssertTrue(h(false, false, true, true, false)); XCTAssertTrue(h(false, false, false, false, true), "TRADE always cycles")
    }

    // MARK: ANSWER v2 (2026-11-06) — the note-math pure functions (§8.3, §8.4)

    private func pool(_ notes: [Int]) -> ArraySlice<(note: Int, vel: UInt8)> { notes.map { (note: $0, vel: UInt8(100)) }[...] }

    /// §10.2/§10.3: MEET plays an own hit only where the source hits; AVOID only where it does not; the two are disjoint and together equal the own hits (a partition over every own/source combination).
    func testRhythmGateMeetAndAvoidPartitionTheOwnHits() {
        for mode in [EuclideousAnswerRhythmMode.copy, .fill] {
            XCTAssertTrue(euclideousAnswerRhythmGate(mode: mode, ownHit: true, sourceHit: true)); XCTAssertTrue(euclideousAnswerRhythmGate(mode: mode, ownHit: true, sourceHit: false), "\(mode) passes the own hit through")
            XCTAssertFalse(euclideousAnswerRhythmGate(mode: mode, ownHit: false, sourceHit: true), "no own hit, nothing plays")
        }
        for own in [false, true] { for src in [false, true] {
            let meet = euclideousAnswerRhythmGate(mode: .meet, ownHit: own, sourceHit: src)
            let avoid = euclideousAnswerRhythmGate(mode: .avoid, ownHit: own, sourceHit: src)
            XCTAssertFalse(meet && avoid, "disjoint at own=\(own) src=\(src)")
            XCTAssertEqual(meet || avoid, own, "their union is exactly the own hits at own=\(own) src=\(src)")
            if own { XCTAssertEqual(meet, src); XCTAssertEqual(avoid, !src) }
        } }
    }
    /// §10.4: MIRROR turns the SHADOW note upside down in the source pool (rank r → N+1−r). Pool C E G A: E→G, C→A, F♯ (nearest G, rank 3) → E. Empty pool mutes.
    func testMirrorNoteFlipsTheRankInTheSourcePool() {
        let p = [60, 64, 67, 69]   // C E G A, N = 4 (ascending)
        XCTAssertEqual(euclideousAnswerMirrorNote(sourceNote: 64, pool: p, count: 4), 67, "E (rank 2) → rank 3 = G")
        XCTAssertEqual(euclideousAnswerMirrorNote(sourceNote: 60, pool: p, count: 4), 69, "C (rank 1) → rank 4 = A")
        XCTAssertEqual(euclideousAnswerMirrorNote(sourceNote: 66, pool: p, count: 4), 64, "F♯ nearest G (rank 3) → rank 2 = E")
        XCTAssertEqual(euclideousAnswerMirrorNote(sourceNote: 67, pool: p, count: 4), 64, "G (rank 3) → rank 2 = E")
        XCTAssertNil(euclideousAnswerMirrorNote(sourceNote: 64, pool: [], count: 0), "empty pool mutes")
    }
    /// §10.5: DODGE steps the own note off the source's pitch class (any octave) to the nearest rank above whose class differs, else below, else mute; a different class is unchanged.
    func testDodgeNoteStepsOffTheSourcesPitchClass() {
        let p1 = pool([48, 52, 55])   // C3 E3 G3
        XCTAssertEqual(euclideousAnswerDodgeNote(ownNote: 52, sourceNote: 76, ownPool: p1), 55, "own E3 vs source E5 → G3 (above)")
        XCTAssertEqual(euclideousAnswerDodgeNote(ownNote: 55, sourceNote: 43, ownPool: p1), 52, "own G3 (top) vs source G2 → E3 (below)")
        XCTAssertEqual(euclideousAnswerDodgeNote(ownNote: 48, sourceNote: 52, ownPool: p1), 48, "own C3 vs source E3 (different class) → unchanged")
        let p2 = pool([48, 52, 60])   // C3 E3 C4
        XCTAssertEqual(euclideousAnswerDodgeNote(ownNote: 60, sourceNote: 36, ownPool: p2), 52, "own C4 (top) vs source C2 → E3 (nearest below, skipping C3)")
        XCTAssertEqual(euclideousAnswerDodgeNote(ownNote: 48, sourceNote: 72, ownPool: p2), 52, "own C3 vs source C4 → E3 (above)")
        XCTAssertNil(euclideousAnswerDodgeNote(ownNote: 48, sourceNote: 48, ownPool: pool([48, 60])), "own pool C3 C4 all pitch-class C vs source C → mute")
    }
    func testCyclePhaseEach4() {
        let phases = (0..<9).map { euclideousCyclePhase(unitsSinceStart: $0, each: 4) }
        XCTAssertEqual(phases, [.a, .a, .a, .a, .b, .b, .b, .b, .a], "EACH 4: units 0–3 A, 4–7 B, 8 A")
        XCTAssertEqual(euclideousCyclePhase(unitsSinceStart: -3, each: 4), .a)
        XCTAssertEqual(euclideousCyclePhase(unitsSinceStart: 1, each: 1), .b)
        XCTAssertEqual(euclideousCyclePhase(unitsSinceStart: 5, each: 0), .b, "EACH is at least 1")
    }

    // MARK: 11.4 – 11.6

    func testPhaseLaneIsTheLowerLaneOfASwapPairElseItself() {
        var L = lanes()
        XCTAssertEqual(euclideousAnswerPhaseLane(lane: 2, lines: L), 2)
        on(&L[0], mode: .swap, with: 2); on(&L[2], mode: .swap, with: 0)
        XCTAssertEqual(euclideousAnswerPhaseLane(lane: 0, lines: L), 0); XCTAssertEqual(euclideousAnswerPhaseLane(lane: 2, lines: L), 0)
        XCTAssertEqual(euclideousAnswerPhaseLane(lane: 1, lines: L), 1)
        on(&L[3], mode: .borrow, with: 1)
        XCTAssertEqual(euclideousAnswerPhaseLane(lane: 3, lines: L), 3, "BORROW counts its own units")
        L[2].answerTradeOn = false
        XCTAssertEqual(euclideousAnswerPhaseLane(lane: 0, lines: L), 0, "a SWAP without a partner is no pair")
    }
    func testEffectiveRowsPerPhase() {
        typealias R = EuclideousAnswerRows
        func rows(_ p: EuclideousCyclePhase, _ rOn: Bool, _ rC: Bool, _ pOn: Bool, _ pC: Bool) -> R { euclideousAnswerEffectiveRows(phase: p, rhythmOn: rOn, rhythmCycle: rC, pitchOn: pOn, pitchCycle: pC) }
        XCTAssertEqual(rows(.a, true, true, true, true), R(rhythm: true, pitch: true), "phase A: the lane exactly as set")
        XCTAssertEqual(rows(.b, true, true, true, true), R(rhythm: false, pitch: false), "phase B: cycling rows act as if switched off")
        XCTAssertEqual(rows(.b, true, false, true, true), R(rhythm: true, pitch: false), "a row on without CYCLE keeps acting")
        XCTAssertEqual(rows(.b, false, true, false, true), R(rhythm: false, pitch: false))
        XCTAssertEqual(rows(.a, false, true, true, false), R(rhythm: false, pitch: true))
    }
    func testEffectiveLineFollowsThePhaseAndLeavesEverythingElseAlone() {
        var l = EuclidLine(); l.answerPitchOn = true; l.answerPitchMode = .shadow; l.answerPitchCycle = true; l.answerRhythmOn = true; l.listenSource = 1
        XCTAssertEqual(euclideousAnswerEffectiveLine(l, phase: .a), l)
        let b = euclideousAnswerEffectiveLine(l, phase: .b)
        XCTAssertEqual(b.listenPitchResolved, .own); XCTAssertEqual(b.listenRhythmResolved, .copy, "RHYTHM is on without CYCLE: it keeps acting")
        XCTAssertEqual(b.answerPitchModeResolved, .shadow, "the remembered mode is untouched"); XCTAssertEqual(b.listenSource, 1)
    }
    func testEmitSource() {
        XCTAssertEqual(euclideousAnswerEmitSource(lane: 3, phase: .a, tradeOn: true, tradeWith: 1), 3)
        XCTAssertEqual(euclideousAnswerEmitSource(lane: 3, phase: .b, tradeOn: true, tradeWith: 1), 1)
        XCTAssertEqual(euclideousAnswerEmitSource(lane: 3, phase: .b, tradeOn: false, tradeWith: 1), 3)
    }

    // MARK: ANSWER v2 §3.5 — the asker is derived from FOLLOW

    func testTradeAskerIsTheLaneWhoseFollowSourceIsItsPartner() {
        var L = (0..<4).map { _ in EuclidLine() }
        L[0].listenSource = 2; L[2].listenSource = 3              // 0 follows 2 (its partner), 2 follows 3 (not 0)
        XCTAssertEqual(euclideousAnswerTradeAsker(L, pair: (0, 2)), 0)
        XCTAssertEqual(euclideousAnswerTradeAsker(L, pair: (2, 0)), 0, "order-independent")
        L[0].listenSource = 1; L[2].listenSource = 0              // now 2 follows 0 (its partner), 0 follows 1
        XCTAssertEqual(euclideousAnswerTradeAsker(L, pair: (0, 2)), 2)
        L[0].listenSource = 2; L[2].listenSource = 0              // both point at each other → lower
        XCTAssertEqual(euclideousAnswerTradeAsker(L, pair: (0, 2)), 0, "both → lower-numbered")
        L[0].listenSource = 1; L[2].listenSource = 3              // neither points at the other → lower
        XCTAssertEqual(euclideousAnswerTradeAsker(L, pair: (0, 2)), 0, "neither → lower-numbered")
    }

    // MARK: 11.7 — SWAP pairing (6.4)

    func testPairingA_SwapOnPairsTheOtherLaneAndCopiesEachAndUnit() {
        var L = lanes(); L[0].answerCycleEach = 7; L[0].answerCycleUnit = .passes
        L = euclideousApplyTradeEdit(L, lane: 0, edit: .with(2))      // WITH alone does not switch TRADE on
        XCTAssertFalse(L[0].answerTradeOnResolved); XCTAssertFalse(L[2].answerTradeOnResolved)
        L = euclideousApplyTradeEdit(L, lane: 0, edit: .on(true))
        XCTAssertTrue(L[0].answerTradeOnResolved); XCTAssertEqual(L[0].answerTradeModeResolved, .swap); XCTAssertEqual(L[0].answerTradeWithResolved(ownLane: 0), 2)
        XCTAssertTrue(L[2].answerTradeOnResolved); XCTAssertEqual(L[2].answerTradeModeResolved, .swap); XCTAssertEqual(L[2].answerTradeWithResolved(ownLane: 2), 0)
        XCTAssertEqual(L[2].answerCycleEachResolved, 7); XCTAssertEqual(L[2].answerCycleUnitResolved, .passes, "X's EACH and UNIT are copied to Y")
        XCTAssertEqual(euclideousAnswerPairPartner(lane: 0, lines: L), 2); XCTAssertEqual(euclideousAnswerPairPartner(lane: 2, lines: L), 0)
    }
    func testPairingB_APairedLaneIsStolenAndItsOldPartnerSwitchesOffKeepingModeAndWith() {
        var L = lanes()
        L = euclideousApplyTradeEdit(L, lane: 0, edit: .with(1)); L = euclideousApplyTradeEdit(L, lane: 0, edit: .on(true))   // 0 ↔ 1
        L = euclideousApplyTradeEdit(L, lane: 2, edit: .with(1)); L = euclideousApplyTradeEdit(L, lane: 2, edit: .on(true))   // 2 takes 1: 1's old partner (0) goes off
        XCTAssertFalse(L[0].answerTradeOnResolved, "Z's TRADE switches off")
        XCTAssertEqual(L[0].answerTradeModeResolved, .swap); XCTAssertEqual(L[0].answerTradeWithResolved(ownLane: 0), 1, "…its mode and WITH kept")
        XCTAssertEqual(euclideousAnswerPairPartner(lane: 1, lines: L), 2); XCTAssertEqual(euclideousAnswerPairPartner(lane: 2, lines: L), 1)
    }
    func testPairingB_ABorrowingLaneIsReplacedBySwap() {
        var L = lanes(); on(&L[1], mode: .borrow, with: 3)
        L = euclideousApplyTradeEdit(L, lane: 0, edit: .with(1)); L = euclideousApplyTradeEdit(L, lane: 0, edit: .on(true))
        XCTAssertEqual(L[1].answerTradeModeResolved, .swap); XCTAssertEqual(L[1].answerTradeWithResolved(ownLane: 1), 0, "Y's BORROW is replaced")
        XCTAssertEqual(euclideousAnswerPairPartner(lane: 0, lines: L), 1)
    }
    func testPairingC_OffOnEitherLaneSwitchesBothOff() {
        var L = lanes(); L = euclideousApplyTradeEdit(L, lane: 0, edit: .with(3)); L = euclideousApplyTradeEdit(L, lane: 0, edit: .on(true))
        let off = euclideousApplyTradeEdit(L, lane: 3, edit: .on(false))
        XCTAssertFalse(off[0].answerTradeOnResolved); XCTAssertFalse(off[3].answerTradeOnResolved)
        let off2 = euclideousApplyTradeEdit(L, lane: 0, edit: .on(false))
        XCTAssertFalse(off2[0].answerTradeOnResolved); XCTAssertFalse(off2[3].answerTradeOnResolved)
    }
    func testPairingC_BorrowOrANewWithOnEitherLaneSwitchesTheOtherOff() {
        var L = lanes(); L = euclideousApplyTradeEdit(L, lane: 0, edit: .with(3)); L = euclideousApplyTradeEdit(L, lane: 0, edit: .on(true))
        let b = euclideousApplyTradeEdit(L, lane: 3, edit: .mode(.borrow))
        XCTAssertEqual(b[3].answerTradeModeResolved, .borrow); XCTAssertTrue(b[3].answerTradeOnResolved, "the edited lane keeps TRADE on, now BORROWing lane 1")
        XCTAssertFalse(b[0].answerTradeOnResolved, "the other lane's TRADE switches off")
        let w = euclideousApplyTradeEdit(L, lane: 0, edit: .with(1))
        XCTAssertFalse(w[3].answerTradeOnResolved, "WITH another lane releases the old partner…")
        XCTAssertEqual(euclideousAnswerPairPartner(lane: 0, lines: w), 1, "…and a new WITH under SWAP pairs per a")
        XCTAssertEqual(euclideousAnswerPairPartner(lane: 1, lines: w), 0)
    }
    func testPairingD_EachAndUnitOnEitherLaneWriteBoth_ButOnlyForAPair() {
        var L = lanes(); L = euclideousApplyTradeEdit(L, lane: 0, edit: .with(2)); L = euclideousApplyTradeEdit(L, lane: 0, edit: .on(true))
        let e = euclideousApplyTradeEdit(L, lane: 2, edit: .each(9)); XCTAssertEqual(e[0].answerCycleEachResolved, 9); XCTAssertEqual(e[2].answerCycleEachResolved, 9)
        let u = euclideousApplyTradeEdit(L, lane: 0, edit: .unit(.passes)); XCTAssertEqual(u[2].answerCycleUnitResolved, .passes)
        XCTAssertEqual(euclideousApplyTradeEdit(L, lane: 1, edit: .each(12))[1].answerCycleEachResolved, 12)
        XCTAssertEqual(euclideousApplyTradeEdit(L, lane: 1, edit: .each(12))[0].answerCycleEachResolved, 4, "a lane outside a pair writes only itself")
        var B = lanes(); on(&B[3], mode: .borrow, with: 1)
        let bE = euclideousApplyTradeEdit(B, lane: 3, edit: .each(2)); XCTAssertEqual(bE[3].answerCycleEachResolved, 2); XCTAssertEqual(bE[1].answerCycleEachResolved, 4, "BORROW is one-way: the WITH lane is not written")
        XCTAssertEqual(euclideousApplyTradeEdit(L, lane: 0, edit: .each(99))[0].answerCycleEachResolved, 16, "clamped to 16")
    }
    func testAnEditNeverTouchesALaneItDoesNotNeedTo() {
        var L = lanes(); L[1].answerRhythmOn = true; L[1].answerRhythmCycle = true; L[3].answerCycleEach = 11
        let after = euclideousApplyTradeEdit(L, lane: 0, edit: .with(2))
        XCTAssertEqual(after[1], L[1]); XCTAssertEqual(after[3], L[3])
    }
    func testWithItselfOrOutOfRangeIsIgnored() {
        let L = lanes()
        XCTAssertEqual(euclideousApplyTradeEdit(L, lane: 1, edit: .with(1)), L); XCTAssertEqual(euclideousApplyTradeEdit(L, lane: 1, edit: .with(7)), L)
        XCTAssertEqual(euclideousApplyTradeEdit(L, lane: 9, edit: .on(true)), L)
    }

    // MARK: 6.5 — normalizeTrades

    func testNormalizeSwitchesOffASwapWhosePartnerDoesNotSwapBack() {
        var L = lanes(); on(&L[0], mode: .swap, with: 2); on(&L[2], mode: .borrow, with: 0)
        let r = euclideousNormalizeTrades(L)
        XCTAssertFalse(r.lines[0].answerTradeOnResolved); XCTAssertEqual(r.lines[0].answerTradeModeResolved, .swap); XCTAssertTrue(r.lines[2].answerTradeOnResolved, "a BORROW is not touched")
        XCTAssertEqual(r.changes.count, 1); XCTAssertTrue(r.changes[0].contains("lane 1"))
    }
    func testNormalizeIsLeftToRightSoAChainResolvesDeterministically() {
        var L = lanes(); on(&L[0], mode: .swap, with: 1); on(&L[1], mode: .swap, with: 2); on(&L[2], mode: .swap, with: 1)
        let r = euclideousNormalizeTrades(L)
        XCTAssertFalse(r.lines[0].answerTradeOnResolved); XCTAssertEqual(euclideousAnswerPairPartner(lane: 1, lines: r.lines), 2)
        XCTAssertEqual(euclideousNormalizeTrades(r.lines).changes, [], "idempotent")
    }
    func testNormalizeGivesAPairTheLowerLanesEachAndUnit() {
        var L = lanes(); on(&L[1], mode: .swap, with: 3, each: 2, unit: .bars); on(&L[3], mode: .swap, with: 1, each: 9, unit: .passes)
        let r = euclideousNormalizeTrades(L)
        XCTAssertEqual(r.lines[3].answerCycleEachResolved, 2); XCTAssertEqual(r.lines[3].answerCycleUnitResolved, .bars)
        XCTAssertEqual(r.lines[1].answerCycleEachResolved, 2); XCTAssertEqual(r.changes.count, 1)
    }
    func testNormalizeLeavesAHealthyDocumentAlone() {
        var L = lanes(); on(&L[0], mode: .swap, with: 3, each: 5); on(&L[3], mode: .swap, with: 0, each: 5); on(&L[1], mode: .borrow, with: 2)
        let r = euclideousNormalizeTrades(L)
        XCTAssertEqual(r.lines, L); XCTAssertTrue(r.changes.isEmpty)
    }
    func testNormalizeTradesAtLoadRewritesTheDocumentOnlyWhenSomethingChanged() {
        var doc = PluginState.makeInit()
        var L = doc.euclideousLinesResolved; on(&L[0], mode: .swap, with: 1)
        doc.euclideousLines = L
        doc.normalizeTradesAtLoad()
        XCTAssertFalse(doc.euclideousLinesResolved[0].answerTradeOnResolved)
        var clean = PluginState.makeInit(); let before = clean
        clean.normalizeTradesAtLoad(); XCTAssertEqual(clean, before)
    }
    // MARK: 11.8 — the phase bar

    func testPhaseColours() {
        var l = EuclidLine(); l.listenSource = 2
        XCTAssertEqual(euclideousAnswerPhaseColours(lane: 0, line: l), EuclideousPhaseColours(a: 0, b: 0))
        l.answerRhythmOn = true; XCTAssertEqual(euclideousAnswerPhaseColours(lane: 0, line: l).a, 0, "a row on WITHOUT cycle leaves half A the lane's own")
        l.answerRhythmCycle = true; XCTAssertEqual(euclideousAnswerPhaseColours(lane: 0, line: l).a, 2, "…with CYCLE: the source's")
        l.answerTradeOn = true; l.answerTradeWith = 3; XCTAssertEqual(euclideousAnswerPhaseColours(lane: 0, line: l), EuclideousPhaseColours(a: 2, b: 3))
        l.answerRhythmOn = false; XCTAssertEqual(euclideousAnswerPhaseColours(lane: 0, line: l).a, 0, "a switched-off row cycles nothing")
    }
    func testPhaseProgress() {
        XCTAssertEqual(euclideousAnswerPhaseProgress(unitsSinceStart: 0, fractionOfUnit: 0, each: 4), 0, accuracy: 1e-12)
        XCTAssertEqual(euclideousAnswerPhaseProgress(unitsSinceStart: 2, fractionOfUnit: 0.5, each: 4), 2.5 / 8, accuracy: 1e-12)
        XCTAssertEqual(euclideousAnswerPhaseProgress(unitsSinceStart: 4, fractionOfUnit: 0, each: 4), 0.5, accuracy: 1e-12, "B starts at the middle")
        XCTAssertEqual(euclideousAnswerPhaseProgress(unitsSinceStart: 8, fractionOfUnit: 0.25, each: 4), 0.25 / 8, accuracy: 1e-12, "a new cycle starts over")
        XCTAssertLessThanOrEqual(euclideousAnswerPhaseProgress(unitsSinceStart: 7, fractionOfUnit: 5, each: 4), 1)
    }

    // MARK: 11.9 / test 14 — borrowed tabs for every combination

    func testBorrowedTabsForEveryCombination() {
        for rOn in [false, true] { for rC in [false, true] { for pOn in [false, true] { for pm in EuclideousAnswerPitchMode.allCases { for pC in [false, true] { for reads in [false, true] {
            let b = euclideousAnswerBorrowedTabs(rhythmOn: rOn, rhythmCycle: rC, pitchOn: pOn, pitchMode: pm, pitchCycle: pC, notesReadsRiff: reads)
            XCTAssertEqual(b.rhythm, rOn && !rC)
            let riff = pOn && pm == .shadow && !pC
            XCTAssertEqual(b.riff, riff, "AVOID and a cycling PITCH are not borrowed")
            XCTAssertEqual(b.notes, riff && reads)
        } } } } } }
    }
    func testTradeNeverPausesATab() {
        var l = EuclidLine(); on(&l, mode: .swap, with: 1)
        XCTAssertEqual(euclideousAnswerBorrowedTabs(l, notesReadsRiff: true), EuclideousListenBorrowedTabs(rhythm: false, riff: false, notes: false))
    }

    // MARK: 5.3 — boundaries only

    func testTheLatchChangesOnlyAtBoundaries() {
        var latch = EuclideousCycleLatch()
        latch.boundary(liveActive: true, liveEach: 4, liveUnit: .bars, barUnitsSinceStart: 0, passUnitsSinceStart: 0)
        XCTAssertEqual(latch.phase, .a)
        for bar in 1..<4 { latch.boundary(liveActive: true, liveEach: 4, liveUnit: .bars, barUnitsSinceStart: bar, passUnitsSinceStart: 0); XCTAssertEqual(latch.phase, .a, "bar \(bar)") }
        latch.boundary(liveActive: true, liveEach: 4, liveUnit: .bars, barUnitsSinceStart: 4, passUnitsSinceStart: 0); XCTAssertEqual(latch.phase, .b)
        // The user changes EACH to 2 mid-unit: nothing happens until the next boundary call…
        XCTAssertEqual(latch.each, 4); XCTAssertEqual(latch.phase, .b)
        // …where bar 5 is read under EACH 2: (5 / 2) % 2 = 0 → A.
        latch.boundary(liveActive: true, liveEach: 2, liveUnit: .bars, barUnitsSinceStart: 5, passUnitsSinceStart: 0)
        XCTAssertEqual(latch.each, 2); XCTAssertEqual(latch.phase, .a)
    }
    func testTheLatchSwitchesUnitAtABoundaryAndCountsInTheNewUnit() {
        var latch = EuclideousCycleLatch()
        latch.boundary(liveActive: true, liveEach: 2, liveUnit: .bars, barUnitsSinceStart: 0, passUnitsSinceStart: 0)
        latch.boundary(liveActive: true, liveEach: 2, liveUnit: .passes, barUnitsSinceStart: 3, passUnitsSinceStart: 5)
        XCTAssertEqual(latch.unit, .passes); XCTAssertEqual(latch.phase, .a, "5 passes under EACH 2: (5 / 2) % 2 = 0, phase A — counted in the unit NOW in force, not the bars (3 bars would be B)")
    }
    func testACycleThatEndsReturnsToPhaseAAtTheNextBoundary() {
        var latch = EuclideousCycleLatch()
        latch.boundary(liveActive: true, liveEach: 1, liveUnit: .bars, barUnitsSinceStart: 1, passUnitsSinceStart: 0); XCTAssertEqual(latch.phase, .b)
        latch.boundary(liveActive: false, liveEach: 1, liveUnit: .bars, barUnitsSinceStart: 2, passUnitsSinceStart: 0)
        XCTAssertFalse(latch.active); XCTAssertEqual(latch.phase, .a)
    }
    func testStandByAdoptsTheUnitWithoutStartingACycle() {
        var latch = EuclideousCycleLatch(); latch.standBy(liveUnit: .passes)
        XCTAssertTrue(latch.known); XCTAssertFalse(latch.active); XCTAssertEqual(latch.unit, .passes); XCTAssertEqual(latch.phase, .a)
    }

    // MARK: test 16 — geometry

    func testAnswerBodyHeightsAtTheReferenceCards() {
        for h: CGFloat in [229, 229.67] {
            let bare = euclideousAnswerTabLayout(contentAreaH: h, pitchPanelShown: false, cycleRowShown: false)
            XCTAssertEqual(bare.heights, [44, 44, 44, 44]); XCTAssertTrue(bare.fits)
            let cyc = euclideousAnswerTabLayout(contentAreaH: h, pitchPanelShown: false, cycleRowShown: true)
            XCTAssertEqual(cyc.heights, [39, 39, 39, 39, 39], "CYCLE only"); XCTAssertTrue(cyc.fits)
            let pan = euclideousAnswerTabLayout(contentAreaH: h, pitchPanelShown: true, cycleRowShown: false)
            XCTAssertEqual(pan.heights.count, 5); XCTAssertEqual([pan.followRowH, pan.rhythmRowH, pan.pitchRowH, pan.tradeRowH], [37, 37, 37, 37], "panel only: rows 37"); XCTAssertEqual(pan.pitchPanelH, 49, "…and the panel takes the points left over"); XCTAssertTrue(pan.fits)
            let all = euclideousAnswerTabLayout(contentAreaH: h, pitchPanelShown: true, cycleRowShown: true)
            XCTAssertEqual(all.heights, [30, 30, 30, 39, 30, 30], "everything showing: rows at the 30 pt floor, the panel at 39 (38 floor + the 1 point left)"); XCTAssertTrue(all.fits)
            XCTAssertLessThanOrEqual(all.totalHeight, h)
            for l in [bare, cyc, pan, all] { XCTAssertGreaterThanOrEqual(l.heights.min() ?? 0, 30, "nothing below 30"); XCTAssertLessThanOrEqual(l.totalHeight, h) }
        }
    }
    func testAnswerLayoutReportsWhenEvenTheFloorsDoNotFit() {
        let l = euclideousAnswerTabLayout(contentAreaH: 150, pitchPanelShown: true, cycleRowShown: true)
        XCTAssertFalse(l.fits); XCTAssertEqual(l.heights, [30, 30, 30, 38, 30, 30], "never squeezed below the floors")
    }

    // MARK: strip: six tabs

    func testTheStripReadsRhythmRiffNotesPoolAnswerMix() {
        XCTAssertEqual(EuclideousPageTab.allCases.map(\.label), ["EUCLID", "RIFF", "STACK", "INPUTS", "ANSWER", "RESETS", "MIX", "FILL"])   // POOL renamed INPUTS (Paul 2026-11-05); NOTES renamed STACK (STACK GRID, 2026-11-08); RESETS added (2026-11-11); FILL added (2026-11-13, rawValue 7 — skips MIX's 6)
        XCTAssertEqual(EuclideousPageTab.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5, 6, 7])
        // the strip DRAWS them INPUTS first, RESETS right after EUCLID, FILL after STACK (the display order is separate from the raw-value coupling)
        XCTAssertEqual(euclideousPageTabOrder.map(\.label), ["INPUTS", "EUCLID", "RESETS", "RIFF", "STACK", "FILL", "ANSWER", "MIX"])
        XCTAssertEqual(euclideousPageTabOrder.count, EuclideousPageTab.allCases.count)
        XCTAssertEqual(Set(euclideousPageTabOrder), Set(EuclideousPageTab.allCases), "every tab appears exactly once")
        XCTAssertEqual(EuclideousTabKind.allCases.map(\.rawValue), [0, 1, 2, 3, 4, 5, 7])   // FILL = 7 (skips MIX's 6, which has no front tab)
        XCTAssertEqual(EuclideousPageTab.pool.front, .pool); XCTAssertEqual(EuclideousPageTab.listen.front, .listen); XCTAssertNil(EuclideousPageTab.mix.front); XCTAssertEqual(EuclideousPageTab.resets.front, .resets); XCTAssertEqual(EuclideousPageTab.fill.front, .fill)
    }
    func testTheSixSegmentsAtTheReferenceWidths() {
        let land = euclideousLaneStripLayout(width: 769.33), port = euclideousLaneStripLayout(width: 782)
        XCTAssertEqual(land.segments.count, 8); XCTAssertEqual(land.segmentWidth, 84.29, accuracy: 0.01); XCTAssertEqual(port.segmentWidth, 85.88, accuracy: 0.01)
        XCTAssertFalse(land.clustersVisible); XCTAssertFalse(port.clustersVisible)   // FILL (2026-11-13): 8 tabs → segments below the 96 cluster floor at the reference
        XCTAssertFalse(euclideousLaneStripLayout(width: 660).clustersVisible)
        // FILL (2026-11-13): at 8 tabs the reference segment (84.29) is BELOW the 96 cluster floor by design — the clusters hide and `.laneStrip` fires (LaneViewStripTests / PageLayoutTests pin this); the labels still fit (6 chars ≈ 47 pt).
        XCTAssertLessThan(land.segmentWidth, EuclideousLaneStripMetrics.segmentFloor); XCTAssertTrue(land.belowFloor)
    }
    func testTheInputsGlyphLightsOnACanonDelayASourceOffOrAMidiMode() {
        var l = EuclidLine()
        XCTAssertFalse(euclideousTabGlyph(tab: .pool, line: l, lane: 1).on)
        l.chordDelay = 2; XCTAssertTrue(euclideousTabGlyph(tab: .pool, line: l, lane: 1).on)
        l.chordDelay = 0; l.poolHold = 9; XCTAssertFalse(euclideousTabGlyph(tab: .pool, line: l, lane: 1).on, "FREEZE is gone: it lights nothing")
        l.poolHold = 0; l.chordSlip = 20; XCTAssertFalse(euclideousTabGlyph(tab: .pool, line: l, lane: 1).on, "…and neither does SLIP")
        l.chordSlip = 0; l.midiMode = .replace; XCTAssertTrue(euclideousTabGlyph(tab: .pool, line: l, lane: 1).on, "a MIDI mode that is not ADD does")
        l.midiMode = nil
        XCTAssertEqual(euclideousTabGlyph(tab: .pool, line: l, lane: 2).fill, .lane(2)); XCTAssertEqual(euclideousTabGlyph(tab: .pool, line: l, lane: 2).shape, .circle)
    }
    func testTheAnswerGlyphIsHollowWhenNothingIsFollowedAndFilledInTheSourcesColour() {
        var l = EuclidLine(); l.listenSource = 3
        XCTAssertFalse(euclideousTabGlyph(tab: .listen, line: l, lane: 0).on)
        l.answerPitchOn = true
        let g = euclideousTabGlyph(tab: .listen, line: l, lane: 0)
        XCTAssertTrue(g.on); XCTAssertEqual(g.fill, .lane(3))
        l.answerPitchOn = false; l.answerTradeOn = true
        XCTAssertFalse(euclideousTabGlyph(tab: .listen, line: l, lane: 0).on, "TRADE is not following")
    }
    func testStripVoiceOverNamesForAnswerAndPool() {
        var ls = lanes(); ls[2].listenSource = 1; ls[2].answerRhythmOn = true; ls[1].chordDelay = 2
        XCTAssertEqual(euclideousLaneStripLabel(tab: .listen, glyphs: euclideousLaneStripGlyphs(tab: .listen, lines: ls)), "Answer, lane 3 following lane 2")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .listen, glyphs: euclideousLaneStripGlyphs(tab: .listen, lines: lanes())), "Answer, all off")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .pool, glyphs: euclideousLaneStripGlyphs(tab: .pool, lines: ls)), "Inputs, lane 2 set")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .pool, glyphs: euclideousLaneStripGlyphs(tab: .pool, lines: lanes())), "Inputs, nothing set")
    }

    // MARK: SHADOW's mover is allocation-free (the Release audit exercises it now) and unchanged

    /// The sorted-array version the render path used before ANSWER — the reference for the bitmask rewrite.
    private func referenceMove(note: Int, interval: Int, octave: Int, keyRoot: Int, scaleIntervals: [Int]) -> Int {
        let pcs = scaleIntervals.map { ((($0 + keyRoot) % 12) + 12) % 12 }.sorted()
        guard !pcs.isEmpty else { return euclideousListenOctaveClamp(note + 12 * octave) }
        let pc = ((note % 12) + 12) % 12
        let noteOctave = (note - pc) / 12
        let m = pcs.count
        let degree: Int, offset: Int
        if let d = pcs.lastIndex(where: { $0 <= pc }) { degree = d; offset = pc - pcs[d] }
        else { degree = m - 1; offset = pc - (pcs[m - 1] - 12) }
        let base = degree + interval
        let wrapped = ((base % m) + m) % m
        let laps = (base - wrapped) / m
        return euclideousListenOctaveClamp((noteOctave + laps) * 12 + pcs[wrapped] + offset + 12 * octave)
    }
    func testTheBitmaskShadowMoverEqualsTheSortedArrayOneOnEveryScaleNoteAndInterval() {
        for scale in ScaleType.allCases {
            for root in 0..<12 {
                for note in stride(from: 0, through: 127, by: 3) {
                    for interval in -6...6 {
                        for octave in [-3, 0, 2] {
                            XCTAssertEqual(euclideousListenMoveByInterval(note: note, interval: interval, octave: octave, keyRoot: root, scaleIntervals: scale.intervals),
                                           referenceMove(note: note, interval: interval, octave: octave, keyRoot: root, scaleIntervals: scale.intervals),
                                           "\(scale) root \(root) note \(note) interval \(interval) octave \(octave)")
                        }
                    }
                }
            }
        }
        XCTAssertEqual(euclideousListenMoveByInterval(note: 60, interval: 3, octave: 1, keyRoot: 0, scaleIntervals: []), referenceMove(note: 60, interval: 3, octave: 1, keyRoot: 0, scaleIntervals: []), "no scale at all")
    }

    // MARK: 12 — VoiceOver words

    func testModeButtonsSpeakTheirMeaningAndAnOffRowSaysOff() {
        // AMENDMENT 1 §5.2 (take/keep wording) + ANSWER v2 §9.1 (MEET / AVOID on RHYTHM, MIRROR / DODGE on PITCH)
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .rhythm, mode: "COPY", lane: 1, rowOn: true), "Rhythm: copy, takes lane 1's hits")
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .rhythm, mode: "FILL", lane: 3, rowOn: false), "Rhythm: fill, takes lane 3's gaps, off")
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .rhythm, mode: "MEET", lane: 1, rowOn: true), "Rhythm: meet, keeps hits shared with lane 1")
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .rhythm, mode: "AVOID", lane: 1, rowOn: true), "Rhythm: avoid, keeps hits apart from lane 1")
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .pitch, mode: "SHADOW", lane: 2, rowOn: true), "Pitch: shadow, plays the note lane 2 plays now")
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .pitch, mode: "MIRROR", lane: 1, rowOn: true), "Pitch: mirror, lane 1's note flipped")
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .pitch, mode: "DODGE", lane: 1, rowOn: true), "Pitch: dodge, steps off lane 1's note")
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .trade, mode: "SWAP", lane: 4, rowOn: true), "Trade: swap, trades places with lane 4")
        XCTAssertEqual(euclideousAnswerModeSpoken(row: .trade, mode: "BORROW", lane: 2, rowOn: false), "Trade: borrow, takes lane 2's setup, off")
        XCTAssertEqual(euclideousAnswerCycleToggleLabel(row: .rhythm, lane: 0), "Cycle rhythm, lane 1"); XCTAssertEqual(euclideousAnswerCycleToggleLabel(row: .pitch, lane: 2), "Cycle pitch, lane 3")
        XCTAssertEqual(euclideousAnswerWithSpoken(lane: 2, mode: .swap), "lane 3, swap"); XCTAssertEqual(euclideousAnswerWithSpoken(lane: 1, mode: .borrow), "lane 2, borrow")
    }
    func testThePhaseBarNamesWhoseTurnItIsAndHowFarThroughTheHalf() {
        var l = EuclidLine(); l.listenSource = 0; l.answerRhythmOn = true; l.answerRhythmCycle = true; l.answerTradeOn = true; l.answerTradeWith = 2
        XCTAssertEqual(euclideousAnswerPhaseSpoken(lane: 1, line: l, status: EuclideousAnswerLaneStatus()), "not running")
        XCTAssertEqual(euclideousAnswerPhaseSpoken(lane: 1, line: l, status: EuclideousAnswerLaneStatus(running: true, phaseB: false, unitInHalf: 0, each: 4, progress: 0)), "following lane 1, 1 of 4")
        XCTAssertEqual(euclideousAnswerPhaseSpoken(lane: 1, line: l, status: EuclideousAnswerLaneStatus(running: true, phaseB: true, unitInHalf: 2, each: 4, progress: 0.7)), "lane 3, 3 of 4")
        l.answerRhythmOn = false; l.answerTradeOn = false
        XCTAssertEqual(euclideousAnswerPhaseSpoken(lane: 1, line: l, status: EuclideousAnswerLaneStatus(running: true, phaseB: false, unitInHalf: 1, each: 2, progress: 0.2)), "own, 2 of 2")
    }
    func testTheReduceMotionPlayheadMovesInQuarterUnits() {
        XCTAssertEqual(euclideousAnswerPlayheadQuantised(0.0, each: 4), 0)
        XCTAssertEqual(euclideousAnswerPlayheadQuantised(0.03, each: 4), 0, "within the first stop")
        XCTAssertEqual(euclideousAnswerPlayheadQuantised(0.04, each: 4), 1.0 / 32, accuracy: 1e-12)
        XCTAssertLessThanOrEqual(euclideousAnswerPlayheadQuantised(1.0, each: 1), 1)
    }
}
