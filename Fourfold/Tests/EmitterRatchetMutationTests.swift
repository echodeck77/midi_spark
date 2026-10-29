//  EmitterRatchetMutationTests.swift — tests written to kill the mutants the first RATCH-tab suite let through (adversarial mutation review, 2026-10-28: 94 mutants, 53 killed by the original suite, 8 equivalent, 33 gaps — all killed by this file).
//  Same fixture as EmitterRatchetRouterTests (copied: those helpers are private): one lane (lane 1 → output A, cable 1), 4 hits in 4 steps at 1/4 — one hit a beat, 24,000 samples apart at 120 BPM / 48 kHz — the riff walked FWD
//  over 8 columns (beat k reads column k mod 8) over a held pool of eight notes. Cable 0 is ALL; cables 1…4 are outputs A…D.

import XCTest

private struct MEv: Equatable { let sample: Int64; let cable: UInt8; let on: Bool; let chan: UInt8; let note: UInt8; let vel: UInt8 }
private final class MTap: MIDIEmitter {
    private(set) var events: [MEv] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0
        guard st == 0x90 || st == 0x80 else { return }
        events.append(MEv(sample: sampleTime, cable: cable, on: st == 0x90 && b2 > 0, chan: b0 & 0x0F, note: b1, vel: b2))
    }
    func ons(_ cable: UInt8) -> [MEv] { events.filter { $0.cable == cable && $0.on } }
    func offs(_ cable: UInt8) -> [MEv] { events.filter { $0.cable == cable && !$0.on } }
}

private let mPool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]

private struct MRig {
    var lines: [EuclidLine]
    var emitters = EmitterRatchetSet()
    var fx = EuclideousFX()
    var ranks = [1, 2, 3, 4, 5, 6, 7, 8]
    var transpose = 0
    func box() -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.transpose = transpose
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousFX = fx
        st.euclideousEmitterRatchets = emitters.isAllDefault ? nil : emitters
        return SnapshotBuilder.build(from: st)
    }
}
private struct MPlayed {
    let tap: MTap
    let router: Router
    let nv: [(beat: Double, lane: Int, masks: UInt8)]
    let restartSamples: [Int64]
}
private func mLine(pulses: Int = 4, steps: Int = 4, rate: ArpRate = .r1_4, gate: Double = 0.5, vel: Int = 90, litNotes: UInt8 = 0, riffOut: UInt8? = nil, notesOut: UInt8? = nil) -> EuclidLine {
    var l = EuclidLine(target: 0, pulses: pulses, steps: steps)
    l.gate = gate; l.velocityAbsolute = vel; l.rate = rate; l.useRiff = true; l.litNotes = litNotes; l.riffOn = true; l.sourceMode = .midi
    l.riffLength = 8; l.notesOn = true; l.riffOnRest = .skip
    l.riffOutMask = riffOut; l.notesOutMask = notesOut
    return l
}
private func mEmitters(_ list: [(Int, EmitterRatchet)]) -> EmitterRatchetSet {
    var s = EmitterRatchetSet()
    for (i, r) in list { s[i] = r }
    return s
}
private func mOn(steps: Int = 8, hits: Int = 3, offset: Int = 0, chance: Int = 100, strikes: Int = 3) -> EmitterRatchet {
    EmitterRatchet(on: true, steps: steps, hits: hits, offset: offset, chance: chance, strikes: strikes)
}
private func mPlay(_ rig: MRig, beats: Double, frames: UInt32 = 2048, tempo: Double = 120, restartAt: [Double] = [], swapAt: [(beat: Double, rig: MRig)] = [], pool notes: [UInt8] = mPool, repeatWindowAt: Double? = nil) -> MPlayed {
    let tap = MTap(), router = Router()
    var diag = KernelDiag(); let sr = 48_000.0
    let p = NotePool(); for n in notes { p.noteOn(n, velocity: 100, channel: 0) }
    var box = rig.box()
    var ts = 0.0, origin = 0.0
    func beatNow() -> Double { (ts - origin) * tempo / 60.0 / sr }
    var restarts = restartAt.sorted(), swaps = swapAt.sorted { $0.beat < $1.beat }
    var nv: [(beat: Double, lane: Int, masks: UInt8)] = []
    var restartSamples: [Int64] = []
    func drain() {
        let all = router.drainEuclideousNoteViewEvents()
        for (lane, evs) in all.enumerated() { for e in evs { nv.append((e.onsetBeat, lane, e.emitMasks)) } }
    }
    while beatNow() < beats {
        if let r = restarts.first, beatNow() >= r {
            restarts.removeFirst()
            router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: tap, diag: &diag)
            ts += Double(frames); origin = ts; restartSamples.append(Int64(ts))
        }
        if let s = swaps.first, beatNow() >= s.beat { swaps.removeFirst(); box = s.rig.box() }
        router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: tap, diag: &diag)
        drain()
        ts += Double(frames)
    }
    router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: tap, diag: &diag)
    drain()
    return MPlayed(tap: tap, router: router, nv: nv, restartSamples: restartSamples)
}
private func mPerBeat(_ e: MTap, cable: UInt8 = 1, beats: Int, perBeatSamples: Double = 24_000) -> [Int] {
    var c = [Int](repeating: 0, count: beats)
    for ev in e.ons(cable) { let b = Int(Double(ev.sample) / perBeatSamples + 0.001); if b >= 0 && b < beats { c[b] += 1 } }
    return c
}
/// Roll records of notes that left on NO output although every part is routed somewhere: a strike handed an empty output set (the roll would draw a silent mark for a note that has no business there).
private func mSilentRollRecords(_ r: Router) -> Int { r.rollRing.drain().filter { !$0.isEnd && $0.outs == 0 }.count }
private func mAssertNothingLeftSounding(_ e: MTap, file: StaticString = #filePath, line: UInt = #line) {
    var last: [Int: Bool] = [:]
    for ev in e.events { last[(Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)] = ev.on }
    for (key, on) in last where on { XCTFail("stuck note: key \(key) last event was ON, not OFF", file: file, line: line) }
}

final class EmitterRatchetMutationTests: XCTestCase {

    // MARK: - the roll is a stored, replayable value

    /// A saved session must ratchet the same hits when it is opened by a later build: pin the first rolls of each output, not only "roll < CHANCE reproduces itself".
    /// Kills: the roll's modulus (% 99), the output term, the salt (the salt is pinned elsewhere, but only as a literal).
    func testTheRollIsPinnedToGoldenValues() {
        // computed independently (a stand-alone splitmix64 script over the documented seed: salt ^ (output + 1) × 0x9E3779B97F4A7C15 ^ v)
        let golden: [[Int]] = [[51, 46, 81, 62, 75, 5, 15, 60, 58, 98, 86, 22],
                               [6, 92, 6, 17, 12, 10, 76, 38, 63, 89, 16, 5],
                               [13, 11, 89, 23, 39, 97, 83, 19, 95, 89, 63, 78],
                               [5, 90, 14, 98, 61, 53, 20, 51, 19, 69, 70, 39]]
        for output in 0..<4 { XCTAssertEqual((0..<12).map { emitterRatchetRoll(output: output, v: Int64($0)) }, golden[output], "output \(output)") }
        XCTAssertEqual(emitterRatchetRoll(output: 2, v: 1_000_003), 52)
        // the distribution reaches both ends of 0…99 (a % 99 would never produce 99)
        XCTAssertTrue((0..<4000).contains { emitterRatchetRoll(output: 1, v: Int64($0)) == 99 }, "99 is reachable")
        XCTAssertTrue((0..<4000).contains { emitterRatchetRoll(output: 1, v: Int64($0)) == 0 }, "0 is reachable")
    }

    // MARK: - §2.1 the count never depends on the switch

    /// While X is OFF its hits still count, so switching it ON at beat 5.5 lands on count 6 (index 2 of a 4-step pattern marking index 0): beat 6 and 7 play once, beat 8 (count 8) ratchets.
    /// Kills: "don't increment while OFF".
    func testAnOffEmitterStillCountsSoSwitchingItOnPicksUpTheRunningCount() {
        let off = MRig(lines: [mLine()], emitters: mEmitters([(0, EmitterRatchet(on: false, steps: 4, hits: 1, strikes: 3))]))
        let live = MRig(lines: [mLine()], emitters: mEmitters([(0, mOn(steps: 4, hits: 1, strikes: 3))]))
        let e = mPlay(off, beats: 12, swapAt: [(5.5, live)])
        mAssertNothingLeftSounding(e.tap)
        XCTAssertEqual(mPerBeat(e.tap, beats: 12), [1, 1, 1, 1, 1, 1, 1, 1, 3, 1, 1, 1], "hits 0…5 were counted while OFF: the first ratchet after the switch is hit 8, not hit 6")
    }

    // MARK: - §2 a hit that sends nothing is not an emitter hit

    /// Pitches the pool can only reach out of MIDI range (riff octave +1 over notes 120 and 126) send nothing: they must not advance the count.
    /// Kills: dropping the `finalPitch != nil` filter of the hook.
    func testAHitWhoseEveryPitchFallsOutsideMidiRangeDoesNotCount() {
        var lane = mLine(); lane.riffOctave = 1
        let pool: [UInt8] = [60, 70, 80, 90, 100, 110, 120, 126]
        let beats = 16
        let e = mPlay(MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 4, hits: 1, strikes: 3))])), beats: Double(beats), pool: pool)
        mAssertNothingLeftSounding(e.tap)
        var counted = 0
        var want = [Int](repeating: 0, count: beats)
        for b in 0..<beats where b % 8 < 6 { want[b] = counted % 4 == 0 ? 3 : 1; counted += 1 }   // columns 6 and 7 read the notes 120 / 126 → 132 / 138: silent
        XCTAssertEqual(mPerBeat(e.tap, beats: beats), want)
    }

    // MARK: - §3.3 / §3.5 the other outputs and ROLL / RUN

    /// The notes layer PLAYS AS ROLL / RUN: on an output whose ratchet fires the notes strike together, n times each (§3.5); no ordinary roll strike is left behind on that output.
    /// Kills: using `outsOf` instead of `outsStrike` in any of the ROLL / RUN strikes, and dropping the `strikesPlain` guard of that loop.
    func testRollAndRunNotesStrikeTogetherNTimesOnARatchetingOutput() {
        for playAs in [EuclidNotesPlayAs.roll, .run] {
            var lane = mLine(gate: 0.9, litNotes: 0b0000_0111, riffOut: 0b0010, notesOut: 0b0011)   // the lit notes on A AND B; the riff note on B
            lane.notesPlayAs = playAs; lane.notesWhen = 0b11; lane.notesGate = 0.9
            let rig = MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 2))]), ranks: [8, 8, 8, 8, 8, 8, 8, 8])   // the riff plays the top note, which no lit note shares
            for frames: UInt32 in [2048, 30_000] {
            let e = mPlay(rig, beats: 4, frames: frames)
            mAssertNothingLeftSounding(e.tap)
            let plain = mPlay(MRig(lines: [lane], ranks: [8, 8, 8, 8, 8, 8, 8, 8]), beats: 4, frames: frames)
            // without the ratchet the notes are rolled / run across the step (more than one distinct onset per beat on A)
            let plainOnsets = Set(plain.tap.ons(1).filter { $0.sample < 24_000 }.map { $0.sample })
            XCTAssertGreaterThan(plainOnsets.count, 1, "\(playAs): the fixture rolls without the ratchet")
            // with it: each of the three lit notes is struck exactly twice a beat on A, all together at the hit and half a step later
            for b in 0..<4 {
                let inBeat = e.tap.ons(1).filter { Int(Double($0.sample) / 24_000 + 0.001) == b }
                XCTAssertEqual(inBeat.count, 6, "\(playAs): beat \(b): 3 notes × 2 strikes")
                let onsets = Set(inBeat.map { $0.sample })
                XCTAssertEqual(onsets.count, 2, "\(playAs): beat \(b): the notes strike together, twice (got onsets \(onsets.sorted()))")
                XCTAssertEqual(Double(onsets.min()! - Int64(b) * 24_000), 0, accuracy: 3)
                XCTAssertEqual(Double(onsets.max()! - Int64(b) * 24_000), 12_000, accuracy: 3)
            }
            // B keeps the notes layer's ROLL / RUN exactly as without the ratchet (its own strikes are untouched by A's)
            XCTAssertEqual(e.tap.events.filter { $0.cable == 2 }.count, plain.tap.events.filter { $0.cable == 2 }.count, "\(playAs): B plays what it always played")
            XCTAssertEqual(Set(e.tap.ons(2).map { $0.sample }.filter { $0 < 24_000 }).count, Set(plain.tap.ons(2).map { $0.sample }.filter { $0 < 24_000 }).count, "\(playAs): B's onsets are the plain ones")
            XCTAssertGreaterThan(Set(e.tap.ons(2).map { $0.sample }.filter { $0 < 24_000 }).count, 1, "\(playAs): B still rolls")
            }
        }
    }

    // MARK: - §3.2 the deferred strikes carry the FINAL pitch

    /// A part's OUT-TRANSPOSE shifts every note of the part; the deferred strikes of a ratchet must sound the same (shifted) pitch as strike 0.
    /// (Out-transpose is applied where each pitch is CHOSEN, so `pitches[j]` is already the shifted pitch: this guards that contract; the mutant 'tail pushes `pitches[j]`' is killed by the ROW-transpose test below.)
    func testEveryStrikeOfARatchetedNoteSoundsTheTransposedPitch() {
        var lane = mLine(); lane.riffOutTranspose = 2
        let e = mPlay(MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 3))])), beats: 8)
        let plain = mPlay(MRig(lines: [lane]), beats: 8)
        mAssertNothingLeftSounding(e.tap)
        for b in 0..<8 {
            let inBeat = e.tap.ons(1).filter { Int(Double($0.sample) / 24_000 + 0.001) == b }
            let want = plain.tap.ons(1).first { Int(Double($0.sample) / 24_000 + 0.001) == b }!.note
            XCTAssertEqual(inBeat.map { $0.note }, [want, want, want], "beat \(b): three strikes of the SAME (transposed) pitch")
            XCTAssertNotEqual(want, mPool[b % 8], "the fixture really transposes")
        }
    }

    // MARK: - §3.2 the deferred strikes carry the ROW transpose too

    /// The row's TRANSPOSE moves every note; the strikes pushed on the echo ring must be the pitch the first strike sounded.
    /// Kills: pushing the untransposed `pitches[j]` in the deferred strike.
    func testEveryStrikeOfARatchetedNoteSoundsTheRowsTransposeToo() {
        let e = mPlay(MRig(lines: [mLine()], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 3))]), transpose: 5), beats: 4)
        let plain = mPlay(MRig(lines: [mLine()], transpose: 5), beats: 4)
        for b in 0..<4 {
            let want = plain.tap.ons(1).first { Int(Double($0.sample) / 24_000 + 0.001) == b }!.note
            XCTAssertEqual(want, mPool[b] + 5, "fixture: the row transposes")
            XCTAssertEqual(e.tap.ons(1).filter { Int(Double($0.sample) / 24_000 + 0.001) == b }.map { $0.note }, [want, want, want], "beat \(b)")
        }
    }

    // MARK: - §3.3 a duplicate the part routing drops is not resurrected by the ratchet

    /// The riff and a lit note play the SAME pitch; the riff reaches {A, B}, the notes {B, C}. The notes copy leaves only on C (it is the duplicate on B). B ratchets ×2: B must sound the riff note twice — not four times.
    /// Kills: `emitOutsOf` ignoring a pitch's own output set (`outsOf`).
    func testTheNotesDuplicateOnASharedOutputIsStillDroppedWhenThatOutputRatchets() {
        let lane = mLine(litNotes: 0b1, riffOut: 0b0011, notesOut: 0b0110)    // lit rank 1 = the lowest pool note = the riff's rank 1 on column 0, ranks = all 1
        let rig = MRig(lines: [lane], emitters: mEmitters([(1, mOn(steps: 2, hits: 2, strikes: 2))]), ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        let e = mPlay(rig, beats: 4)
        mAssertNothingLeftSounding(e.tap)
        XCTAssertEqual(mPerBeat(e.tap, cable: 1, beats: 4), [1, 1, 1, 1], "A: the riff note once")
        XCTAssertEqual(mPerBeat(e.tap, cable: 2, beats: 4), [2, 2, 2, 2], "B: the riff note ×2 — the notes layer's duplicate is not struck here")
        XCTAssertEqual(mPerBeat(e.tap, cable: 3, beats: 4), [1, 1, 1, 1], "C: the notes copy once")
    }

    // MARK: - §3.10 the hit feed on a hit whose count FX RATCH set

    /// A hit carrying FX RATCH (the nRep branch) reports the output's ratchet in the feed too.
    /// Kills: dropping `emitMasks:` from the FX-RATCH branch's NOTE VIEW event.
    func testAHitWithFxRatchStillReportsTheOutputsRatchetInTheFeed() {
        var fx = EuclideousFX(); fx.cells[0 * 8 + 3] = 2    // column 3: FX RATCH ×2
        let e = mPlay(MRig(lines: [mLine(riffOut: 0b0011, notesOut: 0b0011)], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 4))]), fx: fx), beats: 8)
        for b in 0..<8 {
            let masks = e.nv.filter { abs($0.beat - Double(b)) < 0.01 }.map { $0.masks }
            XCTAssertEqual(masks, [0b0001], "beat \(b) (FX RATCH on beats 3 and 11 only): A ratcheted")
        }
    }

    // MARK: - the count is per OUTPUT, not per lane

    /// Lane 1 hits on beats 0, 2, 4, … and lane 2 on beats 1, 3, 5, …; both feed A. A's emitter hits are every beat (one count of 1 per beat): STEPS 4 / HITS 1 ratchets beats 0, 4, 8, 12.
    /// A per-lane count would give lane 1 the hits 0, 2, 4 → ratchet beats 0, 8 and lane 2 → beats 1, 9.
    /// Kills: counting per lane instead of per output.
    func testTwoLanesHittingOneOutputAtDifferentTimesFeedOneCount() {
        var l1 = mLine(pulses: 2, steps: 4); l1.riffOutMask = 0b0001; l1.notesOutMask = 0b0001
        var l2 = mLine(pulses: 2, steps: 4); l2.rotate = 1; l2.octave = 1; l2.riffOctave = 1; l2.riffOutMask = 0b0001; l2.notesOutMask = 0b0001
        let e = mPlay(MRig(lines: [l1, l2], emitters: mEmitters([(0, mOn(steps: 4, hits: 1, strikes: 3))])), beats: 16)
        mAssertNothingLeftSounding(e.tap)
        XCTAssertEqual(mPerBeat(e.tap, beats: 16), (0..<16).map { $0 % 4 == 0 ? 3 : 1 }, "the output counts every lane's hits in the order they happen")
    }

    // MARK: - outputs C and D

    /// The engine tests use A and B only. C and D take their own settings: C ×2, D ×4, each on its own cable and channel; two lanes hitting D together share its decision.
    /// Kills: any index slip for output 2 / 3 in the model, the snapshot, the counter's cache or the Router's output loops.
    func testOutputsCAndDRatchetWithTheirOwnSettings() {
        let lane = mLine(litNotes: 0b10, riffOut: 0b1000, notesOut: 0b0100)       // riff → D, the lit rank-2 note → C
        let rig = MRig(lines: [lane], emitters: mEmitters([(2, mOn(steps: 2, hits: 2, strikes: 2)), (3, mOn(steps: 2, hits: 2, strikes: 4))]), ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        let e = mPlay(rig, beats: 4)
        mAssertNothingLeftSounding(e.tap)
        XCTAssertEqual(mPerBeat(e.tap, cable: 3, beats: 4), [2, 2, 2, 2], "C: the notes layer's note ×2")
        XCTAssertEqual(mPerBeat(e.tap, cable: 4, beats: 4), [4, 4, 4, 4], "D: the riff note ×4")
        XCTAssertTrue(e.tap.ons(1).isEmpty && e.tap.ons(2).isEmpty)
        XCTAssertTrue(e.tap.ons(3).allSatisfy { $0.chan == 2 } && e.tap.ons(4).allSatisfy { $0.chan == 3 }, "each on its own output's channel")
        // two lanes hitting D at one sample share its decision and count once
        var l1 = mLine(riffOut: 0b1000, notesOut: 0b1000)
        var l2 = mLine(riffOut: 0b1000, notesOut: 0b1000); l2.octave = 1; l2.riffOctave = 1
        l1.riffOctave = 0
        let both = mPlay(MRig(lines: [l1, l2], emitters: mEmitters([(3, mOn(steps: 4, hits: 1, strikes: 3))]), ranks: [1, 1, 1, 1, 1, 1, 1, 1]), beats: 8)
        XCTAssertEqual(mPerBeat(both.tap, cable: 4, beats: 8), [6, 2, 2, 2, 6, 2, 2, 2], "counted once per beat, not once per lane")
    }

    // MARK: - what a ratcheted strike carries

    /// Every strike of a ratcheted note carries ITS pitch's velocity and gate (the riff note's and the lit note's differ), at slots of step ÷ n.
    /// Kills: a constant / wrong-pitch velocity in the direct or deferred strikes, the first pitch's gate for every pitch, a gate that ignores the pitch's share.
    func testEveryStrikeKeepsItsPitchsOwnVelocityAndGate() {
        var lane = mLine(gate: 0.5, vel: 90, litNotes: 0b10); lane.notesVelocity = 50; lane.notesGate = 0.25
        let e = mPlay(MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 3))]), ranks: [1, 1, 1, 1, 1, 1, 1, 1]), beats: 4)
        mAssertNothingLeftSounding(e.tap)
        for b in 0..<4 {
            let t0 = Double(b) * 24_000
            for (note, vel, gateShare) in [(UInt8(48), UInt8(90), 0.5), (UInt8(50), UInt8(50), 0.25)] {
                let ons = e.tap.ons(1).filter { $0.note == note && Int(Double($0.sample) / 24_000 + 0.001) == b }.sorted { $0.sample < $1.sample }
                XCTAssertEqual(ons.count, 3, "beat \(b) note \(note)")
                for (k, on) in ons.enumerated() {
                    XCTAssertEqual(on.vel, vel, "beat \(b) note \(note) strike \(k): the pitch's own velocity")
                    XCTAssertEqual(Double(on.sample), t0 + Double(k) * 8_000, accuracy: 3)
                    let off = e.tap.offs(1).first { $0.note == note && $0.sample > on.sample }
                    XCTAssertEqual(Double(off?.sample ?? 0) - Double(on.sample), 8_000 * gateShare, accuracy: 4, "beat \(b) note \(note) strike \(k): the pitch's own gate share of the slot")
                }
            }
        }
    }

    // MARK: - an output's ratchet replaces the hit's own FX RATCH on that output, in every variant of the FX RATCH path

    /// The riff note leaves on A and B; column 3 carries FX RATCH ×2 (flat, then ACCENT-shaped so the deferred strikes are one tail each) and column 4 a TIE, so the ratcheted hit at beat 3 is tied through beat 4. A ratchets ×4
    /// everywhere: its own strikes replace the FX ratchet's strike 0, its in-window strikes, its plain / shaped tails and its tie tail. B keeps the FX ratchet.
    /// Kills: `outsOf` instead of `outsStrike` in the FX-RATCH path's strike 0 / in-window / tail / shaped tail / tie tail, and the `strikesPlain` guard there.
    func testAnOutputsRatchetReplacesTheHitsFxRatchOnThatOutputInEveryVariant() {
        for shape: UInt8 in [0, 1] {
            for tie in [false, true] {
                for frames: UInt32 in [2048, 16_384] {
                    var fx = EuclideousFX(); fx.cells[0 * 8 + 3] = 2; fx.ratchShape = shape
                    if tie { fx.cells[2 * 8 + 4] = 1 }
                    let e = mPlay(MRig(lines: [mLine(riffOut: 0b0011, notesOut: 0b0011)], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 4))]), fx: fx), beats: 16, frames: frames)
                    mAssertNothingLeftSounding(e.tap)
                    let tied: (Int) -> Bool = { tie && $0 % 8 == 4 }
                    XCTAssertEqual(mPerBeat(e.tap, cable: 1, beats: 16), (0..<16).map { tied($0) ? 0 : 4 }, "shape \(shape) tie \(tie) frames \(frames): A strikes ×4 on every sounding hit, FX RATCH or not")
                    XCTAssertEqual(mPerBeat(e.tap, cable: 2, beats: 16), (0..<16).map { tied($0) ? 0 : ($0 % 8 == 3 ? 2 : 1) }, "shape \(shape) tie \(tie) frames \(frames): B keeps the hit's own FX RATCH ×2")
                }
            }
        }
    }

    // MARK: - nothing is handed an empty output set

    /// A pitch whose every output ratchets strikes nothing the ordinary way. The ordinary loops must SKIP it: handing them an empty output set draws a silent mark in the note roll (a note that was never "routed nowhere").
    /// Kills: dropping the `strikesPlain` guard of the FX-RATCH loop or of the ROLL / RUN loop, and the legato reconcile tracking a ratchet-only pitch.
    func testNoRatchetOnlyPitchEverReachesTheRollAsASilentNote() {
        // (a) the FX-RATCH loop: the riff note on A only, A ratcheting, FX RATCH ×2 on column 3
        var fx = EuclideousFX(); fx.cells[0 * 8 + 3] = 2
        let a = mPlay(MRig(lines: [mLine(riffOut: 0b0001, notesOut: 0b0001)], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 3))]), fx: fx), beats: 8)
        XCTAssertEqual(mSilentRollRecords(a.router), 0, "FX RATCH loop")
        // (b) the ROLL / RUN loop: three lit notes on A only, A ratcheting
        for playAs in [EuclidNotesPlayAs.roll, .run] {
            var lane = mLine(gate: 0.9, litNotes: 0b0000_0111, riffOut: 0b0001, notesOut: 0b0001); lane.notesPlayAs = playAs; lane.notesWhen = 0b11; lane.riffOn = false; lane.useRiff = false
            let b = mPlay(MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 2))])), beats: 8)
            XCTAssertEqual(mSilentRollRecords(b.router), 0, "\(playAs) loop")
        }
        // (c) legato: the same pitch held across hits on A, A ratcheting hit 1
        let c = mPlay(MRig(lines: [mLine(gate: 1.0, riffOut: 0b0001, notesOut: 0b0001)], emitters: mEmitters([(0, mOn(steps: 4, hits: 1, offset: 3, strikes: 3))]), ranks: [1, 1, 1, 1, 1, 1, 1, 1]), beats: 6)
        XCTAssertEqual(mSilentRollRecords(c.router), 0, "legato reconcile")
    }

    // MARK: - the same strikes at any buffer size

    /// The in-window strikes (a buffer longer than a slot), the deferred ones and the tie-extended last strike must be one and the same schedule: every event at every buffer size, within two samples.
    /// Kills: anything that only differs when a strike is struck directly instead of from the echo ring (outputs, pitch, velocity, tie length, the window-end test, a skipped strike 1).
    func testTheSchedulePlaysTheSameAtAnyBufferSize() {
        var fx = EuclideousFX(); fx.cells[2 * 8 + 1] = 1                  // a TIE on column 1
        fx.cells[0 * 8 + 3] = 2                                           // FX RATCH ×2 on column 3
        var lane = mLine(gate: 0.6, litNotes: 0b10, riffOut: 0b0011, notesOut: 0b0110); lane.notesGate = 0.4; lane.notesVelocity = 60
        let rig = MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 4)), (1, mOn(steps: 3, hits: 2, strikes: 3)), (2, mOn(steps: 2, hits: 1, strikes: 2))]), fx: fx)
        func norm(_ e: MTap) -> [MEv] { e.events.filter { $0.sample >= 0 && $0.sample < 24_000 * 83 / 10 }.sorted {   // the first 8.3 beats: what a STOP cuts at the end depends on where the last window falls
             ($0.cable, $0.chan, $0.note, $0.on ? 1 : 0, $0.sample) < ($1.cable, $1.chan, $1.note, $1.on ? 1 : 0, $1.sample) } }
        let reference = norm(mPlay(rig, beats: 10, frames: 2048).tap)
        XCTAssertGreaterThan(reference.count, 100)
        for frames: UInt32 in [64, 477, 8192, 30_000] {
            let other = norm(mPlay(rig, beats: 10, frames: frames).tap)
            func missing(_ a: [MEv], from b: [MEv]) -> [MEv] { a.filter { x in !b.contains { y in y.cable == x.cable && y.chan == x.chan && y.note == x.note && y.on == x.on && abs(y.sample - x.sample) <= 2 } } }
            XCTAssertEqual(other.count, reference.count, "frames \(frames): same number of events; only in 2048: \(missing(reference, from: other)); only here: \(missing(other, from: reference))")
            for (a, b) in zip(reference, other) {
                XCTAssertTrue(a.cable == b.cable && a.note == b.note && a.on == b.on && a.vel == b.vel && a.chan == b.chan && abs(a.sample - b.sample) <= 2,
                              "frames \(frames): \(a) vs \(b)")
                if a.cable != b.cable || a.note != b.note || a.chan != b.chan { break }
            }
        }
    }

    // MARK: - legato: the same pitch on every hit (the existing legato tests walk a DIFFERENT pitch each hit, so nothing is ever carried on)

    /// GATE 100 and the riff on rank 1 every hit: one note held across hits. A ratchets hit 1 only: the held note must close at that hit (the pitch leaves only on A, which ratchets) and the hit strikes ×3.
    /// Hit 2 is then a fresh legato note (the old one is gone). Totals on A over beats 0…3: 1 + 3 + 1 + 0.
    /// Kills: dropping `neverLegatoBits` (the ratchet-only pitch stays tracked as a legato hold and is carried through the ratcheted hit).
    func testARatchetOnlyPitchHeldLegatoClosesAtTheRatchetedHitWhenTheSamePitchRepeats() {
        let lane = mLine(gate: 1.0, riffOut: 0b0001, notesOut: 0b0001)
        let ranks = [1, 1, 1, 1, 1, 1, 1, 1]
        let plain = mPlay(MRig(lines: [lane], ranks: ranks), beats: 4)
        XCTAssertEqual(mPerBeat(plain.tap, beats: 4), [1, 0, 0, 0], "fixture: one legato note carried through all four hits")
        let e = mPlay(MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 4, hits: 1, offset: 3, strikes: 3))]), ranks: ranks), beats: 4)
        mAssertNothingLeftSounding(e.tap)
        XCTAssertEqual(mPerBeat(e.tap, beats: 4), [1, 3, 1, 0], "the held note ends at the ratcheted hit; the next hit starts a new legato note")
        let heldOff = e.tap.offs(1).first!
        XCTAssertEqual(Double(heldOff.sample), 24_000, accuracy: 0.011 * 48_000 + 2, "…within the 10 ms overlap of the ratcheted hit")
    }
    /// The documented limit, with a pitch that really is held: one pitch held legato on {A, B}; A ratchets hit 1. The pitch's output set changes, so B's copy is struck afresh at that hit instead of carried on.
    /// Kills: handing the reconcile the pitch's FULL output set instead of the outputs it still strikes on.
    func testALegatoPitchHeldOnTwoOutputsIsReStruckOnTheOtherOutputWhenOneRatchets() {
        let lane = mLine(gate: 1.0, riffOut: 0b0011, notesOut: 0b0011)
        let ranks = [1, 1, 1, 1, 1, 1, 1, 1]
        let plain = mPlay(MRig(lines: [lane], ranks: ranks), beats: 4)
        XCTAssertEqual(mPerBeat(plain.tap, cable: 2, beats: 4), [1, 0, 0, 0], "fixture: B carries one legato note")
        let e = mPlay(MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 4, hits: 1, offset: 3, strikes: 3))]), ranks: ranks), beats: 4)
        mAssertNothingLeftSounding(e.tap)
        XCTAssertEqual(mPerBeat(e.tap, cable: 1, beats: 4), [1, 3, 1, 0])
        XCTAssertEqual(mPerBeat(e.tap, cable: 2, beats: 4), [1, 1, 1, 0], "B's copy is struck afresh at the ratcheted hit and again at the next (its output set changed twice), then carried on")
    }

    // MARK: - a stop / a load cancels the strikes still pending

    /// A ×4 on every hit; the transport stops 0.1 beat after the hit at beat 2 and (a) resumes where it was, (b) a scene is flushed there: the strikes due at 2.25, 2.5 and 2.75 are gone — nothing sounds on A before the next hit.
    /// (The existing stop/load test only checks nothing is left sounding: a late strike has its own off and passes it.)
    /// Kills: not clearing the echo ring at a transport edge / on a scene flush.
    func testAStopOrALoadCancelsTheStrikesStillPending() {
        for mode in ["resume after a stop", "scene flush"] {
            let tap = MTap(), router = Router()
            var diag = KernelDiag(); let sr = 48_000.0
            let p = NotePool(); for n in mPool { p.noteOn(n, velocity: 100, channel: 0) }
            let box = MRig(lines: [mLine()], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 4))])).box()
            var ts = 0.0
            func beat() -> Double { ts * 2 / sr }
            while beat() < 2.1 { router.process(box: box, pool: p, playing: true, beatPos: beat(), tempo: 120, sampleRate: sr, timestampSample: ts, frameCount: 128, forceColumn: 0, out: tap, diag: &diag); ts += 128 }
            let cut = ts
            if mode == "scene flush" {
                router.process(box: box, pool: p, playing: true, beatPos: beat(), tempo: 120, sampleRate: sr, timestampSample: ts, frameCount: 128, forceColumn: 0, sceneFlush: true, out: tap, diag: &diag); ts += 128
            } else {
                router.process(box: box, pool: p, playing: false, beatPos: beat(), tempo: 120, sampleRate: sr, timestampSample: ts, frameCount: 128, out: tap, diag: &diag); ts += 128
            }
            while beat() < 2.9 { router.process(box: box, pool: p, playing: true, beatPos: beat(), tempo: 120, sampleRate: sr, timestampSample: ts, frameCount: 128, forceColumn: 0, out: tap, diag: &diag); ts += 128 }
            // The engine re-strikes the current step's hit after a resume or a flush (true with no ratchets at all), so the strikes due at 2.25, 2.5 and 2.75 come back once — never twice (a stale copy would double them).
            for due in [2.25, 2.5, 2.75] {
                let n = tap.ons(1).filter { abs(Double($0.sample) - due * 24_000) < 300 }.count
                XCTAssertEqual(n, 1, "\(mode): the strike due at beat \(due) sounds once, not \(n) times")
            }
        }
    }

    // MARK: - a tie after a ratcheted hit that is NOT one step away

    /// Hits on beats 0, 2, 4, …; the hit at beat 2 is tied (TIE on column 1). A ×4 on every hit. The last strike of the hit at beat 0 must carry through the tie exactly as the plain note does (to the next SOUNDING hit's reach), not just one step.
    /// Kills: using the step instead of the gap to the next hit when the last strike is extended.
    func testTheLastStrikeOfATiedRatchetReachesThroughTheWholeGapToTheNextHit() {
        var fx = EuclideousFX(); fx.cells[2 * 8 + 1] = 1
        let lane = mLine(pulses: 2, steps: 4)
        let plain = mPlay(MRig(lines: [lane], fx: fx), beats: 4)
        let e = mPlay(MRig(lines: [lane], emitters: mEmitters([(0, mOn(steps: 2, hits: 2, strikes: 4))]), fx: fx), beats: 4)
        mAssertNothingLeftSounding(e.tap)
        let plainOff = Double(plain.tap.offs(1).filter { $0.sample < 48_000 * 2 }.map { $0.sample }.max() ?? 0)
        let lastOff = Double(e.tap.offs(1).filter { $0.sample < 48_000 * 2 }.map { $0.sample }.max() ?? 0)
        XCTAssertGreaterThan(plainOff, 24_000 * 1.5, "fixture: the plain note is carried well past one step")
        XCTAssertEqual(lastOff, plainOff, accuracy: 24_000 * 0.55, "the ratcheted note ends where the tie says, not a step after its last strike (plain \(plainOff), ratcheted \(lastOff))")
        XCTAssertGreaterThan(lastOff, 24_000 * 1.5)
    }

    // MARK: - the card floor

    /// A card of 51 pt is under the 52 pt floor and one of 52 is not.
    /// Kills: the floor constant moved.
    func testTheCardFloorIsExactly52() {
        func belowFloor(cardHeight h: CGFloat) -> Bool { emitterRatchetLayout(bodySize: CGSize(width: 360, height: 4 * h + 3 + 18), portrait: false).belowFloor }
        XCTAssertTrue(belowFloor(cardHeight: 51)); XCTAssertFalse(belowFloor(cardHeight: 52)); XCTAssertFalse(belowFloor(cardHeight: 51.995))
    }

    // MARK: - the flare: a tie within 5 ms belongs to the lower lane

    /// Kills: dropping the 5 ms tolerance of the flare's "later strike wins".
    func testTheFlareKeepsTheLowerLaneForStrikesWithinFiveMilliseconds() {
        func strike(at: Double, masks: UInt8) -> EuclideousPulseStrike {
            var s = EuclideousPulseStrike(onsetBeat: 0, onsetAt: at, riffVel: 100, notesVel: 0); s.emitMasks = masks; return s
        }
        let ties: [[EuclideousPulseStrike]] = [[], [strike(at: 20.000, masks: 0b0001)], [strike(at: 20.003, masks: 0b0001)], []]
        XCTAssertEqual(emitterRatchetFlare(output: 0, strikes: ties, now: 20.01, scale: 1)?.lane, 1, "3 ms later is the same moment: the lower lane keeps it")
        let later: [[EuclideousPulseStrike]] = [[], [strike(at: 20.000, masks: 0b0001)], [strike(at: 20.010, masks: 0b0001)], []]
        XCTAssertEqual(emitterRatchetFlare(output: 0, strikes: later, now: 20.02, scale: 1)?.lane, 2, "10 ms later is a different moment")
    }
}
