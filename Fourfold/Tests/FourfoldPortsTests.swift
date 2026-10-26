//  FourfoldPortsTests.swift — THE NINE PORTS (Paul 2026-10-26): a note's port is fixed by its lane and layer.

import XCTest

final class FourfoldPortsTests: XCTestCase {
    func testTheNineNamesAreAllThenRiffAndNotesPerLane() {
        XCTAssertEqual(FourfoldPorts.names, ["All", "Emit Riff A", "Emit Notes A", "Emit Riff B", "Emit Notes B", "Emit Riff C", "Emit Notes C", "Emit Riff D", "Emit Notes D"])
        XCTAssertEqual(FourfoldPorts.names.count, FourfoldPorts.cableCount)
    }
    func testBusAndCableFollowFromLaneAndLayer() {
        for lane in 0..<4 {
            XCTAssertEqual(FourfoldPorts.bus(lane: lane, part: .riff), 2 * lane)
            XCTAssertEqual(FourfoldPorts.bus(lane: lane, part: .notes), 2 * lane + 1)
            XCTAssertEqual(FourfoldPorts.cable(lane: lane, part: .riff), 2 * lane + 1)
            XCTAssertEqual(FourfoldPorts.cable(lane: lane, part: .notes), 2 * lane + 2)
            XCTAssertEqual(FourfoldPorts.busMask(lane: lane, part: .riff) | FourfoldPorts.busMask(lane: lane, part: .notes), FourfoldPorts.laneBusMask(lane))
            XCTAssertEqual(FourfoldPorts.busMask(lane: lane, part: .riff).nonzeroBitCount, 1)
        }
        XCTAssertEqual((0..<4).reduce(UInt8(0)) { $0 | FourfoldPorts.laneBusMask($1) }, 0xFF, "the four lanes together cover all eight buses, once each")
    }
    func testLanePartInvertsCableAndAllHasNone() {
        XCTAssertNil(FourfoldPorts.lanePart(ofCable: 0), "ALL belongs to no lane")
        XCTAssertNil(FourfoldPorts.lanePart(ofCable: 9))
        for lane in 0..<4 { for part in [EuclideousOutPart.riff, .notes] {
            let back = try! XCTUnwrap(FourfoldPorts.lanePart(ofCable: FourfoldPorts.cable(lane: lane, part: part)))
            XCTAssertEqual(back.lane, lane); XCTAssertEqual(back.part, part)
        } }
    }
    func testShortNamesMatchThePagesWording() {
        XCTAssertEqual(FourfoldPorts.shortName(cable: 0), "ALL")
        XCTAssertEqual(FourfoldPorts.shortName(cable: 1), "RIFF A"); XCTAssertEqual(FourfoldPorts.shortName(cable: 2), "NOTES A")
        XCTAssertEqual(FourfoldPorts.shortName(cable: 7), "RIFF D"); XCTAssertEqual(FourfoldPorts.shortName(cable: 8), "NOTES D")
    }
    func testAPreNinePortsDocumentsLaneChannelsFillBothPortsOfEachLane() {
        var d = PluginState.makeInit()
        XCTAssertEqual(d.busChannelsResolved, [1, 2, 3, 4, 5, 6, 7, 8], "a fresh document stamps each port with its own channel")
        d.busChannels = [3, 5, 7, 9]
        XCTAssertEqual(d.busChannelsResolved, [3, 3, 5, 5, 7, 7, 9, 9], "a four-entry (pre-ports) list is per LANE: both ports take the lane's number")
        d.busChannels = [3, 5]
        XCTAssertEqual(d.busChannelsResolved, [3, 3, 5, 5, 3, 3, 4, 4], "missing lanes keep their own default")
        d.busChannels = [16, 15, 14, 13, 12, 11, 10, 9]
        XCTAssertEqual(d.busChannelsResolved, [16, 15, 14, 13, 12, 11, 10, 9], "eight entries are one per port")
        d.busChannels = [16, 15, 14]
        XCTAssertEqual(d.busChannelsResolved, [16, 16, 15, 15, 14, 14, 4, 4])
    }
}
