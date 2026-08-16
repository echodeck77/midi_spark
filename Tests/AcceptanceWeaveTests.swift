//  AcceptanceWeaveTests.swift
//  ACCEPTANCE tests for the WEAVE processor — an INDEPENDENT ORACLE. The expected output is reasoned FROM THE CONCEPT
//  (a rank-clocked polyrhythm driver + music-theory rate ratios), NOT read from Router.swift / Derivations.swift. The
//  rank rates are DERIVED here from first principles (see CONCEPT below); if the engine and this oracle disagree, ONE of
//  them is wrong — and the oracle never saw the implementation.
//
//  Substrate: the shared offline probe (`Accept`, see AcceptanceTests.swift) — REAL Router, 120 BPM, frozen column,
//  ~3 beats, default held chord C-E-G (60·64·67 @100). The 3-beat window can TRUNCATE a rank's clock mid-period, so the
//  oracle asserts S-INDEPENDENT properties — pitch SETS, strict per-rank onset ORDERING, and per-rank count RATIOS only
//  LOOSELY (generous tolerance) — never sample-exact counts.
//
//  CONCEPT (the derivation, engine-blind):
//   • Each held note ticks on ITS OWN clock, keyed by pitch RANK (0 = lowest). C-E-G ⇒ rank0=60, rank1=64, rank2=67.
//   • LADDER   — rank r fires at base ÷ 2^r, i.e. 2^r times as OFTEN as the bass ⇒ onset counts ~ 1 : 2 : 4.
//   • HARMONIC — rank r fires at (r+1) × base (pitch ratios as time ratios) ⇒ onset counts ~ 1 : 2 : 3.
//   • DRAWN    — rank r fires at its authored weaveDrawn[r] rate (a faster drawn rate ⇒ more onsets).
//   • EUCLID   — rank r plays a euclidean pattern of (2r+1) pulses over M steps: bass = 1 pulse (sparse) … top = dense.
//   • SPAN     — how many ranks get their OWN clock; extras join the top clock. SPAN 1 ⇒ every note shares the bass
//                clock (per-note counts equal); SPAN ≥ ranks ⇒ each rank weaves independently (the ordering above).
//   • Each rank sounds ITS OWN note, repeatedly, on its own clock.

import XCTest

final class AcceptanceWeaveTests: XCTestCase {

    // MARK: - Build helpers

    /// A single WEAVE slot. Rank rates come from the CONCEPT, never the engine — this just fills the schema fields.
    private func weave(mode: WeaveMode = .ladder, base: StepRate = .r1_4, span: Int = 3,
                       phase: ArpPhase = .retrig, drawn: [StepRate]? = nil, euclidSteps: Int? = nil) -> ProcessorSlot {
        var w = ProcessorSlot(type: .weave)
        w.params.weaveMode = mode
        w.params.weaveBaseStep = base
        w.params.weaveSpan = span
        w.params.weavePhase = phase
        if let drawn { w.params.weaveDrawn = drawn }
        if let euclidSteps { w.params.weaveEuclidSteps = euclidSteps }
        return w
    }

    /// Onset count PER sounding pitch — the oracle's unit (rank r sounds its own note repeatedly, so a note's count is
    /// that rank's number of clock ticks inside the probe window).
    private func countsByNote(_ events: [AcceptEvent]) -> [Int: Int] {
        var c: [Int: Int] = [:]
        for e in events { c[e.note, default: 0] += 1 }
        return c
    }

    /// a/b ≈ expected, within ±tol (a FRACTION). Deliberately wide: the ~3-beat window may truncate a partial period,
    /// so the RATIO is only a loose sanity check — the strict ORDERING assertions carry the real weight.
    private func assertRatio(_ a: Int, _ b: Int, expected: Double, tol: Double, _ msg: String) {
        guard b > 0 else { return XCTFail("\(msg): zero denominator (b=\(b))") }
        let r = Double(a) / Double(b)
        XCTAssert(r >= expected * (1 - tol) && r <= expected * (1 + tol),
                  "\(msg): got \(a)/\(b) = \(r), expected ~\(expected) (±\(Int(tol * 100))%)")
    }

    // MARK: - Every rank sounds its own note (a SET oracle, S-independent)

    func testEveryModeSoundsAllThreeRanks() {
        for mode in [WeaveMode.ladder, .harmonic, .drawn, .euclid] {
            XCTAssertEqual(Accept.notesA([weave(mode: mode)]), [60, 64, 67],
                           "WEAVE \(mode.rawValue): each rank must sound ITS OWN held note (60·64·67)")
        }
    }

    // MARK: - LADDER — rank r fires 2^r× the bass (1 : 2 : 4)

    func testLadderRankOrderingAndLooseRatio() {
        let c = countsByNote(Accept.onsA([weave(mode: .ladder, base: .r1_4, span: 3)]))
        let n0 = c[60] ?? 0, n1 = c[64] ?? 0, n2 = c[67] ?? 0   // rank0 · rank1 · rank2
        // STRICT ordering (reliable even under window truncation): bass fires fewest, top most.
        XCTAssertLessThan(n0, n1, "LADDER: rank1 (64) fires more often than rank0 (60)")
        XCTAssertLessThan(n1, n2, "LADDER: rank2 (67) fires more often than rank1 (64)")
        // LOOSE ratio ~ 1 : 2 : 4 (rank r ≈ 2^r × the bass).
        assertRatio(n2, n1, expected: 2, tol: 0.6, "LADDER 67:64 ~ 2×")
        assertRatio(n2, n0, expected: 4, tol: 0.6, "LADDER 67:60 ~ 4×")
    }

    // MARK: - HARMONIC — rank r fires at (r+1)× the bass (1 : 2 : 3)

    func testHarmonicRankOrderingAndLooseRatio() {
        let c = countsByNote(Accept.onsA([weave(mode: .harmonic, base: .r1_4, span: 3)]))
        let n0 = c[60] ?? 0, n1 = c[64] ?? 0, n2 = c[67] ?? 0
        XCTAssertLessThan(n0, n1, "HARMONIC: rank1 (64) fires more often than rank0 (60)")
        XCTAssertLessThan(n1, n2, "HARMONIC: rank2 (67) fires more often than rank1 (64)")
        // LOOSE ratio ~ 1 : 2 : 3 (rank r ≈ (r+1) × the bass).
        assertRatio(n1, n0, expected: 2, tol: 0.6, "HARMONIC 64:60 ~ 2×")
        assertRatio(n2, n0, expected: 3, tol: 0.6, "HARMONIC 67:60 ~ 3×")
    }

    // MARK: - BASE — a slower bass clock yields far fewer onsets

    func testSlowerBaseYieldsFewerOnsets() {
        // SPAN 1 so all three notes share the bass clock (isolates the BASE rate from the rank spread).
        let slow = Accept.onsA([weave(base: .r2_1, span: 1)]).count   // 2/1 = 2 bars
        let fast = Accept.onsA([weave(base: .r1_8, span: 1)]).count   // 1/8
        XCTAssertLessThan(slow, fast, "a 2/1 (2-bar) base must fire far less than a 1/8 base")
    }

    // MARK: - SPAN — 1 equalises the ranks, 3 differentiates them

    func testSpanOneEqualisesAndSpanThreeDifferentiates() {
        // SPAN 1: every note joins the ONE (bass) clock → per-note counts ~equal (they tick together).
        let eq = countsByNote(Accept.onsA([weave(mode: .ladder, base: .r1_8, span: 1)]))
        let e0 = eq[60] ?? 0, e1 = eq[64] ?? 0, e2 = eq[67] ?? 0
        XCTAssertLessThanOrEqual(abs(e0 - e1), 1, "SPAN 1: rank0 (60) ≈ rank1 (64) — one shared clock")
        XCTAssertLessThanOrEqual(abs(e1 - e2), 1, "SPAN 1: rank1 (64) ≈ rank2 (67) — one shared clock")

        // SPAN 3: each rank weaves independently → the ordering returns.
        let df = countsByNote(Accept.onsA([weave(mode: .ladder, base: .r1_4, span: 3)]))
        XCTAssertLessThan(df[60] ?? 0, df[67] ?? 0, "SPAN 3: rank0 (60) fires fewer than rank2 (67)")
    }

    // MARK: - DRAWN — per-rank authored rates drive the counts

    func testDrawnFollowsAuthoredRates() {
        // rank0 SLOW (1/1 = 4 beats), rank1 FAST (1/8 = 0.5 beats) → 60 fires fewer than 64.
        var drawn = Array(repeating: StepRate.r1_8, count: 8)
        drawn[0] = .r1_1
        drawn[1] = .r1_8
        let c = countsByNote(Accept.onsA([weave(mode: .drawn, span: 3, drawn: drawn)]))
        XCTAssertLessThan(c[60] ?? 0, c[64] ?? 0,
                          "DRAWN: the rank drawn slow (60 @ 1/1) fires fewer than the rank drawn fast (64 @ 1/8)")
    }

    // MARK: - EUCLID — rank r fills (2r+1) pulses: bass sparse, top dense

    func testEuclidBassSparserThanTop() {
        // rank0 = 1 pulse (the lone downbeat), rank2 = 5 pulses over M=8 → 60 sparser than 67.
        let c = countsByNote(Accept.onsA([weave(mode: .euclid, span: 3, euclidSteps: 8)]))
        XCTAssertLessThan(c[60] ?? 0, c[67] ?? 0,
                          "EUCLID: bass (rank0, 1 pulse) fires fewer than top (rank2, 5 pulses)")
    }

    // MARK: - PHASE — a light check: every phase still sounds every rank

    func testEachPhaseSoundsEveryRank() {
        for phase in [ArpPhase.retrig, .free, .legato] {
            XCTAssertEqual(Accept.notesA([weave(mode: .ladder, span: 3, phase: phase)]), [60, 64, 67],
                           "WEAVE phase \(phase.rawValue): the interlock must still sound every rank")
        }
    }
}
