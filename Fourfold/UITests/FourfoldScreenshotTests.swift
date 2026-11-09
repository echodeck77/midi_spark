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

    /// RESTART UNITS (2026-11-04); RESTARTS EDITOR V2 (2026-11-06): the restart tiles and editor — free, then set with a RIFF rhythm of its own lane, a PASS source of another lane, a melody HIT chain with WITH RHYTHM — in portrait and landscape,
    /// playing. (Not run this session — no iOS simulator runtime; the labels/flow match the V2 design.)
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
                any(editor, "Count riffs").tap()   // §3: wakes the RHYTHM chain (RIFF of its own lane), appending a 1
                any(editor, "Rhythm link 1, 1 riff").tap()   // steps the count chip
                any(editor, "Count hits").tap()   // wakes the MELODY chain (HIT)
                any(editor, "Melody restarts with the rhythm, off").tap()
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
        let w = editor.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Melody restarts with the rhythm, off")).firstMatch
        XCTAssertTrue(w.waitForExistence(timeout: 3), "the link row"); w.tap()
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
            ("5-mix", { _ in }), ("5-lanes", { $0.buttons["Mute"].tap() }),
            ("5-lane-riff", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff, '")).element(boundBy: 0).tap() }),
            ("5-lane-notes", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notes'")).element(boundBy: 0).tap() }),
            ("5-lane-listen", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Answer, '")).element(boundBy: 0).tap() }),
            ("5-presets", { $0.buttons["Presets"].tap() }), ("5-harmony", { $0.buttons["Harmony"].tap() }), ("5-swing", { $0.buttons["Swing, straight"].tap() }),
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
            app.buttons["Euclid"].tap(); Thread.sleep(forTimeInterval: 0.8); attach("11-answer-\(tag)-3-rhythm-tab-live-body-with-cycle")
            tapPrefix("Answer, "); tap("Cycle rhythm, lane 1"); app.buttons["Euclid"].tap(); Thread.sleep(forTimeInterval: 0.8); attach("11-answer-\(tag)-4-rhythm-tab-borrowed")
            tapPrefix("Inputs, "); Thread.sleep(forTimeInterval: 0.8); attach("11-answer-\(tag)-5-inputs")   // POOL renamed INPUTS (2026-11-05)
        }
        XCUIDevice.shared.orientation = .portrait
    }

    /// INPUTS (ferry 2026-11-06): the INPUTS tab (NOW with its source pips, SOURCES, MIDI, CANON), a lane's MIDI mode switched through ADD · REPLACE · ROOT, a source chip off (the MIDI row dims), the NOTES keys as rank chips and the riff grid's label chips — landscape and portrait.
    func testTheInputsTab() {
        for (tag, o) in [("land", UIDeviceOrientation.landscapeLeft), ("port", .portrait)] {
            XCUIDevice.shared.orientation = o
            let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
            Thread.sleep(forTimeInterval: 2)
            func tap(_ label: String) { let e = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch; if e.waitForExistence(timeout: 3) { e.tap(); Thread.sleep(forTimeInterval: 0.5) } }
            func tapPrefix(_ p: String) { let e = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", p)).firstMatch; if e.waitForExistence(timeout: 3) { e.tap(); Thread.sleep(forTimeInterval: 0.5) } }
            tapPrefix("Inputs, "); Thread.sleep(forTimeInterval: 1); attach("12-inputs-\(tag)-0-bare")
            tap("Chords 2, lane 1"); tap("Chords 2, lane 3"); tap("Chords 1, lane 3"); Thread.sleep(forTimeInterval: 0.6); attach("12-inputs-\(tag)-0b-chord-grids")   // TWO CHORD GRIDS: lane 1 on CHORD 2; lane 3 to CHORD 2 and back to CHORD 1 (the default)
            tap("Replace, lane 1"); tap("Root, lane 2"); tap("Replace, lane 3"); tap("Root, lane 3"); Thread.sleep(forTimeInterval: 0.8); attach("12-inputs-\(tag)-1-midi-modes")
            tap("MIDI in, lane 4"); tap("Key, lane 2"); Thread.sleep(forTimeInterval: 1); attach("12-inputs-\(tag)-2-midi-chip-off-dims-the-row")
            tapPrefix("Stack, "); Thread.sleep(forTimeInterval: 1); attach("12-inputs-\(tag)-3-notes-keys")
            tap("Notes shown for"); Thread.sleep(forTimeInterval: 0.8); attach("12-inputs-\(tag)-4-grid-lane2")
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
        step(app.buttons["Euclid"]); Thread.sleep(forTimeInterval: 1.2)
        step(app.buttons["Random mode"]); Thread.sleep(forTimeInterval: 1); attach("9-strip-6-random-mode")
        step(app.buttons["Random mode"]); Thread.sleep(forTimeInterval: 0.6)
        step(app.switches["Lock mode"]); Thread.sleep(forTimeInterval: 1); attach("9-strip-7-lock-mode")
        step(app.switches["Lock mode"]); Thread.sleep(forTimeInterval: 0.6)
        attach("9-strip-8-back-on-rhythm")
    }

    /// RIFF v2 (2026-11-05): the regrouped RIFF tab — the wide riff toggle with the arrow directions under it, the MOVE and NOTES bands, FLIP NOTES — in both orientations, with a direction, HIT|STEP and FLIP NOTES exercised.
    func testTheRiffTabRegroup() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        func step(_ el: XCUIElement) { if el.waitForExistence(timeout: 3) { el.tap() } }
        func toRiff() { step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff, '")).firstMatch) }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        toRiff(); Thread.sleep(forTimeInterval: 1.2)
        attach("10-riff-1-landscape")
        // exercise a lane: pick a direction (ping-pong), flip notes, switch HIT -> STEP — so the selected looks show
        step(app.buttons["Ping-pong"].firstMatch); step(app.buttons["Flip notes"].firstMatch); step(app.buttons["Advance by steps"].firstMatch)
        Thread.sleep(forTimeInterval: 1)
        attach("10-riff-2-landscape-selected")
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 2)
        toRiff(); Thread.sleep(forTimeInterval: 1.2)
        attach("10-riff-3-portrait")
    }

    /// CHORD CANON (2026-10-31): the LISTEN tab's CANON row in landscape (the card is shorter there than in portrait) and the debug-only CANON ENTRY control on the settings sheet's CLOCK tab.
    func testTheCanonRowAndTheEntrySetting() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--fresh"]; app.launch()
        Thread.sleep(forTimeInterval: 2)
        func step(_ el: XCUIElement) { if el.waitForExistence(timeout: 3) { el.tap() } }
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Inputs, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("10-canon-row-landscape")   // ANSWER ferry: CANON lives on the INPUTS tab (the POOL tab renamed)
        if let delay = Optional(app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "Canon delay, lane 1")).firstMatch), delay.waitForExistence(timeout: 3) {
            delay.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap(); Thread.sleep(forTimeInterval: 1); attach("10-canon-row-landscape-delay-set")
        }
        step(app.buttons["Settings"]); step(app.buttons["CLOCK"]); Thread.sleep(forTimeInterval: 1); attach("10-canon-entry-clock-tab")
        XCUIDevice.shared.orientation = .portrait
    }

    /// MIX ROWS (2026-11-03): the MIX panel (the strip's MIX segment — four lane bands and the A–D emitters), playing, in every orientation — the picture the ferry's §13 acceptance is judged against — then with lane 1's riff also routed
    /// to C, its OCT moved and lane 1's notes off, then back on the cards.
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
        app.buttons["Euclid"].tap(); Thread.sleep(forTimeInterval: 1.5)
        attach("9-mix-6-back-to-the-cards")
    }

    /// MIX v2 (2026-11-05): a part solo latched (lane 2's riff — every other part dims and goes silent, lane 2's notes dims too), and the dev OUTLINE toggles.
    func testTheMixV2PartSoloAndOutlineToggles() {
        for (tag, extra) in [("solo", [String]()), ("outline", ["-fourfold.mixToggleMode", "OUTLINE"])] {
            let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"] + extra; app.launch()
            XCUIDevice.shared.orientation = .landscapeLeft
            Thread.sleep(forTimeInterval: 2)
            let mix = app.buttons["Mix"]
            if mix.waitForExistence(timeout: 5) { mix.tap() }
            if tag == "solo" {
                let s = app.switches["Solo riff, lane 2"]
                if s.waitForExistence(timeout: 3) { s.tap() }
            }
            Thread.sleep(forTimeInterval: 2.5)
            attach("9-mixv2-\(tag)-land-")
            app.terminate()
        }
    }

    /// ONE SOLO (2026-11-05): lane 2's riff soloed on MIX alone → on the RHYTHM tab lane 2's SOLO is half-lit; lane 3 fully soloed from the cards beside it for comparison.
    func testTheHalfLitLaneSolo() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh"]; app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 2)
        let mix = app.buttons["Mix"]
        if mix.waitForExistence(timeout: 5) { mix.tap() }
        let s = app.switches["Solo riff, lane 2"]
        if s.waitForExistence(timeout: 3) { s.tap() }
        Thread.sleep(forTimeInterval: 0.8)
        app.buttons["Euclid"].tap()
        Thread.sleep(forTimeInterval: 1.2)
        let l3 = app.switches["Solo lane 3"]
        if l3.waitForExistence(timeout: 3) { l3.tap() }
        Thread.sleep(forTimeInterval: 1)
        attach("9-solo-halflit-land-")
        app.terminate()
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
        attach("9-ratch-2-portrait-a-16-16-x4")   // RATCH EXPAND (2026-11-04): the collapsed card now shows STEPS·HITS·OFFSET·STRIKES + a config button
        device.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 3)
        attach("9-ratch-3-landscape-a-16-16-x4")
        // RATCH EXPAND §5: open emitter A's config and step through the STRIKES modes + GAP, in landscape (the expanded view fills the panel)
        func tapExact(_ label: String) {
            let e = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).element(boundBy: 0)
            if e.waitForExistence(timeout: 2) { e.tap() }
        }
        tapExact("Configure emitter A"); Thread.sleep(forTimeInterval: 1.2)
        attach("9-ratch-5-landscape-expanded-fix")
        tapExact("Strikes mode RANGE"); Thread.sleep(forTimeInterval: 0.8)
        attach("9-ratch-6-landscape-expanded-range")
        tapExact("Strikes mode HIT"); Thread.sleep(forTimeInterval: 0.8)
        attach("9-ratch-7-landscape-expanded-hit")
        tapExact("Strike gap 1/16"); Thread.sleep(forTimeInterval: 0.8)
        attach("9-ratch-8-landscape-expanded-hit-gap16")
        tapExact("Configure emitter A"); Thread.sleep(forTimeInterval: 1.0)   // the collapse button (open) — back to the four cards
        device.orientation = .portraitUpsideDown
        Thread.sleep(forTimeInterval: 2.5)
        attach("9-ratch-9-portrait-upside-down")
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

    /// HARMONY (ferry 2026-11-06): the page over the lane cards, opened from the header button — the key (title, root keys, scales), both grids, a summary pill's popover, the CHORDS · COLOUR switch, the PICK editor — in portrait and
    /// landscape, playing, so the proportions, the pills and the popovers can be LOOKED AT.
    /// STACK GRID (2026-11-08): the riff panel's STACK view — a few cells lit on different lanes, then the NOTES tab ("STACK" in the strip) showing the same keys lit.
    func testTheStackGrid() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["Stack"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.8)
        attach("13-stack-grid-1-off")
        for label in ["Lane 1, rank 3,", "Lane 1, top,", "Lane 2, rank 5,", "Lane 3, rank 1,", "Lane 4, rank 8,"] { app.els(prefix: label).firstMatch.tap(); Thread.sleep(forTimeInterval: 0.2) }
        Thread.sleep(forTimeInterval: 0.6); attach("13-stack-grid-2-lit")
        app.els(prefix: "Stack, ").firstMatch.tap(); Thread.sleep(forTimeInterval: 1); attach("13-stack-grid-3-notes-tab")
    }

    /// CC tab trace (2026-11-08, lane colours + PING-PONG 2026-11-09): the collapsed rows with two emitters on and the transport playing (curve, lane-coloured dots, playhead), lane 2 routed onto emitter A as well (two colours on one trace),
    /// then emitter A's page under RIFF/STEP, RIFF/GLIDE and PING-PONG with GLIDE, STEP and FALL, so the wave can be LOOKED AT.
    func testTheCCTrace() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        Thread.sleep(forTimeInterval: 1)
        app.buttons["C C emitters"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.8)
        attach("15-cc-trace-1-collapsed-off")
        app.el("Emitter A").tap(); app.el("Emitter B").tap(); Thread.sleep(forTimeInterval: 1.2)
        attach("15-cc-trace-2-collapsed-two-on")
        app.buttons["Mix"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.8)
        app.els(prefix: "Riff to A, off").firstMatch.tap(); Thread.sleep(forTimeInterval: 0.6)   // lane 2's riff also goes to A
        app.buttons["Euclid"].firstMatch.tap(); Thread.sleep(forTimeInterval: 0.8)
        attach("15-cc-trace-3-collapsed-lane-2-on-A")
        app.els(prefix: "Emitter A CC").firstMatch.tap(); Thread.sleep(forTimeInterval: 1)
        attach("15-cc-trace-4-expanded-riff-step-two-lanes")
        app.el("Travel GLIDE").tap(); Thread.sleep(forTimeInterval: 1); attach("15-cc-trace-5-expanded-riff-glide")
        app.el("Value PING").tap(); Thread.sleep(forTimeInterval: 1); attach("15-cc-trace-6-expanded-pingpong-glide")
        app.el("Travel STEP").tap(); Thread.sleep(forTimeInterval: 1); attach("15-cc-trace-7-expanded-pingpong-step")
        app.el("Travel FALL").tap(); Thread.sleep(forTimeInterval: 1); attach("15-cc-trace-8-expanded-pingpong-fall")
        app.el("Value RAMP").tap(); app.el("Travel STEP").tap(); Thread.sleep(forTimeInterval: 1.2); attach("15-cc-trace-9-expanded-ramp-1-pass")
        app.el("Close").tap(); Thread.sleep(forTimeInterval: 1.2); attach("15-cc-trace-10-collapsed")
    }

    func testTheHarmonyPage() {
        let device = XCUIDevice.shared
        for (tag, o) in [("port", UIDeviceOrientation.portrait), ("land", .landscapeLeft)] {
            let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
            device.orientation = o
            Thread.sleep(forTimeInterval: 2)
            func tap(_ label: String, in scope: XCUIElement? = nil, wait: TimeInterval = 3) -> Bool {
                let root = scope ?? app.descendants(matching: .alert)["Harmony"]
                let e = root.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
                guard e.waitForExistence(timeout: wait) else { return false }
                e.tap(); Thread.sleep(forTimeInterval: 0.6); return true
            }
            let header = app.buttons["Harmony"]
            guard header.waitForExistence(timeout: 5) else { attach("13-harmony-\(tag)-0-no-header-button"); continue }
            attach("13-harmony-\(tag)-0-closed")
            header.tap(); Thread.sleep(forTimeInterval: 1)
            let page = app.descendants(matching: .alert)["Harmony"]
            attach("13-harmony-\(tag)-1-opened")                                  // the key, both grids, PICK and MIDI IN
            if tap("Grid 1 timing") { attach("13-harmony-\(tag)-2-pill-popover") }  // ADVANCE (TIME) and RESTART (off)
            if tap("Advance by loop") { _ = tap("Restart"); Thread.sleep(forTimeInterval: 0.4); attach("13-harmony-\(tag)-3-advance-loop-restart-on") }
            if tap("Grid 2 timing") { attach("13-harmony-\(tag)-4-other-pill") }     // opens grid 2's popover instead; grid 1's pill now reads LOOP … RESTART
            page.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap(); Thread.sleep(forTimeInterval: 0.6)   // outside the popover: closes it
            attach("13-harmony-\(tag)-5-popover-closed-pills")
            if tap("Colour rows") { attach("13-harmony-\(tag)-6-colour-rows") }
            _ = tap("Chord rows")
            if tap("D, in scale") { _ = tap("DORIAN"); attach("13-harmony-\(tag)-7-key-d-dorian") }
            if tap("Edit pick notes") { let editor = page.descendants(matching: .any)["Pick editor"]; _ = tap("E", in: editor); _ = tap("G", in: editor); attach("13-harmony-\(tag)-8-pick-editor") }
            if tap("Close harmony") { attach("13-harmony-\(tag)-9-closed-again") }
        }
    }
}
