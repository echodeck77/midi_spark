//  PresetStoreTests.swift
//  PRESETS v1 — the pure surface: name sanitization + the document round-trip (encode ∘ decode == identity).
//  File I/O (save/load/delete/list) is thin FileManager and device-verified, not exercised here.

import XCTest

final class PresetStoreTests: XCTestCase {

    func testSanitizeStripsPathAndReservedChars() {
        XCTAssertEqual(PresetStore.sanitize("My/Rig:1"), "MyRig1", "path + reserved chars removed")
        XCTAssertEqual(PresetStore.sanitize("  spaced   out  "), "spaced out", "trim + collapse whitespace")
        XCTAssertEqual(PresetStore.sanitize("../../etc/passwd"), "etcpasswd", "no directory traversal survives")
    }

    func testSanitizeNeverEmpty() {
        XCTAssertEqual(PresetStore.sanitize(""), "Untitled")
        XCTAssertEqual(PresetStore.sanitize("///"), "Untitled", "a name that sanitizes to nothing falls back")
        XCTAssertEqual(PresetStore.sanitize("   "), "Untitled")
    }

    func testSanitizeCapsLength() {
        XCTAssertLessThanOrEqual(PresetStore.sanitize(String(repeating: "x", count: 200)).count, 48)
    }

    func testDocumentRoundTripsThroughTheCodec() {
        var doc = PluginState.factory()
        doc.scenes[0].cells[2][3] = Cell(colourID: "gold", buses: [.a])
        doc.padScenes()
        doc.activeScene = 0
        guard let data = PresetStore.encode(doc), let back = PresetStore.decode(data) else {
            return XCTFail("encode/decode produced nil")
        }
        XCTAssertEqual(back.scenes[0].cells[2][3]?.colourID, "gold", "the saved cell survives the round-trip")
        XCTAssertEqual(back.scenes.count, doc.scenes.count, "all scene slots preserved")
    }

    func testDecodeMigratesLegacyDocuments() {
        // A v2-shaped document (formatVersion < 3) must come back migrated, exactly as fullState does on load.
        var legacy = PluginState.factory()
        legacy.formatVersion = 1
        legacy.scenes[0].cells[0][0] = Cell(colourID: "gold")
        guard let data = PresetStore.encode(legacy), let back = PresetStore.decode(data) else {
            return XCTFail("nil")
        }
        XCTAssertGreaterThanOrEqual(back.formatVersion, 3, "decode migrates old presets to the v3 schema")
    }

    // CELL MACHINE stage-4 — the CELL LIBRARY store: a saved Cell round-trips through the codec.
    func testCellLibraryRoundTripsThroughTheCodec() {
        var cell = Cell(colourID: "gold", buses: [.a])
        cell.processors = [ProcessorSlot(type: .passgate), { var s = ProcessorSlot(type: .arp); s.bypassed = true; return s }()]
        cell.chop = Chop(slots: Array(repeating: .alt, count: 8), altDest: [.b])
        guard let data = CellLibraryStore.encode(cell), let back = CellLibraryStore.decode(data) else {
            return XCTFail("encode/decode produced nil")
        }
        XCTAssertEqual(back.colourID, "gold")
        XCTAssertEqual(back.processors?.count, 2, "the chain survives the round-trip")
        XCTAssertEqual(back.processors?[1].bypassed, true, "per-slot bypass survives")
        XCTAssertEqual(back.chopResolved.altDest, [.b], "source-shaping (chop) survives")
    }

    // "Machine minus routing": the chain + source-shaping travel; input/output + perform state are stripped.
    func testLibraryStrippedKeepsMachineDropsRouting() {
        var cell = Cell(colourID: "gold", buses: [.a, .b])
        cell.inputRow = 2; cell.inputReceiver = 1; cell.alt = true; cell.muted = true
        cell.chop = Chop(slots: Array(repeating: .mute, count: 8), altDest: [])
        let s = cell.libraryStripped(materialisedChain: [ProcessorSlot(type: .harmonize), ProcessorSlot(type: .arp)])
        XCTAssertEqual(s.colourID, "gold")
        XCTAssertEqual(s.processors?.count, 2, "the materialised chain travels")
        XCTAssertEqual(s.chop?.slots.first, .mute, "source-shaping (chop) travels")
        XCTAssertNil(s.inputRow, "input row stripped"); XCTAssertNil(s.inputReceiver, "receiver stripped")
        XCTAssertTrue(s.buses.isEmpty, "output emitters stripped")
        XCTAssertFalse(s.alt); XCTAssertFalse(s.muted)   // perform state defaulted
    }

    // CELL MACHINE stage-4 — FACTORY cells: a non-empty read-only starter set, each a valid "machine minus routing".
    func testFactoryLibraryCellsAreValidMachinesMinusRouting() {
        let factory = CellLibraryStore.factory()
        XCTAssertGreaterThanOrEqual(factory.count, 3, "there are factory starter cells")
        for (name, cell) in factory {
            XCTAssertFalse(name.isEmpty)
            XCTAssertFalse(cell.processors?.isEmpty ?? true, "\(name) carries a non-empty chain")
            XCTAssertTrue(cell.buses.isEmpty, "\(name) has no output (machine minus routing)")
            XCTAssertNil(cell.inputRow); XCTAssertNil(cell.inputReceiver, "\(name) has no input routing")
            XCTAssertNotNil(colourIDs.firstIndex(of: cell.colourID), "\(name)'s colour is canonical")
        }
        let bloom = factory.first { $0.name == "Bloom" }!.cell   // round-trips like any saved cell
        let rt = try! JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(bloom))
        XCTAssertEqual(rt.processors?.count, 2, "Bloom = harmonize→arp")
    }
}
