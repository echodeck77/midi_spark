//  PlayAsRowsAmendment1Tests.swift — PLAY AS ROWS Amendment 1 (2026-11-13): the NOTES tab tidy.
//
//  The pure layer's tests (§A12). Slice 1 covers test 1 (the one selection colour rule), test 5 (the REPEAT pop-up's
//  PASS = the §2 builder before SHIFT) and test 6 (the SHIFT badge visibility + text). Tests 2/3/4/7/8 (layout +
//  per-control looks) land with their slices.

import XCTest

final class PlayAsRowsAmendment1Tests: XCTestCase {

    // MARK: §A12 test 1 — the ONE selection colour rule (§A1.5)

    func testSelLookCoversEveryState() {
        // §A1.1 selected + on ⇒ lane fill, #1B1D22 ink.
        let onSel = euclideousNotesSelLook(selected: true, switchedOn: true, playing: false)
        XCTAssertEqual(onSel.fill, .lane); XCTAssertEqual(onSel.labelHex, 0x1B1D22); XCTAssertFalse(onSel.laneOutline)
        // §A1.4 selected + off ⇒ #33363D / #AAB0BA (idle-selected).
        let offSel = euclideousNotesSelLook(selected: true, switchedOn: false, playing: false)
        XCTAssertEqual(offSel.fill, .hex(0x33363D)); XCTAssertEqual(offSel.labelHex, 0xAAB0BA)
        // §A1.2 unselected ⇒ #24262C / #8D939D, whatever the switch.
        for on in [true, false] {
            let un = euclideousNotesSelLook(selected: false, switchedOn: on, playing: false)
            XCTAssertEqual(un.fill, .hex(0x24262C)); XCTAssertEqual(un.labelHex, 0x8D939D)
        }
        // §A1.3 the lane outline is drawn iff playing, in every state.
        for sel in [true, false] { for on in [true, false] { for play in [true, false] {
            XCTAssertEqual(euclideousNotesSelLook(selected: sel, switchedOn: on, playing: play).laneOutline, play)
        } } }
        // §A1.1 is reached only by selected + on (test 2's second clause: BASS off ⇒ no A1.1).
        XCTAssertNotEqual(offSel.fill, .lane)
        XCTAssertNotEqual(euclideousNotesSelLook(selected: false, switchedOn: true, playing: false).fill, .lane)
    }

    // MARK: §A12 test 5 — the PASS row is the §2 builder before SHIFT

    private func litOrder(_ ranks: [Int]) -> EuclideousLitOrder {
        var mask: UInt8 = 0; for r in ranks { mask |= 1 << UInt8(r - 1) }
        return .derived(litNotes: mask, top: false, top2: false)
    }
    /// count value v∈{1,2,3} packed as (v−1) at bits 2·(r−1).
    private func counts(_ pairs: [(Int, Int)]) -> UInt16 { var c: UInt16 = 0; for (r, v) in pairs { c |= UInt16(v - 1) << UInt16(2 * (r - 1)) }; return c }
    private func later(_ ranks: [Int]) -> UInt8 { var m: UInt8 = 0; for r in ranks { m |= 1 << UInt8(r - 1) }; return m }

    func testDisplayPassIsTheBuilderBeforeShift() {
        // A battery over the §2.6 shapes: plain, copies AGAIN, copies LATER (rounds), each key order, BOUNCE.
        let orders: [EuclideousOrderMode] = [.up, .down, .outsideIn, .insideOut, .asAdded, .bounce, .shuffle]
        let cases: [(lit: [Int], cnt: UInt16, s2: UInt8, s3: UInt8, bass: Bool)] = [
            ([1, 3, 5], 0, 0, 0, false),
            ([1, 3, 5], counts([(3, 2)]), 0, 0, false),               // rank 3 ×2 AGAIN
            ([1, 3, 5], counts([(3, 2)]), later([3]), 0, false),      // rank 3 ×2 LATER ⇒ a second round
            ([1, 2, 3, 4], counts([(2, 3), (4, 2)]), later([4]), later([2]), false),
            ([2, 4, 6], counts([(2, 3)]), later([2]), later([2]), true),   // bass on drops the lowest
        ]
        for order in orders {
            for c in cases {
                let lo = litOrder(c.lit)
                let rip = euclideousRowsRanksInPlay(litOrder: lo, bassOn: c.bass)
                for passIdx in [0, 1, 7] {
                    let want = euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: order, counts: c.cnt, secondLater: c.s2, thirdLater: c.s3,
                                                       passIndex: passIdx, lane: 2, shiftStart: 0, driftOn: false, driftStep: 0)
                    let got = euclideousRowsDisplayPass(litOrder: lo, bassOn: c.bass, order: order, counts: c.cnt, secondLater: c.s2, thirdLater: c.s3, lane: 2, passIndex: passIdx)
                    XCTAssertEqual(got.array, want.array, "order \(order) case \(c.lit) pass \(passIdx)")
                }
            }
        }
    }

    func testDisplayPassIgnoresShiftThatTheLineMightCarry() {
        // The pre-shift pass must differ from a SHIFTED build when start ≠ 0 — proving §A3.3 is "before SHIFT".
        let lo = litOrder([1, 2, 3, 4])
        let rip = euclideousRowsRanksInPlay(litOrder: lo, bassOn: false)
        let pre = euclideousRowsDisplayPass(litOrder: lo, bassOn: false, order: .up, counts: 0, secondLater: 0, thirdLater: 0, lane: 0, passIndex: 0)
        let shifted = euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: .up, counts: 0, secondLater: 0, thirdLater: 0, passIndex: 0, lane: 0, shiftStart: 1, driftOn: false, driftStep: 0)
        XCTAssertEqual(pre.array, [1, 2, 3, 4])
        XCTAssertEqual(shifted.array, [2, 3, 4, 1])
        XCTAssertNotEqual(pre.array, shifted.array)
    }

    func testRoundBreaksPartitionThePass() {
        let lo = litOrder([1, 3, 5])
        // all round 1 ⇒ no breaks
        XCTAssertEqual(euclideousRowsRoundBreaks(litOrder: lo, bassOn: false, order: .up, counts: counts([(3, 2)]), secondLater: 0, thirdLater: 0), [])
        // rank 3 ×2 LATER ⇒ round1 = [1,3,5] (3 entries), round2 = [3] ⇒ a break at 3
        let brk = euclideousRowsRoundBreaks(litOrder: lo, bassOn: false, order: .up, counts: counts([(3, 2)]), secondLater: later([3]), thirdLater: 0)
        XCTAssertEqual(brk, [3])
        let pass = euclideousRowsDisplayPass(litOrder: lo, bassOn: false, order: .up, counts: counts([(3, 2)]), secondLater: later([3]), thirdLater: 0, lane: 0, passIndex: 0)
        XCTAssertEqual(pass.array, [1, 3, 5, 3])
        // two breaks: rank 1 ×3 with copy 2 AGAIN (round 1) and copy 3 LATER (round 2); rank 2 ×2 LATER (round 2)
        let lo2 = litOrder([1, 2])
        let brk2 = euclideousRowsRoundBreaks(litOrder: lo2, bassOn: false, order: .up, counts: counts([(1, 3), (2, 2)]), secondLater: 0, thirdLater: later([1]))
        // round1: rank1 copy1+copy2(AGAIN), rank2 copy1+copy2(AGAIN) = 4; round2: rank1 copy3(LATER) = 1 ⇒ pass [1,1,2,2,1], break at 4
        XCTAssertEqual(brk2, [4])
        XCTAssertEqual(euclideousRowsDisplayPass(litOrder: lo2, bassOn: false, order: .up, counts: counts([(1, 3), (2, 2)]), secondLater: 0, thirdLater: later([1]), lane: 0, passIndex: 0).array, [1, 1, 2, 2, 1])
        // BOUNCE never shows breaks
        XCTAssertEqual(euclideousRowsRoundBreaks(litOrder: lo, bassOn: false, order: .bounce, counts: counts([(3, 2)]), secondLater: later([3]), thirdLater: 0), [])
    }

    // MARK: §A12 test 4 — the REPEAT pop-up's live/dead cells (dead cells ignore taps)

    func testRepeatCellLiveness() {
        let lo = litOrder([2, 5])   // ranks 2 and 5 lit
        let c = counts([(2, 3), (5, 2)])   // rank 2 ×3, rank 5 ×2
        // the header (row 0) is present for every rank, lit or not
        for r in 1...8 { XCTAssertTrue(euclideousRepeatCellLive(litOrder: lo, counts: c, rank: r, row: 0)) }
        // an unlit rank: every editable row is dead
        for row in 1...3 { XCTAssertFalse(euclideousRepeatCellLive(litOrder: lo, counts: c, rank: 1, row: row), "unlit rank 1 row \(row)") }
        // rank 2 (×3): ×, 2ND, 3RD all live
        XCTAssertTrue(euclideousRepeatCellLive(litOrder: lo, counts: c, rank: 2, row: 1))
        XCTAssertTrue(euclideousRepeatCellLive(litOrder: lo, counts: c, rank: 2, row: 2))
        XCTAssertTrue(euclideousRepeatCellLive(litOrder: lo, counts: c, rank: 2, row: 3))
        // rank 5 (×2): ×, 2ND live; 3RD dead
        XCTAssertTrue(euclideousRepeatCellLive(litOrder: lo, counts: c, rank: 5, row: 1))
        XCTAssertTrue(euclideousRepeatCellLive(litOrder: lo, counts: c, rank: 5, row: 2))
        XCTAssertFalse(euclideousRepeatCellLive(litOrder: lo, counts: c, rank: 5, row: 3))
        // a lit rank at ×1: × live, 2ND/3RD dead
        let lo2 = litOrder([3])
        XCTAssertTrue(euclideousRepeatCellLive(litOrder: lo2, counts: 0, rank: 3, row: 1))
        XCTAssertFalse(euclideousRepeatCellLive(litOrder: lo2, counts: 0, rank: 3, row: 2))
        XCTAssertFalse(euclideousRepeatCellLive(litOrder: lo2, counts: 0, rank: 3, row: 3))
    }

    // MARK: §A12 test 3 — only the playing chip has an outline; stopped → none

    func testOnlyThePlayingChipIsOutlined() {
        XCTAssertTrue(euclideousNotesChipOutlined(chipIndex: 2, activeChip: 2, playing: true))
        XCTAssertFalse(euclideousNotesChipOutlined(chipIndex: 1, activeChip: 2, playing: true))
        for i in 0..<4 { XCTAssertFalse(euclideousNotesChipOutlined(chipIndex: i, activeChip: i, playing: false), "stopped → chip \(i) no outline") }
        // the active chip comes from the engine's own cursor — it moves with the hit ordinal
        let chain = [EuclideousOrderChip(value: .up, hits: 2), EuclideousOrderChip(value: .down, hits: 2)]
        XCTAssertEqual(euclideousRowsActiveChip(chain, hits: { $0.hits }, hitOrdinal: 0), 0)
        XCTAssertEqual(euclideousRowsActiveChip(chain, hits: { $0.hits }, hitOrdinal: 2), 1)
        XCTAssertEqual(euclideousRowsActiveChip(chain, hits: { $0.hits }, hitOrdinal: 4), 0)   // loops
    }

    // MARK: §A12 test 6 — the SHIFT badge

    func testShiftBadgeVisibilityAndText() {
        XCTAssertFalse(euclideousShiftBadgeShown(start: 0, driftOn: false))
        XCTAssertTrue(euclideousShiftBadgeShown(start: 1, driftOn: false))
        XCTAssertTrue(euclideousShiftBadgeShown(start: 0, driftOn: true))
        XCTAssertTrue(euclideousShiftBadgeShown(start: 5, driftOn: true))
        XCTAssertEqual(euclideousShiftValueText(start: 3, driftOn: false, step: 1), "3")
        XCTAssertEqual(euclideousShiftValueText(start: 3, driftOn: true, step: 2), "3 · +2")
        XCTAssertEqual(euclideousShiftValueText(start: 1, driftOn: true, step: -2), "1 · -2")
    }
}
