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
        let before = app.els(prefix: "Rhythm, ").element(boundBy: 0).label
        XCTAssertEqual(before, "Rhythm, 3 of 8 hits")
        app.buttons["More steps, now 8"].firstMatch.tap()
        need(app.buttons["More steps, now 9"].firstMatch, "lane 1 at 9 steps after one + tap")
        need(app.el("Rhythm, 3 of 9 hits"), "the RHYTHM tab following the new length")
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
        XCTAssertNotEqual(app.els(prefix: "Rhythm, ").element(boundBy: 0).label, "Rhythm, 3 of 8 hits")
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
        app.els(prefix: "Riff, ").element(boundBy: 0).tap()
        need(app.el("Advance every"), "the RIFF tab's ADVANCE EVERY row")   // (the WALK strip above it is dropped on a card too short for it — the iPad mini — so it is not the thing to look for)
        app.els(prefix: "Notes").element(boundBy: 0).tap()
        need(app.el("Notes layer, off, 0 notes lit"), "the NOTES tab's layer switch")
        app.els(prefix: "Listen, ").element(boundBy: 0).tap()
        need(app.el("Follow lane 2"), "the LISTEN tab's partner picker")
        app.els(prefix: "Rhythm, ").element(boundBy: 0).tap()
        need(app.otherElements.matching(NSPredicate(format: "label == %@", "HITS")).firstMatch, "the RHYTHM tab again")
    }

    func testTheSequencerPanelSwitchesBetweenMixLanesAndFx() {
        let app = XCUIApplication.fresh()
        need(app.el("Lane 1 riff"), "the MIX pads")
        app.buttons["Lanes"].tap()
        need(app.buttons["Lane 1 cell size PASS"], "the LANES panel's rate box")
        XCTAssertTrue(app.buttons["Lanes"].isSelected)
        app.buttons["FX"].tap()
        need(app.buttons["FX row, ratchet, all lanes, selected"], "the FX panel's RATCH row")
        app.buttons["Mix"].tap()
        need(app.el("Lane 1 riff"), "the MIX pads again")
    }

    func testAnOutputCircleOnTheRiffTabTogglesItsRouting() {
        let app = XCUIApplication.fresh()
        app.els(prefix: "Riff, ").element(boundBy: 0).tap()           // the per-layer routing ferry moved the OUT buttons off MIX onto each lane's RIFF and NOTES tabs
        need(app.el("Riff to output B, off"), "lane 1's riff OUT B, off").tap()        // (a toggle-trait control reports as a switch, so ask for it by label, not by type)
        need(app.el("Riff to output B, on"), "lane 1's riff OUT B, on after a tap")
        app.el("Riff to output B, on").tap()
        need(app.el("Riff to output B, off"), "lane 1's riff OUT B, off after a second tap")
    }

    /// OUT-MASK-NIL-1: a factory preset stores no output mask and sounds on A-D, so its circles must read ON, and the first
    /// tap must switch off just that one output.
    func testAFactoryPresetShowsItsOutputCirclesLitAndATapSwitchesOffOnlyThatOne() {
        let app = XCUIApplication.fresh()
        app.buttons["Presets"].tap()
        need(app.buttons["FIVE AGAINST EIGHT, factory preset"], "a factory preset row").tap()
        gone(app.staticTexts["PRESETS"], "the preset browser after choosing a preset")
        app.els(prefix: "Riff, ").element(boundBy: 0).tap()
        for o in ["A", "B", "C", "D"] { need(app.el("Riff to output \(o), on"), "a preset lane's riff OUT \(o) reads on") }
        app.el("Riff to output A, on").tap()
        need(app.el("Riff to output A, off"), "riff OUT A, off after one tap")
        for o in ["B", "C", "D"] { need(app.el("Riff to output \(o), on"), "riff OUT \(o) still on after A was tapped") }
    }

    func testTheNoteSourceHoldAndLatchControlsSelect() {
        let app = XCUIApplication.fresh()
        XCTAssertTrue(app.buttons["Key"].isSelected, "KEY is the default note source")
        app.buttons["Chords"].tap()
        XCTAssertTrue(app.buttons["Chords"].isSelected); XCTAssertFalse(app.buttons["Key"].isSelected)
        app.buttons["MIDI in"].tap()
        XCTAssertTrue(app.buttons["MIDI in"].isSelected)
        app.buttons["Hold"].tap()
        XCTAssertTrue(app.buttons["Hold"].isSelected, "HOLD should read as on")
        app.buttons["Latch"].tap()
        XCTAssertTrue(app.buttons["Latch"].isSelected, "LATCH should read as on")
        XCTAssertFalse(app.buttons["Hold"].isSelected, "HOLD and LATCH are mutually exclusive")
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
        let before = (0..<4).map { app.els(prefix: "Rhythm, ").element(boundBy: $0).label }
        app.buttons["Presets"].tap()
        need(app.staticTexts["PRESETS"], "the preset browser")
        need(app.buttons["FIVE AGAINST EIGHT, factory preset"], "a factory preset row").tap()
        gone(app.staticTexts["PRESETS"], "the preset browser after choosing a preset")
        let after = (0..<4).map { app.els(prefix: "Rhythm, ").element(boundBy: $0).label }
        XCTAssertNotEqual(before, after, "loading FIVE AGAINST EIGHT should change the lanes")
    }

    func testTheSettingsSheetOpensEditsAChannelAndCloses() {
        let app = XCUIApplication.fresh()
        app.buttons["Settings"].tap()
        need(app.buttons["MIDI IN"].firstMatch, "the settings sheet's MIDI IN tab")
        app.buttons["MAIN OUT"].tap()
        // (the sheet keeps a hidden, invisible copy of this page to measure its height, so ask for the one that can be touched)
        let hittable = { (label: String) -> XCUIElement in
            let all = app.images.matching(NSPredicate(format: "label == %@", label)).allElementsBoundByIndex
            return all.first(where: { $0.isHittable }) ?? all[0]
        }
        need(app.images.matching(NSPredicate(format: "label == %@", "Increase channel")).firstMatch, "the MAIN OUT page's channel steppers")
        hittable("Increase channel").tap()
        Thread.sleep(forTimeInterval: 0.6)
        let seen = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Main out A, Out A'")).allElementsBoundByIndex.map(\.label)
        XCTAssertTrue(seen.contains("Main out A, Out A, channel 2"), "out A should read channel 2 after +; the sheet says \(seen)")
        hittable("Decrease channel").tap()
        app.buttons["Close settings"].tap()
        gone(app.buttons["MAIN OUT"].firstMatch, "the settings sheet after Close")
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
