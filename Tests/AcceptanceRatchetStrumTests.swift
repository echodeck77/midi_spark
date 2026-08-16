//  AcceptanceRatchetStrumTests.swift
//  ACCEPTANCE tests for RATCHET and STRUM — INDEPENDENT ORACLES. The expected output is computed FROM THE CONCEPT
//  (spec v2.8 §3 + music theory), NEVER derived from the engine's code (Router/Derivations were not read while
//  writing this), then checked against the REAL Router's output via the shared `Accept` probe (see AcceptanceTests.swift:
//  a held chord through the real engine, 120 BPM, column frozen, ~3 beats; `onsA` = every emitter-A note-on as
//  (note, vel, onset-bucket) sorted by (onset, note)).
//
//  RATCHET (§3): "repeats 2/3/4/6/8 · velocity ramp 0–100%". CONCEPT — re-strikes the WHOLE held chord `count` times
//  per step (a subdivided repeat); the ramp shapes the velocity across the successive strikes.
//  STRUM (§3): "direction UP/DOWN/ALTERNATE · spread 10 ms–1 beat · curve ±100 · velocity tilt ±100". CONCEPT — rolls
//  the held chord IN over `spread` beats, each note entering at a staggered onset in `strumDir` order, then sustaining;
//  velTilt tilts the velocity across the roll.
//
//  CONVENTION ASSERT-AROUNDS (undefined-by-spec, so we assert a PROPERTY/SET, never a guessed value):
//   • The exact per-strike velocity a ramp produces, and the exact roll gap a spread produces, are engine conventions.
//     We assert RATIOS / ORDER / SETS / relative comparisons that hold for ANY reasonable convention (S-independent).
//   • The "neutral" point of ramp / velTilt is not pinned here, so the "does something" tests assert that SOME setting
//     in a spread of values yields non-flat velocities (an existence property), not that a specific value is flat.

import XCTest

// MARK: - RATCHET — SET · COUNT-RATIO · FULL-CHORD-PER-STRIKE · RAMP-property oracle

final class AcceptanceRatchetTests: XCTestCase {
    private let chordNotes: Set<Int> = [60, 64, 67]

    /// A single RATCHET slot. gate mirrors the harness example (0.6); ramp defaults to a mid value.
    private func ratchet(count: Int, ramp: Double = 0.5, gate: Double = 0.6) -> ProcessorSlot {
        var s = ProcessorSlot(type: .ratchet)
        s.params.count = count
        s.params.ramp = ramp
        s.params.gate = gate
        return s
    }

    private func velsNonFlat(_ events: [AcceptEvent]) -> Bool { Set(events.map { $0.vel }).count > 1 }

    /// CONCEPT: RATCHET repeats the WHOLE chord — it never drops notes — so the sounding set is the full chord for
    /// every legal repeat count (2/3/4/6/8).
    func testRatchetKeepsTheWholeChordForAnyCount() {
        for count in [2, 3, 4, 6, 8] {
            XCTAssertEqual(Accept.notesA([ratchet(count: count)]), chordNotes, "RATCHET count \(count) must keep the whole chord")
        }
    }

    /// CONCEPT: each step is subdivided into `count` strikes, and every strike sounds all 3 chord notes → the number of
    /// emitter-A note-ons over a FIXED window scales with `count`. So count=4 emits ~2× the onsets of count=2, and
    /// count=8 emits more than count=4. (Ratio, not an absolute count → S-independent.)
    func testRatchetCountScalesOnsetDensity() {
        let c2 = Accept.onsA([ratchet(count: 2)]).count
        let c4 = Accept.onsA([ratchet(count: 4)]).count
        let c8 = Accept.onsA([ratchet(count: 8)]).count
        XCTAssertGreaterThan(c2, 0, "RATCHET count=2 should emit something")
        XCTAssertGreaterThan(c4, c2, "count=4 must emit more onsets than count=2")
        XCTAssertGreaterThan(c8, c4, "count=8 must emit more onsets than count=4")
        let ratio = Double(c4) / Double(c2)
        XCTAssertGreaterThan(ratio, 1.5, "count 4:2 onset ratio ~2 (got \(ratio); c2=\(c2) c4=\(c4))")
        XCTAssertLessThan(ratio, 2.5, "count 4:2 onset ratio ~2 (got \(ratio); c2=\(c2) c4=\(c4))")
    }

    /// CONCEPT: every strike sounds the FULL chord together — so grouping the note-ons by onset bucket, each populated
    /// bucket contains exactly the 3 chord notes (all three onset at the same instant → the same 1/16-beat bucket).
    func testRatchetEveryStrikeSoundsTheFullChord() {
        let events = Accept.onsA([ratchet(count: 4, ramp: 0.0)])   // ramp flat here — this test is about the note set, not velocity
        let byBucket = Dictionary(grouping: events, by: { $0.onset })
        XCTAssertFalse(byBucket.isEmpty, "RATCHET must emit at least one strike")
        for (bucket, evs) in byBucket {
            XCTAssertEqual(Set(evs.map { $0.note }), chordNotes, "RATCHET strike @bucket \(bucket) must sound the whole chord")
        }
    }

    /// CONCEPT: the ramp shapes VELOCITY across the successive strikes, not the note set or the strike positions. So:
    ///  (a) the sounding note set is invariant under ramp; and
    ///  (b) the ramp actually does something — for SOME ramp setting the strike velocities are not all equal.
    /// (We assert (b) as an existence property over a spread of ramp values rather than pinning the neutral point.)
    func testRatchetRampVariesVelocityNotTheNoteSet() {
        let ramps = [0.0, 0.5, 1.0]
        for r in ramps {
            XCTAssertEqual(Accept.notesA([ratchet(count: 4, ramp: r)]), chordNotes, "RATCHET note set must be invariant under ramp \(r)")
        }
        let anyNonFlat = ramps.contains { velsNonFlat(Accept.onsA([ratchet(count: 4, ramp: $0)])) }
        XCTAssertTrue(anyNonFlat, "RATCHET ramp must produce non-uniform strike velocities for some setting")
    }
}

// MARK: - STRUM — SET · ROLL-ORDER · SPREAD · velTilt-property oracle

final class AcceptanceStrumTests: XCTestCase {
    private let chordNotes: Set<Int> = [60, 64, 67]

    /// A single STRUM slot (curve 0 = linear roll, per the harness example).
    private func strum(_ dir: StrumDir, spread: Double, velTilt: Double = 0, curve: Double = 0) -> ProcessorSlot {
        var s = ProcessorSlot(type: .strum)
        s.params.strumDir = dir
        s.params.spread = spread
        s.params.velTilt = velTilt
        s.params.curve = curve
        return s
    }

    private func velsNonFlat(_ events: [AcceptEvent]) -> Bool { Set(events.map { $0.vel }).count > 1 }

    /// The FIRST roll's note order: walk the events in ONSET order and collect the first occurrence of each distinct
    /// note (the initial rake), up to `n`. Assumes the roll gap separates the notes into distinct onset buckets so the
    /// (onset, note) sort reads the true stagger order — guaranteed by using a generous spread in the order test.
    private func firstRollOrder(_ events: [AcceptEvent], _ n: Int = 3) -> [Int] {
        var order: [Int] = []
        for e in events where !order.contains(e.note) {   // `events` are already sorted by (onset, note)
            order.append(e.note)
            if order.count == n { break }
        }
        return order
    }

    /// The onset-bucket SPAN (max − min) of the first roll's `n` staggered notes.
    private func firstRollSpan(_ events: [AcceptEvent], _ n: Int = 3) -> Int {
        var firstOnset: [Int: Int] = [:]
        var order: [Int] = []
        for e in events where firstOnset[e.note] == nil {
            firstOnset[e.note] = e.onset
            order.append(e.note)
            if order.count == n { break }
        }
        let onsets = order.compactMap { firstOnset[$0] }
        return (onsets.max() ?? 0) - (onsets.min() ?? 0)
    }

    /// CONCEPT: STRUM rolls the chord IN then sustains it — it plays the whole chord, whatever the direction.
    func testStrumKeepsTheWholeChord() {
        for dir in [StrumDir.up, .down, .alternate] {
            XCTAssertEqual(Accept.notesA([strum(dir, spread: 0.3)]), chordNotes, "STRUM \(dir) must sound the whole chord")
        }
    }

    /// CONCEPT: UP rakes low→high, DOWN rakes high→low. The first roll's note order is therefore ascending pitch for UP
    /// and descending pitch for DOWN. (Generous spread so the three notes land in distinct onset buckets.)
    func testStrumUpRollIsAscendingDownRollIsDescending() {
        XCTAssertEqual(firstRollOrder(Accept.onsA([strum(.up, spread: 0.6)])), [60, 64, 67], "STRUM UP first roll must ascend low→high")
        XCTAssertEqual(firstRollOrder(Accept.onsA([strum(.down, spread: 0.6)])), [67, 64, 60], "STRUM DOWN first roll must descend high→low")
    }

    /// CONCEPT: a larger `spread` stretches the roll over more time — so the first roll's onset-bucket span is larger for
    /// spread=0.6 than for spread=0.05. (Relative comparison → S-independent-ish.)
    func testStrumSpreadWidensTheRoll() {
        let wide = firstRollSpan(Accept.onsA([strum(.up, spread: 0.6)]))
        let tight = firstRollSpan(Accept.onsA([strum(.up, spread: 0.05)]))
        XCTAssertGreaterThan(wide, tight, "a larger spread must stagger the roll's onsets more (wide=\(wide) tight=\(tight))")
    }

    /// CONCEPT: velTilt tilts VELOCITY across the roll, not the note set. So:
    ///  (a) the sounding note set is invariant under velTilt; and
    ///  (b) a non-zero tilt does something — for SOME tilt setting the roll's velocities are not all equal.
    func testStrumVelTiltVariesVelocityNotTheNoteSet() {
        let tilts = [-0.9, 0.0, 0.9]
        for t in tilts {
            XCTAssertEqual(Accept.notesA([strum(.up, spread: 0.6, velTilt: t)]), chordNotes, "STRUM note set must be invariant under velTilt \(t)")
        }
        let anyNonFlat = tilts.contains { velsNonFlat(Accept.onsA([strum(.up, spread: 0.6, velTilt: $0)])) }
        XCTAssertTrue(anyNonFlat, "STRUM velTilt must produce non-uniform roll velocities for some setting")
    }
}
