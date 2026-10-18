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
}
