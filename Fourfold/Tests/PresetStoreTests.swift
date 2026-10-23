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

    // sanitize() is many-to-one, so distinct names can map to the SAME filename → a save would silently clobber.
    // The browser now arms an OVERWRITE? confirm on PresetStore.exists (which keys on the sanitized name), so this
    // collision is surfaced, not silent. (Paul 2026-08-16, M3)
    func testSanitizeCollisionMapsDistinctNamesToOneFilename() {
        XCTAssertEqual(PresetStore.sanitize("My/Rig"), PresetStore.sanitize("MyRig"), "the slash is stripped → same filename")
        XCTAssertEqual(PresetStore.sanitize("A:B"), PresetStore.sanitize("AB"))
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
        doc.scenes[0].cells[2][3] = Cell(machineID: "gold", buses: [.a])
        doc.padScenes()
        doc.activeScene = 0
        guard let data = PresetStore.encode(doc), let back = PresetStore.decode(data) else {
            return XCTFail("encode/decode produced nil")
        }
        XCTAssertEqual(back.scenes[0].cells[2][3]?.machineID, "gold", "the saved cell survives the round-trip")
        XCTAssertEqual(back.scenes.count, doc.scenes.count, "all scene slots preserved")
    }

    func testDecodeMigratesLegacyDocuments() {
        // A v2-shaped document (formatVersion < 3) must come back migrated, exactly as fullState does on load.
        var legacy = PluginState.factory()
        legacy.formatVersion = 1
        legacy.scenes[0].cells[0][0] = Cell(machineID: "gold")
        guard let data = PresetStore.encode(legacy), let back = PresetStore.decode(data) else {
            return XCTFail("nil")
        }
        XCTAssertGreaterThanOrEqual(back.formatVersion, 3, "decode migrates old presets to the v3 schema")
    }


}
