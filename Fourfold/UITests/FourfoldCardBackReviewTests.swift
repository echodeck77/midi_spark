//  FourfoldCardBackReviewTests.swift — CARD BACKS adversarial review (2026-10-28), the reviewer's reproductions kept as regression tests of the REAL app in the simulator. MIX ROWS (2026-11-03): the backs are retired, so the
//  tests that drove them (the pitch pad, ADD HITS) are gone and the two that still mean something run on the MIX panel's part toggles and sliders.
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
    func openBacks() { app.buttons["Mix"].tap(); Thread.sleep(forTimeInterval: 0.6) }   // MIX ROWS: the panel replaces the cards at once

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

    /// A part's sliders stay live while the part is off — a touch writes (OCT, TRANS) — but a slider NEVER switches the part on, and a touch on one tile reaches no other control (MIX ROWS: the card backs' pads, as sliders).
    func testAnOffPartsSlidersWriteButNeverSwitchThePartOn() {
        launch(); openBacks()
        let lane1 = app.el("Lane 1")
        func tile(_ prefix: String) -> XCUIElement { lane1.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch }
        need(tile("Notes, off"), "lane 1's NOTES part starts off on the factory document")
        let oct = need(tile("Notes octave"), "the notes OCT boxes"); XCTAssertEqual(oct.label, "Notes octave 0")
        let before = settled()
        oct.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.05, thenDragTo: oct.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)))
        let after = settled()
        XCTAssertNotEqual(after.snap, before.snap, "an OFF part's OCT slider took a drag and wrote nothing"); XCTAssertTrue(after.consistent, after.raw)
        XCTAssertNotEqual(tile("Notes octave").label, "Notes octave 0", "the value moved")
        XCTAssertTrue(tile("Notes, off").exists, "writing the octave left the NOTES part off")
        let trans = need(tile("Notes transpose"), "the notes TRANS tile")
        trans.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2)).tap()      // MIX v2: TRANS is a pair of halves — the upper half steps up
        XCTAssertEqual(tile("Notes transpose").label, "Notes transpose +1"); XCTAssertTrue(tile("Notes, off").exists, "…and so did the transpose")
        XCTAssertNotEqual(tile("Notes octave").label, "Notes octave 0", "a tap on one tile did not fall through to another")
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
}
