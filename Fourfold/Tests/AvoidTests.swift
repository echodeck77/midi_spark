//  AvoidTests.swift — (2026-11-06) investigation "blue plays 16 of 16, red (3 of 8) AVOIDs blue: shouldn't red be silent?" Through the real Router: yes when every red hit coincides with a blue hit, and AVOID's result is exactly the control minus the coincident hits.
//  AVOID is a TIME hole punch (same onset, within 1e-6 beat), so a red hit that falls BETWEEN blue's hits (TILT, a triplet or dotted rate against a straight one, a slower blue) is not punched — by design.

import XCTest

final class AvoidTests: XCTestCase {
    private func line(hits: Int, steps: Int, rate: ArpRate) -> EuclidLine {
        EuclidLine(target: 0, pulses: hits, steps: steps, velocityAbsolute: 100, rate: rate, useRiff: true, riffOn: true, sourceMode: .midi)
    }
    /// Red = lane 0 (AVOIDs lane 1 when `avoid`), blue = lane 1. Returns [lane: strike onset beats].
    private func run(red: EuclidLine, blue: EuclidLine, avoid: Bool, beats: Double = 16, frames fr: UInt32 = 480, tempo bpm: Double = 120, start: Double = 0, tweak: ((inout PluginState) -> Void)? = nil) -> [Int: [Double]] {
        var r = red, b = blue
        if avoid { r.setAnswerPitch(.avoid); r.listenSource = 1 }
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
    /// By design AVOID punches a hole only where the source strikes at the SAME instant: a red hit between blue's hits still plays.
    func testARedHitBetweenBluesHitsStillPlays() {
        let blue = line(hits: 16, steps: 16, rate: .r1_16)
        var tilted = line(hits: 3, steps: 8, rate: .r1_8); tilted.tilt = 0.3; tilted.tiltFine = 0.3     // TILT moves red's hits off the grid
        XCTAssertGreaterThan(run(red: tilted, blue: blue, avoid: true)[0]?.count ?? 0, 0, "red TILT 30 % AVOIDing a straight blue still plays: its hits fall between blue's")
        XCTAssertGreaterThan(run(red: line(hits: 3, steps: 8, rate: .r1_8t), blue: blue, avoid: true)[0]?.count ?? 0, 0, "a triplet red against a straight blue: most of its hits fall between blue's")
        XCTAssertGreaterThan(run(red: line(hits: 3, steps: 8, rate: .r1_8), blue: line(hits: 16, steps: 16, rate: .r1_4), avoid: true)[0]?.count ?? 0, 0, "a slower blue (1/4) leaves red's hits at 1.5, 4.5 … unpunched")
    }

    private struct Rng { var s: UInt64; mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func pick<T>(_ a: [T]) -> T { a[Int(next() % UInt64(a.count))] } }
    /// The same invariant from beat 0 with direction, rotate and step counts varied on BOTH lanes — the settings a player would plausibly have touched.
    func testAvoidIsExactlyTheControlMinusTheCoincidentHitsWithDirectionRotateAndRatesVaried() {
        var rng = Rng(s: 777)
        let rates: [ArpRate] = [.r1_4, .r1_8, .r1_16, .r1_32, .r1_8d, .r1_16d, .r1_8t, .r1_16t]
        let dirs: [EuclidDir] = [.fwd, .bkw, .pingpong]
        var bad: [String] = [], trials = 0
        for _ in 0..<30 {
            var red = line(hits: 1 + Int(rng.next() % 8), steps: 8, rate: rng.pick(rates)), blue = line(hits: 16, steps: 16, rate: rng.pick(rates))
            red.direction = rng.pick(dirs); blue.direction = rng.pick(dirs); red.rotate = Int(rng.next() % 8); blue.rotate = Int(rng.next() % 16)
            let frames = rng.pick([64, 480, 1024, 2048]) as Int, tempo = rng.pick([93.9, 120.0, 137.31])
            let ctl = run(red: red, blue: blue, avoid: false, beats: 8, frames: UInt32(frames), tempo: tempo)
            let av = run(red: red, blue: blue, avoid: true, beats: 8, frames: UInt32(frames), tempo: tempo)
            let expected = (ctl[0] ?? []).filter { r in !(ctl[1] ?? []).contains { abs($0 - r) < 2e-4 } }, got = av[0] ?? []
            trials += 1
            if got.count != expected.count || zip(got, expected).contains(where: { abs($0 - $1) > 2e-4 }) {
                bad.append("red \(red.pulses)/8 \(red.rate?.rawValue ?? "-") \(red.direction.map { "\($0)" } ?? "-") rot \(red.rotate) · blue \(blue.rate?.rawValue ?? "-") \(blue.direction.map { "\($0)" } ?? "-") rot \(blue.rotate) frames \(frames): expected \(expected.count) got \(got.count)")
            }
        }
                XCTAssertEqual(bad.count, 0)
    }
}
