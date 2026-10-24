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
            ("5-settings-main-out", { $0.buttons["Settings"].tap(); $0.buttons["MAIN OUT"].tap() }),
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
