//  MastersTests.swift — HEADER v2 ferry (2026-11-19), §9: the pure functions behind the two global PLAY-part
//  masters (laneSounds §8.1, euclideousMasterPips §8.2) and the document round-trip (§1.1 / §9 test 6).
//  The Router-gate tests (§9 tests 3-5) live in RouterTests (they reuse its render harness).

import XCTest

final class MastersTests: XCTestCase {
    // §9 test 2: laneSounds — all four combinations. A part sounds exactly when BOTH its own PLAY and its master are on.
    func testLaneSoundsIsTheAndOfPlayAndMaster() {
        XCTAssertTrue(laneSounds(true, true))
        XCTAssertFalse(laneSounds(true, false), "a lane on, master off → silent")
        XCTAssertFalse(laneSounds(false, true), "a lane off, master on → silent")
        XCTAssertFalse(laneSounds(false, false))
    }

    // §9 test 8: masterPips — every combination of master and lane part.
    func testMasterPipsEveryCombination() {
        // master ON: on-parts filled 100 %, off-parts outline
        XCTAssertEqual(euclideousMasterPips(master: true, parts: [true, false, true, false]),
                       [.filled(opacity: 1.0), .outline, .filled(opacity: 1.0), .outline])
        // master OFF: on-parts filled 30 % (they WILL return), off-parts still outline
        XCTAssertEqual(euclideousMasterPips(master: false, parts: [true, true, false, false]),
                       [.filled(opacity: 0.30), .filled(opacity: 0.30), .outline, .outline])
        // all off
        XCTAssertEqual(euclideousMasterPips(master: true, parts: [false, false, false, false]),
                       [.outline, .outline, .outline, .outline])
        XCTAssertEqual(euclideousMasterPips(master: false, parts: [false, false, false, false]),
                       [.outline, .outline, .outline, .outline])
    }
    // RE-ENABLE ON ENABLE (Paul 2026-11-20): enabling a lane's part solos it — every other lane's same part turns off.
    func testEnableLanePartSolo() {
        let lines = (0..<4).map { _ -> EuclidLine in var l = EuclidLine(noteSel: .all); l.riffOn = true; l.notesOn = true; return l }
        let r = euclideousEnableLanePartSolo(lines, lane: 2, isNotes: false)
        XCTAssertEqual(r.map { $0.riffOnResolved }, [false, false, true, false], "riff: only lane 2 stays on")
        XCTAssertEqual(r.map { $0.notesOnResolved }, lines.map { $0.notesOnResolved }, "riff solo leaves notes untouched")
        // stack: clear other lanes' selections first so the layer-on test is meaningful
        var cleared = lines; for i in cleared.indices { cleared[i].setLitOrder(EuclideousLitOrder()) }
        let s = euclideousEnableLanePartSolo(cleared, lane: 1, isNotes: true)
        XCTAssertEqual(s.map { euclideousNotesLayerIsOn($0) }, [false, true, false, false], "stack: only lane 1 plays")
        XCTAssertTrue(euclideousNotesHaveSelection(s[1]), "the enabled lane gets a lit rank so the layer reads on")
        XCTAssertEqual(euclideousEnableLanePartSolo(lines, lane: 9, isNotes: false).map { $0.riffOnResolved }, [true, true, true, true], "out-of-range lane is a no-op")
    }
    // PLAY STACK (Paul 2026-11-20): a lane with no ranks selected shows EMPTY (not the off-outline) — it must not read as enabled.
    func testStackMasterPipsEmptyWhenNoRanks() {
        // lane 0 plays (filled), lane 1 has ranks but part off (outline), lanes 2 & 3 have NO ranks (empty)
        XCTAssertEqual(euclideousStackMasterPips(master: true, parts: [true, false, false, false], hasRanks: [true, true, false, false]),
                       [.filled(opacity: 1.0), .outline, .empty, .empty])
        // with ranks everywhere it matches the plain master pips
        XCTAssertEqual(euclideousStackMasterPips(master: false, parts: [true, false, true, false], hasRanks: [true, true, true, true]),
                       euclideousMasterPips(master: false, parts: [true, false, true, false]))
    }

    // §10.1: the master's spoken VALUE — off, or "on, lanes …" naming the lanes whose own part is on.
    func testMasterVoiceOverValue() {
        XCTAssertEqual(euclideousMasterVoiceOverValue(master: false, parts: [true, true, false, true]), "off")
        XCTAssertEqual(euclideousMasterVoiceOverValue(master: true, parts: [false, false, false, false]), "on, no lanes")
        XCTAssertEqual(euclideousMasterVoiceOverValue(master: true, parts: [true, false, false, false]), "on, lane 1")
        XCTAssertEqual(euclideousMasterVoiceOverValue(master: true, parts: [true, true, false, false]), "on, lanes 1 and 2")
        XCTAssertEqual(euclideousMasterVoiceOverValue(master: true, parts: [true, true, false, true]), "on, lanes 1, 2 and 4")
    }

    // §9 test 6: a session without the fields resolves both ON and round-trips; a session saved with riffMaster off reloads off.
    func testSavedDataRoundTripAndResolveOn() throws {
        let enc = JSONEncoder(); let dec = JSONDecoder()
        // (a) a fresh document has nil masters → both resolve ON
        var fresh = PluginState(machines: [], scenes: [SceneState.empty()])
        XCTAssertNil(fresh.riffMaster); XCTAssertNil(fresh.stackMaster)
        XCTAssertTrue(fresh.riffMasterResolved); XCTAssertTrue(fresh.stackMasterResolved)
        // the encoded form omits the absent keys (synthesized encodeIfPresent) — i.e. exactly an OLD session
        let freshJSON = try enc.encode(fresh)
        XCTAssertFalse(String(data: freshJSON, encoding: .utf8)!.contains("riffMaster"), "a fresh/old session carries no masters key")
        let backFresh = try dec.decode(PluginState.self, from: freshJSON)
        XCTAssertNil(backFresh.riffMaster); XCTAssertTrue(backFresh.riffMasterResolved, "an old session loads with both masters on")
        XCTAssertTrue(backFresh.stackMasterResolved)
        // (b) a document saved with riffMaster off reloads off; stackMaster left on
        fresh.riffMaster = false; fresh.stackMaster = true
        let back = try dec.decode(PluginState.self, from: try enc.encode(fresh))
        XCTAssertEqual(back.riffMaster, false); XCTAssertFalse(back.riffMasterResolved, "riffMaster off reloads off")
        XCTAssertEqual(back.stackMaster, true); XCTAssertTrue(back.stackMasterResolved)
    }
}
