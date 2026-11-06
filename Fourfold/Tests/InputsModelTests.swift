//  InputsModelTests.swift — INPUTS + HARMONY ferry (2026-11-06) §10 tests 2, 3, 8, 9, 10: the pure halves — the load-time source migration, the per-lane mode fallback, the per-source status, the grid pill and the NOW row's source pips.

import XCTest

final class InputsModelTests: XCTestCase {
    private func doc(midi: Bool, chords: Bool, pick: Bool, key: Bool, mode: MidiMode = .add, laneChips: [UInt8?] = [nil, nil, nil, nil]) -> PluginState {
        var st = PluginState.makeInit()
        st.euclideousSourcePlan = SourcePlan(midiOn: midi, chordsOn: chords, pickOn: pick, keyOn: key, midiMode: mode, pickNotes: [60, 64], midiOctaves: .keep)
        var lines = st.euclideousLinesResolved
        for i in 0..<4 { lines[i].poolSrcMask = laneChips[i] }
        st.euclideousLines = lines
        return st
    }

    // MARK: test 2 — migration (1.3)

    func testEveryCombinationOfTheFourSwitchesGivesTheLanesChipsAsTheAND() {
        for bits in 0..<16 {
            let midi = bits & 1 != 0, chords = bits & 2 != 0, pick = bits & 4 != 0, key = bits & 8 != 0
            var st = doc(midi: midi, chords: chords, pick: pick, key: key, laneChips: [nil, 0b10001, 0b01111, 0b00101])
            let changed = st.normalizeSourcesAtLoad()
            let want: [UInt8] = ([0b01111, 0b10001, 0b01111, 0b00101] as [UInt8]).map { c in
                var m = c
                if !midi { m &= ~0b00001 }; if !chords { m &= ~0b10010 }; if !pick { m &= ~0b00100 }; if !key { m &= ~0b01000 }
                return euclideousPoolSrcNormalized(m)
            }
            XCTAssertEqual(changed, bits != 15, "switches \(bits): only a document with a switch off changes")
            XCTAssertEqual(st.euclideousLinesResolved.map { $0.poolSrcMaskResolved }, want, "switches \(bits)")
            let plan = st.sourcePlanResolved
            XCTAssertTrue(plan.midiOnR && plan.chordsOnR && plan.pickOnR && plan.keyOnR, "switches \(bits): all four come out true")
            XCTAssertEqual(plan.pickNotesR, [60, 64]); XCTAssertEqual(plan.midiOctavesR, .keep); XCTAssertEqual(plan.midiModeR, .add)
            let again = st; var twice = st
            XCTAssertFalse(twice.normalizeSourcesAtLoad(), "switches \(bits): idempotent"); XCTAssertEqual(twice, again, "switches \(bits): a second run touches nothing")
        }
    }
    func testADocumentWithNoPlanAndNoLinesMaterialisesTheLanesFromTheLegacySource() {
        var st = PluginState.makeInit(); st.euclideousSourcePlan = nil; st.euclideousLines = nil; st.euclideousNoteSource = .key
        let resolvedBefore = st.sourcePlanResolved
        st.normalizeSourcesAtLoad()
        XCTAssertEqual(st.euclideousLines?.count, 4, "the four default lines are materialised so the chips have somewhere to live")
        for l in st.euclideousLinesResolved { XCTAssertEqual(l.poolSrcMaskResolved, euclideousNormaliseSources(chips: euclideousPoolSrcAll, panel: euclideousPanelSwitches(resolvedBefore))) }
    }
    func testANormalisedDocumentIsUntouchedAndSurvivesARoundTrip() throws {
        var st = doc(midi: true, chords: true, pick: true, key: true, laneChips: [nil, 0b00011, nil, nil])
        let before = st
        XCTAssertFalse(st.normalizeSourcesAtLoad()); XCTAssertEqual(st, before, "an already-normalised document is not dirtied")
        var off = doc(midi: true, chords: false, pick: true, key: true); off.normalizeSourcesAtLoad()
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(off))
        XCTAssertEqual(back.euclideousLinesResolved.map { $0.poolSrcMaskResolved }, off.euclideousLinesResolved.map { $0.poolSrcMaskResolved }, "round-trip without loss")
        XCTAssertEqual(back.sourcePlanResolved, off.sourcePlanResolved)
        // the preset codec runs the migration too
        var legacy = doc(midi: true, chords: false, pick: false, key: true)
        legacy.euclideousSourcePlan?.midiMode = .replace
        let decoded = try XCTUnwrap(PresetStore.decode(try XCTUnwrap(PresetStore.encode(legacy))))
        XCTAssertTrue(decoded.sourcePlanResolved.chordsOnR && decoded.sourcePlanResolved.pickOnR, "a preset opens with the switches true")
        XCTAssertEqual(decoded.euclideousLinesResolved[0].poolSrcMaskResolved, 0b01001, "…and the lane's chips are the old effective sources (MIDI IN + KEY)")
        XCTAssertEqual(decoded.sourcePlanResolved.midiModeR, .replace, "the plan's mode survives as every lane's fallback")
    }
    func testEveryFactoryPresetKeepsItsEffectiveSourcesThroughTheMigration() {
        var changedNames: [String] = []
        for (name, make) in EuclideousPresets.all {
            var st = make(); st.migrateLegacyRoutingIfNeeded()
            let panel = euclideousPanelSwitches(st.sourcePlanResolved)
            let before = st.euclideousLinesResolved.map { euclideousLaneSources(panel: panel, mask: $0.poolSrcMaskResolved) }
            if st.normalizeSourcesAtLoad() { changedNames.append(name) }
            let after = st.euclideousLinesResolved.map { euclideousLaneSources(panel: euclideousPanelSwitches(st.sourcePlanResolved), mask: $0.poolSrcMaskResolved) }
            XCTAssertEqual(before, after, "\(name): each lane's effective sources are unchanged by the migration")
        }
        print("INPUTS-REPORT factory presets changed by the source migration: \(changedNames.isEmpty ? "none" : changedNames.joined(separator: ", "))")
    }

    // MARK: test 3 — the lane's mode (1.1)

    func testALaneWithoutAModeTakesThePlansAndAnUnknownStoredValueIsAdd() throws {
        for plan in MidiMode.allCases {
            XCTAssertEqual(euclideousLaneMidiMode(nil, planMode: plan), plan)
            for own in MidiMode.allCases { XCTAssertEqual(euclideousLaneMidiMode(own, planMode: plan), own, "a lane's own mode wins") }
        }
        let line = EuclidLine(noteSel: .all)
        XCTAssertNil(line.midiMode)
        var json = try XCTUnwrap(try JSONSerialization.jsonObject(with: JSONEncoder().encode(line)) as? [String: Any])
        XCTAssertNil(json["midiMode"], "a lane that never chose encodes nothing")
        json["midiMode"] = "SIDEWAYS"
        let weird = try JSONDecoder().decode(EuclidLine.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertEqual(euclideousLaneMidiMode(weird.midiMode, planMode: .replace), .add, "an unknown stored value resolves ADD, whatever the plan says")
        json["midiMode"] = 7
        XCTAssertNil(try JSONDecoder().decode(EuclidLine.self, from: JSONSerialization.data(withJSONObject: json)).midiMode, "a wrong type reads as missing")
        var set = line; set.midiMode = .root
        XCTAssertEqual(try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(set)).midiMode, .root, "round-trip")
    }

    // MARK: test 8 — the per-source status (6.2)

    func testEachSourceIsPlayingWaitingOrUnusedAcrossTheLanes() {
        typealias L = EuclideousSourceLight
        // lane 1: MIDI + CHORD 1, lane 2: CHORD 2 + KEY, lanes 3 and 4: PICK only / nothing
        let chips: [UInt8] = [0b00011, 0b11000, 0b00100, 0b00000]
        func s(_ contrib: [UInt8]) -> (L, L, L, L) { let r = euclideousSourceStatusAcrossLanes(laneContrib: contrib, laneChips: chips); return (r.midi, r.chords, r.pick, r.key) }
        XCTAssertTrue(s([0, 0, 0, 0]) == (.waiting, .waiting, .waiting, .waiting), "everything on for some lane, nothing contributing: waiting")
        XCTAssertTrue(s([0b0001, 0, 0, 0]) == (.playing, .waiting, .waiting, .waiting), "MIDI contributing to lane 1")
        XCTAssertTrue(s([0, 0b1010, 0, 0]) == (.waiting, .playing, .waiting, .playing), "lane 2's CHORD 2 and KEY lit")
        XCTAssertTrue(s([0b0010, 0, 0, 0]) == (.waiting, .playing, .waiting, .waiting), "CHORD 1 on lane 1 counts as CHORDS")
        XCTAssertTrue(s([0, 0, 0b0100, 0]) == (.waiting, .waiting, .playing, .waiting))
        XCTAssertTrue(s([0, 0, 0, 0b1111]) == (.waiting, .waiting, .waiting, .waiting), "a lane with every chip off contributes nothing, whatever its bits say")
        let none = euclideousSourceStatusAcrossLanes(laneContrib: [0b1111, 0b1111, 0b1111, 0b1111], laneChips: [0, 0, 0, 0])
        XCTAssertTrue((none.midi, none.chords, none.pick, none.key) == (.off, .off, .off, .off), "a source no lane uses is unused")
        let oneUsed = euclideousSourceStatusAcrossLanes(laneContrib: [0, 0, 0, 0], laneChips: [0b00001, 0, 0, 0])
        XCTAssertTrue((oneUsed.midi, oneUsed.chords, oneUsed.pick, oneUsed.key) == (.waiting, .off, .off, .off))
    }

    // MARK: test 9 — the pill (5.6)

    func testThePillShowsAdvanceAndOnlyAnActiveRestart() {
        var set = MachineParams()
        XCTAssertEqual(harmonyPill(set), HarmonyPill(advanceUnit: "TIME", advanceLane: nil, advanceValue: "1/1", restart: nil, spoken: "Advance by time, every 1/1; restart off"))
        set.advanceUnit = .loop; set.advanceLane = 1; set.advanceEvery = 4
        XCTAssertEqual(harmonyPill(set), HarmonyPill(advanceUnit: "LOOP", advanceLane: 1, advanceValue: "\u{00D7}4", restart: nil, spoken: "Advance by loop, lane 2, every 4; restart off"))
        set.advanceUnit = .riff; set.advanceLane = 0; set.advanceEvery = 1; set.restartOn = true; set.restartUnit = .bar; set.restartEvery = 4
        XCTAssertEqual(harmonyPill(set).restart, HarmonyPill.Restart(unit: "BAR", lane: nil, value: "\u{00D7}4"))
        XCTAssertEqual(harmonyPill(set).spoken, "Advance by riff, lane 1, every 1; restart by bar, every 4")
        set.restartUnit = .loop; set.restartLane = 2; set.restartEvery = 2
        XCTAssertEqual(harmonyPill(set).restart, HarmonyPill.Restart(unit: "LOOP", lane: 2, value: "\u{00D7}2"))
        set.restartOn = false
        XCTAssertNil(harmonyPill(set).restart, "restart off hides its part")
        set.advanceUnit = .time; set.chordsRate = .r1_4
        XCTAssertEqual(harmonyPill(set).advanceValue, "1/4", "TIME shows the rate label as built")
    }

    // MARK: test 10 — the rank chip's source pip (3.2)

    func testOnlyReceivedNotesCarryASourcePipAndTheOtherUsersNeverSeeOne() {
        let pool = [48, 50, 52], sources: [UInt8] = [3, 1, 0]
        let now = euclideousRankChips(sortedPool: pool, litMask: 0, sources: sources, name: { "n\($0)" })
        XCTAssertEqual(now.map { $0.sourcePip }, [3, 1, 0, nil, nil, nil, nil, nil], "ranks 1–3 are received (key, chords, MIDI); ranks 4–8 are octave copies: no pip")
        XCTAssertEqual(now.map { $0.received }, [true, true, true, false, false, false, false, false])
        XCTAssertTrue(euclideousRankChips(sortedPool: pool, litMask: 0, name: { "n\($0)" }).allSatisfy { $0.sourcePip == nil }, "the NOTES keys and the grid's labels use the plain function")
        XCTAssertTrue(euclideousRankChips(sortedPool: [], litMask: 0, sources: [], name: { _ in "–" }).allSatisfy { $0.sourcePip == nil }, "an empty pool has none")
        XCTAssertEqual(euclideousRankChips(sortedPool: pool, litMask: 0b101, sources: sources, name: { "n\($0)" }).map { $0.lit }.prefix(3), [true, false, true], "the pip option changes nothing else")
    }
}
