//  FXTabTests.swift
//  FX TAB ferry (2026-10-18): six fixed effect rows (RATCH, GATE, TIE, VEL, NOTE, CC) on the riff's eight steps. The model, the pure decision
//  function and the pass index live in Derivations.swift / Models.swift and are covered here; the wire-level behaviour (the Router) is covered
//  in RouterTests next to the golden streams it must not move.

import XCTest

final class FXTabTests: XCTestCase {

    // MARK: - model (§1.3 – §1.6)

    func testDefaultsAreEveryCellEmptyAllLanesOnAndTheSpecSettings() {
        let fx = EuclideousFX()
        XCTAssertEqual(fx.lanes, [UInt8](repeating: 0b1111, count: 6))
        XCTAssertEqual(fx.cells.count, 48)
        XCTAssertTrue(fx.cells.allSatisfy { $0 == EuclideousFX.emptyCell })
        XCTAssertEqual(fx.notePasses, 4); XCTAssertEqual(fx.ccNumber, 74); XCTAssertEqual(fx.ccBase, -1)
        XCTAssertTrue(fx.isInert)
        for r in 0..<6 { for lane in 0..<4 { XCTAssertTrue(fx.laneOn(row: r, lane: lane)); XCTAssertFalse(fx.rowHasCells(r, lane: lane)) } }
        // a nil document field resolves to the same thing
        let doc = PluginState(machines: [], scenes: [SceneState.empty()])
        XCTAssertNil(doc.euclideousFX)
        XCTAssertEqual(doc.euclideousFXResolved, fx)
    }
    func testLegalCellValuesPerRow() {
        // RATCH 2…4
        XCTAssertEqual(EuclideousFX.legalCell(row: 0, raw: 1), 2); XCTAssertEqual(EuclideousFX.legalCell(row: 0, raw: 3), 3); XCTAssertEqual(EuclideousFX.legalCell(row: 0, raw: 9), 4)
        // GATE: nearest 5 in 5…100
        XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 0), 5); XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 52), 50); XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 53), 55)
        XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 100), 100); XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 127), 100)
        // TIE: on (any non-sentinel)
        XCTAssertEqual(EuclideousFX.legalCell(row: 2, raw: 0), 1); XCTAssertEqual(EuclideousFX.legalCell(row: 2, raw: 77), 1)
        // VEL 1…127
        XCTAssertEqual(EuclideousFX.legalCell(row: 3, raw: 0), 1); XCTAssertEqual(EuclideousFX.legalCell(row: 3, raw: 110), 110); XCTAssertEqual(EuclideousFX.legalCell(row: 3, raw: 200), 127)
        // NOTE: ±1…±3, never 0 (0 is empty)
        XCTAssertNil(EuclideousFX.legalCell(row: 4, raw: 0)); XCTAssertEqual(EuclideousFX.legalCell(row: 4, raw: -2), -2); XCTAssertEqual(EuclideousFX.legalCell(row: 4, raw: 9), 3); XCTAssertEqual(EuclideousFX.legalCell(row: 4, raw: -9), -3)
        // CC 0…127
        XCTAssertEqual(EuclideousFX.legalCell(row: 5, raw: -5), 0); XCTAssertEqual(EuclideousFX.legalCell(row: 5, raw: 20), 20); XCTAssertEqual(EuclideousFX.legalCell(row: 5, raw: 500), 127)
        // the sentinel is empty in every row; an unknown row has no legal value
        for r in 0..<6 { XCTAssertNil(EuclideousFX.legalCell(row: r, raw: Int(EuclideousFX.emptyCell))) }
        XCTAssertNil(EuclideousFX.legalCell(row: 9, raw: 1))
    }
    func testNormalizedClampsEverythingAndFixesLengths() {
        var fx = EuclideousFX()
        fx.lanes = [0xFF, 0, 0b0101]                                     // short and with stray high bits
        fx.cells = [Int8](repeating: 0, count: 10)                       // short, and 0 is illegal for NOTE
        fx.cells[0] = 9; fx.cells[8] = 52                                // RATCH 9 → 4, GATE 52 → 50
        fx.notePasses = 1; fx.ccNumber = 200; fx.ccBase = 999
        let n = fx.normalized()
        XCTAssertEqual(n.lanes, [0b1111, 0, 0b0101, 0b1111, 0b1111, 0b1111])
        XCTAssertEqual(n.cells.count, 48)
        XCTAssertEqual(n.cell(row: 0, column: 0), 4); XCTAssertEqual(n.cell(row: 1, column: 0), 50)
        XCTAssertEqual(n.notePasses, 2); XCTAssertEqual(n.ccNumber, 119); XCTAssertEqual(n.ccBase, 127)
        var hi = EuclideousFX(); hi.notePasses = 99; XCTAssertEqual(hi.normalized().notePasses, 8)
        var none = EuclideousFX(); none.ccBase = -50; XCTAssertEqual(none.normalized().ccBase, -1)
    }
    func testCellAndLaneAccessors() {
        var fx = EuclideousFX()
        fx.cells[2 * 8 + 5] = 1                       // TIE on column 5 (row 2)
        fx.lanes[2] = 0b0101                          // lanes 1 and 3
        XCTAssertEqual(fx.cell(row: 2, column: 5), 1); XCTAssertNil(fx.cell(row: 2, column: 4)); XCTAssertNil(fx.cell(row: 9, column: 0)); XCTAssertNil(fx.cell(row: 0, column: 8))
        XCTAssertTrue(fx.laneOn(row: 2, lane: 0)); XCTAssertFalse(fx.laneOn(row: 2, lane: 1)); XCTAssertTrue(fx.laneOn(row: 2, lane: 2)); XCTAssertFalse(fx.laneOn(row: 2, lane: 4))
        XCTAssertTrue(fx.rowHasCells(2, lane: 0)); XCTAssertFalse(fx.rowHasCells(2, lane: 1), "a lane the row is off for never has cells")
        XCTAssertFalse(fx.isInert); fx.cells[2 * 8 + 5] = EuclideousFX.emptyCell; XCTAssertTrue(fx.isInert)
        fx.ccBase = 64; XCTAssertFalse(fx.isInert, "a BASE alone makes the CC row act on hits")
    }

    // MARK: - persistence (§1.6 / §1.7)

    func testRoundTripAndDocumentFieldSurvive() throws {
        var fx = EuclideousFX()
        fx.cells[0] = 3; fx.cells[8 + 2] = 100; fx.cells[16 + 7] = 1; fx.cells[24 + 1] = 110; fx.cells[32 + 4] = -2; fx.cells[40 + 6] = 20
        fx.lanes[3] = 0b0110; fx.notePasses = 6; fx.ccNumber = 7; fx.ccBase = 64
        let back = try JSONDecoder().decode(EuclideousFX.self, from: JSONEncoder().encode(fx))
        XCTAssertEqual(back, fx)
        var doc = PluginState(machines: [], scenes: [SceneState.empty()])
        doc.euclideousFX = fx
        let doc2 = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(doc2.euclideousFX, fx); XCTAssertEqual(doc2.euclideousFXResolved, fx)
    }
    func testAPreFeatureDocumentDecodesWithEmptyFXAndNoFactoryReset() throws {
        let doc = PluginState(machines: [], scenes: [SceneState.empty()])
        var json = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        json.removeValue(forKey: "euclideousFX")
        let back = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: json))
        XCTAssertNil(back.euclideousFX); XCTAssertTrue(back.euclideousFXResolved.isInert)
        XCTAssertEqual(back.scenes.count, doc.scenes.count)
    }
    func testOutOfRangeAndGarbageWireValuesClampInsteadOfFailingTheLoad() throws {
        // numbers outside Int8, a NOTE 0, a GATE that is not a multiple of 5, a wrong-length lane array, a string where a number belongs
        let wire = #"{"lanes":[255,7],"cells":[300,-300,52,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0, 0,0,0,0,0,0,0,0],"notePasses":"x","ccNumber":500,"ccBase":-7}"#
        let fx = try JSONDecoder().decode(EuclideousFX.self, from: Data(wire.utf8))
        XCTAssertEqual(fx.lanes[0], 0b1111); XCTAssertEqual(fx.lanes[1], 0b0111); XCTAssertEqual(fx.lanes[2], 0b1111, "a missing lane entry defaults to all on")
        XCTAssertEqual(fx.cell(row: 0, column: 0), 4, "300 → clamps into the Int8 domain then RATCH's 2…4")
        XCTAssertNil(fx.cell(row: 0, column: 1), "−300 → −128, the empty sentinel's own value, which reads as empty")
        XCTAssertEqual(fx.cell(row: 0, column: 2), 4)
        XCTAssertEqual(fx.notePasses, 4, "an unreadable value keeps the default"); XCTAssertEqual(fx.ccNumber, 119); XCTAssertEqual(fx.ccBase, -1)
        // an entirely empty object is the defaults
        XCTAssertEqual(try JSONDecoder().decode(EuclideousFX.self, from: Data("{}".utf8)), EuclideousFX())
        // a document whose FX field holds garbage still decodes (the FX falls back to its defaults instead of failing the load)
        let doc = PluginState(machines: [], scenes: [SceneState.empty()])
        var obj = try JSONSerialization.jsonObject(with: JSONEncoder().encode(doc)) as! [String: Any]
        obj["euclideousFX"] = ["cells": "not an array", "lanes": 5, "ccNumber": "x"] as [String: Any]
        let loaded = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: obj))
        XCTAssertEqual(loaded.euclideousFXResolved, EuclideousFX())
    }
    func testEveryFactoryPresetHasNoFX() {
        for (name, make) in EuclideousPresets.all { XCTAssertTrue(make().euclideousFXResolved.isInert, name) }
    }

    // MARK: - snapshot (§1.8)

    func testTheSnapshotCarriesFXToTheEuclideousRowOnly() {
        var fx = EuclideousFX(); fx.cells[3 * 8 + 2] = 110; fx.lanes[3] = 0b0011; fx.ccBase = 64
        var st = PluginState(machines: machineIDs.map { Machine(machineID: $0, type: .arp) }, scenes: [{ var s = SceneState.empty()
            s.cells[0][Snap.euclideousRow] = Cell(machineID: "gold", buses: [.a]); return s }()])
        st.euclideousFX = fx
        let box = SnapshotBuilder.build(from: st)
        let row = box.cells.first { $0.machineIndex >= 0 && $0.procs.first?.euclideousFX.isInert == false }
        XCTAssertNotNil(row, "the Euclideous row's SnapParams carries the FX")
        XCTAssertEqual(row?.procs.first?.euclideousFX.cell(row: 3, column: 2), 110)
        XCTAssertEqual(row?.procs.first?.euclideousFX.lanes[3], 0b0011)
        // an out-of-range stored value is clamped on its way into the snapshot
        var bad = EuclideousFX(); bad.cells[3 * 8] = 120; bad.notePasses = 40
        st.euclideousFX = bad
        let box2 = SnapshotBuilder.build(from: st)
        let row2 = box2.cells.first { $0.machineIndex >= 0 && $0.procs.first?.euclideousFX.isInert == false }
        XCTAssertEqual(row2?.procs.first?.euclideousFX.notePasses, 8)
    }
}
