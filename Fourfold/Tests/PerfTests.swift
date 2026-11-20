//  PerfTests.swift — main-thread performance work (2026-11-20). Pure helpers behind the frame-rate relief valve etc.

import XCTest

final class PerfTests: XCTestCase {
    // P1: Reduce Motion clamps a TimelineView's frame rate to at most euclideousReduceMotionFPS; otherwise the base rate is kept.
    func testAnimIntervalRespectsReduceMotion() {
        // not reduce motion → untouched
        XCTAssertEqual(euclideousAnimInterval(1.0 / 60.0, reduceMotion: false), 1.0 / 60.0, accuracy: 1e-12)
        XCTAssertEqual(euclideousAnimInterval(1.0 / 30.0, reduceMotion: false), 1.0 / 30.0, accuracy: 1e-12)
        // reduce motion → 60/30 fps are clamped down to the 20 fps cap
        XCTAssertEqual(euclideousAnimInterval(1.0 / 60.0, reduceMotion: true), 1.0 / euclideousReduceMotionFPS, accuracy: 1e-12)
        XCTAssertEqual(euclideousAnimInterval(1.0 / 30.0, reduceMotion: true), 1.0 / euclideousReduceMotionFPS, accuracy: 1e-12)
        // already-slower animations keep their own (slower) interval even under reduce motion
        XCTAssertEqual(euclideousAnimInterval(1.0 / 4.0, reduceMotion: true), 1.0 / 4.0, accuracy: 1e-12)
        XCTAssertEqual(euclideousAnimInterval(1.0 / 15.0, reduceMotion: true), 1.0 / 15.0, accuracy: 1e-12)
        XCTAssertEqual(euclideousReduceMotionFPS, 20)
    }
}
