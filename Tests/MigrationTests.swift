//  MigrationTests.swift
//  Off-device tests for the v2 → v3.0 loader migration (migration-tree-routing.md §1, commit 1):
//  chain (▾ stack) config → receiver-picked inputRow references. Protects existing saved sessions.

import XCTest

final class MigrationTests: XCTestCase {

    private func doc(_ build: (inout SceneState) -> Void, version: Int = 2) -> PluginState {
        var s = SceneState.empty(); build(&s)
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [s])
        d.formatVersion = version
        return d
    }

    func testFedCellReferencesTheStackedRowAbove() {
        var d = doc { s in
            s.cells[0][0] = Cell(colourID: "gold", stack: true)   // v2 feeder
            s.cells[0][1] = Cell(colourID: "cyan")                // fed by row 0
        }
        d.migrateLegacyRoutingIfNeeded()
        XCTAssertEqual(d.scenes[0].cells[0][1]?.inputRow, 0)      // references row 0
        XCTAssertNil(d.scenes[0].cells[0][0]?.inputRow)          // top cell → MIDI IN
        XCTAssertEqual(d.formatVersion, 3)
    }

    func testUnstackedAboveMeansMidiIn() {
        var d = doc { s in
            s.cells[0][0] = Cell(colourID: "gold")               // NOT stacked
            s.cells[0][1] = Cell(colourID: "cyan")
        }
        d.migrateLegacyRoutingIfNeeded()
        XCTAssertNil(d.scenes[0].cells[0][1]?.inputRow)          // above not feeding → MIDI IN
    }

    func testSrcMixIsDroppedButReferenceKept() {
        var d = doc { s in
            s.cells[0][0] = Cell(colourID: "gold", stack: true)
            s.cells[0][1] = Cell(colourID: "cyan", srcMix: true) // +SRC has no v3 equivalent
        }
        d.migrateLegacyRoutingIfNeeded()
        XCTAssertEqual(d.scenes[0].cells[0][1]?.inputRow, 0)     // still references its parent
    }

    func testAlreadyV3IsUntouched() {
        var d = doc({ s in
            s.cells[0][1] = Cell(colourID: "cyan", inputRow: 5)  // explicit new-model reference
        }, version: 3)
        d.migrateLegacyRoutingIfNeeded()
        XCTAssertEqual(d.scenes[0].cells[0][1]?.inputRow, 5)     // gated by version → not re-derived
    }

    func testFactoryIsV3Consistent() {
        let f = PluginState.factory()
        XCTAssertEqual(f.formatVersion, 3)
        // factory: vermilion at (2,0) stacked, magenta at (2,1) → magenta references row 0
        XCTAssertEqual(f.scenes[0].cells[2][1]?.inputRow, 0)
        XCTAssertNil(f.scenes[0].cells[0][0]?.inputRow)          // an unfed top cell
    }

    func testNewOptionalFieldsRoundTripThroughJSON() throws {
        // busEnabled (§6a) + per-type transpose/morph stashes survive save/reload.
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 3
        d.busEnabled = [true, false, true, false]
        d.colours[0].transposeByType = [1, 2, 3, 4, 5, 6]
        d.colours[0].morphByType = [0, 0.25, 0.5, 0.75, 1, 0]
        d.claimEmitter = 2                          // §6a CLAIM (a7) — persisted
        let reloaded = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(d))
        XCTAssertEqual(reloaded.busEnabled, [true, false, true, false])
        XCTAssertEqual(reloaded.colours[0].transposeByType, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(reloaded.colours[0].morphByType, [0, 0.25, 0.5, 0.75, 1, 0])
        XCTAssertEqual(reloaded.claimEmitter, 2, "CLAIM survives save/reload")
    }

    func testOldSchemaDocDecodesDefaultsNewFieldsAndIgnoresRemovedKeys() throws {
        // Forward-compat guard for the refactor: an OLD save lacks busEnabled and still carries the
        // now-removed rowBypass/stackMute/stackSolo scene keys — it must decode without error, default
        // busEnabled to nil (⇒ all enabled), and simply ignore the dead keys.
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 3; d.busEnabled = [false, true, true, true]
        var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        root.removeValue(forKey: "busEnabled")                       // old docs never had it
        root.removeValue(forKey: "claimEmitter")                     // nor CLAIM (a7)
        var scene = (root["scenes"] as! [[String: Any]])[0]
        scene["rowBypass"] = [false, false, false]                   // dead keys an old doc still carries
        scene["stackMute"] = [true]; scene["stackSolo"] = [false]
        root["scenes"] = [scene]
        let mutated = try JSONSerialization.data(withJSONObject: root)
        let reloaded = try JSONDecoder().decode(PluginState.self, from: mutated)   // must NOT throw
        XCTAssertNil(reloaded.busEnabled, "missing busEnabled → nil")
        XCTAssertEqual(reloaded.busEnabledResolved, [true, true, true, true], "nil ⇒ all enabled")
        XCTAssertNil(reloaded.claimEmitter, "missing claimEmitter → nil (no claim)")
        XCTAssertEqual(reloaded.formatVersion, 3)                    // decoded despite the removed legacy keys
    }

    func testRoundTripThroughJSONIsStable() throws {
        var d = doc { s in
            s.cells[0][0] = Cell(colourID: "gold", stack: true)
            s.cells[0][1] = Cell(colourID: "cyan")               // fed → inputRow 0
            s.cells[3][0] = Cell(colourID: "teal")               // unfed → nil
        }
        d.migrateLegacyRoutingIfNeeded()
        let data = try JSONEncoder().encode(d)
        var reloaded = try JSONDecoder().decode(PluginState.self, from: data)
        reloaded.migrateLegacyRoutingIfNeeded()                  // no-op: already v3
        XCTAssertEqual(reloaded.scenes[0].cells[0][1]?.inputRow, 0)
        XCTAssertNil(reloaded.scenes[0].cells[3][0]?.inputRow)
        XCTAssertEqual(reloaded.formatVersion, 3)
    }
}
