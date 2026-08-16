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
        let base = [ProcessorSlot(type: .arp)]          // an arp has continuous params (rate/octaves) whose nudge shifts the output
        let baseSig = Dice.signature(base)
        var rng = DiceRNG(seed: 7)
        guard let (mutated, run) = BuildSceneLogic.mutateChain(base, baseSig: baseSig, &rng) else {
            return XCTFail("mutate should find a distinct, audible variant of an arp")
        }
        XCTAssertFalse(run.sig.isEmpty, "the variant is NOT silent")
        XCTAssertNotEqual(run.sig, baseSig, "the variant sounds DIFFERENT from the source")
        XCTAssertEqual(mutated.count, base.count, "value-only: the chain structure (slot count) is unchanged")
        XCTAssertEqual(mutated.map(\.type), base.map(\.type), "value-only: the processor types are unchanged")
    }

    func testMutateReturnsNilForAnEmptyChain() {
        var rng = DiceRNG(seed: 1)
        XCTAssertNil(BuildSceneLogic.mutateChain([], baseSig: [], &rng), "no slots → nothing to tweak")
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
}
