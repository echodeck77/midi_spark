import XCTest

// Tests for the pure BUILD decision cores extracted from BuildPage (Paul 2026-08-16): scene composition and the
// staging-selection reconcile. BuildPage itself is a SwiftUI extension outside the test target; these functions are
// the first BUILD logic under automated coverage. Two of this session's confirmed bugs (C1 deselect resurrection,
// and the scene-composition rules that carry the mute/rung/least-occupied behaviour) are locked here.
final class BuildSceneLogicTests: XCTestCase {

    private func grid(_ pairs: [(Int, Int, String)]) -> [[String?]] {
        var g: [[String?]] = Array(repeating: Array(repeating: nil, count: 8), count: 8)
        for (c, r, id) in pairs { g[c][r] = id }
        return g
    }
    private func colourIDsAt(_ s: SceneState, row: Int) -> [String?] { (0..<8).map { s.cellAt($0, row)?.colourID } }

    // MARK: reconcileStagingSel (bug C1)

    func testReconcilePreservesExplicitDeselect() {
        // A column deliberately silenced (−1) must STAY silent, even though its cell is stocked — the old code
        // resurrected it to the topmost stocked cell.
        let cells = grid([(0, 3, "gold"), (1, 3, "gold"), (2, 3, "gold")])
        let out = BuildSceneLogic.reconcileStagingSel([-1, 3, -1, -1, -1, -1, -1, -1], cells: cells)
        XCTAssertEqual(out[0], -1, "column 0 was explicitly deselected — it stays silent")
        XCTAssertEqual(out[1], 3, "column 1's valid pick survives")
        XCTAssertEqual(out[2], -1, "column 2 stays silent (was never asking for a fallback)")
    }

    func testReconcileFallsBackAPositivePickAtAnEmptyCell() {
        // A POSITIVE pick that now points at an empty cell falls back to the topmost stocked cell in that column.
        let cells = grid([(0, 5, "gold")])          // column 0 only holds a cell at row 5
        let out = BuildSceneLogic.reconcileStagingSel([2, -1, -1, -1, -1, -1, -1, -1], cells: cells)
        XCTAssertEqual(out[0], 5, "the invalid pick at row 2 falls back to the stocked row 5")
    }

    func testReconcileGivesMinusOneForAnEmptyColumn() {
        let out = BuildSceneLogic.reconcileStagingSel([4, 4, 4, 4, 4, 4, 4, 4], cells: grid([]))
        XCTAssertEqual(out, Array(repeating: -1, count: 8), "no stocked cell anywhere → every column resolves to silent")
    }

    // MARK: mutateChain (the MUTATE row action — value-only, guaranteed distinct + audible)

    func testMutateProducesADistinctAudibleValueVariant() {
        let base = [ProcessorSlot(type: .arp)]          // an arp has params whose nudge shifts the output
        let baseFP = Dice.fingerprint(base)
        var rng = DiceRNG(seed: 7)
        guard let mutated = BuildSceneLogic.mutateChain(base, avoid: [baseFP], &rng) else {
            return XCTFail("mutate should find a distinct, audible variant of an arp")
        }
        let fp = Dice.fingerprint(mutated)
        XCTAssertFalse(fp.isEmpty, "the variant is NOT silent")
        XCTAssertNotEqual(fp, baseFP, "the variant sounds DIFFERENT from the source")
        XCTAssertEqual(mutated.map(\.type), base.map(\.type), "value-only: the processor types are unchanged")
    }

    // Subsequent MUTATE hits must not converge: a variant is rejected if its fingerprint matches ANY avoided one (the
    // source plus every row already placed). Two mutations avoiding each other's output produce different fingerprints.
    func testMutateAvoidsAlreadyPresentSignatures() {
        let base = [ProcessorSlot(type: .arp)]
        var rng = DiceRNG(seed: 3)
        guard let first = BuildSceneLogic.mutateChain(base, avoid: [Dice.fingerprint(base)], &rng) else { return XCTFail("first mutate failed") }
        let firstFP = Dice.fingerprint(first)
        guard let second = BuildSceneLogic.mutateChain(base, avoid: [Dice.fingerprint(base), firstFP], &rng) else { return XCTFail("second mutate failed") }
        XCTAssertNotEqual(Dice.fingerprint(second), firstFP, "the second hit avoids the first's output — no repeat")
    }

    func testMutateReturnsNilForAnEmptyChain() {
        var rng = DiceRNG(seed: 1)
        XCTAssertNil(BuildSceneLogic.mutateChain([], avoid: [], &rng), "no slots → nothing to tweak")
    }

    // The richer fingerprint captures GATE (note duration) where the note+onset signature is blind to it.
    func testFingerprintCapturesGateWhereSignatureIsBlind() {
        var longGate = ProcessorSlot(type: .arp); longGate.params.gate = 0.9
        var shortGate = ProcessorSlot(type: .arp); shortGate.params.gate = 0.25
        XCTAssertEqual(Dice.signature([longGate]), Dice.signature([shortGate]), "note+onset signature ignores gate")
        XCTAssertNotEqual(Dice.fingerprint([longGate]), Dice.fingerprint([shortGate]), "the fingerprint sees the shorter note (its OFF moves)")
    }

    // MARK: composeScene

    func testNothingPlayingReturnsNil() {
        XCTAssertNil(BuildSceneLogic.composeScene(BuildSceneLogic.Input()), "no active voice → no scene")
    }

    func testPartHonoursSelectionAndIsSilentWhereDeselected() {
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true
        i.stagingCells = grid([(0, 2, "gold"), (1, 2, "gold"), (2, 2, "gold")])
        i.stagingSel = [2, -1, 2, -1, -1, -1, -1, -1]      // columns 0 and 2 play, column 1 silent
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 2)?.colourID, "gold")
        XCTAssertNil(s.cellAt(1, 2), "column 1 was deselected → no cell in the scene")
        XCTAssertEqual(s.cellAt(2, 2)?.colourID, "gold")
    }

    func testPerRowIOOverridesTheDefaultElseInherits() {
        // PER-ROW I/O (Paul 2026-08-18): row 1 carries its OWN door + emitter; row 4 inherits the part default.
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true
        i.stagingCells = grid([(0, 1, "gold"), (1, 4, "teal")])
        i.stagingSel = [1, 4, -1, -1, -1, -1, -1, -1]
        i.selReceiver = 0; i.partEmitters = [.a]                        // part DEFAULT: door R1 · emitter A
        i.rowReceiver = [0, 2, 0, 0, 0, 0, 0, 0]                        // row 1 → door R3
        i.rowEmitters = [[.a], [.c], [.a], [.a], [.a], [.a], [.a], [.a]] // row 1 → emitter C
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 1)?.inputReceiver, 2, "row 1 uses its OWN door")
        XCTAssertEqual(s.cellAt(0, 1)?.buses, [.c], "row 1 uses its OWN emitter")
        XCTAssertEqual(s.cellAt(1, 4)?.inputReceiver, 0, "row 4 inherits the part default door")
        XCTAssertEqual(s.cellAt(1, 4)?.buses, [.a], "row 4 inherits the part default emitters")
    }

    func testPieceDropsMutedAndInactiveRungCells() {
        var i = BuildSceneLogic.Input()
        i.performPlaying = true
        i.performCells = grid([(0, 0, "gold"), (1, 0, "gold"), (2, 0, "gold")])
        i.performMute = [1 * 8 + 0]                        // column 1 muted
        i.performActiveRung = { c, _ in c != 2 }           // column 2's rung inactive
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 0)?.colourID, "gold", "unmuted, active → plays")
        XCTAssertNil(s.cellAt(1, 0), "muted → dropped")
        XCTAssertNil(s.cellAt(2, 0), "inactive rung → dropped")
    }

    func testChainLandsOnAFullyEmptyRowRawAcrossAllColumns() {
        var i = BuildSceneLogic.Input()
        i.chainActive = true
        i.chainColourID = "cyan"
        i.chainMachine = []                                // raw passthrough
        let s = BuildSceneLogic.composeScene(i)!
        // the whole grid is empty → the chain takes row 0, every column
        XCTAssertEqual(colourIDsAt(s, row: 0), Array(repeating: "cyan", count: 8), "the chain plays raw on every column")
        XCTAssertEqual(s.cellAt(0, 0)?.processors, [], "explicit empty chain (born-audible passthrough), never nil")
    }

    func testChainFallsBackToTheLeastOccupiedRowWhenPieceIsFull() {
        var i = BuildSceneLogic.Input()
        i.chainActive = true
        i.chainColourID = "cyan"
        i.performPlaying = true
        // Fill EVERY row and column with the piece EXCEPT one gap at (7, row 4) — row 4 is the least-occupied.
        var cells: [[String?]] = Array(repeating: Array(repeating: "gold", count: 8), count: 8)
        cells[7][4] = nil
        i.performCells = cells
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(7, 4)?.colourID, "cyan", "the chain fills the one free cell on the least-occupied row")
        XCTAssertEqual(s.cellAt(0, 4)?.colourID, "gold", "the piece's own cells in that row are untouched")
    }

    func testPartAndPieceAndChainCoexist() {
        var i = BuildSceneLogic.Input()
        i.performPlaying = true; i.stagingPlaying = true; i.chainActive = true
        i.performCells = grid([(0, 0, "gold")])            // piece on row 0
        i.stagingCells = grid([(0, 3, "teal")]); i.stagingSel = [3, -1, -1, -1, -1, -1, -1, -1]   // part on row 3
        i.chainColourID = "cyan"                           // chain finds a free row (not 0 or 3)
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 0)?.colourID, "gold", "piece plays")
        XCTAssertEqual(s.cellAt(0, 3)?.colourID, "teal", "part plays alongside")
        let chainRow = (0..<8).first { r in r != 0 && r != 3 && s.cellAt(0, r)?.colourID == "cyan" }
        XCTAssertNotNil(chainRow, "the chain lands on some free row, coexisting with both")
    }
    // MARK: composeScene — the PER-PART CLOCK + PER-ROW LAP mapping (Input → SceneState.rowStepRate/rowLen/rowLane)

    func testPieceAppliesPerRowLengthEvenWhenRateIsDefault() {
        // BUG (Paul 2026-08-19): the piece's per-row LENGTH was set only inside `if let rr = performRate[r]`, so a
        // deployed part at the SCENE-DEFAULT rate (nil) silently lost its short loop — the common Stage-D case.
        var i = BuildSceneLogic.Input()
        i.performPlaying = true
        i.performCells = grid([(0, 2, "gold")])
        i.performActiveRung = { _, _ in true }
        i.performRate = Array(repeating: nil, count: 8)            // scene-default rate
        i.performLen = [nil, nil, 4, nil, nil, nil, nil, nil]      // row 2 loops 4 columns
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.rowLen?[2], 4, "a default-rate part still applies its short loop length")
    }

    func testStagingClaimsRowSoThePieceNeverClobbersItsClock() {
        // Staging OWNS a row it occupies even when its rate is the scene default (nil) — the piece must not override it.
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true; i.performPlaying = true
        i.stagingCells = grid([(0, 2, "gold")]); i.stagingSel = [2, -1, -1, -1, -1, -1, -1, -1]
        i.stagingRate = nil; i.stagingLen = 4                      // staging: default rate, short length
        i.performCells = grid([(1, 2, "teal")]); i.performActiveRung = { _, _ in true }   // piece also on row 2
        i.performRate = [nil, nil, .r2_1, nil, nil, nil, nil, nil] // piece row-2 rate = 2/1
        i.performLen = [nil, nil, 8, nil, nil, nil, nil, nil]
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertNil(s.rowStepRate![2], "staging owns row 2 with its DEFAULT rate — the piece's 2/1 must not clobber it")
        XCTAssertEqual(s.rowLen![2], 4, "staging's short length wins, not the piece's 8")
    }

    func testUniformStagingLeavesPerRowClockNil() {
        // No custom rate/length ⇒ no per-row clock at all → the Router keeps its uniform fast path.
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true
        i.stagingCells = grid([(0, 0, "gold")]); i.stagingSel = [0, -1, -1, -1, -1, -1, -1, -1]
        i.stagingRate = nil; i.stagingLen = nil
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertNil(s.rowStepRate, "uniform staging → no per-row clock (fast path preserved)")
        XCTAssertNil(s.rowLen)
    }

    func testRowLaneStagingWinsAndAMutedPieceCellContributesNoLane() {
        // A muted piece cell must NOT contribute its lane (mirrors the cell-placement guard); staging wins a shared row.
        var i = BuildSceneLogic.Input()
        i.performPlaying = true; i.stagingPlaying = true
        i.performCells = grid([(0, 2, "gold"), (0, 5, "gold")])
        i.performMute = [0 * 8 + 5]                                // the row-5 piece cell is muted
        i.performActiveRung = { _, _ in true }
        i.performLane = 0b1
        i.stagingCells = grid([(1, 2, "teal")]); i.stagingSel = [-1, 2, -1, -1, -1, -1, -1, -1]  // staging on row 2
        i.stagingLane = 0b10
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.rowLane?[5] ?? 0, 0, "a muted piece cell contributes no lane")
        XCTAssertEqual(s.rowLane?[2], 0b10, "staging's lane wins the shared row over the piece's")
    }

    // Regression (Paul 2026-08-16): MUTATE on a EUCLID gave only ONE variant then went dead — its euclidPulses/Steps/Rot
    // params were advertised but NOT wired into processorValues/applyProcessorValues, so the only working tweak was the
    // bypass toggle. With them wired, repeated MUTATE yields many distinct variants.
    func testMutateEuclidYieldsManyDistinctVariants() {
        var eu = ProcessorSlot(type: .euclid); eu.params.euclidPulses = 5; eu.params.euclidSteps = 8
        let base = [eu]
        var avoid = [Dice.fingerprint(base)]
        var rng = DiceRNG(seed: 5)
        var n = 0
        for _ in 0..<8 { guard let m = BuildSceneLogic.mutateChain(base, avoid: avoid, &rng) else { break }; avoid.append(Dice.fingerprint(m)); n += 1 }
        XCTAssertGreaterThanOrEqual(n, 5, "euclid must yield many distinct variants (was 1 — the unwired-param bug)")
    }

    // composeScene precedence: the PART audition "sits in front" of the PIECE on a shared (col,row), carrying the part's
    // I/O. Every other composeScene test puts them on different rows, so this collision path was untested. (Paul 2026-08-19)
    func testPartAuditionSitsInFrontOfThePieceOnASlotCollision() {
        var i = BuildSceneLogic.Input()
        i.performPlaying = true; i.stagingPlaying = true
        i.performActiveRung = { _, _ in true }
        i.performCells = grid([(0, 2, "gold")])            // the PIECE occupies (0,2)
        i.performEmit = Array(repeating: [.a], count: 8)   // piece row 2 → emitter A
        i.stagingCells = grid([(0, 2, "teal")])            // the PART occupies the SAME slot
        i.stagingSel = [2, -1, -1, -1, -1, -1, -1, -1]
        i.selReceiver = 0; i.partEmitters = [.b]           // part default → emitter B
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 2)?.colourID, "teal", "the part/audition wins the shared slot (sits in front)")
        XCTAssertEqual(s.cellAt(0, 2)?.buses, [.b], "and the surviving cell carries the PART's I/O, not the piece's")
    }

    // mutateNudge: each control KIND stays in-range and actually moves. Only covered transitively before. (Paul 2026-08-19)
    func testMutateNudgeStaysInRangePerKind() {
        var rng = DiceRNG(seed: 3)
        let cont = MacroControlParam(key: "c", label: "C", kind: .continuous(lo: 0, hi: 1))
        for _ in 0..<12 {
            let v = BuildSceneLogic.mutateNudge(cont, 0.5, &rng)
            XCTAssertTrue(v >= 0 && v <= 1, "continuous stays in [0,1]"); XCTAssertNotEqual(v, 0.5, "and moves")
        }
        let tog = MacroControlParam(key: "t", label: "T", kind: .toggle)
        XCTAssertEqual(BuildSceneLogic.mutateNudge(tog, 1, &rng), 0, "toggle flips 1→0")
        XCTAssertEqual(BuildSceneLogic.mutateNudge(tog, 0, &rng), 1, "toggle flips 0→1")
        let step = MacroControlParam(key: "s", label: "S", kind: .stepper(lo: 2, hi: 5))
        for _ in 0..<12 {
            let v = BuildSceneLogic.mutateNudge(step, 5, &rng)                 // at the ceiling
            XCTAssertTrue(v >= 2 && v <= 5, "stepper clamps to [2,5]")
        }
        let mask = MacroControlParam(key: "m", label: "M", kind: .mask(bits: 4))
        for _ in 0..<12 {
            let out = Int(BuildSceneLogic.mutateNudge(mask, 0b0101, &rng).rounded())
            XCTAssertEqual((out ^ 0b0101).nonzeroBitCount, 1, "mask flips exactly one bit")
        }
        let opt = MacroControlParam(key: "o", label: "O", kind: .option(["a", "b", "c"]))
        for _ in 0..<12 {
            let v = Int(BuildSceneLogic.mutateNudge(opt, 1, &rng).rounded())
            XCTAssertTrue(v >= 0 && v <= 2 && v != 1, "option steps to a DIFFERENT in-range index")
        }
    }
}
