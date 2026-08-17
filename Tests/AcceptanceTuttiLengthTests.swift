//  AcceptanceTuttiLengthTests.swift
//  ACCEPTANCE tests for the TUTTI + LENGTH processors — the expected output is computed FROM THE CONCEPT
//  (the spec / the AcceptanceCriteria docs / music theory), NOT read off the engine: Router.swift and
//  Derivations.swift were deliberately NOT consulted while writing these oracles. Each expectation is then
//  checked against the REAL Router via the shared `Accept` probe (120 BPM · column frozen · ~3 beats). If the
//  engine and an oracle disagree, ONE of them is wrong — and the oracle never saw the implementation.
//
//  SEEDED-BEHAVIOUR NOTE (how COIN is handled): TUTTI's COIN mode is a per-step SEEDED roll (a hash), so its
//  exact SOLO/TUTTI sequence is NOT reproducible by an independent oracle. Those tests therefore assert only
//  PROPERTIES that hold for ANY seed: the BALANCE extremes are seed-independent (balance 1 = every step TUTTI;
//  balance 0 = every step SOLO, so the surviving note is purely the PICK rank), and the interior is left as a
//  distribution (subset/non-empty). PATTERN mode (an authored per-slice shape) and all of LENGTH are EXACT.

import XCTest

// MARK: - TUTTI — set-level chance (COIN properties) + an EXACT per-slice SET-SHAPE oracle (PATTERN)

final class AcceptanceTuttiTests: XCTestCase {

    // ---- COIN: a seeded per-step roll, P(TUTTI)=balance → SOLO (one PICK-rank note) or TUTTI (the whole set).

    private func coin(balance: Double, pick: TuttiPick) -> ProcessorSlot {
        var t = ProcessorSlot(type: .tutti)
        t.params.tuttiMode = .coin
        t.params.tuttiBalance = balance
        t.params.tuttiPick = pick
        return t
    }

    func testCoinBalanceOneIsAlwaysTheWholeChord() {
        // P(TUTTI)=1 → every step passes the WHOLE set, regardless of PICK or the seed. Deterministic.
        for pick in TuttiPick.allCases {
            XCTAssertEqual(Accept.notesA([coin(balance: 1, pick: pick)]), [60, 64, 67],
                           "COIN balance=1 PICK=\(pick.rawValue): every step is TUTTI → the whole chord sounds")
        }
    }

    func testCoinBalanceZeroSoloPicksLowestAndHighest() {
        // P(TUTTI)=0 → every step is SOLO; the surviving note is the PICK RANK (LOW=lowest, HIGH=highest).
        // This is seed-INDEPENDENT: balance 0 forces SOLO on every step, so only one rank ever sounds.
        XCTAssertEqual(Accept.notesA([coin(balance: 0, pick: .low)]),  [60], "COIN balance=0 LOW → the root pedal (60)")
        XCTAssertEqual(Accept.notesA([coin(balance: 0, pick: .high)]), [67], "COIN balance=0 HIGH → the top note (67)")
    }

    func testCoinBalanceZeroRandomAndCycleStaySoloWithinTheChord() {
        // RANDOM/CYCLE walk the SOLO note by seed/step, so the exact set is NOT oracle-reproducible. But every
        // SOLO step still sounds exactly ONE chord member, so the run's set is a non-empty SUBSET of the chord.
        // (We do NOT assert |notesA| > 1: the frozen ~3-beat probe may not span enough steps to force a walk.)
        for pick in [TuttiPick.random, .cycle] {
            let ns = Accept.notesA([coin(balance: 0, pick: pick)])
            XCTAssertFalse(ns.isEmpty, "COIN balance=0 PICK=\(pick.rawValue) must still sound a SOLO note")
            XCTAssertTrue(ns.isSubset(of: [60, 64, 67]),
                          "COIN balance=0 PICK=\(pick.rawValue) may only sound chord notes, got \(ns.sorted())")
        }
    }

    // ---- PATTERN: an EXACT per-slice set-shape. For a pattern whose 8 slices are ALL the same state, the pitch
    //      SET sounded over the run is exactly that state's shape of the chord — clock/rotate-independent.

    /// The set a single PATTERN slice-state renders from an ASCENDING chord, authored from the spec palette
    /// (AcceptanceCriteria-tutti-processor §2): ALL · LOW · HIGH · TOP2 · BOT2 · LOW+8 · ALL−8 · REST.
    /// Pure oracle — no engine consulted.
    private func tuttiShape(_ state: TuttiSlice, _ asc: [Int]) -> Set<Int> {
        guard !asc.isEmpty else { return [] }
        switch state {
        case .all:        return Set(asc)                  // the whole set
        case .low:        return [asc.first!]              // the lowest
        case .high:       return [asc.last!]               // the highest
        case .top2:       return Set(asc.suffix(2))        // the two highest
        case .bot2:       return Set(asc.prefix(2))        // the two lowest
        case .lowOct:     return [asc.first! + 12]         // LOW+8: the lowest, up an octave
        case .allDownOct: return Set(asc.map { $0 - 12 })  // ALL−8: the whole set, down an octave
        case .rest:       return []                        // silent slice
        }
    }

    private func patternAllSame(_ state: TuttiSlice) -> ProcessorSlot {
        var t = ProcessorSlot(type: .tutti)
        t.params.tuttiMode = .pattern
        t.params.tuttiSlices = Array(repeating: state, count: 8)   // all 8 slices identical → set = the state's shape
        return t
    }

    func testPatternAllSameSliceSoundsTheStateShape() {
        let chord = [60, 64, 67]   // ascending C-E-G
        for state in TuttiSlice.allCases {
            XCTAssertEqual(Accept.notesA([patternAllSame(state)]), tuttiShape(state, chord),
                           "PATTERN all-\(state.rawValue) should sound \(tuttiShape(state, chord).sorted())")
        }
    }

    func testPatternKeySpotChecks() {
        // A few explicit anchors from the brief, so the shape oracle can't drift silently.
        XCTAssertEqual(Accept.notesA([patternAllSame(.high)]),       [67],           "all-HIGH → {67}")
        XCTAssertEqual(Accept.notesA([patternAllSame(.top2)]),       [64, 67],       "all-TOP2 → {64,67}")
        XCTAssertEqual(Accept.notesA([patternAllSame(.lowOct)]),     [72],           "all-LOW+8 → {72}")
        XCTAssertEqual(Accept.notesA([patternAllSame(.allDownOct)]), [48, 52, 55],   "all-ALL−8 → {48,52,55}")
        XCTAssertEqual(Accept.notesA([patternAllSame(.rest)]),       [],             "all-REST → {} (silence)")
    }
}

// MARK: - LENGTH — the per-slice GATE-OVERRIDE processor (DURATION axis only)

final class AcceptanceLengthTests: XCTestCase {
    // CONCEPT (AcceptanceCriteria-length-processor): 8 slices of the step, each PASS (sustain/tie, no re-attack) ·
    // MUTE (a rest) · SHORT (a staccato stab) · LONG (a re-attacked ring). LENGTH shapes DURATION/gaps only — it
    // never changes WHICH pitches sound (MUTE only removes a slice's onset). Standalone it carves the held chord.
    // note-ONS aren't clock-exact under the probe, so these assert SET membership + relative onset COUNTS, never
    // precise durations/off-times (which onsA can't see).

    private func length(_ slices: [LenState]) -> ProcessorSlot {
        precondition(slices.count == 8, "LENGTH paints 8 slices")
        var l = ProcessorSlot(type: .length)
        l.params.lenSlices = slices
        return l
    }
    private func all(_ s: LenState) -> ProcessorSlot { length(Array(repeating: s, count: 8)) }

    func testAllPassSustainsTheWholeChord() {
        XCTAssertEqual(Accept.notesA([all(.pass)]), [60, 64, 67], "all-PASS ties the held chord straight through")
    }

    func testAllMuteIsSilence() {
        XCTAssertTrue(Accept.onsA([all(.mute)]).isEmpty, "all-MUTE is a rest — no note-ons at all")
    }

    func testAllShortReArticulatesMoreThanAllPassTies() {
        let short = Accept.onsA([all(.short)]).count
        let pass  = Accept.onsA([all(.pass)]).count
        // PASS ties (no re-attack); SHORT re-attacks EVERY slice → strictly more onsets, and both non-zero.
        XCTAssertGreaterThan(pass, 0, "all-PASS must sound the chord at least once")
        XCTAssertGreaterThan(short, pass, "all-SHORT re-articulates every slice → more note-ons than the tied all-PASS")
    }

    func testMixedPatternSoundsTheChordWithGaps() {
        let mixed: [LenState] = [.mute, .pass, .pass, .pass, .mute, .pass, .pass, .pass]
        let ns = Accept.notesA([length(mixed)])
        XCTAssertEqual(ns, [60, 64, 67], "a MUTE/PASS mix still sounds the WHOLE chord")
        XCTAssertFalse(ns.isEmpty, "the mix is not all-MUTE, so it sounds")
        // Gaps: fewer onsets than re-articulating every slice with SHORT.
        XCTAssertLessThan(Accept.onsA([length(mixed)]).count, Accept.onsA([all(.short)]).count,
                          "the muted slices leave gaps → fewer onsets than all-SHORT")
    }

    func testLengthNeverInventsNotes() {
        // Duration axis ONLY: any slice pattern that isn't all-MUTE sounds a non-empty SUBSET of the held chord —
        // never a pitch outside {60,64,67}.
        let patterns: [[LenState]] = [
            [.short, .pass,  .long,  .mute,  .short, .pass,  .long,  .mute],
            [.long,  .long,  .short, .short, .pass,  .pass,  .mute,  .mute],
            [.mute,  .short, .mute,  .short, .mute,  .short, .mute,  .short],
            [.pass,  .mute,  .short, .long,  .pass,  .mute,  .short, .long],
        ]
        for p in patterns {
            let ns = Accept.notesA([length(p)])
            XCTAssertFalse(ns.isEmpty, "non-all-MUTE pattern \(p.map { $0.rawValue }) must sound something")
            XCTAssertTrue(ns.isSubset(of: [60, 64, 67]),
                          "LENGTH shapes only duration — pattern \(p.map { $0.rawValue }) leaked \(ns.sorted())")
        }
    }
}

// MARK: - [TUTTI PATTERN → LENGTH] — a downstream LENGTH now folds its gate onto each TUTTI slice hit (Paul 2026-08-17)

final class AcceptanceTuttiPatternLengthChainTests: XCTestCase {
    // CONCEPT: TUTTI PATTERN owns WHICH notes fire per slice; a downstream LENGTH then shapes each hit's DURATION —
    // MUTE = the slice rests, PASS = keep TUTTI's own length, SHORT/LONG = override the off. LENGTH must not change
    // WHICH pitches sound (MUTE only removes onsets). Locks the fix where LENGTH after TUTTI PATTERN was dropped
    // entirely (TUTTI isn't a note-DRIVER, so the per-note emitDriverNote fold never reached the LENGTH slot).

    private func pattern(_ state: TuttiSlice) -> ProcessorSlot {
        var t = ProcessorSlot(type: .tutti)
        t.params.tuttiMode = .pattern
        t.params.tuttiSlices = Array(repeating: state, count: 8)   // all 8 slices identical → set = the state's shape
        return t
    }
    private func lengthAll(_ s: LenState) -> ProcessorSlot {
        var l = ProcessorSlot(type: .length)
        l.params.lenSlices = Array(repeating: s, count: 8)
        return l
    }

    func testDownstreamLengthMuteSilencesTuttiPattern() {
        // THE REGRESSION: before the fix, LENGTH after TUTTI PATTERN was ignored → the chord sounded. all-MUTE rests.
        XCTAssertTrue(Accept.onsA([pattern(.all), lengthAll(.mute)]).isEmpty,
                      "[TUTTI PATTERN all-ALL → LENGTH all-MUTE] must be silent — every slice rests")
    }

    func testDownstreamLengthPassKeepsTuttiSelection() {
        // PASS keeps TUTTI's own gate and never alters pitch: the fold is duration-only.
        XCTAssertEqual(Accept.notesA([pattern(.high), lengthAll(.pass)]), [67],
                       "[TUTTI PATTERN all-HIGH → LENGTH all-PASS] keeps TUTTI's HIGH selection")
        XCTAssertEqual(Accept.notesA([pattern(.all), lengthAll(.pass)]), [60, 64, 67],
                       "[TUTTI PATTERN all-ALL → LENGTH all-PASS] keeps the whole set")
    }

    func testDownstreamLengthShapesDurationNotPitch() {
        // SHORT fires every slice (never drops), just shorter → the whole TUTTI set still sounds, no foreign pitch.
        XCTAssertEqual(Accept.notesA([pattern(.all), lengthAll(.short)]), [60, 64, 67],
                       "[TUTTI PATTERN all-ALL → LENGTH all-SHORT] shapes duration only — the whole set sounds")
    }

    func testDownstreamLengthMuteMaskDropsSlicesNotPitches() {
        // A MUTE/PASS LENGTH mask over an all-ALL TUTTI PATTERN leaves gaps but still sounds the WHOLE chord set.
        let mask: [LenState] = [.mute, .pass, .pass, .pass, .mute, .pass, .pass, .pass]
        var len = ProcessorSlot(type: .length); len.params.lenSlices = mask
        let ns = Accept.notesA([pattern(.all), len])
        XCTAssertEqual(ns, [60, 64, 67], "gaps from MUTE slices, but the surviving slices still sound the whole set")
    }
}
