//  DerivationsTests.swift
//  Off-device unit tests for MidiSpark's pure engine core (Derivations.swift + Models.swift enums).
//  These run in seconds via `xcodebuild test` — no simulator, no iPad, no ears. They guard the
//  regression-prone math: swing warp + inverse, phase modes, arp patterns, dispatch, ratchet ramp.

import XCTest

final class DerivationsTests: XCTestCase {

    // MARK: swing warp (§4)

    func testSwingIdentityAt50() {
        // a = swing/50 = 1 at 50%: musical == real, exactly.
        for beat in stride(from: 0.0, through: 8.0, by: 0.13) {
            XCTAssertEqual(musicalOf(beat, stepBeats: 2, a: 1), beat, accuracy: 1e-9)
            XCTAssertEqual(realOf(beat, stepBeats: 2, a: 1), beat, accuracy: 1e-9)
        }
    }

    func testSwingIsInvertible() {
        // realOf ∘ musicalOf == identity for any swing amount and step (round-trip, no drift).
        for a in [1.0, 1.2, 1.5] {          // swing 50, 60, 75
            for S in [0.5, 1.0, 2.0, 3.0] {
                for beat in stride(from: 0.0, through: 12.0, by: 0.37) {
                    let round = realOf(musicalOf(beat, stepBeats: S, a: a), stepBeats: S, a: a)
                    XCTAssertEqual(round, beat, accuracy: 1e-9, "S=\(S) a=\(a) beat=\(beat)")
                }
            }
        }
    }

    func testSwingWarpsStepPairs() {
        // At swing > 50 the first step of each pair is stretched (its musical midpoint lands early).
        let a = 1.5, S = 1.0
        // musical position of the real halfway point of step 0 should be < 0.5 (compressed forward)
        XCTAssertLessThan(musicalOf(0.5, stepBeats: S, a: a), 0.5)
    }

    // MARK: phase modes (§3.5)

    func testRetrigRestartsEachColumn() {
        // RETRIG: index resets to 0 at each column (step) start.
        let arp = 0.25, S = 2.0, cyc = 16.0
        // column 0 start (beat 0) and column 1 start (beat 2) both → phase 0
        XCTAssertEqual(phaseIndex(tick: 0, mTickBeat: 0, arpBeats: arp, S: S, cycleBeats: cyc,
                                  phase: .retrig, runStartColumn: -1), 0)
        let tickAtCol1 = Int64(2.0 / arp)   // 8
        XCTAssertEqual(phaseIndex(tick: tickAtCol1, mTickBeat: 2.0, arpBeats: arp, S: S, cycleBeats: cyc,
                                  phase: .retrig, runStartColumn: -1), 0)
    }

    func testFreeIsAbsolute() {
        // FREE: phase index == absolute tick, never resets.
        XCTAssertEqual(phaseIndex(tick: 37, mTickBeat: 9.25, arpBeats: 0.25, S: 2, cycleBeats: 16,
                                  phase: .free, runStartColumn: -1), 37)
    }

    func testLegatoCountsFromRunStart() {
        // LEGATO run starting at column 4: at column 5 the index continues (doesn't reset).
        let arp = 0.5, S = 2.0, cyc = 16.0, runStart: Int8 = 4
        // column 4 start = beat 8 → phase 0; column 5 start = beat 10 → phase 4 (4 ticks of 0.5 in)
        XCTAssertEqual(phaseIndex(tick: Int64(8.0 / arp), mTickBeat: 8.0, arpBeats: arp, S: S,
                                  cycleBeats: cyc, phase: .legato, runStartColumn: runStart), 0)
        XCTAssertEqual(phaseIndex(tick: Int64(10.0 / arp), mTickBeat: 10.0, arpBeats: arp, S: S,
                                  cycleBeats: cyc, phase: .legato, runStartColumn: runStart), 4)
    }

    // MARK: arp patterns (§3)

    private func pool(_ notes: [UInt8]) -> NotePool {
        let p = NotePool()
        for n in notes { p.noteOn(n, velocity: 100, channel: 0) }
        p.rebuildSorted()
        return p
    }

    private func sequence(pattern: ArpPattern, octaves: Int, notes: [UInt8], length: Int) -> [Int] {
        let p = pool(notes)
        let pi = UInt8(ArpPattern.allCases.firstIndex(of: pattern)!)
        return (0..<length).map { arpPickSource(phaseIndex: Int64($0), octaves: octaves,
                                                pattern: pi, pool: p) }
    }

    func testPatternUp() {
        XCTAssertEqual(sequence(pattern: .up, octaves: 1, notes: [60, 64, 67], length: 6),
                       [60, 64, 67, 60, 64, 67])
    }

    func testPatternDown() {
        XCTAssertEqual(sequence(pattern: .down, octaves: 1, notes: [60, 64, 67], length: 6),
                       [67, 64, 60, 67, 64, 60])
    }

    func testPatternUpDownNoRepeatedEnds() {
        // C E G with UP-DN: C E G E | C E G E …  (top and bottom each hit once per period)
        XCTAssertEqual(sequence(pattern: .upDown, octaves: 1, notes: [60, 64, 67], length: 8),
                       [60, 64, 67, 64, 60, 64, 67, 64])
    }

    func testPatternUpOctaves() {
        // 2 octaves: base then +12 across the span.
        XCTAssertEqual(sequence(pattern: .up, octaves: 2, notes: [60, 64], length: 4),
                       [60, 64, 72, 76])
    }

    func testPatternAsPlayed() {
        // Pressed 67, 60, 64 (not ascending) → AS-PLAYED follows PRESS order, not pitch…
        XCTAssertEqual(sequence(pattern: .asPlayed, octaves: 1, notes: [67, 60, 64], length: 6),
                       [67, 60, 64, 67, 60, 64])
        // …while UP on the same pool sorts to pitch order.
        XCTAssertEqual(sequence(pattern: .up, octaves: 1, notes: [67, 60, 64], length: 3),
                       [60, 64, 67])
    }

    func testRandomIsLoopConsistent() {
        // Same tick → same note every pass. Compare pass 0 with pass 1 (span apart).
        let p = pool([60, 62, 64, 65, 67])
        let pi = UInt8(ArpPattern.allCases.firstIndex(of: .random)!)
        let span = Int64(p.count)   // octaves 1
        for t in 0..<span {
            let a = arpPickSource(phaseIndex: t, octaves: 1, pattern: pi, pool: p)
            let b = arpPickSource(phaseIndex: t, octaves: 1, pattern: pi, pool: p)
            XCTAssertEqual(a, b, "RANDOM must be a pure function of the tick")
        }
        // and it should actually shuffle (not equal UP for this pool/length)
        let rnd = (0..<8).map { arpPickSource(phaseIndex: Int64($0), octaves: 1, pattern: pi, pool: p) }
        let up = sequence(pattern: .up, octaves: 1, notes: [60, 62, 64, 65, 67], length: 8)
        XCTAssertNotEqual(rnd, up)
    }

    // (Provenance channel removed with delta §7 — a note carries no channel past the input filter;
    //  channel behaviour is covered by the input-channel filter tests below.)

    func testEmptyPoolReturnsMinusOne() {
        let up = UInt8(ArpPattern.allCases.firstIndex(of: .up)!)
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: NotePool()), -1)
    }

    // MARK: input-channel filter (delta §7)

    private func mixedPool() -> NotePool {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0)   // ch 1 (wire 0)
        p.noteOn(64, velocity: 100, channel: 1)   // ch 2 (wire 1)
        p.noteOn(67, velocity: 100, channel: 0)   // ch 1
        p.rebuildSorted()
        return p
    }

    func testSrcCountFilter() {
        let p = mixedPool()
        XCTAssertEqual(p.srcCount(filter: 0), 3)   // OMNI = all
        XCTAssertEqual(p.srcCount(filter: 1), 2)   // ch 1 → 60, 67
        XCTAssertEqual(p.srcCount(filter: 2), 1)   // ch 2 → 64
        XCTAssertEqual(p.srcCount(filter: 5), 0)   // nothing on ch 5
    }

    func testSrcAscendingFilter() {
        let p = mixedPool()
        XCTAssertEqual(p.srcAscending(0, filter: 1), 60)   // ch-1 notes ascending: 60, 67
        XCTAssertEqual(p.srcAscending(1, filter: 1), 67)
        XCTAssertEqual(p.srcAscending(0, filter: 2), 64)   // ch-2: 64
    }

    func testArpPickSourceHonoursFilter() {
        let p = mixedPool()
        let up = UInt8(ArpPattern.allCases.firstIndex(of: .up)!)
        // filter ch 1: the arp cycles only 60 and 67
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: p, filter: 1), 60)
        XCTAssertEqual(arpPickSource(phaseIndex: 1, octaves: 1, pattern: up, pool: p, filter: 1), 67)
        XCTAssertEqual(arpPickSource(phaseIndex: 2, octaves: 1, pattern: up, pool: p, filter: 1), 60)  // wraps (span 2)
        // filter ch 5: empty → −1
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: p, filter: 5), -1)
        // OMNI default unchanged from pre-filter behaviour
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: p), 60)
    }

    // MARK: NotePool (§2.5)

    func testPoolSortsAndCounts() {
        let p = pool([67, 60, 64])
        XCTAssertEqual(p.count, 3)
        XCTAssertEqual(Array(p.sorted[0..<3]), [60, 64, 67])   // ascending regardless of press order
    }

    func testPoolNoteOffAndOmniMerge() {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 0)
        p.noteOn(60, velocity: 100, channel: 5)   // same note, different channel → merges (omni)
        p.rebuildSorted()
        XCTAssertEqual(p.count, 1)
        // latest channel wins — observable through the input filter (wire ch 5 = filter 6):
        XCTAssertEqual(p.srcCount(filter: 6), 1)   // now on ch 5
        XCTAssertEqual(p.srcCount(filter: 1), 0)   // no longer on ch 0
        p.noteOff(60)
        p.rebuildSorted()
        XCTAssertEqual(p.count, 0)
    }

    func testPlayOrderCompactsOnRelease() {
        let p = NotePool()
        p.noteOn(67, velocity: 100, channel: 0)
        p.noteOn(60, velocity: 100, channel: 0)
        p.noteOn(64, velocity: 100, channel: 0)
        XCTAssertEqual((0..<p.playedCount).map { p.played(at: $0) }, [67, 60, 64])
        p.noteOff(60)   // release the middle one
        XCTAssertEqual((0..<p.playedCount).map { p.played(at: $0) }, [67, 64])   // compacts, order kept
        p.noteOn(67, velocity: 110, channel: 0)   // re-press a held note → keeps its slot
        XCTAssertEqual((0..<p.playedCount).map { p.played(at: $0) }, [67, 64])
    }

    // MARK: cellMode dispatch (§3/§4)

    func testCellModeBasics() {
        XCTAssertEqual(cellMode(type: .arp, bypassed: false, passMask: 0, pass: 0), .arp)
        XCTAssertEqual(cellMode(type: .ratchet, bypassed: false, passMask: 0, pass: 0), .ratchet)
        XCTAssertEqual(cellMode(type: .strum, bypassed: false, passMask: 0, pass: 0), .strum)
        XCTAssertEqual(cellMode(type: .chance, bypassed: false, passMask: 0, pass: 0), .chance)
        XCTAssertEqual(cellMode(type: .harmonize, bypassed: false, passMask: 0, pass: 0), .harmonize)
        XCTAssertEqual(cellMode(type: .harmonize, bypassed: true, passMask: 0, pass: 0), .identity)  // bypass wins
    }

    func testPassgateGating() {
        let mask: UInt8 = 0b0101   // open on pass 0 and 2
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 0), .identity)
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 1), .silent)
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 2), .identity)
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 3), .silent)
        XCTAssertEqual(cellMode(type: .passgate, bypassed: false, passMask: mask, pass: 4), .identity) // wraps mod 4
    }

    // MARK: ratchet velocity (§3)

    func testRatchetVelocityFlatWhenRampZero() {
        for i in 0..<4 {
            XCTAssertEqual(ratchetVelocity(base: 96, ramp: 0, index: i, count: 4), 96)
        }
    }

    func testRatchetVelocityCrescendo() {
        // ramp 1: first hit softest, last hit == base, monotonically increasing.
        let vels = (0..<4).map { ratchetVelocity(base: 96, ramp: 1, index: $0, count: 4) }
        XCTAssertLessThan(vels[0], vels[3])
        for i in 1..<4 { XCTAssertGreaterThanOrEqual(vels[i], vels[i - 1]) }
        XCTAssertEqual(vels[3], 96)          // last reaches base
        XCTAssertGreaterThanOrEqual(vels[0], 1)  // never a note-off velocity
    }

    // MARK: strum (§3)

    func testStrumOffsetEndpointsAndMonotonic() {
        let spread = 0.4, K = 5
        XCTAssertEqual(strumOffset(index: 0, count: K, spread: spread, curve: 0), 0, accuracy: 1e-9)
        XCTAssertEqual(strumOffset(index: K - 1, count: K, spread: spread, curve: 0), spread, accuracy: 1e-9)
        var prev = -1.0
        for j in 0..<K {
            let off = strumOffset(index: j, count: K, spread: spread, curve: 0)
            XCTAssertGreaterThan(off, prev); prev = off      // strictly increasing
        }
        // curve 0 is linear
        XCTAssertEqual(strumOffset(index: 2, count: K, spread: spread, curve: 0), spread * 0.5, accuracy: 1e-9)
    }

    func testStrumOffsetSingleNote() {
        XCTAssertEqual(strumOffset(index: 0, count: 1, spread: 0.4, curve: 0), 0)   // nothing to spread
    }

    func testStrumCurveBunchesEnds() {
        // curve>0: early notes bunched (midpoint offset < linear half); curve<0: opposite.
        let mid = { (c: Double) in strumOffset(index: 2, count: 5, spread: 1.0, curve: c) }
        XCTAssertLessThan(mid(1), mid(0))       // positive curve pulls the midpoint earlier
        XCTAssertGreaterThan(mid(-1), mid(0))
    }

    func testStrumVelocityTilt() {
        XCTAssertEqual(strumVelocity(index: 0, count: 4, tilt: 0, base: 96), 96)   // flat
        let up = (0..<4).map { strumVelocity(index: $0, count: 4, tilt: 1, base: 96) }
        XCTAssertLessThan(up[0], up[3])                                            // crescendo
        let down = (0..<4).map { strumVelocity(index: $0, count: 4, tilt: -1, base: 96) }
        XCTAssertGreaterThan(down[0], down[3])                                     // decrescendo
    }

    // MARK: chance (§3)

    func testChanceExtremes() {
        XCTAssertTrue(chancePasses(beat: 3.25, note: 60, probability: 1))    // 100% always passes
        XCTAssertFalse(chancePasses(beat: 3.25, note: 60, probability: 0))   // 0% never passes
    }

    func testChanceIsDeterministic() {
        // Pure function of (beat, note) → loop-consistent (same position, same fate).
        for beat in stride(from: 0.0, through: 8.0, by: 0.25) {
            for note in [48, 60, 72] {
                XCTAssertEqual(chancePasses(beat: beat, note: note, probability: 0.5),
                               chancePasses(beat: beat, note: note, probability: 0.5))
            }
        }
    }

    func testChanceRoughlyHalfAtFifty() {
        var pass = 0, total = 0
        for t in 0..<300 {
            for note in [55, 60, 65] {
                if chancePasses(beat: Double(t) * 0.25, note: note, probability: 0.5) { pass += 1 }
                total += 1
            }
        }
        let frac = Double(pass) / Double(total)
        XCTAssertGreaterThan(frac, 0.42); XCTAssertLessThan(frac, 0.58)   // ~50%, not degenerate
    }

    func testStrumDirection() {
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .up, pass: 0), 0)   // low first
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .down, pass: 0), 3) // high first
        // ALTERNATE: up on even passes, down on odd
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .alternate, pass: 0), 0)
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .alternate, pass: 1), 3)
        XCTAssertEqual(strumSortedIndex(position: 0, count: 4, direction: .alternate, pass: 2), 0)
    }

    // MARK: harmonize (§3)

    private func harmonize(_ base: Int, _ intervals: (Int8, Int8, Int8),
                           vel: UInt8 = 96, scale: Double = 0.8) -> (notes: [Int], vels: [UInt8]) {
        var notes = [Int](repeating: 0, count: 4), vels = [UInt8](repeating: 0, count: 4)
        let n = harmonizeVoices(base: base, intervals: intervals, into: &notes,
                                vel: vel, velScale: scale, vels: &vels)
        return (Array(notes[0..<n]), Array(vels[0..<n]))
    }

    func testHarmonizeMajorTriad() {
        // C (60) + [4, 7, 0] → C E G. Root first, then the two non-zero intervals; a 0 voice is off.
        XCTAssertEqual(harmonize(60, (4, 7, 0)).notes, [60, 64, 67])
    }

    func testHarmonizeRootFullAddedScaled() {
        let (notes, vels) = harmonize(60, (7, 0, 0), vel: 100, scale: 0.5)
        XCTAssertEqual(notes, [60, 67])
        XCTAssertEqual(vels[0], 100)   // root full
        XCTAssertEqual(vels[1], 50)    // added voice scaled
    }

    func testHarmonizeNoIntervalsIsIdentity() {
        XCTAssertEqual(harmonize(60, (0, 0, 0)).notes, [60])   // all off → just the root
    }

    func testHarmonizeDeDupesAndClampsRange() {
        // A +12 that lands on a held-elsewhere pitch would refcount; within one call, a unison de-dups.
        XCTAssertEqual(harmonize(60, (0, 12, 12)).notes, [60, 72])   // duplicate +12 collapses
        // out-of-range voices are dropped, root kept
        XCTAssertEqual(harmonize(120, (24, 0, 0)).notes, [120])      // 120+24=144 > 127 → dropped
        XCTAssertEqual(harmonize(5, (-24, 0, 0)).notes, [5])         // 5-24 < 0 → dropped
    }

    // MARK: - COLUMN-SUBSET LAP (§5b)

    func testLapPassthroughWhenNothingHeld() {
        for step in 0..<16 { XCTAssertEqual(lapColumn(laneMask: 0, absoluteStep: step, trueColumn: step % 8), step % 8) }
    }

    func testLapStutterK1LocksToTheHeldColumn() {
        let mask: UInt8 = 1 << 2                                   // hold column 2 only
        for step in 0..<20 { XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: step, trueColumn: step % 8), 2) }
    }

    func testLapContiguousK2Alternates() {
        let mask: UInt8 = (1 << 3) | (1 << 4)                     // hold columns 3,4 (loop brace)
        let got = (0..<6).map { lapColumn(laneMask: mask, absoluteStep: $0, trueColumn: $0 % 8) }
        XCTAssertEqual(got, [3, 4, 3, 4, 3, 4])
    }

    func testLapK3RotatesAsPolymeterAgainstTheEightStep() {
        // Hold three columns {1,3,5}: the 3-cycle phases against the 8-step timeline and is NEVER reset
        // at the pass boundary (step 8 continues the rotation, landing off-phase vs the grid).
        let mask: UInt8 = (1 << 1) | (1 << 3) | (1 << 5)
        let got = (0..<9).map { lapColumn(laneMask: mask, absoluteStep: $0, trueColumn: $0 % 8) }
        XCTAssertEqual(got, [1, 3, 5, 1, 3, 5, 1, 3, 5])          // step 8 → index 2 → col 5, not reset to col 1
    }

    func testLapSortsHeldColumnsLeftToRight() {
        // The mask bit order IS left→right regardless of the "order pressed" — sorted wins (spec).
        let mask: UInt8 = (1 << 6) | (1 << 0)                     // columns 0 and 6
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: 0, trueColumn: 0), 0)   // leftmost first
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: 1, trueColumn: 1), 6)
    }

    func testLapNegativeStepIsSafe() {
        let mask: UInt8 = (1 << 2) | (1 << 4)
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: -1, trueColumn: 0), 4)  // (-1 mod 2) → index 1
        XCTAssertEqual(lapColumn(laneMask: mask, absoluteStep: -2, trueColumn: 0), 2)
    }

    // MARK: - column sweep fraction (mutation-line / §6b chip playhead)

    func testColumnSweepFractionSwingAwareSpansTheRealColumn() {
        let S = 1.0
        // swing 50: identity — the raw fraction.
        XCTAssertEqual(columnSweepFraction(realBeat: 0.0, stepBeats: S, swing: 50), 0.0, accuracy: 1e-9)
        XCTAssertEqual(columnSweepFraction(realBeat: 0.5, stepBeats: S, swing: 50), 0.5, accuracy: 1e-9)

        // swing 62 stretches the FIRST column to realOf(S) > S raw beats. The raw fraction would WRAP to
        // 0 at real beat 1.0 (the bug); the swing-aware fraction is still mid-sweep there and only wraps
        // at the true (swung) column end.
        let colEnd = realOf(1.0, stepBeats: S, a: 62.0 / 50.0)         // ≈ 1.24
        XCTAssertGreaterThan(colEnd, 1.0, "swing stretches the first column past 1 raw beat")
        let fAtRawWrap = columnSweepFraction(realBeat: 1.0, stepBeats: S, swing: 62)
        XCTAssertGreaterThan(fAtRawWrap, 0.5, "still sweeping at real 1.0 — NOT wrapped early")
        XCTAssertLessThan(fAtRawWrap, 1.0)
        XCTAssertEqual(columnSweepFraction(realBeat: 0.0, stepBeats: S, swing: 62), 0.0, accuracy: 1e-9)
        XCTAssertEqual(columnSweepFraction(realBeat: colEnd - 1e-4, stepBeats: S, swing: 62), 1.0, accuracy: 1e-3)
        XCTAssertEqual(columnSweepFraction(realBeat: colEnd, stepBeats: S, swing: 62), 0.0, accuracy: 1e-9)  // wraps AT the column end
    }
}
