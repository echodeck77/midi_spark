//  ChordsGridTests.swift
//  CHORDS GRID ferry (2026-10-24): four progression tabs, borrowed chords, chord colours (7/9/6/ADD9/SUS2/SUS4),
//  a playhead + chord name, and a pool strip, on top of the single-grid `euclideousChords` model. This file
//  covers the spec's §10 numbered tests; see claude/ferry-chords-grid.md for the ratified text.

import XCTest

final class ChordsGridMigrationTests: XCTestCase {

    // MARK: - §10 test 1: migration (legacy euclideousChords → euclideousChordSets)

    func testLegacyDocumentResolvesSet0EqualToOldFieldAndRestDefault() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        var legacy = MachineParams()
        legacy.chordsDegrees = [0, 3, 4, 5]
        legacy.chordsSteps = 4
        p.euclideousChords = legacy

        XCTAssertNil(p.euclideousChordSets, "never touched -> no eager materialization")
        let sets = p.euclideousChordSetsResolved
        XCTAssertEqual(sets.count, 4)
        XCTAssertEqual(sets[0], legacy)
        XCTAssertEqual(sets[1], MachineParams())
        XCTAssertEqual(sets[2], MachineParams())
        XCTAssertEqual(sets[3], MachineParams())
        XCTAssertEqual(p.activeChordSetResolved, 0)
    }

    func testNeverTouchedDocumentDefaultsSet0ToTheOldFieldsDefault() {
        let p = PluginState(machines: [], scenes: [SceneState.empty()])
        XCTAssertEqual(p.euclideousChordSetsResolved[0], p.euclideousChordsResolved)
        XCTAssertEqual(p.euclideousChordSetsResolved[0], MachineParams())
    }

    func testSettingAChordSetMaterializesTheArrayWithoutDisturbingOthers() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        var legacy = MachineParams()
        legacy.chordsDegrees = [1, 2]
        p.euclideousChords = legacy

        var edited = MachineParams()
        edited.chordsDegrees = [6, 6, 6]
        p.setEuclideousChordSet(2, edited)

        XCTAssertNotNil(p.euclideousChordSets)
        let sets = p.euclideousChordSetsResolved
        XCTAssertEqual(sets[0], legacy, "set 0 still mirrors the pre-migration single grid")
        XCTAssertEqual(sets[1], MachineParams())
        XCTAssertEqual(sets[2], edited)
        XCTAssertEqual(sets[3], MachineParams())
    }

    func testActiveChordSetResolvedClampsToZeroThreeRange() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        p.activeChordSet = 7
        XCTAssertEqual(p.activeChordSetResolved, 3)
        p.activeChordSet = -2
        XCTAssertEqual(p.activeChordSetResolved, 0)
    }

    func testMigrationSoundsIdenticalThroughSnapshotBuilderResolve() {
        // Byte-identical notes at every step: a legacy document's resolve into SnapParams via the ACTIVE
        // chord set (set 0) must match what the OLD single-field resolve produced.
        var legacy = MachineParams()
        legacy.chordsDegrees = [0, 0, 5, 5, 3, 3, 4, 4]
        legacy.chordsSteps = 8
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        p.euclideousChords = legacy

        let viaOldField = p.euclideousChordsResolved
        let viaNewSets = p.euclideousChordSetsResolved[p.activeChordSetResolved]
        XCTAssertEqual(viaOldField, viaNewSets)
        for step in 0..<16 {
            let root = 0, scale = ScaleType.naturalMinor.intervals
            let a = chordSeqNotes(beat: Double(step) * viaOldField.chordsRateResolved.beats, snapParams(for: viaOldField), keyRoot: root, keyTones: scale, followNote: nil)
            let b = chordSeqNotes(beat: Double(step) * viaNewSets.chordsRateResolved.beats, snapParams(for: viaNewSets), keyRoot: root, keyTones: scale, followNote: nil)
            XCTAssertEqual(a, b, "step \(step)")
        }
    }

    private func snapParams(for cfg: MachineParams) -> SnapParams {
        var sp = SnapParams()
        let steps = cfg.chordsStepsResolved
        sp.chordsMode = .pattern
        sp.chordsDegrees = cfg.chordsDegreesResolved(steps: steps)
        sp.chordsColours = Array(cfg.chordsColoursResolved16().prefix(steps))
        sp.chordsSteps = steps
        sp.chordsRateBeats = max(0.03125, cfg.chordsRateResolved.beats)
        sp.chordsRotate = cfg.chordsRotate ?? 0
        sp.chordsVoicing = cfg.chordsVoicingResolved
        sp.chordsSpread = cfg.chordsSpreadResolved
        return sp
    }

    // MARK: - §10 test 2: padding (16-entry storage; shrink/grow preserves hidden columns)

    func testDecoded8EntryArrayPadsTo16WithCopiesOfEntry8() {
        var p = MachineParams()
        p.chordsDegrees = [0, 1, 2, 3, 4, 5, 6, 2]   // entry 8 (index 7) = 2
        let d = p.chordsDegreesResolved16()
        XCTAssertEqual(d.count, 16)
        XCTAssertEqual(Array(d[0..<8]), [0, 1, 2, 3, 4, 5, 6, 2])
        XCTAssertEqual(Array(d[8..<16]), [Int](repeating: 2, count: 8), "columns 9-16 copy column 8, not CARRY")
    }

    func testDecodedColoursArrayPadsWithCopiesOfLastEntryToo() {
        var p = MachineParams()
        p.chordsColours = [0, 0, 1, 1, 2]   // last = 2 (ninth)
        let c = p.chordsColoursResolved16()
        XCTAssertEqual(c.count, 16)
        XCTAssertEqual(Array(c[5..<16]), [Int](repeating: 2, count: 11))
    }

    func testNeverTouchedArraysPadWithCarryAndNoColourRespectively() {
        let p = MachineParams()
        XCTAssertEqual(p.chordsDegreesResolved16(), [0, 0, 5, 5, 3, 3, 4, 4] + [Int](repeating: 4, count: 8), "the default 8-entry progression's own last entry (4) repeats, same rule as a decoded array")
        var empty = MachineParams()
        empty.chordsColours = []
        XCTAssertEqual(empty.chordsColoursResolved16(), [Int](repeating: 0, count: 16))
    }

    func testShrinkingStepsThenGrowingRestoresHiddenColumnsUnchanged() {
        var p = MachineParams()
        p.chordsDegrees = p.chordsDegreesResolved16()   // materialize at 16, as the real editor always does
        var full = p.chordsDegreesResolved16()
        full[5] = 2; full[6] = 3; full[7] = 4           // columns 6,7,8 (0-indexed 5,6,7) carry distinct values
        p.chordsDegrees = full

        // "Shrinking STEPS to 5" never touches chordsDegrees at all -- only chordsSteps changes.
        p.chordsSteps = 5
        XCTAssertEqual(p.chordsDegreesResolved16(), full, "shrinking STEPS must not clear hidden columns")

        // "growing to 8" likewise only changes chordsSteps.
        p.chordsSteps = 8
        XCTAssertEqual(p.chordsDegreesResolved16(), full, "columns 6-8 restored exactly as they were")
        XCTAssertEqual(p.chordsDegreesResolved(steps: 8), Array(full.prefix(8)))
    }
}
