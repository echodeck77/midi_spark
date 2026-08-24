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

    // PER-PART CLOCK (Paul 2026-08-19): the builder resolves each row's step + loop length from the scene's per-row
    // overrides, falling back to the scene default (uniform = today). Stage A — the box just CARRIES the values.
    func testPerRowClockResolvesElseFallsToGlobal() {
        let cs = colours(customizing: 0) { _ in }
        let b = box(cs) { $0.stepRate = .r1_2 }
        XCTAssertEqual(b.rowStep.count, Snap.rows)
        XCTAssertTrue(b.rowStep.allSatisfy { $0 == b.stepBeats }, "no override → every row uses the scene step")
        XCTAssertTrue(b.rowLength.allSatisfy { $0 == Snap.cols }, "no override → every row is a full 8")
        let b2 = box(cs) {
            $0.stepRate = .r1_2
            $0.rowStepRate = [nil, nil, nil, .r1_8, nil, nil, nil, nil]
            $0.rowLen = [nil, nil, nil, 4, nil, nil, nil, nil]
        }
        XCTAssertEqual(b2.rowStep[3], StepRate.r1_8.beats, "row 3 uses its OWN step")
        XCTAssertEqual(b2.rowStep[0], b2.stepBeats, "an unset row falls to the scene default")
        XCTAssertEqual(b2.rowLength[3], 4, "row 3 loops over 4 columns")
        XCTAssertEqual(b2.rowLength[0], Snap.cols, "an unset row is a full 8")
    }

    func testRowLenClampsOutOfRangeToOneThroughEight() {
        // The clamp is load-bearing: the Router multi-clock path divides by cyc = rowLength · rowStep, so a 0 would
        // yield NaN. A hostile/garbage decode of rowLen must resolve into 1…8. (Paul 2026-08-19)
        let cs = colours(customizing: 0) { _ in }
        let b = box(cs) { $0.rowLen = [0, 99, -3, nil, nil, nil, nil, nil] }
        XCTAssertEqual(b.rowLength[0], 1, "0 clamps up to 1")
        XCTAssertEqual(b.rowLength[1], Snap.cols, "99 clamps down to 8")
        XCTAssertEqual(b.rowLength[2], 1, "a negative clamps up to 1")
        XCTAssertEqual(b.rowLength[3], Snap.cols, "nil falls to a full 8")
    }

    // MULTI-CHANNEL (Paul 2026-08-21): a door can hear an arbitrary channel SUBSET; the mask resolves + packs into the box.
    func testChannelMaskResolvesFromLegacyAndExplicit() {
        var r = Receiver(name: "x")
        XCTAssertEqual(r.channelMaskResolved, 0xFFFF, "default (OMNI) → all channels")
        r.channel = 3; XCTAssertEqual(r.channelMaskResolved, 0b100, "single channel 3 → bit 2")
        r.channelMask = 0b10101; XCTAssertEqual(r.channelMaskResolved, 0b10101, "explicit mask wins (channels 1+3+5)")
        r.channelMask = 0; XCTAssertEqual(r.channelMaskResolved, 0, "explicit 0 = none")
    }
    func testMultiChannelSubsetPacksIntoTheBoxAndCell() {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [{ var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold"); s.cells[0][0]?.inputReceiver = 0; return s }()])
        st.receivers = [{ var r = Receiver(name: "1"); r.channelMask = 0b10101; return r }(), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]   // door 0 hears 1+3+5
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.receiverChannelMask[0], 0b10101, "the door's subset packs into the box")
        XCTAssertEqual(b.cells[0].inputChanMask, 0b10101, "the cell inherits the door's channel subset")
        // a plain OMNI door → 0xFFFF, byte-identical to before
        XCTAssertEqual(b.receiverChannelMask[1], 0xFFFF)
    }

    // THE CONFIG SHEETS (Paul 2026-08-20): the RACK has 4 CONFIGS; the render reads the ACTIVE config's membership.
    func testRackConfigResolvesToLegacyMaskWhenUnset() {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.rackEnabledMask = 0b0101                                  // legacy: emitters A + C in path
        XCTAssertEqual(st.rackConfigsResolved, [0b0101, 0b1111, 0b1111, 0b1111], "no configs → config 0 = the legacy mask, rest all-in")
        XCTAssertEqual(st.rackMaskResolved, 0b0101, "the active config (0) is the legacy mask")
        XCTAssertEqual(SnapshotBuilder.build(from: st).rackMask, 0b0101, "the box is byte-identical for an old doc")
    }
    func testActiveRackConfigDrivesTheRenderMask() {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.rackConfigs = [0b0001, 0b0010, 0b0100, 0b1000]; st.rackActiveConfig = 2
        XCTAssertEqual(st.rackMaskResolved, 0b0100)
        XCTAssertEqual(SnapshotBuilder.build(from: st).rackMask, 0b0100, "config 2 is live")
        st.rackActiveConfig = 0
        XCTAssertEqual(SnapshotBuilder.build(from: st).rackMask, 0b0001, "switching the live config switches the render mask")
        st.rackActiveConfig = 9
        XCTAssertEqual(st.rackActiveConfigResolved, 3, "an out-of-range active config clamps to 0…3")
    }
    // CR-9[review]: a short/long rackConfigs array (a truncated or forward-compat doc) must PAD/TRUNCATE to 4, not be
    // discarded wholesale — dropping it silently reverted every config to defaults (data-loss).
    func testRackConfigsShortOrLongArrayPadsNotDiscards() {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.rackEnabledMask = 0b0101
        st.rackConfigs = [0b0010, 0b0011]                          // only 2 present (a truncated doc)
        XCTAssertEqual(st.rackConfigsResolved, [0b0010, 0b0011, 0b1111, 0b1111], "the two real configs survive; the missing tail defaults")
        st.rackConfigs = [0b0001, 0b0010, 0b0100, 0b1000, 0b1111]  // 5 present (forward-compat doc)
        XCTAssertEqual(st.rackConfigsResolved, [0b0001, 0b0010, 0b0100, 0b1000], "extra trailing configs truncate to 4")
    }
    func testRackConfigsSurviveCodableRoundTrip() throws {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.rackConfigs = [0b0001, 0b0010, 0b0100, 0b1000]; st.rackActiveConfig = 2
        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(st))
        XCTAssertEqual(back.rackConfigs, [0b0001, 0b0010, 0b0100, 0b1000])
        XCTAssertEqual(back.rackActiveConfig, 2)
        XCTAssertEqual(back.rackMaskResolved, 0b0100)
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

    // MOD STEPS SPAN (Paul 2026-08-20): the box carries 8/16/32 breakpoints by SPAN (tiled from the stored steps);
    // the old cell|row modSpan migrates onto modStepSpan (byte-identical, 8 steps).
    func testModStepSpanPacksNStepsAndMigratesOldSpan() {
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[0].templateChain = [{ var s = ProcessorSlot(type: .mod); s.params.modSource = .steps; s.params.modStepSpan = .row2
                                 s.params.modSteps = [0, 10, 20, 30, 40, 50, 60, 70]; return s }()]
        let b = box(cs) { $0.cells[0][0] = Cell(colourID: colourIDs[0], buses: [.a]) }
        let p = b.cells[0].procs.first!
        XCTAssertEqual(p.modStepSpan, .row2)
        XCTAssertEqual(p.modSteps.count, 16, "ROW×2 packs 16 breakpoints")
        XCTAssertEqual(Array(p.modSteps.prefix(8)), [0, 10, 20, 30, 40, 50, 60, 70], "the first bar keeps the stored 8")
        XCTAssertEqual(Array(p.modSteps.suffix(8)), [0, 10, 20, 30, 40, 50, 60, 70], "the second bar tiles the 8 (default)")
        // MIGRATION: an old doc set modSpan=.row for STEPS + no modStepSpan → modStepSpan.row (still 8 steps).
        cs[1].templateChain = [{ var s = ProcessorSlot(type: .mod); s.params.modSource = .steps; s.params.modSpan = .row; return s }()]
        let m = box(cs) { $0.cells[0][0] = Cell(colourID: colourIDs[1], buses: [.a]) }
        XCTAssertEqual(m.cells[0].procs.first?.modStepSpan, .row, "old modSpan=.row migrates to modStepSpan=.row")
        XCTAssertEqual(m.cells[0].procs.first?.modSteps.count, 8, "ROW is 8 breakpoints (byte-identical)")
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

    // THE CONFIG SHEETS (Paul 2026-08-20): the door MODE reframes the 3 existing latch modes, behaviour-preserving.
    func testDoorModeDerivesFromLegacyLatchFields() {
        func mode(_ f: (inout Receiver) -> Void) -> DoorMode { var r = Receiver(name: "x"); f(&r); return r.doorModeResolved }
        XCTAssertEqual(mode { _ in }, .latch, "default (nil latch) ⇒ LATCH (the old KEYS default)")
        XCTAssertEqual(mode { $0.latchAdd = false }, .hold, "CHORD ⇒ HOLD")
        XCTAssertEqual(mode { $0.latchPiano = true }, .keys, "PIANO ⇒ KEYS")
        // the legacy resolvers are UNCHANGED for old docs (byte-identical)
        var chord = Receiver(name: "c"); chord.latchAdd = false
        XCTAssertFalse(chord.latchAddResolved); XCTAssertFalse(chord.latchPianoResolved)
        XCTAssertTrue(Receiver(name: "d").latchAddResolved, "nil ⇒ KEYS latch (true)")
    }
    func testExplicitDoorModeDrivesTheLatchResolvers() {
        func r(_ m: DoorMode) -> Receiver { var x = Receiver(name: "x"); x.doorMode = m; return x }
        XCTAssertTrue(r(.latch).latchAddResolved);   XCTAssertFalse(r(.latch).latchPianoResolved)
        XCTAssertFalse(r(.hold).latchAddResolved);   XCTAssertFalse(r(.hold).latchPianoResolved)
        XCTAssertFalse(r(.keys).latchAddResolved);   XCTAssertTrue(r(.keys).latchPianoResolved)
        XCTAssertFalse(r(.replay).latchAddResolved); XCTAssertFalse(r(.replay).latchPianoResolved)   // HOLD-like fallback until stage 3
    }
    func testDoorModeCodableRoundTrip() throws {
        var r = Receiver(name: "x"); r.doorMode = .keys
        let back = try JSONDecoder().decode(Receiver.self, from: try JSONEncoder().encode(r))
        XCTAssertEqual(back.doorMode, .keys)
        XCTAssertTrue(back.latchPianoResolved)
    }
    // REPLAY (config-sheets stage 3): the builder packs the REPLAY doors + their pass lengths into the box.
    func testReplayMaskAndPassesPackIntoTheBox() {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.receivers = [{ var r = Receiver(name: "1"); r.doorMode = .replay; r.replayPasses = 4; return r }(),
                        { var r = Receiver(name: "2"); r.doorMode = .latch; return r }(),
                        { var r = Receiver(name: "3"); r.doorMode = .replay; r.replayPasses = 2; return r }(),
                        Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.receiverReplayMask, 0b0101, "doors 1 + 3 are REPLAY")
        XCTAssertEqual(b.receiverReplayPasses[0], 4)
        XCTAssertEqual(b.receiverReplayPasses[2], 2)
        XCTAssertEqual(b.receiverReplayPasses[1], 1, "non-replay door defaults to 1")
        // REPLAY doors are NOT piano/keys-latch by construction (doorMode == .replay resolves both to false)
        XCTAssertEqual(b.receiverPianoMask & 0b0101, 0, "a REPLAY door is not a PIANO door")
    }
    // FILE (config-sheets stage 4): a FILE door's stored clip packs into the box (only when in FILE mode with a clip).
    func testFileClipPacksIntoTheBoxForAFileDoor() {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        let clip = [MidiFile.NoteEvent(beat: 0, note: 60, vel: 100, on: true), MidiFile.NoteEvent(beat: 1, note: 60, vel: 0, on: false)]
        st.receivers = [{ var r = Receiver(name: "1"); r.doorMode = .file; r.fileClip = clip; r.fileLoopBeats = 4; return r }(),
                        { var r = Receiver(name: "2"); r.doorMode = .replay; r.fileClip = clip; r.fileLoopBeats = 4; return r }(),   // FILE data but NOT file mode → ignored
                        Receiver(name: "3"), Receiver(name: "4")]
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.receiverFile[0].loopBeats, 4, "door 0 (FILE) carries its clip")
        XCTAssertEqual(b.receiverFile[0].notes, [60, 60])
        XCTAssertEqual(b.receiverFile[1].loopBeats, 0, "door 1 is REPLAY, not FILE → no clip packed")
        XCTAssertEqual(b.receiverFile[2].loopBeats, 0, "a plain door has no clip")
    }
    // STORAGE RECONCILE (config-sheets FILE, 2026-08-21): an imported .mid clip lives on the Receiver, so it must
    // survive a full-document save/load (fullState) AND rebuild into the box — else the loop is lost on reload.
    func testFileClipSurvivesDocumentRoundTripAndRebuilds() throws {
        var st = PluginState(colours: colours(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        let clip = [MidiFile.NoteEvent(beat: 0, note: 60, vel: 100, on: true),
                    MidiFile.NoteEvent(beat: 0.5, note: 64, vel: 90, on: true),
                    MidiFile.NoteEvent(beat: 1, note: 60, vel: 0, on: false),
                    MidiFile.NoteEvent(beat: 1, note: 64, vel: 0, on: false)]
        st.receivers = [{ var r = Receiver(name: "1"); r.doorMode = .file; r.fileClip = clip; r.fileLoopBeats = 2; r.fileName = "loop.mid"; return r }(),
                        Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        // save → load the WHOLE document (the fullState path)
        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(st))
        let r0 = back.receiversResolved[0]
        XCTAssertEqual(r0.doorMode, .file, "FILE mode persists")
        XCTAssertEqual(r0.fileClip, clip, "the decoded notes are byte-identical")
        XCTAssertEqual(r0.fileLoopBeats, 2)
        XCTAssertEqual(r0.fileName, "loop.mid", "the display name persists")
        // and the RESTORED document still packs the clip into the box (so the Kernel reloads the DoorRing on load)
        let b = SnapshotBuilder.build(from: back)
        XCTAssertEqual(b.receiverFile[0].loopBeats, 2)
        XCTAssertEqual(b.receiverFile[0].notes, [60, 64, 60, 64])
        XCTAssertEqual(b.receiverFile[0].beats, [0, 0.5, 1, 1])
    }
    func testReplayPassesClampToTheAllowedSet() {
        var r = Receiver(name: "x"); r.replayPasses = 7
        XCTAssertEqual(r.replayPassesResolved, 1, "an out-of-set value clamps to 1")
        r.replayPasses = 8; XCTAssertEqual(r.replayPassesResolved, 8)
        r.replayPasses = nil; XCTAssertEqual(r.replayPassesResolved, 1, "nil ⇒ 1")
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
