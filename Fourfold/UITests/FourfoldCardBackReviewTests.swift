//  FourfoldCardBackReviewTests.swift — CARD BACKS adversarial review (2026-10-28), the reviewer's reproductions kept as regression tests of the REAL app in the simulator.
//    sh Scripts/fourfold-harness/ui-tests.sh "iPad mini" FourfoldUITests/FourfoldCardBackReviewTests

import XCTest

final class FourfoldCardBackReviewTests: XCTestCase {
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

    /// On the FACTORY document every lane's NOTES part is off (no lit note) and offers TURN ON NOTES: the tap turns it on in ONE step (it lights the lowest note, since "on" needs a lit note).
    func testTurnOnNotesOnTheFactoryDocumentTurnsTheNotesPartOnInOneStep() {
        let p0 = launch(); openBacks()
        need(app.el("Turn on notes"), "the invitation on the factory document").tap(); let p1 = settled()
        XCTAssertNotEqual(p1.snap, p0.snap, "TURN ON NOTES changed nothing"); XCTAssertEqual(p1.undo, 1, p1.raw); XCTAssertTrue(p1.consistent, p1.raw)
        XCTAssertTrue(app.els(prefix: "Notes, on").firstMatch.exists, "the NOTES part reads on")
        XCTAssertFalse(app.els(prefix: "Notes, off").element(boundBy: 0).exists && app.els(prefix: "Notes, off").element(boundBy: 0).frame.minX < app.el("Lane 2 mix").frame.minX, "lane 1's NOTES part is no longer off")
        app.buttons["Undo"].tap(); let u = settled()
        XCTAssertEqual(u.snap, p0.snap, "undo returns to the factory document")
    }

    /// A tap anywhere on an OFF part's XY pad changes nothing — in particular it does not fall through to the OCT stepper under it.
    func testATapOnAnOffPartsPadChangesNothingAndReachesNoOtherControl() {
        launch(); openBacks()
        app.els(prefix: "Riff, on").firstMatch.tap(); let off = settled()
        let pad = app.els(prefix: "Riff velocity").firstMatch
        for (dx, dy) in [(0.9, 0.9), (0.9, 0.5), (0.1, 0.9), (0.5, 0.97)] {
            pad.coordinate(withNormalizedOffset: CGVector(dx: dx, dy: dy)).tap()
        }
        let after = settled()
        XCTAssertEqual(after.snap, off.snap, "an OFF pad took a touch that wrote something: \(after.raw)"); XCTAssertEqual(after.undo, off.undo, after.raw)
        XCTAssertEqual(app.els(prefix: "Riff octave").firstMatch.label, "Riff octave, 0")
    }

    /// VoiceOver reads a control's label and then its value: the OCT stepper carries its value in its label, so it must have no separate value (or it is said twice).
    func testTheOctStepperDoesNotSpeakItsValueTwice() {
        launch(orientation: .portrait); openBacks()
        let oct = need(app.els(prefix: "Riff octave").firstMatch, "the riff's OCT stepper")
        let v = value(oct)
        XCTAssertFalse(!v.isEmpty && oct.label.contains(v) && oct.label != v, "label [\(oct.label)] and value [\(v)] say the octave twice")
    }

    /// A 500 pt wide window (Split View half, a small AUM window; it is centred on the screen, so everything is judged against the gear, which ends at the page's trailing edge): HOLD, LATCH and the card-side switch stay inside it —
    /// the header takes a third row there.
    func testAPortraitWindow500WideKeepsHoldAndLatchInsideThePage() {
        launch(["--window-size=500x900"], orientation: .portrait)
        let edge = need(app.buttons["Settings"], "the gear (the page's trailing edge)").frame.maxX
        for name in ["Hold", "Latch", "Mix"] {
            let b = need(app.buttons[name], "the \(name) control")
            XCTAssertLessThanOrEqual(b.frame.maxX, edge + 1, "\(name) ends at \(b.frame.maxX), past the page's edge \(edge)")
        }
        XCTAssertGreaterThan(app.buttons["Hold"].frame.minY, app.buttons["Mix"].frame.maxY - 1, "NOTES sits on its own row below the switch")
    }

    /// The TURN ON NOTES invitation's touch target and the NOTES label's must not overlap (the invitation slides clear of the label); checked on lane 1 of whatever iPad this runs on.
    func testTheInvitationAndTheNotesLabelDoNotShareATouchTarget() {
        launch(orientation: .landscapeLeft); openBacks()
        let label = need(app.els(prefix: "Notes, off").element(boundBy: 0), "lane 1's NOTES switch"), inv = need(app.el("Turn on notes"), "its invitation")
        XCTAssertFalse(label.frame.intersects(inv.frame), "label \(label.frame) and invitation \(inv.frame) overlap")
    }
}
