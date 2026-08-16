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

    func testPianoLatchFlowsToSnapshot() {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.synthesizeReceiversIfNeeded()
        st.receivers![1].latchPiano = true
        st.receivers![1].pianoNotes = [60, 64, 67, 200, -3]   // out-of-range values are filtered
        let box = SnapshotBuilder.build(from: st)
        XCTAssertEqual(box.receiverPianoMask, 0b0010, "receiver 2 is in PIANO latch mode")
        XCTAssertEqual(box.receiverPianoNotes[1], [60, 64, 67], "the picked notes reach the box (out-of-range dropped)")
        XCTAssertEqual(box.receiverPianoMask & 1, 0, "R1 (default) is not PIANO")
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

    // LADDER: a DORMANT rung breaks the legato run — otherwise a full-8×8 ladder reads as one run from column 0
    // and each active rung's legato arp arrives badly phase-advanced (the "starts late / sounds random" bug).
    func testLadderDormantBreaksTheLegatoRun() {
        let cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        func build(ladder: Bool) -> SnapshotBox {
            var s = SceneState.empty()
            for c in 0..<8 { s.cells[c][0] = Cell(colourID: "gold", buses: [.a]); s.cells[c][1] = Cell(colourID: "gold", buses: [.a]) }
            s.activeRow = (0..<8).map { Optional($0 % 2 == 0 ? 0 : 1) }   // even cols → row 0 active, odd → row 1 active
            var st = PluginState(colours: cs, scenes: [s]); st.ladderMode = ladder
            return SnapshotBuilder.build(from: st)
        }
        XCTAssertEqual(build(ladder: false).cells[4 * 8 + 0].runStartColumn, 0, "no ladder → the row is ONE run from col 0")
        let on = build(ladder: true)
        XCTAssertEqual(on.cells[4 * 8 + 0].runStartColumn, 4, "ladder: the active rung (col 4, row 0) runs from its OWN column")
        XCTAssertEqual(on.cells[5 * 8 + 1].runStartColumn, 5, "ladder: the active rung (col 5, row 1) runs from its OWN column")
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
        // KEYS | CHORD (2026-08-03): the per-receiver mode packs into the box mask (bit i = receiver i in KEYS =
        // per-note toggle). KEYS is now the DEFAULT (nil ⇒ KEYS = bit set); CHORD is explicit (latchAdd = false).
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.receivers = [{ var r = Receiver(name: "1"); r.latchAdd = false; return r }(),   // explicit CHORD
                        Receiver(name: "2"),                                                // default ⇒ KEYS
                        { var r = Receiver(name: "3"); r.latchAdd = false; return r }(),   // explicit CHORD
                        Receiver(name: "4")]                                                // default ⇒ KEYS
        XCTAssertEqual(SnapshotBuilder.build(from: st).latchAddMask, 0b1010, "explicit CHORD clears the bit; default KEYS sets it")
        st.receivers = nil   // no receivers ⇒ four default doors ⇒ all KEYS
        XCTAssertEqual(SnapshotBuilder.build(from: st).latchAddMask, 0b1111, "default (nil) ⇒ all KEYS")
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

    // (CELL MACHINE: the A/B morph resolution tests — b/tier/glide/morphMaster — were REMOVED with the morph
    //  layer. The Colour's procB Codable fields still round-trip, tested below.)

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

    // The pool-aware append-only params flow ColourParams → SnapParams: chanceTilt clamps to −1…1; the booleans
    // (chanceDensity / arpFit / strumSpreadNorm) copy through. A missing builder copy would slip past every render test.
    func testPoolAwareParamsResolveAndClamp() {
        let sc = box(colours(customizing: 0) {
            $0.paramsA.chanceTilt = 5.0            // illegal → clamps to +1
            $0.paramsA.chanceDensity = true
            $0.paramsA.arpFit = true
            $0.paramsA.strumSpreadNorm = false
        }) { _ in }.colours[0]
        XCTAssertEqual(sc.a.chanceTilt, 1.0, "chanceTilt clamps to +1")
        XCTAssertTrue(sc.a.chanceDensity, "chanceDensity copies through")
        XCTAssertTrue(sc.a.arpFit, "arpFit copies through")
        XCTAssertFalse(sc.a.strumSpreadNorm, "strumSpreadNorm copies through")
        let neg = box(colours(customizing: 0) { $0.paramsA.chanceTilt = -5.0 }) { _ in }.colours[0]
        XCTAssertEqual(neg.a.chanceTilt, -1.0, "chanceTilt clamps to −1")
    }

    // The render thread's ONLY sanitization of the newer echo/euclid/glide/harmonize params — a wrong bound ships a bad
    // value straight into emission. The non-obvious ones: euclidSteps MIN is 2 (not 1), echoOffset is ±0.33. (coverage 2026-08-15)
    func testEchoEuclidGlideHarmResolveClamps() {
        let a = box(colours(customizing: 0) {
            $0.paramsA.euclidSteps = 1; $0.paramsA.euclidPulses = 0; $0.paramsA.euclidRot = 99
            $0.paramsA.echoDelayDiv = 0; $0.paramsA.echoOffset = 1.0; $0.paramsA.echoPitch = 99
            $0.paramsA.glideRange = 0; $0.paramsA.glideTime = 99
            $0.paramsA.harmIntervals = [30]
        }) { _ in }.colours[0].a
        XCTAssertEqual(a.euclidSteps, 2, "euclidSteps min is 2, not 1")
        XCTAssertEqual(a.euclidPulses, 1)
        XCTAssertEqual(a.euclidRot, 15)
        XCTAssertEqual(a.echoDelayDiv, 1)
        XCTAssertEqual(a.echoOffset, 0.33, accuracy: 1e-9, "echo offset ±0.33")
        XCTAssertEqual(a.echoPitch, 24)
        XCTAssertEqual(a.glideRange, 1)
        XCTAssertEqual(a.glideTime, 4, accuracy: 1e-9)
        XCTAssertEqual(a.harmIntervals.0, 24, "harm interval clamps to +24")
        XCTAssertEqual(a.harmIntervals.1, 0, "missing voices pad to 0")
        XCTAssertEqual(a.harmIntervals.2, 0)
        let hi = box(colours(customizing: 0) { $0.paramsA.euclidSteps = 99 }) { _ in }.colours[0].a
        XCTAssertEqual(hi.euclidSteps, 16, "euclidSteps max is 16")
    }

    // The 16-colour cap is lifted: the builder sizes its colour array to the document and resolves cells BY ID, so a
    // colour appended beyond the canonical 16 (a BUILD ephemeral colour) renders instead of being skipped. (2026-08-15)
    func testBuilderResolvesColourBeyondTheSixteen() {
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        var extra = Colour(colourID: "b1", type: .arp)
        extra.templateChain = [ProcessorSlot(type: .harmonize)]   // a distinctive machine on the 17th colour
        cs.append(extra)                                          // index 16 — beyond the fixed 16
        let b = box(cs) { s in s.cells[3][2] = Cell(colourID: "b1") }
        XCTAssertEqual(b.colours.count, 17, "the colour array sizes to the document, not a fixed 16")
        let cell = b.cells[3 * Snap.rows + 2]
        XCTAssertEqual(Int(cell.colourIndex), 16, "the appended colour resolves BY ID to index 16")
        XCTAssertEqual(cell.procs.first?.type, .harmonize, "its templateChain is applied — the cell is NOT skipped")
    }

    // A cell resolves its colour by the DOCUMENT-order index, NOT the canonical colourIDs position. With the colours
    // held OUT of canonical order, the old `colourIDs.firstIndex ?? …` lookup read the wrong SnapColour (a silent
    // wrong-machine bug latent behind any reorder). (Paul 2026-08-16)
    func testColourResolvesByDocumentOrderNotCanonicalPosition() {
        // Move "cyan" to document slot 0 (a real permutation — SWAP, so no duplicate colourID) and give it a distinct
        // machine. The old `colourIDs.firstIndex ?? …` lookup would read cyan's CANONICAL slot (wrong SnapColour).
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        let cyanIdx = colourIDs.firstIndex(of: "cyan")!             // cyan's canonical position
        cs.swapAt(0, cyanIdx)                                        // cyan → document slot 0; gold → cyan's old slot
        cs[0].templateChain = [ProcessorSlot(type: .harmonize)]     // cyan (now at slot 0) gets a distinctive machine
        let b = box(cs) { s in s.cells[0][0] = Cell(colourID: "cyan") }
        let cell = b.cells[0]
        XCTAssertEqual(Int(cell.colourIndex), 0, "the 'cyan' cell resolves to document slot 0, where cyan now lives")
        XCTAssertEqual(cell.procs.first?.type, .harmonize, "it reads cyan's machine by document order, not the canonical-index colour")
    }

    // MOD STEPS ingest: a <8-element pattern fills cyclically with a per-element 0…127 clamp; an EMPTY pattern is
    // guarded (keeps the default staircase). (coverage 2026-08-15)
    func testResolveModStepsWrapsClampsAndGuards() {
        let a = box(colours(customizing: 0) { $0.paramsA.modSteps = [200, -5, 50] }) { _ in }.colours[0].a
        XCTAssertEqual(a.modSteps, [127, 0, 50, 127, 0, 50, 127, 0], "cyclic fill of a 3-element pattern + clamp")
        let empty = box(colours(customizing: 0) { $0.paramsA.modSteps = [] }) { _ in }.colours[0].a
        XCTAssertEqual(empty.modSteps, [0, 18, 36, 54, 72, 90, 108, 127], "empty pattern → default staircase (guard skips)")
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

    // (grid-chaining retired: resolvedParent-from-inputRow tests removed — resolvedParent is always −1.)

    func testBusChannelsAndInputChannel() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.a]); c.inputChannel = 3; return c }()
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [s])
        d.busChannels = [5, 2, 99, 0]   // 99 and 0 are out of range → clamp to 16 / 1
        let b = SnapshotBuilder.build(from: d)
        XCTAssertEqual(b.busChannels, [5, 2, 16, 1])
        XCTAssertEqual(b.cells[0].inputChannel, 3)
    }

    /// SINGLE (LADDER) active-rung resolution (user 2026-08-05): no choice → topmost occupied; a chosen occupied
    /// rung → it; a chosen rung whose cell is now EMPTY → topmost (a stale preset curve never silences); ONLY an
    /// explicit −1 deselect → nothing; empty column → nothing.
    func testLadderActiveRowResolution() {
        var s = SceneState.empty()
        s.cells[0][2] = Cell(colourID: "gold"); s.cells[0][5] = Cell(colourID: "gold")
        XCTAssertEqual(s.ladderActiveRow(0), 2, "no choice → topmost occupied")
        s.activeRow = [Int?](repeating: nil, count: 8)
        s.activeRow?[0] = 5; XCTAssertEqual(s.ladderActiveRow(0), 5, "chosen occupied rung")
        s.activeRow?[0] = 3; XCTAssertNil(s.ladderActiveRow(0), "chosen rung EMPTY → nothing (user 2026-08-07: selecting an empty cell mutes the column)")
        s.activeRow?[0] = -1; XCTAssertNil(s.ladderActiveRow(0), "explicit deselect → nothing")
        XCTAssertNil(s.ladderActiveRow(1), "empty column → nothing")
    }

}
