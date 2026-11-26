//  DrumCardV2Tests.swift — DRUM CARD V2 ferry (2026-11-26): the pure functions (§7.1 note names, §7.2 scrub, §7.8 bars).

import XCTest
import CoreGraphics

final class DrumCardV2Tests: XCTestCase {

    // §7.1 — note names (§2.1): the ferry's convention IS euclideousNoteViewName (sharps, C4=60).
    func testNoteNames() {
        func nm(_ n: UInt8) -> String { euclideousNoteViewName(n, flatKey: false) }
        XCTAssertEqual(nm(0), "C-1")
        XCTAssertEqual(nm(36), "C2")
        XCTAssertEqual(nm(48), "C3")
        XCTAssertEqual(nm(56), "G\u{266F}3")   // source's convention: the ♯ glyph, not ASCII "#" (§2.1 "use source's convention")
        XCTAssertEqual(nm(60), "C4")
        XCTAssertEqual(nm(127), "G9")
    }

    // §7.2 — scrub maths: start + round(travel/12), clamped 0–127; up raises (startY − y > 0).
    func testScrubMaths() {
        // no travel ⇒ the start note
        XCTAssertEqual(euclideousDrumScrubNote(startNote: 56, startY: 100, y: 100), 56)
        // up 12 pt ⇒ +1; up 18 ⇒ +2 (rounds); up 6 ⇒ +1 (rounds to the nearest, .5 up)
        XCTAssertEqual(euclideousDrumScrubNote(startNote: 56, startY: 100, y: 88), 57)
        XCTAssertEqual(euclideousDrumScrubNote(startNote: 56, startY: 100, y: 82), 58)   // 18/12 = 1.5 → 2
        XCTAssertEqual(euclideousDrumScrubNote(startNote: 56, startY: 100, y: 94), 57)   // 6/12 = 0.5 → 1
        XCTAssertEqual(euclideousDrumScrubNote(startNote: 56, startY: 100, y: 95), 56)   // 5/12 → 0
        // down lowers
        XCTAssertEqual(euclideousDrumScrubNote(startNote: 56, startY: 100, y: 124), 54)  // down 24 → −2
        // clamps at the ends
        XCTAssertEqual(euclideousDrumScrubNote(startNote: 2, startY: 100, y: 400), 0)    // way down
        XCTAssertEqual(euclideousDrumScrubNote(startNote: 125, startY: 100, y: -400), 127)   // way up
    }

    // §7.8 — the VEL bars (euclideousDrumRampVel): 40–100 UP, DOWN, and equal low/high.
    func testRampBars() {
        let up = (1...8).map { euclideousDrumRampVel(rank: $0, low: 40, high: 100, ramp: .up) }
        XCTAssertEqual(up.first, 40); XCTAssertEqual(up.last, 100)
        XCTAssertEqual(up, up.sorted(), "UP ramps low→high")
        let down = (1...8).map { euclideousDrumRampVel(rank: $0, low: 40, high: 100, ramp: .down) }
        XCTAssertEqual(down.first, 100); XCTAssertEqual(down.last, 40)
        XCTAssertEqual(down, up.reversed(), "DOWN mirrors UP")
        let flat = (1...8).map { euclideousDrumRampVel(rank: $0, low: 70, high: 70, ramp: .up) }
        XCTAssertEqual(flat, Array(repeating: 70, count: 8), "equal low/high ⇒ flat")
    }
}
