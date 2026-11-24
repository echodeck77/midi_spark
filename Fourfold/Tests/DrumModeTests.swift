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

    // KIT EDITOR V2 §6.2 — OCT/SEMI shift every note, keep names/velocities; an out-of-range shift refuses.
    func testKitShift() {
        let notes: [UInt8] = [36, 37, 38, 39, 42, 44, 46, 49]
        XCTAssertEqual(euclideousKitShift(notes, by: 12), [48, 49, 50, 51, 54, 56, 58, 61])
        XCTAssertEqual(euclideousKitShift(notes, by: -1), [35, 36, 37, 38, 41, 43, 45, 48])
        XCTAssertNil(euclideousKitShift([0, 5, 10], by: -1), "a note leaving 0…127 refuses the whole shift")
        XCTAssertNil(euclideousKitShift([120, 125], by: 12))
        XCTAssertFalse(euclideousKitCanShift([0], by: -1)); XCTAssertTrue(euclideousKitCanShift([36], by: 12))
    }

    // §6.3 — ▼ copies the selected rank's note+name to ranks below; ▲ to ranks above; velocities untouched.
    func testKitCopy() {
        let notes: [UInt8] = [10, 20, 30, 40, 50, 60, 70, 80]
        let names = ["a", "b", "c", "d", "e", "f", "g", "h"]
        let below = euclideousKitCopy(notes: notes, names: names, from: 2, dir: .below)   // rank 3 (0-based 2) → ranks 1,2
        XCTAssertEqual(below.notes, [30, 30, 30, 40, 50, 60, 70, 80]); XCTAssertEqual(Array(below.names.prefix(3)), ["c", "c", "c"])
        let above = euclideousKitCopy(notes: notes, names: names, from: 6, dir: .above)   // rank 7 → rank 8
        XCTAssertEqual(above.notes, [10, 20, 30, 40, 50, 60, 70, 70]); XCTAssertEqual(above.names[7], "g")
        XCTAssertEqual(euclideousKitCopy(notes: notes, names: names, from: 0, dir: .below).notes, notes, "▼ on rank 1 changes nothing")
        XCTAssertEqual(euclideousKitCopy(notes: notes, names: names, from: 7, dir: .above).notes, notes, "▲ on rank 8 changes nothing")
    }

    // §6.6 — rank badges.
    func testRankBadge() {
        XCTAssertEqual(euclideousKitRankBadge([1, 2, 3, 4, 5, 6]), "1–6")
        XCTAssertEqual(euclideousKitRankBadge([7, 8]), "7·8")
        XCTAssertEqual(euclideousKitRankBadge([1, 3, 5]), "1·3·5")
        XCTAssertEqual(euclideousKitRankBadge([8, 7]), "7·8")   // order-independent
        XCTAssertEqual(euclideousKitRankBadge([3]), "3")
        XCTAssertEqual(euclideousKitRankBadge([]), "")
    }

    // §6.4 — TO KIT: notes = drumNote×8, names = drum GM name, vels = ramp.
    func testKitFromDrum() {
        var l = EuclidLine(noteSel: .all); l.laneMode = .drum; l.drumNote = 42; l.drumLow = 40; l.drumHigh = 100; l.drumRamp = .up
        let k = euclideousKitFromDrum(l, lane: 0)
        XCTAssertEqual(k.notes, Array(repeating: 42, count: 8))
        XCTAssertEqual(k.names, Array(repeating: "CH", count: 8))
        XCTAssertEqual(k.vel.map { Int($0) }, [40, 49, 57, 66, 74, 83, 91, 100])
    }

    // §6.5 — the range label shows the FIRST/LAST notes' names (36→C2, 59→B3), not the next C.
    func testRangeNames() {
        XCTAssertEqual(euclideousNoteViewName(36, flatKey: false), "C2")
        XCTAssertEqual(euclideousNoteViewName(59, flatKey: false), "B3")
        XCTAssertEqual(euclideousNoteViewName(0, flatKey: false), "C-1")
        XCTAssertEqual(euclideousNoteViewName(127, flatKey: false), "G9")
    }

    // §6.8 — the kit editor header frames fit without overlap and inside the card; the keyboard fills the height, at both references.
    func testEditorHeaderLayout() {
        for box in [CGSize(width: 769.33, height: 610), CGSize(width: 782, height: 611.33)] {
            let L = euclideousKitEditorLayout(box: box, lowC: 36)
            let hdr = [L.kitLabel, L.octWell, L.semiWell, L.drumBtn, L.resetBtn, L.closeBtn]
            for i in 0..<hdr.count { for j in (i + 1)..<hdr.count { XCTAssertFalse(hdr[i].intersects(hdr[j].insetBy(dx: 0.5, dy: 0.5)), "header \(i) overlaps \(j)") } }
            for r in hdr { XCTAssertTrue(L.card.insetBy(dx: -0.5, dy: -0.5).contains(r), "a header item is outside the card") }
            XCTAssertEqual(L.octMinus.width, 34); XCTAssertEqual(L.octPlus.width, 34)
            XCTAssertTrue(L.octWell.contains(L.octMinus) && L.octWell.contains(L.octPlus))
            XCTAssertEqual(L.rankTile.width, 44); XCTAssertEqual(L.copyDown.width, 44); XCTAssertEqual(L.copyUp.width, 44)
            // §2.7 the keyboard fills down to the card's bottom padding (no empty band)
            XCTAssertEqual(L.keyboard.maxY, L.card.maxY - 16, accuracy: 0.5)
            XCTAssertGreaterThan(L.keyboard.height, 120)
            // picker: no ranks/NAME, keyboard starts higher and fills
            let P = euclideousKitEditorLayout(box: box, lowC: 36, showsRanksAndName: false)
            XCTAssertTrue(P.ranks.isEmpty); XCTAssertEqual(P.keyboard.maxY, P.card.maxY - 16, accuracy: 0.5)
            XCTAssertGreaterThan(P.keyboard.minY, L.card.minY)
        }
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
