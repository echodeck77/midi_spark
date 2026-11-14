//  ResetsCardLayoutTests.swift — RESETS TAB ferry (2026-11-13), §5.1/§1: the restart controls now live on the lane card (no pop-up). `euclideousResetsCardLayout` splits the body into a RHYTHM half and a MELODY half, each led by its
//  progress tile, the WITH RHYTHM link row the divider. These tests pin §1.2–1.5's frames at the two real card bodies and walk §1.7's shrink ladder and §1.8's narrow-card report. Pure (Foundation + CoreGraphics), so the card and the
//  tests read the same numbers — the page's UI has no macOS test reach.

import XCTest

final class ResetsCardLayoutTests: XCTestCase {
    private func near(_ a: CGFloat, _ b: CGFloat, _ what: String, _ acc: CGFloat = 0.01) { XCTAssertEqual(a, b, accuracy: acc, what) }

    /// The two real card bodies: TW = innerWidth(cardWidth), B = contentAreaH(cardHeight) — from the pinned laneBox 380.67 × 301 (landscape) / 387 × 301.67 (portrait). B = cardHeight − 68 (chromeH), not the stale −72.
    private func landscape() -> CGSize { CGSize(width: EuclideousLaneCardMetrics.innerWidth(cardWidth: 380.67), height: EuclideousLaneCardMetrics.contentAreaH(cardHeight: 301)) }
    private func portrait() -> CGSize { CGSize(width: EuclideousLaneCardMetrics.innerWidth(cardWidth: 387), height: EuclideousLaneCardMetrics.contentAreaH(cardHeight: 301.67)) }

    // MARK: test 1 — §1.2–1.5 frames at the reference bodies, and §1.7 = FULL in both

    func testTheCardFramesAtTheReferenceBodies() {
        for size in [landscape(), portrait()] {
            let TW = size.width, B = size.height
            let L = euclideousResetsCardLayout(size: size)
            XCTAssertEqual(L.appliedCase, .full, "§1.7: the full layout fits at B \(B)")   // B = 233 / 233.67, both ≥ 228
            XCTAssertEqual(L.linkH, 20); near(L.h, (B - 20) / 2, "§1.2 H")
            XCTAssertTrue(L.row1Fits, "§1.8: TW \(TW) ≥ 262")
            let T = L.tileH; XCTAssertEqual(T, 44)
            // §1.3 tiles: RHYTHM at y 0, MELODY at y H + 20, both TW × T
            XCTAssertEqual(L.rhythmTile, CGRect(x: 0, y: 0, width: TW, height: 44))
            near(L.melodyTile.minY, L.h + 20, "§1.2 MELODY tile y"); XCTAssertEqual(L.melodyTile.size, CGSize(width: TW, height: 44))
            // §1.3 RHYTHM row 1 at y T + 4: FREE x 0 (40 × 24); unit chips x 48, 92, 136 (40 × 24)
            XCTAssertEqual(L.rhythm.freePill, CGRect(x: 0, y: 48, width: 40, height: 24))
            XCTAssertEqual(L.rhythm.chips.map { $0.minX }, [48, 92, 136]); L.rhythm.chips.forEach { XCTAssertEqual($0.size, CGSize(width: 40, height: 24)) }
            // §1.3 count chips from x 0 (44 × 28, sp4) at y T + 32; four end at x 188
            XCTAssertEqual(L.rhythm.countChips.map { $0.minX }, [0, 48, 96, 144]); L.rhythm.countChips.forEach { XCTAssertEqual($0.size, CGSize(width: 44, height: 28)) }
            near(L.rhythm.countChips[0].minY, 48 + 28, "§1.3 row 2 y = T + 32")
            near(L.rhythm.countChips[3].maxX, 188, "§1.3/§5.1: four count chips and no + end at x 188")
            // §1.3 source squares 18 × 24 at TW − 78/−58/−38/−18 (sp2), ending at TW
            XCTAssertEqual(L.rhythm.sources.count, 4)
            for (i, r) in L.rhythm.sources.enumerated() { near(r.minX, TW - 78 + CGFloat(i) * 20, "source \(i) x"); XCTAssertEqual(r.size, CGSize(width: 18, height: 24)) }
            near(L.rhythm.sources[3].maxX, TW, "§5.1: the squares end at TW")
            // §1.3 MELODY half mirrors the RHYTHM half, offset by H + 20 (+ T + 4 to row 1)
            near(L.melody.freePill.minY, L.h + 20 + 48, "§1.3 MELODY row 1 y")
            near(L.melody.countChips[0].minY, L.h + 20 + 48 + 28, "§1.3 MELODY row 2 y")
            XCTAssertEqual(L.melody.chips.map { $0.minX }, [48, 92, 136])
            // §1.4 no label column, §3.3 no timeline
            XCTAssertEqual(L.rhythm.labelColumn, .zero); XCTAssertNil(L.rhythm.axisLabel); XCTAssertTrue(L.rhythm.cells.isEmpty)
            // §1.5 link row: button 34 × 20 at x 0, hit x 0–40 by 20, line x 42 → TW (1.5 pt), centred at y H + 10
            XCTAssertEqual(L.linkButton, CGRect(x: 0, y: L.h, width: 34, height: 20))
            XCTAssertEqual(L.linkButtonHit, CGRect(x: 0, y: L.h, width: 40, height: 20))
            near(L.linkLine.minX, 42, "§1.5 line x"); near(L.linkLine.maxX, TW, "§1.5 line ends at TW"); near(L.linkLine.height, 1.5, "§1.5 line 1.5 pt")
            near(L.linkLine.midY, L.h + 10, "§1.5 line centred in the 20 pt link row")
        }
    }

    // MARK: test 2 — §1.7's shrink ladder (never reached at the reference; checked at synthetic short bodies)

    func testTheShortBodyLadder() {
        // B ≥ 228 full · 224–228 a · 216–224 b · 212–216 c · < 212 cantFit (H = (B − linkH)/2, a half's content T + 60 / +58 / +54)
        func c(_ B: CGFloat) -> EuclideousResetsCardLayout.Case { euclideousResetsCardLayout(size: CGSize(width: 360.67, height: B)).appliedCase }
        XCTAssertEqual(c(233), .full); XCTAssertEqual(c(228), .full)
        XCTAssertEqual(c(226), .a); XCTAssertEqual(c(224), .a)
        XCTAssertEqual(c(220), .b); XCTAssertEqual(c(216), .b)
        XCTAssertEqual(c(214), .c); XCTAssertEqual(c(212), .c)
        XCTAssertEqual(c(200), .cantFit)
        // §1.7 (a): gap under the tile 4 → 2 ⇒ row 1 at y T + 2
        near(euclideousResetsCardLayout(size: CGSize(width: 360.67, height: 226)).rhythm.freePill.minY, 46, "§1.7a row 1 at T + 2")
        // §1.7 (b): count chips 24 tall
        XCTAssertEqual(euclideousResetsCardLayout(size: CGSize(width: 360.67, height: 220)).rhythm.countChips[0].height, 24)
        // §1.7 (c): link row 16 tall ⇒ H = (B − 16)/2, button 34 × 16
        let cc = euclideousResetsCardLayout(size: CGSize(width: 360.67, height: 214))
        XCTAssertEqual(cc.linkH, 16); near(cc.h, (214 - 16) / 2, "§1.7c H = (B − 16)/2"); XCTAssertEqual(cc.linkButton.height, 16)
    }

    // MARK: test 3 — §1.8 narrow cards (row 1 needs TW ≥ 262)

    func testNarrowCardsReportRow1() {
        XCTAssertTrue(euclideousResetsCardLayout(size: CGSize(width: 262, height: 233)).row1Fits, "§1.8: TW == 262 fits")
        XCTAssertFalse(euclideousResetsCardLayout(size: CGSize(width: 261, height: 233)).row1Fits, "§1.8: TW < 262 reported")
    }
}
