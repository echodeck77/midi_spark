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
        var longest = 0.0, worstMs = 0.0, windowedCount = 0, total = 0
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
            if set.windowed { windowedCount += 1 }
            for lane in 0..<4 { if let d = set.lane(lane)?.data, d.period + d.prefixEnd > longest { longest = d.period + d.prefixEnd; worstCase = "draw \(n) lane \(lane)" } }
            if ms > worstMs { worstMs = ms }
        }
        print("RESTART UNITS schedule probe: \(total) draws, \(windowedCount) windowed, longest prefix+period \(longest / 4) bars (\(worstCase)), slowest build \(Int(worstMs)) ms (Debug)")
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
}

private struct SplitMix { var state: UInt64; init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) } }
