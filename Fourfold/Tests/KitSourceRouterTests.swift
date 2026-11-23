//  KitSourceRouterTests.swift — KIT SOURCE ferry (2026-11-23): the ENGINE (§2/§3) on the real euclideous-row path.
//  A KIT lane's pool is exactly its 8 kit notes (no pitch change reaches them), scaled per rank by kitVel. The golden
//  harness proves that with no KIT lane the output is byte-identical.

import XCTest

private final class KitEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1, vel: b2))
    }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
    func laneNotes(_ lane: Int) -> [Int] { ons.filter { Int($0.cable) == lane + 1 }.sorted { $0.sample < $1.sample }.map { Int($0.note) } }
    func laneOns(_ lane: Int) -> [Ev] { ons.filter { Int($0.cable) == lane + 1 }.sorted { $0.sample < $1.sample } }
}

final class KitSourceRouterTests: XCTestCase {

    private let pool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]   // a held MIDI chord — a KIT lane must IGNORE it (§2.4)

    private func riffLine(kitNotes: [UInt8]?, kitVel: [UInt8]? = nil, octave: Int = 0, riffOctave: Int = 0, melodyTranspose: Int = 0) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, octave: octave, rate: .r1_4, useRiff: true, riffOn: true, sourceMode: .midi)
        l.gate = 0.5; l.riffOctave = riffOctave; l.melodyTranspose = melodyTranspose
        if let k = kitNotes { l.kitOn = true; l.kitNotes = k; l.kitVel = kitVel }
        return l
    }
    private func stackLine(kitNotes: [UInt8], kitVel: [UInt8], litNotes: UInt8) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, octave: 0, rate: .r1_4, useRiff: true, riffOn: false, sourceMode: .midi)
        l.gate = 0.5; l.notesOn = true; l.setLitOrder(.derived(litNotes: litNotes, top: false, top2: false)); l.notesGate = 0.3
        l.notesVoicesChain = [EuclideousVoicesChip(value: .all)]   // PLAY AS ROWS: VOICES ALL = every lit rank in ONE hit (the old CHORD), so the duplicate ranks collide on one strike (§3.4)
        l.kitOn = true; l.kitNotes = kitNotes; l.kitVel = kitVel
        return l
    }
    private func state(_ lines: [EuclidLine]) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = lines + (lines.count < 4 ? (lines.count..<4).map { _ in EuclidLine(enabled: false) } : [])
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        return st
    }
    private func held() -> NotePool { let p = NotePool(); for n in pool { p.noteOn(n, velocity: 100, channel: 0) }; return p }
    private func run(_ st: PluginState, beats: Double) -> KitEmitter {
        var d = st; var pl = d.sourcePlanResolved; pl.midiOctaves = .keep; d.euclideousSourcePlan = pl
        let box = SnapshotBuilder.build(from: d)
        let e = KitEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: held(), playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: held(), playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }

    // §2.1/§2.4 — the pool is the kit notes in stored order, ignoring the held MIDI chord.
    func testPoolIsTheKit() {
        let kit: [UInt8] = [36, 38, 42, 46, 49, 51, 37, 39]
        let notes = run(state([riffLine(kitNotes: kit)]), beats: 24).laneNotes(0)
        XCTAssertFalse(notes.isEmpty)
        XCTAssertTrue(notes.allSatisfy { kit.contains(UInt8($0)) }, "every note is a kit note (the held chord 48…60 is ignored)")
        XCTAssertTrue(notes.contains(36) && notes.contains(49), "the walk reaches ranks across the kit")
        XCTAssertFalse(notes.contains(48), "the held MIDI chord's notes never sound on a KIT lane")
    }

    // §2.2 — no pitch change: octave / riffOctave do NOT shift a kit note; a non-KIT lane IS shifted.
    func testNoPitchChange() {
        let kit: [UInt8] = [36, 38, 42, 46, 49, 51, 37, 39]
        let shifted = run(state([riffLine(kitNotes: kit, octave: 1, riffOctave: 2)]), beats: 24).laneNotes(0)
        XCTAssertTrue(shifted.allSatisfy { kit.contains(UInt8($0)) }, "octave/riffOctave leave every kit note at its pitch")
        // a NON-kit lane with riffOctave 2 IS shifted up (the guard is kit-specific)
        let plain = run(state([riffLine(kitNotes: nil, riffOctave: 2)]), beats: 8).laneNotes(0)
        XCTAssertTrue(plain.contains { $0 >= 72 }, "a non-KIT lane's riffOctave still raises the pitch")
    }

    // §3.1/§3.2 — kitVel scales the velocity; 0 sends nothing (but the walk still advances).
    func testVelocityScale() {
        let kit: [UInt8] = [36, 37, 38, 39, 42, 44, 46, 49]
        let vel: [UInt8] = [50, 100, 0, 100, 100, 100, 100, 100]   // rank 1 half, rank 3 silent
        let e = run(state([riffLine(kitNotes: kit, kitVel: vel)]), beats: 24)
        let ons = e.laneOns(0)
        XCTAssertFalse(ons.isEmpty)
        for ev in ons where ev.note == 36 { XCTAssertEqual(ev.vel, 50, "rank 1 (36) plays at 50 % of 100") }
        XCTAssertFalse(ons.contains { $0.note == 38 }, "rank 3 (38) at kitVel 0 sends no note")
        XCTAssertTrue(ons.contains { $0.note == 37 && $0.vel == 100 }, "rank 2 (37) at 100 % unchanged")
        // the walk still reaches the ranks after the silent one (rank 3 counts as played)
        XCTAssertTrue(ons.contains { $0.note == 39 }, "rank 4 (39) still plays — the silent rank 3 did not stall the walk")
    }

    // §3.4 — duplicate ranks sending the same note to one emitter sound once, at the higher kit velocity.
    func testDuplicateRanksHighestVelocity() {
        // ranks 1 and 2 both play note 42, kitVel 60 and 90; litOrder ranks 1+2 ⇒ one stack hit strikes both.
        let kit: [UInt8] = [42, 42, 52, 55, 49, 51, 37, 39]
        let vel: [UInt8] = [60, 90, 100, 100, 100, 100, 100, 100]
        let e = run(state([stackLine(kitNotes: kit, kitVel: vel, litNotes: 0b0000_0011)]), beats: 16)   // ranks 1 + 2
        let ons42 = e.laneOns(0).filter { $0.note == 42 }
        XCTAssertFalse(ons42.isEmpty)
        // each stack hit emits ONE 42 (not two), at the higher velocity 90
        XCTAssertTrue(ons42.allSatisfy { $0.vel == 90 }, "the duplicate 42 sounds once at the higher kit velocity (90), not 60")
    }

    // §2.1 — a KIT lane with a NON-DEFAULT source mask (here: MIDI chip OFF, KEY on) still plays ONLY the kit, not its configured sources.
    func testKitBypassesNonDefaultSources() {
        let kit: [UInt8] = [36, 38, 42, 46, 49, 51, 37, 39]
        var l = riffLine(kitNotes: kit)
        l.setPoolSrc(0, false)   // MIDI IN off
        l.setPoolSrc(3, true)    // KEY on — a non-default mask; without the kit bypass the lane would play a KEY pool, not the held chord
        let notes = run(state([l]), beats: 24).laneNotes(0)
        XCTAssertFalse(notes.isEmpty)
        XCTAssertTrue(notes.allSatisfy { kit.contains(UInt8($0)) }, "a non-default-mask KIT lane still plays exactly the kit")
        XCTAssertFalse(notes.contains(48), "the held chord never leaks in")
    }

    // §2.1 — a KIT-only lane (no source chips, NOTHING held) still sounds: the kit IS the source, so the row must not early-out.
    func testKitOnlyLaneWithNothingHeldSounds() {
        let kit: [UInt8] = [36, 38, 42, 46, 49, 51, 37, 39]
        var l = riffLine(kitNotes: kit)
        for b in 0..<5 { l.setPoolSrc(b, false) }   // every source chip OFF — only KIT
        let st = state([l])
        // run with an EMPTY held pool (nothing down), the device case
        var d = st; var pl = d.sourcePlanResolved; pl.midiOctaves = .keep; d.euclideousSourcePlan = pl
        let box = SnapshotBuilder.build(from: d)
        let e = KitEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048; var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < 24 {
            router.process(box: box, pool: NotePool(), playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        let notes = e.laneNotes(0)
        XCTAssertFalse(notes.isEmpty, "a KIT-only lane sounds with nothing held and no source chips on")
        XCTAssertTrue(notes.allSatisfy { kit.contains(UInt8($0)) }, "and plays exactly the kit")
    }

    // §4.8 — the one-shot editor audition emits a note-on at the given velocity AND its note-off, even while the host is STOPPED (playing=false): the preview fires before the `!playing` early-out, and drainDue sends the off.
    func testEditorAuditionSoundsWhileStopped() {
        let kit: [UInt8] = [36, 38, 42, 46, 49, 51, 37, 39]
        let st = state([riffLine(kitNotes: kit)])
        var d = st; var pl = d.sourcePlanResolved; pl.midiOctaves = .keep; d.euclideousSourcePlan = pl
        let box = SnapshotBuilder.build(from: d)
        let e = KitEmitter(); let router = Router(); var diag = KernelDiag()
        let sr = 48_000.0, frames: UInt32 = 2048
        let word: UInt32 = (UInt32(1) << 16) | (UInt32(0) << 14) | (UInt32(100) << 7) | UInt32(60)   // lane 0, note 60, vel 100, seq 1
        // STOPPED (playing=false) across several windows so the 120 ms off falls due; sample clock advances as it does under a stopped host.
        var ts = 0.0
        for _ in 0..<12 { router.process(box: box, pool: NotePool(), playing: false, beatPos: 0, tempo: 120, sampleRate: sr, timestampSample: ts, frameCount: frames, euclideousKitAudWord: word, out: e, diag: &diag); ts += Double(frames) }
        let ons = e.ons.filter { $0.note == 60 && $0.vel > 0 && $0.cable == 1 }   // the lane's own output (cable 1 = A); the ALL mirror (cable 0) doubles it
        XCTAssertEqual(ons.count, 1, "fires exactly once (seq unchanged) while stopped")
        XCTAssertEqual(ons.first?.vel, 100, "at the velocity passed in")
        let offs = e.events.filter { $0.note == 60 && ($0.status == 0x80 || ($0.status == 0x90 && $0.vel == 0)) }
        XCTAssertFalse(offs.isEmpty, "and its note-off is sent (no stuck preview note) while stopped")
    }

    // DRUM MODE helpers / tests
    private func drumLine(note: UInt8, low: UInt8 = 40, high: UInt8 = 100, ramp: EuclideousDrumRamp = .up) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, octave: 0, rate: .r1_4, useRiff: true, riffOn: true, sourceMode: .midi)
        l.gate = 0.5; l.kitOn = true; l.fixedMode = .drum; l.drumNote = note; l.drumLow = low; l.drumHigh = high; l.drumRamp = ramp
        return l
    }

    // §6.3 — a DRUM lane's pool is drumNote eight times (every rank plays the one note).
    func testDrumPoolIsOneNote() {
        let notes = run(state([drumLine(note: 38)]), beats: 24).laneNotes(0)
        XCTAssertFalse(notes.isEmpty)
        XCTAssertTrue(notes.allSatisfy { $0 == 38 }, "every rank plays the one drum note")
        XCTAssertFalse(notes.contains(48), "the held chord never leaks in")
    }

    // §6.4 — the ramp velocity feeds the velocity scale; a 0 % rank sends nothing but the walk continues.
    func testDrumRampVelocity() {
        // low 0, high 100, UP ⇒ rank 1 = 0 % (silent), rank 8 = 100 %. Base velocity is the riff pad default (100), so the scaled velocity equals the ramp percent.
        let e = run(state([drumLine(note: 38, low: 0, high: 100, ramp: .up)]), beats: 48)
        let ons = e.laneOns(0)
        XCTAssertFalse(ons.isEmpty)
        XCTAssertTrue(ons.allSatisfy { $0.note == 38 })
        XCTAssertTrue(ons.contains { $0.vel == 100 }, "rank 8 at 100 %")
        XCTAssertTrue(ons.allSatisfy { $0.vel >= 1 }, "no on carries velocity 0 (a 0 % rank sends nothing, not a silent note)")
        // DOWN reverses it — rank 1 loudest
        let down = run(state([drumLine(note: 38, low: 0, high: 100, ramp: .down)]), beats: 48).laneOns(0)
        XCTAssertTrue(down.contains { $0.vel == 100 })
    }

    // §6.5 — a stack event choosing ranks 2, 5 and 7 sends ONE note at rank 7's velocity (UP).
    func testDrumSamePitchHighestRank() {
        var l = drumLine(note: 42, low: 40, high: 100, ramp: .up)
        l.riffOn = false; l.notesOn = true; l.setLitOrder(.derived(litNotes: 0b0101_0010, top: false, top2: false))   // ranks 2, 5, 7
        l.notesGate = 0.3; l.notesVoicesChain = [EuclideousVoicesChip(value: .all)]   // VOICES ALL ⇒ all three in one hit
        let ons = run(state([l]), beats: 16).laneOns(0).filter { $0.note == 42 }
        XCTAssertFalse(ons.isEmpty)
        // rank 7 UP = euclideousDrumRampVel(7, 40,100) = 91
        XCTAssertTrue(ons.allSatisfy { $0.vel == 91 }, "the same-pitch collapse keeps the loudest chosen rank (7 ⇒ 91), not 2 or 5")
    }

    // §7.7 — turning KIT off returns the lane to its normal (held-MIDI) pool.
    func testKitOffRestoresSources() {
        let kit: [UInt8] = [36, 38, 42, 46, 49, 51, 37, 39]
        var off = riffLine(kitNotes: kit); off.kitOn = false   // kit stored but off
        let notes = run(state([off]), beats: 8).laneNotes(0)
        XCTAssertFalse(notes.isEmpty)
        XCTAssertTrue(notes.contains { pool.contains(UInt8($0)) }, "KIT off ⇒ the lane plays its held-MIDI pool again")
        XCTAssertFalse(notes.contains(36), "the kit notes do not sound when KIT is off (36 ∉ the held chord)")
    }
}
