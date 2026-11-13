//  FillRouterTests.swift — FILL ferry (2026-11-13), slice 3: the Router emission. An armed bar plays the lane's last
//  LENGTH at SPEED m, CONTINUING THE WALK FORWARD (Paul 2026-11-13), then rejoins ×1; REVERSE mirrors the fired order;
//  BREAK silences the last quarter. A neutral / unlit lane is byte-identical to the same lane with no fill. (RANKS/SWELL
//  are slice 3b.) Adapted from the retired RateRouterTests harness.

import XCTest

private final class FillEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8; let vel: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1, vel: b2)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 && $0.vel > 0 } }
}

struct FillSpec { var bars: [Bool]; var speed: UInt8 = 3; var length: UInt8 = 1; var reverse = false; var ranks: Int8 = 0; var swell: Int8 = 0; var brk = false }

final class FillRouterTests: XCTestCase {
    // 120 BPM at 48 kHz: 1 beat = 24000 samples. One strike opens an own-cable (1) voice AND an ALL (0) voice — count cable 1.
    private func onBeats(_ e: FillEmitter) -> [Double] { e.ons.filter { $0.cable == 1 }.map { ((Double($0.sample) / 24_000.0) * 1000).rounded() / 1000 }.sorted() }
    private func onPairs(_ e: FillEmitter) -> [(beat: Double, note: UInt8)] {
        e.ons.filter { $0.cable == 1 }.map { (((Double($0.sample) / 24_000.0) * 1000).rounded() / 1000, $0.note) }.sorted { $0.0 < $1.0 }
    }
    private func perBar(_ beats: [Double]) -> [Int: Int] { Dictionary(grouping: beats, by: { Int(($0 + 1e-3) / 4.0) }).mapValues { $0.count } }

    /// An 8-step 1/8 lane, every step a hit, a `ranks`-pattern riff over `pool` held notes. `fill` sets the fill fields.
    private func run(fill: FillSpec?, riffRanks: [Int] = [1, 1, 1, 1, 1, 1, 1, 1], pool poolNotes: [UInt8] = [60], beats: Double = 32) -> FillEmitter {
        var l = EuclidLine(target: 0, pulses: 8, steps: 8, useRiff: true, riffOn: true, sourceMode: .midi)
        l.rate = .r1_8; l.gate = 0.5; l.velocityAbsolute = 90; l.litNotes = 0; l.notesOn = false
        if let f = fill { l.fillBars = f.bars; l.fillSpeed = f.speed; l.fillLength = f.length; l.fillReverse = f.reverse; l.fillRanks = f.ranks; l.fillSwell = f.swell; l.fillBreak = f.brk }
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: riffRanks)
        c.paramsA.euclidLines = [l] + (1..<4).map { _ in EuclidLine(enabled: false) }
        var sc = SceneState.empty(); sc.stepRate = .r1_8; sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        let box = SnapshotBuilder.build(from: st)
        let e = FillEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0, frames: UInt32 = 2048
        let pool = NotePool(); for n in poolNotes { pool.noteOn(n, velocity: 100, channel: 0) }
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: pool, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }

    private func bar(_ n: Int) -> [Bool] { (0..<8).map { $0 == n } }

    // MARK: neutrality (§1.4/§1.5, §9) — byte-identical to no fill

    func testNeutralIsEightHitsABar() {
        let bars = perBar(onBeats(run(fill: nil)))
        for b in 0..<8 { XCTAssertEqual(bars[b], 8, "bar \(b): 8 hits at ×1") }
    }
    func testUnlitAndX1AreByteIdenticalToNoFill() {
        let plain = run(fill: nil).events
        XCTAssertEqual(run(fill: FillSpec(bars: [Bool](repeating: false, count: 8), speed: 4)).events, plain, "no bar lit ⇒ identical")
        XCTAssertEqual(run(fill: FillSpec(bars: bar(3), speed: 1, length: 0)).events, plain, "×1 (neutral), bar lit ⇒ identical whatever LENGTH")
    }

    // MARK: §2.2/§2.3 forward timing (test 2 / test 3)

    func testBarLitX2BARisSixteenHitsThatBarOnly() {
        let plain = onBeats(run(fill: nil))
        let over = onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 0)))   // ×2, BAR
        let bars = perBar(over)
        XCTAssertEqual(bars[3], 16, "the ×2 BAR fill doubles to 16 note-ons")
        for b in [0, 1, 2, 4, 5, 6, 7] { XCTAssertEqual(bars[b], 8, "bar \(b): unchanged") }
        let inBar3 = over.filter { $0 >= 12 - 1e-6 && $0 < 16 - 1e-6 }
        XCTAssertEqual(inBar3.count, 16)
        for i in 1..<inBar3.count { XCTAssertEqual(inBar3[i] - inBar3[i - 1], 0.25, accuracy: 1e-4) }
        XCTAssertEqual(plain.filter { $0 < 12 - 1e-6 }, over.filter { $0 < 12 - 1e-6 }, "bars 0–2 identical")
        XCTAssertEqual(plain.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, over.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, "bar 4 on identical (rejoin)")
    }

    func testHalfX2IsFourThenEightInThatBar() {
        // LENGTH ½, ×2: bar 3's first half ×1 (4 hits, beats 12–14), second half fill (8 hits 0.25 apart from beat 14).
        let over = onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 1)))
        let firstHalf = over.filter { $0 >= 12 - 1e-6 && $0 < 14 - 1e-6 }
        let fill = over.filter { $0 >= 14 - 1e-6 && $0 < 16 - 1e-6 }
        XCTAssertEqual(firstHalf.count, 4, "first half unchanged ×1")
        XCTAssertEqual(fill.count, 8, "second half fills at ×2")
        for i in 1..<fill.count { XCTAssertEqual(fill[i] - fill[i - 1], 0.25, accuracy: 1e-4) }
    }

    // MARK: §2.3 forward / reverse step VALUES (test 3 / test 4) — a ranked riff over 8 distinct pool notes

    private let cmaj: [UInt8] = [60, 62, 64, 65, 67, 69, 71, 72]   // ascending; rank r → cmaj[r-1]
    private func fillNotes(_ e: FillEmitter) -> [UInt8] { onPairs(e).filter { $0.beat >= 14 - 1e-6 && $0.beat < 16 - 1e-6 }.map { $0.note } }

    // The lane plays its riff an octave below the raw pool note (the lane's default octave) — so rank r sounds cmaj[r-1] − 12.
    // What these tests PROVE is the step ORDER: forward continues the walk (5,6,7,8,1,2,3,4), NOT a loop (which would be
    // 5,6,7,8,5,6,7,8 ⇒ notes …,55,57,59,60); reverse is the exact time-mirror of the forward list.
    func testForwardStepValuesContinueTheWalk() {
        // ×2 ½ on an 8-rank riff ⇒ steps 5,6,7,8,1,2,3,4 (Paul's decision: continue, not loop).
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        XCTAssertEqual(fillNotes(e), [55, 57, 59, 60, 48, 50, 52, 53], "steps 5,6,7,8,1,2,3,4 — the walk runs on, it does not loop")
    }
    func testReverseMirrorsTheForwardList() {
        // REVERSE ⇒ the forward list mirrored (steps 4,3,2,1,8,7,6,5).
        let e = run(fill: FillSpec(bars: bar(3), speed: 3, length: 1, reverse: true), riffRanks: [1, 2, 3, 4, 5, 6, 7, 8], pool: cmaj)
        XCTAssertEqual(fillNotes(e), [53, 52, 50, 48, 60, 59, 57, 55], "the exact time-mirror of the forward list")
    }

    // MARK: §2.7 BREAK (test 7)

    func testBreakDropsTheLastQuarter() {
        // ×2 BAR + BREAK: no note-ons in [15,16) (the last beat); the rest of the bar still fills.
        let over = onBeats(run(fill: FillSpec(bars: bar(3), speed: 3, length: 0, brk: true)))
        XCTAssertTrue(over.filter { $0 >= 15 - 1e-6 && $0 < 16 - 1e-6 }.isEmpty, "the last quarter is silent")
        XCTAssertFalse(over.filter { $0 >= 12 - 1e-6 && $0 < 15 - 1e-6 }.isEmpty, "the rest of the bar still fills")
    }

    // MARK: §2.8 rejoin (test 8) — the bar after a region matches no fill

    func testRejoinMatchesNoFill() {
        for (speed, length) in [(UInt8(3), UInt8(0)), (3, 1), (4, 2), (1, 1)] {
            let plain = onBeats(run(fill: nil))
            let over = onBeats(run(fill: FillSpec(bars: bar(3), speed: speed, length: length)))
            XCTAssertEqual(plain.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, over.filter { $0 >= 16 - 1e-6 && $0 < 31.9 }, "speed \(speed) length \(length): bar 5 on identical")
        }
    }
}
