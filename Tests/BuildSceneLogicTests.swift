import XCTest
import CoreGraphics

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
    // FERRY ROW UNIFICATION (Paul 2026-09-27): every ferry composes from its own BuildPart into its own dedicated
    // engine rows (Snap.ferryRowBase) now — a part only has Snap.rowsPerFerry(4) rows, 0...3. These two helpers build
    // the new Input shape, replacing the old i.stagingPlaying/stagingCells/stagingSel/rowChain-style construction.
    private func partGrid(_ pairs: [(Int, Int, String)]) -> [[String?]] {
        var g = BuildPart().stagingCells   // correctly sized: Snap.maxCols columns × Snap.rowsPerFerry rows
        for (c, r, id) in pairs { g[c][r] = id }
        return g
    }
    private func ferryPart(cells: [[String?]] = [], sel: [Int] = [], rowChain: [[ProcessorSlot]] = [],
                            rate: StepRate? = nil, length: Int? = nil, loopCols: [Int] = [],
                            receiver: Int = 0, emitters: Set<Bus> = [.a],
                            rowReceiver: [Int?]? = nil, rowEmitters: [Set<Bus>?]? = nil,
                            multi: [UInt8]? = nil, selMulti: Bool = false) -> BuildPart {
        var p = BuildPart()
        if !cells.isEmpty { p.stagingCells = cells }
        if !sel.isEmpty { p.stagingSel = sel }
        p.rowChain = rowChain
        p.rate = rate; p.length = length
        p.loopCols = loopCols.isEmpty ? nil : loopCols
        p.receiver = receiver; p.emitters = emitters
        p.rowReceiver = rowReceiver; p.rowEmitters = rowEmitters
        p.stagingMulti = multi; p.selMulti = selMulti   // MULTI-SELECT (2026-09-27)
        return p
    }
    // A SINGLE active ferry (ferry 0) — the direct replacement for the old "i.stagingPlaying = true; i.stagingCells =
    // ...; i.stagingSel = ...` idiom throughout this file.
    private func stagingInput(cells: [[String?]] = [], sel: [Int] = [], rowChain: [[ProcessorSlot]] = [],
                               rate: StepRate? = nil, length: Int? = nil, loopCols: [Int] = [],
                               receiver: Int = 0, emitters: Set<Bus> = [.a],
                               rowReceiver: [Int?]? = nil, rowEmitters: [Set<Bus>?]? = nil,
                               multi: [UInt8]? = nil, selMulti: Bool = false) -> BuildSceneLogic.Input {
        let part = ferryPart(cells: cells, sel: sel, rowChain: rowChain, rate: rate, length: length, loopCols: loopCols,
                              receiver: receiver, emitters: emitters, rowReceiver: rowReceiver, rowEmitters: rowEmitters,
                              multi: multi, selMulti: selMulti)
        var i = BuildSceneLogic.Input()
        i.activeFerry = 0
        i.ferryOn = Array(repeating: false, count: Snap.ferries); i.ferryOn[0] = true
        i.ferryAudible = Array(repeating: true, count: Snap.ferries)
        i.ferryParts = Array(repeating: nil, count: Snap.ferries); i.ferryParts[0] = part
        i.ferryRowChain = Array(repeating: [], count: Snap.ferries); i.ferryRowChain[0] = rowChain
        return i
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
        XCTAssertEqual(out, Array(repeating: -1, count: Snap.maxCols), "no stocked cell anywhere → every column resolves to silent (§E: 16-wide)")
    }
    // C5 FIX (Paul 2026-08-27): a RAGGED column (< 8 rows, from a malformed/older decode) must not trap — the row
    // subscript + the fallback scan were bounded to 8, not the column's actual length.
    func testReconcileToleratesRaggedColumns() {
        var cells: [[String?]] = [["gold", nil, nil], [], ["x", "y"]]                 // columns of length 3, 0, 2
        while cells.count < 8 { cells.append([]) }                                   // the rest empty (length 0)
        let out = BuildSceneLogic.reconcileStagingSel([5, 0, 1, -1, 0, 0, 0, 0], cells: cells)   // picks past several columns' lengths
        XCTAssertEqual(out.count, Snap.maxCols)
        XCTAssertEqual(out[0], 0, "col 0 pick at row 5 (> len 3) falls back to the stocked row 0")
        XCTAssertEqual(out[1], -1, "col 1 is empty → silent, no trap")
        XCTAssertEqual(out[2], 1, "col 2 pick at row 1 is valid")
        XCTAssertEqual(out[4], -1, "col 4 (empty) pick falls back to silent, no trap")
    }


    // MARK: MULTI-SELECT (Paul 2026-09-27) — activeRungs is the plural sibling of selectedRung: SINGLE mode (multi nil,
    // or that column's byte 0) degenerates to exactly [lead], byte-identical everywhere multi-select is unused; once a
    // column's mask is non-zero it's read EXCLUSIVELY (the mask IS the selection, not an addition to the lead).

    func testActiveRungsDegeneratesToTheLeadWhenMultiIsNil() {
        XCTAssertEqual(BuildSceneLogic.activeRungs([2, -1, 0, 3], nil, 0), [2])
        XCTAssertEqual(BuildSceneLogic.activeRungs([2, -1, 0, 3], nil, 1), [], "a silent (-1) lead → no rungs at all")
    }
    func testActiveRungsDegeneratesToTheLeadWhenThatColumnsMaskIsUntouched() {
        let multi: [UInt8] = [0b0000_0000, 0b0000_1010]   // column 0 untouched (0) even though multi is non-nil overall
        XCTAssertEqual(BuildSceneLogic.activeRungs([2, 3], multi, 0), [2], "column 0's own byte is 0 → falls back to its lead")
    }
    func testActiveRungsReadsTheMaskExclusivelyOnceNonZero() {
        let multi: [UInt8] = [0b0000_1010]   // bits 1 and 3 set — rows 1 and 3
        XCTAssertEqual(BuildSceneLogic.activeRungs([2], multi, 0), [1, 3], "the lead (2) is IGNORED once the mask is non-zero — the mask IS the selection")
    }
    func testActiveRungsOutOfRangeColumnIsSilent() {
        XCTAssertEqual(BuildSceneLogic.activeRungs([2, 3], nil, 5), [])
        XCTAssertEqual(BuildSceneLogic.activeRungs([2, 3], [0b0001], 5), [])
    }

    func testReconcileStagingMultiDropsBitsPointingAtEmptyCells() {
        let cells = partGrid([(0, 1, "gold"), (0, 3, "gold")])   // column 0 stocked at rows 1 and 3 only
        let multi: [UInt8] = [0b0000_1011]   // bits 0, 1, 3 — bit 0 points at an EMPTY cell
        let out = BuildSceneLogic.reconcileStagingMulti(multi, cells: cells)
        XCTAssertEqual(out[0], 0b0000_1010, "bit 0 (empty cell) is dropped; bits 1 and 3 (stocked) survive")
    }
    func testReconcileStagingMultiAllBitsDroppedRevertsToZero() {
        let out = BuildSceneLogic.reconcileStagingMulti([0b0001], cells: partGrid([]))   // nothing stocked anywhere
        XCTAssertEqual(out[0], 0, "no surviving bit → the sentinel for 'no mask' (falls back to the lead)")
    }

    // partGridTap: `multi` off reproduces every existing SINGLE-mode assertion above unchanged (the default parameter
    // value); `multi` on always toggles, regardless of firstTapOfGesture — a column can have more than one rung active,
    // so a tap should only ever affect the ONE rung tapped, never exclusively deselect/select like SINGLE mode does.
    func testPartGridTapMultiModeAlwaysToggles() {
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 0, row: 1, currentRung: 1, cid: "gold", selectedMachineID: "gold",
                                                   selectMode: false, firstTapOfGesture: true, multi: true),
                       .toggleRung(row: 1), "even tapping the CURRENT lead on the first tap of a gesture toggles in MULTI, never deselects the whole column")
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 0, row: 3, currentRung: 1, cid: nil, selectedMachineID: "gold",
                                                   selectMode: false, firstTapOfGesture: true, multi: true),
                       .toggleRung(row: 3), "an EMPTY cell still toggles — populated or not")
    }
    func testPartGridTapSelectModeStillWinsOverMulti() {
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 0, row: 1, currentRung: 1, cid: "gold", selectedMachineID: "gold",
                                                   selectMode: true, firstTapOfGesture: true, multi: true),
                       .focus(machineID: "gold"), "SELECT mode intercepts before MULTI ever gets a say")
    }

    // A composeScene-level check that MULTI actually sounds more than one row: ferry 0, MULTI on, column 0's mask has
    // rows 0 AND 2 set — both machines must land in the scene at ferry 0's own row block, simultaneously.
    func testComposeSceneSoundsEveryActiveRungInMultiMode() {
        let cells = partGrid([(0, 0, "gold"), (0, 2, "cyan")])
        let rowChain: [[ProcessorSlot]] = [[ProcessorSlot(type: .arp)], [], [ProcessorSlot(type: .arp)], []]
        let multi: [UInt8] = [0b0000_0101]   // bits 0 and 2
        let i = stagingInput(cells: cells, sel: [0, -1, -1, -1, -1, -1, -1, -1], rowChain: rowChain, length: 1,
                              multi: multi, selMulti: true)
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, Snap.ferryRowBase(0) + 0)?.machineID, "gold", "row 0 sounds")
        XCTAssertEqual(s.cellAt(0, Snap.ferryRowBase(0) + 2)?.machineID, "cyan", "row 2 ALSO sounds, simultaneously")
        XCTAssertNil(s.cellAt(0, Snap.ferryRowBase(0) + 1), "row 1 was never in the mask — stays silent")
    }
    // The same ferry with selMulti OFF plays ONLY its lead (row 0), even though the mask still has bit 2 set — a
    // ferry switched back to SINGLE never sounds a stale mask (composeSceneMeta gates the mask on selMultiResolved).
    func testComposeSceneIgnoresTheMaskWhenSelMultiIsOff() {
        let cells = partGrid([(0, 0, "gold"), (0, 2, "cyan")])
        let rowChain: [[ProcessorSlot]] = [[ProcessorSlot(type: .arp)], [], [ProcessorSlot(type: .arp)], []]
        let multi: [UInt8] = [0b0000_0101]
        let i = stagingInput(cells: cells, sel: [0, -1, -1, -1, -1, -1, -1, -1], rowChain: rowChain, length: 1,
                              multi: multi, selMulti: false)
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, Snap.ferryRowBase(0) + 0)?.machineID, "gold", "the lead still sounds")
        XCTAssertNil(s.cellAt(0, Snap.ferryRowBase(0) + 2), "row 2's bit is ignored while selMulti is off")
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
        XCTAssertNil(BuildSceneLogic.mutateChain([], avoid: [], &rng, scored: true), "scored: still nil for an empty chain")
    }

    // scored: picks the most-musical of a few distinct variants — still value-only, distinct, and audible.
    func testMutateScoredReturnsADistinctAudibleValueVariant() {
        let base = [ProcessorSlot(type: .arp)]
        var rng = DiceRNG(seed: 11)
        guard let m = BuildSceneLogic.mutateChain(base, avoid: [Dice.fingerprint(base)], &rng, scored: true) else {
            return XCTFail("scored mutate should find a distinct, musical variant of an arp")
        }
        XCTAssertEqual(m.map(\.type), base.map(\.type), "value-only: types unchanged")
        let fp = Dice.fingerprint(m)
        XCTAssertFalse(fp.isEmpty, "not silent")
        XCTAssertNotEqual(fp, Dice.fingerprint(base), "distinct from the source")
    }

    // MARK: scale lock (RANDOMIZE/MUTATE keep generated chains in key when a scale door is set)

    func testScaleLockDoorPrefersOwnReceiverThenAnyScaleDoor() {
        // preferred is a scale door → use it
        XCTAssertEqual(BuildSceneLogic.scaleLockDoor(isScale: [false, true, false, false], preferred: 1), 1)
        // preferred is NOT a scale door → fall back to the first scale door
        XCTAssertEqual(BuildSceneLogic.scaleLockDoor(isScale: [false, false, true, false], preferred: 0), 2)
        // no preferred → the first scale door
        XCTAssertEqual(BuildSceneLogic.scaleLockDoor(isScale: [false, false, false, true], preferred: nil), 3)
        // no scale door anywhere → nil (don't lock)
        XCTAssertNil(BuildSceneLogic.scaleLockDoor(isScale: [false, false, false, false], preferred: 1))
    }

    func testScaleLockedAppendsAMoveLockAndIsIdempotent() {
        let base = [ProcessorSlot(type: .arp)]
        // no scale door → unchanged
        XCTAssertEqual(BuildSceneLogic.scaleLocked(base, door: nil), base)
        // a scale door → append a LOCK/MOVE avoid tail referencing that door
        let locked = BuildSceneLogic.scaleLocked(base, door: 2)
        XCTAssertEqual(locked.count, 2)
        XCTAssertEqual(locked.last?.type, .avoid)
        XCTAssertEqual(locked.last?.params.avoidRefKind, .door)
        XCTAssertEqual(locked.last?.params.avoidRefIndex, 2)
        XCTAssertEqual(locked.last?.params.avoidMode, .lock)
        XCTAssertEqual(locked.last?.params.avoidAction, .move)
        // idempotent: re-locking (even after the door changes) leaves exactly ONE lock, pointed at the new door
        let reLocked = BuildSceneLogic.scaleLocked(locked, door: 0)
        XCTAssertEqual(reLocked.filter { $0.type == .avoid }.count, 1, "no accumulation")
        XCTAssertEqual(reLocked.last?.params.avoidRefIndex, 0, "re-points at the current scale door")
    }

    func testScaleLockedLeavesAFullChainUnchanged() {
        let full = (0..<8).map { _ in ProcessorSlot(type: .arp) }   // 8 = maxSlots
        XCTAssertEqual(BuildSceneLogic.scaleLocked(full, door: 1), full, "no room for the lock → unchanged")
    }

    func testScaleEnrichHarmonyReplacesOctavesWithMusicalIntervalsPreservingCount() {
        var h = ProcessorSlot(type: .harmonize)
        h.params.harmIntervals = [12, -12, 0]                        // octave-only + a unison
        let out = BuildSceneLogic.scaleEnrichHarmony([h])
        let iv = out[0].params.harmIntervals!
        XCTAssertEqual(iv.count, 3, "note COUNT preserved (replace, not add) → no density/flood change")
        XCTAssertEqual(iv[2], 0, "unison is left alone")
        XCTAssertFalse(iv[0] % 12 == 0, "the +12 octave became a musical interval")
        XCTAssertFalse(iv[1] % 12 == 0, "the -12 octave became a musical interval")
        // a non-harmonize slot, and an already-musical harmonize, are untouched
        XCTAssertEqual(BuildSceneLogic.scaleEnrichHarmony([ProcessorSlot(type: .arp)]), [ProcessorSlot(type: .arp)])
        var m = ProcessorSlot(type: .harmonize); m.params.harmIntervals = [4, 7, 0]
        XCTAssertEqual(BuildSceneLogic.scaleEnrichHarmony([m]), [m], "already diatonic → unchanged")
    }

    // passLen clamps a play-column pass length into [1, Snap.maxCols]; out-of-range column / short array → a single cell.
    // (Housekeeping 2026-09-07: this gates multi-step play-pass composition and had zero coverage.)
    func testPassLenClampsToMaxColsAndHandlesOutOfRange() {
        XCTAssertEqual(BuildSceneLogic.passLen([5], 0), 5, "in-range length passes through")
        XCTAssertEqual(BuildSceneLogic.passLen([0], 0), 1, "0 floors to a single cell")
        XCTAssertEqual(BuildSceneLogic.passLen([999], 0), Snap.maxCols, "over-long clamps to the maxCols ceiling")
        XCTAssertEqual(BuildSceneLogic.passLen([], 3), 1, "empty array → single cell")
        XCTAssertEqual(BuildSceneLogic.passLen([5], 9), 1, "out-of-range column → single cell")
    }

    // mutateCount always yields 1…3 and is deterministic per seed (the mutate-grid fan-out count).
    func testMutateCountStaysInOneToThreeAndIsSeeded() {
        for seed in UInt64(0)..<200 {
            var g = DiceRNG(seed: seed)
            let n = BuildSceneLogic.mutateCount(&g)
            XCTAssertTrue((1...3).contains(n), "mutateCount out of range: \(n) (seed \(seed))")
        }
        var a = DiceRNG(seed: 42), b = DiceRNG(seed: 42)
        XCTAssertEqual(BuildSceneLogic.mutateCount(&a), BuildSceneLogic.mutateCount(&b), "same seed → same count")
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

    // MARK: PART AUTOMATION — the AUTO lanes (Paul 2026-09-02). A machine's ACTIVE lane ramps a param across its EXTENT
    // of part cells (sub-range low→high, column→row order), baked per-cell at build via applyAuto.

    func testAutoLaneRampsParamAcrossTheSpan() {
        var base = ProcessorSlot(type: .arp); base.params.gate = 0.5   // a distinct base gate to override
        let rowChain = (0..<Snap.rowsPerFerry).map { $0 == 2 ? [base] : [] }
        var i = stagingInput(cells: partGrid([(0, 2, "gold"), (1, 2, "gold"), (2, 2, "gold")]),
                              sel: [2, 2, 2, -1, -1, -1, -1, -1], rowChain: rowChain)   // three gold cells play (rung 2)
        // SPAN-ONLY: AUTO 1 on slot 0's GATE, span start 0 length 3 → ramps LOW→HIGH across cols 0,1,2.
        i.partAuto = ["gold": PartAutoMachine(activeLane: 0, lanes: [AutoLane(slot: 0, param: "", spanStart: 0, spanLen: 3)])]
        let s = BuildSceneLogic.composeScene(i)!
        let row2 = Snap.ferryRowBase(0) + 2
        XCTAssertEqual(s.cellAt(0, row2)?.processors?.first?.params.gate ?? -1, 0.3, accuracy: 1e-6, "rank 0 → the sub-range LOW")
        XCTAssertEqual(s.cellAt(1, row2)?.processors?.first?.params.gate ?? -1, 0.65, accuracy: 1e-6, "rank 1 → the midpoint")
        XCTAssertEqual(s.cellAt(2, row2)?.processors?.first?.params.gate ?? -1, 1.0, accuracy: 1e-6, "rank 2 → the sub-range HIGH")
    }

    func testAutoNoneLaneIsByteIdentical() {
        var base = ProcessorSlot(type: .arp); base.params.gate = 0.5
        let rowChain = (0..<Snap.rowsPerFerry).map { $0 == 2 ? [base] : [] }
        var i = stagingInput(cells: partGrid([(0, 2, "gold")]), sel: [2, -1, -1, -1, -1, -1, -1, -1], rowChain: rowChain)
        // NONE (activeLane −1) even though a lane HAS a span → nothing bakes (byte-identical)
        i.partAuto = ["gold": PartAutoMachine(activeLane: -1, lanes: [AutoLane(slot: 0, param: "gate", spanStart: 0, spanLen: 1)])]
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, Snap.ferryRowBase(0) + 2)?.processors?.first?.params.gate ?? -1, 0.5, accuracy: 1e-6, "NONE → the base value untouched")
    }

    // SPAN-ONLY (Paul 2026-09-04): the span TILES — a length-2 span repeats [lo, hi, lo, hi] across the row.
    func testAutoSpanTilesAcrossTheRowThroughComposeScene() {
        var base = ProcessorSlot(type: .arp); base.params.gate = 0.5
        let rowChain = (0..<Snap.rowsPerFerry).map { $0 == 2 ? [base] : [] }
        var i = stagingInput(cells: partGrid([(0, 2, "gold"), (1, 2, "gold"), (2, 2, "gold"), (3, 2, "gold")]),
                              sel: [2, 2, 2, 2, -1, -1, -1, -1], rowChain: rowChain)
        i.partAuto = ["gold": PartAutoMachine(activeLane: 0, lanes: [AutoLane(slot: 0, param: "", spanStart: 0, spanLen: 2)])]
        let s = BuildSceneLogic.composeScene(i)!
        let row2 = Snap.ferryRowBase(0) + 2
        XCTAssertEqual(s.cellAt(0, row2)?.processors?.first?.params.gate ?? -1, 0.3, accuracy: 1e-6)
        XCTAssertEqual(s.cellAt(1, row2)?.processors?.first?.params.gate ?? -1, 1.0, accuracy: 1e-6)
        XCTAssertEqual(s.cellAt(2, row2)?.processors?.first?.params.gate ?? -1, 0.3, accuracy: 1e-6, "the length-2 span tiles → LOW again")
        XCTAssertEqual(s.cellAt(3, row2)?.processors?.first?.params.gate ?? -1, 1.0, accuracy: 1e-6)
    }
    // The lane's explicit FROM/TO (lo/hi) endpoints override the curated sub-range.
    func testAutoExplicitFromToOverridesTheSubRange() {
        var base = ProcessorSlot(type: .arp); base.params.gate = 0.5
        let rowChain = (0..<Snap.rowsPerFerry).map { $0 == 2 ? [base] : [] }
        var i = stagingInput(cells: partGrid([(0, 2, "gold"), (1, 2, "gold"), (2, 2, "gold")]),
                              sel: [2, 2, 2, -1, -1, -1, -1, -1], rowChain: rowChain)
        i.partAuto = ["gold": PartAutoMachine(activeLane: 0, lanes: [AutoLane(slot: 0, param: "", lo: 0.5, hi: 0.9, spanStart: 0, spanLen: 3)])]
        let s = BuildSceneLogic.composeScene(i)!
        let row2 = Snap.ferryRowBase(0) + 2
        XCTAssertEqual(s.cellAt(0, row2)?.processors?.first?.params.gate ?? -1, 0.5, accuracy: 1e-6, "FROM overrides the gate sub-range low (0.3)")
        XCTAssertEqual(s.cellAt(2, row2)?.processors?.first?.params.gate ?? -1, 0.9, accuracy: 1e-6, "TO overrides the sub-range high (1.0)")
    }
    // HOUSEKEEPING: autoParamFullRange (the FROM/TO fader BOUNDS) returns the RAW range — distinct from autoSubRange's trim.
    func testAutoParamFullRangeIsRawNotTrimmed() {
        let cont = BuildSceneLogic.autoParamFullRange(.continuous(lo: 0.05, hi: 1))
        XCTAssertEqual(cont.lo, 0.05, accuracy: 1e-9, "full range is the RAW low (autoSubRange trims to 0.24)")
        XCTAssertEqual(cont.hi, 1.0, accuracy: 1e-9)
        XCTAssertEqual(BuildSceneLogic.autoParamFullRange(.option(["a", "b", "c"])).hi, 2.0, accuracy: 1e-9, "option → 0…count-1")
        let st = BuildSceneLogic.autoParamFullRange(.stepper(lo: 1, hi: 16))
        XCTAssertEqual(st.lo, 1.0, accuracy: 1e-9); XCTAssertEqual(st.hi, 16.0, accuracy: 1e-9)
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
        d.partAuto = ["gold": PartAutoMachine(activeLane: 2, lanes: [AutoLane(slot: 1, param: "spread", cells: [3, 19, 35])])]
        let data = try JSONEncoder().encode(d)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.partAuto?["gold"]?.activeLane, 2)
        XCTAssertEqual(back.partAuto?["gold"]?.lanes.first?.param, "spread")
        XCTAssertEqual(back.partAuto?["gold"]?.lanes.first?.cells, [3, 19, 35])
    }

    // JOB 2 (Paul 2026-09-03): AutoLane/PartAutoMachine are decode-TOLERANT — a MISSING key (a field added after a save
    // shipped, or a hand-truncated doc) falls back to the default instead of throwing. Guards the CR-8 data-loss class:
    // partAuto is a PluginState dict, so a throw here would reset the WHOLE session.
    func testAutoLaneDecodesWithMissingKeys() throws {
        let full = try JSONDecoder().decode(AutoLane.self, from: "{}".data(using: .utf8)!)   // every key absent
        XCTAssertEqual(full.slot, 0); XCTAssertEqual(full.param, ""); XCTAssertTrue(full.cells.isEmpty)
        XCTAssertNil(full.lo); XCTAssertNil(full.hi); XCTAssertNil(full.span)
        let partial = try JSONDecoder().decode(AutoLane.self, from: #"{"slot":3,"param":"LENGTH","span":4}"#.data(using: .utf8)!)
        XCTAssertEqual(partial.slot, 3); XCTAssertEqual(partial.param, "LENGTH"); XCTAssertEqual(partial.span, 4)
        XCTAssertTrue(partial.cells.isEmpty); XCTAssertNil(partial.lo)     // absent optional/collection keys → defaults, no throw
    }
    func testPartAutoMachineDecodesWithMissingKeys() throws {
        let empty = try JSONDecoder().decode(PartAutoMachine.self, from: "{}".data(using: .utf8)!)
        XCTAssertEqual(empty.activeLane, -1); XCTAssertTrue(empty.lanes.isEmpty)
        // an OLD document with NO partAuto at all decodes to nil (additive-Optional) — no reset
        var d = PluginState.makeInit(); d.partAuto = nil
        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(d))
        XCTAssertNil(back.partAuto)
    }

    // JOB 3 (Paul 2026-09-03, bug-hunt A-1): a fresh AUTO lane (empty param) must resolve to a MUSICAL param, never
    // BYPASS — BYPASS is always macroParamsForProcessor's FIRST entry, so a plain `.first` fallback ramped a mute gate
    // for every type without a curated autoPrimaryKey (drone/euclid/mod/glide/…). Now it prefers the first non-bypass.
    func testAutoDefaultParamIsNeverBypassWhenAMusicalParamExists() {
        for t in [ProcessorType.euclid, .mod, .glide, .burst, .cascade, .length] {
            let key = BuildSceneLogic.autoResolvedParamKey(t, laneParam: "")
            XCTAssertFalse(key.isEmpty, "\(t) resolves a param")
            XCTAssertNotEqual(key, "bypass", "\(t): a fresh lane sweeps a musical param, not the BYPASS gate")
        }
        // a curated type keeps its musical default; an explicit valid choice is honoured
        XCTAssertEqual(BuildSceneLogic.autoResolvedParamKey(.arp, laneParam: ""), "gate")
        XCTAssertEqual(BuildSceneLogic.autoResolvedParamKey(.arp, laneParam: "bypass"), "bypass", "an EXPLICIT bypass choice is still allowed")
    }

    // §E 16-STEP (Paul 2026-09-02): a 16-wide part composes cells past column 7 and the row loops 16.
    func testSixteenWidePartComposesColumnsPastEight() {
        var cells = BuildPart().stagingCells
        cells[12][3] = "gold"                                  // a cell at COLUMN 12 (past the old 8-wide limit)
        var sel = Array(repeating: -1, count: Snap.maxCols); sel[12] = 3
        let rowChain = (0..<Snap.rowsPerFerry).map { $0 == 3 ? [ProcessorSlot(type: .arp)] : [] }
        let i = stagingInput(cells: cells, sel: sel, rowChain: rowChain, length: 16)
        let s = BuildSceneLogic.composeScene(i)!
        let row3 = Snap.ferryRowBase(0) + 3
        XCTAssertEqual(s.cellAt(12, row3)?.machineID, "gold", "a cell at column 12 composes (16-wide part)")
        XCTAssertEqual(s.rowLen?[row3], 16, "the row loops 16 columns")
    }

    func testPartHonoursSelectionAndIsSilentWhereDeselected() {
        let rowChain = (0..<Snap.rowsPerFerry).map { $0 == 2 ? [ProcessorSlot(type: .arp)] : [] }   // gold has a machine → it composes (Paul 2026-08-26: a machine-less part cell is silent)
        let i = stagingInput(cells: partGrid([(0, 2, "gold"), (1, 2, "gold"), (2, 2, "gold")]),
                              sel: [2, -1, 2, -1, -1, -1, -1, -1], rowChain: rowChain)   // columns 0 and 2 play, column 1 silent
        let s = BuildSceneLogic.composeScene(i)!
        let row2 = Snap.ferryRowBase(0) + 2
        XCTAssertEqual(s.cellAt(0, row2)?.machineID, "gold")
        XCTAssertNil(s.cellAt(1, row2), "column 1 was deselected → no cell in the scene")
        XCTAssertEqual(s.cellAt(2, row2)?.machineID, "gold")
    }

    // THE PLAY GRID (Paul 2026-08-29): each STARTED column is an INDEPENDENT, CONTINUOUS voice. It composes at engine
    // (COLUMN 0, row = the play-column index) and that row loops COLUMN 0 — no time axis, so it plays continuously (not
    // only when a playhead crosses). Each carries the I/O it was FERRIED WITH (playColRecv/playColEmit).
    func testPlayGridComposesStartedColumnsAsContinuousVoices() throws {
        // FERRY ROW UNIFICATION (Paul 2026-09-27): every ferry — active or background — composes from its own
        // BuildPart into its own dedicated row block, always (no more "play grid" flatten cache). A single-column
        // part (length 1, no loop selection) is the CONTINUOUS voice this test covers: it loops column 0 forever.
        let part0 = ferryPart(cells: partGrid([(0, 0, "b1")]), sel: [0], rowChain: [[ProcessorSlot(type: .arp)], [], [], []],
                               length: 1, receiver: 2, emitters: [.b])
        let part1 = ferryPart(cells: partGrid([(0, 0, "b2")]), sel: [0], rowChain: [[ProcessorSlot(type: .harmonize)], [], [], []],
                               length: 1, receiver: 1, emitters: [.c, .d])
        let part2 = ferryPart(cells: partGrid([(0, 0, "b3")]), sel: [0], rowChain: [[ProcessorSlot(type: .arp)], [], [], []], length: 1)
        var i = BuildSceneLogic.Input()
        i.ferryOn = [true, true, false, false, false, false, false, false]   // ferry 2 is populated but NOT started
        i.ferryAudible = Array(repeating: true, count: Snap.ferries)
        i.ferryParts = Array(repeating: nil, count: Snap.ferries); i.ferryParts[0] = part0; i.ferryParts[1] = part1; i.ferryParts[2] = part2
        i.ferryRowChain = Array(repeating: [], count: Snap.ferries)
        i.ferryRowChain[0] = part0.rowChain; i.ferryRowChain[1] = part1.rowChain; i.ferryRowChain[2] = part2.rowChain
        let s = BuildSceneLogic.composeScene(i)!
        let base0 = Snap.ferryRowBase(0), base1 = Snap.ferryRowBase(1), base2 = Snap.ferryRowBase(2)   // each ferry's own dedicated row block
        // ferry 0 → engine (col 0, ferry 0's row) — DISJOINT from every other ferry's block
        XCTAssertEqual(s.cellAt(0, base0)?.machineID, "b1", "ferry 0's cell composes at ferry 0's row")
        XCTAssertEqual(s.cellAt(0, base0)?.processors?.first?.type, .arp, "with its own machine")
        XCTAssertEqual(s.cellAt(0, base0)?.buses, [.b], "its own emitter")
        XCTAssertEqual(s.cellAt(0, base0)?.inputReceiver, 2, "its own door")
        // ferry 1 → engine (col 0, ferry 1's row)
        XCTAssertEqual(s.cellAt(0, base1)?.machineID, "b2", "ferry 1's cell composes at ferry 1's row")
        XCTAssertEqual(s.cellAt(0, base1)?.buses, [.c, .d], "carries its own emitters")
        XCTAssertNil(s.cellAt(0, base2), "ferry 2 is populated but NOT started → its engine row is empty")
        // CONTINUOUS: the started ferries' rows loop column 0; the rest don't loop.
        let lane = try XCTUnwrap(s.rowLane, "a single-column ferry sets a per-row lane")
        XCTAssertEqual(lane[base0], 0b1, "ferry 0's row loops column 0 → continuous")
        XCTAssertEqual(lane[base1], 0b1, "ferry 1's row loops column 0 → continuous")
        XCTAssertEqual(lane[base2], 0, "ferry 2 not started → its row doesn't loop")
    }
    func testPlayColumnMultiStepPassLaysStepsAndLoopsItsLength() throws {
        // MULTI-STEP PASS: a ferry's own part with MULTIPLE populated columns (across different rows, so each can
        // carry its own I/O) lays its rows' machines across cols 0..plan.count-1, SWEPT (no col-0 pin) and looped by
        // rowLen. A ferry with only ONE effective column (length 1) stays the pinned single-cell voice.
        let part0 = ferryPart(cells: partGrid([(0, 0, "a"), (2, 2, "c")]), sel: [0, -1, 2, -1],
                               rowChain: [[ProcessorSlot(type: .arp)], [], [ProcessorSlot(type: .harmonize)], []],
                               length: 3, receiver: 0, emitters: [.a],
                               rowReceiver: [0, nil, 2, nil], rowEmitters: [[.a], nil, [.c], nil])   // PER-ROW I/O: row 0 → A/door 0, row 2 → C/door 2
        let part1 = ferryPart(cells: partGrid([(0, 0, "solo")]), sel: [0], rowChain: [[ProcessorSlot(type: .arp)], [], [], []],
                               length: 1, receiver: 0, emitters: [.b])
        var i = BuildSceneLogic.Input()
        i.ferryOn = [true, true, false, false, false, false, false, false]
        i.ferryAudible = Array(repeating: true, count: Snap.ferries)
        i.ferryParts = Array(repeating: nil, count: Snap.ferries); i.ferryParts[0] = part0; i.ferryParts[1] = part1
        i.ferryRowChain = Array(repeating: [], count: Snap.ferries)
        i.ferryRowChain[0] = part0.rowChain; i.ferryRowChain[1] = part1.rowChain
        let s = BuildSceneLogic.composeScene(i)!
        let base = Snap.ferryRowBase(0), base1 = Snap.ferryRowBase(1)
        XCTAssertEqual(s.cellAt(0, base + 0)?.machineID, "a", "logical step 0 at (col 0, row 0)")
        XCTAssertNil(s.cellAt(1, base + 0), "logical step 1 is a REST → no cell")
        XCTAssertEqual(s.cellAt(2, base + 2)?.machineID, "c", "logical step 2 at (col 2, row 2)")
        XCTAssertEqual(s.cellAt(2, base + 2)?.processors?.first?.type, .harmonize, "each row carries its own resolved chain")
        XCTAssertEqual(s.cellAt(0, base + 0)?.buses, [.a], "row 0 keeps its OWN emitter (A)")
        XCTAssertEqual(s.cellAt(2, base + 2)?.buses, [.c], "row 2 keeps its OWN emitter (C) — per-row I/O")
        XCTAssertEqual(s.cellAt(2, base + 2)?.inputReceiver, 2, "row 2 keeps its OWN door")
        let len = try XCTUnwrap(s.rowLen, "the multi-column ferry carries a per-row length")
        XCTAssertEqual(len[base + 0], 3, "row 0's loop reflects the pass length (3)")
        let lane = try XCTUnwrap(s.rowLane, "a ferry sets a per-row lane")
        XCTAssertEqual(lane[base + 0], 0, "multi-step SWEEPS 0..len-1 → no col-0 pin")
        // ferry 1 stays the pinned single cell, byte-identical to today.
        XCTAssertEqual(s.cellAt(0, base1)?.machineID, "solo", "the single-cell ferry is unchanged")
        XCTAssertEqual(lane[base1], 0b1, "single cell → pinned to col 0 (continuous)")
        // Unlike the old flatten model (which left rowLen nil for a single cell, relying solely on the rowLane pin),
        // the unified per-ferry clock-claim now ALSO sets rowLen=1 here (plan.count == partLen == 1) — redundant with,
        // but not in conflict with, the col-0 pin: both independently say "stay at column 0 forever."
        XCTAssertEqual(len[base1], 1, "a length-1 ferry's own row length lands too, alongside the col-0 pin")
    }
    // P1 (2026-08-30): when NO row is fully empty, the chain audition (PLAY THIS MIDI CHAIN) lays across the
    // least-occupied row's FREE columns and must SWEEP. The old code unconditionally pinned col 0 of that row —
    // which, when col 0 already holds another voice's cell, looped THAT cell and left the audition silent.
    func testChainAuditionFallbackSweepsInsteadOfPinningANonChainColumn() throws {
        let rowChain = Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry)   // machined → every diagonal cell sounds
        var i = stagingInput(cells: partGrid((0..<4).map { ($0, $0, "p\($0)") }), sel: Array(0..<4) + [-1, -1, -1, -1],
                              rowChain: rowChain)   // a DIAGONAL → every row occupied (occ 1), none full, col 0 held by "p0"
        i.chainActive = true; i.chainMachineID = "aud"; i.chainMachine = []
        let (sceneOpt, auditionRow) = BuildSceneLogic.composeSceneMeta(i)
        let s = try XCTUnwrap(sceneOpt)
        let row0 = Snap.ferryRowBase(0) + 0
        XCTAssertEqual(auditionRow, row0, "the least-occupied row (all tie → the block's first row)")
        XCTAssertEqual(s.cellAt(0, row0)?.machineID, "p0", "col 0 stays the staging cell")
        XCTAssertEqual(s.cellAt(1, row0)?.machineID, "aud", "the chain lays across the row's FREE columns")
        XCTAssertEqual(try XCTUnwrap(s.rowLane)[row0], 0, "P1: the fallback row is NOT pinned to col 0 → it sweeps (else the pin loops p0 and the audition is silent)")

        // CONTROL — a fully-empty row exists → the single-cell audition DOES pin col 0 (continuous, no re-strike).
        var j = stagingInput(cells: partGrid((0..<3).map { ($0, $0, "p\($0)") }),   // rows 0–2 occupied, ROW 3 empty
                              sel: Array(0..<3) + [-1, -1, -1, -1, -1], rowChain: rowChain)
        j.chainActive = true; j.chainMachineID = "aud"; j.chainMachine = []
        let (s2Opt, aud2) = BuildSceneLogic.composeSceneMeta(j)
        let s2 = try XCTUnwrap(s2Opt)
        let row3 = Snap.ferryRowBase(0) + 3
        XCTAssertEqual(aud2, row3, "the fully-empty row")
        XCTAssertEqual(s2.cellAt(0, row3)?.machineID, "aud", "the single cell parks at col 0 of the empty row")
        XCTAssertEqual(try XCTUnwrap(s2.rowLane)[row3], 0b1, "the single-cell audition pins col 0 → continuous")
    }
    // A multi-column ferry plays at its OWN captured rate (rowStepRate[ferryRowBase(t)+r], not the scene default), and
    // a row with no per-row I/O override falls back to the part default. Neither is asserted by the layout test above.
    // (Coverage gap 2026-08-30; re-based onto a ferry's own BuildPart 2026-09-27.)
    func testMultiStepPassAppliesItsOwnRateAndFallsBackIOToTheColumnDefault() throws {
        let part0 = ferryPart(cells: partGrid([(0, 0, "a"), (1, 0, "b")]), sel: [0, 0], rowChain: [[ProcessorSlot(type: .arp)], [], [], []],
                               rate: .r1_8, length: 2,   // the pass's OWN tempo
                               receiver: 3, emitters: [.b])   // PART default: door D(3) · emitter B — no per-row override, so both cells inherit it
        let part1 = ferryPart(cells: partGrid([(0, 0, "z")]), sel: [0], rowChain: [[ProcessorSlot(type: .arp)], [], [], []], length: 1)
        var i = BuildSceneLogic.Input()
        i.ferryOn = [true, true, false, false, false, false, false, false]
        i.ferryAudible = Array(repeating: true, count: Snap.ferries)
        i.ferryParts = Array(repeating: nil, count: Snap.ferries); i.ferryParts[0] = part0; i.ferryParts[1] = part1
        i.ferryRowChain = Array(repeating: [], count: Snap.ferries)
        i.ferryRowChain[0] = part0.rowChain; i.ferryRowChain[1] = part1.rowChain
        let s = BuildSceneLogic.composeScene(i)!
        let base = Snap.ferryRowBase(0), base1 = Snap.ferryRowBase(1)
        XCTAssertEqual(s.rowStepRate?[base], .r1_8, "the pass plays at its OWN captured rate at rowStepRate[ferryRowBase(t)]")
        XCTAssertNil(s.rowStepRate?[base1], "a single-cell ferry sets no per-row rate")
        XCTAssertEqual(s.cellAt(0, base)?.buses, [.b], "no per-row emitter override → falls back to the part default (B)")
        XCTAssertEqual(s.cellAt(1, base)?.buses, [.b], "both columns share row 0, so both inherit it")
        XCTAssertEqual(s.cellAt(0, base)?.inputReceiver, 3, "no per-row door override → falls back to the part default (D)")
    }
    // TWO same-machine ferries on DIFFERENT emitters get DISTINCT per-cell buses → distinct cables, so both sound (they
    // don't collide to one). Locks the flattened-pass emitter fix (Paul 2026-09-10 bug: re-pointing the 2nd play ferry's
    // emitter was silent → both stayed on the ORIGINAL emitter → identical output collided) — re-based onto ferries'
    // own BuildParts (2026-09-27), which is now the ONLY representation, so the bug class can't recur.
    func testTwoSameMachinePassesOnDifferentEmittersGetDistinctBuses() throws {
        let rowChain = [[ProcessorSlot(type: .arp)], [], [], []]
        let part0 = ferryPart(cells: partGrid([(0, 0, "m"), (1, 0, "m")]), sel: [0, 0], rowChain: rowChain, length: 2, emitters: [.a])
        let part1 = ferryPart(cells: partGrid([(0, 0, "m"), (1, 0, "m")]), sel: [0, 0], rowChain: rowChain, length: 2, emitters: [.c])   // the re-pointed one
        var i = BuildSceneLogic.Input()
        i.ferryOn = [true, true, false, false, false, false, false, false]
        i.ferryAudible = Array(repeating: true, count: Snap.ferries)
        i.ferryParts = Array(repeating: nil, count: Snap.ferries); i.ferryParts[0] = part0; i.ferryParts[1] = part1
        i.ferryRowChain = Array(repeating: [], count: Snap.ferries)
        i.ferryRowChain[0] = part0.rowChain; i.ferryRowChain[1] = part1.rowChain
        let s = BuildSceneLogic.composeScene(i)!
        let base = Snap.ferryRowBase(0), base1 = Snap.ferryRowBase(1)
        XCTAssertEqual(s.cellAt(0, base)?.machineID, "m")
        XCTAssertEqual(s.cellAt(0, base1)?.machineID, "m", "both ferries carry the SAME machine")
        XCTAssertEqual(s.cellAt(0, base)?.buses, [.a], "ferry 0 emits on A")
        XCTAssertEqual(s.cellAt(0, base1)?.buses, [.c], "ferry 1 emits on C (the re-pointed emitter) — NOT A → no collision")
        XCTAssertNotEqual(s.cellAt(0, base)?.buses, s.cellAt(0, base1)?.buses, "distinct cables → both are audible")
    }
    func testPlayGridAloneProducesASceneOnlyWhenAColumnIsStarted() {
        let part = ferryPart(cells: partGrid([(0, 0, "b1")]), sel: [0], rowChain: [[ProcessorSlot(type: .arp)], [], [], []], length: 1)
        var i = BuildSceneLogic.Input()
        i.ferryOn = [true, false, false, false, false, false, false, false]
        i.ferryAudible = Array(repeating: true, count: Snap.ferries)
        i.ferryParts = Array(repeating: nil, count: Snap.ferries); i.ferryParts[0] = part
        i.ferryRowChain = Array(repeating: [], count: Snap.ferries); i.ferryRowChain[0] = part.rowChain
        XCTAssertNotNil(BuildSceneLogic.composeScene(i), "a started ferry alone produces a scene")
        i.ferryOn[0] = false
        XCTAssertNil(BuildSceneLogic.composeScene(i), "no started ferry → no scene")
    }

    // A MACHINE-LESS cell is SILENT (Paul 2026-08-26) — the user only selected it, no output until a machine is added.
    // FERRY ROW UNIFICATION (Paul 2026-09-27): this used to differ between the STAGING part grid (silent) and the
    // flattened PLAY GRID (an explicit-empty chain was a deliberate no-machine "live wire" passthrough). Unifying
    // every ferry onto ONE composition path means there is now only ONE rule — silent — for every ferry, active or
    // background alike; the old passthrough behaviour for a background ferry's machine-less cell is gone; renamed to
    // reflect that this is no longer a staging-vs-play-grid distinction.
    func testMachineLessCellIsSilentForEveryFerryActiveOrBackground() {
        let i = stagingInput(cells: partGrid([(0, 2, "gold")]), sel: [2, -1, -1, -1, -1, -1, -1, -1],
                              rowChain: Array(repeating: [], count: Snap.rowsPerFerry))   // no per-row variation → resolver passes [] (no-machine)
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertNil(s.cellAt(0, Snap.ferryRowBase(0) + 2), "a MACHINE-LESS cell is SILENT — the user hasn't set it up")

        let part = ferryPart(cells: partGrid([(0, 0, "gold")]), sel: [0], rowChain: [[], [], [], []], length: 1)   // a BACKGROUND ferry, same rule now
        var p = BuildSceneLogic.Input()
        p.ferryOn = [true, false, false, false, false, false, false, false]
        p.ferryAudible = Array(repeating: true, count: Snap.ferries)
        p.ferryParts = Array(repeating: nil, count: Snap.ferries); p.ferryParts[0] = part
        p.ferryRowChain = Array(repeating: [], count: Snap.ferries); p.ferryRowChain[0] = part.rowChain
        // The ferry is still ON (a scene is still produced, since composeScene's own top-level guard only checks
        // "is any ferry on", not "does anything actually sound") — but its one cell is silent.
        XCTAssertNil(BuildSceneLogic.composeScene(p)?.cellAt(0, Snap.ferryRowBase(0)), "a BACKGROUND ferry's machine-less cell is silent too, now")
    }

    func testPerRowIOOverridesTheDefaultElseInherits() {
        // PER-ROW I/O (Paul 2026-08-18): row 1 carries its OWN door + emitter; row 3 inherits the part default.
        // (a part only has Snap.rowsPerFerry(4) rows, 0...3.)
        let i = stagingInput(cells: partGrid([(0, 1, "gold"), (1, 3, "teal")]), sel: [1, 3, -1, -1, -1, -1, -1, -1],
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry),   // machined → the cells sound (a machine-less part cell is silent, Paul 2026-08-26)
                              receiver: 0, emitters: [.a],                          // part DEFAULT: door R1 · emitter A
                              rowReceiver: [nil, 2, nil, nil],                      // row 1 → door R3
                              rowEmitters: [[.a], [.c], [.a], [.a]])                // row 1 → emitter C
        let s = BuildSceneLogic.composeScene(i)!
        let row1 = Snap.ferryRowBase(0) + 1, row3 = Snap.ferryRowBase(0) + 3
        XCTAssertEqual(s.cellAt(0, row1)?.inputReceiver, 2, "row 1 uses its OWN door")
        XCTAssertEqual(s.cellAt(0, row1)?.buses, [.c], "row 1 uses its OWN emitter")
        XCTAssertEqual(s.cellAt(1, row3)?.inputReceiver, 0, "row 3 inherits the part default door")
        XCTAssertEqual(s.cellAt(1, row3)?.buses, [.a], "row 3 inherits the part default emitters")
    }

    func testChainAuditionIsAOneStepContinuousPass() throws {
        // SELECT audition = a 1-step CONTINUOUS pass (Paul 2026-08-29: no re-striking per step). It parks at COLUMN 0 of a
        // fully-empty row and loops that row to column 0 — NOT laid across all 8 columns (which re-triggered every step).
        var i = BuildSceneLogic.Input()
        i.chainActive = true
        i.chainMachineID = "cyan"
        i.chainMachine = []                                // raw passthrough
        // no ferries on at all — the audition still needs an activeFerry to park in (mirrors a ferry always being
        // selected in real use, per buildActiveFerry's "always one selected" invariant).
        i.activeFerry = 0
        let s = BuildSceneLogic.composeScene(i)!
        let row0 = Snap.ferryRowBase(0) + 0
        XCTAssertEqual(s.cellAt(0, row0)?.machineID, "cyan", "the audition parks at column 0 of the empty row")
        XCTAssertNil(s.cellAt(1, row0), "NOT laid across the other columns — it's continuous, not re-struck each step")
        XCTAssertEqual(s.cellAt(0, row0)?.processors, [], "explicit empty chain (born-audible passthrough), never nil")
        let lane = try XCTUnwrap(s.rowLane, "the audition sets a per-row lane")
        XCTAssertEqual(lane[row0], 0b1, "the row loops column 0 → continuous")
    }

    func testComposeSceneMetaReportsTheAuditionRow() {
        // #5 (Paul 2026-08-30): composeSceneMeta exposes the engine ROW the audition parked on so the aimed ferry can read
        // its LIVE strike feed at idx = col0*Snap.rows + auditionRow. It must equal where the audition cell actually lands.
        var i = stagingInput(cells: partGrid([(0, 0, "gold")]), sel: [0, -1, -1, -1, -1, -1, -1, -1],   // staging on row 0 → the audition takes the next free row (1)
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry))
        i.chainActive = true; i.chainMachineID = "cyan"
        let m = BuildSceneLogic.composeSceneMeta(i)
        let ar = m.auditionRow
        XCTAssertEqual(ar, Snap.ferryRowBase(0) + 1, "the audition parks on the first free row (row 0 taken by staging)")
        XCTAssertEqual(m.scene?.cellAt(0, ar ?? -1)?.machineID, "cyan", "auditionRow points at the audition cell (col 0)")
        // No chain voice ⇒ no audition row.
        let j = stagingInput(cells: partGrid([(0, 0, "gold")]), sel: [0, -1, -1, -1, -1, -1, -1, -1],
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry))
        XCTAssertNil(BuildSceneLogic.composeSceneMeta(j).auditionRow, "no chain voice → no audition row")
    }

    func testComposeSceneMetaFallbackStillExposesARow() {
        // Paul 2026-08-30: when NO row is fully empty (staging occupies every row), the audition takes the
        // FALLBACK branch — which must STILL expose a chainLaneRow, else the aimed ferry has no live-strike index and reads
        // as dead (the "subsequent copies didn't animate" bug locus).
        var i = stagingInput(cells: partGrid((0..<4).map { ($0, $0, "gold") }), sel: Array(0..<4) + [-1, -1, -1, -1],   // a DIAGONAL → every row occupied, none fully empty
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry))
        i.chainActive = true; i.chainMachineID = "cyan"
        XCTAssertNotNil(BuildSceneLogic.composeSceneMeta(i).auditionRow, "the fallback still exposes a row for the ferry's live feed")
    }

    // EUCLIDEOUS (Paul 2026-10-05): ALWAYS composes into its own reserved Snap.euclideousRow, independent of
    // any ferry — these lock in the two specific guard-edits the plan's own validation pass caught (both are
    // easy to miss: a function that already early-returns before reaching new code, and a publish condition
    // keyed on OTHER voices being active).
    func testEuclideousComposesWithZeroFerriesActive() {
        // The function's own OPENING guard (`anyFerryOn || i.chainActive`) would otherwise return (nil, nil)
        // before any Euclideous-specific code even runs, when Euclideous is the ONLY active thing.
        var i = BuildSceneLogic.Input()
        i.euclideousOn = true
        i.euclideousMachineID = "cyan"
        i.euclideousChain = []
        let s = BuildSceneLogic.composeScene(i)
        XCTAssertNotNil(s, "Euclideous alone (no ferry, no chain audition) must still compose a scene")
        XCTAssertEqual(s?.cellAt(0, Snap.euclideousRow)?.machineID, "cyan", "the Euclideous cell lands at column 0 of its own reserved row")
    }
    func testEuclideousRowIsGenuinelyPinned() {
        // The `rowLane` PUBLISH guard (`s.rowLane = rowLane`) is gated on OTHER voices being active
        // (stagingLane/playLane/anyFerryOn/chainLaneRow) — without `|| i.euclideousOn` added there too, the pin
        // set earlier in the function is computed but never actually PUBLISHED, so the row would fall back to
        // sweeping on whatever the ephemeral global lap key happens to be, instead of staying pinned.
        var i = BuildSceneLogic.Input()
        i.euclideousOn = true
        i.euclideousMachineID = "cyan"
        let s = BuildSceneLogic.composeScene(i)!
        let lane = try! XCTUnwrap(s.rowLane, "Euclideous alone must still publish a rowLane array")
        XCTAssertEqual(lane[Snap.euclideousRow], 0b1, "the row loops column 0 → a genuine 1-step continuous pin")
    }
    func testEuclideousCoexistsWithAnActiveFerry() {
        // Euclideous's reserved row must compose alongside a normal, independently-active ferry — neither
        // should affect the other's cell placement or rowLane entry.
        var i = stagingInput(cells: partGrid([(0, 0, "gold")]), sel: [0, -1, -1, -1, -1, -1, -1, -1],
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry))
        i.euclideousOn = true
        i.euclideousMachineID = "cyan"
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.cellAt(0, Snap.euclideousRow)?.machineID, "cyan", "Euclideous still composes at its own row")
        XCTAssertEqual(s.cellAt(0, Snap.ferryRowBase(0))?.machineID, "gold", "the active ferry's own staging content is unaffected")
        let lane = try! XCTUnwrap(s.rowLane)
        XCTAssertEqual(lane[Snap.euclideousRow], 0b1, "Euclideous's row stays pinned even with a ferry also active")
    }

    func testChainFallsBackToTheLeastOccupiedRowWhenPieceIsFull() {
        // PIECE (many cells per row) is gone; staging places at most ONE cell per column, so "one row far MORE
        // occupied than the rest, none empty" can no longer be constructed directly. The tied-occupancy diagonal
        // (every row exactly 1) exercises the same fallback-fill mechanism instead: the chain fills every OTHER
        // column of its landing row, leaving that row's own pre-existing cell untouched.
        var i = stagingInput(cells: partGrid((0..<4).map { ($0, $0, "gold") }), sel: Array(0..<4) + [-1, -1, -1, -1],   // a DIAGONAL → every row occupied exactly once, none empty
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry))
        i.chainActive = true; i.chainMachineID = "cyan"
        let s = BuildSceneLogic.composeScene(i)!
        let row0 = Snap.ferryRowBase(0) + 0
        XCTAssertEqual(s.cellAt(0, row0)?.machineID, "gold", "the fallback row's own pre-existing cell survives")
        XCTAssertEqual(s.cellAt(1, row0)?.machineID, "cyan", "the chain fills that row's OTHER free columns")
    }

    func testPartAndChainCoexist() {
        // PIECE (the third voice this test originally coexisted with) is gone — this now covers the remaining
        // two-voice coexistence: the part audition alongside the raw chain audition, on different rows.
        var i = stagingInput(cells: partGrid([(0, 3, "teal")]), sel: [3, -1, -1, -1, -1, -1, -1, -1],   // part on row 3
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry))   // machined → the part cell sounds
        i.chainActive = true; i.chainMachineID = "cyan"     // chain finds a free row (not 3)
        let s = BuildSceneLogic.composeScene(i)!
        let row3 = Snap.ferryRowBase(0) + 3
        XCTAssertEqual(s.cellAt(0, row3)?.machineID, "teal", "part plays")
        let chainRow = (Snap.ferryRowBase(0)..<(Snap.ferryRowBase(0) + Snap.rowsPerFerry)).first { r in r != row3 && s.cellAt(0, r)?.machineID == "cyan" }
        XCTAssertNotNil(chainRow, "the chain lands on some free row, coexisting with the part")
    }
    // MARK: composeScene — the PER-PART CLOCK + PER-ROW LAP mapping (Input → SceneState.rowStepRate/rowLen/rowLane)

    func testStagingAppliesItsOwnLengthEvenWhenRateIsDefault() {
        // BUG (Paul 2026-08-19), preserved post-PIECE: a row's per-row LENGTH must land even when its rate is the
        // SCENE-DEFAULT (nil) — both are set unconditionally together, never gated on the rate being non-nil.
        let i = stagingInput(cells: partGrid([(0, 2, "gold")]), sel: [2, -1, -1, -1, -1, -1, -1, -1],
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry),
                              length: 4)                            // default rate, short length
        let s = BuildSceneLogic.composeScene(i)!
        let row2 = Snap.ferryRowBase(0) + 2
        XCTAssertNil(s.rowStepRate?[row2], "the default rate lands as nil (scene default), not skipped")
        XCTAssertEqual(s.rowLen?[row2], 4, "the short length still lands alongside the default rate")
    }

    func testUniformStagingLeavesPerRowClockNil() {
        // No custom rate/length ⇒ no per-row clock at all → the Router keeps its uniform fast path.
        let i = stagingInput(cells: partGrid([(0, 0, "gold")]), sel: [0, -1, -1, -1, -1, -1, -1, -1])
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertNil(s.rowStepRate, "uniform staging → no per-row clock (fast path preserved)")
        XCTAssertNil(s.rowLen)
    }

    func testStagingLanePropagatesToItsOccupiedRow() {
        // PIECE (the row-lane precedence this once tested) is gone; staging is now the sole contributor to a
        // row's loop mask — confirms its own lane still lands on the row it occupies.
        var i = stagingInput(cells: partGrid([(1, 2, "teal")]), sel: [-1, 2, -1, -1, -1, -1, -1, -1],   // staging on row 2
                              rowChain: Array(repeating: [ProcessorSlot(type: .arp)], count: Snap.rowsPerFerry))
        i.stagingLane = 0b10
        let s = BuildSceneLogic.composeScene(i)!
        XCTAssertEqual(s.rowLane?[Snap.ferryRowBase(0) + 2], 0b10, "staging's lane lands on the row it occupies")
        XCTAssertEqual(s.rowLane?[5] ?? 0, 0, "an untouched row carries no lane")
    }

    // MARK: loopColumnPlan + composeScene PART LOOP SELECTION (Paul 2026-09-26)

    func testLoopColumnPlanFallsBackToIdentityWhenEmpty() {
        let plan = BuildSceneLogic.loopColumnPlan([], length: 8)
        XCTAssertEqual(plan.count, 8, "no selection ⇒ play the whole part")
        XCTAssertEqual((0..<8).map(plan.physicalColumn), Array(0..<8), "identity map when unset")
    }

    func testLoopColumnPlanPreservesAddedOrderNotSorted() {
        // The whole point: [3, 1, 5] must stay [3, 1, 5], NOT sort to [1, 3, 5].
        let plan = BuildSceneLogic.loopColumnPlan([3, 1, 5], length: 8)
        XCTAssertEqual(plan.count, 3)
        XCTAssertEqual([plan.physicalColumn(0), plan.physicalColumn(1), plan.physicalColumn(2)], [3, 1, 5])
    }

    func testLoopColumnPlanDropsOutOfRangeAndFallsBackIfAllInvalid() {
        // A column beyond the part's current length (e.g. the part was shortened after the loop was set) is dropped
        // silently, not a crash; if that empties the selection, fall back to full playback rather than going silent.
        let partial = BuildSceneLogic.loopColumnPlan([2, 99, 4], length: 8)
        XCTAssertEqual(partial.count, 2, "the out-of-range 99 is dropped")
        XCTAssertEqual([partial.physicalColumn(0), partial.physicalColumn(1)], [2, 4])
        let allInvalid = BuildSceneLogic.loopColumnPlan([50, 99], length: 8)
        XCTAssertEqual(allInvalid.count, 8, "every entry invalid ⇒ falls back to full playback, not silence")
        XCTAssertEqual((0..<8).map(allInvalid.physicalColumn), Array(0..<8))
    }

    // The defensive out-of-range clamp inside physicalColumn(i) — every real caller iterates 0..<plan.count by
    // construction, so this was previously unexercised (housekeeping survey finding, 2026-09-26). Confirms it never
    // traps and always returns a valid index, rather than trusting the clamp math by inspection alone.
    func testLoopColumnPlanPhysicalColumnClampsOutOfRangeIndices() {
        let plan = BuildSceneLogic.loopColumnPlan([3, 1, 5], length: 8)
        XCTAssertEqual(plan.physicalColumn(-1), plan.physicalColumn(0), "a negative index clamps to the first entry")
        XCTAssertEqual(plan.physicalColumn(plan.count + 5), plan.physicalColumn(plan.count - 1), "an over-range index clamps to the last entry")
    }

    func testComposeScenePlaysOnlySelectedColumnsInAddedOrder() {
        // Columns 3, 1, 5 each hold a distinct machine on row 2; a loop selection of [3, 1, 5] (deliberately NOT
        // ascending) must compose the scene's SEQUENTIAL columns 0, 1, 2 with THAT order's content — reproducing
        // exactly what plays, mirroring how every ferry composes now.
        let i = stagingInput(cells: partGrid([(3, 2, "m3"), (1, 2, "m1"), (5, 2, "m5")]),
                              sel: [-1, 2, -1, 2, -1, 2, -1, -1],
                              rowChain: (0..<Snap.rowsPerFerry).map { $0 == 2 ? [ProcessorSlot(type: .arp)] : [] },
                              loopCols: [3, 1, 5])
        let s = BuildSceneLogic.composeScene(i)!
        let row2 = Snap.ferryRowBase(0) + 2
        XCTAssertEqual(s.cellAt(0, row2)?.machineID, "m3", "logical step 0 plays the FIRST added column (3), not the lowest")
        XCTAssertEqual(s.cellAt(1, row2)?.machineID, "m1", "logical step 1 plays the SECOND added column (1)")
        XCTAssertEqual(s.cellAt(2, row2)?.machineID, "m5", "logical step 2 plays the THIRD added column (5)")
        XCTAssertNil(s.cellAt(3, row2), "columns beyond the selection's count are not written")
        XCTAssertEqual(s.rowLen?[row2], 3, "the row's effective length is the selection's count")
    }

    func testComposeSceneEmptyLoopSelectionIsByteIdenticalToUnset() {
        // No loop selection ⇒ every physical column plays at its OWN position (today's behaviour) — the feature must
        // be a true no-op when unused.
        let i = stagingInput(cells: partGrid([(0, 2, "a"), (1, 2, "b"), (2, 2, "c")]),
                              sel: [2, 2, 2, -1, -1, -1, -1, -1],
                              rowChain: (0..<Snap.rowsPerFerry).map { $0 == 2 ? [ProcessorSlot(type: .arp)] : [] })
        // loopCols left at its default ([])
        let s = BuildSceneLogic.composeScene(i)!
        let row2 = Snap.ferryRowBase(0) + 2
        XCTAssertEqual(s.cellAt(0, row2)?.machineID, "a")
        XCTAssertEqual(s.cellAt(1, row2)?.machineID, "b")
        XCTAssertEqual(s.cellAt(2, row2)?.machineID, "c")
        XCTAssertNil(s.rowLen, "no rate/length/loop customisation at all ⇒ no per-row clock (fast path preserved)")
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

        // 3. A REAL machine on SELECT (a browsed/ferried cell) → NOT grey; PART page → NEVER grey, play state = partActive.
        let realSel = BuildSceneLogic.machineBinding(selID: "c3", audID: aud, onSelectPage: true, chainActive: true,
                                                    partActive: false, selectedPlayCol: nil, playColOn: on)
        XCTAssertFalse(realSel.isGrey, "a real machine is never grey")
        let part = BuildSceneLogic.machineBinding(selID: aud, audID: aud, onSelectPage: false, chainActive: false,
                                                 partActive: true, selectedPlayCol: nil, playColOn: on)
        XCTAssertEqual(part.kind, .partRow); XCTAssertFalse(part.isGrey, "PART wears its machine, never grey"); XCTAssertTrue(part.playing)

        // 4. Nothing selected + nothing playing → .none.
        let none = BuildSceneLogic.machineBinding(selID: nil, audID: aud, onSelectPage: true, chainActive: false,
                                                 partActive: false, selectedPlayCol: nil, playColOn: on)
        XCTAssertEqual(none.kind, .none); XCTAssertFalse(none.playing)

        // 5. THE SELECT SOURCE (Paul 2026-09-06): a .ferryRow rides gsAud like a plain audition, but it carries a real machine
        //    (machineHueOverride[gsAud]) → must NOT be grey; a .browseCell on gsAud stays grey. Regression: tapping a ferry used
        //    to fall to grey because ferry + cell shared gsAud and the resolver couldn't tell them apart.
        let ferrySource = BuildSceneLogic.machineBinding(selID: aud, audID: aud, onSelectPage: true, chainActive: true,
                                                        partActive: false, selectedPlayCol: nil, playColOn: on, source: .ferryRow(3))
        XCTAssertFalse(ferrySource.isGrey, "a ferry source keeps its machine even while riding gsAud")
        let browseAud = BuildSceneLogic.machineBinding(selID: aud, audID: aud, onSelectPage: true, chainActive: true,
                                                      partActive: false, selectedPlayCol: nil, playColOn: on, source: .browseCell(4))
        XCTAssertTrue(browseAud.isGrey, "a plain browse-cell audition is still grey")

        // The sum type makes the ferry/cell exclusivity a type guarantee (was two Int? kept in sync by hand).
        XCTAssertEqual(BuildSceneLogic.SelectSource.ferryRow(3).ferryRow, 3)
        XCTAssertNil(BuildSceneLogic.SelectSource.ferryRow(3).browseCell)
        XCTAssertTrue(BuildSceneLogic.SelectSource.ferryRow(3).isFerry)
        XCTAssertFalse(BuildSceneLogic.SelectSource.browseCell(4).isFerry)
    }

    // ── THE PART-GRID TAP CONTRACT (Paul 2026-09-04): an UNPOPULATED cell must ALWAYS be selectable (when no AUTO lane is
    // armed — a lane armed puts the grid in span-DRAW mode, handled UI-side). Locked here. ─────────────────────────────
    func testPartGridEmptyCellIsSelectable() {
        // a normal tap on an EMPTY cell (cid == nil) selects that rung — no population check
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 3, row: 5, currentRung: -1, cid: nil, selectedMachineID: "gold",
                                                   selectMode: false, firstTapOfGesture: true),
                       .selectRung(row: 5))
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 0, row: 2, currentRung: 6, cid: nil, selectedMachineID: nil,
                                                   selectMode: false, firstTapOfGesture: true),
                       .selectRung(row: 2))
    }
    func testPartGridTapSelectedRungDeselectsOnFirstTapButPaintsOnDrag() {
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 2, row: 5, currentRung: 5, cid: "gold", selectedMachineID: "gold",
                                                   selectMode: false, firstTapOfGesture: true),
                       .deselect)   // first tap on the current rung → column silent
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 2, row: 5, currentRung: 5, cid: "gold", selectedMachineID: "gold",
                                                   selectMode: false, firstTapOfGesture: false),
                       .selectRung(row: 5))   // dragging back over it keeps it (paint, not toggle-off)
    }
    func testPartGridSelectModeFocusesPopulatedExitsOnEmpty() {
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 1, row: 3, currentRung: -1, cid: "gold", selectedMachineID: "gold",
                                                   selectMode: true, firstTapOfGesture: true),
                       .focus(machineID: "gold"))
        XCTAssertEqual(BuildSceneLogic.partGridTap(col: 1, row: 3, currentRung: -1, cid: nil, selectedMachineID: "gold",
                                                   selectMode: true, firstTapOfGesture: true),
                       .exitSelectMode)
    }

    // ── SPAN-ONLY AUTOMATION (Paul 2026-09-04): a lane is a contiguous FROM→TO span that TILES across the row. ─────────
    func testAutoSpanTilesAcrossTheRow() {
        // gold ARP on row 0; a lane on the ARP's GATE (LENGTH), FROM 0.1 → TO 0.9, span start 0, length 4.
        var lane = AutoLane(); lane.slot = 0; lane.param = "gate"; lane.lo = 0.1; lane.hi = 0.9
        lane.spanStart = 0; lane.spanLen = 4
        let pa = PartAutoMachine(activeLane: 0, lanes: [lane])
        let chain = [ProcessorSlot(type: .arp)]
        func gateAt(_ col: Int) -> Double {
            let out = BuildSceneLogic.applyAuto(chain, machineID: "gold", col: col, row: 0, partAuto: ["gold": pa], partWidth: 8)
            return out[0].params.gate ?? -1
        }
        // within the first tile the ramp goes 0.1 → 0.9 across cols 0…3, then REPEATS at col 4
        XCTAssertEqual(gateAt(0), 0.1, accuracy: 1e-9)   // rank 0 → FROM
        XCTAssertEqual(gateAt(3), 0.9, accuracy: 1e-9)   // rank 3 → TO
        XCTAssertEqual(gateAt(4), 0.1, accuracy: 1e-9)   // tile repeats
        XCTAssertEqual(gateAt(7), 0.9, accuracy: 1e-9)
    }
    func testAutoSpanStartOffsetLeavesEarlierColumnsUntouched() {
        var lane = AutoLane(); lane.slot = 0; lane.param = "gate"; lane.lo = 0.2; lane.hi = 0.8
        lane.spanStart = 2; lane.spanLen = 4
        let pa = PartAutoMachine(activeLane: 0, lanes: [lane])
        let base = [ProcessorSlot(type: .arp)]
        let before = BuildSceneLogic.applyAuto(base, machineID: "gold", col: 1, row: 0, partAuto: ["gold": pa], partWidth: 8)
        XCTAssertEqual(before, base, "columns before the span start are untouched")
        let at = BuildSceneLogic.applyAuto(base, machineID: "gold", col: 2, row: 0, partAuto: ["gold": pa], partWidth: 8)
        XCTAssertEqual(at[0].params.gate ?? -1, 0.2, accuracy: 1e-9, "the span begins at start → FROM")
    }
    func testAutoDefaultSpanIsOneSweepAcrossThePart() {
        // span-only defaults (spanStart/spanLen nil) ⇒ one sweep across the whole part width. (Endpoints in-range: gate clamps ≥0.05.)
        var lane = AutoLane(); lane.slot = 0; lane.param = "gate"; lane.lo = 0.1; lane.hi = 0.9
        let pa = PartAutoMachine(activeLane: 0, lanes: [lane])
        let chain = [ProcessorSlot(type: .arp)]
        func gateAt(_ col: Int) -> Double {
            BuildSceneLogic.applyAuto(chain, machineID: "gold", col: col, row: 0, partAuto: ["gold": pa], partWidth: 8)[0].params.gate ?? -1
        }
        XCTAssertEqual(gateAt(0), 0.1, accuracy: 1e-9)
        XCTAssertEqual(gateAt(7), 0.9, accuracy: 1e-9)   // len = partWidth 8 → one full sweep
    }
    func testAutoNoLaneIsByteIdentical() {
        let chain = [ProcessorSlot(type: .arp)]
        XCTAssertEqual(BuildSceneLogic.applyAuto(chain, machineID: "gold", col: 3, row: 0, partAuto: [:], partWidth: 8), chain)
    }
    func testAutoLaneSpanFieldsRoundTrip() throws {
        var lane = AutoLane(); lane.slot = 1; lane.param = "gate"; lane.lo = 0.1; lane.hi = 0.9; lane.spanStart = 3; lane.spanLen = 5
        let data = try JSONEncoder().encode(PartAutoMachine(activeLane: 0, lanes: [lane]))
        let back = try JSONDecoder().decode(PartAutoMachine.self, from: data)
        XCTAssertEqual(back.lanes.first?.spanStart, 3)
        XCTAssertEqual(back.lanes.first?.spanLen, 5)
    }
    func testAutoLaneMigratesLegacyCellsToASpan() throws {
        // an OLD lane persisted with a `cells` extent (cols 2…5, various rows) but no span fields → decode derives a span.
        // The encoding is col*Snap.rows+row (BuildModel.swift's AutoLane migration), so the raw indices depend on the
        // CURRENT Snap.rows — build them from (col,row) pairs rather than hardcoding stale numbers from an earlier
        // Snap.rows value (this migration is legacy-decode-only; only the column math is under test, not real old docs).
        func idx(_ col: Int, _ row: Int) -> Int { col * Snap.rows + row }
        let cells = [idx(2, 1), idx(3, 4), idx(5, 0), idx(5, 3)]
        let legacy = #"{"slot":0,"param":"gate","cells":\#(cells),"lo":0.1,"hi":0.9}"#
        let lane = try JSONDecoder().decode(AutoLane.self, from: Data(legacy.utf8))
        XCTAssertEqual(lane.spanStart, 2, "derived from the min column")
        XCTAssertEqual(lane.spanLen, 4, "min…max column span = cols 2…5 → length 4")
    }

    // MARK: - PLAY-GRID FERRY EDITING — Stage 1 model (Paul 2026-09-05)

    /// The 64-cell part store round-trips through Codable; an OLD doc (missing the key) decodes to nil.
    /// (`workingPart` was removed 2026-09-17 as an unread vestigial field.)
    func testPlayGridDataRoundTripsCellParts() throws {
        var g = BuildPlayGridData()
        var cell = BuildPart(); cell.selID = "gold"; cell.stagingCells[0][0] = "gold"
        var parts = Array(repeating: Array(repeating: BuildPart?.none, count: 8), count: 8)
        parts[3][4] = cell
        g.playCellPart = parts
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(BuildPlayGridData.self, from: data)
        XCTAssertEqual(back.playCellPart?[3][4]?.selID, "gold", "the part-backed cell round-trips")
        XCTAssertNil(back.playCellPart?[0][0] ?? nil, "an empty cell stays nil")
        // OLD doc: strip the new key → decode → nil (byte-identical, no throw).
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "playCellPart")
        let old = try JSONDecoder().decode(BuildPlayGridData.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.playCellPart)
    }
    /// THE PLAY FERRIES ARE PARTS — Phase 1 (Paul 2026-09-08): the 8-slot `parts` round-trips through Codable; a doc with
    /// the legacy per-cell `playCellPart` but NO `parts` MIGRATES via `partsResolved` (each ferry column's first part-backed
    /// cell); a blank doc resolves to 8 empty slots. (No throw on a missing key — the CR-8 decode-tolerance class.)
    func testFerryPartsRoundTripAndMigrateFromCellParts() throws {
        var g = BuildPlayGridData()
        var p2 = BuildPart(); p2.selID = "ferry2"
        var slots = Array(repeating: BuildPart?.none, count: 8); slots[2] = p2
        g.parts = slots
        let back = try JSONDecoder().decode(BuildPlayGridData.self, from: try JSONEncoder().encode(g))
        XCTAssertEqual(back.parts?[2]?.selID, "ferry2", "the ferry part round-trips")
        XCTAssertNil(back.parts?[0] ?? nil, "an empty ferry stays nil")
        XCTAssertEqual(back.partsResolved[2]?.selID, "ferry2", "partsResolved returns the present parts")
        // MIGRATION: an old doc with per-cell playCellPart but no `parts` → derive per column
        var oldDoc = BuildPlayGridData()
        var cellParts = Array(repeating: Array(repeating: BuildPart?.none, count: 8), count: 8)
        var cp = BuildPart(); cp.selID = "col5row3"; cellParts[5][3] = cp
        oldDoc.playCellPart = cellParts
        XCTAssertNil(oldDoc.parts, "no explicit ferry parts on the old doc")
        XCTAssertEqual(oldDoc.partsResolved[5]?.selID, "col5row3", "migrates the column's first part-backed cell into its ferry slot")
        XCTAssertNil(oldDoc.partsResolved[0], "a column with no part-backed cell migrates to an empty ferry")
        // BLANK: neither field → 8 empty slots
        let blank = BuildPlayGridData()
        XCTAssertEqual(blank.partsResolved.count, 8)
        XCTAssertTrue(blank.partsResolved.allSatisfy { $0 == nil })
    }
    /// EMPTY-FERRY COLOUR ALLOCATION (Paul 2026-09-12): the per-slot displaced-colour map round-trips; an old doc (no key) → nil.
    func testFerryHueAllocRoundTrips() throws {
        var g = BuildPlayGridData()
        g.ferryHueAlloc = [2: 0x112233, 5: 0x445566]
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(BuildPlayGridData.self, from: data)
        XCTAssertEqual(back.ferryHueAlloc?[2], 0x112233)
        XCTAssertEqual(back.ferryHueAlloc?[5], 0x445566)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "ferryHueAlloc")
        let old = try JSONDecoder().decode(BuildPlayGridData.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.ferryHueAlloc, "an old doc with no ferryHueAlloc decodes to nil, no throw")
    }
    /// COMMITTED SELECT CELLS (Paul 2026-09-12): the pinned chain + hue + name maps round-trip; an old doc (no keys) → nil.
    func testGridSelOverridesRoundTrip() throws {
        var g = BuildPlayGridData()
        g.gridSelChains = [3: [ProcessorSlot(type: .arp)]]
        g.gridSelHues = [3: 0xAB12CD]
        g.gridSelNames = [3: "wubz"]
        let data = try JSONEncoder().encode(g)
        let back = try JSONDecoder().decode(BuildPlayGridData.self, from: data)
        XCTAssertEqual(back.gridSelChains?[3]?.first?.type, .arp)
        XCTAssertEqual(back.gridSelHues?[3], 0xAB12CD)
        XCTAssertEqual(back.gridSelNames?[3], "wubz")
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        for k in ["gridSelChains", "gridSelHues", "gridSelNames"] { obj.removeValue(forKey: k) }
        let old = try JSONDecoder().decode(BuildPlayGridData.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.gridSelChains); XCTAssertNil(old.gridSelHues); XCTAssertNil(old.gridSelNames)
    }
    /// FERRY DROP HIT-TEST (Paul 2026-09-12): trash wins ties; else the containing ferry; else nil.
    func testFerryZoneAtTrashWinsThenFerries() {
        let zones: [FerryDropZone: CGRect] = [
            .ferry(0): CGRect(x: 0, y: 0, width: 50, height: 50),
            .ferry(1): CGRect(x: 50, y: 0, width: 50, height: 50),
            .trash:    CGRect(x: 40, y: 0, width: 50, height: 50),   // overlaps both ferries
        ]
        XCTAssertEqual(BuildSceneLogic.ferryZoneAt(CGPoint(x: 10, y: 10), zones: zones), .ferry(0))
        XCTAssertEqual(BuildSceneLogic.ferryZoneAt(CGPoint(x: 70, y: 10), zones: zones), .trash, "trash wins the overlap")
        XCTAssertNil(BuildSceneLogic.ferryZoneAt(CGPoint(x: 200, y: 200), zones: zones), "a miss → nil")
    }
    /// FERRY COLOUR SWAP (Paul 2026-09-12, generalised 2026-09-27): overwriting ferry `target` (oldHex) with a cell whose
    /// colour is held by some OTHER ferry — empty placeholder OR populated, the function no longer distinguishes — that
    /// ferry's index is returned (to receive oldHex). nil when not applicable.
    func testFerryColourDisplacement() {
        let old: UInt32 = 0xAAAAAA, cell: UInt32 = 0xBBBBBB
        var hex: [UInt32] = [old, 0x111111, 0x222222, cell, 0x444444, 0x555555, 0x666666, 0x777777]   // slot 3 holds the incoming colour
        XCTAssertEqual(BuildSceneLogic.ferryColourDisplacement(target: 0, cellHex: cell, oldHex: old, hex: hex), 3)
        XCTAssertNil(BuildSceneLogic.ferryColourDisplacement(target: 0, cellHex: old, oldHex: old, hex: hex), "no move when the displaced colour == the incoming colour")
        hex[3] = 0x333333
        XCTAssertNil(BuildSceneLogic.ferryColourDisplacement(target: 0, cellHex: cell, oldHex: old, hex: hex), "no other ferry holds the incoming colour → nil")
        hex[3] = cell
        XCTAssertEqual(BuildSceneLogic.ferryColourDisplacement(target: 0, cellHex: cell, oldHex: old, hex: hex), 3, "a POPULATED ferry holding the colour is chosen too — swapping doesn't care whether the other slot is empty or populated")
    }
    // SOURCE-CELL COMMIT (Paul 2026-09-29): a SELECT-cell → ferry drop names the SOURCE cell too — the FIRST name
    // sticks (a re-drop of an already-committed cell never renames it), an uncommitted cell takes the drop's fallback.
    func testFerryDropSourceNameFirstCommitWins() {
        XCTAssertEqual(BuildSceneLogic.ferryDropSourceName(existing: nil, fallback: "a1b2c3"), "a1b2c3", "uncommitted → takes the fallback")
        XCTAssertEqual(BuildSceneLogic.ferryDropSourceName(existing: "already-named", fallback: "a1b2c3"), "already-named", "already committed → keeps its OWN name, ignores the fallback")
    }
    // NAVIGATION (Paul 2026-09-29): a SELECT-cell → ferry drop only follows onto the PART grid when the target ferry
    // was ALREADY the focused one before the drop.
    func testFerryDropNavigatesOnlyWhenTargetWasAlreadyFocused() {
        XCTAssertTrue(BuildSceneLogic.ferryDropShouldNavigateToPart(targetWasAlreadyFocused: true))
        XCTAssertFalse(BuildSceneLogic.ferryDropShouldNavigateToPart(targetWasAlreadyFocused: false))
    }

    // PLAY-FERRY LAUNCH SETTINGS (Paul 2026-09-09): the per-ferry name/hue/launch fields round-trip through the document,
    // and an older save (missing keys) decodes to the resolved defaults — LOOP · LATCH · SYNC · choke OFF (CR-8 guard).
    func testFerryLaunchSettingsRoundTripAndDefault() throws {
        var p = BuildPart()
        p.ferryName = "BASSLINE"; p.ferryHue = 0x00FF88
        p.launchPlayback = .oneShot; p.launchTrigger = .spring; p.launchStart = .instant; p.chokeGroup = 3
        let back = try JSONDecoder().decode(BuildPart.self, from: try JSONEncoder().encode(p))
        XCTAssertEqual(back.ferryName, "BASSLINE")
        XCTAssertEqual(back.ferryHue, 0x00FF88)
        XCTAssertEqual(back.launchPlayback, .oneShot)
        XCTAssertEqual(back.launchTrigger, .spring)
        XCTAssertEqual(back.launchStart, .instant)
        XCTAssertEqual(back.chokeGroup, 3)
        // An OLD part JSON with none of the launch keys decodes to nil → the resolvers give today's behaviour.
        let old = try JSONDecoder().decode(BuildPart.self, from: Data(#"{"selID":"gold"}"#.utf8))
        XCTAssertNil(old.ferryName); XCTAssertNil(old.ferryHue); XCTAssertNil(old.chokeGroup)
        XCTAssertEqual(old.launchPlaybackResolved, .loop)
        XCTAssertEqual(old.launchTriggerResolved, .latch)
        XCTAssertEqual(old.launchStartResolved, .sync)
        XCTAssertEqual(old.chokeGroupResolved, 0)
        // The settings survive a whole-BuildPlayGridData round-trip on a ferry slot.
        var g = BuildPlayGridData(); var slots = Array(repeating: BuildPart?.none, count: 8); slots[4] = p; g.parts = slots
        let gback = try JSONDecoder().decode(BuildPlayGridData.self, from: try JSONEncoder().encode(g))
        XCTAssertEqual(gback.partsResolved[4]?.ferryName, "BASSLINE")
        XCTAssertEqual(gback.partsResolved[4]?.launchStart, .instant)
    }

    // PLAY-FERRY LAUNCH (Paul 2026-09-09, Phase 3): launching a ferry chokes only the OTHER currently-ON ferries sharing its
    // non-OFF choke group — not itself, not OFF ferries, not other groups, not the OFF (0/nil) group.
    func testChokeVictimsAreOtherOnFerriesInTheSameGroup() {
        func p(_ g: Int?) -> BuildPart { var x = BuildPart(); x.chokeGroup = g; return x }
        var parts = Array(repeating: BuildPart?.none, count: 8)
        parts[0] = p(1)    // the launching ferry (group 1)
        parts[1] = p(1)    // same group, ON  → choked
        parts[2] = p(1)    // same group, OFF → not choked
        parts[3] = p(2)    // other group, ON → not choked
        parts[4] = p(nil)  // OFF group, ON   → not choked
        let on = [true, true, false, true, true, false, false, false]
        XCTAssertEqual(BuildSceneLogic.chokeVictims(launching: 0, group: 1, parts: parts, on: on), [1],
                       "only OTHER, ON, same-non-OFF-group ferries are choked")
        XCTAssertEqual(BuildSceneLogic.chokeVictims(launching: 4, group: 0, parts: parts, on: on), [],
                       "an OFF (0) choke group chokes nothing")
    }
}
