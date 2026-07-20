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
                                                pattern: pi, pool: p).base }
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
            let a = arpPickSource(phaseIndex: t, octaves: 1, pattern: pi, pool: p).base
            let b = arpPickSource(phaseIndex: t, octaves: 1, pattern: pi, pool: p).base
            XCTAssertEqual(a, b, "RANDOM must be a pure function of the tick")
        }
        // and it should actually shuffle (not equal UP for this pool/length)
        let rnd = (0..<8).map { arpPickSource(phaseIndex: Int64($0), octaves: 1, pattern: pi, pool: p).base }
        let up = sequence(pattern: .up, octaves: 1, notes: [60, 62, 64, 65, 67], length: 8)
        XCTAssertNotEqual(rnd, up)
    }

    func testArpProvenanceChannel() {
        let p = NotePool()
        p.noteOn(60, velocity: 100, channel: 3)
        p.noteOn(64, velocity: 100, channel: 7)
        p.rebuildSorted()
        let up = UInt8(ArpPattern.allCases.firstIndex(of: .up)!)
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: p).chan, 3)
        XCTAssertEqual(arpPickSource(phaseIndex: 1, octaves: 1, pattern: up, pool: p).chan, 7)
    }

    func testEmptyPoolReturnsMinusOne() {
        let up = UInt8(ArpPattern.allCases.firstIndex(of: .up)!)
        XCTAssertEqual(arpPickSource(phaseIndex: 0, octaves: 1, pattern: up, pool: NotePool()).base, -1)
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
        XCTAssertEqual(p.channel(of: 60), 5)       // latest channel wins
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
        XCTAssertEqual(cellMode(type: .arp, bypassed: true, passMask: 0, pass: 0), .identity)   // bypass wins
        XCTAssertEqual(cellMode(type: .strum, bypassed: false, passMask: 0, pass: 0), .identity) // unimplemented
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
}
