//  LanesGridTests.swift
//  LANES GRID ferry (2026-10-18): the per-lane mute grid + separate rhythm / melody restart masks. The pure layer in Derivations.swift
//  (mute cells, the 16-cell masked origin, the migration of pre-feature documents) is covered here; the engine half (Router) is covered
//  in RouterTests next to the golden streams it must not move.

import XCTest

final class LanesGridTests: XCTestCase {

    // MARK: - units (§1.2 / §1.4 / §1.5)

    func testUnitLengthsFollowTheLanesOwnStepAndLap() {
        // A 3-of-8 lane at 1/8: step 0.5 beat, lap (8 steps) = 4 beats.
        let step = 0.5, pass = 4.0
        XCTAssertEqual(EuclideousMuteUnit.step.beats(stepBeats: step, passBeats: pass), 0.5)
        XCTAssertEqual(EuclideousMuteUnit.fourSteps.beats(stepBeats: step, passBeats: pass), 2)
        XCTAssertEqual(EuclideousMuteUnit.pass.beats(stepBeats: step, passBeats: pass), 4)
        XCTAssertEqual(EuclideousMuteUnit.twoPass.beats(stepBeats: step, passBeats: pass), 8)
        XCTAssertEqual(EuclideousRestartUnit.fourSteps.beats(stepBeats: step, passBeats: pass), 2)
        XCTAssertEqual(EuclideousRestartUnit.pass.beats(stepBeats: step, passBeats: pass), 4)
        XCTAssertEqual(EuclideousRestartUnit.twoPass.beats(stepBeats: step, passBeats: pass), 8)
        XCTAssertEqual(EuclideousRestartUnit.fourPass.beats(stepBeats: step, passBeats: pass), 16)
        // Change STEPS (8 → 5) and the rate (1/8 → 1/16): the units change with them.
        let step2 = 0.25, pass2 = 5 * 0.25
        XCTAssertEqual(EuclideousMuteUnit.pass.beats(stepBeats: step2, passBeats: pass2), 1.25)
        XCTAssertEqual(EuclideousMuteUnit.twoPass.beats(stepBeats: step2, passBeats: pass2), 2.5)
        XCTAssertEqual(EuclideousMuteUnit.fourSteps.beats(stepBeats: step2, passBeats: pass2), 1)
    }
    func testUnitTicksAreIntegerMultiplesOfTheLanesTickAndTheLapIsTheRoutersCycle() {
        for cycleLen in [2, 5, 8, 16, 32] {
            XCTAssertEqual(EuclideousMuteUnit.step.ticks(cycleLen: cycleLen), 1)
            XCTAssertEqual(EuclideousMuteUnit.fourSteps.ticks(cycleLen: cycleLen), 4)
            XCTAssertEqual(EuclideousMuteUnit.pass.ticks(cycleLen: cycleLen), cycleLen)
            XCTAssertEqual(EuclideousMuteUnit.twoPass.ticks(cycleLen: cycleLen), 2 * cycleLen)
            XCTAssertEqual(EuclideousRestartUnit.fourPass.ticks(cycleLen: cycleLen), 4 * cycleLen)
            // beats == ticks × step, exactly (the engine feeds the origin function Double(ticks) × sub)
            let sub = 0.25
            XCTAssertEqual(EuclideousRestartUnit.twoPass.beats(stepBeats: sub, passBeats: Double(cycleLen) * sub),
                           Double(EuclideousRestartUnit.twoPass.ticks(cycleLen: cycleLen)) * sub)
        }
    }
    func testRateBoxTapOrderCyclesExactlyAsSpecified() {
        XCTAssertEqual(EuclideousMuteUnit.step.next, .fourSteps)
        XCTAssertEqual(EuclideousMuteUnit.fourSteps.next, .pass)
        XCTAssertEqual(EuclideousMuteUnit.pass.next, .twoPass)
        XCTAssertEqual(EuclideousMuteUnit.twoPass.next, .step)
        XCTAssertEqual(EuclideousRestartUnit.fourSteps.next, .pass)
        XCTAssertEqual(EuclideousRestartUnit.pass.next, .twoPass)
        XCTAssertEqual(EuclideousRestartUnit.twoPass.next, .fourPass)
        XCTAssertEqual(EuclideousRestartUnit.fourPass.next, .fourSteps)
        XCTAssertEqual(EuclideousMuteUnit.allCases.map { $0.label }, ["STEP", "4STP", "PASS", "2PASS"])
        XCTAssertEqual(EuclideousRestartUnit.allCases.map { $0.label }, ["4STP", "PASS", "2PASS", "4PASS"])
    }

    // MARK: - mute (§2.1)

    func testMuteCellIndexAndAudibleAcrossAWindowBoundaryForEachUnit() {
        // Cells 0 and 15 clear, the rest set. For each unit length: the cell at beats around the 16-unit window wrap.
        let cells: UInt16 = 0x7FFE
        for unit in [0.25, 1.0, 2.5, 4.0, 8.0] {
            let window = 16 * unit
            XCTAssertEqual(euclideousLaneMuteCell(beat: 0, unitBeats: unit), 0)
            XCTAssertEqual(euclideousLaneMuteCell(beat: unit * 0.999, unitBeats: unit), 0)
            XCTAssertEqual(euclideousLaneMuteCell(beat: unit, unitBeats: unit), 1)
            XCTAssertEqual(euclideousLaneMuteCell(beat: window - unit * 0.001, unitBeats: unit), 15)
            XCTAssertEqual(euclideousLaneMuteCell(beat: window, unitBeats: unit), 0, "the window wraps back to cell 0")
            XCTAssertEqual(euclideousLaneMuteCell(beat: window + unit, unitBeats: unit), 1)
            XCTAssertEqual(euclideousLaneMuteCell(beat: 3 * window + 5 * unit + unit / 3, unitBeats: unit), 5)
            XCTAssertFalse(euclideousLaneAudible(beat: 0, cells16: cells, unitBeats: unit), "cell 0 is clear")
            XCTAssertTrue(euclideousLaneAudible(beat: unit, cells16: cells, unitBeats: unit))
            XCTAssertFalse(euclideousLaneAudible(beat: 15 * unit, cells16: cells, unitBeats: unit), "cell 15 is clear")
            XCTAssertFalse(euclideousLaneAudible(beat: window, cells16: cells, unitBeats: unit), "…and the next window's cell 0 is clear again")
            XCTAssertTrue(euclideousLaneAudible(beat: window - 2 * unit, cells16: cells, unitBeats: unit), "cell 14 is set")
        }
    }
    func testMuteBeforeBeatZeroAndDefaultsAndDegenerateUnits() {
        XCTAssertEqual(euclideousLaneMuteCell(beat: -0.25, unitBeats: 1), 15, "a beat before the transport origin wraps backwards deterministically")
        XCTAssertEqual(euclideousLaneMuteCell(beat: -1.0, unitBeats: 1), 15)
        XCTAssertEqual(euclideousLaneMuteCell(beat: -16.0, unitBeats: 1), 0)
        XCTAssertTrue(euclideousLaneAudible(beat: 7.3, cells16: 0xFFFF, unitBeats: 2), "all-set grid is always audible")
        XCTAssertEqual(euclideousLaneMuteCell(beat: 5, unitBeats: 0), 0, "a zero unit must not trap")
    }
    func testMuteStartFindsTheBoundaryWhereASetCellIsFollowedByAClearOne() {
        let cells: UInt16 = 0b1111_1111_1111_0111   // cell 3 clear
        let unit = 2.0
        // inside cell 2 → the next mute starts at cell 3's left edge, beat 6
        XCTAssertEqual(euclideousLaneMuteStart(fromBeat: 4.5, toBeat: 6.4, cells16: cells, unitBeats: unit), 6)
        // the window ends exactly on the boundary → included (to is inclusive)
        XCTAssertEqual(euclideousLaneMuteStart(fromBeat: 4.5, toBeat: 6.0, cells16: cells, unitBeats: unit), 6)
        XCTAssertNil(euclideousLaneMuteStart(fromBeat: 4.5, toBeat: 5.9, cells16: cells, unitBeats: unit))
        // already inside the clear cell → no new mute start until the next window's cell 3
        XCTAssertNil(euclideousLaneMuteStart(fromBeat: 6.5, toBeat: 9.0, cells16: cells, unitBeats: unit))
        XCTAssertEqual(euclideousLaneMuteStart(fromBeat: 6.5, toBeat: 6.0 + 32, cells16: cells, unitBeats: unit), 6 + 32)
        // an all-set grid never mutes
        XCTAssertNil(euclideousLaneMuteStart(fromBeat: 0, toBeat: 100, cells16: 0xFFFF, unitBeats: unit))
        // clear→clear (a run of muted cells) is not a NEW mute start
        let run: UInt16 = 0b1111_1111_1100_1111    // cells 4, 5 clear
        XCTAssertEqual(euclideousLaneMuteStart(fromBeat: 7, toBeat: 12, cells16: run, unitBeats: unit), 8)
        XCTAssertNil(euclideousLaneMuteStart(fromBeat: 8.5, toBeat: 12, cells16: run, unitBeats: unit))
    }

    // MARK: - 16-cell masked origin (§2.3)


    // MARK: - persistence + migration (§1.6 / §6)

    private func line(_ mutate: (inout EuclidLine) -> Void = { _ in }) -> EuclidLine { var l = EuclidLine(); mutate(&l); return l }

    func testNewFieldsRoundTripAndDefaultsResolve() throws {
        var l = EuclidLine()
        XCTAssertFalse(l.usesLaneGrid)
        XCTAssertEqual(l.muteCells16Resolved, 0xFFFF)
        XCTAssertEqual(l.muteUnitResolved, .pass)
        XCTAssertEqual(l.restartRhythmMask16Resolved, 0)
        XCTAssertEqual(l.restartMelodyMask16Resolved, 0)
        XCTAssertEqual(l.restartUnitResolved, .pass)
        l.muteCells16 = 0x0F0F; l.muteUnit = EuclideousMuteUnit.fourSteps.rawValue
        l.restartRhythmMask16 = 0x0120; l.restartMelodyMask16 = 0x8001; l.restartUnit = EuclideousRestartUnit.twoPass.rawValue
        XCTAssertTrue(l.usesLaneGrid)
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
        XCTAssertEqual(back.muteCells16Resolved, 0x0F0F)
        XCTAssertEqual(back.muteUnitResolved, .fourSteps)
        XCTAssertEqual(back.restartRhythmMask16Resolved, 0x0120)
        XCTAssertEqual(back.restartMelodyMask16Resolved, 0x8001)
        XCTAssertEqual(back.restartUnitResolved, .twoPass)
    }
    func testAPreFeatureLineDecodesWithoutAFactoryResetAndUsesNoGrid() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":1,"invert":false,"resetSteps":2,"restartMask":17}"#.utf8)
        let l = try JSONDecoder().decode(EuclidLine.self, from: json)
        XCTAssertEqual(l.pulses, 5); XCTAssertEqual(l.restartMask, 17)
        XCTAssertFalse(l.usesLaneGrid)
        XCTAssertNil(l.muteCells16); XCTAssertNil(l.restartUnit)
    }
    func testAnOutOfRangeStoredUnitFallsBackToPass() {
        var l = EuclidLine()
        l.muteUnit = 9; l.restartUnit = 0
        XCTAssertEqual(l.muteUnitResolved, .pass)
        XCTAssertEqual(l.restartUnitResolved, .pass)
    }

    private let allLit = [Bool](repeating: true, count: 32)
    private func resolve(_ l: EuclidLine, lane: Int = 0, on: Bool = false, rate: EuclideousSeqRate = .oneBar, len: Int = 8,
                         cells: [Bool]? = nil, step: Double = 0.5, pass: Double = 4, bar: Double = 4) -> EuclideousLaneGrid {
        euclideousLaneGridResolved(line: l, lane: lane, legacyOn: on, legacyRate: rate, legacyLen: len, legacyCells: cells ?? allLit,
                                   stepBeats: step, passBeats: pass, beatsPerBar: bar)
    }
    func testMigrationOldSequencerOffIsTheDefaultGrid() {
        XCTAssertEqual(resolve(line()), EuclideousLaneGrid.defaults)
        // …even with a wrong-length old cell array and odd LEN: OFF reads nothing
        XCTAssertEqual(resolve(line(), on: false, len: 5, cells: [true]), EuclideousLaneGrid.defaults)
    }
    func testMigrationOldSequencerOnPicksTheNearestUnitAndRepeatsCellsModLen() {
        // lane 1 (index 1), LEN 3: old cells for steps 0,1,2 → lit, dark, lit
        var cells = allLit
        cells[0 * 4 + 1] = true; cells[1 * 4 + 1] = false; cells[2 * 4 + 1] = true
        // 3-of-8 @ 1/8: step 0.5, pass 4. Old rate 1 BAR (S = 4) → PASS exactly.
        let g = resolve(line(), lane: 1, on: true, rate: .oneBar, len: 3, cells: cells)
        XCTAssertEqual(g.muteUnit, .pass)
        for i in 0..<16 { XCTAssertEqual((g.muteCells >> UInt16(i)) & 1 != 0, i % 3 != 1, "cell \(i)") }
        // ½ BAR (S = 2) → 4STP (2 beats); ¼ BAR (S = 1) → between STEP 0.5 and 4STP 2: nearest is 0.5 (d .5) vs 2 (d 1) → STEP
        XCTAssertEqual(resolve(line(), on: true, rate: .halfBar).muteUnit, .fourSteps)
        XCTAssertEqual(resolve(line(), on: true, rate: .quarterBar).muteUnit, .step)
        // 2 BARS (S = 8) → 2PASS exactly; 4 BARS (S = 16) → nothing longer than 2PASS, so 2PASS
        XCTAssertEqual(resolve(line(), on: true, rate: .twoBars).muteUnit, .twoPass)
        XCTAssertEqual(resolve(line(), on: true, rate: .fourBars).muteUnit, .twoPass)
    }
    func testMigrationNearestUnitTiesGoToTheLonger() {
        // step 1, pass 3 → STEP 1, 4STP 4, PASS 3, 2PASS 6. S = 2 is equidistant from STEP (1) and PASS (3) → the longer: PASS.
        let g = euclideousLaneGridResolved(line: EuclidLine(), lane: 0, legacyOn: true, legacyRate: .halfBar, legacyLen: 8, legacyCells: allLit,
                                           stepBeats: 1, passBeats: 3, beatsPerBar: 4)
        XCTAssertEqual(g.muteUnit, .pass)
    }
    func testMigrationOldRestartsBecomeBothMasksRepeatedModLenAndAreNotGatedByTheSequencerOn() {
        // every 2 steps: bits 0,2,4,6 of the 8-bit mask; LEN 8; old rate 1 BAR over a lane whose pass is 4 beats → PASS
        let l = line { $0.restartMask = euclideousStampMask(2) }
        for on in [false, true] {
            let g = resolve(l, on: on, rate: .oneBar, len: 8)
            XCTAssertEqual(g.restartUnit, .pass, "on=\(on)")
            XCTAssertEqual(g.rhythmMask, g.melodyMask, "both masks get the old marks")
            XCTAssertEqual(g.rhythmMask, 0x5555, "bits 0,2,4,… of the 16 cells")
        }
        // LEN 3 with an old mark on step 0 only: repeated every 3 cells
        let l3 = line { $0.restartMask = 1 }
        XCTAssertEqual(resolve(l3, on: true, len: 3).rhythmMask, 0x9249)
        // a mark beyond LEN is ignored (the old mask is width-masked to LEN)
        let beyond = line { $0.restartMask = 0b1000_0000 }
        XCTAssertEqual(resolve(beyond, on: true, len: 4).rhythmMask, 0)
        // the restart unit follows S too: ½ BAR over a 3-of-8 @ 1/8 lane → 4STP
        XCTAssertEqual(resolve(l, rate: .halfBar).restartUnit, .fourSteps)
        // old resetSteps (no explicit mask) migrates through the stamp
        let viaSteps = line { $0.resetSteps = 4 }
        XCTAssertEqual(resolve(viaSteps, len: 8).rhythmMask, 0x1111)
    }
    func testMigrationStopsOnceALaneHasBeenEditedOnTheGrid() {
        var l = line { $0.restartMask = 0xFF }
        let before = resolve(l, on: true, rate: .oneBar, len: 8)
        XCTAssertEqual(before.rhythmMask, 0xFFFF)
        euclideousPinLaneGrid(&l, before)                       // the first edit pins all five fields
        XCTAssertTrue(l.usesLaneGrid)
        l.restartMask = 0                                       // later changes to the OLD fields no longer matter
        let after = resolve(l, on: false, rate: .fourBars, len: 1)
        XCTAssertEqual(after, before)
        XCTAssertEqual(after.rhythmMask, 0xFFFF)
    }
    func testPinWritesAllFiveFieldsFromTheResolvedGrid() {
        var l = EuclidLine()
        let g = EuclideousLaneGrid(muteCells: 0x00F0, muteUnit: .twoPass, rhythmMask: 0x0003, melodyMask: 0x4000, restartUnit: .fourPass)
        euclideousPinLaneGrid(&l, g)
        XCTAssertEqual(l.muteCells16, 0x00F0); XCTAssertEqual(l.muteUnit, EuclideousMuteUnit.twoPass.rawValue)
        XCTAssertEqual(l.restartRhythmMask16, 0x0003); XCTAssertEqual(l.restartMelodyMask16, 0x4000)
        XCTAssertEqual(l.restartUnit, EuclideousRestartUnit.fourPass.rawValue)
        XCTAssertEqual(resolve(l), g)
    }
    func testEveryFactoryPresetLaneMigratesToTheDefaultGrid() {
        // None of the 20 presets sets the old sequencer or a reset, so each lane must resolve to "all sounding, no restarts".
        for (name, make) in EuclideousPresets.all {
            let doc = make()
            XCTAssertFalse(doc.euclideousLanesSeqOnResolved, name)
            for (i, l) in doc.euclideousLinesResolved.enumerated() {
                XCTAssertEqual(l.restartMaskResolved, 0, "\(name) lane \(i)")
                XCTAssertEqual(resolve(l, lane: i, on: doc.euclideousLanesSeqOnResolved, rate: doc.euclideousLanesSeqRateResolved,
                                       len: doc.euclideousLanesSeqLenResolved, cells: doc.euclideousLanesSeqCellsResolved),
                               EuclideousLaneGrid.defaults, "\(name) lane \(i)")
            }
        }
    }

    // MARK: - layout, position map, hit test, runs, mark beats (§4, §5)

    func testLayoutAtTheReferenceMatchesTheSpecNumbers() {
        let L = euclideousLanesLayout(width: 394, height: 260)          // the spec's 410×303 panel less 8pt padding and the tab strip
        XCTAssertEqual(L.gridX, 42); XCTAssertEqual(L.gridW, 352)
        XCTAssertEqual(L.cellW, 20.125, accuracy: 1e-9)
        XCTAssertEqual(L.pitch, 22.125, accuracy: 1e-9)
        XCTAssertEqual(L.cellLeft(15), 331.875, accuracy: 1e-9)
        XCTAssertEqual(L.laneH, 50)
        XCTAssertEqual(L.laneTop(0), 28); XCTAssertEqual(L.laneTop(3), 190)       // y = 63 and 225 less the sub-tab row's own 35 origin
        XCTAssertEqual(L.legendTop, 244)                                         // y = 279 − 35
        XCTAssertEqual(L.rowH, 24)                                               // two 24pt restart rows with a 2pt gap
    }
    func testLayoutScalesTheLaneBlocksWithTheRealHeightAndNeverBelowTheFloor() {
        XCTAssertEqual(euclideousLanesLayout(width: 394, height: 272).laneH, 53)
        XCTAssertEqual(euclideousLanesLayout(width: 394, height: 208).laneH, 37)
        XCTAssertEqual(euclideousLanesLayout(width: 394, height: 100).laneH, 34, "a floor, so the cells stay tappable")
        let tall = euclideousLanesLayout(width: 394, height: 400)
        XCTAssertEqual(tall.legendTop + EuclideousLanesLayout.legendH, 60 + 4 * tall.laneH, accuracy: 1e-9, "the stack fills the height")
        XCTAssertEqual(euclideousLanesLayout(width: 320, height: 260).cellW, (320 - 42 - 30) / 16, accuracy: 1e-9)
    }
    func testPositionMapJumpsTheGapsAndWrapsTheWindow() {
        let L = euclideousLanesLayout(width: 394, height: 260)
        let p0 = euclideousLanesPosition(beat: 0, unitBeats: 1, layout: L)
        XCTAssertEqual(p0.cell, 0); XCTAssertEqual(p0.x, 0, accuracy: 1e-9)
        let half = euclideousLanesPosition(beat: 0.5, unitBeats: 1, layout: L)
        XCTAssertEqual(half.x, 0.5 * L.cellW, accuracy: 1e-9)
        let before = euclideousLanesPosition(beat: 0.999999, unitBeats: 1, layout: L), after = euclideousLanesPosition(beat: 1, unitBeats: 1, layout: L)
        XCTAssertEqual(before.cell, 0); XCTAssertEqual(after.cell, 1)
        XCTAssertEqual(after.x - before.x, 2, accuracy: 0.001, "the playhead jumps the 2pt gap")
        XCTAssertEqual(euclideousLanesPosition(beat: 15.5, unitBeats: 1, layout: L).cell, 15)
        XCTAssertEqual(euclideousLanesPosition(beat: 16, unitBeats: 1, layout: L).cell, 0, "the window wraps")
        XCTAssertEqual(euclideousLanesPosition(beat: -0.5, unitBeats: 1, layout: L).cell, 15, "before beat 0 wraps backwards")
        XCTAssertEqual(euclideousLanesPosition(beat: 7.5, unitBeats: 0.5, layout: L).cell, 15)
        XCTAssertEqual(euclideousLanesPosition(beat: 5, unitBeats: 0, layout: L).cell, 0)
    }
    func testWindowStartsAtTheFlooredWindow() {
        let w = euclideousLanesWindow(beat: 37, unitBeats: 2)          // window 32
        XCTAssertEqual(w.start, 32); XCTAssertEqual(w.length, 32)
        XCTAssertEqual(euclideousLanesWindow(beat: 31.99, unitBeats: 2).start, 0)
        XCTAssertEqual(euclideousLanesWindow(beat: -1, unitBeats: 2).start, -32)
    }
    func testHitTestClaimsTheGapsAndTheRowBoundary() {
        let L = euclideousLanesLayout(width: 394, height: 260)
        let gx = L.gridX
        func hit(_ x: CGFloat, _ y: CGFloat, restart: Bool = false) -> EuclideousLanesHit? { euclideousLanesHit(x: x, y: y, layout: L, restart: restart) }
        XCTAssertEqual(hit(gx + 5, 40), EuclideousLanesHit(lane: 0, cell: 0, row: 0))
        XCTAssertEqual(hit(gx + 20.5, 40)?.cell, 0, "the first pt of the gap belongs to the cell on its left")
        XCTAssertEqual(hit(gx + 21.2, 40)?.cell, 1, "…the second to the cell on its right (1pt slop each side)")
        XCTAssertEqual(hit(gx - 0.9, 40)?.cell, 0)
        XCTAssertNil(hit(gx - 1.1, 40)); XCTAssertNil(hit(L.gridX - 20, 40), "the rail is not a cell")
        XCTAssertEqual(hit(gx + L.gridW + 0.5, 40)?.cell, 15)
        XCTAssertNil(hit(gx + L.gridW + 1.1, 40))
        // lanes and the gaps between them
        XCTAssertEqual(hit(gx + 5, L.laneTop(2) + 10)?.lane, 2)
        XCTAssertNil(hit(gx + 5, L.laneTop(0) + L.laneH + 2), "the 4pt gap between blocks is nothing")
        XCTAssertNil(hit(gx + 5, 10), "the sub-tab row is not a lane")
        // RESTART rows: rhythm above, melody below, the 2pt gap split 1pt each
        let t = L.laneTop(1)
        XCTAssertEqual(hit(gx + 5, t + 5, restart: true)?.row, 0)
        XCTAssertEqual(hit(gx + 5, t + L.rowH + 0.5, restart: true)?.row, 0)
        XCTAssertEqual(hit(gx + 5, t + L.rowH + 1.5, restart: true)?.row, 1)
        XCTAssertEqual(hit(gx + 5, t + L.laneH - 1, restart: true)?.row, 1)
        XCTAssertEqual(hit(gx + 5, t + L.laneH - 1, restart: false)?.row, 0, "MUTE has one row")
    }
    func testAStrokeStaysInItsLaneAndClampsToTheGridAndRows() {
        let L = euclideousLanesLayout(width: 394, height: 260)
        // finger drifts below the lane and past the right edge: still lane 1, last cell, melody row
        let h = euclideousLanesStrokeHit(x: 9999, y: L.laneTop(1) + L.laneH + 30, lane: 1, layout: L, restart: true)
        XCTAssertEqual(h, EuclideousLanesHit(lane: 1, cell: 15, row: 1))
        let h2 = euclideousLanesStrokeHit(x: -50, y: L.laneTop(1) - 30, lane: 1, layout: L, restart: true)
        XCTAssertEqual(h2, EuclideousLanesHit(lane: 1, cell: 0, row: 0))
    }

    // MARK: - edits (§5)

    private func gridOf(_ l: EuclidLine) -> EuclideousLaneGrid { resolve(l) }
    func testATapTogglesOneCellAndPinsAllFiveFields() {
        var l = EuclidLine()
        XCTAssertFalse(l.usesLaneGrid)
        euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .mute(cell: 3, on: false))
        XCTAssertTrue(l.usesLaneGrid, "the first edit pins every field")
        XCTAssertEqual(l.muteCells16, 0xFFFF & ~(1 << 3)); XCTAssertEqual(l.muteUnit, EuclideousMuteUnit.pass.rawValue)
        XCTAssertEqual(l.restartRhythmMask16, 0); XCTAssertEqual(l.restartMelodyMask16, 0); XCTAssertEqual(l.restartUnit, EuclideousRestartUnit.pass.rawValue)
        euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .mute(cell: 3, on: true))
        XCTAssertEqual(l.muteCells16, 0xFFFF)
    }
    func testAStrokeOfManyEditsAgainstOneStaleSnapshotKeepsEveryPaintedCell() {
        var l = EuclidLine()
        let snapshot = gridOf(l)                                   // taken at touch-down; the lane then changes under it
        for cell in 4..<12 { euclideousApplyLaneGridOp(&l, resolved: snapshot, .mute(cell: cell, on: false)) }
        XCTAssertEqual(l.muteCells16, 0xFFFF & ~0x0FF0, "all eight painted cells survive — the stale snapshot never re-pins over them")
    }
    func testRestartTapsWriteTheRightRowAndLeaveTheOtherAlone() {
        var l = EuclidLine()
        euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .restart(melody: false, cell: 8, on: true))
        XCTAssertEqual(l.restartRhythmMask16, 1 << 8); XCTAssertEqual(l.restartMelodyMask16, 0)
        euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .restart(melody: true, cell: 8, on: true))
        XCTAssertEqual(l.restartMelodyMask16, 1 << 8)
        euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .restart(melody: false, cell: 8, on: false))
        XCTAssertEqual(l.restartRhythmMask16, 0); XCTAssertEqual(l.restartMelodyMask16, 1 << 8)
        XCTAssertEqual(l.muteCells16, 0xFFFF, "restart edits never touch the mute cells")
    }
    func testRateBoxTapsCycleTheUnitAndKeepEveryCell() {
        var l = EuclidLine()
        euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .mute(cell: 2, on: false))
        euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .restart(melody: false, cell: 5, on: true))
        let cellsBefore = (l.muteCells16, l.restartRhythmMask16)
        var seen: [EuclideousMuteUnit] = []
        for _ in 0..<4 { euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .nextMuteUnit); seen.append(l.muteUnitResolved) }
        XCTAssertEqual(seen, [.twoPass, .step, .fourSteps, .pass], "PASS → 2PASS → STEP → 4STP → PASS")
        var seenR: [EuclideousRestartUnit] = []
        for _ in 0..<4 { euclideousApplyLaneGridOp(&l, resolved: gridOf(l), .nextRestartUnit); seenR.append(l.restartUnitResolved) }
        XCTAssertEqual(seenR, [.twoPass, .fourPass, .fourSteps, .pass])
        XCTAssertEqual(l.muteCells16, cellsBefore.0); XCTAssertEqual(l.restartRhythmMask16, cellsBefore.1, "cell contents are kept; only their meaning in time changes")
    }
    func testStrokeValueIsTheOppositeOfTheCellItStartedOn() {
        let g = EuclideousLaneGrid(muteCells: 0b101, muteUnit: .pass, rhythmMask: 0b10, melodyMask: 0, restartUnit: .pass)
        XCTAssertTrue(euclideousLaneGridCellValue(g, restart: false, melody: false, cell: 0))
        XCTAssertFalse(euclideousLaneGridCellValue(g, restart: false, melody: false, cell: 1))
        XCTAssertTrue(euclideousLaneGridCellValue(g, restart: true, melody: false, cell: 1))
        XCTAssertFalse(euclideousLaneGridCellValue(g, restart: true, melody: true, cell: 1))
    }
    func testAMigratedLanePinsItsMigratedValuesOnTheFirstEdit() {
        // an old lane: every-2 reset on a sequencer at 1 BAR with the lane's pass = 1 bar
        let old = line { $0.restartMask = euclideousStampMask(2) }
        let before = resolve(old, rate: .oneBar)
        var l = old
        euclideousApplyLaneGridOp(&l, resolved: before, .mute(cell: 0, on: false))
        XCTAssertEqual(l.restartRhythmMask16, before.rhythmMask, "the migrated marks became the stored marks")
        XCTAssertEqual(l.restartMelodyMask16, before.melodyMask); XCTAssertEqual(l.restartUnit, before.restartUnit.rawValue)
        XCTAssertEqual(l.muteCells16, 0xFFFE)
    }


    // MARK: - roll geometry + comet phase + lap baseline (§3, §4.6, §2.5)
    func testRollBarRowsFollowTheRankAxis() {
        XCTAssertEqual(euclideousRollBarY(rank: 1, laneH: 50), 4 + 7 * 5)       // lowest rank, lowest row
        XCTAssertEqual(euclideousRollBarY(rank: 8, laneH: 50), 4)
        XCTAssertEqual(euclideousRollBarY(rank: 0, laneH: 50), 22, "a rest sits on the middle line")
        XCTAssertEqual(euclideousRollBarY(rank: 8, laneH: 37), 4 * 0.74, accuracy: 1e-9, "scaled with the real lane height")
    }

    // MARK: - defaults, geometry agreement, and the equivalence with the pre-grid engine for LEN 1–8 (§1, §8, §9)

    func testAFreshDocumentShowsSixteenSoundingCellsAndNoRestartsOnEveryLane() {
        let fresh = PluginState(machines: [], scenes: [SceneState.empty()])
        let lines = fresh.euclideousLinesResolved
        for lane in 0..<4 {
            let v = euclideousLaneGridView(lines: lines, lane: lane, legacy: EuclideousLanesSeq(on: fresh.euclideousLanesSeqOnResolved, rate: fresh.euclideousLanesSeqRateResolved, len: fresh.euclideousLanesSeqLenResolved, cells: fresh.euclideousLanesSeqCellsResolved), defaultRateBeats: 0.25, beatsPerBar: 4)
            XCTAssertEqual(v.grid.muteCells, 0xFFFF, "lane \(lane + 1): 16 sounding cells")
            XCTAssertEqual(v.grid.rhythmMask, 0); XCTAssertEqual(v.grid.melodyMask, 0)
            XCTAssertEqual(v.grid.muteUnit, .pass); XCTAssertEqual(v.grid.restartUnit, .pass)
            XCTAssertFalse(euclideousLaneRestartGrid(v.grid, cycleLen: v.cycleLen).isActive, "no restart: the engine's grid path is not in force")
        }
    }
}
