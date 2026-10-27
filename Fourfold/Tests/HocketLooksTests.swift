//  HocketLooksTests.swift — HOCKET ferry (2026-10-27) §12 test 13 (the looks), test 14 (the layout), the pop-up's edits and §10's VoiceOver strings.
//  Outputs are CABLES in rules (RR 1 … GN 8); the names are the lane colours (RED, BLUE, AMBER, GREEN — Paul's call, the outputs themselves are letter-named in AUM).

import XCTest

final class HocketLooksTests: XCTestCase {
    private func rule(main: [Int] = [], alt: [Int] = [], _ configure: (inout HocketRule) -> Void = { _ in }) -> HocketRule {
        var r = HocketRule(); r.main = main; r.alt = alt; configure(&r); return r
    }
    private let RR = 1, RN = 2, BR = 3, BN = 4, AR = 5, AN = 6, GR = 7, GN = 8

    // MARK: - test 13 — the header button

    func testTheButtonHasThreeLooks() {
        let off = hocketButtonLook(litRules: 0, open: false)
        XCTAssertEqual(off.fill, HocketColor(0x2A2D34)); XCTAssertEqual(off.text, HocketColor(0x8A909A)); XCTAssertEqual(off.borderWidth, 0)
        XCTAssertEqual(hocketButtonLabel(litRules: 0).word, "HOCKET"); XCTAssertNil(hocketButtonLabel(litRules: 0).count)
        let on = hocketButtonLook(litRules: 2, open: false)
        XCTAssertEqual(on.fill, HocketColor(0xDFE3EA, 0.12)); XCTAssertEqual(on.borderWidth, 1); XCTAssertEqual(on.border, HocketColor(0xDFE3EA)); XCTAssertEqual(on.text, HocketColor(0xF2F4F7))
        XCTAssertEqual(hocketButtonLabel(litRules: 2).count, " \u{00B7} 2"); XCTAssertEqual(hocketButtonCountOpacity, 0.7)
        for lit in [0, 3] {
            let open = hocketButtonLook(litRules: lit, open: true)
            XCTAssertEqual(open.fill, HocketColor(0xDFE3EA)); XCTAssertEqual(open.text, HocketColor(0x0D0F14), "open: ink on the light fill (\(lit) lit)")
        }
        XCTAssertEqual(hocketButtonLabel(litRules: 3).count, " \u{00B7} 3", "the open button keeps the count")
    }
    func testTheButtonsWidthFollowsItsLabelAndTheHeaderReservesTheWidest() {
        XCTAssertEqual(HocketButtonMetrics.width(litRules: 0), 24 + 6 * 10 * 0.68, accuracy: 1e-9)
        XCTAssertEqual(HocketButtonMetrics.width(litRules: 4), 24 + 10 * 10 * 0.68, accuracy: 1e-9)
        XCTAssertEqual(HocketButtonMetrics.reservedWidth, HocketButtonMetrics.width(litRules: 4), "the header reserves the \"HOCKET · 4\" width")
        XCTAssertEqual(HocketButtonMetrics.reservedWidth, 92)
        XCTAssertEqual(HocketButtonMetrics.target, 44); XCTAssertEqual(HocketButtonMetrics.height, 30); XCTAssertEqual(HocketButtonMetrics.radius, 7)
        // the header's utilities group carries it plus the sp8 before the presets button, in every layout
        XCTAssertEqual(euclideousHeaderGroupWidths(compact: false).utilities, 4 * 44 + 8 + 92)
        XCTAssertEqual(euclideousHeaderGroupWidths(compact: true).utilities, 4 * 36 + 8 + 92)
    }

    // MARK: - test 13 — the rule tabs and the on/off button

    func testTabLooksForShowingAndLit() {
        let ink = HocketColor(0x0D0F14), light = HocketColor(0xDFE3EA)
        XCTAssertEqual(hocketTabLook(showing: true, lit: true), HocketTabLook(fill: light, label: ink, dot: .filled(ink)))
        XCTAssertEqual(hocketTabLook(showing: true, lit: false), HocketTabLook(fill: light, label: ink, dot: .ring(ink)))
        XCTAssertEqual(hocketTabLook(showing: false, lit: true), HocketTabLook(fill: HocketColor(0x2A2D34), label: HocketColor(0xAAB0BA), dot: .filled(HocketColor(0xF2F4F7))))
        XCTAssertEqual(hocketTabLook(showing: false, lit: false), HocketTabLook(fill: HocketColor(0x2A2D34), label: HocketColor(0xAAB0BA), dot: .ring(HocketColor(0x8A909A))))
        XCTAssertTrue(rule(main: [RR]).isLit); XCTAssertFalse(rule().isLit, "a rule is lit when it is on and its MAIN group isn't empty")
    }
    func testOnOffLooks() {
        XCTAssertEqual(hocketOnOffLook(on: true), HocketOnOffLook(label: "RULE ON", fill: HocketColor(0xDFE3EA, 0.12), borderWidth: 1, border: HocketColor(0xDFE3EA), text: HocketColor(0xF2F4F7)))
        XCTAssertEqual(hocketOnOffLook(on: false), HocketOnOffLook(label: "RULE OFF", fill: HocketColor(0x2A2D34), borderWidth: 1, border: HocketColor(0x2A2D34), text: HocketColor(0x8A909A)))
        XCTAssertEqual(hocketOffRuleBodyOpacity, 0.42)
    }

    // MARK: - test 13 — the chips and badges

    func testEveryChipLook() {
        let lane = 1, l100 = HocketPalette.lane100(1)
        let inGroup = hocketChipLook(lane: lane, inGroup: true, live: false, takenBy: nil)
        XCTAssertEqual(inGroup.fill, HocketColor(l100.hex, 0.2)); XCTAssertEqual(inGroup.border, l100); XCTAssertEqual(inGroup.text, HocketColor(0xF2F4F7)); XCTAssertEqual(inGroup.glyph, .filled(l100))
        let notIn = hocketChipLook(lane: lane, inGroup: false, live: false, takenBy: nil)
        XCTAssertEqual(notIn.fill, HocketColor(0x2A2D34)); XCTAssertEqual(notIn.border, HocketColor(0x2A2D34)); XCTAssertEqual(notIn.text, HocketColor(0xAAB0BA)); XCTAssertEqual(notIn.glyph, .outline(HocketColor(0xAAB0BA), opacity: 0.45))
        let live = hocketChipLook(lane: lane, inGroup: true, live: true, takenBy: nil)
        XCTAssertEqual(live.fill, HocketColor(l100.hex, 0.42)); XCTAssertEqual(live.border, l100)
        XCTAssertEqual(live.glow.count, 2); XCTAssertEqual(live.glow[0].spread, 1); XCTAssertEqual(live.glow[0].color, l100); XCTAssertEqual(live.glow[1].radius, 14); XCTAssertEqual(live.glow[1].color, HocketColor(l100.hex, 0.6))
        let taken = hocketChipLook(lane: lane, inGroup: false, live: false, takenBy: 2)
        XCTAssertEqual(taken.fill, HocketColor(0x1F2127)); XCTAssertEqual(taken.border, HocketColor(0x1F2127)); XCTAssertEqual(taken.text, HocketColor(0x6E727B))
        XCTAssertEqual(taken.glyph, .outline(HocketColor(0x6E727B), opacity: 0.6)); XCTAssertEqual(taken.tag, "R2"); XCTAssertFalse(taken.responds, "a taken chip doesn't respond")
        XCTAssertEqual(hocketChipLook(lane: lane, inGroup: true, live: true, takenBy: 3).tag, "R3", "taken wins over everything")
        XCTAssertTrue(inGroup.responds && notIn.responds && live.responds)
        for l in 0..<4 { XCTAssertNotEqual(hocketChipLook(lane: l, inGroup: true, live: false, takenBy: nil).border, hocketChipLook(lane: (l + 1) % 4, inGroup: true, live: false, takenBy: nil).border, "each lane its own colour") }
    }
    func testAnOutputInAnOffRuleStillCountsAsTaken() {
        let rules = [rule(main: [RR, BR]) { $0.on = false }, rule(main: [AN])]
        XCTAssertEqual(hocketOutputOwner(cable: RR, rules: rules, excluding: 1), 1, "taken by rule 1 even though it is off")
        XCTAssertNil(hocketOutputOwner(cable: RR, rules: rules, excluding: 0), "an output isn't taken by the rule that holds it")
        XCTAssertEqual(hocketOutputOwner(cable: AN, rules: rules, excluding: 0), 2)
        XCTAssertNil(hocketOutputOwner(cable: GN, rules: rules, excluding: 0))
    }
    func testOrderBadges() {
        XCTAssertNil(hocketOrderBadge(position: 0, groupCount: 1), "a group of one carries no badge")
        XCTAssertNil(hocketOrderBadge(position: nil, groupCount: 3))
        XCTAssertEqual([0, 1, 2].map { hocketOrderBadge(position: $0, groupCount: 3) }, [1, 2, 3], "a group of three: 1-up positions")
        XCTAssertEqual(HocketChipMetrics.badgeDisc, 15); XCTAssertEqual(HocketChipMetrics.badgeRing, 2)
    }

    // MARK: - test 13 — the texts

    func testRouteLinesAndNotes() {
        // none: ALT empty
        let none = rule(main: [RN]) { $0.mode = .pass }
        XCTAssertEqual(hocketRouteLines(none), ["NO ALT OUTPUT: ALT TURNS ARE SILENT."]); XCTAssertNil(hocketRouteNote(none))
        // one affected
        var one = rule(main: [RN], alt: [BN]) { $0.mode = .pass }
        XCTAssertEqual(hocketRouteLines(one), ["RED NOTES \u{2192} BLUE NOTES"])
        XCTAssertEqual(hocketRouteNote(one), "BLUE NOTES DROPS ITS OWN PART WHILE IT CARRIES THE LINE.")
        one.own = .merge
        XCTAssertEqual(hocketRouteNote(one), "BLUE NOTES KEEPS PLAYING ITS OWN PART AS WELL.")
        // three affected (TOGETHER): MAIN i → ALT i mod n
        var three = rule(main: [RN, AN, GN], alt: [BR, BN, AR]) { $0.mode = .pass }
        XCTAssertEqual(hocketRouteLines(three), ["RED NOTES \u{2192} BLUE RIFF", "AMBER NOTES \u{2192} BLUE NOTES", "GREEN NOTES \u{2192} AMBER RIFF"])
        XCTAssertEqual(hocketRouteAffected(three), [BR, BN, AR])
        XCTAssertEqual(hocketRouteNote(three), "BLUE RIFF, BLUE NOTES AND AMBER RIFF DROP THEIR OWN PARTS WHILE THEY CARRY THE LINE.")
        three.own = .merge
        XCTAssertEqual(hocketRouteNote(three), "BLUE RIFF, BLUE NOTES AND AMBER RIFF KEEP PLAYING THEIR OWN PARTS AS WELL.")
        // TOGETHER with fewer ALT outputs than MAIN: i mod n
        let fewer = rule(main: [RN, AN], alt: [BN]) { $0.mode = .pass }
        XCTAssertEqual(hocketRouteLines(fewer), ["RED NOTES \u{2192} BLUE NOTES", "AMBER NOTES \u{2192} BLUE NOTES"]); XCTAssertEqual(hocketRouteAffected(fewer), [BN])
        // ROTATE: the ALT outputs listed from ALT i mod n, IN TURN; every ALT output is a receiver
        let rot = rule(main: [RN, AN], alt: [BR, BN, AR]) { $0.mode = .pass; $0.several = .rotate }
        XCTAssertEqual(hocketRouteLines(rot), ["RED NOTES \u{2192} BLUE RIFF \u{00B7} BLUE NOTES \u{00B7} AMBER RIFF, IN TURN", "AMBER NOTES \u{2192} BLUE NOTES \u{00B7} AMBER RIFF \u{00B7} BLUE RIFF, IN TURN"])
        XCTAssertEqual(hocketRouteAffected(rot), [BR, BN, AR])
        let rotOne = rule(main: [RN], alt: [BN]) { $0.mode = .pass; $0.several = .rotate }
        XCTAssertEqual(hocketRouteLines(rotOne), ["RED NOTES \u{2192} BLUE NOTES"], "with one ALT output, no \", IN TURN\"")
        // every ALT output also passes its own line: the crossing
        let crossing = rule(main: [RN, BN], alt: [BN, RN]) { $0.mode = .pass }
        XCTAssertEqual(hocketRouteAffected(crossing), []); XCTAssertEqual(hocketRouteNote(crossing), "EVERY ALT IS ALSO PASSING ITS OWN LINE, SO REPLACE AND MERGE SOUND THE SAME.")
    }
    func testTheBothGroupsNote() {
        XCTAssertNil(hocketBothGroupsNote(rule(main: [RR], alt: [BR])))
        XCTAssertEqual(hocketBothGroupsNote(rule(main: [RR], alt: [RR, BR])), "RED RIFF IS IN BOTH GROUPS, SO IT ALWAYS PLAYS.")
        XCTAssertEqual(hocketBothGroupsNote(rule(main: [RR, BR], alt: [BR, RR])), "RED RIFF AND BLUE RIFF ARE IN BOTH GROUPS, SO THEY ALWAYS PLAY.")
        XCTAssertEqual(hocketBothGroupsNote(rule(main: [RR, BR, AR], alt: [RR, BR, AR])), "RED RIFF AND BLUE RIFF AND AMBER RIFF ARE IN BOTH GROUPS, SO THEY ALWAYS PLAY.")
        XCTAssertNil(hocketBothGroupsNote(rule(main: [RR], alt: [RR]) { $0.mode = .pass }), "only SWAP PARTS explains a both-groups output")
    }
    func testTheWordsAndCounts() {
        XCTAssertEqual(HocketText.count(1, .hits), "1 HIT"); XCTAssertEqual(HocketText.count(8, .hits), "8 HITS")
        XCTAssertEqual(HocketText.count(1, .steps), "1 STEP"); XCTAssertEqual(HocketText.count(2, .passes), "2 PASSES"); XCTAssertEqual(HocketText.count(1, .passes), "1 PASS")
        XCTAssertEqual(HocketText.count(1, .bars), "1 BAR"); XCTAssertEqual(HocketText.count(4, .bars), "4 BARS")
        XCTAssertEqual(HocketText.cycleCaption(rule(main: [RR]) { $0.mainLen = 3; $0.altLen = 1 }), "3 HITS MAIN \u{00B7} 1 HIT ALT")
        XCTAssertEqual(HocketText.passNote, "ON ALT TURNS, MAIN\u{2019}S NOTES MOVE TO THE ALT OUTPUTS.", "U+2019")
        XCTAssertEqual(HocketText.mainHint(.swap), "HEARD FIRST"); XCTAssertEqual(HocketText.mainHint(.pass), "LINES TO PASS")
        XCTAssertEqual(HocketText.joinedNames(["A", "B", "C"]), "A, B AND C")
        XCTAssertEqual(HocketLaneNames.output(bus: 0), "RED RIFF"); XCTAssertEqual(HocketLaneNames.output(bus: 7), "GREEN NOTES"); XCTAssertEqual(HocketLaneNames.lane, ["RED", "BLUE", "AMBER", "GREEN"])
    }

    // MARK: - the pop-up's edits (each is one undo step through `onEditHocket`)

    func testTappingChipsAppendsAndRemovesAndClosesTheGap() {
        var r = HocketRule()
        hocketToggleOutput(&r, cable: BN, inMain: true); hocketToggleOutput(&r, cable: RR, inMain: true); hocketToggleOutput(&r, cable: GN, inMain: true)
        XCTAssertEqual(r.main, [BN, RR, GN], "the order is the order of tapping")
        r.countOn = 2
        hocketToggleOutput(&r, cable: RR, inMain: true)
        XCTAssertEqual(r.main, [BN, GN], "removed, the gap closed"); XCTAssertEqual(r.countOn, 0, "removing a MAIN output resets COUNT ON to the first MAIN output")
        hocketToggleOutput(&r, cable: AR, inMain: false); hocketToggleOutput(&r, cable: BN, inMain: false)
        XCTAssertEqual(r.alt, [AR, BN], "an output may be in both groups"); hocketToggleOutput(&r, cable: AR, inMain: false); XCTAssertEqual(r.alt, [BN])
    }
    func testStepperRules() {
        var r = rule(main: [RR]) { $0.mainLen = 3; $0.altLen = 1; $0.offset = 3 }
        hocketStepLength(&r, main: false, by: 1); XCTAssertEqual(r.altLen, 2); XCTAssertEqual(r.offset, 3, "OFFSET mod the new cycle (5)")
        hocketStepLength(&r, main: true, by: -2); XCTAssertEqual(r.mainLen, 1); XCTAssertEqual(r.offset, 0, "3 mod (1+2) = 0")
        hocketStepLength(&r, main: true, by: -1); XCTAssertEqual(r.mainLen, 1, "stops at 1")
        for _ in 0..<20 { hocketStepLength(&r, main: false, by: 1) }; XCTAssertEqual(r.altLen, 8, "stops at 8")
        r.offset = 0
        hocketStepOffset(&r, by: -1); XCTAssertEqual(r.offset, 8, "OFFSET wraps below 0 to L − 1 (L = 9)"); hocketStepOffset(&r, by: 1); XCTAssertEqual(r.offset, 0, "…and wraps past L − 1")
        var c = rule(main: [RR, BR, AR]); hocketStepCountOn(&c, by: -1); XCTAssertEqual(c.countOn, 2, "COUNT ON wraps through MAIN in group order"); hocketStepCountOn(&c, by: 1); XCTAssertEqual(c.countOn, 0)
        var empty = HocketRule(); hocketStepCountOn(&empty, by: 1); XCTAssertEqual(empty.countOn, 0)
    }
    func testAddingAndDeletingRules() {
        var rs = [HocketRule()]
        XCTAssertEqual(hocketAddRule(&rs), 1); XCTAssertEqual(hocketAddRule(&rs), 2); XCTAssertEqual(hocketAddRule(&rs), 3); XCTAssertNil(hocketAddRule(&rs), "no fifth rule"); XCTAssertEqual(rs.count, 4)
        rs[1].main = [RR]; rs[2].main = [BR]
        XCTAssertEqual(hocketDeleteRule(&rs, at: 2), 1, "deleting R3 shows the rule before it"); XCTAssertEqual(rs.count, 3); XCTAssertEqual(rs[2], HocketRule(), "later rules renumber")
        XCTAssertEqual(hocketDeleteRule(&rs, at: 0), 0, "deleting R1 shows R1")
        rs = [rule(main: [RR])]
        XCTAssertEqual(hocketDeleteRule(&rs, at: 0), 0); XCTAssertEqual(rs, [HocketRule()], "deleting the only rule leaves one empty rule (5.3)")
    }

    // MARK: - test 14 — the layout

    private func playingRule() -> HocketRule { rule(main: [RN, AN], alt: [BN, GN]) { $0.mode = .pass; $0.unit = .hits; $0.mainLen = 3; $0.altLen = 1 } }
    func testTheFramesAtWidth420() {
        let f = hocketPopupFrames(width: 420, ruleCount: 2, rule: playingRule())
        XCTAssertEqual(f.width, 420); XCTAssertEqual(f.contentWidth, 392)
        // header row
        XCTAssertEqual(f.closeTarget, CGRect(x: 392 - 44, y: 0, width: 44, height: 44)); XCTAssertEqual(f.closePlate.size, CGSize(width: 30, height: 30)); XCTAssertEqual(f.closePlate.midX, f.closeTarget.midX); XCTAssertEqual(f.closeCross.size, CGSize(width: 10, height: 10))
        // rule row: the line is 12 below the 14-pt gap after the header; tabs 40 tall, ≥ 48 wide, 4 apart; the add button 44 × 40; on/off 40 tall
        XCTAssertEqual(f.ruleLine.minY, 44 + 14 + 12); XCTAssertEqual(f.ruleLine.height, 1); XCTAssertEqual(f.ruleLine.width, 392)
        XCTAssertEqual(f.tabs.count, 2); XCTAssertTrue(f.tabs.allSatisfy { $0.height == 40 && $0.width >= 48 }); XCTAssertEqual(f.tabs[1].minX - f.tabs[0].maxX, 4)
        XCTAssertEqual(f.add?.size, CGSize(width: 44, height: 40)); XCTAssertEqual(f.add!.minX - f.tabs[1].maxX, 4)
        XCTAssertEqual(f.onOff.height, 40); XCTAssertEqual(f.onOff.maxX, 392); XCTAssertFalse(f.ruleRowWraps); XCTAssertEqual(f.onOff.minY, f.tabs[0].minY)
        XCTAssertLessThanOrEqual(f.add!.maxX + 4, f.onOff.minX, "the on/off button clears the add button")
        // mode: 3 inset, two equal 34-tall segments 3 apart
        XCTAssertEqual(f.mode.height, 40); XCTAssertEqual(f.modeSegments.map { $0.height }, [34, 34]); XCTAssertEqual(f.modeSegments[0].width, f.modeSegments[1].width); XCTAssertEqual(f.modeSegments[1].minX - f.modeSegments[0].maxX, 3)
        // grid: label 44, 6, four equal 44-tall chips 4 apart; two rows 4 apart
        let chipW: CGFloat = (392 - 44 - 6 - 12) / 4
        XCTAssertEqual(f.mainGridLabels[0].width, 44); XCTAssertEqual(f.mainChips[0][0].width, chipW, accuracy: 1e-9); XCTAssertEqual(f.mainChips[0][0].minX, 50)
        XCTAssertEqual(f.mainChips[0][1].minX - f.mainChips[0][0].maxX, 4); XCTAssertEqual(f.mainChips[1][0].minY - f.mainChips[0][0].maxY, 4); XCTAssertTrue(f.mainChips.joined().allSatisfy { $0.height == 44 })
        XCTAssertEqual(f.mainHeader.height, 18); XCTAssertEqual(f.mainBar.size, CGSize(width: 3, height: 14))
        XCTAssertNil(f.mainEmptyHint, "MAIN isn't empty")
        // SWAP EVERY: unit container 3 inset, 30-tall segments 3 apart; three equal 52-tall steppers 4 apart; COUNT ON 44 tall; the cycle strip's cells 28 tall 3 apart
        XCTAssertEqual(f.unit.height, 36); XCTAssertEqual(f.unitSegments.map { $0.height }, [30, 30, 30, 30]); XCTAssertEqual(f.unitSegments[1].minX - f.unitSegments[0].maxX, 3)
        XCTAssertEqual(f.steppers.map { $0.height }, [52, 52, 52]); XCTAssertEqual(f.steppers[0].width, (392 - 8) / 3, accuracy: 1e-9); XCTAssertEqual(f.steppers[1].minX - f.steppers[0].maxX, 4)
        XCTAssertEqual(f.countOn.height, 44); XCTAssertEqual(f.countOnZones.map { $0.width }, [40, 40])
        XCTAssertEqual(f.cycleCells.count, 4); XCTAssertTrue(f.cycleCells.allSatisfy { $0.height == 28 }); XCTAssertEqual(f.cycleCells[1].minX - f.cycleCells[0].maxX, 3)
        XCTAssertEqual(f.cycleCells.last!.maxX, 392, accuracy: 1e-9)
        // ALT: the header is ≥ 30 tall with the several-alts control at the trailing edge (26-tall segments, 2 inset)
        XCTAssertGreaterThanOrEqual(f.altHeader.height, 30); XCTAssertEqual(f.several.maxX, 392); XCTAssertEqual(f.severalSegments.map { $0.height }, [26, 26]); XCTAssertEqual(f.several.height, 30)
        // ROUTES: PASS THE LINE with MAIN: a well with 12 leading, 8 trailing, 8 top and 10 bottom; one line per MAIN output
        let routes = try! XCTUnwrap(f.routes)
        XCTAssertEqual(f.routeLines.count, 2); XCTAssertEqual(f.routesHeader!.minX, 12); XCTAssertEqual(f.routesHeader!.maxX, 392 - 8, accuracy: 1e-9); XCTAssertEqual(f.routesHeader!.minY - routes.minY, 8)
        XCTAssertEqual(routes.maxY - (f.routesNote?.maxY ?? f.routeLines.last!.maxY), 10, accuracy: 1e-9)
        // the footer is last; the sheet is padding + fixed + 14 + body + padding tall
        XCTAssertEqual(f.footer.maxY, f.bodyHeight); XCTAssertEqual(f.totalHeight, 14 + f.fixedHeight + 14 + f.bodyHeight + 14)
        XCTAssertTrue(f.truncations.isEmpty, "nothing truncates at 420: \(f.truncations)")
    }
    func testASwapRuleHasNoRoutesAndAnEmptyMainShowsTheHint() {
        let swap = hocketPopupFrames(width: 420, ruleCount: 1, rule: rule(main: [RR], alt: [BR]))
        XCTAssertNil(swap.routes); XCTAssertNil(swap.routesNote); XCTAssertNil(swap.mainEmptyHint)
        let empty = hocketPopupFrames(width: 420, ruleCount: 1, rule: HocketRule())
        XCTAssertNotNil(empty.mainEmptyHint, "PICK AT LEAST ONE MAIN OUTPUT."); XCTAssertNil(empty.routes, "no ROUTES while MAIN is empty")
        XCTAssertGreaterThan(empty.mainEmptyHint!.minY, empty.mainChips[1][0].maxY)
        let both = hocketPopupFrames(width: 420, ruleCount: 1, rule: rule(main: [RR], alt: [RR, BR]))
        XCTAssertNotNil(both.bothGroupsNote); XCTAssertGreaterThan(both.bothGroupsNote!.minY, both.altChips[1][0].maxY)
        XCTAssertEqual(hocketPopupFrames(width: 420, ruleCount: 4, rule: HocketRule()).add == nil, true, "four rules: no add button")
        XCTAssertEqual(hocketPopupFrames(width: 420, ruleCount: 3, rule: HocketRule()).tabs.count, 3)
    }
    func testNoFrameLeavesTheCardAndEveryTouchTargetIsAtLeast44TallWithoutOverlap() {
        let cases: [(CGFloat, Int, HocketRule)] = [(420, 2, playingRule()), (420, 4, rule(main: [RR], alt: [RR, BR])), (HocketPopupMetrics.narrowestContainer, 1, playingRule()), (HocketPopupMetrics.narrowestContainer, 4, HocketRule())]
        for (w, rc, r) in cases {
            let f = hocketPopupFrames(width: w, ruleCount: rc, rule: r)
            let ctx = "width \(w), \(rc) rules"
            let fixed = [f.closeTarget] + f.tabs + (f.add.map { [$0] } ?? []) + [f.onOff]
            let body = f.modeSegments + f.mainChips.flatMap { $0 } + f.unitSegments + f.steppers + [f.countOn] + f.severalSegments + f.altChips.flatMap { $0 } + (f.routesControl.map { [$0] } ?? [])
            for r in fixed + body {
                XCTAssertGreaterThanOrEqual(r.minX, -1e-9, ctx); XCTAssertLessThanOrEqual(r.maxX, f.contentWidth + 1e-9, "\(ctx): \(r) leaves the card"); XCTAssertGreaterThan(r.width, 0); XCTAssertGreaterThan(r.height, 0)
            }
            func expanded(_ r: CGRect) -> CGRect { r.height >= 44 ? r : CGRect(x: r.minX, y: r.midY - 22, width: r.width, height: 44) }
            // §4.11: a target at least 44 tall extends into the spacing around it without overlapping another
            for group in [fixed.filter { !$0.equalTo(f.closeTarget) }, body] {
                let ex = group.map(expanded)
                for i in ex.indices { for j in ex.indices where j > i {
                    let inter = ex[i].intersection(ex[j])
                    XCTAssertTrue(inter.isNull || inter.width < 1e-6 || inter.height < 1e-6 || (group[i].contains(group[j]) || group[j].contains(group[i])), "\(ctx): targets \(group[i]) and \(group[j]) overlap when expanded to 44")
                } }
            }
        }
    }
    func testAtTheNarrowestContainerTheFramesStillHoldAndTheTruncationsAreNamed() {
        let w = HocketPopupMetrics.width(containerW: HocketPopupMetrics.narrowestContainer)
        XCTAssertEqual(w, 300)
        let f = hocketPopupFrames(width: w, ruleCount: 1, rule: playingRule())
        XCTAssertEqual(f.contentWidth, 272); XCTAssertEqual(f.mainChips[0][0].width, (272 - 44 - 6 - 12) / 4, accuracy: 1e-9)
        XCTAssertTrue(f.truncations.contains("lane names on the output chips"), "AMBER no longer fits a 52.5-wide chip: \(f.truncations)")
        XCTAssertTrue(f.truncations.contains("stepper values"))
        XCTAssertEqual(f.steppers[0].width, (272 - 8) / 3, accuracy: 1e-9)
        // four rules and the on/off button no longer fit one line: it wraps under the tabs, and nothing overlaps
        let four = hocketPopupFrames(width: w, ruleCount: 4, rule: HocketRule())
        XCTAssertTrue(four.ruleRowWraps); XCTAssertGreaterThanOrEqual(four.onOff.minY, four.tabs[0].maxY + 7)
        XCTAssertNil(four.add)
        XCTAssertLessThanOrEqual(four.tabs.last!.maxX, 272)
        // the width follows the settings sheet's container: 420 at most, the container itself below that
        XCTAssertEqual(HocketPopupMetrics.width(containerW: 1158), 420); XCTAssertEqual(HocketPopupMetrics.width(containerW: 343), 343); XCTAssertEqual(HocketPopupMetrics.width(containerW: 420), 420)
    }
    func testTheSheetGrowsWithItsContentOnlyAsFarAsTheSettingsSheetMay() {
        let small = hocketPopupFrames(width: 420, ruleCount: 1, rule: HocketRule()), big = hocketPopupFrames(width: 420, ruleCount: 1, rule: playingRule())
        XCTAssertGreaterThan(big.totalHeight, small.totalHeight, "ROUTES add height")
        XCTAssertGreaterThan(big.bodyHeight, 0); XCTAssertEqual(big.fixedHeight, small.fixedHeight, "the header and rule row never change height")
    }

    // MARK: - §10 VoiceOver

    func testVoiceOverStrings() {
        XCTAssertEqual(HocketAX.buttonLabel, "Hocket"); XCTAssertEqual(HocketAX.buttonHint, "Double-tap to open")
        XCTAssertEqual(HocketAX.buttonValue(litRules: 0), "off"); XCTAssertEqual(HocketAX.buttonValue(litRules: 1), "1 rule on"); XCTAssertEqual(HocketAX.buttonValue(litRules: 3), "3 rules on")
        XCTAssertEqual(HocketAX.tab(rule: 1, lit: true), "Rule 1, on"); XCTAssertEqual(HocketAX.tab(rule: 2, lit: false), "Rule 2, off")
        XCTAssertEqual(HocketAX.addLabel, "Add a rule"); XCTAssertEqual(HocketAX.deleteAction, "Delete rule"); XCTAssertEqual(HocketAX.closeLabel, "Close"); XCTAssertEqual(HocketAX.popupLabel, "Hocket")
        XCTAssertEqual(HocketAX.modeName(.swap), "Swap parts"); XCTAssertEqual(HocketAX.modeName(.pass), "Pass the line")
        XCTAssertEqual(HocketAX.unitName(.hits), "Hits"); XCTAssertEqual(HocketAX.unitName(.passes), "Passes")
        XCTAssertEqual(HocketAX.chip(group: "Main", cable: RR, inGroup: true, position: 0, groupCount: 1, takenBy: nil), "Main: red riff, on")
        XCTAssertEqual(HocketAX.chip(group: "Main", cable: RR, inGroup: false, position: nil, groupCount: 1, takenBy: nil), "Main: red riff, off")
        XCTAssertEqual(HocketAX.chip(group: "Alt", cable: BN, inGroup: true, position: 1, groupCount: 2, takenBy: nil), "Alt: blue notes, on, position 2")
        XCTAssertEqual(HocketAX.chip(group: "Main", cable: RR, inGroup: false, position: nil, groupCount: 0, takenBy: 2), "Main: red riff, used by rule 2")
        XCTAssertEqual(HocketAX.stepperValue(3, .hits), "3 hits"); XCTAssertEqual(HocketAX.stepperValue(1, .hits), "1 hit")
        XCTAssertEqual(HocketAX.cycle(rule(main: [RR]) { $0.mainLen = 3; $0.altLen = 1 }), "Cycle: 3 main, 1 alt, offset 0")
        XCTAssertNil(HocketAX.partState(HocketPartView()))
        XCTAssertEqual(HocketAX.partState(HocketPartView(play: .resting, carrying: -1)), "resting")
        XCTAssertEqual(HocketAX.partState(HocketPartView(play: .away(bus: 2), carrying: -1)), "away on the blue lane")
        XCTAssertEqual(HocketAX.partState(HocketPartView(play: .playing, carrying: 0)), "carrying the red lane\u{2019}s line")
        XCTAssertEqual(HocketAX.partState(HocketPartView(play: .away(bus: 3), carrying: 1)), "away on the blue lane, carrying the red lane\u{2019}s line", "both for a crossing")
    }

    /// TOGETHER with fewer MAIN than ALT outputs shares the lines (Paul, 2026-10-27): ROUTES names every receiver, and every ALT output counts as affected.
    func testTheRouteTextNamesEveryOutputAFannedOutLineReaches() {
        var r = HocketRule(); r.mode = .pass; r.main = [1]; r.alt = [3, 4]; r.several = .together
        XCTAssertEqual(hocketRouteLines(r), ["RED RIFF \u{2192} BLUE RIFF AND BLUE NOTES"])
        XCTAssertEqual(hocketRouteAffected(r), [3, 4])
        r.main = [1, 5]; r.alt = [3, 4, 7]                                           // 2 MAIN, 3 ALT: MAIN 0 → ALT 0 and 2, MAIN 1 → ALT 1
        XCTAssertEqual(hocketRouteLines(r), ["RED RIFF \u{2192} BLUE RIFF AND GREEN RIFF", "AMBER RIFF \u{2192} BLUE NOTES"])
        r.several = .rotate; r.main = [1]; r.alt = [3, 4]
        XCTAssertEqual(hocketRouteLines(r), ["RED RIFF \u{2192} BLUE RIFF \u{00B7} BLUE NOTES, IN TURN"], "ROTATE keeps its own wording: one at a time")
    }
}
