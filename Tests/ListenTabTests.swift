//  ListenTabTests.swift
//  LISTEN tab rebuild (ferry 2026-10-23, "Fourfold Listen Tab"): §8 model/migration tests. The pure
//  functions (§9) and engine (§3-§5) get their own suites once those land; this file covers the new
//  EuclidLine fields' round-trip and the old-model → new-model decode migration (§8.3), including the
//  AVOID+ANY and source-conflict judgment calls this ferry's plan discloses rather than blocks on.

import XCTest

final class ListenTabTests: XCTestCase {

    // MARK: 1. the new fields round-trip and decode safely without their keys

    func testListenRebuiltFieldsDecodeWithoutTheirKeys() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertFalse(line.usesNewListen)
        XCTAssertEqual(line.listenRhythmResolved, .own); XCTAssertEqual(line.listenPitchResolved, .own)
        XCTAssertFalse(line.isFollowingResolved)
        XCTAssertEqual(line.listenDelayResolved, 0); XCTAssertEqual(line.listenFeelResolved, 0, accuracy: 1e-9)
        XCTAssertEqual(line.listenSpeedResolved, 0); XCTAssertEqual(line.listenSpeedRatioResolved, 1, accuracy: 1e-9)
        XCTAssertEqual(line.listenDirectionResolved, .fwd)
        XCTAssertEqual(line.listenIntervalResolved, 0); XCTAssertEqual(line.listenOctaveResolved, 0)
    }
    func testListenRebuiltFieldsRoundTripThroughCodable() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.listenSource = 2; line.listenRhythm = .copy; line.listenDelay = 3; line.listenFeel = -0.4
        line.listenSpeed = 1; line.listenDirection = .bkw; line.listenPitch = .echo; line.listenInterval = -5; line.listenOctave = 2
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertTrue(back.usesNewListen)
        XCTAssertEqual(back.listenSourceResolved(ownLane: 0), 2)
        XCTAssertEqual(back.listenRhythmResolved, .copy); XCTAssertEqual(back.listenPitchResolved, .echo)
        XCTAssertTrue(back.isFollowingResolved)
        XCTAssertEqual(back.listenDelayResolved, 3); XCTAssertEqual(back.listenFeelResolved, -0.4, accuracy: 1e-9)
        XCTAssertEqual(back.listenSpeedResolved, 1); XCTAssertEqual(back.listenSpeedRatioResolved, 2, accuracy: 1e-9)
        XCTAssertEqual(back.listenDirectionResolved, .bkw)
        XCTAssertEqual(back.listenIntervalResolved, -5); XCTAssertEqual(back.listenOctaveResolved, 2)
    }
    func testListenSourceResolvedNeverPointsAtItself() {
        var line = EuclidLine(pulses: 3, steps: 8)
        XCTAssertEqual(line.listenSourceResolved(ownLane: 0), 1, "no stored source: the lowest OTHER lane")
        XCTAssertEqual(line.listenSourceResolved(ownLane: 2), 0)
        line.listenSource = 1
        XCTAssertEqual(line.listenSourceResolved(ownLane: 1), 0, "a stored source equal to this lane's own index is ignored, falling back")
        XCTAssertEqual(line.listenSourceResolved(ownLane: 0), 1, "a stored source different from this lane's own index is honoured")
    }
    func testListenSpeedExponentClampsToPlusMinusTwoAndRatioIsDirect() {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.listenSpeed = 99
        XCTAssertEqual(line.listenSpeedResolved, 2); XCTAssertEqual(line.listenSpeedRatioResolved, 4, accuracy: 1e-9, "x4")
        line.listenSpeed = -99
        XCTAssertEqual(line.listenSpeedResolved, -2); XCTAssertEqual(line.listenSpeedRatioResolved, 0.25, accuracy: 1e-9, "x1/4")
    }
    func testListenIntervalAndOctaveClamp() {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.listenInterval = 99; line.listenOctave = 99
        XCTAssertEqual(line.listenIntervalResolved, 6); XCTAssertEqual(line.listenOctaveResolved, 3)
        line.listenInterval = -99; line.listenOctave = -99
        XCTAssertEqual(line.listenIntervalResolved, -6); XCTAssertEqual(line.listenOctaveResolved, -3)
    }

    // MARK: 2. §8.3 migration — every old mode combination maps to its documented new-model equivalent

    func testMigrationLeavesAnUntouchedLaneCompletelyNil() {
        let m = EuclidLine.migratedListen(rhythmMode: nil, rhythmPartner: nil, pitchMode: nil, pitchPartner: nil,
                                           pitchPartnerAny: nil, shadowInterval: nil, shadowOctave: nil)
        XCTAssertNil(m, "nothing to migrate ⇒ nil everywhere, byte-identical to a doc that never touched LISTEN")
    }
    func testMigrationFollowBecomesCopy() {
        let m = EuclidLine.migratedListen(rhythmMode: .follow, rhythmPartner: 2, pitchMode: nil, pitchPartner: nil,
                                           pitchPartnerAny: nil, shadowInterval: nil, shadowOctave: nil)!
        XCTAssertEqual(m.rhythm, .copy); XCTAssertEqual(m.source, 2); XCTAssertNil(m.pitch)
    }
    func testMigrationGapsBecomesFill() {
        let m = EuclidLine.migratedListen(rhythmMode: .gaps, rhythmPartner: 3, pitchMode: nil, pitchPartner: nil,
                                           pitchPartnerAny: nil, shadowInterval: nil, shadowOctave: nil)!
        XCTAssertEqual(m.rhythm, .fill); XCTAssertEqual(m.source, 3)
    }
    func testMigrationWithBecomesOwn() {
        let m = EuclidLine.migratedListen(rhythmMode: .with, rhythmPartner: 1, pitchMode: nil, pitchPartner: nil,
                                           pitchPartnerAny: nil, shadowInterval: nil, shadowOctave: nil)!
        XCTAssertEqual(m.rhythm, .own, "WITH has no new-model rhythm equivalent — the row returns to OWN")
    }
    func testMigrationShadowKeepsItsNameAndCarriesIntervalOctave() {
        let m = EuclidLine.migratedListen(rhythmMode: nil, rhythmPartner: nil, pitchMode: .shadow, pitchPartner: 1,
                                           pitchPartnerAny: nil, shadowInterval: 4, shadowOctave: -1)!
        XCTAssertEqual(m.pitch, .shadow); XCTAssertEqual(m.source, 1); XCTAssertEqual(m.interval, 4); XCTAssertEqual(m.octave, -1)
    }
    func testMigrationShadowIntervalClampsFromTheOldWiderRangeIntoTheNewOne() {
        // old range was -7...7; new INTERVAL is -6...6 — the outermost old value is a real, disclosed loss.
        let m = EuclidLine.migratedListen(rhythmMode: nil, rhythmPartner: nil, pitchMode: .shadow, pitchPartner: 0,
                                           pitchPartnerAny: nil, shadowInterval: 7, shadowOctave: -2)!
        XCTAssertEqual(m.interval, 6, "old +7 clamps into the new narrower +6 ceiling")
        XCTAssertEqual(m.octave, -2, "old octave range (-2...2) is strictly inside the new one (-3...3): no clamping needed")
    }
    func testMigrationAvoidKeepsItsNameAndDropsTheMoveAction() {
        // MOVE isn't even a parameter to migratedListen — the new AVOID is mute-only by construction, so
        // there is nothing for a MOVE-action lane to carry across beyond which lane it targets.
        let m = EuclidLine.migratedListen(rhythmMode: nil, rhythmPartner: nil, pitchMode: .avoid, pitchPartner: 2,
                                           pitchPartnerAny: false, shadowInterval: nil, shadowOctave: nil)!
        XCTAssertEqual(m.pitch, .avoid); XCTAssertEqual(m.source, 2); XCTAssertNil(m.interval); XCTAssertNil(m.octave)
    }
    func testMigrationAvoidWithAnyFallsBackToTheStoredSpecificPartner() {
        let m = EuclidLine.migratedListen(rhythmMode: nil, rhythmPartner: nil, pitchMode: .avoid, pitchPartner: 3,
                                           pitchPartnerAny: true, shadowInterval: nil, shadowOctave: nil)!
        XCTAssertEqual(m.source, 3, "ANY has no new-model equivalent (one shared source, no multi-lane option) — falls back to the lane's own remembered specific partner")
    }
    func testMigrationAvoidWithAnyAndNoStoredPartnerFallsBackToLaneZero() {
        let m = EuclidLine.migratedListen(rhythmMode: nil, rhythmPartner: nil, pitchMode: .avoid, pitchPartner: nil,
                                           pitchPartnerAny: true, shadowInterval: nil, shadowOctave: nil)!
        XCTAssertEqual(m.source, 0, "no remembered partner at all: the §8.2 default (lowest-numbered other lane) rule's own fallback value")
    }
    func testMigrationRhythmPartnerWinsTheSourceConflictOverPitchPartner() {
        // Old model: independent partners per row — RHYTHM following lane 1, PITCH shadowing lane 2. The
        // new model has one shared source; RHYTHM's partner wins (RHYTHM-before-PITCH ordering throughout
        // the spec), a disclosed judgment call for a case §8.3's own table doesn't cover.
        let m = EuclidLine.migratedListen(rhythmMode: .follow, rhythmPartner: 1, pitchMode: .shadow, pitchPartner: 2,
                                           pitchPartnerAny: nil, shadowInterval: 3, shadowOctave: 0)!
        XCTAssertEqual(m.rhythm, .copy); XCTAssertEqual(m.pitch, .shadow)
        XCTAssertEqual(m.source, 1, "RHYTHM's own partner (1), not PITCH's (2)")
        XCTAssertEqual(m.interval, 3, "SHADOW's own interval/octave still carry across even though its partner lost the source conflict")
    }
    func testMigrationDuckAccentAmountHaveNoParametersAtAllTheyAreSimplyDropped() {
        // There is no listenLevelMode/listenLevelPartner/listenLevelAmount parameter on migratedListen —
        // confirming by construction that the LEVEL row (DUCK/ACCENT/AMOUNT) has nothing to migrate to.
        let m = EuclidLine.migratedListen(rhythmMode: .follow, rhythmPartner: 1, pitchMode: nil, pitchPartner: nil,
                                           pitchPartnerAny: nil, shadowInterval: nil, shadowOctave: nil)!
        XCTAssertEqual(m.rhythm, .copy)
    }
    func testMigrationDelayFeelSpeedDirectionAlwaysDefaultRegardlessOfTheOldFollowMult() {
        // migratedListen never even takes listenFollowMult as a parameter — confirming DELAY/FEEL/SPEED/
        // DIRECTION always come out nil (⇒ their own 0/0/0/FWD defaults), per §8.3's explicit instruction,
        // never derived from FOLLOW's old (and differently-scaled) rate multiplier.
        var line = EuclidLine(pulses: 3, steps: 8)
        line.listenRhythmMode = .follow; line.listenRhythmPartner = 1; line.listenFollowMult = 2   // old x4
        let data = try! JSONEncoder().encode(line)
        let back = try! JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertEqual(back.listenRhythmResolved, .copy)
        XCTAssertEqual(back.listenDelayResolved, 0); XCTAssertEqual(back.listenFeelResolved, 0, accuracy: 1e-9)
        XCTAssertEqual(back.listenSpeedResolved, 0, "not 2 — the old FOLLOW multiplier never carries across"); XCTAssertEqual(back.listenDirectionResolved, .fwd)
    }

    // MARK: 3. migration runs through the real decoder exactly once, and only while untouched

    func testADocumentAlreadyOnTheNewModelIsNeverReMigrated() throws {
        // Explicitly set BOTH an old FOLLOW and a new row at .own — usesNewListen is true (an explicit new
        // field is set), so migration must not override the explicit OWN back to COPY.
        var line = EuclidLine(pulses: 3, steps: 8)
        line.listenRhythmMode = .follow; line.listenRhythmPartner = 1   // old, stale
        line.listenRhythm = .own                                        // new, explicit — the user already decided
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertTrue(back.usesNewListen)
        XCTAssertEqual(back.listenRhythmResolved, .own, "the explicit new-model OWN is never clobbered by the stale old FOLLOW")
    }
    func testAGenuinelyLegacyDocumentMigratesThroughTheRealDecoder() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"listenPitchMode":"SHADOW","listenPitchPartner":2,"listenShadowInterval":3,"listenShadowOctave":1}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)
        XCTAssertTrue(line.usesNewListen)
        XCTAssertEqual(line.listenPitchResolved, .shadow)
        XCTAssertEqual(line.listenSourceResolved(ownLane: 0), 2)
        XCTAssertEqual(line.listenIntervalResolved, 3); XCTAssertEqual(line.listenOctaveResolved, 1)
        // the old fields themselves stay decoded too (hide, don't delete — §0.2)
        XCTAssertEqual(line.listenPitchMode, .shadow); XCTAssertEqual(line.listenPitchPartner, 2)
    }

    // MARK: 4. §9 pure functions

    func testIsFollowingIsTrueWheneverEitherRowIsNotOwn() {
        XCTAssertFalse(euclideousListenIsFollowing(rhythm: .own, pitch: .own))
        XCTAssertTrue(euclideousListenIsFollowing(rhythm: .copy, pitch: .own))
        XCTAssertTrue(euclideousListenIsFollowing(rhythm: .own, pitch: .shadow))
        XCTAssertTrue(euclideousListenIsFollowing(rhythm: .fill, pitch: .avoid))
    }
    func testFollowsTransitivelyWalksTheChainAndStopsAtNil() {
        // 0 -> 1 -> 2; 3 follows nothing.
        let sources: [Int?] = [1, 2, nil, nil]
        XCTAssertTrue(euclideousListenFollowsTransitively(lane: 0, target: 1, sources: sources))
        XCTAssertTrue(euclideousListenFollowsTransitively(lane: 0, target: 2, sources: sources), "transitively, through lane 1")
        XCTAssertFalse(euclideousListenFollowsTransitively(lane: 0, target: 3, sources: sources))
        XCTAssertFalse(euclideousListenFollowsTransitively(lane: 2, target: 0, sources: sources), "2 follows nothing")
        XCTAssertFalse(euclideousListenFollowsTransitively(lane: 3, target: 0, sources: sources))
    }
    func testFollowsTransitivelyIsBoundedAgainstAStrayCycle() {
        // a cycle that should never be stored, but must not hang the walk if it somehow were.
        let sources: [Int?] = [1, 0, nil, nil]
        XCTAssertTrue(euclideousListenFollowsTransitively(lane: 0, target: 1, sources: sources))
        XCTAssertFalse(euclideousListenFollowsTransitively(lane: 0, target: 2, sources: sources))
    }
    func testDisabledSourcesExcludesSelfAndAnythingThatAlreadyFollowsThisLane() {
        // 1 -> 0 (lane 1 follows lane 0). Lane 0's own FOLLOW-row picker must disable lane 1 (picking it
        // as lane 0's source would close the loop) and lane 0 itself.
        let sources: [Int?] = [nil, 0, nil, nil]
        let disabled = euclideousListenDisabledSources(lane: 0, sources: sources)
        XCTAssertEqual(disabled, Set([0, 1]))
        XCTAssertEqual(euclideousListenDisabledSources(lane: 2, sources: sources), Set([2]), "lane 2 has no followers — only itself is disabled")
    }
    func testProcessingOrderPutsASourceBeforeItsFollowerAndIgnoresAStaleSourceWhenOwn() {
        // lane 1 copies lane 0's rhythm; lane 2 has a stale `source=1` but both its rows are OWN, so it
        // has NO live dependency and may land anywhere relative to lane 1.
        let order = euclideousListenProcessingOrder(sources: [0, 0, 1, 0], rhythm: [.own, .copy, .own, .own], pitch: [.own, .own, .own, .own])
        XCTAssertEqual(order.count, 4)
        XCTAssertLessThan(order.firstIndex(of: 0)!, order.firstIndex(of: 1)!, "lane 0 (the source) before lane 1 (the follower)")
    }
    func testProcessingOrderNeverHangsOnAStrayCycle() {
        let order = euclideousListenProcessingOrder(sources: [1, 0, 0, 0], rhythm: [.copy, .copy, .own, .own], pitch: [.own, .own, .own, .own])
        XCTAssertEqual(Set(order), Set(0...3), "every lane still appears exactly once")
    }
    func testBreakLoopsOnTheNewModelForcesTheFirstLaneThatClosesACycleBackToOwn() {
        var lines = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        lines[0].listenRhythm = .copy; lines[0].listenSource = 1   // 0 -> 1
        lines[1].listenPitch = .shadow; lines[1].listenSource = 0  // 1 -> 0, closing the loop
        let fixed = euclideousListenBreakLoopsOnTheNewModel(lines)
        XCTAssertEqual(fixed[0].listenRhythmResolved, .copy, "lane 0 (scanned first) is untouched — it didn't close anything yet")
        XCTAssertEqual(fixed[1].listenRhythmResolved, .own); XCTAssertEqual(fixed[1].listenPitchResolved, .own, "lane 1's own edge is what closed the loop")
    }
    func testBreakLoopsOnTheNewModelLeavesAnAcyclicGraphUntouched() {
        var lines = [EuclidLine(), EuclidLine(), EuclidLine(), EuclidLine()]
        lines[1].listenRhythm = .copy; lines[1].listenSource = 0
        lines[2].listenPitch = .echo; lines[2].listenSource = 1
        let fixed = euclideousListenBreakLoopsOnTheNewModel(lines)
        XCTAssertEqual(fixed[1].listenRhythmResolved, .copy); XCTAssertEqual(fixed[2].listenPitchResolved, .echo)
    }
    func testBorrowedHitsCopyTakesTheSourcesHitsFillTakesItsRests() {
        let source = [true, false, true, false, false]
        var out = [Bool](repeating: false, count: 5)
        XCTAssertEqual(euclideousListenBorrowedHits(sourcePattern: source, n: 5, mode: .copy, into: &out), 5)
        XCTAssertEqual(out, source)
        XCTAssertEqual(euclideousListenBorrowedHits(sourcePattern: source, n: 5, mode: .fill, into: &out), 5)
        XCTAssertEqual(out, [false, true, false, true, true])
    }
    func testBorrowedIndexForwardMirrorsTheSourcesOwnLiveOrderIncludingWhenTheSourceIsPendulum() {
        // FWD: the follower's raw counter fed straight through the SOURCE's own direction function — a
        // pendulum (PING-PONG) source gives a pendulum follower "for free," matching §3.4's own example.
        for raw in 0..<8 {
            XCTAssertEqual(euclideousListenBorrowedIndex(followerRaw: raw, n: 4, followerDirection: .fwd, sourceDirection: .pingpong),
                            euclidReadIndex(raw % euclidCycleLen(.pingpong, n: 4), n: 4, dir: .pingpong), "raw \(raw)")
        }
        // a plain FWD source under a FWD follower is just identity.
        for raw in 0..<4 {
            XCTAssertEqual(euclideousListenBorrowedIndex(followerRaw: raw, n: 4, followerDirection: .fwd, sourceDirection: .fwd), raw)
        }
    }
    func testBorrowedIndexBackwardReversesTheSourcesOrder() {
        // source FWD, follower BKW: step 0 reads the source's LAST step, not its first.
        XCTAssertEqual(euclideousListenBorrowedIndex(followerRaw: 0, n: 4, followerDirection: .bkw, sourceDirection: .fwd), 3)
        XCTAssertEqual(euclideousListenBorrowedIndex(followerRaw: 3, n: 4, followerDirection: .bkw, sourceDirection: .fwd), 0)
    }
    func testBorrowedIndexPingPongUsesTheSourcesStoredOrderIgnoringItsLiveDirection() {
        // even if the source is itself BKW, a PING-PONG follower ping-pongs the STORED (FWD) order.
        XCTAssertEqual(euclideousListenBorrowedIndex(followerRaw: 0, n: 4, followerDirection: .pingpong, sourceDirection: .bkw), 0)
        XCTAssertEqual(euclideousListenBorrowedIndex(followerRaw: 4, n: 4, followerDirection: .pingpong, sourceDirection: .bkw), 3, "the turn")
        XCTAssertEqual(euclideousListenBorrowedIndex(followerRaw: 5, n: 4, followerDirection: .pingpong, sourceDirection: .bkw), 2, "bouncing back")
    }
    func testFollowerPositionIsNilBeforeTheDelayedStepsHaveElapsed() {
        // sourceStepBeats 1, DELAY 2, SPEED x1: the follower's own raw step 0 and 1 are "not yet" (rawAfterDelay < 0).
        XCTAssertNil(euclideousListenFollowerPosition(beat: 0, startBeat: 0, sourceStepBeats: 1, n: 4, speed: 0, delay: 2, direction: .fwd, sourceDirection: .fwd))
        XCTAssertNil(euclideousListenFollowerPosition(beat: 1, startBeat: 0, sourceStepBeats: 1, n: 4, speed: 0, delay: 2, direction: .fwd, sourceDirection: .fwd))
        XCTAssertEqual(euclideousListenFollowerPosition(beat: 2, startBeat: 0, sourceStepBeats: 1, n: 4, speed: 0, delay: 2, direction: .fwd, sourceDirection: .fwd), 0,
                       "the DELAYth step is the first one that plays (position 0 of the borrowed pattern)")
    }
    func testFollowerPositionAtDefaultsTracksTheSourceStepForStep() {
        for raw in 0..<8 {
            let beat = Double(raw) * 1.0
            XCTAssertEqual(euclideousListenFollowerPosition(beat: beat, startBeat: 0, sourceStepBeats: 1, n: 4, speed: 0, delay: 0, direction: .fwd, sourceDirection: .fwd),
                           raw % 4, "defaults (delay 0, speed x1, fwd): sample-for-sample with the source")
        }
    }
    func testFollowerPositionSpeedHalvesOrDoublesTheEffectiveStepLength() {
        // SPEED x2 (exponent 1): follower step length is sourceStepBeats/2 — twice as many follower steps per source step.
        XCTAssertEqual(euclideousListenFollowerPosition(beat: 0.5, startBeat: 0, sourceStepBeats: 1, n: 4, speed: 1, delay: 0, direction: .fwd, sourceDirection: .fwd), 1)
        // SPEED x1/2 (exponent -1): follower step length is sourceStepBeats*2 — half as many steps; beat 1 is still raw step 0.
        XCTAssertEqual(euclideousListenFollowerPosition(beat: 1, startBeat: 0, sourceStepBeats: 1, n: 4, speed: -1, delay: 0, direction: .fwd, sourceDirection: .fwd), 0)
        XCTAssertEqual(euclideousListenFollowerPosition(beat: 2, startBeat: 0, sourceStepBeats: 1, n: 4, speed: -1, delay: 0, direction: .fwd, sourceDirection: .fwd), 1)
    }
    func testEchoIndexPlaysTheCurrentCycleWhileItHasReachedThatRankElseTheLastOneElseRest() {
        XCTAssertEqual(euclideousListenEchoIndex(j: 0, currentCount: 3, lastCount: 8), .current(0))
        XCTAssertEqual(euclideousListenEchoIndex(j: 2, currentCount: 3, lastCount: 8), .current(2))
        XCTAssertEqual(euclideousListenEchoIndex(j: 3, currentCount: 3, lastCount: 8), .last(3), "current hasn't reached rank 3 yet — falls back to the last completed cycle")
        XCTAssertEqual(euclideousListenEchoIndex(j: 9, currentCount: 3, lastCount: 8), .last(1), "9 modulo the last cycle's own 8 strikes")
        XCTAssertEqual(euclideousListenEchoIndex(j: 0, currentCount: 0, lastCount: 0), .rest, "neither cycle has struck anything yet")
    }
    func testMoveByIntervalOnAnInScaleNoteMovesByScaleDegreesAndWrapsOctaves() {
        // C major, root 0. UNISON leaves a scale note untouched.
        XCTAssertEqual(euclideousListenMoveByInterval(note: 60, interval: 0, octave: 0, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 60)
        // a third up: C(60) -> E(64).
        XCTAssertEqual(euclideousListenMoveByInterval(note: 60, interval: 2, octave: 0, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 64)
        // a 2nd up from B(71, the scale's own top degree) wraps into the octave above: C(72).
        XCTAssertEqual(euclideousListenMoveByInterval(note: 71, interval: 1, octave: 0, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 72)
        // OCTAVE stacks on top, in whole octaves.
        XCTAssertEqual(euclideousListenMoveByInterval(note: 60, interval: 0, octave: 1, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 72)
        XCTAssertEqual(euclideousListenMoveByInterval(note: 60, interval: 0, octave: -1, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 48)
    }
    func testMoveByIntervalOnAnOutOfScaleNoteAnchorsBelowAndKeepsItsOwnOffset() {
        // C#(61) in C major: UNISON leaves it exactly where it is (anchored to C, offset +1, interval 0 ⇒ still anchor+1).
        XCTAssertEqual(euclideousListenMoveByInterval(note: 61, interval: 0, octave: 0, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 61)
        // a 2nd up: the anchor (C) moves to D, the +1 semitone offset carries, giving D#(63).
        XCTAssertEqual(euclideousListenMoveByInterval(note: 61, interval: 1, octave: 0, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 63)
    }
    func testMoveByIntervalClampsIntoTheLegalMidiRangeByWholeOctaves() {
        XCTAssertEqual(euclideousListenMoveByInterval(note: 3, interval: 0, octave: -3, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 0)
        XCTAssertEqual(euclideousListenMoveByInterval(note: 125, interval: 0, octave: 3, keyRoot: 0, scaleIntervals: ScaleType.major.intervals), 127)
    }
    func testAvoidMaskIsPitchClassOnlyOctaveIgnored() {
        let mask = euclideousListenAvoidMask(strike: [60])   // C4
        XCTAssertTrue(euclideousListenAvoidDrops(note: 60, mask: mask)); XCTAssertTrue(euclideousListenAvoidDrops(note: 72, mask: mask), "C5 — same pitch class, different octave")
        XCTAssertFalse(euclideousListenAvoidDrops(note: 61, mask: mask), "C# is a different pitch class")
    }
    func testBorrowedTabsRhythmPausesUnderCopyOrFillRiffPausesUnderShadowOrEchoNotAvoid() {
        XCTAssertEqual(euclideousListenBorrowedTabs(rhythm: .copy, pitch: .own, notesReadsRiff: true), EuclideousListenBorrowedTabs(rhythm: true, riff: false, notes: false))
        XCTAssertEqual(euclideousListenBorrowedTabs(rhythm: .fill, pitch: .own, notesReadsRiff: true), EuclideousListenBorrowedTabs(rhythm: true, riff: false, notes: false))
        XCTAssertEqual(euclideousListenBorrowedTabs(rhythm: .own, pitch: .shadow, notesReadsRiff: true), EuclideousListenBorrowedTabs(rhythm: false, riff: true, notes: true))
        XCTAssertEqual(euclideousListenBorrowedTabs(rhythm: .own, pitch: .echo, notesReadsRiff: true), EuclideousListenBorrowedTabs(rhythm: false, riff: true, notes: true))
        XCTAssertEqual(euclideousListenBorrowedTabs(rhythm: .own, pitch: .avoid, notesReadsRiff: true), EuclideousListenBorrowedTabs(rhythm: false, riff: false, notes: false),
                       "AVOID plays the lane's OWN riff live — it never pauses RIFF/NOTES")
        XCTAssertEqual(euclideousListenBorrowedTabs(rhythm: .own, pitch: .shadow, notesReadsRiff: false), EuclideousListenBorrowedTabs(rhythm: false, riff: true, notes: false),
                       "the parameter is honoured literally — only this build's one real caller supplies the confirmed `true`")
    }

    // MARK: 5. §2's own tab layout — proportional shrink with a 30pt floor, footer dropped first

    func testListenTabLayoutAtFullSizeWithNoPanelsFitsAtIdealHeightsAndKeepsTheFooter() {
        let l = euclideousListenTabLayout(contentAreaH: 202, rhythmPanelShown: false, pitchPanelShown: false)
        XCTAssertEqual(l.followRowH, 44); XCTAssertEqual(l.rhythmRowH, 44); XCTAssertEqual(l.pitchRowH, 44)
        XCTAssertEqual(l.rhythmPanelH, 0); XCTAssertEqual(l.pitchPanelH, 0)
        XCTAssertTrue(l.showFooter); XCTAssertEqual(l.footerH, 16); XCTAssertTrue(l.fits)
    }
    func testListenTabLayoutWithOnlyTheRhythmPanelDropsTheFooterAndShrinksProportionally() {
        let l = euclideousListenTabLayout(contentAreaH: 202, rhythmPanelShown: true, pitchPanelShown: false)
        XCTAssertFalse(l.showFooter); XCTAssertEqual(l.footerH, 0)
        XCTAssertEqual(l.followRowH, 32); XCTAssertEqual(l.rhythmRowH, 32); XCTAssertEqual(l.rhythmPanelH, 82); XCTAssertEqual(l.pitchRowH, 32)
        XCTAssertEqual(l.pitchPanelH, 0, "PITCH's own panel isn't shown, so it takes no height at all")
        XCTAssertFalse(l.fits, "scale < 1 — everything shrank below its ideal")
    }
    func testListenTabLayoutWithBothPanelsOpenShrinksEveryRow() {
        let l = euclideousListenTabLayout(contentAreaH: 202, rhythmPanelShown: true, pitchPanelShown: true)
        XCTAssertFalse(l.showFooter)
        XCTAssertEqual(l.followRowH, 30); XCTAssertEqual(l.rhythmRowH, 30); XCTAssertEqual(l.rhythmPanelH, 53)
        XCTAssertEqual(l.pitchRowH, 30); XCTAssertEqual(l.pitchPanelH, 53)
        XCTAssertFalse(l.fits)
    }
    func testListenTabLayoutNeverShrinksAnInteractiveRowBelowThirtyPoints() {
        let l = euclideousListenTabLayout(contentAreaH: 50, rhythmPanelShown: true, pitchPanelShown: true)
        for h in [l.followRowH, l.rhythmRowH, l.rhythmPanelH, l.pitchRowH, l.pitchPanelH] { XCTAssertGreaterThanOrEqual(h, 30) }
        XCTAssertFalse(l.fits)
    }
    func testListenTabLayoutAtAGenerousHeightNeverExceedsIdealEvenWithRoomToSpare() {
        let l = euclideousListenTabLayout(contentAreaH: 2000, rhythmPanelShown: true, pitchPanelShown: true)
        XCTAssertEqual(l.followRowH, 44); XCTAssertEqual(l.rhythmRowH, 44); XCTAssertEqual(l.rhythmPanelH, 112)
        XCTAssertEqual(l.pitchRowH, 44); XCTAssertEqual(l.pitchPanelH, 112)
        XCTAssertTrue(l.showFooter); XCTAssertTrue(l.fits)
    }
}
