//  RateRouterTests.swift — RATE ferry (2026-11-12), slice 3: the Router emission. A box multiplies the lane's step rate for its
//  host bar and the lane rejoins its ×1 position after; every other bar is identical to the same lane with no override.

import XCTest

private final class RateEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
}

final class RateRouterTests: XCTestCase {
    // 120 BPM at 48 kHz: 1 beat = 24000 samples. One strike opens an own-cable (1) voice AND an ALL (0) voice — count cable 1 only.
    // The Router lands a note-on at the window-boundary sample, so a beat can read ~4e-5 early; round to the ms to compare.
    private func onBeats(_ e: RateEmitter) -> [Double] { e.ons.filter { $0.cable == 1 }.map { ((Double($0.sample) / 24_000.0) * 1000).rounded() / 1000 }.sorted() }
    private func perBar(_ beats: [Double]) -> [Int: Int] { Dictionary(grouping: beats, by: { Int(($0 + 1e-3) / 4.0) }).mapValues { $0.count } }

    /// An 8-step 1/8 lane, every step a hit, flat rank-1 riff over a single held note — 8 note-ons a bar at ×1. `bars` sets the strip.
    private func run(rateBars: [UInt8]?, beats: Double = 32) -> RateEmitter {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, useRiff: true, riffOn: true, sourceMode: .midi)
        l.rate = .r1_8; l.gate = 0.5; l.velocityAbsolute = 90; l.litNotes = 0; l.notesOn = false; l.rateBars = rateBars
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = [l] + (1..<4).map { _ in EuclidLine(enabled: false) }
        var sc = SceneState.empty(); sc.stepRate = .r1_8; sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        let box = SnapshotBuilder.build(from: st)
        let e = RateEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let pool = NotePool(); pool.noteOn(60, velocity: 100, channel: 0)
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }

    func testNoOverrideIsEightHitsABar() {
        let bars = perBar(onBeats(run(rateBars: nil)))
        for b in 0..<8 { XCTAssertEqual(bars[b], 8, "bar \(b): 8 hits at ×1") }
    }

    // §7.4 — box 4 (index 3) ×2, 4/4: that bar has 16 note-ons 0.25 beat apart; every other bar is identical to no override.
    func testBoxFourDoubleTimeIsSixteenHitsInThatBarOnly() {
        let plain = onBeats(run(rateBars: nil))
        let over = onBeats(run(rateBars: [0, 0, 0, 3, 0, 0, 0, 0]))
        let bars = perBar(over)
        XCTAssertEqual(bars[3], 16, "the ×2 bar doubles to 16 note-ons")
        for b in [0, 1, 2, 4, 5, 6, 7] { XCTAssertEqual(bars[b], 8, "bar \(b): unchanged at 8") }
        // 0.25 beat apart inside the ×2 bar
        let inBar3 = over.filter { $0 >= 12 - 1e-6 && $0 < 16 - 1e-6 }
        XCTAssertEqual(inBar3.count, 16)
        for i in 1..<inBar3.count { XCTAssertEqual(inBar3[i] - inBar3[i - 1], 0.25, accuracy: 1e-4, "0.25 beat apart") }
        // every other bar's note-on beats match no override exactly (the interior, away from the run-end sample boundary)
        XCTAssertEqual(plain.filter { $0 < 12 - 1e-6 }, over.filter { $0 < 12 - 1e-6 }, "bars 0–2 identical")
        XCTAssertEqual(plain.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, over.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, "bar 4 onward identical (clean rejoin)")
    }

    // §7.5 — box 8 (index 7) ×½: that bar has 4 note-ons 1 beat apart; the next bar is identical to no override.
    func testBoxEightHalfTimeIsFourHitsThenRejoins() {
        let plain = onBeats(run(rateBars: nil))
        let over = onBeats(run(rateBars: [0, 0, 0, 0, 0, 0, 0, 1]))
        let bars = perBar(over)
        XCTAssertEqual(bars[7], 4, "the ×½ bar halves to 4 note-ons")
        let inBar7 = over.filter { $0 >= 28 - 1e-6 && $0 < 32 - 1e-6 }
        XCTAssertEqual(inBar7.count, 4)
        for i in 1..<inBar7.count { XCTAssertEqual(inBar7[i] - inBar7[i - 1], 1.0, accuracy: 1e-4, "1 beat apart") }
        XCTAssertEqual(plain.filter { $0 < 28 - 1e-6 }, over.filter { $0 < 28 - 1e-6 }, "bars 0–6 identical")
    }

    // §7.6 — a two-box run (idx 3,4 ×2) over bars 3–4, then one rejoin at bar 5; from bar 5 on, identical to no override.
    func testTwoBarRunRejoinsAtBarFive() {
        let plain = onBeats(run(rateBars: nil))
        let over = onBeats(run(rateBars: [0, 0, 0, 3, 3, 0, 0, 0]))
        let bars = perBar(over)
        XCTAssertEqual(bars[3], 16); XCTAssertEqual(bars[4], 16, "both bars of the run double")
        XCTAssertEqual(plain.filter { $0 >= 20 - 1e-6 && $0 < 31.9 }, over.filter { $0 >= 20 - 1e-6 && $0 < 31.9 }, "bar 5 onward identical")
    }

    // §7.7 — box 4 ×1½ (code 2) on a 1/8 lane: 12 note-ons in that bar, 1/3 beat apart.
    func testBoxFourDottedIsTwelveHits() {
        let over = onBeats(run(rateBars: [0, 0, 0, 2, 0, 0, 0, 0]))
        let inBar3 = over.filter { $0 >= 12 - 1e-6 && $0 < 16 - 1e-6 }
        XCTAssertEqual(inBar3.count, 12, "×1½ gives 12 note-ons in the bar")
        for i in 1..<inBar3.count { XCTAssertEqual(inBar3[i] - inBar3[i - 1], 1.0 / 3.0, accuracy: 2e-3, "1/3 beat apart (ms-rounded)") }
    }
}
