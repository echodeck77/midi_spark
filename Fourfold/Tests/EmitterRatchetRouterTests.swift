//  EmitterRatchetRouterTests.swift — RATCH tab ferry (2026-10-28) §10 tests 2–10: the engine, through a real Router.
//  "A lane hit that sends notes on output X counts one for X; when X's pattern + CHANCE say so, every note leaving on X from that hit sounds n times within the step — only on X."
//  Unless stated: one lane (lane 1 → output A, cable 1), 4 hits in 4 steps at 1/4 — one hit a beat, 24,000 samples apart at 120 BPM / 48 kHz — the riff walked FWD over 8 columns (beat k reads column k mod 8), a held
//  C-major-ish pool of eight notes. Cable 0 is ALL; cables 1…4 are outputs A…D, each stamping its own channel (A = channel index 0).

import XCTest

private struct Ev: Equatable { let sample: Int64; let cable: UInt8; let on: Bool; let chan: UInt8; let note: UInt8; let vel: UInt8 }
private final class Tap: MIDIEmitter {
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0
        guard st == 0x90 || st == 0x80 else { return }
        events.append(Ev(sample: sampleTime, cable: cable, on: st == 0x90 && b2 > 0, chan: b0 & 0x0F, note: b1, vel: b2))
    }
    func ons(_ cable: UInt8) -> [Ev] { events.filter { $0.cable == cable && $0.on } }
    func offs(_ cable: UInt8) -> [Ev] { events.filter { $0.cable == cable && !$0.on } }
}

private let pool: [UInt8] = [48, 50, 52, 53, 55, 57, 59, 60]

private struct Rig {
    var lines: [EuclidLine]
    var emitters = EmitterRatchetSet()
    var fx = EuclideousFX()
    var ranks = [1, 2, 3, 4, 5, 6, 7, 8]
    var solo: UInt8 = 0
    var fxCounts: FxCountsMode? = nil    // the dev-only FX COUNTS (honoured in DEBUG builds, which the tests are)
    func box() -> SnapshotBox {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)
        c.paramsA.euclidLines = lines
        c.paramsA.soloMask = solo == 0 ? nil : solo
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        st.euclideousNoteSource = .midi
        st.euclideousFX = fx
        st.euclideousEmitterRatchets = emitters.isAllDefault ? nil : emitters
        st.euclideousFxCounts = fxCounts
        return SnapshotBuilder.build(from: st)
    }
}
private struct Played {
    let tap: Tap
    let router: Router
    /// every NOTE VIEW event the run produced: (the hit's beat, lane, the emit masks)
    let nv: [(beat: Double, lane: Int, masks: UInt8)]
    let restartSamples: [Int64]
    var events: [Ev] { tap.events }
}

/// A lane as the header describes: `pulses` hits in `steps` at `rate`, the riff on, lit notes optional.
private func line(pulses: Int = 4, steps: Int = 4, rate: ArpRate = .r1_4, gate: Double = 0.5, vel: Int = 90, litNotes: UInt8 = 0, riffOut: UInt8? = nil, notesOut: UInt8? = nil) -> EuclidLine {
    var l = EuclidLine(target: 0, pulses: pulses, steps: steps)
    l.gate = gate; l.velocityAbsolute = vel; l.rate = rate; l.useRiff = true; l.litNotes = litNotes; l.riffOn = true; l.sourceMode = .midi
    l.riffLength = 8; l.notesOn = true; l.riffOnRest = .skip
    l.riffOutMask = riffOut; l.notesOutMask = notesOut
    return l
}
private func emitters(_ list: [(Int, EmitterRatchet)]) -> EmitterRatchetSet {
    var s = EmitterRatchetSet()
    for (i, r) in list { s[i] = r }
    return s
}
private func on(steps: Int = 8, hits: Int = 3, offset: Int = 0, chance: Int = 100, strikes: Int = 3) -> EmitterRatchet {
    EmitterRatchet(on: true, steps: steps, hits: hits, offset: offset, chance: chance, strikes: strikes)
}

/// Run `beats` of playing windows from beat 0 at `tempo`, with optional transport restarts (a stop window, then back to beat 0), scene flushes (a session / preset load) and document swaps (an edit), then one STOP window.
private func play(_ rig: Rig, beats: Double, frames: UInt32 = 2048, tempo: Double = 120, restartAt: [Double] = [], flushAt: [Double] = [], swapAt: [(beat: Double, rig: Rig)] = [], allOffAt: [Double] = [], jumpAt: [(at: Double, to: Double)] = [], pool notes: [UInt8] = pool) -> Played {
    let tap = Tap(), router = Router()
    var diag = KernelDiag(); let sr = 48_000.0
    let p = NotePool(); for n in notes { p.noteOn(n, velocity: 100, channel: 0) }
    var box = rig.box()
    var ts = 0.0, origin = 0.0
    var jumped = 0.0   // beats added by a jump while playing (a host loop, free-run handing the clock back)
    func beatNow() -> Double { (ts - origin) * tempo / 60.0 / sr + jumped }
    var jumps = jumpAt.sorted { $0.at < $1.at }
    var restarts = restartAt.sorted(), flushes = flushAt.sorted(), swaps = swapAt.sorted { $0.beat < $1.beat }
    var allOffs = allOffAt.sorted()
    var nv: [(beat: Double, lane: Int, masks: UInt8)] = []
    var restartSamples: [Int64] = []
    func drain() {
        let all = router.drainEuclideousNoteViewEvents()
        for (lane, evs) in all.enumerated() { for e in evs { nv.append((e.onsetBeat, lane, e.emitMasks)) } }
    }
    while beatNow() < beats {
        if let j = jumps.first, beatNow() >= j.at { jumps.removeFirst(); jumped += j.to - beatNow() }
        if let r = restarts.first, beatNow() >= r {
            restarts.removeFirst()
            router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: tap, diag: &diag)
            ts += Double(frames); origin = ts; restartSamples.append(Int64(ts))
        }
        if let s = swaps.first, beatNow() >= s.beat { swaps.removeFirst(); box = s.rig.box() }
        var flush = false
        if let f = flushes.first, beatNow() >= f { flushes.removeFirst(); flush = true }
        var allOff = false
        if let a = allOffs.first, beatNow() >= a { allOffs.removeFirst(); allOff = true }
        router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, euclideousAllNotesOff: allOff, sceneFlush: flush, out: tap, diag: &diag)
        drain()
        ts += Double(frames)
    }
    router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: tap, diag: &diag)
    drain()
    return Played(tap: tap, router: router, nv: nv, restartSamples: restartSamples)
}
/// `cable`'s note-ons grouped by the beat they fall in (hit k at beat k), as a count per beat.
private func perBeat(_ e: Tap, cable: UInt8 = 1, beats: Int, perBeatSamples: Double = 24_000) -> [Int] {
    var c = [Int](repeating: 0, count: beats)
    for ev in e.ons(cable) { let b = Int(Double(ev.sample) / perBeatSamples + 0.001); if b >= 0 && b < beats { c[b] += 1 } }
    return c
}
private func assertNothingLeftSounding(_ e: Tap, file: StaticString = #filePath, line: UInt = #line) {
    var last: [Int: Bool] = [:]
    for ev in e.events { last[(Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)] = ev.on }
    for (key, on) in last where on { XCTFail("stuck note: key \(key) last event was ON, not OFF", file: file, line: line) }
}

final class EmitterRatchetRouterTests: XCTestCase {

    // MARK: - §10 test 2 — counting HITS

    func testAnEmitterRatchetsEveryFourthHitOnItsOwnOutputAtTheIndexThePatternMarks() {
        // A on: STEPS 4, HITS 1, OFFSET 0, CHANCE 100, ×3; lane 1 routed to A only. 16 hits (one a beat).
        let e = play(Rig(lines: [line()], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))])), beats: 16)
        assertNothingLeftSounding(e.tap)
        XCTAssertEqual(perBeat(e.tap, beats: 16), (0..<16).map { $0 % 4 == 0 ? 3 : 1 }, "exactly one hit in every four ratchets ×3, at the index P marks (index 0)")
        XCTAssertEqual(perBeat(e.tap, cable: 0, beats: 16), (0..<16).map { $0 % 4 == 0 ? 3 : 1 }, "ALL carries the same strikes")
        for c in [UInt8(2), 3, 4] { XCTAssertTrue(e.tap.ons(c).isEmpty, "output \(c) is not routed to by lane 1") }
        XCTAssertTrue(e.tap.ons(1).allSatisfy { $0.chan == 0 }, "…all on A's own channel")
        // the strikes of a ratcheted hit sit at hit + k × step ÷ n (step = 1 beat)
        let hit0 = e.tap.ons(1).filter { $0.sample < 24_000 }.map { $0.sample }
        XCTAssertEqual(hit0.count, 3)
        for (k, s) in hit0.enumerated() { XCTAssertEqual(Double(s), Double(k) * 8_000, accuracy: 2) }
    }
    func testAnOffEmitterAndAnAllOffSetPlayBitIdenticallyToNoRatchetsAtAll() {
        let plain = play(Rig(lines: [line()]), beats: 12)
        let off = play(Rig(lines: [line()], emitters: emitters([(0, EmitterRatchet(on: false, steps: 4, hits: 1, offset: 1, chance: 50, strikes: 4)), (1, EmitterRatchet())])), beats: 12)
        XCTAssertEqual(plain.events, off.events, "OFF emitters change nothing — a fresh session and an old one sound exactly as before")
        XCTAssertFalse(plain.events.isEmpty)
        XCTAssertTrue(plain.nv.allSatisfy { $0.masks == 0 } && off.nv.allSatisfy { $0.masks == 0 }, "…and an OFF emitter neither ratchets nor misses in the hit feed")
    }
    func testTwoLanesHittingOneOutputAtOneSampleCountOnceAndShareTheDecision() {
        // lanes 1 and 2 both play to A, in step, in different octaves (so the two notes are told apart). One emitter hit a beat, not two.
        var l2 = line(); l2.octave = 1; l2.riffOctave = 1; l2.riffOutMask = 0b0001; l2.notesOutMask = 0b0001
        let e = play(Rig(lines: [line(), l2], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))]), ranks: [1, 1, 1, 1, 1, 1, 1, 1]), beats: 8)
        assertNothingLeftSounding(e.tap)
        XCTAssertEqual(perBeat(e.tap, beats: 8), [6, 2, 2, 2, 6, 2, 2, 2], "both lanes' notes ratchet ×3 together on hits 0 and 4 — counted once per beat, not once per lane (that would ratchet every other beat)")
        XCTAssertEqual(Set(e.tap.ons(1).map { $0.note }).count, 2, "two different notes")
    }

    /// ADVERSARIAL REVIEW (2026-10-28): lanes run their whole window one after another, so two lanes that BOTH hit an output several times inside one window must still share each shared sample's decision — the result may not depend
    /// on the buffer size. (The cache used to remember a single sample per output.)
    func testTwoLockstepLanesOnOneOutputGiveTheSameStrikesAtEveryBufferSize() {
        var l2 = line(pulses: 8, steps: 8, rate: .r1_16); l2.octave = 1; l2.riffOctave = 1; l2.riffOutMask = 0b0001; l2.notesOutMask = 0b0001
        let l1 = line(pulses: 8, steps: 8, rate: .r1_16)
        let rig = Rig(lines: [l1, l2], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 2))]), ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        var results: [[Int]] = []
        for frames in [UInt32(256), 2048, 32_768] {
            let e = play(rig, beats: 6, frames: frames)
            assertNothingLeftSounding(e.tap)
            // quarter-beat hits: bucket the note-ons by 16th (6,000 samples)
            var c = [Int](repeating: 0, count: 24)
            for ev in e.tap.ons(1) { let b = Int(Double(ev.sample) / 6_000 + 0.01); if b < 24 { c[b] += 1 } }
            results.append(c)
        }
        XCTAssertEqual(results[0], results[1], "256 and 2048 frames agree"); XCTAssertEqual(results[1], results[2], "…and so does a 32,768-frame buffer with several hits per lane per window")
        XCTAssertEqual(results[0].filter { $0 == 4 }.count, 6, "one emitter hit in every four ratchets ×2 for BOTH lanes' notes: 2 lanes × 2 strikes = 4 note-ons on those 16ths, 2 on the rest")
    }

    // MARK: - §10 test 3 — what does not count

    func testASilencedLanesHitsDoNotAdvanceTheCount() {
        // lane 2 also feeds A but is solo-silenced (lane 1 soloed): only lane 1's hits count.
        var l2 = line(); l2.octave = 1; l2.riffOutMask = 0b0001; l2.notesOutMask = 0b0001
        let e = play(Rig(lines: [line(), l2], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))]), solo: 0b0001), beats: 12)
        XCTAssertEqual(perBeat(e.tap, beats: 12), (0..<12).map { $0 % 4 == 0 ? 3 : 1 }, "a silenced lane sends nothing, so it is no emitter hit: the pattern runs on lane 1's hits alone")
    }
    /// ADVERSARIAL REVIEW (2026-10-28): spec test 3 names a LANES-muted hit; the first version used a solo-silenced lane. A lane whose LANES mute grid is all clear is inaudible at every hit — it must not count either.
    func testALanesMutedLanesHitsDoNotAdvanceTheCount() {
        var l2 = line(); l2.octave = 1; l2.riffOutMask = 0b0001; l2.notesOutMask = 0b0001; l2.muteCells16 = 0          // every LANES cell clear: this lane never sounds
        let e = play(Rig(lines: [line(), l2], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))])), beats: 12)
        XCTAssertEqual(perBeat(e.tap, beats: 12), (0..<12).map { $0 % 4 == 0 ? 3 : 1 }, "a LANES-muted hit sends nothing, so it is no emitter hit: the pattern runs on lane 1's hits alone")
    }
    /// §3.9: ALL NOTES OFF ends what sounds and leaves nothing stuck, and it is not a count origin (the count carries on) — pending ratchet tails are cancelled exactly as FX RATCH's are (which is: not by this request).
    func testAllNotesOffMidRatchetLeavesNothingStuckAndDoesNotResetTheCount() {
        let rig = Rig(lines: [line()], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 4))]))
        let e = play(rig, beats: 12, frames: 128, allOffAt: [4.1])
        assertNothingLeftSounding(e.tap)
        XCTAssertEqual(perBeat(e.tap, beats: 12).enumerated().filter { $0.element >= 4 }.map { $0.offset }, [0, 4, 8], "the ratchets stay on hits 0, 4, 8: ALL NOTES OFF restarts nothing")
    }
    func testATiedHitSendsNothingSoItNeverCountsAndNeverRatchets() {
        // TIE on column 1 (row 2): the hit at beats 1, 9, 17… ties the note before it. STEPS 4 / HITS 1: every fourth SOUNDING hit ratchets.
        var fx = EuclideousFX(); fx.cells[2 * 8 + 1] = 1
        let beats = 24
        let e = play(Rig(lines: [line()], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))]), fx: fx), beats: Double(beats))
        assertNothingLeftSounding(e.tap)
        let tiedBeats = Set((0..<beats).filter { $0 % 8 == 1 })
        var counted = 0, want = [Int](repeating: 0, count: beats)
        for b in 0..<beats where !tiedBeats.contains(b) { want[b] = counted % 4 == 0 ? 3 : 1; counted += 1 }
        // a tied hit carries the previous note through (no note-on of its own): zero strikes at those beats, and the previous hit's note is held
        let got = perBeat(e.tap, beats: beats)
        for b in 0..<beats where !tiedBeats.contains(b) { XCTAssertEqual(got[b], want[b], "beat \(b)") }
        for b in tiedBeats { XCTAssertEqual(got[b], 0, "the tied hit at beat \(b) strikes nothing") }
    }
    func testASilentRestDoesNotCountButARestHitWhereTheNotesLayerPlaysDoes() {
        // column 1 is a written rest. SKIP, no lit notes: the hit is silent and must not count. With a lit note whose WHEN covers rests, the same hit sounds (notes layer) and counts.
        let ranks = [1, 0, 1, 1, 1, 1, 1, 1]
        let beats = 16
        let silent = play(Rig(lines: [line()], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))]), ranks: ranks), beats: Double(beats))
        var soundingIdx = 0
        var want = [Int](repeating: 0, count: beats)
        for b in 0..<beats where b % 8 != 1 { want[b] = soundingIdx % 4 == 0 ? 3 : 1; soundingIdx += 1 }
        XCTAssertEqual(perBeat(silent.tap, beats: beats), want, "a silent rest sends nothing: it is not an emitter hit")
        var withNotes = line(litNotes: 0b10, notesOut: 0b0001); withNotes.notesWhen = 0b11   // the lit note is rank 2: a different pitch from the riff's rank 1, so it is not the duplicate the part routing drops
        let loud = play(Rig(lines: [withNotes], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))]), ranks: ranks), beats: Double(beats))
        // every beat now sounds something on A (the riff note, or on the rest the lit note): the pattern runs on all 16 hits; rest beats play the lit note alone
        for b in 0..<beats {
            let n = loud.tap.ons(1).filter { Int(Double($0.sample) / 24_000 + 0.001) == b }.count
            let ratcheted = b % 4 == 0
            let perStrike = (b % 8 == 1) ? 1 : 2   // riff note + lit note (distinct pitches) on a sounding riff beat; the lit note alone on the rest
            XCTAssertEqual(n, ratcheted ? perStrike * 3 : perStrike, "beat \(b)")
        }
    }
    func testAPartRoutedAwayFromAnOutputSendsNothingThereAndDoesNotCountThere() {
        // lane 1's riff → B only; A's emitter is ON but nothing ever leaves on A: it never counts, never ratchets.
        let e = play(Rig(lines: [line(riffOut: 0b0010, notesOut: 0b0010)], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 4)), (1, on(steps: 4, hits: 1, strikes: 3))])), beats: 8)
        XCTAssertTrue(e.tap.ons(1).isEmpty)
        XCTAssertEqual(perBeat(e.tap, cable: 2, beats: 8), [3, 1, 1, 1, 3, 1, 1, 1], "B counts its own hits and ratchets ×3 every fourth")
        XCTAssertEqual(e.router.emitterIndexLive & 0xFF, 0xFF, "A published no index: it never took a hit")
    }

    // MARK: - §10 test 4 — the count origin

    func testTheCountRestartsAtTransportStartAndOnALoadButNotOnALanesOwnRestartOrAnEdit() {
        let a = on(steps: 3, hits: 1, strikes: 3)   // period 3: a ratchet on hits 0, 3, 6, …
        let base = Rig(lines: [line()], emitters: emitters([(0, a)]))
        // a transport restart at beat 4: the replayed beat 0 is hit 0 again
        let r = play(base, beats: 8, restartAt: [4])
        XCTAssertEqual(r.restartSamples.count, 1)
        let sr0 = Double(r.restartSamples[0])
        let afterRestart = r.tap.ons(1).filter { Double($0.sample) >= sr0 }
        XCTAssertEqual(Set(afterRestart.filter { Double($0.sample) < sr0 + 24_000 }.map { $0.sample }).count, 3, "the first hit after a transport restart is hit 0 again: it ratchets")
        // a session / preset load (scene flush) at beat 4.3 resets it. (The engine re-strikes the current step's hit in the flush window — true with no ratchets at all — so beat 4 holds that replay: it is hit 0 again and ratchets,
        // and the next ratchet is hit 3 after it, at beat 7. Without the flush they stay on 0, 3, 6, 9.)
        let f = play(base, beats: 10, flushAt: [4.3])
        XCTAssertEqual(perBeat(f.tap, beats: 10), [3, 1, 1, 3, 1 + 3, 1, 1, 3, 1, 1], "a load is a count origin")
        let noFlush = play(base, beats: 10)
        XCTAssertEqual(perBeat(noFlush.tap, beats: 10), [3, 1, 1, 3, 1, 1, 3, 1, 1, 3], "…and without it they stay on 0, 3, 6, 9")
        // the lane's OWN rhythm restart every bar does NOT reset it: ratchets at hits 0, 3, 6, 9 — not at every bar start
        var lr = line(); lr.restartRhythmBars = [1]
        let own = play(Rig(lines: [lr], emitters: emitters([(0, a)])), beats: 12)
        XCTAssertEqual(perBeat(own.tap, beats: 12), (0..<12).map { $0 % 3 == 0 ? 3 : 1 }, "a lane's own restart is not a count origin")
        // editing STEPS / HITS / OFFSET mid-run does not reset it either: the count carries on from 6 under the new STEPS 4 (6 mod 4 = 2 → next ratchet at hit 8)
        let edited = Rig(lines: [line()], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))]))
        let e = play(base, beats: 12, swapAt: [(6, edited)])
        let eb = perBeat(e.tap, beats: 12)
        XCTAssertEqual(eb[0], 3); XCTAssertEqual(eb[3], 3); XCTAssertEqual(eb[6], 3, "hit 6 under STEPS 3 ratchets (6 mod 3 = 0) — the swap lands in the window after beat 6, so check the carry below")
        XCTAssertEqual(eb[8], 3, "…and under the new STEPS 4 the count has carried on: hit 8 is 8 mod 4 = 0")
        XCTAssertEqual(eb[7], 1)
    }

    // MARK: - §10 test 5 — counting STEPS (FX COUNTS, dev builds)

    func testInStepsModeTheIndexFollowsTheLanesPatternStepNotTheCount() {
        // a lane of 2 hits in 4 steps (hits on steps 0 and 2 of every lap, one step a beat): hits at beats 0, 2, 4, 6, 8, 10. A: STEPS 4, HITS 1 → P marks index 0.
        let lane = line(pulses: 2, steps: 4)
        let a = emitters([(0, on(steps: 4, hits: 1, strikes: 3))])
        let hitsMode = play(Rig(lines: [lane], emitters: a), beats: 12)
        XCTAssertEqual(perBeat(hitsMode.tap, beats: 12), [3, 0, 1, 0, 1, 0, 1, 0, 3, 0, 1, 0], "HITS: every fourth HIT ratchets — hits 0 and 4, beats 0 and 8")
        let stepsMode = play(Rig(lines: [lane], emitters: a, fxCounts: .steps), beats: 12)
        XCTAssertEqual(perBeat(stepsMode.tap, beats: 12), [3, 0, 1, 0, 3, 0, 1, 0, 3, 0, 1, 0], "STEPS: the index is the lane's pattern step mod 4 — every lap's step 0, beats 0, 4 and 8")
        assertNothingLeftSounding(stepsMode.tap)
        // …and the setting reaches the snapshot only as a flag: the default is HITS
        XCTAssertFalse(Rig(lines: [lane], emitters: a).box().cells[Snap.euclideousRow].procs[0].emitterRatchets.countsSteps)
    }

    // MARK: - §10 test 6 — CHANCE

    func testChanceIsReplayExactIndependentOfTheBufferSizeAndZeroNeverHundredAlways() {
        func rig(_ chance: Int) -> Rig { Rig(lines: [line()], emitters: emitters([(0, on(steps: 2, hits: 2, chance: chance, strikes: 2))])) }
        let a = play(rig(50), beats: 64), b = play(rig(50), beats: 64), c = play(rig(50), beats: 64, frames: 477)
        XCTAssertEqual(a.events, b.events, "two renders of the same session from the same start give the same strikes")
        XCTAssertEqual(perBeat(a.tap, beats: 64), perBeat(c.tap, beats: 64), "…at any host buffer size")
        let counts = perBeat(a.tap, beats: 64)
        let ratcheted = counts.filter { $0 == 2 }.count
        XCTAssertTrue((16...48).contains(ratcheted), "about half of 64 hits ratchet at CHANCE 50 (got \(ratcheted))")
        XCTAssertTrue(counts.allSatisfy { $0 == 1 || $0 == 2 })
        XCTAssertEqual(perBeat(play(rig(0), beats: 16).tap, beats: 16), [Int](repeating: 1, count: 16), "CHANCE 0 never ratchets")
        XCTAssertEqual(perBeat(play(rig(100), beats: 16).tap, beats: 16), [Int](repeating: 2, count: 16), "CHANCE 100 always does where P is a hit")
        // the hit feed: a ratcheted hit says RATCHED for A, a hit where P was a hit but CHANCE failed says MISSED
        let ratchedBeats = counts.indices.filter { counts[$0] == 2 }, missedBeats = counts.indices.filter { counts[$0] == 1 }
        for bt in ratchedBeats.prefix(6) { XCTAssertEqual(a.nv.first { abs($0.beat - Double(bt)) < 0.01 }?.masks, 0b0000_0001, "beat \(bt): RATCHED A") }
        for bt in missedBeats.prefix(6) { XCTAssertEqual(a.nv.first { abs($0.beat - Double(bt)) < 0.01 }?.masks, 0b0001_0000, "beat \(bt): MISSED A") }
    }

    // MARK: - §10 test 7 — timing

    func testThreeStrikesOnAnEighthLaneAt110BPMStartAtZeroASixthAndAThirdOfABeatEachLastingTheGateShareOfItsSlot() {
        let lane = line(pulses: 8, steps: 8, rate: .r1_8, gate: 0.5)
        let e = play(Rig(lines: [lane], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 3))])), beats: 4, tempo: 110)
        let samplesPerBeat = 48_000.0 * 60 / 110
        let hitBeat = 2.0
        let hitSample = hitBeat * samplesPerBeat
        let strikes = e.tap.ons(1).filter { Double($0.sample) >= hitSample - 2 && Double($0.sample) < hitSample + samplesPerBeat * 0.5 - 2 }
        XCTAssertEqual(strikes.count, 3)
        let slot = samplesPerBeat / 6                                         // 1/6 of a beat = 90.91 ms
        XCTAssertEqual(slot / 48_000 * 1000, 90.909, accuracy: 0.01)
        for (k, s) in strikes.enumerated() {
            XCTAssertEqual(Double(s.sample), hitSample + Double(k) * slot, accuracy: 3, "strike \(k) at hit + k × step ÷ n")
            let off = e.tap.offs(1).first { $0.note == s.note && $0.sample > s.sample }
            XCTAssertEqual(Double(off?.sample ?? 0) - Double(s.sample), slot * 0.5, accuracy: 4, "each lasts the effective gate (50 %) of its slot")
        }
        assertNothingLeftSounding(e.tap)
    }
    func testTheBeatWidthCapLowersNAndAHitThatCapsBelowTwoPlaysOnce() {
        // 1/32 notes at 240 BPM: a step is 0.125 beat = 31.25 ms → at most 3 slots of 10 ms (cap 3); ×4 plays ×3
        let fast = line(pulses: 8, steps: 8, rate: .r1_32)
        let e4 = play(Rig(lines: [fast], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 4))])), beats: 2, tempo: 240)
        let first = e4.tap.ons(1).filter { Double($0.sample) < 48_000.0 * 60 / 240 * 0.125 - 2 }
        XCTAssertEqual(first.count, 3, "the cap (no slot under 10 ms) plays the capped count")
        // a 1/64-ish step: 1/32 at 480 BPM = 15.6 ms → cap 1 → plays once, and is not reported as ratcheted
        let e1 = play(Rig(lines: [fast], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 4))])), beats: 2, tempo: 480)
        let gaps = zip(e1.tap.ons(1), e1.tap.ons(1).dropFirst()).map { Double($1.sample - $0.sample) }
        XCTAssertFalse(gaps.isEmpty)
        XCTAssertTrue(gaps.allSatisfy { abs($0 - 750) < 3 }, "capped below 2: every hit (one every 1/32 = 15.6 ms = 750 samples at 480 BPM) plays once — no strike lands between the hits")
        XCTAssertTrue(e1.nv.allSatisfy { $0.masks & 0x0F == 0 }, "…and none is reported as RATCHETED")
    }

    // MARK: - §10 test 8 — per output

    func testOnlyTheRatchetingOutputRatchetsAndTheOthersPlayTheirCopyOnce() {
        // lane 1: the riff on A, a lit note on B. A ratchets ×2 on every hit.
        let lane = line(litNotes: 0b1, riffOut: 0b0001, notesOut: 0b0010)
        let e = play(Rig(lines: [lane], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 2))])), beats: 4)
        assertNothingLeftSounding(e.tap)
        XCTAssertEqual(perBeat(e.tap, cable: 1, beats: 4), [2, 2, 2, 2], "the riff note strikes twice on A")
        XCTAssertEqual(perBeat(e.tap, cable: 2, beats: 4), [1, 1, 1, 1], "the notes layer's note strikes once on B")
        // one note routed to BOTH outputs: twice on A, once on B
        let both = play(Rig(lines: [line(riffOut: 0b0011, notesOut: 0b0011)], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 2))])), beats: 4)
        assertNothingLeftSounding(both.tap)
        XCTAssertEqual(perBeat(both.tap, cable: 1, beats: 4), [2, 2, 2, 2]); XCTAssertEqual(perBeat(both.tap, cable: 2, beats: 4), [1, 1, 1, 1])
        // ALL carries each output's strikes on that output's channel: A's two, B's one
        XCTAssertEqual(perBeat(both.tap, cable: 0, beats: 4), [3, 3, 3, 3])
        XCTAssertEqual(Set(both.tap.ons(0).map { $0.chan }), [0, 1], "ALL stamps each copy with its OUTPUT's channel")
        // the other output's copy is exactly what it would have been without the feature
        let without = play(Rig(lines: [line(riffOut: 0b0011, notesOut: 0b0011)]), beats: 4)
        XCTAssertEqual(both.tap.events.filter { $0.cable == 2 }, without.tap.events.filter { $0.cable == 2 }, "B's copy is bit-identical to a run with no ratchets")
    }

    // MARK: - §10 test 9 — FX RATCH on the hit, and an output's own ratchet

    func testAnOutputsRatchetReplacesTheHitsOwnCountOnThatOutputOnly() {
        // riff on A and B; column 3 carries FX RATCH ×2 (beat 3, 11…); A always ratchets ×4.
        var fx = EuclideousFX(); fx.cells[0 * 8 + 3] = 2
        let e = play(Rig(lines: [line(riffOut: 0b0011, notesOut: 0b0011)], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 4))]), fx: fx), beats: 8)
        assertNothingLeftSounding(e.tap)
        XCTAssertEqual(perBeat(e.tap, cable: 1, beats: 8), [4, 4, 4, 4, 4, 4, 4, 4], "A: four strikes everywhere — its own n replaces the hit's")
        XCTAssertEqual(perBeat(e.tap, cable: 2, beats: 8), [1, 1, 1, 2, 1, 1, 1, 1], "B: the hit's own FX RATCH ×2 still applies on every other output")
    }

    // MARK: - §10 test 10 — legato

    func testARatchetedCopyClosesTheNoteHeldOnItsOutputAndNotesHeldElsewhereCarryOnAsToday() {
        // GATE 100 (raw): the riff on A, a lit note on B; both held legato. A ratchets at hit 1 only (STEPS 4, HITS 1, OFFSET 3 puts P's hit on index 1).
        let lane = line(gate: 1.0, litNotes: 0b1, riffOut: 0b0001, notesOut: 0b0010)
        var legatoLane = lane; legatoLane.notesGate = 1.0
        let withR = play(Rig(lines: [legatoLane], emitters: emitters([(0, on(steps: 4, hits: 1, offset: 3, strikes: 3))])), beats: 6)
        let without = play(Rig(lines: [legatoLane]), beats: 6)
        assertNothingLeftSounding(withR.tap)
        // the note held on B carries on exactly as today: B's stream is bit-identical to the run with no ratchets
        XCTAssertEqual(withR.tap.events.filter { $0.cable == 2 }, without.tap.events.filter { $0.cable == 2 }, "B's held note is untouched")
        XCTAssertEqual(withR.tap.ons(2).count, 1, "…and it is still the one legato note")
        // A: the note held from hit 0 ends at the ratcheted hit (beat 1, within the 10 ms overlap), and hit 1 sounds as three separate strikes
        let heldOff = withR.tap.offs(1).first!
        XCTAssertLessThanOrEqual(Double(heldOff.sample), 24_000 + 0.011 * 48_000 + 2, "the legato note on A closes at the ratcheted hit")
        XCTAssertGreaterThanOrEqual(Double(heldOff.sample), 24_000 - 2)
        let atHit1 = withR.tap.ons(1).filter { $0.sample >= 24_000 - 2 && $0.sample < 48_000 - 2 }
        XCTAssertEqual(atHit1.count, 3, "the ratcheted hit strikes ×3 on A, never carried on legato")
        // …and the unratcheted hits on A are legato as always (a single sounding carried over)
        XCTAssertEqual(withR.tap.ons(1).filter { $0.sample >= 2 * 24_000 - 2 && $0.sample < 4 * 24_000 }.count, 2, "hits 2 and 3 strike once each")
    }
    func testALegatoPitchHeldOnSeveralOutputsLosesItsWholeEntryWhenOneOfThemRatchets() {
        // the documented limit: one pitch held legato on {A, B} whose A copy ratchets changes its output set, so the existing output-aware match does not carry it on — B's copy is struck afresh.
        let lane = line(gate: 1.0, riffOut: 0b0011, notesOut: 0b0011)
        let withR = play(Rig(lines: [lane], emitters: emitters([(0, on(steps: 4, hits: 1, offset: 3, strikes: 3))])), beats: 6)
        assertNothingLeftSounding(withR.tap)
        let bAtHit1 = withR.tap.ons(2).filter { $0.sample >= 24_000 - 2 && $0.sample < 48_000 - 2 }
        XCTAssertEqual(bAtHit1.count, 1, "B's copy re-strikes once at the ratcheted hit (it was not carried on)")
    }

    func testALegatoHoldsEndRecordNamesTheOutputWhoseVoiceClosed() {
        // GATE 100 on a lane routed to B only: the held note's END record (the roll's note end) says output B, so the roll can tell it from a sibling strike of the same pitch and beat
        let lane = line(gate: 1.0, riffOut: 0b0010, notesOut: 0b0010)
        let e = play(Rig(lines: [lane]), beats: 3)
        let ends = e.router.rollRing.drain().filter { $0.isEnd }
        XCTAssertFalse(ends.isEmpty)
        XCTAssertTrue(ends.allSatisfy { $0.outs == 0b0010 }, "every END names its output: \(ends.map { $0.outs })")
    }

    // MARK: - §3.7 / §3.9 — a tie after a ratcheted hit, and cancelling

    func testATieAfterARatchetedHitExtendsTheLastStrikeAndNothingIsLeftSounding() {
        var fx = EuclideousFX(); fx.cells[2 * 8 + 1] = 1                      // TIE on column 1: the hit at beat 1 is tied to beat 0's note
        let e = play(Rig(lines: [line()], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 3))]), fx: fx), beats: 3)
        assertNothingLeftSounding(e.tap)
        XCTAssertEqual(perBeat(e.tap, beats: 3).prefix(2).map { $0 }, [3, 0], "hit 0 ratchets ×3; the tied hit at beat 1 strikes nothing and is not struck again")
        let lastOff = e.tap.offs(1).filter { $0.sample < 48_000 }.map { $0.sample }.max() ?? 0
        XCTAssertGreaterThan(Double(lastOff), 24_000 - 1, "the last strike is carried through the tie")
    }
    func testAStopAndALoadCancelPendingRatchetStrikesLikeFXRatchAndNothingSticks() {
        let rig = Rig(lines: [line()], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 4))]))
        let e = play(rig, beats: 6, frames: 128, restartAt: [2.5], flushAt: [4.3])
        assertNothingLeftSounding(e.tap)
    }

    // MARK: - the hit feed (§3.10)

    func testTheCurrentIndexIsPublishedPerOutputAndClearedAtATransportEdge() {
        let e = play(Rig(lines: [line()], emitters: emitters([(0, on(steps: 4, hits: 1))])), beats: 6)   // the run ends with a STOP window — a transport edge
        XCTAssertEqual(e.router.emitterIndexLive, 0xFFFF_FFFF, "the stop edge restarts the count origin: no index is current any more")
        // …while playing, A's byte is the index of its latest hit and the other outputs publish nothing
        let router = Router(); var diag = KernelDiag(); let tap = Tap()
        let p = NotePool(); for n in pool { p.noteOn(n, velocity: 100, channel: 0) }
        let box = Rig(lines: [line()], emitters: emitters([(0, on(steps: 4, hits: 1))])).box()
        var ts = 0.0
        while ts < 48_000 * 1.3 { router.process(box: box, pool: p, playing: true, beatPos: ts * 2 / 48_000, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 2048, forceColumn: 0, out: tap, diag: &diag); ts += 2048 }
        XCTAssertEqual(router.emitterIndexLive & 0xFF, 2, "hits 0, 1, 2 have happened by beat 2.6 → A's latest index is 2")
        XCTAssertEqual(router.emitterIndexLive >> 8, 0x00FF_FFFF, "B, C and D have taken no hit")
    }
    // MARK: - adversarial review (2026-10-29): the engine reviewer's findings 2 and 3

    /// A beat jump while the transport keeps running (a host loop; free-run handing the clock back) puts every lane on a new beat with no transport edge. The count restarts with them — a loop must repeat, not carry the history of its
    /// previous passes (ferry §2.5: "whenever every lane's rhythm origin restarts together… and whatever else does that today").
    func testALoopJumpWhilePlayingRestartsTheCountSoTheLoopRepeats() {
        let rig = Rig(lines: [line()], emitters: emitters([(0, on(steps: 4, hits: 1, strikes: 3))]))   // a ratchet on hits 0, 4, 8, …
        let r = play(rig, beats: 14, jumpAt: [(6.0, 0.0)])
        let jumpSample = Int64((6.0 * 24_000 / 2048).rounded(.up)) * 2048   // the first window that starts at or after beat 6 is the one that lands on beat 0
        var after = [Int](repeating: 0, count: 8)
        for e in r.tap.ons(1) where e.sample >= jumpSample { let b = Int(Double(e.sample - jumpSample) / 24_000 + 0.001); if b < 8 { after[b] += 1 } }
        XCTAssertEqual(after, [3, 1, 1, 1, 3, 1, 1, 1], "after the jump the first hit is hit 0 again: it ratchets, and so does the fifth")
        assertNothingLeftSounding(r.tap)
    }

    /// Windows that follow each other are not a jump: nothing in a plain run restarts the count (the existing origin tests hold 0, 3, 6, 9 — this pins the same at a small buffer, where a tolerance that was too tight would reset it).
    func testAPlainRunAtASmallBufferNeverRestartsTheCount() {
        let r = play(Rig(lines: [line()], emitters: emitters([(0, on(steps: 3, hits: 1, strikes: 3))])), beats: 12, frames: 64)
        XCTAssertEqual(perBeat(r.tap, beats: 12), (0..<12).map { $0 % 3 == 0 ? 3 : 1 })
    }

    /// A deferred strike on an output that does NOT ratchet follows the part's routing when it falls due, exactly as without the feature: tapping a jack off halfway through a hit stops that output's pending strikes at once, whether or not
    /// ANOTHER output of the same note is ratcheting. (The tail used to freeze "the outputs less the ratcheting one" at the hit.)
    func testPendingStrikesFollowARoutingEditOnAnOutputThatDoesNotRatchet() {
        var fx = EuclideousFX(); for c in 0..<8 { fx.cells[0 * 8 + c] = 3 }   // FX RATCH ×3 on every column
        func rig(routedToC: Bool, aOn: Bool) -> Rig {
            let m: UInt8 = routedToC ? 0b0101 : 0b0001
            return Rig(lines: [line(riffOut: m, notesOut: m)], emitters: aOn ? emitters([(0, on(steps: 2, hits: 2, strikes: 2))]) : EmitterRatchetSet(), fx: fx)
        }
        let swapBeat = 2.0 + 0.15   // hit 2 is struck at beat 2.0; its deferred strikes fall at 2.33 and 2.67
        func cNoteOnsAfterTheSwap(aOn: Bool) -> (before: Int, after: Int) {
            let r = play(rig(routedToC: true, aOn: aOn), beats: 4, frames: 128, swapAt: [(swapBeat, rig(routedToC: false, aOn: aOn))])
            let ons = r.tap.ons(3)
            return (ons.filter { Double($0.sample) <= swapBeat * 24_000 }.count, ons.filter { Double($0.sample) > swapBeat * 24_000 }.count)
        }
        let without = cNoteOnsAfterTheSwap(aOn: false), with = cNoteOnsAfterTheSwap(aOn: true)
        XCTAssertEqual(without.after, 0, "control: with the emitter off, un-jacking C stops its pending FX-ratchet strikes")
        XCTAssertEqual(with.after, 0, "…and with A ratcheting it stops them just the same")
        XCTAssertEqual(with.before, without.before, "C's strikes before the edit are the same either way: A's ratchet is A's alone")
    }
    /// The ratchet's OWN pending strikes follow the part's routing when they fall due, as FX RATCH's do: un-jack A halfway through a hit A ratchets and the strikes still to come on A stop (they used to ring on A, frozen at the hit),
    /// while C — which never ratcheted — keeps its one ordinary copy per hit.
    func testAnOutputsPendingRatchetStrikesStopWhenItsJackIsTappedOff() {
        func rig(routedToA: Bool) -> Rig {
            let m: UInt8 = routedToA ? 0b0101 : 0b0100
            return Rig(lines: [line(riffOut: m, notesOut: m)], emitters: emitters([(0, on(steps: 2, hits: 2, strikes: 3))]))   // A ratchets ×3 on every hit: strikes at +0, +⅓, +⅔ of the beat
        }
        let swapBeat = 2.0 + 0.15
        let r = play(rig(routedToA: true), beats: 4, frames: 128, swapAt: [(swapBeat, rig(routedToA: false))])
        let aAfter = r.tap.ons(1).filter { Double($0.sample) > swapBeat * 24_000 && Double($0.sample) < 3.0 * 24_000 - 100 }.count
        XCTAssertEqual(aAfter, 0, "A's pending strikes at 2.33 and 2.67 do not sound once A is un-jacked")
        XCTAssertEqual(r.tap.ons(1).filter { Double($0.sample) >= 2.0 * 24_000 - 100 && Double($0.sample) <= swapBeat * 24_000 }.count, 1, "…and the strike already struck before the edit stays")
        XCTAssertEqual(r.tap.ons(3).filter { Double($0.sample) >= 2.0 * 24_000 - 100 && Double($0.sample) < 3.0 * 24_000 - 100 }.count, 1, "C's ordinary copy of the hit is untouched")
        assertNothingLeftSounding(r.tap)
    }
}
