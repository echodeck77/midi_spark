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

    // THE REGENERATED RANGE (Paul 2026-09-11): chains of up to 4 processors, EQUAL weighting on lengths 1/2/3/4, with
    // euclid/arp/ratchet/riff/cc prominent, consonant (no clashing intervals), non-chaotic, and NO PASSGATE.
    func testRegeneratedFactorySetMatchesTheSpec() {
        let set = Dice.factorySet
        // Diversity — no two structurally identical chains.
        var seen = Set<String>()
        for fc in set { XCTAssertTrue(seen.insert(String(describing: fc.chain)).inserted, "duplicate chain: \(fc.name)") }
        // Lean — 1…4 stages each (the chain law).
        for fc in set { XCTAssertTrue((1...4).contains(fc.chain.count), "\(fc.name): \(fc.chain.count) stages (want 1–4)") }
        // EQUAL weighting across the four lengths (tagged SOLO/PAIR/TRIO/QUAD).
        let byLen = Dictionary(grouping: set, by: { $0.chain.count }).mapValues { $0.count }
        XCTAssertEqual(set.count, 200, "expected 4×50 = 200 machines, got \(set.count)")
        for len in 1...4 { XCTAssertEqual(byLen[len], 50, "length \(len): expected 50, got \(byLen[len] ?? 0)") }
        // NO PASSGATE anywhere (Paul's hard exclusion).
        for fc in set { XCTAssertFalse(fc.chain.contains { $0.type == .passgate }, "\(fc.name): contains PASSGATE") }
        // The prominent types are all well represented.
        for t in [ProcessorType.euclid, .arp, .ratchet, .riff, .mod] {
            let n = set.filter { $0.chain.contains { s in s.type == t } }.count
            XCTAssertGreaterThanOrEqual(n, 10, "expected \(t) prominent, only \(n) machines feature it")
        }
        // CONSONANT — every HARMONIZE interval is a perfect 4th/5th/octave/12th (or a stack), never a 3rd/2nd/tritone.
        let consonant: Set<Int> = [0, 5, 7, 12, 17, 19, 24]   // unison · P4 · P5 · octave · +P4 · +P5 · 2 octaves
        for fc in set {
            for slot in fc.chain where slot.type == .harmonize {
                for iv in (slot.params.harmIntervals ?? []) {
                    XCTAssertTrue(consonant.contains(iv), "\(fc.name): discordant harmonize interval \(iv)")
                }
            }
        }
        // BROWSABLE — every machine matches a SELECT rail row (contains a driver or CC), so none is invisible.
        let railTypes: Set<ProcessorType> = [.arp, .riff, .euclid, .ratchet, .cascade, .strum, .weave, .burst, .mod]
        for fc in set { XCTAssertTrue(fc.chain.contains { railTypes.contains($0.type) }, "\(fc.name): no rail-visible type") }
        // Determinism — the cache is stable + seeded (no Date/Math.random in the makers), so a fresh access matches.
        let again = Dice.factorySet
        XCTAssertEqual(set.map { $0.name }, again.map { $0.name })
    }
}
