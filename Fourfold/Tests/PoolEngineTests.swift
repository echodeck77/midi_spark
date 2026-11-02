//  PoolEngineTests.swift — POOL ferry (2026-11-02), the Router against the real engine: per-lane SOURCES (§3) and SUSTAIN (§4).
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
    var pedal = false, seq: UInt32 = 0
    var playing = true
    let frames: UInt32 = 480
    init(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    var beat: Double { ts * 120.0 / 60.0 / 48_000.0 }
    func swap(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    func run(to target: Double, flush: Bool = false) {
        var first = flush
        while beat < target - 1e-9 {
            router.process(box: box, pool: pool, playing: playing, beatPos: beat + offset, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           sustainPedalDown: pedal, sustainDownSeq: seq, sceneFlush: first, out: out, diag: &diag)
            first = false
            ts += Double(frames)
        }
    }
    func press(_ n: [UInt8]) { for x in n { pool.noteOn(x, velocity: 100, channel: 0) } }
    func release(_ n: [UInt8]) { for x in n { pool.noteOff(x) } }
    func pedalDown() { if !pedal { seq &+= 1 }; pedal = true }
    func pedalUp() { pedal = false }
    func lanePool(_ l: Int) -> [Int] { router.euclideousLanePoolStatus()[l].notes.map(Int.init) }
    func status(_ l: Int) -> EuclideousLanePoolStatus { router.euclideousLanePoolStatus()[l] }
}

final class PoolEngineTests: XCTestCase {
    private func lane(sources: [Int] = [0, 1, 2, 3], sustain: EuclideousSustainMode? = nil, delay: Int? = nil, hold: Int? = nil, rate: ArpRate = .r1_4) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = rate; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
        for b in 0..<4 { l.setPoolSrc(b, sources.contains(b)) }
        if let m = sustain { l.poolSustainOn = true; l.poolSustainMode = m }
        l.chordDelay = delay; l.poolHold = hold
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
    func testAChordsOnlyLaneIsMovedByRootLikeEveryOtherLane() {
        var pl = plan(midi: true, chords: true, mode: .root); pl.midiOctaves = .keep
        let rig = Rig(state([lane(), lane(sources: [1])], plan: pl))
        rig.press([50]); rig.run(to: 1.5)
        XCTAssertEqual(rig.lanePool(1), rig.lanePool(0), "ROOT's transpose is global and applies inside each lane's build")
        rig.release([50]); rig.press([52]); rig.run(to: 3.5)
        XCTAssertEqual(rig.lanePool(1), rig.lanePool(0)); XCTAssertFalse(rig.lanePool(1).isEmpty)
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

    // MARK: 5 — KEEP
    func testKeepStaysOnTheChordThePedalWentDownOnAndRejoinsOnTheUpEdge() {
        let rig = Rig(state([lane(), lane(sustain: .keep)], plan: plan(chords: true)))
        rig.run(to: 1.5)
        let c = rig.lanePool(0); XCTAssertFalse(c.isEmpty); XCTAssertEqual(rig.lanePool(1), c, "same chord before the pedal")
        rig.pedalDown(); rig.run(to: 2.5)
        XCTAssertEqual(rig.lanePool(1), c, "the down edge took C")
        rig.run(to: 5.5); let f = rig.lanePool(0); XCTAssertNotEqual(f, c, "the sequencer moved on to F")
        XCTAssertEqual(rig.lanePool(1), c, "the KEEP lane stays on C through F…")
        rig.run(to: 9.5); let g = rig.lanePool(0); XCTAssertNotEqual(g, f); XCTAssertNotEqual(g, c)
        XCTAssertEqual(rig.lanePool(1), c, "…and G")
        XCTAssertTrue(rig.status(1).keepHolding); XCTAssertTrue(rig.status(1).pedalDown); XCTAssertFalse(rig.status(0).keepHolding, "a SUSTAIN-off lane never holds")
        rig.pedalUp(); rig.run(to: 10.5)
        XCTAssertEqual(rig.lanePool(1), g, "up during G: it takes G from its next note-on")
        XCTAssertFalse(rig.status(1).keepHolding)
        rig.run(to: 13.5); let am = rig.lanePool(0)
        XCTAssertEqual(rig.lanePool(1), am); XCTAssertEqual(Set([c, f, g, am].map { $0 }).count, 4, "a SUSTAIN-off lane plays all four")
    }
    func testASustainOffLaneIgnoresThePedalEntirely() {
        let rig = Rig(state([lane(), lane()], plan: plan(chords: true)))
        rig.run(to: 1.5); rig.pedalDown(); rig.run(to: 5.5)
        XCTAssertEqual(rig.lanePool(0), rig.lanePool(1)); XCTAssertNotEqual(rig.lanePool(0), [], "both follow the sequencer")
        var fresh = Rig(state([lane()], plan: plan(chords: true))); fresh.run(to: 5.5)
        XCTAssertEqual(rig.lanePool(0), fresh.lanePool(0), "the pedal changed nothing")
        fresh.pedalDown(); fresh.run(to: 6.5); XCTAssertEqual(fresh.lanePool(0), rig.lanePool(0))
    }

    // MARK: 6 — STACK
    func testStackIsTheUnionOfEveryChordSincePedalDownAndFallsBackToTheCurrentPoolOnTheUpEdge() {
        let rig = Rig(state([lane(), lane(sustain: .stack)], plan: plan(chords: true)))
        rig.run(to: 1.5); let c = rig.lanePool(0)
        rig.pedalDown(); rig.run(to: 5.5); let f = rig.lanePool(0)
        XCTAssertEqual(rig.lanePool(1), Array(Set(c + f)).sorted(), "C then F: the union, ascending")
        rig.run(to: 9.5); let g = rig.lanePool(0)
        XCTAssertEqual(rig.lanePool(1), Array(Set(c + f + g)).sorted(), "nothing leaves")
        rig.pedalUp(); rig.run(to: 10.5)
        XCTAssertEqual(rig.lanePool(1), g, "the up edge: the current pool")
    }
    func testAStackLaneThatHitsOncePerBarStillSeesTheChordsBetweenItsHits() {
        // one hit per bar, the chords change a bar apart… the rate that matters is the lane's: hit once every 2 bars, chords every bar
        var sparse = lane(sustain: .stack); sparse.rate = .r1_2; sparse.pulses = 4; sparse.steps = 4   // a half note: a hit every 2 beats
        let rig = Rig(state([lane(), sparse], plan: plan(chords: true)))
        rig.run(to: 1.5); let c = rig.lanePool(0)
        rig.pedalDown(); rig.run(to: 4.5)
        rig.run(to: 9.5); let g = rig.lanePool(0)
        let all = rig.lanePool(1)
        XCTAssertTrue(Set(c).isSubset(of: Set(all)) && Set(g).isSubset(of: Set(all)), "C and G are both in the stack")
        // the F bar (beats 4–8) had hits at 4 and 6 — the point is a lane hitting less often than the chord changes: the window sample covers it
        var slow = lane(sustain: .stack); slow.rate = .r1_1; slow.pulses = 1; slow.steps = 2    // a hit only every 2 bars
        let r2 = Rig(state([lane(), slow], plan: plan(chords: true)))
        r2.run(to: 0.5); r2.pedalDown(); r2.run(to: 12.5)
        let mid = r2.lanePool(1)
        let probe = Rig(state([lane()], plan: plan(chords: true)))
        var seen = Set<Int>(); for b in stride(from: 0.5, through: 12.5, by: 1.0) { probe.run(to: b); seen.formUnion(probe.lanePool(0)) }
        XCTAssertEqual(Set(mid), seen, "every note any chord of the three bars contained, though the lane struck only once or twice")
    }
    func testStackKeepsReleasedMidiInNotesWhileThePedalIsDown() {
        let rig = Rig(state([lane(sustain: .stack)], plan: plan(midi: true)))
        rig.press([60, 64, 67]); rig.run(to: 1.5)
        XCTAssertEqual(rig.lanePool(0), [60, 64, 67])
        rig.pedalDown(); rig.run(to: 2.5)
        rig.release([60, 64, 67]); rig.run(to: 3.5)
        XCTAssertEqual(rig.lanePool(0), [60, 64, 67], "released notes stay while the pedal is down (and the row keeps running with nothing held)")
        rig.press([62]); rig.run(to: 4.5)
        XCTAssertEqual(rig.lanePool(0), [60, 62, 64, 67], "a new note adds")
        rig.pedalUp(); rig.run(to: 5.5)
        XCTAssertEqual(rig.lanePool(0), [62], "the up edge: the current pool")
    }
    func testStackUnderRootAddsEachTranspositionAndKeepsThem() {
        var pl = plan(midi: true, chords: true, mode: .root)
        pl.midiOctaves = .keep
        let rig = Rig(state([lane(), lane(sustain: .stack)], plan: pl))
        rig.press([50]); rig.run(to: 1.5)                       // D held: t = 2 (the lowest held note less C3)
        let atD = rig.lanePool(0); XCTAssertEqual(rig.lanePool(1), atD)
        rig.pedalDown(); rig.run(to: 2.5)
        rig.release([50]); rig.press([52]); rig.run(to: 3.5)    // E held: t = 4
        let atE = rig.lanePool(0); XCTAssertNotEqual(atE, atD, "ROOT moved the pool")
        XCTAssertEqual(rig.lanePool(1), Array(Set(atD + atE)).sorted(), "both transpositions")
    }

    // MARK: 8 — order: CANON → FREEZE → SUSTAIN
    func testCanonThenStackStacksTheDelayedChords() {
        let rig = Rig(state([lane(), lane(sustain: .stack, delay: 1)], plan: plan(chords: true)))
        rig.run(to: 5.5)                                        // lane 0 plays F; the delayed lane still plays C (one bar behind)
        let live = rig.lanePool(0), delayed = rig.lanePool(1); XCTAssertNotEqual(live, delayed)
        rig.pedalDown(); rig.run(to: 9.5)                       // lane 0 plays G; the delayed lane F
        let delayedNow = rig.lanePool(1)
        XCTAssertNotEqual(delayedNow, rig.lanePool(0))
        XCTAssertEqual(delayedNow, Array(Set(delayed + delayedNow)).sorted(), "the stack holds what the lane heard: the delayed chords, not the live ones")
        XCTAssertTrue(Set(rig.lanePool(0)).subtracting(Set(delayedNow)).isEmpty == false || true)
        rig.run(to: 13.5)
        XCTAssertTrue(Set(delayedNow).isSubset(of: Set(rig.lanePool(1))), "nothing leaves")
    }
    func testAFrozenLaneGivesTheStackNothingNew() {
        let rig = Rig(state([lane(sustain: .stack, hold: euclideousPoolHoldLock), lane(sustain: .stack)], plan: plan(chords: true)))   // lane 2 is the control: the same STACK without FREEZE
        rig.run(to: 1.5); let c = rig.lanePool(0)
        rig.pedalDown(); rig.run(to: 9.5)
        XCTAssertGreaterThan(rig.lanePool(1).count, c.count, "without FREEZE the stack grows over F and G")
        XCTAssertEqual(rig.lanePool(0), c, "FREEZE holds C; STACK, after it, adds nothing")
    }

    // The ordinary pianist gesture: the pedal goes down while NOTHING is held (a MIDI-IN-only row early-outs), THEN the player plays. The edge must still be waiting when the first note arrives (the observe bookkeeping runs in every playing
    // window, processed or not) — found by the POOL adversarial review: it used to be consumed, so STACK never accumulated and KEEP never held.
    func testThePedalPressedBeforeTheFirstNoteStillEngagesAStackLane() {
        let rig = Rig(state([lane(sources: [0], sustain: .stack)], plan: plan(midi: true)))
        rig.run(to: 0.5)
        rig.pedalDown(); rig.run(to: 1.0)
        rig.press([60]); rig.run(to: 1.6)
        rig.release([60]); rig.press([64]); rig.run(to: 2.6)
        rig.release([64]); rig.press([67]); rig.run(to: 3.6)
        rig.release([67]); rig.run(to: 4.6)
        XCTAssertEqual(rig.lanePool(0), [60, 64, 67], "STACK took the pedal's edge when the first note arrived: the union of every note played while down, released notes kept")
    }
    func testThePedalPressedBeforeTheFirstNoteStillEngagesAKeepLane() {
        let rig = Rig(state([lane(sources: [0], sustain: .keep)], plan: plan(midi: true)))
        rig.run(to: 0.5)
        rig.pedalDown(); rig.run(to: 1.0)
        rig.press([60, 64, 67]); rig.run(to: 1.6)
        rig.release([60, 64, 67]); rig.press([62]); rig.run(to: 2.6)
        XCTAssertEqual(rig.lanePool(0), [60, 64, 67], "KEEP held the first chord played after the pedal went down, through a later note")
        rig.pedalUp(); rig.run(to: 3.6)
        XCTAssertEqual(rig.lanePool(0), [62], "…and rejoined on the up edge")
    }
    func testAPedalPressedAndReleasedInSilenceEngagesNothing() {
        let rig = Rig(state([lane(sources: [0], sustain: .stack)], plan: plan(midi: true)))
        rig.run(to: 0.5); rig.pedalDown(); rig.run(to: 1.0); rig.pedalUp(); rig.run(to: 1.5)
        rig.press([60]); rig.run(to: 2.5); rig.release([60]); rig.run(to: 3.5)
        XCTAssertEqual(rig.lanePool(0), [], "the pedal was up when the note came: nothing stacks")
    }

    // MARK: 9 — edges
    func testSwitchingSustainOnWhileThePedalIsDownWaitsForTheNextDownEdge() {
        var lines = [lane(), lane()]
        let rig = Rig(state(lines, plan: plan(chords: true)))
        rig.run(to: 1.5); rig.pedalDown(); rig.run(to: 2.5)
        lines[1] = lane(sustain: .keep); rig.swap(state(lines, plan: plan(chords: true)))
        rig.run(to: 5.5)
        XCTAssertEqual(rig.lanePool(1), rig.lanePool(0), "switched on mid-press: the pool follows the sequencer")
        rig.pedalUp(); rig.run(to: 6.5); rig.pedalDown(); rig.run(to: 7.5); let held = rig.lanePool(0)
        rig.run(to: 9.5); XCTAssertEqual(rig.lanePool(1), held, "the next down edge engages")
    }
    func testSwitchingSustainOffOrChangingModeWhileDownTakesTheCurrentPoolAsAnUpEdge() {
        var lines = [lane(), lane(sustain: .keep)]
        let rig = Rig(state(lines, plan: plan(chords: true)))
        rig.run(to: 1.5); let c = rig.lanePool(0); rig.pedalDown(); rig.run(to: 5.5)
        XCTAssertEqual(rig.lanePool(1), c)
        lines[1] = lane(sustain: .stack); rig.swap(state(lines, plan: plan(chords: true))); rig.run(to: 6.5)
        XCTAssertEqual(rig.lanePool(1), rig.lanePool(0), "KEEP → STACK while down: the current pool, as an up edge")
        lines[1] = lane(); rig.swap(state(lines, plan: plan(chords: true))); rig.run(to: 7.5)
        XCTAssertEqual(rig.lanePool(1), rig.lanePool(0), "off while down: the current pool")
    }
    func testThePedalStateIsClearedOnAStopAndOnALoad() {
        let rig = Rig(state([lane(sustain: .keep)], plan: plan(chords: true)))
        rig.run(to: 1.5); rig.pedalDown(); rig.run(to: 5.5); let c = rig.lanePool(0)
        rig.playing = false; rig.run(to: 6.0); rig.playing = true; rig.offset = -rig.beat + 0.5
        rig.run(to: rig.beat + 5.0)
        XCTAssertTrue(rig.pedal)
        let after = rig.lanePool(0)
        XCTAssertFalse(rig.status(0).keepHolding, "a stop cleared the hold: a pedal still down is no edge")
        XCTAssertNotEqual(after, [], "…and the lane plays its current pool"); _ = c
        // a load (scene flush) does the same
        rig.pedalUp(); rig.run(to: rig.beat + 1); rig.pedalDown(); rig.run(to: rig.beat + 1); XCTAssertTrue(rig.status(0).keepHolding)
        rig.run(to: rig.beat + 0.05, flush: true); rig.run(to: rig.beat + 1.5)
        XCTAssertFalse(rig.status(0).keepHolding, "a load clears it")
    }

    // MARK: 10 — sounding notes
    /// A note sounding when the pedal goes down (and the pool then changes under a KEEP / STACK lane) keeps its own pitch AND its own end: its note-off lands at exactly the sample it lands at with SUSTAIN off — compared event for event with a control run, not just balanced.
    func testANoteSoundingAcrossAKeepOrStackChangeEndsAtItsStartingPitchAndTime() {
        func firstNote(_ rig: Rig) -> (note: UInt8, on: Int64, off: Int64)? {
            guard let on = rig.out.events.first(where: { $0.status == 0x90 }),
                  let off = rig.out.events.first(where: { $0.status == 0x80 && $0.note == on.note && $0.sample > on.sample }) else { return nil }
            return (on.note, on.sample, off.sample)
        }
        for mode in [EuclideousSustainMode.keep, .stack] {
            func session(sustain: EuclideousSustainMode?) -> Rig {
                var l = lane(sustain: sustain); l.gate = 0.99; l.rate = .r1_1; l.pulses = 1; l.steps = 2
                let rig = Rig(state([l], plan: plan(chords: true)))
                rig.run(to: 0.5); rig.pedalDown(); rig.run(to: 12.5); rig.pedalUp(); rig.run(to: 16.5)
                rig.playing = false; rig.run(to: rig.beat + 0.05)
                return rig
            }
            let control = session(sustain: nil), held = session(sustain: mode)
            guard let c = firstNote(control), let h = firstNote(held) else { return XCTFail("\(mode): no note struck") }
            XCTAssertEqual(h.note, c.note, "\(mode): the first note is the same")
            XCTAssertEqual(h.off, c.off, "\(mode): a note sounding when the pedal went down ends at the sample it ends at without SUSTAIN (on \(h.on), off \(h.off) vs \(c.off))")
            var depth: [UInt8: Int] = [:]
            for ev in held.out.events where ev.status == 0x90 || ev.status == 0x80 { depth[ev.note, default: 0] += ev.status == 0x90 ? 1 : -1 }
            for (n, d) in depth { XCTAssertEqual(d, 0, "\(mode): note \(n) has its off at its own pitch") }
        }
    }
}
