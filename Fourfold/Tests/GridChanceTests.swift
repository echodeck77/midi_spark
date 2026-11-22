//  GridChanceTests.swift — GRID CHANCE ferry (2026-11-22): the model (§1), saving/invariant (§1.2–1.4) and the pure
//  functions (§9). The engine's hit-path behaviour (§2) is in GridChanceRouterTests; the golden harness proves the
//  default (all 100) is byte-identical.

import XCTest

final class GridChanceTests: XCTestCase {

    // MARK: §1 model + defaults

    func testDefaultsAre100AndAllDefault() {
        let d = EuclideousGridChance()
        XCTAssertEqual(d.riffRank, Array(repeating: 100, count: 8))
        XCTAssertEqual(d.riffColumn, Array(repeating: 100, count: 8))
        XCTAssertEqual(d.stackRank, Array(repeating: 100, count: 8))
        XCTAssertEqual(d.stackLane, Array(repeating: 100, count: 4))
        XCTAssertTrue(d.isAllDefault)
        XCTAssertFalse(d.riffSet); XCTAssertFalse(d.stackSet)
    }

    func testPluginStateNilResolvesToAll100() {
        let p = PluginState(machines: [], scenes: [SceneState.empty()])
        XCTAssertNil(p.euclideousGridChance)
        XCTAssertTrue(p.euclideousGridChanceResolved.isAllDefault)
    }

    func testInitClampsAndPads() {
        let gc = EuclideousGridChance(riffRank: [-5, 250, 50], riffColumn: [], stackRank: Array(repeating: 100, count: 20), stackLane: [40])
        XCTAssertEqual(gc.riffRank, [0, 100, 50, 100, 100, 100, 100, 100])   // clamped + padded to 8
        XCTAssertEqual(gc.riffColumn.count, 8)
        XCTAssertEqual(gc.stackRank.count, 8)                                 // truncated to 8
        XCTAssertEqual(gc.stackLane, [40, 100, 100, 100])
    }

    func testCodableRoundTripAndTolerantDecode() throws {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        p.euclideousGridChance = EuclideousGridChance(riffRank: [100, 100, 100, 100, 100, 100, 100, 40])
        let data = try JSONEncoder().encode(p)
        let back = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertEqual(back.euclideousGridChanceResolved.riffRank.last, 40)
        // a document with no key at all decodes to nil (every old session / preset)
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(PluginState(machines: [], scenes: [SceneState.empty()]))) as! [String: Any]
        obj.removeValue(forKey: "euclideousGridChance")
        let none = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertNil(none.euclideousGridChance)
        XCTAssertTrue(none.euclideousGridChanceResolved.isAllDefault)
    }

    // MARK: §9.2 riff gate

    func testRiffAll100AlwaysPasses() {
        let m = EuclideousGridChance()
        for step in Int64(0)..<64 {
            XCTAssertTrue(euclideousRiffGridChancePasses(lane: 0, step: step, rank: 5, column: 3, model: m))
        }
    }

    func testRiffRank8At0NeverSoundsOthersDo() {
        var m = EuclideousGridChance(); m.riffRank[7] = 0   // rank 8 = 0%
        for step in Int64(0)..<64 {
            XCTAssertFalse(euclideousRiffGridChancePasses(lane: 1, step: step, rank: 8, column: 2, model: m))
            XCTAssertTrue(euclideousRiffGridChancePasses(lane: 1, step: step, rank: 3, column: 2, model: m))   // other ranks untouched
        }
    }

    func testRiffColumn5At0SilencesThatColumn() {
        var m = EuclideousGridChance(); m.riffColumn[5] = 0   // position 5 = 0%
        for step in Int64(0)..<64 {
            XCTAssertFalse(euclideousRiffGridChancePasses(lane: 2, step: step, rank: 4, column: 5, model: m))
            XCTAssertTrue(euclideousRiffGridChancePasses(lane: 2, step: step, rank: 4, column: 1, model: m))
        }
    }

    func testRiffRankAxisRestAlwaysPasses() {
        var m = EuclideousGridChance(); m.riffRank[0] = 0
        // a rest (rank < 1) has no rank — rank chance never applies (§2.1)
        XCTAssertTrue(euclideousRiffGridChancePasses(lane: 0, step: 3, rank: 0, column: 0, model: m))
    }

    // MARK: §9.2 stack gates

    func testStackRankPerVoice() {
        var m = EuclideousGridChance(); m.stackRank[2] = 0   // rank 3 = 0%
        for step in Int64(0)..<32 {
            XCTAssertFalse(euclideousStackRankChancePasses(lane: 0, step: step, rank: 3, model: m))
            XCTAssertTrue(euclideousStackRankChancePasses(lane: 0, step: step, rank: 1, model: m))
            XCTAssertTrue(euclideousStackRankChancePasses(lane: 0, step: step, rank: 5, model: m))
        }
    }

    func testStackLaneWholeHit() {
        var m = EuclideousGridChance(); m.stackLane[1] = 0   // lane 2 (index 1) = 0%
        for step in Int64(0)..<32 {
            XCTAssertFalse(euclideousStackLaneChancePasses(lane: 1, step: step, model: m))
            XCTAssertTrue(euclideousStackLaneChancePasses(lane: 0, step: step, model: m))
        }
    }

    // MARK: §2.4 roll — bounds, replay-exactness, distribution, salts

    func testRollIsInRangeAndBoundary() {
        for step in Int64(0)..<200 {
            let r = euclideousGridChanceRoll(lane: 0, step: step, coord: 1, salt: euclideousRiffGridChanceSalt)
            XCTAssertTrue((0...99).contains(r))
        }
        // 100 always passes, 0 never (the roll is 0…99)
        XCTAssertTrue(euclideousGridChanceAllows(chance: 100, lane: 0, step: 7, coord: 1, salt: euclideousRiffGridChanceSalt))
        XCTAssertFalse(euclideousGridChanceAllows(chance: 0, lane: 0, step: 7, coord: 1, salt: euclideousRiffGridChanceSalt))
    }

    func testReplayExact() {
        for step in Int64(0)..<100 {
            let a = euclideousGridChanceRoll(lane: 2, step: step, coord: 4, salt: euclideousStackGridChanceSalt)
            let b = euclideousGridChanceRoll(lane: 2, step: step, coord: 4, salt: euclideousStackGridChanceSalt)
            XCTAssertEqual(a, b)
        }
    }

    func testDistribution() {
        func passRate(chance: Int, lane: Int, salt: UInt64) -> Double {
            var pass = 0
            for step in Int64(0)..<10_000 where euclideousGridChanceAllows(chance: chance, lane: lane, step: step, coord: 3, salt: salt) { pass += 1 }
            return Double(pass) / 10_000.0
        }
        XCTAssertEqual(passRate(chance: 50, lane: 0, salt: euclideousRiffGridChanceSalt), 0.50, accuracy: 0.02)
        XCTAssertEqual(passRate(chance: 25, lane: 0, salt: euclideousRiffGridChanceSalt), 0.25, accuracy: 0.02)
        // two lanes thin differently (the sequences are not identical)
        var differ = 0
        for step in Int64(0)..<1000 {
            let a = euclideousGridChanceAllows(chance: 50, lane: 0, step: step, coord: 3, salt: euclideousRiffGridChanceSalt)
            let b = euclideousGridChanceAllows(chance: 50, lane: 1, step: step, coord: 3, salt: euclideousRiffGridChanceSalt)
            if a != b { differ += 1 }
        }
        XCTAssertGreaterThan(differ, 300)   // ~half should differ
    }

    func testSaltsDifferFromEachOtherAndFromExisting() {
        // the two grid salts are distinct ASCII constants, distinct from each other
        XCTAssertNotEqual(euclideousRiffGridChanceSalt, euclideousStackGridChanceSalt)
        // and they produce different roll sequences for identical coordinates (riff vs stack, and vs the NOTES chance idiom)
        var riffVsStack = 0, riffVsNotes = 0
        for step in Int64(0)..<500 {
            if euclideousGridChanceRoll(lane: 0, step: step, coord: 2, salt: euclideousRiffGridChanceSalt)
                != euclideousGridChanceRoll(lane: 0, step: step, coord: 2, salt: euclideousStackGridChanceSalt) { riffVsStack += 1 }
            if euclideousGridChanceRoll(lane: 0, step: step, coord: 2, salt: euclideousRiffGridChanceSalt)
                != euclideousNotesChanceRoll(lane: 0, h: step) { riffVsNotes += 1 }
        }
        XCTAssertGreaterThan(riffVsStack, 400)
        XCTAssertGreaterThan(riffVsNotes, 400)
    }

    // MARK: §9.3 axis + §1.2 invariant

    func testAxisSet() {
        var m = EuclideousGridChance()
        XCTAssertEqual(euclideousGridChanceAxisSet(m, grid: .riff), .none)
        m.riffColumn[2] = 60
        XCTAssertEqual(euclideousGridChanceAxisSet(m, grid: .riff), .other)
        m.riffRank[0] = 70
        XCTAssertEqual(euclideousGridChanceAxisSet(m, grid: .riff), .rank)   // rank wins once both set (pre-repair)
        var s = EuclideousGridChance(); s.stackLane[3] = 10
        XCTAssertEqual(euclideousGridChanceAxisSet(s, grid: .stack), .other)
    }

    func testRepairInvariantKeepsRank() {
        var m = EuclideousGridChance(); m.riffRank[7] = 40; m.riffColumn[1] = 70; m.stackRank[0] = 30; m.stackLane[2] = 20
        let fixed = euclideousGridChanceRepairInvariant(m)
        XCTAssertEqual(fixed.riffRank[7], 40)                 // rank kept
        XCTAssertTrue(fixed.riffColumn.allSatisfy { $0 == 100 })   // other axis reset
        XCTAssertEqual(fixed.stackRank[0], 30)
        XCTAssertTrue(fixed.stackLane.allSatisfy { $0 == 100 })
    }

    func testNormalizeAtLoadKeepsRankAndNilsAllDefault() {
        var p = PluginState(machines: [], scenes: [SceneState.empty()])
        p.euclideousGridChance = EuclideousGridChance(riffRank: [40, 100, 100, 100, 100, 100, 100, 100], riffColumn: [70, 100, 100, 100, 100, 100, 100, 100])
        p.normalizeGridChanceAtLoad()
        XCTAssertEqual(p.euclideousGridChanceResolved.riffRank[0], 40)
        XCTAssertTrue(p.euclideousGridChanceResolved.riffColumn.allSatisfy { $0 == 100 })
        // a stored gridChance that repairs to all-default becomes nil
        var q = PluginState(machines: [], scenes: [SceneState.empty()])
        q.euclideousGridChance = EuclideousGridChance()   // all 100 but explicitly stored
        q.normalizeGridChanceAtLoad()
        XCTAssertNil(q.euclideousGridChance)
        // an already-valid document is untouched
        var r = PluginState(machines: [], scenes: [SceneState.empty()])
        let valid = EuclideousGridChance(stackLane: [20, 100, 100, 100])
        r.euclideousGridChance = valid
        r.normalizeGridChanceAtLoad()
        XCTAssertEqual(r.euclideousGridChance, valid)
    }
}
