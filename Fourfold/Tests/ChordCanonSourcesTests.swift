//  ChordCanonSourcesTests.swift — CHORD CANON, all sources (2026-10-31): a delayed lane hears what the player did `d` beats ago — incoming MIDI (and its note-offs), a PICK edit, a KEY change — as well as the CHORDS progression.
//  The history ring (`EuclideousCanonHistory`) on its own, then the Router against the real engine: lanes that hit once a beat on rank 1 of a flat riff, so each hit plays the LOWEST note of the pool the lane is reading.

import XCTest

private final class SrcEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
}

/// What happens while the engine runs: notes pressed / released at a beat, the document swapped at a beat (a key or PICK edit), and a host loop (the song beat jumps by `by` from that elapsed beat on).
private struct Script {
    var ops: [(beat: Double, on: [UInt8], off: [UInt8])] = []
    var swaps: [(beat: Double, state: PluginState)] = []
    var jumps: [(elapsed: Double, by: Double)] = []
}

final class ChordCanonSourcesTests: XCTestCase {
    private let beat: Int64 = 24_000                         // 120 BPM at 48 kHz

    private func lane(pulses: Int = 4, steps: Int = 4, delay: Int? = nil, slip: Int? = nil) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: pulses, steps: steps)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
        l.chordDelay = delay; l.chordSlip = slip
        return l
    }
    private func plan(midi: Bool = false, chords: Bool = false, pick: Bool = false, key: Bool = false, mode: MidiMode = .add, pickNotes: [UInt8] = []) -> SourcePlan {
        SourcePlan(midiOn: midi, chordsOn: chords, pickOn: pick, keyOn: key, midiMode: mode, pickNotes: pickNotes)
    }
    private func state(_ lines: [EuclidLine], plan: SourcePlan, unit: CanonUnit? = .bars, entry: CanonEntry? = nil, keyRoot: Int = 0) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = [0, 3, 4, 5]; cs.chordsSteps = 4; cs.chordsRate = .r1_1
        st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        st.euclideousSourcePlan = plan
        st.euclideousKeyRoot = keyRoot
        st.euclideousCanonUnit = unit; st.euclideousCanonEntry = entry
        return st
    }
    /// 480-frame windows divide a beat (24 000 frames) into 50, and so do 96 and 2 400: a change at beat 4.5 (108 000 frames) lands on a window boundary at each of those sizes. Changes are put at x.5 on purpose: the lanes
    /// hit on whole beats, and a hit a sample either side of a whole beat (the engine's own rounding) must not be able to fall on the other side of a change.
    private func run(_ st: PluginState, beats: Double, frames: UInt32 = 480, _ script: Script = Script()) -> SrcEmitter {
        var box = SnapshotBuilder.build(from: st)
        let e = SrcEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let p = NotePool()
        var ts = 0.0, offset = 0.0
        var opsDone = 0, swapsDone = 0, jumpsDone = 0
        func elapsed() -> Double { ts * tempo / 60.0 / sr }
        let ops = script.ops.sorted { $0.beat < $1.beat }, swaps = script.swaps.sorted { $0.beat < $1.beat }, jumps = script.jumps.sorted { $0.elapsed < $1.elapsed }
        while elapsed() < beats {
            while opsDone < ops.count, ops[opsDone].beat <= elapsed() + 1e-9 { for n in ops[opsDone].off { p.noteOff(n) }; for n in ops[opsDone].on { p.noteOn(n, velocity: 100, channel: 0) }; opsDone += 1 }
            while swapsDone < swaps.count, swaps[swapsDone].beat <= elapsed() + 1e-9 { box = SnapshotBuilder.build(from: swaps[swapsDone].state); swapsDone += 1 }
            while jumpsDone < jumps.count, jumps[jumpsDone].elapsed <= elapsed() + 1e-9 { offset += jumps[jumpsDone].by; jumpsDone += 1 }
            router.process(box: box, pool: p, playing: true, beatPos: elapsed() + offset, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: elapsed() + offset, tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    /// The note each beat (0…) sounds on one cable (-1 = nothing struck on that beat).
    private func notes(_ e: SrcEmitter, cable: UInt8, beats: Int) -> [Int] {
        var out = [Int](repeating: -1, count: beats)
        for ev in e.ons where ev.cable == cable {
            let b = Int((Double(ev.sample) / Double(beat)).rounded())
            if b >= 0 && b < beats { out[b] = Int(ev.note) }
        }
        return out
    }
    /// A run of beats as `(note, count)` pieces: `seq((48, 4), (53, 4), (-1, 4))`.
    private func seq(_ pieces: (Int, Int)...) -> [Int] { pieces.flatMap { [Int](repeating: $0.0, count: $0.1) } }

    // MARK: the ring

    private func rec(_ h: inout EuclideousCanonHistory, _ e: Double, midi: [Int] = [], playing: Bool = false, pick: [Int] = [], root: Int = 0, mask: UInt16 = 0) {
        h.record(at: e, midi: midi.map { (note: $0, vel: UInt8(100)) }[...], midiPlaying: playing, pick: pick[...], keyRoot: root, keyMask: mask)
    }
    func testTheRingRecordsOnlyChangesAndFindsTheEntryInForce() {
        var h = EuclideousCanonHistory()
        XCTAssertNil(h.seq(atOrBefore: 3))
        rec(&h, 0, midi: [48, 52]); rec(&h, 0.1, midi: [48, 52]); rec(&h, 0.2, midi: [48, 52])          // a held chord: one entry, not one a window
        XCTAssertEqual(h.count, 1)
        rec(&h, 4, midi: [53]); rec(&h, 8, midi: [], playing: true); rec(&h, 8.5, midi: [], playing: true)
        XCTAssertEqual(h.count, 3)
        XCTAssertEqual(h.seq(atOrBefore: -2), 0, "older than everything held: the oldest entry")
        XCTAssertEqual(h.seq(atOrBefore: 0), 0); XCTAssertEqual(h.seq(atOrBefore: 3.99), 0)
        XCTAssertEqual(h.seq(atOrBefore: 4), 1, "an entry is in force from its own beat"); XCTAssertEqual(h.seq(atOrBefore: 7.9), 1)
        XCTAssertEqual(h.seq(atOrBefore: 8), 2); XCTAssertEqual(h.seq(atOrBefore: 1000), 2)
        var buf = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 32)
        XCTAssertEqual(h.fillMidi(0, into: &buf), 2); XCTAssertEqual(buf[0].note, 48); XCTAssertEqual(buf[1].note, 52); XCTAssertEqual(buf[1].vel, 100)
        XCTAssertEqual(h.fillMidi(2, into: &buf), 0); XCTAssertTrue(h.midiPlaying(2)); XCTAssertFalse(h.midiPlaying(1))
        h.reset(); XCTAssertTrue(h.isEmpty); XCTAssertNil(h.seq(atOrBefore: 1))
    }
    func testAnyLayerChangeIsAnEntryAndTheRingKeepsTheNewestWhenItWraps() {
        var h = EuclideousCanonHistory()
        rec(&h, 0); rec(&h, 1, pick: [60]); rec(&h, 2, pick: [60], root: 2); rec(&h, 3, pick: [60], root: 2, mask: 0b101); rec(&h, 4, playing: true, pick: [60], root: 2, mask: 0b101)
        XCTAssertEqual(h.count, 5, "a PICK, KEY root, KEY scale and MIDI-PLAYING change are each an entry")
        var pk = [Int](repeating: 0, count: 16); XCTAssertEqual(h.fillPick(1, into: &pk), 1); XCTAssertEqual(pk[0], 60)
        XCTAssertEqual(h.key(3).root, 2); XCTAssertEqual(h.key(3).mask, 0b101)
        var big = EuclideousCanonHistory()
        let total = EuclideousCanonHistory.capacity + 300
        for i in 0..<total { rec(&big, Double(i), midi: [i % 100]) }                              // every entry differs from its neighbour
        XCTAssertEqual(big.count, EuclideousCanonHistory.capacity); XCTAssertEqual(big.nextSeq, Int64(total)); XCTAssertEqual(big.oldestSeq, 300)
        XCTAssertEqual(big.seq(atOrBefore: 10), 300, "a read older than the ring remembers is the oldest entry")
        XCTAssertEqual(big.seq(atOrBefore: Double(total - 1)), Int64(total - 1)); XCTAssertEqual(big.seq(atOrBefore: 500.5), 500)
        var buf = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 32)
        XCTAssertEqual(big.fillMidi(500, into: &buf), 1); XCTAssertEqual(buf[0].note, 500 % 100)
    }
    func testTheKeyMaskRebuildsExactlyTheNotesTheLiveKeyLayerBuilds() {
        for scale in ScaleType.allCases {
            for root in [0, 2, 9, 11, -3, 14] {
                var out = [Int](repeating: 0, count: 12)
                let n = euclideousCanonKeyNotes(root: root, mask: euclideousCanonKeyMask(tones: scale.intervals), into: &out)
                let r = ((root % 12) + 12) % 12
                XCTAssertEqual(Array(out[0..<n]), scale.intervals.map { 48 + r + $0 }, "\(scale) root \(root)")
            }
        }
    }

    // MARK: incoming MIDI

    func testIncomingMidiReachesADelayedLaneOneBarLateAndTheNoteOffsToo() {
        // C chord held 0–4.5, F chord 4.5–8.5, then the keys are released. Lane 1 hits on whole beats: C on 0…4, F on 5…8, nothing after. Lane 2 is a bar behind: it holds the C chord until the delay has run out, hears the
        // F chord from beat 9 — and keeps playing it after the player has let go, until beat 12.
        let st = state([lane(), lane(delay: 1)], plan: plan(midi: true))
        let e = run(st, beats: 16, Script(ops: [(0, [48, 52, 55], []), (4.5, [53, 57, 60], [48, 52, 55]), (8.5, [], [53, 57, 60])]))
        XCTAssertEqual(notes(e, cable: 1, beats: 16), seq((48, 5), (53, 4), (-1, 7)))
        XCTAssertEqual(notes(e, cable: 2, beats: 16), seq((48, 9), (53, 4), (-1, 3)))
    }
    func testTheDelayedLaneHearsTheSameThingAtEveryBufferSize() {
        let st = state([lane(), lane(delay: 1), lane(delay: 2)], plan: plan(midi: true))
        let script = Script(ops: [(0, [48, 52], []), (4.5, [55], [48, 52]), (6.5, [41], []), (10.5, [], [55, 41])])
        let reference = run(st, beats: 20, frames: 480, script)
        for frames: UInt32 in [96, 2400] {
            let e = run(st, beats: 20, frames: frames, script)
            for c in UInt8(1)...3 { XCTAssertEqual(notes(e, cable: c, beats: 20), notes(reference, cable: c, beats: 20), "cable \(c) at \(frames) frames") }
        }
        XCTAssertNotEqual(notes(reference, cable: 2, beats: 20), notes(reference, cable: 1, beats: 20), "and the lanes really differ")
    }
    func testAHeldChordIsHeardFromTheStartAtEveryDelay() {
        let st = state([lane(), lane(delay: 3), lane(delay: 8)], plan: plan(midi: true))
        let e = run(st, beats: 40, Script(ops: [(0, [60, 64], [])]))
        for c in UInt8(1)...3 { XCTAssertEqual(notes(e, cable: c, beats: 40), seq((60, 40)), "cable \(c)") }
    }
    func testASlipOnIncomingMidiNeverLagsMoreThanOneChange() {
        // slip 50 % on lane 2 with the player changing the held note every two beats for a minute
        var ops: [(beat: Double, on: [UInt8], off: [UInt8])] = []
        for i in 0..<30 {
            let on: [UInt8] = [UInt8(40 + i)]
            let off: [UInt8] = i == 0 ? [] : [UInt8(40 + i - 1)]
            ops.append((beat: i == 0 ? 0 : Double(i * 2) + 0.5, on: on, off: off))
        }
        let e = run(state([lane(), lane(delay: 1, slip: 50)], plan: plan(midi: true)), beats: 60, Script(ops: ops))
        let a = notes(e, cable: 1, beats: 60), b = notes(e, cable: 2, beats: 60)
        for t in 8..<60 {
            let live = a[t - 4], behind = a[max(0, t - 4 - 2)]                                       // what lane 1 played a bar ago, and one change before that
            XCTAssertTrue(b[t] == live || b[t] == behind, "beat \(t): lane 2 played \(b[t]) — not what lane 1 played a bar ago (\(live)) nor the change before it (\(behind))")
        }
        XCTAssertNotEqual(b, notes(run(state([lane(), lane(delay: 1)], plan: plan(midi: true)), beats: 60, Script(ops: ops)), cable: 2, beats: 60), "SLIP really changes what the lane hears")
    }

    // MARK: the other layers

    func testAKeyChangeRipplesDownToADelayedLane() {
        let c = state([lane(), lane(delay: 1)], plan: plan(key: true), keyRoot: 0)
        let d = state([lane(), lane(delay: 1)], plan: plan(key: true), keyRoot: 2)
        let e = run(c, beats: 16, Script(swaps: [(4.5, d)]))
        XCTAssertEqual(notes(e, cable: 1, beats: 16), seq((48, 5), (50, 11)))
        XCTAssertEqual(notes(e, cable: 2, beats: 16), seq((48, 9), (50, 7)), "the same key change, a bar later")
    }
    func testAPickEditRipplesDownToADelayedLane() {
        let a = state([lane(), lane(delay: 1)], plan: plan(pick: true, pickNotes: [60, 64]))
        let b = state([lane(), lane(delay: 1)], plan: plan(pick: true, pickNotes: [67, 71]))
        let e = run(a, beats: 16, Script(swaps: [(4.5, b)]))
        XCTAssertEqual(notes(e, cable: 1, beats: 16), seq((60, 5), (67, 11)))
        XCTAssertEqual(notes(e, cable: 2, beats: 16), seq((60, 9), (67, 7)))
    }
    func testMidiReplacesChordsAtTheTimeTheLaneIsHearingNotNow() {
        // REPLACE: while MIDI plays CHORDS steps aside. MIDI starts at beat 4.5, so lane 1 leaves the chords after its hit on beat 4 and lane 2 — a bar behind — after its hit on beat 8, by the history's own MIDI-PLAYING flag.
        let st = state([lane(), lane(delay: 1)], plan: plan(midi: true, chords: true, mode: .replace))
        let e = run(st, beats: 16, Script(ops: [(4.5, [40], [])]))
        func root(_ k: Int) -> Int { Int(diatonicChord(degree: [0, 3, 4, 5][((k % 4) + 4) % 4], scaleTones: ScaleType.naturalMinor.intervals, rootNote: 48, voicing: .triad, spread: .close).min()!) }
        XCTAssertEqual(notes(e, cable: 1, beats: 16), seq((root(0), 4), (root(1), 1), (40, 11)))
        XCTAssertEqual(notes(e, cable: 2, beats: 16), seq((root(3), 4), (root(0), 4), (root(1), 1), (40, 7)), "wrapped chords, then the chords a bar late, then the MIDI note once it reaches the lane")
    }
    func testTheUndelayedLaneIsNotDisturbedByADelayedOneWhateverTheSources() {
        // The shared pool buffer is re-keyed lane by lane, now for MIDI / PICK / KEY as well: an undelayed lane after a delayed one must hear the LIVE pool.
        let ops: [(beat: Double, on: [UInt8], off: [UInt8])] = [(0, [48], []), (3.5, [55], [48]), (7.5, [41], [55])]
        for p in [plan(midi: true), plan(midi: true, key: true), plan(midi: true, chords: true), plan(midi: true, pick: true, pickNotes: [70])] {
            let plain = run(state([lane(), lane(), lane(), lane()], plan: p), beats: 16, Script(ops: ops))
            let mixed = run(state([lane(), lane(delay: 2), lane(), lane(delay: 1, slip: 20)], plan: p), beats: 16, Script(ops: ops))
            for c in [UInt8(1), 3] { XCTAssertEqual(notes(mixed, cable: c, beats: 16), notes(plain, cable: c, beats: 16), "cable \(c)") }
        }
    }

    // MARK: entry, loops, resets

    #if DEBUG
    func testWaitSilencesEverySourceUntilTheDelayHasRunOut() {
        let st = state([lane(), lane(delay: 1)], plan: plan(midi: true, key: true), entry: .wait)
        let e = run(st, beats: 12, Script(ops: [(0, [60], [])]))
        let b = notes(e, cable: 2, beats: 12), a = notes(e, cable: 1, beats: 12)
        XCTAssertEqual(Array(b[0..<4]), seq((-1, 4)), "silent for a bar: no source sounds while the lane waits — the held MIDI note and the KEY layer included")
        XCTAssertEqual(Array(b[5..<12]), Array(a[5..<12]), "then the pool (the held 60 with the KEY layer placed round it)"); XCTAssertNotEqual(a[6], -1)
        XCTAssertEqual(Set(a), [a[0]], "an undelayed lane never waits")
    }
    #endif
    func testAHostLoopDoesNotBreakTheCanon() {
        // F is pressed at elapsed beat 6.5; the host loops back 8 beats at elapsed 8.5. The history runs on elapsed time, so lane 2 (a bar behind) hears F from elapsed 11 on, however the song beat jumped.
        let st = state([lane(), lane(delay: 1)], plan: plan(midi: true))
        let e = run(st, beats: 16, Script(ops: [(0, [48], []), (6.5, [53], [48])], jumps: [(8.5, -8)]))
        XCTAssertEqual(notes(e, cable: 1, beats: 16), seq((48, 7), (53, 9)))
        XCTAssertEqual(notes(e, cable: 2, beats: 16), seq((48, 11), (53, 5)))
    }
    func testAStopAndRestartStartsTheHistoryOver() {
        // The run's first chord is what a delayed lane holds until its delay runs out: after a stop and a restart that is the chord held at the RESTART, not the one from the first run.
        var st = state([lane(), lane(delay: 1)], plan: plan(midi: true))
        st.euclideousCanonEntry = nil
        let box = SnapshotBuilder.build(from: st)
        let e = SrcEmitter(); let router = Router(); var diag = KernelDiag()
        let p = NotePool(); var ts = 0.0
        func go(_ n: Int, playing: Bool) { for _ in 0..<n { router.process(box: box, pool: p, playing: playing, beatPos: ts * 120 / 60 / 48_000, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 480, forceColumn: 0, out: e, diag: &diag); ts += 480 } }
        p.noteOn(48, velocity: 100, channel: 0); go(8 * 50, playing: true)          // 8 beats on C
        go(50, playing: false)
        p.noteOff(48); p.noteOn(60, velocity: 100, channel: 0)
        let restart = e.events.count
        go(6 * 50, playing: true)                                                    // the second run: a held 60 from its first window
        let second = e.events[restart...].filter { $0.status == 0x90 && $0.cable == 2 }.map { Int($0.note) }
        XCTAssertFalse(second.isEmpty); XCTAssertEqual(Set(second), [60], "lane 2 holds the NEW run's first pool, never the old run's C")
    }
}
