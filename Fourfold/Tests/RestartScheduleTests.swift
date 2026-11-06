//  RestartScheduleTests.swift — RESTART UNITS ferry (2026-11-04), tests 2–14: the schedule against the closed forms it replaces (equivalence over a sampled space), the ferry's own worked examples (riff-first, isorhythm, cross-lane
//  passes and riffs, WITH RHYTHM, a cross-lane cycle), the periodic wrap against a straight simulation, and a melody restart resetting the ordinals the NOTES part reads. Unless a test says otherwise: 1/8 steps (0.5 beat),
//  barBeats 4, riff length 8, FWD, ADV HIT, other lanes FREE.

import XCTest

final class RestartScheduleTests: XCTestCase {
    // MARK: helpers
    private func line(hits: Int, steps: Int, rate: ArpRate = .r1_8, dir: EuclidDir = .fwd, advanceStep: Bool = false) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: hits, steps: steps)
        l.rate = rate; l.direction = dir; l.riffAdvanceStep = advanceStep; l.useRiff = true; l.riffOn = true
        l.restartRhythmBars = []; l.restartMelodyPasses = []   // pinned: FREE / FREE
        return l
    }
    private func rhythm(_ l: inout EuclidLine, _ links: [UInt8], unit: EuclideousRhythmRestartUnit = .bar, source: Int? = nil) {
        l.restartRhythmBars = links; l.restartRhythmUnit = unit; l.restartRhythmSource = source; l.restartRhythmOn = nil
    }
    private func melody(_ l: inout EuclidLine, _ links: [UInt8], unit: EuclideousMelodyRestartUnit = .pass, source: Int? = nil, withRhythm: Bool = false) {
        l.restartMelodyPasses = links; l.restartMelodyUnit = unit; l.restartMelodySource = source; l.restartMelodyOn = nil; l.restartMelodyWithRhythm = withRhythm ? true : nil
    }
    private func four(_ l0: EuclidLine, _ l1: EuclidLine? = nil, _ l2: EuclidLine? = nil, _ l3: EuclidLine? = nil) -> [EuclidLine] {
        [l0, l1 ?? line(hits: 1, steps: 8), l2 ?? line(hits: 1, steps: 8), l3 ?? line(hits: 1, steps: 8)]
    }
    private func setFor(_ lines: [EuclidLine], bar: Double = 4, detect: Bool = true, maxBars: Int = 1024) -> EuclideousRestartScheduleSet {
        euclideousBuildRestartScheduleSet(euclideousScheduleInputs(lines: lines, barBeats: bar, defaultRateBeats: 0.25, riffColumns: 8), engagedMask: 0, maxBars: maxBars, detectPeriod: detect)
    }
    private func cfg(_ lines: [EuclidLine], lane: Int = 0, set: EuclideousRestartScheduleSet?, bar: Double = 4) -> EuclideousWalkLaneConfig {
        euclideousWalkLaneConfig(lane: lane, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, defaultRateBeats: 0.25, beatsPerBar: bar, scheduleSet: set)!
    }
    private func hits(_ c: EuclideousWalkLaneConfig, beats: Double) -> [(beat: Double, col: Int, ord: Int64)] {
        var out: [(Double, Int, Int64)] = []
        for t in 0..<Int((beats / c.sub).rounded(.up)) { let w = euclideousWalkTick(c, tick: Int64(t)); if w.isHit { out.append((Double(t) * c.sub, w.playedStep + 1, w.advOrd)) } }
        return out
    }
    private func restarts(_ next: (Double) -> Double?, upTo: Double) -> [Double] {
        var out: [Double] = [], b = 0.0
        while let n = next(b), n < upTo { out.append(n); b = n; if out.count > 5000 { break } }
        return out
    }
    private func close(_ a: [Double], _ b: [Double], _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a.count, b.count, msg + " \(a) vs \(b)", file: file, line: line)
        for (x, y) in zip(a, b) { XCTAssertEqual(x, y, accuracy: 1e-9, msg, file: file, line: line) }
    }
    private func footers(_ c: EuclideousWalkLaneConfig, passes: Range<Int64>) -> [[Int]] {
        passes.map { q in
            euclideousRiffFooterList(pass: q, buf: c.buf, n: c.n, dir: c.dir, cycleLen: euclidCycleLen(c.dir, n: c.n), sub: c.sub, chains: c.chains, legacySpanBeats: c.spanBeats, advanceStep: c.advanceStep,
                                     riffDir: c.riffDir, stride: c.stride, length: c.length, shift: c.rotate, every: c.every, seed: c.seed).map { $0.column + 1 }
        }
    }

    // MARK: test 2 — equivalence with the closed forms (5.3)

    /// Every setting that existed before the ferry: rhythm FREE or BAR chains of up to four links, melody FREE or own-PASS chains, WITH RHYTHM off. The full cross product is 7 step counts × 4 rates × 3 directions × 11 rhythm chains × 7 melody chains
    /// = 6,468 cases of 64 bars; every 9th (by a fixed index) is run — 720 cases, covering every step count, rate, direction, rhythm chain and melody chain — at EVERY tick, in ADV HIT and ADV STEP, with the schedule FORCED onto the lane (the Router
    /// attaches it only to lanes the closed forms cannot express): `euclideousWalkTick` (hit, ordinal, riff step) plus the origins, next restarts, pass index and pass start the readers hand back, and the tiles. For a dyadic step (1/16, 1/8, dotted 1/8)
    /// every beat is exact in binary and the schedule must equal the closed forms exactly. A 1/8 TRIPLET step (1/3) has no exact beats: the closed forms and the table round a restart beat a hair differently, which can floor a tick boundary either
    /// way — so for triplets the BEAT-level readers are held to 1e-9 and a differing tick is counted, not failed (it is why such a lane keeps the closed forms).
    func testTheScheduleEqualsTheClosedFormsForEverySampledPreFeatureSetting() {
        let stepCounts = [2, 3, 5, 7, 8, 11, 16]
        let rates: [ArpRate] = [.r1_16, .r1_8, .r1_8d, .r1_8t]
        let dirs: [EuclidDir] = [.fwd, .bkw, .pingpong]
        let rhythms: [[UInt8]] = [[], [1], [2], [3], [4], [8], [2, 1, 1], [1, 2], [3, 3], [8, 8, 8, 8], [6, 2]]
        let melodies: [[UInt8]] = [[], [1], [2], [3], [2, 1, 1], [8], [4, 4]]
        var idx = 0, ran = 0, tripletTickDiffs = 0, tripletCombos = 0
        for steps in stepCounts { for rate in rates { for dir in dirs { for r in rhythms { for m in melodies {
            idx += 1
            guard idx % 9 == 0 else { continue }
            ran += 1
            let adv = (idx / 9) % 2 == 1
            var l = line(hits: max(1, steps * 3 / 8), steps: steps, rate: rate, dir: dir, advanceStep: adv)
            rhythm(&l, r); melody(&l, m)
            let lines = four(l)
            let set = setFor(lines)
            let closed = cfg(lines, set: nil)
            var sched = closed; sched.chains.schedule = set.lane(0)
            let ctx = "steps \(steps) \(rate.rawValue) \(dir) rhythm \(r) melody \(m) adv \(adv)"
            let triplet = rate == .r1_8t
            if triplet { tripletCombos += 1 }
            let ticks = Int64(64.0 * 4 / closed.sub)
            var diffs = 0
            for t in 0..<ticks {
                let a = euclideousWalkTick(closed, tick: t), b = euclideousWalkTick(sched, tick: t)
                if a != b { diffs += 1; if !triplet { XCTFail("\(ctx): tick \(t) closed \(a) schedule \(b)"); break } }
            }
            if triplet { tripletTickDiffs += diffs }
            for k in 0..<64 {
                let beat = Double(k) * 3.37 + 0.001
                XCTAssertEqual(closed.chains.rhythmOriginBeat(beat), sched.chains.rhythmOriginBeat(beat), accuracy: 1e-9, "\(ctx) rhythm origin @\(beat)")
                XCTAssertEqual(closed.chains.melodyOriginBeat(beat), sched.chains.melodyOriginBeat(beat), accuracy: 1e-9, "\(ctx) melody origin @\(beat)")
                XCTAssertEqual(closed.chains.passIndex(beat: beat), sched.chains.passIndex(beat: beat), "\(ctx) pass index @\(beat)")
                let n1 = closed.chains.nextRhythmRestart(after: beat), n2 = sched.chains.nextRhythmRestart(after: beat)
                XCTAssertEqual(n1 == nil, n2 == nil, "\(ctx) next rhythm restart @\(beat)"); if let x = n1, let y = n2 { XCTAssertEqual(x, y, accuracy: 1e-9, ctx) }
                let m1 = closed.chains.nextMelodyRestart(after: beat), m2 = sched.chains.nextMelodyRestart(after: beat)
                XCTAssertEqual(m1 == nil, m2 == nil, "\(ctx) next melody restart @\(beat)"); if let x = m1, let y = m2 { XCTAssertEqual(x, y, accuracy: 1e-9, ctx) }
                let q = Int64(k)
                XCTAssertEqual(closed.chains.passStart(q), sched.chains.passStart(q), accuracy: 1e-9, "\(ctx) pass start \(q)")
            }
            if ran % 7 == 0 && !triplet {   // the tiles read the same readers
                for kind in [EuclideousRestartKind.rhythm, .melody] {
                    for k in 0..<12 { let beat = Double(k) * 5.11 + 0.37; XCTAssertEqual(restartTileState(kind, cfg: closed, beat: beat, running: true), restartTileState(kind, cfg: sched, beat: beat, running: true), "\(ctx) tile \(kind) @\(beat)") }
                }
            }
        } } } } }
        XCTAssertGreaterThan(ran, 600, "the sample is the one the comment says")
        print("RESTART UNITS test 2: \(ran) cases run, \(tripletCombos) of them 1/8 triplets with \(tripletTickDiffs) ticks that floored differently")
    }
    /// The Router attaches the schedule only to a lane the closed forms cannot express — the other half of the equivalence: a pre-feature lane is bit-identical because it never leaves the closed forms.
    func testAPreFeatureLaneIsNotGivenTheScheduleAndANewUnitLaneIs() {
        var old = line(hits: 3, steps: 8); rhythm(&old, [2, 1]); melody(&old, [2])
        var new = line(hits: 3, steps: 8); rhythm(&new, [1], unit: .riff, source: 0)
        let a = four(old), b = four(new)
        XCTAssertNil(cfg(a, set: setFor(a)).chains.schedule, "BAR / own-PASS chains keep the closed forms")
        XCTAssertNotNil(cfg(b, set: setFor(b)).chains.schedule, "a RIFF unit needs the schedule")
        var hit = line(hits: 3, steps: 8); melody(&hit, [3], unit: .hit)
        XCTAssertNotNil(cfg(four(hit), set: setFor(four(hit))).chains.schedule, "so does a HIT unit")
        var wr = line(hits: 3, steps: 8); rhythm(&wr, [1]); melody(&wr, [], withRhythm: true)
        XCTAssertNotNil(cfg(four(wr), set: setFor(four(wr))).chains.schedule, "and WITH RHYTHM")
        XCTAssertNil(euclideousAttachedSchedule(setFor(b), lane: 0, barBeats: 3.5), "a schedule simulated with another bar length is not read")
        var answerLane = new; answerLane.answerRhythmOn = true; answerLane.answerRhythmCycle = true; answerLane.listenSource = 1
        let eng = four(answerLane)
        XCTAssertNil(euclideousAttachedSchedule(euclideousRestartScheduleSet(lines: eng, barBeats: 4, defaultRateBeats: 0.25, riffColumns: 8), lane: 0, barBeats: 4), "an ANSWER-engaged lane keeps the closed forms")
    }

    // MARK: test 3 / 4 — riff-first

    private func riffFirst(withRhythm: Bool) -> (lines: [EuclidLine], set: EuclideousRestartScheduleSet) {
        var l = line(hits: 3, steps: 8)
        rhythm(&l, [1], unit: .riff, source: 0)
        if withRhythm { melody(&l, [], withRhythm: true) }
        let lines = four(l)
        return (lines, setFor(lines))
    }
    func testRiffFirstTheWholeRiffPlaysThenTheRhythmWrapsWithAClippedLastPass() {
        let (lines, set) = riffFirst(withRhythm: false)
        let c = cfg(lines, set: set), s = set.lane(0)!
        let h = hits(c, beats: 13)
        XCTAssertEqual(h.prefix(9).map { $0.col }, [1, 2, 3, 4, 5, 6, 7, 8, 1], "all eight riff notes play, then it starts over")
        XCTAssertEqual(h[7].beat, 9.5, accuracy: 1e-9, "the 8th riff note plays at beat 9.5")
        close(restarts({ s.nextRhythmRestart(after: $0) }, upTo: 41), [10, 20, 30, 40], "lane 1 rhythm-restarts at 10, 20, 30, …")
        let starts = (0..<10).map { c.chains.passStart(Int64($0)) }
        close(starts, [0, 4, 8, 10, 14, 18, 20, 24, 28, 30], "its passes start at 0, 4, 8, 10, 14, 18, 20, …")
        XCTAssertEqual(footers(c, passes: 0..<7).map { $0 }, [[1, 2, 3], [4, 5, 6], [7, 8], [1, 2, 3], [4, 5, 6], [7, 8], [1, 2, 3]], "footers run 1 2 3 | 4 5 6 | 7 8 | 1 2 3 | …")
        // the pass from 8 reaches steps 1–4 only (the 8th note is struck at 9.5, step 4): the rhythm tile dashes steps 5–8 while it plays
        let st = restartTileState(.rhythm, cfg: c, beat: 8.2, running: true)
        XCTAssertEqual((0..<8).map { st.cell($0) == 2 }, [false, false, false, false, true, true, true, true], "steps 5–8 are the ghost cells during the cut pass")
        XCTAssertEqual(st.isFree, false)
        let full = restartTileState(.rhythm, cfg: c, beat: 4.2, running: true)
        XCTAssertEqual(full.ghostCount, 0, "a whole pass has no dashed step")
        XCTAssertEqual(s.riffCompletions(before: 10.1), 1); XCTAssertEqual(s.riffCompletions(before: 20.1), 2)
        XCTAssertTrue(set.lane(0)!.data.period > 0, "the schedule is periodic (10 beats)"); XCTAssertEqual(s.data.period, 20, accuracy: 1e-9, "the joint state repeats at a bar line: 20 beats = 2 cycles of 10")
    }
    func testRiffFirstWithRhythmOnIsIdenticalAndNothingCountsTwice() {
        let (l1, s1) = riffFirst(withRhythm: false), (l2, s2) = riffFirst(withRhythm: true)
        let a = hits(cfg(l1, set: s1), beats: 42), b = hits(cfg(l2, set: s2), beats: 42)
        XCTAssertEqual(a.map { $0.col }, b.map { $0.col }); close(a.map { $0.beat }, b.map { $0.beat })
        let ra = restarts({ s1.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 41), rb = restarts({ s2.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 41)
        close(ra, rb, "identical restart beats")
        close(restarts({ s2.lane(0)!.nextMelodyRestart(after: $0) }, upTo: 41), [10, 20, 30, 40], "the riff is welded to every rhythm restart")
        XCTAssertEqual(s2.lane(0)!.riffCompletions(before: 10.1), 1, "the natural completion at 10 is not counted again as a restarted one")
        XCTAssertEqual(s2.lane(0)!.riffCompletions(before: 40.1), 4)
    }

    // MARK: test 5 — isorhythm

    func testIsorhythmAMelodyOfThreeHitsRotatesThroughFiveHits() {
        var l = line(hits: 5, steps: 8); melody(&l, [3], unit: .hit)
        let lines = four(l), set = setFor(lines)
        let c = cfg(lines, set: set)
        XCTAssertEqual(footers(c, passes: 0..<4), [[1, 2, 3, 1, 2], [3, 1, 2, 3, 1], [2, 3, 1, 2, 3], [1, 2, 3, 1, 2]])
        let st = restartTileState(.melody, cfg: c, beat: 1.2, running: true)
        XCTAssertEqual((0..<8).map { st.cell($0) == 2 }, [false, false, false, true, true, true, true, true], "the melody tile dashes columns 4–8")
        // 3.14 — a restart returns the ordinal the notes part reads to zero
        for q in 0..<3 { for h in hits(c, beats: 14) where h.ord == 0 { XCTAssertEqual(h.col, 1, "pass \(q)") } }
    }

    // MARK: test 6 / 7 — a melody restart counts as a completion; the same-beat loop ends

    func testAMelodyRestartCountsAsARiffCompletion() {
        var l = line(hits: 5, steps: 8); rhythm(&l, [1], unit: .riff, source: 0); melody(&l, [3], unit: .hit)
        let lines = four(l), set = setFor(lines), c = cfg(lines, set: set)
        close(restarts({ set.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 10.1), [2.5, 5, 7.5, 10], "rhythm restarts fall every 3 hits")
        let h = hits(c, beats: 8)
        XCTAssertEqual(h.prefix(10).map { $0.col }, [1, 2, 3, 1, 2, 3, 1, 2, 3, 1], "the 4th hit plays at the restart, as step 1, riff note 1")
        XCTAssertEqual(h[3].beat, 2.5, accuracy: 1e-9)
        XCTAssertTrue(set.lane(0)!.data.period > 0)
    }
    func testTheSameBeatLoopEndsAndEqualsMelodyAlone() {
        var both = line(hits: 3, steps: 8); rhythm(&both, [1], unit: .riff, source: 0); melody(&both, [1], withRhythm: true)
        var alone = line(hits: 3, steps: 8); melody(&alone, [1])
        let lb = four(both), sb = setFor(lb), la = four(alone), sa = setFor(la)
        let hb = hits(cfg(lb, set: sb), beats: 40), ha = hits(cfg(la, set: sa), beats: 40)
        XCTAssertEqual(hb.map { $0.col }, ha.map { $0.col }, "the result equals melody 1 alone"); close(hb.map { $0.beat }, ha.map { $0.beat })
        close(restarts({ sb.lane(0)!.nextMelodyRestart(after: $0) }, upTo: 20), [4, 8, 12, 16], "both parts restart at every pass start")
        close(restarts({ sb.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 20), [4, 8, 12, 16])
    }

    // MARK: test 8–10 — another lane's pass or riff

    private func lane2Twelve() -> EuclidLine { line(hits: 5, steps: 12, rate: .r1_16) }
    func testRhythmOnAnotherLanesPass() {
        var l = line(hits: 3, steps: 7); rhythm(&l, [1], unit: .pass, source: 1)
        var set = setFor(four(l, lane2Twelve()))
        close(restarts({ set.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 13), [3, 6, 9, 12], "lane 1 rhythm-restarts at 3, 6, 9, …")
        var l2 = l; rhythm(&l2, [2, 1], unit: .pass, source: 1)
        set = setFor(four(l2, lane2Twelve()))
        close(restarts({ set.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 19), [6, 9, 15, 18], "with links [2,1]: at 6, 9, 15, 18, …")
        XCTAssertTrue(set.lane(0)!.data.period > 0)
    }
    func testRhythmOnAnotherLanesRiff() {
        var l = line(hits: 3, steps: 7); rhythm(&l, [1], unit: .riff, source: 1)
        let l2 = line(hits: 5, steps: 12, rate: .r1_16)
        let lines = four(l, l2), set = setFor(lines)
        close(restarts({ set.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 24), [4.5, 9.25, 14.25, 19.0, 23.75], "lane 1 restarts on every lane-2 riff completion")
        close(restarts({ set.lane(1)!.nextRhythmRestart(after: $0) }, upTo: 24), [], "lane 2 itself restarts nothing")
        // a restart inside lane 1's step (sub 0.5): the origin is the FLOORED tick, the step it falls inside keeps the old phase (RHYTHM ferry 4.5)
        let c = cfg(lines, set: set)
        let ph = euclideousLaneChainPhase(buf: c.buf, n: c.n, dir: c.dir, cycleLen: euclidCycleLen(c.dir, n: c.n), sub: c.sub, tick: 19, chains: c.chains, legacySpanBeats: 0)   // beat 9.5
        XCTAssertEqual(ph.originTickO, 18, "9.25 / 0.5 floors to tick 18")
        XCTAssertEqual(ph.localT, 1)
    }
    func testMelodyOnAnotherLanesPass() {
        var l = line(hits: 3, steps: 7); melody(&l, [2], unit: .pass, source: 1)
        let set = setFor(four(l, lane2Twelve()))
        close(restarts({ set.lane(0)!.nextMelodyRestart(after: $0) }, upTo: 19), [6, 12, 18], "lane 1's riff restarts every 2 passes of lane 2")
        close(restarts({ set.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 19), [], "its rhythm is untouched")
    }

    // MARK: test 11 / 12 — WITH RHYTHM alone, a cross-lane cycle

    func testWithRhythmAloneRestartsTheRiffAtTheRhythmRestartsAndNotAtPassStarts() {
        var l = line(hits: 3, steps: 7); rhythm(&l, [1]); melody(&l, [], withRhythm: true)
        let set = setFor(four(l))
        close(restarts({ set.lane(0)!.nextMelodyRestart(after: $0) }, upTo: 17), [4, 8, 12, 16], "the riff restarts at 4, 8, 12, … and not at the pass starts 3.5, 7.5, …")
        XCTAssertEqual(set.lane(0)!.melodyRestarts, true)
    }

    // MARK: RESTARTS EDITOR V2 §1 — a WITH RHYTHM restart re-aligns the melody chain's COUNT sequence (tests 26–29)

    /// 26 (the worked example): E(5,8), rhythm BAR[2], melody HIT[3], WITH RHYTHM on. The rhythm (and so the melody) loops every 2 bars = at the start of passes 2, 4, … and a loop sends the HIT count back to 0 — so pass 2 reads the SAME as pass 0.
    /// Without §1 the HIT chain would keep counting absolutely and pass 2 would read `1 2 1 2 3` (the melody restart from the loop having moved only the riff ordinal, not where the next HIT restart falls).
    func testTest26AWithRhythmLoopReAlignsTheHitCountSoPassTwoRepeatsPassZero() {
        var l = line(hits: 5, steps: 8); rhythm(&l, [2], unit: .bar); melody(&l, [3], unit: .hit, withRhythm: true)
        let lines = four(l), set = setFor(lines), c = cfg(lines, set: set)
        XCTAssertEqual(footers(c, passes: 0..<4), [[1, 2, 3, 1, 2], [3, 1, 2, 3, 1], [1, 2, 3, 1, 2], [3, 1, 2, 3, 1]],
                       "the loop at bar 2 re-aligns the count: pass 2 == pass 0")
        // the loops (= the rhythm restarts, bars 2/4/6 = beats 8/16/24) are themselves melody restarts (beat-line checks, rotation-independent)
        XCTAssertEqual(set.lane(0)!.melodyRecord(atOrBefore: 8.0).beat, 8.0, accuracy: 1e-9, "the loop at bar 2 is a melody restart")
        XCTAssertEqual(set.lane(0)!.melodyRecord(atOrBefore: 16.0).beat, 16.0, accuracy: 1e-9, "and the loop at bar 4")
        XCTAssertTrue(set.lane(0)!.isLoop(at: 8.0), "bar 2 is a loop")
    }

    /// 27: the count reset is the chain's whole position, not just the HIT case. rhythm BAR[3] (loops at bars 3/6/9), melody PASS[2], WITH RHYTHM on, a 1-bar pass. The PASS count restarts the melody every 2 passes, but each loop sends it back to 0,
    /// so the next PASS restart is 2 passes AFTER the loop — restarts land at 8 (count 2), 12 (loop), 20 (2 after the loop), 24 (loop), 32, 36. Without §1 the 3rd would be at 16 (absolute count 4), not 20.
    func testTest27AWithRhythmLoopReAlignsAPassCountToo() {
        var l = line(hits: 3, steps: 8); rhythm(&l, [3], unit: .bar); melody(&l, [2], unit: .pass, withRhythm: true)
        let set = setFor(four(l))
        close(restarts({ set.lane(0)!.nextMelodyRestart(after: $0) }, upTo: 40), [8, 12, 20, 24, 32, 36],
              "the PASS count restarts 2 passes after each loop, not on the absolute even passes")
    }

    /// 28: §1 is gated on WITH RHYTHM — a plain rhythm restart does NOT reset the melody count. The same lane as 26 with WITH RHYTHM OFF reads the pure isorhythm (a 3-over-5 rotation), identical to test 5, because the rhythm BAR[2] restart replays the
    /// pattern at a natural pass boundary and leaves the melody chain alone.
    func testTest28ARhythmRestartAloneLeavesTheMelodyCountUntouched() {
        var l = line(hits: 5, steps: 8); rhythm(&l, [2], unit: .bar); melody(&l, [3], unit: .hit, withRhythm: false)
        let lines = four(l), set = setFor(lines), c = cfg(lines, set: set)
        XCTAssertEqual(footers(c, passes: 0..<4), [[1, 2, 3, 1, 2], [3, 1, 2, 3, 1], [2, 3, 1, 2, 3], [1, 2, 3, 1, 2]],
                       "no WITH RHYTHM: the melody keeps counting absolutely (the isorhythm of test 5)")
        XCTAssertNotEqual(set.lane(0)!.melodyRecord(atOrBefore: 8.0).beat, 8.0, "the rhythm restart at bar 2 is NOT a melody restart when WITH RHYTHM is off")
    }

    /// 29: a WITH RHYTHM + HIT lane and a WITH RHYTHM + PASS lane are both periodic, and the period-detected reader equals a straight simulation far downstream — the §1 count origins grow without bound, but their phase (mod total) repeats, so detection
    /// and the periodic wrap still agree (§1.4).
    func testTest29WithRhythmLanesArePeriodicAndTheWrapMatchesAStraightRun() {
        var h = line(hits: 5, steps: 8); rhythm(&h, [2], unit: .bar); melody(&h, [3], unit: .hit, withRhythm: true)
        XCTAssertTrue(setFor(four(h)).lane(0)!.data.period > 0, "the HIT + WITH RHYTHM lane is periodic")
        periodicVersusStraight(four(h), at: [1000.3, 1007.4, 1013.9])
        var p = line(hits: 3, steps: 8); rhythm(&p, [3], unit: .bar); melody(&p, [2], unit: .pass, withRhythm: true)
        XCTAssertTrue(setFor(four(p)).lane(0)!.data.period > 0, "the PASS + WITH RHYTHM lane is periodic")
        periodicVersusStraight(four(p), at: [1000.3, 1021.5])
    }

    func testACrossLaneCycleResolvesDeterministically() {
        var a = line(hits: 3, steps: 7); rhythm(&a, [1], unit: .pass, source: 1)
        var b = line(hits: 5, steps: 12, rate: .r1_16); rhythm(&b, [1], unit: .pass, source: 0)
        let s1 = setFor(four(a, b)), s2 = setFor(four(a, b))
        close(restarts({ s1.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 19), [3, 6, 9, 12, 15, 18], "lane 1 restarts at 3, 6, 9, …")
        close(restarts({ s1.lane(1)!.nextRhythmRestart(after: $0) }, upTo: 19), [3, 6, 9, 12, 15, 18], "and so does lane 2")
        close(restarts({ s1.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 200), restarts({ s2.lane(0)!.nextRhythmRestart(after: $0) }, upTo: 200), "deterministic")
    }

    // MARK: test 13 — periodicity

    private func periodicVersusStraight(_ lines: [EuclidLine], at beats: [Double], file: StaticString = #filePath, line ln: UInt = #line) {
        let p = setFor(lines), straight = setFor(lines, detect: false, maxBars: 420)
        for lane in 0..<4 {
            let a = p.lane(lane)!, b = straight.lane(lane)!
            for beat in beats {
                XCTAssertEqual(a.rhythmRecord(atOrBefore: beat), b.rhythmRecord(atOrBefore: beat), "lane \(lane) rhythm record @\(beat)", file: file, line: ln)
                XCTAssertEqual(a.melodyRecord(atOrBefore: beat), b.melodyRecord(atOrBefore: beat), "lane \(lane) melody record @\(beat)", file: file, line: ln)
                XCTAssertEqual(a.nextRhythmRestart(after: beat), b.nextRhythmRestart(after: beat), "lane \(lane) next rhythm @\(beat)", file: file, line: ln)
                XCTAssertEqual(a.nextMelodyRestart(after: beat), b.nextMelodyRestart(after: beat), "lane \(lane) next melody @\(beat)", file: file, line: ln)
                XCTAssertEqual(a.passIndex(beat: beat), b.passIndex(beat: beat), "lane \(lane) pass index @\(beat)", file: file, line: ln)
                XCTAssertEqual(a.riffCompletions(before: beat), b.riffCompletions(before: beat), "lane \(lane) riff completions @\(beat)", file: file, line: ln)
                let tick = Int64((beat / a.data.sub).rounded(.down))
                XCTAssertEqual(a.hitsBefore(tick: tick), b.hitsBefore(tick: tick), "lane \(lane) hits @\(beat)", file: file, line: ln)
                let q = a.passIndex(beat: beat)
                XCTAssertEqual(a.passStart(q), b.passStart(q), accuracy: 1e-9, "lane \(lane) pass start @\(beat)", file: file, line: ln)
            }
        }
    }
    func testAPeriodicScheduleFromATransportStartAtBeat1000EqualsTheStraightSimulation() {
        var rf = line(hits: 3, steps: 8); rhythm(&rf, [1], unit: .riff, source: 0)
        periodicVersusStraight(four(rf), at: [1000.3, 1003.9, 1011.0])
        var iso = line(hits: 5, steps: 8); rhythm(&iso, [1], unit: .riff, source: 0); melody(&iso, [3], unit: .hit)
        periodicVersusStraight(four(iso), at: [1000.3, 1007.4])
        var a = line(hits: 3, steps: 7); rhythm(&a, [2, 1], unit: .pass, source: 1)
        periodicVersusStraight(four(a, lane2Twelve()), at: [1000.3, 1009.5])
        var r9 = line(hits: 3, steps: 7); rhythm(&r9, [1], unit: .riff, source: 1)
        periodicVersusStraight(four(r9, line(hits: 5, steps: 12, rate: .r1_16)), at: [1000.3, 1013.8])
        var dotted = line(hits: 4, steps: 7, rate: .r1_8d); rhythm(&dotted, [1]); melody(&dotted, [2])
        periodicVersusStraight(four(dotted), at: [1000.3, 1005.7], )
    }
    /// A window shorter than the period: the riff-first lane repeats every 20 beats = 5 bars, so a 3-bar window finds none. The windowed path then carries the tables as they stand, a lookup beyond the window says so (`covers`), and the main thread
    /// extends the same simulation ahead of the playhead — in blocks — to exactly what one straight run gives. (Constructing a lane set whose joint state does NOT repeat within 1024 bars proved impossible to find: the lanes re-anchor one another,
    /// so their periods stay short. The longest period found is reported by `testReportTheLongestPeriodsMet`.)
    func testAWindowShorterThanThePeriodIsExtendedAheadAndMatchesAStraightRun() {
        var l = line(hits: 3, steps: 8); rhythm(&l, [1], unit: .riff, source: 0)
        let inputs = euclideousScheduleInputs(lines: four(l), barBeats: 4, defaultRateBeats: 0.25, riffColumns: 8)
        let first = euclideousBuildRestartScheduleSet(inputs, maxBars: 3)
        XCTAssertTrue(first.windowed, "no period within 3 bars"); XCTAssertEqual(first.coveredUntil, 12, accuracy: 1e-9)
        XCTAssertFalse(first.lane(0)!.covers(30)); XCTAssertTrue(first.lane(0)!.covers(10))
        XCTAssertNotNil(first.lane(0)!.data.rBeat.count > 1 ? 1 : nil, "the window holds the restart at 10")
        // the Router reads the closed forms beyond the window (`chains.sched` answers nil there) — and the extension finds the period
        var c = cfg(four(l), set: first)
        XCTAssertNotNil(c.chains.schedule); XCTAssertEqual(c.chains.rhythmOriginBeat(10.5), 10); XCTAssertEqual(c.chains.rhythmOriginBeat(30.5), 0, "beyond the window: the closed form (FREE here) answers until the main thread has extended it")
        guard let second = first.extended(untilBars: 40) else { return XCTFail("extends") }
        XCTAssertFalse(second.windowed, "the extension finds the period at bar 5"); XCTAssertEqual(second.lane(0)!.data.period, 20, accuracy: 1e-9)
        c.chains.schedule = second.lane(0)
        XCTAssertEqual(c.chains.rhythmOriginBeat(30.5), 30); XCTAssertEqual(c.chains.rhythmOriginBeat(1234.5), 1230)
        XCTAssertNil(second.extended(untilBars: 100), "a periodic set is complete")
        XCTAssertNil(euclideousBuildRestartScheduleSet(inputs).extended(untilBars: 100), "…and so is one whose first window already found its period")
        // a straight simulation extended in blocks equals one run to the same end
        let blocks = euclideousBuildRestartScheduleSet(inputs, maxBars: 8, detectPeriod: false)
        let blocks2 = blocks.extended(untilBars: 60)!, once = euclideousBuildRestartScheduleSet(inputs, maxBars: 60, detectPeriod: false)
        for lane in 0..<4 { for beat in [100.3, 150.1, 230.7] {
            XCTAssertEqual(blocks2.lane(lane)!.rhythmRecord(atOrBefore: beat), once.lane(lane)!.rhythmRecord(atOrBefore: beat), "lane \(lane) @\(beat)")
            XCTAssertEqual(blocks2.lane(lane)!.riffCompletions(before: beat), once.lane(lane)!.riffCompletions(before: beat))
            XCTAssertEqual(blocks2.lane(lane)!.passIndex(beat: beat), once.lane(lane)!.passIndex(beat: beat))
        } }
    }
    /// Not an assertion: how long the periods get, and how long a simulation takes, over a seeded draw of four-lane documents that use every unit. The numbers go in the ferry's report.
    func testReportTheLongestPeriodsMet() {
        var rng = SplitMix(seed: 0x5EED)
        var longest = 0.0, worstMs = 0.0, windowedCount = 0, total = 0, biggestTable = 0, windowedMs = 0.0
        var worstCase = ""
        for n in 0..<60 {
            var lines: [EuclidLine] = []
            for lane in 0..<4 {
                var l = line(hits: Int(rng.next() % 8) + 1, steps: Int(rng.next() % 15) + 2, rate: [ArpRate.r1_16, .r1_8, .r1_8d, .r1_8t][Int(rng.next() % 4)], dir: [EuclidDir.fwd, .bkw, .pingpong][Int(rng.next() % 3)], advanceStep: rng.next() % 4 == 0)
                l.riffLength = Int(rng.next() % 8) + 1
                let ru: EuclideousRhythmRestartUnit = [.bar, .pass, .riff][Int(rng.next() % 3)]
                let links: [[UInt8]] = [[], [1], [2], [1, 2], [3, 1, 1], [8], [2, 6]]
                var src = Int(rng.next() % 4); if ru == .pass && src == lane { src = (lane + 1) % 4 }
                rhythm(&l, links[Int(rng.next() % 7)], unit: ru, source: src)
                let mu: EuclideousMelodyRestartUnit = [.pass, .bar, .hit][Int(rng.next() % 3)]
                melody(&l, mu == .hit ? [[], [3], [2, 1], [5, 7]][Int(rng.next() % 4)] : links[Int(rng.next() % 7)], unit: mu, source: Int(rng.next() % 4), withRhythm: rng.next() % 3 == 0)
                lines.append(l)
            }
            let inputs = euclideousScheduleInputs(lines: lines, barBeats: 4, defaultRateBeats: 0.25, riffColumns: 8)
            let t0 = Date()
            let set = euclideousBuildRestartScheduleSet(inputs)
            let ms = Date().timeIntervalSince(t0) * 1000
            total += 1
            if set.windowed { windowedCount += 1; windowedMs = max(windowedMs, ms) }
            for lane in 0..<4 { if let d = set.lane(lane)?.data {
                biggestTable = max(biggestTable, d.rBeat.count + d.mBeat.count + d.fBeat.count)
                if d.period + d.prefixEnd > longest { longest = d.period + d.prefixEnd; worstCase = "draw \(n) lane \(lane)" }
            } }
            if ms > worstMs { worstMs = ms }
        }
        print("RESTART UNITS schedule probe: \(total) draws, \(windowedCount) windowed, longest prefix+period \(longest / 4) bars (\(worstCase)), slowest build \(Int(worstMs)) ms, slowest windowed (no period in 1024 bars) \(Int(windowedMs)) ms (Debug), biggest lane table \(biggestTable) records")
    }

    // MARK: test 14 — a melody restart resets what the notes part reads

    func testEveryMelodyRestartReturnsTheOrdinalTheNotesAndRiffReadToZero() {
        var cases: [([EuclidLine], String)] = []
        var a = line(hits: 5, steps: 8); melody(&a, [3], unit: .hit); cases.append((four(a), "melody HIT 3"))
        var b = line(hits: 5, steps: 8); rhythm(&b, [1], unit: .riff, source: 0); melody(&b, [3], unit: .hit); cases.append((four(b), "rhythm RIFF + melody HIT"))
        var c = line(hits: 3, steps: 7); melody(&c, [1], unit: .pass); cases.append((four(c), "melody PASS 1"))
        var d = line(hits: 3, steps: 7); melody(&d, [2], unit: .pass, source: 1); cases.append((four(d, lane2Twelve()), "melody PASS of lane 2"))
        var e = line(hits: 3, steps: 7); rhythm(&e, [1]); melody(&e, [], withRhythm: true); cases.append((four(e), "WITH RHYTHM"))
        for (lines, name) in cases {
            let set = setFor(lines), c0 = cfg(lines, set: set), s = set.lane(0)!
            let rs = restarts({ s.nextMelodyRestart(after: $0) }, upTo: 40)
            XCTAssertFalse(rs.isEmpty, name)
            let all = hits(c0, beats: 42)
            for b in rs {
                guard let first = all.first(where: { $0.beat >= b - 1e-9 }) else { continue }
                // the first hit at/after the restart reads ordinal 0 — through `LaneChainTick` ADV HIT, which is what `euclideousNotesHitOrdinal` returns
                let t = Int64((first.beat / c0.sub).rounded())
                let info = euclideousLaneChainTick(buf: c0.buf, n: c0.n, dir: c0.dir, cycleLen: euclidCycleLen(c0.dir, n: c0.n), sub: c0.sub, tick: t, chains: c0.chains, legacySpanBeats: 0, advanceStep: false)
                XCTAssertEqual(info.advOrd, 0, "\(name): the first hit after the melody restart at \(b) is hit 0 of the notes' ordinal")
                XCTAssertEqual(first.ord, 0, "\(name): and of the riff's")
            }
        }
    }

    // MARK: the engaged mask, the set's lanes

    func testALaneInAnAnswerCycleIsEngagedAndTheOthersAreNot() {
        var l = line(hits: 3, steps: 8); l.answerRhythmOn = true; l.answerRhythmCycle = true; l.listenSource = 1
        XCTAssertNotEqual(euclideousScheduleEngagedLanes(lines: four(l)) & 1, 0)
        XCTAssertEqual(euclideousScheduleEngagedLanes(lines: four(line(hits: 3, steps: 8))), 0)
        var t = line(hits: 3, steps: 8); t.answerTradeOn = true; t.answerTradeWith = 2
        XCTAssertEqual(euclideousScheduleEngagedLanes(lines: four(line(hits: 1, steps: 8), nil, t, nil)) & 0b0100, 0b0100)
    }
    func testTheSnapshotBuilderCarriesTheSchedule() {
        var m = Machine(machineID: "gold", type: .euclid)
        var l = line(hits: 3, steps: 8); rhythm(&l, [1], unit: .riff, source: 0)
        m.paramsA.euclidLines = four(l)
        var sc = SceneState.empty(); sc.stepRate = .r1_8
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a, .b, .c, .d])
        let box = SnapshotBuilder.build(from: PluginState(machines: machineIDs.map { $0 == "gold" ? m : Machine(machineID: $0, type: .arp) }, scenes: [sc]))
        let set = box.cells[Snap.euclideousRow].procs.first?.restartSchedule
        XCTAssertNotNil(set); XCTAssertEqual(set?.lane(0)?.rhythmRestarts, true); XCTAssertEqual(set?.barBeats, 4)
        let hosted = SnapshotBuilder.build(from: PluginState(machines: machineIDs.map { $0 == "gold" ? m : Machine(machineID: $0, type: .arp) }, scenes: [sc]), restartBarBeats: 3.5)
        XCTAssertEqual(hosted.cells[Snap.euclideousRow].procs.first?.restartSchedule?.barBeats, 3.5, "the host's bar length is what the schedule is simulated with")
    }

    // MARK: adversarial review (2026-11-04) — the schedule reviewer's findings

    /// A restart that lands exactly on a tick start must make THAT tick the origin: the restart beat is a float product (`(t + 1) × sub`), and flooring it with no ε can give `t`, which swallows the new pass's downbeat.
    func testARestartOnATickStartOriginatesAtThatTickEvenWhenTheBeatIsAHairShort() {
        for rate in [ArpRate.r1_8t, .r1_16t, .r1_8, .r1_16d] {
            for (hits, steps) in [(3, 7), (5, 7), (4, 5)] {
                var a = line(hits: hits, steps: steps, rate: rate); rhythm(&a, [1], unit: .riff, source: 0)   // own riff-first
                var b = line(hits: 2, steps: steps, rate: rate); rhythm(&b, [1], unit: .pass, source: 1 - 0 == 1 ? 0 : 0)
                _ = b
                let set = setFor(four(a))
                let d = set.lane(0)!.data
                var bad = 0
                for i in 0..<d.rBeat.count {
                    let exact = d.rBeat[i] / d.sub
                    if abs(exact - exact.rounded()) < 1e-6, d.rTick[i] != Int64(exact.rounded()) { bad += 1 }
                }
                XCTAssertEqual(bad, 0, "\(rate) \(hits)/\(steps): \(bad) of \(d.rBeat.count) on-grid restarts floor a tick early")
            }
        }
        // cross-lane: lane 0 restarts on lane 1's PASS starts (lane 1 at a triplet step, lane 0 at a straight one)
        var src = line(hits: 3, steps: 7, rate: .r1_8t)
        var dst = line(hits: 3, steps: 8, rate: .r1_16); rhythm(&dst, [1], unit: .pass, source: 1)
        _ = src; src = line(hits: 3, steps: 7, rate: .r1_8t)
        let set = setFor([dst, src, line(hits: 1, steps: 8), line(hits: 1, steps: 8)])
        let d = set.lane(0)!.data
        var bad = 0
        for i in 0..<d.rBeat.count { let exact = d.rBeat[i] / d.sub; if abs(exact - exact.rounded()) < 1e-6, d.rTick[i] != Int64(exact.rounded()) { bad += 1 } }
        XCTAssertEqual(bad, 0, "cross-lane PASS restarts: \(bad) of \(d.rBeat.count) floor a tick early")
    }
    /// The phase the engine reads must be the table's own origin tick at every beat, in the periodic region too (the shifted beat re-floors a hair differently from the exact shifted integer).
    func testThePhaseReadsTheTablesOriginTickInThePeriodicRegion() {
        for rate in [ArpRate.r1_8t, .r1_16t] {
            var a = line(hits: 3, steps: 7, rate: rate); rhythm(&a, [2, 1], unit: .riff, source: 0); melody(&a, [3], unit: .hit)
            let set = setFor(four(a))
            let s = set.lane(0)!, sub = s.data.sub
            XCTAssertTrue(s.data.period > 0, "periodic")
            let c = cfg(four(a), set: set)
            var bad = 0, checked = 0
            var tick: Int64 = 0
            while Double(tick) * sub < 4000 {
                let r = s.rhythmRecord(atOrBefore: Double(tick) * sub)   // the engine reads the schedule at the tick's own beat
                let ph = euclideousLaneChainPhase(buf: c.buf, n: c.n, dir: c.dir, cycleLen: euclidCycleLen(c.dir, n: c.n), sub: c.sub, tick: tick, chains: c.chains, legacySpanBeats: c.spanBeats)
                if ph.originTickO != r.tick { bad += 1 }
                checked += 1; tick += 1
            }
            XCTAssertEqual(bad, 0, "\(rate): the phase's origin tick differs from the table's at \(bad) of \(checked) beats")
        }
    }
    /// A lane that counts an engaged (ANSWER cycle / trade) lane's passes would read that lane's static document pattern — it keeps the closed forms too; a lock-perturbed lane detaches its whole component, and only that.
    func testAnEngagedOrPerturbedLaneDetachesItsWholeComponentAndNothingMore() {
        var a = line(hits: 3, steps: 7); rhythm(&a, [1], unit: .pass, source: 1)
        let b = line(hits: 3, steps: 8)
        var d = line(hits: 3, steps: 7); rhythm(&d, [1], unit: .riff, source: 3)
        let lines = [a, b, line(hits: 2, steps: 5), d]
        let inputs = euclideousScheduleInputs(lines: lines, barBeats: 4, defaultRateBeats: 0.25, riffColumns: 8)
        let set = euclideousBuildRestartScheduleSet(inputs, engagedMask: 0b0010)   // lane 2 (index 1) engaged in a cycle
        XCTAssertNil(euclideousAttachedSchedule(set, lane: 0, barBeats: 4), "lane 1 counts the engaged lane's passes")
        XCTAssertNotNil(euclideousAttachedSchedule(set, lane: 3, barBeats: 4), "lane 4's component holds no engaged lane")
        let free = euclideousBuildRestartScheduleSet(inputs, engagedMask: 0)
        XCTAssertNotNil(euclideousAttachedSchedule(free, lane: 0, barBeats: 4))
        XCTAssertNil(euclideousAttachedSchedule(free, lane: 0, barBeats: 4, perturbed: 0b0010), "a lock-substituted lane 2 is in lane 1's component")
        XCTAssertNil(euclideousAttachedSchedule(free, lane: 1, barBeats: 4, perturbed: 0b0001), "…and the other way round")
        XCTAssertNotNil(euclideousAttachedSchedule(free, lane: 3, barBeats: 4, perturbed: 0b0011), "lane 4 is in another component")
        XCTAssertEqual(free.componentMask(lane: 0), 0b0011); XCTAssertEqual(free.componentMask(lane: 2), 0b0100); XCTAssertEqual(free.componentMask(lane: 3), 0b1000)
    }
    /// The page's holder must pick up a set the memo extended (a non-periodic schedule simulated further ahead), or its tiles fall back to the closed forms past the first window while the engine keeps reading the schedule.
    func testTheHolderPicksUpAnExtendedSet() {
        var a = line(hits: 3, steps: 7, rate: .r1_8t); rhythm(&a, [1], unit: .riff, source: 0); a.riffLength = 5
        var b = line(hits: 5, steps: 11, rate: .r1_16d); rhythm(&b, [1], unit: .pass, source: 0)
        let lines = [a, b, line(hits: 1, steps: 8), line(hits: 1, steps: 8)]
        let holder = EuclideousScheduleHolder()
        let first = holder.set(lines: lines, barBeats: 4, defaultRateBeats: 0.25, riffColumns: 8)
        XCTAssertTrue(first === holder.set(lines: lines, barBeats: 4, defaultRateBeats: 0.25, riffColumns: 8), "unchanged inputs: the cached set")
        guard first.windowed else { return }   // this draw found a period; nothing to extend (the extension itself is covered above)
        XCTAssertTrue(EuclideousRestartScheduleMemo.shared.extend(first, untilBars: 3000))
        let second = holder.set(lines: lines, barBeats: 4, defaultRateBeats: 0.25, riffColumns: 8)
        XCTAssertFalse(first === second, "the holder fetched the extended set"); XCTAssertGreaterThan(second.coveredUntil, first.coveredUntil)
    }
    /// A NaN or infinite beat (a host glitch) must not trap in a reader.
    func testTheReadersAnswerANonFiniteBeatWithoutTrapping() {
        var a = line(hits: 3, steps: 7); rhythm(&a, [1], unit: .riff, source: 0); melody(&a, [3], unit: .hit)
        let s = setFor(four(a)).lane(0)!
        for b in [Double.nan, .infinity, -.infinity] {
            _ = s.rhythmRecord(atOrBefore: b); _ = s.melodyRecord(atOrBefore: b); _ = s.nextRhythmRestart(after: b); _ = s.nextMelodyRestart(after: b)
            XCTAssertEqual(s.passIndex(beat: b), 0); XCTAssertEqual(s.riffCompletions(before: b), 0)
        }
        XCTAssertEqual(euclideousScheduleTick(.nan, sub: 0.5), 0)
    }

    // MARK: RESTART UNITS FIX 1 (2026-11-04) — WITH RHYTHM follows the lane's loop; tests 20–23 (24 = test 11 above, 25 = tests 1–2 and the goldens)

    /// 20. E(3,8), rhythm inactive, melody inactive, WITH RHYTHM on: the riff restarts at every pass (4, 8, 12, …), the footers run 1 2 3 each pass, the melody tile dashes columns 4–8.
    func testWithRhythmWithTheRhythmOffRestartsTheRiffEveryPass() {
        var l = line(hits: 3, steps: 8); melody(&l, [], withRhythm: true)
        let lines = four(l), set = setFor(lines), c = cfg(lines, set: set), s = set.lane(0)!
        XCTAssertNotNil(c.chains.schedule, "the schedule is attached: the closed forms cannot express WITH RHYTHM, with the rhythm chain on or off")
        XCTAssertTrue(s.melodyRestarts); XCTAssertFalse(s.rhythmRestarts); XCTAssertFalse(s.data.closedFormExpressible)
        close(restarts({ s.nextMelodyRestart(after: $0) }, upTo: 17), [4, 8, 12, 16], "the melody restarts at every pass start")
        XCTAssertNil(s.nextRhythmRestart(after: 0), "no rhythm restart: the rhythm chain is inactive")
        XCTAssertEqual(footers(c, passes: 0..<6), Array(repeating: [1, 2, 3], count: 6), "footers: 1 2 3 every pass")
        XCTAssertEqual(hits(c, beats: 16).map { $0.col }, [1, 2, 3, 1, 2, 3, 1, 2, 3, 1, 2, 3], "riff notes 1 2 3 every pass")
        let st = restartTileState(.melody, cfg: c, beat: 2.0, running: true)
        XCTAssertEqual((0..<8).map { st.cell($0) == 2 }, [false, false, false, true, true, true, true, true], "the tile dashes columns 4–8")
        XCTAssertEqual(st.progress ?? -1, 0.5, accuracy: 1e-9, "the outer fill runs from the last loop (0) to the next (4): half way at beat 2")
        XCTAssertFalse(st.isFree)
        XCTAssertTrue(set.lane(0)!.data.period > 0, "periodic (one pass)")
    }
    /// 21. 7 steps of 1/8, rhythm inactive, WITH RHYTHM: 3.5, 7, 10.5, …; the same lane with melody BAR [1] and WITH RHYTHM off: 4, 8, 12, ….
    func testAnOddLaneRestartsItsRiffInStepWithItsLoopNotTheBar() {
        var l = line(hits: 3, steps: 7); melody(&l, [], withRhythm: true)
        let s = setFor(four(l)).lane(0)!
        close(restarts({ s.nextMelodyRestart(after: $0) }, upTo: 15), [3.5, 7, 10.5, 14], "every 3.5 beats, in step with the loop")
        var b = line(hits: 3, steps: 7); melody(&b, [1], unit: .bar)
        let sb = setFor(four(b)).lane(0)!
        close(restarts({ sb.nextMelodyRestart(after: $0) }, upTo: 17), [4, 8, 12, 16], "melody BAR [1] with WITH RHYTHM off restarts on the bar")
    }
    /// 22. A rhythm chain with links but switched off behaves exactly as 21.
    func testARhythmChainWithLinksButSwitchedOffBehavesAsTheRhythmOff() {
        var l = line(hits: 3, steps: 7); rhythm(&l, [1]); l.restartRhythmOn = false; melody(&l, [], withRhythm: true)
        XCTAssertFalse(euclideousRestartSettings(line: l, lane: 0).rhythmActive)
        var plain = line(hits: 3, steps: 7); melody(&plain, [], withRhythm: true)
        let a = setFor(four(l)).lane(0)!, b = setFor(four(plain)).lane(0)!
        close(restarts({ a.nextMelodyRestart(after: $0) }, upTo: 15), [3.5, 7, 10.5, 14])
        close(restarts({ a.nextMelodyRestart(after: $0) }, upTo: 60), restarts({ b.nextMelodyRestart(after: $0) }, upTo: 60), "the stored links change nothing while the switch is off")
        XCTAssertNil(a.nextRhythmRestart(after: 0)); XCTAssertFalse(a.rhythmRestarts)
        let c1 = cfg(four(l), set: setFor(four(l))), c2 = cfg(four(plain), set: setFor(four(plain)))
        XCTAssertEqual(hits(c1, beats: 30).map { $0.col }, hits(c2, beats: 30).map { $0.col })
    }
    /// 23. Rhythm inactive, melody PASS [2] of itself, WITH RHYTHM on: the melody restarts at every pass, each beat once (the chain's own restart at every second pass falls on a beat WITH RHYTHM already took).
    func testTheMelodyChainAndWithRhythmTogetherRestartOncePerBeat() {
        var l = line(hits: 3, steps: 8); melody(&l, [2], unit: .pass, withRhythm: true)
        let s = setFor(four(l)).lane(0)!
        let rs = restarts({ s.nextMelodyRestart(after: $0) }, upTo: 41)
        close(rs, [4, 8, 12, 16, 20, 24, 28, 32, 36, 40], "every pass")
        XCTAssertEqual(Set(rs).count, rs.count, "no beat twice")
        XCTAssertEqual(s.data.mBeat.count, Set(s.data.mBeat).count, "the table holds each beat once")
        var chainOnly = line(hits: 3, steps: 8); melody(&chainOnly, [2], unit: .pass)
        close(restarts({ setFor(four(chainOnly)).lane(0)!.nextMelodyRestart(after: $0) }, upTo: 41), [8, 16, 24, 32, 40], "without WITH RHYTHM: the chain's every second pass")
    }
    /// 2.2: a melody restart from this rule is a riff completion exactly where RESTART UNITS 2.7(b) says — unless the riff ordinal is already a whole number of cycles (then the natural completion, struck at the start of the next step after the last hit, is the one that counts).
    func testALoopRestartCountsAsARiffCompletionLikeAnyOther() {
        var l = line(hits: 3, steps: 8); melody(&l, [], withRhythm: true)
        let s = setFor(four(l)).lane(0)!
        // 3 hits a pass over an 8-note riff: every restart cuts the riff short — each is a (restarted) completion
        XCTAssertEqual(s.riffCompletions(before: 4.1), 1); XCTAssertEqual(s.riffCompletions(before: 12.1), 3)
        // a 4-note riff on 4 hits a pass: the riff completes NATURALLY at 3.5 (the step after the 4th hit); the restart at 4 finds the ordinal at a whole cycle and counts nothing more
        var e = line(hits: 4, steps: 8); e.riffLength = 4; melody(&e, [], withRhythm: true)
        let se = setFor(four(e)).lane(0)!
        XCTAssertEqual(se.riffCompletions(before: 4.1), 1, "the natural completion at 3.5 only")
        XCTAssertEqual(se.riffCompletions(before: 8.1), 2, "…and at 7.5; the restarts at 4 and 8 add none")
    }
    /// The ONE loop rule: loops are rhythm restarts while the chain is active, natural pass starts otherwise — `isLoop`, `loopCount` and `loopBeat` agree with a walk, in the periodic region too.
    func testTheLoopFunctionAgreesWithAWalkForEveryKindOfLane() {
        XCTAssertTrue(euclideousIsLoop(rhythmActive: true, rhythmRestartAtB: true, passStartAtB: false))
        XCTAssertFalse(euclideousIsLoop(rhythmActive: true, rhythmRestartAtB: false, passStartAtB: true), "1.3: with the chain active a natural pass start is no loop")
        XCTAssertTrue(euclideousIsLoop(rhythmActive: false, rhythmRestartAtB: false, passStartAtB: true))
        XCTAssertFalse(euclideousIsLoop(rhythmActive: false, rhythmRestartAtB: true, passStartAtB: false))
        var off = line(hits: 3, steps: 7)                                              // rhythm FREE: loops are the 3.5-beat passes
        var bar = line(hits: 3, steps: 7); rhythm(&bar, [1])                           // rhythm BAR [1]: loops are the bar lines
        var riff = line(hits: 3, steps: 8); rhythm(&riff, [1], unit: .riff, source: 0)  // riff-first: loops at 10, 20, …
        var dotted = line(hits: 4, steps: 7, rate: .r1_8d); rhythm(&dotted, [2, 1])     // dotted, two links
        off.restartMelodyWithRhythm = true
        for (name, l) in [("rhythm off", off), ("BAR [1]", bar), ("riff-first", riff), ("dotted [2,1]", dotted)] {
            let set = setFor(four(l)), s = set.lane(0)!
            var walk: [Double] = [], b = 0.0
            while let n = (s.rhythmRestarts ? s.nextRhythmRestart(after: b) : (s.passStart(s.passIndex(beat: b) + 1) as Double?)), n < 400 { walk.append(n); b = n }
            XCTAssertGreaterThan(walk.count, 5, name)
            for (i, w) in walk.enumerated() {
                XCTAssertEqual(s.loopBeat(Int64(i + 1)), w, accuracy: 1e-9, "\(name): loop \(i + 1) is at \(w)")
                XCTAssertTrue(s.isLoop(at: w), "\(name): \(w) is a loop")
                XCTAssertEqual(s.loopCount(atOrBefore: w), Int64(i + 1), "\(name): a loop AT the beat counts")
                XCTAssertEqual(s.loopCount(atOrBefore: w - 0.01), Int64(i), "\(name): and not before it")
                XCTAssertFalse(s.isLoop(at: w + 0.25), "\(name): a quarter beat later is no loop")
            }
            XCTAssertFalse(s.isLoop(at: 0), "\(name): beat 0 is the start, not a loop")
            XCTAssertEqual(s.loopCount(atOrBefore: 0), 0, name)
        }
        // the periodic region (beat 1000): the same answers as a straight simulation
        let rf = setFor(four(riff)).lane(0)!, st = setFor(four(riff), detect: false, maxBars: 420).lane(0)!
        for beat in [1000.3, 1009.9, 1010.0] { XCTAssertEqual(rf.loopCount(atOrBefore: beat), st.loopCount(atOrBefore: beat), "@\(beat)"); XCTAssertEqual(rf.isLoop(at: beat), st.isLoop(at: beat)) }
        XCTAssertEqual(rf.loopBeat(100), st.loopBeat(100), accuracy: 1e-9)
    }
    /// A WITH RHYTHM lane whose rhythm is off, read from the periodic table at beat 1000, equals the straight simulation (2.3: no new periodic state).
    func testAWithRhythmLaneWithTheRhythmOffIsPeriodicLikeAStraightSimulation() {
        var l = line(hits: 3, steps: 7); melody(&l, [], withRhythm: true)
        periodicVersusStraight(four(l), at: [1000.3, 1003.4, 1007.0, 1010.6])
        var m = line(hits: 5, steps: 8, rate: .r1_8d); melody(&m, [3], unit: .hit, withRhythm: true)
        periodicVersusStraight(four(m), at: [1000.3, 1002.9])
    }

    // MARK: Restart timing — the rule (a restart on a tick is applied BEFORE that tick plays, so the tick plays STEP 1; never the old step a tick late, never step 2 from advancing after the reset)

    private func chainPhase(_ c: EuclideousWalkLaneConfig, tick: Int64) -> EuclideousLaneChainPhase {
        euclideousLaneChainPhase(buf: c.buf, n: c.n, dir: c.dir, cycleLen: euclidCycleLen(c.dir, n: c.n), sub: c.sub, tick: tick, chains: c.chains, legacySpanBeats: c.spanBeats)
    }

    /// A 7-step lane with a hit on step 1 and a rhythm restart every bar of 16 sixteenths: step 1 plays on the downbeat of bars 2, 3 and 4. Without the restart tick 16/32/48 would be step 3/5/7 (16%7=2 etc.), so `raw==0` proves the restart was applied before the tick; the next tick is step 2, so it is neither stuck on step 1 nor skipped past it.
    func testRhythmRestartEveryBarPlaysStepOneOnEveryDownbeat() {
        var l = line(hits: 7, steps: 7, rate: .r1_16)   // E(7,7): every step is a hit, so step 0 (step 1) is a hit
        rhythm(&l, [1], unit: .bar)
        let lines = four(l), set = setFor(lines, bar: 4), c = cfg(lines, lane: 0, set: set, bar: 4)
        for (bar, tick) in [(2, Int64(16)), (3, 32), (4, 48)] {   // downbeats: beat 4 / 8 / 12 at 1/16
            let ph = chainPhase(c, tick: tick)
            XCTAssertEqual(ph.raw, 0, "bar \(bar) downbeat plays step 1, not the natural step \(Int(tick) % 7 + 1)")
            XCTAssertTrue(ph.rawIsHit, "and it is a hit")
            XCTAssertEqual(chainPhase(c, tick: tick + 1).raw, 1, "the next tick advances to step 2 — not stuck on step 1, not skipped")
        }
    }

    /// A melody restart every 3 hits: the riff ordinal resets to 0 before the restarting hit sounds, so the hits read 0,1,2,0,1,2,… — the 4th hit plays the first melody note.
    func testMelodyRestartEveryThreeHitsPlaysTheFirstNoteOnTheFourthHit() {
        var l = line(hits: 3, steps: 8, rate: .r1_8)
        melody(&l, [3], unit: .hit)
        let lines = four(l), set = setFor(lines), c = cfg(lines, lane: 0, set: set)
        let hs = hits(c, beats: 16)
        XCTAssertGreaterThanOrEqual(hs.count, 7)
        XCTAssertEqual(hs.prefix(7).map(\.ord), [0, 1, 2, 0, 1, 2, 0], "the 4th and 7th hits restart the riff to its first note")
    }

    /// A lane restarting from a source lane: lane B (restart unit PASS, source = lane A) restarts on the SAME tick as A's pass, never one later, and at that tick both play step 1. Order-independent: the component is one joint schedule, built once on the main thread.
    func testASourceLaneRestartLandsOnTheSameTickForBoth() {
        var a = line(hits: 8, steps: 8, rate: .r1_8); rhythm(&a, [1], unit: .bar)   // A restarts every bar (8 ticks at 1/8); all hits so step 1 is a hit
        var b = line(hits: 7, steps: 7, rate: .r1_8); rhythm(&b, [1], unit: .pass, source: 0)   // B restarts on A's pass
        let lines = four(a, b), set = setFor(lines, bar: 4)
        let ca = cfg(lines, lane: 0, set: set, bar: 4), cb = cfg(lines, lane: 1, set: set, bar: 4)
        XCTAssertEqual(ca.chains.rhythmOriginTick(4.0, sub: 0.5), 8, "A restarts at tick 8 (bar 2 downbeat)")
        XCTAssertEqual(cb.chains.rhythmOriginTick(4.0, sub: 0.5), 8, "B restarts on the SAME tick as A, not one later")
        XCTAssertEqual(chainPhase(ca, tick: 8).raw, 0); XCTAssertEqual(chainPhase(cb, tick: 8).raw, 0, "both play step 1 on that tick")
    }

    /// A 2,1,1 rhythm count sequence (BAR unit) restarts on bars 3, 4, 5, 7, 8, 9 — beats 8, 12, 16, 24, 28, 32 — beginning at its first count on transport start (beat 0 is the implicit start).
    func testTheTwoOneOneCountSequenceRestartsOnBars345789() {
        var l = line(hits: 3, steps: 8, rate: .r1_8); rhythm(&l, [2, 1, 1], unit: .bar)
        let lines = four(l), set = setFor(lines, bar: 4), c = cfg(lines, lane: 0, set: set, bar: 4)
        close(restarts({ c.chains.nextRhythmRestart(after: $0) }, upTo: 33), [8, 12, 16, 24, 28, 32])
    }

    /// Host transport start / a loop back to beat 0: the first tick plays step 1 (beat 0 is an implicit restart origin).
    func testTransportStartPlaysStepOne() {
        var l = line(hits: 7, steps: 7, rate: .r1_16); rhythm(&l, [1], unit: .bar)
        let lines = four(l), set = setFor(lines, bar: 4), c = cfg(lines, lane: 0, set: set, bar: 4)
        XCTAssertEqual(chainPhase(c, tick: 0).raw, 0, "tick 0 plays step 1")
    }

}

private struct SplitMix { var state: UInt64; init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }
