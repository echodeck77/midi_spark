//  RiffDirectionMirrorHuntTests.swift — BUG HUNT (2026-11-06), the RIFF WALK's DIRECTION: every PICTURE of the walk (arrow heading, rails, melody tile, walk period, static arrow seat) against the same independent bounce model
//  `RiffDirectionHuntTests` drives the real Router against (`bounceSequence`, never `riffStepAt`). Pure and fast.

import XCTest

final class RiffDirectionMirrorHuntTests: XCTestCase {
    private let dirs: [RiffDir] = [.forward, .reverse, .pendulum, .pingpong]
    private func pos(_ dir: RiffDir, _ L: Int, _ stride: Int, _ w: Int) -> Int {
        let seq = bounceSequence(dir, L)
        return seq[(((w * stride) % seq.count) + seq.count) % seq.count]
    }
    /// The smallest P ≥ 1 for which the position sequence repeats (checked over three full cycles).
    private func minimalPeriod(_ dir: RiffDir, _ L: Int, _ stride: Int) -> Int {
        let span = 3 * bounceSequence(dir, L).count
        for P in 1...max(1, 2 * bounceSequence(dir, L).count) where (0..<span).allSatisfy({ pos(dir, L, stride, $0) == pos(dir, L, stride, $0 + P) }) { return P }
        return 1
    }

    /// FX WALK PERIOD: the function's value is a period of the model walk (the NOTE pass index and REPEAT's bound lean on it) and never shorter than the minimal one.
    func testWalkPeriodIsAPeriodOfTheModelWalk() {
        var bad: [String] = []
        for dir in dirs { for L in 1...8 { for st in 1...7 {
            let P = euclideousFXWalkPeriod(dir: dir, length: L, stride: st)
            let span = 4 * bounceSequence(dir, L).count
            if !(0..<span).allSatisfy({ pos(dir, L, st, $0) == pos(dir, L, st, $0 + P) }) { bad.append("\(dir) L\(L) st\(st): P \(P) is not a period") }
            if L > 1, P < minimalPeriod(dir, L, st) { bad.append("\(dir) L\(L) st\(st): P \(P) < minimal \(minimalPeriod(dir, L, st))") }
        } } }
        XCTAssertTrue(bad.isEmpty, bad.prefix(5).joined(separator: " | "))
    }

    /// THE ARROW'S HEADING: PENDULUM / PING-PONG point at the next DIFFERENT position of the walk (so PING-PONG's doubled end step turns the arrow at each end); FWD right, REV left, still when the walk never moves.
    func testArrowHeadingIsTheDirectionOfTheNextDifferentPositionOfTheModelWalk() {
        var bad: [String] = []
        for dir in dirs { for L in 1...8 { for st in 1...7 { for every in 1...3 {
            let n = bounceSequence(dir, L).count
            let moves = L > 1 && minimalPeriod(dir, L, st) > 1
            for o in 0..<(2 * n * every + 3) {
                let w = o / every
                var want: EuclideousArrowHeading = .still
                if moves {
                    switch dir {
                    case .forward, .random, .drunk: want = .right
                    case .reverse: want = .left
                    case .pendulum, .pingpong:
                        let p = pos(dir, L, st, w)
                        for k in 1...(2 * n) { let q = pos(dir, L, st, w + k); if q != p { want = q > p ? .right : .left; break } }
                    }
                }
                let got = euclideousArrowHeading(riffDir: dir, length: L, stride: st, every: every, ordinal: Int64(o))
                if got != want { bad.append("\(dir) L\(L) st\(st) ev\(every) o\(o): \(got) vs model \(want)") }
            }
        } } } }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) differ; first: \(bad.prefix(4).joined(separator: " | "))")
    }

    /// THE MELODY TILE'S CELLS: cell i is the i-th DISTINCT column the model walk first visits (shift applied), the columns it never visits follow in window order, and `visited` counts the first group.
    func testRestartTileCellOrderIsTheOrderTheModelWalkFirstVisitsEachColumn() {
        var bad: [String] = []
        for dir in dirs { for L in 1...8 { for st in 1...7 { for shift in 0...7 {
            let n = bounceSequence(dir, L).count
            var order: [Int] = []
            for w in 0..<(4 * n) { let c = (pos(dir, L, st, w) + shift) % 8; if !order.contains(c) { order.append(c) } }
            let visited = order.count
            for i in 0..<L { let c = (i + shift) % 8; if !order.contains(c) { order.append(c) } }
            let got = euclideousRiffCycleOrder(dir: dir, length: L, stride: st, shift: shift)
            if got.cellColumns.map({ Int($0) }) != order || got.visited != visited { bad.append("\(dir) L\(L) st\(st) sh\(shift): \(got.cellColumns) visited \(got.visited) vs \(order) \(visited)") }
            for (cell, col) in order.enumerated() where got.cell(ofColumn: col) != cell { bad.append("\(dir) L\(L) st\(st) sh\(shift): column \(col) is cell \(String(describing: got.cell(ofColumn: col))), want \(cell)"); break }
        } } } }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) differ; first: \(bad.prefix(4).joined(separator: " | "))")
    }

    private func config(_ dir: RiffDir, _ L: Int, _ st: Int, _ shift: Int, _ every: Int, _ step: Bool, hits: [Bool]) -> EuclideousWalkLaneConfig {
        var c = EuclideousWalkLaneConfig(buf: hits, n: hits.count, dir: .fwd, sub: 0.5)
        c.riffDir = dir; c.length = L; c.stride = st; c.rotate = shift; c.every = every; c.advanceStep = step
        return c
    }

    /// THE RAIL: the current column is the model's column for the hit's ordinal; the trail is the columns of the lane's EARLIER hits, newest first, skipping a column equal to the one taken just before it, up to three.
    func testRailCurrentAndTrailMatchTheModelWalk() {
        var bad: [String] = []
        var rng = HuntRng(s: 99)
        for trial in 0..<1500 {
            let dir = dirs[rng.int(0...3)], L = rng.int(1...8), st = rng.int(1...7), shift = rng.int(0...7), every = rng.int(1...3), step = rng.bool()
            var hits = (0..<rng.int(2...8)).map { _ in rng.bool(0.6) }
            if !hits.contains(true) { hits[0] = true }
            let c = config(dir, L, st, shift, every, step, hits: hits)
            let n = hits.count
            let hitTicks = (0..<80).filter { hits[$0 % n] }
            let hi = rng.int(0...(hitTicks.count - 1))
            let k = hitTicks[hi]
            func col(_ ordinal: Int) -> Int { (pos(dir, L, st, ordinal / every) + shift) % 8 }
            func ordinal(of tick: Int) -> Int { step ? tick : hitTicks.firstIndex(of: tick)! }
            let current = col(ordinal(of: k))
            var trail: [Int] = [], last = current
            for t in hitTicks[0..<hi].reversed() where trail.count < 3 { let cc = col(ordinal(of: t)); if cc != last { trail.append(cc); last = cc } }
            let got = euclideousRailWalk(cfg: c, hitTick: Int64(k))
            if got.current != current || got.trail != trail {
                bad.append("trial \(trial) \(dir) L\(L) st\(st) sh\(shift) ev\(every) \(step ? "STEP" : "HIT") hits \(hits.map { $0 ? "x" : "." }.joined()) tick \(k): current \(got.current) trail \(got.trail) vs model \(current) \(trail)")
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) differ; first: \(bad.prefix(3).joined(separator: " | "))")
    }

    /// THE MELODY TILE'S LIT CELLS (melody FREE, ADV HIT, every tick a hit): the cells lit at a beat are the distinct columns the model walk has visited since its CYCLE began.
    func testRestartTileLitCellsAreTheDistinctColumnsOfTheCurrentCycle() {
        var bad: [String] = []
        for dir in dirs { for L in 2...8 { for st in [1, 2, 3, 5] { for every in 1...2 { for shift in [0, 3] {
            let P = euclideousFXWalkPeriod(dir: dir, length: L, stride: st)
            var c = config(dir, L, st, shift, every, false, hits: [true, true, true, true])
            c.chains = .off
            for k in 0..<(2 * P * every + 3) {
                let tile = restartTileState(.melody, cfg: c, beat: (Double(k) + 0.5) * 0.5, running: true)
                let cycle = k / (P * every)
                var seen: [Int] = []
                for w in (cycle * P)...(k / every) { let cc = (pos(dir, L, st, w) + shift) % 8; if !seen.contains(cc) { seen.append(cc) } }
                if tile.litCount != seen.count { bad.append("\(dir) L\(L) st\(st) ev\(every) sh\(shift) k\(k) (P\(P)): lit \(tile.litCount) vs model \(seen.count)") }
            }
        } } } } }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) differ; first: \(bad.prefix(4).joined(separator: " | "))")
    }

    /// THE "N NEVER PLAY" READOUT and the WALK strip's dimmed cells (melody FREE, rhythm FREE): the columns / walk steps no hit of the model ever reads, ADV HIT and ADV STEP, every direction.
    func testNeverPlayReadoutMatchesAnExplicitSimulationOfTheModelWalk() {
        var bad: [String] = []
        var rng = HuntRng(s: 4242)
        for trial in 0..<600 {
            let dir = dirs[rng.int(0...3)], L = rng.int(1...8), st = rng.int(1...7), shift = rng.int(0...7), every = rng.int(1...3), step = rng.bool()
            var hits = (0..<rng.int(2...8)).map { _ in rng.bool(0.5) }
            if !hits.contains(true) { hits[rng.int(0...(hits.count - 1))] = true }
            let n = hits.count
            let P = euclideousFXWalkPeriod(dir: dir, length: L, stride: st)
            var cols = Set<Int>(), walkSteps = Set<Int>()
            var ordinal = 0
            for t in 0..<4000 where hits[t % n] {
                let o = step ? t : ordinal
                let w = o / every
                cols.insert((pos(dir, L, st, w) + shift) % 8); walkSteps.insert(w % P)
                ordinal += 1
            }
            let window = Set((0..<L).map { (shift + $0) % 8 })
            let wantNever = window.subtracting(cols), wantNeverSteps = Set(0..<P).subtracting(walkSteps)
            let r = euclideousRiffReadout(buf: hits, n: n, dir: .fwd, cycleLen: n, sub: 0.5, chains: .off, legacySpanBeats: 0, advanceStep: step,
                                          riffDir: dir, stride: st, length: L, shift: shift, every: every, seed: 0)
            guard let r else { bad.append("trial \(trial): nil readout"); continue }
            if r.neverPlay != wantNever || r.neverPlayWalkSteps != wantNeverSteps {
                bad.append("trial \(trial) \(dir) L\(L) st\(st) sh\(shift) ev\(every) \(step ? "STEP" : "HIT") hits \(hits.map { $0 ? "x" : "." }.joined()): never \(r.neverPlay.sorted()) steps \(r.neverPlayWalkSteps.sorted()) vs model \(wantNever.sorted()) \(wantNeverSteps.sorted())")
            }
        }
        XCTAssertTrue(bad.isEmpty, "\(bad.count) differ; first: \(bad.prefix(3).joined(separator: " | "))")
    }

    /// A STOPPED / uncorroborated arrow seat on a REST with SHIFT: the row it holds is the nearest note BEHIND it in the lane's riff WINDOW (columns SHIFT … SHIFT+LEN−1, wrapping at 8) — the running plan's `heldRank` fallback reads
    /// the window; the static seat reads `posMod(step ∓ j, LEN)`, i.e. columns 0…LEN−1, outside the window the walk plays.
    func testStaticArrowSeatOnARestHoldsTheRowOfTheNearestNoteInsideTheShiftedWindow() {
        var c = EuclideousWalkLaneConfig(buf: [true, true, true, true], n: 4, dir: .fwd, sub: 0.5)
        c.riffDir = .forward; c.length = 4; c.rotate = 4          // the window is columns 4, 5, 6, 7
        let ranks = [3, 0, 0, 0, 0, 0, 5, 0]                       // column 0 (outside the window) has a note of rank 3; the window's only note is column 6, rank 5
        let plan = euclideousWalkTagPlan(cfg: c, ranks: ranks, beat: 0, secondsPerBeat: 0.5, polledStep: 4, running: false, polledOrdinal: 0)
        XCTAssertEqual(plan?.seatIsRest, true)
        XCTAssertEqual(plan?.seatRank, 5, "the row of the nearest note behind column 4 in the walk's window is column 6's (rank 5), not the outside column 0's (rank 3)")
    }
}
