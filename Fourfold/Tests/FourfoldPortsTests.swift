//  FourfoldPortsTests.swift — CARD BACKS (Paul 2026-10-28): five outputs (All + A–D); a note's identity is its PART (a lane's riff or notes), routed to outputs by a mask.

import XCTest

final class FourfoldPortsTests: XCTestCase {
    func testTheFiveNamesAreAllThenOutAToOutD() {
        XCTAssertEqual(FourfoldPorts.names, ["All", "Out_A", "Out_B", "Out_C", "Out_D"])
        XCTAssertEqual(FourfoldPorts.names.count, FourfoldPorts.cableCount)
        XCTAssertEqual(FourfoldPorts.outputCount, 4)
    }
    /// A host lists a plugin's outputs alphabetically, not in cable order (bare letters came out "A, All, B, C, D"): the names must already BE in alphabetical order, case-insensitively and however the host compares them — and so must the standalone app's
    /// virtual CoreMIDI sources, which are the same names behind a common prefix.
    func testTheHostsAlphabeticalOrderIsTheCableOrder() {
        func sorted(_ a: [String], _ cmp: (String, String) -> Bool) -> [String] { a.sorted(by: cmp) }
        let n = FourfoldPorts.names, standalone = n.map { "Fourfold " + $0 }
        for list in [n, standalone] {
            XCTAssertEqual(sorted(list) { $0.lowercased() < $1.lowercased() }, list, "case-insensitive")
            XCTAssertEqual(sorted(list) { $0 < $1 }, list, "plain code-point order")
            XCTAssertEqual(sorted(list) { $0.localizedStandardCompare($1) == .orderedAscending }, list, "Finder-style (localized standard) order")
            XCTAssertEqual(sorted(list) { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }, list, "localized case-insensitive order")
        }
        XCTAssertEqual(n.first, "All", "ALL stays first")
    }
    func testPartMathFollowsFromLaneAndLayer() {
        for lane in 0..<4 {
            XCTAssertEqual(FourfoldPorts.bus(lane: lane, part: .riff), 2 * lane)
            XCTAssertEqual(FourfoldPorts.bus(lane: lane, part: .notes), 2 * lane + 1)
            XCTAssertEqual(FourfoldPorts.busMask(lane: lane, part: .riff) | FourfoldPorts.busMask(lane: lane, part: .notes), FourfoldPorts.laneBusMask(lane))
            XCTAssertEqual(FourfoldPorts.busMask(lane: lane, part: .riff).nonzeroBitCount, 1)
        }
        XCTAssertEqual((0..<4).reduce(UInt8(0)) { $0 | FourfoldPorts.laneBusMask($1) }, 0xFF, "the four lanes together cover all eight parts, once each")
    }
    func testLanePartInvertsBusAndTheDefaultRoutingIsTheLanesOwnOutput() {
        XCTAssertNil(FourfoldPorts.lanePart(ofBus: 8))
        for lane in 0..<4 { for part in [EuclideousOutPart.riff, .notes] {
            let back = try! XCTUnwrap(FourfoldPorts.lanePart(ofBus: FourfoldPorts.bus(lane: lane, part: part)))
            XCTAssertEqual(back.lane, lane); XCTAssertEqual(back.part, part)
            XCTAssertEqual(FourfoldPorts.defaultOutputMask(bus: FourfoldPorts.bus(lane: lane, part: part)), UInt8(1) << UInt8(lane), "lane 1 → A, lane 2 → B, lane 3 → C, lane 4 → D, both parts")
        } }
    }
    func testShortNamesMatchThePagesWording() {
        XCTAssertEqual(FourfoldPorts.shortName(cable: 0), "ALL")
        XCTAssertEqual(FourfoldPorts.shortName(cable: 1), "A"); XCTAssertEqual(FourfoldPorts.shortName(cable: 4), "D")
    }
    func testChannelsAreOnePerOutput() {
        var d = PluginState.makeInit()
        XCTAssertEqual(d.busChannelsResolved, [1, 2, 3, 4], "a fresh document stamps each output with its own channel")
        d.busChannels = [3, 5, 7, 9]
        XCTAssertEqual(d.busChannelsResolved, [3, 5, 7, 9], "four entries are one per output")
        d.busChannels = [3, 5]
        XCTAssertEqual(d.busChannelsResolved, [3, 5, 3, 4], "missing outputs keep their own default")
        d.busChannels = [16, 15, 14, 13, 12, 11, 10, 9]
        XCTAssertEqual(d.busChannelsResolved, [16, 14, 12, 10], "a nine-ports document (eight entries) maps output n ← the RIFF port's entry (2n)")
        d.busChannels = [16, 15, 14, 13, 12]
        XCTAssertEqual(d.busChannelsResolved, [16, 14, 12, 4], "a short list past four entries reads the same way and keeps defaults for the rest")
    }

    // The PORTS tab's output row is fixed-width (a letter, one stepper): it stacks only in a card narrower than it needs.
    func testThePortsRowStacksOnlyWhenItWouldNotFit() {
        XCTAssertEqual(EuclideousPortsRowMetrics.sideBySideW, 146)
        XCTAssertFalse(euclideousPortsRowIsStacked(cardWidth: 448), "the sheet's normal width")
        XCTAssertFalse(euclideousPortsRowIsStacked(cardWidth: 178), "exactly enough")
        XCTAssertTrue(euclideousPortsRowIsStacked(cardWidth: 177.99))
        XCTAssertFalse(euclideousPortsRowIsStacked(cardWidth: euclideousSettingsSheetWidth(containerW: 300)), "a 300 pt host")
    }
}
