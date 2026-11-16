//  RestartRulerTests.swift — RESETS V2 ferry (2026-11-15) §5: the pure ruler / ratio / running-link readers against the
//  ferry's worked examples. Display-only — these readers do not touch the engine; the goldens are unchanged. Defaults as
//  RESTART UNITS §10: 1/8 steps (0.5 beat) unless a test sets the rate, barBeats 4, riff length 8, FWD, ADV HIT.

import XCTest

final class RestartRulerTests: XCTestCase {
    // MARK: helpers (mirrors RestartScheduleTests)
    private func line(hits: Int, steps: Int, rate: ArpRate = .r1_8, dir: EuclidDir = .fwd, advanceStep: Bool = false) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: hits, steps: steps)
        l.rate = rate; l.direction = dir; l.riffAdvanceStep = advanceStep; l.useRiff = true; l.riffOn = true
        l.restartRhythmBars = []; l.restartMelodyPasses = []
        return l
    }
    private func rhythm(_ l: inout EuclidLine, _ links: [UInt8], unit: EuclideousRhythmRestartUnit = .bar, source: Int? = nil) {
        l.restartRhythmBars = links; l.restartRhythmUnit = unit; l.restartRhythmSource = source; l.restartRhythmOn = nil
    }
    private func melody(_ l: inout EuclidLine, _ links: [UInt8], unit: EuclideousMelodyRestartUnit = .pass, source: Int? = nil, withRhythm: Bool = false) {
        l.restartMelodyPasses = links; l.restartMelodyUnit = unit; l.restartMelodySource = source; l.restartMelodyOn = nil; l.restartMelodyWithRhythm = withRhythm ? true : nil
    }
    private func four(_ l0: EuclidLine) -> [EuclidLine] { [l0, line(hits: 1, steps: 8), line(hits: 1, steps: 8), line(hits: 1, steps: 8)] }
    private func setFor(_ lines: [EuclidLine], bar: Double = 4) -> EuclideousRestartScheduleSet {
        euclideousBuildRestartScheduleSet(euclideousScheduleInputs(lines: lines, barBeats: bar, defaultRateBeats: 0.25, riffColumns: 8), engagedMask: 0, maxBars: 1024, detectPeriod: true)
    }
    private func cfg(_ lines: [EuclidLine], set: EuclideousRestartScheduleSet?, bar: Double = 4) -> EuclideousWalkLaneConfig {
        euclideousWalkLaneConfig(lane: 0, lines: lines, cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8, defaultRateBeats: 0.25, beatsPerBar: bar, scheduleSet: set)!
    }
    private func build(_ l: EuclidLine, bar: Double = 4) -> EuclideousWalkLaneConfig { let ls = four(l); return cfg(ls, set: setFor(ls, bar: bar), bar: bar) }

    private func assertBlocks(_ got: [EuclideousRestartRulerBlock], _ want: [(Double, Double, Bool)], _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(got.count, want.count, "\(msg): block count — got \(got)", file: file, line: line)
        for (g, w) in zip(got, want) {
            XCTAssertEqual(g.start, w.0, accuracy: 1e-6, "\(msg): start", file: file, line: line)
            XCTAssertEqual(g.end, w.1, accuracy: 1e-6, "\(msg): end", file: file, line: line)
            XCTAssertEqual(g.cut, w.2, "\(msg): cut @\(g)", file: file, line: line)
        }
    }

    // §5 test 1 — riff-first (RESTART UNITS test 3): E(3,8), rhythm RIFF [1] of itself. Span 0–10; passes 0–4, 4–8 solid, 8–10 cut; ratio 8:8.
    func testRiffFirstRhythmRuler() {
        var l = line(hits: 3, steps: 8); rhythm(&l, [1], unit: .riff, source: 0)
        let c = build(l)
        let r = euclideousRestartRuler(.rhythm, cfg: c, beat: 1.0, running: true)
        XCTAssertFalse(r.isFree)
        XCTAssertEqual(r.spanStart, 0, accuracy: 1e-6); XCTAssertEqual(r.spanLen, 10, accuracy: 1e-6)
        assertBlocks(r.blocks, [(0, 4, false), (4, 8, false), (8, 10, true)], "riff-first passes")
        let ratio = euclideousRestartRatioSteps(.rhythm, cfg: c, beat: 1.0, steps: 8, barBeats: 4)
        XCTAssertEqual(ratio.part, 8, accuracy: 1e-6); XCTAssertEqual(ratio.bar, 8, accuracy: 1e-6)
    }

    // §5 test 2 — a pass SHORTER than the bar: 12 steps of 1/16 (lap 3 beats), rhythm BAR [1] (restart every 4 beats). Blocks 0–3 solid, 3–4 cut; ratio 12:16.
    func testPassShorterThanBar() {
        var l = line(hits: 4, steps: 12, rate: .r1_16); rhythm(&l, [1], unit: .bar)
        let c = build(l)
        let r = euclideousRestartRuler(.rhythm, cfg: c, beat: 1.0, running: true)
        XCTAssertEqual(r.spanStart, 0, accuracy: 1e-6); XCTAssertEqual(r.spanLen, 4, accuracy: 1e-6)
        assertBlocks(r.blocks, [(0, 3, false), (3, 4, true)], "short pass")
        let ratio = euclideousRestartRatioSteps(.rhythm, cfg: c, beat: 1.0, steps: 12, barBeats: 4)
        XCTAssertEqual(ratio.part, 12, accuracy: 1e-6); XCTAssertEqual(ratio.bar, 16, accuracy: 1e-6)
    }

    // §5 test 3 — a pass LONGER than the bar. SPEC-VS-CODE: the spec's "20 steps of 1/16" is unreachable — the Euclid pattern
    // clamps steps to 16 (Models.swift:1121), so at 1/16 (0.25 beat) a pass tops out at 4 beats = exactly the bar (no cut).
    // To exercise the intended behaviour legally: 16 steps of 1/8 (lap 8 beats), rhythm BAR [1] — one block 0–4, cut; ratio 16:8.
    func testPassLongerThanBar() {
        var l = line(hits: 5, steps: 16, rate: .r1_8); rhythm(&l, [1], unit: .bar)
        let c = build(l)
        let r = euclideousRestartRuler(.rhythm, cfg: c, beat: 1.0, running: true)
        XCTAssertEqual(r.spanStart, 0, accuracy: 1e-6); XCTAssertEqual(r.spanLen, 4, accuracy: 1e-6)
        assertBlocks(r.blocks, [(0, 4, true)], "long pass (16 steps of 1/8 = 8-beat lap, cut by the 4-beat bar restart)")
        let ratio = euclideousRestartRatioSteps(.rhythm, cfg: c, beat: 1.0, steps: 16, barBeats: 4)
        XCTAssertEqual(ratio.part, 16, accuracy: 1e-6); XCTAssertEqual(ratio.bar, 8, accuracy: 1e-6)
    }

    // §5 test 4 — FREE drift: 12 steps of 1/16 (lap 3 beats), rhythm FREE. Pass boundaries at beat 3 (bar 1), beat 2 (bar 2), beat 1 (bar 3); bar 4 repeats bar 1; grey blocks; nothing cut; ratio 12:16.
    func testFreeDrift() {
        let l = line(hits: 4, steps: 12, rate: .r1_16)   // no rhythm chain
        let c = build(l)
        func spanAndBounds(_ beat: Double) -> (EuclideousRestartRuler) { euclideousRestartRuler(.rhythm, cfg: c, beat: beat, running: true) }
        let r1 = spanAndBounds(0.5), r2 = spanAndBounds(4.5), r3 = spanAndBounds(8.5), r4 = spanAndBounds(12.5)
        for r in [r1, r2, r3, r4] { XCTAssertTrue(r.isFree); XCTAssertTrue(r.blocks.allSatisfy { !$0.cut }, "FREE never hatches") }
        // the internal pass boundary (a block start strictly inside the bar): bar 1 at beat 3, bar 2 at beat 6 (=beat 2), bar 3 at beat 9 (=beat 1)
        func innerBoundary(_ r: EuclideousRestartRuler) -> Double? { r.blocks.map { $0.start }.first { $0 > r.spanStart + 1e-6 && $0 < r.spanStart + r.spanLen - 1e-6 } }
        XCTAssertEqual(innerBoundary(r1)!, 3, accuracy: 1e-6)             // beat 3 of bar 1
        XCTAssertEqual(innerBoundary(r2)!, 6, accuracy: 1e-6)             // beat 2 of bar 2 (drift)
        XCTAssertEqual(innerBoundary(r3)!, 9, accuracy: 1e-6)             // beat 1 of bar 3 (drift)
        // bar 4 starts ON a pass start (its first block begins exactly at the span start, 12 — the view draws no gap there), and its inner boundary is back at relative beat 3 (15), so it repeats bar 1.
        XCTAssertEqual(r4.blocks.first!.start, 12, accuracy: 1e-6, "bar 4's first block starts on the pass boundary at the span's left edge")
        XCTAssertEqual(innerBoundary(r4)! - r4.spanStart, 3, accuracy: 1e-6, "bar 4 repeats bar 1 (inner boundary at relative beat 3)")
        let ratio = euclideousRestartRatioSteps(.rhythm, cfg: c, beat: 0.5, steps: 12, barBeats: 4)
        XCTAssertEqual(ratio.part, 12, accuracy: 1e-6); XCTAssertEqual(ratio.bar, 16, accuracy: 1e-6)
    }

    // §5 test 5 — melody HIT [3] on E(5,8) (RESTART UNITS test 5, rhythm FREE): one riff cycle per span, cut by the 3-hit restart; ratio 13:8.
    func testMelodyHitThreeRuler() {
        var l = line(hits: 5, steps: 8); melody(&l, [3], unit: .hit)
        let c = build(l)
        let r = euclideousRestartRuler(.melody, cfg: c, beat: 1.2, running: true)
        XCTAssertFalse(r.isFree)
        XCTAssertEqual(r.blocks.count, 1, "one riff cycle in the 3-hit span: \(r.blocks)")
        XCTAssertTrue(r.blocks.allSatisfy { $0.cut }, "every block hatched (cut before its 8-hit natural completion)")
        let ratio = euclideousRestartRatioSteps(.melody, cfg: c, beat: 1.2, steps: 8, barBeats: 4)
        XCTAssertEqual(ratio.part, 13, accuracy: 1e-6, "the riff cycle's natural length is 13 steps"); XCTAssertEqual(ratio.bar, 8, accuracy: 1e-6)
    }

    // §5 test 6 — melody linked (WITH RHYTHM) with its own chain inactive: the melody span equals the rhythm's; set look (not FREE).
    func testLinkedMelodySpanEqualsRhythm() {
        var l = line(hits: 3, steps: 8); rhythm(&l, [1], unit: .bar); melody(&l, [], withRhythm: true)
        let c = build(l)
        let m = euclideousRestartRuler(.melody, cfg: c, beat: 1.0, running: true)
        let ry = euclideousRestartRuler(.rhythm, cfg: c, beat: 1.0, running: true)
        XCTAssertFalse(m.isFree, "a linked melody reads as set, not FREE")
        XCTAssertEqual(m.spanStart, ry.spanStart, accuracy: 1e-6, "the melody span equals the rhythm's restart span")
        XCTAssertEqual(m.spanLen, ry.spanLen, accuracy: 1e-6)
    }

    // §5 test 7 — dotted 1/8 steps (0.75 beat): one host bar is 4 ÷ 0.75 = 5.333 steps (the view shows "5.3").
    func testDottedEighthBarRatio() {
        var l = line(hits: 3, steps: 8, rate: .r1_8d); rhythm(&l, [1], unit: .bar)
        let c = build(l)
        let ratio = euclideousRestartRatioSteps(.rhythm, cfg: c, beat: 1.0, steps: 8, barBeats: 4)
        XCTAssertEqual(ratio.bar, 4.0 / 0.75, accuracy: 1e-6, "barBeats 4 ÷ step 0.75 = 5.333…")
    }

    // §5 test 9 — the running link: rhythm BAR [2,1,1] (links of 2, 1, 1 bars). Link 0 for bars 1–2, link 1 for bar 3, link 2 for bar 4.
    func testRunningLink() {
        let chain = EuclideousRestartChain.from([2, 1, 1])
        XCTAssertEqual(chain.total, 4)
        XCTAssertEqual(euclideousRestartRunningLink(chain: chain, current: 0), 0)
        XCTAssertEqual(euclideousRestartRunningLink(chain: chain, current: 1), 0)
        XCTAssertEqual(euclideousRestartRunningLink(chain: chain, current: 2), 1)
        XCTAssertEqual(euclideousRestartRunningLink(chain: chain, current: 3), 2)
        XCTAssertEqual(euclideousRestartRunningLink(chain: chain, current: 4), 0, "wraps")
        XCTAssertNil(euclideousRestartRunningLink(chain: .free, current: 0), "an inactive chain has no running link")
    }

    // RESETS V2 §2 — the ratio text: a whole part, a bar that drops a trailing .0 and otherwise shows one decimal.
    func testRatioText() {
        XCTAssertEqual(euclideousRestartRatioText(part: 8, bar: 8), "8:8")
        XCTAssertEqual(euclideousRestartRatioText(part: 12, bar: 16), "12:16")
        XCTAssertEqual(euclideousRestartRatioText(part: 13, bar: 8), "13:8")
        XCTAssertEqual(euclideousRestartRatioText(part: 16, bar: 4.0), "16:4", "a whole bar drops the .0")
        XCTAssertEqual(euclideousRestartRatioText(part: 12, bar: 4.0 / 0.75), "12:5.3", "dotted 1/8: 4 ÷ 0.75 = 5.333 → 5.3 (§5 test 7)")
    }

    // RESETS V2 §4.1 — the tile's VoiceOver label.
    func testTileVoiceOver() {
        XCTAssertEqual(euclideousRestartTileVoiceOver(kind: .rhythm, part: 7, bar: 8, isFree: false, cutNow: false), "Rhythm, 7-step pass, 8-step bar")
        XCTAssertEqual(euclideousRestartTileVoiceOver(kind: .melody, part: 17, bar: 8, isFree: false, cutNow: false), "Melody, 17-step riff, 8-step bar")
        XCTAssertEqual(euclideousRestartTileVoiceOver(kind: .rhythm, part: 12, bar: 16, isFree: true, cutNow: false), "Rhythm, 12-step pass, 16-step bar, free")
        XCTAssertEqual(euclideousRestartTileVoiceOver(kind: .melody, part: 13, bar: 8, isFree: false, cutNow: true), "Melody, 13-step riff, 8-step bar, cut short")
    }

    // RESETS V2 draft 3 §2 — the "N OF M" value (how much of the pass / riff cycle plays before the next reset).
    private func hitsIn(_ c: EuclideousWalkLaneConfig, _ r: EuclideousRestartRuler) -> [Double] {
        guard c.sub > 0, r.spanLen > 1e-9 else { return [] }
        var out: [Double] = []; let first = Int64((r.spanStart / c.sub - 1e-9).rounded(.down)), last = Int64(((r.spanStart + r.spanLen) / c.sub + 1e-9).rounded(.up))
        var t = first; while t <= last { if euclideousWalkTick(c, tick: t).isHit { let b = Double(t) * c.sub; if b >= r.spanStart - 1e-9 && b < r.spanStart + r.spanLen - 1e-9 { out.append(b) } }; t += 1 }
        return out
    }
    private func assertNM(_ got: (n: Int, m: Int), _ n: Int, _ m: Int, _ msg: String = "", file: StaticString = #filePath, line ln: UInt = #line) {
        XCTAssertEqual(got.n, n, "N — \(msg)", file: file, line: ln); XCTAssertEqual(got.m, m, "M — \(msg)", file: file, line: ln)
    }
    private func nm(_ kind: EuclideousRestartKind, _ c: EuclideousWalkLaneConfig, _ l: EuclidLine, beat: Double, steps: Int) -> (n: Int, m: Int) {
        let r = euclideousRestartRuler(kind, cfg: c, beat: beat, running: true)
        return euclideousRestartNOfM(kind, sub: c.sub, ruler: r, hits: hitsIn(c, r), line: l, beat: beat, steps: steps)
    }
    func testNOfMRhythmRiffFirstCutsTheThirdPass() {   // §6 test 1
        var l = line(hits: 3, steps: 8); rhythm(&l, [1], unit: .riff, source: 0); let c = build(l)
        assertNM(nm(.rhythm, c, l, beat: 1.0, steps: 8), 8, 8, "8 OF 8 in the first pass")
        XCTAssertEqual(nm(.rhythm, c, l, beat: 9.0, steps: 8).n, 4, "4 OF 8 once the third pass is cut at beat 8")
    }
    func testNOfMRhythmBarPassShorterThanBar() {   // §6 test 2
        var l = line(hits: 4, steps: 12, rate: .r1_16); rhythm(&l, [1], unit: .bar); let c = build(l)
        assertNM(nm(.rhythm, c, l, beat: 0.5, steps: 12), 12, 12, "the whole 12-step pass fits before the bar")
        XCTAssertEqual(nm(.rhythm, c, l, beat: 3.5, steps: 12).n, 4, "the remainder 3..4 is cut at the bar ⇒ 4 OF 12")
    }
    func testNOfMFreeRhythmAndMelodyReadFullUncut() {   // §6 test 1 melody / §2.4
        let c = build(line(hits: 3, steps: 8))   // FREE / FREE
        assertNM(nm(.rhythm, c, line(hits: 3, steps: 8), beat: 1.0, steps: 8), 8, 8, "FREE rhythm 8 OF 8")
        assertNM(nm(.melody, c, line(hits: 3, steps: 8), beat: 1.0, steps: 8), 8, 8, "FREE melody 8 OF 8")
    }
    func testNOfMMelodyEveryPassPlaysThreeOfEight() {   // §6 test 5
        var l = line(hits: 3, steps: 8); melody(&l, [1], unit: .pass, source: 0); let c = build(l)
        assertNM(nm(.melody, c, l, beat: 1.0, steps: 8), 3, 8, "3 of the riff's 8 notes play before the melody restarts each pass")
    }
    func testNOfMMelodyHitThreePlaysThreeOfEight() {   // §6 test 6
        var l = line(hits: 5, steps: 8); melody(&l, [3], unit: .hit, source: 0); let c = build(l)
        assertNM(nm(.melody, c, l, beat: 0.3, steps: 8), 3, 8, "HIT [3] ⇒ 3 OF 8")
    }
    func testNOfMAdvStepMelodyPlaysEightOfEight() {   // §6 test 8
        var l = line(hits: 3, steps: 8, advanceStep: true); melody(&l, [1], unit: .pass, source: 0); let c = build(l)
        assertNM(nm(.melody, c, l, beat: 1.0, steps: 8), 8, 8, "ADV STEP: the riff completes with the pass ⇒ 8 OF 8")
    }
}
