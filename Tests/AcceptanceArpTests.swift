//  AcceptanceArpTests.swift
//  ACCEPTANCE tests for the ARP processor — the expected output is computed FROM THE CONCEPT (spec §3 / §3.5 +
//  music theory), never derived from the engine's code, then checked against the REAL Router's output over a
//  representative + boundary parameter matrix. Independent oracle: if the engine and the oracle disagree, ONE of
//  them is wrong — and this oracle was written WITHOUT reading Router.swift / Derivations.swift.
//
//  Substrate: `Accept.onsA` / `Accept.notesA` (see AcceptanceTests.swift) — a held chord run through the chain
//  against the real engine at 120 BPM, column frozen, ~3 beats; note-ONs on emitter A as (note, vel, onset-bucket)
//  sorted by (onset, note). An ARP emits ONE note per tick, so at these rates successive ticks land in distinct
//  onset buckets → the sorted list IS the tick sequence in order.
//
//  Key derivation facts the oracle uses (from the spec, not the engine):
//   • The POOL is the held chord ascending, repeated up one octave per `octaves` (octave o adds +12·o) — §3 "octaves 1–4".
//   • UP walks the pool ascending and cycles; DOWN walks it descending and cycles. §3.
//   • RATE is one note per tick; 1/16 = 0.25 beat, 1/32 = 0.125 beat. §3 / ArpRate.
//   • PHASE governs only WHERE in the pattern the next note comes from, never which notes exist. §3.5.
//   • RETRIG (default) restarts pattern position 0 at each STEP boundary. The scene's default step is 1/2 = 2 beats
//     (SceneState.empty), so ORDER assertions stay inside ONE step (the first ≤6 ticks at 1/16 = beats 0…1.25) where
//     the plain cycle is exact regardless of the step reset. SET assertions use 1/32 (16 ticks per step) so the
//     whole pool is reached inside the first step, independent of any reset. §4 / §3.5.

import XCTest

final class AcceptanceArpTests: XCTestCase {

    // MARK: - Oracles (music theory — computed WITHOUT reading the engine)

    /// The ascending arp POOL: the chord ascending, then repeated up one octave per `octaves` (octave o adds +12·o).
    private func arpUpPool(_ chord: [Int], octaves: Int) -> [Int] {
        var pool: [Int] = []
        for o in 0..<octaves { for n in chord.sorted() { pool.append(n + 12 * o) } }
        return pool
    }
    /// The DISTINCT sounding pitch SET for `octaves` octaves of `chord` (order-independent, robust).
    private func poolSet(_ chord: [Int], octaves: Int) -> Set<Int> {
        Set(chord.flatMap { n in (0..<octaves).map { n + 12 * $0 } })
    }
    /// Cycle `pool` out to `n` elements (UP/DOWN wrap the pool endlessly).
    private func cycle(_ pool: [Int], _ n: Int) -> [Int] { (0..<n).map { pool[$0 % pool.count] } }

    // MARK: - Builders

    /// One ARP chain slot with explicit params (field names + enums from AUExtension/Models.swift).
    private func arp(_ pattern: ArpPattern = .up, rate: ArpRate = .r1_16, octaves: Int = 1,
                     gate: Double = 0.6, phase: ArpPhase = .retrig) -> ProcessorSlot {
        var s = ProcessorSlot(type: .arp)
        s.params.pattern = pattern
        s.params.rate = rate
        s.params.octaves = octaves
        s.params.gate = gate
        s.params.phase = phase
        return s
    }
    private func chord(_ notes: [Int], vel: Int = 100) -> [(UInt8, UInt8)] { notes.map { (UInt8($0), UInt8(vel)) } }
    /// The tick sequence: emitter-A note-ons in onset order (one note per tick at 1/16 and 1/32).
    private func seq(_ chain: [ProcessorSlot], _ ch: [(UInt8, UInt8)]) -> [Int] {
        Accept.onsA(chain, chord: ch).map { $0.note }
    }

    // MARK: - PATTERN · UP / DOWN — the ORDER of the first onsets equals the concept order

    /// CONCEPT: UP walks the ascending pool and cycles. First 6 ticks (1/16) stay inside step 0, so the plain cycle
    /// is exact whether or not RETRIG resets at the 2-beat step boundary.
    func testUpArpCyclesTheAscendingPoolInOrder() {
        let notes = [60, 64, 67]                                     // C-E-G
        for octs in [1, 2] {                                        // 1-oct = {60,64,67}; 2-oct = {60,64,67,72,76,79}
            let s = seq([arp(.up, rate: .r1_16, octaves: octs)], chord(notes))
            XCTAssertGreaterThanOrEqual(s.count, 6, "UP octaves \(octs): expected ≥6 note-ons")
            XCTAssertEqual(Array(s.prefix(6)), cycle(arpUpPool(notes, octaves: octs), 6),
                           "UP octaves \(octs): first 6 onsets must ascend the pool and cycle")
        }
    }

    /// CONCEPT: DOWN is UP reversed — the pool descending, cycled. 1-oct = [67,64,60,…]; 2-oct = [79,76,72,67,64,60,…].
    func testDownArpCyclesTheDescendingPoolInOrder() {
        let notes = [60, 64, 67]
        for octs in [1, 2] {
            let s = seq([arp(.down, rate: .r1_16, octaves: octs)], chord(notes))
            XCTAssertGreaterThanOrEqual(s.count, 6, "DOWN octaves \(octs): expected ≥6 note-ons")
            let downPool = Array(arpUpPool(notes, octaves: octs).reversed())
            XCTAssertEqual(Array(s.prefix(6)), cycle(downPool, 6),
                           "DOWN octaves \(octs): first 6 onsets must descend the pool and cycle")
        }
    }

    // MARK: - OCTAVES 1…4 — the distinct SET is the chord spanned across `octaves` octaves (S-independent)

    /// CONCEPT: the pool spans `octaves` octaves → distinct set = { n+12·o : n∈chord, o∈0..<octaves }. Uses 1/32
    /// (16 ticks per 2-beat step) so even the 12-note 4-octave pool is fully reached inside the first step.
    func testOctavesSpanThePoolSet() {
        let notes = [60, 64, 67]
        for octs in 1...4 {
            let got = Accept.notesA([arp(.up, rate: .r1_32, octaves: octs)], chord: chord(notes))
            XCTAssertEqual(got, poolSet(notes, octaves: octs),
                           "octaves \(octs): the distinct set must be C-E-G spanned across \(octs) octave(s)")
        }
    }

    // MARK: - UP-DN / AS-PLAYED — assert the SET (endpoint/order convention is underspecified, so not asserted)

    /// CONCEPT: UP-DN and AS-PLAYED re-order the SAME pool — they neither add nor drop pitches. The exact UP-DN
    /// endpoint repeat and the AS-PLAYED octave ordering are underspecified, so only the distinct SET is asserted.
    func testUpDownAndAsPlayedCoverThePoolSetWithoutAddingNotes() {
        let notes = [60, 64, 67]
        for pattern in [ArpPattern.upDown, .asPlayed] {
            for octs in [1, 2] {
                let got = Accept.notesA([arp(pattern, rate: .r1_32, octaves: octs)], chord: chord(notes))
                XCTAssertEqual(got, poolSet(notes, octaves: octs),
                               "\(pattern.rawValue) octaves \(octs): distinct set must equal the pool (order/endpoint not asserted)")
            }
        }
    }

    // MARK: - RANDOM — only the SET membership (order + full coverage are seed-dependent, deliberately not asserted)

    /// CONCEPT: RANDOM draws from the pool in an unspecified order. An independent oracle cannot predict the order
    /// or guarantee full coverage in a finite window (seed-dependent), so it asserts only that every note is IN the
    /// pool and that something sounds.
    func testRandomDrawsOnlyFromThePool() {
        let notes = [60, 64, 67]
        for octs in [1, 2] {
            let got = Accept.notesA([arp(.random, rate: .r1_32, octaves: octs)], chord: chord(notes))
            XCTAssertFalse(got.isEmpty, "RANDOM octaves \(octs): must sound something")
            XCTAssertTrue(got.isSubset(of: poolSet(notes, octaves: octs)),
                          "RANDOM octaves \(octs): every note must come from the pool")
        }
    }

    // MARK: - PHASE — retrig / legato / free each sound the whole pool (phase must not DROP notes)

    /// CONCEPT: PHASE governs the pattern INDEX only, never which pitches exist (§3.5). A deterministic UP covers the
    /// whole pool in any phase mode, so each mode must yield the full set. (Exact tick alignment is not asserted.)
    func testEveryPhaseModeSoundsTheWholePool() {
        let notes = [60, 64, 67]
        for phase in [ArpPhase.retrig, .legato, .free] {
            let got = Accept.notesA([arp(.up, rate: .r1_32, octaves: 2, phase: phase)], chord: chord(notes))
            XCTAssertEqual(got, poolSet(notes, octaves: 2),
                           "PHASE \(phase.rawValue): must not drop pool notes")
        }
    }

    // MARK: - GATE — shortens notes only; the note SET and onset ORDER are invariant

    /// CONCEPT: GATE sets note LENGTH (5–100%), not which notes fire or when they start. onsA sees only note-ONs, so
    /// a long gate and a short gate must produce the IDENTICAL onset sequence (durations are invisible here).
    func testGateChangesDurationsNotTheNoteSetOrOrder() {
        let ch = chord([60, 64, 67])
        let long  = seq([arp(.up, rate: .r1_16, octaves: 2, gate: 0.95)], ch)
        let short = seq([arp(.up, rate: .r1_16, octaves: 2, gate: 0.10)], ch)
        XCTAssertFalse(long.isEmpty, "expected note-ons")
        XCTAssertEqual(short, long, "GATE must change only note lengths — not which notes sound or their order")
    }

    // MARK: - CHORD SIZE — UP order/set follows a 2-note and a 4-note chord

    /// CONCEPT: the pool IS the held chord, so UP over any chord ascends + cycles exactly that chord.
    func testUpFollowsChordSize() {
        let cases: [[Int]] = [[60, 67], [60, 64, 67, 71]]           // dyad · seventh chord
        for notes in cases {
            let s = seq([arp(.up, rate: .r1_16, octaves: 1)], chord(notes))
            XCTAssertGreaterThanOrEqual(s.count, 6, "chord \(notes): expected ≥6 note-ons")
            XCTAssertEqual(Array(s.prefix(6)), cycle(arpUpPool(notes, octaves: 1), 6),
                           "UP over a \(notes.count)-note chord must ascend + cycle that pool")
            XCTAssertEqual(Set(s), poolSet(notes, octaves: 1),
                           "UP over a \(notes.count)-note chord must sound exactly the held notes")
        }
    }

    // MARK: - VELOCITY — a uniform chord arps at that velocity (concept check; would catch accenting)

    /// CONCEPT: the arp re-voices the HELD notes, so a uniform vel-100 chord arps at velocity 100 (velocity
    /// inheritance). A light extra check beyond note/order — a divergence here would reveal accenting/velocity-remap.
    func testArpPreservesTheHeldNoteVelocity() {
        let ons = Accept.onsA([arp(.up, rate: .r1_16, octaves: 2)], chord: chord([60, 64, 67], vel: 100))
        XCTAssertFalse(ons.isEmpty, "expected note-ons")
        XCTAssertTrue(ons.allSatisfy { $0.vel == 100 },
                      "a uniform vel-100 chord should arp at velocity 100 (velocity inheritance)")
    }
}
