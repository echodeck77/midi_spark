//  SmallWindowTests.swift
//  SMALL-WINDOW FALLBACK ferry (2026-10-24): below `euclideousPageTooSmall`'s threshold, EuclideousPage
//  stops laying out for real and shows a scaled-down mockup of itself instead (Paul: "shrinking the
//  entire interface so it's obvious the user needs to resize"). This is a NEW, coarser tier below the
//  existing per-panel `floors` system (PageLayoutTests.swift) — floors stay unshrunk-but-reported as
//  before; this tier is for windows too small for that approach to stay usable at all.

import XCTest

final class SmallWindowTests: XCTestCase {

    private let landscapeRef = CGSize(width: 1190, height: 726)   // PageLayoutTests.swift's own two
    private let portraitRef = CGSize(width: 814, height: 1102)    // reference screenshots

    // MARK: - euclideousPageTooSmall

    func testReferenceSizesAreNeverTooSmall() {
        XCTAssertFalse(euclideousPageTooSmall(landscapeRef))
        XCTAssertFalse(euclideousPageTooSmall(portraitRef))
    }

    func testThresholdIsExactlyThePluginsOwnPreferredContentSizeHint() {
        // FourfoldViewController.swift's preferredContentSize is CGSize(760, 480) -- "too small" means
        // exactly "smaller than what we already told the host/OS we wanted."
        XCTAssertFalse(euclideousPageTooSmall(CGSize(width: 760, height: 480)), "exactly at the floor, landscape")
        XCTAssertTrue(euclideousPageTooSmall(CGSize(width: 759, height: 480)), "1pt under on width")
        XCTAssertTrue(euclideousPageTooSmall(CGSize(width: 760, height: 479)), "1pt under on height")
        XCTAssertFalse(euclideousPageTooSmall(CGSize(width: 480, height: 760)), "exactly at the floor, portrait")
        XCTAssertTrue(euclideousPageTooSmall(CGSize(width: 479, height: 760)))
        XCTAssertTrue(euclideousPageTooSmall(CGSize(width: 480, height: 759)))
    }

    func testDocumentedWindowedAUMPanelCaseStaysInTheExistingFloorsTierNotThisOne() {
        // PageLayoutTests.swift's own "windowed AUM panels" case (900x600) trips 5 legibility floors --
        // but it's ABOVE this ferry's threshold (760x480), so it keeps rendering for real, cramped but
        // interactive, exactly as it did before this ferry. Only genuinely tiny windows trip the new tier.
        XCTAssertFalse(euclideousPageTooSmall(CGSize(width: 900, height: 600)))
    }

    func testDocumentedIPadMiniLandscapePluginGuessIsTooSmall() {
        // PageLayoutTests.swift's "iPad-mini-landscape-plugin" guess (355x274) -- genuinely too small.
        XCTAssertTrue(euclideousPageTooSmall(CGSize(width: 355, height: 274)))
    }

    func testOrientationIsDecidedByTheLiveSizeNotAFixedAssumption() {
        // Landscape-shaped (700>500): judged against the landscape floor (760x480) -- under its width floor.
        XCTAssertTrue(euclideousPageTooSmall(CGSize(width: 700, height: 500)))
        // Portrait-shaped (500<800): judged against the portrait floor (480x760) -- clears both.
        XCTAssertFalse(euclideousPageTooSmall(CGSize(width: 500, height: 800)))
        // Same width, but short enough to fall under the portrait floor's height (760).
        XCTAssertTrue(euclideousPageTooSmall(CGSize(width: 500, height: 700)))
    }

    // MARK: - euclideousTooSmallLayout

    func testScaleIsOneAtTheReferenceSizeItself() {
        let l = euclideousTooSmallLayout(size: landscapeRef)
        XCTAssertEqual(l.reference, landscapeRef)
        XCTAssertEqual(l.scale, 1, accuracy: 1e-9)
        XCTAssertEqual(l.origin.x, 0, accuracy: 1e-9); XCTAssertEqual(l.origin.y, 0, accuracy: 1e-9)
    }

    func testScaleHalvesAtHalfTheReferenceSize() {
        let half = CGSize(width: landscapeRef.width / 2, height: landscapeRef.height / 2)
        let l = euclideousTooSmallLayout(size: half)
        XCTAssertEqual(l.scale, 0.5, accuracy: 1e-9)
        // centred: the scaled content (half the real box) leaves no slack in either axis here, so origin is (0,0)
        XCTAssertEqual(l.origin.x, 0, accuracy: 1e-9); XCTAssertEqual(l.origin.y, 0, accuracy: 1e-9)
    }

    func testScalePicksTheSmallerAxisAndCentresTheSlack() {
        // Landscape-shaped (800>600), but relatively taller/narrower than the reference's own 1190:726
        // aspect ratio -- width is the binding constraint (0.672 < 0.826), leaving vertical slack, centred.
        let box = CGSize(width: 800, height: 600)
        let l = euclideousTooSmallLayout(size: box)
        XCTAssertEqual(l.reference, landscapeRef)
        XCTAssertEqual(l.scale, box.width / landscapeRef.width, accuracy: 1e-9)
        let scaledH = l.reference.height * l.scale
        XCTAssertEqual(l.origin.x, 0, accuracy: 1e-9)
        XCTAssertEqual(l.origin.y, (box.height - scaledH) / 2, accuracy: 1e-9)
        XCTAssertGreaterThan(l.origin.y, 0, "there should be real vertical slack to centre into")
    }

    func testDegenerateSizesNeverProduceANegativeOrNaNScale() {
        for size in [CGSize.zero, CGSize(width: -10, height: -10), CGSize(width: 1, height: 0), CGSize(width: 0, height: 1)] {
            let l = euclideousTooSmallLayout(size: size)
            XCTAssertFalse(l.scale.isNaN, "\(size)")
            XCTAssertGreaterThanOrEqual(l.scale, 0.05, "\(size)")
        }
    }

    func testPortraitReferenceUsedForPortraitShapedBoxes() {
        let l = euclideousTooSmallLayout(size: CGSize(width: 300, height: 500))
        XCTAssertEqual(l.reference, portraitRef)
    }
}
