//  SceneFactoryTests.swift
//  Off-device sanity for the sixteen factory scenes (Docs/factory-scenes.md): they construct, are
//  v3, reference only occupied rows (no accidental warnings) — EXCEPT slot 15's INTENTIONAL cycle.

import XCTest

final class SceneFactoryTests: XCTestCase {

    func testSixteenScenes() {
        XCTAssertEqual(SceneFactory.scenes.count, 16)
    }

    func testAllLoadAsV3WithColoursAndCells() {
        for (i, s) in SceneFactory.scenes.enumerated() {
            let doc = s.make()
            XCTAssertEqual(doc.formatVersion, 3, "scene \(i + 1) \(s.name)")
            XCTAssertEqual(doc.colours.count, 16)
            XCTAssertEqual(doc.scenes.count, 1)
            let occupied = doc.scenes[0].cells.flatMap { $0 }.compactMap { $0 }
            XCTAssertFalse(occupied.isEmpty, "scene \(i + 1) has no cells")
        }
    }

    // A cell's inputRow must point at an occupied row in the same column (else it silently reroutes
    // to MIDI IN — a warning, not the intent). This catches typos in the scene grids.
    func testReferencesResolveToOccupiedRows() {
        for (i, s) in SceneFactory.scenes.enumerated() where s.name != "THE LOOP THAT ISN'T" {
            let cells = s.make().scenes[0].cells
            for col in 0..<8 {
                for row in 0..<8 {
                    guard let ir = cells[col][row]?.inputRow else { continue }
                    XCTAssert(ir >= 0 && ir < 8 && ir != row && cells[col][ir] != nil,
                              "scene \(i + 1) \(s.name): C\(col + 1)R\(row + 1) references empty/self row \(ir + 1)")
                }
            }
        }
    }

    // Slot 15 intentionally contains a two-cell cycle and a backward tap — the reference target IS
    // occupied, so it still resolves; the "dead loop" is a runtime silence, not a build warning.
    func testSlot15CycleIsPresentAndResolves() {
        let cells = SceneFactory.load(14).scenes[0].cells   // 0-based index 14 = slot 15
        // C6 (index 5): R3 (index 2) ⇐ R5 (index 4) and R5 ⇐ R3 — mutual references.
        XCTAssertEqual(cells[5][2]?.inputRow, 4)
        XCTAssertEqual(cells[5][4]?.inputRow, 2)
        // backward tap in C1: R1 (index 0) ⇐ R2 (index 1)
        XCTAssertEqual(cells[0][0]?.inputRow, 1)
    }

    func testPacificUsesHarmonizeAndAltStates() {
        let doc = SceneFactory.load(15)   // slot 16 PACIFIC
        func colour(_ id: String) -> Colour { doc.colours[colourIDs.firstIndex(of: id)!] }
        XCTAssertEqual(colour("mint").type, .harmonize)
        XCTAssertEqual(colour("gold").paramsB.rate, .r1_32)      // gold's designed B state
        XCTAssertEqual(colour("vermilion").paramsB.count, 4)
    }
}
