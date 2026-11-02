import XCTest

/// POOL ferry (2026-11-02) §8 / §10 — the pure functions: per-lane SOURCES, the SUSTAIN gate, the rank chip, the grid's picker and the tab's layout.
final class PoolTabPureTests: XCTestCase {
    typealias Note = (note: Int, vel: UInt8)

    // MARK: 2 — laneSources
    func testLaneSourcesIsPanelAndLaneForEveryCombination() {
        for panelBits in 0..<16 {
            let panel = EuclideousSourceSwitches(midi: panelBits & 1 != 0, chords: panelBits & 2 != 0, pick: panelBits & 4 != 0, key: panelBits & 8 != 0)
            for mask in 0..<16 {
                let e = euclideousLaneSources(panel: panel, mask: UInt8(mask))
                XCTAssertEqual(e.midi, panel.midi && mask & 1 != 0, "panel \(panelBits) mask \(mask)")
                XCTAssertEqual(e.chords, panel.chords && mask & 2 != 0)
                XCTAssertEqual(e.pick, panel.pick && mask & 4 != 0)
                XCTAssertEqual(e.key, panel.key && mask & 8 != 0)
            }
        }
        // bits above the four are ignored
        XCTAssertEqual(euclideousLaneSources(panel: EuclideousSourceSwitches(midi: true, chords: true, pick: true, key: true), mask: 0xF0),
                       EuclideousSourceSwitches(midi: false, chords: false, pick: false, key: false))
    }
    func testLaneSourcePlanWritesOnlyTheFourSwitchesAndIsTheIdentityWhenAllAreOn() {
        var plan = SourcePlan(); plan.midiOn = true; plan.chordsOn = true; plan.pickOn = true; plan.keyOn = false
        plan.midiMode = .replace; plan.midiOctaves = .keep; plan.pickNotes = [60, 64]
        XCTAssertEqual(euclideousLaneSourcePlan(plan, mask: 0b1111), plan, "all on: the plan as it is")
        let p = euclideousLaneSourcePlan(plan, mask: 0b0101)        // MIDI IN + PICK on for the lane
        XCTAssertTrue(p.midiOnR); XCTAssertFalse(p.chordsOnR); XCTAssertTrue(p.pickOnR); XCTAssertFalse(p.keyOnR)
        XCTAssertEqual(p.midiModeR, .replace); XCTAssertEqual(p.midiOctavesR, .keep); XCTAssertEqual(p.pickNotesR, [60, 64])
        XCTAssertFalse(euclideousLaneSourcePlan(plan, mask: 0b1000).keyOnR, "a source off in the panel stays off whatever the lane says")
        XCTAssertFalse(euclideousLaneSourcePlan(plan, mask: 0).anyOnR)
    }
    func testASourceOffInThePanelDrawsItsToggleAt40Percent() {
        XCTAssertEqual(euclideousLaneSourceToggleOpacity(panelOn: true), 1); XCTAssertEqual(euclideousLaneSourceToggleOpacity(panelOn: false), 0.4)
    }

    // MARK: 6–9 — the SUSTAIN gate
    private struct Lane {
        var s = EuclideousSustainLaneState()
        var pool = [Note](repeating: (0, 0), count: 128); var count = 0
        var held = [Note](repeating: (0, 0), count: 128)
        mutating func setPool(_ notes: [Int]) { for (i, n) in notes.enumerated() { pool[i] = (n, 100) }; count = notes.count }
        var notes: [Int] { (0..<count).map { pool[$0].note } }
    }
    /// One window for one lane: observe, then offer `notes` as the pool after FREEZE, then gate.
    private func step(_ l: inout Lane, notes: [Int], on: Bool = true, mode: EuclideousSustainMode, down: Bool, seq: UInt32, cap: Int = 128) -> [Int] {
        euclideousSustainObserve(&l.s, on: on, mode: mode, pedalDown: down, downSeq: seq)
        l.setPool(notes)
        euclideousSustainGate(&l.s, on: on, mode: mode, pedalDown: down, downSeq: seq, pool: &l.pool, poolCount: &l.count, held: &l.held, heldBase: 0, cap: cap)
        return l.notes
    }
    private let C = [48, 52, 55], F = [53, 57, 60], G = [55, 59, 62], Am = [57, 60, 64]

    func testSustainOffOrPedalUpPassesThePoolUntouched() {
        var l = Lane()
        XCTAssertEqual(step(&l, notes: C, on: false, mode: .keep, down: true, seq: 1), C)
        XCTAssertEqual(step(&l, notes: F, on: true, mode: .keep, down: false, seq: 1), F)
        XCTAssertEqual(step(&l, notes: G, on: true, mode: .stack, down: false, seq: 1), G)
    }
    func testKeepHoldsTheCopyThroughEveryChangeAndRejoinsOnTheUpEdge() {
        var l = Lane()
        _ = step(&l, notes: C, mode: .keep, down: false, seq: 0)                 // first window: nothing pressed
        XCTAssertEqual(step(&l, notes: C, mode: .keep, down: true, seq: 1), C, "the down edge takes the pool as it is")
        XCTAssertEqual(step(&l, notes: F, mode: .keep, down: true, seq: 1), C, "…and ignores every change")
        XCTAssertEqual(step(&l, notes: G, mode: .keep, down: true, seq: 1), C)
        XCTAssertEqual(step(&l, notes: G, mode: .keep, down: false, seq: 1), G, "the up edge: the current pool")
        XCTAssertEqual(step(&l, notes: Am, mode: .keep, down: false, seq: 1), Am)
    }
    func testStackIsTheUnionAscendingAndNothingLeaves() {
        var l = Lane()
        _ = step(&l, notes: C, mode: .stack, down: false, seq: 0)
        XCTAssertEqual(step(&l, notes: C, mode: .stack, down: true, seq: 1), C)
        XCTAssertEqual(step(&l, notes: F, mode: .stack, down: true, seq: 1), [48, 52, 53, 55, 57, 60], "C E G + F A C: C E F G A (octaves are distinct notes here, as pitches)")
        XCTAssertEqual(step(&l, notes: [], mode: .stack, down: true, seq: 1), [48, 52, 53, 55, 57, 60], "a note released from the pool is not lost")
        XCTAssertEqual(step(&l, notes: G, mode: .stack, down: true, seq: 1), [48, 52, 53, 55, 57, 59, 60, 62])
        XCTAssertEqual(step(&l, notes: Am, mode: .stack, down: false, seq: 1), Am, "up edge: the current pool")
    }
    func testStackDropsTheNotesAddedLongestAgoFirstWhenTheUnionPassesTheCap() {
        var l = Lane()
        _ = step(&l, notes: [60], mode: .stack, down: false, seq: 0, cap: 4)
        _ = step(&l, notes: [60, 62], mode: .stack, down: true, seq: 1, cap: 4)                   // seed: 60 (oldest), 62
        XCTAssertEqual(step(&l, notes: [64, 65], mode: .stack, down: true, seq: 1, cap: 4), [60, 62, 64, 65], "at the cap")
        XCTAssertEqual(step(&l, notes: [67], mode: .stack, down: true, seq: 1, cap: 4), [62, 64, 65, 67], "60 was added longest ago and leaves")
        XCTAssertEqual(step(&l, notes: [69, 71], mode: .stack, down: true, seq: 1, cap: 4), [65, 67, 69, 71], "62 then 64 leave")
        XCTAssertEqual(step(&l, notes: [65], mode: .stack, down: true, seq: 1, cap: 4), [65, 67, 69, 71], "a note already held is not added again and does not refresh its age")
        XCTAssertEqual(step(&l, notes: [72], mode: .stack, down: true, seq: 1, cap: 4), [67, 69, 71, 72], "…so 65 is the oldest")
        // cap 1: the newest alone
        var one = Lane()
        _ = step(&one, notes: [60], mode: .stack, down: false, seq: 0, cap: 1)
        _ = step(&one, notes: [60], mode: .stack, down: true, seq: 1, cap: 1)
        XCTAssertEqual(step(&one, notes: [64], mode: .stack, down: true, seq: 1, cap: 1), [64])
    }
    func testSwitchingSustainOnWhileThePedalIsDownWaitsForTheNextEdge() {
        var l = Lane()
        _ = step(&l, notes: C, on: false, mode: .keep, down: true, seq: 1)               // pedal already down, SUSTAIN off
        XCTAssertEqual(step(&l, notes: F, on: true, mode: .keep, down: true, seq: 1), F, "switched on mid-press: the pool passes")
        XCTAssertEqual(step(&l, notes: G, on: true, mode: .keep, down: true, seq: 1), G)
        _ = step(&l, notes: G, on: true, mode: .keep, down: false, seq: 1)               // released
        XCTAssertEqual(step(&l, notes: G, on: true, mode: .keep, down: true, seq: 2), G, "the next down edge engages")
        XCTAssertEqual(step(&l, notes: Am, on: true, mode: .keep, down: true, seq: 2), G)
    }
    func testSwitchingSustainOffOrChangingModeWhileDownIsAnUpEdge() {
        var l = Lane()
        _ = step(&l, notes: C, mode: .keep, down: false, seq: 0)
        _ = step(&l, notes: C, mode: .keep, down: true, seq: 1)
        XCTAssertEqual(step(&l, notes: F, mode: .keep, down: true, seq: 1), C)
        XCTAssertEqual(step(&l, notes: G, on: false, mode: .keep, down: true, seq: 1), G, "off while down: the current pool at once")
        XCTAssertEqual(step(&l, notes: Am, on: true, mode: .keep, down: true, seq: 1), Am, "…and back on while down waits for the next edge")
        _ = step(&l, notes: Am, mode: .keep, down: false, seq: 1); _ = step(&l, notes: Am, mode: .keep, down: true, seq: 2)
        XCTAssertEqual(step(&l, notes: F, mode: .keep, down: true, seq: 2), Am, "KEEP engaged again")
        XCTAssertEqual(step(&l, notes: G, mode: .stack, down: true, seq: 2), G, "KEEP → STACK while down: the current pool (as an up edge)")
        XCTAssertEqual(step(&l, notes: C, mode: .stack, down: true, seq: 2), C, "…STACK is not engaged until the next edge")
    }
    func testAPressAndReleaseInsideOneWindowIsNoEdgeForALaneThatNeverSawItDownAndARepressReEngages() {
        var l = Lane()
        _ = step(&l, notes: C, mode: .keep, down: false, seq: 0)
        XCTAssertEqual(step(&l, notes: F, mode: .keep, down: false, seq: 1), F, "down and up between two looks: the pedal is up now")
        _ = step(&l, notes: C, mode: .keep, down: true, seq: 2)
        XCTAssertEqual(step(&l, notes: F, mode: .keep, down: true, seq: 2), C)
        XCTAssertEqual(step(&l, notes: G, mode: .keep, down: true, seq: 3), G, "released and pressed again inside one window: a new edge takes the pool now")
        XCTAssertEqual(step(&l, notes: Am, mode: .keep, down: true, seq: 3), G)
    }
    func testKeepIsHoldingOnlyWhenOnKeepDownAndTaken() {
        var s = EuclideousSustainLaneState(); s.engaged = true
        XCTAssertTrue(euclideousSustainKeepIsHolding(s, on: true, mode: .keep, pedalDown: true))
        XCTAssertFalse(euclideousSustainKeepIsHolding(s, on: true, mode: .stack, pedalDown: true))
        XCTAssertFalse(euclideousSustainKeepIsHolding(s, on: false, mode: .keep, pedalDown: true))
        XCTAssertFalse(euclideousSustainKeepIsHolding(s, on: true, mode: .keep, pedalDown: false))
        s.engaged = false; XCTAssertFalse(euclideousSustainKeepIsHolding(s, on: true, mode: .keep, pedalDown: true))
    }

    // MARK: 11 — the rank chip
    func testReceivedRanksAreBrightAndOctaveCopiesDark() {
        let chips = euclideousRankChips(sortedPool: [48, 52, 55], litMask: 0b0000_0100) { "n\($0)" }
        XCTAssertEqual(chips.map { $0.received }, [true, true, true, false, false, false, false, false])
        XCTAssertEqual(chips.map { $0.name }, ["n48", "n52", "n55", "n60", "n64", "n67", "n72", "n76"], "ranks beyond the pool are octave copies of it")
        XCTAssertEqual(chips.map { $0.lit }, [false, false, true, false, false, false, false, false])
        XCTAssertTrue(chips.allSatisfy { $0.cornerNumber && !$0.empty })
        XCTAssertEqual(chips.map { $0.rank }, Array(1...8))
    }
    func testAnEmptyPoolTakesTheCopyLookWithTheRankNumberInTheCentreAndNoCornerNumber() {
        let chips = euclideousRankChips(sortedPool: [], litMask: 0xFF) { "x\($0)" }
        XCTAssertTrue(chips.allSatisfy { $0.empty && !$0.received && !$0.cornerNumber })
        XCTAssertEqual(chips.map { $0.name }, (1...8).map(String.init))
    }
    func testAPoolOfMoreThanEightShowsTheEightLowest() {
        let pool = Array(40..<52)
        let chips = euclideousRankChips(sortedPool: pool, litMask: 0) { String($0) }
        XCTAssertEqual(chips.map { $0.name }, (40..<48).map(String.init)); XCTAssertTrue(chips.allSatisfy { $0.received })
    }
    func testTopAndTopTwoCarryNoRankNumber() {
        let top = EuclideousRankChipSpec(rank: 0, topKind: 2, received: true, lit: false, empty: false, name: "C4", cornerNumber: false)
        XCTAssertFalse(top.cornerNumber)
        XCTAssertEqual(euclideousRankChip(rank: 3, name: nil, received: false, lit: false, empty: false).name, "\u{2013}", "no note at the rank: an en dash")
    }
    func testPoolRankNoteMatchesTheExtendedPoolAndThePlayedMaskFindsTheRanks() {
        for n in 1...9 {
            let raw = (0..<n).map { 40 + $0 * 3 }
            let slice = raw.map { (note: $0, vel: UInt8(100)) }[0..<n]
            let extended = euclideousGlobalPoolExtended(sortedRaw: raw)
            for r in 1...8 { XCTAssertEqual(euclideousPoolRankNote(slice, rank: r), extended[r - 1], "pool of \(n), rank \(r)") }
        }
        XCTAssertNil(euclideousPoolRankNote([], rank: 1))
        let pool = [(note: 48, vel: UInt8(100)), (note: 52, vel: UInt8(100)), (note: 55, vel: UInt8(100))][0..<3]
        XCTAssertEqual(euclideousPlayedRankMask(pitches: [52, 60, 99], count: 3, pool: pool), 0b0000_1010, "52 is rank 2, 60 is rank 4 (an octave copy), 99 is no rank")
        XCTAssertEqual(euclideousPlayedRankMask(pitches: [48], count: 0, pool: pool), 0)
        XCTAssertEqual(euclideousPlayedRankMask(pitches: [48], count: 1, pool: []), 0)
    }
    func testTheCornerNumberFitsWhereItDoesNotCollideWithTheLabel() {
        let widest = euclideousRankChipWidestName
        XCTAssertEqual(euclideousRankChipLabelWidth("C4"), 9 + 6); XCTAssertEqual(euclideousRankChipLabelWidth(widest), 30)
        // the grid's rows: ≈ 25 tall — the column must widen
        XCTAssertFalse(euclideousRankChipFitsCorner(width: 30, height: 25, name: widest), "today's 30 pt label column cannot hold it")
        XCTAssertFalse(euclideousRankChipFitsCorner(width: euclideousRankChipMinWidth() - 1, height: 25, name: widest))
        XCTAssertTrue(euclideousRankChipFitsCorner(width: euclideousRankChipMinWidth(), height: 25, name: widest))
        XCTAssertEqual(euclideousRankChipMinWidth(), 48)
        // NOW's chips (≈ 41 pt tall, ≈ 30 wide) and the NOTES keys (27.85 × 82–103): tall enough that the label clears the corner number above it
        XCTAssertTrue(euclideousRankChipFitsCorner(width: 30, height: 42, name: widest), "NOW at the reference body (42 tall): the label clears the number above it")
        XCTAssertTrue(euclideousRankChipFitsCorner(width: 30, height: 41, name: widest))
        XCTAssertFalse(euclideousRankChipFitsCorner(width: 30, height: 32, name: widest), "NOW on a short body: the number is dropped, the label is never shrunk")
        XCTAssertTrue(euclideousRankChipFitsCorner(width: 27.85, height: 82, name: widest))
        XCTAssertTrue(euclideousRankChipFitsCorner(width: 27.85, height: 103, name: widest))
    }

    // MARK: 12 — the picker
    func testThePickerStepsOneToFourAndWraps() {
        XCTAssertEqual((0..<5).reduce((0, [Int]())) { acc, _ in (euclideousPickedLaneNext(acc.0), acc.1 + [acc.0]) }.1, [0, 1, 2, 3, 0])
        XCTAssertEqual(euclideousPickedLaneNext(3), 0); XCTAssertEqual(euclideousPickedLaneNext(-1), 0); XCTAssertEqual(euclideousPickedLaneNext(9), 2)
    }

    // MARK: 13 — the tab's layout
    func testPoolTabHeightsAtTheReferenceCardsAndShorterOnes() {
        for h in [229.0, 229.67] {
            let l = euclideousPoolTabLayout(contentAreaH: CGFloat(h))
            XCTAssertTrue(l.fits)
            XCTAssertEqual(l.heights.reduce(0, +) + 4 * l.gap, 226, accuracy: 0.5, "body \(h): the five rows and four gaps")
            XCTAssertTrue(l.heights.allSatisfy { $0 >= 30 }, "no row under 30 pt")
            XCTAssertEqual(l.sourcesH, 30, "SOURCES is 30 (its toggles 26)")
            XCTAssertLessThanOrEqual(l.nowH, 44)
        }
        XCTAssertEqual(euclideousPoolTabLayout(contentAreaH: 229).heights, [42, 30, 42, 42, 41])
        let tall = euclideousPoolTabLayout(contentAreaH: 400); XCTAssertEqual(tall.heights, [44, 30, 44, 44, 44], "ideals at most")
        let mini = euclideousPoolTabLayout(contentAreaH: 193); XCTAssertTrue(mini.fits); XCTAssertTrue(mini.heights.allSatisfy { $0 >= 30 })
        let short = euclideousPoolTabLayout(contentAreaH: 150); XCTAssertFalse(short.fits); XCTAssertEqual(short.heights, [30, 30, 30, 30, 30], "never squeezed under the floor")
        XCTAssertTrue(euclideousPoolTabLayout(contentAreaH: 182).fits, "five 30 pt rows and four gaps = 182")
    }

    // MARK: 2.6 / §9
    func testThePoolGlyphLightsForDelayHoldSustainOrAnySourceOff() {
        var l = EuclidLine(); XCTAssertFalse(euclideousPoolGlyphLit(l))
        l.chordDelay = 1; XCTAssertTrue(euclideousPoolGlyphLit(l)); l.chordDelay = 0
        l.poolHold = 2; XCTAssertTrue(euclideousPoolGlyphLit(l)); l.poolHold = 0
        l.poolSustainOn = true; XCTAssertTrue(euclideousPoolGlyphLit(l)); l.poolSustainOn = false
        XCTAssertFalse(euclideousPoolGlyphLit(l), "a remembered mode alone lights nothing")
        l.setPoolSrc(1, false); XCTAssertTrue(euclideousPoolGlyphLit(l)); l.setPoolSrc(1, true); XCTAssertFalse(euclideousPoolGlyphLit(l))
        XCTAssertTrue(euclideousTabGlyph(tab: .pool, line: { var x = EuclidLine(); x.poolSustainOn = true; return x }(), lane: 0).on)
    }
    func testTheSpokenWords() {
        XCTAssertEqual(euclideousPoolNowSpoken(names: []), "empty"); XCTAssertEqual(euclideousPoolNowSpoken(names: ["C 3", "E 3"]), "C 3, E 3")
        XCTAssertEqual(euclideousPoolSourceNames, ["MIDI in", "Chords", "Pick", "Key"])
        XCTAssertEqual(euclideousPoolSourceValue(on: true, panelOn: true), "on"); XCTAssertEqual(euclideousPoolSourceValue(on: false, panelOn: true), "off")
        XCTAssertEqual(euclideousPoolSourceValue(on: true, panelOn: false), "on, off in sources")
        XCTAssertEqual(euclideousPoolPedalSpoken(down: true), "down"); XCTAssertEqual(euclideousPoolPedalSpoken(down: false), "up")
        XCTAssertEqual(euclideousRankChipGridSpoken(rank: 3, note: "E flat 3"), "Rank 3, E flat 3"); XCTAssertEqual(euclideousPickedLaneSpoken(1), "lane 2")
    }
}
