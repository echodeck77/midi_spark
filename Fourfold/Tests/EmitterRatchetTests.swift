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
}
