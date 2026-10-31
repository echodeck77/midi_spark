//  ChordCanonTests.swift — CHORD CANON ferry (2026-10-31): a lane reads the CHORDS layer behind the host beat. The pure side (`euclideousCanon*`), the model fields, and the Router against the real engine: four chords
//  a bar each (I IV V vi of the default C natural minor), lanes that hit once a beat on rank 1 of a flat riff — so each hit plays the ROOT of the chord the lane is reading at that beat.

import XCTest

private final class CanonEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let status: UInt8; let note: UInt8 }
    private(set) var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) { events.append(Ev(sample: sampleTime, cable: cable, status: b0 & 0xF0, note: b1)) }
    var ons: [Ev] { events.filter { $0.status == 0x90 } }
}

final class ChordCanonTests: XCTestCase {
    private let beat: Int64 = 24_000                         // 120 BPM at 48 kHz
    private let degrees = [0, 3, 4, 5]                       // I IV V vi, one chord a bar

    // MARK: the music

    /// The ROOT (lowest note) of the chord at progression step `k` (any integer: the progression loops).
    private func root(_ k: Int) -> UInt8 {
        var cs = MachineParams(); cs.chordsDegrees = degrees; cs.chordsSteps = 4
        let deg = degrees[((k % 4) + 4) % 4]
        return UInt8(diatonicChord(degree: deg, scaleTones: ScaleType.naturalMinor.intervals, rootNote: 48, voicing: cs.chordsVoicingResolved, spread: cs.chordsSpreadResolved).min()!)
    }
    private func lane(pulses: Int = 4, steps: Int = 4, delay: Int? = nil, slip: Int? = nil, octave: Int = 0, dir: EuclidDir = .fwd) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: pulses, steps: steps)
        l.gate = 0.5; l.velocityAbsolute = 90; l.rate = .r1_4; l.useRiff = true; l.riffOn = true; l.sourceMode = .midi; l.notesOn = true; l.litNotes = 0
        l.chordDelay = delay; l.chordSlip = slip; l.riffOctave = octave; l.direction = dir
        return l
    }
    private func state(_ lines: [EuclidLine], unit: CanonUnit? = nil, entry: CanonEntry? = nil, chords: Bool = true) -> PluginState {
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 1, 1, 1, 1, 1, 1, 1])
        c.paramsA.euclidLines = lines
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        var st = PluginState(machines: machineIDs.map { $0 == "gold" ? c : Machine(machineID: $0, type: .arp) }, scenes: [sc])
        var cs = MachineParams(); cs.chordsDegrees = degrees; cs.chordsSteps = 4; cs.chordsRate = .r1_1
        st.euclideousChordSets = [cs, MachineParams(), MachineParams(), MachineParams()]
        st.euclideousSourcePlan = SourcePlan(midiOn: false, chordsOn: chords, pickOn: false, keyOn: !chords, midiMode: .add, pickNotes: [])
        st.euclideousCanonUnit = unit; st.euclideousCanonEntry = entry
        return st
    }
    private func run(_ st: PluginState, beats: Double, frames: UInt32 = 2048) -> CanonEmitter {
        let box = SnapshotBuilder.build(from: st)
        let e = CanonEmitter(); let router = Router(); var diag = KernelDiag()
        let tempo = 120.0, sr = 48_000.0
        let p = NotePool()
        var ts = 0.0
        func beatNow() -> Double { ts * tempo / 60.0 / sr }
        while beatNow() < beats {
            router.process(box: box, pool: p, playing: true, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, forceColumn: 0, out: e, diag: &diag)
            ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beatNow(), tempo: tempo, sampleRate: sr, timestampSample: ts, frameCount: frames, out: e, diag: &diag)
        return e
    }
    /// The note each beat (0…) sounds on one cable (-1 = nothing struck on that beat).
    private func notes(_ e: CanonEmitter, cable: UInt8, beats: Int) -> [Int] {
        var out = [Int](repeating: -1, count: beats)
        for ev in e.ons where ev.cable == cable {
            let b = Int((Double(ev.sample) / Double(beat)).rounded())
            if b >= 0 && b < beats { out[b] = Int(ev.note) }
        }
        return out
    }
    private func expected(_ beats: Int, delayBeats: Double, slip: Int = 0, lane: Int = 0, clampFromZero: Bool = false) -> [Int] {
        (0..<beats).map { b in
            var k = Int(((Double(b) - delayBeats + 1e-9) / 4).rounded(.down))
            if slip > 0 && euclideousCanonSlipRoll(lane: lane, step: k) < slip { k -= 1 }
            return Int(root(clampFromZero ? max(0, k) : k))
        }
    }

    // MARK: the engine

    func testAnUndelayedLaneFollowsTheProgression() {
        let e = run(state([lane()]), beats: 16)
        XCTAssertEqual(notes(e, cable: 1, beats: 16), expected(16, delayBeats: 0))
    }
    func testADelayedLaneIsAnExactTimeShiftOfTheSameSequence() {
        // Lane 2 is one BAR behind lane 1: the same four chords, four beats later — a canon, not a lag that converges.
        let e = run(state([lane(), lane(delay: 1)], unit: .bars), beats: 24)
        let a = notes(e, cable: 1, beats: 24), b = notes(e, cable: 2, beats: 24)
        XCTAssertEqual(a, expected(24, delayBeats: 0))
        XCTAssertEqual(b, expected(24, delayBeats: 4))
        for t in 4..<24 { XCTAssertEqual(b[t], a[t - 4], "beat \(t): the delayed lane plays what the first lane played four beats ago") }
        XCTAssertNotEqual(a[8], b[8], "a suspension: the lanes sound different chords at the same time")
    }
    func testAPassIsTheLanesOwnLap() {
        // A 5-step lane at 1/4 has a 5-beat pass; one pass of delay is five beats (not a bar, not the 4-step lane's four).
        let e = run(state([lane(pulses: 5, steps: 5, delay: 1), lane(delay: 1)], unit: .passes), beats: 24)
        XCTAssertEqual(notes(e, cable: 1, beats: 24), expected(24, delayBeats: 5))
        XCTAssertEqual(notes(e, cable: 2, beats: 24), expected(24, delayBeats: 4), "the 4-step lane's pass is four beats")
    }
    func testAPingPongPassIsTwiceTheSteps() {
        let e = run(state([lane(delay: 1, dir: .pingpong)], unit: .passes), beats: 24)
        XCTAssertEqual(notes(e, cable: 1, beats: 24), expected(24, delayBeats: 8), "PING-PONG's lap is 2n ticks")
    }
    func testStepsAreTheLanesOwnStep() {
        let e = run(state([lane(delay: 3)], unit: .steps), beats: 16)
        XCTAssertEqual(notes(e, cable: 1, beats: 16), expected(16, delayBeats: 3))
    }
    func testEveryLaneKeepsItsOwnPoolWhateverTheOrderOfTheLanes() {
        // The shared pool buffer is re-keyed lane by lane: an undelayed lane that runs after a delayed one must sound exactly as it does when nothing is delayed.
        let plain = run(state([lane(), lane(), lane(), lane()]), beats: 20)
        let mixed = run(state([lane(), lane(delay: 2), lane(), lane(delay: 1, slip: 20)], unit: .bars), beats: 20)
        for c in [UInt8(1), 3] { XCTAssertEqual(notes(mixed, cable: c, beats: 20), notes(plain, cable: c, beats: 20), "cable \(c)") }
        XCTAssertEqual(notes(mixed, cable: 2, beats: 20), expected(20, delayBeats: 8))
        XCTAssertEqual(notes(mixed, cable: 4, beats: 20), expected(20, delayBeats: 4, slip: 20, lane: 3))
    }
    func testNilAndZeroAreTheSameDocument() {
        let a = run(state([lane(), lane(delay: 0, slip: 0)]), beats: 12)
        let b = run(state([lane(), lane()]), beats: 12)
        XCTAssertEqual(a.events, b.events)
    }
    func testTheDelayIsInertWithoutTheChordsLayer() {
        // KEY is not a function of the beat: nothing to shift, so a delayed lane sounds as an undelayed one.
        let a = run(state([lane(delay: 2)], unit: .bars, chords: false), beats: 12)
        let b = run(state([lane()], chords: false), beats: 12)
        XCTAssertEqual(a.events, b.events)
    }
    func testTheLaneTransformsComeAfterTheDelay() {
        let e = run(state([lane(delay: 1, octave: 1)], unit: .bars), beats: 16)
        XCTAssertEqual(notes(e, cable: 1, beats: 16), expected(16, delayBeats: 4).map { $0 + 12 })
    }
    func testSlipHoldsThePreviousChordForOneChordStep() {
        let e = run(state([lane(slip: 50)]), beats: 64)
        let got = notes(e, cable: 1, beats: 64)
        XCTAssertEqual(got, expected(64, delayBeats: 0, slip: 50))
        XCTAssertNotEqual(got, expected(64, delayBeats: 0), "50% slip over 16 chord steps misses at least one change")
    }
    func testTheSoundDoesNotDependOnTheBufferSize() {
        let st = state([lane(), lane(delay: 1, slip: 25), lane(delay: 2), lane(pulses: 5, steps: 5, delay: 1, slip: 10)], unit: .passes)
        let small = run(st, beats: 24, frames: 96), big = run(st, beats: 24, frames: 4096)
        // (The hit's SAMPLE can differ by one between buffer sizes — the engine's own rounding, nothing to do with the canon — so compare what sounds on which beat, and how many messages each output sent.)
        for c in UInt8(1)...4 {
            XCTAssertEqual(notes(small, cable: c, beats: 24), notes(big, cable: c, beats: 24), "cable \(c)")
            XCTAssertEqual(small.events.filter { $0.cable == c }.count, big.events.filter { $0.cable == c }.count, "cable \(c)")
        }
    }
    func testAHostBeatBeforeTheSongIsAWrappedRound() {
        // ENTRY WRAP (the release behaviour): a lane a bar behind is, at beat 0, on the chord from the END of the cycle.
        let e = run(state([lane(delay: 1)], unit: .bars), beats: 8)
        XCTAssertEqual(notes(e, cable: 1, beats: 8)[0], Int(root(3)))
    }
    #if DEBUG
    func testEntryStartOnChordOneHoldsTheFirstChordUntilItsTurn() {
        let e = run(state([lane(delay: 2)], unit: .bars, entry: .firstChord), beats: 16)
        XCTAssertEqual(notes(e, cable: 1, beats: 16), expected(16, delayBeats: 8, clampFromZero: true))
        XCTAssertEqual(Set(notes(e, cable: 1, beats: 16)[0..<8]), [Int(root(0))], "two bars of chord 1 before the delay has run out")
    }
    func testEntryWaitIsSilentUntilTheDelayHasRunOut() {
        let e = run(state([lane(), lane(delay: 2)], unit: .bars, entry: .wait), beats: 16)
        let b = notes(e, cable: 2, beats: 16)
        XCTAssertEqual(Array(b[0..<8]), [Int](repeating: -1, count: 8), "no chord yet: the chord layer is a rest")
        XCTAssertEqual(Array(b[8..<16]), expected(16, delayBeats: 8)[8..<16].map { $0 })
        XCTAssertEqual(notes(e, cable: 1, beats: 16), expected(16, delayBeats: 0), "an undelayed lane never waits")
    }
    #endif

    // MARK: the pure functions

    func testUnitBeatsAndDelayBeats() {
        XCTAssertEqual(euclideousCanonDelayBeats(delay: 3, unit: .steps, stepBeats: 0.25, lapBeats: 4, barBeats: 4), 0.75)
        XCTAssertEqual(euclideousCanonDelayBeats(delay: 3, unit: .passes, stepBeats: 0.25, lapBeats: 1.25, barBeats: 4), 3.75)
        XCTAssertEqual(euclideousCanonDelayBeats(delay: 3, unit: .bars, stepBeats: 0.25, lapBeats: 1.25, barBeats: 3), 9)
        XCTAssertEqual(euclideousCanonDelayBeats(delay: 99, unit: .bars, stepBeats: 1, lapBeats: 1, barBeats: 4), 32, "the delay is capped at 8 units")
        XCTAssertEqual(euclideousCanonDelayBeats(delay: -2, unit: .bars, stepBeats: 1, lapBeats: 1, barBeats: 4), 0)
        XCTAssertEqual(euclideousCanonDelayBeats(delay: 2, unit: .passes, stepBeats: 1, lapBeats: .nan, barBeats: 4), 0)
    }
    func testChordReadIsTheFloorOfTheShiftedBeat() {
        func step(_ m: Double, d: Double) -> Int { euclideousCanonChordRead(beat: m, rateBeats: 4, delayBeats: d, slipPercent: 0, entry: .wrap, lane: 0).step }
        XCTAssertEqual(step(8, d: 0), 2); XCTAssertEqual(step(8, d: 4), 1); XCTAssertEqual(step(7.999, d: 4), 0); XCTAssertEqual(step(3, d: 4), -1)
        XCTAssertEqual(step(8 - 1e-12, d: 0), 2, "a tick a hair under a chord boundary belongs to the new chord")
        XCTAssertEqual(step(12, d: 4 + 1e-12), 2, "…and so does float noise in the delay")
    }
    func testEntryModesOnlyChangeTheTimeBeforeBeatZero() {
        for m in stride(from: 0.0, to: 40, by: 0.5) {
            let wrap = euclideousCanonChordRead(beat: m, rateBeats: 4, delayBeats: 8, slipPercent: 0, entry: .wrap, lane: 1)
            let first = euclideousCanonChordRead(beat: m, rateBeats: 4, delayBeats: 8, slipPercent: 0, entry: .firstChord, lane: 1)
            let wait = euclideousCanonChordRead(beat: m, rateBeats: 4, delayBeats: 8, slipPercent: 0, entry: .wait, lane: 1)
            if m >= 8 { XCTAssertEqual(wrap, first); XCTAssertEqual(wrap, wait); XCTAssertFalse(wait.waiting) }
            else { XCTAssertEqual(first.step, 0); XCTAssertTrue(wait.waiting); XCTAssertLessThan(wrap.step, 0) }
        }
    }
    func testSlipIsStatelessBoundedAndRoughlyTheAskedPercent() {
        var held = 0
        let n = 4000
        for k in 0..<n {
            let m = Double(k) * 4 + 1
            let r = euclideousCanonChordRead(beat: m, rateBeats: 4, delayBeats: 0, slipPercent: 20, entry: .wrap, lane: 2)
            XCTAssertTrue(r.step == k || r.step == k - 1, "never more than one chord step behind")
            XCTAssertEqual(r, euclideousCanonChordRead(beat: m, rateBeats: 4, delayBeats: 0, slipPercent: 20, entry: .wrap, lane: 2), "replay-exact")
            if r.step == k - 1 { held += 1 }
        }
        XCTAssertEqual(Double(held) / Double(n), 0.20, accuracy: 0.03)
        XCTAssertEqual(euclideousCanonChordRead(beat: 9, rateBeats: 4, delayBeats: 0, slipPercent: 0, entry: .wrap, lane: 2).step, 2, "SLIP 0 never misses")
        // a different lane rolls differently
        let a = (0..<200).map { euclideousCanonSlipRoll(lane: 0, step: $0) }, b = (0..<200).map { euclideousCanonSlipRoll(lane: 1, step: $0) }
        XCTAssertNotEqual(a, b)
    }
    func testSlipSnapsToFives() {
        XCTAssertEqual([-3, 0, 2, 3, 7, 8, 12, 49, 99].map { EuclidLine.legalCanonSlip($0) }, [0, 0, 0, 5, 5, 10, 10, 50, 50])
    }

    // MARK: the CANON row

    func testTheRowIsInertWhenThereIsNothingToShift() {
        XCTAssertNil(euclideousCanonInertReason(chordsOn: true, pitch: .own))
        XCTAssertNil(euclideousCanonInertReason(chordsOn: true, pitch: .avoid), "AVOID plays the lane's own riff from its own pool")
        XCTAssertEqual(euclideousCanonInertReason(chordsOn: false, pitch: .own), "CHORDS is off")
        XCTAssertNotNil(euclideousCanonInertReason(chordsOn: true, pitch: .shadow)); XCTAssertNotNil(euclideousCanonInertReason(chordsOn: true, pitch: .echo))
        XCTAssertEqual(euclideousCanonInertReason(chordsOn: false, pitch: .echo), "CHORDS is off", "the first reason wins")
    }
    func testTheFooterExplainsASetRowThatHasNoEffect() {
        XCTAssertNil(euclideousCanonInertCaption(chordsOn: false, pitch: .own, delay: 0, slip: 0), "nothing set, nothing to explain")
        XCTAssertNil(euclideousCanonInertCaption(chordsOn: true, pitch: .own, delay: 2, slip: 10), "a live row has no caption")
        XCTAssertNil(euclideousCanonInertCaption(chordsOn: true, pitch: .avoid, delay: 2, slip: 0))
        XCTAssertEqual(euclideousCanonInertCaption(chordsOn: false, pitch: .own, delay: 1, slip: 0), "CANON UNUSED: TURN ON CHORDS IN SOURCES")
        XCTAssertNotNil(euclideousCanonInertCaption(chordsOn: false, pitch: .own, delay: 0, slip: 5), "a SLIP alone is set too")
        XCTAssertNotNil(euclideousCanonInertCaption(chordsOn: true, pitch: .shadow, delay: 1, slip: 0)); XCTAssertNotNil(euclideousCanonInertCaption(chordsOn: true, pitch: .echo, delay: 1, slip: 0))
        for c in [euclideousCanonInertCaption(chordsOn: false, pitch: .own, delay: 1, slip: 0)!, euclideousCanonInertCaption(chordsOn: true, pitch: .echo, delay: 1, slip: 0)!] {
            XCTAssertLessThanOrEqual(c.count, 44, "one 11 pt line on the card: \(c)")
        }
    }
    func testTheSteppersClampAndNeverWrap() {
        XCTAssertEqual(euclideousCanonDelayMoved(0, by: -1), 0); XCTAssertEqual(euclideousCanonDelayMoved(8, by: 1), 8); XCTAssertEqual(euclideousCanonDelayMoved(3, by: 1), 4)
        XCTAssertEqual(euclideousCanonSlipMoved(0, by: -1), 0); XCTAssertEqual(euclideousCanonSlipMoved(50, by: 1), 50); XCTAssertEqual(euclideousCanonSlipMoved(10, by: 1), 15); XCTAssertEqual(euclideousCanonSlipMoved(5, by: -1), 0)
        XCTAssertEqual(euclideousCanonUnitMoved(.steps, by: -1), .steps); XCTAssertEqual(euclideousCanonUnitMoved(.bars, by: 1), .bars)
        XCTAssertEqual(euclideousCanonUnitMoved(.steps, by: 1), .passes); XCTAssertEqual(euclideousCanonUnitMoved(.bars, by: -1), .passes)
        // 0 round-trips through nil: a lane that is stepped back to 0 stores nothing, so its document is the one that never had the field.
        var l = EuclidLine(target: 0, pulses: 4, steps: 4)
        let up = euclideousCanonDelayMoved(l.chordDelayResolved, by: 1); l.chordDelay = up == 0 ? nil : up
        let down = euclideousCanonDelayMoved(l.chordDelayResolved, by: -1); l.chordDelay = down == 0 ? nil : down
        XCTAssertEqual(l, EuclidLine(target: 0, pulses: 4, steps: 4))
    }
    func testTheRowSaysWhatItDoes() {
        XCTAssertEqual(euclideousCanonDelayText(2), "2"); XCTAssertEqual(euclideousCanonDelayText(99), "8"); XCTAssertEqual(euclideousCanonSlipText(10), "10%"); XCTAssertEqual(euclideousCanonSlipText(0), "0%")
        XCTAssertEqual(euclideousCanonDelaySpoken(delay: 0, unit: .passes, inert: nil), "off")
        XCTAssertEqual(euclideousCanonDelaySpoken(delay: 1, unit: .passes, inert: nil), "1 pass"); XCTAssertEqual(euclideousCanonDelaySpoken(delay: 3, unit: .bars, inert: nil), "3 bars")
        XCTAssertEqual(euclideousCanonDelaySpoken(delay: 2, unit: .steps, inert: "CHORDS is off"), "2 steps, no effect: CHORDS is off")
        XCTAssertEqual(euclideousCanonSlipSpoken(slip: 15, inert: nil), "15 percent"); XCTAssertEqual(euclideousCanonSlipSpoken(slip: 0, inert: nil), "off")
        XCTAssertEqual(euclideousCanonUnitSpoken(.passes), "passes")
    }

    // MARK: the document

    func testTheFieldsRoundTripAndDecodeTolerantly() throws {
        var l = EuclidLine(target: 0, pulses: 4, steps: 4); l.chordDelay = 3; l.chordSlip = 15
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.chordDelay, 3); XCTAssertEqual(back.chordSlip, 15)
        let old = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(EuclidLine(target: 0, pulses: 4, steps: 4)))
        XCTAssertNil(old.chordDelay); XCTAssertNil(old.chordSlip); XCTAssertEqual(old.chordDelayResolved, 0); XCTAssertEqual(old.chordSlipResolved, 0)
        // wrong types read as missing; out-of-range values clamp.
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(l)) as! [String: Any]
        json["chordDelay"] = "three"; json["chordSlip"] = 99
        let bad = try JSONDecoder().decode(EuclidLine.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(bad.chordDelay); XCTAssertEqual(bad.chordSlip, 50)
        json["chordDelay"] = 40
        XCTAssertEqual(try JSONDecoder().decode(EuclidLine.self, from: JSONSerialization.data(withJSONObject: json)).chordDelay, euclideousCanonMaxDelay)
    }
    func testThePageFieldsRoundTripAndAnUnknownValueReadsAsTheDefault() throws {
        var st = PluginState(machines: [], scenes: [SceneState.empty()])
        XCTAssertEqual(st.canonUnitResolved, .passes)
        st.euclideousCanonUnit = .bars; st.euclideousCanonEntry = .wait
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.euclideousCanonUnit, .bars); XCTAssertEqual(back.euclideousCanonEntry, .wait)
        XCTAssertEqual(try JSONDecoder().decode(CanonUnit.self, from: Data("\"FORTNIGHTS\"".utf8)), .passes)
        XCTAssertEqual(try JSONDecoder().decode(CanonEntry.self, from: Data("\"SIDEWAYS\"".utf8)), .wrap)
        #if !DEBUG
        XCTAssertEqual(st.canonEntryResolved, .wrap, "a release build always wraps")
        #endif
    }
    func testTheSnapshotCarriesTheLaneFieldsAndThePageFields() {
        let box = SnapshotBuilder.build(from: state([lane(delay: 3, slip: 15), lane()], unit: .bars, entry: nil))
        let p = box.cells[0 * Snap.rows + Snap.euclideousRow].procs[0]
        XCTAssertEqual(p.euclidLines[0].chordDelay, 3); XCTAssertEqual(p.euclidLines[0].chordSlip, 15); XCTAssertNil(p.euclidLines[1].chordDelay)
        XCTAssertEqual(p.canonUnit, .bars); XCTAssertEqual(p.canonEntry, .wrap)
    }
}
