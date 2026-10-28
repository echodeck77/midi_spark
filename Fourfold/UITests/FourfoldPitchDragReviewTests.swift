//  FourfoldPitchDragReviewTests.swift — CARD BACKS v2 adversarial review (2026-10-28, reviewer-added).
//  The existing pitch-pad coverage only ever TAPS the pad (one write = trivially one undo step). CARD BACKS v2 §6.8 and the
//  status log both claim "one undo step per DRAG, a drag that crosses detents changes the values as it goes" — the whole reason
//  the pad carries an EuclideousPadUndoBurst. Nothing drags it. This drags it across many detents in ONE continuous gesture.
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
    func openBacks() { app.buttons["Mix"].tap(); Thread.sleep(forTimeInterval: 0.9) }

    /// ONE continuous drag across the PITCH pad (top-left → bottom-right, crossing many octave rows and transpose columns) must be
    /// ONE undo step, and a single ↶ must return to exactly the pre-drag document.
    func testADragAcrossThePitchPadIsExactlyOneUndoStep() {
        let p0 = launch(); openBacks()
        let pitch = need(app.els(prefix: "Riff pitch").firstMatch, "the riff's PITCH pad")
        let before = settled()
        // a slow press-and-drag from one corner to the far corner: the gesture passes through many detents, so many writes, one burst.
        pitch.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.08))
            .press(forDuration: 0.1, thenDragTo: pitch.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.92)))
        let after = settled()
        XCTAssertNotEqual(after.snap, before.snap, "the drag wrote nothing: \(after.raw)")
        XCTAssertTrue(after.consistent, after.raw)
        XCTAssertEqual(after.undo, before.undo + 1, "a single pitch-pad drag should add EXACTLY ONE undo step, not one per detent crossed: \(after.raw)")
        app.buttons["Undo"].tap(); let u = settled()
        XCTAssertEqual(u.snap, p0.snap, "one ↶ should return to the pre-drag document in a single step: \(u.raw)")
    }
}
