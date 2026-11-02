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
        XCTAssertEqual(euclideousOutputMuteRailLabel(output: 0, passes: 1), "Output A cell size 1 pass")
        XCTAssertEqual(euclideousOutputMuteRailLabel(output: 3, passes: 4), "Output D cell size 4 passes")
    }

    // MARK: load-time migration from the old per-lane mute (lane N → output N)

    func testMigrateSeedsOutputMutesAndClearsThePerLaneGrid() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        var l0 = EuclidLine(); l0.muteCells16 = 0x00FF; l0.muteUnit = EuclideousMuteUnit.pass.rawValue       // PASS → 1
        var l2 = EuclidLine(); l2.muteCells16 = 0xF0F0; l2.muteUnit = EuclideousMuteUnit.twoPass.rawValue     // 2PASS → 2
        var l3 = EuclidLine(); l3.muteCells16 = 0xAAAA; l3.muteUnit = EuclideousMuteUnit.step.rawValue         // STEP → 1 (lossy, by design)
        p.euclideousLines = [l0, EuclidLine(), l2, l3]
        p.euclideousMigrateLaneMutesToOutputs()
        let m = p.euclideousOutputMutesResolved
        XCTAssertEqual(m[0], EuclideousOutputMute(cells16: 0x00FF, passes: 1))
        XCTAssertTrue(m[1].isDefault, "a lane with no mute migrates to the default (all sounding)")
        XCTAssertEqual(m[2], EuclideousOutputMute(cells16: 0xF0F0, passes: 2))
        XCTAssertEqual(m[3], EuclideousOutputMute(cells16: 0xAAAA, passes: 1), "STEP collapses to 1 PASS (sub-pass units can't be expressed)")
        // the per-lane grids are cleared so the per-lane strike gate goes inert
        for lane in [0, 2, 3] { XCTAssertEqual(p.euclideousLines?[lane].muteCells16, 0xFFFF) }
    }

    func testMigrateIsIdempotentAndSkipsWhenOutputMutesAlreadySet() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        var l0 = EuclidLine(); l0.muteCells16 = 0x00FF
        p.euclideousLines = [l0]
        p.euclideousMigrateLaneMutesToOutputs()
        let once = p
        p.euclideousMigrateLaneMutesToOutputs()   // the grid is now all-sounding and the field is set → a second run is a no-op
        XCTAssertEqual(p, once, "idempotent")
        // a document already on the new field is never touched, even with a stray per-lane grid
        var q = PluginState(machines: [], scenes: [SceneState.empty()])
        var ql = EuclidLine(); ql.muteCells16 = 0x0001; q.euclideousLines = [ql]
        q.euclideousOutputMutes = EuclideousOutputMutes()   // already present (all-default)
        let qBefore = q
        q.euclideousMigrateLaneMutesToOutputs()
        XCTAssertEqual(q, qBefore, "a new-field document is left as-is (the stray per-lane grid is not migrated)")
    }
}
