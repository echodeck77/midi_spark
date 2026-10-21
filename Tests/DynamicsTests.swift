//  DynamicsTests.swift
//  RHYTHM DYNAMICS ferry (2026-10-21): the pure factor (§5.3), SPREAD's stateless hash, the hit position the Router derives (§5.2), the model's persistence (§4) —
//  ferry §9 tests 2, 3, 4, 5 and 10. The Router half (tests 1, 6–9, 12) lives in RouterTests; the geometry (11) in RhythmDynamicsGeometryTests.

import XCTest

final class DynamicsTests: XCTestCase {
    // E(5,8) at 1/8, FWD: hits on steps 1, 3, 5, 6, 8 → s 0, 2, 4, 5, 7 → j 0…4 (n 8, k 5)
    private let e58: [Bool] = euclideousNoteViewPattern(pulses: 5, steps: 8, rotate: 0, tilt: 0)
    private func factors(_ d: EuclideousDynamics, lane: Int = 0, pass: Int64 = 0, buf: [Bool]? = nil, dir: EuclidDir = .fwd) -> [Double] {
        let hs = euclideousLapHitSteps(buf: buf ?? e58, dir: dir)
        return euclideousDynamicsPassFactors(d, lane: lane, pass: pass, hitSteps: hs, cycleLen: euclidCycleLen(dir, n: (buf ?? e58).count))
    }

    // MARK: §9.2 — the factor
    func testTheE58HitsAreWhereTheFerrySaysTheyAre() {
        XCTAssertEqual(euclideousLapHitSteps(buf: e58, dir: .fwd).map { $0.tick }, [0, 2, 4, 5, 7], "steps 1, 3, 5, 6 and 8")
    }
    func testAccents2OfE58AccentHitsJ0AndJ3AndTheRestPlayAt55Percent() {
        let f = factors(EuclideousDynamics(depth: 45, accents: 2, shape: 0, spread: 0, target: .vel))
        XCTAssertEqual(f.count, 5)
        for (j, v) in f.enumerated() { XCTAssertEqual(v, (j == 0 || j == 3) ? 1 : 0.55, accuracy: 1e-12, "hit j \(j)") }
    }
    func testAccents0GivesFactor1EverywhereAndAccents7OnFiveHitsBehavesAsFive() {
        for v in factors(EuclideousDynamics(depth: 45, accents: 0, shape: 0, spread: 0, target: .vel)) { XCTAssertEqual(v, 1) }
        for v in factors(EuclideousDynamics(depth: 45, accents: 7, shape: 0, spread: 0, target: .vel)) { XCTAssertEqual(v, 1, "min(7, k = 5) = 5: every hit is an accent") }
        XCTAssertEqual(factors(EuclideousDynamics(depth: 45, accents: 7, shape: 0, spread: 0, target: .vel)), factors(EuclideousDynamics(depth: 45, accents: 5, shape: 0, spread: 0, target: .vel)))
    }
    func testTheDefaultAccentIsTheFirstHitOfThePass() {
        let f = factors(EuclideousDynamics(depth: 45, accents: 1, shape: 0, spread: 0, target: .vel))
        XCTAssertEqual(f[0], 1); for v in f.dropFirst() { XCTAssertEqual(v, 0.55, accuracy: 1e-12) }
    }
    func testDepthZeroIsExactlyOneWhateverElseIsSet() {
        let d = EuclideousDynamics(depth: 0, accents: 3, shape: 100, spread: 100, target: .both)
        for pass in Int64(0)..<20 { for v in factors(d, pass: pass) { XCTAssertEqual(v, 1); XCTAssertTrue(v == 1.0) } }
    }

    // MARK: §9.3 — shape
    func testShapeSwellRampsFromHalfToFullAndFadeMirrorsIt() {
        let swell = factors(EuclideousDynamics(depth: 50, accents: 0, shape: 100, spread: 0, target: .vel))
        for (v, want) in zip(swell, [0.5, 0.643, 0.786, 0.857, 1]) { XCTAssertEqual(v, want, accuracy: 0.0006) }
        let fade = factors(EuclideousDynamics(depth: 50, accents: 0, shape: -100, spread: 0, target: .vel))
        for (v, want) in zip(fade, [1, 0.857, 0.714, 0.643, 0.5]) { XCTAssertEqual(v, want, accuracy: 0.0006) }
    }
    func testAShapeOfZeroAndASingleStepPassAreFlat() {
        XCTAssertEqual(euclideousDynamicsFactor(EuclideousDynamics(depth: 80, accents: 0, shape: 60, spread: 0, target: .vel), lane: 0,
                                                at: EuclideousDynamicsPosition(pass: 0, step: 0, steps: 1, hit: 0, hits: 1)), 1 - 0.8 * 0.6, accuracy: 1e-12, "n = 1 ⇒ p = 0: a swell's first step is its quietest")
    }
    func testTheFactorStaysInZeroToOne() {
        var rng: UInt64 = 0x1234_5678
        func next() -> Int { rng = rng &* 6364136223846793005 &+ 1442695040888963407; return Int(rng >> 33) }
        for _ in 0..<5000 {
            let n = 1 + next() % 32, k = 1 + next() % 16, j = next() % k, s = next() % n
            let d = EuclideousDynamics(depth: next() % 101, accents: next() % 17, shape: next() % 201 - 100, spread: next() % 101, target: .both)
            let f = euclideousDynamicsFactor(d, lane: next() % 4, at: EuclideousDynamicsPosition(pass: Int64(next() % 5000), step: s, steps: n, hit: j, hits: k))
            XCTAssertTrue(f >= 0 && f <= 1, "f \(f)")
        }
    }

    // MARK: §9.4 — spread
    func testSpreadIsAStatelessHashInZeroToOneThatChangesWithThePass() {
        var seen = Set<Double>()
        for pass in Int64(0)..<64 {
            let r = euclideousDynamicsSpreadUnit(lane: 1, pass: pass, step: 3)
            XCTAssertTrue(r >= 0 && r < 1)
            XCTAssertEqual(r, euclideousDynamicsSpreadUnit(lane: 1, pass: pass, step: 3), "the same (lane, q, s) gives the same r every time")
            seen.insert(r)
        }
        XCTAssertGreaterThan(seen.count, 60, "different passes give different values")
        XCTAssertNotEqual(euclideousDynamicsSpreadUnit(lane: 0, pass: 7, step: 2), euclideousDynamicsSpreadUnit(lane: 1, pass: 7, step: 2), "…and so do different lanes")
        XCTAssertNotEqual(euclideousDynamicsSpreadUnit(lane: 0, pass: 7, step: 2), euclideousDynamicsSpreadUnit(lane: 0, pass: 7, step: 3), "…and different steps")
    }
    func testSpreadZeroGivesASpreadTermOfOne() {
        let a = EuclideousDynamics(depth: 60, accents: 0, shape: 0, spread: 0, target: .vel)
        for pass in Int64(0)..<10 { for v in factors(a, pass: pass) { XCTAssertEqual(v, 1) } }
        let b = EuclideousDynamics(depth: 60, accents: 0, shape: 0, spread: 100, target: .vel)
        XCTAssertTrue(factors(b, pass: 3).contains { $0 < 1 }, "SPREAD 100 loosens at least one hit")
        XCTAssertEqual(factors(b, pass: 3), factors(b, pass: 3))
        XCTAssertNotEqual(factors(b, pass: 3), factors(b, pass: 4), "SPREAD changes per pass")
    }
    func testTheHashIsKnownAtAFewPoints() {
        // pins the formula (SplitMix64 of lane << 40 | q << 8 | s, top 24 bits / 2^24) against an accidental change
        let key = (UInt64(2) << 40) | (UInt64(5) << 8) | UInt64(3)
        XCTAssertEqual(euclideousDynamicsSpreadUnit(lane: 2, pass: 5, step: 3), Double(splitmix64Mix(key) >> 40) / 16_777_216.0)
    }

    // MARK: §9.5 — positions, as the Router derives them from the per-tick core, against the display's lap list
    private func cfgChains(_ rhythm: [UInt8]?, barBeats: Double = 4, lap: Double = 4) -> EuclideousLaneRestartChains {
        guard let r = rhythm else { return .off }
        return EuclideousLaneRestartChains(rhythm: .from(r), melody: .free, barBeats: barBeats, lapBeats: lap)
    }
    /// Every tick of `passes` passes: the Router's (s, j, k, n) must be the lap list's, for every direction.
    private func checkPositions(buf: [Bool], dir: EuclidDir, sub: Double, chains: EuclideousLaneRestartChains, ticks: Int, file: StaticString = #filePath, line: UInt = #line) {
        let n = buf.count, cl = euclidCycleLen(dir, n: n)
        let hs = euclideousLapHitSteps(buf: buf, dir: dir)
        var checked = 0
        for t in 0..<ticks {
            let ti = euclideousLaneChainTick(buf: buf, n: n, dir: dir, cycleLen: cl, sub: sub, tick: Int64(t), chains: chains, legacySpanBeats: 0, advanceStep: false)
            guard ti.rawIsHit else { continue }
            let pos = euclideousDynamicsPosition(tick: Int64(t), raw: ti.raw, hitsUpTo: ti.hitsUpTo, cycleHits: hs.count, cycleLen: cl, sub: sub, chains: chains)
            XCTAssertEqual(pos.step, ti.raw, file: file, line: line)
            XCTAssertEqual(pos.steps, cl, "n is the full there-and-back for PING-PONG", file: file, line: line)
            XCTAssertEqual(pos.hits, hs.count, file: file, line: line)
            XCTAssertEqual(hs[pos.hit].tick, pos.step, "hit j sits on the lap list's step s (\(dir) tick \(t))", file: file, line: line)
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0, file: file, line: line)
    }
    func testPositionsForForwardBackwardAndPingPongMatchTheLapList() {
        for dir in [EuclidDir.fwd, .bkw, .pingpong] {
            checkPositions(buf: e58, dir: dir, sub: 0.5, chains: .off, ticks: 8 * 2 * 6)
        }
    }
    func testPingPongPlaysEachEndStepTwiceAndCountsBothVisits() {
        let hs = euclideousLapHitSteps(buf: e58, dir: .pingpong)
        XCTAssertEqual(hs.count, 10, "E(5,8) ping-pong: every hit once up, once down")
        XCTAssertEqual(hs.map { $0.tick }, [0, 2, 4, 5, 7, 8, 10, 11, 13, 15])
        let f = factors(EuclideousDynamics(depth: 40, accents: 2, shape: 0, spread: 0, target: .vel), dir: .pingpong)
        XCTAssertEqual(f.count, 10)
        XCTAssertEqual(f.filter { $0 == 1 }.count, 2, "two accents over the full there-and-back pass")
    }
    func testAHandEditedPatternAndTiltAndInvertKeepTheirStepsPositions() {
        let custom: [Bool] = [true, false, true, true, false, true, false]
        checkPositions(buf: custom, dir: .fwd, sub: 0.5, chains: .off, ticks: 7 * 5)
        let tilted = euclideousNoteViewPattern(pulses: 4, steps: 8, rotate: 1, tilt: 0.8)
        checkPositions(buf: tilted, dir: .bkw, sub: 0.5, chains: .off, ticks: 8 * 5)
        let inverted = euclideousNoteViewPattern(pulses: 5, steps: 8, rotate: 0, tilt: -1, patternMiss: true)
        checkPositions(buf: inverted, dir: .pingpong, sub: 0.5, chains: .off, ticks: 16 * 4)
        // a tilted hit keeps its own step's s: the lap list is the pattern's hits in play order
        XCTAssertEqual(euclideousLapHitSteps(buf: tilted, dir: .fwd).map { $0.bufIdx }, (0..<8).filter { tilted[$0] })
    }
    func testAPassCutShortByARhythmRestartKeepsTheFullPassesNAndK() {
        // 16 steps at 1/8 (0.5 beat) = an 8-beat pass; a one-bar (4-beat) rhythm chain cuts every pass after step 8
        let buf = euclideousNoteViewPattern(pulses: 6, steps: 16, rotate: 0, tilt: 0)
        let chains = EuclideousLaneRestartChains(rhythm: .from([1]), melody: .free, barBeats: 4, lapBeats: 8)
        checkPositions(buf: buf, dir: .fwd, sub: 0.5, chains: chains, ticks: 16 * 4)
        let hs = euclideousLapHitSteps(buf: buf, dir: .fwd)
        for t in 0..<64 {
            let ti = euclideousLaneChainTick(buf: buf, n: 16, dir: .fwd, cycleLen: 16, sub: 0.5, tick: Int64(t), chains: chains, legacySpanBeats: 0, advanceStep: false)
            let pos = euclideousDynamicsPosition(tick: Int64(t), raw: ti.raw, hitsUpTo: ti.hitsUpTo, cycleHits: hs.count, cycleLen: 16, sub: 0.5, chains: chains)
            XCTAssertEqual(pos.steps, 16); XCTAssertEqual(pos.hits, hs.count)
            XCTAssertLessThan(ti.raw, 8, "the restart at every bar cuts the pass at step 8")
            XCTAssertEqual(pos.pass, Int64(t / 8), "each bar's (cut-short) pass has its own index")
        }
    }
    func testThePassIndexAgreesWithTheRestartChainsOwnPassIndexAndNeverSitsOnABoundary() {
        for sub in [0.5, 0.25, 1.0 / 6.0, 1.0 / 3.0] {
            let cl = 8
            for t in 0..<(cl * 9) {
                let raw = t % cl
                let q = euclideousDynamicsPassIndex(tick: Int64(t), raw: raw, sub: sub, cycleLen: cl, chains: .off)
                XCTAssertEqual(q, Int64(t / cl), "sub \(sub) tick \(t): free-running pass index")
            }
        }
    }

    // MARK: §5.4 — applying f
    func testScaledVelocityRoundsToNearestAndClampsToOneAndTo127() {
        XCTAssertEqual(euclideousDynamicsScaledVelocity(100, factor: 0.55), 55)
        XCTAssertEqual(euclideousDynamicsScaledVelocity(120, factor: 0.5), 60)
        XCTAssertEqual(euclideousDynamicsScaledVelocity(101, factor: 0.5), 51, "50.5 rounds up")
        XCTAssertEqual(euclideousDynamicsScaledVelocity(1, factor: 0.2), 1, "never below 1")
        XCTAssertEqual(euclideousDynamicsScaledVelocity(80, factor: 0), 1)
        XCTAssertEqual(euclideousDynamicsScaledVelocity(127, factor: 1), 127)
        XCTAssertEqual(euclideousDynamicsScaledVelocity(127, factor: 1.0), 127)
    }
    func testScaledGateNeverDropsBelowOnePercentAndLegatoIsNotScaled() {
        XCTAssertEqual(euclideousDynamicsScaledGate(0.5, factor: 0.5), 0.25, accuracy: 1e-12)
        XCTAssertEqual(euclideousDynamicsScaledGate(0.5, factor: 0), 0.01)
        XCTAssertEqual(euclideousDynamicsScaledGate(0.9, factor: 1), 0.9)
        XCTAssertEqual(euclideousDynamicsScaledGate(1.0, factor: 0.3), 1.0, "legato stays legato")
        XCTAssertEqual(euclideousDynamicsScaledGate(0.995, factor: 0.3), 0.995, "a gate that rounds to 100% is legato (euclideousGateIsLegato)")
        XCTAssertEqual(euclideousDynamicsScaledGate(0.005, factor: 0.5), 0.005, "a gate already under the 1% floor is left alone — DYNAMICS never raises one")
    }

    // MARK: §9.10 — persistence
    func testAllFiveFieldsRoundTripAndAnOldDocumentResolvesToFlat() throws {
        var l = EuclidLine(pulses: 5, steps: 8)
        l.dynDepth = 45; l.dynAccents = 3; l.dynShape = -40; l.dynSpread = 15; l.dynTarget = .both
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
        XCTAssertEqual([back.dynDepth, back.dynAccents, back.dynShape, back.dynSpread], [45, 3, -40, 15]); XCTAssertEqual(back.dynTarget, .both)
        let old = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8))
        XCTAssertNil(old.dynDepth); XCTAssertNil(old.dynAccents); XCTAssertNil(old.dynShape); XCTAssertNil(old.dynSpread); XCTAssertNil(old.dynTarget)
        XCTAssertEqual(old.dynDepthResolved, 0, "a pre-feature lane reads FLAT")
        XCTAssertEqual(old.dynAccentsResolved, 1); XCTAssertEqual(old.dynShapeResolved, 0); XCTAssertEqual(old.dynSpreadResolved, 0); XCTAssertEqual(old.dynTargetResolved, .vel)
        XCTAssertTrue(EuclideousDynamics(old).isFlat)
    }
    func testOutOfRangeAndWrongTypedValuesClampOrReadAsMissingOnDecode() throws {
        let hi = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"dynDepth":250,"dynAccents":99,"dynShape":-900,"dynSpread":101,"dynTarget":"BOTH"}"#.utf8))
        XCTAssertEqual(hi.dynDepth, 100); XCTAssertEqual(hi.dynAccents, 16); XCTAssertEqual(hi.dynShape, -100); XCTAssertEqual(hi.dynSpread, 100)
        let lo = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"dynDepth":-5,"dynAccents":-2,"dynShape":900,"dynSpread":-1}"#.utf8))
        XCTAssertEqual(lo.dynDepth, 0); XCTAssertEqual(lo.dynAccents, 0); XCTAssertEqual(lo.dynShape, 100); XCTAssertEqual(lo.dynSpread, 0)
        let junk = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"pulses":3,"dynDepth":"loud","dynAccents":[1],"dynTarget":"SIDEWAYS"}"#.utf8))   // MUST NOT throw
        XCTAssertNil(junk.dynDepth); XCTAssertNil(junk.dynAccents); XCTAssertNil(junk.dynTarget); XCTAssertEqual(junk.pulses, 3)
    }
    func testNewLanesAndTheFactoryResetStoreTheDefaultsExplicitly() {
        let fresh = PluginState(machines: [], scenes: [])
        for l in fresh.euclideousLinesResolved {
            XCTAssertEqual(l.dynDepth, 0); XCTAssertEqual(l.dynAccents, 1); XCTAssertEqual(l.dynShape, 0); XCTAssertEqual(l.dynSpread, 0); XCTAssertEqual(l.dynTarget, .vel)
        }
    }
}
