//  StackGreyTests.swift — STACK RANKS GREY ferry (2026-11-15) §8: the §1 grey ramp (and, as the later steps land, §2–§5).

import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class StackGreyTests: XCTestCase {

    private func relLum(_ c: EuclideousRGB) -> Double {
        func lin(_ v: Int) -> Double { let s = Double(v) / 255; return s <= 0.04045 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(c.r) + 0.7152 * lin(c.g) + 0.0722 * lin(c.b)
    }

    // §8.1 — stackRankColour: chroma 0 (a true grey, r==g==b) on all 8; luminance rises strictly 1→8; lane-independent; the table builds once.
    func testRampIsGreyRisingAndBuiltOnce() {
        var last = -1.0
        for rank in 1...8 {
            let c = stackRankColour(rank: rank)
            XCTAssertEqual(c.r, c.g, "rank \(rank): chroma 0 ⇒ r == g"); XCTAssertEqual(c.g, c.b, "rank \(rank): chroma 0 ⇒ g == b")
            let lum = relLum(c)
            XCTAssertGreaterThan(lum, last, "rank \(rank): luminance must rise")
            last = lum
        }
        // lane-independent: there is no lane parameter — the same grey serves every lane (this is the point of the ferry).
        for _ in 0..<50 { _ = stackRankColour(rank: 5) }
        XCTAssertEqual(stackRankConversionCount, 8, "the 8-entry table converts once")
    }

    // §8.2 — stackRankInk: ≥ 4.5:1 WCAG contrast on every rank; it is whichever of #0D0F14 / #F2F4F7 is better. Report which take light ink.
    func testInkIsLegibleOnEveryRank() {
        let white = EuclideousRGB(r: 0xF2, g: 0xF4, b: 0xF7), dark = EuclideousRGB(r: 0x0D, g: 0x0F, b: 0x14)
        var lightInk: [Int] = []
        var contrasts: [String] = []
        for rank in 1...8 {
            let c = stackRankColour(rank: rank), ink = stackRankInk(rank: rank)
            XCTAssertTrue(ink == white || ink == dark, "rank \(rank): ink is one of the two tokens")
            // the chosen ink is the better of the two
            XCTAssertGreaterThanOrEqual(euclideousWCAGContrast(c, ink), euclideousWCAGContrast(c, ink == white ? dark : white) - 1e-9, "rank \(rank): the better ink is chosen")
            let ratio = euclideousWCAGContrast(c, ink)
            XCTAssertGreaterThanOrEqual(ratio, 4.5, "rank \(rank): ink contrast ≥ 4.5 (got \(String(format: "%.2f", ratio)))")
            if ink == white { lightInk.append(rank) }
            contrasts.append("r\(rank) #\(String(format: "%02X%02X%02X", c.r, c.g, c.b)) ink=\(ink == white ? "white" : "dark") \(String(format: "%.2f", ratio)):1")
        }
        print("STACK-GREY-REPORT ink: ranks with LIGHT (#F2F4F7) ink = \(lightInk); \(contrasts.joined(separator: " · "))")
    }

    // §8.3 — no caller of stackChipColour remains: verified by grep at build time (a deleted symbol cannot be referenced here).
    // `grep -rn stackChipColour Fourfold/` shows only comment lines — the two code callers + three test refs moved to stackRankColour.
}
