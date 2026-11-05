//  MixPanelV2Tests.swift — MIX v2 ferry (2026-11-05) + amendment 1 (revised): the pure layer (`MixPanelV2.swift`). Test 1 (every frame of §1.3–1.5, the strip frame's contents, the emitters, the floors), the amendment's alignment
//  tests at every page layout, and — as the ferry's later steps land — the strip, stack, TRANS, OCT and solo-button looks.
//  The spec's landscape figures (bandW 677.33, blockW 595.33, V 93.67 …) are the PRE-TAB-STRIP 753.33-wide panel; the source's lane area is 769.33 wide (MIX rows found the same), so the references below are the source's, and one test
//  evaluates the same formulas at 753.33 to show they reproduce the spec's own numbers.

import XCTest

final class MixPanelV2Tests: XCTestCase {
    private func close(_ a: CGFloat, _ b: CGFloat, _ msg: String = "", file: StaticString = #filePath, line: UInt = #line) { XCTAssertEqual(a, b, accuracy: 0.011, msg, file: file, line: line) }
    private func rect(_ r: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ msg: String, file: StaticString = #filePath, line: UInt = #line) {
        close(r.minX, x, "\(msg) x", file: file, line: line); close(r.minY, y, "\(msg) y", file: file, line: line); close(r.width, w, "\(msg) w", file: file, line: line); close(r.height, h, "\(msg) h", file: file, line: line)
    }
    private let landscape = CGSize(width: 769.333333, height: 610)
    private let portrait = CGSize(width: 782, height: 611.333333)

    // MARK: test 1 — the frames

    func testTheLandscapeReferenceInTheSourcesWidth() {
        let L = euclideousMixV2Layout(size: landscape)
        close(L.bandW, 693.33); close(L.bandH, 148); close(L.innerW, 681.33); close(L.innerH, 136); close(L.blockW, 611.33); close(L.rowH, 47); close(L.tileH, 41); close(L.sliderW, 101.67); close(L.chipH, 10.75)
        XCTAssertEqual(L.floors, [], "no floor flags at the reference")
        let b = L.bands[0]
        rect(b.frame, 0, 0, 693.33, 148, "band 1"); rect(b.inner, 6, 6, 681.33, 136, "its inset")
        // §1.3: the pool, the fork, the right block, the strip frame, the two rows
        rect(b.pool, 0, 36, 56, 100, "pool"); close(b.forkStart.x, 56); close(b.forkStart.y, 86, "the fork leaves the pool's mid-height (amendment B2.2)")
        rect(b.stripFrame, 70, 0, 611.33 - 113, 30, "strip frame (498.33 wide)")
        rect(b.riff.plate, 70, 36, 611.33, 47, "riff row"); rect(b.notes.plate, 70, 89, 611.33, 47, "notes row"); close(b.notes.plate.maxY, L.innerH, "the notes row ends at the inner bottom")
        // §1.4: a part row left to right (the riff row; the notes row's x's are the same)
        for r in [b.riff, b.notes] {
            rect(r.solo, 73, r.plate.minY + 3, 22, 41, "S"); rect(r.soloTarget, 70, r.plate.minY, 26, 47, "S target 26 × rowH")
            rect(r.toggle, 99, r.plate.minY + 3, 48, 41, "toggle"); rect(r.stack, 153, r.plate.minY + 3, 30, 41, "stack")
            rect(r.vel, 189, r.plate.minY + 3, 101.67, 41, "VEL"); rect(r.gate, 189 + 101.67 + 4, r.plate.minY + 3, 101.67, 41, "GATE")
            rect(r.trans, 189 + 2 * 101.67 + 8, r.plate.minY + 3, 54, 41, "TRANS")
            rect(r.oct, 189 + 2 * 101.67 + 8 + 54 + 4, r.plate.minY + 3, 110, 41, "OCT")
            rect(r.outs, 189 + 2 * 101.67 + 8 + 54 + 4 + 110 + 6, r.plate.minY + 3, 104, 41, "A–D")
            close(r.outs.maxX, 70 + 611.33 - 3, "A–D ends 3 in from the plate's right edge")
        }
        // §4.7 / 4.8 / 4.9 inside the tiles
        rect(b.riff.transLeft, b.riff.trans.minX, 39, 34, 41, "TRANS left"); rect(b.riff.transRight, b.riff.trans.minX + 34, 39, 20, 41, "TRANS right")
        rect(b.riff.transUpper, b.riff.trans.minX, 36, 54, 23.5, "TRANS upper target (54 × rowH ÷ 2)"); rect(b.riff.transLower, b.riff.trans.minX, 59.5, 54, 23.5, "TRANS lower target")
        XCTAssertEqual(b.riff.octBoxes.count, 5); rect(b.riff.octBoxes[0], b.riff.oct.minX, 39 + 9, 22, 30, "OCT box 1 (22 × 30)"); rect(b.riff.octBoxes[4], b.riff.oct.minX + 88, 48, 22, 30, "OCT box 5")
        for t in b.riff.octTargets { XCTAssertGreaterThanOrEqual(t.height, 44, "an OCT target is never under 44 tall") }
        XCTAssertEqual(b.riff.outTargets.count, 4); rect(b.riff.outTargets[1], b.riff.outs.minX + 26, 36, 26, 47, "B target 26 × rowH"); rect(b.riff.outCircles[0], b.riff.outs.minX + 2, 39 + 9.5, 22, 22, "A's 22 pt circle")
        // amendment B1: the top line
        rect(b.play, 0, 0, 56, 30, "play (the pool's column)"); rect(b.playTarget, 0, 0, 56, 36, "play target 56 × 36")
        rect(b.hitsBox, 70 + 611.33 - 107, 0, 50, 30, "HITS"); rect(b.stepsBox, 70 + 611.33 - 107 + 54, 0, 50, 30, "STEPS")
        rect(b.stripSteps, 72.5, 2.5, 498.33 - 5, 25, "the steps (the strip frame less its 2.5 inset)"); rect(b.badge, 70 + 498.33 - 2.5 - 25, 2.5, 25, 25, "the lock badge, 25 × 25 at the strip's right end")
        close(b.stripStepsWithBadge.maxX, b.badge.minX - 4, "the steps end sp4 before the badge")
        // §6.1 the emitters: 36 pt at x 40…76 of the column, centred at band top + 6 + 36 + rowH + 3
        for n in 0..<4 { let top = CGFloat(n) * (148 + 6); rect(L.emitters[n], 693.33 + 40, top + 45 + 47 - 18, 36, 36, "emitter \(n + 1)") }
        close(L.emitters[0].midY, 92, "the spec's 92")
    }
    func testThePortraitReference() {
        let L = euclideousMixV2Layout(size: portrait)
        close(L.bandW, 706); close(L.bandH, 148.33); close(L.innerW, 694); close(L.innerH, 136.33); close(L.blockW, 624); close(L.rowH, 47.17); close(L.sliderW, 108, "the spec's 108"); close(L.chipH, 10.79, "the amendment's 10.79")
        let b = L.bands[0]
        close(b.stripFrame.width, 511, "the amendment's 511"); close(b.hitsBox.minX, 70 + 517, "HITS starts at 517 in the right block"); close(b.stepsBox.maxX, 70 + 621, "STEPS ends at 621")
        XCTAssertEqual(L.floors, [])
    }
    /// The spec's own reference figures belong to a 753.33-wide panel; the same formulas reproduce them there.
    func testTheFormulasReproduceTheSpecsOwnFigures() {
        let L = euclideousMixV2Layout(size: CGSize(width: 753.333333, height: 610))
        close(L.bandW, 677.33); close(L.innerW, 665.33); close(L.blockW, 595.33); close(L.sliderW, 93.67); close(L.rowH, 47); close(L.tileH, 41)
        let b = L.bands[0]
        close(b.stripFrame.width, 482.33, "the amendment's 482.33"); close(b.hitsBox.minX - 70, 488.33, "HITS from 488.33"); close(b.stepsBox.maxX - 70, 592.33, "STEPS to 592.33")
    }
    func testThePoolAndTheFork() {
        let L = euclideousMixV2Layout(size: landscape), b = L.bands[0]
        XCTAssertEqual(b.chips.count, 8)
        for (i, c) in b.chips.enumerated() { rect(c, 0, 36 + CGFloat(i) * (10.75 + 2), 56, 10.75, "chip \(i) (rank \(8 - i))") }
        close(b.chips[7].maxY, L.innerH, "rank 1 sits on the inner bottom")
        let riff = euclideousMixV2ForkCurve(from: b.forkStart, to: b.forkRiffEnd), notes = euclideousMixV2ForkCurve(from: b.forkStart, to: b.forkNotesEnd)
        close(riff.start.x, 56); close(riff.start.y, 86); close(riff.end.x, 70); close(riff.end.y, b.riff.centreY, "to the riff row's centre"); close(notes.end.y, b.notes.centreY)
        close(riff.c1.x, 63.8); close(riff.c1.y, 86, "(63.8, y0)"); close(riff.c2.x, 62.2); close(riff.c2.y, b.riff.centreY, "(62.2, y1)")
        close(notes.c2.y, b.notes.centreY)
    }

    // MARK: the amendment's alignment — at every page layout

    /// The sizes the page is tested at (the TAB STRIP ferry's table; "layout 5.3" has no list of its own).
    static let pageSizes: [(String, CGSize)] = [("1376×1032", CGSize(width: 1376, height: 1032)), ("1366×1024", CGSize(width: 1366, height: 1024)), ("1194×834", CGSize(width: 1194, height: 834)), ("1190×726", CGSize(width: 1190, height: 726)),
                                                ("1180×820", CGSize(width: 1180, height: 820)), ("1133×744", CGSize(width: 1133, height: 744)), ("1113×683", CGSize(width: 1113, height: 683)), ("1113×636", CGSize(width: 1113, height: 636)),
                                                ("1024×768", CGSize(width: 1024, height: 768)), ("900×600", CGSize(width: 900, height: 600)), ("834×1210", CGSize(width: 834, height: 1210)), ("814×1102", CGSize(width: 814, height: 1102)),
                                                ("768×1024", CGSize(width: 768, height: 1024)), ("744×1133", CGSize(width: 744, height: 1133)), ("700×900", CGSize(width: 700, height: 900)), ("600×900", CGSize(width: 600, height: 900)),
                                                ("500×900", CGSize(width: 500, height: 900)), ("300×700", CGSize(width: 300, height: 700))]
    func testTheColumnsAlignAtEveryPageLayoutAndTheFloorsFlagWhereTheArithmeticSays() {
        var lines: [String] = []
        for (name, size) in Self.pageSizes {
            let p = euclideousPageLayout(size: size)
            let panel = euclideousMixV2PanelSize(stripWidth: p.strip.width, laneBox: p.laneBox)
            let L = euclideousMixV2Layout(size: panel)
            XCTAssertGreaterThan(L.bandH, 0, name)
            for (n, b) in L.bands.enumerated() {
                let tag = "\(name) lane \(n + 1)"
                // play's x range is the pool's; HITS + STEPS' x range is the A–D toggles'
                close(b.play.minX, b.pool.minX, "\(tag): play starts at the pool's x"); close(b.play.maxX, b.pool.maxX, "\(tag): …and ends at its x")
                for r in [b.riff, b.notes] {
                    close(b.hitsBox.minX, r.outs.minX, "\(tag): HITS starts where A–D starts"); close(b.stepsBox.maxX, r.outs.maxX, "\(tag): STEPS ends where A–D ends")
                    close(b.stripFrame.minX, r.plate.minX, "\(tag): the strip frame's left edge is the plates' left edge")
                    if L.blockW >= 113 + 3 { close(b.stripFrame.maxX, r.oct.maxX, "\(tag): …and its right edge is the OCT control's right edge") }   // a panel narrower than 116 in the block (300×700, far under every floor) has no strip to align
                }
                // one top, one height
                close(b.play.minY, b.stripFrame.minY, "\(tag) play/strip top"); close(b.stripFrame.minY, b.hitsBox.minY, "\(tag) strip/HITS top"); close(b.hitsBox.minY, b.stepsBox.minY, "\(tag) HITS/STEPS top")
                close(b.play.height, b.stripFrame.height, "\(tag) play/strip height"); close(b.stripFrame.height, b.hitsBox.height, "\(tag) strip/HITS height"); close(b.hitsBox.height, b.stepsBox.height, "\(tag) HITS/STEPS height")
                XCTAssertEqual(b.play.height, 30, "\(tag)")
                // the column between the strip and the HITS box is the 6 pt gap above OCT → A–D
                if L.blockW >= 113 + 3 { close(b.hitsBox.minX - b.stripFrame.maxX, 6, "\(tag): the gap between the strip frame and HITS") }
            }
            XCTAssertEqual(L.floors.contains(.slider), L.sliderW < 72 - 1e-9, name); XCTAssertEqual(L.floors.contains(.row), L.rowH < 44 - 1e-9, name); XCTAssertEqual(L.floors.contains(.band), L.bandH < 140 - 1e-9, name)
            let pageFloors = euclideousPageFloors(box: p.box, laneBox: p.laneBox, stripWidth: p.strip.width)
            XCTAssertEqual(pageFloors.contains(.mixV2Slider), L.floors.contains(.slider), name); XCTAssertEqual(pageFloors.contains(.mixV2Row), L.floors.contains(.row), name); XCTAssertEqual(pageFloors.contains(.mixV2Band), L.floors.contains(.band), name)
            XCTAssertFalse(pageFloors.contains(.mixRowsRoll) || pageFloors.contains(.mixRowsRow) || pageFloors.contains(.mixRowsBand), "the retired layout's floors are not reported (\(name))")
            lines.append("MIXV2-LAYOUT \(name): panel \(String(format: "%.2f×%.2f", Double(panel.width), Double(panel.height))) | band \(String(format: "%.2f", Double(L.bandH))) row \(String(format: "%.2f", Double(L.rowH))) tile \(String(format: "%.2f", Double(L.tileH))) V \(String(format: "%.2f", Double(L.sliderW))) chip \(String(format: "%.2f", Double(L.chipH))) | play 56×30 · strip \(String(format: "%.2f", Double(L.bands[0].stripFrame.width)))×30 · HITS/STEPS 50×30 ×2 | pool 56×\(String(format: "%.2f", Double(L.bands[0].pool.height))) | floors \(L.floors)")
        }
        print(lines.joined(separator: "\n"))
    }

    // MARK: test 2 — the strip and its boxes

    func testTheStripCellsOfSection23() {
        typealias S = EuclideousMixV2StripMetrics
        XCTAssertEqual(euclideousMixV2CellLook(isHit: false, isCurrent: false), EuclideousMixV2CellLook(fill: .solid(hex: 0x2A2C33), bottomLine: false, glow: false), "empty")
        XCTAssertEqual(euclideousMixV2CellLook(isHit: false, isCurrent: true), EuclideousMixV2CellLook(fill: .solid(hex: 0x383B43), bottomLine: false, glow: false), "the current step on an empty step")
        XCTAssertEqual(euclideousMixV2CellLook(isHit: true, isCurrent: false), EuclideousMixV2CellLook(fill: .lane(alpha: 0.55), bottomLine: true, glow: false), "a hit: lane100 at 55 % with the bottom line")
        XCTAssertEqual(euclideousMixV2CellLook(isHit: true, isCurrent: true), EuclideousMixV2CellLook(fill: .lane(alpha: 1), bottomLine: false, glow: true), "the current step on a hit: solid with the glow")
        XCTAssertEqual(S.bottomLine, 2.5); XCTAssertEqual(S.glow, 8); XCTAssertEqual(S.gap, 2); XCTAssertEqual(S.radius, 4)
        // the steps fill the strip: 8 steps in the landscape reference's 493.33 wide steps area, 2 apart, 25 tall
        let b = euclideousMixV2Layout(size: landscape).bands[0]
        let cells = euclideousMixStripCells(strip: b.stripSteps, steps: 8, mode: .fit)
        XCTAssertEqual(cells.count, 8); close(cells[0].height, 25); close(cells[1].minX - cells[0].maxX, 2); close(cells.last!.maxX, b.stripSteps.maxX)
    }
    func testHitsAndStepsShowTheLanesCounts() {
        XCTAssertEqual(euclideousMixV2HitsStepsTexts(hits: 4, steps: 8).hits, "4"); XCTAssertEqual(euclideousMixV2HitsStepsTexts(hits: 4, steps: 8).steps, "8")
        XCTAssertEqual(euclideousMixV2HitsStepsTexts(hits: 0, steps: 16).hits, "0"); XCTAssertEqual(euclideousMixV2HitsLabel, "HITS"); XCTAssertEqual(euclideousMixV2StepsLabel, "STEPS")
    }

    // MARK: test 3 — pool and fork looks

    func testTheChipsNeverLightAndTheForkFollowsThePartsSwitch() {
        for chip in euclideousMixV2PoolChips(sortedPool: [48, 52, 55], name: { "N\($0)" }) { XCTAssertFalse(chip.lit, "rank \(chip.rank) never lights") }
        let chips = euclideousMixV2PoolChips(sortedPool: [], name: { _ in "x" }); XCTAssertEqual(chips.count, 8); XCTAssertTrue(chips.allSatisfy { $0.name == nil && !$0.lit }, "a rank with no note: the rank only")
        XCTAssertEqual(euclideousMixV2ForkAlpha(partOn: true), 0.70); XCTAssertEqual(euclideousMixV2ForkAlpha(partOn: false), 0.25)
    }

    // MARK: test 4 — the stack

    private func note(rank: UInt8, on: Double, end: Double?, outs: UInt8 = 0x01) -> NoteRollNote { NoteRollNote(onBeat: on, endBeat: end, pitch: 60, velocity: 100, outs: outs, rank: rank) }
    func testARiffNoteOfRankFourLightsCellFourFromNoteOnToNoteOff() {
        let n = [note(rank: 4, on: 2, end: 3)]
        XCTAssertEqual(euclideousMixV2StackCells(notes: n, nowBeat: 1.99), Array(repeating: .unlit, count: 8), "before the note-on")
        for t in [2.0, 2.5, 2.999] { let c = euclideousMixV2StackCells(notes: n, nowBeat: t); XCTAssertEqual(c[4], .lit, "rank 4 is cell index 4 (rank 8 on top)"); XCTAssertEqual(c.filter { $0 == .lit }.count, 1) }
        XCTAssertEqual(euclideousMixV2StackCells(notes: n, nowBeat: 3.0), Array(repeating: .unlit, count: 8), "from the note-off: no fade")
        XCTAssertEqual(euclideousMixV2StackCells(notes: [note(rank: 4, on: 2, end: nil)], nowBeat: 50)[4], .lit, "a held note stays lit until its off")
    }
    func testAChordOfRanksTwoAndFiveLightsBothAndASilentNoteOutlinesItsCell() {
        let chord = [note(rank: 2, on: 1, end: 2), note(rank: 5, on: 1, end: 2)]
        let c = euclideousMixV2StackCells(notes: chord, nowBeat: 1.5)
        XCTAssertEqual(c[8 - 2], .lit); XCTAssertEqual(c[8 - 5], .lit); XCTAssertEqual(c.filter { $0 == .lit }.count, 2)
        let silent = euclideousMixV2StackCells(notes: [note(rank: 7, on: 1, end: 2, outs: 0)], nowBeat: 1.5)
        XCTAssertEqual(silent[1], .silent, "a note routed nowhere outlines its cell (1 pt, no fill)"); XCTAssertEqual(silent.filter { $0 != .unlit }.count, 1)
        let both = euclideousMixV2StackCells(notes: [note(rank: 3, on: 1, end: 2, outs: 0), note(rank: 3, on: 1, end: 2)], nowBeat: 1.5)
        XCTAssertEqual(both[5], .lit, "a sounding note wins over a silent one on the same rank")
        XCTAssertEqual(euclideousMixV2PlayingRanks(notes: chord + [note(rank: 7, on: 1, end: 2, outs: 0)], nowBeat: 1.5), [2, 5], "VoiceOver names the ranks that SOUND (silent ones excluded)")
        XCTAssertEqual(euclideousMixV2StackCells(notes: [note(rank: 0, on: 1, end: 2)], nowBeat: 1.5), Array(repeating: .unlit, count: 8), "a note with no rank lights nothing")
    }
    func testTheStackFramesAndTheUnlitFills() {
        let b = euclideousMixV2Layout(size: landscape).bands[0]
        let f = euclideousMixV2StackFrames(tile: b.riff.stack)
        XCTAssertEqual(f.count, 8); close(f[0].height, 4.25, "cell height (41 − 7) ÷ 8 = 4.25"); close(f[1].minY - f[0].maxY, 1, "1 apart"); close(f[7].maxY, b.riff.stack.maxY); close(f[0].width, 30)
        XCTAssertEqual(EuclideousMixV2StackMetrics.unlitOnHex, 0x2A2C33); XCTAssertEqual(EuclideousMixV2StackMetrics.unlitOffHex, 0x202227)
    }

    // MARK: test 5 — TRANS (the pure half; the taps and the undo are the view's and the UI tests')

    func testTransposeStepsClampAtSevenAndTheTextUsesAMinusSign() {
        XCTAssertEqual(euclideousMixV2TransStep(0, up: true), 1); XCTAssertEqual(euclideousMixV2TransStep(0, up: false), -1)
        XCTAssertEqual(euclideousMixV2TransStep(7, up: true), 7, "clamped at +7"); XCTAssertEqual(euclideousMixV2TransStep(-7, up: false), -7, "clamped at −7")
        XCTAssertEqual(euclideousMixV2TransText(2), "+2"); XCTAssertEqual(euclideousMixV2TransText(0), "0"); XCTAssertEqual(euclideousMixV2TransText(-1), "\u{2212}1")
        // the upper half of the target steps up, the lower half down
        let b = euclideousMixV2Layout(size: landscape).bands[0]
        XCTAssertTrue(euclideousMixV2TransTapIsUp(y: 5, targetHeight: b.riff.transUpper.height * 2)); XCTAssertFalse(euclideousMixV2TransTapIsUp(y: 30, targetHeight: b.riff.transUpper.height * 2))
        // the spec's walk: +1 for an upper tap, −1 after two lower taps
        var v = 0; v = euclideousMixV2TransStep(v, up: true); XCTAssertEqual(v, 1); v = euclideousMixV2TransStep(v, up: false); v = euclideousMixV2TransStep(v, up: false); XCTAssertEqual(v, -1)
    }
    func testAHoldRepeatsEvery150MsAfter400() {
        XCTAssertEqual(euclideousMixV2TransRepeatSteps(heldFor: 0), 0); XCTAssertEqual(euclideousMixV2TransRepeatSteps(heldFor: 0.399), 0, "nothing before 400 ms")
        XCTAssertEqual(euclideousMixV2TransRepeatSteps(heldFor: 0.4), 1, "the first repeat at 400 ms"); XCTAssertEqual(euclideousMixV2TransRepeatSteps(heldFor: 0.549), 1)
        XCTAssertEqual(euclideousMixV2TransRepeatSteps(heldFor: 0.55), 2, "the second at 550 ms"); XCTAssertEqual(euclideousMixV2TransRepeatSteps(heldFor: 0.70), 3); XCTAssertEqual(euclideousMixV2TransRepeatSteps(heldFor: 1.0), 5)
    }

    // MARK: test 6 — OCT (the pure half, shared by every surface)

    func testFiveBoxesOneSelectedAndADragSelectsTheBoxUnderTheFinger() {
        XCTAssertEqual(euclideousOctLabels, ["\u{2212}2", "\u{2212}1", "0", "+1", "+2"])
        for v in -2...2 { XCTAssertEqual(euclideousOctSelectedIndex(value: v), v + 2); XCTAssertEqual(euclideousOctValue(index: v + 2), v) }
        XCTAssertEqual(euclideousOctSelectedIndex(value: 3), 4, "an old document's +3 shows the end box: still exactly one selected"); XCTAssertEqual(euclideousOctSelectedIndex(value: -3), 0)
        XCTAssertEqual((0..<5).map { euclideousOctIndex(x: CGFloat($0) * 22 + 11, width: 110) }, [0, 1, 2, 3, 4], "the box under x")
        XCTAssertEqual(euclideousOctIndex(x: -30, width: 110), 0); XCTAssertEqual(euclideousOctIndex(x: 400, width: 110), 4, "clamped to the ends"); XCTAssertEqual(euclideousOctIndex(x: 109.9, width: 110), 4)
        XCTAssertEqual(euclideousOctStep(2, up: true), 2); XCTAssertEqual(euclideousOctStep(-2, up: false), -2); XCTAssertEqual(euclideousOctStep(0, up: true), 1)
        XCTAssertEqual(euclideousOctLabelSize(boxHeight: 30), 9, "9 pt where the boxes are 28 or more tall"); XCTAssertEqual(euclideousOctLabelSize(boxHeight: 27.9), 8)
        XCTAssertEqual(euclideousOctValueText(-1), "\u{2212}1"); XCTAssertEqual(euclideousOctValueText(1), "+1"); XCTAssertEqual(euclideousOctValueText(0), "0")
        for r in euclideousMixV2Layout(size: landscape).bands[0].riff.octTargets { XCTAssertGreaterThanOrEqual(r.height, 44) }
    }

    // MARK: solo button, dims, lines, VoiceOver

    func testTheSoloButtonLooks() {
        XCTAssertEqual(euclideousMixV2SoloLook(latched: false, heldLook: false), EuclideousMixV2SoloLook(fillHex: nil, inkHex: 0x8A909A, border: true), "off: #1F2127 + a 1.5 pt #30333A border")
        XCTAssertEqual(euclideousMixV2SoloLook(latched: true, heldLook: false), EuclideousMixV2SoloLook(fillHex: 0xF2C230, inkHex: 0x0D0F14, border: false), "latched: yellow")
        XCTAssertEqual(euclideousMixV2SoloLook(latched: true, heldLook: true), EuclideousMixV2SoloLook(fillHex: 0xDFE3EA, inkHex: 0x0D0F14, border: false), "held: #DFE3EA, whatever the latch")
        XCTAssertEqual(euclideousMixV2SoloLook(latched: false, heldLook: true).fillHex, 0xDFE3EA)
    }
    func testDimsAreOne42PercentAndNeverStack() {
        let all: [EuclideousMixV2Element] = [.pool, .fork, .solo, .toggle, .stack, .vel, .gate, .trans, .oct, .outs]
        for e in all {
            XCTAssertEqual(euclideousMixV2Opacity(laneDimmed: true, partDimmed: true, element: e), 0.42, "a dimmed lane: everything below the strip, once (\(e))")
            XCTAssertEqual(euclideousMixV2Opacity(laneDimmed: true, partDimmed: false, element: e), 0.42)
            XCTAssertEqual(euclideousMixV2OwnOpacity(laneDimmed: true, partDimmed: true, element: e), 1, "inside a dimmed lane's group a part's own dim adds nothing (\(e))")
        }
        for e in [EuclideousMixV2Element.stack, .vel, .gate, .trans, .oct] { XCTAssertEqual(euclideousMixV2Opacity(laneDimmed: false, partDimmed: true, element: e), 0.42, "an off / solo-silenced part dims \(e)"); XCTAssertEqual(euclideousMixV2Opacity(laneDimmed: false, partDimmed: false, element: e), 1) }
        for e in [EuclideousMixV2Element.solo, .toggle, .outs, .pool, .fork] { XCTAssertEqual(euclideousMixV2Opacity(laneDimmed: false, partDimmed: true, element: e), 1, "S, the toggle and A–D keep full strength (\(e))") }
    }
    func testTheLinesRunFromEachRowsCentreToItsEmittersCentre() {
        let L = euclideousMixV2Layout(size: landscape)
        var masks = [UInt8](repeating: 0, count: 8); masks[0] = 0b0011; masks[3] = 0b1000     // lane 1 riff → A, B; lane 2 notes → D
        var on = [Bool](repeating: true, count: 8); on[3] = false
        let lines = euclideousMixV2Lines(layout: L, masks: masks, partOn: on)
        XCTAssertEqual(lines.count, 2, "a part that is off draws none")
        let a = lines[0]
        close(a.from.x, L.bandW); close(a.from.y, L.bands[0].inner.minY + L.bands[0].riff.centreY, "from the riff row's centre"); close(a.to.x, L.bandW + 40); close(a.to.y, L.emitters[0].midY)
        close(a.c1.x, L.bandW + 23); close(a.c1.y, a.from.y); close(a.c2.x, L.bandW + 18.5); close(a.c2.y, a.to.y)
    }
    func testVoiceOverStrings() {
        XCTAssertEqual(EuclideousMixV2AX.solo(notes: false, lane: 0), "Solo riff, lane 1"); XCTAssertEqual(EuclideousMixV2AX.solo(notes: true, lane: 3), "Solo notes, lane 4")
        XCTAssertEqual(EuclideousMixV2AX.soloValue(latched: true), "on"); XCTAssertEqual(EuclideousMixV2AX.soloHint, "Tap to latch; hold to solo while held")
        XCTAssertEqual(EuclideousMixV2AX.pool(lowest: "C3", highest: "E\u{266D}5"), "Pool, C3 to E\u{266D}5"); XCTAssertEqual(EuclideousMixV2AX.pool(lowest: nil, highest: nil), "Pool, empty")
        XCTAssertEqual(EuclideousMixV2AX.stack(notes: false, ranks: [4]), "Riff playing rank 4"); XCTAssertEqual(EuclideousMixV2AX.stack(notes: false, ranks: [2, 4, 6]), "Riff playing ranks 2, 4 and 6")
        XCTAssertEqual(EuclideousMixV2AX.stack(notes: true, ranks: [2, 5]), "Notes playing ranks 2 and 5"); XCTAssertEqual(EuclideousMixV2AX.stack(notes: false, ranks: []), "Riff silent")
        XCTAssertEqual(EuclideousMixV2AX.transpose(notes: false, value: 2), "Riff transpose +2"); XCTAssertEqual(EuclideousMixV2AX.octave(notes: true, value: 0), "Notes octave 0"); XCTAssertEqual(EuclideousMixV2AX.octave(notes: false, value: -1), "Riff octave \u{2212}1")
        XCTAssertEqual(euclideousMixStripSpoken(hits: 4, steps: 8), "Rhythm, 4 hits in 8 steps", "the strip's label already reads the hits and steps (B4.1)")
    }
}
