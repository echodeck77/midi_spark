import XCTest

/// POOL ferry (2026-11-02) §7 — the per-lane SOURCES mask and SUSTAIN switch / mode: defaults, tolerant decode, the set-one-source helper and the round trip. Pure model tests; the engine and UI have their own.
final class PoolTabModelTests: XCTestCase {
    private func decode(_ json: String) throws -> EuclidLine { try JSONDecoder().decode(EuclidLine.self, from: Data(json.utf8)) }

    func testDefaultsAreEverySourceOnSustainOffKeep() {
        let l = EuclidLine()
        XCTAssertEqual(l.poolSrcMaskResolved, 0b1111)
        for b in 0..<4 { XCTAssertTrue(l.poolSrcOn(b), "source \(b) defaults on") }
        XCTAssertFalse(l.poolSustainOnResolved); XCTAssertEqual(l.poolSustainModeResolved, .keep)
        XCTAssertNil(l.poolSrcMask); XCTAssertNil(l.poolSustainOn); XCTAssertNil(l.poolSustainMode)
    }
    func testADocumentWithoutTheFieldsDecodesToTheDefaultsAndRoundTripsWithoutThem() throws {
        let l = try decode("{\"pulses\":3,\"steps\":8}")
        XCTAssertNil(l.poolSrcMask); XCTAssertNil(l.poolSustainOn); XCTAssertNil(l.poolSustainMode)
        let back = String(data: try JSONEncoder().encode(l), encoding: .utf8) ?? ""
        XCTAssertFalse(back.contains("poolSrcMask") || back.contains("poolSustain"), "nil fields are not written: an untouched document stays byte-identical")
    }
    func testSettingOneSourceOffAndBackOnReturnsToNil() {
        var l = EuclidLine()
        l.setPoolSrc(2, false)
        XCTAssertEqual(l.poolSrcMask, 0b1011); XCTAssertFalse(l.poolSrcOn(2)); XCTAssertTrue(l.poolSrcOn(0)); XCTAssertTrue(l.poolSrcOn(3))
        l.setPoolSrc(0, false); XCTAssertEqual(l.poolSrcMask, 0b1010)
        l.setPoolSrc(2, true); l.setPoolSrc(0, true)
        XCTAssertNil(l.poolSrcMask, "all four on is stored as nil")
        l.setPoolSrc(7, false); l.setPoolSrc(-1, false); XCTAssertNil(l.poolSrcMask, "out-of-range bits are ignored")
    }
    // TWO CHORD GRIDS (2026-11-03): bit 4 is CHORDS 2; CHORDS 1 (bit 1) and CHORDS 2 are mutually exclusive.
    func testChordsOneAndTwoAreMutuallyExclusive() {
        var l = EuclidLine()
        XCTAssertTrue(l.poolSrcOn(1)); XCTAssertFalse(l.poolSrcOn(4)); XCTAssertEqual(l.poolChordGrid, 0); XCTAssertTrue(l.poolChordsOn)
        l.setPoolSrc(4, true)
        XCTAssertEqual(l.poolSrcMask, 0b11101, "CHORDS 2 on takes CHORDS 1 off")
        XCTAssertFalse(l.poolSrcOn(1)); XCTAssertTrue(l.poolSrcOn(4)); XCTAssertEqual(l.poolChordGrid, 1); XCTAssertTrue(l.poolChordsOn)
        l.setPoolSrc(1, true)
        XCTAssertNil(l.poolSrcMask, "CHORDS 1 on takes CHORDS 2 off — back at the default, stored as nil")
        l.setPoolSrc(1, false)
        XCTAssertEqual(l.poolSrcMask, 0b01101); XCTAssertFalse(l.poolChordsOn, "the lit one tapped again: chords off for the lane")
        l.setPoolSrc(4, true); l.setPoolSrc(4, false)
        XCTAssertEqual(l.poolSrcMask, 0b01101); XCTAssertFalse(l.poolChordsOn)
        l.setPoolSrc(5, true); l.setPoolSrc(-1, true); XCTAssertEqual(l.poolSrcMask, 0b01101, "a sixth bit does not exist")
    }
    func testEveryReachableMaskNeverHasBothChordGrids() {
        for start in 0..<32 {
            var l = EuclidLine(); l.poolSrcMask = UInt8(start)
            for b in 0..<5 { for on in [true, false] {
                var m = l; m.setPoolSrc(b, on)
                XCTAssertFalse(m.poolSrcOn(1) && m.poolSrcOn(4), "start \(start) bit \(b) \(on)")
                XCTAssertLessThan(m.poolSrcMaskResolved, 32)
            } }
        }
    }
    func testADocumentWithBothChordBitsReadsAsChordsOne() throws {
        XCTAssertEqual(try decode("{\"poolSrcMask\":31}").poolSrcMask, 0b01111, "both chord bits: CHORDS 1 wins")
        XCTAssertEqual(try decode("{\"poolSrcMask\":16}").poolSrcMask, 0b10000, "CHORDS 2 alone is legal")
        XCTAssertEqual(try decode("{\"poolSrcMask\":255}").poolSrcMask, 0b01111)
        var l = EuclidLine(); l.poolSrcMask = 0b10100
        XCTAssertEqual(l.poolSrcMaskResolved, 0b10100); XCTAssertEqual(l.poolChordGrid, 1)
        l.poolSrcMask = 0b11111; XCTAssertEqual(l.poolSrcMaskResolved, 0b01111, "a hand-set mask with both resolves to CHORDS 1")
        XCTAssertEqual(euclideousPoolSrcNormalized(0b11111), 0b01111); XCTAssertEqual(euclideousPoolSrcNormalized(0xFF), 0b01111)
    }
    func testAllFourOffIsALegalMask() {
        var l = EuclidLine(); for b in 0..<4 { l.setPoolSrc(b, false) }
        XCTAssertEqual(l.poolSrcMask, 0); XCTAssertEqual(l.poolSrcMaskResolved, 0)
        for b in 0..<4 { XCTAssertFalse(l.poolSrcOn(b)) }
    }
    func testTheMaskAndModeDecodeTolerantly() throws {
        XCTAssertEqual(try decode("{\"poolSrcMask\":255}").poolSrcMask, 0b1111, "bits above the four are masked off")
        XCTAssertEqual(try decode("{\"poolSrcMask\":\"x\"}").poolSrcMask, nil, "a wrong-typed value reads as missing")
        XCTAssertEqual(try decode("{\"poolSustainMode\":\"WHAT\"}").poolSustainModeResolved, .keep, "an unknown mode is KEEP")
        XCTAssertEqual(try decode("{\"poolSustainMode\":\"STACK\",\"poolSustainOn\":true}").poolSustainModeResolved, .stack)
        XCTAssertEqual(try decode("{\"poolSustainOn\":\"yes\"}").poolSustainOn, nil)
    }
    func testTheFieldsRoundTrip() throws {
        var l = EuclidLine(); l.poolSrcMask = 0b0110; l.poolSustainOn = true; l.poolSustainMode = .stack
        let back = try JSONDecoder().decode(EuclidLine.self, from: JSONEncoder().encode(l))
        XCTAssertEqual(back, l)
        XCTAssertEqual(back.poolSrcMaskResolved, 0b0110); XCTAssertTrue(back.poolSustainOnResolved); XCTAssertEqual(back.poolSustainModeResolved, .stack)
    }
    func testASwitchedOffSustainRemembersItsMode() {
        var l = EuclidLine(); l.poolSustainMode = .stack
        XCTAssertFalse(l.poolSustainOnResolved, "the mode alone does not switch the row on")
        XCTAssertEqual(l.poolSustainModeResolved, .stack, "…and an off row keeps its remembered mode")
    }
}
