//  EmitterCCTests.swift — CC tab (ratified Nov 2026): the per-output CC emitters.
//
//  The pure value math (FIXED / RIFF, the LOW…HIGH map including the inverted LOW > HIGH case, the per-emitter default CC numbers, decode tolerance) and the engine end to end: a CC fires on each hit with the right value, FIXED holds a
//  level, RIFF tracks the riff rank at the hit (even with PLAY RIFF off), STEP holds between hits, a muted output sends `muteValue` once, and CC off emits nothing (byte-identical, covered by the golden harness).

import XCTest

private final class CCEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let cc: UInt8; let value: UInt8 }
    private(set) var cc: [Ev] = []
    private(set) var other: [String] = []   // every non-CC message (notes, bend…), for the "CC never changes the notes" comparison
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        if b0 & 0xF0 == 0xB0 { cc.append(Ev(sample: sampleTime, cable: cable, cc: b1, value: b2)) }
        else { other.append("\(sampleTime) c\(cable) \(String(b0, radix: 16)) \(b1) \(b2)") }
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
    private func state(cc: EmitterCC, riffRanks: [Int] = [1, 1, 1, 1, 1, 1, 1, 1], muteA: Bool = false, playRiffOff: Bool = false, pulses: Int = 4) -> PluginState {
        var m = Machine(machineID: "gold", type: .euclid)
        m.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: riffRanks)
        var l = EuclidLine(target: 0, pulses: pulses, steps: 4)   // a hit on every step (pulses 4)
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

    // MARK: a CC is a CC — it never touches the notes
    /// The same documents with CC off and with every VALUE × TRAVEL on all four emitters must produce the identical NOTE stream (every non-CC message, event for event), across host buffer sizes.
    func testCCNeverRestrikesOrReshapesTheNotes() {
        func docs(_ cc: EmitterCC?) -> [PluginState] {
            var out: [PluginState] = []
            func put(_ st: PluginState) { var t = st; if let cc { var set = EmitterCCSet(); for i in 0..<4 { var c = cc; c.ccNumber = [74, 71, 1, 11][i]; set[i] = c }; t.euclideousEmitterCCs = set } else { t.euclideousEmitterCCs = nil }; out.append(t) }
            put(state(cc: EmitterCC(), riffRanks: [1, 8, 3, 6, 2, 7, 4, 5]))                                         // one lane, a hit on every step
            put(state(cc: EmitterCC(), riffRanks: [1, 1, 1, 1, 1, 1, 1, 1], playRiffOff: false))                    // the same rank every hit (the same-note guard's case)
            put(twoLaneState(cc: EmitterCC(), ranks: [1, 8, 3, 6, 2, 7, 4, 5]))                                      // two lanes on one output
            put(twoLaneState(cc: EmitterCC(), ranks: [1, 8, 3, 6, 2, 7, 4, 5], lane1: { $0.gate = 0.99; $0.pulses = 3 }, lane2: { $0.gate = 0.99; $0.pulses = 2; $0.riffOnRest = .tie }, fourthLane: true))   // long gates, TIE
            return out
        }
        let variants: [(String, EmitterCC)] = [
            ("fixed step", EmitterCC(on: true, valueMode: .fixed, level: 90, travel: .step)), ("fixed glide", EmitterCC(on: true, valueMode: .fixed, level: 90, travel: .glide, time: 100)),
            ("fixed fall", EmitterCC(on: true, valueMode: .fixed, level: 90, low: 10, travel: .fall, time: 80)),
            ("riff step", EmitterCC(on: true, valueMode: .riff, travel: .step)), ("riff glide", EmitterCC(on: true, valueMode: .riff, travel: .glide, time: 100)),
            ("riff fall", EmitterCC(on: true, valueMode: .riff, travel: .fall, time: 60)),
            ("ping-pong step", EmitterCC(on: true, valueMode: .pingPong, high: 120, low: 10, travel: .step)), ("ping-pong glide", EmitterCC(on: true, valueMode: .pingPong, high: 120, low: 10, travel: .glide, time: 100)),
            ("sine 1 bar", EmitterCC(on: true, valueMode: .sine, high: 120, low: 10, sineBars: 3)), ("sine 1/8 bar", EmitterCC(on: true, valueMode: .sine, high: 120, low: 10, sineBars: 0)),
        ]
        for frames: UInt32 in [128, 4096] {
            let base = docs(nil)
            for (name, cc) in variants {
                for (i, st) in docs(cc).enumerated() {
                    let off = CCRig(base[i], frames: frames), on = CCRig(st, frames: frames)
                    off.run(to: 8.0); on.run(to: 8.0)
                    XCTAssertFalse(on.out.cc.isEmpty, "\(name) doc \(i): the CC variant must actually be sending")
                    XCTAssertTrue(off.out.cc.isEmpty)
                    XCTAssertFalse(off.out.other.isEmpty, "doc \(i) plays notes")
                    XCTAssertEqual(on.out.other, off.out.other, "\(name) doc \(i) @\(frames) frames: CC on must not change a single note message")
                }
            }
        }
    }

    // MARK: the drawn curve is the one the Router sends
    /// One lane, a hit on every beat of a 4-beat bar, ranks 1 8 3 6 repeating: the pure `emitterCCTrace` of those hits must follow the CC messages the Router actually sends over the second bar — exactly for STEP, within one rate-limited ramp
    /// step (the engine sends at most once per 1/24 beat, on a change) for GLIDE and FALL — so the picture can never describe a different engine.
    func testTheTraceFollowsWhatTheRouterSends() {
        let ranks = [1, 8, 3, 6, 1, 8, 3, 6]
        for (name, mode, travel, time, tol) in [("step", EmitterCCValueMode.riff, EmitterCCTravel.step, 50, 0), ("glide 100", .riff, .glide, 100, 6), ("glide 50", .riff, .glide, 50, 6), ("fall 50", .riff, .fall, 50, 6), ("fall 100", .riff, .fall, 100, 6),
                                                ("ping-pong step", .pingPong, .step, 50, 0), ("ping-pong glide", .pingPong, .glide, 100, 6), ("ping-pong glide 50", .pingPong, .glide, 50, 6), ("ping-pong fall", .pingPong, .fall, 50, 6)] {
            let c = EmitterCC(on: true, ccNumber: 74, valueMode: mode, high: 127, low: 0, travel: travel, time: time)
            let rig = CCRig(state(cc: c, riffRanks: ranks))
            rig.run(to: 8.0)
            let sent = rig.out.timeline(cable: 1, cc: 74)
            let trace = emitterCCTrace(cfg: EmitterCCCfg(c), hits: [(0.0, 1), (1.0, 8), (2.0, 3), (3.0, 6)].enumerated().map { EmitterCCTraceHit(beat: $0.element.0, rank: $0.element.1, lane: 0, ordinal: Int64($0.offset)) }, barBeats: 4)
            var worst = 0
            for i in 1..<96 {   // bar 2, off the exact hit samples (a hit and the ramp's last step share a sample)
                let b = Double(i) / 24
                let sample = Int64(((4.0 + b) * beatSamples).rounded())
                guard i % 24 != 0, let engine = sent.last(where: { $0.sample <= sample })?.value, let drawn = trace.points.first(where: { abs(Double($0.x) - b) < 1e-6 }).map({ Int($0.y) }) else { continue }
                worst = max(worst, abs(engine - drawn))
            }
            XCTAssertLessThanOrEqual(worst, tol, "\(name): the drawn curve and the CC stream differ by \(worst)")
        }
    }

    // MARK: PING-PONG (2026-11-09) — HIGH on the lane's even riff hits, LOW on its odd ones
    func testPingPongValueRuleAndDecode() {
        var c = EmitterCCCfg(EmitterCC(valueMode: .pingPong, level: 33, high: 120, low: 10))
        XCTAssertEqual(c.value(rank: 3, ordinal: 0), 120, "an even hit is HIGH"); XCTAssertEqual(c.value(rank: 3, ordinal: 1), 10, "an odd hit is LOW")
        XCTAssertEqual(c.value(rank: 0, ordinal: 2), 120, "a riff rest still sends: the rank is not read"); XCTAssertEqual(c.value(rank: 8, ordinal: 7), 10)
        XCTAssertEqual(c.value(rank: 1, ordinal: -1), 10, "parity holds for a negative ordinal too")
        c = EmitterCCCfg(EmitterCC(valueMode: .pingPong, high: 5, low: 100))
        XCTAssertEqual(c.value(rank: 1, ordinal: 0), 5); XCTAssertEqual(c.value(rank: 1, ordinal: 1), 100, "LOW above HIGH is not swapped or clamped")
        XCTAssertEqual(EmitterCCCfg(EmitterCC(valueMode: .fixed, level: 33)).value(rank: 0, ordinal: 1), 33); XCTAssertNil(EmitterCCCfg(EmitterCC(valueMode: .riff)).value(rank: 0, ordinal: 0))
        var set = EmitterCCSet(); set[2] = EmitterCC(on: true, ccNumber: 20, valueMode: .pingPong, high: 90, low: 30, travel: .glide)
        let data = try! JSONEncoder().encode(set)
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCCSet.self, from: data), set, "PING-PONG round-trips")
        let junk = #"{"valueMode":"TRIANGLE"}"#.data(using: .utf8)!
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCC.self, from: junk).valueMode, .riff, "an unknown value mode decodes as RIFF")
    }
    func testPingPongAlternatesHighAndLowOnEveryHit() {
        let rig = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .pingPong, high: 120, low: 10, travel: .step), riffRanks: [1, 8, 3, 6, 1, 8, 3, 6]))
        rig.run(to: 5.5)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertEqual(tl.map { $0.value }, [120, 10, 120, 10, 120, 10], "a hit a beat: HIGH, LOW, HIGH… whatever the riff ranks are")
        for (i, e) in tl.enumerated() { XCTAssertEqual(Double(e.sample), Double(i) * beatSamples, accuracy: 2, "each on its own hit") }
    }
    func testPingPongGlideIsATriangleBetweenHighAndLow() {
        let rig = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .pingPong, high: 120, low: 0, travel: .glide, time: 100)))
        rig.run(to: 3.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        func at(_ beat: Double) -> Int { tl.last(where: { Double($0.sample) <= beat * beatSamples })?.value ?? -1 }
        XCTAssertEqual(at(0.0), 120); XCTAssertEqual(at(0.5), 60, "half way down the ramp to LOW"); XCTAssertEqual(at(1.0), 0, "arrives on the odd hit")
        XCTAssertEqual(at(1.5), 60, "and back up"); XCTAssertEqual(at(2.0), 120)
    }
    func testPingPongGlideAimsAtTheOrdinalOfTheNextHitOnTheEmitterNotTheLanesOwn() {
        // Two lanes on A, hits at beat 0 (lane 1, its first: even → HIGH 120) and beat 2 (lane 2, ITS first: even → HIGH 120); lane 1's own next hit (beat 4) is odd → LOW. GLIDE 100 % from beat 0 aims at lane 2's HIGH, so it stays up through beat 2.
        let rig = CCRig(twoLaneState(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .pingPong, high: 120, low: 0, travel: .glide, time: 100)))
        rig.run(to: 2.0)
        let tl = rig.out.timeline(cable: 1, cc: 74).filter { Double($0.sample) < 2.0 * beatSamples - 1 }
        XCTAssertEqual(tl.first?.value, 120)
        XCTAssertGreaterThanOrEqual(tl.last?.value ?? 0, 115, "heading for lane 2's HIGH (own-lane aim would have fallen to ≈60 by beat 2): \(tl.map { $0.value })")
    }

    /// A 3-hit bar flips PING-PONG's parity every bar; the drawn curve (bar 2 here, ordinals 3…5, the seam read from bars 1 and 3) must still be the one the Router sends — including the glide on into the next bar.
    func testThePingPongTraceFollowsTheRouterAcrossAnOddBarSeam() {
        let steps = euclideousLapHitSteps(pulses: 3, steps: 4, rotate: 0, tilt: 0, patternMiss: false, customHits: nil)
        XCTAssertEqual(steps.count, 3)
        for (name, travel, tol) in [("step", EmitterCCTravel.step, 0), ("glide", .glide, 6), ("fall", .fall, 6)] {
            let c = EmitterCC(on: true, ccNumber: 74, valueMode: .pingPong, high: 120, low: 0, travel: travel, time: 100)
            let rig = CCRig(state(cc: c, pulses: 3))
            rig.run(to: 12.0)
            let sent = rig.out.timeline(cable: 1, cc: 74)
            let trace = emitterCCTrace(cfg: EmitterCCCfg(c), hits: steps.enumerated().map { EmitterCCTraceHit(beat: Double($0.element.tick), rank: 1, lane: 0, ordinal: Int64(3 + $0.offset)) }, barBeats: 4)
            var worst = 0
            for i in 1..<96 where i % 24 != 0 {
                let b = Double(i) / 24
                let sample = Int64(((4.0 + b) * beatSamples).rounded())
                guard !steps.contains(where: { abs(Double($0.tick) - b) < 0.05 }), let engine = sent.last(where: { $0.sample <= sample })?.value, let drawn = trace.points.first(where: { abs(Double($0.x) - b) < 1e-6 }).map({ Int($0.y) }) else { continue }
                worst = max(worst, abs(engine - drawn))
            }
            XCTAssertLessThanOrEqual(worst, tol, "\(name): the drawn bar and the CC stream differ by \(worst)")
        }
    }

    // MARK: SINE (2026-11-09) — free-running between LOW and HIGH, locked to the host bar, not driven by hits
    func testSineValueRuleAndDecode() {
        let c = EmitterCCCfg(EmitterCC(valueMode: .sine, high: 120, low: 20, sineBars: 3))   // 1 bar a cycle, 4 beats
        XCTAssertEqual(c.sineValue(beat: 0, beatsPerBar: 4), 20, "a cycle starts at LOW"); XCTAssertEqual(c.sineValue(beat: 2, beatsPerBar: 4), 120, "half way it crests at HIGH")
        XCTAssertEqual(c.sineValue(beat: 1, beatsPerBar: 4), 70, "a quarter in: half way up"); XCTAssertEqual(c.sineValue(beat: 4, beatsPerBar: 4), 20, "and the next bar line starts the next cycle")
        XCTAssertEqual(c.sineValue(beat: -1, beatsPerBar: 4), 70, "a negative beat is the same phase a cycle later")
        XCTAssertEqual(c.sineValue(beat: 3, beatsPerBar: 3), 20, "the bar is the HOST's: in 3/4 a bar line is beat 3")
        let slow = EmitterCCCfg(EmitterCC(valueMode: .sine, high: 120, low: 20, sineBars: 5))   // 4 bars
        XCTAssertEqual(slow.sineValue(beat: 8, beatsPerBar: 4), 120, "crest after 2 bars"); XCTAssertEqual(slow.sineValue(beat: 16, beatsPerBar: 4), 20)
        let inv = EmitterCCCfg(EmitterCC(valueMode: .sine, high: 10, low: 100, sineBars: 3))
        XCTAssertEqual(inv.sineValue(beat: 0, beatsPerBar: 4), 100); XCTAssertEqual(inv.sineValue(beat: 2, beatsPerBar: 4), 10, "LOW above HIGH inverts it")
        XCTAssertNil(c.value(rank: 5, ordinal: 2), "a hit carries no value in SINE")
        // codable: BARS round-trips, clamps, defaults to 1 bar; "SINE" decodes
        var set = EmitterCCSet(); set[1] = EmitterCC(on: true, ccNumber: 20, valueMode: .sine, high: 90, low: 30, sineBars: 6)
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCCSet.self, from: try! JSONEncoder().encode(set)), set)
        let bare = try! JSONDecoder().decode(EmitterCC.self, from: #"{"valueMode":"SINE"}"#.data(using: .utf8)!)
        XCTAssertEqual(bare.valueMode, .sine); XCTAssertEqual(bare.sineBars, 3, "an older document has no BARS: 1 bar")
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCC.self, from: #"{"sineBars":99}"#.data(using: .utf8)!).sineBars, 7); XCTAssertEqual(try! JSONDecoder().decode(EmitterCC.self, from: #"{"sineBars":-4}"#.data(using: .utf8)!).sineBars, 0)
        XCTAssertEqual(EmitterCC.sinePeriodSlider.count, EmitterCC.sinePeriodBars.count); XCTAssertEqual(EmitterCC.sinePeriodRow.count, EmitterCC.sinePeriodBars.count)
    }
    func testASineSendsTheFormulaWithNoHitsAtAll() {
        let sine = EmitterCC(on: true, ccNumber: 74, valueMode: .sine, high: 120, low: 0, sineBars: 3)
        let rig = CCRig(state(cc: sine, pulses: 0))   // the lane is routed to A and has NO hits
        rig.run(to: 8.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertGreaterThan(tl.count, 40, "a sine sends continuously: \(tl.count) messages in two bars")
        XCTAssertEqual(tl.first?.value, 0, "it starts at LOW on the first bar line"); XCTAssertEqual(rig.out.values(cable: 0, cc: 74), tl.map { UInt8($0.value) }, "mirrored on ALL")
        let c = EmitterCCCfg(sine)
        for e in tl { XCTAssertEqual(e.value, c.sineValue(beat: Double(e.sample) / beatSamples, beatsPerBar: 4), accuracy: 1, "sample \(e.sample)") }
        XCTAssertEqual(tl.map { $0.sample }, tl.map { $0.sample }.sorted(), "in time order")
        for (a, b) in zip(tl, tl.dropFirst()) { XCTAssertGreaterThanOrEqual(Double(b.sample - a.sample), beatSamples / 24 - 1, "never faster than the 1/96-note rate limit") }
        XCTAssertTrue(tl.contains { $0.value >= 118 } && tl.contains { $0.value <= 2 }, "it covers LOW…HIGH")
    }
    func testHitsDriveNothingInSine() {
        let sine = EmitterCC(on: true, ccNumber: 74, valueMode: .sine, high: 120, low: 0, sineBars: 3)
        let none = CCRig(state(cc: sine, pulses: 0)), busy = CCRig(state(cc: sine, pulses: 4))
        none.run(to: 6.0); busy.run(to: 6.0)
        XCTAssertEqual(busy.out.timeline(cable: 1, cc: 74).map { "\($0.sample)/\($0.value)" }, none.out.timeline(cable: 1, cc: 74).map { "\($0.sample)/\($0.value)" }, "a lane with a hit on every beat changes nothing: the sine is not hit-driven")
    }
    func testASineFollowsTheSameMuteRulesAsEverythingElse() {
        let sine = EmitterCC(on: true, ccNumber: 74, valueMode: .sine, high: 120, low: 0, muteValue: 7, sineBars: 3)
        // every routed lane stopped ⇒ muteValue once, no sine
        var rig = CCRig(twoLaneState(cc: sine, lane1: { $0.enabled = false }, lane2: { $0.enabled = false }))
        rig.run(to: 6.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [7], "every routed lane stopped ⇒ muteValue once, then nothing")
        // one lane still plays ⇒ the sine runs
        rig = CCRig(twoLaneState(cc: sine, lane1: { $0.enabled = false }))
        rig.run(to: 6.0)
        XCTAssertGreaterThan(rig.out.values(cable: 1, cc: 74).count, 40); XCTAssertFalse(rig.out.values(cable: 1, cc: 74).contains(7) && rig.out.values(cable: 1, cc: 74).first == 7, "a live lane carries it")
        // nothing routed ⇒ nothing at all
        rig = CCRig(twoLaneState(cc: sine, lane1: { $0.riffOutMask = 0b0010; $0.notesOutMask = 0b0010 }, lane2: { $0.riffOutMask = 0b0100; $0.notesOutMask = 0b0100 }))
        rig.run(to: 6.0)
        XCTAssertTrue(rig.out.values(cable: 1, cc: 74).isEmpty, "no lane routed to A ⇒ nothing sent, not even the mute value")
        // the MUTE tab's output gate fully closed ⇒ muteValue once
        rig = CCRig(state(cc: sine, muteA: true, pulses: 0))
        rig.run(to: 6.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [7], "a closed output gate silences the emitter")
    }
    func testASineResumesAtOnceWhenALaneComesBack() {
        let sine = EmitterCC(on: true, ccNumber: 74, valueMode: .sine, high: 120, low: 0, muteValue: 7, sineBars: 3)
        let rig = CCRig(twoLaneState(cc: sine, lane1: { $0.enabled = false }, lane2: { $0.enabled = false }))
        rig.run(to: 2.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [7])
        rig.box = SnapshotBuilder.build(from: twoLaneState(cc: sine))   // PLAY back on
        rig.run(to: 3.0)
        let after = rig.out.timeline(cable: 1, cc: 74).filter { Double($0.sample) >= 2.0 * beatSamples }
        XCTAssertFalse(after.isEmpty, "the sine is sending again right away (no hit needed)")
        XCTAssertEqual(Double(after[0].sample), 2.0 * beatSamples, accuracy: 2.0 * beatSamples / 24 + 480, "within one rate-limit step of the lane coming back")
        XCTAssertEqual(after[0].value, EmitterCCCfg(sine).sineValue(beat: Double(after[0].sample) / beatSamples, beatsPerBar: 4), accuracy: 1)
    }
    func testTheSineTraceFollowsWhatTheRouterSends() {
        for bars in [3, 5, 2] {   // 1 bar, 4 bars, ½ bar a cycle
            let c = EmitterCC(on: true, ccNumber: 74, valueMode: .sine, high: 120, low: 10, sineBars: bars)
            let rig = CCRig(state(cc: c, pulses: 0))
            rig.run(to: 12.0)
            let sent = rig.out.timeline(cable: 1, cc: 74)
            let trace = emitterCCSineTrace(cfg: EmitterCCCfg(c), barStartBeat: 4, barBeats: 4)   // the second bar
            var worst = 0
            for p in trace.dropFirst() {
                let sample = Int64(((4.0 + Double(p.x)) * beatSamples).rounded())
                guard let engine = sent.last(where: { $0.sample <= sample })?.value else { continue }
                worst = max(worst, abs(engine - Int(p.y)))
            }
            XCTAssertLessThanOrEqual(worst, bars == 2 ? 28 : 6, "bars index \(bars): the drawn sine and the CC stream differ by \(worst)")
        }
    }

    // MARK: RIFF spans the riff's own range (2026-11-09) — "the CC value that's output only goes up to 50 %"
    /// The factory riff is 1 2 3 5 4 3 2 1: its highest note is rank 5, so a rank-over-1…8 map peaked at 73 (57 % of HIGH) and could never reach it. The output must now run LOW (the riff's lowest note) to HIGH (its highest).
    func testTheFactoryRiffReachesHighAndLowOnTheWire() {
        let rig = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: .step), riffRanks: [1, 2, 3, 5, 4, 3, 2, 1]))
        rig.run(to: 8.0)
        let vals = rig.out.values(cable: 1, cc: 74).map { Int($0) }
        XCTAssertEqual(vals.max(), 127, "the riff's highest note is HIGH: \(vals)"); XCTAssertEqual(vals.min(), 0, "its lowest is LOW")
        XCTAssertEqual(Set(vals), Set([1, 2, 3, 5, 4].map { Int((Double($0 - 1) / 4.0 * 127).rounded()) }), "rank 1 2 3 4 5 → 0 32 64 95 127: \(Set(vals))")
        // a narrower window and an inverted one scale the same way
        let narrow = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 100, low: 40, travel: .step), riffRanks: [3, 4, 3, 4, 3, 4, 3, 4]))
        narrow.run(to: 6.0)
        XCTAssertEqual(Set(narrow.out.values(cable: 1, cc: 74).map { Int($0) }), [40, 100], "a riff of two notes spans the whole window")
        let inv = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 0, low: 127, travel: .step), riffRanks: [2, 6, 2, 6, 2, 6, 2, 6]))
        inv.run(to: 6.0)
        XCTAssertEqual(Set(inv.out.values(cable: 1, cc: 74).map { Int($0) }), [127, 0], "LOW above HIGH still inverts: the lowest note is LOW (127)")
        // a riff with ONE distinct note has no range to span: it keeps the literal rank map (rank 3 → 2/7 of the way)
        let one = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: .step), riffRanks: [3, 3, 3, 3, 3, 3, 3, 3]))
        one.run(to: 4.0)
        XCTAssertEqual(one.out.values(cable: 1, cc: 74), [Int((2.0 / 7.0 * 127).rounded())].map { UInt8($0) })
    }
    func testTheRiffSpanIsTheLowestAndHighestNoteTheRiffUses() {
        XCTAssertEqual(emitterCCRiffSpan(ranks: [1, 2, 3, 5, 4, 3, 2, 1], count: 8), EmitterCCRiffSpan(lo: 1, hi: 5))
        XCTAssertEqual(emitterCCRiffSpan(ranks: [0, 4, 0, 6, 0, 0, 7, 0], count: 8), EmitterCCRiffSpan(lo: 4, hi: 7), "rests are ignored")
        XCTAssertEqual(emitterCCRiffSpan(ranks: [0, 0, 0, 0, 0, 0, 0, 0], count: 8), .full, "no note at all: the literal map")
        XCTAssertEqual(emitterCCRiffSpan(ranks: [2, 2, 2, 2, 2, 2, 2, 2], count: 8), EmitterCCRiffSpan(lo: 2, hi: 2))
        XCTAssertEqual(emitterCCRiffSpan(ranks: [3, 3, 3, 3, 3, 3, 3, 3, 8, 8, 8, 8, 8, 8, 8, 8], count: 8), EmitterCCRiffSpan(lo: 3, hi: 3), "only the columns the engine reads (8 in MONO)")
        XCTAssertEqual(emitterCCRiffSpan(ranks: [3, 3, 3, 3, 3, 3, 3, 3, 8, 8, 8, 8, 8, 8, 8, 8], count: 16), EmitterCCRiffSpan(lo: 3, hi: 8), "…16 in POLY")
        let c = EmitterCCCfg(EmitterCC(valueMode: .riff, high: 127, low: 0))
        let span = EmitterCCRiffSpan(lo: 1, hi: 5)
        XCTAssertEqual([1, 2, 3, 4, 5].map { c.riffValue(rank: $0, span: span) }, [0, 32, 64, 95, 127])
        XCTAssertEqual(c.riffValue(rank: 8), 127, "the literal map is still there for rank 8"); XCTAssertEqual(c.value(rank: 5, ordinal: 0, span: span), 127)
        XCTAssertEqual(c.riffValue(rank: 3, span: EmitterCCRiffSpan(lo: 3, hi: 3)), Int((2.0 / 7.0 * 127).rounded()), "one distinct note: its literal height")
        XCTAssertEqual(EmitterCCCfg(EmitterCC(valueMode: .fixed, level: 99)).value(rank: 1, ordinal: 0, span: span), 99, "FIXED ignores the span")
    }
    func testTheTraceUsesTheSameSpanTheRouterDoes() {
        let ranks = [1, 2, 3, 5, 1, 2, 3, 5]   // four hits a bar, the riff spanning ranks 1…5
        for (name, travel) in [("step", EmitterCCTravel.step), ("glide", .glide), ("fall", .fall)] {
            let c = EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: travel, time: 100)
            let rig = CCRig(state(cc: c, riffRanks: ranks))
            rig.run(to: 8.0)
            let sent = rig.out.timeline(cable: 1, cc: 74)
            let trace = emitterCCTrace(cfg: EmitterCCCfg(c), hits: [(0.0, 1), (1.0, 2), (2.0, 3), (3.0, 5)].enumerated().map { EmitterCCTraceHit(beat: $0.element.0, rank: $0.element.1, lane: 0, ordinal: Int64(4 + $0.offset)) },
                                    barBeats: 4, span: emitterCCRiffSpan(ranks: ranks, count: 8))
            XCTAssertEqual(trace.dots.map { Int($0.y) }, [0, 32, 64, 127], "\(name): the drawn dots span LOW…HIGH")
            var worst = 0
            for i in 1..<96 where i % 24 != 0 {
                let b = Double(i) / 24, sample = Int64(((4.0 + b) * beatSamples).rounded())
                guard let engine = sent.last(where: { $0.sample <= sample })?.value, let drawn = trace.points.first(where: { abs(Double($0.x) - b) < 1e-6 }).map({ Int($0.y) }) else { continue }
                worst = max(worst, abs(engine - drawn))
            }
            XCTAssertLessThanOrEqual(worst, travel == .step ? 0 : 6, "\(name): the drawn bar and the CC stream differ by \(worst)")
        }
    }

    // MARK: a setting changed under a running segment is followed AT ONCE (the page's ring and the synth no longer finish the old ramp)
    private func replanRig(_ before: EmitterCC, _ after: EmitterCC, swapAt: Double, to end: Double, ranks: [Int] = [1, 8, 1, 8, 1, 8, 1, 8]) -> [(sample: Int64, value: Int)] {
        let rig = CCRig(state(cc: before, riffRanks: ranks))
        rig.run(to: swapAt)
        rig.box = SnapshotBuilder.build(from: state(cc: after, riffRanks: ranks))   // the slider dragged: a new snapshot, same hits
        rig.run(to: end)
        return rig.out.timeline(cable: 1, cc: 74)
    }
    func testAGlideFollowsANewHighAtOnceInsteadOfFinishingTheOldRamp() {
        // hits a beat apart, ranks 1 8 1 8: the hit at beat 2 (rank 1 → 0) glides toward the beat-3 hit (rank 8 → HIGH) over the whole gap. HIGH is dragged from 127 to 60 at beat 2.5: the ramp must now arrive at 60, never overshoot to 127.
        let tl = replanRig(EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: .glide, time: 100), EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 60, low: 0, travel: .glide, time: 100), swapAt: 2.5, to: 3.0)
        let after = tl.filter { Double($0.sample) >= 2.5 * beatSamples }
        XCTAssertFalse(after.isEmpty)
        XCTAssertLessThanOrEqual(after.map { $0.value }.max() ?? 999, 61, "the ramp heads for the NEW high: \(after.map { $0.value })")
        let at275 = tl.last(where: { Double($0.sample) <= 2.75 * beatSamples })?.value ?? -1
        XCTAssertEqual(at275, 45, accuracy: 3, "¾ of the way up the ramp 0 → 60 at beat 2.75")
    }
    func testAHeldValueFollowsANewLevelAtOnceNotAtTheNextHit() {
        let tl = replanRig(EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 90, travel: .step), EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 40, travel: .step), swapAt: 2.5, to: 2.9)
        XCTAssertEqual(tl.map { $0.value }, [90, 40], "the new level goes out within a window of the change, before the beat-3 hit")
        let t40 = tl.first(where: { $0.value == 40 })?.sample ?? 0
        XCTAssertLessThan(Double(t40), 2.6 * beatSamples, "…not at the next hit")
    }
    func testAFallFollowsANewLowAtOnce() {
        let tl = replanRig(EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 100, low: 0, travel: .fall, time: 100), EmitterCC(on: true, ccNumber: 74, valueMode: .fixed, level: 100, low: 60, travel: .fall, time: 100), swapAt: 0.5, to: 0.95)
        let after = tl.filter { Double($0.sample) >= 0.5 * beatSamples }
        XCTAssertGreaterThanOrEqual(after.map { $0.value }.min() ?? 0, 59, "the fall now bottoms out at the new LOW (60), not 0: \(after.map { $0.value })")
    }
    func testSwitchingToSineAndBackWaitsForTheNextHit() {
        let rig = CCRig(state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: .step), riffRanks: [1, 8, 1, 8, 1, 8, 1, 8]))
        rig.run(to: 2.5)
        rig.box = SnapshotBuilder.build(from: state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .sine, high: 127, low: 0, sineBars: 3), riffRanks: [1, 8, 1, 8, 1, 8, 1, 8]))
        rig.run(to: 3.0)
        let mark = rig.out.timeline(cable: 1, cc: 74).count
        rig.box = SnapshotBuilder.build(from: state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, travel: .step), riffRanks: [1, 8, 1, 8, 1, 8, 1, 8]))
        rig.run(to: 4.5)
        let resumed = Array(rig.out.timeline(cable: 1, cc: 74).dropFirst(mark))
        XCTAssertEqual(resumed.map { $0.value }, [0], "back on RIFF nothing is re-sent from the forgotten hit: the first message is the next hit (the beat-4 hit, rank 1 → LOW)")
        XCTAssertEqual(Double(resumed.first?.sample ?? 0) / beatSamples, 4.0, accuracy: 0.01)
    }
}
