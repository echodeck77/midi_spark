//  NotesTabTests.swift
//  NOTES TAB ferry (2026-10-19, "octave and velocity go, WHEN RIFF, seven ways to PLAY AS, CHANCE and RECEIVED; FILL leaves ON REST"): the pure surface —
//  the model + migration (§5, test 10), the engine functions (§6-§7, tests 2-6), the layout (§1/§3/§4, test 12) and the displays (§10, test 11).
//  The Router side (tests 1, 7-9, 13, 14) lives in RouterTests next to the harness it needs.
//
//  The example lane (§13): riff ranks by column [8, 0, 8, 6, 0, 6, 5, 0] (0 = a rest), the hits on steps 1, 3, 5, 6, 8 read columns 6, 8, 2, 3, 5 — so the hits on
//  1 and 6 play the riff (A♭3, C4) and the hits on 3, 5, 8 are rests. KEY C MINOR pool: C3 D3 E♭3 F3 G3 A♭3 B♭3 + the octave copy C4. Lit in this order: rank 8, 5, 6.

import XCTest

final class NotesTabTests: XCTestCase {

    private func decode(_ json: String) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: Data(json.utf8)) }
    private func roundTrip(_ l: EuclidLine) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l)) }
    private func jsonObject(_ l: EuclidLine) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as! [String: Any]
    }

    // MARK: 10. persistence and migration

    func testAPreFeatureDocumentGetsTheSoundPreservingWhen() throws {
        // riff OFF: the lit notes sounded on every hit -> both, whatever ON REST said
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":false,"litNotes":16,"riffOnRest":"SKIP"}"#).notesWhenResolved, 0b11)
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":false,"litNotes":16,"riffOnRest":"TIE"}"#).notesWhenResolved, 0b11)
        // riff ON: SKIP and TIE silenced the lit notes on a rest hit -> PLAYS only; FILL and REPEAT sounded them -> both
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16,"riffOnRest":"SKIP"}"#).notesWhenResolved, 0b01)
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16}"#).notesWhenResolved, 0b01, "no ON REST stored = SKIP")
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16,"riffOnRest":"TIE"}"#).notesWhenResolved, 0b01)
        XCTAssertEqual(try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16,"riffOnRest":"REPEAT"}"#).notesWhenResolved, 0b11)
        let fill = try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":true,"litNotes":16,"riffOnRest":"FILL"}"#)
        XCTAssertEqual(fill.notesWhenResolved, 0b11, "FILL sounded the lit notes on a rest, so it becomes SKIP with both"); XCTAssertEqual(fill.riffOnRestResolved, .skip)
        // the defaults of everything else
        let l = try decode(#"{"target":0,"pulses":5,"steps":8}"#)
        XCTAssertEqual(l.notesChanceResolved, 100); XCTAssertEqual(l.notesPlayAsResolved, .chord); XCTAssertFalse(l.notesReceivedOnlyResolved)
    }
    func testALaneMadeInThisBuildKeepsBothWhenWhenIsUntouchedEvenOnTie() throws {
        var l = EuclidLine(target: 0, pulses: 5, steps: 8); l.riffOn = true; l.riffOnRest = .tie
        XCTAssertEqual(l.notesWhenResolved, 0b11, "a fresh lane: PLAYS and RESTS both on")
        XCTAssertNotNil(try jsonObject(l)["notesWhen"], "the encoder always writes notesWhen, so the migration only ever meets an old document")
        let back = try roundTrip(l)
        XCTAssertEqual(back.notesWhenResolved, 0b11); XCTAssertEqual(back.riffOnRestResolved, .tie)
        l.notesWhen = 0b01
        XCTAssertEqual(try roundTrip(l).notesWhenResolved, 0b01, "a stored PLAYS-only survives")
    }
    func testWhenChanceAndWayDecodeToLegalValues() throws {
        func l(_ extra: String) throws -> EuclidLine { try decode(#"{"target":0,"pulses":5,"steps":8,"riffOn":false,"# + extra + "}") }
        XCTAssertEqual(try l(#""notesWhen":0"#).notesWhenResolved, 0b11, "neither bit -> both")
        XCTAssertEqual(try l(#""notesWhen":6"#).notesWhenResolved, 0b10, "higher bits dropped")
        XCTAssertEqual(try l(#""notesWhen":2"#).notesWhenResolved, 0b10)
        XCTAssertEqual([60, 63, 0, 200, 25, 50, 75, 100, 37, 38, -4].map { EuclidLine.nearestLegalNotesChance($0) }, [50, 75, 25, 100, 25, 50, 75, 100, 25, 50, 25])
        for (stored, want) in [(60, 50), (63, 75), (0, 25), (200, 100)] {
            XCTAssertEqual(try l(#""notesChance":\#(stored)"#).notesChance, want, "\(stored) is stored already normalised")
        }
        XCTAssertEqual(try l(#""notesPlayAs":"WIGGLE""#).notesPlayAsResolved, .chord, "an unknown way decodes as CHORD")
        XCTAssertEqual(try l(#""notesPlayAs":"BOUNCE""#).notesPlayAsResolved, .bounce)
        XCTAssertEqual(try l(#""notesPlayAs":7"#).notesPlayAsResolved, .chord, "a wrong-typed way is missing, not a whole-session reset")
    }
    func testTheLitOrderIsTheSourceOfTruthAndTheLegacyTrioFollowsIt() throws {
        // a lane without an order takes it from litNotes / TOP 2 / TOP: ranks low to high, then TOP 2, then TOP
        let old = try decode(#"{"target":0,"pulses":5,"steps":8,"litNotes":177,"topLit":true,"top2Lit":true}"#)   // 177 = ranks 1, 5, 6, 8
        XCTAssertEqual(old.litOrderResolved.array, [0, 4, 5, 7, 8, 9])
        // an invalid stored order (a repeat, a 10, too long) counts as missing
        for bad in ["[7,4,7]", "[10]", "[0,1,2,3,4,5,6,7,8,9,0]"] {
            let l = try decode(#"{"target":0,"pulses":5,"steps":8,"litNotes":16,"notesLitOrder":\#(bad)}"#)
            XCTAssertEqual(l.litOrderResolved.array, [4], "\(bad) falls back to 5.2")
        }
        // a valid one wins, and the trio is rewritten from it — read back and as encoded
        let l = try decode(#"{"target":0,"pulses":5,"steps":8,"litNotes":1,"notesLitOrder":[7,4,5,9]}"#)
        XCTAssertEqual(l.litOrderResolved.array, [7, 4, 5, 9])
        XCTAssertEqual(l.litNotesResolved, 0b1011_0000); XCTAssertTrue(l.topLitResolved); XCTAssertFalse(l.top2LitResolved)
        XCTAssertEqual(l.litNotes, 0b1011_0000, "the stored trio agrees with the order after decode"); XCTAssertEqual(l.topLit, true); XCTAssertEqual(l.top2Lit, false)
        // every writer goes through setLitOrder: the encoder writes the trio from the order
        var m = EuclidLine(target: 0, pulses: 5, steps: 8)
        var o = EuclideousLitOrder(); o.append(7); o.append(4); o.append(5); o.append(8)
        m.setLitOrder(o)
        let json = try jsonObject(m)
        XCTAssertEqual(json["notesLitOrder"] as? [Int], [7, 4, 5, 8])
        XCTAssertEqual(json["litNotes"] as? Int, 0b1011_0000); XCTAssertEqual(json["top2Lit"] as? Bool, true); XCTAssertEqual(json["topLit"] as? Bool, false)
        let back = try roundTrip(m)
        XCTAssertEqual(back.litOrderResolved.array, [7, 4, 5, 8]); XCTAssertEqual(back, m, "every field round-trips")
    }
    func testTogglingKeysUsesTheOrderLightingAddsAtTheEnd() {
        var l = EuclidLine(target: 0, pulses: 5, steps: 8)
        euclideousToggleNotesKey(&l, rank: 8); euclideousToggleNotesKey(&l, rank: 5); euclideousToggleNotesKey(&l, rank: 6)
        XCTAssertEqual(l.litOrderResolved.array, [7, 4, 5])
        euclideousToggleNotesKey(&l, rank: 5)
        XCTAssertEqual(l.litOrderResolved.array, [7, 5], "unlighting takes it out")
        euclideousToggleNotesKey(&l, rank: 5)
        XCTAssertEqual(l.litOrderResolved.array, [7, 5, 4], "lighting it again puts it at the END")
        euclideousToggleNotesTop2(&l); euclideousToggleNotesTop(&l)
        XCTAssertEqual(l.litOrderResolved.array, [7, 5, 4, 8, 9])
        XCTAssertEqual(l.litNotesResolved, 0b1011_0000); XCTAssertTrue(l.top2LitResolved); XCTAssertTrue(l.topLitResolved)
        XCTAssertTrue(l.notesOnResolved)
        var off = EuclidLine(target: 0, pulses: 5, steps: 8); off.notesOn = false
        euclideousToggleNotesKey(&off, rank: 1)
        XCTAssertTrue(off.notesOnResolved, "a tap on an off layer also turns it on (unchanged)")
    }
    func testTheNotesTabFieldsAllRoundTripAndPerNoteShiftsStayDecodable() throws {
        var l = EuclidLine(target: 0, pulses: 5, steps: 8)
        l.notesWhen = 0b10; l.notesChance = 75; l.notesPlayAs = .build; l.notesReceivedOnly = true
        l.noteOctShifts = [1, -1, 0, 0, 0, 0, 0, 1]; l.notesVelOffset = -20
        var o = EuclideousLitOrder(); o.append(9); o.append(0); l.setLitOrder(o)
        let back = try roundTrip(l)
        XCTAssertEqual(back, l)
        XCTAssertEqual(back.notesWhenResolved, 0b10); XCTAssertEqual(back.notesChanceResolved, 75); XCTAssertEqual(back.notesPlayAsResolved, .build)
        XCTAssertTrue(back.notesReceivedOnlyResolved); XCTAssertEqual(back.noteOctShiftsResolved, [1, -1, 0, 0, 0, 0, 0, 1]); XCTAssertEqual(back.notesVelOffsetResolved, -20)
    }
}
