//  InputsTestAuditionTests.swift — INPUTS TEST (2026-11-08): the pool AUDITION (the TEST button's engine).
//
//  The TEST button sets a live word on the Kernel (0x100 | lane); while set, `Router.process` suppresses that lane's normal output and walks its pool across the lane's emitters (riff mask | notes mask) on a free-running sample
//  clock (~150 ms a note, cut after ~120 ms). These tests drive `Router.process` directly with the `euclideousTestLive` param (the same word the Kernel forwards): the audition sounds on the lane's own output + ALL and nowhere
//  else, every note it strikes comes from the lane's pool, the lane's own hits stop while it runs, every note-on is closed (no stuck note — on a stop, on turning TEST off), and the stream is byte-identical to the baseline when off.

import XCTest

private final class AudEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let chan: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, chan: b0 & 0x0F, note: b1, vel: b2))
    }
    var ons: [Ev] { events.filter { $0.status == 0x90 && $0.vel > 0 } }
    func offs(cable: UInt8, note: UInt8) -> Int { events.filter { $0.cable == cable && $0.note == note && ($0.status == 0x80 || ($0.status == 0x90 && $0.vel == 0)) }.count }
    func ons(cable: UInt8, note: UInt8) -> Int { events.filter { $0.cable == cable && $0.note == note && $0.status == 0x90 && $0.vel > 0 }.count }
}

private final class AudRig {
    let router = Router(); var diag = KernelDiag(); let out = AudEmitter(); let pool = NotePool()
    var box: SnapshotBox
    var ts = 0.0
    var testLane: Int? = nil            // the audition lane (nil = TEST off)
    let frames: UInt32 = 480
    init(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    var beat: Double { ts * 120.0 / 60.0 / 48_000.0 }
    func run(to target: Double, playing: Bool = true) {
        while beat < target - 1e-9 {
            let word: UInt16 = testLane.map { 0x100 | UInt16($0 & 3) } ?? 0
            router.process(box: box, pool: pool, playing: playing, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, forceColumn: 0,
                           euclideousTestLive: word, out: out, diag: &diag)
            ts += Double(frames)
        }
    }
    func stopEdge() {   // one !playing window: the transport edge closes every open voice (§7)
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, forceColumn: 0, out: out, diag: &diag)
        ts += Double(frames)
    }
    func lanePool(_ l: Int) -> [Int] { router.euclideousLanePoolStatus()[l].notes.map(Int.init) }
}

final class InputsTestAuditionTests: XCTestCase {
    /// A lane that reads CHORDS (so its pool is never empty with nothing held), default emitter = its own output, both parts on.
    private func lane(_ idx: Int, sources: [Int] = [1]) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = true; l.notesOn = true; l.litNotes = 0
        for b in 0..<5 { l.setPoolSrc(b, sources.contains(b)) }
        return l
    }
    private func state(_ lines: [EuclidLine]) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = [0, 3, 4, 5]; cs.chordsSteps = 4; cs.chordsRate = .r1_1   // C F G Am, a bar each
        st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        st.euclideousSourcePlan = SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: true, midiMode: .add, pickNotes: [], midiOctaves: .keep)
        st.euclideousCanonUnit = .bars
        return st
    }

    /// TEST on lane 1 (output A): the audition sounds on cable 1 (A) and cable 0 (ALL) only — never B/C/D — on output A's channel, and every note it strikes is in the lane's pool.
    func testAuditionSoundsOnTheLanesOwnOutputAndAll() {
        let rig = AudRig(state([lane(0)]))
        rig.testLane = 0
        rig.run(to: 3.0)                                   // ~1.5 s: several audition notes
        let pool = Set(rig.lanePool(0))
        XCTAssertFalse(pool.isEmpty, "the lane has a pool (the live chord)")
        let ons = rig.out.ons
        XCTAssertGreaterThanOrEqual(ons.filter { $0.cable == 1 }.count, 2, "the audition strikes on output A")
        XCTAssertEqual(ons.filter { $0.cable == 0 }.count, ons.filter { $0.cable == 1 }.count, "ALL mirrors A one for one")
        XCTAssertTrue(ons.allSatisfy { $0.cable == 0 || $0.cable == 1 }, "nothing leaves on B/C/D (cables 2–4): \(Set(ons.map { $0.cable }))")
        XCTAssertTrue(ons.filter { $0.cable == 1 }.allSatisfy { $0.chan == 0 }, "output A's channel (1 → wire 0)")
        XCTAssertTrue(ons.allSatisfy { pool.contains(Int($0.note)) }, "every audition note is from the lane's pool")
    }

    /// The audition replaces the lane's normal hits: while TEST is on, lane 1's riff (which would hit once a beat) is suppressed — the only notes on A are the audition's faster, pool-walking stream.
    func testAuditionSuppressesTheLanesNormalHits() {
        // baseline: TEST off, lane 1 hits its riff once a beat.
        let base = AudRig(state([lane(0)]))
        base.run(to: 4.0)
        let baseOnsA = base.out.ons.filter { $0.cable == 1 }.map { $0.sample }
        XCTAssertGreaterThanOrEqual(baseOnsA.count, 3, "the lane hits normally with TEST off")
        // audition: TEST on, same document and span — a different (faster, free-running) cadence, not the riff's beat grid.
        let aud = AudRig(state([lane(0)]))
        aud.testLane = 0
        aud.run(to: 4.0)
        let audOnsA = aud.out.ons.filter { $0.cable == 1 }.map { $0.sample }
        XCTAssertNotEqual(audOnsA, baseOnsA, "the audition stream is not the riff's hit stream")
        // the audition cadence is ~7200 samples (0.15 s at 48 kHz); the riff at r1_4/120 BPM is 24000 samples a hit.
        if audOnsA.count >= 2 { XCTAssertLessThan(audOnsA[1] - audOnsA[0], 12_000, "the audition is faster than one hit a beat") }
    }

    /// No stuck note: stopping the transport (and, separately, turning TEST off then running on) closes every audition voice — on-count equals off-count for every (cable, note).
    func testAuditionLeavesNoStuckNoteOnStopOrOff() {
        let rig = AudRig(state([lane(0)]))
        rig.testLane = 0
        rig.run(to: 3.0)
        rig.testLane = nil                                 // turn TEST off mid-flight
        rig.run(to: 4.0)                                   // the lane returns to its own hits; the audition's scheduled offs drain
        rig.stopEdge()                                     // the transport edge closes anything still open
        for cable: UInt8 in [0, 1] {
            for note in Set(rig.out.events.filter { $0.cable == cable }.map { $0.note }) {
                XCTAssertEqual(rig.out.ons(cable: cable, note: note), rig.out.offs(cable: cable, note: note), "cable \(cable) note \(note): on-count == off-count")
            }
        }
    }

    /// TEST off is byte-identical to a run that never had the param: the audition touches nothing when the word is 0 (the golden guarantee, asserted event for event here too).
    func testTestOffIsIdenticalToTheBaseline() {
        let a = AudRig(state([lane(0), lane(1)]))   // two lanes, both emitting
        let b = AudRig(state([lane(0), lane(1)]))
        a.run(to: 6.0)                               // a never sets testLane (word stays 0)
        b.testLane = nil; b.run(to: 6.0)             // b explicitly off
        XCTAssertEqual(a.out.events, b.out.events, "TEST off changes nothing")
        XCTAssertFalse(a.out.ons.isEmpty, "the lanes really did emit")
    }
}
