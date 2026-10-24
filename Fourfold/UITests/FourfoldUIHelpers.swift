//  FourfoldUIHelpers.swift — shared lookups for the Fourfold UI tests. The page has no accessibilityIdentifiers (and needs none): every control a VoiceOver user can reach carries a label, so the tests find things the way VoiceOver does,
//  by label — which also means a control that loses its label fails a test here.

import XCTest

extension XCUIApplication {
    /// The first element (any type) whose accessibility label is exactly `label`.
    func el(_ label: String) -> XCUIElement { descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch }
    /// Every element whose label starts with `prefix` (lane tabs: "Riff, ", "Notes, " …; four lanes → four matches, in lane order).
    func els(prefix: String) -> XCUIElementQuery { descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH %@", prefix)) }
    /// A fresh launch on the factory document (the app restores its last session otherwise).
    static func fresh(_ extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication(); app.launchArguments = ["--fresh"] + extra; app.launch()
        return app
    }
}

extension XCTestCase {
    /// Fails (with the label) unless the element shows up.
    @discardableResult func need(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        XCTAssertTrue(e.waitForExistence(timeout: timeout), "expected \(what) on screen", file: file, line: line)
        return e
    }
    func gone(_ e: XCUIElement, _ what: String, timeout: TimeInterval = 5, file: StaticString = #filePath, line: UInt = #line) {
        let end = Date().addingTimeInterval(timeout)
        while e.exists && Date() < end { Thread.sleep(forTimeInterval: 0.1) }
        XCTAssertFalse(e.exists, "expected \(what) to be gone", file: file, line: line)
    }
    func value(_ e: XCUIElement) -> String { (e.value as? String) ?? "\(e.value ?? "")" }
}
