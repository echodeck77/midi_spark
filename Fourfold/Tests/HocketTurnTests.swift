//  HocketTurnTests.swift — HOCKET ferry (2026-10-27) §12 test 3 (the cycle) and the pure half of test 4 (counting), plus §6.5's output table, §8.1's live chips and §9.1's part states as pure functions.
//  The Router tests (HocketRouterTests) drive the same functions through a real engine; these pin the functions themselves.

import XCTest

final class HocketTurnTests: XCTestCase {

    private func snap(_ configure: (inout HocketRule) -> Void) -> HocketRuleSnap {
        var r = HocketRule(); configure(&r); return HocketRuleSnap(r)
    }
    /// The word for each count: "M" or "A", and the ALT turn index.
    private func cycle(mainLen: Int, altLen: Int, offset: Int, over xs: Range<Int>) -> (letters: String, ks: [Int64]) {
        var s = "", k: [Int64] = []
        for x in xs { let t = hocketTurn(x: Int64(x), offset: offset, mainLen: mainLen, altLen: altLen); s += t.isAlt ? "A" : "M"; k.append(t.k) }
        return (s, k)
    }

    // MARK: - test 3 — the cycle

    func testMainThreeAltOneOffsetZero() {
        let c = cycle(mainLen: 3, altLen: 1, offset: 0, over: 0..<8)
        XCTAssertEqual(c.letters, "MMMAMMMA"); XCTAssertEqual(c.ks, [0, 0, 0, 0, 1, 1, 1, 1])
    }
    func testOffsetOneAndThreeRotateTheCycle() {
        XCTAssertEqual(cycle(mainLen: 3, altLen: 1, offset: 1, over: 0..<8).letters, "MMAMMMAM")
        XCTAssertEqual(cycle(mainLen: 3, altLen: 1, offset: 3, over: 0..<8).letters, "AMMMAMMM")
    }
    func testTheCycleStripCellsFollowTheSameRule() {
        for (m, a, o) in [(3, 1, 0), (3, 1, 1), (3, 1, 3), (1, 1, 0), (2, 5, 4), (8, 8, 15)] {
            let strip = (0..<(m + a)).map { hocketCycleCellIsAlt($0, offset: o, mainLen: m, altLen: a) }
            let turns = (0..<(m + a)).map { hocketTurn(x: Int64($0), offset: o, mainLen: m, altLen: a).isAlt }
            XCTAssertEqual(strip, turns, "cell i is the turn at count i (mainLen \(m), altLen \(a), offset \(o))")
            XCTAssertEqual(strip.filter { !$0 }.count, m, "a cycle holds MAIN's turns then ALT's, rotated: \(m) MAIN cells"); XCTAssertEqual(strip.filter { $0 }.count, a)
        }
    }
    func testEveryCountAndOffsetStaysOnTheCycle() {
        for m in 1...8 { for a in 1...8 { for o in 0..<(m + a) {
            var alt = 0
            for x in 0..<(m + a) { let t = hocketTurn(x: Int64(x), offset: o, mainLen: m, altLen: a); if t.isAlt { alt += 1 } }
            XCTAssertEqual(alt, a, "one full cycle holds exactly altLen ALT turns (m \(m) a \(a) o \(o))")
            XCTAssertEqual(hocketTurn(x: Int64(m + a) * 5 + 2, offset: o, mainLen: m, altLen: a).isAlt, hocketTurn(x: 2, offset: o, mainLen: m, altLen: a).isAlt, "periodic")
        } } }
        XCTAssertEqual(hocketTurn(x: -4, offset: 0, mainLen: 2, altLen: 2), hocketTurn(x: 0, offset: 0, mainLen: 2, altLen: 2), "a negative count reads as 0")
    }

    // MARK: - §6.5 — where a note leaves

    func testSwapTable() {
        let together = snap { $0.main = [1]; $0.alt = [3] }                          // RED RIFF / BLUE RIFF → buses 0 and 2
        XCTAssertEqual(hocketOutput(for: 0, rule: together, turn: HocketTurn(isAlt: false, k: 0)), 0)
        XCTAssertEqual(hocketOutput(for: 2, rule: together, turn: HocketTurn(isAlt: false, k: 0)), -1, "MAIN turn: an ALT-only output is silent")
        XCTAssertEqual(hocketOutput(for: 0, rule: together, turn: HocketTurn(isAlt: true, k: 0)), -1, "ALT turn: a MAIN-only output is silent")
        XCTAssertEqual(hocketOutput(for: 2, rule: together, turn: HocketTurn(isAlt: true, k: 0)), 2)
        let both = snap { $0.main = [1]; $0.alt = [1, 3] }
        for alt in [false, true] { XCTAssertEqual(hocketOutput(for: 0, rule: both, turn: HocketTurn(isAlt: alt, k: 0)), 0, "in both groups: always plays") }
        let rotate = snap { $0.main = [1]; $0.alt = [3, 5, 7]; $0.several = .rotate }
        for k in 0..<7 {
            let t = HocketTurn(isAlt: true, k: Int64(k))
            let playing = [2, 4, 6].filter { hocketOutput(for: $0, rule: rotate, turn: t) == $0 }
            XCTAssertEqual(playing, [[2, 4, 6][k % 3]], "ROTATE: ALT[k mod 3] only (k \(k))")
        }
    }
    func testPassTable() {
        let r = snap { $0.mode = .pass; $0.main = [2, 4]; $0.alt = [4, 2] }          // RED NOTES, BLUE NOTES crossing → buses 1, 3
        let main = HocketTurn(isAlt: false, k: 0), alt = HocketTurn(isAlt: true, k: 0)
        XCTAssertEqual(hocketOutput(for: 1, rule: r, turn: main), 1); XCTAssertEqual(hocketOutput(for: 3, rule: r, turn: main), 3)
        XCTAssertEqual(hocketOutput(for: 1, rule: r, turn: alt), 3, "MAIN i = 0 → ALT[0 mod 2]"); XCTAssertEqual(hocketOutput(for: 3, rule: r, turn: alt), 1, "MAIN i = 1 → ALT[1 mod 2]")
        XCTAssertEqual(hocketCarriedSource(by: 3, rule: r, turn: alt), 1, "BLUE NOTES (bus 3) carries RED NOTES' line (bus 1)"); XCTAssertEqual(hocketCarriedSource(by: 1, rule: r, turn: alt), 3)
        XCTAssertEqual(hocketCarriedSource(by: 3, rule: r, turn: main), -1)
        // ROTATE: MAIN i → ALT[(i + k) mod n]
        let rot = snap { $0.mode = .pass; $0.main = [2, 4]; $0.alt = [6, 8, 1]; $0.several = .rotate }
        for k in 0..<4 {
            let t = HocketTurn(isAlt: true, k: Int64(k))
            XCTAssertEqual(hocketOutput(for: 1, rule: rot, turn: t), [5, 7, 0][(0 + k) % 3]); XCTAssertEqual(hocketOutput(for: 3, rule: rot, turn: t), [5, 7, 0][(1 + k) % 3])
        }
        // ALT empty: MAIN's notes go nowhere on ALT turns
        let none = snap { $0.mode = .pass; $0.main = [2]; $0.alt = [] }
        XCTAssertEqual(hocketOutput(for: 1, rule: none, turn: alt), -1); XCTAssertEqual(hocketOutput(for: 1, rule: none, turn: main), 1)
        XCTAssertEqual(hocketReceivers(rule: none, turn: alt), 0)
    }
    func testAnAltOnlyOutputIsSilentWhileItCarriesALineUnderReplaceAndPlaysUnderMerge() {
        func rule(_ own: HocketOwn, rotate: Bool = false) -> HocketRuleSnap { snap { $0.mode = .pass; $0.main = [2]; $0.alt = [4, 6]; $0.own = own; $0.several = rotate ? .rotate : .together } }
        let alt = HocketTurn(isAlt: true, k: 0)
        XCTAssertEqual(hocketReceivers(rule: rule(.replace), turn: alt), 0b0010_1000, "TOGETHER: one MAIN output and two ALT outputs — the line goes to BOTH (BLUE NOTES, bus 3, and AMBER NOTES, bus 5)")
        XCTAssertEqual(hocketOutput(for: 3, rule: rule(.replace), turn: alt), -1, "REPLACE: the receiver's own part is silent")
        XCTAssertEqual(hocketOutput(for: 5, rule: rule(.replace), turn: alt), -1, "…for every receiver")
        XCTAssertEqual(hocketOutput(for: 3, rule: rule(.merge), turn: alt), 3, "MERGE: it keeps playing")
        XCTAssertEqual(hocketOutput(for: 3, rule: rule(.replace), turn: HocketTurn(isAlt: false, k: 0)), 3, "MAIN turn: every output plays its own")
        // ROTATE sends it to ONE ALT output a turn: the one that receives nothing plays its own part
        XCTAssertEqual(hocketReceivers(rule: rule(.replace, rotate: true), turn: alt), 0b0000_1000)
        XCTAssertEqual(hocketOutput(for: 5, rule: rule(.replace, rotate: true), turn: alt), 5, "an ALT output that receives nothing plays its own part")
    }
    /// TOGETHER (Paul, 2026-10-27): pairs by order, and lets the extra ALT outputs share the MAIN lines when MAIN has fewer outputs; ROTATE is one ALT output a turn.
    func testTogetherPairsByOrderAndSharesTheLinesAcrossExtraAltOutputs() {
        func pos(_ i: Int, _ m: Int, _ n: Int, rotate: Bool = false, k: Int64 = 0) -> UInt8 { hocketPassAltPositions(mainIndex: i, mainCount: m, altCount: n, rotate: rotate, k: k) }
        XCTAssertEqual(pos(0, 1, 2), 0b11, "1 MAIN, 2 ALT: both")
        XCTAssertEqual(pos(0, 1, 3), 0b111, "1 MAIN, 3 ALT: all three")
        XCTAssertEqual(pos(0, 2, 2), 0b01); XCTAssertEqual(pos(1, 2, 2), 0b10, "2 MAIN, 2 ALT: a crossing pairs one to one")
        XCTAssertEqual(pos(0, 2, 3), 0b101, "2 MAIN, 3 ALT: MAIN 0 → ALT 0 and 2 …"); XCTAssertEqual(pos(1, 2, 3), 0b010, "… MAIN 1 → ALT 1")
        XCTAssertEqual(pos(0, 3, 2), 0b01); XCTAssertEqual(pos(1, 3, 2), 0b10); XCTAssertEqual(pos(2, 3, 2), 0b01, "3 MAIN, 2 ALT: fan-in, i mod n")
        XCTAssertEqual(pos(0, 4, 1), 0b1, "any MAIN count, one ALT: the one")
        for k in 0..<5 { XCTAssertEqual(pos(0, 1, 3, rotate: true, k: Int64(k)), UInt8(1) << UInt8(k % 3), "ROTATE: one ALT output a turn") }
        XCTAssertEqual(pos(1, 2, 3, rotate: true, k: 1), 0b100, "ROTATE: ALT[(i + k) mod n]")
        XCTAssertEqual(pos(0, 0, 2), 0); XCTAssertEqual(pos(0, 1, 0), 0, "nothing to pair")
        // the engine's output set agrees with the positions, for every rule shape
        for m in 1...3 { for n in 1...3 {
            let r = snap { $0.mode = .pass; $0.main = Array(1...m); $0.alt = Array(4...(3 + n)); $0.own = .merge }
            for i in 0..<m {
                var want: UInt8 = 0; let p = pos(i, m, n)
                for j in 0..<n where p & (UInt8(1) << UInt8(j)) != 0 { want |= UInt8(1) << UInt8(3 + j) }
                XCTAssertEqual(hocketOutputs(for: i, rule: r, turn: HocketTurn(isAlt: true, k: 0)), want, "m=\(m) n=\(n) i=\(i)")
            }
        } }
    }

    // MARK: - §8.1 / §9.1

    func testLiveChipsFollowTheTurn() {
        let swap = snap { $0.main = [1, 3]; $0.alt = [5, 7] }
        XCTAssertEqual(hocketLiveChips(rule: swap, turn: HocketTurn(isAlt: false, k: 0)).main, 0b0000_0101); XCTAssertEqual(hocketLiveChips(rule: swap, turn: HocketTurn(isAlt: false, k: 0)).alt, 0)
        XCTAssertEqual(hocketLiveChips(rule: swap, turn: HocketTurn(isAlt: true, k: 0)).alt, 0b0101_0000); XCTAssertEqual(hocketLiveChips(rule: swap, turn: HocketTurn(isAlt: true, k: 0)).main, 0)
        let rot = snap { $0.main = [1]; $0.alt = [3, 5]; $0.several = .rotate }
        XCTAssertEqual(hocketLiveChips(rule: rot, turn: HocketTurn(isAlt: true, k: 1)).alt, 0b0001_0000, "ROTATE: ALT[1] = cable 5 = bus 4")
        let pass = snap { $0.mode = .pass; $0.main = [2]; $0.alt = [4, 6] }
        XCTAssertEqual(hocketLiveChips(rule: pass, turn: HocketTurn(isAlt: true, k: 0)).alt, 0b0010_1000, "PASS: the ALT chips receiving a line (TOGETHER: both of two ALT outputs)")
    }
    func testPartStates() {
        var rules = HocketRulesSnap(rules: [{ var r = HocketRule(); r.mode = .pass; r.main = [2, 4]; r.alt = [4, 2]; return r }()])
        var turns = HocketTurns(); turns.running = true
        turns[0] = HocketTurn(isAlt: true, k: 0)
        let red = hocketPartView(bus: 1, rules: rules, turns: turns), blue = hocketPartView(bus: 3, rules: rules, turns: turns)
        XCTAssertEqual(red.play, .away(bus: 3)); XCTAssertEqual(red.carrying, 3, "a crossing: away AND carrying")
        XCTAssertEqual(blue.play, .away(bus: 1)); XCTAssertEqual(blue.carrying, 1)
        XCTAssertEqual(hocketPartView(bus: 0, rules: rules, turns: turns), HocketPartView(), "an output in no rule is playing")
        turns[0] = HocketTurn(isAlt: false, k: 0)
        XCTAssertEqual(hocketPartView(bus: 1, rules: rules, turns: turns), HocketPartView(play: .playing, carrying: -1))
        turns.running = false; turns[0] = HocketTurn(isAlt: true, k: 0)
        XCTAssertEqual(hocketPartView(bus: 1, rules: rules, turns: turns), HocketPartView(), "stopped: every part is playing")
        // REPLACE: the receiver rests and carries; MERGE: it plays and carries
        rules = HocketRulesSnap(rules: [{ var r = HocketRule(); r.mode = .pass; r.main = [2]; r.alt = [4]; r.own = .replace; return r }()])
        turns.running = true
        XCTAssertEqual(hocketPartView(bus: 3, rules: rules, turns: turns), HocketPartView(play: .resting, carrying: 1))
        XCTAssertEqual(hocketPartView(bus: 1, rules: rules, turns: turns), HocketPartView(play: .away(bus: 3), carrying: -1))
        rules = HocketRulesSnap(rules: [{ var r = HocketRule(); r.mode = .pass; r.main = [2]; r.alt = [4]; r.own = .merge; return r }()])
        XCTAssertEqual(hocketPartView(bus: 3, rules: rules, turns: turns), HocketPartView(play: .playing, carrying: 1))
        // SWAP: resting off its turn
        rules = HocketRulesSnap(rules: [{ var r = HocketRule(); r.main = [1]; r.alt = [3]; return r }()])
        XCTAssertEqual(hocketPartView(bus: 0, rules: rules, turns: turns), HocketPartView(play: .resting, carrying: -1)); XCTAssertEqual(hocketPartView(bus: 2, rules: rules, turns: turns), HocketPartView())
        // an unlit rule touches nothing
        rules = HocketRulesSnap(rules: [{ var r = HocketRule(); r.on = false; r.main = [1]; r.alt = [3]; return r }()])
        XCTAssertEqual(hocketPartView(bus: 0, rules: rules, turns: turns), HocketPartView())
    }

    // MARK: - §6.6 — a passed note's velocity

    func testPassedVelocityTakesTheDestinationPadUnderTheHitsOwnAccent() {
        XCTAssertEqual(hocketPassedVelocity(fxVel: nil, destNotes: true, destVelocityAbsolute: 100, destNotesVelocity: 50), 50, "no per-hit velocity: the receiving NOTES pad's MIX VEL")
        XCTAssertEqual(hocketPassedVelocity(fxVel: nil, destNotes: false, destVelocityAbsolute: 90, destNotesVelocity: 50), 90, "…the RIFF pad's for a riff output")
        XCTAssertEqual(hocketPassedVelocity(fxVel: 120, destNotes: false, destVelocityAbsolute: 90, destNotesVelocity: 50), 120, "an accent travels as its own value on a riff output")
        XCTAssertEqual(hocketPassedVelocity(fxVel: 120, destNotes: true, destVelocityAbsolute: 100, destNotesVelocity: 50), 70, "…and under the NOTES pad's offset (−50) on a notes output")
        XCTAssertEqual(hocketPassedVelocity(fxVel: nil, destNotes: true, destVelocityAbsolute: 100, destNotesVelocity: 999), 127); XCTAssertEqual(hocketPassedVelocity(fxVel: nil, destNotes: false, destVelocityAbsolute: -5, destNotesVelocity: 0), 1)
    }

    // MARK: - §6.2 — the count, pure

    /// A lane clock for an n-step pattern at `sub` beats a step.
    private func clock(hits: [Int], n: Int = 8, sub: Double = 0.25, chain: [UInt8]? = nil, delays: [Int: Double] = [:]) -> HocketLaneClock {
        var c = HocketLaneClock()
        var cells = [Bool](repeating: false, count: 32)
        for h in hits { cells[h] = true }
        var d = [Double](repeating: 0, count: 32)
        for (k, v) in delays { d[k] = v }
        var chains = EuclideousLaneRestartChains.off
        if let chain { chains = EuclideousLaneRestartChains(rhythm: .from(chain), melody: .free, barBeats: 4, lapBeats: Double(n) * sub) }
        c.capture(cells: cells, delays: d, timing: !delays.isEmpty, n: n, dir: .fwd, cycleLen: n, sub: sub, chains: chains, legacySpanBeats: 0)
        return c
    }
    func testHitsCountsThePatternHitsUpToAndIncludingTheMomentMinusOne() {
        let c = clock(hits: [0, 2, 4, 6])
        func x(_ beat: Double) -> Int64 { hocketLaneCounts(c, atMusicalBeat: beat).hit }
        XCTAssertEqual([0.0, 0.2, 0.5, 0.74, 1.0, 1.5, 1.99, 2.0, 2.5, 4.0].map(x), [0, 0, 1, 1, 2, 3, 3, 4, 5, 8])
        let late = clock(hits: [2, 4])                                                    // the first hit is on step 3: before it, x is 0
        XCTAssertEqual(hocketLaneCounts(late, atMusicalBeat: 0.0).hit, 0); XCTAssertEqual(hocketLaneCounts(late, atMusicalBeat: 0.49).hit, 0)
        XCTAssertEqual(hocketLaneCounts(late, atMusicalBeat: 0.5).hit, 0, "the first hit itself is hit 0"); XCTAssertEqual(hocketLaneCounts(late, atMusicalBeat: 1.0).hit, 1)
    }
    func testPassesCountsTheLapsFromTheRhythmOrigin() {
        let c = clock(hits: [0, 2, 4, 6])                                                  // a lap of 8 steps of 1/16 = 2 beats
        XCTAssertEqual([0.0, 1.9, 2.0, 3.9, 4.0, 11.0].map { hocketLaneCounts(c, atMusicalBeat: $0).pass }, [0, 0, 1, 1, 2, 5])
    }
    func testARhythmRestartStartsTheCountAgainAtZero() {
        let c = clock(hits: [0, 2, 4, 6], chain: [1])                                      // the rhythm restarts every bar (4 beats)
        XCTAssertEqual(hocketLaneCounts(c, atMusicalBeat: 3.75).hit, 7, "the 8th hit of the bar")
        XCTAssertEqual(hocketLaneCounts(c, atMusicalBeat: 4.0).hit, 0, "a restart zeroes the hit count")
        XCTAssertEqual(hocketLaneCounts(c, atMusicalBeat: 4.5).hit, 1)
        XCTAssertEqual(hocketLaneCounts(c, atMusicalBeat: 3.9).pass, 1); XCTAssertEqual(hocketLaneCounts(c, atMusicalBeat: 4.0).pass, 0, "…and the pass count")
        let free = clock(hits: [0, 2, 4, 6])
        XCTAssertEqual(hocketLaneCounts(free, atMusicalBeat: 4.0).hit, 8, "FREE counts on")
    }
    func testAHitDelayedIntoItsCellCountsOnlyOnceItsTimeHasCome() {
        let c = clock(hits: [0, 2, 4, 6], delays: [2: 0.5])                                // the 2nd hit sounds half a step late: at 0.5 + 0.125 beat
        XCTAssertEqual(hocketLaneCounts(c, atMusicalBeat: 0.5).hit, 0, "its cell has begun, the hit has not struck yet")
        XCTAssertEqual(hocketLaneCounts(c, atMusicalBeat: 0.6).hit, 0)
        XCTAssertEqual(hocketLaneCounts(c, atMusicalBeat: 0.625).hit, 1, "it counts at its own time")
    }
    func testStepsAndBarsReadThePageClockFromBeatZero() {
        XCTAssertEqual(hocketCount(unit: .steps, clock: nil, atMusicalBeat: 0.0, beatsPerBar: 4), 0)
        XCTAssertEqual(hocketCount(unit: .steps, clock: nil, atMusicalBeat: 0.5, beatsPerBar: 4), 2); XCTAssertEqual(hocketCount(unit: .steps, clock: nil, atMusicalBeat: 3.999, beatsPerBar: 4), 15)
        XCTAssertEqual(hocketCount(unit: .bars, clock: nil, atMusicalBeat: 3.999, beatsPerBar: 4), 0); XCTAssertEqual(hocketCount(unit: .bars, clock: nil, atMusicalBeat: 4.0, beatsPerBar: 4), 1)
        XCTAssertEqual(hocketCount(unit: .bars, clock: nil, atMusicalBeat: 9.0, beatsPerBar: 3), 3, "a bar is the host's beats per bar")
        XCTAssertEqual(hocketCount(unit: .hits, clock: nil, atMusicalBeat: 9.0, beatsPerBar: 4), 0, "a reference lane that isn't running holds the count at 0")
        XCTAssertEqual(hocketCount(unit: .steps, clock: nil, atMusicalBeat: -3, beatsPerBar: 4), 0)
    }
}
