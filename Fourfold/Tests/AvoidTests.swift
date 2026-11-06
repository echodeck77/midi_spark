//  AvoidTests.swift — LISTEN AVOID is STEP-based (2026-11-06, Paul): a lane that avoids a source is silent whenever the source's current STEP holds a hit — "if blue plays 16 of 16, red is silent" — whatever the two lanes' rates, TILT or ratchets.
//  (The first rule, "the source strikes at exactly the same instant", let a red hit that fell between blue's steps, or beside blue's ratchet repeat, through: the clip that prompted this change.) Pitch and octave never matter.
//  Through the real Router: red = lane 0 AVOIDing blue = lane 1; "control" = the same document with AVOID off.

import XCTest

final class AvoidTests: XCTestCase {
    private func line(hits: Int, steps: Int, rate: ArpRate) -> EuclidLine {
        EuclidLine(target: 0, pulses: hits, steps: steps, velocityAbsolute: 100, rate: rate, useRiff: true, riffOn: true, sourceMode: .midi)
    }
    /// Red = lane 0 (AVOIDs lane 1 when `avoid`), blue = lane 1. Returns [lane: strike onset beats].
    private func run(red: EuclidLine, blue: EuclidLine, avoid: Bool, beats: Double = 16, frames fr: UInt32 = 480, tempo bpm: Double = 120, start: Double = 0, tweak: ((inout PluginState) -> Void)? = nil) -> [Int: [Double]] {
        var r = red, b = blue
        if avoid { r.setAnswerRhythm(.avoid); r.listenSource = 1 }   // ANSWER v2 (2026-11-06): AVOID is a RHYTHM mode now (same step-based behaviour)
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [r, b, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        tweak?(&st)
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag()
        final class Null: MIDIEmitter { func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {} }
        let e = Null()
        let pool = NotePool(); for n in [UInt8]([48, 50, 52, 53, 55, 57, 59, 60]) { pool.noteOn(n, velocity: 100, channel: 0) }
        let tempo = bpm, sr = 48_000.0, frames: UInt32 = fr
        var ts = 0.0, out: [NoteRollRecord] = []
        func beatNow() -> Double { start + ts * tempo / 60.0 / sr }
        while beatNow() < start + beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            out += router.rollRing.drain()
            ts += Double(frames)
        }
        var by: [Int: [Double]] = [:]
        for rec in out where !rec.isEnd { by[Int(rec.part) / 2, default: []].append(rec.onBeat) }
        return by.mapValues { Array(Set($0)).sorted() }
    }

    /// The reported case: blue 16 of 16, red 3 of 8 AVOIDing blue — red is completely silent while every red hit lands on a blue hit (any pairing where red's grid is a subset of blue's), and plays without AVOID.
    func testRedIsSilentWhenEveryRedHitLandsOnABlueHit() {
        for (rr, br) in [(ArpRate.r1_8, ArpRate.r1_16), (.r1_8, .r1_8), (.r1_4, .r1_16), (.r1_16, .r1_16), (.r1_8, .r1_32), (.r1_8d, .r1_16)] {
            let red = line(hits: 3, steps: 8, rate: rr), blue = line(hits: 16, steps: 16, rate: br)
            let ctl = run(red: red, blue: blue, avoid: false), av = run(red: red, blue: blue, avoid: true)
            XCTAssertGreaterThan(ctl[0]?.count ?? 0, 0, "red plays without AVOID (\(rr.rawValue) vs \(br.rawValue))")
            XCTAssertEqual(av[0]?.count ?? 0, 0, "red \(rr.rawValue) AVOIDing blue \(br.rawValue) 16/16 is silent")
            XCTAssertEqual(av[1], ctl[1], "blue is untouched")
        }
    }
    /// Blue plays every step (16 of 16): red is silent whatever its rate, TILT or offset — a triplet red against a straight blue, a dotted one, a blue SLOWER than red, a TILT that moves red's hits between blue's steps. (Under the first rule all of these played.)
    func testRedIsSilentWhenBlueIsPlayingEveryStepWhateverTheRatesAndTimings() {
        let blue = line(hits: 16, steps: 16, rate: .r1_16)
        var tilted = line(hits: 3, steps: 8, rate: .r1_8); tilted.tilt = 0.3; tilted.tiltFine = 0.3
        var offset = line(hits: 3, steps: 8, rate: .r1_8); offset.offsetFraction = 0.3
        for (name, red, b) in [("TILT 30 %", tilted, blue), ("OFFSET +0.3 step", offset, blue), ("1/8T red vs 1/16 blue", line(hits: 3, steps: 8, rate: .r1_8t), blue),
                               ("1/16T red vs 1/16 blue", line(hits: 3, steps: 8, rate: .r1_16t), blue), ("1/8 red vs slower 1/4 blue", line(hits: 3, steps: 8, rate: .r1_8), line(hits: 16, steps: 16, rate: .r1_4)),
                               ("1/8 red vs 1/8D blue", line(hits: 3, steps: 8, rate: .r1_8), line(hits: 16, steps: 16, rate: .r1_8d))] {
            XCTAssertGreaterThan(run(red: red, blue: b, avoid: false)[0]?.count ?? 0, 0, "\(name): red plays without AVOID")
            XCTAssertEqual(run(red: red, blue: b, avoid: true)[0]?.count ?? 0, 0, "\(name): red is silent while blue plays every step")
        }
    }
    /// The reported clip: blue 1/8T 16/16 with FX RATCH ×2 on riff columns 1 and 5, red 1/8 3/8 at riff OCT −2 AVOIDing blue — red's hit at beat 1.5 sits between blue's triplets (and beside blue's ratchet repeat at exactly 1.5): it used to survive, now red is silent.
    func testTheReportedClipRedIsSilentNow() {
        var fx = EuclideousFX(); fx.cells[0 * 8 + 0] = 2; fx.cells[0 * 8 + 4] = 2
        var red = line(hits: 3, steps: 8, rate: .r1_8); red.riffOctave = -2
        var blue = line(hits: 16, steps: 16, rate: .r1_8t); blue.riffOctave = 1
        XCTAssertGreaterThan(run(red: red, blue: blue, avoid: false, beats: 14, tempo: 94, tweak: { $0.euclideousFX = fx })[0]?.count ?? 0, 0)
        XCTAssertEqual(run(red: red, blue: blue, avoid: true, beats: 14, tempo: 94, tweak: { $0.euclideousFX = fx })[0]?.count ?? 0, 0, "red avoids a 16-of-16 blue completely, ratchets included")
    }
    /// A transport that starts or seeks at an off-grid beat strikes each lane's step at once; the first rule missed that red strike (different tick beats), the step rule cannot.
    func testRedIsSilentFromAnOffGridStartToo() {
        for start in [0.1234, 7.77, 33.0, 7.5] {
            for (rr, br) in [(ArpRate.r1_4t, ArpRate.r1_4), (.r1_8t, .r1_8t), (.r1_32, .r1_8d), (.r1_8, .r1_16)] {
                XCTAssertEqual(run(red: line(hits: 3, steps: 8, rate: rr), blue: line(hits: 16, steps: 16, rate: br), avoid: true, beats: 6, start: start)[0]?.count ?? 0, 0, "start \(start), red \(rr.rawValue) vs blue \(br.rawValue)")
            }
        }
    }

    private struct Rng { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] } }
    /// AVOID's result is EXACTLY red's control strikes minus those whose strike time lies inside a step where blue has a hit (a blue strike at the step's start, no TILT on blue) — blue's partial patterns too (5 of 16 …), direction, rotate and rates varied on both lanes.
    func testAvoidIsExactlyTheControlMinusTheHitsInsideTheSourcesHitStepsWithDirectionRotateAndRatesVaried() {
        var rng = Rng(s: 777)
        let rates: [ArpRate] = [.r1_4, .r1_8, .r1_16, .r1_32, .r1_8d, .r1_16d, .r1_8t, .r1_16t]
        let dirs: [EuclidDir] = [.fwd, .bkw, .pingpong]
        var bad: [String] = [], trials = 0
        for _ in 0..<30 {
            var red = line(hits: 1 + Int(rng.next() % 8), steps: 8, rate: rng.pick(rates)), blue = line(hits: 1 + Int(rng.next() % 16), steps: 16, rate: rng.pick(rates))
            red.direction = rng.pick(dirs); blue.direction = rng.pick(dirs); red.rotate = Int(rng.next() % 8); blue.rotate = Int(rng.next() % 16)
            let frames = rng.pick([64, 480, 1024, 2048]) as Int, tempo = rng.pick([93.9, 120.0, 137.31])
            let ctl = run(red: red, blue: blue, avoid: false, beats: 8, frames: UInt32(frames), tempo: tempo)
            let av = run(red: red, blue: blue, avoid: true, beats: 8, frames: UInt32(frames), tempo: tempo)
            let bs = blue.rate?.beats ?? 0.5
            let expected = (ctl[0] ?? []).filter { r in !(ctl[1] ?? []).contains { r >= $0 - 2e-4 && r < $0 + bs - 2e-4 } }, got = av[0] ?? []
            trials += 1
            if got.count != expected.count || zip(got, expected).contains(where: { abs($0 - $1) > 2e-4 }) {
                bad.append("red \(red.pulses)/8 \(red.rate?.rawValue ?? "-") \(red.direction.map { "\($0)" } ?? "-") rot \(red.rotate) · blue \(blue.rate?.rawValue ?? "-") \(blue.direction.map { "\($0)" } ?? "-") rot \(blue.rotate) frames \(frames): expected \(expected.count) got \(got.count)")
            }
        }
                XCTAssertEqual(bad.count, 0)
    }

    // MARK: ANSWER v2 (2026-11-06) — AVOID / MEET as RHYTHM modes

    /// Red = lane 0 with a RHYTHM mode (AVOID or MEET) following blue = lane 1. Same harness as `run`, but the mode is set on the RHYTHM row.
    private func runRhythm(red: EuclidLine, blue: EuclidLine, mode: EuclideousAnswerRhythmMode, beats: Double = 16, frames fr: UInt32 = 480, tempo bpm: Double = 120) -> [Int: [Double]] {
        var r = red; r.setAnswerRhythm(mode == .meet ? .meet : .avoid); r.listenSource = 1
        return runPrepared(red: r, blue: blue, beats: beats, frames: fr, tempo: bpm)
    }
    /// The body of `run` after the mode is set (so a rhythm-mode red can reuse it). Returns [lane: strike onset beats].
    private func runPrepared(red r: EuclidLine, blue b: EuclidLine, beats: Double, frames fr: UInt32, tempo bpm: Double) -> [Int: [Double]] {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        c.paramsA.euclidLines = [r, b, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag()
        final class Null: MIDIEmitter { func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {} }
        let e = Null(); let pool = NotePool(); for n in [UInt8]([48, 50, 52, 53, 55, 57, 59, 60]) { pool.noteOn(n, velocity: 100, channel: 0) }
        let sr = 48_000.0; var ts = 0.0, out: [NoteRollRecord] = []
        while (ts * bpm / 60.0 / sr) < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: ts * bpm / 60.0 / sr, tempo: bpm, sampleRate: sr, timestampSample: ts, frameCount: fr, forceColumn: 0, out: e, diag: &diag)
            out += router.rollRing.drain(); ts += Double(fr)
        }
        var by: [Int: [Double]] = [:]
        for rec in out where !rec.isEnd { by[Int(rec.part) / 2, default: []].append(rec.onBeat) }
        return by.mapValues { Array(Set($0)).sorted() }
    }

    /// §10.2 spirit: against a blue that plays every step (16/16), AVOID silences red completely while MEET plays red exactly as its control (every red hit shares a blue step); against a blue that plays nothing, MEET silences red and AVOID plays it all.
    func testMeetAndAvoidAgainstAFullAndAnEmptyBlue() {
        let red = line(hits: 5, steps: 16, rate: .r1_16)
        let full = line(hits: 16, steps: 16, rate: .r1_16), empty = line(hits: 0, steps: 16, rate: .r1_16)
        let ctl = runPrepared(red: { var r = red; return r }(), blue: full, beats: 8, frames: 480, tempo: 120)
        XCTAssertEqual(runRhythm(red: red, blue: full, mode: .avoid, beats: 8)[0]?.count ?? 0, 0, "AVOID: red silent under a full blue")
        XCTAssertEqual(runRhythm(red: red, blue: full, mode: .meet, beats: 8)[0] ?? [], ctl[0] ?? [], "MEET: red plays every hit (all shared) under a full blue")
        XCTAssertGreaterThan(runRhythm(red: red, blue: empty, mode: .avoid, beats: 8)[0]?.count ?? 0, 0, "AVOID: red plays fully under an empty blue")
        XCTAssertEqual(runRhythm(red: red, blue: empty, mode: .meet, beats: 8)[0]?.count ?? 0, 0, "MEET: red silent under an empty blue (no shared hits)")
    }
    /// Red = lane 0 with a PITCH mode (SHADOW or MIRROR) following blue = lane 1. Returns [lane: the set of pitches it played].
    private func runPitch(red: EuclidLine, blue: EuclidLine, pitch: EuclideousListenPitchMode, riff: [Int] = [1, 2, 3, 4, 5, 6, 7, 8], beats: Double = 16) -> [Int: Set<Int>] {
        var r = red; r.setAnswerPitch(pitch); r.listenSource = 1
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: riff)
        c.paramsA.euclidLines = [r, blue, EuclidLine(enabled: false), EuclidLine(enabled: false)]
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(midiOctaves: .keep)
        let box = SnapshotBuilder.build(from: st)
        let router = Router(); var diag = KernelDiag()
        final class Null: MIDIEmitter { func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {} }
        let e = Null(); let pool = NotePool(); for n in [UInt8]([48, 50, 52, 53, 55, 57, 59, 60]) { pool.noteOn(n, velocity: 100, channel: 0) }
        let sr = 48_000.0; var ts = 0.0, out: [NoteRollRecord] = []
        while (ts * 120.0 / 60.0 / sr) < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: ts * 120.0 / 60.0 / sr, tempo: 120, sampleRate: sr, timestampSample: ts, frameCount: 480, forceColumn: 0, out: e, diag: &diag)
            out += router.rollRing.drain(); ts += Double(480)
        }
        var by: [Int: Set<Int>] = [:]
        for rec in out where !rec.isEnd { by[Int(rec.part) / 2, default: []].insert(Int(rec.pitch)) }
        return by
    }
    /// §6.2 / §11: PITCH MIRROR flips the source's rank in the shared pool. Blue plays the lowest pool note (48); red MIRROR plays the highest (60) — a rising source falls. SHADOW (the control) plays the source's note itself (48).
    func testMirrorFlipsTheSourcesRankInThePool() {
        // a FLAT riff (every column rank 1) so blue plays a constant note (the lowest, pool[0] = 48) whatever its walk does; red MIRROR flips it to the highest (pool[7] = 60).
        let flat: [Int] = [1, 1, 1, 1, 1, 1, 1, 1]
        let blue = line(hits: 8, steps: 8, rate: .r1_8), red = line(hits: 4, steps: 8, rate: .r1_8)
        XCTAssertEqual(runPitch(red: red, blue: blue, pitch: .mirror, riff: flat)[1] ?? [], [48], "blue plays rank 1 = 48 throughout")
        XCTAssertEqual(runPitch(red: red, blue: blue, pitch: .mirror, riff: flat)[0] ?? [], [60], "MIRROR of the lowest pool note (48) is the highest (60)")
        XCTAssertEqual(runPitch(red: red, blue: blue, pitch: .shadow, riff: flat)[0] ?? [], [48], "SHADOW plays the source's own note")
    }
    /// §10.3 partition (Router level): over Euclidean pairs at the same rate, MEET's strikes and AVOID's strikes are DISJOINT and together equal the control (both rows off) — each red hit goes to exactly one of them.
    func testMeetAndAvoidPartitionTheControlStrikes() {
        for (rh, bh) in [(5, 8), (3, 11), (7, 13), (9, 16), (2, 5)] {
            let red = line(hits: rh, steps: 16, rate: .r1_16), blue = line(hits: bh, steps: 16, rate: .r1_16)
            let ctl = Set((runPrepared(red: red, blue: blue, beats: 8, frames: 480, tempo: 120)[0] ?? []).map { Int(($0 * 1e4).rounded()) })
            let meet = Set((runRhythm(red: red, blue: blue, mode: .meet, beats: 8)[0] ?? []).map { Int(($0 * 1e4).rounded()) })
            let avoid = Set((runRhythm(red: red, blue: blue, mode: .avoid, beats: 8)[0] ?? []).map { Int(($0 * 1e4).rounded()) })
            XCTAssertTrue(meet.isDisjoint(with: avoid), "red \(rh)/16 vs blue \(bh)/16: MEET and AVOID are disjoint")
            XCTAssertEqual(meet.union(avoid), ctl, "red \(rh)/16 vs blue \(bh)/16: MEET ∪ AVOID = the control strikes")
            XCTAssertGreaterThan(ctl.count, 0)
        }
    }
}
