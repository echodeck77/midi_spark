//  SnapshotBuilderTests.swift
//  Off-device tests for the document → SnapshotBox resolution (§7): sparse B-over-A merge,
//  enum → index mapping, LEGATO run-start precompute, and the parameter clamps.

import XCTest

final class SnapshotBuilderTests: XCTestCase {

    private func colours(customizing i: Int, _ f: (inout Colour) -> Void) -> [Colour] {
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        f(&cs[i])
        return cs
    }

    private func box(_ cs: [Colour], _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        return SnapshotBuilder.build(from: PluginState(colours: cs, scenes: [s]))
    }

    func testBusEnabledMaskFromDocument() {
        func mask(_ e: [Bool]?) -> UInt8 {
            var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
            st.busEnabled = e
            return SnapshotBuilder.build(from: st).busEnabledMask
        }
        XCTAssertEqual(mask(nil), 0b1111, "nil ⇒ all enabled (loader default)")
        XCTAssertEqual(mask([true, false, true, true]), 0b1101, "B disabled")
        XCTAssertEqual(mask([false, false, false, false]), 0b0000, "all disabled")
        XCTAssertEqual(mask([true, false]), 0b1101, "short array ⇒ missing entries enabled")
    }

    // MARK: - RECEIVERS (delta §9 item 11) — cell → receiver → SnapCell filter resolution

    func testReceiverChannelResolvesIntoSnapCellFilter() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(colourID: "gold"); c.inputReceiver = 1; return c }()   // subscribes R2
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [s])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2", channel: 5), Receiver(name: "3"), Receiver(name: "4")]
        let sc = SnapshotBuilder.build(from: st).cells[0]
        XCTAssertEqual(sc.inputChannel, 5, "R2's channel filter is stamped on the cell")
        XCTAssertEqual(sc.resolvedReceiver, 1)
    }

    func testMutedReceiverProducesMatchNothingFilter() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(colourID: "gold"); c.inputReceiver = 0; return c }()
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [s])
        st.receivers = [Receiver(name: "1", channel: 0, muted: true), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let sc = SnapshotBuilder.build(from: st).cells[0]
        XCTAssertGreaterThanOrEqual(sc.inputChannel, 17, "a muted receiver ⇒ match-nothing filter")
    }

    func testNoReceiversFallsBackToLegacyInputChannel() {
        // Parity: a doc with no receivers (pre-migration / a direct test build) keeps the per-cell filter.
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(colourID: "gold"); c.inputChannel = 4; return c }()
        let st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [s])   // receivers == nil
        XCTAssertEqual(SnapshotBuilder.build(from: st).cells[0].inputChannel, 4)
    }

    func testClaimEmitterMapsToSnapshot() {
        func claim(_ c: Int?) -> Int8 {
            var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
            st.claimEmitter = c
            return SnapshotBuilder.build(from: st).claimEmitter
        }
        XCTAssertEqual(claim(nil), -1, "nil ⇒ no claim")
        XCTAssertEqual(claim(0), 0, "emitter A claims")
        XCTAssertEqual(claim(3), 3, "emitter D claims")
        XCTAssertEqual(claim(9), -1, "out-of-range ⇒ no claim")
    }

    func testSnapshotTransposeFollowsActiveTypeAfterSwitch() {
        // End-to-end proof of the per-type isolation fix: the snapshot's transpose reflects the ACTIVE
        // type's own value, not a stash left over from a different type. (The render reads SnapColour
        // .transpose, so this is what the arp path actually adds to each note.)
        var cs = colours(customizing: 0) { $0.transpose = 5 }   // arp, transpose +5
        cs[0].switchType(to: .harmonize)                        // harmonize keeps its OWN transpose (0)
        let sc = box(cs) { _ in }.colours[0]
        XCTAssertEqual(sc.a.type, .harmonize)
        XCTAssertEqual(sc.transpose, 0, "snapshot uses HARMONIZE's transpose (0), not the stashed ARP +5")
        cs[0].switchType(to: .arp)                              // back to arp restores +5
        XCTAssertEqual(box(cs) { _ in }.colours[0].transpose, 5)
    }

    // MARK: - COLOUR-PAIR morph (delta §9 item 5) — b sourced from the partner, tier gates the resolve

    func testColourPairFullSourcesBFromPartnerAndGlides() {
        // A FULL pair (same type): b comes from the PARTNER Colour (not a retired paramsB), and morph
        // glides a→b — so t=1 adopts the partner's params.
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[0].paramsA.octaves = 1            // self
        cs[1].paramsA.octaves = 3            // partner (same type, differs)
        cs[0].altColour = 1
        let sc = box(cs) { _ in }.colours[0]
        XCTAssertEqual(sc.tier, .full)
        XCTAssertEqual(sc.a.octaves, 1)
        XCTAssertEqual(sc.b.octaves, 3, "b comes from the partner Colour")
        XCTAssertEqual(effectiveOctaves(sc, t: 1.0), 3, "morphing to the partner adopts its octaves")
    }

    func testColourPairSwapIsCrossTypeAndUnpairedIsNone() {
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[2].type = .passgate
        cs[3].type = .chance
        cs[2].altColour = 3
        let b = box(cs) { _ in }
        XCTAssertEqual(b.colours[2].tier, .swap, "different types ⇒ swap")
        XCTAssertEqual(b.colours[2].b.type, .chance, "b carries the partner's type")
        XCTAssertEqual(b.colours[0].tier, .none, "unpaired ⇒ none")
    }

    func testMorphMasterRetiredNoLongerAffectsResolve() {
        // delta §9 item 5: morphMaster (#300) is retired — the snapshot morph is the per-Colour value only.
        let cs = colours(customizing: 0) { $0.morph = 0.2 }
        var st = PluginState(colours: cs, scenes: [SceneState.empty()])
        st.morphMaster = 1.0                              // would have pushed morph→1 in the old model
        XCTAssertEqual(SnapshotBuilder.build(from: st).colours[0].morph, 0.2, accuracy: 1e-9)
    }

    func testUnpairedColourIgnoresLegacyParamsB() {
        // paramsB is retired: an unpaired Colour's b equals a even with a legacy paramsB set.
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[0].paramsA.octaves = 2
        cs[0].paramsB.octaves = 4            // legacy — must be ignored by the builder
        let sc = box(cs) { _ in }.colours[0]
        XCTAssertEqual(sc.tier, .none)
        XCTAssertEqual(sc.b.octaves, 2, "b == a; paramsB is not consulted")
    }

    func testEnumToIndexAndClamps() {
        let cs = colours(customizing: 0) {
            $0.paramsA.pattern = .down
            $0.paramsA.octaves = 9       // illegal → clamps to 4
            $0.transpose = 100           // → clamps to 24
        }
        let sc = box(cs) { _ in }.colours[0]
        XCTAssertEqual(sc.a.patternIndex, UInt8(ArpPattern.allCases.firstIndex(of: .down)!))
        XCTAssertEqual(sc.a.octaves, 4)
        XCTAssertEqual(sc.transpose, 24)
    }

    func testRunStartColumnForContiguousRun() {
        // §7 LEGATO precompute: a contiguous same-Colour run in one row shares the run's first column.
        let b = box(colours(customizing: 0) { _ in }) { s in
            s.cells[2][0] = Cell(colourID: "gold")
            s.cells[3][0] = Cell(colourID: "gold")
        }
        XCTAssertEqual(b.cells[2 * Snap.rows + 0].runStartColumn, 2)
        XCTAssertEqual(b.cells[3 * Snap.rows + 0].runStartColumn, 2)   // continues, not restarts
    }

    func testRunBreaksOnGap() {
        let b = box(colours(customizing: 0) { _ in }) { s in
            s.cells[2][0] = Cell(colourID: "gold")
            // column 3 empty → break
            s.cells[4][0] = Cell(colourID: "gold")
        }
        XCTAssertEqual(b.cells[2 * Snap.rows + 0].runStartColumn, 2)
        XCTAssertEqual(b.cells[4 * Snap.rows + 0].runStartColumn, 4)   // a gap restarts the run
    }

    func testBusMaskAndCellFlags() {
        let b = box(colours(customizing: 0) { _ in }) { s in
            s.cells[0][0] = Cell(colourID: "gold", buses: [.a, .c], alt: true)
        }
        let cell = b.cells[0]
        XCTAssertEqual(cell.busMask, 0b0101)   // A + C
        XCTAssertTrue(cell.alt)
        XCTAssertEqual(cell.colourIndex, 0)
    }

    func testEmptyCellIsMarkedEmpty() {
        let b = box(colours(customizing: 0) { _ in }) { _ in }
        XCTAssertLessThan(b.cells[0].colourIndex, 0)   // colourIndex < 0 = empty
    }

    // MARK: v3.0 graph-routing precompute (delta §1)

    func testResolvedParentFromInputRow() {
        let b = box(colours(customizing: 0) { _ in }) { s in
            s.cells[0][0] = Cell(colourID: "gold")                          // parent
            s.cells[0][1] = Cell(colourID: "gold", inputRow: 0)             // references row 0 (upward)
            s.cells[0][2] = Cell(colourID: "gold", inputRow: 5)             // references empty row → MIDI IN
            s.cells[0][3] = Cell(colourID: "gold", inputRow: 3)             // self-reference → MIDI IN
        }
        XCTAssertEqual(b.cells[0 * Snap.rows + 1].resolvedParent, 0)        // occupied target
        XCTAssertEqual(b.cells[0 * Snap.rows + 2].resolvedParent, -1)       // empty target → MIDI IN
        XCTAssertEqual(b.cells[0 * Snap.rows + 3].resolvedParent, -1)       // self → MIDI IN
        XCTAssertEqual(b.cells[0 * Snap.rows + 0].resolvedParent, -1)       // no inputRow → MIDI IN
    }

    func testDownwardReferenceIsLegal() {
        let b = box(colours(customizing: 0) { _ in }) { s in
            s.cells[0][0] = Cell(colourID: "gold", inputRow: 2)             // references BELOW itself
            s.cells[0][2] = Cell(colourID: "gold")
        }
        XCTAssertEqual(b.cells[0 * Snap.rows + 0].resolvedParent, 2)        // downward refs are legal
    }

    func testBusChannelsAndInputChannel() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputChannel = 3; return c }()
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [s])
        d.busChannels = [5, 2, 99, 0]   // 99 and 0 are out of range → clamp to 16 / 1
        let b = SnapshotBuilder.build(from: d)
        XCTAssertEqual(b.busChannels, [5, 2, 16, 1])
        XCTAssertEqual(b.cells[0].inputChannel, 3)
    }

}
