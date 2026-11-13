//  EuclideousCCSlotsTests.swift — CC SLOTS ferry (2026-11-12), slice 1: the model — three slots per emitter, the
//  driverLane field, the §1.4 stepper skip, and the round-trip / no-migration rules (§7 tests 1–2).

import XCTest

final class EuclideousCCSlotsTests: XCTestCase {

    // §1.1/§1.2 — four outputs × FOUR slots (widened 2026-11-13); defaults a/b/c/d = 74/71/1/11 on every output; off; driverLane nil.
    func testFourSlotsPerEmitterAndDefaults() {
        XCTAssertEqual(EmitterCCSet.outputCount, 4); XCTAssertEqual(EmitterCCSet.slotsPerEmitter, 4); XCTAssertEqual(EmitterCCSet.count, 16)
        let set = EmitterCCSet()
        for o in 0..<4 {
            XCTAssertEqual((0..<4).map { set[output: o, slot: $0].ccNumber }, [74, 71, 1, 11])
            for s in 0..<4 { XCTAssertFalse(set[output: o, slot: s].on); XCTAssertNil(set[output: o, slot: s].driverLane) }
        }
        XCTAssertTrue(set.isAllDefault)
    }

    // §1.1 — the flat index and the (output, slot) subscript agree: i = output*4 + slot.
    func testFlatAndTwoDSubscriptsAgree() {
        var set = EmitterCCSet()
        set[output: 2, slot: 1] = EmitterCC(on: true, ccNumber: 40, driverLane: 3)
        XCTAssertEqual(set[9].ccNumber, 40, "output 2 slot 1 = flat index 9"); XCTAssertTrue(set[9].on); XCTAssertEqual(set[9].driverLane, 3)
    }

    // §1.1 — driverLane clamps to 1…4 (nil stays nil).
    func testDriverLaneClampsAndRoundTrips() throws {
        var e = EmitterCC(driverLane: 9).normalized(); XCTAssertEqual(e.driverLane, 4)
        e = EmitterCC(driverLane: 0).normalized(); XCTAssertEqual(e.driverLane, 1)
        XCTAssertNil(EmitterCC().normalized().driverLane)
        var set = EmitterCCSet(); set[output: 1, slot: 2] = EmitterCC(on: true, ccNumber: 20, valueMode: .riff, driverLane: 2)
        let back = try JSONDecoder().decode(EmitterCCSet.self, from: JSONEncoder().encode(set))
        XCTAssertEqual(back, set, "the 12 slots + driverLane round-trip through Codable")
    }

    // §1.3 — NO MIGRATION: an old 4-wide document (or anything not exactly 12) loads the defaults.
    func testOldFourWideDocumentLoadsDefaults() throws {
        let fourWide = try JSONEncoder().encode([EmitterCC(on: true, ccNumber: 50), EmitterCC(on: true, ccNumber: 51), EmitterCC(on: true, ccNumber: 52), EmitterCC(on: true, ccNumber: 11)])
        let back = try JSONDecoder().decode(EmitterCCSet.self, from: fourWide)
        XCTAssertTrue(back.isAllDefault, "a 4-entry blob is not 12 ⇒ defaults (no migration)")
    }

    // §4 / test 7 — the rows layout (widened + spread 2026-11-13): 4 rows filling the panel height, 8 apart, 10 top/bottom, 12 pad;
    // tile 36 + 6 gap + FOUR cells side by side, 6 apart; within a cell the big number (top half) over the trace (below).
    func testRowsLayout() {
        let panel = CGSize(width: 390, height: 332)
        let r0 = euclideousCCRowRect(0, panel: panel), r1 = euclideousCCRowRect(1, panel: panel)
        XCTAssertEqual(r0.minX, 12); XCTAssertEqual(r0.minY, 10); XCTAssertEqual(r0.width, 390 - 24)
        XCTAssertEqual(r0.height, (332 - 20 - 8 * 3) / 4, accuracy: 1e-6, "four rows fill the panel height")  // 72
        XCTAssertEqual(r1.minY - r0.maxY, 8, "rows 8 apart")
        let L = euclideousCCRowLayout(rowWidth: r0.width, rowHeight: r0.height)
        XCTAssertEqual(L.tile, CGRect(x: 0, y: 0, width: 36, height: r0.height))
        XCTAssertEqual(L.cells.count, 4)
        XCTAssertEqual(L.cells[0].minX, 36 + 6, "cells start after the tile + 6 gap")
        XCTAssertEqual(L.cells[0].height, r0.height, "a cell is the full row height")
        XCTAssertEqual(L.cells[1].minX - L.cells[0].maxX, 6, accuracy: 1e-6, "cells 6 apart")
        XCTAssertEqual(L.cells[3].maxX, r0.width, accuracy: 1e-6, "four cells + three 6-gaps fill the row width")
        // within a cell: the number is the top half, the trace fills below.
        let split = euclideousCCCellSplit(cellSize: L.cells[0].size)
        XCTAssertEqual(split.number.minY, 2); XCTAssertEqual(split.number.width, L.cells[0].width)
        XCTAssertEqual(split.trace.maxY, L.cells[0].height, accuracy: 1e-6, "the trace fills to the cell bottom")
        XCTAssertGreaterThan(split.number.maxY, split.trace.minY - 2, "the number sits above the trace")
        // the big number is much larger than the old 11 pt chip and never smaller than 14.
        XCTAssertGreaterThanOrEqual(euclideousCCNumberFontSize(cellSize: L.cells[0].size), 24)
        XCTAssertGreaterThanOrEqual(euclideousCCNumberFontSize(cellSize: CGSize(width: 44, height: 48)), 14, "a tight cell still fits at the floor font")
        XCTAssertLessThanOrEqual(euclideousCCNumberFontSize(cellSize: CGSize(width: 44, height: 48)), 30)
        // a narrower panel: the cells shrink, the tile keeps its size.
        let narrow = euclideousCCRowLayout(rowWidth: 240, rowHeight: 60)
        XCTAssertEqual(narrow.tile.width, 36); XCTAssertEqual(narrow.cells.count, 4)
        XCTAssertEqual(narrow.cells[3].maxX, 240, accuracy: 1e-6)
        XCTAssertEqual(euclideousCCBandAX(output: 0, cc: 74, driverLane: 1, on: true), "Output A, CC 74, lane 1, on")
    }

    // §2.1 / test 3 — the driver: nil follows routing (one routed lane ⇒ it; none or several ⇒ slot+1); a set lane wins.
    func testDriverResolution() {
        let none = SIMD4<UInt8>(repeating: 0)
        // nil, nothing routed to output 0 ⇒ slot+1 (a→1, b→2, c→3, d→4).
        XCTAssertEqual((0..<4).map { euclideousCCDriver(emitter: 0, slot: $0, driverLane: nil, laneRoutes: none) }, [1, 2, 3, 4])
        // only lane 3 (index 2) routed to output 0 ⇒ every slot drives lane 3.
        var one = none; one[2] = 0b0001
        XCTAssertEqual((0..<4).map { euclideousCCDriver(emitter: 0, slot: $0, driverLane: nil, laneRoutes: one) }, [3, 3, 3, 3])
        // lanes 2 and 4 (indices 1, 3) routed ⇒ several ⇒ slot+1.
        var two = none; two[1] = 0b0001; two[3] = 0b0001
        XCTAssertEqual((0..<4).map { euclideousCCDriver(emitter: 0, slot: $0, driverLane: nil, laneRoutes: two) }, [1, 2, 3, 4])
        // a SET driver ignores routing.
        XCTAssertEqual(euclideousCCDriver(emitter: 0, slot: 0, driverLane: 4, laneRoutes: one), 4)
        // routing to a DIFFERENT output doesn't count: lane 1 routed to output 1 only ⇒ output 0 still slot+1.
        var other = none; other[0] = 0b0010
        XCTAssertEqual((0..<4).map { euclideousCCDriver(emitter: 0, slot: $0, driverLane: nil, laneRoutes: other) }, [1, 2, 3, 4])
    }

    // §1.4 / test 2 — the stepper skips the output's other three slots' numbers, wrapping at 0 and 119.
    func testStepperSkipsOtherSlots() {
        var set = EmitterCCSet()   // output A: a=74, b=71, c=1, d=11
        // slot a stepping DOWN from 72 lands on 70 (71 is taken by b); UP from 70 lands on 72.
        XCTAssertEqual(set.nextCCNumber(from: 72, output: 0, slot: 0, up: false), 70)
        XCTAssertEqual(set.nextCCNumber(from: 70, output: 0, slot: 0, up: true), 72)
        // wrap at 119 → 0, skipping a slot sitting at 0: put b=119, c=0, step a up from 118 → lands on 1 (skips 119 and 0).
        set[output: 0, slot: 1] = EmitterCC(ccNumber: 119); set[output: 0, slot: 2] = EmitterCC(ccNumber: 0)
        XCTAssertEqual(set.nextCCNumber(from: 118, output: 0, slot: 0, up: true), 1)
        // wrap at 0 → 119 downward, skipping 119: step a down from 1 (c=0 taken) → 118 (skips 0 and 119).
        XCTAssertEqual(set.nextCCNumber(from: 1, output: 0, slot: 0, up: false), 118)
        // a different output may share a number: output B's slots don't constrain output A (fresh set: A a/b/c = 74/71/1, B a = 70).
        var set2 = EmitterCCSet(); set2[output: 1, slot: 0] = EmitterCC(ccNumber: 70)
        XCTAssertEqual(set2.nextCCNumber(from: 72, output: 0, slot: 0, up: false), 70, "A steps 72→70 (skips its own b=71); B's 70 does not block A")
    }
}
