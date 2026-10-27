//  HocketGlyphTests.swift — HOCKET ferry (2026-10-27) §12 tests 17 and 19: the part states a rule gives the lane cards, and the glyph / strip looks they draw.
//  Test 17's rules are tests 5, 7 and 9's; the engine tests (HocketRouterTests) prove the notes leave where the state says, these prove what the cards show.

import XCTest

final class HocketGlyphTests: XCTestCase {
    private func rule(main: [Int], alt: [Int], _ configure: (inout HocketRule) -> Void = { _ in }) -> HocketRule { var r = HocketRule(); r.main = main; r.alt = alt; configure(&r); return r }
    private let RR = 1, RN = 2, BR = 3, BN = 4
    private func view(_ r: HocketRule, bus: Int, alt: Bool, k: Int64 = 0, running: Bool = true) -> HocketPartView {
        var t = HocketTurns(); t.running = running; t[0] = HocketTurn(isAlt: alt, k: k)
        return hocketPartView(bus: bus, rules: HocketRulesSnap(rules: [r]), turns: t)
    }

    // MARK: - test 17 — part states
    func testTest5sRuleRestsOneRiffAndPlaysTheOtherThenTheReverse() {
        let r = rule(main: [RR], alt: [BR]) { $0.mainLen = 3; $0.altLen = 1 }       // RED RIFF = bus 0, BLUE RIFF = bus 2
        XCTAssertEqual(view(r, bus: 0, alt: false).play, .playing); XCTAssertEqual(view(r, bus: 2, alt: false).play, .resting, "MAIN turn: BLUE RIFF rests")
        XCTAssertEqual(view(r, bus: 0, alt: true).play, .resting); XCTAssertEqual(view(r, bus: 2, alt: true).play, .playing, "ALT turn: the reverse")
        for alt in [false, true] { for bus in [0, 2] { XCTAssertEqual(view(r, bus: bus, alt: alt).carrying, -1, "SWAP PARTS carries nothing") } }
    }
    func testTest7sCrossingMakesBothNotesPartsAwayAndCarryingOnAltTurns() {
        let r = rule(main: [RN, BN], alt: [BN, RN]) { $0.mode = .pass; $0.unit = .bars }       // RED NOTES = bus 1, BLUE NOTES = bus 3
        XCTAssertEqual(view(r, bus: 1, alt: true), HocketPartView(play: .away(bus: 3), carrying: 3), "RED NOTES: away on blue, carrying the blue lane's line")
        XCTAssertEqual(view(r, bus: 3, alt: true), HocketPartView(play: .away(bus: 1), carrying: 1))
        for bus in [1, 3] { XCTAssertEqual(view(r, bus: bus, alt: false), HocketPartView(), "MAIN turn: each plays its own, carrying nothing") }
    }
    func testTest9ReplaceRestsTheReceiverAndMergePlaysIt() {
        let replace = rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.own = .replace }
        XCTAssertEqual(view(replace, bus: 1, alt: true), HocketPartView(play: .away(bus: 3), carrying: -1), "RED NOTES away on blue")
        XCTAssertEqual(view(replace, bus: 3, alt: true), HocketPartView(play: .resting, carrying: 1), "BLUE NOTES resting and carrying red")
        let merge = rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.own = .merge }
        XCTAssertEqual(view(merge, bus: 3, alt: true), HocketPartView(play: .playing, carrying: 1), "MERGE: BLUE NOTES playing and carrying")
    }
    func testAPartThatIsOffShowsOffInEveryCaseAndAStoppedTransportPlaysEveryOnPart() {
        let r = rule(main: [RN, BN], alt: [BN, RN]) { $0.mode = .pass }
        for alt in [false, true] { for bus in 0..<8 { XCTAssertEqual(hocketGlyphSpec(lane: bus / 2, partOff: true, view: view(r, bus: bus, alt: alt)).body, .offLook, "bus \(bus): off shows the off look, hocket states don't apply") } }
        for bus in 0..<8 { XCTAssertEqual(view(r, bus: bus, alt: true, running: false), HocketPartView(), "stopped: every part is playing") }
    }

    // MARK: - test 19 — glyph and strip looks
    func testTheFourGlyphStatesAndTheCrossingForEachLayer() {
        let own = HocketPalette.lane100(0), blue = HocketPalette.lane100(1), amber = HocketPalette.lane100(2)
        XCTAssertEqual(hocketGlyphSpec(lane: 0, partOff: false, view: HocketPartView()), HocketGlyphSpec(body: .filled(own), awayDisc: nil, carriedRing: nil), "playing: filled lane100, the clarity pass's on look")
        XCTAssertEqual(hocketGlyphSpec(lane: 0, partOff: false, view: HocketPartView(play: .resting, carrying: -1)), HocketGlyphSpec(body: .outline(own), awayDisc: nil, carriedRing: nil), "resting: hollow, never the off look")
        XCTAssertEqual(hocketGlyphSpec(lane: 0, partOff: false, view: HocketPartView(play: .away(bus: 3), carrying: -1)), HocketGlyphSpec(body: .outline(own), awayDisc: blue, carriedRing: nil), "away: hollow + a disc in the away lane's colour")
        XCTAssertEqual(hocketGlyphSpec(lane: 0, partOff: false, view: HocketPartView(play: .playing, carrying: 4)), HocketGlyphSpec(body: .filled(own), awayDisc: nil, carriedRing: amber), "carrying: the glyph as its own state + a ring in the carried lane's colour")
        XCTAssertEqual(hocketGlyphSpec(lane: 0, partOff: false, view: HocketPartView(play: .away(bus: 3), carrying: 4)), HocketGlyphSpec(body: .outline(own), awayDisc: blue, carriedRing: amber), "a crossing: both marks")
        XCTAssertEqual(hocketGlyphSpec(lane: 2, partOff: true, view: HocketPartView(play: .away(bus: 3), carrying: -1)), HocketGlyphSpec(body: .offLook, awayDisc: nil, carriedRing: nil), "an off part that carries nothing is the off look")
        XCTAssertEqual(hocketGlyphSpec(lane: 2, partOff: true, view: HocketPartView(play: .playing, carrying: 4)), HocketGlyphSpec(body: .offLook, awayDisc: nil, carriedRing: amber), "an off part still SOUNDS a line passed to it, so it shows the carrying ring")
        // the sizes the spec gives
        XCTAssertEqual(HocketGlyphSpec.disc, 7); XCTAssertEqual(HocketGlyphSpec.discRing, 1.5); XCTAssertEqual(HocketGlyphSpec.ringGap, 2); XCTAssertEqual(HocketGlyphSpec.ringWidth, 1.5); XCTAssertEqual(HocketGlyphSpec.easeSeconds, 0.15)
        XCTAssertEqual(HocketGlyphSpec.discBeyond, 3); XCTAssertEqual(HocketGlyphSpec.discBelow, 1)
    }
    func testTheStripsHollowRestingMarksAndTheFlashColour() {
        XCTAssertEqual(hocketStripLayerLook(lane: 0, view: HocketPartView(play: .resting, carrying: -1)), HocketStripLayerLook(hollow: true, flashLane: nil), "a resting layer's marks are hollow and don't flash")
        XCTAssertEqual(hocketStripLayerLook(lane: 0, view: HocketPartView()), HocketStripLayerLook(hollow: false, flashLane: 0), "a playing layer flashes in its own colour")
        XCTAssertEqual(hocketStripLayerLook(lane: 0, view: HocketPartView(play: .away(bus: 3), carrying: -1)), HocketStripLayerLook(hollow: false, flashLane: 1), "lane 1's notes are away on lane 2: its key flashes lane 2's colour")
        XCTAssertEqual(hocketStripLayerLook(lane: 0, view: HocketPartView(play: .playing, carrying: 4)), HocketStripLayerLook(hollow: false, flashLane: 0), "carrying adds nothing to the strip")
        XCTAssertEqual(HocketStripLayerLook.hollowWidth, 1.5)
        // the hit event names the output a strike left on, and that wins
        XCTAssertEqual(hocketFlashLane(ownLane: 0, dest: 3), 1); XCTAssertEqual(hocketFlashLane(ownLane: 2, dest: 4), 2); XCTAssertEqual(hocketFlashLane(ownLane: 2, dest: -1), 2, "an event that does not say: the lane's own")
    }
}
