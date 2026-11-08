//  EmitterCCTests.swift — CC tab (ratified Nov 2026): the per-output CC emitters.
//
//  The pure value math (FIXED / RIFF, the LOW…HIGH map including the inverted LOW > HIGH case, the per-emitter default CC numbers, decode tolerance) and the engine end to end: a CC fires on each hit with the right value, FIXED holds a
//  level, RIFF tracks the riff rank at the hit (even with PLAY RIFF off), STEP holds between hits, a muted output sends `muteValue` once, and CC off emits nothing (byte-identical, covered by the golden harness).

import XCTest

private final class CCEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let cc: UInt8; let value: UInt8 }
    private(set) var cc: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if b0 & 0xF0 == 0xB0 { cc.append(Ev(sample: sampleTime, cable: cable, cc: b1, value: b2)) }
    }
    func values(cable: UInt8, cc n: UInt8) -> [UInt8] { cc.filter { $0.cable == cable && $0.cc == n }.map { $0.value } }
}
private final class CCRig {
    let router = Router(); var diag = KernelDiag(); let out = CCEmitter(); let pool = NotePool()
    var box: SnapshotBox
    var ts = 0.0
    let frames: UInt32 = 480
    init(_ st: PluginState) { box = SnapshotBuilder.build(from: st) }
    var beat: Double { ts * 120.0 / 60.0 / 48_000.0 }
    func run(to target: Double) {
        while beat < target - 1e-9 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, forceColumn: 0, out: out, diag: &diag)
            ts += Double(frames)
        }
    }
}

final class EmitterCCTests: XCTestCase {
    // MARK: the pure value math
    func testRiffAndFixedValues() {
        var cfg = EmitterCCCfg(EmitterCC(valueMode: .riff, high: 127, low: 0))
        XCTAssertEqual(cfg.riffValue(rank: 1), 0, "rank 1 → LOW")
        XCTAssertEqual(cfg.riffValue(rank: 8), 127, "rank 8 → HIGH")
        XCTAssertEqual(cfg.riffValue(rank: 4), Int((3.0 / 7.0 * 127).rounded()), "rank 4 maps linearly")
        // LOW above HIGH inverts (never clamped or swapped)
        cfg = EmitterCCCfg(EmitterCC(valueMode: .riff, high: 0, low: 127))
        XCTAssertEqual(cfg.riffValue(rank: 1), 127, "inverted: rank 1 → LOW (127)")
        XCTAssertEqual(cfg.riffValue(rank: 8), 0, "inverted: rank 8 → HIGH (0)")
        // a narrow window
        cfg = EmitterCCCfg(EmitterCC(valueMode: .riff, high: 70, low: 60))
        XCTAssertEqual(cfg.riffValue(rank: 1), 60); XCTAssertEqual(cfg.riffValue(rank: 8), 70)
        XCTAssertEqual(EmitterCCCfg(EmitterCC(valueMode: .fixed, level: 90)).fixedValue, 90)
    }
    func testDefaultsAndDecodeTolerance() {
        let set = EmitterCCSet()
        XCTAssertEqual([set[0].ccNumber, set[1].ccNumber, set[2].ccNumber, set[3].ccNumber], [74, 71, 1, 11], "per-emitter default CC numbers A74 B71 C1 D11")
        for i in 0..<4 { XCTAssertFalse(set[i].on, "default off"); XCTAssertEqual(set[i].valueMode, .riff); XCTAssertEqual(set[i].travel, .step); XCTAssertEqual(set[i].time, 50) }
        XCTAssertTrue(set.isAllDefault)
        // clamps: ccNumber ≤ 119, time 1…100, values 0…127
        let c = EmitterCC(on: true, ccNumber: 127, level: 300, high: -5, low: 200, travel: .fall, time: 0, muteValue: 999).normalized()
        XCTAssertEqual(c.ccNumber, 119); XCTAssertEqual(c.level, 127); XCTAssertEqual(c.high, 0); XCTAssertEqual(c.low, 127); XCTAssertEqual(c.time, 1); XCTAssertEqual(c.muteValue, 127)
        // round-trips through Codable
        var s = EmitterCCSet(); s[0] = EmitterCC(on: true, ccNumber: 20, valueMode: .fixed, level: 64, travel: .glide, time: 75)
        let data = try! JSONEncoder().encode(s)
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCCSet.self, from: data), s)
    }

    // MARK: the engine
    /// A lane routing to output A with a CC emitter A: FIXED STEP sends `level` on every hit; RIFF tracks the rank (rank 1 → LOW, rank 8 → HIGH). A muted output sends `muteValue` once. CC off sends nothing.
    private func state(cc: EmitterCC, riffRanks: [Int] = [1, 1, 1, 1, 1, 1, 1, 1], muteA: Bool = false, playRiffOff: Bool = false) -> PluginState {
        var m = Machine(machineID: "gold", type: .euclid)
        m.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: riffRanks)
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)   // a hit on every step
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = !playRiffOff; l.sourceMode = .key
        m.paramsA.euclidLines = [l] + (1..<4).map { _ in EuclidLine(enabled: false) }
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? m : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousKeyRoot = 0; st.euclideousKeyType = .naturalMinor
        var set = EmitterCCSet(); set[0] = cc; st.euclideousEmitterCCs = set
        if muteA { var mutes = EuclideousOutputMutes(); mutes[0] = EuclideousOutputMute(cells16: 0, passes: 1); st.euclideousOutputMutes = mutes }   // output A fully muted (all 16 cells cleared)
        return st
    }
    func testFixedSendsTheLevelAndHolds() {
        let rig = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 90, travel: .step)))
        rig.run(to: 6.0)
        let vals = rig.out.values(cable: 1, cc: 74)   // cable 1 = output A
        XCTAssertEqual(vals, [90], "FIXED STEP sends the level once and holds (only on-change messages)")
        XCTAssertEqual(rig.out.values(cable: 0, cc: 74), vals, "mirrored on ALL (cable 0)")
    }
    func testRiffTracksTheRankEvenWithPlayRiffOff() {
        // ranks 1 and 8 alternate → the CC alternates LOW (0) and HIGH (127); PLAY RIFF off, so the notes are silent but the CC carries the riff.
        let rig = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: .step), riffRanks: [1, 8, 1, 8, 1, 8, 1, 8], playRiffOff: true))
        rig.run(to: 8.0)
        let vals = Set(rig.out.values(cable: 1, cc: 74))
        XCTAssertTrue(vals.contains(0) && vals.contains(127), "RIFF maps rank 1→0 and rank 8→127 even with PLAY RIFF off: \(vals)")
        XCTAssertTrue(vals.allSatisfy { $0 == 0 || $0 == 127 }, "STEP holds, so only the two hit values appear: \(vals)")
    }
    func testAMutedOutputSendsTheMuteValueOnce() {
        let rig = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 90, travel: .step, muteValue: 7), muteA: true))
        rig.run(to: 6.0)
        let vals = rig.out.values(cable: 1, cc: 74)
        XCTAssertEqual(vals, [7], "a muted output sends muteValue exactly once, then nothing")
    }
    func testCCOffSendsNothing() {
        let rig = CCRig(state(cc: EmitterCC(on: false, ccNumber: 74)))
        rig.run(to: 6.0)
        XCTAssertTrue(rig.out.cc.isEmpty, "an off emitter sends no CC")
    }
}
