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
    // C5 FIX (Paul 2026-08-27): a RAGGED column (< 8 rows, from a malformed/older decode) must not trap — the row
    // subscript + the fallback scan were bounded to 8, not the column's actual length.
    func testReconcileToleratesRaggedColumns() {
        var cells: [[String?]] = [["gold", nil, nil], [], ["x", "y"]]                 // columns of length 3, 0, 2
        while cells.count < 8 { cells.append([]) }                                   // the rest empty (length 0)
        let out = BuildSceneLogic.reconcileStagingSel([5, 0, 1, -1, 0, 0, 0, 0], cells: cells)   // picks past several columns' lengths
        XCTAssertEqual(out.count, 8)
        XCTAssertEqual(out[0], 0, "col 0 pick at row 5 (> len 3) falls back to the stocked row 0")
        XCTAssertEqual(out[1], -1, "col 1 is empty → silent, no trap")
        XCTAssertEqual(out[2], 1, "col 2 pick at row 1 is valid")
        XCTAssertEqual(out[4], -1, "col 4 (empty) pick falls back to silent, no trap")
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

    // MARK: PART AUTOMATION — the AUTO lanes (Paul 2026-09-02). A colour's ACTIVE lane ramps a param across its EXTENT
    // of part cells (sub-range low→high, column→row order), baked per-cell at build via applyAuto.

    func testAutoLaneRampsParamAcrossExtent() {
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true
        i.stagingCells = grid([(0, 2, "gold"), (1, 2, "gold"), (2, 2, "gold")])
        i.stagingSel = [2, 2, 2, -1, -1, -1, -1, -1]          // three gold cells play (rung 2)
        var base = ProcessorSlot(type: .arp); base.params.gate = 0.5   // a distinct base gate to override
        i.rowChain = (0..<8).map { $0 == 2 ? [base] : [] }
        // AUTO 1 on slot 0's GATE (param "" ⇒ the pre-mapped default = gate), extent = (0,2) and (2,2)
        let e0 = 0 * Snap.rows + 2, e2 = 2 * Snap.rows + 2
        i.partAuto = ["gold": PartAutoColour(activeLane: 0, lanes: [AutoLane(slot: 0, param: "", cells: [e0, e2])])]
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 2)?.processors?.first?.params.gate ?? -1, 0.3, accuracy: 1e-6, "rank 0 → the sub-range LOW")
        XCTAssertEqual(s.cellAt(2, 2)?.processors?.first?.params.gate ?? -1, 1.0, accuracy: 1e-6, "rank 1 → the sub-range HIGH")
        XCTAssertEqual(s.cellAt(1, 2)?.processors?.first?.params.gate ?? -1, 0.5, accuracy: 1e-6, "outside the extent → the base value, untouched")
    }

    func testAutoNoneLaneIsByteIdentical() {
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true
        i.stagingCells = grid([(0, 2, "gold")])
        i.stagingSel = [2, -1, -1, -1, -1, -1, -1, -1]
        var base = ProcessorSlot(type: .arp); base.params.gate = 0.5
        i.rowChain = (0..<8).map { $0 == 2 ? [base] : [] }
        // NONE (activeLane −1) even though a lane HAS an extent → nothing bakes (byte-identical)
        i.partAuto = ["gold": PartAutoColour(activeLane: -1, lanes: [AutoLane(slot: 0, param: "gate", cells: [0 * Snap.rows + 2])])]
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 2)?.processors?.first?.params.gate ?? -1, 0.5, accuracy: 1e-6, "NONE → the base value untouched")
    }

    func testAutoSubRangeAndRampEndpoints() {
        XCTAssertEqual(BuildSceneLogic.autoSubRange("gate", .continuous(lo: 0.05, hi: 1)).lo, 0.3, accuracy: 1e-9)
        XCTAssertEqual(BuildSceneLogic.autoSubRange("gate", .continuous(lo: 0.05, hi: 1)).hi, 1.0, accuracy: 1e-9)
        XCTAssertEqual(BuildSceneLogic.autoRamp(0.3, 1.0, rank: 0, count: 1), 1.0, accuracy: 1e-9, "a single cell = the top (full effect)")
        XCTAssertEqual(BuildSceneLogic.autoRamp(0.3, 1.0, rank: 0, count: 3), 0.3, accuracy: 1e-9)
        XCTAssertEqual(BuildSceneLogic.autoRamp(0.3, 1.0, rank: 1, count: 3), 0.65, accuracy: 1e-9)
        XCTAssertEqual(BuildSceneLogic.autoRamp(0.3, 1.0, rank: 2, count: 3), 1.0, accuracy: 1e-9)
        XCTAssertEqual(BuildSceneLogic.autoResolvedParamKey(.arp, laneParam: ""), "gate", "the pre-mapped useful default")
        XCTAssertEqual(BuildSceneLogic.autoResolvedParamKey(.strum, laneParam: ""), "spread")
    }

    func testPartAutoDocumentRoundTrips() throws {
        var d = PluginState.makeInit()
        d.partAuto = ["gold": PartAutoColour(activeLane: 2, lanes: [AutoLane(slot: 1, param: "spread", cells: [3, 19, 35])])]
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.partAuto?["gold"]?.activeLane, 2)
        XCTAssertEqual(back.partAuto?["gold"]?.lanes.first?.param, "spread")
        XCTAssertEqual(back.partAuto?["gold"]?.lanes.first?.cells, [3, 19, 35])
    }

    func testPartHonoursSelectionAndIsSilentWhereDeselected() {
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true
        i.stagingCells = grid([(0, 2, "gold"), (1, 2, "gold"), (2, 2, "gold")])
        i.stagingSel = [2, -1, 2, -1, -1, -1, -1, -1]      // columns 0 and 2 play, column 1 silent
        i.rowChain = (0..<8).map { $0 == 2 ? [ProcessorSlot(type: .arp)] : [] }   // gold has a machine → it composes (Paul 2026-08-26: a machine-less part cell is silent)
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 2)?.colourID, "gold")
        XCTAssertNil(s.cellAt(1, 2), "column 1 was deselected → no cell in the scene")
        XCTAssertEqual(s.cellAt(2, 2)?.colourID, "gold")
    }

    // THE PLAY GRID (Paul 2026-08-29): each STARTED column is an INDEPENDENT, CONTINUOUS voice. It composes at engine
    // (COLUMN 0, row = the play-column index) and that row loops COLUMN 0 — no time axis, so it plays continuously (not
    // only when a playhead crosses). Each carries the I/O it was FERRIED WITH (playColRecv/playColEmit).
    func testPlayGridComposesStartedColumnsAsContinuousVoices() throws {
        var i = BuildSceneLogic.Input()
        i.playPlaying = true
        i.playCells = grid([(0, 1, "b1"), (1, 3, "b2"), (2, 0, "b3")])
        i.playSel = [1, 3, 0, -1, -1, -1, -1, -1]
        i.playColChain = (0..<8).map { c in c == 0 ? [ProcessorSlot(type: .arp)] : [] }
        i.playColOn = [true, true, false, false, false, false, false, false]   // col 2 is populated but NOT started
        i.playColRecv = [2, 1, 0, 0, 0, 0, 0, 0]                                 // per-column doors, derived from the ferry source
        i.playColEmit = [[.b], [.c, .d], [.a], [.a], [.a], [.a], [.a], [.a]]
        let s = BuildSceneLogic.composeScene(i)!
        let base = Snap.playLayerRowBase                                // the hidden play layer starts at engine row 8
        // play column 0 → engine (col 0, row 8) — the HIDDEN play layer, DISJOINT from the part's rows 0–7
        XCTAssertEqual(s.cellAt(0, base + 0)?.colourID, "b1", "col 0's cell composes at engine row 8")
        XCTAssertEqual(s.cellAt(0, base + 0)?.processors?.first?.type, .arp, "with its own machine")
        XCTAssertEqual(s.cellAt(0, base + 0)?.buses, [.b], "its ferried emitter")
        XCTAssertEqual(s.cellAt(0, base + 0)?.inputReceiver, 2, "its ferried door")
        // play column 1 → engine (col 0, row 9)
        XCTAssertEqual(s.cellAt(0, base + 1)?.colourID, "b2", "col 1's cell composes at engine row 9 (empty chain = passthrough)")
        XCTAssertEqual(s.cellAt(0, base + 1)?.buses, [.c, .d], "carries its own ferried emitters")
        XCTAssertNil(s.cellAt(0, base + 2), "col 2 is populated but NOT started → its engine row is empty")
        XCTAssertNil(s.cellAt(0, 0), "the visible rows 0–7 stay free for the part (no play cell there)")
        // CONTINUOUS: the started columns' play-layer rows loop column 0; the rest don't loop.
        let lane = try XCTUnwrap(s.rowLane, "the play grid sets a per-row lane")
        XCTAssertEqual(lane[base + 0], 0b1, "row 8 loops column 0 → continuous")
        XCTAssertEqual(lane[base + 1], 0b1, "row 9 loops column 0 → continuous")
        XCTAssertEqual(lane[base + 2], 0, "col 2 not started → its row doesn't loop")
    }
    func testPlayColumnMultiStepPassLaysStepsAndLoopsItsLength() throws {
        // MULTI-STEP PASS (Paul 2026-08-30, "flatten the part"): a play column with len > 1 lays its step colours across
        // cols 0..len-1 of the play-layer row, SWEPT (no col-0 pin) and looped by rowLen. len ≤ 1 stays the pinned single cell.
        var i = BuildSceneLogic.Input()
        i.playPlaying = true
        i.playColOn = [true, true, false, false, false, false, false, false]
        i.playColEmit = [[.a], [.b], [.a], [.a], [.a], [.a], [.a], [.a]]
        i.playColRecv = [0, 0, 0, 0, 0, 0, 0, 0]
        // column 0 = a 3-step pass (step 1 is a REST); column 1 = a single continuous cell (len defaults to 1).
        i.playColLen = [3, 1, 1, 1, 1, 1, 1, 1]
        i.playColSteps = [["a", nil, "c"], [], [], [], [], [], [], []]
        i.playColStepChain = [[[ProcessorSlot(type: .arp)], [], [ProcessorSlot(type: .harmonize)]], [], [], [], [], [], [], []]
        i.playColStepEmit = [[[.a], [], [.c]], [], [], [], [], [], [], []]   // PER-STEP I/O: step 0 → A, step 2 → C
        i.playColStepRecv = [[0, 0, 2], [], [], [], [], [], [], []]          // step 2 reads door C (2)
        i.playCells = grid([(1, 0, "solo")]); i.playSel = [0, 0, -1, -1, -1, -1, -1, -1]   // col 1's single cell
        let s = BuildSceneLogic.composeScene(i)!
        let base = Snap.playLayerRowBase
        XCTAssertEqual(s.cellAt(0, base)?.colourID, "a", "step 0 at (col 0, play row)")
        XCTAssertNil(s.cellAt(1, base), "step 1 is a REST → no cell")
        XCTAssertEqual(s.cellAt(2, base)?.colourID, "c", "step 2 at (col 2, play row)")
        XCTAssertEqual(s.cellAt(2, base)?.processors?.first?.type, .harmonize, "each step carries its own resolved chain")
        XCTAssertEqual(s.cellAt(0, base)?.buses, [.a], "step 0 keeps its OWN emitter (A)")
        XCTAssertEqual(s.cellAt(2, base)?.buses, [.c], "step 2 keeps its OWN emitter (C) — per-step I/O")
        XCTAssertEqual(s.cellAt(2, base)?.inputReceiver, 2, "step 2 keeps its OWN door (C)")
        let len = try XCTUnwrap(s.rowLen, "the play layer carries a per-row length")
        XCTAssertEqual(len[base], 3, "the multi-step play row loops its pass length (3)")
        let lane = try XCTUnwrap(s.rowLane, "the play grid sets a per-row lane")
        XCTAssertEqual(lane[base], 0, "multi-step SWEEPS 0..len-1 → no col-0 pin")
        // column 1 stays the pinned single cell, byte-identical to today.
        XCTAssertEqual(s.cellAt(0, base + 1)?.colourID, "solo", "the single-cell column is unchanged")
        XCTAssertEqual(lane[base + 1], 0b1, "single cell → pinned to col 0 (continuous)")
        XCTAssertNil(len[base + 1], "single cell sets no per-row length")
    }
    // P1 (2026-08-30): when NO row is fully empty, the chain audition (PLAY THIS MIDI CHAIN) lays across the
    // least-occupied row's FREE columns and must SWEEP. The old code unconditionally pinned col 0 of that row —
    // which, when col 0 already holds another voice's cell, looped THAT cell and left the audition silent.
    func testChainAuditionFallbackSweepsInsteadOfPinningANonChainColumn() throws {
        var i = BuildSceneLogic.Input()
        i.performPlaying = true
        i.performCells = grid((0..<8).map { ($0, $0, "p\($0)") })   // a DIAGONAL → every row occupied (occ 1), none full, col 0 held by "p0"
        i.chainActive = true; i.chainColourID = "aud"; i.chainMachine = []
        let (sceneOpt, auditionRow) = BuildSceneLogic.composeSceneMeta(i)
        let s = try XCTUnwrap(sceneOpt)
        XCTAssertEqual(auditionRow, 0, "the least-occupied row (all tie → row 0)")
        XCTAssertEqual(s.cellAt(0, 0)?.colourID, "p0", "col 0 stays the PIECE's cell")
        XCTAssertEqual(s.cellAt(1, 0)?.colourID, "aud", "the chain lays across the row's FREE columns")
        XCTAssertEqual(try XCTUnwrap(s.rowLane)[0], 0, "P1: the fallback row is NOT pinned to col 0 → it sweeps (else the pin loops p0 and the audition is silent)")

        // CONTROL — a fully-empty row exists → the single-cell audition DOES pin col 0 (continuous, no re-strike).
        var j = BuildSceneLogic.Input()
        j.performPlaying = true
        j.performCells = grid((0..<7).map { ($0, $0, "p\($0)") })   // rows 0–6 occupied, ROW 7 empty
        j.chainActive = true; j.chainColourID = "aud"; j.chainMachine = []
        let (s2Opt, aud2) = BuildSceneLogic.composeSceneMeta(j)
        let s2 = try XCTUnwrap(s2Opt)
        XCTAssertEqual(aud2, 7, "the fully-empty row")
        XCTAssertEqual(s2.cellAt(0, 7)?.colourID, "aud", "the single cell parks at col 0 of the empty row")
        XCTAssertEqual(try XCTUnwrap(s2.rowLane)[7], 0b1, "the single-cell audition pins col 0 → continuous")
    }
    // A multi-step pass plays at its OWN captured rate (rowStepRate[8+c], not the scene default), and a step whose
    // per-step I/O is empty/short falls back to the column default. Neither is asserted by the layout test above.
    // (Coverage gap 2026-08-30.)
    func testMultiStepPassAppliesItsOwnRateAndFallsBackIOToTheColumnDefault() throws {
        var i = BuildSceneLogic.Input()
        i.playPlaying = true
        i.playColOn = [true, false, false, false, false, false, false, false]
        i.playColLen = [2, 1, 1, 1, 1, 1, 1, 1]
        i.playColSteps = [["a", "b"], [], [], [], [], [], [], []]
        i.playColStepChain = [[[], []], [], [], [], [], [], [], []]
        i.playColRate = [.r1_8, nil, nil, nil, nil, nil, nil, nil]         // the pass's OWN tempo
        i.playColEmit = [[.b], [.a], [.a], [.a], [.a], [.a], [.a], [.a]]     // COLUMN default emitter = B
        i.playColRecv = [3, 0, 0, 0, 0, 0, 0, 0]                             // COLUMN default door = D (3)
        i.playColStepEmit = [[[], []], [], [], [], [], [], [], []]           // both steps EMPTY → fall back to the column default
        i.playColStepRecv = [[], [], [], [], [], [], [], []]                 // short → fall back to the column default
        let s = BuildSceneLogic.composeScene(i)!
        let base = Snap.playLayerRowBase
        XCTAssertEqual(s.rowStepRate?[base], .r1_8, "the pass plays at its OWN captured rate at rowStepRate[8+c]")
        XCTAssertNil(s.rowStepRate?[base + 1], "a single-cell column sets no per-row rate")
        XCTAssertEqual(s.cellAt(0, base)?.buses, [.b], "step 0's EMPTY per-step emitter falls back to the column default (B)")
        XCTAssertEqual(s.cellAt(1, base)?.buses, [.b], "step 1 too")
        XCTAssertEqual(s.cellAt(0, base)?.inputReceiver, 3, "the SHORT per-step door falls back to the column default (D)")
    }
    func testPlayGridAloneProducesASceneOnlyWhenAColumnIsStarted() {
        var i = BuildSceneLogic.Input()
        i.playPlaying = true; i.playCells = grid([(0, 0, "b1")]); i.playSel = [0, -1, -1, -1, -1, -1, -1, -1]
        i.playColOn = [true, false, false, false, false, false, false, false]
        XCTAssertNotNil(BuildSceneLogic.composeScene(i), "a started play column alone produces a scene")
        i.playColOn = Array(repeating: false, count: 8)
        // playPlaying reflects "any column on" in real use, but assert the guard: with playPlaying false, no scene.
        i.playPlaying = false
        XCTAssertNil(BuildSceneLogic.composeScene(i), "no started column → no scene")
    }

    // A MACHINE-LESS cell on the PART GRID is SILENT (Paul 2026-08-26): the user only selected it — no output until a
    // machine is added. (The deployed PERFORM/play grid keeps the explicit-empty passthrough — the no-machine live-wire.)
    func testNoMachinePartCellIsSilentButPerformCellIsPassthrough() {
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true
        i.stagingCells = grid([(0, 2, "gold")]); i.stagingSel = [2, -1, -1, -1, -1, -1, -1, -1]
        i.rowChain = Array(repeating: [], count: 8)          // no per-row variation → resolver passes [] (no-machine)
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertNil(s.cellAt(0, 2), "a MACHINE-LESS cell on the part grid is SILENT — the user hasn't set it up")
        var p = BuildSceneLogic.Input()
        p.performPlaying = true
        p.performCells = grid([(0, 0, "gold")]); p.performActiveRung = { c, r in c == 0 && r == 0 }
        p.performChain = Array(repeating: Array(repeating: [], count: 8), count: 8)
        let sp = BuildSceneLogic.composeScene(p)!
        XCTAssertEqual(sp.cellAt(0, 0)?.processors, [], "a no-machine PERFORM cell is an explicit-empty passthrough too")
    }

    func testPerRowIOOverridesTheDefaultElseInherits() {
        // PER-ROW I/O (Paul 2026-08-18): row 1 carries its OWN door + emitter; row 4 inherits the part default.
        var i = BuildSceneLogic.Input()
        i.stagingPlaying = true
        i.stagingCells = grid([(0, 1, "gold"), (1, 4, "teal")])
        i.stagingSel = [1, 4, -1, -1, -1, -1, -1, -1]
        i.rowChain = Array(repeating: [ProcessorSlot(type: .arp)], count: 8)   // machined → the cells sound (a machine-less part cell is silent, Paul 2026-08-26)
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

    func testChainAuditionIsAOneStepContinuousPass() throws {
        // SELECT audition = a 1-step CONTINUOUS pass (Paul 2026-08-29: no re-striking per step). It parks at COLUMN 0 of a
        // fully-empty row and loops that row to column 0 — NOT laid across all 8 columns (which re-triggered every step).
        var i = BuildSceneLogic.Input()
        i.chainActive = true
        i.chainColourID = "cyan"
        i.chainMachine = []                                // raw passthrough
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, 0)?.colourID, "cyan", "the audition parks at column 0 of the empty row 0")
        XCTAssertNil(s.cellAt(1, 0), "NOT laid across the other columns — it's continuous, not re-struck each step")
        XCTAssertEqual(s.cellAt(0, 0)?.processors, [], "explicit empty chain (born-audible passthrough), never nil")
        let lane = try XCTUnwrap(s.rowLane, "the audition sets a per-row lane")
        XCTAssertEqual(lane[0], 0b1, "row 0 loops column 0 → continuous")
    }

    func testComposeSceneMetaReportsTheAuditionRow() {
        // #5 (Paul 2026-08-30): composeSceneMeta exposes the engine ROW the audition parked on so the aimed ferry can read
        // its LIVE strike feed at idx = col0*Snap.rows + auditionRow. It must equal where the audition cell actually lands.
        var i = BuildSceneLogic.Input()
        i.chainActive = true; i.chainColourID = "cyan"
        i.performPlaying = true
        i.performCells = grid([(0, 0, "gold")])            // piece on row 0 → the audition takes the next free row (1)
        let m = BuildSceneLogic.composeSceneMeta(i)
        let ar = m.auditionRow
        XCTAssertEqual(ar, 1, "the audition parks on the first free row (row 0 taken by the piece)")
        XCTAssertEqual(m.scene?.cellAt(0, ar ?? -1)?.colourID, "cyan", "auditionRow points at the audition cell (col 0)")
        // No chain voice ⇒ no audition row.
        var j = BuildSceneLogic.Input(); j.performPlaying = true; j.performCells = grid([(0, 0, "gold")])
        XCTAssertNil(BuildSceneLogic.composeSceneMeta(j).auditionRow, "no chain voice → no audition row")
    }

    func testComposeSceneMetaFallbackStillExposesARow() {
        // Paul 2026-08-30: when NO row is fully empty (a deployed piece fills col 0 of every row), the audition takes the
        // FALLBACK branch — which must STILL expose a chainLaneRow, else the aimed ferry has no live-strike index and reads
        // as dead (the "subsequent copies didn't animate" bug locus).
        var i = BuildSceneLogic.Input()
        i.chainActive = true; i.chainColourID = "cyan"
        i.performPlaying = true
        i.performCells = (0..<8).map { c in (0..<8).map { r in c == 0 ? "gold" : nil } }   // col 0 filled in EVERY row → no empty row
        XCTAssertNotNil(BuildSceneLogic.composeSceneMeta(i).auditionRow, "the fallback still exposes a row for the ferry's live feed")
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
        i.rowChain = Array(repeating: [ProcessorSlot(type: .arp)], count: 8)   // machined → the part cell sounds
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
        i.rowChain = Array(repeating: [ProcessorSlot(type: .arp)], count: 8)   // machined → the part cell sounds
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

    // THE MACHINE BINDING (Paul 2026-09-01, state-unification): the ONE resolution the play button + hue + cell indicators
    // all derive from. Locks the reproduced rules (play-button active, grey, ferry binding) so they can't silently diverge.
    func testMachineBindingResolvesFerryAuditionAndGrey() {
        let aud = "gsAud"
        let on = [false, false, true, false, false, false, false, false]   // column 2 is playing

        // 1. A play ferry the machine names (SELECT page) BINDS to that column — plays iff the column is on, never grey.
        let ferry = BuildSceneLogic.machineBinding(selID: "c5", audID: aud, onSelectPage: true, chainActive: false,
                                                   partActive: false, selectedPlayCol: 2, playColOn: on)
        XCTAssertEqual(ferry.kind, .playFerry(2)); XCTAssertTrue(ferry.playing); XCTAssertFalse(ferry.isGrey)
        let ferryOff = BuildSceneLogic.machineBinding(selID: "c5", audID: aud, onSelectPage: true, chainActive: false,
                                                     partActive: false, selectedPlayCol: 5, playColOn: on)
        XCTAssertEqual(ferryOff.kind, .playFerry(5)); XCTAssertFalse(ferryOff.playing, "column 5 is off")

        // 2. The SELECT audition (selID == gsAud, no ferry) → GREY, plays iff chainActive.
        let audOn = BuildSceneLogic.machineBinding(selID: aud, audID: aud, onSelectPage: true, chainActive: true,
                                                  partActive: false, selectedPlayCol: nil, playColOn: on)
        XCTAssertEqual(audOn.kind, .selectAudition); XCTAssertTrue(audOn.isGrey); XCTAssertTrue(audOn.playing)
        let audOff = BuildSceneLogic.machineBinding(selID: aud, audID: aud, onSelectPage: true, chainActive: false,
                                                   partActive: false, selectedPlayCol: nil, playColOn: on)
        XCTAssertTrue(audOff.isGrey); XCTAssertFalse(audOff.playing, "not auditioning → stopped")

        // 3. A REAL colour on SELECT (a browsed/ferried cell) → NOT grey; PART page → NEVER grey, play state = partActive.
        let realSel = BuildSceneLogic.machineBinding(selID: "c3", audID: aud, onSelectPage: true, chainActive: true,
                                                    partActive: false, selectedPlayCol: nil, playColOn: on)
        XCTAssertFalse(realSel.isGrey, "a real colour is never grey")
        let part = BuildSceneLogic.machineBinding(selID: aud, audID: aud, onSelectPage: false, chainActive: false,
                                                 partActive: true, selectedPlayCol: nil, playColOn: on)
        XCTAssertEqual(part.kind, .partRow); XCTAssertFalse(part.isGrey, "PART wears its colour, never grey"); XCTAssertTrue(part.playing)

        // 4. Nothing selected + nothing playing → .none.
        let none = BuildSceneLogic.machineBinding(selID: nil, audID: aud, onSelectPage: true, chainActive: false,
                                                 partActive: false, selectedPlayCol: nil, playColOn: on)
        XCTAssertEqual(none.kind, .none); XCTAssertFalse(none.playing)
    }
}
