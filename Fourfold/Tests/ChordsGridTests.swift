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
        XCTAssertEqual(sets.count, 2, "TWO CHORD GRIDS: the four progressions became two")
        XCTAssertEqual(sets[0], legacy)
        XCTAssertEqual(sets[1], MachineParams())
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
        p.setEuclideousChordSet(1, edited)
        p.setEuclideousChordSet(2, MachineParams()); p.setEuclideousChordSet(-1, MachineParams())   // out of range: ignored

        XCTAssertNotNil(p.euclideousChordSets)
        let sets = p.euclideousChordSetsResolved
        XCTAssertEqual(sets.count, 2)
        XCTAssertEqual(sets[0], legacy, "set 0 still mirrors the pre-migration single grid")
        XCTAssertEqual(sets[1], edited)
        XCTAssertEqual(p.euclideousChordSets?.count, 2, "a write beyond grid 2 does not grow the array")
    }

    func testActiveChordSetResolvedClampsToZeroOneRange() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        p.activeChordSet = 7
        XCTAssertEqual(p.activeChordSetResolved, 1)
        p.activeChordSet = -2
        XCTAssertEqual(p.activeChordSetResolved, 0)
    }

    // MARK: - TWO CHORD GRIDS (2026-11-03): an old document's four progressions become two, sound-preserving

    private func progression(_ tag: UInt8) -> MachineParams { var m = MachineParams(); m.chordsDegrees = [Int(tag), Int(tag), 0, 0]; m.chordsSteps = 4; return m }

    func testAFourSetDocumentMovesThePlayingProgressionIntoGridOneForEveryActiveIndex() {
        let four = (1...4).map { progression(UInt8($0)) }
        // grid 1 := the progression that was PLAYING (the old active); grid 2 := the lowest-numbered other one.
        let expected: [Int: [Int]] = [0: [0, 1], 1: [1, 0], 2: [2, 0], 3: [3, 0]]
        for (active, want) in expected {
            var p = PluginState(machines: [], scenes: [SceneState.empty()])
            p.euclideousChordSets = four; p.activeChordSet = active
            p.normalizeChordSetsAtLoad()
            XCTAssertEqual(p.euclideousChordSets, [four[want[0]], four[want[1]]], "active \(active)")
            XCTAssertNil(p.activeChordSet, "the edit tab opens on grid 1")
            XCTAssertEqual(p.euclideousChordSetsResolved[0], four[active], "what played before plays now (active \(active))")
        }
    }
    func testTheNormaliserIsIdempotentAndLeavesATwoSetDocumentAlone() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        p.euclideousChordSets = (1...4).map { progression(UInt8($0)) }; p.activeChordSet = 2
        p.normalizeChordSetsAtLoad()
        let once = p
        p.normalizeChordSetsAtLoad(); XCTAssertEqual(p.euclideousChordSets, once.euclideousChordSets); XCTAssertEqual(p.activeChordSet, once.activeChordSet)
        var q = PluginState(machines: [], scenes: [SceneState.empty()])
        q.euclideousChordSets = [progression(7), progression(8)]; q.activeChordSet = 1     // a NEW document's edit tab
        q.normalizeChordSetsAtLoad()
        XCTAssertEqual(q.euclideousChordSets, [progression(7), progression(8)]); XCTAssertEqual(q.activeChordSet, 1, "an edit tab is not an old 'plays' index")
    }
    func testANeverMaterialisedDocumentWithAnOldActiveIndexKeepsItsSound() {
        // The sets were never edited (nil) but the player had clicked tab 3: the default progression played, grid 2 is the default too.
        var p = PluginState(machines: [], scenes: [SceneState.empty()]); p.activeChordSet = 2
        p.normalizeChordSetsAtLoad()
        XCTAssertEqual(p.euclideousChordSetsResolved, [MachineParams(), MachineParams()]); XCTAssertNil(p.activeChordSet)
        // …and with a LEGACY single grid it was set 0 (the legacy grid) that tab 1 played; tab 2-4 were the defaults.
        var l = PluginState(machines: [], scenes: [SceneState.empty()]); l.euclideousChords = progression(5); l.activeChordSet = 0
        l.normalizeChordSetsAtLoad()
        XCTAssertNil(l.euclideousChordSets, "an untouched document stays untouched")
        XCTAssertEqual(l.euclideousChordSetsResolved[0], progression(5))
        var m = PluginState(machines: [], scenes: [SceneState.empty()]); m.euclideousChords = progression(5); m.activeChordSet = 1
        m.normalizeChordSetsAtLoad()
        XCTAssertEqual(m.euclideousChordSetsResolved, [MachineParams(), progression(5)], "tab 2 played a default; the legacy grid (old tab 1) becomes grid 2")
    }
    func testTheNormalisedDocumentDecodesAndRoundTripsAsTwoSets() throws {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        p.euclideousChordSets = (1...4).map { progression(UInt8($0)) }; p.activeChordSet = 3
        p.normalizeChordSetsAtLoad()
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.euclideousChordSets?.count, 2)
        XCTAssertEqual(back.euclideousChordSetsResolved[0], progression(4))
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

final class ChordsGridLayoutTests: XCTestCase {

    // Paul's own two reference screenshots (PageLayoutTests.swift) -- the popup's `size` parameter is the
    // page's geo.size, so these are the right numbers to test the popup's layout against too.
    private let landscapeRef = CGSize(width: 1190, height: 726)
    private let portraitRef = CGSize(width: 814, height: 1102)

    private func contentBox(_ pageSize: CGSize) -> CGSize {
        let maxW = min(640, pageSize.width - 32)
        let maxH = pageSize.height - 60
        return CGSize(width: maxW - 40, height: maxH - 40)   // the card's own 20pt padding, each side
    }

    // MARK: - §10 test 4: frames at n = 1, 8, 16; floor flags below §2.5/§2.6

    func testLandscapeAtEachStepsCountStaysAboveBothFloors() {
        let box = contentBox(landscapeRef)
        for n in [1, 8, 16] {
            let l = euclideousChordsPopupLayout(box: box, steps: n)
            XCTAssertFalse(l.belowRowFloor, "n=\(n) landscape rowH=\(l.rowH)")
            XCTAssertFalse(l.belowCellFloor, "n=\(n) landscape cellW=\(l.cellW)")
        }
    }

    func testPortraitAtEachStepsCountStaysAboveBothFloors() {
        let box = contentBox(portraitRef)
        for n in [1, 8, 16] {
            let l = euclideousChordsPopupLayout(box: box, steps: n)
            XCTAssertFalse(l.belowRowFloor, "n=\(n) portrait rowH=\(l.rowH)")
            XCTAssertFalse(l.belowCellFloor, "n=\(n) portrait cellW=\(l.cellW)")
        }
    }

    func testRowHIsTheSpec25Formula() {
        let box = contentBox(landscapeRef)
        let l = euclideousChordsPopupLayout(box: box, steps: 8)
        let expectedRowH = (l.gridH - (16 * 4 + 10)) / 18
        XCTAssertEqual(l.rowH, expectedRowH, accuracy: 1e-9)
    }

    func testCellWIsTheSpec26FormulaAndScalesWithSteps() {
        let box = contentBox(landscapeRef)
        for n in [1, 8, 16] {
            let l = euclideousChordsPopupLayout(box: box, steps: n)
            let expectedCellW = (box.width - EuclideousChordsPopupMetrics.labelW - 4 - CGFloat(n - 1) * 4) / CGFloat(n)
            XCTAssertEqual(l.cellW, expectedCellW, accuracy: 1e-9, "n=\(n)")
        }
    }

    func testStepsClampsToOneSixteenRangeInsideTheLayoutFunction() {
        let box = contentBox(landscapeRef)
        XCTAssertEqual(euclideousChordsPopupLayout(box: box, steps: 0).steps, 1)
        XCTAssertEqual(euclideousChordsPopupLayout(box: box, steps: 99).steps, 16)
    }

    // MARK: - Row/column frame geometry

    func testEighteenRowsFitExactlyWithinGridHIncludingTheWiderDividerGap() {
        let box = contentBox(landscapeRef)
        let l = euclideousChordsPopupLayout(box: box, steps: 8)
        // rowTop() is absolute from the CARD's top (matches EuclideousRiffPanelLayout's own precedent), so
        // the last row's bottom lands at gridTop + gridH, not bare gridH.
        let lastRowBottom = l.rowTop(17) + l.rowH
        XCTAssertEqual(lastRowBottom, l.gridTop + l.gridH, accuracy: 1e-9)
    }

    func testDividerSitsBetweenRowElevenAndRowTwelveWithTheWiderGap() {
        let box = contentBox(landscapeRef)
        let l = euclideousChordsPopupLayout(box: box, steps: 8)
        let gapBefore12 = l.rowTop(12) - (l.rowTop(11) + l.rowH)
        XCTAssertEqual(gapBefore12, EuclideousChordsPopupMetrics.dividerGap, accuracy: 1e-9)
        let gapBefore11 = l.rowTop(11) - (l.rowTop(10) + l.rowH)
        XCTAssertEqual(gapBefore11, EuclideousChordsPopupMetrics.rowGap, accuracy: 1e-9, "every OTHER gap is the normal 4pt")
        XCTAssertGreaterThan(l.dividerY, l.rowTop(11) + l.rowH)
        XCTAssertLessThan(l.dividerY, l.rowTop(12))
    }

    func testColumnsFillExactlyToTheGridsRightEdge() {
        let box = contentBox(landscapeRef)
        for n in [1, 8, 16] {
            let l = euclideousChordsPopupLayout(box: box, steps: n)
            let lastColumnRight = l.columnLeft(n - 1) + l.cellW
            XCTAssertEqual(lastColumnRight, l.gridWidth, accuracy: 1e-9, "n=\(n)")
        }
    }
}

final class ChordsGridRowMappingTests: XCTestCase {

    func testRowDegreeRoundTripsForAllTwelveChordRows() {
        for row in 0...11 {
            guard let deg = euclideousChordsRowDegree(row) else { return XCTFail("row \(row)") }
            XCTAssertEqual(euclideousChordsDegreeRow(deg), row, "row \(row) degree \(deg)")
        }
    }

    func testColourRowsHaveNoDegree() {
        for row in 12...17 { XCTAssertNil(euclideousChordsRowDegree(row)) }
    }

    func testTabIconRestRowDiffersFromGridRestRow() {
        XCTAssertEqual(euclideousChordsDegreeRow(7), 11, "the grid itself draws REST as row 11")
        XCTAssertNil(euclideousChordsTabIconRow(7), "but the tab icon draws nothing for REST (§4.3)")
    }

    func testCarryNeverMapsToARow() {
        XCTAssertNil(euclideousChordsDegreeRow(-1))
        XCTAssertNil(euclideousChordsTabIconRow(-1))
    }

    func testRowLabelsMatchTheMinorAndMajorKeyTables() {
        let cMinor = ScaleType.naturalMinor.intervals
        XCTAssertEqual(euclideousChordsRowLabel(row: 7, scaleTones: cMinor, minorKey: true), "V")
        XCTAssertEqual(euclideousChordsRowLabel(row: 10, scaleTones: cMinor, minorKey: true), "vii\u{00B0}")
        XCTAssertEqual(euclideousChordsRowLabel(row: 11, scaleTones: cMinor, minorKey: true), "REST")
        XCTAssertEqual(euclideousChordsRowLabel(row: 15, scaleTones: cMinor, minorKey: true), "ADD9")
        let cMajor = ScaleType.major.intervals
        XCTAssertEqual(euclideousChordsRowLabel(row: 7, scaleTones: cMajor, minorKey: false), "\u{266D}VII")
        XCTAssertEqual(euclideousChordsRowLabel(row: 0, scaleTones: cMajor, minorKey: false), "I", "diatonic rows still use degreeLabel")
    }
}

// MARK: - CHORDS PAGE ferry (Paul 2026-11-04) §10: the ADVANCE / RESTART model
// The engine `chordColumn` function (§3) is gated on the RESTART UNITS schedule and lands later; these cover the
// model fields only — the slice that is buildable while the schedule is in flight (inert, byte-identical).

final class ChordsAdvanceModelTests: XCTestCase {

    // §2.1: nil resolves to TIME advance, restart off — the pre-ferry progression.
    func testNilResolvesToTimeAdvanceRestartOff() {
        let p = MachineParams()
        XCTAssertNil(p.advanceUnit); XCTAssertNil(p.restartUnit); XCTAssertNil(p.restartOn)
        XCTAssertEqual(p.advanceUnitResolved, .time)
        XCTAssertEqual(p.advanceLaneResolved, 0)       // nil ⇒ lane 1 (index 0)
        XCTAssertEqual(p.advanceEveryResolved, 1)
        XCTAssertEqual(p.restartOnResolved, false)
        XCTAssertEqual(p.restartUnitResolved, .bar)
        XCTAssertEqual(p.restartLaneResolved, 0)
        XCTAssertEqual(p.restartEveryResolved, 4)
    }

    // §2.3: an out-of-set numeric value resolves to the default; an in-set one survives.
    func testOutOfSetNumericValuesResolveToDefault() {
        var p = MachineParams()
        p.advanceLane = 7; p.restartLane = -2; p.advanceEvery = 5; p.restartEvery = 7   // 5 / 7 are not in the legal sets
        XCTAssertEqual(p.advanceLaneResolved, 0)
        XCTAssertEqual(p.restartLaneResolved, 0)
        XCTAssertEqual(p.advanceEveryResolved, 1)
        XCTAssertEqual(p.restartEveryResolved, 4)
        p.advanceLane = 3; p.advanceEvery = 8; p.restartLane = 1; p.restartEvery = 16
        XCTAssertEqual(p.advanceLaneResolved, 3)
        XCTAssertEqual(p.advanceEveryResolved, 8)
        XCTAssertEqual(p.restartLaneResolved, 1)
        XCTAssertEqual(p.restartEveryResolved, 16)
        // the two "every" sets genuinely differ (12/16 are restart-only)
        XCTAssertEqual(chordsAdvanceEveryValues, [1, 2, 3, 4, 6, 8])
        XCTAssertEqual(chordsRestartEveryValues, [1, 2, 3, 4, 6, 8, 12, 16])
    }

    // §2.3: an unknown enum raw value decodes to the default (lenient decoder), never throws.
    func testUnknownEnumRawDecodesToDefault() throws {
        let bogus = #""BOGUS""#.data(using: .utf8)!
        XCTAssertEqual(try JSONDecoder().decode(ChordsAdvanceUnit.self, from: bogus), .time)
        XCTAssertEqual(try JSONDecoder().decode(ChordsRestartUnit.self, from: bogus), .bar)
        XCTAssertEqual(try JSONDecoder().decode(ChordsAdvanceUnit.self, from: #""RIFF""#.data(using: .utf8)!), .riff)
        XCTAssertEqual(try JSONDecoder().decode(ChordsRestartUnit.self, from: #""LOOP""#.data(using: .utf8)!), .loop)
    }

    // §2.6: round-trip preserves in-set values; a never-touched grid omits every new key (byte-identity §2.4).
    func testRoundTripPreservesValuesAndOmitsNil() throws {
        var p = MachineParams()
        p.advanceUnit = .riff; p.advanceLane = 2; p.advanceEvery = 6
        p.restartOn = true; p.restartUnit = .loop; p.restartLane = 1; p.restartEvery = 12
        let back = try JSONDecoder().decode(MachineParams.self, from: JSONEncoder().encode(p))
        XCTAssertEqual(back.advanceUnit, .riff); XCTAssertEqual(back.advanceLane, 2); XCTAssertEqual(back.advanceEvery, 6)
        XCTAssertEqual(back.restartOn, true); XCTAssertEqual(back.restartUnit, .loop); XCTAssertEqual(back.restartLane, 1); XCTAssertEqual(back.restartEvery, 12)
        let s = String(data: try JSONEncoder().encode(MachineParams()), encoding: .utf8)!
        for k in ["advanceUnit", "advanceLane", "advanceEvery", "restartOn", "restartUnit", "restartLane", "restartEvery"] {
            XCTAssertFalse(s.contains("\"\(k)\""), "a default MachineParams must not encode \(k) (nil omitted → §2.4)")
        }
    }

    // §2.6: the fields reach the snapshot for BOTH grids (the SnapshotBuilder fresh-literal guard — fails if a
    // field is forgotten in the grid-1 assignments or the grid-2 ChordGridSnap literal).
    func testSnapshotCarriesAdvanceRestartForBothGrids() {
        var g1 = MachineParams(); g1.advanceUnit = .riff; g1.advanceLane = 2; g1.advanceEvery = 6
        g1.restartOn = true; g1.restartUnit = .loop; g1.restartLane = 1; g1.restartEvery = 12
        var g2 = MachineParams(); g2.advanceUnit = .loop; g2.advanceLane = 3; g2.advanceEvery = 3
        g2.restartOn = true; g2.restartUnit = .riff; g2.restartLane = 2; g2.restartEvery = 16

        var gold = Machine(machineID: "gold", type: .euclid)
        gold.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8)]
        var sc = SceneState.empty()
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: [gold], scenes: [sc])
        st.euclideousChordSets = [g1, g2]

        let p = SnapshotBuilder.build(from: st).cells[0 * Snap.rows + Snap.euclideousRow].procs[0]
        XCTAssertEqual(p.chordsAdvanceUnit, .riff); XCTAssertEqual(p.chordsAdvanceLane, 2); XCTAssertEqual(p.chordsAdvanceEvery, 6)
        XCTAssertEqual(p.chordsRestartOn, true); XCTAssertEqual(p.chordsRestartUnit, .loop)
        XCTAssertEqual(p.chordsRestartLane, 1); XCTAssertEqual(p.chordsRestartEvery, 12)
        XCTAssertEqual(p.chords2.advanceUnit, .loop); XCTAssertEqual(p.chords2.advanceLane, 3); XCTAssertEqual(p.chords2.advanceEvery, 3)
        XCTAssertEqual(p.chords2.restartOn, true); XCTAssertEqual(p.chords2.restartUnit, .riff)
        XCTAssertEqual(p.chords2.restartLane, 2); XCTAssertEqual(p.chords2.restartEvery, 16)
    }

    // A default document's snapshot is the pre-ferry progression on both grids (inert → golden byte-identical).
    func testDefaultSnapshotIsTimeAdvanceRestartOff() {
        var gold = Machine(machineID: "gold", type: .euclid)
        gold.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8)]
        var sc = SceneState.empty()
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        let st = PluginState(machines: [gold], scenes: [sc])
        let p = SnapshotBuilder.build(from: st).cells[0 * Snap.rows + Snap.euclideousRow].procs[0]
        XCTAssertEqual(p.chordsAdvanceUnit, .time); XCTAssertFalse(p.chordsRestartOn)
        XCTAssertEqual(p.chords2.advanceUnit, .time); XCTAssertFalse(p.chords2.restartOn)
    }

    // §2.7 / undo: the fields ride a whole-MachineParams copy (Equatable notices a change so undo/resync record it).
    func testEquatableNoticesAdvanceRestartChange() {
        var a = MachineParams(); let b = a
        a.advanceEvery = 4
        XCTAssertNotEqual(a, b)
        a.advanceEvery = nil
        XCTAssertEqual(a, b)
        a.restartOn = true
        XCTAssertNotEqual(a, b)
    }
}

// MARK: - CHORDS PAGE ferry (Paul 2026-11-04) §3: the schedule-free column arithmetic
// Tests 1 (byte-identity under TIME + restart off) and 6 (RESTART BAR). The LOOP / RIFF branches and the full
// `chordColumn` land with the RESTART UNITS schedule.

final class ChordColumnArithmeticTests: XCTestCase {

    /// Today's resolved column: the raw step floored, then the engine's `chordsDegreeAt` mod+rotate.
    private func todaysColumn(beat: Double, rate: Double, steps: Int, rotate: Int) -> Int {
        chordsColumnResolve(count: euclideousChordsPlayingColumn(beat: beat, rateBeats: rate), steps: steps, rotate: rotate)
    }

    // §8 test 1 (the pure half): under TIME with restart off, the new `floor((beat+ε)/rate)` column equals today's
    // `floor(beat/rate)` column at every 1/16 over 32 bars — the ε moves no boundary. (The factory-preset MIDI
    // byte-identity is the golden harness; this is the column formula itself.)
    func testTimeColumnIsByteIdenticalToTodayAtEverySixteenthOver32Bars() {
        let beatsTotal = 32.0 * 4.0                                   // 32 bars at 4 beats/bar
        for rate in StepRate.allCases.map({ $0.beats }) {
            for steps in [1, 3, 6, 8, 16] {
                for rotate in [0, 1, 3, 7] {
                    var beat = 0.0
                    while beat <= beatsTotal + 1e-9 {
                        let now = chordsColumnResolve(count: chordsTimeAdvanceCount(beat: beat, rateBeats: rate, restartBeat: 0),
                                                      steps: steps, rotate: rotate)
                        XCTAssertEqual(now, todaysColumn(beat: beat, rate: rate, steps: steps, rotate: rotate),
                                       "rate=\(rate) steps=\(steps) rotate=\(rotate) beat=\(beat)")
                        beat += 0.25
                    }
                }
            }
        }
    }

    // §8 test 6: TIME 1/1 (rate 4 = one chord per bar), STEPS 6, RESTART BAR every 4 ⇒ columns 1 2 3 4 | 1 2 3 4
    // (0-indexed 0 1 2 3 | 0 1 2 3): it reaches column 4, then the 4-bar restart sends it back to column 1.
    func testRestartBarEveryFourOnASixStepGrid() {
        let rate = 4.0, steps = 6, rotate = 0, every = 4, barBeats = 4.0
        func col(_ beat: Double) -> Int {
            let r = chordsBarRestartBeat(beat: beat, restartOn: true, restartEvery: every, barBeats: barBeats)
            return chordsColumnResolve(count: chordsTimeAdvanceCount(beat: beat, rateBeats: rate, restartBeat: r), steps: steps, rotate: rotate)
        }
        let atBar = (0..<8).map { col(Double($0) * barBeats) }        // the column at each bar line
        XCTAssertEqual(atBar, [0, 1, 2, 3, 0, 1, 2, 3])
        // restart off: the grid keeps counting past column 4 and wraps at STEPS (6), never at 4
        func colFree(_ beat: Double) -> Int {
            let r = chordsBarRestartBeat(beat: beat, restartOn: false, restartEvery: every, barBeats: barBeats)
            return chordsColumnResolve(count: chordsTimeAdvanceCount(beat: beat, rateBeats: rate, restartBeat: r), steps: steps, rotate: rotate)
        }
        XCTAssertEqual((0..<8).map { colFree(Double($0) * barBeats) }, [0, 1, 2, 3, 4, 5, 0, 1])
    }

    // §3.4: the wrap applies (a mod STEPS) then ROTATE, matching the engine; negative wrap is handled.
    func testColumnResolveWrapAndRotate() {
        XCTAssertEqual(chordsColumnResolve(count: 10, steps: 8, rotate: 0), 2)
        XCTAssertEqual(chordsColumnResolve(count: 10, steps: 8, rotate: 3), 5)
        XCTAssertEqual(chordsColumnResolve(count: 7, steps: 8, rotate: 3), 2)   // (7+3)%8
        XCTAssertEqual(chordsColumnResolve(count: 0, steps: 6, rotate: -1), 5)  // negative rotate wraps up
        XCTAssertEqual(chordsColumnResolve(count: 5, steps: 1, rotate: 0), 0)   // 1-step grid is always column 0
    }

    // §3.5: a restart at a beat wins — the column there is the first (0 + rotate), and the advance event isn't counted.
    func testRestartBeatIsTheFirstColumn() {
        let rate = 4.0, steps = 8, every = 2, barBeats = 4.0        // restart every 2 bars = every 8 beats
        for restartBeat in [0.0, 8.0, 16.0, 24.0] {
            let r = chordsBarRestartBeat(beat: restartBeat, restartOn: true, restartEvery: every, barBeats: barBeats)
            XCTAssertEqual(r, restartBeat, "the restart lands exactly on the bar line")
            XCTAssertEqual(chordsTimeAdvanceCount(beat: restartBeat, rateBeats: rate, restartBeat: r), 0, "count resets to 0 at the restart")
            XCTAssertEqual(chordsColumnResolve(count: 0, steps: steps, rotate: 2), 2, "the first column is rotate")
        }
    }
}

// MARK: - CHORDS PAGE ferry (Paul 2026-11-04) §3 + §3.6: the schedule-backed column (LOOP / RIFF / RESTART)
// Covers the new schedule accessors (cross-checked against the trusted readers) and the ferry's §8 worked
// examples for LOOP (tests 2,3), RIFF (4), same-beat (7), two grids (8) and transport-start invariance (12).

final class ChordColumnScheduleTests: XCTestCase {

    private func mkLine(hits: Int, steps: Int, rate: ArpRate = .r1_8, dir: EuclidDir = .fwd) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: hits, steps: steps)
        l.rate = rate; l.direction = dir; l.useRiff = true; l.riffOn = true
        l.restartRhythmBars = []; l.restartMelodyPasses = []     // FREE / FREE unless a test sets them
        return l
    }
    private func setOf(_ l0: EuclidLine, bar: Double = 4) -> EuclideousRestartScheduleSet {
        let lines = [l0, mkLine(hits: 1, steps: 8), mkLine(hits: 1, steps: 8), mkLine(hits: 1, steps: 8)]
        return euclideousBuildRestartScheduleSet(euclideousScheduleInputs(lines: lines, barBeats: bar, defaultRateBeats: 0.25, riffColumns: 8),
                                                 engagedMask: 0, maxBars: 1024, detectPeriod: true)
    }
    private func cfg(steps: Int = 8, rotate: Int = 0, rate: Double = 4,
                     adv: ChordsAdvanceUnit = .time, advLane: Int = 0, advEvery: Int = 1,
                     restartOn: Bool = false, rUnit: ChordsRestartUnit = .bar, rLane: Int = 0, rEvery: Int = 4) -> ChordsAdvanceConfig {
        ChordsAdvanceConfig(rateBeats: rate, steps: steps, rotate: rotate, advanceUnit: adv, advanceLane: advLane, advanceEvery: advEvery,
                            restartOn: restartOn, restartUnit: rUnit, restartLane: rLane, restartEvery: rEvery)
    }
    private func cols(_ c: ChordsAdvanceConfig, _ set: EuclideousRestartScheduleSet?, _ beats: [Double], bar: Double = 4) -> [Int] {
        beats.map { chordColumn(c, beat: $0, schedule: set, barBeats: bar) }
    }

    // §3.6: the new rhythm-restart accessors match a brute-force walk of `nextRhythmRestart` (beat 0 included).
    func testRhythmRestartAccessorsMatchABruteForceWalk() {
        var l = mkLine(hits: 3, steps: 7); l.restartRhythmBars = [1]; l.restartRhythmUnit = .bar    // restart every bar (4 beats)
        let s = setOf(l).lane(0)!
        var beats: [Double] = [0]; var b = 0.0
        while let n = s.nextRhythmRestart(after: b), n < 200 { beats.append(n); b = n }
        XCTAssertGreaterThan(beats.count, 10)
        for x in stride(from: 0.0, through: 80, by: 0.5) {
            let bf = Int64(beats.filter { $0 <= x + 1e-9 }.count)
            XCTAssertEqual(s.rhythmRestartCount(atOrBefore: x), bf, "count @\(x)")
        }
        for k in 0..<min(beats.count, 40) {
            XCTAssertEqual(s.rhythmRestartBeat(Int64(k)), beats[k], accuracy: 1e-9, "restart #\(k)")
        }
    }

    // §3.6: riffCompletionBeat(k) is exactly where riffCompletions crosses from k to k+1.
    func testRiffCompletionBeatAgreesWithTheCompletionCount() {
        var l = mkLine(hits: 3, steps: 8); l.restartRhythmBars = [1]; l.restartRhythmUnit = .riff; l.restartRhythmSource = 0
        let s = setOf(l).lane(0)!
        for k in 0..<20 {
            let beat = s.riffCompletionBeat(Int64(k))
            XCTAssertEqual(s.riffCompletionCount(atOrBefore: beat), Int64(k + 1), "completion #\(k) counted at its own beat \(beat)")
            XCTAssertEqual(s.riffCompletionCount(atOrBefore: beat - 1e-6), Int64(k), "and not just before it")
        }
    }

    // §8 test 2 — LOOP, rhythm FREE: an 8-step lane passes every 4 beats; ADVANCE LOOP every 1 changes at 4,8,12…
    func testLoopAdvanceRhythmFreeEveryOneAndTwo() {
        let s = setOf(mkLine(hits: 3, steps: 8))        // lap = 8 × 0.5 = 4 beats, FREE
        let e1 = cfg(adv: .loop, advEvery: 1)
        XCTAssertEqual(cols(e1, s, [0, 2, 3.9, 4, 6, 7.9, 8, 12]), [0, 0, 0, 1, 1, 1, 2, 3])
        let e2 = cfg(adv: .loop, advEvery: 2)            // every 2 loops → changes at 8, 16
        XCTAssertEqual(cols(e2, s, [0, 4, 7.9, 8, 12, 15.9, 16]), [0, 0, 0, 1, 1, 1, 2])
    }

    // §8 test 3 — LOOP follows the rhythm restart: a 7-step lane with RHYTHM BAR [1] advances on the bar line
    // (4,8,12), never on its raw 3.5-beat pass.
    func testLoopAdvanceFollowsRhythmRestartNotTheRawPass() {
        var l = mkLine(hits: 3, steps: 7); l.restartRhythmBars = [1]; l.restartRhythmUnit = .bar
        let s = setOf(l)
        XCTAssertEqual(cols(cfg(adv: .loop), s, [0, 3.4, 3.5, 3.9, 4, 7, 7.5, 7.9, 8, 12]),
                       [0, 0, 0, 0, 1, 1, 1, 1, 2, 3])
    }

    // §8 test 4 — RIFF, riff-first: E(3,8) with RHYTHM RIFF [1] of itself; ADVANCE RIFF changes on each riff
    // completion. The exact completion cadence is the schedule's; the chord must change ONCE per completion and
    // never between completions.
    func testRiffAdvanceChangesOncePerCompletion() {
        var l = mkLine(hits: 3, steps: 8); l.restartRhythmBars = [1]; l.restartRhythmUnit = .riff; l.restartRhythmSource = 0
        let s = setOf(l).lane(0)!
        let set = setOf(l)
        let c = cfg(adv: .riff)
        // at each completion beat the column equals that completion's index (mod steps); it holds between completions
        for k in 0..<12 {
            let beat = s.riffCompletionBeat(Int64(k))
            XCTAssertEqual(chordColumn(c, beat: beat, schedule: set, barBeats: 4), (k + 1) % 8, "column at completion #\(k)")
            XCTAssertEqual(chordColumn(c, beat: beat - 1e-6, schedule: set, barBeats: 4), k % 8, "column just before completion #\(k)")
        }
    }

    // §8 test 7 — same beat: ADVANCE LOOP every 1 + RESTART LOOP every 2 on an 8-step lane → columns 0 1 | 0 1
    // (the restart on loops 2,4,… wins and is not counted).
    func testLoopAdvanceWithLoopRestartSameBeat() {
        let s = setOf(mkLine(hits: 3, steps: 8))        // loops at 4,8,12,16,…
        let c = cfg(adv: .loop, advEvery: 1, restartOn: true, rUnit: .loop, rLane: 0, rEvery: 2)
        XCTAssertEqual(cols(c, s, [0, 4, 8, 12, 16, 20]), [0, 1, 0, 1, 0, 1])
    }

    // §8 test 8 — two grids at once: grid 1 TIME 1/1 and grid 2 RIFF lane 1 switch at their own, independent beats.
    func testTwoGridsAdvanceIndependently() {
        var l = mkLine(hits: 3, steps: 8); l.restartRhythmBars = [1]; l.restartRhythmUnit = .riff; l.restartRhythmSource = 0
        let set = setOf(l)
        let g1 = cfg(rate: 4, adv: .time)                // one chord per bar
        let g2 = cfg(adv: .riff, advLane: 0)
        XCTAssertEqual(cols(g1, set, [0, 3.9, 4, 8]), [0, 0, 1, 2])   // grid 1 moves every 4 beats
        let s = set.lane(0)!
        let firstCompletion = s.riffCompletionBeat(0)
        XCTAssertNotEqual(firstCompletion, 4, accuracy: 1e-9)          // grid 2's cadence is NOT grid 1's
        XCTAssertEqual(chordColumn(g2, beat: firstCompletion, schedule: set, barBeats: 4), 1)
    }

    // §8 test 12 — transport start at a high beat: the column is a pure function of the absolute beat (no
    // transport-relative state), so sampling from beat 1000 matches the low-beat pattern at the same absolute beats.
    func testColumnIsAPureFunctionOfAbsoluteBeat() {
        let s = setOf(mkLine(hits: 3, steps: 8))
        for c in [cfg(adv: .loop), cfg(rate: 4, adv: .time), cfg(adv: .loop, restartOn: true, rUnit: .loop, rEvery: 2)] {
            for delta in stride(from: 0.0, through: 16, by: 0.5) {
                XCTAssertEqual(chordColumn(c, beat: delta, schedule: s, barBeats: 4),
                               chordColumn(c, beat: delta, schedule: s, barBeats: 4))   // deterministic (idempotent)
            }
        }
        // periodic sanity: a TIME grid's column repeats with its STEPS·rate period at a far-off beat
        let t = cfg(steps: 8, rate: 4, adv: .time)
        XCTAssertEqual(chordColumn(t, beat: 1000.0, schedule: s, barBeats: 4), Int((1000.0 / 4).rounded(.down)) % 8)
    }
}

// MARK: - CHORDS PAGE ferry §3 (wiring): the Router actually emits the ADVANCING chord
// The pure `chordColumn` is tested above; this proves the engine resolve routes through it and the pool rebuilds —
// the ferry's §8 test 2 at the EMISSION level (ferry acceptance: "ADVANCE LOOP … chord changes on the lane's loop").

private final class ChordGridEmitter: MIDIEmitter {
    struct Ev { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
}

final class ChordColumnEngineTests: XCTestCase {
    private let beat: Int64 = 24_000                 // 120 BPM at 48 kHz
    private let degrees = [0, 3, 4, 5]               // I IV V vi of the default C natural minor — distinct roots

    private func expectedRoot(column c: Int) -> Int {
        diatonicChord(degree: degrees[((c % 4) + 4) % 4], scaleTones: ScaleType.naturalMinor.intervals, rootNote: 48, voicing: .triad, spread: .close).min()!
    }

    func testTheEmittedChordAdvancesOncePerLaneLoop() {
        // lane 0: FREE, hits every 1/8 step over 8 steps → a loop (pass) every 4 beats; its riff plays rank 1 only,
        // so each hit emits exactly the LOWEST pool note = the current chord's root.
        var l = EuclidLine(target: 0, pulses: 8, steps: 8)
        l.rate = .r1_8; l.useRiff = true; l.riffOn = true; l.gate = 0.5; l.velocityAbsolute = 90
        l.restartRhythmBars = []; l.restartMelodyPasses = []
        var gold = Machine(machineID: "gold", type: .euclid)
        gold.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        gold.paramsA.euclidLines = [l, EuclidLine(target: 0, pulses: 1, steps: 8), EuclidLine(target: 0, pulses: 1, steps: 8), EuclidLine(target: 0, pulses: 1, steps: 8)]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: [gold], scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = degrees; cs.chordsSteps = 4; cs.chordsRate = .r1_1
        cs.advanceUnit = .loop; cs.advanceLane = 0; cs.advanceEvery = 1              // ADVANCE LOOP lane 1 (index 0)
        st.euclideousChordSets = [cs, MachineParams()]
        st.euclideousSourcePlan = SourcePlan(midiOn: false, chordsOn: true, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [])

        let box = SnapshotBuilder.build(from: st)
        let e = ChordGridEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, p = NotePool()
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < 16 {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: 2048, forceColumn: 0, out: e, diag: &diag)
            ts += 2048
        }
        // the ONE note emitted on ALL (cable 0) at each beat = the chord root at that beat
        var rootAt = [Int](repeating: -1, count: 16)
        for ev in e.ons where ev.cable == 0 {
            let b = Int((Double(ev.sample) / Double(beat)).rounded())
            if b >= 0, b < 16 { rootAt[b] = Int(ev.note) }
        }
        // sampled mid-loop: the chord advances once per 4-beat loop → a new column (and root) each loop
        XCTAssertEqual(rootAt[2],  expectedRoot(column: 0), "loop 0 → column 0 (degree I)")
        XCTAssertEqual(rootAt[6],  expectedRoot(column: 1), "loop 1 → column 1 (degree IV)")
        XCTAssertEqual(rootAt[10], expectedRoot(column: 2), "loop 2 → column 2 (degree V)")
        XCTAssertEqual(rootAt[14], expectedRoot(column: 3), "loop 3 → column 3 (degree vi)")
        // and it holds WITHIN a loop (beats 1,2,3 share column 0's root) — it advances on the loop, not the rate
        XCTAssertEqual(rootAt[1], rootAt[2]); XCTAssertEqual(rootAt[3], rootAt[2])
        XCTAssertNotEqual(rootAt[2], rootAt[6], "the root actually changes on the loop")
    }
}

// MARK: - CHORDS PAGE ferry §13: the page geometry (re-based to the real 769.33×610 / 782×611.33 block)

final class ChordsPageLayoutTests: XCTestCase {
    func testLandscapeReferenceGeometry() {
        let L = euclideousChordsPageLayout(block: CGSize(width: 769.33, height: 610))   // = the lane-cards block / euclideousMixRowsPanelSize
        XCTAssertEqual(L.content.width, 737.33, accuracy: 0.02)
        XCTAssertEqual(L.content.height, 578, accuracy: 0.02)
        XCTAssertEqual(L.colW, 360.665, accuracy: 0.02)                 // §5.2 (content − 16)/2 — the ferry's 354 was vs its wrong 724 content
        XCTAssertEqual(L.column1.minX, L.colW + 16, accuracy: 0.02)
        XCTAssertEqual(L.cellW(steps: 8), 38.83, accuracy: 0.02)        // §5.6 (ferry 38)
        XCTAssertEqual(L.cellW(steps: 16), 18.42, accuracy: 0.02)       // (ferry 18)
        XCTAssertEqual(L.gridY, 110, accuracy: 0.02)
        XCTAssertEqual(L.gridH, 385, accuracy: 0.02)
        XCTAssertEqual(L.rowH, 345.0 / 18.0, accuracy: 0.02)            // §5.6 = 19.17 (ferry ~18.9 was vs the wrong content height)
        XCTAssertGreaterThan(L.rowH, EuclideousChordsPageMetrics.rowHFloor)
        XCTAssertEqual(L.laneStrip.minY, 543, accuracy: 0.02)
        XCTAssertEqual(L.laneStrip.height, 35, accuracy: 0.02)
        XCTAssertEqual(L.laneCardW, (737.33 - 24) / 4, accuracy: 0.02)  // §5.7 four cards, 8 apart
        // the divider gap (2 normal + 6) sits between row 11 (REST) and row 12 (first colour row)
        XCTAssertEqual(L.rowTop(12) - (L.rowTop(11) + L.rowH), 8, accuracy: 0.02)
        // the column row stack (§5.2)
        XCTAssertEqual(L.advanceY, 30, accuracy: 0.02)
        XCTAssertEqual(L.restartY, 62, accuracy: 0.02)
        XCTAssertEqual(L.stepStripY, 96, accuracy: 0.02)
    }
    func testPortraitReferenceGeometry() {
        let L = euclideousChordsPageLayout(block: CGSize(width: 782, height: 611.33))
        XCTAssertEqual(L.content.width, 750, accuracy: 0.02)
        XCTAssertEqual(L.colW, 367, accuracy: 0.02)                     // (750 − 16)/2
        XCTAssertEqual(L.cellW(steps: 8), (367 - 36 - 14) / 8, accuracy: 0.02)
    }
}
