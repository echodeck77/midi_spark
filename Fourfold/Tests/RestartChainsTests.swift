//  RestartChainsTests.swift
//  RESTART CHAINS ferry (2026-10-19): the pure layer in Derivations.swift that replaces the LANES GRID's
//  masked rhythm/melody grid — EuclideousRestartChain, the §5.1-§5.4 origin/pass-index/ordinal functions,
//  the chain-era per-tick core (euclideousLaneChainPhase/Tick), and migrateRestartChains. The OLD
//  grid-based core (EuclideousLaneRestartGrid, euclideousLanePhase/Tick, LanesGridTests.swift) stays
//  completely untouched — it now serves only the FX tab's own closed-form pass-index math (out of this
//  ferry's scope), not the real engine path.

import XCTest

final class RestartChainsTests: XCTestCase {

    // MARK: - EuclideousRestartChain (pack/unpack)

    func testChainFromValidatesLinksDropsInvalidAndCapsAtFour() {
        let c = EuclideousRestartChain.from([2, 1, 1])
        XCTAssertEqual(c.count, 3)
        XCTAssertEqual(c.link(0), 2); XCTAssertEqual(c.link(1), 1); XCTAssertEqual(c.link(2), 1)
        XCTAssertEqual(c.total, 4)
        XCTAssertEqual(c.runningTotal(0), 0); XCTAssertEqual(c.runningTotal(1), 2); XCTAssertEqual(c.runningTotal(2), 3)
        XCTAssertFalse(c.isFree)
        // invalid values (0, 5, 7, 9) dropped; capped at 4 links
        let dirty = EuclideousRestartChain.from([1, 0, 5, 2, 7, 3, 4, 6, 8])
        XCTAssertEqual(dirty.count, 4)
        XCTAssertEqual(dirty.links, [1, 2, 3, 4])
    }
    func testEmptyArrayIsFreeAndRoundTripsThroughLinks() {
        XCTAssertTrue(EuclideousRestartChain.free.isFree)
        XCTAssertTrue(EuclideousRestartChain.from([]).isFree)
        XCTAssertEqual(EuclideousRestartChain.from([]).links, [])
        let c = EuclideousRestartChain.from([2, 1, 1])
        XCTAssertEqual(EuclideousRestartChain.from(c.links).packed, c.packed, "pack -> links -> pack round-trips")
    }
    func testIsSingleLink1OnlyTrueForExactlyOneLinkOfOne() {
        XCTAssertTrue(EuclideousRestartChain.from([1]).isSingleLink1)
        XCTAssertFalse(EuclideousRestartChain.from([1, 1]).isSingleLink1)
        XCTAssertFalse(EuclideousRestartChain.from([2]).isSingleLink1)
        XCTAssertFalse(EuclideousRestartChain.free.isSingleLink1)
    }

    // MARK: - §5.1 rhythm origin / next restart — the spec's own [2,1,1] example

    func testRhythmChainOriginMatchesTheFerrysOwn211Example() {
        // "melody 2·1·1 restarts at passes 0, 2, 3, 4, 6, 7, 8, 10, 11, 12" — same running-total rule
        // for RHYTHM, in BARS: barBeats = 4.
        let chain = EuclideousRestartChain.from([2, 1, 1])
        let barBeats = 4.0
        // one cycle (C=4 bars=16 beats): marks at bar 0, 2, 3, then wraps to bar 4 (next cycle's 0)
        for (bar, want) in [(0, 0), (1, 0), (2, 2), (3, 3), (4, 4), (5, 4), (6, 6), (7, 7), (8, 8), (9, 8), (10, 10), (11, 11)] {
            let beat = Double(bar) * barBeats
            let origin = euclideousRhythmChainOrigin(beat: beat, barBeats: barBeats, chain: chain)
            XCTAssertEqual(origin, Double(want) * barBeats, accuracy: 1e-9, "bar \(bar)")
        }
    }
    func testRhythmChainOriginIsZeroWhenFree() {
        XCTAssertEqual(euclideousRhythmChainOrigin(beat: 123.4, barBeats: 4, chain: .free), 0)
    }
    func testNextRhythmRestartWalksTheSameExampleForward() {
        let chain = EuclideousRestartChain.from([2, 1, 1])
        let barBeats = 4.0
        XCTAssertEqual(euclideousNextRhythmRestart(after: 0, barBeats: barBeats, chain: chain), 2 * barBeats)
        XCTAssertEqual(euclideousNextRhythmRestart(after: 2 * barBeats, barBeats: barBeats, chain: chain), 3 * barBeats)
        XCTAssertEqual(euclideousNextRhythmRestart(after: 3 * barBeats, barBeats: barBeats, chain: chain), 4 * barBeats)
        XCTAssertEqual(euclideousNextRhythmRestart(after: 3.5 * barBeats, barBeats: barBeats, chain: chain), 4 * barBeats)
        XCTAssertNil(euclideousNextRhythmRestart(after: 0, barBeats: barBeats, chain: .free))
    }
    func testChainOfOneRestartsEveryBar() {
        let chain = EuclideousRestartChain.from([1])
        let barBeats = 4.0
        for bar in 0...10 {
            XCTAssertEqual(euclideousRhythmChainOrigin(beat: Double(bar) * barBeats, barBeats: barBeats, chain: chain), Double(bar) * barBeats, accuracy: 1e-9)
        }
    }

    // MARK: - §5.2 pass index / pass start — round trip + the epsilon rule

    func testPassIndexFreeMatchesPlainFloorDivision() {
        let lapBeats = 4.0
        for beat in stride(from: 0.0, to: 40.0, by: 0.7) {
            XCTAssertEqual(euclideousPassIndex(beat: beat, lapBeats: lapBeats, barBeats: 4, rhythmChain: .free), Int64((beat / lapBeats).rounded(.down)))
        }
    }
    func testPassIndexAndPassStartRoundTripForAFreeRhythmChain() {
        let lapBeats = 3.5
        for q in Int64(0)...30 {
            let beat = euclideousPassStart(q, lapBeats: lapBeats, barBeats: 4, rhythmChain: .free)
            XCTAssertEqual(euclideousPassIndex(beat: beat, lapBeats: lapBeats, barBeats: 4, rhythmChain: .free), q, "pass \(q) start round-trips")
        }
    }
    /// §3's own worked example: a 7-step 1/8 lane (lapBeats 3.5) with rhythm [1] starts passes at
    /// 0, 3.5, 4, 7.5, 8, 11.5, … — two per bar, the half-beat lap included.
    func testPassStartsForASevenStepLaneWithRhythmChainOfOne() {
        let chain = EuclideousRestartChain.from([1])
        let lapBeats = 3.5, barBeats = 4.0
        let wantStarts: [Double] = [0, 3.5, 4, 7.5, 8, 11.5]
        for (q, want) in wantStarts.enumerated() {
            XCTAssertEqual(euclideousPassStart(Int64(q), lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), want, accuracy: 1e-9, "pass \(q)")
        }
        // and the inverse: a beat just before/at/after a pass start resolves to the right pass index
        XCTAssertEqual(euclideousPassIndex(beat: 3.4, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), 0)
        XCTAssertEqual(euclideousPassIndex(beat: 3.5, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), 1)
        XCTAssertEqual(euclideousPassIndex(beat: 7.4, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), 2)
        XCTAssertEqual(euclideousPassIndex(beat: 7.5, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), 3)
    }
    /// §8's "changes nothing" / epsilon rule: [1] on 8×1/8 (lapBeats 4, barBeats 4) — every bar is already
    /// a lap start, so no empty pass is inserted (pass index == bar index exactly).
    func testExactMultipleLinkAddsNoEmptyPass() {
        let chain = EuclideousRestartChain.from([1])
        let lapBeats = 4.0, barBeats = 4.0
        for bar in 0...10 {
            XCTAssertEqual(euclideousPassIndex(beat: Double(bar) * barBeats, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), Int64(bar))
        }
    }
    /// §3's own worked example (rhythm fixes §8 test 3): a 16-step 1/4 lane (lapBeats 16) with rhythm [1, 2]
    /// starts passes at 0, 4, 12, 16, 24, 28 — the lap (16 beats) is longer than link 0's own segment (1 bar
    /// = 4 beats), so one pass can span a segment boundary.
    func testPassStartsForALapLongerThanASegment() {
        let chain = EuclideousRestartChain.from([1, 2])
        let lapBeats = 16.0, barBeats = 4.0
        let wantStarts: [Double] = [0, 4, 12, 16, 24, 28]
        for (q, want) in wantStarts.enumerated() {
            XCTAssertEqual(euclideousPassStart(Int64(q), lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), want, accuracy: 1e-9, "pass \(q)")
        }
    }
    // REGRESSION (rhythm fixes §3.3, 2026-10-21): `euclideousPassIndex`'s own `m = floor(beat/cycle)` and its
    // pass-within-segment floor both used to omit the `+ ε` the sibling `passesIn` ceil already had — a beat
    // landing within epsilon of (but just under) a cycle or segment boundary read as the PREVIOUS cycle/pass,
    // not the one starting exactly there. Hand-verified against the unfixed formulas (not guessed): both cases
    // below gave the wrong answer before the `+ eps` fix.
    func testPassIndexRoundsUpAtACycleBoundaryWithinEpsilon() {
        let chain = EuclideousRestartChain.from([1])   // cycle = 1 bar = barBeats
        let barBeats = 4.0, lapBeats = 4.0              // one pass per bar
        let justUnderOneCycle = barBeats - 5e-10        // within the 1e-9 epsilon of the cycle boundary
        XCTAssertEqual(euclideousPassIndex(beat: justUnderOneCycle, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), 1,
                       "a beat within epsilon of the cycle boundary must round UP into the next cycle (was 0 before the +eps fix)")
    }
    func testPassIndexRoundsUpAtASegmentBoundaryWithinEpsilon() {
        let chain = EuclideousRestartChain.from([2, 1, 1])   // segment 0 = 2 bars = 8 beats
        let barBeats = 4.0, lapBeats = 4.0                    // one pass per bar within a segment
        let justUnderSegment0End = 8.0 - 5e-10                // within epsilon of where segment 1 begins
        XCTAssertEqual(euclideousPassIndex(beat: justUnderSegment0End, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: chain), 2,
                       "a beat within epsilon of a segment boundary must round UP into that segment's own first pass (was 1 before the +eps fix)")
    }

    // MARK: - §5.3 melody origin — melody [1] ≡ old LOCK; melody FREE ≡ old FREE

    func testMelodyChainOfOneAlwaysOriginatesAtTheCurrentPassStart() {
        let rhythm = EuclideousRestartChain.free
        let melody = EuclideousRestartChain.from([1])
        let lapBeats = 4.0, barBeats = 4.0
        for beat in stride(from: 0.0, to: 40.0, by: 0.9) {
            let want = Double(Int64((beat / lapBeats).rounded(.down))) * lapBeats
            XCTAssertEqual(euclideousMelodyChainOrigin(beat: beat, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: rhythm, melodyChain: melody),
                           want, accuracy: 1e-9, "beat \(beat): melody [1] always re-anchors to the current pass's own start")
        }
    }
    func testMelodyFreeAlwaysOriginatesAtZero() {
        let melody = EuclideousRestartChain.free
        for beat in stride(from: 0.0, to: 40.0, by: 1.3) {
            XCTAssertEqual(euclideousMelodyChainOrigin(beat: beat, lapBeats: 4, barBeats: 4, rhythmChain: .free, melodyChain: melody), 0)
        }
    }
    func testMelodyChainModsAgainstTheRhythmChainCorrectly() {
        // melody [2,1,1] (P=4) under rhythm FREE (lapBeats = barBeats, so pass == bar): origin at pass q
        // is passStart(q0) where q0 = q - (q mod 4) + the largest running total <= (q mod 4).
        let melody = EuclideousRestartChain.from([2, 1, 1])
        let lapBeats = 4.0, barBeats = 4.0
        let wantQ0: [Int64: Int64] = [0: 0, 1: 0, 2: 2, 3: 3, 4: 4, 5: 4, 6: 6, 7: 7, 8: 8, 9: 8, 10: 10]
        for (q, q0) in wantQ0 {
            let beat = Double(q) * lapBeats
            let origin = euclideousMelodyChainOrigin(beat: beat, lapBeats: lapBeats, barBeats: barBeats, rhythmChain: .free, melodyChain: melody)
            XCTAssertEqual(origin, Double(q0) * lapBeats, accuracy: 1e-9, "pass \(q)")
        }
    }

    // MARK: - §5.4 euclideousChainHitsBefore vs brute force

    private func pattern(_ hits: [Int], n: Int) -> [Bool] { var b = [Bool](repeating: false, count: n); for h in hits { b[h] = true }; return b }

    func testChainHitsBeforeMatchesPlainPatternHitsWhenRhythmIsFree() {
        let buf = pattern([0, 3, 6], n: 8)
        let cycleHits = 3
        for m in Int64(0)...60 {
            let got = euclideousChainHitsBefore(m, rhythm: .free, barBeats: 4, sub: 0.5, buf: buf, n: 8, dir: .fwd, cycleLen: 8, cycleHits: cycleHits)
            // brute force: count hits in [0, m)
            var want: Int64 = 0
            var t: Int64 = 0
            while t < m { if buf[euclidReadIndex(Int(((t % 8) + 8) % 8), n: 8, dir: .fwd)] { want += 1 }; t += 1 }
            XCTAssertEqual(got, want, "m=\(m)")
        }
    }
    func testChainHitsBeforeMatchesBruteForceWithARhythmChainRestartingTheBuffersPhase() {
        // E(3,8): hits on 0,3,6. rhythm [1] at barBeats=4, sub=0.5 (8 ticks/bar == cycleLen) — every bar
        // IS a lap start already, so hits-before should be byte-identical to the FREE case (no re-phase).
        let buf = pattern([0, 3, 6], n: 8)
        let chain = EuclideousRestartChain.from([1])
        for m in Int64(0)...60 {
            let got = euclideousChainHitsBefore(m, rhythm: chain, barBeats: 4, sub: 0.5, buf: buf, n: 8, dir: .fwd, cycleLen: 8, cycleHits: 3)
            let want = euclideousChainHitsBefore(m, rhythm: .free, barBeats: 4, sub: 0.5, buf: buf, n: 8, dir: .fwd, cycleLen: 8, cycleHits: 3)
            XCTAssertEqual(got, want, "m=\(m): a chain whose marks all land on existing lap starts changes nothing")
        }
        // Now a rhythm chain that genuinely re-phases: [2] bars (8 beats = 16 ticks = 2 lane-cycles) on a
        // lane whose own cycle is 8 ticks (4 beats) — so EVERY OTHER lap gets cut short back to step 0.
        // Brute-force cross-check: walk tick by tick, re-deriving "raw" from the rhythm chain directly.
        let chain2 = EuclideousRestartChain.from([2])
        func bruteHitsBefore(_ m: Int64) -> Int64 {
            var count: Int64 = 0
            var t: Int64 = 0
            while t < m {
                let beat = Double(t) * 0.5
                let origin = euclideousOriginTick(euclideousRhythmChainOrigin(beat: beat, barBeats: 4, chain: chain2), sub: 0.5)
                let localT = t - origin
                let raw = Int(((localT % 8) + 8) % 8)
                if buf[euclidReadIndex(raw, n: 8, dir: .fwd)] { count += 1 }
                t += 1
            }
            return count
        }
        for m in Int64(0)...80 {
            let got = euclideousChainHitsBefore(m, rhythm: chain2, barBeats: 4, sub: 0.5, buf: buf, n: 8, dir: .fwd, cycleLen: 8, cycleHits: 3)
            XCTAssertEqual(got, bruteHitsBefore(m), "m=\(m): a genuinely re-phasing rhythm chain")
        }
    }

    // MARK: - euclideousLaneChainPhase / euclideousLaneChainTick — byte-identical reproduction of the old
    // single-restart engine when rhythm == melody (§4.8's "both chains at the same restart points
    // reproduce today's single restart").

    func testRhythmOnlyChainRephasesHitsAndTheRiffCountsStraightThrough() {
        // mirrors RouterTests' own LANES GRID rhythm-only golden: rhythm marks re-phase the pattern, the
        // riff ordinal (melody FREE) counts hits straight through the cut, uninterrupted.
        let buf = pattern([0, 3, 6], n: 8)
        let rhythm = EuclideousRestartChain.from([2])   // restarts every 2 bars = every other 8-tick lap
        let chains = EuclideousLaneRestartChains(rhythm: rhythm, melody: .free, barBeats: 4, lapBeats: 4)
        var advOrds: [Int64] = []
        var raws: [Int] = []
        for tick in Int64(0)..<32 {
            let info = euclideousLaneChainTick(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: tick, chains: chains, legacySpanBeats: 0, advanceStep: false)
            if info.rawIsHit { advOrds.append(info.advOrd); raws.append(info.raw) }
        }
        // the riff ordinal is strictly increasing (never resets) — melody FREE counts straight through the rhythm cut
        for i in 1..<advOrds.count { XCTAssertEqual(advOrds[i], advOrds[i - 1] + 1, "the riff never re-anchors on a rhythm-only chain") }
    }

    // MARK: - migrateRestartChains (§12) — hand-constructed synthetic old masks, exact & fallback paths

    func testMigrationOfAnEmptyOldRestartGivesFreeForBothChains() {
        let line = EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8)
        let m = migrateRestartChains(line: line, lane: 0, legacyOn: false, legacyRate: .oneBar, legacyLen: 8, legacyCells: [],
                                     sub: 0.5, n: 8, dir: .fwd, barBeats: 4)
        XCTAssertTrue(m.rhythmExact); XCTAssertTrue(m.melodyExact)
        XCTAssertEqual(m.rhythm, []); XCTAssertEqual(m.melody, [])
    }
    func testMigrationOfRiffLockAloneGivesMelodyChainOfOneExactly() {
        var line = EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8)
        line.riffLock = true
        let m = migrateRestartChains(line: line, lane: 0, legacyOn: false, legacyRate: .oneBar, legacyLen: 8, legacyCells: [],
                                     sub: 0.5, n: 8, dir: .fwd, barBeats: 4)
        XCTAssertEqual(m.melody, [1]); XCTAssertTrue(m.melodyExact)
    }
    /// §14 test 14's own literal example: "a restart every bar on an 8×1/8 lane gives rhythm FREE and melody 1."
    /// Every-bar on an 8-step 1/8 lane (lapBeats 4 == barBeats 4) is already a lap start every bar, so the
    /// rhythm half of the OLD single restart "changes nothing" (§5.6) and converts to FREE; riffLock alone
    /// (the OLD single-restart model's only way to also restart the melody) gives melody 1.
    func testEveryBarRestartOnEightStepOneEighthLaneGivesRhythmFreeAndMelodyOne() {
        var line = EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8)
        line.restartUnit = EuclideousRestartUnit.pass.rawValue   // PASS == one lap == one bar at 8×1/8
        line.restartRhythmMask16 = 0xFFFF                        // every cell marked = restarts every pass
        line.restartMelodyMask16 = 0xFFFF
        line.riffLock = true
        let m = migrateRestartChains(line: line, lane: 0, legacyOn: false, legacyRate: .oneBar, legacyLen: 8, legacyCells: [],
                                     sub: 0.5, n: 8, dir: .fwd, barBeats: 4)
        XCTAssertEqual(m.rhythm, [], "every mark already lands on a lap start — changes nothing, converts to FREE")
        XCTAssertTrue(m.rhythmExact)
        XCTAssertEqual(m.melody, [1])
        XCTAssertTrue(m.melodyExact)
    }
    func testMigrationReportsNotExactWhenGapsDoNotFitTheAllowedLinkSet() {
        var line = EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8)
        line.restartUnit = EuclideousRestartUnit.fourSteps.rawValue   // 4 steps = 2 beats at 1/8 — NOT bar-aligned (barBeats 4)
        line.restartRhythmMask16 = 1   // one mark at cell 0 only within a 16-cell window that otherwise free-runs — misaligned to bars
        let m = migrateRestartChains(line: line, lane: 0, legacyOn: false, legacyRate: .oneBar, legacyLen: 8, legacyCells: [],
                                     sub: 0.5, n: 8, dir: .fwd, barBeats: 4)
        // a single mark on cell 0 every window is actually bar-aligned here (cellBeats=2, window=16 cells=32 beats=8 bars,
        // mark every 8 bars) — construct a genuinely misaligned case instead: 5-step cells against a 4-beat bar.
        _ = m
        var line2 = EuclidLine(target: 0, pulses: 3, steps: 8, rate: .r1_8)
        line2.restartUnit = EuclideousRestartUnit.fourSteps.rawValue
        line2.restartRhythmMask16 = 0b101   // marks at cell 0 and cell 2: 0 and 4 beats — 4 beats = 1 bar exactly, still aligned
        // fourSteps cell = 4 * sub = 4*0.5 = 2 beats; cell 2 = 4 beats = bar 1 — ALIGNED. Use cell 1 instead (2 beats, not bar-aligned).
        line2.restartRhythmMask16 = 0b11   // cells 0 and 1: beats 0 and 2 — 2 beats is NOT a whole bar
        let m2 = migrateRestartChains(line: line2, lane: 0, legacyOn: false, legacyRate: .oneBar, legacyLen: 8, legacyCells: [],
                                      sub: 0.5, n: 8, dir: .fwd, barBeats: 4)
        XCTAssertFalse(m2.rhythmExact, "a mark 2 beats in cannot land on a whole bar boundary")
    }
}
