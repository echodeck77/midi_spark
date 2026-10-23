//  RiffGridArrowFuzzTests.swift
//  RIFF GRID review (2026-10-21): the riff panel's arrows against the engine's own walk mirror, over seeded random lanes — where a lane's arrow sits after each hit it lands, for played hits and for hits on
//  riff rests under SKIP / TIE / REPEAT — and the rule that only a RUNNING lane has an arrow.

import XCTest

final class RiffGridArrowFuzzTests: XCTestCase {
    private struct Rng { var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
        mutating func bool(_ p: Double = 0.5) -> Bool { Double(next() % 10_000) / 10_000 < p } }

    func testHollowArrowsAgainstTheEngine() {
        var rng = Rng(s: 0xA110_0001)
        var played = 0, restSkip = 0, restTie = 0, restRepeat = 0
        var repeatRowMismatch = 0, repeatColMismatch = 0, skipRowMismatch = 0, tieMismatch = 0, playedMismatch = 0
        var examples: [String] = []
        for trial in 0..<1500 {
            let n = rng.int(2...16)
            var l = EuclidLine(target: 0, pulses: rng.int(1...n), steps: n, rate: .r1_16, useRiff: true, sourceMode: .midi)
            l.direction = [.fwd, .bkw][rng.int(0...1)]
            l.riffDir = [.forward, .reverse, .pendulum, .pingpong][rng.int(0...3)]
            l.riffLength = rng.int(1...8); l.riffStride = rng.int(1...3); l.riffRotate = rng.int(0...7)
            l.riffAdvanceEvery = rng.int(1...8); l.riffAdvanceStep = rng.bool(); l.riffOn = true
            l.riffOnRest = [.skip, .tie, .repeatLast][rng.int(0...2)]
            let ranks = (0..<8).map { _ in rng.bool(0.35) ? 0 : rng.int(1...8) }
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { continue }
            let cycleLen = euclidCycleLen(l.directionResolved, n: n)
            let base = Int64(cycleLen) * Int64(rng.int(3...30))
            for off in 0..<cycleLen {
                let t = base + Int64(off)
                let w = euclideousWalkTick(cfg, tick: t)
                guard w.isHit, w.strikes else { continue }
                let beat = (Double(t) + 0.1) * cfg.sub
                guard let plan = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: beat, secondsPerBeat: 0.5, polledStep: w.playedStep, running: true, polledOrdinal: w.advOrd), plan.landedTick == t else { continue }
                let arrow = euclideousLaneArrowState(lane: 0, cfg: cfg, plan: plan, polledOrdinal: w.advOrd)
                let written = ranks[w.playedStep]
                if written >= 1 {
                    played += 1
                    if arrow.column != w.playedStep || arrow.rank != written || arrow.hollow { playedMismatch += 1 }
                } else {
                    switch l.riffOnRestResolved {
                    case .skip: restSkip += 1
                        if arrow.column != w.playedStep || !arrow.hollow { skipRowMismatch += 1 }
                    case .tie: restTie += 1
                        if arrow.hollow { tieMismatch += 1 }
                    default:
                        restRepeat += 1
                        let rep = euclideousRiffRepeatLookback(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: t, chains: cfg.chains, legacySpanBeats: cfg.spanBeats, advanceStep: cfg.advanceStep,
                                                               riffDir: cfg.riffDir, stride: cfg.stride, length: cfg.length, rotate: cfg.rotate, seed: cfg.seed, every: cfg.every, thisBeat: 0, rankAt: { c, _ in ranks[c] })
                        if let rep {
                            if arrow.column != w.playedStep { repeatColMismatch += 1 }
                            if arrow.rank != rep.rank { repeatRowMismatch += 1; if examples.count < 4 { examples.append("trial \(trial) tick \(off): arrow rank \(arrow.rank) vs repeated rank \(rep.rank) (col \(rep.column + 1)); every \(cfg.every) advStep \(cfg.advanceStep) dir \(cfg.riffDir)") } }
                        }
                    }
                }
            }
        }
        print("RIFF GRID arrows: played \(played) (mismatch \(playedMismatch)); SKIP rests \(restSkip) (mismatch \(skipRowMismatch)); TIE rests \(restTie) (arrow hollow \(tieMismatch)); REPEAT rests \(restRepeat) (col mismatch \(repeatColMismatch), row differs from the repeated note \(repeatRowMismatch)) \(examples)")
        XCTAssertEqual(playedMismatch, 0, "a played hit's arrow is on its own column and written row"); XCTAssertEqual(skipRowMismatch, 0, "a SKIP rest's arrow is hollow in the rest's own column")
        XCTAssertLessThanOrEqual(tieMismatch, restTie / 50, "a TIE rest's arrow stays on the held note (hollow only when nothing is held yet)")
        XCTAssertEqual(repeatColMismatch, 0, "a REPEAT rest's arrow is in the rest's own column"); XCTAssertLessThanOrEqual(repeatRowMismatch, restRepeat / 50, "…at the repeated note's row (the held row — the same note but for a rare tie-break)")
        XCTAssertGreaterThan(played, 1000)
    }

    // MARK: only a running lane has an arrow
    func testOnlyARunningLaneHasAnArrow() {
        func line(enabled: Bool, pulses: Int, miss: Bool = false) -> EuclidLine { var l = EuclidLine(target: 0, pulses: pulses, steps: 8, rate: .r1_16, useRiff: true, sourceMode: .midi); l.enabled = enabled; l.patternMiss = miss; return l }
        for transport in [false, true] { for enabled in [false, true] {
            XCTAssertEqual(euclideousLaneIsRunning(transportPlaying: transport, line: line(enabled: enabled, pulses: 3)), transport && enabled, "transport \(transport) lane \(enabled)")
        } }
        XCTAssertFalse(euclideousLaneIsRunning(transportPlaying: true, line: line(enabled: true, pulses: 0)), "a lane taken down to 0 HITS is not run by the engine either")
        XCTAssertTrue(euclideousLaneIsRunning(transportPlaying: true, line: line(enabled: true, pulses: 0, miss: true)), "…unless its pattern is inverted (the engine's own gate)")
        XCTAssertTrue(euclideousLaneArrowShows(riffOn: true, running: true))
        XCTAssertFalse(euclideousLaneArrowShows(riffOn: true, running: false), "a lane switched off (or the transport stopped) has no arrow")
        XCTAssertFalse(euclideousLaneArrowShows(riffOn: false, running: true), "riff off (or SHADOWing): no arrow")
        // why the page must not simply ask the plan about a stopped lane: the engine keeps the lane's last step, and the plan answers a STATIC seat on it
        let ranks = [3, 0, 5, 0, 7, 0, 2, 0]
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [EuclidLine(target: 0, pulses: 4, steps: 8, rate: .r1_16, useRiff: true, sourceMode: .midi)], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        let stale = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: 12.3, secondsPerBeat: 0.5, polledStep: 4, running: false)
        XCTAssertEqual(stale?.seatStep, 4); XCTAssertNil(stale?.landedTick, "a static seat: no hit has landed in this run")
    }
}
