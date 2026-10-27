//  HocketRouterTests.swift — HOCKET ferry (2026-10-27) §12 tests 5–12, 15 and 18: the engine, through a real Router.
//  "Unless stated, each lane is 8 steps of 1/16 at 120 BPM with hits on steps 1, 3, 5 and 7, riff and notes on, every output on its own channel, the transport from bar 1." Lanes 1–4 are RED, BLUE, AMBER, GREEN.
//  Beats: 120 BPM at 48 kHz = 24,000 samples a beat. A lane's hits fall on beats 0, 0.5, 1.0, 1.5 of each 2-beat pass. The outputs are cables: 0 = ALL, RED RIFF 1, RED NOTES 2, BLUE RIFF 3, BLUE NOTES 4, AMBER RIFF 5,
//  AMBER NOTES 6, GREEN RIFF 7, GREEN NOTES 8. Each lane plays its OWN octave (RED +1, BLUE −1, AMBER +2, GREEN −2) over a held C-major triad, so the pitch says which lane a note came from.

import XCTest

private final class HEmitter: MIDIEmitter {
    struct Ev: Equatable { let sample: Int64; let cable: UInt8; let on: Bool; let chan: UInt8; let note: UInt8; let vel: UInt8
        var beat: Double { (Double(sample) / 24_000 * 1000).rounded() / 1000 } }   // to the millisecond: a hit at beat 0.5 may land on sample 11999
    var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let st = b0 & 0xF0
        guard st == 0x90 || st == 0x80 else { return }
        events.append(Ev(sample: sampleTime, cable: cable, on: st == 0x90 && b2 > 0, chan: b0 & 0x0F, note: b1, vel: b2))
    }
    func ons(_ cable: UInt8) -> [Ev] { events.filter { $0.cable == cable && $0.on }.sorted { ($0.sample, $0.note) < ($1.sample, $1.note) } }
    func offs(_ cable: UInt8) -> [Ev] { events.filter { $0.cable == cable && !$0.on }.sorted { ($0.sample, $0.note) < ($1.sample, $1.note) } }
    func all(_ cable: UInt8) -> [Ev] { events.filter { $0.cable == cable } }
}

final class HocketRouterTests: XCTestCase {
    // cables
    private let redRiff: UInt8 = 1, redNotes: UInt8 = 2, blueRiff: UInt8 = 3, blueNotes: UInt8 = 4, amberRiff: UInt8 = 5, amberNotes: UInt8 = 6, greenRiff: UInt8 = 7, greenNotes: UInt8 = 8
    // the same outputs as a rule stores them (cables 1…8)
    private let RR = 1, RN = 2, BR = 3, BN = 4, AR = 5, AN = 6, GR = 7, GN = 8

    private func rule(main: [Int], alt: [Int], _ configure: (inout HocketRule) -> Void = { _ in }) -> HocketRule {
        var r = HocketRule(); r.main = main; r.alt = alt; configure(&r); return r
    }

    /// A lane as the spec describes: 8 steps of 1/16, hits on steps 1, 3, 5, 7 (E(4, 8)), riff and notes both on (the notes layer lights rank 1), in its own octave.
    private func laneLine(_ i: Int, riff: Bool = true, notes: Bool = true) -> EuclidLine {
        var l = EuclidLine()
        l.enabled = true; l.pulses = 4; l.steps = 8; l.rotate = 0; l.rate = .r1_16
        let oct = [1, -1, 2, -2][i]
        l.octave = oct; l.riffOctave = oct
        l.riffOn = riff; l.useRiff = riff
        l.litNotes = notes ? 0b0000_0001 : 0; l.notesWhen = 0b11; l.notesPlayAs = .chord; l.notesOn = notes
        l.gate = 0.5; l.notesGate = 0.5
        return l
    }
    private func doc(lanes: [EuclidLine]? = nil, rules: [HocketRule] = [], rawGates: Bool = false, configure: (inout PluginState) -> Void = { _ in }) -> PluginState {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        st.euclideousLines = lanes ?? (0..<4).map { laneLine($0) }
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(); st.euclideousSoloMask = 0
        st.hocketRules = rules.isEmpty ? nil : HocketRuleSet(rules)
        configure(&st)
        let ls = rawGates ? st.euclideousLines! : st.euclideousLinesResolved     // raw: gate 1.0 (legato) reaches the engine, as the stress tests feed it
        let input = FourfoldCompose.Input(lines: ls, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: st.activeRiffResolved,
                                          soloMask: st.euclideousSoloMaskResolved, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        return st
    }
    /// Play from bar 1 for `beats`, then stop. A held C-major triad.
    private func render(_ st: PluginState, beats: Double, frames: UInt32 = 480) -> HEmitter {
        let box = SnapshotBuilder.build(from: st)
        let pool = NotePool(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        let router = Router(); var diag = KernelDiag(); let e = HEmitter()
        let total = Int(beats * 24_000) - 1                                   // the window ends just short of `beats`, so a hit exactly on it belongs to the next stretch
        var done = 0, beat = 0.0, ts = 0.0
        while done < total {
            let n = UInt32(min(Int(frames), total - done))
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: n, out: e, diag: &diag)
            done += Int(n); beat += Double(n) * 120.0 / 60 / 48_000; ts += Double(n)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        return e
    }
    private func beats(_ evs: [HEmitter.Ev]) -> [Double] { evs.map { $0.beat } }
    private func chanNibble(_ cable: UInt8) -> UInt8 { cable - 1 }                    // default channels: port c → channel c (wire nibble c − 1)
    private let lane1Octave = 12, lane2Octave = -12
    /// Every note of an output: no note-on is left without its off, per (cable, channel, note).
    private func assertBalanced(_ e: HEmitter, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        var bal: [Int: Int] = [:]
        for ev in e.events { bal[(Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note), default: 0] += ev.on ? 1 : -1 }
        XCTAssertTrue(bal.values.allSatisfy { $0 == 0 }, "no stuck note \(msg)", file: file, line: line)
        var orphan = 0
        var run: [Int: Int] = [:]
        for ev in e.events {                                                       // in emission order, as the host receives them
            let k = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            run[k, default: 0] += ev.on ? 1 : -1
            if run[k]! < 0 { orphan += 1 }
        }
        XCTAssertEqual(orphan, 0, "no orphan off \(msg)", file: file, line: line)
    }

    // MARK: - the fixture itself

    func testTheBaselineEveryLaneSoundsOnItsOwnTwoOutputsAndAllCarriesAllEight() {
        let e = render(doc(), beats: 4)
        for c in UInt8(1)...8 {
            XCTAssertEqual(beats(e.ons(c)), [0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 3.5], "cable \(c) sounds on every hit of its lane")
            XCTAssertTrue(e.ons(c).allSatisfy { $0.chan == chanNibble(c) }, "…on its own channel")
        }
        XCTAssertEqual(e.ons(0).count, 64, "ALL carries every note of every output")
        // each lane plays its own octave: the pitch says where a note came from
        XCTAssertTrue(e.ons(redNotes).allSatisfy { [72, 76, 79].contains(Int($0.note)) }, "RED NOTES: a C-major triad one octave up, got \(e.ons(redNotes).map { $0.note })")
        XCTAssertTrue(e.ons(blueNotes).allSatisfy { [48, 52, 55].contains(Int($0.note)) }, "BLUE NOTES: one octave down, got \(e.ons(blueNotes).map { $0.note })")
        assertBalanced(e)
    }

    // MARK: - test 5 — swap together

    func testSwapTogetherRedRiffThreeHitsBlueRiffTheFourth() {
        let rules = [rule(main: [RR], alt: [BR]) { $0.mainLen = 3; $0.altLen = 1 }]
        let e = render(doc(rules: rules), beats: 4), base = render(doc(), beats: 4)
        XCTAssertEqual(beats(e.ons(redRiff)), [0, 0.5, 1.0, 2.0, 2.5, 3.0], "RED RIFF sounds from hits 1–3 of each four")
        XCTAssertEqual(beats(e.ons(blueRiff)), [1.5, 3.5], "BLUE RIFF only between the 4th hit and the next 1st")
        for c in [redNotes, blueNotes, amberRiff, amberNotes, greenRiff, greenNotes] { XCTAssertEqual(e.all(c), base.all(c), "cable \(c) is untouched") }
        XCTAssertEqual(e.ons(0).count, (1...8).reduce(0) { $0 + e.ons(UInt8($1)).count }, "ALL carries exactly what left on the eight outputs")
        assertBalanced(e)
    }

    // MARK: - test 6 — swap rotate

    func testSwapRotateAltTurnsAlternateBlueRiffAndAmberRiff() {
        let rules = [rule(main: [RR], alt: [BR, AR]) { $0.several = .rotate }]
        let e = render(doc(rules: rules), beats: 4)
        XCTAssertEqual(beats(e.ons(redRiff)), [0, 1.0, 2.0, 3.0], "MAIN turns: every other hit")
        XCTAssertEqual(beats(e.ons(blueRiff)), [0.5, 2.5], "ALT turn 1 → BLUE RIFF")
        XCTAssertEqual(beats(e.ons(amberRiff)), [1.5, 3.5], "ALT turn 2 → AMBER RIFF: on each ALT turn the other is silent")
        assertBalanced(e)
    }

    // MARK: - test 7 — crossing

    private func crossingRules(own: HocketOwn = .replace) -> [HocketRule] {
        [rule(main: [RN, BN], alt: [BN, RN]) { $0.mode = .pass; $0.unit = .bars; $0.own = own }]
    }
    func testCrossingBarTwoTradesTheNotesPartsBetweenTheTwoOutputs() {
        let lanes = (0..<4).map { laneLine($0, riff: false) }                     // the notes parts only, so the pitch is unambiguous
        let e = render(doc(lanes: lanes, rules: crossingRules()), beats: 12), base = render(doc(lanes: lanes), beats: 12)
        let redOwn = Set(base.ons(redNotes).map { $0.note }), blueOwn = Set(base.ons(blueNotes).map { $0.note })
        XCTAssertNotEqual(redOwn, blueOwn)
        for (bar, lo, hi) in [(1, 0.0, 4.0), (2, 4.0, 8.0), (3, 8.0, 12.0)] {
            let onRed = e.ons(redNotes).filter { $0.beat >= lo && $0.beat < hi }, onBlue = e.ons(blueNotes).filter { $0.beat >= lo && $0.beat < hi }
            let crossed = bar == 2
            XCTAssertEqual(Set(onRed.map { $0.note }), crossed ? blueOwn : redOwn, "bar \(bar): the pitches on RED NOTES' output")
            XCTAssertEqual(Set(onBlue.map { $0.note }), crossed ? redOwn : blueOwn, "bar \(bar): the pitches on BLUE NOTES' output")
            XCTAssertEqual(onRed.count, 8, "bar \(bar): every hit sounds once on RED NOTES"); XCTAssertEqual(onBlue.count, 8)
            XCTAssertTrue(onRed.allSatisfy { $0.chan == chanNibble(redNotes) }, "bar \(bar): RED NOTES' output stamps its own channel — a passed note takes the DESTINATION output's channel")
            XCTAssertTrue(onBlue.allSatisfy { $0.chan == chanNibble(blueNotes) })
        }
        // ALL carries both in every bar, on the channel each left with
        let allOn = e.ons(0)
        XCTAssertEqual(allOn.count, 4 * 8 * 3, "four notes outputs × 8 hits × 3 bars: ALL carries every note that left on any output")
        for ev in e.ons(redNotes) + e.ons(blueNotes) { XCTAssertTrue(allOn.contains { $0.sample == ev.sample && $0.note == ev.note && $0.chan == ev.chan }, "ALL carries \(ev) on the channel it left with") }
        // REPLACE and MERGE render identically (both outputs are in MAIN: neither is "ALT only")
        let m = render(doc(lanes: lanes, rules: crossingRules(own: .merge)), beats: 12)
        XCTAssertEqual(m.events, e.events, "REPLACE and MERGE render identically")
        assertBalanced(e)
    }

    // MARK: - test 8 — rotate pass

    func testRotatePassVisitsBlueAmberGreenInTurnAndSilencesTheReceiversOwnPart() {
        let lanes = (0..<4).map { laneLine($0, riff: false) }
        let rules = [rule(main: [RN], alt: [BN, AN, GN]) { $0.mode = .pass; $0.several = .rotate; $0.unit = .passes; $0.mainLen = 2; $0.altLen = 1; $0.own = .replace }]
        let e = render(doc(lanes: lanes, rules: rules), beats: 26), base = render(doc(lanes: lanes), beats: 26)
        let redOwn = Set(base.ons(redNotes).map { $0.note })
        func pass(_ c: UInt8, _ p: Int) -> [HEmitter.Ev] { e.ons(c).filter { $0.beat >= Double(p) * 2 && $0.beat < Double(p + 1) * 2 } }
        func carriesRed(_ c: UInt8, _ p: Int) -> Bool { let ev = pass(c, p); return !ev.isEmpty && ev.allSatisfy { redOwn.contains($0.note) } }
        for p in 0..<12 {
            let k = p / 3, onAlt = p % 3 == 2
            XCTAssertEqual(carriesRed(redNotes, p), !onAlt, "pass \(p + 1): RED's line is on its own output except on ALT turns")
            let target: UInt8? = onAlt ? [blueNotes, amberNotes, greenNotes][k % 3] : nil
            for c in [blueNotes, amberNotes, greenNotes] {
                XCTAssertEqual(carriesRed(c, p), c == target, "pass \(p + 1): RED's line is on \(c == target ? "this" : "not this") output")
            }
        }
        // a receiver's own part is silent while it carries the line, and plays the rest of the time
        XCTAssertTrue(pass(blueNotes, 2).allSatisfy { redOwn.contains($0.note) }, "pass 3: BLUE's own part is silent")
        XCTAssertFalse(pass(blueNotes, 5).isEmpty, "pass 6: BLUE's own part plays (AMBER is the receiver)")
        XCTAssertTrue(pass(blueNotes, 5).allSatisfy { !redOwn.contains($0.note) })
        XCTAssertTrue(pass(amberNotes, 5).allSatisfy { redOwn.contains($0.note) }, "pass 6: AMBER's own part is silent")
        assertBalanced(e)
    }

    // MARK: - test 9 — replace and merge

    func testReplaceSilencesTheReceiversOwnNotesMergeKeepsThem() {
        let lanes = (0..<4).map { laneLine($0, riff: false) }
        func run(_ own: HocketOwn) -> HEmitter {
            render(doc(lanes: lanes, rules: [rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.own = own }]), beats: 4)
        }
        let rep = run(.replace), mer = run(.merge), base = render(doc(lanes: lanes), beats: 4)
        let blueOwn = Set(base.ons(blueNotes).map { $0.note }), redOwn = Set(base.ons(redNotes).map { $0.note })
        // hits at 0, 1.0, 2.0, 3.0 are MAIN turns (x even), 0.5, 1.5, 2.5, 3.5 ALT turns
        let repAlt = rep.ons(blueNotes).filter { [0.5, 1.5, 2.5, 3.5].contains($0.beat) }
        XCTAssertTrue(repAlt.allSatisfy { redOwn.contains($0.note) }, "REPLACE: on ALT turns BLUE NOTES carries only RED's line")
        XCTAssertEqual(repAlt.count, 4, "…one note per ALT hit")
        XCTAssertTrue(rep.ons(blueNotes).filter { [0.0, 1.0, 2.0, 3.0].contains($0.beat) }.allSatisfy { blueOwn.contains($0.note) }, "MAIN turns: BLUE plays its own part")
        let merAlt = mer.ons(blueNotes).filter { [0.5, 1.5, 2.5, 3.5].contains($0.beat) }
        XCTAssertTrue(merAlt.contains { blueOwn.contains($0.note) } && merAlt.contains { redOwn.contains($0.note) }, "MERGE: BLUE's own notes sound alongside RED's line")
        assertBalanced(rep); assertBalanced(mer)
    }

    // MARK: - test 10 — fan-in

    func testFanInBothLinesLeaveOnTheSingleAltOutput() {
        let lanes = (0..<4).map { laneLine($0, riff: false) }
        let e = render(doc(lanes: lanes, rules: [rule(main: [RN, AN], alt: [BN]) { $0.mode = .pass }]), beats: 4), base = render(doc(lanes: lanes), beats: 4)
        let redOwn = Set(base.ons(redNotes).map { $0.note }), amberOwn = Set(base.ons(amberNotes).map { $0.note })
        let onAlt = e.ons(blueNotes).filter { [0.5, 1.5, 2.5, 3.5].contains($0.beat) }
        XCTAssertTrue(onAlt.contains { redOwn.contains($0.note) }, "on ALT turns RED's line leaves on BLUE NOTES")
        XCTAssertTrue(onAlt.contains { amberOwn.contains($0.note) }, "…and so does AMBER's")
        XCTAssertTrue(e.ons(redNotes).filter { [0.5, 1.5, 2.5, 3.5].contains($0.beat) }.isEmpty && e.ons(amberNotes).filter { [0.5, 1.5, 2.5, 3.5].contains($0.beat) }.isEmpty, "…and neither sounds on its own output")
        assertBalanced(e)
    }

    // MARK: - test 11 — collisions

    /// The shared-key collision at several window sizes: a window of 65,536 frames (≈ 2.7 beats) holds BOTH holders' offs AND the next hits, which is when the order the voices are swept in, and what a later strike may join, matters (a 480-frame window closes holders in time order anyway).
    private func collision(longerFirst: Bool, frames: UInt32) {
        // RED NOTES and BLUE NOTES both play C4 (60) on the same hit; PASS + MERGE puts both on BLUE NOTES on ALT turns
        var lanes = (0..<4).map { laneLine($0, riff: false) }
        for i in [0, 1] { lanes[i].octave = 0; lanes[i].litNotes = 0b0000_0001 }
        lanes[0].notesGate = longerFirst ? 0.9 : 0.25; lanes[1].notesGate = longerFirst ? 0.25 : 0.9
        let e = render(doc(lanes: lanes, rules: [rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.own = .merge }]), beats: 2, frames: frames)
        let at = 0.5                                                                  // an ALT turn (the 2nd hit)
        let ctx = "(RED's gate \(lanes[0].notesGate!), BLUE's \(lanes[1].notesGate!), \(frames)-frame windows)"
        XCTAssertEqual(e.ons(blueNotes).filter { $0.beat == at && $0.note == 60 }.count, 1, "one note-on on BLUE NOTES for the two lines' C4 \(ctx)")
        XCTAssertEqual(e.ons(0).filter { $0.beat == at && $0.note == 60 && $0.chan == chanNibble(blueNotes) }.count, 1, "…and one on ALL \(ctx)")
        let offsBlue = e.offs(blueNotes).filter { $0.note == 60 && $0.beat > at && $0.beat < at + 0.5 }
        XCTAssertEqual(offsBlue.count, 1, "one note-off \(ctx)")
        // the longer gate is 0.9 of the 0.5-beat gap = 0.45 beat; the shorter is 0.25 × 0.5 = 0.125
        XCTAssertEqual(offsBlue.first?.beat ?? -1, at + 0.45, accuracy: 0.001, "the off goes out when the LONGER of the two ends \(ctx)")
        XCTAssertEqual(e.offs(0).filter { $0.note == 60 && $0.chan == chanNibble(blueNotes) && $0.beat > at && $0.beat < at + 0.5 }.first?.beat ?? -1, at + 0.45, accuracy: 0.001, "…on ALL too \(ctx)")
        assertBalanced(e, ctx)
    }
    func testTwoLinesStrikingTheSameKeyOnOneOutputSendOneNoteOnAndOffAtTheLongerEnd() {
        for frames in [UInt32(480), 16_384, 65_536] { collision(longerFirst: false, frames: frames) }
    }

    // MARK: - test 12 — both groups, off parts

    func testAnOutputInBothGroupsOfASwapAlwaysPlays() {
        let e = render(doc(rules: [rule(main: [RR], alt: [RR, BR]) { $0.mainLen = 1; $0.altLen = 1 }]), beats: 4), base = render(doc(), beats: 4)
        XCTAssertEqual(e.all(redRiff), base.all(redRiff), "RED RIFF is in both groups, so it sounds on every turn")
        XCTAssertEqual(beats(e.ons(blueRiff)), [0.5, 1.5, 2.5, 3.5], "BLUE RIFF (ALT only) plays on ALT turns")
    }
    func testAnOffPartPassesNothingAndSwallowsAPassedLine() {
        var lanes = (0..<4).map { laneLine($0, riff: false) }
        lanes[1].notesOn = false; lanes[1].litNotes = 0                               // BLUE NOTES switched off
        let e = render(doc(lanes: lanes, rules: crossingRules()), beats: 12), base = render(doc(lanes: lanes), beats: 12)
        XCTAssertTrue(e.ons(blueNotes).isEmpty, "BLUE NOTES is off: nothing on its output, ever")
        XCTAssertTrue(e.ons(redNotes).filter { $0.beat >= 4 && $0.beat < 8 }.isEmpty, "bar 2: RED's line moved to BLUE NOTES (off), and BLUE passes nothing — RED NOTES' own output is silent too")
        XCTAssertEqual(e.ons(redNotes).filter { $0.beat < 4 || $0.beat >= 8 }, base.ons(redNotes).filter { $0.beat < 4 || $0.beat >= 8 }, "bars 1 and 3: RED plays as normal")
        XCTAssertEqual(e.ons(0).filter { $0.beat >= 4 && $0.beat < 8 }.filter { $0.chan == chanNibble(blueNotes) || $0.chan == chanNibble(redNotes) }.count, 0, "bar 2: silent on ALL too")
        assertBalanced(e)
    }

    // MARK: - test 15 — several rules at once

    func testTwoRulesRunningTogetherEachBehaveAsTheyWouldAlone() {
        let r1 = rule(main: [RR], alt: [BR]) { $0.mainLen = 3; $0.altLen = 1 }
        let r2 = rule(main: [AN, GN], alt: [GN, AN]) { $0.mode = .pass; $0.unit = .bars }
        let lanes = (0..<4).map { laneLine($0) }
        let both = render(doc(lanes: lanes, rules: [r1, r2]), beats: 12), one = render(doc(lanes: lanes, rules: [r1]), beats: 12), two = render(doc(lanes: lanes, rules: [r2]), beats: 12)
        for c in [redRiff, blueRiff] { XCTAssertEqual(both.all(c), one.all(c), "rule 1's outputs, cable \(c), behave as R1 alone") }
        for c in [amberNotes, greenNotes] { XCTAssertEqual(both.all(c), two.all(c), "rule 2's outputs, cable \(c), behave as R2 alone") }
        for c in [redNotes, blueNotes, amberRiff, greenRiff] { XCTAssertEqual(both.all(c), render(doc(lanes: lanes), beats: 12).all(c), "cable \(c) is in no rule") }
        assertBalanced(both)
    }

    // MARK: - test 18 — velocity and gate

    func testAPassedNoteTakesTheReceivingPadsVelocityAndItsOwnGateAndAnAccentTravels() {
        var lanes = (0..<4).map { laneLine($0, riff: false) }
        lanes[0].notesVelocity = 100; lanes[1].notesVelocity = 50
        lanes[0].notesGate = 0.25; lanes[1].notesGate = 0.9
        let rules = [rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.own = .replace }]
        let e = render(doc(lanes: lanes, rules: rules), beats: 4), base = render(doc(lanes: lanes), beats: 4)
        let redVel = Set(base.ons(redNotes).map { Int($0.vel) }), blueVel = Set(base.ons(blueNotes).map { Int($0.vel) })
        XCTAssertEqual(redVel, [100]); XCTAssertEqual(blueVel, [50])
        let altOnBlue = e.ons(blueNotes).filter { [0.5, 1.5, 2.5, 3.5].contains($0.beat) }
        XCTAssertFalse(altOnBlue.isEmpty)
        XCTAssertTrue(altOnBlue.allSatisfy { $0.vel == 50 }, "on ALT turns RED's notes leave on BLUE NOTES under BLUE NOTES' MIX VEL (50), not RED's (100)")
        // RED's own gate travels: 0.25 of the 0.5-beat gap
        let off = e.offs(blueNotes).filter { $0.beat > 0.5 && $0.beat < 1.0 }.map { $0.beat }.min()!
        XCTAssertEqual(off, 0.5 + 0.125, accuracy: 0.001, "…and with RED's gate, not BLUE's")
        // an FX VEL accent on RED's second hit (column 2) travels as its own value
        var withAccent = doc(lanes: (0..<4).map { laneLine($0) }.enumerated().map { var l = $0.element; if $0.offset < 2 { l.notesVelocity = lanes[$0.offset].notesVelocity; l.notesGate = lanes[$0.offset].notesGate }; return l }, rules: rules)   // riff ON, so an FX VEL cell has a hit to act on
        var fx = EuclideousFX(); fx.cells[3 * 8 + 1] = 120; fx.lanes[3] = 0b0001      // VEL row, column 2, RED only
        withAccent.euclideousFX = fx
        let a = render(withAccent, beats: 4)
        let accented = a.ons(blueNotes).filter { $0.beat == 0.5 }, plain = a.ons(blueNotes).filter { $0.beat == 1.5 }
        XCTAssertFalse(accented.isEmpty)
        XCTAssertTrue(plain.allSatisfy { $0.vel == 50 })
        XCTAssertTrue(accented.allSatisfy { $0.vel > 50 }, "the accent travels with the note: velocity \(accented.map { $0.vel }) vs the plain \(plain.map { $0.vel })")
    }

    // MARK: - test 11, the other order — the off lands at the LONGER holder's end whichever voice is swept last

    func testTheOffGoesOutAtTheLongerEndEvenWhenTheLongerHolderWasStruckFirst() {
        for frames in [UInt32(480), 16_384, 65_536] { collision(longerFirst: true, frames: frames) }
    }

    // MARK: - test 4 — counting, through the engine

    func testHitsCountsTheReferenceLanesHitsEvenWhenItsLanesMuteSilencesThem() {
        var lanes = (0..<4).map { laneLine($0) }
        let rules = [rule(main: [RR], alt: [BR]) { $0.mainLen = 1; $0.altLen = 1 }]
        let plain = render(doc(lanes: lanes, rules: rules), beats: 8)
        lanes[0].muteCells16 = 0                                                   // every LANES cell of RED muted: RED strikes nothing…
        let muted = render(doc(lanes: lanes, rules: rules), beats: 8)
        XCTAssertTrue(muted.ons(redRiff).isEmpty && muted.ons(redNotes).isEmpty, "RED is muted")
        XCTAssertEqual(beats(plain.ons(blueRiff)), [0.5, 1.5, 2.5, 3.5, 4.5, 5.5, 6.5, 7.5])
        XCTAssertEqual(beats(muted.ons(blueRiff)), beats(plain.ons(blueRiff)), "…yet its hits still move the count, so BLUE RIFF plays exactly where it did")
    }
    func testARhythmRestartStartsTheHitCountAgain() {
        var lanes = (0..<4).map { laneLine($0) }
        func rules(_ unit: HocketUnit = .hits) -> [HocketRule] { [rule(main: [RR], alt: [BR]) { $0.mainLen = 2; $0.altLen = 1; $0.unit = unit }] }
        let free = render(doc(lanes: lanes, rules: rules()), beats: 8)
        XCTAssertEqual(beats(free.ons(blueRiff)), [1.0, 2.5, 4.0, 5.5, 7.0], "FREE: the count runs on across the bar line (8 hits a bar is not a multiple of the cycle's 3)")
        lanes[0].restartRhythmBars = [1]; lanes[0].restartMelodyPasses = []
        euclideousPinRestartChains(&lanes[0], .from([1]), .free)
        let restarted = render(doc(lanes: lanes, rules: rules()), beats: 8)
        XCTAssertEqual(beats(restarted.ons(blueRiff)), [1.0, 2.5, 5.0, 6.5], "a rhythm restart every bar starts the count again at 0: the same turns every bar")
    }
    func testSwitchingCountOnToAnotherLanesOutputChangesTheReferenceLane() {
        var lanes = (0..<4).map { laneLine($0) }
        lanes[1].pulses = 2                                                        // BLUE: hits on steps 1 and 5 only (beats 0, 1.0 of each pass)
        func run(_ countOn: Int) -> [Double] {
            beats(render(doc(lanes: lanes, rules: [rule(main: [RR, BR], alt: [GR]) { $0.mainLen = 1; $0.altLen = 1; $0.countOn = countOn }]), beats: 4).ons(greenRiff))
        }
        XCTAssertEqual(run(0), [0.5, 1.5, 2.5, 3.5], "COUNT ON RED RIFF: RED's hits are every half beat")
        XCTAssertEqual(run(1), [1.0, 1.5, 3.0, 3.5], "COUNT ON BLUE RIFF: BLUE's hits are on the beat, so the count moves at 0, 1.0, 2.0, 3.0")
    }
    func testPassesCountsTheReferenceLanesLaps() {
        let lanes = (0..<4).map { laneLine($0) }
        let e = render(doc(lanes: lanes, rules: [rule(main: [RR], alt: [GR]) { $0.unit = .passes }]), beats: 8)
        XCTAssertEqual(beats(e.ons(redRiff)), [0, 0.5, 1.0, 1.5, 4.0, 4.5, 5.0, 5.5], "RED RIFF plays on even laps (a lap is 2 beats)")
        XCTAssertEqual(beats(e.ons(greenRiff)), [2.0, 2.5, 3.0, 3.5, 6.0, 6.5, 7.0, 7.5], "…GREEN RIFF on odd laps")
    }
    func testStepsCountsSixteenthsOfThePageClock() {
        let lanes = (0..<4).map { laneLine($0) }
        let e = render(doc(lanes: lanes, rules: [rule(main: [RR], alt: [GR]) { $0.unit = .steps; $0.mainLen = 2; $0.altLen = 1 }]), beats: 8)
        let altBeats = (0..<16).map { Double($0) * 0.5 }.filter { (Int(($0 / 0.25).rounded()) % 3) >= 2 }
        XCTAssertEqual(beats(e.ons(greenRiff)), altBeats, "a hit on sixteenth x is an ALT turn when x mod 3 ≥ 2")
        XCTAssertEqual(beats(e.ons(redRiff)), (0..<16).map { Double($0) * 0.5 }.filter { !altBeats.contains($0) })
    }

    // MARK: - test 16 — a change while notes sound never moves or strands a note

    /// A rule edit lands between two windows; every note struck before it ends where it began, at the time it would have ended anyway.
    private func changeMidRun(first: [HocketRule], then: [HocketRule], lanes: [EuclidLine], rawGates: Bool, changeBeat: Double = 1.25, beats total: Double = 6, configure: @escaping (inout PluginState) -> Void = { _ in }) -> (changed: HEmitter, steady: HEmitter) {
        func run(_ second: [HocketRule]?) -> HEmitter {
            let a = SnapshotBuilder.build(from: doc(lanes: lanes, rules: first, rawGates: rawGates, configure: configure))
            let b = SnapshotBuilder.build(from: doc(lanes: lanes, rules: second ?? first, rawGates: rawGates, configure: configure))
            let pool = NotePool(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
            let router = Router(); var diag = KernelDiag(); let e = HEmitter()
            let totalFrames = Int(total * 24_000) - 1
            var done = 0, beat = 0.0, ts = 0.0
            while done < totalFrames {
                let n = UInt32(min(480, totalFrames - done))
                router.process(box: beat >= changeBeat ? b : a, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: n, out: e, diag: &diag)
                done += Int(n); beat += Double(n) * 120.0 / 60 / 48_000; ts += Double(n)
            }
            router.process(box: b, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
            return e
        }
        return (run(then), run(nil))
    }
    func testEditingARuleWhileNotesSoundEndsEveryNoteWhereItBeganAtItsNormalTime() {
        var lanes = (0..<4).map { laneLine($0) }
        for i in 0..<4 { lanes[i].gate = 0.99; lanes[i].notesGate = 0.99 }          // long notes: several are sounding when the edit lands
        let base = rule(main: [RN, AN], alt: [BN, GN]) { $0.mode = .pass; $0.unit = .hits; $0.own = .merge }
        let edits: [(String, (inout HocketRule) -> Void)] = [
            ("mode", { $0.mode = .swap }), ("MAIN", { [rn = self.RN] in $0.main = [rn] }), ("ALT", { [bn = self.BN] in $0.alt = [bn] }), ("unit", { $0.unit = .bars }), ("MAIN length", { $0.mainLen = 3 }), ("ALT length", { $0.altLen = 4 }),
            ("offset", { $0.offset = 1 }), ("several", { $0.several = .rotate }), ("own", { $0.own = .replace }), ("COUNT ON", { $0.countOn = 1 }), ("switched off", { $0.on = false }),
        ]
        for (what, edit) in edits {
            var edited = base; edit(&edited)
            let r = changeMidRun(first: [base], then: [edited], lanes: lanes, rawGates: false)
            assertBalanced(r.changed, "after editing \(what)")
            let cut = Int64(1.25 * 24_000)
            for c in UInt8(0)...8 {
                let before = { (e: HEmitter) in e.events.filter { $0.cable == c && $0.sample < cut } }
                XCTAssertEqual(before(r.changed), before(r.steady), "\(what): cable \(c): everything struck or ended before the edit is exactly as without it")
            }
            // every note struck before the edit ends at the sample it would have without the edit, on the same output and channel
            for ev in r.steady.events where ev.on && ev.sample < cut {
                let off = r.steady.events.first { !$0.on && $0.cable == ev.cable && $0.chan == ev.chan && $0.note == ev.note && $0.sample > ev.sample }
                let off2 = r.changed.events.first { !$0.on && $0.cable == ev.cable && $0.chan == ev.chan && $0.note == ev.note && $0.sample > ev.sample }
                XCTAssertEqual(off2?.sample, off?.sample, "\(what): a note struck before the edit (cable \(ev.cable), note \(ev.note)) ends at its normal time")
            }
        }
        // deleting the rule altogether
        let gone = changeMidRun(first: [base], then: [], lanes: lanes, rawGates: false)
        assertBalanced(gone.changed, "after deleting the rule")
        XCTAssertEqual(gone.changed.events.filter { $0.sample < Int64(1.25 * 24_000) }, gone.steady.events.filter { $0.sample < Int64(1.25 * 24_000) })
    }
    func testEditingARuleAtGate100NeverStrandsALegatoNote() {
        var lanes = (0..<4).map { laneLine($0) }
        for i in 0..<4 { lanes[i].gate = 1.0; lanes[i].notesGate = 1.0 }            // raw 100%: notes are held legato into the next hit
        let base = rule(main: [RN, AN], alt: [BN, GN]) { $0.mode = .pass; $0.unit = .hits; $0.own = .merge }
        for (what, edit) in [("mode", { (r: inout HocketRule) in r.mode = .swap }), ("MAIN", { [rn = self.RN] in $0.main = [rn] }), ("unit", { $0.unit = .bars }), ("own", { $0.own = .replace }), ("switched off", { $0.on = false })] as [(String, (inout HocketRule) -> Void)] {
            for changeBeat in [0.75, 1.25, 1.5] {
                var edited = base; edit(&edited)
                let r = changeMidRun(first: [base], then: [edited], lanes: lanes, rawGates: true, changeBeat: changeBeat)
                assertBalanced(r.changed, "after editing \(what) at \(changeBeat) with every gate at 100%")
            }
        }
        let gone = changeMidRun(first: [base], then: [], lanes: lanes, rawGates: true)
        assertBalanced(gone.changed, "after deleting the rule at gate 100%")
    }

    func testARatchetedOrRolledHitKeepsTheRoutingItBeganWithWhenTheRuleChangesMidHit() {
        // RED's first hit is a 4× ratchet (FX RATCH on column 1): its strikes at 0, 0.0625, 0.125, 0.1875 beat (a 1/16 step ÷ 4). The rule passes RED NOTES to BLUE NOTES (bar 1 is an ALT turn). The edit lands at beat 0.1, between the 2nd and 3rd strike.
        let lanes = (0..<4).map { laneLine($0) }
        let pass = rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.unit = .bars; $0.offset = 1; $0.own = .replace }
        var fx = EuclideousFX(); fx.cells[0] = 4; fx.lanes[0] = 0b0001                       // RATCH row, column 1, RED only
        let r = changeMidRun(first: [pass], then: [], lanes: lanes, rawGates: false, changeBeat: 0.1, beats: 2) { $0.euclideousFX = fx }
        let cut = Int64(0.45 * 24_000)                                                        // before the lane's second hit (beat 0.5)
        let ratchets = r.steady.ons(blueNotes).filter { $0.sample < cut }
        XCTAssertEqual(ratchets.count, 4, "the passed ratchet strikes four times on BLUE NOTES (\(beats(ratchets)))")
        XCTAssertEqual(r.changed.events.filter { $0.sample < cut }, r.steady.events.filter { $0.sample < cut }, "deleting the rule between two strikes of one hit changes nothing about that hit: every strike keeps the routing the hit began with")
        XCTAssertFalse(r.changed.ons(redNotes).contains { $0.sample < cut && $0.beat > 0.1 }, "…and none of its later strikes falls back to RED NOTES")
        assertBalanced(r.changed)
        XCTAssertTrue(r.changed.ons(redNotes).contains { $0.beat >= 0.45 }, "hits after the edit follow the new rules (none): RED NOTES sounds on its own output again")
    }

    func testALaterStrikeNeverJoinsANoteThatHasAlreadyEndedEvenWithinOneBigWindow() {
        // PASS + MERGE puts RED's line and BLUE's own part on BLUE NOTES on ALT turns; with every hit of a 2-beat lap in ONE window, a deferred holder from hit 2 must not swallow the strikes of hits 3 and 4.
        var lanes = (0..<4).map { laneLine($0, riff: false) }
        for i in [0, 1] { lanes[i].octave = 0 }
        let rules = [rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.own = .merge }]
        let small = render(doc(lanes: lanes, rules: rules), beats: 2), big = render(doc(lanes: lanes, rules: rules), beats: 2, frames: 65_536)
        for c in [blueNotes, 0] as [UInt8] {
            XCTAssertEqual(big.ons(c).map { $0.beat }, small.ons(c).map { $0.beat }, "cable \(c): every strike is its own note-on whatever the window size")
            XCTAssertEqual(big.offs(c).map { $0.beat }, small.offs(c).map { $0.beat }, "cable \(c): …and ends at its own time")
        }
        assertBalanced(big)
    }

    // MARK: - §8 / §9.3 — what the displays read

    private func renderKeepingRouter(_ st: PluginState, beats total: Double, frames: UInt32 = 480) -> (router: Router, emitter: HEmitter, drained: [[Router.EuclideousNoteViewEventSnapshot]]) {
        let box = SnapshotBuilder.build(from: st)
        let pool = NotePool(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        let router = Router(); var diag = KernelDiag(); let e = HEmitter()
        let totalFrames = Int(total * 24_000) - 1
        var done = 0, beat = 0.0, ts = 0.0
        var drained: [[Router.EuclideousNoteViewEventSnapshot]] = [[], [], [], []]
        while done < totalFrames {
            let n = UInt32(min(Int(frames), totalFrames - done))
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: n, out: e, diag: &diag)
            let evs = router.drainEuclideousNoteViewEvents()
            for l in 0..<4 { drained[l] += evs[l] }
            done += Int(n); beat += Double(n) * 120.0 / 60 / 48_000; ts += Double(n)
        }
        return (router, e, drained)
    }
    func testTheLiveCountIsTheReferenceLanesHitCountAtTheLastWindowsStart() {
        let lanes = (0..<4).map { laneLine($0) }
        let r1 = rule(main: [RR], alt: [BR]) { $0.mainLen = 3; $0.altLen = 1 }
        let a = renderKeepingRouter(doc(lanes: lanes, rules: [r1]), beats: 1.75)       // RED has struck hits at 0, 0.5, 1.0, 1.5
        XCTAssertEqual(a.router.hocketLive().counts[0], 3, "x = the 4th hit's index")
        XCTAssertTrue(a.router.hocketLive().running)
        let b = renderKeepingRouter(doc(lanes: lanes, rules: [r1]), beats: 0.4)
        XCTAssertEqual(b.router.hocketLive().counts[0], 0, "before the 2nd hit")
        XCTAssertEqual(a.router.hocketLive().counts[1], 0, "an unused rule slot reads 0")
        let bars = renderKeepingRouter(doc(lanes: lanes, rules: [rule(main: [RR], alt: [BR]) { $0.unit = .bars }]), beats: 9)
        XCTAssertEqual(bars.router.hocketLive().counts[0], 2, "BARS: bar 3 of the page clock")
        let none = renderKeepingRouter(doc(lanes: lanes), beats: 2)
        XCTAssertEqual(none.router.hocketLive().counts, [0, 0, 0, 0], "no rule: nothing published")
    }
    func testTheHitEventNamesTheOutputEachPitchLeftOn() {
        let lanes = (0..<4).map { laneLine($0, riff: false) }
        let crossing = renderKeepingRouter(doc(lanes: lanes, rules: crossingRules()), beats: 8)
        func dests(_ lane: Int, bar: Int) -> Set<Int8> {
            Set(crossing.drained[lane].filter { $0.onsetBeat >= Double(bar) * 4 && $0.onsetBeat < Double(bar + 1) * 4 }.flatMap { $0.dests })
        }
        XCTAssertEqual(dests(0, bar: 0), [1], "bar 1: RED NOTES' hits left on RED NOTES (bus 1)"); XCTAssertEqual(dests(1, bar: 0), [3])
        XCTAssertEqual(dests(0, bar: 1), [3], "bar 2: RED's notes left on BLUE NOTES (bus 3) — the strip flashes in blue"); XCTAssertEqual(dests(1, bar: 1), [1])
        XCTAssertTrue(crossing.drained[2].flatMap { $0.dests }.allSatisfy { $0 == 5 }, "AMBER is in no rule: its own output (bus 5)")
        let plain = renderKeepingRouter(doc(lanes: lanes), beats: 2)
        XCTAssertEqual(Set(plain.drained[0].flatMap { $0.dests }), [1], "no rule: every strike reports its own output")
        let swap = renderKeepingRouter(doc(rules: [rule(main: [RR], alt: [BR]) { $0.mainLen = 3; $0.altLen = 1 }]), beats: 2)
        XCTAssertTrue(swap.drained[0].contains { $0.hasRiffNote && $0.dests.first == 0 }, "RED's riff note reports bus 0")
        XCTAssertTrue(swap.drained[0].allSatisfy { !$0.notes.isEmpty }, "a hit RED's riff rests on the ALT turn posts no event for that layer's note")
    }
}
