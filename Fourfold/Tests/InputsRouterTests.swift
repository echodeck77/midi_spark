//  InputsRouterTests.swift — INPUTS + HARMONY ferry (2026-11-06) tests 4–7: the Router against the real engine with each lane choosing its own MIDI mode (ADD / REPLACE / ROOT), the latched root transpose t, the shared
//  builds, and the three removed stages (FREEZE, SUSTAIN, SLIP). A stepping rig drives `Router.process` window by window (480 frames = 0.02 beat at 120 BPM / 48 kHz); each lane hits once a beat on a flat riff, and what a lane
//  is choosing from after a hit is read off the same per-lane pool status the INPUTS tab's NOW row polls.

import XCTest

private final class InEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1, vel: b2)) }
}

private final class InRig {
    let router = Router(); var diag = KernelDiag(); let out = InEmitter(); let pool = NotePool()
    var box: SnapshotBox
    var ts = 0.0
    var playing = true
    let frames: UInt32 = 480
    init(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    var beat: Double { ts * 120.0 / 60.0 / 48_000.0 }
    func swap(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    func run(to target: Double, flush: Bool = false) {
        var first = flush
        while beat < target - 1e-9 {
            router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           sceneFlush: first, out: out, diag: &diag)
            first = false
            ts += Double(frames)
        }
    }
    func press(_ n: [UInt8]) { for x in n { pool.noteOn(x, velocity: 100, channel: 0) } }
    func release(_ n: [UInt8]) { for x in n { pool.noteOff(x) } }
    func lanePool(_ l: Int) -> [Int] { router.euclideousLanePoolStatus()[l].notes.map(Int.init) }
    func status(_ l: Int) -> EuclideousLanePoolStatus { router.euclideousLanePoolStatus()[l] }
}

final class InputsRouterTests: XCTestCase {
    private func lane(sources: [Int] = [0, 1], mode: MidiMode? = nil, delay: Int? = nil, rate: ArpRate = .r1_4) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = rate; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
        for b in 0..<5 { l.setPoolSrc(b, sources.contains(b)) }
        l.midiMode = mode
        l.chordDelay = delay
        return l
    }
    /// The panel plan after the load-time migration: every switch true; `mode` is only the fallback of a lane with no mode of its own.
    private func plan(mode: MidiMode = .add) -> SourcePlan {
        SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: mode, pickNotes: [], midiOctaves: .keep)
    }
    private func state(_ lines: [EuclidLine], plan p: SourcePlan? = nil, unit: CanonUnit? = .bars) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = [0, 3, 4, 5]; cs.chordsSteps = 4; cs.chordsRate = .r1_1       // C F G Am, a bar each
        st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        st.euclideousSourcePlan = p ?? plan()
        st.euclideousCanonUnit = unit
        return st
    }

    // MARK: 4 — per-lane modes
    /// Lane 1 ADD, lane 2 REPLACE, lane 3 ROOT, lane 4 ADD with MIDI IN off; CHORDS running; hold D3.
    func testFourLanesFourModesUnderOneHeldNote() {
        let lines = [lane(mode: .add), lane(mode: .replace), lane(mode: .root), lane(sources: [1], mode: .add)]
        let rig = InRig(state(lines))
        rig.run(to: 5.5)                                   // bar 2: the F chord
        let chord = rig.lanePool(3)
        XCTAssertFalse(chord.isEmpty, "lane 4 plays the progression")
        XCTAssertEqual(rig.lanePool(0), chord, "nothing held: lane 1 plays the chord"); XCTAssertEqual(rig.lanePool(1), chord); XCTAssertEqual(rig.lanePool(2), chord)
        rig.press([50]); rig.run(to: 6.0)                  // hold D3 (t = 50 − 48 = +2)
        XCTAssertEqual(Set(rig.lanePool(0)), Set(chord + [50]), "lane 1 (ADD) adds the held note to its chord")
        XCTAssertEqual(rig.lanePool(1), [50], "lane 2 (REPLACE) plays only the held notes")
        XCTAssertEqual(rig.lanePool(2), chord.map { $0 + 2 }, "lane 3 (ROOT) plays its chord moved +2…")
        XCTAssertFalse(rig.lanePool(2).contains(50), "…and never contains a played note")
        XCTAssertEqual(rig.lanePool(3), chord, "lane 4 (MIDI IN off) is unchanged")
        XCTAssertEqual(rig.status(2).midiMode, .root); XCTAssertEqual(rig.status(2).rootT, 2, "the readout's value: the lane's applied t")
        XCTAssertEqual(rig.status(0).rootT, 0); XCTAssertEqual(rig.status(1).rootT, 0); XCTAssertEqual(rig.status(3).rootT, 0, "only a ROOT lane with MIDI IN on applies t")
        XCTAssertEqual(rig.status(1).midiMode, .replace)
        rig.release([50]); rig.run(to: 7.5)                // past RELEASE GRACE (50 ms = 0.1 beat), and past the next hit (a lane's pool is read at its hits)
        XCTAssertEqual(rig.lanePool(1), chord, "lane 2's chord returns after RELEASE GRACE")
        XCTAssertEqual(rig.lanePool(0), chord, "lane 1 lets the note go")
        XCTAssertEqual(rig.lanePool(2), chord.map { $0 + 2 }, "lane 3 stays at +2 (latched)")
        XCTAssertEqual(rig.status(2).rootT, 2)
    }
    /// A lane's own mode wins over the document's; a lane with none follows the document (an old REPLACE document keeps REPLACE on every lane).
    func testALaneWithNoModeFollowsTheDocumentsMode() {
        let rig = InRig(state([lane(), lane(mode: .add), lane(sources: [1])], plan: plan(mode: .replace)))
        rig.run(to: 5.5); let chord = rig.lanePool(2)
        rig.press([50]); rig.run(to: 6.0)
        XCTAssertEqual(rig.lanePool(0), [50], "no field of its own ⇒ the document's REPLACE")
        XCTAssertEqual(Set(rig.lanePool(1)), Set(chord + [50]), "an explicit ADD overrides it")
        XCTAssertEqual(rig.status(0).midiMode, .replace); XCTAssertEqual(rig.status(1).midiMode, .add)
    }
    /// The per-note source of the NOW pips: the held note is MIDI (0), the chord's notes are CHORDS (1).
    func testEachReceivedNoteNamesItsSource() {
        let rig = InRig(state([lane(mode: .add)]))
        rig.run(to: 5.5); rig.press([50]); rig.run(to: 6.0)
        let st = rig.status(0)
        XCTAssertEqual(st.sources.count, st.notes.count)
        for (n, s) in zip(st.notes, st.sources) { XCTAssertEqual(s, n == 50 ? 0 : 1, "note \(n)") }
        XCTAssertEqual(st.contrib & 0b0011, 0b0011, "MIDI playing and CHORDS lit")
    }

    // MARK: 5 — t
    func testTheLatchedTransposeFollowsTheLaneNotTheDocument() {
        // lane 1 under test, lane 2 (CHORDS only) is the reference chord; a lane's pool is read at its hits (once a beat), so every check sits half a beat after one.
        let add = state([lane(mode: .add), lane(sources: [1])])
        let root = state([lane(mode: .root), lane(sources: [1])])
        let rig = InRig(add)
        rig.run(to: 4.5)
        rig.press([50]); rig.run(to: 5.5); rig.release([50]); rig.run(to: 6.5)   // t = +2 is latched while the lane is in ADD (tracked whenever notes are held)
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1), "a lane in ADD applies nothing")
        rig.swap(root); rig.run(to: 7.5)
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1).map { $0 + 2 }, "a lane switched into ROOT after the latch applies the latched t")
        rig.swap(add); rig.run(to: 8.5)
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1), "a lane switched out stops applying it")
        rig.swap(root); rig.run(to: 9.5)
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1).map { $0 + 2 }, "…and back in, the latch is still there")
    }
    func testTransportStartAndStopLeaveTheLatchAloneAndALoadClearsIt() {
        let rig = InRig(state([lane(mode: .root), lane(sources: [1])]))
        rig.run(to: 4.5); rig.press([50]); rig.run(to: 5.5); rig.release([50]); rig.run(to: 6.5)
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1).map { $0 + 2 })
        rig.playing = false; rig.run(to: rig.beat + 1.0)
        rig.playing = true; rig.run(to: rig.beat + 1.5)
        XCTAssertEqual(rig.status(0).rootT, 2, "stop and start leave t alone")
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1).map { $0 + 2 })
        rig.run(to: rig.beat + 0.5, flush: true)
        rig.run(to: rig.beat + 1.5)
        XCTAssertEqual(rig.status(0).rootT, 0, "a load (the scene flush) resets t to 0")
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1))
    }
    /// A ROOT lane whose MIDI IN chip is off uses t = 0 even with a latched t.
    func testARootLaneWithMidiInOffUsesZero() {
        let rig = InRig(state([lane(mode: .root), lane(sources: [1], mode: .root)]))
        rig.run(to: 5.5); rig.press([50]); rig.run(to: 6.0)
        XCTAssertEqual(rig.status(0).rootT, 2); XCTAssertEqual(rig.status(1).rootT, 0)
        XCTAssertEqual(rig.lanePool(1).map { $0 + 2 }, rig.lanePool(0))
    }

    // MARK: 6 — shared builds
    private func buildsInTheWindowAt(_ beat: Double, _ rig: InRig) -> Int {
        rig.run(to: beat - 0.02); let before = rig.router.poolBuildCount
        rig.run(to: beat)
        return rig.router.poolBuildCount - before
    }
    func testLanesWithTheSameSourcesAndModeShareOneBuild() {
        func builds(_ lines: [EuclidLine], mode: MidiMode = .add) -> Int { let r = InRig(state(lines, plan: plan(mode: mode))); r.press([60]); return buildsInTheWindowAt(2.0, r) }
        let all = [0, 1, 2, 3]                                                                                         // the default chips (every source on)
        func lane(sources: [Int] = all, mode: MidiMode? = nil) -> EuclidLine { self.lane(sources: sources, mode: mode) }
        let live = builds([lane(), lane(), lane(), lane()])                                                          // every lane on the default pair
        let twoPairs = builds([lane(), lane(), lane(mode: .replace), lane(mode: .replace)])                         // the default pair + one other
        let twoOther = builds([lane(mode: .replace), lane(mode: .replace), lane(mode: .root), lane(mode: .root)])  // two non-default pairs
        let fourOther = builds([lane(mode: .root), lane(mode: .root), lane(mode: .root), lane(mode: .root)])
        let sameSourcesTwoModes = builds([lane(sources: [1, 3]), lane(sources: [1, 3]), lane(sources: [1, 3], mode: .replace), lane(sources: [1, 3], mode: .replace)])
        print("INPUTS-BUILDS per window: all default \(live) · two distinct pairs (default + REPLACE) \(twoPairs) · two non-default pairs \(twoOther) · four lanes one non-default pair \(fourOther) · same sources, two modes \(sameSourcesTwoModes)")
        XCTAssertEqual(live, 1, "the live pool: one build a window")
        XCTAssertEqual(twoPairs, 2, "four lanes, two distinct (sources, mode) pairs: the live build and one more — two builds")
        XCTAssertEqual(fourOther, 2, "four lanes sharing one non-default pair: the live build plus one")
        XCTAssertEqual(twoOther, 3, "two non-default pairs: the live build plus one each")
        XCTAssertLessThanOrEqual(sameSourcesTwoModes, 4)
    }

    // MARK: 7 — removed stages
    func testFreezeSustainAndSlipPlayAsIfOff() {
        func run(_ l: EuclidLine) -> [InEmitter.Ev] {
            let rig = InRig(state([l, lane(sources: [1], delay: 1)]))
            rig.run(to: 1.5); rig.press([50, 57]); rig.run(to: 6.5); rig.release([50, 57]); rig.run(to: 16.5)
            return rig.out.events
        }
        let off = lane()
        var on = lane(); on.poolHold = 2; on.poolSustainOn = true; on.poolSustainMode = .stack; on.chordSlip = 50
        XCTAssertEqual(run(on), run(off), "FREEZE 2 bars, SUSTAIN STACK and SLIP 50 % play exactly as with all three off")
        var delayed = lane(delay: 1); var delayedOn = delayed
        delayedOn.poolHold = 9; delayedOn.chordSlip = 30
        delayed.chordSlip = nil
        XCTAssertEqual(run(delayedOn), run(delayed), "…also with a CANON delay (SLIP no longer shifts the delayed chord)")
        let data = try! JSONEncoder().encode(on)
        let back = try! JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertEqual(back.poolHold, 2); XCTAssertEqual(back.poolSustainOn, true); XCTAssertEqual(back.poolSustainMode, .stack); XCTAssertEqual(back.chordSlip, 50, "the fields round-trip unchanged")
    }
}
