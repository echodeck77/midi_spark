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

    /// CARD BACKS (2026-10-28): the four lane cards on their BACK (the header's MIX segment), playing, in every orientation — the picture the ferry's §14 acceptance is judged against — then with the riff routed to A and C and
    /// the notes part switched off (an unplugged jack, a part off with its invitation, the roll dimmed).
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
        let notesToggle = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Notes, on'"))
        if notesToggle.count > 0 { notesToggle.element(boundBy: 0).tap() }
        Thread.sleep(forTimeInterval: 2)
        attach("8-back-5-routed-and-off")
        app.buttons["Pattern"].tap(); Thread.sleep(forTimeInterval: 1.5)
        attach("8-back-6-flipped-back")
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
