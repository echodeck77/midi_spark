//  FourfoldComposeTests.swift
//  FOURFOLD Step 1b (2026-10-23): the Fourfold-only scene composer — one cell on the reserved row, a one-slot euclid chain carrying exactly the eight fields. (The parity test against 8x8 State's composer is Tests/FourfoldComposeParityTests.swift.)

import XCTest

final class FourfoldComposeTests: XCTestCase {

    private func input(from doc: PluginState, solo: UInt8 = 0, revs: UInt32 = 0) -> FourfoldCompose.Input {
        FourfoldCompose.Input(lines: doc.euclideousLinesResolved, riff: doc.euclideousRiffResolved, riffs: doc.riffsResolved, activeRiff: doc.activeRiffResolved,
                              mainOutMask: doc.euclideousMainOutMaskResolved, soloMask: solo, locks: doc.euclideousLocksResolved, lockRevs: revs)
    }
    func testOnlyTheReservedRowHoldsACellAndItIsAOneSlotEuclidChain() {
        let i = input(from: PluginState.makeInit())
        let s = FourfoldCompose.scene(i)
        for c in 0..<s.cells.count { for r in 0..<s.cells[c].count {
            if c == 0 && r == Snap.euclideousRow { continue }
            XCTAssertNil(s.cells[c][r], "column \(c) row \(r) must be empty")
        } }
        let cell = try! XCTUnwrap(s.cells[0][Snap.euclideousRow])
        XCTAssertEqual(cell.machineID, FourfoldCompose.machineID)
        XCTAssertEqual(cell.buses, [.a, .b, .c, .d])
        XCTAssertEqual(cell.inputReceiver, 3)
        XCTAssertEqual(cell.processors?.count, 1)
        XCTAssertEqual(cell.processors?.first?.type, .euclid)
        let lanes = try! XCTUnwrap(s.rowLane)
        XCTAssertEqual(lanes.count, Snap.rows, "a FULL-length array — an empty one would mean the global lap key")
        XCTAssertEqual(lanes[Snap.euclideousRow], 1)
        XCTAssertEqual(lanes.enumerated().filter { $0.offset != Snap.euclideousRow }.map { $0.element }, [UInt16](repeating: 0, count: Snap.rows - 1))
    }
    func testTheChainCarriesExactlyTheEightFieldsAndNothingElse() {
        var doc = PluginState.makeInit()
        doc.euclideousMainOutMask = 0b0011
        let i = input(from: doc, solo: 0b0100, revs: 7)
        let p = try! XCTUnwrap(FourfoldCompose.chain(i).first?.params)
        XCTAssertEqual(p.euclidLines, i.lines); XCTAssertEqual(p.euclideousRiff, i.riff)
        XCTAssertEqual(p.riffs, i.riffs); XCTAssertEqual(p.activeRiff, i.activeRiff)
        XCTAssertEqual(p.mainOutMask, 0b0011); XCTAssertEqual(p.soloMask, 0b0100)
        XCTAssertEqual(p.euclideousLocks, i.locks); XCTAssertEqual(p.lockRevs, 7)
        var blank = MachineParams()
        blank.euclidLines = i.lines; blank.euclideousRiff = i.riff; blank.riffs = i.riffs; blank.activeRiff = i.activeRiff
        blank.mainOutMask = 0b0011; blank.soloMask = 0b0100; blank.euclideousLocks = i.locks; blank.lockRevs = 7
        XCTAssertEqual(p, blank, "no other MachineParams field is set")
    }
}
