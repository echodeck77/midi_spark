//  RateStripModelTests.swift — RATE ferry (2026-11-12), slice 1: the three new EuclidLine fields (storage, resolvers, the
//  decoder line, the SnapshotBuilder fresh literal) and the pure strip resolver (run starts, the 8→1 seam, FREE, active).

import XCTest

final class RateStripModelTests: XCTestCase {

    // MARK: defaults + active (§1.5)

    func testDefaultsAreOffAndInactive() {
        let l = EuclidLine()
        XCTAssertNil(l.rateBars); XCTAssertNil(l.rateFree); XCTAssertNil(l.rateBrush)
        XCTAssertEqual(l.rateBarsResolved, [UInt8](repeating: 0, count: 8))
        XCTAssertFalse(l.rateFreeResolved); XCTAssertEqual(l.rateBrushResolved, 3, "default brush is ×2 (code 3)")
        XCTAssertFalse(l.usesRateOverride)
        XCTAssertFalse(euclideousLaneRateStrip(line: l).active)
    }
    func testUsesRateOverrideFollows15() {
        var set = EuclidLine(); set.rateBars = [0, 0, 0, 3, 0, 0, 0, 0]
        XCTAssertTrue(set.usesRateOverride, "a box set, FREE off ⇒ active")
        var free = set; free.rateFree = true
        XCTAssertFalse(free.usesRateOverride, "FREE on ⇒ inactive, as today")
        XCTAssertFalse(euclideousLaneRateStrip(line: free).active)
        var empty = EuclidLine(); empty.rateBars = [0, 0, 0, 0, 0, 0, 0, 0]
        XCTAssertFalse(empty.usesRateOverride, "no box set ⇒ inactive")
    }
    func testMultiplierTable() {
        XCTAssertEqual(euclideousRateMultiplier(code: 1), 0.5); XCTAssertEqual(euclideousRateMultiplier(code: 2), 1.5)
        XCTAssertEqual(euclideousRateMultiplier(code: 3), 2); XCTAssertEqual(euclideousRateMultiplier(code: 4), 4)
        XCTAssertEqual(euclideousRateMultiplier(code: 0), 1); XCTAssertEqual(euclideousRateMultiplier(code: 9), 1, "out of range ⇒ ×1")
    }
    func testMalformedBarsFoldToOff() {
        var short = EuclidLine(); short.rateBars = [3, 3]
        XCTAssertEqual(short.rateBarsResolved, [UInt8](repeating: 0, count: 8), "a wrong-length array folds to all off")
        var hi = EuclidLine(); hi.rateBars = [9, 3, 0, 0, 0, 0, 0, 0]
        XCTAssertEqual(hi.rateBarsResolved[0], 0, "an out-of-range code folds to off"); XCTAssertEqual(hi.rateBarsResolved[1], 3)
    }

    // MARK: codec (the decoder must carry the fields — the velocityAbsolute bug)

    func testTheThreeFieldsRoundTripThroughTheCodec() throws {
        var l = EuclidLine(); l.rateBars = [0, 0, 3, 3, 1, 0, 4, 0]; l.rateFree = true; l.rateBrush = 1
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
        XCTAssertEqual(back.rateBars, [0, 0, 3, 3, 1, 0, 4, 0], "the decoder reads rateBars (missing the line silently drops it)")
        XCTAssertEqual(back.rateFree, true); XCTAssertEqual(back.rateBrush, 1)
    }
    func testAPreFeatureDocumentDecodesToTheDefaults() throws {
        let back = try JSONDecoder().decode(EuclidLine.self, from: Data("{\"target\":0}".utf8))
        XCTAssertNil(back.rateBars); XCTAssertFalse(back.usesRateOverride, "no migration — a document with no RATE fields is inactive")
    }
    func testTheSnapshotBuildersFreshLiteralCarriesTheThreeFields() {
        var m = Machine(machineID: "gold", type: .euclid)
        var lines = (0..<4).map { _ in EuclidLine(noteSel: .all) }
        lines[2].rateBars = [0, 3, 3, 0, 0, 0, 0, 0]; lines[2].rateFree = false; lines[2].rateBrush = 2; lines[2].noteSel = .all
        m.paramsA.euclidLines = lines
        let built = SnapshotBuilder.build(from: PluginState(machines: [m], scenes: [SceneState.empty()]))
        let out = built.machines.first { $0.a.euclidLines.count == 4 }?.a.euclidLines
        XCTAssertEqual(out?[2].rateBars, [0, 3, 3, 0, 0, 0, 0, 0], "a fresh-literal rebuild that forgot the field would reset it on the next render")
        XCTAssertEqual(out?[2].rateBrush, 2); XCTAssertTrue(out?[2].usesRateOverride ?? false)
        XCTAssertNil(out?[0].rateBars, "a lane that never set it stays nil")
    }

    // MARK: the strip resolver (§2.2 — runs, the 8→1 seam, FREE)

    private func strip(_ codes: [UInt8]) -> EuclideousRateStrip { var l = EuclidLine(); l.rateBars = codes; return euclideousLaneRateStrip(line: l) }

    func testRunsAreMaximalStretchesOfEqualCode() {
        // §7.2 example: boxes 4,5 ×2 (one run) and box 6 ×½ (its own) — 0-based indices 3,4 code 3; index 5 code 1.
        let s = strip([0, 0, 0, 3, 3, 1, 0, 0])
        XCTAssertTrue(s.active)
        XCTAssertEqual([s.runStart[3], s.runStart[4]], [3, 3], "boxes 4–5 ×2 are one run starting at box 4")
        XCTAssertEqual(s.runStart[5], 5, "box 6 ×½ is its own run")
    }
    func testBoxOneAlwaysStartsARunNoSeamCrossing() {
        // §7.2: (box 8 ×2, box 1 ×2) gives TWO runs — the 8→1 seam never joins.
        let s = strip([3, 0, 0, 0, 0, 0, 0, 3])
        XCTAssertEqual(s.runStart[0], 0); XCTAssertEqual(s.runStart[7], 7, "box 8 and box 1 are separate runs across the seam")
    }
    func testAllEightSameIsOneRunStartingAtBoxOne() {
        let s = strip([3, 3, 3, 3, 3, 3, 3, 3])
        for i in 0..<8 { XCTAssertEqual(s.runStart[i], 0, "all ×2 is one run, boxes 1–8") }
    }
    func testAnOffBoxIsItsOwnSingletonRun() {
        let s = strip([3, 0, 3, 0, 0, 0, 0, 0])
        XCTAssertEqual(s.runStart[1], 1, "an off box never joins a run"); XCTAssertEqual(s.runStart[2], 2)
    }
}
