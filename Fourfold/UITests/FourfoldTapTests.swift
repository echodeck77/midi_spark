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

    /// STACK GRID (2026-11-08): the riff panel's header switch shows RIFF and STACK, RIFF selected on a fresh launch; there is no POLY option (the debug `--poly-control` flag brings the old segment back for the POLY tests below) and no riff boxes.
    func testTheRiffPanelHasARiffStackSwitchAndNoPoly() {
        let app = XCUIApplication.fresh()
        let riff = app.buttons["Riff"], stack = app.buttons["Stack"]
        need(riff, "the RIFF segment"); need(stack, "the STACK segment")
        XCTAssertTrue(riff.isSelected, "RIFF is the default"); XCTAssertFalse(stack.isSelected)
        XCTAssertFalse(app.buttons["Poly"].exists, "there is no POLY option"); XCTAssertFalse(app.buttons["Mono"].exists, "MONO is RIFF now")
        XCTAssertEqual(app.els(prefix: "Riff 1").count, 0, "the four riff boxes are gone")
        stack.tap(); XCTAssertTrue(app.buttons["Stack"].isSelected); XCTAssertFalse(app.buttons["Riff"].isSelected)
        app.buttons["Riff"].tap(); XCTAssertTrue(app.buttons["Riff"].isSelected)
    }
    /// STACK GRID (2026-11-08): the grid's cells are the NOTES selection — a tap on lane 1's rank 3 cell turns it on (and the NOTES keys show it lit), a tap on that NOTES key turns it off and the cell shows off; one tap each way is one undo step.
    func testAStackGridCellAndTheNotesKeyAreOneSelection() {
        let app = XCUIApplication.fresh()
        app.buttons["Stack"].firstMatch.tap()
        func cell() -> XCUIElement { app.els(prefix: "Lane 1, rank 3,").firstMatch }
        need(cell(), "lane 1's rank 3 cell on the STACK grid"); XCTAssertEqual(value(cell()), "off")
        for lane in 1...4 { need(app.els(prefix: "Lane \(lane), top,").firstMatch, "lane \(lane)'s TOP cell") }
        cell().tap()
        XCTAssertEqual(value(cell()), "on", "the tap lit the cell")
        app.els(prefix: "Stack, ").firstMatch.tap()   // the strip's STACK tab (the NOTES keys)
        let key = need(app.els(prefix: "Rank 3, ").element(boundBy: 0), "lane 1's NOTES key 3")
        XCTAssertTrue(key.label.contains(", lit"), "the NOTES key shows what the grid wrote: \(key.label)")
        key.tap()
        XCTAssertEqual(value(cell()), "off", "a NOTES toggle shows on the grid at once")
        app.buttons["Undo"].tap()
        XCTAssertEqual(value(cell()), "on", "one undo step brings the NOTES toggle back")
    }
    /// With the debug flag the header is RIFF · POLY · STACK and RIFF / POLY switch the lane's riff mode as MONO / POLY did.
    func testThePolyControlFlagBringsBackThePolySegment() {
        let app = XCUIApplication.fresh(["--poly-control"])
        let riff = app.buttons["Riff"], poly = app.buttons["Poly"]
        need(riff, "the RIFF segment"); need(poly, "the POLY segment")
        XCTAssertTrue(riff.isSelected); XCTAssertFalse(poly.isSelected)
        poly.tap(); XCTAssertTrue(app.buttons["Poly"].isSelected); XCTAssertFalse(app.buttons["Riff"].isSelected)
        app.buttons["Riff"].tap(); XCTAssertTrue(app.buttons["Riff"].isSelected)
    }
    /// POLY: a tap on an empty cell makes a length-1 note, a second tap on it takes it away, and pressing a cell then dragging sideways stretches the note — the head cell reads "note, length 5", the cells it covers "held from step 4".
    func testPolyGridTapsAddAndRemoveAndADragStretchesANote() {
        let app = XCUIApplication.fresh(["--poly-control"])
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
        let app = XCUIApplication.fresh(["--poly-control"])
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
        let app = XCUIApplication.fresh(["--poly-control"])
        app.buttons["Poly"].tap()
        func cell(_ step: Int, _ row: Int) -> XCUIElement { app.els(prefix: "Step \(step),").element(boundBy: row) }
        need(cell(1, 0), "the POLY grid")
        cell(1, 0).press(forDuration: 0.1, thenDragTo: cell(4, 0))
        cell(3, 1).press(forDuration: 0.1, thenDragTo: cell(4, 1))
        XCTAssertEqual(cell(1, 0).value as? String, "note, length 4"); XCTAssertEqual(cell(3, 1).value as? String, "note, length 2")
        // RIFF v2 (2026-11-05): the RHYTHM tab now also carries Backward / Ping-pong / Forward buttons, so the page opening on RHYTHM would match the wrong direction — navigate to the RIFF tab FIRST (was a conditional navigate, which no longer fires).
        app.els(prefix: "Riff, ").firstMatch.tap()
        let button = app.els(prefix: direction).element(boundBy: 0)
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
    func testAReversedLaneSeatsItsChordArrowsOnTheNotesLastColumn() { assertLane1SeatsItsChordArrowsOnTheNotesLastColumn(direction: "Backward", seconds: 30) }   // RIFF v2 (2026-11-05) renamed the RIFF direction VoiceOver labels to Backward / Ping-pong / Forward
    /// PING-PONG (2026-10-30): the same notes are met at their last column on the way back (the second visit of the end step), not only at their first on the way up.
    func testAPingPongLaneSeatsItsChordArrowsOnTheNotesLastColumnComingBack() { assertLane1SeatsItsChordArrowsOnTheNotesLastColumn(direction: "Ping-pong", seconds: 60) }

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

    /// TAP A STEP (2026-11-08): one tap on a lane card's strip toggles that step's hit and the HITS number follows (lane 1 starts 3 of 8, hits on steps 1, 4, 7); each tap is its own undo step.
    func testATapOnAStepOfTheCardStripTogglesItsHit() {
        let app = XCUIApplication.fresh()
        func hits() -> String { value(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch) }
        need(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch, "the HITS fader")
        XCTAssertEqual(hits(), "3")
        let strip = need(app.el("Lane 1 step strip"), "lane 1's step strip")
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.1875, dy: 0.5)).tap()   // step 2, a rest
        XCTAssertEqual(hits(), "4", "tapping a rest added a hit")
        strip.coordinate(withNormalizedOffset: CGVector(dx: 0.0625, dy: 0.5)).tap()   // step 1, a hit
        XCTAssertEqual(hits(), "3", "tapping a hit removed it")
        app.buttons["Undo"].tap()
        XCTAssertEqual(hits(), "4", "one tap is one undo step")
        app.buttons["Undo"].tap()
        XCTAssertEqual(hits(), "3")
    }
    /// The same tap on the MIX band's strip: its spoken hit count and the card's HITS follow.
    func testATapOnAStepOfTheMixStripTogglesItsHit() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Mix"].tap()
        func strip() -> XCUIElement { app.el("Lane 1").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Rhythm, ")).firstMatch }
        let s = need(strip(), "lane 1's rhythm strip"); XCTAssertEqual(s.label, "Rhythm, 3 hits in 8 steps")
        s.coordinate(withNormalizedOffset: CGVector(dx: 0.1875, dy: 0.5)).tap()
        XCTAssertEqual(strip().label, "Rhythm, 4 hits in 8 steps", "a tap on a rest added a hit")
        strip().coordinate(withNormalizedOffset: CGVector(dx: 0.0625, dy: 0.5)).tap()
        XCTAssertEqual(strip().label, "Rhythm, 3 hits in 8 steps", "a tap on a hit removed it")
        app.buttons["Undo"].tap()
        XCTAssertEqual(strip().label, "Rhythm, 4 hits in 8 steps", "one tap is one undo step")
        app.buttons["Rhythm"].tap()
        let hits = need(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch, "the HITS fader back on the cards")
        XCTAssertEqual(value(hits), "4", "the card's HITS shows the same count")
    }

    /// PLAY RIFF / PLAY STACK (amendment 1, 2026-11-08): the two top-row buttons switch the lane's riff and notes parts, a tap is one undo step, and the bigger type / new frames leave them tappable on the card.
    func testThePlayRiffAndPlayStackButtonsSwitchTheirPartsAndUndo() {
        let app = XCUIApplication.fresh()
        let riff = need(app.el("Play riff, lane 1"), "lane 1's PLAY RIFF button"), stack = need(app.el("Play stack, lane 1"), "lane 1's PLAY STACK button")
        XCTAssertEqual(value(riff), "on"); XCTAssertEqual(value(stack), "off")
        XCTAssertEqual(riff.frame.height, stack.frame.height, accuracy: 0.5, "both buttons are the same height")
        riff.tap()
        XCTAssertEqual(value(app.el("Play riff, lane 1")), "off", "a tap switched the riff off")
        app.buttons["Undo"].tap()
        XCTAssertEqual(value(app.el("Play riff, lane 1")), "on", "one undo step")
        app.el("Play stack, lane 1").tap()
        XCTAssertEqual(value(app.el("Play stack, lane 1")), "on", "PLAY STACK turned the notes part on")
        app.buttons["Undo"].tap()
        XCTAssertEqual(value(app.el("Play stack, lane 1")), "off", "one undo step")
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
        app.els(prefix: "Stack, ").firstMatch.tap()
        need(app.el("Notes layer, off, 0 notes lit"), "the NOTES tab's layer switch")
        app.els(prefix: "Inputs, ").firstMatch.tap()   // POOL tab renamed INPUTS (Paul 2026-11-05)
        need(app.els(prefix: "Now, lane 1").firstMatch, "the POOL tab's NOW row")
        need(app.el("Canon delay, lane 1"), "the POOL tab's CANON row")
        app.els(prefix: "Answer, ").firstMatch.tap()
        need(app.el("Follow lane 2"), "the ANSWER tab's partner picker")
        need(app.el("Rhythm, lane 1"), "the ANSWER tab's RHYTHM switch")
        app.buttons["Rhythm"].tap()
        need(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch, "the RHYTHM tab again")
    }

    /// ANSWER (2026-11-02): a switch turns its row on (the mode button then draws selected) and RHYTHM's strip appears on the RHYTHM tab; CYCLE shows the CYCLE row; TRADE pairs a SWAP in one undo step; everything undoes.
    func testTheAnswerSwitchesCycleAndTradeAndTheirUndo() {
        let app = XCUIApplication.fresh()
        app.els(prefix: "Answer, ").firstMatch.tap()
        XCTAssertEqual(value(need(app.el("Rhythm, lane 2"), "lane 2's RHYTHM switch")), "off")
        XCTAssertFalse(app.els(prefix: "Each, lane 2").firstMatch.exists, "no CYCLE row while nothing cycles")
        app.el("Rhythm, lane 2").tap()
        XCTAssertEqual(value(app.el("Rhythm, lane 2")), "on")
        app.buttons["Undo"].tap()
        XCTAssertEqual(value(app.el("Rhythm, lane 2")), "off", "a switch tap is one undo step")
        app.el("Rhythm, lane 2").tap()
        app.el("Cycle rhythm, lane 2").tap()
        need(app.el("Each, lane 2"), "the CYCLE row appears while a row is on with CYCLE")
        need(app.el("Phase, lane 2"), "the phase bar")
        // the RHYTHM tab shows the strip while RHYTHM is on
        app.buttons["Rhythm"].tap()
        need(app.el("Delay, lane 2"), "the rhythm strip's DELAY")
        app.els(prefix: "Answer, ").firstMatch.tap()
        // TRADE: SWAP with the default WITH pairs the other lane too, in one undo step
        app.el("Trade, lane 1").tap()
        XCTAssertEqual(value(app.el("Trade, lane 1")), "on")
        XCTAssertEqual(value(app.el("Trade, lane 2")), "on", "lane 1 swaps with lane 2 → lane 2 swaps back")
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["Undo"].tap()
        XCTAssertEqual(value(app.el("Trade, lane 1")), "off")
        XCTAssertEqual(value(app.el("Trade, lane 2")), "off", "the pairing was one undo step for both lanes")
    }

    /// INPUTS (ferry 2026-11-06; the POOL tab renamed): the INPUTS tab's SOURCES toggles and each lane's MIDI mode edit through the document and back through undo (one step each); NOW reads the pool; the grid's lane picker steps
    /// 1 → 2 → 3 → 4 → 1 and the NOTES keys carry their rank numbers in their names.
    func testTheInputsTabSwitchesSourcesMidiModeAndTheGridPicker() {
        let app = XCUIApplication.fresh(["--autoplay"])   // a stopped engine has no pools to show (as before the ferry: the old shared pool was only refreshed while playing)
        Thread.sleep(forTimeInterval: 1.5)
        app.els(prefix: "Inputs, ").firstMatch.tap()
        need(app.els(prefix: "Now, lane 1").firstMatch, "the NOW row (a leaf: the status feed does not re-run the page)")
        // SOURCES: a toggle is one undo step, the lane's name is in its label
        XCTAssertEqual(value(need(app.el("Key, lane 1"), "lane 1's KEY toggle")), "on")
        app.el("Key, lane 1").tap()
        XCTAssertEqual(value(app.el("Key, lane 1")), "off")
        app.buttons["Undo"].tap()
        XCTAssertEqual(value(app.el("Key, lane 1")), "on", "a source toggle is one undo step")
        // TWO CHORD GRIDS: CHORD 1 and CHORD 2 are mutually exclusive; the lit one tapped again turns chords off for the lane
        func lit(_ name: String) -> Bool { value(app.el(name)).hasPrefix("on") }
        XCTAssertTrue(need(app.el("Chords 1, lane 1"), "lane 1's CHORD 1 toggle").exists); XCTAssertTrue(need(app.el("Chords 2, lane 1"), "lane 1's CHORD 2 toggle").exists)
        app.el("Chords 1, lane 1").tap(); Thread.sleep(forTimeInterval: 0.7)
        if !lit("Chords 1, lane 1") { app.el("Chords 1, lane 1").tap(); Thread.sleep(forTimeInterval: 0.7) }   // a fresh document has CHORDS off on every lane (the old panel's switch): light CHORD 1 first
        XCTAssertTrue(lit("Chords 1, lane 1")); XCTAssertFalse(lit("Chords 2, lane 1"))
        app.el("Chords 2, lane 1").tap()
        XCTAssertTrue(lit("Chords 2, lane 1")); XCTAssertFalse(lit("Chords 1, lane 1"), "lighting CHORD 2 puts CHORD 1 out")
        app.buttons["Undo"].tap()
        XCTAssertTrue(lit("Chords 1, lane 1")); XCTAssertFalse(lit("Chords 2, lane 1"), "the pick is one undo step")
        app.el("Chords 1, lane 1").tap()
        XCTAssertFalse(lit("Chords 1, lane 1")); XCTAssertFalse(lit("Chords 2, lane 1"), "the lit one tapped again: chords off for the lane")
        app.buttons["Undo"].tap()
        // MIDI: three segments a lane, a tap selects (one undo step), the readout is hidden outside ROOT
        func selected(_ name: String) -> Bool { app.el(name).isSelected }
        XCTAssertTrue(need(app.el("Add, lane 2"), "lane 2's ADD segment").exists); XCTAssertTrue(selected("Add, lane 2"), "a fresh document is in ADD")
        app.el("Replace, lane 2").tap(); Thread.sleep(forTimeInterval: 0.7)
        XCTAssertTrue(selected("Replace, lane 2")); XCTAssertFalse(selected("Add, lane 2"))
        XCTAssertTrue(selected("Add, lane 3"), "…on that lane only")
        XCTAssertFalse(app.els(prefix: "Root transpose").firstMatch.exists, "no readout outside ROOT")
        app.el("Root, lane 3").tap(); Thread.sleep(forTimeInterval: 0.7)
        XCTAssertTrue(selected("Root, lane 3"))
        need(app.els(prefix: "Root transpose").firstMatch, "ROOT's readout (\"Root transpose, zero\" with nothing latched)")
        app.buttons["Undo"].tap()
        XCTAssertFalse(selected("Root, lane 3")); XCTAssertTrue(selected("Add, lane 3"), "one undo step"); XCTAssertTrue(selected("Replace, lane 2"), "…the earlier edit stays")
        app.buttons["Undo"].tap()
        XCTAssertTrue(selected("Add, lane 2"), "a second step back")
        // the grid's picker
        XCTAssertEqual(value(need(app.el("Notes shown for"), "the lane picker beside the MONO | POLY control")), "lane 1")
        XCTAssertFalse(app.els(prefix: "Rank 1, no note").firstMatch.exists, "lane 1's pool has notes: its chips name them")
        app.el("Notes shown for").tap()
        XCTAssertEqual(value(app.el("Notes shown for")), "lane 2")
        // the grid names the PICKED lane's pool: with lane 2's KEY off nothing feeds it (nothing is held), so lane 2's chips have no notes
        app.el("Key, lane 2").tap()
        let empty = app.els(prefix: "Rank 1, no note").firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 4), "the grid names lane 2's (empty) pool, not lane 1's")
        app.el("Key, lane 2").tap()   // back on: lane 2's pool returns
        for _ in 0..<3 { app.el("Notes shown for").tap() }
        XCTAssertFalse(app.els(prefix: "Rank 1, no note").firstMatch.exists, "back on lane 1 (and lane 2's KEY on again): notes")
        _ = empty
        XCTAssertEqual(value(app.el("Notes shown for")), "lane 1", "1 → 2 → 3 → 4 → 1")
        need(app.els(prefix: "Rank 1, ").firstMatch, "the grid's label chips read \"Rank n, <note>\"")
        // the NOTES keys
        app.els(prefix: "Stack, ").firstMatch.tap()
        need(app.els(prefix: "Rank 1, ").firstMatch, "the NOTES keys keep their \"Rank n, …\" names")
    }

    /// CHORD CANON (2026-10-31; SLIP removed by the INPUTS ferry, 2026-11-06): the CANON row on the INPUTS tab — a lane's DELAY steps through the engine and back through undo; the UNIT is one value shared by all four rows (and undoable). The row works with
    /// every source (the factory document has MIDI IN and KEY on), so it reports no "no effect" reason. The value follows a tap a moment later (the edit goes through the document and back), so each check waits for it.
    func testTheCanonRowStepsDelayAndTheSharedUnit() {
        let app = XCUIApplication.fresh()
        app.els(prefix: "Inputs, ").firstMatch.tap()   // the POOL tab renamed INPUTS; CANON lives there
        func waitValue(_ label: String, _ prefix: String, _ what: String, file: StaticString = #filePath, line: UInt = #line) {
            let end = Date().addingTimeInterval(4)
            while !value(app.el(label)).hasPrefix(prefix) && Date() < end { Thread.sleep(forTimeInterval: 0.1) }
            XCTAssertTrue(value(app.el(label)).hasPrefix(prefix), "\(what) — \(label) reads \"\(value(app.el(label)))\", wanted \"\(prefix)…\"", file: file, line: line)
        }
        func tapUp(_ label: String) { need(app.el(label), label).coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }   // the › zone is the stepper's right 30 pt
        let delay = need(app.el("Canon delay, lane 1"), "lane 1's CANON DELAY stepper")
        XCTAssertTrue(value(delay).hasPrefix("off"), "DELAY starts off — \(value(delay))")
        XCTAssertFalse(value(delay).contains("no effect"), "the factory sources (MIDI IN, KEY) are live for the canon — \(value(delay))")
        tapUp("Canon delay, lane 1"); waitValue("Canon delay, lane 1", "1 pass", "› steps DELAY to 1 pass")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'CANON UNUSED'")).firstMatch.exists, "no \"unused\" footer while a source is on")
        XCTAssertFalse(app.el("Canon slip, lane 1").exists, "SLIP is gone from the row")
        Thread.sleep(forTimeInterval: 0.7)
        app.buttons["Undo"].tap()
        waitValue("Canon delay, lane 1", "off", "an undo puts DELAY back")
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

    /// CARD BACKS §8: the MIX tab is gone, and so is FX (retired 2026-11-07) — the lower-right panel is MUTE | RATCH | VEL, and opens on MUTE.
    func testTheSequencerPanelSwitchesBetweenMuteAndRatchAndHasNoFxTab() {
        let app = XCUIApplication.fresh()
        need(app.els(prefix: "Output A cell 1,").firstMatch, "the MUTE panel's first cell (it opens on MUTE)")   // MUTE TAB ferry (2026-11-02): the tab is "Mute", its blocks are outputs
        XCTAssertTrue(app.buttons["Mute"].isSelected)
        XCTAssertFalse(app.buttons["Mix"].exists && app.buttons["Mute"].frame.intersects(app.buttons["Mix"].frame), "no MIX tab beside MUTE")
        XCTAssertFalse(app.buttons["FX"].exists, "the FX tab is retired")
        app.buttons["Ratchet"].tap()
        need(app.el("Ratchet on emitter A"), "the RATCH panel's first card")
        app.buttons["Mute"].tap()
        need(app.els(prefix: "Output A cell 1,").firstMatch, "the MUTE panel again")
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
        app.buttons["Mute"].tap(); app.buttons["Ratchet"].tap()
        XCTAssertEqual(value(app.el("Ratchet on emitter A")), "on")
    }

    /// A small window (AUM's minimized plugin window, Stage Manager, Split View) must stay the live, interactive page — there is no "resize to continue" screen any more.
    func testASmallWindowStaysLiveAndInteractive() {
        for size in ["480x320", "440x700"] {
            let app = XCUIApplication.fresh(["--window-size=\(size)"])
            XCTAssertFalse(app.el("Window too small. Resize to continue.").exists, "no too-small screen at \(size)")
            XCTAssertFalse(app.staticTexts["RESIZE TO CONTINUE"].exists, "no resize message at \(size)")
            need(app.buttons["Mute"], "the MUTE tab at \(size)").tap()
            XCTAssertTrue(app.buttons["Mute"].isSelected, "tapping MUTE selects it at \(size)")
            app.buttons["Ratchet"].tap()
            XCTAssertTrue(app.buttons["Ratchet"].isSelected, "tapping RATCH selects it at \(size)")
            app.terminate()
        }
    }

    /// MIX ROWS AMENDMENT 1 (§A7): no explanatory caption line on any lower-right tab — MUTE's hint and ZOOM legend (RATCH and VEL never had one; the FX tab, which had them, is retired). (The words are matched whole: the zoom arrows' own VoiceOver labels say "Zoom in".)
    func testNoLowerRightTabShowsAnExplanatoryCaption() {
        let app = XCUIApplication.fresh()
        let captions = ["TAP CELLS TO SILENCE EACH OUTPUT", "GHOSTS DIM BEHIND", "(1\u{2013}8 PASSES)", "TAP: ON/OFF", "DRAG ALONG: PAINT", "DOUBLE-TAP: RESET",
                        "PLAYS THE NOTE 2\u{2013}4 TIMES", "REPLACES THE LANE", "CARRIES ON THROUGH"]
        func assertNone(_ tab: String) {
            for c in captions {
                let hits = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@ OR value CONTAINS[c] %@", c, c))
                XCTAssertEqual(hits.count, 0, "\(tab): the caption \"\(c)\" is hidden")
            }
        }
        need(app.buttons["Mute"], "the MUTE tab"); assertNone("MUTE")
        app.buttons["Ratchet"].tap(); assertNone("RATCH")
        app.buttons["Velocity"].tap(); assertNone("VEL")
    }

    // MARK: RESTART UNITS (2026-11-04)

    /// RESTARTS EDITOR V2 (2026-11-06): the restart editor through the real engine — a tile opens it; the FREE pill is lit; a unit chip (RIFF) selects AND wakes the chain (§3, FREE now off, a link of 1 appended) and reveals the source squares; PASS
    /// shows the squares with the lane itself unavailable, a square selects; the link row toggles WITH RHYTHM; a count-chip tap steps the value; the header carries no instruction text; the close button closes it. (Each tap is one undo step.)
    /// NOTE: not run this session (no iOS simulator runtime installed) — the labels/flow match the V2 design; device-verify.
    func testTheRestartEditorFreePillUnitChipsSourcesAndLinks() {
        let app = XCUIApplication.fresh()
        Thread.sleep(forTimeInterval: 1)
        let tile = app.buttons.matching(NSPredicate(format: "label == %@", "Rhythm restarts, free")).element(boundBy: 0)
        need(tile, "lane 1's RHYTHM restart tile").tap()
        let editor = need(app.el("Restarts for lane 1"), "the editor dialog")
        XCTAssertFalse(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "TAP + TO ADD")).count > 0, "no instruction text in the header")
        func any(_ label: String) -> XCUIElement { editor.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch }
        need(any("Rhythm free, on"), "the FREE pill, lit (the chain is free)")
        let squares = { editor.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Lane ")).count }
        XCTAssertEqual(squares(), 4, "RHYTHM BAR reads no lane (no squares); MELODY PASS reads its own (four)")
        let riff = need(editor.buttons["Count riffs"], "the RIFF chip"); riff.tap()
        XCTAssertTrue(editor.buttons["Count riffs"].isSelected, "tapping a unit chip selects it")
        need(any("Rhythm free, off"), "§3: the unit tap woke the chain — FREE is now off")
        need(any("Rhythm link 1, 1 riff"), "waking the chain appended a link of 1")
        XCTAssertEqual(squares(), 8, "RIFF reads a lane — the RHYTHM row now shows its four squares too")
        XCTAssertTrue(editor.buttons.matching(NSPredicate(format: "label == %@", "Lane 1")).element(boundBy: 0).isSelected, "its own lane by default")
        editor.buttons.matching(NSPredicate(format: "label == %@", "Count passes")).element(boundBy: 0).tap()   // the RHYTHM row's chip (MELODY has its own)
        need(editor.buttons["Lane 1, unavailable"], "RHYTHM PASS: the lane itself is unavailable")
        let l3 = need(editor.buttons.matching(NSPredicate(format: "label == %@", "Lane 3")).element(boundBy: 0), "lane 3's square (the RHYTHM row's first)"); l3.tap()
        XCTAssertTrue(editor.buttons.matching(NSPredicate(format: "label == %@", "Lane 3")).element(boundBy: 0).isSelected, "a source square selects")
        let withRhythm = need(any("Melody restarts with the rhythm, off"), "the link row"); withRhythm.tap()
        need(any("Melody restarts with the rhythm, on"), "WITH RHYTHM is on")
        any("Rhythm link 1, 1 pass").tap()
        need(any("Rhythm link 1, 2 passes"), "a count-chip tap steps the value")
        editor.buttons["Close restarts"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.el("Restarts for lane 1"))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 2.5), .completed, "the close button closes the editor")
        need(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rhythm restarts every 2 passes of lane 3")).element(boundBy: 0), "the tile now reads the new restart")
    }

    // MARK: MIX ROWS (2026-11-03)

    /// MIX swaps the four lane cards for the panel (four lane groups and the emitters) and a front tab swaps them back; the panel's controls read their values aloud. (That the swap has no flip is pinned by `euclideousPageTabTap`.)
    func testSelectingMixSwapsTheCardsForThePanelAndBack() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.els(prefix: "Riff velocity").count, 0, "the lane cards are showing")
        app.buttons["Mix"].tap()
        need(app.els(prefix: "Riff velocity").firstMatch, "the panel's riff VEL slider", timeout: 1.5)
        for n in 1...4 { need(app.el("Lane \(n)"), "lane \(n)'s band") }
        for o in ["A", "B", "C", "D"] { need(app.els(prefix: "Output \(o), ").firstMatch, "emitter \(o)") }
        XCTAssertTrue(app.buttons["Mix"].isSelected)
        app.buttons["Rhythm"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.els(prefix: "Riff velocity").firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 2.5), .completed, "the cards return and the panel is gone")
    }
    /// A fresh session routes lane n to output n from BOTH rows; a tap on a row's A–D toggle is one undo step; the label carries the state.
    func testTheMixPanelsOutputTogglesRouteAPartAndUndoPutsItBack() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Mix"].tap()
        func inLane(_ n: Int, _ label: String) -> XCUIElement { app.el("Lane \(n)").descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch }
        need(inLane(1, "Riff to A, on"), "lane 1's riff leaves through A"); need(inLane(1, "Notes to A, on"), "…and its notes too")
        need(inLane(2, "Notes to B, on"), "lane 2's notes leave through B")
        XCTAssertFalse(inLane(2, "Notes to A, on").exists)
        need(inLane(2, "Notes to A, off"), "lane 2's notes do not leave through A yet").tap()
        need(inLane(2, "Notes to A, on"), "after the tap lane 2's notes leave through A as well")
        need(inLane(2, "Notes to B, on"), "…and still through B")
        app.buttons["Undo"].tap()
        need(inLane(2, "Notes to A, off"), "one undo step takes A away again")
        inLane(3, "Riff to C, on").tap(); need(inLane(3, "Riff to C, off"), "tapping the only output leaves the part routed nowhere (silent)")
        app.buttons["Undo"].tap(); need(inLane(3, "Riff to C, on"), "undo")
    }
    /// The part's toggle switches it on or off (the same field and undo as the tabs' switch), through the panel.
    func testTheMixPanelsPartToggleSwitchesThePartAndUndoReturnsIt() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Mix"].tap()
        func inLane(_ n: Int, _ label: String) -> XCUIElement { app.el("Lane \(n)").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch }
        let riff = need(inLane(3, "Riff, on"), "lane 3's riff toggle"); riff.tap()
        need(inLane(3, "Riff, off"), "after the tap the part is off")
        app.buttons["Undo"].tap(); need(inLane(3, "Riff, on"), "one undo step")
        need(inLane(3, "Notes, off"), "lane 3's notes start off").tap(); need(inLane(3, "Notes, on"), "…and switch on")
        app.buttons["Undo"].tap(); need(inLane(3, "Notes, off"), "undo")
    }
    /// The MIX band's rhythm strip takes the lane card strip's gestures: a drag UP adds hits (here lane 1 goes from 3 hits in 8 steps), the whole drag is ONE undo step, and a drag DOWN takes them away again.
    func testTheMixStripTakesTheCardStripsHitsDragAndItsUndo() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Mix"].tap()
        func strip() -> XCUIElement { app.el("Lane 1").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Rhythm, ")).firstMatch }
        let s = need(strip(), "lane 1's rhythm strip"); XCTAssertEqual(s.label, "Rhythm, 3 hits in 8 steps")
        s.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(forDuration: 0.05, thenDragTo: s.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: -1.5)))
        XCTAssertNotEqual(strip().label, "Rhythm, 3 hits in 8 steps", "dragging up on the strip added hits: \(strip().label)")
        XCTAssertTrue(strip().label.contains("in 8 steps"), "the step count did not change")
        app.buttons["Undo"].tap()
        XCTAssertEqual(strip().label, "Rhythm, 3 hits in 8 steps", "the whole drag was ONE undo step")
        app.buttons["Redo"].tap()
        let added = strip().label
        strip().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)).press(forDuration: 0.05, thenDragTo: strip().coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 2.5)))
        XCTAssertNotEqual(strip().label, added, "dragging down took hits away: \(strip().label)")
    }
    /// MIX v2: VEL and GATE are sliders (a horizontal drag moves a value relative to where it started and is ONE undo step; a vertical drag that starts on a tile moves nothing; a double tap sets the default); OCT is five linked boxes
    /// (a tap selects, a drag across them is ONE undo step). There is no TRANS control on the MIX panel (removed 2026-11-07).
    func testTheMixPanelsSlidersDragRelativeAndOctBoxesUndoAsOneStepAndDoubleTapToDefault() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Mix"].tap()
        func tile(_ prefix: String) -> XCUIElement { app.el("Lane 1").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch }
        // a vertical drag starting on the VEL tile moves nothing
        let vel = need(tile("Riff velocity"), "the riff VEL tile"); XCTAssertEqual(vel.label, "Riff velocity 100")
        vel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(forDuration: 0.05, thenDragTo: vel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        XCTAssertEqual(tile("Riff velocity").label, "Riff velocity 100", "a vertical drag does not move the value")
        // a drag to the left lowers it (ONE undo step), a double tap puts it back at 100
        vel.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).press(forDuration: 0.05, thenDragTo: vel.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.5)))
        let lowered = tile("Riff velocity").label
        XCTAssertNotEqual(lowered, "Riff velocity 100", "the drag lowered VEL: \(lowered)")
        app.buttons["Undo"].tap()
        XCTAssertEqual(tile("Riff velocity").label, "Riff velocity 100", "the whole drag was ONE undo step")
        app.buttons["Redo"].tap()
        tile("Riff velocity").doubleTap()
        XCTAssertEqual(tile("Riff velocity").label, "Riff velocity 100", "a double tap sets the default")
        // OCT: five boxes; a tap on the right-hand box selects +2, a drag across them is ONE step, a tap on the selected box does nothing
        let oct = need(tile("Riff octave"), "lane 1's riff OCT boxes"); XCTAssertEqual(oct.label, "Riff octave 0")
        oct.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        XCTAssertEqual(tile("Riff octave").label, "Riff octave +2", "the fifth box is +2")
        oct.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
        app.buttons["Undo"].tap()
        XCTAssertEqual(tile("Riff octave").label, "Riff octave 0", "the second tap on the selected box wrote nothing, so one undo returns to 0")
        oct.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)).press(forDuration: 0.05, thenDragTo: oct.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.5)))
        XCTAssertEqual(tile("Riff octave").label, "Riff octave +1", "the drag ends on the fourth box")
        app.buttons["Undo"].tap()
        XCTAssertEqual(tile("Riff octave").label, "Riff octave 0", "a drag across the boxes is ONE undo step")
    }
    /// MIX v2: a part's stack of eight ranks lights from the note feed — while the page plays, one of lane 2's stacks (16 steps, 5 hits) reads "playing rank n" within a few seconds, and reads "silent" when nothing sounds.
    func testTheMixPanelsStacksReadTheNoteFeed() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Mix"].tap()
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.els(prefix: "Riff playing rank").firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 12), .completed, "no riff stack ever read \"playing rank n\" in 12 s of playback")
        XCTAssertTrue(app.els(prefix: "Notes silent").firstMatch.exists, "the factory document's notes part is off, so its stack stays silent")
    }
    /// MIX v2 §7: a part's S latches its solo (value "on"); while lane 2's riff is soloed no other part's stack ever reads "playing" (lane 1's riff, a lane that otherwise plays, goes silent), and a second tap releases it.
    func testAPartSoloLatchesOnTheMixPanelAndSilencesEveryOtherPart() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Mix"].tap()
        let solo = need(app.switches["Solo riff, lane 2"], "lane 2's riff S")
        XCTAssertEqual(solo.value as? String, "off")
        solo.tap()
        XCTAssertEqual(app.switches["Solo riff, lane 2"].value as? String, "on", "the tap latches the part solo")
        XCTAssertEqual(app.switches["Solo notes, lane 2"].value as? String, "off", "its sister part's solo is its own")
        Thread.sleep(forTimeInterval: 1.0)
        for _ in 0..<10 {
            Thread.sleep(forTimeInterval: 0.4)
            for n in [1, 3, 4] {
                let playing = app.el("Lane \(n)").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff playing' OR label BEGINSWITH 'Notes playing'")).count
                XCTAssertEqual(playing, 0, "lane \(n) sounds while lane 2's riff is soloed")
            }
        }
        app.switches["Solo riff, lane 2"].tap()
        XCTAssertEqual(app.switches["Solo riff, lane 2"].value as? String, "off", "a second tap releases it")
        let playing = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == true"), object: app.el("Lane 1").descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff playing'")).firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [playing], timeout: 12), .completed, "lane 1's riff plays again once the solo is released")
    }
    /// ONE SOLO (2026-11-05): the lane SOLO tile (cards) and the MIX S buttons are views of the same eight bits. A lane soloed on the cards lights BOTH of its S buttons; switching one S off leaves the lane's SOLO half-lit ("notes only"); a tap on a
    /// half-lit SOLO completes it; a tap on a full one clears both S buttons.
    func testALaneSoloAndThePartSolosOnMixAreOneThing() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        func v(_ label: String) -> String? { app.switches[label].value as? String }
        need(app.switches["Solo lane 2"], "lane 2's SOLO on the cards").tap()
        XCTAssertEqual(v("Solo lane 2"), "on")
        app.buttons["Mix"].tap()
        need(app.switches["Solo riff, lane 2"], "lane 2's riff S")
        XCTAssertEqual(v("Solo riff, lane 2"), "on", "a lane soloed on the cards lights its riff S"); XCTAssertEqual(v("Solo notes, lane 2"), "on", "…and its notes S")
        XCTAssertEqual(v("Solo riff, lane 1"), "off", "another lane's S is untouched")
        app.switches["Solo riff, lane 2"].tap()
        XCTAssertEqual(v("Solo riff, lane 2"), "off"); XCTAssertEqual(v("Solo notes, lane 2"), "on", "the notes stay soloed")
        app.buttons["Rhythm"].tap()
        need(app.switches["Solo lane 2"], "lane 2's SOLO back on the cards")
        XCTAssertEqual(v("Solo lane 2"), "notes only", "only the notes soloed: the lane's SOLO is half-lit, and says so")
        app.switches["Solo lane 2"].tap()
        XCTAssertEqual(v("Solo lane 2"), "on", "a tap completes a half-lit SOLO")
        app.buttons["Mix"].tap()
        need(app.switches["Solo riff, lane 2"], "lane 2's riff S")
        XCTAssertEqual(v("Solo riff, lane 2"), "on"); XCTAssertEqual(v("Solo notes, lane 2"), "on")
        app.buttons["Rhythm"].tap()
        need(app.switches["Solo lane 2"], "lane 2's SOLO").tap()
        XCTAssertEqual(v("Solo lane 2"), "off", "a tap on a full SOLO clears it")
        app.buttons["Mix"].tap()
        need(app.switches["Solo riff, lane 2"], "lane 2's riff S")
        XCTAssertEqual(v("Solo riff, lane 2"), "off"); XCTAssertEqual(v("Solo notes, lane 2"), "off", "both S buttons cleared with it")
    }
    /// The riff grid's label column names what the PICKED lane's riff will SOUND: lane 1's riff OCT −2 moves its first label's octave down by two; another lane's OCT (and the NOTES part's) changes nothing; picking that lane shows its own.
    func testTheRiffGridsLabelColumnFollowsThePickedLanesRiffOctave() {
        let app = XCUIApplication.fresh(["--autoplay"])      // the pool (and so the names) exists only while the transport runs
        Thread.sleep(forTimeInterval: 1)
        func first() -> (label: String, octave: Int)? {
            let l = app.els(prefix: "Rank 1, ").firstMatch.label
            guard let last = l.split(separator: " ").last, let o = Int(last.replacingOccurrences(of: "\u{2212}", with: "-")) else { return nil }
            return (l, o)
        }
        need(app.els(prefix: "Rank 1, ").firstMatch, "the label column's rank 1 chip")
        for _ in 0..<20 where first() == nil { Thread.sleep(forTimeInterval: 0.3) }
        guard let start = first() else { return XCTFail("the first label has no octave: \(app.els(prefix: "Rank 1, ").firstMatch.label)") }
        let o0 = start.octave
        app.els(prefix: "Riff, ").firstMatch.tap()                               // the RIFF tab: each card has its OCT boxes
        let octs = app.els(prefix: "Riff octave")
        need(octs.element(boundBy: 0), "lane 1's riff OCT boxes")
        octs.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()      // the −2 box
        XCTAssertEqual(octs.element(boundBy: 0).label, "Riff octave \u{2212}2")
        XCTAssertEqual(first()?.octave, o0 - 2, "lane 1 is picked: its first label reads two octaves lower (was \(o0), now \(first()?.label ?? "?"))")
        octs.element(boundBy: 1).coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()      // lane 2's riff +2
        XCTAssertEqual(first()?.octave, o0 - 2, "another lane's OCT does not move lane 1's labels")
        app.els(prefix: "Stack, ").firstMatch.tap()                               // the NOTES tab's OCT is the notes part's own
        let nocts = app.els(prefix: "Notes octave")
        if nocts.element(boundBy: 0).waitForExistence(timeout: 3) {
            nocts.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
            XCTAssertEqual(first()?.octave, o0 - 2, "the NOTES part's OCT is not the riff's")
        }
        app.el("Notes shown for").tap()                                           // pick lane 2
        XCTAssertEqual(first()?.octave, o0 + 2, "picking lane 2 shows its own riff OCT (+2)")
    }
    /// Random mode started from MIX shows the cards (their random faces) and finishing returns to the panel.
    func testRandomModeStartedFromMixShowsTheCardsAndReturnsToThePanel() {
        let app = XCUIApplication.fresh(["--autoplay"])
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Mix"].tap()
        need(app.els(prefix: "Riff velocity").firstMatch, "the panel")
        app.buttons["Random mode"].tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.els(prefix: "Riff velocity").firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 2.5), .completed, "random mode shows the cards, not the panel")
        app.buttons["Random mode"].tap()
        need(app.els(prefix: "Riff velocity").firstMatch, "finishing random mode returns to the MIX panel", timeout: 2.5)
        XCTAssertTrue(app.buttons["Mix"].isSelected)
    }

    // INPUTS + HARMONY ferry (2026-11-06): the header's button (four pips, the key) opens and closes the HARMONY page; HOLD/LATCH are unchanged header chips.
    func testTheHarmonyButtonTogglesThePageAndHoldLatchSelect() {
        let app = XCUIApplication.fresh()
        // HOLD / LATCH header chips — always enabled now (MIDI always listens; they used to need a MIDI source).
        app.buttons["Hold"].tap()
        XCTAssertTrue(app.buttons["Hold"].isSelected, "HOLD should read as on")
        app.buttons["Latch"].tap()
        XCTAssertTrue(app.buttons["Latch"].isSelected, "LATCH should read as on")
        XCTAssertFalse(app.buttons["Hold"].isSelected, "HOLD and LATCH are mutually exclusive")
        // the HARMONY button: a tap opens the page over the lane cards, a second tap closes it
        let button = need(app.buttons["Harmony"], "the header HARMONY button")
        XCTAssertTrue((button.value as? String ?? "").hasPrefix("C minor, MIDI IN "), "its value starts with the key and the four pips: \(button.value as? String ?? "")")
        button.tap()
        need(app.buttons["Close harmony"], "the page's close button")
        XCTAssertTrue(app.buttons["Harmony"].isSelected || (app.buttons["Harmony"].value as? String ?? "").hasSuffix("expanded"), "the button reads as open")
        app.buttons["Harmony"].tap()
        gone(app.buttons["Close harmony"], "the page after a second tap on the button")
        // reopened: the close button closes it too
        app.buttons["Harmony"].tap(); need(app.buttons["Close harmony"], "the page again").tap()
        gone(app.buttons["Close harmony"], "the page after its close button")
    }

    func testTheHarmonyPageChangesTheKeyAndTheScale() {
        let app = XCUIApplication.fresh()
        app.buttons["Harmony"].tap()
        need(app.buttons["MAJOR"], "the scale row").tap()
        XCTAssertTrue((app.buttons["Harmony"].value as? String ?? "").hasPrefix("C major"), "the header button reads C major: \(app.buttons["Harmony"].value as? String ?? "")")
        need(app.buttons["D, in scale"], "the root keys (a scale tone reads \"in scale\")").tap()
        XCTAssertTrue((app.buttons["Harmony"].value as? String ?? "").hasPrefix("D major"), "…and then D major: \(app.buttons["Harmony"].value as? String ?? "")")
        app.buttons["Undo"].tap(); Thread.sleep(forTimeInterval: 0.3)
        XCTAssertTrue((app.buttons["Harmony"].value as? String ?? "").hasPrefix("C major"), "the root was one undo step")
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
            need(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Out \(name), channel \(i + 1)")).firstMatch, "Out \(name) reads channel \(i + 1)")
        }
        hittable("Increase channel").tap()
        Thread.sleep(forTimeInterval: 0.6)
        let seen = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Out A, channel'")).allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(seen.contains("Out A, channel 2"), "output A should read channel 2 after +; the sheet says \(seen)")
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
