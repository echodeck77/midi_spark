//  EuclidTabV2Tests.swift — EUCLID tab v2 (2026-11-15) §7: the pure functions (§1 layout; later slices add HITS/inert).

import XCTest
#if canImport(CoreGraphics)
import CoreGraphics
#endif

final class EuclidTabV2Tests: XCTestCase {
    private let acc = 0.02

    // §7.1 — the layout at both references (the spec's W,H; the formulas are what's pinned).
    func testLayoutPortrait() {
        let l = euclideousEuclidTabLayout(W: 367, H: 229.67)
        XCTAssertEqual(l.A, 145.67, accuracy: acc)
        XCTAssertEqual(l.half, 181.5, accuracy: acc)
        XCTAssertEqual(l.col, 88.75, accuracy: acc)
        XCTAssertEqual(l.stepsCol.minX, 92.75, accuracy: acc)
        XCTAssertEqual(l.stepperValue(l.hitsCol).height, 65.67, accuracy: acc)
        XCTAssertEqual(l.offset.width, 181.5, accuracy: acc); XCTAssertEqual(l.offset.minX, 185.5, accuracy: acc)
        XCTAssertEqual(l.offset.height, 50.83, accuracy: acc); XCTAssertEqual(l.offset.minY, 0, accuracy: acc)   // EUCLID FROM §1.3: (A − 36 − 8)/2
        XCTAssertEqual(l.tilt.minY, 54.83, accuracy: acc); XCTAssertEqual(l.tilt.height, 50.83, accuracy: acc)
        XCTAssertEqual(l.from.minY, 109.67, accuracy: acc); XCTAssertEqual(l.from.height, 36, accuracy: acc)      // level with the HITS − button (y = A − 36)
        XCTAssertEqual(l.g, 37, accuracy: acc)
        XCTAssertEqual(l.groupX, [0, 125, 250])
        XCTAssertEqual(l.rowBY, 151.67, accuracy: acc); XCTAssertEqual(l.rowCY, 193.67, accuracy: acc)
        XCTAssertTrue(l.floors.isEmpty, "no floor breached at the portrait reference")
    }
    func testLayoutLandscape() {
        let l = euclideousEuclidTabLayout(W: 360.67, H: 229)
        XCTAssertEqual(l.A, 145, accuracy: acc)
        XCTAssertEqual(l.half, 178.33, accuracy: acc)
        XCTAssertEqual(l.col, 87.17, accuracy: acc)
        XCTAssertEqual(l.stepperValue(l.stepsCol).height, 65, accuracy: acc)
        XCTAssertEqual(l.offset.height, 50.5, accuracy: acc); XCTAssertEqual(l.offset.minX, 182.33, accuracy: acc)   // EUCLID FROM §1.3
        XCTAssertEqual(l.from.minY, 109, accuracy: acc); XCTAssertEqual(l.from.height, 36, accuracy: acc)
        XCTAssertEqual(l.g, 36.30, accuracy: acc)
        XCTAssertEqual(l.groupX[1], 122.89, accuracy: acc); XCTAssertEqual(l.groupX[2], 245.78, accuracy: acc)
        XCTAssertEqual(l.rowBY, 151, accuracy: acc); XCTAssertEqual(l.rowCY, 193, accuracy: acc)
    }

    // §7.2 — alignment: Rows B and C share the nine columns' x ranges; FLIP HITS spans columns 4–6 and LET RING 7–9; the last row ends at H.
    func testAlignment() {
        for (W, H) in [(367.0, 229.67), (360.67, 229.0), (320.0, 260.0)] {
            let l = euclideousEuclidTabLayout(W: CGFloat(W), H: CGFloat(H))
            // every lower-grid column has the same x at Row B and Row C
            for i in 0..<9 {
                XCTAssertEqual(l.colTile(i, y: l.rowBY).minX, l.colTile(i, y: l.rowCY).minX, accuracy: acc, "col \(i) x shared")
            }
            // FLIP HITS (group 1) spans columns 3…5 (0-based); LET RING (group 2) spans 6…8
            let flip = l.groupTile(1, y: l.rowCY)
            XCTAssertEqual(flip.minX, l.colTile(3, y: l.rowCY).minX, accuracy: acc)
            XCTAssertEqual(flip.maxX, l.colTile(5, y: l.rowCY).maxX, accuracy: acc, "FLIP HITS ends at column 6")
            let ring = l.groupTile(2, y: l.rowCY)
            XCTAssertEqual(ring.minX, l.colTile(6, y: l.rowCY).minX, accuracy: acc)
            XCTAssertEqual(ring.maxX, l.colTile(8, y: l.rowCY).maxX, accuracy: acc, "LET RING ends at column 9")
            // the last row ends exactly at H
            XCTAssertEqual(l.rowCY + l.rowH, CGFloat(H), accuracy: acc, "Row C ends at H")
            // the whole grid spans 0 … W
            XCTAssertEqual(l.colTile(8, y: l.rowBY).maxX, CGFloat(W), accuracy: acc, "grid ends at W")
            // the stepper column splits to A exactly (+36, sp4, value, sp4, −36)
            XCTAssertEqual(l.stepperMinus(l.hitsCol).maxY, l.A, accuracy: acc)
        }
    }

    // §7.5 — OFFSET / TILT inert: true only when nothing the control could be would change what plays.
    private func line(hits: Int, steps: Int = 8, flip: Bool = false, rotate: Int = 0) -> EuclidLine {
        var l = EuclidLine(noteSel: .all)
        l.steps = steps; l.pulses = hits; l.rotate = rotate
        if flip { l.patternMiss = true }
        return l
    }
    func testOffsetAndTiltInert() {
        // 0 of 8 → nothing to move: both inert.
        XCTAssertTrue(euclideousOffsetIsInert(line(hits: 0)))
        XCTAssertTrue(euclideousTiltIsInert(line(hits: 0)))
        // 8 of 8 → every step a hit: both inert.
        XCTAssertTrue(euclideousOffsetIsInert(line(hits: 8)))
        XCTAssertTrue(euclideousTiltIsInert(line(hits: 8)))
        // 0 of 8 with FLIP HITS → every step a hit after the flip: both inert.
        XCTAssertTrue(euclideousOffsetIsInert(line(hits: 0, flip: true)))
        XCTAssertTrue(euclideousTiltIsInert(line(hits: 0, flip: true)))
        // 3 of 8 → an asymmetric pattern: rotating by one changes it, tilting moves hits ⇒ NEITHER inert.
        XCTAssertFalse(euclideousOffsetIsInert(line(hits: 3)), "3/8 OFFSET does something")
        XCTAssertFalse(euclideousTiltIsInert(line(hits: 3)), "3/8 TILT does something")
        // 4 of 8 (alternating) → rotating by one flips every cell: OFFSET not inert.
        XCTAssertFalse(euclideousOffsetIsInert(line(hits: 4)), "4/8 OFFSET rotates to a different pattern")
    }
}
