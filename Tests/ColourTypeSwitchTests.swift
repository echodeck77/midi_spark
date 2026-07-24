//  ColourTypeSwitchTests.swift
//  Proves the required behaviour (user spec revision): switching a Colour's processor type must NOT
//  leak parameters between types. Each type keeps its OWN transpose/morph; type-specific params (which
//  live in distinct ColourParams fields) already persist and isolate. A→B→A restores A's values.

import XCTest

final class ColourTypeSwitchTests: XCTestCase {

    private func gold() -> Colour { Colour(colourID: "gold", type: .arp) }

    func testTransposeIsPerType_noLeakAcrossSwitch() {
        var c = gold()
        c.transpose = 5                     // ARP transpose = +5
        c.switchType(to: .harmonize)
        XCTAssertEqual(c.type, .harmonize)
        XCTAssertEqual(c.transpose, 0, "HARMONIZE starts with its OWN transpose (0), not ARP's +5")
        c.transpose = 12                    // HARMONIZE transpose = +12
        c.switchType(to: .arp)
        XCTAssertEqual(c.transpose, 5, "back to ARP restores ARP's +5 — HARMONIZE's +12 did not leak")
        c.switchType(to: .harmonize)
        XCTAssertEqual(c.transpose, 12, "back to HARMONIZE restores its +12")
    }

    func testMorphPersistsAcrossTypeSwitch() {
        // delta §9 item 5: morph is a single per-Colour scalar (the position TOWARD the partner), NOT
        // per-type — so a type switch leaves it untouched (unlike transpose, which stays per-type).
        var c = gold()
        c.morph = 0.7
        c.switchType(to: .strum)
        XCTAssertEqual(c.morph, 0.7, accuracy: 1e-9, "morph is per-Colour now — it survives a type switch")
        c.switchType(to: .arp)
        XCTAssertEqual(c.morph, 0.7, accuracy: 1e-9)
    }

    func testTypeSpecificParamsPersistAndDoNotLeak() {
        // ARP pattern and HARMONIZE intervals live in distinct fields → both survive a round trip, and
        // neither is read by the other type. (This already held; the test guards against regressions.)
        var c = gold()
        c.paramsA.pattern = .down
        c.switchType(to: .harmonize)
        c.paramsA.harmIntervals = [4, 7, 0]
        c.switchType(to: .arp)
        XCTAssertEqual(c.paramsA.pattern, .down, "ARP pattern preserved across the round trip")
        XCTAssertEqual(c.paramsA.harmIntervals, [4, 7, 0], "HARMONIZE intervals still stored (dormant for ARP)")
    }

    func testNoOpSwitchLeavesEverythingUntouched() {
        var c = gold(); c.transpose = 9; c.morph = 0.5
        c.switchType(to: .arp)              // same type
        XCTAssertEqual(c.transpose, 9); XCTAssertEqual(c.morph, 0.5, accuracy: 1e-9)
    }

    func testLegacyColourWithNilStashSwitchesCleanly() {
        // A v2-decoded Colour has nil stashes; the first switch must still isolate (treat nil as zeros).
        var c = gold(); c.transpose = 3
        XCTAssertNil(c.transposeByType)
        c.switchType(to: .ratchet)
        XCTAssertEqual(c.transpose, 0, "RATCHET gets a fresh transpose")
        c.switchType(to: .arp)
        XCTAssertEqual(c.transpose, 3, "ARP's original +3 was stashed and restored")
    }
}
