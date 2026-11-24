//  DrumModeTests.swift — DRUM MODE ferry (2026-11-23): the model (§1) + the pure ramp (§2.2) + APPLY TO ALL (§1.6).
//  The engine's pool/velocity/same-pitch behaviour (§2) is in KitSourceRouterTests; the golden harness proves that with
//  no DRUM lane the output is byte-identical.

import XCTest

final class DrumModeTests: XCTestCase {

    // §6.1 defaults — new lanes and nil give fixedMode KIT, 40–100, UP, and drum notes 36/38/42/39 on lanes 1–4.
    func testDefaults() {
        let l = EuclidLine(noteSel: .all)
        XCTAssertNil(l.fixedMode); XCTAssertEqual(l.fixedModeResolved, .kit)
        XCTAssertEqual(l.drumLowResolved, 40); XCTAssertEqual(l.drumHighResolved, 100)
        XCTAssertEqual(l.drumRampResolved, .up)
        XCTAssertEqual((0..<4).map { euclideousDrumNote(l, lane: $0) }, [36, 38, 42, 39])
        XCTAssertEqual(euclideousDrumNote(l, lane: 7), 36)   // out of range ⇒ KICK
    }

    // §6.2 ramp — UP/DOWN for 40–100, equal low/high, 0–100; rounding as §2.2.
    func testRamp() {
        let up = euclideousDrumRampVels(low: 40, high: 100, ramp: .up).map { Int($0) }
        XCTAssertEqual(up, [40, 49, 57, 66, 74, 83, 91, 100])
        let down = euclideousDrumRampVels(low: 40, high: 100, ramp: .down).map { Int($0) }
        XCTAssertEqual(down, up.reversed())
        XCTAssertEqual(euclideousDrumRampVels(low: 70, high: 70, ramp: .up).map { Int($0) }, Array(repeating: 70, count: 8))
        let full = euclideousDrumRampVels(low: 0, high: 100, ramp: .up).map { Int($0) }
        XCTAssertEqual(full, [0, 14, 29, 43, 57, 71, 86, 100])   // round(100·k/7)
        XCTAssertEqual(euclideousDrumRampVel(rank: 1, low: 40, high: 100, ramp: .up), 40)
        XCTAssertEqual(euclideousDrumRampVel(rank: 8, low: 40, high: 100, ramp: .up), 100)
        XCTAssertEqual(euclideousDrumRampVel(rank: 1, low: 40, high: 100, ramp: .down), 100)
    }

    // §1.4 the drum's name is drumNote's GM short name.
    func testDrumName() {
        XCTAssertEqual(euclideousGMDrumName(36), "KICK")
        XCTAssertEqual(euclideousGMDrumName(42), "CH")
    }

    // §3.5 the high thumb is never read below the low thumb.
    func testHighNeverBelowLow() {
        var l = EuclidLine(noteSel: .all); l.drumLow = 80; l.drumHigh = 30
        XCTAssertEqual(l.drumLowResolved, 80); XCTAssertEqual(l.drumHighResolved, 80)   // high read clamped up to low
    }

    // §1.1 saving — the custom decoder must read every drum field.
    func testCodableRoundTrip() throws {
        var l = EuclidLine(noteSel: .all)
        l.fixedMode = .drum; l.drumNote = 46; l.drumLow = 25; l.drumHigh = 90; l.drumRamp = .down
        var p = PluginState(machines: [Machine(machineID: "g", type: .euclid)], scenes: [SceneState.empty()])
        p.euclideousLines = [l, EuclidLine(enabled: false), EuclidLine(enabled: false), EuclidLine(enabled: false)]
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(p)).euclideousLinesResolved[0]
        XCTAssertEqual(back.fixedModeResolved, .drum)
        XCTAssertEqual(back.drumNote, 46); XCTAssertEqual(back.drumLowResolved, 25); XCTAssertEqual(back.drumHighResolved, 90)
        XCTAssertEqual(back.drumRampResolved, .down)
        // a line with no drum keys decodes to nil (KIT, 40–100, UP)
        let fresh = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(EuclidLine(noteSel: .all)))
        XCTAssertNil(fresh.fixedMode); XCTAssertNil(fresh.drumNote)
    }

    // §1.3 switching mode changes neither the kit nor the drum.
    func testSwitchingKeepsBoth() {
        var l = EuclidLine(noteSel: .all)
        l.kitOn = true; l.kitNotes = [60, 61, 62, 63, 64, 65, 66, 67]; l.kitVel = [10, 20, 30, 40, 50, 60, 70, 80]
        l.drumNote = 44; l.drumLow = 30; l.drumHigh = 95; l.drumRamp = .down
        // KIT → DRUM → KIT: the kit fields are untouched by the mode field
        l.fixedMode = .drum; l.fixedMode = .kit
        XCTAssertEqual(l.kitNotesResolved, [60, 61, 62, 63, 64, 65, 66, 67])
        XCTAssertEqual(l.kitVelResolved, [10, 20, 30, 40, 50, 60, 70, 80])
        XCTAssertEqual(l.drumNote, 44); XCTAssertEqual(l.drumLowResolved, 30); XCTAssertEqual(l.drumHighResolved, 95); XCTAssertEqual(l.drumRampResolved, .down)
    }

    // INPUTS MODE §7.1 — decode: nil ⇒ MELODIC; stored kitOn/fixedMode map per §1.2.
    func testLaneModeMigration() {
        var l = EuclidLine(noteSel: .all)
        XCTAssertNil(l.laneMode); XCTAssertEqual(l.laneModeResolved, .melodic)
        l.kitOn = false; XCTAssertEqual(l.laneModeResolved, .melodic)
        l.kitOn = true; l.fixedMode = nil; XCTAssertEqual(l.laneModeResolved, .kit)
        l.fixedMode = .kit; XCTAssertEqual(l.laneModeResolved, .kit)
        l.fixedMode = .drum; XCTAssertEqual(l.laneModeResolved, .drum)
        l.laneMode = .melodic; XCTAssertEqual(l.laneModeResolved, .melodic, "an explicit laneMode wins over the old fields")
        XCTAssertTrue(EuclidLine(noteSel: .all).laneModeResolved == .melodic)
        XCTAssertFalse(EuclidLine(noteSel: .all).euclideousFixedLane)
    }

    // INPUTS MODE §7.2 — switching MELODIC → KIT → DRUM → MELODIC keeps every mode's settings.
    func testModeSwitchKeepsEverything() {
        var l = EuclidLine(noteSel: .all)
        l.poolSrcMask = 0b01010; l.midiMode = .root
        l.kitNotes = [60, 61, 62, 63, 64, 65, 66, 67]; l.kitVel = [10, 20, 30, 40, 50, 60, 70, 80]
        l.drumNote = 44; l.drumLow = 30; l.drumHigh = 95; l.drumRamp = .down
        l.laneMode = .melodic; l.laneMode = .kit; l.laneMode = .drum; l.laneMode = .melodic
        XCTAssertEqual(l.poolSrcMask, 0b01010); XCTAssertEqual(l.midiMode, .root)
        XCTAssertEqual(l.kitNotesResolved, [60, 61, 62, 63, 64, 65, 66, 67]); XCTAssertEqual(l.kitVelResolved, [10, 20, 30, 40, 50, 60, 70, 80])
        XCTAssertEqual(l.drumNote, 44); XCTAssertEqual(l.drumHighResolved, 95); XCTAssertEqual(l.drumRampResolved, .down)
    }

    // INPUTS MODE §7.1 round-trip — the custom decoder reads laneMode.
    func testLaneModeCodable() throws {
        var l = EuclidLine(noteSel: .all); l.laneMode = .drum
        var p = PluginState(machines: [Machine(machineID: "g", type: .euclid)], scenes: [SceneState.empty()])
        p.euclideousLines = [l, EuclidLine(enabled: false), EuclidLine(enabled: false), EuclidLine(enabled: false)]
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(p)).euclideousLinesResolved[0]
        XCTAssertEqual(back.laneModeResolved, .drum)
    }

    // §6.10 APPLY TO ALL copies fixedMode + the four drum fields (drumNote materialised from the source lane).
    func testApplyToAll() {
        var lines = (0..<4).map { _ in EuclidLine(noteSel: .all) }
        lines[0].kitOn = true; lines[0].fixedMode = .drum; lines[0].drumNote = 50; lines[0].drumLow = 20; lines[0].drumHigh = 80; lines[0].drumRamp = .down
        euclideousApplyInputsToAll(&lines, from: 0)
        for i in 1..<4 {
            XCTAssertEqual(lines[i].fixedModeResolved, .drum)
            XCTAssertEqual(euclideousDrumNote(lines[i], lane: i), 50, "the source's drum note, not lane i's default")
            XCTAssertEqual(lines[i].drumLowResolved, 20); XCTAssertEqual(lines[i].drumHighResolved, 80)
            XCTAssertEqual(lines[i].drumRampResolved, .down)
        }
    }
}
