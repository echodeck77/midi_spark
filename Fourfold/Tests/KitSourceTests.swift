//  KitSourceTests.swift — KIT SOURCE ferry (2026-11-23): the model (§1) + the pure functions (§1.5/§3.1/§4.9) + saving +
//  APPLY TO ALL (§1.8). The engine's pool/velocity behaviour (§2/§3) is in KitSourceRouterTests; the golden harness proves
//  that with no KIT lane the output is byte-identical.

import XCTest

final class KitSourceTests: XCTestCase {

    // §1.2 defaults
    func testDefaults() {
        let l = EuclidLine(noteSel: .all)
        XCTAssertNil(l.kitOn); XCTAssertFalse(l.kitOnResolved)
        XCTAssertEqual(l.kitNotesResolved, [36, 37, 38, 39, 42, 44, 46, 49])   // §1.3
        XCTAssertEqual(l.kitVelResolved, Array(repeating: 100, count: 8))
        XCTAssertEqual(l.kitNamesResolved, ["KICK", "RIM", "SNR", "CLAP", "CH", "PH", "OH", "CRASH"])
    }

    // §1.2 clamp/pad
    func testClampAndPad() {
        XCTAssertEqual(euclideousKitNotesClamped([200, 36]), [127, 36, 38, 39, 42, 44, 46, 49])   // clamp 127, pad with the default kit
        XCTAssertEqual(euclideousKitVelClamped([50, 200]), [50, 100, 100, 100, 100, 100, 100, 100]) // clamp 100, pad 100
        XCTAssertEqual(euclideousKitNotesClamped(nil), [36, 37, 38, 39, 42, 44, 46, 49])
        XCTAssertEqual(euclideousKitVelClamped([]), Array(repeating: 100, count: 8))
    }

    // §1.5 GM names
    func testGMNames() {
        XCTAssertEqual(euclideousGMDrumName(36), "KICK")
        XCTAssertEqual(euclideousGMDrumName(42), "CH")
        XCTAssertEqual(euclideousGMDrumName(49), "CRASH")
        XCTAssertEqual(euclideousGMDrumName(35), "KICK 2")
        XCTAssertEqual(euclideousGMDrumName(81), "O TRI")
        XCTAssertEqual(euclideousGMDrumName(34), euclideousNoteViewName(34, flatKey: false))   // outside 35…81 → note name
        XCTAssertEqual(euclideousGMDrumName(90), euclideousNoteViewName(90, flatKey: false))
    }

    // §1.1/§4.4 name clean
    func testNameClean() {
        XCTAssertEqual(euclideousKitNameClean("snare", note: 38), "SNARE")
        XCTAssertEqual(euclideousKitNameClean("kickdrum", note: 36), "KICKDR")   // ≤ 6 chars
        XCTAssertEqual(euclideousKitNameClean("", note: 38), "SNR")             // empty ⇒ GM name
        XCTAssertEqual(euclideousKitNameClean("   ", note: 38), "   ".uppercased())  // whitespace is kept (only a truly empty string restores GM)
    }

    // §3.1 velocity scale
    func testScaledVelocity() {
        XCTAssertEqual(euclideousKitScaledVelocity(base: 100, kitVel: 100), 100)
        XCTAssertEqual(euclideousKitScaledVelocity(base: 100, kitVel: 50), 50)
        XCTAssertEqual(euclideousKitScaledVelocity(base: 90, kitVel: 50), 45)
        XCTAssertEqual(euclideousKitScaledVelocity(base: 127, kitVel: 100), 127)
        XCTAssertEqual(euclideousKitScaledVelocity(base: 100, kitVel: 33), 33)
        XCTAssertNil(euclideousKitScaledVelocity(base: 100, kitVel: 0))          // §3.2 no note
        XCTAssertEqual(euclideousKitScaledVelocity(base: 1, kitVel: 1), 1)       // clamp min 1 (round(0.01)=0 → 1)
    }

    // §4.9 editor opening range (low C)
    func testEditorRange() {
        XCTAssertEqual(euclideousKitEditorRangeLowC(note: 36), 36)   // KICK → C2 … B3
        XCTAssertEqual(euclideousKitEditorRangeLowC(note: 60), 60)
        XCTAssertEqual(euclideousKitEditorRangeLowC(note: 0), 0)
        XCTAssertEqual(euclideousKitEditorRangeLowC(note: 127), 108) // c=120 > 108 ⇒ second octave, low C 108
        XCTAssertEqual(euclideousKitEditorRangeLowC(note: 119), 108) // c=108
    }

    // §1.1 saving (custom decoder must read each kit field)
    func testCodableRoundTrip() throws {
        var l = EuclidLine(noteSel: .all)
        l.kitOn = true; l.kitNotes = [36, 38, 42, 46, 49, 51, 37, 39]; l.kitNames = ["BD", "SD", "HH", "OH", "CR", "RD", "RM", "CP"]; l.kitVel = [100, 90, 60, 70, 80, 75, 50, 85]
        var p = PluginState(machines: [Machine(machineID: "g", type: .euclid)], scenes: [SceneState.empty()])
        p.euclideousLines = [l, EuclidLine(enabled: false), EuclidLine(enabled: false), EuclidLine(enabled: false)]
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(p))
        let b = back.euclideousLinesResolved[0]
        XCTAssertEqual(b.kitOnResolved, true)
        XCTAssertEqual(b.kitNotesResolved, [36, 38, 42, 46, 49, 51, 37, 39])
        XCTAssertEqual(b.kitVelResolved, [100, 90, 60, 70, 80, 75, 50, 85])
        XCTAssertEqual(b.kitNamesResolved, ["BD", "SD", "HH", "OH", "CR", "RD", "RM", "CP"])
        // a line with no kit keys decodes to nil (off + default)
        let fresh = EuclidLine(noteSel: .all)
        let freshBack = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(fresh))
        XCTAssertNil(freshBack.kitOn)
    }

    // §1.8 APPLY TO ALL copies the four kit fields
    func testApplyToAll() {
        var lines = [EuclidLine(noteSel: .all), EuclidLine(noteSel: .all), EuclidLine(noteSel: .all), EuclidLine(noteSel: .all)]
        lines[0].kitOn = true; lines[0].kitNotes = [36, 36, 36, 36, 36, 36, 36, 36]; lines[0].kitVel = [10, 20, 30, 40, 50, 60, 70, 80]; lines[0].kitNames = ["A", "B", "C", "D", "E", "F", "G", "H"]
        euclideousApplyInputsToAll(&lines, from: 0)
        for i in 1..<4 {
            XCTAssertEqual(lines[i].kitOn, true)
            XCTAssertEqual(lines[i].kitNotes, lines[0].kitNotes)
            XCTAssertEqual(lines[i].kitVel, lines[0].kitVel)
            XCTAssertEqual(lines[i].kitNames, lines[0].kitNames)
        }
    }
}
