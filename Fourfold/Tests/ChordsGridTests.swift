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

final class ChordsGridChordToneTests: XCTestCase {

    private let cMinor = ScaleType.naturalMinor.intervals    // [0,2,3,5,7,8,10]
    private let cMajor = ScaleType.major.intervals           // [0,2,4,5,7,9,11]

    private func pcs(_ tones: [Int]) -> [Int] { tones.map { ((($0 % 12) + 12) % 12) } }

    // MARK: - §5.2/§3.2: which 4 borrowed rows, and §5.6's worked cases (spec test 3)

    func testScaleIsMinorPicksTheRightBorrowedTable() {
        XCTAssertTrue(euclideousScaleIsMinor(cMinor))
        XCTAssertFalse(euclideousScaleIsMinor(cMajor))
        XCTAssertTrue(euclideousScaleIsMinor(ScaleType.dorian.intervals), "a minor-flavoured mode reads minor")
        XCTAssertFalse(euclideousScaleIsMinor(ScaleType.mixolydian.intervals), "a major-flavoured mode reads major")
    }

    func testNonHeptatonicScalesFallBackToTheMajorBorrowedTableWithoutCrashing() {
        for t: ScaleType in [.majorPentatonic, .minorPentatonic, .blues, .wholeTone, .chromatic] {
            XCTAssertFalse(euclideousScaleIsMinor(t.intervals), "\(t) has no scale-stepped third -> major-table fallback")
            // the borrowed chords' own TONES are unaffected by this fallback -- still build cleanly.
            let tones = euclideousChordTones(degree: 8, colour: 0, scaleTones: t.intervals, rootNote: 48, minorKey: false, spread: .close)
            XCTAssertEqual(tones.count, 3)
        }
    }

    func testWorkedCasesKeyCMinor() {
        let root = 48   // C3 anchor, matching chordSeqNotes's own `rootNote: 48 + keyRoot`
        func tones(_ deg: Int, _ colour: Int) -> [Int] {
            euclideousChordTones(degree: deg, colour: colour, scaleTones: cMinor, rootNote: root, minorKey: true, spread: .close)
        }
        func name(_ deg: Int, _ colour: Int, forceFlat: Bool = false) -> String {
            let t = tones(deg, colour)
            let flat = forceFlat || euclideousKeyIsFlat(0, scaleType: .naturalMinor)
            return euclideousChordName(tones: t, rootNote: root + (deg >= 8 ? euclideousBorrowedTriad(row: deg - 8, minorKey: true)[0] : cMinor[deg % cMinor.count]), flatSpelling: flat)
        }

        // V (borrowed row 0), plain
        XCTAssertEqual(pcs(tones(8, 0)), [7, 11, 2])   // G B D (D wraps to pc2)
        XCTAssertEqual(name(8, 0), "G")
        // ♭II (borrowed row 2), plain
        XCTAssertEqual(pcs(tones(10, 0)), [1, 5, 8])   // D♭ F A♭
        XCTAssertEqual(name(10, 0, forceFlat: true), "D\u{266D}")
        // vii° (borrowed row 3), plain
        XCTAssertEqual(pcs(tones(11, 0)), [11, 2, 5])  // B D F
        XCTAssertEqual(name(11, 0), "B\u{00B0}")
        // i with 7 (diatonic degree 0)
        XCTAssertEqual(pcs(tones(0, 1)), [0, 3, 7, 10])   // C E♭ G B♭
        XCTAssertEqual(name(0, 1), "Cm7")
        // V with 7 (borrowed row 0)
        XCTAssertEqual(name(8, 1), "G7")
        // ii° with 7 (diatonic degree 1)
        XCTAssertEqual(pcs(tones(1, 1)), [2, 5, 8, 0])    // D F A♭ C
        XCTAssertEqual(name(1, 1), "Dm7\u{266D}5")
        // vii° with 7 (borrowed row 3) -- same pitch as the "6" colour -> names °7
        XCTAssertEqual(pcs(tones(11, 1)), [11, 2, 5, 8])  // B D F A♭
        XCTAssertEqual(name(11, 1), "B\u{00B0}7")
        // III with 6 (diatonic degree 2)
        XCTAssertEqual(pcs(tones(2, 3)), [3, 7, 10, 0])   // E♭ G B♭ C
        XCTAssertEqual(name(2, 3), "E\u{266D}6")
        // VI with ADD9 (diatonic degree 5)
        XCTAssertEqual(pcs(tones(5, 4)), [8, 0, 3, 10])   // A♭ C E♭ B♭
        XCTAssertEqual(name(5, 4), "A\u{266D}add9")
        // v with SUS4 (diatonic degree 4, lowercase -- the PLAIN diatonic v, not borrowed V)
        XCTAssertEqual(pcs(tones(4, 6)), [7, 0, 2])       // G C D
        XCTAssertEqual(name(4, 6), "Gsus4")
        // ii° with SUS2 (diatonic degree 1)
        XCTAssertEqual(pcs(tones(1, 5)), [2, 4, 9])       // D E A
        XCTAssertEqual(name(1, 5), "Dsus2")
        // i with 9 (diatonic degree 0)
        XCTAssertEqual(pcs(tones(0, 2)), [0, 3, 7, 10, 2]) // C E♭ G B♭ D
        XCTAssertEqual(name(0, 2), "Cm9")
    }

    func testWorkedCasesKeyCMajor() {
        let root = 48
        func tones(_ deg: Int, _ colour: Int) -> [Int] {
            euclideousChordTones(degree: deg, colour: colour, scaleTones: cMajor, rootNote: root, minorKey: false, spread: .close)
        }
        func rowRoot(_ row: Int) -> Int { root + euclideousBorrowedTriad(row: row, minorKey: false)[0] }
        func diatonicRoot(_ deg: Int) -> Int { root + cMajor[deg % cMajor.count] }

        // ♭VII (borrowed row 0) -- forces flat
        XCTAssertEqual(pcs(tones(8, 0)), [10, 2, 5])
        XCTAssertEqual(euclideousChordName(tones: tones(8, 0), rootNote: rowRoot(0), flatSpelling: euclideousBorrowedRowForcesFlat(row: 0, minorKey: false)), "B\u{266D}")
        // iv (borrowed row 1)
        XCTAssertEqual(pcs(tones(9, 0)), [5, 8, 0])
        XCTAssertEqual(euclideousChordName(tones: tones(9, 0), rootNote: rowRoot(1), flatSpelling: euclideousBorrowedRowForcesFlat(row: 1, minorKey: false)), "Fm")
        // ♭VI (borrowed row 2) -- forces flat
        XCTAssertEqual(euclideousChordName(tones: tones(10, 0), rootNote: rowRoot(2), flatSpelling: euclideousBorrowedRowForcesFlat(row: 2, minorKey: false)), "A\u{266D}")
        // II (borrowed row 3)
        XCTAssertEqual(euclideousChordName(tones: tones(11, 0), rootNote: rowRoot(3), flatSpelling: euclideousBorrowedRowForcesFlat(row: 3, minorKey: false)), "D")
        // I with 7 (diatonic degree 0)
        XCTAssertEqual(euclideousChordName(tones: tones(0, 1), rootNote: diatonicRoot(0), flatSpelling: false), "Cmaj7")
        // V with 9 (diatonic degree 4 -- major key's own diatonic V is already major quality)
        XCTAssertEqual(euclideousChordName(tones: tones(4, 2), rootNote: diatonicRoot(4), flatSpelling: false), "G9")
    }

    // MARK: - §10 test 7: chordSeqNotes/diatonicChord stay byte-identical for every pre-ferry caller

    func testChordSeqNotesByteIdenticalWhenNoColoursAndNoNewDegreeCodes() {
        var p = SnapParams()
        p.chordsMode = .pattern
        p.chordsDegrees = [0, 1, 2, 3, 4, 5, 6, 7]   // every diatonic degree + REST; no 8...11, no colours
        p.chordsColours = []                          // the default for every existing caller
        p.chordsSteps = 8
        p.chordsRateBeats = 4
        p.chordsVoicing = .seventh
        p.chordsSpread = .open

        for step in 0..<8 {
            let beat = Double(step) * p.chordsRateBeats
            let viaShared = chordSeqNotes(beat: beat, p, keyRoot: 0, keyTones: cMajor, followNote: nil)
            let (deg, rest) = chordsDegreeAt(step: step, degrees: p.chordsDegrees, rotate: 0)
            let expected = rest ? [] : diatonicChord(degree: deg, scaleTones: cMajor, rootNote: 48, voicing: .seventh, spread: .open).filter { $0 >= 0 && $0 <= 127 }
            XCTAssertEqual(viaShared, expected, "step \(step)")
        }
    }

    func testFollowAndWalkModesUntouchedByTheColourPath() {
        var p = SnapParams()
        p.chordsMode = .follow
        p.chordsColours = []
        let viaShared = chordSeqNotes(beat: 0, p, keyRoot: 0, keyTones: cMajor, followNote: 60)
        let deg = scaleDegreeOf(60, root: 0, scaleTones: cMajor)
        let expected = diatonicChord(degree: deg, scaleTones: cMajor, rootNote: 48, voicing: p.chordsVoicing, spread: p.chordsSpread)
        XCTAssertEqual(viaShared, expected)
    }
}
