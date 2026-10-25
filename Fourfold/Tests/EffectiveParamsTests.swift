//  EffectiveParamsTests.swift
//  Re-homed (2026-08-05) as the MACRO MODULATION engine tests. The old A/B-morph interpolation these once covered
//  was removed; the file is now the natural home for the macro offset model (base ⊕ value×delta) per the map's
//  recommendation. M0 here = the STATE MODEL (persistence + snapshot plumbing); M1 adds the offset-math cases.

import XCTest

final class EffectiveParamsTests: XCTestCase {

    /// A minimal valid document (macro tests don't touch machines/scenes).
    private func doc() -> PluginState { PluginState(machines: [], scenes: [SceneState.empty()]) }

    // MARK: M0 — the macro state model


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

    // PER-LAYER ROUTING ferry (2026-10-25) §3, test 2: riffOutMask / notesOutMask split the single emitterMask.
    func testPerLayerOutMasksDecodeTolerantAndResolveToEmitterMask() throws {
        // A pre-feature document (no riff/notesOutMask keys) decodes with both resolving to its old emitterMask.
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"emitterMask":5}"#.utf8)
        let line = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertNil(line.riffOutMask); XCTAssertNil(line.notesOutMask)
        XCTAssertEqual(line.riffOutMaskResolved, 0b0101, "nil ⇒ inherit emitterMask")
        XCTAssertEqual(line.notesOutMaskResolved, 0b0101)
        // A lane that never had emitterMask either: both resolve to nil (⇒ the Router inherits the cell bus, today's behaviour).
        var bare = EuclidLine(pulses: 3, steps: 8)
        XCTAssertNil(bare.riffOutMaskResolved); XCTAssertNil(bare.notesOutMaskResolved)
        _ = bare
    }
    func testPerLayerOutMasksRoundTripAndDropBitsAboveFour() throws {
        var line = EuclidLine(pulses: 3, steps: 8)
        line.riffOutMask = 0b0001   // A
        line.notesOutMask = 0b0010  // B
        let back = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(line))
        XCTAssertEqual(back.riffOutMask, 0b0001); XCTAssertEqual(back.notesOutMask, 0b0010)
        // A corrupt value with bits above the four outputs is masked to 0x0F at decode.
        let dirty = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"riffOutMask":241,"notesOutMask":255}"#.utf8)
        let d = try JSONDecoder().decode(EuclidLine.self, from: dirty)
        XCTAssertEqual(d.riffOutMask, 0b0001, "241 = 0xF1 → low nibble 0x01"); XCTAssertEqual(d.notesOutMask, 0b1111)
    }
    func testEmitterMaskForEncodeIsTheUnionButUntouchedIsVerbatim() throws {
        // §3.3: a split lane's emitterMask (what an older build reads) is the union of the two parts.
        var split = EuclidLine(pulses: 3, steps: 8)
        split.riffOutMask = 0b0001; split.notesOutMask = 0b0010
        XCTAssertEqual(split.emitterMaskForEncode, 0b0011, "A | B")
        // An untouched lane keeps emitterMask verbatim (incl. nil = inherit), so an existing doc re-saved is byte-identical.
        var untouched = EuclidLine(pulses: 3, steps: 8); untouched.emitterMask = 0b0101
        XCTAssertEqual(untouched.emitterMaskForEncode, 0b0101)
        var inheriting = EuclidLine(pulses: 3, steps: 8)
        XCTAssertNil(inheriting.emitterMaskForEncode, "neither part nor emitterMask set ⇒ still inherit"); _ = inheriting
    }
    // §2.5/§3.4: a circle tap (`toggleOutput`) pins BOTH parts to their resolved value, flips the tapped part's bit,
    // and keeps emitterMask = the union — so the UNtapped part is NOT dragged along and the synthesized encoder persists
    // the §3.3 forward-compat union with no custom encode. This is exactly the leak the "pin both first" rule prevents.
    func testToggleOutputPinsBothPartsFlipsOneAndKeepsEmitterMaskTheUnion() throws {
        var l = EuclidLine(pulses: 3, steps: 8); l.emitterMask = 0b0001   // fresh default: A, both parts nil (inheriting)
        l.toggleOutput(.riff, bit: 0b0010)                                // tap riff B
        XCTAssertEqual(l.riffOutMask, 0b0011, "riff now A+B")
        XCTAssertEqual(l.notesOutMask, 0b0001, "notes PINNED to its old resolved A — NOT dragged to B")
        XCTAssertEqual(l.emitterMask, 0b0011, "emitterMask = riff | notes")
        // The on-disk emitterMask (read by an older build) equals the union, via the SYNTHESIZED encoder.
        let back = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(l))
        XCTAssertEqual(back.emitterMask, 0b0011); XCTAssertEqual(back.riffOutMask, 0b0011); XCTAssertEqual(back.notesOutMask, 0b0001)
        // Tapping the same bit again un-routes it; a part routed nowhere is mask 0 (sounds nowhere).
        l.toggleOutput(.riff, bit: 0b0001); l.toggleOutput(.riff, bit: 0b0010)
        XCTAssertEqual(l.riffOutMask, 0b0000, "riff routed nowhere"); XCTAssertEqual(l.emitterMask, 0b0001, "still carries notes' A")
    }

    // OUT-MASK-NIL-1 (2026-10-25): a lane with NO stored mask (every factory preset, an older session) sounds on A-D —
    // the Router sees nil and inherits the cell's open bus — so the page must show it as all four, and the first circle
    // tap must turn ONE output off, not collapse "all four" to just the tapped one. The Optional `…Resolved` pair stays
    // nil for the Router; only the `…Display` pair reads nil as A-D.
    func testALaneWithNoStoredMaskDisplaysAsAllFourAndStaysNilForTheRouter() {
        let l = EuclidLine(pulses: 3, steps: 8)
        XCTAssertNil(l.riffOutMaskResolved); XCTAssertNil(l.notesOutMaskResolved)
        XCTAssertEqual(l.riffOutMaskDisplay, 0b1111); XCTAssertEqual(l.notesOutMaskDisplay, 0b1111)
        XCTAssertEqual(euclideousLaneMasks([l]), [0b1111, 0, 0, 0])
        var m = EuclidLine(pulses: 3, steps: 8); m.emitterMask = 0b0010
        XCTAssertEqual(m.riffOutMaskDisplay, 0b0010, "a stored mask is shown as stored")
    }
    func testTappingACircleOnALaneWithNoStoredMaskTurnsOffOnlyThatOutput() throws {
        var l = EuclidLine(pulses: 3, steps: 8)                       // no mask anywhere, as a factory preset leaves it
        l.toggleOutput(.riff, bit: 0b0001)                            // tap riff A
        XCTAssertEqual(l.riffOutMask, 0b1110, "riff was on A-D; A is now off")
        XCTAssertEqual(l.notesOutMask, 0b1111, "notes keeps A-D — it is not dragged along")
        XCTAssertEqual(l.emitterMask, 0b1111, "the legacy field is the union")
        let back = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(l))
        XCTAssertEqual(back.riffOutMask, 0b1110); XCTAssertEqual(back.notesOutMask, 0b1111)
        // A hand-made document with only ONE part stored: the other part still inherits A-D in the legacy union.
        var half = EuclidLine(pulses: 3, steps: 8); half.riffOutMask = 0b0001
        XCTAssertEqual(half.emitterMaskForEncode, 0b1111)
    }
    // ── ALT ROUTING ferry (2026-10-25) §4 / test 2 + test 10 ──────────────────────────────────────────
    // §4.2/§4.7: a pre-feature document (no riffAlt/notesAlt/outLink keys) decodes with mode OFF, the defaults, and
    // no link — so every existing lane and preset is unchanged.
    func testAltDecodesOffWithDefaultsAndNoLink() throws {
        let json = Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false}"#.utf8)
        let l = try JSONDecoder().decode(EuclidLine.self, from: json)   // MUST NOT throw
        XCTAssertNil(l.riffAlt); XCTAssertNil(l.notesAlt); XCTAssertNil(l.outLink)
        let r = l.riffAltResolved, n = l.notesAltResolved
        XCTAssertEqual(r.mode, .off); XCTAssertEqual(n.mode, .off)
        XCTAssertEqual(r.every, 1); XCTAssertEqual(r.offset, 0); XCTAssertEqual(r.strip, 0b1111_0000)
        XCTAssertEqual(r.passes, 1); XCTAssertEqual(r.passOffset, 0); XCTAssertEqual(r.chance, 50); XCTAssertEqual(r.altMask, 0)
        // §4.2 part-aware SPLIT default: rank 4 for the riff, LOWEST for the notes.
        XCTAssertEqual(r.splitRank, 4); XCTAssertFalse(r.splitLowest)
        XCTAssertTrue(n.splitLowest); XCTAssertEqual(n.splitRank, 0)
        // an UNKNOWN mode decodes OFF
        let dirty = try JSONDecoder().decode(EuclidLine.self, from: Data(#"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"riffAlt":{"mode":"ZZZ","altMask":2}}"#.utf8))
        XCTAssertEqual(dirty.riffAltResolved.mode, .off, "unknown mode ⇒ OFF"); XCTAssertEqual(dirty.riffAltResolved.altMask, 0b0010)
    }
    // §4.2 clamps, via the resolver.
    func testAltResolverClampsEveryValueIntoRange() {
        var a = EuclideousAltRouting()
        a.every = 99; a.offset = 99; a.passes = 0; a.passOffset = 99; a.chance = 37; a.split = 42; a.altMask = 0xFF
        let r = a.resolved(forRiff: true)
        XCTAssertEqual(r.every, 8, "every clamps to 1…8"); XCTAssertEqual(r.offset, 2 * 8 - 1, "offset into 0…2·every−1")
        XCTAssertEqual(r.passes, 1, "passes clamps to 1…8"); XCTAssertEqual(r.passOffset, 2 * 1 - 1, "passOffset into 0…2·passes−1")
        XCTAssertEqual(r.chance, 40, "chance to the nearest multiple of 10"); XCTAssertEqual(r.splitRank, 7, "split 8+ → 7")
        XCTAssertEqual(r.altMask, 0x0F, "mask bits above the four outputs dropped")
        XCTAssertEqual(EuclideousAltRouting().resolved(forRiff: true).chance, 50)
        // chance clamps into 10…90 at the ends
        var lo = EuclideousAltRouting(); lo.chance = 0; XCTAssertEqual(lo.resolved(forRiff: false).chance, 10)
    }
    // §4 round-trip (incl. the link) + §4.5 seed + SnapshotBuilder carry.
    func testAltRoundTripsSeedsAndTravelsThroughTheSnapshot() throws {
        var l = EuclidLine(pulses: 3, steps: 8); l.emitterMask = 0b0001
        // §4.5 seed: mode OFF → HITS with an empty ALT mask seeds ALT to the output after MAIN's lowest.
        l.setAltMode(.riff, .hits)
        XCTAssertEqual(l.riffAlt?.altMask, 0b0010, "MAIN A ⇒ seed ALT = B (test 10 / §4.5)")
        XCTAssertEqual(l.riffAlt?.mode, .hits)
        l.editAlt(.riff) { $0.every = 2; $0.offset = 1 }
        l.setOutLink(apply: true, source: .riff)
        XCTAssertEqual(l.outLink, .riff, "BOTH from the riff ⇒ the riff leads")
        // round-trip
        let back = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(l))
        XCTAssertEqual(back.riffAlt, l.riffAlt); XCTAssertEqual(back.outLink, .riff)
        // SnapshotBuilder's fresh literal carries all three (miss the spot ⇒ they reset): build a snapshot through the
        // euclid machine (the SnapshotBuilder:346 source) and read them back.
        var c = Machine(machineID: "gold", type: .euclid)
        c.paramsA.euclidLines = [l]
        var sc = SceneState.empty()
        sc.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a])
        let built = SnapshotBuilder.build(from: PluginState(machines: [c], scenes: [sc]))
        let rebuilt = built.machines.first { $0.a.euclidLines.count == 4 }?.a.euclidLines.first
        XCTAssertEqual(rebuilt?.riffAlt, l.riffAlt, "riffAlt survives the SnapshotBuilder rebuild")
        XCTAssertEqual(rebuilt?.outLink, .riff, "outLink survives the SnapshotBuilder rebuild")
    }
    // §4.5 seed, the three other MAIN cases (test 10).
    func testAltSeedPicksTheOutputAfterMainsLowest() {
        XCTAssertEqual(euclideousSeedAltMask(main: 0b0001), 0b0010, "A → B")
        XCTAssertEqual(euclideousSeedAltMask(main: 0b0100), 0b1000, "C → D")
        XCTAssertEqual(euclideousSeedAltMask(main: 0b1000), 0b0001, "D → A")
        XCTAssertEqual(euclideousSeedAltMask(main: 0), 0b0001, "MAIN empty → A")
        XCTAssertEqual(euclideousSeedAltMask(main: 0b0110), 0b0100, "lowest of B+C is B → C")
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


    // MARK: M1 — the offset math (applyMacros)





    // MARK: M1 — end to end through the builder


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


    // MARK: OUTPUT — macros modulate the per-emitter role amounts (LEAK/DUCK/CURVE/POCKET)


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


    // MARK: applyMacros — guard edges (negative index · zero-offset short-circuit)


    // MARK: Snapshot effective* — the quantize/clamp helpers (render-side, §3.2)

    private func snapMachine(_ mutate: (inout SnapParams) -> Void) -> SnapMachine {
        var sc = SnapMachine(); mutate(&sc.a); return sc
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
    /// RHYTHM DYNAMICS was removed (2026-10-21): a lane saved while it existed still carries its five keys (`dynDepth`…`dynTarget`) — they must be ignored on load, never a failure, and never written back.
    func testALaneSavedWithTheRemovedDynamicsKeysStillDecodesAndTheKeysAreDropped() throws {
        let json = #"{"target":0,"pulses":5,"steps":8,"rotate":0,"invert":false,"gate":0.6,"dynDepth":80,"dynAccents":3,"dynShape":-40,"dynSpread":15,"dynTarget":"BOTH"}"#
        let line = try JSONDecoder().decode(EuclidLine.self, from: Data(json.utf8))   // MUST NOT throw
        XCTAssertEqual(line.pulses, 5); XCTAssertEqual(line.gateResolved, 0.6, "everything else is read as before")
        let back = String(decoding: try JSONEncoder().encode(line), as: UTF8.self)
        XCTAssertFalse(back.contains("dyn"), "the removed keys are not written back")
    }
    /// The bug CLASS: a stored field the hand-written decoder forgets. Every stored field is set to a non-default value, round-tripped,
    /// and compared — and a reflection check fails the test if a newly added field isn't populated here, so the next field can't be skipped.
    func testEveryStoredEuclidLineFieldSurvivesAnEncodeDecodeRoundTrip() throws {
        var l = EuclidLine(target: 3, pulses: 7, steps: 11, rotate: 4, invert: true)
        l.pick = .cycle; l.die = 3; l.noteSel = .n3; l.reverse = true; l.gate = 0.61; l.octave = 2; l.direction = .bkw; l.enabled = false
        l.velocity = 1.5; l.velocityAbsolute = 73; l.missNoteSel = .high; l.missGate = 0.4; l.missOctave = -1; l.missVelocity = 0.5
        l.patternMiss = true; l.rate = .r1_8; l.emitterMask = 0b0110; l.riffOutMask = 0b0001; l.notesOutMask = 0b1000; l.useRiff = true; l.melodyMode = .riff; l.litNotes = 0b0101_0101
        l.topLit = true; l.top2Lit = true; l.riffOn = false; l.riffRotate = 2; l.riffOctave = -2; l.riffDir = .pendulum; l.riffDirSeed = 9
        l.riffDirBias = 0.25; l.mask = EuclidLineMask(); l.sourceMode = .midi; l.tilt = -0.3; l.riffLock = true; l.riffInvert = true
        l.riffOnRest = .repeatLast; l.riffStride = 3; l.riffLength = 5; l.riffAdvanceStep = true; l.melodyTranspose = -2
        l.customHits = [true, false, true]; l.notesOn = false; l.noteOctShifts = [1, -1, 0, 0, 0, 0, 0, 1]; l.notesVelOffset = -20
        l.resetSteps = 4; l.restartMask = 0b0000_0101; l.listenRhythmMode = .gaps; l.listenRhythmPartner = 2; l.listenFollowMult = -1
        l.listenPitchMode = .avoid; l.listenPitchPartner = 1; l.listenPitchPartnerAny = true; l.listenShadowInterval = 3; l.listenShadowOctave = -1
        l.listenAvoidAction = .move; l.listenLevelMode = .accent; l.listenLevelPartner = 3; l.listenLevelAmount = 0.65
        // LISTEN REBUILT (2026-10-23)
        l.listenSource = 2; l.listenRhythm = .fill; l.listenDelay = 3; l.listenFeel = -0.2; l.listenSpeed = 1
        l.listenDirection = .pingpong; l.listenPitch = .echo; l.listenInterval = -4; l.listenOctave = 2
        l.notesGate = 0.45; l.notesVelocity = 66
        l.muteCells16 = 0x0F3C; l.muteUnit = 3; l.restartRhythmMask16 = 0x0121; l.restartMelodyMask16 = 0x8040; l.restartUnit = 4   // LANES GRID
        l.restartRhythmBars = [2, 1]; l.restartMelodyPasses = [1]; l.hitsRequested = 5; l.offsetRequested = 3   // RESTART CHAINS (2026-10-19)
        l.riffAdvanceEvery = 3; l.riffShiftRequested = 4   // RIFF WALK (2026-10-19)
        // NOTES TAB (2026-10-19). riffOnRest is `.repeatLast` above, not `.fill`: FILL leaves ON REST and decodes as SKIP by design (§9).
        l.notesWhen = 0b01; l.notesChance = 50; l.notesPlayAs = .split; l.notesReceivedOnly = true
        l.offsetFraction = 0.35; l.tiltFine = -0.3   // RHYTHM POLISH (2026-10-22)
        // ALT ROUTING (2026-10-25): populate all three new Optionals so this guard keeps covering them
        var ra = EuclideousAltRouting(); ra.mode = .hits; ra.altMask = 0b0010; ra.every = 3; ra.offset = 2; ra.strip = 0b1010_1010; ra.passes = 4; ra.passOffset = 1; ra.chance = 70; ra.split = 5
        var na = EuclideousAltRouting(); na.mode = .split; na.altMask = 0b0100; na.split = 0
        l.riffAlt = ra; l.notesAlt = na; l.outLink = .notes
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
