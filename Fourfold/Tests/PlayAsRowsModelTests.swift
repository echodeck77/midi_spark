//  PlayAsRowsModelTests.swift — PLAY AS ROWS ferry (2026-11-11): the MODEL half (§1, §10.6, §10.9).
//
//  Slice 1 fixes the new per-lane fields — the three chains (ORDER/VOICES/SPREAD), per-rank counts + AGAIN/LATER timing, BASS and SHIFT/DRIFT — their §1.9 defaults, decode-tolerance, round-trip, the no-migration rule (§1.10),
//  and that a locked lane snaps the new NOTES-row controls back (LaneLockFields). The engine (the pass builder and each-hit pick) is Slice 2's `PlayAsRows*Tests`.

import XCTest

final class PlayAsRowsModelTests: XCTestCase {
    private func roundTrip(_ l: EuclidLine) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l)) }

    // §1.9 — a new lane takes the defaults: ORDER [UP], VOICES [1], SPREAD [TOGETHER], every chip 4 hits; each rank count 1, AGAIN, AGAIN; bass off / HOLD; start 0, drift off, step +1.
    func testDefaultsAreTheNineOne() {
        let l = EuclidLine()
        XCTAssertEqual(l.notesOrderChainResolved, [EuclideousOrderChip(value: .up, hits: 4)])
        XCTAssertEqual(l.notesVoicesChainResolved, [EuclideousVoicesChip(value: .one, hits: 4)])
        XCTAssertEqual(l.notesSpreadChainResolved, [EuclideousSpreadChip(value: .together, hits: 4)])
        for r in 1...8 {   // ranks are 1…8 (code-review 2026-11-12: the count/timing accessors index rank, not a 0-based slot)
            XCTAssertEqual(l.notesRankCount(r), 1, "rank \(r) count")
            XCTAssertEqual(l.notesRankSecond(r), .again); XCTAssertEqual(l.notesRankThird(r), .again)
        }
        XCTAssertFalse(l.notesBassOnResolved); XCTAssertEqual(l.notesBassModeResolved, .hold)
        XCTAssertEqual(l.notesShiftStartResolved, 0); XCTAssertFalse(l.notesDriftOnResolved); XCTAssertEqual(l.notesDriftStepResolved, 1)
        // The default lane stores NOTHING new (byte-identical to a document that never had the fields): every new field is nil.
        XCTAssertNil(l.notesOrderChain); XCTAssertNil(l.notesRankCounts); XCTAssertNil(l.notesRankSecondLater)
        XCTAssertNil(l.notesBassOn); XCTAssertNil(l.notesShiftStart); XCTAssertNil(l.notesDriftOn); XCTAssertNil(l.notesDriftStep)
    }

    // §10.9 / §1.10 — an old document (PLAY AS data, no new keys) decodes with the §1.9 defaults, and its PLAY AS data is still there.
    func testOldDocumentDecodesWithDefaultsAndKeepsPlayAs() throws {
        let json = "{\"target\":0,\"pulses\":4,\"steps\":8,\"notesPlaySeq\":[{\"mode\":\"ROLL\",\"hits\":3},{\"mode\":\"BUILD\",\"hits\":2}],\"notesPlayAs\":\"CYCLE\"}"
        let l = try JSONDecoder().decode(EuclidLine.self, from: Data(json.utf8))
        XCTAssertEqual(l.notesPlaySeq, [EuclideousPlayStep(mode: .roll, hits: 3), EuclideousPlayStep(mode: .build, hits: 2)])   // still decodable (§0.2)
        XCTAssertEqual(l.notesPlayAs, .cycle)
        XCTAssertEqual(l.notesOrderChainResolved, [EuclideousOrderChip()])   // new model at its defaults
        XCTAssertNil(l.notesOrderChain)
    }

    // §1.1-§1.3 round-trip, and chip-hits clamp 1…32.
    func testChainsRoundTripAndClampHits() throws {
        var l = EuclidLine()
        l.notesOrderChain = [EuclideousOrderChip(value: .shuffle, hits: 99), EuclideousOrderChip(value: .asAdded, hits: 0)]
        l.notesVoicesChain = [EuclideousVoicesChip(value: .all, hits: 7), EuclideousVoicesChip(value: .grow, hits: 2)]
        l.notesSpreadChain = [EuclideousSpreadChip(value: .strum, hits: 1), EuclideousSpreadChip(value: .run, hits: 4)]
        XCTAssertEqual(l.notesOrderChain?[0].hits, 32); XCTAssertEqual(l.notesOrderChain?[1].hits, 1)   // clamped at construction
        let back = try roundTrip(l)
        XCTAssertEqual(back.notesOrderChain, l.notesOrderChain)
        XCTAssertEqual(back.notesVoicesChain, l.notesVoicesChain)
        XCTAssertEqual(back.notesSpreadChain, l.notesSpreadChain)
    }

    // §6.5 — the per-rank count store: cycle 1→2→3→1, independent per rank, AGAIN/LATER bits, and the default packs to nil.
    func testRankCountStore() throws {
        var l = EuclidLine()
        l.cycleNotesRankCount(2); XCTAssertEqual(l.notesRankCount(2), 2)
        l.cycleNotesRankCount(2); XCTAssertEqual(l.notesRankCount(2), 3)
        l.cycleNotesRankCount(2); XCTAssertEqual(l.notesRankCount(2), 1); XCTAssertNil(l.notesRankCounts)   // back to 1 everywhere ⇒ nil
        l.setNotesRankCount(5, 3); XCTAssertEqual(l.notesRankCount(5), 3); XCTAssertEqual(l.notesRankCount(2), 1)   // independent
        l.setNotesRankSecond(5, .later); l.setNotesRankThird(5, .later)
        XCTAssertEqual(l.notesRankSecond(5), .later); XCTAssertEqual(l.notesRankThird(5), .later)
        XCTAssertEqual(l.notesRankSecond(4), .again)   // independent
        let back = try roundTrip(l)
        XCTAssertEqual(back.notesRankCount(5), 3); XCTAssertEqual(back.notesRankSecond(5), .later); XCTAssertEqual(back.notesRankThird(5), .later)
        // clearing back to AGAIN stores nil
        l.setNotesRankSecond(5, .again); l.setNotesRankThird(5, .again)
        XCTAssertNil(l.notesRankSecondLater); XCTAssertNil(l.notesRankThirdLater)
    }

    // §1.8 — SHIFT / DRIFT resolve and clamp; DRIFT never resolves to 0.
    func testShiftDrift() throws {
        var l = EuclidLine()
        l.notesShiftStart = 99; XCTAssertEqual(l.notesShiftStartResolved, 15)
        l.notesShiftStart = -3; XCTAssertEqual(l.notesShiftStartResolved, 0)
        l.notesDriftStep = 0; XCTAssertEqual(l.notesDriftStepResolved, 1, "0 is not a legal step — §1.8 skips it")
        l.notesDriftStep = -40; XCTAssertEqual(l.notesDriftStepResolved, -8)
        l.notesDriftOn = true; l.notesShiftStart = 5; l.notesDriftStep = -2
        let back = try roundTrip(l)
        XCTAssertEqual(back.notesShiftStartResolved, 5); XCTAssertTrue(back.notesDriftOnResolved); XCTAssertEqual(back.notesDriftStepResolved, -2)
    }

    // Unknown stored enum values decode to the §1.9 default (never a whole-session reset).
    func testUnknownEnumValuesDecodeToDefault() throws {
        XCTAssertEqual(try JSONDecoder().decode(EuclideousOrderMode.self, from: Data("\"SIDEWAYS\"".utf8)), .up)
        XCTAssertEqual(try JSONDecoder().decode(EuclideousVoicesMode.self, from: Data("\"NINE\"".utf8)), .one)
        XCTAssertEqual(try JSONDecoder().decode(EuclideousSpreadMode.self, from: Data("\"SCATTER\"".utf8)), .together)
        XCTAssertEqual(try JSONDecoder().decode(EuclideousBassMode.self, from: Data("\"LAST\"".utf8)), .hold)
        XCTAssertEqual(try JSONDecoder().decode(EuclideousCopyTiming.self, from: Data("\"SOON\"".utf8)), .again)
    }

    // The lock holds the new NOTES-row fields: a locked lane edited on them is DEVIATED, and snapping back restores them.
    func testLockHoldsTheNewFields() {
        var base = EuclidLine(target: 0, pulses: 4, steps: 8)
        base.notesOrderChain = [EuclideousOrderChip(value: .down, hits: 2), EuclideousOrderChip(value: .bounce, hits: 3)]
        base.notesBassOn = true; base.notesBassMode = .first; base.setNotesRankCount(3, 2); base.notesShiftStart = 4; base.notesDriftOn = true; base.notesDriftStep = 2
        let locked = LaneLockFields(line: base)
        XCTAssertFalse(euclideousLockDeviated(line: base, from: locked))
        var edited = base
        edited.notesOrderChain = [EuclideousOrderChip(value: .up, hits: 4)]
        XCTAssertTrue(euclideousLockDeviated(line: edited, from: locked), "an ORDER-chain edit deviates")
        edited.notesShiftStart = 9
        XCTAssertTrue(euclideousLockDeviated(line: edited, from: locked))
        // snap back
        locked.applied(to: &edited)
        XCTAssertEqual(edited.notesOrderChain, base.notesOrderChain)
        XCTAssertEqual(edited.notesShiftStartResolved, 4); XCTAssertEqual(edited.notesRankCount(3), 2)
        XCTAssertTrue(edited.notesBassOnResolved); XCTAssertEqual(edited.notesBassModeResolved, .first)
    }
}
