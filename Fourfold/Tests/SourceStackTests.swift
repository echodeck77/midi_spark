//  SourceStackTests.swift
//  Sources panel v2 (Paul 2026-10-28): four switchable sources (MIDI IN · CHORDS · PICK · KEY) in priority order,
//  a MIDI ADD/REPLACE choice, tapped-in PICK notes. Amends the SOURCES STACK ferry (2026-10-26).
//  Pure tests over `euclideousBuildSourceStack`, the §0.1 grace helper, and the model resolvers (§1.1-§1.3) — no
//  engine/UI. The §9 numbered tests map 1:1 to the methods below (§9.11 undo / §9.12 geometry / §9.13 PICK editor
//  ride the UI slices, not this file).

import XCTest

final class SourceStackTests: XCTestCase {

    /// Build the stack from plain arrays; returns (status, the merged pool notes+vels, the status chip buffer).
    private func build(midi: [(Int, UInt8)] = [], midiPlaying: Bool = false,
                       chords: [Int] = [], rest: Bool = false, pick: [Int] = [], key: [Int] = [],
                       plan: SourcePlan, clash: ClashPolicy = .allow, cap: Int = 128)
        -> (r: EuclideousStackResult, pool: [(note: Int, vel: UInt8)], chips: [UInt8]) {
        var dest = [(note: Int, vel: UInt8)](repeating: (0, 0), count: 128)
        var chips = [UInt8](repeating: 0, count: 8)
        let m = midi.map { (note: $0.0, vel: $0.1) }
        let r = euclideousBuildSourceStack(into: &dest, cap: cap, midi: m[...], midiPlaying: midiPlaying,
                                           chords: chords[...], chordsIsRest: rest, pick: pick[...], key: key[...],
                                           plan: plan, clash: clash, midiStatusOut: &chips)
        return (r, Array(dest[0..<r.count]), chips)
    }
    private func notes(_ pool: [(note: Int, vel: UInt8)]) -> [Int] { pool.map { $0.note } }
    /// A RESOLVED v2 plan (the shape `sourcePlanResolved` always returns and the engine reads).
    private func plan(midi: Bool = true, chords: Bool = false, pick: Bool = false, key: Bool = false,
                      mode: MidiMode = .add, pickNotes: [UInt8] = []) -> SourcePlan {
        SourcePlan(midiOn: midi, chordsOn: chords, pickOn: pick, keyOn: key, midiMode: mode, pickNotes: pickNotes)
    }
    private let cMajorBaseOctave = [48, 50, 52, 53, 55, 57, 59]      // C D E F G A B at base C3=48
    private let aMinorBaseOctave = [57, 59, 60, 62, 64, 65, 67]      // A B C D E F G (base 48 + root 9 + natural-minor)

    // ───────────────────────────────── §9.1 legacy derivation + byte-identity ─────────────────────────────────
    // MIDI/CHORDS/KEY documents derive §1.2; with nothing held CHORDS and KEY pools match today's exactly; MIDI
    // matches today in every case; a document without the v2 fields round-trips without loss.
    func testLegacyDerivationAndByteIdentity() throws {
        func doc(_ s: EuclideousLaneSource) -> PluginState {
            var d = PluginState(machines: [], scenes: [SceneState.empty()]); d.euclideousNoteSource = s; return d
        }
        XCTAssertEqual(doc(.midi).sourcePlanResolved,   plan(midi: true), "MIDI ⇒ midiOn only")
        XCTAssertEqual(doc(.chords).sourcePlanResolved, plan(midi: true, chords: true), "CHORDS ⇒ midiOn + chordsOn")
        XCTAssertEqual(doc(.key).sourcePlanResolved,    plan(midi: true, key: true), "KEY ⇒ midiOn + keyOn")
        // nothing held: CHORDS/KEY pools are exactly the single-source pools (byte-identical to SOURCES STACK).
        XCTAssertEqual(notes(build(chords: [60, 64, 67], plan: doc(.chords).sourcePlanResolved).pool), [60, 64, 67])
        XCTAssertEqual(notes(build(key: cMajorBaseOctave, plan: doc(.key).sourcePlanResolved).pool), cMajorBaseOctave)
        // MIDI in every case: held ⇒ the held notes; nothing held ⇒ empty.
        XCTAssertEqual(notes(build(midi: [(60, 100)], midiPlaying: true, plan: doc(.midi).sourcePlanResolved).pool), [60])
        XCTAssertEqual(build(plan: doc(.midi).sourcePlanResolved).r.count, 0)
        // round-trip: a document without the fields decodes with nil plan.
        let decoded = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(PluginState(machines: [], scenes: [SceneState.empty()])))
        XCTAssertNil(decoded.euclideousSourcePlan)
    }

    // ───────────────────────────────── §9.2 Route A: the 16 legacy-cell combinations ─────────────────────────────
    // Each of the 16 combinations of the old four cells maps as §1.3: chordsOn/keyOn = either of that row's cells;
    // midiOn true; REPLACE iff every LIT row is lit for NO-MIDI-only (vacuously ADD when nothing is lit).
    func testRouteALegacyCellMapping() {
        for bits in 0..<16 {
            let cWM = bits & 1 != 0, cNM = bits & 2 != 0, kWM = bits & 4 != 0, kNM = bits & 8 != 0
            var legacy = SourcePlan()
            legacy.chordsWithMidi = cWM; legacy.chordsNoMidi = cNM; legacy.keyWithMidi = kWM; legacy.keyNoMidi = kNM
            var d = PluginState(machines: [], scenes: [SceneState.empty()]); d.euclideousSourcePlan = legacy
            let r = d.sourcePlanResolved
            let chordsOn = cWM || cNM, keyOn = kWM || kNM
            let allLitNoMidiOnly = (!chordsOn || (cNM && !cWM)) && (!keyOn || (kNM && !kWM))
            let expectMode: MidiMode = (chordsOn || keyOn) && allLitNoMidiOnly ? .replace : .add
            XCTAssertEqual(r.midiOnR, true, "bits \(bits): midiOn true")
            XCTAssertEqual(r.chordsOnR, chordsOn, "bits \(bits): chordsOn")
            XCTAssertEqual(r.keyOnR, keyOn, "bits \(bits): keyOn")
            XCTAssertEqual(r.pickOnR, false, "bits \(bits): pick off")
            XCTAssertEqual(r.midiModeR, expectMode, "bits \(bits): mode")
        }
    }

    // ───────────────────────────────── §9.3 single layer ─────────────────────────────
    func testSingleLayerPools() {
        // MIDI only.
        XCTAssertEqual(notes(build(midi: [(60, 100), (64, 90)], midiPlaying: true, plan: plan(midi: true)).pool), [60, 64])
        // CHORDS only (nothing held).
        let c = build(chords: [60, 64, 67], plan: plan(chords: true))
        XCTAssertEqual(notes(c.pool), [60, 64, 67]); XCTAssertEqual(c.pool.map { $0.vel }, [100, 100, 100]); XCTAssertTrue(c.r.chordsLit)
        // PICK only {C4, E4, G4} ascending.
        let p = build(pick: [60, 64, 67], plan: plan(pick: true))
        XCTAssertEqual(notes(p.pool), [60, 64, 67]); XCTAssertTrue(p.r.pickLit); XCTAssertEqual(p.r.pickAdded, 3)
        // KEY only = today's KEY pool.
        let k = build(key: cMajorBaseOctave, plan: plan(key: true))
        XCTAssertEqual(notes(k.pool), cMajorBaseOctave); XCTAssertEqual(k.r.keyAdded, 7); XCTAssertTrue(k.r.keyLit)
    }

    // ───────────────────────────────── §9.4 priority, ADD ─────────────────────────────
    func testPriorityAddMidiChordsPickKey() {
        // MIDI C3 E3 G3; + CHORDS A-minor (A C E) adds only A; + PICK {C#4, A4} adds only C#4; + KEY A-minor fills
        // the remaining scale PCs (B D F) nearest the mean; dropped = 0 at cap 128.
        let r = build(midi: [(48, 100), (52, 100), (55, 100)], midiPlaying: true,
                      chords: [57, 60, 64], pick: [61, 69], key: aMinorBaseOctave,
                      plan: plan(midi: true, chords: true, pick: true, key: true))
        XCTAssertEqual(r.r.midiAdded, 3)
        XCTAssertEqual(r.r.chordsAdded, 1, "CHORDS adds only A (C and E duplicate MIDI's PCs)")
        XCTAssertTrue(notes(r.pool).contains(57))
        XCTAssertEqual(r.r.pickAdded, 1, "PICK adds only C#4 (A4 duplicates CHORDS's A)")
        XCTAssertTrue(notes(r.pool).contains(61))
        XCTAssertEqual(r.r.keyAdded, 3, "KEY fills B D F — the A-minor PCs not already present")
        XCTAssertEqual(r.r.midiAdded + r.r.chordsAdded + r.r.pickAdded + r.r.keyAdded, r.r.count)
        XCTAssertEqual(r.r.dropped, 0)
    }

    // ───────────────────────────────── §9.5 REPLACE ─────────────────────────────
    func testReplaceStepsLowerLayersAsideWhileMidiPlays() {
        let p = plan(midi: true, chords: true, pick: true, key: true, mode: .replace)
        // nothing held ⇒ CHORDS + PICK + KEY all contribute.
        let idle = build(midiPlaying: false, chords: [67], pick: [61], key: cMajorBaseOctave, plan: p)
        XCTAssertTrue(idle.r.chordsLit && idle.r.pickLit && idle.r.keyLit)
        XCTAssertTrue(notes(idle.pool).contains(67) && notes(idle.pool).contains(61))
        // holding a note ⇒ MIDI only (lower layers stepped aside).
        let held = build(midi: [(60, 100)], midiPlaying: true, chords: [67], pick: [61], key: cMajorBaseOctave, plan: p)
        XCTAssertEqual(notes(held.pool), [60])
        XCTAssertFalse(held.r.chordsLit); XCTAssertFalse(held.r.pickLit); XCTAssertFalse(held.r.keyLit)
        // the 50 ms / 60 ms grace boundary that makes a legato chord change safe is §9.10 (euclideousMidiPlaying).
    }

    // ───────────────────────────────── §9.6 MIDI IN off ─────────────────────────────
    func testMidiOffKeepsHeldNotesOutAndDisablesReplace() {
        // MIDI switch off, a note held: it stays OUT of the pool; MIDI reads not-playing; CHORDS/KEY still play.
        let p = plan(midi: false, chords: true, key: true, mode: .replace)   // REPLACE must have no effect with MIDI off
        let r = build(midi: [(60, 100)], midiPlaying: true, chords: [67], key: cMajorBaseOctave, plan: p)
        XCTAssertFalse(notes(r.pool).contains(60), "held MIDI note is ignored while MIDI IN is off")
        XCTAssertFalse(r.r.midiPlaying, "MIDI reads not-playing while its switch is off")
        XCTAssertTrue(r.r.chordsLit && r.r.keyLit, "REPLACE has no effect with MIDI off — lower layers play")
        XCTAssertEqual(r.r.midiAdded, 0)
    }

    // ───────────────────────────────── §9.7 REST column ─────────────────────────────
    func testRestColumnSilencesKeyButNotPickOrMidi() {
        // CHORDS + KEY on, a REST column, PICK on, a note held: CHORDS adds nothing & silences KEY; PICK and MIDI play.
        let a = build(midi: [(60, 100)], midiPlaying: true, chords: [], rest: true, pick: [62], key: cMajorBaseOctave,
                      plan: plan(midi: true, chords: true, pick: true, key: true))
        XCTAssertTrue(notes(a.pool).contains(60) && notes(a.pool).contains(62))
        XCTAssertFalse(a.r.keyLit); XCTAssertTrue(a.r.chordsRest); XCTAssertTrue(a.r.pickLit)
        // CHORDS OFF ⇒ the §2.6 silence does not apply ⇒ KEY plays through the rest.
        let b = build(midiPlaying: false, chords: [], rest: true, key: cMajorBaseOctave, plan: plan(key: true))
        XCTAssertEqual(notes(b.pool), cMajorBaseOctave); XCTAssertTrue(b.r.keyLit)
    }

    // ───────────────────────────────── §9.8 CLASHES DROP (+ PICK never drops) ─────────────────────────────
    func testClashDropWidensButNeverDropsPick() {
        // CHORDS C E G + KEY C-major, DROP: KEY keeps D and A, drops F (±1 of E) and B (±1 of C). (SOURCES STACK test 7.)
        let r = build(chords: [60, 64, 67], key: cMajorBaseOctave, plan: plan(chords: true, key: true), clash: .drop)
        XCTAssertEqual(notes(r.pool), [57, 60, 62, 64, 67], "C E G + D(62) + A(57); F and B dropped")
        XCTAssertEqual(r.r.keyAdded, 2)
        // a pick a semitone from a chord tone STAYS (PICK is never dropped by the clash policy).
        let p = build(chords: [60, 64, 67], pick: [61], key: cMajorBaseOctave, plan: plan(chords: true, pick: true, key: true), clash: .drop)
        XCTAssertTrue(notes(p.pool).contains(61), "a picked C#, a semitone from the chord's C, survives DROP")
    }

    // ───────────────────────────────── §9.9 counts ─────────────────────────────
    // In the §9.3-§9.8 shapes the added counts sum to the pool size and dropped is 0; dropped counts ONLY cap overflow.
    func testAddedCountsSumToPoolAndDroppedIsCapOverflowOnly() {
        let r = build(midi: [(60, 100)], midiPlaying: true, chords: [62, 65, 69], key: cMajorBaseOctave,
                      plan: plan(midi: true, chords: true, key: true))
        XCTAssertEqual(r.r.midiAdded + r.r.chordsAdded + r.r.pickAdded + r.r.keyAdded, r.r.count)
        XCTAssertEqual(r.r.dropped, 0)
        // a tiny cap forces overflow: MIDI(2) + CHORDS(4 distinct) at cap 4 ⇒ 4 placed, 2 dropped; PC dups/clashes excluded.
        let o = build(midi: [(60, 100), (64, 100)], midiPlaying: true, chords: [62, 65, 69, 71],
                      plan: plan(midi: true, chords: true), cap: 4)
        XCTAssertEqual(o.r.count, 4)
        XCTAssertEqual(o.r.midiAdded + o.r.chordsAdded, 4)
        XCTAssertEqual(o.r.dropped, 2, "two chord notes wanted in but the cap was full")
    }

    // ───────────────────────────────── §9.10 status off/playing/waiting ─────────────────────────────
    func testStatusPerSource() {
        // playing: the condition is met. KEY can be playing (contributes) even when it adds 0 (all its PCs present).
        let keyAdds0 = build(midi: [(60, 100), (62, 100), (64, 100), (65, 100), (67, 100), (69, 100), (71, 100)],
                             midiPlaying: true, key: cMajorBaseOctave, plan: plan(midi: true, key: true))
        XCTAssertTrue(keyAdds0.r.keyLit, "KEY is playing"); XCTAssertEqual(keyAdds0.r.keyAdded, 0, "but adds nothing new")
        // waiting: on but not contributing (nothing picked).
        let pickEmpty = build(plan: plan(pick: true))
        XCTAssertFalse(pickEmpty.r.pickLit, "PICK on with nothing picked ⇒ not playing (the UI shows waiting)")
        // MIDI not playing (switch on, nothing held) ⇒ waiting.
        XCTAssertFalse(build(plan: plan(midi: true)).r.midiPlaying)
    }

    // ───────────────────────────────── §9.10-extra RELEASE GRACE arithmetic ─────────────────────────────
    func testReleaseGraceKeepsMidiPlaying() {
        let sr = 48000.0   // grace = 2400 samples
        XCTAssertTrue(euclideousMidiPlaying(nonEmpty: true, windowStart: 1_000_000, lastNonEmptySample: 0, sampleRate: sr))
        XCTAssertTrue(euclideousMidiPlaying(nonEmpty: false, windowStart: 2399, lastNonEmptySample: 0, sampleRate: sr), "49.98 ms: still playing")
        XCTAssertFalse(euclideousMidiPlaying(nonEmpty: false, windowStart: 2400, lastNonEmptySample: 0, sampleRate: sr), "exactly 50 ms: ended")
        XCTAssertFalse(euclideousMidiPlaying(nonEmpty: false, windowStart: 2880, lastNonEmptySample: 0, sampleRate: sr), "60 ms gap: ended")
    }

    // ───────────────────────────────── model: resolver, decode, CLASHES ─────────────────────────────
    // §1.1 a v2-written plan is returned with its nil v2 fields filled; §1.3 maps a legacy cell plan; the decode is
    // additive-tolerant and CLASHES resolves per build config.
    func testResolverDecodeAndClashPolicy() throws {
        // §1.1 a v2 plan survives (nil fields fill to neutral defaults).
        var d = PluginState(machines: [], scenes: [SceneState.empty()])
        d.euclideousSourcePlan = SourcePlan(midiOn: true, chordsOn: true, pickOn: true, keyOn: false, midiMode: .replace, pickNotes: [60, 64])
        XCTAssertEqual(d.sourcePlanResolved, plan(midi: true, chords: true, pick: true, key: false, mode: .replace, pickNotes: [60, 64]))
        // decode: an explicit v2 plan + CLASHES round-trip.
        let decoded = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(decoded.euclideousSourcePlan?.pickNotes ?? [], [60, 64])
        // CLASHES resolver (DEBUG honours stored; nil ⇒ ALLOW).
        var st = PluginState(machines: [], scenes: [SceneState.empty()])
        XCTAssertEqual(st.clashPolicyResolved, .allow, "nil ⇒ ALLOW")
        st.euclideousClashPolicy = .drop
        #if DEBUG
        XCTAssertEqual(st.clashPolicyResolved, .drop)
        #else
        XCTAssertEqual(st.clashPolicyResolved, .allow)
        #endif
    }

    // §9.13 the PICK editor: toggle (ascending, deduped, ≤16) + the opening octave (default / range).
    func testPickEditorToggleAndOctave() {
        XCTAssertEqual(euclideousPickToggle([60, 64], 62), [60, 62, 64], "an add lands ascending")
        XCTAssertEqual(euclideousPickToggle([60, 64], 60), [64], "tapping a picked note removes it")
        let full = Array<UInt8>(60..<76)   // 16 notes
        XCTAssertEqual(euclideousPickToggle(full, 59).count, 16, "a 17th note is dropped (the 16-note limit)")
        XCTAssertEqual(euclideousPickToggle(full, 60), Array<UInt8>(61..<76), "removing one of the 16 still works")
        // the opening octave NUMBER (C4-convention): lowest picked note's octave, else middle C (4), clamped 1…7.
        XCTAssertEqual(euclideousPickEditorDefaultOctave([]), 4)
        XCTAssertEqual(euclideousPickEditorDefaultOctave([60]), 4, "C4 = 60 → octave 4")
        XCTAssertEqual(euclideousPickEditorDefaultOctave([36]), 2, "C2 = 36 → octave 2")
        XCTAssertEqual(euclideousPickEditorDefaultOctave([127]), 7, "clamped to 7")
        XCTAssertEqual(euclideousPickEditorDefaultOctave([12]), 1, "clamped to 1")
    }
}
