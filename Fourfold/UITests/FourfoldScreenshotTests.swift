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
            ("5-mix", { _ in }), ("5-lanes", { $0.buttons["Lanes"].tap() }), ("5-fx", { $0.buttons["FX"].tap() }),
            ("5-lane-riff", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff, '")).element(boundBy: 0).tap() }),
            ("5-lane-notes", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notes'")).element(boundBy: 0).tap() }),
            ("5-lane-listen", { $0.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Listen, '")).element(boundBy: 0).tap() }),
            ("5-presets", { $0.buttons["Presets"].tap() }), ("5-key", { $0.buttons["Key, C minor"].tap() }), ("5-swing", { $0.buttons["Swing, straight"].tap() }),
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

    /// TAB STRIP (2026-10-29): the one strip above the lane cards on each tab (the glyph clusters, the selected segment), MIX, then random mode and lock mode with their faces at the shorter cards — landscape.
    func testTheLaneStripAndTheModes() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        Thread.sleep(forTimeInterval: 2)
        func step(_ el: XCUIElement) { if el.waitForExistence(timeout: 3) { el.tap() } }
        attach("9-strip-1-rhythm")
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("9-strip-2-riff")
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notes, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("9-strip-3-notes")
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Listen, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("9-strip-4-listen")
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
        step(app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Listen, '")).firstMatch); Thread.sleep(forTimeInterval: 1); attach("10-canon-row-landscape")
        step(app.buttons["Settings"]); step(app.buttons["CLOCK"]); Thread.sleep(forTimeInterval: 1); attach("10-canon-entry-clock-tab")
        XCUIDevice.shared.orientation = .portrait
    }

    /// CARD BACKS (2026-10-28): the four lane cards on their BACK (the strip's MIX segment), playing, in every orientation — the picture the ferry's §14 acceptance is judged against — then with the riff routed to A and C and
    /// the notes part switched off (an unplugged jack, a part off with its invitation, the roll dimmed).
    /// POLY RIFF (2026-10-29): the MONO | POLY control and the sixteen-column grid — MONO first (the control in the boxes' row), then POLY seeded from it, then a few notes added, one stretched, one removed — in portrait and landscape.
    func testThePolyRiffGrid() {
        let app = XCUIApplication()
        app.launchArguments = ["--fresh", "--autoplay"]
        app.launch()
        for (name, o) in [("1-portrait", UIDeviceOrientation.portrait), ("2-landscape", .landscapeLeft)] {
            XCUIDevice.shared.orientation = o
            Thread.sleep(forTimeInterval: 2)
            app.buttons["Mono"].tap(); Thread.sleep(forTimeInterval: 0.6); attach("poly-\(name)-a-mono")
            app.buttons["Poly"].tap(); Thread.sleep(forTimeInterval: 0.8); attach("poly-\(name)-b-seeded")
            func cell(_ step: Int, _ row: Int) -> XCUIElement { app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", "Step \(step),")).element(boundBy: row) }
            cell(2, 0).press(forDuration: 0.1, thenDragTo: cell(7, 0))          // rank 8: a long note, steps 2…7
            cell(10, 3).press(forDuration: 0.1, thenDragTo: cell(14, 3))        // rank 5: steps 10…14
            cell(1, 1).tap()                                                    // rank 7: a single note under the first
            cell(3, 5).tap()                                                    // a seeded note taken away
            Thread.sleep(forTimeInterval: 1.2); attach("poly-\(name)-c-edited")
        }
        XCUIDevice.shared.orientation = .portrait
    }

    func testTheCardBacks() {
        let app = XCUIApplication(); app.launchArguments = ["--fresh", "--autoplay"]; app.launch()
        let device = XCUIDevice.shared
        device.orientation = .portrait
        Thread.sleep(forTimeInterval: 1.5)
        let mix = app.buttons["Mix"]
        if mix.waitForExistence(timeout: 5) { mix.tap() }
        for (name, o) in [("8-back-1-portrait", UIDeviceOrientation.portrait), ("8-back-2-landscape-left", .landscapeLeft), ("8-back-3-portrait-upside-down", .portraitUpsideDown), ("8-back-4-landscape-right", .landscapeRight)] {
            device.orientation = o
            Thread.sleep(forTimeInterval: 3)
            attach(name)
        }
        device.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.5)
        let jacks = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff to output C'"))
        if jacks.count > 0 { jacks.element(boundBy: 0).tap() }
        let pitch = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Riff pitch'"))      // CARD BACKS v2: the riff's PITCH pad away from home (the away rectangle, the lane-coloured dot)
        if pitch.count > 0 { pitch.element(boundBy: 0).coordinate(withNormalizedOffset: CGVector(dx: 0.78, dy: 0.2)).tap() }
        let notesToggle = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notes, on'"))
        if notesToggle.count > 0 { notesToggle.element(boundBy: 0).tap() }
        Thread.sleep(forTimeInterval: 2)
        attach("8-back-5-routed-and-off")
        app.buttons["Rhythm"].tap(); Thread.sleep(forTimeInterval: 1.5)
        attach("8-back-6-flipped-back")
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
}
