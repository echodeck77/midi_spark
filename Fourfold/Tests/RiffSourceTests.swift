//  RiffSourceTests.swift — RIFF SOURCE ferry (Paul 2026-11-22): a lane reads another lane's riff position.
//  §11 model + pure-function tests. Lane numbers in the spec are 1-based; the code (and these tests) is 0-based,
//  so the spec's "lane 1 reads lane 2" is `sources[0] = 1`.

import XCTest

final class RiffSourceTests: XCTestCase {

    // §11.1: the field defaults nil (own), round-trips through a document encode/decode, and an old document (no key) loads as own.
    func testModelDefaultsOwnAndRoundTrips() throws {
        var l = EuclidLine()
        XCTAssertNil(l.riffSourceLane, "default is own")
        XCTAssertNil(l.riffSourceLaneResolved(ownLane: 0))
        // a set value round-trips
        l.riffSourceLane = 2
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back.riffSourceLane, 2, "a reader survives a save/load")
        XCTAssertEqual(back.riffSourceLaneResolved(ownLane: 0), 2)
        // an OLD document (the key absent) loads as own — simulate by decoding JSON with no riffSourceLane key
        let fresh = EuclidLine()
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(fresh)) as! [String: Any]
        dict.removeValue(forKey: "riffSourceLane")
        let old = try JSONDecoder().decode(EuclidLine.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertNil(old.riffSourceLane, "an old document loads as own")
        // the resolver cleans a stored self / out-of-range value at read time too
        var bad = EuclidLine(); bad.riffSourceLane = 1
        XCTAssertNil(bad.riffSourceLaneResolved(ownLane: 1), "a self-reference resolves to own")
        bad.riffSourceLane = 9
        XCTAssertNil(bad.riffSourceLaneResolved(ownLane: 0), "an out-of-range value resolves to own")
    }

    // §11.2: normalise — self → nil; a 2-cycle drops the first lane; a 3-cycle drops the first; a plain chain is untouched.
    func testNormaliseBreaksSelfAndLoops() {
        // self → nil
        XCTAssertEqual(euclideousNormaliseRiffSources([0, nil, nil, nil]), [nil, nil, nil, nil])
        // 1→2 with 2→1 (0-based [1,0,…]): lane 1 (idx 0) becomes nil, lane 2 (idx 1) kept
        XCTAssertEqual(euclideousNormaliseRiffSources([1, 0, nil, nil]), [nil, 0, nil, nil])
        // 1→2, 2→3, 3→1 (0-based [1,2,0,…]): lane 1 (idx 0) becomes nil, the others kept
        XCTAssertEqual(euclideousNormaliseRiffSources([1, 2, 0, nil]), [nil, 2, 0, nil])
        // the chain 1→2→3 (0-based [1,2,nil,nil]) is untouched
        XCTAssertEqual(euclideousNormaliseRiffSources([1, 2, nil, nil]), [1, 2, nil, nil])
        // out-of-range → nil; idempotent
        XCTAssertEqual(euclideousNormaliseRiffSources([9, -1, 3, nil]), [nil, nil, nil, nil].enumerated().map { i, _ in [nil, nil, 3, nil][i] })
        let once = euclideousNormaliseRiffSources([1, 2, 0, nil])
        XCTAssertEqual(euclideousNormaliseRiffSources(once), once, "idempotent")
    }

    // §11.3: canRead — with 4→3 and 3→2 (0-based lane3→2, lane2→1), lane 2 (idx 1) can't read 3 or 4 and can read 1.
    func testCanReadRejectsLoops() {
        let sources: [Int?] = [nil, nil, 1, 2]   // idx2 reads idx1, idx3 reads idx2
        XCTAssertFalse(euclideousCanRiffRead(lane: 1, candidate: 2, sources: sources), "lane 2 can't read lane 3 (would loop)")
        XCTAssertFalse(euclideousCanRiffRead(lane: 1, candidate: 3, sources: sources), "lane 2 can't read lane 4 (would loop through 3)")
        XCTAssertTrue(euclideousCanRiffRead(lane: 1, candidate: 0, sources: sources), "lane 2 can read lane 1")
        XCTAssertFalse(euclideousCanRiffRead(lane: 1, candidate: 1, sources: sources), "a lane never reads itself")
    }

    // §1.2: the root chain follows at most three links and stops at the first own lane (or a loop guard).
    func testRootChain() {
        XCTAssertEqual(euclideousRiffRootChain(lane: 0, sources: [1, 2, nil, nil]), [0, 1, 2], "0→1→2(own)")
        XCTAssertEqual(euclideousRiffRootChain(lane: 0, sources: [nil, nil, nil, nil]), [0], "own lane is its own root")
        // a loop never extends past the guard
        XCTAssertEqual(euclideousRiffRootChain(lane: 0, sources: [1, 0, nil, nil]).count, 2)
    }

    // §11.22: pasting a reader of lane 2 onto lane 2 leaves lane 2 own (normalise's self → nil, the paste's safety net).
    func testPasteSelfReferenceBecomesOwn() {
        var doc = PluginState.makeInit()
        var lines = doc.euclideousLinesResolved
        lines[1].riffSourceLane = 1   // lane 2 (idx 1) now "reads itself" — the result of pasting a lane-2 reader onto lane 2
        doc.euclideousLines = lines
        XCTAssertTrue(doc.normalizeRiffSourcesAtLoad(), "normalise changes the self-reference")
        XCTAssertNil(doc.euclideousLinesResolved[1].riffSourceLane, "lane 2 is own after normalise")
        XCTAssertFalse(doc.normalizeRiffSourcesAtLoad(), "a clean document is a no-op")
    }
}
