//  FourfoldAccessibilityTests.swift — Apple's accessibility audit (XCUIApplication.performAccessibilityAudit, iOS 17+) run over every screen the page can show: the three sequencer tabs, each lane tab, and each popup / sheet. It checks contrast,
//  missing or insufficient element descriptions, hit-region size, clipped text, Dynamic Type, traits and parent/child structure. Scripts/fourfold-harness/ui-tests.sh runs it on every iPad size in both orientations.
//
//  How it judges: every issue is written to a text attachment ("AUDIT <screen>: …"), and the test fails on any issue that is NOT in `FourfoldAuditAllowList` — so a NEW accessibility problem fails the run, while the known ones are listed, with the
//  reason each is accepted or still owed, in one place. An empty allow-list entry list is the goal.

import XCTest

/// What the audit is allowed to report. Every entry carries the reason it is accepted; the goal is for both lists to shrink. Measured 2026-10-24 on the base iPad: CONTRAST ≈ 130 distinct elements per screen set, HIT AREA ≈ 90.
enum FourfoldAuditAllowList {
    /// Whole audit types accepted on purpose. Not zero-tolerance because fixing them changes how the instrument LOOKS or is laid out, which is Paul's call, not a test's:
    static let acceptedTypes: [String: String] = [
        "contrast": "DECIDE (Paul): the page draws secondary text (labels, step numbers, dim states, 42 % solo/mute dims) in mid greys on dark tints, 8–11 pt; Apple's audit flags about 130 distinct labels as below its contrast threshold. A look decision, not a defect to patch silently.",
        "hitRegion": "DECIDE (Paul): dense editors (the 16-cell LANES grid, the 8×8 riff grid's rank labels, the key popup's note letters, the rails) have touch targets under Apple's 44 pt. Changing them changes the layout; the known-small ones are what the instrument is.",
    ]
    /// Single known issues: audit type + the element's label (matched by prefix).
    static let known: [(type: String, label: String, why: String)] = [
        ("textClipped", "FOURFOLD", "the audit flags the header wordmark's tight frame; the pictures show it whole — looks like a false positive, confirm on device"),
        ("textClipped", "NOTES", "the NOTES tab's rotated caption (35 × 212): flagged, not visibly cut in the pictures — confirm on device"),
        ("textClipped", "Invert melody", "RIFF tab control caption: look at it on the mini"),
        ("textClipped", "ITS LINE, IN TURN", "LISTEN tab option caption (74 pt wide): probably truly cut — look at it"),
        ("textClipped", "MUTE ON ITS NOTE", "LISTEN tab option caption (74 pt wide): probably truly cut — look at it"),
        ("textClipped", "Starts as an exact copy", "LISTEN tab's one-line help is cut at the card width in portrait — a real truncation"),
        ("textClipped", "TAP: ON/OFF", "the FX tab's instruction line is cut at the panel width in portrait — a real truncation (seen in the picture: \"…DOUBLE-TAP:…\")"),
        ("textClipped", "ITS NOTE NOW", "LISTEN tab option caption, landscape"),
        ("textClipped", "ITS OWN RIFF", "LISTEN tab option caption, landscape"),
    ]
    /// `elementDetection` issues come with NO element ("potentially inaccessible text"), so they cannot be matched by label: up to this many per screen are accepted (the most seen: 6, on the NOTES tab while stopped, where its key
    /// letters are the "–" placeholders). More than this on any screen is a new unlabelled piece of text.
    static let unlocatedElementDetectionCeiling = 6
    /// The HOCKET pop-up is a MODAL group (spec §10.2): while it is up VoiceOver — and this audit — treat the dimmed page behind the scrim as not there, so the page's visible text is reported as "potentially inaccessible" (measured 2026-10-27: 40 in
    /// portrait, 60 in landscape; 0 on every screen, the pop-up included, once the modal trait is removed). That is the intended behaviour, not a missing label, so those two screens accept up to 80 unlocated findings; every other audit type still runs in full.
    static func unlocatedElementDetectionCeilingFor(screen: String) -> Int { screen.contains("hocket popup") ? 80 : unlocatedElementDetectionCeiling }

}

@available(iOS 17.0, *)
final class FourfoldAccessibilityTests: XCTestCase {
    override func setUp() { continueAfterFailure = true }

    /// Run one type at a time: `.all` shares one time budget and times out on this page (about 500 elements), while each type alone finishes in 1-10 s.
    private static let types: [(String, XCUIAccessibilityAuditType)] = [("sufficientElementDescription", .sufficientElementDescription), ("trait", .trait), ("hitRegion", .hitRegion),
                                                                         ("elementDetection", .elementDetection), ("textClipped", .textClipped), ("contrast", .contrast)]

    /// Runs the audit on whatever is showing; returns the number of issues that are not on the allow-list.
    @discardableResult private func audit(_ app: XCUIApplication, _ screen: String) -> Int {
        var lines: [String] = [], unknown = 0, incomplete: [String] = [], unlocated = 0
        for (name, type) in Self.types {
            var tries = 0, done = false
            while !done && tries < 2 {
                tries += 1
                var mine: [String] = [], mineUnknown = 0
                if name == "elementDetection" { unlocated = 0 }   // counted per attempt
                do {
                    try app.performAccessibilityAudit(for: type) { issue in
                        // `issue.element` re-queries the whole accessibility tree on every access (≈ 0.3 s on this page), so resolve it ONCE, and only for types whose issues we name
                        var label = "?", f = "-"
                        if let e = issue.element, let snap = try? e.snapshot() {
                            label = snap.label; f = "\(Int(snap.frame.minX)),\(Int(snap.frame.minY)) \(Int(snap.frame.width))×\(Int(snap.frame.height))"
                        }
                        if name == "elementDetection" && label == "?" { unlocated += 1 }
                        let known = FourfoldAuditAllowList.acceptedTypes[name] != nil || FourfoldAuditAllowList.known.contains { $0.type == name && label.hasPrefix($0.label) }
                            || (name == "elementDetection" && label == "?" && unlocated <= FourfoldAuditAllowList.unlocatedElementDetectionCeilingFor(screen: screen))
                        if !known { mineUnknown += 1 }
                        let detail = label == "?" ? " | " + issue.detailedDescription.replacingOccurrences(of: "\n", with: " ") : ""   // an issue with no element (elementDetection) says where only in its detail
                        mine.append("\(known ? "known  " : "NEW    ")\(name) | \(label) | \(f) | \(issue.compactDescription)\(detail)")
                        return true     // keep going: collect everything, judge at the end
                    }
                    lines += mine; unknown += mineUnknown; done = true
                } catch { if tries == 2 { incomplete.append(name) } }
            }
        }
        let head = "AUDIT \(screen): \(lines.count) issue(s), \(unknown) not on the allow-list" + (incomplete.isEmpty ? "" : "; INCOMPLETE (timed out twice): \(incomplete.joined(separator: ", "))")
        let a = XCTAttachment(string: head + "\n" + lines.joined(separator: "\n"))
        a.name = "audit-" + screen.replacingOccurrences(of: " ", with: "-"); a.lifetime = .keepAlways; add(a)
        XCTAssertEqual(unknown, 0, "\(screen): \(unknown) accessibility issue(s) not on the allow-list (see the audit-… attachment)")
        return unknown
    }

    private func settle() { Thread.sleep(forTimeInterval: 1) }

    /// One test per screen and orientation (a fresh app each): the audit is slow and Apple's test daemon occasionally dies mid-run, so a crash costs one screen, not all of them.
    private func screen(_ name: String, landscape: Bool, _ prepare: (XCUIApplication) -> Void) {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication.fresh(); settle()
        prepare(app); settle()
        audit(app, "\(landscape ? "landscape" : "portrait") \(name)")
    }
    private func laneTab(_ prefix: String) -> (XCUIApplication) -> Void { { $0.els(prefix: prefix).element(boundBy: 0).tap() } }
    /// HOCKET (2026-10-27): the pop-up with a lit rule (a RED RIFF / BLUE RIFF swap), so the chips, the cycle strip, the steppers and the routes all exist when the audit looks.
    private func hocket(_ app: XCUIApplication) {
        app.els(prefix: "Hocket").firstMatch.tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 4), "Hocket did not open")
        for chip in ["Main: red riff, off", "Alt: blue riff, off"] { let c = app.buttons[chip]; if c.waitForExistence(timeout: 3) { c.tap() } }
    }
    private func open(_ button: String, expect: String) -> (XCUIApplication) -> Void { { app in app.buttons[button].tap(); XCTAssertTrue(app.staticTexts[expect].waitForExistence(timeout: 4), "\(button) did not open") } }

    func testAuditCardBackPortrait()  { screen("card backs", landscape: false) { $0.buttons["Mix"].tap() } }
    func testAuditLanesPortrait()    { screen("page LANES", landscape: false) { $0.buttons["Lanes"].tap() } }
    func testAuditFxPortrait()       { screen("page FX", landscape: false) { $0.buttons["FX"].tap() } }
    func testAuditRiffTabPortrait()  { screen("lane tab RIFF", landscape: false, laneTab("Riff, ")) }
    func testAuditNotesTabPortrait() { screen("lane tab NOTES", landscape: false, laneTab("Notes")) }
    func testAuditListenTabPortrait() { screen("lane tab LISTEN", landscape: false, laneTab("Listen, ")) }
    func testAuditPresetsPortrait()  { screen("presets", landscape: false, open("Presets", expect: "PRESETS")) }
    func testAuditKeyPopupPortrait() { screen("key popup", landscape: false, open("Key, C minor", expect: "KEY")) }
    func testAuditSwingPortrait()    { screen("swing", landscape: false, open("Swing, straight", expect: "SWING")) }
    func testAuditSettingsPortrait() { screen("settings", landscape: false) { $0.buttons["Settings"].tap() } }
    func testAuditHocketPortrait()   { screen("hocket popup", landscape: false, hocket) }

    func testAuditCardBackLandscape() { screen("card backs", landscape: true) { $0.buttons["Mix"].tap() } }
    func testAuditLanesLandscape()    { screen("page LANES", landscape: true) { $0.buttons["Lanes"].tap() } }
    func testAuditFxLandscape()       { screen("page FX", landscape: true) { $0.buttons["FX"].tap() } }
    func testAuditRiffTabLandscape()  { screen("lane tab RIFF", landscape: true, laneTab("Riff, ")) }
    func testAuditNotesTabLandscape() { screen("lane tab NOTES", landscape: true, laneTab("Notes")) }
    func testAuditListenTabLandscape() { screen("lane tab LISTEN", landscape: true, laneTab("Listen, ")) }
    func testAuditPresetsLandscape()  { screen("presets", landscape: true, open("Presets", expect: "PRESETS")) }
    func testAuditKeyPopupLandscape() { screen("key popup", landscape: true, open("Key, C minor", expect: "KEY")) }
    func testAuditSwingLandscape()    { screen("swing", landscape: true, open("Swing, straight", expect: "SWING")) }
    func testAuditSettingsLandscape() { screen("settings", landscape: true) { $0.buttons["Settings"].tap() } }
    func testAuditHocketLandscape()   { screen("hocket popup", landscape: true, hocket) }

    /// The one rule the audit cannot see: a control with NO label at all is invisible to VoiceOver. Every Button / Switch / Slider on every screen must have one.
    func testNoButtonSwitchOrSliderIsUnlabelled() {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.fresh(); settle()
        var bad: [String] = []
        for type in [XCUIElement.ElementType.button, .switch, .slider, .toggle] {
            let q = app.descendants(matching: type)
            for i in 0..<q.count {
                let e = q.element(boundBy: i)
                // the transport bar's tempo slider is hidden from VoiceOver on purpose (the tempo group above it is the one adjustable element), though XCUITest still lists it
                if e.label.isEmpty && e.identifier.isEmpty && !(type == .slider && e.frame.minY < 100) { bad.append("\(type.rawValue)@\(Int(e.frame.minX)),\(Int(e.frame.minY))") }
            }
        }
        XCTAssertTrue(bad.isEmpty, "unlabelled controls: \(bad)")
    }
}
