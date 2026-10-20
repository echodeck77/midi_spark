//  EffectiveParamsTests.swift
//  Re-homed (2026-08-05) as the MACRO MODULATION engine tests. The old A/B-morph interpolation these once covered
//  was removed; the file is now the natural home for the macro offset model (base ⊕ value×delta) per the map's
//  recommendation. M0 here = the STATE MODEL (persistence + snapshot plumbing); M1 adds the offset-math cases.

import XCTest

final class EffectiveParamsTests: XCTestCase {

    /// A minimal valid document (macro tests don't touch machines/scenes).
    private func doc() -> PluginState { PluginState(machines: [], scenes: [SceneState.empty()]) }

    // MARK: M0 — the macro state model

    /// A clean instrument (no macros persisted) resolves to 16 unset macros, correctly banked.
    func testMacrosResolveToSixteenInTwoSpecies() {   // §K3 2026-09-01: 16 named movements = 8 SLIDER + 8 TOGGLE (timelines retired)
        let doc = self.doc()
        XCTAssertNil(doc.macros)                                   // nothing persisted on a clean instrument
        let m = doc.macrosResolved
        XCTAssertEqual(m.count, 16)
        XCTAssertEqual(PluginState.macroBankCount, 16)
        XCTAssertTrue(m.allSatisfy { $0.name.isEmpty && $0.value == 0 && !$0.fixed && $0.targets.isEmpty })
        XCTAssertEqual(PluginState.macroKind(0), .slider)
        XCTAssertEqual(PluginState.macroKind(7), .slider)
        XCTAssertEqual(PluginState.macroKind(8), .button)
        XCTAssertEqual(PluginState.macroKind(15), .button)
        // 16+ still CLASSIFY as timeline (tolerance for an old-doc index) but the live bank is 16, so nothing resolves them.
        XCTAssertEqual(PluginState.macroKind(16), .timeline)
    }

    /// A short/partial macros array is padded (missing slots ⇒ unset) — forward/back compatible like the rack arrays.
    func testMacrosResolvedIsShortArraySafe() {
        var doc = self.doc()
        doc.macros = [Macro(name: "FILT", value: 0.5, fixed: true,
                            targets: [MacroTarget(col: 1, row: 2, slot: 0, param: "gate", delta: 0.3)])]
        let m = doc.macrosResolved
        XCTAssertEqual(m.count, 16)
        XCTAssertEqual(m[0].name, "FILT")
        XCTAssertEqual(m[0].value, 0.5)
        XCTAssertTrue(m[0].fixed)
        XCTAssertEqual(m[0].targets.first?.param, "gate")
        XCTAssertTrue(m[1].name.isEmpty)                            // the rest pad to unset
    }

    /// Macros survive a JSON round-trip, and an OLD doc (no `macros` key) decodes to nil (off) — additive-Optional.
    func testMacrosRoundTripAndOldDocDecodesNil() throws {
        var doc = self.doc()
        doc.macros = doc.macrosResolved
        doc.macros?[3] = Macro(name: "SWEEP", value: 0.8, fixed: false,
                               targets: [MacroTarget(col: 4, row: 5, slot: 1, param: "spread", delta: -0.4)])
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.macros?.count, 16)
        XCTAssertEqual(back.macrosResolved[3].name, "SWEEP")
        XCTAssertEqual(back.macrosResolved[3].targets.first?.delta, -0.4)

        // An old document with no macros key: strip it, decode → nil, resolve → 16 unset.
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "macros")
        let oldData = try JSONSerialization.data(withJSONObject: obj)
        let old = try JSONDecoder().decode(PluginState.self, from: oldData)
        XCTAssertNil(old.macros)
        XCTAssertEqual(old.macrosResolved.count, 16)
    }

    /// §K3 RETIREMENT decode-safety: a doc that stored the OLD 24-macro bank (with a TIMELINE macro at 16–23 carrying a
    /// binding) must still DECODE without loss — the full stored array round-trips — but only the first 16 RESOLVE, so
    /// the retired timeline's offset simply stops applying (no crash, no factory-reset). This is how old docs land soft.
    func testOldTwentyFourMacroDocDecodesButOnlyResolvesSixteen() throws {
        var doc = self.doc()
        var full = [Macro](repeating: Macro(), count: 24)
        full[8] = Macro(name: "TOG", value: 1, fixed: false,
                        targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.2)])   // a LIVE toggle (bank 8–15)
        full[20] = Macro(name: "OLDLANE", value: 1, fixed: false,
                         targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.9)])  // a RETIRED timeline (16–23)
        doc.macros = full
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.macros?.count, 24, "the stored array round-trips whole (decode-safe, no data loss)")
        XCTAssertEqual(back.macrosResolved.count, 16, "but only 16 resolve — the timeline bank is retired")
        XCTAssertEqual(back.macrosResolved[8].name, "TOG", "the live toggle survives")
        XCTAssertFalse(back.macrosResolved.contains { $0.name == "OLDLANE" }, "the retired timeline macro is not in the live bank")
    }

    // REVIEW FIX 2026-08-26 (CR-8 class): a macro persisted BEFORE emitterTargets/laneOn/laneRate existed lacks those
    // keys; those fields are NON-Optional, so synthesized Decodable would throw → the WHOLE document decode throws →
    // silent reset (total data loss). Macro's decode-tolerant init must default the missing keys instead of throwing.
    func testMacroDecodesWithMissingNonOptionalKeys() throws {
        var doc = self.doc()
        doc.macros = doc.macrosResolved
        doc.macros?[2] = Macro(name: "OLD", value: 0.5, fixed: false, targets: [])
        let data = try JSONEncoder().encode(doc)
        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        var macros = obj["macros"] as! [[String: Any]]
        for i in macros.indices {   // strip the fields added after Macro first persisted
            macros[i].removeValue(forKey: "emitterTargets"); macros[i].removeValue(forKey: "laneOn"); macros[i].removeValue(forKey: "laneRate")
        }
        obj["macros"] = macros
        let stripped = try JSONSerialization.data(withJSONObject: obj)
        let back = try JSONDecoder().decode(PluginState.self, from: stripped)   // MUST NOT throw
        XCTAssertEqual(back.macrosResolved[2].name, "OLD")
        XCTAssertEqual(back.macrosResolved[2].laneRate, 3, "laneRate defaults to 3 when the key is absent")
        XCTAssertFalse(back.macrosResolved[2].laneOn)
        XCTAssertTrue(back.macrosResolved[2].emitterTargets.isEmpty)
    }

    // REVIEW FIX 2026-08-26: EuclidLine.die was added NON-Optional; a euclidLines doc saved before it lacks the key and
    // would throw on decode. die is now Optional → a pre-die line decodes with die defaulting to 0.
    func testEuclidLineDecodesWithoutDieKey() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertEqual(line.dieResolved, 0)
        XCTAssertNil(line.pick)
        XCTAssertEqual(line.pulses, 5)
    }

    // EUCLIDEOUS (Paul 2026-10-05): rate/emitterMask are the newest two EuclidLine fields — same CR-8 contract as
    // die/noteSel/gate/etc above, a doc saved before they existed must still decode without throwing.
    func testEuclidLineDecodesWithoutRateOrEmitterMaskKeys() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertNil(line.rate, "nil ⇒ inherit the machine-wide rate")
        XCTAssertNil(line.emitterMask, "nil ⇒ inherit the cell's own bus mask")
    }
    func testEuclidLineRateAndEmitterMaskRoundTripThroughCodable() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.rate = .r1_8t
        line.emitterMask = 0b0101   // A + C
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertEqual(back.rate, .r1_8t)
        XCTAssertEqual(back.emitterMask, 0b0101)
    }

    // RIFF ADVANCE (Paul 2026-10-06): useRiff/riffRotate/riffOctave are the newest three EuclidLine fields — same
    // CR-8 contract as rate/emitterMask above, a doc saved before they existed must still decode without throwing.
    func testEuclidLineDecodesWithoutRiffAdvanceKeys() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertFalse(line.useRiffResolved, "nil ⇒ off, byte-identical for every existing doc")
        XCTAssertEqual(line.riffRotateResolved, 0)
        XCTAssertEqual(line.riffOctaveResolved, 0)
    }
    func testEuclidLineRiffAdvanceRoundTripsThroughCodable() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.useRiff = true
        line.riffRotate = 5
        line.riffOctave = -2
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertTrue(back.useRiffResolved)
        XCTAssertEqual(back.riffRotateResolved, 5)
        XCTAssertEqual(back.riffOctaveResolved, -2)
    }
    // OCT RANGE −2…+2 (Paul 2026-10-13 ferry, "Engine" rule 4) — narrowed from the original ±3, Euclideous-only
    // (riffOctave is exclusive to Euclideous's own riff mechanism, confirmed by grep before narrowing — unlike
    // the shared `octave` field, which stays ±3 since the regular, non-Euclideous BUILD-page EUCLID processor's
    // own OCTAVE stepper reads it too).
    func testEuclidLineRiffOctaveClampsToPlusMinusTwo() {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.riffOctave = 9
        XCTAssertEqual(line.riffOctaveResolved, 2)
        line.riffOctave = -9
        XCTAssertEqual(line.riffOctaveResolved, -2)
    }
    // MELODY MODE MIGRATION (Paul 2026-10-13 ferry, "MELODY tab on the lane cards") — `melodyMode` is the
    // new single source of truth for a lane's note/riff choice, migrating from the legacy `useRiff: Bool?`
    // when absent: nil ⇒ derive from `useRiff` (nil/false ⇒ NOTE, true ⇒ RIFF); an explicit `melodyMode`
    // always wins outright over whatever `useRiff` carries, even a disagreeing one.
    func testEuclidLineMelodyModeMigratesFromLegacyUseRiff() {
        XCTAssertEqual(EuclidLine(pulses: 3, steps: 8).melodyModeResolved, .note, "no legacy data at all ⇒ NOTE")
        var fromFalse = EuclidLine(pulses: 3, steps: 8); fromFalse.useRiff = false
        XCTAssertEqual(fromFalse.melodyModeResolved, .note)
        var fromTrue = EuclidLine(pulses: 3, steps: 8); fromTrue.useRiff = true
        XCTAssertEqual(fromTrue.melodyModeResolved, .riff, "legacy useRiff:true migrates to RIFF")
        XCTAssertTrue(fromTrue.useRiffResolved, "useRiffResolved now DERIVES from melodyModeResolved, not the other way round")
        var explicitWins = EuclidLine(pulses: 3, steps: 8); explicitWins.useRiff = true; explicitWins.melodyMode = .note
        XCTAssertEqual(explicitWins.melodyModeResolved, .note, "an explicit melodyMode always wins over a disagreeing legacy useRiff")
        XCTAssertFalse(explicitWins.useRiffResolved)
    }
    func testEuclidLineMelodyModeRoundTripsThroughCodableAndDecodesWithoutIt() throws {
        var line = EuclidLine(pulses: 3, steps: 8); line.melodyMode = .riff
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertEqual(back.melodyModeResolved, .riff)
        // An old doc saved before this field existed must still decode without throwing (CR-8).
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"useRiff":true}"#.utf8)
        let old = try JSONDecoder().decode(EuclidLine.self, from: json)
        XCTAssertEqual(old.melodyModeResolved, .riff, "the legacy useRiff:true still migrates correctly with no melodyMode key present at all")
    }
    // LIT NOTES PLUS THE RIFF MIGRATION (Paul 2026-10-13, second same-day ferry — "Presets and parameters")
    // — `litNotesResolved`/`topLitResolved`/`top2LitResolved`/`riffOnResolved` migrate from BOTH prior eras
    // via the SAME already-tested `melodyModeResolved`/`noteSelResolved` chain, with no era-branching of
    // their own (confirmed: era 2's own UI never produces the "any other value" case).
    func testEuclidLineLitNotesMigratesFromAGenuinelyFreshLine() {
        let fresh = EuclidLine(pulses: 3, steps: 8)
        XCTAssertEqual(fresh.litNotesResolved, 0, "a genuinely untouched line has nothing lit")
        XCTAssertFalse(fresh.topLitResolved); XCTAssertFalse(fresh.top2LitResolved)
        XCTAssertTrue(fresh.riffOnResolved, "the ferry's own stated fresh-lane default: riff on")
        XCTAssertFalse(fresh.litMigrationNeedsWarning)
    }
    func testEuclidLineLitNotesMigratesFromEra1UseRiffBool() {
        var riffOn = EuclidLine(pulses: 3, steps: 8); riffOn.useRiff = true
        XCTAssertEqual(riffOn.litNotesResolved, 0); XCTAssertTrue(riffOn.riffOnResolved)
        var lowest = EuclidLine(pulses: 3, steps: 8); lowest.useRiff = false; lowest.noteSel = .low
        XCTAssertEqual(lowest.litNotesResolved, 0b0000_0001, "LOWEST migrates to rank 1 lit")
        XCTAssertFalse(lowest.riffOnResolved)
        var noteN = EuclidLine(pulses: 3, steps: 8); noteN.useRiff = false; noteN.noteSel = .n5
        XCTAssertEqual(noteN.litNotesResolved, 0b0001_0000, "note 5 migrates to rank 5 lit")
        var highest = EuclidLine(pulses: 3, steps: 8); highest.useRiff = false; highest.noteSel = .high
        XCTAssertTrue(highest.topLitResolved, "HIGHEST migrates to TOP lit"); XCTAssertEqual(highest.litNotesResolved, 0)
        var ambiguous = EuclidLine(pulses: 3, steps: 8); ambiguous.useRiff = false; ambiguous.noteSel = .cycle
        XCTAssertEqual(ambiguous.litNotesResolved, 0b0000_0001, "any other legacy value: 1 lit")
        XCTAssertFalse(ambiguous.riffOnResolved)
        XCTAssertTrue(ambiguous.litMigrationNeedsWarning, "and logged — the 'any other value' case needs the one-time migration warning")
    }
    func testEuclidLineLitNotesMigratesFromEra2MelodyModeField() {
        var noteN = EuclidLine(pulses: 3, steps: 8); noteN.melodyMode = .note; noteN.noteSel = .n3
        XCTAssertEqual(noteN.litNotesResolved, 0b0000_0100, "note 3 (era 2) migrates to rank 3 lit")
        XCTAssertFalse(noteN.riffOnResolved)
        var top2 = EuclidLine(pulses: 3, steps: 8); top2.melodyMode = .note; top2.noteSel = .top2
        XCTAssertTrue(top2.top2LitResolved); XCTAssertFalse(top2.topLitResolved); XCTAssertEqual(top2.litNotesResolved, 0)
        var riff = EuclidLine(pulses: 3, steps: 8); riff.melodyMode = .riff
        XCTAssertEqual(riff.litNotesResolved, 0); XCTAssertTrue(riff.riffOnResolved)
        XCTAssertFalse(riff.litMigrationNeedsWarning, "era 2's own UI never produces the 'any other value' case")
    }
    func testEuclidLineLitNotesExplicitFieldsAlwaysWinOverLegacy() {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.useRiff = true           // legacy says riff on, nothing lit
        line.litNotes = 0b0000_0010   // explicit: rank 2 lit
        line.riffOn = false           // explicit: riff off
        XCTAssertEqual(line.litNotesResolved, 0b0000_0010, "the explicit field wins outright over a disagreeing legacy useRiff")
        XCTAssertFalse(line.riffOnResolved)
    }
    // RIFF/NOTES SPLIT (Paul's third same-day ferry, "split MELODY into RIFF and NOTES tabs") — three new
    // EuclidLine fields: notesOn (the notes layer's own master switch), noteOctShifts (per-rank octave
    // shifts, each -1...1), notesVelOffset (added to VEL for lit notes only, -64...64). Same CR-8 contract
    // as every prior EuclidLine addition — a doc saved before these existed must still decode without
    // throwing, resolving to the ferry's own stated defaults: "per-note shifts load as 0, the notes layer
    // loads as on, the offset loads as 0."
    func testEuclidLineDecodesWithoutRiffNotesSplitKeys() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertTrue(line.notesOnResolved, "nil ⇒ on, the ferry's own stated default")
        XCTAssertEqual(line.noteOctShiftsResolved, Array(repeating: 0, count: 8))
        XCTAssertEqual(line.notesVelOffsetResolved, 0)
    }
    func testEuclidLineRiffNotesSplitFieldsRoundTripThroughCodable() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.notesOn = false
        line.noteOctShifts = [1, -1, 0, 0, 0, 0, 0, 1]
        line.notesVelOffset = -20
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertFalse(back.notesOnResolved)
        XCTAssertEqual(back.noteOctShiftsResolved, [1, -1, 0, 0, 0, 0, 0, 1])
        XCTAssertEqual(back.notesVelOffsetResolved, -20)
    }
    // CLAMP/PAD, mirroring the standing per-field convention (riffOctave's own clamp test, directly above
    // this section) — each new field clamps independently of the others.
    func testEuclidLineNoteOctShiftsClampsEachEntryAndPadsShortArrays() {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.noteOctShifts = [5, -5, 0]   // short (3, not 8) AND out-of-range entries
        let r = line.noteOctShiftsResolved
        XCTAssertEqual(r.count, 8, "pads a short array to exactly 8")
        XCTAssertEqual(r[0], 1, "clamps -1...1")
        XCTAssertEqual(r[1], -1)
        XCTAssertEqual(r[2], 0)
        XCTAssertEqual(r[3], 0, "the padded tail defaults to 0")
        line.noteOctShifts = Array(repeating: 1, count: 12)   // over-long (12, not 8)
        XCTAssertEqual(line.noteOctShiftsResolved.count, 8, "truncates an over-long array to exactly 8")
    }
    func testEuclidLineNotesVelOffsetClampsToPlusMinus64() {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.notesVelOffset = 200
        XCTAssertEqual(line.notesVelOffsetResolved, 64)
        line.notesVelOffset = -200
        XCTAssertEqual(line.notesVelOffsetResolved, -64)
    }
    // EUCLIDEOUS-SCOPED DRUNK/RANDOM→FWD (Paul 2026-10-13 ferry, Presets rule 1: "the stored direction
    // carries over. DRUNK becomes FWD") — scoped to Euclideous's own reader; the SHARED `riffDirResolved`
    // (used by the unrelated generic chain RIFF processor) must stay fully untouched.
    func testEuclideousRiffDirResolvedCoercesDrunkAndRandomToForward() {
        var drunk = EuclidLine(pulses: 3, steps: 8); drunk.riffDir = .drunk
        XCTAssertEqual(drunk.euclideousRiffDirResolved, .forward)
        XCTAssertEqual(drunk.riffDirResolved, .drunk, "the SHARED accessor is untouched — still serves the generic chain RIFF processor's own DRUNK")
        var random = EuclidLine(pulses: 3, steps: 8); random.riffDir = .random
        XCTAssertEqual(random.euclideousRiffDirResolved, .forward)
        var fwd = EuclidLine(pulses: 3, steps: 8); fwd.riffDir = .reverse
        XCTAssertEqual(fwd.euclideousRiffDirResolved, .reverse, "every other direction passes through unchanged")
    }
    // RIFF DIRECTION, PER-LANE (Paul 2026-10-07): moved off the shared EuclideousRiff struct onto EuclidLine
    // itself — "the back/forward, drunk controls should be per lane, not on the riff control."
    func testEuclidLineRiffDirDefaultsForwardAndBiasClamps() {
        let fresh = EuclidLine(pulses: 3, steps: 8)
        XCTAssertEqual(fresh.riffDirResolved, .forward, "nil ⇒ forward, byte-identical for every existing doc")
        XCTAssertEqual(fresh.riffDirSeedResolved, 0)
        XCTAssertEqual(fresh.riffDirBiasResolved, 0)
        var line = fresh
        line.riffDirBias = 5
        XCTAssertEqual(line.riffDirBiasResolved, 1, "clamps to -1...1")
        line.riffDirBias = -5
        XCTAssertEqual(line.riffDirBiasResolved, -1)
    }
    func testEuclidLineRiffDirRoundTripsThroughCodable() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.riffDir = .drunk
        line.riffDirSeed = 7
        line.riffDirBias = 0.5
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertEqual(back.riffDirResolved, .drunk)
        XCTAssertEqual(back.riffDirSeedResolved, 7)
        XCTAssertEqual(back.riffDirBiasResolved, 0.5)
    }

    // MELODY POP-UP (Paul 2026-10-10 ferry): riffStride/riffLength/riffAdvanceStep/melodyTranspose are the
    // newest four EuclidLine fields — same CR-8 contract as every field above, a doc saved before they
    // existed must still decode without throwing.
    func testEuclidLineDecodesWithoutMelodyPopupKeys() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertEqual(line.riffStrideResolved, 1, "nil ⇒ 1, byte-identical for every existing doc")
        XCTAssertEqual(line.riffLengthResolved, 8, "nil ⇒ 8")
        XCTAssertFalse(line.riffAdvanceStepResolved, "nil ⇒ HIT")
        XCTAssertEqual(line.melodyTransposeResolved, 0)
    }
    func testEuclidLineMelodyPopupFieldsRoundTripThroughCodable() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.riffStride = 4
        line.riffLength = 5
        line.riffAdvanceStep = true
        line.melodyTranspose = -3
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertEqual(back.riffStrideResolved, 4)
        XCTAssertEqual(back.riffLengthResolved, 5)
        XCTAssertTrue(back.riffAdvanceStepResolved)
        XCTAssertEqual(back.melodyTransposeResolved, -3)
    }
    func testEuclidLineMelodyPopupFieldsClampToTheirRanges() {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.riffStride = 99; XCTAssertEqual(line.riffStrideResolved, 7, "clamps to 1...7")
        line.riffStride = -5; XCTAssertEqual(line.riffStrideResolved, 1)
        line.riffLength = 99; XCTAssertEqual(line.riffLengthResolved, 8, "clamps to 1...8")
        line.riffLength = -5; XCTAssertEqual(line.riffLengthResolved, 1)
        line.melodyTranspose = 99; XCTAssertEqual(line.melodyTransposeResolved, 7, "clamps to -7...7")
        line.melodyTranspose = -99; XCTAssertEqual(line.melodyTransposeResolved, -7)
    }
    // SOURCE DEFAULT FLIP (Paul 2026-10-10 ferry §2.2): "the default SOURCE for a new instance is KEY" —
    // reverses the 2026-10-08 MIDI default (CLAUDE.md's own history records that original choice as
    // deliberate, to avoid silencing an already-shipped feature at the time — this flip is a fresh,
    // explicit instruction, not an accidental reversion of it).
    func testEuclidLineSourceModeDefaultsToKey() {
        let fresh = EuclidLine(pulses: 3, steps: 8)
        XCTAssertEqual(fresh.sourceModeResolved, .key, "nil ⇒ KEY, per the melody pop-up ferry's own §2.2")
    }

    // SEQUENCER PANEL (2026-10-14 ferry §3/§9): per-lane RESET replaces the old machine-wide
    // `euclideousResetSpanBars` bars-count. `euclideousLinesResolved` migrates a PRE-EXISTING document's
    // lanes (one per entry in the table below — the ferry's own literal "0=OFF·1·2·4·8·16→8" mapping) but
    // NEVER a genuinely fresh one, which gets the plain "new pages: 1 step" default regardless of whatever
    // stale `euclideousResetSpanBars` happens to be sitting unread on the document.
    func testEuclideousLinesResolvedMigratesResetStepsFromLegacyBarsCount() {
        for (bars, expected) in [(0, 0), (1, 1), (2, 2), (4, 4), (8, 8), (16, 8)] {
            var st = doc()
            st.euclideousLines = [EuclidLine(noteSel: .all), EuclidLine(noteSel: .all),
                                   EuclidLine(noteSel: .all), EuclidLine(noteSel: .all)]
            st.euclideousResetSpanBars = bars
            let lines = st.euclideousLinesResolved
            XCTAssertEqual(lines.count, 4)
            for (i, l) in lines.enumerated() {
                XCTAssertEqual(l.resetStepsResolved, expected, "bars=\(bars) lane \(i) should migrate to resetSteps=\(expected)")
            }
        }
    }
    // LANES GRID (2026-10-18, §1.3 / §9.1): the fresh-document default is now NO restarts (it was "every 1 step"); a stale legacy bars-count is still ignored.
    func testEuclideousLinesResolvedFreshDocumentDefaultsToNoRestartsIgnoringLegacyBars() {
        var st = doc()
        st.euclideousResetSpanBars = 8   // must be IGNORED — euclideousLines is nil (genuinely fresh), not migrated
        for l in st.euclideousLinesResolved {
            XCTAssertEqual(l.resetStepsResolved, 0, "a genuinely fresh document's lanes carry no restart, never consulting a legacy bars-count that was never actually authored")
        }
    }

    // §7 test 8 (2026-10-15 ferry, "per-step restart points"): `restartMask`'s own fallback
    // (`euclideousStampMask(resetStepsResolved)`) rides ENTIRELY on `resetStepsResolved`'s own ALREADY-
    // migrated value — a pre-feature document (old `resetSteps`/legacy-bars, never touched `restartMask`)
    // must resolve to the exact stamp of whatever `resetStepsResolved` would have been, including the
    // document-level "fresh page ⇒ 1 step" migration from the two tests just above, with NO separate
    // migration path of its own to drift out of sync.
    func testEuclideousRestartMaskResolvedFallsBackToStampOfTheAlreadyMigratedResetSteps() {
        for (bars, expectedSteps) in [(0, 0), (1, 1), (2, 2), (4, 4), (8, 8), (16, 8)] {
            var st = doc()
            st.euclideousLines = [EuclidLine(noteSel: .all), EuclidLine(noteSel: .all),
                                   EuclidLine(noteSel: .all), EuclidLine(noteSel: .all)]
            st.euclideousResetSpanBars = bars
            for l in st.euclideousLinesResolved {
                XCTAssertEqual(l.restartMaskResolved, euclideousStampMask(expectedSteps), "bars=\(bars)")
            }
        }
        // Fresh document: no euclideousLines at all → no restart (LANES GRID, 2026-10-18) → stamp(0) = no bit set.
        var fresh = doc()
        fresh.euclideousResetSpanBars = 8   // must still be ignored, exactly like the resetSteps-only test above
        for l in fresh.euclideousLinesResolved {
            XCTAssertEqual(l.restartMaskResolved, 0)
        }
    }
    // A pre-feature line (only the old `resetSteps` key, `restartMask` never written) decodes without
    // throwing and resolves to the stamp of that old value — no factory reset.
    func testEuclidLineDecodesWithoutRestartMaskKeyAndResolvesToStampOfOldResetSteps() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"resetSteps":2}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertNil(line.restartMask)
        XCTAssertEqual(line.restartMaskResolved, euclideousStampMask(2))
    }
    // A hand-placed custom mask (not one of the four clean stamps) round-trips byte-identically through
    // encode/decode — §1.4's "every write... writes the mask... stop writing the old field but keep it
    // decodable."
    func testEuclidLineRestartMaskRoundTripsThroughCodable() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.restartMask = 0b10010001   // steps 1, 5, 8 — not any clean "every N" stamp
        let data = try JSONEncoder().encode(line)
        let back = try JSONDecoder().decode(EuclidLine.self, from: data)
        XCTAssertEqual(back.restartMask, 0b10010001)
        XCTAssertEqual(back.restartMaskResolved, 0b10010001)
    }
    // FOUR RIFFS (ferry §7/§9): `riffs == nil` migrates the old singular `euclideousRiff` into slot 0;
    // slots 1-3 start EMPTY — a deliberate, disclosed deviation from the ScalePool/chordSeqs precedent
    // (whose own slots 1-3 default to a fresh REAL value), named explicitly in this test's own title.
    func testRiffsResolvedMigratesSingularRiffIntoSlotZeroOthersEmpty() {
        var st = doc()
        st.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        let riffs = st.riffsResolved
        XCTAssertEqual(riffs.count, 4)
        XCTAssertEqual(riffs[0].ranksResolved, st.euclideousRiffResolved.ranksResolved, "slot 0 migrates the old singular riff exactly")
        for i in 1...3 {
            XCTAssertTrue(riffs[i].ranksResolved.allSatisfy { $0 == 0 }, "slot \(i) must start empty (all rest), not a fresh real default like ScalePool's own precedent")
        }
    }
    func testActiveRiffResolvedClampsToZeroThreeAndDefaultsToZero() {
        var st = doc()
        XCTAssertEqual(st.activeRiffResolved, 0, "nil ⇒ riff 0, the only riff a migrated/fresh document actually has content in")
        st.activeRiff = 9
        XCTAssertEqual(st.activeRiffResolved, 3, "clamps to the real 0...3 range")
        st.activeRiff = -4
        XCTAssertEqual(st.activeRiffResolved, 0)
    }
    // LOOPER TABS (FERRY "looper tabs replace the riff tabs", ratified 2026-10-16, §8.1/§8.4) — migration
    // mirrors `testRiffsResolvedMigratesSingularRiffIntoSlotZeroOthersEmpty` above exactly: no data
    // rewrite, `riffs`/`activeRiff` stay decodable and drive the derived ONE riff on every read.
    func testLiveGridMigratedFromRiffsActiveRiff() {
        var st = doc()
        st.euclideousRiff = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])   // migrates into riff slot 0 first, same as the riffs-migration test above
        XCTAssertEqual(st.euclideousLiveGridResolved.ranksResolved, [1, 2, 3, 4, 5, 6, 7, 8], "live grid = riffs[activeRiffResolved] (0, the migrated singular riff)")
        st.activeRiff = 2   // riffs[2] is empty (all-rest) per the riffs-migration default
        XCTAssertTrue(st.euclideousLiveGridResolved.ranksResolved.allSatisfy { $0 == 0 })
    }
    func testLiveGridExplicitFieldOverridesMigrationOnceSet() {
        var st = doc()
        st.euclideousLiveGrid = EuclideousRiff(steps: 8, ranks: [8, 7, 6, 5, 4, 3, 2, 1])
        XCTAssertEqual(st.euclideousLiveGridResolved.ranksResolved, [8, 7, 6, 5, 4, 3, 2, 1])
    }
    // CODABLE ROUND-TRIP (§9 test 11) — a pre-ferry document (no `euclideousLiveGrid` key at all) decodes
    // with NO factory reset, matching every other additive-Optional field's own decode-tolerance
    // convention. The looper's own fields are NEVER written to `PluginState` at all (§8.5) — nothing to
    // round-trip there by construction, confirmed by there being no such field to even attempt setting.
    func testLiveGridFieldRoundTripsThroughCodable() throws {
        var st = doc()
        st.euclideousLiveGrid = EuclideousRiff(steps: 8, ranks: [1, 2, 3, 4, 5, 6, 7, 8])
        let data = try JSONEncoder().encode(st)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.euclideousLiveGrid?.ranksResolved, [1, 2, 3, 4, 5, 6, 7, 8])
    }
    func testPreFerryDocumentWithoutLiveGridKeyDecodesThroughMigrationNoFactoryReset() throws {
        // A literal pre-ferry JSON snippet (the shape `PluginState`'s own decode-tolerant pattern expects):
        // no `euclideousLiveGrid` key at all, only the old singular riff. Decoding must not throw and must
        // migrate on first read, same as a real old session.
        var st = doc()
        st.euclideousRiff = EuclideousRiff(steps: 8, ranks: [2, 2, 2, 2, 2, 2, 2, 2])
        let data = try JSONEncoder().encode(st)   // this document never had the new field set, so it encodes as absent/null, exactly like a genuinely old file
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertNil(back.euclideousLiveGrid)
        XCTAssertEqual(back.euclideousLiveGridResolved.ranksResolved, [2, 2, 2, 2, 2, 2, 2, 2], "migrates on read — no factory reset")
    }
    // LANES/RIFFS SEQUENCERS (ferry §4/§9) — both default OFF, 1 BAR, LEN 8, with cells defaulting to
    // "everything lit"/"everything plays riff 0" so a never-touched document is byte-identical to the
    // feature not existing at all.
    func testEuclideousLanesAndRiffsSeqDefaultOffWithAllCellsOpen() {
        let st = doc()
        XCTAssertFalse(st.euclideousLanesSeqOnResolved)
        XCTAssertEqual(st.euclideousLanesSeqRateResolved, .oneBar)
        XCTAssertEqual(st.euclideousLanesSeqLenResolved, 8)
        XCTAssertTrue(st.euclideousLanesSeqCellsResolved.allSatisfy { $0 }, "nil ⇒ every lane lit at every step")
        XCTAssertFalse(st.euclideousRiffsSeqOnResolved)
        XCTAssertEqual(st.euclideousRiffsSeqLenResolved, 8)
        XCTAssertTrue(st.euclideousRiffsSeqCellsResolved.allSatisfy { $0 == 0 }, "nil ⇒ every step plays riff 0")
    }
    func testEuclideousLanesSeqCellsResolvedIgnoresAMalformedStoredArray() {
        var st = doc()
        st.euclideousLanesSeqCells = [true, false]   // wrong length (not 32) — must fall back to the all-lit default, not crash
        XCTAssertEqual(st.euclideousLanesSeqCellsResolved.count, 32)
        XCTAssertTrue(st.euclideousLanesSeqCellsResolved.allSatisfy { $0 })
    }
    func testEuclideousRiffsSeqCellsResolvedClampsEachEntryToZeroThree() {
        var st = doc()
        st.euclideousRiffsSeqCells = [0, 1, 2, 3, 9, -5, 0, 1]
        XCTAssertEqual(st.euclideousRiffsSeqCellsResolved, [0, 1, 2, 3, 3, 0, 0, 1])
    }

    // EUCLIDEOUS: PluginState's own persisted config — a doc saved before this feature existed must decode with
    // the page simply absent/disabled, never throw (the same CR-8 contract every other PluginState field follows).
    func testEuclideousFieldsDecodeAbsentAndResolveToTheirDefaults() throws {
        let legacy = doc()   // no euclideousLines/Enabled/Receiver keys at all — PluginState's synthesized Decodable
        let data = try JSONEncoder().encode(legacy)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertTrue(back.euclideousEnabledResolved, "Fourfold header ferry §1: the page always runs — an absent field is no longer 'off'")
        XCTAssertEqual(back.euclideousReceiverResolved, 0)
        XCTAssertEqual(back.euclideousLinesResolved.count, 4, "always pads to exactly 4, mirroring euclidLinesForEditing()")
        // PER-INDEX DEFAULT, REVISED (usability ferry §8.2, 2026-10-11, literal): "riff R1; lane 1: riff
        // FWD, 3/8, rate 1/8; lane 2: riff FWD, 5/16, rate 1/16, OCT +1; lanes 3-4: 0 hits. All outputs A,
        // source KEY." SUPERSEDES the prior ferry's own "lane 1 = 1 of 8, lanes 2-4 = 0 hits" default
        // entirely (that older default is now itself historical — see the 2026-10-09 entry this comment
        // used to cite).
        let lines = back.euclideousLinesResolved
        XCTAssertEqual(lines[0].pulses, 3); XCTAssertEqual(lines[0].steps, 8); XCTAssertEqual(lines[0].rate, .r1_8)
        XCTAssertEqual(lines[1].pulses, 5); XCTAssertEqual(lines[1].steps, 16); XCTAssertEqual(lines[1].rate, .r1_16)
        XCTAssertEqual(lines[1].riffOctaveResolved, 1)
        XCTAssertTrue(lines[2...3].allSatisfy { $0.pulses == 0 }, "lanes 3-4 open deliberately silent (0 hits)")
        XCTAssertTrue(lines.allSatisfy { $0.emitterMask == 0b0001 }, "every lane defaults to output A")
        XCTAssertTrue(lines.allSatisfy { $0.sourceModeResolved == .key }, "every lane defaults to source KEY")
        // MELODY POP-UP (Paul 2026-10-10 ferry §2): NOTE defaults to LOWEST, MODE defaults to RIFF — found
        // on a plan self-re-audit that `euclideousDefaultLine`, not EuclidLine's own shared accessor
        // fallback, is where these fresh-lane defaults actually live; this is the correctly-scoped place
        // to lock them in (MODE was ALREADY correct before this ferry — this also guards it stays that way).
        XCTAssertTrue(lines.allSatisfy { $0.noteSelResolved == .low }, "every fresh lane defaults NOTE to LOWEST")
        XCTAssertTrue(lines.allSatisfy { $0.useRiffResolved }, "every fresh lane defaults MODE to RIFF")
        XCTAssertTrue(lines.allSatisfy { $0.riffDirResolved == .forward }, "every fresh lane's riff walk defaults FWD")
    }
    func testEuclideousLinesResolvedPadsAndTruncates() {
        var d = doc()
        d.euclideousLines = [EuclidLine(pulses: 4, steps: 8)]   // only 1 of 4 authored
        XCTAssertEqual(d.euclideousLinesResolved.count, 4)
        XCTAssertEqual(d.euclideousLinesResolved[0].pulses, 4)
        XCTAssertEqual(d.euclideousLinesResolved[1].pulses, 5, "a padded-in lane 2 takes ITS OWN per-index default (usability ferry §8.2: 5/16), not lane 1's own authored value or a blanket silent fallback")
        d.euclideousLines = Array(repeating: EuclidLine(pulses: 2, steps: 8), count: 6)   // over-long
        XCTAssertEqual(d.euclideousLinesResolved.count, 4)
    }

    // ONE GLOBAL RIFF/NOTE SOURCE (Paul 2026-10-12, 2nd same-day ferry) — `euclideousNoteSourceResolved`'s
    // migration from the 4 now-decode-only per-lane values. "Take lane 1's... if the lanes disagree, still
    // take lane 1" (the ferry's own literal rule), implemented as "lane 1" = index 0 of
    // `euclideousLinesResolved`, which already pads/defaults every lane to a concrete value — so "4
    // per-lane values" always exist to compare, even for a document with no real per-lane data at all.
    func testEuclideousNoteSourceResolvedMigratesFromLegacyPerLaneValues() {
        // (1) No explicit new field, no legacy per-lane data at all: every lane resolves to its own
        // fresh-lane default (.key, per the melody pop-up ferry) — all 4 agree, so the migration is a
        // trivial, warning-free `.key`.
        let untouched = doc()
        XCTAssertEqual(untouched.euclideousNoteSourceResolved, .key, "no legacy data at all ⇒ the shared fresh-lane default, KEY")

        // (2) Legacy per-lane data present, all 4 agreeing: migrates to that shared value cleanly.
        var uniform = doc()
        uniform.euclideousLines = Array(repeating: EuclidLine(sourceMode: .midi), count: 4)
        XCTAssertEqual(uniform.euclideousNoteSourceResolved, .midi, "4 agreeing legacy lanes migrate to their shared value")

        // (3) Legacy per-lane data DISAGREEING: still takes lane 1's (index 0's) value, per the ferry's own
        // literal rule — not an average, not the majority, not any other lane's.
        var disagreeing = doc()
        disagreeing.euclideousLines = [
            EuclidLine(sourceMode: .chords),
            EuclidLine(sourceMode: .midi),
            EuclidLine(sourceMode: .key),
            EuclidLine(sourceMode: .midi),
        ]
        XCTAssertEqual(disagreeing.euclideousNoteSourceResolved, .chords, "disagreeing lanes must still take lane 1's value, not the majority (MIDI) or any other lane's")

        // (4) The explicit new field, once set, always wins over whatever the legacy lanes carry — even
        // when they'd migrate to something else entirely.
        var explicit = disagreeing
        explicit.euclideousNoteSource = .key
        XCTAssertEqual(explicit.euclideousNoteSourceResolved, .key, "an explicit euclideousNoteSource must win outright, ignoring the legacy per-lane data entirely")
    }

    // RIFF ADVANCE (Paul 2026-10-06): the page's ONE shared riff pattern — same additive-Optional CR-8 contract,
    // a doc saved before this feature existed decodes to the struct's own plain defaults, never throws.
    func testEuclideousRiffResolvedDefaultsAbsent() throws {
        let legacy = doc()   // no euclideousRiff key at all
        let data = try JSONEncoder().encode(legacy)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.euclideousRiffResolved.stepsResolved, 16)
        XCTAssertEqual(back.euclideousRiffResolved.ranksResolved.count, 16)
    }
    func testEuclideousRiffResolvedClampsStepsAndPadsRanks() {
        var d = doc()
        d.euclideousRiff = EuclideousRiff(steps: 40, ranks: [1, 2, 3])   // over-range steps, short ranks
        let r = d.euclideousRiffResolved
        XCTAssertEqual(r.stepsResolved, 32, "clamps to the 1...32 range")
        XCTAssertEqual(r.ranksResolved.count, 32, "pads the short ranks array out to the resolved step count")
        XCTAssertEqual(Array(r.ranksResolved.prefix(3)), [1, 2, 3], "existing authored ranks are preserved, not overwritten")
        var d2 = doc()
        d2.euclideousRiff = EuclideousRiff(steps: 4, ranks: [1, 2, 3, 4, 5, 6, 7, 8])   // over-long ranks, truncate to steps
        XCTAssertEqual(d2.euclideousRiffResolved.ranksResolved, [1, 2, 3, 4])
    }

    /// The builder mirrors the 16 macro values into the snapshot (clamped 0…1); a clean doc yields 16 zeros.
    func testBuilderMirrorsMacroValuesClamped() {
        var doc = self.doc()
        let clean = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(clean.macroValues.count, 16)
        XCTAssertTrue(clean.macroValues.allSatisfy { $0 == 0 })

        doc.macros = doc.macrosResolved
        doc.macros?[0].value = 0.75
        doc.macros?[1].value = 2.0                                 // out of range → clamps to 1
        doc.macros?[2].value = -1.0                                // → clamps to 0
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.macroValues[0], 0.75, accuracy: 1e-9)
        XCTAssertEqual(box.macroValues[1], 1.0, accuracy: 1e-9)
        XCTAssertEqual(box.macroValues[2], 0.0, accuracy: 1e-9)
    }

    // MARK: M1 — the offset math (applyMacros)

    /// effective = base + value × delta, and the base bag is returned UNMUTATED (a copy) — identity stays put.
    func testApplyMacrosOffsetsAndLeavesBaseUntouched() {
        var base = SnapParams(); base.gate = 0.5
        let mods = [MacroMod(macro: 0, param: .gate, delta: 0.4)]
        let out = applyMacros(base, mods: mods, values: [0.5])
        XCTAssertEqual(out.gate, 0.7, accuracy: 1e-9)          // 0.5 + 0.5×0.4
        XCTAssertEqual(base.gate, 0.5, accuracy: 1e-9)         // the base is never rewritten
    }

    /// A macro at 0 is HOME — no offset, byte-for-byte the base (nothing to revert).
    func testMacroAtZeroIsHome() {
        var base = SnapParams(); base.gate = 0.5; base.spread = 0.3
        let out = applyMacros(base, mods: [MacroMod(macro: 0, param: .gate, delta: 0.4),
                                           MacroMod(macro: 0, param: .spread, delta: -0.2)], values: [0.0])
        XCTAssertEqual(out.gate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(out.spread, 0.3, accuracy: 1e-9)
    }

    /// Two macros on the SAME param SUM, then clamp ONCE (the offset law) — not sequential per-macro clamping.
    func testOverlappingOffsetsSumThenClamp() {
        var base = SnapParams(); base.probability = 0.6
        // 0.6 + 1.0×0.5 + 1.0×0.5 = 1.6 → clamps to 1 (sum first). Sequential clamping would also hit 1 here,
        // so use a case where order matters: +0.6 then −0.5 = net +0.1 → 0.7 (sequential-with-clamp: 0.6+0.6=1.2→1, then 1−0.5=0.5 ≠ 0.7).
        let out = applyMacros(base, mods: [MacroMod(macro: 0, param: .probability, delta: 0.6),
                                           MacroMod(macro: 1, param: .probability, delta: -0.5)], values: [1.0, 1.0])
        XCTAssertEqual(out.probability, 0.7, accuracy: 1e-9)   // sum (+0.1) then clamp — proves it's not clamped per-mod
    }

    /// Each param clamps to its resolve() range: probability/ramp/spread → [0,1]; curve/velTilt → [−1,1];
    /// gate → [0.05,1]; harmVelScale → [0.1,1].
    func testOffsetsClampToLegalRanges() {
        var base = SnapParams(); base.curve = 0.8; base.gate = 0.9; base.harmVelScale = 0.9
        let out = applyMacros(base, mods: [MacroMod(macro: 0, param: .curve, delta: 0.9),        // 0.8+0.9=1.7 → 1
                                           MacroMod(macro: 0, param: .gate, delta: 0.5),          // 0.9+0.5=1.4 → 1
                                           MacroMod(macro: 0, param: .harmVelScale, delta: -2)],  // 0.9−2=−1.1 → 0.1
                              values: [1.0])
        XCTAssertEqual(out.curve, 1.0, accuracy: 1e-9)
        XCTAssertEqual(out.gate, 1.0, accuracy: 1e-9)
        XCTAssertEqual(out.harmVelScale, 0.1, accuracy: 1e-9)
    }

    // MARK: M1 — end to end through the builder

    /// A macro bound to a cell's chain-slot param shifts the RESOLVED param, while the document cell (and its seal)
    /// are untouched — the whole point of the offset model (performance, not identity).
    func testBuilderFoldsMacroOffsetIntoResolvedChainButNotTheDocument() {
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold")
        var slot = ProcessorSlot(type: .arp); slot.params.gate = 0.5
        cell.processors = [slot]
        s.cells[0][0] = cell
        var doc = PluginState(machines: [Machine(machineID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(name: "GATE", value: 0.5, fixed: false,
                               targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.4)])

        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.cells[0].procs[0].gate, 0.7, accuracy: 1e-9)   // 0.5 + 0.5×0.4, folded at build

        // The base is untouched: the DOCUMENT slot param is still 0.5, and the seal (document-derived) is stable.
        XCTAssertEqual(doc.scenes[0].cells[0][0]?.processors?[0].params.gate, 0.5)
        let sealWith = sealHash(cell, machines: doc.machines)
        var docNoMacro = doc; docNoMacro.macros = nil
        XCTAssertEqual(sealHash(cell, machines: docNoMacro.machines), sealWith)   // macro presence never moves the seal
    }

    /// M2 — the PER-CELL value store (§A2 PUNCH/SPAN): ONE macro targets TWO cells with the same delta; a per-cell
    /// override raises the DRIVING value on cell (0,0) only, so its param shifts while the neighbour (1,0) stays at
    /// base (the global value 0). This is the load-bearing engine bit — a PUNCH-drawn cell is independent.
    func testPerCellMacroValueShiftsOneCellNotItsNeighbour() {
        var s = SceneState.empty()
        func gateCell() -> Cell { var c = Cell(machineID: "gold"); var sl = ProcessorSlot(type: .arp); sl.params.gate = 0.5; c.processors = [sl]; return c }
        s.cells[0][0] = gateCell()
        s.cells[1][0] = gateCell()
        var doc = PluginState(machines: [Machine(machineID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(name: "GATE", value: 0, fixed: false,   // GLOBAL value 0 → no shift anywhere by default
                               targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.4),
                                         MacroTarget(col: 1, row: 0, slot: 0, param: "gate", delta: 0.4)])
        // No overrides yet → both cells sit at base (global 0 × 0.4 = 0).
        let base = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(base.cells[0 * Snap.rows + 0].procs[0].gate, 0.5, accuracy: 1e-9, "no override → base")
        XCTAssertEqual(base.cells[1 * Snap.rows + 0].procs[0].gate, 0.5, accuracy: 1e-9, "neighbour → base")

        // PUNCH cell (0,0) to full value → its gate shifts by the full delta; (1,0) untouched.
        doc.macroCellValues = [MacroCellValue(col: 0, row: 0, macro: 0, value: 1.0)]
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.cells[0 * Snap.rows + 0].procs[0].gate, 0.9, accuracy: 1e-9, "(0,0) drives at value 1 → 0.5 + 1×0.4")
        XCTAssertEqual(box.cells[1 * Snap.rows + 0].procs[0].gate, 0.5, accuracy: 1e-9, "(1,0) has NO override → stays at the global (0) → base")
    }

    /// M2 byte-identity: an empty per-cell store changes nothing (the whole macroCellValues path is inert when unused).
    func testEmptyPerCellStoreIsByteIdentical() {
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold"); var slot = ProcessorSlot(type: .arp); slot.params.gate = 0.5; cell.processors = [slot]
        s.cells[0][0] = cell
        var doc = PluginState(machines: [Machine(machineID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(name: "G", value: 0.5, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.4)])
        let a = SnapshotBuilder.build(from: doc)
        doc.macroCellValues = []                             // present but empty
        let b = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(a.cells[0].procs[0].gate, b.cells[0].procs[0].gate, "an empty override store is a no-op (0.5 + 0.5×0.4 = 0.7 both ways)")
        XCTAssertEqual(b.cells[0].procs[0].gate, 0.7, accuracy: 1e-9)
    }

    /// M2 — the per-cell store travels with the document (Codable, additive-Optional); an old doc decodes nil.
    func testPerCellMacroValuesRoundTripAndOldDocDecodesNil() throws {
        var doc = self.doc()
        doc.macroCellValues = [MacroCellValue(col: 2, row: 3, macro: 5, value: 0.6),
                               MacroCellValue(col: 0, row: 0, macro: 12, value: 1.0)]
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.macroCellValues?.count, 2)
        XCTAssertEqual(back.macroCellValues?.first, MacroCellValue(col: 2, row: 3, macro: 5, value: 0.6))

        var obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        obj.removeValue(forKey: "macroCellValues")
        let old = try JSONDecoder().decode(PluginState.self, from: try JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(old.macroCellValues, "an old doc with no key decodes nil (byte-identical)")
    }

    /// Macro at 0 through the builder is home — the resolved chain equals the un-macro'd build.
    func testBuilderMacroAtZeroMatchesNoMacro() {
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold")
        var slot = ProcessorSlot(type: .arp); slot.params.gate = 0.5
        cell.processors = [slot]
        s.cells[0][0] = cell
        var doc = PluginState(machines: [Machine(machineID: "gold", type: .arp)], scenes: [s])
        let plain = SnapshotBuilder.build(from: doc).cells[0].procs[0].gate

        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(value: 0.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.4)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, plain, accuracy: 1e-9)
    }

    /// M4 A/B semantic: a binding stores delta = B − A; the macro at 1 reconstructs B, at 0 returns to A. The base
    /// (A) is what the document holds — authoring never rewrites it (this is the offset model's contract end-to-end).
    func testABBindingReconstructsBAtOneAndAAtZero() {
        let A = 0.3, B = 0.9
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold")
        var slot = ProcessorSlot(type: .arp); slot.params.gate = A     // the A state lives in the document
        cell.processors = [slot]
        s.cells[0][0] = cell
        var doc = PluginState(machines: [Machine(machineID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        doc.macros?[0].targets = [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: B - A)]   // the authored delta

        doc.macros?[0].value = 1.0
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, B, accuracy: 1e-9)     // full = B
        doc.macros?[0].value = 0.0
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, A, accuracy: 1e-9)     // home = A
        doc.macros?[0].value = 0.5
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, 0.6, accuracy: 1e-9)   // halfway
    }

    // MARK: M1 — builder fold edge cases (guards + summing + multi-cell)

    /// A gold ARP chain cell at (col,row) with the given head gate, ready for macro targeting.
    private func chainCellDoc(gate: Double, at pos: (Int, Int) = (0, 0)) -> PluginState {
        var s = SceneState.empty()
        var cell = Cell(machineID: "gold")
        var slot = ProcessorSlot(type: .arp); slot.params.gate = gate
        cell.processors = [slot]
        s.cells[pos.0][pos.1] = cell
        var doc = PluginState(machines: [Machine(machineID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        return doc
    }

    /// An out-of-range macro index in the values array contributes no offset (no crash, treated as 0).
    func testApplyMacrosIgnoresOutOfRangeMacroIndex() {
        var base = SnapParams(); base.gate = 0.5
        let out = applyMacros(base, mods: [MacroMod(macro: 99, param: .gate, delta: 0.4),
                                           MacroMod(macro: -1, param: .gate, delta: 0.4)], values: [1.0])
        XCTAssertEqual(out.gate, 0.5, accuracy: 1e-9)
    }

    /// The builder SKIPS a target with an unknown param string (forward-compat) — no crash, no change.
    func testBuilderSkipsUnknownParamString() {
        var doc = chainCellDoc(gate: 0.5)
        doc.macros?[0] = Macro(value: 1.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "bogus", delta: 0.4)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, 0.5, accuracy: 1e-9)
    }

    /// The builder SKIPS out-of-bounds cell/slot targets (a stale binding after a resize) — no crash, no change.
    func testBuilderSkipsOutOfBoundsTarget() {
        var doc = chainCellDoc(gate: 0.5)
        doc.macros?[0] = Macro(value: 1.0, targets: [
            MacroTarget(col: 99, row: 0, slot: 0, param: "gate", delta: 0.4),   // col out of range
            MacroTarget(col: 0, row: 0, slot: 7, param: "gate", delta: 0.4),    // slot past the 1-slot chain
        ])
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.cells[0].procs[0].gate, 0.5, accuracy: 1e-9)          // unchanged; no trap
    }

    /// Two macros bound to the SAME (cell,slot,param) SUM through the full build, then clamp once.
    func testBuilderTwoMacrosOnSameParamSumEndToEnd() {
        var doc = chainCellDoc(gate: 0.4)
        doc.macros?[0] = Macro(value: 1.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.2)])
        doc.macros?[1] = Macro(value: 1.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.3)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, 0.9, accuracy: 1e-9)   // 0.4+0.2+0.3
    }

    /// One macro bound to TWO cells (a twin set) modulates BOTH — the multi-cell write law.
    func testBuilderMacroModulatesEveryTargetedCell() {
        var s = SceneState.empty()
        for pos in [(0, 0), (3, 5)] {
            var cell = Cell(machineID: "gold"); var slot = ProcessorSlot(type: .arp); slot.params.gate = 0.5
            cell.processors = [slot]; s.cells[pos.0][pos.1] = cell
        }
        var doc = PluginState(machines: [Machine(machineID: "gold", type: .arp)], scenes: [s])
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(value: 1.0, targets: [
            MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.3),
            MacroTarget(col: 3, row: 5, slot: 0, param: "gate", delta: 0.3),
        ])
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.cells[0 * Snap.rows + 0].procs[0].gate, 0.8, accuracy: 1e-9)
        XCTAssertEqual(box.cells[3 * Snap.rows + 5].procs[0].gate, 0.8, accuracy: 1e-9)
    }

    /// A BUTTON-bank macro (index ≥ 8) folds identically to a slider — the builder iterates all 24 banks, so a
    /// button snapped to B (value 1) reconstructs B just like M1. Locks that non-slider banks aren't excluded.
    func testButtonBankMacroModulatesLikeSlider() {
        XCTAssertEqual(PluginState.macroKind(8), .button)
        var doc = chainCellDoc(gate: 0.5)
        doc.macros?[8] = Macro(value: 1.0, targets: [MacroTarget(col: 0, row: 0, slot: 0, param: "gate", delta: 0.3)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).cells[0].procs[0].gate, 0.8, accuracy: 1e-9)   // 0.5 + 1×0.3
    }

    // MARK: OUTPUT — macros modulate the per-emitter role amounts (LEAK/DUCK/CURVE/POCKET)

    /// A macro bound to an emitter's DUCK amount shifts the RESOLVED amount; the document base is untouched, and a
    /// macro at 0 is home. The amount lives per-emitter (folded in the builder, not through applyMacros).
    func testOutputMacroModulatesEmitterAmountAndLeavesBaseUntouched() {
        var doc = self.doc()
        doc.flattenAmount = [40, 0, 0, 0]                    // base DUCK 40% on emitter A
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(value: 1.0, emitterTargets: [MacroEmitterTarget(emitter: 0, param: "duck", delta: 50)])
        XCTAssertEqual(SnapshotBuilder.build(from: doc).flattenAmount[0], 90)   // 40 + 1×50
        XCTAssertEqual(doc.flattenAmountResolved[0], 40)                        // document base untouched
        doc.macros?[0].value = 0.0
        XCTAssertEqual(SnapshotBuilder.build(from: doc).flattenAmount[0], 40)   // home = base
    }

    // MARK: TIMELINE — the pure lane evaluator (value = f(column))

    private func flat(_ v: Int) -> [Int] { Array(repeating: v, count: 8) }






    func testMacroLaneResolversAreShortArraySafe() {
        var m = Macro(); m.lane = [0.5]; m.laneModes = [2]
        XCTAssertEqual(m.laneResolved.count, 8)
        XCTAssertEqual(m.laneResolved[0], 0.5); XCTAssertEqual(m.laneResolved[1], 0.0)
        XCTAssertEqual(m.laneModesResolved[0], 2); XCTAssertEqual(m.laneModesResolved[1], 0)
        XCTAssertEqual(m.laneRateMulResolved, 1.0)                 // default index 3 = ×1
        m.laneRate = 0; XCTAssertEqual(m.laneRateMulResolved, 8.0) // ×8
    }

    /// Each OUTPUT amount clamps to its native range (LEAK/DUCK 0…100 · CURVE −100…100 · POCKET −50…50), summing
    /// overlaps ONCE. A half-value macro scales the delta.
    func testOutputAmountsSumThenClampToRanges() {
        var doc = self.doc()
        doc.flattenAmount = [40, 0, 0, 0]; doc.curveAmount = [0, 0, 0, 0]; doc.pocketMs = [0, 0, 0, 0]
        doc.macros = doc.macrosResolved
        doc.macros?[0] = Macro(value: 1.0, emitterTargets: [
            MacroEmitterTarget(emitter: 0, param: "duck", delta: 80),     // 40 + 80 = 120 (before the 2nd) …
            MacroEmitterTarget(emitter: 0, param: "duck", delta: -30),    // … + −30 = 90 (sum first, not clamp-per-mod)
            MacroEmitterTarget(emitter: 1, param: "curve", delta: 200),   // 0 + 200 → clamp 100
            MacroEmitterTarget(emitter: 2, param: "pocket", delta: -80),  // 0 − 80 → clamp −50
        ])
        doc.macros?[1] = Macro(value: 0.5, emitterTargets: [MacroEmitterTarget(emitter: 3, param: "leak", delta: 40)])  // 0.5×40 = 20
        let box = SnapshotBuilder.build(from: doc)
        XCTAssertEqual(box.flattenAmount[0], 90)      // sum then clamp (proves not clamped per-mod)
        XCTAssertEqual(box.curveAmount[1], 100)       // clamped to +100
        XCTAssertEqual(box.pocketMs[2], -50)          // clamped to −50
        XCTAssertEqual(box.claimLeak[3], 20)          // half-value scales the delta
    }

    // MARK: applyMacros — guard edges (negative index · zero-offset short-circuit)

    /// A NEGATIVE macro index contributes nothing (the guard's lower half) and a zero-value/zero-delta mod leaves
    /// the base bit-identical (the `off == 0` short-circuit — never a needless re-clamp).
    func testApplyMacrosNegativeIndexAndZeroOffsetLeaveBaseUntouched() {
        var base = SnapParams(); base.gate = 0.5; base.spread = 0.3
        let out = applyMacros(base, mods: [
            MacroMod(macro: -1, param: .gate, delta: 0.5),     // negative index → skipped
            MacroMod(macro: 0, param: .spread, delta: 0.0),    // zero delta → off == 0 → skipped
        ], values: [1.0])
        XCTAssertEqual(out.gate, 0.5, accuracy: 1e-9)
        XCTAssertEqual(out.spread, 0.3, accuracy: 1e-9)
    }

    // MARK: Snapshot effective* — the quantize/clamp helpers (render-side, §3.2)

    private func snapMachine(_ mutate: (inout SnapParams) -> Void) -> SnapMachine {
        var sc = SnapMachine(); mutate(&sc.a); return sc
    }

    /// RATCHET repeats quantize to the nearest LEGAL count in [2,3,4,6,8], first-wins on a tie.
    func testEffectiveRepeatsQuantizesToLegalCount() {
        XCTAssertEqual(effectiveRepeats(snapMachine { $0.count = 2 }), 2)
        XCTAssertEqual(effectiveRepeats(snapMachine { $0.count = 5 }), 4, "5 is equidistant 4/6 → first (4) wins")
        XCTAssertEqual(effectiveRepeats(snapMachine { $0.count = 7 }), 6, "7 is equidistant 6/8 → first (6) wins")
        XCTAssertEqual(effectiveRepeats(snapMachine { $0.count = 8 }), 8)
    }

    /// The scalar effective* helpers saturate at their native bounds — no trap, no off-by-one in the voice switch.
    func testEffectiveScalarClamps() {
        XCTAssertEqual(effectiveOctaves(snapMachine { $0.octaves = 9 }), 4, "octaves clamp 1…4")
        XCTAssertEqual(effectiveOctaves(snapMachine { $0.octaves = 0 }), 1)
        // harmIntervals voice select: 0/1 pick .0/.1, any other index picks .2; each clamps ±24.
        let c = snapMachine { $0.harmIntervals = (100, -100, 7) }
        XCTAssertEqual(effectiveHarmInterval(c, voice: 0), 24)
        XCTAssertEqual(effectiveHarmInterval(c, voice: 1), -24)
        XCTAssertEqual(effectiveHarmInterval(c, voice: 2), 7)
        XCTAssertEqual(effectiveHarmInterval(c, voice: 99), 7, "an out-of-range voice falls to the 3rd interval")
        // rateIndex saturates into the arpRateBeats ladder rather than trapping.
        XCTAssertEqual(effectiveRateBeats(snapMachine { $0.rateIndex = 127 }), Snap.arpRateBeats.last!)
        XCTAssertEqual(effectiveRateBeats(snapMachine { $0.rateIndex = -5 }), Snap.arpRateBeats.first!)
    }

    /// The unit-range render-side reads saturate at their floors/ceilings (the render thread's last line of defence
    /// even though `resolve` already clamps on ingest): ramp/spread/probability ∈ [0,1], harmVelScale ∈ [0.1,1].
    func testEffectiveUnitRangeScalarsClamp() {
        XCTAssertEqual(effectiveRamp(snapMachine { $0.ramp = 2 }), 1)
        XCTAssertEqual(effectiveRamp(snapMachine { $0.ramp = -1 }), 0)
        XCTAssertEqual(effectiveSpread(snapMachine { $0.spread = 5 }), 1)
        XCTAssertEqual(effectiveSpread(snapMachine { $0.spread = -0.5 }), 0)
        XCTAssertEqual(effectiveProbability(snapMachine { $0.probability = 3 }.a), 1)
        XCTAssertEqual(effectiveProbability(snapMachine { $0.probability = -2 }.a), 0)
        XCTAssertEqual(effectiveHarmVelScale(snapMachine { $0.harmVelScale = 5 }), 1)
        XCTAssertEqual(effectiveHarmVelScale(snapMachine { $0.harmVelScale = -1 }), 0.1, "the floor is 0.1, not 0")
    }

    // CHANCE PATTERN (Paul 2026-08-22 §5): effectiveProbability(step:) reads the rotated 8-slice odds; step wraps mod 8;
    // a missing slice falls back to pass (100%); SINGLE mode ignores step. (Only the SINGLE clamp path was tested before.)
    func testEffectiveProbabilityPatternReadsTheRotatedSlice() {
        let slices = [100, 0, 70, 0, 100, 0, 70, 0]
        let p = snapMachine { $0.chanceMode = .pattern; $0.chanceSlices = slices; $0.chanceRotate = 0 }.a
        XCTAssertEqual(effectiveProbability(p, step: 0), 1.0, "slice 0 = 100%")
        XCTAssertEqual(effectiveProbability(p, step: 1), 0.0, "slice 1 = 0%")
        XCTAssertEqual(effectiveProbability(p, step: 9), effectiveProbability(p, step: 1), "step wraps mod 8")
        let pr = snapMachine { $0.chanceMode = .pattern; $0.chanceSlices = slices; $0.chanceRotate = 1 }.a
        XCTAssertEqual(effectiveProbability(pr, step: 0), 0.0, "rotate 1 → step 0 reads slice 1")
        let pn = snapMachine { $0.chanceMode = .pattern; $0.chanceSlices = slices; $0.chanceRotate = -1 }.a
        XCTAssertEqual(effectiveProbability(pn, step: 1), 1.0, "negative rotate wraps: step 1 → slice 0 = 100%")
        let ps = snapMachine { $0.chanceMode = .pattern; $0.chanceSlices = [50]; $0.chanceRotate = 0 }.a
        XCTAssertEqual(effectiveProbability(ps, step: 3), 1.0, "a missing slice falls back to pass (100%)")
        let single = snapMachine { $0.probability = 0.5 }.a
        XCTAssertEqual(effectiveProbability(single, step: 5), effectiveProbability(single, step: 0), "SINGLE ignores step")
    }




    // The Macro lane resolvers CLAMP out-of-range decoded values (a corrupt/hand-edited doc): each lane value to
    // [0,1], each mode to [0,2], and the rate INDEX into Macro.laneRateMul. The existing tests only check count/pad.
    func testMacroLaneResolversClampOutOfRangeValuesAndIndex() {
        var m = Macro(value: 0.5, targets: [])
        m.lane = [1.5, -0.2]
        XCTAssertEqual(m.laneResolved[0], 1.0, "> 1 clamps to 1")
        XCTAssertEqual(m.laneResolved[1], 0.0, "< 0 clamps to 0")
        XCTAssertEqual(m.laneResolved.count, 8, "padded to 8")
        m.laneModes = [9]
        XCTAssertEqual(m.laneModesResolved[0], 2, "an out-of-range mode clamps to the max (2)")
        m.laneRate = 99
        XCTAssertEqual(m.laneRateMulResolved, Macro.laneRateMul.last, "a too-high rate index clamps to the last multiplier")
        m.laneRate = -1
        XCTAssertEqual(m.laneRateMulResolved, Macro.laneRateMul.first, "a negative rate index clamps to the first")
    }

    // MARK: - Phase-2 render-time AUTO param plumbing (Paul 2026-09-04)

    /// `AutoParamField(key:)` must recognise EXACTLY the render-time-automatable scalar keys and reject anything else —
    /// a typo in the string table silently makes a param non-automatable at render time (the builder just skips it), with
    /// no crash and no other test failing. This locks the 28-key table.
    func testAutoParamFieldRecognisesEveryAutomatableKey() {
        let keys = ["gate", "ramp", "spread", "curve", "velTilt", "probability", "harmVelScale",
                    "octaves", "count", "rtcChance", "rtcCountLo", "rtcCountHi", "rtcRotate",
                    "euclidPulses", "euclidSteps", "euclidRot", "glideRange", "modMin", "modMax",
                    "lenShort", "lenLong", "lenRotate", "weaveSpan", "weaveEuclidSteps",
                    "maskK", "maskRotate", "maskChordGate", "maskChordOct", "arpVelocity", "arpVelTilt"]
        for k in keys { XCTAssertNotNil(AutoParamField(key: k), "\(k) must be render-time automatable") }
        XCTAssertEqual(keys.count, 30, "the render-time scalar set is 30 fields")
        for bogus in ["", "nope", "euclidPuls", "bypass", "pattern", "harm0", "passMask"] {
            XCTAssertNil(AutoParamField(key: bogus), "\(bogus) is NOT a render-time scalar (nested/enum/typo)")
        }
    }

    /// `SnapParams.settingAuto` must clamp each field to the SAME bounds `applyProcessorValues` uses (its documented
    /// contract). This locks all 28 bounds — a wrong bound would ship silently otherwise. The `readAuto` switch is
    /// exhaustive, so a NEW AutoParamField case forces this table to be extended.
    func testSettingAutoClampsEveryFieldToItsBound() {
        // (field, expected low clamp, expected high clamp) — copied from applyProcessorValues (MacroAuthoring.swift).
        let table: [(AutoParamField, Double, Double)] = [
            (.gate, 0.05, 1), (.ramp, 0, 1), (.spread, 0, 1), (.curve, -1, 1), (.velTilt, -1, 1),
            (.probability, 0, 1), (.harmVelScale, 0.1, 1), (.octaves, 1, 4), (.count, 2, 8),
            (.rtcChance, 0, 1), (.rtcCountLo, 1, 8), (.rtcCountHi, 1, 8), (.rtcRotate, 0, 7),
            (.euclidPulses, 1, 16), (.euclidSteps, 2, 16), (.euclidRot, 0, 15), (.glideRange, 1, 48),
            (.modMin, 0, 127), (.modMax, 0, 127), (.lenShort, 0.05, 0.95), (.lenLong, 0, 1),
            (.lenRotate, 0, 7), (.weaveSpan, 1, 8), (.weaveEuclidSteps, 2, 16),
            (.maskK, 1, 16), (.maskRotate, 0, 15), (.maskChordGate, 0.05, 1), (.maskChordOct, -2, 2),
            (.arpVelocity, 1, 100), (.arpVelTilt, -1, 1)]
        XCTAssertEqual(table.count, 30, "every AutoParamField case is covered")
        for (f, lo, hi) in table {
            XCTAssertEqual(readAuto(SnapParams().settingAuto(f, -9_999), f), lo, accuracy: 1e-9, "\(f) clamps below to \(lo)")
            XCTAssertEqual(readAuto(SnapParams().settingAuto(f, 9_999), f), hi, accuracy: 1e-9, "\(f) clamps above to \(hi)")
        }
    }
    /// Read one automatable field back out of a SnapParams as a Double (for the clamp assertions above).
    private func readAuto(_ s: SnapParams, _ f: AutoParamField) -> Double {
        switch f {
        case .gate: return s.gate;                 case .ramp: return s.ramp;                 case .spread: return s.spread
        case .curve: return s.curve;               case .velTilt: return s.velTilt;           case .probability: return s.probability
        case .harmVelScale: return s.harmVelScale; case .octaves: return Double(s.octaves);   case .count: return Double(s.count)
        case .rtcChance: return s.rtcChance;       case .rtcCountLo: return Double(s.rtcCountLo); case .rtcCountHi: return Double(s.rtcCountHi)
        case .rtcRotate: return Double(s.rtcRotate); case .euclidPulses: return Double(s.euclidPulses); case .euclidSteps: return Double(s.euclidSteps)
        case .euclidRot: return Double(s.euclidRot); case .glideRange: return Double(s.glideRange); case .modMin: return Double(s.modMin)
        case .modMax: return Double(s.modMax);     case .lenShort: return s.lenShort;         case .lenLong: return s.lenLong
        case .lenRotate: return Double(s.lenRotate); case .weaveSpan: return Double(s.weaveSpan); case .weaveEuclidSteps: return Double(s.weaveEuclidSteps)
        case .maskK: return Double(s.maskK); case .maskRotate: return Double(s.maskRotate)
        case .maskChordGate: return s.maskChordGate; case .maskChordOct: return Double(s.maskChordOct)
        case .arpVelocity: return s.arpVelocity; case .arpVelTilt: return s.arpVelTilt
        }
    }

    // FOURFOLD HEADER ferry §1.2/§10.4: the ON chip is gone, so a document (or preset) SAVED with the page off must load
    // audible — the resolver wins — while the stored value itself is never rewritten.
    func testEuclideousEnabledStoredFalseResolvesTrueAndRoundTripsUntouched() throws {
        var st = doc()
        st.euclideousEnabled = false
        XCTAssertTrue(st.euclideousEnabledResolved, "stored false still resolves true")
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.euclideousEnabled, false, "the stored field round-trips without loss")
        XCTAssertTrue(back.euclideousEnabledResolved)
        var on = doc(); on.euclideousEnabled = true
        XCTAssertEqual(try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(on)).euclideousEnabled, true)
    }

    // MARK: - FERRY (2026-10-15, "Fourfold settings") §10 test 6

    // A document missing both new keys (every pre-ferry doc, including every factory preset) decodes
    // without throwing and resolves to the ferry's own stated defaults — every channel (OMNI) and KEEP
    // PLAYING — relying ENTIRELY on PluginState's synthesized Decodable (no custom init(from:) exists on
    // this struct — confirmed by reading before writing this — so every Optional field, these two included,
    // already decodes tolerantly for free).
    func testFourfoldSettingsFieldsDecodeAbsentAsDefaultsAndRoundTrip() throws {
        // A fresh `doc()`, encoded: both new fields are nil, and Codable's synthesized encode(to:) omits a
        // nil Optional entirely (no key written) — this simulates a real pre-ferry document without needing
        // to hand-write a full PluginState JSON literal (whose many OTHER non-Optional fields would make a
        // hand-rolled minimal literal fail to decode for unrelated reasons).
        let decoded = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(doc()))
        XCTAssertNil(decoded.euclideousMidiInChannelMask)
        XCTAssertEqual(decoded.euclideousMidiInChannelMaskResolved, 0xFFFF)
        XCTAssertNil(decoded.euclideousHostStopBehavior)
        XCTAssertEqual(decoded.euclideousHostStopBehaviorResolved, .keepPlaying)

        var st = doc()
        st.euclideousMidiInChannelMask = (1 << 0) | (1 << 9)
        st.euclideousHostStopBehavior = .stop
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.euclideousMidiInChannelMask, (1 << 0) | (1 << 9))
        XCTAssertEqual(back.euclideousHostStopBehaviorResolved, .stop)

        // §3.5, literal: "a stored 0 resolves to every channel too."
        var zero = doc(); zero.euclideousMidiInChannelMask = 0
        XCTAssertEqual(zero.euclideousMidiInChannelMaskResolved, 0xFFFF)
    }

    // MIX TAB (ferry 2026-10-18) §9.5 — notesGate/notesVelocity decode tolerant, round-trip without loss, and the one field the
    // decoder used to skip (velocityAbsolute) now survives a save/load.
    func testEuclidLineDecodesWithoutTheMixKeysAndResolvesToTheLanesOwnValues() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"gate":0.6,"notesVelOffset":-10}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertNil(line.notesGate); XCTAssertNil(line.notesVelocity)
        XCTAssertEqual(line.notesGateResolved, 0.6, "nil reads the lane's GATE"); XCTAssertEqual(line.notesVelocityResolved, 90, "nil reads VEL (100) + offset (−10)")
    }
    func testVelocityAbsoluteAndTheMixFieldsRoundTripThroughCodable() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.velocityAbsolute = 55; line.notesGate = 0.35; line.notesVelocity = 88
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(line))
        XCTAssertEqual(back.velocityAbsolute, 55, "REGRESSION: the lane's VEL was encoded but never decoded, so it reset to 100 on every load")
        XCTAssertEqual(back.velocityAbsoluteResolved, 55)
        XCTAssertEqual(back.notesGate, 0.35); XCTAssertEqual(back.notesVelocity, 88)
        XCTAssertEqual(back, line)
        // a saved document written by an older build (VEL on disk under its key) loads its VEL
        let old = Data(#"{"target":0,"pulses":3,"steps":8,"rotate":0,"invert":false,"velocityAbsolute":72}"#.utf8)
        XCTAssertEqual(try JSONDecoder().decode(EuclidLine.self, from: old).velocityAbsoluteResolved, 72)
    }
    /// The bug CLASS: a stored field the hand-written decoder forgets. Every stored field is set to a non-default value, round-tripped,
    /// and compared — and a reflection check fails the test if a newly added field isn't populated here, so the next field can't be skipped.
    func testEveryStoredEuclidLineFieldSurvivesAnEncodeDecodeRoundTrip() throws {
        var l = EuclidLine(target: 3, pulses: 7, steps: 11, rotate: 4, invert: true)
        l.pick = .cycle; l.die = 3; l.noteSel = .n3; l.reverse = true; l.gate = 0.61; l.octave = 2; l.direction = .bkw; l.enabled = false
        l.velocity = 1.5; l.velocityAbsolute = 73; l.missNoteSel = .high; l.missGate = 0.4; l.missOctave = -1; l.missVelocity = 0.5
        l.patternMiss = true; l.rate = .r1_8; l.emitterMask = 0b0110; l.useRiff = true; l.melodyMode = .riff; l.litNotes = 0b0101_0101
        l.topLit = true; l.top2Lit = true; l.riffOn = false; l.riffRotate = 2; l.riffOctave = -2; l.riffDir = .pendulum; l.riffDirSeed = 9
        l.riffDirBias = 0.25; l.mask = EuclidLineMask(); l.sourceMode = .midi; l.tilt = -0.3; l.riffLock = true; l.riffInvert = true
        l.riffOnRest = .repeatLast; l.riffStride = 3; l.riffLength = 5; l.riffAdvanceStep = true; l.melodyTranspose = -2
        l.customHits = [true, false, true]; l.notesOn = false; l.noteOctShifts = [1, -1, 0, 0, 0, 0, 0, 1]; l.notesVelOffset = -20
        l.resetSteps = 4; l.restartMask = 0b0000_0101; l.listenRhythmMode = .gaps; l.listenRhythmPartner = 2; l.listenFollowMult = -1
        l.listenPitchMode = .avoid; l.listenPitchPartner = 1; l.listenPitchPartnerAny = true; l.listenShadowInterval = 3; l.listenShadowOctave = -1
        l.listenAvoidAction = .move; l.listenLevelMode = .accent; l.listenLevelPartner = 3; l.listenLevelAmount = 0.65
        l.notesGate = 0.45; l.notesVelocity = 66
        l.muteCells16 = 0x0F3C; l.muteUnit = 3; l.restartRhythmMask16 = 0x0121; l.restartMelodyMask16 = 0x8040; l.restartUnit = 4   // LANES GRID
        l.restartRhythmBars = [2, 1]; l.restartMelodyPasses = [1]; l.hitsRequested = 5; l.offsetRequested = 3   // RESTART CHAINS (2026-10-19)
        l.riffAdvanceEvery = 3; l.riffShiftRequested = 4   // RIFF WALK (2026-10-19)
        // NOTES TAB (2026-10-19). riffOnRest is `.repeatLast` above, not `.fill`: FILL leaves ON REST and decodes as SKIP by design (§9).
        l.notesWhen = 0b01; l.notesChance = 50; l.notesPlayAs = .split; l.notesReceivedOnly = true
        var order = EuclideousLitOrder(); for p in [0, 2, 4, 6, 8, 9] { order.append(p) }; l.setLitOrder(order)   // = the litNotes / topLit / top2Lit set above
        // every OPTIONAL stored field is populated (so this test can't silently stop covering a newly added one)
        for child in Mirror(reflecting: l).children {
            let m = Mirror(reflecting: child.value)
            if m.displayStyle == .optional { XCTAssertFalse(m.children.isEmpty, "field `\(child.label ?? "?")` is not populated in this round-trip test — add it") }
        }
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l, "a stored field was encoded but not decoded (or vice versa)")
    }

}
