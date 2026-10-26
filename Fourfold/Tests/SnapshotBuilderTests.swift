//  SnapshotBuilderTests.swift
//  Off-device tests for the document → SnapshotBox resolution (§7): sparse B-over-A merge,
//  enum → index mapping, LEGATO run-start precompute, and the parameter clamps.

import XCTest

final class SnapshotBuilderTests: XCTestCase {

    private func machines(customizing i: Int, _ f: (inout Machine) -> Void) -> [Machine] {
        var cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        f(&cs[i])
        return cs
    }

    private func box(_ cs: [Machine], _ build: (inout SceneState) -> Void) -> SnapshotBox {
        var s = SceneState.empty(); build(&s)
        return SnapshotBuilder.build(from: PluginState(machines: cs, scenes: [s]))
    }

    // IGNORE ALL-NOTES-OFF (Paul 2026-09-06): the flag resolves (nil ⇒ ignore = true, the new default) and rides to the
    // box, where the Kernel reads it to decide whether an incoming CC120/123 wipes the live input pool.
    func testIgnoreAllNotesOffResolvesToTrueByDefaultAndFlowsToBox() {
        let cs = machines(customizing: 0) { _ in }
        // default (unset) → ignore
        XCTAssertTrue(SnapshotBuilder.build(from: PluginState(machines: cs, scenes: [SceneState.empty()])).ignoreAllNotesOff,
                      "unset ⇒ ignore incoming All-Notes-Off (default ON)")
        // explicit false → honor it (the box tells the Kernel to let CC120/123 clear the pool)
        var st = PluginState(machines: cs, scenes: [SceneState.empty()]); st.ignoreAllNotesOff = false
        XCTAssertFalse(SnapshotBuilder.build(from: st).ignoreAllNotesOff, "explicit false ⇒ honor incoming All-Notes-Off")
        XCTAssertFalse(st.ignoreAllNotesOffResolved, "resolver mirrors the explicit false")
    }

    // PER-PART CLOCK (Paul 2026-08-19): the builder resolves each row's step + loop length from the scene's per-row
    // overrides, falling back to the scene default (uniform = today). Stage A — the box just CARRIES the values.
    func testPerRowClockResolvesElseFallsToGlobal() {
        let cs = machines(customizing: 0) { _ in }
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

    func testRowLenClampsOutOfRangeToOneThroughSixteen() {
        // The clamp is load-bearing: the Router multi-clock path divides by cyc = rowLength · rowStep, so a 0 would
        // yield NaN. A hostile/garbage decode of rowLen must resolve into 1…maxCols. (Paul 2026-08-19; the §E 16-step
        // flip widened the CLAMP to maxCols=16 — a part can loop 16 columns — but the UNSET fallback stays the 8-wide
        // default bar, so a plain doc is byte-identical.)
        let cs = machines(customizing: 0) { _ in }
        let b = box(cs) { $0.rowLen = [0, 99, -3, nil, nil, nil, nil, nil] }
        XCTAssertEqual(b.rowLength[0], 1, "0 clamps up to 1")
        XCTAssertEqual(b.rowLength[1], Snap.maxCols, "99 clamps down to 16 (the allocation ceiling)")
        XCTAssertEqual(b.rowLength[2], 1, "a negative clamps up to 1")
        XCTAssertEqual(b.rowLength[3], Snap.cols, "nil falls to the default 8-wide bar")
    }

    // MULTI-CHANNEL (Paul 2026-08-21): a door can hear an arbitrary channel SUBSET; the mask resolves + packs into the box.
    func testChannelMaskResolvesFromLegacyAndExplicit() {
        var r = Receiver(name: "x")
        XCTAssertEqual(r.channelMaskResolved, 0xFFFF, "default (OMNI) → all channels")
        r.channel = 3; XCTAssertEqual(r.channelMaskResolved, 0b100, "single channel 3 → bit 2")
        r.channelMask = 0b10101; XCTAssertEqual(r.channelMaskResolved, 0b10101, "explicit mask wins (channels 1+3+5)")
        r.channelMask = 0; XCTAssertEqual(r.channelMaskResolved, 0, "explicit 0 = none")
    }

    // CR-18[extras]: inverted-window resolvers must ORDER their bounds, not silently mute.
    func testInvertedResolversOrderTheirBoundsInsteadOfMuting() {
        var r = Receiver(name: "1"); r.rangeLo = 72; r.rangeHi = 48          // decoded window backwards
        XCTAssertLessThanOrEqual(r.rangeLoResolved, r.rangeHiResolved, "a door's range resolver orders lo ≤ hi (never a silent door)")
        XCTAssertEqual(r.rangeHiResolved, 72, "hi is lifted to lo")
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.velWindow = VelWindow(floor: 120, ceil: 20); return c }()
        let box = SnapshotBuilder.build(from: PluginState(machines: machines(customizing: 0) { _ in }, scenes: [s]))
        let sc = box.cells[0]
        XCTAssertLessThanOrEqual(sc.velFloor, sc.velCeil, "an inverted per-cell velocity window is ordered, not left muting the cell")
    }
    // CR-9[review]: a short/long rackConfigs array (a truncated or forward-compat doc) must PAD/TRUNCATE to 4, not be
    // discarded wholesale — dropping it silently reverted every config to defaults (data-loss).
    func testRackConfigsShortOrLongArrayPadsNotDiscards() {
        var st = PluginState(machines: machines(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.rackEnabledMask = 0b0101
        st.rackConfigs = [0b0010, 0b0011]                          // only 2 present (a truncated doc)
        XCTAssertEqual(st.rackConfigsResolved, [0b0010, 0b0011, 0b1111, 0b1111], "the two real configs survive; the missing tail defaults")
        st.rackConfigs = [0b0001, 0b0010, 0b0100, 0b1000, 0b1111]  // 5 present (forward-compat doc)
        XCTAssertEqual(st.rackConfigsResolved, [0b0001, 0b0010, 0b0100, 0b1000], "extra trailing configs truncate to 4")
    }
    func testRackConfigsSurviveCodableRoundTrip() throws {
        var st = PluginState(machines: machines(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.rackConfigs = [0b0001, 0b0010, 0b0100, 0b1000]; st.rackActiveConfig = 2
        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(st))
        XCTAssertEqual(back.rackConfigs, [0b0001, 0b0010, 0b0100, 0b1000])
        XCTAssertEqual(back.rackActiveConfig, 2)
        XCTAssertEqual(back.rackMaskResolved, 0b0100)
    }

    // delta §9 item 1: the builder carries each Machine's ON assignments onto its SnapMachine (nil → unassigned).
    func testOnConfigResolvesOntoSnapMachine() {
        var on = OnConfig()
        on.arrive = .morphDrift; on.driftMode = .pingpong; on.driftPct = 15; on.arriveEvery = 2
        on.sceneEntrance = true; on.entrancePass = 3
        let cs = machines(customizing: 2) { $0.on = on }
        let b = box(cs) { _ in }
        XCTAssertEqual(b.machines[2].on, on, "machine 2's ON assignments reach the snapshot verbatim")
        XCTAssertEqual(b.machines[0].on, OnConfig(), "an unassigned machine resolves to an empty OnConfig")
    }

    func testLegacySingleScaleMigratesToPoolZeroByteIdentical() {
        // FOUR SCALE POOLS (Paul 2026-09-04): a legacy door (no scalePools) must resolve EXACTLY as before — pool 0 = the
        // legacy single scale, active. The four resolvers are unchanged for old docs.
        var r = Receiver()
        r.doorMode = .scale
        r.scaleRoot = 5; r.scaleType = .dorian; r.scaleBaseOct = 2; r.scaleOctaves = 3
        XCTAssertNil(r.scalePools, "legacy door stores no scalePools")
        XCTAssertEqual(r.activeScaleResolved, 0, "a legacy door is always pool 0")
        XCTAssertEqual(r.scaleRootResolved, 5)
        XCTAssertEqual(r.scaleTypeResolved, .dorian)
        XCTAssertEqual(r.scaleBaseOctResolved, 2)
        XCTAssertEqual(r.scaleOctavesResolved, 3)
        XCTAssertEqual(r.scalePoolsResolved[0], ScalePool(root: 5, type: .dorian, baseOct: 2, octaves: 3),
                       "pool 0 IS the legacy scale")
        // A stray activeScale with no scalePools is ignored (byte-identity guard).
        r.activeScale = 2
        XCTAssertEqual(r.activeScaleResolved, 0)
        XCTAssertEqual(r.scaleRootResolved, 5, "stray activeScale can't move a legacy door off pool 0")
    }
    func testActiveScaleRadioSwitchesTheResolvedScale() {
        var r = Receiver()
        r.doorMode = .scale
        r.scalePools = [ScalePool(root: 0, type: .major, baseOct: 3, octaves: 2),
                        ScalePool(root: 9, type: .naturalMinor, baseOct: 2, octaves: 1),
                        ScalePool(), ScalePool()]
        r.activeScale = 1
        XCTAssertEqual(r.scaleRootResolved, 9)
        XCTAssertEqual(r.scaleTypeResolved, .naturalMinor)
        XCTAssertEqual(r.scaleBaseOctResolved, 2)
        XCTAssertEqual(r.scaleOctavesResolved, 1)
        r.activeScale = 0
        XCTAssertEqual(r.scaleRootResolved, 0)
        XCTAssertEqual(r.scaleTypeResolved, .major)
    }
    func testScalePoolsResolvedPadsAndClampsActive() {
        var r = Receiver()
        r.scalePools = [ScalePool(root: 3, type: .lydian)]        // only 1 stored
        XCTAssertEqual(r.scalePoolsResolved.count, 4, "padded to 4")
        XCTAssertEqual(r.scalePoolsResolved[0].root, 3)
        r.activeScale = 7                                          // out of range
        XCTAssertEqual(r.activeScaleResolved, 3, "clamped to 0…3")
    }
    func testReceiverScalePoolsDecodeTolerant() throws {
        // CR-8 class: an old-doc Receiver JSON (no scalePools/activeScale keys) must decode + fall back to the legacy scale.
        let json = """
        {"name":"","channel":0,"mpeMerge":false,"muted":false,"scaleRoot":7,"scaleType":"mixolydian","scaleBaseOct":4,"scaleOctaves":2,"doorMode":"scale"}
        """.data(using: .utf8)!
        let r = try JSONDecoder().decode(Receiver.self, from: json)
        XCTAssertNil(r.scalePools)
        XCTAssertEqual(r.scaleRootResolved, 7)
        XCTAssertEqual(r.scaleTypeResolved, .mixolydian)
        // Round-trip a four-pool door.
        var w = Receiver(); w.doorMode = .scale
        w.scalePools = [ScalePool(root: 2, type: .blues), ScalePool(root: 5, type: .phrygian), ScalePool(), ScalePool()]
        w.activeScale = 1
        let data = try JSONEncoder().encode(w)
        let back = try JSONDecoder().decode(Receiver.self, from: data)
        XCTAssertEqual(back.scalePools?.count, 4)
        XCTAssertEqual(back.activeScale, 1)
        XCTAssertEqual(back.scaleRootResolved, 5)
        XCTAssertEqual(back.scaleTypeResolved, .phrygian)
    }

    // CELL MACHINE stage-3: 3-tier chain resolution — per-cell OVERRIDE → machine TEMPLATE → legacy A face.
    func testChainResolvesOverrideThenTemplateThenAFace() {
        let i = 2, cid = machineIDs[2]
        var cs = machineIDs.map { Machine(machineID: $0, type: .arp) }   // A face = ARP
        cs[i].templateChain = [ProcessorSlot(type: .ratchet)]
        let follow = box(cs) { $0.cells[0][0] = Cell(machineID: cid, buses: [.a]) }   // no override → template
        XCTAssertEqual(follow.cells[0].procs.first?.type, .ratchet, "a following cell resolves the machine TEMPLATE")
        let over = box(cs) { $0.cells[0][0] = { var c = Cell(machineID: cid, buses: [.a]); c.processors = [ProcessorSlot(type: .strum)]; return c }() }
        XCTAssertEqual(over.cells[0].procs.first?.type, .strum, "a per-cell OVERRIDE wins over the template")
        let legacy = box(machineIDs.map { Machine(machineID: $0, type: .arp) }) { $0.cells[0][0] = Cell(machineID: cid, buses: [.a]) }
        XCTAssertEqual(legacy.cells[0].procs.first?.type, .arp, "no override, no template → the legacy A face")
    }

    // LADDER: a DORMANT rung breaks the legato run — otherwise a full-8×8 ladder reads as one run from column 0
    // and each active rung's legato arp arrives badly phase-advanced (the "starts late / sounds random" bug).
    func testLadderDormantBreaksTheLegatoRun() {
        let cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        func build(ladder: Bool) -> SnapshotBox {
            var s = SceneState.empty()
            for c in 0..<8 { s.cells[c][0] = Cell(machineID: "gold", buses: [.a]); s.cells[c][1] = Cell(machineID: "gold", buses: [.a]) }
            s.activeRow = (0..<8).map { Optional($0 % 2 == 0 ? 0 : 1) }   // even cols → row 0 active, odd → row 1 active
            var st = PluginState(machines: cs, scenes: [s]); st.ladderMode = ladder
            return SnapshotBuilder.build(from: st)
        }
        XCTAssertEqual(build(ladder: false).cells[4 * Snap.rows + 0].runStartColumn, 0, "no ladder → the row is ONE run from col 0")
        let on = build(ladder: true)
        XCTAssertEqual(on.cells[4 * Snap.rows + 0].runStartColumn, 4, "ladder: the active rung (col 4, row 0) runs from its OWN column")
        XCTAssertEqual(on.cells[5 * Snap.rows + 1].runStartColumn, 5, "ladder: the active rung (col 5, row 1) runs from its OWN column")
    }

    // THE NINE PORTS: every port is always enabled (the per-output enable was an emitter toggle and is gone) and there are eight stamp channels.
    func testEveryPortIsEnabledAndThereAreEightStampChannels() {
        let st = PluginState(machines: machines(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        let b = SnapshotBuilder.build(from: st)
        XCTAssertEqual(b.busEnabledMask, 0xFF)
        XCTAssertEqual(b.busChannels, [1, 2, 3, 4, 5, 6, 7, 8], "a fresh document stamps each port with its own channel")
    }
    func testAPreNinePortsDocumentsFourLaneChannelsFillBothPortsOfEachLane() {
        var st = PluginState(machines: machines(customizing: 0) { _ in }, scenes: [SceneState.empty()])
        st.busChannels = [5, 6, 7, 8]
        XCTAssertEqual(SnapshotBuilder.build(from: st).busChannels, [5, 5, 6, 6, 7, 7, 8, 8], "the lane's number is both its ports' number, so ALL is unchanged")
        st.busChannels = [9, 8, 7, 6, 5, 4, 3, 2]
        XCTAssertEqual(SnapshotBuilder.build(from: st).busChannels, [9, 8, 7, 6, 5, 4, 3, 2], "an eight-entry list is one per port")
        st.busChannels = [0, 99, 3, 4, 5, 6, 7, 8]
        XCTAssertEqual(SnapshotBuilder.build(from: st).busChannels, [1, 16, 3, 4, 5, 6, 7, 8], "clamped to 1…16")
    }

    // MARK: - RECEIVERS (delta §9 item 11) — cell → receiver → SnapCell filter resolution

    func testReceiverChannelResolvesIntoSnapCellFilter() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold"); c.inputReceiver = 1; return c }()   // subscribes R2
        var st = PluginState(machines: machines(customizing: 0) { _ in }, scenes: [s])
        st.receivers = [Receiver(name: "1"), Receiver(name: "2", channel: 5), Receiver(name: "3"), Receiver(name: "4")]
        let sc = SnapshotBuilder.build(from: st).cells[0]
        XCTAssertEqual(sc.inputChannel, 5, "R2's channel filter is stamped on the cell")
        XCTAssertEqual(sc.resolvedReceiver, 1)
    }

    func testMutedReceiverProducesMatchNothingFilter() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold"); c.inputReceiver = 0; return c }()
        var st = PluginState(machines: machines(customizing: 0) { _ in }, scenes: [s])
        st.receivers = [Receiver(name: "1", channel: 0, muted: true), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        let sc = SnapshotBuilder.build(from: st).cells[0]
        XCTAssertGreaterThanOrEqual(sc.inputChannel, 17, "a muted receiver ⇒ match-nothing filter")
    }

    func testNoReceiversFallsBackToLegacyInputChannel() {
        // Parity: a doc with no receivers (pre-migration / a direct test build) keeps the per-cell filter.
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold"); c.inputChannel = 4; return c }()
        let st = PluginState(machines: machines(customizing: 0) { _ in }, scenes: [s])   // receivers == nil
        XCTAssertEqual(SnapshotBuilder.build(from: st).cells[0].inputChannel, 4)
    }



    // THE CONFIG SHEETS (Paul 2026-08-20): the door MODE reframes the 3 existing latch modes, behaviour-preserving.
    func testDoorModeDerivesFromLegacyLatchFields() {
        func mode(_ f: (inout Receiver) -> Void) -> DoorMode { var r = Receiver(name: "x"); f(&r); return r.doorModeResolved }
        XCTAssertEqual(mode { _ in }, .hold, "default (nothing set) ⇒ HOLD (Paul 2026-08-31: receivers default to HOLD)")
        XCTAssertEqual(mode { $0.latchAdd = false }, .hold, "CHORD ⇒ HOLD")
        XCTAssertEqual(mode { $0.latchAdd = true }, .latch, "explicit legacy KEYS/ADD ⇒ LATCH (honoured)")
        XCTAssertEqual(mode { $0.latchPiano = true }, .keys, "PIANO ⇒ KEYS")
        // the legacy resolvers are UNCHANGED for old docs (byte-identical)
        var chord = Receiver(name: "c"); chord.latchAdd = false
        XCTAssertFalse(chord.latchAddResolved); XCTAssertFalse(chord.latchPianoResolved)
        XCTAssertFalse(Receiver(name: "d").latchAddResolved, "nil ⇒ HOLD (false) — unified with doorModeResolved's HOLD default (Paul 2026-09-07)")
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
    func testReplayPassesClampToTheAllowedSet() {
        var r = Receiver(name: "x"); r.replayPasses = 7
        XCTAssertEqual(r.replayPassesResolved, 1, "an out-of-set value clamps to 1")
        r.replayPasses = 8; XCTAssertEqual(r.replayPassesResolved, 8)
        r.replayPasses = nil; XCTAssertEqual(r.replayPassesResolved, 1, "nil ⇒ 1")
    }


    // MARK: - TWO-PROCESSOR morph (delta item 8) — b sourced from this Machine's OWN procB, tier gates resolve

    // (CELL MACHINE: the A/B morph resolution tests — b/tier/glide/morphMaster — were REMOVED with the morph
    //  layer. The Machine's procB Codable fields still round-trip, tested below.)

    func testProcBFieldsRoundTripThroughCodable() {
        // typeB/transposeB persist through a round-trip.
        var c = Machine(machineID: "gold", type: .arp)
        c.typeB = .ratchet; c.transposeB = 7
        let back = try! JSONDecoder().decode(Machine.self, from: try! JSONEncoder().encode(c))
        XCTAssertEqual(back.typeB, .ratchet)
        XCTAssertEqual(back.transposeBResolved, 7)
        XCTAssertTrue(back.hasProcB)
        // a B-less Machine (typeB/transposeB nil) encodes without those keys → decodes to the B-less default,
        // exactly as an old pre-item-8 doc would (the new fields are Optional; absent ⇒ nil/0).
        let bless = try! JSONDecoder().decode(Machine.self, from: try! JSONEncoder().encode(Machine(machineID: "teal", type: .arp)))
        XCTAssertNil(bless.typeB)
        XCTAssertEqual(bless.transposeBResolved, 0)
        XCTAssertFalse(bless.hasProcB)
    }



    // CLOCK (Paul 2026-09-26): the resolve/clamp block had ZERO test coverage until a housekeeping survey pass —
    // FIXED/WAVE's own clamps (clockDepth/clockRatio) were removed with those modes the same day; only the DRAWN
    // lane's clockDrawnSteps clamp remains (its upper/lower bound — a regression here wouldn't fail anywhere else
    // in the suite, it would silently truncate or extend an authored grid).
    func testClockParamsResolveAndClamp() {
        let sc = box(machines(customizing: 0) {
            $0.paramsA.clockDrawnSteps = 99        // illegal → clamps to the DRAWN lane's upper bound (32)
        }) { _ in }.machines[0]
        XCTAssertEqual(sc.a.clockDrawnSteps, 32, "clockDrawnSteps clamps to its upper bound")
        let neg = box(machines(customizing: 0) { $0.paramsA.clockDrawnSteps = -5 }) { _ in }.machines[0]
        XCTAssertEqual(neg.a.clockDrawnSteps, 1, "clockDrawnSteps clamps to its lower bound too")
    }




    // EUCLIDEOUS (Paul 2026-10-05): rate must survive the explicit EuclidLine(...) reconstruction in
    // SnapshotBuilder — that constructor is a fresh literal, not copy-with-mutation, so this is a REAL regression
    // guard (a prior RATE-automation feature was bitten by exactly this omission).
    func testEuclidLineRateSurvivesSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, rate: .r1_8t)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(a.euclidLines[0].rate, .r1_8t, "per-line rate must survive the resolve, not silently reset")
    }

    // MELODY POP-UP (Paul 2026-10-10 ferry): riffStride/riffLength/riffAdvanceStep/melodyTranspose must
    // ALSO survive the fresh-literal reconstruction — the exact regression class this file keeps
    // guarding for, now exercised for the newest 4 fields.
    func testEuclidLineMelodyPopupFieldsSurviveSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, riffStride: 5, riffLength: 6, riffAdvanceStep: true, melodyTranspose: -4)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(a.euclidLines[0].riffStrideResolved, 5, "per-line STRIDE must survive the resolve, not silently reset")
        XCTAssertEqual(a.euclidLines[0].riffLengthResolved, 6, "per-line LENGTH must survive the resolve")
        XCTAssertTrue(a.euclidLines[0].riffAdvanceStepResolved, "per-line ADVANCE must survive the resolve")
        XCTAssertEqual(a.euclidLines[0].melodyTransposeResolved, -4, "per-line TRANSPOSE must survive the resolve")
        // clamping survives the resolve too (mirrors the emitterMask/riffOctave precedent just above)
        let clamped = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, riffStride: 99, riffLength: 99, melodyTranspose: 99)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(clamped.euclidLines[0].riffStrideResolved, 7)
        XCTAssertEqual(clamped.euclidLines[0].riffLengthResolved, 8)
        XCTAssertEqual(clamped.euclidLines[0].melodyTransposeResolved, 7)
    }
    // LIT NOTES PLUS THE RIFF (Paul 2026-10-13, second same-day ferry): `litNotes`/`topLit`/`top2Lit`/
    // `riffOn` must ALSO survive the fresh-literal reconstruction — the exact regression class this file
    // keeps guarding for. `melodyMode` is included too: a direct read confirmed it was MISSING from this
    // reconstruction entirely (a real, pre-existing gap from the just-shipped MELODY tab, closed here
    // alongside adding these four new fields, so neither ferry's own mode/lit-notes state silently resets
    // on the very next snapshot rebuild).
    func testEuclidLineLitNotesRiffOnAndMelodyModeSurviveSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, melodyMode: .riff, litNotes: 0b0010_0101, topLit: true, top2Lit: true, riffOn: true)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(a.euclidLines[0].litNotesResolved, 0b0010_0101, "the lit-rank bitmask must survive the resolve, not silently reset")
        XCTAssertTrue(a.euclidLines[0].topLitResolved, "TOP lit must survive the resolve")
        XCTAssertTrue(a.euclidLines[0].top2LitResolved, "TOP2 lit must survive the resolve")
        XCTAssertTrue(a.euclidLines[0].riffOnResolved, "the explicit riffOn must survive the resolve, not fall back to migration")
        XCTAssertEqual(a.euclidLines[0].melodyModeResolved, .riff, "melodyMode (the migration source for an era-2 doc) must also survive — found MISSING from the fresh-literal reconstruction entirely before this fix")
    }
    // RHYTHM CARDS / MISS-AS-INVERT (Paul 2026-10-10 ferry): `patternMiss` must ALSO survive the fresh-
    // literal reconstruction — the same standing regression class, now exercised for this field. The 4
    // shared `missNoteSel`/etc. fields (untouched by this ferry, still serving the regular, non-Euclideous
    // BUILD-page EUCLID editor) survive alongside it, unaffected.
    func testEuclidLinePatternMissSurvivesSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8, patternMiss: true)]
        }) { _ in }.machines[0].a
        XCTAssertTrue(a.euclidLines[0].patternMissResolved, "patternMiss must survive the resolve, not silently reset")
        let untouched = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 3, steps: 8)]
        }) { _ in }.machines[0].a
        XCTAssertFalse(untouched.euclidLines[0].patternMissResolved, "nil defaults to HIT, not MISS")
    }

    // NOTES TAB (2026-10-19, §13 test 10): WHEN / CHANCE / PLAY AS / RECEIVED / the lit order must survive the fresh-literal reconstruction. `notesWhen` DEFAULTS
    // to both, so a stored PLAYS-only that the literal forgot would silently turn back into both on every render.
    func testNotesTabFieldsSurviveSnapshotBuild() {
        var line = EuclidLine(target: 0, pulses: 4, steps: 8)
        line.notesWhen = 0b01; line.notesChance = 50; line.notesPlayAs = .cycle; line.notesReceivedOnly = true
        var o = EuclideousLitOrder(); o.append(7); o.append(4); o.append(9); line.setLitOrder(o)
        let a = box(machines(customizing: 0) { $0.paramsA.euclidLines = [line] }) { _ in }.machines[0].a
        let r = a.euclidLines[0]
        XCTAssertEqual(r.notesWhenResolved, 0b01); XCTAssertEqual(r.notesChanceResolved, 50); XCTAssertEqual(r.notesPlayAsResolved, .cycle)
        XCTAssertTrue(r.notesReceivedOnlyResolved); XCTAssertEqual(r.litOrderResolved.array, [7, 4, 9])
        XCTAssertEqual(r.litNotesResolved, 0b1001_0000); XCTAssertTrue(r.topLitResolved)
        let untouched = box(machines(customizing: 0) { $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8)] }) { _ in }.machines[0].a
        XCTAssertEqual(untouched.euclidLines[0].notesWhenResolved, 0b11); XCTAssertEqual(untouched.euclidLines[0].notesChanceResolved, 100)
        XCTAssertEqual(untouched.euclidLines[0].notesPlayAsResolved, .chord); XCTAssertFalse(untouched.euclidLines[0].notesReceivedOnlyResolved)
    }

    // RIFF/NOTES SPLIT (Paul's third same-day ferry, "split MELODY into RIFF and NOTES tabs") —
    // notesOn/noteOctShifts/notesVelOffset must ALSO survive the fresh-literal reconstruction, the exact
    // standing regression class every entry in this cluster already guards for.
    func testEuclidLineRiffNotesSplitFieldsSurviveSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, notesOn: false,
                                                  noteOctShifts: [1, -1, 0, 0, 0, 0, 0, 1], notesVelOffset: -20)]
        }) { _ in }.machines[0].a
        XCTAssertFalse(a.euclidLines[0].notesOnResolved, "notesOn must survive the resolve, not silently reset")
        XCTAssertEqual(a.euclidLines[0].noteOctShiftsResolved, [1, -1, 0, 0, 0, 0, 0, 1], "noteOctShifts must survive the resolve")
        XCTAssertEqual(a.euclidLines[0].notesVelOffsetResolved, -20, "notesVelOffset must survive the resolve")
        let untouched = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8)]
        }) { _ in }.machines[0].a
        XCTAssertTrue(untouched.euclidLines[0].notesOnResolved, "nil defaults to ON")
        XCTAssertEqual(untouched.euclidLines[0].noteOctShiftsResolved, Array(repeating: 0, count: 8))
        XCTAssertEqual(untouched.euclidLines[0].notesVelOffsetResolved, 0)
        // notesVelOffset clamps here too, mirroring velocityAbsolute's own clamp precedent just below
        let clamped = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, notesVelOffset: 200)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(clamped.euclidLines[0].notesVelOffsetResolved, 64)
    }

    // XY PAD REDESIGN (Paul 2026-10-09): velocityAbsolute threads through the SAME fresh-literal
    // reconstruction as every other EuclidLine field above — the exact regression class this file keeps
    // guarding for. A NEW field (not a repurposed `velocity`) specifically so an old doc's saved
    // `"velocity": 1.5` (the Double-typed 0...2 scale) never collides with this Int-typed 1...127 override.
    func testEuclidLineVelocityAbsoluteSurvivesSnapshotBuildAndClamps() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, velocityAbsolute: 55)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(a.euclidLines[0].velocityAbsoluteResolved, 55, "velocityAbsolute must survive the resolve, not silently reset")
        // an untouched line defaults to 100, never 0 (an illegal MIDI velocity)
        let untouched = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(untouched.euclidLines[0].velocityAbsoluteResolved, 100)
        // clamped 1...127, mirroring octave's own clamp precedent above
        let clampedHigh = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, velocityAbsolute: 255)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(clampedHigh.euclidLines[0].velocityAbsoluteResolved, 127)
        let clampedLow = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, velocityAbsolute: 0)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(clampedLow.euclidLines[0].velocityAbsoluteResolved, 1)
    }

    // RIFF ADVANCE (Paul 2026-10-06): useRiff/riffRotate/riffOctave are the newest three EuclidLine fields through
    // the SAME fresh-literal reconstruction — the exact regression class the entry above already guards for.
    func testEuclidLineRiffAdvanceFieldsSurviveSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, useRiff: true, riffRotate: 6, riffOctave: -2, riffDir: .drunk, riffDirSeed: 7, riffDirBias: 0.5)]
        }) { _ in }.machines[0].a
        XCTAssertTrue(a.euclidLines[0].useRiffResolved, "useRiff must survive the resolve, not silently reset")
        XCTAssertEqual(a.euclidLines[0].riffRotateResolved, 6)
        XCTAssertEqual(a.euclidLines[0].riffOctaveResolved, -2)
        // DIRECTION IS PER-LANE (Paul 2026-10-07) — riffDir/riffDirSeed/riffDirBias must also survive this
        // same fresh-literal reconstruction, not just steps/ranks on the shared EuclideousRiff below.
        XCTAssertEqual(a.euclidLines[0].riffDirResolved, .drunk)
        XCTAssertEqual(a.euclidLines[0].riffDirSeedResolved, 7)
        XCTAssertEqual(a.euclidLines[0].riffDirBiasResolved, 0.5)
        // riffOctave/riffDirBias are clamped here too — riffOctave narrowed to -2...2 for Euclideous only
        // (Paul 2026-10-13 ferry, "Engine" rule 4; the shared `octave` field a few lines above stays -3...3)
        let clamped = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, riffOctave: 9, riffDirBias: 5)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(clamped.euclidLines[0].riffOctaveResolved, 2)
        XCTAssertEqual(clamped.euclidLines[0].riffDirBiasResolved, 1)
    }

    // EUCLIDEOUS PAGE REWORK (Paul 2026-10-07): `mask` is the newest EuclidLine field through the SAME
    // fresh-literal reconstruction — the exact regression class the two entries above already guard for.
    func testEuclidLineMaskSurvivesSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, mask: EuclidLineMask(enabled: false, pulses: 3, steps: 5, rotate: 2))]
        }) { _ in }.machines[0].a
        XCTAssertEqual(a.euclidLines[0].mask?.enabled, false, "mask.enabled must survive the resolve, not silently reset")
        XCTAssertEqual(a.euclidLines[0].mask?.pulses, 3, "mask.pulses must survive the resolve")
        XCTAssertEqual(a.euclidLines[0].mask?.steps, 5, "mask.steps must survive the resolve")
        XCTAssertEqual(a.euclidLines[0].mask?.rotate, 2, "mask.rotate must survive the resolve")
        // an untouched line's mask stays nil — no mask is ever silently fabricated
        let untouched = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8)]
        }) { _ in }.machines[0].a
        XCTAssertNil(untouched.euclidLines[0].mask, "a line that never touched MASK must resolve with no mask at all")
    }

    // PER-LANE I/O (Paul 2026-10-08, the new I/O tab): sourceMode must thread through the fresh-literal
    // EuclidLine rebuild like every other field here — the documented hazard spot a prior RATE-automation
    // feature was bitten by.
    func testEuclidLineSourceModeSurvivesSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, sourceMode: .chords)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(a.euclidLines[0].sourceMode, .chords, "sourceMode must survive the resolve, not silently reset")
        // an untouched line defaults to nil ⇒ KEY (melody pop-up ferry, Paul 2026-10-10 §2.2: "the default
        // SOURCE for a new instance is KEY") — reverses the original 2026-10-08 MIDI default; an EXPLICIT
        // sourceMode (above) is of course unaffected either way.
        let untouched = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8)]
        }) { _ in }.machines[0].a
        XCTAssertNil(untouched.euclidLines[0].sourceMode, "a line that never touched I/O must resolve with sourceMode nil")
        XCTAssertEqual(untouched.euclidLines[0].sourceModeResolved, .key, "and resolve to KEY, per the melody pop-up ferry's own §2.2")
    }

    // EUCLIDEOUS PAGE REWORK: a document that has never touched any of the new global fields must resolve
    // to MIDI for both source switches — flipping this default would silently mute every existing Euclideous
    // session the moment this feature ships. (These two RETIRED global switches are legacy decode-only fields
    // now — per-lane `EuclidLine.sourceMode` governs real behaviour, see testEuclideousSourceModeSurvivesSnap-
    // shotBuild above; KEY mode itself now generates a real scale pool, Router.swift's `.key` branch, not an
    // empty one — the §4.4 gap this comment used to describe was closed 2026-10-09.)
    // HOLD/LATCH (Paul 2026-10-20): the field reaches the Euclideous row's own SnapParams (`procs[0]`, same hop
    // `globalSrcChanMask` already uses). SOURCES STACK ferry (2026-10-26): MIDI IN ALWAYS listens now, so the mode
    // reaches the row REGARDLESS of the (decode-only) source value — the old `== .midi ? … : nil` gate is gone.
    func testEuclideousHoldLatchModeReachesTheRowForEverySource() {
        var st = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) },
                             scenes: [{ var s = SceneState.empty()
                                 s.cells[0][Snap.euclideousRow] = Cell(machineID: machineIDs[0], buses: [.a])
                                 return s }()])
        func resolved(_ st: PluginState) -> EuclideousHoldLatchMode? {
            SnapshotBuilder.build(from: st).cells[0 * Snap.rows + Snap.euclideousRow].procs[0].euclideousHoldLatchMode
        }
        st.euclideousNoteSource = .midi
        st.euclideousHoldLatchMode = .hold
        XCTAssertEqual(resolved(st), .hold, "MIDI IN: the stored mode reaches the row")
        st.euclideousHoldLatchMode = .latch
        XCTAssertEqual(resolved(st), .latch)
        st.euclideousNoteSource = .chords
        XCTAssertEqual(resolved(st), .latch, "CHORDS: MIDI always listens, so the stored mode still reaches the row")
        st.euclideousNoteSource = .key
        XCTAssertEqual(resolved(st), .latch, "KEY: same — MIDI always listens")
        // an untouched document (nil, nil) must resolve to nil — byte-identical for every pre-existing session.
        let untouched = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) },
                                    scenes: [{ var s = SceneState.empty()
                                        s.cells[0][Snap.euclideousRow] = Cell(machineID: machineIDs[0], buses: [.a])
                                        return s }()])
        XCTAssertNil(resolved(untouched))
    }
    func testEuclideousSourceModeDefaultsToMidiOnAnUntouchedDocument() {
        let st = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) }, scenes: [SceneState.empty()])
        XCTAssertTrue(st.euclideousRiffSourceMidiResolved, "an untouched document must default to MIDI for the riff's own source")
        XCTAssertTrue(st.euclideousLanesSourceMidiResolved, "and for the lanes' own source")
        XCTAssertEqual(st.euclideousResetSpanBarsResolved, 0, "reset span starts OFF")
    }

    // CHORDS BUTTON (Paul 2026-10-08): euclideousChords resolves into the SHARED chords* SnapParams fields
    // (reused directly from the regular CHORDS processor, not a parallel set — see Snapshot.swift's own doc
    // comment on euclideousChordKeyRoot/KeyTones for why), on Euclideous's row only, PATTERN mode forced
    // unconditionally (there's no MODE picker on this page). keyRoot/keyTones come from the page's own KEY.
    func testEuclideousChordsResolveIntoTheSharedChordsFieldsOnItsOwnRowOnly() {
        var st = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: machineIDs[0], buses: [.a])
                                  s.cells[0][0] = Cell(machineID: machineIDs[1], buses: [.a])   // a DIFFERENT row, same document
                                  return s }()])
        st.euclideousKeyRoot = 2; st.euclideousKeyType = .dorian
        st.euclideousChords = { var m = MachineParams(); m.chordsDegrees = [3, 4]; m.chordsSteps = 2; m.chordsRate = .r1_2; return m }()
        let box = SnapshotBuilder.build(from: st)
        let p = box.cells[0 * Snap.rows + Snap.euclideousRow].procs[0]
        XCTAssertEqual(p.chordsDegrees, [3, 4], "the authored degrees must survive the resolve")
        XCTAssertEqual(p.chordsSteps, 2)
        XCTAssertEqual(p.chordsRateBeats, StepRate.r1_2.beats, accuracy: 0.0001)
        XCTAssertEqual(p.euclideousChordKeyRoot, 2, "the page's own KEY root, not a receiver door")
        XCTAssertEqual(p.euclideousChordKeyTones, ScaleType.dorian.intervals, "the page's own KEY scale")
        // a DIFFERENT row's cell, same document, must be untouched — this is Euclideous-row-only. chordsMode
        // isn't useful here (SnapParams.chordsMode already DEFAULTS to .pattern everywhere) — chordsSteps/
        // Degrees DO have distinct bare defaults (8 / the I-vi-IV-V loop), so a mismatch against THIS test's
        // own authored values (2 / [3,4]) is the real signal that nothing leaked across rows.
        let other = box.cells[0 * Snap.rows + 0].procs[0]
        XCTAssertEqual(other.chordsSteps, 8, "a different row's cell keeps the bare SnapParams default, not Euclideous's authored steps")
        XCTAssertEqual(other.chordsDegrees, [0, 0, 5, 5, 3, 3, 4, 4], "and the bare default degrees, not Euclideous's")
    }
    // An untouched euclideousChords (nil) must resolve to something AUDIBLE, not silence — MachineParams()'s
    // own chordsDegreesResolved default is the sensible I-I-V-V-IV-IV-V-V loop (matches the regular CHORDS
    // processor's own fresh-card default).
    func testEuclideousChordsDefaultsToAnAudibleProgressionWhenUntouched() {
        let st = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) },
                              scenes: [{ var s = SceneState.empty()
                                  s.cells[0][Snap.euclideousRow] = Cell(machineID: machineIDs[0], buses: [.a])
                                  return s }()])
        let box = SnapshotBuilder.build(from: st)
        let p = box.cells[0 * Snap.rows + Snap.euclideousRow].procs[0]
        XCTAssertEqual(p.chordsDegrees, [0, 0, 5, 5, 3, 3, 4, 4], "untouched ⇒ the same default loop MachineParams()'s own chordsDegreesResolved resolves to")
        XCTAssertFalse(p.chordsDegrees.allSatisfy { $0 == 7 }, "must not default to all-REST")
    }

    // RIFF ADVANCE: the page's own shared riff pattern CONTENT (steps/ranks only — direction moved per-lane,
    // see the EuclidLine test above) must also survive the build, resolved/clamped once here.
    func testEuclideousRiffSurvivesSnapshotBuild() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclideousRiff = EuclideousRiff(steps: 40, ranks: [1, 2, 3])
        }) { _ in }.machines[0].a
        XCTAssertEqual(a.euclideousRiff.stepsResolved, 32, "clamped at build time")
        XCTAssertEqual(a.euclideousRiff.ranksResolved.count, 32, "padded at build time")
    }

    // The 16-machine cap is lifted: the builder sizes its machine array to the document and resolves cells BY ID, so a
    // machine appended beyond the canonical 16 (a BUILD ephemeral machine) renders instead of being skipped. (2026-08-15)
    func testBuilderResolvesMachineBeyondTheSixteen() {
        var cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        var extra = Machine(machineID: "b1", type: .arp)
        extra.templateChain = [ProcessorSlot(type: .harmonize)]   // a distinctive machine on the 17th machine
        cs.append(extra)                                          // index 16 — beyond the fixed 16
        let b = box(cs) { s in s.cells[3][2] = Cell(machineID: "b1") }
        XCTAssertEqual(b.machines.count, 17, "the machine array sizes to the document, not a fixed 16")
        let cell = b.cells[3 * Snap.rows + 2]
        XCTAssertEqual(Int(cell.machineIndex), 16, "the appended machine resolves BY ID to index 16")
        XCTAssertEqual(cell.procs.first?.type, .harmonize, "its templateChain is applied — the cell is NOT skipped")
    }

    // A cell resolves its machine by the DOCUMENT-order index, NOT the canonical machineIDs position. With the machines
    // held OUT of canonical order, the old `machineIDs.firstIndex ?? …` lookup read the wrong SnapMachine (a silent
    // wrong-machine bug latent behind any reorder). (Paul 2026-08-16)
    func testMachineResolvesByDocumentOrderNotCanonicalPosition() {
        // Move "cyan" to document slot 0 (a real permutation — SWAP, so no duplicate machineID) and give it a distinct
        // machine. The old `machineIDs.firstIndex ?? …` lookup would read cyan's CANONICAL slot (wrong SnapMachine).
        var cs = machineIDs.map { Machine(machineID: $0, type: .arp) }
        let cyanIdx = machineIDs.firstIndex(of: "cyan")!             // cyan's canonical position
        cs.swapAt(0, cyanIdx)                                        // cyan → document slot 0; gold → cyan's old slot
        cs[0].templateChain = [ProcessorSlot(type: .harmonize)]     // cyan (now at slot 0) gets a distinctive machine
        let b = box(cs) { s in s.cells[0][0] = Cell(machineID: "cyan") }
        let cell = b.cells[0]
        XCTAssertEqual(Int(cell.machineIndex), 0, "the 'cyan' cell resolves to document slot 0, where cyan now lives")
        XCTAssertEqual(cell.procs.first?.type, .harmonize, "it reads cyan's machine by document order, not the canonical-index machine")
    }


    func testRunStartColumnForContiguousRun() {
        // §7 LEGATO precompute: a contiguous same-Machine run in one row shares the run's first column.
        let b = box(machines(customizing: 0) { _ in }) { s in
            s.cells[2][0] = Cell(machineID: "gold")
            s.cells[3][0] = Cell(machineID: "gold")
        }
        XCTAssertEqual(b.cells[2 * Snap.rows + 0].runStartColumn, 2)
        XCTAssertEqual(b.cells[3 * Snap.rows + 0].runStartColumn, 2)   // continues, not restarts
    }

    func testRunBreaksOnGap() {
        let b = box(machines(customizing: 0) { _ in }) { s in
            s.cells[2][0] = Cell(machineID: "gold")
            // column 3 empty → break
            s.cells[4][0] = Cell(machineID: "gold")
        }
        XCTAssertEqual(b.cells[2 * Snap.rows + 0].runStartColumn, 2)
        XCTAssertEqual(b.cells[4 * Snap.rows + 0].runStartColumn, 4)   // a gap restarts the run
    }

    func testBusMaskAndCellFlags() {
        let b = box(machines(customizing: 0) { _ in }) { s in
            s.cells[0][0] = Cell(machineID: "gold", buses: [.a, .c], alt: true)
        }
        let cell = b.cells[0]
        XCTAssertEqual(cell.busMask, 0b0101)   // A + C
        XCTAssertTrue(cell.alt)
        XCTAssertEqual(cell.machineIndex, 0)
    }

    func testEmptyCellIsMarkedEmpty() {
        let b = box(machines(customizing: 0) { _ in }) { _ in }
        XCTAssertLessThan(b.cells[0].machineIndex, 0)   // machineIndex < 0 = empty
    }

    // MARK: v3.0 graph-routing precompute (delta §1)

    // (grid-chaining retired: resolvedParent-from-inputRow tests removed — resolvedParent is always −1.)

    func testBusChannelsAndInputChannel() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(machineID: "gold", buses: [.a]); c.inputChannel = 3; return c }()
        var d = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) }, scenes: [s])
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
        s.cells[0][2] = Cell(machineID: "gold"); s.cells[0][5] = Cell(machineID: "gold")
        XCTAssertEqual(s.ladderActiveRow(0), 2, "no choice → topmost occupied")
        s.activeRow = [Int?](repeating: nil, count: 8)
        s.activeRow?[0] = 5; XCTAssertEqual(s.ladderActiveRow(0), 5, "chosen occupied rung")
        s.activeRow?[0] = 3; XCTAssertNil(s.ladderActiveRow(0), "chosen rung EMPTY → nothing (user 2026-08-07: selecting an empty cell mutes the column)")
        s.activeRow?[0] = -1; XCTAssertNil(s.ladderActiveRow(0), "explicit deselect → nothing")
        XCTAssertNil(s.ladderActiveRow(1), "empty column → nothing")
    }


    // MIX TAB (ferry 2026-10-18) §9.5 — notesGate/notesVelocity must survive the fresh-literal reconstruction (and clamp), like every field above.
    func testEuclidLineNotesGateAndVelocitySurviveSnapshotBuildAndClamp() {
        let a = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, notesGate: 0.35, notesVelocity: 88)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(a.euclidLines[0].notesGate, 0.35, "notesGate must survive the resolve, not silently reset")
        XCTAssertEqual(a.euclidLines[0].notesVelocity, 88, "notesVelocity must survive the resolve")
        let untouched = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8)]
        }) { _ in }.machines[0].a
        XCTAssertNil(untouched.euclidLines[0].notesGate, "nil stays nil — the lane's own GATE keeps ruling"); XCTAssertNil(untouched.euclidLines[0].notesVelocity)
        let clamped = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, notesGate: 7.0, notesVelocity: 900)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(clamped.euclidLines[0].notesGate, 1.0); XCTAssertEqual(clamped.euclidLines[0].notesVelocity, 127)
        let low = box(machines(customizing: 0) {
            $0.paramsA.euclidLines = [EuclidLine(target: 0, pulses: 4, steps: 8, notesGate: 0.0, notesVelocity: 0)]
        }) { _ in }.machines[0].a
        XCTAssertEqual(low.euclidLines[0].notesGate, 0.05, "clamped like GATE itself (the builder's 5% floor), so the layers agree at the low end"); XCTAssertEqual(low.euclidLines[0].notesVelocity, 1)
    }

}
