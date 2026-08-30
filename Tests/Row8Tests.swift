//  Row8Tests.swift
//  ROW 8 — the action strip (Paul 2026-08-22, Docs/row8-spec.md). Model + persistence + the pure runtime derivation.

import XCTest

final class Row8Tests: XCTestCase {

    // THE FACTORY DECK — the "danger gradient": left plays (zero-config trio), right wields (routing wing); cell 4 = [+].
    func testFactoryDeckIsTheDangerGradient() {
        let d = Row8Cell.factoryDeck
        XCTAssertEqual(d.count, 8)
        XCTAssertEqual(d.map(\.type), [.stutter, .freeze, .halftime, .empty, .redirect, .swap, .kill, .broadcast])
        XCTAssertEqual(d[3].type, .empty, "cell 4 is the deliberate [+] authoring invitation")
    }

    // The MOVER defaults follow the spec: the trio (stutter=held, freeze/halftime=toggle), the wing (redirect/broadcast
    // held, kill one-shot), etc.
    func testDefaultMoversPerType() {
        XCTAssertEqual(Row8Cell.defaultMover(for: .stutter), .held)
        XCTAssertEqual(Row8Cell.defaultMover(for: .freeze), .toggle)
        XCTAssertEqual(Row8Cell.defaultMover(for: .halftime), .toggle)
        XCTAssertEqual(Row8Cell.defaultMover(for: .redirect), .held)
        XCTAssertEqual(Row8Cell.defaultMover(for: .broadcast), .held)
        XCTAssertEqual(Row8Cell.defaultMover(for: .swap), .toggle)
        XCTAssertEqual(Row8Cell.defaultMover(for: .kill), .oneShot)
        XCTAssertEqual(Row8Cell.defaultMover(for: .setup), .oneShot)
        XCTAssertEqual(Row8Cell.defaultMover(for: .pcSend), .oneShot)
        XCTAssertEqual(Row8Cell.defaultMover(for: .ccPunch), .held)
    }

    // make(type) seeds the payload + the default mover.
    func testMakeSeedsPayloadAndMover() {
        let s = Row8Cell.make(.stutter)
        XCTAssertEqual(s.type, .stutter); XCTAssertEqual(s.mover, .held); XCTAssertEqual(s.rate, .r1_16)
        let r = Row8Cell.make(.redirect)
        XCTAssertEqual(r.wireFrom, 0); XCTAssertEqual(r.wireTo, 1); XCTAssertEqual(r.mover, .held)
        let h = Row8Cell.make(.halftime)
        XCTAssertEqual(h.halftimeMode, 0, "÷2 — the drop"); XCTAssertEqual(h.mover, .toggle)
        let k = Row8Cell.make(.kill)
        XCTAssertEqual(k.killHard, false, "soft by default"); XCTAssertEqual(k.mover, .oneShot)
        let cc = Row8Cell.make(.ccPunch)
        XCTAssertEqual(cc.ccNum, 74); XCTAssertEqual(cc.ccVal, 127); XCTAssertEqual(cc.mover, .held)
    }

    // row8Resolved: nil ⇒ the factory deck; a short array pads with empty; an explicit deck survives.
    func testRow8ResolvedNilAndShortSafe() {
        var st = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [SceneState.empty()])
        XCTAssertEqual(st.row8Resolved.map(\.type), Row8Cell.factoryDeck.map(\.type), "nil ⇒ factory deck")
        st.row8 = [Row8Cell.make(.freeze), Row8Cell.make(.macro)]              // only 2 authored
        let r = st.row8Resolved
        XCTAssertEqual(r.count, 8)
        XCTAssertEqual(r[0].type, .freeze); XCTAssertEqual(r[1].type, .macro)
        XCTAssertEqual(r[2].type, .empty, "the tail pads with empty cells")
    }

    // Codable: a custom deck + a scene's lit toggles survive the document round-trip; an OLD doc (no row8 keys) decodes.
    func testRow8SurvivesCodableRoundTrip() throws {
        var st = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [SceneState.empty()])
        st.row8 = [Row8Cell.make(.part), Row8Cell.make(.setup), Row8Cell.make(.halftime)]
        st.row8![0].partRef = 2; st.row8![1].setupN = 3
        st.scenes[0].row8On = [false, true, false, false, false, false, false, false]
        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(st))
        XCTAssertEqual(back.row8?[0].partRef, 2)
        XCTAssertEqual(back.row8?[1].setupN, 3)
        XCTAssertEqual(back.row8?[2].type, .halftime)
        XCTAssertEqual(back.scenes[0].row8OnResolved[1], true, "the scene's lit toggle survives")
        XCTAssertEqual(back.scenes[0].row8OnResolved[0], false)
    }

    // SCENES V2 persistence: the deployed play-grid arrangements (BuildSceneSnapshot) travel with the document.
    func testBuildScenesSurviveCodableRoundTrip() throws {
        var st = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [SceneState.empty()])
        var cells = Array(repeating: Array(repeating: String?.none, count: 8), count: 8)
        cells[0][0] = "gold"
        let snap = BuildSceneSnapshot(
            performCells: cells,
            performChain: Array(repeating: Array(repeating: [ProcessorSlot](), count: 8), count: 8),
            performRecv: Array(repeating: 0, count: 8), performEmit: Array(repeating: Set<Bus>([.a]), count: 8),
            performPart: [0, -1, -1, -1, -1, -1, -1, -1], performMute: [3],
            performStagingRow: Array(repeating: -1, count: 8), performLane: 0,
            row8On: [false, true, false, false, false, false, false, false], name: "verse")
        st.buildScenes = [snap, snap]; st.buildScenesActive = 1
        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(st))
        XCTAssertEqual(back.buildScenes?.count, 2)
        XCTAssertEqual(back.buildScenesActive, 1)
        XCTAssertEqual(back.buildScenes?[0].performCells[0][0], "gold")
        XCTAssertEqual(back.buildScenes?[0].performPart[0], 0)
        XCTAssertEqual(back.buildScenes?[0].performMute, [3])
        XCTAssertEqual(back.buildScenes?[0].row8On[1], true)
        XCTAssertEqual(back.buildScenes?[0].performEmit[0], [.a])
    }

    // ROOMS PLAY GRID persistence (Paul 2026-08-30): the play columns + their MULTI-STEP PASSES + referenced ephemeral
    // colours travel with the document, so a reload restores the play grid (was in-memory).
    func testBuildPlayGridSurvivesCodableRoundTrip() throws {
        var st = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [SceneState.empty()])
        var pg = BuildPlayGridData()
        pg.colOn[0] = true
        pg.colLen[0] = 3
        pg.colSteps[0] = ["a", nil, "c"]              // a 3-step pass with a rest
        pg.colStepEmit[0] = [[.a], [], [.c]]          // per-step emitters
        pg.colStepRecv[0] = [0, 0, 2]                 // per-step doors
        pg.colRate[0] = .r1_8
        var eph = Colour(colourID: "a", type: .arp); eph.templateChain = [ProcessorSlot(type: .arp)]
        pg.colours = [eph]
        st.buildPlayGrid = pg
        let back = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(st))
        let r = try XCTUnwrap(back.buildPlayGrid, "the play grid survives the document round-trip")
        XCTAssertTrue(r.colOn[0])
        XCTAssertEqual(r.colLen[0], 3, "the pass length survives")
        XCTAssertEqual(r.colSteps[0], ["a", nil, "c"], "the step colours survive (incl. the rest)")
        XCTAssertEqual(r.colStepEmit[0], [[.a], [], [.c]], "per-step emitters survive")
        XCTAssertEqual(r.colStepRecv[0], [0, 0, 2], "per-step doors survive")
        XCTAssertEqual(r.colRate[0], .r1_8, "the pass rate survives")
        XCTAssertEqual(r.colours.first?.templateChain?.first?.type, .arp, "referenced ephemeral colours travel")
        // Additive-Optional: an old save with no play grid decodes nil.
        var st2 = PluginState(colours: [Colour(colourID: "gold", type: .arp)], scenes: [SceneState.empty()])
        st2.buildPlayGrid = nil
        let back2 = try JSONDecoder().decode(PluginState.self, from: try JSONEncoder().encode(st2))
        XCTAssertNil(back2.buildPlayGrid, "no play grid → nil")
    }

    func testRow8OnResolvedNilSafe() {
        var s = SceneState.empty()
        XCTAssertEqual(s.row8OnResolved, Array(repeating: false, count: 8), "nil ⇒ all off")
        s.row8On = [true]
        XCTAssertEqual(s.row8OnResolved.count, 8); XCTAssertTrue(s.row8OnResolved[0]); XCTAssertFalse(s.row8OnResolved[7])
    }
}
