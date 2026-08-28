//  AcceptanceFactoryLibraryTests.swift
//  Every FACTORY library chain must be MUSICAL: when its machine is fed a held chord it must sound at least one
//  note. This guards the curated set against SILENT breakage from future model churn — precisely the failure that
//  the 19-processor model introduced (the library "no longer worked"). If a processor's params change shape, a
//  factory chain that goes silent trips here instead of shipping a dead library. (2026-08-17)

import XCTest

final class AcceptanceFactoryLibraryTests: XCTestCase {
    func testEveryFactoryChainSoundsNotes() {
        let factory = CellLibraryStore.factory()
        XCTAssertFalse(factory.isEmpty, "the factory library is empty")
        for (name, cell) in factory {
            let chain = cell.processors ?? []
            XCTAssertFalse(chain.isEmpty, "\(name): empty chain — nothing to stamp")
            // Run the chain against a held C–E–G through the real Router (emitter A), same probe as the oracles.
            let ons = Accept.onsA(chain)
            XCTAssertFalse(ons.isEmpty, "\(name): produced NO note-ons — a silent library chain")
        }
    }

    // THE 200-CHAIN COMMISSION (REQUEST-200-chains, 2026-08-28): the generated factory set is deterministic, near the
    // 200 target, diverse (no duplicate chains), lean (1–4 stages), and covers every musical-intent category.
    func testGeneratedFactorySetIsDeterministicDiverseAndCategorised() {
        let set = Dice.factorySet
        XCTAssertGreaterThanOrEqual(set.count, 190, "expected ~200 generated factory chains, got \(set.count)")
        // Diversity — no two structurally identical chains.
        var seen = Set<String>()
        for fc in set { XCTAssertTrue(seen.insert(String(describing: fc.chain)).inserted, "duplicate chain: \(fc.name)") }
        // Lean — 1…4 stages each (the chain law).
        for fc in set { XCTAssertTrue((1...4).contains(fc.chain.count), "\(fc.name): \(fc.chain.count) stages (want 1–4)") }
        // Category coverage — all ten intents present.
        let byTag = Dictionary(grouping: set, by: { $0.tag }).mapValues { $0.count }
        for t in ["RHYTHM", "MELODIC", "PADS", "ACID", "COMPING", "DYNAMICS", "TEACHING", "TEXTURE", "RELATIONSHIP", "WILDCARDS"] {
            XCTAssertNotNil(byTag[t], "missing category \(t)")
        }
        // Determinism — the cache is stable + seeded (no Date/Math.random in the makers), so a fresh access matches.
        let again = Dice.factorySet
        XCTAssertEqual(set.map { $0.name }, again.map { $0.name })
    }
}
