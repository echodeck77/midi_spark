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

    // MARK: - MUTE TAB EMITTER ROLL ferry (2026-11-09): the cell size is now a host-relative UNIT (§1.2)

    func testMuteUnitDefaultCycleAndClamp() {
        XCTAssertEqual(EuclideousOutputMute().muteUnit, 0, "default unit = 1/16")
        var m = EuclideousOutputMute()
        for expected: UInt8 in [1, 2, 3, 0, 1] { m = m.cyclingUnit(); XCTAssertEqual(m.muteUnit, expected) }   // 1/16→1/8→1/4→BAR→1/16→1/8
        XCTAssertEqual(EuclideousOutputMute(cells16: 0, passes: 1, muteUnit: 9).normalized().muteUnit, 0, "an unknown stored unit reads as 1/16")
    }

    func testMuteUnitBeats() {   // §1.2: the cell size in quarter-note beats; BAR follows the host time signature
        XCTAssertEqual(euclideousMuteUnitBeats(0, beatsPerBar: 4), 0.25, accuracy: 1e-12)   // 1/16 = a sixteenth
        XCTAssertEqual(euclideousMuteUnitBeats(1, beatsPerBar: 4), 0.5,  accuracy: 1e-12)   // 1/8
        XCTAssertEqual(euclideousMuteUnitBeats(2, beatsPerBar: 4), 1.0,  accuracy: 1e-12)   // 1/4
        XCTAssertEqual(euclideousMuteUnitBeats(3, beatsPerBar: 4), 4.0,  accuracy: 1e-12)   // BAR in 4/4
        XCTAssertEqual(euclideousMuteUnitBeats(3, beatsPerBar: 3), 3.0,  accuracy: 1e-12)   // BAR in 3/4
        XCTAssertEqual(euclideousMuteUnitBeats(99, beatsPerBar: 4), 0.25, accuracy: 1e-12)  // an unknown unit = 1/16
    }

    func testMuteUnitAudibleWindowIsAbsoluteAndNotReAnchored() {   // §2.1: 16 cells × the unit, floored off the absolute host beat
        // At 1/16 (¼ beat), cell 0 muted, the rest sounding: beats 0…0.25 silent, then audible until the 16-cell window wraps (4 beats) and cell 0 comes round again.
        let cells: UInt16 = 0xFFFE   // bit 0 cleared = cell 0 muted
        let u = euclideousMuteUnitBeats(0, beatsPerBar: 4)
        XCTAssertFalse(euclideousLaneAudible(beat: 0.0,  cells16: cells, unitBeats: u))
        XCTAssertFalse(euclideousLaneAudible(beat: 0.1,  cells16: cells, unitBeats: u))
        XCTAssertTrue (euclideousLaneAudible(beat: 0.25, cells16: cells, unitBeats: u), "cell 1 sounds")
        XCTAssertTrue (euclideousLaneAudible(beat: 3.99, cells16: cells, unitBeats: u), "cell 15 sounds")
        XCTAssertFalse(euclideousLaneAudible(beat: 4.0,  cells16: cells, unitBeats: u), "the window wraps every 4 beats — cell 0 again, still muted (absolute beat, not re-anchored)")
        XCTAssertTrue (euclideousLaneAudible(beat: 4.25, cells16: cells, unitBeats: u))
        XCTAssertTrue(euclideousLaneAudible(beat: 123.4, cells16: 0xFFFF, unitBeats: u), "all-sounding is always audible")
    }

    func testMuteUnitLabelsAndTileVoiceOver() {
        XCTAssertEqual((0..<4).map { euclideousMuteUnitLabel(UInt8($0)) }, ["1/16", "1/8", "1/4", "BAR"])
        XCTAssertEqual(euclideousOutputMuteUnitTileLabel(output: 0, unit: 0), "Output A cell size 1/16")
        XCTAssertEqual(euclideousOutputMuteUnitTileLabel(output: 3, unit: 3), "Output D cell size BAR")
    }

    func testMuteUnitCodableRoundTripAndPreFeatureDefault() throws {   // §1.3: an old document (no muteUnit key) loads at 1/16, keeping its cells
        var set = EuclideousOutputMutes()
        set[0] = EuclideousOutputMute(cells16: 0xAA55, passes: 5, muteUnit: 2)
        set[2] = EuclideousOutputMute(cells16: 0x0001, passes: 1, muteUnit: 3)
        let data = try JSONEncoder().encode(set)
        XCTAssertEqual(try JSONDecoder().decode(EuclideousOutputMutes.self, from: data), set, "muteUnit round-trips")
        // a pre-feature stored mute carried only cells16 + passes — no muteUnit key ⇒ it loads at 1/16, the pattern preserved
        let old = Data("[{\"cells16\":65518,\"passes\":4}]".utf8)
        let decoded = try JSONDecoder().decode(EuclideousOutputMutes.self, from: old)
        XCTAssertEqual(decoded[0].cells16, 0xFFEE, "the old mute pattern is kept")
        XCTAssertEqual(decoded[0].muteUnit, 0, "no stored unit ⇒ 1/16")
    }
}
