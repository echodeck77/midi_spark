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
    // (PLAY AS ROWS amend 2 §B6: the count-based display-pass battery, the round-break test and the ×/2ND/3RD cell-liveness
    //  test are retired — the pass builder, PASS = builder (§B6.5) and the role grid are covered by PlayAsRolesTests.)
    func testDisplayPassIgnoresShiftThatTheLineMightCarry() {
        // The pre-shift pass must differ from a SHIFTED build when start ≠ 0 — proving §A3.3 is "before SHIFT".
        let lo = litOrder([1, 2, 3, 4])
        let rip = euclideousRowsRanksInPlay(litOrder: lo, bassOn: false)
        let pre = euclideousRowsDisplayPass(litOrder: lo, bassOn: false, order: .up, roles: 0, lane: 0, passIndex: 0)
        let shifted = euclideousRowsBuildPass(asc: rip.asc, added: rip.added, order: .up, roles: 0, passIndex: 0, lane: 0, shiftStart: 1, driftOn: false, driftStep: 0)
        XCTAssertEqual(pre.array, [1, 2, 3, 4])
        XCTAssertEqual(shifted.array, [2, 3, 4, 1])
        XCTAssertNotEqual(pre.array, shifted.array)
    }

    // MARK: §A12 test 2 — WHEN / BASS selection colours (a lit segment A1.1; BASS off → neither A1.1)

    func testWhenBassSegmentColours() {
        // a WHEN segment (always "on") that is selected draws A1.1; unselected draws A1.2 (the view paints no fill over #24262C)
        XCTAssertEqual(euclideousNotesSelLook(selected: true, switchedOn: true, playing: false).fill, .lane)
        XCTAssertEqual(euclideousNotesSelLook(selected: false, switchedOn: true, playing: false).labelHex, 0x8D939D)
        // BASS off: the chosen choice is A1.4 (#33363D), NOT A1.1
        let bassOffChosen = euclideousNotesSelLook(selected: true, switchedOn: false, playing: false)
        XCTAssertEqual(bassOffChosen.fill, .hex(0x33363D))
        XCTAssertNotEqual(bassOffChosen.fill, .lane)
        // BASS on: the chosen choice is A1.1
        XCTAssertEqual(euclideousNotesSelLook(selected: true, switchedOn: true, playing: false).fill, .lane)
    }

    // MARK: §A12 test 8 — the tab-body dim (42 % once, never stacked)

    func testTabBodyDimNeverStacks() {
        XCTAssertEqual(euclideousNotesTabBodyOpacity(notesOn: false, shadowing: false, shadowDim: 0.18), 0.42)   // notes off → 42 %
        XCTAssertEqual(euclideousNotesTabBodyOpacity(notesOn: false, shadowing: true, shadowDim: 0.18), 0.42)    // both → still one 42 % (no stack)
        XCTAssertEqual(euclideousNotesTabBodyOpacity(notesOn: true, shadowing: true, shadowDim: 0.18), 0.18)     // only ANSWER-pause → its own
        XCTAssertEqual(euclideousNotesTabBodyOpacity(notesOn: true, shadowing: false, shadowDim: 0.18), 1.0)     // neither
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
