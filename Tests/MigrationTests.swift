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

    // THE LADDER family (§PART 2): every ladder preset is a full 8×8 of 8 machines (one per row, twins across
    // columns), LADDER on, 3 distinct intensity curves, single emitter A, HARM as +12 only.
    func testLadderPresetsAreEightMachineLadders() throws {
        let presets: [(String, PluginState)] = [
            ("THE LADDER", .makeLadder()), ("TIDE", .makeLadderTide()), ("FORGE", .makeLadderForge()),
            ("CHIME", .makeLadderChime()), ("SPARK", .makeLadderSpark()),
        ]
        for (name, st) in presets {
            XCTAssertTrue(st.ladderModeResolved, "\(name): LADDER ships ON")
            XCTAssertGreaterThanOrEqual(st.scenes.count, 3, "\(name): three-act arc")
            let s = st.scenes[0]
            for row in 0..<8 {
                let proto = s.cells[0][row]?.processors
                XCTAssertNotNil(proto, "\(name) row \(row) placed")
                for col in 0..<8 {
                    XCTAssertEqual(s.cells[col][row]?.processors, proto, "\(name) row \(row) stamped as twins across columns")
                    XCTAssertEqual(s.cells[col][row]?.buses, [.a], "\(name): single emitter A")
                }
                for slot in proto ?? [] where slot.type == .harmonize {
                    XCTAssertEqual((slot.params.harmIntervals ?? []).filter { $0 != 0 }, [12], "\(name): HARM is +12 octave only")
                }
            }
            XCTAssertNotEqual(st.scenes[0].activeRow, st.scenes[2].activeRow, "\(name): scenes paint different rung curves")
        }
        // the flagship's specific shape (R1 = PASS · R8 = harmonize → arp → chance) + Codable round-trip of the new fields
        let l = PluginState.makeLadder()
        XCTAssertEqual(l.scenes[0].cells[0][0]?.processors?.map { $0.type }, [.passgate])
        XCTAssertEqual(l.scenes[0].cells[0][7]?.processors?.map { $0.type }, [.harmonize, .arp, .chance])
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(l))
        XCTAssertTrue(back.ladderModeResolved)
        XCTAssertEqual(back.scenes[0].activeRow, l.scenes[0].activeRow, "activeRow round-trips")
    }

    // MIDI DELAYS preset (user 2026-08-08): 8 single-slot ECHO flavours in COLUMN 0 only (sparse so tails ring out),
    // SINGLE mode, three scenes. Guards the echo params + their Codable round-trip.
    func testMidiDelaysPresetIsEightSparseEchoes() throws {
        let d = PluginState.makeDelays()
        XCTAssertTrue(d.ladderModeResolved, "DELAYS ships SINGLE mode ON")
        XCTAssertGreaterThanOrEqual(d.scenes.count, 3, "SLAP · DUB · CANYON scenes")
        let s = d.scenes[0]
        for row in 0..<8 {
            XCTAssertEqual(s.cells[0][row]?.processors?.map { $0.type }, [.echo], "row \(row) is a single-slot ECHO in column 0")
            XCTAssertEqual(s.cells[0][row]?.buses, [.a], "wired to Emitter A")
            for col in 1..<8 { XCTAssertNil(s.cells[col][row], "sparse — only column 0 populated (the tail rings across the rest)") }
        }
        // R1 SLAP = 1 repeat · R5 DUB = 12 · R6 RISER pitches +3 · R8 CANYON offsets the grid
        XCTAssertEqual(s.cells[0][0]?.processors?.first?.params.echoRepeats, 1)
        XCTAssertEqual(s.cells[0][4]?.processors?.first?.params.echoRepeats, 12)
        XCTAssertEqual(s.cells[0][5]?.processors?.first?.params.echoPitch, 3)
        XCTAssertEqual(s.cells[0][7]?.processors?.first?.params.echoOffset, 0.2)
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.scenes[0].cells[0][4]?.processors?.first?.params.echoRepeats, 12, "echo params round-trip")
        XCTAssertEqual(back.scenes[0].activeRow, d.scenes[0].activeRow, "the SLAP scene's active rung round-trips")
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

    // Cells/desk overhaul: a pre-overhaul Colour (no name/defined keys) → type name + defined (migration no-op).
    func testColourNameAndDefinedDecodeToDefaults() throws {
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Colour(colourID: "gold", type: .arp))) as! [String: Any]
        for k in ["name", "defined"] { dict.removeValue(forKey: k) }
        let c = try JSONDecoder().decode(Colour.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(c.nameResolved, "ARP", "missing name ⇒ the type name")
        XCTAssertTrue(c.isDefined, "missing defined ⇒ defined (today's behaviour)")
    }
    func testColourNameAndDefinedRoundTrip() throws {
        var c = Colour(colourID: "gold", type: .arp); c.name = "Bells"; c.defined = false
        let back = try JSONDecoder().decode(Colour.self, from: try JSONEncoder().encode(c))
        XCTAssertEqual(back.nameResolved, "Bells")
        XCTAssertFalse(back.isDefined)
    }
    func testFactoryAndArcShipSparsePalette() {
        for f in [PluginState.factory(), PluginState.defaultArc()] {
            let defined = Set(f.colours.filter { $0.isDefined }.map { $0.colourID })
            XCTAssertTrue(defined.count >= 3 && defined.count < 16, "sparse palette: some defined, some + slots")
            let used = Set(f.scenes.flatMap { $0.cells.flatMap { $0.compactMap { $0?.colourID } } })
            XCTAssertEqual(used, defined, "defined == painted")
        }
    }

    func testNewOptionalFieldsRoundTripThroughJSON() throws {
        // busEnabled (§6a) + per-type transpose/morph stashes survive save/reload.
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 3
        d.busEnabled = [true, false, true, false]
        d.colours[0].transposeByType = [1, 2, 3, 4, 5, 6]
        d.claimEmitter = 2                          // §6a CLAIM (a7) — persisted
        d.latchArmMask = 0b0101                      // doors A + C armed (Paul 2026-08-27) — the latch section is durable config
        let reloaded = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(d))
        XCTAssertEqual(reloaded.busEnabled, [true, false, true, false])
        XCTAssertEqual(reloaded.colours[0].transposeByType, [1, 2, 3, 4, 5, 6])
        XCTAssertEqual(reloaded.claimEmitter, 2, "CLAIM survives save/reload")
        XCTAssertEqual(reloaded.latchArmMask, 0b0101, "the door-arm mask survives save/reload")
        // A pre-field document (no latchArmMask key) decodes to nil (nothing armed) — no migration break.
        var dict = try JSONSerialization.jsonObject(with: try JSONEncoder().encode(d)) as! [String: Any]
        dict.removeValue(forKey: "latchArmMask")
        let old = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertNil(old.latchArmMask, "missing latchArmMask ⇒ nil (nothing armed)")
    }

    // BUILD's single UNASSIGNED part is saved with the document (Paul 2026-08-16) — the part + its ephemeral colours
    // (machine + hue) + the id counter round-trip; a document without the field decodes as nil (no migration break).
    func testBuildUnassignedPartRoundTripsAndDefaultsNil() throws {
        var plain = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        let plainBack = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(plain))
        XCTAssertNil(plainBack.buildUnassigned, "an old/plain document has no unassigned part")

        var part = BuildPart()
        part.stagingCells[0][3] = "b17"; part.stagingSel[0] = 3; part.cast = ["b17"]; part.selID = "b17"
        part.receiver = 2; part.emitters = [.a, .c]; part.rowChain[3] = [ProcessorSlot(type: .harmonize)]
        var ephemeral = Colour(colourID: "b17", type: .arp); ephemeral.defined = true; ephemeral.templateChain = [ProcessorSlot(type: .cascade)]
        ephemeral.transpose = -12   // REGISTER-HOME (BUG fix 2026-08-29): the ephemeral colour's octave must travel too, else a saved ensemble reloads shifted
        plain.buildUnassigned = BuildUnassignedData(part: part, colours: [ephemeral], hues: ["b17": 0x2288EE], idCounter: 17)

        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(plain))
        let u = try XCTUnwrap(back.buildUnassigned, "the unassigned part survives save/reload")
        XCTAssertEqual(u.part.stagingCells[0][3], "b17")
        XCTAssertEqual(u.part.stagingSel[0], 3)
        XCTAssertEqual(u.part.emitters, [.a, .c])
        XCTAssertEqual(u.part.rowChain[3].first?.type, .harmonize)
        XCTAssertEqual(u.colours.first?.templateChain?.first?.type, .cascade, "its ephemeral colour's machine travels")
        XCTAssertEqual(u.colours.first?.transpose, -12, "its register-home (octave) travels — buildCapture/RestoreUnassigned carry Colour.transpose (BUG fix 2026-08-29)")
        XCTAssertEqual(u.hues["b17"], 0x2288EE, "its custom hue travels")
        XCTAssertEqual(u.idCounter, 17)
    }

    /// The RACK + modulation additive-Optional document fields (curve/fence/mono/pocket/conversation gates,
    /// rackEnabled, turnsPerNote, ladderMode, masterMute) all survive a JSON round-trip. Invariant 5 (schema
    /// stability): these shipped over the last few days and had no round-trip lock.
    func testRackAndModulationOptionalFieldsRoundTrip() throws {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 3
        d.curveMask = 0b0001;  d.curveAmount = [50, 0, 0, 0]
        d.fenceMask = 0b0010;  d.fencePolicy = [0, 2, 0, 0]; d.fenceLo = [0, 48, 0, 0]; d.fenceHi = [127, 72, 127, 127]
        d.monoMask = 0b0100;   d.monoPriority = [0, 0, 2, 0]
        d.pocketMask = 0b1000; d.pocketMs = [0, 0, 0, -20]
        d.convLead = 1;        d.convStance = [1, 0, 2, 0]
        d.rackEnabledMask = 0b1011
        d.turnsPerNote = true; d.ladderMode = true; d.masterMute = true
        let r = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(r.curveMask, 0b0001);  XCTAssertEqual(r.curveAmount, [50, 0, 0, 0])
        XCTAssertEqual(r.fencePolicy, [0, 2, 0, 0]); XCTAssertEqual(r.fenceLo, [0, 48, 0, 0]); XCTAssertEqual(r.fenceHi, [127, 72, 127, 127])
        XCTAssertEqual(r.monoPriority, [0, 0, 2, 0])
        XCTAssertEqual(r.pocketMs, [0, 0, 0, -20])
        XCTAssertEqual(r.convLead, 1); XCTAssertEqual(r.convStance, [1, 0, 2, 0])
        XCTAssertEqual(r.rackEnabledMask, 0b1011)
        XCTAssertEqual(r.turnsPerNote, true); XCTAssertEqual(r.ladderMode, true); XCTAssertEqual(r.masterMute, true)
    }

    /// An OLD doc lacking every rack/modulation key decodes each to nil and every `…Resolved` helper returns the
    /// documented default (off / all-in-path / 1 / no-lead / full window) — the "old docs decode nil" contract.
    func testRackFieldsOldDocDecodeNilAndResolveToDefaults() throws {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.formatVersion = 3
        var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        for k in ["curveMask", "curveAmount", "fenceMask", "fencePolicy", "fenceLo", "fenceHi", "monoMask",
                  "monoPriority", "pocketMask", "pocketMs", "convLead", "convStance", "rackEnabledMask",
                  "turnsPerNote", "ladderMode", "masterMute", "altCount", "flattenAmount", "claimLeak"] {
            root.removeValue(forKey: k)
        }
        let r = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: root))
        XCTAssertNil(r.curveMask); XCTAssertNil(r.masterMute); XCTAssertNil(r.ladderMode); XCTAssertNil(r.turnsPerNote)
        XCTAssertEqual(r.curveAmountResolved, [0, 0, 0, 0])
        XCTAssertEqual(r.fencePolicyResolved, [0, 0, 0, 0])
        XCTAssertEqual(r.fenceLoResolved, [0, 0, 0, 0])
        XCTAssertEqual(r.fenceHiResolved, [127, 127, 127, 127], "the high bound defaults to a full window")
        XCTAssertEqual(r.monoPriorityResolved, [0, 0, 0, 0])
        XCTAssertEqual(r.pocketMsResolved, [0, 0, 0, 0])
        XCTAssertEqual(r.convLeadResolved, -1, "no lead")
        XCTAssertEqual(r.convStanceResolved, [0, 0, 0, 0])
        XCTAssertEqual(r.rackEnabledResolved, 0b1111, "nil ⇒ every rack in path")
        XCTAssertEqual(r.altCountResolved, [1, 1, 1, 1], "nil ⇒ 1 note per turn")
        XCTAssertEqual(r.turnsPerNoteResolved, false); XCTAssertEqual(r.ladderModeResolved, false)
    }

    // CR-8: a PRE-v2 document missing busChannels / activeScene / morphMaster used to THROW at decode (the whole document
    // failed to load — data-loss). Now those three are additive-Optional: a missing key decodes nil + resolves to defaults.
    func testPreV2DocMissingBusChannelsActiveSceneMorphDecodes() throws {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty(), SceneState.empty()])
        d.busChannels = [7, 8, 9, 10]; d.activeScene = 1; d.morphMaster = 0.5   // set them, then strip → simulate an even-older doc
        var root = try JSONSerialization.jsonObject(with: JSONEncoder().encode(d)) as! [String: Any]
        for k in ["busChannels", "activeScene", "morphMaster"] { root.removeValue(forKey: k) }
        let r = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: root))   // must NOT throw
        XCTAssertNil(r.busChannels); XCTAssertNil(r.activeScene); XCTAssertNil(r.morphMaster)
        XCTAssertEqual(r.busChannelsResolved, [1, 2, 3, 4], "nil ⇒ the default stamp channels")
        XCTAssertEqual(r.activeSceneResolved, 0, "nil ⇒ scene 0")
        XCTAssertEqual(r.morphMasterResolved, 0)
        // and the present values still round-trip when the keys ARE there
        let back = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(back.busChannelsResolved, [7, 8, 9, 10]); XCTAssertEqual(back.activeSceneResolved, 1); XCTAssertEqual(back.morphMasterResolved, 0.5)
    }

    /// `resolved4` — the shared nil-safe per-emitter resolver behind ~11 rack helpers. Its four branches:
    /// nil→all-default · short→pad-with-default · out-of-range→clamp · over-long→truncate to exactly 4.
    func testResolved4ResolverBranches() {
        XCTAssertEqual(PluginState.resolved4(nil, 1, 1, 8), [1, 1, 1, 1], "nil → all default")
        XCTAssertEqual(PluginState.resolved4([5, 5], 0, 0, 100), [5, 5, 0, 0], "short → pad the tail with the default")
        XCTAssertEqual(PluginState.resolved4([999, -5, 50, 50], 0, 0, 100), [100, 0, 50, 50], "each element clamps to [lo,hi]")
        XCTAssertEqual(PluginState.resolved4([1, 2, 3, 4, 5, 6], 0, 0, 100), [1, 2, 3, 4], "over-long → exactly 4")
    }

    /// `macrosResolved` truncates an over-long persisted array to exactly 24 (the short/nil path is covered in
    /// EffectiveParamsTests; this locks the tail-drop).
    func testMacrosResolvedTruncatesOverLong() {
        var d = PluginState(colours: [], scenes: [SceneState.empty()])
        d.macros = (0..<30).map { Macro(name: "M\($0)") }
        XCTAssertEqual(d.macrosResolved.count, 24)
        XCTAssertEqual(d.macrosResolved[23].name, "M23", "keeps the first 24, drops 24…29")
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

    func testCellProcessorChainRoundTripsAndOldDocsDecodeNil() throws {
        // CELL MACHINE (feat/EditPageSpike): the per-cell processor CHAIN is an additive Optional — it round-trips
        // through JSON, and an old doc that never had it decodes `processors == nil` (the builder falls back to
        // the Colour head). No migration function needed (purely additive), matching chordSplit/velWindow/chop.
        var cell = Cell(colourID: "gold", buses: [.a])
        cell.processors = [ProcessorSlot(type: .arp),
                           { var s = ProcessorSlot(type: .ratchet); s.bypassed = true; return s }()]
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.scenes[0].cells[0][0] = cell
        let rt = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(d))
        XCTAssertEqual(rt.scenes[0].cells[0][0]?.processors?.count, 2, "the chain survives a JSON round-trip")
        XCTAssertEqual(rt.scenes[0].cells[0][0]?.processors?[0].type, .arp)
        XCTAssertEqual(rt.scenes[0].cells[0][0]?.processors?[1].bypassed, true, "per-slot bypass survives")

        var plain = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        plain.scenes[0].cells[0][0] = Cell(colourID: "gold", buses: [.a])   // an "old" cell, no chain
        let reloaded = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(plain))
        XCTAssertNil(reloaded.scenes[0].cells[0][0]?.processors, "a chain-less cell decodes processors == nil")
    }

    func testColourTemplateChainRoundTripsAndOldDocsDecodeNil() throws {
        // CELL MACHINE stage-3: the shared TEMPLATE chain on the Colour is an additive Optional — round-trips,
        // and an old colour without the key decodes nil (the builder then falls back to type+paramsA).
        var cs = colourIDs.map { Colour(colourID: $0, type: .arp) }
        cs[0].templateChain = [ProcessorSlot(type: .passgate), ProcessorSlot(type: .arp)]
        let rt = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(PluginState(colours: cs, scenes: [SceneState.empty()])))
        XCTAssertEqual(rt.colours[0].templateChain?.count, 2, "the colour template chain round-trips")
        XCTAssertEqual(rt.colours[0].templateChain?[1].type, .arp)
        let plain = try JSONDecoder().decode(PluginState.self, from: JSONEncoder().encode(PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])))
        XCTAssertNil(plain.colours[0].templateChain, "a colour with no template decodes templateChain == nil")
    }

    // EDIT-page wave W1 — TWIN editing: `.twins` groups config-equal cells (perform state ignored) and edits
    // apply to the whole set in one step; a divergent cell / other colour is excluded.
    func testTwinScopeGroupsIdenticalCellsAndEditsTogether() {
        var s = SceneState.empty()
        var cell = Cell(colourID: "gold", buses: [.a]); cell.processors = [ProcessorSlot(type: .arp)]
        s.cells[0][0] = cell; s.cells[1][1] = cell                       // two identical twins
        var mutedTwin = cell; mutedTwin.muted = true; s.cells[4][4] = mutedTwin   // perform-state differs → STILL a twin
        var diverged = cell; diverged.processors = [ProcessorSlot(type: .ratchet)]; s.cells[2][2] = diverged   // diff chain → not a twin
        var other = Cell(colourID: "cyan", buses: [.a]); other.processors = [ProcessorSlot(type: .arp)]; s.cells[3][3] = other   // diff colour → not
        XCTAssertEqual(Set(s.editScopeTargets(col: 0, row: 0, scope: .twins)), [0, 1 * 8 + 1, 4 * 8 + 4],
                       "twins = config-identical cells (perform state ignored); divergent chain + other colour excluded")
        s.applyToScope(col: 0, row: 0, scope: .twins) { $0.buses = [.b] }
        XCTAssertEqual(s.cells[0][0]?.buses, [.b]); XCTAssertEqual(s.cells[1][1]?.buses, [.b]); XCTAssertEqual(s.cells[4][4]?.buses, [.b])
        XCTAssertEqual(s.cells[2][2]?.buses, [.a], "the non-twin is untouched")
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

    // DELETE removes the cell (grid-chaining retired → no children to re-point; it's a plain removal).
    func testDeleteSeverRemovesTheCell() {
        var s = SceneState.empty()
        s.cells[0][0] = Cell(colourID: "gold")
        s.cells[0][2] = Cell(colourID: "cyan", buses: [.a])
        s.deleteCellSever(col: 0, row: 2)
        XCTAssertNil(s.cells[0][2], "the cell is removed")
        XCTAssertNotNil(s.cells[0][0], "other cells are untouched")
    }

    // (testMoveRelocatesAndOverwrites removed 2026-08-06: the destructive overwrite-move `moveCellTo` is retired
    //  per the design ferry — a MOVE drop on a populated cell SWAPS, never destroys. The correct swap semantics are
    //  covered by CellRelocationTests.testSwapCells* .)

    // MARK: - §10/11f SPATIAL ROUTING (patch-bay model core)

    private func headed(_ colourID: String, receiver: Int) -> Cell { var c = Cell(colourID: colourID, buses: [.a]); c.inputRow = nil; c.inputReceiver = receiver; return c }
    func testRouteInReceiverAndToggleEmitter() {
        var s = SceneState.empty()
        s.cells[0][3] = headed("gold", receiver: 0)
        s.routeInReceiver(col: 0, row: 3, receiver: 2)  // pick a receiver door
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

    // Bounds-safe cell access: a stale UI position or a decoded RAGGED scene must never trap a subscript (the
    // crash class behind multi-cell edits). cellAt/setCell/inBounds/swapCells all no-op out of range.
    func testBoundsSafeCellAccessNeverTraps() {
        var s = SceneState.empty()
        s.cells[3][4] = Cell(colourID: "gold")
        XCTAssertEqual(s.cellAt(3, 4)?.colourID, "gold", "in-range read round-trips")
        XCTAssertNil(s.cellAt(99, 99), "far out-of-range read → nil, no trap")
        XCTAssertNil(s.cellAt(-1, 0), "negative index → nil")
        s.setCell(50, 50, Cell(colourID: "cyan"))          // out-of-range write is a no-op
        XCTAssertTrue(s.cellAt(50, 50) == nil, "out-of-range write did nothing")
        s.setCell(3, 4, nil); XCTAssertNil(s.cellAt(3, 4), "in-range write clears the cell")
        s.swapCells((0, 0), (99, 99))                      // ragged/out-of-range swap is a no-op (no trap)
        // A genuinely RAGGED scene (short of 8×8, as a bad decode could produce) is safe too.
        let ragged = SceneState(cells: [[Cell(colourID: "gold"), nil]])   // 1 column, 2 rows
        XCTAssertEqual(ragged.cellAt(0, 0)?.colourID, "gold")
        XCTAssertNil(ragged.cellAt(0, 5), "row past the ragged column → nil")
        XCTAssertNil(ragged.cellAt(7, 7), "column past the ragged grid → nil")
        XCTAssertFalse(ragged.inBounds(7, 7)); XCTAssertTrue(ragged.inBounds(0, 1))
    }

    func testPadScenesFillsToEightIdempotently() {
        var d = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        d.scenes[0].cells[0][0] = Cell(colourID: "gold")
        d.padScenes()
        XCTAssertEqual(d.scenes.count, PluginState.maxScenes)
        XCTAssertFalse(d.scenes[0].isEmpty, "slot 0 preserved")
        XCTAssertTrue(d.scenes[PluginState.maxScenes - 1].isEmpty, "padded slots are empty +")
        d.padScenes(); XCTAssertEqual(d.scenes.count, PluginState.maxScenes, "idempotent — never grows past the strip size")
    }

    func testSwitchSceneOnlyToNonEmpty() {
        var d = multi()
        d.scenes[3].cells[0][0] = Cell(colourID: "gold")
        d.switchScene(to: 3); XCTAssertEqual(d.activeSceneResolved, 3)
        d.switchScene(to: 5); XCTAssertEqual(d.activeSceneResolved, 3, "empty slots aren't playable — the switch is ignored")
    }

    func testSaveCurrentSceneCopiesActiveIntoSlotWithoutSwitching() {
        var d = multi()
        d.scenes[0].cells[2][2] = Cell(colourID: "cyan")
        d.saveCurrentScene(toSlot: 7)
        XCTAssertEqual(d.scenes[7].cells[2][2]?.colourID, "cyan", "slot 7 = a copy of the active scene")
        XCTAssertEqual(d.activeSceneResolved, 0, "save-here does NOT switch")
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
        XCTAssertEqual(d.activeSceneResolved, 7, "the playing scene follows its content to the new slot")
    }

    func testSwapCarriesTheActiveIndex() {
        var d = multi()
        d.scenes[3].cells[0][0] = Cell(colourID: "gold")
        d.scenes[6].cells[0][0] = Cell(colourID: "cyan")
        d.activeScene = 6
        d.swapScenes(3, 6)
        XCTAssertEqual(d.activeSceneResolved, 3, "active followed its content across the swap")
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
        XCTAssertGreaterThanOrEqual(box.cells[3 * Snap.rows + 0].colourIndex, 0, "the ACTIVE scene's cell is in the snapshot")
        XCTAssertLessThan(box.cells[0].colourIndex, 0, "the inactive scene's cell is NOT")
    }

    func testMigrationPadsScenesToEight() {
        var d = doc { $0.cells[0][0] = Cell(colourID: "gold") }   // v2, length-1
        d.migrateLegacyRoutingIfNeeded()
        XCTAssertEqual(d.scenes.count, PluginState.maxScenes, "old length-1 docs pad to the scene-strip size")
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
        d.scenes[d.activeSceneResolved].cells[col][row] = cell
        return d
    }
    func testRestoringCellReplacesActiveSceneCell() {
        let preview = Cell(colourID: "gold")
        let d = doc(with: preview, at: 3, 4)                    // preview cell sitting in the document
        let restored = d.restoringCell(col: 3, row: 4, to: nil) // encode with the covered (empty) cell
        XCTAssertNil(restored.scenes[restored.activeSceneResolved].cells[3][4], "preview stripped for encoding")
        XCTAssertEqual(d.scenes[d.activeSceneResolved].cells[3][4]?.colourID, "gold", "the live document is untouched")
    }
    func testRestoringCellRestoresACoveredCell() {
        let covered = Cell(colourID: "cyan")
        var d = doc(with: Cell(colourID: "gold"), at: 1, 1)     // preview covering a cyan cell
        let restored = d.restoringCell(col: 1, row: 1, to: covered)
        XCTAssertEqual(restored.scenes[restored.activeSceneResolved].cells[1][1]?.colourID, "cyan")
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
        XCTAssertNil(decoded.scenes[decoded.activeSceneResolved].cells[2][2], "the reloaded preset has no preview cell")
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

    // DATA-LOSS REGRESSION (Paul 2026-08-27): BuildPart.castSlots was added 2026-08-17, a day after `buildUnassigned`
    // first persisted (2026-08-16) — a save in that window has NO `castSlots` key. Synthesized Decodable would THROW on
    // the missing non-Optional key → the whole PluginState decode fails → silent factory reset. The decode-tolerant
    // init(from:) makes a missing key fall back to its default instead of throwing.
    func testBuildPartDecodesWithMissingCastSlots() throws {
        var p = BuildPart(); p.cast = ["gold", "b0"]; p.receiver = 2; p.rate = .r1_4
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(p)) as! [String: Any]
        dict.removeValue(forKey: "castSlots")                                  // simulate a 2026-08-16→17 save
        let back = try JSONDecoder().decode(BuildPart.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(back.castSlots, [:], "missing castSlots ⇒ empty, not a throw")
        XCTAssertEqual(back.cast, ["gold", "b0"], "the rest of the part still decodes")
        XCTAssertEqual(back.receiver, 2)
    }
    // The nested path that actually loses the document: buildUnassigned → part missing castSlots must not throw.
    func testBuildUnassignedDataSurvivesAPartMissingCastSlots() throws {
        var u = BuildUnassignedData(part: BuildPart()); u.idCounter = 5
        var top = try JSONSerialization.jsonObject(with: JSONEncoder().encode(u)) as! [String: Any]
        var part = top["part"] as! [String: Any]; part.removeValue(forKey: "castSlots"); top["part"] = part
        let back = try JSONDecoder().decode(BuildUnassignedData.self, from: JSONSerialization.data(withJSONObject: top))
        XCTAssertEqual(back.idCounter, 5)
        XCTAssertEqual(back.part.castSlots, [:])
    }
    // The systemic guard: BuildSceneSnapshot had no decode-tolerant init — a future field going missing must not throw.
    func testBuildSceneSnapshotDecodesWithAMissingField() throws {
        let s = BuildSceneSnapshot(performCells: Array(repeating: Array(repeating: nil, count: 8), count: 8),
                                   performChain: Array(repeating: Array(repeating: [], count: 8), count: 8),
                                   performRecv: Array(repeating: 0, count: 8), performEmit: Array(repeating: [.a], count: 8),
                                   performPart: Array(repeating: -1, count: 8), performMute: [],
                                   performStagingRow: Array(repeating: -1, count: 8), performLane: 0,
                                   row8On: Array(repeating: false, count: 8))
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        dict.removeValue(forKey: "row8On")                                     // simulate a pre-row8 snapshot
        let back = try JSONDecoder().decode(BuildSceneSnapshot.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(back.row8On.count, 8, "missing row8On ⇒ 8 defaults, not a throw")
        XCTAssertEqual(back.performPart.count, 8)
    }
    // Full round-trips stay lossless (the decode-tolerant init didn't change the happy path).
    func testBuildTypesRoundTripLosslessly() throws {
        var p = BuildPart(); p.castSlots = [3: "b1"]; p.cast = ["gold"]; p.length = 6
        XCTAssertEqual(try JSONDecoder().decode(BuildPart.self, from: JSONEncoder().encode(p)), p)
        let u = BuildUnassignedData(part: p, colours: [Colour(colourID: "b1", type: .arp)], hues: ["b1": 0x112233], idCounter: 9)
        XCTAssertEqual(try JSONDecoder().decode(BuildUnassignedData.self, from: JSONEncoder().encode(u)), u)
    }

    // CR-8 CLASS on Cell (2026-08-29): `Cell.inputChannel` (non-Optional) was added at v3.0, so a genuine
    // formatVersion-2 document's cells LACK the key → synthesized Decodable would throw at Cell decode, BEFORE
    // migrateLegacyRoutingIfNeeded() runs → the whole session silently factory-resets. The decode-tolerant Cell
    // init(from:) makes a missing key fall back to its default instead of throwing.
    func testCellDecodesWithMissingInputChannel() throws {
        var cell = Cell(colourID: "gold"); cell.buses = [.a, .c]; cell.inputChannel = 3; cell.muted = true
        var dict = try JSONSerialization.jsonObject(with: JSONEncoder().encode(cell)) as! [String: Any]
        dict.removeValue(forKey: "inputChannel")                                // simulate a pre-v3.0 (formatVersion 2) cell
        let back = try JSONDecoder().decode(Cell.self, from: JSONSerialization.data(withJSONObject: dict))
        XCTAssertEqual(back.inputChannel, 0, "missing inputChannel ⇒ OMNI(0), not a throw")
        XCTAssertEqual(back.buses, [.a, .c], "the rest of the cell still decodes")
        XCTAssertTrue(back.muted)
    }
    // The whole-document scenario: a formatVersion-2 PluginState whose cells have NO inputChannel key must load
    // (so migration can then run) rather than throwing and losing the session.
    func testFormatV2DocWithCellsMissingInputChannelDecodes() throws {
        var s = PluginState(colours: colourIDs.map { Colour(colourID: $0, type: .arp) }, scenes: [SceneState.empty()])
        s.formatVersion = 2
        s.scenes[0].cells[0][0] = Cell(colourID: "gold")
        var top = try JSONSerialization.jsonObject(with: JSONEncoder().encode(s)) as! [String: Any]
        var scenes = top["scenes"] as! [[String: Any]]
        var rows = scenes[0]["cells"] as! [[Any]]                              // [col][row]; strip inputChannel from every present cell
        for ci in rows.indices { for ri in rows[ci].indices {
            if var cellDict = rows[ci][ri] as? [String: Any] { cellDict.removeValue(forKey: "inputChannel"); rows[ci][ri] = cellDict }
        } }
        scenes[0]["cells"] = rows; top["scenes"] = scenes
        let back = try JSONDecoder().decode(PluginState.self, from: JSONSerialization.data(withJSONObject: top))
        XCTAssertEqual(back.scenes[0].cells[0][0]?.colourID, "gold", "the v2 document loads instead of throwing → migration can run")
    }
    // The happy path is untouched: a complete cell round-trips byte-identically (the decode-tolerant init didn't
    // change the encoded form — fields stay non-Optional, seal/twin/Equatable identity preserved).
    func testCellRoundTripsLosslessly() throws {
        var cell = Cell(colourID: "azure"); cell.inputChannel = 5; cell.inputReceiver = 2; cell.buses = [.b]
        cell.processors = [ProcessorSlot(type: .harmonize)]; cell.stars = 4; cell.alt = true
        XCTAssertEqual(try JSONDecoder().decode(Cell.self, from: JSONEncoder().encode(cell)), cell)
    }
    // BuildPlayGridData is the newest Codable type + the one lacking a decode-tolerance test (its siblings all have
    // one). A missing post-v1 key must DEFAULT, never throw — else an older save throws → the whole PluginState
    // decode throws → factory reset (the CR-8 data-loss class this decode-tolerant init exists to prevent).
    func testBuildPlayGridDataDecodesWithMissingKeys() throws {
        let json = #"{"colOn":[true,false,false,false,false,false,false,false]}"#.data(using: .utf8)!
        let pg = try JSONDecoder().decode(BuildPlayGridData.self, from: json)
        XCTAssertTrue(pg.colOn[0], "the present key decodes")
        XCTAssertEqual(pg.colLen, Array(repeating: 1, count: 8), "a MISSING key falls back to its default, never throws")
        XCTAssertEqual(pg.sel.count, 8)
        XCTAssertEqual(pg.idCounter, 0)
    }
    // thruReceiverResolved clamps a decoded door index to 0…3 (the four doors A–D); an out-of-range value must not
    // reach the render as-is. (Coverage gap 2026-08-30.)
    func testThruReceiverResolvedClampsToDoorRange() {
        var st = PluginState(colours: [], scenes: [SceneState.empty()])
        st.thruReceiver = 9;  XCTAssertEqual(st.thruReceiverResolved, 3, "above D clamps to 3")
        st.thruReceiver = -4; XCTAssertEqual(st.thruReceiverResolved, 0, "below A clamps to 0")
        st.thruReceiver = nil; XCTAssertEqual(st.thruReceiverResolved, 0, "nil → door A (0)")
    }
}
