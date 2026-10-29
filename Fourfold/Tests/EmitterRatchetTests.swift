//  EmitterRatchetTests.swift — RATCH tab ferry (2026-10-28): the model (§1), the pattern, the count and the decision (§2), the value cells (§6.2). The Router's behaviour is in `EmitterRatchetRouterTests`.
//  The document field is `PluginState.euclideousEmitterRatchets: EmitterRatchetSet?` — four fixed-size ratchets, one per output A–D, nil ⇒ all defaults and all OFF.

import XCTest

final class EmitterRatchetTests: XCTestCase {

    private func decode(ratchetsJSON: String) throws -> PluginState {
        let doc = PluginState(machines: [], scenes: [SceneState.empty()])
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        obj["euclideousEmitterRatchets"] = try JSONSerialization.jsonObject(with: Data(ratchetsJSON.utf8), options: .fragmentsAllowed)
        return try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
    }
    private func cfg(on: Bool = true, steps: Int = 8, hits: Int = 3, offset: Int = 0, chance: Int = 100, strikes: Int = 3) -> EmitterRatchetCfg {
        EmitterRatchetCfg(EmitterRatchet(on: on, steps: steps, hits: hits, offset: offset, chance: chance, strikes: strikes))
    }
    /// The pattern the RHYTHM tab shows for a lane at these settings (tilt 0, not flipped): the lane's own builder.
    private func lanePattern(steps: Int, hits: Int, offset: Int) -> UInt16 {
        var L = EuclidLine(); L.steps = steps; L.pulses = hits; L.rotate = offset
        var cells = [Bool](repeating: false, count: 32), micro = [Double](repeating: 0, count: 32)
        let n = euclideousBuildHitPatternInto(L, cells: &cells, micro: &micro)
        var m: UInt16 = 0
        for i in 0..<n where cells[i] { m |= UInt16(1) << UInt16(i) }
        return m
    }

    // MARK: - §10 test 1 — the pattern is the RHYTHM tab's

    func testThePatternMatchesTheRhythmTabsLanePattern() {
        for (steps, hits, offset) in [(8, 3, 0), (16, 16, 0), (5, 2, 3), (16, 5, 7), (2, 1, 1), (12, 0, 0), (7, 7, 6), (11, 4, 10)] {
            XCTAssertEqual(emitterRatchetPatternMask(steps: steps, hits: hits, offset: offset), lanePattern(steps: steps, hits: hits, offset: offset), "\(steps)/\(hits)/\(offset)")
        }
        XCTAssertEqual(emitterRatchetPatternMask(steps: 8, hits: 3, offset: 0), 0b0100_1001, "8 steps, 3 hits: X . . X . . X .")
        XCTAssertEqual(emitterRatchetPatternMask(steps: 16, hits: 16, offset: 0), 0xFFFF, "every step a hit")
        XCTAssertEqual(emitterRatchetPatternMask(steps: 5, hits: 2, offset: 3), 0b00101, "OFFSET slides the pattern earlier and wraps")
    }
    func testTheSnapshotsConfigCarriesTheMaskAndSteps() {
        let c = cfg(steps: 5, hits: 2, offset: 3)
        XCTAssertEqual(c.patternMask, 0b00101)
        XCTAssertTrue(c.isHit(0)); XCTAssertFalse(c.isHit(1)); XCTAssertTrue(c.isHit(2)); XCTAssertFalse(c.isHit(5), "past STEPS nothing is a hit"); XCTAssertFalse(c.isHit(-1)); XCTAssertFalse(c.isHit(99))
        XCTAssertFalse(EmitterRatchetCfg().on, "a fresh emitter is off")
        XCTAssertEqual(EmitterRatchetCfg().patternMask, 0b0100_1001, "…at 8 / 3 / 0")
        XCTAssertEqual(EmitterRatchetCfg.defaultPatternMask, emitterRatchetPatternMask(steps: 8, hits: 3, offset: 0), "the render thread's literal default IS the page's pattern")
        XCTAssertEqual(EmitterRatchetCfg(EmitterRatchet()), EmitterRatchetCfg(), "the default document value and the inert default agree")
    }

    // MARK: - §1.2 / §1.3 — ranges, defaults, and STEPS dragging HITS and OFFSET down in the same write

    func testTheDefaultsAreTheFerrysAndEveryFieldClamps() {
        let d = EmitterRatchet()
        XCTAssertFalse(d.on); XCTAssertEqual(d.steps, 8); XCTAssertEqual(d.hits, 3); XCTAssertEqual(d.offset, 0); XCTAssertEqual(d.chance, 100); XCTAssertEqual(d.strikes, 3)
        let wild = EmitterRatchet(on: true, steps: 99, hits: 99, offset: 99, chance: 999, strikes: 99).normalized()
        XCTAssertEqual([wild.steps, wild.hits, wild.offset, wild.chance, wild.strikes], [16, 16, 15, 100, 4])
        let low = EmitterRatchet(on: true, steps: -3, hits: -3, offset: -3, chance: -9, strikes: 0).normalized()
        XCTAssertEqual([low.steps, low.hits, low.offset, low.chance, low.strikes], [2, 0, 0, 0, 2])
    }
    func testChanceSnapsToTheNearestFive() {
        for (raw, want) in [(52, 50), (53, 55), (0, 0), (100, 100), (97, 95), (98, 100), (-7, 0), (120, 100), (2, 0), (3, 5)] {
            XCTAssertEqual(EmitterRatchet(chance: raw).normalized().chance, want, "\(raw)")
        }
    }
    func testSettingStepsClampsHitsAndOffsetInTheSameWrite() {
        let r = EmitterRatchet(on: true, steps: 16, hits: 12, offset: 14, chance: 75, strikes: 4)
        let s = EmitterRatchetField.steps.setting(5, in: r)
        XCTAssertEqual([s.steps, s.hits, s.offset], [5, 5, 4], "HITS ≤ STEPS and OFFSET ≤ STEPS − 1, at once")
        XCTAssertEqual([s.chance, s.strikes], [75, 4]); XCTAssertTrue(s.on, "the other fields are untouched")
        XCTAssertEqual(EmitterRatchetField.steps.setting(2, in: r).hits, 2); XCTAssertEqual(EmitterRatchetField.steps.setting(2, in: r).offset, 1)
    }
    func testValueCellsClampAtTheEndsAndNeverWrap() {
        let r = EmitterRatchet(steps: 8, hits: 3, offset: 0, chance: 100, strikes: 4)
        XCTAssertEqual(EmitterRatchetField.strikes.setting(5, in: r).strikes, 4); XCTAssertEqual(EmitterRatchetField.strikes.setting(1, in: r).strikes, 2)
        XCTAssertEqual(EmitterRatchetField.chance.setting(105, in: r).chance, 100); XCTAssertEqual(EmitterRatchetField.chance.setting(-5, in: r).chance, 0)
        XCTAssertEqual(EmitterRatchetField.offset.setting(8, in: r).offset, 7, "OFFSET tops out at STEPS − 1"); XCTAssertEqual(EmitterRatchetField.offset.setting(-1, in: r).offset, 0)
        XCTAssertEqual(EmitterRatchetField.hits.setting(9, in: r).hits, 8, "HITS tops out at STEPS"); XCTAssertEqual(EmitterRatchetField.hits.setting(-1, in: r).hits, 0)
        XCTAssertEqual(EmitterRatchetField.steps.setting(17, in: r).steps, 16); XCTAssertEqual(EmitterRatchetField.steps.setting(1, in: r).steps, 2)
        XCTAssertEqual(EmitterRatchetField.allCases.map { $0.step }, [1, 1, 1, 5, 1], "one VoiceOver step: CHANCE moves in fives")
        XCTAssertEqual(EmitterRatchetField.allCases.map { $0.label }, ["STEPS", "HITS", "OFFSET", "CHANCE", "STRIKES"])
    }
    func testADoubleTapResetsTheCellToItsDefaultClampedBySteps() {
        let r = EmitterRatchet(on: true, steps: 2, hits: 1, offset: 1, chance: 40, strikes: 2)
        XCTAssertEqual(EmitterRatchetField.hits.reset(in: r).hits, 2, "HITS' default 3 is clamped by STEPS 2")
        XCTAssertEqual(EmitterRatchetField.offset.reset(in: r).offset, 0)
        XCTAssertEqual(EmitterRatchetField.chance.reset(in: r).chance, 100); XCTAssertEqual(EmitterRatchetField.strikes.reset(in: r).strikes, 3)
        let wide = EmitterRatchet(steps: 16, hits: 16, offset: 9)
        let s = EmitterRatchetField.steps.reset(in: wide)
        XCTAssertEqual([s.steps, s.hits, s.offset], [8, 8, 7], "resetting STEPS clamps the other two (§1.3)")
    }

    // MARK: - §1.4 / §1.5 / §1.6 — the document field (additive-Optional, fixed-size, tolerant)

    func testANewDocumentHasNoRatchetsAndEncodesNoKey() throws {
        let doc = PluginState.makeInit()
        XCTAssertNil(doc.euclideousEmitterRatchets); XCTAssertEqual(doc.euclideousEmitterRatchetsResolved, EmitterRatchetSet())
        XCTAssertTrue(doc.euclideousEmitterRatchetsResolved.asArray.allSatisfy { $0 == EmitterRatchet() && !$0.on })
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        XCTAssertNil(obj["euclideousEmitterRatchets"], "an untouched document writes nothing, so every existing document encodes as before")
    }
    func testADocumentWithoutTheFieldDecodesAsFourEmittersOffAndRoundTripsLosslessly() throws {
        var doc = PluginState.makeInit(); doc.euclideousKeyRoot = 5
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        obj.removeValue(forKey: "euclideousEmitterRatchets")
        let back = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.euclideousEmitterRatchets); XCTAssertEqual(back.euclideousEmitterRatchetsResolved, EmitterRatchetSet())
        XCTAssertEqual(back.euclideousKeyRoot, 5, "no migration, no factory reset — the rest of the document loads as it was")
        XCTAssertEqual(back, doc)
        XCTAssertEqual(try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(back)), back, "…and round-trips without loss")
    }
    func testAStoredSetRoundTripsAndEncodesAsAFourElementArray() throws {
        var doc = PluginState.makeInit()
        var set = EmitterRatchetSet()
        set[0] = EmitterRatchet(on: true, steps: 16, hits: 16, offset: 0, chance: 75, strikes: 4)
        set[2] = EmitterRatchet(on: true, steps: 5, hits: 2, offset: 3, chance: 5, strikes: 2)
        doc.euclideousEmitterRatchets = set
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.euclideousEmitterRatchetsResolved, set); XCTAssertEqual(back, doc)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((obj["euclideousEmitterRatchets"] as? [Any])?.count, 4, "fixed size: always four")
    }
    func testGarbageShortAndLongStoredValuesNeverFailTheLoad() throws {
        XCTAssertEqual(try decode(ratchetsJSON: "\"banana\"").euclideousEmitterRatchetsResolved, EmitterRatchetSet(), "not an array ⇒ the defaults")
        XCTAssertEqual(try decode(ratchetsJSON: "{\"a\":1}").euclideousEmitterRatchetsResolved, EmitterRatchetSet())
        let short = try decode(ratchetsJSON: "[{\"on\":true,\"steps\":12}]").euclideousEmitterRatchetsResolved
        XCTAssertTrue(short[0].on); XCTAssertEqual(short[0].steps, 12); XCTAssertEqual(short[1], EmitterRatchet(), "a short array leaves the rest at their defaults")
        let long = try decode(ratchetsJSON: "[{},{},{},{\"on\":true},{\"on\":true}]").euclideousEmitterRatchetsResolved
        XCTAssertTrue(long[3].on, "the fifth is dropped, the fourth kept"); XCTAssertEqual(long.asArray.count, 4)
        let clamped = try decode(ratchetsJSON: "[{\"on\":true,\"steps\":300,\"hits\":-4,\"offset\":99,\"chance\":52.5,\"strikes\":\"x\"}]").euclideousEmitterRatchetsResolved[0]
        XCTAssertEqual([clamped.steps, clamped.hits, clamped.offset, clamped.chance, clamped.strikes], [16, 0, 15, 55, 3], "out of range clamps, 52.5 rounds to 53 then snaps to 55, a string keeps its default")
        let bad = try decode(ratchetsJSON: "[{\"on\":\"yes\",\"steps\":null}]").euclideousEmitterRatchetsResolved[0]
        XCTAssertEqual(bad, EmitterRatchet(), "an unreadable key keeps its default")
    }
    func testEveryFactoryPresetCarriesNoRatchetsSoLoadingOneTurnsThemOff() {
        for (name, make) in EuclideousPresets.all { XCTAssertEqual(make().euclideousEmitterRatchetsResolved, EmitterRatchetSet(), "\(name): a preset without the field loads them all off") }
    }
    func testEveryPositionOfTheSetIsAddressableAndNormalised() {
        var s = EmitterRatchetSet()
        for i in 0..<4 { s[i] = EmitterRatchet(on: true, steps: 99, hits: 99, offset: 99, chance: 99, strikes: 99) }
        XCTAssertTrue(s.asArray.allSatisfy { $0.steps == 16 && $0.hits == 16 && $0.offset == 15 && $0.chance == 100 && $0.strikes == 4 }, "a write through the subscript is always normalised")
        XCTAssertFalse(s.isAllDefault); XCTAssertTrue(EmitterRatchetSet().isAllDefault)
        XCTAssertEqual(EmitterRatchetSet([EmitterRatchet(on: true)])[0].on, true); XCTAssertEqual(EmitterRatchetSet([EmitterRatchet(on: true)])[3], EmitterRatchet())
    }

    // MARK: - §1.5 — the snapshot (a page-level field: no MachineParams hop, and NOT the EuclidLine fresh-literal rebuild)

    private func composedState() -> PluginState {
        var st = PluginState.makeInit()
        st.machines.append(Machine(machineID: FourfoldCompose.machineID, type: .euclid))
        let input = FourfoldCompose.Input(lines: st.euclideousLinesResolved, riff: st.euclideousRiffResolved, riffs: st.riffsResolved, activeRiff: st.activeRiffResolved,
                                          soloMask: st.euclideousSoloMaskResolved, locks: st.euclideousLocksResolved, lockRevs: 0)
        st.scenes = [FourfoldCompose.scene(input)]
        return st
    }
    private func rowParams(_ st: PluginState) throws -> SnapParams {
        let box = SnapshotBuilder.build(from: st)
        return try XCTUnwrap(box.cells[Snap.euclideousRow].procs.first)
    }
    func testANonDefaultValueReachesTheEuclideousRowsSnapParamsAndNothingElse() throws {
        var st = composedState()
        XCTAssertEqual(try rowParams(st).emitterRatchets, EmitterRatchetSnap(), "untouched ⇒ the inert default")
        XCTAssertFalse(try rowParams(st).emitterRatchets.anyOn)
        var set = EmitterRatchetSet(); set[1] = EmitterRatchet(on: true, steps: 5, hits: 2, offset: 3, chance: 60, strikes: 2)
        st.euclideousEmitterRatchets = set
        let snap = try rowParams(st).emitterRatchets
        XCTAssertTrue(snap.anyOn); XCTAssertTrue(snap[1].on); XCTAssertFalse(snap[0].on)
        XCTAssertEqual([snap[1].steps, snap[1].hits, snap[1].offset, snap[1].chance, snap[1].strikes], [5, 2, 3, 60, 2])
        XCTAssertEqual(snap[1].patternMask, 0b00101, "the mask is built on the main thread, by the lane's own builder")
        XCTAssertEqual(snap[0], EmitterRatchetCfg()); XCTAssertEqual(snap[2], EmitterRatchetCfg())
        XCTAssertFalse(snap.countsSteps, "HITS counting is the default (and the only one in release)")
    }
    func testTheUndoProbesBoxDescriptionSeesTheRatchets() throws {
        var st = composedState()
        let none = try XCTUnwrap(SnapshotBuilder.build(from: st).euclideousProbeDescription)
        var set = EmitterRatchetSet(); set[0].on = true
        st.euclideousEmitterRatchets = set
        let on = try XCTUnwrap(SnapshotBuilder.build(from: st).euclideousProbeDescription)
        XCTAssertNotEqual(none, on, "a missed republish of the ratchets would otherwise go undetected")
        set[0].strikes = 4; st.euclideousEmitterRatchets = set
        XCTAssertNotEqual(on, try XCTUnwrap(SnapshotBuilder.build(from: st).euclideousProbeDescription))
        set[0].strikes = 3; st.euclideousEmitterRatchets = set
        XCTAssertEqual(on, try XCTUnwrap(SnapshotBuilder.build(from: st).euclideousProbeDescription), "the same document describes the same")
    }
    func testTheSnapshotIsPlainValueStorage() {
        XCTAssertTrue(MemoryLayout<EmitterRatchetSnap>.size > 0)
        var a = EmitterRatchetSnap(); var b = a
        b[2].on = true
        XCTAssertFalse(a[2].on, "a copy is independent: no shared heap buffer to race on")
        a[3].strikes = 2; XCTAssertEqual(b[3].strikes, 3)
    }

    // MARK: - §2.6 / §2.7 — the decision

    func testChance100AlwaysRatchetsWhereTheMaskHitsAndChance0Never() {
        let always = cfg(steps: 8, hits: 3, chance: 100), never = cfg(steps: 8, hits: 3, chance: 0)
        for v in Int64(0)..<400 {
            let a = emitterRatchetDecide(always, output: 0, v: v), n = emitterRatchetDecide(never, output: 0, v: v)
            XCTAssertEqual(a.index, Int(v % 8)); XCTAssertEqual(a.isHit, always.isHit(a.index))
            XCTAssertEqual(a.ratchets, a.isHit, "CHANCE 100 ratchets exactly where P is a hit")
            XCTAssertFalse(n.ratchets, "CHANCE 0 never ratchets"); XCTAssertEqual(n.missed, n.isHit)
            XCTAssertEqual(a.strikes, 3)
        }
    }
    func testAnOffEmitterNeverRatchetsAndNeverMisses() {
        let off = cfg(on: false, steps: 4, hits: 4, chance: 50)
        for v in Int64(0)..<64 {
            let d = emitterRatchetDecide(off, output: 2, v: v)
            XCTAssertTrue(d.isHit); XCTAssertFalse(d.ratchets); XCTAssertFalse(d.missed)
        }
    }
    func testChanceIsReplayExactAndRoughlyProportional() {
        let c = cfg(steps: 2, hits: 2, chance: 50)   // every step a hit: every roll counts
        var ratcheted = 0
        for v in Int64(0)..<2000 {
            let d1 = emitterRatchetDecide(c, output: 1, v: v), d2 = emitterRatchetDecide(c, output: 1, v: v)
            XCTAssertEqual(d1, d2, "replay-exact: the same count gives the same answer")
            XCTAssertEqual(d1.missed, !d1.ratchets)
            if d1.ratchets { ratcheted += 1 }
            let roll = emitterRatchetRoll(output: 1, v: v)
            XCTAssertTrue((0..<100).contains(roll)); XCTAssertEqual(d1.ratchets, roll < 50)
        }
        XCTAssertTrue((850...1150).contains(ratcheted), "about half at CHANCE 50 (got \(ratcheted) of 2000)")
        let c25 = cfg(steps: 2, hits: 2, chance: 25)
        let quarter = (Int64(0)..<2000).filter { emitterRatchetDecide(c25, output: 3, v: $0).ratchets }.count
        XCTAssertTrue((400...600).contains(quarter), "about a quarter at CHANCE 25 (got \(quarter))")
    }
    func testTheRollDependsOnTheOutputAndUsesItsOwnSalt() {
        let same = (Int64(0)..<200).filter { emitterRatchetRoll(output: 0, v: $0) == emitterRatchetRoll(output: 1, v: $0) }.count
        XCTAssertLessThan(same, 20, "each output rolls its own dice")
        XCTAssertEqual(emitterRatchetSalt, 0x454D_4954_5254_4348)
        XCTAssertNotEqual(emitterRatchetSalt, 0x4E4F_5445_5343_4841, "not the notes layer's CHANCE salt")
        XCTAssertNotEqual(emitterRatchetSalt, 0xA24B_AED4_963E_E407, "not the mask's CHANCE salt")
    }
    func testANegativeStepIndexStillLandsInRange() {
        let d = emitterRatchetDecide(cfg(steps: 8, hits: 3), output: 0, v: -3)
        XCTAssertEqual(d.index, 5)
    }

    // MARK: - §2.2 – §2.5 — counting (test 2, 4, 5 at the pure level)

    func testEveryFourthEmitterHitRatchetsAtTheIndexThePatternMarks() {   // §10 test 2: STEPS 4, HITS 1, OFFSET 0, CHANCE 100
        let a = cfg(steps: 4, hits: 1, offset: 0, chance: 100, strikes: 3)
        var counter = EmitterRatchetCounter()
        var ratcheted: [Int] = [], indices: [Int] = []
        for i in 0..<16 {
            let d = counter.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: Int64(i), sample: 100)
            indices.append(d.index); if d.ratchets { ratcheted.append(i) }
        }
        XCTAssertEqual(indices, (0..<16).map { $0 % 4 }, "the index is c mod STEPS, then c goes up by one")
        XCTAssertEqual(ratcheted, [0, 4, 8, 12], "exactly one emitter hit in every four, at the index P marks")
        XCTAssertEqual(counter.counts[0], 16); XCTAssertEqual(counter.counts[1], 0, "another output's counter is its own")
    }
    func testTwoLanesHittingTheSameOutputAtOneSampleCountOnceAndShareTheDecision() {
        let a = cfg(steps: 4, hits: 1, chance: 100)
        var counter = EmitterRatchetCounter()
        let first = counter.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: 7, sample: 512)    // lane 1
        let second = counter.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: 7, sample: 512)   // lane 2, the same sample
        XCTAssertEqual(first, second); XCTAssertEqual(counter.counts[0], 1, "one emitter hit")
        let later = counter.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: 7, sample: 640)    // a different sample is a new hit
        XCTAssertEqual(later.index, 1); XCTAssertEqual(counter.counts[0], 2)
        let nextWindow = counter.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: 8, sample: 640)   // …and so is the same sample number in the next window
        XCTAssertEqual(nextWindow.index, 2); XCTAssertEqual(counter.counts[0], 3)
        let otherOutput = counter.hit(cfg: a, output: 1, countsSteps: false, laneStep: 0, window: 8, sample: 640)
        XCTAssertEqual(otherOutput.index, 0, "the cache is per output"); XCTAssertEqual(counter.counts[1], 1)
    }
    func testTheCountOriginResetsEverythingAndEditsToTheConfigDoNot() {
        var counter = EmitterRatchetCounter()
        var a = cfg(steps: 4, hits: 1)
        for i in 0..<6 { _ = counter.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: Int64(i), sample: 0) }
        XCTAssertEqual(counter.counts[0], 6); XCTAssertEqual(counter.currentIndex(0), 1)
        a = cfg(steps: 6, hits: 2, offset: 1)   // editing STEPS / HITS / OFFSET is not an origin
        let d = counter.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: 6, sample: 0)
        XCTAssertEqual(d.index, 0, "the count carries on from 6: 6 mod 6"); XCTAssertEqual(counter.counts[0], 7)
        counter.reset()
        XCTAssertEqual(counter.counts[0], 0); XCTAssertNil(counter.currentIndex(0)); XCTAssertEqual(counter, EmitterRatchetCounter())
        let again = counter.hit(cfg: cfg(steps: 4, hits: 1), output: 0, countsSteps: false, laneStep: 0, window: 0, sample: 0)
        XCTAssertEqual(again.index, 0, "back to the first hit")
    }
    func testInStepsModeTheIndexFollowsTheLanesPatternStepAndTheFirstLanesStepWinsASimultaneousHit() {   // §10 test 5
        let a = cfg(steps: 8, hits: 3)
        var counter = EmitterRatchetCounter()
        let d1 = counter.hit(cfg: a, output: 2, countsSteps: true, laneStep: 11, window: 0, sample: 10)
        XCTAssertEqual(d1.index, 3, "11 mod 8"); XCTAssertEqual(d1.ratchets, a.isHit(3))
        let sim = counter.hit(cfg: a, output: 2, countsSteps: true, laneStep: 6, window: 0, sample: 10)   // a second lane, the same sample
        XCTAssertEqual(sim, d1, "the first lane's s decides")
        let d2 = counter.hit(cfg: a, output: 2, countsSteps: true, laneStep: 24, window: 1, sample: 10)
        XCTAssertEqual(d2.index, 0); XCTAssertTrue(d2.ratchets, "step 24 mod 8 = 0 is a hit")
        // the roll is seeded with s, not c_X, in STEPS mode: two counters that disagree on c_X agree on the decision
        var c2 = EmitterRatchetCounter(); _ = c2.hit(cfg: a, output: 2, countsSteps: false, laneStep: 0, window: 0, sample: 0)
        let b = cfg(steps: 2, hits: 2, chance: 50)
        let x = c2.hit(cfg: b, output: 2, countsSteps: true, laneStep: 37, window: 5, sample: 1)
        var c3 = EmitterRatchetCounter()
        XCTAssertEqual(x, c3.hit(cfg: b, output: 2, countsSteps: true, laneStep: 37, window: 5, sample: 1), "STEPS mode does not read c_X")
    }
    func testThePublishedIndicesArePackedOneBytePerOutput() {
        var counter = EmitterRatchetCounter()
        XCTAssertEqual(counter.indexPacked, 0xFFFF_FFFF)
        for x in 0..<4 { XCTAssertNil(counter.currentIndex(x)) }
        _ = counter.hit(cfg: cfg(steps: 16), output: 2, countsSteps: true, laneStep: 13, window: 0, sample: 0)
        XCTAssertEqual(counter.currentIndex(2), 13); XCTAssertNil(counter.currentIndex(0)); XCTAssertNil(counter.currentIndex(3))
        _ = counter.hit(cfg: cfg(steps: 16), output: 0, countsSteps: true, laneStep: 15, window: 1, sample: 0)
        XCTAssertEqual(counter.currentIndex(0), 15); XCTAssertEqual(counter.currentIndex(2), 13)
    }
    func testACounterIsFixedSizeValueStorage() {
        var a = EmitterRatchetCounter()
        _ = a.hit(cfg: cfg(), output: 1, countsSteps: false, laneStep: 0, window: 0, sample: 0)
        var b = a
        _ = b.hit(cfg: cfg(), output: 1, countsSteps: false, laneStep: 0, window: 1, sample: 0)
        XCTAssertEqual(a.counts[1], 1); XCTAssertEqual(b.counts[1], 2)
    }

    // MARK: - §4.1 — the tab strip

    func testRatchIsAFixed80AndTheOtherTabsShareTheRest() {
        let w = euclideousSeqTabWidths(tabs: [.lanes, .fx, .ratch], contentWidth: 364.67)
        XCTAssertEqual(w[2], 80); XCTAssertEqual(w[0], w[1], accuracy: 1e-9)
        XCTAssertEqual(w[0], (364.67 - 8 - 80) / 2, accuracy: 1e-9, "LANES and FX share what is left, sp4 apart")
        XCTAssertEqual(w.reduce(0, +) + 8, 364.67, accuracy: 1e-9, "the strip fills the content width")
        XCTAssertEqual(euclideousSeqTabWidths(tabs: [.lanes, .fx], contentWidth: 401), [198.5, 198.5], "without RATCH it is the old equal split")
        XCTAssertEqual(euclideousSeqTabWidths(tabs: [], contentWidth: 100), [])
        XCTAssertEqual(euclideousSeqTabWidth(count: 2, contentWidth: 401), 198.5, "the old function is kept")
        XCTAssertEqual(EuclideousSeqTab.ratch.rawValue, 4); XCTAssertEqual(EuclideousSeqTab.ratch.label, "RATCH"); XCTAssertEqual(emitterRatchetTabAccessibilityLabel(), "Ratchet")
        XCTAssertEqual(EuclideousSeqTab.default, .lanes, "the panel still opens on LANES")
    }

    // MARK: - §4.2–§4.8 — the layout

    func testLandscapeCardsAreTheFerrysNumbers() {
        // the ferry's frame: panel 410 × 303 → tab body 394 × 263 (the panel less 8 + 20 + 4 above and 8 below, 8 each side)
        let l = emitterRatchetLayout(bodySize: CGSize(width: 394, height: 263), portrait: false)
        XCTAssertEqual(l.cards.map { $0.minY + 32 }, [35, 101, 167, 233], "cards at panel y 35 / 101 / 167 / 233 (the body starts at panel y 32)")
        XCTAssertTrue(l.cards.allSatisfy { $0.width == 394 && $0.height == 60 && $0.minX == 0 }, "x 8 of the panel, 394 wide, 60 tall")
        XCTAssertEqual(l.cards.last!.maxY + 32, 293, "the last card ends at 293")
        XCTAssertEqual(l.toggle, CGRect(x: 0, y: 4, width: 44, height: 52), "the toggle target: 44 × 52 at the card's left edge")
        XCTAssertEqual(l.strip, CGRect(x: 50, y: 4, width: 336, height: 20), "the right column is 336 wide, the strip 20 tall")
        XCTAssertEqual(l.cells.count, 5); XCTAssertEqual(l.cells[0].minY, 28, "the readout row starts 4 below the strip"); XCTAssertEqual(l.cells[0].height, 28)
        XCTAssertEqual(l.cells[0].width, 336.0 / 5, accuracy: 1e-9); XCTAssertEqual(l.cells[4].maxX, 386, accuracy: 1e-9)
        XCTAssertEqual(l.slots.count, 16)
        XCTAssertEqual(l.slots[0].width, (336.0 - 30) / 16, accuracy: 1e-9, "about 19.1 wide"); XCTAssertEqual(l.slots[1].minX - l.slots[0].maxX, 2, accuracy: 1e-9)
        XCTAssertEqual(l.slots[15].maxX, 386, accuracy: 1e-9)
        XCTAssertFalse(l.belowFloor)
    }
    func testTheRealPanelScalesTheWidthAndKeepsEverythingElse() {
        // the 1190 × 726 reference: the panel is 380.67 × 319 → body 364.67 × 279
        let l = emitterRatchetLayout(bodySize: CGSize(width: 364.67, height: 279), portrait: false)
        XCTAssertEqual(l.cardHeight, 60); XCTAssertEqual(l.cards[3].maxY + 32, 293); XCTAssertEqual(l.strip.width, 364.67 - 58, accuracy: 1e-9)
        XCTAssertEqual(l.slots[0].width, (364.67 - 58 - 30) / 16, accuracy: 1e-9)
        XCTAssertEqual(l.cells[0].height, 28)
        XCTAssertFalse(l.belowFloor)
        // iPad mini 6 landscape: panel 361.67 × 304.5 → body 345.67 × 264.5 — the four cards still fit, with 3.5 pt to spare below the last
        let mini = emitterRatchetLayout(bodySize: CGSize(width: 345.67, height: 264.5), portrait: false)
        XCTAssertEqual(mini.cardHeight, 60); XCTAssertLessThanOrEqual(mini.cards[3].maxY, 264.5); XCTAssertFalse(mini.belowFloor)
    }
    func testPortraitCardsShareTheHeightEquallyAndTheReadoutTakesTheRest() {
        // 814 × 1102: the panel is 387 × 319.67 → body 371 × 279.67; the four cards share the height (3 above, 6 apart)
        let p = emitterRatchetLayout(bodySize: CGSize(width: 371, height: 279.67), portrait: true)
        let h = (279.67 - 3 - 18) / 4
        XCTAssertEqual(p.cardHeight, h, accuracy: 1e-9); XCTAssertGreaterThan(h, 60)
        XCTAssertEqual(p.cards[1].minY - p.cards[0].maxY, 6, accuracy: 1e-9); XCTAssertEqual(p.cards[3].maxY, 279.67, accuracy: 1e-9)
        XCTAssertEqual(p.strip.height, 20, "the strip stays 20"); XCTAssertEqual(p.cells[0].height, h - 8 - 24, accuracy: 1e-9, "the readout row takes the rest"); XCTAssertGreaterThanOrEqual(p.cells[0].height, 24)
        XCTAssertFalse(p.belowFloor)
        // every full-screen iPad frame computed in the ferry's audit keeps its cards at 52 or more
        for body in [CGSize(width: 352 - 16, height: 330 - 40), CGSize(width: 385 - 16, height: 312.3 - 40), CGSize(width: 361.67 - 16, height: 304.5 - 40)] {
            XCTAssertFalse(emitterRatchetLayout(bodySize: body, portrait: true).belowFloor, "\(body)")
            XCTAssertFalse(emitterRatchetLayout(bodySize: body, portrait: false).belowFloor, "\(body)")
        }
    }
    func testACardUnder52IsReportedNotClamped() {
        // a Stage-Manager window at the scale-to-fit minimum: panel ≈ 172 tall → body ≈ 132
        let small = emitterRatchetLayout(bodySize: CGSize(width: 300, height: 132), portrait: false)
        XCTAssertTrue(small.belowFloor); XCTAssertLessThan(small.cardHeight, 52); XCTAssertGreaterThan(small.cardHeight, 0, "drawn at the formula's height, listed — never shrunk to nothing")
        XCTAssertGreaterThanOrEqual(small.cells[0].height, 24, "the readout row never goes under 24")
        XCTAssertTrue(euclideousPageFloors(box: CGSize(width: 380, height: 172)).contains(.ratchRows))
        XCTAssertFalse(euclideousPageFloors(box: CGSize(width: 380.67, height: 319)).contains(.ratchRows))
        XCTAssertFalse(euclideousPageFloors(box: CGSize(width: 387, height: 319.67)).contains(.ratchRows))
    }
    func testStrikeBarsAreCentredTwoWideOneApartAndTheRestDotTwoByTwo() {
        let slot = CGRect(x: 100, y: 4, width: 19.125, height: 20)
        for n in 2...4 {
            let bars = emitterRatchetBarRects(in: slot, strikes: n)
            XCTAssertEqual(bars.count, n); XCTAssertTrue(bars.allSatisfy { $0.width == 2 })
            XCTAssertEqual(bars.map { $0.height }, Array([14, 12, 10, 8].prefix(n)).map { CGFloat($0) }, "14, 12, 10, 8 in strike order")
            for i in 1..<n { XCTAssertEqual(bars[i].minX - bars[i - 1].maxX, 1, accuracy: 1e-9, "1 apart") }
            XCTAssertEqual((bars.first!.minX + bars.last!.maxX) / 2, slot.midX, accuracy: 1e-9, "centred across")
            XCTAssertTrue(bars.allSatisfy { abs($0.midY - slot.midY) < 1e-9 }, "centred down")
            XCTAssertTrue(bars.allSatisfy { slot.contains($0) }, "nothing overlaps or clips at 16 / 16 / ×4 (n = \(n))")
        }
        XCTAssertEqual(emitterRatchetRestDot(in: slot), CGRect(x: slot.midX - 1, y: slot.midY - 1, width: 2, height: 2))
        XCTAssertEqual(emitterRatchetBarAlpha(chance: 100), 1); XCTAssertEqual(emitterRatchetBarAlpha(chance: 0), 0.5); XCTAssertEqual(emitterRatchetBarAlpha(chance: 50), 0.75, accuracy: 1e-12)
        // at the narrowest slot the four bars (11 pt) still fit
        let narrow = emitterRatchetLayout(bodySize: CGSize(width: 336 - 16, height: 264), portrait: true).slots[0]
        XCTAssertGreaterThan(narrow.width, 11)
    }

    // MARK: - §4.6 / §4.7 / §6.2 — the cells

    func testTheValueTextBarShareAndDragFollowTheFerry() {
        var r = EmitterRatchet(on: true, steps: 8, hits: 3, offset: 0, chance: 75, strikes: 3)
        XCTAssertEqual(EmitterRatchetField.allCases.map { emitterRatchetValueText($0, r) }, ["8", "3", "0", "75%", "\u{00D7}3"])
        r.offset = 2; XCTAssertEqual(emitterRatchetValueText(.offset, r), "+2")
        // the bar: the value's share of its range, never under 6 %
        XCTAssertEqual(emitterRatchetBarShare(.steps, EmitterRatchet(steps: 16)), 1); XCTAssertEqual(emitterRatchetBarShare(.steps, EmitterRatchet(steps: 2)), 0.06, "the minimum")
        XCTAssertEqual(emitterRatchetBarShare(.chance, EmitterRatchet(chance: 50)), 0.5)
        XCTAssertEqual(emitterRatchetBarShare(.strikes, EmitterRatchet(strikes: 3)), 0.5); XCTAssertEqual(emitterRatchetBarShare(.hits, EmitterRatchet(steps: 8, hits: 8)), 1)
        XCTAssertEqual(emitterRatchetBarShare(.hits, EmitterRatchet(steps: 8, hits: 0)), 0.06); XCTAssertEqual(emitterRatchetBarShare(.offset, EmitterRatchet(steps: 8, offset: 7)), 1)
        // drag: up raises, down lowers; STEPS / HITS / OFFSET 1 per 10 pt, CHANCE 5 per 3 pt, STRIKES 1 per 18 pt; clamps, never wraps
        let base = EmitterRatchet(on: true, steps: 8, hits: 3, offset: 3, chance: 50, strikes: 3)
        XCTAssertEqual(emitterRatchetDragActivation, 6)
        XCTAssertEqual(emitterRatchetDragValue(.steps, start: base, travelUp: 25).steps, 10, "2 steps in 25 pt")
        XCTAssertEqual(emitterRatchetDragValue(.steps, start: base, travelUp: -25).steps, 6)
        XCTAssertEqual(emitterRatchetDragValue(.steps, start: base, travelUp: 9).steps, 8, "under 10 pt nothing has moved yet")
        XCTAssertEqual(emitterRatchetDragValue(.chance, start: base, travelUp: 7).chance, 60, "7 pt = 2 steps of 5")
        XCTAssertEqual(emitterRatchetDragValue(.chance, start: base, travelUp: -300).chance, 0); XCTAssertEqual(emitterRatchetDragValue(.chance, start: base, travelUp: 300).chance, 100)
        XCTAssertEqual(emitterRatchetDragValue(.strikes, start: base, travelUp: 17).strikes, 3); XCTAssertEqual(emitterRatchetDragValue(.strikes, start: base, travelUp: 18).strikes, 4)
        XCTAssertEqual(emitterRatchetDragValue(.strikes, start: base, travelUp: 60).strikes, 4, "clamped at the top, never wrapping to 2")
        XCTAssertEqual(emitterRatchetDragValue(.hits, start: base, travelUp: 100).hits, 8, "HITS tops out at STEPS")
        XCTAssertEqual(emitterRatchetDragValue(.offset, start: base, travelUp: 100).offset, 7); XCTAssertEqual(emitterRatchetDragValue(.offset, start: base, travelUp: -100).offset, 0)
        XCTAssertEqual(emitterRatchetDragValue(.steps, start: base, travelUp: -100).hits, 2, "dragging STEPS down drags HITS with it (2 steps: HITS ≤ 2, OFFSET ≤ 1)")
        XCTAssertEqual(emitterRatchetDragValue(.steps, start: base, travelUp: -100).offset, 1)
    }

    // MARK: - §8 — VoiceOver

    func testVoiceOverWordsAreTheFerrys() {
        let r = EmitterRatchet(on: true, steps: 8, hits: 3, offset: 0, chance: 75, strikes: 3)
        XCTAssertEqual(emitterRatchetToggleLabel(output: 0), "Ratchet on emitter A"); XCTAssertEqual(emitterRatchetToggleLabel(output: 3), "Ratchet on emitter D")
        XCTAssertEqual(emitterRatchetToggleValue(on: true), "on"); XCTAssertEqual(emitterRatchetToggleValue(on: false), "off")
        XCTAssertEqual(emitterRatchetStripLabel(output: 0, r, counts: nil), "Emitter A pattern, 3 of 8, offset 0, 3 strikes")
        XCTAssertEqual(emitterRatchetStripLabel(output: 1, r, counts: "hits"), "Emitter B pattern, 3 of 8 hits, offset 0, 3 strikes", "a dev build says what it counts")
        XCTAssertEqual(emitterRatchetStripLabel(output: 2, r, counts: "steps"), "Emitter C pattern, 3 of 8 steps, offset 0, 3 strikes")
        XCTAssertEqual(EmitterRatchetField.allCases.map { emitterRatchetCellLabel(output: 0, $0, r) },
                       ["Emitter A steps 8", "Emitter A hits 3", "Emitter A offset 0", "Emitter A chance 75 percent", "Emitter A strikes 3"])
        var o = r; o.offset = 2
        XCTAssertEqual(emitterRatchetCellLabel(output: 0, .offset, o), "Emitter A offset plus 2")
    }

    // MARK: - §5.3 / §5.4 — the flare

    func testTheFlareIsTheLowestLanesRatchetOrMissAndFadesOnThePulseTimingAndIsGoneAfterAndWhenPulseIsOff() {
        func strike(at: Double, masks: UInt8, vel: UInt8 = 100) -> EuclideousPulseStrike {
            var s = EuclideousPulseStrike(onsetBeat: 0, onsetAt: at, riffVel: vel, notesVel: 0); s.emitMasks = masks; return s
        }
        let none: [[EuclideousPulseStrike]] = [[], [], [], []]
        XCTAssertNil(emitterRatchetFlare(output: 0, strikes: none, now: 1, scale: 1))
        // lane 2 (index 1) ratcheted output A at t = 10 → RATCHED, decaying with τ 0.16 s
        let one: [[EuclideousPulseStrike]] = [[], [strike(at: 10, masks: 0b0001)], [], []]
        let f0 = emitterRatchetFlare(output: 0, strikes: one, now: 10, scale: 1)
        XCTAssertEqual(f0?.lane, 1); XCTAssertEqual(f0?.ratcheted, true); XCTAssertEqual(f0?.f ?? 0, euclideousPulseEnvelopes(velocity: 100, seconds: 0, scale: 1).f, accuracy: 1e-12)
        let f1 = emitterRatchetFlare(output: 0, strikes: one, now: 10.16, scale: 1)
        XCTAssertEqual(f1?.f ?? 0, euclideousPulseEnvelopes(velocity: 100, seconds: 0.16, scale: 1).f, accuracy: 1e-12); XCTAssertLessThan(f1!.f, f0!.f)
        XCTAssertNil(emitterRatchetFlare(output: 0, strikes: one, now: 12, scale: 1), "gone after the 1.5 s afterglow")
        XCTAssertNil(emitterRatchetFlare(output: 0, strikes: one, now: 9.9, scale: 1), "a strike that has not happened yet draws nothing")
        XCTAssertNil(emitterRatchetFlare(output: 1, strikes: one, now: 10, scale: 1), "another output's bit")
        XCTAssertNil(emitterRatchetFlare(output: 0, strikes: one, now: 10, scale: 0), "PULSE off: no flare")
        // MISSED is the high nibble
        let miss: [[EuclideousPulseStrike]] = [[strike(at: 5, masks: 0b0010_0000)], [], [], []]
        let m = emitterRatchetFlare(output: 1, strikes: miss, now: 5.05, scale: 1)
        XCTAssertEqual(m?.ratcheted, false); XCTAssertEqual(m?.lane, 0)
        // several lanes at once: the lowest-numbered lane's colour; a clearly later strike wins
        let both: [[EuclideousPulseStrike]] = [[], [strike(at: 20.001, masks: 0b0001)], [strike(at: 20, masks: 0b0001)], []]
        XCTAssertEqual(emitterRatchetFlare(output: 0, strikes: both, now: 20.01, scale: 1)?.lane, 1)
        let later: [[EuclideousPulseStrike]] = [[strike(at: 20, masks: 0b0001)], [], [strike(at: 20.3, masks: 0b0001)], []]
        XCTAssertEqual(emitterRatchetFlare(output: 0, strikes: later, now: 20.31, scale: 1)?.lane, 2, "the most recent strike")
    }

    // MARK: - §7 / §10 test 12 — FX COUNTS (dev builds only)

    func testFxCountsIsStoredLikeClashesDefaultsToHitsAndIsAlwaysHitsInRelease() throws {
        var st = PluginState.makeInit()
        XCTAssertNil(st.euclideousFxCounts); XCTAssertEqual(st.fxCountsResolved, .hits, "nil ⇒ HITS")
        st.euclideousFxCounts = .steps
        #if DEBUG
        XCTAssertEqual(st.fxCountsResolved, .steps, "a dev build honours the stored value")
        #else
        XCTAssertEqual(st.fxCountsResolved, .hits, "a release build always counts HITS, whatever is stored")
        #endif
        // it is stored where CLASHES is — in the encoded document — and an absent key decodes to nil
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(st))
        XCTAssertEqual(back.euclideousFxCounts, .steps); XCTAssertEqual(back, st)
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PluginState.makeInit())) as! [String: Any]
        XCTAssertNil(obj["euclideousFxCounts"], "an untouched document writes no key")
        // adversarial review: a stored value that is not HITS or STEPS must NEVER fail the document load (the AU's `fullState` and the preset store decode with `try?`, so a throw silently drops the whole session) — it reads as HITS
        for garbage: Any in ["garbage", "steps", 7, true, ["x": 1], NSNull()] {
            obj["euclideousFxCounts"] = garbage
            let doc = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
            XCTAssertTrue(doc.euclideousFxCounts == nil || doc.euclideousFxCounts == .hits, "\(garbage) loads as HITS (or nothing), never as STEPS and never as a failure")
        }
        obj["euclideousFxCounts"] = "STEPS"
        XCTAssertEqual(try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj)).euclideousFxCounts, .steps)
    }
    func testTheSnapshotCarriesTheCountsFlagOnlyWhenTheModeIsSteps() throws {
        var st = composedState()
        XCTAssertFalse(try rowParams(st).emitterRatchets.countsSteps)
        st.euclideousFxCounts = .steps
        #if DEBUG
        XCTAssertTrue(try rowParams(st).emitterRatchets.countsSteps)
        #else
        XCTAssertFalse(try rowParams(st).emitterRatchets.countsSteps)
        #endif
    }
    /// §7.1 / §10 test 12: the FX COUNTS block is `#if DEBUG` on the settings sheet — a release build has no such control (and says nothing about what it counts). A source tripwire, like the repo's others.
    func testTheFxCountsBlockSitsInsideADebugOnlyRegionOfTheSettingsSheet() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("UI/EuclideousSettingsSheet.swift")
        let src = try String(contentsOf: url, encoding: .utf8)
        let r = try XCTUnwrap(src.range(of: "block(name: \"FX COUNTS\")"))
        let before = String(src[..<r.lowerBound])
        let open = try XCTUnwrap(before.range(of: "#if DEBUG", options: .backwards))
        if let close = before.range(of: "#endif", options: .backwards) { XCTAssertLessThan(close.lowerBound, open.lowerBound, "the nearest preceding conditional is an open `#if DEBUG`") }
        let after = String(src[r.upperBound...])
        XCTAssertNotNil(after.range(of: "#endif")); XCTAssertTrue(after.prefix(1200).contains("#endif"), "…and it closes right after the block")
        XCTAssertFalse(src.contains("description: \"FX COUNTS"), "no description line (§7.2)")
    }

    // ADVERSARIAL REVIEW (2026-10-28): the same-sample cache used to hold ONE (window, sample) per output, so a lane that hit an output more than once in a window evicted the entry the NEXT lane needed.
    func testSeveralHitsPerWindowFromTwoLanesStillShareTheirDecisionsPerSample() {
        var c = EmitterRatchetCounter(); let a = cfg(steps: 4, hits: 1, chance: 50)
        // lane 1 plays its whole window first: hits at samples 100, 300 and 500 …
        let lane1 = [100, 300, 500].map { c.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: 9, sample: Int64($0)) }
        XCTAssertEqual(c.counts[0], 3)
        // … then lane 2 plays the same window, hitting the same samples (and one of its own): the shared ones count nothing and answer as lane 1's did
        let lane2 = [100, 300, 500].map { c.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: 9, sample: Int64($0)) }
        XCTAssertEqual(lane2, lane1, "each of lane 2's hits shares the decision of lane 1's hit at that sample")
        XCTAssertEqual(c.counts[0], 3, "…and none of them counts again")
        let own = c.hit(cfg: a, output: 0, countsSteps: false, laneStep: 0, window: 9, sample: 400)
        XCTAssertEqual(c.counts[0], 4); XCTAssertEqual(own.index, 3, "a sample no earlier lane hit is a hit of its own")
        // the next window starts afresh, and a window with more hits than the cache holds still counts every one
        var big = EmitterRatchetCounter()
        for i in 0..<(EmitterRatchetCounter.cacheCapacity + 8) { _ = big.hit(cfg: a, output: 2, countsSteps: false, laneStep: 0, window: 1, sample: Int64(i) * 10) }
        XCTAssertEqual(big.counts[2], Int64(EmitterRatchetCounter.cacheCapacity + 8), "overflowing the cache never drops a count")
        let fresh = big.hit(cfg: a, output: 2, countsSteps: false, laneStep: 0, window: 2, sample: 0)
        XCTAssertEqual(big.counts[2], Int64(EmitterRatchetCounter.cacheCapacity + 9)); XCTAssertEqual(fresh.index, (EmitterRatchetCounter.cacheCapacity + 8) % 4)
    }

    // ADVERSARIAL REVIEW (2026-10-28)
    func testExtremeStoredNumbersNeverTrapTheDecode() throws {
        // `Int(Double(chance) / 5 …) * 5` overflowed for a stored Int.max / Int.min and killed the process at load
        for v in [Int.max, Int.min, Int.max - 3, Int.min + 3, 1 << 62, -(1 << 62), 1_000_000_007, -1_000_000_007] {
            let r = EmitterRatchet(on: true, steps: v, hits: v, offset: v, chance: v, strikes: v).normalized()
            XCTAssertTrue((2...16).contains(r.steps) && (0...16).contains(r.hits) && (0..<16).contains(r.offset) && (0...100).contains(r.chance) && r.chance % 5 == 0 && (2...4).contains(r.strikes), "\(v)")
        }
        let json = "[{\"on\":true,\"steps\":9223372036854775807,\"hits\":-9223372036854775808,\"offset\":9223372036854775807,\"chance\":9223372036854775807,\"strikes\":-9223372036854775808}]"
        let r = try decode(ratchetsJSON: json).euclideousEmitterRatchetsResolved[0]
        XCTAssertEqual([r.steps, r.hits, r.offset, r.chance, r.strikes], [16, 0, 15, 100, 2])
        let f = EmitterRatchetField.chance
        XCTAssertEqual(f.setting(Int.max, in: EmitterRatchet()).chance, 100); XCTAssertEqual(f.setting(Int.min, in: EmitterRatchet()).chance, 0)
    }
    /// UNDO-6 for this funnel: a drag that wandered off and came back is not a step — the page drops the checkpoint's step when the live state equals what it holds.
    func testADragThatReturnsToItsStartIsNotAnUndoStep() {
        var undo = UndoStack<EuclideousUndoSnapshot>()
        func snap(_ s: EmitterRatchetSet) -> EuclideousUndoSnapshot {
            var x = EuclideousUndoSnapshot(lines: [], riff: EuclideousRiff(), resetSpanBars: 0, keyRoot: 0, keyType: .major, chordSets: [], activeChordSet: 0, noteSource: .midi, riffs: [], activeRiff: 0,
                                           lanesSeq: EuclideousLanesSeq(), riffsSeq: EuclideousRiffsSeq())
            x.emitterRatchets = s
            return x
        }
        var set = EmitterRatchetSet()
        undo.record(snap(set), coalesceKey: nil)                        // the drag's first change takes its checkpoint of the state BEFORE it …
        set[0] = EmitterRatchetField.strikes.setting(4, in: set[0])      // … writes 3 → 4, then wanders back to 3 …
        set[0] = EmitterRatchetField.strikes.setting(3, in: set[0])
        XCTAssertTrue(undo.dropLastStepIfUnchanged(current: snap(set)), "it ended where it began: its step is dropped")
        XCTAssertTrue(undo.past.isEmpty)
        undo.record(snap(set), coalesceKey: nil); set[0] = EmitterRatchetField.strikes.setting(4, in: set[0])
        XCTAssertFalse(undo.dropLastStepIfUnchanged(current: snap(set)), "a drag that really changed something keeps its step")
        XCTAssertEqual(undo.past.count, 1)
    }
}
