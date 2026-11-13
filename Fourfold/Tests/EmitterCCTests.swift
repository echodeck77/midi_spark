//  EmitterCCTests.swift — CC tab (ratified Nov 2026): the per-output CC emitters.
//
//  The pure value math (FIXED / RIFF, the LOW…HIGH map including the inverted LOW > HIGH case, the per-emitter default CC numbers, decode tolerance) and the engine end to end: a CC fires on each hit with the right value, FIXED holds a
//  value, RIFF tracks the riff rank at the hit (even with PLAY RIFF off), STEP holds between hits, a muted output sends `muteValue` once, and CC off emits nothing (byte-identical, covered by the golden harness).

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
        var cfg = EmitterCCCfg(EmitterCC.legacy(mode: .riff, high: 127, low: 0))
        XCTAssertEqual(cfg.riffValue(rank: 1), 0, "rank 1 → LOW")
        XCTAssertEqual(cfg.riffValue(rank: 8), 127, "rank 8 → HIGH")
        XCTAssertEqual(cfg.riffValue(rank: 4), Int((3.0 / 7.0 * 127).rounded()), "rank 4 maps linearly")
        // LOW above HIGH inverts (never clamped or swapped)
        cfg = EmitterCCCfg(EmitterCC.legacy(mode: .riff, high: 0, low: 127))
        XCTAssertEqual(cfg.riffValue(rank: 1), 127, "inverted: rank 1 → LOW (127)")
        XCTAssertEqual(cfg.riffValue(rank: 8), 0, "inverted: rank 8 → HIGH (0)")
        // a narrow window
        cfg = EmitterCCCfg(EmitterCC.legacy(mode: .riff, high: 70, low: 60))
        XCTAssertEqual(cfg.riffValue(rank: 1), 60); XCTAssertEqual(cfg.riffValue(rank: 8), 70)
    }
    func testDefaultsAndDecodeTolerance() {
        let set = EmitterCCSet()
        // CC SLOTS (2026-11-12) §1.2: three slots per output, a/b/c = 74/71/1 on EVERY output (the old per-output D=11 is gone).
        for o in 0..<4 { XCTAssertEqual([set[output: o, slot: 0].ccNumber, set[output: o, slot: 1].ccNumber, set[output: o, slot: 2].ccNumber], [74, 71, 1], "output \(o) slot defaults a/b/c = 74/71/1") }
        // amendment 1's defaults: off · HITS · HIGH 127 · LOW 0 · HOLD 25 · RAMP 50 · REST · EXP · MUTE 0
        for i in 0..<4 {
            let e = set[i]
            XCTAssertFalse(e.on, "default off"); XCTAssertEqual(e.valueMode, .hits); XCTAssertEqual(e.high, 127); XCTAssertEqual(e.low, 0); XCTAssertEqual(e.hold, 25); XCTAssertEqual(e.ramp, 50)
            XCTAssertEqual(e.to, .rest); XCTAssertEqual(e.curve, .exp); XCTAssertEqual(e.muteValue, 0); XCTAssertEqual(e.passes, 1)
        }
        XCTAssertTrue(set.isAllDefault)
        // clamps: ccNumber ≤ 119, hold / ramp 0…100, values 0…127, passes 1…16
        let c = EmitterCC(on: true, ccNumber: 127, high: -5, low: 200, hold: 150, ramp: -3, muteValue: 999, passes: 40).normalized()
        XCTAssertEqual(c.ccNumber, 119); XCTAssertEqual(c.high, 0); XCTAssertEqual(c.low, 127); XCTAssertEqual(c.hold, 100); XCTAssertEqual(c.ramp, 0); XCTAssertEqual(c.muteValue, 127); XCTAssertEqual(c.passes, 16)
        // round-trips through Codable
        var s = EmitterCCSet(); s[0] = EmitterCC(on: true, ccNumber: 20, valueMode: .pingPong, high: 64, low: 64, hold: 10, ramp: 75, to: .next, curve: .lin)
        let data = try! JSONEncoder().encode(s)
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCCSet.self, from: data), s)
    }

    // MARK: the engine
    /// A lane routing to output A with a CC emitter A: a PING-PONG whose ends are equal sends that value on every hit; RIFF tracks the rank (rank 1 → LOW, rank 8 → HIGH). A muted output sends `muteValue` once. CC off sends nothing.
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
    func testAnEqualEndedPingPongSendsItsValueOnceAndHolds() {
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .pingPong, high: 90, low: 90, travel: .step)))
        rig.run(to: 6.0)
        let vals = rig.out.values(cable: 1, cc: 74)   // cable 1 = output A
        XCTAssertEqual(vals, [90], "a constant sends once and holds (only on-change messages)")
        XCTAssertEqual(rig.out.values(cable: 0, cc: 74), vals, "mirrored on ALL (cable 0)")
    }
    func testRiffTracksTheRankEvenWithPlayRiffOff() {
        // ranks 1 and 8 alternate → the CC alternates LOW (0) and HIGH (127); PLAY RIFF off, so the notes are silent but the CC carries the riff.
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 127, low: 0, travel: .step), riffRanks: [1, 8, 1, 8, 1, 8, 1, 8], playRiffOff: true))
        rig.run(to: 8.0)
        let vals = Set(rig.out.values(cable: 1, cc: 74))
        XCTAssertTrue(vals.contains(0) && vals.contains(127), "RIFF maps rank 1→0 and rank 8→127 even with PLAY RIFF off: \(vals)")
        XCTAssertTrue(vals.allSatisfy { $0 == 0 || $0 == 127 }, "STEP holds, so only the two hit values appear: \(vals)")
    }
    func testAMutedOutputSendsTheMuteValueOnce() {
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .pingPong, high: 90, low: 90, travel: .step, muteValue: 7), muteA: true))
        rig.run(to: 6.0)
        let vals = rig.out.values(cable: 1, cc: 74)
        XCTAssertEqual(vals, [7], "a muted output sends muteValue exactly once, then nothing")
    }
    func testCCOffSendsNothing() {
        let rig = CCRig(state(cc: EmitterCC.legacy(on: false, ccNumber: 74)))
        rig.run(to: 6.0)
        XCTAssertTrue(rig.out.cc.isEmpty, "an off emitter sends no CC")
    }
    func testTurningAnEmitterOffParksItsCCAtTheMuteValueOnceThenSilent() {
        // The leak Paul reported: turning an emitter OFF left the CC stuck at its last value on the synth. It must park at muteValue once, then send nothing.
        var st = state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .pingPong, high: 90, low: 90, travel: .step, muteValue: 7))
        let rig = CCRig(st)
        rig.run(to: 4.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [90], "CC flows while the emitter is on")
        st.euclideousEmitterCCs![0].on = false      // the CC tab's emitter toggle, republished
        rig.box = SnapshotBuilder.build(from: st)
        rig.run(to: 8.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [90, 7], "off-edge parks the CC at muteValue (7) exactly once, then silent")
        XCTAssertEqual(rig.out.values(cable: 0, cc: 74), [90, 7], "and on ALL (cable 0) too")
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

    func testAnEmitterWithOneLaneOnlyStillUsesItsOwnGap() {
        // With nothing else routed to A the merged gap is the lane's own 4 beats: at beat 2 the FALL is half way (≈50).
        let rig = CCRig(twoLaneState(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 100, low: 0, travel: .fall, time: 100), ranks: [8, 8, 8, 8, 8, 8, 8, 8],
                                     lane2: { $0.riffOutMask = 0b0010; $0.notesOutMask = 0b0010 }))   // lane 2 → B again
        rig.run(to: 2.0)
        let beforeBeat2 = rig.out.timeline(cable: 1, cc: 74).filter { Double($0.sample) < 2.0 * beatSamples - 1 }
        let last = beforeBeat2.last?.value ?? -1
        XCTAssertTrue((46...52).contains(last), "own gap of 4 beats ⇒ about half way at beat 2: \(last)")
    }
    func testAnEarlierHitHeldByALaterLaneIsNotSentOutOfOrder() {
        // One 2.5-beat window. Lane 1 (processed first) hits at beat 2, lane 2 at beat 0, both on A, FIXED-by-rank values 18 and 0. Lane 2's beat-0 hit is superseded in time by lane 1's beat-2 hit, so the messages stay in time order and the emitter ends on 18.
        let rig = CCRig(twoLaneState(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 127, low: 0, travel: .step), ranks: [1, 8, 2, 2, 2, 2, 2, 2],
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
            ("ping-pong fall", EmitterCC.legacy(on: true, mode: .pingPong, high: 90, low: 10, travel: .fall, time: 80)),
            ("ramp glide", EmitterCC.legacy(on: true, mode: .climb, high: 100, low: 5, travel: .glide, time: 100, passes: 1)), ("ramp 3 passes step", EmitterCC.legacy(on: true, mode: .climb, high: 100, low: 5, travel: .step, passes: 3)),
            ("riff step", EmitterCC.legacy(on: true, mode: .riff, travel: .step)), ("riff glide", EmitterCC.legacy(on: true, mode: .riff, travel: .glide, time: 100)),
            ("riff fall", EmitterCC.legacy(on: true, mode: .riff, travel: .fall, time: 60)),
            ("ping-pong step", EmitterCC.legacy(on: true, mode: .pingPong, high: 120, low: 10, travel: .step)), ("ping-pong glide", EmitterCC.legacy(on: true, mode: .pingPong, high: 120, low: 10, travel: .glide, time: 100)),
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
            let c = EmitterCC.legacy(on: true, ccNumber: 74, mode: mode, high: 127, low: 0, travel: travel, time: time)
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

    // MARK: PING-PONG (2026-11-09) — LOW on the lane's first hit and every even one after it, HIGH on the odd ones
    func testPingPongValueRuleAndDecode() {
        var c = EmitterCCCfg(EmitterCC.legacy(mode: .pingPong, high: 120, low: 10))
        XCTAssertEqual(c.value(rank: 3, ordinal: 0), 10, "the FIRST hit (ordinal 0) is LOW"); XCTAssertEqual(c.value(rank: 3, ordinal: 1), 120, "the second is HIGH")
        XCTAssertEqual(c.value(rank: 0, ordinal: 2), 10, "a riff rest still sends: the rank is not read"); XCTAssertEqual(c.value(rank: 8, ordinal: 7), 120)
        XCTAssertEqual(c.value(rank: 1, ordinal: -1), 120, "parity holds for a negative ordinal too")
        c = EmitterCCCfg(EmitterCC.legacy(mode: .pingPong, high: 5, low: 100))
        XCTAssertEqual(c.value(rank: 1, ordinal: 0), 100, "LOW above HIGH is not swapped or clamped: the first hit is still LOW (100) — that is how to start on the high note"); XCTAssertEqual(c.value(rank: 1, ordinal: 1), 5)
        XCTAssertEqual(EmitterCCCfg(EmitterCC.legacy(mode: .pingPong, high: 33, low: 33)).value(rank: 0, ordinal: 1), 33); XCTAssertNil(EmitterCCCfg(EmitterCC.legacy(mode: .riff)).value(rank: 0, ordinal: 0))
        var set = EmitterCCSet(); set[2] = EmitterCC.legacy(on: true, ccNumber: 20, mode: .pingPong, high: 90, low: 30, travel: .glide)
        let data = try! JSONEncoder().encode(set)
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCCSet.self, from: data), set, "PING-PONG round-trips")
        let junk = #"{"valueMode":"TRIANGLE"}"#.data(using: .utf8)!
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCC.self, from: junk).valueMode, .hits, "an unknown value mode decodes as the default, HITS")
    }
    func testPingPongStartsOnLowThenHighThenLowOnEveryHit() {
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .pingPong, high: 120, low: 10, travel: .step), riffRanks: [1, 8, 3, 6, 1, 8, 3, 6]))
        rig.run(to: 5.5)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertEqual(tl.map { $0.value }, [10, 120, 10, 120, 10, 120], "a hit a beat: LOW, HIGH, LOW… whatever the riff ranks are")
        for (i, e) in tl.enumerated() { XCTAssertEqual(Double(e.sample), Double(i) * beatSamples, accuracy: 2, "each on its own hit") }
    }
    func testPingPongGlideIsATriangleStartingOnLow() {
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .pingPong, high: 120, low: 0, travel: .glide, time: 100)))
        rig.run(to: 3.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        func at(_ beat: Double) -> Int { tl.last(where: { Double($0.sample) <= beat * beatSamples })?.value ?? -1 }
        XCTAssertEqual(at(0.0), 0, "the first hit is LOW"); XCTAssertEqual(at(0.5), 60, "half way up the ramp to HIGH"); XCTAssertEqual(at(1.0), 120, "arrives on the second hit")
        XCTAssertEqual(at(1.5), 60, "and back down"); XCTAssertEqual(at(2.0), 0)
    }
    func testThePingPongTraceFollowsTheRouterAcrossAnOddBarSeam() {
        let steps = euclideousLapHitSteps(pulses: 3, steps: 4, rotate: 0, tilt: 0, patternMiss: false, customHits: nil)
        XCTAssertEqual(steps.count, 3)
        for (name, travel, tol) in [("step", EmitterCCTravel.step, 0), ("glide", .glide, 6), ("fall", .fall, 6)] {
            let c = EmitterCC.legacy(on: true, ccNumber: 74, mode: .pingPong, high: 120, low: 0, travel: travel, time: 100)
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


    // MARK: RIFF spans the riff's own range (2026-11-09) — "the CC value that's output only goes up to 50 %"
    /// The factory riff is 1 2 3 5 4 3 2 1: its highest note is rank 5, so a rank-over-1…8 map peaked at 73 (57 % of HIGH) and could never reach it. The output must now run LOW (the riff's lowest note) to HIGH (its highest).
    func testTheFactoryRiffReachesHighAndLowOnTheWire() {
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 127, low: 0, travel: .step), riffRanks: [1, 2, 3, 5, 4, 3, 2, 1]))
        rig.run(to: 8.0)
        let vals = rig.out.values(cable: 1, cc: 74).map { Int($0) }
        XCTAssertEqual(vals.max(), 127, "the riff's highest note is HIGH: \(vals)"); XCTAssertEqual(vals.min(), 0, "its lowest is LOW")
        XCTAssertEqual(Set(vals), Set([1, 2, 3, 5, 4].map { Int((Double($0 - 1) / 4.0 * 127).rounded()) }), "rank 1 2 3 4 5 → 0 32 64 95 127: \(Set(vals))")
        // a narrower window and an inverted one scale the same way
        let narrow = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 100, low: 40, travel: .step), riffRanks: [3, 4, 3, 4, 3, 4, 3, 4]))
        narrow.run(to: 6.0)
        XCTAssertEqual(Set(narrow.out.values(cable: 1, cc: 74).map { Int($0) }), [40, 100], "a riff of two notes spans the whole window")
        let inv = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 0, low: 127, travel: .step), riffRanks: [2, 6, 2, 6, 2, 6, 2, 6]))
        inv.run(to: 6.0)
        XCTAssertEqual(Set(inv.out.values(cable: 1, cc: 74).map { Int($0) }), [127, 0], "LOW above HIGH still inverts: the lowest note is LOW (127)")
        // a riff with ONE distinct note has no range to span: it keeps the literal rank map (rank 3 → 2/7 of the way)
        let one = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 127, low: 0, travel: .step), riffRanks: [3, 3, 3, 3, 3, 3, 3, 3]))
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
        let c = EmitterCCCfg(EmitterCC.legacy(mode: .riff, high: 127, low: 0))
        let span = EmitterCCRiffSpan(lo: 1, hi: 5)
        XCTAssertEqual([1, 2, 3, 4, 5].map { c.riffValue(rank: $0, span: span) }, [0, 32, 64, 95, 127])
        XCTAssertEqual(c.riffValue(rank: 8), 127, "the literal map is still there for rank 8"); XCTAssertEqual(c.value(rank: 5, ordinal: 0, span: span), 127)
        XCTAssertEqual(c.riffValue(rank: 3, span: EmitterCCRiffSpan(lo: 3, hi: 3)), Int((2.0 / 7.0 * 127).rounded()), "one distinct note: its literal height")
        XCTAssertEqual(EmitterCCCfg(EmitterCC.legacy(mode: .pingPong, high: 99, low: 99)).value(rank: 1, ordinal: 0, span: span), 99, "FIXED ignores the span")
    }
    func testTheTraceUsesTheSameSpanTheRouterDoes() {
        let ranks = [1, 2, 3, 5, 1, 2, 3, 5]   // four hits a bar, the riff spanning ranks 1…5
        for (name, travel) in [("step", EmitterCCTravel.step), ("glide", .glide), ("fall", .fall)] {
            let c = EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 127, low: 0, travel: travel, time: 100)
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
        let tl = replanRig(EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 127, low: 0, travel: .glide, time: 100), EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 60, low: 0, travel: .glide, time: 100), swapAt: 2.5, to: 3.0)
        let after = tl.filter { Double($0.sample) >= 2.5 * beatSamples }
        XCTAssertFalse(after.isEmpty)
        XCTAssertLessThanOrEqual(after.map { $0.value }.max() ?? 999, 61, "the ramp heads for the NEW high: \(after.map { $0.value })")
        let at275 = tl.last(where: { Double($0.sample) <= 2.75 * beatSamples })?.value ?? -1
        XCTAssertEqual(at275, 45, accuracy: 3, "¾ of the way up the ramp 0 → 60 at beat 2.75")
    }
    func testAHeldValueFollowsANewLevelAtOnceNotAtTheNextHit() {
        let tl = replanRig(EmitterCC.legacy(on: true, ccNumber: 74, mode: .pingPong, high: 90, low: 90, travel: .step), EmitterCC.legacy(on: true, ccNumber: 74, mode: .pingPong, high: 40, low: 40, travel: .step), swapAt: 2.5, to: 2.9)
        XCTAssertEqual(tl.map { $0.value }, [90, 40], "the new value goes out within a window of the change, before the beat-3 hit")
        let t40 = tl.first(where: { $0.value == 40 })?.sample ?? 0
        XCTAssertLessThan(Double(t40), 2.6 * beatSamples, "…not at the next hit")
    }
    func testAFallFollowsANewLowAtOnce() {
        let tl = replanRig(EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 100, low: 0, travel: .fall, time: 100), EmitterCC.legacy(on: true, ccNumber: 74, mode: .riff, high: 100, low: 60, travel: .fall, time: 100), swapAt: 0.5, to: 0.95, ranks: [8, 8, 8, 8, 8, 8, 8, 8])
        let after = tl.filter { Double($0.sample) >= 0.5 * beatSamples }
        XCTAssertGreaterThanOrEqual(after.map { $0.value }.min() ?? 0, 59, "the fall now bottoms out at the new LOW (60), not 0: \(after.map { $0.value })")
    }

    // MARK: removed controls (2026-11-09) — an old document loses them and still loads
    func testARemovedModeOrControlIsDroppedWithoutMigration() {
        func decode(_ json: String) -> EmitterCC { try! JSONDecoder().decode(EmitterCC.self, from: json.data(using: .utf8)!) }
        let old = decode(#"{"on":true,"valueMode":"FIXED","level":64,"high":10,"low":20,"travel":"GLIDE","time":80,"sineBars":5}"#)
        XCTAssertEqual(old.valueMode, .hits, "FIXED is gone (HITS replaced it): it decodes as the default"); XCTAssertTrue(old.on); XCTAssertEqual(old.high, 10); XCTAssertEqual(old.low, 20)
        XCTAssertEqual(old.hold, 25); XCTAssertEqual(old.ramp, 50); XCTAssertEqual(old.to, .rest); XCTAssertEqual(old.curve, .exp, "travel and time are dropped: the new shape starts from its defaults")
        XCTAssertEqual(decode(#"{"valueMode":"SINE"}"#).valueMode, .hits); XCTAssertEqual(decode(#"{"valueMode":"TRIANGLE"}"#).valueMode, .hits)
        XCTAssertEqual(decode(#"{"valueMode":"RAMP","passes":4}"#).valueMode, .climb, "the first day's name for CLIMB still loads"); XCTAssertEqual(decode(#"{"valueMode":"RIFF"}"#).valueMode, .riff)
        XCTAssertEqual(EmitterCCValueMode.allCases, [.hits, .riff, .pingPong, .climb])
        let data = String(data: try! JSONEncoder().encode(old), encoding: .utf8)!
        XCTAssertFalse(data.contains("level") || data.contains("travel") || data.contains("\"time\"") || data.contains("sineBars"), "the removed fields are never written again: \(data)")
        XCTAssertEqual(decode(#"{"hold":900,"ramp":-4,"to":"NEXT","curve":"LIN"}"#), EmitterCC(hold: 100, ramp: 0, to: .next, curve: .lin), "hold / ramp clamp; to and curve decode")
        XCTAssertEqual(decode(#"{"to":"SIDEWAYS","curve":"WOBBLY"}"#).to, .rest); XCTAssertEqual(decode(#"{"to":"SIDEWAYS","curve":"WOBBLY"}"#).curve, .exp)
    }

    // MARK: RAMP (2026-11-09) — LOW on a lane's first hit climbing evenly to HIGH on the last hit of the span (one pass, or `passes` of them)
    func testRampValueRuleAndDecode() {
        let c = EmitterCCCfg(EmitterCC.legacy(mode: .climb, high: 120, low: 0, passes: 1))
        XCTAssertEqual((0..<4).map { c.value(rank: 0, ordinal: Int64($0), passHits: 4) }, [0, 40, 80, 120], "4 hits a pass: LOW, ⅓, ⅔, HIGH — the rank (rests included) is not read")
        XCTAssertEqual(c.value(rank: 3, ordinal: 4, passHits: 4), 0, "the next span starts again at LOW"); XCTAssertEqual(c.value(rank: 3, ordinal: -1, passHits: 4), 120, "a negative ordinal wraps the same way")
        XCTAssertEqual(c.value(rank: 3, ordinal: 5, passHits: 1), 0, "a one-hit span is just LOW"); XCTAssertEqual(c.value(rank: 3, ordinal: 0, passHits: 0), 0, "a lane with no hits still answers")
        let two = EmitterCCCfg(EmitterCC.legacy(mode: .climb, high: 120, low: 0, passes: 2))
        XCTAssertEqual((0..<8).map { two.value(rank: 0, ordinal: Int64($0), passHits: 4) }, [0, 17, 34, 51, 69, 86, 103, 120], "two passes: one climb across all 8 hits, HIGH on the last hit of the 2nd pass")
        let inv = EmitterCCCfg(EmitterCC.legacy(mode: .climb, high: 0, low: 100, passes: 1))
        XCTAssertEqual([0, 3].map { inv.value(rank: 0, ordinal: Int64($0), passHits: 4) }, [100, 0], "LOW above HIGH inverts: it descends")
        // PASSES: default 1, clamps 1…16, round-trips, and an old document with no passes loads as 1
        func decode(_ json: String) -> EmitterCC { try! JSONDecoder().decode(EmitterCC.self, from: json.data(using: .utf8)!) }
        XCTAssertEqual(decode(#"{"valueMode":"CLIMB"}"#).passes, 1); XCTAssertEqual(decode(#"{"valueMode":"CLIMB"}"#).valueMode, .climb)
        XCTAssertEqual(decode(#"{"passes":99}"#).passes, 16); XCTAssertEqual(decode(#"{"passes":-3}"#).passes, 1)
        var set = EmitterCCSet(); set[3] = EmitterCC.legacy(on: true, ccNumber: 20, mode: .climb, high: 90, low: 30, travel: .glide, passes: 5)
        XCTAssertEqual(try! JSONDecoder().decode(EmitterCCSet.self, from: try! JSONEncoder().encode(set)), set, "RAMP and PASSES round-trip")
    }
    func testARampOnTheWireClimbsLowToHighOverOnePassAndStartsAgain() {
        // 4 hits a pass (a hit a beat): 0, 40, 80, 120 then 0 again
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .climb, high: 120, low: 0, travel: .step, passes: 1)))
        rig.run(to: 8.5)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74).map { Int($0) }, [0, 40, 80, 120, 0, 40, 80, 120, 0], "LOW → HIGH across each pass, then it starts again")
    }
    func testARampOverSeveralPassesIsOneClimbAcrossAllOfThem() {
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .climb, high: 120, low: 0, travel: .step, passes: 2)))
        rig.run(to: 8.5)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74).map { Int($0) }, [0, 17, 34, 51, 69, 86, 103, 120, 0], "one climb over two passes: HIGH lands on the last hit of the second pass")
    }
    func testAGlideRampHeadsForTheNextHitsRungAndDropsBackAtTheEndOfTheSpan() {
        let rig = CCRig(state(cc: EmitterCC.legacy(on: true, ccNumber: 74, mode: .climb, high: 120, low: 0, travel: .glide, time: 100, passes: 1)))
        rig.run(to: 5.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        func at(_ beat: Double) -> Int { tl.last(where: { Double($0.sample) <= beat * beatSamples })?.value ?? -1 }
        XCTAssertEqual(at(0.5), 20, accuracy: 2, "half way from LOW up to the second rung (40)"); XCTAssertEqual(at(1.0), 40, accuracy: 1)
        XCTAssertEqual(at(2.0), 80, accuracy: 1); XCTAssertEqual(at(3.0), 120, accuracy: 1, "HIGH on the last hit")
        XCTAssertEqual(at(3.5), 60, accuracy: 3, "then it glides back down toward the next span's first hit (LOW)")
    }
    func testChangingPassesReplansTheRunningRampAtOnce() {
        let before = EmitterCC.legacy(on: true, ccNumber: 74, mode: .climb, high: 120, low: 0, travel: .step, passes: 1)
        var after = before; after.passes = 2
        let tl = replanRig(before, after, swapAt: 1.5, to: 1.9)   // the beat-1 hit sent rung 2 of 4 (40); with two passes it is rung 2 of 8 (17)
        XCTAssertEqual(tl.map { $0.value }, [0, 40, 17], "the new span takes over within a window, before the beat-2 hit")
        XCTAssertLessThan(Double(tl.last?.sample ?? 0), 1.6 * beatSamples)
    }
    func testTheRampTraceFollowsTheRouterOverSeveralPasses() {
        for passes in [1, 3] {
            for (name, travel, tol) in [("step", EmitterCCTravel.step, 0), ("glide", .glide, 6), ("fall", .fall, 6)] {
                let c = EmitterCC.legacy(on: true, ccNumber: 74, mode: .climb, high: 120, low: 0, travel: travel, time: 100, passes: passes)
                let rig = CCRig(state(cc: c))   // a hit a beat, 4 hits a pass
                rig.run(to: 8.0)
                let sent = rig.out.timeline(cable: 1, cc: 74)
                let trace = emitterCCTrace(cfg: EmitterCCCfg(c), hits: (0..<4).map { EmitterCCTraceHit(beat: Double($0), rank: 1, lane: 0, ordinal: Int64(4 + $0), passHits: 4) }, barBeats: 4)   // the second bar: ordinals 4…7
                var worst = 0
                for i in 1..<96 where i % 24 != 0 {
                    let b = Double(i) / 24, sample = Int64(((4.0 + b) * beatSamples).rounded())
                    guard let engine = sent.last(where: { $0.sample <= sample })?.value, let drawn = trace.points.first(where: { abs(Double($0.x) - b) < 1e-6 }).map({ Int($0.y) }) else { continue }
                    worst = max(worst, abs(engine - drawn))
                }
                XCTAssertLessThanOrEqual(worst, tol, "passes \(passes) \(name): the drawn bar and the CC stream differ by \(worst)")
            }
        }
    }

    // MARK: amendment 1 (2026-11-09) — HITS, the merged hit stream, and the hold-then-ramp shape
    private func hitsEmitter(hold: Int = 100, ramp: Int = 0, to: EmitterCCTo = .rest, curve: EmitterCCCurve = .lin, high: Int = 127, low: Int = 0, mode: EmitterCCValueMode = .hits, muteValue: Int = 0) -> EmitterCC {
        EmitterCC(on: true, ccNumber: 74, valueMode: mode, high: high, low: low, hold: hold, ramp: ramp, to: to, curve: curve, muteValue: muteValue)
    }
    private func at(_ tl: [(sample: Int64, value: Int)], _ beat: Double) -> Int { tl.last(where: { Double($0.sample) <= beat * beatSamples + 1 })?.value ?? -1 }

    func testHitsWithOneRoutedLaneIsHighOnEveryHit() {
        let rig = CCRig(state(cc: hitsEmitter(high: 100, low: 20)))   // lane 1 alone is routed to A (the others are stopped), hits every beat
        rig.run(to: 4.5)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [100], "one routed lane: every hit is HIGH (and a repeated value is not re-sent)")
    }
    func testAStoppedLaneIsNotRouted() {
        let rig = CCRig(twoLaneState(cc: hitsEmitter(), lane1: { _ in }, lane2: { $0.enabled = false }))
        rig.run(to: 4.5)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [127], "lane 2 is stopped, so lane 1 alone is routed: every hit is HIGH, not half")
    }
    func testWhenLanesHitTogetherTheFirstInLaneOrderIsReadForRiff() {
        // both lanes hit at beat 0; lane 1 reads riff column 0 (rank 1), lane 2 column 4 (rank 8): the event is lane 1's — LOW — and lane 2's hit adds nothing
        let ranks = [1, 1, 1, 1, 8, 8, 8, 8]
        let rig = CCRig(twoLaneState(cc: hitsEmitter(mode: .riff), ranks: ranks, lane2: { $0.rotate = 0; $0.riffRotate = 4 }))
        rig.run(to: 1.5)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [0], "the first hitting lane in lane order (lane 1, rank 1 → LOW) is read; lane 2's rank 8 is not")
    }
    func testTheReferenceShapes() {
        func run(_ cc: EmitterCC, to end: Double = 3.2) -> [(sample: Int64, value: Int)] { let rig = CCRig(state(cc: cc)); rig.run(to: end); return rig.out.timeline(cable: 1, cc: 74) }
        // Gate: HOLD 50, RAMP 0, REST — HIGH for half the gap, then straight to LOW
        let gate = run(hitsEmitter(hold: 50, ramp: 0))
        XCTAssertEqual(at(gate, 0.0), 127); XCTAssertEqual(at(gate, 0.49), 127); XCTAssertEqual(at(gate, 0.5), 0, "a RAMP of 0 jumps to the target at the end of the hold"); XCTAssertEqual(at(gate, 0.99), 0); XCTAssertEqual(at(gate, 1.0), 127)
        // Pluck: HOLD 0, RAMP 20, EXP — fast decay from HIGH to LOW over a fifth of the gap, then sits at LOW
        let pluck = run(hitsEmitter(hold: 0, ramp: 20, curve: .exp))
        XCTAssertEqual(at(pluck, 0.0), 127); XCTAssertEqual(Double(at(pluck, 0.1)), 127 * (1 - emitterCCShape((1.0 / 12) / 0.2, curve: .exp)), accuracy: 3, "the last message at or before beat 0.1 is the 1/96-note step at 0.083: 42 % along the 0.2-beat EXP ramp it has done 83 % of the fall"); XCTAssertEqual(at(pluck, 0.25), 0); XCTAssertEqual(at(pluck, 0.9), 0)
        // Stab with a tail: HOLD 25, RAMP 50, EXP — held a quarter, falls over the middle half, sits at LOW
        let stab = run(hitsEmitter(hold: 25, ramp: 50, curve: .exp))
        XCTAssertEqual(at(stab, 0.2), 127); XCTAssertLessThan(at(stab, 0.5), 30); XCTAssertEqual(at(stab, 0.8), 0)
        // Pump: HIGH 0, LOW 127, HOLD 0, RAMP 80, LIN — ducks to 0 on every hit and swells back up to the rest value
        let pump = run(hitsEmitter(hold: 0, ramp: 80, curve: .lin, high: 0, low: 127))
        XCTAssertEqual(at(pump, 0.0), 0); XCTAssertEqual(Double(at(pump, 0.4)), 63.5, accuracy: 4, "linear, half way through the 80 % ramp"); XCTAssertEqual(at(pump, 0.9), 127); XCTAssertEqual(at(pump, 1.0), 0)
        // Riff steps: RIFF, HOLD 100 — each hit's value stays until the next
        let steps = run(hitsEmitter(mode: .riff), to: 2.5)
        XCTAssertEqual(steps.map { $0.value }, [0], "a riff of rank 1 on every hit: one value, held")
    }
    func testTheRampOnlyUsesWhatTheHoldLeaves() {
        // HOLD 75, RAMP 50 → the effective ramp is 25 %: it plays between 75 % and 100 % of the gap
        let rig = CCRig(state(cc: hitsEmitter(hold: 75, ramp: 50, curve: .lin)))
        rig.run(to: 1.2)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertEqual(at(tl, 0.74), 127, "still holding"); XCTAssertEqual(Double(at(tl, 0.875)), 63.5, accuracy: 6, "half way down the effective ramp"); XCTAssertEqual(Double(at(tl, 0.96)), 127 * (1 - (23.0 / 24 - 0.75) / 0.25), accuracy: 4, "83 % down the effective ramp at the last 1/96-note step before the next hit")
    }
    func testTheCurvesLinAndExp() {
        XCTAssertEqual(emitterCCShape(0, curve: .lin), 0); XCTAssertEqual(emitterCCShape(1, curve: .lin), 1); XCTAssertEqual(emitterCCShape(0.25, curve: .lin), 0.25)
        XCTAssertEqual(emitterCCShape(0, curve: .exp), 0, accuracy: 1e-12); XCTAssertEqual(emitterCCShape(1, curve: .exp), 1, accuracy: 1e-12)
        XCTAssertEqual(emitterCCShape(0.5, curve: .exp), (1 - exp(-2.0)) / (1 - exp(-4.0)), accuracy: 1e-12, "(1 − e^(−4f)) / (1 − e^(−4))"); XCTAssertGreaterThan(emitterCCShape(0.5, curve: .exp), 0.85, "EXP starts fast")
        XCTAssertEqual(emitterCCShape(-1, curve: .exp), 0, accuracy: 1e-12); XCTAssertEqual(emitterCCShape(7, curve: .lin), 1)
    }
    func testChangingHoldReplansTheRunningShapeAtOnce() {
        // a hit a beat, HOLD 100 (steps, HIGH 127); at beat 1.5 HOLD is dragged to 0 with RAMP 100 → it starts falling at once (the beat-1 hit's shape is re-planned), instead of staying up until the beat-2 hit
        let rig = CCRig(state(cc: hitsEmitter(hold: 100)))
        rig.run(to: 1.5)
        rig.box = SnapshotBuilder.build(from: state(cc: hitsEmitter(hold: 0, ramp: 100, curve: .lin)))
        rig.run(to: 1.9)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertLessThan(at(tl, 1.9), 40, "falling along the new shape: \(tl.map { $0.value })"); XCTAssertEqual(at(tl, 1.4), 127)
    }
    func testTheTraceFollowsTheRouterForTheReferenceShapes() {
        let shapes: [(String, EmitterCC)] = [
            ("gate", hitsEmitter(hold: 50, ramp: 0)), ("pluck", hitsEmitter(hold: 0, ramp: 20, curve: .exp)), ("stab", hitsEmitter(hold: 25, ramp: 50, curve: .exp)),
            ("pump", hitsEmitter(hold: 0, ramp: 80, curve: .lin, high: 0, low: 127)), ("effective ramp", hitsEmitter(hold: 75, ramp: 50, curve: .exp)), ("riff glide", hitsEmitter(hold: 50, ramp: 50, to: .next, curve: .lin, mode: .riff)),
        ]
        let ranks = [1, 8, 3, 6, 1, 8, 3, 6]
        for (name, cc) in shapes {
            let rig = CCRig(state(cc: cc, riffRanks: ranks))
            rig.run(to: 8.0)
            let sent = rig.out.timeline(cable: 1, cc: 74)
            let hits = [(0.0, 1), (1.0, 8), (2.0, 3), (3.0, 6)].enumerated().map { EmitterCCTraceHit(beat: $0.element.0, rank: $0.element.1, lane: 0, ordinal: Int64(4 + $0.offset), passHits: 4, barHits: 4, count: 1, routed: 1) }
            let trace = emitterCCTrace(cfg: EmitterCCCfg(cc), hits: hits, barBeats: 4, span: emitterCCRiffSpan(ranks: ranks, count: 8))
            var worst = 0
            for i in 1..<96 where i % 24 != 0 {
                let b = Double(i) / 24, sample = Int64(((4.0 + b) * beatSamples).rounded())
                guard let engine = sent.last(where: { $0.sample <= sample })?.value, let drawn = trace.points.first(where: { abs(Double($0.x) - b) < 1e-6 }).map({ Int($0.y) }) else { continue }
                worst = max(worst, abs(engine - drawn))
            }
            XCTAssertLessThanOrEqual(worst, name == "gate" ? 0 : 8, "\(name): the drawn bar and the CC stream differ by \(worst)")
        }
    }
    func testHoldHundredKeepsTheValueThroughARiffRest() {
        // ranks 8, rest, 8, rest…: every second hit is a RIFF rest, which brings no new value — with HOLD 100 (steps) the previous value stays; it does not fall to LOW when the gap ends
        let rig = CCRig(state(cc: hitsEmitter(mode: .riff), riffRanks: [8, 0, 8, 0, 8, 0, 8, 0]))
        rig.run(to: 4.5)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [127], "one value, held through the rests")
    }

    // MARK: CC SLOTS (2026-11-12) — a slot follows its DRIVER lane's hits + riff, whatever its routing / PLAY
    /// Test 4 (§3.1): output A slot a driven by LANE 2 (driverLane 2, HITS). Lane 2 is routed to B (not A) and has PLAY RIFF + STACK off; it still drives A's CC on lane 2's own hit (beat 2), HIGH. Lane 1's beat-0 hit does NOT fire it.
    func testASlotFollowsItsDriverLaneUnroutedAndPlayOff() {
        let cc = EmitterCC(on: true, ccNumber: 74, valueMode: .hits, high: 127, low: 0, hold: 100, driverLane: 2)
        let rig = CCRig(twoLaneState(cc: cc, lane2: { $0.riffOutMask = 0b0010; $0.notesOutMask = 0b0010; $0.riffOn = false; $0.notesOn = false }))
        rig.run(to: 4.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertFalse(tl.contains { Double($0.sample) < beatSamples * 0.5 }, "no CC at beat 0 (lane 1's hit — not the driver): \(tl)")
        XCTAssertTrue(tl.contains { abs(Double($0.sample) - 2 * beatSamples) < 2 && $0.value == 127 }, "lane 2's beat-2 hit fires HIGH: \(tl)")
    }
    /// Test 5 (§3.3): RIFF reads the DRIVER lane's riff column, even with PLAY RIFF off. Lane 2 sits on a rank-8 column at its hit ⇒ the full value (the riff's own span).
    func testRiffReadsTheDriverLanesColumn() {
        let cc = EmitterCC(on: true, ccNumber: 74, valueMode: .riff, high: 127, low: 0, hold: 100, driverLane: 2)
        let rig = CCRig(twoLaneState(cc: cc, ranks: [1, 1, 8, 1, 1, 1, 1, 1], lane2: { $0.riffOutMask = 0b0010; $0.notesOutMask = 0b0010; $0.riffOn = false }))
        rig.run(to: 4.0)
        let tl = rig.out.timeline(cable: 1, cc: 74)
        XCTAssertTrue(tl.contains { abs(Double($0.sample) - 2 * beatSamples) < 2 && $0.value == 127 }, "driver lane 2's rank-8 column at beat 2 ⇒ HIGH: \(tl)")
    }
    /// §3.6: a FULLY-muted output (all cells clear) sends muteValue once; a PARTIAL MUTE-tab pattern does NOT gate CC (every hit still fires).
    func testPartialMuteDoesNotGateCCFullMuteSendsMuteValueOnce() {
        // partial: cells 4…7 only — the CC fires on every hit regardless (not gated by the pattern).
        var st = state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .hits, high: 90, low: 0, hold: 100, muteValue: 7))
        var mutes = EuclideousOutputMutes(); mutes[0] = EuclideousOutputMute(cells16: 0b0000_0000_1111_0000, passes: 1); st.euclideousOutputMutes = mutes
        var rig = CCRig(st)
        rig.run(to: 4.0)
        XCTAssertFalse(rig.out.values(cable: 1, cc: 74).contains(7), "a partial MUTE-tab pattern does not send muteValue")
        XCTAssertTrue(rig.out.values(cable: 1, cc: 74).contains(90), "and the CC fires on the hits")
        // full: every cell clear ⇒ muteValue once, then nothing.
        var st2 = state(cc: EmitterCC(on: true, ccNumber: 74, valueMode: .hits, high: 90, low: 0, hold: 100, muteValue: 7))
        var mutes2 = EuclideousOutputMutes(); mutes2[0] = EuclideousOutputMute(cells16: 0, passes: 1); st2.euclideousOutputMutes = mutes2
        rig = CCRig(st2)
        rig.run(to: 6.0)
        XCTAssertEqual(rig.out.values(cable: 1, cc: 74), [7], "a full output mute sends muteValue once")
    }
}

