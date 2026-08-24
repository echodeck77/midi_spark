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

    func testRow8OnResolvedNilSafe() {
        var s = SceneState.empty()
        XCTAssertEqual(s.row8OnResolved, Array(repeating: false, count: 8), "nil ⇒ all off")
        s.row8On = [true]
        XCTAssertEqual(s.row8OnResolved.count, 8); XCTAssertTrue(s.row8OnResolved[0]); XCTAssertFalse(s.row8OnResolved[7])
    }
}
