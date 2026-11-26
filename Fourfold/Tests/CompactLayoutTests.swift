//  CompactLayoutTests.swift — COMPACT LAYOUT ferry (2026-11-26): the pure size-class + Compact layout layer
//  (`euclideousSizeClass` / `euclideousCompactLayout` / `euclideousCompactFloors` / `euclideousCompactStripParts` and the
//  generalised `euclideousScaleToFit(ref:)`). Foundation-only; the Compact views (slice 4) lay out from these.

import XCTest

final class CompactLayoutTests: XCTestCase {
    private func close(_ a: CGFloat, _ b: CGFloat, _ m: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(Double(a), Double(b), accuracy: 0.001, m, file: file, line: line)
    }
    /// A clean Compact layout flags exactly the inherent chip floor (§2.3) and nothing else.
    private func clean(_ floors: [EuclideousPageFloor]) -> Bool { floors == [.compactLaneChip] }
    private func kind(_ w: CGFloat) -> EuclideousHeaderLayout.Kind { euclideousHeaderKind(containerW: w - 32, isLandscape: true) }
    private func floorsAt(_ w: CGFloat, _ h: CGFloat) -> [EuclideousPageFloor] {
        euclideousCompactLayout(size: CGSize(width: w, height: h), headerKind: kind(w)).floors
    }

    // MARK: §1.1 / §1.5 — the size class (§6 test 1, test 8). Compact is OFF by default (dev-only); OFF ⇒ always FULL.
    func testSizeClasses() {
        let ref = EuclideousScaleToFit.landscapeRef
        // OFF (the default / release): always FULL, at any size
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: 900, height: 600), compactMode: .off), .full, "OFF disables Compact")
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: 400, height: 300), compactMode: .off), .full, "OFF: even a tiny landscape is FULL")
        // AUTO: FULL at/above the reference in BOTH dims, else COMPACT
        XCTAssertEqual(euclideousSizeClass(size: ref, compactMode: .auto), .full)
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: 1194, height: 834), compactMode: .auto), .full)
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: 900, height: 600), compactMode: .auto), .compact)
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: ref.width - 1, height: ref.height), compactMode: .auto), .compact, "1 pt under the ref width")
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: ref.width, height: ref.height - 1), compactMode: .auto), .compact, "1 pt under the ref height")
        // portrait is NEVER Compact (out of scope), whatever the mode
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: 600, height: 900), compactMode: .auto), .full, "portrait")
        XCTAssertEqual(euclideousSizeClass(size: EuclideousScaleToFit.portraitRef, compactMode: .always), .full, "portrait ignores ALWAYS")
        // §1.5 ALWAYS vs AUTO at 1366×1024 (§6 test 8)
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: 1366, height: 1024), compactMode: .always), .compact, "ALWAYS @ 1366×1024 → Compact")
        XCTAssertEqual(euclideousSizeClass(size: CGSize(width: 1366, height: 1024), compactMode: .auto), .full, "AUTO @ 1366×1024 → FULL")
        // the dev-toggle storage round-trips; an unknown value is OFF
        for m in [EuclideousCompactMode.off, .auto, .always] { XCTAssertEqual(EuclideousCompactMode(storage: m.storage), m) }
        XCTAssertEqual(EuclideousCompactMode(storage: "garbage"), .off, "unknown storage ⇒ OFF (Compact disabled)")
    }

    // MARK: §2 — the Compact layout at 900×600 (§6 test 2 / §9.2)
    func testLayoutAt900x600() {
        let size = CGSize(width: 900, height: 600)
        let L = euclideousCompactLayout(size: size, headerKind: kind(size.width))
        print("COMPACT-900x600 header=\(kind(size.width)) leftW=\(L.leftW) rightW=\(L.rightW) card=\(L.card.height) cardContent=\(L.card.height - 20) rightPanel=\(L.rightPanel.height) floors=\(L.floors)")
        // §2.2: tab strip 28, strips panel 219, four 50-tall strips
        close(L.strip.height, 28); close(L.stripsPanel.height, 219)
        XCTAssertEqual(L.laneStrips.count, 4)
        for s in L.laneStrips { close(s.height, 50); close(s.width, L.leftW - 2 * EuclideousCompactMetrics.panelPad) }
        // §2.1: left column = 54 % of the body, never under 476
        XCTAssertGreaterThanOrEqual(L.leftW, 476)
        close(L.leftW, max(476, (0.54 * (900 - 16)).rounded()))
        close(L.rightW, (900 - 16) - L.leftW - 8)
        // columns don't overlap and sit inside the 8 pt page padding
        XCTAssertGreaterThanOrEqual(L.rightTab.minX, L.strip.maxX + 8 - 0.001)
        XCTAssertLessThanOrEqual(L.rightTab.maxX, size.width - 8 + 0.001)
        // §6 test 2 / §7: EUCLID fits — the Compact card (no comet row) clears the 192 floor
        let cardContentH = L.card.height - EuclideousLaneCardMetrics.inset * 2
        XCTAssertGreaterThanOrEqual(cardContentH, EuclideousLaneCardMetrics.rhythmZonesFloor, "EUCLID fits at 900×600 (content \(cardContentH))")
        // clean: only the inherent chip floor
        XCTAssertTrue(clean(L.floors), "no non-chip floor at 900×600: \(L.floors)")
        // §2.2: the ALL row reserves 46 and the card shrinks by exactly 46 + its gap
        let withAll = euclideousCompactLayout(size: size, headerKind: kind(size.width), allRow: 46)
        close(withAll.allRowRect.height, 46)
        close(withAll.card.height, L.card.height - 46 - 8, "the card loses the ALL row + its gap")
        XCTAssertEqual(L.allRowRect, .zero, "no ALL row when allRow is 0")
    }

    // MARK: §2.3 — a lane strip's parts (chip | PLAY RIFF | steps | PLAY STACK)
    func testStripParts() {
        let size = CGSize(width: 900, height: 600)
        let L = euclideousCompactLayout(size: size, headerKind: kind(size.width))
        let p = euclideousCompactStripParts(stripRect: L.laneStrips[0])
        close(p.chip.width, 22); close(p.playRiff.width, 44); close(p.playStack.width, 44)
        XCTAssertLessThan(p.chipHit.width, 44, "§2.3 the chip hit area is under 44 (reported as .compactLaneChip)")
        XCTAssertGreaterThan(p.steps.width, EuclideousCompactMetrics.stepsFloor, "the steps area is usable at 900×600")
        close(p.playStack.maxX, L.laneStrips[0].maxX - EuclideousCompactMetrics.stripPadH, "PLAY STACK at the trailing edge")
        // order, non-overlapping
        XCTAssertLessThanOrEqual(p.chip.maxX, p.playRiff.minX)
        XCTAssertLessThanOrEqual(p.playRiff.maxX, p.steps.minX)
        XCTAssertLessThanOrEqual(p.steps.maxX, p.playStack.minX)
    }

    // MARK: §1.2 / §1.3 — the Compact design minimum (the sweep); compactRef is clean and ≤ 900×600 (§6 test 3 / §9.2)
    func testCompactMinimumSweep() {
        let ref = EuclideousScaleToFit.compactRef
        XCTAssertLessThanOrEqual(ref.width, 900); XCTAssertLessThanOrEqual(ref.height, 600)   // §1.2
        XCTAssertTrue(clean(floorsAt(ref.width, ref.height)), "compactRef clean: \(floorsAt(ref.width, ref.height))")
        // it IS a minimum: a row under the ref height flags the card floor
        XCTAssertFalse(clean(floorsAt(ref.width, ref.height - 8)), "under compactRef height → a floor")
        // the empirical minimums for the report
        var minW: CGFloat = 0, minH: CGFloat = 0
        for w in stride(from: CGFloat(500), through: 900, by: 2) where clean(floorsAt(w, 800)) { minW = w; break }
        for h in stride(from: CGFloat(470), through: 700, by: 1) where clean(floorsAt(820, h)) { minH = h; break }
        print("COMPACT-MIN-SWEEP smallest clean width @ h800 = \(minW); smallest clean height @ w820 = \(minH); compactRef = \(ref.width)×\(ref.height)")
        XCTAssertGreaterThan(minW, 0, "found a clean width"); XCTAssertGreaterThan(minH, 0, "found a clean height")
        XCTAssertLessThanOrEqual(minW, ref.width + 0.001, "compactRef width is no smaller than the swept minimum width")
        XCTAssertLessThanOrEqual(minH, ref.height + 0.001, "compactRef height is no smaller than the swept minimum height")
    }

    // MARK: §1.3 — the generalised scale-to-fit (Compact ref); the no-arg form is unchanged
    func testScaleToFitWithCompactRef() {
        let ref = EuclideousScaleToFit.compactRef
        let big = euclideousScaleToFit(CGSize(width: 1000, height: 650), ref: ref)   // ≥ ref in both → 1×
        XCTAssertFalse(big.scaled); close(big.scale, 1)
        let small = euclideousScaleToFit(CGSize(width: ref.width / 2, height: ref.height), ref: ref)   // half width → 0.5, centred
        XCTAssertTrue(small.scaled); close(small.renderSize.width, ref.width); close(small.scale, 0.5)
        XCTAssertGreaterThan(small.origin.y, 0)   // centred vertically in the taller-than-needed window
        // the no-arg form is byte-identical to passing the orientation reference
        XCTAssertEqual(euclideousScaleToFit(CGSize(width: 900, height: 600)),
                       euclideousScaleToFit(CGSize(width: 900, height: 600), ref: EuclideousScaleToFit.landscapeRef))
        XCTAssertEqual(euclideousScaleToFit(CGSize(width: 1300, height: 800)),
                       euclideousScaleToFit(CGSize(width: 1300, height: 800), ref: EuclideousScaleToFit.landscapeRef), "no-op at/above the ref unchanged")
    }
}
