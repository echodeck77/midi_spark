//  RiffPanelTests.swift
//  RIFF PANEL ferry (2026-10-19): compact riff tabs, big arrows that blend, and lane rails under the grid. The panel's own layout, every arrow's heading / grouping /
//  fill / outline / label, a lane's current column and trail, the played set, the rail's segment looks, the tab-size icon and the VoiceOver words are PURE functions in
//  Derivations.swift and are covered here; the drawing (`RiffArrowPainter.swift`, `EuclideousPage`) has no macOS test-target reach and is device-owed.

import XCTest

final class RiffPanelTests: XCTestCase {

    private func near(_ a: CGFloat, _ b: CGFloat, _ msg: String = "", accuracy: CGFloat = 0.01, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(a, b, accuracy: accuracy, msg, file: file, line: line)
    }
    private let landBox = CGSize(width: 1142.0 / 3, height: 319)              // 380.67 × 319
    private let portBox = CGSize(width: 387, height: 959.0 / 3)               // 387 × 319.67

    // MARK: 1. the panel's inside

    func testPanelLayoutAtTheLandscapeReference() {
        let l = euclideousRiffPanelLayout(box: landBox)
        XCTAssertEqual(EuclideousRiffPanelMetrics.chromeH, 119); XCTAssertEqual(EuclideousRiffPanelMetrics.railsH, 41)
        near(l.rowH, 25); near(l.cellW, 37.83); near(l.cellH, 25)
        near(l.tabFrame(0).minY, 8); near(l.tabFrame(0).maxY, 28); near(l.tabWidth, 88.17)
        near(l.tabFrame(1).minX - l.tabFrame(0).maxX, 4, "tabs are sp4 apart"); near(l.tabFrame(3).maxX, landBox.width - 8)
        near(l.gridTop, 34)
        for r in 0..<8 { near(l.rowTop(r), 34 + 29 * CGFloat(r), "row \(r)") }
        near(l.rowTop(7) + l.cellH, 262, "the last row ends at y 262")
        for c in 0..<8 { near(l.columnLeft(c), 42 + 41.83 * CGFloat(c), "column \(c)", accuracy: 0.05) }
        for (k, y) in [270.0, 281, 292, 303].enumerated() { near(l.railTop(k), CGFloat(y), "rail \(k)"); near(l.railSegmentFrame(lane: k, column: 0).height, 8) }
        near(l.railTop(3) + 8 + 8, landBox.height, "the rails end at the bottom padding")
        near(l.railNumberFrame(0).width, 30); near(l.railNumberFrame(0).minX, 8)
        near(l.railSegmentFrame(lane: 2, column: 5).minX, l.columnLeft(5)); near(l.railSegmentFrame(lane: 2, column: 5).width, l.cellW)
        XCTAssertFalse(l.belowFloor)
        // rank 8 is the top row, rank 1 the bottom
        near(l.cellFrame(column: 0, rank: 8).minY, 34); near(l.cellFrame(column: 0, rank: 1).minY, l.rowTop(7))
        // FX keeps lining up: the column width is still the riff grid's own function
        XCTAssertEqual(l.cellW, euclideousRiffCellW(maxWidth: landBox.width))
    }
    func testPanelLayoutAtThePortraitReferenceAndTheOtherBoxes() {
        let l = euclideousRiffPanelLayout(box: portBox)
        near(l.rowH, 25.08); near(l.cellW, 38.63); near(l.tabWidth, 89.75)
        near(l.rowTop(7) + l.cellH, 262.67)
        for (k, y) in [270.67, 281.67, 292.67, 303.67].enumerated() { near(l.railTop(k), CGFloat(y), "rail \(k)") }
        for c in 0..<8 { near(l.columnLeft(c), 42 + 42.63 * CGFloat(c), "column \(c)", accuracy: 0.05) }
        // the floor: 24pt rows need a box 311 tall; 300 is flagged; the page-is-9pt-short boxes (314.5 / 316.67) clear it
        XCTAssertTrue(euclideousRiffPanelLayout(box: CGSize(width: 380.67, height: 300)).belowFloor)
        XCTAssertFalse(euclideousRiffPanelLayout(box: CGSize(width: 380.67, height: 311)).belowFloor)
        near(euclideousRiffPanelLayout(box: CGSize(width: 380.67, height: 311)).rowH, 24)
        near(euclideousRiffPanelLayout(box: CGSize(width: 380.67, height: 314.5)).rowH, 24.44)
        near(euclideousRiffPanelLayout(box: CGSize(width: 387, height: 316.67)).rowH, 24.71)
        XCTAssertTrue(euclideousPageFloors(box: CGSize(width: 380, height: 300)).contains(.riffRows))
        XCTAssertFalse(euclideousPageFloors(box: CGSize(width: 380, height: 314.5)).contains(.riffRows))
    }

    // MARK: 2. heading

    private func headings(_ dir: RiffDir, length: Int, stride: Int = 1, every: Int = 1, ordinals: ClosedRange<Int64>) -> [EuclideousArrowHeading] {
        ordinals.map { euclideousArrowHeading(riffDir: dir, length: length, stride: stride, every: every, ordinal: $0) }
    }
    func testForwardAlwaysHeadsRightAndReverseLeft() {
        XCTAssertTrue(headings(.forward, length: 8, ordinals: 0...40).allSatisfy { $0 == .right }, "FWD: right at every ordinal, through the wrap from column 8 to 1")
        XCTAssertTrue(headings(.forward, length: 5, stride: 3, ordinals: 0...40).allSatisfy { $0 == .right })
        XCTAssertTrue(headings(.reverse, length: 8, ordinals: 0...40).allSatisfy { $0 == .left }, "REV: left")
        XCTAssertTrue(headings(.random, length: 8, ordinals: 0...8).allSatisfy { $0 == .right }, "RANDOM/DRUNK coerce to FWD")
    }
    func testPendulumAndPingTurnAtEachEnd() {
        let R = EuclideousArrowHeading.right, L = EuclideousArrowHeading.left
        XCTAssertEqual(headings(.pendulum, length: 4, ordinals: 0...7), [R, R, R, L, L, L, R, R], "PEND at LEN 4, walk steps 0–7")
        XCTAssertEqual(headings(.pingpong, length: 4, ordinals: 0...9), [R, R, R, L, L, L, L, R, R, R], "PING at LEN 4, steps 0–9 (the repeated end step looks one further)")
    }
    func testStillWhenThereIsNoWalkAndEveryHoldsAcrossEachPair() {
        XCTAssertTrue(headings(.forward, length: 1, ordinals: 0...5).allSatisfy { $0 == .still }, "LEN 1")
        XCTAssertTrue(headings(.pendulum, length: 1, ordinals: 0...5).allSatisfy { $0 == .still })
        XCTAssertTrue(headings(.forward, length: 4, stride: 4, ordinals: 0...9).allSatisfy { $0 == .still }, "FWD LEN 4 STRIDE 4: P = 1")
        XCTAssertTrue(headings(.reverse, length: 4, stride: 4, ordinals: 0...9).allSatisfy { $0 == .still })
        let pend2 = headings(.pendulum, length: 4, every: 2, ordinals: 0...15)
        for pair in stride(from: 0, to: 16, by: 2) { XCTAssertEqual(pend2[pair], pend2[pair + 1], "EVERY 2: the heading holds across ordinals \(pair), \(pair + 1)") }
        XCTAssertEqual(Array(pend2.prefix(8)), [.right, .right, .right, .right, .right, .right, .left, .left], "EVERY 2 stretches PEND's walk steps 0–3 over eight hits")
    }

    // MARK: 3. grouping

    func testGroupingKindsAndLeftToRightOrder() {
        func g(_ m: [(Int, EuclideousArrowHeading)]) -> (EuclideousArrowKind, [Int]) {
            let r = euclideousArrowGrouping(m.map { EuclideousArrowMember(lane: $0.0, heading: $0.1) }); return (r.kind, r.lanes)
        }
        XCTAssertTrue(g([(3, .right), (1, .left)]) == (.double, [1, 3]), "lanes 2 (left) and 4 (right): double-headed, ordered 2·4")
        XCTAssertTrue(g([(0, .right), (2, .right)]) == (.right, [0, 2]), "lanes 1 and 3 heading right: a right arrow, 1·3")
        XCTAssertTrue(g([(0, .right), (2, .still)]) == (.right, [2, 0]), "lane 3 still with lane 1 right: a right arrow, 3·1")
        XCTAssertTrue(g([(1, .still)]) == (.still, [1]), "one still lane: a capsule")
        XCTAssertTrue(g([(0, .left), (1, .left)]) == (.left, [0, 1]))
        XCTAssertTrue(g([(0, .right), (1, .still), (2, .left), (3, .still)]) == (.double, [2, 1, 3, 0]), "left, then still (lane order), then right")
    }

    // MARK: 4. blend

    func testTheSixMidpointsAreThePublishedOnes() {
        let want: [(Int, Int, UInt32)] = [(0, 1, 0xBF86EC), (0, 2, 0xFC8C2E), (0, 3, 0xE19C00), (1, 2, 0x64D79E), (1, 3, 0x09D6C7), (2, 3, 0xC7CE4A)]
        for (i, j, hex) in want {
            let m = euclideousMixOKLCH(euclideousLaneRGB[i], euclideousLaneRGB[j], t: 0.5)
            XCTAssertEqual(m.r, Int((hex >> 16) & 0xFF), accuracy: 1, "lanes \(i + 1)+\(j + 1) r"); XCTAssertEqual(m.g, Int((hex >> 8) & 0xFF), accuracy: 1, "g"); XCTAssertEqual(m.b, Int(hex & 0xFF), accuracy: 1, "b")
        }
        XCTAssertEqual(euclideousLaneRGB, [EuclideousRGB(r: 242, g: 89, b: 89), EuclideousRGB(r: 89, g: 191, b: 242), EuclideousRGB(r: 242, g: 191, b: 64), EuclideousRGB(r: 140, g: 217, b: 115)])
    }
    func testBlendStopsHoldEachLanesColourPureAtItsEnd() {
        let c = [euclideousLaneRGB[1], euclideousLaneRGB[2]]
        let s = euclideousBlendStops(colours: c)
        XCTAssertEqual(s.count, 7); XCTAssertEqual(s.first?.position, 0); XCTAssertEqual(s.first?.colour, c[0]); XCTAssertEqual(s.last?.position, 1); XCTAssertEqual(s.last?.colour, c[1])
        for i in 1..<s.count { XCTAssertGreaterThan(s[i].position, s[i - 1].position) }
        // interior stops: p0 + hold + (p1 − p0 − 2·hold)·u with hold = 0.14 / (n − 1)
        XCTAssertEqual(s[1].position, 0.14 + (1 - 0.28) / 6, accuracy: 1e-12); XCTAssertEqual(s[3].position, 0.5, accuracy: 1e-12)
        XCTAssertEqual(s[3].colour, euclideousMixOKLCH(c[0], c[1], t: 0.5), "u = 1/2 → e = 1/2")
        let three = euclideousBlendStops(colours: [euclideousLaneRGB[0], euclideousLaneRGB[1], euclideousLaneRGB[2]])
        XCTAssertEqual(three.count, 13, "7 + 7 − the shared middle stop")
        XCTAssertEqual(three[6].position, 0.5); XCTAssertEqual(three[6].colour, euclideousLaneRGB[1])
        XCTAssertEqual(euclideousBlendStops(colours: c), s, "memoised by lane set: the same answer")
        // the shorter way round the hue circle: red↔blue goes via magenta, never via green
        XCTAssertGreaterThan(euclideousMixOKLCH(euclideousLaneRGB[0], euclideousLaneRGB[1], t: 0.5).b, euclideousMixOKLCH(euclideousLaneRGB[0], euclideousLaneRGB[1], t: 0.5).g)
    }

    // MARK: 5–6. current and trail

    private func laneCfg(buf: [Bool]? = nil, n: Int = 8, sub: Double = 0.5, riffDir: RiffDir = .forward, length: Int = 8, stride: Int = 1, rotate: Int = 0, every: Int = 1,
                         advanceStep: Bool = false, chains: EuclideousLaneRestartChains = .off) -> EuclideousWalkLaneConfig {
        EuclideousWalkLaneConfig(buf: buf ?? [Bool](repeating: true, count: n), n: n, dir: .fwd, sub: sub, chains: chains, riffDir: riffDir, stride: stride, length: length,
                                 rotate: rotate, advanceStep: advanceStep, every: every)
    }
    func testCurrentAndTrailAdvHitFwd() {
        let cfg = laneCfg()
        let w = euclideousRailWalk(cfg: cfg, hitTick: 3)                    // hits reading 1, 2, 3, 4
        XCTAssertEqual(w.current, 3); XCTAssertEqual(w.trail, [2, 1, 0], "current 4, trail 3, 2, 1")
        XCTAssertEqual(euclideousRailWalk(cfg: cfg, hitTick: 0).trail, [], "the very first hit has no trail")
        XCTAssertEqual(euclideousRailWalk(cfg: cfg, hitTick: 1).trail, [0])
        XCTAssertEqual(euclideousRailWalk(cfg: cfg, hitTick: 9).current, 1, "FWD wraps 8 → 1")
        XCTAssertEqual(euclideousRailWalk(cfg: cfg, hitTick: 9).trail, [0, 7, 6])
    }
    func testCurrentAndTrailPingEveryAndMelodyRestart() {
        let ping = laneCfg(riffDir: .pingpong, length: 4)
        let p = euclideousRailWalk(cfg: ping, hitTick: 4)                  // hits reading …, 3, 4, 4 (ordinals 2, 3, 4)
        XCTAssertEqual(p.current, 3); XCTAssertEqual(p.trail, [2, 1, 0], "PING at LEN 4, after 3, 4, 4: the second 4's trail is 3, 2, 1 (the first 4 is skipped)")
        let ev = laneCfg(every: 2)
        let e = euclideousRailWalk(cfg: ev, hitTick: 4)                    // hits reading 1, 1, 2, 2, 3
        XCTAssertEqual(e.current, 2); XCTAssertEqual(e.trail, [1, 0], "EVERY 2, after 1, 1, 2, 2, 3: current 3, trail 2, 1")
        // a melody restart every bar (8 ticks at this rate): the first hit after it has no trail; the next has just that one
        let restart = laneCfg(chains: EuclideousLaneRestartChains(rhythm: .free, melody: .from([1]), barBeats: 4, lapBeats: 4))
        XCTAssertEqual(euclideousRailWalk(cfg: restart, hitTick: 8).trail, [], "the first hit after a melody restart has no trail")
        XCTAssertEqual(euclideousRailWalk(cfg: restart, hitTick: 8).current, 0)
        XCTAssertEqual(euclideousRailWalk(cfg: restart, hitTick: 9).trail, [0])
    }
    func testCurrentAndTrailAdvStepFollowsTheRealHitSchedule() {
        let buf = [true, false, false, true, false, false, true, false]      // hits on steps 1, 4 and 7
        let cfg = laneCfg(buf: buf, advanceStep: true)
        XCTAssertEqual([0, 3, 6].map { euclideousRailWalk(cfg: cfg, hitTick: Int64($0)).current }, [0, 3, 6], "the hits read 1, 4, 7")
        let next = euclideousRailWalk(cfg: cfg, hitTick: 8)
        XCTAssertEqual(next.current, 0, "then 1 on the next pass"); XCTAssertEqual(next.trail, [6, 3, 0], "…whose trail is 7, 4, 1")
        // across a RHYTHM restart that cuts the pass short (a 2-beat bar at 0.5 beats a tick = every 4 ticks): hits land on ticks 0, 3, 4, 7, 8 → columns 1, 4, 5, 8, 1
        let cut = laneCfg(buf: buf, advanceStep: true, chains: EuclideousLaneRestartChains(rhythm: .from([1]), melody: .free, barBeats: 2, lapBeats: 4))
        let ticks: [Int64] = (0..<12).filter { euclideousLaneChainTick(buf: buf, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, tick: Int64($0), chains: cut.chains, legacySpanBeats: 0, advanceStep: true).rawIsHit }.map { Int64($0) }
        XCTAssertEqual(ticks, [0, 3, 4, 7, 8, 11], "the Router's own hit schedule")
        let w = euclideousRailWalk(cfg: cut, hitTick: 8)
        XCTAssertEqual(w.current, 0); XCTAssertEqual(w.trail, [7, 4, 3], "ADV STEP across the restart: 8, 5, 4 (1-based) before the 1")
    }

    // MARK: 7. played set

    func testPlayedColumnsAreExactlyTheMiniGridsFullStrengthSet() {
        // the riff ferry's 7.8 example of Paul's lane 1: 16 steps, hits on 1, 4, 8, 11, 14, FWD, ADV STEP, LEN 8, SHIFT 5
        var buf = [Bool](repeating: false, count: 16)
        for h in [1, 4, 8, 11, 14] { buf[h - 1] = true }
        let r = euclideousRiffReadout(buf: buf, n: 16, dir: .fwd, cycleLen: 16, sub: 0.25, chains: .off, legacySpanBeats: 0, advanceStep: true,
                                      riffDir: .forward, stride: 1, length: 8, shift: 5, every: 1, seed: 0)
        XCTAssertEqual(r?.neverPlay, [1, 3, 6], "columns 2, 4 and 7 (1-based) never play")
        XCTAssertEqual(euclideousRailPlayedColumns(length: 8, neverPlay: r?.neverPlay ?? []), [0, 2, 4, 5, 7])
        // 7.6's fallbacks: no hits at all (H = 0) / an over-budget readout → no never-play info → every column within LEN fills
        let none = euclideousRiffReadout(buf: [Bool](repeating: false, count: 16), n: 16, dir: .fwd, cycleLen: 16, sub: 0.25, chains: .off, legacySpanBeats: 0, advanceStep: true,
                                         riffDir: .forward, stride: 1, length: 8, shift: 5, every: 1, seed: 0)
        XCTAssertEqual(none?.neverPlay, [])
        XCTAssertEqual(euclideousRailPlayedColumns(length: 8, neverPlay: none?.neverPlay ?? []), Set(0..<8))
        XCTAssertEqual(euclideousRailPlayedColumns(length: 5, neverPlay: []), Set(0..<5), "only within LEN")
        XCTAssertEqual(euclideousRailPlayedColumns(length: 8, neverPlay: [1]), [0, 2, 3, 4, 5, 6, 7])
    }

    // MARK: 8. arrow spec: size, outline, label, fill, muting, flare

    private func lane(_ i: Int, _ h: EuclideousArrowHeading = .right, muted: Bool = false, flare: Double = 0) -> EuclideousArrowLane { EuclideousArrowLane(lane: i, heading: h, muted: muted, flare: flare) }
    func testArrowSizeOutlineAndLabel() {
        let l = euclideousRiffPanelLayout(box: landBox), p = euclideousRiffPanelLayout(box: portBox)
        near(EuclideousArrowStyle.size(cellW: l.cellW, cellH: l.cellH).width, 30.83); near(EuclideousArrowStyle.size(cellW: l.cellW, cellH: l.cellH).height, 17)
        near(EuclideousArrowStyle.size(cellW: p.cellW, cellH: p.cellH).width, 31.63); near(EuclideousArrowStyle.size(cellW: p.cellW, cellH: p.cellH).height, 17.08)
        // the right arrow in a 30.83 × 17 box: r = 4, t = m = 8.5
        guard case .path(let cmds) = euclideousArrowOutline(kind: .right, w: 30.83, h: 17) else { return XCTFail("a path") }
        XCTAssertEqual(cmds.count, 10)
        XCTAssertEqual(cmds[0], .move(CGPoint(x: 4, y: 0))); XCTAssertEqual(cmds[1], .line(CGPoint(x: 30.83 - 8.5, y: 0)))
        XCTAssertEqual(cmds[2], .line(CGPoint(x: 30.83 - 0.9, y: 8.5 - 1.3))); XCTAssertEqual(cmds[3], .quad(to: CGPoint(x: 30.83 - 0.9, y: 8.5 + 1.3), control: CGPoint(x: 30.83, y: 8.5)))
        XCTAssertEqual(cmds[5], .line(CGPoint(x: 4, y: 17))); XCTAssertEqual(cmds[6], .quad(to: CGPoint(x: 0, y: 13), control: CGPoint(x: 0, y: 17))); XCTAssertEqual(cmds[9], .close)
        guard case .path(let lc) = euclideousArrowOutline(kind: .left, w: 30.83, h: 17) else { return XCTFail("a path") }
        XCTAssertEqual(lc[0], .move(CGPoint(x: 30.83 - 4, y: 0)), "left is the right arrow mirrored")
        guard case .path(let dc) = euclideousArrowOutline(kind: .double, w: 30.83, h: 17) else { return XCTFail("a path") }
        XCTAssertEqual(dc.count, 9); XCTAssertEqual(dc[0], .move(CGPoint(x: 8.5, y: 0))); XCTAssertEqual(dc[5], .line(CGPoint(x: 8.5, y: 17)))
        XCTAssertEqual(euclideousArrowOutline(kind: .still, w: 30.83, h: 17), .capsule)
        // labels: numbers in the fill's order joined by ·; 10 / 8.5 / 6.5 / 6pt; one-way → the body, double / 3+ → the whole arrow with 2pt insets
        let one = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(1)], hollow: false)!
        XCTAssertEqual(one.label, "2"); XCTAssertEqual(one.labelSize, 10); XCTAssertEqual(one.kind, .right); near(one.labelRect.width, 30.83 - 8.5); near(one.labelRect.minX, 0)
        let two = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0), lane(2)], hollow: false)!
        XCTAssertEqual(two.label, "1\u{00B7}3"); XCTAssertEqual(two.labelSize, 8.5); XCTAssertEqual(two.lanes, [0, 2]); near(two.labelRect.width, 30.83 - 8.5)
        let dbl = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(3, .right), lane(1, .left)], hollow: false)!
        XCTAssertEqual(dbl.kind, .double); XCTAssertEqual(dbl.label, "2\u{00B7}4"); near(dbl.labelRect.minX, 2); near(dbl.labelRect.width, 30.83 - 4)
        let left = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(1, .left)], hollow: false)!
        near(left.labelRect.minX, 8.5); near(left.labelRect.width, 30.83 - 8.5)
        XCTAssertEqual(euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0), lane(1), lane(2)], hollow: false)!.labelSize, 6.5)
        XCTAssertEqual(euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0), lane(1), lane(2), lane(3)], hollow: false)!.labelSize, 6)
        let cap = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0, .still)], hollow: false)!
        XCTAssertEqual(cap.outline, .capsule); near(cap.labelRect.minX, 2); near(cap.labelRect.width, 30.83 - 4, "a capsule has no tip: the label centres on the whole shape")
        XCTAssertNil(euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [], hollow: false))
    }
    func testOneLaneFillIsTheCometTilesAndTwoOrMoreBlend() {
        let one = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0)], hollow: false)!
        XCTAssertEqual(one.fill, .single(colour: euclideousLaneRGB[0], topAlpha: 0.95, bottomAlpha: 0.55), "the hit tile's own alpha gradient (source), not the mock's × 0.86")
        guard case .blend(let st) = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(1), lane(2)], hollow: false)!.fill else { return XCTFail("a blend") }
        XCTAssertEqual(st.first?.colour, euclideousLaneRGB[1]); XCTAssertEqual(st.last?.colour, euclideousLaneRGB[2]); XCTAssertTrue(st.allSatisfy { $0.alpha == 1 })
    }
    func testMutingDimsOneLanesStopsOrTheWholeArrow() {
        let alone = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0, muted: true)], hollow: false)!
        XCTAssertEqual(alone.opacity, 0.42, "alone and muted: the whole arrow at 42%")
        let shared = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0, muted: true), lane(2, .right)], hollow: false)!
        XCTAssertEqual(shared.opacity, 1, "one lane muted: the arrow isn't dimmed")
        guard case .blend(let st) = shared.fill else { return XCTFail("a blend") }
        XCTAssertEqual(st.first?.alpha, 0.42, "that lane's stop is at 42% alpha"); XCTAssertEqual(st.last?.alpha, 1)
        XCTAssertEqual(shared.labelParts.first?.alpha, 0.42, "its number draws at 42%"); XCTAssertEqual(shared.labelParts.last?.alpha, 1)
        let both = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0, muted: true), lane(2, muted: true)], hollow: false)!
        XCTAssertEqual(both.opacity, 0.42, "both muted: the arrow at 42%")
        // muting and flaring never change a heading (5.2): the same headings in, the same kind out
        XCTAssertEqual(both.kind, shared.kind)
    }
    func testFlareTakesTheBlendOfTheLanesNowFlaring() {
        XCTAssertNil(euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0), lane(1)], hollow: false)!.flareColour)
        let one = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0, flare: 0.8), lane(1)], hollow: false)!
        XCTAssertEqual(one.flareColour, euclideousLaneRGB[0]); XCTAssertEqual(one.flareStrength, 0.8)
        let two = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0, flare: 1), lane(1, flare: 0.6)], hollow: false)!
        XCTAssertEqual(two.flareColour, euclideousMixOKLCH(euclideousLaneRGB[0], euclideousLaneRGB[1], t: 0.5)); XCTAssertEqual(two.flareStrength, 1)
        let three = euclideousArrowSpec(cellW: 37.83, cellH: 25, members: [lane(0, flare: 1), lane(1, flare: 1), lane(2, flare: 1)], hollow: false)!
        XCTAssertEqual(three.flareColour, euclideousEvenBlend([0, 1, 2].map { euclideousLaneRGB[$0] }))
        // the comet bar's own afterglow / burst windows
        XCTAssertEqual(euclideousArrowFlare(onsetBeat: 1, beat: 1, stepBeats: 0.25), 1, "the strike's peak")
        XCTAssertEqual(euclideousArrowFlare(onsetBeat: 1, beat: 1 + 0.25 * 0.35, stepBeats: 0.25), 0.6 * (1 - 0.35 / 1.5), accuracy: 1e-9, "the burst is over; 60% of the decaying afterglow remains")
        XCTAssertEqual(euclideousArrowFlare(onsetBeat: 1, beat: 1 + 0.25 * 1.5, stepBeats: 0.25), 0, accuracy: 1e-9, "…gone when the afterglow ends")
        XCTAssertEqual(euclideousArrowFlare(onsetBeat: 2, beat: 1, stepBeats: 0.25), 0, "a strike still in the future reads 0")
        XCTAssertEqual(euclideousArrowFlare(onsetBeat: nil, beat: 1, stepBeats: 0.25), 0)
    }

    // MARK: arrow seats: where the arrow sits (TIE stays, the others take the rest's cell)

    private func restRiffCfg(_ onRest: EuclidRiffOnRest) -> EuclideousWalkLaneConfig {
        var c = laneCfg(); c.onRest = onRest; return c
    }
    func testTieKeepsTheArrowOnTheTiedNoteAndTheOthersSitHollowOnTheRest() {
        let ranks = [5, 0, 3, 0, 0, 0, 0, 0]
        // beat 0.51 = just after tick 1 (the hit on the rest at column 2): a running plan seated on it
        func state(_ onRest: EuclidRiffOnRest) -> (EuclideousWalkTagPlan, EuclideousLaneArrowState) {
            let cfg = restRiffCfg(onRest)
            let plan = euclideousWalkTagPlan(cfg: cfg, ranks: ranks, beat: 0.51, secondsPerBeat: 0.5, polledStep: 1, running: true)!
            return (plan, euclideousLaneArrowState(lane: 0, cfg: cfg, plan: plan, polledOrdinal: 1))
        }
        let (tp, tie) = state(.tie)
        XCTAssertTrue(tp.seatIsRest); XCTAssertEqual(tp.seatStep, 1); XCTAssertEqual(tp.seatOrdinal, 1)
        XCTAssertEqual(tp.tieStay, EuclideousTieStay(step: 0, rank: 5, ordinal: 0))
        XCTAssertEqual(tie.column, 0, "TIE: the arrow stays where it was"); XCTAssertEqual(tie.rank, 5); XCTAssertFalse(tie.hollow, "…drawn as normal")
        for mode in [EuclidRiffOnRest.skip, .fill, .repeatLast] {
            let (p, s) = state(mode)
            XCTAssertNil(p.tieStay, "\(mode)")
            XCTAssertEqual(s.column, 1, "\(mode): the rest's own column"); XCTAssertEqual(s.rank, 5, "…at the held row"); XCTAssertTrue(s.hollow, "…hollow")
        }
        // a stopped transport: the polled seat and ordinal give the same answer
        let sp = euclideousWalkTagPlan(cfg: restRiffCfg(.tie), ranks: ranks, beat: 0, secondsPerBeat: 0.5, polledStep: 1, running: false, polledOrdinal: 1)!
        XCTAssertEqual(sp.tieStay, EuclideousTieStay(step: 0, rank: 5, ordinal: 0)); XCTAssertEqual(sp.seatOrdinal, 1)
        // nothing sounding to tie to → the rest is a plain hollow seat (the engine's own SKIP fallback)
        let first = euclideousWalkTagPlan(cfg: restRiffCfg(.tie), ranks: [0, 4, 0, 0, 0, 0, 0, 0], beat: 0.01, secondsPerBeat: 0.5, polledStep: 0, running: true)
        if let f = first { XCTAssertNil(f.tieStay) }
    }
    func testLanesInTheSameCellShareOneArrow() {
        let a = EuclideousLaneArrowState(lane: 1, column: 3, rank: 4, hollow: false, heading: .left)
        let b = EuclideousLaneArrowState(lane: 2, column: 3, rank: 4, hollow: true, heading: .right)
        let c = EuclideousLaneArrowState(lane: 0, column: 5, rank: 4, hollow: true, heading: .right)
        let cells = euclideousArrowCells([b, a, c])
        XCTAssertEqual(cells.count, 2); XCTAssertEqual(cells[0].column, 5, "ordered by lowest lane"); XCTAssertTrue(cells[0].hollow)
        XCTAssertEqual(cells[1].members.map { $0.lane }, [1, 2]); XCTAssertFalse(cells[1].hollow, "hollow only if EVERY lane in it is on a rest")
    }

    // MARK: rails

    func testRailSegmentLooksAndStates() {
        let played: Set<Int> = [0, 2, 3, 4, 5, 6, 7]
        let run = euclideousRailSpec(lane: 2, riffOn: true, running: true, muted: false, played: played, current: 4, trail: [3, 2, 0], heading: .right, flare: 0.5)
        XCTAssertEqual(run.segments[4].look, .current(.right)); XCTAssertEqual(run.segments[3].look, .trail(0)); XCTAssertEqual(run.segments[2].look, .trail(1)); XCTAssertEqual(run.segments[0].look, .trail(2))
        XCTAssertEqual(run.segments[1].look, .notPlayed, "the column the WALK readout says never plays"); XCTAssertEqual(run.segments[7].look, .played)
        XCTAssertEqual(run.flare, 0.5); XCTAssertEqual(run.numberOpacity, 1); XCTAssertTrue(run.segments.allSatisfy { $0.opacity == 1 })
        XCTAssertEqual(EuclideousRailStyle.trailAlphas, [0.5, 0.32, 0.2])
        let off = euclideousRailSpec(lane: 1, riffOn: false, running: true, muted: false, played: played, current: 4, trail: [3], heading: .right, flare: 1)
        XCTAssertTrue(off.segments.allSatisfy { $0.look == .notPlayed && $0.opacity == 0.6 }, "riff off: all eight not-played at 60%"); XCTAssertEqual(off.numberOpacity, 0.42); XCTAssertEqual(off.flare, 0)
        let stopped = euclideousRailSpec(lane: 3, riffOn: true, running: false, muted: false, played: [0, 1, 2, 3], current: 2, trail: [1], heading: .right, flare: 1)
        XCTAssertEqual(stopped.segments.map { $0.look }, [.played, .played, .played, .played, .notPlayed, .notPlayed, .notPlayed, .notPlayed], "stopped: the played columns only, no current or trail")
        XCTAssertEqual(stopped.flare, 0)
        let muted = euclideousRailSpec(lane: 0, riffOn: true, running: true, muted: true, played: played, current: 4, trail: [], heading: .left, flare: 0)
        XCTAssertTrue(muted.segments.allSatisfy { $0.opacity == 0.42 }, "muted: segments and chevron at 42%"); XCTAssertEqual(muted.numberOpacity, 1, "…the number stays at full strength")
        XCTAssertEqual(muted.segments[4].look, .current(.left))
        let both = euclideousRailSpec(lane: 0, riffOn: true, running: true, muted: false, played: played, current: 4, trail: [4, 4], heading: .still, flare: 0)
        XCTAssertEqual(both.segments[4].look, .current(.still), "current outranks a trail column")
    }

    // MARK: 9. the tab-size icon

    func testTabSizeIconGeometry() {
        let st = EuclideousMiniIconStyle.tab
        XCTAssertEqual(st.size.width, 21.7, accuracy: 1e-9); XCTAssertEqual(st.size.height, 12.8, accuracy: 1e-9)
        let g = euclideousMiniIconGeometry(ranks: [4, 1, 1, 1, 1, 1, 1, 1], style: st)
        XCTAssertEqual(g.marks.count, 8); XCTAssertEqual(g.dots.count, 56); XCTAssertEqual(g.size, st.size)
        XCTAssertEqual(g.marks[0], CGRect(x: 0, y: 4 * 1.65, width: 2.1, height: 1.25), "rank 4 → row 4 from the top")
        for c in 1..<8 { XCTAssertEqual(g.marks[c], CGRect(x: CGFloat(c) * 2.8, y: 7 * 1.65, width: 2.1, height: 1.25), "rank 1 → the bottom row, column \(c)") }
        // dots are 0.7 × 0.7 centred where a mark would be: column 0, row 0 is the first dot
        XCTAssertEqual(g.dots[0].minX, 0.7, accuracy: 1e-9); XCTAssertEqual(g.dots[0].minY, 0.275, accuracy: 1e-9); XCTAssertEqual(g.dots[0].width, 0.7); XCTAssertEqual(g.dots[0].height, 0.7)
        XCTAssertFalse(g.dots.contains { abs($0.minY - (4 * 1.65 + 0.275)) < 1e-9 && $0.minX < 2.8 }, "no dot where column 0's mark is")
        let empty = euclideousMiniIconGeometry(ranks: [], style: st)
        XCTAssertEqual(empty.marks.count, 0); XCTAssertEqual(empty.dots.count, 64)
        XCTAssertEqual(euclideousMiniIconGeometry(ranks: [0, 0, 0, 0, 0, 0, 0, 0], style: st).dots.count, 64, "a rest is a full column of dots")
        // the default style is the 31 × 23 icon every other place draws, unchanged
        let std = euclideousMiniIconGeometry(ranks: [8, 0, 1], style: .standard)
        XCTAssertEqual(std.size, CGSize(width: 31, height: 23))
        XCTAssertEqual(std.marks[0], CGRect(x: 0, y: 0, width: 3, height: 2)); XCTAssertEqual(std.marks[1], CGRect(x: 8, y: 21, width: 3, height: 2))
        XCTAssertEqual(std.dots[0], CGRect(x: 1, y: 3.5, width: 1, height: 1), "column 0's first dot is row 1 (row 0 holds the mark)")
    }

    // MARK: 7 (VoiceOver)

    func testSpokenCellPhrasesAndRailLabels() {
        func m(_ l: Int, _ h: EuclideousArrowHeading) -> EuclideousArrowMember { EuclideousArrowMember(lane: l, heading: h) }
        XCTAssertEqual(euclideousArrowCellPhrase(members: [m(0, .right)], onRest: false), ", lane 1 heading right")
        XCTAssertEqual(euclideousArrowCellPhrase(members: [m(0, .left)], onRest: false), ", lane 1 heading left")
        XCTAssertEqual(euclideousArrowCellPhrase(members: [m(0, .still)], onRest: false), ", lane 1 staying put")
        XCTAssertEqual(euclideousArrowCellPhrase(members: [m(2, .right), m(1, .left)], onRest: false), ", lanes 2 and 3: 2 heading left, 3 heading right")
        XCTAssertEqual(euclideousArrowCellPhrase(members: [m(0, .right)], onRest: true), ", lane 1 heading right, on a rest")
        XCTAssertEqual(euclideousArrowCellPhrase(members: [m(0, .right), m(1, .right), m(3, .still)], onRest: false), ", lanes 1, 2 and 4: 1 heading right, 2 heading right, 4 staying put")
        XCTAssertEqual(euclideousSpokenColumns([0, 2, 3, 4, 5, 6, 7]), "1 and 3 to 8", "runs of three or more read as a range")
        XCTAssertEqual(euclideousSpokenColumns([0, 1, 2, 3]), "1 to 4"); XCTAssertEqual(euclideousSpokenColumns([0, 1]), "1 and 2"); XCTAssertEqual(euclideousSpokenColumns([4]), "5")
        XCTAssertEqual(euclideousSpokenColumns([0, 2, 4]), "1, 3 and 5")
        XCTAssertEqual(euclideousRailAccessibilityLabel(lane: 0, riffOn: true, running: true, played: [0, 2, 3, 4, 5, 6, 7], current: 3, heading: .right, muted: false),
                       "Lane 1: plays columns 1 and 3 to 8, on 4, heading right")
        XCTAssertEqual(euclideousRailAccessibilityLabel(lane: 1, riffOn: false, running: true, played: [0], current: nil, heading: .still, muted: false), "Lane 2: riff off")
        XCTAssertEqual(euclideousRailAccessibilityLabel(lane: 3, riffOn: true, running: false, played: [0, 1, 2, 3], current: nil, heading: .still, muted: false), "Lane 4: stopped, plays columns 1 to 4")
        XCTAssertEqual(euclideousRailAccessibilityLabel(lane: 0, riffOn: true, running: true, played: [0, 1], current: 1, heading: .left, muted: true),
                       "Lane 1: plays columns 1 and 2, on 2, heading left, silent at this step")
        XCTAssertEqual(euclideousRailAccessibilityLabel(lane: 2, riffOn: true, running: true, played: [], current: nil, heading: .still, muted: false), "Lane 3: plays no columns")
    }

    // MARK: the readout cache (RIFF WALK §7.2: memoise on the inputs)

    func testReadoutIsComputedOncePerInputsPerLane() {
        let cache = EuclideousRiffReadoutCache()
        let harness = [true, false, true, false, true, true, false, true]   // hits 1, 3, 5, 6, 8 (RouterTests' §7.8 harness lane)
        let a = laneCfg(buf: harness, sub: 0.5, stride: 2)
        let first = cache.readout(lane: 0, cfg: a), again = cache.readout(lane: 0, cfg: a)
        XCTAssertEqual(cache.computeCount, 1, "the second ask is a hit")
        XCTAssertEqual(first?.neverPlay, [1, 3, 5, 7]); XCTAssertEqual(again?.neverPlay, [1, 3, 5, 7])
        let direct = euclideousRiffReadout(buf: harness, n: 8, dir: .fwd, cycleLen: 8, sub: 0.5, chains: .off, legacySpanBeats: 0, advanceStep: false,
                                           riffDir: .forward, stride: 2, length: 8, shift: 0, every: 1, seed: 0)
        XCTAssertEqual(first?.neverPlay, direct?.neverPlay); XCTAssertEqual(first?.period, direct?.period)
        _ = cache.readout(lane: 1, cfg: a)
        XCTAssertEqual(cache.computeCount, 2, "each lane has its own slot")
        _ = cache.readout(lane: 0, cfg: a)
        XCTAssertEqual(cache.computeCount, 2, "…and lane 0's slot survived lane 1's fill")
        // any input a lane edits recomputes: the riff's STRIDE, its pattern, its restart chains, ADV STEP, EVERY, SHIFT, LEN
        let edits: [EuclideousWalkLaneConfig] = [laneCfg(buf: harness, sub: 0.5, stride: 3), laneCfg(buf: [true, true, true, true, true, true, true, false], sub: 0.5, stride: 2),
                                                 laneCfg(buf: harness, sub: 0.5, stride: 2, advanceStep: true), laneCfg(buf: harness, sub: 0.5, stride: 2, every: 2),
                                                 laneCfg(buf: harness, sub: 0.5, stride: 2, rotate: 1), laneCfg(buf: harness, sub: 0.5, length: 5, stride: 2),
                                                 laneCfg(buf: harness, sub: 0.25, stride: 2),
                                                 laneCfg(buf: harness, sub: 0.5, stride: 2, chains: EuclideousLaneRestartChains(rhythm: .free, melody: .from([2]), barBeats: 4, lapBeats: 4))]
        var expected = 2
        for e in edits {
            _ = cache.readout(lane: 0, cfg: e); expected += 1
            XCTAssertEqual(cache.computeCount, expected, "an edit recomputes")
            _ = cache.readout(lane: 0, cfg: e)
            XCTAssertEqual(cache.computeCount, expected, "…and the same edit again is a hit")
        }
        // a lane index outside the four slots is simply computed (never cached, never trapped)
        _ = cache.readout(lane: 9, cfg: a); _ = cache.readout(lane: 9, cfg: a)
        XCTAssertEqual(cache.computeCount, expected + 2)
        // the over-budget answer (nil) is cached too — recomputing it is the expensive case
        let overBudget = laneCfg(buf: [Bool](repeating: true, count: 16), n: 16, sub: 0.25, riffDir: .pingpong, length: 8, stride: 1)
        _ = cache.readout(lane: 2, cfg: overBudget); let c1 = cache.computeCount; _ = cache.readout(lane: 2, cfg: overBudget)
        XCTAssertEqual(cache.computeCount, c1)
    }
}
