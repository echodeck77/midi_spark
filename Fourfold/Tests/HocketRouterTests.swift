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
        // on every ALT turn BLUE NOTES carries EXACTLY the union of RED's and AMBER's own notes of that hit, each on BLUE NOTES' channel; REPLACE (the default) silences BLUE's own part there
        for b in [0.5, 1.5, 2.5, 3.5] {
            let want = Set(base.ons(redNotes).filter { $0.beat == b }.map { $0.note }).union(base.ons(amberNotes).filter { $0.beat == b }.map { $0.note })
            let got = e.ons(blueNotes).filter { $0.beat == b }
            XCTAssertEqual(Set(got.map { $0.note }), want, "ALT hit at \(b): BLUE NOTES carries RED's and AMBER's lines and nothing else")
            XCTAssertEqual(got.count, want.count, "…one note-on each")
            XCTAssertTrue(got.allSatisfy { $0.chan == chanNibble(blueNotes) }, "…all on BLUE NOTES' channel")
            XCTAssertTrue(e.ons(redNotes).filter { $0.beat == b }.isEmpty && e.ons(amberNotes).filter { $0.beat == b }.isEmpty, "…and neither sounds on its own output")
        }
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
    /// Paul, 2026-10-27 (revises §7.2): a line passed to an output SOUNDS on it even when that lane's own layer is switched off — an output is a port. A SOURCE part that is off still passes nothing.
    func testAPassedLineSoundsOnAnOutputWhoseOwnPartIsOffAndAnOffSourcePassesNothing() {
        var lanes = (0..<4).map { laneLine($0, riff: false) }
        lanes[1].notesOn = false; lanes[1].litNotes = 0                               // BLUE NOTES switched off
        let e = render(doc(lanes: lanes, rules: crossingRules()), beats: 12), base = render(doc(lanes: lanes), beats: 12)
        func pairs(_ evs: [HEmitter.Ev], _ lo: Double, _ hi: Double) -> [String] { evs.filter { $0.beat >= lo && $0.beat < hi }.map { "\($0.beat)/\($0.note)" } }
        XCTAssertTrue(pairs(e.ons(blueNotes), 0, 4).isEmpty && pairs(e.ons(blueNotes), 8, 12).isEmpty, "bars 1 and 3: BLUE NOTES' own part is off, so it plays nothing")
        XCTAssertEqual(pairs(e.ons(blueNotes), 4, 8), pairs(base.ons(redNotes), 4, 8), "bar 2: RED's line leaves on BLUE NOTES although BLUE's own NOTES layer is off")
        XCTAssertFalse(pairs(e.ons(blueNotes), 4, 8).isEmpty)
        XCTAssertTrue(e.ons(blueNotes).filter { $0.beat >= 4 && $0.beat < 8 }.allSatisfy { $0.chan == chanNibble(blueNotes) }, "…on BLUE NOTES' channel")
        XCTAssertTrue(e.ons(redNotes).filter { $0.beat >= 4 && $0.beat < 8 }.isEmpty, "bar 2: RED NOTES' own output is silent — its line moved, and BLUE's off part passes nothing back")
        XCTAssertEqual(e.ons(redNotes).filter { $0.beat < 4 || $0.beat >= 8 }, base.ons(redNotes).filter { $0.beat < 4 || $0.beat >= 8 }, "bars 1 and 3: RED plays as normal")
        XCTAssertEqual(e.ons(0).filter { $0.beat >= 4 && $0.beat < 8 && $0.chan == chanNibble(blueNotes) }.count, e.ons(blueNotes).filter { $0.beat >= 4 && $0.beat < 8 }.count, "bar 2: ALL carries the passed line on BLUE NOTES' channel too")
        assertBalanced(e)
    }
    /// Paul, 2026-10-27: ONE MAIN output passed to TWO ALT outputs (a riff and a notes output), TOGETHER: the line comes out of BOTH, each at the receiving pad's MIX VEL — at any window size; BLUE's NOTES layer is off and it still sounds.
    func testOneLinePassedToARiffAndANotesOutputComesOutOfBoth() {
        var lanes = (0..<4).map { laneLine($0, notes: false) }
        lanes[1].velocityAbsolute = 90; lanes[1].notesVelocity = 40                 // BLUE's RIFF pad 90, NOTES pad 40
        let rules = [rule(main: [RR], alt: [BR, BN]) { $0.mode = .pass; $0.mainLen = 1; $0.altLen = 1 }]
        for frames in [UInt32(480), 8192] {
            let e = render(doc(lanes: lanes, rules: rules), beats: 4, frames: frames), base = render(doc(lanes: lanes), beats: 4, frames: frames)
            for b in [0.5, 1.5, 2.5, 3.5] {                                          // the ALT turns
                let red = base.ons(redRiff).filter { $0.beat == b }.map { $0.note }
                XCTAssertFalse(red.isEmpty)
                let onRiff = e.ons(blueRiff).filter { $0.beat == b }, onNotes = e.ons(blueNotes).filter { $0.beat == b }
                XCTAssertEqual(onRiff.map { $0.note }, red, "\(frames) frames, hit at \(b): BLUE RIFF carries RED RIFF's note")
                XCTAssertEqual(onNotes.map { $0.note }, red, "\(frames) frames, hit at \(b): …and so does BLUE NOTES")
                XCTAssertTrue(onRiff.allSatisfy { $0.vel == 90 } && onNotes.allSatisfy { $0.vel == 40 }, "\(frames) frames: each at its receiving pad's MIX VEL (riff 90, notes 40)")
                XCTAssertTrue(onRiff.allSatisfy { $0.chan == chanNibble(blueRiff) } && onNotes.allSatisfy { $0.chan == chanNibble(blueNotes) }, "each on its own output's channel")
                XCTAssertTrue(e.ons(redRiff).filter { $0.beat == b }.isEmpty, "RED RIFF's own output is silent on an ALT turn (its line moved)")
                XCTAssertEqual(e.ons(0).filter { $0.beat == b && ($0.chan == chanNibble(blueRiff) || $0.chan == chanNibble(blueNotes)) }.count, onRiff.count + onNotes.count, "ALL carries both")
            }
            XCTAssertEqual(e.ons(redRiff).filter { [0.0, 1.0, 2.0, 3.0].contains($0.beat) }, base.ons(redRiff).filter { [0.0, 1.0, 2.0, 3.0].contains($0.beat) }, "MAIN turns: RED plays as normal")
            assertBalanced(e)
        }
    }
    /// 2 MAIN, 3 ALT (TOGETHER): MAIN 0 reaches ALT 0 and 2, MAIN 1 reaches ALT 1.
    func testTwoMainOutputsAndThreeAltOutputsShareTheLines() {
        let lanes = (0..<4).map { laneLine($0, riff: true, notes: false) }
        let rules = [rule(main: [RR, AR], alt: [BR, GR, BN]) { $0.mode = .pass; $0.mainLen = 1; $0.altLen = 1; $0.own = .merge }]
        let e = render(doc(lanes: lanes, rules: rules), beats: 4), base = render(doc(lanes: lanes), beats: 4)
        for b in [0.5, 1.5, 2.5, 3.5] {
            let red = base.ons(redRiff).filter { $0.beat == b }.map { $0.note }, amber = base.ons(amberRiff).filter { $0.beat == b }.map { $0.note }
            XCTAssertEqual(e.ons(blueNotes).filter { $0.beat == b }.map { $0.note }, red, "ALT[2] = BLUE NOTES carries MAIN 0 (RED RIFF)")
            XCTAssertTrue(e.ons(blueRiff).filter { $0.beat == b }.map { $0.note }.contains { red.contains($0) }, "ALT[0] = BLUE RIFF carries MAIN 0 (RED RIFF) as well")
            XCTAssertTrue(e.ons(greenRiff).filter { $0.beat == b }.map { $0.note }.contains { amber.contains($0) }, "ALT[1] = GREEN RIFF carries MAIN 1 (AMBER RIFF)")
        }
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
        // FX VEL on a NOTES layer is `cell + clamp(notes pad − riff pad)` (the engine's own convention, `euclideousFXLitVelocity`): under BLUE's pads (notes 50, riff 100) the accent 120 leaves as 120 − 50 = 70
        XCTAssertEqual(Set(accented.map { Int($0.vel) }), [70], "the accent travels with the note, re-based on the receiving pads: velocity \(accented.map { $0.vel }) vs the plain \(plain.map { $0.vel })")
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

    // MARK: - adversarial review (2026-10-27): window-size independence, an independent HITS oracle, destination muting, BARS at 3/4, shared channels on ALL
    /// §7.3 / test 11: two lines striking the same key on one output are ONE note ending at the longer end — at ANY window size. BLUE's own part (hit at 0.75) lands while RED's passed line (struck at 0.5, sounding
    /// until 0.95) is sounding; RED's off falls in the SAME 8192-frame window as BLUE's strike, so the top-of-window drain closes it before BLUE can join.
    func testAJoinDoesNotDependOnWhichWindowTheHoldersOffFallsIn() {
        var lanes = (0..<4).map { laneLine($0, riff: false) }
        for i in [0, 1] { lanes[i].octave = 0 }
        lanes[0].notesGate = 0.9; lanes[1].notesGate = 0.25
        lanes[1].rotate = 1                                              // BLUE's hits fall on 0.25, 0.75, 1.25, 1.75
        let rules = [rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.own = .merge }]
        let small = render(doc(lanes: lanes, rules: rules), beats: 2, frames: 480)
        let big = render(doc(lanes: lanes, rules: rules), beats: 2, frames: 8192)
        for c in [blueNotes, 0] as [UInt8] {
            func stream(_ e: HEmitter) -> [String] { e.all(c).filter { $0.note == 60 }.sorted { ($0.sample, $0.on ? 1 : 0) < ($1.sample, $1.on ? 1 : 0) }.map { "\($0.on ? "on" : "off")@\($0.beat)" } }
            let s = stream(small), b = stream(big)
            XCTAssertEqual(b, s, "cable \(c): the C4 stream must not depend on the window size\n small(480): \(s)\n big(8192): \(b)")
        }
    }

    /// An independent oracle for the HITS clock: BLUE (every tick a hit, its own rate) strikes its riff only on MAIN turns of a SWAP whose COUNT ON is RED, so which BLUE hits sound says what count the engine read.
    /// The oracle counts RED's pattern hits (the engine's own `euclidPatternInto` / `euclidReadIndex` for the pattern, plain arithmetic for the rest) at each BLUE tick.
    func testHitsClockAgreesWithAnIndependentCountAcrossRatesDirectionsAndWindows() {
        struct Case { let k: Int, n: Int, rot: Int, dir: EuclidDir, red: ArpRate, blue: ArpRate, main: Int, alt: Int, off: Int, unit: HocketUnit }
        let cases: [Case] = [
            Case(k: 3, n: 8, rot: 0, dir: .fwd, red: .r1_16, blue: .r1_16, main: 2, alt: 1, off: 0, unit: .hits),
            Case(k: 5, n: 16, rot: 3, dir: .bkw, red: .r1_16, blue: .r1_32, main: 3, alt: 2, off: 1, unit: .hits),
            Case(k: 4, n: 7, rot: 2, dir: .fwd, red: .r1_8, blue: .r1_16, main: 1, alt: 1, off: 0, unit: .hits),
            Case(k: 3, n: 5, rot: 1, dir: .pingpong, red: .r1_16, blue: .r1_16, main: 2, alt: 2, off: 3, unit: .hits),
            Case(k: 3, n: 8, rot: 0, dir: .fwd, red: .r1_16t, blue: .r1_16, main: 2, alt: 1, off: 0, unit: .hits),
            Case(k: 5, n: 8, rot: 2, dir: .fwd, red: .r1_8d, blue: .r1_32, main: 1, alt: 2, off: 1, unit: .hits),
            Case(k: 3, n: 8, rot: 0, dir: .fwd, red: .r1_16, blue: .r1_16, main: 2, alt: 1, off: 0, unit: .passes),
            Case(k: 5, n: 7, rot: 1, dir: .bkw, red: .r1_8, blue: .r1_16, main: 1, alt: 1, off: 0, unit: .passes),
            Case(k: 4, n: 6, rot: 0, dir: .pingpong, red: .r1_16, blue: .r1_32, main: 2, alt: 1, off: 1, unit: .passes),
        ]
        for (ci, c) in cases.enumerated() {
            var lanes = (0..<4).map { laneLine($0, riff: false, notes: false) }
            lanes[0].pulses = c.k; lanes[0].steps = c.n; lanes[0].rotate = c.rot; lanes[0].direction = c.dir; lanes[0].rate = c.red
            lanes[1] = laneLine(1, riff: true, notes: false); lanes[1].pulses = 8; lanes[1].steps = 8; lanes[1].rate = c.blue; lanes[1].gate = 0.5
            lanes[0].riffOn = true; lanes[0].useRiff = true            // RED plays too (not needed for the count, but a real lane)
            let rules = [rule(main: [BR, RR], alt: [GR]) { $0.unit = c.unit; $0.mainLen = c.main; $0.altLen = c.alt; $0.offset = c.off; $0.countOn = 1 }]
            var pat = [Bool](repeating: false, count: 32); euclidPatternInto(&pat, pulses: c.k, steps: c.n, rotation: c.rot)
            let cyc = euclidCycleLen(c.dir, n: c.n)
            let hitsPerCycle = (0..<cyc).filter { pat[euclidReadIndex($0, n: c.n, dir: c.dir)] }.count
            func redCount(_ m: Double) -> Int64 {                        // the engine's definition: hits at or before m, minus one; PASSES = whole cycles done
                let lastTick = Int64((m / c.red.beats + 1e-9).rounded(.down))
                if c.unit == .passes { return lastTick / Int64(cyc) }
                var n: Int64 = 0
                for t in 0...max(0, lastTick) where pat[euclidReadIndex(Int(t % Int64(cyc)), n: c.n, dir: c.dir)] { n += 1 }
                return max(0, n - 1)
            }
            _ = hitsPerCycle
            var want: [Double] = []
            var j = 0
            while Double(j) * c.blue.beats < 8 - 0.01 {
                let m = Double(j) * c.blue.beats
                let t = hocketTurn(x: redCount(m), offset: c.off, mainLen: c.main, altLen: c.alt)
                if !t.isAlt { want.append((m * 1000).rounded() / 1000) }
                j += 1
            }
            for frames in [UInt32(480), 8192] {
                let e = render(doc(lanes: lanes, rules: rules), beats: 8, frames: frames)
                let got = beats(e.ons(blueRiff))
                XCTAssertEqual(got, want, "case \(ci) (\(c)) at \(frames) frames: BLUE RIFF sounds on the MAIN turns the independent count predicts")
                XCTAssertTrue(!want.isEmpty && want.count < Int(8 / c.blue.beats) - 2, "case \(ci): the oracle must mix MAIN and ALT turns (\(want.count) of \(Int(8 / c.blue.beats)))")
            }
        }
    }

    /// The same oracle, for what a RHYTHM restart chain, HIT TIMING (OFFSET's fraction) and a COPY lane do to the count.
    func testHitsClockAgreesWithAnIndependentCountForRestartsTimingAndCopy() {
        struct Case { let name: String; let k: Int, n: Int, rot: Int; let red: ArpRate; let blue: ArpRate; let restart: [UInt8]?; let frac: Double; let copyOfAmber: Bool }
        let cases: [Case] = [
            Case(name: "restart every bar", k: 3, n: 8, rot: 0, red: .r1_16, blue: .r1_16, restart: [1], frac: 0, copyOfAmber: false),
            Case(name: "restart every 2 bars", k: 5, n: 7, rot: 1, red: .r1_16, blue: .r1_32, restart: [2], frac: 0, copyOfAmber: false),
            Case(name: "restart every bar, triplets", k: 3, n: 8, rot: 0, red: .r1_16t, blue: .r1_16, restart: [1], frac: 0, copyOfAmber: false),
            Case(name: "offset fraction 0.5", k: 3, n: 8, rot: 0, red: .r1_16, blue: .r1_32, restart: nil, frac: 0.5, copyOfAmber: false),
            Case(name: "offset fraction 0.25", k: 5, n: 8, rot: 2, red: .r1_16, blue: .r1_32, restart: nil, frac: 0.25, copyOfAmber: false),
            Case(name: "copy lane (AMBER's E(5,8,2))", k: 5, n: 8, rot: 2, red: .r1_16, blue: .r1_16, restart: nil, frac: 0, copyOfAmber: true),
        ]
        for c in cases {
            var lanes = (0..<4).map { laneLine($0, riff: false, notes: false) }
            lanes[0].pulses = c.k; lanes[0].steps = c.n; lanes[0].rotate = c.rot; lanes[0].rate = c.red
            lanes[0].riffOn = true; lanes[0].useRiff = true
            lanes[1] = laneLine(1, riff: true, notes: false); lanes[1].pulses = 8; lanes[1].steps = 8; lanes[1].rate = c.blue; lanes[1].gate = 0.5
            if let r = c.restart { lanes[0].restartRhythmBars = r }
            if c.frac > 0 { lanes[0].offsetFraction = c.frac }
            if c.copyOfAmber {
                lanes[0].pulses = 2; lanes[0].steps = 8; lanes[0].rotate = 0                    // RED's OWN pattern is different; COPY replaces it with AMBER's
                lanes[2] = laneLine(2, riff: false, notes: false); lanes[2].pulses = c.k; lanes[2].steps = c.n; lanes[2].rotate = c.rot; lanes[2].rate = c.red
                lanes[0].listenRhythm = .copy; lanes[0].listenSource = 2
            }
            let rules = [rule(main: [BR, RR], alt: [GR]) { $0.mainLen = 2; $0.altLen = 1; $0.offset = 0; $0.countOn = 1 }]
            var pat = [Bool](repeating: false, count: 32); euclidPatternInto(&pat, pulses: c.k, steps: c.n, rotation: c.rot)
            let R = c.red.beats, barB = 4.0
            func redCount(_ m: Double) -> Int64 {
                var originBeat = 0.0
                if let r = c.restart, let b = r.first { originBeat = (m / (barB * Double(b))).rounded(.down) * barB * Double(b) }
                let originTick = Int64((originBeat / R).rounded())
                var n: Int64 = 0
                var t = originTick
                while (Double(t) + c.frac) * R <= m + 1e-9 { if pat[Int(t - originTick) % c.n] { n += 1 }; t += 1 }
                return max(0, n - 1)
            }
            var want: [Double] = []
            var j = 0
            while Double(j) * c.blue.beats < 8 - 0.01 {
                let m = Double(j) * c.blue.beats
                if !hocketTurn(x: redCount(m), offset: 0, mainLen: 2, altLen: 1).isAlt { want.append((m * 1000).rounded() / 1000) }
                j += 1
            }
            for frames in [UInt32(480), 8192] {
                let e = render(doc(lanes: lanes, rules: rules), beats: 8, frames: frames)
                XCTAssertEqual(beats(e.ons(blueRiff)), want, "\(c.name) at \(frames) frames: BLUE RIFF sounds on the MAIN turns the independent count predicts")
            }
        }
    }

    /// A rule that is LIT but changes nothing (every output of it sits in BOTH groups of a SWAP, so it always plays) must sound exactly like no rule: no same-key overlap exists in the default fixture, so join vs restrike can't differ.
    func testALitRuleThatChangesNothingSendsTheSameMessagesAsNoRuleAtAnyWindowSize() {
        let lanes = (0..<4).map { laneLine($0) }
        let inert = [rule(main: [RR, BN], alt: [RR, BN]) { $0.mainLen = 2; $0.altLen = 1 }, rule(main: [AR, GN], alt: [GN, AR]) { $0.mode = .swap; $0.mainLen = 1; $0.altLen = 3 }]
        for frames in [UInt32(480), 1024, 8192, 65_536] {
            let a = render(doc(lanes: lanes), beats: 8, frames: frames), b = render(doc(lanes: lanes, rules: inert), beats: 8, frames: frames)
            func key(_ e: HEmitter.Ev) -> String { "\(e.sample)/\(e.cable)/\(e.on)/\(e.chan)/\(e.note)/\(e.vel)" }
            XCTAssertEqual(b.events.map(key).sorted(), a.events.map(key).sorted(), "\(frames) frames: the same messages")
            // (the emission ORDER may differ: a lit rule holds a note's off until the end of its window — every message carries its own sample time)
        }
    }

    /// A LANE LOCK snap landing INSIDE a window (RED: live E(5,8), locked to E(3,8) on the bar line, beat 4): the HITS count RED reports must change over at the snap line, at the same instant the lane's own hits do.
    func testHitsClockFollowsALockSnapInsideAWindow() {
        var lanes = (0..<4).map { laneLine($0, riff: false, notes: false) }
        lanes[0].pulses = 3; lanes[0].steps = 8; lanes[0].riffOn = true; lanes[0].useRiff = true
        let locked = EuclideousLaneLock.locking(lanes[0], grid: .bar1)           // L = E(3, 8)
        lanes[0].pulses = 5                                                    // the live lane has moved off its lock
        lanes[1] = laneLine(1, riff: true, notes: false); lanes[1].pulses = 8; lanes[1].steps = 8; lanes[1].gate = 0.5
        let rules = [rule(main: [BR, RR], alt: [GR]) { $0.mainLen = 2; $0.altLen = 1; $0.offset = 0; $0.countOn = 1 }]
        var st = doc(lanes: lanes, rules: rules) { $0.euclideousLocks = [locked, EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()] }
        st = doc(lanes: lanes, rules: rules) { $0.euclideousLocks = [locked, EuclideousLaneLock(), EuclideousLaneLock(), EuclideousLaneLock()] }
        var live = [Bool](repeating: false, count: 32), lock = [Bool](repeating: false, count: 32)
        euclidPatternInto(&live, pulses: 5, steps: 8, rotation: 0); euclidPatternInto(&lock, pulses: 3, steps: 8, rotation: 0)
        func count(_ m: Double) -> Int64 {
            let pat = m < 4.0 - 1e-9 ? live : lock
            var n: Int64 = 0
            for t in 0...Int64((m / 0.25 + 1e-9).rounded(.down)) where pat[Int(t % 8)] { n += 1 }
            return max(0, n - 1)
        }
        for frames in [UInt32(480), 8192] {
            let box = SnapshotBuilder.build(from: st)
            let pool = NotePool(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
            let router = Router(); var diag = KernelDiag(); let e = HEmitter()
            var done = 0, beat = 3.0
            let total = Int(4.0 * 24_000) - 1
            while done < total {
                let n = UInt32(min(Int(frames), total - done))
                router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: Double(Int(3.0 * 24_000) + done), frameCount: n, out: e, diag: &diag)
                done += Int(n); beat += Double(n) * 120.0 / 60 / 48_000
            }
            let got = e.ons(blueRiff).map { ($0.beat * 1000).rounded() / 1000 }, redGot = e.ons(redRiff).map { ($0.beat * 1000).rounded() / 1000 }
            // RED's own hits tell where the snap really landed; BLUE's MAIN turns must follow the count of the pattern RED was playing at each instant
            var want: [Double] = []
            var j = 12
            while j < 28 { let m = Double(j) * 0.25; if !hocketTurn(x: count(m), offset: 0, mainLen: 2, altLen: 1).isAlt { want.append(m) }; j += 1 }
            XCTAssertEqual(got, want, "frames \(frames): BLUE's MAIN turns across the snap at beat 4 (RED's own hits: \(redGot))")        }
    }

    private func renderBpb(_ st: PluginState, beats: Double, bpb: Double, frames: UInt32 = 480) -> HEmitter {
        let box = SnapshotBuilder.build(from: st)
        let pool = NotePool(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        let router = Router(); var diag = KernelDiag(); let e = HEmitter()
        let total = Int(beats * 24_000) - 1
        var done = 0, beat = 0.0, ts = 0.0
        while done < total {
            let n = UInt32(min(Int(frames), total - done))
            router.process(box: box, pool: pool, playing: true, beatPos: beat, tempo: 120, beatsPerBar: bpb, sampleRate: 48_000, timestampSample: ts, frameCount: n, out: e, diag: &diag)
            done += Int(n); beat += Double(n) * 120.0 / 60 / 48_000; ts += Double(n)
        }
        router.process(box: box, pool: pool, playing: false, beatPos: beat, tempo: 120, beatsPerBar: bpb, sampleRate: 48_000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        return e
    }
    /// §6.2: BARS counts the HOST's bars — at 3/4 a bar is three beats, not four (the Router must pass `beatsPerBar` through).
    func testBarsFollowTheHostsBarLengthAtThreeFour() {
        let st = doc(rules: [rule(main: [RR], alt: [BR]) { $0.unit = .bars }])
        let e = renderBpb(st, beats: 12, bpb: 3)
        let all = (0..<24).map { Double($0) * 0.5 }
        XCTAssertEqual(beats(e.ons(redRiff)), all.filter { Int($0 / 3) % 2 == 0 }, "BARS at 3/4: RED RIFF in the even bars")
        XCTAssertEqual(beats(e.ons(blueRiff)), all.filter { Int($0 / 3) % 2 == 1 }, "BARS at 3/4: BLUE RIFF in the odd bars")
    }
    /// §0.1(f) / §7.2: a passed line sent to a lane that is LANES-muted, solo-silenced or PLAY-off is swallowed (decision 3) — silent on the output and on ALL.
    func testADestinationLaneThatIsMutedSoloSilencedOrPlayOffSwallowsAPassedLine() {
        var muted = (0..<4).map { laneLine($0, riff: false) }; muted[1].muteCells16 = 0
        var playOff = (0..<4).map { laneLine($0, riff: false) }; playOff[1].enabled = false
        let plain = (0..<4).map { laneLine($0, riff: false) }
        let cases: [(String, PluginState)] = [("LANES-muted", doc(lanes: muted, rules: crossingRules())),
                                              ("solo-silenced", doc(lanes: plain, rules: crossingRules()) { $0.euclideousSoloMask = 0b0101 }),
                                              ("PLAY-off", doc(lanes: playOff, rules: crossingRules()))]
        for (name, st) in cases {
            let e = render(st, beats: 12)
            XCTAssertTrue(e.ons(blueNotes).isEmpty, "\(name): BLUE plays nothing on BLUE NOTES")
            XCTAssertTrue(e.ons(redNotes).filter { $0.beat >= 4 && $0.beat < 8 }.isEmpty, "\(name): in bar 2 RED's line moved to BLUE's output and is swallowed there — and RED's own output is silent because the line moved")
            XCTAssertTrue(e.ons(0).filter { $0.beat >= 4 && $0.beat < 8 && ($0.chan == chanNibble(blueNotes) || $0.chan == chanNibble(redNotes)) }.isEmpty, "\(name): …and silent on ALL")
            XCTAssertFalse(e.ons(redNotes).filter { $0.beat < 4 }.isEmpty, "\(name): in bar 1 RED plays as normal")
        }
    }
    /// §6.5 SWAP + ROTATE with an output in BOTH groups ("o in both groups: o"): RED RIFF sounds on every turn; GREEN RIFF (MAIN only) only on MAIN turns; BLUE RIFF (ALT only) only on the ALT turns that ROTATE gives it.
    func testSwapRotateWithAnOutputInBothGroups() {
        let e = render(doc(rules: [rule(main: [RR, GR], alt: [RR, BR]) { $0.several = .rotate; $0.mainLen = 1; $0.altLen = 1; $0.unit = .hits }]), beats: 8)
        // every lane hits at 0, 0.5, 1.0 … : hit x sits at beat x/2; MAIN turns are even x, ALT turns odd x with k = x / 2 (rounded down): k even → ALT[0] = RED RIFF, k odd → ALT[1] = BLUE RIFF
        let allHits = (0..<16).map { Double($0) * 0.5 }
        XCTAssertEqual(beats(e.ons(redRiff)), allHits, "RED RIFF is in both groups: it sounds on every turn")
        XCTAssertEqual(beats(e.ons(greenRiff)), allHits.filter { Int($0 * 2) % 2 == 0 }, "GREEN RIFF (MAIN only) sounds on the MAIN turns")
        XCTAssertEqual(beats(e.ons(blueRiff)), allHits.filter { let x = Int($0 * 2); return x % 2 == 1 && (x / 2) % 2 == 1 }, "BLUE RIFF (ALT[1]) sounds on the ALT turns with an odd k")
        assertBalanced(e)
    }
    /// §7.3 on ALL: a pre-nine-ports document gives a lane's riff and notes ports ONE channel. With RED RIFF in a lit rule and RED NOTES in none, a pitch both play is ONE note-on on ALL while it sounds (the lit riff strikes first and
    /// the unlit notes join it); the lanes no rule touches (AMBER, GREEN) send exactly the messages they send with no rule at all — their own same-key collisions keep the engine's old re-articulation.
    func testSharedChannelsOnAllNeverSendASecondNoteOnForASoundingKeyAndUnlitLanesAreUntouched() {
        for frames in [UInt32(480), 8192] {
            let channels: (inout PluginState) -> Void = { $0.busChannels = [1, 1, 2, 2, 3, 3, 4, 4] }
            let st = doc(rules: [rule(main: [RR], alt: [BR]) { $0.mainLen = 1; $0.altLen = 1 }], configure: channels)
            let e = render(st, beats: 4, frames: frames), base = render(doc(configure: channels), beats: 4, frames: frames)
            var sounding: [String: Int] = [:], doubled: [String] = []
            for ev in e.events.sorted(by: { ($0.sample, $0.on ? 1 : 0) < ($1.sample, $1.on ? 1 : 0) }) where ev.cable == 0 && ev.chan == 0 {      // RED's shared channel (wire nibble 0)
                let k = "ch\(ev.chan)-\(ev.note)"
                if ev.on { if (sounding[k] ?? 0) > 0 { doubled.append("\(k)@\(ev.beat)") }; sounding[k, default: 0] += 1 } else { sounding[k, default: 0] -= 1 }
            }
            XCTAssertTrue(doubled.isEmpty, "\(frames) frames: a second note-on on ALL for a key already sounding: \(doubled)")
            XCTAssertTrue(sounding.values.allSatisfy { $0 == 0 }, "\(frames) frames: every note ended")
            func key(_ ev: HEmitter.Ev) -> String { "\(ev.sample)/\(ev.cable)/\(ev.on)/\(ev.chan)/\(ev.note)/\(ev.vel)" }
            let untouched: (HEmitter.Ev) -> Bool = { $0.cable == 5 || $0.cable == 6 || $0.cable == 7 || $0.cable == 8 || ($0.cable == 0 && ($0.chan == 2 || $0.chan == 3)) }
            XCTAssertEqual(e.events.filter(untouched).map(key).sorted(), base.events.filter(untouched).map(key).sorted(), "\(frames) frames: AMBER's and GREEN's outputs are exactly what they are with no rule")
        }
    }
    /// A rule that is lit WHILE a note of its key is sounding (struck before the rule existed) must not double that key: the strike after the edit re-articulates it as it always did, and the note groups begin with the next strike.
    func testARuleLitWhileAPlainNoteSoundsNeverDoublesItsKey() {
        var lanes = (0..<4).map { laneLine($0, riff: false) }
        for i in [0, 1] { lanes[i].octave = 0 }
        lanes[1].notesGate = 0.9; lanes[0].rotate = 1; lanes[0].notesGate = 0.25         // BLUE strikes C4 at 0.0 (sounding to 0.45); RED strikes C4 at 0.25 — passed to BLUE NOTES once the rule is lit
        let before = doc(lanes: lanes), after = doc(lanes: lanes, rules: [rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.own = .merge; $0.offset = 1 }])
        let boxA = SnapshotBuilder.build(from: before), boxB = SnapshotBuilder.build(from: after)
        let pool = NotePool(); for n in [60, 64, 67] { pool.noteOn(UInt8(n), velocity: 100, channel: 0) }
        let router = Router(); var diag = KernelDiag(); let e = HEmitter()
        var beat = 0.0, ts = 0.0
        for w in 0..<100 {                                                    // 480-frame windows; the rule is lit from the 3rd window (beat 0.04)
            router.process(box: w < 2 ? boxA : boxB, pool: pool, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 480, out: e, diag: &diag)
            beat += 480.0 * 120.0 / 60 / 48_000; ts += 480
        }
        router.process(box: boxB, pool: pool, playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        var sounding: [String: Int] = [:], doubled: [String] = []
        for ev in e.events {                                                  // EMISSION order: a restrike is on / off / on, never on / on
            let k = "c\(ev.cable)-ch\(ev.chan)-\(ev.note)"
            if ev.on { if (sounding[k] ?? 0) > 0 { doubled.append("\(k)@\(ev.beat)") }; sounding[k, default: 0] += 1 } else { sounding[k, default: 0] -= 1 }
        }
        XCTAssertTrue(doubled.isEmpty, "a note-on for a key already sounding: \(doubled)")
        XCTAssertTrue(sounding.values.allSatisfy { $0 == 0 }, "every note ended: \(sounding.filter { $0.value != 0 })")
    }
    /// A RATCHET's repeats all take the turn of the hit's FIRST strike, even when a later repeat falls in the next STEPS count.
    func testRatchetRepeatsKeepTheFirstStrikesTurnAcrossAStepBoundary() {
        var lanes = (0..<4).map { laneLine($0) }
        lanes[0].rate = .r1_8                                                  // RED hits every 0.5 beat
        var fx = EuclideousFX(); fx.cells[0] = 4; fx.lanes[0] = 0b0001           // RATCH ×4 on column 1, RED only: strikes at 0, .125, .25, .375 — the 2nd sixteenth starts at .25
        let e = render(doc(lanes: lanes, rules: [rule(main: [RR], alt: [BR]) { $0.unit = .steps }]) { $0.euclideousFX = fx }, beats: 1)
        XCTAssertEqual(beats(e.ons(redRiff)).filter { $0 < 0.5 }, [0, 0.125, 0.25, 0.375], "all four ratchet strikes take the first strike's turn (MAIN, x = 0)")
        XCTAssertTrue(beats(e.ons(blueRiff)).filter { $0 < 0.5 }.isEmpty)
    }
}
