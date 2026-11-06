//  PoolHoldTests.swift — POOL HOLD ferry (FREEZE, 2026-11-01), as the INPUTS ferry (2026-11-06) left it: the engine no longer reads FREEZE or SLIP (their fields stay), so the engine tests assert they change nothing;
//  the pure gate stays tested. Originally: a lane keeps its taken note pool for n bars (or LOCK), ignoring changes, then takes whatever the pool is now (skip, never queue). Mirrors ChordCanonTests' harness: four
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

    // MARK: - INPUTS ferry 1.4 / test 7 — FREEZE is no longer read by the engine

    /// A lane with FREEZE 2 bars, or LOCK, plays exactly as the same lane with FREEZE 0: the field is kept, nothing reads it.
    func testFreezeNoLongerHoldsAnything() {
        let off = SnapshotBuilder.build(from: state([lane(), lane(delay: 1, hold: 0)], unit: .bars))
        for hold in [2, 9] {
            let on = SnapshotBuilder.build(from: state([lane(hold: hold), lane(delay: 1, hold: hold)], unit: .bars))
            XCTAssertEqual(run(beats: 24, boxAt: { _ in on }).events, run(beats: 24, boxAt: { _ in off }).events, "FREEZE \(hold): ignored")
        }
        let e = run(beats: 24, boxAt: { _ in off })
        XCTAssertEqual(notes(e, cable: 1, beats: 24), heldPerBeat(beats: 24, hold: 1), "…and the lane follows every bar, as a lane with no FREEZE always did")
    }

    /// The same for SLIP: a document that sets it plays as if it were 0.
    func testSlipNoLongerShiftsAnything() {
        var slipped = lane(delay: 1); slipped.chordSlip = 50
        let on = SnapshotBuilder.build(from: state([slipped], unit: .bars)), off = SnapshotBuilder.build(from: state([lane(delay: 1)], unit: .bars))
        XCTAssertEqual(run(beats: 24, boxAt: { _ in on }).events, run(beats: 24, boxAt: { _ in off }).events)
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
}
