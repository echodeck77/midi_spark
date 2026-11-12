//  LaneStripBandsTests.swift — LANE STRIP BANDS ferry (2026-11-12), slice 2: the pure band/frame/colour/outline/cell
//  functions (§8), tested at both the real top-row height T 44 (Paul's choice) and the spec's reference T 78, so the
//  ratio formulas are pinned either way. §10 tests 1, 3, 6, 9 + the CC source helper.

import XCTest
import CoreGraphics

final class LaneStripBandsTests: XCTestCase {

    // §B2.1 / §B7.2 — band heights (amendment 1: ratio 0.22, gap 1): the real T 44 and the spec's reference T 78.
    func testBandHeights() {
        let a = laneStripBandHeights(T: 78)
        XCTAssertEqual(a.hH, 17); XCTAssertEqual(a.hC, 42); XCTAssertEqual(a.gap, 1)         // round(78·0.22)=17, 78−34−2=42
        let b = laneStripBandHeights(T: 44)
        XCTAssertEqual(b.hH, 10); XCTAssertEqual(b.hC, 22); XCTAssertEqual(b.gap, 1)         // round(44·0.22)=10, 44−20−2=22
        // the three bands + two gaps always fill T exactly, and hH never drops below the 8 pt floor
        for T in stride(from: CGFloat(30), through: 90, by: 1) {
            let h = laneStripBandHeights(T: T)
            XCTAssertEqual(h.hH + h.gap + h.hC + h.gap + h.hH, T, accuracy: 0.001, "bands fill T at \(T)")
            XCTAssertGreaterThanOrEqual(h.hH, 8, "§B2.1 floor at \(T)")
        }
    }

    // §B7.2 — the chip fills its cell's x/width at the band's full height (no shrink, no 30-cap); the 7 pt label fit.
    func testChipFillsItsBand() {
        let b = laneStripBandHeights(T: 44)
        let slot = CGRect(x: 12, y: 0, width: 18, height: b.hH)
        XCTAssertEqual(laneStripChipFrame(slot: slot), slot, "§B2.2: the chip IS its slot — fills the band")
        XCTAssertEqual(laneStripChipFrame(slot: CGRect(x: 0, y: 0, width: 50, height: b.hH)).width, 50, "§B2.2: no 30-cap")
        XCTAssertEqual(laneStripChipLabelSize(steps: 16), 7, "§B2.3: a flat 7 pt label")
        XCTAssertTrue(laneStripChipLabelFits("16", chipWidth: 16, size: 7))                  // 16 ≥ 2·0.6·7 + 2 = 10.4
        XCTAssertFalse(laneStripChipLabelFits("16", chipWidth: 8, size: 7), "hidden under the label width + 2")
    }

    // §B7.3 — a sounding chip is 100 % with an inner #F2F4F7 stroke; resting 78 %; the old outside ring is gone.
    func testSoundingChipMetrics() {
        XCTAssertEqual(LaneStripBandMetrics.chipRestOpacity, 0.78)
        XCTAssertEqual(LaneStripBandMetrics.soundStroke, EuclideousRGB(r: 0xF2, g: 0xF4, b: 0xF7))
        XCTAssertEqual(LaneStripBandMetrics.chipRadius, 2)
    }

    // §B7.7 — the button type at the REAL T 44 (the amendment's "name 9" holds only at its scaled 41).
    func testButtonTypeAtT44() {
        let t = euclideousPartPlayType(height: 44)
        XCTAssertEqual(t.nameSize, 9.5); XCTAssertEqual(t.playSize, 6); XCTAssertEqual(t.lineGap, 3)
    }

    // §10.1 — the top-row frames: w, tiles span T, the bridges sit in their own row only, the chip slots equal the cells.
    func testTopRowFramesAndChipSlotsMatchCells() {
        let T: CGFloat = 44, g: CGFloat = 4, content = CGSize(width: 360, height: 44)
        let nameW: CGFloat = 30                                                              // a measured "STACK" width
        for steps in [8, 12, 16] {
            let f = laneTopRowFrames(T: T, content: content, g: g, stackNameWidth: nameW, steps: steps)
            XCTAssertEqual(f.w, (nameW + 8).rounded(.up), "w = ceil(STACK + 8)")             // §1.3
            XCTAssertEqual(f.leadTile.height, T); XCTAssertEqual(f.trailTile.height, T)      // §1.5 both span T
            XCTAssertEqual(f.leadTile.minX, 0); XCTAssertEqual(f.trailTile.maxX, content.width, accuracy: 0.01)
            // the header bridge is in the header row only; the footer bridge in the footer row only
            XCTAssertEqual(f.headerBridge, CGRect(x: f.leadTile.maxX, y: 0, width: g, height: f.hH))
            XCTAssertEqual(f.footerBridge, CGRect(x: f.strip.maxX, y: T - f.hH, width: g, height: f.hH))
            // the strip bands
            XCTAssertEqual(f.header.minY, 0); XCTAssertEqual(f.header.height, f.hH)
            XCTAssertEqual(f.cells.minY, f.hH + f.gap); XCTAssertEqual(f.cells.height, f.hC)
            XCTAssertEqual(f.footer.minY, T - f.hH); XCTAssertEqual(f.footer.height, f.hH)
            // §1.6: every step's header slot and footer slot share the cell's x and width
            XCTAssertEqual(f.columnXs.count, steps)
            for i in 0..<steps {
                XCTAssertEqual(f.headerSlot(i).minX, f.cell(i).minX, accuracy: 0.001)
                XCTAssertEqual(f.headerSlot(i).width, f.cell(i).width, accuracy: 0.001)
                XCTAssertEqual(f.footerSlot(i).minX, f.cell(i).minX, accuracy: 0.001)
                XCTAssertEqual(f.footerSlot(i).width, f.cell(i).width, accuracy: 0.001)
                XCTAssertEqual(f.cell(i).height, f.hC)
            }
            // the cells never run under the buttons
            XCTAssertGreaterThanOrEqual(f.cell(0).minX, f.leadTile.maxX)
            XCTAssertLessThanOrEqual(f.cell(steps - 1).maxX, f.trailTile.minX + 0.001)
        }
    }

    // §10.3 — stackChipColour: luminance strictly rises rank 1→8, ink is legible on all 32, the table is built once.
    func testStackChipColourRisesAndIsLegibleAndBuiltOnce() {
        func relLum(_ c: EuclideousRGB) -> Double {
            func lin(_ v: Int) -> Double { let s = Double(v) / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
        }
        let ink = LaneStripBandMetrics.chipInk
        XCTAssertEqual(ink, EuclideousRGB(r: 0x0D, g: 0x0F, b: 0x14))
        for lane in 0..<4 {
            var last = -1.0
            for rank in 1...8 {
                let c = stackChipColour(lane: lane, rank: rank)
                let lum = relLum(c)
                XCTAssertGreaterThan(lum, last, "lane \(lane) rank \(rank): luminance must rise")
                last = lum
                let hi = max(lum, relLum(ink)), lo = min(lum, relLum(ink))
                XCTAssertGreaterThanOrEqual((hi + 0.05) / (lo + 0.05), 4.5, "lane \(lane) rank \(rank): ink contrast ≥ 4.5")
            }
        }
        for _ in 0..<50 { _ = stackChipColour(lane: 2, rank: 5) }
        XCTAssertEqual(stackChipConversionCount, 32, "the 4×8 table converts once")
    }

    // §10.6 — rank outlines/bars: inset riff 3 / stack 6; the stack bar sits inside the riff's on a shared rank; rank 8 above rank 1.
    func testRankMarksInsetsAndOrder() {
        let cell = CGRect(x: 20, y: 0, width: 24, height: 20)                                // hC 20 (T 44) → slot 1.375 < 3 → fallback bars
        let riff6 = rankSlotRect(cell: cell, hC: 20, rank: 6, part: .riff)
        let stack6 = rankSlotRect(cell: cell, hC: 20, rank: 6, part: .stack)
        XCTAssertTrue(riff6.filled, "at hC 20 the slot is 1.375 < 3 → the §4.5 filled-bar fallback")
        XCTAssertEqual(riff6.rect.minX, cell.minX + 3); XCTAssertEqual(stack6.rect.minX, cell.minX + 6)   // §4.4 insets
        XCTAssertGreaterThan(stack6.rect.minX, riff6.rect.minX, "the stack bar is inside the riff's")
        XCTAssertLessThan(stack6.rect.maxX, riff6.rect.maxX)
        // rank 8 is above (smaller y than) rank 1
        let r8 = rankSlotRect(cell: cell, hC: 20, rank: 8, part: .riff).rect.midY
        let r1 = rankSlotRect(cell: cell, hC: 20, rank: 1, part: .riff).rect.midY
        XCTAssertLessThan(r8, r1)
        // at hC 38 (T 78) the slot is 3.625 ≥ 3 → a stroked outline, not a bar
        XCTAssertFalse(rankSlotRect(cell: CGRect(x: 0, y: 0, width: 24, height: 38), hC: 38, rank: 6, part: .riff).filled)
    }

    // §10.9 — a hit cell is lane100 @ 30 % (45 % at the playhead) with the bar; no cell is ever 100 % or glows.
    func testCellLooks() {
        XCTAssertEqual(stripCellLook(isHit: true, isPlayhead: false), LaneCellLook(fill: .hit(alpha: 0.30), bar: true))
        XCTAssertEqual(stripCellLook(isHit: true, isPlayhead: true), LaneCellLook(fill: .hit(alpha: 0.45), bar: true))
        XCTAssertEqual(stripCellLook(isHit: false, isPlayhead: false), LaneCellLook(fill: .step, bar: false))
        XCTAssertEqual(stripCellLook(isHit: false, isPlayhead: true), LaneCellLook(fill: .playheadStep, bar: false))
        for hit in [true, false] { for ph in [true, false] {
            if case .hit(let a) = stripCellLook(isHit: hit, isPlayhead: ph).fill { XCTAssertLessThan(a, 1.0) }
        } }
    }

    // §3.3/§3.4/§4.4/§4.6 — the sounding held sets: rings/outlines map a note's onset to its step; outs==0 is excluded.
    func testSounding() {
        func note(_ on: Double, end: Double?, rank: Int, outs: UInt8 = 1) -> NoteRollNote {
            NoteRollNote(onBeat: on, endBeat: end, pitch: 60, velocity: 100, outs: outs, rank: UInt8(rank))
        }
        let step: (Double) -> Int = { Int($0) }                                   // onset beat == step index, for the test
        let riff = [note(2, end: nil, rank: 4), note(9, end: 9.1, rank: 1)]        // step 2 held (sounds); step 9 ended before now
        let stack = [note(3, end: nil, rank: 5), note(3, end: nil, rank: 2),       // step 3: a two-voice chord, both sounding
                     note(1, end: 1.5, rank: 7),                                   // step 1: played earlier this pass, now silent
                     note(5, end: nil, rank: 6, outs: 0)]                          // step 5: routed nowhere → ignored
        let s = laneStripSounding(riffHeld: riff, stackHeld: stack, n: 8, now: 4.0, passBeats: 8.0, stepOf: step, hitSteps: [1, 2, 3, 5])
        XCTAssertTrue(s.riffRing[2])
        XCTAssertEqual(s.riffRing.filter { $0 }.count, 1, "only the held riff note at step 2 rings (the one at beat 9 is in the future)")
        XCTAssertEqual(s.stackChip[3], 2, "the footer chip is the LOWEST rank played on the step")
        XCTAssertTrue(s.stackRing[3]); XCTAssertEqual(Set(s.stackOutline[3]), [2, 5], "one outline per sounding voice")
        XCTAssertEqual(s.stackChip[1], 7, "a hit played this pass keeps its chip after its note-off")
        XCTAssertFalse(s.stackRing[1]); XCTAssertTrue(s.stackOutline[1].isEmpty, "but no ring or outline once silent")
        XCTAssertNil(s.stackChip[5], "a note routed nowhere (outs 0) is ignored")
    }

    // §B7.1 / §B1 — every footer chip and rank mark sits on its OWN hit's step, snapped from one shared fn — even
    // when the onset maps one step early (the old floor bug) or lands late (a long gate, TIE, ratchet, delayed pool).
    func testSlotsSitOnTheirHitStep() {
        func note(_ on: Double, rank: Int) -> NoteRollNote { NoteRollNote(onBeat: on, endBeat: nil, pitch: 60, velocity: 100, outs: 1, rank: UInt8(rank)) }
        let hits = [0, 4, 8, 12, 15]                                   // a 16-step lane hitting (1-based) 1, 5, 9, 13, 16
        let oneEarly: (Double) -> Int = { max(0, Int($0) - 1) }        // reproduce the floored-comet "one step early"
        let stack = hits.map { note(Double($0), rank: 3) }
        let s = laneStripSounding(riffHeld: [], stackHeld: stack, n: 16, now: 20.0, passBeats: 16.0, stepOf: oneEarly, hitSteps: hits)
        for h in hits { XCTAssertEqual(s.stackChip[h], 3, "footer chip snaps onto hit \(h), not one early") }
        for i in 0..<16 where !hits.contains(i) { XCTAssertNil(s.stackChip[i], "no chip on the non-hit step \(i)") }
        // §B1.3: a late note (onset drifts toward step 5) still belongs to its hit's step (4).
        let late = laneStripSounding(riffHeld: [], stackHeld: [note(4.6, rank: 2)], n: 16, now: 20.0, passBeats: 16.0, stepOf: { Int($0.rounded()) }, hitSteps: hits)
        XCTAssertEqual(late.stackChip[4], 2, "a late/ratcheted/delayed note stays in its hit's (4) slot")
        XCTAssertNil(late.stackChip[5], "not on the step its onset drifted to")
    }

    // §5.3/§5.4 — the CC trace maps the emitter's bar curve onto the steps: value→y (127 top, 0 above the bar), beat→x.
    func testCCStripTrace() {
        let cellXs: [CGFloat] = [0, 20, 40, 60]                                    // 4 steps, pitch 20
        let cells = CGRect(x: 0, y: 10, width: 80, height: 20)                     // value 0 → y 27 (maxY − bar 3), value 127 → y 10 (top)
        let t = laneCCStripTrace(dots: [CGPoint(x: 1.0, y: 127), CGPoint(x: 3.0, y: 0)], sub: 1.0, barBeats: 4.0,
                                 cellXs: cellXs, columnW: 18, cellsRect: cells, bottomBarH: 3, samplesPerStep: 4,
                                 playheadStepFloat: 2.0, playheadValue: 64, value: { _ in 64.0 })
        XCTAssertFalse(t.line.isEmpty)
        let yFor64 = cells.minY + (1 - 64.0 / 127) * (cells.height - 3)
        for p in t.line { XCTAssertEqual(p.y, yFor64, accuracy: 0.5) }             // a constant value is a flat line
        XCTAssertEqual(t.line.first!.x, 0, accuracy: 0.01)
        XCTAssertEqual(t.dots.first!.x, 20, accuracy: 0.5); XCTAssertEqual(t.dots.first!.y, cells.minY, accuracy: 0.5)   // hit at step 1, value 127 → top
        XCTAssertEqual(t.dots.last!.x, 60, accuracy: 0.5); XCTAssertEqual(t.dots.last!.y, cells.maxY - 3, accuracy: 0.5) // hit at step 3, value 0 → above the bar
        XCTAssertEqual(t.playhead!.x, 40, accuracy: 0.5)                           // stepFloat 2 → cell 2's left edge
        XCTAssertNil(laneCCStripTrace(dots: [], sub: 1, barBeats: 4, cellXs: cellXs, columnW: 18, cellsRect: cells, bottomBarH: 3, samplesPerStep: 4, value: { _ in nil }).playhead)
    }

    // §5.1 — the CC source: first routed-and-CC-on in A–D order; none → nil.
    func testCCSourceEmitter() {
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b0110, ccOn: 0b0100), 2)                 // routes to B,C; CC on C → C
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b1111, ccOn: 0b1111), 0)                 // first wins → A
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b1010, ccOn: 0b1010), 1)                 // routes to B,D; both CC on → B
        XCTAssertNil(laneCCSourceEmitter(routed: 0b0001, ccOn: 0b0000))                      // routed, but CC off → none
        XCTAssertNil(laneCCSourceEmitter(routed: 0b0000, ccOn: 0b1111))                      // routed nowhere → none
    }
}
