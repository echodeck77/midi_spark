//  LaneStripFuzzTests.swift
//  An adversarial cross-check of the lane strip's pure plan against the engine's own walk mirror, over seeded random lanes (rhythm, direction incl. PING-PONG, riff walk, ADVANCE EVERY, ADV STEP, ON REST,
//  melody restart chains, riff ranks with rests, the notes layer). The strip must agree with `euclideousWalkTick` (which the Router's tests pin to the real render) on every hit's column and rank, on which
//  hits are riff rests, on REPEAT's rank, on which hits the notes are due on and what the way picks (against a brute-force replay of the hits since the melody origin), and its current chip must be the arrow's.
//  Found by this test: PING-PONG visits each step twice, and a single chip per step showed the later visit's note — the strip now has a leg per sweep.

import XCTest

final class LaneStripFuzzTests: XCTestCase {
    private struct Rng { var s: UInt64
        mutating func next() -> UInt64 { s = s &* 6364136223846793005 &+ 1442695040888963407; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.upperBound - r.lowerBound + 1)) }
        mutating func bool(_ p: Double = 0.5) -> Bool { Double(next() % 10_000) / 10_000 < p } }

    func testTheStripAgreesWithTheEnginesWalkOnRandomLanes() {
        var rng = Rng(s: 0x5EED_1234)
        var checkedHits = 0, checkedCurrent = 0, repeatsChecked = 0, gapsChecked = 0, labelsChecked = 0, pingPongHits = 0
        for trial in 0..<1200 {
            let n = rng.int(2...16)
            var l = EuclidLine(target: 0, pulses: rng.int(1...n), steps: n, rate: [.r1_16, .r1_8, .r1_4][rng.int(0...2)], useRiff: true, sourceMode: .midi)
            if rng.bool(0.5) { l.customHits = (0..<n).map { _ in rng.bool(0.55) }; if !(l.customHits!.contains(true)) { l.customHits![0] = true } }
            l.rotate = rng.int(0...(n - 1))
            l.direction = [.fwd, .bkw, .pingpong][rng.int(0...2)]
            l.riffDir = [.forward, .reverse, .pendulum, .pingpong][rng.int(0...3)]
            l.riffLength = rng.int(1...8); l.riffStride = rng.int(1...3); l.riffRotate = rng.int(0...7)
            l.riffAdvanceEvery = rng.int(1...4); l.riffAdvanceStep = rng.bool(); l.riffOn = true
            l.riffOnRest = [.skip, .tie, .repeatLast][rng.int(0...2)]
            switch rng.int(0...3) { case 1: l.restartMelodyPasses = [1]; case 2: l.restartMelodyPasses = [2]; case 3: l.restartMelodyPasses = [1, 2]; default: break }
            if l.restartMelodyPasses != nil { l.restartRhythmBars = [] }   // FREE rhythm chain: a pass is one lap, so the footers' lap is the engine's pass
            let ranks = (0..<8).map { _ in rng.bool(0.35) ? 0 : rng.int(1...8) }
            guard let cfg = euclideousWalkLaneConfig(lane: 0, lines: [l], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8) else { XCTFail("no cfg"); continue }
            let steps = n
            let hitSteps = euclideousLapHitSteps(pulses: l.pulses, steps: steps, rotate: l.rotate, tilt: l.tiltResolved, patternMiss: false, customHits: l.customHitsResolved(steps), dir: l.directionResolved)
            guard !hitSteps.isEmpty else { continue }
            let cycleLen = euclidCycleLen(l.directionResolved, n: steps)
            // a random later pass of this lane, mid-run
            let lapTickBase = Int64(cycleLen) * Int64(rng.int(3...40))
            let nowBeat = (Double(lapTickBase) + Double(rng.int(0...(cycleLen - 1))) + 0.1) * cfg.sub
            let pass = euclideousFooterPass(line: l, cfg: cfg, hitSteps: hitSteps, lapSteps: steps, liveOrd: 0, nowBeat: nowBeat)
            guard let lapStart = pass.lapStartTick else { XCTFail("trial \(trial): no lap start"); continue }
            XCTAssertEqual(lapStart % Int64(cycleLen), 0, "trial \(trial): the lap starts on a pass boundary")
            var pattern = [Bool](repeating: false, count: steps)
            for hs in hitSteps { pattern[hs.bufIdx] = true }
            var order = EuclideousLitOrder(); for p in [rng.int(0...7), rng.int(0...7), 8].prefix(rng.int(1...3)) { order.append(p) }
            let pool = [48, 50, 51, 53, 55, 56, 58]
            let list = euclideousNotesPlayList(order: order, poolCount: pool.count, receivedOnly: false) { rank in riffResolve(rank: rank, oct: 0, n: pool.count, wrap: .fold, asc: { pool[$0] }) }
            let notes = EuclideousStripNotes(layerOn: true, when: [0b01, 0b10, 0b11][rng.int(0...2)], chance: [25, 50, 100][rng.int(0...2)], way: EuclidNotesPlayAs.allCases[rng.int(0...(EuclidNotesPlayAs.allCases.count - 1))], list: list, lane: 0)
            let pingPong = l.directionResolved == .pingpong
            let legs = euclideousStripLegs(pattern: pattern, hitSteps: hitSteps, prediction: pass.prediction, lapSteps: steps, ranks: ranks, anyLit: true, fxTieColumns: 0, pingPong: pingPong, riffPlays: true, grey: false,
                                           onRest: l.riffOnRestResolved, cfg: cfg, lapStartTick: lapStart, notes: notes, name: { "n\($0)" })
            XCTAssertEqual(legs.count, pingPong ? 2 : 1)
            XCTAssertEqual(legs.reduce(0) { $0 + $1.hitSteps.count }, hitSteps.count, "trial \(trial): every hit of the pass is in exactly one leg")
            for (li, leg) in legs.enumerated() {
                // 1. every hit of the pass: the strip's column and rank are the engine's, whichever sweep it is in
                for (j, hs) in leg.hitSteps.enumerated() {
                    let w = euclideousWalkTick(cfg, tick: lapStart + Int64(hs.tick))
                    XCTAssertTrue(w.isHit, "trial \(trial): the footers' hit is the engine's hit")
                    let col = w.playedStep + 1
                    let written = ranks[w.playedStep]
                    let h = leg.hits[hs.bufIdx]
                    checkedHits += 1; if pingPong { pingPongHits += 1 }
                    XCTAssertEqual(h.column, col, "trial \(trial) leg \(li) hit \(j): column")
                    if written >= 1 {
                        XCTAssertEqual(h.chip, EuclideousStripChip(rank: written, column: col, hollow: false, grey: false), "trial \(trial) leg \(li) hit \(j): chip")
                        XCTAssertEqual(h.kind, .hit)
                    } else if l.riffOnRestResolved == .repeatLast {
                        let rep = euclideousRiffRepeatLookback(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: lapStart + Int64(hs.tick), chains: cfg.chains, legacySpanBeats: cfg.spanBeats,
                                                               advanceStep: cfg.advanceStep, riffDir: cfg.riffDir, stride: cfg.stride, length: cfg.length, rotate: cfg.rotate, seed: cfg.seed, every: cfg.every,
                                                               thisBeat: 0, rankAt: { c, _ in ranks[c] })
                        if let rep { XCTAssertEqual(h.chip, EuclideousStripChip(rank: rep.rank, column: col, hollow: true, grey: false), "trial \(trial) hit \(j): REPEAT"); repeatsChecked += 1 }
                        else { XCTAssertEqual(h.kind, .gap, "trial \(trial) hit \(j): nothing to repeat is a gap"); XCTAssertNil(h.chip) }
                    } else {
                        XCTAssertEqual(h.kind, .gap, "trial \(trial) hit \(j): a rest under SKIP/TIE is a gap"); XCTAssertNil(h.chip); gapsChecked += 1
                    }
                    // 1b. the key: due where WHEN chooses, and the way's pick against a brute-force replay of the hits since the melody origin
                    let t = lapStart + Int64(hs.tick)
                    let isRest = written < 1
                    XCTAssertEqual(h.key?.plays, euclideousNotesWhenChooses(when: notes.when, isRestHit: isRest), "trial \(trial) hit \(j): the key plays when WHEN chooses the hit")
                    if h.key?.plays == true, list.count > 0 {
                        let origin = euclideousLaneChainPhase(buf: cfg.buf, n: cfg.n, dir: cfg.dir, cycleLen: cycleLen, sub: cfg.sub, tick: t, chains: cfg.chains, legacySpanBeats: cfg.spanBeats).originTickM
                        var hOrd = 0, k = 0
                        var tt = origin
                        while tt < t {
                            let e = euclideousWalkTick(cfg, tick: tt)
                            if e.isHit {
                                if euclideousNotesWhenChooses(when: notes.when, isRestHit: ranks[e.playedStep] < 1) && euclideousNotesChanceAllows(chance: notes.chance, lane: 0, h: Int64(hOrd)) { k += 1 }
                                hOrd += 1
                            }
                            tt += 1
                        }
                        if hOrd < 1000 {
                            let want = euclideousNotesWayPick(list: list, way: notes.way, k: euclideousNotesWayUsesCount(notes.way) ? k : 0)
                            XCTAssertEqual(h.key?.picked, (0..<want.count).map { list.pitch(want[$0]) }, "trial \(trial) leg \(li) hit \(j): the way's pick at k = \(k) (\(notes.way), h \(hOrd))")
                            labelsChecked += 1
                        }
                    }
                    // 2. the current chip, with the arrow landed on this hit, is the arrow's chip
                    let beat = (Double(t) + 0.1) * cfg.sub
                    guard let plan = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: beat, secondsPerBeat: 0.5, polledStep: w.playedStep, running: true, polledOrdinal: w.advOrd), plan.landedTick == t else { continue }
                    let arrow = euclideousLaneArrowState(lane: 0, cfg: cfg, plan: plan, polledOrdinal: w.advOrd)
                    let cur = euclideousStripCurrentStep(cfg: cfg, landedTick: plan.landedTick, passLapStartTick: lapStart, arrowStaysOnTiedNote: plan.seatIsRest && !arrow.hollow, legs: legs)
                    if let cur {
                        checkedCurrent += 1
                        let chip = legs[cur.leg].hits[cur.step].chip
                        XCTAssertEqual(chip.map { $0.column - 1 }, arrow.column, "trial \(trial) leg \(li) hit \(j): the current chip is in the arrow's column")
                        XCTAssertEqual(chip?.rank, arrow.rank, "trial \(trial) leg \(li) hit \(j): …and row")
                        XCTAssertFalse(arrow.hollow, "trial \(trial) hit \(j): a hollow arrow has no filled current chip")
                        if !plan.seatIsRest { XCTAssertEqual(cur.leg, li, "trial \(trial) hit \(j): a played hit's chip is in its own sweep") }
                    } else if !arrow.hollow {
                        XCTAssertTrue(plan.seatIsRest, "trial \(trial) leg \(li) hit \(j): a solid arrow on a played hit must have a current chip (col \(arrow.column + 1) rank \(arrow.rank), onRest \(l.riffOnRestResolved))")
                    }
                }
            }
        }
        print("LANE STRIP fuzz: \(checkedHits) hits (\(pingPongHits) PING-PONG), \(checkedCurrent) current chips, \(repeatsChecked) REPEAT hits, \(gapsChecked) gaps, \(labelsChecked) key picks checked")
        XCTAssertGreaterThan(checkedHits, 1000); XCTAssertGreaterThan(checkedCurrent, 300); XCTAssertGreaterThan(pingPongHits, 300)
    }
}
