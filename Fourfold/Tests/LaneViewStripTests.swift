//  LaneViewStripTests.swift — TAB STRIP ferry (2026-10-29): the strip's frames, glyph states, the page's one tab and the VoiceOver strings. Pure functions only (LaneViewStrip.swift); the views have no macOS test-target reach.

import XCTest

final class LaneViewStripTests: XCTestCase {
    private func near(_ a: CGFloat, _ b: CGFloat, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a, b, accuracy: 0.01, msg, file: file, line: line) }
    private func near(_ r: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        near(r.minX, x, "\(msg) x", file: file, line: line); near(r.minY, y, "\(msg) y", file: file, line: line); near(r.width, w, "\(msg) w", file: file, line: line); near(r.height, h, "\(msg) h", file: file, line: line)
    }
    private let land = euclideousPageLayout(size: CGSize(width: 1190, height: 726)), port = euclideousPageLayout(size: CGSize(width: 814, height: 1102))

    // MARK: 2. the strip's frames

    func testLandscapeReferenceFrames() {
        // MIX folded into the one control (2026-10-30): five segments, no separate MIX container; the dice and padlock are unmoved.
        let L = euclideousLaneStripLayout(width: land.strip.width)
        near(land.strip.width, 769.33)
        near(L.tabControl, 0, 0, 701.33, 28, "the tab control: what the tiles and the gaps leave")
        near(L.dice, 709.33, 0, 28, 28, "the dice"); near(L.padlock, 741.33, 0, 28, 28, "the padlock")
        near(L.padlock.maxX, 769.33, "the padlock ends on the strip's edge"); near(L.dice.maxX + 4, L.padlock.minX, "sp4 between the tiles"); near(L.tabControl.maxX + 8, L.dice.minX, "sp8 before the dice")
        XCTAssertEqual(L.segments.count, 5)
        for r in L.segments { near(r.width, 136.67, "segment width"); near(r.height, 22, "segment height"); near(r.minY, 3, "3 pt inset") }
        near(L.segments[0].minX, 3, "3 pt inset"); near(L.segments[1].minX - L.segments[0].maxX, 3, "segments 3 apart"); near(L.tabControl.maxX - L.segments[4].maxX, 3, "3 pt inset at the end (MIX is the fifth)")
        for (r, t) in zip(L.segments, L.segmentTargets) { near(t.width, r.width, "target as wide as the segment"); near(t.height, 44, "target 44 tall"); near(t.midY, r.midY, "centred on the segment"); near(t.midX, r.midX, "centred") }
        near(L.diceTarget.width, 36, "tile targets 36 wide"); near(L.diceTarget.height, 44, "…and 44 tall"); near(L.diceTarget.midX, L.dice.midX, "centred on the tile"); near(L.padlockTarget.midY, L.padlock.midY, "centred")
        XCTAssertTrue(L.clustersVisible); XCTAssertFalse(L.belowFloor)
    }
    func testPortraitReferenceFrames() {
        let L = euclideousLaneStripLayout(width: port.strip.width)
        near(port.strip.width, 782)
        near(L.tabControl, 0, 0, 714, 28, "the tab control"); near(L.dice, 722, 0, 28, 28, "dice"); near(L.padlock, 754, 0, 28, 28, "padlock")
        XCTAssertEqual(L.segments.count, 5); for r in L.segments { near(r.width, 139.2, "segment width") }
        XCTAssertTrue(L.clustersVisible)
    }
    /// §2.6: under 96 pt a segment hides the clusters — on all five together — and nothing shrinks: the tiles stay 28, the segments keep 22 tall and the labels are the views' to truncate.
    func testNarrowStripHidesTheClustersOnAllFourAndShrinksNothing() {
        // a segment is 96 wide when the strip is 5 × 96 + 6 + 12 (the control) + 8 + 28 + 4 + 28 = 566
        let atFloor = euclideousLaneStripLayout(width: 566), under = euclideousLaneStripLayout(width: 565.9)
        XCTAssertTrue(atFloor.clustersVisible); XCTAssertFalse(atFloor.belowFloor); near(atFloor.segmentWidth, 96)
        XCTAssertFalse(under.clustersVisible); XCTAssertTrue(under.belowFloor)
        let narrow = euclideousLaneStripLayout(width: 268)   // a 300-wide portrait window: two 130-wide cards and their gap
        XCTAssertFalse(narrow.clustersVisible)
        near(narrow.dice.width, 28); near(narrow.padlock.width, 28); for r in narrow.segments { near(r.height, 22) }
        XCTAssertEqual(narrow.segments.count, 5); XCTAssertEqual(Set(narrow.segments.map { $0.width }).count, 1, "five equal segments")
        for tab in EuclideousPageTab.allCases {
            XCTAssertNil(euclideousLaneStripSegmentContent(segment: narrow.segments[1], tab: tab, clustersVisible: false).cluster, "no cluster on any segment when they are hidden")
        }
        XCTAssertEqual(euclideousPageFloors(box: CGSize(width: 130, height: 300), stripWidth: 268).contains(.laneStrip), true)
        XCTAssertFalse(euclideousPageFloors(box: CGSize(width: 380, height: 319), stripWidth: 769.33).contains(.laneStrip))
    }
    /// The label and the cluster centre in the segment as ONE group, sp8 apart; RHYTHM (no cluster) centres its label alone.
    func testLabelAndClusterCentreAsOneGroup() {
        let L = euclideousLaneStripLayout(width: land.strip.width)
        for tab in [EuclideousPageTab.riff, .notes, .listen] {
            let c = euclideousLaneStripSegmentContent(segment: L.segments[tab.rawValue], tab: tab, clustersVisible: true)
            guard let cluster = c.cluster else { return XCTFail("\(tab) has a cluster") }
            near((c.label.minX + cluster.maxX) / 2, L.segments[tab.rawValue].midX, "\(tab): the group is centred")
            near(cluster.minX - c.label.maxX, 8, "\(tab): label and cluster sp8 apart")
            XCTAssertEqual(c.glyphs.count, 4); for i in 1..<4 { near(c.glyphs[i].minX - c.glyphs[i - 1].maxX, 4, "glyphs 4 apart") }
            near(c.glyphs[0].midY, L.segments[tab.rawValue].midY, "centred vertically")
        }
        let r = euclideousLaneStripSegmentContent(segment: L.segments[0], tab: .rhythm, clustersVisible: true)
        XCTAssertNil(r.cluster); near(r.label.midX, L.segments[0].midX, "RHYTHM's label alone is centred")
        let sizes = [EuclideousGlyphShape.square: CGSize(width: 6, height: 6), .bar: CGSize(width: 3, height: 8), .circle: CGSize(width: 6, height: 6)]
        for (shape, size) in sizes { XCTAssertEqual(EuclideousLaneStripMetrics.glyphSize(shape), size) }
        near(euclideousLaneStripClusterWidth(.square), 36); near(euclideousLaneStripClusterWidth(.bar), 24); near(euclideousLaneStripClusterWidth(.circle), 36)
    }

    // MARK: 4. glyph states

    private func lines(riffOff: Set<Int> = [], notesOn: Set<Int> = [], follow: [Int: Int] = [:]) -> [EuclidLine] {
        (0..<4).map { i in
            var l = EuclidLine(); l.useRiff = true; l.riffOn = !riffOff.contains(i)
            if notesOn.contains(i) { l.notesOn = true; var o = EuclideousLitOrder(); o.append(0); l.setLitOrder(o) } else { l.notesOn = false }
            if let src = follow[i] { l.listenPitch = .shadow; l.listenSource = src }
            return l
        }
    }
    func testRiffAndNotesGlyphsAreOnOrOffPerLane() {
        let ls = lines(riffOff: [2], notesOn: [0, 1])
        let riff = euclideousLaneStripGlyphs(tab: .riff, lines: ls), notes = euclideousLaneStripGlyphs(tab: .notes, lines: ls)
        XCTAssertEqual(riff.map { $0.on }, [true, true, false, true], "lane 3's riff is off: the third square is an outline")
        XCTAssertEqual(notes.map { $0.on }, [true, true, false, false])
        XCTAssertEqual(riff.map { $0.shape }, [.square, .square, .square, .square]); XCTAssertEqual(notes.map { $0.shape }, [.bar, .bar, .bar, .bar])
        XCTAssertEqual(riff[2], euclideousTabGlyph(tab: .riff, line: ls[2], lane: 2), "one call of the clarity pass's function per lane")
        XCTAssertTrue(euclideousLaneStripGlyphs(tab: .rhythm, lines: ls).isEmpty); XCTAssertTrue(euclideousLaneStripGlyphs(tab: .mix, lines: ls).isEmpty)
    }
    func testListenGlyphTakesTheSourceLanesColourAndIsAnOutlineWhenOff() {
        let ls = lines(follow: [0: 1])   // lane 1 follows lane 2
        let listen = euclideousLaneStripGlyphs(tab: .listen, lines: ls)
        XCTAssertEqual(listen[0], EuclideousTabGlyph(shape: .circle, on: true, fill: .lane(1)), "LISTEN's first circle takes lane 2's colour")
        XCTAssertFalse(listen[1].on); XCTAssertFalse(listen[2].on); XCTAssertFalse(listen[3].on)
        XCTAssertEqual(euclideousLaneStripGlyphLook(listen[0], selected: false), EuclideousLaneStripGlyphLook(filledLane: 1, outline: nil))
        XCTAssertEqual(euclideousLaneStripGlyphLook(listen[1], selected: false), EuclideousLaneStripGlyphLook(filledLane: nil, outline: HocketColor(0x4A4E57)), "off: a 1 pt outline, #4A4E57 on an unselected segment")
        XCTAssertEqual(euclideousLaneStripGlyphLook(listen[1], selected: true), EuclideousLaneStripGlyphLook(filledLane: nil, outline: HocketColor(0x8A909A)), "…and #8A909A on the selected one")
        XCTAssertEqual(EuclideousLaneStripMetrics.outlineWidth, 1)
    }

    // MARK: 5. the page's one tab

    func testTheTabIsOneValueAndTappingTheSelectedSegmentChangesNothing() {
        XCTAssertEqual(EuclideousPageTab.opening, .rhythm, "the page opens on RHYTHM and never on MIX"); XCTAssertNotEqual(EuclideousPageTab.opening, .mix)
        for t in EuclideousPageTab.allCases { XCTAssertNil(euclideousPageTabTap(current: t, tapped: t), "\(t): tapping the selected segment does nothing") }
        XCTAssertEqual(EuclideousPageTab.allCases.count, 5)
        XCTAssertEqual(EuclideousPageTab.riff.front, .riff); XCTAssertNil(EuclideousPageTab.mix.front)
    }
    func testEveryTabChangeFlips() {
        // Paul, 2026-10-30: EVERY tab change turns the cards now — front → front as well as front ↔ MIX.
        XCTAssertEqual(euclideousPageTabTap(current: .rhythm, tapped: .notes), EuclideousPageTabChange(tab: .notes, flips: true), "between two front tabs the cards turn over too")
        XCTAssertEqual(euclideousPageTabTap(current: .listen, tapped: .riff), EuclideousPageTabChange(tab: .riff, flips: true))
        XCTAssertEqual(euclideousPageTabTap(current: .riff, tapped: .mix), EuclideousPageTabChange(tab: .mix, flips: true), "front → MIX turns the cards over")
        XCTAssertEqual(euclideousPageTabTap(current: .mix, tapped: .notes), EuclideousPageTabChange(tab: .notes, flips: true), "MIX → a front tab turns them back")
        // the turn is card back 3.3's flip: lane order, 70 ms apart, 280 ms each, Reduce Motion 150 ms (CardBackTests pins the function; the strip uses it unchanged)
        XCTAssertEqual(EuclideousCardFlipMetrics.stagger, 0.070); XCTAssertEqual(EuclideousCardFlipMetrics.duration, 0.280); XCTAssertEqual(EuclideousCardFlipMetrics.reduceMotionDuration, 0.150)
        // euclideousCardTurn relabels euclideousCardFlip's phases as show-FROM / show-TO (the from tab fills the first half, the to tab the second)
        let mid = EuclideousCardTurnFrame(scaleX: euclideousCardTurn(sinceTap: 0, lane: 0).scaleX, showsTo: false, opacity: 1, underShowsTo: nil, underOpacity: 0, ignoresTouches: false)
        XCTAssertFalse(euclideousCardTurn(sinceTap: 0.0001, lane: 0).showsTo, "the first half draws the FROM tab")
        XCTAssertTrue(euclideousCardTurn(sinceTap: 0.279, lane: 0).showsTo, "the second half draws the TO tab")
        XCTAssertEqual(mid.scaleX, 1, accuracy: 0.001, "the turn starts at full width")
    }
    func testRandomModeStartsOnThePageTabOrRhythmForListenAndMix() {
        XCTAssertEqual(euclideousRandomStartTab(.rhythm), .rhythm); XCTAssertEqual(euclideousRandomStartTab(.riff), .riff); XCTAssertEqual(euclideousRandomStartTab(.notes), .notes)
        XCTAssertEqual(euclideousRandomStartTab(.listen), .rhythm, "random mode throws RHYTHM, RIFF or NOTES"); XCTAssertEqual(euclideousRandomStartTab(.mix), .rhythm)
    }

    // MARK: the strip and the cards at every layout the page can produce

    /// The sizes the project tests the page at (the iPads, the windowed AUM / Stage Manager sizes): header kind, the strip and its segments, the lane card and its zones, the floors that flag — printed as `TABSTRIP-LAYOUT` lines for the status log,
    /// and held to the invariants that must be true everywhere (the strip fits the lane area; the cards end where the old equal boxes did; nothing is negative).
    func testTheStripAndTheCardsAtEveryLayoutThePageCanProduce() {
        let sizes: [(String, CGSize)] = [("1376×1032", CGSize(width: 1376, height: 1032)), ("1366×1024", CGSize(width: 1366, height: 1024)), ("1194×834", CGSize(width: 1194, height: 834)), ("1190×726 (ref)", CGSize(width: 1190, height: 726)),
                                         ("1180×820", CGSize(width: 1180, height: 820)), ("1133×744 (mini)", CGSize(width: 1133, height: 744)), ("1113×683", CGSize(width: 1113, height: 683)), ("1113×636", CGSize(width: 1113, height: 636)),
                                         ("1024×768", CGSize(width: 1024, height: 768)), ("900×600 window", CGSize(width: 900, height: 600)), ("834×1210", CGSize(width: 834, height: 1210)), ("814×1102 (ref)", CGSize(width: 814, height: 1102)),
                                         ("768×1024", CGSize(width: 768, height: 1024)), ("744×1133 (mini)", CGSize(width: 744, height: 1133)), ("700×900 window", CGSize(width: 700, height: 900)), ("600×900 window", CGSize(width: 600, height: 900)),
                                         ("500×900 window", CGSize(width: 500, height: 900)), ("300×700 window", CGSize(width: 300, height: 700))]
        func f(_ v: CGFloat) -> String { String(format: "%.1f", Double(v)) }
        var table: [String] = []
        for (name, size) in sizes {
            let p = euclideousPageLayout(size: size)
            let S = euclideousLaneStripLayout(width: p.strip.width)
            let content = EuclideousLaneCardMetrics.contentAreaH(cardHeight: p.laneBox.height)
            let back = euclideousCardBackLayout(card: p.laneBox)
            let inner = EuclideousLaneCardMetrics.innerWidth(cardWidth: p.laneBox.width)
            table.append("TABSTRIP-LAYOUT \(name): header \(p.headerKind) top \(f(EuclideousPageMetrics.top(p.headerKind))) | strip \(f(p.strip.width)) seg \(f(S.segmentWidth)) clusters \(S.clustersVisible ? "shown" : "HIDDEN") | lane \(f(p.laneBox.width))×\(f(p.laneBox.height)) content \(f(content)) upper \(f(content - 84)) rowH(back) \(f(back.rowHeight)) | comet strip \(f(EuclideousLockBadge.cometStripWidth(innerWidth: inner, withBadge: false)))/\(f(EuclideousLockBadge.cometStripWidth(innerWidth: inner, withBadge: true))) | floors \(p.floors)")
            XCTAssertEqual(p.strip.maxX, p.lanes[1].maxX, accuracy: 1e-9, name); XCTAssertEqual(p.strip.minY + 28 + 8, p.lanes[0].minY, accuracy: 1e-9, name)
            XCTAssertEqual(p.lanes[3].maxY, p.isLandscape ? p.seq.maxY : p.riff.minY - 8, accuracy: 1e-6, "\(name): the cards end where the old equal boxes did")
            XCTAssertGreaterThan(p.laneBox.height, 0); XCTAssertGreaterThan(content, 0)
            XCTAssertEqual(S.segments.count, 5); XCTAssertEqual(S.dice.width, 28); XCTAssertEqual(S.padlock.width, 28)
            // independent of the layout function: the control is the strip less the dice 28, padlock 28 and their gaps 8 / 4 (= 68); a segment is (control − 2 × 3 inset − 4 × 3 gap) ÷ 5, so it is under 96 exactly below 566
            XCTAssertEqual(p.floors.contains(.laneStrip), p.strip.width < 566 - 1e-9, name)
        }
        print(table.joined(separator: "\n"))
    }

    // MARK: adversarial review (2026-10-29) — the literals the ferry names, pinned

    /// §2.2–§2.5 spelled out: a drifted colour, radius, type size or tile size used to pass every test (the painter and the layout both read these constants, so only a literal can catch it).
    func testTheFerrysLiteralLooksArePinned() {
        typealias M = EuclideousLaneStripMetrics
        XCTAssertEqual([M.container.hex, M.selectedFill.hex, M.selectedText.hex, M.unselectedText.hex, M.outlineOnSelected.hex, M.outlineOnUnselected.hex], [0x1F2127, 0xDFE3EA, 0x0D0F14, 0xAAB0BA, 0x8A909A, 0x4A4E57])
        XCTAssertEqual([M.containerRadius, M.segmentRadius, M.containerInset, M.segmentGap, M.segmentHeight, M.height], [8, 6, 3, 3, 22, 28])
        XCTAssertEqual([M.labelFont, M.labelTracking], [10, 0.12], "10 pt heavy, 0.12 em")
        XCTAssertEqual([M.tileSize, M.tilePlateRadius, M.tileGlyph, M.tileTargetWidth, M.targetHeight], [28, 8, 16, 36, 44])
        XCTAssertEqual([M.diceRingSize, M.diceRingRadius], [32, 10])
        XCTAssertEqual([M.squareSize.width, M.squareSize.height, M.squareRadius, M.barSize.width, M.barSize.height, M.barRadius, M.circleSize.width, M.glyphGap, M.outlineWidth], [6, 6, 1.5, 3, 8, 1, 6, 4, 1])
        XCTAssertEqual(M.labelClusterGap, 8); XCTAssertEqual(M.segmentFloor, 96)
    }
    /// The painter draws each tab's cluster from `euclideousLaneStripShape`, not from the glyph's own shape: the two must agree, and be the ferry's (RIFF square, NOTES bar, LISTEN circle, RHYTHM and MIX none).
    func testEachTabsClusterShapeIsTheFerrysAndTheGlyphFunctionsOwn() {
        XCTAssertEqual(euclideousLaneStripShape(.riff), .square); XCTAssertEqual(euclideousLaneStripShape(.notes), .bar); XCTAssertEqual(euclideousLaneStripShape(.listen), .circle)
        XCTAssertEqual(euclideousLaneStripShape(.rhythm), .none); XCTAssertEqual(euclideousLaneStripShape(.mix), .none)
        for tab in [EuclideousPageTab.riff, .notes, .listen] {
            let glyphs = euclideousLaneStripGlyphs(tab: tab, lines: lines(notesOn: [0, 1, 2, 3]))
            XCTAssertEqual(glyphs.count, 4, "\(tab)"); for g in glyphs { XCTAssertEqual(g.shape, euclideousLaneStripShape(tab), "\(tab): the clarity pass's glyph and the strip's shape agree") }
        }
        for tab in [EuclideousPageTab.rhythm, .mix] { XCTAssertTrue(euclideousLaneStripGlyphs(tab: tab, lines: lines()).isEmpty, "\(tab) has no cluster") }
    }
    /// `front` maps the page tab onto the card tab kind by raw value (and the page's `EuclideousLaneTab` the same way): a reorder of either enum would silently show the wrong tab.
    func testThePageTabMapsOntoTheCardTabKindByName() {
        for tab in EuclideousPageTab.allCases where tab != .mix {
            XCTAssertEqual(tab.front.map { "\($0)" }, "\(tab)", "\(tab) must show the card tab of the same name")
        }
        XCTAssertEqual(EuclideousPageTab.allCases.map { $0.rawValue }, [0, 1, 2, 3, 4])
        XCTAssertEqual(EuclideousTabKind.allCases.map { "\($0)" }, ["rhythm", "riff", "notes", "listen"])
    }
    /// Spec 2.5 puts the padlock sp4 after the dice with 36-wide targets: the two targets share 4 pt, and the padlock (later in the stack) owns it. Pinned so the overlap is a known number, not an accident.
    func testTheDiceAndPadlockTargetsShareFourPointsAndNothingElse() {
        for w in [769.33, 782.0, 553.0] as [CGFloat] {
            let S = euclideousLaneStripLayout(width: w)
            near(S.diceTarget.width, 36); near(S.padlockTarget.width, 36); near(S.diceTarget.height, 44); near(S.padlockTarget.height, 44)
            near(S.diceTarget.maxX - S.padlockTarget.minX, 4, "\(w): the dice and padlock targets overlap by 4")
            XCTAssertLessThanOrEqual(S.segmentTargets[4].maxX, S.diceTarget.minX + 1e-9, "\(w): MIX (the fifth segment) stops before the dice's target")
            for i in 0..<5 { XCTAssertLessThanOrEqual(S.segmentTargets[i].maxX, (i < 4 ? S.segmentTargets[i + 1].minX : S.tabControl.maxX) + 1e-9, "\(w): segment \(i)'s target does not cross its neighbour") }
            XCTAssertLessThanOrEqual(S.padlockTarget.maxX, S.bounds.maxX + 4 + 1e-9)
        }
    }
    /// At exactly the 96 pt floor every tab's label and cluster fit inside the segment (LISTEN is the widest: 6 letters + sp8 + four 6 pt circles).
    func testLabelAndClusterFitInASegmentAtTheFloor() {
        let S = euclideousLaneStripLayout(width: 566)   // five segments at the 96 pt floor
        XCTAssertTrue(S.clustersVisible); near(S.segmentWidth, 96)
        for tab in EuclideousPageTab.allCases where tab != .mix {
            let c = euclideousLaneStripSegmentContent(segment: S.segments[2], tab: tab, clustersVisible: true)
            XCTAssertGreaterThanOrEqual(c.label.minX, S.segments[2].minX, "\(tab) label starts inside the segment")
            XCTAssertLessThanOrEqual(c.cluster?.maxX ?? c.label.maxX, S.segments[2].maxX, "\(tab) group ends inside the segment")
        }
    }

    // MARK: 7. random mode and lock mode

    func testATouchOnAStripTabFinishesARunningModeAndChangesNothing() {
        XCTAssertEqual(euclideousStripTapAction(randomMode: false, lockMode: false), .selectTab)
        XCTAssertEqual(euclideousStripTapAction(randomMode: true, lockMode: false), .finishRandom, "random mode: the tab does not change, the mode ends")
        XCTAssertEqual(euclideousStripTapAction(randomMode: false, lockMode: true), .finishLock, "lock mode likewise")
        XCTAssertEqual(euclideousStripTapAction(randomMode: true, lockMode: true), .finishRandom, "both on: the random faces are what is showing, so they finish first")
    }

    // MARK: 7.1 VoiceOver

    func testSegmentLabels() {
        let all = lines(notesOn: [0, 1, 2, 3])
        XCTAssertEqual(euclideousLaneStripLabel(tab: .rhythm, glyphs: []), "Rhythm"); XCTAssertEqual(euclideousLaneStripLabel(tab: .mix, glyphs: []), "Mix")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .riff, glyphs: euclideousLaneStripGlyphs(tab: .riff, lines: all)), "Riff, all on")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .riff, glyphs: euclideousLaneStripGlyphs(tab: .riff, lines: lines(riffOff: [2]))), "Riff, lanes 1, 2 and 4 on")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .riff, glyphs: euclideousLaneStripGlyphs(tab: .riff, lines: lines(riffOff: [0, 1, 2, 3]))), "Riff, all off")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .riff, glyphs: euclideousLaneStripGlyphs(tab: .riff, lines: lines(riffOff: [0, 1, 3]))), "Riff, lane 3 on")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .riff, glyphs: euclideousLaneStripGlyphs(tab: .riff, lines: lines(riffOff: [1, 2]))), "Riff, lanes 1 and 4 on")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .notes, glyphs: euclideousLaneStripGlyphs(tab: .notes, lines: lines(notesOn: [0]))), "Notes, lane 1 on")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .notes, glyphs: euclideousLaneStripGlyphs(tab: .notes, lines: lines())), "Notes, all off")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .listen, glyphs: euclideousLaneStripGlyphs(tab: .listen, lines: lines(follow: [2: 1]))), "Listen, lane 3 following lane 2")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .listen, glyphs: euclideousLaneStripGlyphs(tab: .listen, lines: lines(follow: [0: 1, 2: 3]))), "Listen, lane 1 following lane 2 and lane 3 following lane 4")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .listen, glyphs: euclideousLaneStripGlyphs(tab: .listen, lines: lines(follow: [0: 1, 2: 1, 3: 1]))), "Listen, lane 1 following lane 2, lane 3 following lane 2 and lane 4 following lane 2", "three or more read as a list")
        XCTAssertEqual(euclideousLaneStripLabel(tab: .listen, glyphs: euclideousLaneStripGlyphs(tab: .listen, lines: lines())), "Listen, all off")
        XCTAssertEqual(euclideousLaneStripGroupLabel, "Lane view")
    }
}
