//  MixPanelTests.swift — MIX ROWS (2026-11-03) §12 tests 1–6 (+ the strings and the floor integration): the panel's frames at both references, the sliders, the rhythm strip, the pool, the lines and the roll — every number the views
//  draw comes from `MixPanel.swift`, so they are held to the spec's own arithmetic HERE, written out independently of the code under test. The lane area is 769.33 wide in the code (Paul's 2026-10-30 choice), not the spec's 753.33,
//  so the landscape numbers below are the spec's formulas at the code's width.

import XCTest

final class MixPanelTests: XCTestCase {
    private func close(_ a: CGFloat, _ b: CGFloat, _ msg: String = "", line: UInt = #line) { XCTAssertEqual(Double(a), Double(b), accuracy: 0.01, msg, line: line) }
    private func rect(_ r: CGRect, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ msg: String = "", line: UInt = #line) {
        close(r.minX, x, "\(msg) x", line: line); close(r.minY, y, "\(msg) y", line: line); close(r.width, w, "\(msg) w", line: line); close(r.height, h, "\(msg) h", line: line)
    }

    // MARK: test 1 — layout

    /// The spec's §2 formulas applied to a panel size, independently of `euclideousMixRowsLayout`.
    private func check(_ size: CGSize, _ name: String) {
        let L = euclideousMixRowsLayout(size: size)
        let bandW: CGFloat = size.width - 76
        let bandH: CGFloat = (size.height - 24) / 4
        let innerW: CGFloat = bandW - 16
        let innerH: CGFloat = bandH - 16
        let rowH: CGFloat = (innerH - 42) / 2
        let R: CGFloat = innerW - 514
        close(L.bandW, bandW, name); close(L.bandH, bandH, name); close(L.innerW, innerW, name); close(L.innerH, innerH, name); close(L.rowH, rowH, name); close(L.rollW, R, name)
        rect(L.emitterColumn, bandW, 0, 76, size.height, "\(name) emitter column")
        XCTAssertEqual(L.bands.count, 4)
        for n in 0..<4 {
            let b = L.bands[n]
            let top: CGFloat = CGFloat(n) * (bandH + 8)
            let ox: CGFloat = 8
            let oy: CGFloat = top + 8
            rect(b.frame, 0, top, bandW, bandH, "\(name) band \(n + 1)")
            rect(b.inner, ox, oy, innerW, innerH, "\(name) inner \(n + 1)")
            rect(b.play, ox, oy, 60, 24, "\(name) play"); rect(b.playTarget, ox, oy, 60, 32, "\(name) play target")
            let stripW: CGFloat = innerW - 126 - 68
            rect(b.strip, ox + 68, oy, max(0, stripW), 24, "\(name) strip"); rect(b.stripWithBadge, ox + 68, oy, max(0, stripW - 30), 24, "\(name) strip with the badge")
            let soloX: CGFloat = ox + innerW - 120
            rect(b.solo, soloX, oy, 120, 24, "\(name) solo"); rect(b.soloTarget, soloX, oy, 120, 36, "\(name) solo target")
            rect(b.badge, soloX - 6 - 24, oy, 24, 24, "\(name) badge")
            rect(b.pool, ox, oy + 32, 60, innerH - 32, "\(name) pool")
            let rows: [(Bool, EuclideousMixRowFrames)] = [(false, b.riff), (true, b.notes)]
            for (isNotes, row) in rows {
                let y: CGFloat = oy + (isNotes ? 42 + rowH : 36)
                rect(row.frame, ox + 68, y, innerW - 68, rowH, "\(name) row")
                rect(row.toggle, ox + 68, y, 48, rowH, "\(name) toggle")
                let rollX: CGFloat = ox + 68 + 48 + 6
                rect(row.roll, rollX, y, max(0, R), rowH, "\(name) roll")   // a roll too narrow for the panel is drawn empty (and the floor flags it), never negative
                for k in 0..<4 {
                    let sx: CGFloat = rollX + R + 6 + CGFloat(k) * 66
                    rect(row.sliders[k], sx, y, 62, rowH, "\(name) slider \(k)")
                }
                rect(row.outs, soloX, y, 120, rowH, "\(name) outs")
                for k in 0..<4 { rect(row.outButtons[k], soloX + CGFloat(k) * 30, y, 30, rowH, "\(name) out \(k)") }
                close(row.frame.maxX, ox + innerW, "\(name) the row ends at the inner edge")
            }
            // emitter n: 36 pt at x 40…76 of the column, centred between lane n's two rows
            let cy: CGFloat = top + 8 + 36 + rowH + 3
            rect(L.emitters[n], bandW + 40, cy - 18, 36, 36, "\(name) emitter \(n + 1)")
            close(L.emitters[n].midY, (b.riff.frame.maxY + b.notes.frame.minY) / 2, "\(name) between the two rows")
        }
    }
    func testTheLayoutAtTheLandscapeReference() {
        let size = CGSize(width: 769.333333, height: 610)
        check(size, "landscape"); let L = euclideousMixRowsLayout(size: size)
        close(L.bandW, 693.33); close(L.bandH, 146.5); close(L.innerW, 677.33); close(L.innerH, 130.5); close(L.rowH, 44.25); close(L.rollW, 163.33)
        close(L.bands[0].strip.width, 483.33, "the strip: 467.33 in the spec at its 753.33 width"); close(L.emitters[0].midY, 91.25, "the spec's 91.25")
        close(EuclideousMixRowsLayoutTesting.poolChipH(L), 10.5625, "chipH 10.56")
        XCTAssertEqual(L.floors, [], "no floor flags at the reference")
    }
    func testTheLayoutAtThePortraitReference() {
        let size = CGSize(width: 782, height: 611.333333)
        check(size, "portrait"); let L = euclideousMixRowsLayout(size: size)
        close(L.bandW, 706); close(L.bandH, 146.83); close(L.innerW, 690); close(L.innerH, 130.83); close(L.rowH, 44.42); close(L.rollW, 176)
        close(L.bands[0].strip.width, 496, "the spec's 496"); XCTAssertEqual(L.floors, [])
    }
    func testThePanelSizeIsTheLaneCardsTwoByTwoBox() {
        let p = euclideousPageLayout(size: CGSize(width: 1190, height: 726), headerKind: .a)
        let s = euclideousMixRowsPanelSize(stripWidth: p.strip.width, laneBox: p.laneBox)
        close(s.width, 769.33); close(s.height, 610, "two cards (301) and the gap (8)")
        let q = euclideousPageLayout(size: CGSize(width: 814, height: 1102), headerKind: .b)
        let t = euclideousMixRowsPanelSize(stripWidth: q.strip.width, laneBox: q.laneBox)
        close(t.width, 782); close(t.height, 611.33)
    }
    /// The layouts the page is tested at (the TAB STRIP ferry's table — "layout 5.3" has no list of its own): the formulas hold everywhere, nothing is negative, and a floor flags exactly where the arithmetic says. Printed for the status log.
    func testTheLayoutAtEveryPageLayoutAndWhereTheFloorsFlag() {
        let sizes: [(String, CGSize)] = [("1376×1032", CGSize(width: 1376, height: 1032)), ("1366×1024", CGSize(width: 1366, height: 1024)), ("1194×834", CGSize(width: 1194, height: 834)), ("1190×726", CGSize(width: 1190, height: 726)),
                                         ("1180×820", CGSize(width: 1180, height: 820)), ("1133×744", CGSize(width: 1133, height: 744)), ("1113×683", CGSize(width: 1113, height: 683)), ("1113×636", CGSize(width: 1113, height: 636)),
                                         ("1024×768", CGSize(width: 1024, height: 768)), ("900×600", CGSize(width: 900, height: 600)), ("834×1210", CGSize(width: 834, height: 1210)), ("814×1102", CGSize(width: 814, height: 1102)),
                                         ("768×1024", CGSize(width: 768, height: 1024)), ("744×1133", CGSize(width: 744, height: 1133)), ("700×900", CGSize(width: 700, height: 900)), ("600×900", CGSize(width: 600, height: 900)),
                                         ("500×900", CGSize(width: 500, height: 900)), ("300×700", CGSize(width: 300, height: 700))]
        var lines: [String] = []
        for (name, size) in sizes {
            let p = euclideousPageLayout(size: size)
            let panel = euclideousMixRowsPanelSize(stripWidth: p.strip.width, laneBox: p.laneBox)
            let L = euclideousMixRowsLayout(size: panel)
            check(panel, name)
            XCTAssertGreaterThan(L.bandH, 0, name)
            XCTAssertEqual(L.floors.contains(.roll), L.rollW < 96 - 1e-9, name); XCTAssertEqual(L.floors.contains(.row), L.rowH < 40 - 1e-9, name); XCTAssertEqual(L.floors.contains(.band), L.bandH < 120 - 1e-9, name)
            let pageFloors = euclideousPageFloors(box: p.box, laneBox: p.laneBox, stripWidth: p.strip.width)
            XCTAssertEqual(pageFloors.contains(.mixRowsRoll), L.floors.contains(.roll), name); XCTAssertEqual(pageFloors.contains(.mixRowsRow), L.floors.contains(.row), name); XCTAssertEqual(pageFloors.contains(.mixRowsBand), L.floors.contains(.band), name)
            lines.append("MIXROWS-LAYOUT \(name): panel \(String(format: "%.2f×%.2f", Double(panel.width), Double(panel.height))) | band \(String(format: "%.2f", Double(L.bandH))) row \(String(format: "%.2f", Double(L.rowH))) roll \(String(format: "%.2f", Double(L.rollW))) | floors \(L.floors)")
        }
        print(lines.joined(separator: "\n"))
    }

    // MARK: test 2 — the sliders

    func testTheSliderGeometryAtTheMinimumDefaultAndMaximum() {
        let tile = CGRect(x: 100, y: 50, width: 62, height: 44.25)
        for kind in EuclideousMixSliderKind.allCases {
            let r = kind.range
            for v in [r.lowerBound, kind.defaultValue, r.upperBound] {
                let g = euclideousMixSliderGeometry(tile: tile, kind: kind, value: v)
                rect(g.track, 106, 50 + 44.25 - 6 - 3, 50, 3, "\(kind) track")
                let t = CGFloat(v - r.lowerBound) / CGFloat(r.upperBound - r.lowerBound)
                close(g.thumb.midX, 106 + t * 50, "\(kind) \(v) thumb"); close(g.thumb.width, 10); close(g.thumb.height, 10); close(g.thumb.midY, g.track.midY)
                if kind.isBipolar {
                    guard let tick = g.tick else { return XCTFail("\(kind): a bipolar track has a centre tick") }
                    rect(tick, 131 - 0.5, g.track.midY - 4, 1, 8, "\(kind) tick")
                    close(g.fill.minX, min(131, g.thumb.midX), "\(kind) \(v) the fill runs from the centre"); close(g.fill.width, abs(g.thumb.midX - 131), "\(kind) \(v)")
                } else {
                    XCTAssertNil(g.tick); close(g.fill.minX, 106); close(g.fill.width, t * 50, "\(kind) \(v) fills from the left")
                }
            }
        }
        // the bipolar ones at 0 have no fill at all and the thumb on the tick; at the extremes the fill spans half the track
        let t0 = euclideousMixSliderGeometry(tile: tile, kind: .transpose, value: 0); close(t0.fill.width, 0); close(t0.thumb.midX, 131)
        close(euclideousMixSliderGeometry(tile: tile, kind: .octave, value: 2).fill.width, 25); close(euclideousMixSliderGeometry(tile: tile, kind: .octave, value: -2).fill.width, 25)
    }
    func testASliderDragIsRelativeAndTheTrackWidthSpansTheFullRange() {
        for kind in EuclideousMixSliderKind.allCases {
            let r = kind.range
            XCTAssertEqual(euclideousMixSliderDrag(kind: kind, startValue: r.lowerBound, translation: 50, trackWidth: 50), r.upperBound, "\(kind): the track's width from the bottom reaches the top")
            XCTAssertEqual(euclideousMixSliderDrag(kind: kind, startValue: r.upperBound, translation: -50, trackWidth: 50), r.lowerBound, "\(kind): …and back")
            XCTAssertEqual(euclideousMixSliderDrag(kind: kind, startValue: kind.defaultValue, translation: 0, trackWidth: 50), kind.defaultValue, "\(kind): no movement, no change")
            XCTAssertEqual(euclideousMixSliderDrag(kind: kind, startValue: r.lowerBound, translation: 500, trackWidth: 50), r.upperBound, "\(kind): clamped")
        }
        XCTAssertEqual(euclideousMixSliderDrag(kind: .velocity, startValue: 40, translation: 25, trackWidth: 50), 40 + 63, "relative: half the track moves VEL half its range from WHERE IT STARTED")
        XCTAssertEqual(euclideousMixSliderDrag(kind: .gate, startValue: 90, translation: -10, trackWidth: 50), 90 - 20, "GATE 1…99: 10 pt of 50 is a fifth of 98")
    }
    func testTransposeAndOctaveSnapToWholeStepsAsTheDragCrossesEach() {
        let step = 50.0 / 14.0     // TRANS: 14 steps along 50 pt
        func trans(_ dx: Double) -> Int { euclideousMixSliderDrag(kind: .transpose, startValue: 0, translation: CGFloat(dx), trackWidth: 50) }
        XCTAssertEqual(trans(0.49 * step), 0); XCTAssertEqual(trans(0.51 * step), 1, "the half step is where it crosses"); XCTAssertEqual(trans(1.4 * step), 1); XCTAssertEqual(trans(1.6 * step), 2)
        XCTAssertEqual(trans(-0.51 * step), -1); XCTAssertEqual(trans(-6.6 * step), -7)
        let oct = 50.0 / 4.0
        XCTAssertEqual(euclideousMixSliderDrag(kind: .octave, startValue: 0, translation: CGFloat(0.6 * oct), trackWidth: 50), 1)
        XCTAssertEqual(euclideousMixSliderDrag(kind: .octave, startValue: 0, translation: CGFloat(-1.6 * oct), trackWidth: 50), -2)
    }
    func testTheSliderTexts() {
        XCTAssertEqual(euclideousMixSliderText(kind: .velocity, value: 100), "100"); XCTAssertEqual(euclideousMixSliderText(kind: .gate, value: 90), "90%")
        XCTAssertEqual(euclideousMixSliderText(kind: .transpose, value: 2), "+2"); XCTAssertEqual(euclideousMixSliderText(kind: .octave, value: 0), "0")
        XCTAssertEqual(euclideousMixSliderText(kind: .octave, value: -1), "\u{2212}1", "U+2212, not a hyphen"); XCTAssertEqual(EuclideousMixSliderKind.allCases.map { $0.label }, ["VEL", "GATE", "TRANS", "OCT"])
    }
    func testTheSlidersWriteTheFieldsTheCardBacksPadsWroteAndNothingElse() {
        // RIFF: VEL / GATE through the sliders' own commit — the first edit PINS the notes layer; TRANS is riffOutTranspose (NOT melodyTranspose); OCT is riffOctave
        var l = EuclidLine()
        XCTAssertEqual(euclideousMixSliderValue(of: l, kind: .velocity, notes: false), 100); XCTAssertEqual(euclideousMixSliderValue(of: l, kind: .gate, notes: false), 90)
        XCTAssertEqual(euclideousMixSliderValue(of: l, kind: .transpose, notes: false), 0); XCTAssertEqual(euclideousMixSliderValue(of: l, kind: .octave, notes: false), 0)
        euclideousMixSliderWrite(&l, kind: .velocity, notes: false, value: 64)
        XCTAssertEqual(l.velocityAbsoluteResolved, 64); XCTAssertEqual(l.notesVelocity, 100, "the notes layer was PINNED at its old value, so the two now part (card back 6.3)")
        euclideousMixSliderWrite(&l, kind: .gate, notes: false, value: 40); XCTAssertEqual(l.gateResolved, 0.4, accuracy: 1e-9); XCTAssertEqual(l.notesGate ?? 0, 0.9, accuracy: 1e-9)
        euclideousMixSliderWrite(&l, kind: .transpose, notes: false, value: 3); XCTAssertEqual(l.riffOutTranspose, 3); XCTAssertNil(l.melodyTranspose, "not the RIFF tab's TRANS")
        euclideousMixSliderWrite(&l, kind: .octave, notes: false, value: -2); XCTAssertEqual(l.riffOctave, -2)
        euclideousMixSliderWrite(&l, kind: .transpose, notes: false, value: 0); XCTAssertNil(l.riffOutTranspose, "0 is stored as nil, so a part put back home leaves the document as it was")
        // NOTES: straight into the notes layer's own fields; OCT into `octave` WITHOUT switching the part on
        var n = EuclidLine(); n.notesOn = false
        euclideousMixSliderWrite(&n, kind: .velocity, notes: true, value: 33); XCTAssertEqual(n.notesVelocity, 33); XCTAssertEqual(n.velocityAbsoluteResolved, 100, "the riff's VEL is untouched")
        euclideousMixSliderWrite(&n, kind: .gate, notes: true, value: 55); XCTAssertEqual(n.notesGate ?? 0, 0.55, accuracy: 1e-9)
        euclideousMixSliderWrite(&n, kind: .octave, notes: true, value: 2); XCTAssertEqual(n.octave, 2); XCTAssertFalse(n.notesOnResolved, "a slider on an OFF part must not turn it on")
        euclideousMixSliderWrite(&n, kind: .transpose, notes: true, value: -5); XCTAssertEqual(n.notesOutTranspose, -5)
        for k in EuclideousMixSliderKind.allCases { XCTAssertEqual(euclideousMixSliderValue(of: n, kind: k, notes: true), [33, 55, -5, 2][k.rawValue]) }
        // the range clamps the write
        euclideousMixSliderWrite(&n, kind: .gate, notes: true, value: 100); XCTAssertEqual(n.notesGate ?? 0, euclideousLaneGateMax, accuracy: 1e-9, "never legato")
        euclideousMixSliderWrite(&n, kind: .transpose, notes: true, value: 99); XCTAssertEqual(n.notesOutTranspose, 7)
    }
    func testADoubleTapSetsTheDefaults() {
        var l = EuclidLine(); l.velocityAbsolute = 30; l.gate = 0.2; l.riffOutTranspose = 4; l.riffOctave = 2
        for k in EuclideousMixSliderKind.allCases { euclideousMixSliderReset(&l, kind: k, notes: false) }
        XCTAssertEqual([EuclideousMixSliderKind.velocity, .gate, .transpose, .octave].map { euclideousMixSliderValue(of: l, kind: $0, notes: false) }, [100, 90, 0, 0], "VEL 100, GATE 90%, TRANS 0, OCT 0")
        var n = EuclidLine(); n.notesVelocity = 20; n.notesGate = 0.1; n.notesOutTranspose = -3; n.octave = -1
        for k in EuclideousMixSliderKind.allCases { euclideousMixSliderReset(&n, kind: k, notes: true) }
        XCTAssertEqual([EuclideousMixSliderKind.velocity, .gate, .transpose, .octave].map { euclideousMixSliderValue(of: n, kind: $0, notes: true) }, [100, 90, 0, 0])
        XCTAssertEqual(EuclideousMixSliderKind.allCases.map { $0.defaultValue }, [100, 90, 0, 0])
    }
    func testVoiceOverStepsBySliderUnitsAndClamps() {
        XCTAssertEqual(euclideousMixSliderStep(kind: .velocity, value: 100, up: true), 101); XCTAssertEqual(euclideousMixSliderStep(kind: .gate, value: 90, up: false), 89)
        XCTAssertEqual(euclideousMixSliderStep(kind: .octave, value: 2, up: true), 2); XCTAssertEqual(euclideousMixSliderStep(kind: .transpose, value: -7, up: false), -7)
    }

    // MARK: test 3 — the rhythm strip

    private func hits(_ n: Int, at: Set<Int>) -> [EuclideousStripHit] {
        (0..<n).map { i in var h = EuclideousStripHit(); if at.contains(i) { h.kind = .hit; h.chip = EuclideousStripChip(rank: 3, column: i + 5, hollow: false, grey: false) }; return h }
    }
    func testEightStepsWithFourHitsGiveEightCellsAndNoNumberOnAnyOfThem() {
        let steps = euclideousMixStripSteps(hits: hits(8, at: [0, 2, 4, 6]))
        XCTAssertEqual(steps.count, 8); XCTAssertEqual(steps.map { $0.isHit }, [true, false, true, false, true, false, true, false]); XCTAssertEqual(steps.filter { $0.isHit }.count, 4)
        // AMENDMENT 1: a hit wears NO number on MIX (the card's riff-column numbers are not shown here), whatever the hit reads
        XCTAssertEqual(MemoryLayout<EuclideousMixStripStep>.size, 1, "a step is a hit or not — nothing else (no label)")
        let strip = CGRect(x: 76, y: 8, width: 483.333333, height: 24)
        let cells = euclideousMixStripCells(strip: strip, steps: 8, mode: .fit)
        XCTAssertEqual(cells.count, 8); let w = (483.333333 - 7 * 2) / 8
        for (i, c) in cells.enumerated() { close(c.width, CGFloat(w)); close(c.height, 24); close(c.minX, 76 + CGFloat(i) * CGFloat(w + 2)) }
        close(cells.last!.maxX, strip.maxX, "the cells span the strip")
        var gap = hits(4, at: [1, 3]); gap[1].kind = .gap
        XCTAssertEqual(euclideousMixStripSteps(hits: gap).map { $0.isHit }, [false, true, false, true], "a hit on a riff rest is still a hit")
    }
    func testSixteenStepsFitSixteenCellsAndAlignedPutsAnEightStepLaneOnTheSixteenColumnGrid() {
        let strip = CGRect(x: 0, y: 0, width: 483.333333, height: 24)
        let c16 = euclideousMixStripCells(strip: strip, steps: 16, mode: .fit); XCTAssertEqual(c16.count, 16); close(c16[0].width, (483.333333 - 15 * 2) / 16)
        let aligned8 = euclideousMixStripCells(strip: strip, steps: 8, mode: .aligned)
        XCTAssertEqual(aligned8.count, 8); for c in aligned8 { close(c.width, (483.333333 - 15 * 2) / 16, "an 8-step lane's cells at the 16-column width") }
        for i in 0..<8 { close(aligned8[i].minX, c16[i].minX, "…at the same x as the 16-step lane's, so steps line up across lanes") }
        let over = euclideousMixStripCells(strip: strip, steps: 20, mode: .aligned)
        XCTAssertEqual(over.count, 20); close(over[0].width, (483.333333 - 19 * 2) / 20, "a lane longer than 16 falls back to FIT"); close(over.last!.maxX, strip.maxX)
        XCTAssertEqual(euclideousMixStripCells(strip: strip, steps: 1, mode: .fit).count, 1); XCTAssertEqual(EuclideousMixStripMode(rawValue: "ALIGNED"), .aligned)
    }
    func testTheCellLooksAndTheCurrentStep() {
        // AMENDMENT 1 (§A1, tests 3 / 9): empty #25272D · hit lane100 @ 25 % + the bottom line · the current hit solid lane100 · the current empty step #2E3138 — and no number on any cell
        let empty = euclideousMixCellLook(isHit: false, isCurrent: false), hit = euclideousMixCellLook(isHit: true, isCurrent: false)
        XCTAssertEqual(empty.fill, .solid(hex: 0x25272D)); XCTAssertFalse(empty.bottomLine)
        XCTAssertEqual(hit.fill, .lane(alpha: 0.25)); XCTAssertTrue(hit.bottomLine)
        let curHit = euclideousMixCellLook(isHit: true, isCurrent: true), curEmpty = euclideousMixCellLook(isHit: false, isCurrent: true)
        XCTAssertEqual(curHit.fill, .lane(alpha: 1), "the current hit fills solid lane100"); XCTAssertFalse(curHit.bottomLine, "…with nothing else on it")
        XCTAssertEqual(curEmpty.fill, .solid(hex: 0x2E3138), "the current empty step only slightly lightens"); XCTAssertFalse(curEmpty.bottomLine)
        XCTAssertEqual(EuclideousMixStripMetrics.emptyHex, 0x25272D); XCTAssertEqual(EuclideousMixStripMetrics.currentEmptyHex, 0x2E3138)
        // which step is current: FWD reads the buffer in order, BKW from the end, PING-PONG bounces; the whole number is the step, wrapped; nothing while stopped
        XCTAssertEqual(euclideousMixStripCurrent(raw: 2.7, steps: 8, dir: .fwd, running: true), 2); XCTAssertEqual(euclideousMixStripCurrent(raw: 10.2, steps: 8, dir: .fwd, running: true), 2, "wraps")
        XCTAssertEqual(euclideousMixStripCurrent(raw: 2.7, steps: 8, dir: .bkw, running: true), 5)
        XCTAssertEqual(euclideousMixStripCurrent(raw: 9.2, steps: 8, dir: .pingpong, running: true), 6, "the way back")
        XCTAssertNil(euclideousMixStripCurrent(raw: 2.7, steps: 8, dir: .fwd, running: false), "no current step while the transport is stopped")
        XCTAssertEqual(euclideousMixStripSpoken(hits: 4, steps: 8), "Rhythm, 4 hits in 8 steps"); XCTAssertEqual(euclideousMixStripSpoken(hits: 1, steps: 8), "Rhythm, 1 hit in 8 steps")
    }

    // MARK: test 4 — the pool

    private func note(on: Double, end: Double?, rank: Int, outs: UInt8 = 1, pitch: UInt8 = 60) -> NoteRollNote { NoteRollNote(onBeat: on, endBeat: end, pitch: pitch, velocity: 90, outs: outs, rank: UInt8(rank)) }
    func testANoteOnOfRankFiveLightsChipFiveUntilItsNoteOff() {
        let n = [note(on: 1, end: 2, rank: 5)]
        XCTAssertEqual(euclideousMixLitRanks(parts: [n], nowBeat: 0.9), 0, "not yet")
        XCTAssertEqual(euclideousMixLitRanks(parts: [n], nowBeat: 1.0), 1 << 4); XCTAssertEqual(euclideousMixLitRanks(parts: [n], nowBeat: 1.99), 1 << 4)
        XCTAssertEqual(euclideousMixLitRanks(parts: [n], nowBeat: 2.0), 0, "until its note-off")
        XCTAssertEqual(euclideousMixLitRanks(parts: [[note(on: 1, end: nil, rank: 3)]], nowBeat: 50), 1 << 2, "a held note stays lit until its end arrives")
        XCTAssertEqual(euclideousMixLitRanks(parts: [[note(on: 1, end: 2, rank: 7, outs: 0)]], nowBeat: 1.5), 1 << 6, "a note routed nowhere lights its chip too")
        XCTAssertEqual(euclideousMixLitRanks(parts: [[note(on: 1, end: 2, rank: 2)], [note(on: 1, end: 2, rank: 8)]], nowBeat: 1.5), (1 << 1) | (1 << 7), "either part of the lane")
        XCTAssertEqual(euclideousMixLitRanks(parts: [[note(on: 1, end: 2, rank: 0)]], nowBeat: 1.5), 0, "an unplaced note lights nothing")
        // a CHORD extra (or a ratchet / ROLL / RUN strike) carries the rank of the note it came from, so it lights THAT chip — the feed's rank is all the chip reads
        XCTAssertEqual(euclideousMixLitRanks(parts: [[note(on: 1, end: 1.2, rank: 3, pitch: 67)]], nowBeat: 1.1), 1 << 2)
    }
    func testThePoolChipsAreRankEightAtTheTopAndARankWithNoNoteShowsTheRankOnly() {
        let name: (Int) -> String = { "N\($0)" }
        let chips = euclideousMixPoolChips(sortedPool: [60, 64, 67], lit: 0b0001_0000, name: name)
        XCTAssertEqual(chips.map { $0.rank }, [8, 7, 6, 5, 4, 3, 2, 1], "rank 8 at the top")
        XCTAssertEqual(chips.map { $0.name }, ["N88", "N84", "N79", "N76", "N72", "N67", "N64", "N60"], "the octave copies the riff grid's labels already name (the one derivation)")
        XCTAssertEqual(chips.filter { $0.lit }.map { $0.rank }, [5]); XCTAssertTrue(chips.allSatisfy { !$0.faded })
        let empty = euclideousMixPoolChips(sortedPool: [], lit: 0, name: name)
        XCTAssertEqual(empty.count, 8); XCTAssertTrue(empty.allSatisfy { $0.name == nil && $0.faded }, "an empty pool: the rank only, the chip at 40 %")
        // the chips are the SAME derivation POOL's NOW / the NOTES keys / the grid labels draw
        let specs = euclideousRankChips(sortedPool: [60, 64, 67], litMask: 0, name: name)
        XCTAssertEqual(chips.reversed().map { $0.name }, specs.map { $0.name })
        let frames = euclideousMixPoolFrames(area: CGRect(x: 8, y: 40, width: 60, height: 98.5))
        XCTAssertEqual(frames.count, 8); close(frames[0].height, (98.5 - 14) / 8); close(frames[1].minY - frames[0].maxY, 2); close(frames[7].maxY, 138.5, "the chips fill the pool area")
        XCTAssertEqual(euclideousMixPoolSpoken(litNames: []), "Pool, silent"); XCTAssertEqual(euclideousMixPoolSpoken(litNames: ["E3"]), "Pool, sounding E3")
    }

    // MARK: test 10 (§A3) — the chip text is the riff grid label's style, from one source, at two sizes

    func testTheChipTextAndTheGridLabelReadTheirStylesFromOneSourceAtTwoSizes() {
        typealias S = EuclideousRankLabelStyle
        let grid = S.grid, ref = S.mixChip(chipHeight: S.mixChipReferenceHeight)
        XCTAssertEqual([grid.noteSize, grid.octaveSize, grid.rankSize, grid.inset], [15, 10, 8, 3], "the riff grid's side label as it was drawn before the style was named")
        XCTAssertEqual([ref.noteSize, ref.rankSize, ref.rankRaise, ref.rankGap, ref.inset], [8, 5.5, 2, 2, 5], "the landscape reference: name 8, rank 5.5 raised 2, 2 before the name, 5 pt in")
        close(ref.octaveSize, 8 * 10 / 15, "the octave keeps the label's 10 : 15 against the note")
        // two sizes: every length scales together, the inset (left-aligned 5 pt in) and the weights do not
        let big = S.mixChip(chipHeight: S.mixChipReferenceHeight * 2)
        close(big.noteSize, 16); close(big.octaveSize, ref.octaveSize * 2); close(big.rankSize, 11); close(big.rankRaise, 4); close(big.rankGap, 4); XCTAssertEqual(big.inset, 5)
        XCTAssertEqual([S.noteWeight, S.octaveWeight, S.rankWeight], [.heavy, .bold, .bold], "name heavy, its octave bold, the rank bold — the label's weights")
        XCTAssertEqual(S.rankAlphaFactor, 0.7, "the rank is the name's colour at 70 %")
        // flats and sharps: the same split wherever the name is drawn — the glyph stays a character of the note part
        for n in ["B\u{266D}3", "C\u{266F}4", "E\u{266D}-1", "G2"] {
            XCTAssertEqual(grid.parts(of: n).note, ref.parts(of: n).note); XCTAssertEqual(grid.parts(of: n).octave, big.parts(of: n).octave)
            XCTAssertEqual(grid.parts(of: n).note, euclideousSplitNoteOctave(n).note)
        }
        XCTAssertEqual(ref.parts(of: "B\u{266D}3").note, "B\u{266D}"); XCTAssertEqual(ref.parts(of: "B\u{266D}3").octave, "3")
        XCTAssertEqual(ref.parts(of: "E\u{266D}-1").octave, "-1")
        // where the runs start: left-aligned 5 pt in, the rank first, the name 2 pt after its width
        let f = CGRect(x: 40, y: 10, width: 60, height: S.mixChipReferenceHeight)
        let at = euclideousMixChipTextLayout(frame: f, rankWidth: 3.3, style: ref)
        close(at.rankX, 45); close(at.nameX, 45 + 3.3 + 2); close(at.rankRaise, 2)
        // the chip's colours: idle #1F2127; lit takes the lane colour with ink #0D0F14 for name AND rank (the rank at 70 % of it)
        XCTAssertEqual(EuclideousMixPoolMetrics.idleHex, 0x1F2127); XCTAssertEqual(EuclideousMixPoolMetrics.litTextHex, 0x0D0F14)
        XCTAssertEqual(EuclideousMixPoolMetrics.fadedAlpha, 0.4, "a rank with no note: the rank only, at 40 %")
    }

    // MARK: test 5 — the lines

    private func fresh() -> (EuclideousMixRowsLayout, [UInt8], [Bool]) {
        (euclideousMixRowsLayout(size: CGSize(width: 769.333333, height: 610)), (0..<8).map { UInt8(1) << UInt8($0 / 2) }, Array(repeating: true, count: 8))
    }
    func testAFreshSessionDrawsLaneNToOutputNFromBothRows() {
        let (L, masks, on) = fresh()
        let lines = euclideousMixLines(layout: L, masks: masks, partOn: on)
        XCTAssertEqual(lines.count, 8); XCTAssertEqual(Set(lines.map { $0.lane * 10 + $0.output }), Set([0, 11, 22, 33].map { $0 }), "lane n → output n")
        XCTAssertEqual(lines.filter { $0.lane == 2 }.map { $0.output }, [2, 2])
        XCTAssertEqual(euclideousMixOriginDots(lines: lines).count, 8, "an origin dot for each part that draws a line")
    }
    func testLaneTwosNotesRoutedToAAndBGiveTwoLinesWithTheSpecsControlPoints() {
        var (L, masks, on) = fresh()
        masks[3] = 0b0011                                       // lane 2's notes (part 3) → A and B
        let lines = euclideousMixLines(layout: L, masks: masks, partOn: on).filter { $0.part == 3 }
        XCTAssertEqual(lines.map { $0.output }, [0, 1])
        let y0 = L.bands[1].notes.frame.midY
        for l in lines {
            let y1 = L.emitters[l.output].midY
            XCTAssertEqual(l.from, CGPoint(x: L.bandW, y: y0)); XCTAssertEqual(l.to, CGPoint(x: L.bandW + 40, y: y1))
            XCTAssertEqual(l.c1, CGPoint(x: L.bandW + 23, y: y0)); XCTAssertEqual(l.c2, CGPoint(x: L.bandW + 18.5, y: y1))
        }
        close(lines[0].from.y, L.bands[1].frame.minY + 8 + 42 + L.rowH + L.rowH / 2, "from the notes row's centre")
        on[3] = false
        XCTAssertTrue(euclideousMixLines(layout: L, masks: masks, partOn: on).filter { $0.part == 3 }.isEmpty, "turning the part off removes both")
        on[3] = true; masks[3] = 0
        XCTAssertTrue(euclideousMixLines(layout: L, masks: masks, partOn: on).filter { $0.part == 3 }.isEmpty, "an empty mask draws none")
        XCTAssertFalse(euclideousMixOriginDots(lines: euclideousMixLines(layout: L, masks: masks, partOn: on)).contains { $0.part == 3 }, "…and no origin dot")
    }
    func testLineActivityAtZero75And150MillisecondsAfterANoteOff() {
        let tempo = 120.0                                        // a beat is 500 ms, so 75 ms is 0.15 beat
        let n = [note(on: 0, end: 1, rank: 1, outs: 0b0001)]
        func act(_ ms: Double) -> Double { euclideousMixLineActivity(notes: n, output: 0, nowBeat: 1 + ms / 500, tempo: tempo) }
        XCTAssertEqual(act(0), 1, accuracy: 1e-9); XCTAssertEqual(act(75), 0.5, accuracy: 1e-6); XCTAssertEqual(act(150), 0, accuracy: 1e-6); XCTAssertEqual(act(400), 0)
        XCTAssertEqual(euclideousMixLineActivity(notes: n, output: 0, nowBeat: 0.5, tempo: tempo), 1, "active while the note sounds")
        XCTAssertEqual(euclideousMixLineActivity(notes: n, output: 1, nowBeat: 0.5, tempo: tempo), 0, "a note leaving on A does not light B's line")
        XCTAssertEqual(euclideousMixLineActivity(notes: [note(on: 0, end: nil, rank: 1, outs: 0b0100)], output: 2, nowBeat: 9, tempo: tempo), 1, "a held note")
        XCTAssertEqual(euclideousMixLineActivity(notes: [note(on: 0, end: 2, rank: 1, outs: 0)], output: 0, nowBeat: 1, tempo: tempo), 0, "silent notes (routed nowhere) activate nothing")
        XCTAssertEqual(euclideousMixLineActivity(notes: [note(on: 2, end: 3, rank: 1)], output: 0, nowBeat: 1, tempo: tempo), 0, "a note that has not struck yet")
        XCTAssertEqual(euclideousMixEmitterActivity(parts: [[note(on: 0, end: 1, rank: 1, outs: 0b0010)], [note(on: 0, end: 5, rank: 1, outs: 0b0010)]], output: 1, nowBeat: 3, tempo: tempo), 1, "an emitter is active while ANY note (any lane) leaves through it")
        XCTAssertEqual(euclideousMixEmitterActivity(parts: [[note(on: 0, end: 1, rank: 1, outs: 0)]], output: 0, nowBeat: 0.5, tempo: tempo), 0)
    }
    func testTheLineLooksAndTheDrawOrder() {
        let idle = euclideousMixLineLook(activity: 0), active = euclideousMixLineLook(activity: 1), mid = euclideousMixLineLook(activity: 0.5)
        close(idle.width, 1.25); XCTAssertEqual(idle.alpha, 0.4, accuracy: 1e-9); close(active.width, 2); XCTAssertEqual(active.alpha, 1, accuracy: 1e-9)
        close(mid.width, 1.625); XCTAssertEqual(mid.alpha, 0.7, accuracy: 1e-9)
        XCTAssertEqual(euclideousMixLineDrawOrder(activities: [1, 0, 0.5, 0]), [1, 3, 2, 0], "active lines draw above idle ones; ties keep their order")
        let e0 = euclideousMixEmitterLook(activity: 0), e1 = euclideousMixEmitterLook(activity: 1), e5 = euclideousMixEmitterLook(activity: 0.4)
        XCTAssertEqual(e0, EuclideousMixEmitterLook(fill: 0, letterIsInk: false)); XCTAssertEqual(e1, EuclideousMixEmitterLook(fill: 1, letterIsInk: true))
        XCTAssertFalse(e5.letterIsInk); XCTAssertEqual(e5.fill, 0.4, accuracy: 1e-9, "AMENDMENT 1: the emitter's fill is its activity — there is no light")
        XCTAssertEqual((0..<4).map { euclideousMixOutputColour($0).hex }, [0xF25959, 0x59BFF2, 0xF2BF40, 0x8CD973], "A is lane 1's colour … D lane 4's")
    }

    // MARK: test 6 — the roll

    func testANoteAtBeatTwoOfBarOneDrawsAtAQuarterAndIsWipedWhenThePlayheadComesRound() {
        let size = CGSize(width: 100, height: 44)
        let n = [note(on: 1, end: 2, rank: 4)]                 // "beat 2" of a four-beat bar: one beat in
        let roll = euclideousMixRoll(notes: n, nowBeat: 2.5, barBeats: 4, size: size)
        XCTAssertEqual(roll.notes.count, 1); close(roll.notes[0].rect.minX, 25, "R × 0.25"); close(roll.notes[0].rect.width, 25, "one beat of the bar")
        close(roll.playheadX, 62.5, "the playhead at (time within the bar) × R")
        XCTAssertEqual(euclideousMixRoll(notes: n, nowBeat: 4.99, barBeats: 4, size: size).notes.count, 1, "still the last bar")
        XCTAssertEqual(euclideousMixRoll(notes: n, nowBeat: 5.0, barBeats: 4, size: size).notes.count, 0, "wiped when the playhead reaches R × 0.25 in bar 2")
        close(euclideousMixRoll(notes: n, nowBeat: 5.0, barBeats: 4, size: size).playheadX, 25, "…which is exactly where the playhead is")
        XCTAssertEqual(euclideousMixRoll(notes: n, nowBeat: 0.5, barBeats: 4, size: size).notes.count, 0, "not struck yet")
    }
    func testANoteCrossingTheBarLineIsClippedNotWrapped() {
        let size = CGSize(width: 100, height: 44)
        let roll = euclideousMixRoll(notes: [note(on: 3.5, end: 5, rank: 2)], nowBeat: 5.2, barBeats: 4, size: size)
        XCTAssertEqual(roll.notes.count, 1); close(roll.notes[0].rect.minX, 87.5); close(roll.notes[0].rect.maxX, 100, "clipped at the right edge")
    }
    func testTheRollRowsAndTheThreeLooks() {
        let size = CGSize(width: 100, height: 44)
        let notes = [note(on: 0, end: 0.5, rank: 8), note(on: 0, end: nil, rank: 1), note(on: 0, end: 3.5, rank: 4, outs: 0), note(on: 1, end: 1.25, rank: 5)]
        let roll = euclideousMixRoll(notes: notes, nowBeat: 2, barBeats: 4, size: size)
        XCTAssertEqual(roll.notes.map { $0.look }, [.ended, .sounding, .silent, .ended])
        let rowH: CGFloat = 44 / 8
        close(roll.notes[0].rect.midY, rowH / 2, "rank 8 on the top row"); close(roll.notes[1].rect.midY, 44 - rowH / 2, "rank 1 on the bottom row")
        close(roll.notes[0].rect.height, rowH - 1.5, "the row's height less 1.5"); XCTAssertEqual(roll.rowLines.count, 7); close(roll.rowLines[0], rowH); close(roll.rowLines[6], 7 * rowH)
        close(roll.notes[1].rect.width, 50, "a held note runs to the playhead (2 beats of 4)")
        let tiny = euclideousMixRoll(notes: [note(on: 0, end: 1, rank: 3)], nowBeat: 1, barBeats: 4, size: CGSize(width: 100, height: 8))
        close(tiny.notes[0].rect.height, 2.5, "at least 2.5 tall")
        XCTAssertEqual(euclideousMixRoll(notes: [], nowBeat: 3, barBeats: 4, size: size).notes.count, 0)
        XCTAssertTrue(euclideousMixRollPlaying(notes: notes, nowBeat: 2)); XCTAssertFalse(euclideousMixRollPlaying(notes: [note(on: 0, end: 1, rank: 1)], nowBeat: 2))
    }

    func testASoundingRankFillsItsRowInThatPartsRollFromNoteOnToNoteOff() {
        let size = CGSize(width: 100, height: 44), rowH: CGFloat = 44 / 8
        func rows(_ n: [NoteRollNote], _ now: Double) -> [CGRect] { euclideousMixRoll(notes: n, nowBeat: now, barBeats: 4, size: size).soundingRows }
        // a riff note of rank 4 fills row 4 of the RIFF roll only (the notes roll is built from the notes part's own feed, which holds no note)
        let riff = [note(on: 1, end: 2, rank: 4)]
        XCTAssertEqual(rows(riff, 0.9).count, 0, "not before the note-on")
        let r = rows(riff, 1.5)
        XCTAssertEqual(r.count, 1); close(r[0].minY, CGFloat(8 - 4) * rowH); close(r[0].height, rowH); close(r[0].minX, 0); close(r[0].width, 100, "the whole row")
        XCTAssertEqual(rows([], 1.5).count, 0, "the notes roll of that lane: nothing sounds there")
        XCTAssertEqual(rows(riff, 2.0).count, 0, "cleared at the note-off — no fade, nothing left behind")
        // a chord of ranks 2 and 5 fills both rows of the notes roll
        let chord = [note(on: 1, end: 3, rank: 2, pitch: 62), note(on: 1, end: 3, rank: 5, pitch: 67)]
        let c = rows(chord, 2)
        XCTAssertEqual(c.map { $0.minY }.sorted(), [CGFloat(8 - 5) * rowH, CGFloat(8 - 2) * rowH].sorted(), "ranks 5 and 2")
        // a silent note (routed nowhere) fills its row too
        XCTAssertEqual(rows([note(on: 1, end: 3, rank: 7, outs: 0)], 2).count, 1)
        // each rank ends on its own note-off
        let staggered = [note(on: 1, end: 2, rank: 2), note(on: 1, end: 3, rank: 5)]
        XCTAssertEqual(rows(staggered, 2.5).count, 1); close(rows(staggered, 2.5)[0].minY, CGFloat(8 - 5) * rowH)
        // a held note longer than the bar still fills its row after its dot has been wiped from the roll
        XCTAssertEqual(rows([note(on: 0, end: nil, rank: 3)], 9).count, 1)
        XCTAssertEqual(EuclideousMixRollMetrics.soundingRowAlpha, 0.10)
    }

    // MARK: test 11 (§A5–A6) — a lane with no hits, and the one dim

    func testALaneWithNoHitsDimsEverythingBelowTheTopRowToFortyTwoNotEighteenAndEndsWithTheFirstHit() {
        let dim = EuclideousLaneDimStyle.opacity; XCTAssertEqual(dim, 0.42)
        func leg(_ at: Set<Int>) -> [EuclideousStripLeg] { [EuclideousStripLeg(hitSteps: [], hits: hits(8, at: at))] }
        XCTAssertTrue(euclideousMixLaneHasNoHits(legs: leg([])), "eight steps, no hits")
        XCTAssertFalse(euclideousMixLaneHasNoHits(legs: leg([3])), "adding a hit ends it")
        XCTAssertTrue(euclideousMixLaneHasNoHits(legs: []))
        var gap = hits(4, at: [1]); gap[1].kind = .gap
        XCTAssertFalse(euclideousMixLaneHasNoHits(legs: [EuclideousStripLeg(hitSteps: [], hits: gap)]), "a hit on a riff rest is still a hit")
        XCTAssertFalse(euclideousMixLaneHasNoHits(legs: [EuclideousStripLeg(hitSteps: [], hits: hits(4, at: [])), EuclideousStripLeg(hitSteps: [], hits: hits(4, at: [2]))]), "either leg of a PING-PONG lane")
        // one flag whatever the cause
        XCTAssertTrue(euclideousMixLaneDimmed(soloSilenced: false, noHits: true, muted: false)); XCTAssertTrue(euclideousMixLaneDimmed(soloSilenced: true, noHits: false, muted: false))
        XCTAssertTrue(euclideousMixLaneDimmed(soloSilenced: false, noHits: false, muted: true)); XCTAssertFalse(euclideousMixLaneDimmed(soloSilenced: false, noHits: false, muted: false))
        // the net opacity: 42 % for everything below the top row, 42 % — not 18 % — for an OFF part's roll / sliders in a dimmed lane, and a muted or solo-dimmed lane with no hits is still 42 %
        let all: [EuclideousMixDimTarget] = [.pool, .toggle, .out, .roll, .slider]
        for t in all { XCTAssertEqual(euclideousMixDimOpacity(laneDimmed: true, partOff: false, target: t), dim, "\(t)"); XCTAssertEqual(euclideousMixDimOpacity(laneDimmed: true, partOff: true, target: t), dim, "\(t): no compounding") }
        for t in all { XCTAssertEqual(euclideousMixDimOpacity(laneDimmed: false, partOff: false, target: t), 1, "\(t): an ordinary lane is full strength") }
        XCTAssertEqual(euclideousMixDimOpacity(laneDimmed: false, partOff: true, target: .roll), dim); XCTAssertEqual(euclideousMixDimOpacity(laneDimmed: false, partOff: true, target: .slider), dim)
        for t in [EuclideousMixDimTarget.pool, .toggle, .out] { XCTAssertEqual(euclideousMixDimOpacity(laneDimmed: false, partOff: true, target: t), 1, "\(t): an off part's own switch and the A–D buttons are not dimmed by it") }
        // what a view adds INSIDE the lane's group, so the product is the net and never 0.18
        for lane in [false, true] { for off in [false, true] { for t in all {
            let inside = lane ? dim : 1
            XCTAssertEqual(inside * euclideousMixOwnDimOpacity(laneDimmed: lane, partOff: off, target: t), euclideousMixDimOpacity(laneDimmed: lane, partOff: off, target: t), accuracy: 1e-12)
            XCTAssertGreaterThan(inside * euclideousMixOwnDimOpacity(laneDimmed: lane, partOff: off, target: t), 0.4)
        } } }
        // lines and origin dots: 42 % of the idle look; an active line is as bright as ever; adding a hit restores the idle look
        let idle = euclideousMixLineLook(activity: 0), idleNoHits = euclideousMixLineLook(activity: 0, laneNoHits: true)
        XCTAssertEqual(idle.alpha, 0.4); XCTAssertEqual(idleNoHits.alpha, 0.4 * 0.42, accuracy: 1e-12); close(idle.width, idleNoHits.width, "the line keeps its width")
        XCTAssertEqual(euclideousMixLineLook(activity: 1, laneNoHits: true).alpha, 1); XCTAssertEqual(euclideousMixLineLook(activity: 1, laneNoHits: true).width, EuclideousMixLineMetrics.activeWidth)
        XCTAssertEqual(euclideousMixLineLook(activity: 0, laneNoHits: false).alpha, idle.alpha, "a hit restores it")
        XCTAssertEqual(euclideousMixOriginDotAlpha(laneNoHits: true), 0.42); XCTAssertEqual(euclideousMixOriginDotAlpha(laneNoHits: false), 1)
        // VoiceOver
        XCTAssertEqual(euclideousMixStripSpoken(hits: 0, steps: 8), "Rhythm, no hits in 8 steps")
        XCTAssertEqual(euclideousMixStripSpoken(hits: 1, steps: 8), "Rhythm, 1 hit in 8 steps"); XCTAssertEqual(euclideousMixStripSpoken(hits: 5, steps: 8), "Rhythm, 5 hits in 8 steps")
    }

    // MARK: the strings

    func testVoiceOverStrings() {
        typealias A = EuclideousMixAX
        XCTAssertEqual(A.panel, "Mix"); XCTAssertEqual(A.lane(0), "Lane 1")
        XCTAssertEqual(A.toggle(notes: false, on: true), "Riff, on"); XCTAssertEqual(A.toggle(notes: true, on: false), "Notes, off")
        XCTAssertEqual(A.roll(notes: false, playing: true), "Riff playing"); XCTAssertEqual(A.roll(notes: true, playing: false), "Notes silent")
        XCTAssertEqual(A.slider(kind: .velocity, notes: false, value: 100), "Riff velocity 100"); XCTAssertEqual(A.slider(kind: .gate, notes: false, value: 90), "Riff gate 90%")
        XCTAssertEqual(A.slider(kind: .transpose, notes: false, value: 2), "Riff transpose +2"); XCTAssertEqual(A.slider(kind: .octave, notes: true, value: 0), "Notes octave 0")
        XCTAssertEqual(A.out(notes: false, output: 0, on: true), "Riff to A, on"); XCTAssertEqual(A.out(notes: true, output: 3, on: false), "Notes to D, off")
        XCTAssertEqual(A.emitter(output: 0, active: true), "Output A, active"); XCTAssertEqual(A.emitter(output: 2, active: false), "Output C, idle"); XCTAssertEqual(A.reset, "Reset")
    }
}

/// A test-only reader for numbers the views derive from the layout.
enum EuclideousMixRowsLayoutTesting {
    static func poolChipH(_ l: EuclideousMixRowsLayout) -> CGFloat { euclideousMixPoolFrames(area: l.bands[0].pool)[0].height }
}
