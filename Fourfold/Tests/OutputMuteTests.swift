//  OutputMuteTests.swift — the MUTE tab's per-output mute model (ferry "LANES → MUTE: each block is an emitter", 2026-11-02).
//  Slice 1 covers the pure model (clamp, bounds, cell/pass edits, Codable tolerance). The engine gate is proven in RouterTests / PortsStressTests.

import XCTest

final class OutputMuteTests: XCTestCase {

    func testDefaultsAreNothingMuted() {
        let m = EuclideousOutputMute()
        XCTAssertEqual(m.cells16, 0xFFFF, "every cell sounds by default")
        XCTAssertEqual(m.passes, 1, "the lowest / default resolution is 1 pass")
        XCTAssertTrue(m.isDefault)
        XCTAssertFalse(m.hasMute)
        XCTAssertTrue(EuclideousOutputMutes().isAllDefault)
        XCTAssertFalse(EuclideousOutputMutes().anyMuted, "a fresh set has nothing muted ⇒ the Router skips the gate")
    }

    func testPassLadderIsBounded1to8() {
        var m = EuclideousOutputMute()
        XCTAssertFalse(m.canDec, "◀ disabled at the floor")
        XCTAssertTrue(m.canInc)
        // step up to the ceiling
        for expected in 2...8 { m = m.steppingPasses(up: true); XCTAssertEqual(Int(m.passes), expected) }
        XCTAssertEqual(m.passes, 8)
        XCTAssertFalse(m.canInc, "▶ disabled at the ceiling")
        XCTAssertEqual(m.steppingPasses(up: true).passes, 8, "no wrap past 8")
        // and back down
        for expected in stride(from: 7, through: 1, by: -1) { m = m.steppingPasses(up: false); XCTAssertEqual(Int(m.passes), expected) }
        XCTAssertEqual(m.passes, 1)
        XCTAssertEqual(m.steppingPasses(up: false).passes, 1, "no wrap below 1")
    }

    func testNormalizeClampsStoredPasses() {
        XCTAssertEqual(EuclideousOutputMute(cells16: 0, passes: 0).normalized().passes, 1, "0 clamps up to 1")
        XCTAssertEqual(EuclideousOutputMute(cells16: 0, passes: 99).normalized().passes, 8, "a big value clamps to 8")
        // the subscript normalises on write
        var set = EuclideousOutputMutes()
        set[2] = EuclideousOutputMute(cells16: 0x00FF, passes: 200)
        XCTAssertEqual(set[2].passes, 8)
        XCTAssertEqual(set[2].cells16, 0x00FF)
    }

    func testCellEditsAndSounds() {
        let m = EuclideousOutputMute().settingCell(3, sounds: false).settingCell(10, sounds: false)
        XCTAssertFalse(m.sounds(3)); XCTAssertFalse(m.sounds(10))
        XCTAssertTrue(m.sounds(0)); XCTAssertTrue(m.sounds(15))
        XCTAssertTrue(m.hasMute)
        XCTAssertTrue(m.settingCell(3, sounds: true).settingCell(10, sounds: true).isDefault, "clearing both mutes returns to all-sounding")
        XCTAssertTrue(m.sounds(-1) && m.sounds(16), "an out-of-range cell never silences")
    }

    func testAnyMutedTracksEachOutput() {
        var set = EuclideousOutputMutes()
        XCTAssertFalse(set.anyMuted)
        set[1] = set[1].settingCell(0, sounds: false)
        XCTAssertTrue(set.anyMuted, "one muted cell on output B is enough")
    }

    func testCodableRoundTripAndTolerance() throws {
        var set = EuclideousOutputMutes()
        set[0] = EuclideousOutputMute(cells16: 0xAA55, passes: 5)
        set[3] = EuclideousOutputMute(cells16: 0x0001, passes: 8)
        let data = try JSONEncoder().encode(set)
        XCTAssertEqual(try JSONDecoder().decode(EuclideousOutputMutes.self, from: data), set)
        // a non-array / garbage payload decodes to the defaults, never a throw
        XCTAssertEqual(try JSONDecoder().decode(EuclideousOutputMutes.self, from: Data("{}".utf8)), EuclideousOutputMutes())
        // a short array leaves the rest at defaults
        let shortData = Data("[{\"cells16\":5,\"passes\":3}]".utf8)
        let decoded = try JSONDecoder().decode(EuclideousOutputMutes.self, from: shortData)
        XCTAssertEqual(decoded[0], EuclideousOutputMute(cells16: 5, passes: 3))
        XCTAssertTrue(decoded[1].isDefault && decoded[2].isDefault && decoded[3].isDefault)
    }

    func testPluginStateResolvedNilIsDefault() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        XCTAssertNil(p.euclideousOutputMutes)
        XCTAssertTrue(p.euclideousOutputMutesResolved.isAllDefault, "nil ⇒ nothing muted, byte-identical")
        p.euclideousOutputMutes = EuclideousOutputMutes([EuclideousOutputMute(cells16: 0x00F0, passes: 2)])
        XCTAssertEqual(p.euclideousOutputMutesResolved[0].passes, 2)
    }

    func testOutputLetterAndPassLabel() {
        XCTAssertEqual((0..<4).map(euclideousOutputLetter), ["A", "B", "C", "D"])
        XCTAssertEqual(euclideousOutputMutePassLabel(1), "1 PASS")
        XCTAssertEqual(euclideousOutputMutePassLabel(8), "8 PASS")
        XCTAssertEqual(euclideousOutputMuteCellLabel(output: 1, cell: 2, sounding: false), "Output B cell 3, muted")
        XCTAssertEqual(euclideousOutputMuteRailLabel(output: 0, passes: 1), "Output A showing 1 pass")
        XCTAssertEqual(euclideousOutputMuteRailLabel(output: 3, passes: 4), "Output D showing 4 passes")
        // MUTE ZOOM (2026-11-03): the unlabelled ◀ / ▶ arrows still name themselves to VoiceOver.
        XCTAssertEqual(euclideousOutputZoomLabel(output: 0, passes: 1, zoomIn: true), "Output A zoom in, showing 1 pass")
        XCTAssertEqual(euclideousOutputZoomLabel(output: 2, passes: 8, zoomIn: false), "Output C zoom out, showing 8 passes")
    }

    // NOTE: the old per-lane mute is deliberately NOT migrated (the 16 cells now divide a 1…8-pass window, not the
    // per-lane cell size). An old session's per-lane mute keeps sounding via the Router's still-live per-lane gate; it
    // is just not shown in the new per-output MUTE tab. See OutputMute.swift's "The old per-lane mute is NOT migrated".
}
