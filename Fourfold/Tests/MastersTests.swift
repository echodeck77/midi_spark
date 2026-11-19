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
