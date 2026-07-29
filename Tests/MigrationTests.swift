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
        XCTAssertEqual(d.formatVersion, 5)                       // migration synthesizes receivers + folds pairs (item 8)
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
        XCTAssertEqual(f.receivers?.count, 4)                    // four receivers seeded
        XCTAssertEqual(f.receivers?.map { $0.channel }, [0, 2, 3, 4], "default routing: A=OMNI (out-of-box), B/C/D=ch 2/3/4")
        // factory: vermilion at (2,0) stacked, magenta at (2,1) → magenta references row 0
        XCTAssertEqual(f.scenes[0].cells[2][1]?.inputRow, 0)
        XCTAssertNil(f.scenes[0].cells[0][0]?.inputRow)          // an unfed top cell
        // Every MIDI-IN cell must be POINTED at a receiver — else it bypasses receiver mute (item 11 ruling).
        for scene in f.scenes {
            for col in scene.cells {
                for maybe in col where maybe != nil && maybe!.inputRow == nil {
                    XCTAssertNotNil(maybe!.inputReceiver, "a factory MIDI-IN cell must point at a receiver")
                }
            }
        }
    }

    // MARK: - §3b/3c THE DEFAULT ARC (first-launch music)

    func testDefaultArcIsThreeSceneSingleEmitter() {
        let d = PluginState.defaultArc()
        XCTAssertGreaterThanOrEqual(d.scenes.count, 3)
        XCTAssertFalse(d.scenes[0].isEmpty); XCTAssertFalse(d.scenes[1].isEmpty); XCTAssertFalse(d.scenes[2].isEmpty)
        XCTAssertTrue(d.scenes[3].isEmpty, "slots 4+ ship as + (empty)")
        // MINIMUM-RIG LAW (§3c): every cell routes to A only — the one-synth rig is always audible.
        for s in d.scenes.prefix(3) {
            for col in s.cells { for maybe in col where maybe != nil {
                XCTAssertEqual(maybe!.buses, [.a], "the default arc is single-emitter — everything → A")
            } }
        }
        // every MIDI-IN cell must point at a receiver (else it bypasses receiver mute/config).
        for s in d.scenes {
            for col in s.cells { for maybe in col where maybe != nil && maybe!.inputRow == nil {
                XCTAssertNotNil(maybe!.inputReceiver, "a MIDI-IN cell must point at a receiver")
            } }
        }
        XCTAssertEqual(d.receivers?.map { $0.channel }, [0, 2, 3, 4], "A=OMNI, B/C/D=2/3/4")
        func count(_ s: SceneState) -> Int { s.cells.reduce(0) { $0 + $1.compactMap { $0 }.count } }
        XCTAssertGreaterThan(count(d.scenes[2]), count(d.scenes[0]), "scene 3 (epic) builds denser than scene 1")
    }

    func testDefaultArcRoundTrips() {
        let d = PluginState.defaultArc()
        guard let data = PresetStore.encode(d), let back = PresetStore.decode(data) else { return XCTFail("nil") }
        XCTAssertEqual(back.scenes.prefix(3).map { $0.isEmpty }, [false, false, false])
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

    // A doc built at v3 with receivers PRE-SET but MIDI-IN cells left unpointed (the old factory bug) must be
    // repaired by synthesis — the cell gets pointed so it honours receiver mute (item 11 ruling 2026-07-26).
    func testSynthesisRepairsPreSetReceiversWithUnpointedCells() {
        var d = doc({ s in
            s.cells[0][0] = { var c = Cell(colourID: "gold"); c.inputChannel = 0; return c }()   // MIDI-IN, unpointed
        }, version: 4)
        d.receivers = [Receiver(name: "1"), Receiver(name: "2"), Receiver(name: "3"), Receiver(name: "4")]
        XCTAssertNil(d.scenes[0].cells[0][0]?.inputReceiver)           // pre-condition: unpointed
        d.synthesizeReceiversIfNeeded()                               // must repair despite receivers already set
        XCTAssertEqual(d.scenes[0].cells[0][0]?.inputReceiver, 0, "an unpointed MIDI-IN cell is repaired to R1")
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

    // §item 11 INPUT CABLES: a pre-cable Receiver (no `cable` key) decodes → nil ⇒ ANY (hears every cable).
    func testReceiverWithoutCableDecodesToANY() throws {
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Receiver(name: "Keys", channel: 1))) as! [String: Any]
        dict.removeValue(forKey: "cable")                                     // simulate a pre-cable document
        let back = try JSONDecoder().decode(Receiver.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertNil(back.cable)
        XCTAssertEqual(back.cableResolved, 0b1111, "missing cable ⇒ ANY (hears every cable) — migration no-op")
    }
    func testReceiverCableRoundTrips() throws {
        var r = Receiver(name: "Keys"); r.cable = 0b0101                       // cables {1,3}
        let back = try JSONDecoder().decode(Receiver.self, from: try JSONEncoder().encode(r))
        XCTAssertEqual(back.cable, 0b0101)
        XCTAssertEqual(back.cableResolved, 0b0101)
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
        reloaded.migrateLegacyRoutingIfNeeded()                  // no-op: already v5 (receivers present, pairs folded)
        XCTAssertEqual(reloaded.scenes[0].cells[0][1]?.inputRow, 0)
        XCTAssertNil(reloaded.scenes[0].cells[3][0]?.inputRow)
        XCTAssertEqual(reloaded.formatVersion, 5)
    }

    // MARK: - TWO-PROCESSOR migration (delta item 8) — pair reference → internal procB

    func testColourPairMigratesPartnerIntoProcB() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 4
        let gi = colourIDs.firstIndex(of: "gold")!, ci = colourIDs.firstIndex(of: "cyan")!
        d.colours[ci].type = .ratchet; d.colours[ci].paramsA.count = 5; d.colours[ci].transpose = 7
        d.colours[gi].altColour = ci                             // legacy pair: gold → cyan
        d.migrateColourPairsIfNeeded()
        XCTAssertEqual(d.colours[gi].typeB, .ratchet, "partner's type folds into procB")
        XCTAssertEqual(d.colours[gi].paramsB.count, 5, "partner's params fold into procB")
        XCTAssertEqual(d.colours[gi].transposeBResolved, 7, "partner's transpose folds into transposeB")
        XCTAssertEqual(d.colours[gi].altColour, ci, "altColour kept (decode-only legacy, lossless downgrade)")
        XCTAssertEqual(d.formatVersion, 5)
    }

    func testStaleParamsBWithoutAPairIsInert() {
        // A pre-pair doc with a stale paramsB but no altColour must NOT gain a procB (typeB stays nil).
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 4
        d.colours[0].paramsB.octaves = 4                        // stale, no altColour
        d.migrateColourPairsIfNeeded()
        XCTAssertNil(d.colours[0].typeB, "no pair ⇒ no procB; stale paramsB stays inert")
        XCTAssertFalse(d.colours[0].hasProcB)
    }

    func testColourPairMigrationIsIdempotent() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 4
        d.colours[0].altColour = 1
        d.migrateColourPairsIfNeeded()                          // → v5
        d.colours[0].typeB = nil                                // pretend a later edit cleared procB
        d.migrateColourPairsIfNeeded()                          // gated on v<5 → must NOT re-fold
        XCTAssertNil(d.colours[0].typeB, "version gate stops a second fold")
    }

    func testColourPairMigrationSkipsSelfAndOutOfRangePartner() {
        // The partner guard (pi != i, 0 ≤ pi < count): a Colour pointing at itself or a bogus index yields no procB.
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 4
        d.colours[0].altColour = 0                               // points at itself
        d.colours[1].altColour = 99                              // out of range
        d.migrateColourPairsIfNeeded()
        XCTAssertNil(d.colours[0].typeB, "a self-referencing pair produces no procB")
        XCTAssertNil(d.colours[1].typeB, "an out-of-range partner produces no procB")
        XCTAssertEqual(d.formatVersion, 5, "the version still advances")
    }

    // MARK: - Optional resolved accessors — nil = old-doc default; the clamps guard the render path
    // (SnapshotBuilder maps these into UInt8, so an unclamped >255 amount would trap).

    func testFlattenAmountResolvedClampsAndFillsShort() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.flattenAmount = nil
        XCTAssertEqual(d.flattenAmountResolved, [0, 0, 0, 0], "nil ⇒ all off")
        d.flattenAmount = [150, -5, 50]                          // over / under / short
        XCTAssertEqual(d.flattenAmountResolved, [100, 0, 50, 0], "clamped to 0…100 and the short array pads with 0")
    }

    func testAltCountResolvedClampsAndFillsShort() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.altCount = nil
        XCTAssertEqual(d.altCountResolved, [1, 1, 1, 1], "nil ⇒ one note per turn")
        d.altCount = [0, 20, 2]                                  // under / over / short
        XCTAssertEqual(d.altCountResolved, [1, 8, 2, 1], "clamped to 1…8 and the short array pads with 1")
    }

    // MARK: - MODELESS EDIT scope — target resolution + apply

    func testEditScopeTargets() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(colourID: "gold", buses: [.a])
        s.cells[0][1] = Cell(colourID: "gold", buses: [.a])          // identical to (0,0)
        s.cells[1][0] = Cell(colourID: "gold", buses: [.b])          // same Colour, DIFFERENT routing
        s.cells[2][0] = Cell(colourID: "cyan", buses: [.a])          // different Colour
        XCTAssertEqual(s.editScopeTargets(col: 0, row: 0, scope: .thisOne), [0], "just the exemplar")
        XCTAssertEqual(s.editScopeTargets(col: 0, row: 0, scope: .allIdentical), [0, 1], "same Colour AND routing")
        XCTAssertEqual(s.editScopeTargets(col: 0, row: 0, scope: .allColour), [0, 1, 8], "every gold cell (0,0)(0,1)(1,0)")
        XCTAssertEqual(s.editScopeTargets(col: 5, row: 5, scope: .allColour), [], "an empty exemplar targets nothing")
    }

    func testApplyToScopeRecolorsTheSet() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(colourID: "gold"); s.cells[0][1] = Cell(colourID: "gold"); s.cells[1][0] = Cell(colourID: "cyan")
        s.applyToScope(col: 0, row: 0, scope: .allColour) { $0.colourID = "wine" }
        XCTAssertEqual(s.cells[0][0]?.colourID, "wine")
        XCTAssertEqual(s.cells[0][1]?.colourID, "wine", "the whole gold set is repainted")
        XCTAssertEqual(s.cells[1][0]?.colourID, "cyan", "a different Colour is untouched")
    }

    // MARK: - §11 VERB LOGIC — REMOVE (heal-on-delete §10b) + MOVE

    func testDeleteHealsChildrenToGrandparentInSameColumn() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(colourID: "gold")                                  // row0: receiver-fed root (inputRow nil)
        s.cells[0][2] = Cell(colourID: "cyan", buses: [.a], inputRow: 0)        // row2 ⇐ row0
        s.cells[0][4] = Cell(colourID: "wine", buses: [.b], inputRow: 2)        // row4 ⇐ row2 (the child of the victim)
        s.deleteCellHealing(col: 0, row: 2)                                     // delete the middle link
        XCTAssertNil(s.cells[0][2], "the victim is gone")
        XCTAssertEqual(s.cells[0][4]?.inputRow, 0, "its child re-points to the GRANDPARENT (row 0)")
    }

    func testDeleteHealsChildrenToReceiverWhenVictimWasReceiverFed() {
        var s = SceneState.empty()
        var root = Cell(colourID: "gold"); root.inputRow = nil; root.inputReceiver = 2   // MIDI-IN via receiver 2
        s.cells[3][1] = root
        s.cells[3][5] = Cell(colourID: "cyan", buses: [.a], inputRow: 1)                 // ⇐ row1
        s.deleteCellHealing(col: 3, row: 1)
        XCTAssertEqual(s.cells[3][5]?.inputRow, nil, "the child becomes MIDI-IN…")
        XCTAssertEqual(s.cells[3][5]?.inputReceiver, 2, "…on the victim's receiver (no orphan-silence)")
    }

    // DELETE = SEVER (AcceptanceCriteria ruling): the child does NOT reconnect to the grandparent; it is cut
    // back to MIDI-IN (inputRow nil) and pointed at R1 so it doesn't bypass the receiver.
    func testDeleteSeverCutsChildToMidiInNotGrandparent() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(colourID: "gold")                                  // row0: receiver-fed root
        s.cells[0][2] = Cell(colourID: "cyan", buses: [.a], inputRow: 0)        // row2 ⇐ row0 (the victim)
        s.cells[0][4] = Cell(colourID: "wine", buses: [.b], inputRow: 2)        // row4 ⇐ row2 (the child)
        s.deleteCellSever(col: 0, row: 2)
        XCTAssertNil(s.cells[0][2], "the victim is gone")
        XCTAssertNil(s.cells[0][4]?.inputRow, "the child is CUT to MIDI-IN (does NOT reconnect to row 0)")
        XCTAssertEqual(s.cells[0][4]?.inputReceiver, 0, "a severed MIDI-IN child points at R1 (no bypass)")
        XCTAssertNotNil(s.cells[0][0], "the victim's parent is untouched")
    }

    func testMoveRelocatesAndOverwrites() {
        var s = SceneState.empty()
        s.cells[1][1] = Cell(colourID: "gold", buses: [.a], inputRow: 3)   // reference travels as-is
        s.cells[4][4] = Cell(colourID: "cyan")                             // occupied target (overwritten)
        s.moveCellTo(from: (1, 1), to: (4, 4))
        XCTAssertNil(s.cells[1][1], "source empties")
        XCTAssertEqual(s.cells[4][4]?.colourID, "gold", "overwrites the target (undo covers it)")
        XCTAssertEqual(s.cells[4][4]?.inputRow, 3, "MOVE never rewrites references — inputRow travels as-is")
        s.moveCellTo(from: (4, 4), to: (4, 4))                             // self = no-op
        XCTAssertEqual(s.cells[4][4]?.colourID, "gold")
    }

    // MARK: - §10/11f SPATIAL ROUTING (patch-bay model core)

    private func headed(_ colourID: String, receiver: Int) -> Cell { var c = Cell(colourID: colourID, buses: [.a]); c.inputRow = nil; c.inputReceiver = receiver; return c }
    private func bodied(_ colourID: String, from row: Int) -> Cell { var c = Cell(colourID: colourID, buses: [.a]); c.inputRow = row; return c }

    func testIsChainHeadIsReceiverFedRoot() {
        var s = SceneState.empty()
        s.cells[0][0] = headed("gold", receiver: 0)   // receiver-fed → head
        s.cells[0][2] = bodied("cyan", from: 0)        // row-fed → body
        XCTAssertTrue(s.isChainHead(col: 0, row: 0), "a receiver-fed cell is a chain head")
        XCTAssertFalse(s.isChainHead(col: 0, row: 2), "a row-fed cell is a body, not a head")
        XCTAssertFalse(s.isChainHead(col: 0, row: 5), "an empty cell is not a head")
    }

    func testRouteCandidates_sourcesAbove_headsBelow() {
        var s = SceneState.empty()
        s.cells[0][0] = headed("gold", receiver: 0)    // above X
        s.cells[0][2] = headed("cyan", receiver: 0)    // X (at row 2)
        s.cells[0][4] = headed("mint", receiver: 1)    // a HEAD below X
        s.cells[0][6] = bodied("teal", from: 4)         // a BODY below X (child of row 4)
        XCTAssertEqual(s.routeInSourcesAbove(col: 0, row: 2), [0], "only occupied cells above light as sources")
        XCTAssertEqual(s.graftHeadsBelow(col: 0, row: 2), [4], "only chain HEADS below light — the body (row 6) does not")
    }

    func testGraftCarriesTheWholeSubtree() {
        var s = SceneState.empty()
        s.cells[0][0] = headed("gold", receiver: 0)    // parent X at row 0
        s.cells[0][3] = headed("cyan", receiver: 1)    // a HEAD below (row 3)
        s.cells[0][5] = bodied("mint", from: 3)         // the head's CHILD (references row 3)
        s.graftHeadBelow(headRow: 3, under: 0, col: 0)
        XCTAssertEqual(s.cells[0][3]?.inputRow, 0, "the grafted head is now fed by the parent row")
        XCTAssertEqual(s.cells[0][5]?.inputRow, 3, "its subtree follows — the child still references the head's row")
    }

    func testGraftRefusesBodiesAndCycles() {
        var s = SceneState.empty()
        s.cells[0][0] = headed("gold", receiver: 0)
        s.cells[0][2] = bodied("cyan", from: 0)         // a BODY below (not a head)
        s.graftHeadBelow(headRow: 2, under: 0, col: 0)
        XCTAssertEqual(s.cells[0][2]?.inputRow, 0, "a body is not grafted (its inputRow is untouched)")
        // cycle: parent (row 4) is fed by the head (row 1) → grafting head under parent would loop → refused
        var t = SceneState.empty()
        t.cells[0][1] = headed("gold", receiver: 0)
        t.cells[0][4] = bodied("cyan", from: 1)         // row 4 is a child of the head at row 1
        t.graftHeadBelow(headRow: 1, under: 4, col: 0)  // would make head⇐row4 while row4⇐head → cycle
        XCTAssertNil(t.cells[0][1]?.inputRow, "the grafting head stays receiver-fed — the cycle is refused")
    }

    func testRouteInAndToggleEmitter() {
        var s = SceneState.empty()
        s.cells[0][3] = headed("gold", receiver: 0)
        s.routeInRow(col: 0, row: 3, sourceRow: 1)      // no cell at row 1 → no-op (empty source)
        XCTAssertNil(s.cells[0][3]?.inputRow, "routeInRow onto an empty source is ignored")
        s.cells[0][1] = headed("cyan", receiver: 0)
        s.routeInRow(col: 0, row: 3, sourceRow: 1)      // now valid (occupied, above)
        XCTAssertEqual(s.cells[0][3]?.inputRow, 1, "routeInRow feeds X from the row above")
        s.routeInReceiver(col: 0, row: 3, receiver: 2)  // back to a door
        XCTAssertNil(s.cells[0][3]?.inputRow); XCTAssertEqual(s.cells[0][3]?.inputReceiver, 2)
        s.toggleEmitter(col: 0, row: 3, bus: .b)         // add B
        XCTAssertEqual(s.cells[0][3]?.buses.contains(.b), true)
        s.toggleEmitter(col: 0, row: 3, bus: .a)         // remove A (was the default)
        XCTAssertEqual(s.cells[0][3]?.buses.contains(.a), false)
    }

    // MARK: - MULTI-SCENE — sparse scenes, switch, save-here, bounds-safety

    private func multi() -> PluginState {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.padScenes(); return d
    }

    func testSceneStateIsEmpty() {
        XCTAssertTrue(SceneState.empty().isEmpty)
        var s = SceneState.empty(); s.cells[0][0] = Cell(colourID: "gold")
        XCTAssertFalse(s.isEmpty, "a placed cell ⇒ not empty")
    }

    func testPadScenesFillsToEightIdempotently() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.scenes[0].cells[0][0] = Cell(colourID: "gold")
        d.padScenes()
        XCTAssertEqual(d.scenes.count, 8)
        XCTAssertFalse(d.scenes[0].isEmpty, "slot 0 preserved")
        XCTAssertTrue(d.scenes[7].isEmpty, "padded slots are empty +")
        d.padScenes(); XCTAssertEqual(d.scenes.count, 8, "idempotent — never grows past 8")
    }

    func testSwitchSceneOnlyToNonEmpty() {
        var d = multi()
        d.scenes[3].cells[0][0] = Cell(colourID: "gold")
        d.switchScene(to: 3); XCTAssertEqual(d.activeScene, 3)
        d.switchScene(to: 5); XCTAssertEqual(d.activeScene, 3, "empty slots aren't playable — the switch is ignored")
    }

    func testSaveCurrentSceneCopiesActiveIntoSlotWithoutSwitching() {
        var d = multi()
        d.scenes[0].cells[2][2] = Cell(colourID: "cyan")
        d.saveCurrentScene(toSlot: 7)
        XCTAssertEqual(d.scenes[7].cells[2][2]?.colourID, "cyan", "slot 7 = a copy of the active scene")
        XCTAssertEqual(d.activeScene, 0, "save-here does NOT switch")
    }

    // MARK: - S3 drag: MOVE / SWAP / DELETE (never overwrite; active follows content; active refuses trash)

    func testDragOntoEmptyMovesAndEmptiesSource() {
        var d = multi()
        d.scenes[2].cells[0][0] = Cell(colourID: "gold")
        d.dragScene(from: 2, to: 6)                        // 6 is empty ⇒ MOVE
        XCTAssertEqual(d.scenes[6].cells[0][0]?.colourID, "gold", "the scene relocated to 6")
        XCTAssertTrue(d.scenes[2].isEmpty, "the source slot is now empty")
    }

    func testDragOntoOccupiedSwapsNeverOverwrites() {
        var d = multi()
        d.scenes[2].cells[0][0] = Cell(colourID: "gold")
        d.scenes[5].cells[0][0] = Cell(colourID: "cyan")
        d.dragScene(from: 2, to: 5)                        // 5 occupied ⇒ SWAP, not overwrite
        XCTAssertEqual(d.scenes[5].cells[0][0]?.colourID, "gold", "dragged content lands in 5")
        XCTAssertEqual(d.scenes[2].cells[0][0]?.colourID, "cyan", "the displaced scene survives in 2 (no data lost)")
    }

    func testMoveCarriesTheActiveIndexWithItsContent() {
        var d = multi()
        d.scenes[3].cells[0][0] = Cell(colourID: "gold"); d.activeScene = 3
        d.moveScene(from: 3, to: 7)
        XCTAssertEqual(d.activeScene, 7, "the playing scene follows its content to the new slot")
    }

    func testSwapCarriesTheActiveIndex() {
        var d = multi()
        d.scenes[3].cells[0][0] = Cell(colourID: "gold")
        d.scenes[6].cells[0][0] = Cell(colourID: "cyan")
        d.activeScene = 6
        d.swapScenes(3, 6)
        XCTAssertEqual(d.activeScene, 3, "active followed its content across the swap")
        XCTAssertEqual(d.scenes[3].cells[0][0]?.colourID, "cyan", "…which is now in slot 3")
    }

    func testDeleteEmptiesTheSlotButRefusesTheActiveScene() {
        var d = multi()
        d.scenes[4].cells[0][0] = Cell(colourID: "gold")
        d.scenes[7].cells[0][0] = Cell(colourID: "cyan"); d.activeScene = 7
        XCTAssertTrue(d.deleteScene(4), "a non-active scene deletes")
        XCTAssertTrue(d.scenes[4].isEmpty, "the slot is now empty")
        XCTAssertFalse(d.deleteScene(7), "the ACTIVE scene refuses the trash")
        XCTAssertFalse(d.scenes[7].isEmpty, "…and survives")
    }

    // Guard paths: can't drag a "+", no-op on self/out-of-range, delete of empty/oob — all bounds-safe no-ops.
    func testDragFromEmptySlotIsIgnored() {
        var d = multi()
        d.scenes[3].cells[0][0] = Cell(colourID: "gold")
        d.dragScene(from: 5, to: 3)                       // 5 is a "+" — nothing to lift
        XCTAssertEqual(d.scenes[3].cells[0][0]?.colourID, "gold", "the occupied target is untouched")
        XCTAssertTrue(d.scenes[5].isEmpty, "the empty source stays empty")
    }
    func testDragToSelfIsNoOp() {
        var d = multi()
        d.scenes[2].cells[0][0] = Cell(colourID: "gold")
        d.dragScene(from: 2, to: 2)
        XCTAssertEqual(d.scenes[2].cells[0][0]?.colourID, "gold", "dragging onto itself changes nothing")
    }
    func testDragOutOfRangeDoesNotCrashOrChange() {
        var d = multi()
        d.scenes[1].cells[0][0] = Cell(colourID: "gold")
        d.dragScene(from: 1, to: 99); d.dragScene(from: -1, to: 1); d.moveScene(from: 1, to: 50); d.swapScenes(1, 99)
        XCTAssertEqual(d.scenes[1].cells[0][0]?.colourID, "gold", "out-of-range indices are ignored, no crash")
    }
    func testMoveOntoOccupiedIsIgnored() {
        var d = multi()
        d.scenes[1].cells[0][0] = Cell(colourID: "gold")
        d.scenes[2].cells[0][0] = Cell(colourID: "cyan")
        d.moveScene(from: 1, to: 2)                        // MOVE only relocates onto EMPTY — occupied is a SWAP job
        XCTAssertEqual(d.scenes[1].cells[0][0]?.colourID, "gold", "source untouched")
        XCTAssertEqual(d.scenes[2].cells[0][0]?.colourID, "cyan", "occupied target NOT overwritten by move")
    }
    func testDeleteEmptyOrOutOfRangeReturnsFalse() {
        var d = multi()
        XCTAssertFalse(d.deleteScene(6), "deleting an empty slot is a no-op (false)")
        XCTAssertFalse(d.deleteScene(99), "out-of-range is a no-op (false), no crash")
    }
    func testSaveBeyondSlotCountIsIgnored() {
        var d = multi()
        d.scenes[0].cells[0][0] = Cell(colourID: "gold")
        d.saveCurrentScene(toSlot: PluginState.maxScenes)   // one past the last slot
        XCTAssertEqual(d.scenes.count, PluginState.maxScenes, "no slot is created past the fixed strip")
    }

    func testActiveSceneResolvedIsBoundsSafe() {
        var d = multi(); d.activeScene = 99
        XCTAssertTrue((0..<d.scenes.count).contains(d.activeSceneResolved), "out-of-range clamps in-bounds, never crashes")
        _ = d.activeSceneState   // must not crash
        d.activeScene = -5
        XCTAssertEqual(d.activeSceneResolved, 0, "a negative index clamps to 0")
    }

    func testSnapshotReflectsTheActiveScene() {
        var d = multi()
        d.scenes[0].cells[0][0] = Cell(colourID: "gold")   // scene 0 → cell (0,0)
        d.scenes[1].cells[3][0] = Cell(colourID: "cyan")   // scene 1 → cell (3,0)
        d.activeScene = 1
        let box = SnapshotBuilder.build(from: d)
        XCTAssertGreaterThanOrEqual(box.cells[3 * 8 + 0].colourIndex, 0, "the ACTIVE scene's cell is in the snapshot")
        XCTAssertLessThan(box.cells[0].colourIndex, 0, "the inactive scene's cell is NOT")
    }

    func testMigrationPadsScenesToEight() {
        var d = doc { $0.cells[0][0] = Cell(colourID: "gold") }   // v2, length-1
        d.migrateLegacyRoutingIfNeeded()
        XCTAssertEqual(d.scenes.count, 8, "old length-1 docs pad to the 8-slot strip")
        XCTAssertFalse(d.scenes[0].isEmpty, "the original scene stays in slot 0")
    }

    func testMasterKeyResolvedClampsAndDefaults() {
        var s = SceneState.empty()
        s.masterKey = nil;  XCTAssertEqual(s.masterKeyResolved, 0, "nil ⇒ no transpose")
        s.masterKey = 20;   XCTAssertEqual(s.masterKeyResolved, 12, "clamped to +12")
        s.masterKey = -20;  XCTAssertEqual(s.masterKeyResolved, -12, "clamped to −12")
    }

    // MARK: - CLAIM v2 (delta §6a) — mask derives from the legacy field; leak clamps; append-only round-trip

    func testClaimMaskResolvedDerivesFromLegacyField() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.claimMask = nil; d.claimEmitter = nil
        XCTAssertEqual(d.claimMaskResolved, 0, "nil mask + nil legacy ⇒ no claim")
        d.claimEmitter = 2
        XCTAssertEqual(d.claimMaskResolved, 0b0100, "the legacy single claimant derives its bit")
        d.claimMask = 0b1010
        XCTAssertEqual(d.claimMaskResolved, 0b1010, "an explicit mask wins over the legacy field")
        d.claimMask = nil; d.claimEmitter = 9
        XCTAssertEqual(d.claimMaskResolved, 0, "an out-of-range legacy value ⇒ no claim")
    }

    func testClaimLeakResolvedClampsAndFillsShort() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.claimLeak = nil
        XCTAssertEqual(d.claimLeakResolved, [0, 0, 0, 0], "nil ⇒ all 0 (full suppression)")
        d.claimLeak = [150, -5, 50]                              // over / under / short
        XCTAssertEqual(d.claimLeakResolved, [100, 0, 50, 0], "clamped to 0…100 and the short array pads with 0")
    }

    func testClaimV2FieldsRoundTripAndOldDocsDecode() throws {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.claimMask = 0b0101; d.claimLeak = [30, 0, 70, 0]
        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(d))
        XCTAssertEqual(back.claimMask, 0b0101, "the mask persists")
        XCTAssertEqual(back.claimLeakResolved, [30, 0, 70, 0], "the leak persists")
        // An OLD doc (encoded before the v2 keys existed) has neither key → decodes to no claim, no leak.
        var old = PluginState(colours: [], scenes: [])
        old.claimMask = nil; old.claimLeak = nil; old.claimEmitter = nil
        let oldBack = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(old))
        XCTAssertEqual(oldBack.claimMaskResolved, 0)
        XCTAssertEqual(oldBack.claimLeakResolved, [0, 0, 0, 0])
    }

    // Regression: the persisted receiver config (channel/cable/mute) + THRU pip must survive the fullState
    // save→restore path (encode → decode → migrateLegacyRoutingIfNeeded), exactly as MidiSparkAudioUnit does.
    func testReceiverConfigSurvivesFullStateRoundTrip() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.receivers = [
            { var r = Receiver(name: "1"); r.channel = 3; r.cable = 0b0010; return r }(),   // ch 3, cable 2
            { var r = Receiver(name: "2"); r.muted = true; return r }(),                     // muted
            Receiver(name: "3"), Receiver(name: "4"),
        ]
        d.thruReceiver = 2
        d.formatVersion = 5
        let data = try! JSONEncoder().encode(d)
        var back = try! JSONDecoder().decode(PluginState.self, from: data)
        back.migrateLegacyRoutingIfNeeded()                       // the AU's fullState-set path
        XCTAssertEqual(back.receivers?[0].channel, 3, "channel filter survives")
        XCTAssertEqual(back.receivers?[0].cable, 0b0010, "cable filter survives")
        XCTAssertEqual(back.receivers?[1].muted, true, "mute survives")
        XCTAssertEqual(back.thruReceiver, 2, "THRU pip survives")
    }

    func testAltColourKeyStillDecodesOnOldBuild() {
        // altColour survives a round-trip so an older build can still read the pair (lossless downgrade).
        var c = Colour(colourID: "gold", type: .arp); c.altColour = 3
        let back = try! JSONDecoder().decode(Colour.self, from: try! JSONEncoder().encode(c))
        XCTAssertEqual(back.altColour, 3)
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
        // OCT hold appends a direction; a non-drift arrive skips the drift facet; all scene parts compose.
        c.hold = .oct; c.octUp = true
        XCTAssertTrue(c.holdSummary.hasSuffix(" · +"), "OCT up shows +")
        c.octUp = false
        XCTAssertTrue(c.holdSummary.hasSuffix(" · −"), "OCT down shows −")
        c.arrive = .dice; c.arriveEvery = 3
        XCTAssertEqual(c.arriveSummary, "DICE · every 3")   // no drift facet on a non-drift arrive
        c.sceneResetMorph = true; c.sceneAutoArm = true
        XCTAssertEqual(c.sceneSummary, "ENTER 3 · EXIT 7 · RESET MORPH · AUTO-ARM")
    }
}
