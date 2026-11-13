//  EuclideousFillModelTests.swift — FILL ferry (2026-11-13), slice 1: the eight new EuclidLine fields (storage,
//  resolvers, the decoder lines, the SnapshotBuilder fresh literal) and the §1.5 neutrality predicate.

import XCTest

final class EuclideousFillModelTests: XCTestCase {

    // MARK: defaults (§1.1) + neutrality (§1.4/§1.5)

    func testDefaultsAndNeutrality() {
        let l = EuclidLine()
        XCTAssertNil(l.fillOn); XCTAssertNil(l.fillBars); XCTAssertNil(l.fillSpeed); XCTAssertNil(l.fillLength)
        XCTAssertNil(l.fillReverse); XCTAssertNil(l.fillRanks); XCTAssertNil(l.fillSwell); XCTAssertNil(l.fillBreak)
        XCTAssertTrue(l.fillOnResolved, "FILL defaults ON (§1.1)")
        XCTAssertEqual(l.fillBarsResolved, [Bool](repeating: false, count: 8))
        XCTAssertEqual(l.fillSpeedResolved, 3); XCTAssertEqual(l.fillSpeedMultiplier, 2, "default ×2")
        XCTAssertEqual(l.fillLengthResolved, 1); XCTAssertEqual(l.fillLengthFraction, 0.5, "default ½")
        XCTAssertFalse(l.fillReverseResolved); XCTAssertEqual(l.fillRanksResolved, 0); XCTAssertEqual(l.fillSwellResolved, 0); XCTAssertFalse(l.fillBreakResolved)
        XCTAssertFalse(l.usesFill, "a default lane has no bar lit ⇒ byte-identical to today")
    }

    func testTheSpeedAndLengthTables() {
        func m(_ i: UInt8) -> Double { var l = EuclidLine(); l.fillSpeed = i; return l.fillSpeedMultiplier }
        XCTAssertEqual([m(0), m(1), m(2), m(3), m(4)], [0.5, 1, 1.5, 2, 4])   // ×½ ×1 ×1½ ×2 ×4
        func L(_ i: UInt8) -> Double { var l = EuclidLine(); l.fillLength = i; return l.fillLengthFraction }
        XCTAssertEqual([L(0), L(1), L(2)], [1, 0.5, 0.25])                    // BAR ½ ¼
    }

    func testUsesFillGate() {
        var armedDefault = EuclidLine(); armedDefault.fillBars = [false, false, false, true, false, false, false, false]
        XCTAssertTrue(armedDefault.usesFill, "a bar lit at the ×2/½ defaults ⇒ active")
        var neutralArmed = armedDefault; neutralArmed.fillSpeed = 1   // ×1, everything else neutral
        XCTAssertTrue(neutralArmed.fillNeutral); XCTAssertFalse(neutralArmed.usesFill, "×1 + no reverse/ranks/swell/break ⇒ inert whatever LENGTH (§summary)")
        var neutralLenBar = neutralArmed; neutralLenBar.fillLength = 0   // LENGTH is irrelevant at ×1
        XCTAssertFalse(neutralLenBar.usesFill, "LENGTH does not make a ×1 fill active")
        var reverseOnly = neutralArmed; reverseOnly.fillReverse = true
        XCTAssertTrue(reverseOnly.usesFill, "×1 but REVERSE on ⇒ active (reorders)")
        var ranksOnly = neutralArmed; ranksOnly.fillRanks = 3
        XCTAssertTrue(ranksOnly.usesFill)
        var noBar = EuclidLine(); noBar.fillSpeed = 3   // ×2 but nothing lit
        XCTAssertFalse(noBar.usesFill, "no bar lit ⇒ inert")
        var off = armedDefault; off.fillOn = false
        XCTAssertFalse(off.usesFill, "FILL off ⇒ inert")
    }

    func testFillArmedWrapsMod8() {
        var l = EuclidLine(); l.fillBars = [false, false, false, true, false, false, false, false]
        XCTAssertTrue(l.fillArmed(bar: 3)); XCTAssertTrue(l.fillArmed(bar: 11), "bar 11 mod 8 = 3")
        XCTAssertFalse(l.fillArmed(bar: 4))
        l.fillOn = false; XCTAssertFalse(l.fillArmed(bar: 3), "FILL off disarms every bar")
    }

    func testMalformedFolds() {
        var short = EuclidLine(); short.fillBars = [true, true]
        XCTAssertEqual(short.fillBarsResolved, [Bool](repeating: false, count: 8), "a wrong-length array folds to all off")
        var hiSpeed = EuclidLine(); hiSpeed.fillSpeed = 9; XCTAssertEqual(hiSpeed.fillSpeedResolved, 3, "out of range ⇒ default")
        var hiRanks = EuclidLine(); hiRanks.fillRanks = 40; XCTAssertEqual(hiRanks.fillRanksResolved, 7, "clamped ±7")
        var loSwell = EuclidLine(); loSwell.fillSwell = -40; XCTAssertEqual(loSwell.fillSwellResolved, -3, "clamped ±3")
    }

    // MARK: codec (every field must be decoded explicitly — the velocityAbsolute bug)

    func testAllEightRoundTripThroughTheCodec() throws {
        var l = EuclidLine()
        l.fillOn = false; l.fillBars = [true, false, true, true, false, false, true, false]
        l.fillSpeed = 4; l.fillLength = 2; l.fillReverse = true; l.fillRanks = -5; l.fillSwell = 2; l.fillBreak = true
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
        XCTAssertEqual(back.fillBars, [true, false, true, true, false, false, true, false], "the decoder reads fillBars (missing the line silently drops it)")
        XCTAssertEqual(back.fillSpeed, 4); XCTAssertEqual(back.fillRanks, -5); XCTAssertEqual(back.fillBreak, true)
    }

    func testAPreFeatureDocumentDecodesToTheDefaults() throws {
        let back = try JSONDecoder().decode(EuclidLine.self, from: Data("{\"target\":0}".utf8))
        XCTAssertNil(back.fillBars); XCTAssertTrue(back.fillOnResolved); XCTAssertFalse(back.usesFill, "no migration — a document with no FILL fields is inert")
    }

    func testTheSnapshotBuildersFreshLiteralCarriesEveryField() {
        var m = Machine(machineID: "gold", type: .euclid)
        var lines = (0..<4).map { _ in EuclidLine(noteSel: .all) }
        lines[2].fillBars = [false, true, true, false, false, false, false, false]
        lines[2].fillSpeed = 4; lines[2].fillLength = 0; lines[2].fillReverse = true; lines[2].fillRanks = 3; lines[2].fillSwell = -2; lines[2].fillBreak = true
        m.paramsA.euclidLines = lines
        let built = SnapshotBuilder.build(from: PluginState(machines: [m], scenes: [SceneState.empty()]))
        let out = built.machines.first { $0.a.euclidLines.count == 4 }?.a.euclidLines
        XCTAssertEqual(out?[2].fillBars, [false, true, true, false, false, false, false, false], "a fresh-literal rebuild that forgot the field would reset it on the next render")
        XCTAssertEqual(out?[2].fillSpeed, 4); XCTAssertEqual(out?[2].fillLength, 0); XCTAssertEqual(out?[2].fillReverse, true)
        XCTAssertEqual(out?[2].fillRanks, 3); XCTAssertEqual(out?[2].fillSwell, -2); XCTAssertEqual(out?[2].fillBreak, true)
        XCTAssertTrue(out?[2].usesFill ?? false)
        XCTAssertNil(out?[0].fillBars, "a lane that never set it stays nil")
    }
}
