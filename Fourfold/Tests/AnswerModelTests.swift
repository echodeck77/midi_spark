import XCTest

/// ANSWER ferry (2026-11-02) §9 — the per-lane switch / mode / cycle / trade fields, their defaults, tolerant decode and the one-time migration from the OWN / COPY / FILL and
/// OWN / SHADOW / ECHO / AVOID enums. Pure model tests; the engine and UI have their own.
final class AnswerModelTests: XCTestCase {
    private func decode(_ json: String) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: Data(json.utf8)) }

    func testDefaultsAreEverySwitchOffAndTheRememberedModesCopyShadowSwap() {
        let l = EuclidLine()
        XCTAssertFalse(l.answerRhythmOnResolved); XCTAssertFalse(l.answerPitchOnResolved); XCTAssertFalse(l.answerTradeOnResolved)
        XCTAssertFalse(l.answerRhythmCycleResolved); XCTAssertFalse(l.answerPitchCycleResolved)
        XCTAssertEqual(l.answerRhythmModeResolved, .copy); XCTAssertEqual(l.answerPitchModeResolved, .shadow); XCTAssertEqual(l.answerTradeModeResolved, .swap)
        XCTAssertEqual(l.answerCycleEachResolved, 4); XCTAssertEqual(l.answerCycleUnitResolved, .bars)
        XCTAssertEqual(l.listenRhythmResolved, .own); XCTAssertEqual(l.listenPitchResolved, .own)
        XCTAssertFalse(l.isFollowingResolved); XCTAssertFalse(l.usesNewAnswer)
    }
    func testTradeWithIsTheLowestNumberedOtherLaneUntilOneIsStored() {
        var l = EuclidLine()
        XCTAssertEqual(l.answerTradeWithResolved(ownLane: 0), 1)
        for lane in 1..<4 { XCTAssertEqual(l.answerTradeWithResolved(ownLane: lane), 0) }
        l.answerTradeWith = 2
        XCTAssertEqual(l.answerTradeWithResolved(ownLane: 0), 2); XCTAssertEqual(l.answerTradeWithResolved(ownLane: 1), 2)
        XCTAssertEqual(l.answerTradeWithResolved(ownLane: 2), 0, "a lane never trades with itself")
        l.answerTradeWith = 9
        XCTAssertEqual(l.answerTradeWithResolved(ownLane: 3), 0, "out of range falls back")
    }
    func testCycleEachClampsTo1Through16() {
        var l = EuclidLine(); l.answerCycleEach = 0; XCTAssertEqual(l.answerCycleEachResolved, 1)
        l.answerCycleEach = 99; XCTAssertEqual(l.answerCycleEachResolved, 16)
        l.answerCycleEach = 9; XCTAssertEqual(l.answerCycleEachResolved, 9)
    }
    func testASwitchOffRowRemembersItsModeAndIsNotFollowing() {
        var l = EuclidLine()
        l.answerRhythmMode = .fill; l.answerPitchMode = .avoid
        XCTAssertEqual(l.listenRhythmResolved, .own, "off is off whatever the remembered mode")
        XCTAssertEqual(l.listenPitchResolved, .own); XCTAssertFalse(l.isFollowingResolved)
        l.answerRhythmOn = true; XCTAssertEqual(l.listenRhythmResolved, .fill); XCTAssertTrue(l.isFollowingResolved)
        l.answerRhythmOn = false; l.answerPitchOn = true; XCTAssertEqual(l.listenPitchResolved, .avoid); XCTAssertTrue(l.isFollowingResolved)
    }
    func testTradeIsNotFollowing() {
        var l = EuclidLine(); l.answerTradeOn = true
        XCTAssertFalse(l.isFollowingResolved, "§5.1: TRADE is not following")
    }
    func testASwitchOnWithCycleStillCountsAsFollowing() {
        var l = EuclidLine(); l.answerPitchOn = true; l.answerPitchCycle = true
        XCTAssertTrue(l.isFollowingResolved, "the loop breaker and the processing order are conservative")
    }
    func testSetAnswerWritersUseTheOldVocabulary() {
        var l = EuclidLine()
        l.setAnswerRhythm(.fill); XCTAssertEqual(l.answerRhythmOn, true); XCTAssertEqual(l.answerRhythmMode, .fill)
        l.setAnswerRhythm(.own); XCTAssertEqual(l.answerRhythmOn, false); XCTAssertEqual(l.answerRhythmMode, .fill, "OWN keeps the remembered mode")
        l.setAnswerPitch(.echo); XCTAssertEqual(l.answerPitchOn, true); XCTAssertEqual(l.answerPitchMode, .shadow, "ECHO is hidden: it writes SHADOW")
        l.setAnswerPitch(.mirror); XCTAssertEqual(l.answerPitchOn, true); XCTAssertEqual(l.answerPitchMode, .mirror)
        l.setAnswerPitch(.dodge); XCTAssertEqual(l.answerPitchMode, .dodge)
        l.setAnswerPitch(.avoid); XCTAssertEqual(l.answerPitchOn, false, "ANSWER v2 §7.2: the old pitch AVOID opens as the default — the row off"); XCTAssertEqual(l.answerPitchMode, .dodge, "the remembered mode is kept")
        l.setAnswerPitch(.own); XCTAssertEqual(l.answerPitchOn, false)
        // ANSWER v2: RHYTHM gained MEET / AVOID
        l.setAnswerRhythm(.meet); XCTAssertEqual(l.answerRhythmOn, true); XCTAssertEqual(l.answerRhythmMode, .meet)
        l.setAnswerRhythm(.avoid); XCTAssertEqual(l.answerRhythmMode, .avoid)
    }

    // MARK: migration (§9.3)

    func testMigrationTableEveryOldRhythmAndPitchMode() {
        typealias R = EuclideousListenRhythmMode; typealias P = EuclideousListenPitchMode
        let rhythmCases: [(R?, Bool, EuclideousAnswerRhythmMode)] = [(nil, false, .copy), (.own, false, .copy), (.copy, true, .copy), (.fill, true, .fill)]
        // ANSWER v2 §7.2: a legacy pitch AVOID is NOT migrated — it opens as the default (row off, SHADOW remembered).
        let pitchCases: [(P?, Bool, EuclideousAnswerPitchMode)] = [(nil, false, .shadow), (.own, false, .shadow), (.shadow, true, .shadow), (.echo, true, .shadow), (.avoid, false, .shadow)]
        for (r, rOn, rMode) in rhythmCases {
            for (p, pOn, pMode) in pitchCases {
                var l = EuclidLine(); l.listenRhythm = r; l.listenPitch = p
                let m = EuclidLine.migratedAnswer(rhythm: r, pitch: p)
                if !rOn && !pOn { XCTAssertNil(m, "OWN / nil writes nothing: \(String(describing: r)) \(String(describing: p))"); continue }
                var out = EuclidLine()
                if let m = m { out.answerRhythmOn = m.rhythmOn; out.answerRhythmMode = m.rhythmMode; out.answerPitchOn = m.pitchOn; out.answerPitchMode = m.pitchMode }
                XCTAssertEqual(out.answerRhythmOnResolved, rOn, "\(String(describing: r)) \(String(describing: p))")
                XCTAssertEqual(out.answerPitchOnResolved, pOn)
                if rOn { XCTAssertEqual(out.answerRhythmModeResolved, rMode) }
                if pOn { XCTAssertEqual(out.answerPitchModeResolved, pMode) }
            }
        }
    }
    func testAnOldDocumentThroughTheDecoderMigratesOnce() throws {
        let l = try decode(#"{"target":0,"pulses":3,"steps":8,"rotate":0,"invert":false,"listenSource":1,"listenRhythm":"FILL","listenPitch":"ECHO"}"#)
        XCTAssertEqual(l.answerRhythmOn, true); XCTAssertEqual(l.answerRhythmMode, .fill)
        XCTAssertEqual(l.answerPitchOn, true); XCTAssertEqual(l.answerPitchMode, .shadow, "an old ECHO lane opens as PITCH on, SHADOW (§7.2)")
        XCTAssertEqual(l.listenRhythmResolved, .fill); XCTAssertEqual(l.listenPitchResolved, .shadow)
        XCTAssertTrue(l.isFollowingResolved)
        XCTAssertEqual(l.listenSourceResolved(ownLane: 0), 1, "the source carries across untouched")
    }
    func testAnOwnRowStaysOffAndTheDocumentIsNotMarkedMigrated() throws {
        let l = try decode(#"{"target":0,"pulses":3,"steps":8,"rotate":0,"invert":false,"listenRhythm":"OWN","listenPitch":"OWN"}"#)
        XCTAssertFalse(l.answerRhythmOnResolved); XCTAssertFalse(l.answerPitchOnResolved); XCTAssertFalse(l.isFollowingResolved)
    }
    func testADocumentAlreadyOnTheAnswerModelIsNeverReMigrated() throws {
        // The user switched RHYTHM off after the migration: the legacy COPY is still in the file, but the explicit `false` wins.
        let l = try decode(#"{"target":0,"pulses":3,"steps":8,"rotate":0,"invert":false,"listenRhythm":"COPY","answerRhythmOn":false}"#)
        XCTAssertFalse(l.answerRhythmOnResolved)
        XCTAssertEqual(l.listenRhythmResolved, .own)
    }
    func testTheDoubleHopFromTheOldestListenModelReachesTheAnswerModel() throws {
        // The pre-REBUILD model (FOLLOW / SHADOW with a partner) migrates to listenRhythm / listenPitch first, then to ANSWER.
        let l = try decode(#"{"target":0,"pulses":3,"steps":8,"rotate":0,"invert":false,"listenRhythmMode":"FOLLOW","listenRhythmPartner":2,"listenPitchMode":"SHADOW","listenPitchPartner":2}"#)
        XCTAssertEqual(l.answerRhythmOn, true); XCTAssertEqual(l.answerRhythmMode, .copy)
        XCTAssertEqual(l.answerPitchOn, true); XCTAssertEqual(l.answerPitchMode, .shadow)
        XCTAssertEqual(l.listenSourceResolved(ownLane: 0), 2)
    }
    func testAnEncodeDecodeRoundTripKeepsEveryAnswerField() throws {
        var l = EuclidLine()
        l.answerRhythmOn = true; l.answerRhythmMode = .fill; l.answerRhythmCycle = true; l.answerPitchOn = false; l.answerPitchMode = .avoid; l.answerPitchCycle = true
        l.answerTradeOn = true; l.answerTradeMode = .borrow; l.answerTradeWith = 3; l.answerCycleEach = 11; l.answerCycleUnit = .passes
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
    }
    func testBadStoredValuesAreTolerated() throws {
        let l = try decode(#"{"target":0,"pulses":3,"steps":8,"rotate":0,"invert":false,"answerRhythmOn":"yes","answerRhythmMode":"WOBBLE","answerPitchMode":7,"answerTradeMode":null,"answerTradeWith":17,"answerCycleEach":-4,"answerCycleUnit":"FORTNIGHTS"}"#)
        XCTAssertFalse(l.answerRhythmOnResolved, "a wrong-typed value reads as missing, never a whole-session reset")
        XCTAssertEqual(l.answerRhythmModeResolved, .copy); XCTAssertEqual(l.answerPitchModeResolved, .shadow); XCTAssertEqual(l.answerTradeModeResolved, .swap)
        XCTAssertEqual(l.answerTradeWith, 3, "clamped into the lane range at decode")
        XCTAssertEqual(l.answerCycleEach, 1); XCTAssertEqual(l.answerCycleUnitResolved, .bars)
    }
    func testNoFactoryPresetUsesAListenFieldOrEcho() throws {
        // §9.3 asks for "every factory preset whose sound changed (lanes that used ECHO)": none did, so the list is empty and the golden harness is unchanged.
        for (name, make) in EuclideousPresets.all {
            let json = String(decoding: try JSONEncoder().encode(make().euclideousLinesResolved), as: UTF8.self)
            XCTAssertFalse(json.contains("\"listenPitch\":\"ECHO\""), "preset \(name) used ECHO")
            XCTAssertFalse(json.contains("\"answerPitchOn\":true") || json.contains("\"answerRhythmOn\":true"), "preset \(name) should not follow anything")
        }
    }
}
