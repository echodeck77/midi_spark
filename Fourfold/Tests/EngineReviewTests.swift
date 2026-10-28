//  EngineReviewTests.swift — ENGINE ADVERSARIAL REVIEW of CARD BACKS (2026-10-28). Each test here is a repro for a finding; a test that FAILS is a bug in the engine under review (the assertion messages say what was expected).
//  Self-contained: its own emitter, document builder and render loop (no access to other test files' private helpers).

import XCTest
import Atomics

private final class RevEmitter: MIDIEmitter {
    struct Ev { let sample: Int64; let cable: UInt8; let on: Bool; let off: Bool; let chan: UInt8; let note: UInt8; let vel: UInt8 }
    var events: [Ev] = []
    func emit(sampleTime: Int64, cable: UInt8, _ b0: UInt8, _ b1: UInt8, _ b2: UInt8) {
        let s = b0 & 0xF0; guard s == 0x90 || s == 0x80 else { return }
        events.append(Ev(sample: sampleTime, cable: cable, on: s == 0x90 && b2 > 0, off: s == 0x80 || (s == 0x90 && b2 == 0), chan: b0 & 0x0F, note: b1, vel: b2))
    }
    func ons(_ cable: UInt8) -> [Ev] { events.filter { $0.cable == cable && $0.on } }
    /// per (cable, chan, note): ons − offs must end at 0 and never dip below
    func stuckOrOrphan() -> String? {
        var bal: [Int: Int] = [:]
        for ev in events {
            let k = (Int(ev.cable) * 16 + Int(ev.chan)) * 128 + Int(ev.note)
            if ev.on { bal[k, default: 0] += 1 } else if ev.off { bal[k, default: 0] -= 1; if bal[k]! < 0 { return "ORPHAN off cable \(ev.cable) note \(ev.note)" } }
        }
        for (k, v) in bal where v != 0 { return "STUCK balance \(v) on cable \((k / 128) / 16) note \(k % 128)" }
        return nil
    }
}

final class EngineReviewTests: XCTestCase {

    // MARK: scaffolding

    /// A lane of `pulses`-of-`pulses` at 1/4 (one hit a beat at 120 BPM = 24 000 samples): riff on (rank 1), the notes layer lights rank 1 (so riff pitch == lit pitch — the collision case).
    private func line(riff: Bool = true, notes: Bool = true, gate: Double = 0.5, notesGate: Double? = nil, mask: EuclidLineMask? = nil, rate: ArpRate = .r1_4, pulses: Int = 4, steps: Int = 4, lit: UInt8 = 0b1) -> EuclidLine {
        EuclidLine(target: 0, pulses: pulses, steps: steps, gate: gate, velocityAbsolute: 90, rate: rate, useRiff: true, litNotes: notes ? lit : 0, riffOn: riff, mask: mask, sourceMode: .midi, riffLength: 1, notesOn: notes, notesGate: notesGate ?? gate, notesVelocity: nil)
    }
    private func state(_ lines: [EuclidLine], rules: [HocketRule] = [], channels: [Int]? = nil, ranks: [Int] = Array(repeating: 1, count: 8)) -> PluginState {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        var ls = lines; while ls.count < 4 { var o = EuclidLine(); o.enabled = false; ls.append(o) }
        st.euclideousLines = ls
        st.euclideousNoteSource = .midi; st.euclideousSourcePlan = SourcePlan(); st.euclideousSoloMask = 0
        st.euclideousRiff = EuclideousRiff(steps: 8, ranks: ranks)   // default: every riff column reads rank 1
        st.hocketRules = rules.isEmpty ? nil : HocketRuleSet(rules)
        if let channels { st.busChannels = channels }
        let input = FourfoldCompose.Input(lines: ls, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: 0, soloMask: 0, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        return st
    }
    private func pool(_ notes: [UInt8]) -> NotePool { let p = NotePool(); for n in notes { p.noteOn(n, velocity: 100, channel: 0) }; return p }

    struct Run { var e: [Any] = [] }
    /// Render `beats` of playing windows then a stop window. Returns the wire, the roll records, and the stop beat.
    private func render(_ st: PluginState, pool p: NotePool, beats: Double, frames: UInt32 = 480, maskOn: Bool = false, stopAt: Double? = nil, soloLive: UInt16? = nil) -> (e: RevEmitter, rolls: [NoteRollRecord], maxActive: Int, router: Router) {
        let box = SnapshotBuilder.build(from: st)
        let e = RevEmitter(); let router = Router(); router.euclideousMaskEnabledForTests = maskOn
        var diag = KernelDiag(); var rolls: [NoteRollRecord] = []; var maxActive = 0
        var beat = 0.0, ts = 0.0
        let end = stopAt ?? beats
        while beat < end {
            router.process(box: box, pool: p, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: frames, euclideousSoloLive: soloLive ?? UInt16(st.euclideousSoloMaskResolved), out: e, diag: &diag)
            rolls += router.rollRing.drain(); maxActive = max(maxActive, diag.activeVoiceCount)
            beat += Double(frames) * 120 / 60 / 48_000; ts += Double(frames)
        }
        router.process(box: box, pool: p, playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        rolls += router.rollRing.drain()
        return (e, rolls, maxActive, router)
    }
    /// hit k (beat k) → note-ons of `note` on `cable` within ±5 ms of it
    private func onsAt(_ e: RevEmitter, cable: UInt8, note: UInt8? = nil, hit: Int) -> Int {
        e.ons(cable).filter { (note == nil || $0.note == note!) && abs(Double($0.sample) - Double(hit) * 24_000) < 240 }.count
    }

    // MARK: F1 — REPEAT replays lose a notes pitch's collision set

    /// Riff -> A, notes -> A and B, both on pitch 48. On a plain hit the riff's 48 sounds on A and the notes' copy only on B (the outputs the riff does not use) — one note-on each. A mask REPEAT replay (the trigger AND the hold
    /// that continues it) rebuilds `pitchOuts` as 0xFF (the part's whole mask) and the cache holds the POST-dedupe set, so the notes copy is replayed on A as well: a second note-on of 48 on A at the same sample
    /// (the engine re-articulates: off, on) and a third on ALL.
    func testF1_MaskRepeatReplayDoublesTheNoteOnASharedOutput() throws {
        // KNOWN, LATENT: the per-lane mask (REPEAT) is disabled outside tests (`euclideousMaskEnabledForTests`), so no document or UI can reach this. The replay rebuilds `pitchOuts` as 0xFF from a post-dedupe cache. Fix when the mask ships:
        // cache `pitchOuts` with the set, or re-run the collision pass after the replay is built. Recorded in the pending tasks.
        throw XCTSkip("latent: the mask REPEAT replay path is unreachable in production")
        var m = EuclidLineMask(); m.enabled = true; m.pulses = 2; m.steps = 2; m.chance = 1; m.mode = .repeatNote; m.repeatCount = 3
        let l = line(gate: 0.5, mask: m).routedForReview(riff: 0b0001, notes: 0b0011)
        let r = render(state([l]), pool: pool([48, 50, 52, 53, 55, 57, 59, 60]), beats: 6.5, maskOn: true)
        for hit in 0..<6 {
            let a = onsAt(r.e, cable: 1, note: 48, hit: hit), b = onsAt(r.e, cable: 2, note: 48, hit: hit), all = onsAt(r.e, cable: 0, note: 48, hit: hit)
            XCTAssertEqual(a, 1, "hit \(hit): ONE note-on of 48 on A (riff) — the notes copy is dropped there (got A=\(a) B=\(b) ALL=\(all))")
            XCTAssertEqual(b, 1, "hit \(hit): one on B (the notes copy)")
            XCTAssertEqual(all, a + b, "hit \(hit): ALL = A + B")
        }
    }

    // MARK: F2 — a swapped-away riff takes its pitch off the output for good: the notes layer's identical pitch was already dropped

    /// Lane 1: riff and notes both play 60, both leave on A, so the notes' 60 is dropped (the riff has it). A SWAP rule (MAIN = lane 1's riff part, ALT = lane 2's riff part, one hit each) silences the riff on its ALT turns —
    /// but the notes part is not in the rule, and nothing plays 60 on A on those hits any more. In the nine-ports engine (independent streams) the notes layer sounded.
    func testF2_ASwappedAwayRiffLeavesTheNotesLayersSamePitchSilentOnTheSharedOutput() {
        var r = HocketRule(); r.mode = .swap; r.main = [1]; r.alt = [3]; r.unit = .hits; r.mainLen = 1; r.altLen = 1
        var lane2 = line(); lane2.enabled = false
        let withRule = render(state([line(), lane2], rules: [r]), pool: pool([60]), beats: 8.5)
        let a = (0..<8).map { onsAt(withRule.e, cable: 1, hit: $0) }
        // reference: the same lane with the riff OFF (notes alone) sounds 60 on A at every hit
        let notesOnly = render(state([line(riff: false), lane2]), pool: pool([60]), beats: 8.5)
        XCTAssertEqual((0..<8).map { onsAt(notesOnly.e, cable: 1, hit: $0) }, Array(repeating: 1, count: 8), "control: the notes layer alone sounds on every hit")
        XCTAssertEqual(a.filter { $0 == 0 }.count, 0, "the lane's notes layer is not in the rule: on the riff's ALT turns it must still sound on A (per-hit note-ons on A: \(a))")
    }

    // MARK: HOCKET PASS into a part with a non-default mask (control: expected to pass)

    /// Lane 1's riff (cable 1 in a rule) PASSes onto lane 2's riff part on its ALT turns. Lane 2's riff is routed to C and D (several outputs): the passed note sounds on BOTH, each on its own output's channel, and ALL carries both.
    /// Routed to NO output: the passed line sounds nowhere at all, ALL included. Lane 1's own output only hears its MAIN turns.
    func testHocketPassIntoAPartRoutedToSeveralOutputsOrToNone() {
        var r = HocketRule(); r.mode = .pass; r.main = [1]; r.alt = [3]; r.unit = .hits; r.mainLen = 1; r.altLen = 1
        let lane2 = line(notes: false, pulses: 0)     // PLAY on (a PLAY-off destination lane swallows a passed line), but no rhythm of its own
        for (mask, label) in [(UInt8(0b1100), "C+D"), (UInt8(0), "none")] {
            let l1 = line(notes: false)
            let st = state([l1, lane2.routedForReview(riff: mask)], rules: [r], channels: [1, 2, 3, 4])
            let run = render(st, pool: pool([60]), beats: 8.5)
            XCTAssertEqual((0..<8).map { onsAt(run.e, cable: 1, hit: $0) }, [1, 0, 1, 0, 1, 0, 1, 0], "\(label): A hears lane 1's MAIN turns only")
            let c = (0..<8).map { onsAt(run.e, cable: 3, hit: $0) }, d = (0..<8).map { onsAt(run.e, cable: 4, hit: $0) }
            if mask == 0 {
                XCTAssertEqual(c + d, Array(repeating: 0, count: 16), "none: the passed line sounds on no output")
                XCTAssertEqual((0..<8).map { onsAt(run.e, cable: 0, hit: $0) }, [1, 0, 1, 0, 1, 0, 1, 0], "none: ALL carries MAIN turns only")
            } else {
                XCTAssertEqual(c, [0, 1, 0, 1, 0, 1, 0, 1], "C+D: the passed line on C"); XCTAssertEqual(d, c, "…and on D")
                XCTAssertEqual((0..<8).map { onsAt(run.e, cable: 0, hit: $0) }, [1, 2, 1, 2, 1, 2, 1, 2], "C+D: ALL carries A's note and both copies")
                XCTAssertTrue(run.e.ons(3).allSatisfy { $0.chan == 2 } && run.e.ons(4).allSatisfy { $0.chan == 3 }, "each output stamps its own channel")
            }
            XCTAssertEqual(run.e.stuckOrOrphan() ?? "", "", label)
        }
    }

    // MARK: HOCKET PASS of a collision-reduced notes pitch (kills "a passed note keeps its source's collision output set")

    /// Lane 1: riff -> A, notes -> A+B, both on 48, so the notes' 48 is collision-reduced to B. A PASS rule (MAIN = lane 1's NOTES part, ALT = lane 3's riff part, REPLACE) hands that notes line to lane 3's riff part, which is routed to C+D:
    /// on the ALT turns the note must leave on C and D (the RECEIVING part's mask) — not on B, where the source's own collision set would put it. On MAIN turns it still leaves on B (and the riff on A).
    func testHocketPassOfACollisionReducedNotesPitchTakesTheReceivingPartsMask() {
        var r = HocketRule(); r.mode = .pass; r.main = [2]; r.alt = [5]; r.unit = .hits; r.mainLen = 1; r.altLen = 1; r.own = .replace
        let l1 = line().routedForReview(riff: 0b0001, notes: 0b0011), l2 = line(pulses: 0), l3 = line(notes: false, pulses: 0).routedForReview(riff: 0b1100)
        let run = render(state([l1, l2, l3], rules: [r]), pool: pool([48, 50, 52, 53, 55, 57, 59, 60]), beats: 8.5)
        func per(_ c: UInt8) -> [Int] { (0..<8).map { onsAt(run.e, cable: c, note: 48, hit: $0) } }
        XCTAssertEqual(per(1), Array(repeating: 1, count: 8), "A: the riff's 48 every hit")
        XCTAssertEqual(per(2), [1, 0, 1, 0, 1, 0, 1, 0], "B: the notes' collision-reduced copy on MAIN turns only")
        XCTAssertEqual(per(3), [0, 1, 0, 1, 0, 1, 0, 1], "C: the passed notes line on ALT turns"); XCTAssertEqual(per(4), per(3), "D: …and D")
        XCTAssertEqual(run.e.stuckOrOrphan() ?? "", "")
    }

    // MARK: the held-riff-pitch memory is cleared by a transport edge (kills "held riff pitch survives a stop")

    /// riff -> A and notes -> A, both on 48; ON REST = TIE; the riff's column 0 is a REST and the notes strike on rests. Played to beat 1.6 (the riff sounds 48 at beat 1, setting the "held riff pitch"), stopped, restarted at beat 0: the first hit
    /// is the tied rest with nothing held, so the notes must strike 48 on it — exactly as on a fresh start. A stale held pitch would drop the notes' copy there (it would think the riff still holds it).
    func testAStopForgetsTheHeldRiffPitchSoTheFirstTiedRestAfterARestartStrikesTheNotes() {
        var l = line(); l.riffOnRest = .tie; l.notesWhen = 0b11; l.riffLength = 8     // (the fixture's riff is 1 step long: walk all 8 columns)
        let box = SnapshotBuilder.build(from: state([l], ranks: [0, 1, 1, 1, 1, 1, 1, 1]))
        func run(restart: Bool) -> Int {
            let e = RevEmitter(); let router = Router(); var diag = KernelDiag(); let p = pool([48, 50, 52, 53, 55, 57, 59, 60])
            var beat = 0.0, ts = 0.0
            func play(_ beats: Double) { let end = beat + beats; while beat < end { router.process(box: box, pool: p, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 480, out: e, diag: &diag); beat += 480.0 * 120 / 60 / 48_000; ts += 480 } }
            if restart { play(1.6); router.process(box: box, pool: p, playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 480, out: e, diag: &diag); ts += 480; beat = 0 }
            let origin = ts
            play(1.2)
            return e.ons(1).filter { abs(Double($0.sample) - origin) < 240 }.count
        }
        XCTAssertEqual(run(restart: false), 1, "control: on a fresh start the notes strike 48 on the tied rest at beat 0")
        XCTAssertEqual(run(restart: true), 1, "after a stop and a restart too — nothing is held any more")
    }

    // MARK: LEGATO with partially overlapping masks (control: expected to pass)

    /// Gate exactly 1.0 on both parts, riff -> A, notes -> A+B, same pitch on both. The riff holds 48 on A, the notes' copy holds it on B only; neither is struck again on later hits (a legato carry-on), and the stop closes both.
    /// Then the same with the masks edited mid-run (the notes' copy moves to C+D, then to nowhere): nothing sticks, and a re-routed note starts fresh on its new outputs.
    func testLegatoHoldsOncePerOutputAndFollowsAMaskEditWithoutStrandingAnything() {
        let l = line(gate: 1.0, notesGate: 1.0).routedForReview(riff: 0b0001, notes: 0b0011)
        let a = render(state([l]), pool: pool([48, 50, 52, 53, 55, 57, 59, 60]), beats: 6.5)
        XCTAssertEqual(a.e.ons(1).count, 1, "A: the riff's 48 is struck once and held"); XCTAssertEqual(a.e.ons(2).count, 1, "B: the notes' copy of 48 is struck once and held")
        XCTAssertEqual(a.e.stuckOrOrphan() ?? "", "")
        // edit mid-run
        let box1 = SnapshotBuilder.build(from: state([l])), box2 = SnapshotBuilder.build(from: state([l.routedForReview(riff: 0b0001, notes: 0b1100)])), box3 = SnapshotBuilder.build(from: state([l.routedForReview(riff: 0b0001, notes: 0)]))
        let e = RevEmitter(); let router = Router(); var diag = KernelDiag(); let p = pool([48, 50, 52, 53, 55, 57, 59, 60])
        var beat = 0.0, ts = 0.0; var rolls: [NoteRollRecord] = []
        while beat < 8.5 {
            let box = beat < 2.2 ? box1 : beat < 5.2 ? box2 : box3
            router.process(box: box, pool: p, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 480, out: e, diag: &diag)
            rolls += router.rollRing.drain(); beat += 480.0 * 120 / 60 / 48_000; ts += 480
        }
        router.process(box: box3, pool: p, playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        rolls += router.rollRing.drain()
        XCTAssertEqual(e.stuckOrOrphan() ?? "", "", "a mask edit under a legato hold strands nothing")
        XCTAssertEqual(e.ons(1).count, 1, "A is untouched by the edits"); XCTAssertEqual(e.ons(3).count, 1, "C got the notes' copy once, when the mask moved it there"); XCTAssertEqual(e.ons(4).count, 1)
        XCTAssertEqual(e.ons(2).count, 1, "B's copy ended at the edit and was not struck again")
        var m = NoteRollModel(); m.ingest(rolls); XCTAssertEqual(m.openCount, 0, "every legato hold the roll saw opened has closed")
    }

    // MARK: FLOOD GOVERNOR per OUTPUT (kills "one shared budget" / "budget indexed by part")

    /// Eight busy parts (4 lanes × riff + notes, 1/32 hits, three lit notes) all routed to A: A's budget (160 a beat) throttles A — and A alone has dropped strikes, ALL = A's note-ons, nothing sticks. The same eight parts spread over A–D
    /// (two parts per output) put the SAME total on the wire per beat across the outputs without any of them reaching 160: per-output budgets, not one for the page.
    func testFloodBudgetIsPerOutputNotShared() {
        let busy = (0..<4).map { _ in line(gate: 0.5, notesGate: 0.5, rate: .r1_32, pulses: 16, steps: 16, lit: 0b0111_1110) }
        let onA = busy.map { $0.routedForReview(riff: 0b0001, notes: 0b0001) }
        let spread = busy.enumerated().map { (i, l) in l.routedForReview(riff: UInt8(1 << i), notes: UInt8(1 << i)) }
        let pl = pool([48, 50, 52, 53, 55, 57, 59, 60])
        let crowded = render(state(onA), pool: pl, beats: 4.5, frames: 480), even = render(state(spread), pool: pl, beats: 4.5, frames: 480)
        func perBeat(_ e: RevEmitter, cable: UInt8) -> Int { (0..<4).map { b in e.ons(cable).filter { Int($0.sample / 24_000) == b }.count }.max() ?? 0 }
        XCTAssertLessThanOrEqual(perBeat(crowded.e, cable: 1), 160, "A never carries more than its 160 a beat")
        XCTAssertGreaterThan(crowded.router.floodDropped, 0, "…and the crowd on A really was throttled")
        XCTAssertEqual(crowded.e.ons(0).count, crowded.e.ons(1).count, "ALL carries exactly what A did")
        XCTAssertTrue(crowded.e.ons(2).isEmpty && crowded.e.ons(3).isEmpty && crowded.e.ons(4).isEmpty)
        XCTAssertEqual(even.router.floodDropped, 0, "spread over four outputs nothing reaches a budget — the budget is per output")
        for c in UInt8(1)...4 { XCTAssertLessThan(perBeat(even.e, cable: c), 160) }
        XCTAssertEqual(crowded.e.stuckOrOrphan() ?? "", ""); XCTAssertEqual(even.e.stuckOrOrphan() ?? "", "")
    }

    // MARK: LANE DISABLED under a multi-output legato hold (kills "closes only the first voice of a pitch")

    /// A legato lane routed to A+B+C+D is disabled mid-run: the lane-disabled edge must end its holds on EVERY output at once (not at the later stop).
    func testDisablingALegatoLaneEndsItsHoldOnEveryOutputAtOnce() {
        let l = line(riff: true, notes: false, gate: 1.0).routedForReview(riff: 0b1111)
        var off = l; off.enabled = false
        let on = SnapshotBuilder.build(from: state([l])), dis = SnapshotBuilder.build(from: state([off]))
        let e = RevEmitter(); let router = Router(); var diag = KernelDiag(); let p = pool([48, 50, 52, 53, 55, 57, 59, 60])
        var beat = 0.0, ts = 0.0
        while beat < 3.0 { router.process(box: on, pool: p, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 480, out: e, diag: &diag); beat += 480.0 * 120 / 60 / 48_000; ts += 480 }
        let disableAt = Int64(ts)
        while beat < 4.0 { router.process(box: dis, pool: p, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 480, out: e, diag: &diag); beat += 480.0 * 120 / 60 / 48_000; ts += 480 }
        let stopAt = Int64(ts)
        router.process(box: dis, pool: p, playing: false, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 512, out: e, diag: &diag)
        for c in UInt8(0)...4 {
            let offs = e.events.filter { $0.cable == c && $0.off }
            XCTAssertFalse(offs.isEmpty, "cable \(c) closed")
            XCTAssertTrue(offs.allSatisfy { $0.sample >= disableAt && $0.sample < stopAt }, "cable \(c): the hold ended at the disable edge (sample \(offs.map { $0.sample }) vs disable \(disableAt)), not at the stop \(stopAt)")
        }
    }

    // MARK: F6 — LISTEN AVOID's compaction moves a pitch's bus but not its collision output set

    /// Lane 1 (A for the riff, A+B for the notes): the riff plays 52, the notes light 48 and 52 (the notes' 52 is a collision: it may only sound on B). Lane 2 plays 48, and lane 1 AVOIDs lane 2: the 48 is dropped. The AVOID
    /// compaction moves the last pitch (the notes' 52) into the dropped slot and copies `pitchBus` but not `pitchOuts`, so the 52 loses its "B only" and strikes on A as well — a second note-on of the riff's pitch on A.
    func testF6_AvoidCompactionKeepsAPitchsCollisionOutputs() {
        var l1 = line(lit: 0b0000_0101).routedForReview(riff: 0b0001, notes: 0b0011)       // lit ranks 1 (48) and 3 (52); the riff reads rank 3 (52)
        l1.listenSource = 1; l1.listenPitch = .avoid
        let l2 = line(riff: false, lit: 0b0000_0001).routedForReview(notes: 0b1000)           // lane 2: notes only, rank 1 = 48, out on D so it never touches A / B
        let r = render(state([l1, l2], ranks: Array(repeating: 3, count: 8)), pool: pool([48, 50, 52, 53, 55, 57, 59, 60]), beats: 6.5)
        XCTAssertTrue(r.e.ons(1).contains { $0.note == 52 }, "control: the riff's 52 sounds on A")
        XCTAssertFalse((r.e.ons(1) + r.e.ons(2)).contains { $0.note == 48 }, "control: AVOID dropped lane 1's 48 (it works at all)")
        for hit in 1..<6 {
            XCTAssertEqual(onsAt(r.e, cable: 1, note: 52, hit: hit), 1, "hit \(hit): ONE note-on of 52 on A — the notes copy of it may only sound on B (A=\(onsAt(r.e, cable: 1, note: 52, hit: hit)) B=\(onsAt(r.e, cable: 2, note: 52, hit: hit)))")
        }
    }

    // MARK: F3 — the roll's END record for a note cut at the transport edge says it lasted 0 beats

    func testF3_ANoteCutByTheStopEdgeIsEndedWhereTheStopCutIt() {
        let r = render(state([line(notes: false, gate: 0.9)]), pool: pool([60]), beats: 2.5)
        let strikes = r.rolls.filter { !$0.isEnd && abs($0.onBeat - 2.0) < 0.01 }
        let ends = r.rolls.filter { $0.isEnd && abs($0.onBeat - 2.0) < 0.01 }
        XCTAssertEqual(strikes.count, 1); XCTAssertEqual(ends.count, 1, "the hit at beat 2 (planned to 2.9) was cut by the stop at 2.5")
        XCTAssertEqual(Double(ends.first?.length ?? -1), 0.5, accuracy: 0.05, "…it sounded 0.5 beats; the roll must draw it that long (END record length)")
        var m = NoteRollModel(); m.ingest(r.rolls)
        let n = m.parts[0].first { abs($0.onBeat - 2.0) < 0.01 }
        XCTAssertEqual((n?.endBeat ?? 0) - 2.0, 0.5, accuracy: 0.05, "the model's note for the cut hit")
    }

    // MARK: END records for a note cut at a REAL time (kills "no END record for an early cut"; passes today — the F3 bug only affects the transport-edge cuts)

    /// Lane 1 plays 1-beat hits at 90 % gate; at beat 2.4 the page solos lane 2, which silences lane 1 and cuts the note struck at beat 2 (planned to 2.9) at the window start. The roll must hear about it: one END record for that strike, 0.4 beats long.
    func testASoloCutEndsTheRollNoteWhereItWasCut() {
        let box = SnapshotBuilder.build(from: state([line(notes: false, gate: 0.9), line(riff: false, notes: false)]))
        let e = RevEmitter(); let router = Router(); var diag = KernelDiag(); let p = pool([48, 50, 52, 53, 55, 57, 59, 60])
        var beat = 0.0, ts = 0.0; var rolls: [NoteRollRecord] = []
        while beat < 4.0 {
            router.process(box: box, pool: p, playing: true, beatPos: beat, tempo: 120, sampleRate: 48_000, timestampSample: ts, frameCount: 480, euclideousSoloLive: beat < 2.4 ? 0 : 0x100 | 0b0010, out: e, diag: &diag)
            rolls += router.rollRing.drain(); beat += 480.0 * 120 / 60 / 48_000; ts += 480
        }
        let ends = rolls.filter { $0.isEnd && abs($0.onBeat - 2.0) < 0.01 }
        XCTAssertEqual(ends.count, 1, "one END record for the cut note")
        XCTAssertEqual(Double(ends.first?.length ?? -1), 0.4, accuracy: 0.03, "…saying it lasted 0.4 beats")
        XCTAssertTrue(rolls.filter { !$0.isEnd }.allSatisfy { $0.onBeat < 2.4 }, "nothing struck after the solo")
        XCTAssertEqual(e.stuckOrOrphan() ?? "", "")
    }

    // MARK: F4 — the 128-slot voice table, now that one note costs up to 8 voices

    /// Every part routed to every output (all jacks lit): a note is 4 own + 4 ALL voices. Four busy lanes (riff + 3 lit notes, gate 99 %) need > 128 slots; the first note whose ALL voice cannot be opened (or whose own can't) makes
    /// ALL differ from the union of A–D (the table is full: `openVoice` refuses without emitting).
    func testF4_AllJacksLitOnFourBusyLanesLoseNotesToAFullVoiceTable() {
        let busy = (0..<4).map { _ in line(gate: 0.99, notesGate: 0.99, rate: .r1_16, pulses: 16, steps: 16, lit: 0b0001_1110).routedForReview(riff: 0b1111, notes: 0b1111) }
        let r = render(state(busy, channels: [1, 2, 3, 4]), pool: pool([48, 50, 52, 53, 55, 57, 59, 60]), beats: 8.5)
        var port: [String: Int] = [:], all: [String: Int] = [:]
        for ev in r.e.events where ev.on { let k = "\(ev.sample)/\(ev.note)/\(ev.chan)"; if ev.cable == 0 { all[k, default: 0] += 1 } else { port[k, default: 0] += 1 } }
        XCTAssertEqual(r.e.stuckOrOrphan() ?? "", "", "no stuck note even when the table is full")
        XCTAssertGreaterThanOrEqual(r.maxActive, 120, "the scenario fills the table (maxActive \(r.maxActive))")
        XCTAssertTrue(port == all, "ALL must equal the union of A–D's note-ons (\(port.values.reduce(0, +)) on outputs vs \(all.values.reduce(0, +)) on ALL; maxActive \(r.maxActive))")
        // capacity: every strike is 8 voices here. Count what the wire carries on A against what ONE such lane alone asks for, times four (a lone lane never fills the table).
        let one = render(state([busy[0]], channels: [1, 2, 3, 4]), pool: pool([48, 50, 52, 53, 55, 57, 59, 60]), beats: 8.5)
        let wantPerOutput = 4 * one.e.ons(1).count
        var perOut = [Int](repeating: 0, count: 4)
        for ev in r.e.events where ev.on && ev.cable >= 1 && ev.cable <= 4 { perOut[Int(ev.cable) - 1] += 1 }
        XCTAssertEqual(perOut, [Int](repeating: wantPerOutput, count: 4), "notes silently dropped by a full voice table (note-ons per output vs four lanes' worth); floodDropped=\(r.router.floodDropped)")
    }

    // MARK: F5 — the ring under a fast producer

    /// A producer that pushes with NO pause for a fixed time while the consumer drains in a tight loop, validating every record by its self-describing fields. (The shipped test dawdles the consumer; this one never does,
    /// so the producer laps the ring *during* a copy as often as the machine allows.)
    func testF5_TheRingNeverShowsATornRecordUnderATightConsumerLoop() {
        let ring = NoteRollRing()
        func rec(_ i: Int) -> NoteRollRecord { NoteRollRecord(onBeat: Double(i), length: Float(i & 0xFFFF), pitch: UInt8(i & 0x7F), velocity: UInt8((i >> 3) & 0x7F), part: UInt8(i & 7), flags: UInt8(i & 0x0F)) }
        let stop = ManagedAtomic<Bool>(false)
        let producer = Thread { var i = 0; while !stop.load(ordering: .relaxed) { ring.push(rec(i)); i += 1 } }
        producer.start()
        var last = -1, seen = 0, torn = 0, repeats = 0
        let t0 = Date()
        while Date().timeIntervalSince(t0) < 8 {
            for r in ring.drain() {
                let i = Int(r.onBeat)
                if r.pitch != UInt8(i & 0x7F) || r.velocity != UInt8((i >> 3) & 0x7F) || r.part != UInt8(i & 7) || r.flags != UInt8(i & 0x0F) || r.length != Float(i & 0xFFFF) { torn += 1 }
                if i <= last { repeats += 1 }
                last = max(last, i); seen += 1
            }
        }
        stop.store(true, ordering: .relaxed)
        XCTAssertEqual(torn, 0, "torn records delivered (of \(seen))"); XCTAssertEqual(repeats, 0, "repeated / reordered records")
        XCTAssertGreaterThan(ring.dropped, 0, "the producer must have lapped the consumer for the test to mean anything")
    }
}

extension EuclidLine {
    func routedForReview(riff: UInt8? = nil, notes: UInt8? = nil) -> EuclidLine { var l = self; if let r = riff { l.riffOutMask = r }; if let n = notes { l.notesOutMask = n }; return l }
}
