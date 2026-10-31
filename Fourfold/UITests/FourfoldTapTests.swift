//  FourfoldTapTests.swift — tap-through tests of the REAL app in the iOS simulator (2026-10-24). The page's logic is covered by the macOS unit tests, but its wiring — a tap reaching the engine and the label changing to say so — had no
//  test at all. Each test launches on the factory document (`--fresh`), drives controls by their accessibility labels and reads the result back from the labels and values a VoiceOver user would hear.
//  Scripts/fourfold-harness/ui-tests.sh runs these on every iPad size.

import XCTest

final class FourfoldTapTests: XCTestCase {
    override func setUp() { continueAfterFailure = false; XCUIDevice.shared.orientation = .portrait }

    func testPlayAndStopFlipTheButtonAndTheBarReadout() {
        let app = XCUIApplication.fresh()
        need(app.buttons["Play"], "the Play button")
        need(app.staticTexts["STOPPED"], "the stopped readout")
        app.buttons["Play"].tap()
        need(app.buttons["Stop"], "Stop after pressing Play")
        need(app.staticTexts.matching(NSPredicate(format: "label BEGINSWITH 'BAR '")).firstMatch, "a BAR n · n readout while playing")
        app.buttons["Stop"].tap()
        need(app.buttons["Play"], "Play after pressing Stop")
        need(app.staticTexts["STOPPED"], "the stopped readout again")
    }

    /// POLY RIFF (2026-10-29): the riff panel's four boxes are gone; a MONO | POLY control sits in their row, MONO selected on a fresh launch, and switching is a tap each way.
    func testTheRiffPanelHasAMonoPolyControlAndNoRiffBoxes() {
        let app = XCUIApplication.fresh()
        let mono = app.buttons["Mono"], poly = app.buttons["Poly"]
        need(mono, "the MONO segment"); need(poly, "the POLY segment")
        XCTAssertTrue(mono.isSelected, "MONO is the default"); XCTAssertFalse(poly.isSelected)
        XCTAssertEqual(app.els(prefix: "Riff 1").count, 0, "the four riff boxes are gone")
        poly.tap(); XCTAssertTrue(app.buttons["Poly"].isSelected); XCTAssertFalse(app.buttons["Mono"].isSelected)
        app.buttons["Mono"].tap(); XCTAssertTrue(app.buttons["Mono"].isSelected)
    }
    /// POLY: a tap on an empty cell makes a length-1 note, a second tap on it takes it away, and pressing a cell then dragging sideways stretches the note — the head cell reads "note, length 5", the cells it covers "held from step 4".
    func testPolyGridTapsAddAndRemoveAndADragStretchesANote() {
        let app = XCUIApplication.fresh()
        app.buttons["Poly"].tap()
        func cell(_ step: Int, rowFromTop: Int) -> XCUIElement { app.els(prefix: "Step \(step),").element(boundBy: rowFromTop) }
        need(cell(3, rowFromTop: 0), "the POLY grid's cell, step 3 on the top row")
        XCTAssertEqual(cell(3, rowFromTop: 0).value as? String, "off", "rank 8 is empty in the seeded riff")
        cell(3, rowFromTop: 0).tap()
        XCTAssertEqual(cell(3, rowFromTop: 0).value as? String, "note, length 1")
        cell(3, rowFromTop: 0).tap()
        XCTAssertEqual(cell(3, rowFromTop: 0).value as? String, "off", "a second tap takes the note away")
        cell(4, rowFromTop: 0).press(forDuration: 0.1, thenDragTo: cell(8, rowFromTop: 0))
        XCTAssertEqual(cell(4, rowFromTop: 0).value as? String, "note, length 5")
        XCTAssertEqual(cell(6, rowFromTop: 0).value as? String, "held from step 4")
        XCTAssertEqual(cell(9, rowFromTop: 0).value as? String, "off")
    }

    /// The POLY grid's cells that carry a lane arrow right now, per step — read from ONE accessibility snapshot of the whole screen (a live query resolves element by element while the arrows move).
    private func arrowCells(_ app: XCUIApplication) -> [String: [String]] {
        guard let snap = try? app.snapshot() else { return [:] }
        var out: [String: [String]] = [:]
        func walk(_ s: XCUIElementSnapshot) {
            let l = s.label
            if l.hasPrefix("Step "), l.contains(", lane "), let comma = l.firstIndex(of: ",") { out[String(l[..<comma]), default: []].append(l) }
            for c in s.children { walk(c) }
        }
        walk(snap)
        return out
    }
    /// POLY (2026-10-30): a hit that strikes a chord draws an arrow on EACH of its notes. Notes on the top two rows of every column make every hit a chord (with the seeded note); while the lanes play, some step shows two or more
    /// arrow cells at once.
    func testAChordShowsAnArrowOnEachOfItsNotes() {
        let app = XCUIApplication.fresh()
        app.buttons["Poly"].tap()
        func cell(_ step: Int, _ row: Int) -> XCUIElement { app.els(prefix: "Step \(step),").element(boundBy: row) }
        need(cell(1, 0), "the POLY grid")
        for step in 1...16 { for row in [0, 1] where cell(step, row).value as? String == "off" { cell(step, row).tap() } }
        app.buttons["Play"].tap()
        let deadline = Date().addingTimeInterval(20)
        var seen: [String: [String]] = [:]
        while Date() < deadline {
            seen = arrowCells(app)
            if seen.values.contains(where: { $0.count >= 2 }) { break }
            Thread.sleep(forTimeInterval: 0.25)
        }
        XCTAssertTrue(seen.values.contains(where: { $0.count >= 2 }), "a column holding a chord shows an arrow on each note while a lane is on it: \(seen)")
    }
    /// POLY REVERSE (2026-10-30): lane 1 walking in `direction` (a direction button's label) meets a held note at its LAST column on the way back — rank 8 held over steps 1…4 and rank 7 held over steps 3…4 both end on step 4, so
    /// while lane 1 is there ITS arrows sit on step 4's top two cells (plus the seeded single-column note there). A forward walk would have put them on steps 1 and 3, one at a time.
    private func assertLane1SeatsItsChordArrowsOnTheNotesLastColumn(direction: String, seconds: TimeInterval) {
        let app = XCUIApplication.fresh()
        app.buttons["Poly"].tap()
        func cell(_ step: Int, _ row: Int) -> XCUIElement { app.els(prefix: "Step \(step),").element(boundBy: row) }
        need(cell(1, 0), "the POLY grid")
        cell(1, 0).press(forDuration: 0.1, thenDragTo: cell(4, 0))
        cell(3, 1).press(forDuration: 0.1, thenDragTo: cell(4, 1))
        XCTAssertEqual(cell(1, 0).value as? String, "note, length 4"); XCTAssertEqual(cell(3, 1).value as? String, "note, length 2")
        let button = app.els(prefix: direction).element(boundBy: 0)
        if !button.exists { app.els(prefix: "Riff, ").firstMatch.tap() }
        need(button, "lane 1's \(direction) button on the RIFF tab"); button.tap()
        app.buttons["Play"].tap()
        let deadline = Date().addingTimeInterval(seconds)
        var seen: [String: [String]] = [:]
        func lane1(_ step: String) -> Int { (seen[step] ?? []).filter { $0.contains("lane 1") || $0.contains("lanes 1") }.count }
        while Date() < deadline {
            seen = arrowCells(app)
            if lane1("Step 4") >= 2 { break }
            Thread.sleep(forTimeInterval: 0.2)
        }
        XCTAssertGreaterThanOrEqual(lane1("Step 4"), 2, "lane 1's two held notes both strike on step 4: \(seen)")
    }
    func testAReversedLaneSeatsItsChordArrowsOnTheNotesLastColumn() { assertLane1SeatsItsChordArrowsOnTheNotesLastColumn(direction: "Backward Each Time", seconds: 30) }
    /// PING-PONG (2026-10-30): the same notes are met at their last column on the way back (the second visit of the end step), not only at their first on the way up.
    func testAPingPongLaneSeatsItsChordArrowsOnTheNotesLastColumnComingBack() { assertLane1SeatsItsChordArrowsOnTheNotesLastColumn(direction: "Forward, Then Back, Each End Twice", seconds: 60) }

    /// HOCKET (2026-10-27): the header button opens the pop-up, two chip taps make a lit swap rule, the button then reads "1 rule on", and closing leaves the rule lit.
    func testHocketPopupBuildsARuleAndTheButtonCountsIt() {
        let app = XCUIApplication.fresh()
        let button = app.els(prefix: "Hocket").firstMatch
        need(button, "the HOCKET button"); XCTAssertEqual(button.value as? String, "off")
        button.tap()
        need(app.buttons["Close"], "the pop-up's Close button")
        need(app.staticTexts["PICK AT LEAST ONE MAIN OUTPUT."], "the empty-MAIN hint")
        app.buttons["Main: red riff, off"].tap(); app.buttons["Alt: blue riff, off"].tap()
        need(app.buttons["Main: red riff, on"], "RED RIFF in MAIN"); need(app.buttons["Alt: blue riff, on"], "BLUE RIFF in ALT")
        app.buttons["Close"].tap()
        XCTAssertFalse(app.buttons["Close"].waitForExistence(timeout: 1), "the pop-up closed")
        XCTAssertEqual(app.els(prefix: "Hocket").firstMatch.value as? String, "1 rule on")
    }

    /// HOCKET §3 / acceptance: a 300 ms hold on a rule's tab opens DELETE RULE n, and tapping it removes the rule.
    func testHocketHoldOnARulesTabDeletesIt() {
        let app = XCUIApplication.fresh()
        app.els(prefix: "Hocket").firstMatch.tap()
        need(app.buttons["Close"], "the pop-up's Close button")
        app.buttons["Add a rule"].tap()
        let tab2 = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Rule 2")).firstMatch
        need(tab2, "rule 2's tab")
        tab2.press(forDuration: 0.8)
        need(app.buttons["Delete rule 2"], "the DELETE RULE 2 popover")
        app.buttons["Delete rule 2"].tap()
        XCTAssertFalse(tab2.waitForExistence(timeout: 1), "rule 2 is gone")
        need(app.buttons["Add a rule"], "the add button is back")
    }

    /// HOCKET §2.1 (review 2026-10-27): "the page below dimmed to 42% and still playing, closed by its ×, by the HOCKET button, or by a tap on the dimmed page". The scrim covers the page BELOW the header, so a tap on a header control
    /// (here Undo) acts on the page and leaves the pop-up open, while a tap on the dimmed page — the lower left, clear of the right-aligned card — closes it. (The scrim's hit area used to sit `headerBottomY` too high: a header tap closed
    /// the pop-up without acting, and the bottom of the page stayed live under the dim.)
    func testHocketHeaderStaysLiveWhilePopupIsOpenAndADimmedPageTapClosesIt() {
        let app = XCUIApplication.fresh()
        app.els(prefix: "Hocket").firstMatch.tap()
        need(app.buttons["Close"], "the pop-up's Close button")
        app.buttons["Add a rule"].tap()
        let tab2 = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Rule 2")).firstMatch
        need(tab2, "rule 2's tab")
        app.buttons["Undo"].tap()
        XCTAssertFalse(tab2.waitForExistence(timeout: 1.5), "Undo acted on the page: rule 2 is gone")
        XCTAssertTrue(app.buttons["Close"].exists, "and the pop-up stayed open")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.95)).tap()
        XCTAssertFalse(app.buttons["Close"].waitForExistence(timeout: 1.5), "a tap on the dimmed page (lower left) closed the pop-up")
    }

    /// HOCKET §4.11: every touch target is at least 44 tall, extending into the spacing around it. The unit segments are drawn 30 tall; a tap 6 pt ABOVE one (inside the 7 pt it extends by) still selects it, and so does one on a
    /// mode segment (34 tall, extends 5) 4 pt below.
    func testHocketTargetsUnder44TallTakeTapsInTheSpacingAroundThem() {
        let app = XCUIApplication.fresh()
        app.els(prefix: "Hocket").firstMatch.tap()
        need(app.buttons["Close"], "the pop-up's Close button")
        let steps = app.buttons["Steps"]; need(steps, "the STEPS unit segment")
        XCTAssertFalse(steps.isSelected, "HITS is the default unit")
        steps.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: -6)).tap()
        XCTAssertTrue(steps.waitForExistence(timeout: 1) && steps.isSelected, "a tap 6 pt above the 30-tall segment selected it")
        let pass = app.buttons["Pass the line"]; need(pass, "the PASS THE LINE segment")
        XCTAssertFalse(pass.isSelected)
        pass.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1)).withOffset(CGVector(dx: 0, dy: 4)).tap()
        XCTAssertTrue(pass.isSelected, "a tap 4 pt below the 34-tall segment selected it")
    }

    func testTheTempoButtonsStepTheBpm() {
        let app = XCUIApplication.fresh()
        need(app.el("Tempo, 120 beats per minute"), "the tempo control at 120")
        app.buttons["Add"].tap(); app.buttons["Add"].tap()
        need(app.el("Tempo, 122 beats per minute"), "122 BPM after two + taps")
        app.buttons["Remove"].tap()
        need(app.el("Tempo, 121 beats per minute"), "121 BPM after one − tap")
    }

    func testStepsUndoAndRedoGoThroughTheEngineAndBack() {
        let app = XCUIApplication.fresh()
        app.buttons["More steps, now 8"].firstMatch.tap()
        need(app.buttons["More steps, now 9"].firstMatch, "lane 1 at 9 steps after one + tap")
        app.buttons["Undo"].tap()
        need(app.buttons["More steps, now 8"].firstMatch, "8 steps after Undo")
        app.buttons["Redo"].tap()
        need(app.buttons["More steps, now 9"].firstMatch, "9 steps after Redo")
        app.buttons["Fewer steps, now 9"].firstMatch.tap()
        need(app.buttons["More steps, now 8"].firstMatch, "8 steps after the − button")
    }

    func testDraggingTheHitsFaderChangesTheHitCount() {
        let app = XCUIApplication.fresh()
        let hits = need(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch, "the HITS fader")
        XCTAssertEqual(value(hits), "3")
        hits.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.95)).press(forDuration: 0.05, thenDragTo: hits.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)))
        XCTAssertNotEqual(value(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch), "3", "dragging the HITS fader up should add hits")
    }

    func testDraggingOffsetMovesThePattern() {
        let app = XCUIApplication.fresh()
        let offset = need(app.otherElements.matching(NSPredicate(format: "label == %@", "OFFSET")).firstMatch, "the OFFSET slider")
        XCTAssertEqual(value(offset), "0 steps")
        offset.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)).press(forDuration: 0.05, thenDragTo: offset.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)))
        XCTAssertNotEqual(value(app.otherElements.matching(NSPredicate(format: "label == %@", "OFFSET")).firstMatch), "0 steps")
    }

    func testSoloLatchesAndReleases() {
        let app = XCUIApplication.fresh()
        let solo = need(app.switches["Solo lane 1"], "the lane 1 SOLO switch")
        XCTAssertEqual(value(solo), "off")
        solo.tap()
        XCTAssertEqual(value(app.switches["Solo lane 1"]), "on")
        app.switches["Solo lane 1"].tap()
        XCTAssertEqual(value(app.switches["Solo lane 1"]), "off")
    }

    func testEveryLaneTabOpensItsOwnContent() {
        let app = XCUIApplication.fresh()
        // TAB STRIP (2026-10-29): one strip chooses the tab for all four cards
        app.els(prefix: "Riff, ").firstMatch.tap()
        need(app.el("Advance every"), "the RIFF tab's ADVANCE EVERY row")   // (the WALK strip above it is dropped on a card too short for it — the iPad mini — so it is not the thing to look for)
        app.els(prefix: "Notes, ").firstMatch.tap()
        need(app.el("Notes layer, off, 0 notes lit"), "the NOTES tab's layer switch")
        app.els(prefix: "Listen, ").firstMatch.tap()
        need(app.el("Follow lane 2"), "the LISTEN tab's partner picker")
        app.buttons["Rhythm"].tap()
        need(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch, "the RHYTHM tab again")
    }

    /// CHORD CANON (2026-10-31): the CANON row under PITCH on the LISTEN tab — a lane's DELAY and SLIP step through the engine and back through undo; the UNIT is one value shared by all four rows (and undoable). The factory document's
    /// source is KEY, so the row reports that it has no effect (it still edits). The value follows a tap a moment later (the edit goes through the document and back), so each check waits for it.
    func testTheCanonRowStepsDelayAndSlipAndTheSharedUnit() {
        let app = XCUIApplication.fresh()
        app.els(prefix: "Listen, ").firstMatch.tap()
        func waitValue(_ label: String, _ prefix: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
            let end = Date().addingTimeInterval(4)
            while !value(app.el(label)).hasPrefix(prefix) && Date() < end { Thread.sleep(forTimeInterval: 0.1) }
            XCTAssertTrue(value(app.el(label)).hasPrefix(prefix), "\(what) — \(label) reads \"\(value(app.el(label)))\", wanted \"\(prefix)…\"", file: file, line: line)
        }
        func tapUp(_ label: String) { need(app.el(label), label).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }   // the › zone is the stepper's right 30 pt
        let delay = need(app.el("Canon delay, lane 1"), "lane 1's CANON DELAY stepper")
        XCTAssertTrue(value(delay).hasPrefix("off"), "DELAY starts off — \(value(delay))")
        XCTAssertTrue(value(delay).contains("CHORDS is off"), "…and says why it has no effect on the KEY source — \(value(delay))")
        tapUp("Canon delay, lane 1"); waitValue("Canon delay, lane 1", "1 pass", "› steps DELAY to 1 pass")
        need(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "CANON UNUSED: TURN ON CHORDS IN SOURCES")).firstMatch, "the footer saying a set DELAY has no effect while CHORDS is off")
        tapUp("Canon slip, lane 1"); waitValue("Canon slip, lane 1", "5 percent", "› steps SLIP to 5 percent")
        Thread.sleep(forTimeInterval: 0.7)   // the two edits are two steps (a pause longer than the gesture gap)
        app.buttons["Undo"].tap(); app.buttons["Undo"].tap()
        waitValue("Canon delay, lane 1", "off", "two undos put DELAY back")
        app.buttons["Redo"].tap()
        waitValue("Canon delay, lane 1", "1 pass", "a redo brings it back")
        // the unit is shared: one tap on lane 1's UNIT moves all four rows
        let units = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Canon unit, all lanes"))
        XCTAssertEqual(units.count, 4, "every lane's card carries the shared UNIT stepper")
        XCTAssertEqual(value(units.element(boundBy: 0)), "passes")
        units.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        waitValue("Canon unit, all lanes", "bars", "› moves the UNIT to bars")
        for i in 0..<4 { XCTAssertEqual(value(units.element(boundBy: i)), "bars", "lane \(i + 1)'s UNIT followed") }
        waitValue("Canon delay, lane 1", "1 bar", "the lane's DELAY is now counted in bars")
        app.buttons["Undo"].tap()
        waitValue("Canon unit, all lanes", "passes", "undo puts the unit back")
        XCTAssertEqual(value(units.element(boundBy: 2)), "passes", "…on every row")
    }

    /// CARD BACKS §8: the MIX tab is gone — the lower-right panel is LANES | FX, and opens on LANES.
    func testTheSequencerPanelSwitchesBetweenLanesAndFx() {
        let app = XCUIApplication.fresh()
        need(app.buttons["Lane 1 cell size PASS"], "the LANES panel's rate box (it opens on LANES)")
        XCTAssertTrue(app.buttons["Lanes"].isSelected)
        XCTAssertFalse(app.buttons["Mix"].exists && app.buttons["Lanes"].frame.intersects(app.buttons["Mix"].frame), "no MIX tab beside LANES")
        app.buttons["FX"].tap()
        need(app.buttons["FX row, ratchet, all lanes, selected"], "the FX panel's RATCH row")
        app.buttons["Lanes"].tap()
        need(app.buttons["Lane 1 cell size PASS"], "the LANES panel again")
    }

    /// RATCH tab ferry (2026-10-28): the third visible tab shows four cards; a toggle tap, a value drag and a double-tap reset each reach the document, and each is ONE undo step.
    func testTheRatchTabTogglesAnEmitterDragsAValueResetsItAndUndoes() {
        let app = XCUIApplication.fresh()
        app.buttons["Ratchet"].tap()
        XCTAssertTrue(app.buttons["Ratchet"].isSelected, "tapping RATCH selects it")
        let toggle = need(app.el("Ratchet on emitter A"), "emitter A's toggle")
        XCTAssertEqual(value(toggle), "off", "every emitter starts off")
        for letter in ["B", "C", "D"] { need(app.el("Ratchet on emitter \(letter)"), "emitter \(letter)'s toggle") }
        need(app.els(prefix: "Emitter A pattern, 3 of 8").firstMatch, "A's strip")   // (a dev build says what it counts: "3 of 8 hits, offset 0, 3 strikes"; a release build says nothing)
        toggle.tap()
        XCTAssertEqual(value(app.el("Ratchet on emitter A")), "on")
        app.buttons["Undo"].tap()
        XCTAssertEqual(value(app.el("Ratchet on emitter A")), "off", "a toggle tap is one undo step")
        app.el("Ratchet on emitter A").tap()
        // drag A's CHANCE cell down 30 pt: it falls (CHANCE moves 5 per 3 pt)
        let chance = need(app.el("Emitter A chance 100 percent"), "A's CHANCE cell")
        let from = chance.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        from.press(forDuration: 0.05, thenDragTo: from.withOffset(CGVector(dx: 0, dy: 30)))
        let dragged = app.els(prefix: "Emitter A chance ").element(boundBy: 0)
        need(dragged, "A's CHANCE cell after the drag")
        XCTAssertNotEqual(dragged.label, "Emitter A chance 100 percent", "dragging down lowered CHANCE")
        // a double tap resets it to its default
        dragged.doubleTap()
        need(app.el("Emitter A chance 100 percent"), "CHANCE back at its default after a double tap")
        // the reset was one undo step: undo takes the dragged value back
        app.buttons["Undo"].tap()
        XCTAssertNotEqual(app.els(prefix: "Emitter A chance ").element(boundBy: 0).label, "Emitter A chance 100 percent", "undo brought the dragged value back")
        // a single tap on a cell does nothing
        let steps = need(app.el("Emitter A steps 8"), "A's STEPS cell"); steps.tap()
        XCTAssertTrue(app.el("Emitter A steps 8").exists, "a single tap changes nothing")
        // switching tabs never changes data
        app.buttons["Lanes"].tap(); app.buttons["Ratchet"].tap()
        XCTAssertEqual(value(app.el("Ratchet on emitter A")), "on")
    }

    /// CARD BACKS (2026-10-28): the header's PATTERN | MIX switch turns all four cards over; each back carries a riff row and a notes row whose controls reach the engine — the part's switch, an output jack, the PITCH pad and the VEL/GATE pad.
    func testTheCardSwitchTurnsTheLaneCardsToTheirBacksAndTheControlsEdit() {
        let app = XCUIApplication.fresh()
        XCTAssertTrue(app.buttons["Rhythm"].isSelected, "the strip opens on RHYTHM and never on MIX")
        XCTAssertFalse(app.buttons["Mix"].isSelected)
        need(app.buttons["Mix"], "the strip's MIX segment").tap()
        need(app.el("Lane 1 mix"), "lane 1's back")
        XCTAssertTrue(app.buttons["Mix"].isSelected)
        let jackB = need(app.el("Riff to output B, empty"), "lane 1's riff jack B")
        jackB.tap()
        need(app.el("Riff to output B, plugged in"), "the jack plugs in")
        jackB.tap()
        need(app.el("Riff to output B, empty"), "…and unplugs again")
        need(app.el("Riff, on"), "the riff's label switch").tap()
        need(app.el("Riff, off"), "the riff goes off").tap()
        need(app.el("Riff, on"), "…and the same label turns it back on (there is no turn-on button)")
        XCTAssertFalse(app.el("Turn on riff").exists, "no turn-on pill")
        let pitch = app.els(prefix: "Riff pitch").element(boundBy: 0)
        need(pitch, "the riff's PITCH pad")
        XCTAssertEqual(pitch.value as? String, "octave 0, transpose 0")
        pitch.coordinate(withNormalizedOffset: CGVector(dx: 0.89, dy: 0.06)).tap()           // the top-right detent: octave +2, transpose +7
        XCTAssertEqual(pitch.value as? String, "octave +2, transpose +7", "a tap writes the detent under the finger")
        pitch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()        // a double tap sets both back to 0
        XCTAssertEqual(pitch.value as? String, "octave 0, transpose 0", "a double tap resets both")
        let vel = app.els(prefix: "Riff velocity").element(boundBy: 0)
        need(vel, "the riff's XY pad")
        let before = vel.label
        vel.swipeUp()
        XCTAssertNotEqual(vel.label, before, "an adjustment moves the velocity")
        app.buttons["Rhythm"].tap()
        need(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch, "the fronts again, on RHYTHM")
    }

    /// A small window (AUM's minimized plugin window, Stage Manager, Split View) must stay the live, interactive page — there is no "resize to continue" screen any more.
    func testASmallWindowStaysLiveAndInteractive() {
        for size in ["480x320", "440x700"] {
            let app = XCUIApplication.fresh(["--window-size=\(size)"])
            XCTAssertFalse(app.el("Window too small. Resize to continue.").exists, "no too-small screen at \(size)")
            XCTAssertFalse(app.staticTexts["RESIZE TO CONTINUE"].exists, "no resize message at \(size)")
            need(app.buttons["Lanes"], "the LANES tab at \(size)").tap()
            XCTAssertTrue(app.buttons["Lanes"].isSelected, "tapping LANES selects it at \(size)")
            app.buttons["FX"].tap()
            XCTAssertTrue(app.buttons["FX"].isSelected, "tapping FX selects it at \(size)")
            app.terminate()
        }
    }

    // SOURCES STACK ferry (2026-10-26): the note-source radio became a 3-light SOURCES control opening a pop-up of
    // CHORDS/KEY toggle cells. HOLD/LATCH are unchanged header chips.
    func testTheSourcesControlAndHoldLatchSelect() {
        let app = XCUIApplication.fresh()
        // HOLD / LATCH header chips — always enabled now (MIDI always listens; they used to need a MIDI source).
        app.buttons["Hold"].tap()
        XCTAssertTrue(app.buttons["Hold"].isSelected, "HOLD should read as on")
        app.buttons["Latch"].tap()
        XCTAssertTrue(app.buttons["Latch"].isSelected, "LATCH should read as on")
        XCTAssertFalse(app.buttons["Hold"].isSelected, "HOLD and LATCH are mutually exclusive")
        // the SOURCES control + its pop-up of CHORDS/KEY toggle cells.
        need(app.buttons["Sources"], "the header SOURCES control").tap()
        XCTAssertEqual(need(app.buttons["KEY while MIDI plays"], "KEY-while-MIDI cell").value as? String, "plays", "a fresh instance derives KEY ⇒ its cells play")
        XCTAssertEqual(need(app.buttons["CHORDS while MIDI plays"], "CHORDS-while-MIDI cell").value as? String, "off", "CHORDS off by default")
        app.buttons["CHORDS while MIDI plays"].tap()
        XCTAssertEqual(app.buttons["CHORDS while MIDI plays"].value as? String, "plays", "tapping a SOURCES cell turns it on")
    }

    func testTheKeyPopupChangesTheScale() {
        let app = XCUIApplication.fresh()
        app.buttons["Key, C minor"].tap()
        need(app.staticTexts["MAJOR"], "the scale list").tap()
        need(app.buttons["Key, C major"], "the key pill reading C major")
    }

    func testTheSwingPopoverMovesTheSwing() {
        let app = XCUIApplication.fresh()
        app.buttons["Swing, straight"].tap()
        let slider = need(app.sliders.element(boundBy: 1), "the swing slider")
        slider.adjust(toNormalizedSliderPosition: 0.8)
        XCTAssertFalse(app.buttons["Swing, straight"].exists, "the swing button should now name a swing amount")
        XCTAssertTrue(app.els(prefix: "Swing, ").firstMatch.exists)
    }

    func testThePresetBrowserLoadsAPreset() {
        let app = XCUIApplication.fresh()
        // TAB STRIP (2026-10-29): the lane tabs' "Rhythm, n of m hits" labels are gone — RHYTHM is showing on all four cards, so read each lane's HITS fader and STEPS stepper
        func lanes() -> [String] { (0..<4).map { "\(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).element(boundBy: $0).value as? String ?? "?") / \(app.els(prefix: "More steps, now ").element(boundBy: $0).label)" } }
        let before = lanes()
        app.buttons["Presets"].tap()
        need(app.staticTexts["PRESETS"], "the preset browser")
        need(app.buttons["FIVE AGAINST EIGHT, factory preset"], "a factory preset row").tap()
        gone(app.staticTexts["PRESETS"], "the preset browser after choosing a preset")
        let after = lanes()
        XCTAssertNotEqual(before, after, "loading FIVE AGAINST EIGHT should change the lanes")
    }

    /// THE NINE PORTS (2026-10-26): the lane cards carry no output toggles and the header no rings; routing is fixed, and the settings sheet's PORTS tab gives each of the eight ports its own channel.
    func testThePageHasNoOutputToggles() {
        let app = XCUIApplication.fresh()
        gone(app.buttons["Show its lanes"].firstMatch, "the retired header rings' action")
        app.els(prefix: "Riff, ").firstMatch.tap()
        gone(app.el("Riff to output B, off"), "the retired OUT column on the RIFF tab")
    }

    func testTheSettingsSheetOpensEditsAChannelAndCloses() {
        let app = XCUIApplication.fresh()
        app.buttons["Settings"].tap()
        need(app.buttons["MIDI IN"].firstMatch, "the settings sheet's MIDI IN tab")
        app.buttons["PORTS"].tap()
        // (the sheet keeps a hidden, invisible copy of this page to measure its height, so ask for the one that can be touched)
        let hittable = { (label: String) -> XCUIElement in
            let all = app.images.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
            return all.first(where: { $0.isHittable }) ?? all[0]
        }
        need(app.images.matching(NSPredicate(format: "label == %@", "Increase channel")).firstMatch, "the PORTS page's channel steppers")
        // four outputs, each named as the host lists it, each on its own channel on a fresh document
        for (i, name) in ["A", "B", "C", "D"].enumerated() {
            need(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "\(name), channel \(i + 1)")).firstMatch, "\(name) reads channel \(i + 1)")
        }
        hittable("Increase channel").tap()
        Thread.sleep(forTimeInterval: 0.6)
        let seen = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'A, channel'")).allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(seen.contains("A, channel 2"), "output A should read channel 2 after +; the sheet says \(seen)")
        hittable("Decrease channel").tap()
        app.buttons["Close settings"].tap()
        gone(app.buttons["PORTS"].firstMatch, "the settings sheet after Close")
    }

    func testTheBluetoothMIDIScreenOpensAndCloses() {
        let app = XCUIApplication.fresh()
        need(app.buttons["Bluetooth MIDI devices"], "the Bluetooth MIDI button in the transport bar").tap()
        need(app.buttons["Done"], "the Bluetooth MIDI sheet's Done button").tap()
        gone(app.buttons["Done"], "the Bluetooth MIDI sheet after Done")
        need(app.buttons["Play"], "the transport bar again")
    }

    /// Saved presets are kept in the app's Documents folder (Files app > On My iPad > Fourfold > Presets). Environment KEEP=1 (xcodebuild `TEST_RUNNER_KEEP=1`) skips the clean-up so a script can look at the file.
    func testASavedPresetIsListedAndKeptInDocuments() {
        let app = XCUIApplication.fresh()
        app.buttons["Presets"].tap()
        let name = app.textFields.firstMatch
        need(name, "the preset name field").tap()
        name.typeText("UITest Preset\n")   // the return key also puts the keyboard away, which would otherwise cover the list
        app.buttons["Save preset"].tap()
        need(app.buttons["UITest Preset"], "the saved preset in the YOUR PRESETS list")
        if ProcessInfo.processInfo.environment["KEEP"] == nil {
            app.buttons["Delete UITest Preset"].tap(); app.buttons["Confirm delete UITest Preset"].tap()
            gone(app.buttons["UITest Preset"], "the preset after deleting it")
        }
    }

    func testLockAndRandomModeToggleOnAndOff() {
        let app = XCUIApplication.fresh()
        let random = need(app.buttons["Random mode"], "the dice")
        XCTAssertEqual(value(random), "off")
        random.tap(); XCTAssertEqual(value(app.buttons["Random mode"]), "on")
        app.buttons["Random mode"].tap(); XCTAssertEqual(value(app.buttons["Random mode"]), "off")
        let lock = need(app.switches["Lock mode"], "the padlock")
        XCTAssertEqual(value(lock), "off")
        lock.tap(); XCTAssertEqual(value(app.switches["Lock mode"]), "on")
        app.switches["Lock mode"].tap(); XCTAssertEqual(value(app.switches["Lock mode"]), "off")
    }

    func testTheReelOpensAndClosesInLandscape() {
        let app = XCUIApplication.fresh()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["Reel"].tap()
        need(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'pass'")).firstMatch, "the reel browser (something about passes)")
    }

    func testTheReelKeepsItsPassesAcrossAForceQuitAndRelaunch() {
        var app = XCUIApplication.fresh()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["Play"].tap()
        Thread.sleep(forTimeInterval: 22)                // 120 BPM and a 16-beat pass is 8 s: two whole passes are on the tape
        app.buttons["Stop"].tap()
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 1.5)
        app.terminate()
        app = XCUIApplication(); app.launchArguments = []; app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["Reel"].tap()
        need(app.staticTexts["Tap a pass to choose what to save."], "passes on the tape, recorded before the relaunch (the reel says so only once there is something to save)")
        XCTAssertFalse(app.staticTexts["Nothing recorded yet."].exists)
    }

    func testAFreshLaunchStartsWithAnEmptyReel() {                       // the control for the test above: its text only shows up when there is a recorded pass
        let app = XCUIApplication.fresh()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        app.buttons["Reel"].tap()
        need(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] 'pass'")).firstMatch, "the reel browser")
        need(app.staticTexts["Nothing recorded yet."], "an empty tape says so")
        XCTAssertFalse(app.staticTexts["Tap a pass to choose what to save."].exists)
    }

    func testAnEditSurvivesAForceQuitAndRelaunch() {
        var app = XCUIApplication.fresh()
        app.buttons["More steps, now 8"].firstMatch.tap()
        need(app.buttons["More steps, now 9"].firstMatch, "9 steps")
        XCUIDevice.shared.press(.home)          // leaving the foreground saves the session
        Thread.sleep(forTimeInterval: 1.5)
        app.terminate()
        app = XCUIApplication(); app.launchArguments = []; app.launch()
        need(app.buttons["More steps, now 9"].firstMatch, "the edit restored after a relaunch")
        app.buttons["Fewer steps, now 9"].firstMatch.tap()  // leave the simulator's saved session as it was
        XCUIDevice.shared.press(.home); Thread.sleep(forTimeInterval: 1.5)
    }

    func testRotatingWithAPopupOpenKeepsThePopupAndThePage() {
        let app = XCUIApplication.fresh()
        app.buttons["Settings"].tap()
        need(app.staticTexts["CHANNELS"], "the settings sheet")
        for o in [UIDeviceOrientation.landscapeLeft, .portraitUpsideDown, .landscapeRight, .portrait] {
            XCUIDevice.shared.orientation = o; Thread.sleep(forTimeInterval: 1.2)
            XCTAssertTrue(app.staticTexts["CHANNELS"].exists, "the sheet should survive \(o.rawValue)")
            XCTAssertTrue(app.buttons["Play"].exists)
        }
    }
}
