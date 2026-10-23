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
}
