//  ClarityPassTests.swift
//  CLARITY PASS ferry (2026-10-23): "beat-shaded step columns, tab headers that summarise, and MIX pads grouped by lane". The pure surface (spec §5/§6): the beat groups and the strip's even columns (§1), the tab glyphs and
//  strings (§2/§4), the MIX lane panels and pad readouts (§3). Painting is device-owed; every decision it draws is asserted here.

import XCTest

final class ClarityPassTests: XCTestCase {

    private let landscapeRef = CGSize(width: 1190, height: 726)
    private let portraitRef = CGSize(width: 814, height: 1102)

    private func lane(listen: (inout EuclidLine) -> Void) -> EuclidLine { var l = EuclidLine(); listen(&l); return l }

    // MARK: 1. beat groups — the size (5.1) and the A/B tone of each step (5.2)

    func testGroupSizeFollowsTheDivisionThreeForTripletsFourOtherwise() {
        XCTAssertEqual(euclidStepGroupSize(forRate: .r1_16), 4)
        XCTAssertEqual(euclidStepGroupSize(forRate: .r1_8d), 4, "dotted is straight for grouping")
        XCTAssertEqual(euclidStepGroupSize(forRate: .r1_8t), 3)
        XCTAssertEqual(euclidStepGroupSize(forRate: .r1_32), 4)
        for r in ArpRate.allCases { XCTAssertEqual(euclidStepGroupSize(forRate: r), r.rawValue.hasSuffix("T") ? 3 : 4, "\(r.rawValue)") }
    }
    private func tones(_ n: Int, _ size: Int) -> String {
        (0..<n).map { euclideousStepGroupTone(step: $0, groupSize: size) == .a ? "A" : "B" }.joined()
    }
    func testGroupsAlternateFromStepOneAndAShortLastGroupIsJustShort() {
        XCTAssertEqual(tones(16, 4), "AAAABBBBAAAABBBB")
        XCTAssertEqual(tones(7, 4), "AAAABBB")
        XCTAssertEqual(tones(12, 3), "AAABBBAAABBB")
        XCTAssertEqual(tones(8, 4), "AAAABBBB"); XCTAssertEqual(tones(2, 4), "AA", "a lane shorter than one group is all A")
    }

    // MARK: 2. the strip's columns — even, no group gaps (1.1)

    func testEveryColumnIsTwoPointsFromTheNextEvenlyAndTheFrameIsUnchanged() {
        for n in 2...16 {
            let g = euclidEvenBoxGeometry(n: n, g: 4, usableWidth: 260.67)
            XCTAssertEqual(g.xs.count, n)
            for i in 1..<n { XCTAssertEqual(g.xs[i] - g.xs[i - 1], g.stepW + 2, accuracy: 1e-9, "n \(n) step \(i): one column + the 2 pt within-group gap, everywhere") }
            XCTAssertEqual(g.xs[0], 0)
            XCTAssertEqual(g.xs[n - 1] + g.stepW, 260.67, accuracy: 1e-9, "the overall frame does not change")
        }
    }
    func testColumnWidthsAtTheReferenceStripAt8And16StepsAgainstTheGroupedGeometry() {
        // landscape reference: the lane card is `box.width` wide, 10 pt inset each side, then the 44 play button + 6 and the 6 + 44 solo button before / after the strip
        let box = euclideousPageLayout(size: landscapeRef).box
        let strip = EuclideousLaneCardMetrics.innerWidth(cardWidth: box.width) - 50 - 6 - 44
        XCTAssertEqual(strip, 260.67, accuracy: 0.01)
        let g16 = euclidEvenBoxGeometry(n: 16, g: 4, usableWidth: strip), g8 = euclidEvenBoxGeometry(n: 8, g: 4, usableWidth: strip)
        XCTAssertEqual(g16.stepW, (strip - 30) / 16, accuracy: 1e-9); XCTAssertEqual(g16.stepW, 14.42, accuracy: 0.01)
        XCTAssertEqual(g8.stepW, (strip - 14) / 8, accuracy: 1e-9); XCTAssertEqual(g8.stepW, 30.83, accuracy: 0.01)
        XCTAssertEqual(euclidGroupedBoxGeometry(n: 16, g: 4, usableWidth: strip).stepW, 13.48, accuracy: 0.01, "before: 3 × 7 pt between groups")
        XCTAssertEqual(euclidGroupedBoxGeometry(n: 8, g: 4, usableWidth: strip).stepW, 30.21, accuracy: 0.01)
        XCTAssertGreaterThan(g16.stepW, euclidGroupedBoxGeometry(n: 16, g: 4, usableWidth: strip).stepW, "the freed width is shared across the columns")
    }
    func testTheLeftoverRuleFollowsTheEvenColumnsAndOnlyAShortLastGroupHasOne() {
        XCTAssertNil(euclidEvenBoxGeometry(n: 16, g: 4, usableWidth: 260).ruleX); XCTAssertNil(euclidEvenBoxGeometry(n: 12, g: 3, usableWidth: 260).ruleW)
        let g = euclidEvenBoxGeometry(n: 7, g: 4, usableWidth: 260)
        XCTAssertEqual(g.ruleX!, g.xs[4], accuracy: 1e-9, "7 steps in fours: steps 5-7 are the short group"); XCTAssertEqual(g.ruleX! + g.ruleW!, 260, accuracy: 1e-9)
        let whole = euclidEvenBoxGeometry(n: 2, g: 3, usableWidth: 100)
        XCTAssertEqual(whole.ruleX!, 0); XCTAssertEqual(whole.ruleW!, 100, accuracy: 1e-9, "fewer steps than one group: the whole row")
        XCTAssertTrue(euclidEvenBoxGeometry(n: 0, g: 4, usableWidth: 100).xs.isEmpty)
    }
    func testThePlayheadStillGlidesOverTheEvenColumnsAndSlidesOffTheEndByOneColumnAndTheGap() {
        let g = euclidEvenBoxGeometry(n: 8, g: 4, usableWidth: 226)
        let overTheMiddle = euclideousStripPlayhead(raw: 3.5, n: 8, dir: .fwd, xs: g.xs, columnW: g.stepW)
        XCTAssertEqual(overTheMiddle.x, (g.xs[3] + g.xs[4]) / 2, accuracy: 1e-9)
        XCTAssertEqual(g.xs[4] - g.xs[3], g.xs[3] - g.xs[2], accuracy: 1e-9, "no wider step across the old group boundary")
        let off = euclideousStripPlayhead(raw: 7.999, n: 8, dir: .fwd, xs: g.xs, columnW: g.stepW)
        XCTAssertEqual(off.x, g.xs[7] + (g.stepW + EuclideousStripMetrics.slideGap) * 0.999, accuracy: 0.01)
    }

    // MARK: 3. what a column is filled with (1.3)

    func testRestHitAndGapLooksPerGroup() {
        typealias M = EuclideousStripMetrics
        let restA = euclideousStripColumnLook(kind: .rhythmRest, tone: .a), restB = euclideousStripColumnLook(kind: .rhythmRest, tone: .b)
        XCTAssertEqual(restA.fill, .solid(hex: 0x41454F)); XCTAssertEqual(restB.fill, .solid(hex: 0x30333A))
        XCTAssertEqual(restA.ringAlpha, 0); XCTAssertFalse(restA.floorBar, "a rest is solid, present and unmarked — never dashed")
        let hitA = euclideousStripColumnLook(kind: .hit, tone: .a), hitB = euclideousStripColumnLook(kind: .hit, tone: .b)
        XCTAssertEqual(hitA.fill, .lane(alpha: 0.42)); XCTAssertEqual(hitB.fill, .lane(alpha: 0.30))
        XCTAssertEqual(hitA.ringAlpha, 0, "the readability pass's 70 % border is gone"); XCTAssertTrue(hitA.floorBar); XCTAssertTrue(hitB.floorBar)
        for tone in [EuclideousStepGroupTone.a, .b] {
            let gap = euclideousStripColumnLook(kind: .gap, tone: tone), rest = euclideousStripColumnLook(kind: .rhythmRest, tone: tone)
            XCTAssertEqual(gap.fill, rest.fill, "a gap is its group's rest fill …")
            XCTAssertEqual(gap.ringAlpha, 0.45); XCTAssertEqual(gap.ringWidth, 1, "… plus a 1 pt ring at 45 %"); XCTAssertFalse(gap.floorBar)
        }
        XCTAssertTrue(euclideousStripDrawsAsHit(.gap) && euclideousStripDrawsAsHit(.hit) && !euclideousStripDrawsAsHit(.rhythmRest), "chips and keys still follow the rhythm hitting")
        XCTAssertEqual(M.columnGap, M.slideGap, "the playhead's slide past the last column keeps matching the column gap")
    }

    // MARK: 4. the tab glyphs (5.3)

    func testRiffAndNotesGlyphsFillInTheirOwnLanesColourOnlyWhileTheLayerIsOn() {
        var l = EuclidLine()
        l.riffOn = true; l.litNotes = 0; l.topLit = false; l.top2Lit = false
        XCTAssertEqual(euclideousTabGlyph(tab: .riff, line: l, lane: 2), EuclideousTabGlyph(shape: .square, on: true, fill: .lane(2)))
        XCTAssertEqual(euclideousTabGlyph(tab: .notes, line: l, lane: 2), EuclideousTabGlyph(shape: .bar, on: false, fill: .lane(2)), "NOTES with nothing selected is off")
        l.litNotes = 0b1
        XCTAssertTrue(euclideousTabGlyph(tab: .notes, line: l, lane: 2).on)
        l.notesOn = false
        XCTAssertFalse(euclideousTabGlyph(tab: .notes, line: l, lane: 2).on, "a note selected but the switch off is off")
        l.riffOn = false
        XCTAssertFalse(euclideousTabGlyph(tab: .riff, line: l, lane: 2).on)
        XCTAssertEqual(euclideousTabGlyph(tab: .rhythm, line: l, lane: 0).shape, .none, "RHYTHM has no glyph")
        // the glyph and the MIX pad read ONE definition of on/off
        for riff in [true, false] { for notes in [true, false] {
            var m = EuclidLine(); m.riffOn = riff; m.litNotes = 0b1; m.notesOn = notes
            XCTAssertEqual(euclideousTabGlyph(tab: .riff, line: m, lane: 0).on, !euclideousMixLayerIsOff(m, notes: false))
            XCTAssertEqual(euclideousTabGlyph(tab: .notes, line: m, lane: 0).on, !euclideousMixLayerIsOff(m, notes: true))
        } }
    }
    func testListenGlyphIsTheSourceLanesColourAndOffWithNoSource() {
        // lane 1 (index 0) FOLLOWing lane 2 (index 1): on, in lane 2's colour
        let follow = lane { $0.listenRhythmMode = .follow; $0.listenRhythmPartner = 1 }
        XCTAssertEqual(euclideousTabGlyph(tab: .listen, line: follow, lane: 0), EuclideousTabGlyph(shape: .circle, on: true, fill: .lane(1)))
        // nothing lit: off
        XCTAssertFalse(euclideousTabGlyph(tab: .listen, line: EuclidLine(), lane: 0).on)
        // a mode lit with no stored partner (an old / hand-made document): no source ⇒ off, though today's dot would have filled
        let none = lane { $0.listenRhythmMode = .with }
        XCTAssertFalse(euclideousTabGlyph(tab: .listen, line: none, lane: 0).on)
        XCTAssertEqual(euclideousListenSource(none, lane: 0), .none)
        // a partner that is the lane itself, or out of range, is no source either
        XCTAssertEqual(euclideousListenSource(lane { $0.listenLevelMode = .duck; $0.listenLevelPartner = 0 }, lane: 0), .none)
        XCTAssertEqual(euclideousListenSource(lane { $0.listenLevelMode = .duck; $0.listenLevelPartner = 7 }, lane: 0), .none)
    }
    func testListenTakesTheFirstLitRowInTabOrderAndAnyIsTheQuarteredCircle() {
        // RHYTHM beats PITCH beats LEVEL
        let all = lane { $0.listenRhythmMode = .gaps; $0.listenRhythmPartner = 3; $0.listenPitchMode = .shadow; $0.listenPitchPartner = 2; $0.listenLevelMode = .accent; $0.listenLevelPartner = 1 }
        XCTAssertEqual(euclideousListenSource(all, lane: 0), .lane(3))
        let pitchLevel = lane { $0.listenPitchMode = .shadow; $0.listenPitchPartner = 2; $0.listenLevelMode = .accent; $0.listenLevelPartner = 1 }
        XCTAssertEqual(euclideousListenSource(pitchLevel, lane: 0), .lane(2))
        let levelOnly = lane { $0.listenLevelMode = .duck; $0.listenLevelPartner = 2 }
        XCTAssertEqual(euclideousListenSource(levelOnly, lane: 0), .lane(2))
        // a row with no valid partner is skipped: the next lit row decides
        let skip = lane { $0.listenRhythmMode = .with; $0.listenLevelMode = .duck; $0.listenLevelPartner = 3 }
        XCTAssertEqual(euclideousListenSource(skip, lane: 0), .lane(3))
        // AVOID with ANY: any lane — the four-colour circle
        let any = lane { $0.listenPitchMode = .avoid; $0.listenPitchPartnerAny = true }
        XCTAssertEqual(euclideousListenSource(any, lane: 1), .any)
        XCTAssertEqual(euclideousTabGlyph(tab: .listen, line: any, lane: 1), EuclideousTabGlyph(shape: .circle, on: true, fill: .anyLane))
        // ANY only counts under AVOID (the stored flag is ignored under SHADOW) — that row then needs its specific partner
        let shadow = lane { $0.listenPitchMode = .shadow; $0.listenPitchPartnerAny = true; $0.listenPitchPartner = 3 }
        XCTAssertEqual(euclideousListenSource(shadow, lane: 0), .lane(3))
        // a RHYTHM row ahead of an ANY row wins
        let rhythmThenAny = lane { $0.listenRhythmMode = .follow; $0.listenRhythmPartner = 2; $0.listenPitchMode = .avoid; $0.listenPitchPartnerAny = true }
        XCTAssertEqual(euclideousListenSource(rhythmThenAny, lane: 0), .lane(2))
    }

    // MARK: 5. the RHYTHM count and VoiceOver (2.3, 4.1)

    func testRhythmTabCountTracksHitsAndSteps() {
        var l = EuclidLine(); l.pulses = 5; l.steps = 16
        XCTAssertEqual(euclideousRhythmTabCount(l), "5/16")
        l.pulses = 0; l.steps = 8
        XCTAssertEqual(euclideousRhythmTabCount(l), "0/8")
        euclideousSliderCommit(.steps, &l, snapshot: l, newValue: 12)
        XCTAssertEqual(euclideousRhythmTabCount(l), "\(l.pulses)/12", "updates live with STEPS")
        euclideousSliderCommit(.hits, &l, snapshot: l, newValue: 7)
        XCTAssertEqual(euclideousRhythmTabCount(l), "7/12", "… and HITS")
    }
    func testTabAccessibilityLabelsAreTheSpecsWords() {
        var l = EuclidLine(); l.pulses = 5; l.steps = 16; l.riffOn = true; l.litNotes = 0
        XCTAssertEqual(euclideousTabAccessibilityLabel(tab: .rhythm, line: l, lane: 0), "Rhythm, 5 of 16 hits")
        XCTAssertEqual(euclideousTabAccessibilityLabel(tab: .riff, line: l, lane: 0), "Riff, on")
        XCTAssertEqual(euclideousTabAccessibilityLabel(tab: .notes, line: l, lane: 0), "Notes, off")
        l.riffOn = false; l.litNotes = 1
        XCTAssertEqual(euclideousTabAccessibilityLabel(tab: .riff, line: l, lane: 0), "Riff, off")
        XCTAssertEqual(euclideousTabAccessibilityLabel(tab: .notes, line: l, lane: 0), "Notes, on")
        XCTAssertEqual(euclideousTabAccessibilityLabel(tab: .listen, line: l, lane: 0), "Listen, off")
        l.listenRhythmMode = .follow; l.listenRhythmPartner = 1
        XCTAssertEqual(euclideousTabAccessibilityLabel(tab: .listen, line: l, lane: 0), "Listen, on, following lane 2")
        l.listenRhythmMode = nil; l.listenPitchMode = .avoid; l.listenPitchPartnerAny = true
        XCTAssertEqual(euclideousTabAccessibilityLabel(tab: .listen, line: l, lane: 0), "Listen, on, following any lane")
    }

    // MARK: 6. MIX: four lane panels (3.1, 3.2, 3.3 — test 4)

    func testMixPanelsAreSixteenApartAndPadsFourApartAtBothReferences() {
        for size in [landscapeRef, portraitRef] {
            let box = euclideousPageLayout(size: size).box
            let area = euclideousMixGridArea(panelWidth: box.width, panelHeight: box.height)
            let g = euclideousMixGrid(width: area.width, height: area.height)
            let p = (0..<4).map { g.panelFrame(lane: $0) }
            XCTAssertEqual(p[1].minX - p[0].maxX, 16, accuracy: 1e-9); XCTAssertEqual(p[3].minX - p[2].maxX, 16, accuracy: 1e-9, "sp16 across")
            XCTAssertEqual(p[2].minY - p[0].maxY, 16, accuracy: 1e-9); XCTAssertEqual(p[3].minY - p[1].maxY, 16, accuracy: 1e-9, "… and down")
            XCTAssertEqual(p[0].minX, 0); XCTAssertEqual(p[0].minY, 0)
            XCTAssertEqual(p[1].maxX, area.width, accuracy: 1e-9); XCTAssertEqual(p[3].maxY, area.height, accuracy: 1e-9, "the four panels fill the MIX area")
            XCTAssertEqual(p[0].minY, p[1].minY); XCTAssertEqual(p[2].minY, p[3].minY); XCTAssertEqual(p[0].minX, p[2].minX); XCTAssertEqual(p[1].minX, p[3].minX, "lanes 1,2 on top, 3,4 below — the lane cards' places")
            for lane in 0..<4 {
                let riff = CGRect(origin: g.origin(lane: lane, notes: false), size: CGSize(width: g.cellW, height: g.padH))
                let notes = CGRect(origin: g.origin(lane: lane, notes: true), size: CGSize(width: g.cellW, height: g.padH))
                let panel = g.panelFrame(lane: lane)
                XCTAssertEqual(notes.minX - riff.maxX, 4, accuracy: 1e-9, "RIFF then NOTES, sp4 apart")
                XCTAssertEqual(riff.minX - panel.minX, 4, accuracy: 1e-9); XCTAssertEqual(panel.maxX - notes.maxX, 4, accuracy: 1e-9, "padding sp4")
                XCTAssertEqual(riff.minY - panel.minY, 4, accuracy: 1e-9)
                let out = g.outRowFrame(lane: lane)
                XCTAssertEqual(out.minY, riff.maxY + 4 + EuclideousMixMetrics.stepperH + 4, accuracy: 1e-9, "pad, sp4, OCT stepper, sp4, OUT row")
                XCTAssertEqual(out.maxY, panel.maxY - 4, accuracy: 1e-9, "the OUT row ends at the panel's bottom padding")
                XCTAssertEqual(out.minX, panel.minX + 4, accuracy: 1e-9); XCTAssertEqual(out.width, panel.width - 8, accuracy: 1e-9, "across the panel's width")
                XCTAssertEqual(out.height, 20)
                let btns = (0..<4).map { euclideousMixOutButtonFrame(grid: g, lane: lane, button: $0) }
                XCTAssertEqual(btns[0].minX, out.minX, accuracy: 1e-9); XCTAssertEqual(btns[3].maxX, out.maxX, accuracy: 1e-9)
                for b in 0..<3 { XCTAssertEqual(btns[b + 1].minX - btns[b].maxX, 4, accuracy: 1e-9) }
            }
        }
    }
    func testNoPadIsSmallerThanTheSpacingCostsAndThePlotGrowsBack() {
        // before (the 2026-10-18 grid): cellW = (W − 16) / 4, padH = (H − 8) / 2 − 52
        for size in [landscapeRef, portraitRef] {
            let box = euclideousPageLayout(size: size).box
            let a = euclideousMixGridArea(panelWidth: box.width, panelHeight: box.height)
            let g = euclideousMixGrid(width: a.width, height: a.height)
            let oldCellW = (a.width - 16) / 4, oldPadH = (a.height - 8) / 2 - 52
            XCTAssertEqual(g.cellW, oldCellW - 6, accuracy: 1e-9, "exactly what sp4 padding + sp16 gaps cost in width")
            XCTAssertEqual(g.padH, oldPadH - 12, accuracy: 1e-9, "… and in height")
            let geo = EuclideousMixPadGeometry(cellW: g.cellW, padH: g.padH)
            XCTAssertGreaterThan(geo.plotW, oldCellW - 24, "removing the VEL strip gives the plot more width than the old pad's plot had")
            XCTAssertEqual(geo.plotW, g.cellW, "the plot spans the whole pad")
            XCTAssertFalse(g.belowFloors, "both references still clear the (shifted) floors")
        }
        // the numbers the report quotes
        let l = euclideousPageLayout(size: landscapeRef).box, a = euclideousMixGridArea(panelWidth: l.width, panelHeight: l.height)
        let g = euclideousMixGrid(width: a.width, height: a.height)
        XCTAssertEqual(g.cellW, 81.17, accuracy: 0.01); XCTAssertEqual(g.padH, 69.5, accuracy: 0.01)
        let p = euclideousPageLayout(size: portraitRef).box, pa = euclideousMixGridArea(panelWidth: p.width, panelHeight: p.height)
        let pg = euclideousMixGrid(width: pa.width, height: pa.height)
        XCTAssertEqual(pg.cellW, 82.75, accuracy: 0.01); XCTAssertEqual(pg.padH, 69.83, accuracy: 0.01)
    }
    func testTheFloorsMoveByTheSpacingCostSoTheReferencesStillClearAndSmallPanelsStillFlag() {
        XCTAssertEqual(EuclideousMixMetrics.minCellW, 78); XCTAssertEqual(EuclideousMixMetrics.minPadH, 64); XCTAssertEqual(EuclideousMixMetrics.floorPadH, 48)
        XCTAssertFalse(euclideousPageLayout(size: landscapeRef).floors.contains(.mixCellW)); XCTAssertFalse(euclideousPageLayout(size: portraitRef).floors.contains(.mixPadH))
        let mini = euclideousPageLayout(size: CGSize(width: 1113, height: 636))
        XCTAssertTrue(mini.floors.contains(.mixCellW) && mini.floors.contains(.mixPadH), "an 8.3-inch iPad mini's box still raises the flags")
    }

    // MARK: 7. MIX: the pad's readouts (3.5) and the OFF pad (3.7 — test 5)

    func testReadoutsKeepTheirWordsOnlyWhileTheyFit() {
        XCTAssertEqual(euclideousMixReadouts(padWidth: 130, velocity: 100, gate: 0.9), EuclideousMixReadouts(velocity: "VEL 100", gate: "GATE 90%"))
        XCTAssertEqual(euclideousMixReadouts(padWidth: 81.17, velocity: 100, gate: 0.9), EuclideousMixReadouts(velocity: "VEL 100", gate: "90%"), "the landscape reference pad")
        XCTAssertEqual(euclideousMixReadouts(padWidth: 82.75, velocity: 127, gate: 0.99), EuclideousMixReadouts(velocity: "VEL 127", gate: "99%"), "the portrait reference pad")
        XCTAssertEqual(euclideousMixReadouts(padWidth: 60, velocity: 100, gate: 0.9), EuclideousMixReadouts(velocity: "100", gate: "90%"))
        XCTAssertEqual(euclideousMixReadouts(padWidth: 20, velocity: 7, gate: 0.01), EuclideousMixReadouts(velocity: "7", gate: "1%"), "nothing ever truncates or shrinks")
        // narrower pads never show MORE words than wider ones
        var last = 3
        for w in stride(from: 160.0, through: 20.0, by: -4) {
            let r = euclideousMixReadouts(padWidth: CGFloat(w), velocity: 100, gate: 0.9)
            let words = (r.velocity.hasPrefix("VEL") ? 1 : 0) + (r.gate.hasPrefix("GATE") ? 2 : 0)
            XCTAssertLessThanOrEqual(words, last, "width \(w)"); last = words
        }
    }
    func testADisabledPadTouchChangesNoStateAtAll() {
        let geo = EuclideousMixPadGeometry(cellW: 81.17, padH: 69.5)
        for notes in [false, true] {
            var line = EuclidLine()
            line.riffOn = false; line.notesOn = false; line.litNotes = 0b1
            line.gate = 0.6; line.velocityAbsolute = 90; line.notesGate = 0.7; line.notesVelocity = 80
            XCTAssertTrue(euclideousMixLayerIsOff(line, notes: notes))
            let before = line
            for p in [CGPoint(x: 10, y: 10), CGPoint(x: 70, y: 5), CGPoint(x: 40, y: 40), CGPoint(x: -5, y: 900)] {
                XCTAssertFalse(euclideousMixPadTouchWrite(&line, notes: notes, at: p, geometry: geo), "a touch on an OFF pad writes nothing")
            }
            XCTAssertFalse(euclideousMixPadWriteIfEnabled(&line, notes: notes, gate: 0.2, velocity: 20)); XCTAssertFalse(euclideousMixPadResetIfEnabled(&line, notes: notes))
            XCTAssertEqual(line, before, "the layer switch, velocity and gate are all unchanged")
            XCTAssertEqual(euclideousMixLayerIsOff(line, notes: notes), true, "… and it never turned the layer on")
        }
    }
    func testAnEnabledPadStillWritesExactlyAsBefore() {
        let geo = EuclideousMixPadGeometry(cellW: 81.17, padH: 69.5)
        var line = EuclidLine(); line.riffOn = true; line.litNotes = 0b1; line.notesOn = true
        XCTAssertTrue(euclideousMixPadTouchWrite(&line, notes: true, at: geo.puck(gate: 0.5, velocity: 64), geometry: geo))
        XCTAssertEqual(line.notesGateResolved, 0.5, accuracy: 0.011); XCTAssertEqual(line.notesVelocityResolved, 64)
        var viaRiff = line, direct = line
        XCTAssertTrue(euclideousMixPadWriteIfEnabled(&viaRiff, notes: false, gate: 0.4, velocity: 70))
        euclideousMixPadWrite(&direct, notes: false, gate: 0.4, velocity: 70)
        XCTAssertEqual(viaRiff, direct, "the guarded write is the old write for an enabled pad")
        XCTAssertTrue(euclideousMixPadResetIfEnabled(&line, notes: true)); XCTAssertEqual(line.notesVelocityResolved, 100)
    }
    func testOffStepperDimsToHalfExceptUnderSolo() {
        XCTAssertEqual(euclideousMixOffStepperOpacity(off: true, soloSilenced: false), 0.5)
        XCTAssertEqual(euclideousMixOffStepperOpacity(off: false, soloSilenced: false), 1)
        XCTAssertEqual(euclideousMixOffStepperOpacity(off: true, soloSilenced: true), 1, "the panel's 42 % covers it — never 21 %")
        XCTAssertEqual(euclideousMixOffWord, "OFF")
    }

    // MARK: 8. VoiceOver for the pads (4.2) — already true, pinned

    func testPadLabelsNameTheLaneAndLayerAndOffPadsSaySo() {
        XCTAssertEqual(euclideousMixPadAccessibilityLabel(lane: 0, notes: false, off: true), "Lane 1 riff, off")
        XCTAssertEqual(euclideousMixPadAccessibilityLabel(lane: 2, notes: true, off: false), "Lane 3 notes")
        XCTAssertEqual(euclideousMixPadAccessibilityValue(gate: 0.6, velocity: 104), "gate 60 percent, velocity 104")
    }
}
