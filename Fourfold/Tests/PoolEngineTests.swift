//  PoolEngineTests.swift — POOL ferry (2026-11-02), the Router against the real engine: per-lane SOURCES (§3), shared builds and the two chord grids. (SUSTAIN, KEEP/STACK and FREEZE were removed by the INPUTS ferry, 2026-11-06.)
//  A stepping rig drives `Router.process` window by window (480 frames = 0.02 beat at 120 BPM / 48 kHz) with notes pressed, the pedal moved (the arguments the Kernel passes) and the document swapped; each lane hits once a beat, and what it is
//  choosing from after a hit is read off the same per-lane pool status the POOL tab's NOW row polls (`euclideousLanePoolStatus`).

import XCTest

private final class PoolEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
}

private final class Rig {
    let router = Router(); var diag = KernelDiag(); let out = PoolEmitter(); let pool = NotePool()
    var box: SnapshotBox
    var ts = 0.0, offset = 0.0
    var playing = true
    let frames: UInt32 = 480
    init(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    var beat: Double { ts * 120.0 / 60.0 / 48_000.0 }
    func swap(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    func run(to target: Double, flush: Bool = false) {
        var first = flush
        while beat < target - 1e-9 {
            router.process(box: box, pool: pool, playing: playing, beatPos: beat + offset, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, forceColumn: 0,
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

final class PoolEngineTests: XCTestCase {
    private func lane(sources: [Int] = [0, 1, 2, 3], mode: MidiMode? = nil, delay: Int? = nil, rate: ArpRate = .r1_4) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = rate; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
        for b in 0..<4 { l.setPoolSrc(b, sources.contains(b)) }
        l.midiMode = mode
        l.chordDelay = delay
        return l
    }
    private func plan(midi: Bool = false, chords: Bool = false, pick: Bool = false, key: Bool = false, mode: MidiMode = .add, pickNotes: [UInt8] = []) -> SourcePlan {
        SourcePlan(midiOn: midi, chordsOn: chords, pickOn: pick, keyOn: key, midiMode: mode, pickNotes: pickNotes, midiOctaves: .keep)
    }
    private func state(_ lines: [EuclidLine], plan: SourcePlan, unit: CanonUnit? = .bars) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = [0, 3, 4, 5]; cs.chordsSteps = 4; cs.chordsRate = .r1_1       // C F G Am, a bar each
        st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        st.euclideousSourcePlan = plan
        st.euclideousCanonUnit = unit
        return st
    }

    // MARK: 3 — per-lane SOURCES
    func testALaneWithMidiInOffKeepsItsChordsWhileThePlayerPlaysUnderReplace() {
        // lane 1: MIDI IN + CHORDS; lane 2: CHORDS + KEY (no MIDI IN). Panel: MIDI IN in REPLACE, CHORDS and KEY on.
        let pl = plan(midi: true, chords: true, key: true, mode: .replace)
        let rig = Rig(state([lane(sources: [0, 1]), lane(sources: [1, 3])], plan: pl))
        rig.run(to: 1.5)
        let l1Before = rig.lanePool(0), l2Before = rig.lanePool(1)
        XCTAssertFalse(l1Before.isEmpty); XCTAssertFalse(l2Before.isEmpty); XCTAssertNotEqual(l1Before, l2Before, "lane 2 also has KEY: a different pool")
        rig.press([61]); rig.run(to: 2.5)
        XCTAssertEqual(rig.lanePool(0), [61], "playing replaces lane 1's chord (REPLACE steps CHORDS aside on a lane where MIDI IN is on)")
        XCTAssertEqual(rig.lanePool(1), l2Before, "…and leaves lane 2 on its chords and key")
        XCTAssertFalse(rig.lanePool(1).contains(61), "lane 2 never contains a played note")
        rig.release([61]); rig.run(to: 3.5)                     // still the first bar: the sequencer has not moved on
        XCTAssertEqual(rig.lanePool(0), l1Before, "lane 1 returns to its chord once the player lets go")
        XCTAssertEqual(rig.lanePool(1), l2Before, "lane 2 never moved")
    }
    func testALaneWithEverySourceOffHasAnEmptyPoolAndSoDoesOneWhoseSourcesAreAllOffInThePanel() {
        let rig = Rig(state([lane(sources: []), lane(sources: [0, 2]), lane()], plan: plan(chords: true)))   // panel: only CHORDS on
        rig.press([60]); rig.run(to: 1.5)
        XCTAssertEqual(rig.status(0).count, 0, "no source on the lane")
        XCTAssertEqual(rig.status(1).count, 0, "the lane's MIDI IN and PICK are off in the panel")
        XCTAssertGreaterThan(rig.status(2).count, 0, "an unchanged lane still plays its chords")
        XCTAssertEqual(rig.status(0).srcBits, 0); XCTAssertEqual(rig.status(1).srcBits, 0, "effective = panel AND lane"); XCTAssertEqual(rig.status(2).srcBits, 0b0010)
    }
    func testAChordsOnlyLaneIsNotMovedByRootBecauseItHasNoMidiIn() {
        // INPUTS ferry 2.4: a ROOT lane with MIDI IN off uses t = 0 — the transpose reaches only lanes whose MIDI IN chip is on.
        var pl = plan(midi: true, chords: true, mode: .root); pl.midiOctaves = .keep
        let rig = Rig(state([lane(), lane(sources: [1])], plan: pl))
        let still = Rig(state([lane(), lane(sources: [1])], plan: pl))
        still.run(to: 1.5)
        rig.press([50]); rig.run(to: 1.5)
        XCTAssertEqual(rig.lanePool(1), still.lanePool(1), "lane 2 (CHORDS only) is untouched by the played note")
        XCTAssertNotEqual(rig.lanePool(0), rig.lanePool(1), "lane 1 (MIDI IN on, ROOT) is moved; lane 2 is not")
        XCTAssertEqual(rig.lanePool(0).map { $0 - 2 }, rig.lanePool(1), "…by t = 50 − 48 = +2")
    }
    func testTheLaneSwitchesChangeNothingWhileAllFourAreOn() {
        // all four on is the default path: a lane that had its toggles flipped off and on again plays exactly what an untouched lane plays
        var flipped = lane(); for b in 0..<4 { flipped.setPoolSrc(b, false) }; for b in 0..<4 { flipped.setPoolSrc(b, true) }
        XCTAssertNil(flipped.poolSrcMask)
        let rig = Rig(state([lane(), flipped], plan: plan(midi: true, chords: true, key: true)))
        rig.press([62]); rig.run(to: 6.5)
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1))
    }

    func testALaneWithNoHitsStillHasAPoolItsNowRowAndKeysCanName() {
        var idle = lane(); idle.pulses = 0
        var idleNoKey = lane(sources: [0, 1]); idleNoKey.pulses = 0
        let rig = Rig(state([lane(), idle, idleNoKey], plan: plan(chords: true, key: true)))
        rig.run(to: 1.5)
        XCTAssertFalse(rig.lanePool(1).isEmpty, "an idle lane names the pool through its sources, not an empty one")
        XCTAssertEqual(rig.lanePool(1), rig.lanePool(0), "…the same as a running lane with the same sources")
        XCTAssertNotEqual(rig.lanePool(2), rig.lanePool(0), "an idle lane's own sources apply (this one has no KEY)")
        XCTAssertEqual(rig.status(1).playedRanks, 0, "nothing is playing out of an idle lane")
    }
    func testAnEmptyPoolClearsALanesLitRanks() {
        var l = lane(); l.setPoolSrc(3, true)
        let rig = Rig(state([l], plan: plan(chords: true, key: true)))
        rig.run(to: 2.5)
        XCTAssertNotEqual(rig.status(0).playedRanks, 0, "the lane struck a rank")
        rig.swap(state([lane(sources: [0])], plan: plan(chords: true, key: true)))   // MIDI IN only, nothing held: an empty pool
        rig.run(to: 4.5)
        XCTAssertEqual(rig.status(0).count, 0); XCTAssertEqual(rig.status(0).playedRanks, 0, "an empty pool plays nothing: no lit bar left behind")
    }

    // MARK: 4 — shared builds
    private func buildsInTheWindowAt(_ beat: Double, _ rig: Rig) -> Int {
        rig.run(to: beat - 0.02); let before = rig.router.poolBuildCount   // a window is 0.02 beat; a hit belongs to the window that ENDS on it
        rig.run(to: beat)
        return rig.router.poolBuildCount - before
    }
    func testLanesWithTheSameSourceSetShareOneBuild() {
        let pl = plan(midi: true, chords: true, key: true)
        func builds(_ lines: [EuclidLine]) -> Int { let r = Rig(state(lines, plan: pl)); r.press([60]); return buildsInTheWindowAt(2.0, r) }
        let A: [Int] = [1, 3], B: [Int] = [0, 1]
        let base = builds([lane(), lane(), lane(), lane()])
        let fourSame = builds([lane(sources: A), lane(sources: A), lane(sources: A), lane(sources: A)])
        let twoSets = builds([lane(sources: A), lane(sources: A), lane(sources: B), lane(sources: B)])
        let customThenDefault = builds([lane(sources: A), lane(), lane(), lane()])
        let worst = builds([lane(sources: A), lane(), lane(sources: B), lane()])
        print("POOL-BUILDS per window: default lanes \(base) · four lanes one set \(fourSame) · two sets (2+2) \(twoSets) · one custom lane then three default \(customThenDefault) · custom, default, custom, default \(worst)")
        XCTAssertEqual(base, 1, "the live pool: one build a window")
        XCTAssertEqual(fourSame, base + 1, "four lanes with the SAME source set share one build (plus the live one)")
        XCTAssertEqual(twoSets, base + 2, "two distinct sets cost two")
        XCTAssertEqual(customThenDefault, base + 2, "a default lane after a custom one puts the live pool back: one more")
        XCTAssertLessThanOrEqual(worst, 5, "the worst case: the live build, two sets and two restores")
    }
}

// MARK: - TWO CHORD GRIDS (2026-11-03): a lane's SOURCES mask picks the progression its CHORDS layer plays
extension PoolEngineTests {
    /// Grid 1: C F G Am, a bar each. Grid 2: two chords (II then III — none of grid 1's) on a half-note clock — a different length AND a different rate, so the lanes can only agree by accident.
    private func twoGridState(_ lines: [EuclidLine], plan pl: SourcePlan, unit: CanonUnit? = .bars) -> PluginState {
        var st = state(lines, plan: pl, unit: unit)
        var g1 = MachineParams(); g1.chordsDegrees = [0, 3, 4, 5]; g1.chordsSteps = 4; g1.chordsRate = .r1_1
        var g2 = MachineParams(); g2.chordsDegrees = [1, 2]; g2.chordsSteps = 2; g2.chordsRate = .r1_2
        st.euclideousChordSets = [g1, g2]
        return st
    }
    private func onGrid2(_ l: EuclidLine) -> EuclidLine { var m = l; m.setPoolSrc(4, true); return m }
    /// The chord a grid plays at `beat`, from the same snapshot the engine renders.
    private func gridChord(_ st: PluginState, grid: Int, beat: Double) -> [Int] {
        let p = SnapshotBuilder.build(from: st).cells[0 * Snap.rows + Snap.euclideousRow].procs[0]
        return chordSeqNotes(beat: beat, p, keyRoot: p.euclideousChordKeyRoot, keyTones: p.euclideousChordKeyTones, followNote: nil, grid: grid).sorted()
    }

    func testTwoLanesOnTwoGridsEachFollowTheirOwnProgression() {
        let st = twoGridState([lane(sources: [1]), onGrid2(lane(sources: [])), lane(), onGrid2(lane(sources: [3]))], plan: plan(chords: true, key: true))
        let rig = Rig(st)
        var sawDifference = false
        for b in 1...24 {
            rig.run(to: Double(b) + 0.5)
            let beat = Double(b) + 1e-9
            let g1 = gridChord(st, grid: 0, beat: beat), g2 = gridChord(st, grid: 1, beat: beat)
            XCTAssertEqual(rig.lanePool(0), g1, "lane 1 (CHORDS 1) at beat \(b)")
            XCTAssertEqual(rig.lanePool(1), g2, "lane 2 (CHORDS 2) at beat \(b)")
            XCTAssertTrue(Set(g1).isSubset(of: Set(rig.lanePool(2))), "lane 3 (default) plays grid 1 at beat \(b)")
            XCTAssertTrue(Set(g2).isSubset(of: Set(rig.lanePool(3))), "lane 4 (CHORDS 2 + KEY) plays grid 2 at beat \(b)")
            XCTAssertTrue(Set(rig.lanePool(3)).isSuperset(of: Set(g2)) && rig.lanePool(3).count > g2.count, "…and its KEY sits beneath")
            if g1 != g2 { sawDifference = true }
        }
        XCTAssertTrue(sawDifference, "the two progressions really differ")
    }
    func testGridTwoStepsByItsOwnClock() {
        // grid 2 changes chord every 2 beats, grid 1 every 4: the lane on grid 2 must change on beats 2, 4, 6… and the lane on grid 1 only on 4, 8…
        let st = twoGridState([lane(sources: [1]), onGrid2(lane(sources: []))], plan: plan(chords: true))
        let rig = Rig(st)
        var l1: [[Int]] = [], l2: [[Int]] = []
        for b in 0..<16 { rig.run(to: Double(b) + 0.5); l1.append(rig.lanePool(0)); l2.append(rig.lanePool(1)) }
        for b in 1..<16 {
            XCTAssertEqual(l1[b] != l1[b - 1], b % 4 == 0, "grid 1 moves only on the bar (beat \(b))")
            XCTAssertEqual(l2[b] != l2[b - 1], b % 2 == 0, "grid 2 moves every half note (beat \(b))")
        }
    }
    func testTheSourcesPanelsChordsSwitchIsTheMasterForBothGrids() {
        let off = Rig(twoGridState([onGrid2(lane(sources: [])), lane(sources: [1])], plan: plan(chords: false, key: true)))
        off.run(to: 4.5)
        XCTAssertEqual(off.status(0).count, 0, "CHORDS off in the panel: a CHORDS 2 lane has nothing"); XCTAssertEqual(off.status(1).count, 0)
        XCTAssertEqual(off.status(0).srcBits, 0)
        let on = Rig(twoGridState([onGrid2(lane(sources: []))], plan: plan(chords: true)))
        on.run(to: 4.5)
        XCTAssertGreaterThan(on.status(0).count, 0); XCTAssertEqual(on.status(0).srcBits, 0b0010, "the lane's effective chords bit is lit for CHORDS 2 as for CHORDS 1")
    }
    func testTurningAChordsTwoLaneBackToChordsOneReturnsToTheFirstProgression() {
        var st = twoGridState([onGrid2(lane(sources: []))], plan: plan(chords: true))
        let rig = Rig(st)
        rig.run(to: 5.5)
        XCTAssertEqual(rig.lanePool(0), gridChord(st, grid: 1, beat: 5 + 1e-9))
        var l = st.euclideousLinesResolved[0]; _ = l
        st = twoGridState([lane(sources: [1])], plan: plan(chords: true))
        rig.swap(st); rig.run(to: 9.5)
        XCTAssertEqual(rig.lanePool(0), gridChord(st, grid: 0, beat: 9 + 1e-9))
        XCTAssertNotEqual(gridChord(st, grid: 0, beat: 9 + 1e-9), gridChord(st, grid: 1, beat: 9 + 1e-9), "(the test only means something if the grids differ here)")
    }
    func testAnIdleLaneOnGridTwoNamesGridTwosChord() {
        var idle = onGrid2(lane(sources: [])); idle.pulses = 0
        let st = twoGridState([lane(), idle], plan: plan(chords: true))
        let rig = Rig(st)
        rig.run(to: 3.5)
        XCTAssertEqual(rig.lanePool(1), gridChord(st, grid: 1, beat: 2.5), "an idle lane's NOW row reads its own grid at the window")
        XCTAssertNotEqual(rig.lanePool(1), rig.lanePool(0))
    }
    func testAPlayedNoteStacksOverGridTwoJustAsOverGridOne() {
        let pl = plan(midi: true, chords: true)
        let st = twoGridState([lane(sources: [0, 1]), onGrid2(lane(sources: [0]))], plan: pl)
        let rig = Rig(st)
        rig.press([40]); rig.run(to: 5.5)
        let g1 = gridChord(st, grid: 0, beat: 5 + 1e-9), g2 = gridChord(st, grid: 1, beat: 5 + 1e-9)
        XCTAssertEqual(Set(rig.lanePool(0)), Set(g1 + [40])); XCTAssertEqual(Set(rig.lanePool(1)), Set(g2 + [40]))
    }

    // MARK: CANON on a CHORDS 2 lane
    func testACanonDelayedLaneOnGridTwoPlaysGridTwoBehindTheHostBeat() {
        let st = twoGridState([onGrid2(lane(sources: [], delay: 1)), lane(sources: [1], delay: 1)], plan: plan(chords: true))     // 1 bar = 4 beats behind
        let rig = Rig(st)
        for b in 8...20 {
            rig.run(to: Double(b) + 0.5)
            XCTAssertEqual(rig.lanePool(0), gridChord(st, grid: 1, beat: Double(b) - 4 + 1e-9), "grid 2, one bar back, at beat \(b)")
            XCTAssertEqual(rig.lanePool(1), gridChord(st, grid: 0, beat: Double(b) - 4 + 1e-9), "grid 1, one bar back, at beat \(b)")
        }
    }
    // MARK: shared builds
    func testLanesOnGridTwoShareOneBuildAndGridTwoCostsOnePerDistinctMask() {
        let pl = plan(midi: true, chords: true, key: true)
        func builds(_ lines: [EuclidLine]) -> Int {
            let r = Rig(twoGridState(lines, plan: pl)); r.press([60])
            r.run(to: 1.98); let before = r.router.poolBuildCount; r.run(to: 2.0)
            return r.router.poolBuildCount - before
        }
        let base = builds([lane(), lane(), lane(), lane()])
        let fourOnGrid2 = builds([onGrid2(lane()), onGrid2(lane()), onGrid2(lane()), onGrid2(lane())])
        let gridsMixed = builds([lane(), lane(), onGrid2(lane()), onGrid2(lane())])
        XCTAssertEqual(base, 1, "the live pool: one build a window")
        XCTAssertEqual(fourOnGrid2, base + 1, "four CHORDS 2 lanes with the same other sources share ONE build (plus the live one)")
        XCTAssertLessThanOrEqual(gridsMixed, 3, "grid 1 lanes keep the live pool; the CHORDS 2 pair adds one build, and the restore")
        XCTAssertEqual(gridsMixed, base + 1 + 1 - 1 + 1 - 1 + 1 - 1, "(live, then the pair's one build; the order lane 1, 2, 3, 4 needs no restore after it)")
    }
    func testADocumentThatNeverUsesGridTwoBuildsExactlyAsBefore() {
        // the default mask is unchanged (CHORDS 1 on), so every lane takes the default path whatever grid 2 holds
        let pl = plan(midi: true, chords: true, key: true)
        let r = Rig(twoGridState([lane(), lane(), lane(), lane()], plan: pl)); r.press([60])
        r.run(to: 1.98); let before = r.router.poolBuildCount; r.run(to: 2.0)
        XCTAssertEqual(r.router.poolBuildCount - before, 1)
        for i in 0..<4 { XCTAssertNil(r.router.euclideousLanePoolStatus()[i].count > 0 ? nil as Int? : 0 as Int?, "every lane has a pool") }
    }
}
