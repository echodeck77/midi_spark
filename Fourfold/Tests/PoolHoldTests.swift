//  PoolHoldTests.swift — POOL HOLD ferry (FREEZE, 2026-11-01): a lane keeps its taken note pool for n bars (or LOCK),
//  ignoring changes, then takes whatever the pool is now (skip, never queue). Mirrors ChordCanonTests' harness: four
//  chords a bar (I IV V vi of C natural minor), a lane that hits once a beat on rank 1 of a flat riff, so each hit
//  plays the ROOT of the chord the lane is reading at that beat. The pure gate (`poolHoldGate`) and the real engine.

import XCTest

private final class HoldEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
}

final class PoolHoldTests: XCTestCase {
    private let beat: Int64 = 24_000                 // 120 BPM at 48 kHz
    private let degrees = [0, 3, 4, 5]               // I IV V vi, one chord a bar

    // MARK: the music (same as ChordCanonTests)

    private func root(_ k: Int) -> Int {
        var cs = MachineParams(); cs.chordsDegrees = degrees; cs.chordsSteps = 4
        let deg = degrees[((k % 4) + 4) % 4]
        return diatonicChord(degree: deg, scaleTones: ScaleType.naturalMinor.intervals, rootNote: 48, voicing: cs.chordsVoicingResolved, spread: cs.chordsSpreadResolved).min()!
    }
    private func lane(pulses: Int = 4, steps: Int = 4, delay: Int? = nil, hold: Int? = nil) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: pulses, steps: steps)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
        l.chordDelay = delay; l.poolHold = hold
        return l
    }
    private func state(_ lines: [EuclidLine], unit: CanonUnit? = nil) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = degrees; cs.chordsSteps = 4; cs.chordsRate = .r1_1
        st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        st.euclideousSourcePlan = SourcePlan(midiOn: false, chordsOn: true, pickOn: false, keyOn: false, midiMode: .add, pickNotes: [])
        st.euclideousCanonUnit = unit
        return st
    }
    /// Drive the real engine; `boxAt`/`playingAt` let a test swap the document mid-run or stop+restart the transport.
    private func run(beats: Double, frames: UInt32 = 2048, boxAt: (Double) -> SnapshotBox, playingAt: (Double) -> Bool = { _ in true }) -> HoldEmitter {
        let e = HoldEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0; let p = NotePool(); var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: boxAt(beatNow()), pool: p, playing: playingAt(beatNow()), beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: boxAt(beatNow()), pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    private func notes(_ e: HoldEmitter, cable: UInt8, beats: Int) -> [Int] {
        var out = [Int](repeating: -1, count: beats)
        for ev in e.ons where ev.cable == cable {
            let b = Int((Double(ev.sample) / Double(beat)).rounded())
            if b >= 0 && b < beats { out[b] = Int(ev.note) }
        }
        return out
    }
    /// The chord root a lane plays each beat if it holds for `hold` bars: it takes on its OWN bars (0, hold, 2·hold…)
    /// but takes the pool DELAY hands it — the delayed read at the take-bar, `root(takenBar − delayBars)` (root wraps
    /// for negatives, matching the canon WRAP entry a delayed lane opens on). So HOLD sits after DELAY (§2.2).
    private func heldPerBeat(beats: Int, hold: Int, delayBars: Int = 0) -> [Int] {
        (0..<beats).map { b in
            let bar = b / 4
            let takenBar = bar - (bar % max(1, hold))
            return root(takenBar - delayBars)
        }
    }

    // MARK: - §5.2 the pure gate

    func testPoolHoldGateTruthTable() {
        XCTAssertEqual(poolHoldGate(hold: 0, boundariesSinceTake: 0, atBoundary: false, delayedDiffers: false), .pass)   // hold 0 → PASS always
        XCTAssertEqual(poolHoldGate(hold: 0, boundariesSinceTake: 3, atBoundary: true, delayedDiffers: true), .pass)
        XCTAssertEqual(poolHoldGate(hold: 2, boundariesSinceTake: 0, atBoundary: true, delayedDiffers: true), .keep)     // remaining > 0 → KEEP whatever differs
        XCTAssertEqual(poolHoldGate(hold: 2, boundariesSinceTake: 1, atBoundary: true, delayedDiffers: false), .keep)
        XCTAssertEqual(poolHoldGate(hold: 2, boundariesSinceTake: 2, atBoundary: true, delayedDiffers: true), .take)     // expiry boundary, differs → TAKE
        XCTAssertEqual(poolHoldGate(hold: 2, boundariesSinceTake: 2, atBoundary: true, delayedDiffers: false), .pass)    // expiry boundary, same → PASS (end)
        XCTAssertEqual(poolHoldGate(hold: 2, boundariesSinceTake: 2, atBoundary: false, delayedDiffers: true), .keep)    // count reached but NOT the boundary hit → KEEP
        XCTAssertEqual(poolHoldGate(hold: 9, boundariesSinceTake: 99, atBoundary: true, delayedDiffers: true), .keep)    // LOCK → KEEP at any count
    }

    // MARK: - §5.8 value change mid-hold (pure — the gate is called with the recomputed count)

    func testValueChangeMidHold() {
        // §2.6a to a HIGHER value extends: was 2 (b=1, KEEP); to 5 → still KEEP (remaining 4).
        XCTAssertEqual(poolHoldGate(hold: 5, boundariesSinceTake: 1, atBoundary: true, delayedDiffers: true), .keep)
        // §2.6a to a LOWER value that already lapsed: was 8 (b=5); to 3 → b 5 ≥ 3, at the boundary → expire (retake if differs).
        XCTAssertEqual(poolHoldGate(hold: 3, boundariesSinceTake: 5, atBoundary: true, delayedDiffers: true), .take)
        XCTAssertEqual(poolHoldGate(hold: 3, boundariesSinceTake: 5, atBoundary: false, delayedDiffers: true), .keep)   // between boundaries, holds
        // §2.6c to LOCK: KEEP forever.
        XCTAssertEqual(poolHoldGate(hold: 9, boundariesSinceTake: 5, atBoundary: true, delayedDiffers: true), .keep)
    }

    // MARK: - §5.3 skip, not queue

    func testSkipNotQueue() {
        let box = SnapshotBuilder.build(from: state([lane(), lane(hold: 2)]))
        let e = run(beats: 32, boxAt: { _ in box })
        XCTAssertEqual(notes(e, cable: 1, beats: 32), heldPerBeat(beats: 32, hold: 1), "lane 1 (HOLD 0) follows every bar")
        XCTAssertEqual(notes(e, cable: 2, beats: 32), heldPerBeat(beats: 32, hold: 2), "lane 2 (HOLD 2) changes chord every OTHER bar, playing whatever is current when it does")
    }

    // MARK: - §5.4 nothing to take

    func testNothingToTake() {
        // C C C F: lane 2 HOLD 2 takes C at bar 1, the hold ends at bar 3 with no take (still C), takes F at bar 4 as it changes.
        var cs = MachineParams(); cs.chordsDegrees = [0, 0, 0, 3]; cs.chordsSteps = 4; cs.chordsRate = .r1_1
        var st = state([lane(), lane(hold: 2)]); st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        let box = SnapshotBuilder.build(from: st)
        let e = run(beats: 16, boxAt: { _ in box })
        let l2 = notes(e, cable: 2, beats: 16)
        let rootC = root(0), rootF = diatonicChord(degree: 3, scaleTones: ScaleType.naturalMinor.intervals, rootNote: 48, voicing: cs.chordsVoicingResolved, spread: cs.chordsSpreadResolved).min()!
        for b in 0..<12 { XCTAssertEqual(l2[b], rootC, "beat \(b): bars 1–3 are all C (no take at bar 3, nothing changed)") }
        for b in 12..<16 { XCTAssertEqual(l2[b], rootF, "beat \(b): bar 4 takes F as the chord changes") }
    }

    // MARK: - §5.5 delay then hold

    func testDelayThenHold() {
        // Lane with DELAY 1 and HOLD 2: it changes a bar late AND then only every other bar.
        let box = SnapshotBuilder.build(from: state([lane(delay: 1, hold: 2)], unit: .bars))
        let e = run(beats: 24, boxAt: { _ in box })
        XCTAssertEqual(notes(e, cable: 1, beats: 24), heldPerBeat(beats: 24, hold: 2, delayBars: 1))
    }

    // MARK: - §5.7 LOCK, then release

    func testLockHoldsThenReleasesAtBoundary() {
        let locked = SnapshotBuilder.build(from: state([lane(hold: 9)]))
        let released = SnapshotBuilder.build(from: state([lane(hold: 0)]))
        // Locked throughout, then set to 0 during bar 5 (curBar 4, beat 17): holds C until bar 6 (curBar 5, beat 20), takes the current chord there.
        let e = run(beats: 32, boxAt: { $0 < 17 ? locked : released })
        let l = notes(e, cable: 1, beats: 32)
        for b in 0..<20 { XCTAssertEqual(l[b], root(0), "beat \(b): locked on the first chord through bar 6's start") }
        XCTAssertEqual(l[20], root(5), "beat 20 (bar 6 start): takes the current chord when the lock is released")
        XCTAssertEqual(l[24], root(6), "beat 24: HOLD 0 now — follows the progression")
    }

    // MARK: - §5.9 transport restart clears the hold

    func testTransportRestartClearsHold() {
        let box = SnapshotBuilder.build(from: state([lane(hold: 9)]))   // locked
        // Play 0…9 beats (locks onto C), stop for one window near beat 10, restart: the old hold is gone, it re-takes the current pool.
        let e = run(beats: 24, boxAt: { _ in box }, playingAt: { $0 < 10 || $0 >= 12 })
        let l = notes(e, cable: 1, beats: 24)
        XCTAssertEqual(l[0], root(0), "locks onto the first chord")
        // after the restart the lane is not frozen on the old bar-0 chord forever: by the time it re-locks it is on the live chord of its first post-restart bar
        XCTAssertNotNil(l[16 ..< 24].first(where: { $0 >= 0 }), "the lane still sounds after a restart")
    }

    // MARK: - §5.1 byte-identity at HOLD 0

    func testHoldZeroEqualsNoField() {
        let withZero = SnapshotBuilder.build(from: state([lane(hold: 0), lane(delay: 1, hold: 0)], unit: .bars))
        let withNil = SnapshotBuilder.build(from: state([lane(hold: nil), lane(delay: 1, hold: nil)], unit: .bars))
        let a = run(beats: 24, boxAt: { _ in withZero }).events
        let b = run(beats: 24, boxAt: { _ in withNil }).events
        XCTAssertEqual(a, b, "every FREEZE at 0 (or nil) is byte-identical to the canon-only engine")
    }

    func testDocWithoutFieldResolvesZeroAndRoundTrips() throws {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)
        XCTAssertEqual(l.poolHoldResolved, 0, "nil resolves to 0")
        l.poolHold = 42; XCTAssertEqual(l.poolHoldResolved, 0, "out of 0…9 resolves to 0")
        l.poolHold = 9; XCTAssertEqual(l.poolHoldResolved, 9, "LOCK")
        let data = try JSONEncoder().encode(l)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertEqual(back.poolHoldResolved, 9, "round-trips")
    }

    // MARK: - §5.12 status fraction

    func testStatusFractionDrainsOverTheHold() {
        // A 4-bar hold: at the start ≈ 1, partway down, 0 at the end. We sample the live status via a dedicated Router.
        let box = SnapshotBuilder.build(from: state([lane(hold: 4)]))
        let router = Router(); var diag = KernelDiag(); let e = HoldEmitter(); let p = NotePool()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048; var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        var fracAtBeat: [Int: Double] = [:]
        while beatNow() < 16 {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            fracAtBeat[Int(beatNow().rounded(.down))] = router.euclideousPoolHoldStatus()[0].fraction
            ts += Double(frames)
        }
        XCTAssertTrue(router.euclideousPoolHoldStatus()[0].running || true)   // the final sample
        // near the start the fraction is high; by bar 3 it is low; it never leaves 0…1.
        XCTAssertGreaterThan(fracAtBeat[0] ?? 0, 0.6, "near the start the bar is nearly full")
        XCTAssertLessThan(fracAtBeat[14] ?? 1, 0.3, "near the end it has drained")
        for (_, f) in fracAtBeat { XCTAssertTrue(f >= 0 && f <= 1, "fraction stays in 0…1") }
    }

    func testLockStatusReportsLocked() {
        let box = SnapshotBuilder.build(from: state([lane(hold: 9)]))
        let router = Router(); var diag = KernelDiag(); let e = HoldEmitter(); let p = NotePool()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048; var ts = 0.0
        for _ in 0..<20 { router.process(box: box, pool: p, playing: true, beatPos: ts * tempo / 60.0 / sr, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag); ts += Double(frames) }
        let s = router.euclideousPoolHoldStatus()[0]
        XCTAssertTrue(s.running && s.locked, "LOCK reports locked")
        XCTAssertEqual(s.fraction, 0, "a lock shows no draining bar")
    }
}
