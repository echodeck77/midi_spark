//  ReelExportTests.swift — REEL PHASE 0 (2026-10-25): what an export is called, when SAVE can act and why it cannot, and the "older passes dropped" notice. Docs/reel-redesign-plan.md; findings REEL-1, REEL-5, REEL-6.

import XCTest

final class ReelExportTests: XCTestCase {

    // MARK: names (REEL-5: every export used to be "Fourfold-A.mid", so the second overwrote the first)

    func testTheKernelsFileNamesBecomeTheShortLabels() {
        XCTAssertEqual(reelExportLabel(kernelName: "Fourfold-All.mid"), "All")
        XCTAssertEqual(reelExportLabel(kernelName: "Fourfold-A.mid"), "A")
        XCTAssertEqual(reelExportLabel(kernelName: "Fourfold-D.mid"), "D")
        XCTAssertEqual(reelExportLabel(kernelName: "something.mid"), "something")
        XCTAssertEqual(reelExportLabel(kernelName: ".mid"), "Reel", "an empty label is never produced")
    }

    func testPassesAreNamedOneBasedAndARangeReadsLowToHigh() {
        XCTAssertEqual(reelPassSpanText(lo: 7, hi: 7), "pass 8")
        XCTAssertEqual(reelPassSpanText(lo: 7, hi: 8), "passes 8-9")
        XCTAssertEqual(reelPassSpanText(lo: 12, hi: 3), "passes 4-13", "a range picked right-to-left reads the same")
        XCTAssertEqual(reelPassSpanText(lo: 0, hi: 0), "pass 1")
    }

    func testAFileNameCarriesWhenWhatAndWhichOutput() {
        XCTAssertEqual(reelExportFileName(stamp: "2026-10-25 14-52-07", lo: 7, hi: 8, label: "A"), "Fourfold 2026-10-25 14-52-07 passes 8-9 A.mid")
        XCTAssertEqual(reelExportFileName(stamp: "2026-10-25 14-52-07", lo: 7, hi: 7, label: "All"), "Fourfold 2026-10-25 14-52-07 pass 8 All.mid")
    }

    func testEveryExportNameIsPlainAndSafe() {
        let bad = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        for label in ["All", "A", "B", "C", "D"] {
            let n = reelExportFileName(stamp: reelExportStamp(Date(timeIntervalSince1970: 1_800_000_000)), lo: 3, hi: 9, label: label)
            XCTAssertNil(n.rangeOfCharacter(from: bad), "\(n) must not contain a path or reserved character")
            XCTAssertTrue(n.unicodeScalars.allSatisfy { $0.isASCII }, "\(n) stays ASCII so no DAW chokes on it")
            XCTAssertTrue(n.hasSuffix(".mid"))
        }
    }

    func testTheStampIsDateThenTimeInTheGivenZoneWithNoColons() {
        let utc = TimeZone(identifier: "UTC")!
        XCTAssertEqual(reelExportStamp(Date(timeIntervalSince1970: 0), timeZone: utc), "1970-01-01 00-00-00")
        XCTAssertEqual(reelExportStamp(Date(timeIntervalSince1970: 1791954429), timeZone: utc), "2026-10-14 05-07-09")   // 2026-10-14 05:07:09 UTC, worked out independently
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(reelExportStamp(Date(timeIntervalSince1970: 0), timeZone: tokyo), "1970-01-01 09-00-00")
        XCTAssertFalse(reelExportStamp(Date(), timeZone: utc).contains(":"))
    }

    func testTwoFilesWithTheSameNameBecomeTwoFiles() {
        var taken: Set<String> = []
        func save(_ name: String) -> String { let u = reelUniqueFileName(name, exists: { taken.contains($0) }); taken.insert(u); return u }
        let n = "Fourfold 2026-10-25 14-52-07 pass 8 A.mid"
        XCTAssertEqual(save(n), n)
        XCTAssertEqual(save(n), "Fourfold 2026-10-25 14-52-07 pass 8 A 2.mid")
        XCTAssertEqual(save(n), "Fourfold 2026-10-25 14-52-07 pass 8 A 3.mid")
        XCTAssertEqual(taken.count, 3, "three saves, three files")
        XCTAssertEqual(save("Fourfold 2026-10-25 14-52-07 pass 9 A.mid"), "Fourfold 2026-10-25 14-52-07 pass 9 A.mid", "a different name is untouched")
    }

    func testOneSaveGivesEveryFileTheSameStampSoTheySortTogether() {
        let stamp = reelExportStamp(Date(timeIntervalSince1970: 1_800_000_123))
        let names = ["All", "A", "B"].map { reelExportFileName(stamp: stamp, lo: 4, hi: 6, label: $0) }
        XCTAssertEqual(Set(names.map { $0.prefix("Fourfold 2026-01-01 00-00-00".count) }).count, 1)
        XCTAssertEqual(Set(names).count, 3)
    }

    // MARK: when SAVE can act, and why it cannot (REEL-6: it did nothing, silently, in two cases)

    func testNothingRecordedSaysSo() {
        XCTAssertEqual(reelExportAvailability(anyPass: false, selected: false, outputCounts: [0, 0, 0, 0], lanes: []), ReelExportAvailability(ok: false, reason: "Nothing recorded yet."))
    }

    func testNoSelectionAsksForOne() {
        let a = reelExportAvailability(anyPass: true, selected: false, outputCounts: [12, 0, 0, 0], lanes: [])
        XCTAssertFalse(a.ok); XCTAssertEqual(a.reason, "Tap a pass to choose what to save.")
    }

    func testTheMasterMixNeedsNotesOnAnyOutput() {
        XCTAssertEqual(reelExportAvailability(anyPass: true, selected: true, outputCounts: [0, 0, 0, 5], lanes: []), ReelExportAvailability(ok: true, reason: nil))
        XCTAssertEqual(reelExportAvailability(anyPass: true, selected: true, outputCounts: [0, 0, 0, 0], lanes: []), ReelExportAvailability(ok: false, reason: "No notes in these passes."))
    }

    func testAnEmptyOutputIsNamedInsteadOfBeingSilentlySkipped() {
        // a lane with only a riff has nothing on its Notes port, so ticking that port and pressing SAVE used to do nothing at all (ports: 0 = Riff A, 1 = Notes A, 2 = Riff B …)
        let a = reelExportAvailability(anyPass: true, selected: true, outputCounts: [40, 0, 0, 0, 0, 0, 0, 0], lanes: [1])
        XCTAssertFalse(a.ok); XCTAssertEqual(a.reason, "Nothing on Notes A in these passes.")
        XCTAssertEqual(reelExportAvailability(anyPass: true, selected: true, outputCounts: [40, 0, 0, 0, 0, 0, 0, 0], lanes: [1, 2, 3]).reason, "Nothing on Notes A, Riff B, Notes B in these passes.")
    }

    func testAMixOfFullAndEmptyOutputsStillSaves() {
        XCTAssertTrue(reelExportAvailability(anyPass: true, selected: true, outputCounts: [40, 0, 0, 0], lanes: [0, 1]).ok, "A has notes; B just writes no file")
        XCTAssertTrue(reelExportAvailability(anyPass: true, selected: true, outputCounts: [40, 7, 0, 0], lanes: [0, 1]).ok)
    }

    func testShortOrOutOfRangeCountsNeverCrash() {
        XCTAssertFalse(reelExportAvailability(anyPass: true, selected: true, outputCounts: [], lanes: [2]).ok)
        XCTAssertFalse(reelExportAvailability(anyPass: true, selected: true, outputCounts: [5], lanes: [9]).ok)
        XCTAssertFalse(reelExportAvailability(anyPass: true, selected: true, outputCounts: [5], lanes: [-1]).ok)
    }

    // MARK: older passes dropped (REEL-1: the tape forgets after 64 passes and nothing said so)

    func testNoNoticeWhileTheTapeStillHoldsPassOne() {
        XCTAssertNil(reelDroppedPassesNotice(passNumbers: []))
        XCTAssertNil(reelDroppedPassesNotice(passNumbers: [-1, -1, 0, 1, 2]))
        XCTAssertNil(reelDroppedPassesNotice(passNumbers: [-1, -1, -1]))
    }

    func testTheNoticeNamesWhatIsGone() {
        // 64 slots, oldest→newest, the ring now holds passes 8…71 (0-based 7…70): passes 1-7 are gone
        let held = Array(7..<71)
        XCTAssertEqual(held.count, 64)
        XCTAssertEqual(reelDroppedPassesNotice(passNumbers: held), "Passes 1-7 have dropped off the tape.")
        XCTAssertEqual(reelDroppedPassesNotice(passNumbers: [-1, 1, 2, 3]), "Pass 1 has dropped off the tape.")
    }

    func testTheNoticeFollowsTheRealRing() {
        // record 80 passes through the real deck and ask what it says
        let deck = ReelDeck()
        for p in 0..<80 { deck.cycleBeats = 4; deck.startPass(pass: p); deck.record(beat: 0, cable: 1, 0x90, 60, 100); deck.record(beat: 1, cable: 1, 0x80, 60, 0); deck.promote() }
        XCTAssertEqual(deck.passCounter, 80)
        XCTAssertEqual(reelDroppedPassesNotice(passNumbers: deck.passNumbers()), "Passes 1-16 have dropped off the tape.", "80 filed, 64 kept: numbers 16…79 held, so 1-16 (1-based) are gone")
        let fresh = ReelDeck()
        for p in 0..<10 { fresh.startPass(pass: p); fresh.record(beat: 0, cable: 1, 0x90, 60, 100); fresh.promote() }
        XCTAssertNil(reelDroppedPassesNotice(passNumbers: fresh.passNumbers()))
    }
}
