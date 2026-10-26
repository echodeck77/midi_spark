//  SourceStackTests.swift
//  SOURCES STACK ferry (Paul 2026-10-26): MIDI IN always listens; CHORDS and KEY stack under it.
//  Pure tests over `euclideousBuildSourceStack`, the §0.1 grace helper, and the model resolvers — no engine/UI.
//  The §9 numbered tests map 1:1 to the methods below.

import XCTest

final class SourceStackTests: XCTestCase {

    /// Build the stack from plain arrays; returns (status, the merged pool notes+vels, the status chip buffer).
    private func build(midi: [(Int, UInt8)] = [], midiPlaying: Bool = false,
                       chords: [Int] = [], rest: Bool = false, key: [Int] = [],
                       plan: SourcePlan, clash: ClashPolicy = .allow, cap: Int = 128)
        -> (r: EuclideousStackResult, pool: [(note: Int, vel: UInt8)], chips: [UInt8]) {
        var dest = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128)
        var chips = [UInt8](repeating: 0, count: 8)
        let m = midi.map { (note: $0.0, vel: $0.1) }
        let r = euclideousBuildSourceStack(into: &dest, cap: cap, midi: m[...], midiPlaying: midiPlaying,
                                           chords: chords[...], chordsIsRest: rest, key: key[...],
                                           plan: plan, clash: clash, midiStatusOut: &chips)
        return (r, Array(dest[0..<r.count]), chips)
    }
    private func notes(_ pool: [(note: Int, vel: UInt8)]) -> [Int] { pool.map { $0.note } }
    private let cMajorBaseOctave = [48, 50, 52, 53, 55, 57, 59]   // C D E F G A B at base C3=48
    private let allOff = SourcePlan()
    private let chordsAlways = SourcePlan(chordsWithMidi: true, chordsNoMidi: true)
    private let keyAlways = SourcePlan(keyWithMidi: true, keyNoMidi: true)
    private let allOn = SourcePlan(chordsWithMidi: true, chordsNoMidi: true, keyWithMidi: true, keyNoMidi: true)

    // 1. MIDI-only (plan all false) returns exactly today's MIDI pool — the held notes, ascending, vels intact.
    func testMidiOnlyIsByteIdenticalToLegacyPool() {
        let (r, pool, chips) = build(midi: [(60, 100), (64, 90), (67, 80)], midiPlaying: true, plan: allOff)
        XCTAssertEqual(notes(pool), [60, 64, 67])
        XCTAssertEqual(pool.map { $0.vel }, [100, 90, 80], "MIDI keeps its live velocities")
        XCTAssertEqual(r.midiAdmitted, 3); XCTAssertTrue(r.midiPlaying)
        XCTAssertFalse(r.chordsLit); XCTAssertFalse(r.keyLit)
        XCTAssertEqual(Array(chips.prefix(3)), [60, 64, 67])
    }

    // 2. CHORDS-only matches today's chord arm: the chord notes at the default velocity 100, ascending.
    func testChordsOnlyMatchesLegacyChordArm() {
        let (r, pool, _) = build(chords: [60, 64, 67], plan: chordsAlways)
        XCTAssertEqual(notes(pool), [60, 64, 67])
        XCTAssertEqual(pool.map { $0.vel }, [100, 100, 100])
        XCTAssertTrue(r.chordsLit); XCTAssertFalse(r.keyLit); XCTAssertFalse(r.midiPlaying)
    }

    // 3. KEY-only matches today's .key arm: the scale in the base octave at velocity 100 (the golden path).
    func testKeyOnlyMatchesLegacyKeyArm() {
        let (r, pool, _) = build(key: cMajorBaseOctave, plan: keyAlways)
        XCTAssertEqual(notes(pool), cMajorBaseOctave)
        XCTAssertEqual(pool.map { $0.vel }, Array(repeating: UInt8(100), count: 7))
        XCTAssertTrue(r.keyLit); XCTAssertEqual(r.keyAdded, 7)
    }

    // 4. All three contributing: priority MIDI→CHORDS→KEY, final pool strictly ascending, PC-deduped.
    func testStackOrderMidiChordsKeyAscending() {
        // MIDI C4; CHORDS D F A (no dup); KEY C-major fills E G B around the mean. ALLOW.
        let (r, pool, _) = build(midi: [(60, 100)], midiPlaying: true, chords: [62, 65, 69], key: cMajorBaseOctave, plan: allOn)
        XCTAssertEqual(notes(pool), notes(pool).sorted(), "the merged pool is ascending")
        XCTAssertTrue(notes(pool).contains(60), "MIDI note survives as the base layer")
        XCTAssertEqual(r.count, 7, "C + D F A + E G B (all distinct PCs)")
        XCTAssertEqual(pool.first { $0.note == 60 }?.vel, 100, "MIDI keeps its velocity; generated layers use 100")
    }

    // 5. The four plan bools gate CHORDS/KEY by the live MIDI state.
    func testConditionWithMidiVsNoMidi() {
        let chordsWhileMidiOnly = SourcePlan(chordsWithMidi: true, chordsNoMidi: false)
        // no MIDI held → the "while MIDI plays" cell is unmet → CHORDS silent → empty pool.
        let a = build(midiPlaying: false, chords: [64, 67], plan: chordsWhileMidiOnly)
        XCTAssertEqual(a.r.count, 0)
        // a note held → CHORDS joins.
        let b = build(midi: [(60, 100)], midiPlaying: true, chords: [64, 67], plan: chordsWhileMidiOnly)
        XCTAssertTrue(b.r.chordsLit); XCTAssertTrue(notes(b.pool).contains(64))
    }

    // 6. A CHORDS rest silences KEY (while CHORDS's condition holds) but never silences MIDI; CHORDS off lets KEY through a rest.
    func testChordsRestSilencesKeyNotMidi() {
        // both set to play, no MIDI, a REST column → nothing from CHORDS, KEY silenced → empty; status says rest.
        let a = build(midiPlaying: false, chords: [], rest: true, key: cMajorBaseOctave, plan: allOn)
        XCTAssertEqual(a.r.count, 0); XCTAssertTrue(a.r.chordsRest); XCTAssertFalse(a.r.keyLit)
        // a note held through the rest → MIDI still plays, KEY still silenced.
        let b = build(midi: [(60, 100)], midiPlaying: true, chords: [], rest: true, key: cMajorBaseOctave, plan: allOn)
        XCTAssertEqual(notes(b.pool), [60]); XCTAssertFalse(b.r.keyLit); XCTAssertTrue(b.r.chordsRest)
        // CHORDS OFF (its condition unmet) → the §2.6 silence does not apply → KEY plays through the rest.
        let c = build(midiPlaying: false, chords: [], rest: true, key: cMajorBaseOctave, plan: keyAlways)
        XCTAssertEqual(notes(c.pool), cMajorBaseOctave); XCTAssertTrue(c.r.keyLit)
    }

    // 7. CLASHES DROP: a lower layer's note a semitone from a higher layer's admitted PC is dropped; same-layer never drops.
    func testClashDropWidensPlusMinusOne() {
        // CHORDS C E G + KEY C-major, MIDI empty, DROP. KEY keeps D and A, drops F (±1 of E) and B (±1 of C).
        let (r, pool, _) = build(chords: [60, 64, 67], key: cMajorBaseOctave, plan: allOn, clash: .drop)
        XCTAssertEqual(notes(pool), [57, 60, 62, 64, 67], "C E G + D(62) + A(57); F and B dropped")
        XCTAssertEqual(r.keyAdded, 2)
        // a Cmaj7 keeps BOTH B and C: they are same-layer (the chord), which never drops against itself.
        let maj7 = build(chords: [60, 64, 67, 71], key: cMajorBaseOctave, plan: allOn, clash: .drop)
        XCTAssertTrue(notes(maj7.pool).contains(60) && notes(maj7.pool).contains(71), "Cmaj7's own B and C both survive")
    }

    // 8. CLASHES ALLOW keeps the full union (same inputs as 7).
    func testClashAllowKeepsEverything() {
        let (r, pool, _) = build(chords: [60, 64, 67], key: cMajorBaseOctave, plan: allOn, clash: .allow)
        XCTAssertEqual(notes(pool), [57, 59, 60, 62, 64, 65, 67], "C E G + A B D F, nothing dropped")
        XCTAssertEqual(r.keyAdded, 4)
    }

    // 9. KEY notes land in the octave nearest the mean of the admitted MIDI+CHORDS notes, ties to the lower note.
    func testKeyNearestMeanOctavePlacement() {
        // CHORDS C4 E4 G4 (mean 63); A is equidistant between A3(57) and A4(69) → the lower, 57, wins.
        let (_, pool, _) = build(chords: [60, 64, 67], key: cMajorBaseOctave, plan: allOn)
        XCTAssertTrue(notes(pool).contains(57), "A placed at A3 (tie → lower octave), not A4(69)")
        XCTAssertFalse(notes(pool).contains(69))
        XCTAssertEqual(Set(notes(pool)).subtracting([60, 64, 67]), [57, 59, 62, 65], "D4 F4 A3 B3 around the mean")
    }

    // 10. RELEASE GRACE arithmetic: MIDI counts as playing within 50 ms of its last non-empty window, not after.
    func testReleaseGraceKeepsMidiPlaying() {
        let sr = 48000.0   // grace = 2400 samples
        XCTAssertTrue(euclideousMidiPlaying(nonEmpty: true, windowStart: 1_000_000, lastNonEmptySample: 0, sampleRate: sr))
        XCTAssertTrue(euclideousMidiPlaying(nonEmpty: false, windowStart: 2399, lastNonEmptySample: 0, sampleRate: sr), "49.98 ms: still playing")
        XCTAssertFalse(euclideousMidiPlaying(nonEmpty: false, windowStart: 2400, lastNonEmptySample: 0, sampleRate: sr), "exactly 50 ms: ended")
        XCTAssertFalse(euclideousMidiPlaying(nonEmpty: false, windowStart: 2880, lastNonEmptySample: 0, sampleRate: sr), "60 ms gap: ended")
    }

    // 11. The status byproduct matches the merge (chips, counts, lights).
    func testSourceStatusByproduct() {
        let (r, _, chips) = build(midi: [(60, 100), (64, 100)], midiPlaying: true, chords: [67], key: cMajorBaseOctave, plan: allOn)
        XCTAssertEqual(r.midiAdmitted, 2); XCTAssertTrue(r.midiPlaying)
        XCTAssertEqual(Array(chips.prefix(2)), [60, 64], "the MIDI chips")
        XCTAssertTrue(r.chordsLit); XCTAssertFalse(r.chordsRest)
        XCTAssertTrue(r.keyLit); XCTAssertGreaterThan(r.keyAdded, 0)
    }

    // 12a. The CLASHES resolver: DEBUG honours the stored value; nil ⇒ ALLOW. (Release forces ALLOW — compile-time,
    //      verified by reading the #else; this test runs in DEBUG.)
    func testClashPolicyResolver() {
        var st = PluginState(machines: [], scenes: [SceneState.empty()])
        XCTAssertEqual(st.clashPolicyResolved, .allow, "nil ⇒ ALLOW")
        st.euclideousClashPolicy = .drop
        #if DEBUG
        XCTAssertEqual(st.clashPolicyResolved, .drop, "DEBUG honours a stored DROP")
        #else
        XCTAssertEqual(st.clashPolicyResolved, .allow, "release forces ALLOW")
        #endif
    }

    // 12b. Decode-tolerance: a document missing the new keys decodes, and SourcePlan derives from the legacy source.
    func testSourcePlanDecodeTolerantAndDerives() throws {
        var midiDoc = PluginState(machines: [], scenes: [SceneState.empty()]); midiDoc.euclideousNoteSource = .midi
        XCTAssertEqual(midiDoc.sourcePlanResolved, SourcePlan(), "MIDI ⇒ all false")
        var chordsDoc = PluginState(machines: [], scenes: [SceneState.empty()]); chordsDoc.euclideousNoteSource = .chords
        XCTAssertEqual(chordsDoc.sourcePlanResolved, chordsAlways, "CHORDS ⇒ chords always")
        var keyDoc = PluginState(machines: [], scenes: [SceneState.empty()]); keyDoc.euclideousNoteSource = .key
        XCTAssertEqual(keyDoc.sourcePlanResolved, keyAlways, "KEY ⇒ key always")
        // round-trip: nil fields decode absent; an explicit plan survives.
        let decodedNil = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(PluginState(machines: [], scenes: [SceneState.empty()])))
        XCTAssertNil(decodedNil.euclideousSourcePlan); XCTAssertNil(decodedNil.euclideousClashPolicy)
        var set = PluginState(machines: [], scenes: [SceneState.empty()])
        set.euclideousSourcePlan = SourcePlan(chordsWithMidi: true, keyNoMidi: true); set.euclideousClashPolicy = .drop
        let decodedSet = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(set))
        XCTAssertEqual(decodedSet.euclideousSourcePlan, SourcePlan(chordsWithMidi: true, keyNoMidi: true))
        XCTAssertEqual(decodedSet.euclideousClashPolicy, .drop)
    }
}
