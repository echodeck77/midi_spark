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

    // Build a captured lane CLOCK for a lane with hits at the given 0-based step indices (the hit SCHEDULE); FREE chains; the riff
    // walk values drive the column it reads; `source` = this lane's riffSourceLane (−1 = own). sub = 1 beat/step so a hit's tick ==
    // its step and a hit's beat == its tick. (The clock is exactly what the Router's pre-pass captures.)
    private func cfg(stepCount n: Int, hitsAt: [Int], riffDir: RiffDir = .forward, length: Int = 8, stride: Int = 1, shift: Int = 0, source: Int = -1) -> HocketLaneClock {
        var c = HocketLaneClock()
        for i in 0..<32 { c.buf[i] = false }
        for h in hitsAt where h >= 0 && h < n { if h < 32 { c.buf[h] = true } }
        c.valid = true; c.n = n; c.dir = .fwd; c.cycleLen = n; c.sub = 1.0; c.chains = .off
        c.captureRiff(dir: riffDir, length: length, stride: stride, rotate: shift, every: 1, columns: 8, seed: 0, source: source)
        return c
    }
    private func emptyCfg() -> HocketLaneClock { cfg(stepCount: 8, hitsAt: []) }

    // §11.4 (the canvas case) + §11.5 (same beat): reader lane 3 reads lane 2. Source: 16 steps, hits 1,4,8,10,13 (0-based
    // 0,3,7,9,12), ping-pong, LEN 8. Reader: 12 steps, hits 5,6,8,10,12 (0-based 4,5,7,9,11). The reader's first 20 hits read
    // 1-based columns 2 2 3 4 4 6 6 7 7 8 7 7 7 6 5 4 3 3 2 2, and the 21st reads column 1.
    func testCanvasCaseTheReaderReadsTheSourcesLatestColumn() {
        let source = cfg(stepCount: 16, hitsAt: [0, 3, 7, 9, 12], riffDir: .pingpong, length: 8)
        let reader = cfg(stepCount: 12, hitsAt: [4, 5, 7, 9, 11])
        let clocks = [emptyCfg(), source, reader, emptyCfg()]   // lane 3 (idx 2) reads lane 2 (idx 1); the source is own
        // the reader's hit ticks (sub 1 ⇒ beat == tick): 4,5,7,9,11 then +12 each 12-step bar
        var readerHits: [Int64] = []
        for bar in 0..<5 { for s in [4, 5, 7, 9, 11] { readerHits.append(Int64(bar * 12 + s)) } }
        let expected1Based = [2, 2, 3, 4, 4, 6, 6, 7, 7, 8, 7, 7, 7, 6, 5, 4, 3, 3, 2, 2, 1]
        for (i, exp) in expected1Based.enumerated() {
            let b = Double(readerHits[i])
            let col = euclideousRiffSourceColumn(clocks: clocks, lane: 1, beat: b)   // position(source, reader's hit beat)
            XCTAssertNotNil(col, "reader hit \(i + 1) has a source hit")
            XCTAssertEqual((col ?? -2) + 1, exp, "reader hit \(i + 1) (beat \(b)) reads 1-based column \(exp)")
        }
    }

    // §11.6: a source whose first hit is on step 5 (0-based 4) and a reader hitting on step 1 (beat 0): the reader's first hit is a rest (none).
    func testNoSourceHitYetIsARest() {
        let source = cfg(stepCount: 16, hitsAt: [4, 8, 12])
        let clocks = [emptyCfg(), source, emptyCfg(), emptyCfg()]
        XCTAssertNil(euclideousRiffSourceColumn(clocks: clocks, lane: 1, beat: 0.0), "no source hit at or before beat 0 ⇒ rest")
        XCTAssertNotNil(euclideousRiffSourceColumn(clocks: clocks, lane: 1, beat: 4.0), "the source's first hit lands at beat 4")
    }

    // §11.8 (pure level): stateless — the borrowed column at a beat is the same whether reached directly or from an offset start.
    func testStatelessColumnIsAPureFunctionOfTheBeat() {
        let source = cfg(stepCount: 16, hitsAt: [0, 3, 7, 9, 12], riffDir: .pingpong)
        let clocks = [emptyCfg(), source, emptyCfg(), emptyCfg()]
        for b in stride(from: 0.0, through: 64.0, by: 1.0) {
            XCTAssertEqual(euclideousRiffSourceColumn(clocks: clocks, lane: 1, beat: b),
                           euclideousRiffSourceColumn(clocks: clocks, lane: 1, beat: b),
                           "deterministic at beat \(b)")
        }
        XCTAssertEqual(euclideousRiffSourceColumn(clocks: clocks, lane: 1, beat: 39.0),
                       euclideousRiffSourceColumn(clocks: clocks, lane: 1, beat: 39.0))
    }

    // §11.10: chain 4→3→2 (idx 3 reads idx 2 reads idx 1): lane 4's hit reads the column lane 3's latest hit read, which is lane 2's column.
    func testChainResolvesThroughTheRoot() {
        let root = cfg(stepCount: 8, hitsAt: [0, 2, 4, 6], riffDir: .forward)   // idx 1, own
        let mid = cfg(stepCount: 8, hitsAt: [1, 3, 5, 7], source: 1)            // idx 2, reads idx 1
        let top = cfg(stepCount: 8, hitsAt: [0, 4], source: 2)                  // idx 3, reads idx 2
        let clocks = [emptyCfg(), root, mid, top]
        // top (idx 3) hit at beat 4: position(mid, 4) → mid's latest hit ≤ 4 is tick 3 → position(root, 3) → root's latest ≤ 3 is tick 2 → root's column at its hit on tick 2
        let got = euclideousRiffSourceColumn(clocks: clocks, lane: 2, beat: 4.0)   // lane 4 reads lane 3 (idx 2)
        // hand: mid latest hit ≤ 4 = tick 3 (3rd... hits 1,3 → tick3 is 2nd hit, ord 1); root latest ≤ 3 = tick 2 (hits 0,2 → 2nd hit, ord 1); root fwd col at ord 1 = column 1 (0-based)
        XCTAssertEqual(got, 1, "the chain resolves to the root's column")
        XCTAssertEqual(got, euclideousRiffSourceColumn(clocks: clocks, lane: 1, beat: 3.0), "= position(root, mid's hit beat)")
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
