//  AltStateTests.swift — ALT ferry (2026-11-14), §9.2 (persistence/defaults/clamps) + §9.3 (the cycle) + the §2.2 unit selector.
//  The alt STATE is one pure function the Router and every display share; here it is tested in isolation. Counting against the real Router (§9.4) and locating (§9.17) ride AltRouterTests once the engine lands.

import XCTest

final class AltStateTests: XCTestCase {

    // MARK: §9.3 — the cycle: (x mod L) >= m ⇒ alt

    func testTheCycle() {
        func states(main: Int, alt: Int, _ xs: ClosedRange<Int>) -> String {
            xs.map { euclideousAltState(main: main, alt: alt, x: $0).isAlt ? "A" : "M" }.joined()
        }
        XCTAssertEqual(states(main: 3, alt: 1, 0...7), "MMMAMMMA")   // §9.3
        XCTAssertEqual(states(main: 1, alt: 2, 0...7), "MAAMAAMA")   // §9.3
        // positions and edges
        XCTAssertEqual(euclideousAltState(main: 3, alt: 1, x: 0).pos, 0)
        XCTAssertTrue(euclideousAltState(main: 3, alt: 1, x: 3).isAlt)     // first alt unit
        XCTAssertFalse(euclideousAltState(main: 3, alt: 1, x: 4).isAlt)    // wraps back to main
        // m,a clamp to >= 1; a negative x (never produced by §2.2) wraps safely, not crashes
        XCTAssertFalse(euclideousAltState(main: 0, alt: 0, x: 0).isAlt)    // m,a clamp to 1 ⇒ L=2, p0 main
        XCTAssertTrue(euclideousAltState(main: 1, alt: 1, x: -1).isAlt)    // (-1 mod 2 → 1) ≥ 1
    }

    // MARK: §2.2 — the unit selector picks the right 0-based count

    func testTheUnitSelector() {
        XCTAssertEqual(euclideousAltX(unit: .step, hit: 7, step: 3, pass: 1, bar: 9), 3)
        XCTAssertEqual(euclideousAltX(unit: .hit,  hit: 7, step: 3, pass: 1, bar: 9), 7)
        XCTAssertEqual(euclideousAltX(unit: .pass, hit: 7, step: 3, pass: 1, bar: 9), 1)
        XCTAssertEqual(euclideousAltX(unit: .bar,  hit: 7, step: 3, pass: 1, bar: 9), 9)
    }

    // MARK: §9.2 — defaults, clamps, decode-tolerance, round-trip

    func testDefaults() {
        let l = EuclidLine()
        XCTAssertEqual(l.altUnitResolved, .hit)       // §1.1 default HIT
        XCTAssertEqual(l.altMainCountResolved, 3)
        XCTAssertEqual(l.altAltCountResolved, 1)
        XCTAssertFalse(l.usesAlt)                      // every pill off ⇒ the Router skips the alt branch (§3.7)
        XCTAssertFalse(l.altPart(notes: false).anyOn); XCTAssertFalse(l.altPart(notes: true).anyOn)
    }

    func testClampsAndUnknownEnum() {
        var l = EuclidLine()
        l.altMainCount = 0; l.altAltCount = 99
        XCTAssertEqual(l.altMainCountResolved, 1); XCTAssertEqual(l.altAltCountResolved, 16)
        var p = EuclideousAltPart(outOn: true, out: 0xFF, octOn: true, oct: 9, velOn: true, vel: 500, gateOn: true, gate: 0)
        XCTAssertEqual(p.outValue, 0x0F)              // masked to 4 bits
        XCTAssertEqual(p.octValue, 2); XCTAssertEqual(p.velValue, 127); XCTAssertEqual(p.gateValue, 1)
        p = EuclideousAltPart(octOn: true, oct: -9, velOn: true, vel: 0, gateOn: true, gate: 200)
        XCTAssertEqual(p.octValue, -2); XCTAssertEqual(p.velValue, 1); XCTAssertEqual(p.gateValue, 99)
        XCTAssertNil(EuclideousAltUnit(rawValue: "sideways"))   // §1.3: an unknown enum value folds to nil ⇒ the default
    }

    func testAnyOnReflectsEachPill() {
        XCTAssertTrue(EuclideousAltPart(outOn: true).anyOn)
        XCTAssertTrue(EuclideousAltPart(octOn: true).anyOn)
        XCTAssertTrue(EuclideousAltPart(velOn: true).anyOn)
        XCTAssertTrue(EuclideousAltPart(gateOn: true).anyOn)
        XCTAssertFalse(EuclideousAltPart(outOn: false, out: 0b1010).anyOn)   // a stored value with the pill off is not "on" (§1.2)
        var l = EuclidLine(); l.altNotes = EuclideousAltPart(velOn: true, vel: 100); XCTAssertTrue(l.usesAlt)
    }

    // §9.17 — locating at a tick gives the same cycle states as playing through (the display helper the cycle strip + §5.9 marks use).
    func testLocateMatchesTheCycle() {
        let cfg = EuclideousWalkLaneConfig(buf: [Bool](repeating: true, count: 8), n: 8, dir: .fwd, sub: 0.5)   // every step a hit ⇒ tick i is hit ordinal i
        var line = EuclidLine(); line.altUnit = .hit; line.altMainCount = 3; line.altAltCount = 1
        for i in 0..<8 { XCTAssertEqual(euclideousAltStateAtTick(line: line, cfg: cfg, tick: Int64(i), beat: Double(i) * 0.5, barBeats: 4).isAlt, i % 4 == 3, "HIT 3/1 at hit \(i)") }
        line.altUnit = .step; line.altMainCount = 2; line.altAltCount = 2   // STEP 2/2 ⇒ alt at step indices 2,3,6,7
        for i in 0..<8 { XCTAssertEqual(euclideousAltStateAtTick(line: line, cfg: cfg, tick: Int64(i), beat: Double(i) * 0.5, barBeats: 4).isAlt, (i % 4) >= 2, "STEP 2/2 at step \(i)") }
        line.altUnit = .bar; line.altMainCount = 1; line.altAltCount = 1   // BAR 1/1 ⇒ alt on odd host bars
        for bar in 0..<4 { XCTAssertEqual(euclideousAltStateAtTick(line: line, cfg: cfg, tick: Int64(bar * 8), beat: Double(bar) * 4, barBeats: 4).isAlt, bar % 2 == 1, "BAR 1/1 at bar \(bar)") }
    }

    func testRoundTripAndMissingFieldsDecodeToDefaults() throws {
        // a document WITHOUT the fields decodes to the defaults
        let bare = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(EuclidLine()))
        XCTAssertNil(bare.altUnit); XCTAssertNil(bare.altMainCount); XCTAssertNil(bare.altRiff); XCTAssertNil(bare.altNotes)
        XCTAssertEqual(bare.altUnitResolved, .hit)
        // a populated ALT state round-trips exactly (the hand-written decoder reads every field, §1.3)
        var l = EuclidLine()
        l.altUnit = .pass; l.altMainCount = 7; l.altAltCount = 4
        l.altRiff = EuclideousAltPart(outOn: true, out: 0b0101, octOn: true, oct: -2, velOn: true, vel: 120, gateOn: true, gate: 45)
        l.altNotes = EuclideousAltPart(outOn: true, out: 0)   // a rest
        let l2 = try JSONDecoder().decode(EuclidLine.self, from: try JSONEncoder().encode(l))
        XCTAssertEqual(l2.altUnit, .pass); XCTAssertEqual(l2.altMainCount, 7); XCTAssertEqual(l2.altAltCount, 4)
        XCTAssertEqual(l2.altRiff, l.altRiff); XCTAssertEqual(l2.altNotes, l.altNotes)
        XCTAssertEqual(l2.altNotes?.out, 0)   // a rest (out 0) survives — not confused with nil
    }
}
