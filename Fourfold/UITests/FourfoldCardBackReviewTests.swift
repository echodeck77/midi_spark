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

    /// On the FACTORY document every lane's NOTES part is off (no lit note): the NOTES label is the switch (there is no turn-on button) and one tap turns it on in ONE step — it lights the lowest note, since "on" needs a lit note.
    func testTheNotesLabelTurnsTheNotesPartOnInOneStepOnTheFactoryDocument() {
        let p0 = launch(); openBacks()
        XCTAssertFalse(app.el("Turn on notes").exists, "no turn-on pill on the back")
        need(app.els(prefix: "Notes, off").firstMatch, "lane 1's NOTES label on the factory document").tap(); let p1 = settled()
        XCTAssertNotEqual(p1.snap, p0.snap, "the NOTES label changed nothing"); XCTAssertEqual(p1.undo, 1, p1.raw); XCTAssertTrue(p1.consistent, p1.raw)
        XCTAssertTrue(app.els(prefix: "Notes, on").firstMatch.exists, "the NOTES part reads on")
        app.buttons["Undo"].tap(); let u = settled()
        XCTAssertEqual(u.snap, p0.snap, "undo returns to the factory document")
    }

    /// CARD BACKS v2 §5.5: the pads stay live while a part is off — a touch writes (velocity / gate, octave / transpose) — but a pad NEVER switches the part on, and a touch on one pad reaches no other control.
    func testAnOffPartsPadsWriteButNeverSwitchThePartOn() {
        launch(); openBacks()
        app.els(prefix: "Notes, off").firstMatch.tap(); app.els(prefix: "Notes, on").firstMatch.tap()      // on, then off again: lane 1's NOTES part is off with a lit note
        let off = settled()
        XCTAssertTrue(app.els(prefix: "Notes, off").firstMatch.exists)
        let pitch = app.els(prefix: "Notes pitch").firstMatch
        pitch.coordinate(withNormalizedOffset: CGVector(dx: 0.89, dy: 0.06)).tap(); let afterPitch = settled()
        XCTAssertNotEqual(afterPitch.snap, off.snap, "an OFF part's PITCH pad took a touch and wrote nothing"); XCTAssertTrue(afterPitch.consistent, afterPitch.raw)
        XCTAssertEqual(pitch.value as? String, "octave +2, transpose +7")
        XCTAssertTrue(app.els(prefix: "Notes, off").firstMatch.exists, "writing the pitch left the NOTES part off")
        let pad = app.els(prefix: "Notes velocity").firstMatch
        pad.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.1)).tap(); let afterPad = settled()
        XCTAssertNotEqual(afterPad.snap, afterPitch.snap, "an OFF part's VEL/GATE pad took a touch and wrote nothing")
        XCTAssertTrue(app.els(prefix: "Notes, off").firstMatch.exists, "…and left the part off")
        XCTAssertEqual(pitch.value as? String, "octave +2, transpose +7", "…and the touch did not fall through to the PITCH pad")
    }

    /// VoiceOver reads a control's label and then its value: the PITCH pad's octave and transpose are its VALUE, so the label must not carry them (or they are said twice).
    func testThePitchPadDoesNotSpeakItsValueTwice() {
        launch(orientation: .portrait); openBacks()
        let pitch = need(app.els(prefix: "Riff pitch").firstMatch, "the riff's PITCH pad")
        XCTAssertEqual(pitch.label, "Riff pitch"); XCTAssertEqual(pitch.value as? String, "octave 0, transpose 0")
        XCTAssertFalse(pitch.label.contains("octave"), "the label carries the value: \(pitch.label)")
    }

    /// A 500 pt wide window (Split View half, a small AUM window; it is centred on the screen, so everything is judged against the gear, which ends at the page's trailing edge): HOLD, LATCH and the strip's MIX stay inside it —
    /// TAB STRIP (2026-10-29): the header is two rows there (NOTES alone on row 2), and the lane strip sits below it.
    func testAPortraitWindow500WideKeepsHoldAndLatchInsideThePage() {
        launch(["--window-size=500x900"], orientation: .portrait)
        let edge = need(app.buttons["Settings"], "the gear (the page's trailing edge)").frame.maxX
        for name in ["Hold", "Latch", "Mix"] {
            let b = need(app.buttons[name], "the \(name) control")
            XCTAssertLessThanOrEqual(b.frame.maxX, edge + 1, "\(name) ends at \(b.frame.maxX), past the page's edge \(edge)")
        }
        XCTAssertGreaterThan(app.buttons["Mix"].frame.minY, app.buttons["Hold"].frame.maxY - 1, "the lane strip sits below the header")
    }

    /// ADD HITS' touch target and the riff label's must not overlap (the invitation slides clear of the label); lane 3 has no hits on the factory document, so it offers ADD HITS on whatever iPad this runs on.
    func testTheAddHitsInvitationAndTheRiffLabelDoNotShareATouchTarget() {
        launch(orientation: .landscapeLeft); openBacks()
        let label = need(app.els(prefix: "Riff, on").element(boundBy: 2), "lane 3's RIFF switch"), inv = need(app.el("Add hits"), "its invitation")
        XCTAssertFalse(label.frame.intersects(inv.frame), "label \(label.frame) and invitation \(inv.frame) overlap")
    }
}
