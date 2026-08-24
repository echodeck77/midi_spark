//  AcceptanceGeneratorsTests.swift
//  ACCEPTANCE tests for the GENERATOR processors — EUCLID · BURST · CASCADE · DRONE · SHIFT.
//  INDEPENDENT ORACLES: every EXPECTED result below is reasoned from the CONCEPT (euclidean-rhythm theory / the spec's
//  generator brainstorm), NOT read off the engine. In particular the euclidean pattern is computed here from Bjorklund
//  first principles (see `euclid(pulses:steps:)`) — the engine's own `euclidPattern` was NOT consulted. If the engine
//  and an oracle disagree, ONE is wrong, and the oracle never saw the implementation.
//
//  Substrate: the shared `Accept` probe (REAL Router · 120 BPM · 48 kHz · column FROZEN at 0 · ~3 beats), holding the
//  default C-E-G chord (60,64,67 @ vel 100). `Accept.onsA` returns emitter-A note-ons as (note, vel, onset-bucket),
//  the onset bucket being a 1/16-BEAT grid index; `Accept.notesA` is the DISTINCT pitch set. See AcceptanceTests.swift.
//
//  CONVENTION / ASSERT-AROUNDS (undefined-or-uncertain things we assert as PROPERTIES, noted so a reader can see the
//  boundary of the oracle):
//   • CYCLE = ONE COLUMN-STEP. A generator re-derives its figure at each column boundary, so its rhythmic cycle spans
//     one step S (here the scene default `.r1_2` = 2 beats = 32 onset buckets). We read S from the MODEL (the scene's
//     stepRate), never the engine. Per-cycle assertions window to the FIRST FULL cycle [0, S) so a partial trailing
//     cycle can't skew a count. If the engine tied a generator's cycle to some fixed sub-rate instead of the step,
//     the per-cycle assertions would be the ones to revisit.
//   • EXACT STRIKE POSITIONS within the step are NOT asserted against a specific euclidean ROTATION (the rotation
//     convention is undefined between two independent implementations). We assert the euclidean INVARIANTS instead:
//     the whole-chord SET, the per-cycle pulse COUNT (= K), rotation-count-invariance, and relative/ratio counts.
//   • Velocities/curve shaping below the 1/16-beat bucket are not asserted (the probe's bucket is coarser than a
//     burst's internal spacing) — count/mass/ordering properties are used instead.

import XCTest

// MARK: - Shared oracle helpers

/// One rhythmic cycle = one column-step, in 1/16-beat onset buckets. Read from the MODEL (the probe scene's stepRate),
/// not the engine. Default scene step is `.r1_2` (2 beats) ⇒ 32 buckets.
private let cycleBuckets: Int = Int((SceneState.empty().stepRate.beats * 16.0).rounded())

/// The default held chord as the oracle expects to see it back out (whole-chord generators strike all three).
private let chordSet: Set<Int> = [60, 64, 67]

/// Events landing in the FIRST FULL cycle [0, cycleBuckets).
private func firstCycle(_ events: [AcceptEvent]) -> [AcceptEvent] { events.filter { $0.onset >= 0 && $0.onset < cycleBuckets } }

/// Distinct onset buckets among `events`.
private func onsetSet(_ events: [AcceptEvent]) -> Set<Int> { Set(events.map { $0.onset }) }

/// For each onset bucket, the set of notes that strike there (proves "strikes the WHOLE chord on each pulse").
private func notesByOnset(_ events: [AcceptEvent]) -> [Int: Set<Int>] {
    var m: [Int: Set<Int>] = [:]
    for e in events { m[e.onset, default: []].insert(e.note) }
    return m
}

/// The order in which distinct notes FIRST appear, walking events in (onset, note) order.
private func firstAppearanceOrder(_ events: [AcceptEvent]) -> [Int] {
    var seen = Set<Int>(); var order: [Int] = []
    for e in events.sorted() where !seen.contains(e.note) { seen.insert(e.note); order.append(e.note) }
    return order
}

/// THE EUCLIDEAN PATTERN — computed from the CONCEPT, Bjorklund's algorithm (the same maximally-even distribution the
/// Euclidean-rhythm literature defines). Returns N booleans, exactly K true, a pulse on step 0, gaps as even as
/// possible (max gap − min gap ≤ 1). Written WITHOUT reading the engine's `euclidPattern`.
private func euclid(pulses: Int, steps n: Int) -> [Bool] {
    guard n > 0 else { return [] }
    let k = max(0, min(pulses, n))
    if k == 0 { return Array(repeating: false, count: n) }
    if k == n { return Array(repeating: true, count: n) }
    // Repeatedly append the shorter of the two buckets onto the longer, "as even as possible", until ≤1 remainder.
    var a: [[Bool]] = Array(repeating: [true],  count: k)
    var b: [[Bool]] = Array(repeating: [false], count: n - k)
    while b.count > 1 {
        let m = min(a.count, b.count)
        var newA: [[Bool]] = []; newA.reserveCapacity(m)
        for i in 0..<m { newA.append(a[i] + b[i]) }
        var newB: [[Bool]] = []
        if a.count > m { newB = Array(a[m...]) } else if b.count > m { newB = Array(b[m...]) }
        a = newA; b = newB
    }
    return (a + b).flatMap { $0 }
}

/// Circular gaps between the TRUE positions of a euclidean pattern (used to prove maximal evenness, convention-free).
private func circularGaps(_ pattern: [Bool]) -> [Int] {
    let hits = pattern.indices.filter { pattern[$0] }
    guard hits.count >= 2 else { return [] }
    var gaps: [Int] = []
    for i in 0..<hits.count {
        let next = hits[(i + 1) % hits.count]
        gaps.append((next - hits[i] + pattern.count) % pattern.count)
    }
    return gaps
}

private func euclidSlot(pulses: Int, steps: Int, rot: Int = 0, fromPool: Bool = false) -> ProcessorSlot {
    var s = ProcessorSlot(type: .euclid)
    s.params.euclidPulses = pulses; s.params.euclidSteps = steps; s.params.euclidRot = rot
    s.params.euclidPulsesFromPool = fromPool
    return s
}

// MARK: - EUCLID — a K-of-N euclidean rhythm striking the whole chord on the evenly-spread pulses

final class AcceptanceEuclidTests: XCTestCase {

    // First: the ORACLE ITSELF is validated (pure — no engine). If Bjorklund here is wrong, every engine comparison is
    // meaningless, so pin the canonical cases the concept fixes.
    func testEuclidOracleMatchesCanonicalPatterns() {
        // (3,8) = the tresillo, x..x..x.
        XCTAssertEqual(euclid(pulses: 3, steps: 8), [true, false, false, true, false, false, true, false], "tresillo E(3,8)")
        // Degenerate/edge shapes.
        XCTAssertEqual(euclid(pulses: 4, steps: 8), [true, false, true, false, true, false, true, false], "E(4,8) is the even 4-on-8")
        XCTAssertEqual(euclid(pulses: 1, steps: 8).filter { $0 }.count, 1)
        XCTAssertEqual(euclid(pulses: 8, steps: 8), Array(repeating: true, count: 8))
        // Every canonical case: exactly K pulses, a pulse on step 0, maximally even (gap spread ≤ 1).
        for (k, n) in [(3, 8), (5, 8), (4, 8), (2, 5), (5, 16)] {
            let p = euclid(pulses: k, steps: n)
            XCTAssertEqual(p.count, n, "E(\(k),\(n)) length")
            XCTAssertEqual(p.filter { $0 }.count, k, "E(\(k),\(n)) pulse count")
            XCTAssertTrue(p.first == true, "E(\(k),\(n)) starts on a pulse")
            let g = circularGaps(p)
            XCTAssertLessThanOrEqual((g.max() ?? 0) - (g.min() ?? 0), 1, "E(\(k),\(n)) is maximally even, gaps \(g)")
        }
    }

    // CONCEPT (a): every pulse strikes the WHOLE chord — so the sounding SET is the whole chord for any K in 1…N.
    func testEuclidStrikesTheWholeChordForEveryK() {
        for n in [4, 8, 16] {
            for k in Set([1, 2, 3, n / 2, n - 1, n].filter { $0 >= 1 && $0 <= n }) {
                XCTAssertEqual(Accept.notesA([euclidSlot(pulses: k, steps: n)]), chordSet, "EUCLID(\(k),\(n)) set")
            }
        }
    }

    // CONCEPT (b): the number of DISTINCT onset positions PER CYCLE equals K (the pulses). Windowed to the first full
    // step so a partial trailing cycle can't skew the count. Sweep N = 4, 8, 16 and K across 1…N incl. the edges.
    func testEuclidDistinctOnsetsPerCycleEqualsK() {
        for n in [4, 8, 16] {
            for k in Set([1, 2, 3, n / 2, n - 1, n].filter { $0 >= 1 && $0 <= n }) {
                let onsets = onsetSet(firstCycle(Accept.onsA([euclidSlot(pulses: k, steps: n)])))
                XCTAssertEqual(onsets.count, k, "EUCLID(\(k),\(n)) should pulse K=\(k) times per cycle, got \(onsets.sorted())")
            }
        }
    }

    // Each of those per-cycle onsets carries the FULL chord (not a subset).
    func testEuclidEachPulseIsTheWholeChord() {
        for (k, n) in [(3, 8), (5, 8), (2, 5)] {
            let byOnset = notesByOnset(firstCycle(Accept.onsA([euclidSlot(pulses: k, steps: n)])))
            XCTAssertEqual(byOnset.count, k, "EUCLID(\(k),\(n)) onset count")
            for (onset, notes) in byOnset { XCTAssertEqual(notes, chordSet, "EUCLID(\(k),\(n)) pulse @\(onset) whole chord") }
        }
    }

    // CONCEPT (c): pulses=5 gives MORE onsets than pulses=3 over the same window, ratio ≈ 5:3 (relative, S-independent).
    func testEuclidOnsetCountScalesWithPulses() {
        let n = 8
        let five = onsetSet(firstCycle(Accept.onsA([euclidSlot(pulses: 5, steps: n)]))).count
        let three = onsetSet(firstCycle(Accept.onsA([euclidSlot(pulses: 3, steps: n)]))).count
        XCTAssertGreaterThan(five, three, "5-of-8 has more onsets than 3-of-8")
        XCTAssertEqual(Double(five) / Double(three), 5.0 / 3.0, accuracy: 0.01, "ratio ≈ 5:3")
        // Monotone across the whole K sweep.
        var prev = 0
        for k in 1...n {
            let c = onsetSet(firstCycle(Accept.onsA([euclidSlot(pulses: k, steps: n)]))).count
            XCTAssertGreaterThanOrEqual(c, prev, "onset count is non-decreasing in K (K=\(k))")
            prev = c
        }
    }

    // ROTATION shifts the pattern but preserves the pulse COUNT (a rotation is cyclic within the step).
    func testEuclidRotationPreservesOnsetCount() {
        for (k, n) in [(3, 8), (5, 8), (5, 16)] {
            for rot in [0, 1, 2, n - 1] {
                let onsets = onsetSet(firstCycle(Accept.onsA([euclidSlot(pulses: k, steps: n, rot: rot)])))
                XCTAssertEqual(onsets.count, k, "EUCLID(\(k),\(n)) rot \(rot) still \(k) pulses/cycle")
            }
        }
    }

    // The euclidean EVENNESS shows up in TIME, convention-free: mapping the first cycle's onsets onto the N-step grid,
    // the gaps between consecutive pulses differ by at most one grid step. (Assumes cycle == step; see file header.)
    func testEuclidOnsetsAreMaximallyEvenInTime() {
        for (k, n) in [(3, 8), (5, 8), (4, 8), (2, 5), (5, 16)] {
            let onsets = onsetSet(firstCycle(Accept.onsA([euclidSlot(pulses: k, steps: n)]))).sorted()
            guard onsets.count == k, k >= 2 else { XCTFail("EUCLID(\(k),\(n)) expected \(k) onsets, got \(onsets)"); continue }
            let sub = Double(cycleBuckets) / Double(n)   // buckets per N-grid step
            let grid = onsets.map { Int((Double($0) / sub).rounded()) }
            var gaps: [Int] = []
            for i in 0..<grid.count { gaps.append((grid[(i + 1) % grid.count] - grid[i] + n) % n) }
            XCTAssertLessThanOrEqual((gaps.max() ?? 0) - (gaps.min() ?? 0), 1, "EUCLID(\(k),\(n)) even-in-time, gaps \(gaps)")
        }
    }

    // POOL mode: K tracks the held-note count. A 3-note chord ⇒ 3 pulses/cycle.
    func testEuclidPulsesFromPoolTracksChordSize() {
        let onsets = onsetSet(firstCycle(Accept.onsA([euclidSlot(pulses: 5, steps: 8, fromPool: true)])))
        XCTAssertEqual(onsets.count, 3, "POOL pulses follow the 3-note chord, got \(onsets.sorted())")
    }
}

// MARK: - BURST — a one-shot accel/decel roll at step entry (count strikes; curve = accel vs decel)

final class AcceptanceBurstTests: XCTestCase {

    private func burst(count: Int, curve: Double = 0) -> ProcessorSlot {
        var s = ProcessorSlot(type: .burst); s.params.count = count; s.params.curve = curve; return s
    }

    // Each strike is the whole chord ⇒ the sounding SET is the whole chord, for any count/curve.
    func testBurstStrikesTheWholeChord() {
        for c in [2, 4, 8] {
            for curve in [-1.0, 0.0, 1.0] {
                XCTAssertEqual(Accept.notesA([burst(count: c, curve: curve)]), chordSet, "BURST count \(c) curve \(curve)")
            }
        }
    }

    // COUNT relationship: more strikes ⇒ more emitted note-ons. Uses the emitted-event COUNT (array length), which is
    // robust to two close strikes sharing a 1/16 bucket (the array is not de-duped). count=8 ≳ 2× count=4.
    func testBurstEmittedCountScalesWithCount() {
        let c2 = Accept.onsA([burst(count: 2)]).count
        let c4 = Accept.onsA([burst(count: 4)]).count
        let c8 = Accept.onsA([burst(count: 8)]).count
        XCTAssertGreaterThan(c4, c2, "count 4 emits more than count 2")
        XCTAssertGreaterThan(c8, c4, "count 8 emits more than count 4")
        XCTAssertEqual(Double(c8) / Double(c4), 2.0, accuracy: 0.6, "count 8 ≈ 2× count 4")
    }

    // CR-6[review]: HITS 12 / HITS 16 used to render as 8 — the shared `count` was clamped to 2…8 in the snapshot, so
    // BURST (which reads up to 16) topped out. Widened to 2…16; the two high settings must now out-strike count 8.
    func testBurstHits12And16BeatCount8() {
        let c8  = Accept.onsA([burst(count: 8)]).count
        let c12 = Accept.onsA([burst(count: 12)]).count
        let c16 = Accept.onsA([burst(count: 16)]).count
        XCTAssertGreaterThan(c12, c8,  "HITS 12 emits more than HITS 8 (was silently capped equal)")
        XCTAssertGreaterThan(c16, c12, "HITS 16 emits more than HITS 12")
    }

    // BURST is an ACCEL/DECEL roll across the step; the CURVE shapes the distribution. curve=0 spreads the strikes
    // EVENLY; the two curve extremes skew it OPPOSITELY — accel bunches toward one end, decel toward the other, so
    // exactly ONE extreme is front-heavy. (Event mass, robust to sub-bucket merging.)
    // NOTE (adjudicated 2026-08-16): the original oracle asserted "always front-loaded" — a MISCONCEPTION. A burst only
    // front-loads under a decel curve; at curve=0 it is even (a real engine/oracle disagreement, resolved as oracle-side).
    func testBurstCurveShapesTheDistribution() {
        func frontBack(_ curve: Double) -> (front: Int, back: Int) {
            let ev = firstCycle(Accept.onsA([burst(count: 8, curve: curve)]))
            let half = cycleBuckets / 2
            return (ev.filter { $0.onset < half }.count, ev.filter { $0.onset >= half }.count)
        }
        let (f0, b0) = frontBack(0)
        XCTAssertLessThanOrEqual(abs(f0 - b0), 3, "curve=0 spreads the roll evenly (front \(f0) vs back \(b0))")
        let up = frontBack(1), dn = frontBack(-1)
        XCTAssertNotEqual(up.front > up.back, dn.front > dn.back, "accel and decel skew the roll OPPOSITELY: +1=\(up) −1=\(dn)")
        XCTAssertTrue((up.front > up.back) || (dn.front > dn.back), "one curve extreme front-loads")
        XCTAssertTrue((up.front < up.back) || (dn.front < dn.back), "one curve extreme back-loads")
    }
}

// MARK: - CASCADE — reveal the chord's notes one at a time, each held to the boundary (strumDir order)

final class AcceptanceCascadeTests: XCTestCase {

    private func cascade(_ dir: StrumDir) -> ProcessorSlot {
        var s = ProcessorSlot(type: .cascade); s.params.strumDir = dir; return s
    }

    // The DISTINCT notes revealed accumulate to the whole chord.
    func testCascadeRevealsTheWholeChord() {
        XCTAssertEqual(Accept.notesA([cascade(.up)]), chordSet, "CASCADE up")
        XCTAssertEqual(Accept.notesA([cascade(.down)]), chordSet, "CASCADE down")
    }

    // Notes enter ONE AT A TIME: the first onset is a single note, and the distinct-note set grows monotonically as
    // more onsets arrive — it does not strike the chord all at once.
    func testCascadeEntersOneNoteAtATime() {
        let ev = firstCycle(Accept.onsA([cascade(.up)])).sorted()
        XCTAssertFalse(ev.isEmpty, "cascade should sound")
        // Group by onset in time order; each successive onset must ADD at least one new note and never fewer than one.
        let onsets = onsetSet(ev).sorted()
        XCTAssertGreaterThanOrEqual(onsets.count, 3, "three notes revealed across at least three onset positions")
        let byOnset = notesByOnset(ev)
        XCTAssertEqual(byOnset[onsets[0]]?.count, 1, "the FIRST onset reveals a single note")
        var accumulated = Set<Int>()
        var prevCount = 0
        for o in onsets {
            accumulated.formUnion(byOnset[o] ?? [])
            XCTAssertGreaterThanOrEqual(accumulated.count, prevCount, "revealed set only grows")
            prevCount = accumulated.count
        }
        XCTAssertEqual(accumulated, chordSet, "by the end the whole chord is revealed")
    }

    // DIR=up reveals notes in ASCENDING pitch order; DIR=down in descending order.
    func testCascadeRevealsInStrumDirOrder() {
        XCTAssertEqual(firstAppearanceOrder(firstCycle(Accept.onsA([cascade(.up)]))), [60, 64, 67], "up = ascending reveal")
        XCTAssertEqual(firstAppearanceOrder(firstCycle(Accept.onsA([cascade(.down)]))), [67, 64, 60], "down = descending reveal")
    }
}

// MARK: - DRONE — a flat sustained pad: the entry chord held to the boundary (gate = pad level)

final class AcceptanceDroneTests: XCTestCase {

    private func drone(gate: Double = 0.6) -> ProcessorSlot {
        var s = ProcessorSlot(type: .drone); s.params.gate = gate; return s
    }

    // The SET is the whole chord.
    func testDroneSoundsTheWholeChord() {
        XCTAssertEqual(Accept.notesA([drone()]), chordSet, "DRONE set")
    }

    // It's a SUSTAIN, not a driver: FAR fewer onsets than a 1/16 arp over the same window (roughly one strike per note
    // per column, not a fast repeat).
    func testDroneIsSustainedNotAFastRepeat() {
        let droneOns = Accept.onsA([drone()]).count
        var arp = ProcessorSlot(type: .arp); arp.params.rate = .r1_16
        let arpOns = Accept.onsA([arp]).count
        XCTAssertLessThan(droneOns, arpOns, "a drone emits far fewer note-ons than a 1/16 arp (\(droneOns) vs \(arpOns))")
        XCTAssertLessThanOrEqual(droneOns, 9, "a sustained pad strikes ~once per note per column, not a stream (\(droneOns))")
    }

    // gate scales VELOCITY, not the SET: the pitch set is invariant across gate; a louder gate lifts the velocity.
    func testDroneGateScalesVelocityNotTheSet() {
        for g in [0.2, 0.6, 1.0] {
            XCTAssertEqual(Accept.notesA([drone(gate: g)]), chordSet, "DRONE set invariant under gate \(g)")
        }
        let vLow  = Accept.onsA([drone(gate: 0.25)]).map { $0.vel }.max() ?? 0
        let vHigh = Accept.onsA([drone(gate: 1.0)]).map { $0.vel }.max() ?? 0
        XCTAssertGreaterThan(vHigh, vLow, "a higher pad level (gate) is louder (\(vHigh) vs \(vLow))")
    }
}

// MARK: - SHIFT — a groove nudge: push the chord's onset late (spread = push amount)

final class AcceptanceShiftTests: XCTestCase {

    private func shift(spread: Double) -> ProcessorSlot {
        var s = ProcessorSlot(type: .shift); s.params.spread = spread; return s
    }

    private func firstOnset(spread: Double) -> Int { Accept.onsA([shift(spread: spread)]).map { $0.onset }.min() ?? -1 }

    // The SET is the whole chord (a nudge shifts timing, not membership).
    func testShiftSoundsTheWholeChord() {
        XCTAssertEqual(Accept.notesA([shift(spread: 0.0)]), chordSet, "SHIFT set")
        XCTAssertEqual(Accept.notesA([shift(spread: 0.5)]), chordSet, "SHIFT set (pushed)")
    }

    // Increasing spread pushes the (first) onset LATER than spread=0 — relative, S-independent.
    func testShiftPushesTheOnsetLate() {
        let at0 = firstOnset(spread: 0.0)
        let at5 = firstOnset(spread: 0.5)
        XCTAssertGreaterThanOrEqual(at0, 0, "spread=0 sounds")
        XCTAssertGreaterThan(at5, at0, "a larger spread pushes the onset later (\(at5) vs \(at0))")
        // Monotone across the push amount.
        let a = firstOnset(spread: 0.0), b = firstOnset(spread: 0.25), c = firstOnset(spread: 0.5)
        XCTAssertLessThanOrEqual(a, b, "onset non-decreasing 0 → 0.25")
        XCTAssertLessThanOrEqual(b, c, "onset non-decreasing 0.25 → 0.5")
    }
}
