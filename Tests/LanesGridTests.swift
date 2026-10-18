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

    func testMaskedOriginMarksOnCells0_5_12() {
        let mask: UInt16 = (1 << 0) | (1 << 5) | (1 << 12)
        let cb = 1.0
        for window in 0..<3 {
            let base = Double(window) * 16
            for cell in 0..<16 {
                let want: Double = cell < 5 ? 0 : (cell < 12 ? 5 : 12)
                let got = euclideousMaskedResetOrigin(beat: base + Double(cell) + 0.5, cellBeats: cb, mask: mask, cells: 16)
                XCTAssertEqual(got, base + want, "window \(window) cell \(cell)")
            }
        }
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 16.0, cellBeats: cb, mask: mask, cells: 16), 16, "the next window restarts at its cell 0")
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 15.999, cellBeats: cb, mask: mask, cells: 16), 12)
    }
    func testMaskedOriginMarkOnCell5OnlyCarriesTheLastMarkAcrossTheWindowBoundary() {
        let mask: UInt16 = 1 << 5
        let cb = 2.0
        // window 1, cells 0…4: no mark yet this window → the previous window's cell-5 mark (window 0, beat 10)
        for cell in 0..<5 {
            XCTAssertEqual(euclideousMaskedResetOrigin(beat: 32 + Double(cell) * cb + 0.1, cellBeats: cb, mask: mask, cells: 16), 10, "cell \(cell) of window 1")
        }
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 32 + 5 * cb, cellBeats: cb, mask: mask, cells: 16), 42, "the mark itself")
        // window 0, cells 0…4: nothing before it → a NEGATIVE origin (window −1's cell 5)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 0.5, cellBeats: cb, mask: mask, cells: 16), -32 + 10)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 8.9, cellBeats: cb, mask: mask, cells: 16), -22)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 10.0, cellBeats: cb, mask: mask, cells: 16), 10)
    }
    func testMaskedOriginEmptyMaskIsZeroForEveryBeat() {
        for beat in [-5.0, 0, 0.3, 17, 1000.7] {
            XCTAssertEqual(euclideousMaskedResetOrigin(beat: beat, cellBeats: 0.75, mask: 0, cells: 16), 0)
        }
        XCTAssertNil(euclideousMaskedResetCell(beat: 3, cellBeats: 1, mask: 0, cells: 16))
    }
    func testMaskedOriginNonIntegerCellBeatsOverThreeWindows() {
        let mask: UInt16 = (1 << 2) | (1 << 9)
        let cb = 0.75
        for window in 0..<3 {
            let base = Double(window) * 16 * cb
            for cell in 0..<16 {
                let beat = base + (Double(cell) + 0.25) * cb
                let got = euclideousMaskedResetOrigin(beat: beat, cellBeats: cb, mask: mask, cells: 16)
                let want: Double = cell < 2 ? base - 16 * cb + 9 * cb : (cell < 9 ? base + 2 * cb : base + 9 * cb)
                XCTAssertEqual(got, want, accuracy: 1e-12, "window \(window) cell \(cell)")
            }
        }
    }
    func testMaskedOriginCellFormAgreesWithTheBeatForm() {
        let masks: [UInt16] = [1, 1 << 5, 0b1010_0101_0000_0001, 0xFFFF, 1 << 15, (1 << 3) | (1 << 4)]
        for mask in masks { for cb in [0.25, 0.75, 1.0, 4.0] {
            for k in stride(from: -40.0, through: 90.0, by: 0.37) {
                let beat = k * cb
                let cell = euclideousMaskedResetCell(beat: beat, cellBeats: cb, mask: mask, cells: 16)!
                let origin = euclideousMaskedResetOrigin(beat: beat, cellBeats: cb, mask: mask, cells: 16)
                XCTAssertEqual(origin, Double(cell) * cb, accuracy: 1e-9, "mask \(mask) cb \(cb) beat \(beat)")
            }
        } }
    }
    func testEightBitWrapperIsTheSameFunction() {
        for mask in [UInt8(1), 0b0001_0001, 0b1000_0000, 0xFF, 0b0000_0110] { for len in 1...8 {
            for k in stride(from: -3.0, through: 70.0, by: 0.41) {
                let a = euclideousMaskedResetOrigin(beat: k, stepBeats: 2, mask: mask, loopSteps: len)
                let b = euclideousMaskedResetOrigin(beat: k, cellBeats: 2, mask: UInt16(mask), cells: len)
                XCTAssertEqual(a, b)
            }
        } }
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 5, stepBeats: 0, mask: 1, loopSteps: 8), 0)
        XCTAssertEqual(euclideousMaskedResetOrigin(beat: 5, stepBeats: 1, mask: 1, loopSteps: 0), 0)
    }

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

    // MARK: - the per-tick core (§2.4 – §2.6)

    /// splitmix64 — a deterministic stream for the randomised comparisons below.
    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int { range.lowerBound + Int(next() % UInt64(range.count)) }
        mutating func bool() -> Bool { next() & 1 == 1 }
    }
    private struct LaneCase {
        var buf: [Bool]; var n: Int; var dir: EuclidDir; var cycleLen: Int; var sub: Double
        var unit: Int; var rMask: UInt16; var mMask: UInt16; var locked: Bool; var adv: Bool
        var grid: EuclideousLaneRestartGrid { EuclideousLaneRestartGrid(unitTicks: unit, rhythmMask: rMask, melodyMask: mMask) }
        func core(_ t: Int64, span: Double = 0) -> EuclideousLaneTickInfo {
            euclideousLaneTick(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: sub, tick: t, grid: grid, legacySpanBeats: span, locked: locked, advanceStep: adv)
        }
        // ── an independent, tick-by-tick restatement of §2.5 (no closed forms, origins from the BEAT-based function) ──
        func originTick(_ t: Int64, _ mask: UInt16) -> Int64 {
            if mask == 0 { return 0 }
            // ticks before beat 0 are the previous window's mirror image (the schedule is periodic in the 16-cell window)
            let window = Int64(16 * unit)
            let shift = t < 0 ? ((-t + window - 1) / window) * window : 0
            let b = t + shift
            let o = euclideousMaskedResetOrigin(beat: Double(b) * sub, cellBeats: Double(unit) * sub, mask: mask, cells: 16)
            return Int64((o / sub).rounded()) - shift
        }
        func localT(_ t: Int64) -> Int64 { t - originTick(t, rMask) }
        func raw(_ t: Int64) -> Int { let c = Int64(cycleLen); return Int(((localT(t) % c) + c) % c) }
        func hit(_ t: Int64) -> Bool { buf[euclidReadIndex(raw(t), n: n, dir: dir)] }
        func advOrdBrute(_ t: Int64) -> Int64 {
            let lt = localT(t), r = Int64(raw(t))
            let cy = (lt - r) / Int64(cycleLen)
            let lapStart = originTick(t, rMask) + cy * Int64(cycleLen)
            let mAbs = originTick(t, mMask)
            let ref = locked ? max(lapStart, mAbs) : mAbs
            if adv { return t - ref }
            var c: Int64 = 0
            var k = ref
            while k <= t { if hit(k) { c += 1 }; k += 1 }
            return c - 1
        }
    }
    private func randomCase(_ rng: inout Rng, rMask: UInt16? = nil, mMask: UInt16? = nil) -> LaneCase {
        let n = rng.int(2...16)
        var buf = [Bool](repeating: false, count: 16)
        let k = rng.int(1...n)
        var placed = 0
        while placed < k { let i = rng.int(0...(n - 1)); if !buf[i] { buf[i] = true; placed += 1 } }
        let dir: EuclidDir = [.fwd, .bkw, .pingpong][rng.int(0...2)]
        let cycleLen = euclidCycleLen(dir, n: n)
        let unit = [4, cycleLen, 2 * cycleLen, 4 * cycleLen][rng.int(0...3)]
        func mask() -> UInt16 { let r = rng.int(0...3); return r == 0 ? 0 : UInt16(truncatingIfNeeded: rng.next()) & UInt16(truncatingIfNeeded: rng.next()) }
        return LaneCase(buf: buf, n: n, dir: dir, cycleLen: cycleLen, sub: [0.25, 0.5][rng.int(0...1)], unit: unit,
                        rMask: rMask ?? mask(), mMask: mMask ?? mask(), locked: rng.bool(), adv: rng.bool())
    }

    func testCoreWithoutAnyMarkIsTheLegacyArithmetic() {
        var rng = Rng(state: 11)
        for _ in 0..<60 {
            var c = randomCase(&rng, rMask: 0, mMask: 0)
            for span in [0.0, 6.0, 7.5] {
                for t in stride(from: Int64(-30), through: 220, by: 7) {
                    let got = c.core(t, span: span)
                    // verbatim pre-grid arithmetic
                    let tickBeat = Double(t) * c.sub
                    let phaseBeat = span > 0 ? (tickBeat - columnStart(tickBeat, span)) : tickBeat
                    let localT = Int64((phaseBeat / c.sub).rounded(.down))
                    let cl = Int64(c.cycleLen)
                    let raw = Int(((localT % cl) + cl) % cl)
                    var hitsUpTo = 0; for s in 0...raw where c.buf[euclidReadIndex(s, n: c.n, dir: c.dir)] { hitsUpTo += 1 }
                    var cycleHits = 0; for s in 0..<c.cycleLen where c.buf[euclidReadIndex(s, n: c.n, dir: c.dir)] { cycleHits += 1 }
                    let cy = (localT - Int64(raw)) / cl
                    let ord = cy * Int64(max(1, cycleHits)) + Int64(hitsUpTo - 1)
                    for (locked, adv) in [(false, false), (true, false), (false, true), (true, true)] {
                        c.locked = locked; c.adv = adv
                        let g = c.core(t, span: span)
                        let want: Int64 = adv ? (locked ? Int64(raw) : localT) : (locked ? Int64(hitsUpTo - 1) : ord)
                        XCTAssertEqual(g.advOrd, want, "t \(t) span \(span) locked \(locked) adv \(adv)")
                        XCTAssertEqual(g.localT, localT); XCTAssertEqual(g.raw, raw); XCTAssertEqual(g.hitsUpTo, hitsUpTo); XCTAssertEqual(g.cy, cy)
                        XCTAssertEqual(g.rawIsHit, c.buf[euclidReadIndex(raw, n: c.n, dir: c.dir)])
                    }
                    _ = got
                }
            }
        }
    }
    func testCoreMatchesTheTickByTickDefinitionForIndependentRhythmAndMelodyMarks() {
        var rng = Rng(state: 42)
        var checked = 0
        for _ in 0..<160 {
            let c = randomCase(&rng)
            for _ in 0..<14 {
                let t = Int64(rng.int(0...330))
                let info = c.core(t)
                XCTAssertEqual(info.localT, c.localT(t), "localT")
                XCTAssertEqual(info.raw, c.raw(t), "raw")
                XCTAssertEqual(info.rawIsHit, c.hit(t), "hit")
                guard info.rawIsHit || c.adv else { continue }
                XCTAssertEqual(info.advOrd, c.advOrdBrute(t), "advOrd tick \(t) rMask \(c.rMask) mMask \(c.mMask) unit \(c.unit) n \(c.n) dir \(c.dir) locked \(c.locked) adv \(c.adv)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 1200, "the comparison must actually run")
    }
    func testBothMarksOnTheSameCellsReproduceTheOldSingleRestart() {
        // The old engine: ONE origin (euclideousMaskedResetOrigin over the 8-bit mask) re-anchors the pattern AND the riff.
        var rng = Rng(state: 7)
        for _ in 0..<80 {
            var c = randomCase(&rng)
            let m = UInt16(truncatingIfNeeded: rng.next()) | 1
            c.rMask = m; c.mMask = m
            for t in stride(from: Int64(0), through: 260, by: 5) {   // ticks before beat 0 use the periodic extension, not the legacy truncating quirk
                let origin = euclideousMaskedResetOrigin(beat: Double(t) * c.sub, cellBeats: Double(c.unit) * c.sub, mask: m, cells: 16)
                let localT = Int64(((Double(t) * c.sub - origin) / c.sub).rounded(.down))
                let cl = Int64(c.cycleLen)
                let raw = Int(((localT % cl) + cl) % cl)
                var hitsUpTo = 0; for s in 0...raw where c.buf[euclidReadIndex(s, n: c.n, dir: c.dir)] { hitsUpTo += 1 }
                var cycleHits = 0; for s in 0..<c.cycleLen where c.buf[euclidReadIndex(s, n: c.n, dir: c.dir)] { cycleHits += 1 }
                let ord = (localT - Int64(raw)) / cl * Int64(max(1, cycleHits)) + Int64(hitsUpTo - 1)
                let want: Int64 = c.adv ? (c.locked ? Int64(raw) : localT) : (c.locked ? Int64(hitsUpTo - 1) : ord)
                let g = c.core(t)
                XCTAssertEqual(g.advOrd, want, "t \(t) mask \(m) locked \(c.locked) adv \(c.adv)")
                XCTAssertEqual(g.localT, localT)
            }
        }
    }

    /// A fixed, easy lane for the scenario tests: 3 hits in 8 steps (x..x..x. — Euclid 3/8 is hits at 0, 3, 6), FWD, 1 tick = 0.5 beat.
    private func scenario(rMask: UInt16, mMask: UInt16, unit: Int = 8, locked: Bool = false, adv: Bool = false) -> LaneCase {
        var buf = [Bool](repeating: false, count: 16)
        euclidPatternInto(&buf, pulses: 3, steps: 8, rotation: 0)
        return LaneCase(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, unit: unit, rMask: rMask, mMask: mMask, locked: locked, adv: adv)
    }
    private func hitTicks(_ c: LaneCase, _ range: ClosedRange<Int64>) -> [Int64] { range.filter { c.core($0).rawIsHit } }
    private func ordinals(_ c: LaneCase, _ range: ClosedRange<Int64>) -> [Int64] { range.filter { c.core($0).rawIsHit }.map { c.core($0).advOrd } }

    func testRhythmOnlyMarkRephasesTheHitsAndTheRiffKeepsCountingThroughIt() {
        // restart cells are one 8-tick pass; a RHYTHM mark on cell 2 (tick 16). Pattern hits sit at 0,3,6 of each pass.
        let base = scenario(rMask: 0, mMask: 0)
        let marked = scenario(rMask: 1 << 2, mMask: 0)
        // before the mark nothing differs; at the mark the pass restarts, so hits keep their positions here (16 is a pass boundary)…
        XCTAssertEqual(hitTicks(base, 0...40), hitTicks(marked, 0...40))
        // …now put the mark at cell 2 of a 6-tick cell so the restart lands MID-pass: the hits re-phase
        let odd = scenario(rMask: 1 << 2, mMask: 0, unit: 6)
        let h = hitTicks(odd, 0...40)
        XCTAssertNotEqual(h, hitTicks(scenario(rMask: 0, mMask: 0, unit: 6), 0...40), "the rhythm mark re-phased the hits")
        XCTAssertTrue(h.contains(12), "the mark itself is a restart: step 0 of the pattern (a hit) lands on tick 12")
        // the riff ordinal counts straight through the re-phase: with no melody mark it is simply hit 0,1,2,3… in sounding order
        XCTAssertEqual(ordinals(odd, 0...40), Array(0..<Int64(h.count)), "pitch sequence uninterrupted")
    }
    func testMelodyOnlyMarkLeavesEveryHitInPlaceAndSendsTheRiffBackToZero() {
        for (locked, adv) in [(false, false), (true, false), (false, true), (true, true)] {
            let base = scenario(rMask: 0, mMask: 0, unit: 6, locked: locked, adv: adv)
            let marked = scenario(rMask: 0, mMask: 1 << 2, unit: 6, locked: locked, adv: adv)   // melody mark at tick 12
            XCTAssertEqual(hitTicks(base, 0...60), hitTicks(marked, 0...60), "hit positions unchanged (locked \(locked) adv \(adv))")
            // the first hit at or after tick 12 reads ordinal 0 on the marked lane (STEP advance: ticks since the mark, so ≥ 0 and 0 at 12 itself)
            let after = hitTicks(marked, 12...60).first!
            let o = marked.core(after).advOrd
            if adv { XCTAssertEqual(o, after - 12) } else { XCTAssertEqual(o, 0, "the riff returned to its first position (locked \(locked))") }
            // …and it was NOT zero without the mark (FREE counts on; LOCK is anchored at the lap, so skip that comparison there)
            if !locked && !adv { XCTAssertNotEqual(base.core(after).advOrd, 0) }
        }
    }
    func testMarkOnCellZeroOfTheWindowAndAMarkCarriedAcrossTheWindowBoundary() {
        // melody mark on cell 5 only, 6-tick cells: window = 96 ticks. The riff restarts at tick 30, and again at 126 — NOT at 96.
        let c = scenario(rMask: 0, mMask: 1 << 5, unit: 6)
        let firstAfter30 = hitTicks(c, 30...60).first!
        XCTAssertEqual(c.core(firstAfter30).advOrd, 0)
        let across = hitTicks(c, 90...110)
        XCTAssertFalse(across.isEmpty)
        for t in across { XCTAssertEqual(c.core(t).advOrd, c.advOrdBrute(t)) }
        XCTAssertNotEqual(c.core(across.first(where: { $0 >= 96 })!).advOrd, 0, "no restart at the window boundary: the riff keeps counting from the previous window's mark")
        let firstAfter126 = hitTicks(c, 126...150).first!
        XCTAssertEqual(c.core(firstAfter126).advOrd, 0)
    }
    func testNegativeOriginInTheFirstWindowIsDeterministic() {
        let c = scenario(rMask: 1 << 5, mMask: 1 << 3, unit: 6)
        for t in Int64(0)..<30 { XCTAssertEqual(c.core(t).advOrd, c.advOrdBrute(t), "tick \(t)") }
        XCTAssertLessThan(c.core(0).localT - 0, 1000)
        XCTAssertGreaterThan(c.core(0).localT, 0, "the first window runs from a NEGATIVE origin, so the phase is already advanced")
    }
    func testNextHitGapHonoursARestartBetweenTheTwoHits() {
        // marks on cells 0 and 1 (ticks 0 and 6), 6-tick cells; the 3-of-8 pattern hits at 0,3,6 of each pass.
        let c = scenario(rMask: 0b11, mMask: 0, unit: 6)
        let plain = scenario(rMask: 0, mMask: 0, unit: 6)
        // from the restart at tick 6 (a hit), the plain pattern's next hit is tick 8 (the next pass's step 0)…
        let plainGap = euclideousNextHitGapBeats(buf: plain.buf, n: plain.n, dir: plain.dir, cycleLen: plain.cycleLen, sub: plain.sub, tick: 6, cap: 32, grid: plain.grid, legacySpanBeats: 0)
        XCTAssertEqual(plainGap, 2 * c.sub)
        // …but the pass restarted AT 6, so the next hit is step 3 of the new pass: tick 9
        let gap = euclideousNextHitGapBeats(buf: c.buf, n: c.n, dir: c.dir, cycleLen: c.cycleLen, sub: c.sub, tick: 6, cap: 32, grid: c.grid, legacySpanBeats: 0)
        XCTAssertEqual(gap, 3 * c.sub)
        let truth = (7...40).first { c.hit(Int64($0)) }!
        XCTAssertEqual(gap, Double(truth - 6) * c.sub, "the gap scan and the tick-by-tick definition agree")
    }
}
