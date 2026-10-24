//  FourfoldMonkeyTests.swift — a seeded random-input test of the REAL app (2026-10-24): hundreds of random taps, drags and rotations at random places on the page (popups, sheets and the transport included), and the app must still be running and
//  responsive at the end. No assertion about WHAT happens — only that nothing it is asked can kill it. Same seed → same inputs, so a crash reproduces. Scripts/fourfold-harness/ui-tests.sh runs it on every iPad size.

import XCTest

private struct SplitMix: RandomNumberGenerator {
    var s: UInt64
    mutating func next() -> UInt64 { s &+= 0x9E3779B97F4A7C15; var z = s; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; return z ^ (z >> 31) }
}

final class FourfoldMonkeyTests: XCTestCase {
    override func setUp() { continueAfterFailure = false }

    private func monkey(seed: UInt64, actions: Int, rotate: Bool) {
        XCUIDevice.shared.orientation = .portrait
        let app = XCUIApplication.fresh(["--autoplay"])
        var rng = SplitMix(s: seed)
        func pt(_ r: inout SplitMix) -> CGVector { CGVector(dx: Double.random(in: 0.01...0.99, using: &r), dy: Double.random(in: 0.02...0.99, using: &r)) }
        let orientations: [UIDeviceOrientation] = [.portrait, .landscapeLeft, .portraitUpsideDown, .landscapeRight]
        var log: [String] = []
        for i in 0..<actions {
            let kind = Int.random(in: 0..<100, using: &rng)
            let a = pt(&rng)
            if kind < 62 { app.coordinate(withNormalizedOffset: a).tap(); log.append("tap \(a)") }
            else if kind < 72 { app.coordinate(withNormalizedOffset: a).doubleTap(); log.append("double \(a)") }
            else if kind < 94 { let b = pt(&rng); app.coordinate(withNormalizedOffset: a).press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: b)); log.append("drag \(a)→\(b)") }
            else if kind < 98 { app.coordinate(withNormalizedOffset: a).press(forDuration: 0.6); log.append("hold \(a)") }
            else if rotate { let o = orientations[Int.random(in: 0..<4, using: &rng)]; XCUIDevice.shared.orientation = o; log.append("rotate \(o.rawValue)"); Thread.sleep(forTimeInterval: 0.8) }
            if app.state != .runningForeground {
                let t = XCTAttachment(string: log.suffix(40).joined(separator: "\n")); t.name = "last-actions"; t.lifetime = .keepAlways; add(t)
                XCTFail("the app is no longer running after action \(i) (seed \(seed)); the last actions are attached"); return
            }
        }
        XCUIDevice.shared.orientation = .portrait
        Thread.sleep(forTimeInterval: 1)
        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["Play"].exists || app.buttons["Stop"].exists, "the transport bar should still be there after \(actions) random inputs")
        let t = XCTAttachment(string: log.joined(separator: "\n")); t.name = "actions-seed-\(seed)"; t.lifetime = .keepAlways; add(t)
    }

    func testFiveHundredRandomInputsInPortrait() { monkey(seed: 1, actions: 500, rotate: false) }
    func testFourHundredRandomInputsWithRotations() { monkey(seed: 2, actions: 400, rotate: true) }
}
