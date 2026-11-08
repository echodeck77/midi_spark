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
    let frames: UInt32
    init(_ st: PluginState, frames: UInt32 = 480) { box = SnapshotBuilder.build(from: st); self.frames = frames }
    var beat: Double { ts * 120.0 / 60.0 / 48_000.0 }
    func run(to target: Double) {
        while beat < target - 1e-9 {
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, forceColumn: 0, out: out, diag: &diag)
            ts += Double(frames)
        }
    }
}

extension CCEmitter {
    /// (sample, value) of every CC `n` on `cable`, in the order sent.
    func timeline(cable: UInt8, cc n: UInt8) -> [(sample: Int64, value: Int)] { cc.filter { $0.cable == cable && $0.cc == n }.map { ($0.sample, Int($0.value)) } }
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

    // MARK: slice D (2026-11-08) — the gap and the predicted value are the NEXT HIT ON THE EMITTER, merged across the lanes routed to it; an emitter whose routed lanes are ALL stopped / muted is silent
    /// Two lanes both routed to output A (lane 2 moved off B). Lane 1 hits once a 4-beat pass at beat 0; lane 2 hits once a pass, two beats later (pattern + riff rotated by 2). Per-lane overrides via `lane1` / `lane2`.
    private func twoLaneState(cc: EmitterCC, ranks: [Int] = [1, 1, 1, 1, 1, 1, 1, 1], lane1: (inout EuclidLine) -> Void = { _ in }, lane2: (inout EuclidLine) -> Void = { _ in }, fourthLane: Bool = false, soloMask: UInt8 = 0) -> PluginState {
        var m = Machine(machineID: "gold", type: .euclid)
        m.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)
        m.paramsA.soloMask = soloMask == 0 ? nil : soloMask
        func line(rotate: Int) -> EuclidLine {
            var l = EuclidLine(target: 0, pulses: 1, steps: 4)
            l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = true; l.sourceMode = .key
            l.rotate = rotate; l.riffRotate = rotate
            return l
        }
        var a = line(rotate: 0), b = line(rotate: 2)
        b.riffOutMask = 0b0001; b.notesOutMask = 0b0001   // lane 2 → output A (its default is B)
        lane1(&a); lane2(&b)
        m.paramsA.euclidLines = [a, b] + (2..<4).map { i in i == 3 && fourthLane ? line(rotate: 0) : EuclidLine(enabled: false) }
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? m : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousKeyRoot = 0; st.euclideousKeyType = .naturalMinor
        var set = EmitterCCSet(); set[0] = cc; st.euclideousEmitterCCs = set
        return st
    }
    private let beatSamples = 24_000.0   // 120 BPM at 48 kHz

    func testFallEndsAtTheNextHitOnTheEmitterNotTheLanesOwn() {
        // Lane 1 hits at beats 0, 4, 8…; lane 2 at 2, 6…, both on A. FALL over 100 % of the gap from the beat-0 hit must reach LOW by beat 2 (lane 2's hit), not by beat 4.
        let rig = CCRig(twoLaneState(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 100, low: 0, travel: .fall, time: 100)))
        rig.run(to: 2.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        let beforeBeat2 = tl.filter { Double($0.sample) < 2.0 * beatSamples - 1 }
        XCTAssertEqual(beforeBeat2.first?.value, 100, "the beat-0 hit jumps to the level")
        XCTAssertLessThanOrEqual(beforeBeat2.last?.value ?? 100, 3, "merged gap = 2 beats, so the ramp is down to ~LOW just before lane 2's hit (own-lane gap would leave it near 50): \(beforeBeat2.last.map { String($0.value) } ?? "none")")
    }
    func testGlideAimsAtTheValueTheNextHitOnTheEmitterWillRead() {
        // Ranks [1, 8, 2, …]: lane 1's hit at beat 0 reads column 0 (rank 1 → 0); lane 2's hit at beat 2 reads column 2 (rank 2 → 18); lane 1's own next hit (beat 4) would read column 1 (rank 8 → 127).
        let rig = CCRig(twoLaneState(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: .glide, time: 100), ranks: [1, 8, 2, 2, 2, 2, 2, 2]))
        rig.run(to: 2.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        let beforeBeat2 = tl.filter { Double($0.sample) < 2.0 * beatSamples - 1 }
        XCTAssertEqual(beforeBeat2.first?.value, 0, "the beat-0 hit reads rank 1 → LOW")
        let last = beforeBeat2.last?.value ?? -1
        XCTAssertTrue((16...18).contains(last), "GLIDE heads for lane 2's rank-2 value (18) by beat 2, not for lane 1's own next rank-8 value (127, which would read ~63 here): \(last)")
    }
    func testAnEmitterWithOneLaneOnlyStillUsesItsOwnGap() {
        // With nothing else routed to A the merged gap is the lane's own 4 beats: at beat 2 the FALL is half way (≈50).
        let rig = CCRig(twoLaneState(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 100, low: 0, travel: .fall, time: 100),
                                     lane2: { $0.riffOutMask = 0b0010; $0.notesOutMask = 0b0010 }))   // lane 2 → B again
        rig.run(to: 2.0)
        let beforeBeat2 = rig.out.timeline(cable: 1, cc: 74).filter { Double($0.sample) < 2.0 * beatSamples - 1 }
        let last = beforeBeat2.last?.value ?? -1
        XCTAssertTrue((46...52).contains(last), "own gap of 4 beats ⇒ about half way at beat 2: \(last)")
    }
    func testAMutedLanesHitIsNotAHitOnTheEmitter() {
        // Lane 2 is LANES-muted (all 16 cells clear): its beat-2 hit is silent, so lane 1's gap stays 4 beats (half way at beat 2), and lane 2's hit does not jump the CC.
        let rig = CCRig(twoLaneState(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 100, low: 0, travel: .fall, time: 100), lane2: { $0.muteCells16 = 0 }))
        rig.run(to: 3.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        let atBeat2 = tl.filter { Double($0.sample) < 2.0 * beatSamples - 1 }.last?.value ?? -1
        XCTAssertTrue((46...52).contains(atBeat2), "a muted lane's hit is not the emitter's next hit: \(atBeat2)")
        XCTAssertFalse(tl.contains { $0.value == 100 && Double($0.sample) > 1.0 * beatSamples }, "and it does not fire the CC")
    }
    func testWhenEveryRoutedLaneIsStoppedTheEmitterSendsMuteValueOnce() {
        let cc = EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 90, travel: .step, muteValue: 7)
        // both lanes PLAY off
        var rig = CCRig(twoLaneState(cc: cc, lane1: { $0.enabled = false }, lane2: { $0.enabled = false }))
        rig.run(to: 6.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [7], "every routed lane stopped ⇒ muteValue once, then nothing")
        // both lanes LANES-muted
        rig = CCRig(twoLaneState(cc: cc, lane1: { $0.muteCells16 = 0 }, lane2: { $0.muteCells16 = 0 }))
        rig.run(to: 6.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [7], "every routed lane LANES-muted ⇒ muteValue once")
        // only ONE of the two stopped ⇒ the other still drives the emitter and nothing is "muted"
        rig = CCRig(twoLaneState(cc: cc, lane1: { $0.enabled = false }))
        rig.run(to: 6.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [90], "lane 2 still plays, so the emitter is live: its hit sends the level, no muteValue")
    }
    func testASoloSilencedEmitterSendsMuteValue() {
        // Lanes 1 and 2 both feed A; lane 4 (output D) is soloed, which silences them both ⇒ muteValue once.
        let rig = CCRig(twoLaneState(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 90, travel: .step, muteValue: 7), fourthLane: true, soloMask: 0b1000))   // lane 4 (output D) solo
        rig.run(to: 6.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [7], "solo elsewhere silences every lane routed to A ⇒ muteValue once")
    }
    func testAnEmitterNothingIsRoutedToSendsNothing() {
        // Both lanes routed away from A: no lane feeds it, so there is nothing to be muted — it stays quiet (no stray muteValue).
        let rig = CCRig(twoLaneState(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 90, travel: .step, muteValue: 7),
                                     lane1: { $0.riffOutMask = 0b0010; $0.notesOutMask = 0b0010 }, lane2: { $0.riffOutMask = 0b0100; $0.notesOutMask = 0b0100 }))
        rig.run(to: 6.0)
        XCTAssertTrue(rig.out.values(cable: 1, cc: 74).isEmpty, "no lane routed to A ⇒ nothing sent")
    }
    func testTheOutputGateIsJudgedAtTheHitsOwnBeatNotTheWindowStart() {
        // Output A's gate is open only for cells 4…7 (beats 1…2 of lane 1's 4-beat pass). With a 512-frame window the beat-1 hit lands MID-window: the window started in the closed cell 3, but the hit itself is in an open cell and must fire at its own sample.
        var st = state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 90, travel: .step, muteValue: 7))
        var mutes = EuclideousOutputMutes(); mutes[0] = EuclideousOutputMute(cells16: 0b0000_0000_1111_0000, passes: 1); st.euclideousOutputMutes = mutes
        let rig = CCRig(st, frames: 512)
        rig.run(to: 3.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertEqual(tl.first(where: { $0.value == 90 })?.sample, Int64(1.0 * beatSamples), "the hit at beat 1 sits in an open cell and fires at its own sample: \(tl)")
        XCTAssertEqual(tl.first?.value, 7, "the gate is closed before it, so muteValue goes out first")
    }
    func testAnEarlierHitHeldByALaterLaneIsNotSentOutOfOrder() {
        // One 2.5-beat window. Lane 1 (processed first) hits at beat 2, lane 2 at beat 0, both on A, FIXED-by-rank values 18 and 0. Lane 2's beat-0 hit is superseded in time by lane 1's beat-2 hit, so the messages stay in time order and the emitter ends on 18.
        let rig = CCRig(twoLaneState(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: .step), ranks: [1, 8, 2, 2, 2, 2, 2, 2],
                                     lane1: { $0.rotate = 2; $0.riffRotate = 2 }, lane2: { $0.rotate = 0; $0.riffRotate = 0 }), frames: 60_000)
        rig.run(to: 2.4)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertEqual(tl.map { $0.sample }, tl.map { $0.sample }.sorted(), "the emitter's messages are in time order: \(tl)")
        XCTAssertEqual(tl.last?.value, 18, "the later hit (lane 1 at beat 2, rank 2 → 18) is the value the emitter ends on: \(tl)")
    }
}
