//  EmitterVelocityTests.swift — VELOCITY tab (2026-11-03): the model (clamp / Codable / the document field), the five value cells, the pattern decision and the per-output counter. The Router's behaviour is in `EmitterRatchetRouterTests`.
//  The document field is `PluginState.euclideousEmitterVelocities: EmitterVelocitySet?` — four fixed-size accents, one per output A–D, nil ⇒ all defaults (off, both offsets 0).

import XCTest

final class EmitterVelocityTests: XCTestCase {

    private func decode(velJSON: String) throws -> PluginState {
        let doc = PluginState(machines: [], scenes: [SceneState.empty()])
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        obj["euclideousEmitterVelocities"] = try JSONSerialization.jsonObject(with: Data(velJSON.utf8), options: .fragmentsAllowed)
        return try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
    }

    // MARK: - the model: defaults, clamp, the one-write STEPS clamp

    func testDefaultsAndClamp() {
        let d = EmitterVelocity()
        XCTAssertFalse(d.on); XCTAssertEqual([d.steps, d.hits, d.offset, d.hitVel, d.missVel], [8, 3, 0, 0, 0]); XCTAssertTrue(d.isDefault)
        let wild = EmitterVelocity(on: true, steps: 99, hits: 99, offset: 99, hitVel: 999, missVel: 999).normalized()
        XCTAssertEqual([wild.steps, wild.hits, wild.offset, wild.hitVel, wild.missVel], [16, 16, 15, 63, 63])
        let low = EmitterVelocity(on: true, steps: -3, hits: -3, offset: -3, hitVel: -999, missVel: -999).normalized()
        XCTAssertEqual([low.steps, low.hits, low.offset, low.hitVel, low.missVel], [2, 0, 0, -63, -63])
    }
    func testSettingStepsClampsHitsAndOffsetInTheSameWrite() {
        let v = EmitterVelocity(on: true, steps: 16, hits: 12, offset: 14, hitVel: 20, missVel: -10)
        let s = EmitterVelocityField.steps.setting(5, in: v)
        XCTAssertEqual([s.steps, s.hits, s.offset], [5, 5, 4], "HITS ≤ STEPS and OFFSET ≤ STEPS − 1, at once")
        XCTAssertEqual([s.hitVel, s.missVel], [20, -10], "the offsets are untouched")
    }
    func testFieldRangesStepsDefaultsAndBipolar() {
        XCTAssertEqual(EmitterVelocityField.allCases.map { $0.label }, ["STEPS", "HITS", "OFFSET", "HIT VEL", "MISS VEL"])
        XCTAssertEqual(EmitterVelocityField.allCases.map { $0.defaultValue }, [8, 3, 0, 0, 0])
        XCTAssertEqual(EmitterVelocityField.allCases.map { $0.step }, [1, 1, 1, 5, 5], "velocity moves in fives, the pattern by one")
        XCTAssertEqual(EmitterVelocityField.allCases.map { $0.bipolar }, [false, false, false, true, true])
        let v = EmitterVelocity(steps: 8)
        XCTAssertEqual(EmitterVelocityField.hitVel.range(in: v), -63...63); XCTAssertEqual(EmitterVelocityField.missVel.range(in: v), -63...63)
        XCTAssertEqual(EmitterVelocityField.hits.range(in: v), 0...8); XCTAssertEqual(EmitterVelocityField.offset.range(in: v), 0...7)
        XCTAssertEqual(EmitterVelocityField.hitVel.setting(80, in: v).hitVel, 63); XCTAssertEqual(EmitterVelocityField.missVel.setting(-80, in: v).missVel, -63)
        XCTAssertEqual(EmitterVelocityField.hitVel.reset(in: EmitterVelocity(hitVel: 40)).hitVel, 0, "a double tap resets to 0")
    }

    // MARK: - the pattern decision (Cfg.offsetAt)

    func testTheCfgPicksHitVelOnAPatternHitAndMissVelOnARest() {
        let cfg = EmitterVelocityCfg(EmitterVelocity(on: true, steps: 8, hits: 3, offset: 0, hitVel: 20, missVel: -10))
        XCTAssertEqual(cfg.patternMask, 0b0100_1001, "8/3/0 is the ratchet's pattern — the shared builder")
        XCTAssertEqual(cfg.offsetAt(0), 20); XCTAssertEqual(cfg.offsetAt(3), 20); XCTAssertEqual(cfg.offsetAt(6), 20, "the three hits get HIT VEL")
        XCTAssertEqual(cfg.offsetAt(1), -10); XCTAssertEqual(cfg.offsetAt(2), -10); XCTAssertEqual(cfg.offsetAt(7), -10, "the rests get MISS VEL")
        XCTAssertEqual(EmitterVelocityCfg().offsetAt(0), 0, "a fresh accent adds nothing"); XCTAssertEqual(EmitterVelocityCfg().offsetAt(1), 0)
    }

    // MARK: - the counter (index per output, same-sample sharing, reset)

    func testTheIndexAdvancesPerHitModStepsAndIsPerOutput() {
        var counter = EmitterVelocityCounter()
        var indices: [Int] = []
        for i in 0..<10 { indices.append(counter.hit(steps: 4, output: 0, window: Int64(i), sample: 0)) }
        XCTAssertEqual(indices, (0..<10).map { $0 % 4 }, "the index is count mod STEPS, then the count goes up")
        XCTAssertEqual(counter.counts[0], 10); XCTAssertEqual(counter.counts[1], 0, "another output's count is its own")
        XCTAssertEqual(counter.currentIndex(0), 1); XCTAssertNil(counter.currentIndex(2))
    }
    func testTwoLanesOnOneOutputAtOneSampleShareTheIndexAndCountOnce() {
        var counter = EmitterVelocityCounter()
        let a = counter.hit(steps: 8, output: 2, window: 5, sample: 512)
        let b = counter.hit(steps: 8, output: 2, window: 5, sample: 512)   // a second lane, the same sample
        XCTAssertEqual(a, b, "the first lane's index decides"); XCTAssertEqual(counter.counts[2], 1, "one count")
        let c = counter.hit(steps: 8, output: 2, window: 5, sample: 640)   // a new sample is a new hit
        XCTAssertEqual(c, 1); XCTAssertEqual(counter.counts[2], 2)
        let d = counter.hit(steps: 8, output: 2, window: 6, sample: 512)   // the same sample in a new window is a new hit
        XCTAssertEqual(d, 2); XCTAssertEqual(counter.counts[2], 3)
    }
    func testResetZeroesEverything() {
        var counter = EmitterVelocityCounter()
        for i in 0..<5 { _ = counter.hit(steps: 4, output: 1, window: Int64(i), sample: 0) }
        counter.reset()
        XCTAssertEqual(counter, EmitterVelocityCounter()); XCTAssertNil(counter.currentIndex(1))
        XCTAssertEqual(counter.hit(steps: 4, output: 1, window: 0, sample: 0), 0, "back to the first hit")
    }

    // MARK: - the document field (additive-Optional, fixed-size, tolerant)

    func testANewDocumentHasNoVelocitiesAndEncodesNoKey() throws {
        let doc = PluginState.makeInit()
        XCTAssertNil(doc.euclideousEmitterVelocities); XCTAssertEqual(doc.euclideousEmitterVelocitiesResolved, EmitterVelocitySet())
        let obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        XCTAssertNil(obj["euclideousEmitterVelocities"], "an untouched document writes nothing")
    }
    func testADocumentWithoutTheFieldDecodesAsFourOffAndRoundTrips() throws {
        var doc = PluginState.makeInit(); doc.euclideousKeyRoot = 5
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        obj.removeValue(forKey: "euclideousEmitterVelocities")
        let back = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(back.euclideousEmitterVelocities); XCTAssertEqual(back.euclideousKeyRoot, 5, "no migration, no factory reset")
        XCTAssertEqual(back, doc)
    }
    func testAStoredSetRoundTripsAndEncodesAsAFourElementArray() throws {
        var doc = PluginState.makeInit()
        var set = EmitterVelocitySet()
        set[0] = EmitterVelocity(on: true, steps: 16, hits: 16, offset: 0, hitVel: 40, missVel: -20)
        set[2] = EmitterVelocity(on: true, steps: 5, hits: 2, offset: 3, hitVel: -63, missVel: 63)
        doc.euclideousEmitterVelocities = set
        let data = try JSONEncoder().encode(doc)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.euclideousEmitterVelocitiesResolved, set); XCTAssertEqual(back, doc)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((obj["euclideousEmitterVelocities"] as? [Any])?.count, 4, "fixed size: always four")
    }
    func testGarbageShortAndLongStoredValuesNeverFailTheLoad() throws {
        XCTAssertEqual(try decode(velJSON: "\"banana\"").euclideousEmitterVelocitiesResolved, EmitterVelocitySet(), "not an array ⇒ the defaults")
        let short = try decode(velJSON: "[{\"on\":true,\"hitVel\":12}]").euclideousEmitterVelocitiesResolved
        XCTAssertTrue(short[0].on); XCTAssertEqual(short[0].hitVel, 12); XCTAssertEqual(short[1], EmitterVelocity(), "a short array leaves the rest at their defaults")
        let clamped = try decode(velJSON: "[{\"on\":true,\"steps\":300,\"hits\":-4,\"offset\":99,\"hitVel\":500,\"missVel\":-500}]").euclideousEmitterVelocitiesResolved[0]
        XCTAssertEqual([clamped.steps, clamped.hits, clamped.offset, clamped.hitVel, clamped.missVel], [16, 0, 15, 63, -63], "out of range clamps")
        let long = try decode(velJSON: "[{},{},{},{\"on\":true},{\"on\":true}]").euclideousEmitterVelocitiesResolved
        XCTAssertTrue(long[3].on, "the fifth is dropped, the fourth kept"); XCTAssertEqual(long.asArray.count, 4)
    }
    func testEveryFactoryPresetCarriesNoVelocities() {
        for (name, make) in EuclideousPresets.all { XCTAssertEqual(make().euclideousEmitterVelocitiesResolved, EmitterVelocitySet(), "\(name): a preset without the field loads them all off") }
    }
    // MARK: - the UI pure functions (value text, bar share, drag, VoiceOver)

    func testValueTextBarShareDragAndVoiceOver() {
        let v = EmitterVelocity(on: true, steps: 8, hits: 3, offset: 2, hitVel: 20, missVel: -15)
        XCTAssertEqual(EmitterVelocityField.allCases.map { emitterVelocityValueText($0, v) }, ["8", "3", "+2", "+20", "\u{2212}15"])
        XCTAssertEqual(emitterVelocityValueText(.hitVel, EmitterVelocity(hitVel: 0)), "0")
        // the bipolar bar: signed share −1…+1 for HIT VEL / MISS VEL, 0…1 for the pattern fields
        XCTAssertEqual(emitterVelocityBarShare(.hitVel, EmitterVelocity(hitVel: 63)), 1, accuracy: 1e-9)
        XCTAssertEqual(emitterVelocityBarShare(.missVel, EmitterVelocity(missVel: -63)), -1, accuracy: 1e-9)
        XCTAssertEqual(emitterVelocityBarShare(.hitVel, EmitterVelocity(hitVel: 0)), 0, accuracy: 1e-9)
        XCTAssertEqual(emitterVelocityBarShare(.steps, EmitterVelocity(steps: 16)), 1)
        // the drag: HIT VEL / MISS VEL move 5 per 3 pt, STEPS one per 10 pt; clamps, never wraps
        XCTAssertEqual(emitterVelocityDragValue(.hitVel, start: EmitterVelocity(hitVel: 0), travelUp: 9).hitVel, 15, "3 steps of 5 in 9 pt")
        XCTAssertEqual(emitterVelocityDragValue(.hitVel, start: EmitterVelocity(hitVel: 0), travelUp: -9).hitVel, -15)
        XCTAssertEqual(emitterVelocityDragValue(.hitVel, start: EmitterVelocity(hitVel: 0), travelUp: 999).hitVel, 63, "clamped at the top")
        XCTAssertEqual(emitterVelocityDragValue(.steps, start: EmitterVelocity(steps: 8), travelUp: 25).steps, 10)
        XCTAssertEqual(emitterVelocityCellLabel(output: 0, .hitVel, v), "Emitter A hit velocity plus 20")
        XCTAssertEqual(emitterVelocityCellLabel(output: 1, .missVel, v), "Emitter B miss velocity minus 15")
        XCTAssertEqual(emitterVelocityCellLabel(output: 2, .offset, v), "Emitter C offset plus 2")
        XCTAssertEqual(emitterVelocityStripLabel(output: 0, v), "Emitter A pattern, 3 of 8, hit velocity plus 20, miss velocity minus 15")
        XCTAssertEqual(emitterVelocityTabAccessibilityLabel(), "Velocity"); XCTAssertEqual(emitterVelocityToggleLabel(output: 3), "Velocity on emitter D")
    }
    func testTheSnapshotsConfigCarriesTheMaskAndFields() {
        var set = EmitterVelocitySet(); set[1] = EmitterVelocity(on: true, steps: 5, hits: 2, offset: 3, hitVel: 30, missVel: -15)
        let snap = EmitterVelocitySnap(set)
        XCTAssertTrue(snap.anyOn); XCTAssertEqual(snap[1].patternMask, emitterRatchetPatternMask(steps: 5, hits: 2, offset: 3))
        XCTAssertEqual(snap[1].hitVel, 30); XCTAssertEqual(snap[1].missVel, -15)
        XCTAssertFalse(EmitterVelocitySnap().anyOn, "a fresh snapshot is inert")
    }
}
