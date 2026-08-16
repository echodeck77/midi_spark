//  AcceptanceGatesSpecialTests.swift
//  ACCEPTANCE tests (independent oracle) for the GATE / SEEDED / TAIL / TRANSLATOR / CC family:
//  PASSGATE · CHANCE · HUMANIZE · ECHO · GLIDE · MOD.
//
//  Same law as AcceptanceTests.swift: the EXPECTED output is reasoned FROM THE CONCEPT (spec §3 / the processor's
//  stated meaning / music sense), NEVER read off the engine, then checked against the REAL Router via the shared
//  `Accept` probe (120 BPM · 48 kHz · column frozen · ~3 beats · emitter-A note-ONs only).
//
//  ⚠ STRENGTH VARIES BY PROCESSOR — flagged inline and in the file's report:
//    · PASSGATE — an exact set/emptiness oracle (a pure boolean gate on the held chord).
//    · CHANCE   — PROPERTIES only: it is a SEEDED per-note-on hash, not concept-derivable exactly. p=1 / p=0 are
//                 exact; p=0.5 is asserted as a deterministic proper subset (seed-dependent membership).
//    · HUMANIZE — set-invariance + determinism are SOLID; "spread>0 perturbs timing/velocity" is a property.
//    · ECHO     — COUNT relationships + pitch SETS (echo timing/decay is not oracled exactly).
//    · GLIDE    — WEAK: GLIDE is a notes→pitch-BEND translator; `onsA` cannot see bend, only the mono anchor
//                 note-on. We assert the mono (≤1 concurrent) invariant + a weak priority lean.
//    · MOD      — note-SILENCE only: MOD is a CC generator and `onsA` cannot see CC. A real MOD acceptance test
//                 needs a CC-capturing probe (out of scope here).

import XCTest

// MARK: - PASSGATE — an exact SET / EMPTINESS oracle

final class AcceptancePassgateTests: XCTestCase {
    /// CONCEPT: PASSGATE is a boolean gate on the HELD chord — a 4-bit mask indexed by the lap counter (mod 4). On a
    /// lap whose bit is TRUE the whole chord passes unchanged; on a FALSE lap the chord is silent. So:
    ///   · all-true  → every lap passes  → the chord always sounds → notesA == {60,64,67}
    ///   · all-false → no lap passes      → total silence          → onsA empty
    ///   · a mixed mask with bit 0 TRUE   → at least the lap-0 evaluation passes → the chord sounds over the run,
    ///     so notesA == {60,64,67} (the DISTINCT set is the whole chord; we deliberately do NOT assert exact lap
    ///     timing, which depends on how the frozen run advances the lap counter).
    private func passgate(_ passes: [Bool]) -> ProcessorSlot {
        var s = ProcessorSlot(type: .passgate); s.params.passes = passes; return s
    }

    func testAllTruePassesTheWholeChord() {
        XCTAssertEqual(Accept.notesA([passgate([true, true, true, true])]), [60, 64, 67],
                       "PASSGATE all-true must pass the held chord unchanged")
    }

    func testAllFalseIsTotalSilence() {
        XCTAssertTrue(Accept.onsA([passgate([false, false, false, false])]).isEmpty,
                      "PASSGATE all-false must emit nothing on emitter A")
    }

    func testMixedMaskWithAnOpenLapStillSoundsTheChord() {
        // [true,false,false,false] — the bit-0 lap passes, so over the run the chord is heard (never continuously,
        // but its DISTINCT pitch set is the whole chord). Robust to whether the frozen run walks the lap counter.
        XCTAssertEqual(Accept.notesA([passgate([true, false, false, false])]), [60, 64, 67],
                       "PASSGATE with an open lap must let the chord sound (distinct set == chord)")
    }
}

// MARK: - CHANCE — SEEDED per-note-on probability gate: PROPERTIES only

final class AcceptanceChanceTests: XCTestCase {
    /// CONCEPT: CHANCE keeps each held note-on with probability p, decided by a SEEDED hash (replay-safe). The exact
    /// membership at 0<p<1 is a hash, so it is NOT concept-derivable — we assert PROPERTIES:
    ///   · p=1   → every note passes  → notesA == {60,64,67}   (exact)
    ///   · p=0   → no note passes      → onsA empty              (exact)
    ///   · p=0.5 → a deterministic PROPER SUBSET of the p=1 stream: it drops SOME but not all, and re-running is
    ///     byte-identical (seeded). Membership itself is a hash — only the count relationship + determinism are
    ///     asserted (see the note below).
    private func chance(_ p: Double) -> ProcessorSlot {
        var s = ProcessorSlot(type: .chance); s.params.probability = p; return s
    }

    func testProbabilityOnePassesEverything() {
        XCTAssertEqual(Accept.notesA([chance(1)]), [60, 64, 67], "CHANCE p=1 must pass every note")
    }

    func testProbabilityZeroPassesNothing() {
        XCTAssertTrue(Accept.onsA([chance(0)]).isEmpty, "CHANCE p=0 must drop every note")
    }

    func testProbabilityHalfIsADeterministicProperSubset() {
        let full = Accept.onsA([chance(1)])          // the all-pass reference stream
        let half = Accept.onsA([chance(0.5)])
        // PROPERTY (seed-dependent): 0.5 lets SOME through but strictly fewer note-ons than the all-pass run.
        // Exact membership is a hash — NOT asserted. If this ever proves flaky it is the seed, not a real bug.
        XCTAssertFalse(half.isEmpty, "CHANCE p=0.5 should pass at least one note-on over the run")
        XCTAssertLessThan(half.count, full.count, "CHANCE p=0.5 should pass fewer note-ons than p=1")
        XCTAssertTrue(Set(half.map { $0.note }).isSubset(of: [60, 64, 67]), "CHANCE never invents notes")
    }

    func testChanceIsDeterministicAcrossRuns() {
        // Replay-safe: the same chain + chord + seed yields a byte-identical note-on stream.
        XCTAssertEqual(Accept.onsA([chance(0.5)]), Accept.onsA([chance(0.5)]),
                       "CHANCE must be deterministic (seeded hash, replay-safe)")
    }
}

// MARK: - HUMANIZE — SEEDED per-note timing+velocity jitter: SET-INVARIANCE + DETERMINISM solid

final class AcceptanceHumanizeTests: XCTestCase {
    /// CONCEPT: HUMANIZE applies a seeded, replay-safe per-note jitter to timing + velocity. It NEVER drops or adds
    /// notes — the sounding pitch SET is invariant. `spread` = the jitter amount. So:
    ///   · SOLID: notesA == {60,64,67} for ANY spread (set-invariance).
    ///   · SOLID: onsA is deterministic across runs (replay-safe).
    ///   · PROPERTY: spread>0 actually perturbs SOMETHING (onset bucket and/or velocity), so its stream differs
    ///     from spread=0. Seed-dependent in magnitude — a property, not an exact oracle.
    private func humanize(_ spread: Double) -> ProcessorSlot {
        var s = ProcessorSlot(type: .humanize); s.params.spread = spread; return s
    }

    func testHumanizeNeverChangesTheNoteSet() {
        for spread in [0.0, 0.1, 0.5, 1.0] {
            XCTAssertEqual(Accept.notesA([humanize(spread)]), [60, 64, 67],
                           "HUMANIZE spread \(spread) must keep the exact note set (no drop/add)")
        }
    }

    func testHumanizeIsDeterministic() {
        XCTAssertEqual(Accept.onsA([humanize(0.7)]), Accept.onsA([humanize(0.7)]),
                       "HUMANIZE must be replay-safe (seeded)")
    }

    func testHumanizeWithSpreadActuallyPerturbs() {
        // PROPERTY: a large spread must change the onset buckets and/or velocities vs no jitter — else HUMANIZE is
        // a no-op. The note SET stays equal (asserted above); only timing/velocity may move.
        XCTAssertNotEqual(Accept.onsA([humanize(1.0)]), Accept.onsA([humanize(0.0)]),
                          "HUMANIZE spread>0 should perturb timing or velocity (does something)")
    }
}

// MARK: - ECHO — COUNT relationships + pitch SETS (timing/decay not oracled exactly)

final class AcceptanceEchoTests: XCTestCase {
    /// CONCEPT: ECHO repeats each note at delayed beats — `echoRepeats` decaying copies; THRU passes the dry note,
    /// MUTE emits echoes only; `echoPitch` transposes each successive echo. We oracle the ROBUST facts:
    ///   · THRU adds the dry note + echoes → MORE onsets than a bare passthrough.
    ///   · more repeats → more onsets (count(6) > count(2)) — with a SHORT synced delay so both fit the ~3-beat run.
    ///   · pitch=0 → the echoes are the same pitches → notesA == {60,64,67}.
    ///   · pitch=+12 → the first echo adds the chord transposed up an octave → notesA ⊇ {72,76,79}.
    ///   · MUTE (thru=false) with pitch=0 → echoes only, still sounds, notesA ⊆ {60,64,67} and non-empty.
    /// (Echo timing/decay/exact tail counts are NOT oracled — only counts + pitch sets.)
    private func echo(repeats: Int, thru: Bool = true, pitch: Int = 0, delayDiv: Int = 2) -> ProcessorSlot {
        var s = ProcessorSlot(type: .echo)
        s.params.echoSync = true
        s.params.echoDelayDiv = delayDiv   // synced 16ths; 2 = a 1/2-beat delay so several echoes land inside the run
        s.params.echoRepeats = repeats
        s.params.echoThru = thru
        s.params.echoPitch = pitch
        return s
    }

    func testThruAddsEchoesOnTopOfTheDryNote() {
        let dry = Accept.onsA([]).count                      // bare passthrough (the harness's born-audible identity)
        let wet = Accept.onsA([echo(repeats: 3, thru: true)]).count
        XCTAssertGreaterThan(wet, dry, "ECHO THRU must add echoes on top of the dry note-ons")
    }

    func testMoreRepeatsMeansMoreOnsets() {
        let few = Accept.onsA([echo(repeats: 2)]).count
        let many = Accept.onsA([echo(repeats: 6)]).count
        XCTAssertGreaterThan(many, few, "ECHO with more repeats must emit more onsets")
    }

    func testPitchZeroEchoesTheSamePitches() {
        XCTAssertEqual(Accept.notesA([echo(repeats: 3, pitch: 0)]), [60, 64, 67],
                       "ECHO pitch=0 echoes must be the same pitches as the source chord")
    }

    func testPitchClimbAddsTransposedEchoes() {
        // First echo = source + 12 → the octave-up chord must appear in the sounding set (THRU keeps the dry too).
        let notes = Accept.notesA([echo(repeats: 3, thru: true, pitch: 12)])
        XCTAssertTrue(notes.isSuperset(of: [72, 76, 79]),
                      "ECHO pitch=+12 must add the chord transposed up an octave; got \(notes.sorted())")
    }

    func testMuteEmitsEchoesOnlyStillSounding() {
        let notes = Accept.notesA([echo(repeats: 3, thru: false, pitch: 0)])
        XCTAssertFalse(notes.isEmpty, "ECHO MUTE (thru=false) still sounds — the echoes alone")
        XCTAssertTrue(notes.isSubset(of: [60, 64, 67]), "ECHO MUTE pitch=0 echoes stay within the chord's pitches")
    }
}

// MARK: - GLIDE — WEAK: a notes→pitch-BEND translator (onsA sees only the mono anchor note-on)

final class AcceptanceGlideTests: XCTestCase {
    /// CONCEPT (weakly observable): GLIDE is ONE mono sliding voice tracking the priority note. It emits pitch-BEND
    /// for in-range moves — which `onsA` CANNOT see — plus a note-ON when it anchors / re-anchors. So the only
    /// solid observable is the MONO invariant: at most one distinct note sounds at any instant.
    ///   · SOLID-ish: within any onset bucket there is ≤1 distinct note (mono — no chord ever stacks).
    ///   · WEAK: the anchored pitch leans toward the priority note (LOW → 60, HIGH → 67). Bend is invisible and the
    ///     anchor may re-anchor, so this is asserted as "contains the leaned note OR onsA is empty (bend-only)".
    /// FLAG: this is the weakest oracle in the file — GLIDE's real behaviour lives in the pitch-bend stream.
    private func glide(_ priority: GlidePriority) -> ProcessorSlot {
        var s = ProcessorSlot(type: .glide); s.params.glidePriority = priority; return s
    }

    /// The MONO invariant: bucket the note-ons by onset and assert no bucket carries two distinct pitches.
    private func assertMono(_ ons: [AcceptEvent], _ label: String) {
        var byOnset: [Int: Set<Int>] = [:]
        for e in ons { byOnset[e.onset, default: []].insert(e.note) }
        for (onset, notes) in byOnset {
            XCTAssertLessThanOrEqual(notes.count, 1, "GLIDE \(label): >1 note at onset \(onset) — not mono (\(notes.sorted()))")
        }
    }

    func testGlideIsMonoUnderEveryPriority() {
        for p in [GlidePriority.last, .low, .high] {
            assertMono(Accept.onsA([glide(p)]), "\(p)")   // holds vacuously if the voice is bend-only (empty)
        }
    }

    func testGlidePriorityLeansTowardTheChosenNote() {
        // WEAK: if the mono voice sounds any note-on, LOW should include the low note and HIGH the high note.
        // Guarded with "or empty" because an in-range glide can be pure bend (no captured note-on).
        let low = Accept.notesA([glide(.low)])
        let high = Accept.notesA([glide(.high)])
        XCTAssertTrue(low.isEmpty || low.contains(60), "GLIDE LOW should anchor/lean to the low note 60; got \(low.sorted())")
        XCTAssertTrue(high.isEmpty || high.contains(67), "GLIDE HIGH should anchor/lean to the high note 67; got \(high.sorted())")
    }
}

// MARK: - MOD — a CC generator: NOTE-SILENCE only (onsA cannot see CC)

final class AcceptanceModTests: XCTestCase {
    /// CONCEPT: MOD is a CC generator (a beat-derived shaped CC on the cell's emitters). It sounds NO notes. `onsA`
    /// captures note-ONs only, so the only thing observable here is that MOD is note-silent by design.
    /// ⚠ A PROPER MOD acceptance test needs a CC-CAPTURING probe (the shape/rate/min-max of the emitted CC) — that
    /// is OUT OF SCOPE for this harness. This test ONLY verifies note-silence; it says nothing about the CC itself.
    func testModEmitsNoNotesOnEmitterA() {
        var s = ProcessorSlot(type: .mod)
        s.params.modCC = 74
        s.params.modSource = .shape
        s.params.modShape = .sine
        XCTAssertTrue(Accept.onsA([s]).isEmpty,
                      "MOD is a CC generator — it must emit no note-ons (CC is not captured by this probe)")
    }
}
