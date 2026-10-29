//  FourfoldStackBudgetTests.swift — the stack budget of the page's eager build chain (Fourfold/Shared/FourfoldStackProbe.swift; crash `FourfoldAU-2026-10-25-213535.ips`).
//  The AU extension's main thread has 1,008 KB of stack, and what sits UNDER the page when it is rebuilt is not small: on the iPad the 2026-10-25 crash had a gesture handler plus SwiftUI's synchronous
//  re-render (≈ 320 KB) beneath a page build that needed ≈ 690 KB, in a Debug build. After `EuclideousStackBreak` the same walk reads well under the budget below; if a change re-nests the build (or one
//  tab gets much heavier) this fails in the simulator instead of crashing in AUM. Debug build (that is what UI tests run); only a sample at a few places on the deep chains, not a continuous watch —
//  so a NEW deep leaf should also call `FourfoldStackProbe.note()`.

import XCTest

final class FourfoldStackBudgetTests: XCTestCase {
    /// 1,008 KB of stack − ≈ 320 KB beneath the page on the device when a gesture triggers a rebuild (the crash) − a margin of ≈ 90 KB. Today's walk reads ≈ 350 KB; the structure before `EuclideousStackBreak` read 888 KB.
    static let budgetKB = 600

    override func setUp() { continueAfterFailure = false }

    private func deepest(_ app: XCUIApplication) -> Int {
        Thread.sleep(forTimeInterval: 0.6)
        let e = app.el("Stack probe")
        XCTAssertTrue(e.waitForExistence(timeout: 5), "the stack probe element")
        let v = value(e)                                         // "deepest=372 KB"
        return Int(v.replacingOccurrences(of: "deepest=", with: "").replacingOccurrences(of: " KB", with: "")) ?? -1
    }

    func testEveryTabOnEveryLaneStaysUnderTheStackBudgetInBothOrientations() {
        let app = XCUIApplication.fresh(["--stack-probe"])
        for orientation in [UIDeviceOrientation.landscapeLeft, .portrait] {
            XCUIDevice.shared.orientation = orientation
            Thread.sleep(forTimeInterval: 1.0)
            // TAB STRIP (2026-10-29): one tab for all four cards — each tab is built on every lane at once
            for tab in ["Riff, ", "Notes, ", "Listen, ", "Rhythm"] {
                let t = app.els(prefix: tab).firstMatch
                if t.waitForExistence(timeout: 3) { t.tap() }
            }
            for panel in ["Lanes", "FX", "Ratchet", "Mix", "Rhythm", "Mix", "Rhythm"] where app.buttons[panel].waitForExistence(timeout: 3) { app.buttons[panel].tap() }
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        Thread.sleep(forTimeInterval: 1.0)
        let hocket = app.els(prefix: "Hocket").firstMatch                    // HOCKET (2026-10-27): the pop-up with a lit rule is the deepest new build chain
        if hocket.waitForExistence(timeout: 3) {
            hocket.tap()
            for chip in ["Main: red riff, off", "Alt: blue riff, off"] { let c = app.buttons[chip]; if c.waitForExistence(timeout: 3) { c.tap() } }
            Thread.sleep(forTimeInterval: 0.6)
        }
        let kb = deepest(app)
        print("STACK PROBE deepest = \(kb) KB (budget \(Self.budgetKB) KB)")
        XCTAssertGreaterThan(kb, 0, "the probe saw nothing — is it wired?")
        XCTAssertLessThan(kb, Self.budgetKB, "the page's build chain reached \(kb) KB of main-thread stack; the extension has 1,008 KB and a rebuild under a gesture needs ≈ 320 KB beneath it. Put a `EuclideousStackBreak` around the heaviest new builder.")
    }
}
