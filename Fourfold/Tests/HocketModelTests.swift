//  HocketModelTests.swift — HOCKET ferry (2026-10-27) §12 test 2 (persistence) and the §5.6 fixed-size snapshot types.
//  The document field is `PluginState.hocketRules: HocketRuleSet?` — encoded as a plain array of rules, sanitised whenever it is built or decoded (§5.4). Outputs are CABLES (1…8, `FourfoldPorts.cable`); 0 is ALL.

import XCTest

final class HocketModelTests: XCTestCase {

    private func rule(main: [Int] = [], alt: [Int] = [], _ configure: (inout HocketRule) -> Void = { _ in }) -> HocketRule {
        var r = HocketRule(); r.main = main; r.alt = alt; configure(&r); return r
    }
    /// Decode a document whose `hocketRules` key holds raw JSON.
    private func decode(rulesJSON: String) throws -> PluginState {
        let doc = PluginState(machines: [], scenes: [SceneState.empty()])
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        obj["hocketRules"] = try JSONSerialization.jsonObject(with: Data(rulesJSON.utf8), options: .fragmentsAllowed)
        return try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    // MARK: - §5.2 / §5.3 — nil, empty, the empty rule

    func testANewDocumentHasNoRulesAndEncodesNoKey() throws {
        let doc = PluginState.makeInit()
        XCTAssertNil(doc.hocketRules); XCTAssertEqual(doc.hocketRulesResolved, [])
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        XCTAssertNil(obj["hocketRules"], "a document with no rules writes nothing, so every existing document encodes as before")
    }
    func testAnEmptyRuleIsSection53() {
        let r = HocketRule()
        XCTAssertTrue(r.on); XCTAssertEqual(r.mode, .swap); XCTAssertEqual(r.main, []); XCTAssertEqual(r.alt, [])
        XCTAssertEqual(r.unit, .hits); XCTAssertEqual(r.mainLen, 1); XCTAssertEqual(r.altLen, 1); XCTAssertEqual(r.offset, 0)
        XCTAssertEqual(r.several, .together); XCTAssertEqual(r.countOn, 0); XCTAssertEqual(r.own, .replace)
        XCTAssertFalse(r.isLit, "an empty MAIN is never lit (§3.3)")
        XCTAssertTrue(rule(main: [3]).isLit); XCTAssertFalse(rule(main: [3]) { $0.on = false }.isLit)
    }

    // MARK: - round trip

    func testAdocumentWithRulesRoundTripsAndKeepsEverythingElse() throws {
        var doc = PluginState.makeInit()
        let r1 = rule(main: [1, 3], alt: [2]) { $0.mode = .pass; $0.unit = .bars; $0.mainLen = 3; $0.altLen = 2; $0.offset = 4; $0.several = .rotate; $0.countOn = 1; $0.own = .merge }
        let r2 = rule(main: [5], alt: [6, 7]) { $0.on = false }
        doc.hocketRules = HocketRuleSet([r1, r2])
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.hocketRulesResolved, [r1, r2])
        XCTAssertEqual(back, doc, "no other field moves (no migration, no factory reset — §5.7)")
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((obj["hocketRules"] as? [Any])?.count, 2, "stored as a plain array of rules (§5.1)")
    }
    func testADocumentWithoutTheFieldDecodesWithNoRulesAndNoFactoryReset() throws {
        var doc = PluginState.makeInit(); doc.euclideousKeyRoot = 5
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        obj.removeValue(forKey: "hocketRules")
        let back = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.hocketRules); XCTAssertEqual(back.hocketRulesResolved, [])
        XCTAssertEqual(back.euclideousKeyRoot, 5, "the rest of the document loads as it was")
        XCTAssertEqual(back, doc)
    }
    func testEveryFactoryPresetHasNoRulesAndEveryPresetOfADocumentCarriesItsOwn() throws {
        for (name, make) in EuclideousPresets.all { XCTAssertEqual(make().hocketRulesResolved, [], "\(name): presets without the field load with none") }
        var doc = PluginState.makeInit()
        doc.hocketRules = HocketRuleSet([rule(main: [2], alt: [4]) { $0.unit = .passes }])
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(doc))   // the same codec the user presets and the host session use
        XCTAssertEqual(back.hocketRulesResolved, doc.hocketRulesResolved, "a preset saved with rules loads its rules")
        // a whole-document replace (what a preset load is) that has no rules leaves none — the rules are not in the loads' keep-lists
        var loaded = doc; loaded = PluginState.makeInit()
        XCTAssertEqual(loaded.hocketRulesResolved, [])
    }

    // MARK: - §5.4 — every decode rule

    func testAnUnknownEnumWordTakesTheDefault() throws {
        let doc = try decode(rulesJSON: #"[{"on":true,"mode":"BOGUS","unit":"FORTNIGHTS","several":7,"own":null,"main":[1]}]"#)
        let r = try XCTUnwrap(doc.hocketRulesResolved.first)
        XCTAssertEqual(r.mode, .swap); XCTAssertEqual(r.unit, .hits); XCTAssertEqual(r.several, .together); XCTAssertEqual(r.own, .replace)
        XCTAssertEqual(r.main, [1], "the readable keys survive")
    }
    func testNumbersClampIntoRange() throws {
        let doc = try decode(rulesJSON: #"[{"main":[1,2],"alt":[3],"mainLen":99,"altLen":-4,"offset":999,"countOn":9}]"#)
        let r = try XCTUnwrap(doc.hocketRulesResolved.first)
        XCTAssertEqual(r.mainLen, 8); XCTAssertEqual(r.altLen, 1)
        XCTAssertEqual(r.offset, 8, "offset clamps into 0 … mainLen + altLen − 1 = 0…8")
        XCTAssertEqual(r.countOn, 0, "a COUNT ON past MAIN reads as the first MAIN output")
        let low = try decode(rulesJSON: #"[{"main":[1],"mainLen":2,"altLen":2,"offset":-5,"countOn":-1}]"#)
        XCTAssertEqual(low.hocketRulesResolved.first?.offset, 0); XCTAssertEqual(low.hocketRulesResolved.first?.countOn, 0)
        let frac = try decode(rulesJSON: #"[{"main":[1],"mainLen":2.6,"altLen":"x"}]"#)
        XCTAssertEqual(frac.hocketRulesResolved.first?.mainLen, 3, "a fractional number rounds"); XCTAssertEqual(frac.hocketRulesResolved.first?.altLen, 1, "an unreadable number keeps the default")
    }
    func testUnknownOutputsAllAndRepeatsAreDropped() throws {
        let doc = try decode(rulesJSON: #"[{"main":[0,3,3,9,"x",5,-2,3.0],"alt":[8,0,8,1],"countOn":2}]"#)
        let r = try XCTUnwrap(doc.hocketRulesResolved.first)
        XCTAssertEqual(r.main, [3, 5], "0 is ALL, 9 / −2 / \"x\" are unknown, repeats keep the first: order kept")
        XCTAssertEqual(r.alt, [8, 1])
        XCTAssertEqual(r.countOn, 0, "COUNT ON was index 2 of the raw list (an unknown output); it re-validates against the cleaned MAIN")
    }
    func testAnOutputMayBeInBothGroupsOfItsOwnRule() throws {
        let doc = try decode(rulesJSON: #"[{"main":[1,2],"alt":[2,3]}]"#)
        XCTAssertEqual(doc.hocketRulesResolved.first?.main, [1, 2]); XCTAssertEqual(doc.hocketRulesResolved.first?.alt, [2, 3])
    }
    func testAnOutputInTwoRulesIsKeptOnlyInTheFirstWhetherOrNotItsRuleIsOn() throws {
        let doc = try decode(rulesJSON: #"[{"on":false,"main":[1,2],"alt":[3]},{"main":[2,4],"alt":[1,5]},{"main":[3,6]}]"#)
        let rs = doc.hocketRulesResolved
        XCTAssertEqual(rs.count, 3)
        XCTAssertEqual(rs[0].main, [1, 2]); XCTAssertEqual(rs[0].alt, [3])
        XCTAssertEqual(rs[1].main, [4]); XCTAssertEqual(rs[1].alt, [5], "an OFF rule still owns its outputs (§4.4)")
        XCTAssertEqual(rs[2].main, [6]); XCTAssertEqual(rs[2].alt, [])
        let all = rs.flatMap { $0.main + $0.alt }
        XCTAssertEqual(all.count, Set(all).count, "no output is in two rules")
    }
    func testCountOnKeepsNamingItsOutputWhenAnEarlierRuleTakesOthersOutOfMain() throws {
        let doc = try decode(rulesJSON: #"[{"main":[1]},{"main":[1,2,3],"countOn":2}]"#)
        let r = doc.hocketRulesResolved[1]
        XCTAssertEqual(r.main, [2, 3]); XCTAssertEqual(r.main[r.countOn], 3, "COUNT ON still points at output 3")
    }
    func testRulesPastTheFourthAreDropped() throws {
        let doc = try decode(rulesJSON: #"[{"main":[1]},{"main":[2]},{"main":[3]},{"main":[4]},{"main":[5]},{"main":[6]}]"#)
        XCTAssertEqual(doc.hocketRulesResolved.map { $0.main }, [[1], [2], [3], [4]])
        XCTAssertEqual(HocketRuleSet((1...8).map { rule(main: [$0]) }).rules.count, 4, "building a set sanitises too")
    }
    func testAnUnreadableFieldDecodesToNoRulesInsteadOfFailingTheLoad() throws {
        for junk in ["5", #""x""#, #"{"a":1}"#, "null", "[]"] {
            let doc = try decode(rulesJSON: junk)
            XCTAssertEqual(doc.hocketRulesResolved, [], junk)
        }
        let doc = try decode(rulesJSON: #"[7, {"main":[2]}, "x"]"#)
        XCTAssertEqual(doc.hocketRulesResolved.count, 3, "a non-object entry reads as an empty rule (it still holds its place)")
        XCTAssertEqual(doc.hocketRulesResolved[0], HocketRule()); XCTAssertEqual(doc.hocketRulesResolved[1].main, [2])
    }
    func testSanitisingIsIdempotent() {
        let messy = [rule(main: [0, 3, 3, 12], alt: [3, 4]) { $0.mainLen = 40; $0.offset = 99; $0.countOn = 5 }, rule(main: [3, 4, 5]) { $0.altLen = 0 }]
        let once = HocketRuleSet(messy).rules
        XCTAssertEqual(HocketRuleSet(once).rules, once)
    }

    // MARK: - undo

    func testUndoRestoresThePreviousRulesAndAnEmptySetMeansNothingStored() {
        var stack = UndoStack<EuclideousUndoSnapshot>()
        func snap(_ rules: [HocketRule]) -> EuclideousUndoSnapshot {
            EuclideousUndoSnapshot(lines: [], riff: EuclideousRiff(), resetSpanBars: 0, keyRoot: 0, keyType: .major, chordSets: [], activeChordSet: 0, noteSource: .midi, riffs: [], activeRiff: 0,
                                   lanesSeq: EuclideousLanesSeq(), riffsSeq: EuclideousRiffsSeq(), hocketRules: rules)
        }
        let a = [rule(main: [1], alt: [2])], b = [rule(main: [1], alt: [2]) { $0.mode = .pass }]
        stack.record(snap([]), coalesceKey: nil)
        stack.record(snap(a), coalesceKey: nil)
        let back = stack.undo(current: snap(b))
        XCTAssertEqual(back?.hocketRules, a, "undo restores the previous rules")
        XCTAssertEqual(stack.undo(current: snap(a))?.hocketRules, [], "…and the step before that had none stored")
        XCTAssertEqual(stack.redo(current: snap([]))?.hocketRules, a)
        XCTAssertNotEqual(snap(a), snap(b), "the snapshot compares the rules, so a no-op edit is dropped and a real one is recorded")
    }

    // MARK: - §5.6 the snapshot

    func testTheSnapshotCarriesTheLitRulesAsFixedSizeDataOnTheEuclideousRowOnly() throws {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        let input = FourfoldCompose.Input(lines: st.euclideousLinesResolved, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: st.activeRiffResolved,
                                          soloMask: st.euclideousSoloMaskResolved, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        XCTAssertTrue(try XCTUnwrap(SnapshotBuilder.build(from: st).cells[Snap.euclideousRow].procs.first).hocketRules.isInert, "no rules ⇒ inert (§7.6)")
        st.hocketRules = HocketRuleSet([
            rule(main: [1, 3], alt: [2]) { $0.mode = .pass; $0.unit = .bars; $0.mainLen = 3; $0.altLen = 2; $0.offset = 4; $0.several = .rotate; $0.countOn = 1; $0.own = .merge },
            rule(main: [8], alt: [7]) { $0.on = false },          // off: carried, but not lit
            rule(main: [], alt: [5, 6]),                           // empty MAIN: not lit
        ])
        let p = try XCTUnwrap(SnapshotBuilder.build(from: st).cells[Snap.euclideousRow].procs.first).hocketRules
        XCTAssertFalse(p.isInert); XCTAssertEqual(p.litMask, 0b001, "only rule 1 is lit")
        let r = p[0]
        XCTAssertTrue(r.lit); XCTAssertEqual(r.mode, .pass); XCTAssertEqual(r.unit, .bars); XCTAssertEqual(r.mainLen, 3); XCTAssertEqual(r.altLen, 2); XCTAssertEqual(r.offset, 4)
        XCTAssertTrue(r.rotate); XCTAssertFalse(r.replace)
        XCTAssertEqual((0..<r.main.count).map { r.main[$0] }, [0, 2], "cables 1 and 3 are BUS 0 and 2 (Emit Riff A, Emit Riff B)")
        XCTAssertEqual((0..<r.alt.count).map { r.alt[$0] }, [1])
        XCTAssertEqual(r.countOnBus, 2, "COUNT ON index 1 of MAIN = cable 3 = bus 2"); XCTAssertEqual(r.referenceLane, 1, "bus 2 is lane 2's riff output")
        XCTAssertEqual(p.litBusMask, 0b0000_0111, "outputs of a LIT rule only: the off rule's and the empty-MAIN rule's outputs don't join (§7.3)")
        XCTAssertEqual(p.ruleOfBus[0], 0); XCTAssertEqual(p.ruleOfBus[1], 0); XCTAssertEqual(p.ruleOfBus[2], 0); XCTAssertEqual(p.ruleOfBus[7], -1); XCTAssertEqual(p.ruleOfBus[4], -1)
        XCTAssertFalse(p[1].lit); XCTAssertFalse(p[2].lit)
    }
    func testAGroupHoldsEightOutputsInOrderAsPlainValueStorage() {
        let g = HocketGroup(cables: [8, 1, 0, 9, 4])
        XCTAssertEqual((0..<g.count).map { g[$0] }, [7, 0, 3], "cables → buses in tapped order; ALL (0) and unknown cables are not stored")
        XCTAssertEqual(g.mask, 0b1000_1001); XCTAssertEqual(g.index(of: 3), 2); XCTAssertTrue(g.contains(bus: 7)); XCTAssertFalse(g.contains(bus: 1))
        let full = HocketGroup(cables: Array(1...8))
        XCTAssertEqual(full.count, 8); XCTAssertEqual(full.mask, 0xFF); XCTAssertEqual(full.index(of: 5), 5); XCTAssertNil(HocketGroup().index(of: 0)); XCTAssertTrue(HocketGroup().isEmpty)
        XCTAssertLessThanOrEqual(MemoryLayout<HocketRulesSnap>.size, 512, "four rules of fixed value storage — no array, no class reference")
    }
}
