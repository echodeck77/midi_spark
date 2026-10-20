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
        XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 95), 95); XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 100), 95, "LEGATO RETIRED (2026-10-20): the GATE row tops out at 95 — a stored 100 loads as 95"); XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 127), 95)
        XCTAssertEqual(EuclideousFX.gateMax, 95); XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 98), 95); XCTAssertEqual(EuclideousFX.legalCell(row: 1, raw: 92), 90)
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
        fx.cells[0] = 3; fx.cells[8 + 2] = 95; fx.cells[16 + 7] = 1; fx.cells[24 + 1] = 110; fx.cells[32 + 4] = -2; fx.cells[40 + 6] = 20
        fx.lanes[3] = 0b0110; fx.notePasses = 6; fx.ccNumber = 7; fx.ccBase = 64
        let back = try JSONDecoder().decode(EuclideousFX.self, from: JSONEncoder().encode(fx))
        XCTAssertEqual(back, fx)
        var doc = PluginState(machines: [], scenes: [SceneState.empty()])
        doc.euclideousFX = fx
        let doc2 = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(doc2.euclideousFX, fx); XCTAssertEqual(doc2.euclideousFXResolved, fx)
    }
    /// LEGATO RETIRED from the GATE row (Paul 2026-10-20: "remove 100=legato"): a session saved while a cell held 100 loads it as 95, so the UI and the engine (both fed from the
    /// decoded document) agree and a repeated pitch re-strikes.
    func testAStoredGate100LoadsAs95AndNothingElseMoves() throws {
        var fx = EuclideousFX()
        fx.cells[8 + 2] = 100; fx.cells[8 + 5] = 90; fx.cells[24 + 1] = 100        // GATE 100, GATE 90, and a VEL row 100 (VEL is untouched)
        let back = try JSONDecoder().decode(EuclideousFX.self, from: JSONEncoder().encode(fx))
        XCTAssertEqual(back.cell(row: 1, column: 2), 95, "a stored GATE 100 loads as 95")
        XCTAssertEqual(back.cell(row: 1, column: 5), 90); XCTAssertEqual(back.cell(row: 3, column: 1), 100, "VEL 100 is a real velocity")
        var doc = PluginState(machines: [], scenes: [SceneState.empty()]); doc.euclideousFX = fx
        let doc2 = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(doc))
        XCTAssertEqual(doc2.euclideousFXResolved.cell(row: 1, column: 2), 95)
        XCTAssertFalse(euclideousGateIsLegato(Double(doc2.euclideousFXResolved.cell(row: 1, column: 2)!) / 100), "…so no value a document can hold reaches the engine's legato predicate")
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

    // MARK: - the one per-hit decision (§2.2 / §2.3)

    private func fxWith(_ cells: [(row: Int, col: Int, v: Int)], lanes: [Int: UInt8] = [:], passes: UInt8 = 4, ccBase: Int16 = -1) -> EuclideousFX {
        var fx = EuclideousFX()
        for c in cells { fx.cells[c.row * 8 + c.col] = Int8(c.v) }
        for (r, m) in lanes { fx.lanes[r] = m }
        fx.notePasses = passes; fx.ccBase = ccBase
        return fx
    }
    func testApplyRequiresLaneBitRiffRestAndACell() {
        let fx = fxWith([(0, 3, 3), (1, 3, 50), (3, 3, 110), (4, 3, 2), (5, 3, 20)], lanes: [0: 0b0010])   // RATCH only for lane 2
        // all conditions hold for lane 1 (index 0): GATE, VEL, NOTE, CC apply; RATCH does not (its lane set is lane 2 only)
        let h = euclideousFXApply(fx, lane: 0, playsRiff: true, column: 3, writtenRank: 4, pass: 1)
        XCTAssertEqual(h.ratch, 0); XCTAssertEqual(h.gatePct, 50); XCTAssertEqual(h.vel, 110); XCTAssertEqual(h.noteStep, 2); XCTAssertEqual(h.noteOffset, 2); XCTAssertEqual(h.cc, 20)
        XCTAssertEqual(h.appliedRows, 0b111010, "bits for GATE, VEL, NOTE, CC")
        XCTAssertEqual(euclideousFXApply(fx, lane: 1, playsRiff: true, column: 3, writtenRank: 4, pass: 0).ratch, 3, "lane 2 has RATCH on")
        // (b) a lane whose riff layer is off reads no column → nothing applies
        XCTAssertEqual(euclideousFXApply(fx, lane: 0, playsRiff: false, column: 3, writtenRank: 4, pass: 0), EuclideousFXHit())
        // (c) a rest column (written rank < 1) → nothing applies
        XCTAssertEqual(euclideousFXApply(fx, lane: 0, playsRiff: true, column: 3, writtenRank: 0, pass: 0), EuclideousFXHit())
        // (d) an empty cell on another column → nothing
        XCTAssertEqual(euclideousFXApply(fx, lane: 0, playsRiff: true, column: 4, writtenRank: 4, pass: 0), EuclideousFXHit())
        // bad inputs never trap
        XCTAssertEqual(euclideousFXApply(fx, lane: 9, playsRiff: true, column: 3, writtenRank: 4, pass: 0), EuclideousFXHit())
        XCTAssertEqual(euclideousFXApply(fx, lane: 0, playsRiff: true, column: 8, writtenRank: 4, pass: 0), EuclideousFXHit())
        XCTAssertEqual(euclideousFXApply(fx, lane: 0, playsRiff: true, column: -1, writtenRank: 4, pass: 0), EuclideousFXHit())
    }
    func testTieStopsEveryOtherRowOnItsHitIncludingCC() {
        let fx = fxWith([(0, 2, 4), (1, 2, 50), (2, 2, 1), (3, 2, 100), (4, 2, 1), (5, 2, 9)], ccBase: 64)
        let h = euclideousFXApply(fx, lane: 0, playsRiff: true, column: 2, writtenRank: 3, pass: 0)
        XCTAssertEqual(h, EuclideousFXHit(tie: true))
        // the TIE row's own lane set is honoured: lane 4 off for TIE ⇒ the other rows apply again
        var fx2 = fx; fx2.lanes[2] = 0b0111
        let h2 = euclideousFXApply(fx2, lane: 3, playsRiff: true, column: 2, writtenRank: 3, pass: 0)
        XCTAssertFalse(h2.tie); XCTAssertEqual(h2.ratch, 4); XCTAssertEqual(h2.gatePct, 50); XCTAssertEqual(h2.vel, 100); XCTAssertEqual(h2.cc, 9)
    }
    func testCCBaseSendsOnHitsThatMeetABCButHaveAnEmptyCell() {
        let withBase = fxWith([(5, 1, 20)], ccBase: 64)
        let onCell = euclideousFXApply(withBase, lane: 0, playsRiff: true, column: 1, writtenRank: 2, pass: 0)
        XCTAssertEqual(onCell.cc, 20); XCTAssertEqual(onCell.appliedRows, 1 << 5)
        let off = euclideousFXApply(withBase, lane: 0, playsRiff: true, column: 4, writtenRank: 2, pass: 0)
        XCTAssertEqual(off.cc, 64, "BASE on a hit with an empty CC cell"); XCTAssertEqual(off.appliedRows, 0, "a BASE send has no cell, so no flash")
        XCTAssertNil(euclideousFXApply(withBase, lane: 0, playsRiff: true, column: 4, writtenRank: 0, pass: 0).cc, "a rest column sends nothing, BASE or not")
        XCTAssertNil(euclideousFXApply(withBase, lane: 0, playsRiff: false, column: 4, writtenRank: 2, pass: 0).cc, "a lane with its riff off sends nothing")
        var laneOff = withBase; laneOff.lanes[5] = 0b1110
        XCTAssertNil(euclideousFXApply(laneOff, lane: 0, playsRiff: true, column: 4, writtenRank: 2, pass: 0).cc, "the CC row's own lane set gates BASE too")
        let noBase = fxWith([(5, 1, 20)])
        XCTAssertNil(euclideousFXApply(noBase, lane: 0, playsRiff: true, column: 4, writtenRank: 2, pass: 0).cc, "BASE none: those hits send nothing")
        XCTAssertEqual(euclideousFXApply(fxWith([(5, 1, 0)]), lane: 0, playsRiff: true, column: 1, writtenRank: 2, pass: 0).cc, 0, "CC value 0 is a real value")
    }
    func testNoteOffsetIsStepTimesPassModPasses() {
        for passes in 2...8 { for s in [-3, -2, -1, 1, 2, 3] { for pass in 0..<40 {
            let h = euclideousFXApply(fxWith([(4, 0, s)], passes: UInt8(passes)), lane: 0, playsRiff: true, column: 0, writtenRank: 4, pass: pass)
            XCTAssertEqual(h.noteOffset, s * (pass % passes))
        } } }
        XCTAssertEqual(euclideousFXApply(fxWith([(4, 0, 1)]), lane: 0, playsRiff: true, column: 0, writtenRank: 4, pass: -1).noteOffset, 3, "a negative pass wraps, never traps")
    }
    func testLanePlaysRiffIsRiffOnAndNotShadow() {
        var l = EuclidLine(pulses: 3, steps: 8, riffOn: true)
        XCTAssertTrue(euclideousLanePlaysRiff(l))
        l.riffOn = false; XCTAssertFalse(euclideousLanePlaysRiff(l))
        l.riffOn = true; l.listenPitchMode = .shadow; XCTAssertFalse(euclideousLanePlaysRiff(l), "SHADOW replaces the riff layer")
        l.listenPitchMode = .avoid; XCTAssertTrue(euclideousLanePlaysRiff(l))
    }
    func testLitVelocityFollowsTheNotesVelBarOffset() {
        XCTAssertEqual(euclideousFXLitVelocity(fxVel: 110, notesVelocity: 90, velocityAbsolute: 100), 100, "VEL bar shows −10 ⇒ 110 − 10")
        XCTAssertEqual(euclideousFXLitVelocity(fxVel: 120, notesVelocity: 100, velocityAbsolute: 100), 120)
        XCTAssertEqual(euclideousFXLitVelocity(fxVel: 125, notesVelocity: 127, velocityAbsolute: 100), 127, "clamps at 127")
        XCTAssertEqual(euclideousFXLitVelocity(fxVel: 5, notesVelocity: 1, velocityAbsolute: 100), 1, "clamps at 1")
        XCTAssertEqual(euclideousFXLitVelocity(fxVel: 100, notesVelocity: 127, velocityAbsolute: 1), 127, "the bar's own ±64 clamp: +126 shows as +64 ⇒ 164 → 127")
    }

    // MARK: - fold + cap

    func testExtendedFoldMatchesRiffResolveUpwardAndContinuesDownward() {
        let pool = [48, 51, 55]                       // C3 E♭3 G3
        func asc(_ k: Int) -> Int { pool[k] }
        for rank in 1...40 { XCTAssertEqual(riffResolveExtended(rank: rank, oct: 0, n: 3, asc: asc), riffResolve(rank: rank, oct: 0, n: 3, wrap: .fold, asc: asc), "rank \(rank)") }
        XCTAssertEqual(riffResolveExtended(rank: 9, oct: 0, n: 3, asc: asc), 55 + 24, "rank 9 is G5")
        XCTAssertEqual(riffResolveExtended(rank: 0, oct: 0, n: 3, asc: asc), 55 - 12, "rank 0 is G2")
        XCTAssertEqual(riffResolveExtended(rank: -1, oct: 0, n: 3, asc: asc), 51 - 12, "rank −1 is E♭2")
        XCTAssertEqual(riffResolveExtended(rank: -2, oct: 0, n: 3, asc: asc), 48 - 12, "rank −2 is C2")
        XCTAssertEqual(riffResolveExtended(rank: -3, oct: 0, n: 3, asc: asc), 55 - 24, "rank −3 is G1")
        XCTAssertEqual(riffResolveExtended(rank: 4, oct: 1, n: 3, asc: asc), 48 + 12 + 12, "OCT adds on top")
        XCTAssertNil(riffResolveExtended(rank: 3, oct: 0, n: 0, asc: asc), "an empty pool resolves nothing")
        XCTAssertNil(riffResolve(rank: 0, oct: 0, n: 3, wrap: .fold, asc: asc), "(and the existing fold still calls rank 0 a rest — untouched)")
        // with one note held and a huge move nothing traps and the arithmetic is the octave extension
        XCTAssertEqual(riffResolveExtended(rank: 8 + 3 * 7 + 7, oct: 0, n: 1, asc: { _ in 60 }), 60 + 12 * 35)
        XCTAssertEqual(riffResolveExtended(rank: 1 - 3 * 7 - 7, oct: 0, n: 1, asc: { _ in 60 }), 60 - 12 * 28, "rank 1 is lap 0, so rank −27 is lap −28")
    }
    func testRatchetCapMatchesTheMasksRuleAndFXCountIsTheCellsN() {
        XCTAssertEqual(euclideousRatchetCap(sub: 0.5, cyc: 4), 16)
        XCTAssertEqual(euclideousRatchetCap(sub: 1.0 / 12, cyc: 4), 2, "1/32T over a 4-beat grid bar: 10.67 → clamps to ... 2")
        XCTAssertEqual(euclideousRatchetCap(sub: 0.125, cyc: 16), 1, "a slow grid (16-beat bar) can leave no room")
        XCTAssertEqual(euclideousFXRatchetCount(requested: 4, sub: 0.5, cyc: 4), 4, "never rolled, never clamped to a legal size: exactly n")
        XCTAssertEqual(euclideousFXRatchetCount(requested: 3, sub: 0.5, cyc: 4), 3)
        XCTAssertEqual(euclideousFXRatchetCount(requested: 4, sub: 0.125, cyc: 8), 2, "the cap lowers n to what fits")
        XCTAssertEqual(euclideousFXRatchetCount(requested: 4, sub: 0.125, cyc: 16), 0, "cap 1 ⇒ a plain hit")
    }

    // MARK: - the NOTE pass index (§7.2)

    private struct Rng {
        var state: UInt64
        mutating func next() -> UInt64 { state &+= 0x9E3779B97F4A7C15; var z = state; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
        mutating func int(_ r: ClosedRange<Int>) -> Int { r.lowerBound + Int(next() % UInt64(r.count)) }
        mutating func bool() -> Bool { next() & 1 == 1 }
    }
    private func pattern(_ hits: [Int], n: Int) -> [Bool] { var b = [Bool](repeating: false, count: 16); for h in hits { b[h] = true }; return b }

    func testWalkPeriodsConfirmedAgainstRiffStepAt() {
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .forward, length: 8, stride: 1), 8)
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .reverse, length: 8, stride: 1), 8)
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .pendulum, length: 8, stride: 1), 14, "PEND: 2·8 − 2")
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .pingpong, length: 8, stride: 1), 16, "PING: 2·8")
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .forward, length: 8, stride: 2), 4, "STRIDE 2 at LENGTH 8")
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .forward, length: 1, stride: 5), 1, "LENGTH 1")
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .pendulum, length: 1, stride: 1), 1)
        XCTAssertEqual(euclideousFXWalkPeriod(dir: .random, length: 8, stride: 1), 8, "RANDOM/DRUNK are coerced to FWD upstream; FWD's period")
        // the derivation, checked by brute force: the first ordinal at which the position sequence repeats equals P, for every direction/length/stride
        for dir in [RiffDir.forward, .reverse, .pendulum, .pingpong] { for len in 1...8 { for stride in 1...7 {
            let p = euclideousFXWalkPeriod(dir: dir, length: len, stride: stride)
            let seq = (0..<(4 * 2 * 8 * 8)).map { riffStepAt(dir, raw: $0 * stride, steps: len, seed: 0) }
            for o in 0..<(seq.count - p) { XCTAssertEqual(seq[o], seq[o + p], "\(dir) len \(len) stride \(stride): the walk repeats every P = \(p)") }
            if p > 1 { XCTAssertTrue((1..<p).allSatisfy { k in (0..<p).contains { seq[$0] != seq[$0 + k] } }, "\(dir) len \(len) stride \(stride): no shorter period than \(p)") }
        } } }
    }
    /// All the ticks, in order, at which `col` is read on a lane (hits only), with that hit's pass index.
    private func plays(of col: Int, buf: [Bool], n: Int, ticks: Range<Int64>, locked: Bool, adv: Bool, dir: RiffDir = .forward, stride: Int = 1, length: Int = 8,
                       grid: EuclideousLaneRestartGrid = .off) -> [(tick: Int64, p: Int)] {
        var out: [(Int64, Int)] = []
        for t in ticks {
            let info = euclideousLaneTick(buf: buf, n: n, dir: .fwd, cycleLen: n, sub: 0.5, tick: t, grid: grid, legacySpanBeats: 0, locked: locked, advanceStep: adv)
            guard info.rawIsHit else { continue }
            let step = riffRotateStep(riffStepAt(dir, raw: Int(info.advOrd) * stride, steps: length, seed: 0), by: 0, steps: length)
            guard step == col else { continue }
            out.append((t, euclideousFXPassIndex(buf: buf, n: n, dir: .fwd, cycleLen: n, sub: 0.5, tick: t, grid: grid, legacySpanBeats: 0, locked: locked, advanceStep: adv,
                                                  riffDir: dir, stride: stride, length: length)))
        }
        return out
    }
    func testFreeFwdThreeHitLaneAdvHitGivesRanks4_5_6_7_4OnItsFirstFivePlays() {
        let buf = pattern([0, 3, 6], n: 8)                                  // a 3-hit, 8-step lane (hits on steps 1, 4, 7 one-based)
        let pl = plays(of: 3, buf: buf, n: 8, ticks: 0..<400, locked: false, adv: false)
        XCTAssertGreaterThanOrEqual(pl.count, 5)
        // the column written as rank 4 with NOTE +1, PASSES 4 → ranks 4,5,6,7,4
        let ranks = pl.prefix(5).map { 4 + 1 * ($0.p % 4) }
        XCTAssertEqual(ranks, [4, 5, 6, 7, 4], "p = 0,1,2,3,4 on its first five plays, whatever the lane's hit count")
        XCTAssertEqual(pl.prefix(6).map { $0.p }, [0, 1, 2, 3, 4, 5])
    }
    func testFreeFwdAdvStepGivesTheSamePassesOnAnEightStepThreeHitLane() {
        let buf = pattern([0, 3, 6], n: 8)
        let pl = plays(of: 3, buf: buf, n: 8, ticks: 0..<400, locked: false, adv: true)   // rank 4 written on column 4 (index 3)
        XCTAssertEqual(pl.prefix(5).map { 4 + ($0.p % 4) }, [4, 5, 6, 7, 4])
    }
    func testLockOnAThreeHitLaneMovesOneStepPerEuclidLapAndIsClosedFormTenThousandLapsOut() {
        let buf = pattern([0, 3, 6], n: 8)
        let grid = EuclideousLaneRestartGrid.off
        // LOCK re-anchors the riff every lap, so the column a hit reads is its hit index in the lap; column 0 is the lap's first hit, once per lap
        let pl = plays(of: 0, buf: buf, n: 8, ticks: 0..<200, locked: true, adv: false)
        XCTAssertEqual(pl.prefix(8).map { $0.p }, Array(0..<8), "one NOTE step per Euclid lap")
        // 10,000 laps out, in O(1)
        let lap = Int64(10_000)
        XCTAssertEqual(euclideousFXPassIndex(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: lap * 8, grid: grid, legacySpanBeats: 0, locked: true, advanceStep: false,
                                              riffDir: .forward, stride: 1, length: 8), 10_000)
        XCTAssertEqual(euclideousFXPassIndex(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: lap * 8 + 7, grid: grid, legacySpanBeats: 0, locked: true, advanceStep: false,
                                              riffDir: .forward, stride: 1, length: 8), 10_000)
        // …and with restart marks the closed form still equals the brute force 10,000 laps out
        let g = EuclideousLaneRestartGrid(unitTicks: 8, rhythmMask: (1 << 0) | (1 << 5), melodyMask: 1 << 3)
        let far = Int64(10_000) * 8 * 16 + 37
        XCTAssertEqual(bruteLockPass(tick: far, cycleLen: 8, grid: g, buf: buf, n: 8), euclideousFXLockPass(tick: far, cycleLen: 8, grid: g,
                       localT: euclideousLanePhase(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: far, grid: g, legacySpanBeats: 0).localT))
    }
    /// Independent restatement: step tick by tick from the melody origin counting Euclid lap starts (`raw == 0` on the lane's own phase).
    private func bruteLockPass(tick t: Int64, cycleLen: Int, grid: EuclideousLaneRestartGrid, buf: [Bool], n: Int) -> Int {
        let u = Int64(grid.unitTicks)
        let cellM = grid.melodyMask != 0 ? (euclideousMaskedResetCell(absCell: Int(floorDiv(t, u)), mask: grid.melodyMask) ?? 0) : 0
        let m = Int64(cellM) * u
        var count = 0
        var s = m + 1
        while s <= t {
            if euclideousLanePhase(buf: buf, n: n, dir: .fwd, cycleLen: cycleLen, sub: 0.5, tick: s, grid: grid, legacySpanBeats: 0).raw == 0 { count += 1 }
            s += 1
        }
        return count
    }
    func testLockClosedFormEqualsTheBruteForceForRandomMarkSetsIncludingTheNegativeFirstWindow() {
        var rng = Rng(state: 2026)
        var checked = 0
        for _ in 0..<120 {
            let n = rng.int(2...12), cl = n
            let buf = pattern([0], n: n)
            let unit = [4, cl, 2 * cl, 4 * cl][rng.int(0...3)]
            func mask() -> UInt16 { rng.int(0...3) == 0 ? 0 : UInt16(truncatingIfNeeded: rng.next()) & UInt16(truncatingIfNeeded: rng.next()) }
            let g = EuclideousLaneRestartGrid(unitTicks: unit, rhythmMask: mask(), melodyMask: mask())
            guard g.isActive else { continue }
            for _ in 0..<12 {
                let t = Int64(rng.int(0...(16 * unit * 3)))
                let ph = euclideousLanePhase(buf: buf, n: n, dir: .fwd, cycleLen: cl, sub: 0.5, tick: t, grid: g, legacySpanBeats: 0)
                XCTAssertEqual(euclideousFXLockPass(tick: t, cycleLen: cl, grid: g, localT: ph.localT), bruteLockPass(tick: t, cycleLen: cl, grid: g, buf: buf, n: n),
                               "n \(n) unit \(unit) rhythm \(g.rhythmMask) melody \(g.melodyMask) tick \(t)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 600)
    }
    func testAMelodyRestartSendsThePassBackToZeroInBothModes() {
        let buf = pattern([0, 3, 6], n: 8)
        // melody mark on cell 3 (tick 24), 8-tick cells: FREE and LOCK both start counting from the mark
        let g = EuclideousLaneRestartGrid(unitTicks: 8, rhythmMask: 0, melodyMask: 1 << 3)
        for locked in [false, true] {
            let before = euclideousFXPassIndex(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: 23, grid: g, legacySpanBeats: 0, locked: locked, advanceStep: false,
                                                riffDir: .forward, stride: 1, length: 8)
            let at = euclideousFXPassIndex(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: 24, grid: g, legacySpanBeats: 0, locked: locked, advanceStep: false,
                                            riffDir: .forward, stride: 1, length: 8)
            XCTAssertEqual(at, 0, "locked \(locked): at the melody mark the note is as written")
            XCTAssertGreaterThan(before, 0, "locked \(locked): and it had been climbing before it")
        }
    }
    func testPassIndexIsDeterministicInTheFirstWindowWithANegativeOrigin() {
        let buf = pattern([0, 3, 6], n: 8)
        let g = EuclideousLaneRestartGrid(unitTicks: 8, rhythmMask: 1 << 5, melodyMask: 1 << 2)   // no mark on cell 0 ⇒ window 0 runs from the previous window's marks
        for locked in [false, true] { for t in Int64(0)..<200 {
            let a = euclideousFXPassIndex(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: t, grid: g, legacySpanBeats: 0, locked: locked, advanceStep: false,
                                           riffDir: .forward, stride: 1, length: 8)
            let b = euclideousFXPassIndex(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: t, grid: g, legacySpanBeats: 0, locked: locked, advanceStep: false,
                                           riffDir: .forward, stride: 1, length: 8)
            XCTAssertEqual(a, b); XCTAssertGreaterThanOrEqual(a, 0)
        } }
    }
    func testPassIndexIsAFunctionOfTheBeatNotOfWhichHitsSounded() {
        // muting never shifts the climb: p depends only on the tick and the snapshot (LANES-muted hits advance the ordinal exactly as they do today)
        let buf = pattern([0, 3, 6], n: 8)
        let v1 = (0..<300).map { euclideousFXPassIndex(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: Int64($0), grid: .off, legacySpanBeats: 0, locked: false, advanceStep: false,
                                                       riffDir: .forward, stride: 1, length: 8) }
        let v2 = (0..<300).reversed().map { euclideousFXPassIndex(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: Int64($0), grid: .off, legacySpanBeats: 0, locked: false, advanceStep: false,
                                                                  riffDir: .forward, stride: 1, length: 8) }.reversed()
        XCTAssertEqual(v1, Array(v2))
    }

    // MARK: - UI maths (§15 "UI functions": cell marks, bubble text, preview strings, layout)

    func testLayoutRowsAndColumnsAreTheSpecsAndTheRiffGridsOwn() {
        let panelW: CGFloat = 416.9, w = panelW - 16
        let l = euclideousFXLayout(width: w, height: 260)   // PAGE LAYOUT ferry: rows share the height, (260 − 86) / 6 = 29 — the old fixed reference
        XCTAssertEqual(l.rowH, 29)
        XCTAssertEqual(l.headerTop, 28); XCTAssertEqual(l.rowTop(0), 46); XCTAssertEqual(l.rowTop(5), 46 + 33 * 5); XCTAssertEqual(l.rowTop(5) + l.rowH, 240)
        XCTAssertEqual(l.hintTop, 244); XCTAssertEqual(l.hintTop + EuclideousFXLayout.hintH, 260, "the reference stack is 260 tall")
        // the columns are the riff grid's: ONE function, label 30 + gap 4, then cellW with a 4pt column gap, ending at the content's right edge
        XCTAssertEqual(l.cellW, euclideousRiffCellW(maxWidth: panelW))
        for c in 0..<8 { XCTAssertEqual(l.colLeft(c), 34 + CGFloat(c) * (l.cellW + 4), accuracy: 1e-9) }
        XCTAssertEqual(l.colLeft(7) + l.cellW, w, accuracy: 1e-9)
        XCTAssertEqual(l.bandRect(row: 2), CGRect(x: -4, y: l.rowTop(2) - 2, width: w + 8, height: 33))
        // a shorter panel shares the missing height across the rows down to 24, then stops shrinking; a TALLER one now grows them (no 29pt cap)
        XCTAssertEqual(euclideousFXLayout(width: w, height: 230).rowH, 24, accuracy: 1e-9)
        XCTAssertEqual(euclideousFXLayout(width: w, height: 245).rowH, 29 - 15.0 / 6, accuracy: 1e-9)
        XCTAssertEqual(euclideousFXLayout(width: w, height: 100).rowH, 24)
        XCTAssertEqual(euclideousFXLayout(width: w, height: 272.3).rowH, (272.3 - 86) / 6, accuracy: 1e-9)
        XCTAssertEqual(euclideousFXLayout(width: w, height: 279).hintTop + EuclideousFXLayout.hintH, 279, accuracy: 1e-9, "the stack always ends at the content's bottom")
        // the spec's reference panel (410 wide): the strip stack is the same, cellW = (410 − 78) / 8
        XCTAssertEqual(euclideousFXLayout(width: 394, height: 280).cellW, (410 - 78) / 8.0, accuracy: 1e-9)
    }
    func testHitTestClaimsTheGapsAndTheRails() {
        let l = euclideousFXLayout(width: 400, height: 280)
        for r in 0..<6 { for c in 0..<8 {
            let rect = l.cellRect(row: r, col: c)
            XCTAssertEqual(euclideousFXHit(x: rect.midX, y: rect.midY, layout: l), .cell(row: r, col: c))
            XCTAssertEqual(euclideousFXHit(x: rect.minX - 1.9, y: rect.minY - 1.9, layout: l), .cell(row: r, col: c), "2pt into the gaps on every side")
            XCTAssertEqual(euclideousFXHit(x: rect.maxX + 1.9, y: rect.maxY + 1.9, layout: l), .cell(row: r, col: c))
        }
            XCTAssertEqual(euclideousFXHit(x: 10, y: l.railRect(row: r).midY, layout: l), .rail(row: r))
        }
        XCTAssertNil(euclideousFXHit(x: 100, y: l.headerTop + 2, layout: l), "the header is not a target")
        XCTAssertNil(euclideousFXHit(x: l.colLeft(7) + l.cellW + 2.5, y: l.rowTop(0) + 5, layout: l))
        // a stroke past either end keeps painting the edge cell
        XCTAssertEqual(euclideousFXColumn(x: -50, layout: l, clamped: true), 0); XCTAssertEqual(euclideousFXColumn(x: 5000, layout: l, clamped: true), 7)
    }
    func testCellMarksForEveryValueIncludingANarrowCell() {
        XCTAssertEqual(euclideousFXMark(row: 0, value: 3, cellW: 42), .ticks(count: 3))
        XCTAssertEqual(euclideousFXMark(row: 1, value: 50, cellW: 42), .gate(label: "50", barW: 28, fillW: 14))
        XCTAssertEqual(euclideousFXMark(row: 1, value: 95, cellW: 42), .gate(label: "95", barW: 28, fillW: 28 * 0.95), "the top value reads 95 — there is no LEG")
        XCTAssertEqual(euclideousFXMark(row: 1, value: 100, cellW: 42), .gate(label: "100", barW: 28, fillW: 28), "a raw 100 (never stored any more) is just a number")
        XCTAssertEqual(euclideousFXMark(row: 1, value: 5, cellW: 42), .gate(label: "5", barW: 28, fillW: 2), "the fill never drops under 2pt")
        XCTAssertEqual(euclideousFXMark(row: 2, value: 1, cellW: 42), .tie(arcW: 30))
        XCTAssertEqual(euclideousFXMark(row: 3, value: 127, cellW: 42), .bar(label: "127", barW: 28, fillW: 28))
        XCTAssertEqual(euclideousFXMark(row: 5, value: 0, cellW: 42), .bar(label: "0", barW: 28, fillW: 2))
        XCTAssertEqual(euclideousFXMark(row: 5, value: 20, cellW: 42), .bar(label: "20", barW: 28, fillW: 28 * 20 / 127))
        XCTAssertEqual(euclideousFXMark(row: 4, value: 1, cellW: 42), .step(label: "+1"))
        XCTAssertEqual(euclideousFXMark(row: 4, value: -2, cellW: 42), .step(label: "\u{2212}2"))
        // a narrow cell: the bar is min(28, cellW − 8), the arc min(30, cellW − 6)
        XCTAssertEqual(euclideousFXMark(row: 1, value: 50, cellW: 30), .gate(label: "50", barW: 22, fillW: 11))
        XCTAssertEqual(euclideousFXMark(row: 2, value: 1, cellW: 30), .tie(arcW: 24))
    }
    func testBubbleTextAndPlacement() {
        XCTAssertEqual(euclideousFXBubbleText(row: 0, value: 3, ccNumber: 74), "RATCH \u{00D7}3")
        XCTAssertEqual(euclideousFXBubbleText(row: 1, value: 50, ccNumber: 74), "GATE 50%")
        XCTAssertEqual(euclideousFXBubbleText(row: 1, value: 95, ccNumber: 74), "GATE 95%"); XCTAssertEqual(euclideousFXBubbleText(row: 1, value: 100, ccNumber: 74), "GATE 100%", "no LEGATO wording anywhere")
        XCTAssertEqual(euclideousFXBubbleText(row: 3, value: 110, ccNumber: 74), "VEL 110")
        XCTAssertEqual(euclideousFXBubbleText(row: 4, value: 1, ccNumber: 74), "NOTE +1 A PASS")
        XCTAssertEqual(euclideousFXBubbleText(row: 4, value: -2, ccNumber: 74), "NOTE \u{2212}2 A PASS")
        XCTAssertEqual(euclideousFXBubbleText(row: 5, value: 100, ccNumber: 74), "CC74 = 100")
        let l = euclideousFXLayout(width: 400, height: 280)
        let cell = l.cellRect(row: 3, col: 3)
        let b = euclideousFXBubble(text: "VEL 110", cell: cell, bounds: l.panelBounds)
        XCTAssertEqual(b.rect.height, 24); XCTAssertEqual(b.rect.width, (7 * 6.6).rounded(.up) + 18)
        XCTAssertEqual(b.rect.maxY, cell.minY - 7, accuracy: 1e-9, "bottom 7pt above the cell")
        XCTAssertEqual(b.rect.midX, cell.midX, accuracy: 1e-9); XCTAssertEqual(b.notchX, cell.midX, accuracy: 1e-9)
        // kept 6pt inside the panel at the edges, the notch staying on the cell
        let edge = euclideousFXBubble(text: "CC74 = 100", cell: l.cellRect(row: 5, col: 0), bounds: l.panelBounds)
        XCTAssertGreaterThanOrEqual(edge.rect.minX, l.panelBounds.minX + 6)
        XCTAssertGreaterThanOrEqual(edge.notchX, edge.rect.minX + 9); XCTAssertLessThanOrEqual(edge.notchX, edge.rect.maxX - 9)
        let far = euclideousFXBubble(text: "CC74 = 100", cell: l.cellRect(row: 5, col: 7), bounds: l.panelBounds)
        XCTAssertLessThanOrEqual(far.rect.maxX, l.panelBounds.maxX - 6)
    }
    func testValueDragStepsAndClamps() {
        // RATCH 18pt/step through 2–4
        XCTAssertEqual(euclideousFXDragValue(row: 0, start: 2, travelUp: 18), 3); XCTAssertEqual(euclideousFXDragValue(row: 0, start: 2, travelUp: 36), 4)
        XCTAssertEqual(euclideousFXDragValue(row: 0, start: 2, travelUp: 500), 4); XCTAssertEqual(euclideousFXDragValue(row: 0, start: 4, travelUp: -500), 2)
        XCTAssertEqual(euclideousFXDragValue(row: 0, start: 2, travelUp: 8), 2, "under half a step rounds back"); XCTAssertEqual(euclideousFXDragValue(row: 0, start: 2, travelUp: 10), 3)
        // GATE 5pt per 5%, 5–100
        XCTAssertEqual(euclideousFXDragValue(row: 1, start: 50, travelUp: 5), 55); XCTAssertEqual(euclideousFXDragValue(row: 1, start: 50, travelUp: -45), 5)
        XCTAssertEqual(euclideousFXDragValue(row: 1, start: 50, travelUp: 1000), 95, "the drag stops at 95"); XCTAssertEqual(euclideousFXDragValue(row: 1, start: 50, travelUp: -1000), 5)
        // VEL / CC 2pt per 1
        XCTAssertEqual(euclideousFXDragValue(row: 3, start: 100, travelUp: 20), 110); XCTAssertEqual(euclideousFXDragValue(row: 3, start: 100, travelUp: -1000), 1)
        XCTAssertEqual(euclideousFXDragValue(row: 5, start: 64, travelUp: -200), 0); XCTAssertEqual(euclideousFXDragValue(row: 5, start: 64, travelUp: 1000), 127)
        // NOTE 14pt per step through −3 −2 −1 +1 +2 +3 (never 0)
        XCTAssertEqual(euclideousFXDragValue(row: 4, start: 1, travelUp: -14), -1); XCTAssertEqual(euclideousFXDragValue(row: 4, start: -1, travelUp: 14), 1)
        XCTAssertEqual(euclideousFXDragValue(row: 4, start: 1, travelUp: 28), 3); XCTAssertEqual(euclideousFXDragValue(row: 4, start: 1, travelUp: 700), 3); XCTAssertEqual(euclideousFXDragValue(row: 4, start: 1, travelUp: -700), -3)
        // VoiceOver's one-step adjust
        XCTAssertEqual(euclideousFXAdjust(row: 4, current: -1, brush: 1, up: true), 1, "NOTE skips 0")
        XCTAssertEqual(euclideousFXAdjust(row: 0, current: nil, brush: 2, up: true), 2, "incrementing an empty cell turns it on at the brush")
        XCTAssertNil(euclideousFXAdjust(row: 0, current: nil, brush: 2, up: false)); XCTAssertNil(euclideousFXAdjust(row: 2, current: 1, brush: 1, up: true), "TIE isn't adjustable")
        XCTAssertEqual(euclideousFXAdjust(row: 1, current: 50, brush: 50, up: false), 45); XCTAssertNil(euclideousFXAdjust(row: 1, current: 95, brush: 50, up: true), "95 is the top"); XCTAssertEqual(euclideousFXAdjust(row: 1, current: 90, brush: 50, up: true), 95)
        XCTAssertEqual(euclideousFXAdjust(row: 3, current: 100, brush: 100, up: true), 101)
    }
    func testSteppersNeverWrapAndBaseStepsThroughItsStops() {
        XCTAssertEqual(euclideousFXStepperStep(.passes, current: 4, up: true), 5); XCTAssertNil(euclideousFXStepperStep(.passes, current: 8, up: true)); XCTAssertNil(euclideousFXStepperStep(.passes, current: 2, up: false))
        XCTAssertEqual(euclideousFXStepperStep(.ccNumber, current: 74, up: false), 73); XCTAssertNil(euclideousFXStepperStep(.ccNumber, current: 119, up: true)); XCTAssertNil(euclideousFXStepperStep(.ccNumber, current: 0, up: false))
        XCTAssertEqual(euclideousFXStepperStep(.base, current: -1, up: true), 0); XCTAssertEqual(euclideousFXStepperStep(.base, current: 0, up: true), 32)
        XCTAssertEqual(euclideousFXStepperStep(.base, current: 50, up: true), 64, "from in between › goes to the next listed value up"); XCTAssertEqual(euclideousFXStepperStep(.base, current: 50, up: false), 32)
        XCTAssertEqual(euclideousFXStepperStep(.base, current: 127, up: false), 96); XCTAssertNil(euclideousFXStepperStep(.base, current: 127, up: true)); XCTAssertNil(euclideousFXStepperStep(.base, current: -1, up: false))
        // drags: PASSES 12pt a step, CC and BASE 2pt (BASE's – is one below 0)
        XCTAssertEqual(euclideousFXStepperDrag(.passes, start: 4, travelUp: 24), 6); XCTAssertEqual(euclideousFXStepperDrag(.passes, start: 4, travelUp: -1000), 2)
        XCTAssertEqual(euclideousFXStepperDrag(.ccNumber, start: 74, travelUp: 10), 79); XCTAssertEqual(euclideousFXStepperDrag(.ccNumber, start: 74, travelUp: 1000), 119)
        XCTAssertEqual(euclideousFXStepperDrag(.base, start: 0, travelUp: -2), -1); XCTAssertEqual(euclideousFXStepperDrag(.base, start: 0, travelUp: -100), -1); XCTAssertEqual(euclideousFXStepperDrag(.base, start: 126, travelUp: 100), 127)
        XCTAssertEqual([EuclideousFXStepper.passes, .ccNumber, .base].map { euclideousFXStepperDefault($0) }, [4, 74, -1])
        XCTAssertEqual(euclideousFXStepperValueText(.base, value: -1), "–"); XCTAssertEqual(euclideousFXStepperValueText(.base, value: 64), "64")
        var fx = EuclideousFX()
        euclideousFXSetStepper(&fx, .passes, value: 99); euclideousFXSetStepper(&fx, .ccNumber, value: 300); euclideousFXSetStepper(&fx, .base, value: 500)
        XCTAssertEqual([fx.notePasses, fx.ccNumber], [8, 119]); XCTAssertEqual(fx.ccBase, 127)
        euclideousFXSetStepper(&fx, .base, value: -1); XCTAssertEqual(fx.ccBase, -1)
    }
    func testCellEditsTapLaneToggleAndDoubleTapWindow() {
        var fx = EuclideousFX()
        euclideousFXTapCell(&fx, row: 0, col: 3, brush: 2); XCTAssertEqual(fx.cell(row: 0, column: 3), 2)
        euclideousFXTapCell(&fx, row: 0, col: 3, brush: 2); XCTAssertNil(fx.cell(row: 0, column: 3))
        euclideousFXSetCell(&fx, row: 1, col: 0, value: 52); XCTAssertEqual(fx.cell(row: 1, column: 0), 50, "clamped to the row's legal domain")
        euclideousFXSetCell(&fx, row: 4, col: 0, value: 0); XCTAssertNil(fx.cell(row: 4, column: 0), "NOTE 0 is empty")
        euclideousFXToggleLane(&fx, row: 2, lane: 1); XCTAssertFalse(fx.laneOn(row: 2, lane: 1)); XCTAssertEqual(fx.lanes[2], 0b1101)
        euclideousFXToggleLane(&fx, row: 2, lane: 1); XCTAssertEqual(fx.lanes[2], 0b1111)
        XCTAssertTrue(euclideousFXIsDoubleTap(previous: (0, 3, 10.0), row: 0, col: 3, time: 10.31))
        XCTAssertFalse(euclideousFXIsDoubleTap(previous: (0, 3, 10.0), row: 0, col: 3, time: 10.33), "past 320 ms")
        XCTAssertFalse(euclideousFXIsDoubleTap(previous: (0, 3, 10.0), row: 0, col: 4, time: 10.1), "a different cell")
        XCTAssertFalse(euclideousFXIsDoubleTap(previous: nil, row: 0, col: 3, time: 10.1))
    }
    func testTouchReducerTapPaintAndValueDragWithTheEightPointAxisLock() {
        let l = euclideousFXLayout(width: 400, height: 280)
        func touch(_ row: Int, _ col: Int, value: Int?, brush: Int) -> (EuclideousFXTouch, CGPoint) {
            let r = l.cellRect(row: row, col: col); let p = CGPoint(x: r.midX, y: r.midY)
            return (EuclideousFXTouch(point: p, row: row, col: col, cellValue: value, brush: brush), p)
        }
        // under 8pt of travel is a tap
        var (t, p) = touch(0, 3, value: nil, brush: 2)
        XCTAssertTrue(t.moved(to: CGPoint(x: p.x + 7.9, y: p.y), layout: l).isEmpty); XCTAssertTrue(t.moved(to: CGPoint(x: p.x, y: p.y - 7.9), layout: l).isEmpty)
        XCTAssertEqual(t.ended(), [.tap(row: 0, col: 3)])
        // horizontal: paint — the stroke's value is the OPPOSITE of the first cell (empty ⇒ on); every cell crossed takes it, in order, even a fast finger's skipped ones
        (t, p) = touch(0, 3, value: nil, brush: 2)
        var ev = t.moved(to: CGPoint(x: l.cellRect(row: 0, col: 5).midX, y: p.y), layout: l)
        XCTAssertEqual(ev, [.paint(row: 0, col: 3, on: true), .paint(row: 0, col: 4, on: true), .paint(row: 0, col: 5, on: true)])
        ev = t.moved(to: CGPoint(x: l.cellRect(row: 0, col: 4).midX, y: p.y + 30), layout: l)
        XCTAssertEqual(ev, [.paint(row: 0, col: 4, on: true)], "back over a cell paints it again; drifting vertically stays in the touched row")
        XCTAssertTrue(t.ended().isEmpty)
        // a stroke from a lit cell clears
        (t, p) = touch(1, 6, value: 50, brush: 50)
        ev = t.moved(to: CGPoint(x: p.x - 60, y: p.y), layout: l)
        XCTAssertEqual(ev.first, .paint(row: 1, col: 6, on: false)); XCTAssertTrue(ev.allSatisfy { if case .paint(_, _, let on) = $0 { return !on } else { return false } })
        // vertical on a value row locks to a value drag; travel counts from the LOCK point; an empty cell starts at the brush
        (t, p) = touch(3, 2, value: nil, brush: 100)
        ev = t.moved(to: CGPoint(x: p.x + 1, y: p.y - 8), layout: l)
        XCTAssertEqual(ev, [.value(row: 3, col: 2, value: 100)]); XCTAssertEqual(t.draggedValue, 100)
        ev = t.moved(to: CGPoint(x: p.x + 1, y: p.y - 8 - 20), layout: l)
        XCTAssertEqual(ev, [.value(row: 3, col: 2, value: 110)], "20pt past the lock = +10 at 2pt per step"); XCTAssertEqual(t.draggedValue, 110)
        XCTAssertTrue(t.moved(to: CGPoint(x: p.x + 1, y: p.y - 8 - 20), layout: l).isEmpty, "no change, no event")
        XCTAssertTrue(t.ended().isEmpty)
        // the lock goes to whichever component is larger; a tie goes horizontal; TIE paints even when the drag is vertical
        (t, p) = touch(4, 2, value: 1, brush: 1)
        XCTAssertEqual(t.moved(to: CGPoint(x: p.x + 8, y: p.y - 8), layout: l).first, .paint(row: 4, col: 2, on: false), "equal components ⇒ horizontal")
        (t, p) = touch(2, 2, value: nil, brush: 1)
        XCTAssertEqual(t.moved(to: CGPoint(x: p.x, y: p.y - 30), layout: l), [.paint(row: 2, col: 2, on: true)], "TIE has no value drag")
    }
    func testNotePreviewNamesTheMovedRanksThroughTheFold() {
        var fx = EuclideousFX()
        fx.cells[4 * 8 + 3] = 1                                                          // NOTE +1 on column 4 (index 3), PASSES 4
        let ranks = [1, 1, 1, 4, 1, 1, 1, 1]
        let triad = [48, 51, 55]
        XCTAssertEqual(euclideousFXNotePreviewText(fx: fx, touched: nil, ranks: ranks, pool: triad, name: { "\($0)" }), "60 › 63 › 67 › 72", "C4 › E♭4 › G4 › C5")
        // nothing held: the moved rank numbers
        XCTAssertEqual(euclideousFXNotePreviewText(fx: fx, touched: nil, ranks: ranks, pool: [], name: { "\($0)" }), "4 › 5 › 6 › 7")
        fx.cells[4 * 8 + 0] = -1; fx.notePasses = 3
        XCTAssertEqual(euclideousFXNotePreviewText(fx: fx, touched: 0, ranks: ranks, pool: [], name: { "\($0)" }), "1 › 0 › \u{2212}1")
        XCTAssertEqual(euclideousFXNotePreviewText(fx: fx, touched: 0, ranks: ranks, pool: triad, name: { "\($0)" }), "48 › 43 › 39", "rank 0 is G2 and rank −1 is E♭2: never a rest")
        // the touched cell wins; an empty or rest cell falls back to the leftmost NOTE cell on a non-rest column
        XCTAssertEqual(euclideousFXPreviewColumn(touched: 3, fx: fx, ranks: ranks), 3)
        XCTAssertEqual(euclideousFXPreviewColumn(touched: 5, fx: fx, ranks: ranks), 0)
        XCTAssertEqual(euclideousFXPreviewColumn(touched: 0, fx: fx, ranks: [0, 1, 1, 4, 1, 1, 1, 1]), 3, "a rest column is skipped")
        XCTAssertNil(euclideousFXPreviewColumn(touched: nil, fx: EuclideousFX(), ranks: ranks))
        XCTAssertEqual(euclideousFXNotePreviewText(fx: EuclideousFX(), touched: nil, ranks: ranks, pool: triad, name: { "\($0)" }), "NO STEPS YET")
    }
    func testHeaderLabelsNameTheRankLikeTheRiffGridsLabelColumn() {
        let name: (Int) -> String = { "n\($0)" }
        XCTAssertEqual(euclideousFXHeaderLabel(rank: 0, pool: [48, 51, 55], name: name).text, "–"); XCTAssertTrue(euclideousFXHeaderLabel(rank: 0, pool: [48], name: name).rest)
        XCTAssertEqual(euclideousFXHeaderLabel(rank: 2, pool: [48, 51, 55], name: name).text, "n51")
        XCTAssertEqual(euclideousFXHeaderLabel(rank: 4, pool: [48, 51, 55], name: name).text, "n60", "the octave-extended note, exactly as the label column shows rank 4")
        XCTAssertEqual(euclideousFXHeaderLabel(rank: 4, pool: [], name: name).text, "4", "nothing held ⇒ rank numbers"); XCTAssertFalse(euclideousFXHeaderLabel(rank: 4, pool: [], name: name).rest)
    }
    func testVoiceOverStrings() {
        XCTAssertEqual(euclideousFXLanesPhrase(mask: 0b1111), "all lanes"); XCTAssertEqual(euclideousFXLanesPhrase(mask: 0), "no lanes")
        XCTAssertEqual(euclideousFXLanesPhrase(mask: 0b0100), "lane 3"); XCTAssertEqual(euclideousFXLanesPhrase(mask: 0b0011), "lanes 1 and 2")
        XCTAssertEqual(euclideousFXLanesPhrase(mask: 0b0111), "lanes 1, 2 and 3"); XCTAssertEqual(euclideousFXLanesPhrase(mask: 0b1010), "lanes 2 and 4")
        XCTAssertEqual(euclideousFXRailLabel(row: 0, ccNumber: 74, mask: 0b0011, selected: true), "FX row, ratchet, lanes 1 and 2, selected")
        XCTAssertEqual(euclideousFXRailLabel(row: 5, ccNumber: 74, mask: 0b1111, selected: false), "FX row, controller 74, all lanes")
        XCTAssertEqual(euclideousFXRailLabel(row: 4, ccNumber: 74, mask: 0, selected: false), "FX row, note step, no lanes")
        XCTAssertEqual(euclideousFXLaneGroupLabel(row: 0, ccNumber: 74), "Lanes that play the ratchet row")
        XCTAssertEqual(euclideousFXLaneGroupLabel(row: 5, ccNumber: 74), "Lanes that play the controller 74 row")
        XCTAssertEqual(euclideousFXLaneButtonLabel(lane: 0, on: true), "Lane 1, plays this row"); XCTAssertEqual(euclideousFXLaneButtonLabel(lane: 3, on: false), "Lane 4, ignores this row")
        XCTAssertEqual(euclideousFXCellLabel(row: 1, ccNumber: 74, column: 5, noteName: nil, value: nil), "Note 6, rest, gate off")
        XCTAssertEqual(euclideousFXCellLabel(row: 0, ccNumber: 74, column: 0, noteName: "C3", value: 2), "Note 1, C3, ratchet 2")
        XCTAssertEqual(euclideousFXCellLabel(row: 1, ccNumber: 74, column: 0, noteName: "C3", value: 25), "Note 1, C3, gate 25 percent")
        XCTAssertEqual(euclideousFXCellLabel(row: 1, ccNumber: 74, column: 0, noteName: "C3", value: 95), "Note 1, C3, gate 95 percent")
        XCTAssertEqual(euclideousFXCellLabel(row: 2, ccNumber: 74, column: 0, noteName: "C3", value: 1), "Note 1, C3, tie on")
        XCTAssertEqual(euclideousFXCellLabel(row: 3, ccNumber: 74, column: 0, noteName: "C3", value: 110), "Note 1, C3, velocity 110")
        XCTAssertEqual(euclideousFXCellLabel(row: 4, ccNumber: 74, column: 0, noteName: "C3", value: 1), "Note 1, C3, note step plus 1 per pass")
        XCTAssertEqual(euclideousFXCellLabel(row: 4, ccNumber: 74, column: 0, noteName: "C3", value: -2), "Note 1, C3, note step minus 2 per pass")
        XCTAssertEqual(euclideousFXCellLabel(row: 5, ccNumber: 74, column: 0, noteName: "C3", value: 20), "Note 1, C3, controller 74 value 20")
        XCTAssertEqual(euclideousFXCellLabel(row: 5, ccNumber: 74, column: 0, noteName: "C3", value: nil), "Note 1, C3, controller 74 off")
        XCTAssertEqual(euclideousFXStepperSpoken(.passes, value: 4), "Passes 4"); XCTAssertEqual(euclideousFXStepperSpoken(.ccNumber, value: 74), "Controller number 74")
        XCTAssertEqual(euclideousFXStepperSpoken(.base, value: -1), "Base value none"); XCTAssertEqual(euclideousFXStepperSpoken(.base, value: 64), "Base value 64")
    }
    func testDimmingAndStripTexts() {
        XCTAssertEqual(euclideousFXCellOpacity(restColumn: false, rowHasLanes: true), 1); XCTAssertEqual(euclideousFXCellOpacity(restColumn: true, rowHasLanes: true), 0.42)
        XCTAssertEqual(euclideousFXCellOpacity(restColumn: true, rowHasLanes: false), 0.42 * 0.42, accuracy: 1e-12, "the two dims multiply")
        XCTAssertEqual(EuclideousFXRow.cc.railName(ccNumber: 74), "CC74"); XCTAssertEqual(EuclideousFXRow.ratch.railName(ccNumber: 74), "RATCH")
        XCTAssertEqual(EuclideousFXRow.gate.stripDescription, "REPLACES THE LANE\u{2019}S GATE"); XCTAssertNil(EuclideousFXRow.note.stripDescription); XCTAssertNil(EuclideousFXRow.cc.stripDescription)
        XCTAssertEqual(EuclideousSeqTab.visible(fxAvailable: true), [.mix, .lanes, .fx]); XCTAssertEqual(EuclideousSeqTab.visible(fxAvailable: false), [.mix, .lanes])
        XCTAssertEqual(EuclideousSeqTab.fx.label, "FX")
    }
    func testFiringFlashFollowsTheHitEventsColumnAndTheRowsThatApplied() {
        var fx = EuclideousFX()
        fx.cells[0 * 8 + 3] = 3; fx.cells[3 * 8 + 3] = 110; fx.cells[2 * 8 + 5] = 1            // RATCH + VEL on column 4; a TIE on column 6
        fx.lanes[3] = 0b0001                                                                  // VEL only for lane 1
        let lines = (0..<4).map { _ in EuclidLine(pulses: 3, steps: 8, riffOn: true) }
        // PULSE ferry §8.1: the flash reads the feed's riff strikes — column, played velocity, onset on the display clock — and takes §1's f for that velocity
        func st(_ col: Int8, at: Double, vel: UInt8 = 100) -> EuclideousPulseStrike { EuclideousPulseStrike(onsetBeat: at * 2, onsetAt: at, riffVel: vel, notesVel: 0, rank: 1, column: col) }
        let ranks = [1, 2, 3, 4, 5, 6, 7, 8]
        let now = 10.05
        let cells = euclideousFXFlashCells(fx: fx, lines: lines, strikes: [st(3, at: 10), st(3, at: 10.02), nil, st(5, at: 10)], ranks: ranks, now: now, scale: 1)
        XCTAssertEqual(cells[0 * 8 + 3]?.lane, 1, "RATCH is on for lanes 1 and 2; lane 2's hit is the later one and takes the cell over")
        XCTAssertEqual(cells[3 * 8 + 3]?.lane, 0, "VEL only applies to lane 1")
        XCTAssertNil(cells[2 * 8 + 5], "TIE never flashes (a tied hit posts no event, and the function says TIE hits apply nothing else)")
        XCTAssertNil(cells[1 * 8 + 3]); XCTAssertEqual(cells.compactMap { $0 }.count, 2)
        // the opacity is the strike's flash f at its velocity, 0.05 s after the onset — and a harder hit flashes harder
        XCTAssertEqual(cells[3 * 8 + 3]?.intensity ?? 0, euclideousPulseEnvelopes(velocity: 100, seconds: 0.05, scale: 1).f, accuracy: 1e-9)
        let soft = euclideousFXFlashCells(fx: fx, lines: lines, strikes: [st(3, at: 10, vel: 30), nil, nil, nil], ranks: ranks, now: now, scale: 1)
        XCTAssertLessThan(soft[3 * 8 + 3]?.intensity ?? 9, cells[3 * 8 + 3]?.intensity ?? 0)
        XCTAssertTrue(euclideousFXFlashCells(fx: fx, lines: lines, strikes: [st(3, at: 10), nil, nil, nil], ranks: ranks, now: 11.6, scale: 1).allSatisfy { $0 == nil }, "gone after 1.5 s")
        XCTAssertTrue(euclideousFXFlashCells(fx: fx, lines: lines, strikes: [st(3, at: 10), nil, nil, nil], ranks: ranks, now: 9.9, scale: 1).allSatisfy { $0 == nil }, "a strike still in the future reads nothing")
        XCTAssertTrue(euclideousFXFlashCells(fx: fx, lines: lines, strikes: [st(3, at: 10), nil, nil, nil], ranks: ranks, now: now, scale: 0).allSatisfy { $0 == nil }, "PULSE OFF")
        // a lane with its riff off, a rest column, a notes-only strike and a no-column event flash nothing
        var off = lines; off[0].riffOn = false
        XCTAssertTrue(euclideousFXFlashCells(fx: fx, lines: off, strikes: [st(3, at: 10), nil, nil, nil], ranks: ranks, now: now, scale: 1).allSatisfy { $0 == nil })
        XCTAssertTrue(euclideousFXFlashCells(fx: fx, lines: lines, strikes: [st(3, at: 10), nil, nil, nil], ranks: [1, 2, 3, 0, 5, 6, 7, 8], now: now, scale: 1).allSatisfy { $0 == nil })
        XCTAssertTrue(euclideousFXFlashCells(fx: fx, lines: lines, strikes: [st(-1, at: 10), nil, nil, nil], ranks: ranks, now: now, scale: 1).allSatisfy { $0 == nil })
        var notesOnly = st(3, at: 10); notesOnly.riffVel = 0; notesOnly.notesVel = 90
        XCTAssertTrue(euclideousFXFlashCells(fx: fx, lines: lines, strikes: [notesOnly, nil, nil, nil], ranks: ranks, now: now, scale: 1).allSatisfy { $0 == nil }, "the FX rows act on the riff's hit")
    }

    // MARK: - ADVERSARIAL REVIEW (2026-10-19)

    func testOneUnreadableElementIsOneEmptyCellNotALostArray() {
        // a string, a null and a fractional number among good values: only the bad elements are affected (§1.6 "any value that can't be read is empty")
        let json = #"{"lanes":[15,"x",3,null,15,15],"cells":[2,"bad",null,3,52.5,4,1],"notePasses":"many","ccNumber":300,"ccBase":"none"}"#
        let fx = try! JSONDecoder().decode(EuclideousFX.self, from: Data(json.utf8))
        XCTAssertEqual(fx.cell(row: 0, column: 0), 2, "the readable value before the bad ones survives")
        XCTAssertNil(fx.cell(row: 0, column: 1)); XCTAssertNil(fx.cell(row: 0, column: 2))
        XCTAssertEqual(fx.cell(row: 0, column: 3), 3, "…and the readable one after them")
        XCTAssertEqual(fx.cell(row: 0, column: 4), 4, "52.5 reads as 53 and RATCH clamps to 4"); XCTAssertEqual(fx.cell(row: 0, column: 5), 4)
        XCTAssertEqual(fx.cell(row: 0, column: 6), 2, "RATCH 1 clamps up to 2")
        XCTAssertEqual(fx.lanes[0], 15); XCTAssertEqual(fx.lanes[1], 15, "an unreadable lane set keeps its default, all four on"); XCTAssertEqual(fx.lanes[2], 3)
        XCTAssertEqual(fx.lanes[3], 15)
        XCTAssertEqual(fx.notePasses, 4, "an unreadable setting keeps its default"); XCTAssertEqual(fx.ccNumber, 119, "300 clamps to 119"); XCTAssertEqual(fx.ccBase, -1)
        // not an array at all: the whole field falls back to its defaults, and the document still loads
        let broken = try! JSONDecoder().decode(EuclideousFX.self, from: Data(#"{"cells":"nope","lanes":7}"#.utf8))
        XCTAssertEqual(broken, EuclideousFX())
    }
    func testAFooterHitOnAnFXTiedColumnReadsAsAHitOnATiedRest() {
        let hitSteps = euclideousLapHitSteps(pulses: 3, steps: 8, rotate: 0, tilt: 0, patternMiss: false, customHits: nil, dir: .fwd)
        let ranks = [1, 2, 3, 4, 5, 6, 7, 8]
        let prediction = [0, 1, 2]                                   // the walk reads columns 0, 1, 2 this lap → riff steps 1, 2, 3
        let plain = euclideousFooterStates(hitSteps: hitSteps, lapSteps: 8, prediction: prediction, riffRanksResolved: ranks)
        XCTAssertTrue(plain.contains { if case .hit = $0 { return true } else { return false } })
        var fx = EuclideousFX(); fx.cells[2 * 8 + 1] = 1             // TIE on column 2 (index 1)
        var line = EuclidLine(pulses: 3, steps: 8); line.riffOn = true
        let tied = euclideousFooterStates(hitSteps: hitSteps, lapSteps: 8, prediction: prediction.map { $0 + 1 }, riffRanksResolved: ranks, fxTieColumns: euclideousFXTieColumns(fx, line: line, lane: 0))
        XCTAssertEqual(tied.filter { if case .hitTied = $0 { return true } else { return false } }.count, 1, "exactly the hit that reads column 2")
        XCTAssertTrue(tied.contains(.hitTied(riffStep: 2)))
        // a rest column stays a plain hit-on-rest; a lane with the riff off, a lane off the TIE row, and an SHADOW lane show nothing tied
        XCTAssertEqual(euclideousFXTieColumns(fx, line: { var l = line; l.riffOn = false; return l }(), lane: 0), 0)
        var off = fx; off.lanes[2] = 0b1110; XCTAssertEqual(euclideousFXTieColumns(off, line: line, lane: 0), 0); XCTAssertEqual(euclideousFXTieColumns(off, line: line, lane: 1), 0b10)
        XCTAssertEqual(euclideousFXTieColumns(fx, line: { var l = line; l.listenPitchMode = .shadow; return l }(), lane: 0), 0)
        let restRanks = [1, 0, 3, 4, 5, 6, 7, 8]
        XCTAssertTrue(euclideousFooterStates(hitSteps: hitSteps, lapSteps: 8, prediction: prediction.map { $0 + 1 }, riffRanksResolved: restRanks, fxTieColumns: 0b10).contains(.hitOnRest(riffStep: 2)))
        // the comet flash for a tied hit is the OUTLINE (a hit that plays nothing new), even on a lane whose ON REST is FILL
        XCTAssertEqual(euclideousHitFlashStyle(footerState: .hitTied(riffStep: 2), onRest: .fill), .outline)
        XCTAssertEqual(euclideousHitFlashStyle(footerState: .hitOnRest(riffStep: 2), onRest: .fill), .solid, "a FILL rest still strikes")
    }
}
