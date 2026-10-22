//  LaneStripTests.swift
//  LANE STRIP ferry (2026-10-21, "a riff contour over a row of notes keys, in place of the comet"): the pure surface — the strip's layout, the per-hit plan (chips, gaps, keys), the current chip, the
//  playhead, the strikes, the looks and the VoiceOver words (§1-§7, tests §9.1-§9.9), plus the footer-prediction fix (ADVANCE EVERY) the chips depend on. The drawing itself (`LaneStripPainter.swift`)
//  has no macOS test reach; it is device-owed.
//
//  The example lane (the notes ferry's §13): riff ranks by column [8, 0, 8, 6, 0, 6, 5, 0] (0 = a rest), SHIFT 5, ADV STEP, hits on steps 1, 3, 5, 6, 8 — which read columns 6, 8, 2, 3, 5 in the pass
//  that starts on a multiple of 8 ticks. So the hits on 1 and 6 play the riff (A♭3 at rank 6, C4 at rank 8) and the hits on 3, 5, 8 are riff rests. KEY C MINOR pool: C3 D3 E♭3 F3 G3 A♭3 B♭3 +
//  the octave copy C4 (rank 8). Lit in this order: rank 8, 5, 6 (C4, G3, A♭3).

import XCTest

final class LaneStripTests: XCTestCase {

    // MARK: fixture

    private let exBuf = [true, false, true, false, true, true, false, true]
    private let exRanks = [8, 0, 8, 6, 0, 6, 5, 0]
    private let exPool = [48, 50, 51, 53, 55, 56, 58]
    private let lapStart: Int64 = 800   // a multiple of 8 ticks: the pass starts on the pattern's first step

    private func exLine(onRest: EuclidRiffOnRest = .skip, every: Int = 1, advanceStep: Bool = true, riffOn: Bool = true) -> EuclidLine {
        var l = EuclidLine(target: 0, pulses: 5, steps: 8, rate: .r1_16, useRiff: true, sourceMode: .midi)
        l.customHits = exBuf; l.riffRotate = 5; l.riffAdvanceStep = advanceStep; l.riffOnRest = onRest; l.riffAdvanceEvery = every; l.riffOn = riffOn
        return l
    }
    private struct Fix {
        var line: EuclidLine
        var cfg: EuclideousWalkLaneConfig
        var hitSteps: [EuclidHitStep]
        var pass: EuclideousFooterPass
    }
    private func fix(_ line: EuclidLine) -> Fix {
        let cfg = euclideousWalkLaneConfig(lane: 0, lines: [line], cyc: 4, resetSpanBars: 0, lanesSeqRate: .oneBar, lanesSeqLen: 8)!
        let hitSteps = euclideousLapHitSteps(pulses: line.pulses, steps: 8, rotate: line.rotate, tilt: line.tiltResolved, patternMiss: false, customHits: exBuf, dir: line.directionResolved)
        let pass = euclideousFooterPass(line: line, cfg: cfg, hitSteps: hitSteps, lapSteps: 8, liveOrd: 0, nowBeat: Double(lapStart) * cfg.sub + 0.01)
        return Fix(line: line, cfg: cfg, hitSteps: hitSteps, pass: pass)
    }
    private func states(_ f: Fix, riffRead: Bool = true, anyLit: Bool = true) -> [EuclidFooterState] {
        euclideousFooterStates(hitSteps: f.hitSteps, lapSteps: 8, prediction: riffRead ? f.pass.prediction : nil, riffRanksResolved: exRanks, anyLit: anyLit)
    }
    private func list(_ order: [Int], received: Bool = false) -> EuclideousNotesList {
        var o = EuclideousLitOrder(); for p in order { o.append(p) }
        return euclideousNotesPlayList(order: o, poolCount: exPool.count, receivedOnly: received) { rank in
            riffResolve(rank: rank, oct: 0, n: exPool.count, wrap: .fold, asc: { exPool[$0] })
        }
    }
    private func name(_ p: Int) -> String { ["C", "D♭", "D", "E♭", "E", "F", "G♭", "G", "A♭", "A", "B♭", "B"][p % 12] + "\(p / 12 - 1)" }
    private func notes(_ way: EuclidNotesPlayAs, when: UInt8 = 0b10, chance: Int = 100, on: Bool = true) -> EuclideousStripNotes {
        EuclideousStripNotes(layerOn: on, when: when, chance: chance, way: way, list: list([7, 4, 5]), lane: 0)
    }
    private func hits(_ f: Fix, riffPlays: Bool = true, grey: Bool = false, readRiff: Bool = true, notes n: EuclideousStripNotes? = nil, keyLabels: Bool = true) -> [EuclideousStripHit] {
        euclideousStripHits(pattern: exBuf, hitSteps: f.hitSteps, states: states(f, riffRead: readRiff), ranks: exRanks, riffPlays: riffPlays, grey: grey, onRest: f.line.riffOnRestResolved,
                            cfg: f.cfg, lapStartTick: f.pass.lapStartTick, notes: n, keyLabels: keyLabels, name: name)
    }

    // MARK: 1. chip heights and the layout

    func testChipHeightsFollowTheRank() {
        XCTAssertEqual(euclideousStripChipTop(rank: 8), 0, accuracy: 0.01)
        XCTAssertEqual(euclideousStripChipTop(rank: 1), 14, accuracy: 0.01)
        XCTAssertEqual(euclideousStripChipTop(rank: 6), 4, accuracy: 0.01)
        // LANE STRIP readability ferry: a 9-tall chip at rank 1 now ends at 23 — 1 pt clear of the floor
        // bar at y 24..26 (it used to end flush with the track's 27, before the floor bar existed); a
        // column's chip is inset 2 each side
        let col = CGRect(x: 10, y: 0, width: 25.63, height: 27)
        let chip = euclideousStripChipFrame(column: col, rank: 1)
        XCTAssertEqual(chip.maxY, 23, accuracy: 0.01); XCTAssertEqual(chip.minX, 12); XCTAssertEqual(chip.width, 21.63, accuracy: 0.001); XCTAssertEqual(chip.height, 9)
    }
    func testTheLayoutIsATwentySevenPointTrackOverAFourteenPointKeyRowThreePointsApart() {
        let xs: [CGFloat] = [0, 27.6, 55.2]
        let l = euclideousStripLayout(xs: xs, columnW: 25.63)
        XCTAssertEqual(l.count, 3)
        for (i, f) in l.enumerated() {
            XCTAssertEqual(f.column, CGRect(x: xs[i], y: 0, width: 25.63, height: 27)); XCTAssertEqual(f.key, CGRect(x: xs[i], y: 30, width: 25.63, height: 14))
            XCTAssertEqual(f.key.maxY, 44, "the strip stays the header row's 44")
        }
    }

    // MARK: 1b. LANE STRIP readability ferry — the floor bar, the draws-as-hit rule, and chip clearance

    func testFloorBarFrameInsetsOrGoesFullWidthWhenNarrow() {
        let wide = euclideousStripFloorBarFrame(column: CGRect(x: 10, y: 0, width: 13, height: 27))
        XCTAssertEqual(wide.minX, 12); XCTAssertEqual(wide.width, 9); XCTAssertEqual(wide.minY, 24); XCTAssertEqual(wide.height, 2)
        let narrow = euclideousStripFloorBarFrame(column: CGRect(x: 10, y: 0, width: 5, height: 27))
        XCTAssertEqual(narrow.minX, 10, "under the 6pt floor, the bar goes full width instead of insetting"); XCTAssertEqual(narrow.width, 5)
    }
    func testDrawsAsHitCoversHitAndGapNotRhythmRest() {
        XCTAssertTrue(euclideousStripDrawsAsHit(.hit)); XCTAssertTrue(euclideousStripDrawsAsHit(.gap)); XCTAssertFalse(euclideousStripDrawsAsHit(.rhythmRest))
    }
    func testEveryChipClearsTheFloorBar() {
        for r in 1...8 {
            let bottom = euclideousStripChipTop(rank: r) + EuclideousStripMetrics.chipH
            XCTAssertLessThanOrEqual(bottom, 23, "rank \(r) chip must clear the floor bar's own 24-26 band")
        }
    }

    // MARK: 2. the example lane's chips, gaps and rests

    func testTheExampleLanesChipsAndGapsInPassZero() {
        let f = fix(exLine())
        XCTAssertEqual(f.pass.prediction, [6, 8, 2, 3, 5], "the pass the footers show: the hits read columns 6, 8, 2, 3 and 5")
        let h = hits(f)
        XCTAssertEqual(h[0].chip, EuclideousStripChip(rank: 6, column: 6, hollow: false, grey: false), "step 1: a chip labelled 6 at rank 6's height (A♭3)")
        XCTAssertEqual(euclideousStripChipTop(rank: h[0].chip!.rank), 4, accuracy: 0.01)
        XCTAssertEqual(h[5].chip, EuclideousStripChip(rank: 8, column: 3, hollow: false, grey: false), "step 6: a chip labelled 3 at the top (C4)")
        XCTAssertEqual(euclideousStripChipTop(rank: h[5].chip!.rank), 0)
        for i in [2, 4, 7] { XCTAssertEqual(h[i].kind, .gap, "step \(i + 1) is a riff rest under SKIP: a gap"); XCTAssertNil(h[i].chip) }
        for i in [1, 3, 6] { XCTAssertEqual(h[i].kind, .rhythmRest, "step \(i + 1) is a dashed rhythm rest"); XCTAssertNil(h[i].chip); XCTAssertNil(h[i].key, "a rhythm rest has no key") }
        for i in [0, 5] { XCTAssertEqual(h[i].kind, .hit) }
        // LANE STRIP readability ferry §8 test 4: steps 1,3,5,6,8 (hit or gap) all draw lane-coloured with
        // a floor bar; steps 2,4,7 (rhythm rests) are the quiet dotted cells with none.
        for i in [0, 2, 4, 5, 7] { XCTAssertTrue(euclideousStripDrawsAsHit(h[i].kind), "step \(i + 1) draws as a lane-coloured hit column") }
        for i in [1, 3, 6] { XCTAssertFalse(euclideousStripDrawsAsHit(h[i].kind), "step \(i + 1) is a quiet rhythm rest") }
    }
    func testTheChipsReadTheWrittenRankNotTheSoundingOne() {
        // INV and TRANS change the sounding rank (the LANES roll draws that one); the arrow, and so the chip, keep the WRITTEN row
        var l = exLine(); l.riffInvert = true; l.melodyTranspose = 2
        let h = hits(fix(l))
        XCTAssertEqual(h[0].chip?.rank, 6); XCTAssertEqual(h[5].chip?.rank, 8)
    }

    // MARK: 3. the key row on that lane (C4, G3 and A♭3 lit in that order, WHEN RESTS)

    func testKeysUnderCycleChordPlaysOnlyChanceAndNotesOff() {
        let f = fix(exLine())
        // CYCLE: steps 3, 5 and 8 play C4, G3 and A♭3 in turn; steps 1 and 6 are unlit keys
        let cycle = hits(f, notes: notes(.cycle))
        XCTAssertEqual([2, 4, 7].map { cycle[$0].key?.label }, ["C4", "G3", "A♭3"])
        XCTAssertEqual([2, 4, 7].map { cycle[$0].key?.plays }, [true, true, true]); XCTAssertEqual([0, 5].map { cycle[$0].key?.plays }, [false, false])
        XCTAssertEqual([0, 5].map { cycle[$0].key?.label }, [nil, nil], "an unlit key has no label")
        // CHORD: every playing key reads the lowest note and how many more
        let chord = hits(f, notes: notes(.chord))
        XCTAssertEqual([2, 4, 7].map { chord[$0].key?.label }, ["G3+2", "G3+2", "G3+2"])
        // PLAYS only: steps 1 and 6 play, 3, 5 and 8 are unlit
        let plays = hits(f, notes: notes(.chord, when: 0b01))
        XCTAssertEqual([0, 5].map { plays[$0].key?.plays }, [true, true]); XCTAssertEqual([2, 4, 7].map { plays[$0].key?.plays }, [false, false, false])
        // CHANCE 50: the bars become rings — and the label is still there
        let half = hits(f, notes: notes(.cycle, chance: 50))
        XCTAssertEqual([2, 4, 7].map { half[$0].key?.chanceRing }, [true, true, true]); XCTAssertEqual(half[2].key?.label, "C4")
        XCTAssertEqual([0, 5].map { half[$0].key?.chanceRing }, [false, false], "an unlit key has no ring")
        let full = hits(f, notes: notes(.cycle, chance: 100)); XCTAssertEqual([2, 4, 7].map { full[$0].key?.chanceRing }, [false, false, false])
        // the notes off: every key is unlit
        for off in [hits(f, notes: notes(.cycle, on: false)), hits(f, notes: nil)] {
            XCTAssertEqual([0, 2, 4, 5, 7].map { off[$0].key?.plays }, [false, false, false, false, false])
        }
        // keys too narrow for a label skip the work, the bar stays
        let narrow = hits(f, notes: notes(.cycle), keyLabels: false)
        XCTAssertEqual([2, 4, 7].map { narrow[$0].key?.plays }, [true, true, true]); XCTAssertEqual([2, 4, 7].map { narrow[$0].key?.label }, [nil, nil, nil])
    }
    func testAnEmptyPlayListHasNoLabelAndAnFXTiedHitStrikesNothing() {
        let f = fix(exLine())
        var empty = notes(.cycle); empty.list = EuclideousNotesList()
        let h = hits(f, notes: empty)
        XCTAssertEqual(h[2].key?.plays, true); XCTAssertNil(h[2].key?.label, "nothing to name")
        let tied = euclideousStripHits(pattern: [true], hitSteps: [EuclidHitStep(tick: 0, bufIdx: 0)], states: [.hitTied(riffStep: 3)], ranks: exRanks, riffPlays: true, grey: false, onRest: .skip,
                                       cfg: nil, lapStartTick: nil, notes: notes(.chord, when: 0b11), name: name)
        XCTAssertEqual(tied[0].key?.plays, false, "an FX-tied hit strikes nothing")
        XCTAssertEqual(tied[0].chip?.rank, 8, "…but it reads a note, so it keeps a normal chip")
    }

    // MARK: 4. the riff off

    func testRiffOffGreyChipsOnlyWhenWhenIsOneSided() {
        let f = fix(exLine(riffOn: false))
        // WHEN RESTS only: the footers show as they would with the riff on, grey — chips on the hits that read a note (steps 1 and 6), none on the rest hits
        let grey = hits(f, riffPlays: false, grey: true, notes: notes(.cycle))
        XCTAssertEqual(grey[0].chip, EuclideousStripChip(rank: 6, column: 6, hollow: false, grey: true)); XCTAssertEqual(grey[5].chip, EuclideousStripChip(rank: 8, column: 3, hollow: false, grey: true))
        for i in [2, 4, 7] { XCTAssertNil(grey[i].chip); XCTAssertEqual(grey[i].kind, .hit, "with the riff off a rest hit is a plain hit, not a gap") }
        XCTAssertEqual([2, 4, 7].map { grey[$0].key?.plays }, [true, true, true], "the keys still show where the notes play")
        // LANE STRIP readability ferry §8 test 5: the same five hit columns still draw as hit columns with the riff off.
        for i in [0, 2, 4, 5, 7] { XCTAssertTrue(euclideousStripDrawsAsHit(grey[i].kind)) }
        // both on: no chips at all (the footers read nothing)
        let both = hits(f, riffPlays: false, grey: false, readRiff: false, notes: notes(.cycle, when: 0b11))
        for i in [0, 2, 4, 5, 7] { XCTAssertNil(both[i].chip); XCTAssertEqual(both[i].kind, .hit) }
        XCTAssertEqual([0, 2, 4, 5, 7].map { both[$0].key?.plays }, [true, true, true, true, true])
        // riff on but SHADOWED (riffPlays false, nothing grey): no chips, no gaps
        let shadow = hits(f, riffPlays: false, grey: false)
        for i in [0, 2, 4, 5, 7] { XCTAssertNil(shadow[i].chip); XCTAssertEqual(shadow[i].kind, .hit) }
    }

    // MARK: 5. REPEAT

    func testRepeatDrawsAHollowChipAtTheRepeatedRanksHeight() {
        let f = fix(exLine(onRest: .repeatLast))
        let h = hits(f)
        XCTAssertEqual(h[2].chip, EuclideousStripChip(rank: 6, column: 8, hollow: true, grey: false), "step 3 (rest column 8) repeats the note before it: A♭3 at rank 6, labelled with its own column")
        XCTAssertEqual(h[4].chip, EuclideousStripChip(rank: 6, column: 2, hollow: true, grey: false), "step 5 repeats the same A♭3 (step 3 was itself a rest)")
        XCTAssertEqual(h[7].chip, EuclideousStripChip(rank: 8, column: 5, hollow: true, grey: false), "step 8 repeats the C4 from step 6")
        for i in [2, 4, 7] { XCTAssertEqual(h[i].kind, .hit, "REPEAT strikes: not a gap") }
        // a riff with no note anywhere finds nothing: REPEAT plays as SKIP, so the hit is a gap
        let silent = euclideousStripHits(pattern: exBuf, hitSteps: f.hitSteps, states: states(f), ranks: [Int](repeating: 0, count: 8), riffPlays: true, grey: false, onRest: .repeatLast,
                                         cfg: f.cfg, lapStartTick: f.pass.lapStartTick, notes: nil, name: name)
        XCTAssertEqual(silent[2].kind, .gap, "…and a hit on a rest that REPEAT cannot fill reads as a gap")
    }

    // MARK: 6. the current chip follows the arrow, TIE included

    /// The pass's hits one by one: the arrow's plan at a moment just after the hit on lap tick `t` landed, then the strip's current chip for it.
    private func current(_ f: Fix, hits h: [EuclideousStripHit], afterHitAt t: Int) -> (step: Int?, arrow: EuclideousLaneArrowState) {
        let abs = lapStart + Int64(t)
        let w = euclideousWalkTick(f.cfg, tick: abs)
        let beat = (Double(abs) + 0.1) * f.cfg.sub
        let plan = euclideousWalkTagPlan(cfg: f.cfg, ranks: exRanks, beat: beat, secondsPerBeat: 0.5, polledStep: w.playedStep, running: true, polledOrdinal: w.advOrd)!
        XCTAssertEqual(plan.landedTick, abs, "the arrow's plan landed on this hit")
        let arrow = euclideousLaneArrowState(lane: 0, cfg: f.cfg, plan: plan, polledOrdinal: w.advOrd)
        let stays = plan.seatIsRest && !arrow.hollow
        return (euclideousStripCurrentStep(cfg: f.cfg, landedTick: plan.landedTick, passLapStartTick: f.pass.lapStartTick, arrowStaysOnTiedNote: stays, legs: [EuclideousStripLeg(hitSteps: f.hitSteps, hits: h)])?.step, arrow)
    }
    func testTheCurrentChipIsTheHitTheArrowShowsAndSkipLeavesNoneOnARest() {
        let f = fix(exLine())
        let h = hits(f)
        let ticks = f.hitSteps.map { $0.tick }   // 0, 2, 4, 5, 7
        let want: [Int?] = [0, nil, nil, 5, nil]   // the hits on steps 1 and 6 carry the current chip; a SKIP rest's arrow is hollow on a gap, which has no chip
        for (j, t) in ticks.enumerated() {
            let c = current(f, hits: h, afterHitAt: t)
            XCTAssertEqual(c.step, want[j], "after the hit on step \(t + 1)")
            if let s = c.step, let chip = h[s].chip { XCTAssertEqual(chip.column - 1, c.arrow.column, "the chip's column is the arrow's"); XCTAssertEqual(chip.rank, c.arrow.rank, "…and its row") }
        }
    }
    func testTieKeepsTheCurrentChipOnTheHeldNote() {
        let f = fix(exLine(onRest: .tie))
        let h = hits(f)
        let want: [Int?] = [0, 0, 0, 5, 5]   // steps 3 and 5 are tied rests after the A♭3 on step 1, step 8 a tied rest after the C4 on step 6
        for (j, t) in f.hitSteps.map({ $0.tick }).enumerated() {
            let c = current(f, hits: h, afterHitAt: t)
            XCTAssertEqual(c.step, want[j], "after the hit on step \(t + 1)")
            if let s = c.step, let chip = h[s].chip { XCTAssertEqual(chip.column - 1, c.arrow.column, "the chip stays where the arrow stays"); XCTAssertEqual(chip.rank, c.arrow.rank) }
        }
    }
    func testNoCurrentChipBeforeTheFirstHitOfThePassOrWhenTheLandedHitIsInAnotherPass() {
        let f = fix(exLine(onRest: .tie))
        let h = hits(f)
        XCTAssertNil(euclideousStripCurrentStep(cfg: f.cfg, landedTick: nil, passLapStartTick: f.pass.lapStartTick, arrowStaysOnTiedNote: false, legs: [EuclideousStripLeg(hitSteps: f.hitSteps, hits: h)]), "nothing has landed (stopped, or before the first hit)")
        XCTAssertNil(euclideousStripCurrentStep(cfg: f.cfg, landedTick: lapStart - 1, passLapStartTick: f.pass.lapStartTick, arrowStaysOnTiedNote: true, legs: [EuclideousStripLeg(hitSteps: f.hitSteps, hits: h)]),
                     "the landed hit belongs to the pass before the one the footers show")
    }
    func testATiedRestAtTheStartOfThePassHasNoChipToHold() {
        // SHIFT 7: the pass's hits read columns 8, 2, 4, 5, 7 — the first two are riff rests, so under TIE the held note lives in the pass before
        var l = exLine(onRest: .tie); l.riffRotate = 7
        let f = fix(l)
        XCTAssertEqual(f.pass.prediction, [8, 2, 4, 5, 7])
        let h = hits(f)
        func cur(_ t: Int) -> Int? { euclideousStripCurrentStep(cfg: f.cfg, landedTick: lapStart + Int64(t), passLapStartTick: f.pass.lapStartTick, arrowStaysOnTiedNote: true, legs: [EuclideousStripLeg(hitSteps: f.hitSteps, hits: h)])?.step }
        XCTAssertNil(cur(0)); XCTAssertNil(cur(2))
        XCTAssertEqual(cur(4), 4, "the third hit reads column 4: a chip of its own")
        XCTAssertEqual(cur(5), 4, "…and the tied rest after it holds that chip")
        XCTAssertEqual(cur(7), 7)
    }

    // MARK: PING-PONG — each step is visited twice, with different notes
    func testPingPongHasASweepPerVisitAndTheCurrentChipFollowsTheSweepItIsOn() {
        var l = exLine(); l.direction = .pingpong
        let f = fix(l)
        // the pass is 2n = 16 ticks: up the steps (ticks 0…7) then back down (8…15, step 15 − tick)
        XCTAssertEqual(f.hitSteps.map { $0.tick }, [0, 2, 4, 5, 7, 8, 10, 11, 13, 15]); XCTAssertEqual(f.hitSteps.map { $0.bufIdx }, [0, 2, 4, 5, 7, 7, 5, 4, 2, 0])
        let legs = euclideousStripLegs(pattern: exBuf, hitSteps: f.hitSteps, prediction: f.pass.prediction, lapSteps: 8, ranks: exRanks, anyLit: true, fxTieColumns: 0, pingPong: true, riffPlays: true, grey: false,
                                       onRest: .skip, cfg: f.cfg, lapStartTick: f.pass.lapStartTick, notes: notes(.cycle), name: name)
        XCTAssertEqual(legs.count, 2); XCTAssertEqual(legs[0].hitSteps.count, 5); XCTAssertEqual(legs[1].hitSteps.count, 5)
        // step 1 is read twice: the walk is at tick 800 going up and tick 815 coming back, two different columns of the riff
        XCTAssertEqual(legs[0].hits[0].column, 6); XCTAssertEqual(legs[1].hits[0].column, 5, "the way back reads another column: the old single-chip strip showed this one on the way up too")
        XCTAssertEqual(legs[0].hits[0].chip?.rank, 6); XCTAssertNil(legs[1].hits[0].chip, "column 5 is a riff rest: a gap on the way back")
        XCTAssertEqual(legs[1].hits[0].kind, .gap); XCTAssertEqual(legs[0].hits[0].kind, .hit)
        XCTAssertEqual(euclideousStripLegIndex(raw: 7.99, n: 8, legCount: 2), 0); XCTAssertEqual(euclideousStripLegIndex(raw: 8.0, n: 8, legCount: 2), 1); XCTAssertEqual(euclideousStripLegIndex(raw: 12, n: 8, legCount: 1), 0)
        // the current chip lives in the sweep the landed hit is in
        func cur(_ t: Int, tie: Bool = false) -> EuclideousStripCurrent? { euclideousStripCurrentStep(cfg: f.cfg, landedTick: lapStart + Int64(t), passLapStartTick: f.pass.lapStartTick, arrowStaysOnTiedNote: tie, legs: legs) }
        XCTAssertEqual(cur(0), EuclideousStripCurrent(leg: 0, step: 0))
        XCTAssertNil(cur(15), "the way back lands on a gap at step 1")
        XCTAssertEqual(cur(8), EuclideousStripCurrent(leg: 1, step: 7), "the first hit of the way back reads column 6 (rank 6) at step 8")
        XCTAssertNil(cur(10), "the next hit reads column 8, a rest: a gap")
        XCTAssertEqual(cur(10, tie: true), EuclideousStripCurrent(leg: 1, step: 7), "…and under TIE the current chip stays on the note it holds, in its own sweep")
    }

    // MARK: 7. the playhead

    func testThePlayheadCoversTheColumnAtAnOnsetAndGlidesToTheNext() {
        // 8 steps in two groups of four: 2 pt inside a group, 7 between
        let g = euclidGroupedBoxGeometry(n: 8, g: 4, usableWidth: 226)
        let w = g.stepW
        let atOnset = euclideousStripPlayhead(raw: 2, n: 8, dir: .fwd, xs: g.xs, columnW: w)   // step 3's onset
        XCTAssertEqual(atOnset.x, g.xs[2], accuracy: 1e-9); XCTAssertEqual(atOnset.width, w, accuracy: 1e-9); XCTAssertTrue(atOnset.movingRight)
        let half = euclideousStripPlayhead(raw: 2.5, n: 8, dir: .fwd, xs: g.xs, columnW: w)
        XCTAssertEqual(half.x, (g.xs[2] + g.xs[3]) / 2, accuracy: 1e-9, "halfway through step 3 the left edge is midway between steps 3 and 4")
        let overTheGap = euclideousStripPlayhead(raw: 3.5, n: 8, dir: .fwd, xs: g.xs, columnW: w)   // step 4 -> step 5 crosses the 7 pt group gap
        XCTAssertEqual(overTheGap.x, (g.xs[3] + g.xs[4]) / 2, accuracy: 1e-9)
        XCTAssertGreaterThan(g.xs[4] - g.xs[3], g.xs[3] - g.xs[2], "the gap between groups is wider, and the band glides across it")
    }
    func testThePlayheadSlidesOffTheEndAndStartsTheNextPassOnTheFirstColumn() {
        let g = euclidGroupedBoxGeometry(n: 8, g: 4, usableWidth: 226)
        let last = euclideousStripPlayhead(raw: 7, n: 8, dir: .fwd, xs: g.xs, columnW: g.stepW)
        XCTAssertEqual(last.x, g.xs[7], accuracy: 1e-9)
        let off = euclideousStripPlayhead(raw: 7.999, n: 8, dir: .fwd, xs: g.xs, columnW: g.stepW)
        XCTAssertGreaterThanOrEqual(off.x, g.xs[7] + g.stepW, "after the last step the band is past the end (the painter clips it)")
        let next = euclideousStripPlayhead(raw: 8.0, n: 8, dir: .fwd, xs: g.xs, columnW: g.stepW)
        XCTAssertEqual(next.x, g.xs[0], accuracy: 1e-9, "the next pass starts on the first column")
        // BKW reads the last column first and slides off the LEFT end
        let bkw0 = euclideousStripPlayhead(raw: 0, n: 8, dir: .bkw, xs: g.xs, columnW: g.stepW)
        XCTAssertEqual(bkw0.x, g.xs[7], accuracy: 1e-9); XCTAssertFalse(bkw0.movingRight)
        let bkwHalf = euclideousStripPlayhead(raw: 0.5, n: 8, dir: .bkw, xs: g.xs, columnW: g.stepW)
        XCTAssertEqual(bkwHalf.x, (g.xs[7] + g.xs[6]) / 2, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(euclideousStripPlayhead(raw: 7.999, n: 8, dir: .bkw, xs: g.xs, columnW: g.stepW).x, g.xs[0] - g.stepW)
        // PING-PONG repeats each end step: the band rests there for a step, and turns round
        let pingEnd = euclideousStripPlayhead(raw: 7.5, n: 8, dir: .pingpong, xs: g.xs, columnW: g.stepW)
        XCTAssertEqual(pingEnd.x, g.xs[7], accuracy: 1e-9); XCTAssertTrue(pingEnd.movingRight)
        let pingBack = euclideousStripPlayhead(raw: 8.5, n: 8, dir: .pingpong, xs: g.xs, columnW: g.stepW)
        XCTAssertEqual(pingBack.x, (g.xs[7] + g.xs[6]) / 2, accuracy: 1e-9, "after resting on the repeated end step it heads back"); XCTAssertFalse(pingBack.movingRight)
        XCTAssertEqual(euclideousStripPlayhead(raw: 9, n: 8, dir: .pingpong, xs: g.xs, columnW: g.stepW).x, g.xs[6], accuracy: 1e-9)
        XCTAssertEqual(euclideousStripPlayhead(raw: 15.5, n: 8, dir: .pingpong, xs: g.xs, columnW: g.stepW).x, g.xs[0], accuracy: 1e-9, "the first column's repeat at the wrap is a rest too")
        XCTAssertEqual(euclideousStripPlayhead(raw: 16, n: 8, dir: .pingpong, xs: g.xs, columnW: g.stepW).x, g.xs[0], accuracy: 1e-9, "wraps after 2n")
    }

    // MARK: 8. label floors

    func testLabelFloors() {
        XCTAssertFalse(euclideousStripShowsChipLabel(columnWidth: 11)); XCTAssertTrue(euclideousStripShowsChipLabel(columnWidth: 12)); XCTAssertTrue(euclideousStripShowsChipLabel(columnWidth: 12.25))
        XCTAssertFalse(euclideousStripShowsKeyLabel(keyWidth: 15)); XCTAssertTrue(euclideousStripShowsKeyLabel(keyWidth: 16)); XCTAssertTrue(euclideousStripShowsKeyLabel(keyWidth: 16.08))
        XCTAssertNil(euclideousStripKeyLabel(pitches: [], name: name)); XCTAssertEqual(euclideousStripKeyLabel(pitches: [60], name: name), "C4"); XCTAssertEqual(euclideousStripKeyLabel(pitches: [60, 55], name: name), "G3+1")
    }

    // MARK: 9. muting and the strikes

    func testAMutedLanesStripDimsTo42PercentAndMakesNoStrikes() {
        XCTAssertEqual(euclideousStripMuteLook(muted: true).opacity, 0.42); XCTAssertFalse(euclideousStripMuteLook(muted: true).strikes)
        XCTAssertEqual(euclideousStripMuteLook(muted: false).opacity, 1); XCTAssertTrue(euclideousStripMuteLook(muted: false).strikes)
    }
    func testStrikesSplitByLayerAndMapToTheirStepsLooks() {
        var s = EuclideousPulseStrike(onsetBeat: 1, onsetAt: 100, riffVel: 100, notesVel: 0); s.tile = 0
        var t = EuclideousPulseStrike(onsetBeat: 2, onsetAt: 101, riffVel: 0, notesVel: 70); t.tile = 2
        var u = EuclideousPulseStrike(onsetBeat: 3, onsetAt: 102, riffVel: 90, notesVel: 80); u.tile = 5
        var later = EuclideousPulseStrike(onsetBeat: 4, onsetAt: 200, riffVel: 60, notesVel: 60); later.tile = 7   // not happened yet at now = 102.1
        let (riff, nts) = euclideousStripTileStrikes([s, t, u, later], tiles: 8, now: 102.1)
        XCTAssertEqual(riff[0]?.velocity, 100); XCTAssertNil(riff[2]); XCTAssertEqual(riff[5]?.velocity, 90); XCTAssertNil(riff[7])
        XCTAssertNil(nts[0]); XCTAssertEqual(nts[2]?.velocity, 70); XCTAssertEqual(nts[5]?.velocity, 80); XCTAssertNil(nts[7])
        XCTAssertEqual(riff[0]!.seconds, 2.1, accuracy: 1e-9)
    }
    func testChipAndKeyLooksFollowTheEnvelopeAndHonourPulseOffAndReduceMotion() {
        let env = euclideousPulseEnvelopes(velocity: 127, seconds: 0, scale: 1)
        let full = euclideousStripChipLook(env, scale: 1, reduceMotion: false)
        XCTAssertEqual(full.dip, 2 * CGFloat(env.k), accuracy: 1e-9); XCTAssertEqual(full.glowBlur, CGFloat(10 * env.f), accuracy: 1e-9); XCTAssertEqual(full.glowAlpha, env.f, accuracy: 1e-9)
        let still = euclideousStripChipLook(env, scale: 1, reduceMotion: true)
        XCTAssertEqual(still.dip, 0, "Reduce Motion: no dip"); XCTAssertEqual(still.glowBlur, full.glowBlur, "…the glow stays")
        let off = euclideousStripChipLook(euclideousPulseEnvelopes(velocity: 127, seconds: 0, scale: 0), scale: 0, reduceMotion: false)
        XCTAssertEqual(off, EuclideousStripChipLook(dip: 0, glowBlur: 0, glowAlpha: 0), "PULSE OFF: no dip or glow")
        let key = euclideousStripKeyLook(env, scale: 1, reduceMotion: false)
        XCTAssertEqual(key.ringAlpha, env.f, accuracy: 1e-9); XCTAssertEqual(key.glowAlpha, 0.45 * env.f, accuracy: 1e-9); XCTAssertTrue(key.labelLit)
        XCTAssertFalse(euclideousStripKeyLook(euclideousPulseEnvelopes(velocity: 127, seconds: 0.4, scale: 1), scale: 1, reduceMotion: false).labelLit, "the label returns to its ink once f falls under 0.25")
        XCTAssertGreaterThan(euclideousStripKeyLook(euclideousPulseEnvelopes(velocity: 127, seconds: 0.05, scale: 1), scale: 1, reduceMotion: false).ringAlpha,
                             euclideousStripKeyLook(euclideousPulseEnvelopes(velocity: 40, seconds: 0.05, scale: 1), scale: 1, reduceMotion: false).ringAlpha, "loud hits glow harder than soft ones")
        XCTAssertEqual(euclideousStripKeyLook(env, scale: 1, reduceMotion: true).ringAlpha, key.ringAlpha, "Reduce Motion keeps the key glow")
    }

    // MARK: VoiceOver

    func testTheVoiceOverValueReadsEachHitThenWherePlayingThenMuted() {
        let f = fix(exLine())
        let h = hits(f, notes: notes(.cycle))
        func spokenRank(_ r: Int) -> String? { r == 6 ? "A flat 3" : (r == 8 ? "C 4" : nil) }
        func spokenPitch(_ p: Int) -> String { p == 60 ? "C 4" : (p == 55 ? "G 3" : "A flat 3") }
        let v = euclideousStripAccessibilityValue(hits: h, spokenRank: spokenRank, spokenPitch: spokenPitch, onStep: nil, muted: false)
        XCTAssertEqual(v, "step 1, riff column 6, A flat 3; step 3, rest in the riff, notes play C 4; step 5, rest in the riff, notes play G 3; step 6, riff column 3, C 4; step 8, rest in the riff, notes play A flat 3")
        XCTAssertTrue(euclideousStripAccessibilityValue(hits: h, spokenRank: spokenRank, spokenPitch: spokenPitch, onStep: 5, muted: false).hasSuffix("; on step 5"))
        let muted = euclideousStripAccessibilityValue(hits: h, spokenRank: spokenRank, spokenPitch: spokenPitch, onStep: 5, muted: true)
        XCTAssertTrue(muted.hasSuffix("; on step 5, silent at this step"))
        let chord = euclideousStripAccessibilityValue(hits: hits(f, notes: notes(.chord)), spokenRank: spokenRank, spokenPitch: spokenPitch, onStep: nil, muted: false)
        XCTAssertTrue(chord.contains("step 3, rest in the riff, notes play G 3 and 2 more"), chord)
        XCTAssertEqual(euclideousStripAccessibilityValue(hits: [EuclideousStripHit()], spokenRank: spokenRank, spokenPitch: spokenPitch, onStep: nil, muted: false), "no hits")
        // REPEAT reads the repeated note
        let rep = hits(fix(exLine(onRest: .repeatLast)))
        XCTAssertTrue(euclideousStripAccessibilityValue(hits: rep, spokenRank: spokenRank, spokenPitch: spokenPitch, onStep: nil, muted: false).contains("step 3, rest in the riff, repeats A flat 3"))
    }

    // MARK: the footers' prediction and ADVANCE EVERY (the defect this ferry's chips would have inherited)

    func testTheFooterPredictionAgreesWithTheEnginesWalkAtEveryAdvanceEvery() {
        for advanceStep in [false, true] {
            for every in 1...4 {
                var l = exLine(every: every, advanceStep: advanceStep); l.riffRotate = 3; l.riffStride = 1
                let f = fix(l)
                let lapTicks = (lapStart..<(lapStart + 8)).filter { euclideousWalkTick(f.cfg, tick: $0).isHit }
                XCTAssertEqual(lapTicks.count, f.hitSteps.count)
                for (i, t) in lapTicks.enumerated() {
                    XCTAssertEqual(f.pass.prediction[i] - 1, euclideousWalkTick(f.cfg, tick: t).playedStep, "ADV \(advanceStep ? "STEP" : "HIT"), EVERY \(every): hit \(i + 1)'s column")
                }
            }
        }
        // EVERY 1 is byte-identical to the pre-fix walk (the default parameter)
        let hs = euclideousLapHitSteps(pulses: 5, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: exBuf)
        XCTAssertEqual(euclideousRiffCyclePrediction(hitSteps: hs, advanceStep: false, dir: .forward, stride: 1, length: 8, rotate: 2, seed: 0, startOrd: 3),
                       euclideousRiffCyclePrediction(hitSteps: hs, advanceStep: false, dir: .forward, stride: 1, length: 8, rotate: 2, seed: 0, startOrd: 3, every: 1))
        XCTAssertEqual(euclideousRiffCyclePrediction(hitSteps: hs, advanceStep: false, dir: .forward, stride: 1, length: 8, rotate: 0, seed: 0, startOrd: 0, every: 2), [1, 1, 2, 2, 3], "EVERY 2 holds each note for two hits")
    }
    func testTheFooterPassCarriesTheLapsAbsoluteTick() {
        let f = fix(exLine())
        XCTAssertEqual(f.pass.lapStartTick, lapStart)
        XCTAssertEqual(f.pass.startOrd, euclideousLapStartOrdinal(cfg: f.cfg, beat: Double(lapStart) * f.cfg.sub + 0.01))
    }

    // MARK: cost

    func testAStripsPureWorkIsCheapPerBodyAndPerFrame() {
        let f = fix(exLine(onRest: .tie))
        let n = notes(.cycle, when: 0b11, chance: 60)
        var sink = 0
        let bodies = 200
        let a = Date()
        for _ in 0..<bodies {
            let h = hits(f, notes: n)
            sink += h.count
        }
        let perBody = Date().timeIntervalSince(a) / Double(bodies)
        let h = hits(f, notes: n)
        let frames = 600
        let b = Date()
        for i in 0..<frames {
            let t = f.hitSteps[i % f.hitSteps.count].tick
            let abs = lapStart + Int64(t)
            let w = euclideousWalkTick(f.cfg, tick: abs)
            if let plan = euclideousWalkTagPlan(cfg: f.cfg, ranks: exRanks, beat: (Double(abs) + 0.1) * f.cfg.sub, secondsPerBeat: 0.5, polledStep: w.playedStep, running: true, polledOrdinal: w.advOrd) {
                sink += euclideousStripCurrentStep(cfg: f.cfg, landedTick: plan.landedTick, passLapStartTick: f.pass.lapStartTick, arrowStaysOnTiedNote: plan.seatIsRest, legs: [EuclideousStripLeg(hitSteps: f.hitSteps, hits: h)])?.step ?? 0
            }
            sink += Int(euclideousStripPlayhead(raw: Double(i % 80) / 10, n: 8, dir: .fwd, xs: (0..<8).map { CGFloat($0) * 28 }, columnW: 26).x)
        }
        let perFrame = Date().timeIntervalSince(b) / Double(frames)
        print("LANE STRIP pure work: per body (hits+keys+labels, one lane) \(perBody * 1000) ms; per frame (arrow plan + current chip + playhead, one lane) \(perFrame * 1000) ms (sink \(sink))")
        XCTAssertLessThan(perBody, 0.01, "a lane's strip plan costs well under 10 ms even in a debug build")
        XCTAssertLessThan(perFrame, 0.01)
    }
}
