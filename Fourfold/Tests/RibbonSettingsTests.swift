//  RibbonSettingsTests.swift — RIBBON SETTINGS ferry (2026-11-16), slice 2: the saved settings model (§1) — the defaults,
//  the save round-trip, the decode-tolerance (§1.2), and the PluginState resolver. The LIVE holds (§2) and the engine/UI
//  come in later slices; here the model only has to persist and default correctly.

import XCTest

final class RibbonSettingsTests: XCTestCase {

    // §1.1 defaults: SCRUB, SLIP, LATCH off, both parts on, all lanes included, no marks.
    func testDefaults() {
        let d = RibbonSettings.defaults
        XCTAssertEqual(d.touchMode, .scrub); XCTAssertEqual(d.release, .slip); XCTAssertFalse(d.latch)
        XCTAssertTrue(d.riffOn); XCTAssertTrue(d.stackOn)
        XCTAssertEqual(d.riffLanes, 0x0F); XCTAssertEqual(d.stackLanes, 0x0F)
        XCTAssertEqual(d.tuttiSteps, 0); XCTAssertEqual(d.tuttiRanks, 0)
        XCTAssertFalse(d.tuttiActive)
        for l in 0..<4 { XCTAssertTrue(d.riffLaneIncluded(l)); XCTAssertTrue(d.stackLaneIncluded(l)) }
        for s in 1...8 { XCTAssertFalse(d.stepMarked(s)); XCTAssertFalse(d.rankMarked(s)) }
        XCTAssertEqual(RibbonSettings(), .defaults)
    }

    // §3.1 inclusion + §6 marks — the pure reads the engine + UI share.
    func testInclusionAndMarks() {
        var s = RibbonSettings()
        s.stackOn = false; XCTAssertTrue(s.riffLaneIncluded(2)); XCTAssertFalse(s.stackLaneIncluded(2), "stackOn off excludes every stack lane")
        s.stackOn = true; s.stackLanes = 0b0010; XCTAssertTrue(s.stackLaneIncluded(1)); XCTAssertFalse(s.stackLaneIncluded(0))
        s.riffOn = false; for l in 0..<4 { XCTAssertFalse(s.riffLaneIncluded(l), "riffOn off excludes every riff lane") }
        s.tuttiSteps = 0b0001_0000; XCTAssertTrue(s.stepMarked(5)); XCTAssertFalse(s.stepMarked(4)); XCTAssertTrue(s.tuttiActive)
        s = RibbonSettings(); s.tuttiRanks = 0b1000_0000; XCTAssertTrue(s.rankMarked(8)); XCTAssertFalse(s.rankMarked(7)); XCTAssertTrue(s.tuttiActive)
    }

    // §1.1 save: a non-default value round-trips through JSON exactly.
    func testRoundTrip() throws {
        var s = RibbonSettings()
        s.touchMode = .tutti; s.release = .carryOn; s.latch = true; s.stackOn = false
        s.riffLanes = 0b1010; s.stackLanes = 0b0101; s.tuttiSteps = 0b0010_0100; s.tuttiRanks = 0b1000_0001
        let data = try JSONEncoder().encode(s)
        XCTAssertEqual(try JSONDecoder().decode(RibbonSettings.self, from: data), s)
    }

    // §1.2 decode-tolerant: a garbled / partial blob keeps each field's default and never throws.
    func testTolerantDecode() throws {
        let garbled = Data(#"{"touchMode":"bogus","release":42,"latch":"nope","riffLanes":"x","tuttiSteps":3}"#.utf8)
        let s = try JSONDecoder().decode(RibbonSettings.self, from: garbled)
        XCTAssertEqual(s.touchMode, .scrub); XCTAssertEqual(s.release, .slip); XCTAssertFalse(s.latch)
        XCTAssertEqual(s.riffLanes, 0x0F, "a garbled field keeps its default")
        XCTAssertEqual(s.tuttiSteps, 3, "a valid field still decodes")
        XCTAssertEqual(try JSONDecoder().decode(RibbonSettings.self, from: Data("{}".utf8)), .defaults, "an empty object is all defaults")
    }

    // §9.2 / §13.6 — the loop walk reads columns inside the span a…b, in the lane's own direction, first position at a.
    func testLoopColumn() {
        func seq(_ dir: RiffDir, _ a: Int, _ b: Int, _ n: Int) -> [Int] {
            (0..<n).map { euclideousRibbonLoopColumn(k: Int64($0), spanA: a, spanB: b, direction: dir, stride: 1, every: 1) }
        }
        XCTAssertEqual(seq(.forward, 3, 5, 5), [3, 4, 5, 3, 4], "FWD loop 3–5")
        // §9.2 keeps the lane's OWN direction = riffStepAt. This codebase's ping-pong DOUBLES the turn columns (PENDULUM-style),
        // so PING reads 3,4,5,5,4,3 — NOT the §13.6 assumption 3,4,5,4,3,4 (the reflecting style). Reported (§16.6).
        XCTAssertEqual(seq(.pingpong, 3, 5, 6), [3, 4, 5, 5, 4, 3], "PING loop 3–5 (lane's own doubled-endpoint ping-pong)")
        XCTAssertEqual(seq(.reverse, 3, 5, 4), [5, 4, 3, 5], "REV loop 3–5")
        XCTAssertEqual(euclideousRibbonLoopColumn(k: 3, spanA: 3, spanB: 6, direction: .forward, stride: 1, every: 1), 6, "dragged to 3–6, k carries on: k=3 → column 6")
        XCTAssertEqual(seq(.forward, 2, 2, 3), [2, 2, 2], "a one-column span is a static repeat")
    }

    // §1.2 PluginState: nil ⇒ the defaults; a set value is kept; and an old document (no key) resolves to the defaults.
    func testPluginStateResolver() throws {
        var ps = PluginState(machines: [], scenes: [])
        XCTAssertNil(ps.ribbonSettings); XCTAssertEqual(ps.ribbonSettingsResolved, .defaults)
        var s = RibbonSettings(); s.touchMode = .loop; ps.ribbonSettings = s
        XCTAssertEqual(ps.ribbonSettingsResolved, s)
        // a document encoded WITHOUT ribbonSettings decodes with nil ⇒ defaults
        var old = PluginState(machines: [], scenes: []); old.ribbonSettings = nil
        let data = try JSONEncoder().encode(old)
        XCTAssertEqual(try JSONDecoder().decode(PluginState.self, from: data).ribbonSettingsResolved, .defaults)
    }
}
