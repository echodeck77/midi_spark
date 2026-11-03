//  FourfoldPitchDragReviewTests.swift — CARD BACKS v2 adversarial review (2026-10-28, reviewer-added), kept for the MIX panel (2026-11-03): a slider drag is ONE undo step however many values it crosses (the pad's burst, now on the sliders).
//  The reviewer's point stands: a tap is trivially one step; only a continuous DRAG proves the burst. This drags a TRANS slider across most of its range in ONE gesture.
//    sh Scripts/fourfold-harness/ui-tests.sh "iPad mini" FourfoldUITests/FourfoldPitchDragReviewTests

import XCTest

final class FourfoldPitchDragReviewTests: XCTestCase {
    var app: XCUIApplication!
    override func setUp() { continueAfterFailure = true }

    @discardableResult func launch(_ extra: [String] = [], orientation: UIDeviceOrientation = .landscapeLeft) -> UndoProbeReading {
        app = XCUIApplication(); app.launchArguments = ["--fresh", "--undo-probe"] + extra; app.launch()
        XCUIDevice.shared.orientation = orientation
        return settled()
    }
    func read() -> UndoProbeReading { UndoProbeReading((app.descendants(matching: .any).matching(identifier: "undoProbe").firstMatch.value as? String) ?? "no probe") }
    func settled() -> UndoProbeReading {
        Thread.sleep(forTimeInterval: 0.45)
        var last = read()
        for _ in 0..<8 { Thread.sleep(forTimeInterval: 0.35); let now = read(); if now.raw == last.raw { return now }; last = now }
        return last
    }
    func openBacks() { app.buttons["Mix"].tap(); Thread.sleep(forTimeInterval: 0.6) }

    /// ONE continuous drag across a TRANS slider (crossing many whole steps) must be ONE undo step, and a single ↶ must return to exactly the pre-drag document.
    func testADragAcrossASliderIsExactlyOneUndoStep() {
        let p0 = launch(); openBacks()
        let trans = need(app.el("Lane 1").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Riff transpose")).firstMatch, "the riff's TRANS slider")
        let before = settled()
        trans.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 0.1, thenDragTo: trans.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)))
        let after = settled()
        XCTAssertNotEqual(after.snap, before.snap, "the drag wrote nothing: \(after.raw)")
        XCTAssertTrue(after.consistent, after.raw)
        XCTAssertEqual(after.undo, before.undo + 1, "a single slider drag should add EXACTLY ONE undo step, not one per value crossed: \(after.raw)")
        app.buttons["Undo"].tap(); let u = settled()
        XCTAssertEqual(u.snap, p0.snap, "one ↶ should return to the pre-drag document in a single step: \(u.raw)")
    }
}
