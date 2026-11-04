//  FourfoldScreenshotTests.swift
//  UI tests of the REAL standalone app in the iOS simulator (2026-10-24; Scripts/fourfold-harness/screenshots.sh). The page had no test reach before: it only existed inside an AUv3 extension. These tests launch the app, rotate the iPad
//  through all four orientations and attach a screenshot of each, so layout, clipping and legibility can be LOOKED AT on every iPad size the simulator offers. They do not judge the pictures — a person (or Claude) reads them.

import XCTest

final class FourfoldScreenshotTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    private func attach(_ name: String) {
        let a = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        a.name = name; a.lifetime = .keepAlways; add(a)
    }

    /// RESTART UNITS (2026-11-04): the restart tiles and editor — free, then set with a RIFF rhythm of its own lane, a PASS source of another lane, a melody HIT chain with WITH RHYTHM — in portrait and landscape, playing.
    func testTheRestartTilesAndEditor() {
        let device = XCUIDevice.shared
        func any(_ e: XCUIElement, _ label: String) -> XCUIElement { e.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch }
        for (tag, o) in [("portrait", UIDeviceOrientation.portrait), ("landscape", .landscapeLeft)] {
            let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
            device.orientation = o
            Thread.sleep(forTimeInterval: 2)
            attach("11-restart-\(tag)-1-tiles-free")
            let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rhythm restarts")).element(boundBy: 0)
            XCTAssertTrue(tile.waitForExistence(timeout: 5), "the restart tile (\(tag))")
            tile.tap(); Thread.sleep(forTimeInterval: 1)
            let editor = app.descendants(matching: .any)["Restarts for lane 1"]
            attach("11-restart-\(tag)-2-editor-free")
            XCTAssertTrue(editor.exists, "the editor opened (\(tag))")
            if editor.exists {
                any(editor, "Count riffs").tap()
                any(editor, "Rhythm restarts, off").tap()
                editor.buttons.matching(NSPredicate(format: "label == %@", "Rhythm link 1, 1 riff")).firstMatch.tap()
                any(editor, "Count hits").tap()
                any(editor, "Restart with the rhythm, off").tap()
                Thread.sleep(forTimeInterval: 1.2)
                attach("11-restart-\(tag)-3-editor-set")
                editor.buttons.matching(NSPredicate(format: "label == %@", "Count passes")).element(boundBy: 0).tap()
                editor.buttons.matching(NSPredicate(format: "label == %@", "Lane 2")).element(boundBy: 0).tap()
                Thread.sleep(forTimeInterval: 0.8)
                attach("11-restart-\(tag)-4-editor-pass-of-lane-2")
                editor.buttons["Close restarts"].tap()
            }
            Thread.sleep(forTimeInterval: 1.2)
            attach("11-restart-\(tag)-5-tiles-set")
            app.terminate()
        }
        device.orientation = .portrait
    }

    /// RESTART UNITS FIX 1 (2026-11-04): WITH RHYTHM switched on while the RHYTHM restart is off — lane 1's MELODY tile reads RHYTHM with the link glyph, runs its outer fill to the lane's next loop and dashes the riff notes a pass will not reach.
    func testTheWithRhythmTileWithTheRhythmOff() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
        attach("12-withrhythm-1-before")
        let tile = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Rhythm restarts")).element(boundBy: 0)
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "the restart tile")
        tile.tap(); Thread.sleep(forTimeInterval: 1)
        let editor = app.descendants(matching: .any)["Restarts for lane 1"]
        XCTAssertTrue(editor.exists, "the editor opened")
        let w = editor.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Restart with the rhythm, off")).firstMatch
        XCTAssertTrue(w.waitForExistence(timeout: 3), "WITH RHYTHM"); w.tap()
        Thread.sleep(forTimeInterval: 0.8)
        attach("12-withrhythm-2-editor")
        editor.buttons["Close restarts"].tap()
        Thread.sleep(forTimeInterval: 2.5)
        attach("12-withrhythm-3-tiles")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Melody restarts with the rhythm")).element(boundBy: 0).exists, "the melody tile now reads 'with the rhythm'")
    }

    /// The page, playing, in each orientation (the page lays itself out from its size; every orientation the app declares is exercised).
    func testThePageInEveryOrientation() {
        let app = XCUIApplication()
        app.launchArguments = ["--fresh", "--autoplay"]
        app.launch()
        let device = XCUIDevice.shared
        for (name, o) in [("1-portrait", UIDeviceOrientation.portrait), ("2-landscape-left", .landscapeLeft), ("3-portrait-upside-down", .portraitUpsideDown), ("4-landscape-right", .landscapeRight)] {
            device.orientation = o
            Thread.sleep(forTimeInterval: 2.5)   // let the layout settle and a few steps play
            attach(name)
        }
        device.orientation = .portrait
    }

    /// Every tab, popup and sheet the page can show, in the orientation the device is in (portrait): the pictures the audits' findings (truncated captions, cramped sheets) are judged against.
    func testEveryTabPopupAndSheet() {
        XCUIDevice.shared.orientation = .portrait
        let screens: [(String, (XCUIApplication) -> Void)] = [
            ("5-mix", { _ in }), ("5-lanes", { $0.buttons["Mute"].tap() }), ("5-fx", { $0.buttons["FX"].tap() }),
            ("5-lane-riff", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff, '")).element(boundBy: 0).tap() }),
            ("5-lane-notes", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notes'")).element(boundBy: 0).tap() }),
            ("5-lane-listen", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Answer, '")).element(boundBy: 0).tap() }),
            ("5-presets", { $0.buttons["Presets"].tap() }), ("5-key", { $0.buttons["Sources"].tap() }), ("5-swing", { $0.buttons["Swing, straight"].tap() }),
            ("5-settings-midi-in", { $0.buttons["Settings"].tap() }),
            ("5-settings-ports", { $0.buttons["Settings"].tap(); $0.buttons["PORTS"].tap() }),
            ("5-settings-clock", { $0.buttons["Settings"].tap(); $0.buttons["CLOCK"].tap() }),
        ]
        for (name, open) in screens {
            let app = XCUIApplication(); app.launchArguments = ["--fresh"]; app.launch()
            Thread.sleep(forTimeInterval: 1.2)
            open(app); Thread.sleep(forTimeInterval: 1)
            attach(name)
            app.terminate()
        }
    }

    /// HOCKET (2026-10-27): the pop-up in the states the ferry's acceptance walks through — empty, a swap rule while playing (live chips), a pass rule, a second rule (taken chips with R tags), the lane cards after closing it.
    func testTheHocketPopup() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        Thread.sleep(forTimeInterval: 2)
        func step(_ el: XCUIElement, _ side: CGFloat = 0.5) { if el.waitForExistence(timeout: 3) { el.coordinate(withNormalizedOffset: CGVector(dx: side, dy: 0.5)).tap() } }
        step(app.el("Hocket")); Thread.sleep(forTimeInterval: 1); attach("6-hocket-empty")
        step(app.el("Main: red riff, off")); step(app.el("Alt: blue riff, off"))
        step(app.el("Main length"), 0.9); step(app.el("Main length"), 0.9)
        Thread.sleep(forTimeInterval: 1.2); attach("6-hocket-swap-live")
        step(app.el("Pass the line")); step(app.el("Main: red notes, off")); step(app.el("Main: blue notes, off")); step(app.el("Alt: blue notes, off")); step(app.el("Alt: red notes, off"))
        Thread.sleep(forTimeInterval: 1.2); attach("6-hocket-pass-crossing")
        step(app.el("Add a rule")); step(app.el("Main: amber notes, off")); step(app.el("Alt: green notes, off"))
        Thread.sleep(forTimeInterval: 1.2); attach("6-hocket-rule-2-taken")
        step(app.el("Close")); Thread.sleep(forTimeInterval: 1.5); attach("6-hocket-lane-cards")
        // reopen on the narrowest-ish layout: portrait
        XCUIDevice.shared.orientation = .portrait; Thread.sleep(forTimeInterval: 2)
        step(app.el("Hocket")); Thread.sleep(forTimeInterval: 1); attach("6-hocket-portrait")
    }

    /// HOCKET §4.4 (review 2026-10-27): order badges on a group of 3+ — the fourth-column chips' badges sit beyond the chip's right edge and used to be clipped by the scroll viewport.
    func testTheHocketBadges() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--fresh"]; app.launch()
        Thread.sleep(forTimeInterval: 1.5)
        func step(_ el: XCUIElement) { if el.waitForExistence(timeout: 3) { el.tap() } }
        step(app.el("Hocket"))
        for chip in ["Main: red riff, off", "Main: blue riff, off", "Main: amber riff, off", "Main: green riff, off", "Main: green notes, off", "Main: amber notes, off", "Alt: red notes, off", "Alt: blue notes, off", "Alt: green notes, off"] { step(app.el(chip)) }
        Thread.sleep(forTimeInterval: 1); attach("6-hocket-badges")
    }

    /// HOCKET §3: the DELETE RULE popover after a hold on rule 2's tab, with a taken chip behind it.
    func testTheHocketDeletePopover() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--fresh"]; app.launch()
        Thread.sleep(forTimeInterval: 1.5)
        func step(_ el: XCUIElement) { if el.waitForExistence(timeout: 3) { el.tap() } }
        step(app.el("Hocket")); step(app.el("Main: red riff, off")); step(app.el("Alt: blue riff, off")); step(app.el("Add a rule"))
        let tab2 = app.switches.matching(NSPredicate(format: "label BEGINSWITH %@", "Rule 2")).firstMatch
        if tab2.waitForExistence(timeout: 3) { tab2.press(forDuration: 0.8) }
        Thread.sleep(forTimeInterval: 1); attach("6-hocket-delete-popover")
    }

    /// HOCKET §9: a riff crossing on BARS (RED RIFF and BLUE RIFF trade places every other bar) with the pop-up closed, shot across a few bars so both turns show on the lane cards' glyphs, MIX labels and strips.
    func testTheHocketGlyphStates() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        Thread.sleep(forTimeInterval: 2)
        func step(_ el: XCUIElement, _ side: CGFloat = 0.5) { if el.waitForExistence(timeout: 3) { el.coordinate(withNormalizedOffset: CGVector(dx: side, dy: 0.5)).tap() } }
        step(app.el("Hocket")); Thread.sleep(forTimeInterval: 0.8)
        step(app.el("Pass the line")); step(app.el("Bars"))
        step(app.el("Main: red riff, off")); step(app.el("Main: blue riff, off")); step(app.el("Alt: blue riff, off")); step(app.el("Alt: red riff, off"))
        step(app.el("Close")); Thread.sleep(forTimeInterval: 0.6)
        for i in 1...6 { attach("7-glyphs-\(i)"); Thread.sleep(forTimeInterval: 1.3) }
    }

    /// ANSWER ferry (2026-11-02): the ANSWER tab bare, then with RHYTHM / PITCH (SHADOW, the panel) / TRADE all on and cycling (the worst-case body), the RHYTHM tab with the strip over the borrowed card, the same lane with CYCLE (a live body), and
    /// the POOL tab — landscape, then portrait. The pictures the layout is judged against.
    func testTheAnswerAndPoolTabs() {
        for (tag, o) in [("land", UIDeviceOrientation.landscapeLeft), ("port", .portrait)] {
            XCUIDevice.shared.orientation = o
            let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()   // a fresh document each orientation: the taps below are toggles
            Thread.sleep(forTimeInterval: 2)
            func tap(_ label: String) { let e = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch; if e.waitForExistence(timeout: 3) { e.tap(); Thread.sleep(forTimeInterval: 0.4) } }
            func tapPrefix(_ p: String) { let e = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", p)).firstMatch; if e.waitForExistence(timeout: 3) { e.tap(); Thread.sleep(forTimeInterval: 0.4) } }
            tapPrefix("Answer, "); Thread.sleep(forTimeInterval: 0.8); attach("11-answer-\(tag)-0-bare")
            tap("Rhythm, lane 1"); attach("11-answer-\(tag)-1-rhythm-on")
            tap("Pitch, lane 1"); tap("Cycle pitch, lane 1"); tap("Trade, lane 1"); tap("Cycle rhythm, lane 1"); Thread.sleep(forTimeInterval: 1.5); attach("11-answer-\(tag)-2-everything")
            app.buttons["Rhythm"].tap(); Thread.sleep(forTimeInterval: 0.8); attach("11-answer-\(tag)-3-rhythm-tab-live-body-with-cycle")
            tapPrefix("Answer, "); tap("Cycle rhythm, lane 1"); app.buttons["Rhythm"].tap(); Thread.sleep(forTimeInterval: 0.8); attach("11-answer-\(tag)-4-rhythm-tab-borrowed")
            tapPrefix("Pool, "); Thread.sleep(forTimeInterval: 0.8); attach("11-answer-\(tag)-5-pool")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// POOL ferry (2026-11-02): the POOL tab (NOW, SOURCES, CANON, FREEZE, SUSTAIN), its switches, the NOTES keys as rank chips, and the riff grid's label chips with the lane picker — landscape and portrait.
    func testThePoolTab() {
        for (tag, o) in [("land", UIDeviceOrientation.landscapeLeft), ("port", .portrait)] {
            XCUIDevice.shared.orientation = o
            let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
            Thread.sleep(forTimeInterval: 2)
            func tap(_ label: String) { let e = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch; if e.waitForExistence(timeout: 3) { e.tap(); Thread.sleep(forTimeInterval: 0.5) } }
            func tapPrefix(_ p: String) { let e = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", p)).firstMatch; if e.waitForExistence(timeout: 3) { e.tap(); Thread.sleep(forTimeInterval: 0.5) } }
            tapPrefix("Pool, "); Thread.sleep(forTimeInterval: 1); attach("12-pool-\(tag)-0-bare")
            tap("Chords 2, lane 1"); tap("Chords 2, lane 3"); tap("Chords 1, lane 3"); Thread.sleep(forTimeInterval: 0.6); attach("12-pool-\(tag)-0b-chord-grids")   // TWO CHORD GRIDS: lane 1 on CHORD 2; lane 3 to CHORD 2 and back to CHORD 1 (the default)
            tap("Sustain, lane 1"); tap("Key, lane 2"); tap("Sustain stack, lane 3, loses nothing, off"); Thread.sleep(forTimeInterval: 1); attach("12-pool-\(tag)-1-switches")
            tapPrefix("Notes, "); Thread.sleep(forTimeInterval: 1); attach("12-pool-\(tag)-2-notes-keys")
            tap("Notes shown for"); Thread.sleep(forTimeInterval: 0.8); attach("12-pool-\(tag)-3-grid-lane2")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// TAB STRIP (2026-10-29): the one strip above the lane cards on each tab (the glyph clusters, the selected segment), MIX, then random mode and lock mode with their faces at the shorter cards — landscape.
    func testTheLaneStripAndTheModes() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        Thread.sleep(forTimeInterval: 2)
        func step(_ el: XCUIElement) { if el.waitForExistence(timeout: 3) { el.tap() } }
        attach("9-strip-1-rhythm")
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("9-strip-2-riff")
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notes, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("9-strip-3-notes")
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Answer, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("9-strip-4-listen")
        step(app.buttons["Mix"]); Thread.sleep(forTimeInterval: 1.2); attach("9-strip-5-mix")
        step(app.buttons["Rhythm"]); Thread.sleep(forTimeInterval: 1.2)
        step(app.buttons["Random mode"]); Thread.sleep(forTimeInterval: 1); attach("9-strip-6-random-mode")
        step(app.buttons["Random mode"]); Thread.sleep(forTimeInterval: 0.6)
        step(app.switches["Lock mode"]); Thread.sleep(forTimeInterval: 1); attach("9-strip-7-lock-mode")
        step(app.switches["Lock mode"]); Thread.sleep(forTimeInterval: 0.6)
        attach("9-strip-8-back-on-rhythm")
    }

    /// CHORD CANON (2026-10-31): the LISTEN tab's CANON row in landscape (the card is shorter there than in portrait) and the debug-only CANON ENTRY control on the settings sheet's CLOCK tab.
    func testTheCanonRowAndTheEntrySetting() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--fresh"]; app.launch()
        Thread.sleep(forTimeInterval: 2)
        func step(_ el: XCUIElement) { if el.waitForExistence(timeout: 3) { el.tap() } }
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Pool, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("10-canon-row-landscape")   // ANSWER ferry: CANON lives on the POOL tab now
        if let delay = Optional(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Canon delay, lane 1")).firstMatch), delay.waitForExistence(timeout: 3) {
            delay.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); Thread.sleep(forTimeInterval: 1); attach("10-canon-row-landscape-delay-set")
        }
        step(app.buttons["Settings"]); step(app.buttons["CLOCK"]); Thread.sleep(forTimeInterval: 1); attach("10-canon-entry-clock-tab")
        XCUIDevice.shared.orientation = .portrait
    }

    /// MIX ROWS (2026-11-03): the MIX panel (the strip's MIX segment — four lane bands and the A–D emitters), playing, in every orientation — the picture the ferry's §13 acceptance is judged against — then with lane 1's riff also routed
    /// to C, its TRANS and OCT moved and lane 1's notes off, then back on the cards.
    func testTheMixPanel() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        let device = XCUIDevice.shared
        device.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.5)
        let mix = app.buttons["Mix"]
        if mix.waitForExistence(timeout: 5) { mix.tap() }
        for (name, o) in [("9-mix-1-portrait", UIDeviceOrientation.portrait), ("9-mix-2-landscape-left", .landscapeLeft), ("9-mix-3-portrait-upside-down", .portraitUpsideDown), ("9-mix-4-landscape-right", .landscapeRight)] {
            device.orientation = o
            Thread.sleep(forTimeInterval: 3)
            attach(name)
        }
        device.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        let outs = app.descendants(matching: .any).matching(NSPredicate(format: "label == 'Riff to C, off'"))      // route lane 1's riff to C as well: a second line to C
        if outs.count > 0 { outs.element(boundBy: 0).tap() }
        let trans = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff transpose'"))   // TRANS +2, OCT +1 on lane 1's riff
        if trans.count > 0 { trans.element(boundBy: 0).swipeUp(); trans.element(boundBy: 0).swipeUp() }
        let oct = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff octave'"))
        if oct.count > 0 { oct.element(boundBy: 0).swipeUp() }
        let notesToggle = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notes, on'"))
        if notesToggle.count > 0 { notesToggle.element(boundBy: 0).tap() }
        Thread.sleep(forTimeInterval: 2)
        attach("9-mix-5-routed-shaped-and-off")
        // a LOCKED lane: lock mode on, lock lane 1, lock mode off — the MIX panel returns with the badge (24 pt) before lane 1's SOLO and its strip shortened
        let lockSwitch = app.switches["Lock mode"]
        if lockSwitch.waitForExistence(timeout: 3) {
            lockSwitch.tap(); Thread.sleep(forTimeInterval: 0.8)
            let lane1 = app.els(prefix: "Lock lane 1").firstMatch
            if lane1.waitForExistence(timeout: 3) { lane1.tap(); Thread.sleep(forTimeInterval: 0.5) }
            lockSwitch.tap(); Thread.sleep(forTimeInterval: 1.2)
            attach("9-mix-5b-locked-lane")
        }
        app.buttons["Rhythm"].tap(); Thread.sleep(forTimeInterval: 1.5)
        attach("9-mix-6-back-to-the-cards")
    }

    /// RATCH tab ferry (2026-10-28): the tab as it opens (every emitter off), then with A at 16 / 16 / ×4 (every slot four bars) and B at CHANCE 50 — playing, in both orientations — so the strips, bars and cells can be looked at.
    func testTheRatchTab() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        let device = XCUIDevice.shared
        device.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.5)
        let tab = app.buttons["Ratchet"]
        if tab.waitForExistence(timeout: 5) { tab.tap() }
        Thread.sleep(forTimeInterval: 1.5)
        attach("9-ratch-1-portrait-off")
        func drag(_ label: String, by dy: CGFloat) {
            let cell = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", label)).element(boundBy: 0)
            guard cell.exists else { return }
            let p = cell.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            p.press(forDuration: 0.05, thenDragTo: p.withOffset(CGVector(dx: 0, dy: dy)))
        }
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Ratchet on emitter A")).element(boundBy: 0).tap()
        drag("Emitter A steps ", by: -90); drag("Emitter A hits ", by: -140); drag("Emitter A strikes ", by: -40)
        app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Ratchet on emitter B")).element(boundBy: 0).tap()
        drag("Emitter B chance ", by: 15)
        Thread.sleep(forTimeInterval: 2)
        attach("9-ratch-2-portrait-a-16-16-x4")
        device.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 3)
        attach("9-ratch-3-landscape-a-16-16-x4")
        device.orientation = .portraitUpsideDown
        Thread.sleep(forTimeInterval: 2.5)
        attach("9-ratch-4-portrait-upside-down")
        device.orientation = .portrait
    }

    /// The home screen with the app's icon on it (the icon at its real on-screen size), before and after paging.
    func testTheIconOnTheHomeScreen() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh"]; app.launch()
        XCUIDevice.shared.orientation = .portrait
        XCUIDevice.shared.press(.home)
        Thread.sleep(forTimeInterval: 1.5)
        attach("home-screen-page-1")
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        springboard.swipeLeft(); Thread.sleep(forTimeInterval: 1)
        attach("home-screen-page-2")
    }

    /// CHORDS PAGE (2026-11-04): the full-screen page over the lane cards — opened, then with GRID 1 on ADVANCE LOOP
    /// and RESTART on — in portrait and landscape, playing, so the two grids, the ADVANCE/RESTART rows, the step strip
    /// and the lane strip can be LOOKED AT.
    func testTheChordsPage() {
        let device = XCUIDevice.shared
        for (tag, o) in [("portrait", UIDeviceOrientation.portrait), ("landscape", .landscapeLeft)] {
            let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
            device.orientation = o
            Thread.sleep(forTimeInterval: 2)
            let sources = app.el("Sources")
            guard sources.waitForExistence(timeout: 5) else { continue }
            sources.tap(); Thread.sleep(forTimeInterval: 0.6)
            let edit = app.el("Edit chords")
            guard edit.waitForExistence(timeout: 4) else { attach("12-chords-\(tag)-0-no-chords-row"); continue }
            edit.tap(); Thread.sleep(forTimeInterval: 1)
            attach("12-chords-\(tag)-1-opened")                       // GRID 1 / GRID 2, both on TIME, restart off
            let advLoop = app.el("Advance by loop")                   // first match = GRID 1
            if advLoop.waitForExistence(timeout: 3) { advLoop.tap(); Thread.sleep(forTimeInterval: 0.6); attach("12-chords-\(tag)-2-advance-loop") }
            let restart = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Restart")).firstMatch
            if restart.exists { restart.tap(); Thread.sleep(forTimeInterval: 0.6); attach("12-chords-\(tag)-3-restart-on") }
        }
    }
}
