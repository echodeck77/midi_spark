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

    // delta §9 item 1: the builder carries each Colour's ON assignments onto its SnapColour (nil → unassigned).
    func testOnConfigResolvesOntoSnapColour() {
        var on = OnConfig()
        on.arrive = .morphDrift; on.driftMode = .pingpong; on.driftPct = 15; on.arriveEvery = 2
        on.sceneEntrance = true; on.entrancePass = 3
        let cs = colours(customizing: 2) { $0.on = on }
        let b = box(cs) { _ in }
        XCTAssertEqual(b.colours[2].on, on, "colour 2's ON assignments reach the snapshot verbatim")
        XCTAssertEqual(b.colours[0].on, OnConfig(), "an unassigned colour resolves to an empty OnConfig")
    }

    func testThruReceiverFlowsToSnapshot() {
        func thru(_ v: Int?) -> Int8 {
            var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
            st.thruReceiver = v
            return SnapshotBuilder.build(from: st).thruReceiver
        }
        XCTAssertEqual(thru(nil), 0, "nil ⇒ default R1")
        XCTAssertEqual(thru(2), 2, "the pip's receiver reaches the snapshot")
        XCTAssertEqual(thru(9), 3, "out-of-range clamps to R4")
    }

    // CELL MACHINE stage-3: 3-tier chain resolution — per-cell OVERRIDE → colour TEMPLATE → legacy A face.
    func testChainResolvesOverrideThenTemplateThenAFace() {
        let i = 2, cid = colourIDs[2]
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }   // A face = ARP
        cs[i].templateChain = [ProcessorSlot(type: .ratchet)]
        let follow = box(cs) { $0.cells[0][0] = Cell(colourID: cid, buses: [.a]) }   // no override → template
        XCTAssertEqual(follow.cells[0].procs.first?.type, .ratchet, "a following cell resolves the colour TEMPLATE")
        let over = box(cs) { $0.cells[0][0] = { var c = Cell(colourID: cid, buses: [.a]); c.processors = [ProcessorSlot(type: .strum)]; return c }() }
        XCTAssertEqual(over.cells[0].procs.first?.type, .strum, "a per-cell OVERRIDE wins over the template")
        let legacy = box(colourIDs.map { Colour(colourID: $0, type: .arp) }) { $0.cells[0][0] = Cell(colourID: cid, buses: [.a]) }
        XCTAssertEqual(legacy.cells[0].procs.first?.type, .arp, "no override, no template → the legacy A face")
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

    func testClaimMapsToSnapshot() {
        // Legacy single field derives the mask bit.
        func claimMask(_ c: Int?) -> UInt8 {
            var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
            st.claimEmitter = c
            return SnapshotBuilder.build(from: st).claimMask
        }
        XCTAssertEqual(claimMask(nil), 0, "nil ⇒ no claim")
        XCTAssertEqual(claimMask(0), 0b0001, "emitter A claims")
        XCTAssertEqual(claimMask(3), 0b1000, "emitter D claims")
        XCTAssertEqual(claimMask(9), 0, "out-of-range ⇒ no claim")
        // v2: an explicit MULTI-claim mask + per-claimant LEAK map straight through.
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.claimMask = 0b0110; st.claimLeak = [0, 40, 0, 0]
        let box = SnapshotBuilder.build(from: st)
        XCTAssertEqual(box.claimMask, 0b0110, "explicit mask maps through")
        XCTAssertEqual(box.claimLeak, [0, 40, 0, 0], "per-claimant leak maps through")
    }

    func testLatchAddMaskFromReceivers() {
        // TWO LATCH MODES: the per-receiver ADD flag packs into the box mask (bit i = receiver i toggles).
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.receivers = [Receiver(name: "1"),
                        { var r = Receiver(name: "2"); r.latchAdd = true; return r }(),
                        Receiver(name: "3"),
                        { var r = Receiver(name: "4"); r.latchAdd = true; return r }()]
        XCTAssertEqual(SnapshotBuilder.build(from: st).latchAddMask, 0b1010, "receivers 2 and 4 in ADD mode")
        st.receivers = nil   // no receivers ⇒ all CHORD (mask 0)
        XCTAssertEqual(SnapshotBuilder.build(from: st).latchAddMask, 0, "default (nil) ⇒ all CHORD")
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

    // MARK: - TWO-PROCESSOR morph (delta item 8) — b sourced from this Colour's OWN procB, tier gates resolve

    func testProcBFullSourcesBFromOwnProcBAndGlides() {
        // A FULL procB (same type as A): b comes from THIS Colour's procB, and morph glides a→b — so t=1
        // adopts procB's params.
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[0].paramsA.octaves = 1            // A face
        cs[0].typeB = .arp                   // procB, same type ⇒ FULL
        cs[0].paramsB.octaves = 3            // B face differs
        let sc = box(cs) { _ in }.colours[0]
        XCTAssertEqual(sc.tier, .full)
        XCTAssertEqual(sc.a.octaves, 1)
        XCTAssertEqual(sc.b.octaves, 3, "b comes from the Colour's own procB")
        XCTAssertEqual(effectiveOctaves(sc, t: 1.0), 3, "morphing to procB adopts its octaves")
    }

    func testProcBSwapIsCrossTypeAndBLessIsNone() {
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[2].type = .passgate
        cs[2].typeB = .chance                // procB is a different type ⇒ SWAP
        let b = box(cs) { _ in }
        XCTAssertEqual(b.colours[2].tier, .swap, "different types ⇒ swap")
        XCTAssertEqual(b.colours[2].b.type, .chance, "b carries procB's type")
        XCTAssertEqual(b.colours[0].tier, .none, "no procB (typeB nil) ⇒ none")
    }

    func testSparseProcBInheritsAViaFallback() {
        // procB is resolved with fallback A, so a field left unset on procB inherits the A face.
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[0].paramsA.gate = 0.9
        cs[0].typeB = .arp
        cs[0].paramsB.octaves = 2            // set octaves on B; gate left nil → should inherit A's 0.9
        cs[0].paramsB.gate = nil
        let sc = box(cs) { _ in }.colours[0]
        XCTAssertEqual(sc.b.octaves, 2)
        XCTAssertEqual(sc.b.gate, 0.9, accuracy: 1e-9, "sparse procB gate inherits A via fallback")
    }

    func testMorphMasterRetiredNoLongerAffectsResolve() {
        // delta §9 item 5: morphMaster (#300) is retired — the snapshot morph is the per-Colour value only.
        let cs = colours(customizing: 0) { $0.morph = 0.2 }
        var st = PluginState(colours: cs, scenes: [SceneState.empty()])
        st.morphMaster = 1.0                              // would have pushed morph→1 in the old model
        XCTAssertEqual(SnapshotBuilder.build(from: st).colours[0].morph, 0.2, accuracy: 1e-9)
    }

    func testBLessColourBEqualsAIgnoringStaleParamsB() {
        // B-less (typeB nil): b equals a even with a stale paramsB set (a pre-pair doc must stay inert).
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[0].paramsA.octaves = 2
        cs[0].paramsB.octaves = 4            // stale — B is sourced ONLY when typeB != nil
        let sc = box(cs) { _ in }.colours[0]
        XCTAssertEqual(sc.tier, .none)
        XCTAssertEqual(sc.b.octaves, 2, "b == a; procB not consulted when B-less")
    }

    func testProcBFieldsRoundTripThroughCodable() {
        // typeB/transposeB persist through a round-trip.
        var c = Colour(colourID: "gold", type: .arp)
        c.typeB = .ratchet; c.transposeB = 7
        let back = try! JSONDecoder().decode(Colour.self, from: try! JSONEncoder().encode(c))
        XCTAssertEqual(back.typeB, .ratchet)
        XCTAssertEqual(back.transposeBResolved, 7)
        XCTAssertTrue(back.hasProcB)
        // a B-less Colour (typeB/transposeB nil) encodes without those keys → decodes to the B-less default,
        // exactly as an old pre-item-8 doc would (the new fields are Optional; absent ⇒ nil/0).
        let bless = try! JSONDecoder().decode(Colour.self, from: try! JSONEncoder().encode(Colour(colourID: "teal", type: .arp)))
        XCTAssertNil(bless.typeB)
        XCTAssertEqual(bless.transposeBResolved, 0)
        XCTAssertFalse(bless.hasProcB)
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
