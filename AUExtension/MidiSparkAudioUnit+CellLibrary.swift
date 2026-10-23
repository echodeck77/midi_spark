//  MidiSparkAudioUnit+CellLibrary.swift
//  The 8x8 CELL LIBRARY API of the AU class, split out of MidiSparkAudioUnit.swift 2026-10-23 (Fourfold Step 1a) so the Fourfold targets need not compile it. No behaviour change.

import Foundation

extension MidiSparkAudioUnit {
    // MARK: - CELL MACHINE stage-4 — the CELL LIBRARY (named saved cells, reusable across sessions)

    /// Save the cell at (col,row) to the library under `name` — "machine minus routing" (chain materialised +
    /// source-shaping; routing/perform state stripped). Returns false if the slot is empty or the write fails.
    // saveCellToLibrary RETIRED (Paul 2026-09-12 dead-code sweep — no caller; saveChainToLibrary is the live save path).
    // BUILD-side save: a MACHINE's machine (chain) becomes a library cell (no grid cell needed). Routing stripped.
    @discardableResult
    func saveChainToLibrary(machineID: String, chain: [ProcessorSlot], name: String) -> Bool {
        var c = Cell(machineID: machineID); c.processors = chain; c.buses = []
        return CellLibraryStore.save(c, as: name)
    }
    // Browser rows for SAVED cells: name + chain processor types + star rating (loads each cell).
    func libraryCellSummaries() -> [LibEntry] {
        CellLibraryStore.list().map { name in
            let c = CellLibraryStore.load(name)
            return LibEntry(name: name, types: (c?.processors ?? []).map { $0.type }, stars: c?.starsResolved ?? 0)
        }
    }
    // Browser rows for the read-only FACTORY set (curated star ratings).
    func factoryLibrarySummaries() -> [LibEntry] {
        CellLibraryStore.factory().map { LibEntry(name: $0.name, types: ($0.cell.processors ?? []).map { $0.type }, stars: $0.cell.starsResolved) }
    }
    // The CHEAP curated factory cells only (no Dice.factorySet). The grid-selector seeds the library with these INSTANTLY at
    // startup, then appends the full set (incl. the slow Dice chains) via factoryLibrarySummaries in the background. (Paul 2026-09-11)
    func handFactorySummaries() -> [LibEntry] {
        CellLibraryStore.handFactory().map { LibEntry(name: $0.name, types: ($0.cell.processors ?? []).map { $0.type }, stars: $0.cell.starsResolved) }
    }
    // Re-rate a SAVED cell (0–5) and persist. Factory cells are read-only.
    func setLibraryStars(_ name: String, _ stars: Int) {
        guard var c = CellLibraryStore.load(name) else { return }
        c.stars = max(0, min(5, stars)); CellLibraryStore.save(c, as: name)
    }
    func loadLibraryCell(name: String) -> Cell? { CellLibraryStore.load(name) }
    func deleteLibraryCell(name: String) { CellLibraryStore.delete(name) }
    // Resolve a factory cell by name — check the CHEAP hand cells FIRST so tapping one doesn't trigger the slow Dice build
    // (Paul 2026-09-11); fall back to the full set for the Dice-generated names.
    func factoryLibraryCell(name: String) -> Cell? {
        CellLibraryStore.handFactory().first { $0.name == name }?.cell ?? CellLibraryStore.factory().first { $0.name == name }?.cell
    }
}
