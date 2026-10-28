//  CardBackTests.swift — CARD BACKS ferry (2026-10-28) §13 tests 6–9 and the pure pieces under them: the header switch, the flip, the back's frames and floors, the roll's maths, the jacks' looks and activity, the XY / OCT drawing
//  numbers, the label pill and invitation frames, and the VoiceOver strings. Every expected number is the ferry's own (or Paul's 116 pt override of the switch); where the source differs from the ferry the test says so.

import XCTest

final class CardBackTests: XCTestCase {
    private func near(_ a: CGFloat, _ b: CGFloat, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a, b, accuracy: 1e-9, msg, file: file, line: line) }
    private func near(_ a: Double, _ b: Double, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a, b, accuracy: 1e-9, msg, file: file, line: line) }

    // MARK: §3.1 the switch

    func testTheSwitchIs116WideWithPaulsSplit() {
        typealias S = EuclideousCardSwitchMetrics
        near(S.width, 116); near(S.patternWidth, 64); near(S.mixWidth, 43, "MIX takes the rest: 116 − 3 − 3 − 3 − 64"); near(S.containerHeight, 31); near(S.segmentHeight, 25)
        near(S.containerRadius, 8); near(S.segmentRadius, 6); near(S.fontSize, 9); near(S.tracking, 0.06)
        XCTAssertEqual(S.container, HocketColor(0x1F2127)); XCTAssertEqual(S.selectedFill, HocketColor(0xDFE3EA)); XCTAssertEqual(S.selectedText, HocketColor(0x0D0F14)); XCTAssertEqual(S.unselectedText, HocketColor(0xAAB0BA))
        let f = euclideousCardSwitchFrames(x: 300, rowMidY: 31)
        XCTAssertEqual(f.container, CGRect(x: 300, y: 15.5, width: 116, height: 31))
        XCTAssertEqual(f.pattern, CGRect(x: 303, y: 18.5, width: 64, height: 25)); XCTAssertEqual(f.mix, CGRect(x: 370, y: 18.5, width: 43, height: 25))
        near(f.mix.minX - f.pattern.maxX, 3, "the segments are 3 pt apart")
        XCTAssertEqual(f.patternTarget.height, 44); XCTAssertEqual(f.mixTarget.height, 44, "each a 44 tall target")
        near(f.patternTarget.minX, 300); near(f.mixTarget.maxX, 416); near(f.patternTarget.maxX, f.mixTarget.minX, "together the two targets cover the whole 116 pt")
    }
    func testATapOnTheSelectedSegmentDoesNothing() {
        XCTAssertNil(euclideousCardSwitchTapTarget(tapped: .pattern, current: .pattern)); XCTAssertNil(euclideousCardSwitchTapTarget(tapped: .mix, current: .mix))
        XCTAssertEqual(euclideousCardSwitchTapTarget(tapped: .mix, current: .pattern), .mix); XCTAssertEqual(euclideousCardSwitchTapTarget(tapped: .pattern, current: .mix), .pattern)
    }
    /// Header widths with the switch (Paul: 116, so layout A holds at 1190): A 1029.88 → 1153.88; B 587.88 unchanged; C row 2 needs 550.
    func testTheHeadersLayoutsWithTheSwitch() {
        let full = euclideousHeaderGroupWidths(compact: false)
        near(full.cardSwitch, 116)
        near(euclideousHeaderANeeds(full), 295.88 + 8 + 116 + 16 + 426 + 16 + 276, "A: BRAND + sp8 + switch + gap + NOTES + gap + UTILITIES")
        near(euclideousHeaderANeeds(full), 1153.88)
        near(full.brand + full.utilities + full.gap, 587.88, "B's row 1 is untouched")
        // A at the 1190 reference: the switch right after the lock tile; NOTES pinned by the right edge exactly where it was (440)
        let p = euclideousPageLayout(size: CGSize(width: 1190, height: 834))
        XCTAssertEqual(p.headerKind, .a)
        let l = euclideousHeaderLayout(containerW: 1158, isLandscape: true, riffLeadingX: p.riffLeadingX)
        near(l.brand.width, 295.88); near(l.cardSwitch.x, 303.88); near(l.cardSwitch.width, 116); XCTAssertEqual(l.cardSwitch.row, 0)
        near(l.notes.x, 440, "NOTES does not move at 1190 (435.88 is its floor now)"); near(l.notes.x - (l.cardSwitch.x + l.cardSwitch.width), 20.12)
        // the widths the layouts DO and DO NOT fit
        let a = euclideousHeaderANeeds(full)
        XCTAssertEqual(euclideousHeaderKind(containerW: a, isLandscape: true), .a); XCTAssertEqual(euclideousHeaderKind(containerW: a - 0.01, isLandscape: true), .b)
        for (view, kind) in [(1376.0, EuclideousHeaderLayout.Kind.a), (1210, .a), (1194, .a), (1190, .a), (1186, .a), (1185, .b), (1180, .b), (1176, .b), (1133, .b), (1113, .b), (1024, .b)] {
            XCTAssertEqual(euclideousHeaderKind(containerW: CGFloat(view) - 32, isLandscape: true), kind, "landscape view \(view)")
        }
        // B and C: the switch leads row 2
        let b = euclideousHeaderLayout(containerW: 800, isLandscape: false, riffLeadingX: 0)
        XCTAssertEqual(b.kind, .b); XCTAssertEqual(b.cardSwitch.row, 1); near(b.cardSwitch.x, 0); near(b.notes.x, 124)
        let c = euclideousHeaderLayout(containerW: 550, isLandscape: false, riffLeadingX: 0)
        XCTAssertEqual(c.kind, .c); near(c.notes.x + c.notes.width, 550, "C fits exactly from 550")
    }

    // MARK: §3.3 / §3.5 / test 6 the flip

    func testEachLanesFlipAtItsOwnStartMidpointAndEnd() {
        for lane in 0..<4 {
            let start = 0.070 * Double(lane)
            func at(_ ms: Double) -> EuclideousCardFlipFrame { euclideousCardFlip(sinceTap: ms / 1000, lane: lane, target: .mix) }
            let before = at(start * 1000 - 1 > 0 ? start * 1000 - 1 : 0)           // waiting its turn (lane 0 has no wait: t = 0 is its start)
            near(before.scaleX, 1); XCTAssertEqual(before.side, .pattern); XCTAssertTrue(before.ignoresTouches, "committed from the tap")
            let s = at(start * 1000)
            near(s.scaleX, 1, "lane \(lane + 1) starts at \(70 * lane) ms with the full width"); XCTAssertEqual(s.side, .pattern); XCTAssertTrue(s.ignoresTouches)
            let m = at(start * 1000 + 140)
            near(m.scaleX, 0, "…is edge-on at the midpoint"); XCTAssertEqual(m.side, .mix, "…and swaps its side there"); XCTAssertTrue(m.ignoresTouches)
            let justBefore = at(start * 1000 + 139.9)
            XCTAssertEqual(justBefore.side, .pattern); XCTAssertLessThan(justBefore.scaleX, 0.01)
            let e = at(start * 1000 + 280)
            near(e.scaleX, 1, "…and is full width again at \(280 + 70 * lane) ms"); XCTAssertEqual(e.side, .mix); XCTAssertFalse(e.ignoresTouches, "touches are back")
            let quarter = at(start * 1000 + 70)
            XCTAssertGreaterThan(quarter.scaleX, 0); XCTAssertLessThan(quarter.scaleX, 1); XCTAssertEqual(quarter.side, .pattern, "the ease is symmetric: a quarter in is the same scale as three quarters in")
            near(quarter.scaleX, at(start * 1000 + 210).scaleX)
        }
        near(euclideousCardFlip(sinceTap: -0.1, lane: 2, target: .mix).scaleX, 1); XCTAssertEqual(euclideousCardFlip(sinceTap: -0.1, lane: 2, target: .mix).side, .pattern, "before the tap: the old side")
        XCTAssertEqual(euclideousCardFlip(sinceTap: 0.2, lane: 1, target: .pattern).side, .mix, "flipping back to PATTERN starts from MIX")
    }
    func testReduceMotionIsAOneHundredFiftyMillisecondCrossfadeOfAllFourAtOnce() {
        for t in [0.0, 0.03, 0.075, 0.12, 0.149] {
            let frames = (0..<4).map { euclideousCardFlip(sinceTap: t, lane: $0, target: .mix, reduceMotion: true) }
            XCTAssertTrue(frames.allSatisfy { $0 == frames[0] }, "all four cards at once at \(t)")
            near(frames[0].scaleX, 1, "opacity only: no scaling"); near(frames[0].opacity, t / 0.150); XCTAssertEqual(frames[0].underSide, .pattern); near(frames[0].underOpacity, 1 - t / 0.150)
            XCTAssertTrue(frames[0].ignoresTouches)
        }
        let done = euclideousCardFlip(sinceTap: 0.15, lane: 3, target: .mix, reduceMotion: true)
        XCTAssertEqual(done.side, .mix); near(done.opacity, 1); XCTAssertNil(done.underSide); XCTAssertFalse(done.ignoresTouches)
    }
    func testTheFlipIsLiveUntilTheLastCardIsDone() {
        XCTAssertFalse(euclideousCardFlipIsLive(since: -0.1)); XCTAssertTrue(euclideousCardFlipIsLive(since: 0)); XCTAssertTrue(euclideousCardFlipIsLive(since: 0.489))
        XCTAssertFalse(euclideousCardFlipIsLive(since: 0.49), "280 + 3 × 70 ms"); XCTAssertTrue(euclideousCardFlipIsLive(since: 0.149, reduceMotion: true)); XCTAssertFalse(euclideousCardFlipIsLive(since: 0.15, reduceMotion: true))
    }

    // MARK: §4 / test 7 the back's frames

    /// The ferry's reference card (376 × 316) with the ferry's own strip top (y 62): every number §4.3–4.4 and §7.2 gives.
    func testTheFerrysNumbersAtTheReferenceCard() {
        let L = euclideousCardBackLayout(card: CGSize(width: 376, height: 316), stripTop: EuclideousCardBackMetrics.stripTopFerry)
        XCTAssertEqual(L.strip, CGRect(x: 10, y: 62, width: 356, height: 22), "the MIX strip: x 10–366, y 62–84")
        near(L.rowHeight, 103, "rowH = (306 − 84 − 2 × 8) ÷ 2")
        XCTAssertEqual(L.riff.row, CGRect(x: 10, y: 92, width: 356, height: 103), "the riff row: y 92–195"); XCTAssertEqual(L.notes.row, CGRect(x: 10, y: 203, width: 356, height: 103), "the notes row: y 203–306")
        for p in [L.riff, L.notes] {
            let r = p.row
            XCTAssertEqual(p.xy, CGRect(x: r.minX, y: r.minY, width: 92, height: 71), "the XY pad: x 0–92, y 0 to rowH − 32")
            XCTAssertEqual(p.oct, CGRect(x: r.minX, y: r.maxY - 28, width: 92, height: 28), "OCT: 28 tall at the bottom"); near(p.oct.minY - p.xy.maxY, 4, "sp4 between them")
            XCTAssertEqual(p.rollPanel, CGRect(x: r.minX + 100, y: r.minY, width: 256, height: 103), "the roll panel: x 100–356")
            XCTAssertEqual(p.roll, CGRect(x: r.minX + 100, y: r.minY, width: 256, height: 57), "the roll: y 0 to rowH − 46"); XCTAssertEqual(p.jackStrip, CGRect(x: r.minX + 100, y: r.minY + 57, width: 256, height: 46), "the jack strip: the bottom 46")
            XCTAssertEqual(p.seam, CGRect(x: r.minX + 100, y: r.minY + 57, width: 256, height: 2), "the seam: 2 pt along the top of the jack strip, the roll's full width")
            XCTAssertEqual(p.jackCells.map { $0.width }, [64, 64, 64, 64]); near(p.jackCells[0].minX, p.jackStrip.minX); near(p.jackCells[3].maxX, p.jackStrip.maxX)
            for (i, cell) in p.jackCells.enumerated() {
                XCTAssertEqual(p.jackLights[i], CGRect(x: cell.minX + 8, y: cell.midY - 3, width: 6, height: 6), "the light: 6 pt, 8 pt in, centred")
                XCTAssertEqual(p.jackSockets[i], CGRect(x: cell.minX + 18, y: cell.midY - 12, width: 24, height: 24), "the socket: 24 pt, its leading edge 18 pt in, centred")
                near(p.jackLetters[i].minX, cell.minX + 46, "the letter: 46 pt in"); near(p.jackLetters[i].midY, cell.midY)
            }
        }
        XCTAssertTrue(L.floors.isEmpty, "no floor flags at the reference: \(L.floors)")
    }
    /// SOURCE wins: the lane card's tab row starts at 10 + 44 + 6 = 60 (the ferry says 62), so with the default strip top the strip is y 60–82 and every row is a point taller.
    func testTheSameFormulasFromTheSourcesTabRowTop() {
        near(EuclideousCardBackMetrics.stripTopSource, 60); near(EuclideousCardBackMetrics.stripTopFerry, 62)
        let L = euclideousCardBackLayout(card: CGSize(width: 376, height: 316))
        XCTAssertEqual(L.strip, CGRect(x: 10, y: 60, width: 356, height: 22)); near(L.rowHeight, 104)
        XCTAssertEqual(L.riff.row.minY, 90); XCTAssertEqual(L.riff.row.maxY, 194); XCTAssertEqual(L.notes.row.minY, 202); XCTAssertEqual(L.notes.row.maxY, 306)
        near(L.riff.xy.height, 72); near(L.riff.roll.height, 58); near(L.riff.jackStrip.height, 46)
        near(L.notes.row.maxY, 316 - 10, "the notes row ends on the content box's bottom")
    }
    /// The lane-card sizes the page produces at the iPad sizes the project tests, and the floors that flag on the back (drawn at the formula's values, never shrunk).
    func testTheFloorsAtEveryLayoutThePageCanProduce() {
        let sizes: [(String, CGSize)] = [("1376×1032 landscape", CGSize(width: 1376, height: 1032)), ("1190×834 landscape", CGSize(width: 1190, height: 834)), ("1176×834 landscape", CGSize(width: 1176, height: 834)),
                                         ("1133×744 landscape (mini)", CGSize(width: 1133, height: 744)), ("1113×683 landscape", CGSize(width: 1113, height: 683)), ("900×600 landscape window", CGSize(width: 900, height: 600)),
                                         ("834×1210 portrait", CGSize(width: 834, height: 1210)), ("744×1133 portrait (mini)", CGSize(width: 744, height: 1133)), ("700×900 portrait window", CGSize(width: 700, height: 900)),
                                         ("300×700 portrait window", CGSize(width: 300, height: 700))]
        var table: [String] = []
        for (name, size) in sizes {
            let p = euclideousPageLayout(size: size)
            let card = p.box
            let L = euclideousCardBackLayout(card: card)
            let flagged = L.floors.map { "\($0.name) \(String(format: "%.1f", Double($0.value)))<\(Int($0.floor))" }.joined(separator: ", ")
            table.append("CARDBACK-LAYOUT \(name): header \(p.headerKind) card \(String(format: "%.1f", Double(card.width)))×\(String(format: "%.1f", Double(card.height))) rowH \(String(format: "%.1f", Double(L.rowHeight))) xy \(String(format: "%.1f", Double(L.riff.xy.height))) roll \(String(format: "%.1f", Double(L.riff.roll.height))) cell \(String(format: "%.1f", Double(L.riff.jackCells[0].width))) floors [\(flagged)]")
            XCTAssertGreaterThan(L.riff.xy.height, 0); XCTAssertGreaterThan(L.riff.roll.height, 0)
            XCTAssertLessThanOrEqual(L.notes.row.maxY, card.height - 10 + 1e-9, "\(name): the back never leaves the card")
            near(L.riff.row.height, L.notes.row.height, "\(name): equal rows")
        }
        print(table.joined(separator: "\n"))
    }

    // MARK: §5.4 / §5.6 the label pill and the invitations

    func testTheLabelPillFrames() {
        let roll = CGRect(x: 110, y: 92, width: 256, height: 57)
        let riff = euclideousCardLabelFrames(roll: roll, part: .riff)
        XCTAssertEqual(riff.pill.origin, CGPoint(x: 115, y: 97), "5 pt in"); near(riff.pill.height, 20)
        near(riff.pill.width, 7 + 9 + 6 + 4 * 9 * 0.72 + 7, "7 pt padding, the 9 × 9 glyph, 6 pt, 'RIFF' at 9 pt heavy 0.12 em")
        XCTAssertEqual(riff.glyph.size, CGSize(width: 9, height: 9)); near(riff.glyph.minX, riff.pill.minX + 7); near(riff.glyph.midY, riff.pill.midY); near(riff.text.minX, riff.glyph.maxX + 6)
        XCTAssertEqual(riff.target.height, 44); near(riff.target.midY, riff.pill.midY); near(riff.target.minX, riff.pill.minX); near(riff.target.width, riff.pill.width)
        let notes = euclideousCardLabelFrames(roll: roll, part: .notes)
        XCTAssertEqual(notes.glyph.size, CGSize(width: 6, height: 12), "NOTES is the 6 × 12 bar"); near(notes.pill.width, 7 + 6 + 6 + 5 * 9 * 0.72 + 7)
        near(EuclideousCardLabelMetrics.radius, 5); XCTAssertEqual(EuclideousCardLabelMetrics.fill, HocketColor(0x131519, 0.82)); near(EuclideousCardLabelMetrics.offAlpha, 0.55)
    }
    func testTheInvitationsAndWhichOneTheRollOffers() {
        XCTAssertEqual(euclideousCardInvitation(part: .riff, partOn: false, laneHasHits: true), .turnOnRiff); XCTAssertEqual(euclideousCardInvitation(part: .notes, partOn: false, laneHasHits: false), .turnOnNotes, "off wins over no hits: one at a time")
        XCTAssertEqual(euclideousCardInvitation(part: .riff, partOn: true, laneHasHits: false), .addHits); XCTAssertNil(euclideousCardInvitation(part: .notes, partOn: true, laneHasHits: true))
        XCTAssertEqual([EuclideousCardInvitation.turnOnRiff, .turnOnNotes, .addHits].map { $0.label }, ["TURN ON RIFF", "TURN ON NOTES", "ADD HITS"])
        let roll = CGRect(x: 110, y: 92, width: 256, height: 57)
        let f = euclideousCardInvitationFrames(roll: roll, .turnOnNotes)
        near(f.pill.height, 28); near(f.pill.midX, roll.midX); near(f.pill.midY, roll.midY); near(f.pill.width, 10 + 9 + 6 + 13 * 8 * 0.7 + 10, "10 pt padding, the 9 × 9 plus, 6 pt, the label at 8 pt heavy 0.1 em")
        XCTAssertEqual(f.target.height, 44); near(f.target.midY, roll.midY); XCTAssertEqual(f.plus.size, CGSize(width: 9, height: 9)); near(f.plus.minX, f.pill.minX + 10); near(f.text.minX, f.plus.maxX + 6)
        near(EuclideousCardInvitationMetrics.radius, 7); near(EuclideousCardInvitationMetrics.fillAlpha, 0.20); near(EuclideousCardInvitationMetrics.plusStroke, 1.6)
    }

    // MARK: §6 XY and OCT

    func testTheXYPadMapsGateAcrossAndVelocityUp() {
        let pad = CGRect(x: 10, y: 92, width: 92, height: 71)
        let d = euclideousCardXYDot(gate: 0.38, velocity: 24, in: pad)
        let back = euclideousCardXYValues(at: d, in: pad)
        near(back.gate, 0.38); XCTAssertEqual(back.velocity, 24, "the dot's position reads back as the same values")
        XCTAssertLessThan(euclideousCardXYDot(gate: 0.2, velocity: 24, in: pad).x, euclideousCardXYDot(gate: 0.8, velocity: 24, in: pad).x, "GATE across")
        XCTAssertLessThan(euclideousCardXYDot(gate: 0.5, velocity: 100, in: pad).y, euclideousCardXYDot(gate: 0.5, velocity: 20, in: pad).y, "VEL up the pad (louder = higher)")
        let extreme = euclideousCardXYValues(at: CGPoint(x: pad.maxX + 50, y: pad.minY - 50), in: pad)
        near(extreme.gate, 0.99, "the far right edge is 99 %, not legato"); XCTAssertEqual(extreme.velocity, 127)
        let low = euclideousCardXYValues(at: CGPoint(x: pad.minX - 50, y: pad.maxY + 50), in: pad)
        near(low.gate, 0.01); XCTAssertEqual(low.velocity, 1)
        let fill = euclideousCardXYFillRect(dot: d, in: pad)
        near(fill.minX, pad.minX); near(fill.minY, d.y); near(fill.maxX, d.x); near(fill.maxY, pad.maxY)
        let cross = euclideousCardXYCrosshair(dot: d, in: pad)
        near(cross.horizontal.width, pad.width); near(cross.horizontal.height, 1); near(cross.horizontal.midY, d.y); near(cross.vertical.height, pad.height); near(cross.vertical.midX, d.x)
        let t = euclideousCardXYTexts(gate: 0.38, velocity: 24)
        XCTAssertEqual(t.vel, "VEL 24"); XCTAssertEqual(t.gate, "38%")
        near(EuclideousCardXYMetrics.dot, 11); near(EuclideousCardXYMetrics.dotRing, 2); near(EuclideousCardXYMetrics.radius, 8); near(EuclideousCardXYMetrics.fillAlpha, 0.22); near(EuclideousCardXYMetrics.crosshairAlpha, 0.60)
    }
    func testOctFramesAndValueText() {
        let oct = CGRect(x: 10, y: 135, width: 92, height: 28)
        let f = euclideousCardOctFrames(oct: oct)
        XCTAssertEqual(f.minusZone, CGRect(x: 10, y: 135, width: 28, height: 28)); XCTAssertEqual(f.plusZone, CGRect(x: 74, y: 135, width: 28, height: 28))
        XCTAssertEqual(f.minusGlyph.size, CGSize(width: 10, height: 10)); near(f.minusGlyph.midX, f.minusZone.midX); near(f.plusGlyph.midY, oct.midY)
        XCTAssertGreaterThan(f.caption.minX, f.minusZone.maxX); XCTAssertLessThan(f.value.maxX, f.plusZone.minX, "'OCT' and the value sit between the zones")
        XCTAssertEqual([euclideousCardOctValueText(1), euclideousCardOctValueText(0), euclideousCardOctValueText(-1)], ["+1", "0", "\u{2212}1"])
        XCTAssertFalse(euclideousCardOctValueIsLaneColour(0)); XCTAssertTrue(euclideousCardOctValueIsLaneColour(2))
        XCTAssertEqual(EuclideousCardOctMetrics.fill, HocketColor(0x22252C)); near(EuclideousCardOctMetrics.height, 28); near(EuclideousCardOctMetrics.radius, 7)
    }

    // MARK: §7 / test 8 the jacks

    func testTheJackLooks() {
        let lane = HocketPalette.lane100(0)
        let on = euclideousJackLook(lane: 0, plugged: true, partOn: true)
        XCTAssertEqual(on.ring, lane); XCTAssertEqual(on.plug, lane); XCTAssertEqual(on.plugCap, HocketColor(0x15161A)); XCTAssertEqual(on.letter, HocketColor(0xF2F4F7))
        XCTAssertEqual(on.cellFill, euclideousCardMix(HocketColor(0x101114), toward: lane, 0.12), "#101114 mixed 12 % toward lane100"); XCTAssertEqual(on.cellFill?.hex, 0x2B1A1C)
        XCTAssertEqual(on.light, HocketColor(lane.hex, 0.30))
        let off = euclideousJackLook(lane: 0, plugged: true, partOn: false)
        XCTAssertEqual(off.ring, lane); XCTAssertEqual(off.plug, HocketColor(lane.hex, 0.45), "the plug disc at 45 %"); XCTAssertEqual(off.plugCap, HocketColor(0x15161A)); XCTAssertEqual(off.letter, HocketColor(0xF2F4F7))
        XCTAssertNil(off.cellFill, "the cell unfilled"); XCTAssertEqual(off.light, HocketColor(0x2A2D34))
        let un = euclideousJackLook(lane: 0, plugged: false, partOn: true)
        XCTAssertEqual(un.ring, HocketColor(0x3A3E47)); XCTAssertNil(un.plug); XCTAssertNil(un.plugCap); XCTAssertEqual(un.letter, HocketColor(0x6E727B)); XCTAssertNil(un.cellFill); XCTAssertEqual(un.light, HocketColor(0x2A2D34))
        XCTAssertEqual(euclideousJackLook(lane: 0, plugged: false, partOn: false), un, "unplugged looks the same whether or not the part is on")
        for l in 1..<4 { XCTAssertEqual(euclideousJackLook(lane: l, plugged: true, partOn: true).ring, HocketPalette.lane100(l), "every lane colour") }
        // the socket artwork's numbers
        typealias J = EuclideousJackMetrics
        near(J.ringWidth, 1.5); near(J.socketRadius, 10.5); near(J.plugRadius, 8.5); near(J.capRadius, 3); XCTAssertEqual(J.socketDisc, HocketColor(0x0B0C0E)); XCTAssertEqual(J.notchColor, HocketColor(0x3A3E47)); near(J.notch.width, 2.5); near(J.notch.height, 2.5)
        XCTAssertEqual(J.pins, [CGPoint(x: 6.4, y: 10.4), CGPoint(x: 17.6, y: 10.4), CGPoint(x: 8, y: 15.2), CGPoint(x: 16, y: 15.2), CGPoint(x: 12, y: 17.2)]); near(J.pinSize, 2.3); XCTAssertEqual(J.pinColor, HocketColor(0x4A4E57))
    }
    func testTheJackActivityDecaysLinearlyOver220Milliseconds() {
        for (ms, amount) in [(0.0, 1.0), (55, 0.75), (110, 0.5), (165, 0.25), (220, 0.0), (300, 0.0)] {
            let a = euclideousJackActivity(sinceNoteOn: ms / 1000)
            near(a.amount, amount, "\(ms) ms"); near(a.glowRadius, CGFloat(10 * amount)); near(a.glowAlpha, 0.9 * amount); near(a.cellMix, 0.12 + 0.16 * amount, "the fill: 12 % → 28 % toward lane100"); near(a.lightMix, amount)
        }
        near(euclideousJackActivity(sinceNoteOn: 0).glowRadius, 10, "a 10 pt glow"); near(euclideousJackActivity(sinceNoteOn: 0).cellMix, 0.28)
        near(euclideousJackActivity(sinceNoteOn: -1).amount, 0, "before any note: quiet")
    }
    func testTheSeamGlowsOnANoteAndFallsBack() {
        let lane = HocketPalette.lane100(2)
        let quiet = euclideousSeamLook(lane: 2, audible: true, sinceNoteOn: 5)
        XCTAssertEqual(quiet.colour, HocketColor(lane.hex, 0.35), "lane100 at 35 % while the part is audible"); near(quiet.glowRadius, 0); near(quiet.glowAlpha, 0)
        XCTAssertEqual(euclideousSeamLook(lane: 2, audible: false, sinceNoteOn: 5).colour, HocketColor(0x262930), "else #262930")
        let hit = euclideousSeamLook(lane: 2, audible: true, sinceNoteOn: 0)
        XCTAssertEqual(hit.colour, lane, "on a note-on: lane100"); near(hit.glowRadius, 6); near(hit.glowAlpha, 0.8)
        let half = euclideousSeamLook(lane: 2, audible: true, sinceNoteOn: 0.110)
        near(half.glowRadius, 3); near(half.glowAlpha, 0.4); XCTAssertEqual(half.colour, euclideousCardMix(HocketColor(lane.hex, 0.35), toward: lane, 0.5))
    }
    func testAJackTapTogglesOneBitOfTheFourBitMask() {
        XCTAssertEqual(euclideousJackToggle(mask: 0b0001, output: 1), 0b0011); XCTAssertEqual(euclideousJackToggle(mask: 0b0011, output: 0), 0b0010); XCTAssertEqual(euclideousJackToggle(mask: 0b0001, output: 0), 0, "no minimum: a part unplugged everywhere is silent")
        XCTAssertEqual(euclideousJackToggle(mask: 0xFF, output: 3), 0b0111, "bits above four are dropped"); XCTAssertEqual(euclideousJackToggle(mask: 0b0101, output: 9), 0b0101)
        XCTAssertTrue(euclideousJackIsPlugged(mask: 0b0100, output: 2)); XCTAssertFalse(euclideousJackIsPlugged(mask: 0b0100, output: 3)); XCTAssertEqual(euclideousJackLetters, ["A", "B", "C", "D"])
    }

    // MARK: §5.3 / test 9 the roll

    func testTheRollSpanIsTwelveSemitonesCenteredOrTheNotesOwnPlusOneEachSide() {
        let small = euclideousRollTargetSpan(pitches: [60, 64, 67])
        near(small.rows, 12, "notes inside 12 semitones give a 12-semitone span"); near((small.lo + small.hi) / 2, (60.0 + 67.0) / 2, "…centred on them"); XCTAssertEqual(small, EuclideousRollSpan(lo: 58, hi: 69))
        let wide = euclideousRollTargetSpan(pitches: [48, 72])
        XCTAssertEqual(wide, EuclideousRollSpan(lo: 47, hi: 73), "a wider set gives its own span plus one semitone each side"); near(wide.rows, 27)
        let exact = euclideousRollTargetSpan(pitches: [60, 69])                  // 10 notes + 2 = 12 rows exactly
        XCTAssertEqual(exact, EuclideousRollSpan(lo: 59, hi: 70))
        let eleven = euclideousRollTargetSpan(pitches: [60, 70])                 // 11 + 2 = 13 rows: its own span
        XCTAssertEqual(eleven, EuclideousRollSpan(lo: 59, hi: 71))
        XCTAssertEqual(euclideousRollTargetSpan(pitches: [60]), EuclideousRollSpan(lo: 55, hi: 66), "one note: 12 rows centred — 5 below, 6 above (the odd extra row goes on top)")
        near(euclideousRollTargetSpan(pitches: []).rows, 12, "no notes: 12 rows around middle C")
    }
    func testTheDrawnSpanGrowsAtOnceAndShrinksOver300Milliseconds() {
        let drawn = EuclideousRollSpan(lo: 58, hi: 69)
        let grown = euclideousRollTargetSpan(pitches: [60, 64, 67, 80])                // 59…81
        let atOnce = euclideousRollDisplaySpan(target: grown, drawn: drawn, shrinkElapsed: 0)
        near(atOnce.hi, 81, "a note outside grows the span at once"); near(atOnce.lo, 58, "the side that did not grow has not moved")
        let target = EuclideousRollSpan(lo: 58, hi: 69)
        let wideDrawn = EuclideousRollSpan(lo: 59, hi: 81)
        near(euclideousRollDisplaySpan(target: target, drawn: wideDrawn, shrinkElapsed: 0).hi, 81, "the notes have just left: still wide")
        near(euclideousRollDisplaySpan(target: target, drawn: wideDrawn, shrinkElapsed: 0.150).hi, 75, "halfway after 150 ms")
        near(euclideousRollDisplaySpan(target: target, drawn: wideDrawn, shrinkElapsed: 0.300).hi, 69, "back to the target after 300 ms")
        near(euclideousRollDisplaySpan(target: target, drawn: wideDrawn, shrinkElapsed: 5).hi, 69)
    }
    func testTheRollRowsAreEqualHeightHighestPitchOnTopWithBlackKeysMarked() {
        let rows = euclideousRollRows(span: EuclideousRollSpan(lo: 58, hi: 69), top: 100, height: 57)
        XCTAssertEqual(rows.count, 12); XCTAssertEqual(rows.first?.pitch, 69); XCTAssertEqual(rows.last?.pitch, 58)
        for r in rows { near(r.height, 57 / 12) }
        near(rows.first!.y, 100); near(rows.last!.y + rows.last!.height, 157)
        XCTAssertEqual(rows.filter { $0.isBlackKey }.map { $0.pitch }, [68, 66, 63, 61, 58], "the black-key rows in 58…69, top to bottom: G♯ F♯ D♯ C♯ A♯")
        XCTAssertTrue(rows.first(where: { $0.pitch == 58 })!.isBlackKey); XCTAssertFalse(rows.first(where: { $0.pitch == 60 })!.isBlackKey)
        XCTAssertEqual(EuclideousRollMetrics.blackKeyRow, HocketColor(0x000000, 0.28))
    }
    func testTheRollScrollsLeftWithTheClockOverTwoBars() {
        let left: CGFloat = 110, width: CGFloat = 256
        near(euclideousRollX(beat: 5.3, nowBeat: 5.3, beatsPerBar: 4, left: left, width: width), 366, "newest at the right edge")
        near(euclideousRollX(beat: 5.3 - 8, nowBeat: 5.3, beatsPerBar: 4, left: left, width: width), 110, "two bars (8 beats) ago at the left edge")
        near(euclideousRollX(beat: 5.3 - 4, nowBeat: 5.3, beatsPerBar: 4, left: left, width: width), 238, "one bar ago in the middle")
        near(euclideousRollX(beat: 5.3 - 6, nowBeat: 5.3, beatsPerBar: 3, left: left, width: width), 110, "the window is 2 bars of the page clock: 6 beats at 3/4")
        let grid = euclideousRollGrid(nowBeat: 5.3, beatsPerBar: 4, left: left, width: width)
        XCTAssertEqual(grid.count, 8, "whole beats −2…5 inside the window"); XCTAssertEqual(grid.filter { $0.isBar }.count, 2, "bar lines at beats 0 and 4")
        for l in grid { near(l.alpha, l.isBar ? 0.09 : 0.04) }
        near(grid.last!.x, euclideousRollX(beat: 5, nowBeat: 5.3, beatsPerBar: 4, left: left, width: width))
        XCTAssertTrue(euclideousRollGrid(nowBeat: 0.2, beatsPerBar: 4, left: left, width: width).allSatisfy { $0.x >= left && $0.x <= left + width })
    }
    func testANotesRectangleRunsFromNoteOnToNoteOffOrTheRightEdge() {
        let roll = CGRect(x: 110, y: 92, width: 256, height: 57)
        let span = EuclideousRollSpan(lo: 58, hi: 69)
        let ended = euclideousRollNoteRect(pitch: 64, onBeat: 4.0, offBeat: 4.5, nowBeat: 5.0, beatsPerBar: 4, span: span, roll: roll)!
        near(ended.minX, euclideousRollX(beat: 4.0, nowBeat: 5.0, beatsPerBar: 4, left: 110, width: 256)); near(ended.maxX, euclideousRollX(beat: 4.5, nowBeat: 5.0, beatsPerBar: 4, left: 110, width: 256))
        near(ended.height, 57 / 12 - 1, "the pitch row's height minus 1")
        let sounding = euclideousRollNoteRect(pitch: 64, onBeat: 4.8, offBeat: nil, nowBeat: 5.0, beatsPerBar: 4, span: span, roll: roll)!
        near(sounding.maxX, 366, "a sounding note runs to the right edge")
        let tiny = euclideousRollNoteRect(pitch: 64, onBeat: 4.0, offBeat: 4.5, nowBeat: 5.0, beatsPerBar: 4, span: EuclideousRollSpan(lo: 40, hi: 80), roll: roll)!
        near(tiny.height, 2.5, "at least 2.5")
        XCTAssertNil(euclideousRollNoteRect(pitch: 90, onBeat: 4.0, offBeat: 4.5, nowBeat: 5.0, beatsPerBar: 4, span: span, roll: roll), "a pitch outside the span is not drawn")
        XCTAssertNil(euclideousRollNoteRect(pitch: 64, onBeat: -5, offBeat: -4, nowBeat: 5.0, beatsPerBar: 4, span: span, roll: roll), "wholly left of the window")
    }
    func testTheNotesLooksFollowVelocity() {
        let lane = HocketPalette.lane100(1)
        let loud = euclideousRollNoteLook(lane: 1, velocity: 127, state: .sounding)
        XCTAssertEqual(loud.fill, HocketColor(lane.hex, 1.0), "s = 0.4 + 0.6 × 1"); near(loud.glowRadius, 12, "4 + 8 × 1"); near(loud.glowAlpha, 0.7)
        let soft = euclideousRollNoteLook(lane: 1, velocity: 64, state: .sounding)
        let s = 0.4 + 0.6 * 64.0 / 127; near(soft.fill!.alpha, s); near(soft.glowRadius, CGFloat(4 + 8 * 64.0 / 127)); near(soft.glowAlpha, 0.7 * s)
        let ended = euclideousRollNoteLook(lane: 1, velocity: 64, state: .ended)
        near(ended.fill!.alpha, 0.6 * s, "an ended note is lane100 at 0.6 × s"); near(ended.glowRadius, 0)
        let silent = euclideousRollNoteLook(lane: 1, velocity: 64, state: .silent)
        XCTAssertNil(silent.fill, "a silent note is hollow"); near(silent.borderWidth, 1.5); XCTAssertEqual(silent.border, HocketColor(lane.hex, 0.55))
        XCTAssertGreaterThan(loud.fill!.alpha, soft.fill!.alpha, "VEL changes the brightness")
    }
    func testTheRollGroundAndPlayhead() {
        let g = euclideousRollGround(lane: 0, laneAudible: true, partOn: true, laneHasHits: true)
        XCTAssertEqual(g, euclideousCardMix(HocketColor(0x131519), toward: HocketPalette.lane100(0), 0.07), "#131519 mixed 7 % toward lane100")
        for (a, p, h) in [(false, true, true), (true, false, true), (true, true, false)] { XCTAssertEqual(euclideousRollGround(lane: 0, laneAudible: a, partOn: p, laneHasHits: h), HocketColor(0x131519)) }
        let roll = CGRect(x: 110, y: 92, width: 256, height: 57)
        let on = euclideousRollPlayhead(lane: 0, audible: true, roll: roll)
        XCTAssertEqual(on.rect, CGRect(x: 364, y: 92, width: 2, height: 57)); XCTAssertEqual(on.colour, HocketColor(HocketPalette.lane100(0).hex, 0.55))
        XCTAssertEqual(euclideousRollPlayhead(lane: 0, audible: false, roll: roll).colour, HocketColor(0xDFE3EA, 0.25))
        XCTAssertEqual(EuclideousRollMetrics.border, HocketColor(0x262930)); near(EuclideousRollMetrics.topRadius, 8); near(EuclideousRollMetrics.noteRadius, 2)
    }
    func testMixingColours() {
        XCTAssertEqual(euclideousCardMix(HocketColor(0x000000), toward: HocketColor(0xFFFFFF), 0.5).hex, 0x808080)
        XCTAssertEqual(euclideousCardMix(HocketColor(0x102030), toward: HocketColor(0x102030), 0.9).hex, 0x102030)
        XCTAssertEqual(euclideousCardMix(HocketColor(0x101114), toward: HocketColor(0xF25959), 0).hex, 0x101114); XCTAssertEqual(euclideousCardMix(HocketColor(0x101114), toward: HocketColor(0xF25959), 1).hex, 0xF25959)
        near(euclideousCardMix(HocketColor(0x000000, 0.2), toward: HocketColor(0xFFFFFF, 1), 0.5).alpha, 0.6)
    }

    // MARK: §11 VoiceOver

    func testTheVoiceOverStrings() {
        typealias AX = EuclideousCardBackAX
        XCTAssertEqual(AX.switchGroup, "Card side"); XCTAssertEqual(AX.segment(.pattern), "Pattern"); XCTAssertEqual(AX.segment(.mix), "Mix")
        XCTAssertEqual(AX.group(lane: 0), "Lane 1 mix"); XCTAssertEqual(AX.group(lane: 3), "Lane 4 mix")
        XCTAssertEqual(AX.partToggle(.riff, on: true), "Riff, on"); XCTAssertEqual(AX.partToggle(.notes, on: false), "Notes, off")
        XCTAssertEqual(AX.xy(.riff, velocity: 24, gate: 0.38), "Riff velocity 24, gate 38%")
        XCTAssertEqual(AX.oct(.riff, value: 0), "Riff octave, 0"); XCTAssertEqual(AX.oct(.notes, value: 1), "Notes octave, plus 1"); XCTAssertEqual(AX.oct(.notes, value: -2), "Notes octave, minus 2")
        XCTAssertEqual(AX.roll(.riff, silent: false), "Riff playing"); XCTAssertEqual(AX.roll(.riff, silent: true), "Riff silent")
        XCTAssertEqual(AX.jack(.riff, output: 0, plugged: true), "Riff to output A, plugged in"); XCTAssertEqual(AX.jack(.notes, output: 3, plugged: false), "Notes to output D, empty")
        XCTAssertEqual(AX.invitation(.turnOnNotes), "Turn on notes"); XCTAssertEqual(AX.invitation(.turnOnRiff), "Turn on riff"); XCTAssertEqual(AX.invitation(.addHits), "Add hits")
        XCTAssertFalse([AX.switchGroup, AX.group(lane: 0), AX.xy(.riff, velocity: 1, gate: 0.5)].contains { $0.contains("'") }, "no straight apostrophes (U+2019 is the house character)")
        // the old MIX pad read differently — kept untouched for the tab until it is retired
        XCTAssertEqual(euclideousMixPadAccessibilityValue(gate: 0.6, velocity: 104), "gate 60 percent, velocity 104")
        XCTAssertEqual(euclideousMixPadAccessibilityLabel(lane: 0, notes: false, off: false), "Lane 1 riff")
    }
}
