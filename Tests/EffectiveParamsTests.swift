//  EffectiveParamsTests.swift
//  Off-device tests for the morph/A→B interpolation rules (§3.2 / §13.5) in Snapshot.swift.
//  These are the regression-prone bit of morph: continuous fields interpolate linearly, STEPPED
//  fields must quantize to a legal value (never glide), and MASTER composes per §13.5.

import XCTest

final class EffectiveParamsTests: XCTestCase {

    private func colour(_ build: (inout SnapColour) -> Void) -> SnapColour {
        var c = SnapColour(); build(&c); return c
    }

    // MARK: effectiveT — tier-aware ALT/morph (delta §9 item 5; morphMaster retired)

    func testEffectiveTByTier() {
        // FULL pair: ALT pins full-B, else the per-Colour morph macro.
        let full = colour { $0.tier = .full }
        XCTAssertEqual(effectiveT(full, morph: 0.2, alt: true), 1.0)
        XCTAssertEqual(effectiveT(full, morph: 0.2, alt: false), 0.2, accuracy: 1e-9)
        // SWAP pair: BINARY — ALT flips fully, the morph fader is inert ("the fader never lies").
        let swap = colour { $0.tier = .swap }
        XCTAssertEqual(effectiveT(swap, morph: 0.7, alt: false), 0.0)
        XCTAssertEqual(effectiveT(swap, morph: 0.3, alt: true), 1.0)
        // UNPAIRED: inert — always A regardless of morph/alt.
        let none = colour { $0.tier = .none }
        XCTAssertEqual(effectiveT(none, morph: 0.9, alt: true), 0.0)
    }

    func testEffectiveTypeAndPassMaskFlipAtMidpoint() {
        // A SWAP pair carries the partner's type/mask in b; render flips to it past t=0.5.
        let c = colour { $0.a.type = .arp; $0.b.type = .passgate; $0.a.passMask = 0b1111; $0.b.passMask = 0b0101 }
        XCTAssertEqual(effectiveType(c, t: 0), .arp)
        XCTAssertEqual(effectiveType(c, t: 0.49), .arp)
        XCTAssertEqual(effectiveType(c, t: 0.5), .passgate)
        XCTAssertEqual(effectiveType(c, t: 1), .passgate)
        XCTAssertEqual(effectivePassMask(c, t: 0), 0b1111)
        XCTAssertEqual(effectivePassMask(c, t: 1), 0b0101)
    }

    // MARK: stepped fields quantize (§3.2) — the important rule: step, never glide

    func testRateQuantizesToLadder() {
        // A = 1/16 (index 3, 0.25 beats), B = 1/32 (index 5, 0.125). Every t must land ON a ladder
        // value — never an interpolated in-between like 0.1875.
        let c = colour { $0.a.rateIndex = 3; $0.b.rateIndex = 5 }
        XCTAssertEqual(effectiveRateBeats(c, t: 0), 0.25, accuracy: 1e-12)
        XCTAssertEqual(effectiveRateBeats(c, t: 1), 0.125, accuracy: 1e-12)
        let ladder = Set(Snap.arpRateBeats)
        for i in 0...10 {
            let v = effectiveRateBeats(c, t: Double(i) / 10)
            XCTAssertTrue(ladder.contains(v), "rate \(v) at t=\(Double(i)/10) is off the ladder")
        }
    }

    func testOctavesQuantize() {
        let c = colour { $0.a.octaves = 1; $0.b.octaves = 3 }
        XCTAssertEqual(effectiveOctaves(c, t: 0), 1)
        XCTAssertEqual(effectiveOctaves(c, t: 1), 3)
        XCTAssertEqual(effectiveOctaves(c, t: 0.5), 2)   // rounds, stays integer
        for i in 0...10 { XCTAssertTrue((1...4).contains(effectiveOctaves(c, t: Double(i) / 10))) }
    }

    func testRepeatsQuantizeToLegalCounts() {
        // Legal ratchet counts are 2/3/4/6/8 — 5 and 7 are illegal and must never be produced.
        let c = colour { $0.a.count = 2; $0.b.count = 8 }
        let legal: Set<Int> = [2, 3, 4, 6, 8]
        for i in 0...20 {
            XCTAssertTrue(legal.contains(effectiveRepeats(c, t: Double(i) / 20)))
        }
        XCTAssertEqual(effectiveRepeats(c, t: 0), 2)
        XCTAssertEqual(effectiveRepeats(c, t: 1), 8)
    }

    // MARK: continuous fields interpolate linearly (§3.2)

    func testGateInterpolatesLinearly() {
        let c = colour { $0.a.gate = 0.6; $0.b.gate = 1.0 }
        XCTAssertEqual(effectiveGate(c, t: 0.5), 0.8, accuracy: 1e-9)   // linear midpoint
    }

    func testSpreadProbabilityRampLinearAndClamped() {
        let c = colour { $0.a.spread = 0.1; $0.b.spread = 0.5
                         $0.a.probability = 0.2; $0.b.probability = 1.0
                         $0.a.ramp = 0; $0.b.ramp = 1 }
        XCTAssertEqual(effectiveSpread(c, t: 0.5), 0.3, accuracy: 1e-9)
        XCTAssertEqual(effectiveProbability(c, t: 0.5), 0.6, accuracy: 1e-9)
        XCTAssertEqual(effectiveRamp(c, t: 0.5), 0.5, accuracy: 1e-9)
        // clamped to [0,1] even if A/B were pushed past the ends
        XCTAssertGreaterThanOrEqual(effectiveProbability(colour { $0.a.probability = 0; $0.b.probability = 0 }, t: 2), 0)
    }
}
