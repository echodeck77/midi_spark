//  ReelKeepTests.swift — REEL redesign Phase 4 slice 4a: the pure KEEP model + naming + list ops.

import XCTest

final class ReelKeepTests: XCTestCase {
    private let date = Date(timeIntervalSince1970: 1_700_000_000)   // a fixed instant for stable stamps
    private var stamp: String { reelExportStamp(date, timeZone: TimeZone(identifier: "UTC")!) }

    func testBarLabel() {
        XCTAssertEqual(reelKeepBarLabel(startBeat: 0, endBeat: 16, beatsPerBar: 4), "1\u{2013}4")
        XCTAssertEqual(reelKeepBarLabel(startBeat: 16, endBeat: 20, beatsPerBar: 4), "5", "a one-bar keep shows a single bar number")
        XCTAssertEqual(reelKeepBarLabel(startBeat: 32, endBeat: 64, beatsPerBar: 4), "9\u{2013}16")
    }

    func testAutoName() {
        let n = reelKeepName(startBeat: 0, endBeat: 16, beatsPerBar: 4, at: date, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(n.hasPrefix("Keep "), "named 'Keep · bars … · time'")
        XCTAssertTrue(n.contains("bars 1\u{2013}4"))
        XCTAssertTrue(n.contains(stamp.split(separator: " ").last.map(String.init)!), "carries the HH-MM-SS")
    }

    func testAddAndDedup() {
        var keeps: [ReelKeep] = []
        keeps = reelAddKeep(keeps, startBeat: 0, endBeat: 16, beatsPerBar: 4, at: date)
        XCTAssertEqual(keeps.count, 1)
        XCTAssertEqual(keeps[0].startBeat, 0); XCTAssertEqual(keeps[0].endBeat, 16)
        keeps = reelAddKeep(keeps, startBeat: 0.1, endBeat: 15.9, beatsPerBar: 4, at: date)   // within half a bar of the first → duplicate
        XCTAssertEqual(keeps.count, 1, "a near-identical range is not added twice")
        keeps = reelAddKeep(keeps, startBeat: 16, endBeat: 32, beatsPerBar: 4, at: date)       // a distinct range
        XCTAssertEqual(keeps.count, 2)
        keeps = reelAddKeep(keeps, startBeat: 40, endBeat: 40, beatsPerBar: 4, at: date)        // empty range
        XCTAssertEqual(keeps.count, 2, "an empty range is ignored")
    }

    func testRemove() {
        let keeps = [ReelKeep(startBeat: 0, endBeat: 16, name: "a"), ReelKeep(startBeat: 16, endBeat: 32, name: "b")]
        XCTAssertEqual(reelRemoveKeep(keeps, at: 0), [ReelKeep(startBeat: 16, endBeat: 32, name: "b")])
        XCTAssertEqual(reelRemoveKeep(keeps, at: 5), keeps, "out of range → unchanged")
    }

    func testExportFileName() {
        XCTAssertEqual(reelKeepExportFileName(stamp: "2026-11-16 14-52-07", startBeat: 0, endBeat: 16, beatsPerBar: 4, label: "All"),
                       "Fourfold 2026-11-16 14-52-07 bars 1\u{2013}4 All.mid")
    }

    func testCodableRoundTrip() throws {
        let k = ReelKeep(startBeat: 4, endBeat: 36, name: "Keep · bars 2–9 · 10-00-00")
        let data = try JSONEncoder().encode(k)
        XCTAssertEqual(try JSONDecoder().decode(ReelKeep.self, from: data), k)
    }

    // The session field is additive-Optional: nil resolves to an empty list, so an old document is unchanged.
    func testPluginStateDefaultsEmpty() {
        XCTAssertEqual(PluginState(machines: [], scenes: [SceneState.empty()]).reelKeepsResolved, [])
    }
}
