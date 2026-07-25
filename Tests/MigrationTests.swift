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
        XCTAssertEqual(d.formatVersion, 4)                       // migration now also synthesizes receivers
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
        XCTAssertEqual(f.formatVersion, 4)                       // v3 graph + receivers
        XCTAssertEqual(f.receivers?.count, 4)                    // four OMNI receivers seeded
        // factory: vermilion at (2,0) stacked, magenta at (2,1) → magenta references row 0
        XCTAssertEqual(f.scenes[0].cells[2][1]?.inputRow, 0)
        XCTAssertNil(f.scenes[0].cells[0][0]?.inputRow)          // an unfed top cell
    }

    // MARK: - RECEIVERS (delta §9 item 11) — synthesis from legacy per-cell filters

    func testSynthesizeReceiversFromDistinctInputChannels() {
        let d0 = doc({ s in
            s.cells[0][0] = { var c = Cell(colourID: "gold"); c.inputChannel = 0; return c }()   // OMNI
            s.cells[1][0] = { var c = Cell(colourID: "gold"); c.inputChannel = 3; return c }()   // ch 3
            s.cells[2][0] = { var c = Cell(colourID: "gold"); c.inputChannel = 0; return c }()   // OMNI again
            s.cells[3][0] = { var c = Cell(colourID: "gold"); c.inputChannel = 5; return c }()   // ch 5
        }, version: 3)
        var d = d0; d.synthesizeReceiversIfNeeded()
        XCTAssertEqual(d.receivers?.map { $0.channel }, [0, 3, 5, 0])   // order of appearance, padded OMNI
        XCTAssertEqual(d.scenes[0].cells[0][0]?.inputReceiver, 0)       // OMNI → R1
        XCTAssertEqual(d.scenes[0].cells[1][0]?.inputReceiver, 1)       // ch3 → R2
        XCTAssertEqual(d.scenes[0].cells[2][0]?.inputReceiver, 0)       // OMNI → R1
        XCTAssertEqual(d.scenes[0].cells[3][0]?.inputReceiver, 2)       // ch5 → R3
        XCTAssertEqual(d.formatVersion, 4)
        var again = d; again.synthesizeReceiversIfNeeded()             // idempotent
        XCTAssertEqual(again.receivers?.count, 4)
    }

    func testSynthesizeReceiversOverflowCollapsesToReceiverOne() {
        let d0 = doc({ s in
            for (i, ch) in [1, 2, 3, 4, 5, 6].enumerated() {          // 6 distinct > 4
                s.cells[i][0] = { var c = Cell(colourID: "gold"); c.inputChannel = ch; return c }()
            }
        }, version: 3)
        var d = d0; d.synthesizeReceiversIfNeeded()
        XCTAssertEqual(d.receivers?.map { $0.channel }, [1, 2, 3, 4])  // first four kept
        XCTAssertEqual(d.scenes[0].cells[3][0]?.inputReceiver, 3)      // ch4 → R4
        XCTAssertEqual(d.scenes[0].cells[4][0]?.inputReceiver, 0)      // ch5 overflow → R1
        XCTAssertEqual(d.scenes[0].cells[5][0]?.inputReceiver, 0)      // ch6 overflow → R1
    }

    func testSynthesizeReceiversDefaultsToOmniWhenNoMidiInCells() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 3
        d.synthesizeReceiversIfNeeded()
        XCTAssertEqual(d.receivers?.count, 4)
        XCTAssertEqual(d.receivers?.allSatisfy { $0.channel == 0 }, true)   // all OMNI
    }

    func testReceiversRoundTripThroughJSON() throws {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.receivers = [Receiver(name: "Keys", channel: 1, mpeMerge: true, muted: false),
                       Receiver(name: "Pads", channel: 2, mpeMerge: false, muted: true),
                       Receiver(name: "3"), Receiver(name: "4")]
        let reloaded = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(d))
        XCTAssertEqual(reloaded.receivers?[0], Receiver(name: "Keys", channel: 1, mpeMerge: true, muted: false))
        XCTAssertEqual(reloaded.receivers?[1].muted, true)
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
        root.removeValue(forKey: "receivers")                        // nor RECEIVERS (§9 item 11)
        var scene = (root["scenes"] as! [[String: Any]])[0]
        scene["rowBypass"] = [false, false, false]                   // dead keys an old doc still carries
        scene["stackMute"] = [true]; scene["stackSolo"] = [false]
        root["scenes"] = [scene]
        let mutated = try JSONSerialization.data(withJSONObject: root)
        let reloaded = try JSONDecoder().decode(PluginState.self, from: mutated)   // must NOT throw
        XCTAssertNil(reloaded.busEnabled, "missing busEnabled → nil")
        XCTAssertEqual(reloaded.busEnabledResolved, [true, true, true, true], "nil ⇒ all enabled")
        XCTAssertNil(reloaded.claimEmitter, "missing claimEmitter → nil (no claim)")
        XCTAssertNil(reloaded.receivers, "missing receivers → nil (loader synthesizes on entry)")
        XCTAssertEqual(reloaded.receiversResolved.count, 4, "resolved helper is nil-safe ⇒ four OMNI")
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
        reloaded.migrateLegacyRoutingIfNeeded()                  // no-op: already v4 (receivers present)
        XCTAssertEqual(reloaded.scenes[0].cells[0][1]?.inputRow, 0)
        XCTAssertNil(reloaded.scenes[0].cells[3][0]?.inputRow)
        XCTAssertEqual(reloaded.formatVersion, 4)
    }
}

// MARK: - UndoStack (delta §5 / a6)

final class UndoStackTests: XCTestCase {

    func testUndoRedoWalksHistory() {
        var s = UndoStack<Int>()
        s.record(0)                              // before 0→1
        s.record(1)                              // before 1→2 ; live value is now 2
        XCTAssertTrue(s.canUndo); XCTAssertFalse(s.canRedo)
        XCTAssertEqual(s.undo(current: 2), 1)
        XCTAssertEqual(s.undo(current: 1), 0)
        XCTAssertNil(s.undo(current: 0))         // nothing older
        XCTAssertEqual(s.redo(current: 0), 1)
        XCTAssertEqual(s.redo(current: 1), 2)
        XCTAssertNil(s.redo(current: 2))
    }

    func testNewRecordClearsRedo() {
        var s = UndoStack<Int>()
        s.record(0); s.record(1)
        _ = s.undo(current: 2)                    // at 1, redo future = [2]
        XCTAssertTrue(s.canRedo)
        s.record(1)                              // a fresh edit invalidates redo
        XCTAssertFalse(s.canRedo)
    }

    func testCoalesceCollapsesSameKey() {
        var s = UndoStack<Int>()
        s.record(0, coalesceKey: "morph")        // pre-gesture value captured
        s.record(1, coalesceKey: "morph")        // mid-gesture → no new step
        s.record(2, coalesceKey: "morph")
        XCTAssertEqual(s.undo(current: 3), 0)     // one undo returns to the pre-gesture value
        XCTAssertNil(s.undo(current: 0))
    }

    func testCoalesceBreaksOnDifferentKey() {
        var s = UndoStack<Int>()
        s.record(0, coalesceKey: "a")
        s.record(1, coalesceKey: "b")            // different key → a distinct step
        XCTAssertEqual(s.undo(current: 2), 1)
        XCTAssertEqual(s.undo(current: 1), 0)
    }

    func testDiscreteRecordsNeverCoalesce() {
        var s = UndoStack<Int>()
        s.record(0); s.record(1)                 // nil key ⇒ always a new step
        XCTAssertEqual(s.undo(current: 2), 1)
        XCTAssertEqual(s.undo(current: 1), 0)
    }

    func testCapDropsOldest() {
        var s = UndoStack<Int>(cap: 3)
        for i in 0..<5 { s.record(i) }           // keep the last 3 pre-values: 2,3,4
        XCTAssertEqual(s.undo(current: 5), 4)
        XCTAssertEqual(s.undo(current: 4), 3)
        XCTAssertEqual(s.undo(current: 3), 2)
        XCTAssertNil(s.undo(current: 2))         // 0,1 were dropped by the cap
    }
}

// MARK: - Cell relocation (delta §5 drag-and-drop)

final class CellRelocationTests: XCTestCase {
    func testSwapCellsMovesToEmptyPreservingFields() {
        var s = SceneState.empty()
        s.cells[0][0] = { var c = Cell(colourID: "gold", buses: [.b]); c.inputRow = 3; return c }()
        s.swapCells((0, 0), (2, 5))                    // move onto an empty slot
        XCTAssertNil(s.cells[0][0])
        XCTAssertEqual(s.cells[2][5]?.colourID, "gold")
        XCTAssertEqual(s.cells[2][5]?.inputRow, 3, "the reference moves as-is (fields sacred)")
        XCTAssertEqual(s.cells[2][5]?.buses, [.b])
    }
    func testSwapCellsSwapsTwoOccupied() {
        var s = SceneState.empty()
        s.cells[1][1] = Cell(colourID: "gold")
        s.cells[4][2] = Cell(colourID: "cyan")
        s.swapCells((1, 1), (4, 2))
        XCTAssertEqual(s.cells[1][1]?.colourID, "cyan")
        XCTAssertEqual(s.cells[4][2]?.colourID, "gold")
    }
    func testSwapCellsSelfAndOutOfRangeAreNoOps() {
        var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold")
        s.swapCells((0, 0), (0, 0))                    // self → no-op
        XCTAssertEqual(s.cells[0][0]?.colourID, "gold")
        s.swapCells((0, 0), (9, 9))                    // out of range → no-op
        XCTAssertEqual(s.cells[0][0]?.colourID, "gold")
    }
}

// MARK: - StampConfig (delta §5) — session template / clipboard round trip

final class StampConfigTests: XCTestCase {
    func testFromCellAndBackRoundTrips() {
        var c = Cell(colourID: "cyan", buses: [.b, .d]); c.inputRow = 3; c.inputReceiver = 2
        let t = StampConfig.from(c)
        XCTAssertEqual(t.colourID, "cyan")
        XCTAssertEqual(t.inputRow, 3)
        XCTAssertEqual(t.inputReceiver, 2)
        XCTAssertEqual(t.buses, [.b, .d])
        let made = t.makeCell()
        XCTAssertEqual(made.colourID, "cyan")
        XCTAssertEqual(made.inputRow, 3)
        XCTAssertEqual(made.inputReceiver, 2)
        XCTAssertEqual(made.buses, [.b, .d])
    }
    func testBootstrapIsMidiReceiver1EmitA() {
        let t = StampConfig.bootstrap(colourID: "gold")
        XCTAssertNil(t.inputRow)                 // ⇐ MIDI
        XCTAssertEqual(t.inputReceiver, 0)       // Receiver 1
        XCTAssertEqual(t.buses, [.a])            // → A
    }
    // applyRouting overwrites input + buses but LEAVES the colour (staging live-propagation to placed cells).
    func testApplyRoutingKeepsColour() {
        var c = Cell(colourID: "rose", buses: [.a]); c.inputRow = nil; c.inputReceiver = 0
        var t = StampConfig(colourID: "ignored"); t.inputRow = 5; t.inputReceiver = 3; t.buses = [.c, .d]
        t.applyRouting(to: &c)
        XCTAssertEqual(c.colourID, "rose", "colour is not part of routing")
        XCTAssertEqual(c.inputRow, 5)
        XCTAssertEqual(c.inputReceiver, 3)
        XCTAssertEqual(c.buses, [.c, .d])
    }
}

// MARK: - fullState preview-exclusion (staging: a host autosave mid-hover must not persist the preview)

final class PreviewOverlayTests: XCTestCase {
    private func doc(with cell: Cell?, at col: Int, _ row: Int) -> PluginState {
        var d = PluginState.factory()
        d.scenes[d.activeScene].cells[col][row] = cell
        return d
    }
    func testRestoringCellReplacesActiveSceneCell() {
        let preview = Cell(colourID: "gold")
        let d = doc(with: preview, at: 3, 4)                    // preview cell sitting in the document
        let restored = d.restoringCell(col: 3, row: 4, to: nil) // encode with the covered (empty) cell
        XCTAssertNil(restored.scenes[restored.activeScene].cells[3][4], "preview stripped for encoding")
        XCTAssertEqual(d.scenes[d.activeScene].cells[3][4]?.colourID, "gold", "the live document is untouched")
    }
    func testRestoringCellRestoresACoveredCell() {
        let covered = Cell(colourID: "cyan")
        var d = doc(with: Cell(colourID: "gold"), at: 1, 1)     // preview covering a cyan cell
        let restored = d.restoringCell(col: 1, row: 1, to: covered)
        XCTAssertEqual(restored.scenes[restored.activeScene].cells[1][1]?.colourID, "cyan")
        _ = d
    }
    func testRestoringCellOutOfRangeIsNoOp() {
        let d = PluginState.factory()
        XCTAssertEqual(d.restoringCell(col: 9, row: 0, to: nil), d)
        XCTAssertEqual(d.restoringCell(col: 0, row: 99, to: nil), d)
    }
    // The end-to-end guarantee: encode with an active overlay yields the restored cell, not the preview.
    func testEncodeWithOverlayDropsPreview() throws {
        let d = doc(with: Cell(colourID: "gold"), at: 2, 2)     // gold preview live in the doc
        let encodeDoc = d.restoringCell(col: 2, row: 2, to: nil)
        let data = try JSONEncoder().encode(encodeDoc)
        let decoded = try JSONDecoder().decode(PluginState.self, from: data)
        XCTAssertNil(decoded.scenes[decoded.activeScene].cells[2][2], "the reloaded preset has no preview cell")
    }
}

// MARK: - ON trigger config (§9 item 1, GUI iteration 1) — schema + persistence

final class OnConfigTests: XCTestCase {
    func testDefaultIsEmpty() {
        let c = OnConfig()
        XCTAssertTrue(c.isEmpty)
        XCTAssertEqual(c.tap, .none); XCTAssertEqual(c.hold, .none)
        XCTAssertEqual(c.arrive, .none); XCTAssertEqual(c.leave, .none)
        XCTAssertFalse(c.sceneEntrance); XCTAssertFalse(c.sceneAutoArm)
        XCTAssertEqual(c.tapSummary, ""); XCTAssertEqual(c.holdSummary, "")
        XCTAssertEqual(c.arriveSummary, ""); XCTAssertEqual(c.sceneSummary, "")
    }
    func testCodableRoundTripAllFields() throws {
        var c = OnConfig()
        c.tap = .fill; c.tapWhen = .pass; c.tapFor = .oneLap
        c.hold = .oct; c.octUp = false; c.holdRelease = .latch
        c.arrive = .morphDrift; c.driftMode = .pingpong; c.driftPct = 25; c.arriveEvery = 3
        c.leave = .exitStab
        c.sceneEntrance = true; c.entrancePass = 4; c.sceneExit = true; c.exitPass = 12; c.sceneResetMorph = true
        let back = try JSONDecoder().decode(OnConfig.self, from: JSONEncoder().encode(c))
        XCTAssertEqual(c, back)
        XCTAssertFalse(back.isEmpty)
    }
    // Old (pre-ON) doc: a Colour JSON with no `on` key must decode, resolving to the empty config.
    func testColourWithoutOnKeyDecodes() throws {
        let full = Colour(colourID: "gold", type: .arp)                        // on defaults to nil
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(full)) as! [String: Any]
        dict.removeValue(forKey: "on")                                          // simulate a pre-ON document
        let back = try JSONDecoder().decode(Colour.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertNil(back.on)
        XCTAssertTrue(back.onResolved.isEmpty)
    }
    func testColourRoundTripCarriesOn() throws {
        var col = Colour(colourID: "cyan", type: .chance)
        var on = OnConfig(); on.tap = .mute; on.sceneResetMorph = true; col.on = on
        let back = try JSONDecoder().decode(Colour.self, from: JSONEncoder().encode(col))
        XCTAssertEqual(back.on?.tap, .mute)
        XCTAssertEqual(back.on?.sceneResetMorph, true)
    }
    func testSummaries() {
        var c = OnConfig()
        c.arrive = .morphDrift; c.driftMode = .pingpong; c.driftPct = 10; c.arriveEvery = 2
        XCTAssertEqual(c.arriveSummary, "MORPH-DRIFT ⇄ 10% · every 2")
        c.hold = .sliceCycle; c.sliceSize = .eighth; c.holdRelease = .spring
        XCTAssertEqual(c.holdSummary, "SLICE-CYCLE · SPRING · ⅛")
        c.tap = .solo; c.tapWhen = .lap; c.tapFor = .onePass
        XCTAssertEqual(c.tapSummary, "SOLO EMITTERS · LAP · 1 PASS")
        c.sceneEntrance = true; c.entrancePass = 3; c.sceneExit = true; c.exitPass = 7
        XCTAssertEqual(c.sceneSummary, "ENTER 3 · EXIT 7")
        c.leave = .exitStab
        XCTAssertEqual(c.leaveSummary, "EXIT STAB")
    }
}
