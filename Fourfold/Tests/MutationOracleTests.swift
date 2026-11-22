//  MutationOracleTests.swift — ENGINE HARDENING 1 (2026-11-21), §6 kill oracle.
//  A FAST, high-coverage pin of the rendered MIDI stream for a spread of corpus documents — the oracle the
//  mutation check (Scripts/mutation-check.py) runs after each one-line mutation of Derivations/Router/
//  SnapshotBuilder. Any mutation that changes a single emitted byte for any of these documents moves a hash
//  and fails here (the mutant is KILLED). It renders in a few seconds so a mutant costs ~a rebuild, not a
//  20-minute suite. It is also a plain regression pin in the normal suite.
//
//  Re-pin after an INTENTIONAL engine change (same CAPTURE-line workflow as the other goldens): run it, paste
//  the printed CAPTURE values, note why. These are NOT a second sound oracle — the harness golden is that —
//  they exist to be dense and fast for mutation scoring.

import XCTest

final class MutationOracleTests: XCTestCase {

    /// FNV-1a over every emitted (sample, cable, b0, b1, b2) of an 8-bar render under a held C-major chord.
    private func hash(_ name: String) -> (UInt64, Int) {
        let doc = (HardeningCorpus.presets + HardeningCorpus.authored).first { $0.name == name }!.make()
        let rec = HardeningCorpus.renderContinuous(doc, beats: 32)
        var h: UInt64 = 0xcbf29ce484222325
        func mix(_ v: UInt64) { h = (h ^ v) &* 0x100000001b3 }
        for e in rec.events { mix(UInt64(bitPattern: e.sample)); mix(UInt64(e.cable)); mix(UInt64(e.b0)); mix(UInt64(e.b1)); mix(UInt64(e.b2)) }
        return (h, rec.events.count)
    }

    // A spread across the feature map incl. the mutation-targeted edges (tilt/custom/tie/root).
    private let pins: [String: (UInt64, Int)] = [
        "(default)": (5483164581228339621, 264),
        "CHORD ARP": (14912749089064120033, 560),
        "EUCLID directions": (13557268081135209563, 700),
        "EUCLID custom tiny": (7022300638227720763, 864),
        "FIVE ON EIGHT": (8381925510441271585, 356),
        "INPUTS lanes apart": (8530612876838366861, 264),
        "INPUTS root transpose": (4970920666746730001, 264),
        "MIX routing": (4307192896080910421, 200),
        "RIFF LEAD": (8252341453779098091, 240),
        "RIFF tie advance": (2280704568982536861, 264),
        "RIFF walks": (16994671481090744181, 264),
        "STACK ARP": (325616040662575821, 560),
        "STACK lit": (16654341988918432671, 348),
        ]

    func testTheMutationOraclePinsHold() {
        var captures: [String] = []
        var failed = false
        for (name, want) in pins.sorted(by: { $0.key < $1.key }) {
            let (h, n) = hash(name)
            captures.append("        \"\(name)\": (\(h), \(n)),")
            if want.0 == 0 { failed = true; continue }   // uncaptured pin
            if (h, n) != want { failed = true; XCTFail("\(name): (\(h), \(n)) != pinned \(want)") }
        }
        if failed { print("MUTATION ORACLE CAPTURE:\n" + captures.joined(separator: "\n")) }
        XCTAssertFalse(pins.values.contains { $0.0 == 0 }, "mutation oracle has uncaptured pins — paste the CAPTURE block")
    }
}
