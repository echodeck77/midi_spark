//  LaneStripBandsTests.swift — LANE STRIP BANDS ferry (2026-11-12), slice 2: the pure band/frame/colour/outline/cell
//  functions (§8), tested at both the real top-row height T 44 (Paul's choice) and the spec's reference T 78, so the
//  ratio formulas are pinned either way. §10 tests 1, 3, 6, 9 + the CC source helper.

import XCTest
import CoreGraphics

final class LaneStripBandsTests: XCTestCase {

    // §10.1 — band heights at both heights; the spec's parentheticals (hH 18 / hC 38 at T 78) and the real T 44.
    func testBandHeights() {
        let a = laneStripBandHeights(T: 78)
        XCTAssertEqual(a.hH, 18); XCTAssertEqual(a.hC, 38); XCTAssertEqual(a.gap, 2)         // round(78·0.23)=18, 78−36−4=38
        let b = laneStripBandHeights(T: 44)
        XCTAssertEqual(b.hH, 10); XCTAssertEqual(b.hC, 20); XCTAssertEqual(b.gap, 2)         // round(44·0.23)=10, 44−20−4=20
        // the three bands + two gaps always fill T exactly
        for T in stride(from: CGFloat(30), through: 90, by: 1) {
            let h = laneStripBandHeights(T: T)
            XCTAssertEqual(h.hH + h.gap + h.hC + h.gap + h.hH, T, accuracy: 0.001, "bands fill T at \(T)")
        }
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

    // §5.1 — the CC source: first routed-and-CC-on in A–D order; none → nil.
    func testCCSourceEmitter() {
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b0110, ccOn: 0b0100), 2)                 // routes to B,C; CC on C → C
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b1111, ccOn: 0b1111), 0)                 // first wins → A
        XCTAssertEqual(laneCCSourceEmitter(routed: 0b1010, ccOn: 0b1010), 1)                 // routes to B,D; both CC on → B
        XCTAssertNil(laneCCSourceEmitter(routed: 0b0001, ccOn: 0b0000))                      // routed, but CC off → none
        XCTAssertNil(laneCCSourceEmitter(routed: 0b0000, ccOn: 0b1111))                      // routed nowhere → none
    }
}
