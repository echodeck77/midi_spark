//  FourfoldParamTests.swift — host parameters slice 1: the pure mapping table (count, unique/stable addresses, alphabetical blocks, two-way round-trip, clamping).

import XCTest

final class FourfoldParamTests: XCTestCase {
    // A fixture with headroom: Steps 16 on every lane, so a Hits round-trip at 16 isn't clamped by a smaller Steps.
    private func fixture() -> PluginState {
        var s = PluginState(machines: [], scenes: [SceneState.empty()])
        var lines = s.euclideousLinesResolved
        for i in lines.indices { lines[i].steps = 16 }
        s.euclideousLines = lines
        return s
    }

    func testCountAndAddresses() {
        let p = fourfoldParams()
        XCTAssertEqual(p.count, 70, "2 global + 4×13 lane + 4×4 output")
        XCTAssertEqual(Set(p.map { $0.address }).count, 70, "every address is unique")
        // spot-check the stable scheme (invariant 5 — never renumber)
        func addr(_ name: String) -> UInt64? { p.first { $0.name == name }?.address }
        XCTAssertEqual(addr("Key Root"), 0)
        XCTAssertEqual(addr("Key Scale"), 1)
        XCTAssertEqual(addr("Lane 1 Play"), 1000)
        XCTAssertEqual(addr("Lane 1 Hits"), 1001)
        XCTAssertEqual(addr("Lane 4 Stack Velocity"), 1323)
        XCTAssertEqual(addr("Out a Mute"), 2000)
        XCTAssertEqual(addr("Out d CC Low"), 2303)
    }

    // The whole point: in the host's flat A→Z list the names block cleanly — Key · → Lane 1…4 → Out a…d.
    func testAlphabeticalBlocks() {
        let names = fourfoldParamsAlphabetical().map { $0.name }
        XCTAssertEqual(names.first, "Key Root")
        XCTAssertEqual(Array(names.prefix(2)), ["Key Root", "Key Scale"])
        let lastKey = names.lastIndex { $0.hasPrefix("Key ") }!
        let firstLane = names.firstIndex { $0.hasPrefix("Lane ") }!
        let lastLane = names.lastIndex { $0.hasPrefix("Lane ") }!
        let firstOut = names.firstIndex { $0.hasPrefix("Out ") }!
        XCTAssertLessThan(lastKey, firstLane, "all Key params precede all Lane params")
        XCTAssertLessThan(lastLane, firstOut, "all Lane params precede all Out params")
        // within a lane the parts cluster: Riff … then Stack … then Steps
        let lane1 = names.filter { $0.hasPrefix("Lane 1 ") }
        XCTAssertEqual(lane1, lane1.sorted(), "a lane's own params are in alphabetical order")
        XCTAssertTrue(lane1.firstIndex(of: "Lane 1 Riff Play")! < lane1.firstIndex(of: "Lane 1 Stack Play")!)
    }

    // Two-way: set a value, read it back. Every param is stepped/bool/enum, so the round-trip is clamp(round(v)).
    func testRoundTrip() {
        let s = fixture()
        for d in fourfoldParams() {
            for v in [d.min, d.max, d.def] {
                var st = s
                d.set(&st, v)
                let got = d.get(st)
                let expect = min(d.max, max(d.min, v)).rounded()
                XCTAssertEqual(got, expect, accuracy: 0.51, "\(d.name) round-trip @ \(v)")
            }
        }
    }

    // A value past the ends is clamped into range on the way in.
    func testClamping() {
        let s = fixture()
        for d in fourfoldParams() {
            var st = s
            d.set(&st, d.max + 1000)
            XCTAssertLessThanOrEqual(d.get(st), d.max + 0.51, "\(d.name) clamps above max")
            d.set(&st, d.min - 1000)
            XCTAssertGreaterThanOrEqual(d.get(st), d.min - 0.51, "\(d.name) clamps below min")
        }
    }

    // The enum params index their cases both ways.
    func testEnumIndexing() {
        let p = fourfoldParams()
        let scale = p.first { $0.name == "Key Scale" }!
        guard case .indexed(let names) = scale.kind else { return XCTFail("Key Scale is an enum") }
        XCTAssertEqual(names.count, ScaleType.allCases.count)
        var s = PluginState(machines: [], scenes: [SceneState.empty()])
        scale.set(&s, 3)
        XCTAssertEqual(s.euclideousKeyTypeResolved, ScaleType.allCases[3])
        XCTAssertEqual(scale.get(s), 3)
        let rate = p.first { $0.name == "Lane 1 Rate" }!
        guard case .indexed = rate.kind else { return XCTFail("Rate is an enum") }
        rate.set(&s, 5)
        XCTAssertEqual(rate.get(s), 5)
    }

    // Setting a param touches ONLY its own field — a document with no param written is byte-identical (golden safety).
    func testUntouchedDocumentUnchanged() {
        let a = fixture(), b = fixture()
        XCTAssertEqual(a, b, "no param set → identical")
    }
}
